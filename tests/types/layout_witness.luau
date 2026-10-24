--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
local Facet = require("../../src")
local Compose: ComposeModule = Facet.Compose
local runtime: ComposeRuntime = Facet.Roblox.createRuntime()
local UI = Facet.controls(runtime)
local Host = Facet.host(runtime)
local small: Facet.Space = "s"
local fill: Facet.Extent = "fill"
local gap = Compose.cell(small)
local width: Facet.Cell<Facet.Extent> = Compose.cell(fill)
local visible = Compose.cell(true)
local maximum = Compose.cell(480)
local stackProps: Facet.StackProps =
	{ Name = "Toolbar", maxWidth = 480, gap = "m", padding = { left = "xs", top = 4 }, align = "center" }
local screen: Frame = UI.Screen({
	maxWidth = 640,
	gap = gap,
	padding = "l",
	distribute = "spaceBetween",
	UI.Text({ text = "Title" }),
})
local named: Frame = UI.Screen("Home")({ padding = 0 })
local column: Frame = UI.VStack({
	gap = "s",
	width = width,
	maxWidth = maximum,
	height = 120,
	wrap = true,
	BackgroundTransparency = 0.5,
	Visible = visible,
	UI.Button({ label = "Save" }),
})
local row: Frame = UI.HStack(stackProps)
local readout: Frame = UI.HStack({ surface = "panel", corners = "pill", padding = "s", UI.Text({ text = "12" }) })
local tile: Frame = UI.VStack({ surface = "pane", corners = 6 })
local framed: Frame = UI.VStack({ surface = "surface", corners = "panel" })
local adaptiveProps: Facet.AdaptiveStackProps = { maxWidth = maximum, gap = "s", axis = "x" }
local adaptive: Frame = UI.AdaptiveStack(adaptiveProps)
local fits: Frame = UI.ViewThatFits({ maxWidth = 480, UI.Text({ text = "Wide" }), UI.Text({ text = "Narrow" }) })
local layers: Frame = UI.ZStack({ maxWidth = maximum, alignH = "center", alignV = "end", padding = "s" })
local page: ScrollingFrame = UI.ScrollView({
	maxWidth = 640,
	axis = "y",
	gap = "s",
	align = "stretch",
	ScrollBarThickness = 6,
})
local sideways: ScrollingFrame = UI.ScrollView("Rail")({ axis = "x" })
local grid: Frame = UI.Grid({
	maxWidth = 640,
	columns = 3,
	gap = "s",
	rowGap = 4,
	cellHeight = 60,
	aspectRatio = 1,
	align = "center",
})
local guarded: Frame = UI.ErrorBoundary("Region")({
	maxWidth = function(use: Facet.Use): number
		return use(maximum)
	end,
	view = function()
		return Host.Frame({})
	end,
	fallback = function(failure: unknown, retry: () -> ())
		return Host.TextButton({
			Text = tostring(failure),
			Activated = retry,
		})
	end,
	onError = function(_failure: unknown) end,
	width = "fill",
})
local flexible: UIFlexItem = UI.fill()
local weighted: UIFlexItem = UI.fill(2)
local padding: Facet.Padding = { right = "xl" }
local extent: Facet.Extent = "hug"
local props: Facet.ScreenProps = { padding = padding, width = extent }
local zProps: Facet.ZStackProps = { alignH = "start" }
local scrollProps: Facet.ScrollViewProps = { axis = "xy" }
local gridProps: Facet.GridProps = { columns = 2 }
local dividerProps: Facet.DividerProps = { axis = "x", thickness = "strokes.hairline", appearance = "strong" }
local divider: Frame = UI.Divider(dividerProps)
local spacerProps: Facet.SpacerProps = { minLength = "m" }
local spacer: Frame = UI.Spacer(spacerProps)
local adaptive: Frame = UI.AdaptiveStack({ axis = "x", gap = "s" })
local fits: Frame = UI.ViewThatFits({ UI.Text({ text = "Long" }), UI.Text({ text = "L" }) })
local chosen: Facet.Cell<number> = Compose.cell(1)
local region: Frame = UI.Region("Tasks")({
	zone = "left",
	rank = 2,
	mayDrop = true,
	form = chosen,
	expand = function(): Instance
		return UI.Text({ text = "Win a round" })
	end,
	UI.Text({ text = "Tasks" }),
	UI.Text({ text = "1/3" }),
})
local hud: Frame = UI.Composition("Hud")({ gap = "s", padding = "m", topbar = visible, region })
local compactInset = true
local topInset: Facet.Sides = { top = "xl" }
local optionalInset: Facet.Sides = { top = if compactInset then "xl" else nil, right = 0, bottom = 0, left = 0 }
local paddedTop: Frame = UI.VStack("PaddedTop")({ padding = topInset })
local paddedOptional: Frame = UI.VStack("PaddedOptional")({ padding = optionalInset })

return {
	paddedTop = paddedTop,
	paddedOptional = paddedOptional,
	adaptive = adaptive,
	fits = fits,
	hud = hud,
	screen = screen,
	named = named,
	column = column,
	row = row,
	readout = readout,
	tile = tile,
	framed = framed,
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
	divider = divider,
	spacer = spacer,
}
