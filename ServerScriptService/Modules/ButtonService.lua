--[[
	ButtonService.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ServerScriptService > Modules > ButtonService  (ModuleScript)

	FILOSOFÍA "SERVER-AUTHORITATIVE":
		El cliente NUNCA decide si una compra es válida. El único evento
		que usamos es BasePart.Touched, que se dispara igual en el
		servidor sin necesidad de que el cliente "avise" con un RemoteEvent.
		Esto hace imposible que un exploiter pueda comprar algo gratis,
		porque toda la lógica (comprobar precio, restar dinero, revelar
		piezas, guardar) vive 100% en el servidor.

	CONVENCIÓN DE DISEÑO EN STUDIO (así el sistema es escalable sin tocar
	código cada vez que añades un botón nuevo):

		Tycoon1 (Model)
		└── Buttons (Folder)
		    └── Button1 (Part)                     <- Ladrillo que se toca
		        [Atributos en la pestaña "Attributes" del Part]:
		            Cost      (number)  = 100
		            ButtonId  (string)  = "Button1"   <- ÚNICO dentro del tycoon
		        └── Stuff (Folder)                  <- Todo lo que se revela
		            ├── Wall1 (Part)                 <- Empieza Transparency=1, CanCollide=false
		            ├── Generator1 [Tag: "IncomeGenerator"] <- Ver IncomeManager (Attribute: MoneyPerSecond)
		            └── Decoracion1 (Model)

		IMPORTANTE sobre "Stuff": cada Part/Model dentro de esa carpeta debe
		empezar OCULTO (Transparency = 1, CanCollide = false). El script
		guarda el estado "original" (CanCollide que debería tener al
		revelarse) leyendo el atributo "OriginalCanCollide" si existe, o
		asumiendo `true` por defecto para las Parts. "Generator1" no
		necesita ser una BasePart: es solo un marcador de datos (ver
		ActivateGenerators más abajo), así que puede ser, por ejemplo, una
		Configuration sin representación visual, o una Part decorativa que
		además lleve el Tag "IncomeGenerator".

	FLUJO DE COMPRA:
		1. Jugador toca el Part "Button1".
		2. Identificamos qué jugador es y a qué tycoon pertenece ese botón.
		3. Comprobamos que sea SU tycoon (nadie compra en el tycoon ajeno).
		4. Comprobamos que no esté ya comprado (persistencia).
		5. Aplicamos el descuento del Skill Tree (BuffManager.GetButtonDiscount)
		   y intentamos descontar el dinero vía DataManager.TrySpendMoney.
		6. Si hay saldo: revelamos "Stuff", ACTIVAMOS cualquier generador
		   de ingresos que contenga (IncomeManager), marcamos comprado,
		   guardamos, y destruimos/ocultamos el propio botón para que no
		   se pueda volver a tocar.

	REBIRTH: si un botón es el ÚLTIMO de la progresión del tycoon, márcalo
	en Studio con el Attribute `IsFinalButton = true` (además de sus
	Attributes normales `Cost`/`ButtonId`) — así lo encuentra
	`TycoonManager:Rebirth` para comprobar si el jugador puede renacer.
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local ButtonService = {}

local BUTTON_TAG = "TycoonButton"
local GENERATOR_TAG = "IncomeGenerator"

-- Revela todo el contenido de la carpeta "Stuff" asociada a un botón.
local function RevealStuff(stuffFolder: Instance)
	for _, item in ipairs(stuffFolder:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Transparency = item:GetAttribute("RevealedTransparency") or 0
			item.CanCollide = item:GetAttribute("RevealedCanCollide")
			if item:GetAttribute("RevealedCanCollide") == nil then
				item.CanCollide = true
			end
		end
	end
end

-- Activa cualquier generador de ingresos ("IncomeGenerator") que haya
-- dentro de la carpeta "Stuff" de este botón. Recorremos solo los
-- descendientes de ESTE botón (no todo el juego), así que es barato incluso
-- con muchos generadores totales en el mapa.
local function ActivateGenerators(stuffFolder: Instance, IncomeManager, TycoonManager)
	for _, item in ipairs(stuffFolder:GetDescendants()) do
		if CollectionService:HasTag(item, GENERATOR_TAG) then
			IncomeManager.ActivateGenerator(item, TycoonManager)
		end
	end
end

-- Oculta visualmente el botón ya usado (más barato que destruirlo si quieres
-- poder depurar en Studio; puedes cambiar esto por item:Destroy() si prefieres).
local function DisableButton(buttonPart: BasePart)
	buttonPart.Transparency = 1
	buttonPart.CanCollide = false
	buttonPart.CanTouch = false
end

-- Inversa de RevealStuff: vuelve a ocultar todo lo que había revelado
-- este botón. La usa ResetTycoonToBase (Rebirth) para dejar el tycoon
-- como si nunca se hubiera comprado nada.
local function HideStuff(stuffFolder: Instance)
	for _, item in ipairs(stuffFolder:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Transparency = 1
			item.CanCollide = false
		end
	end
end

-- Inversa de ActivateGenerators: borra el Attribute "_IncomeActivated" de
-- cada generador para que, al volver a comprarse el botón tras un
-- Rebirth, IncomeManager.ActivateGenerator pueda activarlo de nuevo desde
-- cero (si no borráramos este Attribute, ActivateGenerator lo ignoraría
-- por creer que ya estaba activo).
local function DeactivateGenerators(stuffFolder: Instance)
	for _, item in ipairs(stuffFolder:GetDescendants()) do
		if CollectionService:HasTag(item, GENERATOR_TAG) then
			item:SetAttribute("_IncomeActivated", nil)
		end
	end
end

-- Inversa de DisableButton: vuelve a dejar el botón visible y tocable,
-- listo para comprarse otra vez.
local function EnableButton(buttonPart: BasePart)
	buttonPart.Transparency = 0
	buttonPart.CanCollide = true
	buttonPart.CanTouch = true
end

-- Restaura visualmente, SIN cobrar, un botón que el jugador ya había
-- comprado en una sesión anterior. Se llama justo cuando el jugador
-- reclama su tycoon (ver Main.server.lua). También reactiva la tasa de
-- ingresos de sus generadores (IncomeManager cachea por tycoon, así que
-- hay que "recalentar" la caché al reclamar).
function ButtonService.RestorePurchasedButtons(player: Player, tycoonModel: Model, DataManager, IncomeManager, TycoonManager)
	local buttonsFolder = tycoonModel:FindFirstChild("Buttons")
	if not buttonsFolder then return end

	for _, buttonPart in ipairs(buttonsFolder:GetChildren()) do
		local buttonId = buttonPart:GetAttribute("ButtonId")
		if not buttonId then continue end

		if DataManager.HasPurchasedButton(player, buttonId) then
			local stuffFolder = buttonPart:FindFirstChild("Stuff")
			if stuffFolder then
				RevealStuff(stuffFolder)
				ActivateGenerators(stuffFolder, IncomeManager, TycoonManager)
			end
			DisableButton(buttonPart)
		end
	end
end

-- ========================================================================
-- REBIRTH: revierte TODO un tycoon a su estado "recién construido", como
-- si nunca se hubiera comprado ningún botón. La llama
-- TycoonManager:Rebirth tras resetear Money/PurchasedButtons en DataManager.
-- ========================================================================
function ButtonService.ResetTycoonToBase(tycoonModel: Model, IncomeManager)
	local buttonsFolder = tycoonModel:FindFirstChild("Buttons")
	if not buttonsFolder then return end

	for _, buttonPart in ipairs(buttonsFolder:GetChildren()) do
		local stuffFolder = buttonPart:FindFirstChild("Stuff")
		if stuffFolder then
			HideStuff(stuffFolder)
			DeactivateGenerators(stuffFolder)
		end
		EnableButton(buttonPart)
	end

	-- La tasa de ingresos cacheada de ESTE tycoon vuelve a 0: todos sus
	-- generadores se acaban de desactivar, así que ya no debería aportar nada.
	IncomeManager.ResetTycoonRate(tycoonModel)
end

-- Conecta el evento Touched de TODOS los botones del juego (usa
-- CollectionService para no tener que recorrer manualmente cada tycoon).
-- Requiere que cada Part-botón tenga el Tag "TycoonButton" puesto en Studio
-- (pestaña "Tags", o vía script en Main.server.lua al generar el mapa).
function ButtonService.Init(DataManager, TycoonManager, IncomeManager, BuffManager)
	for _, buttonPart in ipairs(CollectionService:GetTagged(BUTTON_TAG)) do
		ButtonService._ConnectButton(buttonPart, DataManager, TycoonManager, IncomeManager, BuffManager)
	end

	-- Por si añades botones dinámicamente más adelante (opcional pero recomendado).
	CollectionService:GetInstanceAddedSignal(BUTTON_TAG):Connect(function(buttonPart)
		ButtonService._ConnectButton(buttonPart, DataManager, TycoonManager, IncomeManager, BuffManager)
	end)
end

function ButtonService._ConnectButton(buttonPart: BasePart, DataManager, TycoonManager, IncomeManager, BuffManager)
	local debounce = false

	buttonPart.Touched:Connect(function(hit)
		if debounce then return end

		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then return end

		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end

		debounce = true
		ButtonService._HandlePurchase(player, buttonPart, DataManager, TycoonManager, IncomeManager, BuffManager)
		task.wait(0.25) -- pequeño respiro para evitar múltiples triggers del mismo frame
		debounce = false
	end)
end

function ButtonService._HandlePurchase(player: Player, buttonPart: BasePart, DataManager, TycoonManager, IncomeManager, BuffManager)
	local tycoonModel = buttonPart:FindFirstAncestorOfClass("Model")
	if not tycoonModel then return end

	-- 1) El botón solo se puede comprar en TU PROPIO tycoon.
	local owner = TycoonManager.GetOwnerOf(tycoonModel)
	if owner ~= player then return end

	local buttonId = buttonPart:GetAttribute("ButtonId")
	local baseCost = buttonPart:GetAttribute("Cost")

	if not buttonId or not baseCost then
		warn("[ButtonService] Falta el atributo ButtonId o Cost en: " .. buttonPart:GetFullName())
		return
	end

	-- 2) Evitar recompras si por lo que sea el botón sigue tocable.
	if DataManager.HasPurchasedButton(player, buttonId) then
		return
	end

	-- 3) Aplicamos el descuento del Skill Tree (rama "Regateo") ANTES de
	--    cobrar: BuffManager.GetButtonDiscount ya viene acotado a un
	--    máximo seguro (ver BuffManager.lua), así que nunca da un coste
	--    negativo ni gratis. math.floor para no cobrar decimales sueltos.
	local discount = BuffManager.GetButtonDiscount(player)
	local finalCost = math.floor(baseCost * (1 - discount))

	-- 4) Único punto donde se gasta dinero: validación 100% en servidor.
	local success = DataManager.TrySpendMoney(player, finalCost)
	if not success then
		-- Dinero insuficiente: aquí podrías disparar un RemoteEvent opcional
		-- para mostrar un mensaje "Necesitas X$" en la UI del cliente.
		return
	end

	-- 5) Compra válida: revelar piezas, activar generadores de ingresos,
	--    marcar como comprado y desactivar botón.
	local stuffFolder = buttonPart:FindFirstChild("Stuff")
	if stuffFolder then
		RevealStuff(stuffFolder)
		ActivateGenerators(stuffFolder, IncomeManager, TycoonManager)
	end

	DataManager.MarkButtonPurchased(player, buttonId)
	DisableButton(buttonPart)

	-- No hace falta llamar a un "Save" explícito: ProfileService guarda
	-- automáticamente los datos en memoria (profile.Data) de forma periódica
	-- y al salir del juego. Como MarkButtonPurchased edita profile.Data
	-- directamente, el progreso ya está "guardado" en cuanto ProfileService
	-- haga su siguiente autosave o cuando el jugador salga.
end

return ButtonService
