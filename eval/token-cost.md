# Author token cost

This analysis uses `smoke-run5/runs/shop/{facet,plain}/codex-sol/seed-1`
under `C:/git/facet-wt/facetbench/artifacts/facetbench`. It reads `result.json`
and `transcript.jsonl` in place. It does not copy transcripts into this tree.
The source baseline is `a807cef3`.

## Method

The result files record these totals:

| Metric | Facet | Plain |
| --- | ---: | ---: |
| Input tokens | 74,983 | 40,327 |
| Cache read tokens | 1,519,872 | 330,752 |
| Output tokens | 9,100 | 10,299 |
| Total tokens | 1,603,955 | 381,378 |
| Wall seconds | 484.63 | 249.26 |
| Tool calls | 39 | 14 |
| Tool errors | 9 | 4 |

Facet uses 4.21 times the total tokens and 0.88 times the output tokens.
Cache reads are 94.8% of its total. Long reads and extra turns both matter.
The wall-time ratio in these files is 1.94. This is the Shop pair in this
directory, not an estimate from another task or run.

For visible text, the estimate is `ceil(characters / 4)`. Count only
`item.completed` events, so a started command and its completed command do not
count twice. Count `aggregated_output` once per completed command. The table
below gives the largest cost groups from both arms. Item IDs locate the text
in the transcripts. A zero means that the other arm has no matching read.

For authored code, count commands that contain `Set-Content`, `WriteAllText`
or `apply_patch`. This includes the first source write, edit programs, test
programs and shell wrappers. It is a code-production proxy, not the model's
recorded output-token count. It excludes source printed by read commands.

| Cost group before changes | Facet tokens | Plain tokens |
| --- | ---: | ---: |
| Control contracts and focus docs, Facet item_5 | 11,015 | 0 |
| Definition discovery and analyzer output, Plain item_10 | 0 | 7,793 |
| Factory and layout docs, Facet item_10 | 6,583 | 0 |
| Authored code and edit commands, all writes | 2,567 | 5,599 |
| Reactive type-error expansion, Facet item_16 | 5,437 | 0 |
| Preview rectangles and paths, Facet items_30,38,42 | 4,547 | 0 |
| Setup and more control docs, Facet item_7 | 4,164 | 0 |
| Initial notes, skills and file discovery, item_1 | 2,562 | 1,030 |
| Own source read and discovery, Facet item_39 / Plain item_9 | 503 | 2,299 |
| Mounting and theme docs, Facet item_8 | 1,887 | 0 |

The initial read contains 1,222 tokens of the Facet skill and 577 of the
Compose skill. Facet item_3 adds 159 tokens of the Compose ownership reference.
These are parts of mixed command results, not extra whole-command costs.
Neither arm reads the Facet or vendor implementation source. Neither reads
the full `api.md`; the Facet docs command prints sections from it.

For category totals, assign each command result to one group. Split the three
skill/reference fragments above out of the mixed reads. Round each command or
fragment, then sum. Keep source and tool output that share a command in a
mixed group when there is no clear boundary.

| Category | Facet tokens | Plain tokens |
| --- | ---: | ---: |
| Facet docs/info and skill/reference fragments | 28,751 | 0 |
| Facet or vendor implementation source | 0 | 0 |
| Lint, audit, preview, analyzer and other tool results | 11,104 | 8,604 |
| Mixed project/source reads, notes and discovery | 4,434 | 6,817 |
| Authored code and edit commands, separate from results | 2,567 | 5,599 |

These estimates do not reconcile to billed tokens. The transcripts do not
give per-category billing or the context sent at every model call. Cached
history can be read again at each later call. Do not add a visible-text saving
directly to a recorded total-token saving.

## Failed attempts

Failure costs below overlap the category tables. A mixed failed command can
also return useful source or documentation.

| Cause | Facet | Plain |
| --- | --- | --- |
| Discovery and environment | item_1: missing `rg`; item_6: no Git repository. Their mixed results total 3,971 tokens. | items_1,2: read/discovery commands exit 1; mixed results total 2,892 tokens. item_1 names missing `rg`. |
| Unresolved doc headings | items_7,8 exit 1; 6,051 tokens of successful sections and missing-heading responses. | None. |
| File encoding | items_12,14: invalid UTF-8, then BOM; 171 result tokens and two repair commands. | item_7: BOM; 29 result tokens, followed by a repair. |
| Application types | items_16,22: mixed reactive reads, then a wallet index; 5,472 result tokens. The agent searches and reads State, adds `Facet.Use`, then fixes the index. | item_10: analyzer setup lacks Roblox definitions and reports unknown engine globals. Its 7,793-token result also contains discovery output. |
| Geometry and inspection | item_18: audit exits 1, 461 tokens. Three later preview commands return 4,547 tokens. | No author audit or preview. |

