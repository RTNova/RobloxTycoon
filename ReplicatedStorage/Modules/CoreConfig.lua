--[[
	CoreConfig.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ReplicatedStorage > Modules > CoreConfig   (ModuleScript)

	Constantes de diseño/balanceo del Núcleo Central. Están en
	ReplicatedStorage porque tanto el servidor (IncomeManager, cada cuánto
	actualiza) como el cliente (CoreVisuals.client.lua, cómo escala y
	parpadea) las necesitan, y no son datos sensibles.
--]]

return {
	-- Cada cuántos segundos IncomeManager suma dinero pendiente al Núcleo
	-- de cada jugador. Un valor más bajo = feedback más fluido, pero más
	-- carga de CPU en el bucle del servidor. 1 segundo es un buen punto
	-- de partida para "cero lag" con muchos jugadores simultáneos.
	INCOME_UPDATE_INTERVAL = 1,

	-- ESCALADO DEL NÚCLEO
	-- Cantidad de dinero pendiente que representa el "100% de crecimiento"
	-- visual. Con más dinero pendiente que esto, el núcleo ya no crece más
	-- (se queda en su tamaño máximo) aunque la cifra real siga subiendo.
	MAX_PENDING_FOR_VISUAL = 5000,

	-- El núcleo, a tamaño máximo, mide esto multiplicado por su tamaño base.
	MAX_SCALE_MULTIPLIER = 1.6,

	-- Duración del tween de escalado cada vez que llega una actualización.
	SCALE_TWEEN_TIME = 0.6,

	-- PARPADEO DE LA LUZ (PointLight) / NEON
	MIN_BRIGHTNESS = 1,
	MAX_BRIGHTNESS = 6,

	-- La duración del parpadeo se calcula como BLINK_BASE_TIME / incomeRate,
	-- así que a más dinero/segundo, menor duración (parpadeo más rápido).
	BLINK_BASE_TIME = 4,
	MIN_BLINK_TIME = 0.15, -- Suelo: nunca más rápido que esto (evita efecto estroboscopio)
	MAX_BLINK_TIME = 2,    -- Techo: nunca más lento que esto aunque el ingreso sea 0
}
