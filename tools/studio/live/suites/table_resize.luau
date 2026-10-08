--!strict

type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type Case = { id: string, contracts: { string }, keepGallery: boolean?, run: (any) -> () }
local cases: { Case } = {
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
					local stage = t.mount(function(UI: FacetControls, constructors, Compose: ComposeModule, env)
						runtime, Host = env.runtime, constructors
						widths = Compose.cell({ name = 140, laps = 72 })
						local rows = {}
						for index = 1, 30 do
							table.insert(rows, { id = index, name = "Driver " .. index, laps = 3 })
						end
						container = Host.Frame {
							Size = UDim2.fromOffset(460, 300),
							Host.UIScale { Scale = scale } :: unknown,
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
												text = function(use: Use)
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
												text = function(use: Use)
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
					local heading = header.laps.Sort :: TextButton
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
									else nil :: unknown,
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
	{
		id = "playlist-edit-done-frame-rects-390",
		contracts = {},
		keepGallery = false,
		run = function(t: any)
			t.device({ device = "iphone_14", orientation = "Portrait", frames = 30 })
			local input = game:GetService("UserInputService")
			local virtual = input:CreateVirtualInput()
			if virtual == nil then
				t.check("native virtual pointer input is available", false)
				return
			end
			local stage = t.mount(function(UI: FacetControls, Host, Compose: ComposeModule, env)
				local example = require(game.ReplicatedStorage.FacetExamples["02_playlist_table"])
				return example.build(t.context(UI, Host, Compose, env)).screen()
			end, { size = Vector2.new(390, 844), motionLevel = "normal", environment = { preferredInput = "Touch" } })
			local inset = game:GetService("GuiService"):GetGuiInset()
			local shield = Instance.new("TextButton")
			shield.Size = UDim2.fromScale(1, 1)
			shield.BackgroundTransparency, shield.TextTransparency, shield.ZIndex = 1, 1, 10000
			shield.Parent = stage
			local seen: Vector3?
			local delivered: Enum.UserInputType?
			local observer = input.InputBegan:Connect(function(event)
				if
					event.UserInputType == Enum.UserInputType.Touch
					or event.UserInputType == Enum.UserInputType.MouseButton1
				then
					seen = event.Position
					delivered = event.UserInputType
				end
			end)
			local probe = (stage :: Frame).AbsolutePosition + Vector2.new(100, 100) + inset
			virtual:SendMousePosition(probe)
			virtual:SendMouseButton(probe, Enum.UserInputType.MouseButton1, true)
			t.settle(2)
			virtual:SendMouseButton(probe, Enum.UserInputType.MouseButton1, false)
			t.settle(2)
			observer:Disconnect()
			shield:Destroy()
			if seen == nil then
				t.check("calibration delivers real pointer input", false)
				return
			end
			t.check("phone calibration delivers real touch", delivered == Enum.UserInputType.Touch)
			t.note("delivered input", tostring(delivered))
			inset = probe - Vector2.new(seen.X, seen.Y)
			local tableNode = t.find(stage, "Tracks")
			local edit: any = tableNode:FindFirstChild("Edit", true)
			local samples: { any }, faults: { any } = {}, {}
			local mode, revision = "Done", 0
			local function sample()
				local header, body = tableNode.Header, tableNode.Body
				local row = body:FindFirstChild("neon", true)
				local entry: { [string]: any } =
					{ frame = #samples + 1, mode = mode, revision = revision, columns = {} }
				local function fault(message)
					if #faults < 20 then
						table.insert(faults, { frame = entry.frame, mode = mode, message = message })
					end
				end
				if row == nil then
					fault("the first row is absent")
				else
					local bodyRect: any = t.rect(body)
					local lastRight = bodyRect.x
					for _, id in { "name", "artist", "rating" } do
						local heading, cell = header:FindFirstChild(id), row:FindFirstChild(id, true)
						if heading == nil or cell == nil then
							fault(id .. " is absent")
						elseif heading.Visible ~= cell.Visible then
							fault(id .. " header and cell visibility differ")
						elseif heading.Visible then
							local top: any, value: any = t.rect(heading), t.rect(cell)
							entry.columns[id] = { header = top, cell = value }
							if math.abs(top.x - value.x) > 1 or math.abs(top.w - value.w) > 1 then
								fault(id .. " header and cell rectangles differ")
							end
							if value.x < lastRight - 1 or value.r > bodyRect.r + 1 or value.w <= 0 then
								fault(id .. " overlaps or is clipped")
							end
							lastRight = value.r
						end
					end
					local name = row:FindFirstChild("name", true)
					local mark = row:FindFirstChild("SelectMark", true)
					if name and mark and mark.Visible and t.rect(mark).r > t.rect(name).x + 1 then
						fault("the selection mark overlaps Name")
					end
					if mode == "Edit" and name then
						local text = name:FindFirstChild("Value", true)
						if text and text:IsA("TextLabel") and not text.TextFits then
							fault("Neon Straightaway is truncated in Edit")
						end
					end
				end
				table.insert(samples, entry)
			end
			local watch = game:GetService("RunService").PreRender:Connect(sample)
			for _ = 1, 3 do
				for _, nextMode in { "Edit", "Done" } do
					revision += 1
					local point = edit.AbsolutePosition + edit.AbsoluteSize / 2 + inset
					virtual:SendMousePosition(point)
					virtual:SendMouseButton(point, Enum.UserInputType.MouseButton1, true)
					t.settle(2)
					virtual:SendMouseButton(point, Enum.UserInputType.MouseButton1, false)
					mode = nextMode
					t.settle(30)
					t.check(
						nextMode .. " changes the toolbar command",
						edit:GetAttribute("label") == (if nextMode == "Edit" then "Done" else "Edit")
					)
				end
			end
			watch:Disconnect()
			t.note("every rendered frame", samples)
			t.check("all six transitions were sampled on every rendered frame", #samples >= 180, #samples)
			t.check("header and first row stay aligned without overlap or clipped columns", #faults == 0, faults)
		end,
	},
}
return cases
