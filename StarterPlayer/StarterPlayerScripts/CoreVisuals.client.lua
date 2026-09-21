--[[
	CoreVisuals.client.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		StarterPlayer > StarterPlayerScripts > CoreVisuals   (LocalScript)

	RESPONSABILIDAD:
		- Localizar el tycoon reclamado por ESTE jugador y, dentro de él,
		  el Núcleo actual ("Core" > "CoreBody" / "CoreLight").
		- Cada vez que el servidor actualiza "PendingMoney" (ver
		  IncomeManager.lua, ~1 vez por segundo), interpolar suavemente el
		  tamaño de "CoreBody" con TweenService hacia un tamaño objetivo,
		  limitado por un máximo (nunca crece sin límite).
		- Ajustar la velocidad de parpadeo de "CoreLight" (PointLight)
		  según "IncomeRate" (dinero/segundo YA multiplicado por mascotas):
		  a más ingreso, parpadeo más rápido.
		- Volver a "engancharse" automáticamente si el Núcleo cambia de
		  skin (SkinController destruye el Core viejo y clona uno nuevo).

	POR QUÉ SE LEE POR EVENTOS Y NO EN UN BUCLE CADA FRAME:
		El servidor solo actualiza PendingMoney/IncomeRate una vez cada
		`CoreConfig.INCOME_UPDATE_INTERVAL` segundos (por defecto, 1). No
		hay ninguna ganancia en comprobar esos valores 60 veces por
		segundo: usamos `.Changed:Connect(...)`, que solo se dispara
		cuando el servidor realmente escribe un valor nuevo, y dejamos que
		TweenService se encargue de que la transición ENTRE esos dos
		valores se vea fluida (interpola durante `SCALE_TWEEN_TIME`
		segundos, más que de sobra para cubrir el hueco de 1 segundo).
--]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoreConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CoreConfig"))
local AudioManager = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AudioManager"))

local player = Players.LocalPlayer
local tycoonsFolder = Workspace:WaitForChild("Tycoons")

local currentCoreBody: BasePart? = nil
local currentCoreLight: PointLight? = nil
local blinkTween: Tween? = nil -- Referencia al tween de parpadeo activo, para poder cancelarlo.
local lastPendingMoney = 0 -- Para detectar una RECOLECCIÓN (el valor baja de golpe en vez de subir).

-- Busca el tycoon cuyo atributo "OwnerUserId" coincide con este jugador.
-- Puede tardar unos segundos si el jugador aún no ha tocado su ClaimPad.
local function FindMyTycoon(): Model?
	for _, tycoonModel in ipairs(tycoonsFolder:GetChildren()) do
		if tycoonModel:GetAttribute("OwnerUserId") == player.UserId then
			return tycoonModel
		end
	end
	return nil
end

-- Vuelve a localizar CoreBody/CoreLight dentro del Núcleo actual. Se llama
-- al principio y cada vez que el Núcleo se sustituye (cambio de skin), ya
-- que las referencias antiguas apuntarían a instancias ya destruidas.
local function RebindCoreParts(tycoonModel: Model)
	local core = tycoonModel:WaitForChild("Core", 5)
	if not core then
		warn("[CoreVisuals] El tycoon no tiene (todavía) un 'Core'.")
		return
	end

	currentCoreBody = core:FindFirstChild("CoreBody", true) :: BasePart?
	currentCoreLight = core:FindFirstChild("CoreLight", true) :: PointLight?

	if not currentCoreBody then
		warn("[CoreVisuals] El Núcleo actual no tiene una parte 'CoreBody'.")
	end
	if not currentCoreLight then
		warn("[CoreVisuals] El Núcleo actual no tiene un PointLight 'CoreLight'.")
	end

	-- El tween de parpadeo anterior apuntaba a una luz que puede ya no
	-- existir: lo cancelamos, UpdateBlinkSpeed creará uno nuevo.
	if blinkTween then
		blinkTween:Cancel()
		blinkTween = nil
	end
end

-- ESCALADO: interpola CoreBody entre su tamaño base (guardado por
-- SkinController como Attributes al clonar el prefab) y ese mismo tamaño
-- multiplicado por MAX_SCALE_MULTIPLIER, según qué % del "techo visual"
-- (CoreConfig.MAX_PENDING_FOR_VISUAL) representa el dinero pendiente actual.
local function UpdateScale(pendingMoney: number)
	if not currentCoreBody then return end

	local baseSize = Vector3.new(
		currentCoreBody:GetAttribute("BaseSize_X") or currentCoreBody.Size.X,
		currentCoreBody:GetAttribute("BaseSize_Y") or currentCoreBody.Size.Y,
		currentCoreBody:GetAttribute("BaseSize_Z") or currentCoreBody.Size.Z
	)

	-- Clamp a [0, 1]: por encima del techo visual, el núcleo simplemente
	-- se queda en su tamaño máximo (no sigue creciendo sin límite).
	local progress = math.clamp(pendingMoney / CoreConfig.MAX_PENDING_FOR_VISUAL, 0, 1)
	local targetSize = baseSize:Lerp(baseSize * CoreConfig.MAX_SCALE_MULTIPLIER, progress)

	TweenService:Create(
		currentCoreBody,
		TweenInfo.new(CoreConfig.SCALE_TWEEN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Size = targetSize }
	):Play()
end

-- SONIDO DE RECOLECCIÓN: IncomeManager solo SUMA dinero pendiente (nunca
-- lo baja), así que la ÚNICA forma en que "pendingMoney" puede ser MENOR
-- que la última vez que lo vimos es que el jugador acaba de tocar el
-- Núcleo y CollectPendingMoney lo reseteó a 0 en el servidor. Aprovechamos
-- esa señal para reproducir el SFX de recolección, posicionado en el
-- propio Núcleo (audio espacial: se oye más fuerte cerca de tu base).
local function DetectCollectionSound(pendingMoney: number)
	if pendingMoney < lastPendingMoney and currentCoreBody then
		AudioManager.PlaySpatialSFX(currentCoreBody, "CoinCollect", {
			RollOffMinDistance = 8,
			RollOffMaxDistance = 40,
		})
	end
	lastPendingMoney = pendingMoney
end

-- PARPADEO: cuanto mayor sea "IncomeRate" (dinero/segundo ya multiplicado
-- por el bono de mascotas equipadas), más rápido parpadea CoreLight. Se
-- implementa como un Tween en bucle infinito (Brightness sube y baja) cuya
-- DURACIÓN se recalcula cada vez que el servidor manda un IncomeRate nuevo.
local function UpdateBlinkSpeed(incomeRate: number)
	if not currentCoreLight then return end

	if blinkTween then
		blinkTween:Cancel()
		blinkTween = nil
	end

	if incomeRate <= 0 then
		-- Sin generadores comprados todavía: luz fija y tenue, sin parpadeo.
		currentCoreLight.Brightness = CoreConfig.MIN_BRIGHTNESS
		return
	end

	-- A más ingreso, menor duración (parpadeo más rápido), acotado entre
	-- MIN_BLINK_TIME y MAX_BLINK_TIME para no generar un estroboscopio ni
	-- un parpadeo demasiado lento en tycoons recién empezados.
	local duration = math.clamp(
		CoreConfig.BLINK_BASE_TIME / incomeRate,
		CoreConfig.MIN_BLINK_TIME,
		CoreConfig.MAX_BLINK_TIME
	)

	-- Repeat = -1 (infinito) y Reverses = true: sube a MAX_BRIGHTNESS y
	-- vuelve a bajar solo, en un único Tween en bucle (barato en rendimiento
	-- comparado con reprogramar un `while true do task.wait() end` a mano).
	blinkTween = TweenService:Create(
		currentCoreLight,
		TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Brightness = CoreConfig.MAX_BRIGHTNESS }
	)
	blinkTween:Play()
