--!strict
-- PROFILE-CONDITIONAL PACKAGE SELECTION (rich-skinning-v2 P4).
--
-- `selectBy = { touch = pkgA, pointer = pkgB, gamepad = pkgC }` is a
-- DECLARATION over machinery that already exists. Nothing here detects an input
-- class — the `interactionClasses` fact already does, live and
-- hybrid-aware — and nothing here is a second swap path: every package change is
-- the existing atomic `swapPackage`, which is what holds mount, focus and scroll
-- identity BY CONSTRUCTION rather than by a promise.
--
-- The five propositions, each a way this could be wrong while everything else
-- stays green:
--   1. the INITIAL package is the profile's, at install, not the default plus a
--      swap a frame later;
--   2. an UNMAPPED profile falls back to the positional default, deterministically;
--   3. a hybrid FLAP produces ONE swap per settlement, and a flap that returns to
--      where it started produces NONE;
--   4. a manual `swapPackage` WINS until the next profile change, and warns once;
--   5. the subscription lives and dies with the controller.
--
-- The controller runs in FALLBACK mode here (`forceFallback`) because selectBy
-- is mode-independent: it changes which package is committed, and the metric
-- commit is the half that has no engine in it. The native materialization is
-- the Studio scenario's evidence.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")

local customFactory = require("../src/core/custom")
local environment = require("../src/env/environment")
local themes = require("../src/themes/package")
local snapshot = require("../src/themes/snapshot")
local theme_controller = require("../src/client/theme_controller")
local fake_target = require("./lib/fake_target")

local function definePackage(id: string, spaceM: number): any
	local pkg, report = themes.define({
		base = snapshot.neutralPackage(),
		identity = { id = id, displayName = id, schemaVersion = themes.SCHEMA, version = "1.0.0" },
		metrics = { space = { xs = 4, s = 8, m = spaceM, l = 24, xl = 40 } },
	})
	assert(pkg ~= nil, `fixture '{id}' failed to compile: {report.errors[1] and report.errors[1].message or "?"}`)
	return pkg
end

local GLOSSY = definePackage("glossy-touch-test", 20) -- the touch package
local COMPACT = definePackage("compact-pointer-test", 12) -- the pointer package
local DEFAULT = definePackage("default-test", 16) -- the positional default

-- a settle timer the spec drives by hand. Every scheduled callback is held, so
-- "one swap per settlement" and "a superseded flap fires nothing" are assertable
-- without a frame loop.
local function fakeSettle()
	local state: any = { pending = {}, scheduled = 0, cancelled = 0 }
	local function settle(_seconds: number, fn: () -> ()): () -> ()
		state.scheduled += 1
		local entry: any = { fn = fn, cancelled = false }
		table.insert(state.pending, entry)
		return function()
			entry.cancelled = true
			state.cancelled += 1
		end
	end
	function state.fire()
		local queue = state.pending
		state.pending = {}
		for _, entry in queue do
			if not entry.cancelled then
				entry.fn()
			end
		end
	end
	return settle, state
end

local function newWorld(preferred: string, capabilities: any?)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	env:set("preferredInput", preferred)
	if capabilities ~= nil then
		env:set("capabilities", capabilities)
	end
	local adapter = fake_target.new()
	return { core = core, env = env, adapter = adapter }
end

local function install(w: any, opts: any?): (any, any)
	local settle, settleState = fakeSettle()
	local o: any = {
		env = w.env,
		core = w.core,
		forceFallback = true,
		selectBySettle = settle,
		warn = function() end,
	}
	for key, value in opts or {} do
		o[key] = value
	end
	local controller = theme_controller.install(w.adapter, DEFAULT, o)
	return controller, settleState
end

-- ===== 1/2. resolution and fallback ========================================

