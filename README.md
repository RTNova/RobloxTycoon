# Arquitectura Base de Tycoon Modular — Guía de Instalación

## 1. Estructura final en el Explorer de Roblox Studio

```
ReplicatedStorage
├── Modules
│   └── TycoonConfig          (ModuleScript)
└── Assets
    └── CoinTemplate          (Part — crear a mano, ver paso 4)

ServerScriptService
├── ProfileService            (ModuleScript — librería externa, ver paso 2)
├── Main                      (Script)
└── Modules
    ├── DataManager            (ModuleScript)
    ├── TycoonManager          (ModuleScript)
    ├── ButtonService          (ModuleScript)
    └── DropperService         (ModuleScript)

Workspace
└── Tycoons                   (Folder)
    ├── Tycoon1                (Model)
    │   ├── ClaimPad            (Part)
    │   ├── Collector           (Part)  [Tag: "Collector"]
    │   └── Buttons             (Folder)
    │       └── Button1          (Part)  [Attributes: Cost, ButtonId]
    │           └── Stuff          (Folder)
    │               ├── Wall1        (Part, empieza oculta)
    │               └── Dropper1     (Part, empieza oculta)  [Tag: "Dropper", Attributes: Value, Interval]
    ├── Tycoon2                (Model — copia de Tycoon1)
    └── ...
```

> **Nota**: este diagrama es el de la entrega ORIGINAL (base Tycoon). Las
> ampliaciones posteriores (Pet Simulator en la sección 8, y el Núcleo
> Central sin droppers físicos en la sección 9) añaden/sustituyen varias
> de estas piezas — en concreto, `DropperService`, `Collector` y
> `CoinTemplate` quedan OBSOLETOS y se sustituyen por `IncomeManager`,
> `SkinController` y el `Core`/`CoreAnchor`. Consulta la sección 9.2-9.4
> para la estructura actualizada y definitiva.

## 2. Instalar ProfileService (dependencia externa)

1. Abre el Toolbox en Roblox Studio → pestaña "Modelos" → busca `ProfileService`
   (autor: loleris), o descárgalo desde su repositorio oficial en GitHub.
2. Arrástralo a `ServerScriptService`.
3. Renómbralo exactamente `ProfileService` si no viene así ya.
4. Asegúrate de que quede como **hermano** de la carpeta `Modules`, no dentro
   de ella (`DataManager.lua` lo busca con `ServerScriptService.ProfileService`).

## 3. Copiar los scripts de este proyecto

Copia cada archivo `.lua` de esta entrega dentro del ModuleScript o Script
correspondiente según la ruta indicada en la cabecera de cada archivo:

| Archivo                          | Tipo de instancia en Studio | Ruta                                   |
|-----------------------------------|------------------------------|-----------------------------------------|
| `ReplicatedStorage/Modules/TycoonConfig.lua` | ModuleScript | `ReplicatedStorage/Modules/TycoonConfig` |
| `ServerScriptService/Main.server.lua`        | Script       | `ServerScriptService/Main` |
| `ServerScriptService/Modules/DataManager.lua`   | ModuleScript | `ServerScriptService/Modules/DataManager` |
| `ServerScriptService/Modules/TycoonManager.lua` | ModuleScript | `ServerScriptService/Modules/TycoonManager` |
| `ServerScriptService/Modules/ButtonService.lua` | ModuleScript | `ServerScriptService/Modules/ButtonService` |
| `ServerScriptService/Modules/DropperService.lua`| ModuleScript | `ServerScriptService/Modules/DropperService` |

Para crear cada carpeta: clic derecho sobre el servicio → Insert Object → Folder.
Para crear cada ModuleScript/Script: clic derecho sobre la carpeta → Insert
Object → ModuleScript (o Script para `Main`).

## 4. Crear la plantilla de moneda (CoinTemplate)

1. En `ReplicatedStorage`, crea una carpeta llamada `Assets`.
2. Dentro, inserta una `Part` pequeña (por ejemplo, una esfera de 1x1x1 studs)
   y renómbrala `CoinTemplate`.
3. Configúrala así:
   - `Anchored` = `false`
   - `CanCollide` = `false` (para que no empuje al jugador, solo se detecte con `Touched`)
   - `Shape` = Ball (opcional, estético)
4. No le pongas ningún script: `DropperService.lua` la clona y le añade los
   atributos `Value` y `OwnerTycoon` dinámicamente en runtime.

## 5. Construir un Tycoon en Workspace

1. Crea en `Workspace` una carpeta llamada `Tycoons`.
2. Dentro, crea un `Model` por cada plot (`Tycoon1`, `Tycoon2`, ...).
3. Dentro de cada `Tycoon1`:
   - Un `Part` llamado `ClaimPad` (la baldosa donde el jugador hace clic para reclamar el plot).
   - Un `Part` llamado `Collector` con el **Tag** `Collector` puesto (pestaña *Tags* del panel de propiedades).
   - Una `Folder` llamada `Buttons`.
4. Dentro de `Buttons`, crea un `Part` por cada botón de compra (`Button1`, `Button2`...):
   - Ponle el **Tag** `TycoonButton`.
   - En la pestaña **Attributes**, añade:
     - `Cost` (tipo `number`) → ej. `100`
     - `ButtonId` (tipo `string`) → ej. `"Button1"` (debe ser único dentro del tycoon)
   - Dentro de ese `Part`, crea una `Folder` llamada `Stuff`.
5. Dentro de `Stuff`, mete todo lo que quieras que aparezca al comprar ese
   botón: paredes, decoraciones, o un dropper.
   - **Importante**: todas las `Part` dentro de `Stuff` deben empezar con
     `Transparency = 1` y `CanCollide = false` (ocultas).
   - Si alguna pieza necesita `CanCollide = false` incluso DESPUÉS de
     revelarse (por ejemplo, un cristal decorativo), añádele el atributo
     `RevealedCanCollide` (`boolean`) = `false`.
6. Si dentro de `Stuff` metes un dropper, la `Part` del dropper necesita:
   - **Tag**: `Dropper`
   - **Attributes**: `Value` (`number`, cuánto dinero da cada moneda) y
     `Interval` (`number`, segundos entre cada moneda generada).
7. Repite el `Model` completo (`Tycoon2`, `Tycoon3`...) duplicando `Tycoon1`
   y cambiando los `ButtonId` para que sigan siendo únicos dentro de cada tycoon.

## 6. Notas de diseño y escalabilidad

- **Añadir un botón nuevo no requiere tocar código**: solo construir en
  Studio con las Attributes/Tags correctas.
- **Server-Authoritative real**: la compra se dispara por `Touched` en el
  servidor; no existe ningún `RemoteEvent` que el cliente pueda "spamear"
  para simular una compra falsa.
- **Rendimiento de droppers**: cada dropper usa su propia corrutina con
  `task.wait(Interval)` en vez de conectarse a `Heartbeat`, y hay un límite
  (`MAX_COINS_PER_TYCOON`) de monedas físicas simultáneas por tycoon.
- **Guardado de datos**: `ProfileService` autogestiona el guardado periódico
  y el guardado final al salir; `DataManager.lua` solo lee/escribe la tabla
  `profile.Data` en memoria, que es prácticamente instantáneo.
