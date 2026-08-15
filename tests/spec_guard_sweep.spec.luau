--!strict
-- THE CLOSED-KEY SWEEP (constitution §4; architecture finding ARCH-1).
--
-- §4 has claimed since the stage opened that "an unknown key ... is an immediate
-- error — never a value that silently does nothing", and that the rule "applies
-- to modifier specs and control specs exactly as to UI.* props". A live probe at
-- HEAD proved the claim false for most of the surface: every composite control
-- spec and every service/model opts table accepted junk without a word, so
-- `newSlider{ tapToPositon = false }` and `newResourceProvider(core,
-- { maxConcurent = 8 })` were working code that ignored the option.
--
-- This spec is the mechanical form of the claim. It is deliberately ONE file and
-- one table: a boundary added without a row here is a boundary nobody proved,
-- and the sweep is much easier to extend than thirteen scattered assertions.
--
-- Every row drives the REAL public entry point twice:
--   * with a bogus key, asserting the error NAMES the boundary and the key (an
--     error that says only "unknown key" sends the author hunting), and
--   * with the legal call it was derived from, proving the closed set did not
--     close over something legitimate. That half is the one that matters: a
--     refusal is easy, a refusal that does not break the library is the work.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local fake_target = require("../tests/lib/fake_target")

local BOGUS = "definitelyNotAKey"

local function failure(fn: () -> any): string
	local ok, err = pcall(fn)
	if ok then
		error("expected a refusal, got a successful call", 0)
	end
	return tostring(err)
end

local function contains(haystack: string, needle: string): boolean
	return string.find(haystack, needle, 1, true) ~= nil
end

local function world()
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	return core, env
end

-- one row = one guarded boundary. `legal` builds the arguments that must work;
-- `call(args)` invokes the boundary. The bogus run reuses `legal` and adds the
-- stray key to the table at `at` (default: the last argument).
type Row = {
	name: string, -- the boundary name the error must carry
	kind: string, -- "spec" | "opts"
	-- returns (args, indexOfTheGuardedTable)
	build: () -> ({ any }, number),
	call: (args: { any }) -> (),
}

local ROWS: { Row } = {}

local function row(name: string, kind: string, build: () -> ({ any }, number), call: (args: { any }) -> ())
	table.insert(ROWS, { name = name, kind = kind, build = build, call = call } :: Row)
end

-- ===== composite control specs =============================================

local function controlRow(name: string, buildSpec: (core: any, env: any) -> any)
	row(name, "spec", function()
		local core, env = world()
		return { core, buildSpec(core, env) }, 2
	end, function(args)
		LuauUI[name](LuauUI, args[1], args[2])
	end)
end

controlRow("newChip", function(core)
	return { id = "C", label = "Filter", selected = core:signal(false) }
end)

controlRow("newLabel", function()
	return { id = "L", title = "Lap" }
end)

controlRow("newTable", function(core)
	return {
		id = "T",
		rows = core:signal({ { id = "a", name = "Apex" } }),
		key = function(item: any)
			return item.id
		end,
		columns = {
			{
				id = "name",
				title = "Name",
				width = { type = "fill", weight = 1 },
				cell = function(item: any)
					return LuauUI.UI.Text({ id = "n", text = item.name })
				end,
			},
		},
	}
end)

controlRow("newVirtualList", function(core)
	return {
		id = "V",
		rows = core:signal({ { id = "a" } }),
		key = function(item: any)
			return item.id
		end,
		rowHeight = 32,
		viewportHeight = 200,
		cell = function(item: any)
			return LuauUI.UI.Text({ id = "r", text = tostring(item.id) })
		end,
	}
end)

controlRow("newVirtualGrid", function(core)
	return {
		id = "G",
		items = core:signal({ { id = "a" } }),
		key = function(item: any)
			return item.id
		end,
		columns = 2,
		itemExtent = 32,
		viewportExtent = 200,
		cell = function(item: any)
			return LuauUI.UI.Text({ id = "r", text = tostring(item.id) })
		end,
	}
end)

controlRow("newPopupButton", function(core)
	return {
		id = "P",
		value = core:signal("a"),
		options = { { id = "a", label = "A" }, { id = "b", label = "B" } },
	}
end)

controlRow("newStepper", function(core)
	return { id = "S", label = "Laps", value = core:signal(3), min = 1, max = 9 }
end)

controlRow("newSlider", function(core)
	return { id = "S", label = "Volume", value = core:signal(0.5), min = 0, max = 1 }
end)

controlRow("newRating", function(core)
	return { id = "R", value = core:signal(3) }
end)

