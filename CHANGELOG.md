# Changelog

All notable changes to Facet are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and Facet's version
numbers follow the policy in
[`CONTRIBUTING.md` §6](CONTRIBUTING.md#6-versioning-and-deprecation): while the
library is pre-1.0, a minor bump may change public behavior, and every retiring
surface is listed in `Facet.DEPRECATIONS` with its replacement and the earliest
version that may remove it.

The version string lives in exactly one place, `src/init.luau`, and is readable at
runtime as `Facet.VERSION`.

## [Unreleased]

### Summary of this release's control work

One pass added the controls most game screens were composing by hand, and
extended existing controls with the options they were missing. Every new
control is on `app.controls` with a typed spec, automatic input discovery
(pointer, touch, keyboard, gamepad), the 44 px hit floor, theme paint through
the package slots, and a section in the [API reference](docs/reference/api.md).
The [control chooser](docs/guide/14-choosing-controls.md) says when to pick
each one over its closest alternative. The entries below this summary give the
detail and every behaviour or path change.

- **New controls.** Identity and status: `UI.Avatar`, `UI.AvatarGroup`,
  `UI.Badge`, `UI.StatusIndicator`, `UI.Skeleton`, `UI.ShortcutHint`.
  Notices and overlays: `UI.Notice`, `UI.Snackbar` (and
  `app.presentSnackbar`), `UI.Dialog`, `UI.Popover`, `UI.Callout`, `UI.NavBar`.
  Workflow and paging: `UI.Card`, `UI.Pagination`, `UI.StepIndicator`,
  `UI.Vote`. Colour and dates: `UI.ColorPicker`, `UI.DateTimePicker` and
  `Facet.civilDate`.
- **Extended controls.** Button and Chip take local `controlSize`,
  `appearance` and `corners`, and Button takes `icon`, `trailingIcon` and
  `over = "media"`. Toggle settings rows, `width` and hints; DisclosureGroup
  descriptions and appearances; removable Chips in edit mode; TextInput field
  chrome, `readOnly` and `selectOnFocus`; NumberInput presets and `scrub`;
  Slider `axis`, `range` and `minGap`; Picker `cards`, field chrome, segmented
  `appearance` and option `indicator`; Sheet placement, `hug` and pinned
  actions; ProgressView segments and trail; Menu edges and widths; TabView tab
  `indicator` and `enabled`.
- **Shared mechanisms.** Success and warning palette pairs; a theme
  `controlSizes` ladder; eleven more standard icons, drawn by every shipped
  theme wherever a control asks for one; the overlay band ladder, so a snackbar, a callout and a menu stack in
  a fixed order; selected-under-hover paint; strokes that sit inside their box;
  a Sink context that never swallows a release it owes.
- **Breaking.** Several mounted paths moved (Dialog, Sheet, Card, StepIndicator,
  plain Chips inside their target); Chip removal is edit mode; a switch paints
  no plate. Each is listed with its new path below.

### Interaction and theme hardening

- Tab bookmarks follow real navigation, including shoulder entry, while explicit focus requests keep their destination.
- All plain Chips reserve disjoint effective targets. Toggle accepts bound width for wrapping content-sized settings; display-only switch labels clamp at zero space.
- Built-in sheets tint resolved framework icons, over-media lettering follows contentStrong, and success/warning pair validation covers authored variants.
- Every lifted label on skinned art (a control's plain, strong, secondary, cancel and destructive text, a field's text and placeholder, a badge's count) takes its role's colour where it clears 4.5:1 on the sampled art, else the next of the content ramp that does. Packages declare `extra.fieldArt` and `extra.badgeArt` beside `controlArt` (`a` < 1 for art that lets the panel through); the generated lifts carry the picks, so they no longer out-rank them with the flat colours.
- Text that is not lifted but paints over skinned art — a field's editor text and placeholder, a stepper's mark, a picker's value, an author's label inside a skinned box or on a `UI.background` plate — takes the colour picked for that art (the renderer tags it `facet-on-<slot>`), and so does an icon picture on art. Hover and pressed tints on skinned art now keep every label on it readable (each state tint moves only as far as its labels still clear 4.5:1), role-tinted art keeps its role through hover and press, and a stepper's pressed plate picks its own label. Packages declare `extra.panelArt` and any per-state control art (`controlArtHover`/`controlArtPressed`, `stepperArtPressed`).
- `UI.VirtualGrid` keeps half of each gutter at its outer edges (both ends of the scroll axis, both sides of the lanes), so content that paints past its cell — a lifted Card and its focus ring — is no longer cut by the grid's clip in a corner cell. Lanes are narrower by one gutter and the canvas longer by one row gutter.
- `UI.ColorPicker`'s panel keeps one height across its techniques: every technique is mounted, the inactive ones `hidden`, so the body reserves the tallest at the current width (at most the scrolling body's own height) and a shorter one sits at its top. A tab switch no longer resizes the panel or the phone sheet.
- Badge placement (owner ruling A): `UI.badged(host, value, direction?)` puts a count or dot seal on a Button's, icon button's or Avatar's top corner (top-left in rtl), centred on the corner, paint only — the host's box, target and label are unchanged. A segmented Picker's icon tabs (so a TabView's icon strip) wear their `badge` there; text tabs and list, menu and picker rows keep the inline trailing pill. Counts above 99 read "99+" everywhere; `true` is a dot (a bullet on the seal).

### Semantic status colors

- Added success/onSuccess and warning/onWarning palette pairs and public effective-pair helpers. Both compile gates enforce 4.5:1; omitted pairs retain earlier fallback paint. Explicitly authored roles that were previously inert now paint and must pass validation.
- Badge semantic art retains one caption-sized host, with room for multi-character fallback glyphs. Managed pictures on the four explicit readable partner roles follow that lettering, including selected menu/picker content; unrelated package icon tint remains unchanged.

### Pickers

- **ColorPicker saved colours.** `onSaveSwatch(color)` ends the Swatches tab with
  a "+" cell that proposes the current colour (never one already listed);
  `onRemoveSwatch(item)` adds an Edit/Done toggle whose editing mode proposes a
  swatch's removal on activate or Delete/Backspace/pad remove. The caller owns
  the list and its persistence.
- **ColorPicker on touch.** The preview leads the panel above the plane, a
  drag on the plane or a strip shows the colour in a bubble above the finger,
  and a phone sheet scrolls its technique so the readout and Apply stay put.
- **ColorPicker paint.** An exact two-layer plane (no banding), a rainbow hue
  strip and a colour-over-checker alpha strip (`UI.Slider.trackContent`, new),
  two-tone opaque thumbs, square cells for a short swatch list, a hue per column
  at any column count, Apply as the accent, the brick name above its grid.
- **DateTimePicker.** The calendar anchors to the field (below, start-aligned),
  its icon sits inside the field, a single date shows one month, the range band
  is one pill with content-coloured ends, in-month days are strong, the header is
  plain words, the draft footer is a Reset all link with Cancel and an accent
  Apply, and the panel hugs its weeks. A TextInput with an error or held
  `invalid` wears the danger border.
- **ViewThatFits** picks the first candidate that fits without being cut (the
  undercut that kept a cut row is gone); a stack offers it only the room its
  siblings' gaps leave, so measure and arrange choose the same candidate.

### Changes

- **Snackbar dismiss words match Dialog and Popover.** A false you write on
  your own now reports `"cancel"` (was `"close"`), and owner teardown or the
  release function reports `"cancel"` once (was silent). The Close button
  keeps `"close"`; application disposal still reports nothing.
- **A hovered selected skin keeps its selection tint.** Image-skinned packages
  painted a selected row plain white under the pointer; a compound rule now
  paints `$ChromeTintSelectedHover`, the selection tint lifted.
- `UI.Alert`'s `icon` name takes Button's icon path, so theme art draws it.
  A Picker option's `indicator` follows the live record, and its `avatar`
  keys are closed. A disabled field's label shows no press or hover.
  `civilDate.parse` asks for AM or PM on a bare 1-12 hour under a 12-hour
  locale. Pixel Quest draws the warning, First and Last icons.

- **`UI.DateTimePicker`** and **`Facet.civilDate`.** A civil date (no time
  zone) field that opens a calendar — one or two consecutive months, disabled
  days focusable and inert, typed entry where a keyboard or pointer is live,
  time fields with a touch time list, ranges with clipped presets and an
  Apply/Cancel draft — or the calendar inline. Today comes from an injected
  clock (default: the player's local clock); `civilDate.fromUnix/toUnix` take
  an explicit offset. The day grid is one Tab stop; the arrows walk days across
  months, and paging stops at a month wholly outside the bounds.

- **`UI.ColorPicker`.** A colour well over the caller's Color3 that opens an
  anchored panel (a hug sheet on compact touch, a centred sheet at ten feet), or
  the panel inline: swatches, a spectrum plane with a hue slider, HSV sliders
  and the engine BrickColors, an RGB/HSV/Hex readout on every tab, optional
  opacity, and an Apply/Cancel draft. Canonical HSV keeps a grey's hue; the
  plane takes (and sinks) the right stick on a pad; an anchored panel fits the
  room beside its well and scrolls its technique.

- **One commit model for both pickers.** Without `draft`, every change commits
  as it happens and every way of closing keeps it; with `draft = true` nothing
  commits until Apply (typed text included) and every other close restores.

- **A single-size Sheet hides its Size control** (it had nothing to choose).

- **Icons in Snackbar, Notice, Vote and StepIndicator** take Button's icon
  path (theme art, `facet:` names, the unknown-name warning), so a semantic
  name no longer paints an empty image. The StepIndicator cue is now
  `Cue/Check` and `Cue/Error` (was one `Cue/Mark`), and its number marker stays
  a circle at every text size.
- **`UI.Snackbar`**: a plain message row hugs its copy up to the strip's
  maximum instead of filling it.
- **Pagination and hugging segmented strips reserve the target floor** as layout
  width, so neighbouring targets never overlap; `UI.Pagination` refuses
  `width = hug | content` (its window narrows to the width it is offered), and
  a focused arrow that disables at an edge hands focus to the current page.
- **`UI.StepIndicator`** always takes the width it is offered; `sizing` is how
  its steps share it. The list closes when `current` changes, so a refused step
  leaves it open, and an empty list has no Steps button.
- **Input**: a Sink context never swallows the release owed to a binding that
  received the press (a menu opened by ButtonA, closed by ButtonB, reopens on
  the next ButtonA).
- **`UI.Card` lifts on engagement.** Hover, a painted focus ring, a held press
  or its open menu raise the card to 1.04x (paint only) with the raised shadow;
  reduced motion keeps the shadow alone, and at ten feet the focus lift is the
  only scale. Gutters around a card reserve the lift
  (`Facet.layout.transformFootprint`).
- **Menu rows.** A floating menu's rows are at least the target floor tall (44
  under Facet Neutral, was the compact 36), so stacked rows' hit rects never
  overlap; a plain row's label leads like a badge or shortcut row's. This
  includes the legacy PopupButton's floating rows.
- **`UI.TabView` tab words fit.** The strip's `textSize` defaults to `"fit"`:
  a label shrinks toward the caption role before it truncates.
- **Text fit refuses an overlong word.** `textSize = "fit"` and `Facet.text.fit`
  compare the widest word with the box, so a single word wider than the box
  shrinks (it used to answer the cap and let the engine truncate it).
- **`UI.Snackbar`** content sits inside a theme package's panel carve (the row
  is the plate).
- **`UI.Picker`** `navigationLink` keeps its one-line row (title leading, value
  trailing) at every width until the text preference needs a second line.
- **Skinned selected rows** keep their selection tint while pressed.
- **Input: one key edge, one delivery.** A `Bool` action armed while one of its
  keys is held (its context enabled, or its binding added, mid-press) no longer
  receives that press or its release; the key's release ends the hold. Game
  contexts enabled by a held key see the next press, not the current one.
