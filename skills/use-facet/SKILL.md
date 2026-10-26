---
name: use-facet
description: Design, build and refine Roblox game UI and Studio plugin interfaces with Facet, including touch, pointer and controller use.
---

# Use Facet

**Find the capability first: Facet → Compose → native Roblox → custom code.**
Search Facet controls, options and helpers. Use Compose for composition, state
and lifetime, then native Roblox for an unmet need. Build custom behavior only
for the remaining gap. Give the game its own art and theme around these controls.

## Design the task before its container

Read the brief and existing game. Identify the player's decision, its accepted
outcome and the return path. Preserve required behavior and working routes.
Read [patterns](references/patterns.md) and choose the information relationship:
subject and decision, records and detail, comparable columns, form sections,
outcome and gains, or actions during play. Navigation, surface and local layout
are separate choices. A VStack is not a default page.

Make three decisions before coding:

- What leads attention: the world, a recognizable subject, a comparison or an outcome?
- What supports the next action, and what can wait behind disclosure or another step?
- What bounds and aligns each group when there is surplus room or too little room?

For phone support, read [compact compositions](references/compact-compositions.md)
now. Work out the first useful view inside the remaining task area, after native
controls and navigation. Width alone cannot establish fit. Keep useful content
and its action close; do not spend the available height on repeated headings.

Design a custom theme from the game's world and tone. Read
[game themes](references/game-themes.md) for type, surfaces, color relationships,
icons, motion and image-based skins. Shared identity does not require a shared
layout. Example colors, labels and placement are not a required skin.

## Build one complete task

Read [runtime essentials](references/runtime.md) once and the nearest example
linked in patterns. Transfer its relationships and ownership, then use actual
game content and callbacks. Art fabrication is separate from layout reading.
Use [capability routes](references/choose.md) for the exact contract needed;
search unknown names with `lute run tools/facet docs --search TERM`.
Retain answers. Do not read the whole manual or guess filenames.

For richer navigation, forms, editable collections or spatial UI, select the
task in [advanced compositions](references/advanced-compositions.md). Use these
capabilities when they serve the task, not to fill a control checklist.

Use typed constructors and reactive callbacks. Keep durable selection, drafts
and accepted state outside disposable pages. Give unrelated tasks separate
scroll state. Connect request, pending, rejection, retry and acceptance to real
game behavior. Demonstration callbacks do not implement a production transaction.

## Capture, correct, then extend

Capture the complete task in its real world at wide, portrait and short sizes
before copying its structure to more tasks. Inspect the actual alternate form
too: ring/list, sidebar/bar, split/detail, floating panel/scrolling task.

Read the image as a player: what leads, what can I do, and what belongs together?
Then find the first useful record or fact, the action and its consequence.
If generic chrome leads or useful content is missing, change the allocation or
surface before tuning color. Remove duplicate facts, strengthen useful subject
scale, align related edges, and preserve deliberate outer space on floating panels.

Complete, reject, retry, cancel and return through real input. Check both phone
orientations, large text, open resize and the keyboard where applicable. Choose
layout from room, prompts from active input and readability from access settings.
Preserve native movement, focus, Back, drafts and selection when forms change.
Use virtual collections and event-driven updates where needed; measure runtime
and retained memory after successful returns.

Revise the largest observed problem and repeat the affected checks. Report the
tested scope. Missing captures, input or performance evidence remain unverified.

For a Compose Design module, read [the design editing contract](../compose/references/design.md)
before changing it. Keep its design shapes and run `lute run tools/facet design check <module>`
so the Studio editor stays in sync.
