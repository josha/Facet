---
name: use-facet
description: Design, build and refine Roblox game UI and Studio plugin interfaces with Facet, including touch, pointer and controller use.
---

# Use Facet

**Find the capability first: Facet → Compose → native Roblox → custom code.**
Search Facet controls, options and helpers. Use Compose for composition, state
and lifetime, then native Roblox for an unmet need. Build custom behavior only
for the remaining gap.

## Start with the requested task

Identify the user's decision, accepted outcome and return path. Preserve the
brief, existing behavior, art direction and working routes. For a small edit,
reuse established decisions rather than redesigning the application.

Choose layout and visual treatment from the task, content, input and available
room. Images, models, glyphs, charts and text are alternatives; use the form
that helps recognition or comparison. A quiet interface or dense text tool can
be appropriate. Examples show working relationships, not required features,
screen lists, skins, dimensions or typography ratios.

Read [runtime essentials](references/runtime.md) and the relevant route below.
Read a theme asset only when adapting it. Retrieve exact control contracts as
needed; an example does not cover every option or integration.

| Task | Read and adapt |
| --- | --- |
| Plan a game interface or choose its surface | [Game UI design](references/GAME_UI_DESIGN_GUIDE.md), then the relevant section of [game screens](references/game-screens.md) |
| Build a Studio plugin or use an existing runtime | [Runtime details](references/runtime-details.md) and the `Mounting` reference; preserve the host's UI and input conventions |
| Browse records, products or equipment | [Collection](examples/collection.luau) and [patterns](references/patterns.md); supply the application's records and subject treatment |
| Inspect a selected object | [Inspection](examples/inspection.luau); allocate subject space from the details the user needs to see |
| Style controls or use image-based surfaces | [Game themes](references/game-themes.md); example themes are optional |
| Show stats, records, prices or progress | [Information display](references/information-display.md); choose density and emphasis from the decision |
| Act during play, then open brief help | [Exploration](examples/exploration.luau) |
| Another composition | [Patterns](references/patterns.md) or [capability routes](references/choose.md) |

Read [compact compositions](references/compact-compositions.md) when room is
constrained, [advanced compositions](references/advanced-compositions.md) for
richer navigation, forms or spatial UI, and [runtime details](references/runtime-details.md)
for integration contracts. With a shell, search unknown names with
`lute run tools/facet docs --search TERM`; without one, read the
[Controls](../../docs/reference/nodes/Controls.md) index. Do not guess filenames.
Use [filesystem workflow](references/FILESYSTEM_WORKFLOW.md) when its tooling
is available and the project uses saved source files.

Use typed constructors and reactive callbacks. Keep durable selection, drafts
and accepted state outside disposable pages. Give unrelated tasks separate
scroll state. Connect pending, rejection, retry and acceptance to the actual
operation. Demonstration callbacks do not implement a production transaction.

## Author through Studio tools

Keep the project's source and sync path. Edit persistent source; Play-only
changes are not the delivered result. Split modules by responsibility and
lifetime. Size tool calls to the host's limits and the amount of code that can
be checked reliably, rather than a fixed line count or number of screens.

Read the relevant source range before patching. An exact-text patch should
assert that its old text occurs once. Return focused diagnostics rather than
whole source trees. Batch independent reads or probes when that is useful.

In Play, exercise the changed routes and inspect errors. In the Client data
model, `Facet.review.screen().text` provides layout and design findings.
Automated findings are evidence to investigate, not a substitute for viewing
the interface or testing input. Capture representative changed states at the
supported sizes the host can show, then capture again after visual repairs.

## Verify against the brief

Before repeating a new layout, check one complete task in its real context.
Can the user find the relevant facts, understand the action and return with
the expected state? Check visual hierarchy, readability and fit against the
requested style. Keep useful context visible when the task needs it; choose
full-screen, modal, docked or contextual presentation deliberately.

Inspect `report.advice` and review findings against actual content and use.
Fix real defects. Explain deliberate choices when a heuristic disagrees;
do not change an appropriate design only to remove a warning or raise a score.
Use the [critique-ui skill](../critique-ui/SKILL.md) for a deeper visual review
when requested or when the visual change warrants one.

Exercise affected acceptance, rejection, cancellation and return routes through
real input. Check relevant compact forms, large text, focus and native-control
clearance. For lifetime or performance changes, measure after successful
returns. Scale verification to the change and report what was actually tested.
Missing captures or input evidence leave those claims unverified.

For a Compose Design module, read [the design editing contract](../compose/references/design.md)
before changing it. Keep its design shapes and run `lute run tools/facet design check <module>`
so the Studio editor stays in sync.
