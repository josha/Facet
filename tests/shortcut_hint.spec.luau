--!strict
local t = require("./lib/testkit")
local expect = t.expect
local world = require("./lib/world")
local Facet = require("../src")
local Compose = Facet.Compose
local keyNames = require("../src/input/key_names")
local chromeSlots = require("../src/tokens/chrome_slots")
local tokens = require("../src/tokens/tokens")
local restores = {}
t.afterEach(function()
	for i = #restores, 1, -1 do
		restores[i]()
	end
	table.clear(restores)
end)
local function ownership()
	local report = Compose.inspect.snapshot()
	local holding = 0
	for _, owner in report.mounts do
		holding += owner.totalHolding
	end
	return { mounts = report.outstandingMounts, holding = holding }
end
local function inspect()
	Compose.inspect.start()
	table.insert(restores, Compose.inspect.stop)
end
local function mount(w, spec, options)
	local record
	local saved = table.clone(spec)
	saved.ref = function(value)
		record = value
	end
	w.present(function()
		return w.UI.Screen("S")({ w.UI.ShortcutHint("Hint")(saved) })
	end, options)
	return record
end
local function caps(w)
	local values = {}
	for _, path in w.adapter.paths() do
		local node = w.adapter.node(path)
		if node.class == "Text" and path:match("/Hint/.*Label$") then
			table.insert(values, node.props.text)
		end
	end
	return values
