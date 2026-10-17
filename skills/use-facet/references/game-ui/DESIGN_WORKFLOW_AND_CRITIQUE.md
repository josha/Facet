# Design workflow and critique

Part of [Designing game interfaces with Facet](../GAME_UI_DESIGN_GUIDE.md). Knowing the available components does not determine a good composition. Use a deliberate process to turn player needs into a coherent screen, then judge the actual result.

## Establish the design brief

Before a substantial new screen, write a short brief with these answers. For a small repair, record only the relevant decisions.

| Question | Useful answer | Unhelpful answer |
| --- | --- | --- |
| What can the player accomplish? | Compare two eligible vehicles and equip one for the next race | Display vehicle data |
| What is happening around the UI? | The player is stationary in a garage; the next match can become ready | It is a menu |
| What must be understood before action? | Eligibility, meaningful performance differences, cost, and equipped state | All available metadata |
| What should be noticed first, second, third? | Selected vehicle; decisive differences; Equip | Everything should stand out |
| What visual character belongs here? | Precise instrument-like values, restrained framing, one energetic accent | Modern and polished |
| What is the smallest complete form? | One candidate, current-versus-candidate comparison, and a reachable commitment | A scaled-down wide screen |
| What would prove the design wrong? | Players mistake selection for equipment or cannot explain the cost | Someone dislikes the color |

Name the primary action and the nearest competing action. If there are several equally urgent actions, state why they must remain peers. Decide the intended pacing: glance, quick choice, sustained comparison, or expressive moment.

## Design the content and flow before the surface

Write real labels and representative values early. “Item name” and “Lorem ipsum” hide identity, length, and hierarchy problems. Include a long name, a missing image, a large total, and a meaningful error. Separate the record's identity, its current state, its comparison facts, and its commands.

Sketch the shortest complete task path, including return and recovery. Decide what stays on one screen and what deserves a separate destination. Prefer a coherent step with the information needed to act over several tiny steps that force the player to remember previous values.

For a major decision, compare two plausible structures before committing. A grid with detail may serve recognition; a table may serve stat comparison. Judge them using the player's question, target visibility, number of necessary transitions, and compact behavior. Do not select the layout solely because it resembles a familiar genre screen.

## Establish a visual system that can survive content

Create one representative screen and a small state specimen containing a heading, body text, number, field, selected object, focused object, primary/secondary/destructive actions, and a pending/error state. Test the same language over a quiet surface and a busy game scene before spreading it across the game.

| Design decision | What to establish | Facet expression |
| --- | --- | --- |
| Typography | A clear scale, readable body text, consistent numeric treatment, restrained emphasis | Semantic `textRole` and theme typography; reserve fitted text for suitable bounded values |
| Spacing | A repeated rhythm with tighter within-group and larger between-group separation | Theme spacing, `gap`, `padding`; shared alignment through stacks/grids/tables |
| Surfaces | Which areas are world, task, object, and overlay | Screen, Card, pane/panel treatments, modal surfaces; avoid arbitrary nested boxes |
| Color | A small set of functional meanings plus identity colors | Semantic palette roles; distinguish focus, selection, danger, and success with more than color |
| Shape and art | A consistent family with room for varying text and states | Shared theme chrome/skin and content insets; preserve intrinsic content space |
| Action hierarchy | One clear principal command per decision area and quieter supporting verbs | Button appearances and roles; Menu for genuinely secondary actions |
| Focus and state | Visibly distinct focused, selected, equipped, locked, and pending treatments | Theme focus chrome, selected paint, status/labels, enabled/busy states |
| Motion | A consistent rhythm from immediate feedback to deliberate celebration | Shared motion tokens and the [motion mechanisms](MOTION_AND_FEEDBACK.md) |

Begin from an appropriate existing theme and change it deliberately. `Facet.themes.define` validates a derived package and returns a report; use a valid package consistently through the app rather than overriding individual instances until their states disagree. `checkCoverage` can identify missing theme needs. A valid theme is a technical starting point: it does not establish good hierarchy, appropriate density, or legibility over every actual background.

Reserve strong accent for a purpose. If the game's identity color is used on every surface, it cannot also uniquely signal the main action. Decoration can live in artwork, edges, material, or motion while readable content retains a calmer field. Consistency does not mean every screen has the same layout; it means the same visual differences carry the same meanings.

## Work from structure to detail

Use this order so polish does not conceal a poor foundation:

1. **Task and flow:** confirm the entry, decision, commitment, result, and return.
2. **Content hierarchy:** allocate attention and choose which facts need simultaneous visibility.
3. **Layout:** choose containers, alignment, readable widths, bounded scrolling, and protected world space.
4. **Interaction:** define selection, activation, editing, focus, cancellation, and input alternatives.
5. **Adaptation:** author rich/compact/minimum forms and meaningful routes to omitted content.
6. **Visual expression:** apply the shared type, color, shape, artwork, and state treatments.
7. **Feedback and motion:** add only effects that reinforce an already understandable relationship.
8. **Rendered evaluation:** inspect and operate the full task, then repair the highest-impact defects.

