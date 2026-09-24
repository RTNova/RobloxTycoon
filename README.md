<div align="center">

# 🏭 RobloxTycoon

**Un framework de tycoon modular para Roblox, con Núcleo Central, sistema de mascotas estilo gacha, monetización completa, árbol de habilidades y Rebirth — todo server-authoritative.**

![Roblox](https://img.shields.io/badge/Roblox-Studio-E2231A?logo=roblox&logoColor=white)
![Luau](https://img.shields.io/badge/lenguaje-Luau-00A2FF)
![Arquitectura](https://img.shields.io/badge/arquitectura-server--authoritative-success)
![Estado](https://img.shields.io/badge/estado-en%20desarrollo-orange)
![Licencia](https://img.shields.io/badge/licencia-MIT-green)

</div>

---

## 📖 Tabla de contenidos

- [Sobre el proyecto](#-sobre-el-proyecto)
- [Características](#-características)
- [Cómo se juega](#-cómo-se-juega)
- [Arquitectura](#-arquitectura)
- [Estructura del repositorio](#-estructura-del-repositorio)
- [Sistemas principales](#-sistemas-principales)
  - [Núcleo Central (economía base)](#1-núcleo-central-economía-base)
  - [Mascotas y huevos (gacha)](#2-mascotas-y-huevos-gacha)
  - [Multiplicadores](#3-multiplicadores)
  - [Rebirth y Árbol de Habilidades](#4-rebirth-y-árbol-de-habilidades)
  - [Monetización](#5-monetización)
  - [Audio](#6-audio)
  - [UI del cliente](#7-ui-del-cliente)
- [Instalación](#-instalación)
- [Seguridad y anti-exploit](#-seguridad-y-anti-exploit)
- [Roadmap](#-roadmap)
- [Contribuir](#-contribuir)
- [Licencia](#-licencia)
- [Autor](#-autor)

---

## 🎯 Sobre el proyecto

**RobloxTycoon** no es un tycoon clásico de droppers físicos: es un **Núcleo Central abstracto** que acumula dinero pendiente por segundo según los generadores que el jugador ha comprado, multiplicado por las mascotas que lleva equipadas. Encima de esa base se apoya un sistema completo de progresión al estilo *Pet Simulator*: huevos con probabilidades ponderadas (incluyendo rarezas ultra bajas del 0.001%), un árbol de habilidades pagado con Puntos de Renacimiento, y monetización real con Gamepasses, Developer Products y clonación social de mascotas.

Todo el proyecto sigue una única regla de diseño: **el servidor decide, el cliente solo pide y muestra**. Ningún cálculo que afecte a la economía (coste, saldo, probabilidad, multiplicador) se ejecuta ni se confía nunca del lado del cliente.

---

## ✨ Características

- 💠 **Núcleo Central sin droppers físicos:** cero partes cayendo, cero colisiones — la economía se calcula de forma abstracta y escala sin lag con cientos de jugadores.
- 🥚 **Sistema de huevos (gacha) con RNG hardcore:** probabilidades representadas sobre una escala de hasta 10.000.000 para soportar rarezas del 0.009% (Mítica) y 0.001% (Secreta) sin errores de redondeo de punto flotante.
- 🐾 **Mascotas con desglose de poder:** cada mascota combina un `BaseMultiplier` de especie + un `VariantBonus` de variante (Normal / Shiny / Dorado), mostrados por separado en la UI.
- 🍀 **Sistema de suerte genérico "tira N y quédate con la mejor":** el Gamepass x2 Luck y los nodos del Skill Tree se combinan sumando tiradas extra, sin tocar nunca los pesos del pool.
- 🌳 **Árbol de habilidades:** nodos con dependencias en cadena que otorgan descuento en botones, tiradas de suerte extra o hueco de equipo adicional.
- ♻️ **Rebirth (Renacimiento):** resetea selectivamente el progreso del tycoon (dinero y botones) a cambio de Puntos de Renacimiento — las mascotas y los buffos nunca se tocan.
- 💳 **Monetización completa:** paquetes de monedas, tres Gamepasses (VIP, x2 Luck, +1 Equipo) y un sistema de **clonación social de mascotas** entre jugadores, todo con `ProcessReceipt` a prueba de fallos (nunca se pierde el Robux del jugador).
- 🎨 **Skins del Núcleo intercambiables:** cualquier prefabricado que respete la convención `CoreBody` + `CoreLight` funciona automáticamente con el escalado y el parpadeo.
- 🔊 **Audio dinámico:** música por zonas con crossfade según la distancia al centro del mapa, pool de SFX anti-corte y audio espacial 3D reutilizable.
- 🖥️ **UI completa:** HUD con contador de dinero tipo "cuentakilómetros", inventario de mascotas con repoblación por diferencias (diff) y vista previa 3D en `ViewportFrame` con encuadre automático.
- 💾 **Persistencia robusta con ProfileService:** sesiones, reintentos e idempotencia de compras gestionados correctamente.
- 🔐 **100% server-authoritative:** cada sistema de esta lista está diseñado explícitamente para ser imposible de explotar desde el cliente (ver [Seguridad](#-seguridad-y-anti-exploit)).

---

## 🎮 Cómo se juega

1. El jugador toca un **ClaimPad** libre y se le asigna su propio tycoon.
2. Compra **botones** que revelan generadores de ingresos (`IncomeManager`), aumentando su tasa de dinero/segundo.
3. El **Núcleo Central** acumula ese dinero como "pendiente", creciendo visualmente y parpadeando más rápido cuanto mayor es la tasa.
4. El jugador **toca el Núcleo** para cobrar el dinero pendiente y convertirlo en saldo real.
5. Con ese saldo, abre **huevos** para conseguir mascotas que multiplican su ingreso al equiparlas.
6. Al completar el tycoon (botón final), puede hacer **Rebirth**: pierde el progreso del ciclo actual, gana un Punto de Renacimiento, y lo invierte en el **Árbol de Habilidades** para hacer el siguiente ciclo más rápido.
7. Opcionalmente, puede **clonar la mascota de otro jugador** pagando con Robux, o mejorar su cuenta con **Gamepasses**.

```
Comprar botón ──► Generador activo ──► Núcleo acumula $/s ──► Recolectar
      ▲                                                            │
      │                                                            ▼
 Árbol de Habilidades ◄── Puntos Renacimiento ◄── Rebirth ◄── Abrir huevos ◄── Equipar mascotas
```

---

## 🧱 Arquitectura

Modelo **cliente-servidor puro**: el cliente nunca toma ninguna decisión económica, solo envía intenciones (`RemoteEvent`) y refleja lo que el servidor confirma.

```
┌──────────────────────┐   RemoteEvent/Function    ┌──────────────────────────┐
│        CLIENTE       │ ────────────────────────► │         SERVIDOR         │
│  UI · Audio · Cámara │   "quiero comprar/abrir/   │  Valida · Calcula ·      │
│                       │    equipar/renacer..."    │  Cobra · Persiste        │
└──────────────────────┘ ◄──────────────────────── └──────────────────────────┘
                            estado confirmado
```

### Módulos del servidor (`ServerScriptService > Modules`)

| Módulo | Responsabilidad |
|---|---|
| `DataManager` | Única fuente de verdad de los datos del jugador (ProfileService). Dinero, mascotas, botones, skins, compras, Rebirth, Skill Tree. |
| `TycoonManager` | Asignación de plots, `ClaimPad`, y lógica de Rebirth de alto nivel. |
| `ButtonService` | Compra de botones server-authoritative, revelado de contenido y activación de generadores. |
| `IncomeManager` | Bucle único de ingresos para todo el servidor; recolección del Núcleo. |
| `EggService` | Apertura de huevos: coste, RNG ponderado, tiradas de suerte extra, variante. |
| `PetManager` / `PetsConfig` | Cálculo puro del poder de una mascota (Base + Variante) y roll de variante. |
| `PetInventoryManager` / `InventoryService` | Equipar/desequipar mascotas y sincronización del inventario con el cliente. |
| `MultiplierManager` | Multiplicador total de dinero según mascotas equipadas + bono VIP. |
| `BuffManager` | Totales combinados del Skill Tree (descuento, suerte extra, hueco de equipo). |
| `SkillTreeService` | Desbloqueo de nodos del árbol, validando dependencias y coste. |
| `RebirthService` | Puente fino entre el cliente y `TycoonManager:Rebirth`. |
| `SkinController` | Clonado y sustitución del prefab del Núcleo según la skin elegida. |
| `GamepassManager` | Caché de propiedad de Gamepasses y refresco en vivo tras una compra. |
| `DevProductHandler` | Único punto de `ProcessReceipt` del juego; registro genérico de handlers por producto. |
| `PetCloneService` | Flujo completo de clonación social de mascotas entre jugadores. |

### Módulos compartidos (`ReplicatedStorage > Modules`)

Configuración pública de balanceo (`*Config.lua`) y lógica pura sin efectos secundarios: `WeightedRNG`, `PetManager`, `NumberFormat`, `AudioManager` (cliente).

### Controladores del cliente (`StarterPlayerScripts`)

`HUDController`, `InventoryController`, `PetViewportController` y `CoreVisuals.client`, orquestados desde `Main.client.lua` sin acoplarse entre sí (se comunican mediante callbacks inyectados, no `require` directo).

### Principios de diseño

- **Servidor autoritativo sin excepciones:** todo lo que afecta a dinero, probabilidad o propiedad se valida y ejecuta en el servidor.
- **Configuración sobre código:** balanceo (costes, pesos, multiplicadores) vive en tablas de `ReplicatedStorage.Modules`, nunca hardcodeado en la lógica.
- **Caché en memoria + O(1):** `BuffManager`, `MultiplierManager` y `GamepassManager` cachean sus totales para que los sistemas críticos (compra, apertura de huevo, tick de ingreso) sean lecturas instantáneas.
- **A prueba de fallos en monetización:** `ProcessReceipt` nunca devuelve un resultado que pueda perder el Robux del jugador; siempre reintenta antes que arriesgar una recompensa no otorgada.
- **Desacoplamiento por inyección de dependencias:** los módulos del servidor reciben sus dependencias como parámetros en `Init(...)` en vez de hacer `require` cruzado, evitando dependencias circulares.

---

## 📁 Estructura del repositorio

```
RobloxTycoon/
├── ServerScriptService/
│   ├── Main.server.lua              # Único script que orquesta todo el servidor
│   ├── ProfileService/              # Dependencia externa (loleris)
│   └── Modules/
│       ├── DataManager.lua
│       ├── TycoonManager.lua
│       ├── ButtonService.lua
│       ├── IncomeManager.lua
│       ├── EggService.lua
│       ├── PetInventoryManager.lua
│       ├── InventoryService.lua
│       ├── MultiplierManager.lua
│       ├── BuffManager.lua
│       ├── SkillTreeService.lua
│       ├── RebirthService.lua
│       ├── SkinController.lua
│       ├── GamepassManager.lua
│       ├── DevProductHandler.lua
│       └── PetCloneService.lua
│
├── ReplicatedStorage/
│   ├── Remotes/                     # RemoteEvents / RemoteFunctions
│   ├── Assets/
│   │   ├── CoreSkins/                # Prefabs del Núcleo (CoreCrystal, CoreSakura...)
│   │   └── PetModels/                # Modelos 3D para el ViewportFrame
│   └── Modules/
│       ├── CoreConfig.lua
│       ├── TycoonConfig.lua
│       ├── EggsConfig.lua
│       ├── PetsConfig.lua
│       ├── PetManager.lua
│       ├── WeightedRNG.lua
│       ├── SkillTreeConfig.lua
│       ├── SkinsConfig.lua
│       ├── GamepassConfig.lua
│       ├── DevProductConfig.lua
│       ├── MusicConfig.lua
│       ├── SFXConfig.lua
│       ├── AudioManager.lua
│       └── NumberFormat.lua
│
├── StarterPlayer/
│   └── StarterPlayerScripts/
│       ├── Main.client.lua
│       ├── CoreVisuals.client.lua
│       └── Controllers/
│           ├── HUDController.lua
│           ├── InventoryController.lua
│           └── PetViewportController.lua
│
├── Workspace/
│   └── Tycoons/                     # Tycoon1, Tycoon2... (ClaimPad, Buttons, CoreAnchor)
│
├── LICENSE
└── README.md
```

> 💡 Ajusta este árbol si tu jerarquía real en Studio difiere ligeramente; refleja la ubicación que cada script indica en su propia cabecera de comentarios.

---

## 🔧 Sistemas principales

### 1) Núcleo Central (economía base)

En vez de generar partes físicas de dinero, cada generador comprado aporta una tasa de `MoneyPerSecond` que se suma a una caché por tycoon (`IncomeManager.baseRateByTycoon`). Un único bucle de servidor (una corrutina para *todos* los jugadores, no una por jugador) recorre esa lista cada `INCOME_UPDATE_INTERVAL` segundos y acumula `Dinero Pendiente` en el perfil de cada jugador, ya multiplicado por su bono de mascotas.

Visualmente, `CoreVisuals.client.lua` escucha esos valores replicados (`CoreData.PendingMoney` / `CoreData.IncomeRate`) y:
- Escala el `CoreBody` con un `Tween` según cuánto dinero pendiente hay (con techo en `MAX_PENDING_FOR_VISUAL`).
- Acelera el parpadeo de `CoreLight` según la tasa de ingreso actual.
- Detecta una recolección (el pendiente baja de golpe) para reproducir el SFX correspondiente.

### 2) Mascotas y huevos (gacha)

`EggsConfig` define cada huevo con un *pool* de mascotas y un peso relativo. Para representar probabilidades tan bajas como 0.001% sin errores de coma flotante, el sistema trabaja con **enteros sobre una escala de hasta 10.000.000** en vez de porcentajes sobre 100 (`WeightedRNG.Roll`).

El resultado de un huevo se compone de **dos tiradas independientes**:
1. **Especie** — ponderada por el pool del huevo.
2. **Variante** (Normal / Shiny / Dorado) — ponderada por separado en `PetsConfig.Variants`, aplicable a cualquier especie por igual.

La suerte extra (Gamepass `x2Luck` + nodos del Skill Tree) no toca los pesos del pool: en su lugar, se realizan **tiradas adicionales independientes** y se conserva la de mayor rareza (`PickRarerEntry`), reutilizando siempre el mismo `WeightedRNG`.

### 3) Multiplicadores

`MultiplierManager` calcula el multiplicador de dinero total de forma **aditiva sobre la base 1x**:

```
Multiplicador = 1 + Σ (Total_mascota_equipada − 1) + BonoVIP
```

Cada mascota aporta `PetManager.CalculatePetPower`, que desglosa `BaseMultiplier` (especie) + `VariantBonus` (variante) — mostrado en la UI como "Base · Variante · Total" por separado.

### 4) Rebirth y Árbol de Habilidades

Al comprar el botón marcado como `IsFinalButton = true` en Studio, el jugador puede renacer: gana 1 Punto de Renacimiento y su tycoon se resetea **selectivamente** (solo `Money` y `PurchasedButtons` — las mascotas y los nodos del árbol nunca se tocan).

Esos puntos se gastan en el **Árbol de Habilidades** (`SkillTreeConfig`), con nodos encadenados por `RequiredNode` que otorgan:
- `ButtonDiscount` — descuento aditivo en el coste de cualquier botón (con techo de seguridad al 90%).
- `EggLuckBoost` — tiradas extra al abrir huevos.
- `MaxEquippedBoost` — hueco adicional de mascotas equipadas.

`BuffManager` recalcula y cachea estos tres totales combinados cada vez que cambia algo, para que el resto de sistemas los lean en O(1).

### 5) Monetización

- **Paquetes de monedas y Gamepasses** (`DevProductConfig` / `GamepassConfig`): IDs centralizados, registro automático de handlers.
- **`DevProductHandler`** es el único punto que asigna `MarketplaceService.ProcessReceipt` en todo el juego, con idempotencia por `PurchaseId` y reintentos: **nunca se pierde el Robux de un jugador**, incluso si el servidor falla a mitad de proceso.
- **Clonación social de mascotas** (`PetCloneService`): un jugador paga por clonar la mascota de otro. El servidor valida que el objetivo siga existiendo *antes* de mostrar el prompt de compra, y compensa automáticamente con monedas si algo deja de ser válido entre la solicitud y la confirmación del pago (por ejemplo, el otro jugador se desconecta).

### 6) Audio

`AudioManager` (cliente) gestiona tres cosas de forma independiente:
- **Música dinámica** por zonas concéntricas alrededor del centro del mapa, con crossfade suave entre pistas.
- **Pool de SFX 2D** que crece bajo demanda para que dos clics rápidos suenen superpuestos en vez de cortarse.
- **Audio espacial 3D** de un solo uso, con autolimpieza tras reproducirse.

### 7) UI del cliente

- **`HUDController`** anima el contador de dinero con una interpolación exponencial ("efecto cuentakilómetros"), desconectando el bucle de renderizado en cuanto el número deja de moverse.
- **`InventoryController`** repuebla el grid de mascotas **por diferencias** (crea/actualiza/destruye solo lo que cambió) en vez de reconstruirlo entero en cada actualización.
- **`PetViewportController`** clona el modelo 3D de la mascota seleccionada en un `ViewportFrame` aislado, con encuadre de cámara automático según su tamaño real y rotación continua tipo "vitrina".

---

## 🚀 Instalación

### Requisitos

- [Roblox Studio](https://create.roblox.com/)
- [ProfileService](https://github.com/MadStudioRoblox/ProfileService) de *loleris* (dependencia externa, ver cabecera de `DataManager.lua`)
- *(Opcional)* [Rojo](https://rojo.space/) si prefieres sincronizar el código desde tu editor

### Pasos

1. Clona el repositorio:
   ```bash
   git clone https://github.com/RTNova/RobloxTycoon.git
   ```
2. Coloca `ProfileService` como `ModuleScript` directamente en `ServerScriptService > ProfileService` (hermano de la carpeta `Modules`, no dentro de ella).
3. Copia cada script a la ubicación indicada en su propia cabecera de comentarios (todos documentan su ruta exacta en Studio).
4. Construye la jerarquía de `Workspace.Tycoons` con al menos un `Tycoon1` que contenga `ClaimPad`, `Buttons` y `CoreAnchor`.
5. Crea los `RemoteEvents`/`RemoteFunctions` necesarios dentro de `ReplicatedStorage.Remotes` (uno por cada `WaitForChild` que verás en los servicios: `RequestOpenEgg`, `EggResult`, `RequestEquipPet`, `GetPetInventory`, `InventoryUpdated`, `RequestChangeSkin`, `RequestRebirth`, `RebirthResult`, `RequestUnlockSkill`, `SkillTreeUpdated`, `RequestClonePet`, `CloneResult`, `CloneNotification`).
6. Sustituye los **IDs placeholder** de `DevProductConfig.lua`, `GamepassConfig.lua`, `SFXConfig.lua` y `MusicConfig.lua` por tus IDs reales de Roblox.
7. Publica el juego y activa **Game Settings → Security → Enable Studio Access to API Services** para que el DataStore funcione en pruebas.

---

## 🔒 Seguridad y anti-exploit

Cada sistema de este proyecto está diseñado explícitamente para ser inmune a manipulación del cliente:

- **Compras de botones:** el cliente nunca envía coste ni resultado — el `Touched` se dispara en el servidor y `DataManager.TrySpendMoney` es el único punto de gasto.
- **Huevos:** el cliente solo dice "quiero abrir `EggId`"; especie, variante y coste se calculan y validan 100% en servidor, con cooldown anti-spam.
- **Inventario:** `InventoryService.GetPetInventory` usa el `Player` que Roblox garantiza en `OnServerInvoke` — es estructuralmente imposible pedir el inventario de otro jugador.
- **Equipar mascotas:** `DataManager.SetPetEquipped` busca el UUID solo dentro del perfil de quien hace la petición; un jugador no puede tocar el diccionario de otro.
- **Monetización:** `ProcessReceipt` centralizado, idempotente por `PurchaseId`, con `pcall` alrededor de cada handler para que un error nunca "trague" un pago real.
- **Clonación social:** la validación ocurre *antes* de mostrar el prompt de pago, nunca después, para que un jugador no pueda pagar por algo que ya no es posible completar.
- **Skill Tree y Rebirth:** el cliente solo envía un identificador; dependencias, coste y condición de renacer se comprueban íntegramente contra los datos del servidor.

---

## 🗺️ Roadmap

- [x] Núcleo Central abstracto (sin droppers físicos)
- [x] Sistema de huevos con RNG ponderado a gran escala
- [x] Mascotas con variantes y multiplicador desglosado
- [x] Rebirth + Árbol de Habilidades
- [x] Monetización (Gamepasses, DevProducts, clonación social)
- [x] Audio dinámico (música, SFX, espacial)
- [x] UI de HUD, inventario y viewport 3D
- [ ] Sistema de trading directo entre jugadores
- [ ] Leaderboard global (dinero, Rebirths, mascota más rara)
- [ ] Eventos temporales / huevos de tiempo limitado
- [ ] Soporte para mando y móvil en la UI
- [ ] Tutorial inicial para nuevos jugadores

---

## 🤝 Contribuir

1. Haz un *fork* del repositorio.
2. Crea una rama: `git checkout -b feature/mi-mejora`
3. Haz *commit* de tus cambios: `git commit -m "Añade mi mejora"`
4. Sube la rama: `git push origin feature/mi-mejora`
5. Abre un *Pull Request* describiendo qué cambia y por qué.

Si encuentras un fallo, abre un [issue](https://github.com/RTNova/RobloxTycoon/issues) con los pasos para reproducirlo.

---

## 📄 Licencia

Distribuido bajo la licencia **MIT**. Consulta el archivo [`LICENSE`](LICENSE) para más información.

---

## 👤 Autor

**Borja Corral Pérez**

- GitHub: [@RTNova](https://github.com/RTNova)
- LinkedIn: [Borja Corral Pérez](https://www.linkedin.com/in/borja-corral-pérez-080811317)

---

<div align="center">

⭐ Si el proyecto te resulta útil o interesante, ¡deja una estrella en el repositorio!

</div>
