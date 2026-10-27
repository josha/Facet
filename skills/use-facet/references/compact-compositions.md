# Compose within narrow and short room

Portrait can support a vertical subject-to-action sequence. Short height often
needs subject and decision side by side, fewer fixed rows, or a separate step.
Use the actual container after native controls, navigation and keyboard. Preserve
world visibility when it communicates identity or the decision; it does not
replace a recognizable subject and clear action.

## Build the first useful view

Render with realistic labels, required controls, data and game art. On entry,
show useful content and the next action without scrolling past setup. Long
catalogs still scroll; not every record must fit at once.

| Task | Portrait allocation | Short-height allocation |
| --- | --- | --- |
| Enter an activity | Compact identity, recognizable selected subject, concise invitation and primary action. Secondary destinations follow or use navigation. | Subject beside invitation/action, or a world-led edge composition. Keep the primary route visible without a tall introductory stack. |
| Browse a collection | One title/Back owner, search plus Filters access, visible records with decisive values. Open the selected detail as a complete step. | A compact search/filter row above useful records. Show a detail step unless both panes leave enough content room. Do not stack every filter above the first item. |
| Inspect or customize | Selected subject followed closely by decisive facts and action; supporting history/choices scroll. Show selected colors or materials visually. | Subject beside a bounded decision column. The inspection example demonstrates this relationship. Do not retain a tall portrait preview above the action. |
| Read a result | Outcome, accepted gains and Continue form the first group. Standings and progression follow in a bounded body. | Outcome/gains beside Continue, with supporting comparison below or disclosed. Do not require a long podium list before reaching the return action. |
| Act during play | Brief readouts, a clear view ahead, controls grouped by simultaneous hand use. | Reduce permanent labels and status rows; keep native movement areas and the subject clear. A touch pad is not a universal pointer/controller form. |
| Learn an action | Callout near the live target with concise lesson and separate step controls. | Compact contextual guidance that leaves the target usable and visible. A floating lesson keeps outer space and footer padding. |

Keep requirements available. Filters uses the same query/category/sort model;
show active filters and result count. Reset/Clear retain their specified meaning.
Price, consequence, pending/error state and required terms stay with the action.

## Allocate the remaining room

Give title and Back one owner: NavBar, page or Sheet header. Measure what remains
after navigation, insets, padding and actions. Width alone cannot establish fit.

For example, a 390-unit-high area with 72 units of top chrome, 56 of actions and
32 of spacing leaves 230 for the task body. A 410-high minimum body cannot fit.
These are not constants to copy. Reallocate structure before reducing text or
targets. Use measured container bounds or complete measurable forms.
`UI.environment(taskBody)` reads an existing GuiObject's size in layout units;
`UI.environment()` reads the camera. Measure the bounded parent that supplies
room, not a hugging child whose size changes with your chosen form. Route:
`environment.environment`.

The [inspection example](../examples/inspection.luau) creates its bounded body
before its panes. Use that body's `viewportHeight` and `viewportWidth` in
record-form formulas.
When a top-art card cannot show its name and decisive values in the remaining
height, try a thumbnail beside those facts. Let column count fall to one when
readable records require it. A virtual collection limits mounted rows; it does
not make a tall row fit. Do not add a permanent Inspect footer when record
activation already opens detail. Keep commitment in that detail step.

Do not force a mid-collection `initialFocus` for every input. It can scroll a
fresh touch browse away from the beginning. Choose focus entry for the active
input; preserve the player's actual key and scroll context on return.

Two possible allocations, not required skins:

```text
PORTRAIT INSPECTION          SHORT INSPECTION
Title / Back                Title / Back
Selected subject            Subject     Name + decisive facts
Name + decisive facts                   Supporting detail scrolls
Supporting detail scrolls               Commit / accepted state
Commit / accepted state
```

A pinned action is useful while its terms and readable content still fit. With
large text or the keyboard, permit an accessible scrolling task surface rather
than overlap or a fixed footer that traps controls.

NavigationSplitView can preserve panes while presenting one compact step;
TabView owns peer selection and adaptive navigation. AdaptiveStack changes a
relationship's axis; it does not decide which facts matter. ViewThatFits needs
bounded, measurable complete candidates; a fill-width candidate always fits.
Use [advanced surfaces](advanced-surfaces.md) for their ownership contracts.

The [collection example](../examples/collection.luau) implements search, type,
sort, active-filter summary, result count, reset and empty recovery. Its bounded
browse keeps search and Filters on one row. Filters opens a separate native
navigation step with Back and Show results, rather than growing above the list.
The retained model keeps query, filters, selection and scroll on return. Wide
records use visual Cards; narrow or short bodies put a thumbnail beside the
name, facts, price and Inspect. Both forms preserve the same decision and model.
Supply the game's records and art; keep commitment in the selected detail.

Opening optional content must give it useful room. In short height, condense the
summary or use a detail step with Back so the requested records are visible.
Disclosure alone does not help if a tall introduction still pushes every record
below the fold. Keep accepted state and a clear route back to the main decision.

## Correct the actual view

Apply the skill's capture correction loop to portrait and short height separately,
on entry and after rotation. The first useful item, recognizable subject and
action with its consequence must survive the smaller form.

Use actual Touch and controller input to confirm native-control clearance,
hold/release/cancel, focus/Back, large text, and rejection. Rotation preserves
selection, drafts and accepted state; unrelated tasks must not inherit scroll
position. Captures do not establish behavior or retained-memory performance.
