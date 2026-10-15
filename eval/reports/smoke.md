# Smoke run report

This report is history. It ran the standalone `shop`, `npc-dialogue` and
`round-hud` tasks and the `smoke.json` suite, which the racing hub and its
`slice.json` suite replaced.

The smoke suite (`eval/smoke.json`) runs `shop`, `npc-dialogue` and
`round-hud` with seed 1 on desktop and phone portrait. Both arms use the same
Codex command line agent (`gpt-6.1-sol`, medium effort) with the user
configuration, apps, plugins, image generation, sub-agents, browser and
computer use turned off. A token is a model token as Codex reports it.

## Run 1: the first Facet kit

| Task | Arm | Cases | Audit mean (4 screens) | Turns | Tool calls | Output tokens | Total tokens | Agent seconds |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| shop | plain | 17/17 | 100.0 | 13 | 12 | 6,881 | 319,857 | 149 |
| shop | facet | 17/17 | 80.5 (100.0 rescored) | 103 | 102 | 29,964 | 10,528,442 | 1,456 |
| npc-dialogue | plain | 12/12 | 99.0 | 11 | 10 | 8,420 | 254,250 | 182 |
| npc-dialogue | facet | 12/12 | 91.0 (100.0 rescored) | 81 | 80 | 28,325 | 11,595,835 | 1,265 |
| round-hud | plain | 12/12 | 99.8 | 16 | 15 | 14,094 | 356,560 | 268 |
| round-hud | facet | stopped | - | - | - | - | - | - |

Both arms passed every hidden case. The Facet arm cost 33 to 46 times the
tokens, 7 to 8 times the turns and 7 to 10 times the time of the plain arm.
The round-hud Facet run was stopped, so that no more runs used the first kit.

"Rescored" is the audit of the same dumps after the audit change below.

## Why the Facet arm lost

From the Facet transcripts:

1. The agent read Facet sources to answer setup questions that `info` and
   `docs` did not answer: the app and runtime setup, Sheet focus, text wrapping
   and sizing, and selection and gamepad focus.
2. The skill asked for a lint, preview and audit loop, and the agent repeated
   it: previews on all five devices, audits of each dump, and its own Studio
   test scripts. It read the sources of the tools, the play host and the probe
   to understand their output.
3. Every audit finding was `focus-hidden`. The audit counted the Facet focus
   ring as an invisible selection image on desktop and phone. The ring is the
   PlayerGui `SelectionImageObject`; it shows after keyboard or gamepad input
   and hides after mouse or touch input. On a device without a gamepad, no
   control is selected, so the rule did not apply to any arm there.

## Fixes before run 2

- The audit checks a hidden selection image only on gamepad devices, like
  `gamepad-unreachable` (Verify). Both arms use the same audit.
- `docs/guide/20-author-questions.md` answers the four setup, focus, text and
  selection questions in short sections, and `info` points at them.
- The skill and the arm instructions ask for `lint --types` while working and
  one `audit` at the end, and tell the agent not to read tool or Facet sources.
  `audit` groups its findings by rule and gives the fix for each rule.
- The arm instructions say that Facet includes Compose, and that a game makes
  one runtime and mounts one tree. `lint` warns about a second app or a second
  mounted root.
- The kit records its source commit in `tools/facet/kit.json`.

## Run 2: Shop on the fixed kit

The kit came from commit `709f8a90` with no local changes
(`tools/facet/kit.json`). Seed 1, desktop and phone portrait, the same agent.

| Task | Arm | Cases | Audit mean (4 screens) | Turns | Tool calls | Output tokens | Total tokens | Agent seconds |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| shop | plain | 17/17 | 97.5 | 13 | 12 | 6,645 | 262,977 | 172 |
| shop | facet | 15/17 | 100.0 | 70 | 69 | 17,258 | 3,062,335 | 831 |

Compared with run 1, the Facet arm used 29% of the tokens, 68% of the turns
and 57% of the time. It still used 11.6 times the tokens, 5.4 times the turns
and 4.8 times the time of the plain arm.

