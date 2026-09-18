# The standalone consumer

The smallest complete Facet project: a Rojo project file, one client script, and
one screen module. It is [guide chapter 3](../../docs/guide/03-getting-started.md)
as something you can build and press Play on.

```sh
rojo build examples/consumer/default.project.json -o build/Facet-Consumer.rbxl
```

Open the result in Roblox Studio and press Play. A panel appears with a title, a
sentence, a tap counter, a toggle, and two buttons. **Bump** raises the count;
**Close** tears the whole surface down. Clicking, pressing Enter, and pressing
gamepad A all work, because every Facet control is reachable from every input
class.

To develop against it instead of building a file, run `rojo serve` on the same
project and connect from Studio.

## What is in here

| File | What it is |
|---|---|
| `default.project.json` | Maps `src/` of the library to `ReplicatedStorage.Facet`, the screen module to `ReplicatedStorage.FacetConsumerScreen`, and the client script to `StarterPlayer.StarterPlayerScripts.FacetConsumer`. It also sets `Workspace.PlayerScriptsUseInputActionSystem`, which Facet's input layer requires and which cannot be set from code. |
| `src/screen.luau` | The screen itself: component state, property recipes, and the view — plus `session`, which presents it, wires both ways out of it, and tears it down in the right order. Takes `Facet` as an argument so the same module can be mounted by Roblox and by a headless test. |
| `src/main.client.luau` | The client script: wait for the DataModel, stand up a host, hand it to `screen.session`. Three statements. |

## What it demonstrates

- **A theme, applied.** The panel takes the `raised` surface and the count takes
  the accent tint, both resolved from the active theme rather than from a colour
  written here. Swap the theme and both follow with no rebuild.
- **Local state with automatic ownership.** `ui.state` returns a getter and setter.
  The count label is a recipe; the toggle uses `value` and `onChange`. Facet’s
  Compose runtime tracks these getters and releases their resources on unmount.
- **Adaptation with no device branch.** `ui.env("viewportRect")` tracks the available
  viewport, and `Facet.adaptive.axisFor` selects the stack axis.
- **The player's text size.** The blurb uses the body role and follows accessibility preferences.
- **Teardown that leaves nothing.** Dismissing the component releases its state,
  bindings and owned frame subscription. Close is a command callback. The session
  dismisses the surface before disposing the host, and both Close and the timer
  use that same teardown path.

## The proof

`tests/consumer_standalone.spec.luau` requires the same `src/screen.luau`, mounts
it against the headless fake render target, and proves it mounts, wears a theme,
answers a button press through the public input path, repaints when a signal
changes, re-solves when the viewport and the preferred text size change, and
returns the reactive registries to their baseline after teardown. It also drives
Close through the same `session` the client script uses, rather than tearing down
out of band, and proves that a screen disposed on a host that keeps running
releases the frame hook it registered. Run it on its own with:

```sh
lune run tests/run_one consumer_standalone
```

Nothing in this project reaches into a Facet internal, and nothing here belongs to
any particular game.
