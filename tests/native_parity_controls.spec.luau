--!strict
local FixtureComposeTypes = require("../src/vendor/compose/core")
local FixtureCollectionTypes = require("../src/ui/collection_types")
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose: typeof(require("@repo/src/vendor/compose/core")) = Facet.Compose

type World = {
	engine: any,
	runtime: any,
	UI: any,
	Host: any,
	gui: any,
	input: any,
	root: any,
	node: any,
	stop: () -> (),
}

local function setup(build: (any, any, any, any) -> any, options: { [string]: any }?): World
	local engine: any = engineLib.new()
	local runtime: typeof(require("@repo/src/vendor/compose/roblox").createRuntime(nil :: any)) =
		Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	input.IsKeyDown = function()
		return false
	end
	local root = engine.new("ScreenGui")
	local config: { [string]: any } = {
		types = engine.types,
		guiService = gui,
		services = { GuiService = gui, UserInputService = input },
		inputParent = root,
		motionLevel = "none",
	}
	for key, value in (options or {}) :: { [string]: any } do
		config[key] = value
	end
	local UI = Facet.controls(runtime, config :: any)
	local Host = (
		runtime.constructors :: unknown
	) :: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host)
	local stop, node: any = runtime.mount(function()
		return build(UI, Host, engine, runtime)
	end, root)
	return {
		engine = engine,
		runtime = runtime,
		UI = UI,
		Host = Host,
		gui = gui,
		input = input,
		root = root,
		node = node,
		stop = function()
			stop()
			runtime:dispose()
		end,
	}
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

local function action(root: any, name: string): any
	for _, child in root:GetChildren() do
		if child:IsA("InputContext") and child.Name == "Facet" .. name and child.Enabled then
			return child:FindFirstChild(name)
		end
	end
	return nil
end

local function contexts(root: any, name: string): { any }
	local found = {}
	for _, child in root:GetChildren() do
		if child:IsA("InputContext") and child.Name == "Facet" .. name then
			table.insert(found, child)
		end
	end
	return found
end

local function mountError(build: (any, any) -> any): string?
	local engine: any = engineLib.new()
	local runtime: typeof(require("@repo/src/vendor/compose/roblox").createRuntime(nil :: any)) =
		Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local UI =
		Facet.controls(runtime, { types = engine.types, guiService = gui, services = { GuiService = gui } } :: any)
	local Host = (
		runtime.constructors :: unknown
	) :: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host)
	local ok, message = pcall(function()
		local stop = runtime.mount(function()
			return Host.Frame({ build(UI, Host) })
		end, engine.new("ScreenGui"))
		stop()
	end)
	runtime:dispose()
	return if ok then nil else tostring(message)
end

local function refuses(message: string, build: (any, any) -> any): boolean
	local failure = mountError(build)
	return failure ~= nil and string.find(failure, message, 1, true) ~= nil
end

local function records(count: number): { { id: number, label: string } }
	local values = {}
	for index = 1, count do
		values[index] = { id = index, label = tostring(index) }
	end
	return values
end

local function key(item: any): number
	return item.id
end

local function V2(world: World, x: number, y: number): any
	return world.engine.types.Vector2.new(x, y)
end

