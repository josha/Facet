# Latest Astra Medium comparison

This run evaluates Facet source `b7a2c8f1`. Both authors ran concurrently with
Astra Medium, the same brief, a 30-minute limit, and Studio MCP only.
The complete submitted games are frozen and unchanged:
[Facet](facet/game.rbxlx) and [Plain](plain/game.rbxlx).

Astra Medium preferred **Facet in both presentation orders** for one diagnostic
comparison of three desktop states: Hub, Garage, and first-use Tutorial.
The judge favored Facet's clearer Garage layout and tutorial actions. It also
noted Plain's stronger Hub presentation. See the [judgment](evidence/judging/judgment.json),
[configuration and image provenance](evidence/judging/provenance.json), and
[unchanged captures](evidence/judging/captures).

This is a three-state diagnostic result. Shop, Livery, Race, Results and the
other device presets are outside this judgment. The full seven-state,
five-device visual target is not established.

| Author result | Plain | Facet |
| --- | ---: | ---: |
| Wall time | 23.14 min | 27.71 min |
| Total tokens, including cached input | 2,392,800 | 12,499,681 |
| Completion | Completed | Completed |

Facet used 5.224 times the tokens and 1.197 times the wall time. It did not meet
the fixed efficiency targets. Recorded completed-turn latency was also higher.
Cost is unknown; token counters are not billing receipts.

The published coverage is limited. Native discovery and
selected calibration checks are retained. Broad gameplay, five-device
acceptance, and performance overhead remain unverified. The complete benchmark
has not passed. Source reviews identify concrete missing behavior separately
from native observations; no diagnostic subset is treated as a complete-row pass.

## Improvements and evidence

The proposed changes improve modal focus recovery, consumer design guidance,
Studio readiness checks, and concurrent author startup. Facet and Compose main
are integrated. The Verify pin has the same tree as the integrated Verify main.

The evaluated source passed 38 runnable full-tier producers, including 2377
behavioral cases and 561 tool cases. Two producers were deferred and two release
producers were excluded. Separate benchmark, package build, and package status
passed. This is selected evidence and is not a release certification.

- [Source validation and launch setup](evidence/setup/README.md)
- [Author usage](evidence/author/summary.json)
- [Frozen-game custody](evidence/custody/summary.sanitized.json)
- [Native discovery](evidence/discovery/summary.sanitized.json)
- [Untouched console focus](evidence/focus/summary.sanitized.json)
- [Facet source findings](evidence/source/facet-audit.json)
- [Plain source findings](evidence/source/plain-audit.md)
- [Facet coverage](evidence/source/facet-coverage.json) and [Plain coverage](evidence/source/plain-coverage.json)
- [Place privacy review](evidence/privacy/review.json)

Earlier results used a Sol judge and are not relabeled as this Astra judgment.
The previous latest bundle remains in Git history. Raw author and judge session
logs, local account paths, and private process receipts are not published.
