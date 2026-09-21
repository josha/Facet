--!strict
local harness = require("./lib/harness")
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local fakeTarget = require("./lib/fake_target")
local Compose = require("../src/vendor/compose/core")
local world = require("./lib/world")
t.describe("Toggle presentations", function()
	for _, presentation in { "switch", "checkbox", "button" } do
		for _, input in { "pointer", "touch", "keyboard", "gamepad" } do
			t.it(presentation .. " toggles once through " .. input, function()
				local core = harness.newCore()
				local env = Facet.newEnvironment(core)
				env:set("viewportRect", { x = 0, y = 0, w = 600, h = 400 })
				local value = Compose.cell(false)
				local mixed = if presentation == "checkbox" then Compose.cell(true) else nil
				local enabled = Compose.cell(true)
				local changes = 0
				local control = harness.Controls.Toggle(core, {
					id = "T",
					label = "Receive race updates with detailed results",
					value = value,
					mixed = mixed,
					presentation = presentation,
					enabled = enabled,
					onChange = function(nextValue)
						changes += 1
						value:set(nextValue)
						if mixed then
							mixed:set(false)
						end
					end,
				})
				local adapter = fakeTarget.new()
				local system = Facet.newActionSystem(core)
				local pres = harness.newPresenter(core, env, adapter, system)
				pres.present(harness.UI.Screen({ id = "S", children = { control.blueprint } }))
				pres.refresh()
				if input == "pointer" or input == "touch" then
					adapter.tap("/S/T", { pointer = input })
				else
					system.deviceKey(if input == "keyboard" then "Return" else "ButtonA", true)
					system.deviceKey(if input == "keyboard" then "Return" else "ButtonA", false)
				end
				t.expect(value:peek()).toBe(true)
				t.expect(changes).toBe(1)
				if mixed then
					t.expect(mixed:peek()).toBe(false)
				end
				enabled:set(false)
				pres.refresh()
				adapter.tap("/S/T")
				t.expect(changes).toBe(1)
				t.expect(adapter.node("/S/T").rect.h >= 44).toBe(true)
			end)
		end
	end
end)