- **Multi-tycoon con varios plots**: `TycoonManager.lua` asigna el primer
  plot libre al primer jugador que toque un `ClaimPad`, y lo libera cuando
  ese jugador sale, para que otro pueda ocuparlo.
- **Divisa premium (`Gems`)**: ya está reservada en `PROFILE_TEMPLATE` y en
  `leaderstats`; para venderla con Robux, crea un GamePass y, en su callback
  de compra (`MarketplaceService.ProcessReceipt`), llama a
  `DataManager.AddMoney` (o crea un `DataManager.AddGems` análogo) sumando
  la cantidad correspondiente.

## 7. Próximos pasos sugeridos (fuera del alcance de esta base)

- UI de cliente (StarterGui) que lea `leaderstats.Money`/`Gems` para
  mostrarlos con formato (ej. "1.2K", "3.4M").
- `MarketplaceService.ProcessReceipt` para la compra de Gems con Robux.
- Sistema de prestigio/reset del tycoon.
- Un `RemoteEvent` opcional de "notificación" (ej. "Necesitas 50$ más")
  para feedback visual cuando `TrySpendMoney` falla.

---

## 8. Expansión: Pet Simulator (huevos, inventario y multiplicadores)

### 8.1 Archivos nuevos y dónde van

| Archivo                          | Tipo de instancia | Ruta |
|-----------------------------------|--------------------|------|
| `ReplicatedStorage/Modules/PetsConfig.lua`  | ModuleScript | `ReplicatedStorage/Modules/PetsConfig` |
| `ReplicatedStorage/Modules/EggsConfig.lua`  | ModuleScript | `ReplicatedStorage/Modules/EggsConfig` |
| `ReplicatedStorage/Modules/WeightedRNG.lua` | ModuleScript | `ReplicatedStorage/Modules/WeightedRNG` |
| `ReplicatedStorage/Modules/PetManager.lua`  | ModuleScript | `ReplicatedStorage/Modules/PetManager` |
| `ServerScriptService/Modules/EggService.lua`         | ModuleScript | `ServerScriptService/Modules/EggService` |
| `ServerScriptService/Modules/MultiplierManager.lua`  | ModuleScript | `ServerScriptService/Modules/MultiplierManager` |
| `ServerScriptService/Modules/PetInventoryManager.lua`| ModuleScript | `ServerScriptService/Modules/PetInventoryManager` |

`DataManager.lua`, `DropperService.lua` y `Main.server.lua` de la entrega
anterior están **actualizados** (no son archivos nuevos): sustituye tu
copia antigua por la nueva versión de esta entrega.

**Nota importante de reorganización**: `WeightedRNG.lua` se movió de
`ServerScriptService` a `ReplicatedStorage` en esta entrega, porque ahora
también lo usa `PetManager.lua` (compartido cliente/servidor) para la
tirada de variante. Esto NO afecta a la seguridad: la única llamada que
genera dinero/mascotas reales sigue viviendo exclusivamente en
`EggService.lua`, en el servidor. Si tenías la versión anterior instalada
en `ServerScriptService > Modules > WeightedRNG`, muévela a
`ReplicatedStorage > Modules > WeightedRNG`.

### 8.2 Crear los RemoteEvents necesarios

En `ReplicatedStorage`, crea una carpeta `Remotes` (si no la tenías ya) y
dentro tres `RemoteEvent`:

```
ReplicatedStorage
└── Remotes (Folder)
    ├── RequestOpenEgg   (RemoteEvent)   <- Cliente → Servidor: "quiero abrir este huevo"
    ├── EggResult        (RemoteEvent)   <- Servidor → Cliente: "te tocó esta mascota"
    └── RequestEquipPet  (RemoteEvent)   <- Cliente → Servidor: "equipa/desequipa esta mascota"
```

Clic derecho en `ReplicatedStorage` → Insert Object → Folder → renombra a
`Remotes`. Luego clic derecho en `Remotes` → Insert Object → RemoteEvent,
tres veces, con esos nombres exactos.

### 8.3 Cómo se conecta todo con el Tycoon existente

- **El Tycoon sigue generando el dinero base** exactamente igual que antes
  (`DropperService` genera monedas físicas según `Value`/`Interval` de
  cada dropper comprado con los botones).
- **El único punto que cambia es el momento de sumar el dinero**: cuando
  el jugador toca una moneda, `DropperService` ahora pregunta a
  `MultiplierManager.GetMultiplier(player)` cuánto vale el bonus actual de
  sus mascotas equipadas, y multiplica el valor base antes de sumarlo.
  Esto significa que **comprar más droppers (Tycoon) y conseguir mejores
  mascotas (Gacha) se combinan de forma multiplicativa**: es la mecánica
  central del híbrido Tycoon + Pet Simulator.
- **Los huevos pueden colocarse como parte de un `Stuff`** de un botón del
  tycoon (por ejemplo, "Button5" desbloquea una zona con un huevo especial
  más caro), reutilizando exactamente el mismo patrón de
  Attributes/Tags que ya usas para paredes y decoraciones.
- **El equipo de mascotas no depende del Tycoon**: un jugador puede
  equipar/desequipar mascotas en cualquier momento (por ejemplo, desde un
  menú de inventario en `StarterGui`), y el multiplicador se recalcula al
  instante vía `PetInventoryManager` sin tocar nada del sistema de
  botones/droppers.

### 8.4 Ejemplo de uso desde un huevo físico en Workspace (servidor)

Para que un huevo en el mundo (una `Part` que el jugador toca) dispare la
apertura, NO necesitas lógica nueva de compra: basta con que, al tocarlo,
el propio SERVIDOR dispare el evento `EggResult` tras llamar internamente
a la misma lógica de `EggService`. Sin embargo, el flujo recomendado (y el
que implementan estos scripts) es que sea el **cliente** quien dispare
`RequestOpenEgg` al pulsar un botón de UI (por ejemplo, un `ProximityPrompt`
en el huevo físico), y el servidor responda con `EggResult`. Ejemplo mínimo
de `LocalScript` dentro del huevo (no incluido en esta entrega, pero así de
simple es conectar el cliente):

```lua
-- LocalScript dentro del ProximityPrompt del huevo
local prompt = script.Parent
local remotes = game:GetService("ReplicatedStorage").Remotes

prompt.Triggered:Connect(function()
    remotes.RequestOpenEgg:FireServer("Egg_Basic")
end)

remotes.EggResult.OnClientEvent:Connect(function(result)
    print("¡Te ha tocado la mascota!", result.PetId)
    -- Aquí iría tu animación de apertura de huevo / actualizar UI de inventario
end)
```

### 8.6 Firma de procedencia (Original Owner) — cómo se guarda

Cada mascota, en el momento exacto en que se genera dentro de `EggService`
(vía `DataManager.AddPet`), graba de forma **permanente** quién la
eclosionó. Estos dos campos nunca se vuelven a tocar después de la
creación, ni siquiera si en el futuro añades trading (si el jugador B
recibe la mascota del jugador A, `OriginalOwnerName`/`Id` siguen apuntando
a A: es un dato histórico, no el dueño actual).

### 8.7 Cómo queda una mascota en el ProfileService/DataStore

Así se ve `profile.Data.Pets` para un jugador con dos mascotas (una
Común equipada, una Mítica Dorada sin equipar), tal y como lo devolvería
`ProfileService` al leer el DataStore:

