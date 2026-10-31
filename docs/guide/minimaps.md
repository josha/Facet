# Minimap patterns

Use a minimap when the player needs spatial information during play. A race
course can show the whole circuit. A radar can show nearby contacts without
terrain. An exploration map can show rooms, routes and discoveries. A simple
objective label or compass can be enough when the player does not need a map.

Facet supplies layout, input, navigation and pan/zoom controls. The game owns
map drawing, coordinates, orientation, detection, visibility and markers.
There is no `UI.Minimap` control. Compose the existing controls around native
content.

## Choose the views

Treat these as separate choices:

| Choice | Examples |
| --- | --- |
| HUD size | Normal map, compact map, Map button |
| World coverage | Entire circuit, nearby area, radar range |
| Orientation | North up, player heading up, fixed course orientation |
| Interaction | Passive display, open map, select a marker, place a ping |
| Larger presentation | Larger HUD view, contextual panel, full-screen page |

A smaller HUD does not have to show less world area. It can omit minor labels
while keeping the same course. Keep important markers and touch targets
readable. Use `UIScale` for artwork when uniform scaling fits the task; do not
shrink all controls and labels to solve a layout problem.

An interactive map does not have to open on tap. If a tap selects a marker or
places a ping, provide a separate Open map button. A passive radar can have no
expansion route at all. A plugin can use the same drawing and ZoomView inside
its existing host without a gameplay HUD or full-screen route.

## Place the HUD

Put the map in the same `Composition` as the other HUD regions. Give the map
`Region` stable native forms, richest first. Each form needs an intrinsic or
pixel size. A fill-sized form cannot tell Composition how much room it needs.
Use the `form` cell to decide which renderer is active.

For example, a game's normal map, compact map and labeled launcher can be:

```luau
UI.Region "Map" {
    zone = "topRight", rank = 2, reveal = false, form = mapForm,
    normalMap,
    compactMap,
    UI.Button { label = "Map", shortcutHint = mapAction, onActivate = openMap },
}
```

The variables in this fragment are game-owned native views, a writable form
cell, a bound InputAction and one opening callback. The corner, rank and form
sizes are choices for that game's sight lines and competing HUD tasks.

By default a reduced Region opens its richest form in a Popover. Its `expand`
factory also supplies Popover content. Use `reveal = false` when your forms
provide their own full-map route. Keep that route in every reduced form. Do
not set `mayDrop = true` unless another reachable command can open the map.

For a display-only map that opens on tap, put a named transparent Facet Button
above the artwork. Give it the map's bounds and `BackgroundTransparency = 1`.
Keep selectable marker controls out of that hit surface. Passive artwork is
not selectable. A separate labeled button makes the opening action visible.

A HUD Composition is passive for controller navigation. Bind a game-owned
InputAction to the same opening callback; `shortcutHint` only displays the
binding. Enable that command only while the HUD is available and no other
surface owns the task. The example uses M and gamepad Y; these are sample
bindings, not reserved map commands.

## Open a full map and return

Use one `NavigationStack` at the screen root. Its root contains the HUD; its
map destination contains a `Screen`, a NavBar with Close, and a bounded
`ZoomView`. Keep the route and shared map state outside destination content.
Use hidden stack chrome when the destination supplies its own header. The
stack still owns Escape, gamepad B, edge Back and selection restoration.

Use expansion rather than the stack's default lateral page movement when a
map grows out of the HUD. A simple centered treatment uses `transition =
{ zoom = 0.25 }`. The Lab example uses the existing custom transition hook to
scale and position the full page from the current HUD form's bounds, using
the theme's `zoomPresent` timing. Reduced motion uses the framework's fade.
Keep both drawings mounted through the handoff: removing full-map art when
the route clears makes it disappear before the closing animation ends.
Let the destination owner release that drawing after departure completes.
See [custom transitions](../reference/nodes/Custom-transitions.md).

The [page recipe](../reference/nodes/Tasks.pages.md) shows this route structure.
Mount it at the app root to fill the screen. A nested stack fills its own
container, as it does in the Lab preview. A small temporary inspection can
instead use a Sheet or Popover.

Use `suspendGameplay = true` when opening the map should suspend gameplay
input. Game commands must read `UI.environment().gameplaySuspended`. This does
not pause the simulation or server. Do not bind Escape or gamepad Start to
your own map command.

`ZoomView` owns pan and zoom for one stable native content tree. Supply
`contentSize`, `content`, and an optional writable `zoom` cell. Its controls
include `fit`, `zoomAt` and `zoomTo`. Native gestures, keyboard and gamepad
input are already supported. Read the [ZoomView contract](../reference/nodes/ZoomView.reference.md).
Keep frequently used map controls outside its scaled content if they need a
constant readable size. Do not give the HUD the full map's zoom cell unless
they should change together.

Define the return policy. The example preserves radar range, orientation and
zoom, and rebuilds the full-map pan position when it reopens. A game that needs
to preserve a manually chosen location should retain that location in its map
model and apply it through ZoomView's `focus` contract.

## Draw only what the game needs

Use a native ImageLabel for prepared map art, native GUI objects for a simple
schematic, or a ViewportFrame for a game-owned scene. Do not clone a whole live
world merely to fill a small HUD. World-to-map projection, marker filtering,
fog, pings, elevation and route generation remain game rules.

Rectangular clipping can use `ClipsDescendants`. A normal UICorner does not
clip descendants to a circle. Use a CanvasGroup with UICorner when the drawing
needs a circular mask, and keep the app's `ZIndexBehavior = Sibling`. CanvasGroup
uses an intermediate texture; prefer stable sizes and check its memory and
quality on target devices. Rotation also has native clipping constraints.
See [Roblox clipping](https://github.com/Roblox/creator-docs/blob/main/content/en-us/includes/ui/clipping.md)
and [CanvasGroup](https://create.roblox.com/docs/reference/engine/classes/CanvasGroup).

Keep static artwork stable. Update only moving markers at the rate the game
needs. A hidden form is not automatically disposed, and some closed surfaces
retain their bodies. Use `Compose.show` inside a stable form to mount only its
active drawing. Own update subscriptions with `Compose.cleanup`; stop costly
work when hidden. Avoid one world subscription per marker or form.

## Try the example

Open **Minimap patterns** in the Facet Lab. The course uses a schematic and
moving racers. The radar uses relative positions, a range filter and an
optional heading-up view. The passive radar has no opening action. These
illustrative renderers share the same HUD and navigation structure.

- [Composition and interaction source](../../examples/facet-lab/src/minimap_demo.luau)
- [Replaceable drawing source](../../examples/facet-lab/src/minimap_art.luau)
- [Standalone project](../../examples/minimap/default.project.json)

From the repository root:

```sh
rojo build examples/minimap/default.project.json -o build/Facet-Minimap.rbxl
open -a RobloxStudio build/Facet-Minimap.rbxl
```

Press Play. Try Race course and Radar. Resize the viewport, open the map from
the picture or the button, change radar settings, then close and reopen it.
Run starts the sample simulation, Pause stops it, and Advance moves one step. Reduced motion
also stops automatic movement. A real game's moving objects still follow its
own simulation policy.

Check pointer and touch activation, the controller opening command, B and
Escape, focus return, pan/zoom, hidden updates, and gameplay input restoration.
Check phone rotation, large text, native movement-control clearance, and the
circular mask. The sample has no character controls; it cannot prove clearance
for the consumer game's movement controls. Distinguish the white player arrow,
round contacts and diamond checkpoint without relying on color alone.
