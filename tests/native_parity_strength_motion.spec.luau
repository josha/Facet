--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local pathShapes = require("../src/ui/nav_path_shapes")
local Compose = Facet.Compose
local themes = Facet.themes

local function find(root: any, name: string): any
	if root.Name == name then
		return root
	end
	for _, child in root:GetChildren() do
		local found = find(child, name)
		if found then
			return found
		end
	end
	return nil
end

local function world(options: { [string]: any }?): any
	local engine: any = engineLib.new()
	local now = 0
	engine.clock = function()
		return now
	end
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	local config: { [string]: any } =
		{ types = engine.types, services = { GuiService = gui, UserInputService = input } }
	for key, value in (options or {}) :: { [string]: any } do
		config[key] = value
	end
	local UI = Facet.controls(runtime, config :: any)
	local w: any = { engine = engine, runtime = runtime, gui = gui, input = input, UI = UI, config = config }
	function w.mount(build: (any, any) -> any): (() -> (), any)
		local stop, node = runtime.mount(function()
			return runtime.constructors.ScreenGui({ build(UI, runtime.constructors) })
		end, engine.new("Folder"))
		return stop, node
	end
	function w.step(seconds: number, frame: number?)
		local dt = frame or 1 / 60
		for _ = 1, math.max(1, math.round(seconds / dt)) do
			now += dt
			engine.heartbeat.fire(dt)
		end
	end
	function w.close()
		runtime:dispose()
	end
	return w
end

local function angleOf(point: any): number
	local x, y = point.Position.X.Scale - 0.5, point.Position.Y.Scale - 0.5
	return math.deg(math.atan2(x, -y)) % 360
end

local function segmentReading(indicator: any): string
	local parts: { string } = {}
	for index = 1, 8 do
		table.insert(parts, string.format("%.4f", find(indicator, "Segment" .. index).BackgroundTransparency))
	end
	return table.concat(parts, ",")
end

local function brightest(indicator: any): number
	local best, bestIndex = math.huge, 0
	for index = 1, 8 do
		local value = find(indicator, "Segment" .. index).BackgroundTransparency
		if value < best then
			best, bestIndex = value, index
		end
	end
	return bestIndex
end

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

t.describe("indeterminate progress lifetime", function()
	t.it("an indeterminate bar keeps travelling in its third second and stops dead with its owner", function()
		local w = world({ reducedMotion = false })
		local stop, screen = w.mount(function(UI)
			return UI.ProgressView({})
		end)
		local fill = find(screen, "Fill1")
		t.expect(find(screen, "FillClip").ClipsDescendants).toBe(true)
		t.expect(w.engine.heartbeat.count() > 0).toBe(true)
		local changes, last = 0, fill.Position.X.Scale
		for frame = 1, 180 do
			w.step(1 / 60)
			local now = fill.Position.X.Scale
			t.expect(now >= -0.3 - 1e-6 and now <= 1 + 1e-6).toBe(true)
			if frame > 120 and now ~= last then
				changes += 1
			end
			last = now
		end
		t.expect(changes > 50).toBe(true)
		stop()
		t.expect(w.engine.heartbeat.count()).toBe(0)
		local held = fill.Position.X.Scale
		w.step(1)
		t.expect(fill.Position.X.Scale).toBe(held)
		t.expect(fill.isDestroyed()).toBe(true)
		w.close()
	end)

	t.it("an indeterminate view built under an owner and never presented stops with that owner", function()
		local w = world({ reducedMotion = false })
		local view
		local root = Compose.createRootOwner(function()
			view = w.UI.ProgressView({})
		end, w.runtime.reactor)
		t.expect(view.Parent).toBe(nil)
		local fill = find(view, "Fill1")
		local before = fill.Position.X.Scale
		w.step(0.2)
		t.expect(fill.Position.X.Scale ~= before).toBe(true)
		t.expect(w.engine.heartbeat.count() > 0).toBe(true)
		root.dispose()
		t.expect(w.engine.heartbeat.count()).toBe(0)
		local held = fill.Position.X.Scale
		w.step(0.5)
		t.expect(fill.Position.X.Scale).toBe(held)
		w.close()
	end)

	t.it("unmounting and disposing the runtime are safe in either order", function()
		for _, unmountFirst in { true, false } do
			local w = world({ reducedMotion = false })
			local stop, screen = w.mount(function(UI)
				return UI.ProgressView({ presentation = "spinner" })
			end)
			local dot = find(screen, "Segment1")
			w.step(0.1)
			local ok = pcall(function()
				if unmountFirst then
					stop()
					w.close()
				else
					w.close()
					stop()
				end
			end)
			t.expect(ok).toBe(true)
			t.expect(w.engine.heartbeat.count()).toBe(0)
			local held = dot.BackgroundTransparency
			w.step(0.5)
			t.expect(dot.BackgroundTransparency).toBe(held)
		end
	end)

	t.it("a plain determinate bar starts no cycle under either motion policy", function()
		for _, reduced in { false, true } do
			local w = world({ reducedMotion = reduced })
			local value = Compose.cell(0.4)
			local stop, screen = w.mount(function(UI)
				return UI.ProgressView({ value = value })
			end)
			t.expect(w.engine.heartbeat.count()).toBe(0)
			t.expect(find(screen, "Fill1").Size.X.Scale).toBeCloseTo(0.4)
			t.expect(find(screen, "Trail")).toBe(nil)
			value:set(0.1)
			t.expect(w.engine.heartbeat.count()).toBe(0)
			t.expect(find(screen, "Fill1").Size.X.Scale).toBeCloseTo(0.1)
			value:set(0.9)
			w.step(0.3)
			t.expect(w.engine.heartbeat.count()).toBe(0)
			t.expect(find(screen, "Fill1").Size.X.Scale).toBeCloseTo(0.9)
			stop()
			w.close()
		end
	end)

	t.it("an indeterminate view under reduced motion still runs its cycle and says Loading", function()
		local w = world({ reducedMotion = true })
		local stop, screen = w.mount(function(UI, Host)
			return Host.Frame({
				UI.ProgressView({ presentation = "spinner" }),
				UI.ProgressView({ showValue = true }),
			})
		end)
		t.expect(w.engine.heartbeat.count() >= 2).toBe(true)
		t.expect(find(screen, "Value").Text).toBe("Loading")
		local indicator = find(screen, "Indicator")
		local start = segmentReading(indicator)
		w.step(0.375, 0.125)
		t.expect(segmentReading(indicator) ~= start).toBe(true)
		stop()
		t.expect(w.engine.heartbeat.count()).toBe(0)
		w.close()
	end)
end)

t.describe("spinner paint", function()
	t.it("draws eight fixed square dots at the theme dot size and no bar", function()
		local package = Compose.cell(themes.neutralPackage())
		local w2 = world({ reducedMotion = false, theme = package })
		local stop, screen = w2.mount(function(UI)
			return UI.ProgressView({ presentation = "spinner" })
		end)
		local indicator = find(screen, "Indicator")
		local dotSize = themes.neutralPackage().metrics.controls.progress.spinnerDotSize
		t.expect(find(screen, "Track")).toBe(nil)
		t.expect(find(screen, "Fill1")).toBe(nil)
		t.expect(find(indicator, "Segment9")).toBe(nil)
		local sizes = {}
		for index = 1, 8 do
			local dot = find(indicator, "Segment" .. index)
			t.expect(dot ~= nil).toBe(true)
			t.expect(dot:HasTag("facet-fill")).toBe(true)
			t.expect(dot.Size).toBe(w2.engine.types.UDim2.fromOffset(dotSize, dotSize))
			t.expect(dot:FindFirstChildWhichIsA("UICorner").CornerRadius.Scale).toBe(1)
			sizes[index] = dot.Size
		end
		for _ = 1, 30 do
			w2.step(1 / 60)
			for index = 1, 8 do
				t.expect(find(indicator, "Segment" .. index).Size).toBe(sizes[index])
			end
		end
		local grown = themes.neutralPackage()
		grown.metrics.controls.progress.spinnerDotSize = dotSize + 3
		package:set(grown)
		t.expect(find(indicator, "Segment1").Size).toBe(w2.engine.types.UDim2.fromOffset(dotSize + 3, dotSize + 3))
		stop()
		w2.close()
	end)

	t.it("moves the brightest dot around the ring while every dot stays visible", function()
		local w = world({ reducedMotion = false })
		local stop, screen = w.mount(function(UI)
			return UI.ProgressView({ presentation = "spinner" })
		end)
		local indicator = find(screen, "Indicator")
		local first = brightest(indicator)
		local visited: { [number]: boolean } = { [first] = true }
		local count = 1
		for _ = 1, 20 do
			w.step(0.05)
			local index = brightest(indicator)
			if not visited[index] then
				visited[index] = true
				count += 1
			end
			for dot = 1, 8 do
				local value = find(indicator, "Segment" .. dot).BackgroundTransparency
				t.expect(value >= 0 and value <= 0.85).toBe(true)
			end
		end
		t.expect(count >= 6).toBe(true)
		stop()
		w.close()
	end)

	t.it("writes the spinner on full-motion frames and quantizes a mid-run switch without restarting", function()
		local reduced = Compose.cell(false)
		local w = world({ reducedMotion = reduced })
		local stop, screen = w.mount(function(UI)
			return UI.ProgressView({ presentation = "spinner" })
		end)
		local indicator = find(screen, "Indicator")
		local seen: { [string]: boolean } = {}
		local fullCount = 0
		for _ = 1, 20 do
			w.step(0.02)
			local key = segmentReading(indicator)
			if not seen[key] then
				seen[key] = true
				fullCount += 1
			end
		end
		t.expect(fullCount).toBe(20)
		w.step(0.2)
		reduced:set(true)
		for index = 1, 8 do
			local expected = ((index / 8 - 0.5) % 1) * 0.85
			t.expect(find(indicator, "Segment" .. index).BackgroundTransparency).toBeCloseTo(expected, 1e-9)
		end
		seen = {}
		local reducedCount = 0
		for _ = 1, 20 do
			w.step(0.02)
			local key = segmentReading(indicator)
			if not seen[key] then
				seen[key] = true
				reducedCount += 1
			end
		end
		t.expect(reducedCount >= 2).toBe(true)
		t.expect(fullCount > reducedCount).toBe(true)
		stop()
		w.close()
	end)
end)

