--!strict
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local cases = {}

local function add(id: string, contracts: { string }, run: (any) -> ())
	table.insert(cases, { id = id, contracts = contracts, run = run })
end

local function pointer(t: any): any
	local virtual = (UserInputService :: any):CreateVirtualInput()
	t.check("virtual input is available", virtual ~= nil)
	local inset = GuiService:GetGuiInset()
	local mouse = {}
	function mouse.move(at: Vector2)
		virtual:SendMousePosition(at + inset)
		t.settle(1)
	end
	function mouse.drag(from: Vector2, to: Vector2, steps: number?)
		local count = steps or 12
		virtual:SendMousePosition(from + inset)
		t.settle(2)
		virtual:SendMouseButton(from + inset, Enum.UserInputType.MouseButton1, true)
		t.settle(2)
		for index = 1, count do
			local at = from:Lerp(to, index / count)
			virtual:SendMousePosition(at + inset)
			t.settle(1)
		end
		virtual:SendMouseButton(to + inset, Enum.UserInputType.MouseButton1, false)
		t.settle(4)
	end
	function mouse.click(at: Vector2)
		mouse.drag(at, at, 1)
	end
	function mouse.key(key: Enum.KeyCode)
		virtual:SendKey(true, key, false)
		t.settle(2)
		virtual:SendKey(false, key, false)
		t.settle(4)
	end
	mouse.virtual = virtual
	mouse.inset = inset
	return mouse
end

local function centre(node: GuiObject): Vector2
	return node.AbsolutePosition + node.AbsoluteSize / 2
end

add("mail-row-grip", { "collections-101" }, function(t)
	local mouse = pointer(t)
	local value = {}
	local demo = t.scenario("collection_demo")
	local stage = t.mount(function(UI, Host, Compose, env)
		local seed = {}
		for index = 1, 30 do
			seed[index] = {
				id = "m" .. index,
				from = "Sender " .. index,
				subject = "Subject " .. index,
				preview = "Preview " .. index,
				read = false,
				flagged = false,
			}
		end
		value.built = demo(t.context(UI, Host, Compose, env), {
			name = "Mail_list",
			title = "Mail",
			rows = seed,
			count = 30,
			actions = true,
			mail = true,
			list = true,
		})
		return value.built.screen()
	end, { frames = 20, reducedMotion = false })
	local function read(): { [string]: boolean }
		return value.built.report().read
	end
	local row = t.find(stage, "Row_m1")
	local grip = row and t.find(row, "SwipeGrip")
	local mail = row and t.find(row, "Item_m1")
	t.check("row m1, its grip and its content Button exist", row ~= nil and grip ~= nil and mail ~= nil)
	if not (row and grip and mail) then
		return
	end
	t.check("the grip is not a selection stop", grip.Selectable == false, grip.Selectable)
	t.check("the content Button stays a selection stop", mail.Selectable == true, mail.Selectable)
	local at = centre(row)
	local hits = (game:GetService("Players").LocalPlayer.PlayerGui :: any):GetGuiObjectsAtPosition(at.X, at.Y)
	t.check("a press on the row lands on the grip first", hits[1] == grip, hits[1] and hits[1]:GetFullName())
	local x = row.AbsolutePosition.X
	local w = row.AbsoluteSize.X
	mouse.drag(Vector2.new(x + w * 0.8, at.Y), Vector2.new(x + w * 0.8 - 160, at.Y))
	t.settle(20)
	local tray = row:FindFirstChild("trailing") :: GuiObject?
	t.check(
		"a real left drag opens the trailing tray of m1",
		tray ~= nil and tray.Visible and tray.AbsoluteSize.X > 40,
		tray and tray.AbsoluteSize
	)
	t.check("the drag does not mark m1 read", read().m1 ~= true, read())
	mouse.click(at)
	t.settle(20)
	t.check(
		"a tap on the open row closes the tray",
		tray == nil or not tray.Visible or tray.AbsoluteSize.X < 1,
		tray and tray.AbsoluteSize
	)
	t.check("the closing tap does not mark m1 read", read().m1 ~= true, read())
	local second = t.find(stage, "Row_m2")
	mouse.click(centre(second))
	t.settle(8)
	t.check("a tap on m2 marks it read through the grip", read().m2 == true, read())
	local third = t.find(stage, "Item_m3")
	GuiService.SelectedObject = third
	t.settle(4)
	mouse.key(Enum.KeyCode.Return)
	t.check("Return on the selected content Button marks m3 read", read().m3 == true, read())
	t.check("the selection stays on the content Button", GuiService.SelectedObject == third, GuiService.SelectedObject)
	GuiService.SelectedObject = nil
end)

