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
-- THREE PHASES, THREE OWNERS OF THE MOMENT (`./sensory_profile.luau` holds the
-- waveforms; this file is the only one that touches the engine).
--
--   press    the DOWN edge. THE ENGINE'S, through `GuiButton.PressHapticEffect`.
--            An undeclared control now gets Facet's own `contact` waveform
--            instead of a bare preset; a control that DECLARED a verb still gets
--            that verb's mapped preset, exactly as it did before.
--   release  the COMPLETED edge, and it is NEW. `GuiButton.Activated` fires only
--            when a press completes on the control, and the presenter stamps
--            `reason = "activation"` on the event it raises for it — so that
--            event is the completed edge and it now plays `settle`. A press
--            dragged away from never fires Activated, so THE CANCEL CASE IS
--            SILENT STRUCTURALLY: there is no cancellation branch below, and
--            there must not be one.
--   select   a CHOICE CHANGED (`select` / `adjust`). Rate-limited, LEADING EDGE:
--            a suppressed pulse is dropped, never deferred.
--
-- NO DOUBLE PULSE, and the guard is narrower than it used to be. The old rule
-- DROPPED every `reason = "activation"` event, because the only alternative
-- would have been replaying the down edge the engine had already played. The two
-- edges are now separate sensations with separate owners, so the rule is simply
-- that the bus never plays the PRESS phase — which it structurally cannot,
-- because `phaseEffect("press")` is reachable only from `decorate`.
--
-- THIS MODULE ADDS NO INPUT LISTENER. When a press begins, completes or is
-- abandoned is decided ONCE, in the presenter/responder path, for pointer, touch,
-- keyboard and gamepad alike (including the echo collapse that makes a keyboard
-- Activate and its engine echo one dispatch). `UserInputService` appears here
-- exactly once, as the DEVICE PROBE's service name — a capability question, not
-- an input one — and `ContextActionService` never appears at all. Pinned by
-- tests/haptics.spec.luau.
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
--      case a two-state capability probe cannot answer honestly, so `support()`
--      is a five-state lattice and re-probes on device
--      change instead of caching at boot.
--   4. `Custom` used as a FALLBACK is a GUARANTEED SILENT NO-OP (a Custom effect
--      with no SetWaveformKeys plays nothing), and `UISelection` — the name the
--      game side guessed once — is not a member at all. So the enum is resolved
--      defensively BY NAME, before anything is constructed, and never falls back
--      to `Custom`. A DELIBERATE Custom is the opposite case and is safe: the
--      waveform keys are built FIRST and the Instance only afterwards, so a
--      client that cannot make a `FloatCurveKey` never gets a keyless Custom —
--      it gets the phase's documented preset (`sensory_profile.FALLBACK`), and
--      `diagnostics().phases[phase].fallbackActive` says so.
--      Confirmed live in Studio 2026-08-13: `Enum.HapticEffectType["UISelection"]`
--      THROWS on index rather than answering nil, so the lookup must sit inside a
--      pcall or a typo is a crash. The engine facts this module rests on are
--      recorded with their Roblox sources in
--      `docs/research/2026-08-12-haptics-engine-facts.md`, and the defensive
--      resolution is pinned by `tests/haptics.spec.luau`. The same canary read
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
local sensory_profile = require("./sensory_profile")

local haptics = {}

-- the typed profile, re-exported so a consumer that resolved only this module
-- (the showcase fixture resolves it by instance path) can build a partial profile
-- without a second resolution route
haptics.sensoryProfile = sensory_profile

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

-- `Enum.HapticEffectType`, all six members, none deprecated (API dump). Owned by
-- `sensory_profile` (which validates preset names against it) and re-exported
-- here as the SAME table, so the two can never disagree.
haptics.EFFECT_TYPES = sensory_profile.EFFECT_TYPES