```lua
profile.Data = {
    Money = 125430,
    Gems = 0,
    PurchasedButtons = { Button1 = true, Button2 = true },
    TycoonId = "Tycoon3",

    Pets = {
        ["3f29a1c4-9e7b-4a2d-8b41-1c9e2f7d5a0b"] = {
            PetId = "Pet_Fox",
            Variant = "Normal",
            Equipped = true,
            OriginalOwnerName = "Borja2005",
            OriginalOwnerId = 123456789,
        },
        ["a7d4e912-5c3f-4b8a-9d21-6e0f8b3c7a44"] = {
            PetId = "Pet_Unicorn",       -- Mítica, 0.009% de probabilidad
            Variant = "Golden",           -- +200% extra sobre su base de 15x
            Equipped = false,
            OriginalOwnerName = "Borja2005",
            OriginalOwnerId = 123456789,
        },
    },
}
```

Con `PetManager:CalculatePetPower(...)` sobre esa segunda entrada:

```lua
PetManager.CalculatePetPower({ PetId = "Pet_Unicorn", Variant = "Golden" })
-- Devuelve:
-- {
--     BaseMultiplier = 15,   -- Multiplicador de la especie (Unicornio, Normal)
--     VariantBonus = 2,      -- Bonus aditivo de la variante Dorada
--     Total = 17,            -- 15 + 2: lo que usaría MultiplierManager si se equipa
-- }
```

La UI del inventario puede entonces mostrar algo como:
`"Unicornio Celestial (Dorado) — Base 15x + Dorado +2x = 17x total"`,
además de `"Eclosionada por primera vez por: Borja2005"` leyendo
`OriginalOwnerName` directamente de la entrada.

### 8.8 La función de Eclosión (Hatching) con precisión hardcore

Así queda `EggService._HandleHatch` (dentro de `EggService.Init`) uniendo
las dos tiradas independientes — especie (escala de 10,000,000) y
variante (escala de 10,000) — antes de escribir en el DataStore:

```lua
-- Dentro de requestOpenEgg.OnServerEvent:Connect(function(player, eggId) ... end)

-- 1) Validar el huevo y cobrar (sin esto, no se sigue).
local eggDef = EggsConfig.Get(eggId)
local paid = DataManager.TrySpendMoney(player, eggDef.Cost)
if not paid then return end

-- 2) Tirada de ESPECIE sobre una escala de hasta 10,000,000, con
--    validación de que el pool cuadre exactamente con TotalWeight.
local winningEntry = WeightedRNG.RollWithValidation(eggDef.Pool, eggDef.TotalWeight)
--    math.random(1, 10000000) internamente: nada de decimales, nada de
--    porcentajes 1-100. Un Pet_VoidWyrm con Weight = 100 tiene EXACTAMENTE
--    100 / 10,000,000 = 0.001% de probabilidad, sin margen de error.

-- 3) Tirada de VARIANTE, independiente, sobre su propia escala (10,000).
local variant = PetManager.RollVariant()

-- 4) Persistir en profile.Data con la firma de procedencia.
local uuid = DataManager.AddPet(player, winningEntry.PetId, variant)

-- 5) Notificar al cliente para la animación/UI.
eggResult:FireClient(player, {
    EggId = eggId,
    PetId = winningEntry.PetId,
    Variant = variant,
    UUID = uuid,
})
```

**Por qué las dos tiradas están separadas y no combinadas en un único
pool gigante**: si metieras "Pet_Cat Normal", "Pet_Cat Shiny", "Pet_Cat
Dorado", "Pet_Fox Normal"... como entradas distintas de un mismo pool,
tendrías que multiplicar manualmente cada peso de especie por cada peso
de variante (docenas de combinaciones), y cualquier cambio futuro en las
probabilidades de variante te obligaría a recalcular TODOS los huevos del
juego. Con dos tiradas independientes, cambias la tabla `Variants` de
`PetsConfig` una sola vez y afecta a todos los huevos automáticamente. Seguridad anti-exploit — resumen de las 3 capas

1. **El cliente nunca envía datos sensibles**: solo manda un `EggId`
   (string) o un `UUID` de mascota + booleano. Nunca manda "qué mascota
   quiero" ni "cuánto dinero tengo".
2. **Todo cálculo económico y de RNG ocurre en el servidor**:
   `TrySpendMoney`, `WeightedRNG.Roll` y `AddPet` viven exclusivamente en
   módulos de `ServerScriptService`, inaccesibles desde el cliente.
3. **Toda operación sobre el inventario valida propiedad**:
   `SetPetEquipped` y `RemovePet` buscan el UUID dentro del `profile.Data`
   del jugador que hizo la petición — es imposible, incluso con un
   RemoteEvent falsificado, tocar el inventario de otro jugador.

---

## 9. Expansión: Núcleo Central abstracto (cero lag, sin droppers físicos)

### 9.1 Qué cambia respecto a la versión con droppers

| Antes (droppers físicos)                          | Ahora (Núcleo Central)                              |
|-----------------------------------------------------|-------------------------------------------------------|
| `DropperService.lua` clonaba una `Part` de moneda cada X segundos | **Eliminado.** No se clona ningún objeto físico. |
| El jugador tocaba cada moneda individualmente        | El dinero se acumula solo como un número (`PendingMoney`) |
| Un `Part` "Collector" por tycoon recogía las monedas | El propio **Núcleo** (`CoreBody`) es el punto de recolección |
| Límite de monedas simultáneas (`MAX_COINS_PER_TYCOON`) para no saturar la física | Ya no aplica: cero partes físicas, cero colisiones que calcular |

**Acción requerida en tu proyecto existente**: borra `ServerScriptService >
Modules > DropperService`, el `Part` "Collector" de cada tycoon, y
`ReplicatedStorage > Assets > CoinTemplate` (ya no se usan). Sustitúyelos
siguiendo la sección 9.3.

### 9.2 Archivos nuevos y dónde van

| Archivo                          | Tipo de instancia | Ruta |
|-----------------------------------|--------------------|------|
| `ReplicatedStorage/Modules/CoreConfig.lua`  | ModuleScript | `ReplicatedStorage/Modules/CoreConfig` |
| `ReplicatedStorage/Modules/SkinsConfig.lua` | ModuleScript | `ReplicatedStorage/Modules/SkinsConfig` |
| `ServerScriptService/Modules/IncomeManager.lua`   | ModuleScript | `ServerScriptService/Modules/IncomeManager` |
| `ServerScriptService/Modules/SkinController.lua`  | ModuleScript | `ServerScriptService/Modules/SkinController` |
| `StarterPlayer/StarterPlayerScripts/CoreVisuals.client.lua` | LocalScript | `StarterPlayer/StarterPlayerScripts/CoreVisuals` |

`DataManager.lua`, `ButtonService.lua`, `TycoonManager.lua` y
`Main.server.lua` están **actualizados** (sustituye tus copias antiguas).

### 9.3 Construir el Núcleo en Workspace

1. Dentro de cada `Tycoon1`, `Tycoon2`... crea un `Part` (puede ser
   invisible, `Transparency = 1`) llamado `CoreAnchor`. Marca solo la
   POSICIÓN donde debe aparecer el Núcleo; no es el Núcleo en sí.
