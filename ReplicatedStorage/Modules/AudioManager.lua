--[[
	AudioManager.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ReplicatedStorage > Modules > AudioManager   (ModuleScript)

	Módulo 100% CLIENTE (aunque viva en ReplicatedStorage para que
	cualquier LocalScript/ModuleScript de UI pueda requerirlo desde
	cualquier punto, igual que NumberFormat o PetManager). Nunca lo
	requieras desde un script de servidor: `SoundService`, `TweenService`
	sobre `Sound.Volume` y la posición del jugador son conceptos de cliente.

	TRES RESPONSABILIDADES:
		1. Música dinámica por distancia al centro del mapa (crossfade).
		2. SFX 2D de UI con pool anti-corte (botones, monedas, subir de nivel).
		3. Helper de audio espacial 3D de un solo uso (para efectos como
		   la eclosión de un huevo) — ver también la sección 12.5 del
		   README para la configuración ESTÁTICA de Sound dentro de cada
		   huevo, que es la otra mitad de la respuesta al audio espacial.
--]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local MusicConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MusicConfig"))
local SFXConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SFXConfig"))

local AudioManager = {}

local player = Players.LocalPlayer

-- ============================================================================
-- 1) MÚSICA DINÁMICA POR DISTANCIA (crossfade con TweenService)
-- ============================================================================

local MUSIC_VOLUME = 0.35
local MUSIC_FADE_TIME = 2.5 -- Segundos que dura el fundido cruzado entre pistas
local MUSIC_CHECK_INTERVAL = 2 -- Cada cuántos segundos comprobamos la distancia

-- No hace falta comprobar la distancia 60 veces por segundo: el jugador
-- no puede cruzar de zona musical en menos de un par de segundos, así que
-- comprobarlo cada MUSIC_CHECK_INTERVAL es indistinguible para el oído y
-- muchísimo más barato que un bucle en Heartbeat.
local musicLoopStarted = false
local currentMusicSound: Sound? = nil
local currentZoneName: string? = nil

-- Referencia al centro del mapa: un Part invisible llamado "MapCenter"
-- colocado a mano en Workspace (posición = el punto desde el que se miden
-- todas las distancias de MusicConfig). Si no existe, usamos el origen
-- (0,0,0) como fallback seguro para no romper el resto del sistema.
local function GetMapCenterPosition(): Vector3
	local marker = Workspace:FindFirstChild("MapCenter")
	if marker and marker:IsA("BasePart") then
		return marker.Position
	end
	return Vector3.zero
end

-- Fundido cruzado: sube el volumen de la pista nueva desde 0 mientras baja
-- la de la pista vieja hasta 0, ambos con el mismo TweenInfo, así que se
-- cruzan a medio camino sin que haya un instante de silencio ni de
-- solapamiento a volumen completo (que sonaría "sucio").
local function CrossfadeToTrack(zone)
	if currentZoneName == zone.Name then return end -- Ya estamos en esa zona; nada que hacer.
	currentZoneName = zone.Name

	local newSound = Instance.new("Sound")
	newSound.Name = "MusicTrack_" .. zone.Name
	newSound.SoundId = zone.TrackId
	newSound.Looped = true
	newSound.Volume = 0
	newSound.Parent = SoundService
	newSound:Play()

	TweenService:Create(newSound, TweenInfo.new(MUSIC_FADE_TIME, Enum.EasingStyle.Sine), {
		Volume = MUSIC_VOLUME,
	}):Play()

	if currentMusicSound then
		local oldSound = currentMusicSound
		local fadeOut = TweenService:Create(oldSound, TweenInfo.new(MUSIC_FADE_TIME, Enum.EasingStyle.Sine), {
			Volume = 0,
		})
		fadeOut.Completed:Connect(function()
			oldSound:Stop()
			oldSound:Destroy()
		end)
		fadeOut:Play()
	end

	currentMusicSound = newSound
end

local function MusicLoop()
	while true do
		task.wait(MUSIC_CHECK_INTERVAL)

		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			local distance = (rootPart.Position - GetMapCenterPosition()).Magnitude
			local zone = MusicConfig.GetZoneForDistance(distance)
			if zone then
				CrossfadeToTrack(zone)
			end
		end
	end
end

-- Arranca el gestor de música dinámica. Idempotente: llamarlo dos veces
-- no duplica el bucle.
function AudioManager.StartDynamicMusic()
	if musicLoopStarted then return end
	musicLoopStarted = true
	task.spawn(MusicLoop)
end

-- ============================================================================
-- 2) SFX 2D DE UI (pool anti-corte)
-- ============================================================================

local SFX_VOLUME = 0.6
local MAX_SFX_POOL_SIZE = 16 -- Límite de seguridad, ver GetAvailableSound más abajo

local sfxContainer: Folder
local sfxPool: { Sound } = {}

local function EnsureSFXContainer()
	if sfxContainer then return end

	sfxContainer = Instance.new("Folder")
	sfxContainer.Name = "SFXPool"
	sfxContainer.Parent = SoundService
end

