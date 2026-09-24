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

t.describe("Toggle switch paint", function()
	-- Owner report 2026-09-22 (bugs/toggle.png): the row's switch wore its own
	-- control plate, darker than the selected row at rest and equal to the row's
	-- hover fill, so the highlight read inverted. A switch paints no plate.
	t.it("a switch, bare or in a settings row, wears no surface plate", function()
		local core = harness.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 600, h = 400 })
		local value = Compose.cell(true)
		local bare = harness.Controls.Toggle(core, { id = "Bare", label = "Bare", value = value })
		local row = harness.Controls.Toggle(core, {
			id = "Row",
			label = "Driving assistance",
			value = value,
			row = { description = "Keep the car stable", icon = "settings" },
		})
		local adapter = fakeTarget.new()
		local pres = harness.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		pres.present(harness.UI.Screen({ id = "S", children = { bare.blueprint, row.blueprint } }))
		pres.refresh()
		local seen = {}
		for _, path in adapter.paths() do
			if adapter.node(path).class == "Toggle" then
				local plate = "none"
				for _, tag in adapter.tagsOf(path) do
					if string.sub(tag, 1, 14) == "facet-surface-" then
						plate = tag
					end
				end
				-- ...and no package plate either: a skinned theme must not frame it
				local slot = require("../src/tokens/chrome_slots").classify({ class = "Toggle" })
				if slot ~= nil then
					plate = `slot {slot}`
				end
				table.insert(seen, `{string.match(path, "^/S/(%a+)")}={plate}`)
			end
		end
		table.sort(seen)
		t.expect(table.concat(seen, " ")).toBe("Bare=none Row=none")
	end)

	-- under Fantasy Ornate the Toggle row wore the `selection`
	-- frame, which carves 6 px less than `control`, so its icon and label sat
	-- left of every Button and Slider row on the same page
	t.it("a toggle row starts its content where a button row does, in every package", function()
		local snapshot = require("../src/themes/snapshot")
		for _, name in { "neutral", "pixel_quest", "fantasy_ornate" } do
			local metrics = if name == "neutral"
				then snapshot.neutral()
				else snapshot.resolve(require("../examples/themes/" .. name).build(Facet.themes), nil, {})
			local w = world.new({ themeMetrics = metrics, viewport = { x = 0, y = 0, w = 700, h = 600 } })
			w.present(function()
				return w.UI.Screen("S")({
					w.UI.Button("B")({ label = "Manage", row = { icon = "settings" } }),
					w.UI.Toggle("T")({ label = "Assist", value = Compose.cell(true), row = { icon = "settings" } }),
				})
			end)
			local xs = {}
			for _, path in w.adapter.paths() do
				if string.sub(path, -5) == "/Icon" then
					xs[string.match(path, "^/S/(%a)")] = w.adapter.node(path).rect.x
				end
			end
			t.expect(`{name} {xs.T == xs.B}`).toBe(`{name} true`)
			w.close()
		end
	end)
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
	t.it("keeps a theme-owned checkbox outline in off, on, mixed and disabled states", function()
		local sheet = require("../src/tokens/sheet_model")
		local packages = { require("../src/themes/snapshot").neutralPackage() }
		for _, name in { "pixel_quest", "fantasy_ornate" } do
			table.insert(packages, (require("../examples/themes/" .. name).build(Facet.themes)))
		end
		for _, side in { "leading", "trailing" } do
			local w = world.new()
			local value, mixed, enabled = Compose.cell(false), Compose.cell(false), Compose.cell(true)
			w.present(function()
				return w.UI.Screen("S")({
					w.UI.Toggle("T")({
						label = "Music",
						value = value,
						mixed = mixed,
						enabled = enabled,
						presentation = "checkbox",
						indicatorPosition = side,
						row = { description = "Race music" },
					}),
				})
			end)
			local mark = togglePart(w, "/Indicator")
			for _, pkg in packages do
				local metrics = Facet.themes.resolve(pkg)
				w.env:set("themeMetrics", metrics)
				w.settle()
				local models = {
					sheet.buildPackage(pkg),
					sheet.build({
						themes = {
							{ name = "Dark", style = require("../src/tokens/default_style") },
							{ name = "Light", style = require("../src/tokens/default_light_style") },
						},
					}),
				}
				for _, state in
					{ { false, false, true }, { true, false, true }, { false, true, true }, { false, false, false } }
				do
					value:set(state[1])
					mixed:set(state[2])
					enabled:set(state[3])
					w.settle()
					t.expect(mark.props.surface).toBe("chip")
					local tags = sheet.classifyTags({ surface = mark.props.surface })
					t.expect(tags["facet-surface-chip"]).toBe(true)
					for _, model in models do
						local outline
						for _, rule in model.rules do
							if rule.selector == ".facet-surface-chip::UIStroke" then
								outline = rule.props
							end
						end
						t.expect(outline ~= nil).toBe(true)
						t.expect(outline.Color).toBe("$Hairline")
						t.expect(outline.Thickness.value > 0).toBe(true)
						t.expect(outline.Transparency.value < 1).toBe(true)
						t.expect(outline.ApplyStrokeMode)
							.toEqual({ kind = "enum", enum = "ApplyStrokeMode", item = "Border" })
						for _, theme in model.themes do
							t.expect(theme.tokens.Hairline ~= nil).toBe(true)
							t.expect(theme.tokens.Hairline).never().toEqual(theme.tokens.Control)
						end
					end
					local _, check = togglePart(w, "/Check")
					local _, dash = togglePart(w, "/Mixed")
					t.expect(w.adapter.visibleOf(check)).toBe(state[1] and not state[2])
					t.expect(w.adapter.visibleOf(dash)).toBe(state[2])
					if not state[3] then
						w.adapter.tap("/S/T")
						t.expect(value:peek()).toBe(false)
					else
						t.expect(#w.handle.focusOrder().traversal).toBe(1)
					end
				end
			end
			w.close()
			t.expect(w.adapter.liveCount()).toBe(0)
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

t.describe("the switch's label column", function()
	local source = require("@lune/fs").readFile("src/client/screen_paint.luau")
	local body = require("./lib/adapter_source").bodyOf(source, "local function toggleLabelBox(")
	local factory = require("@lune/luau").load([[return function(snapshot, themeSnapshot, UDim2)
		local style = { space = { xs = 8, m = 16 } }
	]] .. body .. "\nreturn toggleLabelBox end")()
	local themeSnapshot = require("../src/themes/snapshot")
	local UDim2 = {
		fromOffset = function(x: number, y: number)
			return { x = x, y = y, kind = "offset" }
		end,
		new = function(sx: number, ox: number, sy: number, oy: number)
			return { sx = sx, ox = ox, sy = sy, oy = oy, kind = "udim2" }
		end,
	}

	t.it("a leaf with no room for a label gets a ZERO column, never a negative one", function()
		local snap = Facet.themes.neutral()
		local box = factory(function()
			return snap
		end, themeSnapshot, UDim2)
		local pad = themeSnapshot.toggleRowPadding(snap)
		local reserved = pad.left + pad.right
		local markWidth = snap.controls.toggle.markWidth
		-- the fixture is the real defect's arithmetic: the reservation is WIDER
		-- than the box the adapter paints a display-only switch into
		t.expect(`reserved {reserved} > markWidth {markWidth}: {reserved > markWidth}`)
			.toBe(`reserved {reserved} > markWidth {markWidth}: true`)
		local pos, size = box({ windowRect = { x = 0, y = 0, w = markWidth, h = 24 } })
		t.expect(`squeezed: {size.sx},{size.ox} at {pos.x}`).toBe("squeezed: 0,0 at 0")
		-- ...and unsqueezed, the column is exactly what it always was
		local widePos, wideSize = box({ windowRect = { x = 0, y = 0, w = 320, h = 24 } })
		t.expect(`roomy: {wideSize.sx},{wideSize.ox} at {widePos.x}`).toBe(`roomy: 1,{-reserved} at {pad.left}`)
		-- a handle with no rect yet keeps the shipped answer, so create-time is
		-- byte-identical until the first rect arrives
		local _, bareSize = box({})
		t.expect(`no rect: {bareSize.sx},{bareSize.ox}`).toBe(`no rect: 1,{-reserved}`)
	end)

	t.it("the adapter re-takes it when the rect moves, and only then", function()
		local live = require("./lib/adapter_source").live()
		local setRect = require("./lib/adapter_source").bodyOf(live, "function adapter.setRect(")
		t.expect(string.find(setRect, "handle.labelBoxWidth ~= rect.w", 1, true) ~= nil).toBe(true)
		t.expect(string.find(setRect, "applyToggleLabelBox(handle)", 1, true) ~= nil).toBe(true)
		-- ...and both writers take the handle, or the clamp is unreachable
		local apply = require("./lib/adapter_source").bodyOf(source, "local function applyToggleLabelBox(")
		t.expect(string.find(apply, "toggleLabelBox(handle)", 1, true) ~= nil).toBe(true)
		local build = require("./lib/adapter_source").bodyOf(source, "local function buildToggleVisual(")
		t.expect(string.find(build, "toggleLabelBox(handle)", 1, true) ~= nil).toBe(true)
	end)
end)

t.describe("Toggle bound width", function()
	t.it("wraps content-sized labels and follows live width including rejected row widths", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 420, h = 640 } })
		local UI = w.UI
		local width = Compose.cell(UI.hug())
		w.present(function()
			local children = {}
			for _, label in { "Rain", "Dust", "Night vision", "Mirror" } do
				table.insert(
					children,
					UI.Toggle(label)({
						label = label,
						presentation = "checkbox",
						width = width,
						value = Compose.cell(false),
					})
				)
			end
			return UI.Screen("S")({
				UI.HStack("Wrap")({ wrap = true, gap = "s", width = UI.fill(), table.unpack(children) }),
			})
		end)
		local row = w.controller.rectOf("/S/Wrap")
		local tops = {}
		for _, label in { "Rain", "Dust", "Night vision", "Mirror" } do
			local r = w.controller.rectOf("/S/Wrap/" .. label)
			t.expect(r.w < row.w).toBe(true)
			tops[r.y] = true
		end
		t.expect(w.controller.rectOf("/S/Wrap/Night vision").w > w.controller.rectOf("/S/Wrap/Rain").w).toBe(true)
		local lines = 0
		for _ in tops do
			lines += 1
		end
		t.expect(lines > 1).toBe(true)
		width:set(UI.fill())
		w.settle()
		t.expect(w.controller.rectOf("/S/Wrap/Rain").w).toBe(row.w)
		width:set({ type = "minMax", min = 60 })
		w.settle()
		t.expect(w.controller.rectOf("/S/Wrap/Rain").w < row.w).toBe(true)
		width:set(UI.hug())
		w.settle()
		t.expect(w.controller.rectOf("/S/Wrap/Rain").w < row.w).toBe(true)
		w.app.dispose()
		for _, presentation in { "switch", "button" } do
			local r = world.new()
			local rw = Compose.cell({ type = "fixed", px = 240 })
			r.present(function()
				return r.UI.Screen("S")({
					r.UI.Toggle("T")({
						label = "Rumble",
						value = Compose.cell(false),
						width = rw,
						presentation = presentation,
						row = if presentation == "switch" then { description = "Feedback" } else nil,
					}),
				})
			end)
			t.expect(r.controller.rectOf("/S/T").w).toBe(240)
			rw:set({ type = "hug" })
			r.settle()
			t.expect(r.controller.rectOf("/S/T").w).toBe(240)
			t.expect(string.find(tostring(r.core.lastError()), "content-sized width", 1, true) ~= nil).toBe(true)
			rw:set({ type = "fixed", px = 280 })
			r.settle()
			t.expect(r.controller.rectOf("/S/T").w).toBe(280)
		end
	end)
	t.it("refuses content-sized row/button widths before allocation", function()
		for _, width in { { type = "hug" }, { type = "content" }, { type = "minMax", min = 40 } } do
			for _, presentation in { "switch", "button" } do
				local w = world.new()
				local ok, err = pcall(function()
					w.present(function()
						return w.UI.Screen("S")({
							w.UI.Toggle("T")({
								label = "Rumble",
								value = Compose.cell(false),
								width = width,
								presentation = presentation,
								row = if presentation == "switch" then { description = "Feedback" } else nil,
							}),
						})
					end)
				end)
				t.expect(ok).toBe(false)
				t.expect(string.find(tostring(err), "width", 1, true) ~= nil).toBe(true)
				t.expect(w.adapter.liveCount()).toBe(0)
			end
		end
	end)
end)
