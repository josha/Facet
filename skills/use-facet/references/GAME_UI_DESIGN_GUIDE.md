# Game UI design

Facet supplies reusable behavior. The game supplies purpose and visual character.
Start with the player experience, then choose interaction, composition and controls.
A HUD, contextual choice, planning screen and celebration need different compositions.
Share a visual language without forcing them into one template.

## Principles

- **Serve the player's intent.** Make the situation, choices, action and result understandable. Preserve deliberate game challenge; remove accidental interface difficulty.
- **Direct attention.** Show what changes the next decision. Let urgency, relevance and frequency set priority in the current state.
- **Make the game recognizable.** Use its world, objects and tone to shape art, framing, type and motion.
- **Preserve continuity.** Keep identity, location, useful state and return paths clear as the task changes.
- **Support equivalent tasks.** Adapt to room, reach, input and viewing distance without losing decisions, consequences or exits.
- **Earn trust.** Show what the game accepted. Make commitment, failure, cancellation and recovery predictable.

These principles guide tradeoffs. A calm planning screen can support detailed
comparison; an urgent gameplay decision needs a short glance and direct action.
Consistency means familiar meanings and behavior, not identical layouts everywhere.

## Frame the player task

Before choosing controls, identify the intended experience from the brief and game:

| Decision | What the design must establish |
| --- | --- |
| Player | Prior knowledge, likely goal and access needs |
| Context | Gameplay pace, competing demands, available input and whether the world continues |
| Decision | The facts and alternatives the player needs now |
| Action | Frequency, consequence, reversibility and expected effort |
| Outcome | Visible accepted result, failure response and next useful action |
| Return | Where the player resumes and which state remains |

Keep this brief proportional to the work. Reuse established decisions for a small
change. Ask about missing intent only when it changes the design. Do not invent
extra game systems to fill a screen.

Trace one connected task: entry, orientation, choice, commitment, feedback and
return. Include cancellation and rejection. For example, preparing equipment
starts with a reason to change it and ends with the accepted equipment in play.
Opening a collection alone does not complete that task.

Choose references with a similar task, pace, input and viewing context. Identify
why their grouping, preview or navigation helps the decision. Transfer that
relationship to the game; do not copy a screenshot without its context.

## Organize interaction

Keep these hierarchies distinct and make them support each other:

| Hierarchy | Design question | Visible result |
| --- | --- | --- |
| Task and navigation | Where am I, what can I do, and how do I return? | Clear destinations, peer groups and deeper steps |
| Information and attention | What matters first in this state? | A focal area, supporting facts and quieter optional detail |
| Input and focus | What receives this action, and what is next? | Visible focus, predictable movement and a reliable exit |

A large heading cannot repair a confusing route. A visually prominent action
still needs a reachable focus path. Focus, selection and commitment have distinct
meanings; moving through options must not silently purchase or equip them.

Choose how much attention the task needs before choosing its surface:

| Player relationship | Starting point |
| --- | --- |
| Monitor while playing | Passive Composition Regions and brief readouts |
| Inspect optional context | DisclosureGroup, Callout or Popover |
| Choose a nearby command | Menu or Popover |
| Revisit peer destinations | TabView |
| Go deeper and return | NavigationStack |
| Browse and inspect one object | NavigationSplitView |
| Complete a bounded interruption | Sheet or Dialog |
| Review a brief consequential commitment | Alert |

These are starting points, not fixed screen templates. A persistent destination
usually needs a page or in-world station. Keep a short choice near its source
when it fits; give a sustained task enough room and a clear return path.
Let a dedicated page replace unrelated HUD groups. Keep context needed for its
decision, such as balance beside cost.

Every focus move, menu and confirmation costs attention. Keep frequent safe
actions direct. Add review, deliberate activation or recovery in proportion to
consequence. Disclose optional detail without hiding the terms of commitment.
Avoid using confirmations to compensate for ambiguous labels or adjacent targets.

## Direct attention and express the game

Establish what should be noticed first, second and third in each state.
During play, an immediate hazard can outrank routine gains. During preparation,
object differences can lead. Do not give every message the same visual weight.
Keep required facts visible together instead of making players remember them
across steps. Reduce competing borders and accents before adding decoration.

Choose a coherent palette, type hierarchy, spacing, surfaces, icons and motion.
Express shared values through the theme. Choose the subject that dominates,
a framing or material motif, type contrast and the role of accent.
A field journal might use paper, ink and specimen drawings; a racing garage
might use vehicle silhouettes, technical labels and timing digits.
Carry the visual language through HUD, decisions and results.

