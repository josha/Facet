# CI and native Studio checks

Run all committed live suites with the existing Studio command:

```sh
lute run tools/facet studio live --all --complete
```

The command simulates the `hd_1080` device unless `--device` names another
device. The simulated device sets a 1919×1080 viewport. Without it, the
viewport is the Studio window, and docked panels make it smaller than the
stages. Cases then fail because their content is off the screen.

The committed Verify source plan is `tools/studio/live/plan.json`. The command
runs those sources and their registered cases. The `plan` producer checks that
each live suite source on disk appears exactly once. A source addition or removal
must update the plan. Case IDs remain in the source registrations.

The command runs automatic and interactive registrations in mixed suites. It
runs the two haptics suites as one continuous session. Case filters and resume
are not allowed in complete mode. An empty run, failed case, unsupported case or
missing host report fails the command.

The full gate declares this command as the `studio-live` producer. A portable host
defers this producer because it lacks the `native-studio` capability. Its full
tier result does not establish complete native coverage. On a provisioned host,
run:

```sh
lute run tools/facet gate full --studio-host --reference-host --require-complete
```

The host flags declare capabilities. They do not install Studio, sign in, enable
a controller emulator or supply missing input hooks. The native CI host must also
be the calibrated reference performance host for the checked-in timing budgets.
Keep those budgets and workloads. Confirm same-source timing spread on the
intended hardware before treating it as a reference host. Do not change thresholds
to make a different runner pass. The benchmarks are headless trend checks; they
do not prove a physical device frame rate.

`--require-complete` checks the existing Verify acceptance and scope. It rejects
failed, deferred, unsupported or narrowed full-tier evidence. Release-only
producers remain outside the full tier. Missing input capabilities remain in the
Verify report and fail complete mode. Native CI cannot pass while absolute timing
producers are deferred.

The **CI** workflow runs the full tier in four Linux shards and the Linux paired
performance check in three shards on free GitHub-hosted runners for each pull request and push
to main. The final **Verify** job requires every shard and the performance check
to succeed. The **release** workflow runs the full tier on macOS and Windows
before it publishes. Each performance shard takes every third paired scene with
`perf paired run --shard K/3`, compares the base and candidate on one runner and
gates its own scenes and every third microbenchmark (`bench --shard K/3`). A failed,
cancelled or skipped required job
fails Verify. The manual CI dispatch uses its base and candidate revisions for
the performance comparison and checks the candidate.

Paired performance runs when its code, workload data, fixtures, toolchain or
workflow changes. `lute run tools/facet perf affected BASE` owns this selection.
The retained heap comparison runs in the same job and report as latency.
It uses a separate measurement pass for mounted and teardown heap estimates.
When its collector, scene adapter or policy changes, the job first checks
unchanged scenes and a retained allocation of 4 MiB across three paired rounds.
The proof records all measurements and uses Verify to judge the cases.
Both arms use the same benchmark code, workloads, fixtures, maintainer tooling
and Verify snapshot. The workflow records the shared archive hash and checks
that neither arm's production source changes during measurement setup.

Native Studio checks remain outside hosted CI. The portable gate records that
deferral; a successful Verify job does not establish complete native coverage.
A native host requires an authenticated Studio session, working rendering, and
the input capabilities required by each suite. Verify these capabilities before
running the complete native gate.

Headless CI uses Verify's engine double. Add shared engine mechanisms in Verify,
with native conformance cases, then re-pin them here. Keep the original case
assertions and reject unsupported behavior. A double result proves only the
modeled behavior; it does not replace native rendering or input evidence.

The `native_live_primitives` spec runs five original live cases in the double:
Screen/VStack, grid, ZStack, stack distribution and weighted fill. It mounts
the shared live project with Verify's place runtime. Studio and the double
use the same project builder, attributes, themes and source mounts. The cases use the same
live context and assertions as Studio. The fixture supplies an 800 by 600
viewport and zero GUI insets. Verify supplies the layout, StyleSheets,
Instances, services and frame events. The fixture keeps the strict reflected
property and method rules.

