# Facet API

Facet supplies controls over the Compose Roblox runtime. Compose constructs and owns the native tree; Roblox provides layout, text editing, scrolling, selection and styling. This reference describes the `0.12.0` surface.

## Public entry points

| Export | Contract |
|---|---|
| `VERSION` | Package version string. |
| `Compose` | The pinned Compose core module, by reference. Use its cells, formulas, owners and structural operations directly. |
| `Roblox` | The pinned Compose Roblox module, by reference. `createRuntime(engine?)` creates the native runtime; `createHost(engine?)` creates its host. |
| `controls(runtime, options?)` | Returns the control constructor table for that native runtime. |
| `themes` | Theme package definitions, native StyleSheet compilation, icons and skins. |

Exported Luau types include `Controls`, `ControlOptions`, `ThemePackage`, and the control-specific `Props` and `Spec` contracts. `Cell<T>`, `Readable<T>`, `Runtime` and `Owner` reference Compose's types directly. Collection, menu and picker contracts preserve item and value types through callbacks. Native properties use Roblox's property types; for example, `Size` accepts a `UDim2` or a reactive source of one.

The pinned Luau solver sometimes needs explicit types for reactive `use` parameters, content factories returning `Instance` or `GuiObject`, and native anchors. Literal options may need singleton annotations such as `presentation = "number" :: "number"`; these annotations preserve the contract without using `any`.

Native Instance properties also accept `Compose.static(instance)`. The pinned Compose release types this marker's payload as `unknown`, so Luau cannot check the wrapped Instance's class. Ordinary property values and reactive sources retain their native types.

Run `python3 tools/check_types.py` to check Facet's runtime source and the positive and compile-fail public API witnesses. The checker uses pinned Roblox definitions and reports vendor diagnostics separately; it does not treat a `--!strict` directive alone as proof of a typed API.

There is no Facet application, mounting service, render target, solver, reactor or scene object. The caller owns native targets and calls `runtime.mount`, `runtime.mountFragment`, `runtime.decorate` and `runtime:dispose` directly. `decorate` applies properties and events only; mount native children with `mount` or `mountFragment`. A mount's returned stop function ends that mount; dispose the mounts before disposing the runtime.

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

## Constructor contract

`UI.Button(spec)` and `UI.Button("Name")(spec)` are equivalent named construction forms. Every constructor returns a native Instance. `ref = function(instance) ... end` receives that root. Construct controls inside a Compose owner, normally the component passed to `runtime.mount`.

Control-specific options use lower camel case. Native properties retain Roblox names: `Size`, `Position`, `AutomaticSize`, `LayoutOrder`, `Visible`, `TextSize`, and so on. Native events, Compose property/event keys, `Attributes` and numeric children are forwarded to the host. Add native tags with `node:AddTag(name)`. Unsupported control options fail instead of becoming inert metadata.

Readables and `function(use)` bodies bind reactive properties. State belongs to the caller. Input value controls write a writable cell when the corresponding callback is absent. Supplying `onChange` or `onToggle` makes the callback a request: update the model there to accept it. Navigation controls document their own write-then-notify behavior below.

`controls` accepts a `theme` package or readable for metrics, artwork and icon resolution; `reducedMotion` and `icons` may also be reactive. This does not install paint: parent a `createStyleSheet` result and its StyleLink in the native tree, using the same package source. Optional `services`, `types`, `inputParent` and `overlayParent` supply native dependencies or placement targets; ordinary Roblox consumers use ambient services and datatypes. The supplied runtime must use the Compose Roblox host.

## Actions and input

### Button

`label`, `onActivate`, `enabled`, `disabled` and `busy` define the action. Disabled and busy buttons cannot activate. Optional `repeatDelay` and `repeatInterval` default to `0.4` and `0.1` seconds. `shortcut` supplies a key code and optional modifiers; `dialogAction` is `default` or `cancel`.

Presentation options: `appearance`, `controlSize` (`compact`, `regular`, `large`), `role`, `selected`, `corners` (`pill`, `square`), `shape` (`rect`, `circle`), `icon`, `trailingIcon`, `image`, `imageAspectRatio`, `imageFraming` (`fit`, `crop`), `subtitle`, `row = { title, description }`, `name`, `hint`, `compactLabel` and `pop`. Image aspect ratio defaults to `16/9`. `compactLabel` is an alternate string/readable used when a plain text button cannot fit its full label; it does not apply to icon, image or subtitle buttons. Pointer callbacks are `onPointerDown`, `onPointerUp` and `onPointerCancel`.

