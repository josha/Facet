--!strict
-- THE OPT-IN, DEFAULT-OFF HAPTICS ADAPTER (`src/client/haptics.luau`;
-- docs/plans/swiftui-parity-round2.md §3.3). It is a SUBSCRIBER to the semantic
-- feedback bus, not part of it: Facet still says what happened and plays
-- nothing (`src/present/feedback.luau:4-5`), and this file proves the framework
-- cannot reach it.
--
-- Every engine fact this module is built on is recorded, with sources, in
-- docs/research/2026-08-12-haptics-engine-facts.md — read that before changing
-- anything here. The three that shape the tests below:
--
--   * `HapticEffect`, never `HapticService:SetMotor` (superseded; SetMotor's
--     range, persistence and zeroing are all undocumented).
--   * There is NO capability API, and the only probe on the platform is boolean
--     and belongs to the superseded service. So the probe is the five-state
--     lattice of docs/lessons/capability-probes-must-be-tri-state.md, with
--     `unknown` — not `false` — for touch and for the pre-first-gamepad state.
--   * `Custom` with no waveform is a GUARANTEED silent no-op, so the enum is
--     resolved defensively by name and never falls back to it.
--
-- WHAT THIS FILE CANNOT PROVE, and does not claim to: that anything is FELT.
-- Roblox documents controllers on macOS 15+ as unsupported, so this machine
-- cannot produce positive device evidence at all. Perceptible feedback on a
-- gamepad, on a phone, and whether the player's own haptics setting silences it
-- are three PENDING_PHYSICAL rows that only a device closes.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")
local haptics = require("../src/client/haptics")
local sensory_profile = require("../src/client/sensory_profile")
local feedbackLib = require("../src/present/feedback")

-- ---- scripted engine ------------------------------------------------------
-- Nothing below touches a real engine: `Instance.new`, `Enum`,
-- `UserInputService` and `HapticService` are all injected, which is the only
-- reason any of this is provable headless.

-- THE FAKE MODELS DESTRUCTION, and that is not a detail. The version this
-- replaced had `function effect:Destroy() end` — a no-op — and no notion of
-- parenting at all, so every lifetime assertion in this file could only ever read
-- the adapter's own counters. A RED-TEAM pass measured what those counters could
-- not see: five enable/disable cycles left fifteen `HapticEffect` instances
-- parented to Workspace while `diagnostics().pooled` reported 0. So the fake now
-- carries the two facts a leak is made of — `Parent` and whether `Destroy()` was
-- called — and `liveEffects` counts the INSTANCES, never the module's opinion of
-- them.
type Log = { constructions: number, destroys: number, plays: number, effects: { any } }

local function newLog(): Log
	return { constructions = 0, destroys = 0, plays = 0, effects = {} }
end

local function fakeInstanceNew(log: Log)
	return function(className: string): any
		log.constructions += 1
		local effect: any = {
			ClassName = className,
			Type = nil,
			Parent = nil,
			played = 0,
			stopped = 0,
			destroyed = false,
			-- THE WAVEFORM, RECORDED. A `Custom` effect that was never handed keys
			-- plays NOTHING while reporting success (research §9), so "was
			-- SetWaveformKeys called, with what, and how many times" is the only
			-- thing that separates a shipped waveform from a silent one.
			waveform = nil :: { any }?,
			keyedTimes = 0,
		}
		function effect:Play()
			log.plays += 1
			effect.played += 1
		end
		function effect:Stop()
			effect.stopped += 1
		end
		function effect:SetWaveformKeys(keys: { any })
			effect.waveform = keys
			effect.keyedTimes += 1
		end
		function effect:Destroy()
			log.destroys += 1
			effect.destroyed = true
			effect.Parent = nil -- what the engine does: out of the DataModel
		end
		table.insert(log.effects, effect)
		return effect
	end
end

-- the engine's `FloatCurveKey.new(timeMs, intensity, Enum.KeyInterpolationMode)`,
-- as a plain record so a spec can read back exactly what was authored
local function fakeFloatCurveKey(timeMs: number, intensity: number, mode: any): any
	return { timeMs = timeMs, intensity = intensity, mode = mode }
end

-- the count that cannot inherit the bug: instances that were built, parented, and
-- never destroyed — read off the instances themselves
local function liveEffects(log: Log): number
	local n = 0
	for _, effect in log.effects do
		if not effect.destroyed and effect.Parent ~= nil then
			n += 1
		end
	end
	return n
end

-- a stand-in for Workspace, so the effects this file builds are actually
-- PARENTED. Without it `resolveParent` finds no `game` under Lune and every
-- effect sits unparented, which is precisely the state a leak check must not
-- measure from.
local function fakeWorkspace(): any
	return { Name = "Workspace" }
end

-- the six real `Enum.HapticEffectType` members (API dump, client 0.734.0.7340915)
-- plus `Enum.KeyInterpolationMode`'s three, which a Custom waveform's keys need.
-- A caller that narrows `members` narrows the EFFECT TYPES only when it also
-- narrows the modes: the two enums fail independently on a real client and the
-- fixture has to be able to say which one is missing.
local function fakeEnums(members: { string }?, modes: { string }?): any
	local set: any = {}
	for _, name in
		members or { "Custom", "UIHover", "UIClick", "UINotification", "GameplayExplosion", "GameplayCollision" }
	do
		set[name] = `Enum.HapticEffectType.{name}`
	end
	local modeSet: any = {}
	for _, name in modes or { "Constant", "Linear", "Cubic" } do
		modeSet[name] = `Enum.KeyInterpolationMode.{name}`
	end
	return { HapticEffectType = set, KeyInterpolationMode = modeSet }
end

local function fakeSignal(): any
	local subs: { (any) -> () } = {}
	local signal: any = {}
	function signal:Connect(fn: (any) -> ()): any
		table.insert(subs, fn)
		return {
			Disconnect = function()
				local i = table.find(subs, fn)
				if i ~= nil then
					table.remove(subs, i)
				end
			end,
		}
	end
	function signal.fire(value: any)
		for _, fn in table.clone(subs) do
			fn(value)
		end
	end
	function signal.count(): number
		return #subs
	end
	return signal
end

-- a scripted UserInputService: `pads` is the live connected-gamepad list, so a
-- test hot-plugs by mutating it and firing the matching event
local function fakeInputService(pads: { any }?): any
	local uis: any = {
		TouchEnabled = false,
		GamepadEnabled = false,
		GamepadConnected = fakeSignal(),
		GamepadDisconnected = fakeSignal(),
		LastInputTypeChanged = fakeSignal(),
		pads = pads or {},
	}
	function uis:GetConnectedGamepads(): { any }
		return uis.pads
	end
	return uis
end

-- the SUPERSEDED service, used for nothing but its boolean probe
local function fakeHapticService(answer: any): any
	local hs: any = { asked = 0 }
	function hs:IsVibrationSupported(_pad: any): boolean
		hs.asked += 1
		return answer
	end
	return hs
end

-- ---- the surface under the adapter ---------------------------------------
-- Module-level rather than describe-local: the lifetime cases below attach and
-- detach the same shapes the property-route cases do, and two copies of a fake
-- engine is two chances for them to disagree about what a surface is.
local function fakeButton(name: string): any
	-- `attribute` is the author's declared activation verb as the renderer
	-- publishes it (`Facet_ActivationFeedback`); `Active`/`Interactable` are what
	-- `enabled = false` writes on a real Facet TextButton
	-- (src/client/screen_target.luau). Both are absent by default, which is what an
	-- ordinary enabled, undeclared button looks like.
	local inst: any = {
		Name = name,
		HoverHapticEffect = nil,
		PressHapticEffect = nil,
		descendants = {},
		attribute = nil :: string?,
	}
	function inst:IsA(className: string): boolean
		return className == "GuiButton"
	end
	function inst:GetAttribute(_name: string): any
		return inst.attribute
	end
	return inst
end

local function fakeFrame(name: string): any
	local inst: any = { Name = name, descendants = {} }
	function inst:IsA(): boolean
		return false
	end
	return inst
end

-- `sweeps` counts GetDescendants calls, which is how the "a detach does not
-- re-walk the survivors" case measures the O(live roots x descendants) cost that
-- used to be paid on every dismissal. `destroy()` fires the engine's own
-- `Destroying` — the detach nobody wrote.
local function fakeRoot(children: { any }): any
	local root: any =
		{ Name = "Screen", DescendantAdded = fakeSignal(), Destroying = fakeSignal(), children = children, sweeps = 0 }
	function root:IsA(): boolean
		return false
	end
	function root:GetDescendants(): { any }
		root.sweeps += 1
		return root.children
	end
	function root.add(child: any)
		table.insert(root.children, child)
		root.DescendantAdded.fire(child)
	end
	function root.destroy()
		root.Destroying.fire(root)
	end
	return root
end

-- a bus that behaves exactly like a presenter's (it IS the presenter's bus
-- factory), wrapped in the smallest object `bind` accepts
local function fakePresenter()
	local bus = feedbackLib.new()
	return { onFeedback = bus.subscribe }, bus
