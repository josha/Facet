# FacetBench slice

This record contains one fresh run per arm on one racing-hub slice, seed 1.
Both arms use `gpt-6.1-sol` at medium effort, Codex CLI
`0.162.0-alpha.17.2`, the same harness options and scoped Studio MCP.
It does not establish a general quality, cost or performance claim.
The judge is not run. No visual preference claim is available.

## Comparability

The measurement source commit is
`e2a62b56f9b09a207440e5172f8fe110f766cf44`.
Both kits were rebuilt from that clean commit. Both agents ran fresh with
`eval/slice.json`, seed 1 and `--parallel 2`. No saved agent result was reused.
No check, scenario, budget or reference was changed.

Both arms have a 3,600-second agent wall budget and ephemeral Codex sessions.
Both use `--approve-for-me` and `--ignore-user-config`. Apps, image generation,
multi-agent work, computer use, browser use and plugins are disabled in both.
Each arm receives its own immutable scoped Studio ID and the same six MCP
tools. The overlays differ by design: Facet also receives the rebuilt author kit.

The hidden checks treat the top-bar safe strip as safe content. The audit
includes `text-overlap` and `action-covered`. Only runs with the same input
hashes are comparable to this pair.

All hashes below are lowercase SHA-256. File rows give the file hash.
Tree rows give the hash of a sorted manifest. Each manifest entry contains
the relative path with `/` separators, NUL, the lowercase file hash and LF.
Paths are relative to each tree root; a single-file manifest uses the
basename. Paths use ordinal sorting. Manifests use UTF-8 without a byte order mark.
The manifest files and all single-file manifest hashes are retained in
`artifacts/facetbench/final-setup/comparability.json` and its sibling
`.manifest` files. The input hashes were checked again before agent launch.

| Input | SHA-256 |
| --- | --- |
| Prompt: `eval/tasks/racing-hub/slice/vibe.md` | `f405598e8ac49eb76395b745307e8984723db4df9c2ee5ae2120bbfc2f635cfe` |
| Starter tree | `505596f1580aaa12db0f41431df5cce50012e15493e88ef6a345dc21a161370b` |
| Hidden-check tree | `9d01fd07f8846340e1e2ba407d87c1441e0f0cf41d030435fe02544995944e58` |
| Slice tree | `4fe39ff77a690287ba3e709f340ad10ca3e566567624c13a08a6c55e5b20b11d` |
| `hidden/scenario.luau` | `f206b2565789ad4d30a80393e587a8399178b227b8be775cfa4ffbf3e8c67a25` |
| Plain arm tree | `19dc61f0539efa0119394362e953c47a0bdc115ab6cd6b15cc0cf4687eb48cce` |
| Facet arm tree | `4fc025d54655de6447b40bb9cdbe0ffafac47008f135b8adb4451c1f0a650e94` |
| Shared arm tree | `f804121a7667974bc9d6e83a73d587bf631199a1926918e8bdd9b1a9f5d5600c` |
| Plain `AGENTS.md` | `8e5e5e0e98f46c3dd3c493e48db8a08a260312f1357393bbbae79f086c6804ea` |
| Facet `AGENTS.md` | `bcfa9cf34ec1f1adae2e0b8f10ffeb86c03fe724a87684e287b436eb549e5a94` |
| Shared `TEAM_NOTES.md` | `944d5d4233357f7f801e8498d01fd4febd0ff1a041b2c558f1ebe5ed20b5a8a2` |
| Slice suite | `1f4750673c43402d5528afa33234edd40120d3bf58c4831f066b4df5d9ff23c1` |
| Studio access declaration | `2ce57add3b49e33973c51f9bc23b16dd212577aebe466ac139426f6ce7231b42` |
| Commit text, full identifier followed by LF | `788eca120fa06b127d91286cfd98aff950ee0493687adb2014d722179dd48f45` |
| Commit manifest | `f50433767859095added21a3ec8e8321addc745407767416a7db22c5f3610fa2` |

The pinned Roblox definitions hash is
`9ad75109b8dc9197f6d1726208bfa0b12de47c3a43672a4fa43227f0cec609ee`.
The restored cache matches the committed lock. The Facet kit contains 1,029
files. The shared kit contains the pinned definitions. The corpus check passes.

