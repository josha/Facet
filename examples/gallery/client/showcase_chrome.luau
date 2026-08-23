--!strict
--[[ THE SHOWCASE CHROME — the strip, the panel, and the four inputs that reach
	them.

	WHY THIS IS ITS OWN MODULE. It used to be ~140 lines inside
	`init.client.luau`, which is a LocalScript: it reaches engine globals at load
	and therefore cannot be required headlessly, so every claim about the chrome
	could only ever be made by reading its SOURCE TEXT — which is exactly the
	shape of check `tests/gallery_theme_picker.spec.luau:194` was criticised for
	(it asserted the file *contains* `responder = "passive"`, pinning a
	constraint rather than proving a capability). Everything structural now lives
	here, where `tests/gallery_chrome.spec.luau` mounts the real thing and drives
	real keys through the real action system.

	=== 1. WHAT WAS BROKEN, MEASURED ===

	The chrome was reachable by mouse and touch and by NOTHING else, and the
	measurement found the defect is bigger than "the chips are unreachable":

	  * Both pickers present `responder = "passive"`. A passive surface's nav
	    context is created DISABLED and non-sinking (`presenter.luau:2595-2603`),
	    and Tab/Space bind only while the responder is ENGAGED (`:2839-2842`).
	    The only `engage()` call in `src/` is inside the presenter's own TAP
	    handler (`:2248`) — so a finger engages the chrome and a keyboard and a
	    pad never can.
	  * `demo_picker.next()` carries the comment "the gamepad/keyboard path: a
	    player on a couch should not have to open a list to move on" above a
	    `showNext` whose only callers are the test driver. No key and no pad
	    button was ever bound to it.
	  * AND THE DEMO UNDERNEATH WAS UNREACHABLE TOO, which nothing had reported.
	    A presented surface pushes a focus SCOPE, the graph navigates the TOP
	    scope only, and the old chrome re-presented itself after every demo mount
	    (z-order is present order) — so the chrome's scope was permanently on
	    top. Driven headlessly: Tab moved focus to `/ShowcaseChrome/…/DemoToggle`
	    while the chrome was passive, Return and ButtonA then did NOTHING
	    (`dispatchActivate` ran against the DEMO's handle with a chrome path),
	    and no key could reach a single control of the demo on screen. Keyboard
	    and gamepad were dead in both directions.

	=== 2. THE SHAPE, AND WHY IT IS TWO SURFACES ===

	Present order is z-order AND focus-scope order, and the chrome needs opposite
	answers for those two while it is closed: its strip must be visible (it never
	overlaps a demo — `coreSafeInsets.top` is reserved from the chips' own
	measured bottom edge, so the solver lays every demo out below it) while the
	DEMO must own the focus scope. One surface cannot do both. Two can:

	  * THE BAR (`ShowcaseChrome`) — the two chips. Presented ONCE, before the
	    first demo, and never re-presented. It cannot be covered because nothing
	    is ever laid out into the strip it reserves, and its scope stays buried,
	    so Tab and the d-pad belong to the demo exactly as they should.
	  * THE PANEL (`ShowcasePanel`) — presented when a target is opened and
	    dismissed when it closes. Presented last, so it draws over the demo and
	    its scope is on top; ENGAGED on every open, so Tab/Space/arrows/A/B are
	    bound and sunk while it is up; dismissed on resign, so Cancel (pad B), an
	    outside tap, or the toggle key all put the demo back — `removeScope`
	    restores focus to the surface beneath, which is the demo.

	The bar NEVER engages. A tap on a focusable inside a passive surface engages
	it (`presenter.luau:2248`), so opening resigns the bar in the same breath:
	two engaged surfaces would both sit at the engaged band's 3000 and BOTH would
	receive Tab, stepping the one focus ring twice per press.

	=== 3. TWO TARGETS FOREVER (`[SHOWCASE-CHROME]: CONCERNS 16`) ===

	The strip carries exactly two chips — *which demo*, and *settings* — and the
	third one was rejected on the strip's own arithmetic (at 320 px the two
	existing chips already spend ~284 of ~304 px). Motion and theme both live
	inside settings; see `settings_panel.luau`.

	The chips step down through a `UI.ViewThatFits` ladder to ICON-ONLY rather
	than clipping labels by character count. `p4_foyer`'s nav bar is the reference.

	IT USED TO CARRY A TRAP AND NO LONGER DOES (Facet ADR-0044 / ADR-0040 B-23,
	2026-08-22): `hug` CAPPED at the offer, so a hug candidate could never tell a
	`ViewThatFits` that it did not fit, the ladder silently pinned its first rung
	and the labels truncated anyway. The framework fixed it at the seam — the fit
	probe resolves `hug` as `content`, because a cap-at-the-offer is a squeezing
	term like `shrinkWeight` and a candidate is judged at its IDEAL size — so both
	spellings now choose the same rung at every width. `content` stays here because
	it is what these rungs mean (an uncapped natural width, deliberately), not
	because the other one is unsafe.

	=== 4. THE BINDINGS, AND WHY THESE THREE KEYS ===

	The vocabulary is closed (`constitution.md` §9: "a new verb is an ADR, not a
	new binding at a call site"), so this binds no new verb: the chrome's own
	context declares **`Activate`** — "activate the chrome" — and nothing else.
	Everything after that press is the framework's: Navigate walks the panel,
	Traverse (Tab) walks it linearly, Activate presses a row, Cancel leaves.

	  * KEYBOARD — **Backquote**. `Escape` is engine-reserved and cannot be
	    rebound, so there is no keyboard Cancel and the SAME key has to toggle;
	    `Tab` belongs to Traverse and is already contended by the CoreGui players
	    list; `Space`/`Return` belong to Activate; the arrows belong to Navigate;
	    and a letter is contended by `05_word_game`, which reads the whole
	    alphabet. Backquote is in none of those sets and is not in Roblox's
	    hard-reserved set (`Esc`/`F9`/`F11`/`F12`/`PrintScreen`) — it is the
	    conventional console/menu key on a desktop keyboard.
	  * GAMEPAD — **ButtonL1 / ButtonR1**, and NO face button at all (director
	    round 3, 2026-08-21: the chips sit at the two top corners, so the two
	    shoulders match them by POSITION — left opens the demo list, right opens
	    settings). See `SECTION_GAMEPAD` below. Every face button is spoken for:
	    `ButtonA` is Activate and is eaten unconditionally by the legacy
	    `jumpAction` (docs/lessons/gamepad-contention-truths.md truth 1); `ButtonB`
	    is Cancel; `ButtonX` is the row-actions menu; `ButtonY` is the FRAMEWORK's
	    menu verb (§5); `ButtonStart`/`ButtonSelect` are the platform's own menu
	    buttons and are exactly the trade the gamepad-contention lesson refuses to
	    make.

	The context sits at `presenter.APP_CHROME_PRIORITY` — the framework's own
	app-level global chrome band (registry item 24; W3-D, ADR-0053), strictly
	above the engaged band (3000) and above every live modal depth this
	codebase exercises — so the toggle key can still be pressed while the
	panel it opened is engaged and sinking. See "THE TIE, CLOSED" below for why
	this replaced a hand-picked literal (`3500`) that used to tie a live modal
	exactly.

	=== 5. THE AUDIT, MEASURED — AND WHAT IT COST TWICE ===

	The first version of §4 said "no other context in the place binds either key".
	It was false for the two SHOULDERS, and the paragraph written to correct that
	re-asserted it for `ButtonY` — same sentence, same absence of a measurement,
	one round apart. So this is the audit as a TABLE of what was actually read,
	rather than a claim:

	  * `Backquote` — grep of `src/`, `examples/` and `tests/`: bound nowhere else.
	    Kept.
	  * `ButtonL1` / `ButtonR1` — `presenter.luau:2292-2293` binds them to
	    **Adjust** on any surface that declares `onAdjust`, and `:2394-2395` binds
	    the same pair dynamically whenever the focused node is a declared
	    `adjustTargets` member (Slider, Stepper, a Table column grip, a TabView
	    strip, LevelPicker, Rating — four catalogue demos contain one). CONTENDED.
	  * `ButtonY` — `menu.luau:70-76` declares `TRIGGER_KEYS.gamepad = ButtonY`,
	    and `:884-899` binds it on a **sinking** context at `TRIGGER_KEY_PRIORITY`
	    1200 for every `Menu` control that has an action system. The catalogue
	    ships the `menu` demo, whose whole subject is "one list of verbs, five ways
	    in". CONTENDED — and taken by a context at the chrome's OLD literal
	    priority (3500, since replaced by `presenter.APP_CHROME_PRIORITY` —
	    see below), the chrome would have silently deleted the pad route that
	    demo exists to show.

	MEASURED, both halves. On a surface declaring `onAdjust`, ONE `ButtonR1` press
	fired BOTH — the value under the ring moved AND the panel opened over it (the
	context was non-sinking, so this was never a priority defect; it was the claim
	being false). And with the real `menu` fixture mounted, one `ButtonY` press
	opened the menu AND the chrome at 48b6e7b, then opened only the chrome once
	this context began to sink.

	RULING R19 (controller, 2026-08-21) — the bumpers belong to the chrome
	sections. The director asked for the two top-corner buttons by position and the
	console convention (section switching on the shoulders) agrees. What is NOT
	acceptable is one press resolving to two contexts, so this context SINKS:
	`deviceKey` cuts every strictly-lower candidate for the same key code once a
	sinking context has been delivered, which makes the outcome ONE action, decided
	by priority, deterministically. Sinking is per-KEY, so `Backquote` consumes
	nothing that was ever bound elsewhere.

	WHAT R19 REALLY COSTS, stated accurately (DIR4 review MINOR-3 — the first
	version of this paragraph said "the framework's Adjust keeps DPad / Comma /
	Period", and that is only true for some controls). A control that declares
	`adjustAxis` (Slider, LevelPicker) keeps the D-pad pair, which moves to
	`AdjustAxis`. A **legacy**-state adjust target on a screen with horizontal
	navigation does not: `presenter.luau:2398-2402` returns after binding only
	Comma / Period / ButtonL1 / ButtonR1, so once this chrome takes the bumpers a
	PAD PLAYER KEEPS NOTHING there — Comma and Period are keyboard keys. That is
	TabView and Table, i.e. the `tab-view` and `table-virtualized` demos, and
	`tests/tab_view.spec.luau` asserts the shoulders as the pad's paging
	affordance. R19 authorises the trade; this is its real price, and it is the
	showcase's price only — a game embedding Facet binds its own chrome keys.

	RULING R20 (controller, 2026-08-21) — the chrome toggle DROPS `ButtonY`
	entirely. The bumpers are already the pad's two doors, which makes a pad toggle
	redundant; the platform convention gives the right face button to menus and
	context actions; and the framework's own menu verb claims it. There is no
	gamepad toggle key, and `TOGGLE_GAMEPAD` is gone rather than left naming a
	binding that no longer exists.

	THE TIE, CLOSED (W3-D, ADR-0053, 2026-08-23). `presenter.luau`'s first modal
	used to sit at `topModalPriority() + 500` = 3500 — the same number this
	context hand-picked — and the engine's own rule is "contexts with the same
	priority will receive the input" (artifacts/release-candidate-review/input/
	ias-inventory.md §A.2), so a modal demo with a focused adjust target still
	double-fired. `task-dir4-report.md` reported it CONTESTED and
	`t16-triage.md` recorded the director's ruling: ship the tie as-is, "band
	re-spacing rides the extraction charter." The option weighed and declined
	at the time — an example-local `TOGGLE_PRIORITY = 3501` — broke the
	first-modal tie in the chrome's favour without touching a framework band,
	but left the SECOND modal (4000) winning, so the rule would have been "the
	chrome wins one modal depth and loses the next": a worse thing to explain
	than the tie it replaced. The framework re-banding is `presenter
	.APP_CHROME_PRIORITY` (registry item 24) — a band with real room above it,
	reserved for exactly this: session-lifetime, app-level global chrome bound
	once and meant to win against any live modal depth this codebase
	exercises, not a number this example had to guess and re-guess. ]]

local showcase_chrome = {}

-- the two sections the panel can show; `kind` never goes nil (a picker needs a
-- value), so PRESENCE is the separate `open` signal
showcase_chrome.KINDS = table.freeze({ "demos", "settings" })

showcase_chrome.COPY = table.freeze({
	section = "Section",
	demos = "Demos",
	settings = "Settings",
})

--[[ THE TOGGLE KEY, exported so the spec drives the same string the binding
	carries rather than a copy of it (a test that types its own key code proves the
	test's opinion, not the binding's).

	THERE IS NO `TOGGLE_GAMEPAD` (ruling R20, 2026-08-21). It named `ButtonY` for
	three weeks, and `ButtonY` is `menu.luau`'s gamepad trigger — see §5. The
	constant is DELETED rather than nil'd or left pointing at a key this module no
	longer binds, because a consumer printing "chrome toggle: X / Y" from it would
	otherwise print a route that does not exist. It shipped un-released inside
	0.10.0, so its removal rides R15 (breaking changes ride the unreleased version)
	and is recorded there; the pad's route is `SECTION_GAMEPAD` below. ]]
showcase_chrome.TOGGLE_KEYBOARD = "Backquote"
--[[ THE PAD'S TWO DOORS (director round 3, 2026-08-21). The chips sit at the two
	top corners of the strip, so the two SHOULDER buttons match them by position:
	the left one opens the demo list, the right one opens settings. A player holding
	a pad reaches the thing on the left with the button on the left.

	AND THEY ARE THE PAD'S ONLY ROUTE (R20). A face-button toggle would leave the
	SECTION to whatever it was, which is one press to open and a second to choose —
	fine on a keyboard where the section switch is a Tab away, one press too many on
	a pad, and moot now that the only free face button turned out to belong to the
	framework's menu verb. These two are the same verb with a destination attached,
	bound on a SINKING context (§5: the framework's own Adjust binds this pair, so
	the contention is real and is resolved by priority) and entering through the
	same `requestFromNavigation`, so the focus ring is visible on the frame the
	panel opens. ]]
showcase_chrome.SECTION_GAMEPAD = table.freeze({ demos = "ButtonL1", settings = "ButtonR1" })
--[[ WHAT THE PLAYER IS TOLD, and why it is a `displayName` rather than a string
	beside the chip. `InputBinding.DisplayName` is the framework's own hint seam —
	`Facet.inputHint(core, env, action)` reads exactly this and re-labels with no
	remount when the input class flips — so declaring the glyph on the BINDING is
	what keeps the affordance and the binding from ever disagreeing. Roblox's
	default pad art is Xbox-style, which is where LB/RB come from; a platform-aware
	spelling changes this table and the chips follow. ]]
showcase_chrome.SECTION_GLYPH = table.freeze({ demos = "LB", settings = "RB" })
-- the panel's surface id, named once: `raisePanel` matches focus paths against
-- it and the screen declares it. THE BAR HAS NO SUCH CONSTANT — its id appears
-- exactly once in this file, and a named constant with one reader is the dead
-- `sectionActions` table this module already removed (DIR4 review MINOR-1).
showcase_chrome.PANEL_ID = "ShowcasePanel"

--[[ overscanEdge(distanceProfile, insets, edge) -> the margin the RENDERER will
	apply on this display, in pixels.

	PURE, AND TAKING TWO VALUES RATHER THAN AN ENVIRONMENT, because it has two
	callers who read the environment differently: this module reads it inside a
	memo (`use`), and the host reads it once per heartbeat (`:get`). A helper that
	took the environment would have to pick one and the other would be a second
	copy of the rule.

	THE GATE IS `distanceProfile`. `renderer.luau` applies `effectiveOverscanInsets`
	only while the profile is "ten-foot"; a game may AUTHOR overscan on a near
	display and the renderer still ignores it, so reading the insets alone would
	inset the chrome on a surface whose content was never inset. ]]
function showcase_chrome.overscanEdge(distanceProfile: any, insets: any, edge: string): number
	if distanceProfile ~= "ten-foot" then
		return 0
	end
	local v = if type(insets) == "table" then (insets :: any)[edge] else nil
	return if type(v) == "number" and v == v and v > 0 then v else 0
end

-- nextKind(current) -> the other section. The couch path: with one toggle key
-- and two targets, holding the key's second press for "close" and giving the
-- SECTION its own control inside the panel is the shape that keeps one key
-- meaning one thing.
function showcase_chrome.otherKind(current: string): string
	return if current == "settings" then "demos" else "settings"
end

-- what a toggle press should do, as a pure function of the live state. Pulled
-- out so the spec can assert the state machine without a presenter.
export type ToggleCommand = { action: string, kind: string }

function showcase_chrome.toggle(open: boolean, current: string, want: string?): ToggleCommand
	if want == nil then
		-- the KEY path: it is a toggle, because the keyboard has no Cancel key
		return if open then { action = "close", kind = current } else { action = "open", kind = current }
	end
	if open and current == want then
		return { action = "close", kind = current }
	end
	return { action = "open", kind = want }
end

export type MountOpts = {
	Facet: any,
	core: any,
	env: any,
	presenter: any,
	actionSystem: any,
	-- the composed demo picker (`demo_picker.mount{ composed = true }`)
	demos: any,
	-- the composed settings surface (`settings_panel.mount`)
	settings: any,
	-- the live core-topbar inset, as a Readable: the bar is presented
	-- edge-to-edge (it OWNS the strip) and so places itself below the Roblox
	-- buttons reactively
	coreTop: any,
	-- called with the chip row's solved bottom edge after every refresh, so the
	-- host can reserve exactly what the chips measure instead of a literal
	onChipsBottom: ((number) -> ())?,
	-- ...and the chip row's whole solved RECT, so the host can declare it as app
	-- chrome (`appChromeRects`) instead of only as a bounding-box inset
	onChipsRect: ((any) -> ())?,
	-- override the section switch's copy; see settings_panel.MountOpts.copy
	copy: { [string]: string }?,
}

function showcase_chrome.mount(opts: MountOpts): any
	local Facet = opts.Facet
	local UI = Facet.UI
	local core = opts.core
	local presenter = opts.presenter
	local scope = core:scope("showcase-chrome")
	local COPY: any = opts.copy or showcase_chrome.COPY

	local kind = scope:own(core:signal("demos"))
	local open = scope:own(core:signal(false))

	local self: any = {}
	local PANEL_ID = showcase_chrome.PANEL_ID

	-- ===== the toggle context ===============================================
	-- BUILT BEFORE THE STRIP, because the strip DRAWS these bindings: the shoulder
	-- glyph beside each chip is `Facet.inputHint` reading the binding's own
	-- `DisplayName`, so the action has to exist before the blueprint that labels
	-- it. Every handler below reaches `self` at call time, so nothing here depends
	-- on the rest of `mount` having run.
	local toggleContext = opts.actionSystem.createContext({
		name = "ShowcaseChromeToggle",
		-- registry item 24 (W3-D, ADR-0053): was `showcase_chrome.TOGGLE_PRIORITY
		-- = 3500`, a literal that tied `presenter.luau`'s own first-modal number
		-- exactly — see "THE TIE, CLOSED" in this module's header. Session-lifetime
		-- app chrome now reads the framework's own reserved band instead of
		-- guessing one.
		priority = presenter.APP_CHROME_PRIORITY,
		-- SINKING (§5, ruling R19). `ButtonL1`/`ButtonR1` are the framework's own
		-- Adjust step keys, so a press with an adjustable focused used to fire this
		-- AND move the value under the ring. One press must resolve to one context:
		-- `deviceKey` cuts every strictly-lower candidate for the same key code
		-- once a sinking context has been delivered. Per-KEY, so the toggle key
		-- consumes nothing that was ever bound elsewhere.
		sink = true,
	})
	-- the CLOSED vocabulary (constitution §9): "activate the chrome". No new verb.
	local toggleAction = toggleContext.createAction("Activate", "Bool")
	-- ONE KEY. The pad reaches the chrome through the two shoulders below, never
	-- through a face button (R20, §5).
	toggleAction.bind({ keyCode = showcase_chrome.TOGGLE_KEYBOARD })
	toggleAction.onPressed(function()
		self.requestFromNavigation(nil)
	end)
	--[[ ONE ACTION PER DESTINATION, on the same context. `request` runs the same
		`toggle` command the chips do, so pressing the shoulder of the section that is
		already showing CLOSES it (one button, one place, both directions) and
		pressing the other one SWITCHES without closing — which is what "two buttons,
		two destinations" has to mean for the pair to be worth two buttons. ]]
	local sectionAction: { [string]: any } = {}
	for _, kindName in showcase_chrome.KINDS do
		local action = toggleContext.createAction(`Activate{kindName}`, "Bool")
		action.bind({
			keyCode = showcase_chrome.SECTION_GAMEPAD[kindName],
			-- what the chip says out loud; see SECTION_GLYPH
			displayName = showcase_chrome.SECTION_GLYPH[kindName],
		})
		action.onPressed(function()
			self.requestFromNavigation(kindName)
		end)
		sectionAction[kindName] = action
	end

	--[[ THE SHOULDER GLYPH BESIDE THE CHIP (director round 4, 2026-08-21: "how
		would a user know they're available for the left/right buttons").

		A pad player is told the same way a console dashboard tells them — the button
		mark sits beside the thing it opens, LB at the outside edge of the left chip
		and RB at the outside edge of the right one, which is the POSITION argument
		the two bindings were chosen on, drawn.

		THE LABEL IS THE BINDING'S OWN. `Facet.inputHint` resolves the action's
		preferred binding for the live input class and returns its `DisplayName`, so
		there is no second copy of "LB" anywhere and a re-spelling changes one table.
		The GATE is separate and explicit: `preferredBinding` answers the first
		keyCode binding for every non-touch class, so without it a keyboard would be
		told to press LB. `effectiveInput` is the RESOLVED class (a pad nobody has
		touched yet still reports KeyboardAndMouse), which is the same fact
		`inputHint` itself reads.

		A `UI.When` and not an empty string: an empty `UI.Text` is still a child, and
		a child costs the HStack a gap. Non-pad rows measure byte-identically. ]]
	local gamepadActive = scope:own(core:memo(function(use)
		return use(opts.env:get("effectiveInput")) == "Gamepad"
	end))
	local hintLabel: { [string]: any } = {}
	for _, kindName in showcase_chrome.KINDS do
		hintLabel[kindName] = Facet.inputHint(core, opts.env, sectionAction[kindName], { scope = scope })
	end
	-- A FUNCTION, not a shared node: the two ViewThatFits rungs are two trees and
	-- must never share a node table (the picker's own `buildRows` says why).
	local function shoulderHint(kindName: string): any
		local text = hintLabel[kindName]
		-- `DemosHint` / `SettingsHint`: PascalCase like every other id on this
		-- surface, because a node path is read by a device sweep
		return UI.When({
			id = `{string.upper(string.sub(kindName, 1, 1))}{string.sub(kindName, 2)}Hint`,
			condition = gamepadActive,
			thenView = function()
				return UI.Text({
					id = "Glyph",
					text = text,
					-- caption + secondary is the framework's own "this is an aside"
					-- pair (settings_panel's own notes use it). It WRAPS rather than
					-- clips like every other player-facing string here, so a locale
					-- that spells the button longer stays readable.
					textSize = "caption",
					role = "secondary",
				})
			end,
		})
	end

	-- ===== the panel's own section switch ===================================
	-- A SEGMENTED PICKER, not a second pair of chips. The strip's chips SAY
	-- "open this"; this says "which section am I in", which is a different
	-- question and reads as one. It is also what makes both targets reachable
	-- from ONE toggle key: press the key, then Tab/d-pad onto this.
	-- the disable is gone (ADAPT-1 call-site review): two short labels resolve
	-- segmented at every width anyway, so declaring it only hid the ladder
	local sectionPicker = Facet.Controls.Picker(core, {
		id = "Section",
		label = COPY.section,
		options = {
			{ value = "demos", label = COPY.demos },
			{ value = "settings", label = COPY.settings },
		},
		selected = kind,
	})

	--[[ THE TEN-FOOT MARGIN, ON ALL FOUR EDGES (DIR4 review MINOR-5).

		The first version inset LEFT and TOP and left the other two at the screen
		gutter, which measured `x102 y72 w1806` at 1920x1080 — a right edge at 1908
		on a set that crops 90. Nothing in the strip is right-aligned today so
		nothing was hidden, but the `ViewThatFits` ladder was choosing its rung
		against an offer ~90px wider than the visible width, which is
		"painted at a size nobody measured" one step removed, and any future
		right-hand chrome would land behind the glass.

		SO IT IS THE DOCK'S PADDING, NOT THE BAR'S OFFSETS. A padding insets the
		anchor box on every edge at once, so the answer cannot be half-applied again
		the way two offsets could; it composes with the screen's own `gutter` padding
		rather than replacing it; and `width = fill` inside it now fills the VISIBLE
		width, which is what makes the ladder's offer honest.

		ONE MEMO, RE-USED — not a fresh table per read. `effectiveOverscanInsets` is
		itself a fresh table on every recompute, so this memo is written to recompute
		only when the two facts it reads change (a memo caches its value between
		dependency changes) and every reader then sees one identity per change rather
		than one per read.

		THE GATE IS `distanceProfile`, NOT THE INSETS THEMSELVES. `renderer.luau`
		applies the overscan only while the profile is "ten-foot"; a game may AUTHOR
		`overscanInsets` on a near display and the renderer will still ignore them,
		so reading the insets alone here would inset the strip on a surface whose
		content was never inset — the exact double-standard this fixes, mirrored. ]]
	local overscanPadding = scope:own(core:memo(function(use)
		local profile = use(opts.env:get("distanceProfile"))
		local insets = use(opts.env:get("effectiveOverscanInsets"))
		return {
			top = showcase_chrome.overscanEdge(profile, insets, "top"),
			bottom = showcase_chrome.overscanEdge(profile, insets, "bottom"),
			left = showcase_chrome.overscanEdge(profile, insets, "left"),
			right = showcase_chrome.overscanEdge(profile, insets, "right"),
		}
	end))

	-- ===== the strip ========================================================
	-- CONTENT on both rungs, and now because it is what they MEAN rather than
	-- because the alternative was broken: `hug` capped at the offer, so a hug row
	-- could never report that it did not fit and the ladder pinned its first
	-- candidate forever ("the p4_foyer trap"). Facet closed it at the seam in
	-- ADR-0044 — the fit probe judges a candidate at its ideal size, `hug`'s cap
	-- included — so the two spellings agree at every width. These rungs want the
	-- UNCAPPED natural width either way.
	local NATURAL = { type = "content" }
	local chipRow = UI.ViewThatFits({
		id = "Chips",
		width = UI.fill(),
		children = {
			UI.HStack({
				id = "Full",
				gap = "s",
				width = NATURAL,
				children = {
					shoulderHint("demos"),
					opts.demos.chip,
					opts.settings.chip,
					shoulderHint("settings"),
				},
			}),
			UI.HStack({
				id = "Icons",
				gap = "s",
				width = NATURAL,
				children = {
					shoulderHint("demos"),
					opts.demos.iconChip,
					opts.settings.iconChip,
					shoulderHint("settings"),
				},
			}),
		},
	})

	local barScreen = UI.Screen({
		id = "ShowcaseChrome",
		--[[ THE SCREEN EDGE IS `gutter`, NOT `s` (DIR-1, 2026-08-17 device round).
			This strip is the one the director photographed with its left border
			clipped at the glass, and it was standing off by whatever the active
			package called a small gap — 4px under classic-desktop, 6px under
			compact-pointer. `space.gutter` is that package's own step FLOORED at 8
			(src/themes/snapshot.luau, "THE SCREEN-EDGE GUTTER, WITH A FLOOR"), so a
			package that breathes more still does and no package can go under the
			floor. The panel below spends the same step for the same reason; the
			ScrollView inside it does NOT — that padding is between a card's edge and
			its own rows, which is a spacing decision and stays `s`. ]]
		padding = "gutter",
		children = {
			UI.Anchor({
				id = "Dock",
				padding = overscanPadding,
				width = UI.fill(),
				height = UI.fill(),
				children = {
					UI.VStack({
						id = "Bar",
						anchor = "topLeft",
						-- PUSHED DOWN PAST THE ROBLOX BUTTONS, not lifted into a
						-- reserved strip: the bar is presented edge-to-edge because
						-- it OWNS the strip.
						--
						-- THE BEZEL IS THE DOCK'S PADDING, one level up (director
						-- round 4, 2026-08-21: "the picker/settings buttons seem to
						-- have disappeared on console"). `rootPolicy = "edgeToEdge"`
						-- is honoured by the SOLVER, which takes the whole viewport
						-- and reads no insets at all — so the renderer's ten-foot
						-- margin (`renderer.luau`: distanceProfile == "ten-foot" adds
						-- `effectiveOverscanInsets` to the content rect) reached every
						-- content surface and never reached this one. Measured at
						-- 1920x1080 / Large: the demo body started at (90,149) and the
						-- chips at (12,12) — twelve pixels in from a glass edge a real
						-- television crops by ninety.
						--
						-- The strip still OWNS the strip; owning it never included the
						-- part of the panel the set does not display. What is left
						-- here is the topbar alone, because the Roblox buttons sit
						-- INSIDE the displayed area and the bezel is outside it.
						offsetY = opts.coreTop,
						width = UI.fill(),
						children = { chipRow },
					}),
				},
			}),
		},
	})

	-- ===== the panel ========================================================
	-- ONE CARD, ONE SCROLLER (the theme picker's round-10 finding, restated):
	-- `ScrollView` takes `surface` and `padding` like any container, so the
	-- scroller IS the card — one node, one edge, one padding, scrollbar inside
	-- it by construction. Both sections therefore hand over PLAIN stacks; a
	-- raised scroller inside a raised card is the "two raised surfaces" shape
	-- that was already rejected once.
	--
	-- `hug` on both axes is one declaration for two cases: the settings card
	-- stops at its last row, and the thirteen-demo list lets the cap bite so the
	-- overflow turns scrolling on.
	local panelScreen = UI.Screen({
		id = PANEL_ID,
		-- the screen edge again (see `barScreen` above): `gutter`, floored at 8
		padding = "gutter",
		children = {
			UI.Anchor({
				id = "Dock",
				width = UI.fill(),
				height = UI.fill(),
				children = {
					UI.VStack({
						id = "Column",
						anchor = "topLeft",
						width = UI.fill(),
						height = UI.fill(),
						children = {
							UI.ScrollView({
								id = "Panel",
								surface = "raised",
								padding = "s",
								gap = "s",
								width = UI.hug(),
								height = UI.hug(),
								children = {
									sectionPicker.blueprint,
									UI.When({
										id = "DemosWhen",
										condition = scope:own(core:memo(function(use)
											return use(kind) == "demos"
										end)),
										thenView = function()
											return opts.demos.rows
										end,
									}),
									UI.When({
										id = "SettingsWhen",
										condition = scope:own(core:memo(function(use)
											return use(kind) == "settings"
										end)),
										thenView = function()
											return UI.VStack({
												id = "Settings",
												width = UI.fill(),
												gap = "m",
												children = opts.settings.sections,
											})
										end,
									}),
								},
							}),
						},
					}),
				},
			}),
		},
	})

	-- ===== presentation =====================================================
	local barHandle: any = nil
	local panelHandle: any = nil
	local panelWatch: (() -> ())? = nil
	local closing = false

	local barOpts = {
		-- PASSIVE (ADR-0014): the strip binds nothing gameplay-contended, and it
		-- never engages — every route into the chrome goes through the panel.
		responder = "passive",
		--[[ ...AND ADOPTED AS THE APP'S FRAME (device review 2026-08-16, F1: "the
			demo list and settings button aren't reachable with the dpad").

			Everything in §2 above stays true — the bar is presented once, before the
			first demo, and its scope stays buried so Tab and the arrows belong to the
			demo. What was missing is that "buried" meant UNREACHABLE: every navigation
			verb reads the top scope alone, so a d-pad pressed against a demo walked
			that demo's own ring forever and the two chips were reachable by pointer
			and by a toggle button nothing on the screen named (`ButtonY` then; the
			shoulders now, and they SAY so — see the glyph beside each chip).

			`focusChrome` is the framework capability that closes it (presenter
			PresentOpts; `FocusScope.chrome`): the strip's focusables are ADOPTED into
			whatever scope is active, so the demo's own focus map carries them at its
			`top` edge. Pressing UP off the demo's first row lands on the chips;
			pressing DOWN leaves them again. The demo still OWNS the scope, still takes
			entry focus, and a modal still suspends the whole thing.

			It does NOT replace the shortcuts. Backquote on a keyboard, and the two
			shoulders on a pad, open the panel from anywhere including inside a
			scrolled list; this is the route a player finds without being told one
			exists. ]]
		focusChrome = "top",
		-- the bar owns the strip it draws in, so it is not inset by it
		rootPolicy = "edgeToEdge",
		onGeometry = function(rectOf: (string) -> any)
			local r = rectOf("/ShowcaseChrome/Dock/Bar/Chips")
			if type(r) ~= "table" or type(r.y) ~= "number" or type(r.h) ~= "number" then
				return
			end
			if opts.onChipsBottom ~= nil then
				opts.onChipsBottom(r.y + r.h)
			end
			-- ...AND THE WHOLE RECT, not only its bottom edge (director 2026-08-15,
			-- item 4). A bottom edge is a BOUNDING BOX — it says "the top N pixels of
			-- this screen are spoken for" about a row that is 300px wide — and a
			-- surface told only that has no choice but to start below it everywhere.
			-- The rect is what the app declares through `appChromeRects`, which is
			-- the same mechanism the PLATFORM's own cluster is declared through.
			--
			-- IT IS THE WINNING RUNG'S RECT, NOT THE LADDER'S. `Chips` is a
			-- `ViewThatFits` with `width = fill`, so ITS rect is the whole screen
			-- width — measured live 2026-08-15 at 8..741 on a 749px landscape phone
			-- while the two chips it was drawing ended at 267. Declaring the ladder's
			-- box would have reserved the middle of the screen for a row that is not
			-- there, which is the same bounding-box mistake one level down.
			if opts.onChipsRect ~= nil then
				local best: any = nil
				for _, rung in { "Full", "Icons" } do
					local c = rectOf(`/ShowcaseChrome/Dock/Bar/Chips/{rung}`)
					if type(c) == "table" and type(c.w) == "number" and c.w > 0 and c.h > 0 then
						if best == nil or c.w > best.w then
							best = c
						end
					end
				end
				opts.onChipsRect(best or r)
			end
		end,
		-- NO surface-level `onActivate`. It is an OVERRIDE (presenter
		-- §dispatchActivate) — it wins outright and returns, so every node on the
		-- surface would lose its own handler, which is precisely what killed both
		-- chips the last time this was routed by path matching.
	}

	--[[ THE RING'S LAST KNOWN ROW INSIDE THE PANEL (registry item 23; W3-D,
		ADR-0053), so a raise can hand it straight back to `presenter.focus
		.focusOn`. `presenter.raise` re-tops the panel's OWN focus scope — the
		fix for the OTHER half of this problem, that a freshly re-presented
		demo's scope steals the graph's "active scope" out from under a raised
		surface even though the surface's PAINT is back on top — but it has no
		memory of "where the player was" and must not invent one (its own
		header explains why). So this is still tracked, the same way the
		OLD dismiss+re-present mitigation had to. WHAT IS GONE is the RETRY:
		that mitigation needed `pendingFocus`/`pendingFocusTries` and an
		`onGeometry` callback because a fresh remount's rects were not known
		yet and `initialFocus = "first"` would land a moment later and
		overwrite a same-frame `focusOn`. `raise` never remounts, so the
		panel's rects are already known the instant it returns and a single
		`focusOn` call below lands synchronously — no race to wait out. ]]
	local lastPanelFocus: string? = nil
	--[[ A PREFIX TEST NEEDS ITS SEPARATOR (DIR4 review MINOR-7). Without it
		`/ShowcasePanelX/Row` reads as "mine", which is wrong in the one function
		whose whole job is deciding ownership — the spec file's own `isPrefix` helper
		has always checked for it. Harmless with one such surface; wrong as written. ]]
	local PANEL_ROOT = `/{PANEL_ID}`
	local function isPanelPath(path: any): boolean
		if type(path) ~= "string" then
			return false
		end
		return path == PANEL_ROOT or string.sub(path, 1, #PANEL_ROOT + 1) == `{PANEL_ROOT}/`
	end
	scope:own(core:observe(presenter.focus.focused, function(path: any)
		if isPanelPath(path) then
			lastPanelFocus = path
		end
	end))

	local function closePanel()
		if panelHandle == nil then
			return
		end
		closing = true
		if panelWatch ~= nil then
			panelWatch()
			panelWatch = nil
		end
		presenter.dismiss(panelHandle)
		panelHandle = nil
		closing = false
		-- a fresh open starts at the panel's own first stop, never on a row
		-- the player was reading last time
		lastPanelFocus = nil
		open:set(false)
	end

	local function openPanel()
		if panelHandle ~= nil then
			return
		end
		-- the bar must not hold first responder alongside the panel: a tap on a
		-- chip engaged it on the way in, and two engaged surfaces share the 3000
		-- band, so both would receive Tab and the ring would step twice
		if barHandle ~= nil then
			barHandle.resign()
		end
		panelHandle = presenter.present(panelScreen, {
			responder = "passive",
			-- EXPLICIT, because the passive default is `"none"` — correct for a
			-- HUD that appears unasked, wrong for a surface that exists only
			-- because the player just asked for it. `"first"` is what makes a
			-- keyboard or a pad land somewhere on the frame it opens.
			initialFocus = "first",
		})
		-- ...and this is the call the whole item turns on. Nothing in `src/` ever
		-- makes it outside the tap handler, so without it Tab and Space are never
		-- bound on this surface and the pad's Navigate never reaches it.
		panelHandle.engage()
		open:set(true)
		-- CANCEL, AN OUTSIDE TAP AND `resign()` ALL LAND IN ONE PLACE. The
		-- presenter answers each of them by resigning the surface, not by
		-- dismissing it, so the responder signal is the seam that turns "the
		-- player left" into "the panel is gone".
		panelWatch = core:observe(panelHandle.responder, function(state: any)
			if state == "passive" and not closing then
				closePanel()
			end
		end)
	end

	--[[ AN OPEN PANEL GOES BACK ON TOP WHEN THE DEMO UNDER IT CHANGES (director
		round 3, 2026-08-21; MIGRATED TO `presenter.raise` 2026-08-23 — registry
		item 23, W3-D, ADR-0053).

		THE RULE IT SERVES: a transient opened from a control appears OVER the live
		screen, and the live screen stays visible behind it. THE MECHANISM IT
		REPAIRS: cross-surface z is PRESENT ORDER — the presenter hands each
		presented surface the next slot in its band — and a demo swap DISMISSES AND
		RE-PRESENTS the demo, so the demo climbs past a panel that was presented
		before it. Measured on `tests/gallery_chrome.spec.luau`'s harness: six swaps
		put the demo at displayOrder 11000 against the panel's 10400, i.e. the list
		the player is reading ends up underneath the screen they are reading it over.

		RAISE, NOT RE-PRESENT. Until this landed, the fix here was dismiss+re-present
		— "rebuilding it is cheaper than teaching the presenter a raise operation for
		one example's benefit" — which is exactly the workaround `presenter.raise`
		replaces: `raisePanel` below hands `panelHandle` straight to it, so the SAME
		handle takes a new band slot in place. Nothing unmounts and nothing replays a
		transition — but focus still needs a hand back (see the block above
		`closePanel`): `presenter.raise` re-tops the panel's paint AND its focus scope,
		but a freshly re-presented demo's own scope still steals the graph's "active"
		slot the instant IT is presented, before this function ever runs, so the ring
		lands on the demo's own entry point until `focusOn` below puts it back. What
		IS gone is the 4-frame retry loop (review MINOR-4): `raise` never remounts, so
		the panel's rects are already known and `focusOn` lands synchronously, first
		try, every time.

		=== THE LAYER COST IS UNCHANGED, WHICH IS WORTH SAYING PRECISELY ===

		`presenter.luau`'s `displayLayer` counter still goes UP 100 per present OR
		raise, and back to zero only when the stack EMPTIES — this stack never does,
		because the backdrop is permanent. A swap under an OPEN panel still costs
		+200 (the demo's present and this raise) where a swap under a closed panel
		costs +100 — `raise` was never a cheaper NUMBER, it is a cheaper OPERATION:
		what it removes is the mount/scope/transition/focus cost of a full
		dismiss+re-present, not the band slot, which no re-banding scheme in this
		framework can avoid paying (see `presenter.APP_CHROME_PRIORITY`'s own header
		for the fuller version of that argument). `task-dir4-report.md`'s CONTESTED
		framing and its halved-horizon numbers (30300 vs 20300 over 100 swaps) still
		hold exactly as measured; only the mechanism paying for them changed. ]]
	local function raisePanel(demoHandle: any?)
		if panelHandle == nil then
			return
		end
		--[[ NOTHING WAS PRESENTED, SO NOTHING CLIMBED: RAISE NOTHING.

			THE CONTRACT. A raiser hands over the handle of the screen it just
			presented, and `nil` means it presented NONE. `demo_picker`'s `raise()`
			passes `mounted.handle`, and `mounted` is nil exactly when `mountDemo`
			threw — the failed-mount path, where `show()` has dismissed the old demo
			and put nothing in its place. A dismissal does not move `displayLayer`;
			only a present (or a raise) does. So on that path the panel is provably
			still where it was, above what is left, and raising it would spend a slot
			to restore an order that never changed. `presenter.raise` has its own
			"is this handle even still live" refusal, but this guard is a DIFFERENT
			question — not "is `panelHandle` valid" but "did anything actually climb
			above it" — so it stays here rather than folding into the seam. ]]
		if demoHandle == nil then
			return
		end
		--[[ SNAPSHOT BEFORE `raise`, NOT AFTER — `raise` itself may set focus
			(its own fallback: the demo's stolen path is not a member of the
			panel's re-topped scope, so it lands on the scope's fresh entry
			point), and that write is STILL inside `/ShowcasePanel/...`, so
			the observer above would silently overwrite `lastPanelFocus` with
			it before this function ever got to read the row the player was
			actually on. Reading your own write through an observer you also
			own is the trap; a plain local captured first has no race. ]]
		local wantFocus = lastPanelFocus
		presenter.raise(panelHandle)
		-- HAND FOCUS BACK, SYNCHRONOUSLY (see the block above `closePanel`).
		-- `raise` re-topped the panel's scope, so `focusOn` can now reach it;
		-- `wantFocus` is nil the one time it should be (a fresh panel that has
		-- never held focus yet), in which case the scope's own fresh entry
		-- point — already set by `raise` — stands untouched.
		if wantFocus ~= nil then
			presenter.focus.focusOn(wantFocus)
		end
	end
	if opts.demos ~= nil and opts.demos.watchRaise ~= nil then
		-- AFTER the demo is presented, never on the selection signal: the picker
		-- sets `selection` and mounts on the same call, so a watcher on the signal
		-- would raise the panel and then watch the demo land on top of it.
		scope:own(opts.demos.watchRaise(raisePanel))
	end

	-- apply(command) -> run a ToggleCommand. One place, so a chip press, the
	-- toggle key and the scriptable drive cannot drift apart.
	local function apply(command: ToggleCommand)
		if command.action == "close" then
			closePanel()
			return
		end
		if kind:get() ~= command.kind then
			kind:set(command.kind)
		end
		openPanel()
	end

	function self.request(want: string?)
		apply(showcase_chrome.toggle(open:get(), kind:get(), want))
	end

	-- THE KEY/PAD ROUTE. `setFocusOrigin("navigation")` before the present, so
	-- the ring is VISIBLE on the frame the panel opens: focus origin decides
	-- whether the ring paints, and a chrome opened from a key must show where
	-- the next press goes (api.md "Focus identity vs the focus RING").
	function self.requestFromNavigation(want: string?)
		presenter.focus.setFocusOrigin("navigation")
		self.request(want)
	end

	-- THE DEMO CHIP SAYS "Close" WHILE ITS OWN SECTION IS SHOWING, and only then:
	-- panel presence is one fact here, so the picker's own flag is derived from
	-- it rather than being a second copy that can disagree. Writing it back (as
	-- opposed to handing the picker a memo) keeps the picker's standalone path —
	-- where it really does own its own open state — byte-identical.
	local function syncDemoOpen()
		local flag = open:get() and kind:get() == "demos"
		if opts.demos.open ~= nil and opts.demos.open:get() ~= flag then
			opts.demos.open:set(flag)
		end
	end
	scope:own(core:observe(open, syncDemoOpen))
	scope:own(core:observe(kind, syncDemoOpen))
	syncDemoOpen()

	barHandle = presenter.present(barScreen, barOpts)

	self.open = open
	self.kind = kind
	self.barScreen = barScreen
	self.panelScreen = panelScreen
	function self.barHandle()
		return barHandle
	end
	function self.panelHandle()
		return panelHandle
	end
	function self.isOpen(): boolean
		return panelHandle ~= nil
	end
	function self.close()
		closePanel()
	end
	function self.dispose()
		closePanel()
		if barHandle ~= nil then
			presenter.dismiss(barHandle)
			barHandle = nil
		end
		toggleContext.destroy()
		sectionPicker.dispose()
		scope:dispose()
	end
	return self
end

return showcase_chrome
