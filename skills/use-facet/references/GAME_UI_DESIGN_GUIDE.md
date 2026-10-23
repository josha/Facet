# Game UI design

This guide applies the skill's principles: player intent, game identity,
attention, adaptation and trust. Facet supplies reusable behavior; the game
supplies meaning and visual character.
A HUD, contextual choice, planning screen and celebration need different
compositions. Share a visual language without forcing them into one template.

## Make the game recognizable

Choose a coherent palette, type hierarchy, spacing, surfaces, icons and motion.
Express them through the theme. Establish what should be noticed first, second
and third in each state. Use scale, alignment and negative space to make that
order visible; do not surround every fact with a box.

Choose a visual motif from the game's world and repeat it with restraint in
art, framing and transitions. Design one complete connected sequence: the
gameplay entry, the decision, its feedback and the return. Give each state a
clear focal area and retain the object's identity across the sequence.
A theme is the shared visual language; each task still needs its own composition.

Choose the composition from the subject. Equipment inspection can give the
selected object most of the space, with a quiet collection beside it. A skill
tree needs visible connections and a selected-node explanation. A race result
can lead with placement and the finish moment, then earned gains and standings.
A workshop can keep the object in view while tools and materials surround it.
Use these relationships to choose controls; a grid is useful when silhouettes
help comparison, not as the body of every destination.

Specify the game's visual direction before styling controls: the subject that
dominates, the framing or material motif, the type contrast, and the role of
accent. For example, a field journal can use paper, ink and specimen drawings;
a racing garage can use vehicle silhouettes, technical labels and timing digits.
Carry that direction through HUD, choices and results. Do not turn every theme
into dark rounded cards with a different accent color.

Keep related content closer than separate groups and align comparable facts.
Test text over busy gameplay and bright effects; add a backing surface when
the world cannot provide reliable contrast.

Give objects meaningful artwork or well-framed Stage previews. Make the subject
large enough to inspect its distinguishing details. Frame the chosen object
beside the facts and action it informs. Show a color as a swatch and a pattern
as a preview. Use recognizable glyphs with labels for destinations and object
types. Reserve strong accent for the important action or state; repeating
bright buttons everywhere destroys emphasis. Distinguish focus, selection,
equipped, pending and unavailable beyond color.

Choose density for the task: comparison needs several facts visible together,
action needs brief glances, and celebration can give artwork room. Preserve
recognition rather than making players remember facts across tiny steps.
One dominant action suits many decision panels, but gameplay may require
several immediate controls at once.

Polish includes responsive feedback and stable targets. Acknowledge input
promptly, preserve identity during updates and animate meaningful changes.
Hover or focus must not move neighboring targets or clip the object it emphasizes.
Motion must preserve the same final result when reduced or skipped.

## Protect play

Keep the camera's focus area and space covered by a held thumb clear. Show
glanceable information that changes the next action. Put coherent HUD groups
in separate Composition Regions, with meaningful smaller forms and explicit
priority. Keep Region nodes stable; branch inside forms.

Safe edges are useful working space. Use the free top-bar strip for a compact
44-pixel form when appropriate; Composition handles TopbarInset and fallback.
Secondary navigation can use the safe top-right area. A compact Menu must
preserve every destination it replaces. Avoid duplicate routes in the same form.

Gameplay commands appear only while applicable. Clear expired queue, voting or
other notices when state changes. A world marker may occupy the focus area
when locating that target is the immediate task; routine status may not.

## Match the structure to the decision

| Relationship | Starting point |
| --- | --- |
| Several HUD groups competing for room | Composition and Region |
| Revisited peer destinations | TabView |
| Deeper task with a return path | NavigationStack |
| Collection and selected detail | NavigationSplitView |
| Visual recognition, descriptions, shared attributes | VirtualGrid, VirtualList, Table respectively |
| Optional facts in the current flow | DisclosureGroup |
| A quick choice attached to an object | Popover or Menu |
| A bounded interruption that must own attention | Sheet or Dialog |
| Brief consequential confirmation | Alert |
| Current progress, deadline, acknowledgement | ProgressView, Timer, Toast |

