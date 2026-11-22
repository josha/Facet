--!strict
local CatalogTypes = require("./catalog_types")

type FacetControls = CatalogTypes.FacetControls
type StackProps = CatalogTypes.StackProps
type AdaptiveStackProps = CatalogTypes.AdaptiveStackProps
type Value<T> = CatalogTypes.Value<T>
type Use = CatalogTypes.Use
type Context = CatalogTypes.Context
type Properties = CatalogTypes.Properties
type Axis = CatalogTypes.Axis
type PageDefinition = CatalogTypes.PageDefinition

type Kit = {
	ALIGN: Axis,
	DISTRIBUTE: Axis,
	GAP: Axis,
	DEFAULT: string,
	NONE: Properties,
	fixed: (number, number?) -> Properties,
	plate: (Context, string, number, number) -> Frame,
	properties: (Properties) -> Properties,
	stackDemo: (Context, Properties) -> Properties,
	stacked: (StackProps) -> StackProps,
	strips: { scrolls: CatalogTypes.Builder, fallback: CatalogTypes.Builder },
	Color3: typeof(Color3),
	Enum: typeof(Enum),
	UDim2: typeof(UDim2),
}

return function(pages: { [string]: PageDefinition }, kit: Kit)
	local ALIGN, DISTRIBUTE, GAP, DEFAULT, NONE = kit.ALIGN, kit.DISTRIBUTE, kit.GAP, kit.DEFAULT, kit.NONE
	local fixed, plate, properties, stackDemo = kit.fixed, kit.plate, kit.properties, kit.stackDemo
	local stacked, strips = kit.stacked, kit.strips
	local Color3, Enum, UDim2 = kit.Color3, kit.Enum, kit.UDim2
	local layout: { [string]: PageDefinition } = {
		Divider = {
			family = "layout",
			alias = "Divider",
			purpose = "A hairline between content groups; turns with its stack.",
			alternatives = "Spacing alone when the grouping is already clear.",
			scenarios = { "containers" },
			snippet = "UI.Divider {}",
			base = function()
				return {}
			end,
			axes = {
				{ key = "appearance", values = { "standard", "strong" } },
				{ key = "thickness", values = { DEFAULT, 3, "strokes.hairline" } },
			},
			states = {
				{ name = "vertical (in an HStack)", props = properties { vertical = true }, across = false },
				{ name = "axis x forced", props = properties { axis = "x", Size = UDim2.fromOffset(1, 40) } },
			},
			make = function(UI: FacetControls, p: Properties): Instance
				local vertical = p.vertical
				p.vertical = nil
				if vertical then
					return UI.HStack {
						height = 40,
						gap = "s",
						UI.Text { text = "Left" },
						UI.Divider(p),
						UI.Text { text = "Right" },
					}
				end
				return UI.VStack {
					width = 200,
					gap = "s",
					UI.Text { text = "Above" },
					UI.Divider(p),
					UI.Text { text = "Below" },
				}
			end,
		},
		Grid = {
			family = "layout",
			alias = "Grid (Root · Cell)",
			purpose = "A UIGridLayout of equal cells: columns, gaps, row gap, cell height or aspect ratio, alignment.",
			alternatives = "VirtualGrid for large data.",
			scenarios = { "container_grid" },
			snippet = 'UI.Grid { columns = 3, gap = "s", … }',
			base = function(c: Context)
				local cells = { columns = 3, gap = "xs", Size = UDim2.fromOffset(300, 0) }
				for i = 1, 6 do
					table.insert(cells, c.UI.Button { label = `Cell {i}`, Size = UDim2.fromScale(1, 1) })
				end
				return cells
			end,
			axes = {
				{ key = "columns", values = { 1, 2, 3, 4 } },
				{ key = "align", values = { "start", "center", "end" } },
			},
			states = {
				{ name = "row gap l", props = properties { rowGap = "l" } },
				{ name = "cell height 64", props = properties { cellHeight = 64 } },
				{ name = "square cells", props = properties { aspectRatio = 1 } },
				{ name = "padding s", props = properties { padding = "s" } },
				{
					name = "width 200, height 160 (extents)",
					props = properties { Size = NONE, width = 200, height = 160 },
					across = false,
				},
				{ name = "column flow", props = properties { flow = "column" } },
				{
					name = "min cell width 120 (as many columns as fit)",
					props = properties { columns = NONE, minCellWidth = 120 },
					across = false,
				},
			},
		},
		Path = {
			family = "layout",
			alias = "Path (vector stroke) · Facet.pathShapes",
			purpose = "Strokes normalized points (a ring, an arc, a needle from Facet.pathShapes) in a theme role or tint.",
			alternatives = "ProgressView circular for a progress ring.",
			scenarios = { "progress_ring" },
			snippet = 'UI.Path { points = Facet.pathShapes.ring({ radius = 0.4 }), closed = true, thickness = 4, role = "accent" }',
			base = function(c: Context)
				return {
					points = c.Facet.pathShapes.ring({ radius = 0.4 }),
					closed = true,
					thickness = 4,
					width = 64,
					height = 64,
				}
			end,
			axes = {
				{ key = "role", values = { "accent", "secondary", "content" } },
				{ key = "thickness", values = { 2, 4, 8 } },
			},
			states = {
				{
					name = "arc 250°",
					props = function(c: Context)
						return { points = c.Facet.pathShapes.arc(0, 250, { radius = 0.4 }), closed = false }
					end,
				},
				{
					name = "needle at 45°",
					props = function(c: Context)
						return {
							points = c.Facet.pathShapes.needle(45, { innerRadius = 0.1, radius = 0.45 }),
							closed = false,
						}
					end,
				},
				{ name = "tint", props = properties { tint = Color3.fromRGB(63, 184, 113) } },
			},
		},
		HStack = {
			family = "layout",
			alias = "HStack (row)",
			purpose = "Lays children out in a row; gap, cross-axis align, main-axis distribution and wrapping.",
			alternatives = "VStack for a column; Grid for aligned columns.",
			scenarios = { "flow_wrap" },
			snippet = 'UI.HStack { gap = "s", align = "center", distribute = "spaceBetween", a, b, c }',
			base = function(c: Context)
				return stackDemo(c, { width = 300, height = 80 })
			end,
			axes = { ALIGN, DISTRIBUTE, GAP },
			states = {
				{
					name = "wrap (narrow)",
					props = properties { wrap = true, width = 120, height = "hug" },
					across = false,
				},
				{ name = "panel surface", props = properties { surface = "panel", padding = "s" }, across = false },
				{
					name = "pill surface",
					props = properties { surface = "panel", corners = "pill", padding = "s" },
					across = false,
				},
				{
					name = "warning status",
					props = properties { surface = "panel", status = "warning", padding = "s" },
					across = false,
				},
				{
					name = "tail at the bottom",
					props = properties { surface = "panel", padding = "s", tail = "bottom" },
					across = false,
				},
			},
			demonstrates = { "grow" },
		},
		VStack = {
			family = "layout",
			alias = "VStack (column)",
			purpose = "Lays children out in a column; gap, cross-axis align, main-axis distribution and wrapping.",
			alternatives = "HStack for a row; ScrollView when the column can outgrow its box.",
			scenarios = { "containers" },
			snippet = 'UI.VStack { gap = "s", align = "start", a, b, c }',
			base = function(c: Context)
				return stackDemo(c, { width = 160, height = 240 })
			end,
			axes = { ALIGN, DISTRIBUTE, GAP },
			states = {
				{
					name = "wrap (short)",
					props = properties { wrap = true, height = 80, width = "hug" },
					across = false,
				},
				{ name = "panel surface", props = properties { surface = "panel", padding = "s" }, across = false },
				{
					name = "pane, 6 px corners",
					props = properties { surface = "pane", corners = 6, padding = "s" },
					across = false,
				},
				{
					name = "success status",
					props = properties { surface = "panel", status = "success", padding = "s" },
					across = false,
				},
				{
					name = "hug, max height 96",
					props = properties { height = "hug", maxHeight = 96 },
					across = false,
				},
				{
					name = "ground behind the content",
					props = function(c: Context): Properties
						return { ground = plate(c, "facet-status-info", 10, 10) }
					end,
					across = false,
				},
			},
		},
		Spacer = {
			family = "layout",
			alias = "Spacer",
			purpose = "Flexible space that takes a stack's leftover, never less than its minimum length.",
			alternatives = "distribute on the stack when every gap should grow alike; UI.fill() to grow a child.",
			scenarios = { "navigation_stack" },
			snippet = "UI.HStack { back, UI.Spacer {}, done }",
			base = function()
				return {}
			end,
			axes = {
				{ key = "minLength", values = { 0, 24, "l" } },
				{ key = "room", values = { "hug", 360 } },
			},
			states = {},
			make = function(UI: FacetControls, p: Properties, c: Context): Instance
				local room = p.room
				p.room = nil
				return UI.HStack(stacked({
					align = "center",
					width = (if room == 360 then 360 else "hug") :: number | "hug",
					UI.Button { label = "Back", onActivate = c.log("back") },
					UI.Spacer(p),
					UI.Button { label = "Done", appearance = "emphasis" :: string, onActivate = c.log("done") },
				}))
			end,
		},
		fill = {
			host = "HStack",
			family = "layout",
			alias = "Flex grow (UIFlexItem)",
			purpose = "Makes one child grow along its stack's main axis; a weight shares the free space.",
			alternatives = 'Spacer for empty space; width = "fill" on the cross axis.',
			snippet = 'UI.Button { label = "Grows", UI.fill() }',
			base = function()
				return {}
			end,
			axes = { { key = "weight", values = { DEFAULT, 1, 3 } } },
			states = {},
			make = function(UI: FacetControls, p: Properties, c: Context): Instance
				return UI.VStack {
					gap = "s",
					UI.HStack {
						width = 360,
						gap = "s",
						UI.Button { label = "Grows", UI.fill(p.weight) },
						UI.Button { label = "Weight 1", UI.fill(1) },
						UI.Button { label = "Fixed" },
					},
					UI.HStack {
						width = 360,
						gap = "s",
						UI.VStack { surface = "panel", padding = "s", grow = 2, UI.Text { text = "grow = 2" } },
						UI.VStack { surface = "panel", padding = "s", grow = 1, UI.Text { text = "grow = 1" } },
						UI.Button { label = "Fixed" },
					},
				}
			end,
		},
		Screen = {
			family = "layout",
			alias = "Screen (a mount's root)",
			purpose = "The root of a screen: it fills its parent, stacks its children vertically and pads them "
				.. "(padding m by default). The safe area is the ScreenGui's job (ScreenInsets keeps the root out "
				.. "of the top bar and notches); a long body goes in a ScrollView that takes the remaining height.",
			alternatives = "A stack for anything that is not the root.",
			snippet = 'app.mount(function() return UI.Screen { Name = "Main", UI.Text { … }, UI.ScrollView { UI.fill(), … } } end)',
			cellWidth = 380,
			cellHeight = 320,
			base = function()
				return {}
			end,
			axes = {
				{ key = "padding", values = { DEFAULT, 0, "xl" } },
				{ key = "align", values = { DEFAULT, "start", "center", "end" } },
				{ key = "distribute", values = { DEFAULT, "start", "center", "spaceBetween" } },
			},
			states = {
				{ name = "chrome band", props = properties { chrome = "band" } },
				{ name = "chrome edge", props = properties { chrome = "edge" } },
				{ name = "surface (reaches the glass at safe edges)", props = properties { surface = "surface" } },
				{ name = "gap l", props = properties { gap = "l" } },
				{ name = "fixed 300×200 (width/height)", props = properties { width = 300, height = 200 } },
				{
					name = "ground behind the content",
					props = function(c: Context): Properties
						return { ground = plate(c, "facet-status-info", 10, 10) }
					end,
				},
			},

			make = function(UI: FacetControls, p: Properties, c: Context): Instance
				local env = UI.environment()
				local facts = c.Compose.formula(function(use: Use)
					local inset = use(env.safeInsets)
					local size = use(env.viewportSize)
					return `Environment: {math.floor(size.X)}×{math.floor(size.Y)} {use(env.sizeClass)}, input {use(
						env.effectiveInput
					)}; ` .. `safe insets top {inset.top} (the top bar) — the ScreenGui keeps the root below it`
				end)
				local rows: Properties = { width = "fill", gap = "xs", UI.fill() }
				for i = 1, 8 do
					table.insert(
						rows,
						UI.Text {
							wrap = true,
							Size = UDim2.fromScale(1, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							text = `Body row {i} — scrolls inside the remaining height`,
						}
					)
				end
				table.insert(
					p,
					UI.Text {
						wrap = true,
						Size = UDim2.fromScale(1, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = "Screen title (first child)",
						textRole = "heading",
					}
				)
				table.insert(
					p,
					UI.Text {
						wrap = true,
						Size = UDim2.fromScale(1, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = facts,
						textRole = "caption",
					}
				)
				if p.surface then
					table.insert(p, require("./full_bleed_demo")(c))
				end
				table.insert(p, UI.ScrollView(rows))
				table.insert(p, UI.Button { label = "Continue (last child, stays pinned)", appearance = "emphasis" })
				local screen = UI.Screen(p)
				screen:AddTag("facet-panel")
				return UI.VStack {
					gap = "xs",
					width = "fill",
					UI.Text {
						wrap = true,
						Size = UDim2.fromScale(1, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = "The plate is the Screen's box (it fills this cell like a ScreenGui); its padding is the gap to the plate edge.",
						textRole = "caption",
					},
					UI.VStack { width = "fill", height = 260, screen },
				}
			end,
		},
		ErrorBoundary = {
			family = "layout",
			alias = "ErrorBoundary",
			purpose = "Contains a failing view: its fallback shows in its place, with retry; the rest of the screen lives.",
			alternatives = "Validate data before it reaches the view when the failure is expected.",
			snippet = "UI.ErrorBoundary { view = risky, fallback = function(err, retry) … end }",
			base = function()
				return {}
			end,
			axes = {},
			states = { { name = "view fails", props = properties { fails = true } } },
			make = function(UI: FacetControls, p: Properties, c: Context): Instance
				local fail = c.Compose.cell(p.fails == true)
				return UI.ErrorBoundary {
					view = function()
						if fail:peek() then
							error("the track list could not load", 0)
						end
						return UI.Text { text = "Track list loaded" }
					end,
					fallback = function(err, retry)
						return UI.VStack {
							gap = "xs",
							UI.Text { text = `Fallback: {tostring(err)}` },
							UI.Button {
								label = "Retry (succeeds)",
								onActivate = function()
									fail:set(false)
									retry()
								end,
							},
						}
					end,
					onError = c.log("onError"),
					width = p.width or 260,
					maxWidth = p.maxWidth,
				}
			end,
			demonstrates = { "view", "fallback", "onError", "width", "height" },
		},

		AdaptiveStack = {
			family = "layout",
			fills = true,
			alias = "AdaptiveStack (row that folds to a column)",
			purpose = "A row while its children fit its width, a column when they do not; `axis` pins one. "
				.. "The playground is the preview's width: switch Platform (phone, desktop) to watch it fold live.",
			alternatives = "ViewThatFits to swap whole layouts; HStack wrap to flow onto more lines.",
			scenarios = { "hud" },
			snippet = 'UI.AdaptiveStack { gap = "s", start, garage, leaderboard }',
			cellWidth = 460,
			base = function(c: Context)
				return {
					width = "fill",
					gap = "s",
					c.UI.Button { label = "Start race", appearance = "emphasis" },
					c.UI.Button { label = "Garage" },
					c.UI.Button { label = "Leaderboard" },
					c.UI.Button { label = "Settings" },
				}
			end,
			make = function(UI: FacetControls, p: AdaptiveStackProps): Instance
				if p.axis ~= "x" then
					return UI.AdaptiveStack(p)
				end
				local row = table.clone(p)
				row.width = "hug"
				row.height = "hug"
				local window: Properties = {
					axis = "x",
					width = p.width or "fill",
					height = p.height or "hug",
					UI.AdaptiveStack(row),
				}
				return UI.ScrollView(window)
			end,
			axes = {
				{ key = "width", values = { "fill", 460, 240 } },
				{ key = "axis", values = { DEFAULT, "x", "y" } },
				{ key = "gap", values = { "xs", "s", "l" } },
			},
			states = {
				{ name = "padding s", props = properties { padding = "s" } },
				{ name = "align center", props = properties { align = "center" } },
				{ name = "distribute spaceBetween", props = properties { distribute = "spaceBetween" } },
				{ name = "height 160", props = properties { height = 160 } },
				{
					name = "column, max height 96",
					props = properties { axis = "y", maxHeight = 96 },
					across = false,
				},
			},
		},
		ViewThatFits = {
			family = "layout",
			fills = true,
			alias = "ViewThatFits (first candidate that fits)",
			purpose = "Shows the first child, richest first, that fits its width (and height when fixed); the "
				.. "last is the fallback. The playground is the preview's width: switch Platform to watch it step down.",
			alternatives = "AdaptiveStack when only the axis should change; compactLabel on one Button.",
			scenarios = { "hud" },
			snippet = "UI.ViewThatFits { fullToolbar, shortToolbar, menuButton }",
			cellWidth = 380,
			base = function(c: Context)
				local UI = c.UI
				return {
					width = "fill",
					UI.HStack {
						gap = "s",
						UI.Button { label = "Start race", appearance = "emphasis" },
						UI.Button { label = "Garage" },
						UI.Button { label = "Leaderboard" },
						UI.Button { label = "Settings" },
					},
					UI.HStack {
						gap = "s",
						UI.Button { label = "Start", appearance = "emphasis" },
						UI.Button { label = "More" },
					},
					UI.Button { label = "Menu" },
				}
			end,
			axes = { { key = "width", values = { "fill", 360, 200, 110 } } },
			states = {
				{ name = "height 32 (too short for any)", props = properties { height = 32 } },
				{ name = "segmented, then menu", props = strips.fallback },
			},
		},
		Composition = {
			family = "layout",
			fills = true,
			alias = "Composition (HUD zones)",
			purpose = "A HUD with ranked regions. Narrow the plate: higher ranks give way first. "
				.. "The caption names each form; tap a short form to expand it.",
			note = "Room sets the plate width; gap and padding set spacing. Enable topbar for the real Roblox strip. "
				.. "In the captioned bottom row, captioned circles and the Race Button share one baseline. "
				.. "The leading Settings button opens a popup. Resize Studio to see strip regions land in the top zone. "
				.. "With topbar, a trailing badge keeps the padding from the screen edge.",
			alternatives = "A Screen with stacks when nothing competes for the same edge.",
			scenarios = { "hud", "radial_menu" },
			snippet = 'UI.Composition { UI.Region { zone = "topLeft", rank = 1, full, short }, … }',
			cellWidth = 380,
			cellHeight = 300,
			base = function()
				return { topbar = false, passive = false }
			end,
			axes = {
				{ key = "room", values = { "fill", 300, 200 } },
				{ key = "gap", values = { DEFAULT, "xs", "m" } },
				{ key = "padding", values = { DEFAULT, 0, "l" } },
				{ key = "rows", values = { DEFAULT, "fit" }, matrix = false },

				{ key = "topbar", values = { false, true }, matrix = false },
			},
			states = { { name = "captioned bottom row", props = properties { captions = true } } },
			make = function(UI: FacetControls, p: Properties, c: Context): Instance
				local room = p.room or "fill"
				local captions = p.captions == true
				p.room, p.captions = nil, nil
				local forms: { Value<number> } = {}
				local names: { string } = {}
				local function region(name: string, zone, rank, mayDrop, ...)
					local form = c.cell("form" .. name, 1)
					table.insert(forms, form)
					table.insert(names, name)
					return UI.Region {
						Name = name,
						zone = zone,
						rank = rank,
						mayDrop = mayDrop,
						form = form,
						expand = if name == "Round"
							then function(): Instance
								return UI.Text { text = "Round 3 · Capture the flag · 2:14 left" }
							end
							else nil,
						...,
					}
				end
				table.insert(
					p,
					region("Menu", "topLeft", 1, false, UI.Button { label = "Open menu" }, UI.Button { label = "Menu" })
				)
				table.insert(
					p,
					region(
						"Round",
						"top",
						2,
						false,
						UI.Badge { label = "Round 3 · Capture the flag" },
						UI.Badge { label = "R3" }
					)
				)
				table.insert(
					p,
					region(
						"Weapons",
						"topRight",
						3,
						true,
						UI.HStack {
							gap = "xs",
							UI.Badge { label = "Rifle 24/90" },
							UI.Badge { label = "Pistol 7/21" },
						}
					)
				)
				table.insert(p, region("Strip", "topbar", 5, true, UI.Badge { label = "Top bar strip" }))
				for _, strip in require("./topbar_demo")(c, p.topbar == true) do
					table.insert(p, strip)
				end
				if captions then
					for _, item in require("./caption_row_demo")(UI) do
						table.insert(p, item)
					end
				else
					table.insert(
						p,
						region("Ready", "bottom", 1, false, UI.Button { label = "Ready up", appearance = "emphasis" })
					)
					table.insert(
						p,
						region("Fps", "bottomRight", 4, true, UI.Text { text = "60 FPS", textRole = "caption" })
					)
				end
				local composition = UI.Composition(p)
				local plate = UI.VStack { width = room, height = "fill", composition }
				plate:AddTag("facet-panel")
				return UI.VStack {
					width = "fill",
					height = 260,
					gap = "xs",
					UI.Text {
						text = function(use: Use)
							local parts = {}
							for i, form in forms do
								local shown = use(form)
								table.insert(
									parts,
									`{names[i]}: {if shown == 0 then "hidden" elseif shown == 1 then "full" else "short"}`
								)
							end
							return "Showing now — " .. table.concat(parts, " · ")
						end,
						textRole = "caption",
						wrap = true,
						Size = UDim2.fromScale(1, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
					},
					plate,
				}
			end,
		},
		Region = {
			family = "layout",
			fills = true,
			alias = "Region (a Composition zone member)",
			purpose = "A full and short form compete with a rank 1 neighbour. Narrow the plate to change forms; "
				.. "tap a short form to expand it. Choose topbar to compare strip placements.",
			note = "Higher ranks give way first. Form is 1 for full, 2 for short, 0 for hidden. "
				.. 'A hidden mayDrop region has a "…" reveal button unless reveal is false.',
			alternatives = "A plain child of a Screen when it never competes for room.",
			scenarios = { "hud" },
			snippet = 'UI.Region { zone = "topRight", rank = 2, mayDrop = true, form = formCell, full, short }',
			cellWidth = 380,
			cellHeight = 220,
			base = function()
				return { zone = "top", rank = 2 }
			end,
			axes = {
				{
					key = "zone",
					values = {
						"topLeft",
						"top",
						"topRight",
						"left",
						"center",
						"right",
						"bottomLeft",
						"bottom",
						"bottomRight",
						"topbar",
						"action",
					},
				},
				{ key = "rank", values = { 1, 2, 3 } },
				{ key = "room", values = { "fill", 200 } },
			},
			states = {
				{ name = "mayDrop", props = properties { mayDrop = true } },
				{ name = "noReveal", props = properties { mayDrop = true, reveal = false } },
				{ name = "leading top bar", props = properties { zone = "topbar", leading = true } },
				{ name = "trailing", props = properties { zone = "topbar", trailing = true } },
				{
					name = "label and icon on the mark of a hidden region",
					props = properties { mayDrop = true, label = "Map", icon = "flag", room = 200 },
					across = false,
				},
				{ name = "no plate under the region", props = properties { plate = false } },
			},
			make = function(UI: FacetControls, p: Properties, c: Context): Instance
				local form = c.cell("form", 1)
				local room = p.room or "fill"
				local composition = UI.Composition {
					topbar = p.zone == "topbar",
					UI.Region "Neighbour" {
						zone = "top",
						rank = 1,
						UI.Badge { label = "Neighbour · rank 1 · top" },
					},
					UI.Region "UnderTest" {
						zone = p.zone,
						rank = p.rank,
						leading = if p.zone == "topbar" then p.leading else nil,
						trailing = if p.zone == "topbar" then p.trailing else nil,
						mayDrop = p.mayDrop,
						reveal = p.reveal,
						label = p.label,
						icon = p.icon,
						plate = p.plate,
						form = form,
						expand = function(): Instance
							return UI.Text { text = "Region under test — the full form, disclosed in place" }
						end,
						UI.Badge { label = "Region under test (full form)" },
						UI.Badge { label = "Short form" },
					},
				}
				local plate = UI.VStack { width = room, height = "fill", composition }
				plate:AddTag("facet-panel")
				return UI.VStack {
					width = "fill",
					height = 200,
					gap = "xs",
					UI.Text {
						text = function(use: Use)
							local shown = use(form)
							return `Showing now: {if shown == 0
								then "hidden (form 0)"
								elseif shown == 1 then "full form (form 1)"
								else "short form (form 2) — tap it to expand"}`
						end,
						textRole = "caption",
						wrap = true,
						Size = UDim2.fromScale(1, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
					},
					plate,
				}
			end,
			demonstrates = { "form", "expand", "leading", "trailing" },
		},
	}
	for id, page in layout do
		pages[id] = page
	end
end