describe("selectBy resolves at INSTALL from the facts already published", function()
	it("the profile's package is the one that installs — never default-then-swap", function()
		local w = newWorld("Touch")
		local controller = install(w, { selectBy = { touch = GLOSSY, pointer = COMPACT } })
		expect(controller.inspect().package.id).toBe("glossy-touch-test")
		-- and the METRICS that came with it, in the same install: a swap a frame
		-- later would have painted one frame of the default package's geometry
		expect(w.env:get("themeMetrics"):get().space.m).toBe(20)
		expect(controller.inspect().selectBy.profile).toBe("touch")
		expect(controller.inspect().selectBy.swaps).toBe(0)
		controller.uninstall()
	end)

	it("a pointer profile takes the pointer package", function()
		local w = newWorld("KeyboardAndMouse")
		local controller = install(w, { selectBy = { touch = GLOSSY, pointer = COMPACT } })
		expect(controller.inspect().package.id).toBe("compact-pointer-test")
		controller.uninstall()
	end)

	it("an UNMAPPED profile falls back to the positional default package", function()
		local w = newWorld("Gamepad", { gamepad = true })
		-- the map names touch and pointer only
		local controller = install(w, { selectBy = { touch = GLOSSY, pointer = COMPACT } })
		expect(theme_controller.profileOf(w.env)).toBe("gamepad")
		expect(controller.inspect().package.id).toBe("default-test")
		expect(controller.inspect().selectBy.profile).toBe("gamepad")
		controller.uninstall()
	end)

	it("PRIMARY is the decision, not the whole class set (a hybrid has several)", function()
		-- touch AND gamepad AND pointer all live; the preferred class decides
		local w = newWorld("Touch", { touch = true, gamepad = true, mouse = true, keyboard = true })
		local classes = w.env:get("interactionClasses"):get()
		expect(classes.touch).toBe(true)
		expect(classes.gamepad).toBe(true)
		expect(classes.pointer).toBe(true)
		expect(theme_controller.profileOf(w.env)).toBe("touch")
		local controller = install(w, { selectBy = { touch = GLOSSY, pointer = COMPACT, gamepad = COMPACT } })
		expect(controller.inspect().package.id).toBe("glossy-touch-test")
		controller.uninstall()
	end)

	it("the vocabulary is CLOSED — a name outside the classes is an authoring error", function()
		local w = newWorld("Touch")
		local ok, err = pcall(function()
			install(w, { selectBy = { phone = GLOSSY } })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "phone", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "touch | pointer | gamepad", 1, true) ~= nil).toBe(true)
	end)

	it("a selectBy entry must be a compiled package, and the rule needs a core", function()
		local w = newWorld("Touch")
		local okPkg, errPkg = pcall(function()
			install(w, { selectBy = { touch = { identity = { id = "raw" } } } })
		end)
		expect(okPkg).toBe(false)
		expect(string.find(tostring(errPkg), "themes.define", 1, true) ~= nil).toBe(true)

		local okCore, errCore = pcall(function()
			theme_controller.install(w.adapter, DEFAULT, {
				env = w.env,
				forceFallback = true,
				selectBy = { touch = GLOSSY },
			})
		end)
		expect(okCore).toBe(false)
		expect(string.find(tostring(errCore), "opts.core", 1, true) ~= nil).toBe(true)
	end)
end)

-- ===== 3. the settled swap, and the flap ===================================

