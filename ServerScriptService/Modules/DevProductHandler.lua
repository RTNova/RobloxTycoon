--[[
	DevProductHandler.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ServerScriptService > Modules > DevProductHandler   (ModuleScript)

	RESPONSABILIDAD:
		Ser el ÚNICO punto del juego que asigna `MarketplaceService.ProcessReceipt`.
		Roblox solo permite UN callback activo para todo el juego — si dos
		scripts distintos intentan asignarlo, el segundo pisa al primero.
		Por eso este módulo no conoce la lógica de cada producto: expone
		`RegisterHandler(productId, fn)` para que OTROS módulos (paquetes
		de monedas, PetCloneService...) registren su propia función sin
		que este archivo tenga que saber nada de mascotas ni de clonación.

	--------------------------------------------------------------------
	POR QUÉ ES "A PRUEBA DE FALLOS" (nunca se pierde el Robux del jugador):

	`ProcessReceipt` DEBE devolver uno de dos valores:
		- `Enum.ProductPurchaseDecision.PurchaseGranted`: "ya le di su
		  recompensa, no me vuelvas a llamar con este PurchaseId".
		- `Enum.ProductPurchaseDecision.NotProcessedYet`: "todavía no pude
		  otorgarlo (el jugador no está, el DataStore falló, etc.) —
		  Roblox reintentará automáticamente más tarde (hasta 3 días),
		  incluida la posibilidad de que el jugador ya se haya
		  desconectado y vuelva a entrar".

	Este módulo devuelve `NotProcessedYet` en CUALQUIER punto donde algo
	pueda haber fallado sin haber otorgado la recompensa todavía — nunca
	asumimos que "seguro que funcionó". Y antes de ejecutar el handler de
	un producto, comprueba si ese `PurchaseId` YA fue otorgado
	(`DataManager.HasProcessedPurchase`), para que un reintento de Roblox
	(o una doble llamada por cualquier motivo) nunca duplique la recompensa.
--]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevProductConfig = require(ReplicatedStorage.Modules.DevProductConfig)

local DevProductHandler = {}

-- [productId] = function(player, receiptInfo): boolean (true = otorgado con éxito)
local productHandlers = {}

-- API pública: cualquier módulo puede registrar el handler de SU producto
-- sin que este archivo conozca su lógica interna.
function DevProductHandler.RegisterHandler(productId: number, handlerFn: (Player, any) -> boolean)
	productHandlers[productId] = handlerFn
end

-- Atajo para el caso más común: productos que simplemente dan una
-- cantidad fija de dinero (los "paquetes de monedas" de DevProductConfig).
-- Recorre automáticamente cualquier entrada de DevProductConfig que tenga
-- un campo `Amount`, así añadir un cuarto o quinto paquete de monedas en
-- el futuro NO requiere tocar este archivo, solo DevProductConfig.lua.
function DevProductHandler.RegisterMoneyPacks(DataManager)
	for _, def in pairs(DevProductConfig.DevProducts) do
		if def.Amount then
			DevProductHandler.RegisterHandler(def.Id, function(player, _receiptInfo)
				DataManager.AddMoney(player, def.Amount)
				return true
			end)
		end
	end
end

local function ProcessReceipt(receiptInfo, DataManager)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- El jugador no está en este servidor ahora mismo (se desconectó
		-- justo tras pagar, o el pago llegó con retraso). Roblox
		-- reintentará automáticamente más tarde, incluida una futura
		-- sesión: NUNCA se pierde el Robux por esto.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- El perfil (DataManager) puede tardar unos segundos en cargar justo
	-- al entrar. Si el pago llega ANTES de que termine de cargar, pedimos
	-- que se reintente en vez de arriesgarnos a escribir sobre datos que
	-- todavía no están listos.
	local data = DataManager.GetData(player)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Idempotencia: si este PurchaseId concreto YA fue otorgado antes
	-- (por ejemplo, Roblox reintentó tras un fallo posterior a la
	-- recompensa pero antes de poder confirmar), lo confirmamos sin
	-- volver a ejecutar el handler ni duplicar nada.
	local checkOk, alreadyProcessed = pcall(function()
		return DataManager.HasProcessedPurchase(player, tostring(receiptInfo.PurchaseId))
	end)

	if not checkOk then
		-- Fallo de DataStore al comprobar el historial: mejor reintentar
		-- más tarde que arriesgarnos a un doble-otorgamiento.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if alreadyProcessed then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local handler = productHandlers[receiptInfo.ProductId]
	if not handler then
		warn("[DevProductHandler] ProductId sin manejador registrado: " .. tostring(receiptInfo.ProductId))
		-- No es un fallo transitorio (nunca va a aparecer un handler solo),
		-- pero devolvemos NotProcessedYet igualmente: preferimos que quede
		-- "pendiente para siempre" y lo detectemos en los logs de Roblox
		-- (Analytics → Robux → Pending), antes que cobrar Robux sin dar nada.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- pcall alrededor del handler: si CUALQUIER cosa dentro de él lanza un
	-- error inesperado, lo tratamos igual que un fallo normal (reintentar),
	-- nunca dejamos que un error se "trague" el pago del jugador.
	local runOk, grantSuccess = pcall(handler, player, receiptInfo)
	if not runOk or not grantSuccess then
		warn(("[DevProductHandler] Fallo al otorgar el producto %s a %s."):format(
			tostring(receiptInfo.ProductId),
			player.Name
		))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- La recompensa YA se otorgó con éxito: marcamos el PurchaseId como
	-- procesado para blindarnos contra un reintento futuro duplicado.
	local markOk = pcall(function()
		DataManager.MarkPurchaseProcessed(player, tostring(receiptInfo.PurchaseId))
	end)

	if not markOk then
		-- Caso límite: la recompensa se otorgó pero no pudimos marcarlo.
		-- Devolver NotProcessedYet aquí volvería a ejecutar el handler en
		-- el reintento (doble recompensa) — peor que el riesgo contrario.
		-- Por eso confirmamos igualmente: es preferible, en este punto
		-- concreto del flujo, arriesgar un fallo de marcado silencioso
		-- (quedaría registrado en el warn) que arriesgar un otorgamiento
		-- duplicado de la recompensa.
		warn("[DevProductHandler] Recompensa otorgada pero no se pudo marcar como procesada: " .. tostring(receiptInfo.PurchaseId))
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function DevProductHandler.Init(DataManager)
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		return ProcessReceipt(receiptInfo, DataManager)
	end
end

return DevProductHandler
