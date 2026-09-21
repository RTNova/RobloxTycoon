--[[
	PetInventoryManager.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ServerScriptService > Modules > PetInventoryManager   (ModuleScript)

	RESPONSABILIDAD:
		Escuchar la petición del cliente para equipar/desequipar una
		mascota concreta (por su UUID), validar que esa mascota REALMENTE
		pertenezca a quien la pide, aplicar el cambio en DataManager, y
		disparar el recálculo del multiplicador (MultiplierManager).

	POR QUÉ ES SEGURO:
		DataManager.SetPetEquipped busca el UUID dentro de
		DataManager.Profiles[player].Data.Pets — es decir, dentro del
		PROPIO perfil del jugador que hizo la petición. Es físicamente
		imposible que un jugador equipe una mascota de otro jugador,
		porque ni siquiera está buscando en la tabla correcta: cada
		jugador solo puede tocar su propio diccionario Pets.

	LÍMITE DE MASCOTAS EQUIPADAS:
		Muchos Pet Simulators limitan a "máximo N mascotas equipadas a la
		vez" (por rendimiento visual, ya que las mascotas siguen al
		jugador). MAX_EQUIPPED_PETS_BASE controla el límite base (por
		defecto 3); se le suma el Gamepass "+1 Equip" (GamepassManager) y
		el nodo "Vínculo Extra" del Skill Tree (BuffManager) — ambas
		fuentes de bonus se acumulan sin conflicto entre sí.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetInventoryManager = {}

local MAX_EQUIPPED_PETS_BASE = 3

function PetInventoryManager.Init(DataManager, MultiplierManager, InventoryService, GamepassManager, BuffManager)
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	local requestEquipPet = remotesFolder:WaitForChild("RequestEquipPet") -- RemoteEvent: (uuid: string, equip: boolean)

	requestEquipPet.OnServerEvent:Connect(function(player, uuid, equip)
		-- Validación de tipos estricta: nunca confiar en lo que manda el cliente.
		if typeof(uuid) ~= "string" or typeof(equip) ~= "boolean" then
			return
		end

		if equip then
			-- El límite combina TRES fuentes: la base fija, el Gamepass
			-- "+1 Equip" y los nodos "Vínculo Extra" del Skill Tree. Ambos
			-- bonus son lecturas O(1) ya cacheadas, así que consultarlos en
			-- cada intento de equipar no tiene coste real.
			local maxEquipped = MAX_EQUIPPED_PETS_BASE
			if GamepassManager.HasGamepass(player, "PlusOneEquip") then
				maxEquipped += 1
			end
			maxEquipped += BuffManager.GetMaxEquippedBonus(player)

			local currentlyEquipped = DataManager.GetEquippedPets(player)
			if #currentlyEquipped >= maxEquipped then
				-- Aquí podrías disparar un RemoteEvent de aviso tipo
				-- "Máximo N mascotas equipadas" para la UI del cliente.
				return
			end
		end

		local success = DataManager.SetPetEquipped(player, uuid, equip)
		if not success then
			-- El UUID no existe en el inventario de ESTE jugador: ignorar.
			-- (esto es lo que bloquea el exploit de "equipar mascota ajena").
			return
		end

		-- El equipo cambió: recalculamos el multiplicador cacheado.
		MultiplierManager.Recalculate(player, DataManager, GamepassManager)

		-- Y avisamos a InventoryController (UI) para que refresque el
		-- estado visual de "Equipada" en el grid y el botón del panel lateral.
		InventoryService.NotifyChanged(player)
	end)
end

return PetInventoryManager
