--[[
	MultiplierManager.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ServerScriptService > Modules > MultiplierManager   (ModuleScript)

	RESPONSABILIDAD:
		Calcular el multiplicador de dinero total de un jugador según las
		mascotas que tiene EQUIPADAS ahora mismo, y mantenerlo cacheado en
		memoria para que IncomeManager pueda leerlo instantáneamente cada
		vez que el jugador recoge una moneda (sin recalcular ni recorrer
		el inventario entero en cada recolección, que sería caro si el
		jugador tiene cientos de mascotas).

	FÓRMULA ELEGIDA (aditiva sobre la base 1x):
		Multiplicador total = 1 + Σ (Total_mascota - 1) + BonoVIP (si aplica)

		Donde "Total_mascota" ya incluye el desglose completo calculado por
		PetManager:CalculatePetPower (BaseMultiplier de la especie +
		VariantBonus de la variante con la que salió esa copia concreta), y
		"BonoVIP" es GamepassConfig.VIP_MULTIPLIER_BONUS si el jugador
		posee el Gamepass VIP (ver GamepassManager) — un bono FIJO y
		permanente, independiente de qué mascotas tenga equipadas.

		Ejemplo: equipar un Zorro Normal (Total 1.4x) y un Dragón Dorado
		(BaseMultiplier 2.5 + VariantBonus 2 = Total 4.5x), siendo VIP:
			1 + (1.4 - 1) + (4.5 - 1) + 0.5 = 5.4x

	CUÁNDO SE RECALCULA:
		- Al cargar el perfil del jugador (para restaurar el multiplicador
		  de mascotas ya equipadas en sesiones anteriores).
		- Cada vez que el jugador equipa/desequipa una mascota
		  (ver PetInventoryManager.lua).
		- Al comprar el Gamepass VIP en mitad de la partida (ver
		  GamepassManager.Init, para que el bono se note al instante).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PetManager = require(ReplicatedStorage.Modules.PetManager)
local GamepassConfig = require(ReplicatedStorage.Modules.GamepassConfig)

local MultiplierManager = {}

-- Caché en memoria: [player] = multiplicador numérico ya calculado.
local cache = {}

-- Recalcula y actualiza la caché de un jugador. DataManager y
-- GamepassManager se inyectan como parámetros (en vez de hacer require
-- aquí) para evitar dependencias circulares entre módulos.
function MultiplierManager.Recalculate(player: Player, DataManager, GamepassManager)
	local equippedPets = DataManager.GetEquippedPets(player)

	local total = 1
	for _, petData in ipairs(equippedPets) do
		local power = PetManager.CalculatePetPower(petData)
		total += (power.Total - 1)
	end

	if GamepassManager and GamepassManager.HasGamepass(player, "VIP") then
		total += GamepassConfig.VIP_MULTIPLIER_BONUS
	end

	cache[player] = total
	return total
end

-- Lectura RÁPIDA usada por IncomeManager en cada tick de su bucle principal.
-- Si por lo que sea aún no se ha calculado (jugador recién entrado),
-- devolvemos 1 (sin bonus) como valor seguro por defecto.
function MultiplierManager.GetMultiplier(player: Player): number
	return cache[player] or 1
end

function MultiplierManager.ClearCache(player: Player)
	cache[player] = nil
end

return MultiplierManager
