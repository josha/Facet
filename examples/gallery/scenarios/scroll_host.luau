--!strict
-- Scenario 'scroll_host' (ledger row NS-A2): UI.ScrollView rides a native
-- ScrollingFrame — the solver owns every content rect and the canvas extent;
-- the ENGINE owns scrolling (wheel/touch/momentum/bars) and clipping.
-- Fallback A/B (NS-I2): run again with workspace attribute
-- LuauUI_ForceScrollFallback=true — same blueprint, clip-only Frame host.
--
-- Native-input rows are driven by the MCP's real wheel injection OVER the
-- list, not by steps; the steps here are labeled programmatic drivers.

return {
	title = "Native scroll host (NS-A2)",
	ledgerRows = { "NS-A2", "NS-I2" },
	build = function(ctx: any)
		local UI = ctx.LuauUI.UI

		local rows = {}
		for i = 1, 20 do
			table.insert(
				rows,
				UI.Text({
					id = "Row" .. i,
					text = "List row " .. i,
					textSize = 18,
					height = { type = "fixed", px = 36 },
				})
			)
		end

		-- A-SV1: the HORIZONTAL axis, and focusable rows so the shared
		-- keep-visible substrate can be driven through real navigation
		local strip = {}
		for i = 1, 12 do
			table.insert(
				strip,
				UI.Box({
					id = "Cell" .. i,
					surface = "control",
					width = { type = "fixed", px = 70 },
					height = { type = "fill", weight = 1 },
				})
			)
		end
		local focusRows = {}
		for i = 1, 15 do
			table.insert(
				focusRows,
				UI.Button({
					id = "Focus" .. i,
					label = "Focusable " .. i,
					height = { type = "fixed", px = 44 },
					width = { type = "fill", weight = 1 },
				})
			)
		end

		local screen = UI.Screen({
			id = "ScrollHost",
			padding = 16,
			gap = 8,
			children = {
				UI.Text({ id = "Title", text = "Native scroll host", textSize = 22 }),
				UI.ScrollView({
					id = "List",
					height = { type = "fixed", px = 260 },
					width = { type = "fixed", px = 280 },
					padding = 8,
					gap = 0,
					children = rows,
				}),
				UI.Text({ id = "StripLabel", text = "horizontal axis", textSize = 14, role = "secondary" }),
				UI.ScrollView({
					id = "Strip",
					axis = "x",
					gap = 8,
					width = { type = "fixed", px = 280 },
					height = { type = "fixed", px = 56 },
					children = strip,
				}),
				UI.Text({ id = "KeepLabel", text = "keep-visible (focusable rows)", textSize = 14, role = "secondary" }),
				UI.ScrollView({
					id = "FocusList",
					height = { type = "fixed", px = 140 },
					width = { type = "fixed", px = 280 },
					gap = 2,
					children = focusRows,
				}),
				UI.Text({ id = "Below", text = "BELOW-LIST MARKER (must never move)", textSize = 14 }),
			},
		})

		return {
			screen = screen,
			present = {},
			steps = {
				-- programmatic keep-visible write (framework's only scroll write)
				scrollToBottom = function(built: any)
					built.handle.controller.scrollTo("/ScrollHost/List", { x = 0, y = 100000 })
					return true
				end,
				scrollToTop = function(built: any)
					built.handle.controller.scrollTo("/ScrollHost/List", { x = 0, y = 0 })
					return true
				end,
				-- A-SV1: the shared keep-visible substrate, on both axes. These
				-- are programmatic drivers; the NATIVE-input proof is the real
				-- wheel/navigation injection paired with these offsets.
				keepVisibleFar = function(built: any)
					local c = built.handle.controller
					local moved = c.scrollToVisible("/ScrollHost/FocusList/Focus13")
					return { moved = moved, offset = c.scrollPosition("/ScrollHost/FocusList") }
				end,
				keepVisibleAlreadyVisible = function(built: any)
					local c = built.handle.controller
					c.scrollTo("/ScrollHost/FocusList", { x = 0, y = 0 })
					local moved = c.scrollToVisible("/ScrollHost/FocusList/Focus1")
					return { moved = moved, offset = c.scrollPosition("/ScrollHost/FocusList") }
				end,
				keepVisibleHorizontal = function(built: any)
					local c = built.handle.controller
					local moved = c.scrollToVisible("/ScrollHost/Strip/Cell11")
					return { moved = moved, offset = c.scrollPosition("/ScrollHost/Strip") }
				end,
				readOffsets = function(built: any)
					local c = built.handle.controller
					return {
						list = c.scrollPosition("/ScrollHost/List"),
						strip = c.scrollPosition("/ScrollHost/Strip"),
						focusList = c.scrollPosition("/ScrollHost/FocusList"),
					}
				end,
			},
			report = function()
				return { rowCount = 20, rowHeight = 36, pad = 8, stripCells = 12, focusRows = 15 }
			end,
		}
	end,
}