end

-- ============================================================================
-- ARRANQUE
-- ============================================================================
task.spawn(function()
	local tycoonModel: Model? = nil
	while not tycoonModel do
		tycoonModel = FindMyTycoon()
		if not tycoonModel then
			task.wait(1) -- El jugador puede tardar unos segundos en reclamar su plot.
		end
	end

	RebindCoreParts(tycoonModel)

	-- Si el jugador cambia de skin en pleno directo, SkinController destruye
	-- el "Core" viejo y clona uno nuevo con el mismo nombre: reaccionamos
	-- para no quedarnos apuntando a instancias muertas.
	tycoonModel.ChildAdded:Connect(function(child)
		if child.Name == "Core" then
			RebindCoreParts(tycoonModel)
			-- Reaplicamos el último estado conocido al Núcleo recién clonado.
			local coreData = player:FindFirstChild("CoreData")
			if coreData then
				UpdateScale(coreData.PendingMoney.Value)
				UpdateBlinkSpeed(coreData.IncomeRate.Value)
			end
		end
	end)

	local coreData = player:WaitForChild("CoreData")
	local pendingMoney = coreData:WaitForChild("PendingMoney")
	local incomeRate = coreData:WaitForChild("IncomeRate")

	-- Aplicamos el estado inicial por si el jugador entra con progreso
	-- (dinero pendiente) ya guardado de una sesión anterior.
	lastPendingMoney = pendingMoney.Value -- Evita un falso "sonido de recolección" en el primer Changed.
	UpdateScale(pendingMoney.Value)
	UpdateBlinkSpeed(incomeRate.Value)

	pendingMoney.Changed:Connect(function(newValue)
		DetectCollectionSound(newValue)
		UpdateScale(newValue)
	end)
	incomeRate.Changed:Connect(UpdateBlinkSpeed)
end)
