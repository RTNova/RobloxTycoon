# Checklist Maestra — De estos archivos a un juego funcionando en Studio

Esta guía sustituye tener que ir saltando entre las 13 secciones del
`README.md`: aquí está TODO en el orden en que hay que hacerlo. El
`README.md` sigue siendo la referencia detallada de "por qué" cada cosa
es como es; esta checklist es el "qué hacer, en qué orden".

Se apoya en **Rojo**, la herramienta estándar de la comunidad para
sincronizar archivos `.lua` de tu ordenador directamente a Roblox Studio
en tiempo real — así no tienes que crear a mano los ~35 Scripts/ModuleScripts
de este proyecto ni copiar y pegar su contenido uno a uno.

---

## PASO 0 — Instalar Rojo (una vez, en tu ordenador)

1. **Plugin de Studio**: abre Roblox Studio → pestaña "Plugins" → busca en
   el Toolbox `Rojo` (por el usuario `rojo-rbx`) → instálalo. Esto añade un
   botón "Rojo" en la barra de Plugins de Studio.
2. **Rojo en tu sistema** (elige UNA opción):
   - Más simple: instala la extensión **"Rojo"** en VS Code (marketplace),
     que trae Rojo integrado sin pasos adicionales.
   - Alternativa por línea de comandos (si tienes Rust/Cargo instalado):
     `cargo install rojo`.
3. Verifica que tienes los archivos de esta entrega en una carpeta local,
   con esta forma exacta (todo lo que ves en el panel de archivos de esta
   conversación, descargado a tu disco):

   ```
   TuProyecto/
   ├── default.project.json      ← el que te acabo de generar
   ├── README.md
   ├── ReplicatedStorage/
   ├── ServerScriptService/
   └── StarterPlayer/
   ```

## PASO 1 — Primera sincronización con Rojo

1. En VS Code (o terminal), abre la carpeta `TuProyecto/`.
2. Ejecuta `rojo serve` (o el botón "Start Server" de la extensión).
3. En Roblox Studio, abre tu juego (o crea uno nuevo), pulsa el botón
   "Rojo" del plugin → "Connect".
4. Pulsa "Sync In". Cuando termine, tu Explorer de Studio ya debería tener:
   - `ReplicatedStorage > Modules` con los **14 ModuleScripts** compartidos
     (AudioManager, MusicConfig, SFXConfig, CoreConfig, DevProductConfig,
     EggsConfig, GamepassConfig, NumberFormat, PetManager, PetsConfig,
     SkillTreeConfig, SkinsConfig, TycoonConfig, WeightedRNG).
   - `ReplicatedStorage > Assets` con dos carpetas vacías: `PetModels` y
     `CoreSkins` (las rellenas tú a mano en el Paso 5).
   - `ReplicatedStorage > Remotes` con los **13 RemoteEvents/RemoteFunction**
     ya creados automáticamente (ver la lista completa en el Apéndice A).
   - `ServerScriptService > Main` (Script) y
     `ServerScriptService > Modules` con los **15 ModuleScripts** del
     servidor.
   - `StarterPlayer > StarterPlayerScripts` con `Main`, `CoreVisuals` y la
     carpeta `Controllers` (3 ModuleScripts).
   - `Workspace > Tycoons` (carpeta vacía) y `Workspace > MapCenter`
     (una Part ya configurada como invisible/sin colisión).

   A partir de aquí, cualquier cambio que yo te dé en una conversación
   futura: lo guardas en el archivo `.lua` correspondiente de tu carpeta
   local, y aparece solo en Studio la próxima vez que sincronices — nunca
   más copiar/pegar código a mano.

## PASO 2 — Instalar ProfileService (manual, fuera de Rojo)

Deliberadamente NO viene por Rojo (ver nota en `default.project.json`).

1. Toolbox de Studio → busca `ProfileService` (autor **loleris**).
2. Arrástralo dentro de `ServerScriptService`, como **hermano** de `Main`
   y `Modules` (no dentro de `Modules`).
3. Renómbralo exactamente `ProfileService` si no viene así.

Como no está declarado en `default.project.json`, sobrevive a cualquier
sincronización futura de Rojo sin que se borre ni se sobrescriba.

## PASO 3 — Etiquetas (Tags) y Atributos (Attributes)

Esto es lo único que Rojo no puede automatizar por ti porque depende de
CADA Part concreta que construyas en el Paso 4. Usa esta tabla como
referencia rápida mientras construyes:

| Instancia | Tag (CollectionService) | Attributes |
|---|---|---|
| Cada botón de compra | `TycoonButton` | `Cost` (number), `ButtonId` (string, único por tycoon), `IsFinalButton` (boolean, **solo** en el último botón de cada tycoon) |
| Cada generador de ingresos dentro de `Stuff` | `IncomeGenerator` | `MoneyPerSecond` (number) |
| El `CoreBody` de cada prefab de skin (`CoreCrystal`, `CoreSakura`) | *(Rojo/SkinController lo etiqueta solo en runtime, no lo pongas a mano)* | — |

## PASO 4 — Construir el Workspace (manual, específico de tu mapa)