## Calibration and rendering

Fresh calibration is retained under
`artifacts/facetbench/final-calibration/runs/racing-hub-slice/{strong,weak}/reference/seed-1`.
Each reference has all six universal case records on both devices.

| Reference | Desktop | Phone portrait | Calibration result |
| --- | ---: | ---: | --- |
| Strong | 6/6 | 6/6 | Pass |
| Weak | 0/6 | 0/6 | Required separation |

Calibration passes. Strong-reference mount observations hit the settle limit
on both devices. They supply no valid mount baseline. Behavioral calibration
does not make those timeout values valid runtime measurements.

The two owned preflight Studios each rendered a viewport of about 1703 by
798. They advanced 178 and 180 frames over three seconds. Each scope listed
only itself, rejected the other owned Studio ID for all six tools, rejected
an unknown tool, and rejected calls after scope closure. Closing one Studio
left its sibling responsive. Both closed without surviving processes.
Evidence is `artifacts/facetbench/final-setup/scope-preflight.json`.

## Host conditions

The host uses Windows build 26200, a Ryzen 9 9950X3D with 16 cores and 32
logical processors, and about 61.6 GiB of reported physical memory.
It lists an NVIDIA GeForce RTX 5090 with driver `32.0.15.9186` and AMD Radeon
Graphics with driver `32.0.21001.9024`. The active GPU is not isolated.
Studio uses installation `version-4f087c32742644ab`.

Five unrelated Studio processes were present at setup. Other Studios opened
and closed during the measurement. Other Codex processes were present.
Those workloads were not controlled or stopped. The host may run other Studio
work. Only measurement-owned Studios were used and closed.
Host snapshots are retained under `artifacts/facetbench/final-setup`.
The final census contains five unrelated Studios and no surviving owned Studio.

The required tool directories precede other PATH entries. Lute is
`1.0.1-nightly.20261006`, luau-lsp is `1.69.0`, StyLua is `2.5.2`, and Rojo
is `7.7.0`. No repository gate or benchmark overlaps the measured agent
phases or sequential runtime rescore.

Plain's initial hidden checks overlap Facet's remaining author work.
Runtime ratios therefore use a separate checks-only rescore with
`--parallel 1`. It runs the two saved builds one arm at a time without
another agent invocation. This removes overlap between these two arms;
it does not control other host workloads or isolate UI CPU time.

## Results against the targets

Both agents complete within budget. Both contract checks and strict type
checks pass, with zero type errors. Facet passes the required universal run
gate; Plain fails it. Spec results are diagnostic.

| Device | Arm | Universal | Spec | Universal audit findings |
| --- | --- | ---: | ---: | ---: |
| Desktop | Plain | 0/6 | 13/24 | 0 |
| Desktop | Facet | 6/6 | 18/24 | 0 |
| Phone portrait | Plain | 0/6 | 13/24 | 36 |
| Phone portrait | Facet | 6/6 | 18/24 | 0 |

These case and audit counts come from the initial fresh paired results,
retained in `artifacts/facetbench/final-paired/paired-results/{plain,facet}.json`.
The runtime table uses the sequential rescore. Target decisions compare
observed point values. One pair does not supply independent task samples.
The sequential rescore preserves all per-device universal and spec pass counts.

| Target | Desktop | Phone portrait |
| --- | --- | --- |
| Universal pass rate: Facet clearly above Plain | Met: 100% versus 0% | Met: 100% versus 0% |
| Headline audit findings: Facet <= Plain | Met: 0 <= 0 | Met: 0 <= 36 |
| Total tokens: Facet <= Plain; stretch <= 0.5x | Miss: 4.123x | Same run-level miss: 4.123x |
| Idle frame p50: <= 1.05x | Met: 1.015x | Miss: 4.010x |
| Idle frame p95: <= 1.05x | Met: 0.996x | Miss: 3.803x |
| Mount time: <= 1.10x | Met: 1.002x | Miss: 3.518x |

The report command exits 1 and writes `headline.md` and `quality.json`.
Its headline is FAIL. The policy requires at least five paired tasks and
judge evidence. This measurement has one task and no judge. The token and
wall-time limits also fail. Repeating the same single observation in a
bootstrap does not establish an interval over independent tasks.