2. **No crees el `Core` a mano**: lo clona `SkinController` en runtime la
   primera vez que el jugador reclama el tycoon (skin `"Default"` por
   defecto). Si quieres verlo en el editor mientras construyes, puedes
   colocar uno temporalmente y borrarlo antes de publicar.
3. Ya no hace falta el `Part` "Collector": bórralo si lo tenías de la
   versión con droppers.

### 9.4 Construir los prefabricados de skin (`CoreCrystal`, `CoreSakura`)

1. En `ReplicatedStorage`, dentro de `Assets`, crea una carpeta
   `CoreSkins`.
2. Dentro, crea un `Model` llamado exactamente `CoreCrystal` (el skin
   `"Default"`):
   - Una `BasePart` (o `MeshPart`) llamada exactamente `CoreBody` — esta
     es la pieza que se escala y la que el jugador toca para recolectar.
     Aplícale un `MaterialVariant` de tipo Neon (o simplemente
     `Material = Neon`) para el efecto de brillo.
   - Un `PointLight` llamado exactamente `CoreLight`, como hijo de
     `CoreBody` (Insert Object → PointLight sobre `CoreBody`).
3. Repite el proceso con otro `Model` llamado `CoreSakura` (el skin
   `"Tatami"`), con su propia geometría (un brote/árbol de sakura), pero
   respetando el MISMO naming: debe contener una parte `CoreBody` y un
   `CoreLight`. El tamaño base puede ser completamente distinto al del
   cristal: `SkinController` guarda el tamaño de CADA prefab por
   separado como Attributes al clonarlo, así que el escalado siempre
   parte de las proporciones correctas de cada skin.
4. **Por qué el nombrado es obligatorio y no opcional**: tanto
   `SkinController` (para etiquetar el punto de recolección) como
   `CoreVisuals.client.lua` (para escalar/parpadear) buscan estas piezas
   por NOMBRE (`FindFirstChild("CoreBody", true)`), nunca por índice ni
   por tipo de skin. Esto es lo que permite añadir un tercer, cuarto o
   décimo skin en el futuro sin tocar ni una línea de `SkinController` ni
   de `CoreVisuals`: solo creas el `Model` con esos dos nombres y lo
   registras en `SkinsConfig.lua`.

### 9.5 Crear el RemoteEvent para el cambio de skin

En `ReplicatedStorage > Remotes`, añade un `RemoteEvent` más:

```
ReplicatedStorage
└── Remotes (Folder)
    ├── RequestOpenEgg
    ├── EggResult
    ├── RequestEquipPet
    └── RequestChangeSkin   (RemoteEvent)   <- Cliente → Servidor: "quiero este skin"
```

Ejemplo de `LocalScript` para un botón de UI que cambia de skin (no
incluido en esta entrega, pero así de simple es conectarlo):

```lua
local remotes = game:GetService("ReplicatedStorage").Remotes

tatamiButton.MouseButton1Click:Connect(function()
    remotes.RequestChangeSkin:FireServer("Tatami")
end)
```

### 9.6 Configurar generadores de ingresos en los botones existentes

Donde antes ponías un `Dropper1` con Tag `"Dropper"` y Attributes
`Value`/`Interval`, ahora pones un `Generator1` con Tag
`"IncomeGenerator"` y un único Attribute:

```
Button1 > Stuff > Generator1
    [Tag]: "IncomeGenerator"
    [Attribute]: MoneyPerSecond (number) = 10
```

`Generator1` no necesita ser una `BasePart` — puede ser una
`Configuration` sin representación visual, o una `Part` decorativa (una
máquina, una granja) que además lleve el Tag. `ButtonService` la activa
automáticamente al comprar el botón (o al restaurar progreso guardado),
y `IncomeManager` suma su `MoneyPerSecond` a la tasa total del tycoon.

### 9.7 Cómo se conecta todo — flujo completo

```
Jugador compra Button1
        │
        ▼
ButtonService revela "Stuff" y activa Generator1 (IncomeManager.ActivateGenerator)
        │
        ▼
IncomeManager.baseRateByTycoon[Tycoon1] += 10   (cacheado, no se recalcula cada tick)
        │
        ▼
Cada 1 segundo (CoreConfig.INCOME_UPDATE_INTERVAL), el bucle ÚNICO de
IncomeManager recorre TODOS los jugadores:
        │
        ▼
finalRate = baseRate (10) × MultiplierManager.GetMultiplier(player)
        │
        ▼
DataManager.AddPendingMoney(player, finalRate × 1seg, finalRate)
        │
        ├──▶ profile.Data.Core.PendingMoney (persistido en el DataStore)
        └──▶ player.CoreData.PendingMoney / IncomeRate (NumberValues replicados)
                        │
                        ▼
        CoreVisuals.client.lua (LocalScript) reacciona a los .Changed:
            - Escala CoreBody con TweenService según PendingMoney
            - Ajusta la velocidad de parpadeo de CoreLight según IncomeRate
        │
        ▼
Jugador toca CoreBody (tag "CoreCollector")
        │
        ▼
DataManager.CollectPendingMoney(player): PendingMoney → Money real (leaderstats)
```

**El multiplicador de mascotas sigue aplicándose exactamente en el mismo
punto conceptual que antes** (al convertir "generación bruta" en dinero
real para el jugador): antes se aplicaba al recoger cada moneda física
en `DropperService`; ahora se aplica una vez por tick sobre la tasa
agregada en `IncomeManager`. El resultado económico para el jugador es
equivalente, pero sin ningún coste de física.

### 9.8 Seguridad — por qué no se puede "inflar" el dinero pendiente

- El cliente **nunca envía** cuánto dinero pendiente tiene ni a qué
  velocidad genera: todo el cálculo (`baseRate`, `multiplier`,
  `finalRate`) ocurre exclusivamente en el bucle de `IncomeManager`, en
  el servidor.
- El único evento que dispara el cliente relacionado con el Núcleo es
  `Touched` sobre `CoreBody` (recolectar) — un evento físico estándar de
  Roblox que el servidor ya procesa de forma autoritativa — y
  `RequestChangeSkin` (solo un string validado contra `SkinsConfig`).
- Aunque un exploiter tocara `CoreBody` en bucle sin parar, cada toque
  simplemente llama a `DataManager.CollectPendingMoney`, que solo puede
  mover el dinero que YA estaba acumulado en el servidor: no crea dinero
  de la nada.

---

## 10. Expansión: UI del cliente (HUD, Inventario y Viewport 3D)

### 10.1 Archivos nuevos y dónde van

| Archivo                          | Tipo de instancia | Ruta |
|-----------------------------------|--------------------|------|
| `ReplicatedStorage/Modules/NumberFormat.lua` | ModuleScript | `ReplicatedStorage/Modules/NumberFormat` |
| `ServerScriptService/Modules/InventoryService.lua` | ModuleScript | `ServerScriptService/Modules/InventoryService` |
| `StarterPlayer/StarterPlayerScripts/Main.client.lua` | LocalScript | `StarterPlayer/StarterPlayerScripts/Main` |
| `StarterPlayer/StarterPlayerScripts/Controllers/HUDController.lua` | ModuleScript | `StarterPlayer/StarterPlayerScripts/Controllers/HUDController` |
| `StarterPlayer/StarterPlayerScripts/Controllers/InventoryController.lua` | ModuleScript | `StarterPlayer/StarterPlayerScripts/Controllers/InventoryController` |
| `StarterPlayer/StarterPlayerScripts/Controllers/PetViewportController.lua` | ModuleScript | `StarterPlayer/StarterPlayerScripts/Controllers/PetViewportController` |

