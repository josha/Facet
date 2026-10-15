# Slice run on 2026-10-15

The lighting block is fixed. The slice report gives **FAIL**. Both agents
completed, but neither passed a universal case. The strong reference also
failed every universal case. These results do not establish a headline claim.

## Changes

All committed Rojo projects with a DataModel now set `Lighting.Technology`
to `Future`. This includes the eval starter, both racing-hub references,
example places and the Designer smoke place. The live builder inherits the
setting from `examples/gallery.project.json`. The place generator and package
publisher also set it. Extended preparation sets Future in the generated
reference type project. Extended and other turn workspaces inherit the starter
project. The extended contract overlay preserves that inherited project.
The tracked example places were rebuilt.

The existing `facetbench` producer checks place projects in `eval`, `examples`
and `tools`, plus the generated extended starter. It rejects absent, empty,
non-string and Compatibility technology values. A negative check with
Compatibility failed as expected. All 12 committed DataModel projects built
with Rojo and serialized Future as technology 4.

The universal geometry check now accepts Verify's sparse rule map: an absent
rule summary means zero violations. It still checks all the same rules.

Verify is pinned to `970a72d796878f8f6b9c1e33f29e84b3266b8734`.
The old executable read a chunk of MCP requests as one JSON value. The upstream
change at `5c8e51d` fixes request framing and Studio lifecycle use. Verify
`939b58e` fixes object serialization for initialize and ping. Verify `970a72d`
sets Future on native fixtures. Tests cover the serialized handshake and
default fixture lighting.

The measured arms use identical scoped transport code. Plain started on
a local commit with the fix in `939b58e`. The fixture follow-up changes only the
default place builder and its test. It does not change the base-place path used
by the play host.
Facet started on a local commit with the fixes in `939b58e` and `970a72d`.

The native engine APIs used are `Lighting.Technology`, `Camera.ViewportSize`
and `RunService.RenderStepped`. Verify's public Studio launch, session and
cleanup APIs own the disposable processes. A serialized engine property needs
no Compose mechanism. No control or Compose source was changed.

## Studio checks

No previous validation-slice Studio remained at the first process inventory.
Other open Studios were left alone. New checks and runs used owned Studios.
No migration dialog was clicked.

`lute run tools/facet facetbench render PROJECT OUTPUT` builds a place, starts
an owned Studio, checks a viewport larger than 1 by 1 and advancing rendered
frames, records the observation, then closes the Studio.

| Before run | Viewport | Frames in three seconds | Observation under artifacts/facetbench/render |
| --- | --- | ---: | --- |
| strong | 1919 x 1080 | 45 | strong-retry/render.txt |
| weak | 1919 x 1080 | 180 | weak/render.txt |
| plain | 1919 x 1080 | 45 | plain-wire-fix/render.txt |
| facet | 1919 x 1080 | 180 | facet/render.txt |

Both calibration arms and both measured arms ran sequentially with
`--parallel 1`. Universal and spec producers used separate game sessions.

## Calibration

| Reference | Universal desktop | Universal phone portrait | Spec desktop | Spec phone portrait |
| --- | ---: | ---: | ---: | ---: |
| strong | 0/6 | 0/6 | 20/24 | 21/24 |
| weak | 0/6 | 0/6 | 18/24 | 13/24 |

Evidence is in `artifacts/facetbench/validation-slice/runs/racing-hub-slice/`.
The strong reference fails text-overlap and touch-control checks. Later cases
can fail because an earlier failed case leaves a panel open. Calibration does
not separate the references on the universal tier.

## Slice measurements

Both arms used `gpt-6.1-sol`, medium effort, seed 1 and the installed Codex CLI
`0.162.0-alpha.17.2`. All requested pinned tool directories came first on PATH.
The installed Codex executable directory was added after them.

| Measurement | plain | facet |
| --- | ---: | ---: |
| Universal desktop | 0/6 (0%) | 0/6 (0%) |
| Universal phone portrait | 0/6 (0%) | 0/6 (0%) |
| Spec desktop | 13/24 (54.2%) | 16/24 (66.7%) |
| Spec phone portrait | 12/24 (50.0%) | 16/24 (66.7%) |
| Universal audit violations | 4 | 36 |
| Violations per universal screen | 0.4 | 3.6 |
| Total tokens | 3,414,538 | 8,426,575 |
| Input tokens, excluding cache | 107,614 | 172,374 |
| Output tokens | 25,900 | 30,969 |
| Cache-read tokens | 3,281,024 | 8,223,232 |
| Cache-write tokens | 0 | 0 |
| Tool calls | 149 | 143 |
| Agent wall seconds | 947.415 | 1196.277 |
| Strict types | pass | pass |

