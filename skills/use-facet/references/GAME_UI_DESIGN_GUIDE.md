# Designing game interfaces with Facet

An interface succeeds when players understand the situation, choose, act, and
recognize the result. Its visual character should belong to the game. Design
the complete task, including return and failure, before choosing controls.

These foundations are required reading. For a new screen, also read the
[design workflow](game-ui/DESIGN_WORKFLOW_AND_CRITIQUE.md). Read the task
chapters needed for the decisions you are making; do not load the full guide.
[Detailed foundations and worked examples](DESIGN_FOUNDATIONS.md) explain
these principles further when a design tradeoff remains unclear.

## Start with the player's next decision

Name the situation, decision, action, and visible result. State whether the
world continues while the task is open. For example: compare a vehicle with
the equipped vehicle, choose it for the next race, and show the confirmed
loadout. This defines the information and behavior; it does not yet require
a grid or a modal.

Match the interface to its pace. Driving needs stable, glanceable information
and immediate controls. Loadout planning needs comparison and deliberate
commitment. Results need outcome, explanation, rewards, and a next action.
Social actions must identify the recipient and distinguish pending from sent
or accepted. One game can need all of these forms.

## Establish an attention order

For each important state, decide what should be noticed first, second, and
third. Judge the rendered screen against that order. Group an object's cost,
state, and action together. Use alignment, spacing, scale, contrast, and motion
to express those relationships.

Protect the road, aiming area, hazards, characters, and other required sight
lines. Fingers and controls also occupy space. A modal sets input ownership;
the game still decides whether movement stops. Do not cover an urgent action
with a reward, instruction, or purchase offer.

Use safe screen edges deliberately; reserve the center for play. The top-right
area below the engine top bar is a useful home for secondary destinations such
as Garage, Shop, and Menu when it clears the game's sight lines. Keep the group
inside device and TV safe areas. On narrow screens, reduce it to a reachable
Menu that preserves every destination. Empty space is useful when it protects
gameplay; do not fill every edge merely because room is available.

Use stable widths and record identities for live values. A changing balance
must not move Buy under the player's finger. Preserve selection and focus
when rows update. Emphasize meaningful changes briefly, then let the UI settle.

## Make the visual language coherent

Choose a small shared visual system: palette roles, type hierarchy, spacing,
surfaces, shapes, icons, and motion. Express the game's character through
deliberate typography, artwork, material, and feedback. Avoid a separate style
for every page. Use a backing where gameplay cannot provide reliable contrast.

Give each visual difference a meaning. Focus, selected, equipped, unavailable,
pending, and confirmed are different states. Color alone cannot carry a
required distinction. Keep supporting text readable; shrinking text is not
a substitute for arranging content.

Beauty depends on composition as well as controls: a clear focal area,
intentional proportions, consistent reading edges, and space between distinct
groups. Remove decoration that competes with the player's decision.

## Choose what survives when space runs out

Design the narrow form as a complete way to perform the task. Wider forms
should expose useful context and reduce navigation.

| Information | Space priority |
| --- | --- |
| Needed for an immediate action or consequence | Keep a usable visible form |
| Needed before commitment | Keep with the decision, possibly in a detail step |
| Useful on demand | Provide a named route or a meaningful summary |
| Decorative | Remove before sacrificing controls or legibility |

Reduce decoration, reflow groups, shorten summaries, then move optional detail.
Never silently lose a task, its terms, the selected object, or an exit.

Use one `Composition` for competing HUD groups and a `Region` for each group.
Lower `rank` numbers have priority. Supply measurable forms from richest to
smallest; rank alone cannot make an oversized form fit. Use a numeric or hug
width for a region form, not a fill width that depends on the space being
measured. Let Composition choose forms instead of adding another device switch.

The smallest form must preserve access to omitted tasks. A passive summary
can use the region's built-in reveal. An interactive Menu button owns its
press and must open the omitted choices. Use `mayDrop` only when the task can
safely wait or has another usable route. Fix fit warnings rather than scaling
the entire screen down.

## Choose controls by behavior

| Player need | Starting choice |
| --- | --- |
| Read sections in order | VStack; HStack for one compact horizontal group |
| Browse repeated objects | VirtualList or VirtualGrid, with stable model keys |
| Compare shared attributes | Table; Outline only for a real hierarchy |
| Choose a value | Picker or an input control |
| Perform a command | Button; contextual Menu for secondary commands |
| Move between peer tasks | TabView |
| Open deeper task detail | NavigationStack or NavigationSplitView |
| Expand optional facts in the flow | DisclosureGroup |
| Show content anchored to an object | Popover |
| Temporarily own attention for a task | Sheet; choose centered or docked placement deliberately |
| Read amount, time, status, acknowledgement | ProgressView, Timer, Badge/StatusIndicator, Toast |

Compare the nearest alternatives. A setting is a value, not a navigation tab.
A contextual command set is not automatically a modal. Use selection for an
object under consideration; do not equip or buy it merely because it gained
focus. Expose frequent important actions directly.

Size the surface and its content together. A short task can fit its content;
a browsing task should use the available room for its collection. Avoid a large
surface around a short, fixed-height list. Reuse item components without forcing
every task into the same layout.

