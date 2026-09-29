# Facet API

Facet supplies controls that use the Compose Roblox runtime. Compose makes and
owns the native tree. Roblox supplies layout, text editing, scrolling, selection
and styling. This reference describes the `0.12.0` surface.

## Public entry points

| Export | Contract |
|---|---|
| `VERSION` | The package version string. |
| `Compose` | The pinned Compose core module, by reference. Use its cells, formulas, owners and structural operations directly. |
| `Roblox` | The pinned Compose Roblox module, by reference. `createRuntime(engine?)` makes the native runtime. `createHost(engine?)` makes its host. |
| `controls(runtime, options?)` | Returns the control constructor table for that native runtime. |
| `app(options?)` | Returns an app: a runtime, the controls for it, and a `mount` that adds the ScreenGui, the StyleSheet and the StyleLink. See [Mounting](#mounting). |
| `themes` | Theme package definitions, native StyleSheet compilation, icons and skins. |
| `COMPOSE_COMMIT` | The full Compose commit of the pinned copy. The Facet tests use this commit. |
| `civilDate` | Calendar arithmetic, words and fixed-offset instants for civil dates. See [Civil dates](#civil-dates). |
| `adaptive` | Pure size, height, orientation, axis and column decisions. See [Adaptive environment](#adaptive-environment). |
| `gamepadContention` | Probes and the one remedy for the legacy player scripts that hold ButtonA, the arrow keys and Tab. See [Facet.gamepadContention](#facetgamepadcontention). |
| `pathShapes` | Normalized arc, ring and needle points for `UI.Path`. See [Path shapes](#path-shapes). |
| `richText` | `escape` for player and server text inside rich text. See [Text](#text). |
| `inputPriority` | `{ belowControls, aboveFacet }`: `InputContext.Priority` values just below and just above every input context Facet creates. A game shortcut at `belowControls` loses to any selected Facet control; one at `aboveFacet` wins over all of them. |
| `recipes` | Opt-in helpers. `recipes.arithmetic.parse` is a bounded arithmetic parser for a number field. See [Recipes](#recipes). |
| `bind(Compose, Roblox)` | Returns a Facet table whose `controls` and `themes` use the Compose core module and the Compose Roblox module that you give. See [Your own Compose](#your-own-compose). |

### Types

The exported Luau types include `Facet`, `ComposeModule`, `ComposeRobloxModule`,
`Controls`, `ControlOptions`, `App`, `AppOptions`, `Component`, `ThemePackage`,
`CivilDate`, `CivilRange`, `CivilLocale`, `CivilDateModule`,
and the `Props` and `Spec` contracts of each control. The layout types include
`Space`, `Padding` and `Extent`. `Cell<T>`, `Readable<T>`,
`Runtime`, `Owner` and `Use` are the Compose types. Collection, menu and picker
contracts keep the item and value types through callbacks. Native properties use
the Roblox property types. For example, `Size` accepts a `UDim2` or a reactive
source of a `UDim2`.

The pinned Luau solver sometimes needs explicit types for these values:

- reactive `use` parameters,
- content factories that return `Instance` or `GuiObject`,
- native anchors.

Literal options can need singleton annotations, such as
`presentation = "number" :: "number"`. These annotations keep the contract
without `any`.

Native Instance properties also accept `Compose.static(instance)`. The pinned
Compose release types the payload of this marker as `unknown`. Thus Luau cannot
check the class of the wrapped Instance. Ordinary property values and reactive
sources keep their native types.

Run `python3 tools/check_types.py` to check the Facet runtime source and the
positive and compile-fail public API witnesses. The checker uses pinned Roblox
definitions and the default analyzer limits, so the full `Facet` type checks
the same way in a consumer's editor. It runs the old Luau type solver and then
the new type solver. The new solver pass must stay within the diagnostic budget
in `tools/typecheck/solver_v2_budget.json`. It reports vendor diagnostics separately. It does not accept a
`--!strict` directive alone as proof of a typed API.

### Mounting

`Facet.app(options?)` is the short path to a screen. It uses only the public
pieces below. It adds no service, solver, scene or render target.

```luau
local Facet = require(game.ReplicatedStorage.Facet)
local app = Facet.app()
local UI = app.UI

app.mount(function()
    return UI.Screen {
        UI.Button { label = "Continue", onActivate = function() print("Continue") end },
    }
end)
script.Destroying:Connect(app.dispose)
```

The app has these fields:

| Field | Contract |
|---|---|
| `runtime` | `options.runtime`, or a new runtime from `Facet.Roblox.createRuntime()`. |
| `UI` | `Facet.controls(runtime, options)`. |
| `mount(component, parent?)` | Mounts a ScreenGui into `parent`, `options.parent` or the PlayerGui of the local player. The ScreenGui holds a StyleSheet from `Facet.themes.createStyleSheet(runtime, options.theme)`, a StyleLink to that sheet, and the result of `component()`. In a PlayerGui it also mounts `UI.focusRing(playerGui)` (see [environment](#environment)). It returns the stop function and the ScreenGui. |
| `refusal(control, spec)` | Asks whether the control `UI[control]` takes `spec`. It returns the words of the error that the constructor raises, or nil when the constructor accepts the spec. It builds the control under a temporary Compose owner and releases it at once, so nothing mounts. A refusal that only a later update can raise, such as a readable that changes to a refused value, is not answered. An unknown control name is an error. Use it to offer only the combinations that a control accepts, for example in a catalog or an editor. |
| `presentToast(component, options?)` | Shows `component(app.UI)` as a `UI.Toast` in the app's shared toast ScreenGui and returns `{ id, dismiss() }`. See [Toast](#toast). |
| `presentAnchored(component, options)` | Shows `component(app.UI)` in a `UI.Popover` against `options.source` (`{ node }` or `{ rect }`), in its own ScreenGui from `mount`. `options` takes the Popover placement keys (`edge`, `align`, `gap`, `crossOffset`, `tail`, `maxWidth`, `maxHeight`), `modal`, `cancelPolicy` and `onDismiss`. The panel is always anchored, never a sheet. It returns `close, screen`. A dismissal (Cancel, an outside tap, a lost source node) or `close()` reports `onDismiss` once and stops the mount. Use it for a coach mark or a custom anchored panel that no control owns. |
| `dispose()` | Stops each mount of the app. Then it disposes the runtime if the app made it. A second call does nothing. |

`AppOptions` accepts every `controls` option (see [Factory options](#factory-options))
and these fields:

- `runtime`: a runtime that you own. The app does not dispose it. Give a
  runtime when you test without Roblox.
- `parent`: the default parent of each ScreenGui.
- `name`: the ScreenGui name. The default is `Facet`.
- `screen`: native ScreenGui properties, such as `DisplayOrder`,
  `ScreenInsets` or a reactive `Enabled`. They replace the defaults
  (`Name` from `name`, `ResetOnSpawn = false`, `ZIndexBehavior = Sibling`).
- `sheet`: `createStyleSheet` options, such as `theme` for the palette or
  `transition`. The app adds `types` and `motionLevel` when you do not set
  them.

The app gives `theme` to the controls and to the StyleSheet, so you set the
theme one time.
`component` runs in the owner of the mount. Cells that it makes belong to that
mount. `app.mount` after `app.dispose` stops with an error.

When you need a root that is not a ScreenGui, such as a SurfaceGui, or a
StyleSheet that other roots share, use the runtime directly. These functions are the pieces that
`app` uses:

- `runtime.mount`,
- `runtime.mountFragment`,
- `runtime.decorate`,
- `runtime:dispose`.

`decorate` applies only properties and events. To mount native children, use
`mount` or `mountFragment`. The stop function that a mount returns ends that
mount. Stop the mounts before you dispose the runtime.

```luau
local Facet = require(game.ReplicatedStorage.Facet)
local Compose = Facet.Compose
local runtime = Facet.Roblox.createRuntime()
local Host = runtime.constructors
local UI = Facet.controls(runtime)
local stop = runtime.mount(function()
    local sheet = Facet.themes.createStyleSheet(runtime)
    return Host.ScreenGui {
        Name = "Example",
        sheet,
        Host.StyleLink { StyleSheet = Compose.static(sheet) },
        UI.Button { label = "Continue", onActivate = function() print("Continue") end },
    }
end, game.Players.LocalPlayer.PlayerGui)
```

### Call style

Use a dot for fields that are plain functions: `Facet.app`, `app.mount`,
`app.dispose`, `runtime.mount`, `runtime.mountFragment`, `runtime.decorate`
`runtime.spring` and `runtime.tween`. Use a colon for the Compose runtime
methods: `runtime:dispose()`, `runtime:batch(body)`, `runtime:watch(body)`,
`runtime:settle()` and `runtime:pending()`. Compose declares these with `self`,
and the type check rejects the dot form. Cells use a colon:
`cell:set(value)`, `cell:update(fn)` and `cell:peek()`.

### Your own Compose

A game that already uses Compose must use one Compose instance for its state
and for Facet. Two instances make two reactive graphs. A value from one graph
does not reliably update a reader in the other graph.

`Facet.bind(Compose, Roblox)` returns a table with the same fields as `Facet`.
Its `Compose` and `Roblox` fields are the modules that you give. Its `controls`
and `themes` use only those modules. The default `Facet` table is
`bind` applied to the pinned copy.

```luau
local Compose = require(game.ReplicatedStorage.Packages.Compose.core)
local ComposeRoblox = require(game.ReplicatedStorage.Packages.Compose.roblox)
local Facet = require(game.ReplicatedStorage.Packages.Facet).bind(Compose, ComposeRoblox)
local runtime = ComposeRoblox.createRuntime()
local UI = Facet.controls(runtime)
```

Give both modules from the same Compose copy. Make the runtime with that
`Roblox` module.

`bind` rules:

- The Facet tests use the Compose commit in `COMPOSE_COMMIT`. Facet supports a
  later Compose commit when it keeps the functions that Facet uses and their
  behavior.
- `bind` stops with an error when the Compose module does not have a function
  that Facet uses. The error names the function and the tested commit. `bind`
  cannot find a change in behavior. Run your tests when you change Compose.
- A control stops with an error that names the control when no owner of its
  Compose instance is active. This occurs when you build a control outside
  `runtime.mount`, or when the runtime comes from a different Compose instance.
- A control stops with an error that names the control and the option when an
  option is a cell or formula from a different Compose instance. `read` of a
  value from a different Compose instance also stops with an error.

## Constructor contract

`UI.Button(spec)` and `UI.Button("Name")(spec)` are equivalent construction
forms. The second form sets the name. Every constructor returns a native
Instance. `ref = function(instance) ... end` receives that root. Make controls
inside a Compose owner. This is usually the component that you give to
`runtime.mount`.

### Options and native properties

Control-specific options use lower camel case. Native properties keep their
Roblox names: `Size`, `Position`, `AutomaticSize`, `LayoutOrder`, `Visible`,
`TextSize` and the others. The control forwards native events, Compose property
and event keys, `Attributes` and numeric children to the host. To add native
tags, use `node:AddTag(name)`. An unsupported control option causes an error.
It does not become inert metadata. The error names the control and, when an
option is close, suggests it:
`Facet UI.Button: unknown option 'lable'. Did you mean 'label'?`. A spec that is
not a table gives `Facet UI.Button: expected a property table, got number`.

### State

Readables and `function(use)` bodies bind reactive properties. The caller owns
the state. An input value control writes a writable cell when the related
callback is absent. If you supply `onChange` or `onToggle`, the callback is a
request. Update the model in the callback to accept it. Navigation controls
document their own write-then-notify behavior below.

### Factory options

`controls` accepts these options:

- `theme`: a theme package or a readable of one. The controls use it for
  metrics, artwork and icon resolution. At ten feet (`adaptive.isTenFoot`)
  they use `themes.forDistance(theme, "ten-foot")`, so every metric length,
  the 44 pixel hit floor (66) and the control heights are 1.5 times. A
  readable `environment` preview of the distance, the display size or the
  pointer makes the ladder follow a change at once. Without one, the controls
  take the distance when `Facet.controls` runs. `Screen` overscan follows the
  live fact.
- `motionLevel` and `icons`: these can also be reactive. `motionLevel` is
  `"normal"` (full motion), `"limited"` or `"none"` (see Motion). If you omit
  it, motion follows the device: `GuiService.ReducedMotionEnabled` gives
  `"limited"`, otherwise `"normal"`. The effective level is the stronger of
  yours and the device's (`"normal"` < `"limited"` < `"none"`): a game can add
  reduction but never remove a player's Reduce Motion. An unknown value given
  when the controls are made is an error, and so is the removed
  `reducedMotion` option; an unknown value that a readable delivers later
  (such as a stale saved setting) follows the device level with one warning.
- `pressHaptic`: a native `HapticEffect` or a feedback kind (`"selection"`,
  `"impact"`, `"success"`, `"warning"` or `"error"`). Only a control that
  changes a state or a value plays it. See [Haptics](#haptics).
- `controlSize`: the control-size step (`xsmall`, `compact`, `regular` or
  `large`) for theme icons.
- `onError`: receives a failure from the content of a presented Alert or
  Sheet, which then dismisses, and a failure from a Callout `onShow`. It also
  receives a failure that an `ErrorBoundary` without its own `onError`
  contains.
- `environment`: a preview of the device facts. Each field is a value or a
  readable. `nil` follows the engine. `preferredInput` (a `PreferredInput` or
  its name), `touchEnabled`, `mouseEnabled`, `gamepadEnabled` and
  `keyboardEnabled` replace the `UserInputService` facts that every control
  reads. `preferredTextSize` and `displaySize` (a `PreferredTextSize` or a
  `DisplaySize`, or its name) replace the `GuiService` facts. `viewportSize`
  replaces the camera viewport of `UI.environment()` without a source. Use it
  for a preview in a catalog or a gallery. The engine input still arrives:
  a mouse click still works in a touch preview. `viewingDistance`
  (`"automatic"`, `"near"` or `"ten-foot"`) is the authored viewing context:
  `"ten-foot"` makes a lounge PC with a mouse a television, and `"near"` keeps
  a console near. It outranks every inference. `overscanInsets`
  (`{ top, left, bottom, right }` in pixels, or `"none"`) replaces the default
  ten-foot margins. An unknown field or value causes an error.
- `keyboardNavigation`: `true` (the default) binds Tab traversal and Space
  next to Return on a selected Button. `false` binds neither: Return still
  activates. Use `false` for an app whose keys belong to the game (see
  [Selection](#selection) and [responder](#responder)).
- `services`, `guiService`, `userInputService` and `types`: native dependencies.
- `inputParent` and `overlayParent`: placement targets. A callout and a help
  plate place themselves inside `overlayParent` when you set it.

### Motion

The controls animate navigation and presentation by default. All motion uses
the Compose runtime. Motion does not block input or focus. An exiting element
cannot be interacted with, and the selection never stays on it. Every time,
easing, spring, scale and distance below is a token in the theme package's
`metrics.motion` (named in brackets). The values are Facet Neutral's.

| Control | Enter | Exit |
|---|---|---|
| NavigationStack push | The new page slides in from the trailing edge. The old page moves 30 percent (`distances.parallax`) to the leading edge and dims by 0.1 (`distances.dim`). Critically damped spring with a 0.3 second period (`springs.move`), visually complete in approximately 0.35 seconds. | Pop is the reverse. |
| TabView page change | Crossfade, 0.2 seconds (`durations.tabFade`), Quad Out (`easing.fade`). | The same. |
| Sheet | Slides up from the bottom, 0.3 seconds (`sheet.enter`), Cubic Out (`easing.present`). A side sheet slides in from its edge. The scrim fades in. A detent change, a released drag and a side sheet's released pull settle on one critically damped spring (`springs.sheet`, a 0.4 second period, visually complete in about 0.45 seconds) that starts from the finger's release velocity; a detent change retargeted mid-flight keeps its velocity. A release faster than 800 pixels per second (`fling.bounceSpeed`) settles on `springs.flick` (0.3 second period, damping 0.8), so it passes its detent by under 2 percent once and comes back. While you drag or pull a sheet that can be dismissed, the scrim lightens in proportion to how far the sheet has moved toward dismissal. | Slides down, or toward its edge, 0.2 seconds (`sheet.exit`). |
| Alert, Dialog | Scales from 0.94 (`materialize.modal`) to 1 and fades in, 0.2 seconds (`dialog.enter`), Cubic Out. The scrim fades in. | The reverse, 0.15 seconds (`dialog.exit`). |
| Popover | Scales from 0.9 (`materialize.anchored`) to 1 from the edge nearest to the anchor, and fades in, 0.15 seconds (`popover.enter`), Cubic Out. | The reverse, 0.1 seconds (`popover.exit`). |
| Callout | Scales from 0.9 to 1 about its tail point, and fades in, over the theme's `motion.fast` (0.12 seconds by default), Cubic Out (`easing.present`), from `materialize.anchored`. The panel, its text and its tail appear on the same first styled frame. | The reverse, over the same time. |
| Button `help` | Scales from 0.9 to 1 about its tail point, and fades in once, over the theme's `motion.normal` (0.2 seconds by default), Cubic Out (`easing.present`), from `materialize.anchored`. The panel, its text and its tail appear on the same first styled frame. | The reverse, over `motion.fast`. |
| Menu, Picker menu | The panel scales from 0.96 (`materialize.menu`) to 1 from the corner where it hangs; a pointer submenu grows from the chosen row (about that row's top edge, on the side facing the parent), and Back grows the parent from the side that faced the child; and fades in, 0.15 seconds (`popover.enter`), Cubic Out. As a sheet (touch, gamepad, narrow window), the panel slides up from the bottom edge and fades in with the Sheet timing (`sheet.enter` 0.3 seconds, `sheet.exit` 0.2 seconds) and never scales. A sheet level change slides the rows 32 pixels (`distances.menuSlide`) in from the trailing side (Back: from the leading side) and cross-fades them over `popover.enter`. | The reverse, 0.1 seconds (`popover.exit`); a sheet slides back down over `sheet.exit`. |
| Popover compact sheet | The Sheet motion. | The Sheet motion. |
| Toast | Slides in from its edge and fades in, 0.2 seconds (`toast.enter`), Cubic Out. `fade = false` only slides. | Slides out toward its edge and fades out, 0.2 seconds (`toast.exit`). |
| Toast with an action | Slides up from below the layer and fades in, 0.2 seconds (`toast.enter`), Cubic Out. | Slides down and fades out, 0.2 seconds (`toast.exit`). |
| DisclosureGroup | The content height opens from 0, 0.25 seconds (`reveal.enter`), Cubic Out, and the content fades in over the theme's `motion.revealFadeShare` of that time (half by default). The chevron turns 90 degrees with it. | The height closes in 0.2 seconds (`reveal.exit`), and the content fades out over the same share of that time. |
| CollapsibleView | The panel grows out of the trigger's rectangle to its open rectangle, 0.25 seconds (`reveal.enter`), Cubic Out (`easing.present`), and the content fades in over the theme's `motion.revealFadeShare` of that time (half by default). The chevron turns 180 degrees with it. | The panel shrinks back in 0.2 seconds (`reveal.exit`), and the content fades out over the same share of that time. |
| Notice | The height opens from 0, 0.25 seconds (`reveal.enter`), Cubic Out. | After a press on its close button, the height closes to 0 in 0.2 seconds (`reveal.exit`). Then `onDismiss` runs. |
| RadialMenu slot | A slot that enters an open ring fades in, 0.16 seconds (`radial.slot`). A slot of a submenu unfolds from the chosen item: it starts at that item's angle and ring band and sweeps along the ring to its own angle, its wedge growing from the theme's `motion.unfoldStart` of its arc (a quarter by default, Cubic Out). Other slots move from 30 percent (`materialize.branch`) of the distance toward the center to their positions. Back folds the level into its item and re-opens the parent around it: each parent slot starts at that item's angle and band and sweeps to its place. A ring that opens again starts from the centre. Reduced motion places the slot at once. | The slot fades out, 0.12 seconds (`radial.exit`). A submenu slot left by Back folds along the ring into the item it came from as it fades. |
| NavBar | No motion. | No motion. |

- A fade uses a CanvasGroup named `Fade` only while it runs. The group holds
  the faded node's children. When the fade ends, the children move back and
  the group is removed, so settled text and art are never rasterised. A
  `UIGradient` named `FadePaint` fades the node's own paint. A new group
  draws one frame almost transparent before the fade shows it, and the node's
  own paint waits for that frame, so the panel and its text appear together.
- A faded node also carries a `UIStroke` named `FadeStroke` (tag
  `facet-fade-stroke`) with its own `FadePaint` gradient. It is disabled at
  rest. Every theme stroke rule `S::UIStroke` has a twin
  `S > .facet-fade-stroke` with the same properties, so the stroke resolves
  exactly like the node's theme stroke. While a fade runs the node is tagged
  `facet-fading`: its `::UIStroke` is disabled and `FadeStroke` is enabled in
  the same style pass, so the outline fades with the fill and the content. A
  game rule on `S::UIStroke` gets the same twin. `FindFirstChildWhichIsA("UIStroke")`
  on a faded node returns `FadeStroke`.
- A presentation's fade leads its travel. An Alert, Dialog, Popover, Menu,
  Callout, Button `help` plate and Sheet (its scrim) is fully opaque once 60
  percent of its entrance time has run (`presentFadeIn`) and fully clear once
  half of its exit time has run (`presentFadeOut`); the scale, slide or rise
  runs its whole time. The scrim and a tail fade with the panel. A presentation
  reversed mid-entrance or mid-exit continues its fade from where it is.
- An Alert, a Dialog, a Popover, a Menu (and each Menu level), a Callout and
  a Button `help` plate measure themselves at rest before the entrance: each
  waits, invisible and at scale 1, until its size holds for one frame, at most
  the theme's `motion.restLimit` (0.25 seconds by default). The placement then
  reads that rested size for the whole entrance and exit, so the scale never
  moves the plate or its tail, and a Dialog, Callout or help plate holds that
  size as a fixed box while it scales. The wait applies at every motion level,
  so a presentation never grows after it shows.
- The motion level (`motionLevel`, or `GuiService.ReducedMotionEnabled` for
  `"limited"`) changes this motion:
  - `"normal"`: the motion above.
  - `"limited"`: no travel, scale or slide. An Alert, Dialog, Popover, Menu
    (pointer and sheet form), Callout, Button `help` plate and Sheet
    cross-fade in and out over `reducedFade` (0.15 seconds, `easing.fade`);
    a Sheet's panel fades with its scrim. A Toast fades in place over
    `reducedFade` (even with `fade = false`), a TabView page cross-fades
    over `reducedFade`, a NavigationStack push fades the new page in over
    `reducedFade` with no slide (a pop is immediate), and a DisclosureGroup
    or CollapsibleView lands its height at once and fades its content over
    `reducedFade`, and so does a Notice when it arrives and when its close
    button is pressed (`onDismiss` runs after the fade). A NavigationStack pop
    is a known gap: it is immediate. A custom `transition` keeps its own timing. Paint
    transitions keep their timing.
  - `"none"`: every presentation appears and leaves at once, and paint
    transitions are instant.
- A presentation that has not drawn a frame, or whose anchor is no longer
  available, leaves immediately.
- If you present a control again during its exit, the exit reverses.
- PageView keeps its native page swipe.
- Collapsing DisclosureGroup content cannot be interacted with. If the
  selection is in it, the selection moves to the header when the collapse
  starts.
- A Notice whose close button was pressed cannot be interacted with, and it
  clears a selection inside it. If the notice stays mounted after
  `onDismiss`, it opens again.

### Modal input

Dialog, Alert, Sheet, Popover, Menu and the other modal
surfaces put an Active full-screen root and an Active scrim button over the
layer. Thus a press, a tap or a drag under the modal does not reach the
content below.

Roblox can send a touch pan or the mouse wheel to a ScrollingFrame below the
scrim. Thus, while a modal is open, Facet sets `ScrollingEnabled = false` on
each ScrollingFrame in the same LayerCollector that is outside the top modal:

- Facet records the value of each frame before it changes the frame. When no
  modal holds the frame, Facet writes the recorded value back. A frame that
  was already `false` stays `false`.
- With stacked modals, only the ScrollingFrames of the top modal scroll. When
  the top modal closes, the modal below it scrolls again.
- A ScrollingFrame that is added to the layer while a modal is open is held
  in the same way. A held frame that leaves the layer gets its recorded value
  back at once.
- A modal gives the frames back when its exit starts, not when its exit ends.
- ScrollingFrames in a different LayerCollector do not change.
- Do not write `ScrollingEnabled` on a frame outside the modal while the modal
  is open. Facet writes the recorded value back when the modal closes.

### Haptics

`pressHaptic` plays only for a control that changes a state or a value:

- Toggle and a Chip with `selected`.
- A Picker option that is not selected. A multiple Picker option always plays.
- A Stepper step.
- A Slider with a `step`. The effect plays once for each detent, not for each
  frame.
- Rating and LevelPicker.
- An Alert action with the `destructive` role or the `defaultAction` shortcut.

A plain Button, a tab, a menu row, a keyboard key and a link do not play it.
Set `haptic = true` on a Button to play `pressHaptic` for a game-specific
action. `true` is the shorthand for `pressHaptic`. `haptic` also takes a
feedback kind, which plays that kind whether or not `pressHaptic` is set.
`haptic` can be a readable of either. An explicit `PressHapticEffect` always
wins.

The feedback kinds map to one engine `HapticEffect` each. The controls create
each effect once, when a control or `UI.feedback` first asks for it, and
parent it to the Workspace. The engine plays the press effect through
`GuiButton.PressHapticEffect`.

| Kind | Engine effect | Use it for |
|---|---|---|
| `selection` | `UIClick` preset | a choice that changes |
| `impact` | `GameplayCollision` preset | a heavy press, a hit or a landing |
| `success` | `UINotification` preset | a completed task |
| `warning` | `Custom`: two pulses of 0.7 | a choice with a cost |
| `error` | `Custom`: three pulses of 1 | a refused action |

`UI.feedback(kind)` plays a kind at once, for a result that does not come from
a press, such as a purchase that the server confirms. An unknown kind causes
an error that lists the kinds. Studio plays no motor; a phone or a gamepad on
a supported client feels it.

The `theme` option of `controls` does not install paint. Parent a
`createStyleSheet` result and its StyleLink in the native tree, with the same
theme package source. `Facet.app` does this for you.
Ordinary Roblox consumers use the ambient services and datatypes. The runtime
that you supply must use the Compose Roblox host.

### Instances you hand to a presenter

A Sheet (`content`, `header`, `hero.content`), DisclosureGroup, CollapsibleView,
Callout and NavigationStack destination accept an Instance as well as a
factory. The presenter parents that Instance while it is shown and detaches it
(`Parent = nil`) before the surface is destroyed, also on the final unmount, so
the same Instance can be shown again. The game owns it: destroy it, and
disconnect what you connected to it, when you no longer need it. A factory
builds a fresh Instance each time and needs nothing.

### Selection

The controls use `GuiService.SelectedObject` for keyboard and gamepad focus.
The engine moves the selection with the D-pad and the arrow keys. Facet adds
these rules:

- Entry. When nothing is selected, the first D-pad press selects the first
  control of the active screen in layout order. An open modal is the active
  screen. The press does not move a selection that already exists.
- Presentation. A modal presented while a control is selected, or while a
  gamepad is the preferred input, selects its first control. It waits until
  the surface is shown, so it never selects a hidden control.
- Leaving. A Facet presenter hands the selection back to its anchor or opener
  as it starts to leave. A game's own panel is not a presenter: when its
  buttons stop being selectable before it is gone, the engine moves the
  selection to another control on the page. Set `SelectedObject` yourself
  first, or present the panel through `UI.responder` or a modal.
- Tab and Shift+Tab. Tab selects the next control in layout order. In a
  collection that is row order (each row's `LayoutOrder` is its index), even
  after scrolling has recycled the row containers.
  Shift+Tab selects the previous control. The walk wraps at both ends. It
  stays inside an open modal. It skips hidden, disabled and removed controls,
  and scroll containers, except one that is itself a documented stop (an
  overflowing Dialog body, a Collection or Pagination root).
  The native `SelectionOrder` of a control is its traversal tier: a lower
  value comes first, and within a tier layout order wins (the `tabindex`
  model). The `FacetTraversal` input context is a child of `inputParent`, or
  of the local `PlayerGui` when you do not set `inputParent`. It is enabled
  only while `UserInputService.KeyboardEnabled` is true, so a phone binds
  nothing. The engine keeps Tab and Escape from input actions, so Facet also
  reads both keys from `UserInputService.InputBegan` and runs the one enabled
  Facet action with the highest priority for each press (Tab: traversal;
  Escape: the top modal's Back). A real Escape still opens the Roblox menu as
  well; the engine reserves it. Closing Facet's top modal on the same press is
  deliberate, and an Escape while the Roblox menu is already open closes
  nothing in Facet. Escape does nothing in Facet while a TextBox has the
  keyboard, and Tab leaves only a Facet text field (a game's own box or the
  chat keeps it). Tab with Ctrl, Alt or Meta held does nothing. With several
  `Facet.controls` sets on one `UserInputService`, one press runs one action
  across all of them: the highest priority, then the one whose control holds
  the selection, then the newest. The factory option `keyboardNavigation = false` disables it for a
  HUD over live gameplay, where Tab belongs to the game. A passive
  [responder](#responder) binds it only while it is engaged, and one with
  `traversalWrap = false` stops the walk at its ends.
- Grids and lanes. The engine walks a grid in two dimensions. Use the native
  properties for the rest: `SelectionGroup = true` on a container keeps the
  arrows inside it, and `SelectionBehaviorUp`, `Down`, `Left` and `Right`
  (`Stop` or `Escape`) choose per direction whether the arrows may leave it.
  `NextSelectionUp`, `Down`, `Left` and `Right` name an explicit neighbour.
  A `UI.Grid` whose last line is short sets `NextSelectionDown` (`Right` for
  `flow = "column"`) on the cells of the line before it that have no cell
  below, so the move lands on the last cell. A neighbour that you set wins.
  `UI.focusSection` chooses where the selection lands when it enters a
  region.
- Removal. When the selected control goes away, the selection moves to the
  nearest control that remains. A following control comes before a
  preceding control. A collection keeps the selection on its rows by key: it
  selects the next row, or the previous row when the removed row was the last.
- Scroll containers. A scroll container is not a stop. When the engine selects
  one, the selection moves to the child nearest to the entry edge. A TabView
  strip gives the selected tab. A container that has no controls passes the
  selection to the next control in the direction of travel.
- Value controls. While a Slider, Stepper, Rating, LevelPicker or
  `UI.adjustable` node has the selection, Left and Right (Up and Down for a
  vertical control; the D-pad, the arrow keys and the left stick) change the
  value. A held or repeating press stops at the minimum or maximum; a new press
  toward a limit the value is already at moves the selection to the next control
  that way, if there is one (the control's own `NextSelection*` link in that
  direction when it has one). L1, R1, Comma and Period also change the value
  and never move the selection. Only a navigation gamepad's stick adjusts
  (`UserInputService:GetNavigationGamepads`; restrict it with
  `SetNavigationGamepad`). The control claims the
  axis only while it is the selected object itself, never while a part inside
  it is. Its root has the tag `facet-adjustable`, the attribute `axis`
  (`horizontal` or `vertical`) and the attribute `disabled`. A disabled value
  control is not a selection stop; a busy one stays a stop and ignores presses.
  The root listens for `SelectionGained` (the engine's D-pad ranks listened
  objects first), and a Slider's drag detectors are off while the gamepad is
  the preferred input.
  A range Slider's Return does nothing while a TextBox has the keyboard. A table column grip and a reorder move also
  take Left and Right (Up and Down for a vertical list) while they have the
  selection, from the D-pad and the arrow keys only. A Menu row with a submenu
  opens it on Right, and Left returns to the parent row. The other axis still
  moves the selection.

A control that restores its own selection sets the `FacetSelectionOwner`
attribute on its root. The removal and scroll-container rules do not change
the selection inside that root.

## Layout

The layout constructors make ordinary native containers. A container is a
`Frame` or a `ScrollingFrame` with a `UIListLayout` or a `UIGridLayout`, and a
`UIPadding` when you set `padding`. Roblox does the layout. Facet adds no
solver and no measurement pass. Each constructor accepts the native properties
of its root, and a native property that you set replaces the default value.

Write the children as dense numeric children. The container sets the
`LayoutOrder` of each child to its position in the list. Nodes that a
`Compose.show` or `Compose.keyed` child adds sit at the position of that child,
in the directive's own order: a keyed child keeps its rows in list order. A
`LayoutOrder` that you set in a row orders it within that child. When the list
has such a child, the positions are spaced by 65536 (position 2 is 131072).

```luau
local sound = Compose.cell(true)
local function save() print("Saved") end
return UI.Screen "Settings" {
    gap = "s",
    UI.Text { text = "Settings", textRole = "title" },
    UI.ScrollView "Page" {
        gap = "s",
        UI.Toggle { label = "Sound", value = sound },
        UI.Button { label = "Save", onActivate = save },
    },
}
```

### Layout options

| Option | Values | Native result |
|---|---|---|
| `gap` | a spacing step or a number of pixels | `UIListLayout.Padding` |
| `padding` | a spacing step, a number, or `{ top?, right?, bottom?, left? }` | a `UIPadding` child |
| `width`, `height` | `"fill"`, `"hug"` or a number of pixels | `Size` and `AutomaticSize` |
| `align` | `start`, `center`, `end` or `stretch` | cross-axis alignment, `ItemLineAlignment` and the cross-axis flex |
| `distribute` | `start`, `center`, `end`, `spaceBetween`, `spaceAround` or `spaceEvenly` | main-axis alignment and `HorizontalFlex` or `VerticalFlex` |

- The spacing steps are `xs`, `s`, `m`, `l` and `xl`. They come from
  `metrics.space` of the theme package in the `theme` factory option. The
  neutral values are 4, 8, 16, 24 and 40 pixels. A package without a step uses
  the neutral value.
- When the theme package changes, the containers write the new pixel values.
  The native layout objects stay the same.
- An unknown step, alignment or size causes an error that names the valid
  values.
- `"fill"` sets the scale of that axis to 1. `"hug"` sets `AutomaticSize` on
  that axis. A number sets the pixel offset.
- `align = "stretch"` sets `ItemLineAlignment.Stretch` and sets the flex of
  the cross axis to `Fill`, so each child fills the cross axis of the
  container. `ItemLineAlignment.Stretch` alone fills only the line, and the
  line is as wide as the widest child.
- A container writes an alignment property only when you set `align` or
  `distribute`.
- All options accept a value, a readable or a `function(use)` body.

### Screen

`UI.Screen(spec) -> Frame` is the root of a screen. It fills its parent
(`width` and `height` are `"fill"`) and stacks its children vertically. It has
`padding = "m"` by default. The ScreenGui `ScreenInsets` property keeps the
screen inside the device safe area. The content never sits under the engine top
bar: when the screen reaches into the `GuiService.TopbarInset` band, the covered
height is added to the top padding. This holds with `IgnoreGuiInset` on or off.
The band covers the full width, as `CoreUISafeInsets` does. The background of
the screen still fills its parent. A Screen in a SurfaceGui takes no top bar
padding. At ten feet the Screen also adds the environment's `overscanInsets`
(see [environment](#environment)). Options: `gap`, `padding`, `align`,
`distribute`, `width`, `height` and `chrome`.

`chrome` is the platform-chrome policy. `"device"` (the default) clears the
device safe area, the top bar and the overscan. `"band"` lets the content ride
the free strip of the top bar beside the engine's buttons (a game's own top
row): no top bar padding, overscan kept. `"edge"` adds neither; pair it with
`ScreenInsets = Enum.ScreenInsets.None` on the ScreenGui for art that reaches
the glass. Your own persistent chrome is `padding`.

### VStack and HStack

`UI.VStack(spec) -> Frame` stacks its children vertically. `UI.HStack(spec) ->
Frame` stacks them horizontally. Both hug their content by default. Options:
`gap`, `padding`, `align`, `distribute`, `wrap`, `width` and `height`. `wrap`
sets `UIListLayout.Wraps`. The shared props type is `StackProps`.

### ZStack

`UI.ZStack(spec) -> Frame` puts its children on top of each other. It has no
layout object. A later child gets a higher `ZIndex`. A child that sets its own
`ZIndex` keeps it. `alignH` and `alignV` (`start`, `center` or `end`) set the
`AnchorPoint` and the scale `Position` of each child. On an axis that hugs
its content, the stack aligns each child by offset against the largest child on
that axis, so the stack keeps its size. Options: `padding`,
`alignH`, `alignV`, `width` and `height`.

### ScrollView

`UI.ScrollView(spec) -> ScrollingFrame` scrolls its children. It fills its
parent by default. It contains a `UIListLayout` and sets `AutomaticCanvasSize`
and `ScrollingDirection` for its axis. Thus the content fits the scroll window
beside the scroll bar. `axis` is `"y"` (the default), `"x"` or `"xy"`. The
`"x"` axis stacks the children horizontally and, unless you give a `height`,
hugs their height, so a row of chips never clips when they grow at ten feet.
When a child passed in the props has a Scale height (`height = "fill"`), the
ScrollView fills its parent's height instead, as before, because a hugging
frame would give that child no height.
Options: `axis`, `gap`, `padding`,
`align`, `distribute`, `width` and `height`.

### scrollTo and scrollToVisible

`UI.scrollTo(frame, position, options?) -> boolean` moves a native
`ScrollingFrame` to a position. `position` is `"top"`, `"bottom"`, a `Vector2`
or `{ x?, y? }`. An omitted axis keeps its value. The canvas limits clamp the
position: from 0 to `AbsoluteCanvasSize - AbsoluteWindowSize`. The result is
`false` when the frame does not move.

`UI.scrollToVisible(node, rect?, options?) -> boolean` brings a `GuiObject`
into view. It walks every `ScrollingFrame` ancestor from the inside out. Each
one moves the minimum distance that shows the node, or the `{ x, y, w, h }`
rectangle relative to the node. A node taller or wider than the window aligns
to its start. A frame moves only on the axes that its `ScrollingDirection`
permits. The result is `false` when no frame moves or the node has no scroll
ancestor.

Both calls tween `CanvasPosition` with `TweenService` for 0.25 seconds. A new
call cancels the tween that runs on the same frame. The move is instant when
`options.animated` is `false` or when the motion level is not `"normal"`. Call them from an event, for
example a button that goes back to the top of a page.

### Grid

`UI.Grid(spec) -> Frame` puts its children in a `UIGridLayout`. `columns` is
required. It must be a whole number, 1 or more. The grid divides its width into
that number of cells. Each cell gets its share of the gaps, rounded up to a
whole pixel, so a full row always fits the width. `gap` spaces the cells on both axes, and `rowGap`
replaces the vertical space. `cellHeight` is the cell height in pixels. The
default is the regular control height of the theme package. `aspectRatio` adds
a `UIAspectRatioConstraint` to the grid layout, which sets the cell height
from the cell width. `align` (`start`, `center` or `end`) aligns the cells
horizontally. The grid fills the width and hugs the height by default.
`flow = "column"` fills each column from top to bottom before the next column.
The grid keeps `columns` columns and sets the rows from the number of children,
so a new child moves the others to keep the columns even. The default is
`flow = "row"`.

### AdaptiveStack

`UI.AdaptiveStack(spec) -> Frame` is a stack that changes its axis. The
children stay mounted when it turns, so they keep their state, focus and
scroll position. Options: `axis`, `gap`, `padding`, `align`, `distribute`,
`width` and `height`. The props type is `AdaptiveStackProps`.

- `axis` is `"x"` or `"y"` and can be bound. The stack then turns when the
  value changes. Any other value causes an error.
- Without `axis`, the stack is a row while the row fits its width and a column
  when it does not. It fills the width and hugs the height by default.
- The row width is the `AbsoluteContentSize` of its `UIListLayout` while it is
  a row. As a column it adds the widths of the visible children and the gaps.
  A child with a `UIFlexItem` or a scale width, such as a `Divider`, counts
  as no width.
- When a column turns into a row that does not fit, it turns back and stays a
  column until its width or its children change. So the stack never flips on
  every frame.
- With `align = "stretch"` a column keeps the row width that it last measured,
  because stretched children fill the column. It measures the row again when a
  child is added or removed.
- The stack compares against its width inside its `padding`. Directly in a
  `ScrollView` that scrolls horizontally, the width is unbounded and the stack
  stays a row.
- `align` stays on the cross axis and `distribute` on the main axis when the
  stack turns. `Divider` and `Spacer` children turn with it.

```luau
UI.AdaptiveStack "Actions" { gap = "s", save, cancel, help }
```

### ViewThatFits

`UI.ViewThatFits(spec) -> Frame` shows the first child that fits and hides the
others. Each child is a candidate, in order of preference. The last candidate
shows when none fits. It needs at least one candidate. Options: `width` and
`height`. The props type is `ViewThatFitsProps`.

- A candidate fits when its `AbsoluteSize` is not larger than the size of the
  container. Roblox measures every candidate, also a hidden one. Facet only
  sets `Visible`.
- Give the candidates a `hug` or a pixel width. A candidate that fills the
  width always fits.
- The container fills the width and hugs the height by default. An axis that
  hugs is unbounded, so only the width is tested. With a bounded `height`, the
  height is tested too. Directly in a `ScrollView`, the scroll axis is
  unbounded and the first candidate shows.

```luau
UI.ViewThatFits "Actions" {
    UI.HStack { gap = "s", save, cancel, help },
    UI.VStack { gap = "xs", save, cancel, help },
}
```

### Composition and Region

`UI.Composition(spec) -> Frame` places ranked regions at the edges and
corners of the screen, as a game HUD does. `UI.Region(spec) -> Frame` is one
of those regions. Put the composition in a ScreenGui, or in any Frame that
covers the area to use. It fills its parent. The ScreenGui `ScreenInsets`
keeps it inside the device safe area. When the composition reaches into the
`GuiService.TopbarInset` band, it adds the covered height to its top padding,
as `Screen` does.

```luau
local hidden = Compose.cell(1)
return UI.Composition "Hud" {
	UI.Region "Score" { zone = "top", rank = 1, UI.Text { text = "12 : 9" } },
	UI.Region "Tasks" {
		zone = "left",
		rank = 3,
		mayDrop = true,
		form = hidden,
		UI.Text { text = "Win a round, land 25 hits" },
		UI.Button { label = "Tasks 1/2" },
	},
	UI.Region "Objective" { zone = "topbar", rank = 2, UI.Text { text = "Round 3" } },
}
```

Composition options:

- `gap`: the space between the regions of one zone, between the three lanes
  and between the zones of one lane. The default is `s`.
- `padding`: the space inside the edges. The default is `s`.
- `topbar`: a boolean or a readable. The default is `true`. See `topbar` below.
- The children are `UI.Region` nodes. A `UI.fill()` child is also allowed, so
  the composition can take the free height of a stack.

Region options:

- `zone` is required: `topLeft`, `top`, `topRight`, `left`, `center`,
  `right`, `bottomLeft`, `bottom`, `bottomRight` or `topbar`.
- `rank` is required: a whole number, 1 or more. Rank 1 is the most
  important region.
- `mayDrop`: when `true`, the region can hide completely after its last form.
- `form`: a writable cell. The composition writes the index of the form that
  shows, or 0 when the region is hidden. Read it to offer the hidden content in
  another place, such as a sheet.
- `reveal`: a boolean, default `true`. While the region shows a reduced form,
  a tap, click or `A` on that form opens the richest form in a Popover
  anchored at the region (`compact = "popover"`, so a phone keeps it in
  context too). The target is a transparent button under the forms, at least
  the hit floor in size, so a control inside a reduced form keeps its own
  press. A region with `mayDrop` steps to one more form before it hides: a
  small `Reveal` badge with a "…" icon in the same place, which opens the same
  Popover. The Popover hosts the region's own form 1 node, so its state and
  selection carry over, and puts it back when it closes or the region returns
  to its richest form. When not even the badge fits, the region hides and the
  zone shows one `ZoneReveal<Zone>` "…" button beside the zone, outside its
  list flow and at least the hit floor in size, while any of its regions is
  hidden. It opens one Popover that hosts each hidden region's own form 1
  node. `false` turns the affordance and the badges off, for a region whose
  reduced forms lose nothing. The badge is the last form, so
  `form` reads one past the authored forms while it shows.
- `expand`: an optional function that returns content for the Popover in
  place of the region's own form 1.
- The children are the forms of the region, richest first. At least one form
  is necessary. Give each form a pixel or `hug` size. A form that fills its
  parent has no size of its own.

Layout:

- A zone is a native Frame with an `AnchorPoint` and a scale `Position` at
  its edge or corner. It hugs its regions and stacks them
  in declaration order with a `UIListLayout`.
- The screen has three lanes of equal width: left, center and right. Each lane
  reserves its third. An empty lane does not give its width to the others, so
  a zone stays at its edge.
- A zone must fit the width of its lane. The zones of one lane must not
  overlap vertically. The `center` zone stays centred and keeps `gap` from the
  zones above and below it.

Step-down:

- Every form stays mounted in its own `Form<n>` Frame. Roblox measures each
  form, also a hidden one. Only the Frame of the chosen form is visible, so a
  form keeps its own `Visible`. The region has the `FacetForm` attribute.
- When a lane does not fit, the region with the highest rank in the zones
  that do not fit shows its next form. After its last form, a region with
  `mayDrop` hides. With equal ranks, the later region gives way first.
- When a zone is too wide, only its regions that are wider than the lane give
  way. A narrow region cannot make the zone narrower.
- The composition repeats this until every lane fits or no region can give
  way. It never scales content down.
- The decision uses only the measured sizes and the size of the composition.
  Thus a rotation, a resize or a text size change gives the same forms as a
  new mount of the same size.
- When the size of the composition changes, for example on a rotation, a
  region that changes form scales from 0.94 to 1 in 0.15 seconds, Cubic
  Out, from the edge of its zone. The first layout after a mount does not
  move. Its measurement holds until the motion ends,
  so the motion cannot change the decision. Reduced motion removes the motion.

`topbar`:

- A region with `zone = "topbar"` goes into the free strip of the Roblox top
  bar, level with the Roblox buttons. The composition puts these regions in a
  second ScreenGui with `ScreenInsets = TopbarSafeInsets`, in the parent of its
  own ScreenGui. That ScreenGui has the same `DisplayOrder`, follows the
  `Enabled` of the host and links the same StyleSheet. The regions stack
  horizontally centred in the strip, and they step down when the strip is too
  small.
- When `topbar` is `false`, when `GuiService.TopbarInset` has no width, or
  when the composition is not in a ScreenGui, these regions come first in the
  `top` zone.

### fill

`UI.fill(weight?) -> UIFlexItem` makes a child grow along the main axis of its
stack. Put the result in the children of the control:
`UI.Text { text = "Name", UI.fill() }`. Without a weight, the item uses
`UIFlexMode.Fill`. With a weight, it uses `UIFlexMode.Custom` with that
`GrowRatio` and `ShrinkRatio`. The weight must be a positive number. For the
cross axis, use `align = "stretch"` on the stack or `width = "fill"` on a
container.

### Divider

`UI.Divider(spec) -> Frame` is a hairline that separates the items of a stack.
It gets its direction from the stack that holds it. In a `VStack` it is a
horizontal line that fills the width. In an `HStack` it is a vertical line that
fills the height. When the stack changes its `FillDirection`, the line turns
with it. `axis = "y"` makes a horizontal line and `axis = "x"` makes a vertical
line, whatever the parent is. A native `Size` replaces the computed size.

- `thickness` is a number of pixels or a theme metric name, such as
  `"strokes.hairline"` or a spacing step. The default is the `strokes.hairline`
  metric of the theme package.
- `appearance` is `"standard"` (the default) or `"strong"`, and can be bound.
  The line has the `facet-divider` tag. The theme paints it in the hairline
  colour at `extra.hairlineOpacity`. `"strong"` adds the `facet-divider-strong`
  tag, which paints at `extra.strongHairlineOpacity` for a pane edge.

### Spacer

`UI.Spacer(spec) -> Frame` takes the free space along the main axis of its
stack. It is a transparent Frame with a `UIFlexItem` in `Fill` mode.
`minLength` is a number of pixels or a spacing step, such as `"m"`, and can be
bound. It is the length that the spacer keeps when there is no free space. The
default is 0. The spacer gets its axis from the stack that holds it. A native
`Size` replaces the computed size. Use `UI.fill()` to make an existing child
grow instead.

### ErrorBoundary

`UI.ErrorBoundary(spec) -> Frame` contains a failure in the region that it
builds. `view()` builds the region. `fallback(failure, retry)` builds the
content that replaces the region after a failure. Both are required.

- A failure in `view` when the boundary mounts, or in a later Compose update
  inside the region, disposes the region and shows the fallback. Siblings
  outside the boundary stay. The code that wrote the cell that caused the
  failure does not see an error.
- The boundary reports each failure once. `onError(failure)` receives it. If you
  do not set `onError`, the factory `onError` option receives it. The
  `FacetError` attribute of the frame holds the failure text.
- Call `retry()` to build the view again. A successful retry clears
  `FacetError`.
- A failure in the fallback is not contained.
- `width` and `height` take `fill`, `hug` or pixels. The default is `hug` on
  both axes.

The boundary uses `Compose.boundary`. A failure outside every boundary stays a
hard error.

## Actions and input

### Button

`label`, `onActivate`, `enabled`, `disabled` and `busy` define the action. A
disabled or busy button cannot activate. With `repeatDelay` or
`repeatInterval` (the defaults are `0.4` and `0.1` seconds), a held button
activates again after `repeatDelay` and then every `repeatInterval`, for a
mouse, a touch, Return, Space or ButtonA. The repeat follows the frame clock
only while the button is held, and it stops on release, when the pointer
leaves, and when the button is disabled or hidden. The Stepper buttons and the
NumberInput `stepButtons` repeat in this way. `shortcut` supplies
a key code and optional modifiers. `dialogAction` is `default` or `cancel`.

A Button keeps the height of its `controlSize` when its `Size` has no height
and its `AutomaticSize` grows on the Y axis. For example,
`Size = UDim2.new(1, 0, 0, 0)` gives a full-width button of the control height.

Presentation options:

- `appearance`, `role`, `selected`, `name`, `hint` and `pop`. `appearance` is
  `standard`, `emphasis`, `soft`, `utility`, `link` or `inverse`. `inverse` is a
  light plate on a dark theme, and a dark plate on a light theme. It uses the
  `inverseSurface` and `onInverse` colors of the palette. Without them it uses
  `contentStrong` with `surface` text. The button has the
  `facet-appearance-inverse` tag. A `utility` or `link` Button has no plate:
  a theme's `control` chrome art paints only the other appearances. A Button
  whose `BackgroundTransparency` is 1 has no plate art either, so a
  transparent hit target never covers the content beneath it.
  A destructive or `emphasis` Button keeps its role on skinned art. When the
  label (`onDanger` or `onAccent`) is lighter than the fill (`danger` or
  `accent`), the art is tinted with the fill. When `onAccent` is darker than
  `accent` in any palette and the `control` slot has `selected` art, every
  `emphasis` plate of that package shows the selected art with an
  `onSelected` label instead (Pixel Quest, Fantasy Ornate, Fantasy Parchment).
  Only a package without selected art falls back to the flat fill, so the
  label always meets its palette contrast. Skin images have the
  `facet-skin-art` tag.
- `controlSize`: `xsmall`, `compact`, `regular` or `large`. `xsmall` is one
  step below `compact` unless the theme package declares
  `metrics.controlSizes.xsmall`. With the neutral values it is 28 pixels high,
  with a `paddingX` of 4 and an `iconSize` of 12. The native button is its hit
  area. When the device has touch or a gamepad, a `TargetFloor`
  `UISizeConstraint` keeps a button with a smaller step at least
  `targetSizes.minimum` (44 pixels in the neutral package) on both axes, so a
  player can still tap it. On a mouse-only device an `xsmall` button stays a
  28 pixel target. Use `xsmall` for dense pointer rows. A named step adds the `facet-size-<step>` tag. The theme
  StyleSheet then sets the left and right padding to
  `controlSizes.<step>.paddingX`. Without `controlSize`, the button has no
  size tag and keeps the padding of 12. On skinned `control` art, the art's
  carve (`chrome.control.contentInsets`) is added to that padding on each
  side, so the label and a Menu or Picker disclosure icon sit inside the
  frame. A framed TextInput adds the `field` carve the same way.
- `textSize`: a type role (`caption`, `label`, `body`, `heading`, `title`,
  `control`, `strong` or `numeral`) or a number of pixels, or a readable of
  one. A role adds the `facet-type-<role>` tag to the label, and a number sets
  `TextSize`. It reaches the label of a plain text button and the `Title` label
  next to an icon.
- `underline`: `always` or `hover`, for a plain text button only. The label
  uses RichText and shows underlined always, or while the pointer is on the
  button, while it is pressed and while it has the gamepad or keyboard
  selection. It is the usual cue on a `link` button. The label text is escaped
  for RichText. An icon, image, row, circle or `compactLabel` button refuses
  `underline`.
- `corners`: `pill` or `square`, or a readable of one.
- `shape`: `rect` or `circle`. A circle with an authored `Size` on one axis
  only keeps that axis and matches the other axis to it.
- `icon` and `trailingIcon`.
- `image`, `imageAspectRatio` (default `16/9`) and `imageFraming` (`fit` or
  `crop`). An image button is 240 pixels wide by default. Its height hugs the
  image and the text. The image fills the width at `imageAspectRatio`, sits
  flush with the top edge and follows the top corners of the plate. The text
  keeps the button side insets and a bottom inset. With an authored fixed
  height, the image fits the space the text leaves at `imageAspectRatio` and
  is centered in it (a native `UIAspectRatioConstraint`, `FitWithinMaxSize`).
- `subtitle` and `row = { title, description, value, icon }`. A row button
  fills its width. It shows `icon` on the leading edge, the title and the
  description, and `value` as secondary text on the trailing edge. When the
  button has `onActivate` and no `trailingIcon`, it also shows a disclosure
  chevron. `value` and `icon` are static strings. `hint` shows as a second
  line of text below the label. See [Settings rows](#settings-rows).
- `haptic`: a boolean or a readable. When it is true, the button plays the
  `pressHaptic` of the controls. The default is false. See [Haptics](#haptics).
- `help`: one sentence that describes the action. It shows in a small panel
  when a pointer rests on the button for 0.45 seconds, when a keyboard or a
  gamepad selection rests on the button for 0.45 seconds, or at once when a
  touch player long-presses the button. The release of that long-press does
  not activate the button, and the next touch anywhere closes the panel. So
  every input can open every help. `help` can also be a table
  `{ title?, body, shortcut?, edge?, align? }`. `title` shows above the body.
  `body` can be empty only when `title` has the words. `shortcut` is a list of
  key chords such as `{ { "Ctrl", "K" }, { "F1" } }`. It is display text only
  and binds no key. `edge` (`top`, `bottom`, `leading` or `trailing`) and
  `align` (`start`, `center` or `end`) place the panel against the button. The
  panel uses the anchored placement of `UI.Popover`. The body fits its text
  up to 264 pixels wide and then wraps. A malformed table stops
  with an error that names `help`.
- `disclose`: `true` lets a player read the whole label of a text Button
  that truncates. With an authored width the label keeps one line and
  truncates at the end instead of wrapping. The label shows in the help panel (named `Disclosure`) on the
  same routes as `help`, only while the engine reports that the text does not
  fit (`TextFits`). While it shows, `help` waits: the full value comes first.
- `compactLabel`: an alternative string or readable. The button uses it when a
  plain text button cannot fit its full label. It does not apply to icon, image
  or subtitle buttons.

The pointer callbacks are `onPointerDown`, `onPointerUp` and `onPointerCancel`.
Each callback works alone. `onPointerCancel` runs when a held pointer leaves
the button.

A text Button with a bounded width truncates its label at the end when the
label does not fit its box. A Button whose width follows its label does not
truncate. A text Button or Toggle with an authored `Size` that has a width, and no
authored `AutomaticSize`, wraps its label inside that width and grows in
height. With an authored `TextTruncate` other than `None`, it keeps one line
and truncates instead. An icon Button with an authored width (and no image,
row, subtitle or hint) keeps that width, and its label truncates at the end.
An authored width never leaves less than one `control` em for the label inside
the padding and the theme carve: the Button grows to that minimum.
Without an authored width, it hugs its label.

### Toggle

`value` is a boolean source. `onChange(next)` requests a new value. Without it,
the control updates the writable cell. `presentation` is `switch`, `checkbox` or
`button`. The checkbox presentation supports `mixed`. A read-only `value` or
`mixed` source requires `onChange`. `indicatorPosition` is
`leading` or `trailing`. A checkbox with `controlSize` sizes its box to the
icon size of the rung plus the `xs` space. Without `controlSize` the box is 24
pixels. The label, row, hint, enabled and common button styling
options apply.

`controlSize` also sizes the switch. The track is the rung `iconSize` plus 4
pixels high, its width scales 38 by 24 to that height, and the knob is 6 pixels
smaller than the track. Without `controlSize`, the switch is 38 by 24 pixels.

A switch Toggle's knob glides between its ends on a critically damped spring
(`motion.springs.control`, a 0.25 second period) while the track colour
fades, and a change mid-flight turns it without a jump. Below motion level
`"normal"` the knob lands at once.

A switch or checkbox Toggle paints no plate and takes no `control` art from a
theme package. A settings row (a Toggle with `row`, `hint` or `icon`) has the
`facet-toggle-settings` tag. Its horizontal padding is the padding of a
Button, so its content lines up with Button rows in each theme. The row shows
`icon` or `row.icon` first. A Toggle with `row` puts its switch last unless
`indicatorPosition` is `leading`, so its label starts where the label of a
Button row starts.

The checked mark of a switch and a checkbox uses the `selection` color of the
palette, and its knob or tick uses `onSelection`. Without them, it uses
`accent` and `onAccent`. An off switch's knob also uses `onSelection`
when it has at least 3:1 contrast on the `control` track. Otherwise the
knob uses `content`, so the off switch stays visible.

`appearance = "plain"` makes a switch or checkbox a bare row. The row does not
get the `facet-selected` tag, so only the mark shows the state. The row has the
`facet-toggle-plain` tag and no settings padding. Use it for a checkbox in a
toolbar. The `button` presentation refuses `plain`, because its plate shows the
state. `textSize` is a type role or a number of pixels for the label, as on
Button. The default is the `control` role.

`disclose = true` lets a player read the whole label of a Toggle whose label
truncates, as on Button: the label shows in the `Disclosure` panel while the
engine reports that the painted label does not fit (`TextFits` of the label
itself on a settings row). Without `disclose` the Toggle shows no panel.

### TextInput

`value` is the string model. Roblox TextBox owns editing, IME, the caret, the
text selection and focus. `onChange(text)` handles user edits. An external
model update does not send it. `onCommit(value, reason)` receives `submit` or
`focusLost`. The number presentation also reports `clamped`. `onCancel`
observes cancellation and the restoration of the initial value of the edit.

`presentation` is `plain`, `search` or `number`. The number presentation also
uses a writable `numericValue`, `min`, `max`, `parse` and `format`, and the
number options of [NumberInput](#numberinput). If a callback disables the input
during a commit, the commit stops. `numericValue` does not change and
`onCommit` does not run. `validate(proposed)` returns the accepted text, or
`nil` to reject it. `maxLength` counts UTF-8 characters.

The other options are `placeholder`, `multiline`, `invalid`, `enabled`,
`disabled`, `clearButton` and `clearButtonMode` (`never`, `always`,
`whileEditing` or `unlessEditing`). Native TextBox properties stay available.
The placeholder uses the `contentSecondary` colour of the theme. A
TextInput without field chrome (no `label`, `hint` or other chrome option) is
the TextBox itself, so it keeps the flat `facet-field` plate in a skinned
theme. A framed TextInput shows the `field` art on its `Input` plate.
The clear button is a 44 by 44 `utility` Button named `Clear`. It shows the
`close` icon and no text. Its accessible name is "Clear".

- `readOnly`: a boolean or a readable boolean. A read-only field stays
  selectable, keeps full contrast and can take focus. `TextEditable` is false,
  the control refuses each edit, the clear button does not show and focus loss
  commits nothing. A live change keeps the same TextBox and the edit.
- `selectOnFocus`: `none` (the default), `all` or `end`, or a readable of one.
  The control applies it once for each focus session. A pointer focus applies
  it at the release of that pointer. Other focus applies it at once. A change
  during focus applies at the next focus. A live value that is not one of the
  three words causes an error, and the control keeps the last correct word. The
  TextBox has the `selectOnFocus` attribute only when you supply the option.
- `visibleLines`: a whole number of at least 1, for a multiline field only. The
  field shows that number of body lines in a native ScrollingFrame named
  `Viewport`. Longer text scrolls in the viewport, and the viewport keeps its
  size. The viewport is selectable, so a D-pad move reaches the field while the
  viewport is still off the screen, and the selection passes to the field. Without `visibleLines`, a multiline field grows to hold all its lines,
  including a final empty line.

#### Field chrome

A field can have these field chrome options: `label`, `requiredMark`, `hint`,
`errorText`, `leading`, `trailing`, `controlSize`, `appearance` and `corners`.
A field without chrome options, number units, step buttons or `visibleLines`
keeps the native TextBox as its root. Other fields return a Frame. The root
Frame holds these children in order:

1. `Label`: a TextButton that is not selectable. Its `Title` text is the label.
   Activation focuses the TextBox. The label is 44 pixels tall or more, and
   its words sit at the bottom. It follows `enabled`.
2. `Input`: the plate. It holds `SearchIcon` or `Leading`, `Prefix`, the
   TextBox named `Field`, `Suffix`, `Clear`, `Decrement`, `Increment` and
   `Trailing`, in that order. A named `controlSize` puts the plate in an
   `Input+target` Frame that is 44 pixels tall or more.
3. `Message`: one line. It shows `errorText` when it is not empty, then the
   number rejection text, then `hint`. An error shows the `status.error` mark
   (`MessageMark`), adds the `facet-validation` tag to the text and the
   `facet-invalid` tag to the plate. The plate does not move or shake.

`requiredMark` is `required` or `optional`. It is notation only. It does not
validate. `required` adds ` *` to the label text, also for a readable label.
`optional` adds no word. Put localized "optional" text in `hint`.

`leading` and `trailing` are native Instances. `leading` is decoration and is
not a focus stop. A search field refuses `leading`, because its search mark
leads. The focusable parts of `trailing` come after the TextBox and the clear
button.

`appearance` is `standard` (the `facet-field` plate), `contrast` (the
`facet-control` plate) or `utility` (no plate). A readable word changes the tag
in place. A word that is not one of these causes an error, and the plate keeps
the last correct paint. `corners` is `pill` or `square`. It adds a native
UICorner named `Corners`. `controlSize` is `xsmall`, `compact`, `regular` or
`large`.

A word that the chrome does not know causes an error that names the option.

### NumberInput

`UI.NumberInput(spec)` is `UI.TextInput` with `presentation = "number"`. It
refuses `presentation`. `value` (the editable string) and `numericValue` (the
committed number) are cells that you own. Each TextInput option applies. These
options are for the number presentation only:

- `step`: a finite number above zero. The default is 1.
- `precision`: a whole number of decimal places from 0 to 10. A commit and a
  step press round half away from zero. Typing does not round.
- `stepButtons`: two 44 by 44 buttons, `Decrement` and `Increment`, after the
  clear button. They are ordinary focus stops and do not take the arrow keys.
  The control disables a button at the bound that it faces, and disables both
  buttons when the field is read-only or disabled. A press commits with `submit`. With `min` and
  `max`, a press follows the step grid from `min`.
- `prefix` and `suffix`: a string or a readable string beside the TextBox.
  They are not part of the draft.
- `scrub`: a boolean or a readable boolean. A horizontal drag across the
  TextBox changes the number. See below.

Without `precision`, a step press or a scrub rounds to the decimal places of
`step` and `min`. Thus three presses of 0.1 give 0.3.

A commit parses the draft. The default parser accepts an optional sign, digits
and one decimal point only. It refuses an exponent, grouping, hex and blanks.
`Facet.recipes.arithmetic.parse` adds arithmetic. A number outside `min` or
`max` becomes the bound, and `onCommit(number, "clamped")` reports it. A draft
that is empty, a sign alone or a point alone is incomplete. At commit, the
field restores the text of the last committed number and shows no message,
unless `requiredMark` is `required`. A draft that is not a number keeps its
text and shows "Enter a valid number.". `onCommit` receives the number.

`scrub` starts after 6 pixels of mouse travel or 14 pixels of touch travel. A
tap below that distance stays a native tap. A drag that is mostly vertical
stays native. A horizontal drag ends the edit without a commit and restores
the text of the edit start. Then each 8 pixels of total travel is one `step`,
with the rounding and bounds of the step buttons. `onChange` reports each new
text. The release commits once with `submit`. Escape or ButtonB, a change of
PreferredInput, disabling, `readOnly`, `scrub` turning off and disposal cancel
the drag: the number and the text return to the values at the drag start, and
nothing commits. A write of your own to `numericValue` during a drag ends the
drag, and your number stays.

```luau
local draft, laps = Compose.cell("3"), Compose.cell(3)
UI.NumberInput "Laps" {
    value = draft,
    numericValue = laps,
    min = 1,
    max = 99,
    stepButtons = true,
    label = "Laps",
}
```

### ColorPicker

`UI.ColorPicker(spec)` returns a Frame. The player uses it to choose any
colour, for example the paint of a kart. For a few named colours, use
`UI.Picker`. A fixed palette also fits `modes = { "swatches" }`.

```luau
local paint = Compose.cell(Color3.fromRGB(230, 57, 70))
UI.ColorPicker "KartPaint" {
    label = "Kart paint",
    value = paint,
    onChange = function(color)
        paint:set(color)
    end,
    onCommit = function(color)
        print("save", color)
    end,
}
```

- `value`: a Color3, or a readable of one. It is `nil` only with
  `allowEmpty = true`. Then the plate has a cross and the text is
  `placeholder`.
- `onChange(color)`: receives each proposal. It is necessary unless `value` is
  a writable cell or `readOnly` is true. With `allowEmpty`, a discarded draft
  that opened empty proposes `nil`.
- `onCommit(color)`: runs once at the end of each gesture.
- `alpha` and `onAlphaChange(alpha)`: an opacity from 0 to 1. They add the
  `Opacity` slider, and the text becomes `#RRGGBBAA`.
- `modes`: the techniques in tab order. Each is `swatches`, `spectrum`,
  `sliders` or `brick`. The default is all four. Without `BrickColor` in the
  controls' `types`, the default is the first three. Set it at construction.
  With `brick`, a colour that is a BrickColor is named by that brick, for
  example "Kart paint, Really red".
- `swatches`: a list of Color3 values or `{ color, label? }` items, or a
  readable of one. The label or the hex text is the key of an item. Without
  it, the control shows a generated grid of 48 colours.
- `onSaveSwatch(color)` and `onRemoveSwatch({ color, label?, key })`: saved
  colours. See below.
- `style`: `automatic` (the default) or `inline`. Set it at construction.
  `automatic` is a well that opens a panel. `inline` shows the panel in place.
- `draft`: adds Cancel and Apply.
- `isPresented`, `onPresentedChange(next)` and `onDismiss(reason)`: the open
  state of the panel. The reason is `activate`, `outside`, `cancel`,
  `anchorLost` or `apply`. Without `isPresented`, the control keeps its own
  open state.
- `enabled` and `readOnly`: booleans or readables. A disabled well keeps its
  colour and does not open.
- The field chrome keys: `label`, `requiredMark`, `hint`, `errorText`,
  `controlSize`, `appearance` and `corners`. See
  [Field chrome](#field-chrome).

A value that is not legal at construction causes an error. A value that
becomes illegal later is not painted. The control keeps the last legal colour
and adds a line to the `diagnostics` attribute.

#### Proposals and commits

The colour belongs to you. Each change sends a proposal to `onChange`. The
control shows only the colour that you then hold. If you refuse a change,
nothing paints.

A gesture is a drag of the plane, a slider drag or step, a stick session, a
swatch press or a field commit. Without `draft`, each gesture commits once. B,
Escape, a tap outside and Done close the panel and keep the colour.

With `draft = true`, only Apply commits. Each other way out proposes the
colour that the panel opened with. Cancel does this too. If you write the
value while the panel is open, your value becomes the value that Cancel
restores. Apply has the `facet-accent` tag.

#### The well and the panel

A well with a `label` is a form row. The `Well` button holds `Title`, the
`Swatch`, the `Value` text and `Chevron`. A well without a label is the
swatch alone, 44 by 44 pixels. The `label` attribute of the well names the
colour, for example "Kart paint, #E63946".

The panel opens below the well. If there is not sufficient room below, it
opens above. If neither side has room, it opens beside the well. Otherwise it
takes the larger side, and its `Body` ScrollingFrame scrolls. The panel never
covers the well. On a touch screen narrower than 600 pixels, the panel is a
sheet at the bottom of the screen with a Done button. On a ten-foot screen,
the panel is a sheet at the center of the screen. The `placement` attribute is
`bottom`, `top`, `right`, `left`, `sheet` or `center`. A skinned theme's panel `contentInsets` pad the panel,
and the panel grows by them, so the grid keeps 8 columns inside the art.

The panel holds these parts in order:

1. `Modes`: a `UI.Picker` of the techniques. It is present only with two or
   more modes.
2. `Body`: the `Technique` frame. Each technique stays mounted. The inactive
   techniques are not visible. The frame is as tall as the tallest technique,
   so the panel keeps one height when the tab changes. In a scrolling body,
   an inactive technique reserves at most the height of the body, so a short
   technique has nothing below it to scroll to. The swatch and brick
   grids are centred in the panel.
3. `Opacity`: present only with `alpha`.
4. `Readout`: the `Preview` swatch, the `Format` picker (RGB, HSV and Hex) and
   the fields. The preview is two cells wide and one cell tall, and the format
   picker fills the rest of the row. The fields share the `Fields` row in equal
   columns with a native `HorizontalFlex`, each with its label above it. The
   `Hex` field takes the whole row. On a touch screen, the readout comes before
   the body, so the finger does not cover it.
5. `Actions`: Cancel and Apply, or Done on a sheet.

#### Techniques

- `swatches`: the `Swatches` grid of 44 by 44 cells, at most 8 in a row. A
  press on a cell proposes its colour. The chosen cell shows `Check`. Each
  cell has the `facet-color-cell` tag and no padding, so its swatch is square.
  A swatch has the `facet-color-swatch` tag and the theme's `radii.control`
  corner. The `Save` cell and the `BrickGrid` cells are the same.
- `spectrum`: the `Plane`, the `StickHint` and the `Hue` slider. The plane is
  two native layers. `Hue` has a white-to-hue UIGradient across. `Value` has
  a black UIGradient that fades in downward. A UIDragDetector on `Surface`
  sets saturation and brightness 1:1. The hue track is a rainbow UIGradient.
- `sliders`: the `Hue`, `Saturation` and `Brightness` sliders. Their labels
  share the width of the widest label, so the three tracks start at one x.
- `brick`: the 128 engine BrickColors in the `BrickGrid`, and the name of the
  chosen brick in `NameField` above the grid.

The thumbs are rings with a white band between two dark lines. The opacity
track shows the colour over a checker. If the preferred input changes during
a drag of the plane, the colour returns to the start of the drag.

On a touch screen, a bubble of the colour shows above the finger during a
drag of the plane or a strip. On a gamepad, the right stick moves the plane
while `Surface` has the selection. The stick input action sinks the stick, so
a camera does not turn. The D-pad still moves the selection. `StickHint`
shows while the plane has the selection.

The fields commit typed values. `Hex` accepts `#RGB` and `#RRGGBB`. With
`alpha`, it also accepts `#RRGGBBAA`. A hex text that is not legal stays in
the field with its error, and nothing commits. A change of the readout format
never changes the colour. A grey keeps the hue that the player set.

There is no eyedropper, because Roblox cannot read a screen pixel. Put your
own Button beside the well, and call `onChange` with the colour that it
sampled.

#### Saved colours

The control keeps no colours of its own. `swatches` stays yours.

- With `onSaveSwatch`, the grid ends with a `Save` cell named "Save colour".
  It proposes the current colour. It is disabled when the list has the colour.
- With `onRemoveSwatch`, an `Edit` button toggles editing. While editing, a
  cell shows `Remove`. A press on a cell proposes its removal. Delete,
  Backspace or ButtonX on the selected cell does the same. Then the selection
  moves to the cell that takes its place.

The root Frame has these attributes: `value`, `text`, `hue`, `saturation`,
`brightness`, `mode`, `format`, `presented`, `placement`, `hexError`,
`columns`, `editing` and `diagnostics`. `ref` receives the root Frame.

### DateTimePicker

`UI.DateTimePicker(spec)` returns a Frame. The player uses it to choose a
calendar date, a date range, or a date with a time. For a count of days, use
`UI.NumberInput`. For a few fixed dates, use `UI.Picker`.

```luau
local raceDay = Compose.cell({ year = 2026, month = 10, day = 3 })
UI.DateTimePicker "RaceDay" {
    label = "Race day",
    value = raceDay,
    onChange = function(date)
        raceDay:set(date)
    end,
    min = { year = 2026, month = 1, day = 1 },
}
```

The values are civil dates. See [Civil dates](#civil-dates). A date has no
time zone, so it does not move a day where the player sees it.

- `selection`: `single` (the default) or `range`. Set it at construction.
- A single picker uses `value`, `onChange(date)` and `onCommit(date)`. A range
  picker uses `range = { start?, finish? }`, `onRangeChange(range)` and
  `onRangeCommit(range)`. The keys of the other mode cause an error.
- `time`: a single picker only. The value also has `hour` and `minute`.
  `minuteStep` is the minute grid. It must divide 60. The default is 5.
  `hourCycle` is 12 or 24. The default comes from `locale`.
- `min` and `max`: inclusive bounds, or readables of them. `isDateDisabled(date)`
  returns true for a day that the player cannot choose.
- `weekStart`: 1 (Sunday) to 7 (Saturday). The default is 1.
- `locale`: `months`, `weekdays` (short names, Sunday first), `order` (`mdy`,
  `dmy` or `ymd`), `separator` and `hourCycle`.
- `clock()`: returns today. The default is the local clock of the player.
  `referenceDate` sets the month that an empty picker opens on.
- `presets`: a range picker only. Each preset is
  `{ id, label, range = function(today) }`.
- `draft`: adds Reset all, Cancel and Apply.
- `style`: `automatic` (the default) or `inline`. Set it at construction.
  `automatic` is a field that opens a calendar panel. `inline` shows the
  calendar in place.
- `format(date)`: the words of the field. A custom `format` turns off typed
  entry. `placeholder` is the text of an empty field.
- `isPresented`, `onPresentedChange(next)` and `onDismiss(reason)`: the open
  state of the panel. The reason is `activate`, `outside`, `cancel`,
  `anchorLost` or `apply`. Without `isPresented`, the control keeps its own
  open state.
- `enabled` and `readOnly`: booleans or readables. A read-only picker can omit
  the change callback.
- The field chrome keys: `label`, `requiredMark`, `hint`, `errorText`,
  `controlSize`, `appearance` and `corners`. See
  [Field chrome](#field-chrome).

#### Proposals and commits

The value belongs to you. A pick sends a proposal to `onChange` or
`onRangeChange`. The calendar shows only the value that you then hold. If you
refuse a pick, the calendar does not change.

Without `draft`, each change commits at once. A pick, a time step and a typed
date each call `onCommit`. A single pick without `time` also closes the panel.
In a range, the first pick sets `start`. The second pick sets `finish`. If the
second day is earlier, the two ends change places. `onRangeCommit` runs only
when both ends are set. B, Escape and a tap outside close the panel and keep
the value.

With `draft = true`, only Apply commits. Typed text also only proposes. Each
other way out proposes the value that the panel opened with. Cancel does this
too. Reset all proposes an empty value. If you write the value while the panel
is open, your value becomes the value that Cancel restores.

A pointer or a finger can drag the start or the end of a complete range. Each
move proposes a new range. If the end crosses the other end, the two ends
change places. The release commits once, as the draft rules permit. A cancelled
drag proposes the range that the drag started from. A press on another day
does not start a drag, so a tap there still picks.

#### The field

The field is the `Field` plate in the field chrome. When the preferred input
is keyboard and mouse, the field holds a native TextBox named `Entry`.
Otherwise, it holds a button named `Show`. The calendar button `Open` is 44
pixels wide, inside the plate at its trailing edge, with no plate of its own.
The plate is 44 pixels tall, or the `controlSize` height. `Entry`, `Show` and
`Open` take the plate's full height, so no part paints outside it at any
size. `Show` and `Open` fill the plate from edge to edge, share its corners,
and the plate clips their hover and press highlights. `Show` reads in the
`body` text role, the same as `Entry`.

`Entry` takes the numeric form of the locale when focus leaves it. A year has
four digits. A typed range is two dates with " – " or " - " between them. If
the text is not a date, or the day is not available, the text stays. The field
shows the error in the message line and adds the `facet-invalid` tag to the
plate. Nothing commits. An empty text proposes an empty value.

The panel opens below the field, aligned to its leading edge. If there is not
sufficient room below, the panel opens above the field. The panel stays 8
pixels from the screen edges. The `CalendarSurface` ScrollingFrame holds the
calendar. A skinned theme's panel carve (`chrome.panel.contentInsets`) is added
around the calendar, so the art never covers it. The surface is never taller
than the screen, so a tall calendar scrolls. On a touch screen narrower than 600 pixels, the
panel is a sheet at the bottom of the screen with a Done button. On a ten-foot
screen, the panel is a sheet at the center of the screen. The panel is a native
modal. A tap outside the panel, B or Escape closes it. When it closes, the
selection returns to the control that had it before.

#### The calendar

The `Calendar` frame holds these parts in order:

1. `Header`: `Previous`, the `Month` and `Year` menus, and `Next`.
2. `Panes`: `Pane1`, and `Pane2` for a wide range picker. Each pane holds
   `Weekdays` and `Days`, with 42 day buttons `D1` to `D42`.
3. `PageHint`: the page keys, only while the preferred input is a gamepad.
4. `Time`: the `Hour` and `Minute` number fields, and `Half` (AM and PM) on a
   12-hour clock. On touch, it also holds the `Times` list.
5. `Presets`: one chip for each preset, named `Preset-<id>`.
6. `Actions`: `ResetAll` at the leading edge, then `Cancel` and `Apply` in the
   `Commit` row. A sheet without `draft` shows `Done`.

A single date shows one month. A range shows two consecutive months when the
width holds them. The title of each month shows only with two months.

A day outside `min` and `max`, or refused by `isDateDisabled`, stays in the
grid. It is selectable, its label ends with "unavailable", its `Strike` line
shows, and a press does nothing. A day of the next or the previous month is
dim. A press chooses it, but it is not selectable.

The month menu disables a month outside the bounds. The year menu lists the
years up to 50 before and 50 after the shown year, and only the years inside
`min` and `max`. Pick an end year to reach years further away. Each menu opens with the selection on the shown month or year.
A choice moves the calendar to the nearest month inside the bounds. `Previous`
and `Next` stop at a month that is fully outside the bounds.

The day buttons use native GuiService selection. The arrow keys and the
D-pad move one day or one week. Right on the last day of a week moves to the
next day. Left and Right page the month past the first or the last day. Up and
Down move across the shown months. From the first row, Up goes to the `Month`
menu. From the last row, Down goes to the `Hour` field, else to the first
action, else to the next control below. L1, R1, Comma and Period page the
month from each day. When selection enters the grid from another control, it
goes to the chosen day, else to today.

`time` adds the `Hour` and `Minute` fields. Their step buttons follow the
minute grid. The top minute is the last step before 60. `Half` changes between
AM and PM. On touch, the `Times` list shows each time on the minute grid. It
opens at the held time, else at the time of `clock()`.

#### Native state

`ref` receives the root Frame. The root has the `facet-date-time-picker` tag
and these attributes: `month` (for example `2026-09`), `dual`, `route`
(`inline`, `popover` or `sheet`), `presented`, `text`, `typedError` and
`diagnostics`. A readable value that is not a legal date does not change the
picker. The picker keeps the last legal value, adds one to `diagnostics`, and
sends the message to the `onError` factory option.

The theme paints the calendar through these tags: `facet-calendar-day`,
`facet-calendar-band`, `facet-calendar-disc`, `facet-calendar-end`,
`facet-calendar-today`, `facet-calendar-strike`, `facet-calendar-number`,
`facet-calendar-banded`, `facet-calendar-dim`, `facet-calendar-chosen` and
`facet-calendar-chosen-end`. The band is `controlSelected`, and a day number on
it (`facet-calendar-banded`) is `onSelected`.

### Settings rows

The `row` form of Button, Toggle and Slider is one list row. The row has the
`facet-list-row` tag and one `Content` frame. `Content` holds the
`LeadingIcon`, then a `Captions` column that fills the width, then the
trailing parts. `Captions` holds the `Title` and the `Description`. The
description is secondary text. The trailing part is the value and chevron of
a Button, the switch of a Toggle, or nothing on a Slider. A Slider puts its
value next to its title and its track below the description.

A row fills its width. Its minimum height is the `controlSize` height, and it
grows with its content. The row takes the `facet-size-<step>` tag of its
`controlSize`, or no size tag for `regular`. Its left and right padding is
the `paddingX` of the step. Its top and bottom padding is half of the step
height minus its `iconSize` and the `xs` space, so a one-line row keeps the
step height. When the `control` chrome of the theme has a larger inset, the
row uses the inset.
A row draws no separator. Put a `Divider` between rows when a list needs one.

### Stepper and Slider

Both take a numeric `value`, `min` (default `0`), `max` (default `1`), `step`,
`format`, `onChange`, `enabled` and `label`. The maximum must be more than the
minimum. A specified step must be positive. The Stepper step default is `1`.
The Slider default is continuous values.

A Stepper is one selection stop: the Stepper itself takes the selection, Left
and Right change the value, and Up and Down leave it. Its `Decrease` and
`Increase` buttons are not selectable; they still respond to touch and the
mouse.

By default, Slider shows an inline track and a value readout, with an optional
label. Its default native `AutomaticSize.Y` keeps the authored width and fits
the control height. `row` gives a stacked title, description and track. A
Slider row has the `facet-slider-settings` tag and the horizontal padding of a
Button. It shows `row.icon` before the stack, so the Slider row lines up with
Button and Toggle rows.

Slider also supports `onCommit(value)`, `tapToPosition` (default true),
`thumbImage`, `trackImage` and `row`. Dragging uses native drag detection.
Keyboard and gamepad adjustment use the input actions of the control.
The whole Slider (its label, track and value) is one selection stop, so the
engine measures moves from the whole control. Its track and thumb are not
selectable. The focus look is drawn on the 44 by 44 `ThumbStop` frame around
the painted `Thumb` through `FacetFocusPart`, and follows it. With
`thumb = "auto"`, `thumb = "none"` or a `thumbContent` knob, the look is drawn
on the track. A held adjustment repeats after 0.4 seconds, then every 0.1 seconds
(a Stepper's `repeatDelay` and `repeatInterval` set both its held arrow keys
and its held step buttons, with one repeat policy). The
repeat stops when the engine gives the held input to a higher-priority input
context, for example a gameplay binding with `Sink`. The next change needs a
new press.

`contained = true` makes the rail and the fill as thick as the knob, with round
ends, so the knob rides inside the rail. The fill ends at the center of the
knob.

Slider shapes. `axis`, `range`, `minGap` and `thumb` are construction options.
A readable value for one of them causes an error that names the option.

- `axis`: `x` (the default) or `y`. A `y` track runs from bottom to top. Its
  arrows are Up and Down, and Left and Right do not change it. The arrow that
  moves the selection onto a slider does not also change the value.
- `range`: `value` holds `{ lower, upper }`. Each change calls
  `onChange(pair, { thumb = "lower" | "upper" })`, and each completed gesture
  calls `onCommit(pair, { thumb })` once. The two handles, `HandleLower` and
  `HandleUpper`, are 44 by 44 touch targets, and the fill spans between
  them. The handles never cross. A drag keeps the handle that it started
  with. A press on the track moves the nearer handle. For coincident handles,
  a press below the pair moves the lower one and a press above moves the upper
  one. The range Slider is one selection stop. The selection always lands on
  the lower handle; A (gamepad) or Return (keyboard) switches the handle that
  the arrows and the left stick move, and the arrows stay on that handle when
  `minGap` stops the move. The focus look is drawn on the handle being moved,
  and the Slider's `adjusting` attribute (`lower` or `upper`) and accessible
  label name it. A pair that
  is not legal at construction causes an error. A pair that becomes illegal
  later is not painted or written back: the control keeps the last legal pair
  and adds a line to the `diagnostics` attribute.
- `minGap`: a number from 0 (the default) to the width of the range. It is the
  least distance between the handles.
- `thumb`: `always` (the default), `auto` or `none`. `auto` shows the handle on
  hover, selection, drag and with touch input. `none` never shows it. Input
  and the readout do not change.
- `thumbContent(info)`: builds the knob once for each handle.
  `info = { thumb, value, fraction, dragging, enabled }`. `thumb` is `value`,
  `lower` or `upper`. The other four are readables. The knob has no
  `sliderThumb` art and grows from 24 by 24 to fit its content. You cannot
  use it with `thumbImage`.
- `trackContent()`: builds a track node once, for example a colour ramp. It
  replaces the rail and the fill, and fills the track. You cannot use it with
  `trackImage`.
- `rotation`: degrees, or a readable of them. It turns the painted track only.
  The control turns a press back by the same angle, so it reads the value that the
  upright track reads. The label and the readout stay upright.
- `controlSize`: `xsmall`, `compact`, `regular` or `large`. It sets the painted
  track thickness (3, 4, 6 or 8 pixels). The track stays 44 pixels thick as a target.
  The rung also sets the thumb. The thumb is 24 pixels plus the rung's icon size
  less the `regular` icon size, so `regular` keeps the 24 pixel thumb.
- The track is at least 44 pixels long. A cell that fits its content keeps a
  track that you can drag.
- Each knob travels inside the rail by half of its own art size. At the
  minimum, the left edge of the knob art is at the start of the rail. At the
  maximum, the right edge is at the end of the rail. A vertical knob stops on
  the bottom and the top of the rail. The control measures each knob
  separately, so two custom knobs of different sizes both stop flush. For
  `thumbContent`, the art is the first GuiObject that the function returns.
  The fill ends at the centre of the knob. A press or a drag reads the value
  from the same inset travel. With `thumb = "none"`, the travel is the full
  rail.

Losing the input class during a drag (a change of `PreferredInput`) restores
the value, or the whole pair, from the start of the drag. The later move and
release commit nothing.

### Rating and LevelPicker

Both take a numeric `value`, a positive integer `count` (default `5`),
`allowZero` (default true), `readOnly`, `enabled` and `onChange`. The
`value` and `semanticValue` attributes stay in the range from the minimum to
`count`, also when the model holds a value outside it.

- Rating supports `glyphs = { filled, empty }` and `starSize`.
- LevelPicker supports `segment` (`bar`, `glyph` or `image`), `segmentSize`,
  `glyphs`, `images` and `tint` filled and empty Color3 pairs. A bar segment has
  the `facet-level-segment` tag, and a filled bar also has `facet-level-on`.

The named sizes are `small` (20), `medium` (28) and `large` (36).

### Vote

Vote is up, down or none over your value. It requires `value` (`up`, `down`
or `none`, or a readable of one) and `onChange(next)`, unless `readOnly` is
true. `summary` is your own text, such as "99% liked". The optional
`controlSize`, `enabled` and `controls` apply. The control sets
`controls.diagnostics()`.

- The caller owns `value`. A press calls `onChange(next)` once. The strip
  changes only when your value changes. Thus a refused vote never paints, and
  a change from up to down is one change.
- A press on the chosen side proposes `none`.
- The two sides are icon Buttons (`vote.up`, `vote.down`) with the names
  "Upvote" and "Downvote", in the `facet-segmented` strip that Picker uses.
  The chosen side has `facet-segment-current`. Each side is at least the
  target size (`targetSizes.minimum`).
- The summary is one line. Its whole text is in the `FacetLabel` attribute.
  Vote counts nothing.
- `readOnly = true` shows the same icons with your choice marked, with no
  Button and no selection stop. It is not disabled paint. A later
  `readOnly = false` without `onChange` keeps the vote read-only, with a
  warning and a diagnostic line. Each read-only mark has the size of an
  interactive option at the same `controlSize`: the rung height, and not less
  than `targetSizes.minimum`.
- `enabled = false` gives the ordinary disabled Buttons. A late value that is
  not legal keeps the last legal value.

Pointer and touch press a side. Native gamepad selection moves between the
sides. The Activate action (Return or Space) and ButtonA propose the selected
side. The root has the attributes `FacetValue` and `FacetReadOnly`. For a
score out of five, use Rating. For a number that the player adjusts, use
Stepper.

### Chip and ShortcutHint

Chip takes `label` and either a boolean `selected` or `onRemove`.
`onToggle(next)` is controlled. The other options are `editing`,
`removeLabel`, `removeFocusFallback`, and native `leading` and `trailing`
children.

Removal is edit mode. A chip with both `selected` and `onRemove` requires
`editing`, a boolean or a readable boolean that you own. A chip with
`onRemove` and no `selected` is always in edit mode. Outside edit mode, a
chip only selects and shows no close mark. In edit mode, a `Remove` text mark
shows inside the one chip button, and the `AccessibleLabel` attribute is
`removeLabel` (the default is "Remove" and the label). Then activation, and
Delete, Backspace or ButtonX while the chip is selected, call `onRemove`. The
mark is not a separate button or focus stop. `onRemove` does not change your
collection. Remove the item yourself. When a selected chip is removed,
selection moves to the next removable chip, then the previous one, then
`removeFocusFallback`. A Delete or Backspace key that is still down when
selection arrives does not remove the next chip.

A Chip has the `facet-selection-mark` tag. A chosen chip uses the `selection`
and `onSelection` colors when a palette of the theme package declares
`selection`. Otherwise it keeps the selected wash (`controlSelected`).

ShortcutHint takes `keys = { { "Ctrl", "K" } }` or an `action` InputAction. It
also takes an optional `separator` and `controlSize`. The default separator is
` / `. The theme metric `controls.shortcutHint.capStroke` sets the width of the
cap outline. Without it, the outline is `strokes.hairline`. A value of 0 draws
no outline.

`label` shows the words for the action beside the keys in the secondary text
color, such as `label = "Interact"`. `labelPosition` is `end` (the default,
after the keys) or `start`. With a label, ShortcutHint returns a row Frame that
holds the keys, named `Keys`, and the `Label`.

## Menus and navigation

### Menu and SplitButton

Menu takes an `items` array or readable. It also takes an optional `label` or
`trigger`, `icon`, writable `isPresented`, `enabled`, `onOpen` and `onClose`.

Items have a stable `id` and a `label`. They have optional `icon`, `enabled`,
`hidden`, `children` and `onSelect`. Checked and selected items bind their
writable state. Native input actions supply opening and Back behavior. Nested
menus keep the control-specific navigation of the menu.

- `trigger` attaches the menu to a node that you make. The node can be any
  GuiObject, or a function that returns one. Menu returns that same node, with
  the input actions and the overlay of the menu attached. Menu adds no wrapper,
  so the layout does not change. The other native properties of the spec, and a
  constructor name, apply to the trigger node. Give `label` and Menu makes a
  plain Button trigger in a `Menu` frame. `label` and `trigger` together cause
  an error.
- `onOpen` runs once each time the menu opens and `onClose` runs once each
  time it closes. This includes a change of `isPresented`, a chosen action, a
  tap outside, Back, a disabled or removed trigger, and unmount.
- Under the `menu` presentation the floating panel is one raised card. The
  panel has the `facet-menu` tag and owns the corner (`radii.panel`), the
  hairline stroke and a raised `UIShadow`. The rows are flat and touch, and a
  hairline (`facet-menu-hairline`) separates each pair of adjacent rows. A
  divider or a section title starts a new group with no hairline. A selected or
  checked row fills with the `accent` of the theme under an `onAccent` label
  and icon. Each theme package must have 4.5:1 contrast for this pair. Under
  `sheet` the rows keep their gaps and have no hairlines.
- Each row of a floating panel is the hit floor high: `targetSizes.minimum`.
  When the theme package declares `targetSizes.pointer` and the input is
  pointer-only (`MouseEnabled`, and neither `TouchEnabled` nor
  `GamepadEnabled`), the rows use that smaller height and get the
  `facet-menu-dense` tag, which removes their vertical padding. The rows grow
  back when touch or a gamepad becomes available, and become dense again when
  the input is pointer-only. A Picker menu uses the same rows.
- `triggers` limits the routes that open the menu. The routes are `activate`,
  `secondary`, `longPress`, `keyboard` and `gamepad`. The default is all five.
- `presentation` is `automatic`, `menu` or `sheet`. `automatic` is a sheet
  when the preferred input is touch or a gamepad, or when the layer is too
  narrow for the open levels side by side, and a floating menu otherwise. So a
  gamepad gets one panel whose submenus replace its rows, not a cascade.
  `backLabel` sets the text of the Back row. In a sheet, a submenu replaces the rows and adds a Back
  row. In a floating menu, a submenu opens as a new level beside its parent
  level, which keeps the open row filled. A floating menu has no Back row.
- When the player navigates by selection, an open menu selects its first
  enabled item. If an enabled selected item holds the value of its group, the
  menu selects that item instead. Back and Left close one level and return the selection to the
  item that opened it.
- Each level of a floating menu scales from 0.96 to 1 and fades in. It grows
  from the corner where it hangs on its trigger or on its parent row. On
  dismiss it scales and fades out, faster than it came in. In a sheet, a
  submenu slides in from the trailing side, and Back slides the parent level in
  from the leading side. Reduced motion removes the scale and the slide. See
  [Motion](#motion).
- `edge` (`top`, `bottom`, `leading` or `trailing`) and `align` (`start`,
  `center` or `end`) place the root panel against its trigger. The default is
  `bottom` and `start`. When the panel does not fit on its edge and fits on
  the opposite edge, it flips. Submenus keep their position beside their
  parent level. A malformed value causes an error that names the option.
- The panel follows its trigger when the trigger moves while the menu is open.
  The panel stays 8 pixels inside the safe area. When the screen of the menu
  has `IgnoreGuiInset` or `ScreenInsets = None`, the safe area removes the
  `GuiService:GetGuiInset()` insets. A sheet uses the same insets.
- `width` is the width of the floating panel. It takes pixels, a `UDim` or a
  `UDim2` (the X part, against the room of the screen), a dimension table, or
  a readable of one of these. The dimension tables are `{ type = "fixed", px }`,
  `{ type = "fill" }`, `{ type = "hug", min?, max? }`,
  `{ type = "percent", fraction, offset?, min?, max? }`,
  `{ type = "minMax", min?, preferred?, max? }` and `{ type = "content" }`.
  `px`, `min`, `preferred` and `max` take pixels or a theme metric name such as
  `"targetSizes.minimum"`. `hug` and `content` start from the natural width of
  the rows. The width never goes past the room of the screen. A malformed width
  causes an error that names the field.
- `maxHeight` bounds the whole floating panel in pixels. The panel is always
  bounded by the screen, and its rows scroll inside it. On skinned panel art,
  the panel is its rows plus the art carve (`chrome.panel.contentInsets`) on
  each side, and the rows scroll inside the carve. The row ids and the
  activation do not change. The `MenuPanel` Frame is the plate. It holds the
  `MenuScroll` ScrollingFrame that holds `MenuRows`. When the menu fades, the
  `MenuGroup` Frame sits between them and is the size of the panel, so
  a long list never makes a tall fade group, and its text stays sharp.
- A level whose `selected` group holds one of its rows opens with the
  selection on that row, and scrolls that row to the center of the list. A
  `checked` item does not move the landing.
- Every row is at least the target size (44) tall, and the label leads the row.
  A row can also have `badge` (a string, a number or a readable, shown as a
  Badge named `Count`), `avatar` (`{ name, image?, userId? }`, a compact
  Avatar that takes no selection), `sectionTitle` (a caption heading before the
  row, never a selection stop) and `shortcutLabel` (display text such as
  "Ctrl+B"). `shortcutLabel` binds no key. Bind the key where the action is.
  Picker passes the option `badge` to its menu rows.
- `controls` is an optional table. The menu sets `controls.diagnostics()`,
  which returns the platform-guidance advice for the current items: a
  submenu two or more levels deep, a level of more than five items, and a
  destructive item that is not the last of its level. Advice never refuses a
  menu.

```lua
UI.Menu {
    trigger = UI.Button "More" { icon = "more", shape = "circle" },
    width = { type = "hug", min = 220, max = 320 },
    onOpen = function() headerPinned:set(true) end,
    onClose = function() headerPinned:set(false) end,
    items = {
        { id = "rename", label = "Rename", onSelect = rename },
        { id = "delete", label = "Delete", role = "destructive", onSelect = delete },
    },
}
```

SplitButton combines a primary `label` and `onActivate` action with the
secondary `items` of the menu. Use it when the secondary operations supplement
one clear primary action.

With a mouse or a gamepad, SplitButton is one control plate with two parts:
the primary action and a narrow chevron segment, joined by a hairline. Only the
outer corners are round. Each part is its own focus stop and is at least 44
pixels. The chevron opens the menu. Its accessible name and help text are
`menuLabel` (default `More options`). A skinned theme paints its `control` art
once across the whole plate. With touch, SplitButton is one button
with a trailing chevron: a tap runs the primary action, and a long press opens
the menu.

### Picker

Picker requires a writable `selected` and `options`. Each option has `value` and
`label`, and an optional `id`, `icon` and `enabled`. Options can be a plain
array or a readable.
A row keeps its node and its focus when a replacement changes the option. The
row shows the new icon. When the replacement removes the icon, the row hides
it. A row that starts with no icon does not add one later.

The styles are `automatic`, `segmented`, `inline`, `radioGroup`,
`navigationLink`, `menu` and `cards`. The `automatic` style never chooses
`cards`. The `automatic` style follows the options, the
measured width and the native PreferredInput:

- If you supply `query`, it uses the navigation-link presentation.
- It uses `segmented` for four options or fewer when no option has a
  description, the picker is at least 360 pixels wide and the measured
  labels fit in the width.
- Otherwise, for keyboard and mouse, and for touch, it uses a menu.
- For other input, it uses `inline` for six options or fewer, and a menu for
  larger sets.

A `label` shows on the leading edge of a horizontal segmented row, with the
control at its natural width on the trailing edge. With `sizing = "fill"` (the
default) each segment starts at its label's width, at least a 44 pixel target,
and the segments share the space that is left. A strip that does not fit in the
width of the row stays one line: its segments shrink in proportion, a label
wraps between words, and a word that cannot fit its line ends in "…". With
`hug` the segments keep their natural widths. A segment is never wider than the
strip, or than the row of a labelled strip. A radio group or card label that does not
fit wraps inside its row. A segmented picker
takes no `query` and causes an error: a strip shows every option at once, so
use `navigationLink` or `menu` for a searchable list. The label shows above a vertical
segmented, inline or radio group control. A menu shows the label on the leading
edge of the row and the value on the trailing edge.

`onChanging(next, previous)` can return `false` to veto a change. The control
writes `selected`, and then calls `onChange(next)`. An optional writable `query`
filters the labels. The other options include `label`, `placeholder`, `axis`,
`sizing`, `iconOnly`, `textSize`, `isPresented` and `enabled`.

Picker is a field. These options apply:

- `requiredMark`, `hint` and `errorText`: as on [TextInput](#field-chrome). The
  message line shows under the picker in each style. An error adds the
  `facet-invalid` tag to a menu trigger. The picker does not move.
- `controlSize`: the height of the menu trigger, the segmented track and the
  rows. A horizontal segmented track is one control height tall. Each segment
  fills the track inside a 3 pixel inset on all sides. The corner radius of a
  segment is the track radius minus the inset.
- `appearance`: for `menu` and `navigationLink`, `standard`, `contrast` (the
  emphasis plate) or `utility`. For `segmented`, `filled` (the default plate),
  `stroke` (the `facet-segmented-stroke` tag) or `utility` (no plate).
  `automatic` takes all five words and maps them onto the style on screen.
  `inline`, `radioGroup` and `cards` refuse `appearance`. A readable word that
  is not in the family causes an error, and the last correct paint stays.
- `corners`: `pill` or `square`, on the menu trigger or the segmented strip.
- `maxHeight`: for `menu`, `navigationLink` and `automatic`, a finite number of
  pixels above zero. It caps the open panel. The panel always shows one row.
- `valueAlignment`: `end` (the default) or `start`, for a labelled `menu`.
  `end` shows the title above the trigger. `start` shows the title and the
  trigger on one row, with the trigger right after the title. The row is a
  horizontal UIListLayout with `Wraps`, so the trigger moves below the title
  only when the pair does not fit, for example at a large player text size.
  With `sizing = "hug"` the row hugs the pair, which suits a toolbar setting.
  The trigger hugs its value on each input, touch included.
- `indicatorPosition`: for `radioGroup` only, `leading` (the default) or
  `trailing`. It puts the radio mark in its own slot on that edge of the
  content row of each option. The label is next to the mark and does not go
  under it.

A labelled `menu` picker shows its title above a trigger at the leading edge.
With `valueAlignment = "start"`, it shows the title and the trigger on one row.
A labelled `navigationLink` shows the title and the chosen value in one row
button. It opens its list as a Popover attached to the button: a panel with
the theme plate and a tail, `controls.popup.panelWidth` wide and at most
`maxHeight` (400 pixels by default) tall, below the button's trailing end
where the value shows, and no page dim.
On a touch layer narrower than 600 pixels it opens as a sheet, the Popover's
compact route. A searchable list marks the chosen row with a check and paints no
selection plate. Opening a menu puts the selection on the chosen row.

The `cards` style shows each option as a card with the `facet-card-option`
tag: the icon, the label, the description, `meta` and `badge`. The chosen card
has the emphasis plate and is selected, so a skinned theme shows its selected
art. With `axis = "x"`, the cards wrap onto more lines.
With `required = false`, activating the chosen card again sets `selected` to
`nil`.

Options also take `meta` (secondary text), `sectionTitle` (a caption heading
above the option in menus and in stacked rows), `avatar = { name, image?,
userId? }` (an Avatar at the leading edge of a menu row, which adds no stop)
and `indicator = { status, form?, count? }` (a StatusIndicator that follows
the live option record). A menu row, a stacked row and a searchable list row
show `badge` as a `Badge` named `Count`; a segmented option keeps the count in
its words. Menu items take the same `badge`, `meta`, `avatar` and `sectionTitle`
fields, and Menu takes `maxHeight`.

### ComboBox

ComboBox requires a writable string `value`, a writable string `text`, options
and an `acceptCustom` validator. The control combines editable search, option
selection and explicit acceptance of custom values. Keep the accepted value and
the text in progress in separate model cells.

### TabView

TabView requires a writable `selection` that names a declared tab. It also
requires `tabs` with unique `{ id, label, content }` entries. Tabs can be a
plain array or a readable. `content` is a factory that returns native content.

A bottom bar (with its `aboveBar` accessory) sets the `FacetInsetBottom`
attribute on its layer while it shows, so a bottom Toast docks above it.

By default, Compose `LayerStack` keeps the visited content
(`retention = "all"`). Use `retention = "top"` to dispose departing pages after
their transition. Keep durable page state in the model.

An automatic placement follows `adaptive.navPlacement` of the TabView's own
size, the preferred input, the display size and ten-foot viewing: a TV takes a
top bar, a compact width a bottom bar in the thumb zone, a short height the
compact bottom bar, a pointer a sidebar, and a roomy touch screen or a gamepad
on a larger display a top bar. A TabView inside another TabView's page keeps a
top bar.

Use `style = "sidebarAdaptable"` for peer destinations. Its selected tab is a
pill, and its top bar is a segmented strip: the tabs hug their labels, centred
on a track. `sidebarPreference` (`"sidebar"` or `"topBar"`) chooses between the
two roomy homes, except on a ten-foot display, which keeps the top bar.
`sidebarExpanded`, a writable boolean cell, is the ten-foot command that
replaces `expandSidebar()` and `collapseSidebar()`: set it to `true` (from a
Menu or a Button) and a distant screen shows the sidebar; ButtonB while the
selection is in that sidebar sets it back to `false` and the top bar returns,
with the selection kept on its tab. A near screen ignores it and follows
`sidebarPreference`. Page Back keeps ButtonB when the selection is in the page.
`placement` sets an explicit choice. `placement = "none"` hides the
bar and gives the page the whole view. Selection, shoulder navigation and
`selection` changes still work; supply your own route to the other tabs, such
as a Menu. `railWidth`,
`sidebarPreference`, `sections`, accessories and
`customization = { order, hidden }` refine the presentation. Required tabs
cannot be hidden.

A sidebar is as wide as its widest tab label plus the tab padding and icon, and
its labels are centred. Before the labels are measured it is 20 percent of the
TabView width, from 200 to 280 pixels. `railWidth` sets the width and aligns
the labels to the leading edge. The tabs of a top bar are centred in it.

`onChange(id)` reports a user selection. A programmatic selection change does
not look like user input. The control owns scroll and focus restoration and
shoulder navigation.

A tab can have `indicator`, a StatusIndicator spec `{ form?, status?, count?,
max? }`. It shows in that tab's own button. The whole-control `indicator` is a
different setting. A tab with `enabled = false` stays in the strip, but no
route selects it: a press, shoulder navigation and the collapsed menu skip or
refuse it. A malformed tab indicator causes an error that names `indicator`.

A tab with an `icon` and a `badge` shows the badge on the icon's top corner.
When the tab also shows its label, the gap between the icon and the label
grows to hold the half of the badge that sticks out past the icon. Thus the
badge never covers the label.

`textSize` defaults to `fit`. In a bottom bar each tab gets an equal share of
the width, and its words shrink from the `control` type size toward the
`caption` size to fit that share before the engine truncates them. The control
measures the words at the control size. A number or a readable number sets a
fixed size.

`controlSize` (`xsmall`, `compact`, `regular` or `large`, or a readable) is the
size step of the tabs. Each tab is `controlSizes.<step>.height` high and has the
`controlSize` attribute. The strip stays `targetSizes.minimum` high (44
pixels, 66 at ten feet) and centres the tabs in it. Without `controlSize`,
each tab is that high too.

A TabView that is built inside the page of another TabView is nested, also
when a branch of that page builds it later. A nested TabView uses a top band.
An outer TabView with `placement = "none"` shows no bar, so a TabView in its
page is not nested and takes the full home policy.

A page change uses a native crossfade. The default is
`transition = { seconds = 0.2, ease = Compose.easing.outQuad }`. Supply other
direct Compose tween options to change it. Use `false` to disable motion. Named
Facet transition presets do not exist. The first page shows without motion.

### NavigationStack

NavigationStack requires a writable `path`, `root` and `destinations`. The path
is an array of `{ id, value }` entries. `root` and each `destinations[id]` are
`{ title, content }`. Destination content receives the entry.

- To push, append an entry.
- To pop, remove the last entry.

`backLabel` sets the text of the native Back chrome. Compose `LayerStack` owns
the retained pages and their disposal.

A push slides the new page in from the trailing edge. The covered page moves
30 percent to the leading edge and dims. The covered page keeps its full
width, so its controls do not change size. A pop plays the reverse. The popped
page stays until its motion completes. It cannot be interacted with, and it
cannot hold the selection. While a page moves, both pages are opaque. Each page
gets the background color of the nearest opaque container of the stack. A
separate black shade frame dims the covered page from 0 to 0.1 opacity. The page
content does not change its transparency. At rest, the pages are transparent. The default motion is a critically damped Compose
spring. `transition = { seconds, ease }` replaces the slide with a crossfade
that uses those Compose tween options.
`transition = false` disables motion. The pages that are present when the
stack mounts show without motion.

### PageView

PageView requires a writable `selection` and `pages` with unique ids and
content factories. It supplies page navigation, indicators, and previous and
next actions. Use it for a sequential set of peer pages. TabView is for named
destinations. NavigationStack is for a drill-down path.

The indicators are a row of dots, one button per page, named by the page id.
The current page's dot is painted in the accent colour. Each dot's accessible
name is `Page n of m`. `indicators = false` hides them.

While the selection is on a control in a page, Left and Right (and the D-pad
Left and Right) page back and forward. The selection then moves into the new
page. Up and Down leave the pages.

The native `UIPageLayout` moves between pages over 0.3 seconds, Cubic Out, with
no overshoot, for Previous, Next, a dot and the arrow keys. A swipe released
faster than 1200 pixels a second settles with Quint Out (`styles.fling`)
instead, which decelerates harder and never overshoots.

### Pagination

Pagination selects one page of numbered results. It does not fetch data.
It requires `page` (a number or a readable) and `onChange(nextPage)`.

- `pageCount` is a whole number of 0 or more, or a readable of one. `nil`
  means that the count is unknown.
- `hasNext` and `hasPrevious` (default false) set the arrows for an unknown
  count. A known `pageCount` ignores them.
- `siblingCount` and `boundaryCount` are whole numbers from 0 to 20. The
  default of each is 1.
- `showFirstLast` (default false) adds First and Last arrows. Last shows only
  for a known count.
- `form` is `numbers` (default), `arrows` or `label`. `direction` is `ltr`
  (default) or `rtl`. `controlSize` and `enabled` are optional.
- `controls` is an optional table. The control sets `controls.diagnostics()`,
  which returns the refusal lines.

The caller owns `page`. A press proposes one page through `onChange`. The row
changes only when your value changes. Thus a refused proposal changes nothing.
A page outside the range shows clamped, with a warning and a diagnostic line.
The control never writes it back. A late value that is not legal keeps the
last legal value. A malformed value at construction causes an error.

The numbers form shows the boundary pages, the current page and
`siblingCount` pages on each side. An ellipsis replaces a gap of two or more
pages. The work is bounded by the two counts, not by `pageCount`. The control
measures the width of its root (`AbsoluteSize.X`). When the row does not fit,
the farthest boundary page goes first, then the farthest neighbour (the higher
page on a tie). When only the current page and the arrows do not fit, the row
shows "Page n of m". An unknown count always shows "Page n". Zero pages shows
"No pages" with no stops. One page has no enabled arrow.

Each page is a compact Button in a slot that is at least the target size
(`targetSizes.minimum`) wide. The arrows are icon Buttons of the same size.
The label keeps the width of the widest label that the count can make, so the
arrows do not move when the page gains a digit. Page nodes are keyed by page
number. When the selected page leaves the window, or a selected arrow becomes
disabled at an edge, the selection moves to the current page. When the row has
no live page or arrow, for example when the count drops to zero, the selection
moves to the nearest selectable object outside the row. `rtl` reverses
the row once. The root is a Frame that fills its width. `AutomaticSize` on X
causes an error, because the window narrows to the width that it gets.

The root has the attributes `FacetCurrent`, `FacetCount`, `FacetForm` and
`FacetDirection`. Use Pagination for results that you load one page at a time.
Use VirtualList for one long list and PageView to swipe between screens.

### StepIndicator

StepIndicator shows where a workflow is. It shows a list of step states. It
is not a number control. It requires `steps` (an array or a readable) and
`current` (a step id, `nil` or a readable). A step is `{ id, label,
description?, state?, navigable?, enabled? }`. `state` is `complete`,
`current`, `upcoming` or `error`.

- Step ids are nonempty and unique. Labels are nonempty and can repeat.
- `current` alone sets the current step. It places the underline and the
  summary "Step n of m — Label". `state = "current"` is accepted only on the
  step that `current` names.
- A step's `state` sets its cue and its state word: a check for `complete`,
  the error icon for `error`, and otherwise the step number in a circle. Thus
  an errored current step keeps its error cue. The state word shows under the
  label.
- A `current` that names no step shows "No current step". An empty list shows
  "No steps" and has no Steps button.
- A step is a Button only when it is `navigable`, it is not disabled, and you
  supply `onSelect`. Other steps are plain content and never selectable. A
  press on a permitted step calls `onSelect(id)` once. The control never
  writes `current`. Thus a refused step changes nothing.
- Every step has the same inset as a Button of its `controlSize`, whether it
  is a Button or plain content. Thus every cue starts at the same place.
- `sizing` is `fill` (default, every step gets an equal share of the row) or
  `hug` (each step gets its own width). `listLabel` (default
  "Steps"), `controlSize`, `enabled` and `controls` are optional. The control
  sets `controls.diagnostics()`.

A malformed snapshot at construction causes an error. A later malformed
snapshot keeps the last legal one, with a warning and a diagnostic line. The
control measures its root width. With `fill` it compares that width with the
widest step text times the step count. With `hug` it compares that width with
the laid-out row (the row `UIListLayout.AbsoluteContentSize`). When the steps
do not fit, the row changes to the summary and a Steps Menu. The menu lists every
step. Permitted steps select through the same `onSelect`. The menu closes
when your `current` changes, so a refused step leaves it open. The number
circle keeps an aspect ratio of 1 at every text size. The row stretches its
cells to one height with a native `ItemLineAlignment`.

The underline is a `facet-selection-indicator` frame. It moves to the new
current step on a spring. Reduced motion places it immediately. Its position
and width are fractions of the row width, so an ancestor `UIScale` (the TV
scale) does not scale it twice. The root has
the attributes `FacetCurrent`, `FacetSummary`, `FacetForm` (`row` or
`summary`) and `FacetListOpen`.

### RadialMenu

The required `items` use the menu item model. The options are:

`isPresented`, `label`, `launcher`, `preset`, `distribution`, `navigation`,
`expansion`, `center`, `centerLabel`, `centerContent`, `centerPassThrough`,
`anchor`, `follow`, `clearance`, `ringWidth`, `contentFit`, `gestureSelection`,
`holdAction`, `enabled`, `scrim`, `onOpen` and `onClose`.

The launcher is a round `more` button whose accessible name is
`Quick actions`. With a `label`, the launcher is a text button that shows the
label, and `icon` adds a glyph to it. `launcher = false` hides it. With a
native GuiObject `anchor`, the launcher sits over the centre of that object.

`holdAction` is a native InputAction Instance that the caller owns. The control
subscribes to its `Pressed` and `Released` events. It does not accept an action
name, and it does not define key bindings. Parent the action under a native
InputContext and declare the InputBindings there.

`completion` sets what item activation does: close, stay, return to the root,
or go back. You can navigate nested items. Checked and selected items update
their model. The geometry is specific to this control. It does not add a second
general layout or input system. A native GuiObject anchor or a projected
screen-point anchor connects the menu to an existing surface.

An open ring is a modal surface on the same layer as Dialog and Menu. It
blocks the page's input but does not dim it by default, as in 0.11.
`scrim` sets how much the open ring dims the page: `"none"` (the default),
`"dark"` or `"light"` (the theme scrim that a Dialog uses). The dark scrim is
black and at least 80 percent opaque (the theme's `scrimOpacity` when that is
higher). A scrim reaches past the ScreenGui's safe-area insets to the screen
edges, the hole included, unless `centerPassThrough` is on. The transparency
preference scales it like every scrim. A still tap outside
the ring closes the menu. A press outside the ring that slides onto a wedge
still selects it. With `centerPassThrough`, the page is not dimmed.

A wedge takes the theme panel paint (`surfaceStrong`) and its label the
content paint. A hovered, focused, checked or selected wedge takes the selected
paint (`controlSelected`), the same state its label shows.
The wedge is the item. Its icon and label are a plate-less `utility` button
with no theme control art, sized to the largest box that fits inside the wedge
and clipped to it.

An item on the ring shows its icon or its label, never both. It shows the
icon when its `labelStyle` is `icon`, its `compactLabel.prefer` is set, or it
is a `buttons` item with an `icon`. Otherwise it shows the label. The list
fallback shows both.

`ringWidth` is a number of pixels or a theme width: `narrow`, `regular` or
`wide` (`controls.radial.narrow`, `.regular` and `.wide`). Each ring is at
least that thick and grows until every item's label or icon box fits, with
`space.s` around it, at the item's direction. The box is estimated from theme
metrics, not measured: the label is its character count times 0.6 of
`typography.control.size` wide and one control line tall, and an icon is
`iconSize` square. The ring is never thinner than `targetSizes.minimum`, is
thick enough for each wedge to be one touch target wide, and is never wider
than the room. The same items and theme always give the same ring.

Where Back and Close sit depends on the preset, `center` and the room:

- A full ring (`donut` or `circle`) with `center = "back"` (the default) has
  one control in the centre hole. It is Close at the root and Back in a
  submenu; Back goes up one level and Close closes.
- A full ring with `center = "empty"`, `"content"`, `"root"` or `"close"`
  puts Back/Close on the ring, as a wedge (or button) of the deepest open
  level. An even ring turns so that this wedge sits at the lower left. A
  compass ring gives it the first free slot of `SW`, `S`, `SE`, `NW`, `W`,
  `E`, `NE`, `N`. `root` also shows Home in the centre, which returns to the
  root, and `close` shows Close there. With `empty` or `content` the centre
  holds no control, except on a compass ring with no free slot: then Back/Close
  sits in the centre.
- A corner preset never puts it on the arc or uses `center`: the control on
  the corner, over the launcher, is Close at the root and Back in a submenu.
  It grows out of the launcher, which it hides while the ring shows: it opens
  at the launcher's size with the launcher's glyph, and shrinks to its own size as that glyph crossfades to
  Close or Back. As the ring closes it grows back into the launcher the same
  way.
- The list fallback has one round Back/Close control at the top right, above
  the list, for every preset and `center`.

The centre control is a small round `utility` button, 32 pixels across, with
no plate and no theme control art. A transparent `CenterHit` target around it
is one touch target (`targetSizes.minimum`) across and does the same thing. It
shows a close, back or up-chevron (Home) icon. The word is its accessible name,
and a `centerLabel` replaces that name; it is never shown as text. Cancel (the B button) and the
Back/Close control do the same thing. The name of the highlighted item sits in
the hole under the centre control, on one caption line, truncated to the
hole's width. Without a centre control the name is centred in the hole. In
the list fallback the name sits at the bottom left, in its own band under the
scrolling list, never inside it.

A corner ring names the highlighted item just outside the arc, on the arc's
middle direction.

A finger held still on an item for 0.4 seconds names it and does not pick
it: that release does nothing, and a second tap picks the item. A press that
slides more than 14 pixels is a gesture, and its release picks the item under
the finger.

Nothing is highlighted when the ring opens, until the player points at an
item, presses a direction or moves the stick. With a gamepad as the preferred
input, the first item is selected, because the console needs a focused
control. When a submenu replaces the level, the selection moves to the first
item of the new level. While any ring is open, `GuiService.GuiNavigationEnabled`
is false, because the engine's pad navigation otherwise takes the left stick
from the ring; the ring binds its own D-pad, A and B. On the ring, a D-pad
direction pointing back across the centre goes to the centre control, and the
next press on to the item on the other side; from the centre each direction
goes to the item nearest that direction; any other direction moves to the
neighbouring item along the ring, so every item can be reached. The value before the
first ring opened comes back when the last one closes, unless the game turned
it on at any point while a ring was open; then the game's current value stays.
Setting it to false while it is already false is not a change the engine
reports, so a game that wants it off after the rings close sets it after the
last close. The ring blooms out of its centre: the items and wedges travel from a
fifth of their distance to their places as they fade in. Reduced motion places
them at once.

Without an `anchor`, the ring opens centred on its launcher. It is placed on
the measured presentation layer from the first frame. Before the
launcher has a size, and with `launcher = false`, the `preset` sets the
position. A full ring (`donut` or `circle`) then moves inward until its inner
radius plus `ringWidth` (or 44 pixels) fits inside the presentation area. The
ScreenGui keeps that area inside the safe area. Corner presets are not moved.

## Presented controls

A Sheet or Dialog title shows in the theme's title plaque when the panel art
has one, and the header title then hides. Without a title the plaque is not
drawn.

A presented panel with a theme skin keeps its content inside the art. Sheet,
Dialog, Popover, a Toast with an action, Menu and the picker panels pad their content by the
theme's `panel` chrome `contentInsets` on each side, and never by less than
their own padding. The padding follows a live theme change.

### Alert

Supply a writable boolean `isPresented`, or a writable `item` cell where `nil`
means hidden. Also supply `title`, `message` and `actions`. The alert captures
the item payload for the active presentation and gives it to the content and
callback factories.

Actions have `id`, `label` and `role`, and an optional `enabled`, `shortcut` and
`onActivate(payload)`. Dismissal occurs before the action callback.

The control owns the initial selection, selection containment, Back and cancel,
and restoration to the previous selection if that object still exists.

Motion options:

- `transition = { source = nativeNode, seconds = 0.2, ease = Compose.easing.outQuad }`
  enables native source motion. `source` can also be a readable.
- `surface = "fullScreen"` fills the native presentation area. The content
  and the actions stay in a centered column. The column is not wider than
  `maxWidth` (default 960 pixels).
- With `surface = "fullScreen"` and a source transition, both bounds
  interpolate from the source rectangle. The alert content keeps its final
  size and the growing panel clips it. A non-interactive native snapshot at
  the source size covers the start of the handoff and fades out in the first
  35 percent of the motion. Dismissal fades it in during the last 35 percent. Dismissal reverses to the source if
  it still exists. Compose owns the snapshot and the departing presentation.
  The source stays mounted.
- Native reduced motion makes the handoff immediate.
- Without `transition`, the alert scales from 0.94 to 1 and fades in. See
  [Motion](#motion).
- `transition = false` makes the presentation immediate.

The alert clears a writable `error` on dismissal. Use an alert for a brief
decision. `icon`, `severity`, suppression and custom content refine the
presentation. The `suppression` checkbox sits below the actions.

### Sheet

Sheet requires a writable `isPresented` and a writable `detent`. The default
detents are `medium` and `large`. A custom entry is `{ id, fraction }` or
`{ id, height }`, never both. The `hug` entry fits the body and the pinned
regions. It measures the content of the body, not the scroll canvas, so it does
not grow to fill the room. It measures again when the content changes, and it
stays inside the safe room and above a minimum of four target heights.

Supply a `title` and a `content` factory that returns native children. The
sheet calls the factory without arguments. Its subtree fills the body region.
The body uses a native vertical ScrollingFrame named `SheetContent`. Thus
content taller than the selected detent stays reachable, and the sheet chrome
stays fixed.

Layout options:

- `placement`: `automatic` (the default, the bottom edge), `adaptive`,
  `bottom`, `center` or `side`. On a ten-foot screen `automatic` and
  `adaptive` centre the sheet, and they dock it again when the screen is near. `adaptive` docks the sheet at the side edge
  when the room is 600 pixels wide or more, a mouse is available and touch is
  not. Otherwise it uses the bottom edge. It changes live with the room and
  the input. The `FacetPlacement` attribute of `SheetPanel` holds the result.
  A side sheet docks to `edge` (`left` or `right`, default `right`). `edge`
  also applies to `adaptive`. Its detents stay vertical. It slides in from its edge and leaves
  toward it. Under reduced motion it arrives and leaves at once.
- `width`: `automatic`, `narrow` or `wide`. These are the Dialog widths:
  `controls.alert.maxWidth`, `controls.popup.panelWidth` and
  `controls.dialog.wideWidth`. The safe room bounds each one.
- `header`: absent shows `title`. An Instance or a factory replaces the title.
  `false` removes the title row.
- `hero`: `{ image | content, aspectRatio | height, scaleMode?, background?,
  sticky? }`. A sticky hero stays pinned above the body. Otherwise it scrolls
  with the body. With `header = false`, the close control sits over the hero
  as an `inverse` button, so it reads on any art. Hero `content` is inset 16
  pixels from the sides and 12 from the bottom.
- `actions`: a list of `{ id, label, role?, enabled?, busy?, onActivate }`.
  They stay pinned below the body and never close the sheet. `actionLayout`
  is `automatic`, `row` or `stacked`. Cancel runs an enabled `role = "cancel"`
  action first.
- `contentInset`: `standard` (8 pixels) or `none`. It changes only the body
  padding.
- `scrollPolicy`: `always` (the default) keeps the body scrolling at every
  height. `atLargestDetent` stops the body scroll below the tallest detent.
- `closeButton`: absent, `true`, `false`, or a string or readable label.
  Absent shows no close button while the grabber shows, because the grabber
  closes and resizes the sheet. With `dragIndicator = "hidden"`, absent shows
  an icon-only close button in the trailing corner of the header. Its
  accessible name is `Close`, and its target is 44 pixels. `true` always shows
  that icon button. A label shows a text button with that label. `false` shows
  none; Back, Escape and the backdrop still close the sheet.

When the pinned regions and a short body do not fit the panel, every region
moves into one scrolling column named `Room`. Thus each action stays
reachable. The on-screen keyboard height comes off the room, and the panel
sits above the keyboard.

Native drag detection resizes the sheet. The grabber detector starts a drag at
once. A second detector on the panel starts a drag only after 6 pixels, or 14
pixels on touch. A release goes to the detent nearest to the released height
plus 0.15 seconds of its velocity. A hold before the release has no velocity.
Below the lowest detent the whole sheet moves down instead of getting shorter,
so the header, the body and the pinned actions move together. A drag below 70
percent of the lowest detent dismisses the sheet, and the exit slide starts
where the drag left it. Past the
limits the drag resists. `interactiveDismissDisabled` holds the sheet near its
lowest detent and blocks Back and the backdrop. An outside detent change
during a drag ends the drag. Only one drag runs at a time.

The grabber sits on the edge that the sheet came from. A bottom or center
sheet has a horizontal bar at the top. A side sheet from the right has a
vertical bar on its left edge, and a side sheet from the left has one on its
right edge. The grabber sits in its own gutter at that edge, just inside the inner edge
of the theme's panel art (`contentInsets`), centred along the edge. The
content reserves only the gutter, 20 pixels plus an 8 pixel gap, on that side
and keeps equal padding on the other sides. On a side sheet,
a drag of the grabber toward the sheet's edge moves the whole sheet. A release
past a third of the width, or faster than 600 pixels a second, closes it.
Otherwise it slides back.

The grabber is also a selectable button. A tap or click closes the sheet
(with `interactiveDismissDisabled` it grows the sheet instead). The engine
gives a press on the grabber to its drag detector and never fires the button's
`Activated`, so a grip drag that ends within 4 pixels of where it started is
the tap. Return or the
gamepad A button grows the sheet to the next taller detent, and its accessible
label reads `Resize: Medium`, or `Resize: Fit` for `hug`. At the tallest
detent, and with one detent, Return or A closes the sheet, and its label reads
`Close sheet`. The grabber's own drag detector
takes a press-drag that starts on the pill, and a release after a drag is not
also a click. The pointer shows a resize cursor over the grabber and a closed
hand while it drags (`SizeNS`, or `SizeEW` on a side sheet, and
`ClosedHand`). Return and the gamepad A button activate it. A bottom
sheet slides up from the bottom and slides down when it closes. The sheet
stays off screen until its room, width, text and height are the same for two
frames, and then it starts to move. Thus the text has its final size and wrap
before the sheet shows, and the height does not change during the slide. With
reduced motion the sheet appears at rest after the same wait. See
[Motion](#motion).

### DisclosureGroup and CollapsibleView

Both require a writable `expanded` and `content`. DisclosureGroup expands its
content in the document flow. The content is in a clipped Frame named
`Reveal` that holds a Frame named `RevealFade`, which fades. The height of `Reveal`
opens with the motion, and then follows the content with `AutomaticSize`.
The chevron keeps its `chevron.trailing` and `chevron.down` art and turns
between them. For outer layout, use the native properties on their returned
roots. See [Motion](#motion).

CollapsibleView returns its trigger, a pill Button (`corners = "pill"` unless
you pass `corners`).

- Collapsed, the trigger shows `label` on one line. The label truncates at
  the end (`TextTruncate.AtEnd`) and shrinks in the row (a `UIFlexItem` in
  `Shrink` mode). A `chevron.down` trailing icon is the More affordance. Pass
  `trailingIcon` to replace it.
- When `expanded` is true, a panel named `Expanded` grows out of the trigger:
  its rectangle moves from the trigger's rectangle to its open rectangle on
  the page's layer, and it clips its content. The open panel is at least
  `controls.popup.panelWidth` wide (or the trigger's width), as tall as its
  content, and stays inside the layer by `space.s`. A taller content scrolls
  in a `ScrollingFrame` named `ExpandedScroll`. The content is laid out once at
  the open size in a Frame named `ExpandedFade`, which fades in, so the text
  does not rewrap while the panel grows. The page does not move and is not
  dimmed.
- The panel is on the modal layer, so the selection moves into it: to
  `initialFocus` if you give it, otherwise to the first selectable node.
- The trigger (A, Return or a tap), a tap outside the panel, the Close button
  and Cancel (Escape or ButtonB) collapse it. The selection goes back to the
  trigger.
- `dismissButton = false` hides Close unless the preferred input is a gamepad.
- Reduced motion opens and closes the plate at once.
- The plate is inside the trigger. An ancestor with `ClipsDescendants`, such
  as a ScrollingFrame, clips it. Give the trigger room below it.

DisclosureGroup `appearance` is `plain` (the default), `contained`, `divided`
or `outline`. The root has the `facet-disclosure-<appearance>` tag. `outline`
is a tree row: the header starts its chevron and label at the leading edge, it
does not get the `facet-selected` tag while the group is expanded, and it keeps
focus and activation. `textSize` is a type role or a
number of pixels for the header label, as on Button. `indent` is a spacing step
(`xs`, `s`, `m`, `l` or `xl`) or a number of pixels. It adds a left UIPadding to
`RevealFade`, so nested groups read as an outline.

### Callout

Callout requires a native `anchor` with a separate parent and `onRetire`. The
callout borrows the anchor. When a native ancestor of the anchor is hidden, the
callout is suspended. `seen`, `sessions`, `afterSessions`, `featureUsed` and
priority set eligibility and queue order. Each fact can be a value, a readable
or a function of `use`. Retirement is delivered once. A callout is contextual
teaching attached to a control. It is not a second application presenter.
`edge = "top"` puts the callout above the anchor. If there is no room above
and there is room below, the callout goes below the anchor. The callout
scales and fades from the edge nearest to its anchor. See [Motion](#motion).
A tail points from the plate to the centre of the anchor.
The plate stays inside its layer by the `space.s` step of the theme on each
side. The step follows a live theme change. The layer is the safe area of the
ScreenGui, so a device safe inset adds to the step.
A callout and a help plate paint above a toast with an action and below a presented modal.

The plate parts are optional, but the plate must show something:

- `content`: an Instance or a factory.
- `title`: a string or a bound string. It shows as a heading.
- `media`: `{ image, aspectRatio | height, scaleMode?, background? }`.
- `steps`: `{ index, count }`. It shows `index of count`.
- `actions`: one or two `{ id, label, role?, enabled?, busy?, onActivate }`.
  They replace the bottom `Got it` button. A press retires the plate with the
  reason `action`, once, also when `onActivate` fails. A disabled or busy
  action does not run.
- `closeButton`: `true` adds a close control at the top. It retires the plate
  with the reason `dismissed`.

A failure in `onShow` does not stop the plate. The failure goes to the
`onError` factory option, or to a warning.

### Dialog

`UI.Dialog` returns an empty anchor Frame. The panel is a modal surface.

```luau
local open = Compose.cell(false)
runtime.mount(function()
    return Host.ScreenGui {
        UI.Dialog "Leave" {
            isPresented = open,
            onPresentedChange = function(nextValue) open:set(nextValue) end,
            onDismiss = function(reason) print(reason) end,
            title = "Leave the race?",
            content = function() return UI.Text { text = "Your lap will not count." } end,
            actions = {
                { id = "Retry", label = "Retry", keepOpen = true, onActivate = function() print("retry") end },
                { id = "Leave", label = "Leave", role = "destructive", onActivate = function() print("left") end },
            },
        },
    }
end, playerGui)
```

The caller owns `isPresented`. The dialog reads it and never writes it. The
close button, Cancel and a tap on the backdrop call `onPresentedChange(false)`.
The dialog closes only when the fact changes. A refused proposal keeps the same
panel and selection. A dialog with `actions` has no close button: ButtonB
and Escape run its `cancel` action. A dialog without actions shows one;
`closeButton = true` or `false` decides either way. A dialog that shows a
close button needs `onPresentedChange`. Without `onPresentedChange`, the
backdrop and Cancel do nothing.

An action press closes the dialog by default. It runs its `onActivate`, and
then proposes `onPresentedChange(false)`, as the close button does, so a
refused proposal keeps the dialog open. An accepted close reports `action`, and
so does a false that the caller accepts in the callback. An action with
`keepOpen = true` runs its `onActivate` and proposes nothing. Use it for Apply
or Next. An action that raises an error proposes nothing. Sheet, Notice
and Callout actions refuse `keepOpen`. Cancel runs an enabled `role = "cancel"`
action first. Otherwise Cancel proposes false. The one
`role = "default"` action answers Return. A disabled or busy action does not
run. `onDismiss(reason)` reports each closure once, after its cleanup:
`close`, `outside`, `cancel` or `action`. The caller's own false and owner
disposal report `cancel`. A failing callback is raised after the dialog state
is consistent.

Other options:

- `title`, `actionLabel`: strings or bound strings. An empty bound title hides
  until it has text.
- `content`: a factory for the one body. The body scrolls between the pinned
  header, hero, action label and actions.
- `hero`: the shared media shape.
- `actionLayout`: `automatic`, `row` or `stacked`. `automatic` puts two short
  actions in a row and stacks three or more. A row that cannot show the full
  labels also stacks, and so do the actions of an Alert, a Dialog and a Sheet
  on a ten-foot screen (`ctx.tenFoot()`) or at the `Larger` and `Largest`
  preferred text sizes, each full width.
- `width`: `automatic`, `narrow` or `wide`.
- `contentSelectable`: `true` (the default) makes an overflowing body one
  selectable stop. With the selection on it, Up and Down scroll the body. At
  each end the selection moves on.

A dialog needs a title, content, a hero, an action label or actions. The
height is the layer height less the keyboard height and the margins. When the
pinned regions and a short body do not fit, every region moves into one
scrolling column named `Room`. The panel is a Frame. It scales from
0.94 and fades in with its scrim. See [Motion](#motion).

### Popover

`UI.Popover` returns its `trigger`, or an empty Frame for a `source` popover.

```luau
local open = Compose.cell(false)
runtime.mount(function()
    return Host.ScreenGui {
        UI.Popover "About" {
            isPresented = open,
            onPresentedChange = function(nextValue) open:set(nextValue) end,
            trigger = UI.Button { label = "About scoring" },
            maxWidth = 320,
            content = function() return UI.Text { text = "Laps score by position." } end,
        },
    }
end, playerGui)
```

Supply exactly one of `trigger` (a native GuiButton) or `source`. `source` is
`{ node = GuiObject }` or `{ rect = { x, y, w, h } }`. A trigger press, Cancel
and a tap outside call `onPresentedChange(next)`. The popover changes only when
the caller's fact changes. An open popover is modal, so a press on its own
trigger lands outside it. `onDismiss(reason)` reports each closure once:
`cancel`, `outside` or `anchorLost`. The trigger proposal uses `trigger`.

When a source node leaves the layer, the popover closes at once, proposes
false and reports `anchorLost`. It does not open again until the caller's fact
goes from false to true. A source node that is not mounted yet is not lost.
The popover waits for it and warns once. A `rect` source never draws a tail.

Placement options: `edge` (`top`, `bottom`, `leading` or `trailing`), `align`
(`start`, `center` or `end`), `gap` (pixels, default 8) and `crossOffset`
(pixels along the alignment axis). The placement tries the preferred edge,
then the opposite edge. When neither side holds the panel, it hangs beside the
source before any clamp. `maxWidth` and `maxHeight` bound the whole panel,
chrome included, inside the live safe box. The body scrolls. `tail = false`
removes the arrow.

The tail of a Popover, a Callout and a Button `help` plate is one shape: a
`space.m` square turned 45 degrees under the panel (`facet-tail`), with no
stroke of its own. One closed native `Path2D` named `Outline` in the panel
(`facet-outline`, `facet-outline-tooltip` on a help plate) draws the whole
border: the panel's rounded corners and the tail's two outer sides as one
line, so the edge stops exactly where the tail begins. Its colour is the
theme hairline blended over the panel fill, because a `Path2D` has no
transparency, and it fades with the panel. The panel's own `UIStroke` is off
(`facet-outlined`). The tail stays clear of the panel's rounded corners. The panel stands the tail's reach off
its source, so the tip stops at the gap. The panel's `AnchorPoint` is the tail
point while it scales, so a moving scale never moves the tip. The tail keeps
8 pixels from the panel's ends; a panel too short for that (a one-line panel
beside its source) centres the tail on its side instead of dropping it. The
tail is dropped only when it would no longer point at the source.

`cancelPolicy` is `dismiss` (the default) or `none`. With `none`, Cancel and a
tap outside propose nothing, so only the caller's fact or an action in the
content closes the panel. The panel stays modal.

`modal = false` makes the panel chrome, such as a coach mark or a hint beside
a control. There is no backdrop, no outside-tap catcher, no Cancel binding and
no selection claim, and the full-layer `Popup` Frame is not `Active`, so input
reaches the controls under and around it. The panel paints in the callout band
(`ZIndex` 95). A chrome panel always uses the anchored route.

`compact` is `sheet` (the default) or `popover`. With `sheet`, a touch player
on a layer narrower than 600 pixels gets the Sheet route. A live change of
input or width switches the route without a proposal. Only one content owner
exists at a time, and the selection returns to the same content node. The
sheet uses the `hug` detent, so its height fits the content. `title` (a string
or a bound string) shows in the sheet header beside Done. Without `title`, the
header shows only Done.

The trigger keeps its own `onActivate`. The panel scales and fades from the
edge nearest to its source. See [Motion](#motion).

### Toast

`UI.Toast` returns an empty anchor Frame. It shows a transient message. Without
an `action` it is display-only and stacks at the top (or bottom) of its layer.
With an `action` it docks at the bottom center, one at a time, and a player can
reach it. Both modes share one schedule per layer.

```luau
runtime.mount(function()
    return Host.ScreenGui {
        UI.Toast "Saved" { message = "Settings saved", key = "save", duration = 3 },
        UI.Toast "Sold" {
            message = "Kart sold",
            action = { label = "Undo", onActivate = function() print("undo") end },
        },
    }
end, playerGui)
```

- `message` (a string or a bound string) or `content` (a factory for the
  body). Give exactly one. A toast with an action takes `message`.
- `icon`: an icon name or an image source, before the message.
- `duration`: seconds on screen. Without an action the default is 4. With an
  action, `nil` keeps the row until it is closed, and a timeout waits for at
  least `readFloor` of readable time. `readFloor`: the seconds before anything
  may replace it, default 2.5.
- `priority`: a number, default 0. Higher toasts go first in the queue.
- `key`: a toast with the same key replaces a queued one at once and a
  showing one when its read floor is met, so the two never show together.
- `isPresented`: optional, the caller's boolean fact. The toast shows while it
  is true. A timeout, a replacement, Close, Cancel and the action then propose
  false through `onPresentedChange(false)`, and the row leaves only when the
  fact is false. A refusal keeps the same row and is not asked again. A bound
  toast that can end itself (a duration, or a close button) needs
  `onPresentedChange`. Without `isPresented`, mounting shows the toast once
  and it retires itself.
- `onDismiss(reason)` reports each retirement once: `timeout`, `supersede`
  (the same key replaced it), `preempt` (a more urgent toast replaced it),
  `capacity`, `action`, `close`, `cancel` (a bound toast's fact went false, or
  its owner went away), or `manual` (an unbound toast unmounted first). A
  bound toast retired for `capacity` or `supersede` also proposes false.

Without an action:

- `position`: `top` (the default) or `bottom`, the edge that the stack docks
  to. Each edge of a layer has its own stack. The stack docks clear of the
  app's reserved chrome on that edge: the deepest `FacetInsetTop` or
  `FacetInsetBottom` reservation of its layer and of every enabled sibling
  ScreenGui (a TabView bottom bar, a visible toast with an action, an affixed
  Notice), read each frame while a toast shows.
- `width`: `fill` (the default) spans the layer less 16 pixels on each side.
  `hug` fits the content, centred, up to 560 pixels, and wraps longer text.
- `fade`: by default the row fades in and out as it slides (the fade draws
  the row through a CanvasGroup only while it runs, so settled text keeps
  native glyph rendering). `false` only slides.

At most three toasts show on an edge and eight wait. The queue is in priority
order, first in first out within a priority. A more urgent toast replaces the
weakest showing one, but only after that toast's read floor. At the cap the
least urgent waiting toast retires with `capacity`; a showing toast never does.

The row is input-transparent: it is neither `Active` nor `Interactable`,
nothing in it is `Selectable`, it binds no input and it never takes the
selection, so the controls under it work as before. Rows (`ToastRow`) paint
at `ZIndex` 70, above the page and below a modal. A new row slides in from its
edge and fades in (unless `fade = false`), and the others slide to close the slot a
retired row leaves. Under reduced motion the rows are placed at once, for the
same times in the same order.

With an action:

- `action`: `{ label, onActivate }`. Unbound, it runs and retires the row
  with `action`. Bound, it runs once and the row leaves when the fact is
  false.
- `closeButton`: `true` (the default) or `false`.

One row shows and up to eight wait. Readable time pauses while the row is
hovered or selected, or while a modal is open. Queued time does not count.
The row uses `controls.snackbar.maxWidth`, bounded by the layer, and docks
16 pixels above the app's reserved bottom chrome (a TabView bottom bar, an
affixed Notice; its own reservation does not count). The action
moves below long text. Arrival never takes the selection, and one Down from
the control that had it reaches the row. Cancel (Escape or the B button) on a
selected row proposes or retires with `cancel` and returns the selection to
the content, also when the caller refuses. The Down link from the control that had the selection lasts
until the selection moves anywhere else; an action toast still stays until it
is closed when it has no `duration`, as the snackbar did. A visible row sets the
`FacetInsetBottom` attribute on its layer until it has slid out, so a bottom
stack of display-only toasts docks above it. The row is a Frame named `Snack`
at `ZIndex` 60. It slides up and fades in to enter, and slides down and fades
out to leave. A leaving row cannot be interacted with. Under reduced motion it
arrives and leaves at once. There is no swipe.

The anchor carries `ToastVisible` and `ToastQueued` attributes.

`app.presentToast(component, options?) -> { id, dismiss() }` shows
`component(app.UI)` as a toast in the app's toast ScreenGui (named from
`name`, `FacetToasts` by default), which all its toasts share, so they stack
and queue together. `options` takes the keys
above except `message` and `content`. `dismiss()` retires it with `manual`
and returns false when it has already gone. The toast's mount stops when it
retires.

### Notice

`UI.Notice` returns the notice Frame. It keeps a status in the page until the
state changes. It is never modal.

- `message`: required, a string or a bound string. `title` is optional.
- `severity`: `info` (the default), `success`, `warning` or `error`.
- `appearance`: `standard` or `emphasis`. `emphasis` fills the plate with the
  severity color. A `standard` plate pads its content by the theme's `panel`
  chrome `contentInsets`, and not less than 8 pixels, so art in the frame does
  not cover the content. The title wraps and is never cut.
- `icon`: `true` (the severity icon), `false`, or an icon name or source.
- `link`: `{ label, onActivate }`. It uses the link appearance on a standard
  plate.
- `actions`: up to two actions. Roles only paint. There is no default or
  cancel key.
- `onDismiss`: shows a close button. A press closes the height of the
  notice and then calls `onDismiss`. Remove the notice yourself. If the notice
  stays mounted, it opens again. Under reduced motion, or before the notice
  has drawn a frame, `onDismiss` runs at once.
- `placement`: `inline` (the default) or `affixed`.

The link and actions sit beside the copy when the measured width holds them.
Otherwise they move below it. The notice does not take the selection. A new
notice opens its height from 0, so the content below it moves down smoothly.
While the height moves, the notice clips its content and uses
`AutomaticSize = None`. At rest it uses its own `Size` and `AutomaticSize`. An
affixed notice fills the width and sets the `FacetInsetTop` attribute on its
layer to its bottom edge. Several affixed notices keep the deepest edge.
Content that must avoid the notice reads the attribute and pads by it.

### NavBar

`UI.NavBar` returns the bar Frame: `{ onBack?, backLabel?, title?, titleSize?,
leading?, center?, trailing?, gap?, padding?, surface? }`. `surface` paints a
background plate: `surface`, `panel` or `pane`, the theme roles of the same
names.

The first row holds Back, `leading` and a `center` that fills the remaining
width. Without `center`, the title shows on one line and truncates. `trailing`
is one GuiObject. Put a cluster in a Frame. The title and the trailing node
stay on one row when the full title fits beside the trailing node. When the
full title does not fit, the trailing node moves to a second row. Without a
title, the bar uses `controls.popup.panelWidth` as the minimum center width. The
center is not rebuilt, so a search field keeps its text. Back shows the
`chevron.leading` icon beside its word, half a `space.xs` apart, in the
content colour with no plate (`utility`), and a `space.s` gap keeps the title
away from it. NavigationStack's Back and the Back row of a sheet menu are the
same control. `gap` and `padding` are pixels or `space` metric
names.

## Collections

### VirtualList and VirtualGrid

Required: `from` (an array, readable or body) and
`render(current, placement, key)`. `key` is a function `(item, index) -> key`
or the name of the field that holds the identity, for example `key = "id"`. A
field name gives `tostring(item[field])` as the key. If you omit `key`, Compose
uses item identity. Render receives readables for the current item and its
placement, and returns native content. Keep durable row state outside that
render owner.

| Option | Default and meaning |
|---|---|
| `mode` | `windowed`; `all` deliberately mounts the entire collection. |
| `direction` | `vertical`; `horizontal` changes the scrolling axis. |
| `itemSize` | `40`, the estimated main-axis extent. On a horizontal list, `"cards"` sizes the cards from the space the rail gets. A compact touch rail (under 600 px) shows one card with a peek of the next and snaps to cards. Wider rails show as many whole cards of at least 200 px as fit. `cards = { perView?, minWidth?, peek? }` overrides the count, the floor or the peek. `cards` is refused without `"cards"`. |
| `gap`, `crossGap` | `0`; the cross gap defaults to the gap. A VirtualGrid keeps half of each gap (rounded up) at its outer edges, as a `UIPadding` on its `Items` frame and in its canvas extent. Thus content that paints past its cell, such as a lifted Card, is not cut by the scroll clip. |
| `columns` | The grid column count, default `1`; can be reactive. |
| `overscan` | `2`. |
| `measure` | `false`; set to observe the rendered native `AbsoluteSize`. |
| `measured` | An optional readable map from key to extent; overrides observed measurements. |
| `follow` | `none` or `end`, or a readable of one, with an optional `followThreshold`. |
| `status` | An optional writable Compose collection status cell. A cell that holds `nil` is filled with the empty status record. |
| `controls` | An optional table that the control fills with the Compose `indexOfKey`, `placementOf` and `offsetOf`. |
| `maxRetained` | The pool keeps at most `32` row hosts by default. |

The returned root is a ScrollingFrame. Compose `OrderedCollection` owns
indexing, window selection, anchor preservation and placement. The control
applies its desired offset to `CanvasPosition`. Sorting keeps the native anchor.
It does not force the first item to the top.

`snap = "item"` settles scrolling to the Compose placement boundaries. The
default is `none`. With `follow = "end"`, the list follows appended rows while
the viewport stays at the end. When a readable `follow` changes, the control
replaces its Compose `OrderedCollection` and mounts the rows again. Keep durable
row state in the model. Other values cause an error.

Optional collection focus uses `focus`, `initialFocus`, `autoFocus`,
`wrapFocus`, `focusPolicy` and `disabled(item)`. `focusPolicy = "key"` (the
default) keeps focus on the item when the order changes. `"index"` keeps it on
the slot, so a live standings list does not walk the gamepad focus up and down.
It moves focus to the item that now holds the slot, or the last slot when the
list shrank, and leaves focus alone while a row is being dragged. With `wrapFocus = true`, `focus.next()`,
`focus.previous()` and the arrow and D-pad actions wrap at the two ends of the
collection. A list wraps only along its scrolling axis.

- `selection` is a writable key-set map.
- `selectionMode` defaults to single when you supply `selection` or its
  callback. Otherwise it defaults to none.
- `onSelectionChange(nextMap)`, `onActivate(item, key)` and `onReachEnd`
  connect control events to domain behavior.
- When the selection mode is not `none`, one mouse click selects a row. A
  double click, Return, a gamepad press or a touch tap runs `onActivate`. A
  double click keeps the selection. When the mode is `none`, each activation
  runs `onActivate`. Table rows follow the same rule.
- `selectable(item)`, `reorderable`, `movable(item)`, `dragLabel` and
  `onReorder(keys, insertionSlot)` use the same zero-based insertion contract
  among the remaining rows as Table.
- A keyboard or gamepad move steps along the scrolling axis. A vertical
  collection uses Up and Down. A horizontal collection uses Left and Right.
- A reorder that would move a row that is not movable does not occur.

Native properties and children stay available.

```luau
local rows = Compose.cell({ { id = "a", title = "Amber" } })
local list = UI.VirtualList {
    from = rows,
    key = "id",
    itemSize = 52,
    Size = UDim2.fromScale(1, 1),
    render = function(current)
        return UI.Button {
            label = function(use) return use(current).title end,
            onActivate = function() inspect(current:peek().id) end,
            Size = UDim2.new(1, 0, 0, 52),
        }
    end,
}
```

### Card

Card shows one item of a browsable collection: artwork, a title and an
optional caption, with a primary action and a More menu that show on
engagement. It requires `title` and `image` (nonempty strings or readables).
`artwork` can replace `image`. The other options are `caption`,
`imageAspectRatio` (default `16/9`),
`imageFraming` (`fit` or `crop`), `onActivate`, `primaryAction = { label,
icon?, onActivate, enabled?, busy? }`, `menu = { items, label? }`, `reveal`
(`automatic` or `always`), `browseTarget`, `enabled`, `ringTarget` and
`controls`.

With `onActivate`, the selection ring of the body surrounds the whole card: the
artwork, the text and the action row. `ringTarget = "media"` rings only the
artwork. The body keeps the PlayerGui's live focus look (see
[focusRing](#focusring)) and sets its `FacetFocusHeight` attribute, the height
of that area as a multiple of the body's, which the look reads. So a card's look
pulses, hides after mouse input and follows a theme change like every other
control's. A selected action keeps the look on itself.

Use a Card for a game, a track or a kart, where the picture helps the player
choose. For rows of text, use VirtualList or Table.

- The artwork frame is as wide as the card. Its height is the measured card
  width divided by `imageAspectRatio`.
- `artwork` is a factory that returns a GuiObject, such as a `Stage` preview.
  The card mounts it once in the artwork frame and sizes it to fill the frame. With `image`, the image shows under the
  artwork. The card owns the artwork and releases it with the card.
- With `onActivate`, the body is a Button. `onActivate(input)` receives the
  native input of the activation, or `nil`. Without it, the body is plain
  artwork and text. The primary action is a Button. `menu` is a Menu behind a
  More trigger (`menu.label`, default "More"). The body, the primary action
  and More are sibling targets under a root that is not a Button. Thus a press
  runs exactly one of them. `enabled = false` applies to all three.
- A late value of `title` or `image` that is empty or of the wrong type keeps
  the last legal paint, with a warning and a diagnostic line.
- `always` keeps the action plate visible. `automatic` (the default) shows it
  at rest when the session has touch (`TouchEnabled` or a touch
  `PreferredInput`), and otherwise while the card is engaged. The card is
  engaged while the pointer is in it, the selection is in it, a press is held
  on one of its actions, its menu is open, its actions are entered, or the
  `browseTarget` is selected. A card with no body action and no
  `browseTarget` has no stop of its own, so it shows its actions at rest.
- The plate is a Frame directly below the body in the card's own layout.
  With `automatic`, it paints a panel surface under the action row. The
  primary action fills the row and More is an icon button at its end. With
  `always`, the row has no plate and sits a small gap below the body. The plate
  is always laid out, so the card size never changes and the siblings never move.
  At rest it is transparent and not `Interactable`, so its actions take no
  press and no selection. The fade uses a Compose tween, so a quick reversal
  continues from the current value. Reduced motion shows and hides it
  immediately.
- While engaged, the card's `UIScale` named `Lift` rises to 1.04 on a spring,
  and a body Button shows its `UIShadow` named `LiftShadow`. A card with no
  body action has no shadow. When `PreferredInput` is `Touch`, the card does
  not lift and shows no shadow: a tap on the body, the primary action or More
  gives only the press paint of that control. The lift is for pointer hover,
  selection and a held mouse press. The scale is paint only: the artwork height
  uses the width without the lift, so the card size does not change. Outside a
  layout, the card offsets its `Position` by half of the growth, so it grows
  evenly around its centre. Keep gutters of at least half the scaled growth
  around each card. Reduced motion keeps only the shadow.
  When a `browseTarget` exists, the card puts a `UIScale` named `CardLift` with
  the same scale on it, so the selection ring grows with the card.

`browseTarget` is a function that returns the browse stop of the card, such
as the `RowHit` of a VirtualGrid cell. `controls` is an optional table. The
card sets `enterActions()`, `leaveActions()`, `diagnostics()` and the readables
`engaged`, `revealed`, `scale`, `lifting` (true while the lift applies) and
`revealExtent` (`{ body }`, the measured root height). `enterActions()` holds the reveal and selects the first eligible
action. It returns false for a disabled or unmounted card, or when no action
is eligible. It never runs the primary action. While the actions are entered,
the action row is a `SelectionGroup` whose selection behavior is `Stop` on all
four sides. Escape or ButtonB leaves the actions and selects the browse stop.
The menu closes first when it is open. A press outside the card also leaves.
When the card is removed or recycled, it releases the entry.

The root has the attributes `FacetReveal`, `FacetRevealed`, `FacetEngaged`,
`FacetHovered`, `FacetFocusWithin`, `FacetPressing`, `FacetBrowsing`,
`FacetEntered`, `FacetMenuOpen` and `FacetBody` (`button` or `informational`).

```luau
local controls = {}
local cards = {}
UI.VirtualGrid {
    from = games,
    key = "id",
    columns = 3,
    itemSize = 320,
    measure = true,
    gap = 16,
    onActivate = function(_item, key) local entry = controls[key]; if entry then entry.enterActions() end end,
    render = function(current, _placement, key)
        controls[key] = {}
        local card = UI.Card {
            image = art,
            title = function(use) return use(current).title end,
            controls = controls[key],
            browseTarget = function()
                local node = cards[key]
                return node and node.Parent and node.Parent:FindFirstChild("RowHit")
            end,
            primaryAction = { label = "Play", onActivate = function() play(key) end },
            menu = { items = { { id = "hide", label = "Not interested", onSelect = function() hide(key) end } } },
        }
        cards[key] = card
        Compose.cleanup(function() cards[key], controls[key] = nil, nil end)
        return card
    end,
}
```

### Table

`from`, `key` and `columns` define the rows. `key` has the same forms as for
VirtualList. A column has:

- `id` and `label`,
- an optional pixel `width` (otherwise flex),
- `minWidth` (48) and `maxWidth` (1e6),
- `resizable` and `sortable` (both true),
- `value(item)` or `render(current, placement, key)`.

A column collapses only when it has a numeric `priority`. Larger values
collapse first. The first column always stays visible. The other columns
keep their `minWidth` and truncate their text, so a narrow table scrolls
sideways and never loses a column. Under touch or gamepad input a flexible
column's floor is the smaller of its `minWidth` and the theme's touch floor
(`targetSizes.minimum`, 44), so more columns fit a phone before the table
scrolls sideways. A Popover shows collapsed and natively
truncated values through the row's icon-only `more` (…) button, named
"More actions". The cell
state stays retained. The header band spans the whole row, edit controls
included, and shows a hairline divider between headings; the headings sit over
their columns.

Editable cells. A column with `editor = "text"`, `"number"`, `"toggle"` or
`"menu"` shows a TextInput, a NumberInput, a plain checkbox Toggle or a menu
Picker in each cell. The column `value(item)`, or the field named by `id`, is the
raw value: a string, a number, a boolean or the value of a menu option. `options`
(`{ { value, label } }`) configures a menu. `min`, `max` and `step` configure a
number. Each accepted edit calls the `onCellChange(rowKey, columnId, value)` of
the table, which an editor column requires. The caller updates its rows, and a
row change updates the cell. An edit that does not change the value proposes
nothing. A refused edit shows the value of the row again. The editors keep
their native routes: a click or a tap, Return or the A button starts a text
edit, and Escape or the B button cancels it. A row that leaves the table, or
scrolls out of a windowed table, releases its editors and discards an edit in
progress. An editor with `render`, an unknown editor word, a menu without
`options`, editor settings on a column without `editor`, and an editor column
without `onCellChange` cause an error.

Editable collections. Table, VirtualList and VirtualGrid take the same model.
`reorderable = true` with `onReorder(keys, insertionSlot)` moves rows, and
`deletable = true` with `onDelete(keys)` removes them; both only propose, and
the caller changes its rows. `movable(item)` and `rowDeletable(item)` refuse
single rows. On a Table, a row that `rowDeletable` refuses also loses its
destructive `rowActions`, so no swipe, menu or key can remove it. The paths per
input:

- Pointer: drag a row, or one of the selected rows to move them all, more than
  6 pixels along the list. There is no handle. The drag shows an image of the
  row, stacked two or three deep for a selection, and scrolls the list near its
  edges unless `autoscroll = false`. Once the list can move no further that
  way, the nearest enclosing ScrollingFrame whose own 40 pixel edge band holds
  the pointer scrolls instead (innermost first), so a list inside a page hands
  the drag to the page. Delete or Backspace removes the selected
  rows.
- Touch: hold a finger still on a row for a third of a second to pick it up
  and move it; a finger that moves first scrolls the list or swipes the row.
- Touch and gamepad, and a keyboard with no mouse on a reorderable Table: a
  Table without a supplied `editing` shows a toolbar with an `Edit` button (`Done` while editing; its width fits the wider word).
  Edit mode shows, inside each row band, a round red minus at the leading
  edge (deletable, unless `selectionMode = "multiple"`) and a move handle at
  the trailing edge (reorderable); the row content slides to make room
  (instantly with reduced motion). The minus reveals a `Delete` button at the
  trailing edge, which confirms. A handle
  drags, or Return or the A button starts a move that the arrows or D-pad
  place and Return, A or `Drop` ends. The X
  button removes the selected rows, and L1 and R1 move them by one slot. A
  VirtualList reads the `editing` cell that you supply and show your own
  Edit control.
- Without a readable input class the edit controls always show.
- A selectable collection (`selectionMode` other than `"none"`) that is not
  `deletable`, and any `selectionMode = "multiple"` collection, marks each
  row's selection at the leading edge while `editing` is true: a ring
  (`facet-radio-mark`) with a filled dot on a selected row. The mark is paint
  and takes no focus. A Table with a supplied `editing` shows it even when it
  is neither reorderable nor deletable.
- While `editing` is true, a tap, a click, Return or the A button on a row of
  a selectable collection toggles that row's selection and does not run
  `onActivate`. With `selectionMode = "single"` the row becomes the one
  selected row, and a second press on it clears the selection. A deletable
  Table's own
  toolbar shows a `DeleteSelected` button (`Delete`) beside `Edit` while it
  edits, except with a gamepad, whose X button does the same; it removes the
  selected rows through `onDelete` and is disabled while nothing is selected.

With touch or gamepad input, a Table with the Edit toolbar accepts cell edits
only while editing; otherwise its editor cells accept edits at all times.
`rowActions` are independent of edit mode.

`sort` is `nil` or `{ column, direction = "ascending" | "descending" }`.
`widths` is a map of column widths. A pointer drags a heading's divider to
resize the column. With a keyboard or gamepad, focus the divider: Left and
Right resize, Up and Down sort by the column, and Escape or B returns focus to
the heading. Comma and Period resize the column whose heading or divider has
focus. `selection` is a key-set map.
`selectionMode` is `single`, `multiple` or `none`. When you supply
`onSortChange`, `onWidthsChange` or `onSelectionChange`, it is a controlled
request. Otherwise the control updates the writable cells.

In `multiple` mode, the selection keys are the same in Table, VirtualList and
VirtualGrid:

- A plain mouse click selects only that row.
- Ctrl-click or Cmd-click adds the row to the selection or removes it.
- Shift-click selects the rows from the anchor to the clicked row. The anchor
  is the last row that a click without Shift selected. A second Shift-click
  makes the range again from the same anchor. Rows that you added with
  Ctrl-click before the anchor stay selected.
- A touch tap, a gamepad press and a plain Return add the row or remove it.
  Return with Ctrl, Cmd or Shift follows the click rules.
- Shift with an arrow key, Home or End moves the focus and selects the range
  from the anchor to the focused row. Without an anchor, the focused row
  becomes the anchor.
- An arrow key without Shift moves the focus and does not change the
  selection.

In `single` mode, each activation selects only that row, and the modifiers
have no effect. A selected Table row carries the `facet-selected` tag, so the
theme paints it in `controlSelected`. Rows that `selectable` or `disabled` refuse are never selected.

`selectable(item)`, `disabled(item)`, `onActivate(item, key, input, clickCount)`
and `rowActions(current, key)` specialize rows. `onActivate` receives the same
native activation facts as in VirtualList. The insertion slot of `onReorder` is zero-based among the remaining rows.

Sizes:

- The header height starts at 40.
- Rows follow a ladder by viewing distance (`itemSize` pins the minimum on
  every rung):
  - Near (pointer, keyboard, or a gamepad at a desk): one line, at the larger
    of 40 and the regular control height (44 with a gamepad).
  - Touch: cells wrap, and a row starts at two lines of body text plus 16, at
    least `targetSizes.minimum`.
  - Ten-foot (`ctx.tenFoot()`: a TV interface, or a Large display with no
    touch and no mouse): one line, at least the large control height.
- The native touch and gamepad minimum header height is `44`.
- Native text bounds can make rows and the header larger.

The header band and each row paint a rounded band (`radii.control`) through
the theme tags `facet-tablehead` and `facet-tablerow`; a 1 pixel inner
`surface` stroke separates adjacent rows, and a selected row is the same band
in `controlSelected`.
`alternatingRows = true` also tags every second row `facet-tablerow-alternate`.
The palette roles are `tableHeader`, `tableRow` and `tableRowAlternate`. Each
heading is a standard Button without a plate (`facet-tableheading`) on the
band, so a skinned theme paints its `control` art on it.

`header = false` removes the header band. `scrolls = false` mounts all rows and
sizes the table to its content. Otherwise, `mode` selects the Compose windowed
or all lifetime. The collection measurement, status, controls, focus and
follow options also apply.

### RowActions

`content` is native content or a factory. `leading` and `trailing` contain
`{ id, label, icon, enabled, role, onActivate }` actions. `open` is `nil`,
`leading` or `trailing`. `onOpenChange` is controlled.

`actionWidth` has a minimum default of `88`. Native label bounds can make the
action tray larger. Each action is as wide as its painted label, plus its icon
and gap when it has an `icon`, plus 32 pixels. Full swipe is on by default. You can set it for each edge.
A row with no measured width does not open or run an action from a swipe.
A shared `coordinator` cell lets only one row be open. When a row opens,
through a gesture or a write to its `open` cell, the other rows close.

Native swipe, context, and keyboard and gamepad actions reach the same
commands. In a collection row, these actions also apply when the row itself
has the selection. A destructive action runs exactly once, after its Compose
departure animation. If the owner is removed, an unfinished departure is
cancelled. If the owner keeps the row, for example when the server refuses the
delete, the row returns to its full height on the next frame, and the action
can run again. A full swipe commits or opens a tray only after the row has a
measured width.
`reducedMotion`, `enabled` and `editing` stay explicit control options.

A mouse click or a touch outside an open row closes its tray. The row observes
`UserInputService.InputBegan` only while its tray is open, and it does not
consume the input. Thus the control under the pointer also receives the press.
A transparent `SwipeGrip` button covers the row content while the row has
actions. It holds the native UIDragDetector, so a drag that starts on a
content Button also opens the tray. A press and release that moves less than
8 pixels is a tap. In a selectable Table, VirtualList or VirtualGrid row, the
grip sends the tap to the row, so the tap selects the row with the click rules
of the collection, and a reorder handle or a cell Button does not activate.
Otherwise the grip sends a tap to the first Facet Button in the content, and
that Button activates as if the player pressed it. The grip is
not a selection stop, so keyboard and gamepad selection still stop on the
content. With touch input, the grip turns its UIDragDetector off and uses the
native `TouchPan` gesture. Thus a vertical pan scrolls the list, and a
horizontal pan opens the tray. A touch tap reaches the content Button through
the grip.

A tap or a click on the content of the open row closes the tray, and the
content does not activate. While the tray is open, a transparent
`DismissTray` button covers the row content and receives that press. A press
on another row closes the open row, and that other row activates. A press on
the open tray does not close the tray, and its action runs once. A
press during a destructive commit does not stop the commit. The check uses the
row bounds on a ScreenGui, with the top bar inset when the ScreenGui ignores
it. A row on a SurfaceGui or a BillboardGui does not close from an outside
press.

## Media and status

| Control | Main contract |
|---|---|
| `Text` | Plain text in a native TextLabel. `text` is required. `textRole` (or `textSize` as a role name) is one of `TYPE_ROLES`. `textSize` is also a pixel number or a fit form. `role` is `secondary` or `content`. Also `truncate`, `lines`, `textAlign`, `wrap`, `rich`, `direction`, `tint`, and native text properties. See [Text](#text). |
| `Label` | An icon and a title in a row. `title` is required, and it is the accessible name. Also `icon`, `presentation`, `iconSize`, `textSize`, `gap` and `iconPosition`. See [Label](#label). |
| `Image` | A native ImageLabel. `image`, `tint`, `scaleMode`, `tileSize`, `sliceCenter`, `sliceScale`, `resample` and `shape`. See [Image](#image). |
| `Badge` | `label`, `status`, an optional icon and position, appearance, corners and control size. The icon and the label share one pill. The status appearance keeps a neutral pill and shows the status as a leading dot. |
| `StatusIndicator` | `status`: `neutral`, `info`, `success`, `warning`, `error`, `accent`, `voice` or `contrast`. `voice` marks live voice chat in the `voice` color. `contrast` is a `contentStrong` mark that reads on any surface. Badge `status` takes the same words. `form`: dot, ring, square or dash. Optional `count`, `max`, `diameter` and `name`. The `name` sets the accessible label. A ring is a native inner stroke in the status color. A count grows into a pill that is never narrower than it is tall. |
| `Path` | A stroked vector path on a native `Path2D`, for simple vector icons, arcs and gauge needles. `points` is required: a list, or a readable of a list, of normalized points from `Facet.pathShapes`, at most 100. A new list moves the same stroke. `role` is `content` (the default), `secondary` or `accent`, and the StyleSheet colours the stroke from the active palette. `tint` sets a colour that no role names. `thickness` is pixels or a theme metric name; without it the engine default applies. `closed` joins the last point to the first. `width` and `height` set a square or rectangular box in pixels. The engine strokes a path and does not fill it, and a path has no transparency of its own. |
| `ProgressView` | `value`, `min` (0), `max` (1). `presentation`: bar, circular or spinner. label and endLabel, showValue and format, diameter, thickness, segments, and an optional trail `{ delay, duration }`. The endLabel shows after the value. With a label, a bar shows the value and the endLabel on the label row. Segments require the bar presentation. Diameter requires circular or spinner. A trail holds on damage, settles over its duration, and snaps on healing or reduced motion. A circular value is centered when the native text bounds fit. Otherwise it shows below the ring. A circular ring with no thickness uses 8 percent of its diameter, and not less than the theme metric. On a bar, `controlSize` sets the track thickness: `xsmall` and `compact` use `space.xs`, and `regular` and `large` use `controls.progress.trackHeight`. A bar refuses `controlSize` together with `thickness`, and a ring or a spinner refuses it together with `diameter`. `endLabel` must be a string. |
| `Skeleton` | A loading placeholder with a configurable form and line count. `corners` rounds a box or a line: `square`, a number of pixels, `control` (or `rounded`) and `panel` for the radii of the theme, or `pill`. A circle refuses `corners`. |
| `AsyncImage` | An image or source, an optional resource or loader, a placeholder, a failure label and a status callback. `imageProperties` forwards native properties and children to the inner ImageLabel. |
| `Avatar` | `name`; one face: image, userId, resource or `icon` (an icon name, such as `"person"` for a guest, drawn in place of the initials); loader and onStatus; presence online, away, busy, offline or `inExperience`; presence label and mark; diameter or controlSize; standard or icon form; `background`, a palette role (`surface`, `surfaceStrong`, `control`, `contentStrong`, `accent`, `success`, `warning` or `danger`) for the plate, with its partner color on the initials and the icon; optional activation. `inExperience` draws an `accent` ring with a `surface` gap inside the edge of the face in place of a corner mark. Each band is twice `strokes.hairline` wide. An Avatar without an activation takes no input. With one, a `HoverRing` stroke in `accent` lights only the avatar under the pointer. |
| `AvatarGroup` | `items` with id, name, image, userId, icon and presence, and an optional `resource` shared-resource acquire function. max (4); stacked or spread layout; count or ellipsis overflow; onOverflow; diameter or controlSize. A stacked group has the `facet-avatar-stack` tag, and the theme draws a surface ring around each face. The faces take no input. The overflow chip is the only target: an `OverflowGap` keeps it clear of the overlapping faces, and with touch or a gamepad it is at least `targetSizes.minimum` on both axes. The group binds no gamepad button, so ButtonB reaches the screen. |
| `Stage` | A native ViewportFrame. A `camera` CFrame or a borrowed Camera, `fieldOfView`, `content(runtime, world, live)` for 3D content that Compose owns, and `lazy`. |

### Text

`UI.Text(spec) -> TextLabel` shows plain text. `text` is a string, a readable
or a function of `use`. It is required. `label` and the native `Text` cause an
error, and so do `color` and `font`, because the theme owns them. Use `role`
or `textRole` instead.

- `textRole` sets the type role tag, for example `facet-type-title`. The
  default is `body`. `textSize` can give the role instead, as a role name.
  Both together cause an error.
- `textSize` as a number sets `TextSize` in pixels. `"fit"` and
  `{ fit = { cap, floor } }` fit the text to its box. See below.
- `role = "secondary"` adds the `facet-secondary` tag. `role = "content"`
  removes it. `role` can be bound.
- `textAlign` is `start`, `center` or `end` and sets `TextXAlignment`. It can
  be bound. `wrap` sets `TextWrapped`. `rich = true` sets `RichText`.
- `direction` is `auto`, `ltr` or `rtl` and sets `TextDirection`.
- `tint` sets `TextColor3` for a colour that no role gives.
- `disclose = true` keeps a truncated value readable. While the engine
  reports that the text does not fit (`TextFits`), or a middle cut shortens
  it, the whole value shows in a panel named `Disclosure` beside the label:
  after a pointer rests on the label for 0.45 seconds, after a keyboard or
  gamepad selection rests on the label or on the control that holds it, or at
  once on a touch long-press on the label. The next touch anywhere closes it.
  The panel takes no selection.
- `reveal = "auto"` makes a one-line label that truncates at the end scroll its
  whole value. It rests in the engine's ellipsis for 1.2 seconds, then the
  whole string slides left as one strip (`Reveal`, clipped to the label's box)
  at about three characters a second until the tail shows, holds 1.2 seconds,
  slides back and rests again. The label's own paint is hidden by a
  `RevealHold` UIGradient while the strip shows. It is also a `disclose`
  label, and its `Disclosure` panel stops the strip while it shows. Only one
  strip moves at a time in the controls. It stays still under reduced motion
  and while the text fits. `reveal` refuses `wrap`, `lines` and a middle cut.
- `lines = n` shows at most `n` lines. The text fills the width, wraps, and
  ends with an ellipsis when it needs more lines. The box hugs shorter text.
  The limit follows the text size, the line height and the vertical padding.
  `lines` cannot combine with a middle cut or a fitted text size.

To put player names or server strings into rich text, escape them with
`Facet.richText.escape(s)`. It replaces `&`, `<`, `>`, `"` and `'` with their
RichText entities. It does not filter the text; the game still uses the
platform filtering rules.

```luau
local name = "Ann <3"
UI.Text { rich = true, text = "<b>" .. Facet.richText.escape(name) .. "</b> joined" }
```

#### Text fit

`truncate = "end"` sets the native `TextTruncate.AtEnd`. `truncate = "middle"`
keeps the start and the end of the value and puts an ellipsis between them,
for example `Coastal circui…lap 14`. Use it when the end identifies the value,
such as a file name, a path or an id.

- The label is one line. It fills the width and hugs the height by default.
  `TextWrapped = true` or `RichText = true` with `truncate = "middle"` causes
  an error.
- The label measures each candidate with the engine `TextBounds` of the label
  itself, so the measurement uses the painted face and size. A cut never
  divides a UTF-8 character. When the value fits, the label shows all of it.
  When no character fits, it shows only the ellipsis.
- The label cuts the value again when the value, the width, `TextSize` or
  `FontFace` changes. It does not measure on other changes. Before the label
  has a width, it shows all of the value.

`textSize = "fit"` sets `TextScaled` and adds a `UITextSizeConstraint`. The
engine then paints the largest size that fits the box of the label. The
default box fills its parent. `textSize = { fit = { cap = size, floor = size } }`
sets the band. A size is a pixel number or a type role name. The default `cap`
is the `textRole` of the label, or `body`. The default `floor` is `caption`.
Role sizes come from the theme package and follow a theme change. Another
`textSize` value, or another key in `fit`, causes an error.

The AsyncImage loader receives `(source, resolve, reject)`. It can return a
cancellation. A superseded result cannot replace the current image. Loading and
failure stay observable. The control does not invent successful assets.
Resource lifetime uses Compose ownership and shared resources.

The Stage content callback mounts into its WorldModel. It can return a teardown
function. The third argument, `live`, is a readable boolean. It is false while
the nearest ScrollingFrame ancestor scrolls and for 0.15 seconds after, and
while less than half of the stage shows in that scroll window. Without a
ScrollingFrame ancestor it is true. Pause scene animation while `live` is
false, so a scrolling feed does not write scene properties on each frame. With
`lazy = true`, the stage builds its content when it comes within half a window
of the scroll window, so a card never scrolls in empty. It builds also while
the window scrolls, and the stages of one control set build one per frame. Its
animation stays paused until `live` is true, and the last frame stays visible.
A stage farther away than that does not build its scene. The stage sets the attributes `FacetLive` and
`FacetBuilt`. Use the `Host.Part`, `Host.Model` and other native constructors of the
same runtime. A 3D view inside a UI rectangle is not the same as 3D UI layout.

### Label

`UI.Label(spec) -> Frame` shows an icon and a title in a row. The title is the
accessible name in every presentation. The root has the `AccessibleLabel`
attribute, which follows a bound title.

- `title` is required. Its first value must be a string that is not empty. It
  can be a readable or a function of `use`. A `Title` child (a `UI.Text`)
  shows it.
- `icon` is a semantic icon name or an asset id. An `Icon` child shows it. An
  unknown semantic name causes an error.
- `presentation` is `titleAndIcon` (the default), `titleOnly` or `iconOnly`.
  Another value causes an error. Without an icon, every presentation shows the
  title only, because an empty square is worse than a word. The root has the
  `FacetPresentation` attribute with the presentation that shows.
- `iconSize` is a number of pixels or a theme metric name. The default is the
  icon size of the regular control size. `textSize` is a number of pixels or a
  type role, default `body`. `gap` is a number of pixels or a spacing step.
- `iconPosition` is `leading` (the default) or `trailing`.
- `text` and `label` cause an error. Use `UI.Text` for plain text.

### Image

`UI.Image(spec) -> ImageLabel` shows an image. `image` is an asset string and
can be bound. It can be empty. The default size is a square of the regular
control height. A native `Size` replaces it.

- `tint` sets `ImageColor3`.
- `scaleMode` is `fit`, `fill`, `crop`, `stretch`, `tile` or `slice`, and
  sets `ScaleType`. `fill` and `crop` both give `Crop`. It can be bound, but a
  bound mode cannot be `tile` or `slice`.
- `tile` requires `tileSize = { width, height }` in whole pixels above zero.
  `slice` requires `sliceCenter = { x0, y0, x1, y1 }`, the centre rectangle in
  source pixels, and takes an optional `sliceScale` above zero (default 1). A
  geometry key without its mode, or a mode without its geometry, causes an
  error.
- `resample` is `default` or `pixelated` and sets `ResampleMode`. It can be
  bound.
- `shape = "circle"` adds a `UICorner` of half the size and a square
  `UIAspectRatioConstraint`. A circle cannot use `slice`.

### badged

`UI.badged(host, value, direction?) -> Frame` puts a count or a dot on the
corner of a host, such as a Button, an icon Button or an Avatar. It returns a
Frame named `<host name>+badge` that hugs the host and takes its
`LayoutOrder`. A zero-size `Corner` frame sits at the top-right corner of the
host, or at the top-left when `direction` is `"rtl"`. It holds a Badge named
`CornerBadge`, centred on the corner. The Corner frame has no size, so the host
keeps its layout box, its hit area and its selection. `value` is a string, a
whole count (above 99 shows "99+"), `true` for a dot, or a readable of one.
`nil`, `false`, `0` and `""` show nothing. A TabView tab or a segmented Picker
option with an `icon` shows its `badge` on the corner of the icon. A text tab or
option keeps the count in its words.
The seal paints past the host by half its size, so give a host at a clipping
edge that much room.

## Themes

`themes.SCHEMA` is `facet-theme/2`. `TYPE_ROLES` and `REQUIRED_TYPE_ROLES` list
`caption`, `label`, `body`, `heading`, `title`, `control`, `strong` and
`numeral`. The `caption` role also uses the `contentSecondary` color.
If a definition sets `body` and does not set `strong`, `define` makes `strong`
from `body` with the `SemiBold` weight. If a definition sets `control` and does
not set `numeral`, `define` makes `numeral` from `control` with the `Bold`
weight. The derived role keeps the family, style, size and line height.

- `neutralPackage()` returns a mutable copy of the neutral theme package. It
  declares two palettes, `Dark` (the default) and `Light`. Both palettes pass
  the contrast gate of `define`.
- `define(definition)` derives from `base` (neutral by default) and returns
  `package?, report`. Check `report.ok` before use. An accepted theme package is
  recursively frozen. Callbacks, cycles and malformed definitions are rejected.
  A type role needs a positive size. Each `metrics.space` step needs a pixel
  size of 0 or more. A chrome shadow name must be a
  package shadow or a preset (`raised` or `overlay`). A chrome art link
  `rotation` must be 0 or 180, and its `tint` needs `r`, `g` and `b` from 0
  to 1. Each palette pair needs a
  contrast of at least 4.5:1, which includes `onSelected` (or `content`) on
  `controlSelected`.
  Color channels and semantic contrast pairs are validated. A package that
  does not declare `style.themes` gets only the first palette of its base. Thus
  a package derived from Neutral has one palette unless it declares more.
- `checkCoverage(package, needs)` returns `{ ok, covered, missing }`.
- `resolveIcon(package, name, state?)` resolves real image content. A name
  that ends in `.fill`, such as `"star.fill"`, is the filled variant. The
  package art for that name wins. Without it, the regular icon draws.
- `createStyleSheet(runtime, packageOrReadable?, options?)` returns a native
  StyleSheet that Compose owns. See the list below.
- `forDistance(package, distance)` is the ten-foot metric ladder. `"near"`
  returns the authored package (the same table). `"ten-foot"` returns a frozen
  package whose lengths are 1.5 times (`adaptive.TEN_FOOT_SCALE`): `space`,
  `targetSizes` (a 44 pixel target is 66), `iconSizes`, `strokes`, every
  `controlSizes` field, `radii` (rounded to whole pixels) and each type role
  size, so a 16 pixel `body` is 24. A `metrics.controls` value scales unless
  its name ends in `TextSize`, `Lines`, `Count`, `Duration`, `Seconds`,
  `Ratio`, `Fraction`, `Scale`, `Opacity` or `Weight`. Motion, colors, chrome
  art and art insets do not scale. Every proportion of text to its control is
  the same at both distances. The call is idempotent and reversible:
  `forDistance(far, "near")` returns the authored package. You rarely call it:
  controls and a StyleSheet apply it from the ten-foot fact. A frozen
  package's ladder is cached.
- `skin(runtime, packageOrReadable, slot, options?)` builds native control
  artwork. The options include `state`, `selected`, `target`, `label`,
  `onCaption`, `ZIndex` and injected `types`. When a state has no art of its
  own and `selected` is true, the skin uses the `selected` art before the
  `default` art. A plaque layer with `text = true` is title art: it shows
  `label` and is drawn only while `label` is not empty. It grows around the
  text by its `textInsets`, never below its own size, and stays centred on its
  edge. `onCaption(shown)` reports whether the plaque shows the label.
  A `target` that is a TextBox gets no art images, only the recipe shadow.
  Roblox draws children above their parent, so art in a TextBox would cover
  its text and placeholder.

`createStyleSheet` contract:

- Make the sheet inside a Compose owner. Parent it as a numeric child. A
  StyleLink only references the sheet. It does not parent it.
- The options are:
  - `types`: injected datatypes.
  - `theme`: the selected palette, as a name or a readable.
  - `name`: the native name.
  - `transition`: a native TweenInfo, a readable, or `false`.
  - `motionLevel`: `"normal"`, `"limited"` or `"none"`, or a readable. If you
    omit it, the sheet uses the `motionLevel` given to `Facet.controls` on the
    same runtime. Paint transitions are instant only at `"none"`; the device's
    Reduce Motion (`"limited"`) keeps them.
  - `preferredTransparency`: a number or a readable. The value multiplies the
    scrim transparency. Other rules keep their authored transparency. A value
    that is not a number has no effect. If you omit it, the sheet follows
    GuiService.
  - `hover`: a boolean or a readable. When it is `false`, the sheet leaves out
    the `:Hover` rules, so a tapped control does not keep a hover tint. Press
    paint stays. If you omit it, or the readable gives `nil`, the sheet leaves
    out hover paint while UserInputService.PreferredInput is Touch.
  - `tenFoot`: a boolean or a readable. When it is `true`, the sheet compiles
    `forDistance(package, "ten-foot")`: the ten-foot type ramp, radii and
    strokes. If you omit it, the sheet follows `adaptive.isTenFoot` of
    GuiService and UserInputService. `app.mount` passes the environment's
    `isTenFoot`. Pass `false` for a SurfaceGui or BillboardGui, whose canvas
    has its own scale, and give its controls `environment.viewingDistance =
    "near"`.
  - `contentProvider`: the ContentProvider that warms the package's art. If
    you omit it, the sheet uses the engine's ContentProvider. The first time
    the sheet applies a package, it calls `PreloadAsync` once on the content of
    every entry in `package.assets` except those marked `preload = "lazy"`,
    off the calling thread, so a panel that
    first opens later already has its art.
- Colors and opacity use native StyleRule transitions. `:Press` rules use
  `metrics.motion.press` (0.08 seconds), `:Hover` rules use
  `metrics.motion.hover` (0.15 seconds), and other rules use
  `metrics.motion.normal` (0.2 seconds). Press and hover are never slower than
  `normal`. The easing is `metrics.motion.styles.paint` (Quad Out). The theme
  StyleSheet carries the three timings as TweenInfo attributes
  (`FacetMotionNormal`, `FacetMotionPress`, `FacetMotionHover`), and each rule's
  transitions reference one of them as a `$` token, so a timing change updates
  three attributes and rewrites no rule. The engine reads the token when a
  transition starts, so a new timing applies to the next change. The three
  attributes belong to Facet: a game rule may reference them but must not write
  them, and the sheet writes a cleared or overwritten one back at once (a rule
  whose token is missing falls back to another matching rule's timing). Roblox applies the transition of the
  rule being entered, so a press arrives in the press time; its release eases
  back in the normal time, or in the hover time while the pointer is still over
  the control (the release enters `:Hover`). Native transitions retarget
  interrupted changes.
- Reduced motion or `transition = false` sets zero-duration paint. If you omit
  reduced motion, the sheet follows GuiService.
- Explicit Instance paint still overrides stylesheet paint.

A theme package contains `identity`, `style = { defaultTheme, themes }`,
`metrics`, `chrome`, `assets`, `icons` and additional
`rules = { { selector, properties } }`. A palette contains `name`, `colors` and
`extra`. The main colors are `surface`, `surfaceStrong`, `content`,
`contentStrong`, `accent`, `onAccent`, `danger`, `onDanger`, `success`,
`onSuccess`, `warning` and `onWarning`. The extras include control states,
secondary content, hairlines and opacities.

These `extra` entries are optional. A palette that does not declare them paints
as before:

- `selection` and `onSelection`: the color of an on or chosen mark and the
  color on it. The switch track and knob, the checkbox box and tick, the slider
  fill and the tab and segment underline (`facet-selection-indicator`) use
  them. Without them they are `accent` and `onAccent`. When a palette of the
  package declares `selection`, a chosen Chip and a selected `link` Button also
  use it.
- `voice`: the color of the `voice` status. Without it, it is halfway between
  `warning` and `danger`.
- `scrim`: the color of a modal backdrop. `scrimOpacity` sets how much it
  dims. Without it the backdrop is black.
- `inverseSurface` and `onInverse`: the plate and text of
  `appearance = "inverse"`. Without them they are `contentStrong` and
  `surface`.
- `tableHeader`, `tableRow` and `tableRowAlternate`: the Table header band,
  its rows and its alternate rows. Without them they are `control`, `control`
  and `controlHover`.
- `dimDisabledPlates = true`: a disabled Button fades its plate toward
  `surface` by `disabledContentOpacity`, in addition to its text. This applies
  to the standard, selected, emphasis, soft, inverse and destructive plates and
  to the Toggle indicator. Without it only the text dims.
- `artTint`: multiplies the `control`, `field` and `panel` chrome art of
  that palette, so one art set serves a light and a dark palette. Fantasy
  Parchment Candlelight darkens its parchment to 0.3 so cream text reads on
  it. Without it the art is untinted. A selected, emphasis or destructive
  plate keeps its own tint.
- `strongHairlineOpacity`: the transparency of `facet-divider-strong`. Without
  it, the strong divider is three times as visible as the hairline (0.76 with
  the neutral 0.92).

Two tags need no control. `facet-pane` paints the `surfaceStrong` fill with no
corner and no stroke, for a sidebar or a split pane. Add
`facet-divider-strong` next to `facet-divider` for a heavier rule, such as a
pane edge.

The `focus` chrome slot is the focus look that `UI.focusRing` hands to the
engine:

| Field | Meaning |
|---|---|
| `kind` | `"ring"` (the default): a stroke just outside the control. `"glow"`: a native `UIShadow` halo, which the engine paints over the control. `"nineSlice"`: the `asset` art, sliced around the control. `"brackets"`: a square stroke masked by a `UIGradient` to its two ends, like `[ ]`. |
| `color` | An RGB or a `$Role` palette token such as `"$FocusGlow"`. The default is `accent`. |
| `thickness` | The ring stroke (2) or the bracket bar (4), in pixels. |
| `size` | How far each bracket reaches along the top and bottom, in pixels (12). |
| `outset` | Pixels that art and brackets stand outside the control (0). |
| `sliceScale` | The art `SliceScale`; the asset's own value by default. |
| `blurRadius`, `transparency`, `zIndex` | The glow (24 pixels, 0.25, -1). |
| `corner` | `"square"` or `"pill"` for every control; otherwise the selected control's shape. |
| `pulse` | `true`: the look breathes slowly while it shows. Reduced motion stops it. |

The engine draws only the selection object itself and its UI components
(`UIStroke`, `UIGradient`, `UICorner`, `UIShadow`), never a child GuiObject,
so every look is one `ImageLabel` with those components. Facet Neutral uses
the default thin ring. Pixel Quest draws square brackets, Fantasy Ornate its
gold frame with a slow pulse, and Fantasy Parchment a gold ring.

A chrome slot names its art with `asset`: one asset name, or one name per
state (`default`, `hover`, `pressed`, `selected`, `disabled`). A state can also
be `{ asset, rotation, tint }`. `rotation = 180` turns the art over, so a
nine-slice frame with a centred slice rect shows its bevel pressed in. `tint`
is an RGB that multiplies the art (`ImageColor3`). When the `control` slot has
`selected` art, every skinned selected plate shows that art and never a flat
fill: a segment, a Picker row or card, a Chip, a Toggle button, a menu row and a
pill tab. The plate keeps the size of its unselected siblings, and its label is
`onSelected`. Each shipped skinned package has a selected piece. Pixel Quest
turns its wood plate over and tints it green. Fantasy Ornate turns its jewelled
selection plate over, so it sits inset in its gold trim. Fantasy Parchment turns
its parchment plate over and inks it dark brown, with a vellum label. Glossy
Touch uses its blue gel selection plate. Compact Pointer uses its pressed button
tinted blue.

The metrics also have optional entries:

- `controlSizes.xsmall = { height, paddingX, iconSize }`. Without it, each
  field is `2 * compact - regular`, and not less than 0. `define` refuses an
  `xsmall` entry that does not have all three numbers.
- `targetSizes.pointer`: a row height from 24 to `targetSizes.minimum`. Floating
  Menu and Picker menu rows use it while the input is pointer-only. `define`
  refuses a value outside that range.
- `strokes.utility`: a number of pixels. When it is more than 0, a
  `utility` Button draws a hairline outline of that width. Without it, a
  utility Button has no outline.
- `controls.shortcutHint.capStroke`: a number of pixels for the ShortcutHint
  cap outline. Without it, the outline is `strokes.hairline`. A value of 0 draws
  no outline.
- `controls.shortcutHint.capGap`: a number of pixels. `define` accepts it for
  packages that also target main. The native ShortcutHint draws each chord as
  one label, so it has no gap between caps to set.

StyleSheet rules own ordinary paint. Explicit Instance properties override
native styling intentionally. Give the same theme package readable to
`Facet.controls(runtime, { theme = package })` and to
`createStyleSheet(runtime, package)`. Mount the resulting sheet and a native
StyleLink in the target tree. See [custom themes](../guide/09-custom-themes.md)
and [skins](../guide/10-rich-skinning.md).

## Civil dates

`Facet.civilDate` is the calendar that `UI.DateTimePicker` keeps its values in.
A `CivilDate` is `{ year, month, day, hour?, minute? }` in no time zone. A
`CivilRange` is `{ start?, finish? }`.

- Arithmetic: `isLeap(year)`, `daysIn(year, month)`, `toDays(d)` and
  `fromDays(n)` (days from 1970-01-01), `dateOf(d)` (the date without its
  time), `addDays(d, n)`, `addMonths(d, n)`, `compare(a, b)` (by date),
  `same(a, b)` (every field), `weekday(d)` (1 is Sunday),
  `monthGrid(year, month, weekStart)` (six weeks of dates),
  `within(d, min?, max?)`, `clampRange(range, min?, max?)` and
  `problem(d, withTime?)`. `addMonths` clamps the day: January 31 plus one
  month is the last day of February. `clampRange` returns `nil` when the range
  is fully outside the bounds. `problem` returns why a value is not a date, or
  `nil`.
- Words: `format(d, locale?)`, `formatTime(d, hourCycle)` and
  `parse(text, locale?, withTime?)`. They use the numeric order of the locale.
  `parse` returns two values, `(date?, why?)`. Test the date before you use it.
  A year has four digits. On a 12-hour clock, an hour from 1 to 12 needs AM or
  PM. `ENGLISH` is the default locale: `months`, `weekdays` (Sunday first),
  `order` (`mdy`, `dmy` or `ymd`), `separator` and `hourCycle`.
- Instants: `fromUnix(seconds, offsetMinutes)` and
  `toUnix(date, offsetMinutes)` always name their offset. There is no zone
  database. Convert a zone with daylight time to a fixed offset yourself.
  `systemClock(offsetMinutes?)` returns the default clock: the local date and
  time of the player, or the engine clock at the offset that you name.

```luau
local civil = Facet.civilDate
local start = { year = 2026, month = 2, day = 27 }
print(civil.format(civil.addDays(start, 3))) -- "03/02/2026"
local date, why = civil.parse("02/30/2026")
if date == nil then
    print(why)
end
```

## Path shapes

`Facet.pathShapes` makes the normalized points that `UI.Path` strokes. The points
are in a unit box, with the angle 0 at 12 o'clock and positive angles clockwise.

- `pathShapes.arc(startDeg, sweepDeg, { segments?, radius? })` makes a circular
  arc.
- `pathShapes.ring({ radius? })` makes a full circle from four exact quarters.
- `pathShapes.needle(angleDeg, { innerRadius?, radius? })` makes one straight
  segment from `innerRadius` to `radius` at `angleDeg`.
- `pathShapes.MAX_CONTROL_POINTS` is 100, the limit of the engine `Path2D`.
  A shape that needs more points is refused when you make it.

```luau
local speed = Compose.cell(0.5)
UI.Path "Needle" {
	points = function(use)
		return Facet.pathShapes.needle(use(speed) * 270 - 135, { innerRadius = 0.2 })
	end,
	role = "accent",
	thickness = 3,
	width = 64,
}
```

## Adaptive environment

### Facet.adaptive

`Facet.adaptive` holds pure decisions. They take numbers and never a device
name.

| Call | Result |
|---|---|
| `sizeClass(width)` | `"compact"` below 600, `"regular"` below 1000, else `"wide"`. A nil, NaN or negative width gives `"compact"`. |
| `heightClass(height)` | `"short"` below 600, `"medium"` below 1000, else `"tall"`. |
| `orientationFor(width, height)` | `"landscape"`, `"portrait"` or `"square"`. This is a shape fact. |
| `axisFor(width, { stackAbove? })` | `"x"` at or above `stackAbove` (default 600), else `"y"`. |
| `columnsFor(available, minColumnWidth, gap?)` | The number of columns of at least `minColumnWidth` that fit, at least 1. |
| `sizeClassAtLeast(value, target)` | `true` when `value` ranks at or above `target` in `compact < regular < wide`. |
| `isTenFoot({ displaySize?, touch?, mouse?, tenFootInterface?, viewingDistance? })` | `viewingDistance` `"ten-foot"` or `"near"` decides. Otherwise `true` for `GuiService:IsTenFootInterface()` or a `Large` display, when there is no touch and no mouse. A large desk monitor with a mouse is near, and so is Studio, which reports `IsTenFootInterface()` true on a desktop. |
| `overscanInsets(width, height)` | The console overscan margins for a viewport: `{ top, left, bottom, right }` of 60/1080 of the height and 90/1920 of the width, rounded. |
| `TEN_FOOT_SCALE` | 1.5, the ten-foot metric factor. |
| `navPlacement({ sizeClass, heightClass, primary?, displaySize?, tenFoot? })` | The app navigation home, in this order: ten-foot `"topBar"`; compact width `"bottomBar"`; short height `"bottomBarCompact"`; a pointer `"sidebar"`; a gamepad on a `Small` display `"bottomBar"`; otherwise (a roomy touch screen, a gamepad on a larger display) `"topBar"`. |
| `BREAKPOINTS`, `HEIGHT_BREAKPOINTS` | The same table: `{ regular = 600, wide = 1000 }`. |
| `DEFAULT_STACK_ABOVE` | 600. |

### Facet.gamepadContention

`Facet.gamepadContention` reports whether the engine's legacy player scripts
hold input that the controls need. Every probe is guarded: without an engine
it answers `false` and never throws. Nothing warns on its own; call them from
a doctor check or when an input looks dead.

| Call | Result |
|---|---|
| `legacyStackActive()` | `true` while ContextActionService binds `jumpAction`, which takes gamepad ButtonA before a selected control. |
| `cameraKeysContended(boundActionInfo?)` | `true` while any ContextActionService binding holds an arrow key (the camera's `RbxCameraKeypress` holds Left and Right). It reads a different binding than `legacyStackActive`. |
| `traversalKeyContended()` | `true` while the CoreGui players list is enabled, which takes Tab. |
| `iasPlayerScriptsActive(player?, waitSeconds?)` | `true` when the player has the engine's default `InputContexts` (`CharacterContext`, `CameraContext` or `VehicleContext`), which exist only when `Workspace.PlayerScriptsUseInputActionSystem` is on. |
| `disableLegacyControls(playerModuleParent?, player?)` | For a UI-only place only: it turns off avatar input. Returns `true, "inert: IAS owns PlayerScripts"` when the player scripts are on the Input Action System, `true, "disabled"` after `PlayerModule:GetControls():Disable()`, `true, "unbound"` when it removed `jumpAction`, else `false, "unavailable"`. |
| `freedJumpAction(before, after)` | The pure verdict of an unbind: `jumpAction` was bound before and is gone after. |
| `describeContention()` | The whole explanation as one string, for a log line. |

The fix for a game with an avatar is `Workspace.PlayerScriptsUseInputActionSystem`.
No script can read or set it, but a Rojo project file can declare it. No
`InputContext` priority outranks a sinking ContextActionService binding.

### focusRing

`UI.focusRing(playerGui) -> Frame` sets `PlayerGui.SelectionImageObject` to
one selection object that the engine draws on the selected control, so the
engine owns where the focus is and when it moves. The theme package supplies
the look in its `chrome.focus` recipe (see [Themes](#themes)). The look shows
after keyboard or gamepad input, or when the effective input is a gamepad, and
hides after mouse or touch input. Call it inside a component and put the
returned Frame (an invisible paint probe) in the ScreenGui that holds the
StyleSheet link. `app.mount` does this for you; `app({ focusRing = false })`
leaves the PlayerGui's selection object to the game. Several apps share the one
engine selection object: the latest mounted look is drawn, unmounting gives
the previous look back, and the last unmount restores the object the game had
before.

The look takes the shape of the selected control: the control's own
`UICorner` (a `corners = "pill"` Button, a Slider thumb), a pill for a Chip, a
circle for a circle Button, and otherwise the theme's `radii.control`. A
recipe with `corner = "square"` or `corner = "pill"` keeps that shape
everywhere. The colour is the recipe `color`, or `accent`. A selected object
with a number attribute `FacetFocusHeight` gets a look that many times its own
height, measured down from its top edge (a Card uses this to ring the whole
card from its body). A selected object with a string attribute
`FacetFocusPart` (a path of child names such as `"Track/Thumb"`) gets the look
on that part instead, sized to it and shaped by its `UICorner`; a Slider uses
this so the look stays on its thumb while the whole Slider is the stop. The
part's place and size are kept as shares of the selected object, so a parent
`UIScale` moves and sizes the look with the part. A part that is itself rotated
relative to the selected object gets an unrotated look around its unrotated box.
Known limit: when the selected object itself is rotated, the engine turns the
look with it about the look's own centre, so a look on a part off the object's
centre sits beside the part.

At ten feet the look is larger: a ring is twice as thick, brackets, art
outsets and slices are 1.5 times, a glow blurs 1.6 times and is more opaque,
and the whole look stands 3 pixels off the control, so it lifts clear of the
control's own edge. A ring is drawn just outside the control at every distance,
so it never covers a label that runs to the control's edge.

A keyboard or gamepad selection inside a ScrollingFrame scrolls it so the
selected control and some room on each side are in view, so the engine can
always reach the next control (the pre-0.12 keep-visible rule). The room is
the control's height, but never more than half the space the control leaves in
the window, so a tall control stays fully in view. Facet does this for every
app that observes the selection, with or without `focusRing`; it reads
`UserInputService:GetLastInputType()`, so a mouse or touch selection does not
scroll.

A value control is one stop; its look is drawn on its value part through
`FacetFocusPart` (a Slider's thumb or track, a range Slider's adjusted
handle). Each segment of a segmented Picker is its own selected object. A game control that needs its own look
sets `SelectionImageObject` on that control; the engine then draws that
object for it.

### focusSection

`UI.focusSection(group, options?)` makes the GuiObject `group` an entry
region for directional navigation. Call it inside a component or a Compose
owner; it stops when the owner ends. It reads and writes
`GuiService.SelectedObject` and adds no input binding or focus stop.

| Option | Effect |
|---|---|
| `entry` | Where the selection lands when it enters `group` from outside. `"restore"` (the default): the item last selected there, while it is still selectable and visible. `"first"`: the first selectable item in layout order, every time. `"nearest"`: the engine's own choice. |
| `preferred` | The name, or a relative path such as `"Hero/Play"`, of a descendant. On a `"restore"` entry with nothing remembered, it wins. |
| `focusOnAppear` | `true` selects the first item in layout order when the section appears; a name or path selects that descendant. It acts only while something is already selected (keyboard or gamepad navigation), so a touch or mouse player gets no selection ring. |
| `returnFocus` | `true` remembers the selected item when the section appears and selects it again when the section goes away, if it is still selectable and the selection was inside the section or gone. |

An unknown option or `entry` causes an error. A branch that shows a detail
over a list uses `focusOnAppear` and `returnFocus` together:

```luau
local open = Compose.cell(false)
Compose.show(open, function()
	local detail = UI.VStack "Detail" {
		UI.Button "Back" { label = "Back", onActivate = function() open:set(false) end },
	}
	UI.focusSection(detail, { focusOnAppear = "Back", returnFocus = true })
	return detail
end)
```

### focusQuery

`UI.focusQuery(from?) -> FocusQuery` says what a D-pad or arrow move from
`from` (default: the selected object) selects and why, without moving. Each of
`Up`, `Down`, `Left`, `Right` is `{ target, rule }`. `rule` is `"capture"` (a
value control keeps that axis, whether or not it is selected yet), `"link"` (a
`NextSelection*` link to a shown, selectable object; a link to a hidden or
unselectable one is ignored), `"beam"`
(Facet's model of the engine's own choice, measured in Studio: a candidate is
ahead when its near edge is past the control's centre and, unless it overlaps
on the cross axis, it ends past the control's leading edge; candidates that
overlap on the cross axis come first, nearest edge first; then candidates whose
centre lies within 45 degrees of the move from the middle of the leading edge,
by the smallest centre offset plus 0.028 times the distance along the move;
then the rest, by centre offset over the distance along the move to the power
0.15),
`"stop"` (a `SelectionGroup` with `SelectionBehavior` `Stop`) or `"none"`. The
candidates are the ones Tab visits plus every selectable scroll container, minus zero-size objects, objects outside
the screen, and children of a scroll container that does not hold `from` where
its window is clipped or off the screen; a selectable scrolling frame ranks by its own rectangle like a
control, and the query reports the control it passes the selection to; enclosing `SelectionGroup`s are searched from
the innermost out, and the first one whose `SelectionBehavior` is `Stop` in
that direction ends the search. The engine still
performs every move; tests and tools use the query to check navigation without
a device. The query does no per-frame work.

### responder

`UI.responder(root, options?) -> Responder` declares how the surface `root`
(a GuiObject or a LayerCollector) shares the keyboard with the game. Call it
inside a component or a Compose owner; it stops when the owner ends. It works
on the engine selection: the surface is engaged while the selection is inside
it.

| Option | Effect |
|---|---|
| `passive` | `true` (the default): a HUD over live gameplay. At rest it binds nothing. Tab is not bound while nothing is selected, a D-pad press does not enter it, and Space reaches the game. It engages when the selection enters it, when the player taps it (the tapped control takes the selection) and on `engage()`. It resigns on a tap outside it, on ButtonB or Escape that no control takes, on `resign()`, and when the selection moves to another surface. `false`: the surface is always engaged, like any screen without a responder. |
| `gameplayGuard` | `true` (the default): while a passive surface is engaged, a sinking `FacetGameplayGuard` context at priority 3000 takes Space, so the avatar does not jump while the UI has the keyboard. `false`: no guard, and a Button inside `root` binds only Return, so Space reaches the game (a word game over the world). |
| `traversalWrap` | `true` (the default): Tab and Shift+Tab wrap at the ends of the surface. `false`: they stop at the last and the first control. |

The `Responder` has `state`, a readable of `"passive"` or `"engaged"`, and
`engage()` and `resign()`. `engage()` binds Tab and the guard; the first Tab
then enters the surface. `resign()` clears a selection inside `root`. On a
passive-only screen a gamepad player needs `engage()`, for example from a
menu button of the game. An unknown option or a value that is not a boolean
causes an error.

```luau
local hud = UI.Screen "Hud" { UI.Button "Map" { label = "Map" } }
local responder = UI.responder(hud)
-- the game opens its menu with a key of its own
responder.engage()
```

### adjustable

`UI.adjustable(node, options)` gives a game control the keyboard and gamepad
adjustment of the Slider and the Stepper. `UI.adjustable` makes `node` the
selection stop; give it no selectable descendants. While the selection is on
`node`, Comma and Period and L1 and R1 call `onAdjust(-1)` and `onAdjust(1)`,
and the arrows and the left stick on `axis` do too. The other axis keeps
moving the selection. Call it inside a component or a Compose owner; it stops
when the owner ends.

| Option | Effect |
|---|---|
| `onAdjust(direction)` | Required. `direction` is -1 or 1. |
| `axis` | `"horizontal"` (the default) takes Left and Right, `"vertical"` takes Up and Down, `"none"` takes no arrows and leaves only the shoulders. |
| `repeats` | `true`: a held key or button adjusts again after 0.4 seconds, then every 0.1 seconds, like the built-in value controls. The default is `false`: one step for each press. |
| `canAdjust(direction, use?)` | Optional. `false` makes a press of that arrow do nothing, for example at a limit; the arrow still belongs to the node while it is selected. |
| `enabled`, `disabled`, `busy` | Values or readables. A disabled control takes no keys. |

The actions have the priority of the built-in value controls, so a higher
priority gameplay context still wins, and a held repeat stops when it does.
An unknown `axis` causes an error.

```luau
local angle = Compose.cell(0)
local function turn(direction: number)
	angle:set(angle:peek() + direction * 15)
end
local row = UI.HStack "Turn" {
	UI.Button "Left" { label = "Turn left", onActivate = function() turn(-1) end },
	UI.Button "Right" { label = "Turn right", onActivate = function() turn(1) end },
}
UI.adjustable(row, { onAdjust = turn, axis = "none", repeats = true })
```

### feedback

`UI.feedback(kind)` plays one of the named feedback kinds at once. See
[Haptics](#haptics) for the kinds and their engine effects.

```luau
local function onPurchaseConfirmed(granted: boolean)
	UI.feedback(if granted then "success" else "error")
end
onPurchaseConfirmed(true)
```

### draggable and dropTarget

`UI.draggable(source, spec)` lets a player pick up the GuiObject `source`, and
`UI.dropTarget(target, spec)` lets the GuiObject `target` receive it. Call both
inside a component or a Compose owner; they stop when the owner ends. Every
input ends in the same drop:

- Pointer: press the source and move it 6 pixels. A release before that is a
  click, and the source's own activation still happens.
- Touch: a finger that moves first scrolls. Hold the finger still until the
  engine's long press (`TouchLongPress`) to pick the source up; the
  ScrollingFrame under it stops scrolling until the finger lifts.
- While the source is held, an inert copy of it (`DragGhost`) follows the
  pointer at the root of its screen, and the target under the pointer is the
  aim. Release to drop there. The press that became a drag never activates a
  Facet Button, so a drag of a card never opens it.
- Keyboard and gamepad: select the source and press Return or A to pick it up.
  Move the selection into a target and press Return or A to drop. Escape or B
  puts the source back. On a Facet Button source or target this is the
  Button's own activation, so its `onActivate` also runs.
- `armOnTap = true`: a touch tap on the source picks it up, the list under it
  still scrolls, and a tap on a target drops it.

While the source is held it has the `facet-drag-held` tag and the
`FacetDragHeld` attribute. Every theme hides its text and icons, so its plate
stays as the empty slot until the drop lands or the source goes back.

```lua
UI.draggable(card, { payload = { kind = "sponsor", id = 7 } })
UI.dropTarget(slot, {
	accepts = function(payload)
		if payload.kind ~= "sponsor" then
			return false, "WRONG_KIND"
		end
		return true
	end,
	onDrop = function(payload, info)
		place(payload, info.target)
	end,
})
```

`draggable` spec:

- `payload`: required. The value every target receives. A function is called
  with the source at pickup.
- `enabled`: a boolean or a readable. While false the source cannot be picked
  up, and it stays selectable and activatable.
- `armOnTap`: a touch tap picks the source up (above). Default `false`.

`dropTarget` spec:

- `onDrop(payload, info)`: required. `info` is `{ source, target, mode }`,
  where `mode` is `"pointer"` or `"armed"`.
- `accepts(payload) -> (legal, reason?)`: the game's rule. Without it the
  target accepts everything. A refused drop calls `onReject(payload, reason)`
  and puts the source back.
- `onEnter(payload)` and `onLeave(payload)`: called once each time the aim
  enters or leaves the target. A nested target wins over the one around it.

`UI.focusSection(group, { focusOnAppear?, returnFocus? })` also says where the
selection goes when a branch appears and leaves. Call it in the component that
builds the branch, such as the content of a `Compose.show` or a detail page.

- `focusOnAppear = true` selects the first selectable item in `group`
  (`GuiService:Select(group)`) when `group` arrives in a ScreenGui.
  `focusOnAppear = "Save"` selects the descendant with that name. The claim
  happens only while the player navigates by selection: something is
  selected, or the preferred input is a gamepad. A pointer or touch player
  gets no selection.
- `returnFocus = true` remembers what was selected before the claim. When the
  owner ends and the selection is inside `group` or gone, the selection
  returns there. When that item has left the screen, the first selectable item
  of the screen gets the selection, so the ring never goes blank. A selection
  that the player moved outside `group` stays.

An unknown option causes an error.

### environment

`UI.environment(source?) -> Environment` returns readables of the engine facts
that a screen adapts to. Call it inside a component or a Compose owner. The
readables stop when the owner ends. `source` is a `GuiBase2d`, whose
`AbsoluteSize` in layout units (divided by the scale of its `UIScale`
ancestors) is the viewport, or a `Camera`, whose `ViewportSize` is the
viewport. Without a source it reads the `ViewportSize` of the workspace camera.
A viewport smaller than 2 by 2 pixels is an engine placeholder. The
environment keeps the last real size.

| Field | Source and value |
|---|---|
| `viewportSize`, `viewportWidth`, `viewportHeight` | The viewport: layout units for a `GuiBase2d` source, pixels for a camera. |
| `sizeClass`, `heightClass`, `orientation`, `axis` | `adaptive` applied to the viewport. On a ten-foot display (`isTenFoot`) `sizeClass` stops at `"regular"` and `heightClass` at `"medium"`, so a television never takes the densest arrangement. |
| `isCompact`, `isRegular`, `isWide`, `isRegularOrWider`, `isShort`, `isTall`, `isLandscape` | Booleans. `isRegular` is the middle class only. Use `isRegularOrWider` for "not compact". |
| `atLeast(target)` | A new boolean readable for `sizeClassAtLeast(sizeClass, target)`. |
| `interactionClasses` | `{ primary, pointer, touch, gamepad, keyboard }` from `UserInputService.PreferredInput` and the `MouseEnabled`, `TouchEnabled`, `GamepadEnabled` and `KeyboardEnabled` capabilities. `primary` is `"pointer"`, `"touch"` or `"gamepad"`. Before a player uses touch or a gamepad, a device with touch and no mouse is `"touch"`. The primary class is always in the set. A press of modifier keys alone (Shift, Control, Alt, Meta or Super, with no other key or mouse button down) does not move Facet to keyboard and mouse, though the engine's `PreferredInput` changes; the next other key, mouse button, mouse movement or wheel does. Every control, and the theme StyleSheet's hover paint, reads `PreferredInput` through this rule. |
| `effectiveInput` | `primary` as `"KeyboardAndMouse"`, `"Touch"` or `"Gamepad"`. |
| `displaySize` | The name of `GuiService.ViewportDisplaySize`: `"Small"`, `"Medium"` or `"Large"`. |
| `isTenFoot` | `adaptive.isTenFoot` of the `viewingDistance` option, the display size, the touch and mouse capabilities and `GuiService:IsTenFootInterface()`. A gamepad alone is not ten-foot. |
| `viewingDistanceSource` | `"authored"` when the `viewingDistance` option is `"near"` or `"ten-foot"`, else `"inferred"`. |
| `metricScale` | `adaptive.TEN_FOOT_SCALE` (1.5) at ten feet, else 1. It is the factor of the ten-foot metric ladder (see [Themes](#themes)). |
| `overscanInsets` | `{ top, left, bottom, right }` in pixels. At ten feet it is the console profile as a proportion of the viewport (`adaptive.overscanInsets`): 60/1080 of the height and 90/1920 of the width, so 1920 by 1080 reserves 60 and 90. Near, it is zero. The `overscanInsets` option wins; `"none"` is zero. `UI.Screen` adds it to its padding. |
| `navPlacement` | `adaptive.navPlacement` of the classes, the primary input, the display size and `isTenFoot`. |
| `safeInsets` | `{ top, left, bottom, right }` from `GuiService:GetGuiInset()`. It updates when the viewport or `GuiService.TopbarInset` changes. |
| `preferredTextSize` | The name of `GuiService.PreferredTextSize`, for example `"Medium"` or `"Largest"`. The engine applies the text size. |
| `motionLevel` | The stronger of the factory `motionLevel` option and the device level (`"limited"` when `GuiService.ReducedMotionEnabled` is true, otherwise `"normal"`). |
| `reducedMotion` | `true` when `motionLevel` is not `"normal"`. |

```luau
local function Apps(tabs, selection)
	local env = UI.environment()
	return UI.TabView "Apps" {
		tabs = tabs,
		selection = selection,
		railWidth = function(use)
			return if Facet.adaptive.sizeClassAtLeast(use(env.sizeClass), "wide") then 176 else 148
		end,
	}
end
```

For a choice that depends on the space of one container, observe the
`AbsoluteSize` of that container. The environment describes the viewport.

### worldAnchor

`UI.worldAnchor(options) -> { anchor, dispose }` projects a world object to a
screen anchor for a `RadialMenu` `anchor` or a marker. It reads the camera on
each `RunService.Heartbeat`. It creates no Instances.

| Option | Meaning and default |
|---|---|
| `target` | Required. A `BasePart`, a `Model` or a `Player`, or a readable of one. A `Player` resolves its current `Character`. A nil value makes the anchor invisible until the target comes back. |
| `padding` | A fraction from 0 to 1 of the measured radius. The default is 0.15. |
| `offscreen` | `"hide"` (the default) or `"retain"`. `"retain"` projects the center for a marker, also in a direction past the viewport for a target behind the camera. A retained anchor has `onscreen` and `clearance = 0`. |
| `occlusion` | `false` by default. When `true`, one `Workspace:Raycast` from the camera to the target center hides a target behind another object. |
| `camera` | A `Camera` or a readable of one. The default is the workspace camera. |

`anchor` is a readable `{ x, y, clearance, visible, onscreen?, occluded? }` in
viewport pixels. `x` and `y` are the center of the projected bounding box.
`clearance` encloses the eight projected corners, times `1 + padding`. A
missing, removed, empty, offscreen or near-plane target has `visible = false`,
and an open `RadialMenu` closes. An unknown option, a padding out of range and
a missing target are errors before the frame hook starts. `dispose()` sets
`visible = false` and disconnects the hook. The owner that creates the binding
also disposes it.

The game owns the `ProximityPrompt`, the proximity rules and the server checks.
Open the menu from the prompt:

```luau
local function CrateActions(crate, prompt, actions)
	local binding = UI.worldAnchor({ target = crate })
	local open = Compose.cell(false)
	local triggered = prompt.Triggered:Connect(function()
		open:set(true)
	end)
	Compose.cleanup(function()
		triggered:Disconnect()
	end)
	return UI.RadialMenu "CrateActions" {
		items = actions,
		anchor = binding.anchor,
		isPresented = open,
		launcher = false,
	}
end
```

## Recipes

`Facet.recipes.arithmetic.parse(text)` returns a finite number or `nil` for
any value. Give it to a number field as `parse`. It accepts `+`, `-`, `*`, `/`,
parentheses, the typographic signs `×`, `÷` and `−`, and blanks. It refuses a
division by zero, an exponent, a hex number, more than 256 characters and more
than 32 levels of nesting. It never compiles the text.

## Migrating from 0.11

The 0.11 screen-anchored composition maps to these 0.12 calls:

| 0.11 | 0.12 |
|---|---|
| `UI.Composition { groups = Facet.composition.HUD_GROUPS, arrangements = { Facet.composition.HUD } }` | `UI.Composition {}`. The three HUD lanes and nine zones are the only layout. |
| `UI.Region { group = "topRight", ... }` | `UI.Region { zone = "topRight", ... }`. The nine zone names are the same. |
| the `topbar` group with `rootPolicy = "bandSafeContent"` | `zone = "topbar"`. The composition uses a native `TopbarSafeInsets` ScreenGui. |
| `rank`, `mayDrop`, forms as children, richest first | The same. |
| `holdsLane` | Always on. Each lane reserves its third of the width. |
| `resolution.unshown`, `simplified` | The `form` cell of each region: 0 is hidden, 2 or more is simplified. |
| `recover`, `expand`, `dismissButton` | Removed. Make a simplified form a Button that opens the full content, for example in a Sheet. |
| `floor`, `sizing`, `weight`, `mayScroll`, `reserved`, `exclusions`, `maxMeasure`, spans, custom arrangements | Removed. Use native layout inside a form. Put chrome outside the composition, or give the composition a native `Size` and `Position`. |
| `UI.Anchor` with `anchor` and offsets on each child | A native Frame with `AnchorPoint` and `Position`, or a one-region `UI.Composition`. |
| `Facet.composition.resolve` | Removed. The decision runs on the measured native sizes. |

## Native targets and boundaries

Use the ordinary Compose Roblox constructors to mount:

- a ScreenGui into PlayerGui,
- a BillboardGui into an applicable world target,
- a SurfaceGui onto a part.

The native safe-area and sizing properties belong to those targets. World
surfaces stay flat two-dimensional UI. Facet does not supply ray, hand or gaze
input, or a VR layout mode.

Engine geometry settles asynchronously. When a control policy needs
measurements, observe the native bounds. Do not add a competing general solver.
Do not assume final text or layout bounds synchronously after construction.

The supported import boundary is the Facet root table and the Compose exports
that you can reach from it. Control implementation modules are private. The
vendored Compose tree is a generated, read-only snapshot. Make changes upstream
and synchronize them through the repository tooling.
