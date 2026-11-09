# Use this evaluation set

## Historical review and calibration

Choose a question before inspecting the labels. Examples are whether a
reviewer catches clipped paint, whether a runtime retains the selected target's
composition, or whether it confuses a matching palette with distinctive design.
Use the original brief, guidance version and relevant unscaled images. Include
the relevant small viewport and changed states. Keep input findings separate.

For a blind screen review, use the existing `facet-critic-case/1` format and
`lute run tools/facet critique cases`. Give a fresh reviewer only its packet
and the chosen critic brief. Do not give it this catalog, source assessments,
owner labels, arm assignments or other reviewers' output. Use
`lute run tools/facet critique score` after the verdict is frozen. The
[development cases](../critic/development-cases) include the owner's Moon
Market disagreement. A repeat of a known case is calibration, not unseen proof.

The five checked-in calibration cases are a small, failure-focused seed. They
are not a balanced benchmark or a fully owner-rated gold standard. Most labels
are parent interpretations, and only the stated owner observations carry owner
authority. The historical archive contains many more images and original
reviews, but those reviews are not automatically ground-truth labels.

Do not average scores across different frozen rubrics, models, task scopes or
intervention stages. Use a common rubric and blind protocol for a new paired
comparison, and retain the older judgments as provenance. The historical runs
changed several conditions; they do not isolate every guidance change's effect.

The four new repair-pair cases have neutral `history-screen-*` IDs so the
screen name does not reveal before/after or the expected verdict. The older
Moon Market calibration has `bland` in its ID; retain that original record,
but do not describe its earlier run as a fully blinded quality test.

For a target-to-runtime comparison, show the original target with the actual
first representative screen and each later source-matched revision. Preserve
labels such as concept-only, first screen, internal repair, first delivery and
directed repair. Do not average a serious usability defect into a visual score.
If provenance or timing is unknown, say unknown rather than inferring it from
a filename. The catalog's path-based groupings do not establish causality.

## A new author trial

Freeze and hash the consumer kit and task before starting. Use a fresh author
with no access to this corpus or prior solutions. State the player task and
constraints without prescribing a control unless that control is the subject
of the test. Keep operational assistance separate from design feedback.

Preserve the alternatives, selected target, first representative runtime,
internal review rounds, first complete delivery, and all later interventions.
Tie source and captures to hashes. Test desktop, measured smallest portrait,
short landscape, relevant notched layouts and console. Use actual pointer,
Touch and native virtual-controller events. Test rotation and return with an
existing draft and accepted state. Record unavailable evidence as unavailable.

Freeze author delivery before parent review or repairs. Report failures as
well as successes. One trial is an example of transfer, not a reliable rate.
Repeated families and all tasks used to revise the candidate are exposed
development material. Future test tasks must be selected outside that history.

The current poker trial uses gpt-6.1-sol at medium, frozen guidance, no parent
design coaching before first delivery, and up to three independent Sol-medium
reviews across target, runtime and final task. Its original brief and protocol
are in the evidence bundle. Original artwork uploads are authorized; generated
concept text is never substituted for live labels or playable game state.
