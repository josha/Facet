# Astra Medium evaluation

The proposed changes improve modal focus recovery, author guidance, native
Studio readiness, and concurrent evaluation startup. Evaluated source: `b7a2c8f1`.

Both authors used Astra Medium, Studio MCP only, the same brief, and a
30-minute limit. They started less than one second apart. The complete games
are frozen: [Facet](facet/game.rbxlx) and [Plain](plain/game.rbxlx).

## Visual judging

Astra Medium preferred **Facet in both presentation orders** for the desktop
Hub, Garage, and first-use Tutorial. It favored Facet's clearer Garage layout
and tutorial actions, while noting Plain's stronger Hub presentation.

| Device | Available result |
| --- | --- |
| Desktop | Facet preferred in both orders; three-state diagnostic |
| Phone portrait | Pending |
| Phone landscape | Pending |
| Tablet | Pending |
| Console | Pending |

[Selected captures](captures) show the exact images used. The remaining device
judgments and input observations are in progress. This is not yet a completed
five-device result or a full game-acceptance pass.

## Author usage

| Author | Wall time | Tokens, including cached input |
| --- | ---: | ---: |
| Plain | 23.14 min | 2,392,800 |
| Facet | 27.71 min | 12,499,681 |

Facet did not meet the efficiency targets: it used 5.224 times the tokens and
1.197 times the wall time. Cost is unknown; token counters are not billing receipts.

## Validation and evidence

The evaluated source passed 38 runnable full-tier producers, including 2377
behavioral cases and 561 tool cases. Benchmark, package build, and package status
passed. Two producers were deferred and two release producers excluded.
The modal fix has 95 focused checks and three native selection checks.

The [evidence archive](evidence.zip) contains reviewed reports, model and effort
attestation, judgment details, hashes, native observations, and source findings.
It excludes raw author/judge session logs and private process records. The
frozen games are unchanged. Broad game acceptance and performance overhead
remain unverified. Earlier Sol judgments are not relabeled as Astra results.
