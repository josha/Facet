# Sheet.dismissal

Without `onPresentedChange`, a dismissal writes `false` to `isPresented`.
With `onPresentedChange(nextValue)`, the Sheet proposes `false` and leaves
the cell unchanged. Set the cell to accept. Leave it unchanged to keep the
same mounted content, including its draft and focus, while asking the player.

Close, the dismissible grabber, drag dismissal, outside press, and keyboard
or gamepad Back use this request. `interactiveDismissDisabled` still blocks
interactive dismissal; an explicit Close remains a request. A cancel action
in `actions` owns its callback, so route that callback through the same guard.
Programmatic `isPresented:set(false)` is an accepted model change and does
not invoke the request callback. A content-factory failure still closes the
failed Sheet and reports the error.

For an editor, compare every draft field with accepted state. Use one close
function for the Sheet and other routes that leave the editor:

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local C = Facet.Compose
local open, dirty, confirmDiscard = C.cell(true), C.cell(false), C.cell(false)
local function requestClose(nextValue: boolean)
    if not nextValue and dirty:peek() then
        confirmDiscard:set(true)
    else
        open:set(nextValue)
    end
end
```

Pass `requestClose` as `onPresentedChange`. Cancel closes only the discard
confirmation. Discard restores the accepted draft, then closes both surfaces.
Save keeps the draft pending until the server accepts it; rejection preserves
the draft and shows the error. See [Tasks.purchase](Tasks.purchase.md) for the
request and response pattern. Do not mark a draft saved when sending a request.

`initialFocus` is a name, or a function that Facet calls once, with no
arguments, when the sheet opens and that returns a name or nil. With a
keyboard or gamepad, the sheet first selects that control, or the first
shown and enabled control inside an instance of that name, in the body or the
actions. Content that mounts after the sheet opens, such as collection rows,
still takes the selection while the player has not moved it. Without it, or when no such control is selectable, it selects the
body's first control, then the action with `role = "default"`, then the
`cancel` action, then the first action that is not `destructive`, and Close or the grabber only
when nothing else can be acted on, since Back already closes the sheet. Name
the item the player most likely wants, such as a recommended product.
