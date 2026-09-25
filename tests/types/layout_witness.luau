--!strict
local Facet = require("../../src")
local Compose = Facet.Compose
local runtime = Facet.Roblox.createRuntime()
local UI = Facet.controls(runtime)
local gap = Compose.cell("s" :: Facet.Space)
local width: Facet.Cell<Facet.Extent> = Compose.cell("fill" :: Facet.Extent)
local visible = Compose.cell(true)
local stackProps: Facet.StackProps = { gap = "m", padding = { left = "xs", top = 4 }, align = "center" :: "center" }
local screen: Frame = UI.Screen({
	gap = gap,
	padding = "l",
	distribute = "spaceBetween" :: "spaceBetween",
	UI.Label({ text = "Title" }),
})
local named: Frame = UI.Screen("Home")({ padding = 0 })
local column: Frame = UI.VStack({
	gap = "s",
	width = width,
	height = 120,
	wrap = true,
	BackgroundTransparency = 0.5,
	Visible = visible,
	UI.Button({ label = "Save" }),
})
local row: Frame = UI.HStack("Toolbar")(stackProps)
local layers: Frame = UI.ZStack({ alignH = "center" :: "center", alignV = "end" :: "end", padding = "s" })
local page: ScrollingFrame = UI.ScrollView({
	axis = "y" :: "y",
	gap = "s",
	align = "stretch" :: "stretch",
	ScrollBarThickness = 6,
})
local sideways: ScrollingFrame = UI.ScrollView("Rail")({ axis = "x" :: "x" })
local grid: Frame =
	UI.Grid({ columns = 3, gap = "s", rowGap = 4, cellHeight = 60, aspectRatio = 1, align = "center" :: "center" })
local guarded: Frame = UI.ErrorBoundary("Region")({
	view = function()
		return runtime.constructors.Frame({})
	end,
	fallback = function(failure: unknown, retry: () -> ())
		return runtime.constructors.TextButton({ Text = tostring(failure), Activated = retry })
	end,
	onError = function(_failure: unknown) end,
	width = "fill" :: "fill",
})
local flexible: UIFlexItem = UI.fill()
local weighted: UIFlexItem = UI.fill(2)
local padding: Facet.Padding = { right = "xl" }
local extent: Facet.Extent = "hug" :: "hug"
local props: Facet.ScreenProps = { padding = padding, width = extent }
local zProps: Facet.ZStackProps = { alignH = "start" :: "start" }
local scrollProps: Facet.ScrollViewProps = { axis = "xy" :: "xy" }
local gridProps: Facet.GridProps = { columns = 2 }
return {
	screen = screen,
	named = named,
	column = column,
	row = row,
	layers = layers,
	page = page,
	sideways = sideways,
	grid = grid,
	guarded = guarded,
	flexible = flexible,
	weighted = weighted,
	props = props,
	zProps = zProps,
	scrollProps = scrollProps,
	gridProps = gridProps,
}