t.describe("Toggle model approval", function()
	local worlds = {}
	t.afterEach(function()
		local pending = table.clone(worlds)
		table.clear(worlds)
		for _, w in pending do
			w.app.dispose()
		end
	end)
	for _, presentation in { "switch", "checkbox", "button", "row" } do
		for _, input in { "pointer", "touch", "keyboard", "gamepad" } do
			t.it(presentation .. " waits for the model through " .. input, function()
				local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 400 } })
				table.insert(worlds, w)
				local value, mixed, enabled = Compose.cell(false), Compose.cell(false), Compose.cell(true)
				local requests, observedValue, observedMixed, wanted = 0, nil, nil, nil
				local accept = false
				w.present(function()
					return w.UI.Screen("S")({
						w.UI.Toggle("T")({
							label = "Music",
							value = value,
							enabled = enabled,
							mixed = if presentation == "checkbox" then mixed else nil,
							presentation = if presentation == "row" then "switch" else presentation,
							row = if presentation == "row" then { description = "Background music" } else nil,
							onChange = function(nextValue)
								requests += 1
								observedValue, observedMixed, wanted = value:peek(), mixed:peek(), nextValue
								if accept then
									value:set(nextValue)
									mixed:set(false)
								end
							end,
						}),
					})
				end)
				local function press()
					if input == "pointer" or input == "touch" then
						w.adapter.tap("/S/T", { pointer = input })
					else
						w.press(if input == "keyboard" then "Return" else "ButtonA")
					end
					w.settle()
				end
				local function painted()
					local props = w.adapter.node("/S/T").props
					return if presentation == "switch" then props.value else props.selected
				end
				for _, initial in { false, true } do
					value:set(initial)
					w.settle()
					local before = requests
					accept = false
					press()
					t.expect(requests).toBe(before + 1)
					t.expect(wanted).toBe(not initial)
					t.expect(observedValue).toBe(initial)
					t.expect(value:peek()).toBe(initial)
					t.expect(painted()).toBe(initial)
					accept = true
					press()
					t.expect(requests).toBe(before + 2)
					t.expect(observedValue).toBe(initial)
					t.expect(value:peek()).toBe(not initial)
					t.expect(painted()).toBe(not initial)
				end
				if presentation == "checkbox" then
					value:set(false)
					mixed:set(true)
					w.settle()
					accept = false
					press()
					t.expect(wanted).toBe(true)
					t.expect(observedValue).toBe(false)
					t.expect(observedMixed).toBe(true)
					t.expect(value:peek()).toBe(false)
					t.expect(mixed:peek()).toBe(true)
					t.expect(painted()).toBe(true)
					accept = true
					press()
					t.expect(value:peek()).toBe(true)
					t.expect(mixed:peek()).toBe(false)
				end
				local before = requests
				enabled:set(false)
				w.settle()
				press()
				t.expect(requests).toBe(before)
				t.expect(value:peek()).toBe(painted())
			end)
		end
	end
	for _, source in { "cell", "formula", "function" } do
		t.it("reads the accepted " .. source .. " without a writable proxy", function()
			local w = world.new()
			table.insert(worlds, w)
			local value, mixed = Compose.cell(false), Compose.cell(true)
			local accept = false
			local function binding(cell)
				if source == "formula" then
					return Compose.formula(function(use)
						return use(cell)
					end)
				elseif source == "function" then
					return function(use)
						return use(cell)
					end
				end
				return cell
			end
			w.present(function()
				return w.UI.Screen("S")({
					w.UI.Toggle("T")({
						label = "Select all",
						value = binding(value),
						mixed = binding(mixed),
						presentation = "checkbox",
						onChange = function(wanted)
							if accept then
								value:set(wanted)
								mixed:set(false)
							end
						end,
					}),
				})
			end)
			w.adapter.tap("/S/T")
			w.settle()
			t.expect(value:peek()).toBe(false)
			t.expect(mixed:peek()).toBe(true)
			accept = true
			w.adapter.tap("/S/T")
			w.settle()
			t.expect(value:peek()).toBe(true)
			t.expect(mixed:peek()).toBe(false)
			t.expect(w.adapter.node("/S/T").props.selected).toBe(true)
			value:set(false)
			w.settle()
			t.expect(w.adapter.node("/S/T").props.selected).toBe(false)
		end)
	end
	for _, presentation in { "switch", "checkbox", "button" } do
		t.it(presentation .. " still edits cells without a callback", function()
			local w = world.new()
			table.insert(worlds, w)
			local value, mixed = Compose.cell(false), Compose.cell(true)
			w.present(function()
				return w.UI.Screen("S")({
					w.UI.Toggle("T")({
						label = "Music",
						value = value,
						mixed = if presentation == "checkbox" then mixed else nil,
						presentation = presentation,
					}),
				})
			end)
			w.adapter.tap("/S/T")
			w.settle()
			t.expect(value:peek()).toBe(true)
			if presentation == "checkbox" then
				t.expect(mixed:peek()).toBe(false)
			end
			w.adapter.tap("/S/T")
			w.settle()
			t.expect(value:peek()).toBe(false)
		end)
	end
	for _, field in { "value", "mixed" } do
		t.it("requires a request callback for readonly " .. field, function()
			local w = world.new()
			table.insert(worlds, w)
			t.expect(function()
				w.scoped(function()
					local spec = { value = Compose.cell(false), mixed = Compose.cell(false), presentation = "checkbox" }
					spec[field] = Compose.formula(function()
						return false
					end)
					w.UI.Toggle(spec)
				end)
			end).toThrow("readonly value or mixed requires onChange")
		end)
	end
end)

