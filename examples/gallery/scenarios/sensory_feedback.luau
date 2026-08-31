--!strict
--[[ Scenario 'sensory_feedback' — WHAT DOES PRESSING THIS FEEL LIKE?

	THE SWITCH THAT DECIDES EVERYTHING IS FIRST, AND IT IS ON. The surface used to
	end with it: five verbs, one cascade, a table of what an adapter *would* play,
	and only then — seventh of eight panels — the toggle that made any of it reach
	the device, starting OFF. That is a good story and a bad demo, so the panel now
	sits directly under the title and one sentence, above every control it affects,
	and it opens ON. Everything above the four comparisons fits the first viewport
	on compact portrait, short landscape, desktop and ten-foot INCLUDING at the
	Largest text preference, and that is proved from solved geometry in
	tests/control_feedback.spec.luau — never from the order of this file.

	ON BY DEFAULT IS THE DEMO'S DECISION, NOT THE LIBRARY'S, and the two are
	different sentences. Facet's contract is unchanged: `src/present/feedback.luau`
	says what happened and plays nothing, and `src/client/haptics.luau` is an opt-in
	client adapter a GAME constructs (pinned by tests/haptics.spec.luau's
	"default OFF means the engine is never touched"). THIS EXAMPLE IS A GAME, and
	it opts in — it requests and installs the adapter at mount so that pressing a
	sample control demonstrates the feature immediately instead of after four
	panels of reading.

	THE STATUS REPORTS WHAT ACTUALLY HAPPENED, IN THREE STATES, and never that a
	player felt anything — Roblox exposes no motor confirmation, so a claim of
	sensation is a claim nothing can support:

	  INSTALLED      the adapter is up and holding Facet's own waveforms.
	  HOST DECLINED  a connected pad answers `false`, or this client cannot build
	                 a `HapticEffect` at all. The request STAYS ON.
	  UNDETERMINED   everything else — and it is not a failure. Touch has no probe
	                 on the platform at all, and an absent gamepad answers exactly
	                 as a motorless one does. The request STAYS ON.

	The five-value lattice, the decorated count and the engine's own words ride a
	separate evidence line under the panel, so a reviewer can argue with the
	conclusion rather than only with the word — and so the sentence a player reads
	stays one short line.

	FOUR PLAYABLE COMPARISONS, each a labelled row with a live control, a live
	readout, and a note saying whether it uses a BUILT-IN DEFAULT or THIS EXAMPLE'S
	OWN OVERRIDE:

	  PRESS      an ordinary control, no local declaration. The DOWN edge is the
	             ENGINE's, through `GuiButton.PressHapticEffect`, and what it holds
	             is Facet's own `contact` waveform. Nothing in this file asked for
	             it; it is what the library does.
	  RELEASE    the other end of the same interaction: a COMPLETED press asks for
	             `settle`, which is a different waveform from the press. The row
	             also carries the CANCEL — press, slide off, let go — which is
	             structurally silent (`GuiButton.Activated` never fires for a press
	             that was dragged away from), and the history says "(no request)"
	             rather than pretending the activation succeeded.
	  SELECTION  a real discrete choice. `tick` is asked for when the VALUE CHANGES
	             and at no other moment: re-picking what is already picked is a
	             visible "(no request)", and hover has no cause in Facet's taxonomy
	             at all, so there is nothing for it to fire.
	  CUSTOM     one control whose feel this example supplies, through the
	             documented public seam and nothing else: a PARTIAL PROFILE handed
	             to `haptics.new({ profile = … })` and resolved against the shipped
	             defaults (docs/guide/07-input.md). No `HapticEffect` is constructed
	             here and no adapter internal is reached.

	WHY THE CUSTOM ROW HAS ITS OWN ADAPTER, stated plainly because it is the one
	structural surprise on this surface. A profile is ADAPTER-WIDE by design — one
	declaration, no control touched — and Facet has exactly three phases. Rows 1-3
	spend all three on the shipped defaults, so there is no fourth phase left for a
	custom waveform to occupy: an override on the ONE installed adapter would move
	the very waveform the row beside it is there to demonstrate. So:

	  THE INSTALLED ADAPTER  is the only one bound to the presenter and the only one
	                         attached to the interface root. It carries Facet's
	                         defaults and serves the Press, Release and Selection
	                         rows. Exactly one of these exists, ever.
	  THE OVERRIDE ADAPTER   is never bound to the presenter and never attached to
	                         any root, so no control on this page — or anywhere else
	                         in the showcase — can reach it. The Custom row hands it
	                         ONE cause through `bind`'s documented shape
	                         ("something with an `onFeedback(fn) -> unsubscribe`"),
	                         which is why the two can never both answer one gesture.

	That is the whole reason a duplicate pulse is impossible here rather than
	merely unobserved, and tests/control_feedback.spec.luau censuses the history
	per input path — pointer/touch, keyboard, gamepad — rather than watching it.

	THE HISTORY IS THE DEMO. The last `HISTORY_LINES` requests, newest first: the
	phase, the waveform's own name, what caused it, and whether the profile was a
	built-in default or this example's override. It shows what was REQUESTED and
	never that a motor moved. Bounded for the reason `lifecycle_hidden` bounds its
	own: an unbounded log in a demo four input paths can hammer is a leak with a
	nice name.

	WHAT IS KEPT FROM THE OLD SURFACE, because it teaches a different thing: the
	five identical-looking buttons that report four different verbs (and `Mute`,
	which reports nothing and whose line therefore never appears), and the cascade
	where ONE declaration on a panel reaches three controls including a nested pair.
	WHAT IS GONE: the "Sensations" table of what an adapter *would* play, and the
	calibration panel's phase table — both were maps of a thing the four rows now
	actually do, and both were written-out copies that could drift. Every identity
	on this page is now READ FROM THE INSTALLED ADAPTER, so there is nothing left to
	drift.

	NOTHING HERE IS FIXED AGAINST AN UNFIXED VIEWPORT: no panel declares a height,
	the button rows WRAP rather than running off the edge, and the page scrolls.

	TWO HOSTS MOUNT THIS FILE and only one of them runs steps (the pair
	`lifecycle_hidden.luau` documents): the scenario runner drives `steps` by name,
	and the showcase demo picker mounts it with a minimal ctx and no step ever runs.
]]