`PetsConfig.lua`, `EggService.lua`, `PetInventoryManager.lua` y
`Main.server.lua` están **actualizados** (añaden `RarityColors` y las
llamadas a `InventoryService.NotifyChanged`).

`Controllers` es una carpeta normal (`Insert Object → Folder`) dentro de
`StarterPlayerScripts`, hermana de `Main` y de `CoreVisuals` (de la
sección 9). Los `ModuleScript` de ahí dentro NUNCA se ejecutan solos: los
requiere `Main.client.lua`.

### 10.2 Jerarquía de UI que deben construir en Studio

Estos son los nombres EXACTOS que buscan los tres controladores
(`WaitForChild`). Constrúyela dentro de `StarterGui`:

```
StarterGui
└── MainHUD (ScreenGui)
    ├── TopBar (Frame)
    │   └── MoneyLabel (TextLabel)
    └── InventoryFrame (Frame)
        ├── GridContainer (ScrollingFrame)
        │   [Un UIGridLayout como hijo, con el tamaño de celda que prefieras]
        │   └── PetCardTemplate (ImageButton)   <- Plantilla; el script la oculta solo
        │       ├── UIStroke                      (Enabled = false por defecto)
        │       ├── RarityColorFrame (Frame)
        │       ├── PetNameLabel (TextLabel)
        │       └── EquippedIcon (ImageLabel)     (Visible = false por defecto)
        └── StatsPanel (Frame)
            ├── PetViewport (ViewportFrame)
            ├── NameLabel (TextLabel)
            ├── RarityLabel (TextLabel)
            ├── ElementLabel (TextLabel)
            ├── BaseMultiplierLabel (TextLabel)
            ├── VariantBonusLabel (TextLabel)
            ├── TotalMultiplierLabel (TextLabel)
            ├── OriginalOwnerLabel (TextLabel)
            └── EquipButton (TextButton)
```

**Importante sobre `PetCardTemplate`**: constrúyela ya con su apariencia
final (icono, fuente, tamaño...) directamente en Studio. El script la
clona tal cual está — no genera estilos por código — y solo pone
`Visible = false` sobre la plantilla original para que no aparezca ella
misma como una tarjeta más del grid.

### 10.3 Modelos 3D de las mascotas (para el Viewport)

```
ReplicatedStorage
└── Assets
    └── PetModels (Folder)
        ├── Pet_Cat      (Model)  <- El nombre debe ser IDÉNTICO al PetId de PetsConfig
        ├── Pet_Rabbit   (Model)
        ├── Pet_Fox      (Model)
        └── ... (uno por cada especie que definas en PetsConfig.Pets)
```

### 10.4 Nuevos RemoteEvent/RemoteFunction

En `ReplicatedStorage > Remotes`, añade:

```
ReplicatedStorage
└── Remotes (Folder)
    ├── GetPetInventory     (RemoteFunction)  <- Cliente → Servidor: "dame mi inventario completo"
    └── InventoryUpdated    (RemoteEvent)     <- Servidor → Cliente: "tu inventario cambió, vuelve a pedirlo"
```

### 10.5 Cómo funciona el contador de dinero "cuentakilómetros"

`HUDController` NO usa `TweenService` para el número: usa una
interpolación exponencial manual, recalculada cada frame mientras hay una
diferencia pendiente:

```lua
displayedMoney += (targetMoney - displayedMoney) * math.min(LERP_SPEED * dt, 1)
```

La velocidad de la animación es proporcional a la distancia que falta:
si acabas de ganar 50.000$, los primeros dígitos suben muy rápido; a
medida que se acerca al valor real, la velocidad cae sola, sin ninguna
curva de easing explícita ni saltos de un número a otro. La conexión a
`Heartbeat` solo permanece activa mientras dura la animación (se
desconecta al llegar al valor real vía `SNAP_THRESHOLD`), así que un HUD
"quieto" no consume nada en cada frame.

### 10.6 Cómo funciona la repoblación optimizada del inventario

`InventoryController.Populate` compara la lista que devuelve el servidor
contra su propio caché (`cardsByUUID`) y solo CREA/ACTUALIZA/DESTRUYE las
tarjetas que realmente cambiaron, en vez de `ClearAllChildren()` +
recrear todo el grid en cada apertura de huevo. Con un inventario de
cientos de mascotas, esto evita parpadeos visibles y presión innecesaria
sobre el recolector de basura.

El panel lateral sigue una única fuente de verdad: al pulsar
"Equipar/Desequipar", el cliente NO cambia su propio estado — solo
dispara `RequestEquipPet` y espera a que el servidor confirme el cambio
vía `InventoryUpdated`. Esto evita que la UI "mienta" si el servidor
rechaza la petición (por ejemplo, por el límite de `MAX_EQUIPPED_PETS`
de `PetInventoryManager`).

### 10.7 Cómo funciona el encuadre automático de la cámara del Viewport

`PetViewportController.CenterAndFrame` usa `Model:GetBoundingBox()` para:

1. Recentrar el modelo clonado en el origen `(0,0,0)` de su propio
   "mini-mundo" (así la rotación gira sobre su propio centro).
2. Calcular la distancia de la cámara como
   `max(ancho, alto, profundo) × 1.6 + 1`, así un Gato pequeño y un
   Dragón enorme quedan igual de bien encuadrados sin tocar ni un número
   a mano por especie.

La rotación usa `RunService.RenderStepped` (ideal para efectos puramente
visuales, ya que se sincroniza con el renderizado del frame) y se
desconecta explícitamente en `ClearModel` cada vez que cambias de
mascota seleccionada — evita dejar conexiones "fantasma" corriendo sobre
modelos ya destruidos.

### 10.8 Flujo completo: seleccionar una mascota

```
Jugador toca una tarjeta del grid
        │
        ▼
InventoryController.SelectCard(uuid)
        │
        ├──▶ Resalta la tarjeta (UIStroke.Enabled = true)
        ├──▶ UpdateStatsPanel(petEntry) — Base / Variante / Total, procedencia
        └──▶ onPetSelectedCallback(petEntry)  (inyectado por Main.client.lua)
                        │
                        ▼
        PetViewportController.SetPet(petEntry)
                        │
                        ├──▶ Destruye el modelo anterior y su rotación (ClearModel)
                        ├──▶ Clona ReplicatedStorage.Assets.PetModels[petEntry.PetId]
                        ├──▶ Centra el modelo y encuadra la cámara (CenterAndFrame)
                        └──▶ Arranca la rotación en RenderStepped
```

---

## 11. Expansión: Monetización (Gamepasses, DevProducts y clonación social)

### 11.1 Archivos nuevos y dónde van

| Archivo                          | Tipo de instancia | Ruta |
|-----------------------------------|--------------------|------|
| `ReplicatedStorage/Modules/GamepassConfig.lua`   | ModuleScript | `ReplicatedStorage/Modules/GamepassConfig` |
| `ReplicatedStorage/Modules/DevProductConfig.lua` | ModuleScript | `ReplicatedStorage/Modules/DevProductConfig` |
| `ServerScriptService/Modules/GamepassManager.lua`  | ModuleScript | `ServerScriptService/Modules/GamepassManager` |
| `ServerScriptService/Modules/DevProductHandler.lua`| ModuleScript | `ServerScriptService/Modules/DevProductHandler` |
| `ServerScriptService/Modules/PetCloneService.lua`  | ModuleScript | `ServerScriptService/Modules/PetCloneService` |

