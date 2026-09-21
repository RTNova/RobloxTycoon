--[[
	GamepassConfig.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ReplicatedStorage > Modules > GamepassConfig   (ModuleScript)

	IMPORTANTE: los `Id` de abajo son PLACEHOLDERS. Sustitúyelos por los
	IDs reales de tus Gamepasses (Roblox Studio → botón "Monetization" del
	juego publicado → "Passes" → crear cada uno → copiar su ID numérico).

	Está en ReplicatedStorage porque el CLIENTE también necesita estos IDs
	para poder llamar a `MarketplaceService:PromptGamePassPurchase(...)`
	directamente desde un botón de la tienda (ver sección 11.6 del README).
	Los IDs de producto no son secretos: cualquiera puede verlos inspeccionando
	la página de la tienda del juego en el sitio web de Roblox.
--]]

export type GamepassDefinition = {
	Id: number,
	Name: string,
}

local Gamepasses: { [string]: GamepassDefinition } = {
	VIP = {
		Id = 0000001, -- ← Sustituir por el Id real
		Name = "VIP",
	},
	x2Luck = {
		Id = 0000002, -- ← Sustituir por el Id real
		Name = "x2 Luck",
	},
	PlusOneEquip = {
		Id = 0000003, -- ← Sustituir por el Id real
		Name = "+1 Equip",
	},
}

local GamepassConfig = {}
GamepassConfig.Gamepasses = Gamepasses

-- Bono ADITIVO permanente que aporta VIP al multiplicador total del
-- jugador (mismo sistema que el bono de mascotas: ver MultiplierManager).
-- +0.5 significa "+50% de dinero" de forma permanente, se tenga la mascota
-- que se tenga equipada.
GamepassConfig.VIP_MULTIPLIER_BONUS = 0.5

function GamepassConfig.Get(key: string): GamepassDefinition?
	return Gamepasses[key]
end

return GamepassConfig