-- how many request lines the history keeps. See the header.
local HISTORY_LINES = 10

--[[ EVERY PLAYER-VISIBLE STRING, in one table, EXPORTED as `copy` — the contract
	`flow_wrap.luau` and `lifecycle_hidden.luau` carry, so the localization case in
	tests/examples_gallery.spec.luau can re-run the whole fixture through a ~1.4x
	pseudo-localizing expansion. Flat keys only: the pseudo-localizer walks values
	and would throw on a nested table. Every branch is a WHOLE SENTENCE rather than
	a fragment assembled at a call site, because a sentence stitched from three of
	them expands in three places at once. ]]
local COPY = {
	title = "Sensory feedback",
	intro = "Facet reports what an interaction MEANT. A game decides what that feels like.",

	-- ===== the panel that decides everything, and it is FIRST ==============
	playToggle = "Haptics on this device",
	playNote = "This demo asks for haptics when it opens.",
	playLibrary = "Facet ships them off until a game asks.",
	stateOffHeadline = "Off",
	stateOff = "Nothing installed or claimed.",
	stateRequestedHeadline = "On · installed",
	requestedDetail = "Facet's own waveforms are in place.",
	stateRefusedHeadline = "On · host declined",
	refusedDetail = "The controls below still report what they meant.",
	stateUnknownHeadline = "On · support unknown",
	unknownDetail = "Roblox cannot tell whether this device has a motor.",
	-- the evidence line: the lattice verbatim, so the conclusion can be argued with
	supportPrefix = "support()",
	decoratedSuffix = "buttons holding a press effect",
	evidenceOff = "Nothing is installed, and nothing is claimed about this device.",
	refusedNoMotor = "a gamepad IS connected and reports no vibration motor.",
	refusedAbsent = "this client cannot construct a HapticEffect at all, so no route to a motor exists.",
	unknownBlocked = "the engine refused for a reason that is not a missing motor, and this surface will not guess which.",
	unknownNoProbe = "the effects went out and the engine is holding them; nothing on this platform can be asked whether they will be felt.",
	unknownNoRoot = "no interface root could be reached, so no button was handed a press effect.",
	unknownNothingDecorated = "a root was reached but no button under it took a press effect.",
	unknownNoModule = "the haptics adapter could not be loaded on this host, so nothing was requested.",

	-- ===== the four comparisons ===========================================
	sourceBuiltIn = "built-in default",
	sourceOverride = "custom (this example's override)",
	pressTitle = "1 · Press",
	pressLabel = "Press sample",
	pressNote = "An ordinary control that declares nothing. The DOWN edge belongs to the engine, through the button's own press property, and what Facet hands it is the waveform below.",
	statePressed = "pressed",
	stateIdle = "not pressed",
	releaseTitle = "2 · Release",
	releaseLabel = "Release sample",
	releaseNote = "The other end of the same interaction. Let go ON the control for the completed edge; press it, slide off and let go for the cancel — a press that was dragged away from never completes, so it is silent by construction.",
	stateReleased = "released",
	stateCancelled = "cancelled — the press never completed",
	stateWaiting = "waiting for a press",
	selectTitle = "3 · Selection",
	selectLabel = "Picker",
	selectNote = "A choice moves when the VALUE changes, which is the only moment the tick is asked for. Pick what is already picked and the history says so; hover has no cause in Facet's taxonomy at all, so there is nothing for it to fire.",
	selectLow = "Soft",
	selectMedium = "Medium",
	selectStrong = "Strong",
	customTitle = "4 · Custom",
	customLabel = "Custom sample",
	customNote = "This example hands the adapter a PARTIAL profile — one phase named, the other two left as Facet shipped them — through the same public seam a game uses. Nothing here builds an effect or reaches inside the adapter.",
	customLonger = "Deliberately longer than anything Facet ships: the >= 0.3 peak and <= 34 ms budget are constraints on FACET'S defaults, not on a game's taste.",
	phasePrefix = "asks for",

	-- ===== the history ====================================================
	historyTitle = "What was requested",
	historyEmpty = "Nothing yet — press a control above.",
	historyNote = "The last ten requests, newest first. A REQUEST, never a claim that a motor moved: whether a HapticEffect actually fired is not readable from game code.",
	noRequest = "(no request)",
	whyCancelled = "press did not complete",
	whyUnchanged = "value unchanged",
	whyOff = "haptics off",
	requestsPrefix = "Requests",
	causeCancelled = "cancelled",
	causeAgain = "again",

	-- ===== what is kept: the declaration forms and the cascade ============
	declaredTitle = "Declared one by one",
	buy = "Buy",
	delete = "Delete",
	pick = "Pick",
	mute = "Mute",
	plain = "Plain",
	muteNote = "Mute declares `none`: it activates, and reports nothing. Its line never appears.",
	cascadeTitle = "Declared once, on the panel",
	cascadeNote = "One declaration on this panel. All three buttons inherit it — including the nested pair.",
	first = "First",
	second = "Second",
	third = "Third",

	unknowableTitle = "What no game code can read",
	unknowable = "Whether a HapticEffect actually fired, and the player's own haptics strength — UserGameSettings.HapticStrength is RobloxScriptSecurity on read. Neither is a thing this screen can honestly claim, in either direction.",
}

-- the five leaf declarations, in press order. `nil` is "declares nothing", which
-- is the default every control has always had.
local DECLARED: { { id: string, copyKey: string, activation: string? } } = {
	{ id = "Buy", copyKey = "buy", activation = "commit" },
	{ id = "Delete", copyKey = "delete", activation = "reject" },
	{ id = "Pick", copyKey = "pick", activation = "select" },
	{ id = "Mute", copyKey = "mute", activation = "none" },
	{ id = "Plain", copyKey = "plain", activation = nil },
}

