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
performance job compares the pinned checkpoint and candidate on the same runner. A failed,
cancelled or skipped required job
fails Verify. The manual CI dispatch uses its base and candidate revisions for
the performance comparison and checks the candidate on each platform.

A [fresh hosted Windows probe](https://github.com/josha/Facet/actions/runs/39839446426)
on 2026-10-22 installed Studio and confirmed an interactive desktop. Studio's
RunScript task then waited at a login dialog and produced no script output.
This probe did not supply authentication. It does not establish that authenticated
hosted execution is unavailable. Hosted Studio work is deferred by maintainer
decision while headless coverage improves. Native Studio checks currently remain
outside hosted CI. The portable gate records that deferral; a successful Verify
job does not establish complete native coverage.

To revisit hosted Studio, first create a dedicated test account and provision its
session as the `ROBLOX_STUDIO_CI_COOKIE` Actions secret. The isolated
`codex/hosted-studio-readiness` branch contains an authenticated probe. It validates
the supplied session from the runner, initializes Studio's credential entries,
then checks edit and client execution. That authenticated path has not run.
Session renewal and acceptance across fresh hosted runners must also be verified.

Headless CI uses Verify's engine double. Add shared engine mechanisms in Verify,
with native conformance cases, then re-pin them here. Keep the original case
assertions and reject unsupported behavior. A double result proves only the
modeled behavior; it does not replace native rendering or input evidence.

Push and pull request comparisons use the accepted checkpoint pinned in
`.github/workflows/ci.yml`. A manual dispatch requires an explicit base and
candidate. See [paired performance](../../docs/guide/19-paired-performance.md)
for the pin and its evidence limits. An unavailable base fails the comparison.

The current live driver has four explicit host gaps: a native text-size setting
change, and controller connection changes in three cases. Controller cases also
need actual controller button delivery. Keyboard events with controller key names
do not establish this capability. A desktop phase, a native touch phase and a
controller phase must retain their original assertions. The initial complete
command reports these gaps; it does not establish that the full device matrix
passes.

Open Cloud can run native server code and TextService measurements. It does not
provide the original client lifecycle or virtual input. A current-source cloud
probe also found different TextLabel bounds for the original Callout case. Cloud
results do not replace the Studio producer.
