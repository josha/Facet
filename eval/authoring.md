# Studio author workflow

Use this workflow within the supplied tool boundary. It does not change the
product requirements. Make persistent
changes in Edit and test them in Play. Keep supplied libraries and documents
unchanged.

Plan the brief as connected player routes. Identify each route's entry, shared
state, accepted game effect, cancellation or failure, and return. Track the
required routes that remain incomplete. A missing route is not offset by polish
elsewhere. Fix a defect that blocks later routes first.

## Order of work

Do these in order. Each one ends with a result that you can observe.

1. **One route works.** Read the required guidance and the task chapters for
   the first route. Resolve unfamiliar library options from their public
   contracts. Build a small complete route before expanding features: enter
   from gameplay, use normal player input, observe the actual game effect and
   accepted result, and return. Include the server behavior that makes the
   result real. An open page, a changed label or a successful tool call does
   not prove this route.
2. **Its screen is finished.** For a new visual direction, finish the look of
   that one route before you build the interface of a second route: its
   composition, subject treatment, type hierarchy and action emphasis, with
   representative data. Capture it at each supported form: wide, narrow and
   short. A phone brief covering both orientations needs both portrait and
   landscape here; one compact preset cannot prove both. Repair what the
   captures show, then check the screen with controller-only focus when a
   controller is supported. This step covers one screen. It is not polish:
   every later route copies what this screen settles, so a fault left here is
   repeated in each of them. A theme definition alone does not complete it.
   The screen can be resolved with static data before step 1; static data
   does not count as the accepted game effect. Skip this step when the brief
   asks for an established look or supports one form factor and one input.
3. **Every route has an entry and a result.** Give each remaining required
   route a minimal working entry and result before you deepen a route that
   already works. Build each from what the first screen settled, with a
   composition suited to its task. Do not pour every route into one page
   layout.
4. **Deepen and verify.** Add features in small groups and verify their real
   effects after each group. Check choices and progression in the later tasks
   that consume them. Keep the place working after each group of changes.

## Checks

- Check unfamiliar native constructors, datatype operations and members with a
  small native probe in the intended data model before using them in shared
  code.
- Start Play after the first persistent implementation. Check Client and Server
  errors and the current camera's `ViewportSize`. If the camera stays absent or
  at 1 by 1, report unavailable native rendering separately from game failures.
  Request a capture when rendering is ready. Inspect the returned image at its actual size.
  A text response, object bounds or an image from an earlier state does not
  verify the current appearance. Keep a coherent visual language across the world
  and UI. Check the main subject, next action, readable terms and gameplay
  clearance. Revise weak composition before adding decorative detail.
- Fix the persistent source, restart Play and repeat the affected route. Check
  normal completion, cancellation and return, including input and focus.
  Repeat representative routes with each required input and layout, including
  a live viewport change. Keep decisions, consequences and exits usable.
- A check covers only the code that ran. A syntax check does not run a branch,
  and a branch that needs data does not run on an empty state. After a change
  to code that several routes share, repeat each state that uses it with data
  that enters the changed branch.
- For controller-only focus, switch the device preview to a console. Injected
  arrow keys stand for the D-pad and Return stands for the A button. When
  nothing is selected, `GuiService:Select(playerGui)` stands for the first
  press. Send one key after a change of device before you select; the first
  injected key can clear the selection. Read `GuiService.SelectedObject`
  after each move. Check the first directional move, an activation and the
  return on each kind of surface, in a fresh Play session after a change to
  focus or input ownership. Keys reserved by Roblox core UI, such as Tab and
  gamepad B, cannot be injected with VirtualInput.
- The place uses the native input action system, and no PlayerModule control
  script runs in PlayerScripts. Read player movement from
  `StarterPlayer.PlayerModule.InputContexts.CharacterContext.MoveAction`
  (Direction2D) with `GetState()`; it keeps reporting while the character is
  seated. Camera and vehicle contexts sit beside it.
- If a tool times out, its action may still have occurred. Inspect state before
  repeating an action. If capture remains unavailable, do not claim visual
  review or spend the remaining attempt on identical retries. Continue useful
  functional checks and repairs with available tools. Report the missing visual
  evidence; do not assume access to tools outside the supplied boundary.
- Stop only when every requirement in the brief works or no useful work can
  proceed with the available tools. Before finishing, check the persistent
  result in a fresh Play session. State which routes you actually operated,
  what failed, and what remains untested or incomplete. Keep implementation,
  functional testing and visual review distinct. A normal author exit is not
  proof that the game meets the brief.
