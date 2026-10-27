# A theme for this game

Build a recognizable game interface. Inspect the world and available art before
choosing type, materials, silhouettes and subject treatment. River restoration
can use botanical labels and recognizable tools; an archive can use printed
headings and specimens on paper. Uniform rounded cards with changed colors do
not establish that identity. Keep an existing theme when it already fits.

Prefer useful existing images or models for game objects. Text-only can serve
word or number comparisons better; it still needs deliberate typography, graphic
hierarchy and composition. Neither custom art nor an image-heavy theme is mandatory.

Build the theme with one complete task. Let subject or outcome lead, decisive
facts support it, and commitment stand apart from navigation. Carry the same
identity into a dense task and a temporary surface using their own compositions.
More borders, gradients or decorative assets do not repair weak hierarchy.

## Theme contracts

Collection and Exploration share Riverbank's identity across supply decisions,
the dense catalogue and temporary guide. Start the existing app with
`Facet.app({ name = "Riverbank", theme = Collection.theme })` and use that app
for all three. Inspection's Field Station archive is an alternative game.
Local fonts and native subjects need no uploaded art; replace these cues with
the new game's own.

For a custom visual identity, read a complete task with its theme:

| Reference | Task or theme treatment |
| --- | --- |
| Riverbank | Collection and Exploration: native supply models, botanical type, pale material, distinct cost and commitment; catalogue, detail and temporary field guide use different footprints |
| Pixel Quest | Optional theme builder: image-backed wood plates, pixel borders, green selection and square focus brackets; apply it to Collection with the game's subject renderer |

Use Collection's complete task structure with either visual or text-led records.
Retrieve `Tasks.theme` for a new definition's contract, then only the needed
`Themes.definition`, `Themes.palette`,
`Themes.art` or `Themes.chrome` details. Define one package with
`Facet.themes.define` and inspect its package and report. Put semantic palette,
typography, targets and motion there. Use `textRole` so access adjustments work.

Check both navigation directions, interruption and reduced motion; settled
captures do not validate motion.

Theme validation checks semantic color pairs, not text over imagery or the world.
Test focus, selected, disabled, pressed and error states against bright and dark
backgrounds, with large/translated text and missing art. Preserve targets, labels
and focus; convey meaning through text or shape as well as color.

## Three ways to use images

| Need | Use | Responsibility |
| --- | --- | --- |
| Reusable control surfaces and states | Theme `assets` and `chrome` recipes | Stretch/tile geometry, content insets, state paint and readable focus |
| Subject art, portraits or illustrations | Image or AsyncImage | Fit/crop, useful scale, loading/failure state and an accessible label |
| Game-specific framing or decoration | Host image/frame composition | Bounds, clipping, layering and input clearance; it does not replace a control |

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
