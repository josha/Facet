# Current package

A theme can name plates: `finish.plates = { row = { edge = { width = 2 },
depth = { lift = 4 } } }`, and a VStack or an HStack with `surface = "panel"`
takes one with `plate = "row"`. Before, every panel had the one line and the
one shadow of the theme, so the rows in a panel could not have a thinner
line and a shorter shadow than the panel. `depth.controls` accepts `side`
and `shade`: with a `shade`, the shadow of a control takes the fill of that
control, made darker, so each Button has a lower edge in its own color. The
controls can have that shadow on a theme whose panels have none. A stated
`controls` table beside a look keeps the values of the look that it does
not state.

A theme can take its edge and depth from a named look and its motion from a
named feel: `finish = { look = "raised" }` and `motion = { feel = "calm" }`.
The looks are `flat`, `raised`, `glow` and `hard`; the feels are `calm`,
`crisp` and `lively`. A stated value replaces the value of the name. An
author who cannot see the result chose shadows and glows too faint to show;
the names carry values that show. The words-only direction card now names
the look, the feel and an icon or a glyph for each thing.

A finish reads a role that the palette of the theme does not state, such as
`hairline`, from the base palette. Before, `define` failed for a palette with
only the main colors.

`UI.Pagination` has a `step` form for a short set, such as the cars of a
garage: Previous, a label and Next in a row that has its own width, so it
fits a HUD Region. A `label` function gives the text of the label for a
page. Before, an author built this row from two Buttons and a Text.

The "…" control of a `left` or `right` column zone moves clear of a wide
centre zone of its row: below a `top` zone, and above a `center` or `bottom`
zone. It stays beside its zone when the new place is off the screen or over
another zone of its column. A zone whose regions cannot drop has no
`ZoneReveal` control until a Region first collapses into it.

Facet Neutral has larger type: caption 16, label 17, body 18, heading 22,
title 26, strong 18 and numeral 20, with a minimum text size of 16. A theme
that keeps the Neutral minimum gets its smaller sizes raised to 16. Before,
text on a desktop screen was small beside a hand-built UI. A theme can set
`controls.typography.minimumSize` as low as 14 to keep smaller sizes.

When one zone of a Composition still covers another zone after every Region
is at its last form, a Region of those zones now hides behind the "…"
control of its zone, where the player can open it. The Region with the
highest rank number goes first. Before, the regions stayed over each other.
A Region with `reveal = false` stays in view, and so does a Region that is
only too large for its lane or the screen. The fit warning and `FacetUnfit`
still name each Region that does not fit. Every zone that has a Region with `reveal` now has a
hidden "…" control ready.

A hugging Region form keeps a child with `UI.fill()` at its natural size.
Before, three filled Buttons in a hugging row collapsed to their minimum
width and their labels ran over each other, because the Region takes its
size from the form and the filled children then shrank to that size.

A row Card with `reveal = "always"` shows its actions at the trailing end of
the row while the title keeps 120 pixels of room. Before, each row had a
full-width button below it.

A centered Sheet on a screen less than 600 pixels tall keeps a `space.s`
margin above and below. Before, the `space.m` margin took 16 more pixels
from a phone in landscape.

A live build recovers from three option mistakes that replaced the control
with an error label before. It ignores an unknown option. It gives a stack
whose `surface` is not one of `surface`, `panel` or `pane` the `panel`
surface. It puts a `Compose.show`, `switch` or `keyed` child of a Region in a
form of its own. Each recovery is reported through `onError`, or as an error
in the output. A strict build, which tests and Studio Edit use, still rejects
all three. An author who cannot run the game often makes these mistakes, and
one of them removed a whole HUD or every row of a list.

On a short screen in landscape, the art of a stacked Card is a band no taller
than a quarter of its width. Before, the art of a wide Card filled a phone
panel and its title and action were below the fold.

A Region form that is a hugging row does not wrap. Before, `wrap = true` on an
HStack with no width put each child on a line of its own, because a row that
hugs has no width to wrap at, and a hotbar became a column over the play area.
A row form with a width still wraps.

A Slider row shows `row.icon` on the title line, before the title, and the
track on its own line at the full width of the row. Before, the icon was in a
column of its own, centred between the title and the track.

A `Composition` does not move a `top` or `bottom` zone beside its corners to
a place that is off the screen; it reports the regions that do not fit. A
`Grid` with automatic cell height ignores a hidden child, measures with the
layout unit of the grid, and releases its connections to a removed child.
`minCellWidth` counts columns in the width inside the Grid's padding. A Card
with `image` and `glyph` shows the image only. The theme contrast repair
tries both white and black and keeps the nearest color that passes.

A `topbar` region form that shows text with no surface and no Button gets a
panel plate. Before, a currency or a timer in the strip was bare text over the
world, and it was small and hard to read on a bright scene. A form with its
own `surface` keeps it. In the other zones, a Text with no plate under it
gets an outline in the surface color. `plate = false` on a Region keeps its
text bare in either case.

The strip of a HUD `Composition` sits under a modal's scrim. Before, the
strip's ScreenGui had the display order of its host, the engine drew it above
the scrim, and its buttons stayed bright while a Sheet was open.

A `center` Sheet with `automatic` width narrows to content that does not fill
it, down to the `narrow` width. Before, a body with a fixed width sat at the
start edge of a wider panel and left the rest empty. A body with
`width = "fill"` keeps the full width.

Breaking: a passive Toast hugs its content by default. `width = "fill"` gives
the former full-width row. Before, a short message such as "+10 coins" spanned
the screen.

A `Grid` that sets no `cellHeight` and no `aspectRatio` gives each cell the
height of its tallest Card or hugging stack, and at least the height of a
control. Before, the cells had the height of a control, and taller children
overlapped each other and the parts around the grid. A grid of Buttons keeps
the height of a control.

A `Grid` turns off the horizontal hug of each child, so a child is as wide
as its cell. Before, a hugging stack with a child that fills its width grew
past the cell by its padding, and its content went past its plate.

`UI.Card` has the new option `glyph`: a Facet icon name or an emoji. The Card
draws it in the art frame at 75 percent of the frame height, and the frame of
a glyph card is `4/3` by default. Use it for an item that has no art.

