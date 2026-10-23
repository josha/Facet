# Surfaces and feedback

Part of [game UI design](../GAME_UI_DESIGN_GUIDE.md).

## Decide what interrupts

Use the least interruption that makes the decision clear. Consider urgency,
consequence and whether the player must keep watching or controlling the world.
Keep information at its source when it helps the current task. Take attention
only when proceeding without a decision would create a meaningful problem.

DisclosureGroup expands optional facts in the reading flow. Popover attaches
a quick task to its source. Callout teaches a contextual action. Alert confirms
a brief consequential decision. Dialog or Sheet owns a bounded interruption.
Recurring destinations generally need pages.

Separate required facts from optional detail. A price, risk or reason an action
is unavailable must not depend on hover. Progressive disclosure should reduce
distraction while keeping the next step and its consequence discoverable.
For example, an optional stat breakdown can expand beside an upgrade, while
its cost and effect stay beside the commitment.

A modal does not automatically pause the game or suppress custom gameplay
commands. Define input ownership, visible exits and recovery. Do not stack
modals to simulate navigation.

Popover's default `compact = "sheet"` adapts an anchored task for narrow touch
room. Use the control's route change and keep durable state in the model.
The same task needs a clear title, commitment and exit in either presentation.

For a floating Sheet, center placement has a visible Close and no grabber.
Edge docking serves tasks where resizing or edge dismissal helps. Leave
closeButton absent to let the exit follow placement. Use hug for short intrinsic
content; bound and scroll collections. Keep actions reachable at every detent.
Apply Sheet.dismissal to all dirty exits. Pinned actions do not close it
automatically; rejected work must remain usable.

Alert dismisses before invoking its action. Use a controlled Dialog or Sheet
when the task must remain open for an accepted or rejected request. Read the
chosen contract before wiring dismissal or pending behavior.

Dialog reads `isPresented` and requests changes through `onPresentedChange`;
the model accepts or refuses the request. Its actions propose closure by
default; `keepOpen = true` suppresses that proposal. Sheet actions never close
the sheet. Use `Sheet.dismissal` for its guard instead of copying Dialog's
action options. Keep one dismissal policy for Close, Back, outside presses,
gestures and actions that leave a dirty task.

## Explain state where it matters

Use Notice for persistent state, Toast for a brief acknowledgement, Badge or
StatusIndicator for a compact attached signal. Keep required consequences
available after a toast expires. Aggregate repeated gains and remove messages
whose context no longer applies.
Do not dismiss the only explanation for a blocked action while it remains
blocked. An expiring Undo must not be the only way to prevent serious loss.

Put feedback near the object or action that changed. State what happened and
what the player can do next. Match emphasis to urgency; repeated routine
success should not compete with danger or the player's current decision.
Use a confirmation only when it helps the player understand or prevent a
meaningful error. Name the object and consequence in its action labels.

ProgressView shows a meaningful quantity or unknown wait. Timer displays a
deadline; zero does not independently authorize rewards or completion.
Skeleton reserves known loading structure. Keep loading separate from an
empty result. Show progress only from a known measure; use an unknown wait
when the game cannot measure completion. Retrying must not create a second
purchase or repeat an already accepted action.

ErrorBoundary contains failures while building or updating its UI region.
Its `fallback(failure, retry)` rebuilds that region when retried. A rejected
server request is model state, not a rendering failure. Show its explanation
and recovery through normal bound content, using Compose.show or Compose.switch
when the structure changes. Keep useful input available in either case.

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

## Verify interruption and return

Open from a meaningful source, act, cancel, reject a request and reopen. Check
that feedback describes the accepted state, the previous task remains usable,
and focus returns to the source or a useful surviving target. Change room and
input while the surface is open. Test the visible exit and Back in every
presentation, including a short viewport with the keyboard open.

Read `Tasks.sheet`, `Sheet.layout`, `Sheet.dismissal`, `Dialog.Dialog`,
`Alert.reference` and `Popover.compact` for presentation ownership. Read
`ErrorBoundary.reference` and `Typewriter.reference` for their recovery and
completion contracts.
