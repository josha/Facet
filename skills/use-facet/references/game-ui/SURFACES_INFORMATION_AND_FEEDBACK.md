# Surfaces and feedback

Part of [game UI design](../GAME_UI_DESIGN_GUIDE.md).

A surface is the container a task appears in: a HUD region, a popover, a sheet, a dialog or a page.  Feedback is what the game says after the player acts.  Both follow one rule: take only the attention the decision needs.

## Use the least interruption

Weigh the urgency, the consequence and whether the player must keep watching or controlling the world.  Keep information at its source when that helps the current task.  Take the player's attention only when going on without a decision would cause a real problem.

| Need | Surface |
| --- | --- |
| Optional facts in the reading flow | DisclosureGroup |
| A quick task attached to its source | Popover |
| Guidance on a contextual action | Callout |
| A brief consequential confirmation | Alert |
| A bounded task that owns attention | Dialog or Sheet |
| A destination players return to | A page, from `Tasks.pages` |

Separate required facts from optional detail.  A price, a risk or the reason an action is unavailable never depends on hover.  Progressive disclosure reduces distraction while the next step and its consequence stay in view.  An optional stat breakdown can expand beside an upgrade while its cost and effect stay beside the commitment.

A modal does not pause the game or suppress gameplay commands by itself.  Decide who owns input, show a visible exit and plan recovery.  Do not stack modals to imitate navigation.

## Own presentation and dismissal

Each surface has its own contract.  Read it before you wire dismissal or pending work.

- **Popover.**  Its default `compact = "sheet"` turns an anchored task into a sheet in narrow touch room.  The task keeps a clear title, commitment and exit in either presentation, and durable state stays in the model.
- **Sheet.**  A floating Sheet placed in the center has a visible Close and no grabber.  Docking to an edge suits tasks where resizing or edge dismissal helps.  Leave `closeButton` absent so the exit follows the placement.  Use `hug` for short content, and bound and scroll collections.  Keep actions reachable at every detent.  Sheet actions never close the sheet, so rejected work stays usable.
- **Alert.**  It dismisses before it runs its action.  When the task must stay open for an accepted or rejected request, use a controlled Dialog or Sheet.
- **Dialog.**  It reads `isPresented` and requests changes through `onPresentedChange`; the model accepts or refuses.  Its actions propose closing by default, and `keepOpen = true` suppresses that.

Apply `Sheet.dismissal` to every exit from a dirty task: Close, Back, an outside press, a gesture and any action that leaves.  Do not copy Dialog's action options into a Sheet.

## Explain state where it matters

| Need | Control |
| --- | --- |
| Persistent state | Notice |
| A brief acknowledgement | Toast |
| A compact signal attached to something | Badge or StatusIndicator |
| A meaningful quantity or an unknown wait | ProgressView |
| A deadline | Timer |
| Known structure while content loads | Skeleton |
| A failure while building a region of UI | ErrorBoundary |

Put feedback near the object or action that changed.  Say what happened and what the player can do next.  Match emphasis to urgency, so repeated routine success never competes with danger or with the current decision.  Use a confirmation only when it helps the player understand a choice or avoid a meaningful mistake.  Name the object and the consequence in its action labels.

Keep required consequences available after a toast expires.  Combine repeated gains, and remove messages whose context has ended.  Do not dismiss the only explanation of a blocked action while it is still blocked.  An expiring Undo is never the only protection against serious loss.

Show progress only from a known measure; use an unknown wait when the game cannot measure completion.  A Timer at zero does not authorize a reward or a completion.  Keep loading separate from an empty result.  A retry never creates a second purchase or repeats an accepted action.

ErrorBoundary contains failures while building or updating its region, and its `fallback(failure, retry)` rebuilds that region on retry.  A rejected server request is model state, not a rendering failure.  Show its explanation and recovery through normal bound content, with `Compose.show` or `Compose.switch` when the structure changes.  Keep useful input available in both cases.

## Present content in its frame

Use semantic Text roles, readable contrast and bounded wrapping.  Text and important actions survive missing art, long labels and larger text.  ShortcutHint describes a real binding; it does not create one.

Image and AsyncImage need stable dimensions and a useful failure state.  Create expensive previews only when they help, and keep their space stable while they load.  Stage frames an object at a useful scale, and its inspection input never activates the surrounding item.  AvatarGroup summarizes membership; use a list when players compare individual status.

Any reveal can finish without advancing.  Typewriter, for example, needs a finish action distinct from advancing the dialogue.  Skip and reduced motion still reveal the complete text, and accepted state never depends on the reveal's timing.

## Check

Open each surface from a meaningful source, act, cancel, refuse a request and open it again.  Confirm that the feedback describes the accepted state, the previous task still works, and focus returns to the source or to a useful surviving target.  Change the room and the input while the surface is open.  Test the visible exit and Back in every presentation, including a short viewport with the keyboard open.

Read `Tasks.sheet`, `Sheet.layout`, `Sheet.dismissal`, `Dialog.Dialog`, `Alert.reference` and `Popover.compact` for presentation.  Read `ErrorBoundary.reference` and `Typewriter.reference` for recovery and completion.
