--[[
	GamepassManager.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ServerScriptService > Modules > GamepassManager   (ModuleScript)

	RESPONSABILIDAD:
		- Al entrar cada jugador, consultar (con reintentos) si posee cada
		  uno de los Gamepasses clave (`VIP`, `x2Luck`, `PlusOneEquip`) y
		  guardar el resultado en una CACHÉ EN MEMORIA por sesión (no en
		  el DataStore: la propiedad de un Gamepass la gestiona Roblox,
		  no nosotros — nunca la persistimos nosotros mismos).
		- Escuchar `MarketplaceService.PromptGamePassPurchaseFinished`
		  para refrescar la caché AL INSTANTE si el jugador compra un
		  Gamepass en mitad de la partida, sin que tenga que reconectar.
		- Exponer `GamepassManager.HasGamepass(player, key)`, una lectura
		  O(1) que usan EggService (x2Luck), PetInventoryManager (+1 Equip)
		  y MultiplierManager (VIP) sin volver a llamar a la API de
		  Roblox en cada eclosión/equipar/tick de ingresos.

	POR QUÉ "VARIABLES DE SESIÓN" Y NO DATASTORE:
		`UserOwnsGamePassAsync` es la fuente de verdad — consultarla es
		barato y NUNCA puede desincronizarse (a diferencia de guardar
		nosotros mismos "tiene VIP: true/false" en el perfil, que sí
		podría quedar desactualizado si el jugador reembolsa el gamepass,
		por ejemplo). La caché en memoria es solo para no golpear esa API
		en cada acción del jugador dentro de la MISMA sesión.
--]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GamepassConfig = require(ReplicatedStorage.Modules.GamepassConfig)

local GamepassManager = {}

-- Caché en memoria: [player] = { VIP = bool, x2Luck = bool, PlusOneEquip = bool }
local ownedCache = {}

-- Reintenta hasta 3 veces con backoff creciente: `UserOwnsGamePassAsync`
-- puede fallar por un corte de red puntual o un límite de tasa de la API,
-- y NO queremos denegarle a un jugador VIP legítimo su beneficio solo
-- porque la primera consulta falló.
local function CheckOwnership(player: Player, gamepassKey: string): boolean
	local def = GamepassConfig.Get(gamepassKey)
	if not def then
		warn("[GamepassManager] Gamepass desconocido: " .. tostring(gamepassKey))
		return false
	end

	for attempt = 1, 3 do
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.Id)
		end)

		if ok then
			return owns
		end

		task.wait(attempt) -- Backoff: 1s, 2s, 3s
	end

	warn(("[GamepassManager] No se pudo verificar '%s' para %s tras 3 intentos."):format(gamepassKey, player.Name))
	return false
end

-- Consulta y cachea los TRES gamepasses de golpe. Llamar en Players.PlayerAdded
-- (idealmente en una corrutina aparte, ya que puede tardar unos segundos si
-- hay que reintentar alguna consulta).
function GamepassManager.LoadForPlayer(player: Player)
	local status = {}

	for key in pairs(GamepassConfig.Gamepasses) do
		status[key] = CheckOwnership(player, key)
	end

	ownedCache[player] = status
end

-- Lectura O(1) usada por EggService, PetInventoryManager y MultiplierManager.
-- Si por lo que sea la caché del jugador aún no existe (consulta inicial
-- todavía en curso), devolvemos `false` como valor seguro por defecto:
-- nunca aplicamos un beneficio premium "por si acaso".
function GamepassManager.HasGamepass(player: Player, key: string): boolean
	local status = ownedCache[player]
	return status ~= nil and status[key] == true
end

function GamepassManager.ClearCache(player: Player)
	ownedCache[player] = nil
end

-- Punto de entrada: escucha compras de Gamepass EN VIVO, durante la sesión.
-- Recibe DataManager y MultiplierManager para poder recalcular AL INSTANTE
-- el multiplicador del jugador si lo que acaba de comprar es VIP (los
-- otros dos gamepasses no afectan a ningún valor cacheado aparte, así que
-- no necesitan un recálculo inmediato: EggService y PetInventoryManager ya
-- consultan HasGamepass en tiempo real la próxima vez que se usan).
function GamepassManager.Init(DataManager, MultiplierManager)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamepassId, wasPurchased)
		if not wasPurchased then return end

		for key, def in pairs(GamepassConfig.Gamepasses) do
			if def.Id == gamepassId then
				if not ownedCache[player] then
					ownedCache[player] = {}
				end
				ownedCache[player][key] = true

				if key == "VIP" then
					MultiplierManager.Recalculate(player, DataManager, GamepassManager)
				end

				break
			end
		end
	end)
end

return GamepassManager
