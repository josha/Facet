--!strict
local Types = require("./catalog_types")
type Context = Types.Context
type PageDefinition = Types.PageDefinition

return function(
	pages: { [string]: PageDefinition },
	plate: (Context, string, number, number) -> Frame,
	properties: (Types.Properties) -> Types.Source,
	art: string
)
	pages.Group = {
		family = "layout",
		alias = "Group (one fade)",
		purpose = "Dims a strip's text, image, fill and child outlines together with native CanvasGroup compositing.",
		alternatives = "HStack for an unfaded row; a native CanvasGroup when no Facet sizing is needed.",
		scenarios = { "canvas_group" },
		snippet = "UI.Group { groupTransparency = dim, width = 360, height = 80, strip }",
		base = function(c: Context)
			return {
				width = 360,
				height = 80,
				groupTransparency = 0.4,
				c.UI.HStack {
					gap = "s",
					c.UI.Image { image = art, Size = c.types.UDim2.fromOffset(40, 40) },
					c.UI.Text { text = "Audio" },
					c.UI.Button { label = "Apply" },
				},
			}
		end,
		axes = { { key = "groupTransparency", values = { 0, 0.4, 1 } } },
		states = { { name = "padding s", props = properties { padding = "s" } } },
	}
	pages.ZStack = {
		family = "layout",
		alias = "ZStack (layers)",
		purpose = "Layers children in one box; each layer aligns inside it (AnchorPoint + scale Position).",
		alternatives = "A stack when the children should not overlap.",
		scenarios = { "containers" },
		snippet = 'UI.ZStack { alignH = "end", alignV = "start", plate, badge }',
		base = function(c: Context)
			return {
				width = 140,
				height = 96,
				plate(c, "facet-panel", 140, 96),
				c.UI.Badge { label = "New", appearance = "status", status = "accent" },
			}
		end,
		axes = {
			{ key = "alignH", values = { "start", "center", "end" } },
			{ key = "alignV", values = { "start", "center", "end" } },
		},
		states = { { name = "padding s", props = properties { padding = "s" } } },
	}
end