Iterate between these stages when evidence requires it. A strong illustration may influence layout, and a touch test may change an interaction. The order is a way to expose dependencies, not a rule to finish one stage forever before starting another.

## Worked critique: a crowded garage

Suppose a garage shows a large decorative title, six equally bright action buttons, stacked vehicle cards containing the same statistics in different positions, and a floating Equip button in a corner. Selection is only a border color. On a narrow screen, all text shrinks.

| Observed defect | Why it harms the task | Repair and Facet mapping |
| --- | --- | --- |
| The title is the first thing noticed; the candidate is unclear | Attention goes to a label rather than the decision | Reduce title prominence; give selected identity and decisive facts the focal area |
| Every command looks primary | Players must re-evaluate which action progresses the task | Emphasize Equip, keep Compare direct if frequent, move Duplicate/Rename and rare commands into an object Menu |
| Statistics move between cards | Comparing requires repeated search and memory | Use a shared Table or a stable current-versus-candidate comparison |
| Equip is spatially detached from the vehicle | The action's target is ambiguous | Put the named commitment beside the selected candidate and its eligibility/cost |
| Focus, selection, and equipped state look identical | Navigating appears to change equipment | Keep a focus ring, selected-candidate treatment, and explicit Equipped label distinct |
| Narrow mode shrinks everything | Content technically fits while the task becomes unreadable | Use one-pane NavigationSplitView behavior, fewer grid columns, and a compact comparison retaining decisive attributes |

The repair is not “use more Facet controls.” It changes the information relationships and expresses them through the appropriate controls. A successful compact version may show fewer facts at once, but it must still let the player make the same informed choice.

## Worked critique: a noisy combat HUD

A low-health warning pulses, currency counts upward, quest completion expands, and an achievement crosses the center while an ability wheel covers the target. Each effect is defensible in isolation; together they compete with survival.

Protect the world view and the immediate response first. Keep health's current value legible with a brief loss trail, show the urgent direction/action, and defer routine rewards. Give Composition regions priorities and useful smaller forms. Keep a life-critical ability direct instead of placing it behind a modal wheel. Combine repeated gains into a quiet total and let an appropriate post-action moment carry the celebration. Test the worst simultaneous combination, not four isolated screenshots.

## Evaluate comprehension and behavior

Review in layers. Do not polish a border while the primary action is unreachable.

| Review layer | Evidence to collect | Failures that require repair |
| --- | --- | --- |
| Comprehension | Ask an unfamiliar player what is happening, what is selected, and what happens next | Incorrect target, unclear cost, mistaken state, unknown next action |
| Perception | Inspect real backgrounds, intended viewing distance, expanded text, and content extremes | Unreadable text, lost focus, clipped essential facts, ambiguous color-only meaning |
| Operation | Complete, cancel, repeat, and recover through supported inputs | Focus trap, gesture conflict, accidental activation, inaccessible alternate route |
| Adaptation | Perform the same task in each meaningful form | Compact mode removes required information or changes semantics unexpectedly |
| Change and failure | Trigger loading, empty, stale, rejected, disconnected, and interrupted states | False success, lost draft, duplicate command, unreachable recovery |
| Coherence and character | Compare neighboring screens and repeated state treatments | Conflicting action hierarchy, unrelated visual styles, arbitrary motion |

Observe first-use mistakes and expert repetition separately. A hidden shortcut can make expert use fast while the primary task remains undiscoverable. Useful measures include task completion, accidental actions, recovery success, unnecessary navigation, time to a meaningful decision, and focus moves for repeated work. Choose thresholds from the task's demands and compare alternatives under the same conditions; do not invent one universal number for “good UI.”

A brief exposure can test what attracts attention; a full task tests whether the flow works. Neither proves the other. Screenshots reveal clipping, hierarchy, and visual coherence. Interaction tests reveal focus, gesture, commitment, and recovery problems. Player observation reveals assumptions the author no longer notices.

## What an agent should deliver with a substantial UI change

Keep the design rationale short and specific: the player task, intended attention order, chosen interaction versus its nearest alternative, compact behavior, and important commitment/recovery rules. Include representative rendered evidence and explain which input/task paths were actually exercised.

Report untested behavior as untested. A coverage index proves that guidance exists; types prove a narrower form of correctness; neither proves that the UI is enjoyable or understandable. Identify defects by state, location, player impact, and repair. Finish the task-critical repairs before optional polish, then inspect the changed state again.
