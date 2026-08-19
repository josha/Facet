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
	than clipping labels by character count. `p4_foyer`'s nav bar is the
	reference, including its trap: a candidate must be sized `content` (the
	uncapped natural width), because `hug` CAPS at the offer and a capped row can
	never tell a `ViewThatFits` that it does not fit — the ladder would silently
	pin its first candidate and the labels would truncate anyway.

	=== 4. THE BINDINGS, AND WHY THESE TWO KEYS ===

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
	  * GAMEPAD — **ButtonY**. `ButtonA` is Activate and is eaten unconditionally
	    by the legacy `jumpAction` (docs/lessons/gamepad-contention-truths.md
	    truth 1); `ButtonB` is Cancel; `ButtonX` is the row-actions menu;
	    `ButtonStart`/`ButtonSelect` are the platform's own menu buttons and are
	    exactly the trade the gamepad-contention lesson refuses to make. ButtonY
	    is the one face button no verb in this framework claims.

	The context sits at priority 3500 — above the engaged band (3000) — so the
	toggle key can still be pressed while the panel it opened is engaged and
	sinking. Sinking is per-KEY (`actions.luau` `deviceKey` only cuts candidates
	for the same key code), so this steals nothing from anything: no other
	context in the place binds either key. ]]

local showcase_chrome = {}

-- the two sections the panel can show; `kind` never goes nil (a picker needs a
-- value), so PRESENCE is the separate `open` signal
showcase_chrome.KINDS = table.freeze({ "demos", "settings" })

showcase_chrome.COPY = table.freeze({
	section = "Section",
	demos = "Demos",
	settings = "Settings",
})

-- THE TOGGLE KEYS, exported so the spec drives the same strings the bindings
-- carry rather than a copy of them (a test that types its own key code proves
-- the test's opinion, not the binding's).
showcase_chrome.TOGGLE_KEYBOARD = "Backquote"
showcase_chrome.TOGGLE_GAMEPAD = "ButtonY"
-- strictly above the engaged band (`presenter.luau` ENGAGED_BASE_PRIORITY =
-- 3000) so an engaged panel can never sink its own way out
showcase_chrome.TOGGLE_PRIORITY = 3500

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

	-- ===== the strip ========================================================
	-- CONTENT, NOT HUG, on both rungs (the p4_foyer trap): `hug` caps at the
	-- offer, so a hug row can never report that it does not fit and the ladder
	-- would pin its first candidate forever.
	local NATURAL = { type = "content" }
	local chipRow = UI.ViewThatFits({
		id = "Chips",
		width = { type = "fill", weight = 1 },
		children = {
			UI.HStack({
				id = "Full",
				gap = "s",
				width = NATURAL,
				children = { opts.demos.chip, opts.settings.chip },
			}),
			UI.HStack({
				id = "Icons",
				gap = "s",
				width = NATURAL,
				children = { opts.demos.iconChip, opts.settings.iconChip },
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
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = {
					UI.VStack({
						id = "Bar",
						anchor = "topLeft",
						-- PUSHED DOWN PAST THE ROBLOX BUTTONS, not lifted into a
						-- reserved strip: the bar is presented edge-to-edge because
						-- it OWNS the strip.
						offsetY = opts.coreTop,
						width = { type = "fill", weight = 1 },
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
		id = "ShowcasePanel",
		-- the screen edge again (see `barScreen` above): `gutter`, floored at 8
		padding = "gutter",
		children = {
			UI.Anchor({
				id = "Dock",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = {
					UI.VStack({
						id = "Column",
						anchor = "topLeft",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = {
							UI.ScrollView({
								id = "Panel",
								surface = "raised",
								padding = "s",
								gap = "s",
								width = { type = "hug" },
								height = { type = "hug" },
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
												width = { type = "fill", weight = 1 },
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
			and by ButtonY — a button nothing on the screen names.

			`focusChrome` is the framework capability that closes it (presenter
			PresentOpts; `FocusScope.chrome`): the strip's focusables are ADOPTED into
			whatever scope is active, so the demo's own focus map carries them at its
			`top` edge. Pressing UP off the demo's first row lands on the chips;
			pressing DOWN leaves them again. The demo still OWNS the scope, still takes
			entry focus, and a modal still suspends the whole thing.

			It does NOT replace the toggle key. Backquote/ButtonY is the shortcut that
			opens the panel from anywhere including inside a scrolled list; this is the
			route a player finds without being told one exists. ]]
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

	-- ===== the toggle context ===============================================
	local toggleContext = opts.actionSystem.createContext({
		name = "ShowcaseChromeToggle",
		priority = showcase_chrome.TOGGLE_PRIORITY,
		-- NOT sinking: it binds two keys nothing else in the place binds, so
		-- there is nothing to consume and a sink would only be a claim it cannot
		-- justify.
		sink = false,
	})
	-- the CLOSED vocabulary (constitution §9): "activate the chrome". No new verb.
	local toggleAction = toggleContext.createAction("Activate", "Bool")
	toggleAction.bind({ keyCode = showcase_chrome.TOGGLE_KEYBOARD })
	toggleAction.bind({ keyCode = showcase_chrome.TOGGLE_GAMEPAD })
	toggleAction.onPressed(function()
		self.requestFromNavigation(nil)
	end)

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
