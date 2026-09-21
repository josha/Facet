# Virtual monitors

The widest showcase in the repository. Three Facet applications share a virtual
desktop, and between them they exercise every public control and every public
modifier, on a world surface and on a screen, under two themes and two
appearances.

## The three applications

- **Discover** — an endless, windowed game catalog. Each mounted card contains a
  small animated 3D world. Selecting a game expands its measured card into the
  detail panel; Back reverses the motion. The detail preview shows the selected
  world.
- **Avatar** — an R15 preview with idle animation, palette, rotation and hat
  controls. The preview and controls sit side by side on wide screens and stack
  on narrow ones. The settings scroll beside or beneath the pinned preview when
  they exceed the available height.
- **Chat** — an editable composer, persistent history, streamed simulated
  replies and a Stop action. Measured rows keep long conversations windowed.

The header switches between Screen and Spatial modes and between Light and Dark
appearance. Both presentations share application state and scroll positions.
Screen mode uses adaptive application tabs. Spatial mode places the same flat
interfaces on three monitors. Click anywhere on an inactive monitor or use
**Focus** to enter it, and **All monitors** to return to the overview. A compact
viewport or a ten-foot display chooses Screen mode until the viewer chooses
otherwise.

## What it demonstrates

**Hosting.** `Facet.new` builds four applications. Three take
`surface = { kind = "surface", target = part, face = …, canvas = …,
maxDistance = … }` and paint a monitor; the fourth is an ordinary screen
application with a `displayOrder`. `app.installTheme` installs a per-application
theme package with native StyleSheet transitions, `app.mount` mounts and
unmounts a monitor as it becomes visible or covered, and `app.dispose` releases
everything when the script is destroyed. `app.onFrame` drives the camera, the
chat model and the catalog from the host's own frame source.

**Every control.** Layout and structure: `UI.Screen`, `UI.VStack`, `UI.HStack`,
`UI.ZStack`, `UI.AdaptiveStack`, `UI.Grid` / `UI.GridRow`, `UI.Composition`,
`UI.Region`, `UI.ViewThatFits`, `UI.ScrollView`, `UI.Spacer`, `UI.Divider`,
`UI.Box`. Content: `UI.Text`, `UI.Label`, `UI.Image`, `UI.AsyncImage`,
`UI.Path`, `UI.Stage`, `UI.Foreign`. Values and commands: `UI.Button`,
`UI.SplitButton`, `UI.PopupButton`, `UI.Toggle`, `UI.Slider`, `UI.Stepper`,
`UI.Rating`, `UI.LevelPicker`, `UI.Picker`, `UI.ComboBox`, `UI.Chip`,
`UI.TextInput`, `UI.TextField`, `UI.ProgressView`. Navigation and disclosure:
`UI.TabView`, `UI.NavigationStack`, `UI.PageView`, `UI.DisclosureGroup`,
`UI.CollapsibleView`, `UI.Menu`, `UI.RadialMenu`. Presented surfaces:
`UI.Alert`, `UI.Sheet`, `UI.Callout`. Collections: `UI.VirtualGrid`,
`UI.VirtualList`, `UI.Table`, `UI.RowActions`.

**The modifiers.** `UI.corners`, `UI.cornersData`, `UI.shadow`, `UI.strokeData`,
`UI.background`, `UI.overlay`, `UI.padding`, `UI.frame`, `UI.offset` (under the
`UI.Anchor` that reads it), `UI.aspectRatio`, `UI.containerRelativeFrame`,
`UI.fill`, `UI.hug`, `UI.styleGroup`, `UI.focusSection`, `UI.sensoryFeedback`,
`UI.activationGate`, `UI.draggable`, `UI.dropTarget`, and the `UI.navBar`
surface bar.

`UI.gradient` is deliberately **not** used. Its colour names are resolved once,
against the style the blueprint is built with, and on the native target that
resolution cannot be redone — colour reaches a live screen as StyleSheet rules
keyed on a node's tags, while the target's own style value table is fixed at
construction. A token-coloured wash therefore survives a theme swap unchanged,
which this showcase demonstrated as an unreadable near-black hero card sitting
in the light theme. A surface tag swaps; a baked ramp does not.

**Collection depth.** The catalog is a `UI.VirtualGrid` with a fixed
`itemExtent` and named scroll navigation. The saved list is a `UI.Table` with
single selection, reordering and a `ref` that hands the host its record. The
conversation is a `UI.VirtualList` with `itemExtent = "measured"`, a `follow`
readable that tracks new replies until the reader scrolls away, and
`rowActions`.

**Presentation.** `app.presentModal` opens a full task, `app.presentAnchored`
opens a surface attached to a row, and `app.presentToast` confirms a command.
`UI.Alert` and `UI.Sheet` bind their presentation to Compose cells, and the
sheet carries a detent cell.

**Motion.** `transition = { enter = "transform", source = { path = … } }` grows
the detail view out of the card that opened it, and the source rect is re-read
each painted frame. `UI.NavigationStack` pages slide. Tab pages fade.
`Facet.motion.newTextReveal` streams a reply into a `UI.Text` without splitting
a codepoint. `app.runtime` and a Compose Roblox runtime drive the camera spring,
the mode tween and each card's timeline. Reduced motion settles transitions and
pauses decorative animation; hidden previews pause their own.

**Input.** `UI.activationGate` spends an inactive monitor's first press on
waking it, for every input class at once. `UI.draggable` and `UI.dropTarget`
move a card onto a shelf. `UI.focusSection` groups the settings column.

**Resources and containment.** `app.newResourceProvider` leases the avatar
images `UI.AsyncImage` shows, with a shimmering `UI.Foreign` placeholder adopted
through the node's own `onHost` seam. `Compose.boundary` quarantines a 3D scene
factory failure to its own reserved box.

**State.** Compose owns everything: `Compose.cell` for model and interaction
state, `Compose.formula` for derived lists, `Compose.watch` for reactive effects,
`Compose.show` for branches and `Compose.keyed` for small mounted collections.
Every model cell lives outside the screens, so mode switches, page evictions and
monitor unmounts keep selections, drafts and scroll positions. `chat_model.luau`
and `catalog.luau` are pure data models: no network, no timer, no UI object, and
no AI service.

## Files

| File | What it is |
|---|---|
| `main.client.luau` | The host: world geometry, the four applications, the camera, theme installation and teardown. |
| `screens.luau` | The three applications' views, built from `app.controls`. |
| `desktop.luau` | Screen mode's `UI.TabView` shell over the same three views. |
| `scenes.luau` | The 3D content each `UI.Stage` shows, built on a Compose Roblox runtime. |
| `catalog.luau` | Deterministic local catalog data and its paging. |
| `chat_model.luau` | The conversation model and its character streaming. |
| `icons.luau` | Vector icon shapes drawn through `UI.Path`. |
| `theme.luau` | The per-application theme packages, Light and Dark. |
| `default.project.json` | The Rojo project. |

## Running it

From the repository root:

```sh
python3 tools/sync_compose.py
rojo build examples/virtual_monitors/default.project.json -o artifacts/virtual-monitors/virtual-monitors.rbxl
open -a RobloxStudio artifacts/virtual-monitors/virtual-monitors.rbxl
```

Use the standard HD 1080 desktop emulator and press Play. No character is
needed. Keep this showcase local and unpublished.

Device and interaction evidence is recorded in
`artifacts/virtual-monitors/studio-evidence.md`. Desktop evidence does not
establish mobile, console or VR support. The world-fixed monitors are flat
screens; they do not provide a 3D layout system or a VR pointer input path.
