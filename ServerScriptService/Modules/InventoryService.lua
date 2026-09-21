--[[
	InventoryService.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ServerScriptService > Modules > InventoryService   (ModuleScript)

	RESPONSABILIDAD:
		- Responder la petición del cliente "dame mi inventario completo
		  de mascotas" vía RemoteFunction (`GetPetInventory`).
		- Avisar al cliente vía RemoteEvent (`InventoryUpdated`) cada vez
		  que su inventario cambia de verdad (nueva mascota, equipar/
		  desequipar), para que `InventoryController.lua` sepa cuándo
		  volver a pedirlo, sin tener que sondear al servidor sin parar.

	POR QUÉ ES SEGURO EXPONER EL INVENTARIO COMPLETO POR ESTE REMOTEFUNCTION:
		`OnServerInvoke` recibe automáticamente, como primer argumento, el
		`Player` que realmente hizo la llamada (Roblox lo garantiza a nivel
		de motor; el cliente no puede falsificarlo). Devolvemos SIEMPRE
		`DataManager.GetData(ESE player).Pets`: es estructuralmente
		imposible pedir el inventario de otro jugador a través de esta
		función, porque ni siquiera aceptamos un "userId" como parámetro.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryService = {}

function InventoryService.Init(DataManager)
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	local getPetInventory = remotesFolder:WaitForChild("GetPetInventory") -- RemoteFunction

	getPetInventory.OnServerInvoke = function(player: Player)
		local data = DataManager.GetData(player)
		if not data then return {} end

		-- Tabla { [uuid] = { PetId, Variant, Equipped, OriginalOwnerName, OriginalOwnerId } }
		return data.Pets
	end
end

-- Llamar desde cualquier módulo que modifique el inventario de un jugador
-- (EggService tras añadir una mascota, PetInventoryManager tras equipar).
-- Solo notifica "algo cambió, vuelve a pedirlo" — no manda los datos en sí,
-- así el propio RemoteFunction sigue siendo la única fuente de verdad.
function InventoryService.NotifyChanged(player: Player)
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	local inventoryUpdated = remotesFolder:WaitForChild("InventoryUpdated") -- RemoteEvent

	inventoryUpdated:FireClient(player)
end

return InventoryService