Some setup and error guidance was already added between the measured run and
`a807cef3`. Do not credit that guidance again. This work does not change the
shared harness, either arm's instructions, task files, validation references
or thresholds. It does not change control behavior or the public control API.

## Estimated effect

The docs replay runs only the recorded `docs` and `info` requests against the
new CLI. It does not run an agent, Studio, preview or a live audit.

| Change | Text removed or replaced | Estimated visible-token effect |
| --- | --- | ---: |
| Bound default docs and deduplicate aliases | The seven docs results, items_5,7,8,10,19,20,35 | 24,907 to 5,090; saves 19,817 |
| Short setup overview | item_2 | 1,886 to 411; saves 1,475 |
| Short consumer skill | The use-facet fragment of item_1 | 1,222 to 918; saves 304 |
| Generic HUD and collection recipes | A different first reading path, 774 tokens for both recipes | Could replace more control reads; overlaps the docs saving, so no added saving is claimed |
| Short type expansions and a conditional fix | Apply the new formatting to all six diagnostics in item_16 | 5,437 to about 627; saves about 4,810 |
| Preview rectangles on request | Keep headers, screenshot paths, tap results and problems from items_30,38,42 | 4,547 to about 573; saves about 3,974 |
| Audit fixes once per rule | Remove three repeated fixes in item_18 | Saves about 131 |
| Consumer kit guide selection | Five maintainer evidence guides | Removes 14,585 candidate-read tokens; zero observed reads of these guides in this run |

The direct visible-text estimate is about 30,511 tokens saved. Full contracts
remain available with `docs --full`, full type errors with `lint --verbose`
or the saved details file, and rectangles with `preview --outline` or `--dump`.
Requests for those details reduce the saving. The new reading path can reduce
turns, but this analysis assigns no token or wall-time saving to avoided turns.
Only a new agent run can test the thresholds.

## Kit

Build command: `lute run tools/facet kit --out artifacts/facetbench/arm-facet --force`.
The pinned Roblox definitions came from the existing local cache in the run
workspace. Their SHA-256 matches `tools/typecheck/roblox.lock.json`.

| Complete generated kit | Before | After |
| --- | ---: | ---: |
| Files | 511 | 506 |
| Bytes | 5,423,236 | 5,370,694 |
| Characters | 5,423,164 | 5,370,624 |
| Estimated tokens, characters / 4 | 1,355,791 | 1,342,656 |

The net kit saving is 13,135 estimated tokens. This includes the library,
Roblox definitions and Verify files. These files are needed by the tools;
they are not instructions to read them. New recipes and command code offset
part of the guide removal. The baseline character count subtracts UTF-8
encoding overhead from the baseline byte count, using the unchanged files,
the original versions of changed files and the five omitted guides.

## Checks

The focused Verify cases for documentation budgets, alias deduplication,
lint details and repeated audit fixes pass. The documentation style, links,
call-shape and type-policy checks pass. No Studio or agent evaluation ran.

## Round two: calls first

Round two changes Facet and its consumer instructions. It leaves `eval/tasks`,
`eval/validation`, `eval/thresholds.json`, the plain instructions and the shared
harness unchanged. There are no task hints or control behavior changes. No
Studio session or new agent evaluation ran. The estimate below is a planning
model, not a measured token result.

### Changes and replays

1. Bare `lute run tools/facet docs` is the first read. It returns project files,
   a task recipe index with control call shapes, app setup, typed state,
   collections, text fit and verification. The current repository response is
   about 1,900 estimated tokens. The default stays below 12,000 characters in
   its integration test. Detailed contracts remain available. Both recorded
   missing headings, `Theme packages` and `Sizing and layout`, now suggest
   close headings and exit 0. Unknown searches also give a starting command.
   The seven recorded docs requests were replayed without Studio; all exit 0.
   Their response character counts are 8,119, 2,835, 2,714, 1,530, 672, 1,369
   and 3,462. The first-read path replaces these requests and `info`.
2. The first docs response includes a bounded application file list.
   `project [directory]` uses Facet's file walker and requires neither rg nor
   Git. The skill, Facet arm and kit README name this discovery path. The kit
   runs from a directory without Git metadata. No shared environment changed.
3. Lint, preview, audit and verify remove a UTF-8 BOM from application Luau
   files before Rojo or luau-lsp reads them. They preserve every source byte
   after the BOM. Rojo/luau-lsp read source files directly, so changing only
   Facet's text reader would not fix the engine path. Other encodings still
   need conversion to UTF-8. A BOM-prefixed copy of the recorded final Shop
   source passes `verify --static` in the exported kit; its first byte after
   verification is 45 (`-`), instead of 239 (the BOM prefix).