### Toggle

`value` is a boolean source. `onChange(next)` requests a new value; without it the writable cell is updated. `presentation` is `switch`, `checkbox` or `button`. `mixed` is supported by checkbox presentation. `indicatorPosition` is `leading` or `trailing`. Label, row, hint, enabled and common button styling apply.

### TextInput

`value` is the string model. Roblox TextBox owns editing, IME, caret, selection and focus. `onChange(text)` handles user edits; external model updates do not emit it. `onCommit(text, reason)` receives `submit` or `focusLost`; `onCancel` observes cancellation and restoration of the edit's initial value.

`presentation` is `plain`, `search` or `number`. Number presentation additionally uses writable `numericValue`, `min`, `max`, `parse` and `format`. `validate(proposed)` returns accepted text or `nil` to reject it. `maxLength` counts UTF-8 characters. Additional options are `placeholder`, `multiline`, `invalid`, `enabled`, `disabled`, `clearButton` and `clearButtonMode` (`never`, `always`, `whileEditing`, `unlessEditing`). Native TextBox properties remain available.

### Stepper and Slider

Both take numeric `value`, `min` (default `0`), `max` (default `1`), `step`, `format`, `onChange`, `enabled` and `label`. The maximum must exceed the minimum; a specified step must be positive. Stepper defaults to step `1`; Slider defaults to continuous values.

Slider defaults to an inline track and value readout, with optional label. Its default native `AutomaticSize.Y` preserves the authored width while fitting the control height; `row` uses a stacked title/description and track. Slider additionally supports `onCommit(value)`, `tapToPosition` (default true), `thumbImage`, `trackImage` and `row`. Dragging uses native drag detection. Keyboard/gamepad adjustment uses the control's input actions.

### Rating and LevelPicker

Both take numeric `value`, positive integer `count` (default `5`), `allowZero` (default true), `readOnly`, `enabled` and `onChange`. Rating supports `glyphs = { filled, empty }` and `starSize`. LevelPicker supports `segment` (`bar`, `glyph`, `image`), `segmentSize`, `glyphs`, `images` and `tint` filled/empty pairs. Named sizes are `small` (20), `medium` (28) and `large` (36).

### Chip and ShortcutHint

Chip takes `label` and either boolean `selected` or `onRemove`. `onToggle(next)` is controlled. Removal options are `removeLabel`, `removeFocusFallback`, and native `leading`/`trailing` children.

ShortcutHint takes `keys = { { "Ctrl", "K" } }` or an `action` InputAction, plus optional `separator` and `controlSize`. The default separator is ` / `.

## Menus and navigation

### Menu and SplitButton

Menu takes an `items` array/readable, optional `label`, `icon`, writable `isPresented`, and `enabled`. Items have stable `id`, `label`, optional `icon`, `enabled`, `hidden`, `children` and `onSelect`. Checked and selected items bind their writable state. Native input actions provide opening and Back behavior; nested menus preserve the menu's control-specific navigation.

SplitButton combines a primary `label`/`onActivate` action with the menu's secondary `items`. Use it when the secondary operations supplement one clear primary action.

### Picker

Required: writable `selected` and `options`, where each option has `value`, `label`, and optional `id`, `icon` and `enabled`. Options may be a plain array or readable. Styles are `automatic`, `segmented`, `inline`, `radioGroup`, `navigationLink` and `menu`. Automatic follows native PreferredInput: a supplied `query` uses navigation-link presentation; keyboard/mouse and touch use menu; other input uses segmented for at most four options and inline for larger sets.

`onChanging(next, previous)` can veto with `false`. The control writes `selected`, then calls `onChange(next)`. Optional writable `query` filters labels. Other options include `label`, `placeholder`, `axis`, `sizing`, `iconOnly`, `textSize`, `valueAlignment`, `isPresented` and `enabled`.

### ComboBox

Requires writable string `value`, writable string `text`, options and an `acceptCustom` validator. The control combines editable search, option selection and explicit custom-value acceptance. Keep the accepted value and in-progress text as separate model cells.

### TabView

Requires writable `selection` naming a declared tab and `tabs` containing unique `{ id, label, content }` entries. Tabs may be a plain array or readable. `content` is a factory returning native content. Visited content is retained through Compose LayerStack.

