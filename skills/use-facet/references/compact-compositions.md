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

For a world-led hub, keep related actions in one bottom Composition group
above native movement controls. For a live readout, give deciding values
enough type size and limit competing accents. Keep brief guidance visible
near its target. State affordability, unsaved changes, confirmation terms
and the accepted result in words when they affect the decision. These are
task conditions: a text-led record browser or a plugin tool can use its
existing navigation and a quiet, dense layout instead of a gameplay HUD.

## Allocate the remaining room

During time-critical world interaction, keep permanent HUD content limited to
the current decision, progress and usable commands. Show other resources when
they affect an action or in a destination page. Check the view ahead and world
nameplates at short heights. Move or hide optional regions when they cover
those subjects. Composition fits its own regions; it does not project or avoid
arbitrary BillboardGui nameplates. The game owns that visibility decision.
This advice applies to overlays during play. A text-led task, a quiet status
tool or a plugin can keep persistent facts when users need them.

Give title and Back one owner: NavBar, page or Sheet header. Measure what remains
after navigation, insets, padding and actions. Width alone cannot establish fit.

Keep side-by-side panes only while both can hold their required content at the
chosen text scale and input target size. Their minimum usable widths plus the
gap must fit the body; their required heights must fit or have useful scrolling.
If that relationship fails, reflow into a vertical sequence or a separate
detail step using the same selection and draft. Choose the boundary from these
content needs, not a fixed desktop aspect ratio or a device name. A narrow
table or tool can retain columns when they remain readable and usable.

Plan the compact header and body separately. A wrapping title must not run
under a fixed settings button, and a shorter preview must still show the
subject's distinguishing details. Reuse the visual language across forms;
the portrait form need not keep the desktop panel arrangement.

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

NavigationSplitView can preserve panes while presenting one compact step.
For list and detail tasks, read `Tasks.collection-detail` and `Collection-layout`
with the docs command or FacetDocs search. These routes work in exported skills.
Put long facts and the action in the detail ScrollView. A fill preview in a
hugging page does not prevent facts below it from leaving the viewport.
Keep search and Filters on one row when permanent filters crowd out records.

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

## Verify the minimum viewport

Before the first runtime review, record the supported width and height limits
for each orientation. Use the product's existing limits when available. For
unspecified phone support, test the smallest phone preset available in the
host in both orientations, plus a notched preset when its insets impose a
different constraint. Record these as provisional tested limits, not proof
for every phone. If the host cannot reach the product's minimum, name the gap.
Do not raise a support limit after a failure merely to make the test pass.
For a resizable desktop or plugin, use its minimum supported container size;
phone tests do not apply to a desktop-only tool.

Record the actual camera viewport, mounted safe rectangle, task-body size,
UI scale, text preference and received input. Preset names and screenshot
pixel dimensions can differ from the space the UI actually has. Measure after
insets, headers, padding, actions and native target floors are applied.
Check both sides of a responsive boundary changed by the implementation.

For supported console use, also record the resolved viewing-distance context
and effective styled text sizes. Inspect opened details, history and dialogs at
the same viewing scale as the main screen. A console preset, controller focus
or large button target does not establish readable text. Keep near-view desktop
typography when a controller is attached at a desk; a desktop-only tool does
not need a television layout.

At each minimum, open the task normally and inspect its initial view, longest
supported content, opened controls or confirmation, changing feedback and
return. Include the largest supported text preference. Check the complete
painted bounds of labels, actions and focus/selection treatments, including
the left and bottom edges of dialogs. A button center inside the viewport
does not prove its target or outline fits. Account for clipping ancestors
and art insets; separate object bounds can still overlap in their paint.

Activate the main action and exit with actual supported input. If a route
depends on scrolling, perform the scroll from entry, reveal the whole target
and its required terms, then activate it. Do not infer a reachable action from
the existence of a ScrollView, assign focus as navigation proof, or call its
callback. Keep commitment outside a long catalog when the task needs it
continuously available. A deliberately scrolling detail step remains valid.
An in-view center that accepts input does not excuse clipped content.

Rotate the open task to its other supported orientation and back without
remounting or resetting it. Verify the same selection, draft, accepted state
and useful scroll context, then use the action and return route again. Check
focus separately from persistent selection when controller input is supported.
After a padding, text, footer or layout repair, repeat the affected states at
both minima and the adjacent layout. Earlier captures do not verify new source.

Missing minimum-size captures or real-input routes leave device fit unverified,
even when larger presets and static checks pass. Report exact tested limits
and remaining gaps. Studio emulation does not prove physical-device readability
or touch ergonomics.

## Correct the actual view

Apply the skill's capture correction loop to portrait and short height separately,
on entry and after rotation. The first useful item, recognizable subject and
action with its consequence must survive the smaller form.
Check the task's changed layouts as well as its opening view, including any
confirmation, accepted feedback and return at the largest supported text size.
Check these forms before copying the composition into other tasks. A later
capture of the old source does not establish an early compact review.

Use actual Touch and controller input to confirm native-control clearance,
hold/release/cancel, focus/Back, large text, and rejection. Rotation preserves
selection, drafts and accepted state; unrelated tasks must not inherit scroll
position. Captures do not establish behavior or retained-memory performance.
