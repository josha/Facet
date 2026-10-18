# Verification scope

The current suite is the evidence. A passing run proves only the cases and
producers that the runner selected. A focused run is not full evidence. Do not
infer a performance improvement from a shorter verification time.

## Headless evidence

The control specs check input, layout policy, and resource cleanup. Test counts do not measure coverage. Read the assertions and results for the selected build.

`tests/plan.json` lists the executable spec sources. The Verify gate runs the
cases that these sources register. Reports record each case result and the
selected tier. A native engine double checks control policy, state and resource
ownership. It does not prove engine layout, paint or real input behavior.

`lute run tools/facet check plan` checks that the plan lists every spec file on disk
exactly once. It rejects missing files, duplicate IDs and incorrect source
paths. The `plan` producer runs this check. The `suite` producer runs the
registered cases and records their results.

## Live evidence

Geometry, hit testing, text editing, scrolling, selection and real input need
live Studio evidence. The live runner uses Verify to produce case reports.
Use the report for the build, device and case that ran. A source file or a
hand-written observation does not replace a run result.

The desktop fixture waits for the native viewport and CoreGui insets to settle
before each case. A zero top bar rectangle during CoreGui startup is not a
stable desktop environment. The frame matrix still records later native inset
changes and does not use them to discard geometry faults.

For padded, unwrapped text, the clipping check also compares native glyph
bounds with the padded content box. Roblox can report `TextFits = false` when
those glyphs fit. Wrapped text, real padding overflow and clipping by an
ancestor still fail the check.

The native shelf check also fails if the engine reports a layout event loop
while the gallery changes size or viewing distance.

The calendar toggle check waits for visible, interactive native content before
the next click. It fails if the calendar does not become ready within four seconds.
Interactive runs keep the selected Studio device profile between cases.

The live fixture uses the binary place format. The native dependency check
loads the XML codec and parses text across adjacent CDATA sections. This check
detects script source lost during place loading.

The frame stability matrix records the paint of an indeterminate progress bar.
It checks the bar's layout box and nearby controls for late changes. It does
not require the moving fill inside that box to stop. A negative case changes
the bar's width during activity and checks that the matrix reports the change.

A change to a text property, visibility or a native scroll position starts a new state in
the frame stability matrix. Geometry must stay stable while that state stays
the same. Negative cases change the text, visibility or scroll position, then change a box
width on the next frame. The matrix must report that late change.

Focus recordings use one Verify case per page. The recorder discovers stops
as native scrolling reveals more rows. The run deadline bounds this work.
The recorder does not stop after 512 stops in a larger collection.
Each input recording keeps its own native geometry and stop indices.

Studio device simulation does not prove physical haptic output, device memory
pressure, thermals or battery use. See
[device verification](11-device-verification.md) for the commands and device
checks.

## Gate evidence

The gate records the selected producers, case results, failures and deferrals.
A complete tier means that all selected commands were attempted. It does not
prove fresh Studio evidence for every control or physical device behavior.
The `release` tier requires the complete gate with no deferrals.

Timing budgets stop the run on the reference host. On other hosts, `bench` is
reported as `deferred` without running, and a failed `perf` timing budget is
reported as `deferred`. A deferral is not a passing measurement.
Compare performance reports only with their workload and host limits in view.
See [paired performance](19-paired-performance.md) for the comparison method.

Use [Contributing](../../CONTRIBUTING.md) to run the current tier. Read the
Verify reports to determine what passed, failed, was unsupported or was not
selected.