Use `style = "sidebarAdaptable"` for peer destinations: the control chooses a sidebar on a sufficiently wide native viewport and a bottom bar otherwise. `placement` makes an explicit choice. `railWidth`, `sidebarPreference`, `sections`, accessories and `customization = { order, hidden }` refine presentation. Required tabs cannot be hidden. `onChange(id)` reports user selection; programmatic selection changes do not masquerade as user input. Scroll/focus restoration and shoulder navigation belong to the control. Native fades accept direct Compose tween options such as `transition = { seconds = 0.18, ease = Compose.easing.outQuad }`, or `false` to disable motion; named Facet transition presets do not exist.

### NavigationStack

Requires writable `path`, `root`, and `destinations`. The path is an array of `{ id, value }` entries. `root` and each `destinations[id]` are `{ title, content }`; destination content receives the entry. Append an entry to push; remove the last entry to pop. `backLabel` customizes native Back chrome. Compose LayerStack owns retained pages and their disposal.

### PageView

Requires writable `selection` and `pages` with unique ids and content factories. It provides page navigation, indicators and previous/next actions. Use for a sequential set of peer pages, while TabView represents named destinations and NavigationStack represents a drill-down path.

### RadialMenu

Required `items` use the menu item model. Options include `isPresented`, `label`, `launcher`, `preset`, `distribution`, `navigation`, `expansion`, `center`, `centerLabel`, `centerContent`, `centerPassThrough`, `anchor`, `follow`, `clearance`, `ringWidth`, `contentFit`, `gestureSelection`, `holdAction`, `enabled`, `onOpen` and `onClose`.

`holdAction` is a native InputAction Instance owned by the caller. The control subscribes to its `Pressed` and `Released` events; it does not accept an action name or define key bindings. Parent the action under a native InputContext and declare InputBindings there.

Item activation can close, stay, return to the root or go back using `completion`. Nested items are navigable; checked/selected items update their model. Geometry is specific to this control. It does not add a second general layout or input system. Native GuiObject or projected screen-point anchors connect the menu to an existing surface.

## Presented controls

### Alert

Supply writable boolean `isPresented` or a writable `item` cell (`nil` means hidden), plus `title`, `message` and `actions`. Item payloads are captured for the active presentation and passed to content/callback factories. Actions have `id`, `label`, `role`, optional `enabled`, `shortcut` and `onActivate(payload)`. Dismissal occurs before the action callback.

The control owns initial selection, selection containment, Back/cancel and restoration to a surviving previous selection. `transition = { source = nativeNode, seconds = 0.2, ease = Compose.easing.outQuad }` opts into native source motion; source may also be a readable. `surface = "fullScreen"` fills the native presentation area. Combined with a source transition, both bounds interpolate from the source rectangle, a non-interactive native snapshot preserves its appearance during the handoff, and dismissal reverses to the surviving source. Compose owns the snapshot and departing presentation; the source remains mounted. Native reduced motion makes the handoff immediate. Without transition, presentation is immediate. A writable `error` is cleared on dismissal. Use an alert for a brief decision. `icon`, `severity`, suppression and custom content refine the presentation.

### Sheet

Requires writable `isPresented` and writable `detent`. Default detents are `medium` and `large`. Custom entries are `{ id, fraction }` or `{ id, height }`, never both. Supply `title` and a `content` factory returning native children. The factory is called without arguments, and its subtree fills the available body region. The body uses a native vertical ScrollingFrame so content taller than the selected detent remains reachable while the sheet chrome stays fixed. Native drag detection resizes between declared detents. `interactiveDismissDisabled` blocks gesture dismissal; the explicit Close action remains available.

### DisclosureGroup and CollapsibleView

Both require writable `expanded` and `content`. DisclosureGroup expands content in the document flow. CollapsibleView opens its content as a larger presented surface. Use the native properties on their returned roots for outer layout.

### Callout

Requires a separately parented native `anchor`, content and `onRetire`. The anchor is borrowed; hiding its native ancestors suspends the callout. `seen`, `sessions`, `afterSessions`, `featureUsed` and priority determine eligibility and queue order. Retirement is delivered once. This is contextual teaching attached to a control, not a second application presenter.

## Collections

### VirtualList and VirtualGrid

Required: `from` (array/readable/body) and `render(current, placement, key)`. `key` is a function; when omitted, Compose uses item identity. Render receives readables for the current item and placement and returns native content. Durable row state belongs outside that render owner.

