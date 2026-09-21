--[[
	DevProductConfig.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ReplicatedStorage > Modules > DevProductConfig   (ModuleScript)

	IMPORTANTE: los `Id` de abajo son PLACEHOLDERS. Sustitúyelos por los
	IDs reales de tus Developer Products (Roblox Studio → "Monetization"
	del juego publicado → "Developer Products" → crear cada uno → copiar
	su ID numérico).

	`Amount` es opcional: solo lo usan los productos de "paquete de
	monedas", que DevProductHandler registra automáticamente de forma
	genérica (ver DevProductHandler.RegisterMoneyPacks). "PetCloneFee" NO
	tiene Amount porque su recompensa no es un número fijo de monedas: la
	gestiona por completo PetCloneService.
--]]

export type DevProductDefinition = {
	Id: number,
	Amount: number?,
}

local DevProducts: { [string]: DevProductDefinition } = {
	MoneyPack_Small = { Id = 1000001, Amount = 1000 },
	MoneyPack_Medium = { Id = 1000002, Amount = 5000 },
	MoneyPack_Large = { Id = 1000003, Amount = 25000 },

	-- Tarifa de la clonación social de mascotas (ver PetCloneService.lua).
	PetCloneFee = { Id = 1000004 },
}

local DevProductConfig = {}
DevProductConfig.DevProducts = DevProducts

function DevProductConfig.Get(key: string): DevProductDefinition?
	return DevProducts[key]
end

-- Búsqueda inversa (Id de Roblox → key interna), útil para depuración/logs.
function DevProductConfig.GetKeyById(productId: number): string?
	for key, def in pairs(DevProducts) do
		if def.Id == productId then
			return key
		end
	end
	return nil
end

return DevProductConfig
