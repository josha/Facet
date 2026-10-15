# Task recipes for authors

Status: proposal. The `info` and `docs` commands are the first step.

## The problem

The consumer skill used to tell an author to read every file in `docs/` in
full before the first line of interface code. The sizes below are characters
of Markdown. A token is about four characters.

| What an author read | Characters | Tokens (about) |
| --- | ---: | ---: |
| `docs/reference/api.md` | 315,999 | 79,000 |
| `docs/guide/*.md` | 162,985 | 40,700 |
| All 46 Markdown files in `docs/` | 538,728 | 134,700 |
| `AGENTS.md`, the skill and the Compose skill | 18,406 | 4,600 |
| Total for the first screen | 557,134 | 139,300 |

The reference is one file. A section for one control is often small, but an
author who opens the file pays for all of it.

## The first step: commands that print one section

The skill now tells the author to run `lute run tools/facet info` and then
`lute run tools/facet docs <Control>` for the controls that the task needs.

| What an author reads for the shop task | Characters | Tokens (about) |
| --- | ---: | ---: |
| The arm instructions and the skill | 4,567 | 1,100 |
| `info`: mounting, rules, task-to-control map, blocks | 4,618 | 1,200 |
| `docs Button Sheet VirtualList Toast Text Alert` | 37,490 | 9,400 |
| Total for the first screen | 46,675 | 11,700 |

That is about one twelfth of the earlier cost.

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

With a recipe, the shop task costs about 9,200 characters of fixed reading
(arm, skill, `info`) plus one 6,000 character recipe, about 3,800 tokens in
total, before any targeted `docs` call.

## Changes to make

- Add `docs/recipes/<task>.md` with the structure above, and list the recipes
  in the `info` output in place of the full task-to-control table.
- Split `docs/reference/api.md` into one file for each control under
  `docs/reference/controls/`, with the current file as an index. The `docs`
  command and the `links` producer already work by heading, so the split does
  not change a link anchor.
- Measure each recipe with the `docs` command, and fail the `tool-specs`
  producer when a recipe passes 6,000 characters.
- Run the FacetBench slice suite before and after, and compare the input
  tokens of the Facet arm.
