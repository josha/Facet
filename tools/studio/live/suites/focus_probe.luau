--!strict
local GuiService = game:GetService("GuiService")
local storage = game:GetService("ReplicatedStorage")

type Case = {
	id: string,
	contracts: { string },
	run: ((any) -> ())?,
	setup: ((any) -> any)?,
	steps: { [string]: (any, any) -> () }?,
	keepGallery: boolean?,
}
local cases: { Case } = {}
local function add(id: string, run: (any) -> ())
	table.insert(cases, { id = id, contracts = {}, run = run })
end

local function live(): any
	return (require :: any)(storage:WaitForChild("FacetLive"))
end

local function box(Host: any, name: string, x: number, y: number, w: number, h: number, selectable: boolean?)
	return Host.Frame({
		Name = name,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		Selectable = selectable ~= false,
		BackgroundTransparency = 0.5,
	})
end

local function move(t: any, from: GuiObject, key: string): string
	GuiService.SelectedObject = from
	t.settle(3)
	live().press({ key })
	local now = GuiService.SelectedObject
	return if now then now.Name else "nil"
end

local function each(t: any, from: GuiObject, keys: { string }, label: string)
	for _, key in keys do
		t.note(`{label} {key}`, move(t, from, key))
	end
end

add("F1-overlap-vs-near", function(t)
	local world = t.mount(function(_, Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host))
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			box(Host, "Source", 300, 600, 600, 44) :: unknown,
			box(Host, "NearOutOfSpan", 100, 520, 44, 44),
			box(Host, "FarInSpan", 500, 200, 300, 44),
		})
	end, { size = Vector2.new(1200, 800) })
	local source = t.find(world, "Source")
	each(t, source, { "StickUp" }, "stick from Source")
	GuiService.SelectedObject = nil
end)

add("F2-m2-with-control-frames", function(t)
	local world = t.mount(function(_, Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host))
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			box(Host, "Lap", 71, 272, 633, 44) :: unknown,
			box(Host, "Tilt", 164, 402, 392, 44),
			box(Host, "Rear", 17, 480, 44, 190),
			box(Host, "Boost", 17, 700, 687, 44),
		})
	end, { size = Vector2.new(1542, 900) })
	each(t, t.find(world, "Boost"), { "StickUp", "Up" }, "from Boost")
	each(t, t.find(world, "Rear"), { "StickUp", "StickDown", "StickRight", "DPadRight", "Down" }, "from Rear")
	GuiService.SelectedObject = nil
end)

add("F3-stick-honours-links", function(t)
	local world = t.mount(function(_, Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host))
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			box(Host, "A", 100, 100, 100, 44) :: unknown,
			box(Host, "B", 300, 100, 100, 44),
			box(Host, "C", 100, 300, 100, 44),
		})
	end, { size = Vector2.new(800, 600) })
	local a, c = t.find(world, "A"), t.find(world, "C")
	a.NextSelectionRight = a
	each(t, a, { "StickRight", "DPadRight", "Right" }, "A self-linked right")
	a.NextSelectionRight = c
	each(t, a, { "StickRight", "DPadRight", "Right" }, "A linked right to C")
	a.NextSelectionRight = nil
	GuiService.SelectedObject = nil
end)

add("F4-drag-detector-phantom", function(t)
	local world = t.mount(function(_, Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host))
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			box(Host, "Top", 100, 100, 300, 44) :: unknown,
			Host.Frame({
				Name = "Track",
				Position = UDim2.fromOffset(100, 250),
				Size = UDim2.fromOffset(300, 44),
				Selectable = false,
				Host.UIDragDetector({ Name = "Drag" }),
			}),
			box(Host, "Bottom", 100, 400, 300, 44),
		})
	end, { size = Vector2.new(800, 600) })
	local top = t.find(world, "Top")
	t.note("detector enabled: Down from Top", move(t, top, "DPadDown"))
	t.find(world, "Drag").Enabled = false
	t.settle(3)
	t.note("detector disabled: Down from Top", move(t, top, "DPadDown"))
	GuiService.SelectedObject = nil
end)

