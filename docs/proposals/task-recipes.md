# Task recipes for authors

Status: proposal. Start with `lute run tools/facet docs`. Use a scoped control query when an option is missing.

## The proposal: one recipe for each player task

Most game screens repeat a small set of player tasks. Each recipe holds what
an author needs for one task, and nothing else:

1. The player task and the controls that do it, in one sentence each.
2. One complete starter block from `examples/blocks/` that builds, mounts and
   passes `lint`.
3. The contract facts that the block depends on, about ten lines. For example:
   "Sheet requires a writable `isPresented`", "a Toast action closes the
   toast".
4. The device facts: what changes on a phone, on a TV and with a gamepad.
5. Links to `docs <Control>` for everything else.

Each recipe stays under 6,000 characters (1,500 tokens).

| Recipe | Controls |
| --- | --- |
| Open a panel from the HUD | Composition, Region, Button, Sheet |
| Buy an item and see the result | VirtualGrid, Card, Button, Alert, Toast |
| Read and equip items by slot | VirtualGrid, Card, Sheet, Button |
| Change settings and keep them | Toggle, Slider, Picker, Settings rows |
| Redeem a code | TextInput, Button, Notice, Toast |
| Claim a daily reward | StepIndicator, Button, countdown |
| Talk to an NPC | typewriter text, Button rows |
| Follow a round | countdown, compact numbers, Composition, VirtualList |
| Show a sorted scoreboard | Table |
| Confirm a purchase | Alert |

## Changes to make

- Add `docs/recipes/<task>.md` with the structure above, and list the recipes
  in the `docs` output in place of the full task-to-control table.
- Split `docs/reference/api.md` into one file for each control under
  `docs/reference/controls/`, with the current file as an index. The `docs`
  command and the `links` producer already work by heading, so the split does
  not change a link anchor.
- Measure each recipe with the `docs` command, and fail the `tool-specs`
  producer when a recipe passes 6,000 characters.
- Run the FacetBench slice suite before and after, and compare the input
  tokens of the Facet arm.
