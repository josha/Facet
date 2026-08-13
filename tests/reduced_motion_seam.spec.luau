--!strict
-- REDUCED MOTION REACHES THE TARGET (C1, adversarial review 2026-08-12).
--
-- WHY THIS FILE EXISTS. `screen_target.new` declared `opts.isReducedMotion` and
-- defaulted it to `function() return false end`. Every bespoke tween in that
-- adapter — the press dip, the state-paint fades, the fill crossfade, the toggle
-- slide — asked that closure, and NO production caller anywhere passed one: not
-- the showcase, and not RascalRally's four LuauUI GUIs (`GaragePilotGui`,
-- `LuauUIRacerListGui`, `LuauUISettingsGui`, `LuauUISponsor`), which all pass
-- `nativeStyle` and nothing else. So a player who asked for reduced motion got
-- full motion on every LuauUI surface ever shipped.
--
-- It survived because the only checks that named `isReducedMotion` matched the
-- SOURCE TEXT of screen_target.luau (`native_style_scenario.spec.luau` uses the
-- string as a section delimiter). Source text is true of a closure nobody calls.
-- So this file checks BEHAVIOUR, through the seam a real player's setting travels:
--
--   env `reducedMotion` -> renderer's live observation -> `adapter.setReducedMotion`
--   -> the adapter's own tween decision.
--
-- The instrument is `tests/lib/fake_target.luau`'s press-dip model
-- (`takeMotionOps()`), which records the same fork the live adapter makes and is
-- fed ONLY by the pushed fact — never by a construction-time closure, so the
-- forgotten-opt defect cannot come back in through the instrument.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")

local LuauUI = require("../src") :: any
local target_contract = require("../src/render/target_contract")
local fake_target = require("./lib/fake_target")

local UI = LuauUI.UI

-- ONE BUTTON, PRESENTED THE WAY A CONSUMER PRESENTS ONE — with no motion opts of
-- any kind. That absence is the point: the fix is framework-side, so the fact has
-- to arrive without this world asking for it.
local function world(): any
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 360, h = 640 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local presenter = LuauUI.newPresenter(core, env, adapter, system)
	local pressed = 0
	local handle = presenter.present(UI.Screen({
		id = "S",
		children = {
			UI.Button({
				id = "Go",
				label = "Go",
				onActivate = function()
					pressed += 1
				end,
			}),
		},
	}))
	presenter.refresh()
	return {
		core = core,
		env = env,
		adapter = adapter,
		presenter = presenter,
		handle = handle,
		presses = function()
			return pressed
		end,
	}
end

