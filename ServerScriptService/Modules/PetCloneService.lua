--[[
	PetCloneService.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ServerScriptService > Modules > PetCloneService   (ModuleScript)

	FLUJO COMPLETO:

		1. Jugador A (comprador) dispara "RequestClonePet" con
		   (targetUserId, targetUUID): a quién y qué mascota quiere clonar.
		2. El SERVIDOR valida que el jugador objetivo siga en el servidor
		   y que esa mascota siga existiendo en su inventario AHORA MISMO.
		3. Si es válido, el servidor guarda la solicitud en el PROPIO
		   perfil del comprador (DataManager.SetPendingClone) — persistida
		   en el DataStore, no solo en memoria — y ENTONCES lanza el
		   prompt de compra (`PromptProductPurchase`).
		4. Cuando `ProcessReceipt` confirma el pago (puede ser al momento,
		   o en una sesión futura si el jugador se desconectó justo tras
		   pagar), `PetCloneService.GrantClone` lee esa solicitud guardada,
		   clona la mascota preservando su `OriginalOwnerName`/`Id`
		   ORIGINAL, y recompensa al dueño actual con monedas gratis.

	--------------------------------------------------------------------
	POR QUÉ EL SERVIDOR INICIA EL PROMPT DE COMPRA (Y NO EL CLIENTE
	DIRECTAMENTE, COMO EN LOS PAQUETES DE MONEDAS):

	Para un paquete de monedas, el cliente puede llamar
	`MarketplaceService:PromptProductPurchase` directamente — no hay nada
	que validar de antemano. Pero clonar SIEMPRE depende de un objetivo
	concreto (qué jugador, qué mascota) que puede dejar de ser válido en
	cualquier momento (el jugador se desconecta, la mascota ya no existe).
	Si dejáramos que el cliente lanzara el prompt directamente y solo
	validáramos al cobrar, un jugador podría PAGAR por un clon que ya no
	se puede completar. Validando ANTES de mostrar el prompt (aquí, en
	`RequestClonePet`), nos aseguramos de que el jugador solo ve la
	ventana de pago de Roblox cuando la clonación es, en ese instante,
	realizable.

	--------------------------------------------------------------------
	LÍMITE ACEPTADO DEL DISEÑO: si el jugador objetivo se desconecta
	DESPUÉS de validar pero ANTES de que `ProcessReceipt` confirme el
	pago (una ventana de tiempo normalmente de segundos), no podemos leer
	su inventario en vivo en una sesión futura (ProfileService no permite
	dos sesiones simultáneas del mismo perfil, y no queremos arriesgarnos
	a corromper datos abriendo una sesión de lectura paralela). En ese
	caso concreto, compensamos al comprador con monedas en vez de dejar
	la solicitud pendiente para siempre — ver `GrantClone` más abajo.
--]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevProductConfig = require(ReplicatedStorage.Modules.DevProductConfig)

local PetCloneService = {}

-- Monedas gratis que recibe el dueño ACTUAL de la mascota cuando alguien
-- paga por clonarla — la parte "social" de la monetización: cuanto más
-- deseable sea tu mascota para otros, más te compensa mantenerla equipada
-- y visible.
local CLONE_REWARD_AMOUNT = 500

-- ========================================================================
-- PASO 1-3: Solicitud del comprador + validación + prompt de compra.
-- ========================================================================
function PetCloneService.Init(DataManager)
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	local requestClonePet = remotesFolder:WaitForChild("RequestClonePet") -- RemoteEvent: (targetUserId, targetUUID)
	local cloneResult = remotesFolder:WaitForChild("CloneResult") -- RemoteEvent → comprador

	requestClonePet.OnServerEvent:Connect(function(buyer, targetUserId, targetUUID)
		-- Validación de tipos estricta: nunca confiar en lo que manda el cliente.
		if typeof(targetUserId) ~= "number" or typeof(targetUUID) ~= "string" then
			return
		end

		local targetPlayer = Players:GetPlayerByUserId(targetUserId)
		if not targetPlayer then
			cloneResult:FireClient(buyer, { Success = false, Reason = "Ese jugador ya no está en el servidor." })
			return
		end

		-- No tiene sentido "comprar" tu propia mascota: la tienes ya.
		if targetPlayer == buyer then
			cloneResult:FireClient(buyer, { Success = false, Reason = "No puedes clonar tu propia mascota." })
			return
		end

		local targetData = DataManager.GetData(targetPlayer)
		local sourcePet = targetData and targetData.Pets[targetUUID]
		if not sourcePet then
			cloneResult:FireClient(buyer, { Success = false, Reason = "Esa mascota ya no existe." })
			return
		end

		-- Guardamos la solicitud ANTES de lanzar el prompt: si el pago se
		-- confirma en una sesión futura (el comprador se desconecta justo
		-- tras pagar), ProcessReceipt necesita poder leer esto igualmente.
		DataManager.SetPendingClone(buyer, {
			TargetUserId = targetUserId,
			TargetUUID = targetUUID,
		})

		local devProduct = DevProductConfig.Get("PetCloneFee")
		MarketplaceService:PromptProductPurchase(buyer, devProduct.Id)
	end)
end

-- ========================================================================
-- PASO 4: Otorgar el clon tras el pago confirmado. Se registra en
-- DevProductHandler como el handler del producto "PetCloneFee" (ver
-- Main.server.lua). Devuelve true/false: false hace que DevProductHandler
-- devuelva NotProcessedYet y Roblox reintente más tarde — el Robux del
-- jugador NUNCA se pierde aunque este paso falle.
-- ========================================================================
function PetCloneService.GrantClone(buyer: Player, receiptInfo, DataManager, InventoryService): boolean
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	local cloneResult = remotesFolder:WaitForChild("CloneResult")
	local cloneNotification = remotesFolder:WaitForChild("CloneNotification") -- RemoteEvent → dueño original

	local pending = DataManager.GetPendingClone(buyer)

	if not pending then
		-- Caso límite documentado en la cabecera: el Robux YA se cobró,
		-- pero no encontramos ninguna solicitud guardada (por ejemplo, se
		-- limpió por algún otro camino). Compensamos en vez de dejar al
		-- jugador sin nada y sin reintentar para siempre.
		warn(("[PetCloneService] PurchaseId %s sin PendingClone: compensando a %s."):format(
			tostring(receiptInfo.PurchaseId),
			buyer.Name
		))
		DataManager.AddMoney(buyer, CLONE_REWARD_AMOUNT)
		return true
	end

	local targetPlayer = Players:GetPlayerByUserId(pending.TargetUserId)
	if not targetPlayer then
		-- El jugador objetivo ya no está en este servidor (ver "Límite
		-- aceptado del diseño" en la cabecera). Compensamos al comprador.
		DataManager.ClearPendingClone(buyer)
		DataManager.AddMoney(buyer, CLONE_REWARD_AMOUNT)
		cloneResult:FireClient(buyer, {
			Success = false,
			Reason = "El otro jugador se desconectó antes de completarse el pago. Se te compensó con monedas.",
		})
		return true
	end

	local targetData = DataManager.GetData(targetPlayer)
	local sourcePet = targetData and targetData.Pets[pending.TargetUUID]
	if not sourcePet then
		-- La mascota dejó de existir entre la solicitud y el pago
		-- confirmado (poco probable sin sistema de venta, pero contemplado).
		DataManager.ClearPendingClone(buyer)
		DataManager.AddMoney(buyer, CLONE_REWARD_AMOUNT)
		cloneResult:FireClient(buyer, {
			Success = false,
			Reason = "Esa mascota ya no existe. Se te compensó con monedas.",
		})
		return true
	end

	-- CLON REAL: misma especie y variante que la fuente, pero preservando
	-- el OriginalOwnerName/Id de quien la eclosionó la PRIMERA vez — NUNCA
	-- el del comprador, ni el del dueño actual si este a su vez la obtuvo
	-- por clonación (sourcePet.OriginalOwnerName ya viene heredado en
	-- cadena desde AddClonedPet/AddPet).
	local newUUID = DataManager.AddClonedPet(
		buyer,
		sourcePet.PetId,
		sourcePet.Variant,
		sourcePet.OriginalOwnerName,
		sourcePet.OriginalOwnerId
	)

	-- Recompensa social: el dueño ACTUAL (targetPlayer, quien tenía la
	-- mascota en el momento de la venta) recibe monedas gratis + una
	-- notificación, independientemente de quién la eclosionara originalmente.
	DataManager.AddMoney(targetPlayer, CLONE_REWARD_AMOUNT)
	cloneNotification:FireClient(targetPlayer, {
		ClonerName = buyer.Name,
		PetId = sourcePet.PetId,
		RewardAmount = CLONE_REWARD_AMOUNT,
	})

	cloneResult:FireClient(buyer, {
		Success = true,
		PetId = sourcePet.PetId,
		UUID = newUUID,
	})

	DataManager.ClearPendingClone(buyer)
	InventoryService.NotifyChanged(buyer)

	return true
end

return PetCloneService
