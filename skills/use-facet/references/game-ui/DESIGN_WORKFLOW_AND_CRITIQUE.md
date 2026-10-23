# Design workflow and critique

Part of [Designing game interfaces with Facet](../GAME_UI_DESIGN_GUIDE.md).
Use this chapter to choose and evaluate a composition; control signatures belong
in the installed API docs.

## Establish the design brief

For a substantial screen, define the player task, surrounding gameplay, facts
needed before action, primary command, return path and smallest complete form.
For a repair, state only the affected decision. Name the intended pace: glance,
quick choice, sustained comparison or celebration.

Make the brief testable: “compare eligible objects and equip one” identifies a
result; “display data” does not. State what players should notice first, second
and third, and what mistake would disprove the design.

## Design the content and flow before the surface

Use representative labels and values, including a long name, missing image,
large total and useful error. Separate identity, state, comparison facts and
commands. Sketch entry, decision, commitment, result, return and recovery.

Compare plausible structures where the choice matters: a grid supports visual
recognition; a table supports shared-attribute comparison. Judge simultaneous
visibility, navigation cost and compact behavior. Avoid making players remember
facts from several tiny steps when one coherent decision would work.

## Establish a visual system that can survive content

Build one representative task and its important states before spreading the
pattern. Test it over quiet and busy gameplay backgrounds.

| Decision | Facet expression and design criterion |
| --- | --- |
| Type and spacing | Semantic `textRole`, theme typography/spacing, shared reading edges; separate groups more than their contents |
| Surfaces and art | Distinguish world, task, object and overlay; use theme chrome/content insets without nesting a box around every fact |
| Color and emphasis | Reserve strong accent for a purpose; focus, selected, equipped, locked and pending need distinct cues beyond color |
| Commands | Give the main action stronger emphasis; keep frequent supporting actions direct and rare ones in a Menu |
| Motion | Use shared tokens and [motion mechanisms](MOTION_AND_FEEDBACK.md) to explain change |

Start from an appropriate theme. `Facet.themes.define` validates a derived
package; `checkCoverage` finds missing theme needs. Apply the package consistently
rather than accumulating instance overrides. Validation does not establish
visual hierarchy or legibility. Shared meanings should remain consistent while
layouts adapt to different tasks.

## Work from structure to detail

Resolve task/flow, information hierarchy and layout before polishing paint and
motion. Define interaction and compact forms while the structure is still easy
to change. Render and operate the result, then revise the highest-impact defect.
These are dependencies, not a rigid production sequence.

## Worked critique: a crowded garage

A large title, equally bright commands and statistics in shifting positions
compete with the chosen object. Give that object and decisive comparison the
focal area; put its named commitment nearby. Distinguish focus, selection and
accepted equipment. In compact form preserve the informed choice through fewer
columns or a detail step, rather than shrinking all text.

## Worked critique: a noisy combat HUD

Individually reasonable alerts can collectively hide survival information.
Test their simultaneous state: protect the world view and immediate response,
defer routine rewards and aggregate repeated gains. Composition priorities need
useful smaller forms. A life-critical command must remain directly reachable.

## Evaluate comprehension and behavior

| Review | Evidence and failure boundary |
| --- | --- |
| Comprehension | Can a new player identify the target, terms, state and next action? |
| Perception | Inspect real backgrounds, viewing distance, expanded text and content extremes; repair unreadable or clipped essentials |
| Operation | Complete, cancel, repeat and recover with supported inputs; repair focus traps, gesture conflicts and accidental activation |
| Adaptation | Perform the same informed task in each meaningful form, including both phone orientations |
| Change and failure | Exercise loading, empty, stale, rejected, disconnected and interrupted states; reject false success, lost drafts and duplicate consequences |
| Coherence | Compare neighboring screens and repeated states for consistent hierarchy, style and motion |

First-use discovery and expert repetition are different tests. Screenshots show
hierarchy and clipping; interaction shows focus and recovery; player observation
reveals misunderstood assumptions. Use task completion, accidental actions,
recovery, unnecessary navigation or focus travel when comparing alternatives
under the same conditions. Do not invent one universal quality score.

## What an agent should deliver with a substantial UI change

Briefly explain the task, attention order, chosen interaction versus its nearest
alternative, compact behavior and commitment/recovery rules. Show representative
rendered evidence and state the input/task paths actually exercised. Identify
defects by state, location, player impact and repair. Recheck task-critical fixes
before optional polish. Guidance coverage and type checks do not prove usability;
report untested behavior as untested.
