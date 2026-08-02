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
	--[[ …and WHERE that geometry lives, in window space. `topbarInset` is the
		platform's FREE topbar rect — the strip left over beside the engine's own
		control cluster — but its coordinates are stated relative to the
		TOPBAR-SAFE area, not the window, so on a notched device it cannot be
		placed without knowing where that area starts. That is this fact: the same
		four-edge shape as `coreSafeInsets`/`deviceSafeInsets`, measured from
		`GuiService:GetInsetArea(Enum.ScreenInsets.TopbarSafeInsets)`.

		A game that docks its own control into the platform's topbar row — beside
		the engine cluster, where a player already looks for chrome — needs both,
		and until this fact existed the second one could only be re-measured by
		hand through the engine, which is exactly the platform branch §6 forbids.
		Window-space free band = `{ x = topbarSafeInsets.left + topbarInset.x,
		y = topbarSafeInsets.top + topbarInset.y, w = topbarInset.w,
		h = topbarInset.h }`; present into it with `rootPolicy = "edgeToEdge"`,
		whose content rect IS window space. Zeroes on a platform that reports no
		topbar-safe area, which reads as "the strip starts at the window origin" —
		the desktop/no-notch answer, and the pre-adoption behaviour. ]]
	topbarSafeInsets = { top = 0, bottom = 0, left = 0, right = 0 },
	keyboardOcclusionRect = nil,
	preferredInput = "KeyboardAndMouse", -- Touch | Gamepad | KeyboardAndMouse
	capabilities = { keyboard = true, mouse = true, touch = false, gamepad = false },
	reducedMotion = false,
	preferredTextSize = 1, -- multiplicative reservation seam (tests/dev profiles)
	-- ADDITIVE preference reservation (platform verifier F1, 2026-07-23): the
	-- ENGINE applies PreferredTextSize as a FIXED PIXEL OFFSET (official
	-- text-scaling announcement), not a multiplier — so live reservation adds
	-- headroom in px. The multiplier fact above stays as the injectable
	-- test/profile seam (over-reserving via it is safe); the Roblox adapter
	-- populates THIS fact from the live enum and leaves the multiplier at 1.
	preferredTextOffset = 0,
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
	derived.typographyScale = core:memo(function(use)
		local raw = use(signals.preferredTextSize)
		local base = if type(raw) ~= "number" or raw ~= raw then 1 else math.clamp(raw, 0.5, 3)
		-- ten-foot type-scale floor (input-paradigms expansion, matrix D.1): body
		-- text must clear ~29pt at 3m, so a Large display class composes a 1.5x
		-- multiplier ON TOP of the accessibility preference (kept in its legal
		-- domain first). A near display leaves the preference untouched, so the
		-- corpus invariant typographyScale == preferredTextSize still holds.
		local floor = if use(signals.displaySize) == "Large" then 1.5 else 1
		return base * floor
	end)
	-- PAINT-seam scale (native-substrate NS-A9, corrections §9): the ENGINE
	-- applies the player's PreferredTextSize in its own font pipeline
	-- (accessibility doc, grounded 2026-07-23), so LuauUI must not multiply it
	-- into the painted TextSize again — that is the double-application defect.
	-- Paint carries ONLY authored scale (the ten-foot floor). MEASUREMENT
	-- (typographyScale above) keeps the preference factor so the solver
	-- RESERVES the engine-scaled bounds; the two seams differ by exactly the
	-- engine-owned factor, and measured-vs-painted agreement is the engine's
	-- own application of that factor at draw time.
	derived.typographyPaintScale = core:memo(function(use)
		return if use(signals.displaySize) == "Large" then 1.5 else 1
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
		signal:set(value)
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
