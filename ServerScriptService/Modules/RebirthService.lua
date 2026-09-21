--[[
	RebirthService.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ServerScriptService > Modules > RebirthService   (ModuleScript)

	RESPONSABILIDAD:
		Puente fino entre el RemoteEvent del cliente y
		`TycoonManager:Rebirth(player)` — toda la lógica real (validar el
		botón final, sumar puntos, resetear datos, recargar el tycoon)
		vive en TycoonManager.lua; este módulo solo traduce la petición de
		red a esa llamada y devuelve el resultado al cliente.

	POR QUÉ ES SEGURO:
		El RemoteEvent no lleva NINGÚN parámetro además del propio
		`player` (que Roblox garantiza que es quien realmente hizo la
		llamada). No hay nada que un cliente pueda falsificar aquí: o
		cumple la condición de Rebirth (botón final comprado) o no,
		y esa comprobación es 100% del lado del servidor.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RebirthService = {}

function RebirthService.Init(TycoonManager)
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	local requestRebirth = remotesFolder:WaitForChild("RequestRebirth") -- RemoteEvent (sin parámetros)
	local rebirthResult = remotesFolder:WaitForChild("RebirthResult") -- RemoteEvent

	requestRebirth.OnServerEvent:Connect(function(player)
		local success, reason = TycoonManager:Rebirth(player)

		rebirthResult:FireClient(player, {
			Success = success,
			Reason = reason, -- nil si success es true
		})
	end)
end

return RebirthService