--[[ THE VERBS THE SELECT PHASE CLAIMS, and the precedence rule written down.
	`select` and `adjust` describe the same thing happening — A CHOICE MOVED — so
	they play one pooled waveform behind one shared limiter.

	A CHOICE MOVES WHEN THE VALUE CHANGES, not when a finger goes down on the
	control that will change it. So these two verbs have NO down edge of their own:
	`pressSpecFor` answers nil for both, a select-declared button is handed no
	press effect, and the select phase is reachable from a VALUE-CHANGE event
	only — an event carrying `reason = "activation"` is a completed press and
	belongs to the release phase whatever verb it names.

	(Review F2. Until it was fixed the property route resolved these two from
	`MAP` and ignored this rule entirely, so a `select`-declared control clicked
	going down and ticked coming up: two sensations for one choice, and the
	opposite of what the module, `api.md` and the parity doc all said.)

	Their `MAP` rows above stay as written, and are now purely the TOTALITY ledger
	— a thirteenth verb must surface in `unmappedVerbs()` — plus the preset for
	every verb the phases do not claim. ]]
haptics.PHASE_VERBS = table.freeze({ select = "select", adjust = "select" })

--[[ ONE FRAME AT 60 Hz. A POINTER press has two moments a hand can tell apart:
	the finger lands, then it lifts. A KEYBOARD or GAMEPAD press does not — the IAS
	`Activate` action resolves on the key going DOWN, so the completion event the
	release phase answers is raised in the same instant the engine would play the
	button's own press effect. Two sensations at one instant are not two
	sensations; they are one blurred pulse. See `onEvent`. ]]
haptics.SAME_INSTANT_SECONDS = 1 / 60

-- one frozen preset spec per mapped verb, built once at load so the decorate path
-- allocates nothing per button and the pool can be keyed by sensation
local PRESET_SPECS: { [string]: any } = {}
local PRESET_KEYS: { [string]: string } = {}
for verb, effectType in MAP do
	if type(effectType) == "string" then
		local spec = table.freeze({ kind = "preset", effect = effectType })
		PRESET_SPECS[verb] = spec
		PRESET_KEYS[verb] = sensory_profile.key(spec :: any)
	end
end
table.freeze(PRESET_SPECS)
table.freeze(PRESET_KEYS)