`UI.Card` has the new option `layout`. With `layout = "row"`, the art is a
square of the control height at the start of the title and the caption, and
the card is as short as a list row. The default, `stack`, keeps the art above
the text.

`UI.Grid` has the new option `minCellWidth`. The grid shows as many columns
as fit at that width or more, and `columns` becomes optional and is the most
columns. Use it for item tiles in a panel of unknown width.

A Card in a box taller than its content keeps its plate and its place on
hover. Before, in a Grid cell or a stretched row, the plate became as small
as the content and the content moved to the middle of the box.

`Facet.themes.define` repairs a text color whose contrast on its ground is
below 4.5:1: it moves the color toward white or black until the pair passes,
and `report.advice` names the color. Before, one such pair rejected the whole
theme, and a game that did not read the report showed the neutral theme.

When a top corner zone at its last form is over the touch controls, or the
`topLeft` and `topRight` zones are too wide for one row, and no region can
give way, the `top` zone moves below the corners and the corners share the
row. There, a narrow `top` zone sits at the left edge below `topLeft`, not in
the center of the play area. When the corners are still too wide, the
`topRight` zone moves below the `topLeft` zone. Before, the two corners drew
over each other on a portrait phone, and a tall corner form drew over the
touch controls.

With the `top` or `bottom` zone below or above its corners, a corner region
at its last form now uses the room that the other corner leaves in the row.
Before, it was held to one third of the width and the composition reported
that it did not fit, although it was drawn with room to spare.

A `Composition` that is a direct child of a `Screen` now reaches past the
bottom padding that the Screen adds for the touch controls. The Composition
clears each touch control in its own column. Before, the Screen held the
whole HUD above the highest touch control, so a game with action buttons
around Jump had a HUD area less than 100 pixels high on a phone in
landscape, and the regions that did not fit drew over the play area.

A `center` row region does not go over a wider side zone that cannot step
down, drop or land. Before, the row kept its lane width and three wide
Buttons at `topRight` covered a short region at `top` on a phone.

The new recipe `Tasks.shortcut` makes an InputAction with a key and a gamepad
button for a HUD Button and shows it with `shortcutHint`.

The new recipe `Tasks.inventory` shows a bag and a small shop in a Sheet:
a segmented Picker, a Grid of Cards with a picture for each item, and the
action on the Card.

Breaking: UI.Text refuses the native `TextXAlignment` and `TextDirection`.
Use `textAlign` and `direction`. `textAlign = "start"` and `"end"` now follow
the text direction. With `direction = "rtl"`, `start` is the right edge. With
`direction = "auto"` or no `direction`, the first strong character of the
text sets the direction, as the engine does for `TextDirection.Auto`. Before,
`start` was always the left edge, and right-to-left text with `start` sat at
the wrong edge. The engine does not mirror `TextXAlignment` for right-to-left
text. A Timer takes `textAlign` and `direction`. Timer and Typewriter pass
their native properties to Text, so they refuse `TextXAlignment` and
`TextDirection` too. To update, replace `TextXAlignment =
Enum.TextXAlignment.Left`, `Center` and `Right` on UI.Text with `textAlign =
"start"`, `"center"` and `"end"`.

A panel stack takes `tail`, so a speech bubble or a label that points at a
thing on the screen needs no art of its own. `tail = "bottom"` or
`tail = { side = "bottom", at = 0.3 }` draws the tail that Callout and
Popover use, with one outline around the plate and the tail.

A ZStack with `alignH` or `alignV` places its children in its own box when
that box is larger than its largest child. Before, a ZStack that had a native
`Size` and no `width` or `height` placed its children as if it hugged them,
so a centred child sat at the top-left corner of the box.

A Stepper keeps the shadows of its keys inside its own box. Before, a theme
with `finish.depth.controls = true` drew the key shadows below the Stepper,
and the part under it in a stack touched them.

`cut-at-edge` also reports a plate that the edge of the screen cuts, when its
text is still on the screen. A row that wraps its last parts onto a line
below the room is the usual cause, and the fix text now names it.

A one-line Text that is wider than its room shrinks to fit, with a `UIScale`
named `TextFit`, down to 70 percent of its size and never below 10 pixels.
Its room is its own width when it fills a stack, and the box of an aligned
ZStack when it hugs there. Before, the text ran past its box (blackjack card
spots on a phone in landscape). A text that does not fit at the floor still
runs past, and `escaped-text` reports it. A filling text reads the engine's
`TextBounds` after layout and widens its `Size` by the inverse of the scale,
so its box stays the width of its room. `truncate`, a native
`TextTruncate`, `wrap`, `lines` and a fitted `textSize` keep their own
behavior, and a text size above the player's default is never reduced.

A one-line Text in an aligned ZStack takes `alignH` as its text alignment,
as one in a vertical stack takes the stack's alignment, unless it sets
`textAlign`.

A VStack or HStack with a positive `gap` keeps the hard part (offset and
spread) of its children's shadows inside the gap, in a theme that draws plate
or control shadows, so a gap of 4 between two lifted Buttons leaves 4 pixels
between their shadows. A gap of 0 or less is not changed.

`escaped-text` also measures a text against an outlined box, a box with a
visible stroke and no fill, and reports it even when a larger plate under
the box still holds the text.

`Facet.review` measures the parts from the top of the screen. Before, it read
their positions below the engine GUI inset (58 pixels for the top bar) and
compared them with the full height of the screen, so a part that the bottom
edge cut by less than the inset had no finding. This applied to every rule
that compares a part with an edge of the screen, such as `cut-at-edge`,
`offscreen-text` and `touch-control-overlap`.

`UI.Toast` and `app.presentToast` accept `reading`, a readable
`Facet.ToastReading` record with `duration` and optional `readFloor`.
A new record restarts reading time without requeueing the row. Waiting time
does not count, and the existing pause setting applies to each period.
`onPresentedChange` receives the dismissal reason as its second argument.
`app.presentToast` exposes the same controlled presentation options.
The Toast page in Facet Lab exercises host resizing and controlled continuation.

