--!strict
-- THE OPT-IN, DEFAULT-OFF HAPTICS ADAPTER (`src/client/haptics.luau`;
-- docs/plans/swiftui-parity-round2.md §3.3). It is a SUBSCRIBER to the semantic
-- feedback bus, not part of it: LuauUI still says what happened and plays
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
local feedbackLib = require("../src/present/feedback")

-- ---- scripted engine ------------------------------------------------------
-- Nothing below touches a real engine: `Instance.new`, `Enum`,
-- `UserInputService` and `HapticService` are all injected, which is the only
-- reason any of this is provable headless.

type Log = { constructions: number, plays: number, effects: { any } }

local function newLog(): Log
	return { constructions = 0, plays = 0, effects = {} }
end

local function fakeInstanceNew(log: Log)
	return function(className: string): any
		log.constructions += 1
		local effect: any = { ClassName = className, Type = nil, Parent = nil, played = 0, stopped = 0 }
		function effect:Play()
			log.plays += 1
			effect.played += 1
		end
		function effect:Stop()
			effect.stopped += 1
		end
		function effect:Destroy() end
		table.insert(log.effects, effect)
		return effect
	end
end

-- the six real `Enum.HapticEffectType` members (API dump, client 0.734.0.7340915)
local function fakeEnums(members: { string }?): any
	local set: any = {}
	for _, name in
		members or { "Custom", "UIHover", "UIClick", "UINotification", "GameplayExplosion", "GameplayCollision" }
	do
		set[name] = `Enum.HapticEffectType.{name}`
	end
	return { HapticEffectType = set }
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
		adjustIntervalSeconds = given.adjustIntervalSeconds,
		instanceNew = given.instanceNew or fakeInstanceNew(log),
		inputService = given.inputService or uis,
		hapticService = given.hapticService or fakeHapticService(true),
		enums = given.enums or fakeEnums(),
		parent = given.parent,
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

	it("`activate` is silent on the BUS because the engine plays it (property route)", function()
		expect(haptics.MAP.activate).toBe(false)
		expect(haptics.PRESS_EFFECT_TYPE).toBe("UIClick")
		expect(table.find(haptics.EFFECT_TYPES, haptics.PRESS_EFFECT_TYPE) ~= nil).toBeTruthy()
	end)
end)

describe("haptics: what an enabled adapter actually plays", function()
	it("plays one pooled effect per mapped verb, and reuses it forever", function()
		local adapter, bus, log = rig({ enabled = true })
		for _ = 1, 50 do
			for _, verb in feedbackLib.TYPES do
				bus.emit({ type = verb, path = "/S/B" })
			end
		end
		local mapped = 0
		for _, effectType in haptics.MAP do
			if effectType ~= false then
				mapped += 1
			end
		end
		expect(mapped).toBe(7)
		-- ONE construction per mapped verb, whatever the fire count (the
		-- documented "fewer than 100 simultaneous effects" budget)
		expect(log.constructions).toBe(mapped)
		expect(adapter.diagnostics().pooled).toBe(mapped)
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

	it("the rate limit is `adjust`'s alone — discrete verbs are never swallowed", function()
		local _, bus, log = rig({ enabled = true })
		for _ = 1, 5 do
			bus.emit({ type = "select", path = "/S/Row" })
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
			enums = fakeEnums({ "Custom" }), -- every preset missing
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
	local function fakeButton(name: string): any
		local inst: any = { Name = name, HoverHapticEffect = nil, PressHapticEffect = nil, descendants = {} }
		function inst:IsA(className: string): boolean
			return className == "GuiButton"
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

	local function fakeRoot(children: { any }): any
		local root: any = { Name = "Screen", DescendantAdded = fakeSignal(), children = children }
		function root:IsA(): boolean
			return false
		end
		function root:GetDescendants(): { any }
			return root.children
		end
		function root.add(child: any)
			table.insert(root.children, child)
			root.DescendantAdded.fire(child)
		end
		return root
	end

	it("assigns PressHapticEffect and NEVER calls Play", function()
		local adapter, _, log = rig({ enabled = true })
		local button = fakeButton("Go")
		local root = fakeRoot({ button, fakeFrame("Plate") })
		adapter.attachButtons(root)
		expect(button.PressHapticEffect ~= nil).toBeTruthy()
		expect(button.PressHapticEffect.ClassName).toBe("HapticEffect")
		expect(button.PressHapticEffect.Type).toBe("Enum.HapticEffectType.UIClick")
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
		local LuauUI = require("../src") :: any
		expect(LuauUI.haptics).toBeNil()
		expect(string.find(fs.readFile("src/init.luau"), "haptic", 1, true)).toBeNil()
	end)

	it("the adapter itself calls Play only on a POOLED effect, never on a button's", function()
		-- a structural pin on the property route: the one `:Play(` call site in
		-- the module is the bus path. If a future edit plays the press effect
		-- itself, "LuauUI plays nothing" stops being literally true.
		local source = fs.readFile("src/client/haptics.luau")
		local plays = 0
		for _ in string.gmatch(source, ":Play%(%)") do
			plays += 1
		end
		expect(plays).toBe(1)
	end)
end)
