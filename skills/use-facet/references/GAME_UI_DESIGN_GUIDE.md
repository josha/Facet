# Game UI design

Facet supplies reusable behavior. The game supplies purpose and visual character.
Start with the player experience, then choose interaction, composition and controls.
A HUD, contextual choice, planning screen and celebration need different compositions.
Share a visual language without forcing them into one template. Read the sections
relevant to the task, then use the skill's task table for the API route.
The brief and established art direction set the target. These principles guide
tradeoffs; examples and automated design advice do not prescribe a house style.
For a new interface or visual redesign, [choose the theme direction](game-themes.md#choose-a-direction)
before building screens. Establish its feeling and concrete visual cues, then
prove them in one complete task before repeating the treatment.

## Principles

- **Serve the player's intent.** Make the situation, choices, action and result understandable. Preserve deliberate game challenge; remove accidental interface difficulty.
- **Direct attention.** Show what changes the next decision. Let urgency, relevance and frequency set priority in the current state.
- **Make the game recognizable.** Use its world, objects and tone to shape art, framing, type and motion.
- **Preserve continuity.** Keep identity, location, useful state and return paths clear as the task changes.
- **Support equivalent tasks.** Adapt to room, reach, input and viewing distance without losing decisions, consequences or exits.
- **Earn trust.** Show what the game accepted. Make commitment, failure, cancellation and recovery predictable.

Use the principles to resolve tradeoffs: planning can support detailed comparison;
urgent play needs a short glance and direct action. Keep meanings and behavior
familiar without making every layout identical.

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

Reuse established decisions for a small change. Ask about missing intent only
when it changes the design. Do not invent game systems to fill a screen.

Trace entry, orientation, choice, commitment, feedback and return, including
cancellation and rejection. Preparing equipment ends with accepted equipment
in play; opening the collection alone does not complete the task.

Choose references with a similar task, pace, input and viewing context. Inspect
the actual images for principles of clarity and craft, then create this game's
own visual treatment from its brief. Review the first representative Studio screen before repeating a new expressive
direction. Use a separate concept when the chosen art needs it. See
[theme direction](game-themes.md#inspect-references-before-choosing-the-composition).

## Organize interaction

Keep three hierarchies clear: navigation shows location and return; information
shows what matters first; input shows what receives the action and what is next.
A prominent action still needs a reachable focus path. Focus, selection and
commitment differ; moving through options must not silently purchase or equip them.

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

Keep a short choice near its source when it fits. Give a sustained task a page
or in-world station with enough room and a clear return. Replace unrelated HUD
groups; retain needed context, such as balance beside cost.

Use a radial choice when direction or a learned spatial arrangement helps the
player choose from a short set. A readable menu or anchored popover often fits
labeled alternatives better. A circle is not inherently more playful or more
usable with a controller. For a custom opener, supply the control's actual
anchor; a hidden built-in launcher cannot locate that opener. Inspect the open
state near screen edges and after rotation. Allow safe-area adjustment or a
compact fallback while keeping its relationship to the source understandable.

Use a Sheet when the task needs modal focus over the game. Keep HUD context
visible when it helps the decision. A Sheet can contain a NavigationStack for
child steps; the task root has Close and no Back. Use a page when entering a
different mode replaces the play view. A Screen with `surface` paints to the
edges. A HUD opener alone does not determine the presentation: a contextual
command, persistent tool and full-screen map have different needs.

Keep frequent safe actions direct. Add review or recovery in proportion to
consequence. Disclose optional detail without hiding commitment terms. A
confirmation does not repair an ambiguous label or adjacent targets.

## Direct attention and express the game

Establish what should be noticed first, second and third. A hazard can outrank
routine gains during play; object differences can lead during preparation.
Keep required facts visible together. Reduce competing borders and accents
before adding decoration.

Choose a coherent palette, type hierarchy, spacing, surfaces, icons and motion.
Express shared values through the theme. Derive the dominant subject, framing,
material, type contrast and accent from this game's objects and tone.
Aim for an engaging expression of this game, beyond recoloring neutral panels.
Use image-based control surfaces when the art direction benefits from them;
keep standard labels, input, state and focus behavior in the controls.
Carry that visual language through HUD, decisions and results. Recipe labels,
sample art and dimensions show a contract; they do not define the game's identity.

Art direction also sets composition. A subject staged beside a choice, objects
arranged on a surface and a chart with contextual commands need different
bodies. Do not first build a generic card page and then add an illustration
above it as the entire game treatment. Standard controls can have custom
artwork and silhouettes while retaining their behavior.

Choose the page body before making a shared page helper. Share navigation,
input lifetime and visual roles; let each body arrange its decision. A full-width
stack of headings, paragraphs and buttons can hide the difference between
inspection, comparison and results. Use the [layout chapter](game-ui/LAYOUT_AND_NAVIGATION.md)
to choose that relationship before adding containers.

Keep related content close and comparable facts aligned. Use space to separate
groups without boxing every fact. Align comparable groups and use elevation
consistently to explain relationships. Different sizes or surfaces can express
different roles; equal height and uniform shadows are not requirements. Reserve strong
accent for the important action or state. Keep stable meanings for color and icons.
Distinguish focus, selection, equipped, pending and unavailable beyond color.

Present facts in a form the player can read and compare. Repeat a fact when
distance, scrolling or a consequential action makes it useful. Price does not
establish ownership: an owned item can still be sold or bought again. Show
ownership, availability and selection when those states affect the decision.
Use familiar glyphs with accessible names or clear text labels; neither is
required for every fact. Show one kind of fact consistently, such as
every price in one treatment, so the eye compares values. A second color can
add a second fact at a glance, such as rarity or a price the player cannot pay
yet, when it means the same thing on every item, keeps the fact readable on
every background and is not the only signal.

Give objects meaningful artwork or well-framed Stage previews. Show the actual
subject and its distinguishing details. Show a color as a swatch and a pattern
as a preview. Keep that preview recognizable when selected or focused; put the
state cue around it instead of replacing the fact it communicates. Pair
unfamiliar glyphs with labels. Test text over busy gameplay
and bright effects; use a backing surface when contrast otherwise fails.

Comparison needs enough candidates and facts in view; action needs brief
glances; celebration can give artwork room. Use grids for recognition, lists
for descriptions and tables for shared attributes. Keep identity, decisive facts
and commitment together. Avoid introductions or filters that consume a short
screen's decision area. Keep commitment outside a long browsing collection.

Polish includes stable targets and responsive feedback. Hover and focus must
not move neighbors or clip the emphasized object. Motion explains a change and
must preserve the result when reduced or skipped.

## Protect play

Keep the camera's focus area and space covered by a held thumb clear.
Show glanceable information that changes the next action. Group HUD content by
meaning, with smaller forms and explicit priority. A compact form must retain
access to every required task it replaces. Repeating the same status in several
groups spends space and attention without adding a decision.

Use safe edges without crowding native controls. The free strip beside Roblox's
top bar buttons suits a compact item, such as a currency or a menu button.
It holds readouts and menus, not frequent actions: a phone's top edge is out of
thumb reach. Give the primary action the widest target and put it, with its
frequent neighbours, in one `action` region. A portrait phone shows it at
the bottom centre, and a landscape screen at the bottom right.
Composition handles TopbarInset and its fallback; read `HUD-actions` to match
Roblox's row. A marker may occupy the focus area when locating that target is
the task. End commands and notices when their context ends.

Provide compact Region forms when the preferred arrangement cannot fit.
Choose what remains from the information needed during play; text, a bar or
a contextual cue can each be appropriate. Check simultaneous regions with
real labels and native controls at supported sizes. Investigate `hud-in-view`
findings from `lute run tools/facet audit` against the game's actual focus area;
a world marker and an unrelated status panel can need different placement.

Composition is passive. Gameplay keeps the movement stick and D-pad.
Give HUD tasks explicit gamepad actions and visible input hints. The opened
task surface owns selection; choose a useful, safe initial target through the
control's focus policy. A page replacing gameplay must own input and restore
the previous state on return. Opening an overlay does not pause the world.
The [input chapter](game-ui/INPUT_FOCUS_AND_ACCESS.md) explains input ownership;
`Tasks.pages` shows its lifetime.

## Adapt the task

Room, physical readability, reach, input precision and pace are separate
constraints. A high-resolution handheld can need large text and controller
navigation in a short layout. Do not infer all constraints from a device label.

Choose layout from usable container bounds, including height and insets.
Choose prompts from the active input and actual bindings. Apply text and access
preferences independently. Keep selection, drafts and location through a resize
or input change. The input chapter maps these decisions to `UI.environment`.

Show useful browsing and detail together when they fit; otherwise provide a
complete detail step. Reduce decoration, reflow groups and disclose optional
facts before reducing legibility, consequences or exits. Do not shrink the whole UI.

Bound task width before wrapped text or fill collections. Short readouts can hug;
explanations grow. Test long labels, larger text and missing art. Short decisions
fit their content; large collections need bounded scrolling. Inspection artwork
needs room for distinguishing details, beyond a thumbnail's fixed height.

Touch needs reachable targets and movement clearance. Pointer hover cannot hold
required information. Gamepad needs visible entry, predictable focus, scroll
access and Back. Provide digital alternatives to precision gestures.
A displayed shortcut must invoke the same command as its visible control.
Do not bind Roblox's reserved Escape or gamepad Start in game commands.

## Make outcomes truthful

Acknowledge input and distinguish pending, accepted and rejected work. Sending
is not saving; the server owns accepted progression. Keep drafts recoverable
with one dirty-dismissal policy. Preserve query, selection and useful scroll
position on return.

Distinguish no items, no matches, loading, unavailable and failed requests.
Offer the matching next step: create, clear filters, wait, explain eligibility
or retry. Pair constraints with their reason and a route forward when one exists.
Test stale data, disconnection and interruption without false success.

Keep important results available after transient feedback. Sound and haptics
need an equivalent visible signal. Lead results with personal outcome and
accepted gains, then comparison and the next action. Teach through the visible
action with Skip and replay. Time or a finished animation does not prove progress.

## Correct the composition before repeating it

Build one complete task with representative labels, art and data. Capture it
with gameplay at the intended viewing size, including the supported narrow and
short layouts. Identify the dominant subject, the next useful action and
the facts needed to choose it. If these are hard to find, change the grouping,
space or hierarchy before adding more pages. A larger title or another accent
does not repair an unclear relationship.

Compare the capture with the task and visual references before delivery. Do
not wait for the user to request the first visual critique. Functional checks
and readable text do not establish the quality of the art direction.
Can the player recognize the object, compare
the decisive facts and see the action and return route together? If a preview
is small, reallocate the body around it. If routine status competes with the
decision, move or quiet it. If every destination looks alike, revise the body
for its task. Capture the revised result before copying the structure.

When usability testing with players is available, have an unfamiliar player
locate the task, predict the action, complete it and
explain the result without coaching. Observe hesitation, wrong turns, repeated
input and missed feedback. Fix the cause, then repeat the affected task.
An agent walkthrough can find gaps; it does not establish player preference.

Separate technical checks, visual review, input tests and player observations.
Screenshots do not prove reachability; simulated dimensions do not prove handheld
readability. Record the actual build, device, inputs and paths tested.
Fix shared layout or control causes before copying the pattern elsewhere.

## Reference chapters

These chapters give more detail about one subject. They are optional. Read a
chapter only when the task needs that subject. The skill's task table stays the
reading route.

- [Game flows](game-ui/GAME_FLOWS_AND_INFORMATION.md): pace and information need across a flow.
- [Layout and navigation](game-ui/LAYOUT_AND_NAVIGATION.md): the relationship between surfaces, location and return.
- [Collections and actions](game-ui/COLLECTIONS_AND_ACTIONS.md): how to represent records and act on them.
- [Choices and input](game-ui/CHOICES_AND_INPUT.md): how to expose a decision and collect a value.
- [Surfaces and feedback](game-ui/SURFACES_INFORMATION_AND_FEEDBACK.md): what interrupts, what stays and how a result shows.
- [Input, focus and access](game-ui/INPUT_FOCUS_AND_ACCESS.md): how each input reaches the same task.
- [Motion and feedback](game-ui/MOTION_AND_FEEDBACK.md): motion that explains a change.
- [Adaptive manipulation](game-ui/ADAPTIVE_INTERACTION_AND_DIRECT_MANIPULATION.md): move, reorder, resize and adjust across inputs.

## Design sources

These sources explain the reasoning. Use the Facet API nodes for implementation.

- Celia Hodent's [game UX practice](https://celiahodent.com/ux-practices-epic-games/) distinguishes intended challenge from interface difficulty. Her [cognitive psychology guide](https://celiahodent.com/cognitive-psychology-applied-to-user-experience-in-video-games/) explains attention, memory and player testing.
- Edd Coates's [Animex talk abstract](https://animex.tees.ac.uk/speaker_page.cfm?speaker=950&year=32) explains why reference analysis must identify design rationale. His [Game UI Database](https://www.gameuidatabase.com/) supplies screen references; [The Game UI Bible](https://www.lostincult.co.uk/shop/p/gameui) is further reading. [Interface In Game](https://interfaceingame.com/) is another visual archive.
- Xbox Accessibility Guidelines cover [navigation](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/112) and [context and consequences](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/114). Apply the principles without treating Xbox button labels as universal.
- Valve's [handheld recommendations](https://partner.steamgames.com/doc/steamhardware/recommendations) and [compatibility guidance](https://partner.steamgames.com/doc/steamhardware/compat) separate controller access and physical readability from resolution. They inform cross-platform review; they are not Roblox requirements.