end
local function state(w)
	local action = w.system.actionNamed("Activate")
	return { revision = w.system.revision:peek(), contexts = w.system.contextCount(), bindings = #action.bindings }
end

t.describe("ShortcutHint public construction", function()
	t.it("letters explicit alternatives and tracks separator and rung without rebuilding", function()
		local w = world.new()
		local separator, rung = Compose.cell("or"), Compose.cell("compact")
		local record = mount(
			w,
			{ keys = { { "Ctrl", "K" }, { "F1" } }, separator = separator, controlSize = rung, over = "media" }
		)
		expect(caps(w)).toEqual({ "Ctrl", "K", "F1" })
		local word = w.adapter.node("/S/Hint/Or2")
		expect(word.props.text).toBe("or")
		expect(word.props.over).toBe("media")
		local cap = w.adapter.node("/S/Hint/Chord1/Key2")
		local small = cap.rect.h
		separator:set("ou")
		rung:set("large")
		w.settle()
		expect(w.adapter.node("/S/Hint/Or2")).toBe(word)
		expect(word.props.text).toBe("ou")
		expect(cap.rect.h > small).toBe(true)
		expect(record.dump().alternatives).toEqual({ { "Ctrl", "K" }, { "F1" } })
		expect(record.dump().separator).toBe("ou")
	end)
	for name, spec in
		{
			missing = {},
			both = { action = "Activate", keys = { { "K" } } },
			emptyAction = { action = "" },
			boundAction = { action = Compose.cell("Activate") },
			emptyKeys = { keys = {} },
			emptyChord = { keys = { {} } },
			badKey = { keys = { { 3 } } },
			emptyKey = { keys = { { "" } } },
			separatorOnAction = { action = "Activate", separator = "or" },
			emptySeparator = { keys = { { "K" } }, separator = Compose.cell("") },
			size = { keys = { { "K" } }, controlSize = "huge" },
			over = { keys = { { "K" } }, over = "photo" },
			unknown = { keys = { { "K" } }, typo = true },
		}
	do
		t.it(`refuses malformed {name} without native leftovers`, function()
			local w = world.new()
			inspect()
			local before = ownership()
			local ok, err = pcall(function()
				mount(w, spec)
			end)
			expect(ok).toBe(false)
			expect(string.find(tostring(err), "Facet ShortcutHint", 1, true) ~= nil).toBe(true)
			expect(w.adapter.liveCount()).toBe(0)
			expect(ownership()).toEqual(before)
		end)
	end
	t.it("owns no binding, context or focus target beyond its surface", function()
		local plain = world.new()
		plain.present(function()
			return plain.UI.Screen("S")({ plain.UI.Text("T")({ text = "x" }) })
		end)
		local w = world.new()
		mount(w, { action = "Activate" })
		expect(state(w)).toEqual(state(plain))
		for _, path in w.adapter.paths() do
			local node = w.adapter.node(path)
			expect(node.props.focusable == true).toBe(false)
			expect(node.props.onActivate).toBeNil()
		end
	end)
	t.it("updates late, replaced and removed bindings within one device class", function()
		local w = world.new()
		local record = mount(w, { action = "Launch" })
		expect(record.dump().visible).toBe(false)
		local context = w.system.createContext({ name = "Game" })
		local action = context.createAction("Launch", "Bool")
		local first = action.bind({ keyCode = "Return" })
		w.settle()
		expect(caps(w)).toEqual({ "Enter" })
		local second = action.bind({ keyCode = "Q", displayName = "Launch" })
		first.remove()
		w.settle()
		expect(caps(w)).toEqual({ "Launch" })
		second.remove()
		w.settle()
		expect(record.dump().visible).toBe(false)
		context.destroy()
		w.close()
		expect(w.adapter.liveCount()).toBe(0)
	end)
	for _, responder in { "active", "passive" } do
		t.it(`names its own {responder} surface before competing chrome`, function()
			local w = world.new()
			local chrome = w.system.createContext({ name = "Chrome", priority = 13500 })
			chrome.createAction("Activate", "Bool").bind({ keyCode = "Backquote" })
			mount(w, { action = "Activate" }, if responder == "passive" then { responder = "passive" } else nil)
			expect(caps(w)).toEqual({ "Enter" })
			expect(w.system.actionNamed("Activate").context.name).toBe("Chrome")
			if responder == "passive" then
				expect(w.handle.context.enabled).toBe(false)
				w.handle.engage()
				w.settle()
				expect(caps(w)).toEqual({ "Enter" })
				w.handle.resign()
				w.settle()
				expect(caps(w)).toEqual({ "Enter" })
			end
		end)
	end
	t.it("changes keyboard, vendor glyph, touch emptiness and back in one build", function()
		table.insert(
			restores,
			keyNames.setPlatform({
				image = function(key)
					return if key == "ButtonA" then "rbxassetid://12" else nil
				end,
			})
		)
		local w = world.new({ capabilities = { keyboard = true, mouse = true, gamepad = true, touch = true } })
		local record = mount(w, { action = "Activate" })
		expect(caps(w)).toEqual({ "Enter" })
		w.env:set("preferredInput", "Gamepad")
		w.settle()
		expect(record.dump().glyph).toBe("rbxassetid://12")
		local glyph = w.adapter.node("/S/Hint/LiveGlyph/then/Chord1/Key1/Glyph")
		expect(glyph.props.image).toBe("rbxassetid://12")
		expect(glyph.tintSpec).toBeNil()
		local before = table.clone(glyph.rect)
		w.env:set("preferredTextOffset", 14)
		w.settle()
		expect(glyph.rect.w).toBe(before.w)
		expect(glyph.rect.h).toBe(before.h)
		w.env:set("preferredInput", "Touch")
		w.settle()
		expect(record.dump().visible).toBe(false)
		expect(caps(w)).toEqual({})
		w.env:set("preferredInput", "KeyboardAndMouse")
		w.settle()
		expect(caps(w)).toEqual({ "Enter" })
	end)
	t.it("repeated mounted branch changes retain neither formulas nor borrowed state", function()
		inspect()
		local w = world.new()
		local show = Compose.cell(true)
		local builds = 0
		w.present(function()
			return w.UI.Screen("S")({
				w.UI.When("Region")({
					condition = show,
					thenView = function()
						builds += 1
						return w.UI.ShortcutHint("Hint")({ action = "Activate" })
					end,
				}),
			})
		end)
		local before = ownership()
		expect(before.holding > 0).toBe(true)
		local bundle = Facet.contribution.read(w.record("Hint").blueprint)
		for _ = 1, 20 do
			bundle.bindActionSystem(w.system, function()
				return w.handle.context
			end)
			w.settle()
		end
		expect(ownership()).toEqual(before)
		expect(w.record("Hint").dump().alternatives).toEqual({ { "Enter" } })
		for _ = 1, 20 do
			show:set(false)
			w.settle()
			show:set(true)
			w.settle()
		end
		expect(builds).toBe(21)
		expect(ownership()).toEqual(before)
		local revision = w.system.revision:peek()
		w.close()
		local game = w.system.createContext({ name = "Still live" })
		expect(w.system.revision:peek() > revision).toBe(true)
		game.destroy()
		show:set(false)
		expect(w.adapter.liveCount()).toBe(0)
	end)
end)

local packages = {
	"classic_desktop",
	"compact_pointer",
	"fantasy_ornate",
	"fantasy_parchment",
	"glossy_mobile",
	"glossy_touch",
	"pixel_quest",
	"scifi_hud",
}
t.describe("ShortcutHint passive cap anatomy", function()
	local function box(metrics, offset)
		local w = world.new({ themeMetrics = metrics, env = { preferredTextOffset = offset } })
		mount(w, { keys = { { "K" } } })
		return w, w.adapter.node("/S/Hint/Chord1/Key1")
	end
	t.it("uses a painted strong leaf with authored corner/stroke and no decoration slot", function()
		local w, cap = box(nil, 0)
		local plate = w.adapter.node("/S/Hint/Chord1/Key1/Plate")
		local label = w.adapter.node("/S/Hint/Chord1/Key1/Label")
		expect(cap.rect.w).toBe(cap.rect.h)
		expect(cap.rect.h < 44).toBe(true)
		expect(cap.decorationHint).toBeNil()
		expect(plate.decorationHint).toBeNil()
		expect(chromeSlots.classify({ class = cap.class, surface = cap.props.surface })).toBeNil()
		expect(chromeSlots.classify({ class = plate.class, surface = plate.props.surface })).toBeNil()
		expect(chromeSlots.classify({ class = plate.class, surface = "badge" })).toBe("badge")
		expect(plate.tintSpec.role).toBe("surfaceStrong")
		expect(plate.paintClaims.BackgroundColor3).toBe(true)
		expect(label.tintSpec.role).toBe("contentStrong")
		expect(label.paintClaims.TextColor3).toBe(true)
		local old = cap.rect.h
		w.env:set("preferredTextOffset", 14)
		w.settle()
		expect(cap.rect.h > old).toBe(true)
	end)
	t.it("the keycap stroke and the gap between caps are theme metrics (Neutral: hairline, xs)", function()
		local snapshot = require("../src/themes/snapshot")
		local function chord(metrics)
			local w = world.new({ themeMetrics = metrics })
			mount(w, { keys = { { "Ctrl", "S" } } })
			local a = w.adapter.node("/S/Hint/Chord1/Key1").rect
			local b = w.adapter.node("/S/Hint/Chord1/Key2").rect
			local stroke = w.adapter.node("/S/Hint/Chord1/Key1/Plate").props.stroke
			return b.x - (a.x + a.w), stroke
		end
		local neutral = snapshot.neutral()
		local gap, stroke = chord(nil)
		expect(gap).toBe(neutral.space.xs)
		expect(stroke ~= nil).toBe(true)
		expect(neutral.controls.shortcutHint.capStroke).toBe(neutral.strokes.hairline)
		local soft = table.clone(neutral)
		soft.controls = table.clone(neutral.controls)
		soft.controls.shortcutHint = { capGap = 2, capStroke = 0 }
		local tight, none = chord(soft)
		expect(tight).toBe(2)
		expect(none).toBeNil()
	end)
	for _, name in packages do
		t.it(`stays a cap at normal and largest text in {name}`, function()
			local pkg = require("../examples/themes/" .. name).build(Facet.themes)
			for _, theme in pkg.style.themes do
				expect(tokens.contrastRatio(theme.colors.contentStrong, theme.colors.surfaceStrong) >= 4.5).toBe(true)
			end
			for _, offset in { 0, 14 } do
				local _, neutral = box(nil, offset)
				local _, cap = box(Facet.themes.resolve(pkg, nil, {}), offset)
				expect(cap.rect.w <= neutral.rect.w * 1.6 and cap.rect.h <= neutral.rect.h * 1.6).toBe(true)
			end
		end)
	end
end)

t.describe("ShortcutHint gallery integration", function()
	local function make()
		local w = world.new({
			viewport = { x = 0, y = 0, w = 1100, h = 900 },
			capabilities = { keyboard = true, mouse = true, gamepad = true, touch = true },
		})
		local built = require("../examples/gallery/scenarios/shortcut_hint").build({
			Facet = Facet,
			UI = w.UI,
			Compose = Compose,
			env = w.env,
			presenter = w.pres,
			actionSystem = w.system,
		})
		expect(built.report().live.text).toBeNil()
		w.present(built.screen)
		return w, built
	end
	t.it("reports mounted class, separator and rung changes with a reactive Label", function()
		local w, built = make()
		expect(built.report().live.text).toBe("Enter")
		expect(built.steps.pad().live.text).toBe("A")
		expect(built.steps.touch().live.text).toBeNil()
		expect(built.steps.keyboard().live.text).toBe("Enter")
		local before = built.steps.compact().capHeight
		expect(built.steps.large().capHeight > before).toBe(true)
		expect(built.steps.localize().separator).toBe("ou")
		expect(built.steps.rename().title).toBe("Lap saved")
		w.close()
		expect(built.report().live.text).toBeNil()
	end)
	t.it("drives same-class live add/remove/rebind and caller-owned link navigation", function()
		local w, built = make()
		expect(built.steps.bind().custom.text).toBe("Enter")
		expect(built.steps.rebind().custom.text).toBe("R")
		expect(built.steps.unbind().custom.text).toBeNil()
		expect(w.adapter.driveActivate("/ShortcutHint/Content/HintRecipe/OpenGuide")).toBe(true)
		w.settle()
		expect(built.report().guideVisible).toBe(true)
	end)
end)
