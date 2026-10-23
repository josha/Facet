# The run

Build one complete Roblox game from a blank place in **30 minutes**.
Compare Plain Roblox with Facet using the same brief, model, tools, deadline,
and device requirements. There are no smaller modes or follow-up author turns.

The [brief](tasks/run/brief.md) contains the complete game requirements.
The [suite](run.json) contains one task and two arms. Both authors use
Sol 6.1 Medium. Each author gets one prompt and one fresh Studio place.
Coding, reading guidance, tool calls, play checks, and self-correction all
consume the same 1800-second window. No operator coaches either author.

## Starting conditions

Each place contains a baseplate and spawn. It contains no game code, network
contract, UI, track, catalog, or solution assets. The evaluator prepares the
place before the author clock starts. Build inputs are evaluator files.
Both authors must build the game as well as its interface.

Both authors get only Studio MCP tools. Plain uses native Roblox UI APIs.
Facet also gets the current library installed in `ReplicatedStorage.Packages.Facet`,
the public consumer skill, and reference documents in `ServerStorage.FacetDocs`.
No author gets filesystem, shell, sync, build, or Studio relaunch tools.
Facet guidance must explain reusable design principles and
current APIs. It must not contain the benchmark's game implementation.
Authors must not read other submissions, earlier evidence, or hidden checks.

Provision and maximize each owned Studio before the author starts. Verify
that it renders and that scoped MCP tools can access it. Resolve the pinned
toolchain before launch. Setup time is recorded separately from author time.
A setup failure does not consume a paid author attempt.

Check the native camera viewport as well as the simulated screen dimensions.
A responding Studio with a 1-by-1 camera viewport is not ready. Wake rendering
and confirm actual frames before starting the author clock. Verify that a native
Studio menu opens and closes, then test input delivery in Play and return to Edit.
If input fails, restore and maximize the window and repeat these checks.

## Deadline and submission

Use Verify's bounded author process with `wallSeconds = 1800`. An instruction
to stop is not the enforcement mechanism. The author may finish early.
At exit or deadline, stop author access and any outstanding author mutations.
Stop Play and preserve the complete persistent Edit data model before closing
Studio. Play-only changes are temporary and are not part of the submission.

Record the saved place's hash before evaluation. Reopen and test a copy of
those bytes. Compare hashes after evaluation. Preserve scripts, instances,
terrain, and service settings. A source-only export is insufficient.
Do not repair the place, add a missing game feature, or continue the author.
An unfinished or broken submission remains an evaluated failure.

The deadline ends authoring, not evaluation. Retain the deadline result and
all available usage even if the process is stopped during a tool call.
Do not report missing token usage as zero. Distinguish a deadline stop from
an infrastructure error and from an early completed submission.

Keep the local author session log (`persistSession = true`) so a deadline
stop does not discard the available usage events. This does not permit a
resume or another prompt. Preserve the log with the evaluator's evidence;
do not infer complete usage from an incomplete event or from tool counts.

## Independent evaluation

Evaluate the frozen game against the [acceptance requirements](acceptance.md).
Keep the author absent. Discover routes from the submitted interface; do not
require an internal module name, catalog, exact wording, or admin hook. Use normal input to complete player tasks. Read server state
and source when needed to verify authority, persistence, and effects. A source
review alone does not prove that the player can perform the action.

The evaluator writes `evaluation/player.luau` in each run's evidence directory
after inspecting its frozen submission. Use the existing Play host and Verify
cases. Adapt locators and read-only observations to the submitted game, while
keeping every acceptance requirement unchanged. Keep this check source with the
evidence. Do not require each author to use the same labels or network contract.
The required `play` check fails while this file is missing. An initial author
result is therefore incomplete until its independent checks have run.

Use the case IDs `<device>/play/<outcome>` listed in `eval/compare.luau`.
Each case must cover the complete corresponding acceptance row, including its
rejection and return paths. Attach the starting state, actions, observations,
and captures. Do not mark a row passed from a subset of its assertions. Use
separate cases for diagnostic subsets. Check source observations against live
player behavior, and demonstrate that a false result fails the assertion.
Review both arms against the same requirements before accepting either report.

