--[[
	DataManager.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		ServerScriptService > Modules > DataManager  (ModuleScript)

	DEPENDENCIA EXTERNA REQUERIDA:
		Este módulo asume que ya tienes instalado "ProfileService" (de loleris),
		la librería estándar de la comunidad para guardado de datos robusto
		(maneja sesiones, reintentos, corrupción de datos, etc. mejor que
		usar DataStoreService "a pelo").

		1. Descárgalo del modelo oficial en el Toolbox de Roblox Studio
		   (busca "ProfileService" by loleris) o desde su repositorio de GitHub.
		2. Colócalo como ModuleScript directamente dentro de:
		       ServerScriptService > ProfileService
		   (es decir, como HERMANO de la carpeta "Modules", NO dentro de ella).

	RESPONSABILIDAD DE ESTE MÓDULO:
		- Definir la plantilla de datos por defecto de cada jugador.
		- Cargar y liberar "profiles" (perfiles) cuando el jugador entra/sale.
		- Exponer funciones seguras para leer y modificar Money, Gems,
		  los botones comprados (PurchasedButtons) y el INVENTARIO DE
		  MASCOTAS (Pets/EquippedPets).
		- Mantener un caché en memoria (Profiles[player]) para que el resto
		  de servicios (ButtonService, IncomeManager, EggService,
		  MultiplierManager) puedan leer/escribir datos de forma instantánea
		  sin golpear el DataStore constantemente.

	ACTUALIZACIÓN (Pet Simulator): cada mascota se guarda como una entrada
	en el diccionario "Pets", indexada por un UUID único generado con
	HttpService:GenerateGUID(). Usar un UUID como clave (en vez de un array)
	evita colisiones y hace que buscar/quitar una mascota concreta sea O(1)
	en vez de tener que recorrer un array entero.
--]]

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")

-- Requerimos la librería externa ProfileService (ver instrucciones arriba)
local ProfileService = require(ServerScriptService:WaitForChild("ProfileService"))

local DataManager = {}

-- Caché en memoria: [player] = profile
DataManager.Profiles = {}

-- Plantilla de datos por defecto. Si un jugador es nuevo, se le clona esta tabla.
local PROFILE_TEMPLATE = {
	Money = 0,
	Gems = 0, -- Divisa premium (Robux/GamePasses). Déjalo en 0 si tu juego no la usa.
	PurchasedButtons = {}, -- Diccionario: { [ButtonId] = true }
	TycoonId = nil, -- Qué plot/tycoon tiene reclamado el jugador (se rellena en runtime)

	-- Diccionario de mascotas en propiedad del jugador.
	-- Clave = UUID único de ESA copia concreta de la mascota (permite tener
	-- dos veces la misma mascota como entradas independientes).
	-- Valor = { PetId = "PetId_del_PetsConfig", Equipped = false }
	Pets = {},

	-- ACTUALIZACIÓN — Núcleo Central (acumulación abstracta, sin droppers
	-- físicos): el dinero generado por los generadores del tycoon se suma
	-- aquí como "dinero pendiente" antes de que el jugador lo recolecte
	-- tocando el Núcleo. Se persiste en el DataStore para que, si el
	-- servidor se cae o el jugador sale, no pierda el progreso acumulado.
	Core = {
		PendingMoney = 0,
	},

	-- Skin visual del Núcleo elegida por el jugador (ver SkinsConfig.lua).
	-- Se restaura automáticamente al reclamar el tycoon (SkinController.ApplySavedSkin).
	SelectedSkin = "Default",

	-- ACTUALIZACIÓN — Monetización (DevProducts):
	-- Diccionario de PurchaseId de Roblox YA otorgados, para que
	-- DevProductHandler nunca pueda dar una recompensa dos veces si
	-- ProcessReceipt se reintenta (por ejemplo, tras un fallo de guardado
	-- justo después de otorgar la recompensa pero antes de confirmar).
	ProcessedPurchaseIds = {},

	-- Solicitud de clonación de mascota EN CURSO (o `false` si no hay
	-- ninguna). Se guarda en el DataStore (no solo en memoria) porque el
	-- pago puede completarse en una sesión FUTURA del jugador si cierra
	-- el juego justo tras pagar: ProcessReceipt necesita poder leer QUÉ
	-- mascota pidió clonar aunque haya pasado por una desconexión.
	PendingClone = false,

	-- ACTUALIZACIÓN — Rebirth (Renacimiento) y Árbol de Habilidades:
	-- Los Puntos de Renacimiento son la divisa del Skill Tree. Nunca se
	-- resetean al renacer (todo lo contrario: renacer es como se ganan).
	RebirthPoints = 0,

	-- Diccionario de nodos del Skill Tree ya desbloqueados: { [nodeId] = true }.
	-- Tampoco se resetea al renacer — los buffos del árbol son permanentes.
	UnlockedSkills = {},
}