Interface cost (`eval/tools/overhead.luau`, Facet divided by plain, median of
the two devices): mount 1.00, idle frame p50 1.00, active frame p50 1.00,
active frame p95 1.02, no instance left after close on either arm. The Facet
shop mounts its panel only when it opens: 11 GuiObjects at rest against 64,
and 121 against 64 at the peak on desktop (101 on phone portrait).

### The two failed cases

`refuses-insufficient-coins` failed on both devices: the check found no Buy
control near Rainbow Trail. The Facet arm shows the nine items in a
`VirtualList`, which mounts only the rows in its window. Rainbow Trail is the
ninth row, so it had no instance. The play host scrolls a mounted control into
view, but it does not scroll a list to find a row that is not mounted. A player
scrolls the list and buys the item, so the interface is correct. The Facet
guide and the item store block put data rows in a `VirtualList` or a
`VirtualGrid`, even a short list. The cause is in the play host: it cannot
reach a virtualized row in any arm.

### Where the Facet arm spent its time

| Step | Count | Seconds |
| --- | ---: | ---: |
| Edits | 13 | 204 |
| `preview` runs and reads of the dump files | 19 | 276 |
| `lint --types` | 13 | 132 |
| `docs` | 8 | 57 |
| Messages, `info`, `audit`, Rojo builds and other commands | 26 | 162 |

- The agent used `preview` as a flow test on three to five devices (tap Shop,
  Buy, Close) and read the dump JSON with PowerShell. The plain arm made no
  Studio check.
- 7 of 13 lint runs failed. Five failures were the `VirtualList` overloads
  (`KeyedCollectionSpec` and `IdentityCollectionSpec`); `docs --search` found
  no section for either type. One failure was a file that PowerShell saved in
  a non-UTF-8 encoding, which Rojo refused.
- The agent did not read Facet, tool or probe sources.

### Proposed fixes before the next run

- The play host scrolls each visible scrolling list through its canvas to find
  a target that is not mounted, for both arms.
- The `VirtualList` reference shows a typed collection spec, and
  `docs --search` finds the spec types.
- `preview` prints whether each tap found its target. The skill says that
  `preview` shows a screen and is not a flow test, and that the outline is the
  summary of a dump.
- `lint` tells the author to save the file as UTF-8 when Rojo refuses it.

## Run 3: Shop after the four fixes

The kit came from commit `f3fb9b56` with no local changes. The fixes: the play
host scrolls a list to find a row that is not mounted, the reference types
the collection specs and `docs --search` finds the spec types, `preview`
reports each tap and is not a flow test, and `lint` gives hints for type
errors that hide their cause. Re-run of the hidden checks on the run 2
workspaces with the new play host: Facet 17/17 (was 15/17), plain 17/17, and
the weak Shop reference keeps 11/11 on desktop and 3/5 on phone portrait.

| Task | Arm | Cases | Audit mean (4 screens) | Turns | Tool calls | Output tokens | Total tokens | Agent seconds |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| shop | plain | 17/17 | 97.5 | 19 | 18 | 12,792 | 645,490 | 353 |
| shop | facet | 16/17 | 91.0 | 28 | 27 | 7,234 | 1,067,274 | 314 |

Facet divided by plain: 1.65 times the tokens, 1.47 times the turns, 0.89
times the time and 0.57 times the output tokens. The plain arm used more than
in run 2 (19 turns against 13), so one seed does not give a stable ratio.
Interface cost (median of two devices): mount 1.00, idle frame p50 0.99,
active frame p50 and p95 1.00, no instance left after close. Peak GuiObjects
176 against 101 (1.74).

The Facet arm followed the loop: `info`, `docs` (7 runs), `lint --types`
(4 runs, 2 failed: an unknown `width` option on Text, which the new hint named,
and a typed table), one `audit` and no `preview`. It did not read Facet, tool
or probe sources.

### Remaining Facet losses