Choose composition from the decision. Equipment inspection benefits from a
large object beside comparable facts. A skill tree needs visible connections.
Results can lead with the personal outcome, then gains and standings.
Use a grid when silhouettes help recognition, a list when descriptions matter,
and a table when shared attributes need comparison.

Keep related content close and align comparable facts. Use negative space to
separate groups without surrounding every fact with a box. Reserve strong accent
for the important action or state. Keep stable meanings for color and icons.
Distinguish focus, selection, equipped, pending and unavailable beyond color.

Give objects meaningful artwork or well-framed Stage previews. Show the actual
subject and its distinguishing details. Show a color as a swatch and a pattern
as a preview. Pair unfamiliar glyphs with labels. Test text over busy gameplay
and bright effects; use a backing surface when contrast otherwise fails.

Choose density for the task. Comparison needs enough candidates and facts in
view; action needs brief glances; celebration can give artwork room.
Keep identity, decisive facts and commitment together. Avoid large introductions
or filters that consume the decision area on short screens. Put the selected
object's main action outside a long scrolling collection when appropriate.

Polish includes stable targets and responsive feedback. Hover and focus must
not move neighbors or clip the emphasized object. Motion explains a change and
must preserve the result when reduced or skipped.

## Protect play

Keep the camera's focus area and space covered by a held thumb clear.
Show glanceable information that changes the next action. Put coherent HUD
groups in Composition Regions, with smaller forms and explicit priority.
Keep Region nodes stable; branch inside their forms. A compact form must retain
access to every required task it replaces.

Use safe edges without crowding native controls. Let Composition handle
TopbarInset and its fallback. A world marker can occupy the focus area when
locating that target is the immediate task. Routine status should stay quieter.
End commands and notices when their context ends.

Composition is passive. Gameplay keeps the movement stick and D-pad.
Give HUD tasks explicit gamepad actions and visible input hints. Let the opened
task surface own selection. Choose a useful, safe initial target for that task;
use the control's documented focus policy rather than forcing one rule everywhere.

A page replacing gameplay must own input. Disable the game's gameplay
InputContext and hide custom touch commands while appropriate. Save and restore
GuiService.TouchControlsEnabled for native movement controls. Opening an overlay
does not pause the world. Restore prior input state when the task ends.

## Adapt the task

Available room, physical readability, reach, input precision and gameplay pace
are separate constraints. A high-resolution handheld can need large readable
text and controller navigation in a short layout. A desktop can use a gamepad;
a touch device can have a keyboard. Do not infer all constraints from one label.

Choose layout from usable container bounds, including height and insets.
Choose prompts from the active input and actual bindings. Apply text and access
preferences independently. Keep selection, drafts and location through a resize
or input change. The input chapter maps these decisions to `UI.environment`.

On wide surfaces, show useful browsing and detail together. When they no longer
fit, provide a complete detail step. Reduce decoration, reflow groups and disclose
optional facts before reducing legibility, consequences or exits.
Do not shrink the whole interface to fit an oversized design.

Bound task width before wrapped text or fill collections. Keep short readouts
unwrapped; let explanatory text grow. Test long labels, larger text and missing
artwork. Size short decisions to their content and bound large collections for
scrolling. The layout chapter covers grids that fit their content.

Touch needs reachable targets and movement clearance. Pointer hover cannot hold
required information. Gamepad needs visible entry, predictable focus, scroll
access and Back. Provide digital alternatives to precision gestures.
A displayed shortcut must invoke the same command as its visible control.
Do not bind Roblox's reserved Escape or gamepad Start in game commands.

## Connect design to implementation

Use exact contracts from installed API nodes. Keep one owned tree and use the
nearest existing runtime. Native mechanisms come first, then Compose ownership
and composition, then Facet's task-specific control policy.

| Design responsibility | Mechanism and contract route |
| --- | --- |
| State changes without rebuilding the page | Compose cells and property bindings; `State`, `Types.reactive` |
| Conditional content, stable identity and cleanup | `Compose.show`, `Compose.keyed`, `Compose.cleanup`; Compose consumer skill |
| Overlay ownership | Facet surfaces use Compose lifetime and native input; `Tasks.sheet`, `Sheet.dismissal` |
| Entry, navigation and return | `Tasks.pages`, then the selected navigation control's card |
| Competing HUD groups | Composition and Region; `Tasks.hud`, `Composition.regions` |
| Collection identity and selection | Stable model keys; collection card and `VirtualList-and-VirtualGrid.selection` |
| Game identity and motion | Theme tokens, native StyleSheets and Compose motion; `Tasks.theme`, `Custom-transitions` |
| Accepted game effects | Game/server state bound through Compose; `Tasks.state`, `Tasks.purchase` |