-- "ProfileStore" es el almacén real de DataStoreService gestionado por ProfileService.
-- El nombre "PlayerData_v1" es la KEY del DataStore: cámbialo (v2, v3...) SOLO si
-- quieres resetear a todos los jugadores (útil si cambias la estructura de datos
-- de forma incompatible en el futuro).
local ProfileStore = ProfileService.GetProfileStore("PlayerData_v1", PROFILE_TEMPLATE)

-- ========================================================================
-- CARGA DE PERFIL (llamar en Players.PlayerAdded)
-- ========================================================================
function DataManager.LoadProfile(player: Player)
	-- ":Reconcile()" en OnLoad rellena claves nuevas que no existían cuando
	-- el jugador guardó por última vez (por ejemplo, si añades "Gems" más adelante).
	local profile = ProfileStore:LoadProfileAsync("Player_" .. player.UserId)

	if profile == nil then
		-- No se pudo cargar (otro servidor tiene la sesión, DataStore caído, etc.)
		player:Kick("No se pudieron cargar tus datos. Vuelve a entrar en unos segundos.")
		return
	end

	profile:AddUserId(player.UserId) -- Permite borrado de datos por GDPR/compliance
	profile:Reconcile() -- Rellena valores por defecto que falten

	-- Si el jugador se va antes de que termine de cargar, liberamos el perfil.
	profile:ListenToRelease(function()
		DataManager.Profiles[player] = nil
		player:Kick("Tu sesión de datos se cerró en otro servidor.")
	end)

	if player:IsDescendantOf(Players) then
		DataManager.Profiles[player] = profile
		DataManager.CreateLeaderstats(player, profile)
		DataManager.CreateCoreReplication(player, profile)
	else
		-- El jugador salió mientras cargábamos: liberamos inmediatamente.
		profile:Release()
	end
end

-- ========================================================================
-- LIBERACIÓN DE PERFIL (llamar en Players.PlayerRemoving)
-- ========================================================================
function DataManager.ReleaseProfile(player: Player)
	local profile = DataManager.Profiles[player]
	if profile ~= nil then
		profile:Release() -- Esto dispara ListenToRelease y guarda los datos
	end
end

-- ========================================================================
-- LEADERSTATS: usamos IntValue/NumberValue dentro de "leaderstats" porque
-- Roblox los replica automáticamente al cliente (Money/Gems visibles en la
-- UI sin necesidad de RemoteEvents extra para mostrar el saldo).
-- ========================================================================
function DataManager.CreateLeaderstats(player: Player, profile)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local money = Instance.new("IntValue")
	money.Name = "Money"
	money.Value = profile.Data.Money
	money.Parent = leaderstats

	local gems = Instance.new("IntValue")
	gems.Name = "Gems"
	gems.Value = profile.Data.Gems
	gems.Parent = leaderstats

	local rebirthPoints = Instance.new("IntValue")
	rebirthPoints.Name = "RebirthPoints"
	rebirthPoints.Value = profile.Data.RebirthPoints
	rebirthPoints.Parent = leaderstats

	leaderstats.Parent = player
end

-- ========================================================================
-- CORE DATA: igual que "leaderstats", pero para valores que NO queremos
-- mostrar en la lista de jugadores (PendingMoney, IncomeRate). Vive en una
-- carpeta separada "CoreData" dentro del Player, y se replica solo para
-- que CoreVisuals.client.lua pueda leerlo sin necesidad de RemoteEvents.
-- ========================================================================
function DataManager.CreateCoreReplication(player: Player, profile)
	local coreData = Instance.new("Folder")
	coreData.Name = "CoreData"

	local pendingMoney = Instance.new("NumberValue")
	pendingMoney.Name = "PendingMoney"
	pendingMoney.Value = profile.Data.Core.PendingMoney
	pendingMoney.Parent = coreData

	-- Dinero/segundo YA multiplicado por el bono de mascotas. Solo se usa
	-- como referencia visual (velocidad de parpadeo); no es lo que se guarda
	-- en el DataStore, así que no necesita persistir entre sesiones.
	local incomeRate = Instance.new("NumberValue")
	incomeRate.Name = "IncomeRate"
	incomeRate.Value = 0
	incomeRate.Parent = coreData

	coreData.Parent = player
