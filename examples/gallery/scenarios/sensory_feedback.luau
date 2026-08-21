--!strict
--[[ Scenario 'sensory_feedback' — WHAT DOES PRESSING THIS FEEL LIKE?

	The per-control sensory hook shipped in parity round 3 from a direct
	director request: *"should we have sensory feedback per control so that when
	you press a button, for example, you get haptic feedback?"* Every gap closure
	ships its showcase fixture, and this is that fixture.

	WHAT A STILL SCREENSHOT CANNOT SHOW, and therefore what this surface is FOR:

	  · FIVE BUTTONS THAT LOOK IDENTICAL AND FEEL DIFFERENT. `Buy` is a `commit`,
	    `Delete` is a `reject`, `Pick` is a `select`, `Mute` is `none` — declared
	    with `UI.sensoryFeedback(bp, { activation = … })` — and `Plain` declares
	    nothing. Nothing about their PAINT differs; the whole capability is the
	    difference in what each one says happened, which is why the log below is
	    not decoration but the demo itself.
	  · THE CASCADE. The second panel declares ONE verb, on the panel, and all
	    three buttons inside it inherit — including the two nested a level deeper.
	    That is the point of the mechanism: a Chip, a Stepper, a Table row and a
	    PopupButton each build their own inner Button, so a per-control PROP would
	    reach none of them without ten pieces of plumbing. Press any of the three
	    and watch the same verb appear under three different paths.
	  · `none` IS NOT `activate`. Pressing `Mute` writes NOTHING to the log — the
	    control still activates, it simply reports no sensation. An absence is
	    invisible until something says it was deliberate, so the log's counter
	    keeps climbing for every OTHER press while Mute's line never appears.

	  · WHETHER THIS DEVICE CAN FEEL ANY OF IT — three answers, never two. The
	    switch at the bottom installs the real adapter, and the line under it says
	    REQUESTED, or THIS PLATFORM SAYS NO, or COULD NOT DETERMINE. See below.

	WHAT Facet ITSELF STILL DOES NOT DO: play anything.
	`src/present/feedback.luau:4-5` — Facet says what happened and plays nothing.
	Playback is one opt-in, DEFAULT-OFF client adapter (`src/client/haptics.luau`)
	that the GAME constructs. The sensation column below is that adapter's
	published map, shown so a reader can see what each verb would be felt as; the
	headless suite pins the column against `haptics.MAP` so it cannot drift into
	fiction.

	AND SINCE 2026-08-16 THE SURFACE CAN INSTALL THAT ADAPTER ITSELF (NM-G3), from
	a physical pass in which the director reported "none of the haptics in sensory
	feedback work". They were right, and the cause was not the engine choice — the
	adapter has always used `HapticEffect` rather than the superseded
	`HapticService:SetMotor`. THIS FIXTURE SIMPLY NEVER CONSTRUCTED IT. It printed
	the map and captioned it "what an opt-in adapter WOULD play", which is a
	sentence a reader can reasonably mistake for a demonstration.

	THE SWITCH IS THE DEMO'S DECISION, NOT THE LIBRARY'S, and the screen says so:
	default-off is the framework's correct posture and does not move. `PlayHaptics`
	constructs `haptics.new({ enabled = true })` and hands it the two seams a game
	hands it — `bind(presenter)` and `attachButtons(root)`. BOTH MATTER NOW: since
	the phase model (task 11) a control activation has TWO felt moments with two
	owners — the DOWN edge, which belongs to the ENGINE through
	`GuiButton.PressHapticEffect` and arrives through `attachButtons`, and the
	COMPLETED edge, which arrives on the bus through `bind`. Before that, every
	event this surface produced carried `reason = "activation"` and the adapter
	dropped all of them, so a `bind` alone felt like nothing at all — which is
	exactly what "wire up the haptics" would have produced.

	AND THE CALIBRATION PANEL IS WHERE THE THREE PHASES ARE JUDGED ONE AT A TIME.
	Press / release / select fire at three different moments, and two of them can
	be driven in isolation from a control that reports nothing of its own; the
	third cannot be driven at all, because it is the engine's. The panel says which
	is which, counts the pulses this adapter played, and stays honest about the one
	it cannot count.

	AND IT REPORTS A TRI-STATE, which is the part that matters most
	(docs/lessons/capability-probes-must-be-tri-state.md). "Nothing happened" must
	never be indistinguishable from "this device cannot":

	  REQUESTED           a pad is connected, it reports vibration support, and N
	                      buttons are holding a press effect. NOT "played" — whether
	                      a motor fired is unreadable from game code, so a human
	                      has to close that gap.
	  PLATFORM SAYS NO    a connected pad answers `false`, or this client cannot
	                      construct `HapticEffect` at all. The engine's own words
	                      are kept in the line.
	  COULD NOT DETERMINE everything else, and it is NOT a failure: a phone has no
	                      probe on the platform at all, and an absent gamepad
	                      answers the same `false` as a motorless one. The line
	                      still says whether the effects went out.

	`support()` is printed verbatim beside the headline — all five lattice values,
	so a reviewer can argue with the conclusion rather than only with the word.

	THE LOG IS BOUNDED TO `LOG_LINES` for the reason `lifecycle_hidden` bounds
	its own: an unbounded event log is a Text that grows on every press, which is
	the fixed-px-height defect wearing a different hat.

	NOTHING HERE IS FIXED AGAINST AN UNFIXED VIEWPORT: no panel declares a height,
	the button rows WRAP rather than running off the edge, and the page scrolls.

	TWO HOSTS MOUNT THIS FILE and only one of them runs steps (the pair
	`lifecycle_hidden.luau` documents): the scenario runner drives `steps` by name,
	and the showcase demo picker mounts it with a minimal ctx and no step ever
	runs. Every button here is an ordinary control pressed by an ordinary press.
]]

