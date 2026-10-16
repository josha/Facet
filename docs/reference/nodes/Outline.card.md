# Outline.card

Show a hierarchical collection.

Inside an app mount, set `local UI = app.UI`.

```luau
local spec: Facet.KeyedOutlineSpec<string, string> = { from = { "Root" }, key = function(item) return item end, children = function() return {} end, render = function(current) return UI.Text { text = current } end }
UI.Outline "Tree" (spec)
```

Key options: `from`, `key`, `children`, `expanded`, `render`.

Keep expansion and durable row state in the model.

Related controls: [Controls](Controls.md).

Open:

- [Outline.reference](Outline.reference.md)