controlRow("newProgressView", function(core)
	return { id = "P", label = "Load", value = core:signal(0.5) }
end)

controlRow("newPicker", function(core)
	return {
		id = "P",
		label = "Track",
		options = { { value = "a", label = "A" }, { value = "b", label = "B" } },
		selected = core:signal("a"),
	}
end)

controlRow("newDisclosureGroup", function(core)
	return {
		id = "D",
		label = "Details",
		expanded = core:signal(false),
		content = function()
			return LuauUI.UI.Text({ id = "T", text = "body" })
		end,
	}
end)

controlRow("newTextInput", function(core)
	return { id = "F", value = core:signal("") }
end)

controlRow("newAsyncImage", function(core)
	return {
		id = "I",
		scope = core:scope("img"),
		provider = LuauUI.newResourceProvider(core),
		key = "rbxassetid://1",
	}
end)

-- ===== models and services =================================================

row("valueModel.new", "spec", function()
	return { { min = 0, max = 10, step = 1 } }, 1
end, function(args)
	LuauUI.valueModel.new(args[1])
end)

row("newResourceProvider", "opts", function()
	local core = world()
	return { core, { maxConcurrent = 4, cacheBudget = 16 } }, 2
end, function(args)
	LuauUI.newResourceProvider(args[1], args[2])
end)

row("newResourceProvider opts.retry", "opts", function()
	local core = world()
	return { core, { count = 2, delaySeconds = 1, giveUp = true } }, 2
end, function(args)
	LuauUI.newResourceProvider(args[1], { retry = args[2] })
end)

row("provider.acquire", "opts", function()
	local core = world()
	local provider = LuauUI.newResourceProvider(core)
	return { core, provider, { retry = { count = 1 } } }, 3
end, function(args)
	args[2].acquire(args[1]:scope("acq"), "rbxassetid://1", args[3])
end)

row("provider.preload", "opts", function()
	local core = world()
	return { LuauUI.newResourceProvider(core), { retry = { count = 1 } } }, 2
end, function(args)
	args[1].preload({ "rbxassetid://1" }, args[2])
end)

row("adaptive.conditions", "opts", function()
	local core, env = world()
	return { core, env, { scope = core:scope("cond"), stackAbove = 600 } }, 3
end, function(args)
	LuauUI.adaptive.conditions(args[1], args[2], args[3])
end)

row("inputHint", "opts", function()
	local core, env = world()
	return { core, env, { style = "phrase" } }, 3
end, function(args)
	LuauUI.inputHint(args[1], args[2], nil, args[3])
end)

row("newAutoscroll", "opts", function()
	return { { bandH = 40, dwellS = 0.1, vMin = 100, vMax = 900 } }, 1
end, function(args)
	LuauUI.newAutoscroll(args[1])
end)

row("newDragVelocity", "opts", function()
	return { { windowS = 0.1 } }, 1
end, function(args)
	LuauUI.newDragVelocity(args[1])
end)

row("newDragSession", "opts", function()
	return {
		{
			payload = { kind = "card" },
			source = "/S/A",
			targets = { { id = "/S/B", rect = { x = 0, y = 0, w = 10, h = 10 } } },
		},
	},
		1
end, function(args)
	LuauUI.newDragSession(args[1])
end)

row("newDragSession target", "spec", function()
	return { { id = "/S/B", rect = { x = 0, y = 0, w = 10, h = 10 } } }, 1
end, function(args)
	LuauUI.newDragSession({ payload = 1, source = "/S/A", targets = { args[1] } })
end)

row("newDragRegistry", "opts", function()
	local core = world()
	return {
		{
			core = core,
			rectOf = function()
				return nil
			end,
		},
	}, 1
end, function(args)
	LuauUI.newDragRegistry(args[1])
end)

row("mount", "opts", function()
	local core = world()
	return { core, { scope = core:scope("mount") } }, 2
end, function(args)
	LuauUI.mount(args[1], LuauUI.UI.Screen({ id = "S", children = {} }), args[2])
end)

row("renderer.attach", "opts", function()
	local core, env = world()
	return { core, env, { rootPolicy = "edgeToEdge" } }, 3
end, function(args)
	local root = LuauUI.mount(args[1], LuauUI.UI.Screen({ id = "S", children = {} }))
	LuauUI.renderer.attach(args[1], root, args[2], fake_target.new(), args[3])
end)

row("motion.newClock", "opts", function()
	local core = world()
	return { core, { now = os.clock } }, 2
end, function(args)
	LuauUI.motion.newClock(args[1], args[2])
end)

