--[[
	TycoonManager.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ServerScriptService > Modules > TycoonManager  (ModuleScript)

	RESPONSABILIDAD:
		- Mantener la relación entre un jugador y su plot/tycoon físico
		  en Workspace (Workspace.Tycoons.Tycoon1, Tycoon2, ...).
		- Gestionar la reclamación del tycoon (tocar el "ClaimPad").
		- Restaurar visualmente el progreso guardado cuando el jugador
		  reclama su tycoon (botones ya comprados en sesiones anteriores).

	ESTRUCTURA ESPERADA EN WORKSPACE:
		Workspace
		└── Tycoons (Folder)
		    ├── Tycoon1 (Model)
		    │   ├── ClaimPad (Part)        <- Tocar para reclamar el plot
		    │   ├── Buttons (Folder)       <- Botones de compra (ver ButtonService)
		    │   ├── CoreAnchor (Part)      <- Marca DÓNDE va el Núcleo Central (ver SkinController)
		    │   └── Core (Model)           <- Clonado en runtime por SkinController; no lo crees a mano
		    ├── Tycoon2 (Model)
		    └── ...

	NOTA: el antiguo "Collector" (Part) de la versión con droppers físicos
	ya no es necesario: el Núcleo Central actúa como único punto de
	recolección (ver IncomeManager.lua y SkinController.lua).

	--------------------------------------------------------------------
	ACTUALIZACIÓN — REBIRTH (RENACIMIENTO):

	`TycoonManager:Rebirth(player)` verifica que el jugador haya comprado
	el ÚLTIMO botón de su tycoon (marcado en Studio con el Attribute
	`IsFinalButton = true` sobre esa Part concreta — ver `FindFinalButtonId`
	más abajo), y si es así: suma 1 Punto de Renacimiento, resetea
	ÚNICAMENTE Money y PurchasedButtons (nunca las mascotas ni ningún otro
	dato), y recarga el tycoon a su estado visual base.

	`TycoonManager.Init(DataManager, ButtonService, IncomeManager)` debe
	llamarse UNA vez desde Main.server.lua antes de que cualquier jugador
	pueda renacer — guarda esas tres dependencias como variables internas
	para que `Rebirth` pueda usarlas con la firma corta `(player)`.
--]]

local TycoonManager = {}

-- Relaciones en memoria (no se guardan en DataStore, se reconstruyen en runtime)
TycoonManager.OwnerByTycoon = {} -- [tycoonModel] = player
TycoonManager.TycoonByPlayer = {} -- [player] = tycoonModel

local Workspace = game:GetService("Workspace")
local TycoonsFolder = Workspace:WaitForChild("Tycoons")

-- Dependencias inyectadas UNA vez vía TycoonManager.Init, para que
-- `Rebirth(player)` pueda usarlas sin tener que recibirlas en cada
-- llamada (mismo espíritu que la firma pedida: un método corto y limpio).
local _DataManager
local _ButtonService
local _IncomeManager

function TycoonManager.Init(DataManager, ButtonService, IncomeManager)
	_DataManager = DataManager
	_ButtonService = ButtonService
	_IncomeManager = IncomeManager
end

-- Devuelve el primer tycoon libre (sin dueño), o nil si todos están ocupados.
local function GetFreeTycoon()
	for _, tycoonModel in ipairs(TycoonsFolder:GetChildren()) do
		if TycoonManager.OwnerByTycoon[tycoonModel] == nil then
			return tycoonModel
		end
	end
	return nil
end

-- Asigna un tycoon concreto a un jugador y actualiza un atributo visual
-- (útil para pintar un cartel con el nombre del dueño, por ejemplo).
function TycoonManager.AssignTycoon(player: Player, tycoonModel: Model)
	TycoonManager.OwnerByTycoon[tycoonModel] = player
	TycoonManager.TycoonByPlayer[player] = tycoonModel
	tycoonModel:SetAttribute("OwnerUserId", player.UserId)
end

-- Libera el tycoon cuando el jugador sale (para que otro pueda usarlo).
function TycoonManager.ReleaseTycoon(player: Player)
	local tycoonModel = TycoonManager.TycoonByPlayer[player]
	if tycoonModel then
		TycoonManager.OwnerByTycoon[tycoonModel] = nil
		tycoonModel:SetAttribute("OwnerUserId", nil)
	end
	TycoonManager.TycoonByPlayer[player] = nil
end

function TycoonManager.GetTycoonOf(player: Player): Model?
	return TycoonManager.TycoonByPlayer[player]
end

