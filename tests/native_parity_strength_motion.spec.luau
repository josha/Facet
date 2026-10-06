--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type ScreenGuiConstructor = typeof(require("@repo/tools/typecheck/aliases").ScreenGuiConstructor)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type MotionLevel = typeof(require("@repo/tools/typecheck/aliases").MotionLevel)
	local FixtureComposeTypes = require("../src/vendor/compose/core")
	local FixtureRadialTypes = require("../src/ui/radial_types")
	local FixtureCollectionTypes = require("../src/ui/collection_types")
	local FixtureNavigationTypes = require("../src/ui/navigation_types")
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local transitionOf = require("./lib/transition")
	local fadeKit = require("./lib/fade")
	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local pathShapes = require("../src/ui/nav_path_shapes")
	local Compose: ComposeModule = Facet.Compose
	local themes = Facet.themes

	local function openSettings(root: any)
		local function seek(node: any, name: string): any
			if node.Name == name then
				return node
			end
			for _, child in node:GetChildren() do
				local found = seek(child, name)
				if found then
					return found
				end
			end
			return nil
		end
		local layer = root:FindFirstAncestorWhichIsA("LayerCollector") or root
		seek(layer, "Showcase").Activated.fire()
		seek(seek(layer, "Section"), "settings").Activated.fire()
	end
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
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
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
			local stop, node: any = runtime.mount(function()
				return ((runtime.constructors.ScreenGui :: unknown) :: ScreenGuiConstructor)({
					build(UI, runtime.constructors),
				})
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

	verifyHarness:suite("indeterminate progress lifetime", function()
		verifyHarness:case("an indeterminate bar keeps travelling in its third second and stops dead with its owner", {
			id = "native_parity_strength_motion::indeterminate progress lifetime::an indeterminate bar keeps travelling in its third second and stops dead with its owner",
			run = function()
				local w = world({ motionLevel = "normal" })
				local stop, screen = w.mount(function(UI: FacetControls)
					return UI.ProgressView({})
				end)
				local fill = find(screen, "Fill1")
				Verify.expect(find(screen, "FillClip").ClipsDescendants):toBe(true)
				Verify.expect(w.engine.heartbeat.count() > 0):toBe(true)
				local changes, last = 0, fill.Position.X.Scale
				for frame = 1, 180 do
					w.step(1 / 60)
					local now = fill.Position.X.Scale
					Verify.expect(now >= -0.3 - 1e-6 and now <= 1 + 1e-6):toBe(true)
					if frame > 120 and now ~= last then
						changes += 1
					end
					last = now
				end
				Verify.expect(changes > 50):toBe(true)
				stop()
				Verify.expect((w.engine.heartbeat.count())):toBe(0)
				local held = fill.Position.X.Scale
				w.step(1)
				Verify.expect(fill.Position.X.Scale):toBe(held)
				Verify.expect((fill.isDestroyed())):toBe(true)
				w.close()
			end,
		})

		verifyHarness:case("an indeterminate view built under an owner and never presented stops with that owner", {
			id = "native_parity_strength_motion::indeterminate progress lifetime::an indeterminate view built under an owner and never presented stops with that owner",
			run = function()
				local w = world({ motionLevel = "normal" })
				local view
				local root = Compose.createRootOwner(function()
					view = w.UI.ProgressView({})
				end, w.runtime.reactor)
				Verify.expect(view.Parent):toBe(nil)
				local fill = find(view, "Fill1")
				local before = fill.Position.X.Scale
				w.step(0.2)
				Verify.expect(fill.Position.X.Scale ~= before):toBe(true)
				Verify.expect(w.engine.heartbeat.count() > 0):toBe(true)
				root.dispose()
				Verify.expect((w.engine.heartbeat.count())):toBe(0)
				local held = fill.Position.X.Scale
				w.step(0.5)
				Verify.expect(fill.Position.X.Scale):toBe(held)
				w.close()
			end,
		})

		verifyHarness:case("unmounting and disposing the runtime are safe in either order", {
			id = "native_parity_strength_motion::indeterminate progress lifetime::unmounting and disposing the runtime are safe in either order",
			run = function()
				for _, unmountFirst in { true, false } do
					local w = world({ motionLevel = "normal" })
					local stop, screen = w.mount(function(UI: FacetControls)
						return UI.ProgressView({ presentation = "spinner" :: "spinner" })
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
					Verify.expect(ok):toBe(true)
					Verify.expect((w.engine.heartbeat.count())):toBe(0)
					local held = dot.BackgroundTransparency
					w.step(0.5)
					Verify.expect(dot.BackgroundTransparency):toBe(held)
				end
			end,
		})

		verifyHarness:case("a plain determinate bar starts no cycle under either motion policy", {
			id = "native_parity_strength_motion::indeterminate progress lifetime::a plain determinate bar starts no cycle under either motion policy",
			run = function()
				for _, reduced in { false, true } do
					local w = world({ motionLevel = if reduced then "none" else "normal" })
					local value = Compose.cell(0.4)
					local stop, screen = w.mount(function(UI: FacetControls)
						return UI.ProgressView({ value = value })
					end)
					Verify.expect((w.engine.heartbeat.count())):toBe(0)
					Verify.expect(find(screen, "Fill1").Size.X.Scale):toBeCloseTo(0.4, 1e-4)
					Verify.expect((find(screen, "Trail"))):toBe(nil)
					value:set(0.1)
					Verify.expect((w.engine.heartbeat.count())):toBe(0)
					Verify.expect(find(screen, "Fill1").Size.X.Scale):toBeCloseTo(0.1, 1e-4)
					value:set(0.9)
					w.step(0.3)
					Verify.expect((w.engine.heartbeat.count())):toBe(0)
					Verify.expect(find(screen, "Fill1").Size.X.Scale):toBeCloseTo(0.9, 1e-4)
					stop()
					w.close()
				end
			end,
		})

		verifyHarness:case("an indeterminate view under reduced motion still runs its cycle and says Loading", {
			id = "native_parity_strength_motion::indeterminate progress lifetime::an indeterminate view under reduced motion still runs its cycle and says Loading",
			run = function()
				local w = world({ motionLevel = "none" })
				local stop, screen = w.mount(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.ProgressView({ presentation = "spinner" :: "spinner" }) :: unknown,
						UI.ProgressView({ showValue = true }),
					})
				end)
				Verify.expect(w.engine.heartbeat.count() >= 2):toBe(true)
				Verify.expect(find(screen, "Value").Text):toBe("Loading")
				local indicator = find(screen, "Indicator")
				local start = segmentReading(indicator)
				w.step(0.375, 0.125)
				Verify.expect(segmentReading(indicator) ~= start):toBe(true)
				stop()
				Verify.expect((w.engine.heartbeat.count())):toBe(0)
				w.close()
			end,
		})
	end)

	verifyHarness:suite("spinner paint", function()
		verifyHarness:case("draws eight fixed square dots at the theme dot size and no bar", {
			id = "native_parity_strength_motion::spinner paint::draws eight fixed square dots at the theme dot size and no bar",
			run = function()
				local package = Compose.cell(themes.neutralPackage())
				local w2 = world({ motionLevel = "normal", theme = package })
				local stop, screen = w2.mount(function(UI: FacetControls)
					return UI.ProgressView({ presentation = "spinner" :: "spinner" })
				end)
				local indicator = find(screen, "Indicator")
				local dotSize = themes.neutralPackage().metrics.controls.progress.spinnerDotSize
				Verify.expect((find(screen, "Track"))):toBe(nil)
				Verify.expect((find(screen, "Fill1"))):toBe(nil)
				Verify.expect((find(indicator, "Segment9"))):toBe(nil)
				local sizes = {}
				for index = 1, 8 do
					local dot = find(indicator, "Segment" .. index)
					Verify.expect(dot ~= nil):toBe(true)
					Verify.expect((dot:HasTag("facet-fill"))):toBe(true)
					Verify.expect(dot.Size):toBe(w2.engine.types.UDim2.fromOffset(dotSize, dotSize))
					Verify.expect(dot:FindFirstChildWhichIsA("UICorner").CornerRadius.Scale):toBe(1)
					sizes[index] = dot.Size
				end
				for _ = 1, 30 do
					w2.step(1 / 60)
					for index = 1, 8 do
						Verify.expect(find(indicator, "Segment" .. index).Size):toBe(sizes[index])
					end
				end
				local grown = themes.neutralPackage()
				grown.metrics.controls.progress.spinnerDotSize = dotSize + 3
				package:set(grown)
				Verify.expect(find(indicator, "Segment1").Size)
					:toBe(w2.engine.types.UDim2.fromOffset(dotSize + 3, dotSize + 3))
				stop()
				w2.close()
			end,
		})

		verifyHarness:case("moves the brightest dot around the ring while every dot stays visible", {
			id = "native_parity_strength_motion::spinner paint::moves the brightest dot around the ring while every dot stays visible",
			run = function()
				local w = world({ motionLevel = "normal" })
				local stop, screen = w.mount(function(UI: FacetControls)
					return UI.ProgressView({ presentation = "spinner" :: "spinner" })
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
						Verify.expect(value >= 0 and value <= 0.85):toBe(true)
					end
				end
				Verify.expect(count >= 6):toBe(true)
				stop()
				w.close()
			end,
		})

		verifyHarness:case(
			"writes the spinner on full-motion frames and quantizes a mid-run switch without restarting",
			{
				id = "native_parity_strength_motion::spinner paint::writes the spinner on full-motion frames and quantizes a mid-run switch without restarting",
				run = function()
					local reduced = Compose.cell(false)
					local w = world({
						motionLevel = (Compose.formula(function(use: Use): "normal" | "limited" | "none"
							return if use(reduced) then "none" else "normal"
						end) :: unknown) :: MotionLevel,
					})
					local stop, screen = w.mount(function(UI: FacetControls)
						return UI.ProgressView({ presentation = "spinner" :: "spinner" })
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
					Verify.expect(fullCount):toBe(20)
					w.step(0.2)
					reduced:set(true)
					for index = 1, 8 do
						local expected = ((index / 8 - 0.5) % 1) * 0.85
						Verify.expect(find(indicator, "Segment" .. index).BackgroundTransparency)
							:toBeCloseTo(expected, 1e-9)
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
					Verify.expect(reducedCount >= 2):toBe(true)
					Verify.expect(fullCount > reducedCount):toBe(true)
					stop()
					w.close()
				end,
			}
		)
	end)

	verifyHarness:suite("circular progress motion", function()
		verifyHarness:case("travels the indeterminate head while the sweep stays a fixed quarter turn", {
			id = "native_parity_strength_motion::circular progress motion::travels the indeterminate head while the sweep stays a fixed quarter turn",
			run = function()
				local w = world({ motionLevel = "normal" })
				local stop, screen = w.mount(function(UI: FacetControls)
					return UI.ProgressView({ presentation = "circular" :: "circular", diameter = 100 })
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
					Verify.expect(math.abs(sweep() - 90) < 1e-3):toBe(true)
					if math.abs(angleOf(arc:GetControlPoints()[1]) - startHead) > 0.001 then
						moved = true
					end
				end
				Verify.expect(moved):toBe(true)
				Verify.expect((find(screen, "RingFill"))):toBe(arc)
				stop()
				w.close()
			end,
		})

		verifyHarness:case("keeps the reduced-motion ring travelling in a few visible poses each second", {
			id = "native_parity_strength_motion::circular progress motion::keeps the reduced-motion ring travelling in a few visible poses each second",
			run = function()
				local function poses(reducedMotion: boolean, frames: number, dt: number): (number, any)
					local w = world({ motionLevel = if reducedMotion then "none" else "normal" })
					local stop, screen = w.mount(function(UI: FacetControls)
						return UI.ProgressView({ presentation = "circular" :: "circular", diameter = 100 })
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
				local w = world({ motionLevel = "none" })
				local stop, screen = w.mount(function(UI: FacetControls)
					return UI.ProgressView({ presentation = "circular" :: "circular", diameter = 100 })
				end)
				local arc = find(screen, "RingFill")
				local start = angleOf(arc:GetControlPoints()[1])
				for _ = 1, 3 do
					w.step(0.05)
					Verify.expect(math.abs(angleOf(arc:GetControlPoints()[1]) - start) < 1e-9):toBe(true)
				end
				w.step(0.15)
				Verify.expect(math.abs(angleOf(arc:GetControlPoints()[1]) - start) > 0.001):toBe(true)
				stop()
				w.close()
				local reducedCount = poses(true, 20, 0.05)
				Verify.expect(reducedCount >= 3 and reducedCount <= 8):toBe(true)
				local fullCount = poses(false, 20, 0.05)
				Verify.expect(fullCount > reducedCount):toBe(true)
			end,
		})

		verifyHarness:case("ends a quarter value at three o'clock and closes the ring at the full value", {
			id = "native_parity_strength_motion::circular progress motion::ends a quarter value at three o'clock and closes the ring at the full value",
			run = function()
				local w = world({ motionLevel = "none" })
				local value = Compose.cell(0.25)
				local stop, screen = w.mount(function(UI: FacetControls)
					return UI.ProgressView({
						presentation = "circular" :: "circular",
						value = value,
						diameter = 100,
						thickness = 10,
					})
				end)
				local arc = find(screen, "RingFill")
				local points = arc:GetControlPoints()
				Verify.expect((near(angleOf(points[1]), 0, 1e-3))):toBe(true)
				Verify.expect((near(angleOf(points[#points]), 90, 1e-3))):toBe(true)
				Verify.expect((near(points[#points].Position.Y.Scale, 0.5, 1e-5))):toBe(true)
				Verify.expect(points[#points].Position.X.Scale > 0.9):toBe(true)
				value:set(0.65)
				points = arc:GetControlPoints()
				Verify.expect((near(angleOf(points[#points]), 234, 1e-3))):toBe(true)
				Verify.expect(points[#points].Position.X.Scale < 0.5):toBe(true)
				Verify.expect(points[#points].Position.Y.Scale > 0.5):toBe(true)
				value:set(1)
				points = arc:GetControlPoints()
				Verify.expect((near(points[1].Position.X.Scale, points[#points].Position.X.Scale, 1e-5))):toBe(true)
				Verify.expect((near(points[1].Position.Y.Scale, points[#points].Position.Y.Scale, 1e-5))):toBe(true)
				Verify.expect((find(screen, "RingFill"))):toBe(arc)
				stop()
				w.close()
			end,
		})
	end)

	verifyHarness:suite("arc shape math", function()
		verifyHarness:case("closes a full ring with nine points on the radius", {
			id = "native_parity_strength_motion::arc shape math::closes a full ring with nine points on the radius",
			run = function()
				local points = pathShapes.ring()
				Verify.expect(#points):toBe(9)
				Verify.expect((near(points[1].x, points[9].x))):toBe(true)
				Verify.expect((near(points[1].y, points[9].y))):toBe(true)
				for _, point in points do
					Verify.expect((near(math.sqrt((point.x - 0.5) ^ 2 + (point.y - 0.5) ^ 2), 0.5, 1e-9))):toBe(true)
				end
				local inset = pathShapes.ring({ radius = 0.8 })
				for _, point in inset do
					Verify.expect((near(math.sqrt((point.x - 0.5) ^ 2 + (point.y - 0.5) ^ 2), 0.4, 1e-9))):toBe(true)
				end
			end,
		})

		verifyHarness:case("uses screen angles where zero is up, ninety is right and y grows down", {
			id = "native_parity_strength_motion::arc shape math::uses screen angles where zero is up, ninety is right and y grows down",
			run = function()
				local points = pathShapes.arc(0, 90, { segments = 2 })
				Verify.expect((near(points[1].x, 0.5))):toBe(true)
				Verify.expect((near(points[1].y, 0))):toBe(true)
				Verify.expect((near(points[2].x, 0.5 + 0.5 * math.sin(math.rad(45))))):toBe(true)
				Verify.expect((near(points[2].y, 0.5 - 0.5 * math.cos(math.rad(45))))):toBe(true)
				Verify.expect((near(points[3].x, 1))):toBe(true)
				Verify.expect((near(points[3].y, 0.5))):toBe(true)
				local bottom = pathShapes.arc(90, 90, { segments = 1 })
				Verify.expect((near(bottom[2].x, 0.5))):toBe(true)
				Verify.expect((near(bottom[2].y, 1))):toBe(true)
			end,
		})

		verifyHarness:case("points tangents forward with the exact cubic handle length and mirrors them", {
			id = "native_parity_strength_motion::arc shape math::points tangents forward with the exact cubic handle length and mirrors them",
			run = function()
				for _, case in { { 180, 4 }, { 90, 2 }, { 270, 6 }, { -120, 3 } } do
					local sweep, segments = case[1], case[2]
					local points = pathShapes.arc(0, sweep, { segments = segments })
					Verify.expect(#points):toBe(segments + 1)
					local expected = (4 / 3) * math.tan(math.abs(math.rad(sweep / segments)) / 4) * 0.5
					local direction = if sweep >= 0 then 1 else -1
					Verify.expect((near(points[1].outX, expected * direction, 1e-9))):toBe(true)
					Verify.expect((near(points[1].outY, 0, 1e-9))):toBe(true)
					Verify.expect((near(points[1].inX, -expected * direction, 1e-9))):toBe(true)
					for index, point in points do
						Verify.expect((near(point.inX, -point.outX, 1e-9))):toBe(true)
						Verify.expect((near(point.inY, -point.outY, 1e-9))):toBe(true)
						Verify.expect((near(math.sqrt(point.outX ^ 2 + point.outY ^ 2), expected, 1e-9))):toBe(true)
						local radialX, radialY = point.x - 0.5, point.y - 0.5
						Verify.expect((near(radialX * point.outX + radialY * point.outY, 0, 1e-9))):toBe(true)
						local angle = math.rad(sweep * (index - 1) / segments)
						Verify.expect((near(point.x, 0.5 + 0.5 * math.sin(angle), 1e-9))):toBe(true)
					end
				end
			end,
		})

		verifyHarness:case("ends a larger sweep farther along the circle and refuses more than one hundred points", {
			id = "native_parity_strength_motion::arc shape math::ends a larger sweep farther along the circle and refuses more than one hundred points",
			run = function()
				local previous = -1
				for sweep = 15, 345, 15 do
					local points = pathShapes.arc(0, sweep)
					local finish = points[#points]
					local angle = math.deg(math.atan2(finish.x - 0.5, -(finish.y - 0.5))) % 360
					Verify.expect((near(angle, sweep, 1e-6))):toBe(true)
					Verify.expect(angle > previous):toBe(true)
					previous = angle
					Verify.expect(#points):toBe(math.max(2, math.ceil(sweep / 45)) + 1)
				end
				local clamped = pathShapes.arc(0, 720)
				Verify.expect((near(clamped[1].x, clamped[#clamped].x))):toBe(true)
				Verify.expect((pcall(pathShapes.arc, 0, 360, { segments = 120 }))):toBe(false)
				Verify.expect((pcall(pathShapes.arc, 0, 360, { segments = 99 }))):toBe(true)
				Verify.expect(pathShapes.MAX_CONTROL_POINTS):toBe(100)
			end,
		})
	end)

	verifyHarness:suite("skeleton clock sharing", function()
		verifyHarness:case(
			"shares one clock inside an application, keeps applications apart and detaches with the last skeleton",
			{
				id = "native_parity_strength_motion::skeleton clock sharing::shares one clock inside an application, keeps applications apart and detaches with the last skeleton",
				run = function()
					local engine: any = engineLib.new()
					local runtimeA = Facet.Roblox.createRuntime(engine)
					local runtimeB = Facet.Roblox.createRuntime(engine)
					local UIA = Facet.controls(runtimeA, { types = engine.types, motionLevel = "normal" } :: any)
					local UIB = Facet.controls(runtimeB, { types = engine.types, motionLevel = "normal" } :: any)
					Verify.expect((engine.heartbeat.count())):toBe(0)
					local stopA1, a1 = runtimeA.mount(function()
						return UIA.Skeleton({ form = "line" :: "line", lines = 2 })
					end, engine.new("Folder"))
					Verify.expect((engine.heartbeat.count())):toBe(1)
					local stopA2, a2 = runtimeA.mount(function()
						return UIA.Skeleton({ form = "circle" :: "circle" })
					end, engine.new("Folder"))
					Verify.expect((engine.heartbeat.count())):toBe(1)
					local stopB, b = runtimeB.mount(function()
						return UIB.Skeleton({ form = "box" :: "box" })
					end, engine.new("Folder"))
					Verify.expect((engine.heartbeat.count())):toBe(2)
					engine.heartbeat.fire(0.3)
					local shimmerA1 = find(a1, "Shimmer")
					local shimmerA2 = find(a2, "Shimmer")
					local shimmerB = find(b, "Shimmer")
					Verify.expect(shimmerA1.Offset):toBe(shimmerA2.Offset)
					Verify.expect(shimmerA1.Offset):toBe(shimmerB.Offset)
					stopB()
					Verify.expect((engine.heartbeat.count())):toBe(1)
					local stopB2, b2 = runtimeB.mount(function()
						return UIB.Skeleton({ form = "box" :: "box" })
					end, engine.new("Folder"))
					Verify.expect((engine.heartbeat.count())):toBe(2)
					engine.heartbeat.fire(0.2)
					Verify.expect(find(b2, "Shimmer").Offset ~= shimmerA1.Offset):toBe(true)
					stopA1()
					Verify.expect((engine.heartbeat.count())):toBe(2)
					stopA2()
					Verify.expect((engine.heartbeat.count())):toBe(1)
					local held = shimmerA2.Offset
					engine.heartbeat.fire(0.2)
					Verify.expect(shimmerA2.Offset):toBe(held)
					stopB2()
					Verify.expect((engine.heartbeat.count())):toBe(0)
					runtimeA:dispose()
					runtimeB:dispose()
				end,
			}
		)
	end)

	local function compassItems(onSelect: (string) -> ()): { any }
		local entries = {}
		for _, id in { "N", "E", "S", "W" } do
			table.insert(entries, {
				id = id,
				slot = id,
				label = id,
				completion = "stay" :: "stay",
				onSelect = function()
					onSelect(id)
				end,
			})
		end
		return entries
	end

	verifyHarness:suite("radial retirement motion", function()
		verifyHarness:case("reopening mid-exit continues from the painted opacity and keeps every node", {
			id = "native_parity_strength_motion::radial retirement motion::reopening mid-exit continues from the painted opacity and keeps every node",
			run = function()
				local w = world({ motionLevel = "normal" })
				local opened = Compose.cell(true)
				local stop, screen = w.mount(function(UI: FacetControls)
					return UI.RadialMenu({
						isPresented = opened,
						distribution = "compass" :: "compass",
						items = compassItems(function() end),
					})
				end)
				w.step(0.3)
				local panel, sector = find(screen, "RadialPanel"), find(screen, "Sector-N")
				local paint = find(sector, "Sector")
				local thickness = paint.Thickness
				Verify.expect((fadeKit.of(sector))):toBe(0)
				opened:set(false)
				w.step(0.05)
				local fading = fadeKit.of(sector)
				Verify.expect(fading > 0 and fading < 1):toBe(true)
				Verify.expect(panel.Interactable):toBe(false)
				Verify.expect(paint.Thickness):toBe(thickness)
				opened:set(true)
				Verify.expect((find(screen, "RadialPanel"))):toBe(panel)
				Verify.expect((find(screen, "Sector-N"))):toBe(sector)
				Verify.expect((fadeKit.of(sector))):toBe(fading)
				Verify.expect(panel.Interactable):toBe(true)
				local previous = fadeKit.of(sector)
				for _ = 1, 30 do
					w.step(1 / 60)
					Verify.expect(fadeKit.of(sector) <= previous):toBe(true)
					previous = fadeKit.of(sector)
				end
				Verify.expect((fadeKit.of(sector))):toBe(0)
				opened:set(false)
				w.step(0.4)
				Verify.expect((find(screen, "RadialPanel"))):toBe(nil)
				Verify.expect((sector.isDestroyed())):toBe(true)
				Verify.expect((panel.isDestroyed())):toBe(true)
				stop()
				Verify.expect((w.engine.heartbeat.count())):toBe(0)
				w.close()
			end,
		})

		verifyHarness:case("a retiring branch keeps its geometry, leaves the focus order and then releases", {
			id = "native_parity_strength_motion::radial retirement motion::a retiring branch keeps its geometry, leaves the focus order and then releases",
			run = function()
				local w = world({ motionLevel = "normal" })
				local stop, screen = w.mount(function(UI: FacetControls)
					return UI.RadialMenu({
						isPresented = Compose.cell(true),
						items = {
							{
								id = "Branch",
								label = "Branch",
								children = {
									{ id = "Leaf", label = "Leaf", completion = "stay" :: "stay" },
									{ id = "Twig", label = "Twig", completion = "stay" :: "stay" },
								},
							} :: FixtureRadialTypes.RadialItem<any>,
							{ id = "Other", label = "Other", completion = "stay" :: "stay" } :: FixtureRadialTypes.RadialItem<any>,
						},
					})
				end)
				w.step(0.3)
				local retiring = find(screen, "Sector-Branch")
				local paint = find(retiring, "Sector")
				local thickness, points = paint.Thickness, paint:GetControlPoints()
				local retiringButton = find(retiring, "Branch")
				find(screen, "Branch").Activated.fire()
				Verify.expect((retiring.isDestroyed())):toBe(false)
				Verify.expect(retiring.Parent.Interactable):toBe(false)
				Verify.expect(find(screen, "Sector-Leaf").Parent.Interactable):toBe(true)
				local right = find(screen, "Radial-right")
				local down = find(screen, "Radial-down")
				Verify.expect(right ~= nil and down ~= nil):toBe(true)
				local visited: { [string]: boolean } = {}
				for _ = 1, 4 do
					right.Pressed.fire()
					local selected = w.gui.SelectedObject
					Verify.expect(selected ~= nil):toBe(true)
					Verify.expect(selected == retiringButton):toBe(false)
					Verify.expect((selected:IsDescendantOf(retiring))):toBe(false)
					visited[selected.Name] = true
					down.Pressed.fire()
					Verify.expect(w.gui.SelectedObject == retiringButton):toBe(false)
				end
				Verify.expect(visited.Leaf == true or visited.Twig == true):toBe(true)
				w.step(0.04)
				Verify.expect(fadeKit.of(retiring) > 0 and fadeKit.of(retiring) < 1):toBe(true)
				Verify.expect(paint.Thickness):toBe(thickness)
				Verify.expect(#paint:GetControlPoints()):toBe(#points)
				w.step(0.3)
				Verify.expect((retiring.isDestroyed())):toBe(true)
				stop()
				w.close()
			end,
		})

		verifyHarness:case("reduced motion opens a whole usable ring with a long iconed label under a native theme", {
			id = "native_parity_strength_motion::radial retirement motion::reduced motion opens a whole usable ring with a long iconed label under a native theme",
			run = function()
				local picked = {}
				local package = themes.neutralPackage()
				assert(package.assets).search = { content = "rbxassetid://77" }
				assert(package.icons)["facet:search"] = { default = "search" }
				local w = world({ theme = package })
				w.gui.ReducedMotionEnabled = true
				local opened = Compose.cell(false)
				local stop, screen = w.mount(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						themes.createStyleSheet(w.runtime, package, { types = w.engine.types, motionLevel = "none" }) :: unknown,
						UI.RadialMenu({
							isPresented = opened,
							distribution = "even" :: "even",
							items = {
								{
									id = "look",
									label = "Look at the beautiful mountain",
									icon = "facet:search" :: string,
									labelStyle = "text" :: "text",
									completion = "stay" :: "stay",
									onSelect = function()
										table.insert(picked, "look")
									end,
								} :: FixtureRadialTypes.RadialItem<any>,
								{ id = "wave", label = "Wave", completion = "stay" :: "stay" } :: FixtureRadialTypes.RadialItem<any>,
							},
						}),
					})
				end)
				opened:set(true)
				local sector = find(screen, "Sector-look")
				Verify.expect(sector ~= nil):toBe(true)
				Verify.expect((fadeKit.of(sector))):toBe(0)
				Verify.expect((fadeKit.of(find(screen, "Sector-wave")))):toBe(0)
				local button = find(sector, "look")
				Verify.expect(find(button, "Title").Text):toBe("Look at the beautiful mountain")
				Verify.expect((button:GetAttribute("label"))):toBe("Look at the beautiful mountain")
				Verify.expect(find(button, "LeadingIcon").Image):toBe("rbxassetid://77")
				Verify.expect(button.Size.X.Offset >= 40 and button.Size.Y.Offset >= 36):toBe(true)
				button.Activated.fire()
				Verify.expect((table.concat(picked, ","))):toBe("look")
				opened:set(false)
				Verify.expect((find(screen, "RadialPanel"))):toBe(nil)
				Verify.expect((sector.isDestroyed())):toBe(true)
				stop()
				Verify.expect((w.engine.heartbeat.count())):toBe(0)
				w.close()
			end,
		})
	end)

	verifyHarness:suite("presented surface motion", function()
		verifyHarness:case(
			"fades an alert in from transparent, fades it out over the declared time and then removes it",
			{
				id = "native_parity_strength_motion::presented surface motion::fades an alert in from transparent, fades it out over the declared time and then removes it",
				run = function()
					local w = world({ motionLevel = "normal" })
					local shown = Compose.cell(false)
					local stop, screen = w.mount(function(UI: FacetControls)
						return UI.Alert({
							isPresented = shown,
							title = "Delete?",
							transition = { seconds = 0.2 },
							actions = { { id = "ok", label = "OK" } :: FixtureNavigationTypes.AlertAction<any> },
						})
					end)
					shown:set(true)
					local panel = find(screen, "AlertPanel")
					Verify.expect(panel.ClassName):toBe("Frame")
					Verify.expect((panel:HasTag("facet-panel"))):toBe(true)
					Verify.expect(panel.BackgroundTransparency):toBe(0)
					Verify.expect((fadeKit.of(panel))):toBe(1)
					local previous, enterFrames = 1, 0
					for frame = 1, 30 do
						w.step(1 / 60)
						Verify.expect(fadeKit.of(panel) <= previous):toBe(true)
						previous = fadeKit.of(panel)
						if enterFrames == 0 and previous <= 1e-9 then
							enterFrames = frame
						end
					end
					Verify.expect(enterFrames >= 11 and enterFrames <= 13):toBe(true)
					shown:set(false)
					Verify.expect((find(screen, "AlertPanel"))):toBe(panel)
					Verify.expect(find(screen, "AlertModal").Interactable):toBe(false)
					previous = 0
					local goneAt = 0
					for frame = 1, 30 do
						w.step(1 / 60)
						if find(screen, "AlertPanel") == nil then
							if goneAt == 0 then
								goneAt = frame
							end
						else
							Verify.expect(fadeKit.of(panel) >= previous):toBe(true)
							Verify.expect(fadeKit.of(panel) > 0):toBe(true)
							previous = fadeKit.of(panel)
						end
					end
					Verify.expect(goneAt >= 11 and goneAt <= 13):toBe(true)
					Verify.expect((panel.isDestroyed())):toBe(true)
					stop()
					Verify.expect((w.engine.heartbeat.count())):toBe(0)
					w.close()
				end,
			}
		)

		verifyHarness:case("presents and removes an alert immediately without a transition", {
			id = "native_parity_strength_motion::presented surface motion::presents and removes an alert immediately without a transition",
			run = function()
				local w = world({ motionLevel = "normal" })
				local shown = Compose.cell(false)
				local stop, screen = w.mount(function(UI: FacetControls)
					return UI.Alert({
						isPresented = shown,
						title = "Now",
						transition = false :: false,
						actions = { { id = "ok", label = "OK" } :: FixtureNavigationTypes.AlertAction<any> },
					})
				end)
				shown:set(true)
				local panel = find(screen, "AlertPanel")
				Verify.expect(panel ~= nil):toBe(true)
				Verify.expect((panel:HasTag("facet-panel"))):toBe(true)
				Verify.expect((w.engine.heartbeat.count())):toBe(0)
				shown:set(false)
				Verify.expect((find(screen, "AlertPanel"))):toBe(nil)
				Verify.expect((panel.isDestroyed())):toBe(true)
				stop()
				w.close()
			end,
		})

		verifyHarness:case("a dismissed alert returns selection and refuses input the moment its fade begins", {
			id = "native_parity_strength_motion::presented surface motion::a dismissed alert returns selection and refuses input the moment its fade begins",
			run = function()
				local w = world({ motionLevel = "normal" })
				local shown = Compose.cell(false)
				local cancels = 0
				local stop, screen = w.mount(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Button "Keep" { label = "Keep" } :: unknown,
						UI.Alert({
							isPresented = shown,
							title = "Leave?",
							transition = { seconds = 0.2 },
							actions = {
								{ id = "ok", label = "OK" } :: FixtureNavigationTypes.AlertAction<any>,
								{
									id = "cancel",
									label = "Cancel",
									role = "cancel" :: "cancel",
									onActivate = function()
										cancels += 1
									end,
								} :: FixtureNavigationTypes.AlertAction<any>,
							},
						}),
					})
				end)
				local keep = find(screen, "Keep")
				w.gui.SelectedObject = keep
				shown:set(true)
				w.step(0.3)
				local modal = find(screen, "AlertModal")
				Verify.expect((w.gui.SelectedObject:IsDescendantOf(modal))):toBe(true)
				local back = find(screen, "FacetModalBack")
				Verify.expect(back.Enabled):toBe(true)
				shown:set(false)
				Verify.expect((find(screen, "AlertModal"))):toBe(modal)
				Verify.expect(modal.Interactable):toBe(false)
				Verify.expect(w.gui.SelectedObject):toBe(keep)
				Verify.expect(back.Enabled):toBe(false)
				find(back, "ModalBack").Pressed.fire()
				Verify.expect(cancels):toBe(0)
				w.step(0.1)
				Verify.expect(w.gui.SelectedObject):toBe(keep)
				w.step(0.2)
				Verify.expect((find(screen, "AlertModal"))):toBe(nil)
				Verify.expect(w.gui.SelectedObject):toBe(keep)
				stop()
				w.close()
			end,
		})

		verifyHarness:case("a departing tab layer and a retiring radial slot stop taking input while they fade", {
			id = "native_parity_strength_motion::presented surface motion::a departing tab layer and a retiring radial slot stop taking input while they fade",
			run = function()
				local w = world({ motionLevel = "normal" })
				local selection = Compose.cell("a")
				local opened = Compose.cell(true)
				local stop, screen = w.mount(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.TabView({
							selection = selection,
							placement = "topBar" :: "topBar",
							transition = { seconds = 0.2 },
							tabs = {
								{
									id = "a",
									label = "A",
									content = function(): Instance
										return UI.Button "AContent" { label = "A" }
									end,
								} :: FixtureNavigationTypes.Tab,
								{
									id = "b",
									label = "B",
									content = function(): Instance
										return UI.Button "BContent" { label = "B" }
									end,
								} :: FixtureNavigationTypes.Tab,
							},
						}) :: unknown,
						UI.RadialMenu({
							isPresented = opened,
							distribution = "compass" :: "compass",
							items = compassItems(function() end),
						}),
					})
				end)
				w.step(0.3)
				local layerA = fadeKit.layer(find(screen, "AContent"))
				selection:set("b")
				local layerB = fadeKit.layer(find(screen, "BContent"))
				Verify.expect(layerA.Interactable):toBe(false)
				Verify.expect(layerB.Interactable):toBe(true)
				w.step(0.1)
				Verify.expect(layerA.Parent ~= nil):toBe(true)
				Verify.expect(layerA.Interactable):toBe(false)
				Verify.expect(fadeKit.of(layerA) > 0 and fadeKit.of(layerA) < 1):toBe(true)
				local slot = find(screen, "Sector-N").Parent
				Verify.expect(slot.Interactable):toBe(true)
				opened:set(false)
				Verify.expect(find(screen, "RadialPanel").Interactable):toBe(false)
				w.step(0.05)
				Verify.expect(find(screen, "Sector-N") ~= nil):toBe(true)
				Verify.expect(find(screen, "RadialPanel").Interactable):toBe(false)
				stop()
				w.close()
			end,
		})

		verifyHarness:case(
			"a sheet reversed mid-flight holds its painted height and returns, and reduced motion settles it",
			{
				id = "native_parity_strength_motion::presented surface motion::a sheet reversed mid-flight holds its painted height and returns, and reduced motion settles it",
				run = function()
					local w = world({})
					local detent, shown = Compose.cell("medium"), Compose.cell(true)
					local stop, screen = w.mount(function(UI: FacetControls)
						return UI.Sheet({
							detent = detent,
							isPresented = shown,
							title = "Details",
							content = function(): Instance
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
					Verify.expect(inFlight > medium):toBe(true)
					w.step(2 / 60)
					inFlight = panel.Size.Y.Offset
					detent:set("medium")
					Verify.expect(panel.Size.Y.Offset):toBe(inFlight)
					w.step(1 / 60)
					local returning = panel.Size.Y.Offset
					Verify.expect(math.abs(returning - inFlight) < math.abs(inFlight - medium)):toBe(true)
					local previous, turned = returning, false
					for _ = 1, 60 do
						w.step(1 / 60)
						local height = panel.Size.Y.Offset
						turned = turned or height < previous
						Verify.expect(
							if turned then height <= previous + 1e-6 else height <= inFlight + 2 * (inFlight - medium)
						)
							:toBe(true)
						Verify.expect(height >= medium - 1):toBe(true)
						previous = height
					end
					Verify.expect(turned):toBe(true)
					Verify.expect(math.abs(panel.Size.Y.Offset - medium) < 0.5):toBe(true)
					detent:set("large")
					w.step(1 / 60)
					Verify.expect(panel.Size.Y.Offset > medium):toBe(true)
					w.gui.ReducedMotionEnabled = true
					local large = panel.Size.Y.Offset
					w.step(0.2)
					Verify.expect(panel.Size.Y.Offset):toBe(large)
					detent:set("medium")
					Verify.expect(math.abs(panel.Size.Y.Offset - medium) < 0.5):toBe(true)
					Verify.expect(find(screen, "Kept") ~= nil):toBe(true)
					stop()
					Verify.expect((w.engine.heartbeat.count())):toBe(0)
					w.close()
				end,
			}
		)
	end)

	verifyHarness:suite("tab content transition", function()
		local function tabs(w: any, transition: any, retention: ("all" | "top")?): (() -> (), any, any)
			local selection = Compose.cell("a")
			local stop, screen = w.mount(function(UI: FacetControls)
				return UI.TabView({
					selection = selection,
					placement = "topBar" :: "topBar",
					transition = transition,
					retention = retention,
					tabs = {
						{
							id = "a",
							label = "A",
							content = function(): Instance
								return UI.Button "AContent" { label = "A" }
							end,
						} :: FixtureNavigationTypes.Tab,
						{
							id = "b",
							label = "B",
							content = function(): Instance
								return UI.Button "BContent" { label = "B" }
							end,
						} :: FixtureNavigationTypes.Tab,
					},
				})
			end)
			return stop, screen, selection
		end

		verifyHarness:case("crossfades only the content layers and never the strip", {
			id = "native_parity_strength_motion::tab content transition::crossfades only the content layers and never the strip",
			run = function()
				local w = world({ motionLevel = "normal" })
				local stop, screen, selection = tabs(w, { seconds = 0.2 })
				w.step(0.3)
				local strip = find(screen, "Tabs")
				local cursor = strip
				while cursor do
					Verify.expect(cursor.ClassName == "CanvasGroup"):toBe(false)
					cursor = cursor.Parent
				end
				local layerA = fadeKit.layer(find(screen, "AContent"))
				Verify.expect(layerA.ClassName):toBe("Frame")
				Verify.expect((fadeKit.of(layerA))):toBe(0)
				selection:set("b")
				local layerB = fadeKit.layer(find(screen, "BContent"))
				Verify.expect(layerB.ClassName):toBe("Frame")
				Verify.expect((fadeKit.of(layerB))):toBe(1)
				w.step(0.1)
				Verify.expect(fadeKit.of(layerA) > 0 and fadeKit.of(layerA) < 1):toBe(true)
				Verify.expect(fadeKit.of(layerB) > 0 and fadeKit.of(layerB) < 1):toBe(true)
				Verify.expect(math.abs(fadeKit.of(layerA) + fadeKit.of(layerB) - 1) < 1e-6):toBe(true)
				Verify.expect(layerA.Visible):toBe(true)
				Verify.expect(layerA.Interactable):toBe(false)
				w.step(0.15)
				Verify.expect((fadeKit.of(layerB))):toBe(0)
				Verify.expect(layerA.Visible):toBe(false)
				Verify.expect((layerA.isDestroyed())):toBe(false)
				stop()
				w.close()
			end,
		})

		verifyHarness:case("groups the pages only while they fade and leaves no CanvasGroup once the fade settles", {
			id = "native_parity_strength_motion::tab content transition::groups the pages only while they fade and leaves no CanvasGroup once the fade settles",
			run = function()
				local w = world({ motionLevel = "normal" })
				local stop, screen, selection = tabs(w, { seconds = 0.2 })
				w.step(0.3)
				Verify.expect((fadeKit.groups(screen))):toBe(0)
				selection:set("b")
				w.step(0.1)
				Verify.expect(find(screen, "AContent"):FindFirstAncestorWhichIsA("CanvasGroup") ~= nil):toBe(true)
				Verify.expect(find(screen, "BContent"):FindFirstAncestorWhichIsA("CanvasGroup") ~= nil):toBe(true)
				w.step(0.15)
				Verify.expect((fadeKit.groups(screen))):toBe(0)
				Verify.expect(fadeKit.layer(find(screen, "BContent")).Name):toBe("b")
				Verify.expect(fadeKit.layer(find(screen, "AContent")).Name):toBe("a")
				stop()
				w.close()
			end,
		})

		verifyHarness:case("keeps a departing layer mounted until its fade ends when only the top page is retained", {
			id = "native_parity_strength_motion::tab content transition::keeps a departing layer mounted until its fade ends when only the top page is retained",
			run = function()
				local w = world({ motionLevel = "normal" })
				local stop, screen, selection = tabs(w, { seconds = 0.2 }, "top")
				w.step(0.3)
				local layerA = fadeKit.layer(find(screen, "AContent"))
				selection:set("b")
				w.step(0.1)
				Verify.expect((layerA.isDestroyed())):toBe(false)
				Verify.expect(layerA.Interactable):toBe(false)
				w.step(0.2)
				Verify.expect((find(screen, "AContent"))):toBe(nil)
				Verify.expect((layerA.isDestroyed())):toBe(true)
				stop()
				w.close()
			end,
		})

		verifyHarness:case(
			"switches without a fade when the transition is absent or false and refuses other spellings",
			{
				id = "native_parity_strength_motion::tab content transition::switches without a fade when the transition is absent or false and refuses other spellings",
				run = function()
					for _, transition in { false :: any, nil } do
						local w = world({ motionLevel = "normal" })
						local stop, screen, selection = tabs(w, transition)
						local layerA = fadeKit.layer(find(screen, "AContent"))
						Verify.expect(layerA.ClassName):toBe("Frame")
						selection:set("b")
						Verify.expect(fadeKit.layer(find(screen, "BContent")).Visible):toBe(true)
						Verify.expect(layerA.Visible):toBe(false)
						Verify.expect((w.engine.heartbeat.count())):toBe(0)
						stop()
						w.close()
					end
					for _, bad in
						{ "fade" :: any, { enter = "fade" }, { fade = true }, { seconds = 0.2, class = "container" } }
					do
						local w = world({ motionLevel = "normal" })
						local ok, err = pcall(tabs, w, bad)
						Verify.expect(ok):toBe(false)
						Verify.expect(string.find(tostring(err), "Compose tween options", 1, true) ~= nil):toBe(true)
						w.close()
					end
				end,
			}
		)
	end)

	verifyHarness:suite("row action reveal motion", function()
		local function row(reduced: boolean): (any, () -> (), any, any)
			local w = world({ motionLevel = if reduced then "none" else "normal" })
			local open: FixtureComposeTypes.Cell<("leading" | "trailing")?> =
				Compose.cell(nil :: ("leading" | "trailing")?)
			local stop, screen = w.mount(function(UI: FacetControls)
				return UI.RowActions({
					content = UI.Button "Body" { label = "A preview line long enough to wrap once squeezed" } :: GuiObject,
					open = open,
					leading = { { id = "Read", label = "Read" } :: FixtureCollectionTypes.RowAction },
					trailing = {
						{ id = "Archive", label = "Archive" } :: FixtureCollectionTypes.RowAction,
						{ id = "Flag", label = "Flag" } :: FixtureCollectionTypes.RowAction,
					},
				})
			end)
			local node = find(screen, "Content").Parent
			node.AbsoluteSize = w.engine.types.Vector2.new(320, 44)
			return w, stop, node, open
		end

		verifyHarness:case("a programmatic open uncovers the tray behind the row and never ahead of it", {
			id = "native_parity_strength_motion::row action reveal motion::a programmatic open uncovers the tray behind the row and never ahead of it",
			run = function()
				for _, edge in { "trailing", "leading" } :: { "leading" | "trailing" } do
					local w, stop, node, open = row(false)
					local content, tray = find(node, "Content"), find(node, edge)
					local band = if edge == "leading" then 88 else 176
					open:set(edge)
					local sawPartial, previous = false, 0
					for _ = 1, 60 do
						w.step(1 / 60)
						local travel = math.abs(content.Position.X.Offset)
						local painted = tray.Size.X.Offset
						Verify.expect(painted <= travel + 1e-6):toBe(true)
						Verify.expect(math.abs(painted - math.min(band, travel)) < 1e-6):toBe(true)
						Verify.expect(travel >= previous - 1e-6):toBe(true)
						previous = travel
						if painted > 0 and painted < band then
							sawPartial = true
						end
					end
					Verify.expect(sawPartial):toBe(true)
					Verify.expect(math.abs(tray.Size.X.Offset - band) < 0.01):toBe(true)
					Verify.expect(tray.Visible):toBe(true)
					open:set(nil)
					w.step(1)
					Verify.expect(tray.Visible):toBe(false)
					stop()
					w.close()
				end
			end,
		})

		verifyHarness:case("a leading reveal translates the row content and keeps its width", {
			id = "native_parity_strength_motion::row action reveal motion::a leading reveal translates the row content and keeps its width",
			run = function()
				for _, edge in { "leading", "trailing" } :: { "leading" | "trailing" } do
					local w, stop, node, open = row(false)
					local content = find(node, "Content")
					local width = content.Size
					Verify.expect(width):toBe(w.engine.types.UDim2.new(1, 0, 1, 0))
					open:set(edge)
					local moved = false
					for _ = 1, 60 do
						w.step(1 / 60)
						Verify.expect(content.Size):toBe(width)
						local x = content.Position.X.Offset
						if edge == "leading" then
							Verify.expect(x >= 0):toBe(true)
						else
							Verify.expect(x <= 0):toBe(true)
						end
						moved = moved or x ~= 0
					end
					Verify.expect(moved):toBe(true)
					local expected = if edge == "leading" then 88 else -176
					Verify.expect(math.abs(content.Position.X.Offset - expected) < 0.01):toBe(true)
					stop()
					w.close()
				end
			end,
		})

		verifyHarness:case("a reduced-motion open lands the full band on the same frame", {
			id = "native_parity_strength_motion::row action reveal motion::a reduced-motion open lands the full band on the same frame",
			run = function()
				local w, stop, node, open = row(true)
				open:set("leading")
				Verify.expect(find(node, "leading").Size.X.Offset):toBe(88)
				Verify.expect(find(node, "Content").Position.X.Offset):toBe(88)
				Verify.expect(find(node, "Content").Size):toBe(w.engine.types.UDim2.new(1, 0, 1, 0))
				open:set("trailing")
				Verify.expect(find(node, "trailing").Size.X.Offset):toBe(176)
				Verify.expect(find(node, "Content").Position.X.Offset):toBe(-176)
				stop()
				Verify.expect((w.engine.heartbeat.count())):toBe(0)
				w.close()
			end,
		})
	end)

	local function withGame(gui: any, body: () -> ())
		local env = getfenv(0) :: any
		local previous = env.game
		env.game = {
			GetService = function(_, name: string)
				return if name == "GuiService" then gui else nil
			end,
		}
		local ok, err = pcall(function(): boolean
			body()
			return true
		end)
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

	verifyHarness:suite("reduced motion preference", function()
		verifyHarness:case(
			"the player preference stops control motion live and the sheet keeps its colour fades (limited)",
			{
				id = "native_parity_strength_motion::reduced motion preference::the player preference stops control motion live and the sheet keeps its colour fades (limited)",
				run = function()
					local w = world({})
					withGame(w.gui, function()
						local presses = 0
						local sheet
						local stop, screen = w.mount(function(UI: FacetControls, Host: RobloxHost)
							sheet =
								themes.createStyleSheet(w.runtime, themes.neutralPackage(), { types = w.engine.types })
							return Host.Frame({
								sheet :: unknown,
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
							return transitionOf(text, "TextColor3").Time == 0
						end
						local function pressMoves(): boolean
							button.Activated.fire()
							w.step(0.1)
							local moved = scale.Scale ~= 1
							w.step(1)
							return moved
						end
						Verify.expect((sheetReduced())):toBe(false)
						Verify.expect((pressMoves())):toBe(true)
						button.Activated.fire()
						w.step(0.05)
						Verify.expect(scale.Scale ~= 1):toBe(true)
						w.gui.ReducedMotionEnabled = true
						Verify.expect(scale.Scale):toBe(1)
						Verify.expect((sheetReduced())):toBe(false)
						Verify.expect((pressMoves())):toBe(false)
						w.gui.ReducedMotionEnabled = false
						Verify.expect((sheetReduced())):toBe(false)
						Verify.expect((pressMoves())):toBe(true)
						Verify.expect(presses):toBe(4)
						stop()
						Verify.expect((w.engine.heartbeat.count())):toBe(0)
						Verify.expect((w.gui:GetPropertyChangedSignal("ReducedMotionEnabled").count())):toBe(0)
					end)
					w.close()
				end,
			}
		)

		verifyHarness:case("a surface mounted while the preference is on is reduced from its first press", {
			id = "native_parity_strength_motion::reduced motion preference::a surface mounted while the preference is on is reduced from its first press",
			run = function()
				local w = world({})
				w.gui.ReducedMotionEnabled = true
				withGame(w.gui, function()
					local sheet
					local stop, screen = w.mount(function(UI: FacetControls, Host: RobloxHost)
						sheet = themes.createStyleSheet(w.runtime, themes.neutralPackage(), { types = w.engine.types })
						return Host.Frame({
							sheet :: unknown,
							UI.Button({ Name = "Go", label = "Go", pop = true, onActivate = function() end }),
						})
					end)
					Verify.expect(transitionOf(ruleFor(sheet, ".facet-surface"), "BackgroundColor3").Time):toBe(0.2)
					local scale = find(find(screen, "Go"), "Pop")
					find(screen, "Go").Activated.fire()
					for _ = 1, 10 do
						w.step(1 / 60)
						Verify.expect(scale.Scale):toBe(1)
					end
					stop()
				end)
				w.close()
			end,
		})
	end)

	verifyHarness:suite("invalid entry feedback", function()
		local function field(reduced: any): (any, () -> (), any, any)
			local w = world({
				motionLevel = (Compose.formula(function(use: Use): "normal" | "limited" | "none"
					return if if type(reduced) == "table" then use(reduced) else reduced then "none" else "normal"
				end) :: unknown) :: MotionLevel,
			})
			local invalid = Compose.cell(false)
			local stop, screen = w.mount(function(UI: FacetControls)
				return UI.TextInput({ Name = "Name", value = Compose.cell("ready"), invalid = invalid })
			end)
			return w, stop, find(screen, "Name"), invalid
		end

		verifyHarness:case("pulses on a rising edge without moving the field and returns to rest", {
			id = "native_parity_strength_motion::invalid entry feedback::pulses on a rising edge without moving the field and returns to rest",
			run = function()
				local w, stop, node, invalid = field(false)
				local pulse = find(node, "ValidationPulse")
				local position, size = node.Position, node.Size
				Verify.expect(pulse.Scale):toBe(1)
				invalid:set(true)
				Verify.expect(find(node, "ValidationMessage").Visible):toBe(true)
				local sawPulse = false
				for _ = 1, 20 do
					w.step(1 / 60)
					Verify.expect(pulse.Scale <= 1):toBe(true)
					sawPulse = sawPulse or pulse.Scale < 1
					Verify.expect(node.Position):toBe(position)
					Verify.expect(node.Size):toBe(size)
				end
				Verify.expect(sawPulse):toBe(true)
				Verify.expect(pulse.Scale):toBe(1)
				Verify.expect((w.engine.heartbeat.count())):toBe(0)
				Verify.expect(find(node, "ValidationMessage").Visible):toBe(true)
				stop()
				w.close()
			end,
		})

		verifyHarness:case("a second edge mid-pulse restarts the pulse instead of racing it", {
			id = "native_parity_strength_motion::invalid entry feedback::a second edge mid-pulse restarts the pulse instead of racing it",
			run = function()
				local w, stop, node, invalid = field(false)
				local pulse = find(node, "ValidationPulse")
				invalid:set(true)
				local fresh: { number } = {}
				for index = 1, 10 do
					w.step(1 / 60)
					fresh[index] = pulse.Scale
				end
				Verify.expect(fresh[1] < 1):toBe(true)
				invalid:set(false)
				invalid:set(true)
				for index = 1, 6 do
					w.step(1 / 60)
					Verify.expect(pulse.Scale):toBeCloseTo(fresh[index], 1e-12)
				end
				w.step(0.5)
				Verify.expect(pulse.Scale):toBe(1)
				stop()
				w.close()
			end,
		})

		verifyHarness:case(
			"keeps the message and never pulses under reduced motion, and a live switch settles a pulse",
			{
				id = "native_parity_strength_motion::invalid entry feedback::keeps the message and never pulses under reduced motion, and a live switch settles a pulse",
				run = function()
					local w, stop, node, invalid = field(true)
					local pulse = find(node, "ValidationPulse")
					invalid:set(true)
					Verify.expect(find(node, "ValidationMessage").Visible):toBe(true)
					for _ = 1, 20 do
						w.step(1 / 60)
						Verify.expect(pulse.Scale):toBe(1)
					end
					stop()
					w.close()
					local reduced = Compose.cell(false)
					local w2, stop2, node2, invalid2 = field(reduced)
					local pulse2 = find(node2, "ValidationPulse")
					invalid2:set(true)
					w2.step(0.05)
					Verify.expect(pulse2.Scale < 1):toBe(true)
					reduced:set(true)
					Verify.expect(pulse2.Scale):toBe(1)
					Verify.expect((w2.engine.heartbeat.count())):toBe(0)
					Verify.expect(find(node2, "ValidationMessage").Visible):toBe(true)
					stop2()
					w2.close()
				end,
			}
		)

		verifyHarness:case("disposing mid-pulse leaves nothing armed", {
			id = "native_parity_strength_motion::invalid entry feedback::disposing mid-pulse leaves nothing armed",
			run = function()
				local w, stop, node, invalid = field(false)
				local pulse = find(node, "ValidationPulse")
				invalid:set(true)
				w.step(0.05)
				Verify.expect(pulse.Scale < 1):toBe(true)
				stop()
				Verify.expect((w.engine.heartbeat.count())):toBe(0)
				local held = pulse.Scale
				for _ = 1, 10 do
					w.step(1 / 60)
					Verify.expect(pulse.Scale):toBe(held)
				end
				Verify.expect((pcall(function()
					invalid:set(false)
					invalid:set(true)
				end))):toBe(true)
				Verify.expect((w.engine.heartbeat.count())):toBe(0)
				w.close()
			end,
		})

		verifyHarness:case("refuses an invalid declaration that is not a readable boolean", {
			id = "native_parity_strength_motion::invalid entry feedback::refuses an invalid declaration that is not a readable boolean",
			run = function()
				for _, bad in { true :: any, "yes", 1, Compose.cell("no") } do
					local w = world({})
					local ok, err = pcall(w.mount, function(UI: FacetControls)
						return UI.TextInput({ value = Compose.cell(""), invalid = bad })
					end)
					Verify.expect(ok):toBe(false)
					Verify.expect(string.find(tostring(err), "invalid", 1, true) ~= nil):toBe(true)
					w.close()
				end
			end,
		})
	end)

	verifyHarness:suite("control motion policy and lifetime", function()
		local function motionScene(UI: any, Host: any, state: any): any
			return Host.Frame({
				UI.Sheet({
					detent = state.detent,
					isPresented = state.sheet,
					title = "Sheet",
					content = function(): Instance
						return UI.Button({ Name = "Go", label = "Go", pop = true, onActivate = function() end })
					end,
				}) :: unknown,
				UI.RowActions({
					content = UI.Button "RowBody" { label = "Row" },
					open = state.open,
					trailing = { { id = "Archive", label = "Archive" } :: FixtureCollectionTypes.RowAction },
				}),
				UI.Alert({
					isPresented = state.alert,
					title = "Alert",
					transition = { seconds = 0.2 },
					actions = { { id = "ok", label = "OK" } :: FixtureNavigationTypes.AlertAction<any> },
				}),
				UI.TabView({
					selection = state.tab,
					placement = "topBar" :: "topBar",
					transition = { seconds = 0.2 },
					tabs = {
						{
							id = "a",
							label = "A",
							content = function(): Instance
								return Host.Frame({ Name = "APage" })
							end,
						} :: FixtureNavigationTypes.Tab,
						{
							id = "b",
							label = "B",
							content = function(): Instance
								return Host.Frame({ Name = "BPage" })
							end,
						} :: FixtureNavigationTypes.Tab,
					},
				}),
				UI.Skeleton({ form = "line" }),
				UI.ProgressView({ Name = "Health", value = state.value, trail = { delay = 0.05, duration = 0.3 } }),
				UI.ProgressView({ Name = "Busy", presentation = "spinner" :: "spinner" }),
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

		verifyHarness:case(
			"a live reduced-motion switch lands decorative motion on its terminus while progress keeps stepping",
			{
				id = "native_parity_strength_motion::control motion policy and lifetime::a live reduced-motion switch lands decorative motion on its terminus while progress keeps stepping",
				run = function()
					local reduced = Compose.cell(false)
					local w = world({
						motionLevel = (Compose.formula(function(use: Use): "normal" | "limited" | "none"
							return if use(reduced) then "none" else "normal"
						end) :: unknown) :: MotionLevel,
					})
					local state = newState()
					local stop, screen = w.mount(function(UI: FacetControls, Host: RobloxHost)
						return motionScene(UI, Host, state)
					end)
					local row = find(screen, "RowBody").Parent.Parent
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
					local arriving = fadeKit.layer(find(screen, "BPage"))
					local departing = fadeKit.layer(find(screen, "APage"))
					local shimmer = find(screen, "Shimmer")
					local trail = find(find(screen, "Health"), "Trail")
					Verify.expect(pop.Scale ~= 1):toBe(true)
					Verify.expect(sheetPanel.Size.Y.Offset > medium):toBe(true)
					Verify.expect(content.Position.X.Offset < 0 and content.Position.X.Offset > -88):toBe(true)
					Verify.expect(fadeKit.of(alertPanel) > 0 and fadeKit.of(alertPanel) < 1):toBe(true)
					Verify.expect(fadeKit.of(arriving) > 0 and fadeKit.of(arriving) < 1):toBe(true)
					Verify.expect(trail.Size.X.Scale > 0.3 + 1e-6):toBe(true)
					Verify.expect(shimmer.Enabled):toBe(true)
					local indicator = find(find(screen, "Busy"), "Indicator")
					reduced:set(true)
					local landed = {
						pop = pop.Scale,
						sheet = sheetPanel.Size.Y.Offset,
						row = content.Position.X.Offset,
						alert = fadeKit.of(alertPanel),
						arriving = fadeKit.of(arriving),
						trail = trail.Size.X.Scale,
						shimmer = shimmer.Offset,
					}
					Verify.expect(landed.pop):toBe(1)
					Verify.expect(landed.row):toBe(-88)
					Verify.expect(landed.alert):toBe(0)
					Verify.expect(landed.arriving):toBe(0)
					Verify.expect(departing.Visible):toBe(false)
					Verify.expect(landed.trail):toBeCloseTo(0.3, 1e-6)
					Verify.expect(shimmer.Enabled):toBe(false)
					local start = segmentReading(indicator)
					local stepped = false
					for _ = 1, 30 do
						w.step(1 / 60)
						Verify.expect(pop.Scale):toBe(landed.pop)
						Verify.expect(sheetPanel.Size.Y.Offset):toBe(landed.sheet)
						Verify.expect(content.Position.X.Offset):toBe(landed.row)
						Verify.expect((fadeKit.of(alertPanel))):toBe(landed.alert)
						Verify.expect((fadeKit.of(arriving))):toBe(landed.arriving)
						Verify.expect(trail.Size.X.Scale):toBe(landed.trail)
						Verify.expect(shimmer.Offset):toBe(landed.shimmer)
						stepped = stepped or segmentReading(indicator) ~= start
					end
					Verify.expect(stepped):toBe(true)
					Verify.expect(landed.sheet > medium):toBe(true)
					state.detent:set("medium")
					Verify.expect(math.abs(sheetPanel.Size.Y.Offset - medium) < 0.5):toBe(true)
					state.alert:set(false)
					Verify.expect((find(screen, "AlertPanel"))):toBe(nil)
					stop()
					Verify.expect((w.engine.heartbeat.count())):toBe(0)
					w.close()
				end,
			}
		)

		verifyHarness:case("fifty animated mount, flight and unmount cycles return the census to its baseline", {
			id = "native_parity_strength_motion::control motion policy and lifetime::fifty animated mount, flight and unmount cycles return the census to its baseline",
			run = function()
				local w = world({ motionLevel = "normal" })
				local target = w.engine.new("Folder")
				local function cycle()
					local state = newState()
					local stop = w.runtime.mount(function()
						return ((w.runtime.constructors.ScreenGui :: unknown) :: ScreenGuiConstructor)({
							motionScene(w.UI, w.runtime.constructors, state),
						})
					end, target)
					local row = find(target, "RowBody").Parent.Parent
					row.AbsoluteSize = w.engine.types.Vector2.new(320, 44)
					w.step(0.05)
					find(target, "Go").Activated.fire()
					state.detent:set("large")
					state.open:set("trailing")
					state.alert:set(true)
					state.tab:set("b")
					state.value:set(0.2)
					w.step(0.05)
					Verify.expect(w.engine.heartbeat.count() > 0):toBe(true)
					stop()
					Verify.expect((w.engine.heartbeat.count())):toBe(0)
					Verify.expect(#target:GetChildren()):toBe(0)
				end
				local baseline = w.engine.census()
				cycle()
				local first = w.engine.census()
				Verify.expect(first.live):toBe(baseline.live)
				Verify.expect(first.connections):toBe(baseline.connections)
				for _ = 2, 50 do
					cycle()
				end
				local final = w.engine.census()
				Verify.expect(final.live):toBe(baseline.live)
				Verify.expect(final.connections):toBe(baseline.connections)
				w.close()
			end,
		})

		verifyHarness:case("motion refuses to start outside an owner and a disposed owner cannot restart its clock", {
			id = "native_parity_strength_motion::control motion policy and lifetime::motion refuses to start outside an owner and a disposed owner cannot restart its clock",
			run = function()
				local w = world({ motionLevel = "normal" })
				local okTimeline, timelineError = pcall(function()
					return w.runtime.timeline({ duration = 1 })
				end)
				Verify.expect(okTimeline):toBe(false)
				Verify.expect(string.find(tostring(timelineError), "no-active-owner", 1, true) ~= nil):toBe(true)
				local okTween, tweenError = pcall(function()
					return w.runtime.tween(function()
						return 1
					end, { seconds = 1 })
				end)
				Verify.expect(okTween):toBe(false)
				Verify.expect(string.find(tostring(tweenError), "no-active-owner", 1, true) ~= nil):toBe(true)
				local clock, target = nil, Compose.cell(0)
				local moving
				local root = Compose.createRootOwner(function()
					clock = w.runtime.timeline({ duration = 1, autoplay = false })
					moving = w.runtime.tween(function(use: Use)
						return use(target)
					end, { seconds = 1 })
				end, w.runtime.reactor)
				target:set(10)
				Verify.expect((w.engine.heartbeat.count())):toBe(1)
				w.step(0.1)
				local midway = moving:peek()
				Verify.expect(midway > 0 and midway < 10):toBe(true)
				root.dispose()
				Verify.expect((w.engine.heartbeat.count())):toBe(0)
				clock:play()
				clock:restart()
				target:set(20)
				Verify.expect((w.engine.heartbeat.count())):toBe(0)
				Verify.expect((clock.moving:peek())):toBe(false)
				w.step(0.5)
				Verify.expect((moving:peek())):toBe(midway)
				Verify.expect((clock.progress:peek())):toBe(0)
				w.close()
			end,
		})

		verifyHarness:case("a row reveal reversed mid-flight continues from its painted offset", {
			id = "native_parity_strength_motion::control motion policy and lifetime::a row reveal reversed mid-flight continues from its painted offset",
			run = function()
				local w = world({ motionLevel = "normal" })
				local open: FixtureComposeTypes.Cell<("leading" | "trailing")?> =
					Compose.cell(nil :: ("leading" | "trailing")?)
				local stop, screen = w.mount(function(UI: FacetControls)
					return UI.RowActions({
						content = UI.Button "Body" { label = "Row" } :: GuiObject,
						open = open,
						trailing = { { id = "Archive", label = "Archive" } :: FixtureCollectionTypes.RowAction },
					})
				end)
				local node = find(screen, "Content").Parent
				node.AbsoluteSize = w.engine.types.Vector2.new(320, 44)
				local content = find(node, "Content")
				open:set("trailing")
				w.step(0.05)
				local painted = content.Position.X.Offset
				Verify.expect(painted < 0 and painted > -88):toBe(true)
				open:set(nil)
				Verify.expect(content.Position.X.Offset):toBe(painted)
				w.step(1 / 60)
				local next = content.Position.X.Offset
				Verify.expect(math.abs(next - painted) < 20):toBe(true)
				local farthest = math.min(painted, next)
				for _ = 1, 60 do
					w.step(1 / 60)
					farthest = math.min(farthest, content.Position.X.Offset)
				end
				Verify.expect(farthest > -88):toBe(true)
				Verify.expect(math.abs(content.Position.X.Offset) < 0.01):toBe(true)
				stop()
				w.close()
			end,
		})

		verifyHarness:case("an alert reopened mid-exit continues from its painted opacity", {
			id = "native_parity_strength_motion::control motion policy and lifetime::an alert reopened mid-exit continues from its painted opacity",
			run = function()
				local w = world({ motionLevel = "normal" })
				local shown = Compose.cell(false)
				local stop, screen = w.mount(function(UI: FacetControls)
					return UI.Alert({ isPresented = shown, title = "Again", transition = { seconds = 0.2 } })
				end)
				shown:set(true)
				w.step(0.3)
				local panel = find(screen, "AlertPanel")
				shown:set(false)
				w.step(0.1)
				local fading = fadeKit.of(panel)
				Verify.expect(fading > 0 and fading < 1):toBe(true)
				shown:set(true)
				Verify.expect((find(screen, "AlertPanel"))):toBe(panel)
				Verify.expect((fadeKit.of(panel))):toBe(fading)
				w.step(1 / 60)
				Verify.expect(fadeKit.of(panel) < fading):toBe(true)
				Verify.expect(fading - fadeKit.of(panel) < 0.1):toBe(true)
				w.step(0.3)
				Verify.expect((fadeKit.of(panel))):toBe(0)
				stop()
				w.close()
			end,
		})
	end)

	verifyHarness:suite("theme paint transitions", function()
		local function isPaint(property: string, value: any): boolean
			return typeof(value) == "Color3" or string.find(property, "Transparency$") ~= nil
		end

		verifyHarness:case("the sheet puts back a FacetMotion token that other code clears or overwrites", {
			id = "native_parity_strength_motion::theme paint transitions::the sheet puts back a FacetMotion token that other code clears or overwrites",
			run = function()
				local w = world({})
				local stop, sheet = w.runtime.mount(function()
					return themes.createStyleSheet(w.runtime, themes.neutralPackage(), { types = w.engine.types })
				end, w.engine.new("Folder"))
				local press = sheet:GetAttribute("FacetMotionPress")
				Verify.expect(press.Time):toBe(0.08)
				sheet:SetAttribute("FacetMotionPress", nil)
				Verify.expect((sheet:GetAttribute("FacetMotionPress"))):toBe(press)
				sheet:SetAttribute("FacetMotionNormal", w.engine.types.TweenInfo.new(5))
				Verify.expect(sheet:GetAttribute("FacetMotionNormal").Time):toBe(0.2)
				stop()
				w.close()
			end,
		})

		verifyHarness:case(
			"press rules transition in motion.press, hover rules in motion.hover, other rules in motion.normal",
			{
				id = "native_parity_strength_motion::theme paint transitions::press rules transition in motion.press, hover rules in motion.hover, other rules in motion.normal",
				run = function()
					local themePackages = require("../tools/lune/theme_packages")
					local packages: { any } = { themes.neutralPackage() }
					for _, name in themePackages.shippable() do
						local module: any = (require :: any)("../examples/themes/" .. name)
						local package, report = module.build(themes)
						Verify.expect(report.ok):toBe(true)
						table.insert(packages, package)
					end
					Verify.expect(#packages >= 9):toBe(true)
					for _, package in packages do
						local m = package.metrics.motion
						local normal = m.normal
						local press = math.min(m.press or 0.08, normal)
						local hover = math.min(m.hover or 0.15, normal)
						for _, mode in
							{ "full", "limited", "reduced", "off" } :: { "full" | "limited" | "off" | "reduced" }
						do
							local w = world({})
							local stop, sheet = w.runtime.mount(function()
								return themes.createStyleSheet(w.runtime, package, {
									types = w.engine.types,
									motionLevel = if mode == "reduced"
										then "none"
										elseif mode == "limited" then "limited"
										else "normal",
									transition = if mode == "off" then false else nil,
								})
							end, w.engine.new("Folder"))
							local checked = { press = 0, hover = 0, base = 0 }
							for _, rule in sheet:GetChildren() do
								if rule.ClassName == "StyleRule" then
									local kind = if string.find(rule.Selector, ":Press", 1, true)
										then "press"
										elseif string.find(rule.Selector, ":Hover", 1, true) then "hover"
										else "base"
									local want = if mode == "reduced" or mode == "off"
										then 0
										elseif kind == "press" then press
										elseif kind == "hover" then hover
										else normal
									local properties = rule:GetProperties()
									local transitions = rule:GetPropertyTransitions()
									for property, value in properties do
										if isPaint(property, value) then
											Verify.expect(transitions[property]):toBe(
												if kind == "press"
													then "$FacetMotionPress"
													elseif kind == "hover" then "$FacetMotionHover"
													else "$FacetMotionNormal"
											)
											local timing = transitionOf(rule, property)
											Verify.expect(timing ~= nil):toBe(true)
											Verify.expect(timing.Time):toBe(want)
											Verify.expect(timing.EasingStyle):toBe(w.engine.types.Enum.EasingStyle.Quad)
											Verify.expect(timing.EasingDirection)
												:toBe(w.engine.types.Enum.EasingDirection.Out)
											checked[kind] += 1
										else
											Verify.expect(transitions[property]):toBe(nil)
										end
									end
									for property in transitions do
										Verify.expect(properties[property] ~= nil):toBe(true)
									end
								end
							end
							Verify.expect(checked.press > 5 and checked.hover > 5 and checked.base > 30):toBe(true)
							stop()
							w.close()
						end
					end
				end,
			}
		)
	end)

	verifyHarness:suite("match3 cascade order and input lock", function()
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
			local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
			local target = engine.new("Folder")
			local viewport = Compose.cell({ width = 800, height = 600 })
			local ctx: any = {
				Facet = Facet,
				Compose = Compose,
				runtime = runtime,
				Host = (runtime.constructors :: unknown) :: RobloxHost,
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
			local stop, node: any = runtime.mount(function()
				gallery.configure(ctx)
				ctx.UI = Facet.controls(
					runtime,
					{
						types = engine.types,
						viewport = viewport,
						motionLevel = (Compose.formula(function(use: Use): "normal" | "limited" | "none"
							return if ctx.reducedMotion and use(ctx.reducedMotion) then "none" else "normal"
						end) :: unknown) :: MotionLevel,
					} :: any
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

		verifyHarness:case(
			"removes before gravity before refill, refuses taps while settling and unlocks after the last cascade",
			{
				id = "native_parity_strength_motion::match3 cascade order and input lock::removes before gravity before refill, refuses taps while settling and unlocks after the last cascade",
				run = function()
					local game, ctx = newGame()
					local everSeen: { [number]: boolean } = {}
					for _, id in game.tileIds() do
						Verify.expect(everSeen[id]):toBe(nil)
						everSeen[id] = true
					end
					game.swap(3, 3, 4, 3)
					Verify.expect((game.isResolving())):toBe(true)
					local frames = 0
					local refused = 0
					while game.phase() ~= "idle" and frames < 2400 do
						Verify.expect((game.isResolving())):toBe(true)
						if frames % 20 == 5 then
							local hit = hitAt(game, ctx, 6, 6)
							local movesBefore, phaseBefore = game.moves(), game.phase()
							gamepadTap(ctx, hit)
							Verify.expect((hit:GetAttribute("selected"))):toBe(false)
							Verify.expect(string.find(game.hintText(), "still settling", 1, true) ~= nil):toBe(true)
							Verify.expect((game.moves())):toBe(movesBefore)
							Verify.expect((game.phase())):toBe(phaseBefore)
							refused += 1
						end
						ctx.engine.heartbeat.fire(0.01)
						frames += 1
					end
					Verify.expect(refused > 2):toBe(true)
					Verify.expect((game.phase())):toBe("idle")
					Verify.expect((game.isResolving())):toBe(false)
					Verify.expect((game.tickHookActive())):toBe(false)
					local log = game.phaseLog()
					Verify.expect(log[1]):toBe("swap")
					Verify.expect(log[2]):toBe("mark")
					local cleared = tonumber(string.match(log[3], "^remove:(%d+)$"))
					Verify.expect(cleared ~= nil and (cleared :: number) >= 3):toBe(true)
					Verify.expect(log[4]):toBe("gravity")
					local added = tonumber(string.match(log[5], "^refill:(%d+)$"))
					Verify.expect(added):toBe(cleared)
					Verify.expect(log[6]):toBe("land")
					Verify.expect(log[#log]):toBe("idle")
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
							Verify.expect(previous):toBe("remove")
						elseif current == "refill" then
							Verify.expect(previous):toBe("gravity")
						end
					end
					Verify.expect(#game.tileIds()):toBe(36)
					Verify.expect((game.moves())):toBe(1)
					local hit = hitAt(game, ctx, 6, 6)
					gamepadTap(ctx, hit)
					Verify.expect((hit:GetAttribute("selected"))):toBe(true)
					Verify.expect((string.find(game.hintText(), "still settling", 1, true))):toBe(nil)
					gamepadTap(ctx, hit)
					Verify.expect((hit:GetAttribute("selected"))):toBe(false)
					Verify.expect((game.moves())):toBe(1)
					ctx.stop()
					Verify.expect((ctx.engine.heartbeat.count())):toBe(0)
				end,
			}
		)

		verifyHarness:case("never reuses a tile id across refills", {
			id = "native_parity_strength_motion::match3 cascade order and input lock::never reuses a tile id across refills",
			run = function()
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
					Verify.expect(live[id]):toBe(nil)
					live[id] = true
				end
				Verify.expect(total > 36):toBe(true)
				ctx.stop()
			end,
		})
	end)

	verifyHarness:suite("gallery motion setting", function()
		verifyHarness:case("offers Full and Reduced, never on or off wording, and follows the native preference", {
			id = "native_parity_strength_motion::gallery motion setting::offers Full and Reduced, never on or off wording, and follows the native preference",
			run = function()
				local gallery = require("../examples/gallery/client/screen")
				local engine: any = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
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
					Host = (runtime.constructors :: unknown) :: RobloxHost,
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
				local stop, root: any = runtime.mount(function()
					gallery.configure(ctx)
					ctx.UI = Facet.controls(
						runtime,
						{
							types = engine.types,
							viewport = ctx.viewport,
							inputParent = target,
							services = { GuiService = gui, UserInputService = input },
							theme = ctx.theme,
							motionLevel = (Compose.formula(function(use: Use): "normal" | "limited" | "none"
								return if ctx.reducedMotion and use(ctx.reducedMotion) then "none" else "normal"
							end) :: unknown) :: MotionLevel,
						} :: any
					)
					ctx.demos = { { id = "first", title = "First", kind = "fixture" :: "fixture", module = "first" } }
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
				openSettings(root)
				Verify.expect(find(root, "ShowcasePanel") ~= nil or find(root, "Section") ~= nil):toBe(true)
				local sheet = find(target, "MotionNote")
				while sheet and sheet.Name ~= "Settings" do
					sheet = sheet.Parent
				end
				Verify.expect(sheet ~= nil):toBe(true)
				local picker = find(sheet, "Motion")
				Verify.expect(picker ~= nil):toBe(true)
				local device, full, limited, reduced =
					find(picker, "device"), find(picker, "normal"), find(picker, "limited"), find(picker, "none")
				Verify.expect(device ~= nil and full ~= nil and limited ~= nil and reduced ~= nil):toBe(true)
				local optionCount = 0
				for _, node in picker:GetDescendants() do
					if node:IsA("TextButton") and node:GetAttribute("label") ~= nil then
						optionCount += 1
					end
				end
				Verify.expect(optionCount):toBe(4)
				Verify.expect((device:GetAttribute("label"))):toBe("Device")
				Verify.expect((full:GetAttribute("label"))):toBe("Game: Normal")
				Verify.expect((limited:GetAttribute("label"))):toBe("Game: Limited")
				Verify.expect((reduced:GetAttribute("label"))):toBe("Game: None")
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
				Verify.expect(#wording > 5):toBe(true)
				for _, text in wording do
					local lower = string.lower(text)
					for _, banned in
						{ "^off$", "^on$", "%f[%a]off%f[%A]", "%f[%a]disabled?%f[%A]", "%f[%a]enabled?%f[%A]" }
					do
						Verify.expect(`{text} matches {banned}: {string.find(lower, banned) ~= nil}`)
							:toBe(`{text} matches {banned}: false`)
					end
				end
				Verify.expect((device:GetAttribute("selected"))):toBe(true)
				reduced.Activated.fire()
				Verify.expect((ctx.motionLevel:peek())):toBe("none")
				Verify.expect((ctx.motionMode:peek())):toBe("none")
				Verify.expect((reduced:GetAttribute("selected"))):toBe(true)
				full.Activated.fire()
				Verify.expect((ctx.reducedMotion:peek())):toBe(false)
				Verify.expect((full:GetAttribute("selected"))):toBe(true)
				gui.ReducedMotionEnabled = true
				Verify.expect((ctx.reducedMotion:peek())):toBe(true)
				Verify.expect((ctx.motionLevel:peek())):toBe("limited")
				device.Activated.fire()
				Verify.expect((ctx.motionLevel:peek())):toBe("limited")
				Verify.expect((device:GetAttribute("selected"))):toBe(true)
				limited.Activated.fire()
				Verify.expect((ctx.motionMode:peek())):toBe("limited")
				gui.ReducedMotionEnabled = false
				Verify.expect((ctx.motionLevel:peek())):toBe("limited")
				device.Activated.fire()
				Verify.expect((ctx.reducedMotion:peek())):toBe(false)
				stop()
				runtime:dispose()
			end,
		})
	end)

	verifyHarness:suite("performance lab motion flight", function()
		verifyHarness:case(
			"profiles a live animation flight apart from the idle control and releases it on the next selection",
			{
				id = "native_parity_strength_motion::performance lab motion flight::profiles a live animation flight apart from the idle control and releases it on the next selection",
				run = function()
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
							orientation = "landscape" :: "landscape",
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
					Verify.expect(probe.state().iterations):toBe(0)
					local idleRow = probe.capture()
					Verify.expect(idleRow.captureFrames):toBe(0)
					Verify.expect(#idleRow.scopes.controlStepMs):toBe(0)
					Verify.expect(idleRow.scenario):toBe("idle-baseline")
					local resting = labWorld.engine.heartbeat.count()
					probe.select("motion-flight", 100)
					local active = probe.state().active
					Verify.expect(#active.springs):toBe(24)
					Verify.expect(#active.nodes):toBe(24)
					local chips: { any } = table.clone(active.nodes)
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
					Verify.expect(movedEveryFrame):toBe(true)
					Verify.expect(active.n):toBe(30)
					Verify.expect(active.beats >= 2):toBe(true)
					Verify.expect(labWorld.engine.heartbeat.count() > resting):toBe(true)
					local row = probe.capture()
					Verify.expect(#modules.capture.problems(row)):toBe(0)
					Verify.expect(row.scenario):toBe("motion-flight")
					Verify.expect(row.captureFrames):toBe(30)
					Verify.expect(#row.scopes.controlStepMs):toBe(30)
					Verify.expect(row.frame.measured):toBe(true)
					Verify.expect(row.counters.iterations):toBe(30)
					probe.select("idle-baseline", 100)
					for _, chip in chips do
						Verify.expect((chip:isDestroyed())):toBe(true)
					end
					Verify.expect(probe.state().active ~= active):toBe(true)
					Verify.expect((labWorld.engine.heartbeat.count())):toBe(resting)
					local held = active.springs[1]:peek()
					labWorld.frame(0.5)
					Verify.expect((active.springs[1]:peek())):toBe(held)
					labWorld.dispose()
					Verify.expect((labWorld.engine.heartbeat.count())):toBe(0)
				end,
			}
		)

		verifyHarness:case("the segmented selection fill never reaches past the strip, so it cannot widen it", {
			id = "native_parity_strength_motion::performance lab motion flight::the segmented selection fill never reaches past the strip, so it cannot widen it",
			run = function()
				local w = world({ motionLevel = "none" })
				local _, screen = w.mount(function(UI: FacetControls)
					return UI.Picker "Mode" {
						style = "segmented" :: "segmented",
						selected = Compose.cell("b"),
						options = {
							{ value = "a", label = "A long option" } :: FixtureNavigationTypes.PickerOption<any>,
							{ value = "b", label = "Rally" } :: FixtureNavigationTypes.PickerOption<any>,
						},
					}
				end)
				local V = w.engine.types.Vector2
				find(screen, "Mode").AbsolutePosition, find(screen, "Mode").AbsoluteSize = V.new(0, 0), V.new(300, 60)
				find(screen, "a").AbsolutePosition, find(screen, "a").AbsoluteSize = V.new(0, 0), V.new(294, 54)
				find(screen, "b").AbsolutePosition, find(screen, "b").AbsoluteSize = V.new(298, 0), V.new(294, 54)
				w.step(0.1)
				local fill = find(screen, "SelectionFill")
				Verify.expect(fill.Position.X.Offset + fill.Size.X.Offset <= 300):toBe(true)
				w.close()
			end,
		})

		verifyHarness:case(
			"the segmented selection fill is placed in the strip's padded content box, so it cannot grow the strip",
			{
				id = "native_parity_strength_motion::performance lab motion flight::the segmented selection fill is placed in the strip's padded content box, so it cannot grow the strip",
				run = function()
					local w = world({ motionLevel = "none" })
					local _, screen = w.mount(function(UI: FacetControls)
						return UI.Picker "Mode" {
							style = "segmented" :: "segmented",
							selected = Compose.cell("b"),
							options = {
								{ value = "a", label = "Road" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "Rally" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "c", label = "Drift" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						}
					end)
					local V = w.engine.types.Vector2
					find(screen, "Mode").AbsolutePosition, find(screen, "Mode").AbsoluteSize =
						V.new(0, 0), V.new(218, 50)
					find(screen, "SlideUnit").AbsolutePosition = V.new(3, 3)
					find(screen, "Mode"):FindFirstChildWhichIsA("UIListLayout").AbsoluteContentSize = V.new(212, 44)
					for index, name in { "a", "b", "c" } do
						find(screen, name).AbsolutePosition = V.new(3 + (index - 1) * 72, 3)
						find(screen, name).AbsoluteSize = V.new(68, 44)
					end
					w.step(0.1)
					local fill = find(screen, "SelectionFill")
					Verify.expect(fill.Position):toBe(w.engine.types.UDim2.fromOffset(72, 0))
					Verify.expect(fill.Size):toBe(w.engine.types.UDim2.fromOffset(68, 44))
					w.close()
				end,
			}
		)

		verifyHarness:case("a stale segment position cannot place the selection fill past the laid-out segments", {
			id = "native_parity_strength_motion::performance lab motion flight::a stale segment position cannot place the selection fill past the laid-out segments",
			run = function()
				local w = world({ motionLevel = "none" })
				local _, screen = w.mount(function(UI: FacetControls)
					return UI.Picker "Mode" {
						style = "segmented" :: "segmented",
						axis = "y" :: "y",
						selected = Compose.cell("b"),
						options = {
							{ value = "a", label = "Road" } :: FixtureNavigationTypes.PickerOption<any>,
							{ value = "b", label = "Rally" } :: FixtureNavigationTypes.PickerOption<any>,
							{ value = "c", label = "Drift" } :: FixtureNavigationTypes.PickerOption<any>,
						},
					}
				end)
				local V = w.engine.types.Vector2
				local picker = find(screen, "Mode")
				picker.AbsolutePosition, picker.AbsoluteSize = V.new(0, 0), V.new(300, 308)
				picker:FindFirstChildWhichIsA("UIListLayout").AbsoluteContentSize = V.new(294, 140)
				find(screen, "SlideUnit").AbsolutePosition = V.new(3, 3)
				for index, name in { "a", "b", "c" } do
					find(screen, name).AbsoluteSize = V.new(294, 44)
					find(screen, name).AbsolutePosition = V.new(3, 3 + (index - 1) * 48)
				end
				find(screen, "b").AbsolutePosition = V.new(3, 267)
				w.step(0.1)
				local fill = find(screen, "SelectionFill")
				Verify.expect(fill.Position.Y.Offset + fill.Size.Y.Offset <= 140):toBe(true)
				find(screen, "b").AbsolutePosition = V.new(3, 51)
				w.step(0.1)
				Verify.expect(fill.Position):toBe(w.engine.types.UDim2.fromOffset(0, 48))
				Verify.expect(fill.Size):toBe(w.engine.types.UDim2.fromOffset(294, 44))
				w.close()
			end,
		})

		verifyHarness:case(
			"the segmented selection fill sits on a segment that wrapped to the next line, inside the strip",
			{
				id = "native_parity_strength_motion::performance lab motion flight::the segmented selection fill sits on a segment that wrapped to the next line, inside the strip",
				run = function()
					local w = world({ motionLevel = "none" })
					local selected = Compose.cell("b")
					local _, screen = w.mount(function(UI: FacetControls)
						return UI.Picker "Mode" {
							style = "segmented" :: "segmented",
							selected = selected,
							options = {
								{ value = "a", label = "A deliberately long label that wraps the strip" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "Rally" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						}
					end)
					local V = w.engine.types.Vector2
					find(screen, "Mode").AbsolutePosition, find(screen, "Mode").AbsoluteSize =
						V.new(10, 20), V.new(294, 112)
					find(screen, "SlideUnit").AbsolutePosition = V.new(10, 20)
					find(screen, "Mode"):FindFirstChildWhichIsA("UIListLayout").AbsoluteContentSize = V.new(294, 112)
					find(screen, "a").AbsolutePosition, find(screen, "a").AbsoluteSize = V.new(10, 20), V.new(294, 54)
					find(screen, "b").AbsolutePosition, find(screen, "b").AbsoluteSize = V.new(10, 78), V.new(294, 54)
					w.step(0.1)
					local fill = find(screen, "SelectionFill")
					Verify.expect(fill.Position):toBe(w.engine.types.UDim2.fromOffset(0, 58))
					Verify.expect(fill.Size):toBe(w.engine.types.UDim2.fromOffset(294, 54))
					w.close()
				end,
			}
		)

		verifyHarness:case(
			"the segmented selection fill slides between segments laid out from their sizes and snaps under reduced motion",
			{
				id = "native_parity_strength_motion::performance lab motion flight::the segmented selection fill slides between segments laid out from their sizes and snaps under reduced motion",
				run = function()
					local function run(reduced: boolean): (any, any, any)
						local w = world({ motionLevel = if reduced then "none" else "normal" })
						local selected = Compose.cell("a")
						local _, screen = w.mount(function(UI: FacetControls)
							return UI.Picker "Mode" {
								style = "segmented" :: "segmented",
								selected = selected,
								options = {
									{ value = "a", label = "A" } :: FixtureNavigationTypes.PickerOption<any>,
									{ value = "b", label = "B" } :: FixtureNavigationTypes.PickerOption<any>,
									{ value = "c", label = "C" } :: FixtureNavigationTypes.PickerOption<any>,
								},
							}
						end)
						find(screen, "Mode").AbsoluteSize = w.engine.types.Vector2.new(312, 44)
						find(screen, "Mode"):FindFirstChildWhichIsA("UIListLayout").AbsoluteContentSize =
							w.engine.types.Vector2.new(312, 44)
						for index, name in { "a", "b", "c" } do
							find(screen, name).AbsoluteSize = w.engine.types.Vector2.new(100, 44)
							find(screen, name).AbsolutePosition = w.engine.types.Vector2.new((index - 1) * 104, 0)
						end
						local fill = find(screen, "SelectionFill")
						w.step(0.1)
						Verify.expect(fill.Visible):toBe(true)
						Verify.expect(fill.Position.X.Offset):toBe(0)
						Verify.expect((find(screen, "Mode"):HasTag("facet-segmented-slides"))):toBe(true)
						selected:set("c")
						w.step(0.05)
						return w, fill, fill.Position.X.Offset
					end
					local w, fill, midway = run(false)
					Verify.expect(midway > 0 and midway < 208):toBe(true)
					w.step(1)
					Verify.expect(fill.Position.X.Offset):toBe(208)
					Verify.expect(fill.Size.X.Offset):toBe(100)
					w.close()
					local still, _, snapped = run(true)
					Verify.expect(snapped):toBe(208)
					still.close()
				end,
			}
		)

		verifyHarness:case(
			"the segmented selection fill lands with the strip when the strip reflows during its slide",
			{
				id = "native_parity_strength_motion::performance lab motion flight::the segmented selection fill lands with the strip when the strip reflows during its slide",
				run = function()
					local w = world({ motionLevel = "normal" })
					local selected = Compose.cell("c")
					local _, screen = w.mount(function(UI: FacetControls)
						return UI.Picker "Mode" {
							style = "segmented" :: "segmented",
							selected = selected,
							options = {
								{ value = "a", label = "A" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "B" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "c", label = "C" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						}
					end)
					local V = w.engine.types.Vector2
					local function lay(width: number)
						find(screen, "Mode").AbsoluteSize = V.new(3 * width + 12, 44)
						find(screen, "Mode"):FindFirstChildWhichIsA("UIListLayout").AbsoluteContentSize =
							V.new(3 * width + 12, 44)
						for index, name in { "a", "b", "c" } do
							find(screen, name).AbsoluteSize = V.new(width, 44)
							find(screen, name).AbsolutePosition = V.new((index - 1) * (width + 4), 0)
						end
					end
					lay(100)
					local fill = find(screen, "SelectionFill")
					w.step(0.1)
					Verify.expect(fill.Position.X.Offset):toBe(208)
					selected:set("a")
					w.step(0.02)
					Verify.expect(fill.Position.X.Offset > 0):toBe(true)
					lay(40)
					w.step(0.01)
					Verify.expect(fill.Position.X.Offset):toBe(0)
					Verify.expect(fill.Size.X.Offset):toBe(40)
					selected:set("b")
					w.step(0.02)
					local sliding = fill.Position.X.Offset
					Verify.expect(sliding > 0 and sliding < 44):toBe(true)
					w.step(1)
					Verify.expect(fill.Position.X.Offset):toBe(44)
					w.close()
				end,
			}
		)

		verifyHarness:case(
			"the segmented selection fill keeps sliding through a scale-only change and a reflow that comes with the selection",
			{
				id = "native_parity_strength_motion::performance lab motion flight::the segmented selection fill keeps sliding through a scale-only change and a reflow that comes with the selection",
				run = function()
					local w = world({ motionLevel = "normal" })
					local selected = Compose.cell("c")
					local _, screen = w.mount(function(UI: FacetControls)
						return UI.Picker "Mode" {
							style = "segmented" :: "segmented",
							selected = selected,
							options = {
								{ value = "a", label = "A" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "B" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "c", label = "C" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						}
					end)
					local V = w.engine.types.Vector2
					local function lay(width: number, scale: number)
						find(screen, "SlideUnit").AbsoluteSize = V.new(scale, scale)
						find(screen, "Mode").AbsoluteSize = V.new((3 * width + 12) * scale, 44 * scale)
						find(screen, "Mode"):FindFirstChildWhichIsA("UIListLayout").AbsoluteContentSize =
							V.new((3 * width + 12) * scale, 44 * scale)
						for index, name in { "a", "b", "c" } do
							find(screen, name).AbsoluteSize = V.new(width * scale, 44 * scale)
							find(screen, name).AbsolutePosition = V.new((index - 1) * (width + 4) * scale, 0)
						end
					end
					lay(100, 1)
					local fill = find(screen, "SelectionFill")
					w.step(0.1)
					selected:set("a")
					w.step(0.02)
					lay(100, 0.98)
					w.step(0.01)
					Verify.expect(fill.Position.X.Offset > 100):toBe(true)
					w.step(1)
					Verify.expect(fill.Position.X.Offset):toBe(0)
					w.runtime:batch(function()
						selected:set("c")
						lay(60, 0.98)
					end)
					w.step(0.02)
					local sliding = fill.Position.X.Offset
					Verify.expect(sliding > 0 and sliding < 128):toBe(true)
					w.step(1)
					Verify.expect(fill.Position.X.Offset):toBe(128)
					w.close()
				end,
			}
		)
	end)

	verifyHarness:suite("radial presentation geometry", function()
		local function reach(screen: any, id: string): number
			local center, button = find(screen, "Center"), find(find(screen, "Sector-" .. id), id)
			local dx = button.Position.X.Offset - center.Position.X.Offset
			local dy = button.Position.Y.Offset - center.Position.Y.Offset
			return math.sqrt(dx * dx + dy * dy)
		end

		verifyHarness:case("closing folds the ring back into its centre as it fades", {
			id = "native_parity_strength_motion::radial presentation geometry::closing folds the ring back into its centre as it fades",
			run = function()
				local w = world({ motionLevel = "normal" })
				local opened = Compose.cell(true)
				local stop, screen = w.mount(function(UI: FacetControls)
					return UI.RadialMenu({ isPresented = opened, items = compassItems(function() end) })
				end)
				w.step(0.3)
				local rest = reach(screen, "N")
				opened:set(false)
				w.step(0.06)
				local folding = reach(screen, "N")
				Verify.expect(folding < rest * 0.9):toBe(true)
				Verify.expect(fadeKit.of(find(screen, "Sector-N")) > 0):toBe(true)
				w.step(0.4)
				Verify.expect((find(screen, "RadialPanel"))):toBe(nil)
				stop()
				w.close()
			end,
		})

		verifyHarness:case("a replacing level keeps the ring it replaced", {
			id = "native_parity_strength_motion::radial presentation geometry::a replacing level keeps the ring it replaced",
			run = function()
				local w = world({ motionLevel = "normal" })
				local opened = Compose.cell(true)
				local stop, screen = w.mount(function(UI: FacetControls)
					return UI.RadialMenu({
						isPresented = opened,
						preset = "bottom-left" :: "bottom-left",
						appearance = "buttons" :: "buttons",
						items = {
							{ id = "look", label = "Look", icon = "close", onSelect = function() end } :: FixtureRadialTypes.RadialItem<any>,
							{
								id = "pack",
								label = "Pack",
								icon = "menu",
								navigation = "replace" :: "replace",
								children = {
									{
										id = "map",
										label = "Map",
										compactLabel = { icon = "flag" },
										onSelect = function() end,
									},
									{
										id = "snack",
										label = "Snack",
										compactLabel = { icon = "checkmark" },
										onSelect = function() end,
									},
								},
							} :: FixtureRadialTypes.RadialItem<any>,
							{ id = "wave", label = "Wave", icon = "flag", onSelect = function() end } :: FixtureRadialTypes.RadialItem<any>,
						},
					})
				end)
				w.step(0.5)
				local root = reach(screen, "look")
				find(find(screen, "Sector-pack"), "pack").Activated.fire()
				w.step(0.5)
				Verify.expect(reach(screen, "map") >= root - 1):toBe(true)
				Verify.expect(reach(screen, "snack") >= root - 1):toBe(true)
				stop()
				w.close()
			end,
		})
	end)
end
