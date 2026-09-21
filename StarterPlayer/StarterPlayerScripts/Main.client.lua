--[[
	Main.client.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		StarterPlayer > StarterPlayerScripts > Main   (LocalScript, NO ModuleScript)

	Igual que Main.server.lua en el servidor: es el ÚNICO script que se
	ejecuta solo en el cliente. Todo lo demás son ModuleScripts
	(AudioManager, Controllers/HUDController, Controllers/InventoryController,
	Controllers/PetViewportController) que este script orquesta.

	CONEXIÓN ENTRE CONTROLADORES:
		InventoryController no conoce a PetViewportController directamente
		(evitamos el acoplamiento): en su lugar, le inyectamos un callback
		con `SetOnPetSelected`, que InventoryController invoca cada vez
		que el jugador selecciona una tarjeta distinta. Así cada
		controlador se puede leer, mantener y sustituir de forma
		independiente.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local AudioManager = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AudioManager"))

local Controllers = script.Parent:WaitForChild("Controllers")
local HUDController = require(Controllers:WaitForChild("HUDController"))
local InventoryController = require(Controllers:WaitForChild("InventoryController"))
local PetViewportController = require(Controllers:WaitForChild("PetViewportController"))

AudioManager.Init() -- Arranca la música dinámica por distancia (ver AudioManager.lua).

HUDController.Init(playerGui)
PetViewportController.Init(playerGui)

-- Cuando el jugador selecciona una mascota en el grid, mostramos su
-- modelo 3D en el Viewport del panel lateral.
InventoryController.SetOnPetSelected(function(petEntry)
	PetViewportController.SetPet(petEntry)
end)

InventoryController.Init(playerGui)
