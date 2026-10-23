# Latest evaluation

**Facet wins the four sampled desktop visual comparisons. The full eval does not pass.**
Both authors used **Astra Medium (`gpt-6-astra`)** with the same racing-game brief
and 1,800-second limit. The runs overlapped on this machine. This directory
replaces the previous Sol attempt and saved Plain reference with this fresh pair.
Keep only the current evidence here. Design guidance remains separate.

## Readout

| Measure | Plain | Facet | Pass requirement and result |
| --- | --- | --- | --- |
| Observed author duration | 1,796.412 seconds to last event; no final turn event | 1,479.315 seconds to completed turn | Facet is about 82.3% of Plain, not the required ≤60%. Target missed on observed timing; final runner receipts are missing. |
| Total tokens, including cached input | 3,657,332 | 6,126,395 | Facet uses about 167.5% of Plain, not the required ≤50%. Target missed on observed counters. |
| Visual quality | No overall preference in the sampled pairs | Preferred in hub, garage, shop and livery, in both orders | Strong desktop subset result. Required states and five device configurations remain incomplete. |
| Player outcomes | Desktop navigation and purchase Cancel/Confirm checked | Desktop navigation and purchase Cancel/Confirm checked | Full acceptance matrix unverified. |
| Runtime overhead | No valid paired measurements | No valid paired measurements | <5% frame-time and retained-memory overhead unverified. |

Do not treat four screens from one pair of games as four independent author runs.
The 4/4 desktop result does not establish the required whole-game preference rate.
Neither repository benchmarks nor author claims prove authored-game performance.
Median turn latency is not established by these single-turn attempts.

## Visual judgment

The judge is **Sol 6.1 (`gpt-6.1-sol`), medium reasoning**. Verify's public
`Eval.judge.compare` API presents anonymous image pairs in both orders, using
the same six-criterion rubric as the previous review. The authors used Astra;
the judge did not. Each capture is 1914 × 737. Native mouse input opened the
initial task views. Onboarding remains where the game shows it. No game code
was repaired, and no screenshot was edited.

| State | Result | Evidence |
| --- | --- | --- |
| Hub | Facet, both orders | [Judgment](evidence/judgment-hub.json), [Facet](evidence/captures/facet-hub.jpg), [Plain](evidence/captures/plain-hub.jpg) |
| Garage | Facet, both orders | [Judgment](evidence/judgment-garage.json), [Facet](evidence/captures/facet-garage.jpg), [Plain](evidence/captures/plain-garage.jpg) |
| Shop | Facet, both orders | [Judgment](evidence/judgment-shop.json), [Facet](evidence/captures/facet-shop.jpg), [Plain](evidence/captures/plain-shop.jpg) |
| Livery | Facet, both orders | [Judgment](evidence/judgment-livery.json), [Facet](evidence/captures/facet-livery.jpg), [Plain](evidence/captures/plain-livery.jpg) |

Facet gives onboarding a direct Garage action and keeps the central game view
clear. Its garage shows the complete kart, readable statistics and selection
actions together. Its shop groups details, price and purchase action within each
item. Its livery shows both body and accent palettes in the initial view.

There are still concrete design improvements to make. The garage collection
requires scrolling, and its filters occupy much of the available height.
The shop uses large stacked cards with limited visible inventory. Facet's selected
livery color is less explicit than Plain's checkmark and named selection. Plain
also has stronger typography and visual identity in one hub judgment, and gives
purchase buttons stronger emphasis. These are useful directions for the next
iteration; they do not erase Facet's observed visual advantage.

## Independent player checks

[Desktop observations](evidence/player-observations.json) record a diagnostic
subset, not complete acceptance rows:

- Plain's frozen binary was copied, reopened and started. Facet's saved persistent
  Edit model was started. Both mounted their interfaces.
- Native mouse input opened Garage, Livery and Shop in each game. Facet also
  returned through Close and its Menu. The captures show the resulting states.
- Facet's Flux motor cost 350 credits. Cancel retained 1,800; Confirm left 1,450
  and displayed `Purchased Flux motor`.
- Plain's Flux motor cost 700 credits. Cancel retained 2,400; Confirm left 1,700
  and displayed `Owned`.
- Facet exposed no `FacetError` attributes in the inspected Shop state.
- Both frozen submissions passed integrity checks before and after evaluation.

Both authors report completed races and economy checks. Their
[Plain](evidence/plain-author-report.json) and
[Facet](evidence/facet-author-report.json) reports are retained as self-reports,
not independent proof. Facet explicitly reports session-only progress and
incomplete controller/device verification, localization and radial quick chat.

The authors' compact checks resized UI roots: Plain used 390 × 650 and 844 × 390;
Facet used 390 × 650. These are layout probes, not full device emulation or
physical touch/controller evidence. This new pair does not inherit the previous
Sol submission's portrait and console reports.

Still required: independent full race and return loop, every acceptance row and
rejection path, all five device configurations, physical-input coverage, race
and results visual comparisons, and matched runtime measurements. See the fixed
[acceptance requirements](../acceptance.md). No whole-game or all-device pass is claimed.

## Run identity and limitations

- Source revision: `b956c8c9` on main base `be08a98d`. The Facet kit was regenerated
  from the current library, skill, design guide and recipes before launch.
- Plain started `2026-10-23T15:53:45.837Z`; Facet started
  `2026-10-23T15:53:47.361Z`. Each used a separate runner and scoped Studio place.
- A brief initial Plain startup was stopped when the runner serialized the arms.
  It had made no game implementation. Both fresh author sessions then started
  concurrently. The abandoned startup is excluded from the paired counters.
- Facet emitted a final answer and `turn.completed` at 1,479.315 seconds. Plain's
  final recorded edit was at 1,796.412 seconds, with no final turn event.
  Neither runner emitted a standard final result/index. Do not infer a completed
  benchmark record or an exact termination cause from missing output.
- [Usage](evidence/author-usage.json) contains the last observed cumulative
  counters and transcript hashes. Cached input is already included in input;
  reasoning output is already included in output. These are not billing receipts.
- Author access ended before saving. Persistent Edit models were saved and frozen;
  evaluation made no persistent game repairs. Full transcripts remain local
  because they contain account/session metadata.
- [Manifest](evidence/manifest.json) records input and artifact hashes. The runtime
  suite snapshot records the Astra override; the default suite remains Sol.

The next iteration should retain Facet's clearer task layouts while reducing
reference-reading and tool overhead, then prove the full device and gameplay
matrix. Faster completion alone did not meet this eval's efficiency thresholds.
