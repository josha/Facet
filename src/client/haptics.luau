--!strict
-- CLIENT-ONLY, OPT-IN, DEFAULT OFF. One adapter that turns LuauUI's semantic
-- feedback events into Roblox haptics — and the framework's only relationship
-- with it is that it is a SUBSCRIBER. `src/present/feedback.luau:4-5` says
-- LuauUI plays nothing; nothing in `src/` outside this directory names a haptic
-- symbol or requires this file (pinned by tests/haptics.spec.luau), so that rule
-- survives this module existing.
--
--   local haptics = require(ReplicatedStorage.LuauUI.client.haptics)
--   local hap = haptics.new({ enabled = settings.haptics })
--   hap.bind(presenter)             -- the verbs with no engine hook
--   hap.attachButtons(screenGui)    -- the property route, for `activate`
--
-- EVERY ENGINE FACT BELOW IS MEASURED AND RECORDED, with sources, in
-- docs/research/2026-08-12-haptics-engine-facts.md (live creator docs + the API
-- dump for client 0.734.0.7340915, 2026-08-12). Read it before changing this
-- file — it overturns the obvious approach in four places:
--
--   1. `HapticEffect`, NEVER `HapticService:SetMotor`. Roblox's own class
--      reference says the service "has been superseded by HapticEffect … For new
--      work, use HapticEffect instead", and SetMotor's value range, persistence
--      and zeroing requirement are all undocumented. A motor you cannot prove
--      stops is a stuck-rumble bug with no test.
--   2. `GuiButton.HoverHapticEffect` / `PressHapticEffect` are assignable
--      references the ENGINE fires. LuauUI already materializes TextButtons, so
--      `activate` takes that property route: this module hands over a reference
--      and never calls Play on it, which keeps "LuauUI plays nothing" literally
--      true rather than nearly true. The bus subscription covers only the verbs
--      with no engine hook.
--   3. There is NO capability API — no IsSupported, nothing on
--      UserInputService. The only probe on the platform belongs to the
--      superseded service, is boolean, and returns false both for "this device
--      has no motor" and for "no gamepad connected YET". That is precisely the
--      shape docs/lessons/capability-probes-must-be-tri-state.md was written
--      about, so `support()` is a five-state lattice and re-probes on device
--      change instead of caching at boot.
--   4. `Custom` used as a fallback is a GUARANTEED SILENT NO-OP (a Custom effect
--      with no SetWaveformKeys plays nothing), and `UISelection` — the name the
--      game side guessed once — is not a member at all. So the enum is resolved
--      defensively BY NAME, before anything is constructed, and never falls back.
--      Confirmed live in Studio 2026-08-13: `Enum.HapticEffectType["UISelection"]`
--      THROWS on index rather than answering nil, so the lookup must sit inside a
--      pcall or a typo is a crash (artifacts/swiftui-parity-round2/
--      phase-3-haptics-evidence.md). The same canary read
--      `HapticService:IsVibrationSupported(Gamepad1) == false` on a machine with
--      ZERO gamepads attached — the boolean lying exactly as fact 3 predicts.
--
-- WHAT THIS MODULE CANNOT KNOW. `UserGameSettings.HapticStrength` is
-- RobloxScriptSecurity on read and write, so the player's own haptics preference
-- is unreadable from game code; whether `HapticEffect` is scaled by it is
-- undocumented. The adapter therefore owns its own on/off switch and makes no
-- claim about honouring the player's — that is a device-only question.
--
-- REQUIRE-SAFE: nothing at module scope touches an engine global, so this file
-- requires cleanly under Lune and in Studio Edit, and every engine call inside it
-- is pcall-guarded.

local feedbackLib = require("../present/feedback")

local haptics = {}

