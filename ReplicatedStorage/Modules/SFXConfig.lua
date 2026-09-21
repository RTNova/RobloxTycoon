--[[
	SFXConfig.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ReplicatedStorage > Modules > SFXConfig   (ModuleScript)

	Diccionario plano `clave -> SoundId`. AudioManager.PlaySFX(key) busca
	aquí para no tener ningún Id de sonido "hardcodeado" repartido por los
	distintos controladores de UI — añadir o cambiar un sonido es tocar
	SOLO esta tabla, nunca el código que lo reproduce.
--]]

local SFX: { [string]: string } = {
	ButtonClick = "rbxassetid://0000000101", -- ← Sustituir por un Id real
	CoinCollect = "rbxassetid://0000000102",
	LevelUp = "rbxassetid://0000000103",
	EggHatch = "rbxassetid://0000000104",
	PetEquip = "rbxassetid://0000000105",
	Error = "rbxassetid://0000000106",
}

local SFXConfig = {}
SFXConfig.SFX = SFX

function SFXConfig.Get(key: string): string?
	return SFX[key]
end

return SFXConfig
