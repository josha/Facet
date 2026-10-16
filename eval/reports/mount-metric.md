# Mount measurement

The shared probe measures the first complete layout that stays stable for one
second of rendered frames. It compares every measured object's identity,
parent, absolute position and absolute size. Structure changes restart the run.
It excludes a TextLabel or TextButton's own Text change in that frame, and a
one-axis size change inside a fixed-size parent when the element's position
stays fixed.
Other position and size changes restart the run, including neighbour movement
from a live counter. Both arms and both references use this probe.

The 20-second settle bound and 1.10 Facet/plain mount limit are unchanged.
Timeout captures are explicit failures to establish a stable layout. Their
value is the bound plus the host offset, rather than a completed mount time.
Mount includes player join, probe readiness, host calls and fixed host waits.
It does not isolate construction CPU time.

## Tests

The nine Verify cases in `tests/play_mount.verify.luau` cover a static HUD,
growing fill, ticking countdown, text content sizing, a counter that shifts its
neighbour, additions, removals, replacements, reparenting, two-axis sizing,
position movement, an empty screen and the stable-run clock. They check that
structure changes restart the clock, that repeated neighbour movement never
settles, and that live content can complete the same run as a static HUD.
They also check that a timed-out capture emits its timeout flag and no valid
mount overhead score. The existing missing-evidence rule fails closed.

The Roblox APIs used are `GuiBase2d.AbsolutePosition`, `AbsoluteSize`,
`TextLabel.Text`, `TextButton.Text`, `Instance.Parent`, `GetDescendants` and
`RunService.RenderStepped`. Compose ownership and geometry helpers do not
provide this benchmark policy. Verify supplies registration, assertions,
execution and reports.

## Reference calibration

The slice runs all six universal cases on desktop and phone portrait. The
commands invoke `eval/tasks/racing-hub/hidden/play.luau` directly with
`--systems hud-dock,shop --tier universal`. No agent evaluation is run.
Each workspace copies the slice starter, then the 11 files in the declared
`eval/validation/slice.json` fixture map with its arm substitution. Each built
interface has one Kit module. The direct weak Rojo project has three Kit
modules at the same path, including strong modules, so its results are outside
this calibration. `reference-source-check.json` records the source variants.
`calibration-workspace-hashes.json` verifies all 22 arm-specific fixture copies
against the declared files and records the manifest hash.

| Reference | Desktop | Phone portrait | Build |
| --- | ---: | ---: | --- |
| Strong | 6/6 | 6/6 | Pass |
| Weak | 0/6 | 0/6 | Pass |

Weak desktop failures cover incomplete scrims and a wallet readout that does
not follow server state. Weak phone failures cover truncated text, absent
route controls and a Shop control covered by the open shop. The case reports
retain each failure separately. These results establish separation for these
universal cases on the two Studio simulator devices.
The final case reports, scores, performance records and captures are under
`artifacts/mount-metric/calibration-slice/{strong,weak}`. All four reference
mount observations hit the settle bound. Universal case success remains
separate from valid mount overhead evidence.

## Saved-build measurements

The plain workspace is the saved plain build from the first slice run. The
Facet workspace is a copy of a saved Facet slice build.
Its 40 saved source files match. Its replacement `Packages/Facet` matches all
319 package files in the Facet arm kit built from this change.

Each capture observes both definitions on the same rendered frames with the
same play-start clock and host offset. The old definition uses the whole-screen
geometry checksum and one quiet second. The new definition uses per-object
layout comparisons and the live-content exclusions. Each definition stops at
its own first stable run or the 20-second bound. One owned Studio runs at a
time and closes before the next capture. The measurements are three captures
per build and device, not independent task seeds or confidence intervals.

The selected evidence is under `artifacts/mount-metric`. Each capture keeps
`perf.json`, `play.log`, the built place and desktop and phone captures.
`mount.liveContent` records distinct identities, full paths, reasons, frame
counts, observation times and first and last before/after samples. These
records make the exclusions auditable, including elements with duplicate names.

Selected captures are `captures/{plain,facet}-{2,3,4}`. Each built probe contains
the shared per-object classifier and layer-collector geometry observation.
Capture 1 is outside this set because its embedded probe does not match the
current source.
`summary.json` contains the samples, medians, ratios, timeout counts and path
unions. `snapshot-hashes.json` records the saved source and replacement kit.
`capture-hashes.json` records each built place hash and the embedded classifier
and mount-observation code hashes. All six selected places contain the same
measurement code, and both hashes match the current source.

Times are seconds. Ratios divide the Facet median by the plain median. A star
marks a median with timed-out samples; those cells and ratios are raw bounded
observations, not valid completed-mount estimates.