-- THE PER-CONTROL DECLARATION'S ARRIVAL POINT (director request 2026-08-13). The
-- renderer publishes `UI.sensoryFeedback(bp, { activation = … })`'s resolved verb
-- as this attribute on the materialized GuiButton
-- (`src/render/target_contract.luau`'s `setActivationFeedback`), so this adapter
-- can hand the ENGINE a different effect per control without knowing anything
-- about Facet's node graph. An attribute is data: reading one keeps this module
-- a subscriber rather than a second consumer of framework internals.
haptics.ACTIVATION_ATTRIBUTE = "Facet_ActivationFeedback"

--[[ WHAT A BUTTON'S PRESS SHOULD FEEL LIKE, given the verb the author declared on
	it (nil = undeclared). Three answers, and the third is the one that matters:

	  undeclared / `activate`   THE PRESS PHASE — Facet's own `contact` waveform by
	                            default, or whatever the game's profile replaced it
	                            with (including a silence).
	  a declared verb           that verb's mapped preset, exactly as before this
	                            module grew phases. A Buy button and a Delete
	                            button still feel different, and they still feel
	                            like what they always did.
	  `none`, or a verb the MAP silences   NOTHING. A `cancel` that buzzes would
	                            contradict the reason `cancel` is silent
	                            everywhere else — and the same answer decides the
	                            RELEASE edge, so such a control is unfelt on both.

	PURE, and profile-aware: `profile` defaults to Facet's own, which is what makes
	this callable from a test or a fixture with no adapter in hand. ]]
function haptics.pressSpecFor(verb: string?, profile: sensory_profile.SensoryProfile?): sensory_profile.PhaseSpec?
	if verb == nil or verb == "activate" then
		return (profile or sensory_profile.DEFAULTS).press
	end
	if verb == feedbackLib.ACTIVATION_SILENT then
		return nil
	end
	-- THE SELECT PHASE'S TWO VERBS HAVE NO DOWN EDGE (see `PHASE_VERBS`). They are
	-- still FELT — ask `activationIsFelt` — but what they are felt as is a choice
	-- moving, and a choice has not moved yet when the finger lands.
	if haptics.PHASE_VERBS[verb] ~= nil then
		return nil
	end
	if type(MAP[verb]) == "string" then
		return PRESET_SPECS[verb]
	end
	return nil
end

--[[ IS THIS CONTROL FELT AT ALL — a different question from what its DOWN edge
	feels like, and the two must not share an answer. They did until review F2: the
	release edge was gated on `pressSpecFor(verb) ~= nil`, so the moment the select
	phase's verbs lost their down edge they would have lost their completed edge
	too, silently.

	`nil` (undeclared) and `activate` are felt; every verb the MAP maps is felt;
	`none` and the four verbs the MAP deliberately silences are not — and a control
	that is unfelt is unfelt on BOTH edges, which is the rule a `cancel` button
	that refused to buzz going down must not break coming up. ]]
function haptics.activationIsFelt(verb: string?): boolean
	if verb == nil or verb == "activate" then
		return true
	end
	if verb == feedbackLib.ACTIVATION_SILENT then
		return false
	end
	return type(MAP[verb]) == "string"
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
	-- A GAME'S OWN PROFILE, merged over `sensory_profile.DEFAULTS` PER PHASE. A
	-- game replaces one phase, swaps it for a preset, or silences it
	-- (`{ kind = "silent" }`) without touching a single control. Anything it does
	-- not name keeps Facet's default. Validated at construction, so a typo is an
	-- authoring error rather than a session-long silence.
	profile: sensory_profile.PartialProfile?,
	-- monotonic seconds, for the select-phase rate limit (default os.clock)
	now: (() -> number)?,
	-- the SELECT PHASE floor. Sliders, steppers and scrubbed lists fire per tick;
	-- unthrottled that is a buzzsaw AND a breach of the documented "fewer than 100
	-- simultaneous effects" budget. Coalescing DROPS — a swallowed tick is never
	-- replayed late, because a haptic after the gesture is a phantom.
	selectIntervalSeconds: number?,
	-- the pre-phase spelling of the same floor, when it governed `adjust` alone.
	-- Still honoured so an existing caller keeps working; `selectIntervalSeconds`
	-- wins if both are given.
	adjustIntervalSeconds: number?,
	-- injection seams (the reason any of this is provable headless). `false`
	-- means "there is none", which is not the same as absent-and-unprobed.
	instanceNew: ((className: string) -> any)?,
	-- `FloatCurveKey.new(timeMs, intensity, Enum.KeyInterpolationMode)` — a
	-- DATA TYPE constructor, not a service, so it needs its own seam
	floatCurveKey: ((timeMs: number, intensity: number, mode: any) -> any)?,
	inputService: any?,
	hapticService: any?,
	enums: any?,
	-- where pooled effects are parented. Default: Workspace, MATCHING THE
	-- OFFICIAL SAMPLE — the docs state no parenting requirement, and this module
	-- does not claim one. `false` parents nothing.
	parent: any?,
}

-- PER PHASE, and honest about all three states. `effect` is the sensation this
-- phase is CURRENTLY serving (a waveform's name, a preset's name, or nil for a
-- silence or a phase nothing has needed yet); `fallbackActive` is true only once
-- the phase has actually been served by its preset because the Custom route would
-- not build here.
export type PhaseDiagnostics = {
	kind: string, -- "custom" | "preset" | "silent", as RESOLVED right now
	effect: string?,
	fallbackActive: boolean,
	plays: number,
}

export type Diagnostics = {
	enabled: boolean,
	support: Support,
	constructions: number,
	plays: number,
	coalesced: number,
	collapsed: number,
	ignored: number,
	unmapped: number,
	enumMisses: number,
	probes: number,
	pooled: number,
	decorated: number,
	phases: { press: PhaseDiagnostics, release: PhaseDiagnostics, select: PhaseDiagnostics },
	lastError: string?,
}