--[[ THIS EXAMPLE'S OWN WAVEFORM, and the whole of its reach into the framework:
	a PARTIAL profile, handed to `haptics.new({ profile = … })` and resolved
	against `sensory_profile.DEFAULTS`. One phase is named; `press` and `select`
	are not, so they keep Facet's shipped waveforms — which is what a partial
	profile is FOR, and is asserted rather than described
	(tests/control_feedback.spec.luau).

	OBVIOUSLY DISTINCT ON PURPOSE. Twice the length of `settle`, a two-stage rise
	instead of one, and a peak between `contact`'s and `tick`'s: a hand can tell it
	from the built-ins with no instruments. It is BOUNDED — 60 ms, written out —
	and it deliberately runs past the <= 34 ms budget Facet holds its OWN defaults
	to, because `sensory_profile.resolve` says in as many words that the budget
	governs Facet's taste and not a game's. ]]
local CUSTOM_WAVEFORM_NAME = "swell"
local CUSTOM_PROFILE = table.freeze({
	release = table.freeze({
		kind = "custom",
		name = CUSTOM_WAVEFORM_NAME,
		keys = table.freeze({
			table.freeze({ timeMs = 0, intensity = 0, mode = "Linear" }),
			table.freeze({ timeMs = 14, intensity = 0.45, mode = "Linear" }),
			table.freeze({ timeMs = 30, intensity = 0.85, mode = "Cubic" }),
			table.freeze({ timeMs = 60, intensity = 0, mode = "Linear" }),
		}),
	}),
})

-- ===== the opt-in's plumbing ===============================================
-- THE THREE ANSWERS, as three values rather than one boolean. A capability
-- probe must be tri-state, and that rule was written after a boolean probe
-- published two false platform facts, so `refused`
-- and `undetermined` are separate states carrying separate sentences, and they
-- are named here so a caller cannot spell one of them differently.
local STATE_OFF = "off"
local STATE_REQUESTED = "requested"
local STATE_REFUSED = "refused"
local STATE_UNDETERMINED = "undetermined"

-- the three choices the Selection row offers, and the one it opens on
local CHOICES: { { id: string, copyKey: string } } = {
	{ id = "ChoiceSoft", copyKey = "selectLow" },
	{ id = "ChoiceMedium", copyKey = "selectMedium" },
	{ id = "ChoiceStrong", copyKey = "selectStrong" },
}
local FIRST_CHOICE = CHOICES[1].id
-- id -> the COPY key that names it, so a history line and a readout print the
-- LOCALIZED word rather than the node id the pseudo-localizing pass never sees
local CHOICE_KEY: { [string]: string } = {}
for _, option in CHOICES do
	CHOICE_KEY[option.id] = option.copyKey
end

-- what a readout prints for a phase nothing is currently serving
local NO_EFFECT = "—"

export type Facts = {
	-- did the adapter MODULE load at all? A host where it did not is a fact about
	-- this build, never about the device.
	adapterLoaded: boolean,
	moduleError: string?,
	rootError: string?,
	-- the adapter's own five-state lattice, verbatim
	support: string?,
	decorated: number?,
	lastError: string?,
}

--[[ HOW THE ADAPTER IS FOUND, and why it is a search rather than a require at the
	top of this file.

	Two hosts, two different instance trees. `tools/build_places.sh` maps `src` to
	`ReplicatedStorage.Facet` and this directory to `ReplicatedStorage.FacetScenarios`
	— SIBLING trees, so no relative path between them exists in the place even
	though one exists on disk. The headless suite is the mirror image: it has a
	filesystem and no `game`. Each route is therefore the ONLY route on the host it
	serves, both are pcall-guarded, and a failure keeps the engine's own words
	instead of turning into a claim about hardware.

	It is deliberately NOT at module scope: a fixture that fails to require is a
	demo the picker cannot mount at all, and this one still has plenty to show when
	the adapter cannot be reached. ]]
local function resolveAdapterModule(): (any?, string?)
	local reasons: { string } = {}
	local engineOk, engineResult = pcall(function(): any
		return require((game :: any):GetService("ReplicatedStorage").Facet.client.haptics)
	end)
	if engineOk and engineResult ~= nil then
		return engineResult, nil
	end
	table.insert(reasons, `engine route: {tostring(engineResult)}`)
	local fileOk, fileResult = pcall(function(): any
		return require("../../../src/client/haptics")
	end)
	if fileOk and fileResult ~= nil then
		return fileResult, nil
	end
	table.insert(reasons, `file route: {tostring(fileResult)}`)
	return nil, table.concat(reasons, " | ")
end

--[[ ...and the root the press effects are handed to. `attachButtons` needs a real
	Instance — that is the whole mechanism, since `GuiButton.PressHapticEffect` is
	an assignable reference the ENGINE fires — and a scenario has no handle on the
	ScreenGui the host presented it into. `PlayerGui` is the container that holds it
	either way, and the same reach a sibling fixture already makes
	(`theme_authoring.luau` walks it for the installed StyleSheet).

	THE BREADTH IS DISCLOSED RATHER THAN NARROWED: while the switch is on, every
	button on this client carries its declared press effect, chrome included. That
	is what a device pass wants — press anything, judge whether this hardware does
	haptics at all — and `attachButtons` records per root, so switching off or
	leaving the demo clears every one of them. ]]
local function resolveUiRoot(): (any?, string?)
	local ok, result = pcall(function(): any
		local player = (game :: any):GetService("Players").LocalPlayer
		if player == nil then
			error("this peer has no LocalPlayer", 0)
		end
		local gui = player:FindFirstChildOfClass("PlayerGui")
		if gui == nil then
			error("the LocalPlayer has no PlayerGui yet", 0)
		end
		return gui
	end)
	if ok and result ~= nil then
		return result, nil
	end
	return nil, tostring(result)
end

--[[ classify(facts) -> { state, headline, detail, evidence } — PURE, and the whole
	testable part of the report. A headless target cannot fire a motor and cannot
	read whether one fired, so what is provable is the DECISION and the REPORTED
	STATE.

	THE ORDER OF THE BRANCHES IS THE ARGUMENT. A construction verdict outranks a
	device one (the adapter's own rule: if the class cannot be built, what the pads
	say is irrelevant), `blocked` is could-not-tell rather than no, and the two "we
	never even asked" cases are separated from both so that a missing root never
	reads as a hardware refusal.

	`detail` IS THE PLAYER'S SENTENCE AND `evidence` IS THE REVIEWER'S. The detail
	is one short line and sits inside the first viewport at every profile and text
	preference; the evidence carries `support()` verbatim, the decorated count and
	the engine's own words, and is allowed to be long and to sit below the fold. A
	single field would have had to be one or the other. ]]
