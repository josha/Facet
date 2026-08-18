--!strict
--[[
	THE ADAPTERS' RECOVERY AND HONESTY CONTRACTS — release-candidate platform
	review PLAT-7, PLAT-9, PLAT-11, PLAT-21, PLAT-22, PLAT-24, PLAT-25, PLAT-26.

	Eight findings across four client modules and the replication adapters, all of
	one family: a path that could not come back, or a verdict that was not earned.

	  · PLAT-7  — a LOST resnapshot reply latched the gap forever; every later
	              patch answered "gap" for the rest of the session, with no retry,
	              no timeout, and no way for a consumer to know.
	  · PLAT-25 — `patch.remove` was read only as an array, so a set-shaped remove
	              removed nothing and still reported "applied".
	  · PLAT-26 — `PreloadAsync` was handed content strings; every official sample
	              passes Instances.
	  · PLAT-21 — `UnbindAction` on an unbound action only warns, so
	              `disableLegacyControls` answered true on any live client whether
	              or not anything was freed.
	  · PLAT-22 — the TouchControlsEnabled suppression was per-binder, so a second
	              binder captured the SUPPRESSED value as "prior" and restored the
	              controls to hidden.
	  · PLAT-11 — an unbounded `WaitForChild("PlayerScripts")` on the input
	              adapter's first line.
	  · PLAT-9  — a deleted `Theme <name>` child on a stamp-matching sheet made
	              `setTheme` hard-error out of mount.
	  · PLAT-24 — the wrong-schema sheet found in the OTHER container was stranded.

	WHERE A PIN IS STRUCTURAL IT SAYS SO. `native_style.ensure` and
	`roblox_input.newSystem` build real Instances and cannot run headlessly; those
	two are pinned on the live source, in the idiom `tests/lib/adapter_source`
	already establishes for the adapter. Everything else is driven.
]]

local fs = require("@lune/fs")
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local adapters = require("../src/replication/adapters")