A HUD `Composition` reserves room for the Roblox touch controls only under the
zones that they cover. Before, the space above the highest control was taken
from the whole width of the screen: on a phone in landscape the thumbstick's
touch area left the HUD a band about 90 pixels tall, and regions on the other
side overlapped. Facet now finds the thumbstick art that the current
PlayerModule draws with Frames, and a side region (`left` or `right`) moves
down below the corner region above it when the center does not fit, in place
of overlapping it. The reference phone check behind `FacetUnfit` and
`composition-unfit` now includes the default stick and jump controls.

A number for `width`, `height`, `padding` or `gap` on a stack, and for the
size of `UI.Image`, follows the theme scale: it grows by 1.5 at ten feet and
with the resolution factor on large displays, as text and controls do. Before,
a panel with `width = 220` stayed 220 pixels on a console while its text grew.
A readable, such as `env.scaled(220)`, is used as it is, so code that already
scales its lengths keeps its size.

A `Sheet` with `placement = "center"` keeps `space.m` clear of every screen
edge, as `Dialog` does. Before, on a phone in portrait it ran from edge to
edge.

A HUD `Composition` reserves the columns around the resting art of the
dynamic thumbstick, and as far as the stick travels to either side, in place
of the whole width of its touch frame. In landscape the current PlayerModule
draws that frame across the left 40 percent of the screen, and a region at
the bottom center rose above the stick. In portrait the frame is the full
width, and every bottom region did. Facet reads the resting art when the HUD mounts
and follows it only while no finger is down, after it has seen a finger lift,
so a HUD that mounts during a drag does not follow the drag.

A finish `sheen` is a wash over an opaque plate. Before, the sheen was
the plate's own transparency, so the top of each plate showed the world
through it and the hidden half of a Popover tail showed inside the plate.
Each end of the wash is exact on dark and light palettes: the plate takes the
lighter of the washed top and the fill in each channel, and the gradient
darkens toward the other. A Popover tail matches the plate where it joins it:
the washed top on the top edge, the fill on the bottom edge and the middle
tone on a side.

`Facet.review` reports `duplicate-close` (medium): a Close, Done or Cancel
button in the content of a Sheet, Dialog or Popover that already shows its own
Close in the header. The use-facet skill says not to add one.

`Facet.review` reports two HUD findings, both `medium`. `worded-command`: a
Button in a Composition region spells out a standard command or a known
destination, such as Settings, Shop or Lifetime Stats, in place of its icon.
A Button that already shows its icon is told to drop the label.
`top-row-stacked`: the top-center regions sit below a corner region,
because the top row has no room. Both fixes name `zone = "topbar"`.

A HUD `Composition` keeps the room of the Roblox touch controls while a Facet
overlay holds them off. Before, opening a Popover, Sheet or Dialog turned the
controls off, the HUD moved into their room, and a region could change form
under the overlay. A region's reveal Popover then closed as it opened, since
the region now fit at its richest form. While the hold lasts, Facet keeps
measuring the controls as the game last showed them, so a rotation, a rebuilt
Jump button or a HUD that mounts under the overlay still clears them.

A theme with a `finish` edge draws the edge of a Popover or Menu with a tail
as one line around the plate and the tail. Before, the plate kept its own
stroke in the edge color and the tail had a thin outline of its own, so the
tail looked separate. The Popover that shows a HUD region's richest form has
no Close button; a tap outside, `B` or Escape closes it.

Text at ten feet is larger: the smallest type role is at least 28 pixels and
every other role at least 32, so the neutral `body` is 33 pixels on a console.
Before, the floors were 24 and 28, and captions drew shorter than the 26 pixel
text height that the Xbox Accessibility Guidelines ask for at 1080p.

**Breaking:** a theme whose `contentSecondary` is below 4.5:1 on `surface` or
`surfaceStrong` no longer defines; `themes.define` returns nil and a report with
the error. Before, the theme loaded with a caption that players could not read.
Raise the contrast of that color, or remove it so that Facet derives one.

A `Composition` inside a full-screen frame now gets the TV overscan margins at
ten feet, the part of each margin that its position does not already clear.
Before, only a Composition placed directly in a ScreenGui had them. The phone
reference check of `FacetUnfit` is skipped at ten feet, where its sizes do not
apply.

`themes.define` derives the palette roles that a theme does not state from the
theme's own colors when it states a `surface`: secondary text from `content`,
the control plate and the selected plate from the surfaces and `accent`.
Secondary text aims at 7:1 on both surfaces and keeps the hue of `content`.
Before, these roles came from the neutral palette, so a navy theme had slate
controls and a gray caption below 4.5:1 contrast. The contrast report now checks
`contentSecondary` on `surface` and on `surfaceStrong`, and a pair below 4.5:1
is an error.

Each standard icon name now has a built-in vector glyph. When no theme
package or `icons` map supplies image art for a name, the icon draws as native
Path2D strokes in the theme's icon color. Before, only the names that controls
use for their own parts drew strokes, and a name such as `settings`, `coin` or
`car` showed an empty image. The glyphs need no uploaded asset. Image art in a
theme package still takes precedence.

`Facet.Rule` and `Facet.AuthoredRuleProperties` are removed. They were second
names for `Facet.ThemeRule` and `Facet.ThemeRuleProperties`. Use those names;
the types do not change.

The neutral theme no longer has `metrics.controls.image.defaultSize`. No
control read it, so a theme that set it saw no effect. A theme that still sets
it loads as before.

The reference no longer has nodes for the three themes that declare
`testOnly = true`: `content_alias_test`, `fantasy_parchment_stub` and
`layered_test`. The theme index lists only themes that a game can choose.

The library no longer has the modules `ui/inputs`, `ui/media`, `ui/nav_pages`,
`ui/nav_surfaces` and `ui/travel_geometry`. No control loaded them:
`Facet.controls` loads each control family on first use, and Travel calculates
its arc in `ui/travel`. The public surface and the control behavior do not
change.

The use-facet skill covers a game that already has an interface. The game is
the reference: a request to replace the interface with Facet matches its
screens, controls and words; a request to improve it keeps what makes the
game recognizable and improves inside that language; the user's instruction
can fix or open any part.

