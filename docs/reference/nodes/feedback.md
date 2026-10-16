### feedback

`UI.feedback(kind)` plays one of the named feedback kinds at once. See
[Haptics](Haptics.md) for the kinds and their engine effects.

```luau
local function onPurchaseConfirmed(granted: boolean)
	UI.feedback(if granted then "success" else "error")
end
onPurchaseConfirmed(true)
```
