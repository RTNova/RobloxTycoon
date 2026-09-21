--[[
	EggService.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ServerScriptService > Modules > EggService   (ModuleScript)

	FLUJO COMPLETO (y por qué es seguro):

		Cliente                          Servidor
		--------                         --------
		Toca/pulsa un huevo
		  → Dispara RemoteEvent
		    "RequestOpenEgg" con
		    SOLO el EggId (string)  ---->  1. Verifica que el EggId exista en EggsConfig.
		                                   2. Verifica cooldown/debounce anti-spam.
		                                   3. DataManager.TrySpendMoney(cost).
		                                      Si no hay saldo → aborta, no pasa nada más.
		                                   4. WeightedRNG.RollWithValidation(pool, TotalWeight)
		                                      → PetId ganador (escala de hasta 10,000,000
		                                      para soportar Míticas 0.009% / Secretas 0.001%).
		                                   5. PetManager.RollVariant() → Normal/Shiny/Dorado
		                                      (tirada independiente de la especie).
		                                   6. DataManager.AddPet(player, PetId, Variant) →
		                                      UUID nuevo, con OriginalOwnerName/Id grabados
		                                      de forma permanente.
		                                   7. Dispara RemoteEvent "EggResult" DE VUELTA
		                                      al cliente con { PetId, Variant, UUID } para
		                                      que la UI muestre la animación de apertura.
		                                   8. InventoryService.NotifyChanged(player) para
		                                      que InventoryController refresque el grid.

	¿Por qué es imposible "darse mascotas gratis"?
		- El cliente nunca envía qué mascota quiere ni cuánto dinero tiene:
		  solo dice "quiero abrir Egg_Basic". TODO lo demás (coste, saldo,
		  resultado del RNG) lo decide y ejecuta el servidor.
		- Aunque un exploiter dispare el RemoteEvent 1000 veces por segundo,
		  cada intento pasa individualmente por TrySpendMoney: si no hay
		  saldo, simplemente no ocurre nada. El debounce (paso 2) además
		  evita que sature el servidor de peticiones.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EggsConfig = require(ReplicatedStorage.Modules.EggsConfig)
local WeightedRNG = require(ReplicatedStorage.Modules.WeightedRNG)
local PetManager = require(ReplicatedStorage.Modules.PetManager)
local PetsConfig = require(ReplicatedStorage.Modules.PetsConfig)

local EggService = {}

-- Cooldown mínimo entre aperturas de huevo por jugador, para evitar spam
-- de RemoteEvents (protección adicional además de TrySpendMoney).
local OPEN_COOLDOWN = 0.3
local lastOpenAt = {} -- [player] = tick()

-- ========================================================================
-- SUERTE (GAMEPASS "x2 LUCK" + SKILL TREE "Suerte del Cazador") —
-- implementación GENÉRICA "tira N veces, quédate con la mejor" en vez de
-- duplicar los pesos del pool.
--
-- Por qué este diseño y no "multiplicar por 2 el peso de las mascotas
-- raras": tocar los pesos del pool obligaría a mantener varias tablas de
-- probabilidad por huevo (una por cada combinación posible de bonus) o a
-- recalcular TotalWeight sobre la marcha, con más riesgo de descuadres.
-- Tirando N veces y quedándonos con el resultado de mayor rareza
-- obtenemos el mismo efecto ("más probabilidad efectiva de sacar algo
-- raro") reutilizando exactamente el mismo WeightedRNG y el mismo pool,
-- sin tocar ni un número de EggsConfig — y las dos fuentes de suerte
-- (Gamepass + Skill Tree) se combinan solo SUMANDO tiradas extra.
-- ========================================================================
local function PickRarerEntry(entryA, entryB)
	local defA = PetsConfig.Get(entryA.PetId)
	local defB = PetsConfig.Get(entryB.PetId)

	local rankA = defA and PetsConfig.RarityOrder[defA.Rarity] or 0
	local rankB = defB and PetsConfig.RarityOrder[defB.Rarity] or 0

	return (rankB > rankA) and entryB or entryA
end

function EggService.Init(DataManager, InventoryService, GamepassManager, BuffManager)
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	local requestOpenEgg = remotesFolder:WaitForChild("RequestOpenEgg") -- RemoteEvent
	local eggResult = remotesFolder:WaitForChild("EggResult") -- RemoteEvent

	requestOpenEgg.OnServerEvent:Connect(function(player, eggId)
		-- Validación de TIPO: nunca confíes en que el cliente mande lo que
		-- "debería" mandar. Si no es un string, lo descartamos sin más.
		if typeof(eggId) ~= "string" then return end

		-- Anti-spam: si el jugador abrió un huevo hace menos de OPEN_COOLDOWN
		-- segundos, ignoramos la petición.
		local now = os.clock()
		if lastOpenAt[player] and (now - lastOpenAt[player]) < OPEN_COOLDOWN then
			return
		end
		lastOpenAt[player] = now

		local eggDef = EggsConfig.Get(eggId)
		if not eggDef then
			warn(("[EggService] %s intentó abrir un huevo inexistente: %s"):format(player.Name, tostring(eggId)))
			return
		end

		-- Único punto de gasto: si no hay dinero suficiente, TrySpendMoney
		-- devuelve false y NO seguimos (no se genera mascota, no se cobra).
		local paid = DataManager.TrySpendMoney(player, eggDef.Cost)
		if not paid then
			return
		end

		-- Cálculo del resultado 100% en servidor: primero la ESPECIE...
		local winningEntry = WeightedRNG.RollWithValidation(eggDef.Pool, eggDef.TotalWeight)
		if not winningEntry then
			-- Pool mal configurado: devolvemos el dinero para no perjudicar al jugador.
			DataManager.AddMoney(player, eggDef.Cost)
			warn("[EggService] Pool vacío o inválido para: " .. eggId)
			return
		end

		-- Tiradas EXTRA: 1 por el Gamepass "x2 Luck" (si lo tiene) + N por
		-- los nodos "Suerte del Cazador" desbloqueados en el Skill Tree
		-- (BuffManager.GetExtraLuckRolls ya viene sumado de todas sus ramas).
		-- Cada tirada extra es 100% independiente y justa; solo nos
		-- quedamos con la de mayor rareza de TODAS las realizadas.
		local extraRolls = BuffManager.GetExtraLuckRolls(player)
		if GamepassManager.HasGamepass(player, "x2Luck") then
			extraRolls += 1
		end

		for _ = 1, extraRolls do
			local extraRoll = WeightedRNG.Roll(eggDef.Pool)
			if extraRoll then
				winningEntry = PickRarerEntry(winningEntry, extraRoll)
			end
		end

		-- ...y después, en una tirada COMPLETAMENTE INDEPENDIENTE, la VARIANTE
		-- (Normal / Shiny / Dorado). Cualquier especie puede salir en cualquier
		-- variante: son dos sistemas de probabilidad desacoplados.
		local variant = PetManager.RollVariant()

		local uuid = DataManager.AddPet(player, winningEntry.PetId, variant)

		-- Avisamos al cliente qué le tocó, para que anime la apertura del huevo.
		eggResult:FireClient(player, {
			EggId = eggId,
			PetId = winningEntry.PetId,
			Variant = variant,
			UUID = uuid,
		})

		-- Avisamos también a InventoryController (UI) de que su inventario
		-- cambió, para que vuelva a pedirlo y la tarjeta nueva aparezca en
		-- el grid sin que el jugador tenga que reabrir el menú.
		InventoryService.NotifyChanged(player)
	end)
end

return EggService