4. `Facet.Use` was already exported at this baseline. A consumer integration
   case now checks it through a public root require with mixed cell reads and
   a typed dynamic map. The first guide explains that it is a type, not a
   runtime import. Fixed-record diagnostics name the literal-key branch fix;
   an open map must be typed before `Compose.cell`. Starter blocks use public
   types, annotated reactive reads and typed collection, picker and alert
   specs. The kit replaces their one repository require with the public root.
   All nine exported blocks pass `lint examples/blocks --types` with the
   default new solver and with `--solver old`. This replay first exposed 39 starter diagnostics; the
   final replay has zero. No application API was changed. Lint also refuses
   an analyzer failure that returns no usable diagnostics.
5. `verify --tap TEXT...` runs strict types, usage lint, a Rojo build and one
   capture session across all five devices. Verify's public UI audit reads
   the same dumps as the screenshots. Output contains problems and screenshot
   paths. High and medium findings, missed taps and missing live captures
   fail. `--static` runs no Studio and states the evidence limit. `--dump`
   replays saved audit evidence and states that it is saved evidence. The
   integration case checks BOM repair, mixed public types, static build and
   rejection of a weak saved dump. The consumer skill and Facet arm use this
   command; they do not request separate audit and preview calls for the same
   screens. New edits and unresolved problems still need another check.

Roblox's native layout and input APIs and Compose's cells, owners and control
constructors remain in use. No missing engine or Compose mechanism was added.
This work changes author tooling and type examples. The combined command uses
the existing `Look.run` capture host and Verify's public `ui-audit` API. The
Verify consumer skill and public case API were read before adding cases to the
existing `tool-specs` producer. No runner, receipt or verdict was added.

### Expected Shop path

This conservative path budgets three visual repair edits and four verify
calls. It includes screenshot inspection; a successful first layout uses
fewer calls. Batch commands count as one agent tool call, even when the shell
runs more than one program. A screenshot inspection call can show several
images together.

1. Read team notes, ticket and the consumer skill; run bare `docs` in the same call.
2. Read the listed application contract, data, entry point and current component together.
3. Write the interface with typed state and specs.
4. Run `verify --tap Shop`.
5. Inspect the screenshot set.
6. Apply a visual repair.
7. Run `verify --tap Shop`.
8. Inspect affected screenshots.
9. Read the relevant application source if a problem remains.
10. Apply a second repair.
11. Run `verify --tap Shop`.
12. Inspect affected screenshots.
13. Apply a final repair if needed, then run `verify --tap Shop` in that call.
14. Inspect the final affected screenshots.

The target is **14 calls**, equal to plain's 14 and 25 fewer than Facet's 39.
The path removes the two discovery errors, two heading errors, two encoding
errors and two type-error attempts. The measured ninth error was an audit
finding; visual repair findings can still occur. Budget one to three failed
verify calls, below plain's four errors. These are expectations, not replayed
agent outcomes. UTF-8 guidance must prevent the original code-page write;
BOM repair alone does not fix invalid UTF-8. The 14 calls include final image inspection.

### Cache arithmetic

The transcript has no per-call cache billing or hidden context sizes. Use a
calibrated visible-history proxy rather than claim to know those sizes. For
each completed command, estimate command and result tokens with
`ceil(characters / 4)`, accumulate prior completed messages, and call the
history before command i `H_i`. Their sum is 1,367,843. Choose one unknown
initial-context term so that the 39 original proxies sum to recorded cache
reads:

`B = (1,519,872 - 1,367,843) / 39 = 3,898.18`.

Then `C_i = round(B + H_i)`. Rounding leaves a seven-token residual:
the rounded proxies sum to 1,519,865. This attributes the aggregate cache total; it
does not recover actual cache occupancy, reasoning, concurrency or model
message boundaries. The following disjoint groups show the gross cost of
removed old calls. Each sum is `C_i * 1` for every removed call in the group.
Replacement calls and shorter retained history are accounted for separately.

| Cause | Old calls removed | Original item IDs | Gross cache proxy removed |
| --- | ---: | --- | ---: |
| Docs and info, merged into startup | 8 | 2,5,7,8,10,19,20,35 | 230,383 |
| Extra discovery | 1 | 6 | 21,375 |
| Encoding attempts and repairs | 4 | 12,13,14,15 | 149,411 |
| Reactive and record attempts and repairs | 4 | 16,21,22,24 | 169,066 |
| Separate checks, help, process and path discovery | 15 | 18,23,26,29,31,32,33,30,37,40,38,42,43,44,25 | 707,315 |
| Total removed before replacements | 32 | | 1,277,550 |