`Facet.review` reports the measures of a screen: the largest numeral as a
share of the screen height and against the most common text size, the number
of plates, a typical control, and the strongest control with its place and
size. They end `report.text`, and `report.measures` has the values. An author
puts them against the quantities of a target, with or without a shell.

`finish.edge.controls` takes values of its own. `true` drew the line of the
plates on every Button, so a bright plate edge became as many equal bright
borders as the plate had controls, and the main action was one outline among
them. `edge.controls = { width = 1, transparency = 0.5 }` draws a quieter
line on the controls; a value left out is that of the plates, and the
controls can have a line when the plates have none. `true` with a line of
2 pixels or more gives a `finish.edge.controls` entry in `report.advice`.
The `finish.depth.glow` advice now asks for a look at the specimen instead
of stating that a faint glow never shows.

A Callout whose anchor is in a Composition region stays clear of the other
regions. Its plate was centred on the anchor whatever sat beside it, so on a
short landscape phone a lesson under a top region covered 21 pixels of the
first action button, and the two read as one row. The plate now slides along
its edge, one `space.s` step clear of the other regions and zone marks, as
far as its tail still reaches the anchor; with no clear place it stays where
it was. `overlay_placement.solve` takes the rectangles as `avoid`. A region
that shows its compact mark still suspends the Callout of an anchor inside
it, and the Callout shows again in the popover of the mark.

`Facet.review` reports `covered-control`: a control with a part of its box
under a plate or an image from another part that is drawn above it. A control
under a presented modal, wholly under a part, in a scrolling view or in a
fan is taken as layered on purpose. The snapshot records the layer of each
element and whether a part that is not a button takes input, so parts of two
ScreenGuis are not compared.

Wrapping `UI.Text` that moves into a filling row after it mounts makes its
shrink item under its own owner. The label made the `UIFlexItem` in its
re-fit callback, which runs outside any owner, so Compose raised
`owner/no-active-owner` and the label did not shrink in the row.

A theme StyleSheet keeps its style rules as plain records instead of one
Compose row each, which takes 6 to 33 KiB of Luau heap off each themed screen
in Studio. Rule priorities were already unique, so the order of the rules in
the sheet does not change which rule wins.

An app mount builds its whole ScreenGui inside the app controls. Content that
a returned `show`, `switch` or `keyed` directive built after `component()`
returned ran outside them, so `Facet.controls(runtime)` there made default
controls without the app theme. `app.mount` also takes `{ parent, name,
screen }` for one ScreenGui, so one app can mount a main layer and an overlay
layer, and `app.sheet()` returns the shared StyleSheet for a root that the app
does not mount, such as a SurfaceGui.

The art of a stack `ground` keeps the size of its stack. `UI.Image` binds
its own `Size`, 44 pixels square with no `width` or `height`, and the stack
set the full size once. When the binding ran again, on a console preview, a
change of device or a late first frame, the art went back to 44 pixels in
the corner of the stack. The stack now holds the size.

The edge of a theme's finish is drawn inside the box, and it can reach the
controls. `finish.edge` drew its line outside each panel, and it did not
reach Buttons, so two authors wrote stroke rules on the Button tags by hand.
Those strokes were also outside the box: with a hard shadow they used up the
gap between a Stepper and the action under it, and the two touched. The
line is now inside the box, and `finish.edge.controls = true` draws it on
Buttons and Stepper keys. A theme rule on `::UIStroke` takes
`BorderStrokePosition`, `LineJoinMode` and `ApplyStrokeMode` as names.

`Facet.review` has two new findings. `cut-at-edge` reports a text (high) or
a control (medium) that crosses the edge of the screen, such as a result
plate that is wider than a phone in portrait; `offscreen-text` reports a
text only when more than half of it is outside. `touching-controls`
(medium) reports a control whose stroke or shadow, drawn outside its box,
reaches the control beside it.

An app makes one StyleSheet and shares it. Each `app.mount`, popover and
toast built its own theme StyleSheet inside its ScreenGui, at about 300 KiB of
Luau heap and 1.5 ms each in Studio. The app now makes the sheet on its first
mount, in the `parent` option or the PlayerGui, and each ScreenGui holds only
a StyleLink to it. `app.dispose()` removes the sheet. Code that looked for a
StyleSheet inside an app ScreenGui reads the StyleLink's `StyleSheet` instead.

The theme compile cache now hits on the default theme. The engine types table
was new on each call and the neutral theme was not frozen, so each
StyleSheet compiled every theme rule again and kept its own copy. A
StyleSheet now reuses the compiled rules: in Studio a mount went from about
605 to 297 KiB of Luau heap and from 3.0 to 1.5 ms. `themes.neutralPackage()`
still returns an editable copy. An editable package is cached by its contents,
so two copies with the same values share one compile and an edited copy
compiles again.

A Composition matches the heights of similar regions only. With the default
`rows = "match"`, every region in a row of the `top` or `bottom` zone took
the height of the tallest one, so a lap readout beside a standings list was
stretched to the list, 343 px in one game. A region under half the height
of the tallest now keeps its own height and matches the others of its size.
Readouts of similar heights still read as one row, and `rows = "fit"` is
unchanged.

`Facet.themes.define` says when a stated glow will not be seen. A `finish`
with a glow under 8 px or a strength under 0.4 draws nothing that shows in a
capture, and a theme could state one and stay flat. `report.advice` now has
a `finish.depth.glow` entry for it, and `Themes.finish` lists what an edge
and a glow of each size look like on a screen of 1080 lines.

A NavigationStack holds gameplay only while it is on the screen. In an app
with `suspendGameplay = true`, a stack with a nonempty path suspended play
for as long as the path stayed nonempty, also when the stack was hidden or
when the Sheet that showed it had closed. A game that kept its path between
openings then found its drive input off with no interface open. The hold now
needs the path and a stack that is visible under an enabled ScreenGui, and it
returns when the stack shows again.