The generated headline counts every Verify audit rule except the four
diagnostic rules: `press-feedback-missing`, `type-scale`, `spacing-scale` and
`instance-count`. Its audit metric is 3.600 violations per audited universal
screen for Plain and 0.000 for Facet. This agrees with the table above.

## Failure reasons

Facet has no universal failure. Plain desktop hub and all four panel routes
fail the readable-text-size assertion. Its desktop purchase case cannot find
a visible Buy action near Sport Motor. Plain phone hub fails readable text
size. Shop and Boosts fail text overlap. Quests, Offer and the purchase case
fail because their panel openers do not respond to two taps.

Each table lists every failed spec case. All unlisted spec cases pass.
The common `shop/` or `hud-dock/` prefix is omitted where clear.

| Plain spec case | Desktop failure | Phone portrait failure |
| --- | --- | --- |
| refuses-insufficient-coins | No visible Buy action near Rainbow Trail | Same |
| buys-with-gems | No visible Buy action near Amber Wheels | Same |
| refuses-insufficient-gems | No visible Buy action near Gold Paint | Same |
| closes-shop | No visible Close action | Same |
| shows-counters | Expected short-form 1180 Coins | Same |
| follows-the-income | Expected short-form 1195 Coins | Expected short-form 1200 Coins |
| buys-a-boost | Missing `2x coins for 30 seconds` text | Same |
| claims-quests | No exact Claim action near Earn 1,200 Coins | Quests opener does not respond |
| buys-the-offer | Expected server-matched `Ends in MM:SS` | Offer opener does not respond |
| coherence | Return controls are not in a consistent region | Same |
| hub-reachable | No exact Shop action on return | Same |

| Facet spec case | Desktop failure | Phone portrait failure |
| --- | --- | --- |
| shows-counters | Expected short-form 1180 Coins | Same |
| follows-the-income | Expected short-form 1195 Coins | Same |
| buys-a-boost | Missing `2x coins for 30 seconds` text | Same |
| claims-quests | Quests opener does not respond | Quests is covered by the modal DismissTarget |
| buys-the-offer | Offer button lacks the required time-left text | Same |
| coherence | Return controls are not in a consistent region | Same |

Each universal producer retains 13 results, including the build. Each spec
producer retains 49. Exact copy and sequence failures remain separate from
the universal verdict.

## Audit findings by rule

Each arm has five universal and six spec dumps per device. All dumps are
present. The table lists every nonzero rule and also the new `action-covered`
rule. All other rules have zero findings. Type-scale and spacing-scale are
diagnostic and do not enter the headline total.

| Device | Tier | Rule | Plain | Facet |
| --- | --- | --- | ---: | ---: |
| Desktop | Universal | type-scale | 22 | 0 |
| Desktop | Universal | spacing-scale | 17 | 0 |
| Desktop | Universal | text-overlap | 0 | 0 |
| Desktop | Universal | action-covered | 0 | 0 |
| Desktop | Spec | type-scale | 31 | 0 |
| Desktop | Spec | spacing-scale | 25 | 0 |
| Desktop | Spec | action-covered | 0 | 0 |
| Phone portrait | Universal | text-overlap | 36 | 0 |
| Phone portrait | Universal | type-scale | 16 | 0 |
| Phone portrait | Universal | spacing-scale | 16 | 0 |
| Phone portrait | Universal | action-covered | 0 | 0 |
| Phone portrait | Spec | text-overlap | 54 | 0 |
| Phone portrait | Spec | type-scale | 24 | 0 |
| Phone portrait | Spec | spacing-scale | 24 | 0 |
| Phone portrait | Spec | action-covered | 0 | 0 |

Plain has 107 total universal findings and 158 total spec findings. Facet has
zero in both tiers. The headline universal totals are 36 and zero. Readable
text size is a separate universal assertion. Property audits do not establish
visual preference or physical-device behavior.

## Run-level cost and tools

These costs apply once per arm, not once per device. Input excludes cached
input. Total includes uncached input, cache reads, cache writes and output.
No USD cost is supplied.

