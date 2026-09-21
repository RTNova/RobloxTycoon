--[[
	SkinController.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ServerScriptService > Modules > SkinController   (ModuleScript)

	RESPONSABILIDAD:
		- Clonar el prefabricado correcto (Cristal, Sakura...) en el
		  "CoreAnchor" del tycoon, sustituyendo cualquier Núcleo anterior.
		- Etiquetar la parte "CoreBody" del nuevo Núcleo para que
		  IncomeManager (recolección) y CoreVisuals.client.lua
		  (escalado/parpadeo) la encuentren automáticamente, sin que este
		  módulo tenga que conocer esa lógica.
		- Persistir la skin elegida en el perfil del jugador y restaurarla
		  al reclamar el tycoon.

	POR QUÉ ES SEGURO:
		El cliente solo envía un `skinId` (string). Si ese id no existe en
		SkinsConfig, la petición se descarta sin más. El cliente nunca
		especifica una ruta de instancia ni un modelo directamente: no hay
		forma de que un exploiter "clone" nada que no esté ya definido en
		SkinsConfig por el propio desarrollador.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local SkinsConfig = require(ReplicatedStorage.Modules.SkinsConfig)

local SkinController = {}

local CORE_BODY_NAME = "CoreBody"
local CORE_COLLECTOR_TAG = "CoreCollector"

-- Clona el prefab del skin indicado dentro del tycoon, sustituyendo
-- cualquier Núcleo anterior. Devuelve el nuevo Model (o nil si algo faltaba).
function SkinController.ApplySkin(tycoonModel: Model, skinId: string): Model?
	local skinDef = SkinsConfig.Get(skinId)
	if not skinDef then
		warn("[SkinController] Skin desconocido: " .. tostring(skinId))
		return nil
	end

	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local prefabFolder = assetsFolder and assetsFolder:FindFirstChild("CoreSkins")
	local prefab = prefabFolder and prefabFolder:FindFirstChild(skinDef.PrefabName)
	if not prefab then
		warn("[SkinController] Prefab no encontrado: ReplicatedStorage.Assets.CoreSkins." .. skinDef.PrefabName)
		return nil
	end

	local anchor = tycoonModel:FindFirstChild("CoreAnchor")
	if not anchor then
		warn("[SkinController] El tycoon no tiene un 'CoreAnchor': " .. tycoonModel:GetFullName())
		return nil
	end

	-- Elimina el Núcleo actual (de cualquier skin anterior) antes de clonar
	-- el nuevo. CollectionService limpia automáticamente el tag al
	-- destruirse la instancia, así que no hay que desetiquetarlo a mano.
	local existingCore = tycoonModel:FindFirstChild("Core")
	if existingCore then
		existingCore:Destroy()
	end

	local newCore = prefab:Clone()
	newCore.Name = "Core" -- SIEMPRE se llama "Core", pase lo que pase con el skin.
	newCore:PivotTo(anchor.CFrame)
	newCore.Parent = tycoonModel

	local coreBody = newCore:FindFirstChild(CORE_BODY_NAME, true)
	if coreBody then
		-- Guardamos el tamaño ORIGINAL como Attributes: CoreVisuals.client.lua
		-- los usa como punto de partida del Lerp de escalado, y así funciona
		-- igual de bien con un cristal pequeño que con un brote de sakura grande.
		coreBody:SetAttribute("BaseSize_X", coreBody.Size.X)
		coreBody:SetAttribute("BaseSize_Y", coreBody.Size.Y)
		coreBody:SetAttribute("BaseSize_Z", coreBody.Size.Z)

		CollectionService:AddTag(coreBody, CORE_COLLECTOR_TAG)
	else
		warn(("[SkinController] El prefab '%s' no contiene una parte llamada '%s'."):format(
			skinDef.PrefabName,
			CORE_BODY_NAME
		))
	end

	return newCore
end

-- Restaura el skin guardado del jugador en el momento de reclamar su tycoon.
function SkinController.ApplySavedSkin(player: Player, tycoonModel: Model, DataManager)
	local skinId = DataManager.GetSelectedSkin(player)
	SkinController.ApplySkin(tycoonModel, skinId)
end

-- Punto de entrada: escucha la petición del cliente para cambiar de skin.
function SkinController.Init(DataManager, TycoonManager)
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	local requestChangeSkin = remotesFolder:WaitForChild("RequestChangeSkin") -- RemoteEvent: (skinId: string)

	requestChangeSkin.OnServerEvent:Connect(function(player, skinId)
		-- Validación de tipo estricta, como en el resto de RemoteEvents.
		if typeof(skinId) ~= "string" then return end

		-- Anti-exploit: si el id no existe en SkinsConfig, se ignora.
		if not SkinsConfig.Get(skinId) then return end

		-- Solo puedes cambiar el skin de TU PROPIO tycoon.
		local tycoonModel = TycoonManager.GetTycoonOf(player)
		if not tycoonModel then return end

		local newCore = SkinController.ApplySkin(tycoonModel, skinId)
		if newCore then
			DataManager.SetSelectedSkin(player, skinId)
		end
	end)
end

return SkinController
