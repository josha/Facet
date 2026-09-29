--!strict
return {
	{
		id = "table-scrollbar-and-large-heading-resize",
		contracts = {},
		run = function(t)
			for _, theme in t.themes do
				if theme.name ~= "Neutral" and theme.name ~= "scifi_hud" then
					continue
				end
				for _, scale in { 0.75, 1.5 } do
					local widths, runtime, Host, container
					local stage = t.mount(function(UI, constructors, Compose, env)
						runtime, Host = env.runtime, constructors
						widths = Compose.cell({ name = 140, laps = 72 })
						local rows = {}
						for index = 1, 30 do
							table.insert(rows, { id = index, name = "Driver " .. index, laps = 3 })
						end
						container = Host.Frame {
							Size = UDim2.fromOffset(460, 300),
							Host.UIScale { Scale = scale },
							UI.Table "Results" {
								from = rows,
								key = function(row)
									return row.id
								end,
								widths = widths,
								columns = {
									{
										id = "name",
										label = "Driver",
										render = function(row)
											return UI.Text {
												text = function(use)
													return use(row).name
												end,
											}
										end,
									},
									{
										id = "laps",
										label = "Laps completed",
										render = function(row)
											return UI.Text {
												text = function(use)
													return tostring(use(row).laps)
												end,
											}
										end,
									},
								},
							},
						}
						return container
					end, {
						theme = theme.package,
						size = Vector2.new(960, 720),
						environment = {
							preferredInput = "Gamepad",
							displaySize = "Large",
							preferredTextSize = "Largest",
						},
					})
					local tableNode = t.find(stage, "Results")
					local body, header = tableNode.Body, tableNode.Header
					body.VerticalScrollBarInset = Enum.ScrollBarInset.Always
					body.ScrollBarThickness = 12
					local heading = header.laps.Sort
					heading.TextSize = 48
					for _, width in { 72, 230, 90, 520, 300 } do
						widths:set({ name = 140, laps = width })
						t.settle(8)
						body.CanvasPosition = Vector2.new(if width > 300 then 60 else 0, 0)
						t.settle(3)
						local label = `{theme.name}/{scale}/{width}`
						t.check(
							label .. " large heading has vertical room",
							header.AbsoluteSize.Y >= heading.TextBounds.Y + 15 * scale
						)
						if width > 300 then
							t.near(label .. " canvas reaches the last column", body.CanvasSize.X.Offset, 140 + width, 1)
						end
						local row = body:FindFirstChild("1", true)
						local cell = row and row:FindFirstChild("laps", true)
						t.check(label .. " body column is present", cell ~= nil)
						if cell then
							t.near(
								label .. " scrolled heading aligns with its column",
								header.laps.AbsolutePosition.X,
								cell.AbsolutePosition.X,
								1
							)
						end
						t.near(label .. " column accepts logical width", header.laps.AbsoluteSize.X, width * scale, 1)
						t.near(
							label .. " heading follows resized cell",
							heading.AbsoluteSize.X,
							header.laps.AbsoluteSize.X,
							1
						)
						t.near(
							label .. " header band covers scrollbar",
							t.rect(tableNode.HeaderBand).r,
							t.rect(body).r,
							1
						)
						local stop, fresh = runtime.mount(function()
							local padding = heading:FindFirstChildWhichIsA("UIPadding")
							return Host.TextLabel "FreshHeading" {
								Text = heading.Text,
								TextSize = heading:GetStyled("TextSize"),
								FontFace = heading:GetStyled("FontFace"),
								TextWrapped = heading.TextWrapped,
								TextTruncate = heading.TextTruncate,
								Size = UDim2.fromOffset(heading.AbsoluteSize.X / scale, heading.AbsoluteSize.Y / scale),
								TextTransparency = 1,
								BackgroundTransparency = 1,
								if padding
									then Host.UIPadding {
										PaddingLeft = padding:GetStyled("PaddingLeft"),
										PaddingRight = padding:GetStyled("PaddingRight"),
										PaddingTop = padding:GetStyled("PaddingTop"),
										PaddingBottom = padding:GetStyled("PaddingBottom"),
									}
									else nil,
							}
						end, container)
						t.settle(3)
						t.near(
							label .. " truncation matches freshly drawn text",
							heading.TextBounds.X,
							fresh.TextBounds.X,
							1
						)
						stop()
					end
					t.cleanup()
				end
			end
		end,
	},
}
