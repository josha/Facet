# Virtual monitors

Three applications share one Compose Roblox runtime and one durable model. Facet
provides controls; Roblox provides the Instances, layouts, scrolling, input and
styling. `Host` is the runtime's native constructor table.

- **Discover:** a paged, windowed catalog with procedural game previews, featured
  content with native swipe paging, search suggestions, genre and sort choices,
  detail previews, six similar games, personal star ratings and trend lines. The
  saved table has sortable columns, selection, drag ordering and notes that commit
  on Return/focus loss or restore their previous value on Escape.
- **Avatar:** an animated R15 explorer, with a procedural fallback, palette and hat
  choices, rotation, shared turn increments, auto-spin, reset confirmation and a
  summary sheet with retained detents. Disclosure state and compact HUD values
  survive presentation changes. The preview and settings share a row when space
  permits and stack otherwise.
- **Chat:** editable prompts, persistent messages, streaming local replies, Stop,
  message removal, Clear, persistent suggested prompts and optional end following.
  Send can start a fresh conversation while preserving the draft; the next draft
  stays editable during a reply. Native row measurements feed Compose's ordered
  collection.

The header switches appearance and spatial/screen presentation. In spatial mode,
Focus fits a monitor to the camera; All monitors returns to the overview. In
screen mode, native Facet tabs select the application. Model state survives page
and monitor disposal. Compact viewports and native ten-foot interfaces initially choose screen mode; an explicit
choice takes precedence.

The caller mounts ordinary `Host.SurfaceGui` and `Host.ScreenGui` instances with
`runtime.mount`. Each surface declares a native StyleSheet and StyleLink. The
world, camera springs, procedural preview scenes, reactive bindings and mounted
branches all use the same Compose runtime. One frame subscription advances model
data and the camera; its lifetime belongs to the root Compose owner.

Collections use Facet's native `VirtualGrid`, `VirtualList` and `Table` controls, which
consume Compose `OrderedCollection` placements. Compose preserves the visible
anchor during sorting and updates the actual Roblox scroll position. A sort does
not promise to jump to the first item. Avatar animation and scene clocks obey
reduced motion. Modals use Facet controls for native selection and dismissal.

`model.luau`, `catalog.luau` and `chat_model.luau` contain application data and
commands. They contain no UI objects or independent timers. `screens.luau` builds
Discover and shares ordinary native composition helpers with `avatar.luau` and
`chat.luau`. `desktop.luau` supplies the tabs, and `scenes.luau` supplies procedural
and R15 scene content. Only the active presentation publishes native scrolling
back into the shared model during a presentation transition.

Build from the repository root:

```sh
rojo build examples/virtual_monitors/default.project.json -o artifacts/virtual-monitors/virtual-monitors.rbxl
open -a RobloxStudio artifacts/virtual-monitors/virtual-monitors.rbxl
```

Press Play in Studio. The showcase needs no character and stays local and
unpublished. The monitors are flat two-dimensional interfaces placed in the
world; they provide no VR ray, gaze or hand-input implementation.

Automated behavior coverage lives in `tests/native_virtual_monitors.spec.luau`.
Studio evidence must exercise both presentations, Discover filtering/sorting and
details, saved notes, Avatar settings, streaming Chat, appearance changes and
teardown. A successful build or headless test is not a substitute for that check.