describe("a lost resnapshot reply is a bounded retry, not a wedge (PLAT-7)", function()
	local function rig()
		local core = Facet.newCore()
		local asks: { number } = {}
		local col = adapters.collection(core, 1, { a = 1 }, function(from: number)
			table.insert(asks, from)
		end)
		return col, asks
	end

	it("asks once for a gap, then retries on a backoff of refused patches", function()
		local col, asks = rig()
		-- the gap: revision 5 when we hold 1
		expect(col.ingestPatch(5, { set = { b = 2 } })).toBe("gap")
		expect(#asks).toBe(1)
		expect(col.gapDiagnostics().awaiting).toBe(true)

		-- one refused patch does NOT race an in-flight reply
		col.ingestPatch(6, { set = { c = 3 } })
		expect(#asks).toBe(1)

		-- ...and the reply never comes. Refused patches are the clock.
		local seen: { number } = {}
		for _ = 1, 200 do
			col.ingestPatch(6, { set = { c = 3 } })
			table.insert(seen, #asks)
		end
		expect(#asks > 1).toBe(true)
		-- bounded: it stops asking, and says so
		expect(#asks <= 5).toBe(true)
		expect(col.gapDiagnostics().exhausted).toBe(true)
		-- ...and the gaps between asks GREW rather than being one per patch
		expect(#asks < #seen).toBe(true)
	end)

	it("a resnapshot that finally arrives heals it completely", function()
		local col, asks = rig()
		col.ingestPatch(5, {})
		for _ = 1, 200 do
			col.ingestPatch(6, {})
		end
		expect(col.gapDiagnostics().exhausted).toBe(true)

		expect(col.ingestResnapshot(9, { z = 9 })).toBe("applied")
		local diagnostics = col.gapDiagnostics()
		expect(diagnostics.awaiting).toBe(false)
		expect(diagnostics.exhausted).toBe(false)
		expect(diagnostics.attempts).toBe(0)
		-- patching resumes at the new revision
		expect(col.ingestPatch(10, { set = { y = 1 } })).toBe("applied")
		expect(col.binding:get().y).toBe(1)
		expect(#asks <= 5).toBe(true)
	end)

	it("a throwing hook still un-latches immediately, as it always did", function()
		local core = Facet.newCore()
		local asks = 0
		local col = adapters.collection(core, 1, {}, function()
			asks += 1
			error("remote is down", 0)
		end)
		col.ingestPatch(5, {})
		expect(asks).toBe(1)
		expect(col.gapDiagnostics().awaiting).toBe(false)
		-- the very next patch asks again — no backoff wait, because nothing was sent
		col.ingestPatch(6, {})
		expect(asks).toBe(2)
	end)
end)

describe("patch.remove is an array of keys, loudly (PLAT-25)", function()
	local function newCollection()
		local core = Facet.newCore()
		return adapters.collection(core, 1, { a = 1, b = 2, [3] = "three" }, function() end)
	end

	it("an array remove applies", function()
		local col = newCollection()
		expect(col.ingestPatch(2, { remove = { "a" } })).toBe("applied")
		expect(col.binding:get().a).toBe(nil)
		expect(col.binding:get().b).toBe(2)
	end)

	it("a set-shaped remove is REFUSED by name instead of silently removing nothing", function()
		local col = newCollection()
		local ok, err = pcall(col.ingestPatch, 2, { remove = { a = true } })
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "must be an ARRAY of keys", 1, true) ~= nil).toBe(true)
		-- and nothing moved: the collection is exactly where it was
		expect(col.binding:get().a).toBe(1)
		expect(col.revision()).toBe(1)
	end)

	it("an empty remove and a missing remove are both fine", function()
		local col = newCollection()
		expect(col.ingestPatch(2, { remove = {} })).toBe("applied")
		expect(col.ingestPatch(3, { set = { c = 3 } })).toBe("applied")
		expect(col.binding:get().c).toBe(3)
	end)
end)

describe("PreloadAsync is handed Instances (PLAT-26)", function()
	it("the transport builds one per key, hands it over, and destroys it", function()
		local roblox_resources = require("../src/client/roblox_resources")
		local preloaded: { any } = {}
		local destroyed = 0
		local heartbeat = { fn = nil :: any }
		local completed: { string } = {}
		local provider = {
			pendingRequests = function()
				return { { key = "rbxassetid://123", generation = 1 } }
			end,
			complete = function(key: string)
				table.insert(completed, key)
			end,
			fail = function() end,
		}
		local SUCCESS = { name = "Success" }
		local unbind = roblox_resources.bind(provider, {
			contentProvider = {
				PreloadAsync = function(_self, list: { any }, callback: (string, any) -> ())
					table.insert(preloaded, list)
					callback("rbxassetid://123", SUCCESS)
				end,
			},
			run = {
				Heartbeat = {
					Connect = function(_self, fn: () -> ())
						heartbeat.fn = fn
						return { Disconnect = function() end }
					end,
				},
			},
			successStatus = SUCCESS,
			spawn = function(f: () -> ())
				f()
			end,
			newPreloadTarget = function(key: string): any
				return {
					Image = key,
					Destroy = function()
						destroyed += 1
					end,
				}
			end,
		})

		heartbeat.fn()
		expect(#preloaded).toBe(1)
		expect(#preloaded[1]).toBe(1)
		-- an INSTANCE-shaped target carrying the key, not the raw content string
		expect(type(preloaded[1][1])).toBe("table")
		expect(preloaded[1][1].Image).toBe("rbxassetid://123")
		expect(destroyed).toBe(1)
		-- ...and the PUBLIC contract is unchanged: the completed value is the key
		expect(completed).toEqual({ "rbxassetid://123" })
		unbind()
	end)
end)

describe("disableLegacyControls only claims what it freed (PLAT-21)", function()
	local gamepad_contention = require("../src/client/gamepad_contention")

	it("an action that was never bound was not freed by unbinding it", function()
		expect(gamepad_contention.freedJumpAction({}, {})).toBe(false)
	end)

	it("an action still bound afterwards was not freed either", function()
		expect(gamepad_contention.freedJumpAction({ jumpAction = {} }, { jumpAction = {} })).toBe(false)
	end)

	it("gone from a table it was in IS freed", function()
		expect(gamepad_contention.freedJumpAction({ jumpAction = {} }, {})).toBe(true)
	end)

	it("the live fallback consults the binding table before claiming success", function()
		local source = fs.readFile("src/client/gamepad_contention.luau")
		local fallback = string.match(source, "local ok, freed = pcall%(function%(%): boolean(.-)\n\tend%)")
		expect(fallback ~= nil).toBe(true)
		expect(string.find(fallback :: string, "GetAllBoundActionInfo()", 1, true) ~= nil).toBe(true)
		expect(string.find(fallback :: string, "freedJumpAction(", 1, true) ~= nil).toBe(true)
		--[[ The claim is still gated on what was actually freed — the spelling moved
			with DF-9 (2026-08-18), which gave the function a STATUS alongside the
			boolean so an inert call could be told apart from a real remedy. It used
			to read `return ok and freed`; the gate is now the `if`, and the failure
			path names itself instead of returning a bare false. ]]
		expect(string.find(source, "if ok and freed then", 1, true) ~= nil).toBe(true)
		expect(string.find(source, 'return true, "unbound"', 1, true) ~= nil).toBe(true)
		expect(string.find(source, 'return false, "unavailable"', 1, true) ~= nil).toBe(true)
	end)

	--[[ DF-9: and the inert branch must come FIRST. If the IAS check ran after the
		primary path, a flag-on place would still spend the bounded PlayerModule
		wait before discovering there was nothing to disable — which is the cost
		the whole change exists to remove, and it would be invisible in a boolean
		return. Order is the behaviour here, so order is what this pins. ]]
	it("the IAS inert check runs BEFORE either engine remedy is attempted", function()
		local source = fs.readFile("src/client/gamepad_contention.luau")
		local body = string.match(source, "function gamepad_contention%.disableLegacyControls(.*)")
		expect(body ~= nil).toBe(true)
		local inert = string.find(body :: string, "iasPlayerScriptsActive", 1, true)
		local primary = string.find(body :: string, "GetControls():Disable()", 1, true)
		local fallbackAt = string.find(body :: string, "UnbindAction", 1, true)
		expect(inert ~= nil).toBe(true)
		expect((inert :: number) < (primary :: number)).toBe(true)
		expect((inert :: number) < (fallbackAt :: number)).toBe(true)
	end)
end)

describe("the touch-controls suppression is refcounted (PLAT-22)", function()
	local responder_effects = require("../src/client/responder_effects")

	local function withFakeGuiService(body: (state: { value: boolean }) -> ())
		local state = { value = true }
		local readOriginal = responder_effects.readTouchControls
		local writeOriginal = responder_effects.writeTouchControls
		responder_effects.readTouchControls = function(): boolean?
			return state.value
		end
		responder_effects.writeTouchControls = function(on: boolean): boolean
			state.value = on
			return true
		end
		local ok, err = pcall(body, state)
		responder_effects.readTouchControls = readOriginal
		responder_effects.writeTouchControls = writeOriginal
		if not ok then
			error(err, 0)
		end
	end

	local function newPresenterStub(core: any)
		local active = core:signal(false)
		return { exclusiveSurfaceActive = active }, active
	end

	it("two binders share one suppression, and the SECOND release restores the prior value", function()
		withFakeGuiService(function(state)
			local core = Facet.newCore()
			local first, firstActive = newPresenterStub(core)
			local second, secondActive = newPresenterStub(core)
			local unbindFirst = responder_effects.bind(core, first)
			local unbindSecond = responder_effects.bind(core, second)
			expect(state.value).toBe(true)
			expect(responder_effects.suppressionCount()).toBe(0)

			firstActive:set(true)
			expect(state.value).toBe(false)
			expect(responder_effects.suppressionCount()).toBe(1)

			-- the second binder must NOT read `false` as the prior value
			secondActive:set(true)
			expect(responder_effects.suppressionCount()).toBe(2)

			secondActive:set(false)
			-- still suppressed: the first binder is still holding
			expect(state.value).toBe(false)
			expect(responder_effects.suppressionCount()).toBe(1)

			firstActive:set(false)
			-- ...and the ORIGINAL value comes back, not the suppressed one
			expect(state.value).toBe(true)
			expect(responder_effects.suppressionCount()).toBe(0)
			unbindFirst()
			unbindSecond()
			expect(responder_effects.suppressionCount()).toBe(0)
		end)
	end)

	it("unbinding while suppressed releases exactly one reference", function()
		withFakeGuiService(function(state)
			local core = Facet.newCore()
			local first, firstActive = newPresenterStub(core)
			local second, secondActive = newPresenterStub(core)
			local unbindFirst = responder_effects.bind(core, first)
			local unbindSecond = responder_effects.bind(core, second)
			firstActive:set(true)
			secondActive:set(true)
			expect(responder_effects.suppressionCount()).toBe(2)
			unbindFirst()
			expect(state.value).toBe(false)
			unbindSecond()
			expect(state.value).toBe(true)
			expect(responder_effects.suppressionCount()).toBe(0)
		end)
	end)

	it("the release RE-READS: a host that took the property back keeps it (PLAT-22)", function()
		--[[ The half of PLAT-22's contract that had ZERO coverage (review): deleting
			the re-read guard left all seventeen cases green. The shape it protects is
			a host game that turns the touch controls back on itself while a Facet
			surface is exclusive — on release, restoring "the prior value" would take
			them away again, from a property the framework no longer owns. ]]
		withFakeGuiService(function(state)
			-- the host already had the touch controls OFF, so `prior` is false and
			-- "restore the prior value" and "leave it alone" are finally different
			-- answers — with a boolean property they are indistinguishable any other
			-- way, which is how this half went uncovered
			state.value = false
			local core = Facet.newCore()
			local presenter, active = newPresenterStub(core)
			local unbind = responder_effects.bind(core, presenter)
			active:set(true)
			expect(state.value).toBe(false)
			expect(responder_effects.suppressionCount()).toBe(1)

			-- the HOST turns them back on mid-suppression: the property is its
			-- decision now, not ours
			state.value = true
			active:set(false)
			-- ...and the release does NOT put its own stale `prior` back over it
			expect(state.value).toBe(true)
			expect(responder_effects.suppressionCount()).toBe(0)
			unbind()
		end)
	end)

	it("...and it still restores when the value IS the one we wrote (PLAT-22)", function()
		-- the negative control for the case above: without it, "never restores"
		-- would pass the same assertions
		withFakeGuiService(function(state)
			local core = Facet.newCore()
			local presenter, active = newPresenterStub(core)
			local unbind = responder_effects.bind(core, presenter)
			active:set(true)
			expect(state.value).toBe(false)
			active:set(false)
			expect(state.value).toBe(true)
			unbind()
		end)
	end)

	it("a write the engine accepts but does not APPLY is not counted as suppression", function()
		local readOriginal = responder_effects.readTouchControls
		local writeOriginal = responder_effects.writeTouchControls
		-- the shape that made `pcall` success a lie: the call returns fine and the
		-- property does not move
		responder_effects.readTouchControls = function(): boolean?
			return true
		end
		responder_effects.writeTouchControls = function(): boolean
			return true
		end
		local core = Facet.newCore()
		local presenter, active = newPresenterStub(core)
		local unbind = responder_effects.bind(core, presenter)
		active:set(true)
		local count = responder_effects.suppressionCount()
		unbind()
		responder_effects.readTouchControls = readOriginal
		responder_effects.writeTouchControls = writeOriginal
		expect(count).toBe(0)
	end)
end)

describe("bounded waits and stranded sheets (PLAT-11, PLAT-9, PLAT-24)", function()
	--[[ STRUCTURAL, and the header says why: `roblox_input.newSystem` and
		`native_style.ensure` build real engine Instances on their first lines, so
		neither loads headlessly. The pins read the live source, which is the idiom
		`tests/lib/adapter_source.luau` establishes for the client adapter. ]]
	it("the PlayerScripts wait is bounded and loud, like gamepad_contention's (PLAT-11)", function()
		local source = fs.readFile("src/client/roblox_input.luau")
		expect(string.find(source, 'WaitForChild("PlayerScripts", PLAYER_SCRIPTS_WAIT_SECONDS)', 1, true) ~= nil).toBe(
			true
		)
		expect(string.find(source, "local PLAYER_SCRIPTS_WAIT_SECONDS = 5", 1, true) ~= nil).toBe(true)
		-- ...and it does not degrade silently: a nil host would accept every bind
		-- and drive nothing
		expect(string.find(source, "host ~= nil", 1, true) ~= nil).toBe(true)
		-- the pattern it is modelled on is still bounded too
		local contention = fs.readFile("src/client/gamepad_contention.luau")
		expect(string.find(contention, 'WaitForChild("PlayerModule", 5)', 1, true) ~= nil).toBe(true)
	end)

	it("the theme-child ensure runs OUTSIDE the stamp-mismatch branch (PLAT-9)", function()
		local source = fs.readFile("src/client/native_style.luau")
		local existingBranch = string.match(source, "\n\tif existing ~= nil then\n(.-)\n\telse\n")
		expect(existingBranch ~= nil).toBe(true)
		local branch = existingBranch :: string
		-- the migration block ends at buildRules; the ensure loop must come AFTER it
		local buildRulesAt = string.find(branch, "buildRules(sheet)", 1, true)
		local ensureAt = string.find(branch, 'created.Name = "Theme " .. theme.name', 1, true)
		expect(buildRulesAt ~= nil).toBe(true)
		expect(ensureAt ~= nil).toBe(true)
		expect((ensureAt :: number) > (buildRulesAt :: number)).toBe(true)
		-- ...and it is no longer nested inside the stamp test
		local stampBlock =
			string.match(branch, "if sheet:GetAttribute%(ATTR_STAMP%) ~= model.stamp then(.-)\n\t\tend\n")
		expect(stampBlock ~= nil).toBe(true)
		expect(string.find(stampBlock :: string, 'created.Name = "Theme "', 1, true)).toBe(nil)
	end)

	it("every wrong-schema sheet found is destroyed, in both lookup orders (PLAT-24)", function()
		local source = fs.readFile("src/client/native_style.luau")
		-- one collector, appended to by the lookup helper both call sites use...
		expect(string.find(source, "local staleSheets: { StyleSheet } = {}", 1, true) ~= nil).toBe(true)
		expect(string.find(source, "table.insert(staleSheets, staleOne)", 1, true) ~= nil).toBe(true)
		-- ...and drained once the host is resolved, before either branch runs
		local drain = string.match(source, "for _, artifact in staleSheets do(.-)end")
		expect(drain ~= nil).toBe(true)
		expect(string.find(drain :: string, "artifact:Destroy()", 1, true) ~= nil).toBe(true)
		-- the single-slot assignment the second lookup used to overwrite is gone,
		-- and `findSheet` is now reached through the collecting helper ONLY (its
		-- own definition plus the one call inside `lookup`)
		expect(string.find(source, "existing, stale = findSheet", 1, true)).toBe(nil)
		local _, calls = string.gsub(source, "findSheet%(", "")
		expect(calls).toBe(2)
	end)
end)
