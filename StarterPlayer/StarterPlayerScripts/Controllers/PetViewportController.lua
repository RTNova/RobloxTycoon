--[[
	PetViewportController.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		StarterPlayer > StarterPlayerScripts > Controllers > PetViewportController
		(ModuleScript)

	RESPONSABILIDAD:
		- Clonar el modelo 3D de la mascota SELECCIONADA dentro de un
		  `ViewportFrame` (nunca en Workspace: un ViewportFrame renderiza
		  su propio mini-mundo aislado, así que el modelo clonado no
		  interfiere para nada con el juego real).
		- Crear y centrar una `Camera` propia (`ViewportFrame.CurrentCamera`)
		  encuadrando el modelo automáticamente según su tamaño real, sin
		  tener que ajustar la distancia a mano mascota por mascota.
		- Rotar el modelo suavemente sobre el eje Y en bucle, para dar
		  sensación de "vitrina 3D".

	CONVENCIÓN EN ReplicatedStorage:
		ReplicatedStorage
		└── Assets
		    └── PetModels (Folder)
		        ├── Pet_Cat     (Model) — el nombre DEBE coincidir con el PetId de PetsConfig
		        ├── Pet_Fox     (Model)
		        └── ...

	OPTIMIZACIÓN Y LIMPIEZA:
		Cada vez que se selecciona una mascota nueva, `ClearModel` destruye
		el modelo clonado anterior Y desconecta su bucle de rotación ANTES
		de crear el siguiente. Sin esto, cada cambio de selección dejaría
		una conexión de `RenderStepped` "fantasma" corriendo para siempre
		sobre un modelo ya destruido — una fuga de memoria y CPU clásica
		en UIs de inventario con vista previa 3D.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PetViewportController = {}

-- Velocidad de rotación en radianes/segundo. math.rad(30) = 30°/segundo,
-- una vuelta completa cada 12 segundos aprox.: lo bastante lento para
-- apreciar el modelo, lo bastante rápido para no parecer estático.
local ROTATION_SPEED = math.rad(30)

-- Multiplicador de margen: cuánto "aire" dejamos alrededor del modelo al
-- encuadrar la cámara, para que no quede pegado a los bordes del Viewport.
local CAMERA_MARGIN_MULTIPLIER = 1.6

local viewportFrame: ViewportFrame
local viewportCamera: Camera
local currentModel: Model? = nil
local rotationConn: RBXScriptConnection? = nil
local currentAngle = 0

local petModelsFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("PetModels")

-- Detiene (si existe) el bucle de rotación del modelo actual.
local function StopRotation()
	if rotationConn then
		rotationConn:Disconnect()
		rotationConn = nil
	end
end

-- Destruye el modelo clonado actual y detiene su rotación. Se llama SIEMPRE
-- antes de mostrar una mascota nueva, y también podría llamarse al cerrar
-- el menú de inventario para liberar recursos mientras no se usa.
local function ClearModel()
	StopRotation()

	if currentModel then
		currentModel:Destroy()
		currentModel = nil
	end
end

-- Centra el modelo en el origen (0,0,0) del pequeño "mundo" del Viewport,
-- y coloca la cámara mirándolo de frente a una distancia proporcional a su
-- tamaño real (bounding box), para que un Gato pequeño y un Dragón enorme
-- se vean igual de bien encuadrados sin tocar ni un número a mano.
local function CenterAndFrame(model: Model)
	local boundsCFrame, boundsSize = model:GetBoundingBox()

	-- Recentramos el modelo para que su centro geométrico quede en el
	-- origen: así la rotación (aplicada más abajo) gira sobre su propio
	-- centro en vez de "orbitar" desplazado.
	model:PivotTo(CFrame.new(-boundsCFrame.Position) * boundsCFrame)

	local maxExtent = math.max(boundsSize.X, boundsSize.Y, boundsSize.Z)
	local distance = (maxExtent * CAMERA_MARGIN_MULTIPLIER) + 1

	-- Cámara ligeramente elevada (un ángulo de "vitrina de tienda" en vez
	-- de una vista totalmente frontal y plana) mirando siempre al origen.
	local cameraPosition = Vector3.new(0, boundsSize.Y * 0.15, distance)
	viewportCamera.CFrame = CFrame.new(cameraPosition, Vector3.new(0, boundsSize.Y * 0.15, 0))
end

-- ========================================================================
-- API PÚBLICA
-- ========================================================================

-- petEntry: la entrada de inventario tal cual la usa InventoryController
-- (como mínimo necesita { PetId: string }).
function PetViewportController.SetPet(petEntry)
	ClearModel()

	local prefab = petModelsFolder:FindFirstChild(petEntry.PetId)
	if not prefab then
		warn("[PetViewportController] No hay modelo 3D registrado para: " .. tostring(petEntry.PetId))
		return
	end

	currentModel = prefab:Clone()
	currentModel.Parent = viewportFrame

	CenterAndFrame(currentModel)

	currentAngle = 0
	rotationConn = RunService.RenderStepped:Connect(function(dt)
		if not currentModel then
			StopRotation()
			return
		end

		currentAngle += ROTATION_SPEED * dt
		currentModel:PivotTo(CFrame.Angles(0, currentAngle, 0))
	end)
end

-- Útil para llamar al cerrar el panel de inventario, liberando el modelo
-- y la conexión de rotación mientras el jugador no está mirando la UI.
function PetViewportController.Clear()
	ClearModel()
end

function PetViewportController.Init(playerGui: PlayerGui)
	viewportFrame = playerGui
		:WaitForChild("MainHUD")
		:WaitForChild("InventoryFrame")
		:WaitForChild("StatsPanel")
		:WaitForChild("PetViewport")

	-- Cada ViewportFrame necesita su PROPIA Camera (no la CurrentCamera
	-- del Workspace real, que sigue siendo la del jugador en el mundo 3D).
	viewportCamera = Instance.new("Camera")
	viewportCamera.Name = "PetViewportCamera"
	viewportCamera.Parent = viewportFrame
	viewportFrame.CurrentCamera = viewportCamera
end

return PetViewportController
