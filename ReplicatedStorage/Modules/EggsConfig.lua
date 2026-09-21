--[[
	EggsConfig.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ReplicatedStorage > Modules > EggsConfig   (ModuleScript)

	Define cada huevo: su coste y su "pool" de mascotas posibles con un
	PESO relativo. La probabilidad real de cada mascota = su Weight /
	TotalWeight del huevo (WeightedRNG lo calcula en runtime).

	--------------------------------------------------------------------
	ACTUALIZACIÓN — RNG Hardcore a gran escala:

	Para poder representar probabilidades EXTREMADAMENTE bajas (0.009%,
	0.001%) sin depender de decimales flotantes, ya NO trabajamos sobre
	una escala de 100. Trabajamos sobre una escala de 10,000,000 (diez
	millones), que es una potencia de 10 grande y cómoda de razonar:

		1 de peso en 10,000,000  =  0.0000001  =  0.00001%
		100 de peso en 10,000,000  =  0.00001 = 0.001%   ← Secreta
		900 de peso en 10,000,000  =  0.00009 = 0.009%   ← Mítica

	Con math.random() operando sobre ENTEROS en vez de floats, evitamos
	los errores de redondeo que sí aparecerían si intentases representar
	"0.009%" como 0.00009 en punto flotante y compararlo contra un roll
	decimal. Ver WeightedRNG.lua para el algoritmo exacto.
--]]

export type EggPoolEntry = {
	PetId: string,
	Weight: number,
}

export type EggDefinition = {
	Id: string,
	Name: string,
	Cost: number,
	TotalWeight: number, -- Debe coincidir EXACTAMENTE con la suma de Weight del Pool
	Pool: { EggPoolEntry },
}

local Eggs: { [string]: EggDefinition } = {
	Egg_Basic = {
		Id = "Egg_Basic",
		Name = "Huevo Básico",
		Cost = 100,
		TotalWeight = 100,
		Pool = {
			{ PetId = "Pet_Cat", Weight = 60 },    -- 60 / 100 = 60%
			{ PetId = "Pet_Rabbit", Weight = 30 }, -- 30 / 100 = 30%
			{ PetId = "Pet_Fox", Weight = 10 },    -- 10 / 100 = 10%
		},
	},

	-- Huevo "hardcore": probabilidades ultra bajas para Mítica/Secreta,
	-- calculadas sobre una escala de 10,000,000 en vez de 100.
	Egg_Mythical = {
		Id = "Egg_Mythical",
		Name = "Huevo Místico",
		Cost = 50000,
		TotalWeight = 10000000,
		Pool = {
			{ PetId = "Pet_Cat", Weight = 5000000 },     -- 50%
			{ PetId = "Pet_Rabbit", Weight = 3000000 },  -- 30%
			{ PetId = "Pet_Fox", Weight = 1500000 },     -- 15%
			{ PetId = "Pet_Shark", Weight = 490000 },    -- 4.9%
			{ PetId = "Pet_Dragon", Weight = 8000 },     -- 0.08%
			{ PetId = "Pet_Phoenix", Weight = 1000 },    -- 0.01%
			{ PetId = "Pet_Unicorn", Weight = 900 },     -- 0.009%  ← Mítica
			{ PetId = "Pet_VoidWyrm", Weight = 100 },    -- 0.001%  ← Secreta
		},
		-- Suma: 5,000,000 + 3,000,000 + 1,500,000 + 490,000 + 8,000 + 1,000 + 900 + 100
		--     = 10,000,000  ✓ (comprobar SIEMPRE que cuadre con TotalWeight)
	},
}

local EggsConfig = {}
EggsConfig.Eggs = Eggs

function EggsConfig.Get(eggId: string): EggDefinition?
	return Eggs[eggId]
end

return EggsConfig
