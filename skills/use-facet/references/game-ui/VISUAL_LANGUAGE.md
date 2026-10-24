# Visual language

Part of [game UI design](../GAME_UI_DESIGN_GUIDE.md).

The look of game UI does two jobs.  The functional layer makes information usable.  The flourish layer makes the interface belong to the world.  When they conflict, the functional layer wins.  Decide both before the first screen and put them in the theme, so every surface shares them from the start.

## Write the direction first

Before you choose a single color, write the direction in a few words for each row.  These three directions show how far apart two games of one genre can be:

| | Toy kart racer | Night-city street racer | Fantasy expedition |
| --- | --- | --- | --- |
| Setting and tone | A bedroom floor, playful, loud | Wet asphalt at 2 a.m., tense, cool | Old maps and field notes, curious |
| Shape | Chunky, rounded, thick outlines | Thin rules, cut corners, slanted edges | Torn edges, ink borders, wax seals |
| Material and pattern | Glossy plastic, stickers, confetti | Glass, sodium glow, scan lines | Parchment, ink wash, compass lines |
| Type voice | Rounded and bold | Wide and technical | Calligraphic headings over a plain body |
| Accent | Primary red | Sodium amber | Wax-seal red |
| Motion | Springy overshoot | Fast, clipped, no bounce | Slow ink-like fades |

A direction is specific.  "Dark with a bright accent" is not a direction; it describes most generic interfaces.  Take each row from the game's world, its objects and its fiction.

Choose the type voice from the face's visible traits.  Rounded ends feel friendly, wide letters feel technical, high-contrast strokes feel formal and brush forms feel handmade.  Set a real line from the game, such as "Final lap", and check it in a capture at its real size.

## The functional layer

### Values and contrast

Compose with four to six values: the backdrop, the surface, a raised plate or control, secondary content, content and the strongest content.  Only the focal content and the focus indicator reach the extremes.  To make one thing stand out, quiet the others: dim what is not selected and lower the contrast of what is locked.  This is emphasis by de-emphasis, and it costs nothing.

Keep body text at 4.5:1 or more against its plate, and large text and essential marks at 3:1 or more.  Check the ladder in numbers before you look at a capture: the theme report lists the contrast of each text pair, and adjacent plates need clearly different lightness.

### Type

Give each type role one meaning and keep it across the game.  `title` and `heading` name places and sections.  `strong` names an item.  `body` explains, and `caption` supports.  `numeral` shows a balance, cost, score or time.  `label` and `control` sit on controls.  About four visible sizes per surface is enough.

Put personality in a display face for titles, headings and large numbers.  Keep the body face plain and readable, even when it is less themed than the headings; players notice unreadable text, not a plain body.  Pair a display face with a plain sans body, or use one family with clear weight steps.  Roblox's built-in families cover several voices: Builder Sans is plain, Nunito is rounded and friendly, Michroma is wide and technical, and Fondamento is calligraphic.

Check digits and colons in the chosen face at small sizes.  Reserve the width of a changing value so digits do not push their neighbors.  Let text wrap and grow instead of squeezing it into a box.

### Icons

Use one icon family.  Keep the stroke weight and the corner shape consistent, and count negative space as stroke.  Icons that navigate or command are functional: use a convention that players already know, such as a gear for settings, or add a label.  Decorative icons, such as nodes in a skill tree, can be expressive, because the text beside them names the item.  An icon does not need to depict its effect literally; the label explains the effect.  Check each icon at the size it appears.  When you generate custom icon art, design it for that size and remove detail that turns to noise.  Keep a glyph at 3:1 or more against its plate.  `Icons.names` lists Facet's built-in glyphs, and a theme package can supply its own icon set.

### Space and alignment

Use the theme's space tokens for every gap and padding, and one gutter for page margins.  Align text on shared edges and comparable numbers on one line.  Separate groups with space first.  A box around every fact flattens the hierarchy.

## The flourish layer

### Color

Choose one accent, at most two.  Use it for focus, the primary action and the current selection.  Do not use it on every button or border.  The accent becomes the game's signature, because it sits on what the player looks at most.

Tint the value ladder toward the world's palette, and keep each step's lightness so the ladder still separates without hue.  Keep danger, success and warning in hues distinct from the accent, and pair each one with an icon or a word.  Avoid distinctions that depend only on red and green.