row("newPresenter", "opts", function()
	local core, env = world()
	return { core, env, { now = os.clock } }, 3
end, function(args)
	LuauUI.newPresenter(args[1], args[2], fake_target.new(), LuauUI.newActionSystem(args[1]), args[3])
end)

local function presenterRow(name: string, method: string, opts: any)
	row(name, "opts", function()
		local core, env = world()
		local pres = LuauUI.newPresenter(core, env, fake_target.new(), LuauUI.newActionSystem(core))
		-- a FRESH opts table per build: the bogus run mutates the table it is
		-- handed, and a shared literal would leak the stray key into the legal run
		return { pres, table.clone(opts) }, 2
	end, function(args)
		local screen = LuauUI.UI.Screen({
			id = `S{math.random(1, 1e6)}`,
			children = { LuauUI.UI.Text({ id = "T", text = "hi" }) },
		})
		if method == "presentCritical" then
			args[1].presentCritical(function()
				return screen
			end, args[2])
		else
			args[1][method](screen, args[2])
		end
	end)
end

presenterRow("presenter.present", "present", { rootPolicy = "edgeToEdge" })
presenterRow("presenter.presentModal", "presentModal", { scrim = "none", cancelPolicy = "none" })
presenterRow("presenter.presentCritical", "presentCritical", {
	fallbackScreen = function()
		return LuauUI.UI.Screen({ id = "Fallback", children = {} })
	end,
})
presenterRow("presenter.presentToast", "presentToast", { duration = 2, readFloor = 1, position = "top" })

-- ===== the sweep ===========================================================

describe("ARCH-1: every guarded boundary refuses an unknown key", function()
	it("the sweep covers every boundary the constitution's §4 claim names", function()
		-- a coverage floor, so a row deleted to make a failure go away is visible
		local names: { [string]: boolean } = {}
		for _, r in ROWS do
			names[r.name] = true
		end
		for _, required in
			{
				"newChip",
				"newLabel",
				"newTable",
				"newVirtualList",
				"newVirtualGrid",
				"newPopupButton",
				"newStepper",
				"newSlider",
				"newRating",
				"newProgressView",
				"newPicker",
				"newDisclosureGroup",
				"newTextInput",
				"newAsyncImage",
				"valueModel.new",
				"newResourceProvider",
				"adaptive.conditions",
				"inputHint",
				"newAutoscroll",
				"newDragVelocity",
				"newDragSession",
				"newDragRegistry",
				"mount",
				"renderer.attach",
				"motion.newClock",
				"newPresenter",
				"presenter.present",
				"presenter.presentToast",
			}
		do
			expect(`{required}=covered`).toBe(`{required}={if names[required] then "covered" else "MISSING"}`)
		end
		expect(#ROWS >= 30).toBe(true)
	end)

	for _, r in ROWS do
		it(`{r.name} refuses '{BOGUS}' and names itself`, function()
			local args, at = r.build()
			args[at][BOGUS] = 1
			local err = failure(function()
				r.call(args)
			end)
			expect(contains(err, `LuauUI {r.name}:`)).toBe(true)
			expect(contains(err, `unknown {r.kind} key '{BOGUS}'`)).toBe(true)
			-- the legal set is in the message, because a closed set the author
			-- cannot read is a wall with no door
			expect(contains(err, "Known: ")).toBe(true)
		end)

		it(`{r.name} still accepts its legal call`, function()
			local args = r.build()
			r.call(args) -- must not throw
		end)
	end

	it("a near-miss key gets a did-you-mean", function()
		local core = world()
		local err = failure(function()
			LuauUI.valueModel.new({ min = 0, max = 1, stepp = 1 })
		end)
		expect(contains(err, "Did you mean 'step'?")).toBe(true)
		-- ...and a key nothing resembles does not invent one
		local far = failure(function()
			LuauUI.newAutoscroll({ zzzzzzzzzz = 1 })
		end)
		expect(contains(far, "Did you mean")).toBe(false)
		expect(core ~= nil).toBe(true)
	end)

	it("nil and empty tables stay legal — the guard is a closed set, not a schema", function()
		local core = world()
		expect(LuauUI.newAutoscroll() ~= nil).toBe(true)
		expect(LuauUI.newAutoscroll({}) ~= nil).toBe(true)
		expect(LuauUI.newResourceProvider(core, {}) ~= nil).toBe(true)
		expect(LuauUI.motion.newClock(core, nil) ~= nil).toBe(true)
	end)

	it("a NON-STRING key is the same authoring mistake and is refused too", function()
		local err = failure(function()
			LuauUI.valueModel.new({ min = 0, max = 1, [1] = "positional" })
		end)
		expect(contains(err, "unknown spec key '1'")).toBe(true)
	end)
end)
