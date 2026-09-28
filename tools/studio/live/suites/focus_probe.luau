--!strict
local GuiService = game:GetService("GuiService")
local storage = game:GetService("ReplicatedStorage")

local cases = {}
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
	local world = t.mount(function(_, Host)
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			box(Host, "Source", 300, 600, 600, 44),
			box(Host, "NearOutOfSpan", 100, 520, 44, 44),
			box(Host, "FarInSpan", 500, 200, 300, 44),
		})
	end, { size = Vector2.new(1200, 800) })
	local source = t.find(world, "Source")
	each(t, source, { "StickUp" }, "stick from Source")
	GuiService.SelectedObject = nil
end)

add("F2-m2-with-control-frames", function(t)
	local world = t.mount(function(_, Host)
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			box(Host, "Lap", 71, 272, 633, 44),
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
	local world = t.mount(function(_, Host)
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			box(Host, "A", 100, 100, 100, 44),
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
	local world = t.mount(function(_, Host)
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			box(Host, "Top", 100, 100, 300, 44),
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
	local world = t.mount(function(_, Host)
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			box(Host, "Tilt", 164, 402, 392, 44),
			Host.Frame({
				Name = "Column",
				Position = UDim2.fromOffset(17, 480),
				Size = UDim2.fromOffset(687, 264),
				BackgroundTransparency = 1,
				SelectionGroup = true,
				box(Host, "Rear", 0, 0, 44, 190),
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
	local world = t.mount(function(_, Host)
		local rows = {}
		for index = 1, 12 do
			table.insert(rows, box(Host, `Row{index}`, 0, (index - 1) * 60, 300, 44))
		end
		return Host.ScrollingFrame({
			Name = "Scroller",
			Size = UDim2.fromOffset(320, 200),
			CanvasSize = UDim2.fromOffset(0, 720),
			table.unpack(rows),
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
	local world = t.mount(function(_, Host)
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			box(Host, "Top", 200, 100, 300, 44),
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
	local world = t.mount(function(_, Host)
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			box(Host, "A", 100, 100, 100, 44),
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
	context.Parent = game:GetService("Players").LocalPlayer.PlayerGui
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
	local world = t.mount(function(_, Host)
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			box(Host, "A", 100, 100, 100, 44),
			box(Host, "B", 300, 100, 100, 44),
		})
	end, { size = Vector2.new(800, 600) })
	t.note("Right arrow from A", move(t, t.find(world, "A"), "Right"))
	GuiService.SelectedObject = nil
end)

add("F10-l1-r1-with-selection", function(t)
	local world = t.mount(function(_, Host)
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Host.Frame({
				Name = "G1",
				Size = UDim2.fromOffset(300, 60),
				SelectionGroup = true,
				box(Host, "A", 0, 0, 100, 44),
			}),
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

add("F11-selection-image-part", function(t)
	local world = t.mount(function(_, Host)
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
		(game:GetService("Players").LocalPlayer.PlayerGui :: any).SelectionImageObject
			and (game:GetService("Players").LocalPlayer.PlayerGui :: any).SelectionImageObject.AbsolutePosition,
	})
	GuiService.SelectedObject = nil
end)

return cases
