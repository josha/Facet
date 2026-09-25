--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local hud = require("../examples/gallery/scenarios/hud")
local terminal = require("../examples/gallery/examples/outpost_terminal")
local outpost = require("../examples/gallery/scenarios/outpost_terminal")
local settingsSync = require("../examples/gallery/examples/03_settings_sync")

local rules = terminal.rules
local Compose = Facet.Compose

local SKIPPED = {
	Parent = true,
	AbsoluteSize = true,
	AbsolutePosition = true,
	AbsoluteWindowSize = true,
	AbsoluteContentSize = true,
	TextBounds = true,
}

local written: { [string]: { [string]: boolean } } = {}

local function recordingEngine()
	local engine = engineLib.new()
	local create = engine.new
	engine.new = function(className)
		local node = create(className)
		local metatable = getmetatable(node)
		local assign = metatable.__newindex
		metatable.__newindex = function(instance, property, value)
			if property == "Text" then
				assert(type(value) == "string", className .. ".Text requires a string")
			end
			if type(property) == "string" and not SKIPPED[property] then
				local keys = written[className]
				if keys == nil then
					keys = {}
					written[className] = keys
				end
				keys[property] = true
			end
			assign(instance, property, value)
		end
		return node
	end
	return engine
end

local function encode(value: any): string
	if type(value) == "table" then
		if getmetatable(value) ~= nil and value.ClassName ~= nil then
			return "<" .. tostring(value.ClassName) .. ":" .. tostring(value.Name) .. ">"
		end
		local keys = {}
		for key in value do
			table.insert(keys, tostring(key))
		end
		table.sort(keys)
		local parts = {}
		for _, key in keys do
			local item = value[key]
			if item == nil then
				item = value[tonumber(key)]
			end
			table.insert(parts, key .. "=" .. encode(item))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return tostring(value)
end

local function painted(node: any): string
	local className = node.ClassName
	local lines = { className .. " " .. tostring(node.Name) }
	local keys = {}
	for key in written[className] or {} do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		if key ~= "Name" then
			local value = node[key]
			if value ~= nil and type(value) ~= "function" and not (type(value) == "table" and value.Connect) then
				table.insert(lines, key .. "=" .. encode(value))
			end
		end
	end
	if className == "Path2D" then
		table.insert(lines, "points=" .. encode(node:GetControlPoints()))
	end
	local tags = node:GetTags()
	table.sort(tags)
	table.insert(lines, "tags=" .. table.concat(tags, ","))
	table.insert(lines, "style=" .. encode(node:GetProperties()))
	local children = {}
	for _, child in node:GetChildren() do
		table.insert(children, painted(child))
	end
	table.sort(children)
	return "[" .. table.concat(lines, ";") .. "|" .. table.concat(children, "") .. "]"
end

