--!strict
-- P1.8 slice tests (§17 Phase 1 exit gate): the authoritative-mutation path
-- driven through the UI (Button activate -> mutation -> server -> reconcile),
-- including delayed confirmation and rejection leaving no permanent
-- pending/divergent state; plus multi-input bindings present simultaneously
-- (keyboard + touch + gamepad on one action, hybrid-device rule).

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src")
local fake_target = require("../tests/lib/fake_target")

local function world()
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)
	return core, env, system, adapter, pres
end

describe("slice: UI-driven authoritative mutation", function()
	local function build(core: any, pres: any, system: any)
		local snapshot = LuauUI.replication.snapshot(core, 1, { music = false })
		local draft = core:signal(false)
		local status = core:signal("idle")
		local mutation = LuauUI.replication.mutation(core, {
			optimistic = {
				apply = function(payload)
					draft:set(payload.music)
				end,
				restore = function()
					draft:set(snapshot.binding:get().music)
				end,
			},
		})
		local pendingEnvelope: any = nil
		local screen = LuauUI.UI.Screen({
			id = "S",
			children = {
				LuauUI.UI.Toggle({ id = "Music", label = "Music", value = draft }),
				LuauUI.UI.Button({ id = "Save", label = "Save" }),
			},
		})
		pres.present(screen, {
			onActivate = function(path: string)
				if path == "/S/Music" then
					draft:set(not draft:get())
				elseif path == "/S/Save" then
					pendingEnvelope = mutation.send({ music = draft:get() }, snapshot.revision())
					status:set("pending")
				end
			end,
		})
		return {
			snapshot = snapshot,
			draft = draft,
			status = status,
			mutation = mutation,
			envelope = function()
				return pendingEnvelope
			end,
		}
	end

	it("toggle + save + delayed server confirm reconciles cleanly", function()
		local core, _, system, _, pres = world()
		local s = build(core, pres, system)
		-- keyboard: activate Music (toggle on), move down, activate Save
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		expect(s.draft:get()).toBe(true)
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		expect(s.mutation.status:get()).toBe("pending")
		-- pending NEVER implies success
		expect(s.snapshot.binding:get().music).toBe(false)
		-- delayed server: validate, replicate, confirm
		s.snapshot.ingest(2, { music = true })
		s.mutation.confirm(s.envelope().requestId, "ok")
		expect(s.mutation.status:get()).toBe("confirmed")
		expect(s.snapshot.binding:get().music).toBe(true)
		expect(s.draft:get()).toBe(true)
	end)

	it("rejection restores the draft; no permanent pending state", function()
		local core, _, system, _, pres = world()
		local s = build(core, pres, system)
		system.deviceKey("Return", true)
		system.deviceKey("Return", false) -- toggle on
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		system.deviceKey("Return", true)
		system.deviceKey("Return", false) -- save
		expect(s.mutation.status:get()).toBe("pending")
		s.mutation.reject(s.envelope().requestId, "rate-limited")
		expect(s.mutation.status:get()).toBe("rejected")
		expect(s.draft:get()).toBe(false) -- restored to authoritative
		s.mutation.reset()
		expect(s.mutation.status:get()).toBe("idle") -- reusable, not stuck
	end)

	it("one action carries keyboard, touch, and gamepad bindings simultaneously", function()
		local core = LuauUI.newCore()
		local system = LuauUI.newActionSystem(core)
		local ctx = system.createContext({ name = "Multi" })
		local activate = ctx.createAction("Activate", "Bool")
		activate.bind({ keyCode = "Return", displayName = "Enter" })
		activate.bind({ keyCode = "ButtonA", displayName = "A" })
		activate.bind({ uiButton = "SaveTapTarget", displayName = "Tap" })
		local fires = 0
		activate.onPressed(function()
			fires += 1
		end)
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		system.deviceKey("ButtonA", true)
		system.deviceKey("ButtonA", false)
		expect(fires).toBe(2)
		-- hints per device kind, all bindings intact
		expect(activate.preferredBinding("KeyboardAndMouse").displayName).toBe("Enter")
		expect(activate.preferredBinding("Touch").displayName).toBe("Tap")
		expect(#activate.bindings).toBe(3)
	end)
end)