describe("a profile change swaps ONCE, after it settles", function()
	it("dock: touch -> pointer swaps the package and the metrics together", function()
		local w = newWorld("Touch")
		local controller, settle = install(w, { selectBy = { touch = GLOSSY, pointer = COMPACT } })
		expect(controller.inspect().package.id).toBe("glossy-touch-test")

		w.env:set("preferredInput", "KeyboardAndMouse")
		-- nothing yet: the profile has to HOLD
		expect(controller.inspect().package.id).toBe("glossy-touch-test")
		expect(settle.scheduled).toBe(1)

		settle.fire()
		expect(controller.inspect().package.id).toBe("compact-pointer-test")
		expect(w.env:get("themeMetrics"):get().space.m).toBe(12)
		expect(controller.inspect().selectBy.profile).toBe("pointer")
		expect(controller.inspect().selectBy.swaps).toBe(1)
		controller.uninstall()
	end)

	it("a hybrid FLAP produces one swap per settlement, not one per flap", function()
		local w = newWorld("Touch")
		local controller, settle = install(w, { selectBy = { touch = GLOSSY, pointer = COMPACT, gamepad = COMPACT } })
		-- touch -> gamepad -> pointer -> gamepad, all before anything settles
		w.env:set("preferredInput", "Gamepad")
		w.env:set("preferredInput", "KeyboardAndMouse")
		w.env:set("preferredInput", "Gamepad")
		expect(settle.scheduled).toBe(3)
		expect(settle.cancelled).toBe(2) -- each flap cancelled the one before it
		settle.fire()
		-- ONE swap, to where it actually came to rest
		expect(controller.inspect().selectBy.swaps).toBe(1)
		expect(controller.inspect().selectBy.profile).toBe("gamepad")
		expect(controller.inspect().package.id).toBe("compact-pointer-test")
		controller.uninstall()
	end)

	it("a flap that returns to where it started swaps NOTHING", function()
		local w = newWorld("Touch")
		local controller, settle = install(w, { selectBy = { touch = GLOSSY, pointer = COMPACT } })
		w.env:set("preferredInput", "KeyboardAndMouse")
		w.env:set("preferredInput", "Touch")
		settle.fire()
		expect(controller.inspect().selectBy.swaps).toBe(0)
		expect(controller.inspect().package.id).toBe("glossy-touch-test")
		controller.uninstall()
	end)

	it("an unmapped profile ARRIVING swaps back to the default, deterministically", function()
		local w = newWorld("Touch")
		local controller, settle = install(w, { selectBy = { touch = GLOSSY, pointer = COMPACT } })
		w.env:set("capabilities", { gamepad = true })
		w.env:set("preferredInput", "Gamepad")
		settle.fire()
		-- NOT "keep whatever the last mapped profile installed"
		expect(controller.inspect().package.id).toBe("default-test")
		expect(controller.inspect().selectBy.profile).toBe("gamepad")
		controller.uninstall()
	end)
end)

-- ===== 4. manual precedence =================================================

