--[[
	Main.server.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ServerScriptService > Main   (Script, NO ModuleScript)

	Este es el ÚNICO script que se ejecuta solo. Todo lo demás son
	ModuleScripts (librerías) que este script "orquesta". Esto mantiene
	el código organizado, testeable, y evita el caos de tener lógica
	repartida en 10 Scripts sueltos.
--]]

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ServerScriptService:WaitForChild("Modules")

local DataManager = require(Modules.DataManager)
local TycoonManager = require(Modules.TycoonManager)
local ButtonService = require(Modules.ButtonService)
local IncomeManager = require(Modules.IncomeManager)
local SkinController = require(Modules.SkinController)
local EggService = require(Modules.EggService)
local PetInventoryManager = require(Modules.PetInventoryManager)
local MultiplierManager = require(Modules.MultiplierManager)
local InventoryService = require(Modules.InventoryService)
local GamepassManager = require(Modules.GamepassManager)
local DevProductHandler = require(Modules.DevProductHandler)
local PetCloneService = require(Modules.PetCloneService)
local DevProductConfig = require(ReplicatedStorage.Modules.DevProductConfig)
local BuffManager = require(Modules.BuffManager)
local SkillTreeService = require(Modules.SkillTreeService)
local RebirthService = require(Modules.RebirthService)

-- 1) Arrancamos los servicios que solo necesitan configurarse UNA vez.
ButtonService.Init(DataManager, TycoonManager, IncomeManager, BuffManager)
IncomeManager.Init(DataManager, MultiplierManager, TycoonManager)
SkinController.Init(DataManager, TycoonManager)
InventoryService.Init(DataManager)
EggService.Init(DataManager, InventoryService, GamepassManager, BuffManager)
PetInventoryManager.Init(DataManager, MultiplierManager, InventoryService, GamepassManager, BuffManager)
GamepassManager.Init(DataManager, MultiplierManager)
PetCloneService.Init(DataManager)
SkillTreeService.Init(DataManager, BuffManager)

-- 1.1) Rebirth: TycoonManager.Init inyecta las dependencias que
-- TycoonManager:Rebirth(player) necesita internamente, para poder usar la
-- firma corta de un solo parámetro. RebirthService es solo el puente
-- fino entre el RemoteEvent del cliente y esa llamada.
TycoonManager.Init(DataManager, ButtonService, IncomeManager)
RebirthService.Init(TycoonManager)

-- 1.2) Monetización con Robux: DevProductHandler es el ÚNICO punto que
-- asigna MarketplaceService.ProcessReceipt (Roblox solo permite un
-- callback activo para todo el juego). Los paquetes de monedas se
-- registran automáticamente desde DevProductConfig; la clonación registra
-- su propio handler porque necesita leer PendingClone, no solo sumar dinero.
DevProductHandler.RegisterMoneyPacks(DataManager)
DevProductHandler.RegisterHandler(
	DevProductConfig.Get("PetCloneFee").Id,
	function(player, receiptInfo)
		return PetCloneService.GrantClone(player, receiptInfo, DataManager, InventoryService)
	end
)
DevProductHandler.Init(DataManager)

-- 2) Cuando un jugador reclama un tycoon (ver TycoonManager.SetupClaimPads),
--    cargamos sus datos (si no estaban ya), aplicamos su skin del Núcleo
--    guardada y restauramos visualmente su progreso (botones + generadores).
TycoonManager.SetupClaimPads(function(player, tycoonModel)
	-- Esperamos a que el profile ya esté cargado (PlayerAdded corre en paralelo).
	while DataManager.GetData(player) == nil do
		task.wait(0.1)
	end

	SkinController.ApplySavedSkin(player, tycoonModel, DataManager)
	ButtonService.RestorePurchasedButtons(player, tycoonModel, DataManager, IncomeManager, TycoonManager)
end)

-- Carga completa de un jugador: perfil + Gamepasses (VIP/x2Luck/+1 Equip)
-- + buffos del Skill Tree + multiplicador inicial de mascotas ya
-- equipadas en sesiones anteriores (para que el Núcleo empiece a
-- acumular con el bonus correcto, incluido el de VIP si lo posee, desde
-- el primer segundo).
local function OnPlayerAdded(player: Player)
	DataManager.LoadProfile(player)

	-- Esperamos a que el profile termine de cargar antes de calcular el
	-- multiplicador (LoadProfile puede tardar por la llamada al DataStore).
	while player:IsDescendantOf(Players) and DataManager.GetData(player) == nil do
		task.wait(0.1)
	end

	if DataManager.GetData(player) == nil then
		return -- El jugador salió antes de que su perfil terminara de cargar.
	end

	-- Los buffos del Skill Tree se calculan al instante (no dependen de
	-- ninguna llamada de red externa, a diferencia de los Gamepasses).
	BuffManager.Recalculate(player, DataManager)

	-- La verificación de Gamepasses puede tardar unos segundos (reintentos
	-- de red incluidos): la lanzamos en paralelo para no bloquear el resto
	-- de la carga del jugador.
	task.spawn(function()
		GamepassManager.LoadForPlayer(player)
		-- Recalculamos DESPUÉS de tener los Gamepasses listos, para que el
		-- bono VIP (si aplica) quede incluido desde el primer cálculo.
		if DataManager.GetData(player) ~= nil then
			MultiplierManager.Recalculate(player, DataManager, GamepassManager)
		end
	end)
end

-- 3) Ciclo de vida del jugador: cargar datos al entrar, liberar al salir.
Players.PlayerAdded:Connect(OnPlayerAdded)

Players.PlayerRemoving:Connect(function(player)
	TycoonManager.ReleaseTycoon(player)
	DataManager.ReleaseProfile(player)
	MultiplierManager.ClearCache(player)
	GamepassManager.ClearCache(player)
	BuffManager.ClearCache(player)
end)

-- Por si el script se inicia después de que algún jugador ya esté en el
-- servidor (poco común, pero es una buena práctica defensiva).
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(OnPlayerAdded, player)
end