| Metric | Plain | Facet |
| --- | ---: | ---: |
| Total tokens | 2,047,740 | 8,443,324 |
| Uncached input tokens | 89,015 | 176,208 |
| Output tokens | 19,781 | 33,900 |
| Cache-read tokens | 1,938,944 | 8,233,216 |
| Cache-write tokens | 0 | 0 |
| Tool calls | 82 | 145 |
| MCP calls, included above | 66 | 56 |
| Tool errors | 6 | 21 |
| Agent wall seconds | 589.443 | 1,594.449 |
| Tool interval union, seconds | 199.755 | 1,105.259 |
| Complete initial run, seconds | 1,281 | 1,894 |
| Documentation invocations | 0 | 50 |
| Documentation node requests | 0 | 41 |
| Documentation searches | 0 | 8 |
| Documentation index requests | 0 | 1 |

All 41 requested documentation node names are distinct. Completed tool items
are counted once, including failed calls. Neither transcript contains a web
search. Tool interval union is not a sum of command durations. Complete run
time includes provisioning and hidden checks. It is separate from agent wall
time. The token ratio is 4.123x and the agent wall-time ratio is 2.705x.

| Tool | Plain | Facet |
| --- | ---: | ---: |
| command_execution | 16 | 89 |
| mcp__studio__list_roblox_studios | 1 | 1 |
| mcp__studio__execute_luau | 30 | 24 |
| mcp__studio__start_stop_play | 8 | 11 |
| mcp__studio__screen_capture | 9 | 3 |
| mcp__studio__get_console_output | 2 | 6 |
| mcp__studio__input | 16 | 11 |
| MCP subtotal | 66 | 56 |
| All tools | 82 | 145 |

Plain makes no `facet verify` call. Facet makes 16: twelve live invocations,
two static invocations and two report reads. The table gives transcript
item IDs and elapsed shell-command intervals. Several commands also edit
source before calling verify; their intervals include those edits. Report
reads do not launch a new Studio.

| Transcript item | Mode | Seconds | Exit code |
| --- | --- | ---: | ---: |
| item_35 | All devices | 147.681 | 1 |
| item_46 | Static | 24.290 | 1 |
| item_56 | Static | 23.773 | 0 |
| item_61 | All devices | 47.800 | 1 |
| item_66 | Report | 4.893 | 0 |
| item_71 | Desktop | 26.002 | 1 |
| item_78 | Desktop | 35.502 | 0 |
| item_85 | All devices | 99.594 | 1 |
| item_100 | Report | 3.001 | 0 |
| item_111 | Console | 35.615 | 1 |
| item_115 | Console, wait 1 | 41.418 | 1 |
| item_118 | Console, wait 1 | 42.877 | 1 |
| item_122 | Console, wait 1 | 41.273 | 0 |
| item_125 | All devices, purchase actions | 145.177 | 1 |
| item_137 | All devices, wait 1 | 117.040 | 1 |
| item_146 | All devices, wait 1 | 112.689 | 0 |

These command intervals sum to 948.626 seconds. They can overlap other tool
work and must not be added to agent wall time. Failed verification is a
recorded diagnostic result, not necessarily a tool crash.

## Token ledgers

The final ledgers are `artifacts/facetbench/final-paired/ledger-plain.json`
and `artifacts/facetbench/final-paired/ledger-facet.json`. They retain the
row IDs, commands, excerpts, categories and recorded adapter usage.

| Ledger measure | Plain | Facet |
| --- | ---: | ---: |
| Numbered tool calls | 82 | 145 |
| Observable text bytes | 339,281 | 400,174 |
| First-insertion estimate, bytes / 4 | 84,820.25 | 100,043.50 |
| Later-call text replay estimate | 3,534,668.25 | 8,099,786.50 |
| Images | 9 | 3 |
| Later-call image exposures | 299 | 142 |

Replay values below are rounded to the nearest whole estimated token.
The JSON retains quarter-token precision.

| Replay estimate by category | Plain | Facet |
| --- | ---: | ---: |
| File reads | 1,097,580 | 2,417,333 |
| Docs and recipes, including batched reads | 0 | 1,843,249 |
| Instructions and skills, including batched reads | 0 | 555,503 |
| Code edits and checks | 968,090 | 840,880 |
| Studio source transfer | 713,756 | 1,035,243 |
| Studio console output | 148,756 | 740,410 |
| Other shell | 403,310 | 195,065 |
| Facet CLI | 0 | 129,552 |
| Studio execute_luau | 83,799 | 129,197 |
| Studio input | 68,400 | 78,649 |
| Agent messages | 16,455 | 67,041 |
| Initial prompt and arm instructions | 30,832 | 57,384 |
| Studio list | 2,094 | 3,763 |
| Studio play/stop | 1,449 | 3,848 |
| Studio capture text | 150 | 71 |
| Error events | 0 | 2,599 |