add("F5-selection-group-column", function(t)
	local world = t.mount(function(_, Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host))
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			box(Host, "Tilt", 164, 402, 392, 44) :: unknown,
			Host.Frame({
				Name = "Column",
				Position = UDim2.fromOffset(17, 480),
				Size = UDim2.fromOffset(687, 264),
				BackgroundTransparency = 1,
				SelectionGroup = true,
				box(Host, "Rear", 0, 0, 44, 190) :: unknown,
				box(Host, "Boost", 0, 220, 687, 44),
			}),
		})
	end, { size = Vector2.new(1542, 900) })
	local boost = t.find(world, "Boost")
	t.note("group Escape: Up from Boost", move(t, boost, "StickUp"))
	t.note("group Escape: DPad Up from Boost (send pad_key 18 now)", "manual")
	t.find(world, "Column").SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	t.note("group Stop: Up from Rear", move(t, t.find(world, "Rear"), "StickUp"))
	t.find(world, "Column").NextSelectionUp = t.find(world, "Tilt")
	t.note("NextSelectionUp on the group frame: Up from Rear", move(t, t.find(world, "Rear"), "StickUp"))
	GuiService.SelectedObject = nil
end)

add("F6-offscreen-scroll-child", function(t)
	local world = t.mount(function(_, Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host))
		local rows = {}
		for index = 1, 12 do
			table.insert(rows, box(Host, `Row{index}`, 0, (index - 1) * 60, 300, 44))
		end
		return Host.ScrollingFrame({
			Name = "Scroller",
			Size = UDim2.fromOffset(320, 200),
			CanvasSize = UDim2.fromOffset(0, 720),
			table.unpack((rows :: unknown) :: { unknown }),
		})
	end, { size = Vector2.new(800, 600) })
	local scroller = t.find(world, "Scroller")
	t.note("Down from Row3 (Row4 partly clipped)", move(t, t.find(world, "Row3"), "DPadDown"))
	t.note("CanvasPosition after", scroller.CanvasPosition.Y)
	GuiService.SelectedObject = t.find(world, "Row12")
	t.settle(5)
	t.note(
		"select off-screen Row12 -> SelectedObject",
		if GuiService.SelectedObject then GuiService.SelectedObject.Name else "nil"
	)
	t.note("CanvasPosition after selecting Row12", scroller.CanvasPosition.Y)
	GuiService.SelectedObject = nil
end)

add("F7-rotated-and-canvasgroup", function(t)
	local world = t.mount(function(_, Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host))
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			box(Host, "Top", 200, 100, 300, 44) :: unknown,
			Host.Frame({
				Name = "Rotated",
				Position = UDim2.fromOffset(200, 250),
				Size = UDim2.fromOffset(300, 44),
				Rotation = 20,
				Selectable = true,
			}),
			Host.CanvasGroup({
				Name = "Group",
				Position = UDim2.fromOffset(200, 400),
				Size = UDim2.fromOffset(300, 60),
				box(Host, "InGroup", 0, 8, 300, 44),
			}),
		})
	end, { size = Vector2.new(800, 600) })
	local top = t.find(world, "Top")
	t.note("Down from Top", move(t, top, "DPadDown"))
	t.note("Down from Rotated", move(t, t.find(world, "Rotated"), "DPadDown"))
	GuiService.SelectedObject = nil
end)

add("F8-sink-context-on-dpad-and-stick", function(t)
	local world = t.mount(function(_, Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host))
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			box(Host, "A", 100, 100, 100, 44) :: unknown,
			box(Host, "B", 300, 100, 100, 44),
		})
	end, { size = Vector2.new(800, 600) })
	local heard = 0
	local context = Instance.new("InputContext")
	context.Priority = 250
	context.Sink = false
	local action = Instance.new("InputAction")
	action.Type = Enum.InputActionType.Direction2D
	action.Parent = context
	local binding = Instance.new("InputBinding")
	binding.KeyCode = Enum.KeyCode.Thumbstick1
	binding.Parent = action
	action.StateChanged:Connect(function()
		heard += 1
	end)
	context.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	t.note("Sink=false stick right from A", move(t, t.find(world, "A"), "StickRight"))
	t.note("Sink=false Direction2D events", heard)
	context.Sink = true
	heard = 0
	t.note("Sink=true stick right from A", move(t, t.find(world, "A"), "StickRight"))
	t.note("Sink=true Direction2D events", heard)
	context:Destroy()
	GuiService.SelectedObject = nil
end)

