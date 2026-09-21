--!strict
-- Compare displayed rich text, end/middle fitting, tile/slice art and an xy canvas.
-- Mounted reports read geometry and offsets; controls also work inside All controls.

return {
	title = "Leaf capabilities",
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI, Compose = ctx.UI, ctx.Compose

		local TRACK = "Coastal circuit reverse night lap 14"
		-- a name the app did not author: escaped ONCE, at the composition site
		local GUEST = "Racer <Nightfall> & Co."
		-- Existing 64×64 framework art; both Image modes use the same loaded source.
		local ART = "rbxassetid://133513168894379"

		local frozen = Compose.cell(false)
		local narrow = Compose.cell(true)

		local rootPath: string? = nil
		local function controllerOf(built: any): any
			return if rootPath and built and built.handle then built.handle.controller else nil
		end
		local function solvedNameWidth(built: any, name: string?): number?
			local controller = controllerOf(built)
			if controller == nil then
				return nil
			end
			controller.refresh()
			local rect = controller.rectOf(rootPath .. "/Content/Body/" .. (name or "CutMiddle"))
			return if rect then rect.w else nil
		end
		local function boardOffset(built: any): any
			local controller = controllerOf(built)
			return if controller then controller.scrollPosition(rootPath .. "/Content/Body/Board") else nil
		end

		-- Setup builds once; the recipes read state on every reactive update.
		local function Page()
			local function nameWidth(use)
				return { type = "fixed", px = if use(narrow) then 160 else 320 }
			end

			local board = { UI.Text("BoardNote")({ text = "Touch-drag or scroll in both directions" }) }
			for row = 1, 3 do
				local tiles = {}
				for col = 1, 4 do
					table.insert(
						tiles,
						-- a ZStack, not a Box: a Box is a LEAF, and a tile has to hold
						-- the label that makes the scroll visible
						UI.ZStack(`Tile{row}{col}`)({
							surface = "control",
							width = { type = "fixed", px = 140 },
							height = { type = "minMax", min = 56 },

							UI.Text("Label")({ text = `sector {row}-{col}`, textSize = "label", padding = "xs" }),
						})
					)
				end
				table.insert(board, UI.HStack(`BoardRow{row}`)({ gap = "s", table.unpack(tiles) }))
			end

			return UI.VStack("Body")({
				width = UI.fill(),
				gap = "m",

				UI.Text("Title")({ text = "Leaf capabilities", textSize = "title" }),
				UI.HStack("Actions")({
					gap = "s",
					UI.Button("Width")({
						label = function(use)
							return if use(narrow) then "Widen text" else "Narrow text"
						end,
						onActivate = function()
							narrow:set(not narrow:peek())
						end,
					}),
					UI.Button("Freeze")({
						label = function(use)
							return if use(frozen) then "Thaw canvas" else "Freeze canvas"
						end,
						onActivate = function()
							frozen:set(not frozen:peek())
						end,
					}),
				}),

				UI.Text("MarkupHeading")({ text = "Markup, and the box it reserves", textSize = "heading" }),
				--[[ HUGGING, so the plate IS the reserved box. A fill-width label
						cannot show that a tag did not widen anything, which is what the
						first Studio pass of this fixture could not judge. ]]
				UI.Text("Plain")({ text = "Lap record", surface = "chip", padding = "xs" }),
				--[[ PAINT-ONLY MARKUP, AND A READABLE PAIR. `<mark>` with no colour
						paints the engine's own bright yellow behind whatever the text
						colour is, which on a dark theme is an unreadable band (found on a
						device, 2026-09-18) — so the demo names both halves of the pair.
						The point of the row is that neither of them widens the box. ]]
				UI.Text("Marked")({
					rich = true,
					text = '<mark color="#20304a" transparency="0.2"><font color="#cfe4ff">Lap record</font></mark>',
					surface = "chip",
					padding = "xs",
				}),
				UI.Text("Bold")({ rich = true, text = "<b>Lap record</b>", surface = "chip", padding = "xs" }),
				UI.Text("Heavy")({
					rich = true,
					text = '<font weight="heavy">Lap record</font>',
					surface = "chip",
					padding = "xs",
				}),
				UI.Text("Escaped")({ rich = true, text = "<b>" .. Facet.richText.escape(GUEST) .. "</b> joined" }),
				UI.Text("Rtl")({ direction = "rtl", text = "Direction: right to left" }),

				UI.Text("CutHeading")({ text = "Where the cut goes", textSize = "heading" }),
				UI.Text("CutEnd")({ text = TRACK, lineLimit = 1, disclose = true, width = nameWidth }),
				UI.Text("CutMiddle")({
					text = TRACK,
					truncate = "middle",
					lineLimit = 1,
					disclose = true,
					width = nameWidth,
				}),

				UI.Text("PictureHeading")({ text = "One picture, two modes", textSize = "heading" }),
				UI.HStack("Pictures")({
					gap = "s",

					UI.Image("Tiled")({
						image = ART,
						scaleMode = "tile",
						tileSize = { width = 24, height = 24 },
						resample = "pixelated",
						width = { type = "fixed", px = 96 },
						height = { type = "fixed", px = 64 },
					}),
					UI.Image("Sliced")({
						image = ART,
						scaleMode = "slice",
						sliceCenter = { x0 = 8, y0 = 8, x1 = 56, y1 = 56 },
						width = { type = "fixed", px = 96 },
						height = { type = "fixed", px = 64 },
					}),
				}),

				UI.Text("BoardHeading")({ text = "A canvas with two axes", textSize = "heading" }),
				--[[ A WINDOW NARROWER THAN ITS OWN CANVAS, which is what makes the
						horizontal axis reachable at all: 320 across a 640 extent, 140 down
						a 480 one. The first cut of this fixture was fill-width over a 640
						canvas, so there was nothing to scroll to. ]]
				UI.ScrollView("Board")({
					axis = "xy",
					scrollEnabled = function(use)
						return not use(frozen)
					end,
					extent = { width = 640, height = 480 },
					width = { type = "fixed", px = 320 },
					height = { type = "fixed", px = 140 },
					padding = "s",
					gap = "s",
					table.unpack(board),
				}),
			})
		end

		local built: any
		built = {
			screen = function()
				return UI.Screen("LeafCapabilities")({
					surface = "base",
					onAppear = function(path)
						rootPath = path
					end,
					onDisappear = function()
						rootPath = nil
					end,
					padding = "m",
					UI.ScrollView("Content")({ width = UI.fill(), height = UI.fill(), Page() }),
				})
			end,
			steps = {
				--[[ THE TWO WIDTH STOPS THE MIDDLE CUT IS LEGIBLE BETWEEN, and each
					reports the width the SCREEN has rather than the one it asked for.
					Returning its own request is how this step agreed with itself for
					three rounds while the row it names never moved: an instrument that
					echoes its input can only ever confirm it. ]]
				widen = function(built: any)
					narrow:set(false)
					return { width = solvedNameWidth(built) }
				end,
				narrow = function(built: any)
					narrow:set(true)
					return { width = solvedNameWidth(built) }
				end,
				-- the one thing here no still frame holds: the canvas does not move
				freeze = function(built: any)
					local before = boardOffset(built)
					frozen:set(true)
					return { frozen = true, offsetBefore = before }
				end,
				thaw = function()
					frozen:set(false)
					return { frozen = false }
				end,
			},
			report = function()
				return {
					frozen = frozen:peek(),
					narrow = narrow:peek(),
					track = TRACK,
					guest = GUEST,
					escaped = Facet.richText.escape(GUEST),
					art = ART,
					width = solvedNameWidth(built),
					endWidth = solvedNameWidth(built, "CutEnd"),
					offset = boardOffset(built),
				}
			end,
			reset = function()
				frozen:set(false)
				narrow:set(true)
			end,
		}
		return built
	end,
}