end

-- ========================================================================
-- API pública de lectura/escritura usada por ButtonService e IncomeManager
-- ========================================================================

-- Devuelve el profile.Data de un jugador, o nil si aún no ha cargado.
function DataManager.GetData(player: Player)
	local profile = DataManager.Profiles[player]
	return profile and profile.Data or nil
end

-- Suma (o resta, con número negativo) dinero y sincroniza el leaderstat.
function DataManager.AddMoney(player: Player, amount: number)
	local data = DataManager.GetData(player)
	if not data then return end

	data.Money += amount

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		leaderstats.Money.Value = data.Money
	end
end

-- Intenta gastar dinero. Devuelve true si había saldo suficiente y se descontó.
-- Esta es la función CLAVE de seguridad: todo gasto pasa por aquí en el servidor.
function DataManager.TrySpendMoney(player: Player, amount: number): boolean
	local data = DataManager.GetData(player)
	if not data then return false end

	if data.Money >= amount then
		DataManager.AddMoney(player, -amount)
		return true
	end

	return false
end

-- Marca un botón como comprado en los datos guardados.
function DataManager.MarkButtonPurchased(player: Player, buttonId: string)
	local data = DataManager.GetData(player)
	if not data then return end

	data.PurchasedButtons[buttonId] = true
end

-- Comprueba si un botón ya fue comprado (para restaurar el estado al entrar).
function DataManager.HasPurchasedButton(player: Player, buttonId: string): boolean
	local data = DataManager.GetData(player)
	if not data then return false end

	return data.PurchasedButtons[buttonId] == true
end

-- ========================================================================
-- INVENTARIO DE MASCOTAS (Pet Simulator)
-- ========================================================================

-- Añade una mascota nueva al inventario del jugador. Genera un UUID propio
-- para esa copia concreta (así el jugador puede tener 5 copias del mismo
-- PetId sin que se pisen entre sí). Devuelve el UUID generado.
-- SOLO debe ser llamada desde el servidor (EggService), nunca a partir de
-- un valor que venga directamente del cliente.
--
-- ACTUALIZACIÓN — Firma de procedencia (Original Owner):
-- Guardamos de forma PERMANENTE quién eclosionó esta copia por primera
-- vez (OriginalOwnerName/OriginalOwnerId). Estos dos campos se escriben
-- UNA SOLA VEZ, aquí, en el momento de creación, y ningún otro módulo
-- (ni siquiera un futuro sistema de trading) debería sobreescribirlos:
-- son un dato histórico, no el dueño ACTUAL de la mascota.
function DataManager.AddPet(player: Player, petId: string, variant: string?): string?
	local data = DataManager.GetData(player)
	if not data then return nil end

	local uuid = HttpService:GenerateGUID(false)

	data.Pets[uuid] = {
		PetId = petId,
		Variant = variant or "Normal",
		Equipped = false,

		-- Firma de procedencia: permanente, no se toca nunca más.
		OriginalOwnerName = player.Name,
		OriginalOwnerId = player.UserId,
	}

	return uuid
end

-- Variante de AddPet usada EXCLUSIVAMENTE por el sistema de clonación
-- (PetCloneService). La diferencia clave: NO estampa a `player` (el
-- comprador) como procedencia — recibe explícitamente el
-- OriginalOwnerName/Id de la mascota FUENTE, para que la copia preserve
-- quién la eclosionó de verdad la primera vez, tal y como pide el diseño
-- ("el comprador recibe una copia manteniendo el OriginalOwnerName").
function DataManager.AddClonedPet(
	player: Player,
	petId: string,
	variant: string?,
	originalOwnerName: string,
	originalOwnerId: number
): string?
	local data = DataManager.GetData(player)
	if not data then return nil end

	local uuid = HttpService:GenerateGUID(false)

	data.Pets[uuid] = {
		PetId = petId,
		Variant = variant or "Normal",
		Equipped = false,

		-- Procedencia HEREDADA de la mascota original, no del comprador.
		OriginalOwnerName = originalOwnerName,
		OriginalOwnerId = originalOwnerId,
	}

	return uuid