add("F9-arrow-keys-drive-engine", function(t)
	local world = t.mount(function(_, Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host))
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			box(Host, "A", 100, 100, 100, 44) :: unknown,
			box(Host, "B", 300, 100, 100, 44),
		})
	end, { size = Vector2.new(800, 600) })
	t.note("Right arrow from A", move(t, t.find(world, "A"), "Right"))
	GuiService.SelectedObject = nil
end)

add("F10-l1-r1-with-selection", function(t)
	local world = t.mount(function(_, Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host))
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Host.Frame({
				Name = "G1",
				Size = UDim2.fromOffset(300, 60),
				SelectionGroup = true,
				box(Host, "A", 0, 0, 100, 44),
			}) :: unknown,
			Host.Frame({
				Name = "G2",
				Position = UDim2.fromOffset(400, 0),
				Size = UDim2.fromOffset(300, 60),
				SelectionGroup = true,
				box(Host, "B", 0, 0, 100, 44),
			}),
		})
	end, { size = Vector2.new(800, 600) })
	t.note("ButtonL1 from A", move(t, t.find(world, "A"), "ButtonL1"))
	GuiService.SelectedObject = nil
end)

add("E1-input-actions-while-selected", function(t)
	local world = t.mount(function(_, Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host))
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			box(Host, "A", 300, 100, 100, 44),
		})
	end, { size = Vector2.new(800, 600) })
	local a = t.find(world, "A")
	a.NextSelectionLeft = a
	local heard = {}
	local context = Instance.new("InputContext")
	context.Priority = 10000
	context.Sink = true
	for _, key in { Enum.KeyCode.Thumbstick1, Enum.KeyCode.DPadLeft, Enum.KeyCode.ButtonL1 } do
		local action = Instance.new("InputAction")
		action.Type = if key == Enum.KeyCode.Thumbstick1
			then Enum.InputActionType.Direction2D
			else Enum.InputActionType.Bool
		local binding = Instance.new("InputBinding")
		binding.KeyCode = key
		binding.Parent = action
		action.StateChanged:Connect(function()
			heard[key.Name] = (heard[key.Name] or 0) + 1
		end)
		action.Parent = context
	end
	context.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	for _, key in { "StickLeft", "DPadLeft", "ButtonL1" } do
		move(t, a, key)
	end
	t.note("selected: action events by key", heard)
	table.clear(heard)
	GuiService.SelectedObject = nil
	t.settle(3)
	live().press({ "StickLeft", "DPadLeft" })
	t.note("nothing selected: action events by key", heard)
	context:Destroy()
	GuiService.SelectedObject = nil
end)

add("E2-wired-candidates-first", function(t)
	local world = t.mount(function(_, Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host))
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			box(Host, "A", 16, 100, 741, 44) :: unknown,
			box(Host, "B", 16, 154, 741, 44),
			box(Host, "X", 1100, 242, 62, 50),
		})
	end, { size = Vector2.new(1200, 800) })
	local a, x = t.find(world, "A"), t.find(world, "X")
	t.note("plain: Down from A", move(t, a, "DPadDown"))
	for _, signal in { "SelectionGained", "SelectionLost", "SelectionChanged", "InputBegan" } do
		local connection = (x :: any)[signal]:Connect(function() end)
		t.note(`X has {signal}: Down from A`, move(t, a, "DPadDown"))
		t.note(`X has {signal}: stick Down from A`, move(t, a, "StickDown"))
		connection:Disconnect()
	end
	GuiService.SelectedObject = nil
end)

add("F12-out-of-beam-alignment", function(t)
	local world = t.mount(function(_, Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host))
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			box(Host, "S", 100, 500, 100, 44) :: unknown,
			box(Host, "Near", 430, 250, 40, 44),
			box(Host, "Aligned", 1030, 200, 40, 44),
		})
	end, { size = Vector2.new(1200, 800) })
	t.note("Right from S: Near (40 deg) or Aligned (18 deg)", move(t, t.find(world, "S"), "DPadRight"))
	GuiService.SelectedObject = nil
end)