A ColorPicker with a stated palette is a palette. With `modes = { "swatches" }`
and `swatches`, a press on a swatch proposed the colour after a conversion to
hue, saturation and brightness and back, so the Color3 that `onChange` got
differed from the palette's in the last bits, and a caller that looked the
colour up in its palette found nothing. The same form also showed the RGB, HSV
and Hex fields, where a player could type a colour outside the palette. A
swatch and a typed hex now propose the exact Color3, and that form has no
fields. It keeps them with `onSaveSwatch`, with `alpha`, with the generated
grid and with any other technique.

A plate's shadow arrives after its content. A theme with a glow puts a
bright shadow under the whole plate, and while a Callout, Sheet or Popover
faded in at the same rate as its shadow, the glow showed through the
half-transparent plate as a lit slab before any text could be read. The
shadow's strength now follows the cube of how much of the plate is shown, so
it is a fiftieth of its strength when the plate is a quarter in and an eighth
at half, and it leaves first on the way out. The resting look is unchanged.

A Composition also sets `FacetUnfit` for a region that opens its fullest form
in a Popover when that form is wider than the screen or than a 358 pixel
phone: the Popover cannot be narrower than a form with a pixel width, so it
ran past the edge and its Close button with it. `composition-unfit` names the
region. `mayDrop = true` no longer hides a form that is too wide.

On touch, `UI.Screen` and `UI.Composition` reserve less room for the dynamic
thumbstick. The band was as tall as the region that takes the drag, which is
two thirds of a phone in landscape: 228 of 331 pixels on an iPhone 14, so a
HUD kept 79 pixels and its regions were drawn over each other. The band is
now as tall as the stick where it rests, 111 pixels there, the same band that
the Jump button needs. A classic thumbstick, a thumbpad and a game's own
`touchReservations` are reserved as before.

A Composition whose regions do not fit the size it has now sets `FacetUnfit`
and names that size and the regions in `FacetUnfitDetails`, so `Facet.review`
reports `composition-unfit` on the device where the overlap shows. Before,
the review reported only the two phone areas from a larger screen, and an
overlap on the phone itself reached only the output as a warning.

When a `Facet.review` report has medium findings, its `text` ends the list
with their count and says what a new interface owes each one: a repair, or a
noted reason to keep the design.

The unknown-option error for `surface` says where the plate belongs: `A plate
belongs to a VStack, an HStack or a Screen: put this control in one that has
the surface.`

`Facet.review` has the rule `oversized-target`. It finds buttons that are
taller or wider than the scroll view that holds them, such as a record card
of 290 pixels in a list that has 170 pixels of room on a phone in landscape.
The player can scroll and can activate the part that shows, but never sees
one record whole. The finding names the count, the size and the room.

An unknown option on a control now names what the control takes. When no
known option is close to the name, the error lists the options of a control
that has 14 or fewer, and points to the reference of a control that has more:
`Facet UI.ZStack: unknown option 'surface'. Its options include alignH,
alignV, ground, height, padding, width.`

A theme states its edge and its depth as values. `finish` on a theme
definition takes `edge` (width, role, transparency) and `depth` (lift, blur,
side, glow, sheen, role, strength, controls), and `define` writes them into
the theme's stroke rule, its plate shadow and its plate gradient. The same
block gives a quiet interface with zeros, a neon one with a bright edge and
a wide glow, and a hard-edged one with a thick line and a hard shadow. A
definition without `finish` is accepted as before and gets a `finish` entry
in `report.advice`. `app.specimen(parent?)` mounts one screen of the theme
(type roles, actions in each state, a field and records) to capture beside
a concept before the first screen is built.

`Facet.review` reports `joined-facts` as high when the joined line has a
number and is the largest text of a HUD Region, such as
"P4 / 4 • LAP 1 / 2 • 0 km/h" alone on a plate. The player reads a HUD value
at a glance during play, and in that line no value leads. The same line under
a larger text in its region, and a joined line outside a Composition, stay
medium.

A Region takes `label` and `icon`. A region that the screen has no room for
showed as a "…" badge, and three of them on a phone in portrait said nothing
about what each one held. The region's `Reveal` badge and the zone's
`ZoneReveal` button now show the label and the icon that the region has,
and the Popover that holds several hidden regions puts each label above its
region. A region with neither keeps the "…" mark, and `Facet.review` has a
new medium rule, `unnamed-reveal`, for a mark that is on the screen.

A row with `width = "fill"` inside a parent that hugs keeps its content. A
Button with child content hugs it, so a row inside that asked to fill was as
wide as its fixed parts, and its `UI.fill()` child was 0 pixels wide: a
record of a thumbnail and two captions showed the thumbnail alone. The fill
child now takes the width of its content, with a wrapped text counted as one
line up to 320 pixels, and no more than the room that the nearest ancestor
with a width leaves. The same holds in a stack with no `width`. A row in a
parent with a width, and a parent in a list with `align = "stretch"`, are
sized as before. A stack with no `width` that held such a row beside a wider
child gave the row the width of that child; the row can now make the stack
wider.

`Facet.review` has a new rule. `collapsed-text` (high) finds a text that is
0 pixels wide inside a holder that is on the screen: the holder is as wide
as its content, and the content waits for a width from the holder.

A Popover stays inside the screen when its content has a pixel width that is
wider than the screen. The body carried a size constraint with the right
maximum, but the engine does not apply a maximum to an automatic size, so a
420 pixel child made a 420 pixel panel on a 389 pixel phone and the Close
button was drawn off the screen. The panel now takes the width of the safe
box, the header and its Close button stay in it, and the body scrolls
sideways to the rest of the content. Content that fits, and content that
fills, are sized as before.

A `UI.Text` with `wrap = true` in a parent that hugs its width no longer
collapses. In a stack with no width it had nothing to fill: in a VStack it
was 0 pixels wide, and in a HUD Region it wrapped to the narrowest slot that
the Composition ever gave it and stayed there, so a plate of "ION // RUN"
became 44 pixels wide and four lines tall. The text is now as wide as its
line, up to 320 pixels, and wraps past that. A wrapped text in a parent with
a width, in a bounded HStack and with its own `Size` is sized as before.

