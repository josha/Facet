--!strict
-- CLIENT-ONLY, OPT-IN, DEFAULT OFF. One adapter that turns Facet's semantic
-- feedback events into Roblox haptics — and the framework's only relationship
-- with it is that it is a SUBSCRIBER. `src/present/feedback.luau:4-5` says
-- Facet plays nothing; nothing in `src/` outside this directory names a haptic
-- symbol or requires this file (pinned by tests/haptics.spec.luau), so that rule
-- survives this module existing.
--
--   local haptics = require(ReplicatedStorage.Facet.client.haptics)
--   local hap = haptics.new({ enabled = settings.haptics })
--   hap.bind(presenter)             -- the verbs with no engine hook
--   hap.attachButtons(screenGui)    -- the property route: every button's press
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
--      references the ENGINE fires. Facet already materializes TextButtons, so
--      `activate` takes that property route: this module hands over a reference
--      and never calls Play on it, which keeps "Facet plays nothing" literally
--      true rather than nearly true. The bus subscription covers only the verbs
--      with no engine hook. Since 2026-08-13 the reference is chosen PER BUTTON
--      from the verb the author declared with
--      `UI.sensoryFeedback(bp, { activation = … })`, which the renderer publishes
--      as the `Facet_ActivationFeedback` attribute — so a Buy button and a
--      Cancel button can feel different without this module learning anything
--      about Facet's node graph, and without either of them being played twice.
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
-- EVERY EFFECT THIS ADAPTER BUILDS IS PARENTED INTO THE DATA MODEL, so `Stop()`
-- is only half of putting one away — `Stop()` ends the sensation, `Destroy()`
-- ends the Instance, and dropping the Lua reference ends neither. A settings
-- screen with a haptics toggle flips this switch as often as the player likes, so
-- the disable path is the one that has to be airtight: `setEnabled(false)`,
-- `undecorate` and `dispose` all destroy what they release, and `pooled` is
-- DERIVED from the effects that actually exist (the press effect included) rather
-- than kept as a counter beside them. Measured before the fix: five enable/disable
-- cycles left `constructions = 15, destroys = 0, live-parented = 15` while
-- `diagnostics().pooled` reported 0 — an instrument that hid the leak it was there
-- to show. The rule that follows: this module's own counters are never the
-- evidence for its own lifetime; the spec counts Instances.
--
-- DECORATION IS PER-ROOT. Press effects are shared adapter-wide and pooled by
-- EFFECT TYPE (that is the point — one Instance per sensation, however many
-- buttons want it), but the RECORD of which instances carry one is kept per
-- attached root, so detaching one surface touches only that surface's buttons: no
-- global strip, no re-sweep of every survivor, and the shared effects outlive
-- every detach. It dies at `setEnabled(false)` and at `dispose`, which
-- are the two moments the adapter genuinely stops. `decorate` also RE-READS the
-- property instead of trusting the record, so a second adapter (or anything else)
-- clearing the reference cannot leave a button permanently unfelt.
--
-- AFTER `dispose()` THE ADAPTER IS INERT, never throwing: `setEnabled` already
-- refused to re-enable a disposed adapter, and `bind`/`attachButtons` now match it
-- rather than opening a subscription and a `DescendantAdded` connection that
-- nothing will ever drain.
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
--               so it is silent HERE, on the bus, and felt anyway. NOTE that the
--               general rule is now wider than this one row: `onEvent` drops any
--               event carrying `reason = "activation"`, whatever verb it names,
--               because a control that renamed its activation is still played by
--               the engine through its own property. This row remains for a
--               `type = "activate"` a GAME emits for its own reasons.
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

-- what `GuiButton.PressHapticEffect` is set to for an UNDECLARED control: the
-- preset Roblox describes as "crisp … immediate feedback", which is what a plain
-- button press is. A control that declared its own verb gets that verb's effect
-- instead (see `pressEffectFor`).
haptics.PRESS_EFFECT_TYPE = "UIClick"

