# The run

See the [latest evidence and pass readout](latest/README.md).

The separate [UI design history set](design-history/README.md) preserves the
theme studies, references, design iterations and reviewer disagreements. It
has its own frozen poker trial and does not rerun this full-game baseline.

The [guidance trials](guidance-trials/README.md) keep the small paired trials
that changed the use-facet guidance: one screen, fresh authors and blind
reviews of captures. They are development evidence, not this baseline.

The [controlled UI study](controlled-ui/README.md) holds the game, camera and
server behavior fixed while comparing plain Roblox and old/new Facet guidance.
It reports six Sol runs, native input checks and both-order visual judgments.
It is a separate key-screen experiment, not the full-game baseline below.

Build one complete Roblox game from a blank place in **30 minutes**.
Compare Plain Roblox with Facet using the same brief, model, tools, deadline,
and device requirements. There are no smaller modes or follow-up author turns.

The [brief](tasks/run/brief.md) contains the complete game requirements.
The [suite](run.json) contains one task, two arms and three author agents:
`codex-sol` (Sol 6.1 Medium), `codex-sol-images` (the same author with its
image generator left on) and `claude-opus` (Opus 5.5 Medium). Select one
author with `--agent ID`, so both arms of a pair use the same model and the
same tools. Compare a `codex-sol` pair with a `codex-sol-images` pair to see
what images add; do not pair an arm with images against one without. Before
a `codex-sol-images` pair, approve the generator's output folder for uploads
in each owned Studio (Assistant Settings, MCP Permissions), and pass the
[image preflight](#image-preflight), or the authors can make a concept but
cannot put art in the game. Each
author gets one prompt and one fresh Studio place. Coding, reading guidance,
tool calls, play checks, and self-correction all consume the same 1800-second
window. The brief does not state the limit; the runner stops the author at the
deadline. No operator coaches either author.

Keep automatic instruction discovery off. Codex's `--ignore-user-config`
excludes `config.toml`; it does not exclude ancestor `AGENTS.md` files or the
host's skill catalog. The suite disables project document loading and automatic
skill discovery. Pass each arm's frozen instructions explicitly. Facet still
receives its skill in those instructions and its references in StudioDocs;
Plain must not inherit Facet guidance from the evaluator's repository.
The judge policy uses the same isolation settings in its neutral directory.
Before an author run, inspect the model-visible prompt with the installed
CLI's `debug prompt-input` command under the same instruction and skill
settings. Retain the prompt audit and CLI version with the frozen inputs.
Check tool availability separately in the actual author session; the local
prompt audit does not include every tool supplied at runtime.
The [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)
describes the document and skill settings. A leaked instruction makes the
affected run an invalid pilot; preserve it and restart from a fresh fixture
and session after correcting the profile.

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
Keep setup failures separate from author results. If a failure occurs after a
model starts, retain the partial usage and submission.

Before a paired launch, verify the public runner on a fresh evidence directory
with two local fixture processes. Both must start before either can finish.
Also verify the deadline and child-process cleanup. This check uses no model.
After the paid launch, confirm both author processes started and record their
actual overlap. A parallelism setting alone does not prove concurrent execution.

Use the common [authoring protocol](authoring.md) for both arms. Record the
suite, author model, reasoning effort and source revision before launch.
Use `lute run tools/facet facetbench prepare --suite PATH` to prepare the
restricted model catalog for that suite's authors. Without `--suite`, prepare
uses the canonical Sol suite. Prepare also rebuilds the Facet author kit in
`artifacts/facetbench/arm-facet` from the checked-out source. Run it at the
commit under test, before every pair, and confirm that
`tools/facet/kit.json` in the kit names that commit.

Check the native camera viewport as well as the simulated screen dimensions.
A responding Studio with a 1-by-1 camera viewport is not ready. Wake rendering
and confirm actual frames before starting the author clock. Verify that a native
Studio menu opens and closes, then test input delivery in Play and return to Edit.
If input fails, restore and maximize the window and repeat these checks.

Hold the display and system awake through a passive OS power request during
setup and authoring. Record its acknowledgment and release. Do not send player
input to keep the display awake. Verify a capture after a repeated Play cycle
and through a fresh scoped connection. For concurrent arms, check both native
renderers while both Studios are open. Close each preflight transport and verify
that its owned process exited before handing the Studio to the author.

## Image preflight

An author whose suite entry declares `preflight` must have both routes
proven before its clock starts: `image-generation` and `asset-upload`. Try
each route through the same scoped tool set that the author will get, in
its own owned Studio. A generator that answers is not enough: on 12
November the scoped Studio tools had no upload tool, and the author could
make images and could not use one.

1. List the tool names of the author's scoped Studio connection.
2. Generate one small image with the author's generator.
3. Upload it with one of those tools (`upload_image` or `open_cloud_invoke`),
   and see the asset loaded in that Studio, for example an `ImageLabel`
   whose `IsLoaded` is true.
4. Write `preflight/images.json` in the run's evidence directory:
   `{ agent, tools, generation = { ok, file, bytes, at }, upload = { ok,
   tool, assetId, loaded, at }, authorStart }`. Times are seconds on one
   clock. Leave `authorStart` out until the clock starts, then record it.
5. Run `lute run tools/facet facetbench preflight --evidence DIR --agent ID
   --report PATH --run ID`. Start the author only when it passes. Run it
   again after the launch, with `authorStart`, so the report shows that both
   routes were complete before the clock.

A failed preflight is a setup failure. Keep its record and report; repair
the tool set and write a new record under a new evidence directory.

## Deadline and submission

Use Verify's bounded author process with `wallSeconds = 1800`. An instruction
to stop is not the enforcement mechanism. The author may finish early.
At exit or deadline, stop author access and any outstanding author mutations.
Stop Play and preserve the complete persistent Edit data model before closing
Studio. Play-only changes are temporary and are not part of the submission.

`facetbench seal` saves the kept Studio place and freezes its bytes. On
Windows it sends Control-S to the kept Studio window. On macOS it sends
Command-S through System Events, which needs the Accessibility permission
for the program that runs `lute`. When the save cannot be sent, save the
place in the kept Studio by hand and run `facetbench snapshot --place PATH`;
both routes freeze the same bytes. `facetbench check-submission` reopens the
frozen place and fails when its hash differs. A failed save changes nothing
in the place.

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

Calibrate locators against a retained UI dump before a multi-device run.
A card can have an empty button label and a title in a sibling object. Use a
scoped query such as `{ role = "button", near = "Item title" }` and confirm
the returned target. Do not assume that the title is the button's text.
Scope duplicate commands to the open task. Parse the complete wallet token;
for example, the Luau pattern `cr%f[%W]` does not match the word `credits`.
Check all matching balances before an action, not only the first number.

`qa:tap` requires full reveal. Keep that check when the task requires the
whole target to be visible. If a partly visible button is the intended
target, `qa:tapVisible(query)` checks native reachability and requires an
activation. It returns the native hit bounds as its third value. Retain
those bounds and the capture. This action does not prove full visibility.
It supports pointer and simulated touch, not console selection. Do not
use it as an automatic fallback for an ambiguous or unmatched query.

Give each `context:attach` call a unique name within its case, including
repeated route entries. Use a phase or sequence in the name. Check reopening
in the setup fixture so a duplicate attachment cannot stop a later task.
Use Verify's duplicate-name error; do not replace its attachment mechanism.
Retain the failed report when correcting an evaluator error, then run only
the affected cases. Keep partial diagnostic cases separate from full rows.

Check desktop, portrait phone, landscape phone, tablet, and console input.
Also resize and rotate an open task. Native Studio simulation does not prove
behavior on physical phones or physical controllers; state that limit.
Keep every owned Studio maximized and record actual viewport dimensions.
Record the observed input flags as well as the intended device preset.
A simulated console can report `GamepadEnabled` without physical controller
events. Arrow keys and Return test engine selection; they do not prove L3,
other controller bindings, or physical controller behavior.

Judge equivalent player states with anonymous A/B captures in both orders.
Inspect `outputs/captures.json` before preparing judge inputs. Capture triage
does not validate UI content, player state, device size, settled motion or custody.
`unreviewed` means only that the image passed pixel heuristics. Noise and a
world-only view can pass those heuristics and must not count as UI evidence.

A capture enters the matched comparison only when its interface dump shows
the requested state. List each candidate in `judge-candidates.json` in the
evidence directory: `{ arms, captures = { { id, arm, device, screen, image,
dump, attempt, expect = { visible, absent, modal } } } }`. `visible` names
texts that the state must show, in the words of that submission, and
`absent` names texts that it must not show. `lute run tools/facet facetbench
admit --evidence DIR` checks each dump and writes `admission.json`:

- every screen needs one visible text that the evaluator named, and
  `tutorial` needs two, such as the lesson's title and its next step. A
  capture that shows only a collapsed launcher is excluded.
- `hub` and `race` must have no layer over their controls. A race capture
  with a menu open is excluded. Set `modal = "any"` only with a reason in the
  evaluation notes.
- a capture with no dump is excluded: its state cannot be checked.
- a pair is compared only when each arm has an admitted capture of that
  device and screen. The latest admitted attempt is used.

Excluded captures stay in the evidence with their reasons, and a rerun gets a
new `id` and a higher `attempt`. Do not delete or overwrite a failed attempt.
Build the judge bundle from the admitted pairs only, and report the pairs
that were not compared.

The Play host retains every decoded attempt in `outputs/capture-review`.
Uniform images and images smaller than 64 pixels on either axis are `unusable`.
Low-contrast or mostly single-color images are `needs-review`, not blank: sparse
UI can produce either result. They have a `reviewPath`, but no judge-input `path`.
Review the retained image with its state, viewport and custody evidence. Record
the decision and exact image identity before admitting it to a separate matched
judge bundle. Keep the original image and triage record unchanged. Missing,
unusable, world-only or unreviewed suspicious captures cannot establish a visual
win. `capturesKept` counts heuristic candidates, not validated screenshots.

The canonical suite uses the Sol 6.1 Medium judge. The suite's `judge.rubric`
scores both games against the principles of the
[game UI design guide](../skills/use-facet/references/GAME_UI_DESIGN_GUIDE.md):
player intent, attention, game identity, facts at a glance, protected play,
adaptation, continuity and truthful outcomes. More content on a screen is not
better by itself. A beautiful screenshot does not override a broken interaction.

The canonical suite uses Sol. For an Astra evaluation, record
`gpt-6-astra` and `medium` explicitly. The [judge policy](judge.luau) passes
these values to public `AgentEval.judge.codexCli`; public
`AgentEval.judge.compare` still owns both presentation orders and the verdict.
Create each neutral parent directory before parallel comparison groups start.
Keep each group's directory unique and outside the source tree. Keep the
command arguments with the evidence. The judgment records the model; it does
not record reasoning effort, so do not infer effort from the verdict.

Pass the matching `Compare.Identity` to `Compare.cases`: suite, task, agent,
model, seed and judge model. Omission keeps the canonical Sol identity.
Do not rename earlier Sol results as Astra results to satisfy this check.
Different model pairs can support a descriptive comparison, but cannot pass
the same-model pair check.

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
Use `facetbench compare --suite PATH --agent ID` to check that author's identity
and use the suite's evidence directory. `--judge-model ID` replaces the suite's
judge model. Without `--suite`, comparison keeps the canonical Sol identity. A comparison with different author models does
not pass the same-model requirement.
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

Keep reusable design changes separate from evaluation results. Follow the
experiment's declared publication timing. Record the evaluated source revision
with the result.
Commit only the latest [Plain place](latest/plain/game.rbxl) and
[Facet place](latest/facet/game.rbxl). Put the verdict and gaps in the PR description.
Commit the reviewed latest reports and captures with the places. Keep raw logs and prior generated evidence in the artifact directory.
