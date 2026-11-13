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

The order is: the concept, the measured card, the style on one sheet, the
first playable screen, the remaining routes. Each step ends with a result
that you can observe, and each later step is built from the one before it.

A brief that asks for an established look, a quiet tool that keeps the
conventions of its host and a small edit to an interface that exists start
at step 4: reuse the decisions that exist. A product with one form factor
and one input captures that form only.

1. **The concept.** A precise reference from the user, such as a screenshot
   or a chosen concept, is the target: match it, and go to step 2. A
   conceptual reference, such as a mood, a genre or a named inspiration, is
   a direction: keep what makes it recognizable and improve on it. With no
   reference, make one. Write the direction in a few lines. Then make a
   picture of the screen that the player sees most, which for a game is
   play with its interface over it. With an image tool, generate two or
   three whole-screen compositions and choose one. Give sizes and strengths
   as quantities; a prompt that asks for restraint gets a plain screen. The
   same tool can make art for the game, one file for each use, when the
   Studio connection uploads the file; say so in one message when an upload
   is refused, and carry on without it. Without an image tool, block the
   screen in: its ground, its main subject at its size and its main action,
   with fixed sample data and no game logic, and capture it. In a 3D game
   the ground is the world: its sky and its light belong to the picture, and
   the sky that the engine starts with is no direction. This picture is the
   first capture of the work, and it comes in the first few minutes. Change
   the composition until it is strong, and say in one message what you
   chose.
2. **The measured card.** The picture that you chose, or the precise
   reference, is now the target. Write its measures against the screen in
   about ten lines at the head of the style source: the size of the largest
   number, the share that the main subject takes, the width and the
   brightness of the edges, the shape of a surface and of a control, and
   where the main action sits and what makes it the strongest thing near
   it. A line with an adjective where the picture shows a size is not
   finished. Build to these lines.
3. **The style on one sheet.** Build the style or theme from the card, and
   look at it alone before a screen uses it: its type sizes, its actions in
   each state and one record on a single sheet, with no game logic. Compare
   the sheet with the concept by measure, at the same size. Compare the
   levels too: the surface that leads keeps the strongest edge, and the
   controls inside it are quieter, as far as the concept shows. Change the
   style until the two agree, and say what you measured and what you
   changed.
4. **The first playable screen.** Read the required guidance and the task
   chapters for the first route. Resolve unfamiliar library options from
   their public contracts. Build one small complete route on the screen of
   the concept, with the style from step 3: enter from gameplay, use normal
   player input, observe the actual game effect and accepted result, and
   return. Include the server behavior that makes the result real. An open
   page, a changed label or a successful tool call does not prove this
   route. For a game, this screen is play with its interface over it; a
   sheet that opens over play does not stand in for it. When the product
   also has destinations that cover or replace play, finish one of those in
   the same way afterwards. Then finish the screen before you build the
   interface of a second route: its composition, subject treatment, type
   hierarchy and action emphasis, with representative data, and the parts
   that later routes will call: one record, the actions and the body of a
   page. Those parts draw every later route, so a plain part makes every
   route plain. Capture one revision at each supported form: wide, narrow
   and short. A phone brief covering both orientations needs both portrait
   and landscape here; one compact preset cannot prove both. Repair what
   the captures show, then check the screen with controller-only focus when
   a controller is supported. Then put the concept beside the wide capture
   at the same size and state in one message, one line each, what the
   captures show of the ground, the main subject, the type, the edge of the
   surfaces and the main action, and what the build lost from the concept.
   A line that you cannot point to in a capture is work to do before the
   next route. This step is not polish: a fault left here is repeated in
   every later route.
5. **Every remaining route has an entry and a result.** Give each remaining
   required route a minimal working entry and result before you deepen a
   route that already works. Build each from what the first screen settled,
   with a composition suited to its task. Do not pour every route into one
   page layout.
6. **Deepen and verify.** Add features in small groups and verify their real
   effects after each group. Check choices and progression in the later tasks
   that consume them. Keep the place working after each group of changes.
   Leave time for the end: after the last change, capture the main screen
   again at each form and repair what a late change broke.

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