`DataManager.lua`, `EggService.lua`, `PetInventoryManager.lua`,
`MultiplierManager.lua`, `PetsConfig.lua` y `Main.server.lua` están
**actualizados** (sustituye tus copias antiguas).

### 11.2 Antes de nada: crea los Gamepasses y Developer Products reales

1. Publica el juego (aunque sea privado) al menos una vez — Roblox exige
   esto para poder crear productos de monetización.
2. En el sitio web de Roblox, o desde Studio (menú "Monetization" con el
   juego abierto), crea:
   - 3 **Game Passes**: `VIP`, `x2 Luck`, `+1 Equip`.
   - 4 **Developer Products**: `MoneyPack_Small`, `MoneyPack_Medium`,
     `MoneyPack_Large`, `PetCloneFee` (ponle el precio en Robux que
     quieras a cada uno).
3. Copia cada ID numérico real y sustitúyelo en `GamepassConfig.lua` y
   `DevProductConfig.lua` (los que trae la entrega son placeholders
   `0000001`, `1000001`, etc. — **no funcionarán tal cual**).

### 11.3 Nuevos RemoteEvents

En `ReplicatedStorage > Remotes`, añade:

```
ReplicatedStorage
└── Remotes (Folder)
    ├── RequestClonePet     (RemoteEvent)  <- Cliente → Servidor: "quiero clonar esta mascota de este jugador"
    ├── CloneResult         (RemoteEvent)  <- Servidor → Comprador: resultado de la clonación
    └── CloneNotification   (RemoteEvent)  <- Servidor → Dueño original: "te clonaron una mascota, +monedas"
```

Los Gamepasses y los paquetes de monedas **NO necesitan un RemoteEvent
propio**: el cliente llama directamente a `MarketplaceService` (ver 11.6),
porque no hay nada que validar en el servidor antes de mostrar el prompt
de compra. La clonación es la excepción, por las razones explicadas en la
cabecera de `PetCloneService.lua` (sección 11.5).

### 11.4 Cómo se aplican los tres Gamepasses

| Gamepass | Dónde se aplica | Mecanismo |
|---|---|---|
| **VIP** | `MultiplierManager.Recalculate` | Bono ADITIVO fijo (`GamepassConfig.VIP_MULTIPLIER_BONUS`, por defecto `+0.5`) sumado al multiplicador total, igual que si fuera "una mascota más" siempre equipada. |
| **x2 Luck** | `EggService` en cada eclosión | Tira el `WeightedRNG` DOS veces sobre el mismo pool y se queda con la mascota de mayor rareza de las dos (`PickRarerEntry`), en vez de tocar los pesos del pool. |
| **+1 Equip** | `PetInventoryManager` al equipar | Sube `MAX_EQUIPPED_PETS_BASE` (3) en 1 solo para quien lo posee, comprobado en cada intento de equipar vía `GamepassManager.HasGamepass`. |

Los tres se leen de una caché en memoria por sesión
(`GamepassManager.ownedCache`), calculada al entrar y refrescada al
instante si el jugador compra un Gamepass en mitad de la partida (evento
`PromptGamePassPurchaseFinished`) — nunca hace falta reconectar para que
el beneficio se note.

### 11.5 Cómo se aplica la clonación social — flujo completo

```
Jugador A ve la mascota equipada del Jugador B (en su tycoon, en una UI social...)
        │
        ▼
Cliente de A dispara RequestClonePet(B.UserId, uuidDeLaMascota)
        │
        ▼
PetCloneService (servidor) valida:
    - ¿B sigue en el servidor?
    - ¿Esa mascota sigue en el inventario de B AHORA MISMO?
        │ (si algo falla, CloneResult:FireClient(A, {Success=false, Reason=...}) y fin)
        ▼
DataManager.SetPendingClone(A, {TargetUserId=B.UserId, TargetUUID=uuid})
        │  (persistido en el DataStore de A, sobrevive a una desconexión)
        ▼
MarketplaceService:PromptProductPurchase(A, PetCloneFee.Id)
        │
        ▼
        [A confirma el pago en la ventana de Roblox — puede tardar segundos
         o, si A cierra el juego justo tras pagar, confirmarse en su
         PRÓXIMA sesión]
        │
        ▼
ProcessReceipt → DevProductHandler → PetCloneService.GrantClone(A, receiptInfo, ...)
        │
        ├──▶ Lee DataManager.GetPendingClone(A)
        ├──▶ Vuelve a comprobar que B siga en el servidor y la mascota siga existiendo
        │       (si no: compensa a A con CLONE_REWARD_AMOUNT monedas y notifica el motivo)
        │
        ├──▶ DataManager.AddClonedPet(A, PetId, Variant, sourcePet.OriginalOwnerName, sourcePet.OriginalOwnerId)
        │       (la copia de A hereda la procedencia ORIGINAL, no la de A ni la de B)
        │
        ├──▶ DataManager.AddMoney(B, CLONE_REWARD_AMOUNT)   ← recompensa social al dueño actual
        ├──▶ CloneNotification:FireClient(B, {ClonerName=A.Name, PetId=..., RewardAmount=...})
        ├──▶ CloneResult:FireClient(A, {Success=true, PetId=..., UUID=nuevoUUID})
        └──▶ InventoryService.NotifyChanged(A)   ← su UI de inventario se refresca sola
```

**Sobre la limitación aceptada del diseño**: si B se desconecta DESPUÉS de
que A ya vio el prompt de pago pero ANTES de que Roblox confirme el cobro
(normalmente una ventana de segundos), `GrantClone` no puede leer el
inventario de B en una sesión futura — compensa a A con monedas en vez de
dejarlo esperando. Esto es una limitación conocida y aceptada de cualquier
consumible atado a un jugador objetivo concreto en Roblox; está
documentada en la cabecera de `PetCloneService.lua`.

### 11.6 Ejemplo de cliente: prompts de compra (Gamepasses y paquetes de monedas)

Los Gamepasses y los DevProducts "simples" (paquetes de monedas) se piden
directamente desde un `LocalScript`, sin pasar por ningún RemoteEvent:

```lua
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GamepassConfig = require(ReplicatedStorage.Modules.GamepassConfig)
local DevProductConfig = require(ReplicatedStorage.Modules.DevProductConfig)

local player = Players.LocalPlayer

vipButton.MouseButton1Click:Connect(function()
    MarketplaceService:PromptGamePassPurchase(player, GamepassConfig.Get("VIP").Id)
end)

moneyPackButton.MouseButton1Click:Connect(function()
    MarketplaceService:PromptProductPurchase(player, DevProductConfig.Get("MoneyPack_Medium").Id)
end)
```

Y la clonación, que SÍ pasa por el servidor primero:

