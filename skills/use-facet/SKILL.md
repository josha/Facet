---
name: use-facet
description: Use when building, changing, debugging, styling, or testing Roblox user interface with the Facet library.
---

# Use Facet

Facet is a Roblox user-interface library in Luau. You describe a screen as plain
data; Facet creates, updates, and destroys the Roblox objects.

Read [`AGENTS.md`](../../AGENTS.md) at the repository root first. It is the full
routing table: which document answers which question, what belongs to the game
versus the framework, and the shortcuts that are defects. This page is only the
short loop.

## The loop

1. **Find the capability before writing one.** The catalog in
   [`docs/guide/README.md`](../../docs/guide/README.md) lists every public
   capability with a link to its reference entry. Most screens need no new code in
   the library.
2. **Copy the smallest working screen** from
   [`docs/guide/03-getting-started.md`](../../docs/guide/03-getting-started.md),
   or run [`examples/consumer/`](../../examples/consumer/), which is that screen as
   a standalone project.
3. **Compose and bind.** Layout from `Facet.UI.*`, controls from
   `Facet.Controls.<Name>(core, spec)`, state in signals and memos from
   `Facet.newCore()`. Pass a signal as a property to make that property reactive.
4. **Style through the theme.** Semantic roles, spacing steps, and type roles —
   never a raw color or a literal pixel size.
   [`docs/guide/05-styling.md`](../../docs/guide/05-styling.md) is the chapter.
5. **Let Facet adapt, focus, and tear down.** Never branch on a device name, never
   build a second input or focus system, never create a Roblox interface object by
   hand. [`docs/guide/07-input.md`](../../docs/guide/07-input.md) covers input and
   its real limits.
6. **Stand the surface up with `client.host.new()`**, which drives both halves of
   the frame. Choosing a screen, a billboard, or a world-fixed surface is section 3
   of `AGENTS.md`.
7. **Look the property up** in
   [`docs/reference/api.md`](../../docs/reference/api.md) rather than guessing. A
   misspelled property raises an error naming what you probably meant.
8. **Prove it.** Write the covering spec first and watch it fail:
   `lune run tests/run_one <spec-name>`. Then `tools/verify.sh affected` while you
   work, and `tools/verify.sh full` before proposing the change. Format with
   `stylua --check src tests tools bench examples`.

## When something is missing

If Facet cannot express what you need, add the capability through the playbook for
that kind of change in [`docs/extending/`](../../docs/extending/), and put the
change where [`docs/MAINTAINERS.md`](../../docs/MAINTAINERS.md) says it belongs. Do
not reach around the public surface, and do not work around a framework promise
inside a game.