t.describe("native parity controls", function()
	t.it("aligns icon button content by the declared text alignment and centers it by default", function()
		local alignment = Compose.cell(nil :: any)
		local world = setup(
			function(
				UI: typeof(require("@repo/src").controls(nil :: any)),
				Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host)
			)
				return Host.Frame("Buttons")({
					UI.Button("Plain")({ label = "Plain", icon = "person" }) :: unknown,
					UI.Button("Aligned")({ label = "Aligned", icon = "person", TextXAlignment = alignment }),
				})
			end
		)
		local E = world.engine.types.Enum
		local function layoutOf(name: string): any
			return find(find(world.node, name), "Content"):FindFirstChildWhichIsA("UIListLayout")
		end
		t.expect(layoutOf("Plain").HorizontalAlignment).toBe(E.HorizontalAlignment.Center)
		alignment:set(E.TextXAlignment.Left)
		t.expect(layoutOf("Aligned").HorizontalAlignment).toBe(E.HorizontalAlignment.Left)
		alignment:set(E.TextXAlignment.Right)
		t.expect(layoutOf("Aligned").HorizontalAlignment).toBe(E.HorizontalAlignment.Right)
		world.stop()
	end)

	t.it("repaints a chip in place, refuses incomplete chips and honors live and inherited disabled", function()
		local selected, enabled, removed = Compose.cell(false), Compose.cell(true), 0
		local removable = Compose.cell(false)
		local world = setup(
			function(
				UI: typeof(require("@repo/src").controls(nil :: any)),
				Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host)
			)
				return Host.Frame("Chips")({
					UI.Chip("Filter")({ label = "Filter", selected = selected, enabled = enabled }) :: unknown,
					UI.Chip("Tag")({
						label = "Tag",
						enabled = removable,
						onRemove = function()
							removed += 1
						end,
					}),
				})
			end
		)
		local chip = find(world.node, "Filter")
		t.expect(chip:HasTag("facet-selected")).toBe(false)
		chip.Activated.fire()
		t.expect(selected:peek()).toBe(true)
		t.expect(find(world.node, "Filter")).toBe(chip)
		t.expect(chip:HasTag("facet-selected")).toBe(true)
		selected:set(false)
		t.expect(chip:HasTag("facet-selected")).toBe(false)
		enabled:set(false)
		t.expect(chip.Interactable).toBe(false)
		t.expect(chip.Selectable).toBe(false)
		chip.Activated.fire()
		t.expect(selected:peek()).toBe(false)
		enabled:set(true)
		chip.Activated.fire()
		t.expect(selected:peek()).toBe(true)
		local remove = find(world.node, "Tag")
		t.expect(find(remove, "Remove").Visible).toBe(true)
		t.expect(remove.Interactable).toBe(false)
		remove.Activated.fire()
		t.expect(removed).toBe(0)
		removable:set(true)
		find(world.node, "Chips").Interactable = false
		remove.Activated.fire()
		t.expect(removed).toBe(0)
		find(world.node, "Chips").Interactable = true
		remove.Activated.fire()
		t.expect(removed).toBe(1)
		world.stop()
		t.expect(
			refuses("selected or onRemove is required", function(UI: typeof(require("@repo/src").controls(nil :: any)))
				return UI.Chip({ label = "A" } :: any)
			end)
		)
			.toBe(true)
		t.expect(
			refuses(
				"read-only selected requires onToggle",
				function(UI: typeof(require("@repo/src").controls(nil :: any)))
					return UI.Chip({
						label = "A",
						selected = Compose.formula(function()
							return false
						end),
					} :: any)
				end
			)
		)
			.toBe(true)
		t.expect(mountError(function(UI: typeof(require("@repo/src").controls(nil :: any)))
			return UI.Chip({
				label = "A",
				selected = Compose.formula(function()
					return false
				end),
				onToggle = function() end,
			})
		end)).toBeNil()
	end)

	t.it("stops a held value adjustment when a modal takes input and waits for a fresh press", function()
		for _, name in { "Stepper", "Slider", "Rating" } do
			local value = Compose.cell(if name == "Slider" then 0 else 1)
			local presented = Compose.cell(false)
			local world = setup(
				function(
					UI: typeof(require("@repo/src").controls(nil :: any)),
					Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host)
				)
					local control = if name == "Stepper"
						then UI.Stepper("Control")({ value = value, max = 100 })
						elseif name == "Slider" then UI.Slider("Control")({
							value = value,
							min = 0,
							max = 1,
							step = 0.01,
						})
						else UI.Rating("Control")({ value = value, count = 50 })
					return Host.Frame({
						control :: unknown,
						UI.Alert("Blocker")({ isPresented = presented, title = "Wait" }),
					})
				end
			)
			local control = find(world.node, "Control")
			world.gui.SelectedObject = control
			local increase = action(world.root, "Increase")
			increase.Pressed.fire()
			local held = value:peek()
			world.engine.heartbeat.fire(0.5)
			t.expect(value:peek() > held).toBe(true)
			presented:set(true)
			local stopped = value:peek()
			world.engine.heartbeat.fire(1)
			t.expect(value:peek()).toBe(stopped)
			t.expect(world.engine.heartbeat.count() <= 1).toBe(true)
			presented:set(false)
			world.gui.SelectedObject = control
			world.engine.heartbeat.fire(1)
			t.expect(value:peek()).toBe(stopped)
			world.stop()
		end
	end)

	t.it("refuses malformed level picker and rating declarations with named errors", function()
		local value = Compose.cell(1)
		local invalidCases: { { any } } = {
			{
				"count must be a positive integer",
				function(UI: typeof(require("@repo/src").controls(nil :: any)))
					return UI.LevelPicker({ value = value, count = 0 })
				end,
			},
			{
				"count must be a positive integer",
				function(UI: typeof(require("@repo/src").controls(nil :: any)))
					return UI.LevelPicker({ value = value, count = 2.5 })
				end,
			},
			{
				"unknown option 'typo'",
				function(UI: typeof(require("@repo/src").controls(nil :: any)))
					return UI.LevelPicker({ value = value, typo = 1 })
				end,
			},
			{
				"invalid segment",
				function(UI: typeof(require("@repo/src").controls(nil :: any)))
					return UI.LevelPicker({ value = value, segment = "dots" } :: any)
				end,
			},
			{
				"invalid size",
				function(UI: typeof(require("@repo/src").controls(nil :: any)))
					return UI.LevelPicker({ value = value, segmentSize = "huge" } :: any)
				end,
			},
			{
				"glyphs require glyph segments",
				function(UI: typeof(require("@repo/src").controls(nil :: any)))
					return UI.LevelPicker(
						{ value = value, segment = "bar", glyphs = { filled = "x", empty = "y" } } :: any
					)
				end,
			},
			{
				"count must be a positive integer",
				function(UI: typeof(require("@repo/src").controls(nil :: any)))
					return UI.Rating({ value = value, count = 0 })
				end,
			},
			{
				"invalid size",
				function(UI: typeof(require("@repo/src").controls(nil :: any)))
					return UI.Rating({ value = value, starSize = "huge" } :: any)
				end,
			},
		}
		for _, case in invalidCases do
			t.expect(refuses(case[1], case[2])).toBe(true)
		end
	end)

	t.it("publishes level values inside the declared run and paints glyphs in place", function()
		local level, rating = Compose.cell(0), Compose.cell(7)
		local world = setup(
			function(
				UI: typeof(require("@repo/src").controls(nil :: any)),
				Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host)
			)
				return Host.Frame({
					UI.LevelPicker("Level")({
						value = level,
						allowZero = false,
						segment = "glyph" :: "glyph",
						glyphs = { filled = "#", empty = "." },
						segmentSize = "large" :: "large",
					}) :: unknown,
					UI.Rating("Stars")({ value = rating, starSize = "medium" :: "medium" }),
				})
			end
		)
		local picker, stars = find(world.node, "Level"), find(world.node, "Stars")
		t.expect(picker:GetAttribute("minimum")).toBe(1)
		t.expect(picker:GetAttribute("maximum")).toBe(5)
		t.expect(picker:GetAttribute("value")).toBe(1)
		t.expect(picker:GetAttribute("semanticValue")).toBe("1 of 1 to 5")
		level:set(9)
		t.expect(picker:GetAttribute("value")).toBe(5)
		t.expect(picker:GetAttribute("semanticValue")).toBe("5 of 1 to 5")
		t.expect(stars:GetAttribute("value")).toBe(5)
		t.expect(stars:GetAttribute("semanticValue")).toBe("5 of 0 to 5")
		rating:set(-3)
		t.expect(stars:GetAttribute("semanticValue")).toBe("0 of 0 to 5")
		level:set(2)
		local third = find(picker, "Level3")
		t.expect(find(picker, "Level1").Text).toBe("#")
		t.expect(third.Text).toBe(".")
		t.expect(third.TextSize).toBe(36)
		t.expect(third.Size).toBe(world.engine.types.UDim2.fromOffset(36, 36))
		level:set(3)
		t.expect(find(picker, "Level3")).toBe(third)
		t.expect(third.Text).toBe("#")
		rating:set(2)
		local star = find(stars, "Level3")
		t.expect(find(stars, "Level2").Text).toBe("★")
		t.expect(star.Text).toBe("☆")
		t.expect(star.TextSize).toBe(28)
		rating:set(4)
		t.expect(find(stars, "Level3")).toBe(star)
		t.expect(star.Text).toBe("★")
		world.stop()
	end)

	t.it("refuses pointer, drag and focused adjustment on a disabled level picker, rating and slider", function()
		local level, stars, slide = Compose.cell(2), Compose.cell(2), Compose.cell(0.5)
		local enabled = Compose.cell(false)
		local world = setup(
			function(
				UI: typeof(require("@repo/src").controls(nil :: any)),
				Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host)
			)
				return Host.Frame({
					UI.LevelPicker("Level")({ value = level, enabled = enabled }) :: unknown,
					UI.Rating("Stars")({ value = stars, enabled = enabled }),
					UI.Slider("Slider")({ value = slide, enabled = enabled }),
				})
			end
		)
		for _, name in { "Level", "Stars" } do
			local node = find(world.node, name)
			node.AbsoluteSize = V2(world, 100, 44)
			t.expect(node.Selectable).toBe(false)
			t.expect(node.Interactable).toBe(false)
			t.expect(find(node, "Scrub").Enabled).toBe(false)
			node.Activated.fire({ Position = world.engine.types.Vector3.new(90, 10, 0) }, 1)
			find(node, "Scrub").DragStart.fire(V2(world, 90, 10))
			find(node, "Scrub").DragContinue.fire(V2(world, 10, 10))
			world.gui.SelectedObject = node
			t.expect(#contexts(world.root, "Increase")).toBe(0)
		end
		local track = find(world.node, "Track")
		track.AbsoluteSize = V2(world, 200, 44)
		t.expect(find(world.node, "Slider").Selectable).toBe(false)
		t.expect(find(track, "Drag").Enabled).toBe(false)
		find(track, "Drag").DragStart.fire(V2(world, 180, 10))
		find(track, "Drag").DragContinue.fire(V2(world, 190, 10))
		world.gui.SelectedObject = find(world.node, "Slider")
		t.expect(#contexts(world.root, "Increase")).toBe(0)
		t.expect(level:peek()).toBe(2)
		t.expect(stars:peek()).toBe(2)
		t.expect(slide:peek()).toBe(0.5)
		enabled:set(true)
		t.expect(find(world.node, "Slider").Selectable).toBe(true)
		world.gui.SelectedObject = find(world.node, "Slider")
		action(world.root, "Increase").Pressed.fire()
		t.expect(slide:peek() > 0.5).toBe(true)
		world.stop()
	end)

	t.it("requires a request callback for a read-only toggle value or mixed state", function()
		local readOnly = Compose.formula(function()
			return true
		end)
		t.expect(
			refuses("read-only value requires onChange", function(UI: typeof(require("@repo/src").controls(nil :: any)))
				return UI.Toggle({ value = readOnly } :: any)
			end)
		)
			.toBe(true)
		t.expect(
			refuses("read-only mixed requires onChange", function(UI: typeof(require("@repo/src").controls(nil :: any)))
				return UI.Toggle({
					value = Compose.cell(false),
					mixed = readOnly,
					presentation = "checkbox" :: "checkbox",
				})
			end)
		)
			.toBe(true)
		local requests = {}
		local world = setup(function(UI: typeof(require("@repo/src").controls(nil :: any)))
			return UI.Toggle("Mixed")({
				value = Compose.cell(false),
				mixed = readOnly,
				presentation = "checkbox" :: "checkbox",
				onChange = function(nextValue)
					table.insert(requests, nextValue)
				end,
			})
		end)
		find(world.node, "Mixed").Activated.fire()
		t.expect(requests).toEqual({ true })
		world.stop()
	end)

	t.it("edits the consumer's caller-owned sound value through its toggle", function()
		local world = setup(function(_, _, engine, runtime)
			return require("../examples/consumer/src/screen").build(
				Facet,
				Facet.controls(runtime, { types = engine.types })
			)
		end)
		local sound = find(world.node, "Sound")
		local indicator = find(sound, "Indicator")
		t.expect(indicator:GetAttribute("selected")).toBe(true)
		t.expect(indicator:HasTag("facet-toggle-on")).toBe(true)
		sound.Activated.fire()
		t.expect(find(world.node, "Sound")).toBe(sound)
		t.expect(indicator:GetAttribute("selected")).toBe(false)
		t.expect(indicator:HasTag("facet-toggle-on")).toBe(false)
		sound.Activated.fire()
		t.expect(indicator:GetAttribute("selected")).toBe(true)
		world.stop()
	end)
	t.it("shows a bar value readout beside its label, keeps the end label with it and applies thickness", function()
		local ending, value = Compose.cell("Connecting"), Compose.cell(0.5)
		local world = setup(
			function(
				UI: typeof(require("@repo/src").controls(nil :: any)),
				Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host)
			)
				return Host.Frame({
					UI.ProgressView("Health")({ value = value, showValue = true, label = "HP", thickness = 10 }) :: unknown,
					UI.ProgressView("Themed")({ value = 0.25 }),
					UI.ProgressView("Steps")({ value = 0.4, showValue = true, endLabel = "2 of 5" }),
					UI.ProgressView("Loading")({ endLabel = ending }),
				})
			end
		)
		local health = find(world.node, "Health")
		local header = find(health, "Header")
		local label = header:FindFirstChildWhichIsA("TextLabel")
		t.expect(label.Text).toBe("HP")
		t.expect(label.LayoutOrder).toBe(1)
		t.expect(find(header, "Value").Text).toBe("50%")
		t.expect(find(header, "Value").LayoutOrder).toBe(2)
		t.expect(find(health, "Track").Size.Y.Offset).toBe(10)
		value:set(0.75)
		t.expect(find(header, "Value").Text).toBe("75%")
		t.expect(find(find(world.node, "Themed"), "Track").Size.Y.Offset).toBe(6)
		t.expect(find(find(world.node, "Themed"), "Value")).toBeNil()
		local steps = find(world.node, "Steps")
		t.expect(find(steps, "Value").Text).toBe("40%")
		t.expect(find(steps, "EndLabel").Text).toBe("2 of 5")
		t.expect(find(steps, "EndLabel").LayoutOrder > find(steps, "Value").LayoutOrder).toBe(true)
		local loading = find(world.node, "Loading")
		local frames = world.engine.heartbeat.count()
		t.expect(find(loading, "EndLabel").Text).toBe("Connecting")
		ending:set("Almost there")
		t.expect(find(loading, "EndLabel").Text).toBe("Almost there")
		t.expect(world.engine.heartbeat.count()).toBe(frames)
		world.stop()
	end)

	t.it("mounts and removes a live badge caption while keeping its icon and plate", function()
		local caption = Compose.cell(nil :: string?)
		local world = setup(function(UI: typeof(require("@repo/src").controls(nil :: any)))
			return UI.Badge("Info")({ label = caption, icon = "checkmark", name = "Info" })
		end)
		local pill = world.node
		local icon = pill:FindFirstChildWhichIsA("ImageLabel")
		local label = find(pill, "Label")
		t.expect(label.Text).toBe("")
		caption:set("Ready")
		t.expect(label.Text).toBe("Ready")
		caption:set(nil)
		t.expect(label.Text).toBe("")
		t.expect(find(world.root, "Info")).toBe(pill)
		t.expect(pill:FindFirstChildWhichIsA("ImageLabel")).toBe(icon)
		t.expect(find(pill, "Label")).toBe(label)
		t.expect(pill:HasTag("facet-badge")).toBe(true)
		world.stop()
	end)

	t.it("sizes skeleton and status indicator rungs live and recovers from an illegal rung", function()
		local skeletonRung, statusRung = Compose.cell("compact" :: string?), Compose.cell("compact" :: string?)
		local world = setup(
			function(
				UI: typeof(require("@repo/src").controls(nil :: any)),
				Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host)
			)
				return Host.Frame({
					UI.Skeleton("Avatar")({ form = "circle" :: "circle", controlSize = skeletonRung }) :: unknown,
					UI.StatusIndicator("Dot")({ status = "success" :: "success", controlSize = statusRung }),
				})
			end
		)
		local placeholder = find(find(world.node, "Avatar"), "Placeholder1")
		local dot = find(world.node, "Dot")
		local UDim2 = world.engine.types.UDim2
		t.expect(placeholder.Size).toBe(UDim2.fromOffset(36, 36))
		t.expect(dot.Size).toBe(UDim2.fromOffset(16, 16))
		skeletonRung:set("large")
		statusRung:set("large")
		t.expect(placeholder.Size).toBe(UDim2.fromOffset(56, 56))
		t.expect(dot.Size).toBe(UDim2.fromOffset(24, 24))
		skeletonRung:set(nil)
		statusRung:set(nil)
		t.expect(placeholder.Size).toBe(UDim2.fromOffset(44, 44))
		t.expect(dot.Size).toBe(UDim2.fromOffset(20, 20))
		t.expect(pcall(function()
			skeletonRung:set("wrong" :: any)
		end)).toBe(false)
		skeletonRung:set("large")
		t.expect(placeholder.Size).toBe(UDim2.fromOffset(56, 56))
		world.stop()
		for _, case in
			{
				{ "invalid form", { form = "wrong" } },
				{ "lines require line form", { form = "box", lines = 2 } },
				{ "lines must be positive", { form = "line", lines = 0 } },
				{ "circle owns its corners", { form = "circle", corners = "pill" :: "pill" } },
				{ "unknown option 'surprise'", { form = "box", surprise = true } },
			} :: { { any } }
		do
			t.expect(refuses(case[1], function(UI: typeof(require("@repo/src").controls(nil :: any)))
				return UI.Skeleton(case[2])
			end)).toBe(true)
		end
	end)

	t.it("puts per-view slider artwork ahead of the theme skin and keeps the theme skin without it", function()
		local engine: any = engineLib.new()
		local runtime: typeof(require("@repo/src/vendor/compose/roblox").createRuntime(nil :: any)) =
			Facet.Roblox.createRuntime(engine)
		local package = Facet.themes.neutralPackage()
		package.assets = { art = { content = "rbxassetid://30" } }
		for _, slot in { "sliderThumb", "sliderTrack" } do
			(package.chrome :: any)[slot] = { kind = "nineSlice" :: "nineSlice", asset = "art" }
		end
		local UI = Facet.controls(runtime, { types = engine.types, theme = package } :: any)
		local custom, themed: any
		local stop = runtime.mount(function()
			custom = UI.Slider({
				value = Compose.cell(0.5),
				thumbImage = "rbxassetid://100",
				trackImage = "rbxassetid://101",
			})
			themed = UI.Slider({ value = Compose.cell(0.5) })
			return (
				(
					runtime.constructors.Frame :: unknown
				) :: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host.Frame)
			)({ custom :: unknown, themed })
		end, engine.new("Folder"))
		t.expect(find(find(custom, "Thumb"), "Artwork").Image).toBe("rbxassetid://100")
		t.expect(find(find(custom, "Rail"), "Artwork").Image).toBe("rbxassetid://101")
		t.expect(custom:FindFirstChild("sliderThumb1", true)).toBeNil()
		t.expect(custom:FindFirstChild("sliderTrack1", true)).toBeNil()
		t.expect(find(custom, "Thumb"):HasTag("facet-skinned")).toBe(false)
		t.expect(find(custom, "Thumb"):HasTag("facet-slider-thumb")).toBe(true)
		t.expect(find(themed, "Thumb"):FindFirstChild("Artwork")).toBeNil()
		t.expect((themed:FindFirstChild("sliderThumb1", true) :: any).Image).toBe("rbxassetid://30")
		t.expect((themed:FindFirstChild("sliderTrack1", true) :: any).Image).toBe("rbxassetid://30")
		t.expect(find(themed, "Thumb"):HasTag("facet-skinned")).toBe(true)
		stop()
		runtime:dispose()
	end)

	t.it("drops the toggle pill under skin art, restores it without art and keeps the knob geometry", function()
		local engine: any = engineLib.new()
		local runtime: typeof(require("@repo/src/vendor/compose/roblox").createRuntime(nil :: any)) =
			Facet.Roblox.createRuntime(engine)
		local skinned = Facet.themes.neutralPackage()
		skinned.assets = { art = { content = "rbxassetid://30" } }
		for _, slot in { "toggleTrack", "toggleKnob" } do
			(skinned.chrome :: any)[slot] = { kind = "nineSlice" :: "nineSlice", asset = "art" }
		end
		local theme = Compose.cell(skinned :: any)
		local UI = Facet.controls(runtime, { types = engine.types, theme = theme } :: any)
		local value = Compose.cell(false)
		local toggle
		local stop = runtime.mount(function()
			toggle = UI.Toggle({ value = value, label = "Music" })
			return toggle
		end, engine.new("Folder"))
		local indicator, mark = find(toggle, "Indicator"), find(toggle, "Mark")
		local function geometry()
			return { mark.Position, mark.AnchorPoint, mark.Size, indicator.Position, indicator.Size }
		end
		t.expect(indicator:HasTag("facet-skinned")).toBe(true)
		t.expect(mark:HasTag("facet-skinned")).toBe(true)
		local skinnedOff = geometry()
		value:set(true)
		for _ = 1, 60 do
			engine.heartbeat.fire(1 / 60)
		end
		local skinnedOn = geometry()
		t.expect(skinnedOn[1] ~= skinnedOff[1]).toBe(true)
		theme:set(Facet.themes.neutralPackage())
		t.expect(indicator:HasTag("facet-skinned")).toBe(false)
		t.expect(mark:HasTag("facet-skinned")).toBe(false)
		t.expect(indicator:HasTag("facet-toggle-indicator")).toBe(true)
		t.expect(geometry()).toEqual(skinnedOn)
		value:set(false)
		for _ = 1, 60 do
			engine.heartbeat.fire(1 / 60)
		end
		t.expect(geometry()).toEqual(skinnedOff)
		theme:set(skinned)
		t.expect(indicator:HasTag("facet-skinned")).toBe(true)
		t.expect(geometry()).toEqual(skinnedOff)
		stop()
		runtime:dispose()
	end)
	t.it("recovers a kept row after a destructive commit so a later commit runs again", function()
		for _, reduced in { true, false } do
			local invoked = 0
			local world = setup(function(UI: typeof(require("@repo/src").controls(nil :: any)))
				return UI.RowActions({
					open = Compose.cell("trailing" :: "leading" | "trailing" | nil) :: FixtureComposeTypes.Cell<FixtureCollectionTypes.RowEdge?>,
					reducedMotion = reduced,
					content = UI.Button("Action")({ label = "Row" }) :: GuiObject,
					trailing = {
						{
							id = "Delete",
							label = "Delete",
							role = "destructive" :: "destructive",
							onActivate = function()
								invoked += 1
							end,
						} :: FixtureCollectionTypes.RowAction,
					},
				})
			end)
			local row = world.node
			row.AbsoluteSize = V2(world, 300, 40)
			world.engine.heartbeat.fire(0.3)
			find(row, "Delete").Activated.fire()
			if not reduced then
				world.engine.heartbeat.fire(0.3)
			end
			t.expect(invoked).toBe(1)
			t.expect(row.Size.Y.Offset).toBe(0)
			world.engine.heartbeat.fire(1 / 60)
			t.expect(row.Size.Y.Offset).toBe(44)
			local detector = row:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
			t.expect(detector.Enabled).toBe(true)
			for _ = 1, 120 do
				world.engine.heartbeat.fire(1 / 60)
			end
			t.expect(find(row, "Content").Position.X.Offset).toBe(0)
			detector.DragStart.fire(V2(world, 290, 20))
			detector.DragContinue.fire(V2(world, 10, 20))
			detector.DragEnd.fire()
			world.engine.heartbeat.fire(0.3)
			t.expect(invoked).toBe(2)
			world.stop()
		end
	end)

	t.it("closes an open row on another row's gesture or menu, the Cancel key, and unmount", function()
		local coordinator = Compose.cell(nil :: any)
		local openA, openB, showA = Compose.cell(nil :: string?), Compose.cell(nil :: string?), Compose.cell(true)
		local function row(
			UI: typeof(require("@repo/src").controls(nil :: any)),
			name: string,
			open: FixtureComposeTypes.Cell<FixtureCollectionTypes.RowEdge?>
		)
			return UI.RowActions(name)({
				open = open,
				coordinator = coordinator,
				content = UI.Button("Action")({ label = name }) :: GuiObject,
				trailing = { { id = "Save", label = "Save" } :: FixtureCollectionTypes.RowAction },
				leading = { { id = "Read", label = "Read" } :: FixtureCollectionTypes.RowAction },
			})
		end
		local world = setup(
			function(
				UI: typeof(require("@repo/src").controls(nil :: any)),
				Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host)
			)
				return Host.Frame({
					Compose.show(showA, function()
						return row(UI, "A", openA)
					end) :: unknown,
					row(UI, "B", openB),
				})
			end
		)
		local a, b = find(world.node, "A"), find(world.node, "B")
		for _, node in { a, b } do
			node.AbsoluteSize = V2(world, 300, 40)
		end
		local detectorA = a:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
		local detectorB = b:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
		detectorA.DragStart.fire(V2(world, 200, 20))
		detectorA.DragContinue.fire(V2(world, 100, 20))
		detectorA.DragEnd.fire()
		t.expect(openA:peek()).toBe("trailing")
		detectorB.DragStart.fire(V2(world, 200, 20))
		detectorB.DragContinue.fire(V2(world, 100, 20))
		detectorB.DragEnd.fire()
		t.expect(openA:peek()).toBeNil()
		t.expect(openB:peek()).toBe("trailing")
		a.InputBegan.fire({ UserInputType = world.engine.types.Enum.UserInputType.MouseButton2 })
		t.expect(find(world.root, "MenuPanel") ~= nil).toBe(true)
		t.expect(openB:peek()).toBeNil()
		b.InputBegan.fire({ UserInputType = world.engine.types.Enum.UserInputType.MouseButton2 })
		t.expect(find(find(world.root, "MenuPanel"), "trailing:Save") ~= nil).toBe(true)
		find(world.root, "ModalBack").Pressed.fire()
		t.expect(find(world.root, "MenuPanel")).toBeNil()
		world.gui.SelectedObject = find(a, "Action")
		detectorA.DragStart.fire(V2(world, 100, 20))
		detectorA.DragContinue.fire(V2(world, 200, 20))
		detectorA.DragEnd.fire()
		t.expect(openA:peek()).toBe("leading")
		t.expect(world.gui.SelectedObject.Parent.Name).toBe("leading")
		local close = action(world.root, "RowActionsClose")
		t.expect(close ~= nil).toBe(true)
		local bindings = {}
		for _, binding in close:GetChildren() do
			table.insert(bindings, binding.KeyCode.Name)
		end
		table.sort(bindings)
		t.expect(bindings).toEqual({ "ButtonB", "Escape" })
		close.Pressed.fire()
		t.expect(openA:peek()).toBeNil()
		t.expect(world.gui.SelectedObject).toBe(find(a, "Action"))
		detectorA.DragStart.fire(V2(world, 100, 20))
		detectorA.DragContinue.fire(V2(world, 200, 20))
		detectorA.DragEnd.fire()
		t.expect(openA:peek()).toBe("leading")
		t.expect(coordinator:peek() ~= nil).toBe(true)
		openB:set("trailing")
		t.expect(openA:peek()).toBeNil()
		t.expect(openB:peek()).toBe("trailing")
		openA:set("leading")
		t.expect(openB:peek()).toBeNil()
		t.expect(openA:peek()).toBe("leading")
		showA:set(false)
		t.expect(coordinator:peek()).toBeNil()
		world.stop()
	end)

	t.it("routes a Shift+Return native activation of the row content to the row menu", function()
		local shifted, activated = false, 0
		local world = setup(
			function(
				UI: typeof(require("@repo/src").controls(nil :: any)),
				Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host)
			)
				return Host.Frame({
					UI.RowActions("Row")({
						content = UI.Button("Action")({
							label = "Row",
							onActivate = function()
								activated += 1
							end,
						}) :: GuiObject,
						trailing = {
							{ id = "Delete", label = "Delete", role = "destructive" :: "destructive" } :: FixtureCollectionTypes.RowAction,
						},
					}),
				})
			end
		)
		local Keys = world.engine.types.Enum.KeyCode
		world.input.IsKeyDown = function(_, code)
			return shifted and (code == Keys.LeftShift or code == Keys.RightShift)
		end
		local content = find(world.node, "Action")
		world.gui.SelectedObject = content
		local press = { KeyCode = Keys.Return, UserInputType = world.engine.types.Enum.UserInputType.Keyboard }
		content.Activated.fire(press, 1)
		t.expect(activated).toBe(1)
		t.expect(find(world.root, "MenuPanel")).toBeNil()
		shifted = true
		content.Activated.fire(press, 1)
		t.expect(activated).toBe(1)
		t.expect(find(world.root, "MenuPanel") ~= nil).toBe(true)
		find(world.root, "ModalBack").Pressed.fire()
		t.expect(find(world.root, "MenuPanel")).toBeNil()
		content.Activated.fire(
			{ KeyCode = Keys.Unknown, UserInputType = world.engine.types.Enum.UserInputType.MouseButton1 },
			1
		)
		t.expect(activated).toBe(2)
		world.stop()
	end)

	t.it("toggles the row menu with Shift+Return, reveals it with ButtonX and dismisses it with the row", function()
		local shifted, invoked = false, 0
		local show = Compose.cell(true)
		local world = setup(
			function(
				UI: typeof(require("@repo/src").controls(nil :: any)),
				Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host)
			)
				return Host.Frame({
					Compose.show(show, function()
						return UI.RowActions("Row")({
							content = UI.Button("Action")({ label = "Row" }) :: GuiObject,
							trailing = {
								{
									id = "Delete",
									label = "Delete",
									role = "destructive" :: "destructive",
									onActivate = function()
										invoked += 1
									end,
								} :: FixtureCollectionTypes.RowAction,
							},
						})
					end),
				})
			end
		)
		world.input.IsKeyDown = function(_, code)
			return shifted
				and (
					code == world.engine.types.Enum.KeyCode.LeftShift
					or code == world.engine.types.Enum.KeyCode.RightShift
				)
		end
		local content = find(world.node, "Action")
		t.expect(action(world.root, "RowActionsToggle")).toBeNil()
		world.gui.SelectedObject = content
		t.expect(action(world.root, "Activate") ~= nil).toBe(true)
		local toggle = action(world.root, "RowActionsToggle")
		local Keys = world.engine.types.Enum.KeyCode
		local chords = {}
		for _, binding in toggle:GetChildren() do
			t.expect(binding.KeyCode).toBe(Keys.Return)
			table.insert(chords, binding.PrimaryModifier.Name)
		end
		table.sort(chords)
		t.expect(chords).toEqual({ "LeftShift", "RightShift" })
		shifted = true
		toggle.Pressed.fire()
		t.expect(find(world.root, "MenuPanel") ~= nil).toBe(true)
		t.expect(invoked).toBe(0)
		find(world.root, "ModalBack").Pressed.fire()
		t.expect(find(world.root, "MenuPanel")).toBeNil()
		t.expect(world.gui.SelectedObject).toBe(content)
		shifted = false
		local reveal = action(world.root, "RowActionsReveal")
		local keys = {}
		for _, binding in reveal:GetChildren() do
			table.insert(keys, binding.KeyCode.Name)
		end
		table.sort(keys)
		t.expect(keys).toEqual({ "ButtonX", "Menu" })
		reveal.Pressed.fire()
		t.expect(find(world.root, "MenuPanel") ~= nil).toBe(true)
		show:set(false)
		t.expect(find(world.root, "MenuPanel")).toBeNil()
		t.expect(find(world.root, "DismissOutside")).toBeNil()
		t.expect(invoked).toBe(0)
		world.stop()
	end)

	t.it("moves pad selection into a revealed tray and back, and deletes once from either key", function()
		local invoked, open: FixtureComposeTypes.Cell<("leading" | "trailing")?> =
			0, Compose.cell(nil :: ("leading" | "trailing")?)
		local world = setup(function(UI: typeof(require("@repo/src").controls(nil :: any)))
			return UI.RowActions("Row")({
				open = open,
				content = UI.Button("Action")({ label = "Row" }) :: GuiObject,
				leading = { { id = "Pin", label = "Pin" } :: FixtureCollectionTypes.RowAction },
				trailing = {
					{ id = "Flag", label = "Flag" } :: FixtureCollectionTypes.RowAction,
					{
						id = "Erase",
						label = "Delete",
						role = "destructive" :: "destructive",
						onActivate = function()
							invoked += 1
						end,
					} :: FixtureCollectionTypes.RowAction,
				},
			})
		end)
		world.node.AbsoluteSize = V2(world, 300, 40)
		local content = find(world.node, "Action")
		world.gui.SelectedObject = content
		for _, edge in { "trailing", "leading" } :: { "leading" | "trailing" } do
			open:set(edge :: FixtureCollectionTypes.RowEdge)
			t.expect(world.gui.SelectedObject.Parent.Name).toBe(edge)
			t.expect(world.gui.SelectedObject.Name).toBe(if edge == "trailing" then "Flag" else "Pin")
			open:set(nil)
			t.expect(world.gui.SelectedObject).toBe(content)
		end
		local delete = action(world.root, "RowActionsDelete")
		local keys = {}
		for _, binding in delete:GetChildren() do
			table.insert(keys, binding.KeyCode.Name)
		end
		table.sort(keys)
		t.expect(keys).toEqual({ "Backspace", "Delete" })
		delete.Pressed.fire()
		t.expect(invoked).toBe(1)
		delete.Pressed.fire()
		t.expect(invoked).toBe(1)
		world.stop()
	end)

	t.it("keeps a destructive commit running through a sibling gesture and a table scroll", function()
		local invoked, coordinator = 0, Compose.cell(nil :: any)
		local world = setup(
			function(
				UI: typeof(require("@repo/src").controls(nil :: any)),
				Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host)
			)
				return Host.Frame({
					UI.RowActions("A")({
						open = Compose.cell("trailing" :: "leading" | "trailing" | nil) :: FixtureComposeTypes.Cell<FixtureCollectionTypes.RowEdge?>,
						coordinator = coordinator,
						content = UI.Button({ label = "A" }) :: GuiObject,
						trailing = {
							{
								id = "Delete",
								label = "Delete",
								role = "destructive" :: "destructive",
								onActivate = function()
									invoked += 1
								end,
							} :: FixtureCollectionTypes.RowAction,
						},
					}) :: unknown,
					UI.RowActions("B")({
						coordinator = coordinator,
						content = UI.Button({ label = "B" }) :: GuiObject,
						trailing = { { id = "Save", label = "Save" } :: FixtureCollectionTypes.RowAction },
					}),
				})
			end,
			{ motionLevel = "normal" }
		)
		local a, b = find(world.node, "A"), find(world.node, "B")
		a.AbsoluteSize = V2(world, 300, 40)
		b.AbsoluteSize = V2(world, 300, 40)
		world.engine.heartbeat.fire(0.3)
		find(a, "Delete").Activated.fire()
		t.expect(invoked).toBe(0)
		local detector = b:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
		detector.DragStart.fire(V2(world, 200, 20))
		detector.DragContinue.fire(V2(world, 100, 20))
		detector.DragEnd.fire()
		coordinator:set(nil)
		world.engine.heartbeat.fire(0.3)
		t.expect(invoked).toBe(1)
		world.stop()
	end)

	t.it("declines row gestures until actions exist and keeps the drag detector off without them", function()
		local trailing = Compose.cell({} :: { any })
		local world = setup(function(UI: typeof(require("@repo/src").controls(nil :: any)))
			return UI.RowActions({ content = UI.Button({ label = "Row" }) :: GuiObject, trailing = trailing })
		end)
		local detector = world.node:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
		t.expect(detector.Enabled).toBe(false)
		trailing:set({ { id = "Save", label = "Save" } })
		t.expect(detector.Enabled).toBe(true)
		trailing:set({})
		t.expect(detector.Enabled).toBe(false)
		world.stop()
	end)
	t.it("coordinates table row trays, closes them on body scroll and deletes from a focused row", function()
		local deleted, editing = {}, Compose.cell(false)
		local world = setup(function(UI: typeof(require("@repo/src").controls(nil :: any)))
			return UI.Table({
				from = records(20),
				key = key,
				itemSize = 40,
				editing = editing,
				columns = {
					{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
				},
				rowActions = function(_, rowKey): FixtureCollectionTypes.RowActionsOptions?
					return {
						trailing = {
							{
								id = "Delete",
								label = "Delete",
								role = "destructive" :: "destructive",
								onActivate = function()
									table.insert(deleted, rowKey)
								end,
							} :: FixtureCollectionTypes.RowAction,
						},
					}
				end,
			})
		end)
		local body = find(world.node, "Body")
		body.AbsoluteWindowSize = V2(world, 300, 200)
		local function row(rowKey: number): any
			for _, node in body:FindFirstChild(tostring(rowKey), true):GetDescendants() do
				if node:HasTag("facet-rowactions") then
					return node
				end
			end
			return nil
		end
		local function swipe(rowKey: number)
			local node = row(rowKey)
			node.AbsoluteSize = V2(world, 300, 40)
			local detector = node:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
			detector.DragStart.fire(V2(world, 200, 20))
			detector.DragContinue.fire(V2(world, 130, 20))
			detector.DragEnd.fire()
		end
		local function opened(rowKey: number): boolean
			return find(row(rowKey), "trailing").Visible
		end
		swipe(1)
		t.expect(opened(1)).toBe(true)
		swipe(2)
		t.expect(opened(1)).toBe(false)
		t.expect(opened(2)).toBe(true)
		find(row(2), "Delete").Activated.fire()
		t.expect(deleted).toEqual({ 2 })
		swipe(3)
		t.expect(opened(3)).toBe(true)
		body.CanvasPosition = V2(world, 0, 10)
		t.expect(opened(3)).toBe(false)
		local hit = find(body:FindFirstChild("4", true), "RowHit")
		t.expect(hit.Selectable).toBe(true)
		world.gui.SelectedObject = hit
		local delete = action(world.root, "RowActionsDelete")
		t.expect(delete ~= nil).toBe(true)
		delete.Pressed.fire()
		t.expect(deleted).toEqual({ 2, 4 })
		editing:set(true)
		t.expect(row(5):FindFirstChild("Delete")).toBeNil()
		world.stop()
	end)
	t.it("refuses a reorder that would displace a pinned row and accepts one that keeps it in place", function()
		local requests = {}
		local world = setup(function(UI: typeof(require("@repo/src").controls(nil :: any)))
			return UI.Table({
				from = records(5),
				key = key,
				itemSize = 20,
				reorderable = true,
				movable = function(item)
					return item.id ~= 3
				end,
				onReorder = function(keys, slot)
					table.insert(requests, { keys = keys, slot = slot })
				end,
				columns = {
					{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
				},
			})
		end)
		local body = find(world.node, "Body")
		body.AbsoluteWindowSize = V2(world, 200, 100)
		local function drag(rowKey: number, y: number)
			local handle = body:FindFirstChild(tostring(rowKey), true):FindFirstChild("Move", true)
			local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
			detector.DragStart.fire(V2(world, 10, (rowKey - 1) * 20 + 10))
			detector.DragContinue.fire(V2(world, 10, y))
			detector.DragEnd.fire()
		end
		drag(1, 95)
		drag(2, 95)
		t.expect(#requests).toBe(0)
		drag(4, 95)
		t.expect(requests).toEqual({ { keys = { 4 }, slot = 4 } })
		t.expect(body:FindFirstChild("3", true):FindFirstChild("Move", true).Interactable).toBe(false)
		world.stop()
	end)

	t.it(
		"cancels an armed keyboard move when keyboard and gamepad both leave and keeps it when a pointer arrives",
		function()
			local requests = 0
			local world = setup(function(UI: typeof(require("@repo/src").controls(nil :: any)))
				return UI.Table({
					from = records(5),
					key = key,
					itemSize = 20,
					reorderable = true,
					onReorder = function()
						requests += 1
					end,
					columns = {
						{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
					},
				})
			end)
			world.input.KeyboardEnabled = true
			world.input.GamepadEnabled = true
			world.input.MouseEnabled = false
			local body = find(world.node, "Body")
			body.AbsoluteWindowSize = V2(world, 200, 100)
			body:FindFirstChild("1", true):FindFirstChild("Move", true).Activated.fire()
			local line = find(world.node, "DropLine")
			world.input.MouseEnabled = true
			local start = line.Position.Y.Offset
			action(world.root, "ReorderDown").Pressed.fire()
			t.expect(find(world.node, "DropLine")).toBe(line)
			t.expect(line.Position.Y.Offset).toBe(start + 20)
			world.input.KeyboardEnabled = false
			t.expect(find(world.node, "DropLine")).toBe(line)
			world.input.GamepadEnabled = false
			t.expect(find(world.node, "DropLine")).toBeNil()
			t.expect(action(world.root, "ReorderDrop")).toBeNil()
			t.expect(requests).toBe(0)
			world.stop()
		end
	)

	t.it("reorders a horizontal list along X by pointer, autoscroll and Left and Right stepping", function()
		local requests = {}
		local world = setup(
			function(
				UI: typeof(require("@repo/src").controls(nil :: any)),
				Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host)
			)
				return UI.VirtualList({
					from = records(10),
					key = key,
					direction = "horizontal" :: "horizontal",
					itemSize = 40,
					reorderable = true,
					onReorder = function(keys, slot)
						table.insert(requests, { keys = keys, slot = slot })
					end,
					render = function(): GuiObject
						return Host.Frame({})
					end,
				})
			end
		)
		local list = world.node
		list.AbsoluteWindowSize = V2(world, 200, 60)
		local handle = list:FindFirstChild("1", true):FindFirstChild("Move", true)
		local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
		t.expect(detector.DragAxis).toBe(V2(world, 1, 0))
		detector.DragStart.fire(V2(world, 10, 10))
		detector.DragContinue.fire(V2(world, 130, 10))
		t.expect(find(list, "DropLine").Position.X.Offset).toBe(120)
		detector.DragEnd.fire()
		t.expect(requests).toEqual({ { keys = { 1 }, slot = 2 } })
		local Enum = world.engine.types.Enum
		handle.InputBegan.fire({ UserInputType = Enum.UserInputType.MouseButton1 })
		detector.DragStart.fire(V2(world, 10, 10))
		detector.DragContinue.fire(V2(world, 190, 10))
		world.engine.heartbeat.fire(0.1)
		t.expect(list.CanvasPosition.X).toBeCloseTo(45, 0.01)
		t.expect(list.CanvasPosition.Y).toBe(0)
		action(world.root, "ReorderCancel").Pressed.fire()
		t.expect(find(list, "DropLine")).toBeNil()
		list.CanvasPosition = V2(world, 0, 0)
		handle.Activated.fire()
		local later = action(world.root, "ReorderDown")
		local earlier = action(world.root, "ReorderUp")
		local keys = {}
		for _, binding in later:GetChildren() do
			table.insert(keys, binding.KeyCode.Name)
		end
		for _, binding in earlier:GetChildren() do
			table.insert(keys, binding.KeyCode.Name)
		end
		table.sort(keys)
		t.expect(keys).toEqual({ "DPadLeft", "DPadRight", "Left", "Right" })
		later.Pressed.fire()
		later.Pressed.fire()
		earlier.Pressed.fire()
		action(world.root, "ReorderDrop").Pressed.fire()
		t.expect(requests[2]).toEqual({ keys = { 1 }, slot = 1 })
		world.stop()
	end)

	t.it("finds the insertion slot from measured midpoints on ragged rows", function()
		local requests = {}
		local world = setup(
			function(
				UI: typeof(require("@repo/src").controls(nil :: any)),
				Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host)
			)
				return UI.VirtualList({
					from = records(5),
					key = key,
					itemSize = 20,
					measured = { [1] = 80 },
					reorderable = true,
					onReorder = function(keys, slot)
						table.insert(requests, { keys = keys, slot = slot })
					end,
					render = function(): GuiObject
						return Host.Frame({})
					end,
				})
			end
		)
		world.node.AbsoluteWindowSize = V2(world, 200, 300)
		local detector =
			world.node:FindFirstChild("3", true):FindFirstChild("Move", true):FindFirstChildWhichIsA("UIDragDetector")
		for _, y in { 30, 50 } do
			detector.DragStart.fire(V2(world, 10, 110))
			detector.DragContinue.fire(V2(world, 10, y))
			detector.DragEnd.fire()
		end
		t.expect(requests).toEqual({ { keys = { 3 }, slot = 0 }, { keys = { 3 }, slot = 1 } })
		world.stop()
	end)
	t.it("binds modifier shortcuts only with their modifier and adds the unmodified dialog key", function()
		local saves, confirms = 0, 0
		local world = setup(
			function(
				UI: typeof(require("@repo/src").controls(nil :: any)),
				Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host)
			)
				return Host.Frame({
					UI.Button("Save")({
						label = "Save",
						shortcut = { keyCode = "S", modifiers = { shift = true } },
						onActivate = function()
							saves += 1
						end,
					}) :: unknown,
					UI.Button("Confirm")({
						label = "Confirm",
						shortcut = { keyCode = "Y", modifiers = { shift = true } },
						dialogAction = "default" :: "default",
						onActivate = function()
							confirms += 1
						end,
					}),
				})
			end
		)
		local Enum = world.engine.types.Enum
		local found: { [string]: { string } } = {}
		for _, context in contexts(world.root, "Shortcut") do
			local shortcut = context:FindFirstChild("Shortcut")
			local rows = {}
			for _, binding in shortcut:GetChildren() do
				local modifier = binding.PrimaryModifier
				local unmodified = modifier == nil or modifier == Enum.KeyCode:FromValue(0)
				table.insert(rows, binding.KeyCode.Name .. (if unmodified then "" else "+" .. modifier.Name))
			end
			table.sort(rows)
			found[if string.find(table.concat(rows), "S+", 1, true) then "Save" else "Confirm"] = rows
			shortcut.Pressed.fire()
		end
		t.expect(found.Save).toEqual({ "S+LeftShift", "S+RightShift" })
		t.expect(found.Confirm).toEqual({ "Return", "Y+LeftShift", "Y+RightShift" })
		t.expect(saves).toBe(1)
		t.expect(confirms).toBe(1)
		world.stop()
	end)

	t.it("activates a selected button once per Activate action press and once per native activation", function()
		local count = 0
		local world = setup(function(UI: typeof(require("@repo/src").controls(nil :: any)))
			return UI.Button("Go")({
				label = "Go",
				onActivate = function()
					count += 1
				end,
			})
		end)
		local button = world.node
		t.expect(action(world.root, "Activate")).toBeNil()
		world.gui.SelectedObject = button
		local activate = action(world.root, "Activate")
		local context = activate.Parent
		t.expect(context.Sink).toBe(true)
		t.expect(context.Priority).toBe(5000)
		local keys = {}
		for _, binding in activate:GetChildren() do
			table.insert(keys, binding.KeyCode.Name)
		end
		table.sort(keys)
		t.expect(keys).toEqual({ "Return", "Space" })
		activate.Pressed.fire()
		t.expect(count).toBe(1)
		button.Activated.fire()
		t.expect(count).toBe(2)
		world.gui.SelectedObject = nil
		t.expect(context.Enabled).toBe(false)
		world.stop()
	end)

	t.it(
		"moves radial selection and the commit candidate together on the D-pad and returns to it after the stick",
		function()
			local picked = {}
			local world = setup(function(UI: typeof(require("@repo/src").controls(nil :: any)))
				local items = {}
				for _, id in { "N", "E", "S", "W" } do
					table.insert(items, {
						id = id,
						slot = id :: "N" | "E" | "S" | "W",
						label = id,
						completion = "stay" :: "stay",
						onSelect = function()
							table.insert(picked, id)
						end,
					})
				end
				return UI.RadialMenu({
					isPresented = Compose.cell(true),
					distribution = "compass" :: "compass",
					items = items,
				})
			end)
			world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Gamepad
			local function contextsIn(root: any, name: string): { any }
				local found = {}
				for _, node in root:GetDescendants() do
					if node:IsA("InputContext") and node:FindFirstChild(name) then
						table.insert(found, node)
					end
				end
				return found
			end
			local function fire(name: string)
				for _, context in contextsIn(world.root, name) do
					local inner = context:FindFirstChild(name)
					if context.Enabled and inner.Enabled ~= false then
						inner.Pressed.fire()
						return
					end
				end
				error("no enabled " .. name)
			end
			fire("Radial-right")
			t.expect(world.gui.SelectedObject.Name).toBe("E")
			fire("Radial-down")
			t.expect(world.gui.SelectedObject.Name).toBe("S")
			fire("RadialCommit")
			t.expect(picked).toEqual({ "S" })
			local aim = world.root:FindFirstChild("RadialAim", true)
			aim.StateChanged.fire(V2(world, 1, 0))
			t.expect(world.gui.SelectedObject.Name).toBe("E")
			aim.StateChanged.fire(V2(world, 0, 0))
			fire("Radial-up")
			t.expect(world.gui.SelectedObject.Name).toBe("N")
			fire("RadialCommit")
			t.expect(picked).toEqual({ "S", "N" })
			world.stop()
		end
	)
	t.it("the radial D-pad crosses through the centre and reaches every item of a corner arc", function()
		local function radial(spec: { [any]: any }): (any, (string) -> ())
			local world = setup(function(UI: typeof(require("@repo/src").controls(nil :: any)))
				return UI.RadialMenu(spec)
			end)
			world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Gamepad
			return world,
				function(name: string)
					for _, node in world.root:GetDescendants() do
						if node:IsA("InputContext") and node.Enabled and node:FindFirstChild(name) then
							node:FindFirstChild(name).Pressed.fire()
							return
						end
					end
					error("no enabled " .. name)
				end
		end
		local function items(ids: { string }, slots: boolean): { any }
			local out = {}
			for _, id in ids do
				table.insert(out, {
					id = id,
					slot = if slots then id else nil,
					label = id,
					completion = "stay" :: "stay",
					onSelect = function() end,
				})
			end
			return out
		end
		local world, fire = radial({
			isPresented = Compose.cell(true),
			distribution = "compass" :: "compass",
			center = "close" :: "close",
			items = items({ "N", "E", "S", "W" }, true),
		})
		fire("Radial-right")
		t.expect(world.gui.SelectedObject.Name).toBe("E")
		fire("Radial-left")
		t.expect(world.gui.SelectedObject.Name).toBe("Center")
		fire("Radial-left")
		t.expect(world.gui.SelectedObject.Name).toBe("W")
		fire("Radial-right")
		fire("Radial-up")
		t.expect(world.gui.SelectedObject.Name).toBe("N")
		fire("Radial-right")
		t.expect(world.gui.SelectedObject.Name).toBe("E")
		local E = world.engine.types.Enum
		local down: { [string]: boolean? } = {}
		world.input.IsKeyDown = function(_, key)
			return down[key.Name] == true == true
		end
		local function action(name: string): any
			for _, node in world.root:GetDescendants() do
				if node:IsA("InputContext") and node.Enabled and node:FindFirstChild(name) then
					return node:FindFirstChild(name)
				end
			end
			error("no enabled " .. name)
		end
		local function key(began: boolean)
			down.DPadLeft = began or nil
			local event = { KeyCode = E.KeyCode.DPadLeft, UserInputType = E.UserInputType.Gamepad1 }
			if began then
				world.input.InputBegan.fire(event, true)
			else
				world.input.InputEnded.fire(event, true)
			end
		end
		local left = action("Radial-left")
		key(true)
		left.Pressed.fire()
		t.expect(world.gui.SelectedObject.Name).toBe("Center")
		key(false)
		left.Released.fire()
		fire("Radial-right")
		action("Radial-right").Released.fire()
		t.expect(world.gui.SelectedObject.Name).toBe("E")
		down.DPadLeft = true
		left.Pressed.fire()
		key(true)
		t.expect(world.gui.SelectedObject.Name).toBe("Center")
		left.Released.fire()
		key(false)
		fire("Radial-right")
		t.expect(world.gui.SelectedObject.Name).toBe("E")
		left.Pressed.fire()
		t.expect(world.gui.SelectedObject.Name).toBe("Center")
		fire("Radial-right")
		t.expect(world.gui.SelectedObject.Name).toBe("E")
		key(true)
		t.expect(world.gui.SelectedObject.Name).toBe("Center")
		key(false)
		world.stop()
		local arc, press = radial({
			isPresented = Compose.cell(true),
			preset = "bottom-left" :: "bottom-left",
			items = items({ "look", "pack", "wave" }, false),
		})
		local reached = {}
		for _ = 1, 3 do
			for _, direction in
				{ "Radial-right", "Radial-up", "Radial-up", "Radial-down", "Radial-left" } :: { "Radial-down" | "Radial-left" | "Radial-right" | "Radial-up" }
			do
				press(direction)
				local now = arc.gui.SelectedObject
				if now then
					reached[now.Name] = true
				end
			end
		end
		t.expect(reached.look and reached.pack and reached.wave).toBe(true)
		arc.stop()
	end)

	t.it("combines table row actions with reorder handles, editing, refresh and disposal", function()
		local source, editing = Compose.cell(records(4)), Compose.cell(false)
		local deleted, reorders = {}, {}
		local world = setup(function(UI: typeof(require("@repo/src").controls(nil :: any)))
			return UI.Table({
				from = source,
				key = key,
				itemSize = 40,
				editing = editing,
				reorderable = true,
				onReorder = function(keys, slot)
					table.insert(reorders, { keys = keys, slot = slot })
				end,
				columns = {
					{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
				},
				rowActions = function(_, rowKey): FixtureCollectionTypes.RowActionsOptions?
					return {
						trailing = {
							{
								id = "Delete",
								label = "Delete",
								role = "destructive" :: "destructive",
								onActivate = function()
									table.insert(deleted, rowKey)
								end,
							} :: FixtureCollectionTypes.RowAction,
						},
					}
				end,
			})
		end)
		local body = find(world.node, "Body")
		body.AbsoluteWindowSize = V2(world, 300, 200)
		local function row(rowKey: number): any
			for _, node in body:FindFirstChild(tostring(rowKey), true):GetDescendants() do
				if node:HasTag("facet-rowactions") then
					return node
				end
			end
			return nil
		end
		local function handleOf(rowKey: number): any
			return body:FindFirstChild(tostring(rowKey), true):FindFirstChild("Move", true)
		end
		for rowKey = 1, 4 do
			t.expect(handleOf(rowKey) ~= nil).toBe(true)
		end
		editing:set(true)
		for rowKey = 1, 4 do
			t.expect(row(rowKey):FindFirstChild("Delete")).toBeNil()
			t.expect(handleOf(rowKey) ~= nil).toBe(true)
		end
		editing:set(false)
		local handle = handleOf(2)
		local reorder = handle:FindFirstChildWhichIsA("UIDragDetector")
		reorder.DragStart.fire(V2(world, 10, 50))
		reorder.DragContinue.fire(V2(world, 10, 150))
		t.expect(find(world.node, "DropLine") ~= nil).toBe(true)
		source:set(records(4))
		t.expect(find(world.node, "DropLine")).toBeNil()
		reorder.DragEnd.fire()
		t.expect(#reorders).toBe(0)
		reorder.DragStart.fire(V2(world, 10, 50))
		reorder.DragContinue.fire(V2(world, 10, 150))
		reorder.DragEnd.fire()
		t.expect(reorders).toEqual({ { keys = { 2 }, slot = 3 } })
		local target = row(3)
		target.AbsoluteSize = V2(world, 300, 40)
		local detector = target:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
		detector.DragStart.fire(V2(world, 290, 20))
		detector.DragContinue.fire(V2(world, 10, 20))
		detector.DragEnd.fire()
		t.expect(deleted).toEqual({ 3 })
		t.expect(target.Size.Y.Scale).toBe(0)
		world.engine.heartbeat.fire(1 / 60)
		t.expect(target.Size.Y.Scale).toBe(1)
		t.expect(detector.Enabled).toBe(true)
		local open = row(4)
		open.AbsoluteSize = V2(world, 300, 40)
		open:FindFirstChild("SwipeGrip", true)
			:FindFirstChildWhichIsA("UIDragDetector").DragStart
			.fire(V2(world, 200, 20))
		open:FindFirstChild("SwipeGrip", true)
			:FindFirstChildWhichIsA("UIDragDetector").DragContinue
			.fire(V2(world, 130, 20))
		open:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector").DragEnd.fire()
		t.expect(find(open, "trailing").Visible).toBe(true)
		world.stop()
		t.expect(open:isDestroyed()).toBe(true)
		t.expect(deleted).toEqual({ 3 })
	end)

	t.it("closes a swiped playlist tray when the table scrolls", function()
		local engine: any = engineLib.new()
		local runtime: typeof(require("@repo/src/vendor/compose/roblox").createRuntime(nil :: any)) =
			Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local target = engine.new("Folder")
		local ctx = {
			Facet = Facet,
			Compose = Compose,
			runtime = runtime,
			Host = (
					runtime.constructors :: unknown
				) :: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host),
			types = engine.types,
			viewport = Compose.cell({ width = 1280, height = 720 }),
			inputTarget = target,
			worldTarget = engine.new("Folder"),
			guiService = gui,
			runService = { Heartbeat = engine.heartbeat },
			UI = Facet.controls(runtime, { types = engine.types, guiService = gui, motionLevel = "none" } :: any),
		}
		local built
		local stop, screen: any = runtime.mount(function()
			built = require("../examples/gallery/examples/02_playlist_table").build(ctx)
			return built.screen()
		end, target)
		local body = find(find(screen, "Tracks"), "Body")
		body.AbsoluteWindowSize = engine.types.Vector2.new(600, 100)
		local row
		for _, node in body:GetDescendants() do
			if node:HasTag("facet-rowactions") then
				row = node
				break
			end
		end
		row.AbsoluteSize = engine.types.Vector2.new(600, 44)
		local detector = row:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
		detector.DragStart.fire(engine.types.Vector2.new(400, 20))
		detector.DragContinue.fire(engine.types.Vector2.new(320, 20))
		detector.DragEnd.fire()
		local playing = built.nowPlaying:peek()
		t.expect(find(row, "trailing").Visible).toBe(true)
		body.CanvasPosition = engine.types.Vector2.new(0, 12)
		t.expect(find(row, "trailing").Visible).toBe(false)
		t.expect(built.nowPlaying:peek()).toBe(playing)
		stop()
		runtime:dispose()
	end)
	t.it("never commits or opens a row that has no measured width", function()
		local invoked, open: FixtureComposeTypes.Cell<("leading" | "trailing")?> =
			0, Compose.cell(nil :: ("leading" | "trailing")?)
		local world = setup(function(UI: typeof(require("@repo/src").controls(nil :: any)))
			return UI.RowActions({
				open = open,
				content = UI.Button({ label = "Row" }) :: GuiObject,
				trailing = {
					{
						id = "Delete",
						label = "Delete",
						onActivate = function()
							invoked += 1
						end,
					} :: FixtureCollectionTypes.RowAction,
				},
			})
		end)
		local detector = world.node:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
		detector.DragStart.fire(V2(world, 100, 0))
		detector.DragContinue.fire(V2(world, 85, 0))
		detector.DragEnd.fire()
		t.expect(invoked).toBe(0)
		t.expect(open:peek()).toBeNil()
		world.node.AbsoluteSize = V2(world, 300, 40)
		detector.DragStart.fire(V2(world, 290, 0))
		detector.DragContinue.fire(V2(world, 10, 0))
		detector.DragEnd.fire()
		t.expect(invoked).toBe(1)
		world.stop()
	end)

	t.it("keeps Delete and swipes inert while the row menu is open and leaks nothing across menu toggles", function()
		local invoked = 0
		local world = setup(function(UI: typeof(require("@repo/src").controls(nil :: any)))
			return UI.RowActions({
				content = UI.Button("Action")({ label = "Row" }) :: GuiObject,
				trailing = {
					{
						id = "Erase",
						label = "Erase",
						role = "destructive" :: "destructive",
						onActivate = function()
							invoked += 1
						end,
					} :: FixtureCollectionTypes.RowAction,
				},
			})
		end)
		local Enum = world.engine.types.Enum
		local row = world.node
		row.AbsoluteSize = V2(world, 300, 40)
		local content = find(row, "Action")
		world.gui.SelectedObject = content
		t.expect(action(world.root, "RowActionsDelete") ~= nil).toBe(true)
		row.InputBegan.fire({ UserInputType = Enum.UserInputType.MouseButton2 })
		t.expect(find(world.root, "MenuPanel") ~= nil).toBe(true)
		world.gui.SelectedObject = content
		t.expect(action(world.root, "RowActionsDelete")).toBeNil()
		t.expect(invoked).toBe(0)
		local detector = row:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
		detector.DragStart.fire(V2(world, 290, 20))
		detector.DragContinue.fire(V2(world, 10, 20))
		detector.DragEnd.fire()
		t.expect(invoked).toBe(0)
		t.expect(find(world.root, "MenuPanel") ~= nil).toBe(true)
		action(world.root, "ModalBack").Pressed.fire()
		t.expect(find(world.root, "MenuPanel")).toBeNil()
		local baseline = world.engine.census()
		for _ = 1, 10 do
			row.InputBegan.fire({ UserInputType = Enum.UserInputType.MouseButton2 })
			action(world.root, "ModalBack").Pressed.fire()
		end
		t.expect(find(world.root, "MenuPanel")).toBeNil()
		local after = world.engine.census()
		t.expect(after.live).toBe(baseline.live)
		t.expect(after.connections).toBe(baseline.connections)
		world.stop()
		t.expect(refuses("unknown option 'bogus'", function(UI: typeof(require("@repo/src").controls(nil :: any)))
			return UI.RowActions({ content = UI.Button({ label = "Row" }) :: GuiObject, bogus = 1 })
		end)).toBe(true)
		t.expect(mountError(function(UI: typeof(require("@repo/src").controls(nil :: any)))
			return UI.RowActions({
				open = Compose.cell("trailing"),
				content = UI.Button({ label = "Row" }),
				trailing = { { id = "a", label = "A", role = "weird" } },
			} :: any)
		end) ~= nil).toBe(true)
	end)
end)
