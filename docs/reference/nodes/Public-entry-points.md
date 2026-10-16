## Public entry points

| Export | Contract |
|---|---|
| `VERSION` | The package version string. |
| `Compose` | The pinned Compose core module, by reference. Use its cells, formulas, owners and structural operations directly. |
| `Roblox` | The pinned Compose Roblox module, by reference. `createRuntime(engine?)` makes the native runtime. `createHost(engine?)` makes its host. |
| `controls(runtime, options?)` | Returns the control constructor table for that native runtime. |
| `host(runtime)` | Returns `runtime.constructors` with the `Host` type. Use it for native objects: `local Host = Facet.host(runtime)`. |
| `app(options?)` | Returns an app: a runtime, the controls for it, and a `mount` that adds the ScreenGui, the StyleSheet and the StyleLink. See [Mounting](Mounting.md). |
| `themes` | Theme package definitions, native StyleSheet compilation, icons and skins. |
| `COMPOSE_COMMIT` | The full Compose commit of the pinned copy. The Facet tests use this commit. |
| `civilDate` | Calendar arithmetic, words and fixed-offset instants for civil dates. See [Civil dates](Civil-dates.md). |
| `adaptive` | Pure size, height, orientation, axis and column decisions. See [Adaptive environment](Adaptive-environment.md). |
| `gamepadContention` | Probes and the one remedy for the legacy player scripts that hold ButtonA, the arrow keys and Tab. See [Facet.gamepadContention](Facet-gamepadContention.md). |
| `pathShapes` | Normalized arc, ring and needle points for `UI.Path`. See [Path shapes](Path-shapes.md). |
| `richText` | `escape` for player and server text inside rich text. See [Text](Text.reference.md). |
| `inputPriority` | `{ belowControls, aboveFacet }`: `InputContext.Priority` values just below and just above every input context Facet creates. A game shortcut at `belowControls` loses to any selected Facet control; one at `aboveFacet` wins over all of them. |
| `recipes` | Opt-in helpers. `recipes.arithmetic.parse` is a bounded arithmetic parser for a number field. See [Recipes](Recipes.md). |
| `bind(Compose, Roblox)` | Returns a Facet table whose `controls` and `themes` use the Compose core module and the Compose Roblox module that you give. See [Your own Compose](Your-own-Compose.md). |

The pinned Compose includes `Compose.createSlot` for owned native instances and
`Compose.geometry` for geometry calculations. It includes `Compose.focusNeighbor` for directional selection over
rectangles and `Compose.TileCollection` for camera-windowed tile scenes. Facet
uses `focusNeighbor` for its directional focus queries. See the
[upstream Compose API](https://github.com/voidmeld/compose/blob/e3c942cb1490f8b7bfc1af59e40cb20d447cd233/docs/api.md)
for these Compose contracts.

Open:

- [Call-style](Call-style.md)
- [Mounting](Mounting.md)
- [Types](Types.md)
- [Your-own-Compose](Your-own-Compose.md)