end

-- Quita una mascota del inventario (por ejemplo, para un sistema de fusión
-- o venta que quieras añadir más adelante).
function DataManager.RemovePet(player: Player, uuid: string)
	local data = DataManager.GetData(player)
	if not data then return end

	data.Pets[uuid] = nil
end

-- Cambia el estado "Equipped" de una mascota concreta. Devuelve false si el
-- UUID no existe en el inventario de ESE jugador (protección anti-exploit:
-- un jugador no puede equipar una mascota que no sea suya).
function DataManager.SetPetEquipped(player: Player, uuid: string, equipped: boolean): boolean
	local data = DataManager.GetData(player)
	if not data then return false end

	local pet = data.Pets[uuid]
	if not pet then return false end

	pet.Equipped = equipped
	return true
end

-- Devuelve una lista (array) de las entradas COMPLETAS de mascota
-- actualmente equipadas (incluye UUID, PetId, Variant, OriginalOwnerName,
-- OriginalOwnerId...). La usa MultiplierManager (para calcular el poder
-- vía PetManager:CalculatePetPower) y la UI de "mascota equipada".
function DataManager.GetEquippedPets(player: Player)
	local data = DataManager.GetData(player)
	if not data then return {} end

	local equipped = {}
	for uuid, pet in pairs(data.Pets) do
		if pet.Equipped then
			local entry = table.clone(pet)
			entry.UUID = uuid
			table.insert(equipped, entry)
		end
	end

	return equipped
end

-- ========================================================================
-- NÚCLEO CENTRAL (acumulación abstracta de dinero — sin droppers físicos)
-- ========================================================================

-- Suma dinero PENDIENTE (todavía no cobrado) al Núcleo del jugador.
-- La llama IncomeManager en su bucle principal, una vez por tick, con el
-- importe ya multiplicado por el bono de mascotas.
-- "currentRate" es opcional: si se pasa, también actualiza el NumberValue
-- "IncomeRate" que usa el cliente para decidir la velocidad de parpadeo.
function DataManager.AddPendingMoney(player: Player, amount: number, currentRate: number?)
	local data = DataManager.GetData(player)
	if not data then return end

	data.Core.PendingMoney += amount

	local coreData = player:FindFirstChild("CoreData")
	if coreData then
		coreData.PendingMoney.Value = data.Core.PendingMoney
		if currentRate then
			coreData.IncomeRate.Value = currentRate
		end
	end
end

-- Convierte TODO el dinero pendiente del Núcleo en dinero real (Money),
-- y resetea el pendiente a 0. Se llama cuando el jugador toca el Núcleo.
-- Devuelve la cantidad recolectada (útil para un mensaje de UI tipo "+1,240$").
function DataManager.CollectPendingMoney(player: Player): number
	local data = DataManager.GetData(player)
	if not data then return 0 end

	local amount = data.Core.PendingMoney
	if amount <= 0 then return 0 end

	data.Core.PendingMoney = 0
	DataManager.AddMoney(player, amount) -- Reutiliza la función existente (ya sincroniza leaderstats)

	local coreData = player:FindFirstChild("CoreData")
	if coreData then
		coreData.PendingMoney.Value = 0
	end

	return amount
end

-- Solo lectura, útil si algún otro sistema necesita saber cuánto hay
-- pendiente sin pasar por el NumberValue replicado (por ejemplo, lógica
-- puramente de servidor).
function DataManager.GetPendingMoney(player: Player): number
	local data = DataManager.GetData(player)
	return data and data.Core.PendingMoney or 0
end

-- ========================================================================
-- SKINS DEL NÚCLEO
-- ========================================================================

function DataManager.SetSelectedSkin(player: Player, skinId: string)
	local data = DataManager.GetData(player)
	if not data then return end

	data.SelectedSkin = skinId
end

function DataManager.GetSelectedSkin(player: Player): string
	local data = DataManager.GetData(player)
	return data and data.SelectedSkin or "Default"
end

-- ========================================================================
-- MONETIZACIÓN — IDEMPOTENCIA DE COMPRAS (DevProducts)
-- ========================================================================