Use controls for their supported behavior. Use Host objects for game art and
scene content. Do not recreate a focus graph, text editor, layout engine or
animation scheduler. Read the control's card, then only the missing options.
A recipe shows a working structure; adapt its content and density to the task.

## Make outcomes truthful

Acknowledge input promptly and distinguish pending, accepted and rejected work.
Sending is not saving. The server owns game rules and accepted progression.
Keep drafts recoverable and use one dirty-dismissal policy for all exit routes.
Preserve query, selection and useful scroll position on return.

Distinguish no items, no matches, loading, unavailable and failed requests.
Offer the matching next step: create, clear filters, wait, explain eligibility
or retry. Pair constraints with their reason and a route forward when one exists.
Test stale data, disconnection and interruption without false success.

Keep important results available after transient feedback ends. Use sound or
haptics to reinforce information, with an equivalent visible signal.
Lead results with personal outcome and accepted gains, then comparison and the
next action. Teach through the actual visible action with Skip and replay.
Do not grant progress because time elapsed or an animation finished.

## Verify the experience early

Build one complete task with representative labels, art and data. Test its most
constrained supported context before repeating the pattern. Include active play,
choice, interruption, failure and return. Read the relevant task chapter below.

Have an unfamiliar player locate the task, predict the action, complete it and
explain the result without coaching. Observe hesitation, wrong turns, repeated
input and missed feedback. Fix the cause, then repeat the affected task.
An agent walkthrough can find gaps; it does not establish player preference.

Inspect captures at intended viewing size for focal order, readable text,
recognizable art and deliberate alignment. Operate the same task with supported
inputs at wide, narrow and short sizes. Change input or viewport while it is open.
Check completion, cancellation, rejection and restoration of input and focus.

Separate technical checks, visual review, input tests and player observations.
Screenshots do not prove reachability; simulated dimensions do not prove handheld
readability. Record the actual build, device, inputs and paths tested.
Fix shared layout or control causes before copying the pattern elsewhere.

## Read only the relevant detail

| Task | Chapter |
| --- | --- |
| HUD, lobby, objectives, results, onboarding | [Game flows](game-ui/GAME_FLOWS_AND_INFORMATION.md) |
| Compact layout and page navigation | [Layout](game-ui/LAYOUT_AND_NAVIGATION.md) |
| Browsing, selection and actions | [Collections](game-ui/COLLECTIONS_AND_ACTIONS.md) |
| Values and editing | [Choices](game-ui/CHOICES_AND_INPUT.md) |
| Interruption and feedback | [Surfaces](game-ui/SURFACES_INFORMATION_AND_FEEDBACK.md) |
| Drag, resize and input alternatives | [Manipulation](game-ui/ADAPTIVE_INTERACTION_AND_DIRECT_MANIPULATION.md) |
| Focus, input ownership and accessibility | [Input](game-ui/INPUT_FOCUS_AND_ACCESS.md) |
| Transitions and reward motion | [Motion](game-ui/MOTION_AND_FEEDBACK.md) |

## Design sources

These sources explain the reasoning. Use the Facet API nodes for implementation.

- Celia Hodent's [game UX practice](https://celiahodent.com/ux-practices-epic-games/) distinguishes intended challenge from interface difficulty. Her [cognitive psychology guide](https://celiahodent.com/cognitive-psychology-applied-to-user-experience-in-video-games/) explains attention, memory and player testing.
- Edd Coates's [Animex talk abstract](https://animex.tees.ac.uk/speaker_page.cfm?speaker=950&year=32) explains why reference analysis must identify design rationale. His [The Game UI Bible](https://www.lostincult.co.uk/shop/p/gameui) is further reading.
- Xbox Accessibility Guidelines cover [navigation](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/112) and [context and consequences](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/114). Apply the principles without treating Xbox button labels as universal.
- Valve's [handheld recommendations](https://partner.steamgames.com/doc/steamhardware/recommendations) and [compatibility guidance](https://partner.steamgames.com/doc/steamhardware/compat) separate controller access and physical readability from resolution. They inform cross-platform review; they are not Roblox requirements.