local function firstDifference(left: string, right: string): string
	for index = 1, math.max(#left, #right) do
		if string.sub(left, index, index) ~= string.sub(right, index, index) then
			return "at "
				.. index
				.. ": driven="
				.. string.sub(left, math.max(1, index - 80), index + 80)
				.. " fresh="
				.. string.sub(right, math.max(1, index - 80), index + 80)
		end
	end
	return "none"
end

local function mountHud(width: number?, height: number?, input: string?)
	local engine = recordingEngine()
	local runtime = Facet.Roblox.createRuntime(engine)
	local viewport = Compose.cell({ width = width or 1079, height = height or 809 })
	local target = engine.new("ScreenGui")
	local gui = engine.new("GuiService")
	local userInput = engine.new("UserInputService")
	userInput.GetFocusedTextBox = function()
		return nil
	end
	if input then
		userInput.PreferredInput = engine.types.Enum.PreferredInput[input]
	end
	local ctx = {
		Facet = Facet,
		Compose = Compose,
		runtime = runtime,
		Host = runtime.constructors,
		UI = Facet.controls(runtime, {
			types = engine.types,
			viewport = viewport,
			services = { GuiService = gui, UserInputService = userInput },
		}),
		types = engine.types,
		viewport = viewport,
	}
	local built
	local stop, root = runtime.mount(function()
		built = hud.build(ctx)
		return built.screen()
	end, target)
	return {
		built = built,
		root = root,
		target = target,
		viewport = viewport,
		engine = engine,
		gui = gui,
		stop = function()
			stop()
			runtime:dispose()
			t.expect(#target:GetChildren()).toBe(0)
		end,
	}
end

local function find(root: any, name: string): any
	return root:FindFirstChild(name, true)
end

local function laneOf(node: any): string?
	local cursor = node.Parent
	while cursor do
		if cursor.Name == "Left" or cursor.Name == "Center" or cursor.Name == "Right" then
			return cursor.Name
		end
		cursor = cursor.Parent
	end
	return nil
end

local RANK = { full = 3, compact = 2, tiny = 1, hidden = 0 }
local ZONES = { "Tasks", "Clock", "Rail", "Health", "Actions", "Feed", "Readout", "Weapon" }
local SIZES = {
	{ width = 1079, height = 809 },
	{ width = 360, height = 691 },
	{ width = 691, height = 360 },
	{ width = 320, height = 240 },
}
local LANDSCAPE = { width = 691, height = 360 }
local PORTRAIT = { width = 360, height = 691 }

local function assertStrip(w: any, where: string)
	for _, name in { "HudActionsTrigger", "Report", "Overflow" } do
		local button = find(w.root, name)
		t.expect(`{where}: {name} present={button ~= nil}`).toBe(`{where}: {name} present=true`)
		local cursor = button
		local visible = true
		while cursor and cursor ~= w.target do
			if cursor.Visible == false then
				visible = false
			end
			cursor = cursor.Parent
		end
		t.expect(`{where}: {name} visible={visible}`).toBe(`{where}: {name} visible=true`)
	end
	find(w.root, "Overflow").Activated.fire()
	t.expect(`{where}: sink opens={w.built.report().overflowOpen}`).toBe(`{where}: sink opens=true`)
	t.expect(find(w.target, "OverflowBody") ~= nil).toBe(true)
	w.built.steps.closeOverflow()
	t.expect(find(w.target, "OverflowBody")).toBe(nil)
end

local function inputObject(engine: any, input: string): any
	local E = engine.types.Enum
	if input == "Gamepad" then
		return { UserInputType = E.UserInputType.Gamepad1, KeyCode = E.KeyCode.ButtonA }
	elseif input == "KeyboardAndMouse" then
		return { UserInputType = E.UserInputType.Keyboard, KeyCode = E.KeyCode.Return }
	elseif input == "Touch" then
		return { UserInputType = E.UserInputType.Touch, KeyCode = E.KeyCode.Unknown }
	end
	return { UserInputType = E.UserInputType.MouseButton1, KeyCode = E.KeyCode.Unknown }
end

t.describe("native parity weaker hud-world", function()
	t.it(
		"apps-206 apps-234 apps-218 every A to B to A path with a URL bar episode and the sink paints the fresh tree",
		function()
			local moved = false
			local checked = 0
			for _, a in SIZES do
				local fresh = mountHud(a.width, a.height)
				for _, b in SIZES do
					if b == a then
						continue
					end
					local w = mountHud(a.width, a.height)
					w.viewport:set(b)
					w.built.steps.openUrlBar()
					w.built.steps.openOverflow()
					local away = painted(w.target)
					moved = moved or away ~= painted(fresh.target)
					w.built.steps.closeOverflow()
					w.built.steps.closeUrlBar()
					w.viewport:set(a)
					local got, want = painted(w.target), painted(fresh.target)
					t.expect(`{a.width}x{a.height} <- {b.width}x{b.height}: {firstDifference(got, want)}`)
						.toBe(`{a.width}x{a.height} <- {b.width}x{b.height}: none`)
					assertStrip(w, `{a.width}x{a.height} <- {b.width}x{b.height}`)
					t.expect(painted(w.target)).toBe(painted(fresh.target))
					checked += 1
					w.stop()
				end
				fresh.stop()
			end
			t.expect(checked).toBe(12)
			t.expect(moved).toBe(true)
		end
	)

	t.it("apps-210 URL bar and rotation sequences and four cycles land on the fresh landscape tree", function()
		local fresh = mountHud(LANDSCAPE.width, LANDSCAPE.height)
		for _, row in
			{
				{ name = "reported", onBefore = true, onDuring = false },
				{ name = "never touched", onBefore = false, onDuring = false },
				{ name = "on only while portrait", onBefore = false, onDuring = true },
				{ name = "on before and again in portrait", onBefore = true, onDuring = true },
			}
		do
			local w = mountHud(LANDSCAPE.width, LANDSCAPE.height)
			if row.onBefore then
				w.built.steps.openUrlBar()
			end
			w.viewport:set(PORTRAIT)
			if row.onDuring then
				w.built.steps.openUrlBar()
			end
			local midway = painted(w.target)
			t.expect(`{row.name}: portrait differs {midway ~= painted(fresh.target)}`)
				.toBe(`{row.name}: portrait differs true`)
			w.built.steps.closeUrlBar()
			w.viewport:set(LANDSCAPE)
			t.expect(`{row.name}: {firstDifference(painted(w.target), painted(fresh.target))}`).toBe(`{row.name}: none`)
			w.stop()
		end
		local w = mountHud(LANDSCAPE.width, LANDSCAPE.height)
		for cycle = 1, 4 do
			w.viewport:set(PORTRAIT)
			t.expect(`cycle {cycle}: portrait differs {painted(w.target) ~= painted(fresh.target)}`)
				.toBe(`cycle {cycle}: portrait differs true`)
			w.viewport:set(LANDSCAPE)
			t.expect(`cycle {cycle}: {firstDifference(painted(w.target), painted(fresh.target))}`)
				.toBe(`cycle {cycle}: none`)
		end
		w.stop()
		fresh.stop()
	end)

	t.it("apps-206 unbatched viewport and native body facts settle where a single change lands", function()
		local Vector2 = nil :: any
		local batched = mountHud(PORTRAIT.width, PORTRAIT.height)
		batched.viewport:set(LANDSCAPE)
		local live = mountHud(PORTRAIT.width, PORTRAIT.height)
		live.viewport:set({ width = LANDSCAPE.width, height = PORTRAIT.height })
		t.expect(painted(live.target) ~= painted(batched.target)).toBe(true)
		live.viewport:set(LANDSCAPE)
		t.expect(firstDifference(painted(live.target), painted(batched.target))).toBe("none")
		live.stop()
		batched.stop()

		local fresh = mountHud()
		Vector2 = fresh.engine.types.Vector2
		find(fresh.root, "HudBody").AbsoluteSize = Vector2.new(300, 140)
		local settling = mountHud()
		local body = find(settling.root, "HudBody")
		body.AbsoluteSize = Vector2.new(960, 620)
		body.AbsoluteSize = Vector2.new(300, 620)
		local between = settling.built.report().forms
		t.expect(between.Tasks).toBe("compact")
		t.expect(painted(settling.target) ~= painted(fresh.target)).toBe(true)
		body.AbsoluteSize = Vector2.new(300, 140)
		t.expect(settling.built.report().forms.Tasks).toBe("hidden")
		t.expect(settling.built.report().forms).toEqual(fresh.built.report().forms)
		t.expect(firstDifference(painted(settling.target), painted(fresh.target))).toBe("none")
		settling.stop()
		fresh.stop()
	end)

	t.it("apps-206 the URL bar takes exactly its drawn height and only the tail of the ladder leaves", function()
		local droppable = { Tasks = true, Feed = true, Readout = true, Weapon = true }
		local stepped = false
		for _, size in SIZES do
			local w = mountHud(size.width, size.height)
			local before = w.built.report().forms
			w.built.steps.openUrlBar()
			local chrome = find(w.root, "BrowserChrome")
			t.expect(chrome.Visible).toBe(true)
			t.expect(chrome.Size.Y.Offset).toBe(64)
			t.expect(chrome.LayoutOrder < find(w.root, "HudBody").LayoutOrder).toBe(true)
			local after = w.built.report().forms
			for _, id in ZONES do
				t.expect(`{id} richer={RANK[after[id]] > RANK[before[id]]}`).toBe(`{id} richer=false`)
				if after[id] == "hidden" then
					t.expect(`{size.width}x{size.height} {id} may leave={droppable[id] == true}`)
						.toBe(`{size.width}x{size.height} {id} may leave=true`)
				elseif after[id] ~= "full" then
					stepped = true
				end
			end
			t.expect(after.Clock ~= "hidden" and after.Actions ~= "hidden").toBe(true)
			assertStrip(w, `{size.width}x{size.height} with the URL bar`)
			w.stop()
		end
		t.expect(stepped).toBe(true)
		for _, row in
			{
				{ height = 660, bar = false, readout = "full" },
				{ height = 659, bar = false, readout = "hidden" },
				{ height = 724, bar = true, readout = "full" },
				{ height = 723, bar = true, readout = "hidden" },
				{ height = 660, bar = true, readout = "hidden" },
			}
		do
			local w = mountHud(1079, row.height)
			if row.bar then
				w.built.steps.openUrlBar()
			end
			local forms = w.built.report().forms
			t.expect(`{row.height} bar={row.bar} Readout={forms.Readout}`)
				.toBe(`{row.height} bar={row.bar} Readout={row.readout}`)
			for _, id in ZONES do
				if id ~= "Readout" then
					t.expect(`{row.height} bar={row.bar} {id}={forms[id]}`).toBe(`{row.height} bar={row.bar} {id}=full`)
				end
			end
			w.stop()
		end
	end)

	t.it("apps-214 a height shrink degrades zones in ladder order and re-solves in place", function()
		local w = mountHud(1079, 809)
		local lanes = {}
		local regions = {}
		for _, lane in { "Left", "Center", "Right" } do
			lanes[lane] = find(w.root, lane)
			t.expect(lanes[lane].ClassName).toBe("ScrollingFrame")
		end
		local home = {
			Tasks = "Left",
			Health = "Left",
			Feed = "Left",
			Clock = "Center",
			Rail = "Right",
			Readout = "Right",
			Weapon = "Right",
			Actions = "Right",
		}
		for _, id in ZONES do
			regions[id] = find(w.root, id)
			t.expect(`{id} in {laneOf(regions[id])}`).toBe(`{id} in {home[id]}`)
		end
		local grid = find(w.root, "HudBody"):FindFirstChildWhichIsA("UIGridLayout")
		t.expect(grid.FillDirectionMaxCells).toBe(3)
		t.expect(grid.CellSize.X.Scale * 3).toBeCloseTo(1)
		t.expect(grid.CellSize.X.Offset * 3 + grid.CellPadding.X.Offset * 2).toBe(0)
		t.expect(grid.CellSize.Y.Scale).toBe(1)
		for _, lane in lanes do
			local stack = lane:FindFirstChild("Content")
			t.expect(stack:FindFirstChildWhichIsA("UIListLayout").FillDirection)
				.toBe(w.engine.types.Enum.FillDirection.Vertical)
		end
		local clock = find(w.root, "ClockFull")
		local previous = w.built.report().forms
		local events = {}
		for height = 809, 200, -1 do
			w.viewport:set({ width = 1079, height = height })
			local forms = w.built.report().forms
			for _, id in ZONES do
				t.expect(`{height} {id} richer={RANK[forms[id]] > RANK[previous[id]]}`)
					.toBe(`{height} {id} richer=false`)
				if forms[id] ~= previous[id] then
					table.insert(events, `{id}:{forms[id]}`)
				end
			end
			if forms.Clock == "full" then
				t.expect(find(w.root, "ClockFull")).toBe(clock)
			end
			previous = forms
		end
		t.expect(table.concat(events, " ")).toBe(
			"Readout:hidden Feed:hidden Tasks:compact Weapon:hidden Rail:compact Actions:compact Clock:compact Tasks:hidden Health:compact"
		)
		for lane, node in lanes do
			t.expect(find(w.root, lane)).toBe(node)
		end
		for _, id in ZONES do
			t.expect(find(w.root, id)).toBe(regions[id])
			t.expect(`{id} in {laneOf(regions[id])}`).toBe(`{id} in {home[id]}`)
		end
		w.viewport:set({ width = 1079, height = 809 })
		for _, id in ZONES do
			t.expect(w.built.report().forms[id]).toBe("full")
		end
		w.stop()
	end)

	t.it("apps-215 the timer is a live ring, the health bar is bound and the round buttons are icon discs", function()
		local w = mountHud()
		local ring = find(w.root, "TimerRing")
		local indicator = ring:FindFirstChild("Indicator")
		t.expect(indicator.Size.X.Offset).toBe(72)
		t.expect(indicator.Size.Y.Offset).toBe(indicator.Size.X.Offset)
		local arc = indicator:FindFirstChild("RingFill")
		t.expect(arc.ClassName).toBe("Path2D")
		local before = encode(arc:GetControlPoints())
		local step = w.built.steps.tickRound()
		t.expect(type(step.fraction)).toBe("number")
		t.expect(step.fraction).toBeCloseTo(0.57)
		t.expect(encode(arc:GetControlPoints()) ~= before).toBe(true)
		t.expect(find(w.root, "TimerText").Text).toBe("2:04")
		local fill = find(find(w.root, "HealthBar"), "Fill4")
		t.expect(fill.Size.X.Scale > 0).toBe(true)
		w.built.steps.takeDamage()
		t.expect(find(w.root, "HealthNum").Text).toBe("59")
		t.expect(fill.Size.X.Scale).toBe(0)
		local images = {}
		for _, entry in
			{
				{ "HudActionsTrigger", hud.copy.round1 },
				{ "Report", hud.copy.round2 },
				{ "Overflow", hud.copy.round3 },
			}
		do
			local disc = find(w.root, entry[1])
			t.expect(disc.ClassName).toBe("TextButton")
			t.expect(disc.Text).toBe("")
			t.expect(disc:HasTag("facet-shape-circle")).toBe(true)
			t.expect(disc.Size.X.Offset).toBe(44)
			t.expect(disc.Size.Y.Offset).toBe(disc.Size.X.Offset)
			t.expect(disc:FindFirstChildWhichIsA("UIAspectRatioConstraint").AspectRatio).toBe(1)
			t.expect(disc:FindFirstChildWhichIsA("UICorner").CornerRadius.Scale).toBe(1)
			t.expect(disc:GetAttribute("label")).toBe(entry[2])
			local icon = find(disc, "LeadingIcon")
			t.expect(icon.ClassName).toBe("ImageLabel")
			t.expect(string.find(icon.Image, "^rbxassetid://%d+$") ~= nil).toBe(true)
			t.expect(images[icon.Image]).toBe(nil)
			images[icon.Image] = true
		end
		w.stop()
	end)

	for _, input in { "Gamepad", "KeyboardAndMouse", "Touch", "Mouse" } do
		t.it(`apps-221 {input} uses the HUD actions and recovers focus after a notification`, function()
			local w = mountHud(1280, 800, if input == "Mouse" then "KeyboardAndMouse" else input)
			local trigger = find(w.root, "HudActionsTrigger")
			local directional = input == "Gamepad" or input == "KeyboardAndMouse"
			local event = inputObject(w.engine, input)
			if directional then
				w.gui.SelectedObject = trigger
			end
			local function choose(id: string)
				trigger.Activated.fire(event, 1)
				local item = find(w.target, id)
				t.expect(`{input} {id} item present={item ~= nil}`).toBe(`{input} {id} item present=true`)
				if directional then
					t.expect(w.gui.SelectedObject ~= nil and w.gui.SelectedObject:IsDescendantOf(w.target)).toBe(true)
					t.expect(w.gui.SelectedObject:IsDescendantOf(trigger.Parent)).toBe(false)
				else
					t.expect(w.gui.SelectedObject).toBe(nil)
				end
				item.Activated.fire(event, 1)
				t.expect(find(w.target, id)).toBe(nil)
				t.expect(w.gui.SelectedObject).toBe(if directional then trigger else nil)
			end
			choose("damage")
			t.expect(w.built.report().health < 0.84).toBe(true)
			choose("heal")
			t.expect(w.built.report().health).toBe(1)
			choose("notice")
			local notice = find(w.root, "Notice")
			t.expect(notice.Visible).toBe(true)
			t.expect(notice:FindFirstChildWhichIsA("TextButton").Text).toBe("Supplies delivered")
			t.expect(notice.LayoutOrder < find(w.root, "HudBody").LayoutOrder).toBe(true)
			t.expect(w.gui.SelectedObject).toBe(if directional then trigger else nil)
			trigger.Activated.fire(event, 1)
			t.expect(find(w.target, "damage") ~= nil).toBe(true)
			local back = find(w.target, "ModalBack")
			local keys = {}
			for _, binding in back:GetChildren() do
				keys[tostring(binding.KeyCode)] = true
			end
			t.expect(keys["Enum.KeyCode.ButtonB"]).toBe(true)
			t.expect(keys["Enum.KeyCode.Escape"]).toBe(true)
			back.Pressed.fire()
			t.expect(find(w.target, "damage")).toBe(nil)
			t.expect(w.gui.SelectedObject).toBe(if directional then trigger else nil)
			t.expect(notice.Visible).toBe(true)
			notice:FindFirstChildWhichIsA("TextButton").Activated.fire(event, 1)
			t.expect(notice.Visible).toBe(false)
			w.stop()
		end)
	end

	t.it("themes-P1-11 circular readouts center only while native text bounds fit inside the ring", function()
		local engine = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local UI = Facet.controls(runtime, { types = engine.types })
		local stop, meter = runtime.mount(function()
			return UI.ProgressView({ value = 0.75, presentation = "circular", diameter = 120, showValue = true })
		end, engine.new("Folder"))
		local readout, gauge = find(meter, "Value"), find(meter, "Gauge")
		local V2, D2, E = engine.types.Vector2, engine.types.UDim2, engine.types.Enum
		t.expect(readout.TextXAlignment).toBe(E.TextXAlignment.Center)
		t.expect(readout.TextWrapped).toBe(false)
		t.expect(readout.AutomaticSize).toBe(E.AutomaticSize.XY)
		for _, bounds in { V2.new(38, 20), V2.new(72, 72) } do
			readout.TextBounds = bounds
			t.expect(readout.AnchorPoint).toBe(V2.new(0.5, 0.5))
			t.expect(readout.Position).toBe(D2.new(0.5, 0, 0, 60))
			t.expect(gauge.Size).toBe(D2.fromOffset(120, 120))
			local left = 60 - bounds.X / 2
			t.expect(left >= 0 and left + bounds.X <= 120).toBe(true)
		end
		readout.TextBounds = V2.new(73, 20)
		t.expect(readout.AnchorPoint).toBe(V2.new(0.5, 0))
		t.expect(readout.Position).toBe(D2.new(0.5, 0, 0, 128))
		t.expect(gauge.Size).toBe(D2.fromOffset(120, 148))
		stop()
		runtime:dispose()
	end)

	t.it("themes-P1-14 a gauge keeps a long value whole and visible as native text grows", function()
		local engine = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local UI = Facet.controls(runtime, { types = engine.types })
		local stop, meter = runtime.mount(function()
			return UI.ProgressView({
				value = 1,
				presentation = "circular",
				diameter = 80,
				showValue = true,
				label = "A long localized resource label",
				format = function()
					return "10000 / 10000"
				end,
			})
		end, engine.new("Folder"))
		local readout, gauge = find(meter, "Value"), find(meter, "Gauge")
		local V2, E = engine.types.Vector2, engine.types.Enum
		for _, bounds in { V2.new(120, 20), V2.new(150, 24), V2.new(190, 32), V2.new(260, 40) } do
			readout.TextBounds = bounds
			t.expect(readout.Text).toBe("10000 / 10000")
			t.expect(readout.Visible).toBe(true)
			t.expect(readout.TextWrapped).toBe(false)
			t.expect(readout.TextTruncate).toBe(E.TextTruncate.None)
			t.expect(readout.TextXAlignment).toBe(E.TextXAlignment.Center)
			t.expect(readout.AnchorPoint).toBe(V2.new(0.5, 0))
			t.expect(readout.Position.Y.Offset).toBe(88)
			t.expect(gauge.Size.X.Offset).toBe(bounds.X)
			t.expect(gauge.Size.X.Offset > 80).toBe(true)
			t.expect(gauge.Size.Y.Offset).toBe(80 + 8 + bounds.Y)
			t.expect(gauge.ClipsDescendants).toBe(false)
		end
		stop()
		runtime:dispose()
	end)

	t.it("themes-P1-102 Stage forwards ambient, light color and light direction and keeps them reactive", function()
		local engine = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local UI = Facet.controls(runtime, { types = engine.types })
		local Color3, Vector3 = engine.types.Color3, engine.types.Vector3
		local light = Compose.cell(Color3.new(1, 0.95, 0.9))
		local stop, stage = runtime.mount(function()
			return UI.Stage({
				Ambient = Color3.new(0.2, 0.2, 0.25),
				LightColor = light,
				LightDirection = Vector3.new(-1, -1, 0),
			})
		end, engine.new("Folder"))
		t.expect(stage.ClassName).toBe("ViewportFrame")
		t.expect(stage.Ambient).toBe(Color3.new(0.2, 0.2, 0.25))
		t.expect(stage.LightColor).toBe(Color3.new(1, 0.95, 0.9))
		t.expect(stage.LightDirection).toBe(Vector3.new(-1, -1, 0))
		light:set(Color3.new(0.5, 0.6, 0.7))
		t.expect(stage.LightColor).toBe(Color3.new(0.5, 0.6, 0.7))
		stop()
		local defaults = engine.new("ViewportFrame")
		local stopPartial, partial = runtime.mount(function()
			return UI.Stage({ Ambient = Color3.new(0, 0, 0) })
		end, engine.new("Folder"))
		t.expect(partial.Ambient).toBe(Color3.new(0, 0, 0))
		t.expect(partial.LightColor).toBe(defaults.LightColor)
		t.expect(partial.LightDirection).toBe(defaults.LightDirection)
		stopPartial()
		runtime:dispose()
	end)

	t.it("apps2-130 the terminal surface declares its walk-up contract and a 4:3 console canvas", function()
		local engine = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local sent = {}
		local remote = engine.new("RemoteEvent")
		remote.OnClientEvent = engine.heartbeat
		remote.FireServer = function(_, message)
			table.insert(sent, message)
		end
		local world = engine.new("Folder")
		local model = engine.new("Model")
		model.Name = "Outpost"
		model.Parent = world
		local console = engine.new("Part")
		console.Name = "Console"
		console.Parent = model
		local inputTarget = engine.new("PlayerGui")
		local outside = engine.new("TextButton")
		outside.Parent = engine.new("ScreenGui")
		gui.SelectedObject = outside
		local ctx = {
			Facet = Facet,
			Compose = Compose,
			runtime = runtime,
			Host = runtime.constructors,
			UI = Facet.controls(runtime, { types = engine.types, services = { GuiService = gui } }),
			types = engine.types,
			inputTarget = inputTarget,
			worldTarget = world,
			guiService = gui,
			outpostRemote = remote,
			load = function()
				return terminal
			end,
		}
		local built
		local stop = runtime.mount(function()
			built = outpost.build(ctx)
			return built.screen()
		end, engine.new("ScreenGui"))
		t.expect(terminal.CANVAS.w).toBe(640)
		t.expect(terminal.CANVAS.h).toBe(480)
		t.expect(terminal.CANVAS.w / terminal.CANVAS.h).toBeCloseTo(8 / 6)
		local surface = inputTarget:FindFirstChild("OutpostSurface")
		t.expect(surface.CanvasSize).toBe(engine.types.Vector2.new(640, 480))
		t.expect(surface.SizingMode).toBe(engine.types.Enum.SurfaceGuiSizingMode.FixedSize)
		t.expect(surface.Adornee).toBe(console)
		local context = inputTarget:FindFirstChild("OutpostInput")
		local leave = context:FindFirstChild("LeaveConsole")
		local keys = {}
		for _, binding in leave:GetChildren() do
			keys[tostring(binding.KeyCode)] = true
		end
		t.expect(keys["Enum.KeyCode.Escape"]).toBe(true)
		t.expect(keys["Enum.KeyCode.ButtonB"]).toBe(true)
		t.expect(context.Sink).toBe(true)
		t.expect(surface.Active).toBe(false)
		t.expect(context.Enabled).toBe(false)
		t.expect(gui.SelectedObject).toBe(outside)
		remote.OnClientEvent.fire({ kind = "session", token = "s1", revision = 1, allocation = rules.START })
		t.expect(surface.Active).toBe(true)
		t.expect(context.Enabled).toBe(true)
		local first = gui.SelectedObject
		t.expect(first ~= outside and first:IsDescendantOf(surface)).toBe(true)
		local expected = nil
		for _, node in surface:GetDescendants() do
			if node:IsA("GuiButton") and node.Selectable then
				expected = node
				break
			end
		end
		t.expect(first).toBe(expected)
		t.expect(first:IsDescendantOf(find(surface, "doorStep"))).toBe(true)
		leave.Pressed.fire()
		t.expect(built.report().lastExit).toBe("cancel")
		t.expect(built.report().terminal.phase).toBe("exited")
		t.expect(surface.isDestroyed()).toBe(false)
		t.expect(surface.Parent).toBe(inputTarget)
		t.expect(surface.Active).toBe(false)
		t.expect(context.Enabled).toBe(false)
		t.expect(gui.SelectedObject).toBe(outside)
		t.expect(sent[#sent].kind).toBe("release")
		remote.OnClientEvent.fire({ kind = "session", token = "s2", revision = 2, allocation = rules.START })
		t.expect(surface.Active).toBe(true)
		t.expect(built.report().terminal.phase).toBe("engaged")
		stop()
		t.expect(surface.isDestroyed()).toBe(true)
		runtime:dispose()
	end)
end)

local function lab(noTransport: boolean?)
	local engine = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local sent = {}
	local ctx = {
		Facet = Facet,
		Compose = Compose,
		runtime = runtime,
		Host = runtime.constructors,
		UI = Facet.controls(runtime, { types = engine.types }),
		types = engine.types,
	}
	local built
	local stop, root = runtime.mount(function()
		built = terminal.build(ctx, {
			send = if noTransport
				then nil
				else function(envelope)
					table.insert(sent, envelope)
				end,
		})
		return built.screen()
	end, engine.new("ScreenGui"))
	return {
		built = built,
		steps = built.steps,
		sent = sent,
		root = root,
		shown = function()
			return find(root, "Message").Text
		end,
		stop = function()
			stop()
			runtime:dispose()
		end,
	}
end

local function answer(f: any, situation: any?): boolean
	local envelope = f.sent[#f.sent]
	assert(envelope ~= nil, "nothing was sent")
	local s = situation or {}
	local verdict = rules.authorize({
		holderId = s.holderId or "me",
		senderId = "me",
		holderToken = s.holderToken or "s1",
		token = s.token or "s1",
		sinceLast = s.sinceLast,
		distance = if s.distance ~= nil then s.distance else 4,
		allocation = envelope.payload.allocation,
	})
	if verdict.ok then
		return f.steps.confirm(envelope.requestId, { revision = 99, allocation = envelope.payload.allocation })
	end
	return f.steps.reject(envelope.requestId, { code = verdict.code, message = verdict.message })
end

local function solve(f: any)
	f.steps.engage(rules.START)
	f.steps.setValue("door", 2)
	f.steps.setValue("beacon", 1)
	f.steps.setValue("workshop", 2)
end

local function tap(engine: any): any
	return { UserInputType = engine.types.Enum.UserInputType.Touch, KeyCode = engine.types.Enum.KeyCode.Unknown }
end

t.describe("native parity weaker replication-server", function()
	t.it("apps2-127 an illegal draft is refused on the terminal and never reaches the wire", function()
		local f = lab()
		f.steps.engage(rules.START)
		f.steps.setValue("door", 3)
		f.steps.setValue("beacon", 2)
		f.steps.setValue("workshop", 4)
		local state = f.steps.snapshot()
		t.expect(state.canApply).toBe(false)
		t.expect(state.message).toBe("The generator makes 6 units and that allocation asks for 9.")
		t.expect(f.shown()).toBe("The generator makes 6 units and that allocation asks for 9.")
		local result = f.steps.apply()
		t.expect(result.sent).toBe(false)
		t.expect(result.reason).toBe("budget")
		t.expect(#f.sent).toBe(0)
		t.expect(f.steps.snapshot().counters.refusedLocally).toBe(1)
		f.stop()
	end)

	t.it(
		"apps2-127 apply sends one intent with the draft, pending is not success and a second apply is refused",
		function()
			local f = lab()
			solve(f)
			local result = f.steps.apply()
			t.expect(result.sent).toBe(true)
			t.expect(#f.sent).toBe(1)
			t.expect(f.sent[1].payload.kind).toBe("set")
			t.expect(f.sent[1].payload.allocation.door).toBe(2)
			t.expect(f.sent[1].payload.allocation.beacon).toBe(1)
			t.expect(f.sent[1].payload.allocation.workshop).toBe(2)
			local state = f.steps.snapshot()
			t.expect(state.status).toBe("pending")
			t.expect(state.message).toBe("Sending to the outpost…")
			t.expect(f.shown()).toBe("Sending to the outpost…")
			t.expect(state.outpost.door).toBe(3)
			t.expect(state.complete).toBe(false)
			local second = f.steps.apply()
			t.expect(second.sent).toBe(false)
			t.expect(second.reason).toBe("pending")
			t.expect(#f.sent).toBe(1)
			f.stop()
		end
	)

	t.it("apps2-127 a confirmed verdict moves the outpost and the screen says what changed", function()
		local f = lab()
		solve(f)
		f.steps.apply()
		t.expect(answer(f)).toBe(true)
		local state = f.steps.snapshot()
		t.expect(state.status).toBe("confirmed")
		t.expect(state.outpost.beacon).toBe(1)
		t.expect(state.revision).toBe(99)
		t.expect(state.complete).toBe(true)
		t.expect(state.message).toBe("All three are running, with 1 unit to spare.")
		t.expect(f.shown()).toBe("All three are running, with 1 unit to spare.")
		t.expect(state.counters.applied).toBe(1)
		f.stop()
	end)

	t.it("apps2-127 a refusal is shown and the draft survives it", function()
		local f = lab()
		solve(f)
		f.steps.apply()
		answer(f, { distance = 22 })
		local state = f.steps.snapshot()
		t.expect(state.status).toBe("rejected")
		t.expect(state.message).toBe("You are 22 studs from the console. Step within 10 to use it.")
		t.expect(f.shown()).toBe("You are 22 studs from the console. Step within 10 to use it.")
		t.expect(state.outpost.door).toBe(3)
		t.expect(state.draft.door).toBe(2)
		t.expect(state.draft.beacon).toBe(1)
		t.expect(state.draft.workshop).toBe(2)
		local retry = f.steps.apply()
		t.expect(retry.sent).toBe(true)
		t.expect(f.sent[#f.sent].payload.allocation.door).toBe(2)
		f.stop()
	end)

	t.it("apps2-127 every server refusal reaches the screen as its own sentence", function()
		local seen = {}
		for _, case in
			{
				{ situation = { holderId = "someone-else" }, message = rules.refusal("holder") },
				{ situation = { token = "stale" }, message = rules.refusal("session") },
				{ situation = { sinceLast = 0.01 }, message = rules.refusal("rate") },
				{ situation = { distance = 40 }, message = rules.refusal("distance", { distance = 40, range = 10 }) },
			}
		do
			local f = lab()
			f.steps.engage(rules.START)
			f.steps.setValue("door", 2)
			f.steps.apply()
			answer(f, case.situation)
			t.expect(f.steps.snapshot().message).toBe(case.message)
			t.expect(f.shown()).toBe(case.message)
			t.expect(f.steps.snapshot().status).toBe("rejected")
			t.expect(seen[case.message]).toBe(nil)
			seen[case.message] = true
			f.stop()
		end
	end)

	t.it("apps2-127 reset is a server intent and the verdict moves the outpost back", function()
		local f = lab()
		f.steps.engage({ door = 2, beacon = 1, workshop = 2 })
		local result = f.steps.reset()
		t.expect(result.sent).toBe(true)
		t.expect(#f.sent).toBe(1)
		t.expect(f.sent[1].payload.allocation.door).toBe(rules.START.door)
		t.expect(f.sent[1].payload.allocation.beacon).toBe(0)
		t.expect(f.steps.snapshot().draft.door).toBe(rules.START.door)
		t.expect(f.steps.snapshot().outpost.workshop).toBe(2)
		answer(f)
		t.expect(f.steps.snapshot().outpost.workshop).toBe(0)
		t.expect(f.steps.snapshot().outpost.door).toBe(rules.START.door)
		f.stop()
	end)

	t.it("apps2-127 an allocation another player applied lands without touching this draft", function()
		local f = lab()
		f.steps.engage(rules.START)
		f.steps.setValue("workshop", 3)
		t.expect(f.steps.ingest(12, { door = 2, beacon = 1, workshop = 2 })).toBe(true)
		local state = f.steps.snapshot()
		t.expect(state.outpost.workshop).toBe(2)
		t.expect(state.draft.workshop).toBe(3)
		t.expect(find(f.root, "Confirmed").Text).toBe("Outpost: 3 of 3 consumers running.")
		t.expect(f.steps.ingest(3, { door = 0, beacon = 0, workshop = 0 })).toBe(false)
		t.expect(f.steps.snapshot().outpost.door).toBe(2)
		t.expect(f.steps.snapshot().draft.workshop).toBe(3)
		f.stop()
	end)

	t.it(
		"apps2-41 settings sync applies optimistically, confirms, and rolls back a rejection by touch alone",
		function()
			local engine = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local ctx = {
				Facet = Facet,
				Compose = Compose,
				runtime = runtime,
				Host = runtime.constructors,
				UI = Facet.controls(runtime, { types = engine.types }),
				types = engine.types,
			}
			local built
			local stop, node = runtime.mount(function()
				built = settingsSync.build(ctx)
				return built.screen()
			end, engine.new("ScreenGui"))
			local touch = tap(engine)
			local function shown(name: string): string
				return find(node, name).Text
			end
			t.expect(shown("Status")).toBe("idle")
			t.expect(shown("Draft")).toBe("What you see now: music off, volume 10")
			t.expect(shown("Confirmed")).toBe("Server confirmed: music off, volume 10 (revision 1)")
			find(node, "Music").Activated.fire(touch, 1)
			t.expect(built.report().draft.music).toBe(true)
			t.expect(built.report().status).toBe("pending")
			t.expect(built.report().server.music).toBe(false)
			t.expect(shown("Status")).toBe("pending")
			t.expect(shown("Draft")).toBe("What you see now: music on, volume 10")
			t.expect(shown("Confirmed")).toBe("Server confirmed: music off, volume 10 (revision 1)")
			find(node, "Deliver").Activated.fire(touch, 1)
			t.expect(built.report().status).toBe("confirmed")
			t.expect(built.report().server.music).toBe(true)
			t.expect(built.report().server.revision).toBe(2)
			t.expect(built.report().draft.music).toBe(true)
			t.expect(shown("Status")).toBe("confirmed")
			t.expect(shown("Confirmed")).toBe("Server confirmed: music on, volume 10 (revision 2)")
			find(node, "Music").Activated.fire(touch, 1)
			t.expect(built.report().status).toBe("pending")
			find(node, "Deliver").Activated.fire(touch, 1)
			t.expect(built.report().draft.music).toBe(false)
			t.expect(built.report().server.music).toBe(false)
			t.expect(built.report().status).toBe("confirmed")
			find(node, "Invalid").Activated.fire(touch, 1)
			t.expect(built.report().draft.volume).toBe(99)
			t.expect(built.report().status).toBe("pending")
			t.expect(shown("Draft")).toBe("What you see now: music off, volume 99")
			find(node, "Deliver").Activated.fire(touch, 1)
			t.expect(built.report().status).toBe("rejected")
			t.expect(built.report().draft.volume).toBe(10)
			t.expect(built.report().server.revision).toBe(3)
			t.expect(shown("Status")).toBe("rejected")
			t.expect(shown("Draft")).toBe("What you see now: music off, volume 10")
			t.expect(shown("Confirmed")).toBe("Server confirmed: music off, volume 10 (revision 3)")
			stop()
			runtime:dispose()
		end
	)
end)