t.describe("circular progress motion", function()
	t.it("travels the indeterminate head while the sweep stays a fixed quarter turn", function()
		local w = world({ reducedMotion = false })
		local stop, screen = w.mount(function(UI)
			return UI.ProgressView({ presentation = "circular", diameter = 100 })
		end)
		local arc = find(screen, "RingFill")
		local function sweep(): number
			local points = arc:GetControlPoints()
			return (angleOf(points[#points]) - angleOf(points[1]) + 360) % 360
		end
		local startHead = angleOf(arc:GetControlPoints()[1])
		local moved = false
		for _ = 1, 10 do
			w.step(0.05)
			t.expect(math.abs(sweep() - 90) < 1e-3).toBe(true)
			if math.abs(angleOf(arc:GetControlPoints()[1]) - startHead) > 0.001 then
				moved = true
			end
		end
		t.expect(moved).toBe(true)
		t.expect(find(screen, "RingFill")).toBe(arc)
		stop()
		w.close()
	end)

	t.it("keeps the reduced-motion ring travelling in a few visible poses each second", function()
		local function poses(reducedMotion: boolean, frames: number, dt: number): (number, any)
			local w = world({ reducedMotion = reducedMotion })
			local stop, screen = w.mount(function(UI)
				return UI.ProgressView({ presentation = "circular", diameter = 100 })
			end)
			local arc = find(screen, "RingFill")
			local seen: { [string]: boolean } = {}
			local count = 0
			for _ = 1, frames do
				w.step(dt)
				local key = string.format("%.6f", angleOf(arc:GetControlPoints()[1]))
				if not seen[key] then
					seen[key] = true
					count += 1
				end
			end
			stop()
			w.close()
			return count, arc
		end
		local w = world({ reducedMotion = true })
		local stop, screen = w.mount(function(UI)
			return UI.ProgressView({ presentation = "circular", diameter = 100 })
		end)
		local arc = find(screen, "RingFill")
		local start = angleOf(arc:GetControlPoints()[1])
		for _ = 1, 3 do
			w.step(0.05)
			t.expect(math.abs(angleOf(arc:GetControlPoints()[1]) - start) < 1e-9).toBe(true)
		end
		w.step(0.15)
		t.expect(math.abs(angleOf(arc:GetControlPoints()[1]) - start) > 0.001).toBe(true)
		stop()
		w.close()
		local reducedCount = poses(true, 20, 0.05)
		t.expect(reducedCount >= 3 and reducedCount <= 8).toBe(true)
		local fullCount = poses(false, 20, 0.05)
		t.expect(fullCount > reducedCount).toBe(true)
	end)

	t.it("ends a quarter value at three o'clock and closes the ring at the full value", function()
		local w = world({ reducedMotion = true })
		local value = Compose.cell(0.25)
		local stop, screen = w.mount(function(UI)
			return UI.ProgressView({ presentation = "circular", value = value, diameter = 100, thickness = 10 })
		end)
		local arc = find(screen, "RingFill")
		local points = arc:GetControlPoints()
		t.expect(near(angleOf(points[1]), 0, 1e-3)).toBe(true)
		t.expect(near(angleOf(points[#points]), 90, 1e-3)).toBe(true)
		t.expect(near(points[#points].Position.Y.Scale, 0.5, 1e-5)).toBe(true)
		t.expect(points[#points].Position.X.Scale > 0.9).toBe(true)
		value:set(0.65)
		points = arc:GetControlPoints()
		t.expect(near(angleOf(points[#points]), 234, 1e-3)).toBe(true)
		t.expect(points[#points].Position.X.Scale < 0.5).toBe(true)
		t.expect(points[#points].Position.Y.Scale > 0.5).toBe(true)
		value:set(1)
		points = arc:GetControlPoints()
		t.expect(near(points[1].Position.X.Scale, points[#points].Position.X.Scale, 1e-5)).toBe(true)
		t.expect(near(points[1].Position.Y.Scale, points[#points].Position.Y.Scale, 1e-5)).toBe(true)
		t.expect(find(screen, "RingFill")).toBe(arc)
		stop()
		w.close()
	end)
end)

t.describe("arc shape math", function()
	t.it("closes a full ring with nine points on the radius", function()
		local points = pathShapes.ring()
		t.expect(#points).toBe(9)
		t.expect(near(points[1].x, points[9].x)).toBe(true)
		t.expect(near(points[1].y, points[9].y)).toBe(true)
		for _, point in points do
			t.expect(near(math.sqrt((point.x - 0.5) ^ 2 + (point.y - 0.5) ^ 2), 0.5, 1e-9)).toBe(true)
		end
		local inset = pathShapes.ring({ radius = 0.8 })
		for _, point in inset do
			t.expect(near(math.sqrt((point.x - 0.5) ^ 2 + (point.y - 0.5) ^ 2), 0.4, 1e-9)).toBe(true)
		end
	end)

	t.it("uses screen angles where zero is up, ninety is right and y grows down", function()
		local points = pathShapes.arc(0, 90, { segments = 2 })
		t.expect(near(points[1].x, 0.5)).toBe(true)
		t.expect(near(points[1].y, 0)).toBe(true)
		t.expect(near(points[2].x, 0.5 + 0.5 * math.sin(math.rad(45)))).toBe(true)
		t.expect(near(points[2].y, 0.5 - 0.5 * math.cos(math.rad(45)))).toBe(true)
		t.expect(near(points[3].x, 1)).toBe(true)
		t.expect(near(points[3].y, 0.5)).toBe(true)
		local bottom = pathShapes.arc(90, 90, { segments = 1 })
		t.expect(near(bottom[2].x, 0.5)).toBe(true)
		t.expect(near(bottom[2].y, 1)).toBe(true)
	end)

	t.it("points tangents forward with the exact cubic handle length and mirrors them", function()
		for _, case in { { 180, 4 }, { 90, 2 }, { 270, 6 }, { -120, 3 } } do
			local sweep, segments = case[1], case[2]
			local points = pathShapes.arc(0, sweep, { segments = segments })
			t.expect(#points).toBe(segments + 1)
			local expected = (4 / 3) * math.tan(math.abs(math.rad(sweep / segments)) / 4) * 0.5
			local direction = if sweep >= 0 then 1 else -1
			t.expect(near(points[1].outX, expected * direction, 1e-9)).toBe(true)
			t.expect(near(points[1].outY, 0, 1e-9)).toBe(true)
			t.expect(near(points[1].inX, -expected * direction, 1e-9)).toBe(true)
			for index, point in points do
				t.expect(near(point.inX, -point.outX, 1e-9)).toBe(true)
				t.expect(near(point.inY, -point.outY, 1e-9)).toBe(true)
				t.expect(near(math.sqrt(point.outX ^ 2 + point.outY ^ 2), expected, 1e-9)).toBe(true)
				local radialX, radialY = point.x - 0.5, point.y - 0.5
				t.expect(near(radialX * point.outX + radialY * point.outY, 0, 1e-9)).toBe(true)
				local angle = math.rad(sweep * (index - 1) / segments)
				t.expect(near(point.x, 0.5 + 0.5 * math.sin(angle), 1e-9)).toBe(true)
			end
		end
	end)

	t.it("ends a larger sweep farther along the circle and refuses more than one hundred points", function()
		local previous = -1
		for sweep = 15, 345, 15 do
			local points = pathShapes.arc(0, sweep)
			local finish = points[#points]
			local angle = math.deg(math.atan2(finish.x - 0.5, -(finish.y - 0.5))) % 360
			t.expect(near(angle, sweep, 1e-6)).toBe(true)
			t.expect(angle > previous).toBe(true)
			previous = angle
			t.expect(#points).toBe(math.max(2, math.ceil(sweep / 45)) + 1)
		end
		local clamped = pathShapes.arc(0, 720)
		t.expect(near(clamped[1].x, clamped[#clamped].x)).toBe(true)
		t.expect(pcall(pathShapes.arc, 0, 360, { segments = 120 })).toBe(false)
		t.expect(pcall(pathShapes.arc, 0, 360, { segments = 99 })).toBe(true)
		t.expect(pathShapes.MAX_CONTROL_POINTS).toBe(100)
	end)
end)

t.describe("skeleton clock sharing", function()
	t.it(
		"shares one clock inside an application, keeps applications apart and detaches with the last skeleton",
		function()
			local engine: any = engineLib.new()
			local runtimeA = Facet.Roblox.createRuntime(engine)
			local runtimeB = Facet.Roblox.createRuntime(engine)
			local UIA = Facet.controls(runtimeA, { types = engine.types, reducedMotion = false } :: any)
			local UIB = Facet.controls(runtimeB, { types = engine.types, reducedMotion = false } :: any)
			t.expect(engine.heartbeat.count()).toBe(0)
			local stopA1, a1 = runtimeA.mount(function()
				return UIA.Skeleton({ form = "line", lines = 2 })
			end, engine.new("Folder"))
			t.expect(engine.heartbeat.count()).toBe(1)
			local stopA2, a2 = runtimeA.mount(function()
				return UIA.Skeleton({ form = "circle" })
			end, engine.new("Folder"))
			t.expect(engine.heartbeat.count()).toBe(1)
			local stopB, b = runtimeB.mount(function()
				return UIB.Skeleton({ form = "box" })
			end, engine.new("Folder"))
			t.expect(engine.heartbeat.count()).toBe(2)
			engine.heartbeat.fire(0.3)
			local shimmerA1 = find(a1, "Shimmer")
			local shimmerA2 = find(a2, "Shimmer")
			local shimmerB = find(b, "Shimmer")
			t.expect(shimmerA1.Offset).toBe(shimmerA2.Offset)
			t.expect(shimmerA1.Offset).toBe(shimmerB.Offset)
			stopB()
			t.expect(engine.heartbeat.count()).toBe(1)
			local stopB2, b2 = runtimeB.mount(function()
				return UIB.Skeleton({ form = "box" })
			end, engine.new("Folder"))
			t.expect(engine.heartbeat.count()).toBe(2)
			engine.heartbeat.fire(0.2)
			t.expect(find(b2, "Shimmer").Offset ~= shimmerA1.Offset).toBe(true)
			stopA1()
			t.expect(engine.heartbeat.count()).toBe(2)
			stopA2()
			t.expect(engine.heartbeat.count()).toBe(1)
			local held = shimmerA2.Offset
			engine.heartbeat.fire(0.2)
			t.expect(shimmerA2.Offset).toBe(held)
			stopB2()
			t.expect(engine.heartbeat.count()).toBe(0)
			runtimeA:dispose()
			runtimeB:dispose()
		end
	)
end)

local function compassItems(onSelect: (string) -> ()): { any }
	local entries = {}
	for _, id in { "N", "E", "S", "W" } do
		table.insert(entries, {
			id = id,
			slot = id,
			label = id,
			completion = "stay",
			onSelect = function()
				onSelect(id)
			end,
		})
	end
	return entries
end

t.describe("radial retirement motion", function()
	t.it("reopening mid-exit continues from the painted opacity and keeps every node", function()
		local w = world({ reducedMotion = false })
		local opened = Compose.cell(true)
		local stop, screen = w.mount(function(UI)
			return UI.RadialMenu({
				isPresented = opened,
				distribution = "compass",
				items = compassItems(function() end),
			})
		end)
		w.step(0.3)
		local panel, sector = find(screen, "RadialPanel"), find(screen, "Sector-N")
		local paint = find(sector, "Sector")
		local thickness = paint.Thickness
		t.expect(sector.GroupTransparency).toBe(0)
		opened:set(false)
		w.step(0.05)
		local fading = sector.GroupTransparency
		t.expect(fading > 0 and fading < 1).toBe(true)
		t.expect(panel.Interactable).toBe(false)
		t.expect(paint.Thickness).toBe(thickness)
		opened:set(true)
		t.expect(find(screen, "RadialPanel")).toBe(panel)
		t.expect(find(screen, "Sector-N")).toBe(sector)
		t.expect(sector.GroupTransparency).toBe(fading)
		t.expect(panel.Interactable).toBe(true)
		local previous = sector.GroupTransparency
		for _ = 1, 30 do
			w.step(1 / 60)
			t.expect(sector.GroupTransparency <= previous).toBe(true)
			previous = sector.GroupTransparency
		end
		t.expect(sector.GroupTransparency).toBe(0)
		opened:set(false)
		w.step(0.4)
		t.expect(find(screen, "RadialPanel")).toBe(nil)
		t.expect(sector.isDestroyed()).toBe(true)
		t.expect(panel.isDestroyed()).toBe(true)
		stop()
		t.expect(w.engine.heartbeat.count()).toBe(0)
		w.close()
	end)

	t.it("a retiring branch keeps its geometry, leaves the focus order and then releases", function()
		local w = world({ reducedMotion = false })
		local stop, screen = w.mount(function(UI)
			return UI.RadialMenu({
				isPresented = Compose.cell(true),
				items = {
					{
						id = "Branch",
						label = "Branch",
						children = {
							{ id = "Leaf", label = "Leaf", completion = "stay" },
							{ id = "Twig", label = "Twig", completion = "stay" },
						},
					},
					{ id = "Other", label = "Other", completion = "stay" },
				},
			})
		end)
		w.step(0.3)
		local retiring = find(screen, "Sector-Branch")
		local paint = find(retiring, "Sector")
		local thickness, points = paint.Thickness, paint:GetControlPoints()
		local retiringButton = find(retiring, "Branch")
		find(screen, "Branch").Activated.fire()
		t.expect(retiring.isDestroyed()).toBe(false)
		t.expect(retiring.Parent.Interactable).toBe(false)
		t.expect(find(screen, "Sector-Leaf").Parent.Interactable).toBe(true)
		local right = find(screen, "Radial-right")
		local down = find(screen, "Radial-down")
		t.expect(right ~= nil and down ~= nil).toBe(true)
		local visited: { [string]: boolean } = {}
		for _ = 1, 4 do
			right.Pressed.fire()
			local selected = w.gui.SelectedObject
			t.expect(selected ~= nil).toBe(true)
			t.expect(selected == retiringButton).toBe(false)
			t.expect(selected:IsDescendantOf(retiring)).toBe(false)
			visited[selected.Name] = true
			down.Pressed.fire()
			t.expect(w.gui.SelectedObject == retiringButton).toBe(false)
		end
		t.expect(visited.Leaf == true or visited.Twig == true).toBe(true)
		w.step(0.04)
		t.expect(retiring.GroupTransparency > 0 and retiring.GroupTransparency < 1).toBe(true)
		t.expect(paint.Thickness).toBe(thickness)
		t.expect(#paint:GetControlPoints()).toBe(#points)
		w.step(0.3)
		t.expect(retiring.isDestroyed()).toBe(true)
		stop()
		w.close()
	end)

	t.it("reduced motion opens a whole usable ring with a long iconed label under a native theme", function()
		local picked = {}
		local package = themes.neutralPackage()
		package.assets.search = { content = "rbxassetid://77" }
		package.icons["facet:search"] = { default = "search" }
		local w = world({ reducedMotion = false, theme = package })
		w.gui.ReducedMotionEnabled = true
		local opened = Compose.cell(false)
		local stop, screen = w.mount(function(UI, Host)
			return Host.Frame({
				themes.createStyleSheet(w.runtime, package, { types = w.engine.types, reducedMotion = true }),
				UI.RadialMenu({
					isPresented = opened,
					distribution = "even",
					items = {
						{
							id = "look",
							label = "Look at the beautiful mountain",
							icon = "facet:search",
							labelStyle = "both",
							completion = "stay",
							onSelect = function()
								table.insert(picked, "look")
							end,
						},
						{ id = "wave", label = "Wave", completion = "stay" },
					},
				}),
			})
		end)
		opened:set(true)
		local sector = find(screen, "Sector-look")
		t.expect(sector ~= nil).toBe(true)
		t.expect(sector.GroupTransparency).toBe(0)
		t.expect(find(screen, "Sector-wave").GroupTransparency).toBe(0)
		local button = find(sector, "look")
		t.expect(find(button, "Title").Text).toBe("Look at the beautiful mountain")
		t.expect(button:GetAttribute("label")).toBe("Look at the beautiful mountain")
		t.expect(find(button, "LeadingIcon").Image).toBe("rbxassetid://77")
		t.expect(button.Size.X.Offset >= 40 and button.Size.Y.Offset >= 36).toBe(true)
		button.Activated.fire()
		t.expect(table.concat(picked, ",")).toBe("look")
		opened:set(false)
		t.expect(find(screen, "RadialPanel")).toBe(nil)
		t.expect(sector.isDestroyed()).toBe(true)
		stop()
		t.expect(w.engine.heartbeat.count()).toBe(0)
		w.close()
	end)
end)

t.describe("presented surface motion", function()
	t.it("fades an alert in from transparent, fades it out over the declared time and then removes it", function()
		local w = world({ reducedMotion = false })
		local shown = Compose.cell(false)
		local stop, screen = w.mount(function(UI)
			return UI.Alert({
				isPresented = shown,
				title = "Delete?",
				transition = { seconds = 0.2 },
				actions = { { id = "ok", label = "OK" } },
			})
		end)
		shown:set(true)
		local panel = find(screen, "AlertPanel")
		t.expect(panel.ClassName).toBe("CanvasGroup")
		t.expect(panel:HasTag("facet-panel")).toBe(true)
		t.expect(panel.BackgroundTransparency).toBe(0)
		t.expect(panel.GroupTransparency).toBe(1)
		local previous, enterFrames = 1, 0
		for frame = 1, 30 do
			w.step(1 / 60)
			t.expect(panel.GroupTransparency <= previous).toBe(true)
			previous = panel.GroupTransparency
			if enterFrames == 0 and previous <= 1e-9 then
				enterFrames = frame
			end
		end
		t.expect(enterFrames >= 11 and enterFrames <= 13).toBe(true)
		shown:set(false)
		t.expect(find(screen, "AlertPanel")).toBe(panel)
		t.expect(find(screen, "AlertModal").Interactable).toBe(false)
		previous = 0
		local goneAt = 0
		for frame = 1, 30 do
			w.step(1 / 60)
			if find(screen, "AlertPanel") == nil then
				if goneAt == 0 then
					goneAt = frame
				end
			else
				t.expect(panel.GroupTransparency >= previous).toBe(true)
				t.expect(panel.GroupTransparency > 0).toBe(true)
				previous = panel.GroupTransparency
			end
		end
		t.expect(goneAt >= 11 and goneAt <= 13).toBe(true)
		t.expect(panel.isDestroyed()).toBe(true)
		stop()
		t.expect(w.engine.heartbeat.count()).toBe(0)
		w.close()
	end)

	t.it("presents and removes an alert immediately without a transition", function()
		local w = world({ reducedMotion = false })
		local shown = Compose.cell(false)
		local stop, screen = w.mount(function(UI)
			return UI.Alert({
				isPresented = shown,
				title = "Now",
				transition = false,
				actions = { { id = "ok", label = "OK" } },
			})
		end)
		shown:set(true)
		local panel = find(screen, "AlertPanel")
		t.expect(panel ~= nil).toBe(true)
		t.expect(panel:HasTag("facet-panel")).toBe(true)
		t.expect(w.engine.heartbeat.count()).toBe(0)
		shown:set(false)
		t.expect(find(screen, "AlertPanel")).toBe(nil)
		t.expect(panel.isDestroyed()).toBe(true)
		stop()
		w.close()
	end)

	t.it("a dismissed alert returns selection and refuses input the moment its fade begins", function()
		local w = world({ reducedMotion = false })
		local shown = Compose.cell(false)
		local cancels = 0
		local stop, screen = w.mount(function(UI, Host)
			return Host.Frame({
				UI.Button "Keep" { label = "Keep" },
				UI.Alert({
					isPresented = shown,
					title = "Leave?",
					transition = { seconds = 0.2 },
					actions = {
						{ id = "ok", label = "OK" },
						{
							id = "cancel",
							label = "Cancel",
							role = "cancel",
							onActivate = function()
								cancels += 1
							end,
						},
					},
				}),
			})
		end)
		local keep = find(screen, "Keep")
		w.gui.SelectedObject = keep
		shown:set(true)
		w.step(0.3)
		local modal = find(screen, "AlertModal")
		t.expect(w.gui.SelectedObject:IsDescendantOf(modal)).toBe(true)
		local back = find(screen, "FacetModalBack")
		t.expect(back.Enabled).toBe(true)
		shown:set(false)
		t.expect(find(screen, "AlertModal")).toBe(modal)
		t.expect(modal.Interactable).toBe(false)
		t.expect(w.gui.SelectedObject).toBe(keep)
		t.expect(back.Enabled).toBe(false)
		find(back, "ModalBack").Pressed.fire()
		t.expect(cancels).toBe(0)
		w.step(0.1)
		t.expect(w.gui.SelectedObject).toBe(keep)
		w.step(0.2)
		t.expect(find(screen, "AlertModal")).toBe(nil)
		t.expect(w.gui.SelectedObject).toBe(keep)
		stop()
		w.close()
	end)

	t.it("a departing tab layer and a retiring radial slot stop taking input while they fade", function()
		local w = world({ reducedMotion = false })
		local selection = Compose.cell("a")
		local opened = Compose.cell(true)
		local stop, screen = w.mount(function(UI, Host)
			return Host.Frame({
				UI.TabView({
					selection = selection,
					placement = "topBar",
					transition = { seconds = 0.2 },
					tabs = {
						{
							id = "a",
							label = "A",
							content = function()
								return UI.Button "AContent" { label = "A" }
							end,
						},
						{
							id = "b",
							label = "B",
							content = function()
								return UI.Button "BContent" { label = "B" }
							end,
						},
					},
				}),
				UI.RadialMenu({ isPresented = opened, distribution = "compass", items = compassItems(function() end) }),
			})
		end)
		w.step(0.3)
		local layerA = find(screen, "AContent").Parent
		selection:set("b")
		local layerB = find(screen, "BContent").Parent
		t.expect(layerA.Interactable).toBe(false)
		t.expect(layerB.Interactable).toBe(true)
		w.step(0.1)
		t.expect(layerA.Parent ~= nil).toBe(true)
		t.expect(layerA.Interactable).toBe(false)
		t.expect(layerA.GroupTransparency > 0 and layerA.GroupTransparency < 1).toBe(true)
		local slot = find(screen, "Sector-N").Parent
		t.expect(slot.Interactable).toBe(true)
		opened:set(false)
		t.expect(find(screen, "RadialPanel").Interactable).toBe(false)
		w.step(0.05)
		t.expect(find(screen, "Sector-N") ~= nil).toBe(true)
		t.expect(find(screen, "RadialPanel").Interactable).toBe(false)
		stop()
		w.close()
	end)

	t.it("a sheet reversed mid-flight holds its painted height and returns, and reduced motion settles it", function()
		local w = world({ reducedMotion = false })
		local detent, shown = Compose.cell("medium"), Compose.cell(true)
		local stop, screen = w.mount(function(UI)
			return UI.Sheet({
				detent = detent,
				isPresented = shown,
				title = "Details",
				content = function()
					return UI.Button "Kept" { label = "Kept" }
				end,
			})
		end)
		w.step(0.6)
		local panel = find(screen, "SheetPanel")
		local medium = panel.Size.Y.Offset
		detent:set("large")
		w.step(1 / 60)
		local inFlight = panel.Size.Y.Offset
		t.expect(inFlight > medium).toBe(true)
		w.step(2 / 60)
		inFlight = panel.Size.Y.Offset
		detent:set("medium")
		t.expect(panel.Size.Y.Offset).toBe(inFlight)
		w.step(1 / 60)
		local returning = panel.Size.Y.Offset
		t.expect(math.abs(returning - inFlight) < math.abs(inFlight - medium)).toBe(true)
		local previous = returning
		for _ = 1, 60 do
			w.step(1 / 60)
			t.expect(panel.Size.Y.Offset <= previous + 1e-6).toBe(true)
			t.expect(panel.Size.Y.Offset >= medium - 1).toBe(true)
			previous = panel.Size.Y.Offset
		end
		t.expect(math.abs(panel.Size.Y.Offset - medium) < 0.5).toBe(true)
		detent:set("large")
		w.step(1 / 60)
		t.expect(panel.Size.Y.Offset > medium).toBe(true)
		w.gui.ReducedMotionEnabled = true
		local large = panel.Size.Y.Offset
		w.step(0.2)
		t.expect(panel.Size.Y.Offset).toBe(large)
		detent:set("medium")
		t.expect(math.abs(panel.Size.Y.Offset - medium) < 0.5).toBe(true)
		t.expect(find(screen, "Kept") ~= nil).toBe(true)
		stop()
		t.expect(w.engine.heartbeat.count()).toBe(0)
		w.close()
	end)
end)

t.describe("tab content transition", function()
	local function tabs(w: any, transition: any, retention: string?): (() -> (), any, any)
		local selection = Compose.cell("a")
		local stop, screen = w.mount(function(UI)
			return UI.TabView({
				selection = selection,
				placement = "topBar",
				transition = transition,
				retention = retention,
				tabs = {
					{
						id = "a",
						label = "A",
						content = function()
							return UI.Button "AContent" { label = "A" }
						end,
					},
					{
						id = "b",
						label = "B",
						content = function()
							return UI.Button "BContent" { label = "B" }
						end,
					},
				},
			})
		end)
		return stop, screen, selection
	end

	t.it("crossfades only the content layers and never the strip", function()
		local w = world({ reducedMotion = false })
		local stop, screen, selection = tabs(w, { seconds = 0.2 })
		w.step(0.3)
		local strip = find(screen, "Tabs")
		local cursor = strip
		while cursor do
			t.expect(cursor.ClassName == "CanvasGroup").toBe(false)
			cursor = cursor.Parent
		end
		local layerA = find(screen, "AContent").Parent
		t.expect(layerA.ClassName).toBe("CanvasGroup")
		t.expect(layerA.GroupTransparency).toBe(0)
		selection:set("b")
		local layerB = find(screen, "BContent").Parent
		t.expect(layerB.ClassName).toBe("CanvasGroup")
		t.expect(layerB.GroupTransparency).toBe(1)
		w.step(0.1)
		t.expect(layerA.GroupTransparency > 0 and layerA.GroupTransparency < 1).toBe(true)
		t.expect(layerB.GroupTransparency > 0 and layerB.GroupTransparency < 1).toBe(true)
		t.expect(math.abs(layerA.GroupTransparency + layerB.GroupTransparency - 1) < 1e-6).toBe(true)
		t.expect(layerA.Visible).toBe(true)
		t.expect(layerA.Interactable).toBe(false)
		w.step(0.15)
		t.expect(layerB.GroupTransparency).toBe(0)
		t.expect(layerA.Visible).toBe(false)
		t.expect(layerA.isDestroyed()).toBe(false)
		stop()
		w.close()
	end)

	t.it("keeps a departing layer mounted until its fade ends when only the top page is retained", function()
		local w = world({ reducedMotion = false })
		local stop, screen, selection = tabs(w, { seconds = 0.2 }, "top")
		w.step(0.3)
		local layerA = find(screen, "AContent").Parent
		selection:set("b")
		w.step(0.1)
		t.expect(layerA.isDestroyed()).toBe(false)
		t.expect(layerA.Interactable).toBe(false)
		w.step(0.2)
		t.expect(find(screen, "AContent")).toBe(nil)
		t.expect(layerA.isDestroyed()).toBe(true)
		stop()
		w.close()
	end)

	t.it("switches without a fade when the transition is absent or false and refuses other spellings", function()
		for _, transition in { false :: any, nil } do
			local w = world({ reducedMotion = false })
			local stop, screen, selection = tabs(w, transition)
			local layerA = find(screen, "AContent").Parent
			t.expect(layerA.ClassName).toBe("Frame")
			selection:set("b")
			t.expect(find(screen, "BContent").Parent.Visible).toBe(true)
			t.expect(layerA.Visible).toBe(false)
			t.expect(w.engine.heartbeat.count()).toBe(0)
			stop()
			w.close()
		end
		for _, bad in { "fade" :: any, { enter = "fade" }, { fade = true }, { seconds = 0.2, class = "container" } } do
			local w = world({ reducedMotion = false })
			local ok, err = pcall(tabs, w, bad)
			t.expect(ok).toBe(false)
			t.expect(string.find(tostring(err), "Compose tween options", 1, true) ~= nil).toBe(true)
			w.close()
		end
	end)
end)

t.describe("row action reveal motion", function()
	local function row(reduced: boolean): (any, () -> (), any, any)
		local w = world({ reducedMotion = reduced })
		local open = Compose.cell(nil :: string?)
		local stop, screen = w.mount(function(UI)
			return UI.RowActions({
				content = UI.Button "Body" { label = "A preview line long enough to wrap once squeezed" },
				open = open,
				leading = { { id = "Read", label = "Read" } },
				trailing = { { id = "Archive", label = "Archive" }, { id = "Flag", label = "Flag" } },
			})
		end)
		local node = find(screen, "Content").Parent
		node.AbsoluteSize = w.engine.types.Vector2.new(320, 44)
		return w, stop, node, open
	end

	t.it("a programmatic open uncovers the tray behind the row and never ahead of it", function()
		for _, edge in { "trailing", "leading" } do
			local w, stop, node, open = row(false)
			local content, tray = find(node, "Content"), find(node, edge)
			local band = if edge == "leading" then 88 else 176
			open:set(edge)
			local sawPartial, previous = false, 0
			for _ = 1, 60 do
				w.step(1 / 60)
				local travel = math.abs(content.Position.X.Offset)
				local painted = tray.Size.X.Offset
				t.expect(painted <= travel + 1e-6).toBe(true)
				t.expect(math.abs(painted - math.min(band, travel)) < 1e-6).toBe(true)
				t.expect(travel >= previous - 1e-6).toBe(true)
				previous = travel
				if painted > 0 and painted < band then
					sawPartial = true
				end
			end
			t.expect(sawPartial).toBe(true)
			t.expect(math.abs(tray.Size.X.Offset - band) < 0.01).toBe(true)
			t.expect(tray.Visible).toBe(true)
			open:set(nil)
			w.step(1)
			t.expect(tray.Visible).toBe(false)
			stop()
			w.close()
		end
	end)

	t.it("a leading reveal translates the row content and keeps its width", function()
		for _, edge in { "leading", "trailing" } do
			local w, stop, node, open = row(false)
			local content = find(node, "Content")
			local width = content.Size
			t.expect(width).toBe(w.engine.types.UDim2.new(1, 0, 1, 0))
			open:set(edge)
			local moved = false
			for _ = 1, 60 do
				w.step(1 / 60)
				t.expect(content.Size).toBe(width)
				local x = content.Position.X.Offset
				if edge == "leading" then
					t.expect(x >= 0).toBe(true)
				else
					t.expect(x <= 0).toBe(true)
				end
				moved = moved or x ~= 0
			end
			t.expect(moved).toBe(true)
			local expected = if edge == "leading" then 88 else -176
			t.expect(math.abs(content.Position.X.Offset - expected) < 0.01).toBe(true)
			stop()
			w.close()
		end
	end)

	t.it("a reduced-motion open lands the full band on the same frame", function()
		local w, stop, node, open = row(true)
		open:set("leading")
		t.expect(find(node, "leading").Size.X.Offset).toBe(88)
		t.expect(find(node, "Content").Position.X.Offset).toBe(88)
		t.expect(find(node, "Content").Size).toBe(w.engine.types.UDim2.new(1, 0, 1, 0))
		open:set("trailing")
		t.expect(find(node, "trailing").Size.X.Offset).toBe(176)
		t.expect(find(node, "Content").Position.X.Offset).toBe(-176)
		stop()
		t.expect(w.engine.heartbeat.count()).toBe(0)
		w.close()
	end)
end)

local function withGame(gui: any, body: () -> ())
	local env = getfenv(0) :: any
	local previous = env.game
	env.game = {
		GetService = function(_, name: string)
			return if name == "GuiService" then gui else nil
		end,
	}
	local ok, err = pcall(body)
	env.game = previous
	if not ok then
		error(err, 0)
	end
end

local function ruleFor(sheet: any, selector: string): any
	for _, rule in sheet:GetChildren() do
		if rule.Selector == selector then
			return rule
		end
	end
	error("No rule: " .. selector)
end

t.describe("reduced motion preference", function()
	t.it("the player preference stops control motion live and the sheet transitions agree", function()
		local w = world({})
		withGame(w.gui, function()
			local presses = 0
			local sheet
			local stop, screen = w.mount(function(UI, Host)
				sheet = themes.createStyleSheet(w.runtime, themes.neutralPackage(), { types = w.engine.types })
				return Host.Frame({
					sheet,
					UI.Button({
						Name = "Go",
						label = "Go",
						pop = true,
						onActivate = function()
							presses += 1
						end,
					}),
				})
			end)
			local button = find(screen, "Go")
			local scale = find(button, "Pop")
			local text = ruleFor(sheet, ".facet-text")
			local function sheetReduced(): boolean
				return text:GetPropertyTransitions().TextColor3.Time == 0
			end
			local function pressMoves(): boolean
				button.Activated.fire()
				w.step(0.1)
				local moved = scale.Scale ~= 1
				w.step(1)
				return moved
			end
			t.expect(sheetReduced()).toBe(false)
			t.expect(pressMoves()).toBe(true)
			button.Activated.fire()
			w.step(0.05)
			t.expect(scale.Scale ~= 1).toBe(true)
			w.gui.ReducedMotionEnabled = true
			t.expect(scale.Scale).toBe(1)
			t.expect(sheetReduced()).toBe(true)
			t.expect(pressMoves()).toBe(false)
			w.gui.ReducedMotionEnabled = false
			t.expect(sheetReduced()).toBe(false)
			t.expect(pressMoves()).toBe(true)
			t.expect(presses).toBe(4)
			stop()
			t.expect(w.engine.heartbeat.count()).toBe(0)
			t.expect(w.gui:GetPropertyChangedSignal("ReducedMotionEnabled").count()).toBe(0)
		end)
		w.close()
	end)

	t.it("a surface mounted while the preference is on is reduced from its first press", function()
		local w = world({})
		w.gui.ReducedMotionEnabled = true
		withGame(w.gui, function()
			local sheet
			local stop, screen = w.mount(function(UI, Host)
				sheet = themes.createStyleSheet(w.runtime, themes.neutralPackage(), { types = w.engine.types })
				return Host.Frame({
					sheet,
					UI.Button({ Name = "Go", label = "Go", pop = true, onActivate = function() end }),
				})
			end)
			t.expect(ruleFor(sheet, ".facet-surface"):GetPropertyTransitions().BackgroundColor3.Time).toBe(0)
			local scale = find(find(screen, "Go"), "Pop")
			find(screen, "Go").Activated.fire()
			for _ = 1, 10 do
				w.step(1 / 60)
				t.expect(scale.Scale).toBe(1)
			end
			stop()
		end)
		w.close()
	end)
end)

t.describe("invalid entry feedback", function()
	local function field(reduced: any): (any, () -> (), any, any)
		local w = world({ reducedMotion = reduced })
		local invalid = Compose.cell(false)
		local stop, screen = w.mount(function(UI)
			return UI.TextInput({ Name = "Name", value = Compose.cell("ready"), invalid = invalid })
		end)
		return w, stop, find(screen, "Name"), invalid
	end

	t.it("pulses on a rising edge without moving the field and returns to rest", function()
		local w, stop, node, invalid = field(false)
		local pulse = find(node, "ValidationPulse")
		local position, size = node.Position, node.Size
		t.expect(pulse.Scale).toBe(1)
		invalid:set(true)
		t.expect(find(node, "ValidationMessage").Visible).toBe(true)
		local sawPulse = false
		for _ = 1, 20 do
			w.step(1 / 60)
			t.expect(pulse.Scale <= 1).toBe(true)
			sawPulse = sawPulse or pulse.Scale < 1
			t.expect(node.Position).toBe(position)
			t.expect(node.Size).toBe(size)
		end
		t.expect(sawPulse).toBe(true)
		t.expect(pulse.Scale).toBe(1)
		t.expect(w.engine.heartbeat.count()).toBe(0)
		t.expect(find(node, "ValidationMessage").Visible).toBe(true)
		stop()
		w.close()
	end)

	t.it("a second edge mid-pulse restarts the pulse instead of racing it", function()
		local w, stop, node, invalid = field(false)
		local pulse = find(node, "ValidationPulse")
		invalid:set(true)
		local fresh: { number } = {}
		for index = 1, 10 do
			w.step(1 / 60)
			fresh[index] = pulse.Scale
		end
		t.expect(fresh[1] < 1).toBe(true)
		invalid:set(false)
		invalid:set(true)
		for index = 1, 6 do
			w.step(1 / 60)
			t.expect(pulse.Scale).toBeCloseTo(fresh[index], 1e-12)
		end
		w.step(0.5)
		t.expect(pulse.Scale).toBe(1)
		stop()
		w.close()
	end)

	t.it("keeps the message and never pulses under reduced motion, and a live switch settles a pulse", function()
		local w, stop, node, invalid = field(true)
		local pulse = find(node, "ValidationPulse")
		invalid:set(true)
		t.expect(find(node, "ValidationMessage").Visible).toBe(true)
		for _ = 1, 20 do
			w.step(1 / 60)
			t.expect(pulse.Scale).toBe(1)
		end
		stop()
		w.close()
		local reduced = Compose.cell(false)
		local w2, stop2, node2, invalid2 = field(reduced)
		local pulse2 = find(node2, "ValidationPulse")
		invalid2:set(true)
		w2.step(0.05)
		t.expect(pulse2.Scale < 1).toBe(true)
		reduced:set(true)
		t.expect(pulse2.Scale).toBe(1)
		t.expect(w2.engine.heartbeat.count()).toBe(0)
		t.expect(find(node2, "ValidationMessage").Visible).toBe(true)
		stop2()
		w2.close()
	end)

	t.it("disposing mid-pulse leaves nothing armed", function()
		local w, stop, node, invalid = field(false)
		local pulse = find(node, "ValidationPulse")
		invalid:set(true)
		w.step(0.05)
		t.expect(pulse.Scale < 1).toBe(true)
		stop()
		t.expect(w.engine.heartbeat.count()).toBe(0)
		local held = pulse.Scale
		for _ = 1, 10 do
			w.step(1 / 60)
			t.expect(pulse.Scale).toBe(held)
		end
		t.expect(pcall(function()
			invalid:set(false)
			invalid:set(true)
		end)).toBe(true)
		t.expect(w.engine.heartbeat.count()).toBe(0)
		w.close()
	end)

	t.it("refuses an invalid declaration that is not a readable boolean", function()
		for _, bad in { true :: any, "yes", 1, Compose.cell("no") } do
			local w = world({})
			local ok, err = pcall(w.mount, function(UI)
				return UI.TextInput({ value = Compose.cell(""), invalid = bad })
			end)
			t.expect(ok).toBe(false)
			t.expect(string.find(tostring(err), "invalid", 1, true) ~= nil).toBe(true)
			w.close()
		end
	end)
end)

t.describe("control motion policy and lifetime", function()
	local function motionScene(UI: any, Host: any, state: any): any
		return Host.Frame({
			UI.Sheet({
				detent = state.detent,
				isPresented = state.sheet,
				title = "Sheet",
				content = function()
					return UI.Button({ Name = "Go", label = "Go", pop = true, onActivate = function() end })
				end,
			}),
			UI.RowActions({
				content = UI.Button "RowBody" { label = "Row" },
				open = state.open,
				trailing = { { id = "Archive", label = "Archive" } },
			}),
			UI.Alert({
				isPresented = state.alert,
				title = "Alert",
				transition = { seconds = 0.2 },
				actions = { { id = "ok", label = "OK" } },
			}),
			UI.TabView({
				selection = state.tab,
				placement = "topBar",
				transition = { seconds = 0.2 },
				tabs = {
					{
						id = "a",
						label = "A",
						content = function()
							return Host.Frame({ Name = "APage" })
						end,
					},
					{
						id = "b",
						label = "B",
						content = function()
							return Host.Frame({ Name = "BPage" })
						end,
					},
				},
			}),
			UI.Skeleton({ form = "line" }),
			UI.ProgressView({ Name = "Health", value = state.value, trail = { delay = 0.05, duration = 0.3 } }),
			UI.ProgressView({ Name = "Busy", presentation = "spinner" }),
		})
	end

	local function newState(): any
		return {
			detent = Compose.cell("medium"),
			sheet = Compose.cell(true),
			open = Compose.cell(nil :: string?),
			alert = Compose.cell(false),
			tab = Compose.cell("a"),
			value = Compose.cell(1),
		}
	end

	t.it(
		"a live reduced-motion switch lands decorative motion on its terminus while progress keeps stepping",
		function()
			local reduced = Compose.cell(false)
			local w = world({ reducedMotion = reduced })
			local state = newState()
			local stop, screen = w.mount(function(UI, Host)
				return motionScene(UI, Host, state)
			end)
			local row = find(screen, "RowBody").Parent.Parent.Parent
			row.AbsoluteSize = w.engine.types.Vector2.new(320, 44)
			w.step(0.6)
			local sheetPanel = find(screen, "SheetPanel")
			local medium = sheetPanel.Size.Y.Offset
			local go = find(screen, "Go")
			go.Activated.fire()
			state.detent:set("large")
			state.open:set("trailing")
			state.alert:set(true)
			state.tab:set("b")
			state.value:set(0.3)
			w.step(0.1)
			local pop = find(go, "Pop")
			local content = find(row, "Content")
			local alertPanel = find(screen, "AlertPanel")
			local arriving = find(screen, "BPage").Parent
			local departing = find(screen, "APage").Parent
			local shimmer = find(screen, "Shimmer")
			local trail = find(find(screen, "Health"), "Trail")
			t.expect(pop.Scale ~= 1).toBe(true)
			t.expect(sheetPanel.Size.Y.Offset > medium).toBe(true)
			t.expect(content.Position.X.Offset < 0 and content.Position.X.Offset > -88).toBe(true)
			t.expect(alertPanel.GroupTransparency > 0 and alertPanel.GroupTransparency < 1).toBe(true)
			t.expect(arriving.GroupTransparency > 0 and arriving.GroupTransparency < 1).toBe(true)
			t.expect(trail.Size.X.Scale > 0.3 + 1e-6).toBe(true)
			t.expect(shimmer.Enabled).toBe(true)
			local indicator = find(find(screen, "Busy"), "Indicator")
			reduced:set(true)
			local landed = {
				pop = pop.Scale,
				sheet = sheetPanel.Size.Y.Offset,
				row = content.Position.X.Offset,
				alert = alertPanel.GroupTransparency,
				arriving = arriving.GroupTransparency,
				trail = trail.Size.X.Scale,
				shimmer = shimmer.Offset,
			}
			t.expect(landed.pop).toBe(1)
			t.expect(landed.row).toBe(-88)
			t.expect(landed.alert).toBe(0)
			t.expect(landed.arriving).toBe(0)
			t.expect(departing.Visible).toBe(false)
			t.expect(landed.trail).toBeCloseTo(0.3, 1e-6)
			t.expect(shimmer.Enabled).toBe(false)
			local start = segmentReading(indicator)
			local stepped = false
			for _ = 1, 30 do
				w.step(1 / 60)
				t.expect(pop.Scale).toBe(landed.pop)
				t.expect(sheetPanel.Size.Y.Offset).toBe(landed.sheet)
				t.expect(content.Position.X.Offset).toBe(landed.row)
				t.expect(alertPanel.GroupTransparency).toBe(landed.alert)
				t.expect(arriving.GroupTransparency).toBe(landed.arriving)
				t.expect(trail.Size.X.Scale).toBe(landed.trail)
				t.expect(shimmer.Offset).toBe(landed.shimmer)
				stepped = stepped or segmentReading(indicator) ~= start
			end
			t.expect(stepped).toBe(true)
			t.expect(landed.sheet > medium).toBe(true)
			state.detent:set("medium")
			t.expect(math.abs(sheetPanel.Size.Y.Offset - medium) < 0.5).toBe(true)
			state.alert:set(false)
			t.expect(find(screen, "AlertPanel")).toBe(nil)
			stop()
			t.expect(w.engine.heartbeat.count()).toBe(0)
			w.close()
		end
	)

	t.it("fifty animated mount, flight and unmount cycles return the census to its baseline", function()
		local w = world({ reducedMotion = false })
		local target = w.engine.new("Folder")
		local function cycle()
			local state = newState()
			local stop = w.runtime.mount(function()
				return w.runtime.constructors.ScreenGui({ motionScene(w.UI, w.runtime.constructors, state) })
			end, target)
			local row = find(target, "RowBody").Parent.Parent.Parent
			row.AbsoluteSize = w.engine.types.Vector2.new(320, 44)
			w.step(0.05)
			find(target, "Go").Activated.fire()
			state.detent:set("large")
			state.open:set("trailing")
			state.alert:set(true)
			state.tab:set("b")
			state.value:set(0.2)
			w.step(0.05)
			t.expect(w.engine.heartbeat.count() > 0).toBe(true)
			stop()
			t.expect(w.engine.heartbeat.count()).toBe(0)
			t.expect(#target:GetChildren()).toBe(0)
		end
		local baseline = w.engine.census()
		cycle()
		local first = w.engine.census()
		t.expect(first.live).toBe(baseline.live)
		t.expect(first.connections).toBe(baseline.connections)
		for _ = 2, 50 do
			cycle()
		end
		local final = w.engine.census()
		t.expect(final.live).toBe(baseline.live)
		t.expect(final.connections).toBe(baseline.connections)
		w.close()
	end)

	t.it("motion refuses to start outside an owner and a disposed owner cannot restart its clock", function()
		local w = world({ reducedMotion = false })
		local okTimeline, timelineError = pcall(function()
			return w.runtime.timeline({ duration = 1 })
		end)
		t.expect(okTimeline).toBe(false)
		t.expect(string.find(tostring(timelineError), "no-active-owner", 1, true) ~= nil).toBe(true)
		local okTween, tweenError = pcall(function()
			return w.runtime.tween(function()
				return 1
			end, { seconds = 1 })
		end)
		t.expect(okTween).toBe(false)
		t.expect(string.find(tostring(tweenError), "no-active-owner", 1, true) ~= nil).toBe(true)
		local clock, target = nil, Compose.cell(0)
		local moving
		local root = Compose.createRootOwner(function()
			clock = w.runtime.timeline({ duration = 1, autoplay = false })
			moving = w.runtime.tween(function(use)
				return use(target)
			end, { seconds = 1 })
		end, w.runtime.reactor)
		target:set(10)
		t.expect(w.engine.heartbeat.count()).toBe(1)
		w.step(0.1)
		local midway = moving:peek()
		t.expect(midway > 0 and midway < 10).toBe(true)
		root.dispose()
		t.expect(w.engine.heartbeat.count()).toBe(0)
		clock:play()
		clock:restart()
		target:set(20)
		t.expect(w.engine.heartbeat.count()).toBe(0)
		t.expect(clock.moving:peek()).toBe(false)
		w.step(0.5)
		t.expect(moving:peek()).toBe(midway)
		t.expect(clock.progress:peek()).toBe(0)
		w.close()
	end)

	t.it("a row reveal reversed mid-flight continues from its painted offset", function()
		local w = world({ reducedMotion = false })
		local open = Compose.cell(nil :: string?)
		local stop, screen = w.mount(function(UI)
			return UI.RowActions({
				content = UI.Button "Body" { label = "Row" },
				open = open,
				trailing = { { id = "Archive", label = "Archive" } },
			})
		end)
		local node = find(screen, "Content").Parent
		node.AbsoluteSize = w.engine.types.Vector2.new(320, 44)
		local content = find(node, "Content")
		open:set("trailing")
		w.step(0.05)
		local painted = content.Position.X.Offset
		t.expect(painted < 0 and painted > -88).toBe(true)
		open:set(nil)
		t.expect(content.Position.X.Offset).toBe(painted)
		w.step(1 / 60)
		local next = content.Position.X.Offset
		t.expect(math.abs(next - painted) < 20).toBe(true)
		local farthest = math.min(painted, next)
		for _ = 1, 60 do
			w.step(1 / 60)
			farthest = math.min(farthest, content.Position.X.Offset)
		end
		t.expect(farthest > -88).toBe(true)
		t.expect(math.abs(content.Position.X.Offset) < 0.01).toBe(true)
		stop()
		w.close()
	end)

	t.it("an alert reopened mid-exit continues from its painted opacity", function()
		local w = world({ reducedMotion = false })
		local shown = Compose.cell(false)
		local stop, screen = w.mount(function(UI)
			return UI.Alert({ isPresented = shown, title = "Again", transition = { seconds = 0.2 } })
		end)
		shown:set(true)
		w.step(0.3)
		local panel = find(screen, "AlertPanel")
		shown:set(false)
		w.step(0.1)
		local fading = panel.GroupTransparency
		t.expect(fading > 0 and fading < 1).toBe(true)
		shown:set(true)
		t.expect(find(screen, "AlertPanel")).toBe(panel)
		t.expect(panel.GroupTransparency).toBe(fading)
		w.step(1 / 60)
		t.expect(panel.GroupTransparency < fading).toBe(true)
		t.expect(fading - panel.GroupTransparency < 0.1).toBe(true)
		w.step(0.3)
		t.expect(panel.GroupTransparency).toBe(0)
		stop()
		w.close()
	end)
end)

t.describe("theme paint transitions", function()
	local function isPaint(property: string, value: any): boolean
		return typeof(value) == "Color3" or string.find(property, "Transparency$") ~= nil
	end

	t.it("every shipped package transitions exactly its paint properties on one shared timing", function()
		local themePackages = require("../tools/lune/theme_packages")
		local packages: { any } = { themes.neutralPackage() }
		for _, name in themePackages.shippable() do
			local module: any = (require :: any)("../examples/themes/" .. name)
			local package, report = module.build(themes)
			t.expect(report.ok).toBe(true)
			table.insert(packages, package)
		end
		t.expect(#packages >= 9).toBe(true)
		for _, package in packages do
			local seconds = (package.metrics and package.metrics.motion and package.metrics.motion.normal) or 0.2
			for _, mode in { "full", "reduced", "off" } do
				local w = world({})
				local stop, sheet = w.runtime.mount(function()
					return themes.createStyleSheet(w.runtime, package, {
						types = w.engine.types,
						reducedMotion = mode == "reduced",
						transition = if mode == "off" then false else nil,
					})
				end, w.engine.new("Folder"))
				local shared = nil
				local checked = 0
				for _, rule in sheet:GetChildren() do
					if rule.ClassName == "StyleRule" then
						local properties = rule:GetProperties()
						local transitions = rule:GetPropertyTransitions()
						for property, value in properties do
							if isPaint(property, value) then
								local timing = transitions[property]
								t.expect(timing ~= nil).toBe(true)
								shared = shared or timing
								t.expect(timing).toBe(shared)
								checked += 1
							else
								t.expect(transitions[property]).toBe(nil)
							end
						end
						for property in transitions do
							t.expect(properties[property] ~= nil).toBe(true)
						end
					end
				end
				t.expect(checked > 30).toBe(true)
				t.expect(shared.Time).toBe(if mode == "full" then seconds else 0)
				t.expect(shared.EasingStyle).toBe(w.engine.types.Enum.EasingStyle.Quad)
				t.expect(shared.EasingDirection).toBe(w.engine.types.Enum.EasingDirection.Out)
				stop()
				w.close()
			end
		end
	end)
end)

t.describe("match3 cascade order and input lock", function()
	local match3 = require("../examples/gallery/examples/07_match3")
	local gallery = require("../examples/gallery/client/screen")
	local dropBoard = {
		{ "b", "c", "d", "e", "a", "b" },
		{ "c", "d", "e", "a", "b", "c" },
		{ "a", "a", "b", "d", "e", "a" },
		{ "d", "e", "a", "b", "c", "d" },
		{ "e", "a", "b", "c", "d", "e" },
		{ "a", "b", "c", "d", "e", "a" },
	}

	local function newGame(): (any, any)
		local engine: any = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local target = engine.new("Folder")
		local viewport = Compose.cell({ width = 800, height = 600 })
		local ctx: any = {
			Facet = Facet,
			Compose = Compose,
			runtime = runtime,
			Host = runtime.constructors,
			types = engine.types,
			inputTarget = target,
			worldTarget = engine.new("Folder"),
			guiService = engine.new("GuiService"),
			viewport = viewport,
			runService = { Heartbeat = engine.heartbeat },
			target = target,
			engine = engine,
		}
		local game
		local stop, node = runtime.mount(function()
			gallery.configure(ctx)
			ctx.UI = Facet.controls(
				runtime,
				{ types = engine.types, viewport = viewport, reducedMotion = ctx.reducedMotion } :: any
			)
			game = match3.build(ctx)
			return ctx.Host.ScreenGui "GameScreen" { game.screen() }
		end, target)
		ctx.node = node
		ctx.stop = function()
			stop()
			runtime:dispose()
		end
		game.debugSetBoard(dropBoard)
		return game, ctx
	end

	local function hitAt(game: any, ctx: any, row: number, col: number): any
		return find(find(ctx.node, "tile" .. game.tileIdAt(row, col)), "hit")
	end

	local function gamepadTap(ctx: any, hit: any)
		hit.Activated.fire({
			UserInputType = ctx.types.Enum.UserInputType.Gamepad1,
			KeyCode = ctx.types.Enum.KeyCode.ButtonA,
		})
	end

	t.it(
		"removes before gravity before refill, refuses taps while settling and unlocks after the last cascade",
		function()
			local game, ctx = newGame()
			local everSeen: { [number]: boolean } = {}
			for _, id in game.tileIds() do
				t.expect(everSeen[id]).toBe(nil)
				everSeen[id] = true
			end
			game.swap(3, 3, 4, 3)
			t.expect(game.isResolving()).toBe(true)
			local frames = 0
			local refused = 0
			while game.phase() ~= "idle" and frames < 2400 do
				t.expect(game.isResolving()).toBe(true)
				if frames % 20 == 5 then
					local hit = hitAt(game, ctx, 6, 6)
					local movesBefore, phaseBefore = game.moves(), game.phase()
					gamepadTap(ctx, hit)
					t.expect(hit:GetAttribute("selected")).toBe(false)
					t.expect(string.find(game.hintText(), "still settling", 1, true) ~= nil).toBe(true)
					t.expect(game.moves()).toBe(movesBefore)
					t.expect(game.phase()).toBe(phaseBefore)
					refused += 1
				end
				ctx.engine.heartbeat.fire(0.01)
				frames += 1
			end
			t.expect(refused > 2).toBe(true)
			t.expect(game.phase()).toBe("idle")
			t.expect(game.isResolving()).toBe(false)
			t.expect(game.tickHookActive()).toBe(false)
			local log = game.phaseLog()
			t.expect(log[1]).toBe("swap")
			t.expect(log[2]).toBe("mark")
			local cleared = tonumber(string.match(log[3], "^remove:(%d+)$"))
			t.expect(cleared ~= nil and (cleared :: number) >= 3).toBe(true)
			t.expect(log[4]).toBe("gravity")
			local added = tonumber(string.match(log[5], "^refill:(%d+)$"))
			t.expect(added).toBe(cleared)
			t.expect(log[6]).toBe("land")
			t.expect(log[#log]).toBe("idle")
			local order: { string } = {}
			for _, entry in log do
				local name = string.match(entry, "^(%a+)")
				if name ~= order[#order] then
					table.insert(order, name :: string)
				end
			end
			for index = 2, #order do
				local previous, current = order[index - 1], order[index]
				if current == "gravity" then
					t.expect(previous).toBe("remove")
				elseif current == "refill" then
					t.expect(previous).toBe("gravity")
				end
			end
			t.expect(#game.tileIds()).toBe(36)
			t.expect(game.moves()).toBe(1)
			local hit = hitAt(game, ctx, 6, 6)
			gamepadTap(ctx, hit)
			t.expect(hit:GetAttribute("selected")).toBe(true)
			t.expect(string.find(game.hintText(), "still settling", 1, true)).toBe(nil)
			gamepadTap(ctx, hit)
			t.expect(hit:GetAttribute("selected")).toBe(false)
			t.expect(game.moves()).toBe(1)
			ctx.stop()
			t.expect(ctx.engine.heartbeat.count()).toBe(0)
		end
	)

	t.it("never reuses a tile id across refills", function()
		local game, ctx = newGame()
		local seen: { [number]: boolean } = {}
		for _, id in game.tileIds() do
			seen[id] = true
		end
		local total = #game.tileIds()
		game.swap(3, 3, 4, 3)
		for _ = 1, 2400 do
			if game.phase() == "idle" then
				break
			end
			ctx.engine.heartbeat.fire(0.01)
			for _, id in game.tileIds() do
				if not seen[id] then
					seen[id] = true
					total += 1
				end
			end
		end
		local live: { [number]: boolean } = {}
		for _, id in game.tileIds() do
			t.expect(live[id]).toBe(nil)
			live[id] = true
		end
		t.expect(total > 36).toBe(true)
		ctx.stop()
	end)
end)

t.describe("gallery motion setting", function()
	t.it("offers Full and Reduced, never on or off wording, and follows the native preference", function()
		local gallery = require("../examples/gallery/client/screen")
		local engine: any = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local target, gui = engine.new("Folder"), engine.new("GuiService")
		local input = engine.new("UserInputService")
		input.PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
		input.GetFocusedTextBox = function()
			return nil
		end
		local ctx: any = {
			Facet = Facet,
			Compose = Compose,
			runtime = runtime,
			Host = runtime.constructors,
			types = engine.types,
			viewport = Compose.cell({ width = 1280, height = 720 }),
			inputTarget = target,
			guiService = gui,
			runService = { Heartbeat = engine.heartbeat },
			selection = Compose.cell("first"),
			theme = Compose.cell(themes.neutralPackage()),
			themeMode = Compose.cell("light"),
		}
		ctx.packages = { Neutral = ctx.theme:peek() }
		local stop, root = runtime.mount(function()
			gallery.configure(ctx)
			ctx.UI = Facet.controls(
				runtime,
				{
					types = engine.types,
					viewport = ctx.viewport,
					inputParent = target,
					services = { GuiService = gui, UserInputService = input },
					theme = ctx.theme,
					reducedMotion = ctx.reducedMotion,
				} :: any
			)
			ctx.demos = { { id = "first", title = "First", kind = "fixture", module = "first" } }
			ctx.load = function()
				return {
					build = function(page)
						return {
							screen = function()
								return page.Host.Frame({ Name = "FirstDemo" })
							end,
						}
					end,
				}
			end
			return ctx.Host.ScreenGui "GalleryTest" { gallery.build(ctx) }
		end, target)
		local settings
		for _, node in root:GetDescendants() do
			if node.Name == "Settings" and node:IsA("TextButton") then
				settings = node
			end
		end
		settings.Activated.fire()
		t.expect(find(root, "GallerySettings") ~= nil).toBe(true)
		local sheet = find(target, "MotionNote").Parent
		t.expect(sheet.Name).toBe("Settings")
		local picker = find(sheet, "Motion")
		t.expect(picker ~= nil).toBe(true)
		local full, reduced = find(picker, "full"), find(picker, "reduced")
		t.expect(full ~= nil and reduced ~= nil).toBe(true)
		local optionCount = 0
		for _, node in picker:GetDescendants() do
			if node:IsA("TextButton") and node:GetAttribute("label") ~= nil then
				optionCount += 1
			end
		end
		t.expect(optionCount).toBe(2)
		t.expect(full:GetAttribute("label")).toBe("Full")
		t.expect(reduced:GetAttribute("label")).toBe("Reduced")
		local wording: { string } = {}
		for _, node in sheet:GetDescendants() do
			local ok, text = pcall(function()
				return node.Text
			end)
			if ok and type(text) == "string" and text ~= "" then
				table.insert(wording, text)
			end
			local label = node:GetAttribute("label")
			if type(label) == "string" then
				table.insert(wording, label)
			end
		end
		t.expect(#wording > 5).toBe(true)
		for _, text in wording do
			local lower = string.lower(text)
			for _, banned in { "^off$", "^on$", "%f[%a]off%f[%A]", "%f[%a]disabled?%f[%A]", "%f[%a]enabled?%f[%A]" } do
				t.expect(`{text} matches {banned}: {string.find(lower, banned) ~= nil}`)
					.toBe(`{text} matches {banned}: false`)
			end
		end
		t.expect(full:GetAttribute("selected")).toBe(true)
		reduced.Activated.fire()
		t.expect(ctx.reducedMotion:peek()).toBe(true)
		t.expect(ctx.motionMode:peek()).toBe("reduced")
		t.expect(reduced:GetAttribute("selected")).toBe(true)
		full.Activated.fire()
		t.expect(ctx.reducedMotion:peek()).toBe(false)
		t.expect(full:GetAttribute("selected")).toBe(true)
		gui.ReducedMotionEnabled = true
		t.expect(ctx.reducedMotion:peek()).toBe(true)
		t.expect(reduced:GetAttribute("selected")).toBe(true)
		full.Activated.fire()
		t.expect(ctx.reducedMotion:peek()).toBe(true)
		t.expect(ctx.motionMode:peek()).toBe("reduced")
		find(sheet, "FollowRobloxMotion").Activated.fire()
		gui.ReducedMotionEnabled = false
		t.expect(ctx.reducedMotion:peek()).toBe(false)
		t.expect(full:GetAttribute("selected")).toBe(true)
		stop()
		runtime:dispose()
	end)
end)

t.describe("performance lab motion flight", function()
	t.it(
		"profiles a live animation flight apart from the idle control and releases it on the next selection",
		function()
			local nativeApp = require("../bench/native_app")
			local lab = require("../examples/performance/lab/perf_lab")
			local modules = {
				sensory = require("../examples/performance/lab/sensory"),
				dataset = require("../examples/performance/lab/dataset"),
				rows = require("../examples/performance/lab/rows"),
				capture = require("../examples/performance/lab/capture"),
				workloads = require("../examples/performance/lab/workloads"),
			}
			local labWorld: any = nativeApp()
			local probe: any
			labWorld.heartbeat = labWorld.engine.heartbeat
			labWorld.captureFacts = function()
				return {
					evidenceClass = "lune",
					capturedAtIso = "2026-09-23T00:00:00Z",
					sourceStamp = "test",
					placeName = "headless",
					viewport = "800x600",
					orientation = "landscape",
					graphicsQualityLevel = "n/a",
					frameTarget = "n/a",
					studioVersion = "n/a",
					deviceLabel = "lune",
					thermalNote = "n/a",
				}
			end
			labWorld.probe = function(value)
				probe = value
			end
			labWorld.runtime.mount(function()
				return labWorld.Host.ScreenGui({ lab.build(labWorld, modules) })
			end, labWorld.target)
			probe.select("idle-baseline", 100)
			for _ = 1, 20 do
				probe.step(1 / 60)
				labWorld.frame(1 / 60)
			end
			t.expect(probe.state().iterations).toBe(0)
			local idleRow = probe.capture()
			t.expect(idleRow.captureFrames).toBe(0)
			t.expect(#idleRow.scopes.controlStepMs).toBe(0)
			t.expect(idleRow.scenario).toBe("idle-baseline")
			local resting = labWorld.engine.heartbeat.count()
			probe.select("motion-flight", 100)
			local active = probe.state().active
			t.expect(#active.springs).toBe(24)
			t.expect(#active.nodes).toBe(24)
			local chips = table.clone(active.nodes)
			local previous: { number } = {}
			for index, chip in chips do
				previous[index] = chip.Position.Y.Scale
			end
			local movedEveryFrame = true
			for _ = 1, 30 do
				probe.step(1 / 60)
				labWorld.frame(1 / 60)
				for index, chip in chips do
					local now = chip.Position.Y.Scale
					if now == previous[index] then
						movedEveryFrame = false
					end
					previous[index] = now
				end
			end
			t.expect(movedEveryFrame).toBe(true)
			t.expect(active.n).toBe(30)
			t.expect(active.beats >= 2).toBe(true)
			t.expect(labWorld.engine.heartbeat.count() > resting).toBe(true)
			local row = probe.capture()
			t.expect(#modules.capture.problems(row)).toBe(0)
			t.expect(row.scenario).toBe("motion-flight")
			t.expect(row.captureFrames).toBe(30)
			t.expect(#row.scopes.controlStepMs).toBe(30)
			t.expect(row.frame.measured).toBe(true)
			t.expect(row.counters.iterations).toBe(30)
			probe.select("idle-baseline", 100)
			for _, chip in chips do
				t.expect(chip:isDestroyed()).toBe(true)
			end
			t.expect(probe.state().active ~= active).toBe(true)
			t.expect(labWorld.engine.heartbeat.count()).toBe(resting)
			local held = active.springs[1]:peek()
			labWorld.frame(0.5)
			t.expect(active.springs[1]:peek()).toBe(held)
			labWorld.dispose()
			t.expect(labWorld.engine.heartbeat.count()).toBe(0)
		end
	)
end)