-- how many press lines the log keeps. See the header.
local LOG_LINES = 5

--[[ EVERY PLAYER-VISIBLE STRING, in one table, EXPORTED as `copy` — the contract
	`flow_wrap.luau` and `lifecycle_hidden.luau` carry, so the localization case in
	tests/examples_gallery.spec.luau can re-run the whole fixture through a ~1.4x
	pseudo-localizing expansion. Flat keys only: the pseudo-localizer walks values
	and would throw on a nested table. ]]
local COPY = {
	title = "Sensory feedback, per control",
	intro = "Five identical-looking buttons. Press them and watch what each one says happened.",
	declaredTitle = "Declared one by one",
	buy = "Buy",
	delete = "Delete",
	pick = "Pick",
	mute = "Mute",
	plain = "Plain",
	cascadeTitle = "Declared once, on the panel",
	cascadeNote = "One declaration on this panel. All three buttons inherit it — including the nested pair.",
	first = "First",
	second = "Second",
	third = "Third",
	logTitle = "What reached the feedback bus",
	logEmpty = "Nothing yet — press a button.",
	pressesPrefix = "Presses that reported something",
	muteNote = "Mute declares `none`: it activates, and reports nothing. Its line never appears.",
	sensationTitle = "What an opt-in haptics adapter would play",
	playsNothing = "Facet itself plays nothing. Playback is one opt-in, default-OFF client adapter — the switch below installs it.",
	silent = "(silent, on purpose)",
	-- THE OPT-IN AND ITS REPORT (NM-G3). Every branch below is a whole sentence
	-- rather than a fragment assembled at the call site, because the pseudo-
	-- localizing pass in tests/examples_gallery.spec.luau walks these values and a
	-- sentence stitched from three of them expands in three places at once.
	playTitle = "Feel it on this device",
	playToggle = "Play haptics on this device",
	playNote = "Facet stays default-OFF, and this switch does not change that: it is the DEMO opting in, which is a different decision from the library opting in. It constructs the client adapter and hands it the same two seams a game does.",
	stateOffHeadline = "Off",
	stateOff = "Nothing is installed, and nothing is claimed about this device.",
	stateRequestedHeadline = "Requested",
	stateRefusedHeadline = "This platform says no",
	stateUnknownHeadline = "Could not determine",
	requestedDetail = "the press effects are with the engine, and a connected pad reports vibration support. Whether a motor actually fired is not readable from game code, so a human has to feel it and say.",
	refusedNoMotor = "a gamepad IS connected and reports no vibration motor. Nothing will be felt here, and that is an answer rather than a fault.",
	refusedAbsent = "this client cannot construct a HapticEffect at all, so no route to a motor exists.",
	unknownBlocked = "the engine refused for some reason that is not a missing motor, and this surface will not guess which.",
	unknownNoProbe = "the effects went out and the engine is holding them, but nothing on this platform can be asked whether they will be felt: touch has no probe at all, and a gamepad that is not connected answers exactly as a motorless one does. Press a button and judge with your hand.",
	unknownNoRoot = "no interface root could be reached, so no button was handed a press effect and nothing was requested.",
	unknownNothingDecorated = "a root was reached but no button under it took a press effect, so nothing was requested.",
	unknownNoModule = "the haptics adapter could not be loaded on this host, so nothing was requested.",
	supportPrefix = "support()",
	decoratedSuffix = "buttons holding a press effect",
	-- ===== the calibration panel (task 11) =================================
	-- One row per PHASE, because the three fire at three different moments and a
	-- device session has to be able to judge them one at a time. Every note is a
	-- whole sentence for the pseudo-localization reason the header gives.
	calibrationTitle = "Calibrate the three phases",
	calibrationNote = "Turn the switch above on, then press each row and judge with your hand. Nothing here plays anything while it is off.",
	calPress = "Press",
	calPressNote = "The engine plays this one on the way DOWN, from the reference Facet handed the button — no game code fires it. The same press answers with the release waveform on the way UP, so hold it, drag off the button and let go to feel the down edge alone. That drag is also the cancellation proof: no completed activation, no sound.",
	calRelease = "Release",
	calReleaseNote = "A control that reports nothing of its own, driving one completed activation onto the bus: the release waveform, alone.",
	calSelect = "Select",
	calSelectNote = "One changed choice onto the bus: the select waveform, alone. Tap it fast — pulses closer together than the floor are DROPPED, never queued behind each other.",
	-- THE HONEST LABEL (review F6). The Release and Select rows put a cause on the
	-- bus DIRECTLY so each waveform can be judged with nothing else in the way;
	-- that isolation is bought by skipping the real cause. The Press row is a plain
	-- control taking the real path end to end, so it is the row that proves the
	-- wiring rather than the waveform — and the count beside it is read off the
	-- BUS, not off the button's handler, or it would only prove the button works.
	calSynthNote = "Release and Select put their cause on the bus directly, so each waveform can be judged with nothing else in the way. Press is the row that proves the wiring: it is an ordinary control, and the count below is what actually reached the bus.",
	heardPrefix = "Completed presses heard on the bus",
	profileTitle = "Which profile is installed",
	profileDefaults = "Facet defaults",
	profileFallback = "Preset fallback",
	profileSilent = "Silent",
	profileNote = "The same three phases, three ways: Facet's own waveforms, the platform presets a client that cannot build a custom waveform falls back to, or nothing at all. Switching re-installs the adapter.",
	profileCurrentPrefix = "Installed",
	pulsePrefix = "Pulses this adapter played",
	pulsePressNote = "press: the engine's, and no game code can read whether it fired",
	phasesTitle = "The three phases and their waveforms",
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

-- the verbs this surface can produce, and what a button declaring each one hands
-- the ENGINE for its press. WRITTEN OUT rather than derived, because a gallery
-- fixture may not require a client module — and pinned against
-- `haptics.pressSpecFor` by the headless suite, which is what keeps a written-out
-- table honest. `activate` (and an undeclared control) is the PRESS PHASE, which
-- is Facet's own `contact` waveform rather than a platform preset.
--
-- `select` HAS NO DOWN EDGE, and the `note` says why rather than letting an empty
-- cell read as an oversight: a choice moves when the VALUE changes, so the tick
-- belongs to the change and the press itself is answered by `settle` like any
-- other completed press.
local SENSATION: { { verb: string, effect: string?, note: string? } } = {
	{ verb = "commit", effect = "UIClick" },
	{ verb = "reject", effect = "UINotification" },
	{ verb = "select", effect = nil, note = "no down edge — the tick fires when the value changes" },
	{ verb = "activate", effect = "contact" },
}

-- THE THREE PHASES AND THEIR SHIPPED WAVEFORMS (`src/client/sensory_profile.luau`).
-- Written out for the same reason and pinned the same way. `owner` is the half a
-- reader cannot infer from the name: WHO decides the moment it fires.
local PHASES: { { phase: string, effect: string, owner: string } } = {
	{ phase = "press", effect = "contact", owner = "the engine, on the way down" },
	{ phase = "release", effect = "settle", owner = "the bus, when the press completes" },
	{ phase = "select", effect = "tick", owner = "the bus, when a choice changes" },
}

-- ===== the opt-in's plumbing (NM-G3) =======================================
-- THE THREE ANSWERS, as three values rather than one boolean. The lesson this
-- shape comes from — docs/lessons/capability-probes-must-be-tri-state.md — was
-- written after a boolean probe published two false platform facts, and this
-- repository has since shipped a second collapsed instrument. So `refused` and
-- `undetermined` are separate states carrying separate sentences, and they are
-- named here so a caller cannot spell one of them differently.
local STATE_OFF = "off"
local STATE_REQUESTED = "requested"
local STATE_REFUSED = "refused"
local STATE_UNDETERMINED = "undetermined"

-- the three profiles the calibration panel can install, named so a caller cannot
-- spell one of them differently
local PROFILE_DEFAULTS = "defaults"
local PROFILE_FALLBACK = "fallback"
local PROFILE_SILENT = "silent"

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
	demo the picker cannot mount at all, and this one has plenty to show with the
	switch off. ]]
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
	ScreenGui the host presented it into. `PlayerGui` is the container that holds
	it either way, and the same reach a sibling fixture already makes
	(`theme_authoring.luau` walks it for the installed StyleSheet).

	THE BREADTH IS DISCLOSED RATHER THAN NARROWED: while the switch is on, every
	button on this client carries its declared press effect, chrome included. That
	is what a device pass wants — press anything, feel whether this hardware does
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

