--[[
	InventoryController.lua
	--------------------------------------------------------------------
	Ubicación en Roblox Studio:
		StarterPlayer > StarterPlayerScripts > Controllers > InventoryController
		(ModuleScript)

	RESPONSABILIDAD:
		- Pedir al servidor el inventario completo del jugador (vía
		  RemoteFunction `GetPetInventory`) y volcarlo en un `UIGridLayout`.
		- Gestionar qué tarjeta está seleccionada (resaltado visual) y
		  mantener sincronizado el panel lateral de estadísticas con esa
		  selección.
		- Escuchar `InventoryUpdated` (RemoteEvent) para refrescarse solo
		  cuando el servidor confirma un cambio real (nueva mascota,
		  equipar/desequipar) — nunca adivinamos el resultado en el
		  cliente antes de que el servidor lo confirme.

	--------------------------------------------------------------------
	JERARQUÍA DE UI ESPERADA (constrúyela en Studio con estos nombres
	EXACTOS; son los que este script busca con WaitForChild):

		PlayerGui
		└── MainHUD (ScreenGui)
		    └── InventoryFrame (Frame)
		        ├── GridContainer (ScrollingFrame, con UIGridLayout)
		        │   └── PetCardTemplate (ImageButton) — plantilla, Visible = false
		        │       ├── UIStroke (Enabled = false por defecto: marca "seleccionada")
		        │       ├── RarityColorFrame (Frame)
		        │       ├── PetNameLabel (TextLabel)
		        │       └── EquippedIcon (ImageLabel, Visible = false por defecto)
		        └── StatsPanel (Frame)
		            ├── PetViewport (ViewportFrame)          <- Ver PetViewportController
		            ├── NameLabel (TextLabel)
		            ├── RarityLabel (TextLabel)
		            ├── ElementLabel (TextLabel)
		            ├── BaseMultiplierLabel (TextLabel)
		            ├── VariantBonusLabel (TextLabel)
		            ├── TotalMultiplierLabel (TextLabel)
		            ├── OriginalOwnerLabel (TextLabel)
		            └── EquipButton (TextButton)

	--------------------------------------------------------------------
	OPTIMIZACIÓN — REPOBLACIÓN POR DIFERENCIAS ("diff"):

		Cada vez que el inventario cambia, NO destruimos y recreamos todas
		las tarjetas del grid (eso provocaría un parpadeo visible y
		presión de recolector de basura innecesaria si el jugador tiene
		cientos de mascotas). En su lugar, `Populate` compara la lista
		nueva contra `cardsByUUID` (nuestro caché local) y solo:
			- CREA una tarjeta para cada UUID nuevo que no existía.
			- ACTUALIZA la tarjeta de un UUID que ya existía (por ejemplo,
			  cambió su estado "Equipada").
			- DESTRUYE la tarjeta de un UUID que ya no está en la lista
			  (poco común sin sistema de venta/trading, pero queda
			  preparado para cuando lo añadas).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetsConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PetsConfig"))
local PetManager = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PetManager"))
local AudioManager = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AudioManager"))

local InventoryController = {}

local player = Players.LocalPlayer
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local getPetInventory = remotesFolder:WaitForChild("GetPetInventory") -- RemoteFunction
local inventoryUpdated = remotesFolder:WaitForChild("InventoryUpdated") -- RemoteEvent
local requestEquipPet = remotesFolder:WaitForChild("RequestEquipPet") -- RemoteEvent

-- Referencias de UI, asignadas en Init.
local gridContainer: ScrollingFrame
local cardTemplate: GuiButton
local nameLabel, rarityLabel, elementLabel: TextLabel
local baseLabel, variantLabel, totalLabel, ownerLabel: TextLabel
local equipButton: TextButton

-- Estado en memoria del cliente.
local cardsByUUID: { [string]: { Button: GuiButton, Data: any } } = {}
local selectedUUID: string? = nil

-- Inyectado desde Main.client.lua para avisar a PetViewportController
-- cuando cambia la selección, sin que este módulo tenga que conocerlo.
local onPetSelectedCallback: ((petData: any) -> ())? = nil

-- ========================================================================
-- PANEL LATERAL DE ESTADÍSTICAS
-- ========================================================================
local function UpdateStatsPanel(petEntry)
	local petDef = PetsConfig.Get(petEntry.PetId)
	if not petDef then return end

	local variantDef = PetsConfig.GetVariant(petEntry.Variant or "Normal")
	local power = PetManager.CalculatePetPower(petEntry) -- { BaseMultiplier, VariantBonus, Total }

	local displayName = petDef.Name
	if variantDef and variantDef.Id ~= "Normal" then
		displayName ..= (" (%s)"):format(variantDef.Name)
	end

	nameLabel.Text = displayName
	rarityLabel.Text = petDef.Rarity
	rarityLabel.TextColor3 = PetsConfig.GetRarityColor(petDef.Rarity)
	elementLabel.Text = petDef.Element

	-- Desglose pedido explícitamente: base, variante y total por separado.
	baseLabel.Text = ("Base: x%.2f"):format(power.BaseMultiplier)
	variantLabel.Text = ("Variante (%s): +%.2f"):format(variantDef and variantDef.Name or "Normal", power.VariantBonus)
	totalLabel.Text = ("Total: x%.2f"):format(power.Total)

	ownerLabel.Text = "Eclosionada por primera vez por: " .. petEntry.OriginalOwnerName

	equipButton.Text = petEntry.Equipped and "Desequipar" or "Equipar"
end

-- ========================================================================
-- SELECCIÓN DE TARJETA
-- ========================================================================
local function SelectCard(uuid: string)
	local entry = cardsByUUID[uuid]
	if not entry then return end

	-- Quitamos el resaltado de la tarjeta seleccionada anteriormente.
	if selectedUUID and cardsByUUID[selectedUUID] then
		local previousStroke = cardsByUUID[selectedUUID].Button:FindFirstChild("UIStroke")
		if previousStroke then
			previousStroke.Enabled = false
		end
	end

	selectedUUID = uuid

	local stroke = entry.Button:FindFirstChild("UIStroke")
	if stroke then
		stroke.Enabled = true
	end

	UpdateStatsPanel(entry.Data)

	if onPetSelectedCallback then
		onPetSelectedCallback(entry.Data)
	end
end

-- ========================================================================
-- CREACIÓN / ACTUALIZACIÓN / ELIMINACIÓN DE TARJETAS (ver nota de "diff")
-- ========================================================================
local function ApplyCardVisuals(button: GuiButton, petEntry)
	local petDef = PetsConfig.Get(petEntry.PetId)
	if not petDef then return end

	local nameLabelOnCard = button:FindFirstChild("PetNameLabel")
	if nameLabelOnCard then
		nameLabelOnCard.Text = petDef.Name
	end

	local rarityFrame = button:FindFirstChild("RarityColorFrame")
	if rarityFrame then
		rarityFrame.BackgroundColor3 = PetsConfig.GetRarityColor(petDef.Rarity)
	end

	local equippedIcon = button:FindFirstChild("EquippedIcon")
	if equippedIcon then
		equippedIcon.Visible = petEntry.Equipped == true
	end
end

local function CreateCard(uuid: string, petEntry)
	local button = cardTemplate:Clone()
	button.Name = uuid
	button.Visible = true
	button.LayoutOrder = 0

	ApplyCardVisuals(button, petEntry)

	button.MouseButton1Click:Connect(function()
		AudioManager.PlaySFX("ButtonClick")
		SelectCard(uuid)
	end)

	button.Parent = gridContainer

	cardsByUUID[uuid] = { Button = button, Data = petEntry }
end

local function UpdateCard(uuid: string, petEntry)
	local entry = cardsByUUID[uuid]
	if not entry then return end

	entry.Data = petEntry
	ApplyCardVisuals(entry.Button, petEntry)

	-- Si la tarjeta que cambió es la que está seleccionada ahora mismo
	-- (por ejemplo, el jugador la acaba de equipar), refrescamos también
	-- el panel lateral para que el botón "Equipar/Desequipar" no quede desfasado.
	if uuid == selectedUUID then
		UpdateStatsPanel(petEntry)
	end
end

local function RemoveCard(uuid: string)
	local entry = cardsByUUID[uuid]
	if not entry then return end

	entry.Button:Destroy()
	cardsByUUID[uuid] = nil

	if uuid == selectedUUID then
		selectedUUID = nil
	end
end

-- Repuebla el grid comparando contra el estado actual, tocando solo lo
-- que cambió (ver cabecera del módulo).
local function Populate(fullInventory: { [string]: any })
	local seenThisTime = {}

	for uuid, petEntry in pairs(fullInventory) do
		seenThisTime[uuid] = true

		if cardsByUUID[uuid] then
			UpdateCard(uuid, petEntry)
		else
			CreateCard(uuid, petEntry)
		end
	end

	for uuid in pairs(cardsByUUID) do
		if not seenThisTime[uuid] then
			RemoveCard(uuid)
		end
	end
end

local function RefreshInventory()
	local ok, inventory = pcall(function()
		return getPetInventory:InvokeServer()
	end)

	if ok and inventory then
		Populate(inventory)
	else
		warn("[InventoryController] No se pudo obtener el inventario del servidor.")
	end
end

-- ========================================================================
-- API PÚBLICA
-- ========================================================================

-- Main.client.lua usa esto para enganchar PetViewportController.SetPet sin
-- que InventoryController tenga que requerir el módulo del viewport (evita
-- acoplar dos controladores que, por lo demás, no necesitan conocerse).
function InventoryController.SetOnPetSelected(callback: (petData: any) -> ())
	onPetSelectedCallback = callback
end

function InventoryController.Init(playerGui: PlayerGui)
	local inventoryFrame = playerGui:WaitForChild("MainHUD"):WaitForChild("InventoryFrame")

	gridContainer = inventoryFrame:WaitForChild("GridContainer")
	cardTemplate = gridContainer:WaitForChild("PetCardTemplate")
	cardTemplate.Visible = false -- Es una plantilla: nunca se muestra ella misma en el grid.

	local statsPanel = inventoryFrame:WaitForChild("StatsPanel")
	nameLabel = statsPanel:WaitForChild("NameLabel")
	rarityLabel = statsPanel:WaitForChild("RarityLabel")
	elementLabel = statsPanel:WaitForChild("ElementLabel")
	baseLabel = statsPanel:WaitForChild("BaseMultiplierLabel")
	variantLabel = statsPanel:WaitForChild("VariantBonusLabel")
	totalLabel = statsPanel:WaitForChild("TotalMultiplierLabel")
	ownerLabel = statsPanel:WaitForChild("OriginalOwnerLabel")
	equipButton = statsPanel:WaitForChild("EquipButton")

	equipButton.MouseButton1Click:Connect(function()
		if not selectedUUID then return end
		local entry = cardsByUUID[selectedUUID]
		if not entry then return end

		AudioManager.PlaySFX("PetEquip")

		-- No cambiamos nada localmente aquí: solo pedimos el cambio. La
		-- ÚNICA fuente de verdad es el servidor, que confirmará (o
		-- rechazará, p. ej. por el límite de mascotas equipadas) vía
		-- "InventoryUpdated". Esto evita que la UI "mienta" si el
		-- servidor deniega la petición.
		requestEquipPet:FireServer(selectedUUID, not entry.Data.Equipped)
	end)

	inventoryUpdated.OnClientEvent:Connect(RefreshInventory)

	RefreshInventory()
end

return InventoryController