end

local function scriptedClock()
	local now = 0
	return {
		now = function(): number
			return now
		end,
		advance = function(dt: number)
			now += dt
		end,
	}
end

-- the standard fully-scripted adapter: an engine that WORKS, so a test that
-- sees nothing played is seeing a decision, not a missing seam
local function rig(opts: any?)
	local log = newLog()
	local clock = scriptedClock()
	local uis = fakeInputService()
	local given = opts or {}
	local adapter = haptics.new({
		enabled = given.enabled,
		now = clock.now,
		profile = given.profile,
		selectIntervalSeconds = given.selectIntervalSeconds,
		adjustIntervalSeconds = given.adjustIntervalSeconds,
		floatCurveKey = if given.floatCurveKey ~= nil then given.floatCurveKey else fakeFloatCurveKey,
		instanceNew = given.instanceNew or fakeInstanceNew(log),
		inputService = given.inputService or uis,
		hapticService = given.hapticService or fakeHapticService(true),
		enums = given.enums or fakeEnums(),
		-- DEFAULTS TO A PARENT, because the module's default is Workspace and an
		-- unparented effect cannot demonstrate the leak this file now measures.
		-- `parent = false` still means "there is none".
		parent = if given.parent ~= nil then given.parent else fakeWorkspace(),
	})
	local presenter, bus = fakePresenter()
	adapter.bind(presenter)
	return adapter, bus, log, clock, uis
end

describe("haptics: default OFF means the engine is never touched", function()
	it("constructs nothing and plays nothing until it is switched on", function()
		local adapter, bus, log = rig() -- no `enabled`
		expect(adapter.isEnabled()).toBe(false)
		for _, verb in feedbackLib.TYPES do
			bus.emit({ type = verb, path = "/S/B" })
		end
		expect(log.constructions).toBe(0)
		expect(log.plays).toBe(0)
		expect(adapter.diagnostics().pooled).toBe(0)
		expect(adapter.diagnostics().plays).toBe(0)
	end)

	it("publishes no platform claim while it is off", function()
		local adapter = rig()
		expect(adapter.support()).toBe("unknown")
		expect(adapter.diagnostics().probes).toBe(0)
	end)

	it("switching it on, then off, stops it again", function()
		local adapter, bus, log = rig()
		adapter.setEnabled(true)
		bus.emit({ type = "select", path = "/S/B" })
		expect(log.plays).toBe(1)
		adapter.setEnabled(false)
		bus.emit({ type = "select", path = "/S/B" })
		expect(log.plays).toBe(1)
	end)
end)