A `UI.Text` with `wrap = true` in an HStack that has a bounded width stays
inside the row. It took the full width of the row, whatever stood beside it:
after a 40 pixel Avatar in a 276 pixel row it ran 48 pixels past the end, and
the part after it was drawn outside the plate or off the screen. A long text
made the row spill, so the text dropped under the Avatar. Now the text takes
the size of its words and shrinks into the room that the other parts leave,
where it wraps. Two wrapped texts in one row share the shortage. A wrapped
text with its own `UI.fill()`, a wrapped text in a VStack and a wrapped text
in a row that hugs are sized as before.

`Facet.review` has a new rule. `offscreen-text` (high) finds a text with less
than half of its glyphs on the screen while the stack that holds it is on the
screen. A text inside a clip or a scrolling view does not count.

`UI.Screen` takes `ground`: one GuiObject, most often a `UI.Image` or a
`UI.ZStack` of images, that Facet draws behind the content and continues to
every edge of the glass, while the content stays in the safe area. `UI.Image`
takes `width`, `height` (`"fill"` or pixels, also as a cell or a function) and
`aspectRatio`. A stack `gap` can be a negative number of pixels, so that the
children overlap. `UI.Button { appearance = "bare" }` is a Button that is its
face: it has no plate, no padding and no label, and Facet still draws focus
and keeps the touch target.

`Facet.review` has four new rules. `overlapping-text` (high) finds two texts
that are drawn over each other. `covered-text` finds a text under a plate or
an image from another part. `escaped-text` finds a text that runs past the
plate or the image that it sits on, or that a clip cuts. `native-text` finds
labels that were not built with `UI.Text`. `floating-text` counts a large
image, such as a ground, as a plate. A part that is turned by a quarter turn
is read at its turned rectangle.

VStack, HStack and ZStack take `ground`: one GuiObject, most often a
`UI.Image` of a note, a card or a sign, that Facet draws behind the content
of the stack. The ground fills the stack and takes no space in it. When the
image has `paintRect`, the padding of the stack starts at the edge of the
paint, so a label on the art cannot sit on the transparent margin of the
file. `Facet.review.paintRect(image)` reads the painted bounds and the pixel
size of an image in Studio, in the form that `paintRect` takes. The review
counts the art of a ground as built beside the texts of its stack, and
`escaped-text` finds a text of that stack that runs past the paint of the
ground, also when most of the text is off the art. `floating-text` counts an
image as a plate when its paint is under the text.

An HStack that wraps by itself now also wraps when the content of a child
that fills does not fit beside the other children. The content counts by its
stacks with a `width` in pixels and its texts that do not wrap or truncate.
Before, the fill child took the room that was left, and such a part inside
it ran under the next child of the row.

`Facet.review` counts the art of a theme skin as built in the part that
wears the skin, so a skinned Sheet or panel hides the texts under it from
`overlapping-text` and `covered-text`.

`Facet.review` reads where an image is painted. `covered-text`,
`escaped-text` and the backing check of `overlapping-text` use the painted
bounds of an image: the smallest rectangle that holds its visible pixels. An
image with a transparent margin no longer covers a text that its paint does
not reach, and a label that runs over the edge of a shape painted inside its
image is found. In Studio, `review.collect` reads the pixels one time for
each asset and can yield on the first read. `UI.Image` takes
`paintRect = { x0, y0, x1, y1, width, height }` to declare the bounds for art
that Studio cannot read, such as an asset of another creator; the root module
exports `ImagePaintRect`. Without either source the rules use the rectangle
of the part, as before. A text that is mostly on the transparent margin of an
image is still measured against the rectangle, and a hole in the paint counts
as paint.

A disabled Button of a skinned theme no longer draws its own text under its
caption. The doubled text was hidden by opaque art and showed through
translucent art.

An `AdaptiveStack` without `axis` no longer flickers between a row and a
column while its width changes, such as during a window resize. It measures
its row the same way as a row and as a column: the widths of its children and
the gaps, with no width for a `Spacer`, a `Divider` or another filling child.
It turns back into a row only when the row fits with 8 pixels to spare, and
after a refused row it stays a column until its width holds the row that it
measured. An `AdaptiveStack` without `axis` and with `width = "hug"` warns
once, because it can never turn.

When the theme supplies no art for a standard icon that a control uses for its
own parts (close, the chevrons, checkmark, more, menu, increment, decrement,
search, the status and selection marks, clock and calendar), the icon draws as
native Path2D strokes in its styled tint. A Dialog close button, a disclosure
chevron or a checkbox mark is no longer blank in a game that supplies no icon
art. A Button caption next to an icon now uses the control type role, the same
size as a text-only Button label.

On touch, a Button with no text keeps its plate size. An icon, glyph, image or
circle Button no longer grows to `targetSizes.minimum`. An invisible
`HitTarget` around the plate meets that size instead. An empty `label` is the
same as no label, also when a reactive label changes to `""`. A Button with
text still grows its plate. The touch floor now follows the effective input
(`PreferredInput`), so a touch laptop that the player uses with a mouse has no
floor. A gamepad keeps the floor on text Buttons only.
Controls no longer read layout inside a layout change signal. In a game, the
geometry that controls observe (collection viewports and measured rows,
navigation chrome, pickers, popovers, Button `compactLabel`, level pickers,
focus rings, world markers and grid cells) is read on the next frame. Fast
resizes and scrolls no longer run these reads during the engine's layout pass.
A form, a placement or a title style can update one frame after its bounds
change. Feedback decoration still follows its host in the same frame.

`Facet.DesignStudioKit` is now the read-only form of the Compose design editor
kit type, so a kit built with the Compose design editor has this type.
`Facet.composeDesign` returns `Facet.DesignStudioEditorKit`, whose `edit`
returns the full `Facet.DesignStudioEditor`.
`environment.safeInsets` measures each side from the full screen to the core
UI safe area with `GuiService:GetInsetArea`. On Android, the bottom value now
includes the navigation bar; before, it was always 0. A core script also gets
the status bar, bottom bar, side bar and safe zone sizes. The value follows
orientation changes.