-- ===== the mapping, TOTAL over the closed twelve ===========================
-- `false` means DELIBERATELY SILENT, and it is written out rather than omitted:
-- a missing key and a decided silence look identical at a call site, and a
-- thirteenth verb added to the taxonomy tomorrow must surface as a visible gap
-- (`unmappedVerbs()`, asserted empty by the spec) instead of being dropped.
--
--   activate    the ENGINE plays it, through PressHapticEffect (see 2 above) —
--               so it is silent HERE, on the bus, and felt anyway
--   arrive      fires on every chase settle; a haptic there is per-frame noise
--   cancel      the ABSENCE of feedback is the signal for "nothing happened"
--   dismiss     not player-caused — a self-retiring toast buzzing is a phantom
--   supersede   likewise: a replacement the player did not ask for
local MAP: { [string]: string | false } = {
	activate = false,
	select = "UIClick",
	adjust = "UIHover", -- the subtlest preset; also rate-limited (below)
	pickup = "UIClick",
	commit = "UIClick",
	reject = "UINotification", -- a refusal must be distinguishable from a commit
	cancel = false,
	arrive = false,
	land = "UIClick",
	dismiss = false,
	supersede = false,
	celebrate = "UINotification",
}
haptics.MAP = table.freeze(MAP)

-- `Enum.HapticEffectType`, all six members, none deprecated (API dump). Listed
-- so a mapped name is checkable against the real vocabulary without an engine.
haptics.EFFECT_TYPES = table.freeze({
	"Custom",
	"UIHover",
	"UIClick",
	"UINotification",
	"GameplayExplosion",
	"GameplayCollision",
})

-- what `GuiButton.PressHapticEffect` is set to: the preset Roblox describes as
-- "crisp … immediate feedback", which is what a button press is
haptics.PRESS_EFFECT_TYPE = "UIClick"

-- verbs the taxonomy has and this map does not (must be empty)
function haptics.unmappedVerbs(): { string }
	local gaps: { string } = {}
	for _, verb in feedbackLib.TYPES do
		if MAP[verb] == nil then
			table.insert(gaps, verb)
		end
	end
	table.sort(gaps)
	return gaps
end

-- verbs this map has and the taxonomy does not (must be empty)
function haptics.strayVerbs(): { string }
	local stray: { string } = {}
	for verb in MAP do
		if table.find(feedbackLib.TYPES, verb) == nil then
			table.insert(stray, verb)
		end
	end
	table.sort(stray)
	return stray
end

-- ===== the capability lattice ==============================================
-- `unknown` is not a failure state: it means "attempt it, expect nothing,
-- publish no platform claim". It is the DEFAULT for touch (there is no probe for
-- a phone at all) and for the pre-first-gamepad state (the boolean probe cannot
-- tell "no motor" from "no pad yet").
export type Support = "supported" | "unsupported" | "unknown" | "blocked" | "absent"

export type Options = {
	-- DEFAULT FALSE. Off means: no construction, no play, no device listener.
	enabled: boolean?,
	-- monotonic seconds, for the `adjust` rate limit (default os.clock)
	now: (() -> number)?,
	-- the `adjust` floor. Sliders and steppers fire per tick; unthrottled that is
	-- a buzzsaw AND a breach of the documented "fewer than 100 simultaneous
	-- effects" budget. Coalescing DROPS — a swallowed tick is never replayed
	-- late, because a haptic after the gesture is a phantom.
	adjustIntervalSeconds: number?,
	-- injection seams (the reason any of this is provable headless). `false`
	-- means "there is none", which is not the same as absent-and-unprobed.
	instanceNew: ((className: string) -> any)?,
	inputService: any?,
	hapticService: any?,
	enums: any?,
	-- where pooled effects are parented. Default: Workspace, MATCHING THE
	-- OFFICIAL SAMPLE — the docs state no parenting requirement, and this module
	-- does not claim one. `false` parents nothing.
	parent: any?,
}

export type Diagnostics = {
	enabled: boolean,
	support: Support,
	constructions: number,
	plays: number,
	coalesced: number,
	ignored: number,
	unmapped: number,
	enumMisses: number,
	probes: number,
	pooled: number,
	decorated: number,
	lastError: string?,
}

local DEFAULT_ADJUST_INTERVAL = 0.06

-- a client that cannot create the class at all vs one that refused for another
-- reason. The engine's own words are the discriminator and they are KEPT: the
-- lesson's `absent`/`blocked` split is only useful if the text survives.
local function classifyConstructionError(message: string): Support
	local lowered = string.lower(message)
	if
		string.find(lowered, "unable to create", 1, true) ~= nil
		or string.find(lowered, "is not a valid", 1, true) ~= nil
		or string.find(lowered, "attempt to index nil", 1, true) ~= nil
	then
		return "absent"
	end
	return "blocked"
