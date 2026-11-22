--!strict
local Types = require("./catalog_types")
type Context = Types.Context
type PageDefinition = Types.PageDefinition

return function(
	pages: { [string]: PageDefinition },
	plate: (Context, string, number, number) -> Frame,
	properties: (Types.Properties) -> Types.Source,
	art: string,
	shared: { sizes: Types.Axis, disabled: Types.State, none: unknown }
)
	pages.Pagination = {
		family = "navigation",
		cellWidth = 360,
		alias = "Pagination",
		purpose = "Moves between numbered result pages, or next/previous for unknown counts.",
		alternatives = "PageView for swiped content.",
		scenarios = { "paging" },
		snippet = "UI.Pagination { page = page, pageCount = 12, onChange = function(n) page:set(n) end }",
		base = function(c: Context): Types.Properties
			local page = c.cell("page", 4)
			return {
				page = page,
				pageCount = 12,
				onChange = function(n)
					page:set(n)
					c.log("onChange")(n)
				end,
			}
		end,
		axes = {
			{ key = "form", values = { "numbers", "arrows", "label", "step" } },
			shared.sizes,
			{ key = "direction", values = { "ltr", "rtl" } },
		},
		states = {
			{
				name = "step with a label (a short set)",
				props = properties {
					form = "step",
					pageCount = 5,
					label = function(page: number, count: number?): string
						return if count then `Car {page} of {count}` else `Car {page}`
					end,
				},
				across = false,
			},
			{
				name = "two siblings, two at each end",
				props = properties { siblingCount = 2, boundaryCount = 2, pageCount = 20 },
			},
			shared.disabled,
			{ name = "first/last", props = properties { showFirstLast = true } },
			{
				name = "unknown total",
				props = properties { pageCount = shared.none, hasNext = true, hasPrevious = true },
			},
			{ name = "no pages", props = properties { pageCount = 0 } },
			{ name = "diagnostics table", props = properties { controls = {} } },
		},
	}
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
		states = {
			{ name = "padding s", props = properties { padding = "s" } },
			{ name = "pill corners", props = properties { corners = "pill", padding = "s" } },
		},
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
		states = {
			{ name = "padding s", props = properties { padding = "s" } },
			{ name = "height 200 held to max height 120", props = properties { height = 200, maxHeight = 120 } },
			{
				name = "ground behind the layers",
				props = function(c: Context): Types.Properties
					return { width = 180, height = 130, ground = plate(c, "facet-status-info", 10, 10) }
				end,
			},
			{
				name = "12 px corners on a filled box",
				props = function(c: Context): Types.Properties
					return {
						width = 180,
						height = 130,
						corners = 12,
						BackgroundTransparency = 0,
						BackgroundColor3 = c.types.Color3.fromRGB(60, 94, 246),
					}
				end,
			},
		},
	}
end
