# Toast.Toast

`UI.Toast` returns an empty anchor Frame. It shows a transient message. Without
an `action` it is display-only and stacks at the top (or bottom) of its layer.
With an `action` it docks at the bottom center, one at a time, and a player can
reach it. Both modes share one schedule per layer.

```luau
runtime.mount(function()
    return Host.ScreenGui {
        UI.Toast "Saved" { message = "Settings saved", key = "save", duration = 3 },
        UI.Toast "Sold" {
            message = "Kart sold",
            action = { label = "Undo", onActivate = function() print("undo") end },
        },
    }
end, playerGui)
```

- `message` (a string or a bound string) or `content` (a factory for the
  body). Give exactly one. A toast with an action takes `message`.
- `icon`: an icon name or an image source, before the message.
- `duration`: seconds on screen. Without an action the default is 4. With an
  action, `nil` keeps the row until it is closed, and a timeout waits for at
  least `readFloor` of readable time. `readFloor`: the seconds before anything
  may replace it, default 2.5.
- `priority`: a number, default 0. Higher toasts go first in the queue.
- `key`: a toast with the same key replaces a queued one at once and a
  showing one when its read floor is met, so the two never show together.
- `isPresented`: optional, the caller's boolean fact. The toast shows while it
  is true. A timeout, a replacement, Close, Cancel and the action then propose
  false through `onPresentedChange(false)`, and the row leaves only when the
  fact is false. A refusal keeps the same row and is not asked again. A bound
  toast that can end itself (a duration, or a close button) needs
  `onPresentedChange`. Without `isPresented`, mounting shows the toast once
  and it retires itself.
- `onDismiss(reason)` reports each retirement once: `timeout`, `supersede`
  (the same key replaced it), `preempt` (a more urgent toast replaced it),
  `capacity`, `action`, `close`, `cancel` (a bound toast's fact went false, or
  its owner went away), or `manual` (an unbound toast unmounted first). A
  bound toast retired for `capacity` or `supersede` also proposes false.

Without an action:
