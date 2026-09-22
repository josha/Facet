--!strict
-- Container layout is a recipe over solved geometry, not a viewport breakpoint.
-- Outer width chooses columns; the actual Cells row supplies the usable tracks.
local STOPS = { compact = 3, regular = 6, wide = 12 }
local CELLS = {
	{ id = "Standings", label = "Standings", span = { compact = 3, regular = 4, wide = 6 } },
	{ id = "Lap", label = "Lap times", span = { compact = 3, regular = 2, wide = 3 } },
	{ id = "Media", label = "Replays" },
	{ id = "Notes", label = "Notes", span = 12 },
}
return {
	title = "Measured container grid",
	build = function(ctx)
		local Facet, UI, Compose = ctx.Facet, ctx.UI, ctx.Compose
		local sidebarWidth, showDebug, mediaSpan = Compose.cell(360), Compose.cell(false), Compose.cell(4)
		local panels = {}
		local function ContainerGrid(id, widthSpec)
			local width, content = Compose.cell(0), Compose.cell(0)
			local layout = Compose.formula(function(use)
				local metrics = use(ctx.env:get("themeMetrics")) or Facet.themes.neutral()
				local class = Facet.adaptive.sizeClass(use(width))
				local columns = STOPS[class]
				local gutter = metrics.space.s
				return {
					class = class,
					columns = columns,
					margin = metrics.space.m,
					gutter = gutter,
					lane = math.max(1, math.floor((use(content) - gutter * (columns - 1)) / columns)),
				}
			end)
			local state = { bands = {} }
			panels[id] = state
			Compose.cleanup(function()
				if panels[id] == state then
					panels[id] = nil
				end
			end)
			local function spanOf(cell, use)
				local grid = use(layout)
				local declared = if cell.id == "Media" then use(mediaSpan) else cell.span
				if type(declared) == "table" then
					declared = declared[grid.class]
				end
				return math.clamp(math.floor(declared or 1), 0, grid.columns)
			end
			local cells = {}
			for _, cell in CELLS do
				table.insert(
					cells,
					UI.When("Slot" .. cell.id)({
						condition = function(use)
							return spanOf(cell, use) > 0
						end,
						thenView = function()
							return UI.ZStack(cell.id)({
								surface = "control",
								width = function(use)
									local span, grid = spanOf(cell, use), use(layout)
									return { type = "fixed", px = span * grid.lane + (span - 1) * grid.gutter }
								end,
								height = { type = "minMax", min = 44 },
								alignH = "center",
								alignV = "center",
								UI.Text("Label")({ text = cell.label, textSize = "label", padding = "xs" }),
							})
						end,
					})
				)
			end
			local body = UI.HStack("Cells")({
				width = UI.fill(),
				wrap = true,
				gap = function(use)
					return use(layout).gutter
				end,
				table.unpack(cells),
			})
			local overlay = UI.When("DebugOverlay")({
				condition = showDebug,
				thenView = function()
					return UI.HStack("Lanes")({
						width = UI.fill(),
						height = UI.fill(),
						gap = function(use)
							return use(layout).gutter
						end,
						UI.ForEach("Bands")({
							items = function(use)
								local items = {}
								for index = 1, use(layout).columns do
									table.insert(items, index)
								end
								return items
							end,
							key = function(index)
								return index
							end,
							row = function(index)
								return UI.Box("Lane" .. index)({
									surface = "accent",
									opacity = 0.25,
									height = UI.fill(),
									width = function(use)
										return { type = "fixed", px = use(layout).lane }
									end,
									onAppear = function(path)
										state.bands[index] = path
									end,
									onDisappear = function()
										state.bands[index] = nil
									end,
								})
							end,
						}),
					})
				end,
			})
			local root = UI.VStack(id)({
				width = widthSpec,
				gap = "s",
				surface = "raised",
				padding = function(use)
					local grid = use(layout)
					return { left = grid.margin, right = grid.margin, top = grid.gutter, bottom = grid.gutter }
				end,
				UI.When("CaptionSlot")({
					condition = function(use)
						return use(width) > 0
					end,
					thenView = function()
						return UI.Text("Caption")({
							text = function(use)
								local grid = use(layout)
								return `{grid.class} · {math.floor(use(width))}px · {grid.columns} columns`
							end,
							textSize = "caption",
							role = "secondary",
							width = UI.fill(),
						})
					end,
				}),
				UI.ZStack("Grid")({ width = UI.fill(), height = UI.hug(), overlay, body }),
			})
			return Facet.contribution.attach(root, {
				bindController = function(controller)
					state.controller = controller
				end,
				syncGeometry = function(rectOf, node)
					if not node then
						return
					end
					state.path = node.path
					local outer, row = rectOf(node.path), rectOf(node.path .. "/Grid/Cells")
					if outer and outer.w > 0 and outer.w ~= width:peek() then
						width:set(outer.w)
					end
					if row and row.w > 0 and row.w ~= content:peek() then
						content:set(row.w)
					end
				end,
			})
		end
		local function readPanel(id)
			local state = panels[id]
			if not state or not state.path or not state.controller then
				return {}
			end
			local controller, root = state.controller, state.path
			-- Geometry publishes the new column count; the following commit mounts its bands.
			ctx.presenter.refresh()
			ctx.presenter.refresh()
			local outer, row = controller.rectOf(root), controller.rectOf(root .. "/Grid/Cells")
			if not outer then
				return {}
			end
			local text = controller.textAt(root .. "/CaptionSlot/then/Caption")
			local cells, rects, bands = {}, {}, 0
			for _, cell in CELLS do
				local rect = controller.rectOf(root .. "/Grid/Cells/Slot" .. cell.id .. "/then/" .. cell.id)
				if rect then
					table.insert(cells, cell.id)
					rects[cell.id] = rect
				end
			end
			for _, path in state.bands do
				if controller.rectOf(path) then
					bands += 1
				end
			end
			return {
				width = outer.w,
				rowWidth = if row then row.w else nil,
				row = row,
				rects = rects,
				cells = cells,
				bands = bands,
				columns = STOPS[Facet.adaptive.sizeClass(outer.w)],
				caption = if text then text.text else nil,
			}
		end
		local function report()
			return { Sidebar = readPanel("Sidebar"), Column = readPanel("Column"), Board = readPanel("Board") }
		end
		local function section()
			return UI.VStack("GridRecipe")({
				width = UI.fill(),
				gap = "m",
				UI.Text("Title")({ text = "One screen, three containers", textSize = "heading", width = UI.fill() }),
				UI.Text("Note")({
					text = "Each panel reads its own width; its cells use the actual space inside the frame.",
					width = UI.fill(),
				}),
				UI.HStack("Actions")({
					wrap = true,
					gap = "s",
					UI.Button("Resize")({
						label = "Resize sidebar",
						onActivate = function()
							sidebarWidth:set(if sidebarWidth:peek() == 360 then 720 else 360)
						end,
					}),
					UI.Button("Debug")({
						label = "Toggle grid guides",
						onActivate = function()
							showDebug:set(not showDebug:peek())
						end,
					}),
					UI.Button("Media")({
						label = "Toggle replays",
						onActivate = function()
							mediaSpan:set(if mediaSpan:peek() == 0 then 4 else 0)
						end,
					}),
				}),
				UI.VStack("Panels")({
					width = UI.fill(),
					gap = "m",
					ContainerGrid("Sidebar", function(use)
						return { type = "fixed", px = use(sidebarWidth) }
					end),
					ContainerGrid("Column", { type = "fixed", px = 600 }),
					ContainerGrid("Board", { type = "fixed", px = 1040 }),
				}),
			})
		end
		return {
			section = section,
			screen = function()
				return UI.Screen("ContainerGrid")({
					surface = "base",
					padding = { top = "m", bottom = "m" },
					UI.ScrollView("Content")({
						width = UI.fill(),
						height = UI.fill(),
						padding = { left = "m", right = "m" },
						section(),
					}),
				})
			end,
			report = report,
			steps = {
				grow = function()
					sidebarWidth:set(720)
					return readPanel("Sidebar")
				end,
				wide = function()
					sidebarWidth:set(1040)
					return readPanel("Sidebar")
				end,
				shrink = function()
					sidebarWidth:set(360)
					return readPanel("Sidebar")
				end,
				hideMedia = function()
					mediaSpan:set(0)
					return readPanel("Board")
				end,
				showMedia = function()
					mediaSpan:set(4)
					return readPanel("Board")
				end,
				debugOn = function()
					showDebug:set(true)
					return report()
				end,
				debugOff = function()
					showDebug:set(false)
					return report()
				end,
			},
			reset = function()
				sidebarWidth:set(360)
				showDebug:set(false)
				mediaSpan:set(4)
			end,
		}
	end,
}