The retained old calls are 1,3,11,28,36,39,41. Their original context sum is
`1,519,865 - 1,277,550 = 242,315`. Add three separate combined verify calls and four
image inspections: `39 - 32 + 3 + 4 = 14`. The fourth verify is in the final edit call.

For the predicted path, use these context increments after each call:
`3700,1782,1533,650,1000,248,650,1000,539,260,650,1000,824,1000`.
The startup allowance includes the short skill, notes, recipes and discovery.
The application read and write increments use recorded command lengths.
Each verify allows 650 tokens of problems, paths and command text; each image
inspection allows 1,000 tokens. Image encoding is not present in this trace,
so that allowance is uncertain.

The 14 contexts are
`3898,7598,9380,10913,11563,12563,12811,13461,14461,15000,15260,15910,16910,17734`.
Their sum is **177,462 estimated cache-read tokens**. The three separate verify
contexts sum to 38,984 and the four inspection contexts to 58,668. Shorter
history on the seven retained calls saves 162,505:

`242,315 + 38,984 + 58,668 - 162,505 = 177,462`.

For each change, the early-history effect can also be calculated before
replacement text is added. Multiply each removed command/result token count
by the number of the seven retained calls after it:

| Cause | Weighted history removed from retained calls |
| --- | ---: |
| Docs and info | `1912*6 + 11075*5 + 4207*5 + 1923*5 + 6615*5 + 79*4 + 370*4 + 903*3 = 135077` |
| Discovery | `1479*5 = 7395` |
| Encoding | `(129+56+96+75)*4 = 1424` |
| Application types | `(5465+89+63+136)*4 = 23012` |
| Separate checks | `(45+489+55+40)*4 + (429+40+45+215+2737)*3 + 40*2 + (45+967)*1 + (957+40+45)*0 = 14006` |

The gross history effect is `135077+7395+1424+23012+14006 = 180914`.
The complete predicted timeline accounts for replacement startup text, new
check and image output, and changed message allowances. Its net retained
history effect is 162,505. These history terms apply only to retained calls;
they are separate from the contexts of the 32 removed calls.

This last term accounts for early reads remaining in later contexts. For a
read reduction d at position j, its contribution is `d * remaining retained
calls after j`; sum this over removed reads and added starter text. Do not
multiply that text over the 32 removed calls again. As a simple sensitivity
check, 1,000 extra early tokens across 13 later calls adds 13,000 cache tokens.

The visible increments sum to 14,836. The central total-token proxy is
`177,462 + 14,836 = 192,298`, about **192k versus plain's recorded 381,378**.
This is about 50% lower. Report a planning range of **200k–350k**, because
hidden instructions, image tokens, cache eligibility and agent choices can
move the result. The recorded input/output totals cannot be reconstructed
from visible characters. This estimate does not prove a billed-token saving.
An actual paired agent run is still required to measure it.

### Round-two evidence

The final documentation and gallery focused run passes. Documentation style,
links, call shapes and type policy pass. The exported Shop static replay and
all nine exported starter type checks pass. Bench passes in its separate run;
package build and package status succeed. Package status reports the existing
publication drift and pending Studio evidence; nothing was published.

The full gate was attempted. It exposed and led to the correction of the
new guide's `GetService` use against the documentation test stub. The focused
documentation and gallery rerun passes after that correction. The full run
also reports the existing Lute setup permission failure under
`C:/Users/bacon/.lute/typedefs/1.0.1` in `types` and the tool analyzer selftest.
Bench and perf timing are deferred away from the reference host. The requested
fast gate is also run; its final result is recorded below.

The recorded phone-portrait `2-shop.json` dump also passes the combined
command's saved-evidence audit after a static build of the exported Shop.
The complete repository `types` command passes with the old solver: 1,109
targets, zero blocking diagnostics and 186/186 negative probes rejected. It
reports 898 dependency diagnostics separately. The check found two new
assertion argument errors, which were corrected before this passing run.
An intermediate fast run found unsupported repository alias imports in the
starter blocks. Those imports now use the public root through a relative path;
the architecture check passes. These were regressions found and fixed during
this round, not baseline failures.

Final fast run: `gate-1792069218-945937-1`, exit 0. All 13 selected producers
pass. The report says `selected` / `NARROWED run passed`: 24 full/release
producers are not selected and 14 cases are deselected. This is not full
evidence. The run has cache access so Lute can refresh its installed
definitions. An earlier concurrent types/fast invocation failed format when
a temporary type probe disappeared during StyLua discovery. The final fast
run was isolated and has no such failure. The last documentation-only edit
adds the Windows PowerShell UTF-8 save command; documentation style and links
are checked again before the ledger commit.
