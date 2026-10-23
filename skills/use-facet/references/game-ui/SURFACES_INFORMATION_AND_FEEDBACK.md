# Surfaces and feedback

Part of [game UI design](../GAME_UI_DESIGN_GUIDE.md).

## Decide what interrupts

DisclosureGroup expands optional facts in the reading flow. Popover attaches
a quick task to its source. Callout teaches a contextual action. Alert confirms
a brief consequential decision. Dialog or Sheet owns a bounded interruption.
Recurring destinations generally need pages.

A modal does not automatically pause the game or suppress custom gameplay
commands. Define input ownership, visible exits and recovery. Do not stack
modals to simulate navigation.

For a floating Sheet, center placement has a visible Close and no grabber.
Edge docking serves tasks where resizing or edge dismissal helps. Leave
closeButton absent to let the exit follow placement. Use hug for short intrinsic
content; bound and scroll collections. Keep actions reachable at every detent.
Apply Sheet.dismissal to all dirty exits. Pinned actions do not close it
automatically; rejected work must remain usable.

Alert dismisses before invoking its action. Use a controlled Dialog or Sheet
when the task must remain open for an accepted or rejected request. Read the
chosen contract before wiring dismissal or pending behavior.

## Explain state where it matters

Use Notice for persistent state, Toast for a brief acknowledgement, Badge or
StatusIndicator for a compact attached signal. Keep required consequences
available after a toast expires. Aggregate repeated gains and remove messages
whose context no longer applies.
Do not dismiss the only explanation for a blocked action while it remains
blocked. An expiring Undo must not be the only way to prevent serious loss.

ProgressView shows a meaningful quantity or unknown wait. Timer displays a
deadline; zero does not independently authorize rewards or completion.
Skeleton reserves known loading structure. ErrorBoundary offers recovery
rather than leaving a partial interactive screen.

## Give content an intentional frame

Use semantic Text roles, readable contrast and bounded wrapping. Text and
important actions must survive missing art, long labels and larger text.
ShortcutHint describes an actual binding; it does not create one.

Image and AsyncImage need stable dimensions and a useful failure state.
Stage should frame the object clearly at a useful scale; inspection controls
must not also activate the surrounding item. AvatarGroup summarizes membership;
use a list when players must compare individual status.
Use a static image when it conveys the same decision at lower cost. Create
expensive previews only when useful; keep stable space while they load.

Typewriter needs a finish action distinct from advancing dialogue. Reduced
motion and Skip still reveal the complete result. Keep accepted state
independent of presentation timing.