Choose light or dark plates from the world, not by habit.  A sunny world can carry light plates; a night world suits dark ones.  Over 3D gameplay, plates need a consistent separation from the scene in both cases.

### Shape, pattern and material

Shape carries tone before the player reads a word.  Round, soft corners feel friendly and toy-like.  Sharp, slanted edges feel fast or technical.  Irregular edges feel handmade.

Patterns carry setting and era.  Geometric art deco lines suggest 1920s luxury.  A blueprint grid suggests building and technology.  Knots and runes suggest myth.  Halftone dots suggest comics.  Scan lines turn a flat panel into a screen.  Use a pattern at low contrast in a background, a border, a corner or a header.

Material adds physicality: paper, metal, wood, glass or plastic.  Apply it to panels, control plates and bars.  One pattern and one material are usually enough.  Keep body text on calm plates.

### Motion character

Timing is part of the identity.  Springs with a little overshoot suit a toy world.  Short, clipped transitions suit an instrument panel.  Keep every duration short, never block input, and give reduced motion the same result.

## Readable over the world

HUD elements sit on a scene that moves and changes brightness.  Protect each one:

- **Backing panel.**  A plate behind text and readouts, for example `surface = "panel"`.
- **Stroke.**  An outline around a mark or text, so either side of the scene reads.
- **Shadow.**  A soft shadow under light marks.  It does little for dark marks.
- **Container.**  A circle or frame around an icon.  Many HUD icons sit in containers for contrast, not decoration.
- **Vignette.**  A darkened screen edge behind the HUD, drawn by the game.

Check each element over the brightest and darkest places in the game, in bright effects and in every lighting state.  Facet's focus ring adds a contrasting `halo` so focus reads over any scene.

## Objects and art

Show the actual object.  Match camera angle, lighting and scale across comparable objects, and frame each silhouette with room for its extremes.  Use Stage when the player needs to inspect a 3D object, and a static image when it carries the same decision at lower cost.  Art identifies; a decorative image repeated across every item does not.  When art is missing, keep the name and the layout.

## Put it in the theme

| Decision | Theme field |
| --- | --- |
| Value ramp and accent | Palette `colors`: `surface`, `surfaceStrong`, `content`, `contentStrong`, `accent`, `onAccent`, `danger`, `success`, `warning` and their `on` colors.  Palette `extra`: `control`, `controlSelected`, `contentSecondary`, `hairline` and opacities.  Optional `selection`, `scrim` and `inverseSurface` |
| Type voice and sizes | `metrics.typography` per role: `font.family`, weight and `size`; `controls.typography.minimumSize` |
| Shape | `metrics.radii` (`control`, `panel`, `pill`, `tab`) and `metrics.strokes` |
| Spacing | `metrics.space` |
| Material | `assets` and `chrome` slots (`panel`, `control`, `field`, `badge`, `barTrack`, `barFill`, `panelTail`) with `nineSlice` or `layered` recipes and state art |
| Focus look | `chrome.focus` kind: `ring` (with an optional `halo`), `glow`, `brackets` or `nineSlice` art |
| Motion character | `metrics.motion` durations, easing and springs |
| Anything else | `rules` with `{ role = ... }` and `{ metric = ... }` values |

`Facet.themes.define` returns a report.  Check `report.ok`: it refuses main color pairs below 4.5:1.  Chrome art needs image assets that the experience can use.  Without them, express material through the palette, radii, strokes, type and motion; do not leave a broken image in its place.

The repository's example themes show how far a package can go.  Fantasy Ornate frames its panels and Fantasy Parchment uses paper.  Pixel Quest draws pixel art and Sci-fi HUD draws instruments.  Glossy Touch uses large touch plates, and Classic Desktop serves dense tools.  Their builders are game-owned examples in the Facet repository, not part of the installed package; read them for technique when you have the repository.

## Check the look

- Judge a capture by lightness and size, ignoring hue.  The focal area, the selection and the primary action still lead.  With an image tool, desaturate the capture to confirm.
- Place each HUD element over the brightest and the darkest scene.
- View the result at its real size and distance: a television from across the room, a handheld at about 30 cm.
- Run the longest translation and the largest text setting.
- Ask whether the screen could belong to another game.  If it could, the flourish is missing.

Read `Tasks.theme` for a working package and `Theme-identity` for mapping a direction to roles.  Read `Themes.palette`, `Themes.metrics`, `Themes.chrome` and `Themes.skin` for the exact options.
