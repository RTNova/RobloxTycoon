--[[
	BuffManager.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ServerScriptService > Modules > BuffManager   (ModuleScript)

	RESPONSABILIDAD:
		Recorrer TODOS los nodos del Skill Tree que un jugador tiene
		desbloqueados, sumar sus efectos por tipo, y cachear el resultado
		en memoria para que ButtonService, EggService y PetInventoryManager
		puedan leerlo instantáneamente (una lectura O(1) de tabla) cada vez
		que lo necesiten, sin recorrer `UnlockedSkills` en cada compra,
		cada eclosión o cada intento de equipar.

	CUÁNDO SE RECALCULA:
		- Al cargar el perfil del jugador (para restaurar sus buffos de
		  sesiones anteriores).
		- Cada vez que desbloquea un nodo nuevo (ver SkillTreeService.lua).

	--------------------------------------------------------------------
	LA MATEMÁTICA: los nodos se agrupan por `EffectType` y sus
	`EffectValue` se SUMAN dentro de cada grupo. Un jugador con
	`Discount_1` (0.05) y `Discount_2` (0.05) desbloqueados tiene un
	`ButtonDiscount` total de 0.10 (10%) — el resto de sistemas
	(ButtonService, EggService, PetInventoryManager) solo necesitan leer
	ese número final ya combinado, sin saber nada de nodos individuales.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SkillTreeConfig = require(ReplicatedStorage.Modules.SkillTreeConfig)

local BuffManager = {}

-- Techo de seguridad: un botón NUNCA debe poder costar 0 o negativo, por
-- muchos nodos de descuento que el jugador acumule a lo largo de varios
-- Rebirths. 0.9 dejaría, como mínimo, un 10% del precio original.
local MAX_BUTTON_DISCOUNT = 0.9

-- Caché en memoria: [player] = { ButtonDiscount, EggLuckBoost, MaxEquippedBoost }
local cache = {}

-- Recalcula y cachea los tres totales de un jugador a partir de sus nodos
-- desbloqueados. DataManager se inyecta como parámetro (mismo patrón que
-- MultiplierManager) para evitar dependencias circulares entre módulos.
function BuffManager.Recalculate(player: Player, DataManager)
	local totals = {
		ButtonDiscount = 0,
		EggLuckBoost = 0,
		MaxEquippedBoost = 0,
	}

	for nodeId in pairs(DataManager.GetUnlockedSkills(player)) do
		local node = SkillTreeConfig.Get(nodeId)
		if node then
			totals[node.EffectType] = (totals[node.EffectType] or 0) + node.EffectValue
		else
			warn("[BuffManager] Nodo desconocido en UnlockedSkills: " .. tostring(nodeId))
		end
	end

	totals.ButtonDiscount = math.min(totals.ButtonDiscount, MAX_BUTTON_DISCOUNT)

	cache[player] = totals
	return totals
end

-- Lecturas O(1) usadas por ButtonService, EggService y PetInventoryManager.
-- Si la caché del jugador aún no existe (recalculo inicial en curso), el
-- valor seguro por defecto es 0 en los tres casos: nunca aplicar un buffo
-- "por si acaso" antes de haberlo calculado de verdad.

function BuffManager.GetButtonDiscount(player: Player): number
	local totals = cache[player]
	return totals and totals.ButtonDiscount or 0
end

function BuffManager.GetExtraLuckRolls(player: Player): number
	local totals = cache[player]
	return totals and totals.EggLuckBoost or 0
end

function BuffManager.GetMaxEquippedBonus(player: Player): number
	local totals = cache[player]
	return totals and totals.MaxEquippedBoost or 0
end

function BuffManager.ClearCache(player: Player)
	cache[player] = nil
end

return BuffManager