local function classify(facts: Facts): { state: string, headline: string, detail: string, evidence: string }
	local support = facts.support
	local decorated = facts.decorated or 0
	local function record(state: string, headline: string, detail: string, why: string, raw: string?): any
		local parts = {
			why,
			`{COPY.supportPrefix} = {tostring(support or "—")}`,
			`{decorated} {COPY.decoratedSuffix}`,
		}
		if raw ~= nil and raw ~= "" then
			table.insert(parts, raw)
		end
		return { state = state, headline = headline, detail = detail, evidence = table.concat(parts, " · ") }
	end
	local unknown = COPY.stateUnknownHeadline
	if not facts.adapterLoaded then
		return record(STATE_UNDETERMINED, unknown, COPY.unknownDetail, COPY.unknownNoModule, facts.moduleError)
	end
	if support == "absent" then
		return record(STATE_REFUSED, COPY.stateRefusedHeadline, COPY.refusedDetail, COPY.refusedAbsent, facts.lastError)
	end
	if support == "unsupported" then
		return record(STATE_REFUSED, COPY.stateRefusedHeadline, COPY.refusedDetail, COPY.refusedNoMotor, nil)
	end
	if support == "blocked" then
		return record(STATE_UNDETERMINED, unknown, COPY.unknownDetail, COPY.unknownBlocked, facts.lastError)
	end
	if facts.rootError ~= nil then
		return record(STATE_UNDETERMINED, unknown, COPY.unknownDetail, COPY.unknownNoRoot, facts.rootError)
	end
	if decorated == 0 then
		return record(STATE_UNDETERMINED, unknown, COPY.unknownDetail, COPY.unknownNothingDecorated, facts.lastError)
	end
	if support == "supported" then
		return record(STATE_REQUESTED, COPY.stateRequestedHeadline, COPY.requestedDetail, COPY.unknownNoProbe, nil)
	end
	return record(STATE_UNDETERMINED, unknown, COPY.unknownDetail, COPY.unknownNoProbe, nil)
end