describe("haptics: the map is TOTAL over the twelve verbs", function()
	it("every verb in the taxonomy has an explicit entry — no silent drop", function()
		expect(haptics.unmappedVerbs()).toEqual({})
		-- and the count matches the taxonomy exactly
		local n = 0
		for _ in haptics.MAP do
			n += 1
		end
		expect(n).toBe(#feedbackLib.TYPES)
	end)

	it("the map invents no verb the taxonomy does not have", function()
		expect(haptics.strayVerbs()).toEqual({})
	end)

	it("exactly five verbs map to nothing, and they are the five decided", function()
		local silent: { string } = {}
		for _, verb in feedbackLib.TYPES do
			if haptics.MAP[verb] == false then
				table.insert(silent, verb)
			end
		end
		table.sort(silent)
		expect(silent).toEqual({ "activate", "arrive", "cancel", "dismiss", "supersede" })
	end)

	it("every mapped verb names a REAL HapticEffectType, and never Custom", function()
		for verb, effectType in haptics.MAP do
			if effectType ~= false then
				expect(table.find(haptics.EFFECT_TYPES, effectType) ~= nil).toBeTruthy()
				expect(effectType == "Custom").toBe(false)
				expect(type(verb)).toBe("string")
			end
		end
	end)

	it("`activate` names no preset on the bus — the two edges belong to two owners", function()
		-- the DOWN edge is the engine's, through the button's own press property;
		-- the COMPLETED edge is the release PHASE's. Neither is a MAP row, which is
		-- why this one is `false`.
		expect(haptics.MAP.activate).toBe(false)
		expect(sensory_profile.label(haptics.pressSpecFor(nil))).toBe("contact")
		expect(sensory_profile.label(haptics.pressSpecFor("activate"))).toBe("contact")
		expect(sensory_profile.FALLBACK.press).toBe("UIClick")
	end)

	it("the two verbs the SELECT phase claims are named, and the MAP still covers them", function()
		-- PHASE_VERBS is the precedence rule written down: `select` and `adjust`
		-- play the select phase whatever caused them, so their MAP rows are the
		-- pre-phase record kept for TOTALITY (a thirteenth verb must still surface
		-- as a gap) rather than a live preset choice.
		expect(haptics.PHASE_VERBS).toEqual({ select = "select", adjust = "select" })
		for verb in haptics.PHASE_VERBS do
			expect(type(haptics.MAP[verb])).toBe("string")
			expect(table.find(feedbackLib.TYPES, verb) ~= nil).toBe(true)
		end
	end)

	it("`pressSpecFor` answers the three cases a control can be in", function()
		-- undeclared / `activate` -> the PRESS PHASE; a declared verb -> its mapped
		-- preset; `none` or a silenced verb -> nothing at all
		expect(haptics.pressSpecFor(nil)).toEqual(sensory_profile.DEFAULTS.press)
		expect(haptics.pressSpecFor("commit")).toEqual({ kind = "preset", effect = "UIClick" })
		expect(haptics.pressSpecFor("reject")).toEqual({ kind = "preset", effect = "UINotification" })
		expect(haptics.pressSpecFor(feedbackLib.ACTIVATION_SILENT)).toBeNil()
		expect(haptics.pressSpecFor("cancel")).toBeNil()
		-- and it honours a game's own profile for the undeclared case
		local silenced = sensory_profile.resolve({ press = { kind = "silent" } })
		expect(haptics.pressSpecFor(nil, silenced)).toEqual({ kind = "silent" })
	end)
end)

describe("haptics: what an enabled adapter actually plays", function()
	it("plays one pooled effect per mapped verb, and reuses it forever", function()
		local adapter, bus, log, clock = rig({ enabled = true })
		for _ = 1, 50 do
			for _, verb in feedbackLib.TYPES do
				bus.emit({ type = verb, path = "/S/B" })
			end
			clock.advance(1) -- past the select limiter, so its phase is exercised too
		end
		local mapped, claimed = 0, 0
		for verb, effectType in haptics.MAP do
			if effectType ~= false then
				mapped += 1
				if haptics.PHASE_VERBS[verb] ~= nil then
					claimed += 1
				end
			end
		end
		expect(mapped).toBe(7)
		expect(claimed).toBe(2) -- `select` and `adjust` are the select PHASE's
		-- ONE construction per mapped verb the phases do not claim, plus ONE for the
		-- select phase itself, whatever the fire count (the documented "fewer than
		-- 100 simultaneous effects" budget)
		expect(log.constructions).toBe(mapped - claimed + 1)
		expect(adapter.diagnostics().pooled).toBe(log.constructions)
	end)

	it("the five silent verbs never play, however often they arrive", function()
		local adapter, bus, log = rig({ enabled = true })
		for _ = 1, 20 do
			for _, verb in { "activate", "arrive", "cancel", "dismiss", "supersede" } do
				bus.emit({ type = verb, path = "/S/B" })
			end
		end
		expect(log.constructions).toBe(0)
		expect(log.plays).toBe(0)
		expect(adapter.diagnostics().ignored).toBe(100)
	end)

	it("a played effect carries the resolved enum value, never a bare Custom", function()
		local _, bus, log = rig({ enabled = true })
		bus.emit({ type = "reject", path = "/S/B" })
		expect(#log.effects).toBe(1)
		expect(log.effects[1].ClassName).toBe("HapticEffect")
		expect(log.effects[1].Type).toBe("Enum.HapticEffectType.UINotification")
		expect(log.effects[1].played).toBe(1)
	end)
end)

describe("haptics: `adjust` is rate-limited (a slider is not a buzzsaw)", function()
	it("coalesces a per-tick storm down to one play per interval", function()
		local adapter, bus, log, clock = rig({ enabled = true, adjustIntervalSeconds = 0.06 })
		-- 20 ticks inside 38 ms — a dragged slider inside two 60 fps frames
		for _ = 1, 20 do
			bus.emit({ type = "adjust", path = "/S/Slider" })
			clock.advance(0.002)
		end
		expect(log.plays).toBe(1)
		expect(adapter.diagnostics().coalesced).toBe(19)
	end)

	it("the next tick after the interval plays again", function()
		local _, bus, log, clock = rig({ enabled = true, adjustIntervalSeconds = 0.06 })
		bus.emit({ type = "adjust", path = "/S/Slider" })
		clock.advance(0.02)
		bus.emit({ type = "adjust", path = "/S/Slider" })
		expect(log.plays).toBe(1)
		clock.advance(0.05) -- now 0.07 since the first
		bus.emit({ type = "adjust", path = "/S/Slider" })
		expect(log.plays).toBe(2)
	end)

	it("coalescing DROPS — a swallowed tick never arrives late as a phantom", function()
		local _, bus, log, clock = rig({ enabled = true, adjustIntervalSeconds = 0.06 })
		bus.emit({ type = "adjust", path = "/S/Slider" })
		bus.emit({ type = "adjust", path = "/S/Slider" })
		expect(log.plays).toBe(1)
		clock.advance(10) -- the gesture is long over
		expect(log.plays).toBe(1) -- nothing was deferred to here
	end)

	it("the rate limit is the SELECT PHASE's — discrete verbs are never swallowed", function()
		-- `select` joined `adjust` behind the limiter when the two became one phase
		-- (a list scrubbed with a finger emits `select` per row, not `adjust`), so
		-- the negative control moved to the verbs that are genuinely discrete
		local _, bus, log = rig({ enabled = true })
		for _ = 1, 5 do
			bus.emit({ type = "commit", path = "/S/Buy" })
		end
		expect(log.plays).toBe(5)
	end)
end)

describe("haptics: the capability probe is a LATTICE, never a boolean", function()
	it("touch is `unknown`, not `unsupported` — there is no probe for a phone", function()
		local uis = fakeInputService()
		uis.TouchEnabled = true
		-- the superseded probe answers `false` here, and it means nothing:
		-- there is no gamepad for it to be describing
		local adapter = haptics.new({
			enabled = true,
			inputService = uis,
			hapticService = fakeHapticService(false),
			instanceNew = fakeInstanceNew(newLog()),
			enums = fakeEnums(),
		})
		expect(adapter.support()).toBe("unknown")
	end)

	it("the pre-first-gamepad state is `unknown` too", function()
		local adapter = haptics.new({
			enabled = true,
			inputService = fakeInputService({}),
			hapticService = fakeHapticService(false),
			instanceNew = fakeInstanceNew(newLog()),
			enums = fakeEnums(),
		})
		expect(adapter.support()).toBe("unknown")
	end)

	it("a CONNECTED pad answering false is the one case that means `unsupported`", function()
		local adapter = haptics.new({
			enabled = true,
			inputService = fakeInputService({ "Gamepad1" }),
			hapticService = fakeHapticService(false),
			instanceNew = fakeInstanceNew(newLog()),
			enums = fakeEnums(),
		})
		expect(adapter.support()).toBe("unsupported")
	end)

	it("a connected pad answering true is `supported`", function()
		local adapter = haptics.new({
			enabled = true,
			inputService = fakeInputService({ "Gamepad1" }),
			hapticService = fakeHapticService(true),
			instanceNew = fakeInstanceNew(newLog()),
			enums = fakeEnums(),
		})
		expect(adapter.support()).toBe("supported")
	end)

	it("no input service at all is `unknown`, never a negative claim", function()
		local adapter = haptics.new({
			enabled = true,
			inputService = false, -- explicit "there is none"
			instanceNew = fakeInstanceNew(newLog()),
			enums = fakeEnums(),
		})
		expect(adapter.support()).toBe("unknown")
	end)

	it("re-probes on hot-plug instead of caching the boot answer", function()
		local uis = fakeInputService({})
		local adapter = haptics.new({
			enabled = true,
			inputService = uis,
			hapticService = fakeHapticService(true),
			instanceNew = fakeInstanceNew(newLog()),
			enums = fakeEnums(),
		})
		expect(adapter.support()).toBe("unknown") -- nothing connected yet
		local probesBefore = adapter.diagnostics().probes
		uis.pads = { "Gamepad1" }
		uis.GamepadConnected.fire("Gamepad1")
		expect(adapter.diagnostics().probes).toBeGreaterThan(probesBefore)
		expect(adapter.support()).toBe("supported")
		uis.pads = {}
		uis.GamepadDisconnected.fire("Gamepad1")
		expect(adapter.support()).toBe("unknown")
	end)

	it("re-probes on LastInputTypeChanged as well", function()
		local uis = fakeInputService({})
		local adapter = haptics.new({
			enabled = true,
			inputService = uis,
			hapticService = fakeHapticService(true),
			instanceNew = fakeInstanceNew(newLog()),
			enums = fakeEnums(),
		})
		local before = adapter.diagnostics().probes
		uis.pads = { "Gamepad2" }
		uis.LastInputTypeChanged.fire("Gamepad2")
		expect(adapter.diagnostics().probes).toBeGreaterThan(before)
		expect(adapter.support()).toBe("supported")
	end)

	it("disconnects its device listeners when switched off", function()
		local uis = fakeInputService({})
		local adapter = haptics.new({
			enabled = true,
			inputService = uis,
			hapticService = fakeHapticService(true),
			instanceNew = fakeInstanceNew(newLog()),
			enums = fakeEnums(),
		})
		expect(uis.GamepadConnected.count()).toBe(1)
		adapter.setEnabled(false)
		expect(uis.GamepadConnected.count()).toBe(0)
		expect(uis.LastInputTypeChanged.count()).toBe(0)
	end)
end)

describe("haptics: the enum is resolved defensively, and never falls back", function()
	it("a missing member plays NOTHING rather than a silent `Custom`", function()
		-- exactly the shape that bit this repo game-side: a guessed name made
		-- every tier fall back to the weakest tick, and `Custom` with no waveform
		-- plays nothing at all while reporting success
		local log = newLog()
		local adapter, bus = rig({
			enabled = true,
			instanceNew = fakeInstanceNew(log),
			enums = fakeEnums({ "Custom" }, {}), -- every preset AND every mode missing
		})
		for _, verb in feedbackLib.TYPES do
			bus.emit({ type = verb, path = "/S/B" })
		end
		expect(log.constructions).toBe(0) -- nothing is built for an unresolvable type
		expect(log.plays).toBe(0)
		expect(adapter.diagnostics().enumMisses).toBeGreaterThan(0)
	end)

	it("an enum source that THROWS on index is survived, not propagated", function()
		local exploding: any = setmetatable({}, {
			__index = function()
				error("no such enum")
			end,
		})
		local log = newLog()
		local adapter, bus = rig({ enabled = true, instanceNew = fakeInstanceNew(log), enums = exploding })
		local ok = pcall(function()
			bus.emit({ type = "select", path = "/S/B" })
		end)
		expect(ok).toBe(true)
		expect(log.plays).toBe(0)
		expect(adapter.diagnostics().lastError ~= nil).toBeTruthy()
	end)
end)

describe("haptics: a client without the class degrades, it does not crash", function()
	it("an uncreatable class is `absent`, with the engine's own words kept", function()
		local adapter, bus = rig({
			enabled = true,
			instanceNew = function()
				error('Unable to create an Instance of type "HapticEffect"')
			end,
		})
		local ok = pcall(function()
			bus.emit({ type = "select", path = "/S/B" })
		end)
		expect(ok).toBe(true)
		expect(adapter.support()).toBe("absent")
		expect(string.find(tostring(adapter.diagnostics().lastError), "Unable to create", 1, true) ~= nil).toBeTruthy()
	end)

	it("any other refusal is `blocked` — the two are not the same fact", function()
		local adapter, bus = rig({
			enabled = true,
			instanceNew = function()
				error("The current identity (2) cannot create this instance")
			end,
		})
		pcall(function()
			bus.emit({ type = "select", path = "/S/B" })
		end)
		expect(adapter.support()).toBe("blocked")
	end)

	it("with NO seams injected at all it still never throws (this very process)", function()
		-- there is no engine under Lune: `Instance`, `Enum` and `game` are all
		-- absent, which is the harshest version of "a client without the class"
		local adapter = haptics.new({ enabled = true })
		local presenter, bus = fakePresenter()
		adapter.bind(presenter)
		local ok = pcall(function()
			for _, verb in feedbackLib.TYPES do
				bus.emit({ type = verb, path = "/S/B" })
			end
		end)
		expect(ok).toBe(true)
		expect(adapter.diagnostics().plays).toBe(0)
		expect(adapter.support() == "supported").toBe(false)
	end)
end)

describe("haptics: `activate` takes the PROPERTY route (the engine plays it)", function()
	it("assigns PressHapticEffect and NEVER calls Play", function()
		local adapter, _, log = rig({ enabled = true })
		local button = fakeButton("Go")
		local root = fakeRoot({ button, fakeFrame("Plate") })
		adapter.attachButtons(root)
		expect(button.PressHapticEffect ~= nil).toBeTruthy()
		expect(button.PressHapticEffect.ClassName).toBe("HapticEffect")
		expect(button.PressHapticEffect.Type).toBe("Enum.HapticEffectType.Custom")
		-- the WHOLE point of the property route: the framework hands over a
		-- reference and the engine is the one that plays it
		expect(log.plays).toBe(0)
		expect(button.PressHapticEffect.played).toBe(0)
	end)

	it("leaves HoverHapticEffect alone — a felt cursor is nobody's request", function()
		local adapter = rig({ enabled = true })
		local button = fakeButton("Go")
		adapter.attachButtons(fakeRoot({ button }))
		expect(button.HoverHapticEffect).toBeNil()
	end)

	it("shares ONE press effect across every button on the surface", function()
		local adapter, _, log = rig({ enabled = true })
		local a, b, c = fakeButton("A"), fakeButton("B"), fakeButton("C")
		adapter.attachButtons(fakeRoot({ a, b, c }))
		expect(log.constructions).toBe(1)
		expect(a.PressHapticEffect == b.PressHapticEffect).toBe(true)
		expect(b.PressHapticEffect == c.PressHapticEffect).toBe(true)
	end)

	it("decorates a button that appears later", function()
		local adapter = rig({ enabled = true })
		local root = fakeRoot({})
		adapter.attachButtons(root)
		local late = fakeButton("Late")
		root.add(late)
		expect(late.PressHapticEffect ~= nil).toBeTruthy()
	end)

	it("touches nothing that is not a GuiButton", function()
		local adapter = rig({ enabled = true })
		local plate = fakeFrame("Plate")
		adapter.attachButtons(fakeRoot({ plate }))
		expect((plate :: any).PressHapticEffect).toBeNil()
	end)

	it("assigns nothing at all while the adapter is off", function()
		local adapter, _, log = rig() -- default off
		local button = fakeButton("Go")
		adapter.attachButtons(fakeRoot({ button }))
		expect(button.PressHapticEffect).toBeNil()
		expect(log.constructions).toBe(0)
	end)

	it("switching off CLEARS the references, so the engine stops too", function()
		local adapter = rig({ enabled = true })
		local button = fakeButton("Go")
		adapter.attachButtons(fakeRoot({ button }))
		expect(button.PressHapticEffect ~= nil).toBeTruthy()
		adapter.setEnabled(false)
		expect(button.PressHapticEffect).toBeNil()
		adapter.setEnabled(true)
		expect(button.PressHapticEffect ~= nil).toBeTruthy()
	end)

	it("detaching ONE surface leaves the others decorated", function()
		-- the press effect is shared and the decorated set is one weak set for the
		-- whole adapter, so a naive detach strips every other live surface too
		local adapter = rig({ enabled = true })
		local mine, theirs = fakeButton("Mine"), fakeButton("Theirs")
		local detachMine = adapter.attachButtons(fakeRoot({ mine }))
		adapter.attachButtons(fakeRoot({ theirs }))
		detachMine()
		expect(mine.PressHapticEffect).toBeNil()
		expect(theirs.PressHapticEffect ~= nil).toBeTruthy()
	end)

	it("attaching the same root twice does not double-count or rebuild", function()
		local adapter, _, log = rig({ enabled = true })
		local button = fakeButton("Go")
		local root = fakeRoot({ button })
		adapter.attachButtons(root)
		adapter.attachButtons(root)
		expect(log.constructions).toBe(1)
		expect(adapter.diagnostics().decorated).toBe(1)
	end)

	it("detaching clears them and stops watching for new buttons", function()
		local adapter = rig({ enabled = true })
		local button = fakeButton("Go")
		local root = fakeRoot({ button })
		local detach = adapter.attachButtons(root)
		detach()
		expect(button.PressHapticEffect).toBeNil()
		expect(root.DescendantAdded.count()).toBe(0)
		local late = fakeButton("Late")
		root.add(late)
		expect(late.PressHapticEffect).toBeNil()
	end)
end)

--[[ ===== THE INSTANCE LEDGER ==============================================
	Every case in this block counts INSTANCES — `liveEffects(log)`, read off the
	fake engine's own objects — and never `diagnostics()`. That is the whole
	lesson of the RED-TEAM finding these cases close: the adapter's `pooled`
	counter reported 0 while fifteen `HapticEffect`s sat parented in Workspace, so
	a leak check that consults the module's instrument inherits the module's bug.
	`diagnostics().pooled` is asserted here too, but always AGAINST the instance
	count rather than instead of it.
]]
describe("haptics: an effect is DESTROYED, never merely dropped", function()
	it("five enable/disable cycles leave nothing in the DataModel", function()
		-- the RED-TEAM measurement, verbatim: 5 cycles x 3 mapped verbs. Before the
		-- fix this read constructions=15 destroys=0 live=15 pooled=0.
		local adapter, bus, log = rig()
		for _ = 1, 5 do
			adapter.setEnabled(true)
			for _, verb in { "select", "reject", "land" } do
				bus.emit({ type = verb, path = "/S/B" })
			end
			adapter.setEnabled(false)
		end
		expect(log.constructions).toBe(15)
		expect(log.destroys).toBe(15)
		expect(liveEffects(log)).toBe(0)
		-- and each one was STOPPED before it was destroyed: an effect mid-play must
		-- not outlive the switch, which Destroy alone does not promise
		for _, effect in log.effects do
			expect(effect.stopped >= 1).toBe(true)
		end
		expect(adapter.diagnostics().pooled).toBe(liveEffects(log))
	end)

	it("`pooled` counts what actually exists — the press effect included", function()
		-- THE DIAGNOSTIC IS THE OTHER HALF OF THE DEFECT. `pooled` used to be a
		-- counter maintained beside the pool that had never heard of the press
		-- effect, so it under-reported by one for every decorated surface.
		local adapter, bus, log = rig({ enabled = true })
		bus.emit({ type = "select", path = "/S/B" })
		adapter.attachButtons(fakeRoot({ fakeButton("Go") }))
		expect(liveEffects(log)).toBe(2) -- one pooled verb + one press effect
		expect(adapter.diagnostics().pooled).toBe(2)
		adapter.setEnabled(false)
		expect(liveEffects(log)).toBe(0)
		expect(adapter.diagnostics().pooled).toBe(0)
	end)

	it("dispose destroys the pool AND the press effect", function()
		local adapter, bus, log = rig({ enabled = true })
		bus.emit({ type = "select", path = "/S/B" })
		adapter.attachButtons(fakeRoot({ fakeButton("Go") }))
		expect(liveEffects(log)).toBe(2)
		adapter.dispose()
		expect(liveEffects(log)).toBe(0)
		expect(log.destroys).toBe(log.constructions)
		expect(adapter.diagnostics().pooled).toBe(0)
	end)

	it("disposing an already-OFF adapter destroys nothing twice", function()
		-- `dispose` runs the teardown unconditionally rather than relying on
		-- setEnabled(false), which takes an early return when it is already off —
		-- so the risk this pins is the opposite one: a double Destroy.
		local adapter, bus, log = rig({ enabled = true })
		bus.emit({ type = "select", path = "/S/B" })
		adapter.setEnabled(false)
		expect(log.destroys).toBe(1)
		adapter.dispose()
		adapter.dispose()
		expect(log.destroys).toBe(1)
		expect(liveEffects(log)).toBe(0)
	end)
end)

describe("haptics: a detach is LOCAL", function()
	it("detaching a surface that contributed nothing builds and destroys nothing", function()
		-- the RED-TEAM measurement: three attach/detach round trips on EMPTY guis
		-- used to read constructions=4 destroys=0 live=4, because the global
		-- undecorate dropped the shared press effect (leaking it) and the next
		-- sweep rebuilt one.
		local adapter, _, log = rig({ enabled = true })
		local a, b = fakeButton("A"), fakeButton("B")
		adapter.attachButtons(fakeRoot({ a }))
		adapter.attachButtons(fakeRoot({ b }))
		expect(log.constructions).toBe(1)
		local shared = a.PressHapticEffect
		for _ = 1, 3 do
			adapter.attachButtons(fakeRoot({}))()
		end
		expect(log.constructions).toBe(1)
		expect(log.destroys).toBe(0)
		expect(liveEffects(log)).toBe(1)
		-- the survivors keep the SAME effect object, not a replacement
		expect(a.PressHapticEffect == shared).toBe(true)
		expect(b.PressHapticEffect == shared).toBe(true)
	end)

	it("a detach does not re-walk the surviving roots", function()
		-- the O(live roots x descendants) cost a game attaching per presented
		-- surface (toasts, modals) used to pay on every dismissal
		local adapter = rig({ enabled = true })
		local survivor = fakeRoot({ fakeButton("Keep"), fakeFrame("Plate") })
		adapter.attachButtons(survivor)
		expect(survivor.sweeps).toBe(1) -- its own attach
		local detach = adapter.attachButtons(fakeRoot({ fakeButton("Going") }))
		detach()
		expect(survivor.sweeps).toBe(1) -- and nothing since
	end)

	it("a button under TWO attached roots keeps its reference until the last lets go", function()
		local adapter = rig({ enabled = true })
		local shared = fakeButton("Shared")
		local detachFirst = adapter.attachButtons(fakeRoot({ shared }))
		local detachSecond = adapter.attachButtons(fakeRoot({ shared }))
		detachFirst()
		expect(shared.PressHapticEffect ~= nil).toBeTruthy()
		detachSecond()
		expect(shared.PressHapticEffect).toBeNil()
	end)

	it("a surface DESTROYED without a detach releases its entry", function()
		-- `roots` is a strong list, so a ScreenGui torn down by the game used to be
		-- retained for the process lifetime. `Destroying` is the detach nobody wrote.
		local adapter = rig({ enabled = true })
		local button = fakeButton("Go")
		local root = fakeRoot({ button })
		adapter.attachButtons(root)
		expect(button.PressHapticEffect ~= nil).toBeTruthy()
		root.destroy()
		expect(button.PressHapticEffect).toBeNil()
		expect(root.DescendantAdded.count()).toBe(0)
		expect(root.Destroying.count()).toBe(0)
		expect(adapter.diagnostics().decorated).toBe(0)
	end)

	it("a root with no `Destroying` signal at all still attaches and detaches", function()
		-- the guard degrades: a plain table (or a future engine object without it)
		-- keeps the explicit detach and never throws
		local adapter = rig({ enabled = true })
		local button = fakeButton("Go")
		local bare: any = { Name = "Bare", DescendantAdded = fakeSignal(), children = { button } }
		function bare:IsA(): boolean
			return false
		end
		function bare:GetDescendants(): { any }
			return bare.children
		end
		local detach = adapter.attachButtons(bare)
		expect(button.PressHapticEffect ~= nil).toBeTruthy()
		detach()
		expect(button.PressHapticEffect).toBeNil()
	end)

	it("another writer clearing the property does not leave the button unfelt forever", function()
		-- TWO ADAPTERS ON ONE SURFACE. A's detach clears `PressHapticEffect`; B's
		-- record still says "done", so before the fix B's next sweep skipped the
		-- button and it silently lost its press haptic for the session.
		local logA, logB = newLog(), newLog()
		local function build(log: Log): any
			return haptics.new({
				enabled = true,
				instanceNew = fakeInstanceNew(log),
				enums = fakeEnums(),
				inputService = false,
				hapticService = false,
				parent = fakeWorkspace(),
			})
		end
		local a, b = build(logA), build(logB)
		local button = fakeButton("Go")
		local rootA, rootB = fakeRoot({ button }), fakeRoot({ button })
		local detachA = a.attachButtons(rootA)
		b.attachButtons(rootB)
		local fromB = button.PressHapticEffect
		expect(fromB ~= nil).toBeTruthy()
		detachA() -- A lets go, and takes B's reference with it
		expect(button.PressHapticEffect).toBeNil()
		-- ...and B's record still says "done". The moment B sees this button again
		-- — a recycled instance re-parented under its root, which is exactly what
		-- this framework's instance recycling does — it must RE-READ the property
		-- rather than believe the record and skip it.
		rootB.add(button)
		expect(button.PressHapticEffect ~= nil).toBeTruthy()
		expect(button.PressHapticEffect == fromB).toBe(true)
		expect(logB.constructions).toBe(1) -- restored, never rebuilt
	end)
end)

describe("haptics: an `absent` class is asked exactly once", function()
	it("50 events cost ONE construction attempt, not 50", function()
		local attempts = 0
		local adapter = haptics.new({
			enabled = true,
			instanceNew = function(): any
				attempts += 1
				error("Unable to create an Instance of type HapticEffect")
			end,
			enums = fakeEnums(),
			inputService = false,
			hapticService = false,
		})
		local bus = feedbackLib.new()
		adapter.bind({ onFeedback = bus.subscribe })
		-- `commit` rather than `select`: the select PHASE is rate-limited, and a
		-- coalesced event would make this pass by not asking at all
		for _ = 1, 50 do
			bus.emit({ type = "commit", path = "/S/B" })
		end
		expect(attempts).toBe(1)
		expect(adapter.support()).toBe("absent")
	end)

	it("...and `blocked` is NOT short-circuited — the two verdicts are not the same fact", function()
		-- the negative control. `absent` means the class does not exist on this
		-- client and will not start existing; `blocked` is the "refused for some
		-- other reason" bucket, and this module does not claim to know that it is
		-- permanent.
		local attempts = 0
		local adapter = haptics.new({
			enabled = true,
			instanceNew = function(): any
				attempts += 1
				error("permission denied")
			end,
			enums = fakeEnums(),
			inputService = false,
			hapticService = false,
		})
		local bus = feedbackLib.new()
		adapter.bind({ onFeedback = bus.subscribe })
		for _ = 1, 5 do
			bus.emit({ type = "commit", path = "/S/B" })
		end
		expect(attempts).toBe(5)
		expect(adapter.support()).toBe("blocked")
	end)
end)

describe("haptics: lifetime", function()
	it("unbind stops delivery and leaves the bus clean", function()
		local log = newLog()
		local adapter = haptics.new({
			enabled = true,
			instanceNew = fakeInstanceNew(log),
			enums = fakeEnums(),
			inputService = false,
		})
		local bus = feedbackLib.new()
		local unbind = adapter.bind({ onFeedback = bus.subscribe })
		bus.emit({ type = "select", path = "/S/B" })
		expect(log.plays).toBe(1)
		unbind()
		bus.emit({ type = "select", path = "/S/B" })
		expect(log.plays).toBe(1)
		expect(bus.count()).toBe(0)
	end)

	it("dispose unsubscribes, releases the pool and switches off", function()
		local adapter, bus, log = rig({ enabled = true })
		bus.emit({ type = "select", path = "/S/B" })
		expect(log.plays).toBe(1)
		adapter.dispose()
		bus.emit({ type = "select", path = "/S/B" })
		expect(log.plays).toBe(1)
		expect(adapter.isEnabled()).toBe(false)
		expect(adapter.diagnostics().pooled).toBe(0)
		expect(bus.count()).toBe(0)
	end)

	it("attachButtons AFTER dispose opens no connection for nothing to close", function()
		-- `dispose` drains its lists once and returns early on re-entry, so a
		-- `DescendantAdded` connection opened after it is permanent.
		local adapter, _, log = rig({ enabled = true })
		adapter.dispose()
		local button = fakeButton("Go")
		local root = fakeRoot({ button })
		local detach = adapter.attachButtons(root)
		expect(root.DescendantAdded.count()).toBe(0)
		expect(root.Destroying.count()).toBe(0)
		expect(button.PressHapticEffect).toBeNil()
		expect(log.constructions).toBe(0)
		expect(type(detach)).toBe("function")
		detach() -- and the returned release is safe to call
	end)

	it("bind AFTER dispose opens no subscription for nothing to drain", function()
		local adapter = rig({ enabled = true })
		adapter.dispose()
		local bus = feedbackLib.new()
		local unbind = adapter.bind({ onFeedback = bus.subscribe })
		expect(bus.count()).toBe(0)
		bus.emit({ type = "select", path = "/S/B" })
		expect(adapter.diagnostics().plays).toBe(0)
		unbind()
	end)

	it("binding something that is not a presenter is an authoring error that NAMES the seam", function()
		local adapter = haptics.new()
		-- a bare `toThrow()` here proves nothing: without the guard the call
		-- crashes anyway on a nil `onFeedback`, so the message is the assertion
		local ok, err = pcall(function()
			adapter.bind({} :: any)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "onFeedback", 1, true) ~= nil).toBeTruthy()
		expect(string.find(tostring(err), "haptics.bind", 1, true) ~= nil).toBeTruthy()
	end)
end)

--[[ ===== THE THREE PHASES ==================================================
	Facet's sensory profile (`src/client/sensory_profile.luau`) gives the adapter
	three phases, and each one has a DIFFERENT OWNER of the moment it fires:

	  press    the DOWN edge — the ENGINE's, through `GuiButton.PressHapticEffect`.
	           This module hands over a reference and never calls Play on it.
	  release  the COMPLETED edge — the BUS's. `GuiButton.Activated` only fires when
	           a press completes on the control, so a press dragged away from
	           produces no bus event at all and is silent STRUCTURALLY. There is no
	           cancellation branch in this module, and there must not be one.
	  select   a CHOICE CHANGED — the bus's too, rate-limited leading-edge.

	The double-pulse guard is the consequence of the first two having different
	owners: the bus must never replay the DOWN edge, and it no longer needs to drop
	the completed one to avoid doing so.
]]
describe("haptics: the press phase is the ENGINE's, and it is the Facet waveform", function()
	it("an undeclared button gets the Custom `contact` effect, keyed exactly once", function()
		local adapter, _, log = rig({ enabled = true })
		local button = fakeButton("Go")
		adapter.attachButtons(fakeRoot({ button }))
		local effect = button.PressHapticEffect
		expect(effect ~= nil).toBeTruthy()
		expect(effect.Type).toBe("Enum.HapticEffectType.Custom")
		expect(effect.keyedTimes).toBe(1)
		-- the keys are the product, byte for byte, in the engine's own argument
		-- order (time ms, intensity 0..1, interpolation mode)
		expect(effect.waveform).toEqual({
			{ timeMs = 0, intensity = 0, mode = "Enum.KeyInterpolationMode.Linear" },
			{ timeMs = 6, intensity = 0.9, mode = "Enum.KeyInterpolationMode.Cubic" },
			{ timeMs = 30, intensity = 0, mode = "Enum.KeyInterpolationMode.Linear" },
		})
		-- ...and STILL nobody here played it
		expect(log.plays).toBe(0)
		expect(effect.played).toBe(0)
	end)

	it("a control's DECLARED verb still selects its mapped preset, exactly as before", function()
		local adapter = rig({ enabled = true })
		local buy, delete, mute = fakeButton("Buy"), fakeButton("Delete"), fakeButton("Mute")
		buy.attribute, delete.attribute, mute.attribute = "commit", "reject", "none"
		adapter.attachButtons(fakeRoot({ buy, delete, mute }))
		expect(buy.PressHapticEffect.Type).toBe("Enum.HapticEffectType.UIClick")
		expect(delete.PressHapticEffect.Type).toBe("Enum.HapticEffectType.UINotification")
		expect(mute.PressHapticEffect).toBeNil()
		-- a preset carries NO waveform: `SetWaveformKeys` on a non-Custom effect
		-- would be a write the engine ignores and a reader would misread
		expect(buy.PressHapticEffect.keyedTimes).toBe(0)
	end)

	it("the phase waveform is built ONCE however many buttons want it", function()
		local adapter, _, log = rig({ enabled = true })
		local a, b, c = fakeButton("A"), fakeButton("B"), fakeButton("C")
		adapter.attachButtons(fakeRoot({ a, b, c }))
		expect(log.constructions).toBe(1)
		expect(log.effects[1].keyedTimes).toBe(1)
		expect(a.PressHapticEffect == c.PressHapticEffect).toBe(true)
	end)

	it("a DISABLED control is skipped, and a control that BECOMES disabled is cleared", function()
		-- `enabled = false` on a Facet Button writes `Active = false` (and
		-- `Interactable = false` under native styling) — src/client/screen_target.luau.
		-- A disabled affordance that still holds a press effect is a promise the
		-- control does not keep.
		local adapter = rig({ enabled = true })
		local off, on = fakeButton("Off"), fakeButton("On")
		off.Active = false
		local root = fakeRoot({ off, on })
		adapter.attachButtons(root)
		expect(off.PressHapticEffect).toBeNil()
		expect(on.PressHapticEffect ~= nil).toBeTruthy()
		-- ...and the other direction: decorated, then disabled, then re-swept
		on.Interactable = false
		adapter.setEnabled(false)
		adapter.setEnabled(true) -- re-sweeps every attached root
		expect(on.PressHapticEffect).toBeNil()
		expect(adapter.diagnostics().decorated).toBe(0)
	end)

	it("a remount re-decorates idempotently — no duplicate effect, no second key write", function()
		local adapter, _, log = rig({ enabled = true })
		local button = fakeButton("Go")
		local root = fakeRoot({ button })
		adapter.attachButtons(root)
		local first = button.PressHapticEffect
		for _ = 1, 5 do
			root.add(button) -- the same instance re-parented, as recycling does
		end
		expect(button.PressHapticEffect == first).toBe(true)
		expect(log.constructions).toBe(1)
		expect(first.keyedTimes).toBe(1)
		expect(adapter.diagnostics().decorated).toBe(1)
	end)
end)

describe("haptics: the release phase is the COMPLETED edge, and it is new", function()
	it("a completed activation plays `settle` — once, on the pooled release effect", function()
		local adapter, bus, log = rig({ enabled = true })
		bus.emit({ type = "activate", path = "/S/Go", reason = "activation" })
		expect(log.plays).toBe(1)
		expect(#log.effects).toBe(1)
		expect(log.effects[1].Type).toBe("Enum.HapticEffectType.Custom")
		expect(log.effects[1].waveform).toEqual({
			{ timeMs = 0, intensity = 0, mode = "Enum.KeyInterpolationMode.Linear" },
			{ timeMs = 10, intensity = 0.5, mode = "Enum.KeyInterpolationMode.Cubic" },
			{ timeMs = 34, intensity = 0, mode = "Enum.KeyInterpolationMode.Linear" },
		})
		expect(adapter.diagnostics().phases.release.plays).toBe(1)
		expect(adapter.diagnostics().phases.press.plays).toBe(0)
	end)

	it("ONE pulse per cause: fifty completed activations build one effect and play fifty", function()
		local adapter, bus, log = rig({ enabled = true })
		for _ = 1, 50 do
			bus.emit({ type = "activate", path = "/S/Go", reason = "activation" })
		end
		expect(log.constructions).toBe(1) -- flat: zero per-pulse allocation
		expect(log.plays).toBe(50)
		expect(log.effects[1].played).toBe(50)
		expect(log.effects[1].keyedTimes).toBe(1) -- the waveform is written at BUILD
		expect(adapter.diagnostics().pooled).toBe(1)
	end)

	it("A CANCELED PRESS IS SILENT STRUCTURALLY — there is no bus completion to hear", function()
		--[[ The engine plays the down edge through the button's own property; a
			press dragged away from never fires `Activated`, so the presenter emits
			NOTHING and this module is not asked. That is the proof: not a branch that
			recognises a cancel, but the ABSENCE of any event to act on. This case
			asserts the absence, and the mutation that would break it — special-casing
			a cancel here — would have to invent an event first. ]]
		local adapter, bus, log = rig({ enabled = true })
		local button = fakeButton("Go")
		adapter.attachButtons(fakeRoot({ button }))
		local pressBuilt = log.constructions
		-- the down edge happened (the engine holds the reference) and nothing
		-- completed: no `reason = "activation"` event is ever emitted
		expect(button.PressHapticEffect ~= nil).toBeTruthy()
		expect(log.plays).toBe(0)
		expect(adapter.diagnostics().phases.release.plays).toBe(0)
		-- and an explicit `cancel` verb — which a GAME may emit for its own reasons
		-- — stays as silent as it has always been
		bus.emit({ type = "cancel", path = "/S/Go" })
		expect(log.plays).toBe(0)
		expect(log.constructions).toBe(pressBuilt)
	end)

	it("the bus NEVER replays the down edge: no activation event plays the press effect", function()
		local adapter, bus, log = rig({ enabled = true })
		local button = fakeButton("Go")
		adapter.attachButtons(fakeRoot({ button }))
		local pressEffect = button.PressHapticEffect
		for _, verb in { "activate", "commit", "reject", "pickup", "land", "celebrate" } do
			bus.emit({ type = verb, path = "/S/Go", reason = "activation" })
		end
		expect(pressEffect.played).toBe(0) -- the engine's instance, untouched
		expect(adapter.diagnostics().phases.press.plays).toBe(0)
		-- six completed activations, six release pulses, one release instance
		expect(adapter.diagnostics().phases.release.plays).toBe(6)
		expect(log.plays).toBe(6)
	end)

	it("an input-method switch mid-press is at most one press + one release", function()
		--[[ The presenter collapses the keyboard/gamepad Activate and the engine's
			echoing `GuiButton.Activated` into ONE dispatch (its ACTIVATE_ECHO_WINDOW),
			so however the press started and however it finished, this module hears one
			completion. What it must never do is turn that one completion into two
			pulses of its own. ]]
		local adapter, bus, log = rig({ enabled = true })
		local button = fakeButton("Go")
		adapter.attachButtons(fakeRoot({ button }))
		bus.emit({ type = "activate", path = "/S/Go", reason = "activation", context = { source = "action" } })
		expect(log.plays).toBe(1)
		expect(button.PressHapticEffect.played).toBe(0)
		-- ...and a clean silence is the other legal outcome: a control the author
		-- silenced completes without a sound on either edge
		local quiet = fakeButton("Mute")
		quiet.attribute = "none"
		adapter.attachButtons(fakeRoot({ quiet }))
		expect(quiet.PressHapticEffect).toBeNil()
		bus.emit({ type = "cancel", path = "/S/Mute", reason = "activation" })
		expect(log.plays).toBe(1)
		expect(adapter.diagnostics().ignored).toBeGreaterThan(0)
	end)

	it("a control whose verb the MAP silences is unfelt on BOTH edges", function()
		local adapter, bus, log = rig({ enabled = true })
		for _, verb in { "cancel", "arrive", "dismiss", "supersede" } do
			bus.emit({ type = verb, path = "/S/X", reason = "activation" })
		end
		expect(log.plays).toBe(0)
		expect(log.constructions).toBe(0)
		expect(adapter.diagnostics().phases.release.plays).toBe(0)
	end)

	it("focus movement alone fires nothing — moving is not activating", function()
		local adapter, bus, log = rig({ enabled = true })
		local button = fakeButton("Go")
		adapter.attachButtons(fakeRoot({ button }))
		local before = log.constructions
		-- the presenter emits NO feedback verb for a focus move; the closest thing
		-- on the bus is an `arrive`, which is silent by decision
		for _ = 1, 20 do
			bus.emit({ type = "arrive", path = "/S/Go" })
		end
		expect(log.plays).toBe(0)
		expect(log.constructions).toBe(before)
	end)
end)

describe("haptics: the select phase, and its leading-edge coalescing", function()
	it("`select` and `adjust` both play the pooled `tick` — one instance for the two", function()
		local adapter, bus, log, clock = rig({ enabled = true })
		bus.emit({ type = "select", path = "/S/Row" })
		clock.advance(1)
		bus.emit({ type = "adjust", path = "/S/Slider" })
		expect(log.constructions).toBe(1)
		expect(log.effects[1].Type).toBe("Enum.HapticEffectType.Custom")
		expect(log.effects[1].waveform).toEqual({
			{ timeMs = 0, intensity = 0, mode = "Enum.KeyInterpolationMode.Linear" },
			{ timeMs = 4, intensity = 0.35, mode = "Enum.KeyInterpolationMode.Linear" },
			{ timeMs = 16, intensity = 0, mode = "Enum.KeyInterpolationMode.Linear" },
		})
		expect(adapter.diagnostics().phases.select.plays).toBe(2)
	end)

	it("the two verbs share ONE limiter — a scrubbed picker cannot alternate past it", function()
		-- the defect a per-verb limiter would ship: a control emitting `select` and
		-- `adjust` alternately would pass both limiters and fire at full rate
		local adapter, bus, log, clock = rig({ enabled = true, selectIntervalSeconds = 0.05 })
		for _ = 1, 10 do
			bus.emit({ type = "select", path = "/S/Row" })
			bus.emit({ type = "adjust", path = "/S/Slider" })
			clock.advance(0.002)
		end
		expect(log.plays).toBe(1)
		expect(adapter.diagnostics().coalesced).toBe(19)
	end)

	it("the default floor is at least the 50 ms the design asks for", function()
		expect(haptics.DEFAULT_SELECT_INTERVAL).toBeGreaterThanOrEqual(0.05)
	end)

	it("a hold-to-repeat stepper fires SELECT pulses and never press or release", function()
		local adapter, bus, log, clock = rig({ enabled = true, selectIntervalSeconds = 0.05 })
		-- a held +/- repeating at 20 Hz for a second: the value changes, so the
		-- author's change-form declaration emits `adjust` — never an activation
		for _ = 1, 20 do
			bus.emit({ type = "adjust", path = "/S/Stepper" })
			clock.advance(0.06)
		end
		local diagnostics = adapter.diagnostics()
		expect(diagnostics.phases.select.plays).toBe(20)
		expect(diagnostics.phases.press.plays).toBe(0)
		expect(diagnostics.phases.release.plays).toBe(0)
		expect(log.constructions).toBe(1) -- one instance for twenty pulses
	end)

	it("a suppressed pulse is DROPPED, never deferred — advance the clock and nothing arrives", function()
		local _, bus, log, clock = rig({ enabled = true, selectIntervalSeconds = 0.05 })
		bus.emit({ type = "select", path = "/S/Row" })
		bus.emit({ type = "select", path = "/S/Row" })
		bus.emit({ type = "adjust", path = "/S/Row" })
		expect(log.plays).toBe(1)
		clock.advance(10) -- the gesture is long over
		expect(log.plays).toBe(1) -- nothing was queued behind it
	end)

	it("passive pointer hover never reaches the select phase", function()
		-- hover is the ENGINE's `HoverHapticEffect`, which this module deliberately
		-- leaves unassigned; nothing a hover produces is on the feedback bus at all
		local adapter = rig({ enabled = true })
		local button = fakeButton("Go")
		adapter.attachButtons(fakeRoot({ button }))
		expect(button.HoverHapticEffect).toBeNil()
		expect(adapter.diagnostics().phases.select.plays).toBe(0)
	end)

	it("a DISCRETE verb is never swallowed by the select limiter", function()
		local _, bus, log = rig({ enabled = true })
		for _ = 1, 5 do
			bus.emit({ type = "commit", path = "/S/Buy" })
			bus.emit({ type = "land", path = "/S/Slot" })
		end
		expect(log.plays).toBe(10)
	end)
end)

describe("haptics: a game's own profile, per phase", function()
	it("replacing ONE phase leaves the other two on the Facet defaults", function()
		local mine = {
			kind = "custom" :: any,
			name = "thud",
			keys = { { timeMs = 0, intensity = 0.7, mode = "Constant" } },
		}
		local adapter, bus, log = rig({ enabled = true, profile = { release = mine } })
		bus.emit({ type = "activate", path = "/S/Go", reason = "activation" })
		expect(log.effects[1].waveform).toEqual({
			{ timeMs = 0, intensity = 0.7, mode = "Enum.KeyInterpolationMode.Constant" },
		})
		expect(adapter.diagnostics().phases.release.effect).toBe("thud")
		expect(adapter.diagnostics().phases.press.effect).toBe("contact")
		expect(adapter.diagnostics().phases.select.effect).toBe("tick")
	end)

	it("a phase swapped for a PRESET needs no waveform at all", function()
		local adapter, bus, log =
			rig({ enabled = true, profile = { select = { kind = "preset", effect = "UIHover" } } })
		bus.emit({ type = "select", path = "/S/Row" })
		expect(log.effects[1].Type).toBe("Enum.HapticEffectType.UIHover")
		expect(log.effects[1].keyedTimes).toBe(0)
		expect(adapter.diagnostics().phases.select.effect).toBe("UIHover")
	end)

	it("a SILENCED phase builds nothing and plays nothing — without touching a control", function()
		local adapter, bus, log = rig({ enabled = true, profile = { release = { kind = "silent" } } })
		local button = fakeButton("Go")
		adapter.attachButtons(fakeRoot({ button }))
		local afterPress = log.constructions
		for _ = 1, 10 do
			bus.emit({ type = "activate", path = "/S/Go", reason = "activation" })
		end
		expect(log.constructions).toBe(afterPress) -- nothing new was built for release
		expect(adapter.diagnostics().phases.release.plays).toBe(0)
		expect(adapter.diagnostics().phases.release.effect).toBeNil()
		-- ...and the press property is untouched by the release decision
		expect(button.PressHapticEffect ~= nil).toBeTruthy()
	end)

	it("silencing PRESS clears the property route and leaves the other phases alone", function()
		local adapter, bus, log = rig({ enabled = true, profile = { press = { kind = "silent" } } })
		local button = fakeButton("Go")
		adapter.attachButtons(fakeRoot({ button }))
		expect(button.PressHapticEffect).toBeNil()
		expect(log.constructions).toBe(0)
		bus.emit({ type = "activate", path = "/S/Go", reason = "activation" })
		expect(log.plays).toBe(1) -- release still answers
	end)

	it("an unknown phase name in a game's profile is an authoring error at CONSTRUCTION", function()
		local ok = pcall(function()
			return haptics.new({ profile = { hover = { kind = "silent" } } :: any })
		end)
		expect(ok).toBe(false)
	end)
end)

describe("haptics: the FALLBACK when a Custom effect will not build", function()
	it("a client with no KeyInterpolationMode gets the phase's PRESET, and says so", function()
		-- the honest degrade: `Custom` with no waveform is a guaranteed silence, so
		-- the phase falls back to a real preset rather than shipping a quiet lie
		local log = newLog()
		local adapter, bus = rig({
			enabled = true,
			instanceNew = fakeInstanceNew(log),
			enums = fakeEnums(nil, {}), -- every interpolation mode missing
		})
		bus.emit({ type = "activate", path = "/S/Go", reason = "activation" })
		expect(log.constructions).toBe(1)
		expect(log.effects[1].Type).toBe("Enum.HapticEffectType.UIHover") -- release's fallback
		expect(log.effects[1].keyedTimes).toBe(0)
		expect(log.plays).toBe(1)
		local phases = adapter.diagnostics().phases
		expect(phases.release.fallbackActive).toBe(true)
		expect(phases.release.effect).toBe("UIHover")
		-- ...and a phase nobody asked for yet has not been decided either way
		expect(phases.select.fallbackActive).toBe(false)
	end)

	it("under fallback, release and select SHARE UIHover and press keeps UIClick", function()
		local log = newLog()
		local adapter, bus, _, clock = rig({
			enabled = true,
			instanceNew = fakeInstanceNew(log),
			enums = fakeEnums(nil, {}),
		})
		local button = fakeButton("Go")
		adapter.attachButtons(fakeRoot({ button }))
		bus.emit({ type = "activate", path = "/S/Go", reason = "activation" })
		clock.advance(1)
		bus.emit({ type = "select", path = "/S/Row" })
		expect(button.PressHapticEffect.Type).toBe("Enum.HapticEffectType.UIClick")
		local phases = adapter.diagnostics().phases
		expect(phases.press.effect).toBe("UIClick")
		expect(phases.release.effect).toBe("UIHover")
		expect(phases.select.effect).toBe("UIHover")
		-- THE LIMITATION, MEASURED: the two quiet phases are ONE Instance under
		-- fallback, distinct only by cause. Three phases, two effects.
		expect(log.constructions).toBe(2)
	end)

	it("with no fallback available either, the phase is silent and nothing throws", function()
		local log = newLog()
		local adapter, bus = rig({
			enabled = true,
			instanceNew = fakeInstanceNew(log),
			enums = fakeEnums({ "Custom" }, {}), -- no presets AND no modes
		})
		local ok = pcall(function()
			bus.emit({ type = "activate", path = "/S/Go", reason = "activation" })
		end)
		expect(ok).toBe(true)
		expect(log.constructions).toBe(0)
		expect(log.plays).toBe(0)
		expect(adapter.diagnostics().enumMisses).toBeGreaterThan(0)
	end)
end)

describe("haptics: the pool is BOUNDED, and the Instances are the evidence", function()
	it("every phase and every verb at once stays far under the platform's 100 cap", function()
		local adapter, bus, log, clock = rig({ enabled = true })
		local button = fakeButton("Go")
		adapter.attachButtons(fakeRoot({ button, fakeButton("Two"), fakeButton("Three") }))
		for _ = 1, 40 do
			for _, verb in feedbackLib.TYPES do
				bus.emit({ type = verb, path = "/S/B" })
				bus.emit({ type = verb, path = "/S/B", reason = "activation" })
			end
			clock.advance(1)
		end
		-- ONE Instance per distinct phase spec, plus one per mapped VERB the phases
		-- do not claim. Nothing about the fire count changes it.
		local phaseSpecs = 3 -- contact / settle / tick
		local verbEffects = 0
		for verb, effectType in haptics.MAP do
			if effectType ~= false and haptics.PHASE_VERBS[verb] == nil then
				verbEffects += 1
			end
		end
		expect(verbEffects).toBe(5)
		expect(liveEffects(log)).toBe(phaseSpecs + verbEffects)
		expect(adapter.diagnostics().pooled).toBe(liveEffects(log))
		expect(liveEffects(log) < 100).toBe(true)
	end)

	it("teardown destroys every phase effect too — Instances, not the module's opinion", function()
		local adapter, bus, log, clock = rig({ enabled = true })
		adapter.attachButtons(fakeRoot({ fakeButton("Go") }))
		bus.emit({ type = "activate", path = "/S/Go", reason = "activation" })
		clock.advance(1)
		bus.emit({ type = "select", path = "/S/Row" })
		bus.emit({ type = "commit", path = "/S/Buy" })
		expect(liveEffects(log)).toBe(4) -- press, release, select, commit
		adapter.dispose()
		expect(liveEffects(log)).toBe(0)
		expect(log.destroys).toBe(log.constructions)
		expect(adapter.diagnostics().pooled).toBe(0)
		for _, effect in log.effects do
			expect(effect.stopped >= 1).toBe(true)
		end
	end)

	it("five enable/disable cycles across all three phases leave nothing behind", function()
		local adapter, bus, log, clock = rig()
		for _ = 1, 5 do
			adapter.setEnabled(true)
			adapter.attachButtons(fakeRoot({ fakeButton("Go") }))()
			bus.emit({ type = "activate", path = "/S/Go", reason = "activation" })
			clock.advance(1)
			bus.emit({ type = "select", path = "/S/Row" })
			adapter.setEnabled(false)
		end
		expect(liveEffects(log)).toBe(0)
		expect(log.destroys).toBe(log.constructions)
		expect(adapter.diagnostics().pooled).toBe(0)
	end)
end)

describe("haptics: the timing is the CONTROL PATH's, and this module adds no listener", function()
	it("no raw-input API is reached for a press, a release or a select", function()
		--[[ The four input classes (pointer, touch, keyboard, gamepad) each resolve
			their activation ONCE, in the presenter/responder path, and this module
			consumes the events that come out. A second listener here would be a second
			opinion about when a press happened — the exact shape the input inventory
			at artifacts/release-candidate-review/input/ias-inventory.md exists to
			bound. So: `ContextActionService` never appears, and `UserInputService`
			appears exactly ONCE, as the string handed to `GetService` for the DEVICE
			PROBE (which is a capability question, not an input one). ]]
		-- COMMENTS STRIPPED FIRST: the header explains what `UserInputService` is
		-- and is not used for, and a scan that matched the prose would fail on the
		-- documentation and pass on a file whose documentation was deleted.
		local raw = fs.readFile("src/client/haptics.luau")
		local source = string.gsub(raw, "%-%-%[%[.-%]%]", "")
		source = string.gsub(source, "\n%s*%-%-[^\n]*", "\n")
		local uisMentions, uisProbeCalls = 0, 0
		for _ in string.gmatch(source, "UserInputService") do
			uisMentions += 1
		end
		for _ in string.gmatch(source, 'service%(options%.inputService, "UserInputService"%)') do
			uisProbeCalls += 1
		end
		-- TWO mentions, and BOTH are the device probe's own seam (the probe itself
		-- and the hot-plug listener it re-runs on). The equality is the assertion: a
		-- third use in any other shape moves one count and not the other.
		expect(uisMentions).toBe(2)
		expect(uisProbeCalls).toBe(uisMentions)
		for _, banned in
			{
				"ContextActionService",
				"BindAction",
				"InputBegan",
				"InputEnded",
				"InputChanged",
				"TouchTap",
				"TouchLongPress",
				"IsKeyDown",
				"GetMouseLocation",
				"MouseButton1",
			}
		do
			expect(`{banned}:{string.find(source, banned, 1, true) ~= nil}`).toBe(`{banned}:false`)
		end
		-- ...and the ONLY UserInputService members it touches are the gamepad
		-- roster and the three device-change signals it re-probes on
		local methods: { string } = {}
		for member in string.gmatch(source, "uis:([%a]+)%(") do
			table.insert(methods, member)
		end
		expect(methods).toEqual({ "GetConnectedGamepads" })
		local events = string.match(source, "for _, eventName in (%b{})")
		expect(events).toBe('{ "GamepadConnected", "GamepadDisconnected", "LastInputTypeChanged" }')
	end)

	it("the profile module is engine-free and the adapter is the only file that builds keys", function()
		expect(string.find(fs.readFile("src/client/sensory_profile.luau"), "SetWaveformKeys", 1, true)).toBeNil()
		local adapterSource = fs.readFile("src/client/haptics.luau")
		local keyed = 0
		for _ in string.gmatch(adapterSource, "SetWaveformKeys") do
			keyed += 1
		end
		-- exactly one CALL SITE (plus the comments that explain it), so a waveform
		-- can only ever be written where the pool is built
		local calls = 0
		for _ in string.gmatch(adapterSource, ":SetWaveformKeys%(") do
			calls += 1
		end
		expect(calls).toBe(1)
		expect(keyed >= calls).toBe(true)
	end)
end)

describe("haptics: the framework cannot reach it", function()
	local ENGINE_SYMBOLS = { "HapticEffect", "HapticService", "SetMotor", "VibrationMotor" }

	local function luauFiles(dir: string, out: { string })
		for _, name in fs.readDir(dir) do
			local path = `{dir}/{name}`
			if fs.isDir(path) then
				luauFiles(path, out)
			elseif string.sub(name, -5) == ".luau" then
				table.insert(out, path)
			end
		end
		return out
	end

	it("no haptics symbol exists anywhere outside src/client", function()
		local offenders: { string } = {}
		for _, path in luauFiles("src", {}) do
			if string.sub(path, 1, 11) == "src/client/" then
				continue
			end
			local source = fs.readFile(path)
			for _, symbol in ENGINE_SYMBOLS do
				if string.find(source, symbol, 1, true) ~= nil then
					table.insert(offenders, `{path}: {symbol}`)
				end
			end
			-- a REQUIRE of the adapter, not a comment that names it: the boundary
			-- rule is about the require graph
			for call in string.gmatch(source, "require%b()") do
				if string.find(call, "haptics", 1, true) ~= nil then
					table.insert(offenders, `{path}: requires the adapter`)
				end
			end
		end
		expect(offenders).toEqual({})
	end)

	it("src/present and src/layout in particular are clean", function()
		local offenders: { string } = {}
		for _, dir in { "src/present", "src/layout" } do
			for _, path in luauFiles(dir, {}) do
				local source = fs.readFile(path)
				for _, symbol in ENGINE_SYMBOLS do
					if string.find(source, symbol, 1, true) ~= nil then
						table.insert(offenders, `{path}: {symbol}`)
					end
				end
			end
		end
		expect(offenders).toEqual({})
	end)

	it("the shared/server-safe entry point does not export it", function()
		-- src/init.luau is the module a server require graph may reach
		-- (UI-BOUND-001); an engine adapter behind it would be a boundary break
		local Facet = require("../src") :: any
		expect(Facet.haptics).toBeNil()
		expect(string.find(fs.readFile("src/init.luau"), "haptic", 1, true)).toBeNil()
	end)

	it("the adapter itself calls Play only on a POOLED effect, never on a button's", function()
		-- a structural pin on the property route: the one `:Play(` call site in
		-- the module is the bus path. If a future edit plays the press effect
		-- itself, "Facet plays nothing" stops being literally true.
		local source = fs.readFile("src/client/haptics.luau")
		local plays = 0
		for _ in string.gmatch(source, ":Play%(%)") do
			plays += 1
		end
		expect(plays).toBe(1)
	end)
end)