-- 60 ms, comfortably past the >= 50 ms the design asks for and comfortably inside
-- the 16 ms `tick` waveform, so two select pulses can never overlap.
local DEFAULT_SELECT_INTERVAL = 0.06
haptics.DEFAULT_SELECT_INTERVAL = DEFAULT_SELECT_INTERVAL

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
	local selectInterval: number = options.selectIntervalSeconds
		or options.adjustIntervalSeconds
		or DEFAULT_SELECT_INTERVAL
	local parentOption = options.parent

	--[[ THE PROFILE IS RESOLVED AND VALIDATED HERE, at construction, and never
		again. A misspelled phase or a keyless Custom waveform is an authoring error
		that throws in the caller's own frame; discovering it at the first pulse
		would mean discovering it as a silence, on a device, with nothing to read. ]]
	local resolvedProfile = sensory_profile.resolve(options.profile)
	-- ...and the two derived tables the hot path reads instead of recomputing:
	-- `sensory_profile.key` builds a string, and a string built per pulse is an
	-- allocation per pulse, which is the one thing this module promises not to do.
	local fallbackSpecs: { [string]: any } = {}
	local phaseKey: { [string]: string } = {}
	local fallbackKey: { [string]: string } = {}
	local phaseFallback: { [string]: boolean } = {}
	local phasePlays: { [string]: number } = {}
	for _, phase in sensory_profile.PHASES do
		fallbackSpecs[phase] = sensory_profile.fallbackFor(phase)
		phaseKey[phase] = sensory_profile.key((resolvedProfile :: any)[phase])
		fallbackKey[phase] = sensory_profile.key(fallbackSpecs[phase])
		phaseFallback[phase] = false
		phasePlays[phase] = 0
	end

	local enabled = options.enabled == true
	local disposed = false

	-- ONE effect per mapped verb the phases do not claim, played BY NAME from the
	-- bus. Never constructed per fire (the "fewer than 100 simultaneous effects"
	-- budget).
	local pool: { [string]: any } = {}
	--[[ THE SENSATION POOL, keyed by `sensory_profile.key(spec)` rather than by verb
		— the opposite of `pool` above, deliberately. A page of forty buttons
		declaring `commit`, `select` and `land` wants ONE UIClick instance shared by
		all forty, because what a button hands the engine is a sensation, not a verb;
		and the three PHASES belong here for the same reason (two phases that resolve
		to the same preset under fallback are one Instance, which is exactly the
		limitation `sensory_profile.FALLBACK` documents).

		(`pool` stays verb-keyed: its entries are played by name from the bus, and
		re-keying it would merge two effects an existing test counts separately.) ]]
	local sensations: { [string]: any } = {}

	local deviceVerdict: Support = "unknown"
	local constructionVerdict: Support? = nil
	local diag = {
		constructions = 0,
		plays = 0,
		coalesced = 0,
		-- bus causes dropped because another sensation for the same control had
		-- already been felt in the same instant (see `onEvent`'s same-instant rule).
		-- SEPARATE from `coalesced`, which is the select phase's rate limit: one is
		-- "too soon after the last tick", the other is "this is the same gesture".
		collapsed = 0,
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
	local lastSelectAt: number? = nil
	-- the last non-pointer activation: WHICH control, and WHEN. Both, because the
	-- collapse is per gesture — two different controls activated in one frame are
	-- two gestures, and the same control activated a frame later is a second press.
	local sameInstantPath: string? = nil
	local sameInstantAt: number? = nil

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
	local function resolveEnum(enumName: string, memberName: string): any?
		local source = if options.enums ~= nil then options.enums else nil
		local value = guard(function(): any
			local enums: any = if source ~= nil then source else Enum :: any
			return enums[enumName][memberName]
		end)
		if value == nil then
			diag.enumMisses += 1
		end
		return value
	end

	local function resolveEffectType(name: string): any?
		return resolveEnum("HapticEffectType", name)
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

	--[[ THE WAVEFORM, BUILT BEFORE THE INSTANCE — and the order is the whole
		safety property. `SetWaveformKeys` takes an array of `FloatCurveKey`, each
		constructed from a time in milliseconds, an intensity in [0, 1] and an
		`Enum.KeyInterpolationMode`; a client that cannot make one would otherwise
		leave us holding a `Custom` effect with no keys, which plays NOTHING while
		reporting success. Building the keys first means such a client never gets
		one: it gets the phase's documented preset instead. ]]
	local function waveformKeys(spec: any): { any }?
		local factory = options.floatCurveKey
		local out: { any } = {}
		for _, key in spec.keys do
			local mode = resolveEnum("KeyInterpolationMode", key.mode)
			if mode == nil then
				return nil
			end
			local built = guard(function(): any
				if factory ~= nil then
					return factory(key.timeMs, key.intensity, mode)
				end
				return (FloatCurveKey :: any).new(key.timeMs, key.intensity, mode)
			end)
			if built == nil then
				return nil
			end
			table.insert(out, built)
		end
		return out
	end

	-- ONE Instance from ONE resolved PhaseSpec, or nil. A `silent` spec builds
	-- nothing at all — silence is not an effect that happens to be quiet.
	local function buildFromSpec(spec: any): any?
		if spec.kind == "silent" then
			return nil
		end
		-- THE VERDICT IS ALREADY IN, and checking it HERE rather than only inside
		-- `construct` matters for two reasons. A client that cannot create the class
		-- would otherwise re-resolve `Enum.KeyInterpolationMode` and rebuild a key
		-- list for every button of every sweep, forever; and the second of those
		-- failed lookups would overwrite `lastError` — the engine's own words about
		-- why the class could not be made — with a far less informative one. The
		-- report is only as good as the message it keeps.
		if constructionVerdict == "absent" then
			return nil
		end
		if spec.kind == "preset" then
			return construct(spec.effect)
		end
		local keys = waveformKeys(spec)
		if keys == nil then
			return nil
		end
		local effect = construct("Custom")
		if effect == nil then
			return nil
		end
		local keyed = guard(function()
			effect:SetWaveformKeys(keys)
			return true
		end)
		if keyed ~= true then
			-- a Custom that would not take its waveform is a guaranteed silence:
			-- put it away rather than pool it
			retire(effect)
			return nil
		end
		return effect
	end

	-- pooled BY SENSATION (see `sensations` above): two phases, or forty buttons,
	-- that would feel identical share one Instance
	local function pooledEffect(spec: any, key: string): any?
		local existing = sensations[key]
		if existing ~= nil then
			return existing
		end
		local built = buildFromSpec(spec)
		if built == nil then
			return nil
		end
		sensations[key] = built
		return built
	end

	--[[ THE PHASE'S LIVE EFFECT, with the one fallback this module allows.

		LAZY, not eager: nothing is built until a phase is actually needed, which is
		the same rule the verb pool has always followed and the reason an adapter
		constructed enabled still builds nothing at boot. What the design asks for is
		that a pulse ALLOCATES NOTHING and that the waveform is written exactly once
		— both are properties of the pool, not of when it is filled.

		`fallbackActive` is set only once the preset has ACTUALLY been built and
		handed back. A phase whose Custom route failed AND whose preset route failed
		is not "on fallback"; it is silent, and `support()`/`lastError` are where that
		is explained. It is not reset by `setEnabled(false)`: whether this client can
		make a `FloatCurveKey` is a fact about the client, not about the switch. ]]
	local function phaseEffect(phase: string): any?
		if not enabled or disposed then
			return nil
		end
		local onFallback = phaseFallback[phase]
		local spec = if onFallback then fallbackSpecs[phase] else (resolvedProfile :: any)[phase]
		if spec.kind == "silent" then
			return nil
		end
		local key = if onFallback then fallbackKey[phase] else phaseKey[phase]
		local existing = sensations[key]
		if existing ~= nil then
			return existing
		end
		local built = buildFromSpec(spec)
		if built ~= nil then
			sensations[key] = built
			return built
		end
		if onFallback or spec.kind ~= "custom" then
			return nil
		end
		local viaPreset = pooledEffect(fallbackSpecs[phase], fallbackKey[phase])
		if viaPreset == nil then
			return nil
		end
		phaseFallback[phase] = true
		return viaPreset
	end

	-- THE ONE `Play` CALL SITE IN THIS MODULE, and it is deliberately the only one:
	-- a button's press effect is handed to the ENGINE and never played from here,
	-- which is what keeps "Facet plays nothing" literally true (pinned structurally
	-- by tests/haptics.spec.luau).
	local function play(effect: any?): boolean
		if effect == nil then
			return false
		end
		local played = guard(function()
			effect:Play()
			return true
		end)
		if played == true then
			diag.plays += 1
			return true
		end
		return false
	end

	-- DERIVED, NEVER COUNTED. The counter this replaced read 0 while fifteen
	-- effects sat in Workspace, because it was maintained beside the pool instead
	-- of from it and never knew the press effect existed at all.
	local function pooledCount(): number
		local n = 0
		for _ in sensations do
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
		-- only "most" phones have haptics, so a phone is
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
	-- THE ONLY CALLER OF THE PRESS PHASE. Nothing on the bus can reach it, which
	-- is what makes "the bus never replays the down edge" structural rather than a
	-- rule somebody has to keep remembering.
	local function pressEffectHandle(verb: string?): any?
		if not enabled then
			return nil
		end
		if verb == nil or verb == "activate" then
			return phaseEffect("press")
		end
		local spec = PRESET_SPECS[verb]
		if spec == nil then
			return nil
		end
		return pooledEffect(spec, PRESET_KEYS[verb])
	end

	local function isGuiButton(instance: any): boolean
		local result = guard(function()
			return instance:IsA("GuiButton")
		end)
		return result == true
	end

	-- IS THIS CONTROL STILL AN AFFORDANCE? `enabled = false` on a Facet Button
	-- writes `Active = false`, and under native styling `Interactable = false` as
	-- well (src/client/screen_target.luau's `enabled` branch). A disabled control
	-- holding a press effect is a promise it does not keep, so it is skipped — and
	-- a control that BECOMES disabled has its reference cleared on the next sweep,
	-- for the same reason `none` clears rather than skips.
	local function isDisabled(instance: any): boolean
		local active = guard(function(): any
			return instance.Active
		end)
		if active == false then
			return true
		end
		local interactable = guard(function(): any
			return instance.Interactable
		end)
		return interactable == false
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
		local verb: string? = if type(declaredVerb) == "string" then declaredVerb else nil
		local spec = haptics.pressSpecFor(verb, resolvedProfile)
		if spec == nil or (spec :: any).kind == "silent" or isDisabled(instance) then
			-- DELIBERATELY UNFELT (`none`, a verb the MAP silences, a phase this
			-- game silenced, or a control that is disabled). Clearing rather than
			-- skipping: a button that was decorated and is now silent — because the
			-- adapter re-swept, because it was disabled, or because another writer
			-- set the property — must actually lose its reference, or "none" would
			-- mean "none unless somebody already said otherwise".
			guard(function()
				instance.PressHapticEffect = nil
				return nil
			end)
			entry.decorated[instance] = nil
			return
		end
		local effect = pressEffectHandle(verb)
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
	-- every pooled SENSATION destroyed rather than merely forgotten. The phase
	-- effects live in the same pool as the press route's presets, so one loop puts
	-- all of them away and nothing can be forgotten by being a different kind.
	local function undecorateAll()
		for _, entry in roots do
			undecorateEntry(entry)
		end
		for key, effect in sensations do
			retire(effect)
			sensations[key] = nil
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
		local path = if type(event.path) == "string" then event.path else nil
		--[[ THE SAME-INSTANT COLLAPSE (review F4's keyboard/gamepad analysis).

			A POINTER press has two moments a hand can tell apart — the finger lands,
			then it lifts — and they get two sensations: the engine's `contact` going
			down and the bus's `settle` at the completion. A KEYBOARD or GAMEPAD press
			has ONE moment: the IAS `Activate` action resolves on the key going down,
			so the completion event is raised in the same instant the engine would
			play the press effect. Two sensations at one instant are not two
			sensations; they are one blurred pulse.

			So for an activation the presenter marks as non-pointer, the BUS
			contributes exactly ONE sensation — `settle`, the answer to a completed
			action — and anything else it would have played for that same control in
			that same instant is DROPPED. Dropped, never deferred: a haptic that
			arrives after the gesture is a phantom, which is the same rule the select
			limiter follows.

			`context.source` is the presenter's own classification (`"action"` is the
			IAS path, `"pointer"` is a real pointer gesture); this module reads it as
			DATA and adds no listener of its own. What it cannot do is silence the
			ENGINE's `contact` in that instant — that is the engine's, and whether it
			fires at all for a non-pointer press is undocumented. The device packet's
			keyboard and gamepad rows ask a hand. ]]
		if path ~= nil and sameInstantPath == path and sameInstantAt ~= nil then
			if (now() - sameInstantAt) < haptics.SAME_INSTANT_SECONDS then
				diag.collapsed += 1
				return
			end
			sameInstantPath, sameInstantAt = nil, nil
		end
		--[[ A COMPLETED ACTIVATION IS THE RELEASE PHASE'S, WHATEVER VERB IT NAMES.
			The presenter stamps `reason = "activation"` on the event a control's own
			activation raises, and that event exists only when the activation
			COMPLETED — the engine's `GuiButton.Activated` does not fire for a press
			that was dragged away from, and the presenter's echo window collapses the
			keyboard/gamepad pair into one dispatch. So this is the up edge, the
			engine already played the down edge through the button's own property, and
			there is no double pulse: two moments, two sensations, two owners.

			IT IS CHECKED BEFORE THE SELECT PHASE (review F2), and the order is the
			rule: a verb says WHAT happened, `reason` says A CONTROL WAS PRESSED, and
			a press completing is not a choice moving. A `select`-declared control
			therefore feels `settle` when it is pressed and `tick` when its VALUE
			changes — one sensation per thing that actually happened, instead of the
			click-then-tick pair the two routes used to produce between them.

			A control that is deliberately unfelt is unfelt on BOTH edges — `cancel`
			and its three silent siblings, and anything declared `none` — so a button
			that refused to buzz on the way down cannot buzz on the way up. ]]
		if event.reason == "activation" then
			if not haptics.activationIsFelt(verb) then
				diag.ignored += 1
				return
			end
			if play(phaseEffect("release")) then
				phasePlays.release += 1
			end
			-- ARM THE COLLAPSE only for the input classes that need it. A pointer
			-- gesture's two moments are genuinely apart, and collapsing them would
			-- swallow the value change a tap on a picker row causes.
			local context = event.context
			if path ~= nil and type(context) == "table" and context.source == "action" then
				sameInstantPath, sameInstantAt = path, now()
			end
			return
		end
		--[[ THE SELECT PHASE, reachable from a VALUE CHANGE only. ONE LIMITER FOR
			THE PAIR, deliberately: two limiters (one per verb) would let a control
			alternating `select` and `adjust` — which a scrubbed picker does — pass
			both and fire at full rate. Leading edge: a suppressed pulse is DROPPED
			and never replayed. ]]
		if haptics.PHASE_VERBS[verb] ~= nil then
			local at = now()
			local previous = lastSelectAt
			if previous ~= nil and (at - previous) < selectInterval then
				diag.coalesced += 1
				return
			end
			lastSelectAt = at
			if play(phaseEffect("select")) then
				phasePlays.select += 1
			end
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
		play(effectFor(verb, effectTypeName))
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
			lastSelectAt = nil
			sameInstantPath, sameInstantAt = nil, nil
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

	--[[ WHAT EACH PHASE IS CURRENTLY SERVING, derived at read time from the resolved
		profile and the live fallback state — never a snapshot taken when something
		was decided. `effect` is nil for a silence AND for a phase that resolved to
		nothing buildable, which is why `kind` rides beside it: a reader can tell
		"this game silenced it" from "this client could not". ]]
	local function phaseDiagnostics(phase: string): PhaseDiagnostics
		local onFallback = phaseFallback[phase]
		local spec: any = if onFallback then fallbackSpecs[phase] else (resolvedProfile :: any)[phase]
		return {
			kind = spec.kind,
			effect = sensory_profile.label(spec),
			fallbackActive = onFallback,
			plays = phasePlays[phase],
		}
	end

	function adapter.diagnostics(): Diagnostics
		return {
			enabled = enabled,
			support = adapter.support(),
			phases = {
				press = phaseDiagnostics("press"),
				release = phaseDiagnostics("release"),
				select = phaseDiagnostics("select"),
			},
			constructions = diag.constructions,
			plays = diag.plays,
			coalesced = diag.coalesced,
			collapsed = diag.collapsed,
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