add("F12-sweep", function(t)
	local world = t.mount(function(_, Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host))
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			box(Host, "S", 100, 400, 100, 44) :: unknown,
			box(Host, "A", 0, 0, 10, 10),
			box(Host, "B", 0, 0, 10, 10),
			box(Host, "C", 0, 0, 10, 10),
		})
	end, { size = Vector2.new(1400, 900) })
	local source = t.find(world, "S")
	local frames = { t.find(world, "A"), t.find(world, "B"), t.find(world, "C") }
	for _, node in { source, table.unpack(frames) } do
		node.SelectionGained:Connect(function() end)
	end
	local options = shared.FacetFocusSweep or {}
	local view = options.view or "right"
	local key = if view == "left" then "DPadLeft" elseif view == "down" then "DPadDown" else "DPadRight"
	local function place(node: GuiObject, x: number, y: number, w: number, h: number)
		if view == "left" then
			x = 1400 - x - w
		elseif view == "down" then
			x, y, w, h = y * 0.65, x * 0.65, h * 0.65, w * 0.65
		end
		node.Position = UDim2.fromOffset(x, y)
		node.Size = UDim2.fromOffset(w, h)
	end
	place(source, 100, 400, 100, 44)
	local random = Random.new(options.seed or 12)
	local trials = {}
	local count = options.count or 90
	local used = options.pairs and 2 or 3
	frames[3].Visible = used == 3
	for trial = 1, count do
		local rects = {}
		for index = 1, used do
			local node = frames[index]
			local w, h = random:NextInteger(30, 220), random:NextInteger(30, 140)
			local x = random:NextInteger(210, 1300 - w)
			local y
			if trial % 3 == 0 and index == 1 then
				y = random:NextInteger(400 - h + 1, 443)
			else
				repeat
					y = random:NextInteger(10, 880 - h)
				until y + h <= 400 or y >= 444
			end
			place(node, x, y, w, h)
			rects[node.Name] = { x, y, w, h }
		end
		t.settle(2)
		rects.pick = move(t, source, key)
		table.insert(trials, rects)
	end
	local grid = options.grid
	if grid then
		table.clear(trials)
		frames[3].Visible = false
		place(frames[2], table.unpack(grid.b))
		for y = grid.ys[1], grid.ys[2], grid.ys[3] do
			for x = grid.xs[1], grid.xs[2], grid.xs[3] do
				place(frames[1], x, y, grid.size[1], grid.size[2])
				t.settle(2)
				table.insert(
					trials,
					{ A = { x, y, grid.size[1], grid.size[2] }, B = grid.b, pick = move(t, source, key) }
				)
			end
		end
	end
	t.note(`trials (S = 100,400,100,44; canonical Right; view {view})`, trials)
	GuiService.SelectedObject = nil
end)

add("F14-scroll-strip-vs-its-tabs", function(t)
	local world = t.mount(function(_, Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host))
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			box(Host, "Above", 200, 200, 100, 44) :: unknown,
			box(Host, "Left", 0, 420, 100, 44),
			box(Host, "Side", 0, 303, 100, 44),
			Host.ScrollingFrame({
				Name = "Strip",
				Position = UDim2.fromOffset(150, 300),
				Size = UDim2.fromOffset(500, 50),
				CanvasSize = UDim2.fromOffset(500, 0),
				Selectable = true,
				box(Host, "T1", 10, 3, 80, 44) :: unknown,
				box(Host, "T2", 100, 3, 80, 44),
				box(Host, "T3", 190, 3, 80, 44),
			}),
		})
	end, { size = Vector2.new(1000, 700) })
	local strip = t.find(world, "Strip")
	local seen: { string } = {}
	local watch = GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		local now = GuiService.SelectedObject
		table.insert(seen, if now then now.Name else "nil")
	end)
	local function run(label: string)
		for _, spec in { { "Above", "DPadDown" }, { "Left", "DPadRight" }, { "Side", "DPadRight" } } do
			table.clear(seen)
			local landed = move(t, t.find(world, spec[1]), spec[2])
			t.note(`{label}: {spec[2]} from {spec[1]}`, { landed = landed, sequence = table.clone(seen) })
		end
	end
	run("strip unwired, tabs unwired, tabs inset 3")
	for _, name in { "T1", "T2", "T3" } do
		t.find(world, name).SelectionGained:Connect(function() end)
	end
	run("strip unwired, tabs wired, tabs inset 3")
	for _, name in { "T1", "T2", "T3" } do
		local tab = t.find(world, name)
		tab.Position = UDim2.fromOffset(tab.Position.X.Offset, 0)
		tab.Size = UDim2.fromOffset(80, 50)
	end
	run("strip unwired, tabs wired, tabs fill")
	strip.SelectionGained:Connect(function() end)
	run("strip wired, tabs wired, tabs fill")
	watch:Disconnect()
	GuiService.SelectedObject = nil
