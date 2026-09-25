return {
	title = "World markers",
	build = function(ctx)
		local Host, UI, Compose = ctx.Host, ctx.UI, ctx.Compose
		local D, D2, V2, C3, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2, ctx.types.Color3, ctx.types.Enum
		local shifted, crowded, hidden = Compose.cell(false), Compose.cell(false), Compose.cell(false)
		local size = Compose.cell(V2.new(320, 360))
		local selected = Compose.cell("Choose a marker")
		local geometry = Compose.formula(function(use)
			local box = use(size)
			local width, height = math.max(96, box.X), math.max(240, box.Y)
			local rows = {}
			for index, name in { "Objective", "Ally", "Supplies" } do
				local x = width * (if index == 1 and use(shifted) then 1.4 else if index == 3 then 0.62 else 0.6)
				local y = height
					* (if use(crowded) then 0.5 elseif index == 1 then 0.5 elseif index == 2 then 0.3 else 0.72)
				local clamped = math.clamp(x - 32, 8, width - 72)
				local top = math.clamp(y - 24, 64, height - 56)
				for _, previous in rows do
					if previous.visible and math.abs(previous.x - clamped) < 72 and math.abs(previous.y - top) < 56 then
						top = previous.y + 56
					end
				end
				if top > height - 56 then
					top = math.max(64, rows[1].y - 56 * (index - 1))
				end
				rows[index] = {
					id = ({ "A", "B", "C" })[index],
					label = name,
					x = clamped,
					y = top,
					edge = x > width or x < 0,
					visible = index ~= 3 or not use(hidden),
					width = 64,
					height = 48,
				}
			end
			return rows
		end)
		local function screen()
			local pins = {}
			for index, name in { "A", "B", "C" } do
				table.insert(
					pins,
					UI.Button({
						Name = name,
						label = name,
						Size = D2.fromOffset(64, 48),
						Position = function(use)
							local row = use(geometry)[index]
							return D2.fromOffset(row.x, row.y)
						end,
						Visible = function(use)
							return use(geometry)[index].visible and (not ctx.pageVisible or use(ctx.pageVisible))
						end,
						onActivate = function()
							selected:set(geometry:peek()[index].label)
						end,
						Host.ImageLabel "Direction" {
							BackgroundTransparency = 1,
							Size = D2.fromOffset(16, 16),
							Position = D2.new(1, -18, 0.5, -8),
							Image = "rbxasset://textures/ui/Controls/DropDownArrow.png",
							Rotation = -90,
							Visible = function(use)
								return use(geometry)[index].edge
							end,
						},
					})
				)
			end
			local map = Host.Frame "Map" {
				Size = D2.new(1, 0, 0, 360),
				BackgroundTransparency = 1,
				Host.Frame "HudReservation" {
					Size = D2.new(1, 0, 0, 56),
					BackgroundColor3 = C3.fromRGB(32, 45, 65),
					BorderSizePixel = 0,
					UI.Text({
						text = "HUD reservation — markers stay below this band",
						Size = D2.fromScale(1, 1),
						TextWrapped = true,
					}),
				},
				table.unpack(pins),
			}
			local function measure()
				if map.AbsoluteSize.X > 0 then
					size:set(map.AbsoluteSize)
				end
			end
			measure()
			local connection = map:GetPropertyChangedSignal("AbsoluteSize"):Connect(measure)
			Compose.cleanup(function()
				connection:Disconnect()
			end)
			return Host.ScrollingFrame "WorldMarkers" {
				Size = D2.fromScale(1, 1),
				BackgroundTransparency = 1,
				AutomaticCanvasSize = E.AutomaticSize.Y,
				CanvasSize = D2.new(),
				Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder, Padding = D.new(0, 12) }),
				UI.Text({ text = "A · Objective   B · Ally   C · Supplies", TextWrapped = true }),
				map,
				UI.Toggle "Move" { label = "Move objective offscreen", value = shifted },
				UI.Toggle "Crowd" { label = "Bring markers together", value = crowded },
				UI.Toggle "Hide" { label = "Occlude supplies", value = hidden },
				UI.Text "Selected" { text = selected, TextWrapped = true },
			}
		end
		return {
			screen = screen,
			report = function()
				return {
					markers = geometry:peek(),
					shifted = shifted:peek(),
					crowded = crowded:peek(),
					hidden = hidden:peek(),
					selected = selected:peek(),
				}
			end,
		}
	end,
}