-- THE PER-CONTROL DECLARATION'S ARRIVAL POINT (director request 2026-08-13). The
-- renderer publishes `UI.sensoryFeedback(bp, { activation = … })`'s resolved verb
-- as this attribute on the materialized GuiButton
-- (`src/render/target_contract.luau`'s `setActivationFeedback`), so this adapter
-- can hand the ENGINE a different effect per control without knowing anything
-- about Facet's node graph. An attribute is data: reading one keeps this module
-- a subscriber rather than a second consumer of framework internals.
haptics.ACTIVATION_ATTRIBUTE = "Facet_ActivationFeedback"

-- the effect a button's press should play, given the verb the author declared on
-- it (nil = undeclared). Returns nil for a control that must be felt as nothing:
-- either the author said `none`, or the verb is one of the four the MAP silences
-- on purpose — a `cancel` that buzzes would contradict the reason `cancel` is
-- silent everywhere else.
function haptics.pressEffectFor(verb: string?): string?
	if verb == nil or verb == "activate" then
		return haptics.PRESS_EFFECT_TYPE
	end
	if verb == feedbackLib.ACTIVATION_SILENT then
		return nil
	end
	local mapped = MAP[verb]
	if type(mapped) == "string" then
		return mapped
	end
	return nil
end

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

	-- ONE effect per mapped verb, plus the button property route's own effects.
	-- Never constructed per fire (the "fewer than 100 simultaneous effects"
	-- budget).
	local pool: { [string]: any } = {}
	-- THE PRESS ROUTE'S POOL, keyed by EFFECT TYPE rather than by verb — the
	-- opposite of `pool` above, deliberately. A page of forty buttons declaring
	-- `commit`, `select` and `land` wants ONE UIClick instance shared by all
	-- forty, because what a button hands the engine is a sensation, not a verb.
	-- (`pool` stays verb-keyed: its entries are played by name from the bus, and
	-- re-keying it would merge two effects an existing test counts separately.)
	local pressEffects: { [string]: any } = {}

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
		-- `pooled` and `decorated` are deliberately ABSENT from this table: both are
		-- derived from the live state at read time (`pooledCount`, `decoratedCount`),
		-- because the counter they replaced is exactly what reported 0 while fifteen
		-- effects sat in Workspace.
		lastError = nil :: string?,
	}
	local lastAdjustAt: number? = nil

	local subscriptions: { () -> () } = {}
	local deviceConnections: { any } = {}
	-- ATTACHED ROOTS, each carrying its OWN weak record of the instances it
	-- decorated. Per-root is what makes a detach local (see the header); weak keys
	-- are what stop an instance the game destroyed from being held alive here.
	-- `destroying` is the other half of that: a surface torn down without an
	-- explicit detach releases its entry from this list instead of sitting in it
	-- forever, because a ScreenGui's own destruction is the detach nobody wrote.
	type Root = { root: any, connection: any, destroying: any, decorated: { [any]: boolean } }
	local roots: { Root } = {}

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
		-- THE VERDICT IS ALREADY IN. A client that cannot create the class will not
		-- start being able to, so re-attempting per event turned 50 feedback events
		-- into 50 failed pcalls (measured) while `support()` had said `absent` since
		-- the first one. `blocked` is deliberately NOT short-circuited: that is the
		-- "refused for some other reason" bucket, and this module does not claim to
		-- know that it is permanent.
		if constructionVerdict == "absent" then
			return nil
		end
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
		return effect
	end

	-- PUTTING AN EFFECT AWAY IS TWO CALLS, NOT ONE. `Stop()` ends the sensation
	-- (an effect mid-play must not outlive the switch); `Destroy()` ends the
	-- Instance, which is parented into the DataModel at construction and is
	-- otherwise immortal however thoroughly Lua forgets it.
	local function retire(effect: any)
		if effect == nil then
			return
		end
		guard(function()
			effect:Stop()
			return nil
		end)
		guard(function()
			effect:Destroy()
			return nil
		end)
	end

	-- DERIVED, NEVER COUNTED. The counter this replaced read 0 while fifteen
	-- effects sat in Workspace, because it was maintained beside the pool instead
	-- of from it and never knew the press effect existed at all.
	local function pooledCount(): number
		local n = 0
		for _ in pressEffects do
			n += 1
		end
		for _ in pool do
			n += 1
		end
		return n
	end

	local function retirePool()
		for verb, effect in pool do
			retire(effect)
			pool[verb] = nil
		end
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

	-- ===== the property route (`activate`, and every declared verb) =========
	local function pressEffectHandle(effectTypeName: string): any?
		if not enabled then
			return nil
		end
		local existing = pressEffects[effectTypeName]
		if existing ~= nil then
			return existing
		end
		local built = construct(effectTypeName)
		if built == nil then
			return nil
		end
		pressEffects[effectTypeName] = built
		return built
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
	--
	-- THE RECORD IS A CACHE, THE PROPERTY IS THE TRUTH. `entry.decorated` used to
	-- be the sole authority, which meant a second adapter's detach (or any other
	-- writer) clearing `PressHapticEffect` left this one saying "done" forever and
	-- the button silently unfelt for the session. So the property is re-read and
	-- re-assigned whenever it is not already our effect; the record only saves the
	-- write when it is.
	local function decorate(entry: Root, instance: any)
		if not enabled or disposed or not isGuiButton(instance) then
			return
		end
		-- WHAT THIS PARTICULAR CONTROL FEELS LIKE. The renderer published the
		-- author's `UI.sensoryFeedback(bp, { activation = … })` verb here as an
		-- attribute; absent means undeclared, which is the generic press preset and
		-- is exactly what every button got before this existed.
		local declaredVerb = guard(function(): any
			return instance:GetAttribute(haptics.ACTIVATION_ATTRIBUTE)
		end)
		local effectTypeName = haptics.pressEffectFor(if type(declaredVerb) == "string" then declaredVerb else nil)
		if effectTypeName == nil then
			-- DELIBERATELY UNFELT (`none`, or a verb the MAP silences). Clearing
			-- rather than skipping: a button that was decorated and is now silent —
			-- because the adapter re-swept, or because another writer set the
			-- property — must actually lose its reference, or "none" would mean
			-- "none unless somebody already said otherwise".
			guard(function()
				instance.PressHapticEffect = nil
				return nil
			end)
			entry.decorated[instance] = nil
			return
		end
		local effect = pressEffectHandle(effectTypeName)
		if effect == nil then
			return
		end
		local current = guard(function()
			return instance.PressHapticEffect
		end)
		if current ~= effect then
			local ok = guard(function()
				instance.PressHapticEffect = effect
				return true
			end)
			if ok ~= true then
				return
			end
		end
		entry.decorated[instance] = true
	end

	-- is `instance` still carried by some OTHER attached root? A button under two
	-- attached surfaces (nested ScreenGuis, an adapter attached twice) must keep
	-- its reference until the last of them lets go.
	local function decoratedElsewhere(instance: any, except: Root): boolean
		for _, other in roots do
			if other ~= except and other.decorated[instance] == true then
				return true
			end
		end
		return false
	end

	-- release ONE root's decorations. Nothing global happens here — no other
	-- surface is stripped, nothing is re-swept, and the shared press effect stays
	-- alive for the roots that are still attached (header).
	local function undecorateEntry(entry: Root)
		for instance in entry.decorated do
			if not decoratedElsewhere(instance, entry) then
				guard(function()
					instance.PressHapticEffect = nil
					return nil
				end)
			end
		end
		table.clear(entry.decorated)
	end

	-- ...and the two moments the adapter genuinely stops: every root released, and
	-- the shared effect destroyed rather than merely forgotten.
	local function undecorateAll()
		for _, entry in roots do
			undecorateEntry(entry)
		end
		for name, effect in pressEffects do
			retire(effect)
			pressEffects[name] = nil
		end
	end

	local function decoratedCount(): number
		local seen: { [any]: boolean } = {}
		local n = 0
		for _, entry in roots do
			for instance in entry.decorated do
				if seen[instance] == nil then
					seen[instance] = true
					n += 1
				end
			end
		end
		return n
	end

	local function sweep(entry: Root)
		decorate(entry, entry.root)
		local descendants = guard(function()
			return entry.root:GetDescendants()
		end)
		for _, child in descendants or {} do
			decorate(entry, child)
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
		-- A CONTROL ACTIVATION IS THE ENGINE'S TO PLAY, whatever verb the author
		-- gave it. The presenter stamps `reason = "activation"` on every event a
		-- press causes, and the press route has already handed that button its
		-- effect through `GuiButton.PressHapticEffect` — so playing it here too
		-- would be two pulses for one press. This replaces what used to be a
		-- `MAP.activate = false` hole, which said the same thing but only for the
		-- default verb: the moment a control could rename its activation, the hole
		-- stopped covering the case it was cut for.
		if event.reason == "activation" then
			diag.ignored += 1
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
				"Facet haptics.bind(presenter): expected something with an `onFeedback(fn) -> unsubscribe` — "
					.. "a presenter, or a presented handle for one surface only.",
				0
			)
		end
		-- INERT AFTER DISPOSE, exactly as setEnabled already is. `dispose` drains
		-- `subscriptions` once and returns early on re-entry, so a subscription
		-- opened after it is one nothing will ever close.
		if disposed then
			return function() end
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

	-- attachButtons(root) -> detach. Point it at the Facet ScreenGui: every
	-- GuiButton under it, now and later, gets the press reference.
	function adapter.attachButtons(root: any): () -> ()
		-- INERT AFTER DISPOSE (see `bind`): the `DescendantAdded` connection this
		-- would open is one `dispose` has already finished draining.
		if disposed then
			return function() end
		end
		local entry: Root = {
			root = root,
			connection = nil,
			destroying = nil,
			decorated = setmetatable({}, { __mode = "k" }) :: any,
		}
		entry.connection = guard(function()
			return root.DescendantAdded:Connect(function(child: any)
				decorate(entry, child)
			end)
		end)
		table.insert(roots, entry)

		local function release()
			local index = table.find(roots, entry)
			if index == nil then
				return
			end
			table.remove(roots, index)
			for _, connection in { entry.connection, entry.destroying } do
				if connection ~= nil then
					guard(function()
						connection:Disconnect()
						return nil
					end)
				end
			end
			entry.connection = nil
			entry.destroying = nil
			-- ONLY THIS ROOT. The decoration record is per-root (header), so a
			-- detach neither strips the surviving surfaces nor re-sweeps them, and
			-- the shared press effect — which the survivors are still pointing at —
			-- stays alive. Measured before the fix: three attach/detach round trips
			-- on EMPTY guis destroyed and rebuilt it three times, leaking each one.
			undecorateEntry(entry)
		end

		-- THE DETACH NOBODY WROTE. A surface destroyed without calling the returned
		-- function used to sit in `roots` for the process lifetime, strongly held
		-- and re-walked at every later detach. `Destroying` is the engine's own
		-- answer; a root that has no such signal (a plain table in a test) simply
		-- keeps the explicit detach, which is what `guard` returning nil means here.
		entry.destroying = guard(function()
			return root.Destroying:Connect(release)
		end)

		sweep(entry)
		return release
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
				sweep(entry)
			end
		else
			disconnectDevices()
			-- NOTHING SURVIVES THE SWITCH. A pooled effect that is mid-play must
			-- stop, and every effect this adapter built must leave the DataModel:
			-- `Stop()` alone left the Instance parented to Workspace forever, so a
			-- settings toggle leaked up to eight of them per flip.
			undecorateAll()
			retirePool()
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
			pooled = pooledCount(),
			decorated = decoratedCount(),
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
		-- UNCONDITIONAL, not "whatever setEnabled(false) happened to do". Disposing
		-- an adapter that was ALREADY off takes the early return in setEnabled, so
		-- this is the only place that is guaranteed to run — and an adapter that was
		-- switched off and then re-decorated by nothing still owns its roots.
		undecorateAll()
		retirePool()
		for _, entry in table.clone(roots) do
			for _, connection in { entry.connection, entry.destroying } do
				if connection ~= nil then
					guard(function()
						connection:Disconnect()
						return nil
					end)
				end
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