The optional generic navigation scan is a calibration tool, outside the automatic
run. Its common root labels do not find every valid nested route. The
submission-specific player checks must follow those routes and verify their
layout, input, stability, and return behavior. Diagnostic captures use a
`navigation-` prefix and must not enter the matched visual comparison.

Use Verify cases and reports, the existing Studio host, native input, UI
audits, screenshots, and performance observations. Record each requirement
as passed, failed, or unverified, with the action and observed result.
Unverified requirements cannot contribute a pass. An evaluator problem is
reported separately from a game defect; it does not excuse missing evidence.

Check desktop, portrait phone, landscape phone, tablet, and console input.
Also resize and rotate an open task. Native Studio simulation does not prove
behavior on physical phones or physical controllers; state that limit.
Keep every owned Studio maximized and record actual viewport dimensions.

Judge equivalent player states with anonymous A/B captures in both orders.
Use the Sol 6.1 Medium judge separately from any other judge. Assess hierarchy,
legibility, composition, coherent art direction, compact layouts, and feedback.
A beautiful screenshot does not override a broken interaction.

## Pass requirements

Freeze these requirements before the first author pair. Do not change them
in response to a disappointing result.

- Every required player outcome works. The complete game loop works on all
  five device configurations. No blocking overlap, unreadable essential text,
  inaccessible action, false transaction result, or broken return route remains.
- The blind judge prefers Facet in at least 70% of matched comparisons.
  Report disagreements between presentation orders and ties explicitly.
- Facet uses at most 50% of Plain's total author tokens, including cached input,
  and at most 60% of Plain's author wall time. Median author turn latency must
  also be lower. A shared thirty-minute ceiling does not establish a latency win.
- Frame-time and retained-memory overhead are each strictly below 5%.
  Check idle and active frame p50/p95 and post-return Luau heap and GUI memory
  on each device. Repeated navigation must return memory to its settled level.
  Missing samples, failed return routes, and measurement noise that crosses the
  limit cannot establish a pass.
- The required repository gate, benchmark, package build, package status, and
  live Studio checks pass on the proposed final changes. Separate pre-existing
  failures from regressions and name limits on the evidence.

Compare equivalent game states and report scene differences. Whole-client
frame cadence can hide UI cost and includes the authored world. Use the
controlled Facet/Plain performance benchmarks as well as the game observations;
do not attribute an easier world or omitted feature to lower library overhead.

Keep at least 120 rendered frame samples for the idle hub, open shop, and active
race on each device. Keep each state's p50 and p95; a mean across menus does not
replace the race measurement. Record post-return memory only after a successful
return. The [comparison cases](compare.luau) check these measurements, complete
player-outcome coverage, author cost, capture coverage, and both judgment orders.
Run them on the recorded pair with `lute run tools/facet facetbench compare`.
Use `--evidence PATH` to select a different pair directory.
The command writes the standard Verify report to
`artifacts/facetbench/run/comparison.verify.json`. A missing pair fails.

The comparison consumes Verify's recorded results. It does not establish place
custody or prove that an incorrectly written player check is meaningful. Verify
the frozen place and calibrate the player checks before accepting the report.

This is a paired game result. Do not count screens, requirements, devices, or repeated judgments
as independent authored games, and do not claim a population confidence interval
from a single pair.

## Iteration

Establish a new Plain/Facet baseline under this protocol. During development,
reuse the frozen Plain result only while the brief, tools, model, evaluation,
and environment remain comparable. Change Facet and its general guidance from
observed failures, then author a fresh Facet submission from blank. Never repair
the previous submission and call it a new author success.

Keep source revisions, input hashes, frozen submissions, transcripts, judgments,
and Verify reports together under `artifacts/facetbench/run`. Report author cost
separately from evaluation cost. Preserve enough evidence to reproduce the latest
comparison without committing a history of generated games.

Keep reusable design changes separate from evaluation results. Open the design
PR before the author run. Record the evaluated source revision with the result.
Commit only the latest [Plain place](latest/plain/game.rbxl) and
[Facet place](latest/facet/game.rbxl). Put the verdict and gaps in the PR description.
Keep generated reports and captures in the artifact directory. The existing
[Kart example](../examples/facet-kart/README.md) remains a game example; it is not
an author starter or a new benchmark result.
