# Surfaces and adaptive forms

## Disclosure and commands

**DisclosureGroup** keeps optional detail in the reading flow. Use it for advanced
settings or specifications under a useful summary. **CollapsibleView** opens a
contextual panel from a trigger. It can leave the scene visually present, but
uses the modal layer; do not promise uninterrupted gameplay input.

Keep the main decision visible while closed. Put related controls inside, not
every destination. Store durable state outside the disclosed content's lifetime.
Both use writable `expanded`; DisclosureGroup's `onToggle` reports the change
after the write. `outsideDismiss` belongs to CollapsibleView, not DisclosureGroup.
CollapsibleView restores trigger focus on close; choose useful `initialFocus`.
Check Close, outside dismissal, Escape/B and reopening with the same values.
Routes: `DisclosureGroup-and-CollapsibleView.expanded`,
`DisclosureGroup-and-CollapsibleView.appearance`.

**RadialMenu** fits a small, learned spatial command set. Give commands stable
positions and short names. A corner launcher can preserve world space, but the
open radial needs room; do not crop the ring to force a corner composition.
Use a readable menu for many commands or long, unfamiliar labels. Keep frequent
urgent commands available without opening either menu.

Choose `donut` or `fourcorners`, wedges or buttons, even or compass distribution.
For a real hierarchy, choose replace or expand navigation and fan or ring
expansion. Set completion deliberately: close, stay, root or back. Ring items
show an icon OR a label; the fallback list can show both. `follow = "idle"`
freezes the anchor during interaction. `gestureSelection` changes selection and
suppresses the normal list fallback; it is not a general accessibility upgrade.
`holdAction` needs a game-owned InputAction and binding. Touch hold can reveal a
name without committing. Verify launcher release, tap, hold, D-pad/A/B, fallback
and cancellation; do not infer accepted game state from a highlighted candidate.
Routes: `RadialMenu.items`, `RadialMenu.donut`, `RadialMenu.labelStyle`,
`RadialMenu.GuiService.GuiNavigationEnabled`, `RadialMenu.props`.

Inspect both ring and list forms. The list uses a themed width and fits narrower
room; wrapped labels can make it taller and scroll. Its path and Back/Close
share the same bounds. This adaptation preserves commands, but does not decide
whether a radial is the right interaction. Choose a bounded Menu/Popover when
a readable contextual list better fits the task. Route: `RadialMenu.donut`.

## Temporary tasks

Use **Sheet** for a bounded temporary task. Consider inline disclosure for a few
related options and Popover for context at its source. A Sheet can contain a
NavigationStack for deeper history; its root has Close and no Back. A large central sheet is not automatically a
good phone landscape form.

Choose `side` to keep a subject beside its inspector; `edge` selects left/right.
Choose `bottom` for a lower task surface, or `center` for a floating dialog.
`adaptive` uses side placement with pointer room, bottom otherwise, and center
on ten-foot displays. There is no top placement. Side-sheet detents still
control vertical height, not width.

Use `header` for identity, optional `hero` for useful art, `content` for the body
and `actions` for the commitment group. Do not duplicate the main action in the
body. Choose a typed detent that leaves intentional outer space in the actual
short viewport. `hug` can fill the room; minimum height still applies.
`contentInset` is inner padding, not an outer margin. In tiny room the pinned
regions can join the scrolling column. Inspect the whole sheet with long content
and the keyboard, rather than forcing internal panel positions.

For a dirty draft, `onPresentedChange(false)` is a dismissal request. Decide
whether to write the cell; refusing preserves the draft and focus. Explicit
Cancel must use the same policy. Setting the cell false directly bypasses it.
`interactiveDismissDisabled` blocks interactive Back/outside/drag, but explicit
Close still requests dismissal. Verify refuse, accept, cancel and return focus.
Routes: `Sheet.layout`, `Sheet.detents`, `Sheet.dismissal`, `Sheet.drag`.

## Navigation

**TabView** supplies persistent peer navigation. A left sidebar can support a
substantial home, collection or workshop body without turning every destination
into a modal. A destination still needs its own composition; the rail does not
require opaque full-screen content or full-width action buttons.

