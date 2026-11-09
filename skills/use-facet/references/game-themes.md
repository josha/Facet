# A theme for this product

## Choose a direction

For a new interface or a visual redesign, choose its visual identity before
building screens. Start with the brief, audience, pace, world and existing art.
Facet supplies familiar controls; the product supplies their visual character.
The neutral package is a technical base and a possible professional style.
It does not decide how every game should look.

### Inspect references before choosing the composition

For a new game direction, inspect screenshots of shipped games with a related
player task, tone or input context. [Game UI Database](https://www.gameuidatabase.com/)
and [Interface In Game](https://interfaceingame.com/) collect such screens.
An explicitly spare native or text-led brief can use its actual first screen
as the design target without a separate image-reference search.
Open the images at a useful size; search snippets and a list of game names
are not visual analysis. Prefer choice, detail and result screens relevant to
the task over an unrelated title screen. Supplied art and established game
screens can provide the reference for an existing project. If visual references
are unavailable, state that limit and work from the brief.
If image search returns only URLs or descriptions, open the chosen image in
an image viewer or capture it in a browser before calling it inspected. Keep
the reference link and a concrete observation from the visible image in the
working notes. Do not claim to have inspected pixels that the tool did not show.

Identify the principles that make the references work, then design this
product's own treatment:

| Inspect | Turn the observation into a decision |
| --- | --- |
| Composition and scale | What leads, how much room the subject gets, and how the choice relates to its result |
| Silhouette and material | How frames, tabs, plates, edges and negative space belong to the game |
| Type and graphic rhythm | Display type versus reading type, quiet areas versus emphasis, and repeated motifs |
| Subject and state | How art identifies a choice, how selection differs from focus, and how acceptance changes the scene |

Record a short direction in working notes, with the reference links and the
reasons for the choices. Describe visible decisions, such as an illustrated
item on a paper label, rather than adjectives such as "fun" or "premium".
Use references to judge clarity, material quality, subject scale and control
craft. Create the composition, assets and visual motifs for the current brief;
do not reproduce a reference screen with changed labels. An original direction
can retain familiar genre arrangements and standard controls. It need not
invent new interaction conventions. Choose a base theme after this decision.

These examples assume different briefs. They illustrate decisions, not presets
or requirements for their genres:

| Product and intended feeling | Possible visual direction |
| --- | --- |
| Toy racing game: playful speed | Bold readable display type, toy-plastic plates, track markings, car portraits and a brief finish-line flourish |
| Handcrafted bakery game: warm and tactile | Recipe-paper surfaces, stamped headings, illustrated pastries and a soft response when an order completes |
| Abandoned research station: quiet tension | Instrument labels, spare angular frames, subdued phosphor colors and a restrained warning pulse |
| Professional mail app: calm and efficient | Neutral surfaces, clear message hierarchy, familiar icons, aligned rows and subtle selection feedback |

Games in the same genre can have different identities. Derive the choices from
this game's art and tone rather than applying neon to every sci-fi game or
parchment to every fantasy game. A mail app can be deliberately familiar, like
Apple Mail or Gmail. A minimalist puzzle can express play through type, shape
and timing. Fun does not always mean bright colors, bounce or heavy decoration.

### Resolve the whole composition

For a new expressive game direction, make and review a visual study before
building functional routes. It can use static representative data. Resolve the subject, type hierarchy, control surfaces,
state marks and use of space together. Use a styled native prototype, a drawn
mockup or a generated concept. An existing screen can serve when it already
establishes the intended direction. A wireframe or isolated character image
does not show how the complete interface will feel.
Inspect an actual image of the study. Written notes and unrendered source do
not resolve the visual target. A capture of the later working game cannot
retroactively supply this design step. Keep the early target so implementation
can be compared with it. If the drawing is provisional, keep its layout
provisional too.

When illustration or material surfaces carry the direction, explore their
whole-screen relationship before commissioning separate assets. Use the study
to identify the needed backdrop, subjects and control surfaces. Native shapes
and typography can be a complete study for a graphic or text-led game.
Choose the medium from the intended finish. Obtain or generate original art
when material, lighting or subject detail needs it; do not settle for flat
fills because they are easy to code. A coherent graphic style can remain flat.
For a direction built on illustration or tactile materials, begin the study
in an art tool. Use image generation when available and useful, or author the
art. Establish the complete visual target before approximating it with GUI
objects. A colored layout diagram is a wireframe even when it uses the right
genre colors. A named cloth, wood or metal surface needs visible material
treatment; a plain fill does not supply it. A deliberately graphic direction
can instead achieve its finish through shape, type and composition.
Generate a new composition for the brief, not a reskin of a reference image.
Then derive separate runtime assets with quiet live-text regions; do not
flatten the controls, labels or focus behavior into a screenshot.
For a new expressive game with no established art direction, use available
image generation for this whole-screen exploration by default. Give it the
brief, player task, representative content, intended finish, readable text
areas and relevant states. Ask for a new composition and artwork, without
passing a reference screen to be reskinned. Review the resulting image as a
design target; generation alone does not prove its quality or correctness.
Derive the needed background, subject and control-surface assets from the
reviewed direction. For an illustrated or material-led target, generate or
author the reusable runtime artwork, [upload it through Open Cloud](asset-upload.md)
and verify that it loads before
building functional routes. Keep dynamic facts and controls live in Studio.
Use the theme's [chrome contracts](#three-ways-to-use-images) for control artwork.
A brief or existing style that calls for a graphic or text-led interface can
use a native prototype; tool unavailability is a limit to report, not a reason
to call a wireframe finished.
Professional tools and small edits within an established style do not need
this separate exploration.

Inspect the study beside the shipped references at a similar viewing size.
Check whether the choices and action belong to the same visual world as the
subject. Use the [early critique](../../critique-ui/SKILL.md#review-a-design-target)
before translating the study into functional routes. Resolve its visual
`must` fixes here, while the composition is still inexpensive to change.
Then mount one representative screen in Studio with the intended artwork,
live labels and real controls. Static data is sufficient for this first runtime
check. For multi-device work, include the supported narrow and short layouts
as well as a wide view. Phones supporting both orientations need portrait
and landscape checks. Resolve these compact forms before functional routes;
changing device scale does not make a fixed desktop control stack fit.
Compare the actual capture with the target at the same viewing size.
Identify the few visible qualities that make the target work, then check each
in the runtime capture. These can include a subject separated from its
background, a distinctive control silhouette, consistent edges and depth, or
a strong result treatment. Choose these qualities from this design; they are
not a required style. Imported textures do not preserve them automatically.
If a control becomes an ordinary rectangle, the subject blends into its
backdrop, or important state feedback becomes a small text line, inspect what
the translation lost. Fix the relevant asset, crop, surface or type treatment.
Adapt composition for each device while preserving these qualities. Correct
generated details and functional mistakes; the concept is not a pixel-perfect
specification or a reason to retain an unreadable or incorrect design.
Inspect the subject, materials, edges, depth, type and action surfaces. A flat
fill with a line pattern does not reproduce a textile; a character glyph does
not reproduce illustrated subject art. Native drawing is valid when
the visible result preserves the chosen finish. Judge that result, not the
implementation's name or its ease of construction.
If the identity or finish is lost, repair the artwork, layout or control skin
before adding functional routes. More small ornaments on the same generic
structure may not fix its cause. A failed asset import is a blocker to resolve
or report, not a reason to silently replace finished art with placeholders.
Prove the hardest visual relationship in this early runtime screen. When a
live 3D subject shares a scene with an image backdrop, check their perspective,
lighting, ground contact and level of detail together. If the chosen runtime
medium cannot carry the study's finish, revise the direction into a coherent
treatment it can deliver before extending the game.
Keep the target beside the runtime captures through later device and state
repairs. A mockup is a design target, not runtime or input proof.

Spend the next fresh [critique round](../../critique-ui/SKILL.md#review-a-design-target)
on this first Studio screen before functional routes or repeated layouts.
Include the actual choice, action and opened control where used, with their
relevant visual states. This catches a translation that keeps the palette and
subject but replaces the defining control shapes and type with defaults.
Repair known visual `must` fixes and inspect the new capture before proceeding.
Keep this review within the existing three-round budget; it moves the runtime
judgment earlier rather than adding another review process. A quiet professional
tool, small edit or established direction still uses the focused review its
scope needs.

### Build the visual language into the task

Choose the dominant subject and its relationship to the controls before adding
containers. A selection screen might stage objects on a workbench or let a
character stand beside compact choices. A planning screen might use a chart.
These are possibilities, not templates. Default stacks and equal cards are
layout tools; they do not decide the composition.

Carry the direction into the parts the player uses: choice surfaces, labels,
state marks and commitment. A themed banner above neutral cards leaves most
of the task unchanged. One coherent material, edge treatment or graphic motif
across those parts is stronger than unrelated ornaments. Use quiet areas to
make the subject and next action clear; do not decorate every rectangle.

When visual recognition drives a choice, make the subject part of the actual
choice surface at a useful size. For example, an equipment selector can stage
the selectable objects on an inventory mat, with live facts beside each one.
A tiny glyph in a text row plus a separate large illustration can leave the
choice itself generic. Keep the hit target and state in a real Facet control;
use the theme's surface treatment around its live content. Dense comparisons,
settings and text-led choices can use quieter rows when that serves the task.

Plan a response that belongs to the action. Selection can lift or frame the
chosen object; acceptance can visibly place, equip or transform it. A generic
success sentence alone can miss that opportunity. Keep feedback brief, truthful
and legible with reduced motion. Do not invent extra game systems for spectacle.

For feedback within the same task, keep the main action in a stable location.
Reserve space for pending, error and success messages, or place them in a
separate status region. Do not let added or wrapped feedback push the action
away from the pointer, thumb or focus. Size that space from the supported
content and text scale; do not hide overflow to keep the button still. A new
page can recompose deliberately. If success replaces the action with a new
command in the same place, make the new meaning clear and require a fresh
activation; the input that completed one action must not trigger the next.

Prefer useful existing images or models for game objects. Choose custom or
generated art when illustration, texture or shaped surfaces would materially
improve the direction. Native shapes and type can also carry a complete identity.
Text-only can serve word or number comparisons better. If art is unavailable,
carry the direction through type, shape and color while preserving space for
the intended assets. State the missing art; do not silently call neutral
placeholder styling the finished theme.
Do not assume art is unavailable because the brief supplied none. Check the
available asset or image-generation workflow when the direction calls for
illustration. If simple native marks cannot express the intended subject or
material, obtain suitable art or choose a direction the implementation can
deliver. Use a useful crop and scale; a beautiful image below several screens
of controls does not improve the initial task.

## Prove the direction in one task

### Protect labels from artwork

When a label or state mark sits over an image, texture or moving scene, reserve
a quiet area for it. Essential text must remain readable across every crop and
state. Use a solid plate, a sufficiently opaque backing, or a verified quiet
part of the art. A font color that contrasts with the average image color can
still disappear against detail behind individual letters. A shadow or outline
alone is not evidence that the label is readable.

Design this space when commissioning the art. Keep decoration outside the
label's bounds, including padding and room for larger or translated text.
Keep the label live and distinct from the image. Match its backing to the
game's materials; readability does not require a generic rectangular panel.
Plain text on an already quiet surface needs no additional badge.

When repairing contrast or fit, preserve the established visual direction.
Use its materials, edge treatment and type hierarchy for the repair. A plain
utility panel can be correct for a quiet tool, but can weaken an illustrated
game. Compare the repaired view with the previous composition as well as the
reference: keep both readability and the game's character.

Reserve feedback space without stranding its content. Center a short status
group within that space when it is meant to read as a sign or label; align
dense reading content from the top when that serves the task. Inspect the
rendered space above and below the group. Auto-sized text can exceed an
assigned box, so layout declarations alone do not prove visual centering.

Inspect state changes, not only the initial and accepted screens. Trigger
selection and focus separately, then together, and check relevant disabled,
pressed and error states. Read essential labels in the actual capture at the
smallest supported presentation and at console viewing size, without zooming
in to make them legible. Check each materially different image or crop behind
the label. An unreadable state mark is a defect even when the art is attractive
and the geometry report is clean. Preserve a non-color selection cue, and
give it clear space from the focus treatment. A ring must not cross a check,
badge or label, or touch it in a way that looks accidental. Place the mark
inside the content area or in a separate reserved area; allow for the ring's
stroke, halo and rounded corners. Raising the badge above the ring can hide
the crossing without fixing the composition. Inspect the combined state at
the smallest supported size, then move focus away and confirm that selection
remains clear. This does not require an extra badge where the control already
has a clear non-color selection mark.

### Review the complete task

Build one complete task with representative content and the chosen theme before
repeating it. Let subject or outcome lead, decisive facts support it, and
commitment stand apart from navigation. Inspect a capture in the real game or
host at its intended size. Compare it with the direction: which visible choices
express the intended feeling? Would its treatment still suit this game if the
title were hidden, or could it be pasted into any unrelated game unchanged?
Use this as a design check, not a demand for novelty in a professional tool or
an explicitly restrained game.

When references informed the direction, compare the actual capture beside
them at a similar viewing size.
Assess the subject's prominence, the screen's silhouette, the treatment of
interactive surfaces and the clarity of state. Name the largest visible gap
and fix its cause before delivery. This is part of the first build, not a
polish phase that requires the user to reject a bland result first.
Use the [critique-ui loop](../../critique-ui/SKILL.md#the-loop) for the new game
direction. The reviewer needs the original request and any references that
informed the direction, not the author's reasons that the current design should pass. Keep
its visual judgment separate from layout warnings and input evidence.

Judge identity separately from correctness. Working buttons and readable text
do not prove that an expressive game feels inviting. Nor does naming a font,
palette and illustration prove that they form a coherent result. Temporarily
ignore the title and hero image: do the choices and actions still carry the
intended visual language? If the remaining task is a generic app layout, revise
its composition or control treatment. This is a diagnostic for an expressive
brief, not a demand to decorate a quiet tool or an intentionally spare game.
Also judge finish separately from genre recognition. A player can recognize
the genre in a schematic prototype. That does not make it a finished-looking
game. Compare the quality of subject rendering, type, surfaces, edges and
state feedback with the visual target, while keeping the composition original.

Carry the identity into other tasks with their own compositions. Keep dense
settings and repeated rows quieter when needed; they can share typography,
materials and state cues without repeating hero art.

Judge the rendered subject, not the direction statement. A named material or
illustration in working notes does not count until it is visible. Colored cards
and decorative Unicode symbols alone rarely express a character, creature,
vehicle or place. Give an important visual subject a recognizable image, model
or deliberate native drawing at a useful size. Verify every glyph in Studio;
replace missing-glyph boxes instead of describing them as finished artwork.

Prove the same task in phone portrait, phone landscape and console when those
devices are supported. Recompose for both width and available height: a short
landscape screen must not spend its usable area on a title while hiding the
choice and commitment. Check the actual root and scroll bounds, safe insets,
touch controls and controller focus. A width breakpoint or a successful type
check is not evidence of responsive behavior. Capture the initial view and an
accepted action on each form factor; confirm visible state changes after real
input, not merely that an input tool returned success. Fix the composition and
interaction before judging the theme successful.

## Theme contracts

For illustrated controls, use an image viewer to inspect a relevant comparison
in the [worked visual examples](visual-translations/guide.md). Reading their
links alone does not inspect them. They pair original concepts with first and corrected Studio captures, plus
recipes for choices, primary actions and dialogs. The quiet export example
shows where restrained styling fits. Adapt the relationships to the current
task; the example art and dimensions are not defaults.

Collection and Exploration demonstrate Riverbank's identity across supply
decisions, a catalogue and a temporary guide. To run that example, start it with
`Facet.app({ name = "Riverbank", theme = Collection.theme })` and use that app
for all three. This does not require a new app or theme in an existing project.
Inspection's Field Station archive is an alternative game.
Local fonts and native subjects need no uploaded art; replace these cues with
the new game's own.

For a custom visual identity, read a complete task with its theme:

| Reference | Task or theme treatment |
| --- | --- |
| Riverbank | Collection and Exploration: native supply models, botanical type, pale material, distinct cost and commitment; catalogue, detail and temporary field guide use different footprints |
| Neon Circuit | [Theme](../assets/neon-circuit-theme.luau) for a night-time sci-fi game: cyan panel edges, a glow on the current input target, saturated blue controls, magenta selection, Michroma titles and Zekton numerals |
| Pixel Quest | Optional theme builder: image-backed wood plates, pixel borders, green selection and square focus brackets; apply it to Collection with the game's subject renderer |

Use Collection's complete task structure with either visual or text-led records.
Retrieve `Tasks.theme` for a new definition's contract, then only the needed
`Themes.definition`, `Themes.palette`,
`Themes.art` or `Themes.chrome` details. Define one package with
`Facet.themes.define` and inspect its package and report. Put semantic palette,
typography, targets and motion there. Use `textRole` so access adjustments work.
If the custom definition fails, repair the reported errors. Do not hide the
failure behind a neutral-package fallback and continue as if the theme applied.
Verify the intended paint on real controls in selected and focused states.

Choose motion from the meaning of the change. A slide can show entry into a
deeper page. A selection change, confirmation or accepted result within the
same task often needs a stationary update instead. Route history does not
require a slide: `NavigationStack` with `transition = false` keeps navigation
and focus restoration without page motion.

Inspect the transition itself, including its middle, forward and Back,
interruption and reduced motion. Transparent pages over shared scene art can
expose both sets of subjects and labels while they move or crossfade. Keep the
scene stable and use a stationary change when that overlap has no purpose.
For a deliberate page slide, provide a surface that hides the covered content.
Check that labels, focus and primary actions remain clear through the change;
settled captures do not validate motion.

Theme validation checks semantic color pairs, not text over imagery or the world.
Test focus, selected, disabled, pressed and error states against bright and dark
backgrounds, with large/translated text and missing art. Preserve targets, labels
and focus; convey meaning through text or shape as well as color.

## Type scale and recipes

Choose type roles from information priority, density and viewing distance.
`numeral` can emphasize a deciding value; not every number needs that role.
Readable tables may use a restrained scale. `define` reports flat scales and
limited font variation in `report.advice`; inspect the result rather than
treating those heuristics as mandatory ratios or font-family counts.

Use visual cues where they serve the intended identity and task:

- Type, spacing, shape, imagery and material can establish character. A single
  readable family or an undecorated panel can be deliberate.
- Edges, fills or shadows can distinguish surfaces when needed. Choose their
  strength from the actual background and states, not a universal opacity.
- Use action emphasis to express priority. Use `selection` with `onSelection`
  for selected paint and retain a non-color cue for meaning.
- In repeated browse rows, keep idle surfaces quiet. Reserve strong glow or
  action emphasis for selection, the current input target or the action the
  user can take next. Focus and selection can mark different rows. Do not
  put the same accent shadow on every row through a shared panel skin.
  A text-led list or plugin table can use a simple selection mark. A quiet
  interface may need no glow; decorative lighting can still serve a scene
  when it does not compete with the user's decision.
- Category colors can help recognition when stable and accessible. Labels
  remain useful when the category is unfamiliar.
- Keep the world visible when it informs the task; an opaque page or a docked
  plugin panel can be appropriate when the task needs that working space.

Verify fonts in the target runtime with actual labels, numerals, punctuation
and supported languages. A missing family can fall back silently; a family
that loads can still have unsuitable glyphs. Do not treat an example's font
list as a permanent list of platform capabilities.

Keep useful information recipes beside the theme, such as a stat block, price,
section header or row (see [information display](information-display.md)).
Share stable meanings and treatments without forcing every screen to contain
the same decorations or content.

## Three ways to use images

Image-based UI is a supported choice when the product calls for painted,
illustrated, textured or sculpted surfaces. Use the existing image and theme
contracts to retain standard control behavior.

| Need | Use | Responsibility |
| --- | --- | --- |
| Reusable control surfaces and states | Theme `assets` and `chrome` recipes | Stretch/tile geometry, content insets, state paint and readable focus |
| Subject art, portraits or illustrations | Image or AsyncImage | Fit/crop, useful scale, loading/failure state and an accessible label |
| Game-specific framing or decoration | Host image/frame composition | Bounds, clipping, layering and input clearance; it does not replace a control |

When creating or commissioning art, specify its runtime role: a reusable
control plate needs stretchable or tiled regions and safe content insets; an
illustration needs a useful crop; an ornament needs clear bounds. Keep dynamic
labels, prices and actions as live text and controls, not baked into an image
of a screen. Use the available image-generation workflow when it fits the
task. Generated local art still needs a usable runtime asset before it can
ship; use real asset identifiers and verify access in the target experience.

Design hover, pressed, selected, disabled and focus treatments with the art.
A painted button must still act as a Button. Decorative images must not cover
its target or intercept input. Keep a readable fallback for unavailable art.
An image beside a transparent Button does not inherit the Button's state paint.
If an asset workaround changes the skin implementation, prove the needed
states again on the actual painted surface. Keep a persistent selection mark
visible when focus moves to another control; color alone does not identify it.
Complete the [asset upload route](asset-upload.md) for authored images,
including icons. Use the returned Roblox asset IDs; do not replace that route
with EditableImage, embedded pixels or runtime reconstruction.
EditableImage can render dynamic player-created pixels, such as a drawing
canvas and its live brush preview; those are not authored UI assets.
Check the asset contract before choosing the import route: theme asset
`content` is a string ID, not an `ImageContent` value. See `Themes.art`.

Choose the art's runtime role before generating or drawing it. Separate a
subject cutout, background, control plate and state ornament when they need
different crop, stretch or input behavior. A full-screen picture of a menu is
not an implemented interface. For an illustrated choice, compose the art with
one semantic control target; do not add a second image click handler beside a
Button. Read `Button.records`, `Button.label`, `Themes.art` and `Themes.chrome`
for their exact contracts.
Use a nine-slice plate for stretchable borders and a layered recipe for parts
that must stay fixed. Native shapes remain useful for deliberate graphic art.
Choose generated or authored images when the subject or material needs them.

Inspect uploaded art in Studio. Image services can resize the source, so derive
atlas crop and slice coordinates from the runtime dimensions. Check transparent
edges, visible subject size and text-safe areas at the smallest layout. Do not
shrink an intricate full scene into each choice and call it a subject portrait.

Pixel Quest's [theme builder](../../../examples/themes/pixel_quest.luau) is an
optional image-treatment reference. In an exported kit it lives under
`examples/themes/` at the kit root, outside `.agents/skills`. In Studio:

```luau
local docs = game.ServerStorage.FacetDocs
print(docs.examples.themes["pixel_quest.luau"].Value)
```

The builder returns `theme, report = PixelQuest.build(Facet.themes)`; check
`report.ok and theme`, then pass `theme` to the existing app. Pair it with
Collection's complete browse/detail task and supply the game's own subjects.
Read individual `Themes.pixel_quest` contracts only when needed.

Keep the theme's image slices, content insets, selected paint and focus
together. Changing only the palette loses that relationship. Check actual asset
access and missing-art behavior; theme validation cannot prove either. Derive slices and
insets from replacement art, and preserve readable selected labels.

For another catalogue, pass its image/model factory to Collection's
`renderSubject` argument in browse and detail. Keep the name, decisive facts,
price and ownership readable without the image. RadialMenu uses separate `skin`
options; subject images use `Image.reference` or `AsyncImage.reference`.

Ten-foot metrics do not scale every art inset; limited motion can retain paint
transitions. Use their actual contracts. Keep reusable assets small; non-lazy
theme assets preload. Pause hidden live subjects, dispose owned resources and
measure frame timing and retained memory after completed returns.