These estimates assume that text remains in history at later tool calls.
They are not adapter or billing tokens and cannot be added to measured
usage. Images are counted separately. Base64 is not converted to text tokens.
Per-request usage, hidden context, reasoning allocation and truncation
boundaries are absent. Batched categories can include unrelated source reads.
The ledger supports a replay-cost diagnosis, not an exact allocation of the
measured token difference.

## Sequential runtime observations

All values below come from the sequential checks-only rescore. Ratios divide
Facet by Plain. Both devices and arms have valid, non-timeout mount samples.
Both arms return to the hub before their final universal memory sample.

| Device | Metric | Plain | Facet | Facet/Plain |
| --- | --- | ---: | ---: | ---: |
| Desktop | Mount seconds | 2.414334 | 2.418996 | 1.002 |
| Desktop | Idle frame p50 ms | 16.453899 | 16.702199 | 1.015 |
| Desktop | Idle frame p95 ms | 18.098701 | 18.028900 | 0.996 |
| Desktop | Idle frame samples | 120 | 120 | — |
| Desktop | Base UI instances | 59 | 549 | 9.305 |
| Phone portrait | Mount seconds | 3.133831 | 11.026155 | 3.518 |
| Phone portrait | Idle frame p50 ms | 16.628200 | 66.673703 | 4.010 |
| Phone portrait | Idle frame p95 ms | 17.968399 | 68.326101 | 3.803 |
| Phone portrait | Idle frame samples | 120 | 30 | — |
| Phone portrait | Base UI instances | 59 | 529 | 8.966 |

Frame time covers the whole Studio client and probe. It is not isolated UI
CPU time or a physical-phone measurement. The same saved Facet build has
phone p50/p95 of 16.597/18.059 ms in the initial paired pass and
66.674/68.326 ms in the sequential pass. No agent or source edit occurs
between those observations. The initial phone mount is 11.054 seconds;
the sequential value is 11.026 seconds. Mount and frame pacing therefore
show different repeatability in these two observations.

Five unrelated Studio processes are present before the sequential rescore.
The snapshot during Facet's rescore contains six Studios, including its
owned check Studio. Other Studio work may continue on the host. Sequential
execution removes mutual arm overlap, but it does not make the host quiet.
The table retains the requested sequential observations without substituting
the more favorable initial Facet frame sample.

## Missed targets and proposed Facet fixes

### Total tokens: 4.123x, including the 0.5x stretch miss

Facet makes 145 tool calls against Plain's 82. It reads 8,233,216 cache tokens
against 1,938,944. The retained context is larger and is reused over more
calls. Facet achieves the universal result that Plain does not, so the two
stopping points differ in quality. The cost target still fails.
Cache reads account for 6,294,272 of the 6,395,584 extra measured tokens.

The following Facet causes have direct transcript and ledger evidence:

| Cause in Facet | Evidence | Proposed fix |
| --- | --- | --- |
| Live verification starts before blocking static results are known | `tools/facet/commands/verify.luau` starts lint asynchronously, then calls `Look.run` before `lintFailed`. `item_35` runs for 147.681 seconds with type errors, including an unsupported leaf `width` and a nonexistent cell `subscribe`. Ledger call 43 retains 19,012 bytes and an estimated 484,806 later replay tokens for that command and output. | Await blocking static results before starting Studio. Keep live coverage for valid builds. Put the native leaf-sizing pattern and Compose watch/cleanup pattern in the task recipes. Do not add compatibility options or a cell subscription alias. |
| The HUD and shop recipe path requires many separate documentation reads | There are 41 node requests and eight searches. The docs-and-recipes ledger category contains 82,957 bytes and an estimated 1,843,249 replay tokens. File reads add 105,339 bytes and 2,417,333 estimated replay tokens. The docs command returns only query names for multiple paths. | Give the HUD and shop recipes complete, strict examples for sizing, modal roots, state ownership and safe reservations. Expose a bounded task packet and direct links to the exact option nodes. Support one bounded response for a small set of related nodes. |
| Sheet, layout and focus diagnostics cause repeated live repair loops | `item_61` cannot activate Close. `item_71` reports an offscreen dock label. `item_85` and `item_137` report hidden selection images on Sheet controls. Console repairs occur in `item_111` through `item_122`. `item_146` sets `motionLevel="none"` and `sheet.transition=false`; the next full sweep passes. Ledger calls 89, 106, 109, 130 and 139 retain those commands and findings. | Fix the shared Sheet/focus integration and its verification readiness. Keep native `GuiService` selection and `SelectionImageObject` consistent with visible focus through presentation and dismissal. Capture a settled themed transition. Preserve motion and fix the shared cause instead of requiring each app to disable it. |