describe("reduced motion: the fact reaches the target with NO consumer wiring", function()
	it("full motion is the default, and a press plays a tween", function()
		local w = world()
		expect(w.adapter.reducedMotion()).toBe(false)
		w.adapter.takeMotionOps()
		w.adapter.tap("/S/Go")
		local ops = w.adapter.takeMotionOps()
		expect(#ops).toBe(1)
		expect(ops[1].kind).toBe("tween")
		expect(w.presses()).toBe(1)
		expect(w.core:lastError()).toBeNil()
	end)

	-- THE CASE THE DEFECT COULD NOT PASS. Nothing here passes an
	-- `isReducedMotion`, which is exactly what every production caller does.
	it("reduced motion ON: an adapter-side tween must NOT run", function()
		local w = world()
		w.env:set("reducedMotion", true)
		expect(w.adapter.reducedMotion()).toBe(true)
		w.adapter.takeMotionOps()
		w.adapter.tap("/S/Go")
		local ops = w.adapter.takeMotionOps()
		expect(#ops).toBe(1)
		expect(ops[1].kind).toBe("instant")
		-- the control still WORKS: reduced motion removes the animation, never
		-- the action (the accessibility failure mode nobody notices in review)
		expect(w.presses()).toBe(1)
		expect(w.core:lastError()).toBeNil()
	end)

	-- LIVE, not construction-time. A closure captured at `new` could never do
	-- this, which is the second half of why the old design was wrong.
	it("a mid-session flip lands on the very next press, both directions", function()
		local w = world()
		w.env:set("reducedMotion", true)
		w.adapter.takeMotionOps()
		w.adapter.tap("/S/Go")
		expect(w.adapter.takeMotionOps()[1].kind).toBe("instant")
		w.env:set("reducedMotion", false)
		w.adapter.tap("/S/Go")
		expect(w.adapter.takeMotionOps()[1].kind).toBe("tween")
		expect(w.core:lastError()).toBeNil()
	end)

	-- the fact is pushed at ATTACH, before anything is presented or pressed: a
	-- player who set the preference before the game booted must not see one
	-- full-motion frame
	it("a surface attached while the preference is already ON is born reduced", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 360, h = 640 })
		env:set("reducedMotion", true)
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		expect(adapter.reducedMotion()).toBe(false) -- nothing has told it yet
		local presenter = LuauUI.newPresenter(core, env, adapter, system)
		presenter.present(UI.Screen({ id = "S", children = { UI.Text({ id = "T", text = "hi" }) } }))
		presenter.refresh()
		expect(adapter.reducedMotion()).toBe(true)
		expect(core:lastError()).toBeNil()
	end)

	-- BOTH halves ride one observation (renderer.luau). The sheet half was
	-- already wired; the bespoke half is C1, and they must never disagree.
	it("the sheet half and the bespoke half stay in step", function()
		local w = world()
		expect(w.adapter.nativeTransitionsEnabled()).toBe(true)
		expect(w.adapter.reducedMotion()).toBe(false)
		w.env:set("reducedMotion", true)
		expect(w.adapter.nativeTransitionsEnabled()).toBe(false)
		expect(w.adapter.reducedMotion()).toBe(true)
	end)

	-- the declared degrade: an adapter without the method is not a crash
	it("a target WITHOUT setReducedMotion degrades by name", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 360, h = 640 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new();
		(adapter :: any).setReducedMotion = nil
		local presenter = LuauUI.newPresenter(core, env, adapter, system)
		presenter.present(UI.Screen({ id = "S", children = { UI.Text({ id = "T", text = "hi" }) } }))
		presenter.refresh()
		env:set("reducedMotion", true)
		expect(core:lastError()).toBeNil()
		-- and the seam is DECLARED, so the absence is a reported degrade
		local absent = target_contract.check(adapter).optionalAbsent
		expect(table.concat(absent, ",")).toBe("setReducedMotion")
	end)
end)

describe("reduced motion: the LIVE ScreenTarget resolves it from the pushed fact", function()
	-- screen_target.luau cannot load headless (engine globals at load), so its
	-- half is read from source exactly as render_target_contract.spec.luau reads
	-- it. What is pinned is the WIRING the behavioural cases above cannot see:
	-- that the adapter's one resolver reads the pushed flag, and that the pushed
	-- flag is what `setReducedMotion` writes.
	local source = fs.readFile("src/client/screen_target.luau")

	it("its one resolver consults the pushed flag, not only the legacy closure", function()
		expect(string.find(source, "local reducedMotionPushed = false", 1, true) ~= nil).toBe(true)
		expect(
			string.find(
				source,
				"return reducedMotionPushed or (isReducedMotionOpt ~= nil and isReducedMotionOpt() == true)",
				1,
				true
			) ~= nil
		).toBe(true)
		-- exactly ONE definition of the resolver: two would drift, and a second
		-- one defaulting to false is the defect verbatim
		local _, defs = string.gsub(source, "local function isReducedMotion%(", "")
		expect(defs).toBe(1)
	end)

	it("the pushed seam writes that same flag", function()
		local i = string.find(source, "function adapter.setReducedMotion(reduced: boolean)", 1, true)
		expect(i ~= nil).toBe(true)
		local body = string.sub(source, i :: number, (i :: number) + 200)
		expect(string.find(body, "reducedMotionPushed = reduced == true", 1, true) ~= nil).toBe(true)
	end)

	it("the deprecated construction opt can no longer say NO on the player's behalf", function()
		-- the exact shape of the defect: an opt that defaulted to "not reduced"
		-- and was the sole authority
		expect(string.find(source, "local isReducedMotion = (opts and opts.isReducedMotion) or function()", 1, true)).toBeNil()
	end)
end)

return true