t.describe("switch value paint", function()
	local source = require("@lune/fs").readFile("src/client/screen_paint.luau")
	local body = require("./lib/adapter_source").bodyOf(source, "local function applyToggleValue(")
	local factory = require("@lune/luau").load([[return function(TweenService, Enum, isReducedMotion)
		local style = { motion = { normal = 0.2 } }
		local TOGGLE_KNOB_ON, TOGGLE_KNOB_OFF = 1, 0
		local function motionInfo() return "smooth" end
		local function overshootInfo() return "overshoot" end
		local function syncTags() end
		local function syncToggleArt() end
		local function stopToggleTweens() end
		local function togglePalette() return {trackOn=1, trackOff=0, knobOn=1, knobOff=0} end
	]] .. body .. "\nreturn applyToggleValue end")()
	for _, initial in { false, true } do
		t.it("paints initial " .. tostring(initial) .. " immediately, then slides without overshoot", function()
			local tweens = {}
			local paint = factory({
				Create = function(_, target, curve, values)
					table.insert(tweens, { target = target, curve = curve, values = values })
					return { Completed = { Once = function() end }, Play = function() end }
				end,
			}, { PlaybackState = { Completed = "Completed" } }, function()
				return false
			end)
			local h = { track = {}, knob = { Position = 0 } }
			-- A theme refresh before the binding must not count as an initial value.
			paint(h, false, true)
			paint(h, initial)
			t.expect(#tweens).toBe(0)
			t.expect(h.knob.Position).toBe(if initial then 1 else 0)
			paint(h, not initial)
			t.expect(#tweens).toBe(2)
			t.expect(tweens[2].curve).toBe("smooth")
			t.expect(tweens[2].values.Position).toBe(if initial then 0 else 1)
		end)
	end
end)

local function togglePart(w, suffix)
	for path, value in w.adapter.liveNodes() do
		if string.sub(path, -#suffix) == suffix then
			return value, path
		end
	end
	error("missing toggle part " .. suffix)
end

t.describe("Toggle setting rows", function()
	t.it("keeps a real switch or checkbox on either requested side", function()
		for _, presentation in { "switch", "checkbox" } do
			for _, side in { "leading", "trailing" } do
				local w = world.new()
				local value = Compose.cell(false)
				w.present(function()
					return w.UI.Screen("S")({
						w.UI.Toggle("T")({
							label = "Music",
							value = value,
							presentation = presentation,
							indicatorPosition = side,
							row = { description = "Play race music" },
						}),
					})
				end)
				local mark, label = togglePart(w, "/Indicator"), togglePart(w, "/Label")
				t.expect(mark.class).toBe(if presentation == "switch" then "Toggle" else "ZStack")
				t.expect(
					if side == "leading"
						then mark.rect.x + mark.rect.w <= label.rect.x
						else label.rect.x + label.rect.w <= mark.rect.x
				).toBe(true)
				value:set(true)
				w.pres.refresh()
				if presentation == "switch" then
					t.expect(mark.props.value).toBe(true)
				else
					local _, path = togglePart(w, "/Check")
					t.expect(w.adapter.visibleOf(path)).toBe(true)
				end
				t.expect(#w.handle.focusOrder().traversal).toBe(1)
				w.close()
			end
		end
	end)
	for _, input in { "pointer", "touch", "keyboard", "gamepad" } do
		t.it("requests model approval from the real row indicator through " .. input, function()
			local w = world.new()
			local value, enabled, requests, accept = Compose.cell(false), Compose.cell(true), 0, false
			w.present(function()
				return w.UI.Screen("S")({
					w.UI.VStack("Col")({
						w.UI.Button("Other")({ label = "Other", onActivate = function() end }),
						w.UI.Toggle("T")({
							label = "Music",
							value = value,
							enabled = enabled,
							row = { description = "Play race music" },
							onChange = function(wanted)
								requests += 1
								if accept then
									value:set(wanted)
								end
							end,
						}),
					}),
				})
			end)
			local mark, path = togglePart(w, "/Indicator")
			t.expect(w.adapter.hitRectOf(path)).toBeNil()
			t.expect(require("../src/paths").nodeAt(w.handle.root.node, path).props.focusable).toBe(false)
			local function press()
				w.pres.focus.focusOn("/S/Col/Other")
				if input == "pointer" or input == "touch" then
					w.adapter.tap(path, { pointer = input })
				else
					w.pres.focus.focusOn("/S/Col/T")
					w.press(if input == "keyboard" then "Return" else "ButtonA")
				end
				w.settle()
			end
			press()
			t.expect(requests).toBe(1)
			t.expect(value:peek()).toBe(false)
			t.expect(mark.props.value).toBe(false)
			t.expect(w.pres.focus.focused:peek()).toBe("/S/Col/T")
			accept = true
			press()
			t.expect(requests).toBe(2)
			t.expect(value:peek()).toBe(true)
			t.expect(mark.props.value).toBe(true)
			enabled:set(false)
			w.settle()
			press()
			t.expect(requests).toBe(2)
		end)
	end
	t.it("reserves both native track insets and no negative label column across four packages", function()
		local snapshot = require("../src/themes/snapshot")
		for _, name in { "neutral", "pixel_quest", "fantasy_ornate", "compact_pointer" } do
			local metrics = if name == "neutral"
				then snapshot.neutral()
				else snapshot.resolve(require("../examples/themes/" .. name).build(Facet.themes), nil, {})
			local track, inset = metrics.controls.toggle.trackWidth, metrics.controls.toggle.trackInset
			for _, side in { "leading", "trailing" } do
				local w = world.new({ themeMetrics = metrics, viewport = { x = 0, y = 0, w = 700, h = 600 } })
				w.present(function()
					return w.UI.Screen("S")({
						w.UI.Toggle("T")({
							label = "Driving assistance",
							value = Compose.cell(true),
							indicatorPosition = side,
							row = { description = "Keep the car stable on rough ground" },
						}),
					})
				end)
				local mark, copy = togglePart(w, "/Indicator").rect, togglePart(w, "/Description").rect
				local trackLeft = mark.x + mark.w - inset - track
				t.expect(trackLeft - mark.x).toBe(inset)
				t.expect(mark.x + mark.w - (trackLeft + track)).toBe(inset)
				t.expect(mark.w - (inset + track + inset)).toBe(0)
				t.expect(mark.x + mark.w <= copy.x or copy.x + copy.w <= mark.x).toBe(true)
				w.close()
			end
		end
	end)
	t.it("keeps live rung height, bare-switch padding and a wrapping hint", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 420, h = 600 } })
		local size = Compose.cell("compact")
		w.present(function()
			return w.UI.Screen("S")({
				w.UI.VStack("Col")({
					w.UI.Toggle("Bare")({ label = "Music", value = Compose.cell(false), controlSize = size }),
					w.UI.Toggle("Hinted")({
						label = "Assistance",
						value = Compose.cell(false),
						presentation = "checkbox",
						hint = "Keeps the car stable on rough terrain and eases you back onto the track after a spin",
						controlSize = size,
					}),
				}),
			})
		end)
		local bare = togglePart(w, "/Bare")
		local padding = require("../src/paths").nodeAt(w.handle.root.node, "/S/Col/Bare+target/Bare").props.padding
		t.expect(padding).toBeNil()
		for _, pair in { { "compact", 36 }, { "large", 56 }, { nil, 44 } } do
			size:set(pair[1])
			w.pres.refresh()
			t.expect(bare.rect.h).toBe(pair[2])
		end
		local target, hint, label =
			togglePart(w, "/Hinted").rect, togglePart(w, "/Hint").rect, togglePart(w, "/Label").rect
		t.expect(hint.y >= label.y + label.h and hint.y + hint.h <= target.y + target.h).toBe(true)
		t.expect(hint.h > label.h).toBe(true)
	end)
	t.it("refuses a hand-built nested switch despite the inert public prop pair", function()
		local w = world.new()
		t.expect(pcall(function()
			w.present(function()
				return w.UI.Screen("S")({
					w.UI.Button("Bad")({
						label = "Bad",
						harness.UI.Toggle({ id = "Inner", label = "", value = false, focusable = false }),
					}),
				})
			end)
		end)).toBe(false)
	end)
end)
