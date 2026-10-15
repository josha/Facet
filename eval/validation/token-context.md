# Context cost review

This review uses the saved racing-hub-slice seed-1 transcripts. It starts no
agent and reads no hidden check. The plain arm is unchanged.

## Method

Run from the repository root:

```sh
lute run tools/facet context-ledger C:/git/facet-wt/slice/artifacts/facetbench/slice/runs/racing-hub-slice/plain/codex-sol/seed-1 --out artifacts/context-plain.json
lute run tools/facet context-ledger C:/git/facet-wt/slice/artifacts/facetbench/slice/runs/racing-hub-slice/facet/codex-sol/seed-1 --out artifacts/context-facet.json
```

Each JSON row records the item ID, completion time, call number, payload part,
UTF-8 bytes, later tool calls and potential replay cost. It separates commands,
arguments, returned text and images. The source transcript identifies the full
payload. The saved prompt and workspace AGENTS.md enter at call zero. Other
file reads enter when the command returns. Batched outputs stay together;
their category does not imply that every byte is documentation.

The estimate is `UTF-8 bytes / 4 * later calls`. It assumes retained history.
It is not a tokenizer or a reconstruction of billed cache entries. The
transcript gives aggregate usage, but no request-level token counts, system
prompt, tool schemas, private reasoning, image token counts or context eviction
boundaries. Thus exact billed attribution and actual replay counts cannot be
recovered. Later-call counts below are exposure counts, not observed cache hits.
The final completion after the last tool call is excluded from replay estimates.

Image base64 is transport data, not text tokens. Plain has 16 image blocks
(4,023,264 base64 bytes), with 1,171 later-call image exposures. Facet has 24
(7,488,604 bytes), with 1,337 exposures. No image saving is priced below.
`mcp.json` configures the shared Studio transport; it is not itself a transcript
message. Its server schemas and any skill catalog injection are unobserved.

## Returned-context ledger

Numbers in the last two columns are thousands of replay-token equivalents.
Bytes exclude command arguments and image data. Each Studio group includes all
results of that tool, including failures. The JSON has each entry's exact time
and later-call count.

| Entered context | Plain bytes | Facet bytes | Plain replay k | Facet replay k |
| --- | ---: | ---: | ---: | ---: |
| Initial prompt and arm AGENTS.md, call 0 | 1,402 | 2,542 | 52.2 | 90.9 |
| Docs, recipes, kit examples and batched reads, calls 1–40 | 0 | 137,541 | 0 | 4,623.1 |
| Explicit TEAM_NOTES and use-facet skill, call 2 | 0 | 9,475 | 0 | 334.0 |
| File reads, including plain TEAM_NOTES, contracts and Facet source rereads | 60,985 | 126,483 | 2,091.4 | 2,477.7 |
| Code-edit command results and their checks | 918 | 10,902 | 19.2 | 267.5 |
| Standalone Facet lint and verify | 0 | 3,277 | 0 | 100.6 |
| Other shell output, including discovery and native API queries | 26,910 | 58 | 886.7 | 0.1 |
| Studio execute_luau queries | 3,970 | 5,412 | 78.8 | 94.9 |
| Studio full-source transfer results | 104 | 119 | 2.5 | 2.2 |
| Studio console output | 24,447 | 8,149 | 348.4 | 256.7 |
| Studio input, play control and discovery | 1,212 | 1,425 | 18.0 | 24.4 |
| Studio capture text; images counted separately | 0 | 0 | 0 | 0 |

Messages and web-search records add 32.4k plain and 383.6k Facet equivalents.
The table totals about 3.50M plain and 8.27M Facet before those records.

Code and tool arguments are also retained in the ledger, separately from
returned context: shell commands contain 210,093 bytes plain and 31,734 Facet;
Studio arguments contain 222,633 bytes plain and 163,653 Facet. Of these,
full-source Studio transfers are 200,398 bytes in eight plain calls and
143,091 bytes in six Facet calls. A hypothetical replay of all these arguments
adds 7.68M plain and 3.83M Facet equivalents. This exceeds the actual usage;
it must not be added to the returned-text estimate as a billed prediction.
The transcript cannot establish how those arguments were retained or charged.

## Cause

Actual cached input is 8,223,232 Facet versus about 3.28M plain. The Facet run
loads these outputs before its first implementation:

| Call | Material | Bytes | Later calls |
| --- | --- | ---: | ---: |
| 1 | Default docs and project summary | 7,296 | 142 |
| 2 | TEAM_NOTES and use-facet skill | 9,475 | 141 |
| 3 | Application contracts | 11,249 | 140 |
| 5 | Project listing, Compose skill, HUD, Sheet, layout and Button | 19,715 | 138 |
| 6 | HUD, full Sheet, Composition, Button, two blocks and Compose API pointer | 23,724 | 137 |
| 7 | Composition, runtime setup, theme search, environment, Progress and game contracts | 19,504 | 136 |
| 8 | Theme catalog, factory options, environment, media, collection and theme validation | 37,632 | 135 |
| 9 | Full Themes, Mounting and Card | 20,990 | 134 |

This is early reference expansion, not a larger number of tool calls. Full
references and overlapping reads stay exposed through almost all later calls.
The docs batches alone produce about 4.62M replay equivalents, close to the
observed 4.94M cached-input gap. Six later full interface reads add another
2.08M equivalents within the file-read row. Other plain outputs offset some
of that difference. Facet has fewer full-source Studio transfers than plain;
these transfers do not explain the gap. More screenshots add image exposure,
but base64 length cannot explain billed tokens.

## Changes and conditional projection

The following is a fixed-call scenario, not a measured agent result. It keeps
143 tool calls, the same game contract reads and the same visual checks. It
assumes that the agent follows the new skill: scoped reference queries instead
of batched `--full` reads, one matching starter only when needed, and local
source reads instead of whole-file rereads. More follow-up reference queries
would reduce the saving.

| Change | Arithmetic | Estimated cache-read saving |
| --- | --- | ---: |
| Shorter arm instructions | `(2063 - 878) / 4 * 143` | 42,364 |
| Smaller default start response; typed collection example remains queryable | `(5738 - 4214) / 4 * 142` | 54,102 |
| New skill guidance costs context | `-(5041 - 3816) / 4 * 141` | -43,181 |
| Scoped docs at call 5; omit redundant project listing and Compose skill read | `(19715 - 7610) / 4 * 138` | 417,623 |
| Scoped docs at call 6; omit unnecessary starter reads | `(23724 - 5600) / 4 * 137` | 620,747 |
| Scoped docs at call 7; retain both game contract reads | `(19504 - 15452) / 4 * 136` | 137,768 |
| Scoped docs at call 8 | `(37632 - 12498) / 4 * 135` | 848,273 |
| Scoped docs at call 9 | `(20990 - 4676) / 4 * 134` | 546,519 |
| Six local source reads, budget 1,600 bytes each | `2084018.75 - 1600 / 4 * (130+120+89+53+32+22)` | 1,905,619 |
| Terse lint in five unchanged 796-byte verify outputs | `(796 - 348) / 4 * (116+87+70+58+23)` | 39,648 |
| Studio patch guidance and selective captures | Unpriced; preserve visual evidence | 0 credited |
| Diagnostic ledger and bounded project-root discovery | No extra saving beyond the scoped-docs row | 0 credited |

The scoped response sizes were measured with the changed CLI. Call 7 includes
the original server and item contracts. The source-read budget is an assumption.
Explicit `--full` and `--outline` remain available. Long default responses now
show useful excerpts, close code fences, cap heading discovery and direct the
reader to a subsection. `project .` now uses the bounded application summary.
Lint keeps each location and rule, prints repeated advice once, and preserves
source lines and repeated advice with `--verbose`. Verify inherits that output.

Total estimated saving is 4,569,480 cache-read tokens. Projected cache reads are
`8,223,232 - 4,569,480 = 3,653,752`. Holding fresh input (172,374) and output
(30,969) fixed gives **3,857,095 total tokens**, versus 8,426,575 observed Facet
tokens: about **54% less**. This scenario is not a confidence interval or an
eval result. If the agent keeps its old full-reference reads, the large
behavioral savings do not follow from the CLI change alone.

No UI mechanism is added. The guidance uses Studio execute_luau, native Source
updates, GetDescendants, AbsolutePosition and AbsoluteSize for scoped checks.
The existing Compose cell, show, keyed and cleanup APIs cover state and ownership.

## Validation

Results are recorded after the final checks. No agent eval is run.