```lua
local remotes = game:GetService("ReplicatedStorage").Remotes

cloneButton.MouseButton1Click:Connect(function()
    remotes.RequestClonePet:FireServer(targetPlayer.UserId, targetPetUUID)
end)

remotes.CloneResult.OnClientEvent:Connect(function(result)
    if result.Success then
        print("¡Clonaste " .. result.PetId .. "!")
    else
        print("No se pudo clonar: " .. result.Reason)
    end
end)

remotes.CloneNotification.OnClientEvent:Connect(function(notification)
    print(notification.ClonerName .. " clonó tu " .. notification.PetId .. " — +" .. notification.RewardAmount .. "$")
end)
```

### 11.7 Por qué `DevProductHandler` es "a prueba de fallos"

- Devuelve `Enum.ProductPurchaseDecision.NotProcessedYet` en CUALQUIER
  punto donde la recompensa podría no haberse otorgado todavía: jugador
  no encontrado, perfil sin cargar, fallo de DataStore al comprobar o
  marcar el historial, o un error dentro del propio handler del producto
  (protegido con `pcall`). Roblox reintenta automáticamente hasta 3 días,
  incluso en una sesión futura del jugador.
- Nunca duplica una recompensa: antes de ejecutar el handler, comprueba
  `DataManager.HasProcessedPurchase(player, receiptInfo.PurchaseId)` — si
  ese `PurchaseId` ya fue otorgado, confirma sin volver a ejecutar nada.
- Es el ÚNICO módulo que asigna `MarketplaceService.ProcessReceipt`
  (Roblox solo permite un callback global): el resto de módulos
  (paquetes de monedas, `PetCloneService`) se registran a través de
  `DevProductHandler.RegisterHandler`, sin necesidad de tocar este
  archivo cada vez que añades un producto nuevo.

---

## 12. Expansión: AudioManager (música dinámica, SFX de UI y audio espacial)

### 12.1 Archivos nuevos y dónde van

| Archivo                          | Tipo de instancia | Ruta |
|-----------------------------------|--------------------|------|
| `ReplicatedStorage/Modules/AudioManager.lua` | ModuleScript | `ReplicatedStorage/Modules/AudioManager` |
| `ReplicatedStorage/Modules/MusicConfig.lua`  | ModuleScript | `ReplicatedStorage/Modules/MusicConfig` |
| `ReplicatedStorage/Modules/SFXConfig.lua`    | ModuleScript | `ReplicatedStorage/Modules/SFXConfig` |

`Main.client.lua`, `InventoryController.lua` y `CoreVisuals.client.lua`
están **actualizados** (añaden `AudioManager.Init()` y llamadas de
ejemplo a `PlaySFX`/`PlaySpatialSFX`).

`AudioManager` vive en `ReplicatedStorage` (no en `StarterPlayerScripts`)
para que CUALQUIER script de cliente pueda `require`lo desde cualquier
punto, igual que `NumberFormat` o `PetManager` — pero es un módulo
exclusivamente de CLIENTE: nunca lo requieras desde `ServerScriptService`.

### 12.2 Marcador del centro del mapa

En `Workspace`, crea un `Part` invisible (`Transparency = 1`,
`CanCollide = false`, `Anchored = true`) llamado exactamente `MapCenter`,
colocado donde quieras que se midan las distancias de `MusicConfig`
(normalmente el centro geométrico de tu isla/mapa, no necesariamente el
`CoreAnchor` de un tycoon concreto).

### 12.3 Sustituye los SoundId de ejemplo

`MusicConfig.lua` y `SFXConfig.lua` traen `rbxassetid://000000000X` como
placeholders. Sube tus audios (Roblox Studio → "Asset Manager" → arrastra
tus archivos de audio) y sustituye cada Id por el real. Recuerda que
Roblox exige que los audios pasen por moderación antes de poder usarse en
un juego publicado.

### 12.4 Cómo funciona el crossfade de música

`AudioManager.StartDynamicMusic` comprueba la distancia del jugador al
`MapCenter` cada `MUSIC_CHECK_INTERVAL` segundos (2s por defecto — no
hace falta comprobarlo cada frame, el jugador no puede cambiar de zona
musical en menos tiempo del que tarda en notarse). Al cruzar de zona,
`CrossfadeToTrack`:

1. Crea un `Sound` NUEVO con la pista de la zona destino, arrancando en
   `Volume = 0`, y lo sube con `TweenService` hasta `MUSIC_VOLUME`.
2. Simultáneamente, baja el `Sound` de la pista ANTERIOR hasta `Volume = 0`
   con el mismo `TweenInfo` (mismo `MUSIC_FADE_TIME`), y lo destruye al
   terminar (`Tween.Completed`).

Como ambos tweens duran lo mismo y arrancan a la vez, se cruzan a mitad
de camino sin silencio ni solapamiento a volumen completo.

### 12.5 Audio espacial 3D — configurar los huevos en Workspace

Tienes DOS formas válidas de hacer sonar un huevo al eclosionar, según si
quieres un sonido "permanente" colocado a mano o uno disparado por código:

**Opción A — Sound colocado a mano dentro del huevo (recomendado si el
huevo es un objeto fijo del mapa, por ejemplo, un huevo decorativo que se
puede tocar directamente):**

1. Selecciona el `Part` (o el `PrimaryPart` del `Model`) del huevo en
   Workspace.
2. Insértale un `Sound` como HIJO DIRECTO de esa `Part` — **esto es lo
   que lo hace posicional**: un `Sound` solo suena en 3D si su `Parent`
   es una `BasePart` o un `Attachment`; si lo pones en `SoundService` o
   en un `Script`, sonará igual de fuerte en todo el mapa sin importar el
   RollOff.
3. Configura estas propiedades en el panel de propiedades del `Sound`:

   | Propiedad | Valor recomendado | Por qué |
   |---|---|---|
   | `RollOffMode` | `InverseTapered` | El modo por defecto de Roblox y el que más se parece a cómo cae el volumen del sonido real en el mundo físico (caída rápida cerca, luego se suaviza). |
   | `RollOffMinDistance` | `5` | Dentro de 5 studs, el sonido se oye a volumen completo — la distancia típica a la que estás parado tocando el huevo. |
   | `RollOffMaxDistance` | `60` | Más allá de 60 studs, el sonido es inaudible. Lo bastante lejos para que se oiga desde varias parcelas de tycoon vecinas (efecto social: "algo eclosionó cerca"), sin llegar a todo el mapa. |
   | `Looped` | `false` | Es un efecto de un disparo (la eclosión), no ambiente en bucle. |
   | `PlayOnRemove` | `false` | No queremos que suene si el huevo se destruye/reemplaza. |

4. Dispara `sound:Play()` desde el script que gestiona la compra/eclosión
   de ESE huevo concreto (por ejemplo, dentro de tu flujo de `EggService`
   en el cliente, al recibir `EggResult`, si el huevo físico está
   asociado a ese jugador).

**Opción B — Sonido dinámico de un solo uso vía `AudioManager.PlaySpatialSFX`
(recomendado si el "huevo" es más bien un efecto puntual sin una Part
fija dedicada, por ejemplo, un efecto de partículas + sonido que aparece
donde esté el jugador en ese momento):**

```lua
-- Cliente: al recibir el resultado de una eclosión, suena en la posición
-- del propio jugador (o de la Part del huevo con el que interactuó).
remotes.EggResult.OnClientEvent:Connect(function(result)
    local character = player.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    if rootPart then
        AudioManager.PlaySpatialSFX(rootPart, "EggHatch", {
            RollOffMinDistance = 5,
            RollOffMaxDistance = 60,
        })
    end
end)
```