return {
	title = "Sensory feedback per control",
	ledgerRows = {},
	copy = COPY,
	classify = classify,
	states = table.freeze({
		off = STATE_OFF,
		requested = STATE_REQUESTED,
		refused = STATE_REFUSED,
		undetermined = STATE_UNDETERMINED,
	}),
	historyLines = HISTORY_LINES,
	declared = DECLARED,
	choices = CHOICES,
	-- the example's override, exported so a test can pin the identity it produces
	-- against the one it declared rather than believing the screen
	customProfile = CUSTOM_PROFILE,
	customWaveform = CUSTOM_WAVEFORM_NAME,

	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI = Facet.UI
		local core = ctx.core
		local scope = core:scope("sensory-feedback")

		-- ===== the report the panel at the top publishes ===================
		-- DEFAULT TRUE. This is the DEMO opting in — see the header — and it is the
		-- one line of this file that a reader must not confuse with the library's
		-- own posture.
		local playHaptics = scope:own(core:signal(true))
		local hapticsState = scope:own(core:signal(STATE_OFF))
		local hapticsHeadline = scope:own(core:signal(COPY.stateOffHeadline))
		local hapticsDetail = scope:own(core:signal(COPY.stateOff))
		local hapticsEvidence = scope:own(core:signal(COPY.evidenceOff))

		-- ===== the four rows' live readouts ================================
		local historyText = scope:own(core:signal(COPY.historyEmpty))
		local requests = scope:own(core:signal(0))
		local heldPath = scope:own(core:signal(""))
		local releaseOutcome = scope:own(core:signal(COPY.stateWaiting))
		local choice = scope:own(core:signal(FIRST_CHOICE))
		-- the waveform each phase is CURRENTLY serving, read off the installed
		-- adapters rather than written out here. A written-out table is the shape
		-- that drifts into fiction; there is nothing left on this page to drift.
		local pressEffect = scope:own(core:signal(NO_EFFECT))
		local releaseEffect = scope:own(core:signal(NO_EFFECT))
		local selectEffect = scope:own(core:signal(NO_EFFECT))
		local customEffect = scope:own(core:signal(NO_EFFECT))

		local history: { string } = {}

		-- the two adapters, and the releases they handed back. See the header for
		-- why there are two and why only one of them can hear a control.
		local hap: any = nil
		local customHap: any = nil
		local unbindHaptics: (() -> ())? = nil
		local unbindCustom: (() -> ())? = nil
		local detachHaptics: (() -> ())? = nil
		local adapterModule: any = nil
		local rootError: string? = nil
		local moduleError: string? = nil
		local installed = false
		local teardown = false
		--[[ THE ONE SEAM, and its DEFAULT is what both shipped hosts run. A test
			hands in a scripted engine (a module, a root, and the adapter's own
			injection options) so all three states can be driven with no hardware;
			with nothing handed in, `install` takes the real routes — which is what
			makes "with NOTHING injected it still installs" a test of the shipped path
			rather than of the rig. Named `scriptedEngine` and not `deps` because that
			is all it may ever be: it never changes the DECISION, only where the facts
			come from. ]]
		local scriptedEngine: any = nil

		--[[ THE OVERRIDE ADAPTER'S ONLY WAY IN, and the reason a duplicate pulse is
			impossible rather than merely unobserved. `bind` documents what it takes:
			"something with an `onFeedback(fn) -> unsubscribe` — a presenter, or a
			presented handle for one surface only". This is that shape and nothing
			more: one list, one push, no engine, no framework internal. Nothing on the
			presenter's bus can reach it, so the Custom row's cause is the ONLY cause
			the override adapter will ever answer. ]]
		local customSinks: { (any) -> () } = {}
		local customBus = {
			onFeedback = function(fn: (any) -> ()): () -> ()
				table.insert(customSinks, fn)
				return function()
					local index = table.find(customSinks, fn)
					if index ~= nil then
						table.remove(customSinks, index)
					end
				end
			end,
		}

		-- ===== the history =================================================
		local function pushLine(line: string)
			if teardown then
				return
			end
			-- NEWEST FIRST, and BOUNDED: four input paths can hammer this surface,
			-- and an unbounded log is a Text that grows on every press.
			table.insert(history, 1, line)
			while #history > HISTORY_LINES do
				table.remove(history)
			end
			historyText:set(table.concat(history, "\n"))
		end

		local function noteRequest(phase: string, effect: string?, cause: string, source: string)
			if effect == nil or effect == NO_EFFECT then
				-- nothing is installed, or this game silenced the phase: an absence is
				-- invisible until something says it was deliberate
				pushLine(`{COPY.noRequest} · {cause} · {COPY.whyOff}`)
				return
			end
			pushLine(`{phase} {effect} · {cause} · {source}`)
			requests:set(requests:get() + 1)
		end

		local function noteNothing(cause: string, why: string)
			pushLine(`{COPY.noRequest} · {cause} · {why}`)
		end

		-- ===== what the adapters are currently serving =====================
		local function phaseOf(handle: any, phase: string): string?
			if handle == nil then
				return nil
			end
			local ok, diagnostics = pcall(handle.diagnostics)
			if not ok or diagnostics == nil then
				return nil
			end
			local phases: any = diagnostics.phases
			if phases == nil or phases[phase] == nil then
				return nil
			end
			return phases[phase].effect
		end

		local function publishPhases()
			if teardown then
				return
			end
			pressEffect:set(phaseOf(hap, "press") or NO_EFFECT)
			releaseEffect:set(phaseOf(hap, "release") or NO_EFFECT)
			selectEffect:set(phaseOf(hap, "select") or NO_EFFECT)
			customEffect:set(phaseOf(customHap, "release") or NO_EFFECT)
		end

		local function publish()
			if teardown then
				return
			end
			if not installed then
				hapticsState:set(STATE_OFF)
				hapticsHeadline:set(COPY.stateOffHeadline)
				hapticsDetail:set(COPY.stateOff)
				hapticsEvidence:set(COPY.evidenceOff)
				return
			end
			local facts: Facts
			if hap == nil then
				facts = { adapterLoaded = false, moduleError = moduleError, decorated = 0 }
			else
				local diagnostics = hap.diagnostics()
				facts = {
					adapterLoaded = true,
					rootError = rootError,
					support = diagnostics.support,
					decorated = diagnostics.decorated,
					lastError = diagnostics.lastError,
				}
			end
			local verdict = classify(facts)
			hapticsState:set(verdict.state)
			hapticsHeadline:set(verdict.headline)
			hapticsDetail:set(verdict.detail)
			hapticsEvidence:set(verdict.evidence)
		end

		-- PUTTING IT AWAY IS THE PATH THAT HAS TO BE AIRTIGHT (the adapter's own
		-- header says so): `dispose` stops every effect, destroys it, and clears
		-- every `PressHapticEffect` this adapter assigned. Dropping the reference
		-- would end none of that — and there are TWO adapters here, so both go.
		local function release()
			for _, undo in { unbindHaptics, unbindCustom, detachHaptics } do
				if undo ~= nil then
					pcall(undo)
				end
			end
			unbindHaptics, unbindCustom, detachHaptics = nil, nil, nil
			for _, handle in { hap, customHap } do
				if handle ~= nil then
					pcall(handle.dispose)
				end
			end
			hap, customHap = nil, nil
			adapterModule = nil
			rootError = nil
			moduleError = nil
			installed = false
			publish()
			publishPhases()
		end

		local function install()
			-- IDEMPOTENT BY CONSTRUCTION: every path in releases first, so a third
			-- toggle cannot leave a second adapter behind. A second adapter is
			-- invisible until something fires twice, and by then the cause is several
			-- interactions in the past.
			release()
			installed = true
			local given: any = scriptedEngine or {}
			local module: any = given.module
			moduleError = given.moduleError
			if module == nil and moduleError == nil then
				module, moduleError = resolveAdapterModule()
			end
			if module == nil then
				publish()
				publishPhases()
				return
			end
			adapterModule = module

			-- THE INSTALLED ADAPTER: Facet's own defaults, no profile argument at all.
			local options: any = table.clone(given.options or {})
			options.enabled = true
			options.profile = nil
			local madeOk, made = pcall(module.new, options)
			if not madeOk or made == nil then
				-- a module that exists and will not construct is still a fact about
				-- this HOST, never about the hardware
				moduleError = `haptics.new refused this host: {tostring(made)}`
				adapterModule = nil
				publish()
				publishPhases()
				return
			end
			hap = made
			-- THE BUS SEAM, wired because a game wires it: a control's DOWN edge
			-- belongs to the button's own press property, and its COMPLETED edge is
			-- the release phase and arrives here.
			local presenter = ctx.presenter
			if presenter ~= nil and type(presenter.onFeedback) == "function" then
				unbindHaptics = hap.bind(presenter)
			end
			local root: any = given.root
			rootError = given.rootError
			if root == nil and rootError == nil then
				root, rootError = resolveUiRoot()
			end
			if root ~= nil then
				detachHaptics = hap.attachButtons(root)
			end

			-- THE OVERRIDE ADAPTER: the same module, the same host, one PARTIAL
			-- profile, and neither of the two seams a control can reach. See the
			-- header for why it exists and why it cannot double-pulse.
			local customOptions: any = table.clone(given.options or {})
			customOptions.enabled = true
			customOptions.profile = CUSTOM_PROFILE
			local customOk, customMade = pcall(module.new, customOptions)
			if customOk and customMade ~= nil then
				customHap = customMade
				unbindCustom = customHap.bind(customBus)
			end

			publish()
			publishPhases()
		end

		scope:own(core:observe(playHaptics, function(on: any)
			if on == true then
				install()
			else
				release()
			end
		end))
		-- the fixture may be torn down with the switch still on
		scope:own(function()
			teardown = true
			release()
			table.clear(customSinks)
		end)
		-- ...AND THE FIRST INSTALL IS EXPLICIT. `core:observe` baselines on the
		-- signal's CURRENT value and fires only for changes, so a default of `true`
		-- would otherwise be a switch that reads on and installed nothing — the
		-- exact "it says it is on and does nothing" defect this rework exists to end.
		install()

		--[[ WHICH CONTROL A PATH IS, in the player's own words. The whole path is the
			truth, but a phone's history column is 40 characters wide, so the line
			carries the LAST segment mapped back through `COPY` — which keeps it
			localized under the pseudo-localizing pass instead of printing an id. ]]
		local LABELS: { [string]: string } = {
			PressSample = COPY.pressLabel,
			ReleaseSample = COPY.releaseLabel,
			CustomSample = COPY.customLabel,
			Choice = COPY.selectLabel,
		}
		for _, entry in DECLARED do
			LABELS[entry.id] = COPY[entry.copyKey]
		end
		local function causeOf(path: string): string
			local leaf = string.match(path, "([^/]+)$") or path
			return LABELS[leaf] or leaf
		end

		--[[ IS THIS VERB FELT AT ALL — asked of the adapter module rather than
			answered here. `none` and the four verbs the map deliberately silences are
			unfelt on BOTH edges, and a fixture that re-implemented that rule would be
			demonstrating its own copy of it. With no module reachable the question is
			moot: nothing is installed, so nothing is requested either way. ]]
		local function activationIsFelt(verb: string): boolean
			if adapterModule == nil or type(adapterModule.activationIsFelt) ~= "function" then
				return true
			end
			local ok, felt = pcall(adapterModule.activationIsFelt, verb)
			return not ok or felt == true
		end

		-- THE BUS IS THE DEMO. Subscribing here — at build, on the presenter the host
		-- handed us — is the same one line a game writes, and it is the only place
		-- this fixture learns what a control did: no control calls back into it.
		local presenter = ctx.presenter
		if presenter ~= nil and type(presenter.onFeedback) == "function" then
			scope:own(presenter.onFeedback(function(event: any)
				local path = tostring(event.path)
				-- only THIS surface's own controls. The showcase presents its chrome
				-- and its demo on one presenter, so every chip-strip press is an
				-- activation this subscriber would otherwise write a line for.
				if string.find(path, "/SensoryFeedback", 1, true) ~= 1 then
					return
				end
				local verb = tostring(event.type)
				local cause = causeOf(path)
				if event.reason == "activation" then
					-- A COMPLETED ACTIVATION IS THE RELEASE PHASE'S, whatever verb it
					-- names — and the verb is kept in the line because the five leaves
					-- below exist to show that four of them report four different
					-- things through one identical-looking press.
					if not activationIsFelt(verb) then
						return
					end
					noteRequest("release", releaseEffect:get(), `{cause} → {verb}`, COPY.sourceBuiltIn)
				elseif verb == "select" or verb == "adjust" then
					local picked = choice:get()
					local named = COPY[CHOICE_KEY[picked] or ""] or picked
					noteRequest("select", selectEffect:get(), `{cause} → {named}`, COPY.sourceBuiltIn)
				end
				-- ...AND RE-READ THE ADAPTER. `support()` is not a boot fact: it is
				-- re-probed on every gamepad connect/disconnect, so a pad plugged in
				-- after the switch went on changes the answer while this surface would
				-- still be showing the old one. A press is the moment the reader is
				-- looking, which makes it the moment to re-read.
				publish()
				publishPhases()
			end))
		end

		-- ===== the four rows' drivers ======================================
		--[[ THE DOWN EDGE, WATCHED WHERE IT ACTUALLY HAPPENS. The press phase is the
			ENGINE's — Facet hands the button a reference and never calls Play on it —
			so nothing in game code can COUNT that pulse. What game code can see is the
			moment the engine plays it, which is the pointer going down on the control,
			and that is what the line records: a REQUEST, at the instant it is made.

			A KEY OR A PAD HAS NO SEPARATE DOWN MOMENT. The IAS `Activate` action
			resolves on the way down, so the completion arrives in the same instant the
			engine would play the press — which is why the adapter collapses the pair
			(`SAME_INSTANT_SECONDS`) and why this row writes no press line for them.
			Claiming two requests where the platform may have made one would be the
			duplicate this whole surface is built to rule out. ]]
		local function samplePointerDown(path: string): any
			heldPath:set(path)
			releaseOutcome:set(COPY.statePressed)
			noteRequest("press", pressEffect:get(), causeOf(path), COPY.sourceBuiltIn)
			return nil
		end

		local function inside(rect: any, pos: any): boolean
			if rect == nil or pos == nil then
				return false
			end
			return pos.x >= rect.x and pos.x <= rect.x + rect.w and pos.y >= rect.y and pos.y <= rect.y + rect.h
		end

		--[[ THE CANCEL, AND IT IS DECIDED AT THE RELEASE POINT rather than inferred
			from a silence. The rect is re-read through the `rectOf` the renderer hands
			every pointer handler — never a rect captured when the press began — for
			the reason this repository wrote down once already: a page that scrolls
			under a live gesture moves the control, and a stale rect answers about
			where it used to be. ]]
		local function samplePointerUp(path: string, pos: any, rectOf: (string) -> any)
			heldPath:set("")
			if inside(rectOf(path), pos) then
				-- a completed press: the activation is about to arrive on the bus, and
				-- IT is what writes the release line
				releaseOutcome:set(COPY.stateReleased)
				return
			end
			releaseOutcome:set(COPY.stateCancelled)
			noteNothing(`{causeOf(path)}, {COPY.causeCancelled}`, COPY.whyCancelled)
		end

		local function samplePointerCancel(path: string): any
			heldPath:set("")
			releaseOutcome:set(COPY.stateCancelled)
			noteNothing(`{causeOf(path)}, {COPY.causeCancelled}`, COPY.whyCancelled)
			return nil
		end

		--[[ A CHOICE MOVES WHEN THE VALUE CHANGES, and this is the only place that
			decides it. Writing the value that is already there would be a no-op the
			player cannot see, so the no-op is written down instead: the absence
			becomes evidence rather than an unexplained silence. ]]
		local function choose(id: string)
			if choice:get() == id then
				local named = COPY[CHOICE_KEY[id] or ""] or id
				noteNothing(`{COPY.selectLabel} → {named} {COPY.causeAgain}`, COPY.whyUnchanged)
				return
			end
			choice:set(id)
		end

		--[[ THE CUSTOM ROW'S ONE CAUSE. It goes to the override adapter's private bus
			and nowhere else — the control itself declares `activation = "none"`, so
			the presenter emits nothing for it and the INSTALLED adapter never hears
			the press at all. One gesture, one request, and no arithmetic needed to
			believe it. ]]
		local function playCustom()
			local effect = customEffect:get()
			if customHap == nil or effect == NO_EFFECT then
				noteNothing(COPY.customLabel, COPY.whyOff)
				return
			end
			for _, sink in table.clone(customSinks) do
				pcall(sink, {
					type = "activate",
					path = "/SensoryFeedback/Page/CustomRow/CustomSample",
					reason = "activation",
				})
			end
			noteRequest("release", effect, COPY.customLabel, COPY.sourceOverride)
		end

		-- ===== the tree ====================================================
		local function caption(id: string, text: any, secondary: boolean?): any
			return UI.Text({
				id = id,
				text = text,
				textSize = "caption",
				role = if secondary == true then "secondary" else nil,
			})
		end

		local function sampleButton(id: string, label: string): any
			return UI.Button({
				id = id,
				label = label,
				surface = "chip",
				onPointerDown = function(path: string): any
					return samplePointerDown(path)
				end,
				onPointerUp = samplePointerUp,
				onPointerCancel = function(path: string): any
					return samplePointerCancel(path)
				end,
			})
		end

		local pressLine = scope:own(core:memo(function(use)
			return `{COPY.phasePrefix} press → {use(pressEffect)} · {COPY.sourceBuiltIn}`
		end))
		local releaseLine = scope:own(core:memo(function(use)
			return `{COPY.phasePrefix} release → {use(releaseEffect)} · {COPY.sourceBuiltIn}`
		end))
		local selectLine = scope:own(core:memo(function(use)
			return `{COPY.phasePrefix} select → {use(selectEffect)} · {COPY.sourceBuiltIn}`
		end))
		local customLine = scope:own(core:memo(function(use)
			return `{COPY.phasePrefix} release → {use(customEffect)} · {COPY.sourceOverride}`
		end))
		local pressState = scope:own(core:memo(function(use)
			return if use(heldPath) ~= "" then COPY.statePressed else COPY.stateIdle
		end))
		local statusLine = scope:own(core:memo(function(use)
			return `{use(hapticsHeadline)} · {use(hapticsDetail)}`
		end))
		local requestLine = scope:own(core:memo(function(use)
			return `{COPY.requestsPrefix}: {use(requests)}`
		end))
		local choiceLine = scope:own(core:memo(function(use)
			local id = use(choice)
			return `{COPY.selectLabel}: {COPY[CHOICE_KEY[id] or ""] or id}`
		end))

		local optionButtons: { any } = {}
		for _, option in CHOICES do
			local id = option.id
			table.insert(
				optionButtons,
				UI.Button({
					id = id,
					label = COPY[option.copyKey],
					surface = "chip",
					selected = scope:own(core:memo(function(use)
						return use(choice) == id
					end)),
					onActivate = function()
						choose(id)
					end,
				})
			)
		end

		--[[ BOTH FORMS OF ONE MODIFIER, ON ONE NODE, and they compose because they
			describe two different causes. The CHANGE form fires when the value moves,
			which is the tick; `activation = "none"` silences each option's OWN press,
			so the row's only sensation is the choice moving — which is what makes it a
			comparison rather than a pile. ]]
		local choiceGroup = UI.sensoryFeedback(
			UI.sensoryFeedback(
				UI.HStack({ id = "Choice", wrap = true, gap = "tight", children = optionButtons }),
				{ trigger = choice, event = "select" }
			),
			{ activation = "none" }
		)

		-- one button, declared or not. The ONLY difference between these five is the
		-- modifier — same class, same surface, same label treatment.
		local function declaredButton(entry: { id: string, copyKey: string, activation: string? }): any
			local button = UI.Button({ id = entry.id, label = COPY[entry.copyKey], surface = "chip" })
			if entry.activation == nil then
				return button
			end
			return UI.sensoryFeedback(button, { activation = entry.activation })
		end

		local leafButtons: { any } = {}
		for _, entry in DECLARED do
			table.insert(leafButtons, declaredButton(entry))
		end

		local function panel(id: string, children: { any }): any
			return UI.VStack({
				id = id,
				surface = "control",
				padding = "s",
				gap = "tight",
				width = UI.fill(),
				children = children,
			})
		end

		local screen = UI.Screen({
			id = "SensoryFeedback",
			padding = 12,
			gap = "s",
			children = {
				-- THE PAGE SCROLLS, for the reason every fixture here does: four
				-- comparison panels, a history and two kept panels do not fit the
				-- ~200px a 640x320 landscape phone has left once the showcase reserves
				-- its chip strip, and content that overflows with nothing to scroll it
				-- is this repo's named recurring defect. What must fit WITHOUT
				-- scrolling is the title, the sentence and the haptics panel — proved
				-- from solved rects, per profile, at Largest text.
				UI.ScrollView({
					id = "Page",
					axis = "y",
					gap = "s",
					width = UI.fill(),
					height = UI.fill(),
					children = {
						UI.Text({ id = "Title", text = COPY.title, textSize = "control" }),
						caption("Intro", COPY.intro, true),
						--[[ FIRST, AND ON. The toggle, the one-line status and the
							short explanation are the three things the first viewport has
							to hold; the evidence line under them may fall below the fold
							and is allowed to grow, because the engine's own error text is
							appended to it and a refusal in a pseudo-localized package is
							longer than any budget worth declaring. ]]
						panel("Haptics", {
							UI.Toggle({ id = "PlayHaptics", label = COPY.playToggle, value = playHaptics }),
							caption("PlayState", statusLine),
							caption("PlayNote", COPY.playNote, true),
							caption("PlayLibrary", COPY.playLibrary, true),
							caption("PlayEvidence", hapticsEvidence, true),
						}),
						panel("PressRow", {
							caption("PressTitle", COPY.pressTitle),
							UI.HStack({
								id = "PressControls",
								wrap = true,
								gap = "tight",
								children = { sampleButton("PressSample", COPY.pressLabel) },
							}),
							caption("PressState", pressState),
							caption("PressPhase", pressLine),
							caption("PressNote", COPY.pressNote, true),
						}),
						panel("ReleaseRow", {
							caption("ReleaseTitle", COPY.releaseTitle),
							UI.HStack({
								id = "ReleaseControls",
								wrap = true,
								gap = "tight",
								children = { sampleButton("ReleaseSample", COPY.releaseLabel) },
							}),
							caption("ReleaseState", releaseOutcome),
							caption("ReleasePhase", releaseLine),
							caption("ReleaseNote", COPY.releaseNote, true),
						}),
						panel("SelectRow", {
							caption("SelectTitle", COPY.selectTitle),
							choiceGroup,
							caption("SelectState", choiceLine),
							caption("SelectPhase", selectLine),
							caption("SelectNote", COPY.selectNote, true),
						}),
						panel("CustomRow", {
							caption("CustomTitle", COPY.customTitle),
							UI.HStack({
								id = "CustomControls",
								wrap = true,
								gap = "tight",
								children = {
									-- `none` on the control itself: the presenter emits
									-- nothing for it, so the INSTALLED adapter never hears
									-- this press and the override adapter is the only thing
									-- that answers it
									UI.sensoryFeedback(
										UI.Button({
											id = "CustomSample",
											label = COPY.customLabel,
											surface = "chip",
											onActivate = playCustom,
										}),
										{ activation = "none" }
									),
								},
							}),
							caption("CustomPhase", customLine),
							caption("CustomNote", COPY.customNote, true),
							caption("CustomLonger", COPY.customLonger, true),
						}),
						panel("History", {
							caption("HistoryTitle", COPY.historyTitle),
							caption("HistoryLog", historyText, true),
							caption("HistoryCount", requestLine),
							caption("HistoryNote", COPY.historyNote, true),
						}),
						-- ===== KEPT: the two lessons the four rows do not teach =====
						panel("Leaves", {
							caption("LeavesTitle", COPY.declaredTitle),
							-- WRAPS. Five chips at the Largest text preference,
							-- pseudo-localized, do not fit one line on a 320px phone, and a
							-- row that cannot wrap walks off the right edge of its own box.
							UI.HStack({ id = "LeafRow", wrap = true, gap = "tight", children = leafButtons }),
							caption("MuteNote", COPY.muteNote, true),
						}),
						-- ONE DECLARATION, THREE CONTROLS, and the nesting is the point:
						-- `Third` sits a level deeper than the other two, so a mechanism
						-- that only reached direct children would be visibly wrong here.
						UI.sensoryFeedback(
							panel("Cascade", {
								caption("CascadeTitle", COPY.cascadeTitle),
								UI.HStack({
									id = "CascadeRow",
									wrap = true,
									gap = "tight",
									children = {
										UI.Button({ id = "First", label = COPY.first, surface = "chip" }),
										UI.VStack({
											id = "Nested",
											gap = "tight",
											children = {
												UI.Button({ id = "Second", label = COPY.second, surface = "chip" }),
												UI.Button({ id = "Third", label = COPY.third, surface = "chip" }),
											},
										}),
									},
								}),
								caption("CascadeNote", COPY.cascadeNote, true),
							}),
							{ activation = "pickup" }
						),
						panel("Unknowable", {
							caption("UnknowableTitle", COPY.unknowableTitle),
							caption("UnknowableNote", COPY.unknowable, true),
						}),
					},
				}),
			},
		})

		return {
			screen = screen,
			present = {},
			-- published for the headless suite: the signals a test reads, rather than
			-- a re-implementation of them
			historyText = historyText,
			requests = requests,
			playHaptics = playHaptics,
			hapticsState = hapticsState,
			hapticsHeadline = hapticsHeadline,
			hapticsDetail = hapticsDetail,
			hapticsEvidence = hapticsEvidence,
			choice = choice,
			releaseOutcome = releaseOutcome,
			-- the live adapters, or nil. A test counts INSTANCES through them rather
			-- than believing this fixture's own account of them.
			hapticsAdapter = function(): any
				return hap
			end,
			overrideAdapter = function(): any
				return customHap
			end,
			-- the seam's only setter. Re-installs immediately when the switch is
			-- already on, so a test drives the SAME install path a toggle drives
			-- rather than a second one that only exists for tests.
			useScriptedEngine = function(engine: any)
				scriptedEngine = engine
				if installed then
					install()
				end
			end,

			steps = {
				-- (_session, payload): the runner's one true call shape — api.step
				-- invokes `fn(session.built, payload)`, and a step that declared a
				-- single parameter read the SESSION as its value (live find 2026-08-21)
				readHistory = function()
					return { history = historyText:get(), requests = requests:get() }
				end,
				setPlayHaptics = function(_session, on: any)
					playHaptics:set(on == true or on == "true")
					return {
						state = hapticsState:get(),
						headline = hapticsHeadline:get(),
						detail = hapticsDetail:get(),
					}
				end,
				readHaptics = function()
					publish()
					publishPhases()
					return {
						state = hapticsState:get(),
						headline = hapticsHeadline:get(),
						detail = hapticsDetail:get(),
						evidence = hapticsEvidence:get(),
						support = if hap ~= nil then hap.support() else nil,
						decorated = if hap ~= nil then hap.diagnostics().decorated else 0,
					}
				end,
				-- the four rows, driven BY NAME through the same functions the controls
				-- call — so a scripted sweep and a finger take one path
				readRows = function()
					return {
						press = pressEffect:get(),
						release = releaseEffect:get(),
						select = selectEffect:get(),
						custom = customEffect:get(),
						choice = choice:get(),
						held = heldPath:get(),
						outcome = releaseOutcome:get(),
						releasePlays = if hap ~= nil then hap.diagnostics().phases.release.plays else 0,
						selectPlays = if hap ~= nil then hap.diagnostics().phases.select.plays else 0,
						customPlays = if customHap ~= nil then customHap.diagnostics().phases.release.plays else 0,
					}
				end,
				choose = function(_session, id: any)
					choose(tostring(id))
					return { choice = choice:get(), history = historyText:get() }
				end,
				playCustom = function()
					playCustom()
					return { history = historyText:get() }
				end,
			},

			report = function()
				return {
					history = historyText:get(),
					requests = requests:get(),
					haptics = hapticsState:get(),
					hapticsDetail = hapticsDetail:get(),
				}
			end,

			dispose = function()
				scope:dispose()
			end,
		}
	end,
}
