--[[
	IncomeManager.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ServerScriptService > Modules > IncomeManager   (ModuleScript)

	SUSTITUYE a DropperService.lua (eliminado): ya no se generan partes
	físicas de dinero. En su lugar, cada generador comprado aporta una
	tasa de "Dinero Por Segundo" (MoneyPerSecond) que se suma de forma
	abstracta al "Dinero Pendiente" del Núcleo Central del jugador.

	--------------------------------------------------------------------
	POR QUÉ ESTE DISEÑO ES "CERO LAG":

		1. CERO PARTES FÍSICAS: no hay Parts cayendo, sin colisiones que
		   calcular, sin límite de "monedas simultáneas" que vigilar.
		2. UN ÚNICO BUCLE PARA TODO EL SERVIDOR: en vez de una conexión
		   RunService.Heartbeat POR JUGADOR (que con 50 jugadores serían
		   50 callbacks ejecutándose 30-60 veces por segundo cada uno),
		   usamos UNA sola corrutina que se despierta cada
		   `INCOME_UPDATE_INTERVAL` segundos (por defecto 1) y recorre la
		   lista de jugadores una vez. Con un tycoon-game típico esto es
		   una operación trivial incluso con cientos de jugadores.
		3. TASA CACHEADA POR TYCOON: la suma de "MoneyPerSecond" de todos
		   los generadores de un tycoon se calcula UNA VEZ, cuando se
		   compra o se restaura cada generador (ver `RegisterGeneratorRate`),
		   nunca recorriendo el árbol de instancias en cada tick.

	CONVENCIÓN DE DISEÑO EN STUDIO:

		Tycoon1
		└── Buttons/Button1/Stuff/Generator1  (Instance cualquiera, p.ej. Configuration)
		        [Tag]: "IncomeGenerator"
		        [Attribute]: MoneyPerSecond (number) = 10

	El "Generator" NO necesita ser una BasePart: es solo un marcador de
	datos. Si quieres representarlo visualmente (una máquina, una granja),
	puedes seguir metiendo Parts normales en "Stuff" para que ButtonService
	las revele con Transparency/CanCollide como siempre; el marcador
	"IncomeGenerator" es un objeto aparte, exclusivamente para la tasa.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local CoreConfig = require(ReplicatedStorage.Modules.CoreConfig)

local IncomeManager = {}

local CORE_COLLECTOR_TAG = "CoreCollector"

-- Caché: [tycoonModel] = suma de MoneyPerSecond de todos sus generadores
-- YA ACTIVADOS (comprados). Sin multiplicar por mascotas: eso se aplica
-- en el momento de repartir, no aquí, para que un cambio de equipo de
-- mascotas no requiera recalcular esta caché.
local baseRateByTycoon = {}

-- ========================================================================
-- ACTIVACIÓN DE GENERADORES (llamado por ButtonService al comprar/restaurar)
-- ========================================================================
function IncomeManager.ActivateGenerator(generatorInstance: Instance, TycoonManager)
	-- Idempotente: si ButtonService restaura el mismo botón dos veces (no
	-- debería pasar, pero por seguridad), no duplicamos la tasa.
	if generatorInstance:GetAttribute("_IncomeActivated") then return end
	generatorInstance:SetAttribute("_IncomeActivated", true)

	local tycoonModel = TycoonManager.FindTycoonRoot(generatorInstance)
	if not tycoonModel then
		warn("[IncomeManager] Generador fuera de un tycoon válido: " .. generatorInstance:GetFullName())
		return
	end

	local rate = generatorInstance:GetAttribute("MoneyPerSecond") or 0
	baseRateByTycoon[tycoonModel] = (baseRateByTycoon[tycoonModel] or 0) + rate
end

-- Lectura usada por el bucle principal (y disponible para UI/depuración).
function IncomeManager.GetBaseRate(tycoonModel: Model): number
	return baseRateByTycoon[tycoonModel] or 0
end

-- Pone a 0 la tasa cacheada de un tycoon completo. La usa
-- ButtonService.ResetTycoonToBase durante un Rebirth: como TODOS los
-- generadores del tycoon se desactivan a la vez, es más simple y más
-- barato resetear el acumulado de golpe que ir restando uno a uno.
function IncomeManager.ResetTycoonRate(tycoonModel: Model)
	baseRateByTycoon[tycoonModel] = 0
end

-- ========================================================================
-- RECOLECCIÓN: tocar el CoreBody transfiere el Dinero Pendiente a Money.
-- Se conecta vía CollectionService, así que funciona automáticamente con
-- CUALQUIER skin (SkinController etiqueta el CoreBody nuevo cada vez que
-- se clona, sea cual sea el prefab).
-- ========================================================================
local function ConnectCollector(coreBodyPart: BasePart, DataManager, TycoonManager)
	if coreBodyPart:GetAttribute("_CollectorConnected") then return end
	coreBodyPart:SetAttribute("_CollectorConnected", true)

	local debounce = false

	coreBodyPart.Touched:Connect(function(hit)
		if debounce then return end

		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then return end

		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end

		local tycoonModel = TycoonManager.FindTycoonRoot(coreBodyPart)
		if not tycoonModel then return end

		-- Solo el DUEÑO de este tycoon puede recolectar de SU propio Núcleo.
		if TycoonManager.GetOwnerOf(tycoonModel) ~= player then return end

		debounce = true
		DataManager.CollectPendingMoney(player)
		task.wait(0.3)
		debounce = false
	end)
end

-- ========================================================================
-- PUNTO DE ENTRADA
-- ========================================================================
function IncomeManager.Init(DataManager, MultiplierManager, TycoonManager)
	-- Conectamos el/los CoreBody ya presentes (por si el mapa se construyó
	-- con un skin por defecto ya colocado a mano) y los que se etiqueten
	-- más adelante (cada vez que SkinController clona un Núcleo nuevo).
	for _, part in ipairs(CollectionService:GetTagged(CORE_COLLECTOR_TAG)) do
		ConnectCollector(part, DataManager, TycoonManager)
	end

	CollectionService:GetInstanceAddedSignal(CORE_COLLECTOR_TAG):Connect(function(part)
		ConnectCollector(part, DataManager, TycoonManager)
	end)

	-- ====================================================================
	-- BUCLE PRINCIPAL: UNA sola corrutina para TODOS los jugadores.
	-- ====================================================================
	task.spawn(function()
		while true do
			task.wait(CoreConfig.INCOME_UPDATE_INTERVAL)

			for _, player in ipairs(Players:GetPlayers()) do
				local tycoonModel = TycoonManager.GetTycoonOf(player)
				if not tycoonModel then continue end

				local baseRate = IncomeManager.GetBaseRate(tycoonModel)
				if baseRate <= 0 then continue end -- Nada que generar: no tocamos sus datos.

				local multiplier = MultiplierManager.GetMultiplier(player)
				local finalRate = baseRate * multiplier -- Dinero/segundo YA con el bono de mascotas.
				local amountThisTick = finalRate * CoreConfig.INCOME_UPDATE_INTERVAL

				DataManager.AddPendingMoney(player, amountThisTick, finalRate)
			end
		end
	end)
end

return IncomeManager
