# ADR-0038: The theme-authoring tag vocabulary is `facet-*`

- Status: accepted
- Date: 2026-08-18
- Stage: release-candidate review (wave R5); controller ruling R11
- Supersedes the tag half of: [`ADR-0018`](ADR-0018-native-stylesheets.md),
  [`ADR-0019`](ADR-0019-theme-packages.md), [`ADR-0020`](ADR-0020-rich-skinning-v2.md)
- Related: [`ADR-0036`](ADR-0036-facet-rename.md) (the product rename),
  [`ADR-0037`](ADR-0037-public-call-shapes.md) (the call-shape half of the same wave)

## The problem

A theme package is authored against CollectionService tags. They are the
selector vocabulary — the thing a package writes in its own source, the thing a
Style Editor shows, the thing the rich-skinning guide teaches:

```
.luau-chrome-panel     .luau-slot-sliderThumb     .luau-skinned-control
.luau-role-destructive .luau-surface-raised       .luau-state-error
```

Every one of them still carried the retired product name under a framework
called Facet. ADR-0036 renamed the library, the modules, the places and the
attributes, and listed what deliberately did not move; the tags were not on that
list, because nothing could see them. `check_brand_drift.py`'s `BRAND` pattern is
`luau[\s._-]?ui`, and `luau-chrome-panel` has no "ui" after "luau" — so the guard
whose entire job is noticing a surviving old name was structurally blind to the
largest surviving old name in the repository (346 occurrences across 56 files).
That is ARCH-15 and ARCH-16 of the release-candidate architecture review, filed
as one Low finding and one Low finding, which together are a High.

## Decision

The tags rename **outright** to `facet-*` / `facet-slot-*`. No alias, no dual
vocabulary, no deprecation window.

**Why outright, when ADR-0037 chose a compatible migration for call shapes on the
same day.** The two are not the same situation, and the difference is who is
holding the old name:

- A `Facet.newTable` call site lives in *someone else's* source. Deprecating it
  costs one ledger row and breaks nobody.
- A `luau-chrome-panel` selector lives in a *theme package* — and the complete
  set of theme packages in existence is the eleven in this repository. There are
  zero external theme authors, because the framework is pre-public. An alias
  would therefore create a dual vocabulary for the benefit of no one, and the
  cost of a dual vocabulary is permanent: two spellings in the guide, two in the
  Style Editor, two in every selector the cascade has to consider, and a new
  author who has to be told which one is "the real one".

This is the only moment the rename is free, and ADR-0036's coherence argument
applies to a public authoring vocabulary exactly as it applied to the call
shapes: a framework whose public vocabulary names a product that no longer
exists is teaching the wrong thing on every page.

## What moved

Every producer and consumer of the tag family, in one change: the vocabulary
itself (`src/tokens/chrome_slots.luau`, `src/tokens/sheet_model.luau`,
`src/tokens/styling.luau`), the client paint/adapter path
(`src/client/screen_paint.luau`, `screen_target.luau`, `screen_chrome.luau`), the
controls and presenters that emit tags, the eleven example theme packages, the
specs that assert selectors, the guide chapters (05-styling, 09-custom-themes,
10-rich-skinning), the theme-authoring playbook, and the ADRs that record the
vocabulary. 395 occurrences, 56 files. Two of them were Lua *patterns* with
escaped hyphens (`"^%.luau%-skinned%-"`), which a plain-text sweep misses and one
spec caught.

## Enforcement

`tools/check_brand_drift.py` gains the tag family to its old-brand profile, so
this class can never again be invisible to the guard that owns it. The pattern is
case-sensitive on purpose — "Luau-side", "Luau-authoritative" and "a Luau-call-count
win" are prose about the *language* and appear in a dozen ADRs — and it excludes
five stems that name the Luau toolchain rather than the retired product
(`luau-lsp`, `luau-analyze`, the Open Cloud `luau-execution-session` scope, and
two lesson filenames about Luau syntax). The `--selftest` plants a `luau-*` tag
and requires it caught, and plants a `luau-analyze` mention and requires it *not*
caught: a guard that cries wolf on the toolchain is a guard people route around.

## Consequences

- A theme package published against 0.9.0 does not install unchanged: its
  selectors name tags that no longer exist. This is a breaking change to the
  authoring vocabulary, and it is why it ships in the 0.10.0 MINOR bump under the
  pre-1.0 rule rather than as a patch. Zero packages outside this repository
  exist to break; the eleven inside it moved in the same commit.
- The `.rbxl` places checked in under `examples/places/` still carry the old tags
  in their serialized instances. They are build outputs, rebuilt by
  `tools/build_places.sh` / `tools/build_reference_places.sh`, and the drift guard
  scans built XML by object *name* rather than by tag — so they are stale rather
  than wrong. Rebuilding them is a Step 14 packaging action.
