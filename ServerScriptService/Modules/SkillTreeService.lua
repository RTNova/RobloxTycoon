--[[
	SkillTreeService.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ServerScriptService > Modules > SkillTreeService   (ModuleScript)

	RESPONSABILIDAD:
		Validar y procesar la petición del cliente para desbloquear un
		nodo del Skill Tree: existencia del nodo, dependencia (`RequiredNode`)
		ya desbloqueada, coste en Puntos de Renacimiento suficiente, y que
		no esté ya desbloqueado (evita "comprarlo" dos veces y duplicar su
		efecto en BuffManager).

	POR QUÉ ES SEGURO:
		El cliente solo envía un `nodeId` (string). Todo lo demás —qué
		nodo existe, de qué depende, cuánto cuesta, cuántos puntos tiene
		el jugador— se valida y se lee EXCLUSIVAMENTE del lado del
		servidor (SkillTreeConfig + DataManager). Es el mismo patrón que
		EggService o ButtonService: el cliente pide, el servidor decide.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SkillTreeConfig = require(ReplicatedStorage.Modules.SkillTreeConfig)

local SkillTreeService = {}

function SkillTreeService.Init(DataManager, BuffManager)
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	local requestUnlockSkill = remotesFolder:WaitForChild("RequestUnlockSkill") -- RemoteEvent: (nodeId: string)
	local skillTreeUpdated = remotesFolder:WaitForChild("SkillTreeUpdated") -- RemoteEvent

	requestUnlockSkill.OnServerEvent:Connect(function(player, nodeId)
		-- Validación de tipo estricta: nunca confiar en lo que manda el cliente.
		if typeof(nodeId) ~= "string" then return end

		local node = SkillTreeConfig.Get(nodeId)
		if not node then
			warn(("[SkillTreeService] %s intentó desbloquear un nodo inexistente: %s"):format(player.Name, nodeId))
			return
		end

		-- Ya desbloqueado: ignorar. Esto NO es solo una optimización — es
		-- lo que impide que el jugador "compre" el mismo nodo varias veces
		-- y duplique su EffectValue en BuffManager.Recalculate.
		if DataManager.HasUnlockedSkill(player, nodeId) then
			return
		end

		-- Dependencia de rama: si este nodo requiere otro, ese otro debe
		-- estar desbloqueado PRIMERO.
		if node.RequiredNode and not DataManager.HasUnlockedSkill(player, node.RequiredNode) then
			skillTreeUpdated:FireClient(player, {
				Success = false,
				NodeId = nodeId,
				Reason = "Antes debes desbloquear: " .. node.RequiredNode,
			})
			return
		end

		-- Único punto de gasto: validación 100% en servidor, mismo patrón
		-- que DataManager.TrySpendMoney.
		local paid = DataManager.TrySpendRebirthPoints(player, node.Cost)
		if not paid then
			skillTreeUpdated:FireClient(player, {
				Success = false,
				NodeId = nodeId,
				Reason = "No tienes suficientes Puntos de Renacimiento.",
			})
			return
		end

		DataManager.UnlockSkill(player, nodeId)

		-- El nodo cambió: recalculamos TODOS los buffos combinados del
		-- jugador (no solo el de este nodo), para que ButtonDiscount,
		-- EggLuckBoost y MaxEquippedBoost queden consistentes de inmediato.
		BuffManager.Recalculate(player, DataManager)

		skillTreeUpdated:FireClient(player, { Success = true, NodeId = nodeId })
	end)
end

return SkillTreeService
