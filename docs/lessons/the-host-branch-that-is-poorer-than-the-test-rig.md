# The shipped host keeps arriving at a capability its test rigs already have

**2026-08-15, third occurrence.** `examples/gallery/client/init.client.luau`'s
`mountDemo` has two branches: one mounts a tutorial example, one mounts a
scenario fixture. Three times now, the FIXTURE branch has been found missing
something that the scenario runner, the overflow sweep, and the tutorial branch
eleven lines below it all had:

| When | What the fixture branch did not do | What it cost |
|---|---|---|
| 2026-08-12 (C2) | pass `built.present` to `pres.present` | `row_actions`' hosted list painted past its pane on a landscape phone |
| 2026-08-13 (ADR-0034) | hand fixtures a `foreign.adopt` seam | `foreign_content` mounted three EMPTY panes in the shipped place |
| 2026-08-15 (O-31) | call `bindNativeScroll` after `present` | five picker demos windowed their first lines forever |

Each was invisible to the whole suite, because every rig that mounts a fixture
headlessly builds its own ctx and does its own post-present wiring. **The test
rigs were more correct than production, and being correct is what hid the bug.**

## The diagnostic, which is cheap and should be run on sight

List every host that mounts the same kind of module and diff what each hands it
and does to it afterwards. Here that is four: `scenarios/runner.luau`,
`tests/overflow_sweep.spec.luau`'s `scenarioCtx`, the picker's fixture branch,
and the picker's tutorial branch. Any seam present in three and absent in one is
a defect in the one — the asymmetry IS the finding, before any behaviour is
measured.

The 2026-08-15 round found the same shape a fourth time while fixing the third:
`async_images` calls `ctx.bindResourceTransport` at BUILD, the runner and the
sweep both provide it, and the picker did not — so the demo could not have been
added to the catalogue without also adding the seam.

## Why a fixture publishing something "for the host" is not enough

`scenarios/virtual_grid.luau` published its control with the comment *"for the
showcase host's native-scroll auto-bind, which probes a returned table's values
for a flat `bindNativeScroll`"* — against a loop that existed for tutorials and
not for fixtures. A comment naming a consumer is a hypothesis about that
consumer. Grep the consumer.

## The rule

> When one host is a test rig and the other is what ships, the rig will be the
> more capable of the two unless something forces them level. Enumerate the
> hosts, diff their seams, and fix the asymmetry — do not wait for the behaviour
> to be noticed on a device, because these defects are all silent: the tree
> mounts, the control renders, and it renders the wrong thing.

The durable fix is one layer down and is booked as **O-31**: a control that
silently renders the wrong rows when a caller forgets one post-`present` call is
a footgun regardless of how many hosts remember. This framework's answer to that
shape is a refusal that is legible at construction and names the alternative
(`REFUSED_FADE`, `src/blueprint_schema.luau`), or a seam that makes the call
unnecessary — `buildFocusGroups(rootNode)` already hands a control its own
mounted path and could hand it the controller with it.