end

function haptics.new(opts: Options?): any
	local options: Options = opts or {}
	local now: () -> number = options.now or os.clock
	local adjustInterval: number = options.adjustIntervalSeconds or DEFAULT_ADJUST_INTERVAL
	local parentOption = options.parent

	local enabled = options.enabled == true
	local disposed = false

	-- ONE effect per mapped verb, plus one for the button property route. Never
	-- constructed per fire (the "fewer than 100 simultaneous effects" budget).
	local pool: { [string]: any } = {}
	local pooled = 0
	local pressEffect: any = nil

	local deviceVerdict: Support = "unknown"
	local constructionVerdict: Support? = nil
	local diag = {
		constructions = 0,
		plays = 0,
		coalesced = 0,
		ignored = 0,
		unmapped = 0,
		enumMisses = 0,
		probes = 0,
		decorated = 0,
		lastError = nil :: string?,
	}
	local lastAdjustAt: number? = nil

	local subscriptions: { () -> () } = {}
	local deviceConnections: { any } = {}
	-- attached roots, and every instance this adapter has written a reference
	-- onto (weak keys: an instance destroyed by the game must not be held alive
	-- by this table)
	local roots: { { root: any, connection: any } } = {}
	local decorated: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any

	local function guard<T>(fn: () -> T): T?
		local ok, result = pcall(fn)
		if not ok then
			diag.lastError = tostring(result)
			return nil
		end
		return result
	end

	local function service(injected: any, name: string): any?
		if injected ~= nil then
			return if injected == false then nil else injected
		end
		return guard(function()
			return (game :: any):GetService(name)
		end)
	end

	-- RESOLVED BY NAME, BEFORE ANYTHING IS BUILT, and never falling back to
	-- `Custom` (fact 4 in the header). A miss is counted and plays nothing —
	-- silence a diagnostic can see beats a Custom effect that reports success and
	-- produces no sensation.
	local function resolveEffectType(name: string): any?
		local source = if options.enums ~= nil then options.enums else nil
		local value = guard(function(): any
			local enums: any = if source ~= nil then source else Enum :: any
			return enums.HapticEffectType[name]
		end)
		if value == nil then
			diag.enumMisses += 1
		end
		return value
	end

	local function resolveParent(): any?
		if parentOption ~= nil then
			return if parentOption == false then nil else parentOption
		end
		return service(nil, "Workspace")
	end

	local function construct(effectTypeName: string): any?
		local enumValue = resolveEffectType(effectTypeName)
		if enumValue == nil then
			return nil -- never `Custom`, never a guess
		end
		local factory = options.instanceNew
		local ok, result = pcall(function(): any
			if factory ~= nil then
				return factory("HapticEffect")
			end
			return (Instance :: any).new("HapticEffect")
		end)
		if not ok or result == nil then
			local message = if ok then "Instance.new returned nil" else tostring(result)
			diag.lastError = message
			constructionVerdict = classifyConstructionError(message)
			return nil
		end
		diag.constructions += 1
		local effect: any = result
		guard(function()
			effect.Type = enumValue
			return nil
		end)
		local parent = resolveParent()
		if parent ~= nil then
			guard(function()
				effect.Parent = parent
				return nil
			end)
		end
		return effect
	end

	local function effectFor(verb: string, effectTypeName: string): any?
		local existing = pool[verb]
		if existing ~= nil then
			return existing
		end
		local effect = construct(effectTypeName)
		if effect == nil then
			return nil
		end
		pool[verb] = effect
		pooled += 1
		return effect
	end

	-- ===== the device probe =================================================
	local function probe()
		diag.probes += 1
		local uis = service(options.inputService, "UserInputService")
		if uis == nil then
			deviceVerdict = "unknown"
			return
		end
		local pads = guard(function()
			return uis:GetConnectedGamepads()
		end)
		-- NO PAD MEANS NO EVIDENCE, not "no haptics": the only probe on the
		-- platform answers `false` for an absent gamepad exactly as it does for a
		-- motorless one, and on touch there is no probe at all — the docs say only
		-- "most" iPhone/Pixel/Galaxy devices have haptics, so a phone is
		-- permanently `unknown` and never `supported`.
		if pads == nil or #pads == 0 then
			deviceVerdict = "unknown"
			return
		end
		local hs = service(options.hapticService, "HapticService")
		if hs == nil then
			deviceVerdict = "unknown"
			return
		end
		local answered, anySupported = false, false
		for _, pad in pads do
			local supported = guard(function()
				return hs:IsVibrationSupported(pad)
			end)
			if supported ~= nil then
				answered = true
				if supported == true then
					anySupported = true
				end
			end
		end
		if not answered then
			deviceVerdict = "unknown"
		elseif anySupported then
			deviceVerdict = "supported"
		else
			-- a pad IS connected and says no: this is the one case where the
			-- boolean means what it says
			deviceVerdict = "unsupported"
		end
	end

	local function disconnectDevices()
		for _, connection in deviceConnections do
			guard(function()
				connection:Disconnect()
				return nil
			end)
		end
		table.clear(deviceConnections)
	end

	-- HOT-PLUG INVALIDATES A CACHED ANSWER. The docs never say whether Play()
	-- re-routes to a newly connected pad or whether the probe is re-evaluated, so
	-- the answer is re-derived on every device change rather than trusted from
	-- boot. (Input events only fire while the client window has focus — a
	-- documented caveat, not something this module can fix.)
	local function connectDevices()
		local uis = service(options.inputService, "UserInputService")
		if uis == nil then
			return
		end
		for _, eventName in { "GamepadConnected", "GamepadDisconnected", "LastInputTypeChanged" } do
			local connection = guard(function()
				return uis[eventName]:Connect(function()
					probe()
				end)
			end)
			if connection ~= nil then
				table.insert(deviceConnections, connection)
			end
		end
	end

	-- ===== the property route (`activate`) ==================================
	local function pressEffectHandle(): any?
		if not enabled then
			return nil
		end
		if pressEffect == nil then
			pressEffect = construct(haptics.PRESS_EFFECT_TYPE)
		end
		return pressEffect
	end

	local function isGuiButton(instance: any): boolean
		local result = guard(function()
			return instance:IsA("GuiButton")
		end)
		return result == true
	end

	-- ASSIGN, NEVER PLAY. The engine owns the trigger for these two properties;
	-- handing over a reference is the whole mechanism. `HoverHapticEffect` is
	-- deliberately left alone: a felt cursor is nobody's request, and on a
	-- pointer device it would tick on every mouse-over.
	local function decorate(instance: any)
		if not enabled or decorated[instance] == true or not isGuiButton(instance) then
			return
		end
		local effect = pressEffectHandle()
		if effect == nil then
			return
		end
		local ok = guard(function()
			instance.PressHapticEffect = effect
			return true
		end)
		if ok == true then
			decorated[instance] = true
			diag.decorated += 1
		end
	end

	local function undecorate()
		for instance in decorated do
			guard(function()
				instance.PressHapticEffect = nil
				return nil
			end)
		end
		table.clear(decorated)
		diag.decorated = 0
		if pressEffect ~= nil then
			guard(function()
				pressEffect:Stop()
				return nil
			end)
			pressEffect = nil
		end
	end

	local function sweep(root: any)
		decorate(root)
		local descendants = guard(function()
			return root:GetDescendants()
		end)
		for _, child in descendants or {} do
			decorate(child)
		end
	end

	local adapter: any = {}

	-- ===== the bus subscription (every verb with no engine hook) ============
	local function onEvent(event: any)
		if not enabled or disposed then
			return
		end
		local verb = if type(event) == "table" then event.type else nil
		if type(verb) ~= "string" then
			return
		end
		local effectTypeName = MAP[verb]
		if effectTypeName == nil then
			-- the taxonomy grew and this map did not: counted, never guessed
			diag.unmapped += 1
			return
		end
		if effectTypeName == false then
			diag.ignored += 1
			return
		end
		if verb == "adjust" then
			local at = now()
			local previous = lastAdjustAt
			if previous ~= nil and (at - previous) < adjustInterval then
				diag.coalesced += 1
				return
			end
			lastAdjustAt = at
		end
		local effect = effectFor(verb, effectTypeName)
		if effect == nil then
			return
		end
		local played = guard(function()
			effect:Play()
			return true
		end)
		if played == true then
			diag.plays += 1
		end
	end

	-- bind(presenter) -> unbind. `presenter.onFeedback` is the primary seam (one
	-- subscription, every surface); a per-surface `handle.onFeedback` works
	-- identically.
	function adapter.bind(presenter: any): () -> ()
		if type(presenter) ~= "table" or type(presenter.onFeedback) ~= "function" then
			error(
				"LuauUI haptics.bind(presenter): expected something with an `onFeedback(fn) -> unsubscribe` — "
					.. "a presenter, or a presented handle for one surface only.",
				0
			)
		end
		local unsubscribe = presenter.onFeedback(onEvent)
		table.insert(subscriptions, unsubscribe)
		return function()
			local index = table.find(subscriptions, unsubscribe)
			if index ~= nil then
				table.remove(subscriptions, index)
				unsubscribe()
			end
		end
	end

	-- attachButtons(root) -> detach. Point it at the LuauUI ScreenGui: every
	-- GuiButton under it, now and later, gets the press reference.
	function adapter.attachButtons(root: any): () -> ()
		local connection = guard(function()
			return root.DescendantAdded:Connect(function(child: any)
				decorate(child)
			end)
		end)
		local entry = { root = root, connection = connection }
		table.insert(roots, entry)
		sweep(root)
		return function()
			local index = table.find(roots, entry)
			if index == nil then
				return
			end
			table.remove(roots, index)
			if entry.connection ~= nil then
				guard(function()
					entry.connection:Disconnect()
					return nil
				end)
			end
			-- THE CLEAR IS GLOBAL, SO THE SURVIVORS ARE RE-EARNED. `decorated` is
			-- one weak set for the whole adapter (a shared press effect is the
			-- point), so there is no per-root subset to clear — detaching one
			-- surface would otherwise strip the references off every OTHER surface
			-- still attached. Clearing and re-sweeping what remains costs one walk
			-- per live root at detach time and cannot leave a stale reference.
			undecorate()
			for _, remaining in roots do
				sweep(remaining.root)
			end
		end
	end

	function adapter.setEnabled(on: boolean)
		local want = on == true and not disposed
		if want == enabled then
			return
		end
		enabled = want
		if enabled then
			probe()
			connectDevices()
			for _, entry in roots do
				sweep(entry.root)
			end
		else
			disconnectDevices()
			undecorate()
			-- a pooled effect that is mid-play must not outlive the switch
			for verb, effect in pool do
				guard(function()
					effect:Stop()
					return nil
				end)
				pool[verb] = nil
			end
			pooled = 0
			lastAdjustAt = nil
		end
	end

	function adapter.isEnabled(): boolean
		return enabled
	end

	-- The lattice. A construction verdict outranks the device one: if the class
	-- cannot be built on this client, what the pads say is irrelevant.
	function adapter.support(): Support
		return constructionVerdict or deviceVerdict
	end

	-- force a re-probe (a game that knows something the events did not say)
	function adapter.reprobe(): Support
		if enabled then
			probe()
		end
		return adapter.support()
	end

	function adapter.diagnostics(): Diagnostics
		return {
			enabled = enabled,
			support = adapter.support(),
			constructions = diag.constructions,
			plays = diag.plays,
			coalesced = diag.coalesced,
			ignored = diag.ignored,
			unmapped = diag.unmapped,
			enumMisses = diag.enumMisses,
			probes = diag.probes,
			pooled = pooled,
			decorated = diag.decorated,
			lastError = diag.lastError,
		}
	end

	function adapter.dispose()
		if disposed then
			return
		end
		adapter.setEnabled(false)
		disposed = true
		for _, unsubscribe in table.clone(subscriptions) do
			guard(function()
				unsubscribe()
				return nil
			end)
		end
		table.clear(subscriptions)
		for _, entry in table.clone(roots) do
			if entry.connection ~= nil then
				guard(function()
					entry.connection:Disconnect()
					return nil
				end)
			end
		end
		table.clear(roots)
	end

	if enabled then
		-- constructed enabled: probe and listen immediately, but still build
		-- nothing — the pool stays empty until a verb actually fires
		probe()
		connectDevices()
	end

	return adapter
end

return haptics