add("mail-row-touch-pan", { "collections-101" }, function(t)
	t.device({ device = "iphone_14", input = Enum.PreferredInput.Touch, restore = "xbox" })
	local mouse = pointer(t)
	local value = {}
	local demo = t.scenario("collection_demo")
	local stage = t.mount(function(UI, Host, Compose, env)
		local seed = {}
		for index = 1, 30 do
			seed[index] = {
				id = "m" .. index,
				from = "Sender " .. index,
				subject = "Subject " .. index,
				preview = "Preview " .. index,
				read = false,
				flagged = false,
			}
		end
		value.built = demo(t.context(UI, Host, Compose, env), {
			name = "Mail_list",
			title = "Mail",
			rows = seed,
			count = 30,
			actions = true,
			mail = true,
			list = true,
		})
		return value.built.screen()
	end, { frames = 20, reducedMotion = false })
	local function read(): { [string]: boolean }
		return value.built.report().read
	end
	local kinds = {}
	local watch = UserInputService.InputBegan:Connect(function(input)
		table.insert(kinds, input.UserInputType.Name)
	end)
	local row = t.find(stage, "Row_m2")
	local body = nil
	for _, node in stage:GetDescendants() do
		if node:IsA("ScrollingFrame") and row:IsDescendantOf(node) then
			body = node
		end
	end
	t.check("the mail list is a native ScrollingFrame", body ~= nil)
	if not body then
		watch:Disconnect()
		return
	end
	local at = centre(row)
	local before = body.CanvasPosition.Y
	mouse.drag(at, at - Vector2.new(0, 200), 16)
	t.settle(30)
	t.note("input types seen", kinds)
	t.note("canvas before and after the pan", { before, body.CanvasPosition.Y })
	t.check("the pan arrives as touch", table.find(kinds, "Touch") ~= nil, kinds)
	t.check("a vertical touch pan over the rows scrolls the list", body.CanvasPosition.Y > before + 40, {
		before = before,
		after = body.CanvasPosition.Y,
	})
	t.check("the pan marks no row read", read().m2 ~= true, read())
	local tray = row:FindFirstChild("trailing") :: GuiObject?
	t.check("the pan opens no tray", tray == nil or tray.AbsoluteSize.X < 1, tray and tray.AbsoluteSize)
	body.CanvasPosition = Vector2.zero
	t.settle(10)
	local other = t.find(stage, "Row_m3")
	local x, w = other.AbsolutePosition.X, other.AbsoluteSize.X
	local y = centre(other).Y
	mouse.drag(Vector2.new(x + w * 0.8, y), Vector2.new(x + w * 0.8 - 160, y))
	t.settle(20)
	local opened = other:FindFirstChild("trailing") :: GuiObject?
	t.check(
		"a horizontal touch drag opens the trailing tray",
		opened ~= nil and opened.AbsoluteSize.X > 40,
		opened and opened.AbsoluteSize
	)
	t.check("the horizontal touch drag does not mark m3 read", read().m3 ~= true, read())
	mouse.click(centre(other))
	t.settle(20)
	t.check(
		"a touch tap on the open row closes the tray",
		opened == nil or opened.AbsoluteSize.X < 1,
		opened and opened.AbsoluteSize
	)
	t.check("the closing touch tap does not mark m3 read", read().m3 ~= true, read())
	local fourth = t.find(stage, "Row_m4")
	local spot = centre(fourth)
	local top = (game:GetService("Players").LocalPlayer.PlayerGui :: any):GetGuiObjectsAtPosition(spot.X, spot.Y)[1]
	t.check("the tap point on m4 is its grip", top == t.find(fourth, "SwipeGrip"), top and top:GetFullName())
	mouse.click(spot)
	t.settle(10)
	t.check("a touch tap on m4 marks it read through the grip", read().m4 == true, read())
	watch:Disconnect()
end)

