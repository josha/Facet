# CI and native Studio checks

Run all committed live suites with the existing Studio command:

```sh
lute run tools/facet studio live --all --complete
```

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

The **CI** workflow runs platform checks and paired performance checks on free
GitHub-hosted runners for each pull request and push to main. The final **Verify**
job requires both job matrices to succeed on Linux, macOS and Windows. Each
performance job compares the base and candidate on the same runner. A failed,
cancelled or skipped required job
fails Verify. The manual CI dispatch uses its base and candidate revisions for
the performance comparison and checks the candidate on each platform.

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

The `native_live_contracts` spec adds 27 original cases. These cover padded
text geometry, stable indeterminate progress, state changes, late resize
detection, clipping detection, lifecycle, style properties, grid sizing and
content. Together the two specs run 32 original cases. Diagnostic probes
are not included in that count.

Verify supplies bounded text measurement from 18 captured font faces. The
model supports Latin letters, digits, spaces and newlines at integer rendered
sizes 1–100. It covers automatic size constraints, wrapped visible-line limits
and stretched vertical lists. Unsupported shaping and text modes raise errors.
Verify checks 348 shared text layout configurations against Studio and the
double. This checks the selected model behavior, not arbitrary text rendering.

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