Controls under `CoreGui` move gamepad and keyboard focus through
`GuiService.SelectedCoreObject` when the script can write it. All selection
reads and writes go through one host seam, `ctx.selection`. The
`selection-seam` check rejects a direct `SelectedObject` use in `src`.
Text size comes from a type role. The base `facet-text` rule no longer sets
`TextSize`; each Facet text node carries one `facet-type-<role>` tag, `body`
by default. A Badge label and a ShortcutHint key use `caption`, and the text of
a Chip with leading, trailing or remove content uses `control`. A pixel
`textSize` on Text, Toggle or Picker sets the size with no role tag, so a size
of 14 (the engine default) is no longer replaced by the body size. NavBar
`titleSize` is a type role.

Text fills the width that its parent gives and grows only in height. It still
hugs its words in a horizontal stack, in a parent that hugs its width and at an
explicit position. `AutomaticSize = Enum.AutomaticSize.XY` is the opt-in to hug
everywhere. Collection rows keep the cell's cross-axis size and grow only on
the main axis; `contentOverflow = "grow"` is the opt-in for growth on both
axes. Card titles and captions show at most two lines and end with an
ellipsis, so a long title in a narrow grid cell keeps the card's size.
Theme and factory `icons` entries accept a font glyph
`{ font, codepoint, tintRole? }` beside image content. Each control that takes
an icon name draws the glyph at the short side of the icon box without
`TextScaled`. The glyph follows the image icon state colors and transparency,
and state maps can mix glyph and image entries. `themes.resolveIcon` returns
the content string or the glyph table. `themes.define` rejects a glyph without
a font or with an invalid codepoint. `Facet.IconEntry` and `Facet.IconGlyph`
type the entries.

ScrollView and stack containers accept `maxHeight` beside `maxWidth` through
one native size constraint. `ScrollView { height = "hug", maxHeight = limit }`
grows with short content and caps the window for long content. Compose Design
preserves the limits and their bindings. Horizontal ScrollView keeps room for
its scroll bar within the authored limits.

`Facet.Compose` includes `cubicBezier(x1, y1, x2, y2)` from the Compose pin.
It returns an easing function for Compose motion.

`Facet.review.screens(targets?, options?)` reviews all mounted Sheets or named
screen targets in one client call during Play. It opens and closes each target,
returns one text report and reports common build and runtime errors once.

Facet Design accepts consumer kinds through `DesignContext.extension`, using
Compose Design's library extension contract. `DesignKind`, `DesignResolved`
and `DesignExtension` type the registration and editor builder. `Path.points`
and `RadialMenu.skin` accept whole theme tokens. Inline token expressions in
plain point tables still need Compose Design support.

Menus use a short fade after layout is ready, with separate theme timing for
menus and sheets. Menu overlays share their preparation result, and successful
font preparation is reused when a menu opens again.

A help tooltip no longer breaks a short word across two lines, such as
"Paus / e". Its width rounds the measured text width up to a whole pixel.

Compose Design documents can author more Facet controls without code. A Text
node can own native constraint children such as `UISizeConstraint`. Dialog,
Sheet and DisclosureGroup content fields bind a prepared slot input, so the
control keeps creation and lifetime of lazy content. Sheet `detents`, overlay
`actions` and RowActions `leading` and `trailing` emit typed tables, for
example `{ Facet.SheetDetent }` and `{ Facet.DialogAction }`. Toggle offers the
`button` presentation. Design previews resolve native datatype tokens, for
example a `UDim2` with token components, with fewer allocations.

A named Alert call such as `UI.Alert "Confirm" { ... }` type-checks in strict
consumer code without an explicit `<<unknown>>` instantiation. The generated
Design source for an Alert document now type-checks as emitted.

A `DiegeticScreen` that unmounts while it is presented returns its layers and
their input contexts to the screen. Before, the app UI was destroyed with the
display surface.

A bottom tab bar with a fixed `textSize`, or with `sections`, shows its tab
titles. Before, the title of each tab could have zero width.

A row copied into its own reorderable collection no longer stops the drag with
an error when the pointer is past the last row.

`Grid` with `aspectRatio` sets the cell height from the cell width, as
documented. Before, the cells fitted inside the control height.
Compose Design documents can author more Facet controls without code. A Text
node can own native constraint children such as `UISizeConstraint`. Dialog,
Sheet and DisclosureGroup content fields bind a prepared slot input, so the
control keeps creation and lifetime of lazy content. Sheet `detents`, overlay
`actions` and RowActions `leading` and `trailing` emit typed tables, for
example `{ Facet.SheetDetent }` and `{ Facet.DialogAction }`. Toggle offers the
`button` presentation. Design previews resolve native datatype tokens, for
example a `UDim2` with token components, with fewer allocations.

A named Alert call such as `UI.Alert "Confirm" { ... }` type-checks in strict
consumer code without an explicit `<<unknown>>` instantiation. The generated
Design source for an Alert document now type-checks as emitted.

Named control builders type-check again in strict consumer code. A named call
such as `UI.Menu "Commands"` returns a generic builder, descriptor fields such
as `DialogAction` and `SheetDetent` are read-only, and `Facet.RadialMenuBuilder`
and `Facet.AlertBuilder` type the direct call of `UI.RadialMenu` and
`UI.Alert`.

Theme readers accept shallow-frozen packages without copying them. Native
property observations expose read-only values. Controls share these observations
without treating them as writable cells.

`Facet.controls(runtime)` now loads a control family when code first reads one
of its members. `require(Facet)` and `Facet.controls(runtime)` load 82 Facet
modules instead of 275. A game that uses only `UI.Button` loads 90. An
iteration over the controls object still loads all families. The first call to
`Facet.design()` loads the design kit. The public names and types do not change.

In a compact `NavigationSplitView` with a `transition`, the closing pane keeps
its size and screen position until its motion ends. A tab bar placement or a
header that changes with the push no longer reflows the closing pane.

A new theme token, `motion.frameLimit` (0 by default, off), lets a game absorb
a slow mount frame on a device. When it is above 0, the first frame of a
navigation transition adds at most `motion.frameLimit` seconds to its clock, and
the `motion.restLimit` readiness fallback starts after the first frame with
layout. Later frames run in real time. Keep it at 0 in fixtures that advance one
large step and expect the motion to finish.

A `TabView` placement change to `"none"` slides the bar out over the new theme
token `motion.durations.tabChrome` (0.3 seconds), and the content grows when the
bar is gone. A change back slides the bar in. A push that hides the tab bar no
longer removes it before the push motion starts.

