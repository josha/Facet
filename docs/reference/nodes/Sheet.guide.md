# Sheet.guide

The Sheet `guide` option pins a ButtonGuide to the bottom edge of the sheet.

- `guide`: [ButtonGuide](ButtonGuide.reference.md) options (`entries`,
  `inputs`, `controlSize`) without native properties. The Sheet puts the
  guide in a `Guide` region at the bottom of the panel, inside the sheet
  padding and below the scrolling `Room` that holds the body and the pinned
  `actions`. The region is outside every scroller, so the guide never scrolls
  away, also when a short sheet scrolls its pinned regions.
- `guideAlignment`: `"end"` (the default, the trailing edge) or `"start"`.

The guide follows the ButtonGuide rules. It shows for its input classes. It
hides when no entry is live and when an Alert opens above the sheet. It is
never a focus stop: a gamepad enters the sheet on its content.

The guide takes its height and an 8 pixel gap from the room above it, so
the body is shorter while the guide shows. While the guide is hidden, the
body takes that room back.

```luau
return UI.Sheet {
    title = "Shop",
    isPresented = Compose.cell(true),
    content = function()
        return UI.Button { label = "Blade" }
    end,
    guide = {
        entries = { { keyCode = { Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1 }, label = "Tabs" } },
    },
    guideAlignment = "start",
}
```