The focus evidence shows a repair loop and its final configuration. It does
not isolate one faulty animation function. Source investigation should cover
`src/ui/environment.luau`, Sheet presentation and the author verification
capture boundary. The current measurement changes none of them.

The sizing hint already names native `Size`, `AutomaticSize`, parent
`align="stretch"` and `UI.fill()`. The proposed change is to make the correct
pattern available before the first failed build. Compose already supplies
`watch`, cells and cleanup. These fixes need no second scene graph or new
general resource mechanism. Generic shell quoting, source-edit syntax faults
and transport errors remain recorded costs and are not assigned to Facet APIs.

### Phone mount: 3.518x, limit 1.10x

The source-backed Facet cause to investigate is responsive layout convergence
with eagerly mounted live alternatives. `src/ui/composition.luau` initializes
each Region at form 1, constructs every Form frame, observes each form's
layout size, then chooses a fitting form. The saved wallet supplies three
complete live forms. The shared HUD path does not supply a reservation for
the observed native touch controls, so the saved app also adds a reactive
`TouchSafeHUD` wrapper around Composition.

The transcript adds the third form in `item_115` and the touch-safe wrapper
in `item_118`; ledger calls 106 and 109 preserve the edits. The final saved
source retains both. The sequential mount record has 12 live-content entries
across Form1, Form2 and Form3, including hidden alternatives. It spends
8.730 seconds before the stable layout run, against Plain's 0.718 seconds.
Desktop needs zero seconds in that part for both arms. Phone has 529 UI
instances against 59. The initial and sequential Facet phone mounts are both
about 11 seconds.

Fix Facet's shared Composition initialization and HUD recipe so the selected
form and touch reservation are ready before the first visible layout.
Keep measurement stable when live counters change. Mount only the selected
live subtree where native constraints can describe the layout; where measured
alternatives are required, cache their settled geometry instead of keeping
complete live copies active. Use native `UIListLayout`, `UIFlexItem`,
`UISizeConstraint`, `ScreenInsets`, `GuiObject.AbsolutePosition` and
`AbsoluteSize`, and the observed touch buttons. Compose already provides
conditional ownership, watches and cleanup.

The mount exclusions prove that the alternatives are live; they do not name
every geometry reset. This is a source-backed diagnosis and proposed fix,
not a measured allocation of the full arm difference to one function.
Keep the settle rule and budget unchanged when validating the fix.

### Phone idle frames: p50 4.010x and p95 3.803x, limit 1.05x

Both observed frame targets fail. The named Facet cost candidate is the same
eager Composition tree: 529 UI instances and three reactive wallet forms.
The transcript edits and ledger calls 106 and 109 identify that structure;
the raw mount record confirms updates in every form. The proposed Facet fix
is to remove work from unselected forms and profile the selected form's
layout and reactive updates in the native client.

A causal Facet attribution for the fourfold frame jump is not established.
The same build changes from about 60 to about 15 sampled frames per second
between passes, while its mount stays about 11 seconds. Concurrent Studio
work and scheduling remain uncontrolled. The transcript and token ledger
measure author work and retained context, not native CPU or GPU ownership.
They cannot prove that a Facet function caused these frame intervals.
Profile the shared layout candidate, then repeat the unchanged sequential
capture with host conditions recorded. Do not weaken the audit, change a
budget or replace this observed miss with the initial faster sample.

## Repository validation

The corpus check passes. The fast gate exits 0 with all 16 selected
producers passing. It is a narrowed result, not the complete gate.