`PlaySpatialSFX` crea el `Sound` como hijo de la `BasePart`/`Attachment`
que le pases (por eso es igual de posicional que la Opción A), lo
reproduce, y se autodestruye al terminar — ideal para efectos que no
necesitan una instancia `Sound` permanente en el mapa.

### 12.6 Por qué el pool de SFX no corta los sonidos al pulsar rápido

`AudioManager.PlaySFX` NUNCA reutiliza el mismo `Sound` para dos
reproducciones simultáneas: busca uno LIBRE en el pool (`not sound.Playing`)
y, si todos están ocupados, crea uno nuevo y lo añade al pool para el
futuro. El pool crece solo hasta el pico real de sonidos simultáneos que
necesita ese jugador (con un techo de seguridad de `MAX_SFX_POOL_SIZE`,
16, para el caso patológico de un bug disparando SFX en bucle) — así dos
clics rápidos en botones distintos suenan SUPERPUESTOS, como pasaría con
sonidos reales, en vez de que el segundo clic corte al primero en seco.

---

## 13. Expansión: Rebirth (Renacimiento) y Árbol de Habilidades

### 13.1 Archivos nuevos y dónde van

| Archivo                          | Tipo de instancia | Ruta |
|-----------------------------------|--------------------|------|
| `ReplicatedStorage/Modules/SkillTreeConfig.lua` | ModuleScript | `ReplicatedStorage/Modules/SkillTreeConfig` |
| `ServerScriptService/Modules/BuffManager.lua`      | ModuleScript | `ServerScriptService/Modules/BuffManager` |
| `ServerScriptService/Modules/SkillTreeService.lua` | ModuleScript | `ServerScriptService/Modules/SkillTreeService` |
| `ServerScriptService/Modules/RebirthService.lua`   | ModuleScript | `ServerScriptService/Modules/RebirthService` |

`DataManager.lua`, `TycoonManager.lua`, `ButtonService.lua`,
`IncomeManager.lua`, `EggService.lua`, `PetInventoryManager.lua` y
`Main.server.lua` están **actualizados** (sustituye tus copias antiguas).

### 13.2 Marca el botón final de cada tycoon

En Studio, selecciona la `Part` del ÚLTIMO botón de la progresión de cada
`Tycoon1`, `Tycoon2`... (el que se compra en último lugar) y añádele un
Attribute nuevo, además de los que ya tenía (`Cost`, `ButtonId`):

```
Button_Final
    [Attributes]:
        Cost           (number)  = 50000
        ButtonId       (string)  = "ButtonFinal"
        IsFinalButton  (boolean) = true   ← NUEVO
```

Sin este Attribute en al menos un botón, `TycoonManager:Rebirth` siempre
devolverá `false, "Este tycoon no tiene un Rebirth configurado todavía."`
— es un fallo seguro, nunca deja renacer "por accidente".

### 13.3 Nuevos RemoteEvents

En `ReplicatedStorage > Remotes`, añade:

```
ReplicatedStorage
└── Remotes (Folder)
    ├── RequestRebirth      (RemoteEvent)  <- Cliente → Servidor: "quiero renacer" (sin parámetros)
    ├── RebirthResult       (RemoteEvent)  <- Servidor → Cliente: {Success, Reason}
    ├── RequestUnlockSkill  (RemoteEvent)  <- Cliente → Servidor: (nodeId: string)
    └── SkillTreeUpdated    (RemoteEvent)  <- Servidor → Cliente: {Success, NodeId, Reason}
```

### 13.4 Qué hace exactamente `TycoonManager:Rebirth(player)`

```lua
remotes.RequestRebirth:FireServer()

remotes.RebirthResult.OnClientEvent:Connect(function(result)
    if result.Success then
        print("¡Has renacido! +1 Punto de Renacimiento")
    else
        print("No se pudo renacer: " .. result.Reason)
    end
end)
```

En el servidor, en orden:

1. Busca el botón con `IsFinalButton = true` en el tycoon del jugador y
   comprueba `DataManager.HasPurchasedButton(player, finalButtonId)`. Si
   no lo tiene comprado, devuelve `false` sin tocar NADA más.
2. `DataManager.AddRebirthPoints(player, 1)` — la única forma de ganar
   Puntos de Renacimiento en este diseño base (puedes ampliarlo para dar
   más de 1 en tycoons más avanzados, si quieres).
3. `DataManager.ResetForRebirth(player)` — pone `Money = 0` y
   `PurchasedButtons = {}`. **Nada más se toca**: `Pets`, `Core`
   (`PendingMoney`), `Gems`, `SelectedSkin`, `RebirthPoints`,
   `UnlockedSkills`, `ProcessedPurchaseIds` y `PendingClone` quedan
   exactamente igual que antes de renacer.
4. `ButtonService.ResetTycoonToBase(tycoonModel, IncomeManager)` — oculta
   de nuevo todo lo que estaba revelado, vuelve a hacer tocables todos los
   botones, borra el Attribute interno que marca los generadores como
   activados (para que puedan reactivarse al comprar de nuevo su botón), y
   pone a 0 la tasa de ingresos cacheada de ESE tycoon en `IncomeManager`.

### 13.5 Cómo se aplican los tres tipos de efecto del Skill Tree

| EffectType | Dónde se aplica | Cómo se combinan varios nodos |
|---|---|---|
| `ButtonDiscount` | `ButtonService._HandlePurchase`, ANTES de cobrar | Se SUMAN (Discount_1 + Discount_2 + Discount_3), con techo en `BuffManager.MAX_BUTTON_DISCOUNT` (90%) para que un botón nunca sea gratis. |
| `EggLuckBoost` | `EggService`, en cada eclosión | Se SUMAN como tiradas extra, junto con la tirada extra del Gamepass "x2 Luck" si lo tiene — todas comparten el mismo mecanismo "quédate con la más rara de todas". |
| `MaxEquippedBoost` | `PetInventoryManager`, al equipar | Se SUMAN al límite base (3) y al bonus del Gamepass "+1 Equip" si lo tiene. |

`BuffManager.Recalculate` es la ÚNICA función que lee `UnlockedSkills` y
hace la suma por tipo — el resto de sistemas solo leen los tres totales
ya calculados (`GetButtonDiscount`, `GetExtraLuckRolls`,
`GetMaxEquippedBonus`), igual que `MultiplierManager`/`GamepassManager`
para sus propios cachés.

### 13.6 Por qué el Skill Tree es a prueba de exploits

- `SkillTreeService` comprueba `DataManager.HasUnlockedSkill` ANTES de
  cobrar: un nodo no se puede "comprar" dos veces (lo que duplicaría su
  `EffectValue` en `BuffManager.Recalculate` si no se bloqueara).
- La dependencia de rama (`RequiredNode`) se valida en servidor: no hay
  forma de saltarse `Discount_1` para comprar `Discount_2` directamente,
  por mucho que el cliente intente enviar ese `nodeId` sin más.
- El gasto pasa por `DataManager.TrySpendRebirthPoints`, el mismo patrón
  de "único punto de gasto" que `TrySpendMoney`: si no hay puntos
  suficientes, no pasa nada más.
