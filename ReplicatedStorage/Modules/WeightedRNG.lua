--[[
	WeightedRNG.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ReplicatedStorage > Modules > WeightedRNG   (ModuleScript)

	NOTA DE UBICACIÓN: este módulo vive en ReplicatedStorage (no en
	ServerScriptService) porque es lógica matemática PURA — no toma
	decisiones de diseño ni conoce dinero, mascotas o probabilidades
	reales de tu juego. Recibe un pool de pesos como parámetro y devuelve
	una entrada; no importa "de dónde" venga ese pool. Colocarlo aquí
	permite que tanto EggService (servidor, autoridad real del resultado)
	como PetManager (compartido) lo reutilicen sin duplicar código. La
	seguridad NO depende de dónde vive esta función, sino de que la ÚNICA
	llamada que genera una mascota real y descuenta dinero ocurre dentro
	de EggService.lua, en el servidor.

	Módulo puro (sin estado, sin dependencias de otros sistemas) que
	implementa la selección aleatoria por pesos. Reutilizable para loot de
	huevos, cofres, recompensas diarias, variantes de mascota, etc.

	--------------------------------------------------------------------
	ACTUALIZACIÓN — RNG Hardcore a gran escala con math.random():

	Antes usábamos Random.new():NextNumber(0, total), que devuelve un
	FLOAT. Para pesos "normales" (escala 100) es suficiente, pero para
	representar un 0.001% de forma fiable (1 en 10,000,000) los floats de
	64 bits empiezan a introducir imprecisión en la comparación del roll
	acumulado, especialmente si sumas muchos decimales pequeños.

	La solución es trabajar SIEMPRE con ENTEROS y math.random(1, n), que
	en Luau usa un generador de enteros exacto (sin redondeo) hasta
	2^53 - ampliamente suficiente para escalas de 10,000,000 o incluso
	1,000,000,000 si en el futuro quieres aún más precisión.

	REQUISITO: todos los "Weight" de tu pool DEBEN ser números enteros
	(no 0.5, no 12.3). Si necesitas más granularidad, sube la escala del
	TotalWeight (por ejemplo, de 100 a 10,000,000) en vez de usar decimales.

	ALGORITMO ("cumulative weight roll"):
		1. Sumamos todos los pesos del pool → totalWeight (entero).
		2. math.random(1, totalWeight) → roll (entero entre 1 y totalWeight).
		3. Recorremos el pool acumulando pesos hasta que el acumulado
		   sea >= roll: esa es la entrada ganadora.

	IMPORTANTE DE SEGURIDAD: este módulo SOLO se usa en el servidor. Si el
	cliente pudiera ejecutar este cálculo, podría manipular su propio
	resultado. Todo el roll ocurre dentro de EggService.lua / PetManager.lua,
	en el servidor.
--]]

local WeightedRNG = {}

-- pool: array de tablas que contienen AL MENOS un campo "Weight" (entero).
-- Devuelve la entrada elegida, o nil si el pool está vacío o mal formado.
function WeightedRNG.Roll(pool: { [number]: { Weight: number } })
	local totalWeight = 0
	for _, entry in ipairs(pool) do
		totalWeight += entry.Weight
	end

	if totalWeight <= 0 then
		warn("[WeightedRNG] El pool no tiene peso total válido.")
		return nil
	end

	-- math.random con dos argumentos enteros devuelve un entero uniforme
	-- en [1, totalWeight] sin pasar por coma flotante en ningún momento.
	local roll = math.random(1, totalWeight)

	local cumulative = 0
	for _, entry in ipairs(pool) do
		cumulative += entry.Weight
		if roll <= cumulative then
			return entry
		end
	end

	-- Fallback defensivo (no debería alcanzarse nunca con enteros exactos).
	return pool[#pool]
end

-- Variante que además valida que el TotalWeight declarado en tu config
-- (por ejemplo, EggsConfig.Egg_Mythical.TotalWeight) coincida EXACTAMENTE
-- con la suma real de los pesos del pool. Úsala en desarrollo para
-- detectar errores de balanceo (p. ej. te olvidaste de sumar una mascota
-- nueva al TotalWeight) antes de que lleguen a producción.
function WeightedRNG.RollWithValidation(pool: { [number]: { Weight: number } }, expectedTotalWeight: number)
	local totalWeight = 0
	for _, entry in ipairs(pool) do
		totalWeight += entry.Weight
	end

	if totalWeight ~= expectedTotalWeight then
		warn(("[WeightedRNG] TotalWeight declarado (%d) no coincide con la suma real del pool (%d)."):format(
			expectedTotalWeight,
			totalWeight
		))
	end

	return WeightedRNG.Roll(pool)
end

return WeightedRNG
