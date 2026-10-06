--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local hud = require("../examples/gallery/scenarios/hud")
	local terminal = require("../examples/gallery/examples/outpost_terminal")
	local outpost = require("../examples/gallery/scenarios/outpost_terminal")
	local settingsSync = require("../examples/gallery/examples/03_settings_sync")

	local measured = require("./lib/hud_measure")
	local rules = terminal.rules
	local Compose: ComposeModule = Facet.Compose

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
		for key in (written[className] or {}) :: { [string]: boolean } do
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
		table.insert(lines, "style=" .. encode(if node:IsA("StyleRule") then node:GetProperties() else {}))
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
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local viewport = Compose.cell({ width = width or 1079, height = height or 809 })
		local target = engine.new("ScreenGui")
		local gui = engine.new("GuiService")
		local userInput = engine.new("UserInputService")
		userInput.GetFocusedTextBox = function()
			return nil
		end
		if input then
			userInput.PreferredInput = engine.types.Enum.PreferredInput:FromName(input)
		end
		local ctx = {
			Facet = Facet,
			Compose = Compose,
			runtime = runtime,
			Host = (runtime.constructors :: unknown) :: RobloxHost,
			UI = Facet.controls(runtime, {
				types = engine.types,
				viewport = viewport,
				services = { GuiService = gui, UserInputService = userInput },
			}),
			types = engine.types,
			viewport = viewport,
		}
		local built
		local stop, root: any = runtime.mount(function()
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
				Verify.expect(#target:GetChildren()):toBe(0)
			end,
		}
	end

	local function find(root: any, name: string): any
		return root:FindFirstChild(name, true)
	end

	local function depth(id: string, name: string): number
		return if name == "hidden" then 99 elseif name == "reveal" then 98 else assert(table.find(hud.forms[id], name))
	end
	local LADDER =
		"Feed:hidden Tasks:one Readout:hidden Weapon:hidden Rail:chip Tasks:reveal Tasks:hidden Health:reveal Rail:hidden Health:hidden Clock:timer"
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
		for _, name in { "HudActionsTrigger", "Report" } do
			local button = find(w.root, name)
			Verify.expect(`{where}: {name} present={button ~= nil}`):toBe(`{where}: {name} present=true`)
			local cursor = button
			local visible = true
			while cursor and cursor ~= w.target do
				if cursor.Visible == false then
					visible = false
				end
				cursor = cursor.Parent
			end
			Verify.expect(`{where}: {name} visible={visible}`):toBe(`{where}: {name} visible=true`)
		end
		w.built.steps.openOverflow()
		Verify.expect(`{where}: sink opens={w.built.report().overflowOpen}`):toBe(`{where}: sink opens=true`)
		Verify.expect(find(w.target, "OverflowBody") ~= nil):toBe(true)
		w.built.steps.closeOverflow()
		Verify.expect((find(w.target, "OverflowBody"))):toBe(nil)
	end

	local function inputObject(engine: any, input: string): any
		local E = engine.types.Enum
		if input == "Gamepad" then
			return { UserInputType = E.UserInputType.Gamepad1, KeyCode = E.KeyCode.ButtonA }
		elseif input == "KeyboardAndMouse" then
			return { UserInputType = E.UserInputType.Keyboard, KeyCode = E.KeyCode.Return }
		elseif input == "Touch" then
			return { UserInputType = E.UserInputType.Touch, KeyCode = E.KeyCode:FromValue(0) }
		end
		return { UserInputType = E.UserInputType.MouseButton1, KeyCode = E.KeyCode:FromValue(0) }
	end

	verifyHarness:suite("native parity weaker hud-world", function()
		verifyHarness:case(
			"apps-206 apps-234 apps-218 every A to B to A path with a URL bar episode and the sink paints the fresh tree",
			{
				id = "native_parity_weaker_hud::native parity weaker hud-world::apps-206 apps-234 apps-218 every A to B to A path with a URL bar episode and the sink paints the fresh tree",
				run = function()
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
							Verify.expect(`{a.width}x{a.height} <- {b.width}x{b.height}: {firstDifference(got, want)}`)
								:toBe(`{a.width}x{a.height} <- {b.width}x{b.height}: none`)
							assertStrip(w, `{a.width}x{a.height} <- {b.width}x{b.height}`)
							Verify.expect((painted(w.target))):toBe(painted(fresh.target))
							checked += 1
							w.stop()
						end
						fresh.stop()
					end
					Verify.expect(checked):toBe(12)
					Verify.expect(moved):toBe(true)
				end,
			}
		)

		verifyHarness:case("apps-210 URL bar and rotation sequences and four cycles land on the fresh landscape tree", {
			id = "native_parity_weaker_hud::native parity weaker hud-world::apps-210 URL bar and rotation sequences and four cycles land on the fresh landscape tree",
			run = function()
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
					Verify.expect(`{row.name}: portrait differs {midway ~= painted(fresh.target)}`)
						:toBe(`{row.name}: portrait differs true`)
					w.built.steps.closeUrlBar()
					w.viewport:set(LANDSCAPE)
					Verify.expect(`{row.name}: {firstDifference(painted(w.target), painted(fresh.target))}`)
						:toBe(`{row.name}: none`)
					w.stop()
				end
				local w = mountHud(LANDSCAPE.width, LANDSCAPE.height)
				for cycle = 1, 4 do
					w.viewport:set(PORTRAIT)
					Verify.expect(`cycle {cycle}: portrait differs {painted(w.target) ~= painted(fresh.target)}`)
						:toBe(`cycle {cycle}: portrait differs true`)
					w.viewport:set(LANDSCAPE)
					Verify.expect(`cycle {cycle}: {firstDifference(painted(w.target), painted(fresh.target))}`)
						:toBe(`cycle {cycle}: none`)
				end
				w.stop()
				fresh.stop()
			end,
		})

		verifyHarness:case("apps-206 unbatched viewport and native body facts settle where a single change lands", {
			id = "native_parity_weaker_hud::native parity weaker hud-world::apps-206 unbatched viewport and native body facts settle where a single change lands",
			run = function()
				local batched = mountHud(PORTRAIT.width, PORTRAIT.height)
				batched.viewport:set(LANDSCAPE)
				local live = mountHud(PORTRAIT.width, PORTRAIT.height)
				live.viewport:set({ width = LANDSCAPE.width, height = PORTRAIT.height })
				live.viewport:set(LANDSCAPE)
				Verify.expect((firstDifference(painted(live.target), painted(batched.target)))):toBe("none")
				live.stop()
				batched.stop()

				local fresh = mountHud()
				measured.measure(fresh.root, fresh.engine, measured.TINY)
				local settling = mountHud()
				measured.measure(settling.root, settling.engine, { 1040, 640 })
				measured.measure(settling.root, settling.engine, { 300, 640 })
				local between = settling.built.report().forms
				Verify.expect(between.Tasks):toBe("chip")
				Verify.expect(painted(settling.target) ~= painted(fresh.target)):toBe(true)
				measured.measure(settling.root, settling.engine, measured.TINY)
				Verify.expect(settling.built.report().forms.Tasks):toBe("hidden")
				Verify.expect(settling.built.report().forms):toEqual(fresh.built.report().forms)
				settling.engine.heartbeat.fire(1)
				Verify.expect((firstDifference(painted(settling.target), painted(fresh.target)))):toBe("none")
				settling.stop()
				fresh.stop()
			end,
		})

		verifyHarness:case(
			"apps-206 the URL bar takes exactly its drawn height and only the tail of the ladder leaves",
			{
				id = "native_parity_weaker_hud::native parity weaker hud-world::apps-206 the URL bar takes exactly its drawn height and only the tail of the ladder leaves",
				run = function()
					local droppable =
						{ Tasks = true, Feed = true, Readout = true, Weapon = true, Health = true, Rail = true }
					local stepped = false
					for _, box in { measured.LANDSCAPE, measured.PORTRAIT, { 1040, 640 } } do
						local w = mountHud()
						measured.measure(w.root, w.engine, box)
						local before = w.built.report().forms
						w.built.steps.openUrlBar()
						local chrome = find(w.root, "BrowserChrome")
						Verify.expect(chrome.Visible):toBe(true)
						Verify.expect(chrome.Size.Y.Offset):toBe(64)
						Verify.expect(chrome.LayoutOrder < find(w.root, "HudBody").LayoutOrder):toBe(true)
						measured.measure(w.root, w.engine, { box[1], box[2] - 64 })
						local after = w.built.report().forms
						for _, id in ZONES do
							Verify.expect(`{id} richer={depth(id, after[id]) < depth(id, before[id])}`)
								:toBe(`{id} richer=false`)
							if after[id] == "hidden" then
								Verify.expect(`{box[1]}x{box[2]} {id} may leave={droppable[id] == true}`)
									:toBe(`{box[1]}x{box[2]} {id} may leave=true`)
							elseif after[id] ~= before[id] then
								stepped = true
							end
						end
						Verify.expect(after.Clock ~= "hidden" and after.Actions ~= "hidden"):toBe(true)
						w.stop()
					end
					Verify.expect(stepped):toBe(true)
					for _, row in
						{
							{ height = 232, bar = false, feed = "full" },
							{ height = 231, bar = false, feed = "hidden" },
							{ height = 296, bar = true, feed = "full" },
							{ height = 295, bar = true, feed = "hidden" },
						}
					do
						local w = mountHud()
						if row.bar then
							w.built.steps.openUrlBar()
						end
						measured.measure(w.root, w.engine, { 828, row.height - (if row.bar then 64 else 0) })
						local forms = w.built.report().forms
						Verify.expect(`{row.height} bar={row.bar} Feed={forms.Feed}`)
							:toBe(`{row.height} bar={row.bar} Feed={row.feed}`)
						for _, id in ZONES do
							if id ~= "Feed" then
								Verify.expect(`{row.height} bar={row.bar} {id}={forms[id]}`)
									:toBe(`{row.height} bar={row.bar} {id}=full`)
							end
						end
						w.stop()
					end
				end,
			}
		)

		verifyHarness:case("apps-214 a height shrink degrades zones in ladder order and re-solves in place", {
			id = "native_parity_weaker_hud::native parity weaker hud-world::apps-214 a height shrink degrades zones in ladder order and re-solves in place",
			run = function()
				local w = mountHud(1079, 809)
				local home = {
					Tasks = "Left",
					Health = "BottomLeft",
					Feed = "BottomLeft",
					Clock = "Top",
					Rail = "TopRight",
					Readout = "TopRight",
					Weapon = "BottomRight",
					Actions = "BottomRight",
				}
				local regions = {}
				for _, id in ZONES do
					regions[id] = find(w.root, id)
					Verify.expect(`{id} in {regions[id].Parent.Name}`):toBe(`{id} in {home[id]}`)
				end
				local clock = find(w.root, "ClockFull")
				measured.measure(w.root, w.engine, { 828, 400 })
				local previous = w.built.report().forms
				local events = {}
				for height = 400, 60, -1 do
					measured.measure(w.root, w.engine, { 828, height })
					local forms = w.built.report().forms
					for _, id in ZONES do
						Verify.expect(`{height} {id} richer={depth(id, forms[id]) < depth(id, previous[id])}`)
							:toBe(`{height} {id} richer=false`)
						if forms[id] ~= previous[id] then
							table.insert(events, `{id}:{forms[id]}`)
						end
					end
					if forms.Clock == "full" then
						Verify.expect((find(w.root, "ClockFull"))):toBe(clock)
					end
					previous = forms
				end
				Verify.expect((table.concat(events, " "))):toBe(LADDER)
				for _, id in ZONES do
					Verify.expect((find(w.root, id))):toBe(regions[id])
					Verify.expect(`{id} in {regions[id].Parent.Name}`):toBe(`{id} in {home[id]}`)
				end
				measured.measure(w.root, w.engine, { 828, 400 })
				for _, id in ZONES do
					Verify.expect(w.built.report().forms[id]):toBe("full")
				end
				w.stop()
			end,
		})

		verifyHarness:case(
			"apps-215 the timer is a live ring, the health bar is bound and the round buttons are icon discs",
			{
				id = "native_parity_weaker_hud::native parity weaker hud-world::apps-215 the timer is a live ring, the health bar is bound and the round buttons are icon discs",
				run = function()
					local w = mountHud()
					local ring = find(w.root, "TimerRing")
					local indicator = ring:FindFirstChild("Indicator")
					Verify.expect(indicator.Size.X.Offset):toBe(28)
					Verify.expect(indicator.Size.Y.Offset):toBe(indicator.Size.X.Offset)
					local arc = indicator:FindFirstChild("RingFill")
					Verify.expect(arc.ClassName):toBe("Path2D")
					local before = encode(arc:GetControlPoints())
					local step = w.built.steps.tickRound()
					Verify.expect((type(step.fraction))):toBe("number")
					Verify.expect(step.fraction):toBeCloseTo(0.57, 1e-4)
					Verify.expect(encode(arc:GetControlPoints()) ~= before):toBe(true)
					Verify.expect(find(w.root, "TimerText").Text):toBe("2:04")
					local fill = find(find(w.root, "HealthBar"), "Fill4")
					Verify.expect(fill.Size.X.Scale > 0):toBe(true)
					w.built.steps.takeDamage()
					Verify.expect(find(w.root, "HealthNum").Text):toBe("59")
					Verify.expect(fill.Size.X.Scale):toBe(0)
					local images = {}
					for _, entry in
						{
							{ "HudActionsTrigger", hud.copy.round1 },
							{ "Report", hud.copy.round2 },
						}
					do
						local disc = find(w.root, entry[1])
						Verify.expect(disc.ClassName):toBe("TextButton")
						Verify.expect(disc.Text):toBe("")
						Verify.expect((disc:HasTag("facet-shape-circle"))):toBe(true)
						Verify.expect(disc.Size.X.Offset):toBe(44)
						Verify.expect(disc.Size.Y.Offset):toBe(disc.Size.X.Offset)
						Verify.expect(disc:FindFirstChildWhichIsA("UIAspectRatioConstraint").AspectRatio):toBe(1)
						Verify.expect(disc:FindFirstChildWhichIsA("UICorner").CornerRadius.Scale):toBe(1)
						Verify.expect((disc:GetAttribute("label"))):toBe(entry[2])
						local icon = find(disc, "LeadingIcon")
						Verify.expect(icon.ClassName):toBe("ImageLabel")
						Verify.expect(string.find(icon.Image, "^rbxassetid://%d+$") ~= nil):toBe(true)
						Verify.expect(images[icon.Image]):toBe(nil)
						images[icon.Image] = true
					end
					w.stop()
				end,
			}
		)

		for _, input in { "Gamepad", "KeyboardAndMouse", "Touch", "Mouse" } do
			verifyHarness:case(`apps-221 {input} uses the HUD actions and recovers focus after a notification`, {
				id = "native_parity_weaker_hud::"
					.. "native parity weaker hud-world"
					.. "::"
					.. `apps-221 {input} uses the HUD actions and recovers focus after a notification`,
				run = function()
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
						Verify.expect(`{input} {id} item present={item ~= nil}`):toBe(`{input} {id} item present=true`)
						if directional then
							Verify.expect(w.gui.SelectedObject ~= nil and w.gui.SelectedObject:IsDescendantOf(w.target))
								:toBe(true)
							Verify.expect((w.gui.SelectedObject:IsDescendantOf(trigger.Parent))):toBe(false)
						else
							Verify.expect(w.gui.SelectedObject):toBe(nil)
						end
						item.Activated.fire(event, 1)
						Verify.expect((find(w.target, id))):toBe(nil)
						Verify.expect(w.gui.SelectedObject):toBe(if directional then trigger else nil)
					end
					choose("damage")
					Verify.expect(w.built.report().health < 0.84):toBe(true)
					choose("heal")
					Verify.expect(w.built.report().health):toBe(1)
					choose("notice")
					local notice = find(w.root, "Notice")
					Verify.expect(notice.Visible):toBe(true)
					Verify.expect(notice:FindFirstChildWhichIsA("TextButton").Text):toBe("Supplies delivered")
					Verify.expect(notice.LayoutOrder < find(w.root, "HudBody").LayoutOrder):toBe(true)
					Verify.expect(w.gui.SelectedObject):toBe(if directional then trigger else nil)
					trigger.Activated.fire(event, 1)
					Verify.expect(find(w.target, "damage") ~= nil):toBe(true)
					local back = find(w.target, "ModalBack")
					local keys = {}
					for _, binding in back:GetChildren() do
						keys[tostring(binding.KeyCode)] = true
					end
					Verify.expect(keys["Enum.KeyCode.ButtonB"]):toBe(true)
					Verify.expect(keys["Enum.KeyCode.Escape"]):toBe(true)
					back.Pressed.fire()
					Verify.expect((find(w.target, "damage"))):toBe(nil)
					Verify.expect(w.gui.SelectedObject):toBe(if directional then trigger else nil)
					Verify.expect(notice.Visible):toBe(true)
					notice:FindFirstChildWhichIsA("TextButton").Activated.fire(event, 1)
					Verify.expect(notice.Visible):toBe(false)
					w.stop()
				end,
			})
		end

		verifyHarness:case("themes-P1-11 circular readouts center only while native text bounds fit inside the ring", {
			id = "native_parity_weaker_hud::native parity weaker hud-world::themes-P1-11 circular readouts center only while native text bounds fit inside the ring",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local UI = Facet.controls(runtime, { types = engine.types })
				local stop, meter: any = runtime.mount(function()
					return UI.ProgressView({
						value = 0.75,
						presentation = "circular" :: "circular",
						diameter = 120,
						showValue = true,
					})
				end, engine.new("Folder"))
				local readout, gauge = find(meter, "Value"), find(meter, "Gauge")
				local V2, D2, E = engine.types.Vector2, engine.types.UDim2, engine.types.Enum
				Verify.expect(readout.TextXAlignment):toBe(E.TextXAlignment.Center)
				Verify.expect(readout.TextWrapped):toBe(false)
				Verify.expect(readout.AutomaticSize):toBe(E.AutomaticSize.XY)
				for _, bounds in { V2.new(38, 20), V2.new(72, 72) } do
					readout.TextBounds = bounds
					Verify.expect(readout.AnchorPoint):toBe(V2.new(0.5, 0.5))
					Verify.expect(readout.Position):toBe(D2.new(0.5, 0, 0, 60))
					Verify.expect(gauge.Size):toBe(D2.fromOffset(120, 120))
					local left = 60 - bounds.X / 2
					Verify.expect(left >= 0 and left + bounds.X <= 120):toBe(true)
				end
				readout.TextBounds = V2.new(73, 20)
				Verify.expect(readout.AnchorPoint):toBe(V2.new(0.5, 0))
				Verify.expect(readout.Position):toBe(D2.new(0.5, 0, 0, 128))
				Verify.expect(gauge.Size):toBe(D2.fromOffset(120, 148))
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("themes-P1-14 a gauge keeps a long value whole and visible as native text grows", {
			id = "native_parity_weaker_hud::native parity weaker hud-world::themes-P1-14 a gauge keeps a long value whole and visible as native text grows",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local UI = Facet.controls(runtime, { types = engine.types })
				local stop, meter: any = runtime.mount(function()
					return UI.ProgressView({
						value = 1,
						presentation = "circular" :: "circular",
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
					Verify.expect(readout.Text):toBe("10000 / 10000")
					Verify.expect(readout.Visible):toBe(true)
					Verify.expect(readout.TextWrapped):toBe(false)
					Verify.expect(readout.TextTruncate):toBe(E.TextTruncate.None)
					Verify.expect(readout.TextXAlignment):toBe(E.TextXAlignment.Center)
					Verify.expect(readout.AnchorPoint):toBe(V2.new(0.5, 0))
					Verify.expect(readout.Position.Y.Offset):toBe(88)
					Verify.expect(gauge.Size.X.Offset):toBe(bounds.X)
					Verify.expect(gauge.Size.X.Offset > 80):toBe(true)
					Verify.expect(gauge.Size.Y.Offset):toBe(80 + 8 + bounds.Y)
					Verify.expect(gauge.ClipsDescendants):toBe(false)
				end
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case(
			"themes-P1-102 Stage forwards ambient, light color and light direction and keeps them reactive",
			{
				id = "native_parity_weaker_hud::native parity weaker hud-world::themes-P1-102 Stage forwards ambient, light color and light direction and keeps them reactive",
				run = function()
					local engine = engineLib.new()
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local UI = Facet.controls(runtime, { types = engine.types })
					local Color3, Vector3 = engine.types.Color3, engine.types.Vector3
					local light = Compose.cell(Color3.new(1, 0.95, 0.9))
					local stop, stage: any = runtime.mount(function()
						return UI.Stage({
							Ambient = Color3.new(0.2, 0.2, 0.25),
							LightColor = light,
							LightDirection = Vector3.new(-1, -1, 0),
						})
					end, engine.new("Folder"))
					Verify.expect(stage.ClassName):toBe("ViewportFrame")
					Verify.expect(stage.Ambient):toBe(Color3.new(0.2, 0.2, 0.25))
					Verify.expect(stage.LightColor):toBe(Color3.new(1, 0.95, 0.9))
					Verify.expect(stage.LightDirection):toBe(Vector3.new(-1, -1, 0))
					light:set(Color3.new(0.5, 0.6, 0.7))
					Verify.expect(stage.LightColor):toBe(Color3.new(0.5, 0.6, 0.7))
					stop()
					local defaults = engine.new("ViewportFrame")
					local stopPartial, partial: any = runtime.mount(function()
						return UI.Stage({ Ambient = Color3.new(0, 0, 0) })
					end, engine.new("Folder"))
					Verify.expect(partial.Ambient):toBe(Color3.new(0, 0, 0))
					Verify.expect(partial.LightColor):toBe(defaults.LightColor)
					Verify.expect(partial.LightDirection):toBe(defaults.LightDirection)
					stopPartial()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case("apps2-130 the terminal surface declares its walk-up contract and a 4:3 console canvas", {
			id = "native_parity_weaker_hud::native parity weaker hud-world::apps2-130 the terminal surface declares its walk-up contract and a 4:3 console canvas",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local gui = engine.new("GuiService")
				local sent: { { kind: string, payload: any } } = {}
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
					Host = (runtime.constructors :: unknown) :: RobloxHost,
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
				Verify.expect(terminal.CANVAS.w):toBe(640)
				Verify.expect(terminal.CANVAS.h):toBe(480)
				Verify.expect(terminal.CANVAS.w / terminal.CANVAS.h):toBeCloseTo(8 / 6, 1e-4)
				local surface = inputTarget:FindFirstChild("OutpostSurface")
				Verify.expect(surface.CanvasSize):toBe(engine.types.Vector2.new(640, 480))
				Verify.expect(surface.SizingMode):toBe(engine.types.Enum.SurfaceGuiSizingMode.FixedSize)
				Verify.expect(surface.Adornee):toBe(console)
				local context = inputTarget:FindFirstChild("OutpostInput")
				local leave = context:FindFirstChild("LeaveConsole")
				local keys = {}
				for _, binding in leave:GetChildren() do
					keys[tostring(binding.KeyCode)] = true
				end
				Verify.expect(keys["Enum.KeyCode.Escape"]):toBe(true)
				Verify.expect(keys["Enum.KeyCode.ButtonB"]):toBe(true)
				Verify.expect(context.Sink):toBe(true)
				Verify.expect(surface.Active):toBe(false)
				Verify.expect(context.Enabled):toBe(false)
				Verify.expect(gui.SelectedObject):toBe(outside)
				remote.OnClientEvent.fire({
					kind = "session" :: "session",
					token = "s1",
					revision = 1,
					allocation = rules.START,
				})
				Verify.expect(surface.Active):toBe(true)
				Verify.expect(context.Enabled):toBe(true)
				local first = gui.SelectedObject
				Verify.expect(first ~= outside and first:IsDescendantOf(surface)):toBe(true)
				local expected = nil
				for _, node in surface:GetDescendants() do
					if node:IsA("GuiObject") and node.Selectable and not node:IsA("ScrollingFrame") then
						expected = node
						break
					end
				end
				Verify.expect(first):toBe(expected)
				Verify.expect(first):toBe(find(surface, "doorStep"))
				leave.Pressed.fire()
				Verify.expect(built.report().lastExit):toBe("cancel")
				Verify.expect(built.report().terminal.phase):toBe("exited")
				Verify.expect((surface.isDestroyed())):toBe(false)
				Verify.expect(surface.Parent):toBe(inputTarget)
				Verify.expect(surface.Active):toBe(false)
				Verify.expect(context.Enabled):toBe(false)
				Verify.expect(gui.SelectedObject):toBe(outside)
				Verify.expect(sent[#sent].kind):toBe("release")
				remote.OnClientEvent.fire({
					kind = "session" :: "session",
					token = "s2",
					revision = 2,
					allocation = rules.START,
				})
				Verify.expect(surface.Active):toBe(true)
				Verify.expect(built.report().terminal.phase):toBe("engaged")
				stop()
				Verify.expect((surface.isDestroyed())):toBe(true)
				runtime:dispose()
			end,
		})
	end)

	local function lab(noTransport: boolean?)
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local sent: { { kind: string, payload: any } } = {}
		local ctx = {
			Facet = Facet,
			Compose = Compose,
			runtime = runtime,
			Host = (runtime.constructors :: unknown) :: RobloxHost,
			UI = Facet.controls(runtime, { types = engine.types }),
			types = engine.types,
		}
		local built
		local stop, root: any = runtime.mount(function()
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
		return {
			UserInputType = engine.types.Enum.UserInputType.Touch,
			KeyCode = engine.types.Enum.KeyCode:FromValue(0),
		}
	end

	verifyHarness:suite("native parity weaker replication-server", function()
		verifyHarness:case("apps2-127 an illegal draft is refused on the terminal and never reaches the wire", {
			id = "native_parity_weaker_hud::native parity weaker replication-server::apps2-127 an illegal draft is refused on the terminal and never reaches the wire",
			run = function()
				local f = lab()
				f.steps.engage(rules.START)
				f.steps.setValue("door", 3)
				f.steps.setValue("beacon", 2)
				f.steps.setValue("workshop", 4)
				local state = f.steps.snapshot()
				Verify.expect(state.canApply):toBe(false)
				Verify.expect(state.message):toBe("The generator makes 6 units and that allocation asks for 9.")
				Verify.expect((f.shown())):toBe("The generator makes 6 units and that allocation asks for 9.")
				local result = f.steps.apply()
				Verify.expect(result.sent):toBe(false)
				Verify.expect(result.reason):toBe("budget")
				Verify.expect(#f.sent):toBe(0)
				Verify.expect(f.steps.snapshot().counters.refusedLocally):toBe(1)
				f.stop()
			end,
		})

		verifyHarness:case(
			"apps2-127 apply sends one intent with the draft, pending is not success and a second apply is refused",
			{
				id = "native_parity_weaker_hud::native parity weaker replication-server::apps2-127 apply sends one intent with the draft, pending is not success and a second apply is refused",
				run = function()
					local f = lab()
					solve(f)
					local result = f.steps.apply()
					Verify.expect(result.sent):toBe(true)
					Verify.expect(#f.sent):toBe(1)
					Verify.expect(f.sent[1].payload.kind):toBe("set")
					Verify.expect(f.sent[1].payload.allocation.door):toBe(2)
					Verify.expect(f.sent[1].payload.allocation.beacon):toBe(1)
					Verify.expect(f.sent[1].payload.allocation.workshop):toBe(2)
					local state = f.steps.snapshot()
					Verify.expect(state.status):toBe("pending")
					Verify.expect(state.message):toBe("Sending to the outpost…")
					Verify.expect((f.shown())):toBe("Sending to the outpost…")
					Verify.expect(state.outpost.door):toBe(3)
					Verify.expect(state.complete):toBe(false)
					local second = f.steps.apply()
					Verify.expect(second.sent):toBe(false)
					Verify.expect(second.reason):toBe("pending")
					Verify.expect(#f.sent):toBe(1)
					f.stop()
				end,
			}
		)

		verifyHarness:case("apps2-127 a confirmed verdict moves the outpost and the screen says what changed", {
			id = "native_parity_weaker_hud::native parity weaker replication-server::apps2-127 a confirmed verdict moves the outpost and the screen says what changed",
			run = function()
				local f = lab()
				solve(f)
				f.steps.apply()
				Verify.expect((answer(f))):toBe(true)
				local state = f.steps.snapshot()
				Verify.expect(state.status):toBe("confirmed")
				Verify.expect(state.outpost.beacon):toBe(1)
				Verify.expect(state.revision):toBe(99)
				Verify.expect(state.complete):toBe(true)
				Verify.expect(state.message):toBe("All three are running, with 1 unit to spare.")
				Verify.expect((f.shown())):toBe("All three are running, with 1 unit to spare.")
				Verify.expect(state.counters.applied):toBe(1)
				f.stop()
			end,
		})

		verifyHarness:case("apps2-127 a refusal is shown and the draft survives it", {
			id = "native_parity_weaker_hud::native parity weaker replication-server::apps2-127 a refusal is shown and the draft survives it",
			run = function()
				local f = lab()
				solve(f)
				f.steps.apply()
				answer(f, { distance = 22 })
				local state = f.steps.snapshot()
				Verify.expect(state.status):toBe("rejected")
				Verify.expect(state.message):toBe("You are 22 studs from the console. Step within 10 to use it.")
				Verify.expect((f.shown())):toBe("You are 22 studs from the console. Step within 10 to use it.")
				Verify.expect(state.outpost.door):toBe(3)
				Verify.expect(state.draft.door):toBe(2)
				Verify.expect(state.draft.beacon):toBe(1)
				Verify.expect(state.draft.workshop):toBe(2)
				local retry = f.steps.apply()
				Verify.expect(retry.sent):toBe(true)
				Verify.expect(f.sent[#f.sent].payload.allocation.door):toBe(2)
				f.stop()
			end,
		})

		verifyHarness:case("apps2-127 every server refusal reaches the screen as its own sentence", {
			id = "native_parity_weaker_hud::native parity weaker replication-server::apps2-127 every server refusal reaches the screen as its own sentence",
			run = function()
				local seen = {}
				for
					_,
					case: {
					situation: { holderId: string?, token: string?, sinceLast: number?, distance: number? },
					message: typeof(rules.refusal("holder"))
						| typeof(rules.refusal("session"))
						| typeof(rules.refusal("rate"))
						| typeof(rules.refusal("distance", { distance = 40, range = 10 })),
				}
				in
					{
						{ situation = { holderId = "someone-else" }, message = rules.refusal("holder") },
						{ situation = { token = "stale" }, message = rules.refusal("session") },
						{ situation = { sinceLast = 0.01 }, message = rules.refusal("rate") },
						{
							situation = { distance = 40 },
							message = rules.refusal("distance", { distance = 40, range = 10 }),
						},
					} :: {
						{
							situation: { holderId: string?, token: string?, sinceLast: number?, distance: number? },
							message: typeof(rules.refusal("holder"))
								| typeof(rules.refusal("session"))
								| typeof(rules.refusal("rate"))
								| typeof(rules.refusal("distance", { distance = 40, range = 10 })),
						}
					}
				do
					local f = lab()
					f.steps.engage(rules.START)
					f.steps.setValue("door", 2)
					f.steps.apply()
					answer(f, case.situation)
					Verify.expect(f.steps.snapshot().message):toBe(case.message)
					Verify.expect((f.shown())):toBe(case.message)
					Verify.expect(f.steps.snapshot().status):toBe("rejected")
					Verify.expect(seen[case.message]):toBe(nil)
					seen[case.message] = true
					f.stop()
				end
			end,
		})

		verifyHarness:case("apps2-127 reset is a server intent and the verdict moves the outpost back", {
			id = "native_parity_weaker_hud::native parity weaker replication-server::apps2-127 reset is a server intent and the verdict moves the outpost back",
			run = function()
				local f = lab()
				f.steps.engage({ door = 2, beacon = 1, workshop = 2 })
				local result = f.steps.reset()
				Verify.expect(result.sent):toBe(true)
				Verify.expect(#f.sent):toBe(1)
				Verify.expect(f.sent[1].payload.allocation.door):toBe(rules.START.door)
				Verify.expect(f.sent[1].payload.allocation.beacon):toBe(0)
				Verify.expect(f.steps.snapshot().draft.door):toBe(rules.START.door)
				Verify.expect(f.steps.snapshot().outpost.workshop):toBe(2)
				answer(f)
				Verify.expect(f.steps.snapshot().outpost.workshop):toBe(0)
				Verify.expect(f.steps.snapshot().outpost.door):toBe(rules.START.door)
				f.stop()
			end,
		})

		verifyHarness:case("apps2-127 an allocation another player applied lands without touching this draft", {
			id = "native_parity_weaker_hud::native parity weaker replication-server::apps2-127 an allocation another player applied lands without touching this draft",
			run = function()
				local f = lab()
				f.steps.engage(rules.START)
				f.steps.setValue("workshop", 3)
				Verify.expect((f.steps.ingest(12, { door = 2, beacon = 1, workshop = 2 }))):toBe(true)
				local state = f.steps.snapshot()
				Verify.expect(state.outpost.workshop):toBe(2)
				Verify.expect(state.draft.workshop):toBe(3)
				Verify.expect(find(f.root, "Confirmed").Text):toBe("Outpost: 3 of 3 consumers running.")
				Verify.expect((f.steps.ingest(3, { door = 0, beacon = 0, workshop = 0 }))):toBe(false)
				Verify.expect(f.steps.snapshot().outpost.door):toBe(2)
				Verify.expect(f.steps.snapshot().draft.workshop):toBe(3)
				f.stop()
			end,
		})

		verifyHarness:case(
			"apps2-41 settings sync applies optimistically, confirms, and rolls back a rejection by touch alone",
			{
				id = "native_parity_weaker_hud::native parity weaker replication-server::apps2-41 settings sync applies optimistically, confirms, and rolls back a rejection by touch alone",
				run = function()
					local engine = engineLib.new()
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local ctx = {
						Facet = Facet,
						Compose = Compose,
						runtime = runtime,
						Host = (runtime.constructors :: unknown) :: RobloxHost,
						UI = Facet.controls(runtime, { types = engine.types }),
						types = engine.types,
					}
					local built
					local stop, node: any = runtime.mount(function()
						built = settingsSync.build(ctx)
						return built.screen()
					end, engine.new("ScreenGui"))
					local touch = tap(engine)
					local function shown(name: string): string
						return find(node, name).Text
					end
					Verify.expect((shown("Status"))):toBe("idle")
					Verify.expect((shown("Draft"))):toBe("What you see now: music off, volume 10")
					Verify.expect((shown("Confirmed"))):toBe("Server confirmed: music off, volume 10 (revision 1)")
					find(node, "Music").Activated.fire(touch, 1)
					Verify.expect(built.report().draft.music):toBe(true)
					Verify.expect(built.report().status):toBe("pending")
					Verify.expect(built.report().server.music):toBe(false)
					Verify.expect((shown("Status"))):toBe("pending")
					Verify.expect((shown("Draft"))):toBe("What you see now: music on, volume 10")
					Verify.expect((shown("Confirmed"))):toBe("Server confirmed: music off, volume 10 (revision 1)")
					find(node, "Deliver").Activated.fire(touch, 1)
					Verify.expect(built.report().status):toBe("confirmed")
					Verify.expect(built.report().server.music):toBe(true)
					Verify.expect(built.report().server.revision):toBe(2)
					Verify.expect(built.report().draft.music):toBe(true)
					Verify.expect((shown("Status"))):toBe("confirmed")
					Verify.expect((shown("Confirmed"))):toBe("Server confirmed: music on, volume 10 (revision 2)")
					find(node, "Music").Activated.fire(touch, 1)
					Verify.expect(built.report().status):toBe("pending")
					find(node, "Deliver").Activated.fire(touch, 1)
					Verify.expect(built.report().draft.music):toBe(false)
					Verify.expect(built.report().server.music):toBe(false)
					Verify.expect(built.report().status):toBe("confirmed")
					find(node, "Invalid").Activated.fire(touch, 1)
					Verify.expect(built.report().draft.volume):toBe(99)
					Verify.expect(built.report().status):toBe("pending")
					Verify.expect((shown("Draft"))):toBe("What you see now: music off, volume 99")
					find(node, "Deliver").Activated.fire(touch, 1)
					Verify.expect(built.report().status):toBe("rejected")
					Verify.expect(built.report().draft.volume):toBe(10)
					Verify.expect(built.report().server.revision):toBe(3)
					Verify.expect((shown("Status"))):toBe("rejected")
					Verify.expect((shown("Draft"))):toBe("What you see now: music off, volume 10")
					Verify.expect((shown("Confirmed"))):toBe("Server confirmed: music off, volume 10 (revision 3)")
					stop()
					runtime:dispose()
				end,
			}
		)
	end)
end