| Device | Old plain | Old Facet | Old ratio | New plain | New Facet | New ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Desktop | 3.261 | 22.244* | 6.820* | 2.424 | 3.379 | 1.394 |
| Phone portrait | 22.414* | 22.284* | 0.994* | 9.281 | 22.418* | 2.415* |

| Device | Build | Old samples | New samples | Old timeouts | New timeouts |
| --- | --- | --- | --- | ---: | ---: |
| Desktop | Plain | 9.257, 3.261, 3.241 | 2.424, 2.429, 2.424 | 0/3 | 0/3 |
| Desktop | Facet | 22.238, 22.244, 22.294 | 4.955, 3.329, 3.379 | 3/3 | 0/3 |
| Phone portrait | Plain | 10.280, 22.440, 22.414 | 9.264, 9.358, 9.281 | 2/3 | 0/3 |
| Phone portrait | Facet | 22.293, 15.158, 22.284 | 22.427, 15.158, 22.418 | 2/3 | 2/3 |

The desktop point ratio is above 1.10. The new phone measurement has two Facet
timeouts and cannot establish a passing mount result. The old phone ratio is
near one because both arms have two timeouts. These three captures do not
establish a task bootstrap interval or a passing headline claim.

## Live-content exclusions

Paths below omit `Players.voidmeld_agent.PlayerGui.`. Full paths, stable
per-run identities and samples remain in every selected capture's `perf.json`.
The lists are unions across the three captures; an exclusion does not hide a
change in any other element.

Both plain devices exclude Text changes in `ApexHub.Root.Dock.Offer`,
`ApexHub.Root.WalletAndProgress.Coins` and
`ApexHub.Root.WalletAndProgress.Progress`, and one-axis fill changes in
`ApexHub.Root.WalletAndProgress.ZoneTrack.Fill`.

Facet paths share the prefix
`ApexHub.HubRoot.TouchSafeRoom.HubHUD.Zones.`. Both devices exclude Text changes
in these five elements:

- `Bottom.DockRegion.Form1.Dock.OfferDock`
- `Top.TelemetryRegion.Form1.Telemetry.LiveWallet`
- `Top.TelemetryRegion.Form1.Telemetry.ZoneReadout`
- `Top.TelemetryRegion.Form2.CompactTelemetry.LiveWallet`
- `Top.TelemetryRegion.Form2.CompactTelemetry.ZoneReadout`

Both Facet devices also exclude one-axis size changes in these three elements:

- `Bottom.DockRegion.Form1`
- `Top.TelemetryRegion.Form1.Telemetry.ZoneProgress.Track.FillClip.Fill1`
- `Top.TelemetryRegion.Form2.CompactTelemetry.ZoneProgress.Track.FillClip.Fill1`

Phone portrait also excludes one-axis size changes in `Top` and
`Top.TelemetryRegion.Form1`. The container rows are listed explicitly because
the fixed-parent, fixed-position, one-axis rule applies to them as well.

## Repository checks

- `lute run eval/tools/check.luau`: exit 0; the corpus is consistent.
- `lute run tools/facet gate fast`: exit 0; all 14 selected producers pass.
  Evidence: `artifacts/verify/native/gate/gate-1792146940-583355-1/outcome.json`.
  This tier deselects 14 cases.
- `lute run tools/facet types`: exit 0; 1,214 targets, zero blocking
  diagnostics, all 186 public negative probes rejected. The old solver runs
  under the repository's default configuration. Dependency diagnostics remain
  separate from owned blocking diagnostics.
- `lute run tools/facet gate full`: exit 0; 36 producers pass and two timing
  producers are deferred. It selects 38 of 39 producers, with no case
  deselection. Bench lacks the reference-host capability; perf exceeds host
  timing budgets away from that host. The release-only producer is outside
  this tier. This is selected evidence, not complete or release evidence.
  Evidence: `artifacts/verify/native/gate/gate-1792146269-753109-1/outcome.json`.
- `lute run tools/facet bench`: exit 2, `FAIL_ENVIRONMENT`; the yardstick drifts
  43.7 percent. This run supports no timing improvement or regression claim.
  Evidence: `artifacts/mount-metric/bench.log` and `bench.json`.
- `lute run tools/facet package build`: exit 0; the package builds locally.
- `lute run tools/facet package status`: exit 0; publication remains separate
  and the package Studio check is pending.

Lute's shared typedef cache requires access outside the sandbox on this host.
The fast gate with cache access passes. No any budget, universal
case, reference source, motion value, overhead budget or limit changes.
Generated example place binaries are restored after build verification.
Selected captures and references have no Studio cleanup warnings.
No agent evaluation, package publication or push is performed.
