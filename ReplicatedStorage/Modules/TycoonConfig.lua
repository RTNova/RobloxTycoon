--[[
	TycoonConfig.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ReplicatedStorage > Modules > TycoonConfig   (ModuleScript)

	Por qué está en ReplicatedStorage y no en ServerScriptService:
		Estas son constantes de BALANCEO/diseño que pueden ser útiles
		también en el cliente (por ejemplo, para mostrar en una UI
		"cuántos droppers máximos hay" o animaciones), y no contienen
		lógica sensible. La validación de coste/dinero SIEMPRE ocurre en
		el servidor (ver ButtonService), así que exponer estos números no
		supone ningún riesgo de seguridad.

	Este módulo NO define cada botón individualmente (eso vive como
	Attributes en cada Part dentro de Studio: Cost, ButtonId, Value,
	Interval). Esto es intencional: así puedes añadir botones o droppers
	nuevos sin tocar ni una línea de código Luau, solo construyendo en
	Studio y poniendo attributes + tags. Aquí solo van constantes
	GLOBALES del sistema.
--]]

return {
	-- Límite de monedas físicas simultáneas por tycoon (rendimiento).
	MAX_COINS_PER_TYCOON = 40,

	-- Segundos que tarda una moneda no recogida en autodestruirse.
	COIN_LIFETIME = 20,

	-- Nombres de los Tags de CollectionService usados por todo el sistema.
	-- Centralizarlos aquí evita errores de tipeo ("Droppper" vs "Dropper").
	Tags = {
		Button = "TycoonButton",
		Dropper = "Dropper",
		Collector = "Collector",
	},
}