Facet/plain is 2.468 for tokens, 1.263 for wall time, 0.960 for tool calls
and 9.000 for audit violations. Each arm has ten universal audit screens.
Spec audits do not enter these audit counts.

| Device | Mount | Idle frame p50 | Idle frame p95 | Heap return | GUI return | Base instances |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| desktop | 3.072 | 0.988 | 0.980 | 0.876 | 1.008 | 7.713 |
| phone portrait | 1.224 | 0.995 | 0.996 | 1.059 | 1.007 | 7.400 |

These are observed Facet/plain ratios. Instances are reported, not gated.
Plain heap return is 1.179 on desktop and 1.131 on phone. Facet heap return is
1.033 on desktop and 1.197 on phone. The per-arm heap limit is 1.05.
Repository gates overlapped the agent work and plain's universal producer.
The timing ratios are diagnostic measurements on this host, not a controlled
performance claim. The slice has only one paired task; the report requires
five for its statistical rules.

The report command was:

```sh
lute run eval/tools/report.luau artifacts/facetbench/slice --suite eval/slice.json
```

It exited 1 and wrote `headline.md` and `quality.json` in that directory.
Both cached results were indexed with zero new agent runs before the report.

## Cost projection

A direct extrapolation of each measured arm to 11 tasks and one seed gives:

| Arm | Projected agent tokens |
| --- | ---: |
| plain | 37,559,918 |
| facet | 92,692,325 |
| total | 130,252,243 |

This includes cache reads. It is about 130.3M agent tokens, above the approved
44M. Judge cost is unpriced and would add tokens. No extended run was started.
This extrapolation assumes each task costs as much as the slice. The full hub
and chained follow-ups have not been measured; their actual costs can differ.

## Other limits

- The judge did not run. No Anthropic API key was available, and the Claude
  CLI reported that it was signed out. Automatic approval review also rejected
  the proposed Anthropic transfer because the captures and results had not
  been explicitly authorized for that destination. No data was transferred.
  No judgments or human calibration labels are present.
- The Facet author command `lute run tools/facet verify --tap Shop` could not
  mount its probe. `tools/play/engine/probe.luau` imports
  `eval/validation/racing-hub/driving-probe`, which is absent from the generated
  author kit. The agent used scoped Studio tools but reported controller
  A-button validation as unconfirmed. This tooling defect remains.
- Plain fails universal checks for small text, phone overlap and purchase
  discovery. Facet fails for small text, safe areas and actions covered by an
  open modal. Failed geometry checks can leave panels open for later cases.
- The turn-latency statistic needs review. Plain records 81 of 150 latency
  intervals below one millisecond; Facet records 32 of 144. Do not interpret
  the reported 3007.956 ratio as a comparison of equivalent model requests.
- Earlier setup attempts are retained in `slice-codex-missing`,
  `slice-mcp-input-blocked` and `slice-mcp-shape-blocked` under
  `artifacts/facetbench`. The two completed setup-failure transcripts contain
  143,422 tokens in total. They are separate from the measured arm costs.

## Repository validation

Verify's final headless gate is `gate-1792099229-590809-1`: all 19 headless
producers pass. Its native gate is `gate-1792101430-646956-1`: all 21 producers
pass, including native conformance, scoped MCP and multiplayer.

Facet's final full gate is `gate-1792101905-94775-1`.
It has 35 passing producers and two environment deferrals, bench and perf.
It is a narrowed pass, not a complete gate pass. Types, type policy, format,
reference builds, vendor integrity and all other selected code checks pass.

The final standalone bench exits 2 with `FAIL_ENVIRONMENT`: yardstick drift
is 44.1 percent. An earlier standalone run passed with 1.7 percent drift.
The inconsistent host timings do not establish a benchmark regression.
Package build and package status both exit 0. No package was published.
Package status still records publication drift and pending Studio evidence.

The final Studio process inventory contains no owned eval or native-check
Studio. The other user sessions remain open. Documentation style, links and
`git diff --check` pass.
