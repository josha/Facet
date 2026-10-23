# Sheet.guide

The Sheet `guide` option puts a ButtonGuide on the bottom edge of the sheet.

- `guide`: [ButtonGuide](ButtonGuide.reference.md) options (`entries`,
  `inputs`, `controlSize`) without native properties. The Sheet puts the
  guide in a `Guide` region below the body and the pinned `actions`, inside
  the sheet padding. The region is outside the scrolling content, so the guide
  never scrolls away. It aligns to the trailing edge.

The guide follows the ButtonGuide rules. It shows for its input classes. It
hides when no entry is live and when an Alert opens above the sheet. It is
never a focus stop: a gamepad enters the sheet on its content. While the
guide is hidden, the body takes its room.

```luau
local buy = Host.InputAction { Name = "Buy" }
return UI.Sheet {
    title = "Shop",
    isPresented = Compose.cell(true),
    content = function()
        return UI.Button { label = "Blade" }
    end,
    guide = { entries = { { action = buy, label = "Buy" } } },
}
```
