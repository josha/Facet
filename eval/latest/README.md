# Latest paired run

**Verdict: FAIL.** Both authors finished within the 1,800-second limit. Facet
used 3.21 times Plain's total tokens and 1.38 times its wall time. This fails
the efficiency requirements. Beauty, complete player outcomes, and runtime
overhead are not independently established for this pair.

## Author results

| Measurement | Plain | Facet | Required Facet result |
| --- | ---: | ---: | --- |
| Wall time | 1,115.47 s | 1,544.00 s | At most 669.28 s (60% of Plain) |
| Total tokens, including cache reads | 4,056,603 | 13,014,739 | At most 2,028,301 (50% of Plain) |
| Cache-read tokens | 3,915,776 | 12,783,488 | Included in total |
| Uncached input tokens | 90,200 | 171,083 | Included in total |
| Output tokens | 50,627 | 60,168 | Included in total |
| Completed turn latency | 1,113.99 s | 1,542.60 s | Lower than Plain |
| Tool calls | 111 | 222 | Diagnostic |
| Tool errors | 5 | 6 | Diagnostic |
| Permission denials | 0 | 0 | Diagnostic |

Both arms used Sol 6.1 Medium, one prompt, a blank place, Studio MCP only,
and the same 30-minute deadline. Facet additionally received the library and
consumer skill. Both Studios were maximized. The recorded native viewport
was 1939.33337 by 946. No author was coached or resumed. Library source was
from commit `a86af51aee8ef5e5f50f8d67359048fd72bc8760`.

The author results are unchanged originals. Their `passed: false` fields
include checks attempted before submission sealing. Separate submission
receipts record the subsequent seal. Neither receipt proves the game's
required player outcomes. Paths in the original results identify the local
artifact workspace; the preserved places are linked below.

The recorded [Verify comparison](comparison.verify.json) has 2 passing and
16 failing requirements. Identity and complete usage pass. Efficiency
fails on measured results; completion, behavior, runtime, and visual gates
remain failed because the required independent evidence is absent. The
comparison uses the unchanged original author results, not rewritten passes.

## What this evidence proves

- Both authors completed one turn within the deadline and reported usage.
- Both submissions were saved and sealed. Facet's 930 supplied source and
  documentation entries were unchanged.
- Both authors used screenshots and native input. They reported a completed
  race and return to the hub, purchases, and livery cancellation. These are
  author observations, not independent functional acceptance.
- The efficiency thresholds failed. A better visual judgment cannot change
  this overall verdict.

The required independent player checks cover 29 outcomes on five devices.
They have not been completed for this pair. The new pair has no blind visual
judgment and no matched frame-time or retained-memory measurements. The
less-than-5% overhead requirement remains unproven. The library benchmark
in [validation](validation.md) is a different measurement.

The earlier 600-second submissions, captures, and judge observations have
been removed from this checkpoint. They do not describe these new games.
The `author-preview.png` files are captures from during authoring. They are
not final matched visual-judge inputs.

## Preserved submissions

| Arm | Place | Original result | Seal | Author preview |
| --- | --- | --- | --- | --- |
| Plain | [game](plain/game.rbxl) | [result](plain/author-result.json) | [receipt](plain/submission.verify.json) | [preview](plain/author-preview.png) |
| Facet | [game](facet/game.rbxl) | [result](facet/author-result.json) | [receipt](facet/submission.verify.json) | [preview](facet/author-preview.png) |

SHA-256 of the exact saved place bytes:

- Plain: `29b6cb775b958ac59407a02ccde94ae64e1e4280a22650924e25f253f5e40aae`
- Facet: `3d8ad4ca84534883f8cb337d53074455b4eac2f382ede191e52c5b5b0ddf461a`

The files contain Studio XML despite their `.rbxl` extension. Git preserves
their exact bytes. The [Plain preflight](plain/preflight.json),
[Facet preflight](facet/preflight.json), and
[supplied-content comparison](facet/supplied-content.json) record setup checks.

See [next improvements](next-improvements.md) for the trace analysis and
[validation](validation.md) for repository and library evidence. No further
author run is authorized for this checkpoint.
