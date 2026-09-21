--[[
	SkinsConfig.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ReplicatedStorage > Modules > SkinsConfig   (ModuleScript)

	Define qué skins existen y a qué prefabricado (Model dentro de
	ReplicatedStorage.Assets.CoreSkins) corresponde cada una.

	IMPORTANTE — Anatomía obligatoria de un prefabricado de skin:
	Para que el escalado, el parpadeo y la recolección funcionen SIN
	importar qué skin esté activa, todo Model dentro de CoreSkins debe
	contener, en cualquier punto de su jerarquía:

		- Una BasePart llamada exactamente "CoreBody"
		  (es la que se escala y la que se puede tocar para recolectar).
		- Un PointLight llamado exactamente "CoreLight"
		  (normalmente como hijo de "CoreBody").
		- Opcionalmente, aplica un MaterialVariant tipo "Neon" a "CoreBody"
		  para el efecto de brillo (esto se hace en Studio, no por código).

	Esto es lo que permite que SkinController y CoreVisuals.client.lua NO
	necesiten saber nada de diseño 3D: solo buscan por NOMBRE esas dos
	piezas, sea cual sea el skin.
--]]

export type SkinDefinition = {
	Id: string,
	Name: string,
	PrefabName: string, -- Nombre exacto del Model dentro de Assets.CoreSkins
}

local Skins: { [string]: SkinDefinition } = {
	Default = {
		Id = "Default",
		Name = "Núcleo de Cristal",
		PrefabName = "CoreCrystal",
	},
	Tatami = {
		Id = "Tatami",
		Name = "Brote de Sakura",
		PrefabName = "CoreSakura",
	},
}

local SkinsConfig = {}
SkinsConfig.Skins = Skins

function SkinsConfig.Get(skinId: string): SkinDefinition?
	return Skins[skinId]
end

return SkinsConfig
