# Sol 6.1 Medium slice

Facet passed the required universal tier, 13/13, against reused Plain's 1/13.
The headline still failed. Facet used 2.74 times the total tokens and 1.53 times
the author time. The separate blind judge preferred Plain on desktop and
Facet on phone portrait. This is one task and one seed, below the required
five paired tasks. It does not establish the full corpus claim.

| Measurement | Reused Plain6 | Fresh Facet7 |
| --- | ---: | ---: |
| Required universal cases | 1/13 | 13/13 |
| Optional spec cases | 30/49 | 37/49 |
| Whole run | fail | pass |
| Contract / type check | pass / pass | pass / pass |
| Author wall time | 1098.91 s | 1677.65 s |
| Total tokens, including cache reads | 2,633,876 | 7,226,639 |
| Input tokens, excluding cache reads | 135,354 | 171,777 |
| Cache read tokens | 2,460,032 | 7,018,112 |
| Output tokens | 38,490 | 36,750 |
| Tool calls / errors | 97 / 5 | 133 / 13 |

Facet7 used 31.7% fewer total tokens and 19.4% less author time than Facet6.
This is a comparison of single authored outputs, not a causal estimate of
the shared changes. Against Plain, the token and time reduction goals remain
unmet. Codex supplies no dollar cost. Total tokens include repeated cached
input and are not a dollar cost estimate. A backend WebSocket interruption
recovered through HTTPS in the same author process; its delay is retained.

Exactly one fresh Facet author ran. Plain6's entire saved run subtree was
copied into the new evidence directory without changing its original author
metrics, timestamps or digest. The public `--checks-only` command then replayed
both saved workspaces with the same corrected checks and regenerated the
two-arm index. No Plain author ran. Facet's second check pass was needed for
the public CLI's complete index and the same-check comparison. Previous
results, checks and captures are under each run's `rechecks/` directory.
The original pair6 evidence remains unchanged. Plain's spec score changed
from 31 to 30 on replay; Facet retained its initial 13/13 and 37/49.

The judge used OpenAI CLI, `gpt-6.1-sol`, medium effort. Both comparisons have
two valid presentations in opposite orders and consistent winners. There
were no forfeits, skipped comparisons or failed judgments. Facet won 1/2
device comparisons. On desktop, Plain had stronger hierarchy, neon styling,
primary actions and world visibility. Facet had clearer supporting text,
currency shortfalls and actual timed boosts. On phone, Facet had distinct
functional destinations, quest rewards, boost status and offer timing. Plain
had stronger styling and visual grouping; Facet's panels were oversized and
sparse. These judgments are separate from Claude results and have no human
calibration.

The remaining optional spec failures on both devices include missing expected
currency-shortfall wording, income wording, boost-duration wording and time
on the Offer button. The Quests entry after a prior panel was covered by
`OverlayArrival.Modal.DismissTarget`. Actual shop purchase and ownership cases
passed. The author also retained a broader transaction sweep failure:
compact-device Buy targets could not be revealed, and desktop Claim matched
a large quest container and was reported covered. Scoped native transactions
passed, so these failures need locator and UI diagnosis. A final five-device
panel-opening sweep passed. Physical controller navigation remains unverified.
A separate fixed-viewport native trace confirmed the user-observed idle
jitter: the wallet readout alternated between one and two lines on income
updates, moving later content by 22 pixels. The outer Sheet and grid size
stayed constant. The text-sizing cause is under investigation. The measured
workspace, place and captures remain unchanged.

Observed Facet/Plain frame ratios range from 0.969 to 1.042 across idle and
active p50/p95 on both devices. Post-return heap ratios are 1.008 on desktop
and 1.387 on phone; GUI memory ratios are 0.999 and 0.997. The phone heap
bound was not met. Mount ratios are 2.738 on desktop and 1.931 on phone.
Memory also failed the return-to-baseline requirement. These are whole-client
Studio samples, not isolated UI CPU or allocation measurements. The preceding
standalone bench failed its environment check with 21.5% yardstick drift.
No competing native/Lute workload appeared in the recorded run-boundary
inventory, but this does not establish a stable isolated timing environment.
This slice cannot prove the requested frame or memory bound across tasks.

Facet source was `9b5b5c7b976136fda23ea437bbceb8da5c2652e1`, with Verify
`3056dada056d819b4400efeba7e437948d7ddb39`. The generated kit recorded that
source with `changed=false`. The shared skill, recipes and occlusion check
were the intervention. Briefs, thresholds, model effort, seed and budgets
were unchanged. Suite `eval/slice.json` used seed 1 and parallelism 1. Both
authors used `gpt-6.1-sol` medium, with a 3600-second wall budget and declared
$40 budget. Codex does not report or enforce a dollar limit. Plan digests are:

- Reused Plain6: `3a4c8d4393db532e324bf54d89eb72c22999ba56eb92656ab3929e5f78e8f009`
- Fresh Facet7: `7d420ba285e329bfe9645b09abefeb35cf9882472fea8ffe1e530168a2d01409`

The playable places retain the measured behavior, including failures:
[Plain](places/racing-hub-slice-sol61-plain.rbxl) and
[Facet](places/racing-hub-slice-sol61-facet.rbxl). Facet was built with Rojo
7.7.0 from its final saved workspace. Plain is the unchanged pair6 build.
The two Opus places remain separate.

Authoritative raw evidence is local at
`artifacts/facetbench/slice-sol61-medium-7`: `index.json`, `plan.json`,
`judgments.json`, `report.json`, `report.md`, `headline.md` and `quality.json`.
Each `runs/racing-hub-slice/<arm>/codex-sol/seed-1/` holds `result.json`,
`transcript.jsonl`, `workspace`, `checks`, `captures` and `rechecks`.
Desktop judgment: `judgments/bc69eb970d2201ffd39451eb01f3dcbbae61aefe3e09bc062600126567777c82.json`.
Phone judgment: `judgments/30a91ea71f390d943511ed8ca02bdf146fa2df263f7eaf8579004b5e35093676.json`.
The broad author sweep is transcript item 133; final source is
`workspace/src/client/Interface/`. The judge returned exit 0; both standard
report and headline returned exit 1 (FAIL). An initial report invocation
omitted required `--thresholds` and exited 2; the corrected invocation used
the unchanged `eval/thresholds.json`. Logs and process provenance are in
`artifacts/facetbench/sol61-preflight/`, with `-7` suffixes. All evaluation
runners and their Studios have exited. Separate post-run diagnosis uses a copy.
