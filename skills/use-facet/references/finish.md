# Finish

This page maps each line of the [direction card](../SKILL.md#write-the-card)
to the Facet value that realizes it. Read it once for a new interface. It names
levers and where their contracts are; it does not choose a look. The sample
values belong to their own examples.

## Where the character lives

Put each decision in the theme first. A theme value reaches every control,
state and device form. One-off paint on a control reaches one place and misses
its hover, pressed, selected and ten-foot forms.

| Card line | Theme value or control | Contract |
| --- | --- | --- |
| Ground | `UI.Screen { ground = UI.Image { ... } }` draws art behind the content and continues it to every glass edge. `surface = "surface"` does the same with the `surface` color, and `extra.chromeGradient.surface` makes that plate a gradient; see [the ground](#the-ground) | `Screen.reference`, `Themes.palette` |
| Palette | `style.themes[n].colors`: `surface`, `surfaceStrong`, `content`, `accent`, `onAccent`, and the status pairs. `extra`: `control`, `controlSelected`, `onSelected`, `selection`, `contentSecondary`, `hairline` | `Theme-identity`, `Themes.palette` |
| Type | `metrics.typography`: `title`, `heading`, `numeral`, `strong`, `label`, `control`, `body`, `caption`. Each role takes `size` and `font = { family, weight }`; `family` is a name from the table below or a full font path | `Tasks.theme` |
| Shape and edge | `metrics.radii` (`control`, `panel`) and `finish`: the edge, the lift, the glow and the sheen of every plate as values; see [edge and depth](#edge-and-depth) | `Themes.finish`, `Themes.definition` |
| Controls | `chrome.control`, `chrome.panel`, `chrome.field`, `chrome.badge`: `native`, `nineSlice`, `tile`, `frame` or `layered` art with per-state assets and `contentInsets` | `Themes.art`, `Themes.chrome` |
| Focus and selection | `chrome.focus`: `ring`, `glow`, `brackets` or `nineSlice`. `extra.controlSelected` and the control's `selected` art | `Themes.chrome` |
| Main action | `appearance = "emphasis"` uses `accent` and `onAccent`. A uniquely shaped action is one `UI.Button` with an authored face; see [worked translations](visual-translations/guide.md#use-the-control-contracts) | `Button.appearance` |
| Lead | `UI.Image` for art (`width`, `height`, `aspectRatio`, and `scaleMode = "fit"` or `"crop"`), `UI.Stage` for a lit 3D object, `UI.Path` for a stroked vector shape, or the content itself | `Image.reference`, `Stage.card`, `Path-shapes` |
| Response | `metrics.motion` tokens and the effect controls (`Flash`, `Shake`, reward sequences, `Travel` between containers) | `Themes.definition`, `Zoom-and-travel` |

`Facet.themes.define(definition)` returns `theme, report`. Check `report.ok`,
repair `report.errors` and read `report.advice`. Each palette pair needs a
contrast of 4.5:1. Give the first task its theme through
`Facet.app({ name = ..., theme = theme })`.

A definition that changes only `accent` leaves the neutral theme in place.
So does one that sets only colors, fonts and radii: every plate is still a
flat fill with no edge. A definition that sets the ground, two type families,
the radii, one edge or depth treatment and the selected state has left it.

## Edge and depth

The neutral plates are flat fills, and a plate close to the color of the
ground disappears into it. `finish` in the theme definition states the edge
and the depth of every plate as values, and `Facet.themes.define` draws
them. State it in every theme; `Themes.finish` has each value.

```luau
finish = {
    edge = { width = 1, role = "hairline" },
    depth = { lift = 0, glow = 0, sheen = 0 },
}
```

Take the values from the card as [the concept corrected
it](../SKILL.md#read-the-card-off-the-concept):

- **The edge.** `width` in pixels, the palette `role` of the line and its
  `transparency`. A panel radius of 0 gives the line square corners.
- **A raised plate.** `lift` is the fall of a shadow in pixels, `blur` its
  softness and `side` its fall to the right. `blur = 0` is a hard shadow. A
  shadow shows on a light ground only.
- **A lit plate.** `glow` is a halo in pixels in the `role` color, for a
  dark ground. A plate has a lift or a glow, not both.
- **A sheen.** `sheen` from 0 to 1 washes the `role` color down from the top
  of the plate.
- **The controls.** `edge.controls = true` draws the edge on Buttons and
  Stepper keys, and `depth.controls = true` gives them the shadow of the
  plates. Do not write a stroke rule on a control's tag for this: the edge
  of `finish` is drawn inside the box, and a stroke that you add is drawn
  outside it and takes the gap to the next control.

Zeros are a decision too: a quiet tool states them. Keep the strong edge
for the plates; equal bright strokes on every nested part erase the
hierarchy.

### What a value looks like

A value that is too small draws nothing that a player sees, and the theme
stays flat with its card line ticked. These are measures on a screen of
1080 lines with a saturated color. They say what shows; they do not choose
a look.

| Value | What shows |
| --- | --- |
| `edge.width = 1` | A hairline. In the `hairline` color, or with a transparency over 0.5, it is hard to find. |
| `edge.width = 2` | A clear line. |
| `edge.width = 3` or `4` | A frame. It is the first thing that a player sees of the plate. |
| `glow` under 8, or `strength` under 0.4 | Nothing. `report.advice` says so. |
| `glow` 12 to 16 at a `strength` of 0.5 to 0.7 | A soft light around the plate, on a dark ground. |
| `glow` 24 or more at 0.7 to 1 | A lit plate. On a bright ground only this range shows. |

Read the concept in these terms. A plate whose edge you can see in the
concept at thumbnail size has a width of 2 or more. A plate that is lit in
the concept has a glow in the last two rows. Set the first value at the
strength of the concept, look at the capture, and reduce it only when it
competes with the lead. A direction with no line and no light states zeros
and gets its character from the ground, the type and the art.

`finish` covers what most directions need. Beyond it:

- **Another edge.** A theme rule draws a stroke on any tag, such as
  `.facet-surface::UIStroke`, with `Color = { role = ... }`, `Thickness`
  and `Transparency`. Pass it as `rules`.
- **Focus.** `chrome.focus = { kind = "glow", color = "$Accent" }` in place
  of the ring, or `brackets` for a hard-edged world.
- **Art.** `chrome.panel` and `chrome.control` take nine-slice art when the
  material is drawn; see `Themes.art`. State `finish` with zeros then.

Check the result with `app.specimen()` and in a capture over the real
ground. An edge that reads on a plain backdrop can vanish over a bright
scene.

## Type

Type carries more identity per token than any other lever. Give the display
role a family with a voice. Give the reading roles a family that stays legible
at caption size. Make the leading line at least twice the body size unless the
interface is deliberately dense.

These families load from `rbxasset://fonts/families/<Name>.json` (verified in
Studio in November 2026). The number is how many faces the family has; a family
with one face has no bold or light weight. Check a family that is not listed
with `TextService:GetFamilyInfoAsync` before using it; a missing family falls
back silently.

| Voice | Families |
| --- | --- |
| Clean interface sans | BuilderSans (7), Montserrat (18), GothamSSm (18), SourceSansPro (12), Roboto (12), Ubuntu (8), Arimo (8) |
| Soft or rounded | Nunito (14), FredokaOne (1), DenkOne (1), ComicNeueAngular (1) |
| Geometric or elegant | JosefinSans (14), Jura (5), BuilderExtended (5) |
| Technical or sci-fi | TitilliumWeb (11), Michroma (1), Zekton (1), Sarpanch (6) |
| Condensed or signage | Oswald (6), RobotoCondensed (6), HighwayGothic (1), AmaticSC (2) |
| Book and classical serif | Merriweather (8), AccanthisADFStd (1), RomanAntique (1), Balthazar (1), Guru (1) |
| Calligraphic or blackletter | Fondamento (2), GrenzeGotisch (9) |
| Cartoon display | LuckiestGuy (1), Bangers (1), Creepster (1) |
| Handwritten | PatrickHand (1), Kalam (3), IndieFlower (1), PermanentMarker (1) |
| Mono, typewriter or pixel | RobotoMono (14), Inconsolata (8), BuilderMono (3), SpecialElite (1), PressStart2P (1) |

Check the actual labels, numerals and punctuation in the chosen family at the
smallest size. Some display families draw thin colons or have capitals only.
Use `textRole` or `textSize` roles on Text so accessibility scaling works.

## The ground

The ground is the largest surface on the screen, so it sets the first
impression. Choose its kind from the card.

- **A color field.** `UI.Screen { surface = "surface" }`. The plate reaches the
  glass under the top bar and the device cutouts, and the content stays safe.
- **A gradient or a lit field.** Add `extra.chromeGradient.surface` to the
  palette: `{ rotation = 90, stops = { { t = 0, r, g, b }, { t = 1, r, g, b } } }`.
  The same key works for `panel`. The stops multiply the plate color, so set
  the plate color light and put the color in the stops.
- **A material or a scene.**
  `UI.Screen { ground = UI.Image { image = art.ground, scaleMode = "crop" } }`.
  Facet sizes the art to cover the screen and continues it to the glass,
  under the top bar and the device cutouts. The content stays safe. Use
  `scaleMode = "tile"` with a `tileSize` for a repeating material. For more
  than one layer, pass a `UI.ZStack` of images, for example a backdrop with a
  counter along its bottom edge. Give the Screen no `surface`. Keep the focal
  part of a scene near its centre, because phones and wide screens crop
  different edges.

A piece that belongs to an edge, such as a canopy, a rail or a counter, is its
own layer of that `ZStack`, pinned to its edge: a filling stack with
`distribute = "start"` or `"end"` that holds the image. Only the far backdrop
crops. A piece that is painted into the backdrop disappears when a short or a
narrow screen crops that edge away.

Do not make a separate ScreenGui for the ground, and do not change
`ScreenInsets`. An image among the content stops at the safe area, and on a
phone the game world then shows in a band beside or above it.

Protect live text from a busy ground with a surface from the same material
language, not a generic dark box. See [labels over artwork](game-themes.md#protect-labels-from-artwork).

## Native drawing

Many graphic directions need no image file.

- `UIGradient` on a frame gives a lit surface, a sheen or a vignette edge.
- `UIStroke` gives an outline, a double rule (two nested frames) or an inked
  edge. `UICorner` with a large radius gives a pill, a token or a disc.
- `Rotation` on a `ZStack` or an image gives a diamond, a ribbon end or a
  tilted card. A small rotation on a few faces makes a hand-placed
  arrangement. A stack keeps its direct children upright, so rotate the face
  inside the child.
- `UI.Path` with `Facet.pathShapes` strokes arcs, rings and needles.
- A `ZStack` with an offset darker copy behind gives a hard shadow.
- `UI.Stage` shows real 3D parts with lighting when the subject is an object.

A glyph that is the subject's real marking, such as a card suit or a music
note, is content. A decorative Unicode symbol or an emoji is not a substitute
for a character, a creature, a vehicle or a place.

## Quiet interfaces

A professional tool, a dense manager or a text-led game is finished when it is
calm, fast to scan and familiar. Decoration does not supply that.

- **Hierarchy inside each row.** Give the identifying text, the summary and
  the supporting facts three distinct treatments of weight and color, not
  three sizes of one gray.
- **Rhythm.** Use the theme's space steps consistently. Align comparable facts
  on shared edges. Separate groups with space or a hairline, not a box around
  each fact.
- **Density that fits the input.** Rows can be compact for a pointer and must
  reach the touch target on a phone. Let the theme's target sizes decide.
- **Every state.** Design unread, selected, hover, focused, disabled, empty,
  loading and error. The states are most of what makes a tool feel complete.
- **The platform's arrangement.** Use panes side by side on a wide screen and
  one step at a time on a phone, with the same selection and drafts.
  `NavigationSplitView`, `TabView` and `Table` own those changes.
- **One accent.** Use it for the main action and one state. Restraint makes
  it mean something.
- **Small truthful details.** Initials or avatars, counts, relative times,
  attachment marks and keyboard hints make a tool look inhabited.

Name the product family that users already know and match its conventions
before inventing new ones.