--[[ classify(facts) -> { state, headline, detail } — PURE, and the whole testable
	part of this feature. A headless target cannot fire a motor and cannot read
	whether one fired, so what is provable is the DECISION and the REPORTED STATE.

	THE ORDER OF THE BRANCHES IS THE ARGUMENT. A construction verdict outranks a
	device one (the adapter's own rule: if the class cannot be built, what the pads
	say is irrelevant), `blocked` is could-not-tell rather than no, and the two
	"we never even asked" cases are separated from both so that a missing root
	never reads as a hardware refusal. Every branch ends with `support()` printed
	verbatim and the decorated count beside it, so the conclusion can be argued
	with rather than only believed. ]]
local function classify(facts: Facts): { state: string, headline: string, detail: string }
	local support = facts.support
	local decorated = facts.decorated or 0
	local function record(state: string, headline: string, sentence: string, raw: string?): any
		local parts = {
			sentence,
			`{COPY.supportPrefix} = {tostring(support or "—")}`,
			`{decorated} {COPY.decoratedSuffix}`,
		}
		if raw ~= nil and raw ~= "" then
			table.insert(parts, raw)
		end
		return { state = state, headline = headline, detail = table.concat(parts, " · ") }
	end
	if not facts.adapterLoaded then
		return record(STATE_UNDETERMINED, COPY.stateUnknownHeadline, COPY.unknownNoModule, facts.moduleError)
	end
	if support == "absent" then
		return record(STATE_REFUSED, COPY.stateRefusedHeadline, COPY.refusedAbsent, facts.lastError)
	end
	if support == "unsupported" then
		return record(STATE_REFUSED, COPY.stateRefusedHeadline, COPY.refusedNoMotor, nil)
	end
	if support == "blocked" then
		return record(STATE_UNDETERMINED, COPY.stateUnknownHeadline, COPY.unknownBlocked, facts.lastError)
	end
	if facts.rootError ~= nil then
		return record(STATE_UNDETERMINED, COPY.stateUnknownHeadline, COPY.unknownNoRoot, facts.rootError)
	end
	if decorated == 0 then
		return record(STATE_UNDETERMINED, COPY.stateUnknownHeadline, COPY.unknownNothingDecorated, facts.lastError)
	end
	if support == "supported" then
		return record(STATE_REQUESTED, COPY.stateRequestedHeadline, COPY.requestedDetail, nil)
	end
	return record(STATE_UNDETERMINED, COPY.stateUnknownHeadline, COPY.unknownNoProbe, nil)
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
	logLines = LOG_LINES,
	declared = DECLARED,
	sensation = SENSATION,
	phases = PHASES,
	profiles = table.freeze({
		defaults = PROFILE_DEFAULTS,
		fallback = PROFILE_FALLBACK,
		silent = PROFILE_SILENT,
	}),
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI = Facet.UI
		local core = ctx.core
		local scope = core:scope("sensory-feedback")

		local logText = scope:own(core:signal(COPY.logEmpty))
		local reported = scope:own(core:signal(0))
		local lines: { string } = {}

		-- ===== the opt-in (NM-G3) ==========================================
		-- DEFAULT FALSE, exactly like the adapter it installs.
		local playHaptics = scope:own(core:signal(false))
		local hapticsState = scope:own(core:signal(STATE_OFF))
		local hapticsHeadline = scope:own(core:signal(COPY.stateOffHeadline))
		local hapticsDetail = scope:own(core:signal(COPY.stateOff))

		-- ===== the calibration panel (task 11) =============================
		-- WHICH PROFILE, and what the adapter has actually played. Both are signals
		-- the panel reads and the steps below publish, so a Studio session, a device
		-- session and the headless suite all read the same numbers.
		local profileChoice = scope:own(core:signal(PROFILE_DEFAULTS))
		local pulseLine = scope:own(core:signal(`{COPY.pulsePrefix}: 0`))

		-- the live adapter, and the two releases it handed back
		local hap: any = nil
		local unbindHaptics: (() -> ())? = nil
		local detachHaptics: (() -> ())? = nil
		local rootError: string? = nil
		local moduleError: string? = nil
		local installed = false
		local teardown = false
		--[[ THE ONE SEAM, and its DEFAULT is what both shipped hosts run. A test
			hands in a scripted engine (a module, a root, and the adapter's own four
			injection options) so all three states can be driven with no hardware;
			with nothing handed in, `install` takes the real routes — which is what
			makes "with NOTHING injected it still installs" a test of the shipped
			path rather than of the rig. Named `scriptedEngine` and not `deps`
			because that is all it may ever be: it never changes the DECISION, only
			where the facts come from. ]]
		local scriptedEngine: any = nil

		--[[ WHAT THE ADAPTER HAS PLAYED, per phase, read off its own diagnostics.

			THE PRESS ROW IS DELIBERATELY NOT A NUMBER. Facet hands the button a
			reference and the ENGINE fires it, so nothing in game code can count that
			pulse or even know it happened — printing a 0 there would read as "the
			press never fired" when what it means is "nobody can see". The sentence is
			the honest instrument. ]]
		local function publishPulses()
			if teardown then
				return
			end
			if hap == nil then
				pulseLine:set(`{COPY.pulsePrefix}: 0 · {COPY.pulsePressNote}`)
				return
			end
			local ok, diagnostics = pcall(hap.diagnostics)
			if not ok or diagnostics == nil then
				pulseLine:set(`{COPY.pulsePrefix}: 0 · {COPY.pulsePressNote}`)
				return
			end
			local phases: any = diagnostics.phases or {}
			local release = if phases.release ~= nil then phases.release.plays else 0
			local select_ = if phases.select ~= nil then phases.select.plays else 0
			pulseLine:set(
				`{COPY.pulsePrefix}: {diagnostics.plays} · release {release} · select {select_} · `
					.. `{COPY.heardPrefix}: {reported:get()} · {COPY.pulsePressNote}`
			)
		end

		local function publish()
			if teardown then
				return
			end
			if not installed then
				hapticsState:set(STATE_OFF)
				hapticsHeadline:set(COPY.stateOffHeadline)
				hapticsDetail:set(COPY.stateOff)
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
		end

		-- PUTTING IT AWAY IS THE PATH THAT HAS TO BE AIRTIGHT (the adapter's own
		-- header says so): `dispose` stops every effect, destroys it, and clears
		-- every `PressHapticEffect` this adapter assigned. Dropping the reference
		-- would end none of that.
		local function release()
			if unbindHaptics ~= nil then
				pcall(unbindHaptics)
				unbindHaptics = nil
			end
			if detachHaptics ~= nil then
				pcall(detachHaptics)
				detachHaptics = nil
			end
			if hap ~= nil then
				pcall(hap.dispose)
				hap = nil
			end
			rootError = nil
			moduleError = nil
			installed = false
			publish()
			publishPulses()
		end

		--[[ THE THREE PROFILES, built from the adapter module's OWN
			`sensory_profile` rather than from a copy of its numbers here. The fallback
			arm names the presets `sensory_profile.FALLBACK` names — so if that
			limitation ever changes, this panel changes with it instead of quietly
			demonstrating the old one. ]]
		local function profileOption(adapterModule: any): any?
			local choice = profileChoice:get()
			if choice == PROFILE_DEFAULTS then
				return nil
			end
			local sp = adapterModule ~= nil and adapterModule.sensoryProfile or nil
			if sp == nil then
				return nil
			end
			if choice == PROFILE_SILENT then
				return {
					press = { kind = "silent" },
					release = { kind = "silent" },
					select = { kind = "silent" },
				}
			end
			return {
				press = { kind = "preset", effect = sp.FALLBACK.press },
				release = { kind = "preset", effect = sp.FALLBACK.release },
				select = { kind = "preset", effect = sp.FALLBACK.select },
			}
		end

		local function install()
			release()
			installed = true
			local given: any = scriptedEngine or {}
			local adapterModule: any = given.module
			moduleError = given.moduleError
			if adapterModule == nil and moduleError == nil then
				adapterModule, moduleError = resolveAdapterModule()
			end
			if adapterModule == nil then
				publish()
				return
			end
			local options: any = table.clone(given.options or {})
			options.enabled = true
			if options.profile == nil then
				options.profile = profileOption(adapterModule)
			end
			local madeOk, made = pcall(adapterModule.new, options)
			if not madeOk or made == nil then
				-- a module that exists and will not construct is still a fact about
				-- this HOST, never about the hardware
				moduleError = `haptics.new refused this host: {tostring(made)}`
				publish()
				return
			end
			hap = made
			-- THE BUS SEAM, wired because a game wires it. Since task 11 it is no
			-- longer inert for this surface: an activation's DOWN edge still belongs
			-- to the button's own press property, but its COMPLETED edge is the
			-- release phase and arrives here.
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
			publish()
			publishPulses()
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
		end)

		-- THE BUS IS THE DEMO. Subscribing here — at build, on the presenter the
		-- host handed us — is the same one line a game writes, and it is the only
		-- place this fixture learns anything: no control calls back into it.
		local presenter = ctx.presenter
		if presenter ~= nil and type(presenter.onFeedback) == "function" then
			scope:own(presenter.onFeedback(function(event: any)
				-- only this surface's own presses. `reason` is what the presenter
				-- stamps on a control activation, so a toast retiring somewhere else
				-- in the showcase cannot write a line here.
				if event.reason ~= "activation" then
					return
				end
				local path = tostring(event.path)
				if string.find(path, "/SensoryFeedback", 1, true) ~= 1 then
					return
				end
				-- the LAST path segment: the whole path is the truth but a phone's
				-- log column is 40 characters wide
				local leaf = string.match(path, "([^/]+)$") or path
				table.insert(lines, `{event.type}  ←  {leaf}`)
				while #lines > LOG_LINES do
					table.remove(lines, 1)
				end
				logText:set(table.concat(lines, "\n"))
				reported:set(reported:get() + 1)
				-- ...AND RE-READ THE ADAPTER. `support()` is not a boot fact: it is
				-- re-probed on every gamepad connect/disconnect, so a pad plugged in
				-- after the switch went on changes the answer while this surface
				-- would still be showing the old one. A press is the moment the
				-- reader is looking, which makes it the moment to re-read; it costs
				-- one early return while nothing is installed.
				publish()
				publishPulses()
			end))
		end

		local counts = scope:own(core:memo(function(use)
			return `{COPY.pressesPrefix}: {use(reported)}`
		end))

		--[[ ===== the calibration panel's three drivers ======================
			The RELEASE and SELECT phases are the BUS's, so a control that reports
			nothing of its own can put exactly one of their causes onto the bus and
			nothing else — which is how each is judged alone. The PRESS phase has no
			driver here and cannot have one: Facet hands the engine a reference and the
			engine decides the moment. Pressing the row IS the driver. ]]
		local function emit(event: any)
			local presenter = ctx.presenter
			if presenter == nil or type(presenter.emitFeedback) ~= "function" then
				return
			end
			pcall(presenter.emitFeedback, event)
			publishPulses()
		end

		local function fireRelease()
			emit({ type = "activate", path = "/SensoryFeedback/Page/Calibration/CalRelease", reason = "activation" })
		end

		local function fireSelect()
			emit({ type = "select", path = "/SensoryFeedback/Page/Calibration/CalSelect" })
		end

		local function chooseProfile(choice: string)
			if profileChoice:get() == choice then
				return
			end
			profileChoice:set(choice)
			-- take effect NOW rather than at the next toggle: a selector that needs a
			-- second gesture to mean anything is a selector a device pass mistrusts
			if installed then
				install()
			end
			publishPulses()
		end

		local profileLine = scope:own(core:memo(function(use)
			local choice = use(profileChoice)
			local label = COPY.profileDefaults
			if choice == PROFILE_FALLBACK then
				label = COPY.profileFallback
			elseif choice == PROFILE_SILENT then
				label = COPY.profileSilent
			end
			return `{COPY.profileCurrentPrefix}: {label}`
		end))

		local function profileButton(id: string, copyKey: string, choice: string): any
			return UI.Button({
				id = id,
				label = COPY[copyKey],
				surface = "chip",
				onActivate = function()
					chooseProfile(choice)
				end,
			})
		end

		local phaseRows: { any } = {}
		for i, row in PHASES do
			table.insert(
				phaseRows,
				UI.Text({
					id = `Phase{i}`,
					text = `{row.phase} → {row.effect} — {row.owner}`,
					textSize = 12,
					role = "secondary",
				})
			)
		end

		-- one button, declared or not. The ONLY difference between these five is
		-- the modifier — same class, same surface, same label treatment.
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

		local sensationRows: { any } = {}
		for i, row in SENSATION do
			table.insert(
				sensationRows,
				UI.Text({
					id = `Sensation{i}`,
					text = `{row.verb} → {row.effect or row.note or COPY.silent}`,
					textSize = 12,
					role = "secondary",
				})
			)
		end

		local screen = UI.Screen({
			id = "SensoryFeedback",
			padding = 12,
			gap = 8,
			children = {
				-- THE PAGE SCROLLS, for the reason every fixture here does: two
				-- panels, a log and a table do not fit the ~200px a 640x320 landscape
				-- phone has left once the showcase reserves its chip strip, and content
				-- that overflows with nothing to scroll it is this repo's named
				-- recurring defect.
				UI.ScrollView({
					id = "Page",
					axis = "y",
					gap = 8,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.Text({ id = "Title", text = COPY.title, textSize = 18 }),
						UI.Text({ id = "Intro", text = COPY.intro, textSize = 12, role = "secondary" }),
						UI.VStack({
							id = "Leaves",
							surface = "control",
							padding = 8,
							gap = 6,
							width = { type = "fill", weight = 1 },
							children = {
								UI.Text({ id = "LeavesTitle", text = COPY.declaredTitle, textSize = 12 }),
								-- WRAPS. Five chips at the Largest text preference, pseudo-
								-- localized, do not fit one line on a 320px phone, and a row
								-- that cannot wrap walks off the right edge of its own box.
								UI.HStack({ id = "LeafRow", wrap = true, gap = 6, children = leafButtons }),
								UI.Text({ id = "MuteNote", text = COPY.muteNote, textSize = 12, role = "secondary" }),
							},
						}),
						-- ONE DECLARATION, THREE CONTROLS, and the nesting is the point:
						-- `Third` sits a level deeper than the other two, so a mechanism
						-- that only reached direct children would be visibly wrong here.
						UI.sensoryFeedback(
							UI.VStack({
								id = "Cascade",
								surface = "control",
								padding = 8,
								gap = 6,
								width = { type = "fill", weight = 1 },
								children = {
									UI.Text({ id = "CascadeTitle", text = COPY.cascadeTitle, textSize = 12 }),
									UI.HStack({
										id = "CascadeRow",
										wrap = true,
										gap = 6,
										children = {
											UI.Button({ id = "First", label = COPY.first, surface = "chip" }),
											UI.VStack({
												id = "Nested",
												gap = 6,
												children = {
													UI.Button({ id = "Second", label = COPY.second, surface = "chip" }),
													UI.Button({ id = "Third", label = COPY.third, surface = "chip" }),
												},
											}),
										},
									}),
									UI.Text({
										id = "CascadeNote",
										text = COPY.cascadeNote,
										textSize = 12,
										role = "secondary",
									}),
								},
							}),
							{ activation = "pickup" }
						),
						UI.Text({ id = "LogTitle", text = COPY.logTitle, textSize = 12 }),
						UI.Text({ id = "Log", text = logText, textSize = 12, role = "secondary" }),
						UI.Text({ id = "Counts", text = counts, textSize = 12, role = "secondary" }),
						UI.VStack({
							id = "Sensations",
							surface = "control",
							padding = 8,
							gap = 6,
							width = { type = "fill", weight = 1 },
							children = (function(): { any }
								local kids: { any } = {
									UI.Text({ id = "SensationTitle", text = COPY.sensationTitle, textSize = 12 }),
								}
								for _, row in sensationRows do
									table.insert(kids, row)
								end
								table.insert(
									kids,
									UI.Text({
										id = "PlaysNothing",
										text = COPY.playsNothing,
										textSize = 12,
										role = "secondary",
									})
								)
								return kids
							end)(),
						}),
						--[[ THE SWITCH, AND THE ANSWER (NM-G3). Last on the page because
							it is the last step of the story: five verbs, then one cascade,
							then what an adapter maps them to — and only then, whether they
							reach this particular hardware.

							NOTHING HERE IS FIXED AGAINST AN UNFIXED VIEWPORT, for the reason
							the header gives: the detail line is a whole sentence that GROWS
							when the engine's own error text is appended to it, so it wraps
							and the page scrolls rather than declaring a height a pseudo-
							localized refusal would overflow. ]]
						UI.VStack({
							id = "Play",
							surface = "control",
							padding = 8,
							gap = 6,
							width = { type = "fill", weight = 1 },
							children = {
								UI.Text({ id = "PlayTitle", text = COPY.playTitle, textSize = 12 }),
								UI.Toggle({ id = "PlayHaptics", label = COPY.playToggle, value = playHaptics }),
								UI.Text({ id = "PlayNote", text = COPY.playNote, textSize = 12, role = "secondary" }),
								UI.Text({ id = "PlayState", text = hapticsHeadline, textSize = 12 }),
								UI.Text({ id = "PlayDetail", text = hapticsDetail, textSize = 12, role = "secondary" }),
								UI.Text({ id = "UnknowableTitle", text = COPY.unknowableTitle, textSize = 12 }),
								UI.Text({
									id = "Unknowable",
									text = COPY.unknowable,
									textSize = 12,
									role = "secondary",
								}),
							},
						}),
						--[[ THE CALIBRATION PANEL (task 11). Three phases, judged one at
							a time, plus the profile they are judged under and a count of
							what actually went out.

							THE ROWS WRAP AND THE NOTES ARE WHOLE SENTENCES, for the two
							reasons the header gives: three chips at the Largest text
							preference do not fit one line on a 320px phone, and a note
							stitched from fragments expands in three places at once under
							the pseudo-localizing pass. ]]
						UI.VStack({
							id = "Calibration",
							surface = "control",
							padding = 8,
							gap = 6,
							width = { type = "fill", weight = 1 },
							children = {
								UI.Text({ id = "CalTitle", text = COPY.calibrationTitle, textSize = 12 }),
								UI.Text({
									id = "CalNote",
									text = COPY.calibrationNote,
									textSize = 12,
									role = "secondary",
								}),
								UI.Text({ id = "PhasesTitle", text = COPY.phasesTitle, textSize = 12 }),
								UI.VStack({ id = "PhaseRows", gap = 2, children = phaseRows }),
								-- PRESS has no handler and cannot have one: pressing it IS
								-- the phase, because the engine owns the moment.
								UI.HStack({
									id = "CalRow",
									wrap = true,
									gap = 6,
									children = {
										UI.Button({ id = "CalPress", label = COPY.calPress, surface = "chip" }),
										-- the two bus phases are driven from controls that
										-- report NOTHING of their own, so each row puts exactly
										-- one cause on the bus and nothing else
										UI.sensoryFeedback(
											UI.Button({
												id = "CalRelease",
												label = COPY.calRelease,
												surface = "chip",
												onActivate = fireRelease,
											}),
											{ activation = "none" }
										),
										UI.sensoryFeedback(
											UI.Button({
												id = "CalSelect",
												label = COPY.calSelect,
												surface = "chip",
												onActivate = fireSelect,
											}),
											{ activation = "none" }
										),
									},
								}),
								UI.Text({
									id = "CalPressNote",
									text = COPY.calPressNote,
									textSize = 12,
									role = "secondary",
								}),
								UI.Text({
									id = "CalReleaseNote",
									text = COPY.calReleaseNote,
									textSize = 12,
									role = "secondary",
								}),
								UI.Text({
									id = "CalSelectNote",
									text = COPY.calSelectNote,
									textSize = 12,
									role = "secondary",
								}),
								UI.Text({
									id = "CalSynthNote",
									text = COPY.calSynthNote,
									textSize = 12,
									role = "secondary",
								}),
								UI.Text({ id = "ProfileTitle", text = COPY.profileTitle, textSize = 12 }),
								UI.HStack({
									id = "ProfileRow",
									wrap = true,
									gap = 6,
									children = {
										profileButton("ProfileDefaults", "profileDefaults", PROFILE_DEFAULTS),
										profileButton("ProfileFallback", "profileFallback", PROFILE_FALLBACK),
										profileButton("ProfileSilent", "profileSilent", PROFILE_SILENT),
									},
								}),
								UI.Text({ id = "ProfileCurrent", text = profileLine, textSize = 12 }),
								UI.Text({
									id = "ProfileNote",
									text = COPY.profileNote,
									textSize = 12,
									role = "secondary",
								}),
								UI.Text({ id = "PulseCount", text = pulseLine, textSize = 12 }),
							},
						}),
					},
				}),
			},
		})

		return {
			screen = screen,
			present = {},
			-- published for the headless suite: the signals a test reads, rather
			-- than a re-implementation of them
			logText = logText,
			reported = reported,
			playHaptics = playHaptics,
			hapticsState = hapticsState,
			hapticsHeadline = hapticsHeadline,
			hapticsDetail = hapticsDetail,
			profileChoice = profileChoice,
			pulseLine = pulseLine,
			-- the live adapter, or nil. A test counts INSTANCES through it rather
			-- than believing this fixture's own account of them.
			hapticsAdapter = function(): any
				return hap
			end,
			-- the seam's only setter. Takes effect at the NEXT install, so the
			-- switch stays the one and only path in.
			useScriptedEngine = function(engine: any)
				scriptedEngine = engine
			end,

			steps = {
				-- the log, as the runner reads it after driving real presses through
				-- the adapter's activate path
				readLog = function()
					return { log = logText:get(), reported = reported:get() }
				end,
				-- the opt-in, driven by name. `on` flips the same signal the Toggle
				-- writes, so a scripted device sweep and a finger take one path.
				setPlayHaptics = function(on: boolean)
					playHaptics:set(on == true)
					return {
						state = hapticsState:get(),
						headline = hapticsHeadline:get(),
						detail = hapticsDetail:get(),
					}
				end,
				readHaptics = function()
					publish()
					return {
						state = hapticsState:get(),
						headline = hapticsHeadline:get(),
						detail = hapticsDetail:get(),
						support = if hap ~= nil then hap.support() else nil,
						decorated = if hap ~= nil then hap.diagnostics().decorated else 0,
					}
				end,
				-- the calibration panel, driven BY NAME through the same functions the
				-- three chips call — so a scripted sweep and a finger take one path
				setProfile = function(choice: string)
					chooseProfile(choice)
					return { profile = profileChoice:get(), pulses = pulseLine:get() }
				end,
				firePhase = function(phase: string)
					if phase == "release" then
						fireRelease()
					elseif phase == "select" then
						fireSelect()
					end
					-- "press" is deliberately undrivable: it is the ENGINE's moment,
					-- and a fixture that faked it would be demonstrating itself
					return { phase = phase, pulses = pulseLine:get() }
				end,
				readPulses = function()
					publishPulses()
					local phases = if hap ~= nil then hap.diagnostics().phases else nil
					return {
						line = pulseLine:get(),
						profile = profileChoice:get(),
						plays = if hap ~= nil then hap.diagnostics().plays else 0,
						release = if phases ~= nil then phases.release.plays else 0,
						select = if phases ~= nil then phases.select.plays else 0,
						-- what actually reached the bus, so a device session can tell a
						-- felt press from a wired one (review F6)
						heard = reported:get(),
						pressEffect = if phases ~= nil then phases.press.effect else nil,
						releaseEffect = if phases ~= nil then phases.release.effect else nil,
						selectEffect = if phases ~= nil then phases.select.effect else nil,
					}
				end,
			},

			report = function()
				return {
					log = logText:get(),
					reported = reported:get(),
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
