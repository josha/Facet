# Astra Medium evaluation

The proposed changes improve modal focus recovery, author guidance, native
Studio readiness, and concurrent evaluation startup. Evaluated source: `b7a2c8f1`.

Both authors used Astra Medium, Studio MCP only, the same brief, and a
30-minute limit. They started less than one second apart. The complete games
are frozen: [Facet](facet/game.rbxlx) and [Plain](plain/game.rbxlx).

## Visual judging

Astra Medium judged the available valid states in both presentation orders.
The expanded comparisons favor Plain on desktop, both phone orientations,
and the available console states. Tablet produced a split result. Each order
used one attempt: ten judgments across five device presets.

| Device | Result | Valid states compared |
| --- | --- | --- |
| Desktop | Plain in both orders | Hub, Shop, Garage, Livery, Race, Tutorial (6/7) |
| Phone portrait | Plain in both orders | Hub, Shop, Garage, Livery, Race, Tutorial (6/7) |
| Phone landscape | Plain in both orders | Hub, Garage, Livery, Tutorial (4/7) |
| Tablet | Split between orders | All seven states, including Results |
| Console | Plain in both orders | Hub and Tutorial (2/7) |

Only tablet has the complete seven-state comparison. The other comparisons
are diagnostics of the listed states. Failed routes were not substituted for
the requested panels. Plain's tablet Results image came from a failed return
check; it shows Results but does not prove that Return works.
Console panel captures that remained on Hub were excluded. The controller
Race captures contain different overlays and were kept as input observations.
Console Hub/Tutorial captures used the Xbox preset with keyboard-driven
selection. Actual Controller Emulator input was checked in a separate pass.

The earlier desktop Hub/Garage/Tutorial comparison favored Facet in both
orders. It remains in the archive as preliminary evidence. The expanded
comparisons above are the main result.

[Selected captures](captures) provide a small preview. The archive contains
the exact images used for every judgment.

## Native input checks

The frozen games were checked with desktop mouse and keyboard, simulated
touch on both phone orientations and tablet, and Studio's Controller Emulator.
These are native Studio checks; they do not claim physical-device coverage or
complete acceptance of every interaction.

The five-device capture reports recorded 23 passed and 3 failed checks for
Facet; Plain recorded 10 passed, 9 failed, and 2 unsupported. Each report
includes one build check. The drivers selected different diagnostics, so
these counts are not comparative scores.
Failures and evaluator limits remain in the reports. For example, portrait
touch controls obstructed Plain's acceleration/help targets, and a reserved
Tab injection prevented Facet's desktop Results capture.

The Controller Emulator delivered actual `Gamepad1` ButtonA, ButtonR2, and
Thumbstick1 events in both games. Facet's ButtonX also opened its race terminal.
Queue entry used a pointer fallback, so this was a mixed-input route.
Plain moved under the trigger/stick hold; Facet remained at 0 km/h with an
unchanged camera. The final captures show Facet's race terminal and Plain's
Leave Drive confirmation over their races. The check did not isolate why
those overlays appeared or prove complete controller-only gameplay.

The two controller cases passed event-delivery assertions, not gameplay
acceptance. All owned Studio processes closed, the display wake hold was
released, and both frozen game hashes remained unchanged.

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