| Option | Default / meaning |
|---|---|
| `mode` | `windowed`; `all` deliberately mounts the entire collection. |
| `direction` | `vertical`; `horizontal` changes the scrolling axis. |
| `itemSize` | `40`, estimated main-axis extent. |
| `gap`, `crossGap` | `0`; cross gap defaults to gap. |
| `columns` | Grid column count, default `1`; may be reactive. |
| `overscan` | `2`. |
| `measure` | `false`; opt in to observing rendered native `AbsoluteSize`. |
| `measured` | Optional readable key-to-extent map; overrides observed measurements. |
| `follow` | Compose `none` or `end` policy, with optional `followThreshold`. |
| `status` | Optional writable Compose collection status cell. |
| `controls` | Optional table populated with Compose `indexOfKey`, `placementOf`, `offsetOf`. |
| `maxRetained` | Pool retains at most `32` row hosts by default. |

The returned root is a ScrollingFrame. Compose OrderedCollection owns indexing, window selection, anchor preservation and placement; its desired offset is applied to CanvasPosition. Sorting preserves the native anchor rather than forcing the first item to the top. `snap = "item"` settles scrolling to Compose placement boundaries; the default is `none`. Follow is a static Compose option; replace the collection owner through Compose.keyed when switching its policy.

Optional collection focus uses `focus`, `initialFocus`, `autoFocus`, `wrapFocus` and `disabled(item)`. `selection` is a writable key-set map. `selectionMode` defaults to single when selection or its callback is supplied, otherwise none. `onSelectionChange(nextMap)`, `onActivate(item, key)` and `onReachEnd` connect control events to domain behavior. `selectable(item)`, `reorderable`, `movable(item)`, `dragLabel` and `onReorder(keys, insertionSlot)` use the same zero-based remaining-row insertion contract as Table. Native properties and children remain available.

