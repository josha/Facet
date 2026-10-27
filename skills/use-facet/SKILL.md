---
name: use-facet
description: Design, build and refine Roblox game UI and Studio plugin interfaces with Facet, including touch, pointer and controller use.
---

# Use Facet

**Find the capability first: Facet → Compose → native Roblox → custom code.**
Search Facet controls, options and helpers. Use Compose for composition, state
and lifetime, then native Roblox for an unmet need. Build custom behavior only
for the remaining gap.

## Start with a complete task

Read the brief and existing game. Identify the player's decision, its accepted
outcome and the return path. Preserve required behavior and working routes.
Default to a visually authored game interface. Derive concrete type, material,
silhouette and subject cues from its world and existing art. A color swap on
uniform rounded cards is insufficient. Prefer available images or models that
make game objects recognizable. Choose text-only deliberately when words or
numbers serve the decision better; give it expressive type, hierarchy and composition.

| First task | Read and adapt |
| --- | --- |
| Browse records, products or equipment | [Collection](examples/collection.luau): supply game image/model subjects; use `false` for intentional text-only records. [Riverbank](assets/riverbank-theme.luau) is one example identity. |
| Inspect a selected object | [Inspection](examples/inspection.luau) with its [Field Station theme](assets/field-station-theme.luau): useful subject scale beside a decision |
| Use image-based surfaces and subjects | [Game themes](references/game-themes.md): optional Pixel Quest theme builder with Collection's subject renderer |
| Act during play, then open brief help | [Exploration](examples/exploration.luau), using the same Riverbank app/theme as Collection |
| Another task | [Patterns](references/patterns.md): choose its information relationship and example |

Read [runtime essentials](references/runtime.md) once. Transfer the example's
relationships and ownership, then supply this game's identity, records and
callbacks. Keep a fitting existing theme. Examples are alternatives, not required
skins or decoration quotas. Read only the chosen route; subject-art implementation
can remain outside the layout-reading context.

For phone support, use [compact compositions](references/compact-compositions.md)
before building the first form. Budget the body after navigation and native
controls so useful content and its action appear before a long introduction.

Use [capability routes](references/choose.md) for the exact contract needed;
search unknown names with `lute run tools/facet docs --search TERM`.
Retain answers. Do not read the whole manual or guess filenames.

For richer navigation, forms or spatial UI, use
[advanced compositions](references/advanced-compositions.md) as needed.

Use typed constructors and reactive callbacks. Keep durable selection, drafts
and accepted state outside disposable pages. Give unrelated tasks separate
scroll state. Connect request, pending, rejection, retry and acceptance to real
game behavior. Demonstration callbacks do not implement a production transaction.

## Correct the task before sharing its layout

Capture the first complete task in its real world at wide, portrait and short
sizes before extracting a common page shell or repeating it across destinations.

Reject generic or bland results: could this capture belong to an unrelated game?
Find the largest visible cause in identity, subject recognition, hierarchy or
space use. Correct it before copying the layout, then compare actual before/after
captures. State what visibly changed; a correction to a HUD
does not validate a catalogue. Missing captures leave this step unverified.

Share theme, controls and accepted-state behavior. Give each task its own
footprint: a subject and decision, useful collection space, or a brief floating
confirmation. Keep sequential steps inside one stable navigation surface.

Exercise acceptance, rejection, cancellation and return through real input.
Inspect restored subjects and state. Check affected compact forms, large text,
focus and native-control clearance using runtime essentials. Measure performance
after successful returns. Report tested scope; missing evidence stays unverified.

For a Compose Design module, read [the design editing contract](../compose/references/design.md)
before changing it. Keep its design shapes and run `lute run tools/facet design check <module>`
so the Studio editor stays in sync.