The control policy fixture in `tests/lib/native_engine.luau` configures the same
Verify engine. It allows writable geometry, raw style reads and configured
service methods so tests can supply their own conditions. The live double host
uses strict reflection and computed layout. Keep engine mechanisms in Verify.
Move policy cases to the strict fixture when they no longer need those supplied
conditions.

The spec also loads every source in the committed live plan and registers its
cases. This checks source loading and the full fixture metadata. It does not
prove the behavior of those cases.

The test module loader reads source files before it runs a case. It supplies
those files to Verify's loader in memory. A signal callback can then require a
module without waiting for host filesystem operations. The live fixture shares
Verify's source and bytecode cache across isolated runtime environments. A
planted source change uses a separate cache.

The `native_live_contracts` spec adds 33 original cases. These cover padded
text geometry, stable indeterminate progress, state changes, late resize
detection, clipping detection, lifecycle, style properties, grid sizing and
content and round status containment. Together the two specs run 38 original cases. Diagnostic probes
are not included in that count.

Verify supplies bounded text measurement from 18 captured font faces. The
model supports Latin letters, digits, spaces and newlines at integer rendered
sizes 1–100. It covers automatic size constraints, wrapped visible-line limits
and stretched vertical lists. Unsupported shaping and text modes raise errors.
Verify checks 348 shared text layout configurations against Studio and the
double. This checks the selected model behavior, not arbitrary text rendering.

The 2026-10-24 full live-source audit uses the engine model from Verify commit
`4d0b46de7c8fb97ea2e4a21f4d8c99086ea7d325`. It
reports 40 passed, 894 failed and 108 unsupported out of 1,042 cases. Two passes
are diagnostic probes. The 38 original passing cases are selected in the
committed headless specs. No previous passing case regressed. This audit
reports remaining gaps; it is not a passing full live gate.

Hierarchy selectors and phantom modifiers added five original passing cases:
clear-button placement, circular button axes, segmented opening layout,
utility strokes and field accessories. The bounded automatic-parent model
added no complete passing cases. It moved 278 cases from relative sizing to
unsupported `TextTruncate`. There are now 326 cases whose first blocker is
`TextTruncate`. A first blocker does not describe every missing mechanism in
a case.

Verify checks wrapped lists and fixed-size GUI aspect constraints with 1,164
shared Studio/double layout configurations and a mutation sequence. The bounded
automatic-parent model adds 444 shared configurations and an eight-stage
mutation sequence. Growing sizing feedback, padded relative positions and
constrained automatic parents with relative children remain unsupported.
Aspect constraints on automatic-size objects and individual grid cells also
remain unsupported. Advanced text modes, scrolling geometry, input delivery,
device services and the remaining style mechanisms still block live cases.

Run the contract cases with `lute run tools/facet gate spec native_live_contracts`.
Run the primitive selection with `lute run tools/facet gate spec native_live_primitives`.
The spec also plants a gap regression and checks that the original geometry
assertion fails. It is part of the committed test plan and the existing
`tool-specs` producer. This selection does not cover the full live primitives
suite. Scrolling canvas/window geometry and native input remain outside this
selection. Unsupported mechanisms must fail; do not fill geometry
properties with expected results to make a live assertion pass.

Push comparisons use the previous commit from the push event. A manual dispatch
requires an explicit base and candidate. An absent base or an initial push with
no previous commit fails the comparison; it does not report a performance pass.

The current live driver has four explicit host gaps: a native text-size setting
change, and controller connection changes in three cases. Controller cases also
need actual controller button delivery. Keyboard events with controller key names
do not establish this capability. A desktop phase, a native touch phase and a
controller phase must retain their original assertions. The initial complete
command reports these gaps; it does not establish that the full device matrix
passes.

Open Cloud can run native server code and TextService measurements. It does not
provide the original client lifecycle or virtual input. Cloud results do not replace the Studio producer.