```luau
local rows = Compose.cell({ { id = "a", title = "Amber" } })
local list = UI.VirtualList {
    from = rows,
    key = function(item) return item.id end,
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

### Table

`from`, `key` and `columns` define rows. A column has `id`, `label`, optional pixel `width` (otherwise flex), `minWidth` (48), `maxWidth` (1e6), `resizable` and `sortable` (both true), and `value(item)` or `render(current, placement, key)`. Numeric `priority` collapses larger values first; `"always"` prevents collapse, and the first column always remains visible. A shared CollapsibleView exposes collapsed and natively truncated values through the row's More action while cell state stays retained.

`sort` is `nil` or `{ column, direction = "ascending" | "descending" }`. `widths` is a column-width map; `selection` is a key-set map. `selectionMode` is `single`, `multi` or `none`. `onSortChange`, `onWidthsChange` and `onSelectionChange` are controlled requests when supplied; otherwise writable cells are updated.

`selectable(item)`, `disabled(item)`, `onActivate(item, key)` and `rowActions(current, key)` specialize rows. `reorderable`, `movable(item)` and `onReorder(keys, insertionSlot)` support native drag reorder. The insertion slot is zero-based among the remaining rows. `editing` is a writable cell. Header height starts at 40. Estimated row height starts at the larger of 40 and the theme's regular control height, with native touch/gamepad minimum `44`; native text bounds can enlarge both. `header = false` removes the header band. `scrolls = false` mounts all rows and sizes to content; otherwise `mode` selects Compose windowed/all lifetime. Collection measurement, status, controls, focus and follow options also apply.

### RowActions

`content` is native content or a factory. `leading` and `trailing` contain `{ id, label, icon, enabled, role, onActivate }` actions. `open` is `nil`, `leading` or `trailing`; `onOpenChange` is controlled. `actionWidth` defaults to a minimum `88`; native label bounds can enlarge the action tray. Full swipe defaults on and can be set per edge. A shared `coordinator` cell permits only one open row.

Native swipe, context and keyboard/gamepad actions reach the same commands. A destructive action runs after its Compose departure animation exactly once; removing the owner cancels an unfinished departure. `reducedMotion`, `enabled` and `editing` remain explicit control options.

## Media and status

| Control | Main contract |
|---|---|
| `Label` | `text` or `label`, icon/iconPosition, textRole/role and native text properties; returns a TextLabel. |
| `Badge` | `label`, `status`, optional icon/position, appearance, corners and control size. |
| `StatusIndicator` | `status`: `neutral`, `info`, `success`, `warning`, `error`, `accent`; `form`: dot/ring/square/dash; optional `count`, `max`, `diameter`. |
| `ProgressView` | `value`, `min` (0), `max` (1); `presentation` bar/circular/spinner; label/endLabel, showValue/format, diameter/thickness/segments and optional trail `{ delay, duration }`. Segments require bar presentation; diameter requires circular/spinner. Trails hold on damage, settle over duration and snap on healing or reduced motion. Circular values center when native text bounds fit, otherwise display below the ring. |
| `Skeleton` | Loading placeholder with configurable form and line count. |
| `AsyncImage` | Image/source, optional resource or loader, placeholder, failure label and status callback; `imageProperties` forwards native properties/children to the inner ImageLabel. |
| `Avatar` | `name`, image/userId/resource, loader/onStatus, presence online/away/busy/offline, presence label/mark, diameter/controlSize, standard/icon form and optional activation. |
| `AvatarGroup` | `items` with id/name/image/userId/presence and optional `resource` shared-resource acquire function; max (4), stacked/spread layout, count/ellipsis overflow, onOverflow and diameter/controlSize. |
| `Stage` | Native ViewportFrame, `camera` CFrame or borrowed Camera, `fieldOfView`, `content(runtime, world)` for Compose-owned 3D content. |

AsyncImage's loader receives `(source, resolve, reject)` and may return cancellation. Superseded results cannot replace the current image. Loading and failure remain observable; the control does not invent successful assets. Resource lifetime uses Compose ownership and shared resources.

Stage's content callback mounts into its WorldModel and may return a teardown function. Use the same runtime's `Host.Part`, `Host.Model` and other native constructors. A 3D view inside a UI rectangle is different from 3D UI layout.

## Themes

`themes.SCHEMA` is `facet-theme/2`. `TYPE_ROLES` and `REQUIRED_TYPE_ROLES` list `caption`, `label`, `body`, `heading`, `title`, `control`, `strong` and `numeral`.

- `neutralPackage()` returns a mutable neutral package copy.
- `define(definition)` derives from `base` (neutral by default) and returns `package?, report`. Check `report.ok` before use. Accepted packages are recursively frozen; callbacks, cycles and malformed definitions are rejected. Color channels and semantic contrast pairs are validated.
- `checkCoverage(package, needs)` returns `{ ok, covered, missing }`.
- `resolveIcon(package, name, state?)` resolves real image content.
- `createStyleSheet(runtime, packageOrReadable?, options?)` returns a Compose-owned native StyleSheet. Create it inside a Compose owner and parent it as a numeric child; StyleLink only references the sheet and does not parent it. Options are injected `types`, selected palette `theme` (name or readable), native `name`, `transition` (native TweenInfo/readable or `false`), and `reducedMotion` (boolean/readable). Colors and opacity use native StyleRule transitions; the default duration is the package’s `metrics.motion.normal` (0.2 seconds if omitted), with Quad Out easing. The same timing applies across rules, and native transitions retarget interrupted changes. Reduced motion or `transition = false` sets zero-duration paint; omitted reduced motion follows GuiService. Explicit Instance paint still overrides stylesheet paint.
- `skin(runtime, packageOrReadable, slot, options?)` builds native control artwork. Options include `state`, `target`, `label`, `ZIndex` and injected `types`.

Packages contain `identity`, `style = { defaultTheme, themes }`, `metrics`, `chrome`, `assets`, `icons` and additional `rules = { { selector, properties } }`. Palettes contain `name`, `colors` and `extra`. Main colors are `surface`, `surfaceStrong`, `content`, `contentStrong`, `accent`, `onAccent`, `danger`, `onDanger`, `success`, `onSuccess`, `warning`, `onWarning`. Extras include control states, secondary content, hairlines and opacities.

StyleSheet rules own ordinary paint; explicit Instance properties intentionally override native styling. Share a package readable with both `Facet.controls(runtime, { theme = package })` and `createStyleSheet(runtime, package)`. Mount the resulting sheet and a native StyleLink in the target tree. See [custom themes](../guide/09-custom-themes.md) and [skins](../guide/10-rich-skinning.md).

## Native targets and boundaries

Mount a ScreenGui into PlayerGui, a BillboardGui into an appropriate world target, or a SurfaceGui onto a part using ordinary Compose Roblox constructors. Native safe-area and sizing properties belong to those targets. World surfaces remain flat two-dimensional UI; Facet does not supply ray, hand or gaze input or a VR layout mode.

Engine geometry settles asynchronously. Observe native bounds when a control policy needs measurements. Do not add a competing general solver or synchronously assume final text/layout bounds after construction.

The supported import boundary is the Facet root table and Compose exports reachable there. Control implementation modules are private. The vendored Compose tree is a generated, read-only snapshot; changes are made upstream and synchronized through the repository tooling.