-- Comprueba si un PurchaseId concreto YA fue otorgado a este jugador.
-- DevProductHandler la usa ANTES de ejecutar el handler de un producto,
-- para no volver a dar la recompensa si ProcessReceipt se reintenta.
function DataManager.HasProcessedPurchase(player: Player, purchaseId: string): boolean
	local data = DataManager.GetData(player)
	if not data then return false end

	return data.ProcessedPurchaseIds[purchaseId] == true
end

-- Marca un PurchaseId como YA otorgado. Se llama SOLO después de que el
-- handler del producto haya tenido éxito.
function DataManager.MarkPurchaseProcessed(player: Player, purchaseId: string)
	local data = DataManager.GetData(player)
	if not data then return end

	data.ProcessedPurchaseIds[purchaseId] = true
end

-- ========================================================================
-- MONETIZACIÓN — CLONACIÓN SOCIAL DE MASCOTAS
-- ========================================================================

-- Registra una solicitud de clonación EN CURSO para el comprador, justo
-- antes de lanzar el prompt de compra del DevProduct. Persistida en el
-- DataStore (no en una tabla en memoria) para sobrevivir a una posible
-- desconexión entre el momento de pedir el clon y el momento en que
-- Roblox confirma el pago.
function DataManager.SetPendingClone(player: Player, requestData: { TargetUserId: number, TargetUUID: string })
	local data = DataManager.GetData(player)
	if not data then return end

	data.PendingClone = requestData
end

-- Devuelve la solicitud de clonación en curso del jugador, o nil si no hay ninguna.
function DataManager.GetPendingClone(player: Player)
	local data = DataManager.GetData(player)
	if not data or data.PendingClone == false then return nil end

	return data.PendingClone
end

-- Limpia la solicitud tras completarla (con éxito o compensada).
function DataManager.ClearPendingClone(player: Player)
	local data = DataManager.GetData(player)
	if not data then return end

	data.PendingClone = false
end

-- ========================================================================
-- REBIRTH (RENACIMIENTO)
-- ========================================================================

-- Suma Puntos de Renacimiento (nunca se restan salvo por el propio Skill
-- Tree al gastarlos) y sincroniza el leaderstat.
function DataManager.AddRebirthPoints(player: Player, amount: number)
	local data = DataManager.GetData(player)
	if not data then return end

	data.RebirthPoints += amount

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		leaderstats.RebirthPoints.Value = data.RebirthPoints
	end
end

function DataManager.GetRebirthPoints(player: Player): number
	local data = DataManager.GetData(player)
	return data and data.RebirthPoints or 0
end

-- Intenta gastar Puntos de Renacimiento (para desbloquear un nodo del
-- Skill Tree). Misma forma que TrySpendMoney: único punto de gasto,
-- validación 100% en servidor.
function DataManager.TrySpendRebirthPoints(player: Player, amount: number): boolean
	local data = DataManager.GetData(player)
	if not data then return false end

	if data.RebirthPoints >= amount then
		DataManager.AddRebirthPoints(player, -amount)
		return true
	end

	return false
end

-- Reset SEGURO y SELECTIVO para el Renacimiento: reinicia ÚNICAMENTE
-- Money y PurchasedButtons. Deliberadamente NO toca: Pets, Core
-- (PendingMoney), Gems, SelectedSkin, ProcessedPurchaseIds, PendingClone,
-- RebirthPoints ni UnlockedSkills — el Rebirth solo reinicia "el progreso
-- de este ciclo de tycoon", nunca las mascotas ni los buffos permanentes.
function DataManager.ResetForRebirth(player: Player)
	local data = DataManager.GetData(player)
	if not data then return end

	data.Money = 0
	data.PurchasedButtons = {}

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		leaderstats.Money.Value = 0
	end
end

-- ========================================================================
-- ÁRBOL DE HABILIDADES (SKILL TREE)
-- ========================================================================

function DataManager.HasUnlockedSkill(player: Player, nodeId: string): boolean
	local data = DataManager.GetData(player)
	if not data then return false end

	return data.UnlockedSkills[nodeId] == true
end

function DataManager.UnlockSkill(player: Player, nodeId: string)
	local data = DataManager.GetData(player)
	if not data then return end

	data.UnlockedSkills[nodeId] = true
end

-- Devuelve el diccionario completo de nodos desbloqueados. La usa
-- BuffManager para recalcular todos los efectos activos del jugador.
function DataManager.GetUnlockedSkills(player: Player): { [string]: boolean }
	local data = DataManager.GetData(player)
	return data and data.UnlockedSkills or {}
end

return DataManager
