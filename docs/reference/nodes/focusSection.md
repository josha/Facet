### focusSection

`UI.focusSection(group, options?)` makes the GuiObject `group` an entry
region for directional navigation. Call it inside a component or a Compose
owner; it stops when the owner ends. It reads and writes
`GuiService.SelectedObject` and adds no input binding or focus stop.

| Option | Effect |
|---|---|
| `entry` | Where the selection lands when it enters `group` from outside. `"restore"` (the default): the item last selected there, while it is still selectable and visible. `"first"`: the first selectable item in layout order, every time. `"nearest"`: the engine's own choice. |
| `preferred` | The name, or a relative path such as `"Hero/Play"`, of a descendant. On a `"restore"` entry with nothing remembered, it wins. |
| `focusOnAppear` | `true` selects the first item in layout order when the section appears; a name or path selects that descendant. It acts only while something is already selected (keyboard or gamepad navigation), so a touch or mouse player gets no selection ring. |
| `returnFocus` | `true` remembers the selected item when the section appears and selects it again when the section goes away, if it is still selectable and the selection was inside the section or gone. |

An unknown option or `entry` causes an error. A branch that shows a detail
over a list uses `focusOnAppear` and `returnFocus` together:

```luau
local open = Compose.cell(false)
Compose.show(open, function()
	local detail = UI.VStack "Detail" {
		UI.Button "Back" { label = "Back", onActivate = function() open:set(false) end },
	}
	UI.focusSection(detail, { focusOnAppear = "Back", returnFocus = true })
	return detail
end)
```