- `refuses-insufficient-coins` failed on phone portrait. The arm used a
  `VirtualGrid` with `onActivate`. The Rainbow Trail row was mounted, but the
  touch drag of the play host did not bring it into view. The same case passed
  on desktop with the mouse wheel, and touch drags scrolled the plain arm and
  the run 2 Facet `VirtualList`. A touch drag that starts on a grid cell with
  `onActivate` may not scroll the grid. This needs a Studio probe; if a player
  cannot drag the grid from a cell, it is a Facet defect.
- The audit mean is 91.0 against 97.5: clipped text on the desktop shop
  screen, and a small touch target and an overlap on phone portrait. The
  arm's own `audit` checked only the first screen, because the skill does not
  say to give `--tap` for each screen. `info` and the skill should say
  `audit --tap Shop`.
- The author questions guide says to give a wrapped label room with
  `width = "fill"`, but Text has no `width` option. It should say to put the
  label in a stack with `width = "fill"`.
- `docs --search "Facet.Use"` found nothing. The reference does not name the
  `Facet.Use` and `Facet.Readable` types.

## Run 4: stopped

Run 4 was stopped during the plain arm's hidden check. Another Studio MCP
bridge on the host disconnected the play host's bridge at each screenshot, so
no check could finish. The plain agent had finished; the Facet arm did not
start. No numbers are recorded.

## Run 5: Shop with the touch reveal fix and the audit tap path

The kit came from commit `fc71a04a` with no local changes: run 3's kit, plus
the play host fix for touch reveal through an outer scroll viewport, the
`audit --tap` guidance, the reference names `Facet.Use` and `Facet.Readable`,
and the wrapped label advice. Before the run, the hidden checks of the run 3
workspaces ran again on the host's 1024 x 768 placeholder display: the plain
arm stays 17/17 with audits 97 and 98, the Facet arm becomes 17/17 (the touch
reveal fix) with the same audits 88 and 94, and the captures keep their sizes.

| Task | Arm | Cases | Audit mean (4 screens) | Turns | Tool calls | Output tokens | Total tokens | Agent seconds |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| shop | plain | 17/17 | 100.0 | 15 | 14 | 10,299 | 381,378 | 249 |
| shop | facet | 17/17 | 100.0 | 40 | 39 | 9,100 | 1,603,955 | 485 |

Both arms pass every case and audit 100 on every screen. Facet divided by
plain: 4.2 times the tokens, 2.7 times the turns, 1.9 times the time and 0.88
times the output tokens. Interface cost (median of two devices): mount, idle
frame and active frame p50 and p95 1.00, no instance left after close. Peak
GuiObjects 167 against 64 (2.61).

The Facet arm ran `info`, `docs` 7 times, `lint --types` 8 times (4 failed),
`audit --tap Shop` once and `preview` 3 times after its audit fixes. It did not
read Facet, tool or probe sources. Its own audit found the two problems that
run 3's hidden audit found (HUD text that did not fit, a small Close on the
phone), and the arm fixed them.

Where the extra turns went:

- File encoding, 3 lint runs: the arm wrote the file in a non-UTF-8 encoding,
  then with `Set-Content -Encoding utf8`, which in Windows PowerShell 5.1 adds a
  byte order mark that Luau refuses. The lint hint named `-Encoding utf8`,
  which caused the second error.
- Types, 2 lint runs: a `use` body that read a cell of a different type, and
  indexing the contract's `Wallet` type with a currency string.
- `preview` 3 times to look at the phone and tablet screens after the fixes,
  instead of one more `audit --tap Shop`.

## Control coverage

From `lute run eval/tools/coverage.luau` over the Facet arm of runs 1, 2, 3 and 5
(`usage.json` in each run directory).