- **Grid navigation leaves for a neighbouring control.** Up from a grid's first
  row or Down from its last row now reaches a control beside it that
  contributes exactly one focus group (a TextInput, a range Slider, a
  VirtualList, a Chip row, a DateTimePicker's time fields), where it used to
  stop or skip. The exit names that control, not its group name.
- **`UI.Vote`.** Up, down or none over the caller's value, on Picker's
  segmented icon strip through a private submission seam (a refused vote never
  paints; pressing the chosen side proposes none), a caller summary, and a
  read-only informational form with no stops.
- **`UI.StepIndicator`.** Workflow steps with `current` as the one authority
  over the underline and summary, per-step state cues and words (check, error
  mark, number), Buttons only for navigable enabled steps, and a "Step n of m"
  summary with a Popover list when the labels do not fit.
- **`UI.Pagination`.** Controlled page selection: `page` and `onChange`, a known
  or unknown `pageCount`, a bounded numeric window with real-gap ellipses, First
  and Last on request, `numbers | arrows | label` forms, an explicit `rtl`
  direction, and a measured narrowing that drops the farthest pages before it
  falls back to "Page n of m".
- **`UI.Card`.** Artwork, a title and a caption as one body, with a primary
  action and a More menu as sibling targets. `reveal = "automatic"` shows them
  on engagement (pointer, painted focus, a held press, the open menu, a browse
  stop) on a plate inside the card's own hosted envelope, so its box never
  changes, and at rest whenever the session has touch; `always` keeps them in
  layout. `api.enterActions()` enters them from a
  `UI.VirtualGrid` browse stop; Cancel returns to it.
- **Transient traps follow their contribution.** A `transientScope` whose
  control left the tree (a recycled cell, a closed region) no longer strands
  focus in its trap; the trap is released before the focus map is rebuilt.
- **Overlay paths and the tiny room (breaking paths).** `UI.Dialog` and
  `UI.Sheet` lay their regions in one `Room/Column`: `/<Dialog>/Center/Panel/Room/Column/{Header,Body,Actions,…}`
  and `/<Sheet>/Layer/Panel/Room/Column/{Header,Body,Actions,…}`, with Sheet
  content at `…/Room/Column/Body/<content>` (a scrolling hero: `Body/Inset`);
  the Sheet grip stays `/Layer/Panel/Drag/Handle`. When the pinned regions and
  a one-line body do not fit the room, every region scrolls as one, so each
  action stays reachable. A compact screen alone no longer stacks two Dialog
  actions that fit, and a Dialog hero sizes from the live panel width.
- **Selected under hover** paints the selected fill lifted by the theme's
  hover step (new `$ControlSelectedHover` token, `Selected — hover` rule in both
  sheet builders and the fallback painter), never plain hover.
- **Snackbar layer.** The strip is the toast band's first step
  (`src/present/surface_bands.luau` now owns the band ladder); Callout, a
  passive Popover and help, disclosure and reveal plates read above it; modals
  above all. The strip docks bottom-centre, a stacked action trails, a close by
  pointer leaves no input catcher, and the HUD reservation holds exiting rows
  until they have slid out.
- **Caller callbacks are never swallowed.** A throwing `onActivate`,
  `onPresentedChange` or `onDismiss` on Dialog, Popover, Sheet, Notice, Callout
  or Snackbar is raised after the control has settled its own state.
- `UI.Sheet`: `interactiveDismissDisabled` also stops Cancel running the
  cancel action; the Size control reads player words (`Size: Fit`,
  `Size: Medium`). Overlay actions type-check `label`/`enabled`/`busy`, and
  `UI.Notice` refuses the reserved action ids `Link` and `Close`.
- `UI.Picker` options take `indicator` (a StatusIndicator spec in a segmented
  option's trailing lane; construction-only).
- `UI.Menu`: rows with a badge, shortcut or section heading take the themed
  panel width instead of collapsing a hugging panel.
- `UI.Popover`: a path source resolves from its own screen's root inside an
  embedding screen; a path that has not mounted is awaited with one warning.
- A focused horizontal value control and live chrome share one owner of the
  arrow keys (`NavigateH`), so arrows never stay bound to a flat screen.
- **`UI.Snackbar`** and **`app.presentSnackbar`**: one application snackbar
  service with a persistent bottom strip. The caller's `isPresented` is the only
  authority; close, Cancel, timeout and supersession are proposals, and
  `onDismiss` reports action | close | timeout | superseded | cancel once. One
  row shows, eight wait by priority, nine is the cap (refused, never dropped).
  Readable dwell pauses on hover, focus and covering surfaces.
- `toast_schedule` gains an opt-in controlled mode (Toast defaults unchanged).
- Adopted chrome composes top, content, bottom in either presentation order; an
  empty chrome scope takes no part and binds no arrow keys; Cancel on an adopted
  chrome row reaches its own surface.
- **`UI.Sheet` placement, parts and gestures.** `placement` (automatic keeps
  ten-foot centre, otherwise bottom; `side` with a physical `edge`), the Dialog
  `width` presets, `closeButton`, a `header` blueprint or `false`, a sticky or
  scrolling `hero` (image or authored content), pinned `actions` with the
  Dialog action group, `contentInset`, a `"hug"` detent, and `scrollPolicy`.
  The panel is now a pinned column around ONE body scroller: the panel itself
  no longer scrolls, and content moved from `/Layer/Panel/<content>` to
  `/Layer/Panel/Body/<content>` (see the Room/Column entry above for the final
  paths). Drags acquire
  from the grip, the panel's native drag detector or the touch-pan stream, are
  bound to the input class that started them, and release through a projected
  velocity with bounded resistance. A function-bound `title` now works, as its
  type always said. The room includes the on-screen keyboard.
- **`UI.NavBar`** and the nav bar's slot form: `leading` follows Back, `center`
  replaces the title and fills the rest, and trailing content moves to a second
  row when the measured width cannot hold it, without rebuilding the center.
  The lowercase `navBar` keeps its legacy shape unless a slot is given.
- **`UI.Notice`.** An in-page status message: severity icon and paint, optional
  title, link, up to two actions and a close that reports the press. The
  accessories move below the copy when the measured width cannot hold both.
  `placement = "affixed"` publishes its measured rect through
  `presenter.reserveHud` for content that reads `Facet.layout.hudInsets`.
- **`UI.Dialog`.** A modal panel the caller owns the open state of: optional
  hero, title with a close button, one scrolling body, an action label and pinned
  actions. Close, Cancel and the backdrop propose; actions never close by
  themselves; `onDismiss(reason)` reports `close | outside | cancel | action`.
  Width presets are theme ceilings (new `controls.dialog.wideWidth`), the height
  is the live room above the keyboard, and an overflowing plain body is one pad
  stop that scrolls (`contentSelectable`).
- **`UI.Popover`.** Content against a trigger or a source (a path or a rect).
  The caller owns `isPresented`; `onPresentedChange(next)` is a proposal and
  `onDismiss(reason)` reports each closure once. A compact touch screen gets a
  sheet (`compact = "popover"` opts out). `maxWidth`/`maxHeight` cap the whole
  panel inside the live safe box; a removed or replaced path source releases it
  with `"anchorLost"`.
- **Anchored surfaces** take `crossOffset` (px along the alignment axis, before
  the safe clamp) and live `maxWidth`/`maxHeight` caps; `Facet.layout.anchorPlacement`
  takes `crossOffset` too.
- **`help` has a table form** `{ title?, body, shortcut?, edge?, align? }`;
  `text_audit.helpRoutes` checks the title and body separately. A live help or
  disclosure plate now follows a same-path rebuild or changed value, and stays
  inside the live safe box as insets grow; the disclosure plate also retires
  when its label becomes a hidden ViewThatFits candidate.
- **`UI.Callout`** takes `title`, `media`, `steps`, up to two `actions` and a
  top `closeButton`; `content` is optional when another part draws something.
  Function (`(use) -> T`) facts are now tracked, and a dismiss, dispose or rearm
  inside a synchronous `onShow` no longer strands a plate.
- **`UI.Menu`** takes root `edge`/`align`, panel `width` and `maxHeight` (rows
  scroll one path level deeper), and items take `badge`, `avatar`,
  `sectionTitle` and a display-only `shortcutLabel`.
- **`UI.TabView`** tabs take `indicator` (a StatusIndicator spec) and `enabled`.

- **Every stroke sits inside its box.** Theme hairlines (raised, chip, field,
  `utility`) and authored `UI.stroke` borders set
  `BorderStrokePosition = Inner`, so a scroll clip no longer cuts them, and the
  node's padding on each side is at least the stroke's thickness. A stroked
  container that had no padding (a raised menu card, a field plate) now insets
  its content by its hairline (1 px under Facet Neutral). Only a resting stroke
  pays: a bound `stroke` (a focus, hover or selection ring) stays paint-only
  and never moves padding.
- **Toggle loses its plate.** A switch, bare or in a settings row, paints no
  surface plate and takes no press dip, and a theme package's `control` slot art
  no longer paints Toggles (`CONTROL_CLASSES` is Button only). A settings row
  wears the `control` frame, so its content lines up with Button and Slider
  rows in every theme.
- Slider row content inset changed from 16 to 12 px, matching the other rows.
- A labelled `menu` Picker is a field (title above, trigger at the leading edge)
  at a regular or wider size class under a pointer or pad; the popover counts
  avatar, icon, meta and badge when it sizes to its widest row, never lists
  fewer than one visible row under `maxHeight`, and stops warning about an
  ignored `offsetY`. The hint/error line is released by the picker's dispose.
- NumberInput: without `precision`, a step button or scrub rounds to the decimal
  places of `step` and `min` (three presses of 0.1 hold 0.3); a scrub over a
  typed, uncommitted draft discards the draft and starts from the committed
  number. A touch on a field with nothing to select or scrub adds no listener;
  a mouse press whose release was lost no longer blocks the next scrub.
- The arrow that moves focus onto a slider is not also a value step; a range
  thumb stopped by `minGap` keeps the arrow instead of passing focus.
- A plain icon name outside the vocabulary draws a dot and warns once per name,
  naming the near miss (`search` → `facet:search`).

- **Breaking — `UI.Chip` removal is edit mode.** A tag selects and shows no
  close mark by default. The new `editing` (boolean or readable boolean,
  required with `onRemove` on a selectable chip) shows the mark inside the tag's
  one plate; activating the tag, or Delete/Backspace while it holds the ring,
  removes it. The separate `…+token/Remove` button, its focus stop and its
  plate are gone; the tag mounts at `<id>+target/<id>` like every chip. A
  remove-only token (no `selected`) is always editing. Removal focus moves to
  the next removable tag, then the previous, then `removeFocusFallback`.

- `UI.TextInput{ selectOnFocus = "none" | "all" | "end" }` (and the primitive's
  `UI.TextField{ selectOnFocus }`): what each new native focus session selects,
  in byte offsets. A pointer focus applies it at that pointer's release, after
  the engine's own caret placement; activation applies it at once. The default
  writes nothing.

- `UI.NumberInput{ scrub = true }`: a horizontal drag across the editor moves
  the number one `step` per 8 px of total travel, through the step buttons'
  rounding and bounds, and commits once at release. Before the shared slop a
  tap stays native; Escape, class loss, disable, read-only and disposal restore
  the snapshot; a caller write ends the drag. `UI.TextField` gains the
  `onScrub` handler the adapter reports it through.

- `UI.Picker{ style = "cards" }`: each option a selectable card on the shared
  menu card row (a hairline edge at rest, the accent plate when chosen),
  carrying the new option `meta` (a secondary label/value, also on menu rows)
  beside its description, icon and badge. A row of cards wraps instead of
  overflowing and long copy wraps; with `required = false` choosing the
  chosen card again clears it. The picker sweep covers the new style.

- `UI.Picker` segmented strips take `appearance` (`filled` plate, `stroke`
  outline, `utility` none; bound words repaint in place), `corners` (track,
  outer ends and selected fill; `pill` is the reference `isCircular`) and
  `controlSize` (segments inside one reserved target); radio and inline rows
  take the rung's height. `indicatorPosition = "leading" | "trailing"` places
  the radioGroup's mark. `selection_indicator.segmentShape` takes an optional
  outer corner.

- `UI.Picker` is a field: `requiredMark`, one `hint`/`errorText` message line
  (on every style; an error also borders the menu trigger), `controlSize`
  (the menu trigger inside a reserved target), `appearance` (menu standard /
  contrast / utility; automatic maps five words across families), `corners`,
  and `maxHeight` on the open menu panel. Opening a menu scrolls the selected
  row into view. Options take `avatar` (the shipped Avatar leading the row);
  menu rows gain `menu_recipe` `avatar`.

- Fixed: a `UI.Picker` option carrying `badge` or `sectionTitle` crashed as
  soon as its style resolved to `menu` or `navigationLink` (what `automatic`
  resolves to on most nearby screens). Both now render on the menu engine —
  the count seal on the row and the heading as a caption before it — in
  static, keyed and searchable lists. A keyed list (and a keyed strip) can
  gain its first heading after mount; sectioned live strip rows no longer sit
  in a `SectionRow-<id>` wrapper (the heading is its own keyed entry).

- `UI.Slider` gains `axis` (`"y"` runs bottom to top), `range` with `minGap`
  (a `{ lower, upper }` band, thumbs never cross, illegal runtime pairs
  quarantined with `api.diagnostics()`), `thumb` (`always`/`auto`/`none`,
  paint only), `thumbContent(info)` (a custom knob per thumb; refused with
  `thumbImage`), live paint-only `rotation` with inverse pointer conversion,
  and `controlSize`. Pointer input now reads the track's painted rect at event
  time, so a scrolled track converts correctly. Range handles share one focus
  group; a gamepad enters adjust mode with Activate. **Behavior change for
  every Slider:** the label now shrinks (full text disclosed) before the track
  and readout, which clears two recorded Brightness row overflows. Losing the
  pointer and touch classes mid-drag now cancels through the live environment.
  `reserveTarget` takes an optional height negotiated like width.

- `UI.NumberInput` is the number presentation preset over the same text-entry
  engine, with `step`, `precision`, `stepButtons`, `prefix` and `suffix`, and
  `Facet.recipes.arithmetic.parse` is an opt-in bounded arithmetic parser for
  its `parse`. **Breaking, number presentation:** `onCommit` now reports the
  committed number rather than the string; the default parser is a strict
  decimal grammar instead of `tonumber` (no exponent, hex or blanks); a typed
  value outside `min`/`max` is clamped and committed with reason `"clamped"`
  instead of refused; leaving on an incomplete draft (empty, lone sign or point)
  restores the last number silently unless the field is `requiredMark =
  "required"`; `precision` rounds half away from zero at commit.

- `UI.TextInput{ readOnly }` keeps a field focusable, selectable and at full
  contrast while refusing every edit through the engine and the model (no clear
  affordance, no commit report). `visibleLines` sizes a multiline viewport as
  that many lines plus the field inset. The primitive gains
  `UI.TextField{ editable }` (default true), composed with `enabled` onto the
  engine's `TextEditable`.

- `UI.TextInput` wears the shared field chrome: `label` (a tap focuses the
  field; no extra focus stop), `requiredMark` notation, one `hint`/`errorText`
  message line with the `status.error` mark, `leading`/`trailing` accessories
  inside the plate, and `controlSize`, `appearance` and `corners`. A field with
  none of these keys keeps its tree. The number presentation's rejection line
  now lives on that message line (`<id>/Message/Validation`, was
  `<id>/Validation`), and the clear affordance plus any trailing focusable are
  now keyboard and gamepad stops after the editor. Managed pictures under
  `danger` lettering follow it, so the error mark paints the message's colour.

- A chat thread can be scrolled while a reply is arriving. `UI.VirtualList`'s
  `follow = "end"` re-pinned the end on every frame of content growth, and one
  frame of a pan never moves the whole `followThreshold`, so a player panning
  away from a growing thread was snapped back faster than they could travel and
  the list read as completely stuck (measured on a phone: canvas 1216 in a 389
  window, a 230 px pan moved the offset 827 -> 827, while the same gestures
  worked once the thread was a few hundred px up). Following now YIELDS on a
  reported offset that moves away from the end — including from inside
  `followThreshold`, which is what the old test could not see — and while it is
  yielded, growth moves the view by nothing. It resumes when the player comes
  back to the end, or when the consumer re-asserts `follow`. The list's own
  follow-write is matched against its echo, so it is never mistaken for the
  player.

- A desktop the engine buckets as a `"Large"` physical display no longer gets the
  ten-foot treatment (1.5x type, metrics, target floors and overscan margins).
  `GuiService.ViewportDisplaySize` answers `"Large"` for a 4K desk monitor, and a
  big pixel count is not a long viewing distance; a mouse now corroborates
  against it exactly as a touchscreen already did. A console has neither and is
  unchanged, and `viewingDistance = "ten-foot"` still outranks the derivation.
- A placement property a parent never reads (`alignH` under a stack, the
  `offsetX`/`offsetY` pair `UI.offset` writes under anything but a `UI.Anchor`)
  now `warn`s in Studio, once per site, as well as being reported on
  `controller.diagnostics()`. Off in a running game.
- A finger can scroll a list of draggable things again. A `UIDragDetector` owns
  a touch from the press and keeps it whether or not the press ever becomes a
  drag, so on a phone a feed of draggable cards could not be scrolled at all
  (measured: a 230 px flick moved the scroller 0 px; the same flick with the
  detectors off moved it 249 px). A touch press now claims nothing until it has
  been held still for `interactionTokens.touchDragArm.holdMs`; travelling
  `slopPx` first releases the gesture to the scroller — or to a swipeable row —
  for good. A mouse and a pen are unchanged, and so is any engine with no
  touchscreen. `UI.draggable`'s `declineTouch` also reaches the engine's
  acquisition now: it used to disable Facet's own drag and leave the detector
  claiming the finger anyway, which was the worst of the two.

- ...and the hold now actually *picks the thing up*. The arm above switched the
  engine's detector on and stopped there, so a player who held a card still felt
  nothing, saw nothing, and then watched the page pan out from under the card
  when they moved. Three things changed. An armed press is now a **promotion
  already spent**: the drag session begins at the arm instead of asking for
  another 14 px of travel, so the ghost, the lift and the `dragHeld` state all
  land at the moment the hold does. The nearest scrolling ancestor is **stopped
  for the rest of an armed gesture** and handed back when the drag ends (never at
  the lift — the engine can still be dragging). And `holdMs` is **280 ms**, not
  320, which sits closer to what a phone teaches. A mouse, a pen and any engine
  without a touchscreen are still untouched.

- A surface presented before its content exists now navigates that content when
  it arrives. Whether a screen's ring is GROUPED (so Down moves by direction and
  Left/Right are a real horizontal axis) used to be settled once, at present
  time, from the tree as it stood then — so a screen whose body is behind a
  `Compose.show` or a tab, and is therefore presented empty, walked every control
  that arrived later in flat document order and had no horizontal axis at all.
  The focus graph was already grouped; only the key wiring was not.

- A `UI.PageView` carousel is ONE keyboard and gamepad stop: Left/Right page,
  Activate reaches the page's own primary action, and one vertical press leaves
  it. The page indicators stay tappable and stay the stops for a carousel whose
  pages hold no focusable of their own.
- A `UI.ComboBox`'s suggestions opener is exactly as tall as the field beside it.

- Consolidate Showcase recipes into existing family tabs with shared reset actions.
  Long removable tags scroll horizontally; progress tracks retain visible segments
  beside trailing copy at large text sizes. New-control scaffolds use existing demos.

- Setting rows retain their real switch/checkbox with optional side, hint and size.
  DisclosureGroup gains description, icon, side, appearance and size; removable
  Chips retain independent target floors and collection focus. Add the archived
  settings gear without changing earlier icon art. Small status cutouts cap their
  separator proportionally so thick theme strokes do not consume the mark.

- ProgressView gains a trailing endLabel and checked live spinner/circular size
  rungs. Omitting the rung preserves each package's authored indicator sizes.

- Add passive `UI.StatusIndicator` shapes/counts and `UI.Badge` captions with live
  status paint. Avatar presence uses the shared status shapes and cutout. Existing
  All controls Indicators gains Status and Badges child tabs. Round marks fit both
  reserved axes, counted height resolves once, and Badge caption presence stays live.

- Add `UI.AvatarGroup` keyed player rosters with shared caller-owned picture
  requests, stacked or spread faces, and one optional overflow target. Indicators
  gains an Identity child tab alongside its existing Progress demonstrations.

- Add `UI.Avatar` player pictures and UTF-8 initials with caller-owned loading,
  presence marks, localized semantic labels, and optional activation targets.

- Add `UI.Skeleton` loading silhouettes with checked bound sizing and a shared
  decorative shimmer whose lifetime follows mounted Compose branches. Reduced
  motion retains a static theme-tinted plate.

- Bound control sizes and each control's appearance family reject invalid updates
  before publishing derived geometry or paint, and recover on a legal value.
  Scroll extents require positive finite pixels or known metrics resolving to
  that range. Middle truncation returns an ellipsis for nonpositive width.
  Rich text caps authored font sizes at 100 in both published markup and layout,
  leaving caller strings intact. It measures glyphs and runs in one parse; font memos have bounded
  admission and reset with measured text. Rich inter-word spaces use their active
  font and size, including learned widths, so a large span reserves its full phrase.
  Button and Chip animation policies
  now reach the primitive plate and retain its property validation.

- Custom-child Buttons retain their theme padding when a control size is named;
  explicit padding still wins. A Button with no drawable content now refuses,
  even when a semantic name is supplied; an initially empty bound label remains
  valid. Decorative text reveals no longer block horizontal drag acquisition;
  real overlays, native child gestures and an authored scroll freeze retain
  their existing input ownership.

- Add passive `UI.ShortcutHint` keycaps, borrowing live action names and native
  key labels/images. Shared input lookup follows device class and the hint's own
  surface, including passive contexts; revision changes update bindings in place.
  Provider teardown is safe out of order. Keys use theme tint and icon sizes,
  with no decoration slot or interactive floor. Existing Actions and Adaptive
  pages now include keys/labels/link navigation and a measured container grid;
  the grid uses actual inner geometry and updates already-visible debug bands.

- `UI.Label.title` accepts Compose readables and tracked functions; visual text,
  accessible text and dumps update together without rebuilding. Semantic icon
  names use package art with the shared glyph fallback; asset URLs remain Images.
  `UI.Text.over = "media"` exposes the existing strong-contrast style treatment
  for passive text over artwork, as a construction-only word.

- Expose the native leaf capabilities the leaf specs did not reach. `UI.Text`
  takes `rich` (construction-only boolean, default false — parses the engine's
  closed tag set `b i u s font stroke br uc sc mark` plus the five `&…;` escapes)
  and `direction` (`"auto" | "ltr" | "rtl"`, mapped to `TextDirection`; absent
  leaves the class default, which is not the same as authoring `"auto"`).
  **Measurement reserves the box for the DISPLAYED text**, so a tag never widens a
  label: EVERY well-formed tag and `<!-- -->` comment is removed (measured live —
  the engine consumes markup it does not implement rather than drawing it),
  `<uc>`/`<uppercase>` content is measured upper-cased, and markup that does not
  parse is measured RAW because that is what the engine draws. A span that changes
  FACE — `<b>`, `<font weight|face|size>` — travels with the string to the per-word
  measurement key and is measured at that face (in every `weight` spelling the
  engine accepts: the nine `FontWeight` names case-insensitively and the nine
  numbers they carry, so `heavy`, `Heavy` and `900` name one face and `800` is
  `ExtraBold` rather than being rounded up to it), which is what keeps
  a marked-up label from clipping; small caps, non-ASCII upper-casing and nested
  face changes remain approximate and are named in `docs/reference/api.md`. The disclosure plate and the `reveal`
  strip render a rich label's value as rich. New public
  `Facet.richText.escape(s)` escapes `< > & " '`; escape untrusted or
  composed-in text before pasting it into markup (it is not a text filter).

- Add `UI.Text{ truncate = "end" | "middle" }`, default `"end"` (the engine's own
  end ellipsis, unchanged). `"middle"` keeps the head AND the tail, sized by
  the library's own measurer to the DRAWABLE width (the box minus the label's own
  padding, published on the solve's text facts as `padX`), re-derived only when the
  string, the face, the size, that width or the measurer's own epoch moves — the
  last is the engine's boot window, so a cut derived before the text metrics settle
  is derived again when they do. The engine has no such mode, so this is a fit
  policy rather than an adapter write. The whole value stays reachable through
  `disclose`. `truncate = "middle"` needs `lineLimit = 1` and cannot be combined
  with `rich = true`; both are spec errors.

- Add `UI.Image{ resample = "default" | "pixelated" }` (`ResampleMode` — pixel art
  stays crisp), and two new `scaleMode` words, `"tile"` and `"slice"`, each with
  a required companion geometry key: `tileSize = { width, height }` in whole
  pixels `> 0`, and `sliceCenter = { x0, y0, x1, y1 }` — the stretchable centre
  RECTANGLE in SOURCE pixels, the engine's own `SliceCenter` under the name and
  shape a theme package's art already uses, never insets — plus `sliceScale`
  (`> 0`, default 1). A geometry key without its mode, or a mode without its
  geometry, is a spec error; the geometry keys are construction-only, so the two
  new modes are authored statically and a BOUND `scaleMode` resolving to either is
  refused at the binding write (new `PropSpec.staticOnly`, checked in
  `primitive_properties` through the Compose property write). Theme-owned nine-slice chrome is unaffected.
  `UI.AsyncImage` forwards all five keys.

- Add `UI.ScrollView{ axis = "xy" }` (`ScrollingDirection.XY` — neither axis
  clamps its canvas), `scrollEnabled` (`Bound<boolean>`, default true; false
  freezes PLAYER scrolling through `ScrollingEnabled` while the offset, the layout
  and framework keep-visible are untouched), `extent = { width?, height? }` (an
  explicit canvas in pixels or a theme metric name, for a host whose canvas is a
  coordinate space rather than a content sum — **only on an axis this host
  scrolls**, because the adapter clamps a cross-axis canvas back to the window and
  accepting one would diverge live from headless). `indicators` stays ONE word for
  both axes: a `ScrollingFrame` carries one `ScrollBarThickness`, so a per-axis
  form would be a declaration that does nothing, and a table is refused. An `xy`
  host is a `"y"` host to the chrome lane, the leading-edge bleed and the
  drag-to-edge autoscroll band; its children arrange at their natural size on both
  axes; keep-visible moves both axes; and it reaches the same nested-scroller chain
  rule: pinned at the end of the band a drag is asking for, it is transparent and
  the page behind it wins. `ScrollingEnabled` has ONE writer — the paging
  mouse-drag restores the authored value at release rather than an unconditional
  `true` — and Facet's own drag-to-edge autoscroll respects a freeze.

- Add eleven common glyphs to the framework's own standard icon set: `status.info`,
  `status.success`, `status.warning`, `status.error`, `calendar`, `clock`,
  `vote.up`, `vote.down`, `person`, `chevron.first` and `chevron.last`, each with
  an ASCII fallback floor (`i`, `ok`, `!`, `x!`, `[#]`, `(:)`, `+1`, `-1`, `@`,
  `|<`, `>|`). Same generator, style, manifest and resolver as the existing
  eighteen; no control wires them in yet.

- Add optional local `controlSize` (`compact`, `regular`, `large`), `appearance`,
  and `corners` to `app.controls.Button` and `Chip`, plus Button `over = "media"`.
  Compose readables and `function(use)` bindings update size and appearance in
  place. Named sizes use theme metric paths and reserve the effective hit floor
  in layout, so compact neighbors retain separate targets. Appearance composes
  with semantic role at rest, hover and press in the default and package sheets;
  `standard` is the untagged default. Button gains construction-time semantic
  `icon`/`trailingIcon` and the required `name` for icon-only content; Chip gains
  static `leading`/`trailing` content. Omitted keys preserve existing behavior.

- Application presentation forwards the existing renderer comparison options
  `measureReuse`, `commitScope`, `structuralReuse` and `translateHosts`.
  `Facet.schema` exposes read-only constructor facts for contract tooling, and
  the supported PopupButton alias is again listed in the deprecation ledger.
- Application disposal immediately retires animated exits, toasts and auxiliary
  surfaces before releasing their state. All cleanup steps run even if one fails.
- Headless test worlds release their complete applications after each case.
  CI runs the full verifier with one worker, reports producer progress, and saves
  verification diagnostics on failure.

### One authoring model (breaking)

Facet has one way to build an interface. `local app = Facet.new(opts)` builds the
application and `local UI = app.controls` is its constructor table. A component
is a plain Luau function that returns a node. State is `Compose.cell`,
`Compose.formula`, `Compose.watch` and `Compose.cleanup`, and lifetime is a
Compose owner. Present with `app.mount`, `app.presentModal`,
`app.presentAnchored` and `app.presentToast`.

This lands before 0.11.0's first publish, so the surfaces below are removed
directly rather than deprecated for a minor version
([`CONTRIBUTING.md` §6](CONTRIBUTING.md#6-versioning-and-deprecation)). Each row
names what moved and why a caller breaks.

| Removed | Use instead | Why a caller breaks |
|---|---|---|
| `Facet.UI.<Class>({ id, children, … })` | `app.controls.<Class>("Id")({ …, child, child })` | The blueprint constructors are gone. Children are positional and the identity is the constructor name. |
| `Facet.Controls.<Name>(core, spec)` and `.blueprint` | `app.controls.<Name>(spec)`, which returns the node | A control is built under an application, not a core. Its record arrives through `ref`. |
| `Facet.View`, `Facet.component` | A plain function that returns a node | There is no component wrapper and no separate state API. |
| `Facet.mount(core, blueprint)` | `app.mount(component)` | Mounting belongs to the application, which owns the surface and its teardown. |
| `Facet.newCore`, `Facet.newPresenter`, `Facet.newEnvironment` as entry points | `Facet.new(opts)`; reach `app.environment` and `app.presenter` from it | The application builds and releases these together. |
| `core:signal`, `core:memo`, `scope:own` | `Compose.cell`, `Compose.formula`, `Compose.cleanup` / a Compose owner | State and ownership are Compose's. `:get()` reads become `:peek()` or a tracked `use(...)`. |
| `Facet.preload` | Nothing; controls load with the application | The deferred control loader is gone. |
| A composite's `dispose` and `blueprint` on its record | The owner the control was built under | `ref` publishes `{ api, dump }` only. |

New public API:

- `UI.Toggle.onChange(wanted)` requests a model change before any write. The
  model accepts by writing its value; a declined request preserves the value
  and appearance, including a checkbox's mixed state. This form accepts
  readonly Compose bindings. Cell-only toggles continue updating directly.
- `UI.activationGate(node, { closed, onOpen })`. While `closed` reads true, the
  first Activate at or under the node wakes the subtree instead of reaching what
  is under the press. `onOpen(path, meta)` receives the path that press would
  have reached. One dispatch covers pointer, touch, keyboard and gamepad.
- `Facet.motion.newTextReveal({ value, cursor?, placeholder?, policy? })`. It
  publishes `text` and `revealed`, never splits a codepoint, paints
  `placeholder` only while nothing is revealed, and lands the whole value when
  `policy` reads `"reduced"`.
- `transition.source` on `UI.When` and `UI.ForEach`. With `enter = "transform"`,
  `{ path = "…" }` or `{ rect = … }` expands the region from a shared element.
  The source rect is re-read on every painted frame, so a moving source is
  tracked. Either field may itself be a readable.
- `app.newResourceProvider(options?)` returns `provider, release`. `options.bind`
  replaces the Roblox transport.
- `app.presentToast(component, options)` runs the component inside the toast's
  own row.
- `ref` on a composite control's spec. It must be a function, and it is called
  once while the control is built, with a frozen `{ api, dump }` record.
- `UI.PageView` `summary` and `controls`. Both are booleans; `false` removes that
  row.
- `UI.VirtualList` `follow` accepts a readable.
- `UI.Slider` `step` accepts a readable.
- `UI.ComboBox` puts the field and its opener on a single row.
- `UI.DisclosureGroup` does not draw an expanded header as selected.
- `UI.ForEach` and `UI.When` are public and take schema-shaped specs:
  `items`/`row`/`key`, `condition`/`thenView`/`elseView`, and `transition`.

Focus and enablement:

- `enabled = false` means the node and its whole subtree.
- A presentation refuses when `initialFocus` names a disabled control, on every
  screen. The error lists the focusables that are available. Name a control that
  is live, or use `"first"` or `"none"`.
- The arrows cannot cross a `Grid` row whose every cell is disabled. A grid names
  each row group's `up`/`down` exit by index, so an emptied row is still the
  named neighbour and everything below it is unreachable by the arrows and the
  pad. The same content as stacked `HStack` rows is crossed cleanly, and
  `UI.When` removes the row outright. Tab is unaffected.

- Replace Signals and Facet’s duplicate scheduler and
  ownership storage with pinned Compose cells, formulas, watches, batching and
  owners. Remove the unused `Facet.Signals` export and raw-getter bridge.
  Delivery now follows dependency FIFO, and runaway watches use the native
  million-run cap with explicit re-registration after abandonment. Failed
  evaluations retain partial dependency changes. Keep Facet’s renderer settling,
  structural transitions and error boundaries. See `src/core/README.md`.
  Rebuild all bundled tutorial, showcase, reference and performance places with
  this runtime; examples use plain components, Compose cells and `function(use)` bindings.

- Unlink retired child scopes in constant time, preserving reverse cleanup order
  and cleanup-error quarantine. Large keyed collections no longer scan and shift
  the parent's ownership list for every removed row; storage tracks live resources.

- Toast rows animate into vacated positions at either screen edge. Add per-toast
  `width` using ordinary dimensions, including content-fit `hug`; default slides
  avoid CanvasGroup text rasterization, while explicit fades remain available.
  Component toast bodies inherit environment and animation services.
- `UI.ProgressView` inherits the mounted owner and presenter clock, including
  activity cycles and trails. Maintained examples adopt ordered numeric children;
  tutorials, showcase chrome and reference views use Compose state, property
  bindings and automatic ownership. New-feature scaffolding and contributor
  guidance teach the same syntax.
- Track getter-based drag enablement without invoking payload callbacks.
  NavigationStack pages and Alert content accept component descriptions.
  AsyncImage request leases follow the mounted owner, including stale-response
  rejection after unmount.
- Prevent getter indexes from retaining cyclic values after unmount; keep shared
  bindings alive through their component owner instead of a global strong value.
- Earlier unreleased Signals queue optimizations are superseded by the pinned
  Compose runtime described above.

- Native StyleRule paint transitions now default on with explicit opt-out and live reduced-motion support; `client.host` installs Roblox's easing evaluator just like `motion_driver`.

- Historical unreleased work introduced Signals 0.9.0, `Facet.component` and
  `Facet.View`. The current authoring-model change above replaces those APIs
  with Compose and plain component functions, including the showcase and
  Settings Sync examples.
- Add declarative screen, billboard and surface placement to the client host.
- Complete previously untyped public control specs, describe activation metadata,
  and check real component authoring with the pinned Luau analyzer.


- Add segmented ProgressView bars, delayed damage trails, and sized circular HUD
  gauges with readouts that adapt to preferred text size. Share transient HUD
  reservations through the presenter and add pure HUD inset/marker layout helpers.
  World anchors can retain offscreen direction and test center occlusion.
- Expose Toasts in the Showcase's Indicators pages and World markers in its Layout
  pages. Screen-anchored HUD actions demonstrate damage, healing, and notifications
  that displace nearby HUD content without taking focus.


- Expand adaptive region disclosures over their compact source. Region and
  CollapsibleView share an optional automatic dismissal affordance; the HUD
  task disclosure uses outside taps for pointer/touch and reveals Collapse for
  keyboard/gamepad navigation. The always-visible corner close remains available.

- Repair Showcase interaction routes: focused context-menu chords and a true
  right-click example, Match 3 neighbor dragging through public drag/drop,
  a standalone HUD, Corner commands with Slim band defaults, and clearer
  pending-save/rollback instructions in Settings sync.
- Keep adaptive Picker row separators on the live axis so TV selections cannot
  overlap the next setting. Theme adaptable TabView bands with control corners;
  preserve per-corner focus shapes and square skin highlights.
- Use one compositing buffer for expanded CollapsibleView content. Keyboard
  arrows now share held-navigation repeat with D-pad and thumbstick input.

- Hide the initial focus ring in mouse/touch sessions while retaining entry
  focus. Controller sessions show it immediately; navigation restores it after
  a pointer interaction.

- Keep aspect-sized children at their measured size in stretching stacks, fixing
  the oversized circular action that overlapped the Showcase sidebar. Move the
  demo layout action into the existing Showcase toolbar as a labeled Button.

- Add Picker `valueAlignment` (`start` or `end`) for labeled menu rows. Showcase
  display settings use start alignment to keep values close to their labels;
  trailing alignment remains the default for other forms.
- Remove TabView's built-in sidebar toggle. Add the bindable `sidebarPreference`
  API for nearby layouts; the Showcase supplies its demo toggle in its toolbar.

- Add Showcase display previews for Automatic, Desktop, Phone, Tablet and TV,
  with orientation and independent input selection. The reusable
  `client.environment_preview` binding retains live platform facts for restoration
  and updates mounted screens through the existing layout and focus system.

- Use adaptable outer navigation in All controls, Collections, and Motion and
  layout, with ordinary nested page tabs. Clarify that navigation role, rather
  than the screen being a game or demo, determines the TabView style.
- Reflow scrollable content when switching input changes scrollbar reservation,
  including pages whose content and viewport have not changed.
- Bound Alert's animated CanvasGroup to the card and its margin instead of the
  full viewport, reducing desktop text rasterization blur while preserving motion.
- Consolidate the Showcase picker from 46 entries to nine. All controls uses nested
  tabs for inputs, actions, indicators and navigation; Collections and Motion and
  layout combine focused comparisons. Playlist, settings and three games remain
  standalone. Individual regression scenarios remain available by workspace attribute.

- Compact menu submenus slide forward and back through the shared navigation motion. Switches paint their initial value immediately, slide without overshoot on changes, and keep label size steady when pressed.

- PageView now advances at most one page per mouse/touch swipe, settles on release, and preserves direct dot jumps and child input priority.
- Fix pixelated text in expanded disclosure groups, including the UI laboratory menu. The shared `reveal` transition animates a native clipping frame instead of rasterizing the entire list in a CanvasGroup; caret timing, focus restoration and reversal remain intact.

- Horizontal scroll hosts support desktop mouse dragging after child controls get first refusal. Ordinary clicks remain clicks, text editing and claimed drags keep ownership, and snapping waits until mouse release. PageView hides its horizontal scrollbar when page dots are shown.
- CollapsibleView transforms its plate from the compact button's current screen rectangle, with separate content fading and no text scaling or overshoot. Race settings now has one collapse action. CanvasGroup surface paint follows the stylesheet instead of forcing a transparent backdrop.

- Reuse reactive propagation work lists between completed rounds, reducing allocation
  during repeated signal updates while preserving observer order, transaction reads,
  feedback handling and isolation between cores.

- Gallery fallback cleanup releases parent controls before child scopes, preventing duplicate-disposal errors when switching demos.

- Added `Controls.CollapsibleView`: arbitrary content expands from a static or bound summary button, with modal focus, safe-area placement, scrolling and grow/shrink motion. `TabView.style = "collapsible"` supplies the selected-destination version. NavigationStack retains its Back hierarchy.

- Add `Controls.Sheet`: owner-held detents, bottom entry and dismissal, a header
  grip, focus-based sizing, and centered distant-screen presentation. Content pans
  remain scrolling; the header owns resizing. Add `Controls.PageView`: finite
  pages, dots, native snapping, and focus that follows the visible page. These
  controls reuse the shared presentation, input, scrolling and motion systems.
- A fixed-height container now bounds descendant measurement inside an outer
  vertical scroller, so nested page viewports receive their actual height.

- **A modal centres on the whole screen; content still yields the host's own
  chrome (2026-09-13).** `coreSafeInsets` carried two meanings — the device safe
  area AND any band the HOST app reserved for chrome of its own, because inflating
  it was the only vocabulary a host had. The showcase folded its demo/settings chip
  strip in there, so every alert it raised centred in the space UNDER the strip,
  visibly high-shouldered against a backdrop covering the whole window. The fact is
  split: `coreSafeInsets` means the device safe area again, and **`appChromeInsets`**
  is the host's own four-edge reservation (zero by default, the sibling of
  `appChromeRects` — that one says where the chrome IS, this one says how much
  content must clear). The content root policies add the two; `presentModal` and
  `presentCritical` reserve the device's edges alone (`renderer.attach`'s new
  `reserveAppChrome`, default true), and `bandSafeContent` still consumes the app's
  chrome per column through `platformChrome.rects`. Anything a surface RAISES —
  an anchored popover (a picker panel, a Menu, an expanded region), a disclosure
  or help plate, the room a field measures for the soft keyboard — belongs to the
  surface that raised it and takes ITS answer, so a popover over a content page
  keeps the band and one inside a modal does not. **Nothing moves for a
  consumer that never sets the new fact** — Rascal Rally's `coreSafeInsets` was
  always device-only, and its role-pick modal's centre is pinned unchanged.

- **A modal's action label is never cut before the form changes (2026-09-13).**
  `Controls.Alert`'s row/stack decision was categorical only — a width class, a
  viewing distance, a text preference — and every rung was a proxy for the question
  that decides whether a label gets cut. The labels now get a vote: the control
  measures each at the size and face a Button will draw it, adds the button's
  chrome and the row's gap, and stacks when the sum does not fit the card
  (`alert.rowFits` is the pure rung, exported beside `resolveStacked`). Measured, a
  1280 desktop row asked for 802 px of a 528 px card and ran outside it. The card
  also stops paying twice for its own frame: its `padding` yields to the panel
  slot's carved inset (down to one `xs`, never to nothing) and it declares
  nothing about its chrome lane at all: the bleed a scroller keeps for content
  that paints past its box is NETTED against the slot's carved frame at the layout
  reader (`chrome_slots.bleedLane`, read per solve, so a theme swapped under a live
  modal moves the lane with it), because that carved
  frame is the lane a scroller reserves for content chrome — 288 px of content on a
  390 px phone under Fantasy Parchment becomes 322, which is what lets "Continue"
  draw whole at the Largest preference. The primary action also stretches in the
  stacked form again: a `shortcut`-bearing action inherited `Controls.Button`'s own
  `align = "center"`, and the stack's `align = "stretch"` passed it by. `disclose`
  stays underneath all of it as the last resort it was meant to be.

- **A content-sized `ScrollView` reserves BOTH chrome-bleed edges, so the Alert
  card grows instead of scrolling (2026-09-13).** The scroll canvas is
  `contentSize + padding + lane`, where the lane is the trailing allowance that
  makes the last child's shadow reachable — the package's `chromeBleed` netted
  against the slot's own carved frame, per the entry above — while a hugging
  scroller's measure counted only the leading edge of that two-edge reservation.
  A box measured one edge short of the canvas it then publishes can never fit
  inside itself, so the Alert card overflowed by exactly the lane and showed a
  scrollbar forever: measured before the netting landed in this same release, 17 px
  under Fantasy Parchment, Fantasy Ornate and Glossy Touch and 24 px under Sci-Fi
  HUD, on a 390×844 phone with 400 px of room behind the card. A card wearing a
  carved panel frame now nets that lane away entirely (Fantasy Parchment carves 18
  under a 17 px reach), so what the reservation is still worth is the uncarved
  packages. A definite-extent scroller is untouched.

- **The Alert's severity mark is punctuation, and its title is centred
  (2026-09-13).** The critical caution mark (and an authored `icon`) was
  `targetSizes.minimum` — 44 px, the *hit floor* — beside a 20 px heading, so it
  was more than twice the height of the line it qualifies. Its default is now
  `iconSizes.medium` capped at the heading it leads — the type-height rung the rest
  of the library already spends, with the cap because a package may pitch its
  picture ladder above its type (Fantasy Ornate's `medium` is 32 against a 22 px
  heading) — and `controls.alert.iconStroke` follows the mark (a tenth of the box, floored at
  the package's hairline) instead of a spacing step. With no mark the title's text
  is centred in the card, as the message under it always was; with a mark the pair
  is centred **as a unit** and the title reads from the mark, instead of a `fill`
  title centring its line in whatever width the icon left over. A package that
  authors `controls.alert.iconSize` still wins.

- **The ten-foot overscan is a fraction of the display, not 1080p pixels
  (2026-09-13).** `effectiveOverscanInsets` derived the console profile's
  60/60/90/90 as literals, so it reserved the same absolute band from any
  viewport — 5.6%/4.7% of a television and 31%/22% of an 801×392 Studio window,
  where an alert's card resolved to 577×73 around 269 px of content. It is now
  that same profile expressed as the proportion it is (`60/1080` of the height,
  `90/1920` of the width, whole pixels). At 1920×1080 the answer is byte-identical
  to what shipped; an authored `overscanInsets` and the `"none"` opt-out are
  unchanged.

- **A materialize may declare the scale it starts from, and `Controls.Alert`
  settles DOWN into place (2026-09-13).** `transition.scale` joins `distance` as
  the scaling form's own opt-in override. It exists because of a measured engine
  fact: Roblox rasterizes text at `floor(TextSize × effectiveScale)`, so any
  `UIScale` below 1 paints every string under it one whole pixel smaller for the
  entire flight — 0.9999999 renders exactly as 0.96 does — and snaps ~5% larger
  the moment the scale reaches 1, which is when the spring settles and the
  channel finally drops the `UIScale`. On the Alert that read as the card's title
  re-flowing a quarter of a second after the card had stopped moving. The modal's
  default is now `{ enter = "materialize", plate = "fades", scale = 1.015 }`: the
  band `[1, 1 + 1/66)` floors to the same pixel for every text size the framework
  can paint, so the type lands at its final rect on the first painted frame. It is
  the **enter's** band only — an exit is the opposite instant, so it still dips out
  to the ratified `0.96` — and every other caller keeps that `0.96` both ways.

- **Transitions round (2026-09-12, informed by a transitions.dev survey).**
  Structural exits default to the new `dismiss` motion class (`exitClass` opts a
  caller into its own); `Controls.Alert` and `Controls.Menu` materialize on open
  (`AlertSpec.transition`, including `transition = false`); `transition.plate`
  acknowledges a modal/popover's fading backdrop; a keyed `ForEach`'s rows can
  arrive on a `stagger` beat; `Controls.TextInput` gains `invalid`, a caller-
  driven shake; `Controls.Button` gains opt-in `pop`; `RadialMenu` wedges bloom,
  the candidate lifts, and a commit pops; `Controls.DisclosureGroup`'s caret
  turns and its content slides in behind an optional `presenter` glide (its old
  `chevron.down` art slot is no longer requested); the `Toggle` knob settles
  with a Back overshoot; the ten-foot focus lift tweens between controls instead
  of snapping; and a `Picker`/`TabView` selection fill can wear its own strip's
  `stripCorner`. `presenter.surfaceIdNotes()` diagnoses two live surfaces under
  one id. New perf scene `control-motion` and gate `tests/motion_paint_only.spec.luau`
  price and prove every motion above stays on the paint-only presentation
  channel. Each is its own row below; this one just points at them.
- `Controls.DisclosureGroup`'s caret is one `chevron.trailing` glyph now, not a
  mounted/unmounted `chevron.down`/`chevron.trailing` pair: its paint-only
  `rotation` springs 0 → 90 as `expanded` flips, turning to point down instead of
  swapping identity. A package's `chevron.down` art, if it declared any, is no
  longer requested by this control. Content still mounts through `UI.When`, now
  with `{ enter = "slide-up", distance = 12 }`; its exit rides the structural
  default (`dismiss`) rather than declaring its own, so reopening mid-exit
  reverses through the same travel instead of jumping across it. `DisclosureGroupSpec`
  gains an optional `presenter`: when given, the toggle runs inside
  `presenter.withAnimation("container", …)` so a sibling whose position the flip
  moves — a section below sliding to make or close room — glides there instead of
  jumping; absent (the common case), the flip is instant and only the caret/content
  animate their own paint, off the ambient motion clock every mounted control
  already receives.
- Structural exits are faster than the entrances they mirror. A new built-in
  spring class `dismiss` (ζ1.0, 0.2 s) is what every exit runs on unless a
  `transition` names its own `exitClass`, so a `When`, a `ForEach` row, a toast
  and a dismissed surface all dip out at about 1.7x the pace they came in —
  transitions.dev's 250/150 ms pairing, and the one deliberately visible change
  of the round. The exit's settle tolerance is coarser than the enter's
  (`EXIT_EPS`, 2% of the transition's own progress, which is 2% alpha or 0.48 px
  of the themed 24 px slide): an exit that is visually absent should stop
  existing, and at the enter's tolerance a `dismiss` exit disposed on the flat
  500 ms cap — the same frame `container` did — rather than on its own spring.
  The bound is now "at most 2% of the travel remains, or the 500 ms cap,
  whichever comes first"; frames to dispose at 60 fps went `dismiss` 30 → 22 and
  `object` 31 → 28, while `container` and `decay` genuinely outrun the cap and
  still end on it. An ENTER keeps the default tolerance, because its settle is
  what fires the `arrive` feedback event.
- `Controls.Alert` and `Controls.Menu` materialize. A modal card and a floating
  menu popover scale 0.96 → 1 with a fade on the `container` class and dip out on
  `dismiss`; `AlertSpec` gains `transition?` so a caller can override it or pass
  `{ enter = "instant" }` to opt out, and `transition = false` is accepted as the
  framework's own "no transition" spelling (it folds to the default, which is
  what the present site already did with it). An invalid transition is refused
  where it can be seen: a static one at BUILD, named `Controls.Alert: transition:
  …` rather than the coordinator's own message, and a Readable one on its first
  read, where the refusal is recorded on `dump().lastError` and resets the
  binding instead of raising inside the observer that opened it.
- `transition.plate = "fades"` acknowledges the modal/popover shape. The
  backdrop-before-content gate reports a fade group that composes its own opaque
  plate, because `GroupTransparency` dims the backdrop and the content together
  — and an Alert's card or a Menu's popover is structurally identical to that
  defect while being exactly what a modal should look like, its backdrop being
  the scrim behind the whole surface rather than the card's own face. No tree
  read can separate the two, so the surface declares it. Honoured only for a
  fade group whose SOLE child is the plate: a plate with a sibling still reports,
  and an acknowledged shape is still recorded (under its own kind) so a reader
  can see which surfaces made the claim. `Controls.Alert`, `Controls.Menu` and
  the menu-style `Picker` declare it; nothing else needs to.
- The modal card wears the `panel` decoration slot. `Alert`'s card is a
  `UI.ScrollView` so a long message stays reachable, and `chrome_slots.classify`
  answers by CLASS before it reads `surface` — so under every skinned package the
  card classified as a scroll TRACK and got no carved frame, hairline, shadow or
  contentInsets. An unhinted `ScrollView` is still a scrollbar, which is right
  for every other one. An alert ACTION now declares `disclose` with it: a carved
  frame spends contentInsets, and a one-word label that no longer fits has
  nothing to wrap at, so it keeps a route to its whole string.
- `presenter.surfaceIdNotes()` reports two surfaces presented under one id. Every
  node path is rooted at the blueprint id, so the second surface silently takes
  over the first's paths in the adapter and the first can no longer be torn down
  by path. A diagnostic, not a refusal, once per id per session.
- `When`/`ForEach` transitions gain `stagger` (a nonnegative number of
  **seconds**, enter only): the beat between one entering row and the next, so
  a list that lands as one slab reads as a redraw instead. It is inert outside
  a keyed `ForEach` — a lone `When` branch is always the first (and only) row of
  its own batch and waits for nothing. The accumulated wait caps at eight beats,
  not the number of timers running: every row past the eighth still books its
  own hold, the rows past the cap simply all book the same duration, so a
  600-row list's last row enters with its ninth rather than half a minute
  later. Exits never stagger, a re-entry mid-exit reverses immediately, and
  reduced motion lands every row on the first frame. A ms/seconds mixup such as
  `stagger = 500` is not clamped or warned about — it holds a row absent for
  minutes.
- `Controls.TextInput` gains `invalid`: an optional caller-owned readable
  boolean whose false→true edge shakes the field once — four legs on the
  paint-only `offset` (±8px at 0/80/140/200/240ms) that never move the solved
  rect, hit target or focus order. A numeric-presentation rejection shares the
  same shake but fires on every rejected commit rather than an edge, because a
  repeat of the same rejection is exactly when the nudge is worth the most.
  Reduced motion drops the shake on both paths; the validation message is the
  only account of *why* and is unaffected.
- `Controls.Button` gains opt-in `pop`: an activate seeds velocity into a
  `reward` spring on the button's paint-only `scale`, kicking past 1 and
  springing back rather than easing to a target — the same acknowledgement
  `RadialMenu`'s commit uses, on a plain button. Fires on the initial press
  only; a pointer-held repeating button's later repeat pulses do not re-kick
  it, though keyboard/gamepad activation still pops once, on the press that
  starts the hold. Reduced motion holds the scale at exactly 1.
- `RadialMenu`: an opening ring blooms as a sequence rather than a slab (each
  wedge waits 20ms longer than the one before it, capped at 100ms total
  regardless of how many wedges the ring holds); the candidate wedge — under
  the pointer, the stick, or a direct hover — lifts 4% out of the ring; and
  committing it seeds an overshoot into that same lift so the acknowledgement
  continues the motion instead of starting a new one. Both are paint-only.
  Reduced motion opens the ring whole, keeps the candidate lifted, and drops
  the commit overshoot.
- The `Toggle` knob's settle tween switches from `Quad`/`Out` to `Back`/`Out`
  (transitions.dev's `(.34,1.35,.64,1)` shape): it overshoots by about 10% and
  returns, the way a physical switch thumb settles. The track's colour tween is
  unaffected — a colour never overshoots. Both tweens are now held and
  cancelled the same way (`handle.toggleKnobTween` beside `toggleTrackTween`),
  so a flip-flip inside 0.2s can no longer leave a stale tween racing a fresh
  one into a recycled control.
- The ten-foot focus lift (the 1.05 paint-only scale a pad/keyboard focus
  change applies) now tweens between controls instead of snapping: moving
  focus across a row used to snap each control to 1.05 and the previous one
  back to 1 on the same frame. One tween per focus change, cancelled by the
  next; the floating focus ring travels along the same tween rather than
  arriving at its destination size ahead of the lift. Reduced motion keeps the
  instant write.
- New perf scene `control-motion` (`UI-PERF-001`) prices a 30-row staggered
  `ForEach` enter, a `DisclosureGroup`, `TextInput.invalid` and `Button.pop`
  overlapping in one frame, off a scripted clock so the sample measures work
  rather than wall-clock luck. New gate `tests/motion_paint_only.spec.luau`
  proves every motion this round added — the shake, the pop, the caret turn,
  the radial lift/commit and the stagger — writes only to the paint channel,
  never the solver, and that idle after a motion settles costs nothing: zero
  clock steps, writes, transactions and rect writes for sixty more frames.

- Fixed: a count badge's number sat off-centre in its seal. Two rules make the
  plate bigger than the glyph — the intrinsic `controls.badge.minimum` on both
  axes and the row recipe's `xs` a side — and while the plate and the number were
  ONE `UI.Text`, where the number sat came from the adapter's per-class text
  defaults (`TextXAlignment.Left`, 2.5px off centre on a 20px circle in Facet
  Neutral) rather than from the control. The seal is a plate with a `Count` glyph
  inside it now, centred on both axes by the control, which also makes the claim
  measurable: a mounted badge exposes `<row>/Badge/Count` beside `<row>/Badge`.
  New gate: `tests/badge_centering.spec.luau`.
- A selection highlight wears the silhouette of the strip that holds it.
  `radii.selection:<container>` is the new token form — an authored
  `radii.selection` wins over every container, a `pill` container gives a pill by
  the pill rule, and anything else is the container's radius less one `space.xs`,
  the inset the fill floats by. A segmented picker's fill therefore sits
  concentric inside its own `radii.control` track, and a `TabView`'s adaptable
  app bar in its BAND form — a `radii.pill` capsule that previously held a
  `radii.selection` rounded rect (999 against 4 under Compact Pointer) — now
  holds a capsule. Its SIDEBAR RAIL names no container and its rows keep plain
  `radii.selection`, because a selected row sits in the middle of a column rather
  than concentric with the rail's outer corner. `newPicker` gains an optional
  `stripCorner` for a caller that suppressed the picker's own track; it refuses a
  name outside the container vocabulary and refuses to sit on a tracked strip.
  The vocabulary is the LIVE style's: a package that authors a radius of its own
  (`radii.chip`) may be named, because `radii.selection:chip` resolves under it,
  and a package may only ADD to the base names, never narrow them. An authored
  `radii.selection` no longer makes every spelling resolvable — the container has
  to exist before any clause answers for it. If the live style stops publishing
  the container — a theme swapped away from the package that declares it, or a
  READABLE `stripCorner` set to a name that never resolves — the fill falls back
  to plain `radii.selection` rather than losing its corner, says so once per
  token per control WHILE it is falling back — a swap back clears it, and a
  second departure warns again; a reactive `stripCorner` alternating between two
  unresolvable names warns on every change (the cost of a present-tense count) —
  and reports it on `dump().indicator.cornerFallbacks`, which counts what is
  falling back RIGHT NOW: it returns to zero when the package comes back, and
  stays at one for a name that never resolves. A static `stripCorner` is
  resolved once at build (through the same fallback, once) and never re-derives,
  so a later swap-away leaves it on the token it took and neither the counter
  nor the fallback moves again.
  The bar's own corner is unchanged, and so is what plain `radii.selection`
  means, so a menu card's chosen-row shade reads it exactly as before. New gate:
  `tests/selection_shape_container.spec.luau`.
- Fixed: a `TabView`'s strip touched its page at every placement but the sidebar.
  The root stack spent the theme's `m` step beside a rail and nothing at all
  above or below a band, so a strip — a plate with its own fill and corner — ran
  straight into the content under it in every theme. A placement with room for a
  gap owns a theme-sized one now (`m` beside a rail, `s` above or below a band),
  spent as a metric name so a package's spacing and a ten-foot display's scale
  both reach it; `bottomBarCompact` — the placement the policy picks when the
  screen is too short for an ordinary band — spends none, because the chrome
  gives way before the content does. New gate: `tests/tab_strip_gap.spec.luau`.
- Fixed: a `UI.Divider` painted the theme's hairline COLOUR at full opacity while
  every stroke in the sheet painted the same token at `hairlineOpacity` — so a
  segmented picker's seam, a menu's row rule and any list separator were a solid
  bar of a colour meant to be washed (Facet Neutral's hairline is pure white).
  Both paint paths spend the theme's own `hairlineOpacity` now, so every package
  inherits a subtle seam and one authored number still moves strokes and dividers
  together. The background-transparency preference does not patch it — a divider
  is a border. New gate: `tests/divider_hairline.spec.luau`.
- Fixed: the swipe-actions gallery example's List surface had lost the plate
  behind its rows in every theme. `6a65baef` made a declared surface outrank the
  class map, and these rows had been drawing their plate out of exactly that
  accident while declaring `base` — the app background, which is also what the
  screen behind them declares. The plate is a node of its own now (`ListPlate`, a
  stack that fills the band and holds the scroller), so one `panel` recipe frames
  the pane a player looks at and carries the shadow, and every row's own fill
  reads against it; the row's sender line fills and truncates, so the panel's
  carved border comes out of the name rather than out of the box. The card gives
  way only when the band MEASURES too small for the package's own carved frame
  plus one tappable row — a package that carves nothing (Facet Neutral among
  them) therefore never loses its plate at any size, and a theme swapped in place
  re-measures rather than answering with the previous package's band. It cannot live on the
  ScrollView itself — `chrome_slots.classify` answers for a ScrollView's own chrome (its
  SCROLLBAR) before it reads the declared surface — so the gate pins the SLOT
  beside the surface name. New gate: `tests/row_plate_paint.spec.luau`.
- Segmented picker, shape round (2026-09-12, user visual review). The strip is
  ONE strip: only its outer ends round, with the theme's `radii.control` rather
  than a hard-coded pill; the inner segments are square and touch, with a
  hairline seam between each pair (hidden beside the selection, because the
  sliding fill paints behind the strip); the fill wears the silhouette of the
  segment it is on; and the track plate takes the same outer radius. The same
  rule turned 90 degrees is the vertical rail's. `selection_indicator` gains
  `segmentCorners`, and its default corner is now `radii.control` — Pixel Quest
  draws a 4px selection and Fantasy Ornate a 6px one where both drew a capsule.
  `corner = "pill"` remains the caller's opt-in. A `TabView` strip
  (`track = false`) keeps its own spacing and gains only the theme radius.
- A ten-foot row list gives every row one silhouette, chosen or not, and lifts
  the FOCUSED row by a paint-only 1.05 on the presenter's spring (reduced motion
  places it on the frame it arrives). The solver, the hit target and the focus
  order do not move, and the rows' own gap is wider than the lift.
- `newLevelPicker`'s `bar` segment plates a track and rounds only the run's two
  ends, the same language the segmented picker speaks. `newRating` (glyph) is
  unchanged.
- Fixed: a segmented strip's segments were the same height only while their
  labels agreed about truncating — at the Largest preference under Fantasy
  Ornate one reserved its disclosure plate and the other did not, solving 108px
  beside 66px. The option stack stretches its children on the cross axis now.
- `Controls.Menu`'s anchored panel is now one card: flat `plain` rows with no
  radius of their own, one hairline between adjacent rows, and a selection fill
  that is the row's own surface, clipped to the card's radius at its two ends.
- A selected menu row's label is now painted for the fill it sits on
  (`accent`/`onAccent`). It previously kept `$Content`, which read at 2.37:1 on
  Glossy Touch and 2.46:1 on Pixel Quest. New gate:
  `tests/selection_contrast.spec.luau`.
- `Controls.SplitButton`'s touch form shows a trailing `chevron.down` hint, so
  the long-press menu is discoverable. Still one hit target, one focus stop,
  one activation.
- A control's content line is centred: an icon beside a word in a `UI.Button` no
  longer rides the top of the line under a package whose icon rung is taller
  than its control type (Pixel Quest 6px, Fantasy Ornate 4.5, Glossy Touch and
  Classic Desktop 2.5).
- A closed picker trigger paints its package's `control` plate instead of the
  row-selection wash. It declares `selected` so its open state can light up, and
  the slot classifier read that declaration as a state.
- A picker popover grows to fit its widest row's full label, measured through
  `text_metrics` and counting the card's frame, the scroller's shadow reserve
  and the row's real padding. Pixel Quest asked for 182px where 280 was needed,
  leaving 78px for a 176px word.
- `UI.ScrollView` accepts `chromeReserve` (`"auto"` default, `"none"`): the
  lane a scroller keeps for content chrome that reaches past its box —
  `max(0, chromeBleed − the slot's own carve)` since 2026-09-13
  (`chrome_slots.bleedLane`), because a carved frame already holds content that
  far from the clip edge. The
  picker popover's list declares `"none"` — its rows are plain and its check
  draws inside its box — so the list runs to the card's content box and the
  chosen row's fill spans the card less one `xs` a side with the theme's
  control radius (Glossy Touch had it floating 31px inside the card), and
  two rows that fit no longer show a scrollbar (the region's content grew by
  two lanes while the host grew by one). Pinned in `picker_sweep`.
- `radii.selection` (theme metrics): the highlight shape — the segmented
  picker's sliding fill, now an inset rounded rect on all four corners floating
  inside a track that keeps `radii.control` on its ends, and a menu card's
  chosen-row shade plus the focus ring on that row, clipped to the row's place
  (first row rounds its top, last its bottom, middle rows square, an only row
  all four). It follows `radii.control` unless a package authors it; Pixel
  Quest and Fantasy Ornate set `0` in their own metrics. Documented in
  `docs/guide/09-custom-themes.md`, `05-styling.md` and `api.md` themes.
- `controls.popup.shadeInset` (theme metrics, optional, default 0) picks the
  menu card's row-shade form: flush (edge to edge, clipped to the row's place)
  or, for a positive inset, floating (that far inside the card's edges, all four
  corners on `radii.selection`, the row under it inset the same so the focus
  ring matches). Glossy Touch authors `selection = 10` and `shadeInset = 4`.