A slot collection again creates new slot nodes before item watches that look
them up in the same settle. Compose 147835f keeps an equal-cut-off formula's
consumers in propagation order.

When the destination of `UI.Travel` changes to a node at the same position and
size as the content, the content lands in the new destination at once. It does
not start a flight. A tile that a reserved-slot preview moved into an empty slot
thus stays visible in place when the drop gives it that slot.

In a collection with `slots`, an accepted payload from another source now
parts the items at `info.insertion` while it hovers. The items between the
insertion and the nearest empty reserved slot move one slot toward that empty
slot. The items return when the payload leaves. The landing of a drop with
`travel` uses the same slot. Each node from `slotControls.nodeOfKey` follows the
displayed position of its item, so content that you place on a slot node moves
with the item.

A DiegeticScreen waits for a slow first room frame instead of returning to the
screen. A heavy scene that takes longer than `motion.restLimit` to settle now
enters the room.

A reorderable collection row with a `drag` `previewScale` now lifts when you
press it with a mouse or touch, as `UI.draggable` does. The lift uses the
`motion.durations.pressLift` theme token. The row settles when you release it
without movement. When a drag starts, the drag preview continues the lift.

In a collection with `slots`, an external payload whose first key names an
occupied slot now opens a gap at `info.insertion`. Only a key with an empty
reserved slot returns the payload to that slot.

A palette-only theme swap does no control work. Controls ignore a package change
that differs only in palettes. A StyleSheet writes only the color tokens that
changed and applies only the rules that changed. Compiled rules are shared by
every StyleSheet for the same frozen package. A swap across 200 buttons costs
about 15 us instead of about 950 us in the engine double.

Collection rows write LayoutOrder, Position and Size only when they change.
Text that a function supplies is written only when the result changes.

The `transition.scale` zoom no longer scales the page content, so text does not
step between sizes during motion. The content fades in at full size. A plate in
the color of the nearest opaque ancestor grows behind it. The plate and its
`TransitionScale` UIScale exist only during motion. Without an opaque ancestor,
and in a Sheet, the zoom is a fade. `scale = true` starts the plate at the
theme value `motion.materialize.zoom` (0.92 in Facet Neutral). The zoom uses
the new theme tokens `motion.durations.zoomPresent` (0.3 seconds),
`motion.easing.zoomFade` (`outCubic`) for opacity and `motion.easing.zoomScale`
(`outSine`) for the plate, so the fade leads. In a compact NavigationSplitView,
only the pane that opens zooms. The pane that closes only fades.

Auto-localization stays on for text that the author gives as a plain string,
also when a control reads it through a function. Only `UI.Text` and `UI.Badge`
text that the author binds to a readable or a function turns it off.

Unwrapped text given as a fixed string builds its font-metric size floor when
its text first changes or when the engine reports that the text does not fit.
Until then it uses the native automatic size. Bound text keeps its floor from
the start.

A negative pixel width or height, such as a computed extent before the first
measure, resolves to 0 instead of raising.

Text labels leave their first layout to the engine and read their geometry from
the `Changed` signal. Text floors apply directly from text, style and
measurement events instead of through watches. A bound Badge caption is
computed once per change.

Bound text, given as a readable or a function, sets `AutoLocalize` to false
unless you set it. Engine auto-localization of each change costs about 15 µs.
Text floors build without `Compose.show` or a separate measurement watch, and
text labels observe their geometry by signal instead of by a poll each frame.
A NavigationStack without transitions shows each page in a plain frame after it
is ready. `lute run tools/facet build studio-bench` builds a Studio place that
times the comparison workloads natively.

Facet pins Compose `d6592f9`, which allocates less per watch, shared
resource and observation. Text layout reruns only its measurement when text
changes, caches native measurements, and builds measurement parameters on
demand.

World drag sources use `UI.draggable` with `world` options and the shared drop
session. World targets supply `worldPlacement` through `DropInfo`. See
[world drag and drop](docs/reference/nodes/draggable-and-dropTarget.world.md).

`Facet.Compose` now includes `Compose.map` from Compose d74f653.
`Compose.map(source, transform)` returns a body that transforms the value of one
cell or formula. A property bound to it updates without dependency tracking.

## 0.12.0

Facet provides Roblox UI controls built on Compose and native engine APIs.
Use the [API reference](docs/reference/api.md) for public contracts and the
[architecture](docs/guide/architecture.md) for ownership and engine integration.
Use the [game UI design guide](skills/use-facet/references/GAME_UI_DESIGN_GUIDE.md)
for composition, input, and device decisions.

`Facet.review` reports design patterns that make a screen look generic, on a
live screen or a saved dump; `facet critique` turns captures and those
findings into a packet for a fresh reviewer. `Facet.themes.define` adds
`report.advice` for a flat type scale and for a display family on only one
type role. `Facet.review` reports `stacked-choices`: short choices stacked one
per row in a wide space; `hollow-plate`, `lopsided-page`, `floating-text` and
`touch-control-overlap` report empty plates, one-sided pages, HUD text on the
world and controls over Jump. `Facet.SkinLayerPatch`, `Facet.ThemeRule` and
`Facet.ThemeRuleProperties` type a theme's `chrome` and `rules` tables.

ScrollView and card Collections keep room for the theme's plate glow and
edge, so plates at the canvas edge are not clipped. `UI.environment()` without
a source returns the app's shared camera environment, also from a property
function that reruns outside an owner. A NavigationStack page that fails to build
reports its error to `onError` or the output. RadialMenu sizes its ring from measured captions, paints bands wider than the
engine's 100-pixel Path2D limit as adjacent strokes so captions stay inside
their wedges, judges a measured caption by its real width and never lets an icon that several items share replace a
label.

The version in `src/init.luau` identifies the source package. A local build does
not publish it. Run `lute run tools/facet package status` for publication and
verification status. See [package operations](package/README.md).

The [verification scope](docs/guide/verification-scope.md) defines evidence
limits. The [evaluation protocol](eval/README.md) defines game comparisons;
`eval/latest` contains the latest saved submissions.
