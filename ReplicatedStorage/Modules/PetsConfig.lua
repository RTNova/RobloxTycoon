--[[
	PetsConfig.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ReplicatedStorage > Modules > PetsConfig   (ModuleScript)

	Por qué en ReplicatedStorage: el CLIENTE necesita esta tabla para poder
	dibujar la UI del inventario/gacha (nombre, icono, color de rareza...).
	Es información pública de diseño, no un dato sensible. Lo que SÍ es
	sensible (qué mascota te toca, si tienes dinero) se calcula solo en el
	servidor (ver EggService.lua).

	Cada entrada es la "plantilla" de una mascota (la especie). El
	inventario del jugador (DataManager.Data.Pets) NO copia estos campos:
	solo guarda PetId + Variant, y usa esta tabla para resolver el resto
	en tiempo real (Nombre, BaseMultiplier, etc.). Así, si rebalanceas el
	multiplicador de una mascota, se aplica automáticamente a todos los
	jugadores que ya la tengan.

	--------------------------------------------------------------------
	ACTUALIZACIÓN — Desglose de multiplicadores (Valor Base vs Variante):

	El "poder" final de una mascota YA NO es un único número. Se compone
	de dos partes independientes, para que la UI pueda mostrarlas por
	separado ("Base: +40%  ·  Shiny: +50%  ·  Total: +90%"):

		1. BaseMultiplier  → depende de la ESPECIE (Pet_Fox, Pet_Dragon...).
		   Vive aquí, en `Pets`.
		2. VariantBonus    → depende de la VARIANTE con la que salió esa
		   copia concreta al eclosionar (Normal, Shiny, Dorado...).
		   Vive aquí, en `Variants`.

	La función que las combina (`PetManager:CalculatePetPower`) vive en
	PetManager.lua, no aquí: este módulo es solo la base de datos estática,
	sin lógica de cálculo.
--]]

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary" | "Mythical" | "Secret"

export type PetDefinition = {
	Id: string,
	Name: string,
	Element: string,
	Rarity: Rarity,
	BaseMultiplier: number, -- Multiplicador de la especie en su versión Normal
}

export type VariantId = "Normal" | "Shiny" | "Golden"

export type VariantDefinition = {
	Id: VariantId,
	Name: string,
	Weight: number,      -- Peso para el RNG de variante (ver PetManager.RollVariant)
	VariantBonus: number, -- Bonus ADITIVO que se suma al BaseMultiplier de la especie
}

-- ========================================================================
-- ESPECIES DE MASCOTA
-- ========================================================================
local Pets: { [string]: PetDefinition } = {
	Pet_Cat = {
		Id = "Pet_Cat",
		Name = "Gato",
		Element = "Normal",
		Rarity = "Common",
		BaseMultiplier = 1.1,
	},
	Pet_Rabbit = {
		Id = "Pet_Rabbit",
		Name = "Conejo",
		Element = "Tierra",
		Rarity = "Common",
		BaseMultiplier = 1.15,
	},
	Pet_Fox = {
		Id = "Pet_Fox",
		Name = "Zorro de Fuego",
		Element = "Fuego",
		Rarity = "Rare",
		BaseMultiplier = 1.4,
	},
	Pet_Shark = {
		Id = "Pet_Shark",
		Name = "Tiburón",
		Element = "Agua",
		Rarity = "Rare",
		BaseMultiplier = 1.5,
	},
	Pet_Dragon = {
		Id = "Pet_Dragon",
		Name = "Dragón Ancestral",
		Element = "Fuego",
		Rarity = "Epic",
		BaseMultiplier = 2.5,
	},
	Pet_Phoenix = {
		Id = "Pet_Phoenix",
		Name = "Fénix",
		Element = "Fuego",
		Rarity = "Legendary",
		BaseMultiplier = 5,
	},

	-- Rareza Mítica: pensada para probabilidades del orden de 0.009%.
	Pet_Unicorn = {
		Id = "Pet_Unicorn",
		Name = "Unicornio Celestial",
		Element = "Luz",
		Rarity = "Mythical",
		BaseMultiplier = 15,
	},

	-- Rareza Secreta: la más alta del juego, pensada para ~0.001%.
	Pet_VoidWyrm = {
		Id = "Pet_VoidWyrm",
		Name = "Wyrm del Vacío",
		Element = "Oscuridad",
		Rarity = "Secret",
		BaseMultiplier = 50,
	},
}

-- ========================================================================
-- VARIANTES (aplican a CUALQUIER especie por igual)
-- ========================================================================
-- El peso aquí es independiente del peso de especie: se hace una tirada
-- SEPARADA en el momento de eclosionar (ver PetManager.RollVariant),
-- así que estos números son su propia escala de 1 a TotalWeight, no
-- porcentajes sobre 100.
local Variants: { [string]: VariantDefinition } = {
	Normal = {
		Id = "Normal",
		Name = "Normal",
		Weight = 9000, -- 90% con TotalWeight = 10000
		VariantBonus = 0,
	},
	Shiny = {
		Id = "Shiny",
		Name = "Shiny",
		Weight = 900, -- 9%
		VariantBonus = 0.5, -- +50% adicional sobre el multiplicador base
	},
	Golden = {
		Id = "Golden",
		Name = "Dorado",
		Weight = 100, -- 1%
		VariantBonus = 2, -- +200% adicional: una copia Dorada de un Dragón (2.5x) da 4.5x
	},
}

local PetsConfig = {}
PetsConfig.Pets = Pets
PetsConfig.Variants = Variants

-- Colores de rareza para la UI (bordes de tarjeta, texto, etc.). Vive aquí
-- y no en el propio InventoryController para que TODA la UI del juego
-- (inventario, notificación de "¡Te tocó...!", tienda...) use exactamente
-- el mismo color por rareza sin duplicar la tabla en cada script.
PetsConfig.RarityColors = {
	Common = Color3.fromRGB(190, 190, 190),
	Rare = Color3.fromRGB(70, 140, 255),
	Epic = Color3.fromRGB(170, 70, 255),
	Legendary = Color3.fromRGB(255, 170, 30),
	Mythical = Color3.fromRGB(255, 60, 60),
	Secret = Color3.fromRGB(15, 15, 15),
}

-- Orden numérico de rareza (mayor = más raro). Lo usa EggService para
-- comparar dos tiradas y quedarse con la más rara cuando el jugador tiene
-- el gamepass "x2 Luck" (ver GamepassManager). También sirve para
-- ordenar el inventario por rareza en la UI si lo necesitas más adelante.
PetsConfig.RarityOrder = {
	Common = 1,
	Rare = 2,
	Epic = 3,
	Legendary = 4,
	Mythical = 5,
	Secret = 6,
}

-- Helper: obtener la definición de una mascota validando que exista.
function PetsConfig.Get(petId: string): PetDefinition?
	return Pets[petId]
end

-- Helper: obtener la definición de una variante validando que exista.
function PetsConfig.GetVariant(variantId: string): VariantDefinition?
	return Variants[variantId]
end

-- Helper: color de una rareza, con blanco como fallback seguro si algún
-- día añades una rareza nueva y olvidas registrar su color.
function PetsConfig.GetRarityColor(rarity: string): Color3
	return PetsConfig.RarityColors[rarity] or Color3.new(1, 1, 1)
end

return PetsConfig
