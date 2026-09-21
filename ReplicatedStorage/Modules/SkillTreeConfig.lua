--[[
	SkillTreeConfig.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ReplicatedStorage > Modules > SkillTreeConfig   (ModuleScript)

	Define cada nodo del árbol de habilidades: su coste (en Puntos de
	Renacimiento), de qué otro nodo depende (`RequiredNode`, para formar
	ramas — `nil` significa "nodo raíz, sin requisito"), y qué tipo de
	efecto aplica (`EffectType`) con qué magnitud (`EffectValue`).

	Está en ReplicatedStorage porque el CLIENTE necesita esta tabla para
	DIBUJAR el árbol (nombres, costes, qué nodo depende de cuál). El
	efecto real (aplicar el descuento, la suerte extra, el límite de
	equipo) SIEMPRE se calcula en el servidor (ver BuffManager.lua) — el
	cliente solo la usa para pintar la UI y sabe qué nodo es su próximo
	paso lógico en cada rama.

	--------------------------------------------------------------------
	TIPOS DE EFECTO SOPORTADOS (ver BuffManager.lua para la matemática
	exacta de cómo se combinan/aplican):

		- "ButtonDiscount": descuento ADITIVO (0.05 = 5%) sobre el coste
		  de CUALQUIER botón del tycoon. Varios nodos de este tipo se
		  SUMAN (Discount_1 + Discount_2 = 10% total), con un techo
		  máximo fijado en BuffManager para que un botón nunca cueste 0.

		- "EggLuckBoost": tiradas EXTRA al abrir un huevo (se suma a la
		  tirada base +1 del Gamepass "x2 Luck" si lo tiene, quedándose
		  siempre con la más rara de todas las tiradas). EffectValue = 1
		  significa "una tirada extra por este nodo".

		- "MaxEquippedBoost": mascotas equipadas extra, sumado al límite
		  base y al bonus del Gamepass "+1 Equip" si lo tiene.
--]]

export type SkillEffectType = "ButtonDiscount" | "EggLuckBoost" | "MaxEquippedBoost"

export type SkillNode = {
	Id: string,
	Name: string,
	Cost: number, -- En Puntos de Renacimiento
	RequiredNode: string?, -- Id de otro nodo que debe estar desbloqueado antes (nil = nodo raíz)
	EffectType: SkillEffectType,
	EffectValue: number,
}

local Nodes: { [string]: SkillNode } = {
	-- Rama de descuentos en botones (regateo)
	Discount_1 = {
		Id = "Discount_1",
		Name = "Regateo I",
		Cost = 1,
		RequiredNode = nil,
		EffectType = "ButtonDiscount",
		EffectValue = 0.05, -- +5% de descuento
	},
	Discount_2 = {
		Id = "Discount_2",
		Name = "Regateo II",
		Cost = 3,
		RequiredNode = "Discount_1",
		EffectType = "ButtonDiscount",
		EffectValue = 0.05, -- +5% adicional (10% total con Discount_1)
	},
	Discount_3 = {
		Id = "Discount_3",
		Name = "Regateo III",
		Cost = 6,
		RequiredNode = "Discount_2",
		EffectType = "ButtonDiscount",
		EffectValue = 0.10, -- +10% adicional (20% total con toda la rama)
	},

	-- Rama de suerte en la eclosión
	Luck_1 = {
		Id = "Luck_1",
		Name = "Suerte del Cazador I",
		Cost = 2,
		RequiredNode = nil,
		EffectType = "EggLuckBoost",
		EffectValue = 1, -- +1 tirada extra
	},
	Luck_2 = {
		Id = "Luck_2",
		Name = "Suerte del Cazador II",
		Cost = 5,
		RequiredNode = "Luck_1",
		EffectType = "EggLuckBoost",
		EffectValue = 1, -- +1 tirada extra adicional
	},

	-- Rama de vínculo con mascotas (límite de equipo)
	Equip_1 = {
		Id = "Equip_1",
		Name = "Vínculo Extra",
		Cost = 4,
		RequiredNode = nil,
		EffectType = "MaxEquippedBoost",
		EffectValue = 1, -- +1 mascota equipada
	},
}

local SkillTreeConfig = {}
SkillTreeConfig.Nodes = Nodes

function SkillTreeConfig.Get(nodeId: string): SkillNode?
	return Nodes[nodeId]
end

return SkillTreeConfig
