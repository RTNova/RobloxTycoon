--[[
	NumberFormat.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ReplicatedStorage > Modules > NumberFormat   (ModuleScript)

	Módulo puro y compartido: cualquier UI que muestre una cifra grande
	(HUD de dinero, tienda, leaderboard...) debería pasar por aquí, para
	que todo el juego use el mismo criterio de formateo (evita que una
	pantalla diga "1.2K" y otra "1,200").
--]]

local NumberFormat = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

-- Convierte 1234567 en "1.23M", -500 en "-500", 999 en "999".
function NumberFormat.Format(number: number): string
	local isNegative = number < 0
	number = math.abs(number)

	local tier = 1
	while number >= 1000 and tier < #SUFFIXES do
		number /= 1000
		tier += 1
	end

	local formatted: string
	if tier == 1 then
		formatted = tostring(math.floor(number))
	else
		formatted = string.format("%.2f%s", number, SUFFIXES[tier])
	end

	return (isNegative and "-" or "") .. formatted
end

return NumberFormat
