--!strict
local COPY = {
	title = "Containers",
	sizing = "Sizing: fixed, a quarter, fill",
	ratios = "Aspect ratios in the same 96 x 96 offer",
	align = "Alignment moves a child through spare room",
	spacing = "Gap and a left-heavy padding",
	wrap = "Wrap, or no wrap inside a sideways scroller",
	style = "Rounding, stroke and shadow",
	scale = "Scale 0.75 / 1 / 1.5 paints, never moves",
	fade = "Group transparency 0 to 1",
	keep = "Hide a node and keep its space, or remove it",
	child = "Child",
	group = "One activation in a group",
	disable = "Disable the group",
}

return {
	title = "Containers (View recipes)",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx)
		local UI, Compose, Host = ctx.UI, ctx.Compose, ctx.Host
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Enum = Enum }
		local UDim, UDim2, Enum = nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Enum
		local copy = ctx.copy or COPY
		local groupEnabled = Compose.cell(true)
		local reserved = Compose.cell(true)
		local presses = Compose.cell(0)
		local function heading(name: string, text: string)
			return UI.Text({ Name = name, text = text, textRole = "label" })
		end
		local function tile(name: string, width: number?, height: number?, extra: any?)
			local node = Host.Frame({
				Name = name,
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(width or 24, height or 24),
				extra,
			})
			node:AddTag("facet-fill")
			return node
		end
		local function screen()
			local ratios = {}
			for index, ratio in { 1, 16 / 9, 9 / 16 } do
				table.insert(
					ratios,
					UI.ZStack({
						Name = `Offer{index}`,
						width = 96,
						height = 96,
						alignH = "center",
						alignV = "center",
						tile("Subject", 96 * math.min(1, ratio), 96 / math.max(1, ratio)),
					})
				)
			end
			local spots = {}
			for _, v in { "start", "center", "end" } do
				for _, h in { "start", "center", "end" } do
					table.insert(
						spots,
						UI.ZStack({
							Name = `{h}-{v}`,
							width = 48,
							height = 48,
							alignH = h,
							alignV = v,
							tile("Dot", 16, 16),
						})
					)
				end
			end
			local function three()
				return { tile("One", 72), tile("Two", 72), tile("Three", 72) }
			end
			local scales = {}
			for index, scale in { 0.75, 1, 1.5 } do
				local scaled = tile("Tile", 32, 32, Host.UIScale({ Scale = scale }))
				table.insert(
					scales,
					UI.ZStack({
						Name = `Scale{index}`,
						width = 48,
						height = 48,
						alignH = "center",
						alignV = "center",
						scaled,
					})
				)
			end
			local fades = {}
			for index, transparency in { 0, 0.25, 0.5, 0.75, 1 } do
				table.insert(
					fades,
					Host.CanvasGroup({
						Name = `Fade{index}`,
						BackgroundTransparency = 1,
						GroupTransparency = transparency,
						Size = UDim2.fromOffset(0, 0),
						AutomaticSize = Enum.AutomaticSize.XY,
						UI.VStack({
							Name = "Inner",
							gap = "xs",
							UI.Text({ Name = "Child", text = copy.child }),
							tile("Bar", 40),
						}),
					})
				)
			end
			local styled = Host.Frame({
				Name = "Styled",
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(120, 56),
				Host.UICorner({
					TopLeftRadius = UDim.new(0, 16),
					TopRightRadius = UDim.new(0, 0),
					BottomLeftRadius = UDim.new(0, 0),
					BottomRightRadius = UDim.new(0, 16),
				}),
				Host.UIStroke({ Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
				Host.UIShadow({ Name = "Shadow" }),
			})
			styled:AddTag("facet-panel")
			local group = Host.Frame({
				Name = "Group",
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(0, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
				Interactable = groupEnabled,
				Host.UIPadding({
					PaddingTop = UDim.new(0, 8),
					PaddingBottom = UDim.new(0, 8),
					PaddingLeft = UDim.new(0, 8),
					PaddingRight = UDim.new(0, 8),
				}),
				UI.Button({
					Name = "Activate",
					label = copy.group,
					onActivate = function()
						presses:update(function(count)
							return count + 1
						end)
					end,
				}),
			})
			group:AddTag("facet-panel")
			return UI.ScrollView({
				Name = "Containers",
				gap = "m",
				padding = "m",
				UI.Text({ Name = "Title", text = copy.title, textRole = "heading" }),
				heading("GroupTitle", copy.group),
				group,
				UI.Toggle({ Name = "GroupEnabled", label = copy.disable, value = groupEnabled }),
				heading("SizingTitle", copy.sizing),
				UI.HStack({
					Name = "Sizing",
					width = "fill",
					gap = "s",
					tile("Fixed", 64),
					(function()
						local quarter = tile("Quarter")
						quarter.Size = UDim2.new(0.25, 0, 0, 24)
						return quarter
					end)(),
					(function()
						local fill = Host.Frame({
							Name = "Fill",
							BorderSizePixel = 0,
							Size = UDim2.new(0, 0, 0, 24),
							UI.fill(),
						})
						fill:AddTag("facet-fill")
						return fill
					end)(),
				}),
				heading("RatiosTitle", copy.ratios),
				UI.HStack({ Name = "Ratios", gap = "s", wrap = true, table.unpack(ratios) }),
				heading("AlignTitle", copy.align),
				UI.HStack({ Name = "Align", gap = "xs", wrap = true, width = "fill", table.unpack(spots) }),
				heading("SpacingTitle", copy.spacing),
				UI.HStack({ Name = "Gap", gap = "xl", tile("A"), tile("B"), tile("C") }),
				(function()
					local padded = UI.VStack({
						Name = "Padding",
						padding = { top = 8, bottom = 8, left = 32, right = 8 },
						tile("Inset"),
					})
					padded:AddTag("facet-panel")
					return padded
				end)(),
				heading("WrapTitle", copy.wrap),
				UI.HStack({ Name = "Wrap", width = 180, wrap = true, gap = "xs", table.unpack(three()) }),
				UI.ScrollView({
					Name = "NoWrap",
					axis = "x",
					width = 180,
					height = 32,
					gap = "xs",
					table.unpack(three()),
				}),
				heading("StyleTitle", copy.style),
				styled,
				heading("ScaleTitle", copy.scale),
				UI.HStack({ Name = "Scales", gap = "xl", table.unpack(scales) }),
				heading("FadeTitle", copy.fade),
				UI.HStack({ Name = "Fades", gap = "s", wrap = true, table.unpack(fades) }),
				heading("KeepTitle", copy.keep),
				UI.Toggle({ Name = "Reserved", label = copy.keep, value = reserved }),
				UI.HStack({
					Name = "Keep",
					gap = "s",
					Host.CanvasGroup({
						Name = "Kept",
						BackgroundTransparency = 1,
						Size = UDim2.fromOffset(48, 24),
						GroupTransparency = function(use)
							return if use(reserved) then 0 else 1
						end,
						Interactable = reserved,
						tile("KeptTile", 48),
					}),
					Compose.show(reserved, function()
						return tile("Removed", 48)
					end),
					tile("After", 48),
				}),
			})
		end
		return {
			screen = screen,
			steps = {
				disable = function()
					groupEnabled:set(false)
				end,
				hide = function()
					reserved:set(false)
				end,
			},
			report = function()
				return { presses = presses:peek(), enabled = groupEnabled:peek(), reserved = reserved:peek() }
			end,
		}
	end,
}