A temporary task does not imply a draggable surface. For a floating task
panel, use Sheet with `placement = "center"`: Close is visible and there is
no grabber. Dock at an edge when drag resizing or edge dismissal helps the
task. Use one visible exit: a grabber or Close. Leave `closeButton` absent so
Facet can change that exit with placement. Use one `hug` detent for a short
intrinsic body; use a bounded height and scrolling for a collection. Hover,
press and focus feedback must not resize the surface or move nearby targets.

Establish width at the task boundary. A stack that contains a collection or
wrapped task text should fill its bounded surface, for example
`UI.VStack { width = "fill", ... }` inside a Sheet. Stacks hug by default;
a fill-width child inside a hugging stack does not establish the available
width. Use hugging stacks for short readouts and command groups inside that
bounded task body.

Do not place several full-width fields in a hugging horizontal stack. Arrange
them vertically or allocate their share of a bounded row. Keep secondary
filters compact so the objects being chosen remain the focal area.

Use Facet controls for their supported behaviors. They share theme, metrics,
input, focus, and fixes. Use Stage for 3D previews, with native `Host` objects
for its scene content, game art, or minimaps. Reuse a component pattern across similar tasks, with
the game's model supplying data and commands.

## Adapt to input and viewing conditions

Available space, input precision, viewing distance, and gameplay pace are
separate constraints. Adapt from actual room and environment facts, not a
device name. An input hint can change without rearranging the whole screen.

- Touch: preserve usable targets and separation. Test finger occlusion and
  competing gestures. Essential actions cannot depend on hover or precise drag.
- Pointer and keyboard: provide discoverable actions as well as shortcuts.
  Text entry and menus must not trigger gameplay commands underneath them.
- Gamepad: make focus visible, traversal predictable, and Back reliable.
  Preserve the selected object and restore focus on return. Provide digital
  routes for required operations, including alternatives to analog dragging.
- Distance and accessibility: use readable type, safe margins, clear focus,
  preferred text size, localization, and reduced motion. Reflow longer content.
  Do not make color, sound, vibration, animation, or a precise gesture the only
  way to understand or perform an essential action.

## Design the complete task

For each flow, define entry, working state, commitment, feedback, and exit.
Keep draft edits separate from accepted state. Show the object and full cost
before a consequential action; use confirmation or recovery in proportion to
the consequence. Safe reversible changes need not add a confirmation step.

The server owns game rules and accepted progression. Distinguish request sent,
pending, confirmed, and rejected. Prevent duplicate consequences and preserve
a recoverable draft on failure. A button that changes a label without producing
the promised effect does not complete the task.

Plan empty, filtered-empty, loading, unavailable, error, and content-extreme
states. Each needs the correct explanation and next action. Back, Cancel,
outside dismissal, target loss, and successful completion must leave the
interface in a useful state. Keep routes and state consistent across compact
and wide forms. Motion should explain changes and preserve orientation;
reduced motion must retain the result.

## Review the rendered interface

Technical checks do not establish visual quality. Inspect actual gameplay and
UI together, at representative sizes and with supported inputs. Ask:

1. Is the next useful action clear, and does the intended attention order show?
2. Are required world information, text, targets, and exits visible and usable?
3. Can every task be reached, completed, cancelled, and revisited in each form?
4. Do pending, confirmed, rejected, selected, and equipped states tell the truth?
5. Do spacing, alignment, type, surfaces, and feedback belong to the same game?

Describe a defect by location, state, player impact, and repair. Fix blocked
actions, clipping, unreadable content, misleading state, and focus traps before
optional polish. Recheck the affected state and adjacent layouts after a repair.
Never average a blocked task into a passing score because another screen looks
good.

## Task chapters

| Decision | Chapter |
| --- | --- |
| Visual direction, implementation order, critique | [Design workflow](game-ui/DESIGN_WORKFLOW_AND_CRITIQUE.md) |
| HUD, shop, inventory, lobby, onboarding, results | [Game flows](game-ui/GAME_FLOWS_AND_INFORMATION.md) |
| Layout, compact forms, navigation | [Layout and navigation](game-ui/LAYOUT_AND_NAVIGATION.md) |
| Browsing, comparison, selection, editing, bulk actions | [Collections and actions](game-ui/COLLECTIONS_AND_ACTIONS.md) |
| Values, fields, commitment | [Choices and input](game-ui/CHOICES_AND_INPUT.md) |
| Overlays, interruption, information, feedback | [Surfaces and feedback](game-ui/SURFACES_INFORMATION_AND_FEEDBACK.md) |
| Input alternatives and direct manipulation | [Adaptive interaction](game-ui/ADAPTIVE_INTERACTION_AND_DIRECT_MANIPULATION.md) |
| Transitions and animation | [Motion](game-ui/MOTION_AND_FEEDBACK.md) |
| Ownership, focus, accessibility | [Input and focus](game-ui/INPUT_FOCUS_AND_ACCESS.md) |
| A particular control and its alternatives | [Control index](game-ui/CONTROL_INDEX.md) |

Use the installed API docs for exact signatures. These chapters explain design
decisions; they are not a second API reference or a requirement to use every control.
