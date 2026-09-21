--[[
	PetManager.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ReplicatedStorage > Modules > PetManager   (ModuleScript)

	Por qué en ReplicatedStorage y no en ServerScriptService: las dos
	funciones de este módulo son PURAS (mismo input → mismo output, sin
	tocar dinero, DataStore ni estado global), así que tanto el servidor
	(EggService, MultiplierManager) como el cliente (UI de inventario, que
	necesita mostrar "Base +40% · Shiny +50% · Total +90%") pueden usarlas
	sin duplicar la fórmula en dos sitios.

	Esto NO abre ningún agujero de seguridad: un cliente podría llamar a
	PetManager:CalculatePetPower() con datos inventados para "verse a sí
	mismo" un resultado falso en su propia pantalla, pero eso no cambia
	nada en el servidor — el servidor jamás confía en un cálculo que le
	llegue del cliente, siempre usa su propia copia de profile.Data.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PetsConfig = require(ReplicatedStorage.Modules.PetsConfig)
local WeightedRNG = require(ReplicatedStorage.Modules.WeightedRNG)

export type PetPowerBreakdown = {
	BaseMultiplier: number,  -- Multiplicador de la especie en su versión Normal
	VariantBonus: number,    -- Bonus adicional aportado por la variante (Shiny, Dorado...)
	Total: number,           -- BaseMultiplier + VariantBonus: lo que usa MultiplierManager
}

local PetManager = {}

-- ========================================================================
-- 1) DESGLOSE DE MULTIPLICADORES
-- ========================================================================
-- petData: la entrada tal cual se guarda en profile.Data.Pets[uuid], es
-- decir, como mínimo necesita los campos { PetId: string, Variant: string }.
--
-- Devuelve un diccionario con el Valor Base, el bonus de variante y el
-- Total final, para que la UI pueda mostrarlos por separado.
function PetManager.CalculatePetPower(petData: { PetId: string, Variant: string? }): PetPowerBreakdown
	local petDef = PetsConfig.Get(petData.PetId)
	if not petDef then
		warn("[PetManager] PetId desconocido: " .. tostring(petData.PetId))
		return { BaseMultiplier = 1, VariantBonus = 0, Total = 1 }
	end

	-- Si la mascota no tiene variante guardada (dato antiguo o corrupto),
	-- asumimos "Normal" como fallback seguro (bonus 0).
	local variantDef = PetsConfig.GetVariant(petData.Variant or "Normal")
	local variantBonus = variantDef and variantDef.VariantBonus or 0

	return {
		BaseMultiplier = petDef.BaseMultiplier,
		VariantBonus = variantBonus,
		Total = petDef.BaseMultiplier + variantBonus,
	}
end

-- ========================================================================
-- 2) ROLL DE VARIANTE (parte del proceso de eclosión)
-- ========================================================================
-- Tirada INDEPENDIENTE de qué especie te tocó: toda mascota, sea Común o
-- Secreta, pasa por esta misma tirada para decidir si sale Normal, Shiny
-- o Dorada. Se apoya en el mismo WeightedRNG genérico.
--
-- SEGURIDAD: aunque este módulo esté en ReplicatedStorage, la llamada que
-- CUENTA (la que decide la variante real que se guarda en el inventario
-- del jugador) solo se ejecuta dentro de EggService.lua, en el servidor,
-- en el mismo momento en que ya se validó y descontó el dinero.
function PetManager.RollVariant(): string
	local pool = {}
	for variantId, variantDef in pairs(PetsConfig.Variants) do
		table.insert(pool, { VariantId = variantId, Weight = variantDef.Weight })
	end

	local winner = WeightedRNG.Roll(pool)
	if not winner then
		return "Normal" -- Fallback seguro: nunca dejar una mascota sin variante.
	end

	return winner.VariantId
end

return PetManager