The full-gate command exits 0 with a NARROWED result. It selects 40 of 41
producers: 38 pass, bench and perf timing are deferred on this non-reference
host, and the release-only `prove-perf-gate` producer is not selected.
This is not complete-gate evidence. Its durable result is
`artifacts/verify/native/gate/gate-1792184722-589970-1/outcome.json`.
No runtime source or performance budget is changed by this report.

The full type check passes 1,226 targets with zero blocking diagnostics and
rejects all 188 public negative probes. Documentation style, links, type
policy, references, standalone builds, lab build, package verification,
package canary, memory, footprint and scene checks pass.

The standalone benchmark exits 0 with PASS and 0.9% yardstick drift.
Its log is `artifacts/facetbench/final-setup/bench.log`.
Package build and package status both exit 0; their logs are in the same
directory. Status retains publication drift, pending package Studio evidence
and a gate receipt that does not attest the reporting tree. These release
conditions are separate from the slice result. No publication operation is run.

## Built places

Each arm's final saved workspace is built as a binary place. Open a place in
Studio and press Play to use the result that the hidden checks scored.

| Arm | Place |
| --- | --- |
| Plain | [`places/racing-hub-slice-plain.rbxl`](places/racing-hub-slice-plain.rbxl) |
| Facet | [`places/racing-hub-slice-facet.rbxl`](places/racing-hub-slice-facet.rbxl) |

Each place is built from the saved workspace's own project file. The project
is the same one that the hidden checks built:

```sh
rojo build default.project.json -o racing-hub-slice-facet.rbxl
```

## Evidence and reproduction

The measured runs are
`artifacts/facetbench/final-paired/runs/racing-hub-slice/{plain,facet}/codex-sol/seed-1`.
The original result copies and generated report remain in `paired-results`.
Checks-only rescoring archives earlier checks and preserves the agent
transcripts, usage and saved workspaces. The directories remain intact.
`artifacts/facetbench/final-setup/final-integrity.json` confirms all 13 input
manifests, both saved prompt hashes, distinct measured Studio IDs and
preserved agent metrics after rescoring.

Use the source commit and the pinned tool directories first on PATH:

```sh
lute run tools/facet gate fast
lute run eval/tools/check.luau
lute run tools/facet kit --out artifacts/facetbench/arm-facet --force
lute run eval/tools/shared-kit.luau
lute run tools/vendor/verify/tools/agent-eval.luau run --suite eval/validation/slice.json --evidence artifacts/facetbench/final-calibration --parallel 1 --fresh
```

Record the comparability manifests before starting either arm. Confirm a
run-owned Studio has a viewport larger than 1 by 1 and advancing frames.
The retained `final-setup/scope-preflight.luau` uses Verify's public Studio
launch and scope APIs, checks both owned scopes and closes them.

Create both shared evidence parents before parallel provisioning:

```sh
mkdir -p artifacts/facetbench/final-paired/runs/racing-hub-slice/plain/codex-sol artifacts/facetbench/final-paired/runs/racing-hub-slice/facet/codex-sol
lute run tools/vendor/verify/tools/agent-eval.luau run --suite eval/slice.json --seed 1 --parallel 2 --fresh --evidence artifacts/facetbench/final-paired
lute run eval/tools/report.luau artifacts/facetbench/final-paired --suite eval/slice.json
lute run tools/facet context-ledger artifacts/facetbench/final-paired/runs/racing-hub-slice/plain/codex-sol/seed-1 --out artifacts/facetbench/final-paired/ledger-plain.json
lute run tools/facet context-ledger artifacts/facetbench/final-paired/runs/racing-hub-slice/facet/codex-sol/seed-1 --out artifacts/facetbench/final-paired/ledger-facet.json
lute run tools/vendor/verify/tools/agent-eval.luau run --suite eval/slice.json --seed 1 --parallel 1 --checks-only --evidence artifacts/facetbench/final-paired
lute run eval/tools/report.luau artifacts/facetbench/final-paired --suite eval/slice.json
lute run tools/facet gate full
lute run tools/facet bench
lute run tools/facet package build
lute run tools/facet package status
```

No judge command is part of this measurement. Keep the saved run directories
and record concurrent host workloads when interpreting runtime ratios.
