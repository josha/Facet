# Choosing and configuring controls

A control describes an interaction, such as choosing a value or editing a name.
Your signals hold the data. The control supplies the visual structure, input
behavior and cleanup. Start with `Facet.Controls.<Name>(core, spec)` and put the
returned `blueprint` in your screen. Own the returned control in the screen's
scope so subscriptions and in-flight work end with that screen.

```lua
local scope = core:scope("audio-settings")
local volume = scope:own(core:signal(0.5))
local slider = scope:own(Facet.Controls.Slider(core, {
    id = "Volume",
    label = "Volume",
    value = volume,
    min = 0,
    max = 1,
    step = 0.05,
    format = function(value) return tostring(math.round(value * 100)) .. "%" end,
}))
local blueprint = Facet.UI.VStack({ gap = "m", children = { slider.blueprint } })
-- Present blueprint in the usual way; dispose scope when its owner ends.
```

Use the [API reference](../reference/api.md) for the exact property types and
defaults. Specs have closed key sets: a property accepted by one control is not
automatically accepted by another. A signal is legal only on properties marked
reactive. A control that writes a value needs a settable signal; a memo is useful
for display and derived properties.

## Actions and boolean choices

| Control | Use it for | Configuration that changes its behavior |
|---|---|---|
| [`UI.Button`](../reference/api.md#button) | A simple action. | `label`, `onActivate`, `enabled`, semantic `role`, shape and size properties. `children` replaces the painted label with composed content; keep `label` as the action's readable name. |
| [`Controls.Button`](../reference/api.md#controlsbutton) | An action with busy state, repeat or a shortcut. | `busy`, `repeatDelay`, `repeatInterval`, `shortcut`, `dialogAction`, `enabled`, `role`, and `children`. Busy state gates activation. Shortcut ownership follows the active surface. `dialogAction = "default"` or `"cancel"` is an input behavior, not automatic dialog layout. |
| [`Controls.SplitButton`](../reference/api.md#controlssplitbutton) | A primary action beside a separate menu. | `label`, `onActivate`, `items`, `enabled`, `busy`, `shortcut`, `menuLabel`, and `env`. The primary action and menu remain separate focusable targets. |
| [`Controls.Toggle`](../reference/api.md#controlstoggle) | An on/off setting. | Caller-owned `value`; `presentation = "switch"`, `"checkbox"`, or `"button"`; `label`, `enabled`, `onChange`. Checkbox accepts a separate `mixed` signal. Only the button presentation accepts composed `children`. |
| [`UI.Toggle`](../reference/api.md#toggle) | The switch primitive underlying composite settings. | `value`, `label`, `enabled` and the primitive's activation callback. Prefer `Controls.Toggle` when you want the control to own the toggle interaction. |
| [`Controls.Chip`](../reference/api.md#newchip) | An independently selected filter or small action pill. | Caller-owned `selected`, `label`, `enabled`, and `onToggle`. Use Picker when choices must be mutually exclusive. |

Text plus an icon can be composed inside a button without adding another
activation target:

```lua
local saveLabel = scope:own(Facet.Controls.Label(core, {
    title = "Save",
    icon = "rbxassetid://YOUR_ICON",
    presentation = "titleAndIcon",
}))
local save = scope:own(Facet.Controls.Button(core, {
    label = "Save",
    children = { saveLabel.blueprint },
    onActivate = saveChanges,
}))
```

`Controls.Label` takes a fixed nonempty `title`, optional image asset `icon`,
`presentation = "titleAndIcon" | "titleOnly" | "iconOnly"`, and theme-compatible
`iconSize`, `textSize` and `gap`. If no icon exists, icon-only safely shows the
title. Its title and presentation are construction-time choices. For live text,
compose a bound `UI.Text` directly. See [Label](../reference/api.md#newlabel).

## Text entry

[`Controls.TextInput`](../reference/api.md#newtextinput) uses a native Roblox
text box. `value` is your editable `Signal<string>`. `onChange` reports accepted
edits; `onCommit` reports a completed edit; `onCancel` reports restoration of the
text captured when editing began. Caller writes do not pretend to be user edits.

| Configuration | What it gives you |
|---|---|
| `presentation = "plain"` | Ordinary text entry. Configure `placeholder`, `enabled`, and `clearButtonMode`. |
| `presentation = "search"` | A theme-tinted magnifying glass (`facet:search`) and clear behavior. Themes may replace the icon through their normal icon map. Connect the string signal to your filtering memo; the control does not choose your search rules. |
| `presentation = "number"` | A separate committed `numericValue` signal, `min`/`max` bounds, optional `parse` and `format`, and visible validation feedback. A half-typed string does not replace the committed number. |
| `multiline = true` | Wrapped native editing inside a native scrolling viewport. `height` controls the viewport; omitted height follows the multiline theme metric and available keyboard-free space. Numeric mode is single-line only. |
| `maxLength`, `validate` | Length limiting and accepted-value normalization or rejection. `validate(text)` returns an accepted string or nil. It is not server validation. |
| `clearButtonMode` | `"never"`, `"whileEditing"`, `"unlessEditing"`, or `"always"`; empty and disabled fields hide the affordance. |
| `keyboardType`, `submitLabel` | Declared intent only. Roblox's public API does not currently let Facet choose the native keyboard or Return-key label. |

[`UI.TextField`](../reference/api.md#textfield) is the lower-level primitive.
Use TextInput for the complete editing, validation, cancellation and input-context
handshake. Secure/password entry and rich-text editing are not provided.

[`Controls.ComboBox`](../reference/api.md#controlscombobox) combines editing with
suggestions. Supply separate string signals `value` (committed choice) and
`text` (draft), an `options` collection, and `acceptCustom(text)` to explicitly
validate values outside that collection. `commitOnFocusLost` opts into blur
commit. `placeholder`, `enabled`, `onChange`, and `env` configure the usual
behavior. Use a `Picker` when arbitrary typed values must never be accepted.

## Selecting values

| Control | Data you own | Presentation and configuration |
|---|---|---|
| [`Controls.Slider`](../reference/api.md#newslider) | Numeric `value`. | Required `min`/`max`, optional `step` and `format`, `label`, `enabled`, `tapToPosition`, `onChange` and `onCommit`. Optional `thumbImage` and `trackImage` override just those art slots. Pointer/touch drag and keyboard/gamepad adjustment share one value model. |
| [`Controls.Stepper`](../reference/api.md#newstepper) | Numeric `value`. | `min`, `max`, `step` (default 1), `format`, `label`, `enabled`, `onChange`. Useful for exact small increments. |
| [`Controls.Picker`](../reference/api.md#newpicker) | Single `selected` signal. | `options`, `style = "automatic" | "menu" | "segmented" | "inline" | "radioGroup" | "navigationLink"`, `label`, `query` (a searchable navigation link), `axis`, `enabled`, and selection callbacks. The automatic style is a form-row menu under touch or a pointer and a strip on a television, read from the environment. Options can carry labels, icons, badges, descriptions and availability. Live options use stable identities. Segmented strips support `iconOnly` and a pill/underline selection `indicator`; radio options retain visible labels. `presentation` is the deprecated spelling of `style`. |
| [`Controls.PopupButton`](../reference/api.md#newpopupbutton) | One `value` or a `selectedValues` set. | **Deprecated** (0.11.0): a value is a `Picker` menu style, a searchable list is `style = "navigationLink"` with `query`, a set of checks is a `Menu` with `checked` items. |
| [`Controls.Rating`](../reference/api.md#newrating) | Numeric `value`. | `count`, `allowZero`, `readOnly`, `enabled`, `glyphs`, `starSize`, `onChange`, and `env`. Read-only ratings show a value without offering interaction. |
| [`Controls.LevelPicker`](../reference/api.md#newlevelpicker) | Numeric `value`. | A discrete level strip: `count`, `allowZero`, `segment = "bar" | "glyph" | "image"`, the matching `glyphs` or `images`, `segmentSize`, independent filled/empty `tint`, `readOnly`, `enabled`, and `onChange`. This is not a game-level browser. |

Menus execute actions; pickers choose values. [`Controls.Menu`](../reference/api.md#newmenu)
takes a `trigger` blueprint and `items`, with normal actions, dividers, check or
radio state, icons, and nested children. Configure its adaptive presentation and
environment through the documented spec. Avoid inventing a second list of options
for a menu-shaped selection control: the Picker's `menu` style already supplies that behavior.

## Showing content and progress

| Control or primitive | Main configuration |
|---|---|
| [`UI.Text`](../reference/api.md#text) | `text`, semantic typography and color roles, wrapping, line limits, fitting and truncated-text disclosure. Text may be a readable value. |
| [`UI.Image`](../reference/api.md#image) | Image source, dimensions, fitting and tint. Use semantic tint to follow the active theme. |
| [`Controls.AsyncImage`](../reference/api.md#newasyncimage) | Resource `provider`, `key`, owner `scope`, dimensions, `failureLabel`, `retry`, and `dimmed`. Loading, failure and disposal use the resource provider's lifetime. |
| [`Controls.ProgressView`](../reference/api.md#newprogressview) | Supply `value` for determinate progress or omit it for indeterminate activity. `presentation` selects bar, spinner or ring where supported; `min`/`max`, `label`, `format`, `showValue`, and bar `height` configure the reading. Indeterminate activity needs its documented `scope` and `motionClock`. A spinner's size is theme-owned; bar height is not a spinner-size option. |
| [`UI.Path`](../reference/api.md#path) | Stroke and points, including points from `Facet.pathShapes`. This is drawing geometry, not a second layout engine. |
| [`UI.Stage`](../reference/api.md#stage) | A solver-sized viewport for live 3D content such as an avatar or item preview. |
| [`UI.Foreign`](../reference/api.md#foreign) | A solver-sized host for a third-party GUI object, with an explicit ownership boundary. |

## Grouping, navigation and collections

| Control | Use and configuration |
|---|---|
| [`Controls.DisclosureGroup`](../reference/api.md#newdisclosuregroup) | `label`, caller-owned `expanded`, a `content()` builder, `enabled`, `onToggle`. Content mounts only while expanded; collapsing restores focus to the header. |
| [`Controls.TabView`](../reference/api.md#newtabview) | Caller-owned `selection` and `tabs` pair labels/icons with content. `placement` accepts automatic, bottomBar, bottomBarCompact, topBar or sidebar; `indicator`, `sizing`, `iconOnly`, `textSize`, `accessories`, `railWidth`, `enabled` and `transition` configure the supported forms. Use it for peer sections. |
| [`Controls.NavigationStack`](../reference/api.md#controlsnavigationstack) | Supply `root`, `destinations`, caller-owned `path`, and a localized `backLabel`; optional `env` and `transition` use existing policy. Destination `content(scope, entry)` builders receive their resource owner. `api.push`, `pop`, `back` and `popToRoot` change testable data-flow state. Use it for drill-down screens and wizards. |
| [`Controls.Callout`](../reference/api.md#newcallout) | `anchor`, `content`, placement (`edge`, `align`, `tail`), `priority`, eligibility facts (`seen`, `sessions`, `afterSessions`, `featureUsed`), and required `onRetire`. Optional `onShow`/`onHide` report lifetime. The queue avoids competing attention surfaces. |
| [`Controls.Table`](../reference/api.md#newtable) | Items, columns, row keys, sorting and selection; optional disclosure, resizing, reordering and windowing. Cell builders compose ordinary blueprints. Read the reference's restrictions before combining virtualization with row actions. |
| [`Controls.VirtualList`](../reference/api.md#newvirtuallist) | Keyed items, cell builder and declared item extents; builds the visible band on either axis. Configure gaps, focus policy, snapping and supported row actions. Keep durable item state outside cells. |
| [`Controls.VirtualGrid`](../reference/api.md#newvirtualgrid) | Windowed keyed cells in an adaptive grid, with declared extents, gap, axis and snapping configuration. |
| [`Controls.RowActions`](../reference/api.md#newrowactions) | Wrap `content` with `leading`/`trailing` action arrays; configure `fullSwipe`, shared `coordinator`, `editing`, and `env`. Each action declares its label, optional icon, role and callback. Keyboard/gamepad users reach the same actions through the action menu. |
| [`UI.ScrollView`](../reference/api.md#scrollview) | Native scrolling, clipping, axis and indicator configuration. It does not virtualize arbitrary children. A presented controller supplies `scrollTo` and `scrollToVisible`; collection APIs can reveal off-window items by identity. |

Forms are compositions today. Combine a ScrollView, stacks or grid rows, TextInput,
Toggle, Picker and buttons. Baseline alignment keeps differently sized label text
on the same reading line, and `UI.Spacer({ minLength = "m" })` reserves space while
still expanding. Facet does not provide a Form container that automatically
restyles every contained control or validates an entire data model.

## Theme, adaptation and lifetime

Start with the [theme catalog](13-theme-catalog.md), including Facet Neutral.
Use semantic roles and metric names such as `"m"` or `"targetSizes.minimum"`.
A literal pixel value is a deliberate choice to stop following that theme metric.
Use the [styling](05-styling.md) and [rich skinning](10-rich-skinning.md) chapters
when a whole control family needs new paint or art.

Container `enabled` applies to descendants; a disabled ancestor wins over an
enabled child. Container `tint` supplies an inherited continuous color, while a
local tint can override it. Neither requires rebuilding the control. For motion,
`presenter.withAnimation` animates supported commit changes;
`presenter.motionClock:animate(readable, motionClass, { scope = scope })` follows
a numeric readable automatically. Map its output to an existing tint blend for
theme-compatible color motion. The clock keeps reduced-motion behavior in the
same authority as other motion.

Let the environment supply size, safe areas, preferred text size and live input
classes. Use [adaptive recipes](15-adaptive-recipes.md) for layout decisions;
branching on a device name bypasses that policy. Test the same description under
phone, tablet, desktop and ten-foot facts, and use `dump()` for inspectable control
state. Headless tests establish logic; Studio and physical-device observations
are separate evidence, as [device verification](11-device-verification.md)
explains.