function TycoonManager.GetOwnerOf(tycoonModel: Model): Player?
	return TycoonManager.OwnerByTycoon[tycoonModel]
end

-- Sube por la jerarquía desde CUALQUIER instancia (una parte del Núcleo,
-- un generador, un botón...) hasta encontrar el Model que es hijo directo
-- de Workspace.Tycoons. La usan IncomeManager y SkinController para saber
-- "¿de qué tycoon es esta pieza?" sin tener que recibirlo como parámetro
-- explícito en cada llamada.
function TycoonManager.FindTycoonRoot(instance: Instance): Model?
	local current = instance
	while current and current.Parent ~= TycoonsFolder do
		current = current.Parent
	end
	return current
end

-- Busca, dentro de la carpeta "Buttons" de un tycoon, la Part marcada con
-- el Attribute `IsFinalButton = true` en Studio (el último botón de esa
-- rama de progresión) y devuelve su ButtonId. `nil` si el tycoon no tiene
-- ninguno marcado (Rebirth no estará disponible hasta que lo configures).
local function FindFinalButtonId(tycoonModel: Model): string?
	local buttonsFolder = tycoonModel:FindFirstChild("Buttons")
	if not buttonsFolder then return nil end

	for _, buttonPart in ipairs(buttonsFolder:GetChildren()) do
		if buttonPart:GetAttribute("IsFinalButton") == true then
			return buttonPart:GetAttribute("ButtonId")
		end
	end

	return nil
end

-- ========================================================================
-- REBIRTH (RENACIMIENTO)
-- ========================================================================
-- Devuelve (true) si renació con éxito, o (false, razón) si no pudo.
-- Usa sintaxis de método (`:`) tal y como se pidió; `self` es el propio
-- módulo TycoonManager (se llama como `TycoonManager:Rebirth(player)`).
function TycoonManager:Rebirth(player: Player): (boolean, string?)
	local tycoonModel = self.TycoonByPlayer[player]
	if not tycoonModel then
		return false, "No tienes un tycoon reclamado."
	end

	local finalButtonId = FindFinalButtonId(tycoonModel)
	if not finalButtonId then
		warn("[TycoonManager] " .. tycoonModel.Name .. " no tiene ningún botón con el Attribute IsFinalButton.")
		return false, "Este tycoon no tiene un Rebirth configurado todavía."
	end

	-- ÚNICA condición para poder renacer: haber comprado el botón final.
	if not _DataManager.HasPurchasedButton(player, finalButtonId) then
		return false, "Debes comprar todos los botones de tu tycoon antes de renacer."
	end

	-- 1) Sumar Puntos de Renacimiento. Las mascotas NUNCA se tocan en este
	--    flujo — ni se leen ni se escriben — así que quedan intactas por
	--    el simple hecho de no estar incluidas en el reset del paso 2.
	_DataManager.AddRebirthPoints(player, 1)

	-- 2) Reset SEGURO y SELECTIVO: SOLO Money y PurchasedButtons.
	_DataManager.ResetForRebirth(player)

	-- 3) Recargar el tycoon a su estado visual base: todos los botones
	--    vuelven a ser tocables, todo lo que revelaban queda oculto de
	--    nuevo, y la tasa de ingresos de IncomeManager para ESTE tycoon
	--    vuelve a 0 (los generadores tendrán que comprarse otra vez).
	_ButtonService.ResetTycoonToBase(tycoonModel, _IncomeManager)

	return true
end

-- Conecta el ClaimPad de cada tycoon libre para que, al ser tocado por un
-- jugador sin tycoon asignado todavía, se le asigne ese plot.
function TycoonManager.SetupClaimPads(onClaimed: (Player, Model) -> ())
	for _, tycoonModel in ipairs(TycoonsFolder:GetChildren()) do
		local claimPad = tycoonModel:FindFirstChild("ClaimPad")
		if not claimPad then continue end

		local debounce = false

		claimPad.Touched:Connect(function(hit)
			if debounce then return end

			local character = hit:FindFirstAncestorOfClass("Model")
			if not character then return end

			local player = game:GetService("Players"):GetPlayerFromCharacter(character)
			if not player then return end

			-- El jugador ya tiene un tycoon: ignoramos.
			if TycoonManager.TycoonByPlayer[player] ~= nil then return end

			-- Este tycoon ya tiene dueño: ignoramos.
			if TycoonManager.OwnerByTycoon[tycoonModel] ~= nil then return end

			debounce = true
			TycoonManager.AssignTycoon(player, tycoonModel)
			onClaimed(player, tycoonModel)
			debounce = false
		end)
	end
end

return TycoonManager