| Run | Controls and helpers (count) |
| --- | --- |
| run 1: npc-dialogue | `Facet.app` 1, `Facet.format.grouped` 1, `UI.Button` 3, `UI.Composition` 1, `UI.Dialog` 1, `UI.Region` 2, `UI.Screen` 1, `UI.Text` 5, `UI.VStack` 4, `UI.environment` 1, `UI.fill` 1, `UI.focusSection` 1 |
| run 1: shop | `Facet.app` 1, `Facet.format.grouped` 2, `UI.Button` 3, `UI.Composition` 1, `UI.HStack` 2, `UI.Notice` 1, `UI.Region` 1, `UI.Screen` 1, `UI.Sheet` 1, `UI.Text` 8, `UI.VStack` 2, `UI.VirtualList` 1, `UI.environment` 1, `UI.fill` 1 |
| run 2: shop | `Facet.app` 1, `UI.Button` 2, `UI.Composition` 1, `UI.HStack` 1, `UI.Notice` 1, `UI.Region` 1, `UI.Screen` 1, `UI.Sheet` 1, `UI.Text` 6, `UI.VStack` 2, `UI.VirtualList` 1, `UI.fill` 1 |
| run 3: shop | `Facet.app` 1, `Facet.format.grouped` 3, `UI.Button` 2, `UI.Composition` 1, `UI.HStack` 1, `UI.Region` 1, `UI.Screen` 1, `UI.Sheet` 1, `UI.Text` 8, `UI.VStack` 2, `UI.VirtualGrid` 1, `UI.fill` 2 |
| run 5: shop | `Facet.app` 1, `Facet.format.grouped` 3, `UI.Button` 2, `UI.Composition` 1, `UI.HStack` 1, `UI.Region` 1, `UI.Screen` 1, `UI.Sheet` 1, `UI.Text` 9, `UI.VStack` 2, `UI.VirtualGrid` 1, `UI.fill` 2 |

| Control or helper | Runs that use it (of 5) |
| --- | ---: |
| `Facet.app` | 5 |
| `UI.Button` | 5 |
| `UI.Composition` | 5 |
| `UI.Region` | 5 |
| `UI.Screen` | 5 |
| `UI.Text` | 5 |
| `UI.VStack` | 5 |
| `UI.fill` | 5 |
| `Facet.format.grouped` | 4 |
| `UI.HStack` | 4 |
| `UI.Sheet` | 4 |
| `UI.Notice` | 2 |
| `UI.VirtualGrid` | 2 |
| `UI.VirtualList` | 2 |
| `UI.environment` | 2 |
| `UI.Dialog` | 1 |
| `UI.focusSection` | 1 |

UI members that no run uses (73 of 88): `UI.AdaptiveStack`, `UI.Alert`, `UI.AsyncImage`, `UI.Avatar`, `UI.AvatarGroup`, `UI.Badge`, `UI.Callout`, `UI.Card`, `UI.CellEditor`, `UI.Chip`, `UI.CollapsibleView`, `UI.ColorPicker`, `UI.ComboBox`, `UI.DateTimePicker`, `UI.DisclosureGroup`, `UI.Divider`, `UI.ErrorBoundary`, `UI.Flash`, `UI.Grid`, `UI.Image`, `UI.Label`, `UI.LevelPicker`, `UI.Menu`, `UI.NavBar`, `UI.NavigationSplitView`, `UI.NavigationStack`, `UI.NumberInput`, `UI.Outline`, `UI.PageView`, `UI.Pagination`, `UI.Path`, `UI.Picker`, `UI.Popover`, `UI.ProgressView`, `UI.RadialMenu`, `UI.Rating`, `UI.RowActions`, `UI.ScrollView`, `UI.ShortcutHint`, `UI.Skeleton`, `UI.Slider`, `UI.Spacer`, `UI.SplitButton`, `UI.Stage`, `UI.StatusIndicator`, `UI.StepIndicator`, `UI.Stepper`, `UI.TabView`, `UI.Table`, `UI.TextInput`, `UI.Timer`, `UI.Toast`, `UI.Toggle`, `UI.Travel`, `UI.Typewriter`, `UI.ViewThatFits`, `UI.Vote`, `UI.ZStack`, `UI.ZoomView`, `UI.adjustable`, `UI.badged`, `UI.commandScope`, `UI.countUp`, `UI.draggable`, `UI.dropTarget`, `UI.feedback`, `UI.focusRing`, `UI.gestureArbiter`, `UI.responder`, `UI.scrollTo`, `UI.scrollToVisible`, `UI.sequence`, `UI.worldAnchor`