Choose the surface before its controls. Persistent destinations usually need
pages or in-world stations; Sheet is not the default for every task. A settings
value is not a navigation tab. Focus or selection must not silently commit a
purchase, equip change or destructive action.
Let a dedicated page replace unrelated HUD groups. Keep only the context it
needs, such as the balance beside a cost. On short screens, reduce introductory
copy and decorative headers before reducing the usable decision area.

Use controls that expose the decision: Toggle for an on/off state, Picker for
named alternatives, and cards with artwork for visually identified objects.
Keep available choices and the current value visible. A button that cycles
through hidden values makes comparison and correction harder.

Every menu, focus move and confirmation costs attention. Add a step when it
improves understanding or prevents a meaningful error. Keep frequent safe
actions direct; use review or recovery in proportion to the consequence.

Keep identity, decisive facts and commitment together. On wide screens expose
useful context. On narrow screens use a complete detail step where necessary.
On short screens let art and secondary content yield before required actions.
Keep the main action outside a long scrolling collection when it applies to
the selected object.

Use wide space for simultaneous browsing and detail, then a complete detail
page in compact space. Size a surface for its content and task; short decisions
should not leave a large empty panel, and long catalogs should not push the
selected object's action below the viewport. Verify this with real content
before repeating the layout across destinations.

Build the destination with Tasks.pages and its body with the recipe that fits
the decision. A collection needs recognizable silhouettes and comparable facts;
an editor needs a useful preview and visible choices; results need an outcome
and accepted gains. Share headers, spacing and interaction rules without
forcing those bodies into one universal panel. Review the shortest viewport
with real labels, art and data before copying the structure.

## Adapt the task, not just its size

Space, input precision, viewing distance and gameplay pace are separate facts.
Use actual room and environment information, not device-name switches. Do not
shrink the entire interface to make an oversized design fit.

Bound task width before wrapped text or fill collections. Keep compact readouts
unwrapped; let explanatory text grow. Support long labels, larger text and
missing artwork. Reduce decoration, reflow groups and disclose optional detail
before sacrificing legibility, consequences or exits.

For a small set of peer cards that determines surface height, use VirtualGrid with
`minColumnWidth`, `mode = "all"` and `hug = true`. Items share the available
row width without empty columns and wrap as the surface narrows. Do not size
items from the viewport or leave unused space beside fixed-width cards.
Keep large catalogs in a bounded scrolling collection.

Touch needs reachable targets and clearance from native movement controls.
Pointer hover cannot hold required information. Gamepad needs a visible entry,
predictable focus, scroll access and reliable Back. Displayed shortcuts must
invoke real commands. Do not bind Roblox's Escape or gamepad Start.

Composition is a passive responder. Gameplay keeps the movement stick and
D-pad. Give each HUD task a gamepad button action with a visible glyph; let
the task surface take selection when it opens. Test the first stick push
after spawning with nothing selected, then each HUD task and Back.

A page replacing gameplay must own input: disable the game's gameplay
InputContext, hide custom touch commands and restore them on exit. Use
GuiService.TouchControlsEnabled for native movement controls and restore the
previous value. A visible overlay does not itself pause the world.

## Make outcomes truthful

Show pending, accepted and rejected work separately. The server owns game rules,
eligibility and accepted progression. Keep drafts recoverable; apply one dirty
dismissal decision to every exit route. Preserve query, selection and useful
scroll position on return.

Distinguish no items, no matches, loading, unavailable and failed requests.
Offer the matching next step: create, clear filters, wait, explain eligibility
or retry. Test stale data, disconnection and interruption without false success.

Lead results with the personal outcome and earned gains, then comparison and
the next action. Teach through the actual visible action with Skip and replay.
Do not grant progress merely because time elapsed or an animation finished.

Review connected states, not one polished screen: active play, choosing,
editing, interruption, failure, return and reward. Operate each distinct pattern
with supported inputs at wide, narrow and short sizes. A technically passing
screen is not proof of visual quality; a beautiful screen cannot excuse a
blocked task.

Inspect a capture at its intended viewing size. The first glance should reveal
the subject, current state and next useful action. If every element has equal
weight, reduce competing borders, labels and accents before adding decoration.
Check that art shows the actual object and its distinguishing features, that
text and art share a deliberate alignment, and that empty space supports the
focal area. Remove redundant headers and repeated information. Apply feedback
to the selected object and accepted result, not to every container at once.

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

Use installed API nodes for signatures and defaults.
