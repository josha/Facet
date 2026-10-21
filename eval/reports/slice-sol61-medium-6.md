# Sol 6.1 Medium slice

This fresh pair failed the approved headline rules. Facet passed more hidden
cases, but used 4.02 times the total tokens and 1.89 times the author time.
The blind judge preferred Plain on desktop and Facet on phone portrait.
Both runs failed the required universal tier. This is one task and one seed;
it does not establish the full corpus claim.

| Measurement | Plain | Facet |
| --- | ---: | ---: |
| Required universal cases | 1/13 | 9/13 |
| Optional spec cases | 31/49 | 33/49 |
| Contract / type check | pass / pass | pass / pass |
| Author wall time | 1098.91 s | 2081.47 s |
| Total tokens, including cache reads | 2,633,876 | 10,576,820 |
| Input tokens, excluding cache reads | 135,354 | 201,632 |
| Cache read tokens | 2,460,032 | 10,340,352 |
| Output tokens | 38,490 | 34,836 |
| Tool calls / errors | 97 / 5 | 145 / 15 |

Both authors completed normally. Token and time reduction goals were not met.
Codex supplies no dollar cost. Total tokens include repeated cached input;
they are not a dollar cost estimate.

The separate judge used OpenAI CLI, `gpt-6.1-sol`, medium effort. Both device
comparisons have two valid presentations in opposite orders and consistent
winners. There were no forfeits or skipped comparisons. Facet won 1/2 device
comparisons. On desktop, the judge preferred Plain's hierarchy and visual
finish, while it preferred Facet's task details. On phone, it preferred Facet's
distinct destination screens and task information. These judgments are
separate from Claude results and have no human calibration.

Facet passed all desktop universal cases. Its four phone route failures each
report `text does not overlap`. The saved shop dump contains intersecting HUD
and sheet text bounds. It also records an opaque sheet below a Modal ancestor
with ZIndex 100, while the sheet and HUD text each have ZIndex 1. The hidden
occlusion check compares the elements' own ZIndex values. This is a candidate
stacking interpretation issue; the dump alone does not prove visible overlap.
The failures remain unchanged. No check was rerun and no threshold was changed.
The spec also records unrevealed category purchase targets, counter text
mismatches, boost text mismatches, covered Quests controls and missing offer
time text. A single authored result does not establish a library regression.

Observed Facet/Plain frame ratios range from 0.988 to 1.019 across idle and
active p50/p95 on both devices. Post-return heap ratios are 1.351 on desktop
and 1.096 on phone; GUI memory ratios are 0.898 and 1.052. The requested memory
bound was not met. Frame samples measure cadence, not isolated UI frame cost.
These are whole-client Studio samples. Other Facet and
Word Amigos workloads ran during this pair, so time, frame and memory values
are not a clean isolated comparison. Process times and paths are retained in
the provenance log. The approved report requires at least five paired tasks;
this one-task slice cannot pass that evidence requirement, even when an
individual ratio is below its limit.

The source was `7f1b00f86f58d646151acc24965e2ae2443522ae`, with Verify
`66e86ca14218be7e9ed25822d4d812b0c52453d7`. The generated kit recorded that
source with `changed=false`. Suite `eval/slice.json` ran seed 1, Plain then
Facet, with parallelism 1 and `--fresh`. Both authors used `gpt-6.1-sol` medium.
Each arm had a 3600-second wall budget and the suite declared a $40 budget;
Codex does not report or enforce a dollar limit. Plan digests are:

- Plain: `3a4c8d4393db532e324bf54d89eb72c22999ba56eb92656ab3929e5f78e8f009`
- Facet: `d017881543c67c8a47ee5770bdb5f69e0a5b86bedac38562af9658658c2617d2`

Both places were built with Rojo 7.7.0 from the final saved workspaces:
[Plain](places/racing-hub-slice-sol61-plain.rbxl) and
[Facet](places/racing-hub-slice-sol61-facet.rbxl). They retain the measured
behavior, including failures. The existing Opus places remain separate.

Authoritative raw evidence is retained locally in
`artifacts/facetbench/slice-sol61-medium-6`:
`index.json`, `plan.json`, `judgments.json`, `report.json`, `report.md`,
`headline.md` and `quality.json`. Each arm's
`runs/racing-hub-slice/<arm>/codex-sol/seed-1/` contains `result.json`,
`transcript.jsonl`, `workspace`, `checks` and `captures`.
The existing headline command returned exit 1 (FAIL); the judge returned
exit 0 with two comparisons and no failed judgments. Logs are in
`artifacts/facetbench/sol61-preflight/`: `slice-sol61-run-6.log`,
`slice-sol61-provenance-6.log`, `judge-sol61-6.log`, `report-sol61-6.log`
and `headline-sol61-6.log`. This report records the original pair without a
check replay. Its owned runners and Studios have exited.
