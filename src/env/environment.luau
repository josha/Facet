--!strict
-- Environment (design §8, UI-ENV-001): per-key observable client facts +
-- derived policy. Engine-free: the Roblox platform adapter (client-only)
-- pushes engine facts through set(); tests push fakes the same way. Views
-- subscribe to individual keys, so a keyboard-occlusion change never touches
-- a color-only subscriber (per-key signals guarantee that structurally).
-- Derived keys are memos over fact keys (typographyScale, sizeClass, ...).

local adaptive = require("../layout/adaptive")
local themeSnapshot = require("../themes/snapshot")

local environment = {}

export type Env = {
	get: (self: Env, key: string) -> any, -- Readable
	set: (self: Env, key: string, value: any) -> (),
	keys: (self: Env) -> { string },
}

local FACT_DEFAULTS: { [string]: any } = {
	viewportRect = { x = 0, y = 0, w = 1280, h = 720 },
	deviceSafeInsets = { top = 0, bottom = 0, left = 0, right = 0 },
	coreSafeInsets = { top = 0, bottom = 0, left = 0, right = 0 },
	topbarInset = { x = 0, y = 0, w = 0, h = 0 }, -- dynamic geometry, NOT a symmetric margin (§8.1)
	--[[ …and the SAME band stated as four edges: the topbar-safe area, measured
		from `GuiService:GetInsetArea(Enum.ScreenInsets.TopbarSafeInsets)` through
		the same conversion `coreSafeInsets`/`deviceSafeInsets` use, so it is in
		window space like them.

		THESE TWO FACTS ARE TWO ENCODINGS OF ONE RECT, AND MUST NOT BE ADDED.
		This comment used to say `topbarInset` was stated relative to the
		topbar-safe area, so the window-space band was `topbarSafeInsets.left +
		topbarInset.x`. Measured live on 2026-08-14 (Studio, Play, showcase place,
		735x413) that is wrong: the engine reports `TopbarInset` = (164,0)+571x58
		and the topbar-safe area as x 164..735 / y 0..58 — the same band — and a
		probe Frame under a `ScreenInsets = None` ScreenGui placed at
		`TopbarInset.Min` lands exactly on the strip. Adding them double-counts the
		engine's control cluster. The evidence is in tests/adaptive.spec.luau's
		DV3-1 header; the derived `platformChrome` below INTERSECTS them, which is
		an identity on a healthy platform and a belt when one is missing.

		Consumers should read `platformChrome` (band / rects / insets /
		bandInsets) rather than either raw fact: it is the one place that knows
		what a zero means. Zeroes here are "the platform reported no topbar-safe
		area", which is the desktop/no-notch answer and the pre-adoption
		behaviour — never "a strip at the window origin". ]]
	topbarSafeInsets = { top = 0, bottom = 0, left = 0, right = 0 },
	--[[ THE APP'S OWN CHROME, DECLARED THROUGH THE SAME MECHANISM AS THE
		PLATFORM'S (director 2026-08-15, item 4: *"should we also treat the demo
		selector and settings menu as part of this control so that the stuff in the
		middle are more aligned with it instead of below it?"*).

		`platformChrome` already answers "what does the PLATFORM's own chrome
		occupy, and what is left free" — as a LIST of rects, precisely because the
		remainder of a band with a strip in it is an L rather than an inset
		(ADR-0027). An APP with a persistent chrome row of its own — a showcase's
		demo/settings chips, a game's own always-on top bar — occupies exactly the
		same kind of space, and until now had no way to say so: the only vocabulary
		available was inflating `coreSafeInsets.top`, which is a BOUNDING BOX and
		therefore reserves the full width for a row that is 300px wide. Anything
		that would have sat level with it is pushed below it instead, which is the
		defect this fact exists to remove.

		It is a LIST of window-space rects, `{}` by default, and it changes nothing
		for a consumer that declares none: `platformChrome` merges it into `rects`
		and takes the free band down to what is genuinely free. It is the app's
		DECLARATION, never a measurement this module makes — the declarer is the one
		surface that knows where it drew itself, and it feeds the rect back through
		the presenter's `onGeometry` seam exactly as the showcase already feeds its
		chip row's bottom edge. ]]
	appChromeRects = {},
	keyboardOcclusionRect = nil,
	preferredInput = "KeyboardAndMouse", -- Touch | Gamepad | KeyboardAndMouse
	capabilities = { keyboard = true, mouse = true, touch = false, gamepad = false },
	reducedMotion = false,
	preferredTextSize = 1, -- multiplicative reservation seam (tests/dev profiles)
	-- ADDITIVE preference reservation (Step 8.5, decision LTN-1): the ENGINE
	-- paints every text node at TextSize + a per-preference constant pixel
	-- offset — measured live 2026-08-03 as Medium=0 / Large=4 / Larger=10 /
	-- Largest=14, uniform across font, weight and size (probe artifact:
	-- artifacts/large-text-accessibility/probe/preference-probe.json) — and
	-- the bounds APIs answer WITHOUT it, so reserving at `size + offset` is
	-- exact. The Roblox adapter populates THIS fact (measured fallback applied
	-- synchronously, GetTextSizeOffsetAsync confirmation cached per value) and
	-- subscribes to PreferredTextSize changes; the multiplier fact above stays
	-- 1 on the live path and remains the injectable test/profile seam — the
	-- two authorities never overlap.
	preferredTextOffset = 0,
	--[[ THE EXACT-WIDTH STORE'S GENERATION (director 2026-08-04, the finish-screen
		size pop). `text_metrics`' exact-width store is plain, non-reactive data
		filled ASYNCHRONOUSLY: the first solve of a newly presented surface uses the
		conservative estimator, the engine answers `GetTextBoundsAsync` a few frames
		later, and the renderer re-solves. The SOLVER re-runs and is fine — but a
		consumer MEMO that calls `LuauUI.text.fit/.size/.measure` has no dependency
		on a table nobody can subscribe to, so it evaluates once against the
		estimator and is never invalidated. It then changes at an arbitrary later
		moment, when some unrelated dependency happens to tick, which is what a
		"pop with no cause" is.

		This is that missing dependency: a counter the renderer bumps once per round
		that actually taught the measurer something. A memo that reads it re-derives
		exactly once when the round closes, and never again. It is deliberately a
		plain number rather than a timestamp — the value carries no meaning beyond
		"different from last time", and a monotonic counter is reproducible in a
		scripted test where a clock is not. ]]
	textMeasureEpoch = 0,
	preferredTransparency = 1,
	locale = "en-us",
	-- console 10-foot facts (input-paradigms expansion): the physical display
	-- class (GuiService.ViewportDisplaySize — Small | Medium | Large) and the
	-- developer-authored TV overscan-safe margins. overscanInsets is DISTINCT
	-- from coreSafeInsets/topbarInset (mobile notch / CoreGui geometry): TVs
	-- clip edges, so a ten-foot presentation insets content on all four sides.
	displaySize = "Medium", -- Small | Medium | Large
	overscanInsets = { top = 0, bottom = 0, left = 0, right = 0 },
	-- PRESENTATION SPACE (roadmap Step 4, ADR-0021). WHERE this surface is
	-- presented, as a fact rather than a device name: "screen" is the flat
	-- ScreenGui every game UI uses today, "billboard" is the shipped
	-- BillboardTarget, and "world" is the future SurfaceGui target that does not
	-- exist yet. A screen never branches on a headset model; it may reasonably
	-- ask whether it is flat or in the world, because that changes legibility
	-- and target sizing, not which controls exist.
	--
	-- Declaring "world" today does NOT make a world target appear. The value is
	-- here so the policy that will consume it can be written and tested before
	-- the adapter exists, per docs/extending/new-platform-mode.md §2.
	presentationSpace = "screen", -- screen | billboard | world
	-- THE metric authority (ADR-0019 §2): one frozen ThemeSnapshot the solver,
	-- renderer, presenter and headless suite all read, so a theme change is a
	-- single atomic commit — one key, one signal, one downstream invalidation —
	-- and every mounted screen RE-SOLVES rather than rebuilding. A plain per-key
	-- fact on purpose: it must never be derived, because the controller commits
	-- it in the same invocation as the native derive swap. The default is Studio
	-- Neutral, whose values are byte-identical to the literals the framework
	-- shipped before packages existed, so no screen has to opt in.
	themeMetrics = themeSnapshot.neutral(),
}

function environment.new(core: any): Env
	local signals: { [string]: any } = {}
	local derived: { [string]: any } = {}

	for key, default in FACT_DEFAULTS do
		signals[key] = core:signal(default)
	end
	-- keys with nil defaults still need signals
	signals.keyboardOcclusionRect = signals.keyboardOcclusionRect or core:signal(nil)

	-- derived policy (§8.2): memos subscribe only to their fact keys.
	-- Derived values CLAMP garbage platform facts into their legal domain —
	-- a broken adapter fact must never leak a negative text scale or a
	-- non-policy value downstream (phase-4 fault injection: accessibility).
	-- THE POLICY ITSELF LIVES IN `themes/snapshot` (the text-scale policy block),
	-- as pure functions of these two facts. These memos only supply the facts.
	-- The reason it moved there rather than staying here: `composition.floorPx`
	-- and the public `LuauUI.text.facts` must derive the SAME two scales from a
	-- theme snapshot, which carries the facts but has no env — and a second copy
	-- that agrees today is the defect the line-box helper exists to end
	-- (docs/plans/variable-item-extents.md).
	derived.typographyScale = core:memo(function(use)
		return themeSnapshot.typographyScale(use(signals.displaySize), use(signals.preferredTextSize))
	end)
	-- PAINT-seam scale (NS-A9; MODEL CORRECTED by Step 8.5, LTN-1): the engine
	-- applies the player's PreferredTextSize as an ADDITIVE px offset at draw
	-- time, so LuauUI must not fold the preference into the painted TextSize —
	-- that is the double-application defect. Paint carries ONLY authored scale
	-- (the ten-foot floor). On the live path the multiplier fact stays 1, so
	-- the two SCALE seams are identical and the preference travels exclusively
	-- through `preferredTextOffset` at the measure seam; a dev/test profile
	-- that raises the multiplier widens measurement only (over-reserve, safe).
	derived.typographyPaintScale = core:memo(function(use)
		return themeSnapshot.typographyPaintScale(use(signals.displaySize))
	end)
	derived.effectiveTransparency = core:memo(function(use)
		local raw = use(signals.preferredTransparency)
		if type(raw) ~= "number" or raw ~= raw then
			return 1
		end
		return math.clamp(raw, 0, 1)
	end)
	derived.sizeClass = core:memo(function(use)
		local vp = use(signals.viewportRect)
		local w = if type(vp) == "table" and type(vp.w) == "number" and vp.w == vp.w then vp.w else 1280
		-- ONE implementation of the breakpoints and the ten-foot density floor
		-- (verifier finding V15: this used to re-implement 600/1000 as literals
		-- beside src/layout/adaptive.luau's table, so the "they can never disagree"
		-- comment there was aspirational). The pure function is the single source;
		-- this memo only supplies the facts.
		return adaptive.sizeClass(w, {
			distanceProfile = if use(signals.displaySize) == "Large" then "ten-foot" else "near",
		})
	end)
	derived.motionPolicy = core:memo(function(use)
		return if use(signals.reducedMotion) == true then "reduced" else "full"
	end)
	-- SCROLL INDICATOR POLICY (director ruling 2026-08-09, "auto-showing scroll
	-- bars"): pointer sessions keep the desktop convention — a persistent bar
	-- whose thickness the solver RESERVES off the cross axis; touch and gamepad
	-- sessions get the platform convention their users know — OVERLAY
	-- indicators (no reserve) that appear while scrolling, flash once on mount
	-- so a scrollable page never reads as cut off, and fade when idle. Derived
	-- from the same interactionClasses fact as every other input adaptation,
	-- never from a device name.
	derived.scrollIndicatorPolicy = core:memo(function(use)
		local classes = use(derived.interactionClasses)
		local primary = if type(classes) == "table" then classes.primary else "pointer"
		return if primary == "pointer" then "always" else "auto"
	end)
	-- interactionClasses (ADR-0015): the LIVE interaction-class set derived
	-- from capabilities + preferredInput — never preferredInput alone. A
	-- single preferred value cannot describe a hybrid device (touch+gamepad
	-- handheld, desktop with a pad connected), and the engine fact can lag
	-- reality (director repro 2026-07-21: physical gamepad, PreferredInput
	-- stuck at KeyboardAndMouse). The preferred class is forced live even if
	-- its capability fact disagrees, so `primary` is always in the set.
	-- ten-foot presentation keys off the display class, not the input class:
	-- a console is Large + gamepad, but Large alone (any input) earns the
	-- distance treatment (type floor, overscan margins, focus visibility)
	derived.distanceProfile = core:memo(function(use)
		return if use(signals.displaySize) == "Large" then "ten-foot" else "near"
	end)
	-- effectiveOverscanInsets (director live find, Xbox emulator 2026-07-21):
	-- a TV-class display must never render edge-flush, so when the display is
	-- Large and no margins were AUTHORED the tvOS-equivalent defaults apply
	-- (60 top/bottom, 90 left/right at 1080p — the console-profile numbers).
	-- Authored values always win; the "none" sentinel opts out entirely.
	derived.effectiveOverscanInsets = core:memo(function(use)
		local authored = use(signals.overscanInsets)
		if authored == "none" then
			return { top = 0, bottom = 0, left = 0, right = 0 }
		end
		if type(authored) == "table" then
			local any = (authored.top or 0) ~= 0
				or (authored.bottom or 0) ~= 0
				or (authored.left or 0) ~= 0
				or (authored.right or 0) ~= 0
			if any then
				return authored
			end
		end
		if use(signals.displaySize) == "Large" then
			return { top = 60, bottom = 60, left = 90, right = 90 }
		end
		return { top = 0, bottom = 0, left = 0, right = 0 }
	end)
	--[[ THE PLATFORM'S OWN CHROME, AS RECTS RATHER THAN AS A BOUNDING BOX
		(ADR-0027; director 2026-08-14, "things at top that are aligned with the
		controls but don't overlap").

		`coreSafeInsets` says "the top 58px of this window belongs to the engine".
		That is true as a BOUNDING BOX and blunt as a fact: measured live on
		2026-08-14 (Studio, Play, showcase place, 735x413) the engine's own controls
		occupy x 0..164 of that band, and the rest of it — the strip
		`GuiService.TopbarInset` names — is explicitly the developer's. A surface
		that insets by the bounding box cannot put anything level with the
		platform's buttons, which is the top-centre row every shipped Roblox HUD
		has.

		So the same geometry is published a second way, in window space:

		  band        the FREE strip, or NIL. Never a zero rect at the origin: "no
		              strip" and "a strip at (0,0)" are the same table and opposite
		              instructions, and an engine without `GetInsetArea` publishes
		              zeroes (roblox_env's pcall belt), so the absence has to be
		              expressible.
		  rects       what the platform's OWN controls occupy — the top band MINUS
		              the free strip. A LIST, because the remainder of a band with a
		              strip in it is an L (or, on a notched landscape phone, two
		              rects), and that is exactly what an inset cannot say.
		  insets      clear EVERYTHING. Byte-identical to what `rootPolicy =
		              "deviceSafeContent"` applies (per-edge max of core and device,
		              plus the ten-foot overscan) — pinned against the live policy in
		              tests/adaptive.spec.luau, because a HUD riding the band is
		              inset by THIS number and a drift would be silent.
		  bandInsets  clear everything EXCEPT the free band, for a surface that
		              means to ride it: the same four edges with the top brought up
		              to where the band starts. Equal to `insets` when there is no
		              band, so a platform with no strip degrades to today's answer
		              and a consumer needs no branch.

		WHERE THE BAND COMES FROM, and why it intersects rather than adds.
		`topbarInset` and `topbarSafeInsets` are two encodings of ONE rect —
		measured live, `TopbarInset` = (164,0)+571x58 and the topbar-safe area = x
		164..735, y 0..58, the same band. (The earlier recorded belief that
		`TopbarInset` is stated relative to the topbar-safe area, so the two should
		be ADDED, was wrong: a probe Frame under a `ScreenInsets = None` ScreenGui
		placed at `TopbarInset.Min` lands exactly on the strip. The correction and
		its evidence are in tests/adaptive.spec.luau's DV3-1 header.) Intersecting
		them is therefore an identity on a healthy platform and a belt when one of
		them is missing or lying; adding them would double-count the cluster. The
		result is then clipped to the platform's own top band, so a strip reported
		outside it is no strip at all. ]]
	local function finite(v: any): number?
		return if type(v) == "number" and v == v and v > -math.huge and v < math.huge then v else nil
	end
	local function edgesOf(t: any): { top: number, bottom: number, left: number, right: number }
		local out = { top = 0, bottom = 0, left = 0, right = 0 }
		if type(t) == "table" then
			for _, edge in { "top", "bottom", "left", "right" } do
				out[edge] = math.max(0, finite((t :: any)[edge]) or 0)
			end
		end
		return out
	end
	derived.platformChrome = core:memo(function(use)
		local vp = use(signals.viewportRect)
		local W = math.max(0, finite(if type(vp) == "table" then vp.w else nil) or 0)
		local H = math.max(0, finite(if type(vp) == "table" then vp.h else nil) or 0)
		local coreI = edgesOf(use(signals.coreSafeInsets))
		local deviceI = edgesOf(use(signals.deviceSafeInsets))
		local safeI = edgesOf(use(signals.topbarSafeInsets))
		local bar = use(signals.topbarInset)
		local overscan = edgesOf(use(derived.effectiveOverscanInsets))
		local tenFoot = use(signals.displaySize) == "Large"

		local insets = {
			top = math.max(coreI.top, deviceI.top),
			bottom = math.max(coreI.bottom, deviceI.bottom),
			left = math.max(coreI.left, deviceI.left),
			right = math.max(coreI.right, deviceI.right),
		}
		if tenFoot then
			for _, edge in { "top", "bottom", "left", "right" } do
				insets[edge] += overscan[edge]
			end
		end

		-- the platform's own top band: full width, as tall as the CoreUI inset
		local bandH = math.min(coreI.top, H)
		local band: { x: number, y: number, w: number, h: number }? = nil
		if bandH > 0 and type(bar) == "table" then
			local bx, by = finite((bar :: any).x), finite((bar :: any).y)
			local bw, bh = finite((bar :: any).w), finite((bar :: any).h)
			if bx ~= nil and by ~= nil and bw ~= nil and bh ~= nil and bw > 0 and bh > 0 then
				local x0 = math.max(bx, safeI.left, 0)
				local y0 = math.max(by, safeI.top, 0)
				local x1 = math.min(bx + bw, W - safeI.right, W)
				local y1 = math.min(by + bh, H - safeI.bottom, bandH)
				if x1 - x0 > 0 and y1 - y0 > 0 then
					band = { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
				end
			end
		end

		--[[ THE APP'S OWN DECLARED CHROME, merged before the free band is reported.
			Same treatment the platform's cluster gets and for the same reason: a row
			that occupies part of the band takes that part OUT of the free strip, and
			the remainder is still a rect. A declared row that does not overlap the
			band vertically (the showcase's chip strip sits UNDER the platform's own
			58px row) narrows nothing — it is simply reported as occupied, which is
			what lets a consumer reserve around it per column. ]]
		local appRects: { { x: number, y: number, w: number, h: number } } = {}
		do
			local declared = use(signals.appChromeRects)
			if type(declared) == "table" then
				for _, r in declared :: any do
					if type(r) ~= "table" then
						continue
					end
					local rx, ry = finite((r :: any).x), finite((r :: any).y)
					local rw, rh = finite((r :: any).w), finite((r :: any).h)
					if rx == nil or ry == nil or rw == nil or rh == nil or rw <= 0 or rh <= 0 then
						continue
					end
					local x0, y0 = math.max(0, rx), math.max(0, ry)
					local x1, y1 = math.min(rx + rw, W), math.min(ry + rh, H)
					if x1 - x0 <= 0 or y1 - y0 <= 0 then
						continue
					end
					table.insert(appRects, { x = x0, y = y0, w = x1 - x0, h = y1 - y0 })
					-- and it narrows the free band where the two genuinely overlap
					if band ~= nil then
						local b = band :: any
						if y0 < b.y + b.h and y1 > b.y then
							if x0 <= b.x and x1 > b.x then
								local nx = math.min(x1, b.x + b.w)
								band = if b.x + b.w - nx > 0
									then { x = nx, y = b.y, w = b.x + b.w - nx, h = b.h }
									else nil
							elseif x1 >= b.x + b.w and x0 < b.x + b.w then
								band = if x0 - b.x > 0 then { x = b.x, y = b.y, w = x0 - b.x, h = b.h } else nil
							end
						end
					end
				end
			end
		end

		-- ...and the chrome is what is LEFT of that band, in reading order
		local rects: { { x: number, y: number, w: number, h: number } } = {}
		if bandH > 0 then
			if band == nil then
				table.insert(rects, { x = 0, y = 0, w = W, h = bandH })
			else
				local b = band :: any
				if b.y > 0 then
					table.insert(rects, { x = 0, y = 0, w = W, h = b.y })
				end
				if b.x > 0 then
					table.insert(rects, { x = 0, y = b.y, w = b.x, h = b.h })
				end
				if b.x + b.w < W then
					table.insert(rects, { x = b.x + b.w, y = b.y, w = W - (b.x + b.w), h = b.h })
				end
				if b.y + b.h < bandH then
					table.insert(rects, { x = 0, y = b.y + b.h, w = W, h = bandH - (b.y + b.h) })
				end
			end
		end

		-- the APP'S OWN DECLARED CHROME joins the platform's in the occupancy list,
		-- after it, so `rects` reads top-down in the order a viewer meets them
		for _, r in appRects do
			table.insert(rects, r)
		end

		local bandInsets = table.clone(insets)
		if band ~= nil then
			-- down to where the band starts, and never above the device-safe edge:
			-- a notch is not negotiable, and a platform that reported the band
			-- inside one must not be taken at its word about the pixels above it
			bandInsets.top = math.clamp(math.max(deviceI.top, (band :: any).y), 0, insets.top)
		end
		return table.freeze({
			band = if band ~= nil then table.freeze(band) else nil,
			rects = table.freeze(rects),
			insets = table.freeze(insets),
			bandInsets = table.freeze(bandInsets),
		})
	end)
	-- presentationProfile (ADR-0021): the derived half of presentationSpace.
	-- `flat` is what almost everything wants to know — a billboard is still a
	-- flat pixel canvas, it just lives in the world — and `world` is the narrow
	-- question only a future world target answers yes to. Unknown values clamp
	-- to "screen" rather than propagating: a broken platform fact must not
	-- silently put a menu in the world.
	derived.presentationProfile = core:memo(function(use)
		local raw = use(signals.presentationSpace)
		local space = if raw == "billboard" or raw == "world" then raw else "screen"
		return {
			space = space,
			flat = space ~= "world",
			world = space == "world",
		}
	end)
	derived.interactionClasses = core:memo(function(use)
		local caps = use(signals.capabilities)
		if type(caps) ~= "table" then
			caps = FACT_DEFAULTS.capabilities
		end
		local preferred = use(signals.preferredInput)
		local classes = {
			pointer = caps.mouse == true,
			touch = caps.touch == true,
			gamepad = caps.gamepad == true,
			keyboard = caps.keyboard == true,
			-- SPATIAL POINTING as a capability, not a mode (ADR-0021). A spatial
			-- session may have a controller ray, a tracked hand, a gaze and a
			-- gamepad live at once, so "VR" could never be one replacement for
			-- pointer/touch/keyboard/gamepad — it is one more thing that may be
			-- available. Nothing sets this capability today; it defaults false
			-- and is here so a future adapter adds a fact rather than a branch.
			spatialPointer = caps.spatialPointer == true,
			primary = "pointer",
		}
		if preferred == "Touch" then
			classes.touch = true
			classes.primary = "touch"
		elseif preferred == "Gamepad" then
			classes.gamepad = true
			classes.primary = "gamepad"
		else
			-- A PREFERENCE THE PLAYER HAS NOT EXPRESSED YET CANNOT OUTVOTE WHAT THE
			-- DEVICE PHYSICALLY IS (device report 2026-07-29, iPhone 15 Pro).
			--
			-- `UserInputService.PreferredInput` reports the most recently USED input,
			-- so a phone nobody has touched yet reads KeyboardAndMouse — the engine's
			-- default, not a fact. This branch used to take that at face value and
			-- make the surface pointer-primary, so a phone BOOTED INTO THE POINTER
			-- LAYOUT and reflowed to the touch one the instant a finger landed.
			-- Measured on the shipped playlist example: rows 36px -> 48px, page canvas
			-- 409 -> 553, and the native scrollbar thumb shrank by exactly that ratio
			-- — which is the "scrollbar looks very small" the report was about, and it
			-- was the layout BEFORE the touch that was wrong, not the one after.
			--
			-- So fall back to the class the device actually HAS, in the order a
			-- primary would be chosen if the player never expressed one. A mouse
			-- still wins outright, which keeps every desktop and every hybrid
			-- (touchscreen laptop) exactly where it was — a hybrid has a mouse, so
			-- the dense layout is still its default and the first touch still flips
			-- it. Only a device with NO pointer at all changes answer, which is the
			-- one case the old fallback could not have been right about.
			if caps.mouse == true then
				classes.pointer = true
				classes.primary = "pointer"
			elseif caps.touch == true then
				classes.primary = "touch"
			elseif caps.gamepad == true then
				classes.primary = "gamepad"
			else
				classes.pointer = true
				classes.primary = "pointer"
			end
		end
		return classes
	end)

	-- THE PREFERRED INPUT, RESOLVED (2026-07-29). `preferredInput` is the raw
	-- platform fact and it is only a REPORT OF THE LAST INPUT USED — before the
	-- player has touched anything it reads KeyboardAndMouse on a phone. Anything
	-- choosing an AFFORDANCE from it ("Press Enter" vs "Tap") therefore labelled a
	-- touchscreen with keyboard prompts until the first tap, which is the same
	-- defect that gave a phone the dense pointer row height (see interactionClasses
	-- above). This is the resolved answer in the platform fact's own vocabulary, so
	-- an existing consumer swaps one key for the other and nothing else moves.
	derived.effectiveInput = core:memo(function(use)
		local primary = (use(derived.interactionClasses) :: any).primary
		if primary == "touch" then
			return "Touch"
		elseif primary == "gamepad" then
			return "Gamepad"
		end
		return "KeyboardAndMouse"
	end)

	local env = {}

	function env.get(_self, key: string): any
		local readable = signals[key] or derived[key]
		assert(readable ~= nil, `unknown environment key '{key}'`)
		return readable
	end

	function env.set(_self, key: string, value: any)
		local signal = signals[key]
		assert(signal ~= nil, `cannot set unknown/derived environment key '{key}'`)
		--[[ THE ENGINE'S PLACEHOLDER VIEWPORT IS NOT A FACT (director clip
			2026-08-04, textpop.mov; boot watcher measured `vp=1x1` on the first
			client frame, the real size one frame later). A surface painted from
			the placeholder derives the wrong size class and visibly re-derives
			when the truth lands — the first-present size pop. Same boundary rule
			as `interactionClasses` ("an engine default the player never expressed
			cannot outvote what the device is"): a viewport write without two real
			>1px axes is REFUSED, the fact keeps its last real value, and the
			adapter's already-wired change signal delivers the true size within a
			frame — one atomic re-solve. Every legitimate viewport (the smallest
			emulated phone included) clears the bar by orders of magnitude. ]]
		if key == "viewportRect" then
			local w = if type(value) == "table" then tonumber(value.w) else nil
			local h = if type(value) == "table" then tonumber(value.h) else nil
			if w == nil or h == nil or w ~= w or h ~= h or w <= 1 or h <= 1 then
				return
			end
		end
		signal:set(value)
	end

	--[[ ONE REAL CHANGE IS ONE FACT-GROUP. An adapter almost never learns one
		environment fact at a time: `roblox_env.pushViewport()` learns SIX on a
		single resize (the viewport, three inset shapes, the topbar rect and the
		size class). Written one at a time each is its own flush, and every
		observer downstream — the renderer's re-solve above all — pays once per
		write for a change the player made once. Measured 2026-08-13 on a 40-row
		tree: six loose writes cost 5 solves, the same six inside one batch cost
		1 (tests/geometry_solve_coalescing.spec, L-27's "the lever for a resize
		is the solve COUNT, not the solve").

		This is the core's own transaction, not a second mechanism: writes inside
		are invisible to observers until the OUTERMOST batch closes, nested
		batches collapse into it, and memos stay glitch-free throughout. Group
		whatever one platform event taught you; do not group across events.

		TWO THINGS THIS IS NOT (RED-TEAM 2026-08-13, both probed). It is a
		GROUPING, NOT A ROLLBACK: a `body` that throws leaves the writes made
		before the throw published, and observers fire once for that partial
		group before the error is re-raised. And `body` MUST NOT YIELD — the
		transaction stays open across the yield, so every observer in the session
		waits, and an unrelated `env:set` made meanwhile is held with it. Neither
		is guarded here, because both guards would cost more than they buy on a
		path the adapter drives synchronously; they are stated so a caller can
		choose correctly. ]]
	function env.batch(_self, body: () -> ())
		core:transaction(body)
	end

	function env.keys(_self): { string }
		local out = {}
		for k in signals do
			table.insert(out, k)
		end
		for k in derived do
			table.insert(out, k)
		end
		table.sort(out)
		return out
	end

	return env :: any
end

return environment
