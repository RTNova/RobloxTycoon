--[[
	HUDController.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		StarterPlayer > StarterPlayerScripts > Controllers > HUDController
		(ModuleScript)

	RESPONSABILIDAD:
		Mostrar el dinero del jugador (leaderstats.Money) en un TextLabel,
		animando la transición entre el valor viejo y el nuevo como un
		cuentakilómetros: sube RÁPIDO al principio y se FRENA solo al
		acercarse al valor real, sin ningún salto brusco de un número a otro.

	--------------------------------------------------------------------
	LA MATEMÁTICA (interpolación exponencial por frame):

		displayedMoney += (targetMoney - displayedMoney) * factor

		Cada frame, el valor mostrado avanza una FRACCIÓN de la distancia
		que le falta para llegar al valor real. Esto tiene una propiedad
		muy útil: si la distancia es grande (acabas de ganar 10.000$), el
		incremento absoluto también es grande (se ve "rápido"); a medida
		que displayedMoney se acerca a targetMoney, la distancia se
		reduce, así que el incremento también se reduce (se ve que "frena
		suavemente"), sin necesidad de una curva de easing explícita ni de
		conocer de antemano cuánto va a tardar la animación.

		"factor" se recalcula cada frame como `LERP_SPEED * deltaTime`
		(acotado a 1) para que la velocidad de la animación sea la MISMA
		independientemente del framerate del jugador (30 FPS o 240 FPS).

	OPTIMIZACIÓN: la conexión a Heartbeat solo está activa MIENTRAS el
	número se está animando. En cuanto alcanza el valor real, se
	desconecta — así un HUD con dinero parado (jugador AFK) no consume
	nada de CPU en cada frame.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NumberFormat = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormat"))

local HUDController = {}

-- A mayor valor, más rápido "atrapa" el número mostrado al número real.
local LERP_SPEED = 6

-- Diferencia por debajo de la cual saltamos directos al valor exacto: sin
-- esto, una interpolación exponencial nunca llega a 0 exacto (se acerca
-- infinitamente), y nos quedaríamos con el Heartbeat conectado para siempre
-- por una diferencia de 0.0001$ imperceptible.
local SNAP_THRESHOLD = 1

local moneyLabel: TextLabel
local displayedMoney = 0
local targetMoney = 0
local heartbeatConn: RBXScriptConnection? = nil

local function Render()
	moneyLabel.Text = "$" .. NumberFormat.Format(math.floor(displayedMoney))
end

local function StopAnimation()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
end

local function StartAnimationIfNeeded()
	if heartbeatConn then return end -- Ya está animándose, no dupliques la conexión.

	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		local diff = targetMoney - displayedMoney

		if math.abs(diff) <= SNAP_THRESHOLD then
			displayedMoney = targetMoney
			Render()
			StopAnimation() -- Llegamos: apagamos el bucle hasta el próximo cambio.
			return
		end

		local factor = math.min(LERP_SPEED * dt, 1)
		displayedMoney += diff * factor
		Render()
	end)
end

function HUDController.Init(playerGui: PlayerGui)
	local mainHud = playerGui:WaitForChild("MainHUD")
	moneyLabel = mainHud:WaitForChild("TopBar"):WaitForChild("MoneyLabel")

	local player = Players.LocalPlayer
	local leaderstats = player:WaitForChild("leaderstats")
	local money = leaderstats:WaitForChild("Money")

	-- Estado inicial: sin animación (el jugador no necesita ver el
	-- cuentakilómetros subiendo desde 0 al entrar a la partida).
	displayedMoney = money.Value
	targetMoney = money.Value
	Render()

	money.Changed:Connect(function(newValue: number)
		targetMoney = newValue
		StartAnimationIfNeeded()
	end)
end

return HUDController
