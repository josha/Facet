--!strict
--[[ Containers: what a catchall "View" offers, as recipes over the primitives
	(docs/guide/17-recipes.md §17.7). Sizing, a known-offer contain for three
	aspect ratios, nine alignments, gap and per-edge padding, wrap / no-wrap /
	sideways scroll, rounding with a stroke and a shadow, paint scale and group
	opacity. Each section is ordinary layout; `tests/view_recipes.spec.luau`
	asserts the same recipes' solved rects, including the deliberate no-wrap
	overrun and the clip this page does not paint (the overflow sweep treats
	content cut off at a clip edge as a defect, as a player would). ]]
local COPY = {
	sizing = "Sizing: fixed, a quarter, fill",
	ratios = "Aspect ratios in the same 96 x 96 offer",
	align = "Alignment moves a child through spare room",
	spacing = "Gap and a left-heavy padding",
	wrap = "Wrap, or no wrap inside a sideways scroller",
	style = "Rounding, stroke and shadow",
	scale = "Scale 0.75 / 1 / 1.5 paints, never moves",
	fade = "Group opacity 1 to 0",
	child = "Child",
}

-- tinted faces, not themed surfaces: a package's control chrome carries its
-- own insets, which a 16 px tile has no room for
local ACCENT = { role = "accent", blend = 1 }
local PLATE = { role = "surfaceStrong", blend = 1 }

local function fixed(px: number): any
	return { type = "fixed", px = px }
end

return {
	title = "Containers (View recipes)",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: any)
		local UI = ctx.UI
		local function heading(id: string, text: string): any
			return UI.Text(id)({ text = text, textSize = "label", width = UI.fill() })
		end
		local function tile(id: string, px: number?): any
			return UI.Box(id)({ width = fixed(px or 24), height = fixed(24), tint = ACCENT })
		end

		-- built per mount, under the screen's own owner
		local screen = function()
			local ratios = {}
			for i, r in { 1, 16 / 9, 9 / 16 } do
				table.insert(
					ratios,
					UI.ZStack(`Offer{i}`)({
						width = fixed(96),
						height = fixed(96),
						alignH = "center",
						alignV = "center",
						UI.Box("Subject")({
							width = fixed(96 * math.min(1, r)),
							height = fixed(96 / math.max(1, r)),
							tint = ACCENT,
						}),
					})
				)
			end
			local spots = {}
			for _, v in { "start", "center", "end" } do
				for _, h in { "start", "center", "end" } do
					table.insert(
						spots,
						UI.ZStack(`{h}-{v}`)({
							width = fixed(48),
							height = fixed(48),
							alignH = h,
							alignV = v,
							tile("Dot", 16),
						})
					)
				end
			end
			local function three(): { any }
				return { tile("One", 72), tile("Two", 72), tile("Three", 72) }
			end
			local scales = {}
			for i, s in { 0.75, 1, 1.5 } do
				table.insert(scales, UI.ZStack(`Scale{i}`)({ scale = s, tile("Tile", 32) }))
			end
			local fades = {}
			for i, o in { 1, 0.75, 0.5, 0.25, 0 } do
				table.insert(
					fades,
					UI.ZStack(`Fade{i}`)({
						opacity = o,
						UI.VStack("Inner")({
							gap = "xs",
							UI.Text("Child")({ text = COPY.child }),
							tile("Bar", 40),
						}),
					})
				)
			end

			return UI.Screen("Containers")({
				surface = "base",
				padding = { top = "m", bottom = "m" },
				UI.ScrollView("Content")({
					width = UI.fill(),
					height = UI.fill(),
					padding = { left = "m", right = "m" },
					gap = "m",
					heading("SizingTitle", COPY.sizing),
					UI.HStack("Sizing")({
						width = UI.fill(),
						gap = "s",
						tile("Fixed", 64),
						UI.Box("Quarter")({
							width = { type = "percent", fraction = 0.25 },
							height = fixed(24),
							tint = ACCENT,
						}),
						UI.Box("Fill")({ width = UI.fill(), height = fixed(24), tint = ACCENT }),
					}),
					heading("RatiosTitle", COPY.ratios),
					UI.HStack("Ratios")({ gap = "s", wrap = true, table.unpack(ratios) }),
					heading("AlignTitle", COPY.align),
					UI.HStack("Align")({ gap = "xs", wrap = true, width = UI.fill(), table.unpack(spots) }),
					heading("SpacingTitle", COPY.spacing),
					UI.HStack("Gap")({ gap = "xl", tile("A"), tile("B"), tile("C") }),
					UI.VStack("Padding")({
						surface = "raised",
						padding = { top = 8, bottom = 8, left = 32, right = 8 },
						tile("Inset"),
					}),
					heading("WrapTitle", COPY.wrap),
					UI.HStack("Wrap")({ width = fixed(180), wrap = true, gap = "xs", table.unpack(three()) }),
					UI.ScrollView("NoWrap")({
						axis = "x",
						width = fixed(180),
						UI.HStack("Row")({ gap = "xs", table.unpack(three()) }),
					}),
					heading("StyleTitle", COPY.style),
					UI.shadow(
						UI.stroke(
							UI.corners(
								UI.Box("Styled")({ width = fixed(120), height = fixed(56), tint = PLATE }),
								{ topLeft = 16, bottomRight = 16 }
							),
							{ thickness = 2, color = "accent" }
						),
						"raised"
					),
					heading("ScaleTitle", COPY.scale),
					UI.HStack("Scales")({ gap = "xl", overflow = "intentionalOverlap", table.unpack(scales) }),
					heading("FadeTitle", COPY.fade),
					UI.HStack("Fades")({ gap = "s", wrap = true, table.unpack(fades) }),
				}),
			})
		end
		return { screen = screen, steps = {} }
	end,
}