end)

add("F15-lane-is-span-or-centre-line", function(t)
	local world = t.mount(function(_, Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host))
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			box(Host, "S", 100, 400, 100, 44) :: unknown,
			box(Host, "EdgeOverlap", 400, 350, 60, 60),
			box(Host, "CentreLine", 900, 380, 60, 60),
			box(Host, "OutNear", 260, 330, 60, 40),
		})
	end, { size = Vector2.new(1200, 800) })
	for _, name in { "S", "EdgeOverlap", "CentreLine", "OutNear" } do
		t.find(world, name).SelectionGained:Connect(function() end)
	end
	local source = t.find(world, "S")
	t.note("Right: EdgeOverlap (span only, near) vs CentreLine (far) vs OutNear", move(t, source, "DPadRight"))
	t.find(world, "EdgeOverlap").Visible = false
	t.settle(2)
	t.note("Right without EdgeOverlap: CentreLine (far, in lane) vs OutNear", move(t, source, "DPadRight"))
	GuiService.SelectedObject = nil
end)

add("F16-scroll-container-in-lane-vs-control-out-of-lane", function(t)
	local world = t.mount(function(_, Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host))
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			box(Host, "Above", 100, 20, 300, 44) :: unknown,
			box(Host, "Right", 600, 120, 100, 44),
			Host.ScrollingFrame({
				Name = "Scroller",
				Position = UDim2.fromOffset(100, 100),
				Size = UDim2.fromOffset(320, 200),
				CanvasSize = UDim2.fromOffset(0, 800),
				Selectable = true,
				box(Host, "Clipped", 0, 250, 300, 44) :: unknown,
				box(Host, "Shown", 0, 60, 300, 44),
			}),
		})
	end, { size = Vector2.new(1000, 800) })
	for _, name in { "Above", "Right", "Clipped", "Shown" } do
		t.find(world, name).SelectionGained:Connect(function() end)
	end
	local seen: { string } = {}
	local watch = GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		local now = GuiService.SelectedObject
		table.insert(seen, if now then now.Name else "nil")
	end)
	local above = t.find(world, "Above")
	local landed = move(t, above, "DPadDown")
	t.note("Down from Above, scroller holds a visible child", { landed = landed, sequence = table.clone(seen) })
	t.find(world, "Shown").Visible = false
	t.settle(2)
	table.clear(seen)
	landed = move(t, above, "DPadDown")
	t.note("Down from Above, scroller child only clipped", { landed = landed, sequence = table.clone(seen) })
	watch:Disconnect()
	GuiService.SelectedObject = nil
end)

add("F6b-clipped-scroll-child-from-outside", function(t)
	local world = t.mount(function(_, Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host))
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			box(Host, "Above", 100, 20, 300, 44) :: unknown,
			Host.ScrollingFrame({
				Name = "Scroller",
				Position = UDim2.fromOffset(100, 100),
				Size = UDim2.fromOffset(320, 200),
				CanvasSize = UDim2.fromOffset(0, 800),
				Selectable = false,
				box(Host, "Clipped", 0, 250, 300, 44),
			}),
			box(Host, "Far", 100, 700, 300, 44),
		})
	end, { size = Vector2.new(800, 800) })
	t.note("Down from Above (Clipped below the window, Far visible)", move(t, t.find(world, "Above"), "DPadDown"))
	GuiService.SelectedObject = nil
end)

add("F11-selection-image-part", function(t)
	local world = t.mount(function(_, Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host))
		return Host.Frame({
			Name = "Row",
			Position = UDim2.fromOffset(100, 100),
			Size = UDim2.fromOffset(600, 60),
			Selectable = true,
			Host.Frame({ Name = "Part", Position = UDim2.fromOffset(300, 8), Size = UDim2.fromOffset(44, 44) }),
		})
	end, { size = Vector2.new(800, 600) })
	GuiService.SelectedObject = t.find(world, "Row")
	t.settle(5)
	t.note("ring (PlayerGui.SelectionImageObject) abs rect", {
		((game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui) :: any).SelectionImageObject
			and ((game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui) :: any).SelectionImageObject.AbsolutePosition,
	})
	GuiService.SelectedObject = nil
end)

return cases