Inside the existing mounted app, with `homePage`, `collectionPage` and
`workshopPage` factories returning their task bodies:

```luau
local selected = Facet.Compose.cell("home")
local sidebarExpanded = Facet.Compose.cell(false)
UI.TabView "Destinations" {
    selection = selected,
    style = "sidebarAdaptable",
    sidebarPreference = "sidebar",
    sidebarExpanded = sidebarExpanded,
    tabs = {
        { id = "home", label = "Home", content = homePage },
        { id = "collection", label = "Collection", content = collectionPage },
        { id = "workshop", label = "Workshop", content = workshopPage },
    },
}
```

Do not force sidebar placement on a short phone. This style adapts; ten-foot
viewing normally uses a top bar. An explicit Menu action can set
`sidebarExpanded` to true on that display; B within the sidebar collapses it,
while page Back keeps its meaning. This is the expand/collapse navigation path.
Use `railWidth` only when the composition needs a bound; it also changes label
alignment. Choose retention deliberately: visited content is retained by default,
while `retention = "top"` disposes departing pages. Keep durable state in the
model and inspect resources after returns. Route: `TabView.selection`.

For an occasional destination chooser, **CollapsibleView** can animate a compact
trigger into a panel over the unchanged page. It owns modal focus and dismissal;
it is not a persistent sidebar or an inline expanding section. A TabView with
`placement = "none"` can own the destination content behind that chooser, with
one shared selection model. Close the chooser after a committed destination
change and verify focus/Back through the documented control lifetimes. Keep
frequent primary destinations visible when hiding them would slow the player.

**NavBar** supplies chrome, not history. Give it a short identity/title, a stable
center task such as search, and a trailing group of secondary commands. Each
slot accepts one GuiObject; an HStack can hold the trailing group. The trailing
group can wrap to a second row and then scroll horizontally. Do not assume a
fixed bar height or repair wrapping by shrinking text. Center content stays
mounted through this change. Route: `NavBar.reference`.

**NavigationSplitView** keeps collection and detail together where room permits;
compact form opens detail and supplies Back. Both panes remain mounted. Keep
selection separate from compact presentation state. Share a writable boolean
cell between split-view `compactBack` and NavBar `onBack`; the split view writes
whether Back is available, and writing false goes Back. No Back command belongs
on the root. Ten-foot viewing
can collapse the view even at wide width. Route:
`NavigationSplitView.NavigationSplitView`; see the [inspection example](../examples/inspection.luau).

**PageView** suits sequential peer pages, not named destinations or navigation
history. Reserve room for its indicators; pause auto-advance when inactive and
do not advance while the player is reading or editing. Wheel paging defaults
off. Route: `PageView.reference`.

## Adaptive forms

Use VStack/HStack for reading/action order, Grid for peers and Table for aligned
attributes. Use **AdaptiveStack** when the same content can simply reflow.
Choose **ViewThatFits** when the task needs genuinely different complete forms,
such as a segmented choice becoming a menu. Supply measurable candidates in
preference order and a last form that works in the minimum room.

Candidates stay mounted; share model state, create distinct Instances, and avoid
duplicate subscriptions or requests in their factories. A fill-width candidate
always fits. A hugging axis is unbounded; in a ScrollView the scroll axis does
not constrain the choice. Route: `ViewThatFits.reference`.

Use **Composition/Region** for ranked HUD information and top-bar forms. Preserve
the useful world view, main command and access to omitted detail. Forms are
concrete GuiObjects, richest first. Do not put a required task only in a form
that can disappear. Use live safe room and top-bar insets rather than fixed
offsets for Roblox controls. Check the resulting form, including generated
reveal/hidden states. Routes: `Composition.regions`, `Composition.layout`,
`Composition.adaptation`; see [patterns](patterns.md).

Resize while a task is open. Confirm the selection, draft, accepted result and
return path survive; inspect vertical text centering, lower-edge breathing room
and clearance from movement/Jump controls. Responsive selection cannot judge
the aesthetics of the chosen form for you.