describe("a manual swapPackage wins until the next profile change", function()
	it("it stands, and it warns exactly once", function()
		local w = newWorld("Touch")
		local warnings: { string } = {}
		local controller, settle = install(w, {
			selectBy = { touch = GLOSSY, pointer = COMPACT },
			warn = function(message: string)
				table.insert(warnings, message)
			end,
		})
		controller.swapPackage(DEFAULT)
		expect(controller.inspect().package.id).toBe("default-test")
		expect(#warnings).toBe(1)
		expect(string.find(warnings[1], "selectBy", 1, true) ~= nil).toBe(true)
		controller.swapPackage(COMPACT)
		expect(#warnings).toBe(1) -- once, not per call
		expect(controller.inspect().selectBy.manualOverride).toBe(true)
		controller.uninstall()
	end)

	it("...and the NEXT settled profile change takes it back", function()
		local w = newWorld("Touch")
		local controller, settle = install(w, { selectBy = { touch = GLOSSY, pointer = COMPACT } })
		controller.swapPackage(DEFAULT)
		expect(controller.inspect().package.id).toBe("default-test")
		w.env:set("preferredInput", "KeyboardAndMouse")
		settle.fire()
		expect(controller.inspect().package.id).toBe("compact-pointer-test")
		expect(controller.inspect().selectBy.manualOverride).toBe(false)
		controller.uninstall()
	end)

	it("the manual flag clears on a settlement even when the package does not move", function()
		-- the case a naive `if target == active then return` would have broken:
		-- the hand-swapped package IS the one the arriving profile wants, so
		-- nothing swaps — but the override has to end, or selectBy would stay
		-- suppressed forever after one lucky coincidence
		local w = newWorld("Touch")
		local controller, settle = install(w, { selectBy = { touch = GLOSSY, pointer = COMPACT } })
		controller.swapPackage(COMPACT)
		expect(controller.inspect().selectBy.manualOverride).toBe(true)
		w.env:set("preferredInput", "KeyboardAndMouse")
		settle.fire()
		expect(controller.inspect().package.id).toBe("compact-pointer-test")
		expect(controller.inspect().selectBy.manualOverride).toBe(false)
		expect(controller.inspect().selectBy.swaps).toBe(0) -- nothing had to move
		controller.uninstall()
	end)
end)

-- ===== 5. the subscription's lifetime ======================================

describe("the subscription lives and dies with the controller", function()
	it("uninstall drops it, and a later profile change touches nothing", function()
		local w = newWorld("Touch")
		local controller, settle = install(w, { selectBy = { touch = GLOSSY, pointer = COMPACT } })
		local scheduledBefore = settle.scheduled
		controller.uninstall()
		w.env:set("preferredInput", "KeyboardAndMouse")
		expect(settle.scheduled).toBe(scheduledBefore)
		settle.fire()
		-- the environment is back on the pre-install snapshot, not on a package
		-- some dead controller swapped in after its own uninstall
		expect(w.env:get("themeMetrics"):get().identity.packageId).toBe("studio-neutral")
	end)

	it("a controller with no selectBy publishes no selectBy state at all", function()
		local w = newWorld("Touch")
		local controller = theme_controller.install(w.adapter, DEFAULT, {
			env = w.env,
			core = w.core,
			forceFallback = true,
		})
		expect(controller.inspect().selectBy).toBeNil()
		controller.uninstall()
	end)

	-- runtime-F7: the old version of this test grepped the source for the
	-- unsubscribe CALL, which reports the variable and not the registry. The core
	-- owns the only truth about whether an observer is still attached, so the
	-- leak check reads the registry across a full install/uninstall cycle.
	it("the core's OWN observer count returns to baseline across install/uninstall", function()
		local w = newWorld("Touch")
		local baseline = w.core:counters().observers
		local controller = install(w, { selectBy = { touch = GLOSSY, pointer = COMPACT } })
		-- the subscription is real: the count actually went up
		expect(w.core:counters().observers > baseline).toBe(true)
		controller.uninstall()
		expect(w.core:counters().observers).toBe(baseline)
		-- ...and it stays at baseline over a second cycle (no per-install residue)
		local again = install(w, { selectBy = { touch = GLOSSY, pointer = COMPACT } })
		again.uninstall()
		expect(w.core:counters().observers).toBe(baseline)
	end)

	it("uninstall CANCELS a settle already in flight (runtime-F6)", function()
		local w = newWorld("Touch")
		local controller, settle = install(w, { selectBy = { touch = GLOSSY, pointer = COMPACT } })
		w.env:set("preferredInput", "KeyboardAndMouse")
		expect(settle.scheduled).toBe(1)
		local cancelledBefore = settle.cancelled
		controller.uninstall()
		-- the timer is cancelled, not merely no-opped by the disposed flag: a live
		-- task.delay closure keeps the whole controller reachable for its window
		expect(settle.cancelled).toBe(cancelledBefore + 1)
		settle.fire()
		expect(w.env:get("themeMetrics"):get().identity.packageId).toBe("studio-neutral")
	end)

	it("the source keeps ONE swap path with an explicit ORIGIN (contract)", function()
		local source = fs.readFile("src/client/theme_controller.luau")
		-- platform-F9: no monkey-patch rebind — one function, one parameter
		expect(string.find(source, "local rawSwapPackage", 1, true)).toBeNil()
		expect(string.find(source, 'swapPackageInternal(nextPackage, themeName, "manual")', 1, true) ~= nil).toBe(true)
		expect(string.find(source, 'swapPackageInternal(target, nil, "profile")', 1, true) ~= nil).toBe(true)
		-- the observer is created from the caller's core and released on uninstall
		expect(string.find(source, "o.core:observe(selectByClasses, onProfileChanged)", 1, true) ~= nil).toBe(true)
		expect(string.find(source, "selectByUnsubscribe()", 1, true) ~= nil).toBe(true)
	end)
end)

-- ===== the adversarial half (rich-skinning-v2 runtime/platform verifiers) ===

describe("selectBy under adversarial input (verifier fix round)", function()
	-- runtime-F1. `interactionClasses` is a memo returning a FRESH table per
	-- recompute under identity equality, so ANY capability write fires the
	-- observer. The settle body compared the profile CAPTURED AT NOTIFICATION
	-- time and then ran `applyProfile` whenever a manual override was live —
	-- which discarded the operator's hand-picked package 0.25s after an
	-- unrelated gamepad connect, with the profile completely unchanged.
	it("a capability write whose PRIMARY did not change revokes nothing", function()
		local w = newWorld("Touch", { touch = true, mouse = false, gamepad = false, keyboard = false })
		local controller, settle = install(w, { selectBy = { touch = GLOSSY, pointer = COMPACT } })
		expect(controller.inspect().package.id).toBe("glossy-touch-test")
		controller.swapPackage(DEFAULT)
		expect(controller.inspect().selectBy.manualOverride).toBe(true)
		-- a gamepad connects. `primary` is still "touch" — nothing about the
		-- profile moved — but the memo recomputed and the observer fired.
		w.env:set("capabilities", { touch = true, mouse = false, gamepad = true, keyboard = false })
		settle.fire()
		expect(theme_controller.profileOf(w.env)).toBe("touch")
		expect(controller.inspect().package.id).toBe("default-test")
		expect(controller.inspect().selectBy.manualOverride).toBe(true)
		expect(controller.inspect().selectBy.swaps).toBe(0)
		-- ...and a GENUINE profile change still takes it back
		w.env:set("preferredInput", "KeyboardAndMouse")
		w.env:set("capabilities", { touch = false, mouse = true, gamepad = true, keyboard = true })
		settle.fire()
		expect(controller.inspect().package.id).toBe("compact-pointer-test")
		expect(controller.inspect().selectBy.manualOverride).toBe(false)
		controller.uninstall()
	end)

	-- runtime-F2. `manualOverride` and the once-only warning were latched BEFORE
	-- the call that can throw, so a rejected manual swap suppressed selectBy
	-- anyway and spent the warning the next (valid) caller needed.
	it("a FAILED manual swap latches nothing and spends no warning", function()
		local w = newWorld("Touch")
		local warnings: { string } = {}
		local controller, settle = install(w, {
			selectBy = { touch = GLOSSY, pointer = COMPACT },
			warn = function(message: string)
				table.insert(warnings, message)
			end,
		})
		local ok = pcall(function()
			-- a package with a theme it does not declare: rejected pre-mutation
			controller.swapPackage(COMPACT, "NoSuchTheme")
		end)
		expect(ok).toBe(false)
		expect(controller.inspect().selectBy.manualOverride).toBe(false)
		expect(#warnings).toBe(0)
		expect(controller.inspect().package.id).toBe("glossy-touch-test")
		-- the warning is still there to be spent by the swap that succeeds
		controller.swapPackage(DEFAULT)
		expect(controller.inspect().selectBy.manualOverride).toBe(true)
		expect(#warnings).toBe(1)
		controller.uninstall()
	end)

	-- runtime-F4. `o.core:observe` ran ~750 lines past the first mutation. On a
	-- throw the caller never got a handle, so `uninstall` was unreachable and the
	-- liveControllers entry persisted for the process lifetime — the env could
	-- never be themed again.
	it("a throwing core.observe leaves the environment installable (no half-install)", function()
		local w = newWorld("Touch")
		local poisoned = {
			observe = function()
				error("observe exploded", 0)
			end,
			signal = w.core.signal,
			memo = w.core.memo,
		}
		setmetatable(poisoned, { __index = w.core })
		local ok = pcall(function()
			return theme_controller.install(w.adapter, DEFAULT, {
				env = w.env,
				core = poisoned,
				forceFallback = true,
				selectBy = { touch = GLOSSY, pointer = COMPACT },
				selectBySettle = (fakeSettle()),
				warn = function() end,
			})
		end)
		expect(ok).toBe(false)
		-- the environment is not poisoned: a fresh install succeeds
		local controller = install(w, { selectBy = { touch = GLOSSY, pointer = COMPACT } })
		expect(controller.inspect().package.id).toBe("glossy-touch-test")
		expect(w.core:counters().observers >= 0).toBe(true)
		controller.uninstall()
	end)

	-- runtime-F3. The identity was published BEFORE the decoration commit, and
	-- the decoration commit is the one call in the transaction that runs foreign
	-- code. A throwing adapter left the controller saying pkg-b while the env's
	-- themeMetrics said pkg-a, and every later swap re-entered the same throw.
	it("a throwing adapter.setThemePackage rolls the WHOLE identity back", function()
		local w = newWorld("Touch")
		local calls = 0
		local adapter = fake_target.new()
		local seen: { any } = {}
		adapter.setThemePackage = function(pkg: any)
			calls += 1
			if calls == 2 then
				error("decoration exploded", 0)
			end
			seen[#seen + 1] = if pkg ~= nil then pkg.identity.id else nil
			return true
		end
		local controller = theme_controller.install(adapter, DEFAULT, {
			env = w.env,
			core = w.core,
			forceFallback = true,
			warn = function() end,
		})
		expect(controller.inspect().package.id).toBe("default-test")
		local ok = pcall(function()
			controller.swapPackage(GLOSSY)
		end)
		expect(ok).toBe(false)
		-- ALL THREE surfaces still describe the previous package
		expect(controller.inspect().package.id).toBe("default-test")
		expect(controller.current()).toBe("Dark")
		expect(w.env:get("themeMetrics"):get().identity.packageId).toBe("default-test")
		expect(seen[#seen]).toBe("default-test")
		-- ...and the controller re-converges: a later swap to a good package works
		controller.swapPackage(COMPACT)
		expect(controller.inspect().package.id).toBe("compact-pointer-test")
		expect(w.env:get("themeMetrics"):get().identity.packageId).toBe("compact-pointer-test")
		controller.uninstall()
	end)

	-- platform-F3, RE-ROOTED 2026-07-29. `PreferredInput` is known to lag reality
	-- (a phone that has not been touched yet still reads KeyboardAndMouse), and a
	-- touch-only device was therefore installing the 22px compact-POINTER package.
	-- It used to be corrected HERE, with a warning. It is now correct at the
	-- SOURCE — `interactionClasses` resolves the primary from capability when no
	-- preference has been expressed — because this was never a theme problem: the
	-- same wrong fact was also giving a phone the Table's dense pointer row height
	-- until the player's first touch reflowed the whole page (device report, same
	-- day). So the package is still right and there is nothing left to warn about.
	it("a touch-only device whose PreferredInput says KeyboardAndMouse takes the TOUCH package", function()
		local w = newWorld("KeyboardAndMouse", { touch = true, mouse = false, gamepad = false, keyboard = false })
		expect(theme_controller.profileOf(w.env)).toBe("touch")
		local warnings: { string } = {}
		local controller = install(w, {
			selectBy = { touch = GLOSSY, pointer = COMPACT },
			warn = function(message: string)
				table.insert(warnings, message)
			end,
		})
		expect(controller.inspect().package.id).toBe("glossy-touch-test")
		-- no warning: the fact arrives correct, so nothing is being overruled
		expect(#warnings).toBe(0)
		controller.uninstall()

		-- the tiebreaker is NARROW: it needs exactly one capability class, so a
		-- genuine hybrid (touch + mouse) keeps the preferred class
		local hybrid = newWorld("KeyboardAndMouse", { touch = true, mouse = true, gamepad = false, keyboard = true })
		expect(theme_controller.profileOf(hybrid.env)).toBe("pointer")
		-- ...and a device whose caps AGREE with the preferred class is untouched
		local plain = newWorld("KeyboardAndMouse", { touch = false, mouse = true, gamepad = false, keyboard = true })
		expect(theme_controller.profileOf(plain.env)).toBe("pointer")
		-- ...and no capability facts at all changes nothing (the default caps)
		local bare = newWorld("Touch")
		expect(theme_controller.profileOf(bare.env)).toBe("touch")
	end)
end)
