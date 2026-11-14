# A theme for this product

Facet supplies familiar controls; the product supplies their visual character.
The neutral package is a technical base and a possible professional style. It
does not decide how a game looks. The skill's [direction card](../SKILL.md#write-the-card)
is the normal way to choose a direction. This page covers the cases around it:
matching finish to the game, a target chosen from rendered concepts or supplied
by the user, labels over artwork, and the theme and image contracts.
[Finish](finish.md) maps a direction to theme values.

## Choose a direction

### Match the finish to the game

Choose the kind and level of detail from the game's world, art, tone, pace and
audience. Polish means deliberate, consistent execution within that visual
language. Crisp pixel art, simple rounded forms, expressive illustration and
detailed materials can all be finished. More texture, realism or geometry does
not make a UI better.

The user's direction and the game's existing art take precedence over any
genre tendency. Games in one genre can have different identities: do not give
every sci-fi game neon or every fantasy game parchment. A quiet tool or a
minimalist game can express itself through type, shape and timing alone.

When a runtime font cannot reproduce a target, keep its hierarchy with an
available family, scale, spacing and placement.

### Inspect references before choosing the composition

When the host can show images, look at screens from shipped games with a
related task, tone or input, and at one source outside games, such as print,
packaging or stage design. [Game UI Database](https://www.gameuidatabase.com/)
and [Interface In Game](https://interfaceingame.com/) collect game screens.
Take the principle that makes a reference work, then design this product's own
treatment. Do not reproduce a reference with changed labels. Skip this step
when the host cannot display images; do not claim to have inspected pixels
that the tool did not show.

### Resolve the whole composition

Use finished concept art when image generation is available and the brief is
an open expressive game, or when the user asks to explore concepts. Otherwise
the skill's card and sketches decide.

Render three whole-screen directions for the same task, facts and states. Vary
composition, type and rendering approach, not only palette or subject art. They
must stay visibly different when viewed small or in grayscale, and each must
suit the game's world and audience. Give the art tool the brief, the player
task, representative content, the intended finish and the areas that need
readable live text. State sizes and strengths as quantities. Words such as
restrained, sparse and subtle ask the tool for the neutral theme; use them
only when the brief asks for a quiet product.

Keep the supplied game scene and subjects fixed across the UI alternatives.
If they are unavailable, label their stand-ins as context. The concept's
commitment applies to the interface, not to invented world content; follow
the [UI scope](../SKILL.md#ui-scope).

Compare them together for character, finished craft, task clarity and a
credible route to runtime assets. If all three are generic, revise the set.
Choose one without a user approval step, and keep the image.

### Commit to the visual target

| Target | Commitment |
| --- | --- |
| A concept that the agent chose | Keep its composition, relative scale, type hierarchy, materials, depth and control shapes. Limited refinements are allowed; a different design is not. |
| A reference that the user supplied | It is the specification unless the user calls it inspiration or limits it to named qualities. Do not substitute a preferred style. If a technical or usability limit forces a material departure, ask the user. |
| A sketch or wireframe offered as "roughly this" | It fixes content, relationships and behavior. Develop the styling, proportions and finish that it leaves open. |
| The interface that the game already has | For a replacement it is the specification: match its screens, controls and words. For an improvement it is the direction: keep what makes the game recognizable and improve inside that language. The user's instruction decides which, and can fix or open any part. |

Decide the role from the user's words, not from how polished the image looks.
Write down the few visible relationships that define the target: the major
regions and their relative sizes, the type roles, the layering, the material
edges, and the choice and action treatments. Write each as a measure against
the screen, not as a word. A mood description does not constrain a build,
and neither does "thin" or "subtle" beside a target that shows a size.

A target usually omits states, opened controls and feedback. Design those from
its own materials, shapes and type, so they do not look like parts from another
interface.

### Translate the selected screen

Take the target apart into the skill's layers: ground, lead, controls and
type. Derive UI assets for their runtime roles, reuse supplied game content,
and keep quiet areas for live text. Do
not flatten controls, labels or focus into a picture, and do not rebuild the
target as one fixed canvas. A fixed canvas matches the picture at one size and
fails on every other screen.

Build the first screen at the target's aspect ratio, then compare the capture
and the target at the same viewing size. For each defining relationship, decide
whether the capture keeps it, weakens it or replaces it. Common losses are a
control that became an ordinary rectangle, a subject that blends into its
ground, display type that became body type, and state feedback that became a
small line of text. Repair the asset, the theme or the composition that lost
the quality. More small ornaments on a generic structure do not repair it.
Correct factual errors in a generated image without changing its direction.

If the runtime cannot carry the target's finish, report the unmet quality and
the limit. Do not lower the target without saying so.

Then adapt the same layers to the other screens, as the skill's
[step 3](../SKILL.md#3-make-one-build-fit-every-screen) describes. The other
forms keep the target's materials and hierarchy; they need not keep its
arrangement.

### Build the visual language into the task

When visual recognition drives a choice, make the subject part of the choice
surface at a useful size. A tiny glyph in a text row beside a separate large
illustration leaves the choice itself generic. Keep the hit target and state in
one real control. Dense comparisons, settings and text-led choices can use
quieter rows.

Keep the main action in a stable place within one task. Reserve room for
pending, error and success messages, sized for the longest supported text, so
feedback does not push the action away from the pointer, thumb or focus. If
success replaces the action with a new command in the same place, require a
fresh activation.

## Prove the direction in one task

### Protect labels from artwork

When a label or state mark sits over an image, a texture or a moving scene,
give it a quiet area: a plate from the same material language, a sufficiently
opaque backing, or a part of the art that is plain in every crop. A font color
that contrasts with the average image color can still vanish against the
detail behind single letters. A shadow or outline alone is not enough.

Plan that area when making the art, with room for larger and translated text.
Keep decoration outside it. When repairing contrast or fit, use the direction's
own materials and edges; a generic utility panel weakens an illustrated game.

Keep selection distinct from focus. Use a selection cue that is not only color,
and place it clear of the focus ring's stroke and halo. Check the combined
state at the smallest supported size, then move focus to a peer and confirm
that the selection still reads.

## Theme contracts

Read `Tasks.theme` for the definition contract, then only the needed
`Themes.definition`, `Themes.palette`, `Themes.art` or `Themes.chrome` nodes.
Define one package with `Facet.themes.define` and check its report. If the
definition fails, repair the reported errors; do not fall back to the neutral
package. Theme validation checks semantic color pairs. It does not check text
over imagery, asset access or readable labels on art.

Three complete references show different treatments. Their cues belong to
their own games.

| Reference | Treatment |
| --- | --- |
| Riverbank | [Collection](../examples/collection.luau) and [Exploration](../examples/exploration.luau): native supply models, botanical type, pale material |
| Neon Circuit | [Theme](../assets/neon-circuit-theme.luau): panel edges through `rules`, a glow focus, a panel gradient, display and numeral families |
| Pixel Quest | [Theme builder](../../../examples/themes/pixel_quest.luau): image-backed plates, pixel borders, selected art and square focus brackets |

Choose motion from the meaning of the change. A slide shows entry into a
deeper page. A selection change or an accepted result within one task usually
needs a stationary update; `NavigationStack` with `transition = false` keeps
history and focus restoration without page motion. Transparent pages over
shared scene art show both pages while they move, so give a sliding page a
surface or keep the change stationary.

In repeated browse rows, keep idle surfaces quiet. Reserve strong glow or
action emphasis for the selection, the current input target and the next
action. Do not put one accent shadow on every row through a shared panel skin.

## Three ways to use images

| Need | Use | Responsibility |
| --- | --- | --- |
| Reusable control surfaces and states | Theme `assets` and `chrome` recipes | Stretch or tile geometry, content insets, state paint and readable focus |
| Subject art, portraits or illustrations | `Image` or `AsyncImage` | Fit or crop, useful scale, loading and failure state, and an accessible label |
| Game-specific framing or decoration | `UI.Image` layered in a `ZStack` | Bounds, clipping, layering and input clearance; it does not replace a control |

Decide each image's runtime role before making it; [art](art.md) lists the
geometry for each role. A picture of a whole menu is not an interface. Keep
labels, prices and actions as live text and controls.

A painted button is still one `Button`. Decorative images must not cover its
target or intercept input, and an image beside a transparent Button does not
inherit the Button's state paint. For an illustrated choice, compose the art
with one semantic control; do not add a second click handler on the image.
Read `Button.records`, `Button.label`, `Themes.art` and `Themes.chrome` for the
exact contracts, and the [worked translations](visual-translations/guide.md)
for a shaped action and a nine-slice choice.

Theme asset `content` is a string asset ID, not an `ImageContent` value.
[Upload](asset-upload.md) authored images, including icons, and use the
returned IDs. Do not use EditableImage, embedded pixels or runtime
reconstruction for authored art. Roblox can resize an upload, so take slice
and crop coordinates from the delivered image in Studio.

Ten-foot metrics do not scale every art inset. Keep reusable assets small,
because theme assets preload unless marked lazy. Pause hidden live subjects
and dispose owned resources.