Sigue, EN ESTE ORDEN, las instrucciones ya detalladas en el README:

1. **§5** — Un `Model` por plot dentro de `Workspace.Tycoons`
   (`Tycoon1`, `Tycoon2`...), cada uno con `ClaimPad`, `Buttons/`, y
   `CoreAnchor` (§9.3). Aplica la tabla del Paso 3 a cada botón.
2. **§9.6** — Dentro de la carpeta `Stuff` de cada botón que deba generar
   dinero, el marcador `IncomeGenerator` con su `MoneyPerSecond`.
3. **§13.2** — En el ÚLTIMO botón de cada tycoon, añade `IsFinalButton = true`.
4. **§9.4** — Los dos prefabs de skin (`CoreCrystal`, `CoreSakura`) dentro
   de `ReplicatedStorage.Assets.CoreSkins`, cada uno con una parte
   `CoreBody` y un `PointLight` llamado `CoreLight`.
5. **§12.2** — Coloca `Workspace.MapCenter` (ya creado por Rojo) en el
   punto real desde el que quieres medir las zonas de música.
6. **§12.5** — Si vas a usar la Opción A de audio espacial (Sound fijo
   dentro de cada huevo físico), configúralo ahora con la tabla de
   RollOff de esa sección.

## PASO 5 — Subir Assets (manual: audio y modelos 3D)

1. **§10.3** — Un `Model` por especie dentro de
   `ReplicatedStorage.Assets.PetModels`, con el nombre EXACTO de cada
   `PetId` de `PetsConfig.lua` (`Pet_Cat`, `Pet_Rabbit`, `Pet_Fox`,
   `Pet_Shark`, `Pet_Dragon`, `Pet_Phoenix`, `Pet_Unicorn`, `Pet_VoidWyrm`).
2. **§12.3** — Sube tus pistas de música y SFX (Asset Manager de Studio),
   y sustituye los `rbxassetid://000...` placeholder en `MusicConfig.lua`
   y `SFXConfig.lua` por los IDs reales.

## PASO 6 — Construir la UI en StarterGui (manual, específico de tu diseño)

Sigue **§10.2** al pie de la letra para los nombres (los controladores de
cliente los buscan con `WaitForChild`, así que un nombre distinto rompe
el enganche): `MainHUD > TopBar > MoneyLabel`, y todo el árbol de
`InventoryFrame` (`GridContainer` + `PetCardTemplate`, `StatsPanel` +
`PetViewport` + las etiquetas de desglose de poder).

## PASO 7 — IDs reales de monetización

**§11.2** — Publica el juego al menos una vez, crea los 3 Game Passes
(`VIP`, `x2 Luck`, `+1 Equip`) y los 4 Developer Products
(`MoneyPack_Small/Medium/Large`, `PetCloneFee`), y sustituye los IDs
placeholder en `GamepassConfig.lua` y `DevProductConfig.lua`.

## PASO 8 — Primera prueba

1. En Studio, pulsa "Play" (F5) con al menos 2 jugadores simulados
   (Test → "Start Server and 2 Players") para poder probar la reclamación
   de tycoon, la compra de botones y — más adelante — la clonación social.
2. Revisa la ventana de Output: cualquier `warn()` de los scripts te dirá
   exactamente qué Attribute, Tag o instancia te falta (todos los módulos
   de esta entrega avisan por nombre del problema en vez de fallar en
   silencio).

---

## Apéndice A — Los 13 Remotes (ya creados por Rojo en el Paso 1)

| Remote | Tipo | Para qué |
|---|---|---|
| `RequestOpenEgg` | RemoteEvent | Cliente pide abrir un huevo |
| `EggResult` | RemoteEvent | Servidor confirma qué mascota tocó |
| `RequestEquipPet` | RemoteEvent | Cliente pide equipar/desequipar |
| `GetPetInventory` | RemoteFunction | Cliente pide su inventario completo |
| `InventoryUpdated` | RemoteEvent | Servidor avisa de que el inventario cambió |
| `RequestChangeSkin` | RemoteEvent | Cliente pide cambiar el skin del Núcleo |
| `RequestClonePet` | RemoteEvent | Cliente pide clonar la mascota de otro jugador |
| `CloneResult` | RemoteEvent | Servidor confirma el resultado al comprador |
| `CloneNotification` | RemoteEvent | Servidor avisa al dueño original de que le clonaron una mascota |
| `RequestRebirth` | RemoteEvent | Cliente pide renacer |
| `RebirthResult` | RemoteEvent | Servidor confirma el resultado del Rebirth |
| `RequestUnlockSkill` | RemoteEvent | Cliente pide desbloquear un nodo del Skill Tree |
| `SkillTreeUpdated` | RemoteEvent | Servidor confirma el resultado del desbloqueo |

## Apéndice B — Orden de lectura del README si prefieres el detalle completo

`§1-2` base y ProfileService → `§3-6` estructura del tycoon original →
`§7-8` Pet Simulator y UI → `§9` Núcleo Central → `§10` UI del cliente →
`§11` Monetización → `§12` Audio → `§13` Rebirth y Skill Tree.
