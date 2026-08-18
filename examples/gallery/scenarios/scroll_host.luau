--!strict
-- Scenario 'scroll_host' (ledger row NS-A2): UI.ScrollView rides a native
-- ScrollingFrame — the solver owns every content rect and the canvas extent;
-- the ENGINE owns scrolling (wheel/touch/momentum/bars) and clipping.
-- Fallback A/B (NS-I2): run again with workspace attribute
-- Facet_ForceScrollFallback=true — same blueprint, clip-only Frame host.
--
-- Native-input rows are driven by the MCP's real wheel injection OVER the
-- list, not by steps; the steps here are labeled programmatic drivers.
--
-- The three demo regions (List/Strip/FocusList) size by a `fill` weight
-- share of the page, not a fixed px, so the page itself never overflows the
-- viewport (overflow_sweep, device bug round 2026-08-12) — see the comment
-- at their declaration below.

return {
	title = "Native scroll host (NS-A2)",
	ledgerRows = { "NS-A2", "NS-I2" },
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI = Facet.UI
		local scope = ctx.core:scope("scroll-host")
		-- "the vertical room is scarce", the framework's own Readable for it
		-- (`adaptive.HEIGHT_BREAKPOINTS`, ADR-0023) — a Readable, so a rotation
		-- re-resolves it instead of freezing whichever orientation booted first
		local conditions = Facet.adaptive.conditions(ctx.core, ctx.env, { scope = scope })
		local showTitle = scope:own(ctx.core:memo(function(use)
			return not use(conditions.isShort)
		end))

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
				--[[ THE TITLE GOES WHEN THE ROOM DOES (O-21, measured 2026-08-15) —
					the same call `row_actions` makes, for the same reason: the demo
					picker's own chip already names this demo on screen, so on a short
					viewport it is the one piece of chrome that says nothing the player
					cannot already see. At +14 on a 640x320 landscape the four labels on
					this page came to 194px of a 168px content box with all three regions
					already windowed to ZERO, and the `BELOW-LIST MARKER` — the node this
					fixture asserts must never move — ended 10px under the fold. ]]
				UI.When({
					id = "TitleWhen",
					condition = showTitle,
					thenView = function()
						return UI.Text({ id = "Title", text = "Native scroll host", textSize = 22 })
					end,
				}),
				-- The three demo regions below used to be FIXED px (260/56/140) —
				-- taller together than a short landscape phone's whole safe area,
				-- with nothing to scroll the PAGE (overflow_sweep, device bug round
				-- 2026-08-12). Wrapping the page in a second y-ScrollView would nest
				-- a y-scroller inside the y-scrollers this fixture exists to prove
				-- (NS-A2/NS-I2/A-SV1), so instead each region states its SHARE of
				-- whatever height the viewport actually has (`fill`, weighted
				-- roughly by its original px so List stays the tallest demo and
				-- Strip the shortest) rather than a constant that stops fitting
				-- below ~640px. Every region's own content (20/12/15 items) still
				-- outgrows its box at any weight share, so the scroll/keep-visible
				-- behavior under test is unchanged — only the box gets smaller.
				UI.ScrollView({
					id = "List",
					height = { type = "fill", weight = 3 },
					width = { type = "fixed", px = 280 },
					padding = 8,
					gap = 0,
					children = rows,
				}),
				-- the two region labels go with the title, and for the same 26px: with
				-- only the title gone the LIST region came out 13px tall against 8+8 of
				-- its own padding, i.e. a scroll host with no content box at all. Three
				-- regions that read at 55/18/37px beat four labels over nothing.
				UI.When({
					id = "StripLabelWhen",
					condition = showTitle,
					thenView = function()
						return UI.Text({
							id = "StripLabel",
							text = "horizontal axis",
							textSize = 14,
							role = "secondary",
						})
					end,
				}),
				UI.ScrollView({
					id = "Strip",
					axis = "x",
					gap = 8,
					width = { type = "fixed", px = 280 },
					height = { type = "fill", weight = 1 },
					children = strip,
				}),
				UI.When({
					id = "KeepLabelWhen",
					condition = showTitle,
					thenView = function()
						return UI.Text({
							id = "KeepLabel",
							text = "keep-visible (focusable rows)",
							textSize = 14,
							role = "secondary",
						})
					end,
				}),
				UI.ScrollView({
					id = "FocusList",
					height = { type = "fill", weight = 2 },
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
