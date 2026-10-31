# Game screens

Choose the surface and composition from the task. A game does not need a hub,
shop, inventory, editor or tutorial unless its brief calls for one. The patterns
below are alternatives, not a screen inventory or an application template.
Use [patterns](patterns.md) for complete examples and the control references
for exact options.

## Choose presentation and navigation

| Relationship to the current activity | Starting point |
| --- | --- |
| Monitor or act while play continues | Composition with Regions |
| Inspect optional nearby context | Callout, Popover or DisclosureGroup |
| Complete a bounded modal task | Sheet or Dialog |
| Enter a mode that replaces play | A page with a Screen surface |
| Switch frequently between peer tasks | TabView |
| Go deeper and return | NavigationStack within the chosen surface |
| Browse candidates and inspect a selection | NavigationSplitView or a collection with a separate detail step |

Opening from a HUD does not require a centered Sheet. Decide how much world
context and input access the task needs. A modal owns input; visible gameplay
behind it is not necessarily interactive or paused. Use `suspendGameplay = true`
and gate game commands with `UI.environment().gameplaySuspended` when the app
should suspend them. A Studio plugin uses its host's mounting and input model;
read `Mounting` and [runtime details](runtime-details.md) for that case.

## Navigation and lifetime

Give title and return controls a clear owner. A task root can have Close;
Back returns to a parent step. A root with no parent has no Back. Redundant
controls are useful only when reach, scrolling or the host's conventions need
another access point.

For a Sheet with child navigation, build NavigationStack inside its `content`
so the stack's lifetime belongs to the Sheet. Use a bounded detent, such as
`large`, for a stack that fills its viewport. A single-step task can mount its
body directly. Keep shared selection and drafts outside disposable content.

When closing an animated surface, preserve its content through departure.
Reset a transient path and root on the next opening if the task should start
fresh; preserve them if the brief requires resuming. Clone navigation paths
without replacing unchanged entry tables. Push a child or replace an entry
in one path update rather than calling Back and deferring another navigation.
Do not close and reopen a Sheet merely to change its child step.

Route Back, Close and dismissal through the same dirty-draft policy when
edits could be lost. Read `Sheet.dismissal` and the navigation control's
contract. Keep confirmations distinct from the task being confirmed and
settle them according to the actual accepted result.

Test direct entry, child entry, Back, Close and reopening, including interrupted
transitions. Verify restored focus, state and gameplay input.

## Fit the task body

Measure the containing surface, including height and insets. Use
`UI.environment(container)` for a bounded task, not the world viewport.
Choose pane minimums, column counts and preview sizes from readable content,
useful subject detail and input targets. Sample pixel sizes are not breakpoints
for every game.

A collection may use rows, tiles or a table. Put filters beside, above or in a
separate step according to their complexity and the available room. A wrapping
`HStack { width = "fill", wrap = true }` suits short peer choices;
AdaptiveStack suits a group that should change between a row and a column.
Neither is required for every filter or choice.

Bound scrolling content. Keep commitment and its terms accessible without
trapping them behind a fixed footer when the keyboard or larger text reduces
room. See [compact compositions](compact-compositions.md).

## Choose, inspect and edit

Use [Collection](../examples/collection.luau) for one browse/detail implementation
and [Inspection](../examples/inspection.luau) for a subject-led decision.
Their models, theme assets, field names and controls illustrate those tasks.
Transfer only the parts the current application needs.

Choose a segmented Picker when a few short alternatives fit and benefit from
being visible together. Use Chips with a swatch `leading` for a named palette,
a menu for longer choices, and ColorPicker when arbitrary color entry is needed.
Keep selection distinguishable beyond color. Preview a draft where that helps
predict the accepted result; preserve it on rejected or cancelled work according
to the task's save policy.

For a purchase, show the item and complete terms at commitment. Add confirmation
in proportion to consequence, reversibility and the platform's requirements.
Use emphasis to establish action priority; every affordable item need not have
an equally prominent Buy button. Keep owned, unavailable and selected states
clear when they affect the decision.

## HUD and contextual help

For a course map, radar or spatial overview, use the
[minimap guide](../../../docs/guide/minimaps.md). It combines Region forms,
game-owned drawing, an optional opening action and a full-map destination.

Use Composition Regions for information that needs to coexist with play.
Prioritize from urgency, frequency and the camera's focus area. Provide smaller
complete forms when regions compete for room. Keep required tasks reachable
through any compact menu. Read `HUD-actions` for input ownership and bindings.

Check native touch-control clearance in the actual experience; fixed offsets
from one game's controls do not establish clearance elsewhere. Investigate
`touch-control-overlap` and `composition-unfit` findings with real labels and
supported inputs. Test text against gameplay; use a backing surface when
contrast needs it, rather than requiring a panel behind every readout.

Contextual teaching can use Callout anchored to the live target. Focused reading
may need a different surface. Keep the target usable, provide an exit, and use
real completion evidence when teaching an action.

## Quick wheel example

This example declares a game-owned action for a RadialMenu over play. Its Q and
ButtonY bindings and chat content are illustrative; choose bindings that fit
the application's existing commands. The shortcut hint displays the binding;
the action must also drive the menu.

```luau
local chatAction = Host.InputAction "QuickChat" { Type = Enum.InputActionType.Bool,
    Host.InputBinding { KeyCode = Enum.KeyCode.Q }, Host.InputBinding { KeyCode = Enum.KeyCode.ButtonY } }
Host.InputContext "Commands" { Parent = playerGui, chatAction }
local wheelOpen = C.cell(false)
local items: { Facet.RadialItem<string> } = {}
for index, message in MESSAGES do
    items[index] = { id = "chat" .. index, label = message.short, onSelect = function() sendChat(message.text) end }
end
UI.Region "Chat" { zone = "right", rank = 3,
    UI.Button "Chat" { icon = "chat", shape = "circle", caption = "Chat", shortcutHint = chatAction,
        onActivate = function() wheelOpen:set(true) end } },
UI.RadialMenu "QuickChat" { label = "Quick chat", items = items, launcher = false,
    isPresented = wheelOpen, holdAction = chatAction },
```

Mount the Region in the HUD Composition and the RadialMenu beside it in the
same mount. Use concise, distinct labels and test localization. Label width,
item count and available space determine whether the menu can remain radial;
a character-count rule does not prove fit. Inspect `RadialPanel.Presentation`
(`radial` or `list`) after opening. With `launcher = false`, the ring opens at
the screen center. Check its actual fallback and input behavior.

For results and preferences, [Outcome](../examples/outcome.luau) and
[Settings](../examples/settings.luau) demonstrate accepted data and save callbacks.
Neither example grants rewards or implements server acceptance for the game.