add("range-knobs-flush", { "post-pickers-127" }, function(t)
	local mouse = pointer(t)
	local value = {}
	local stage = t.mount(function(UI, Host, Compose)
		value.range = Compose.cell({ lower = 0, upper = 100 })
		value.single = Compose.cell(0)
		value.vertical = Compose.cell(0)
		local function art(side: number): (any) -> Instance
			return function()
				return Host.Frame "Art" {
					Size = UDim2.fromOffset(side, side),
					BackgroundColor3 = Color3.new(1, 1, 1),
					Host.UICorner({ CornerRadius = UDim.new(0.5, 0) }),
				}
			end
		end
		return Host.Frame "Column" {
			Size = UDim2.fromOffset(420, 600),
			Position = UDim2.fromOffset(100, 60),
			BackgroundTransparency = 1,
			Host.UIListLayout({ Padding = UDim.new(0, 24), SortOrder = Enum.SortOrder.LayoutOrder }),
			UI.Slider "Band" {
				LayoutOrder = 1,
				value = value.range,
				range = true,
				minGap = 10,
				min = 0,
				max = 100,
				step = 1,
				Size = UDim2.fromOffset(420, 0),
				thumbContent = function(info)
					return art(if info.thumb == "lower" then 12 else 40)(info)
				end,
			},
			UI.Slider "Plain" {
				LayoutOrder = 2,
				value = value.single,
				min = 0,
				max = 100,
				step = 1,
				Size = UDim2.fromOffset(420, 0),
			},
			UI.Slider "Tall" {
				LayoutOrder = 3,
				value = value.vertical,
				axis = "y",
				min = 0,
				max = 100,
				step = 1,
				Size = UDim2.fromOffset(0, 240),
			},
		}
	end, { frames = 20 })
	local function part(slider: string, name: string): GuiObject
		return t.find(t.find(stage, slider), name)
	end
	local function knobArt(slider: string, handle: string): GuiObject
		local node = part(slider, handle)
		local knob = node:FindFirstChild("Art", true) or node:FindFirstChild("Knob")
		return (knob or node) :: GuiObject
	end
	local rail = part("Band", "Rail")
	local lower, upper = knobArt("Band", "HandleLower"), knobArt("Band", "HandleUpper")
	local rx, rr = rail.AbsolutePosition.X, rail.AbsolutePosition.X + rail.AbsoluteSize.X
	t.note("band rail", { rx, rr })
	t.near("the 12 px lower knob starts at the rail start", lower.AbsolutePosition.X, rx, 1)
	t.near("the 40 px upper knob ends at the rail end", upper.AbsolutePosition.X + upper.AbsoluteSize.X, rr, 1)
	t.near("the lower art measures 12", lower.AbsoluteSize.X, 12, 0.5)
	t.near("the upper art measures 40", upper.AbsoluteSize.X, 40, 0.5)
	local fill = part("Band", "Fill")
	t.near("the fill starts under the lower knob centre", fill.AbsolutePosition.X, centre(lower).X, 1)
	t.near(
		"the fill ends under the upper knob centre",
		fill.AbsolutePosition.X + fill.AbsoluteSize.X,
		centre(upper).X,
		1
	)
	local plainRail, plainKnob = part("Plain", "Rail"), knobArt("Plain", "Thumb")
	t.near(
		"the default knob starts at its rail start at 0",
		plainKnob.AbsolutePosition.X,
		plainRail.AbsolutePosition.X,
		1
	)
	value.single:set(100)
	t.settle(6)
	t.near(
		"the default knob ends at its rail end at 100",
		plainKnob.AbsolutePosition.X + plainKnob.AbsoluteSize.X,
		plainRail.AbsolutePosition.X + plainRail.AbsoluteSize.X,
		1
	)
	local tallRail, tallKnob = part("Tall", "Rail"), knobArt("Tall", "Thumb")
	t.near(
		"the vertical knob sits on the rail bottom at 0",
		tallKnob.AbsolutePosition.Y + tallKnob.AbsoluteSize.Y,
		tallRail.AbsolutePosition.Y + tallRail.AbsoluteSize.Y,
		1
	)
	value.vertical:set(100)
	t.settle(6)
	t.near("the vertical knob meets the rail top at 100", tallKnob.AbsolutePosition.Y, tallRail.AbsolutePosition.Y, 1)
	local half = rx + 20 + (rr - rx - 40) / 2
	mouse.drag(centre(upper), Vector2.new(half, centre(upper).Y))
	t.settle(6)
	t.near("a real drag of the upper knob to the middle of its travel reads 50", value.range:peek().upper, 50, 1)
	t.near("the dragged upper knob centre follows the pointer", centre(upper).X, half, 1.5)
	mouse.drag(centre(upper), Vector2.new(rr + 60, centre(upper).Y))
	t.settle(6)
	t.check("a drag past the rail end reads the maximum", value.range:peek().upper == 100, value.range:peek())
	t.near(
		"the upper knob stops flush at the rail end after a drag",
		upper.AbsolutePosition.X + upper.AbsoluteSize.X,
		rr,
		1
	)
	mouse.drag(centre(lower), Vector2.new(half, centre(lower).Y))
	t.settle(6)
	t.near("a real drag of the lower knob to the middle reads 50", value.range:peek().lower, 50, 1)
	mouse.drag(centre(lower), Vector2.new(rx - 60, centre(lower).Y))
	t.settle(6)
	t.check("a drag past the rail start reads the minimum", value.range:peek().lower == 0, value.range:peek())
	t.near("the lower knob stops flush at the rail start after a drag", lower.AbsolutePosition.X, rx, 1)
	mouse.drag(centre(lower), Vector2.new(rr, centre(lower).Y))
	t.settle(6)
	local band = value.range:peek()
	t.check("a lower drag past the upper knob stops at minGap", band.lower == 90 and band.upper == 100, band)
end)

return cases