- The picker card keeps no padding of its own (Glossy Touch stacked it on the
  frame's insets); rows run to the card's content box.
- `menu_recipe.row` accepts a Readable `indicatorEdge`; the picker popover
  passes one, so the check follows the live interaction class instead of the
  class at build time.
- The chosen row in a picker popover paints its label with the theme's
  `onSelected` partner (Glossy Touch 2.37:1 → 7.03:1, Pixel Quest 2.46:1 →
  6.04:1). `onSelected` is a new tint role: the decision `$OnSelected` already
  carried, reachable by a child `UI.Text` that no `TextButton`-scoped sheet rule
  can descend into.
- Gallery: the selection and action demos caption every control ("Picker ·
  segmented", "Split button", …) so a capture names what it shows.

- Picker menu, third visual round (2026-09-12, user review of the side-by-side
  against the reference platform). The popover is ONE card: the panel owns the
  corner and the stroke, the rows are plain with a hairline between them, the
  chosen row carries a subtle `controlSelected` fill, and the check sits at the
  row's trailing edge on a touch surface (leading on a pointer or pad). The
  touch form row is one row — title and value + chevron on one line, value and
  chevron flush trailing, no box, the whole row the tap target; a pointer or a
  pad keeps the boxed pop-up button beside the title, centred on its line. The
  chevron is centred on the value's line everywhere, and the picker sweep pins
  both centres to a pixel. `menu_recipe.row` gains `indicatorEdge`.

- `UI.Button` accepts `disclose` (construction-only), the same full-value
  path a one-line `Text` or a Toggle label carries: a squeezed label reaches its
  whole string through the large-text plate. Every segment of a sliding picker
  strip declares it, which closes the LT-G4 gap the large-text sweeps recorded
  (an option label with no route to the whole string); a TabView's tab strip
  declines it (`track = false`) because the bar's own compact ladder owns
  overflow there.

- **Icons: no shipped theme paints a character where a picture belongs.** The
  radio and checkbox indicators, the pop-up button's chevron pair and the tick
  now resolve to real art in every shipped package. Facet's own icon set gained
  the three selection marks; Pixel Quest gained the eight names it was missing,
  which is what licenses it to keep declining the framework set; Glossy Touch and
  Compact Pointer no longer decline it. `tests/icon_coverage.spec.luau` fails a
  package that leaves any control-requested name on the ASCII floor, which stays
  an engine recovery path. `tools/upload_icons.py --theme` uploads a theme
  package's own art headlessly.
- Picker visual round (2026-09-11). The segmented style is one plated track
  (the `control` surface every package skins) holding equal pill segments with
  the bar sliding beneath them; a segment carries a label only — a described
  option is refused on a declared segmented picker and steers the automatic
  ladder to a row form; the ladder also estimates the band from facts (glyph
  count x the text size the preference and the ten-foot scale make, plus the
  theme's padding) against the control's own measured offer and falls to
  inline/menu when a pill would not fit. The menu popover hugs its widest row
  between the trigger's width and the safe width, hangs from the visible
  trailing edge (a plain touch trigger's chevron) with an `xs` gap, keeps the
  screen's content inset, grows out of the corner it hangs at, and the trigger
  stays selected while it is open. `presentAnchored` gains `anchor.margin`; a
  transition gains `pivot`; Menu popovers take the same gap and margin. The
  overflow sweep now runs the largest text preference at the widest viewport
  under every shipped package as well as at the narrowest.

- Performance: a scale-only presentation transform write (every frame of a
  `materialize` transition, every animated scale) re-applies the written node
  only; the subtree is walked only when the offset half moved. Headless, the
  picker menu open/close scene halves (3.1 -> 1.4 ms) and the radial menu
  open/close drops 14%. `tests/presentation_transform_subtree.spec.luau` pins
  the rule in both adapters.
- Performance lab: a nineteenth workload, `transient-surfaces` (alert present,
  picker menu open, radial menu open), with fixtures shared by the headless
  scenes `alert-present-dismiss`, `picker-menu-open-close`,
  `picker-segmented-textsize` and `radial-menu-open-close`. Seven trend budgets
  tightened after earlier improvements; none loosened. The round's numbers and
  booked levers: `docs/plans/2026-09-11-perf-round.md`.
- Picker gains `style` — `automatic` (default), `menu`, `segmented`, `inline`,
  `radioGroup`, `navigationLink` — the reference platform's picker styles over
  one selection model. The automatic style resolves from published facts: a
  nearby touch or pointer surface gets the menu family (one integrated trigger
  carrying the value and an up/down chevron, the options anchored to it with a
  materialize transition, the current value focused and check-marked, no Cancel
  row; a titled picker is a form row that stacks at accessibility text sizes;
  a gamepad or a long list on a compact or touch surface presents a sheet); a
  ten-foot display gets a focus-navigable strip; a nearby gamepad keeps a short
  strip and folds a long list, or any list on a compact screen, into the menu.
  A searchable list (`query`) is the navigation link. `presentation` is the
  deprecated spelling of `style` (`radio` reads as `radioGroup`), declared in
  `DEPRECATIONS`; `Picker.resolveStyle(facts)` is the pure ladder.
- `Controls.PopupButton` / `newPopupButton` are deprecated (removal no earlier
  than 0.12.0): the popup engine moved to `src/controls/picker_menu.luau` and
  both names build on it. Migrate a value to a `Picker` menu style, a searchable
  list to `navigationLink` with `query`, and a `selectedValues` set to a `Menu`
  with `checked` items.
- SplitButton is one button with a long-press menu under touch and a joined
  edge-to-edge split under a pointer or gamepad; the forms follow the live
  interaction class. `dump().form` reports which is on screen.
- New framework icon `chevron.up.chevron.down` (the pop-up button's stacked
  pair), generated and uploaded with the standard set; the menu row recipe
  gains the check-only `mark` indicator.
- Showcase: Choices and filters is built on the Picker's styles (radio group,
  segmented, the automatic form-row menu, a searchable navigation link) and a
  checked `Menu` for filters; the section switch and the Actions and menus idiom
  switch declare `segmented`. The Cartwheel reference app's sort, axis and
  ingredient popups are Pickers.
- Alert actions follow the platform alert rules instead of author order: the
  cancel action leads a row and closes a stack; a stack (full-width buttons) is
  used with more than two actions, on compact widths, on ten-foot displays and at
  accessibility text sizes. The action region is one keyed `AdaptiveStack`, so a
  live width/distance/text flip moves the mounted buttons rather than remounting
  them. Alert accepts `env` like the other adaptive controls. Action paths are now
  `…/Card/Actions/Order/[<id>]/<id>`.
- Directional search inside inferred layout groups shares the section scorer
  (one beam/distance rule, not two copies).

- A node that declares a surface is no longer given a theme package's control
  decoration by its class. A `Button` or `Toggle` declaring `surface = "base"`
  or `"scrim"` fell through to the class map and was skinned as a control —
  plate, corner and, under a package with depth, the control slot's shadow,
  which reaches outside the node and painted onto whatever sat next to it. Every
  other declared surface already decided the slot; the class map now answers
  only for a node that declared none. A node carrying a `selected` prop still
  reaches the selection slot whatever surface it declared.
- A virtualized list or grid's full-bleed row hit target no longer takes a
  control surface when it paints no selection. It carried no label, no icon and
  no image, yet wore the installed theme package's control plate, corner,
  gradient and shadow — and since rows sit back to back, that shadow painted as
  far into the neighbouring rows as the package's `chromeBleed` reaches. A list
  that paints selection keeps the surface its selected row is drawn with, so
  selection treatment is unchanged.
- Add Controls.Alert for content-sized confirmations, adaptive action rows,
  presentation/data/error bindings, safe cancel focus, icons, severity and an
  optional suppression choice. Showcase confirmations and Delete Save use it.
- Adaptable tabs retain a complete TV tab strip across destination changes and
  use a shared sidebar/body gap. Distant viewing changes navigation placement
  even with mouse input; Actions and menus reflows its content sections.
- Measure capped hugging containers at their declared width limit so wrapped
  text contributes its full height before actions are placed. Hugging scroll
  containers also reserve the leading space their themed shadows require.
- Match integer fill allocation during measurement and arrangement, preventing
  aspect images from exceeding their measured columns by a pixel.
- Let pointer zones inside native scrolling containers pass touch scrolling
  through while retaining horizontal swipe gestures and their normal input capture.
- Release completed press-only scale modifiers so native themed shadows return
  after taps, including the first row after changing List and VList modes.
- Release unread-marker bindings when Row Actions List and VList rows unmount.
- Keep the virtualized table toolbar scrollable on narrow phones with large
  text; remove its resolved themed-overflow waiver.
- Remove the forced line break in the Journey details “Travel light” heading.

- Framed image geometry commits no longer reread or rewrite unchanged native
  paint. Origin-only moves preserve the crop, while source, theme and modifier
  changes retain their existing synchronization. Performance Lab now includes
  the same 24-image adaptive navigation inventory used by the headless bench.

- Keep adaptable navigation controls and their ScrollView mounted across nearby
  top/sidebar changes. ScrollView axis now accepts a readable value and updates
  directional navigation and active named travel without restoring cancelled focus.
  Scan presentation-path separators directly instead of visiting each character.

- Navigation performance: rendering and input share a live path lookup that skips
  unrelated subtrees. Buttons without a possible busy state omit progress regions
  and their reactive state; declared busy buttons retain their spinner behavior.
  The one-time input binding registry no longer strongly retains retired control
  bundles, while reusable blueprints keep their once-only binding behavior.

- Adaptive follow-up: explicit scroll-to-focus arrival and removed-target visibility exits;
  opt-in content shoulder paging, bounded value hold-repeat, and layered Table edit Back.
  Navigation flow now demonstrates adaptive search with query/focus restoration.
  Theme navigation chrome keeps ornate capsules light. Completed partial feedback
  no longer causes a redundant next-refresh layout pass. Agent guidance applies
  the Facet-first implementation order to layouts and controls.

- Narrow nonstructural geometry feedback to its changed subtree, preserving full-layout fallbacks. Cache selection-indicator geometry by structural/layout changes, pair reordered identities with their measured rectangles, and remove image-button focus polling from idle refreshes. Sidebar commands retain focus when the effective navigation placement does not change.

- Fit radial label height as well as width inside thin rings; measure compact icons against their actual padding so ten-foot action and navigation artwork remains usable.

- `UI.Image.imageFraming` adds source focal-point crop, fit, stretch, unscaled
  pixels and an explicit scale multiplier through the existing image/background
  path. Reactive framing is paint-only. Game-authoring guidance now calls for
  game-specific themes, real icon artwork and deliberate background framing.

- Add opt-in `TabView.style = "sidebarAdaptable"`: tablet toggle, pointer sidebar, distant-screen collapsed destination pill, and stable page identity when navigation moves.
- Picker/TabView badges reuse measured, wrapping row content so image-backed counts do not cover labels; `onAccent` tint keeps custom selected labels paired with the theme palette.
- Extend existing `Controls.Button` with image, aspect ratio, and subtitle content; reserve padded focus enlargement space, animate lift with the shared interruptible motion clock, and coordinate image highlight with persistent captions. Reduced motion retains the ring without lift.
- Use single-panel automatic gamepad menu hierarchies. Update the Showcase, agent/control-selection guidance, ornate-theme checks, and the 24-card adaptive-navigation performance workload.

- Navigate inferred nested layouts using resting geometry, including bound stack-axis changes; preserve declared grid, virtual collection, and radial topology.
- Add `viewingDistance` (automatic/near/ten-foot) and `distanceProfileSource`, with a Showcase setting. Explicit distance applies across typography, metrics, density, focus, and safe areas independently of controller connection.
- Restore valid tab focus paths on navigation entry without retaining tab content; `TabView.restoreFocus = false` allows a fresh task entry. Long automatic gamepad menus and popups use the existing sheet presentation.
- Keep Pixel Quest selection ornaments inside their content reservation; wrap the existing Showcase action row when theme or text needs more room.
- Bound held-navigation catch-up to three steps per frame. Expand controller and Pixel Quest theme verification to nearby handheld screens.

- Round native presentation offsets and size deltas before writing pixel geometry, removing the final pixel snap when Showcase animations settle.

- Blend focal launchers back in on the radial exit clock, including interrupted closing; hand off lists without overlapping rows. Measure navigation arcs against the themed icon square so large Close artwork stays inside its plate. Fit custom compact images against their actual rendered rectangle, including responsive image fallback. Keep explicit image content visible when a composite suppresses its theme plate, without borrowing the plate’s shadow.
- Give Pixel Quest, Compact Pointer, and Glossy Touch the actual tinted search image while preserving their other glyph choices. Expand world-anchor design guidance for proximity actions and choosing between object, corner, and single-action UI.

- Change unpublished `client.world_anchor.padding` from pixel spacing (default 12) to a relative radius fraction from 0 to 1 (default 0.15). Remove its pixel `minimumRadius` option; use RadialMenu’s theme-based `clearance` for a minimum opening. Existing pixel padding callers must migrate to a fraction.

- Preserve runtime native theme sheets across character respawns in a shared, non-rendering ScreenGui with `ResetOnSpawn = false`. This fixes lost styling after revisiting the Quick actions Item scene.

- Add public `client.world_anchor` for Part, Model, and avatar bounds projected into radial anchor/clearance data on the host frame. Radial menus follow measured radius, freeze it during selection, and support `launcher = false` and `api.isVisible` for proximity prompts without overlapping launchers. Add the real-world Item example to Quick actions.

- Preserve themed circular launcher borders outside their animation content bounds. Measure radial preview space and compact bands around fixed clearance so the Fantasy Ornate character ring fits small portrait offers.
- Keep the corner navigation disc visible through dismissal, crossfading Back/Close into the launcher icon and smoothly returning to its size; support reopening during retirement.
- Compact radial geometry before choosing a list on small landscape surfaces, preserving minimum touch targets, directions, and explicit focal clearance.
- Keep radial opening/closing centered on its launcher or focal anchor through the presentation offset channel, including all four corners and interrupted animations.

- Add `UI.Button.focusVisual` for composed controls that paint their own focus treatment; radial selection highlights the outer circle/wedge while image-only buttons retain the content outline.
- Center radial compact representations and use semantic navigation icons. Animate opening/closing rings in one coordinate space; fade list fallback fully before restoring its launcher.

- Allocate radial list rows at their themed button height so adjacent rows cannot cover the keyboard focus outline; use standard list navigation to scroll the focused row into view.
- Inset focus rings beneath any clipping ancestor, including scroll containers beyond an intermediate layout or motion host.
- Keep the native scaling pivot at an explicit settled scale of one, removing a final-frame pixel snap while preserving scale cleanup when the transform clears.
- Refine radial menus with single list navigation, closed arc borders, image-only button surfaces, concurrent parent-origin submenu motion, and a four-corner Showcase selector. Add control-choice guidance for UI-building agents.
- Correct radial-menu touch/list activation, shared surface/content retirement and replacement transitions, centered skins/icons, ring/corner navigation, uniform slim bands, and contrasting outlines. Add direction-based gesture selection for cramped layouts.

- Add `Controls.RadialMenu`: native wedges and corner buttons, configurable content-fitted arcs (both axes by default), compact icon/text labels, mixed ring/page hierarchy, captured gestures and semantic keyboard/gamepad input. Add the curated Quick actions Showcase demo.
- Add the Path tint alpha channel via a reused UIGradient; document that CanvasGroup does not fade Path2D.
- Fix scaffold runner-signature drift and remove the type checker's stale hardcoded control count.

## [0.11.0] — not yet published

- `Controls.NavigationStack` adds a caller-owned observable route path, root and
  destination builders, push/pop/back/root operations, page scope cleanup and
  legal focus restoration through the existing presenter contribution seam.
- Navigation pages share a clipped viewport. Pure horizontal slides travel the
  stack's width, reverse on Back and preserve motion when interrupted; outgoing
  pages no longer create a second vertical layout slot. Structural transition
  declarations can be readable and are sampled on enter/exit.
- Interrupted transitions release paint channels no longer used by the next
  form, so changing a fade to a slide cannot leave content partly transparent.
- The confirmation example uses an content-sized horizontal actions with compact-label fitting, centered
  labels and a primary Cancel action with explicit initial focus.
- Search clear icons and checkbox marks are centered through the existing layout
  rules, including theme changes and larger text.
- Search fields use a tintable magnifying-glass asset in the existing `facet:search`
  icon slot. Preferred compact icons reserve their theme size, including Back.
  Selected labels keep aligned with their selection pill during ten-foot focus.
- Horizontal `firstTextBaseline` / `lastTextBaseline` alignment composes with
  nested and wrapped layouts. Theme typography supplies semantic guides; no
  engine glyph-baseline measurement is claimed.
- `UI.Spacer.minLength` adds a reactive, theme-compatible main-axis floor.
- `motion` clocks can bind numeric animation values to observable state with
  `clock:animate`, including existing theme tint blends and reduced motion.
- The default theme is **Facet Neutral**, package ID `facet-neutral`. Replace
  saved or configured `studio-neutral` identifiers with `facet-neutral`.
  The theme's colors and geometry are unchanged; its identity and content stamp
  change. `themes.neutral()` and `themes.neutralPackage()` keep their names.
- The Showcase journey demonstrates navigation, text guides and flexible gaps;
  the controls guide describes current controls and their configuration.


### Added

- **`Button.role = "onIndicator"`, the label-only role.** The other three button
  roles name a fill *and* the colour that reads on it; this one names the colour
  alone, because the plate is painted by something behind the button — an accent
  surface such as Facet's own sliding selection indicator. Its rule is
  `TextColor3 = $OnAccent`, the theme contract's one gated partner for `$Accent`,
  and it brings no background, so the chip it sits on is still the only plate on
  screen. See [api.md — semantic roles](docs/reference/api.md#button).
- **`enabled` and `tint` on the layout containers, where they apply to the whole
  subtree.** `enabled = false` on a `Screen`, stack, `ScrollView`, `Grid`,
  `Anchor`, `AdaptiveStack` or `Composition` disables everything under it: every
  descendant leaves focus order — both derivations, the linear one Tab walks and
  the directional one the arrows and the pad walk — refuses Activate on every
  input class, and takes no pointer, touch, drag or secondary action. `tint` on
  the same containers is the continuous colour their subtree paints with. Both are
  reactive, and a change re-solves in place rather than rebuilding.
  See [Inherited properties](docs/reference/api.md#inherited-properties-enabled-and-tint).
- **A themed disabled state, `facet-state-disabled`**, and what it paints is
  exactly one rule. The engine's `:NonInteractable` state exists only on the
  classes it considers interactable, so Facet Neutral and every theme package
  emit `Disabled subtree text`: a `TextLabel` carrying the tag is dimmed to that
  theme's own `disabledContentOpacity`. **Text only** — image paint is legal in a
  theme rule only inside a nineSlice chrome recipe — and the tag reaches the four
  classes that consume it (`Button`, `Toggle`, `TextField`, `Text`) rather than
  every node, because writing to a container the renderer had elided materializes
  it permanently. A `tint` that declares its own `transparency` claims that
  property and outranks the dim. A presented surface (modal, toast, menu, popover,
  anchored sheet) is its own root and inherits neither channel. All four limits
  are stated in [api.md](docs/reference/api.md#inherited-properties-enabled-and-tint).
- **A Roblox Package distribution channel.** Facet is now published as one Roblox
  Package asset, which is the recommended install for creators who work in Studio
  without a file sync. The asset id does not exist yet; it is recorded in
  `package/facet-package.json` when the asset is created, and the maintainer
  interface is `tools/package.sh` with [`package/README.md`](package/README.md) as
  its reference.
  Installing, updating, and version checking are described in
  [guide 8](docs/guide/08-without-rojo.md).
- **A standalone consumer project**, `examples/consumer/`, that builds the
  five-minute screen from the public API alone and is proved headlessly by
  `tests/consumer_standalone.spec.luau`.
- **Public project files**: `LICENSE`, `THIRD_PARTY_NOTICES.md`, this changelog,
  [`CONTRIBUTING.md`](CONTRIBUTING.md), [`SECURITY.md`](SECURITY.md),
  [`AGENTS.md`](AGENTS.md), a `skills/use-facet/` skill, and continuous
  integration plus issue and pull-request templates under `.github/`.

### Fixed

- **An authored hide that moves during a solve now lands on the next drain.** A
  `hidden` flip made from inside the presenter's geometry feed was swallowed
  for the life of the surface, so a segmented `Picker`'s selection indicator
  never painted until a real slide ticked. The renderer now forces the solve
  that owes the walk when the re-read value actually moved.
- **A `UI.Path`'s stroke is born at, and follows, its node's paint order, and its
  geometry is uploaded once.** The screen target never gave a `Path2D` its
  `ZIndex` and re-sent unchanged control points on every rect write.

### Changed

- **A segmented `Picker`'s selected option is readable on its own chip.** The
  sliding pill paints `$Accent` behind the option; the option's label kept
  `$Content`, the colour chosen to read on `$Surface`, and on a package with a
  saturated accent the pair measured 1.55:1 against a 4.5 floor. The option the
  pill covers now carries `role = "onIndicator"`, so the label takes `$OnAccent`
  and travels with the selection. Nothing else about the control moves: the
  option still declares `surface = "plain"`, still carries no `selected` tag, and
  the chip is still the selection paint. The `underline` indicator is unaffected —
  it paints a tint rule on the segment's far edge, not a plate under the label.
- **`present()` refuses when `initialFocus` names a disabled control**, on every
  screen rather than only some. The flat focus derivation always refused —
  "initialFocus 'X' names no focusable on this surface", listing the ones that
  are — but a screen with horizontal structure took the grouped derivation, which
  did not exclude a disabled control at all and so presented happily with the
  ring sitting on it. The two agree now, and the error is the same one. **If you
  focus a primary action that starts disabled until a form is valid, name a
  control that is live, or use `"first"` / `"none"`.**
- **The arrows cannot cross a `Grid` row whose every cell is disabled.** A grid
  names each row group's `up`/`down` exit by index, so an emptied row is still the
  named neighbour and the move lands nowhere — everything below it is unreachable
  by the arrows and the pad. This is exactly what a fully `hidden` grid row has
  always done; what changed is that `enabled` is now inheritable, so the shape
  reaches an ordinary settings screen. **The same content as stacked `HStack` rows
  is crossed cleanly**, and `UI.When` removes the row outright. Tab is unaffected.
- **`enabled = false` now means the node AND its subtree.** On `Button`, `Toggle`
  and `TextField` the property is unchanged for a leaf; what is new is that the
  state is inherited, and that it cannot be undone from below — an ancestor never
  re-enables a node that declares `enabled = false`, and a descendant never
  re-enables itself inside a disabled container. A focusable `Grip` inside a
  disabled subtree now leaves focus order too, which it did not before: `Grip`
  carries no `enabled` of its own, so nothing had ever asked the question for it.
  A `Button` is a container, so **a disabled button's custom content is now
  disabled with it** — its own children wear the theme's disabled state instead
  of keeping full contrast beside a plate the engine had already dimmed.
- **Facet is licensed under the MIT License.** Material this repository did not
  create is listed with its own notice in
  [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
- **Verification runs in four named tiers** — affected, fast, full, and release —
  through one command, `tools/verify.sh`. An ordinary change runs affected or
  fast; a change about to merge runs full; a release runs the release tier.
  `./run-tests.sh` and `./run-tests.sh --fast` still work and still mean the same
  thing.
- **The public documentation was refreshed end to end**: the README, the guide
  index and capability catalog, installation and upgrade instructions, the
  extension playbooks, and every link that pointed at internal material.

### Removed

- **The vendored copy of another reactive library, and its adapter.** Both were
  bake-off arms kept from the comparison that chose Facet's own core; neither
  ever shipped in Facet's runtime, model, or Package. Facet used its own core
  at that point; the current unreleased runtime uses Compose as described above.

## [0.10.0] — not yet published

The version this tree reports as `Facet.VERSION`. It has not been published, so
the deprecation window begins at its first release. Until then the register below
is the record of every behavior change riding this version. Recording the change
is what makes a breaking change legal before a version's first publish
([`CONTRIBUTING.md` §6](CONTRIBUTING.md#6-versioning-and-deprecation)).

### Added

- `Facet.Controls`, a frozen namespace of typed control constructors called as
  `Facet.Controls.<Name>(core, spec)`. Every older `Facet.new<Name>(Facet, core,
  spec)` builder still works and is listed in `Facet.DEPRECATIONS`.
- The world-fixed surface render target, `client.surface_target`: the same flat
  two-dimensional Facet screen on a `SurfaceGui` a player walks up to. It is a
  flat world target, not a spatial one — geometry in front of it blocks input,
  and it pins `AlwaysOnTop = false` so that stays true.

### Changed

- **Adaptation answers for itself.** Controls that need device facts and cannot
  find an environment now refuse to construct instead of quietly assuming a
  large screen with a pointer. A `UI.Grid` given neither `columns` nor
  `minColumnWidth` lanes itself from the box it was given, and
  `UI.AdaptiveStack` requires its `axis`.
- **The ten-foot display class scales type, theme metrics, and paint**, so a
  screen written the ordinary way is legible on a television.
- **Roblox `StyleSheet` paint is the default render path** rather than an opt-in.
- The library is named Facet, and its call shapes moved with the name.

### Behavior changes riding this unreleased version

Each row names the surface, what it did before, what it does now, and why the
move breaks a caller. A change to what the library promises is landed by adding
its row here in the same commit.

1. `UI.AdaptiveStack.axis` was optional and defaulted to `"y"`; it is now
   **required**. A bare `UI.AdaptiveStack{…}` was a permanent vertical stack and
   now raises at construction.
2. `UI.Grid` given neither `columns` nor `minColumnWidth` laid out one lane at
   every width; it now lanes itself from the box it was given
   (`minColumnWidth = "intrinsic"`). A bare grid silently re-lays out: the same
   six cards go from one column to two, four, six, nine, five, or seven across
   the audited viewport combinations.
3. `newPicker`, `newMenu`, `newPopupButton`, `newTabView`, `newTextInput`, and
   `newVirtualList` with `itemExtent = "cards"` each **refuse to construct** when
   no environment can be found. Each previously substituted the large-screen,
   near-distance, no-cutout answer in silence. The refusal replaced wrong
   behavior rather than working behavior: zero of the seventeen shipped `Picker`
   sites had reached the adaptive default.
4. `adaptive.navPlacement` on a tablet answered `bottomBar` and now answers
   `topBar`. A documented policy answers differently for a real device class;
   six shipped assertions were re-pinned because they had asserted the defect.
5. `adaptive.columnsFor` at the ten-foot distance was uncapped and is now capped
   against the wide breakpoint, so a television gets fewer columns than a desktop
   where it used to get more.
6. Unauthored text on a `Large` display scaled only at its authored size; the
   whole type ladder now scales by 1.5. Every screen written the natural way is
   1.5 times larger on a television.
7. Every theme metric on a `Large` display was unscaled and is now scaled by the
   type floor's own factor, so control heights, spacing, icon sizes and the 44px
   hit floor all move on a television.
8. `UI.Composition`'s content lane at the ten-foot distance took an uncapped
   share and is now capped at the lane measure times the metric scale (900px). A
   shipped composition re-measures on a television and nowhere else.
9. `newTable` narrower than its columns clipped; it now **collapses** a column by
   priority and discloses it. Shipped tables re-lay out at the compact size
   class, and a `fill` column's `minWidth` is honored — one playlist column went
   from 30px to 66px.
10. `newTable` selection and edit-mode keys had no modifier semantics: an arrow
    key replaced the selection. Control or Command now moves without selecting,
    Shift extends, and on a table with no `onPrimaryAction` a device Activate
    toggles.
11. A horizontal `UI.ScrollView`'s focus ring ran vertically and now runs
    **horizontally**: Left and Right step the rail, Up and Down leave it. That is
    the opposite of what shipped.
12. `newTabView` and `newPicker` band placement parked in the band's corner and
    are now centred in it. Shipped geometry moves on three placements.
13. The library's own name and call shapes changed: the require path is `Facet`,
    and `Facet.newTable(Facet, core, spec)` became
    `Facet.Controls.Table(core, spec)`. Nineteen call shapes moved; every old
    builder still works and is in the deprecation ledger.
14. The gallery example's `showcase_chrome.TOGGLE_GAMEPAD` was `"ButtonY"` and is
    **removed**. The showcase chrome bound the gamepad toggle to `ButtonY`, which
    is `newMenu`'s own gamepad trigger, so one press opened both. `ButtonY`
    belongs to the menu verb; the pad reaches the chrome through the two shoulder
    buttons instead. This is an example's export rather than a library surface,
    and it is recorded because a consumer copying the showcase's key map is
    exactly who this register is for.
15. `native_style.DEFAULT_ENABLED`, the library's default paint path, was opt-in
    (`false`) and is now default-on (`true`): a `screen_target.new({})` carrying
    no `nativeStyle` option paints through a Roblox `StyleSheet`. Every screen
    target that never named a paint path changes painter. Sheet rules and the
    `::UICorner` and `::UIStroke` modifiers replace the adapter's per-property
    writes, so no `UICorner` or `UIStroke` instance exists under a Facet root any
    more and a consumer reading those instances back finds nothing; the Style
    Editor becomes the paint authority for anyone who opens the place. The two
    paths were measured byte-equal on every mapped property, so the pixels are
    the same and the mechanism is what moved — which is exactly the kind of
    change a consumer's own code touches and a screenshot does not. The escape
    hatch is unchanged and still wins over everything: an explicit
    `nativeStyle = false` keeps the explicit-write path, which stays a
    first-class tested path rather than a corpse.
16. `UI.Region{ expand }` on a form that carries no control of its own
    synthesized a chevron beside the form; it now synthesizes a **cover** over
    the whole form. A passive compact form draws no mark at all and the whole of
    it becomes the tap or Activate target at the standard hit floor, where it
    used to draw a caret in a column the form's own measure reserved. Shipped
    geometry moves: the form gets the mark's column back — one demo's clock zone
    went from 100px to 80px at 360x691 — so a value that was being cut may now
    fit and a screen tuned against the reserved width re-lays out. The cover
    declares `zIndex = -1`, so it and the hit expander banded below it paint
    under every form within its own region. `UI.Foreign` and the lazy regions
    still force the chevron.
17. Corner radii and hairline strokes now scale with the metric ladder at the
    ten-foot display class, derived from the same metric scale so a later scale
    change moves them in lockstep. A radius rounds to a whole pixel because a
    `UDim` offset is an integer; a stroke keeps its fraction because thickness is
    a float. At a scale of 1.5: 12 becomes 18, 8 becomes 12, and 1 becomes 1.5.
    The capsule sentinel scales from 999 to 1499 and paints identically for every
    box up to 1998px on its shorter side. A theme package's ten-foot metrics may
    name a paint path and win on both sides. Near-distance density is
    byte-identical.
18. `UI.Region{ expand }`'s plate-or-sheet selection, and the resolved
    `plate.max`, were measured against the gutter allowance and are now measured
    against **the allowance minus the plate's own chrome** (at a 390px viewport,
    358 becomes 342). A form whose natural width lands in the last few pixels of
    the allowance now falls back to the full-width sheet instead of mounting an
    anchored panel that was wider than the allowance it had just been chosen
    against — reproduced at 390px, where a 320px form gave a 358px cap and a
    380px panel. No shipped screen moves today, which is exactly why the row is
    owed: the next reader tuning a form against the allowance has no other way to
    learn the band exists.
19. The hit expander a `role = "cover"` affordance receives inflated the solved
    rect by 44px unconditionally; it now **grows one side at a time, and each
    side stops at the first rect outside it that can sink a press**. Boxed in on
    every side it retracts, and the affordance is reached through the region's own
    box. A cover is its region's whole box, so the old floor took presses from
    neighbours: measured at 390x150, 960 square pixels of one neighbouring button
    and 828 of another — 26% of each — were delivered to the plate instead of the
    button the player aimed at. Only rects the author declared stop a floor: a
    framework affordance may not take the accessibility floor off another one. Of
    381 swept routes, 38 end below the effective floor and every one is cut by an
    author node; the smallest route is 35px and 31 covers retract.
20. `newPicker`'s activation order is now **one transaction** around both the
    control's own write to `selected` and the `onChange` it then calls. It used
    to be two turns: the write flushed on its own before the callback ran. A caller
    may redirect or veto a pick from inside `onChange` by writing the signal
    back, and until now the value it was about to undo was published first: every
    observer of `selected` saw it, and a `UI.When` over the selection mounted a
    whole subtree and evicted it in the same frame. An observer that counted
    selection changes now sees fewer of them, and an `onChange` inherits a
    transaction body's obligation not to yield. A read is unaffected: a
    transaction defers the flush, never a read.
21. `newTabView` with a declared `sizing = "hug"` at `bottomBar` now gets the same
    **centred scroller** every other hugging home gets. It used to park the strip
    at the band's leading edge in a stack that could not scroll.
    The thumb-zone band is deliberately not a scroller because a
    `fill` strip divides the offer and has nothing to overflow with — a statement
    about the default that the code was applying to the home, so a caller who
    declared `hug` there got natural-width segments at the leading edge and a
    strip wider than the phone simply ran off it. The `fill` default is
    untouched.
22. `Facet.text.fit` and `Facet.text.size` decided a size "fits" when the wrapped
    form stayed inside `lines` (and `height` when given); the widest line must now
    also stay inside `width`. A single word has no legal break, so the wrapper
    reported one natural line at every size however far past the box the glyphs
    ran, and the function handed back the cap for a string that does not fit at
    all. For a multi-word phrase nothing moves, except the one case where it
    should not have: a phrase whose longest word is wider than the box, which the
    engine breaks mid-word and paints outside the column.
23. A `hug` dimension on a `UI.ViewThatFits` **candidate** was measured at the
    minimum of content and offer, like every other `hug`, so the width test was
    true at every width. It is now resolved as content, uncapped, for the
    duration of the fit probe; the author's own `min` and `max` still bind, and
    the winning candidate is capped by its offer exactly as before. A `hug`
    candidate could never report "does not fit", so the ladder pinned its first
    rung forever and the labels it exists to protect truncated anyway. Refusing
    `hug` at construction was rejected: a control that picks `hug` for itself
    would have been refused for a spelling its author never wrote.
24. A `topbar` region under `rootPolicy = "bandSafeContent"` was a row spanning
    the composition's full width, as tall as its own content. It is now laid into
    the platform's own free strip — that strip's x and width, reaching its bottom
    edge — and the lane band below it is floored at the platform's whole top
    reservation. The tenth zone is the one that is not an anchor, and its purpose
    is to sit level with the platform's own controls; until now its geometry was
    the consumer's, held open with spacers and a memo. A caller that declares a
    `topbar` region now gets a row whose x, width and height are all platform
    facts, so a hand-computed spacer beside it is a double reservation. Two
    further consequences: a span row's slack now goes to its `fill` regions, which
    is what lets a region centre in the strip rather than sit at the top of it;
    and the lane band's floor is the platform's whole reservation rather than the
    band's bottom edge, except for a composition that both rides the strip and
    declares `exclusions`, which has already said where its own chrome is per
    column and gets the platform's own row instead of the bounding box. A
    composition that declares no `topbar` region resolves exactly as
    `deviceSafeContent` would have resolved it.
25. The gallery's grid scenarios forced their cell and line gaps to `"xs"` (4px)
    at Facet Neutral, because no space step named 6. They are restored to
    `"tight"` (6px), the value both fixtures originally wanted, now that
    `space.tight` exists as a derived step naming the value halfway between `xs`
    and `s`. Both grids' rendered gutters grow from 4px to 6px in the shipped
    gallery: a deliberate value change, not a value-identical rewrite.
26. Two gallery viewports carried literal pixel heights (150 and 120, each a
    hand-guessed "roughly N rows with the next one peeking through"). They are
    now content-terms formulas — four rows of the compact control height (144px),
    and six lines (116px). Both render 6px and 4px shorter at Facet Neutral, in
    the safe direction for a viewport: the old 150 never held four full rows
    either, since the rows are 46px each. What actually changes is that both now
    grow at the ten-foot ladder and at a raised text preference, where the frozen
    literals never did: 144 becomes 216, and 116 becomes 173.
27. Under `rootPolicy = "bandSafeContent"` with both a declared `topbar` region
    and declared `exclusions`, the lane band used to start at the topbar row's own
    measured height with no platform-reservation floor under it whenever the
    platform band was absent. It now falls back to the same reservation the
    no-exclusions path already used. The platform band really is absent on a live
    device, both at boot before the first platform push and on a measured
    rotation-recovery frame, so this was a real lane-and-topbar overlap risk
    rather than a headless-only one.
28. The expand plate's close disc used a spacing step (`space.xs`) for its corner
    inset, which had no relationship to the focus ring it exists to clear. It now
    uses the larger of that step and the ring's own inset. Every package whose
    spacing already cleared the ring gets the identical inset back; the two
    packages that were short move from 3px to 4px at the ten-foot ladder, closing
    a measured 1px overrun by construction rather than by a named ratchet.
29. `surface = "badge"` had no intrinsic size at all — a bare glyph hugging its
    own pixels, or an empty zero-sized box. It now carries a theme-owned minimum
    (20px at Facet Neutral, scaling at the ten-foot ladder like every other
    control metric) on both axes when the author declared neither `width` nor
    `height`.
30. Two gallery motion fixtures sized their lane and puck with a raw 40, unscaled
    at every display class. Both now use the theme-owned decorative-chrome floor:
    identical 40 at Facet Neutral and Medium, and 60 at the ten-foot class — the
    first scaling either box has ever had. Both render 20px larger there, in the
    safe direction.
31. `UI.Composition{ exclusions }` shared a lane's slack out as the lane's budget
    without the chrome row, rather than as the lane's own already-inset height.
    An `end`-placed group landed exactly the give-way inset past the bottom of its
    own lane, a `center`-placed one half of it, a numeric placement a matching
    fraction of it, and a `fill` group took the same phantom pixels as height.
    Measured one-for-one from a 1px inset to a 300px one, and seen live at 141px
    on a console and 54px on a phone. It is a defect fix that restores the
    partition guarantee, and shipped geometry moves for every consumer that
    declares `exclusions`.
32. The themed-chrome family changed in four places. An inset was spent whenever
    any pixels remained; it is now spent only when the node's own line box still
    fits — a text-bearing leaf needs more than its text size, everything else is
    unchanged — on both the measure and the paint seam. A sibling plate's border
    is no longer spent twice. The pill selection indicator's inset is reduced by
    the plate slot's carved border. Shipped geometry moves under every package
    that carves a border: an ornate disc loses the frame it was reserving twice
    (60px becomes 52px under one package, 44px becomes 38px under another), and
    every pill indicator covers its whole segment rather than an inset chip.
    Facet Neutral and every flat package are byte-identical, because their carve
    insets are all zero.
33. `newMenu`'s automatic presentation at a **compact** size class with a
    pointer-primary interaction class resolved to its own answer, gated on live
    touch plus an item count; it is now forced to the sheet presentation whenever
    the size class is compact, unconditionally. A documented policy answered
    differently for a real, reachable environment — a compact width with no touch
    signal, which is a phone with a mouse, or Studio's own compact preset, which
    cannot inject touch at all. Every submenu now replaces the panel in place with
    a Back row instead of floating a second panel over a parent that does not have
    room for it. The regular and wide classes are unaffected, and an
    author-forced presentation is unaffected at any width.
34. `distanceProfile`, `typographyScale`, `typographyPaintScale`, `themeMetrics`,
    `sizeClass` and `effectiveOverscanInsets` resolved from the raw `displaySize`
    and now resolve from the derived `effectiveDisplaySize`, which downgrades
    `"Large"` to `"Medium"` when the session is touch-capable. On a
    `"Large"`-reporting, touch-capable session the ten-foot type and metric scale,
    the density cap and the console overscan margins now read off, 1, uncapped
    and zero, where they used to read on, 1.5, capped and 60 to 90px.
35. Under `scrollIndicatorPolicy = "auto"`, the solver's scroll-bar reserve was
    policy-blind: `"always"` and `"auto"` reserved the same thickness. It is
    policy-driven again. `"always"` is unchanged; `"auto"` now publishes zero, so
    content measures to the full cross-axis width instead of the width minus the
    bar. Content that used to stop 8px short of the scroller's own edge now runs
    to the full edge. A bare zero reserve alone would reproduce an older defect,
    because Roblox narrows a `ScrollingFrame`'s window by the bar's thickness
    whenever the scroll axis overflows regardless of paint policy — measured
    again this round, and a fully transparent bar image does not stop it — so the
    zero reserve is paired with widening the scroll host's own frame by the same
    thickness on the cross axis while it overflows. The overlap is the bar sitting
    in that borrowed space.
36. The float focus ring a focusable control draws inside a clipping or scrolling
    host read its corner radius from the target's construction-time style, which
    no theme swap ever reassigns; it now prefers the live theme snapshot's radii
    and falls back to the construction-time style only while no package is
    installed. The corner was also built only on first creation and is now
    re-synced on every focus-visual call, so a live swap's repaint reaches it. A
    focused control's ring corner moves under any installed package whose control
    or panel radius differs from the target's boot radius, on the first focus
    after a swap. With no package installed at all it is byte-identical.
37. Every badge overlay in the repository — the segmented picker's count seal and
    the gallery's hand-rolled tile badge, two independent implementations — was
    anchored flush at the raw corner under every package. Each now insets top and
    right by the theme's carved border for its slot, through one shared
    primitive rather than the same four-line loop written by hand three times.
    Shipped geometry moves under any package that carves a control or accent
    border; flat and Facet Neutral packages are byte-identical, because the
    computed inset is zero on both axes.
38. Every `UI.Path` wrote its normalized control points as pixel offsets and now
    writes them as scale. A `UDim` offset is a 32-bit integer — measured live on a
    round trip, `UDim2.new(0, 25.05, 0, 6.95)` reads back as 25 and 6, while the
    same pair survives to six decimals as scale — so every control point was
    truncated to a whole pixel. A 32px progress ring lost 0.8px at its 3 and 6
    o'clock extremes and 0.2px at 12 and 9, painting as an off-centre egg, and a
    closed ring's last point floored to 15 where its identical first point floored
    to 16, so the track closed one pixel left of where it opened. Separately, the
    showcase's glass plates now declare their own surface role and take the
    caller's gutter through one shared inset memo, instead of painting a raised
    box behind a sibling that wrote its own gutter.
39. The layout reserve every native scroll host spends under
    `scrollIndicatorPolicy = "always"` was exactly the bar instance's thickness
    (8px) and is now that thickness plus a one-pixel gutter (9px). The bar
    instance itself is untouched at 8px, and so is the engine's own window
    narrowing, which is what makes the extra pixel visible rather than painted
    over. Every overflowing `"always"` scroll host lays its content out 1px
    narrower on the cross axis, and the gutter a sibling pays — a table header
    aligning with its body — grows from 8 to 9 on the right for a vertical
    scroller and on the bottom for a horizontal one. `"auto"` is untouched: it
    reserves zero and deliberately overlaps. The earlier round had already
    measured that this boundary was not an overlap; the ruling is that
    exact-and-flush is the defect, because content on the bar's outermost pixel
    reads as a collision.

## Earlier versions

Versions 0.4.0 through 0.9.0 predate this file. Their public surfaces are
documented in [`docs/reference/api.md`](docs/reference/api.md), and the retiring
ones are listed with the version that may remove them in `Facet.DEPRECATIONS`.

### Unreleased — game navigation continuity

- Add declarative per-property animation and automatic layout groups on the shared
  motion clock; provide owned `ui.animate` and explicit `ui.withAnimation` helpers.
- Normalize custom-component children, accept direct `When` children and collection
  key fields, and share repeated getter bindings within their mounted owner.
- Add Motion → Automatic to the showcase and paired animation benchmark workloads.


- Keep client input contexts in stable client-created storage; entering Table rows from a focus section works in normal and edit modes. Showcase unread markers use bounded vector paint so ornate panel decorations cannot spill across their rows.

- Add semantic row presentations to Button, Toggle and Slider, declarative focus
  sections, and named ScrollView targets with shared snap/motion and visibility/progress.
- Restore TabView scroll positions by stable descendant/item key, including virtual
  lists, grids and tables; preserve lazy page disposal.
- Add optional tab sections and caller-owned order/visibility customization, with
  animated selection indicators that follow changing keyed options.
- Extend Showcase game-art/row/navigation examples, theme containment checks and the
  adaptive navigation performance scene. Document when agents should choose each.