-- Busca un Sound del pool que NO esté sonando ahora mismo (reutilizable).
-- Si todos están ocupados, crea uno nuevo Y LO AÑADE al pool para
-- reutilizarlo en el futuro — el pool "crece" solo hasta que cubre el
-- pico de sonidos simultáneos que realmente necesita este jugador, sin
-- tener que adivinar un tamaño fijo de antemano.
local function GetAvailableSound(): Sound
	for _, sound in ipairs(sfxPool) do
		if not sound.Playing then
			return sound
		end
	end

	if #sfxPool >= MAX_SFX_POOL_SIZE then
		-- Límite de seguridad: si hay MAX_SFX_POOL_SIZE sonidos sonando A
		-- LA VEZ, casi seguro que es un bug en bucle disparando SFX sin
		-- parar, no un jugador pulsando botones. Reutilizamos el más
		-- antiguo (cortándolo) en vez de seguir creando instancias sin límite.
		return sfxPool[1]
	end

	EnsureSFXContainer()
	local sound = Instance.new("Sound")
	sound.Name = "SFXSlot" .. (#sfxPool + 1)
	sound.Parent = sfxContainer
	table.insert(sfxPool, sound)
	return sound
end

-- Reproduce un SFX 2D (sin posición en el mundo — se oye igual de fuerte
-- lo mires desde donde lo mires) identificado por su clave en SFXConfig.
--
-- POR QUÉ NO SE CORTA AL PULSAR RÁPIDO: cada llamada usa un Sound
-- INDEPENDIENTE del pool (reutilizando uno libre, o creando uno nuevo si
-- todos están ocupados), en vez de reproducir siempre sobre EL MISMO
-- objeto Sound. Un único Sound reproduciéndose de nuevo (`:Play()`)
-- corta el sonido anterior en seco; con un pool, dos clics rápidos suenan
-- SUPERPUESTOS de forma natural, como pasaría con sonidos reales.
function AudioManager.PlaySFX(key: string, volumeOverride: number?)
	local soundId = SFXConfig.Get(key)
	if not soundId then
		warn("[AudioManager] SFX desconocido: " .. tostring(key))
		return
	end

	local sound = GetAvailableSound()
	sound.SoundId = soundId
	sound.Volume = volumeOverride or SFX_VOLUME
	sound.TimePosition = 0
	sound:Play()
end

-- ============================================================================
-- 3) AUDIO ESPACIAL 3D — helper de un solo uso (efectos puntuales)
-- ============================================================================

-- Valores por defecto pensados para un efecto puntual de tamaño mediano
-- (una eclosión, una explosión de confeti al comprar un botón...). Se
-- pueden sobrescribir por llamada con la tabla `options`. Ver la sección
-- 12.5 del README para los mismos conceptos aplicados a un Sound
-- COLOCADO A MANO dentro de cada huevo en Studio (el otro caso de uso
-- que pediste: audio espacial "permanente", no solo de un solo uso).
local SPATIAL_DEFAULTS = {
	RollOffMinDistance = 5,
	RollOffMaxDistance = 60,
	RollOffMode = Enum.RollOffMode.InverseTapered,
	Volume = 0.8,
}

export type SpatialSFXOptions = {
	RollOffMinDistance: number?,
	RollOffMaxDistance: number?,
	RollOffMode: Enum.RollOffMode?,
	Volume: number?,
}

-- target: una BasePart o un Attachment — un Sound SOLO es posicional
-- (3D) si su `Parent` es una de esas dos cosas; parentarlo a SoundService
-- o a un Script lo convierte en un sonido 2D global, sin importar qué
-- RollOff le pongas.
function AudioManager.PlaySpatialSFX(target: BasePart | Attachment, key: string, options: SpatialSFXOptions?)
	local soundId = SFXConfig.Get(key)
	if not soundId then
		warn("[AudioManager] SFX desconocido: " .. tostring(key))
		return
	end

	options = options or {}

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = options.Volume or SPATIAL_DEFAULTS.Volume
	sound.RollOffMode = options.RollOffMode or SPATIAL_DEFAULTS.RollOffMode
	sound.RollOffMinDistance = options.RollOffMinDistance or SPATIAL_DEFAULTS.RollOffMinDistance
	sound.RollOffMaxDistance = options.RollOffMaxDistance or SPATIAL_DEFAULTS.RollOffMaxDistance
	sound.Parent = target
	sound:Play()

	-- Autolimpieza: como es un efecto de un solo uso (no está en bucle),
	-- lo destruimos en cuanto termine de sonar. Usamos el evento `Ended`
	-- en vez de `sound.TimeLength` porque TimeLength puede seguir siendo 0
	-- justo después de crear el Sound (el audio aún no ha terminado de
	-- cargar sus metadatos) — depender de él aquí podría destruir el
	-- sonido antes de que llegue a sonar. `Debris:AddItem` con un margen
	-- amplio (30s) es solo una red de seguridad por si `Ended` no llegara
	-- a dispararse nunca (por ejemplo, un SoundId roto).
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	Debris:AddItem(sound, 30)
end

-- ============================================================================
-- ARRANQUE
-- ============================================================================

-- Llamar UNA vez desde Main.client.lua. Separado de `require(...)` a
-- propósito (requerir el módulo no debe tener efectos secundarios):
-- arrancar el bucle de música es una acción explícita.
function AudioManager.Init()
	AudioManager.StartDynamicMusic()
end

return AudioManager
