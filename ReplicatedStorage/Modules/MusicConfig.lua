--[[
	MusicConfig.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ReplicatedStorage > Modules > MusicConfig   (ModuleScript)

	Define las "zonas" de música según la distancia del jugador al centro
	del mapa. AudioManager recorre esta lista de MENOR a MAYOR `MaxDistance`
	y usa la PRIMERA zona cuyo `MaxDistance` sea mayor o igual que la
	distancia real del jugador — así que el orden de la tabla importa.

	Piensa en ello como "círculos concéntricos" alrededor del centro:
	dentro de 60 studs suena la música "núcleo" (más intensa/electrónica,
	a juego con el Núcleo Central); entre 60 y 200, una música de tycoon
	más neutra; más allá de 200, ambiente relajado de fondo.
--]]

export type MusicZone = {
	Name: string,
	MaxDistance: number, -- Distancia máxima al centro del mapa para esta zona
	TrackId: string, -- "rbxassetid://..."
}

-- ORDENADO de menor a mayor MaxDistance. La última entrada debería usar
-- math.huge para cubrir "cualquier distancia mayor" como zona por defecto.
local MusicZones: { MusicZone } = {
	{
		Name = "Core",
		MaxDistance = 60,
		TrackId = "rbxassetid://0000000001", -- ← Sustituir por un Id real
	},
	{
		Name = "TycoonArea",
		MaxDistance = 200,
		TrackId = "rbxassetid://0000000002", -- ← Sustituir por un Id real
	},
	{
		Name = "Ambient",
		MaxDistance = math.huge,
		TrackId = "rbxassetid://0000000003", -- ← Sustituir por un Id real
	},
}

local MusicConfig = {}
MusicConfig.Zones = MusicZones

-- Devuelve la primera zona (de menor a mayor distancia) que cubre la
-- distancia dada. Como la última entrada usa math.huge, esta función
-- SIEMPRE devuelve algo — nunca nil — mientras la tabla no esté vacía.
function MusicConfig.GetZoneForDistance(distance: number): MusicZone?
	for _, zone in ipairs(MusicZones) do
		if distance <= zone.MaxDistance then
			return zone
		end
	end
	return nil
end

return MusicConfig
