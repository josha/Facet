--!strict
-- ScreenTarget (design §13; CLIENT-ONLY — the only module that reaches engine
-- Instances for rendering, per ADR-0003's seam rule; check_boundary enforces
-- that non-client code never requires this). Implements the same
-- RenderTargetAdapter interface as tests/lib/fake_target: createRoot/create/
-- setRect/setProp/remove/destroyRoot (+ setActivateHandler/setFocusVisual/
-- getInstance). Renders under PlayerGui with ZIndexBehavior=Sibling and
-- IgnoreGuiInset=true: Facet solves insets itself (§8.1).
--
-- STYLE: applies the "Studio Neutral" default style (src/tokens/default_style)
-- or a game-compiled override passed via new({ style = ... }). All visual
-- writes here are the STYLE authority (design §7.3): surfaces, radii,
-- hairlines, state colors, focus ring, motion. Data writes (text/value/
-- enabled) remain the binding authority in setProp. Motion honors reduced
-- motion through `adapter.setReducedMotion`, which the RENDERER pushes from the
-- environment's `reducedMotion` fact at attach and on every change (C1,
-- 2026-08-12) — no consumer wiring, and live for a mid-session flip. The legacy
-- `opts.isReducedMotion` closure still forces reduced motion on if a caller
-- passes one (deprecated, never removed: ADR-0011), but nothing has to.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local CollectionService = game:GetService("CollectionService")

local defaultStyle = require("../tokens/default_style")
local defaultLightStyle = require("../tokens/default_light_style")
local sheet_model = require("../tokens/sheet_model")
local chrome_slots = require("../tokens/chrome_slots")
-- the PURE package library: `resolveIcon` is the one icon-resolution ruling and
-- this file is its application site (ADR-0020 R4)
local themePackage = require("../themes/package")
local themeSnapshot = require("../themes/snapshot")
local styling = require("../tokens/styling")
local native_style = require("./native_style")
-- the chrome/decoration materializer, extracted from this file (Studio's
-- 200_000-byte `Source` ceiling). Strictly one-way: it never requires back.
local screen_chrome = require("./screen_chrome")
-- the scroll host's region/position writes and the indicator driver, extracted
-- for the same ceiling. Also strictly one-way.
local screen_scroll_indicators = require("./screen_scroll_indicators")
-- the bespoke (non-native) paint vocabulary — the sibling of screen_chrome,
-- extracted for the same ceiling. Also strictly one-way.
local screen_paint = require("./screen_paint")
-- the presentation channel (ADR-0022 Decision 2) and the clip-host record it
-- composes against — see that module's header for why the seam is here
local screen_presentation = require("./screen_presentation")
-- the pointer seam: the one activate meta, the global capture, the semantic
-- cursor and the connection census that reports what they hold
local screen_pointer = require("./screen_pointer")
local text_premeasure = require("./text_premeasure")
local authority = require("../render/authority")
-- the PURE rulings the UI.Stage content seam is made of (camera/lighting shapes,
-- the dead-handle refusal). Shared with the headless twin so the two adapters
-- cannot disagree about what the seam accepts.
local stage_content = require("../render/stage_content")
-- ...and the FOREIGN content seam's ruling ladder (UI.Foreign, ADR-0034), for
-- exactly the same reason: one refusal ladder, both adapters
local foreign_content = require("../render/foreign_content")

--[[ THE ENGINE CHARGES FOR THIS BAR, ALWAYS. A `ScrollingFrame`'s VISIBLE window
	is narrower than its own frame by this thickness on the cross axis whenever the
	scroll axis overflows — even at `ScrollBarInset.None` — and the indicator POLICY
	cannot change that: the policy only fades the bar's IMAGE. So the solver reserves
	it off the cross axis under every policy, and the number is one value shared by
	both seams (`adapter.scrollBarThickness`, published below and again in
	`setScrollIndicatorPolicy` — now in src/client/screen_scroll_indicators, which
	is handed this constant — and `tests/lib/fake_target.luau`'s lockstep copy). ]]
local SCROLL_BAR_THICKNESS = 8
-- The scroll indicator POLICY (and its "auto" flash/fade driver) now lives in
-- src/client/screen_scroll_indicators, together with the ruling that explains
-- why the policy paints the bar but never moves the reserve above.

-- `textAlign` (director review 2026-07-24). Absent means Left, which is what the
-- adapter hard-coded before the prop existed, so every existing screen is
-- unchanged.
local TEXT_ALIGN_MAP: { [string]: Enum.TextXAlignment } = {
	start = Enum.TextXAlignment.Left,
	center = Enum.TextXAlignment.Center,
	["end"] = Enum.TextXAlignment.Right,
}

-- THE ENGINE FACE FOR A TYPOGRAPHY-ROLE DESCRIPTOR (F2, 2026-08-02).
--
-- `text_premeasure.fontFor` is the SAME resolver the premeasure batch hands to
-- `GetTextBoundsAsync`, keyed on the same canonical "family#weight#style"
-- descriptor (ADR-0019 §6). So the face the engine DRAWS and the face the engine
-- was asked to MEASURE are one cached lookup, not two parallel mappings that can
-- drift — which is the failure `Text.font` was deprecated for. An unresolvable
-- family returns nil and the node keeps the face it already has.
local function fontFaceFor(descriptor: any): Font?
	if type(descriptor) ~= "table" or type(descriptor.fontKey) ~= "string" then
		return nil
	end
	return text_premeasure.fontFor(descriptor.fontKey)
end

-- authored `scaleMode` -> engine ScaleType (ADR-0022 Decision 6).
--
-- `fill` and `crop` BOTH map to Crop, and that is deliberate rather than a
-- collision: Roblox's `Crop` IS the cover behaviour every other UI vocabulary
-- calls "fill" (preserve the aspect ratio, let the overflow be cropped), and an
-- author arriving from either vocabulary should not have to look it up. `slice`
-- is absent because nine-slice geometry is theme-owned chrome.
--
-- Mirrored headlessly by tests/lib/fake_target's SCALE_MODE_ENGINE_NAME so the
-- mapping is provable without an engine — keep the two in lockstep, exactly as
-- KEYBOARD_TYPE_ENGINE_NAME is.
local SCALE_MODE_ENGINE: { [string]: Enum.ScaleType } = {
	fit = Enum.ScaleType.Fit,
	fill = Enum.ScaleType.Crop,
	crop = Enum.ScaleType.Crop,
	stretch = Enum.ScaleType.Stretch,
}

-- props whose own write repaints a property the `tint` channel may have claimed
-- (see the tail of setProp)
local TINT_REPAINTING_PROPS: { [string]: boolean } =
	{ surface = true, role = true, selected = true, enabled = true, value = true }

local screen_target = {}

local CLASS_TO_INSTANCE: { [string]: string } = {
	Text = "TextLabel",
	Button = "TextButton",
	Toggle = "TextButton",
	Image = "ImageLabel",
	TextField = "TextBox", -- §17 Phase 5 (UI.TextInput): the only engine text-entry instance
	ScrollView = "ScrollingFrame", -- native scroll host; opts.forceScrollFallback keeps a Frame
	-- the engine-content box (ViewportFrame adoption 2026-08-08): a GuiObject that
	-- renders its own scene. The adapter also creates and owns the WorldModel the
	-- content lives in and the Camera the frame renders through — see buildHandle.
	Stage = "ViewportFrame",
	-- Path renders as a transparent Frame holder + child Path2D
	-- containers and everything else render as Frames
}

-- the instances the stage seam owns, named from one place so the adapter and any
-- probe reading the Explorer agree
local STAGE_WORLD_NAME = "FacetStageWorld"
local STAGE_CAMERA_NAME = "FacetStageCamera"

-- THE ONE WRITER for a seam-owned engine property (render/authority.luau's
-- SEAM_OWNED: Ambient, LightColor, LightDirection, CurrentCamera). It writes by
-- INDEX rather than by field name, so a dotted assignment to any of the four
-- appears NOWHERE in this adapter — which turns "a bespoke write defeated the
-- seam" into a literal tests/stage.spec.luau pins at zero, the same way the paint
-- gate turns a sheet-defeating write into a loud error. Every call site is inside
-- the stage seam, so `bySeam` is true here and false everywhere the gate is asked
-- from outside it.
local function writeStageProp(instance: Instance, engineProp: string, value: any)
	authority.assertSeamWrite(engineProp, true);
	(instance :: any)[engineProp] = value
end

-- a stage node's seam going dead, spelled once because two teardown paths need it
-- (`remove` and `destroyRoot`). The instances themselves are children of the frame
-- and die with it; this is what makes a handle a consumer still holds REFUSE
-- instead of writing into the corpse.
local function markStageDisposed(handle: any)
	if handle == nil or handle.stageWorld == nil then
		return
	end
	handle.stageDisposed = true
	handle.stageWorld = nil
	handle.stageCamera = nil
	handle.stageApi = nil
end

-- ...and the same thing for a FOREIGN box (ADR-0034). There is nothing to tear
-- down — whatever the caller adopted is a child of the container and dies with
-- it, exactly as they were told it would — so this is purely the HANDLE going
-- dead, which is what turns a consumer's stale `adopt` from a write into a
-- destroyed instance (silent) into a refusal that names the node (loud).
local function markForeignDisposed(handle: any)
	if handle == nil or handle.foreignBox == nil then
		return
	end
	handle.foreignDisposed = true
	handle.foreignApi = nil
end

local function toColor3(c: any): Color3
	return Color3.new(c.r, c.g, c.b)
end

export type Opts = {
	style: any?,
	--[[ AUTOLOCALIZE — default `true`, which is Roblox's own default and keeps
		`LocalizationTable` translation working. Pass `false` ONLY if this
		experience does not localize.

		WHY IT IS AN OPTION AND NOT A DEFAULT, corrected 2026-08-13 after the
		game director's ruling: *"we do want to localize text."* The first cut of
		this shipped `AutoLocalize = false` unconditionally, on the strength of a
		device measurement, and that was the wrong call — it bought frame time by
		silently removing a capability the game wants.

		THE MEASUREMENT IS REAL AND IS WHY THE OPTION EXISTS (Galaxy A10e, the
		first MicroProfiler capture ever to contain Facet's solver scopes,
		2026-08-13): `LocalizationService::attemptLocalization` ran 64 times for
		39.54 ms, parented to `Facet/mount` in ALL 64 cases — 25.1% of `mount`
		and 8.9% of all Facet CPU, at 0.6178 ms per call. **55% of that is
		`Stat::send` telemetry**, not translation.

		So a game that localizes pays ~0.62 ms per text instance materialised on
		that class of hardware, and a game that does not can now decline it in one
		place instead of paying for a lookup that can never hit. Stated here so the
		choice is informed rather than invisible. ]]
	autoLocalize: boolean?,
	--[[ DEPRECATED (C1, 2026-08-12) — do not reach for this in new code, and
		nothing has to pass it any more. Reduced motion arrives on its own through
		`adapter.setReducedMotion`, which the renderer pushes from the environment
		at attach and on every change.

		Declared in `Facet.DEPRECATIONS` as `screen_target.new(opts.isReducedMotion)`
		(since 0.9.0, remove no earlier than 0.10.0) — prose in two places and no
		ledger row was the Milestone-1 review's C3.

		Why it is deprecated rather than removed (ADR-0011): it is public, it is
		documented, `billboard_target` forwards it, and a harness that wants to
		FORCE reduced motion regardless of the environment still has a use for it.
		It is now an OR with the pushed fact — a closure returning true still wins,
		a closure returning false no longer overrides a player who asked for
		reduced motion. That last part is the bug it caused: it defaulted to
		`function() return false end` and every production caller took the default,
		so the setting reached nothing. ]]
	isReducedMotion: (() -> boolean)?,
	parent: Instance?,
	-- root override (ADR-0009): everything below the root is target-agnostic
	-- flat instance rendering, so BillboardTarget swaps ONLY the root — the
	-- factory returns { gui = <the container all nodes parent under> }
	rootFactory: ((screenId: string) -> { gui: Instance })?,
	-- the native substrate/the native substrate: render ScrollView nodes as plain Frame clip
	-- hosts (no engine scrolling). Billboard targets set this until proven;
	-- the gallery sets it from the Facet_ForceScrollFallback attribute so the
	-- fallback path is exercised separately in Studio (never only headlessly).
	forceScrollFallback: boolean?,
	-- the native substrate/the native substrate: force setDragDetector to return nil so the
	-- raw pointer-capture fallback is exercised separately (A/B evidence runs)
	forceDragFallback: boolean?,
	-- native-stylesheets stage (plan §7 Phase 2): native paint, and THE DEFAULT
	-- since 2026-08-21 (ADR-0040 B-15). When the engine has StyleSheets, the
	-- adapter stops
	-- explicit-writing every handed-off style property and instead CLASSIFIES
	-- nodes (class + facet-* tags, sheet_model.classifyTags) under one
	-- StyleLink per root; the DataModel sheet (seed-once, native_style.ensure)
	-- owns fills, chrome, text paint, and interaction-state paint. An explicit
	-- `false` — or an engine without StyleSheets — takes the explicit-write path
	-- below, unchanged (the native stylesheets work
	-- fallback parity). `true` builds the built-in Dark+Light model; a table
	-- passes { model | handle, host, theme }.
	-- table form also takes `transitions = true` to opt into sheet transitions
	-- (progressive enhancement; default OFF until the native stylesheets work publish rider clears)
	nativeStyle: (boolean | { model: any?, handle: any?, host: Instance?, theme: string?, transitions: boolean? })?,
	-- theme-packages stage (ADR-0019 §5): the installed ThemePackage whose
	-- chrome recipes decide DECORATION SLOTS. A package whose slots are all
	-- native — every reference package except an asset-backed one — creates
	-- zero instances, so this is free to leave unset. The theme controller
	-- swaps it at runtime through `adapter.setThemePackage`.
	themePackage: any?,
	--[[ WHERE THIS TARGET'S ROOTS SIT AGAINST THE GAME'S OWN `ScreenGui`s.
		Every root this target creates gets this
		`DisplayOrder`; the presenter still layers its OWN surfaces above one
		another with `adapter.setRootDisplayOrder`, so this is the FLOOR the whole
		target stands on, not a per-surface number.

		WHY IT HAS TO BE STATEABLE. Roots were created with `DisplayOrder` unset,
		which is 0, and the audit counted seventeen hand-made game `ScreenGui`s
		carrying scattered magic numbers between 90 and 100 — so every native game
		surface floated above every Facet surface by default, and no one had
		decided that; it was discovered. Absent still means 0, so nothing moves
		unless a consumer says where it wants to be. ]]
	displayOrder: number?,
	-- THE DISPLAY CLASS THIS TARGET PAINTS FOR: at ten-foot the paint family
	-- (radii, strokes) scales — see `themes/snapshot.paintForDisplay`. `host`
	-- passes the environment's fact; absent is near, the identity. Taken at
	-- construction, like the palette (ADR-0040 B-17).
	displaySize: string?,
}

function screen_target.new(opts: Opts?)
	-- the AUTHORED style is kept by identity (the built-in Light theme is keyed
	-- on it); `style` is that style AS PAINTED at this distance
	local baseStyle: any = (opts and opts.style) or defaultStyle
	local displaySize: any = opts and (opts :: any).displaySize
	local style: any = themeSnapshot.paintForDisplay(baseStyle, displaySize)
	-- default TRUE: Roblox's own default, and the director's ruling is that this
	-- experience localizes. `false` is an explicit opt-out for one that does not.
	local autoLocalize: boolean = not (opts ~= nil and opts.autoLocalize == false)
	-- REUSE-122: absent stays 0 (the engine's own default), so no existing
	-- consumer's layering moves
	local baseDisplayOrder: number? = opts and opts.displayOrder
	--[[ THE LIVE REDUCED-MOTION FACT (C1, 2026-08-12). Every bespoke tween in this
		file asks `isReducedMotion()`; what changed is where the answer comes from.

		It used to come ONLY from `opts.isReducedMotion`, a construction-time
		closure defaulting to "no". No production caller anywhere passed one — not
		the showcase, not RascalRally's four Facet GUIs — so the player's setting
		reached none of these tweens, on any surface, ever.

		Now the RENDERER pushes the environment fact into `adapter.setReducedMotion`
		at attach and again on every change (renderer.luau, beside
		`setNativeTransitionsEnabled`), so the fact arrives with no consumer wiring
		and stays live if the player flips the setting mid-session. The legacy
		closure is OR'd in rather than dropped (ADR-0011 deprecate-not-break): a
		caller that passes one can still force reduced motion on, and one that
		returns false can no longer override the player. ]]
	local reducedMotionPushed = false
	local isReducedMotionOpt = opts and opts.isReducedMotion
	local function isReducedMotion(): boolean
		return reducedMotionPushed or (isReducedMotionOpt ~= nil and isReducedMotionOpt() == true)
	end
	-- parent override (ws2 Edit-mode preview): Studio Edit has no LocalPlayer,
	-- so the preview harness hands us an explicit host instead of PlayerGui
	local playerGui = (opts and opts.parent) or Players.LocalPlayer:WaitForChild("PlayerGui")
	local adapter = {}
	local instancesByPath: { [string]: Instance } = {}

	-- Burn the engine's text boot window NOW, while the game is still loading
	-- and no UI exists (text-measurement milestone). The engine's bounds API
	-- answers wrongly-but-stably for the first seconds of a session; settling it
	-- once here means every later measurement is trusted on its first read, so
	-- no screen ever pays a delayed correction reflow. Idempotent and
	-- non-blocking — build your adapter early and this is free.
	text_premeasure.warmUp()

	-- The renderer feeds this into solver.solve so a scrolling region lays its
	-- content out INSIDE the bar rather than underneath it. Zero on the fallback
	-- path, where a plain Frame host draws no bar at all.
	local forceScrollFallbackMode = opts ~= nil and (opts :: any).forceScrollFallback == true
	adapter.scrollBarThickness = if forceScrollFallbackMode then 0 else SCROLL_BAR_THICKNESS
	-- scroll indicator state. SHARED BY REFERENCE with the driver in
	-- src/client/screen_scroll_indicators (which owns the policy from here on);
	-- it lives HERE because the create path below reads `.policy` at instance
	-- birth, to decide whether a new ScrollingFrame is born with its bar hidden.
	local scrollIndicatorState = { policy = "always", reduced = false }

	-- native paint: `paintPlan` IS the decision (the default, the capability gate,
	-- the escape hatch, the transitions seed) and this closure OBEYS it rather
	-- than re-deriving it — the only way a module nothing can require headlessly
	-- gets a witness for any of it (ADR-0040 B-15).
	local nativeHandle: any = nil
	do
		local plan = native_style.paintPlan(opts and (opts :: any).nativeStyle, isReducedMotion)
		local nativeOpt: any = plan.opt
		if plan.native then
			if type(nativeOpt) == "table" and nativeOpt.handle ~= nil then
				nativeHandle = nativeOpt.handle
			else
				local model = (type(nativeOpt) == "table" and nativeOpt.model) or nil
				if model == nil then
					-- built-in model: the passed style is the default theme; the
					-- built-in Light theme ships only when running Studio Neutral
					-- (a game style carries no light variant to derive)
					local themes = { { name = "Dark", style = baseStyle } }
					if baseStyle == defaultStyle then
						table.insert(themes, { name = "Light", style = defaultLightStyle })
					end
					-- authored styles in, class beside them: one derivation
					model = sheet_model.build({ themes = themes, displaySize = displaySize })
				end
				-- transitions are progressive-enhancement OPT-IN (the native stylesheets work rider:
				-- publish status unconfirmed; default = instant change), and
				-- reduced motion always wins over the opt. This is CONSTRUCTION
				-- time, before the renderer has pushed anything, so it can only
				-- see a legacy `opts.isReducedMotion`; the live fact lands a
				-- moment later through `setNativeTransitionsEnabled`, which the
				-- renderer calls at attach (C1) — so the seed is never the last
				-- word, only the value for the frames before a surface attaches.
				nativeHandle = native_style.ensure(model, {
					host = plan.host,
					theme = plan.theme,
					transitionsEnabled = plan.transitions,
				})
			end
		end
	end
	local nativeMode = nativeHandle ~= nil

	-- ===== PAINT CLAIMS (ADR-0022 Decision 6) =============================
	--
	-- An authored continuous value — a `tint` blend, an identity hue, an Image's
	-- `scaleMode` — is data, and no rule can see data. So the node CLAIMS that
	-- engine property from the sheet: the write happens, the engine's defeat of the
	-- rule is INTENTIONAL, and the claim is recorded so the defeat-detection
	-- instrument (`GetStyled` versus the sheet-resolved value) reads a declared
	-- hand-off instead of tripping on it. Without the record the audit could not
	-- tell this apart from the accidental write it exists to catch.
	--
	-- THE CLAIM DOES NOT STRIP THE NODE'S TAGS, deliberately, and this is where
	-- this implementation departs from ADR-0022's sketch ("strips the paint-family
	-- tag for that property"). A surface tag does not carry one property: it carries
	-- the fill AND the phantom ::UICorner radius AND the ::UIStroke hairline AND the
	-- :Hover/:Press states. Removing it to hand over a colour would silently take
	-- away chrome the author never mentioned, and the engine already gives the
	-- explicit write the win — permanently, for that property, on that instance
	-- (spike m10). So the tag stays, everything the tint did not claim keeps its
	-- rule, and the claim is the audit trail.
	--
	-- TWO CONSEQUENCES, both documented in the reference:
	--   * a claim is permanent for the instance's lifetime. Releasing a tint
	--     restores the value recorded at claim time; it does NOT give ownership back
	--     to the sheet, because the engine has no such operation.
	--   * a claimed property no longer follows a theme swap. That is the price of a
	--     continuous channel and the reason finite states must stay on tags.
	local CLAIM_ATTRIBUTE = "Facet_PaintClaims"

	-- the per-control sensory verb's attribute name. Kept identical to
	-- `src/client/haptics.luau`'s `ACTIVATION_ATTRIBUTE` and pinned equal by
	-- tests/control_feedback.spec.luau, because the two ends of a string-keyed
	-- channel that drift apart fail as silence rather than as an error.
	local ACTIVATION_FEEDBACK_ATTRIBUTE = "Facet_ActivationFeedback"

	-- the value the sheet (or the bespoke path) had on this property when the claim
	-- was taken. `GetStyled` is the instrument in native mode: a plain read is blind
	-- to a rule-owned value. Read BEFORE the first claimed write, which is the only
	-- moment it is still true.
	local function styledValue(instance: Instance, engineProp: string): any
		if nativeMode then
			local ok, resolved = pcall(function()
				return (instance :: any):GetStyled(engineProp)
			end)
			if ok then
				return resolved
			end
		end
		local ok, plain = pcall(function()
			return (instance :: any)[engineProp]
		end)
		return if ok then plain else nil
	end

	local function claimPaint(handle: any, engineProp: string)
		local claims = handle.paintClaims
		if claims == nil then
			claims = {}
			handle.paintClaims = claims
			handle.paintRestore = {}
		end
		if claims[engineProp] then
			return
		end
		claims[engineProp] = true
		handle.paintRestore[engineProp] = styledValue(handle.instance, engineProp)
		-- the DUMP channel: an attribute, so the scenario runner's node dump reports
		-- the claim beside the GetStyled reading it explains, without the runner
		-- needing a new adapter seam
		local names: { string } = {}
		for prop in claims do
			table.insert(names, prop)
		end
		table.sort(names)
		handle.instance:SetAttribute(CLAIM_ATTRIBUTE, table.concat(names, ","))
	end

	-- restore a claimed property to the value recorded when the claim was taken
	-- (a released tint, a cleared scaleMode). The claim itself stays: see above.
	local function restorePaint(handle: any, engineProp: string)
		local recorded = if handle.paintRestore ~= nil then handle.paintRestore[engineProp] else nil
		if recorded == nil then
			return
		end
		pcall(function()
			(handle.instance :: any)[engineProp] = recorded
		end)
	end

	-- CENTRAL native-authority gate (arch verifier 2026-07-24): every
	-- bespoke paint path calls this before writing a sheet-ownable engine
	-- property. In native mode such a write would silently and permanently
	-- defeat the rule (spike m10) — so a missed `if not nativeMode` guard is a
	-- LOUD error here, never a silent dual authority. The toggle knob-track
	-- assembly's chrome instances ride the "Toggle chrome" tag rule for
	-- opacity and untargeted color writes for value state, so nothing there
	-- routes through this gate either.
	--
	-- `handle` is optional and carries the CLAIMS above: a property the node
	-- declared it owns is expected to diverge from the sheet, so the gate lets it
	-- through — and only that property, only on that node.
	local function assertBespokePaint(engineProp: string, handle: any?)
		if nativeMode and authority.nativeSheetOwned(engineProp) then
			if
				type(handle) == "table"
				and type(handle.paintClaims) == "table"
				and handle.paintClaims[engineProp] == true
			then
				return
			end
			error(`Facet native-style: bespoke write to sheet-owned {engineProp} in native mode`, 0)
		end
	end

	-- tag synchronization: the ONLY channel by which Facet state reaches
	-- native selectors (corrections §5 — GuiState is read-only; app state is
	-- tags). Desired set computed by the PURE sheet_model.classifyTags.
	local function syncTags(handle: any)
		if not nativeMode then
			return
		end
		local instance = handle.instance
		local desired = sheet_model.classifyTags({
			surface = handle.nativeSurface,
			selected = handle.isSelected == true,
			roleSecondary = handle.nativeRoleSecondary == true,
			strong = handle.nativeStrong == true,
			interactive = handle.nativeInteractive == true,
			-- the engine-selection bridge suppresses the hover gate while it
			-- owns the node (engine selection reports GuiState=Hover, m9)
			pointerLive = handle.nativePointerLive == true and handle.nativeBridgeSelected ~= true,
			gripFocus = handle.nativeGripFocus == true,
			-- THE TINTED FILL (director report 2026-08-15). Set by `applyTint`'s
			-- GuiObject branch only — a Text/Image tint claims a colour the class
			-- default already paints and must NOT gain a background. It rides the
			-- desired set like every other classification tag, or the next pass
			-- would strip the fill and the node would go invisible again.
			tinted = handle.tintFill == true,
			divider = handle.nativeDivider == true,
			buttonRole = handle.nativeButtonRole,
			-- the skinned-slot tag rides the SAME desired set as every other
			-- classification tag: computed here, it survives the diff below.
			-- Added by syncChrome (which sets handle.chromeSlot) and removed the
			-- moment the decoration goes away.
			skinnedSlot = handle.chromeSlot,
			-- the SLOT IDENTITY tag, which unlike the one above does not depend
			-- on the package skinning anything: it is what gives a value
			-- control's chrome its own native paint instead of borrowing a
			-- public surface's (and its gradient's alpha with it)
			slotHint = if type(handle.decorationHint) == "table" then handle.decorationHint.slot else nil,
			-- THE SIXTH VARIANT STATE (ADR-0020 R2). `error` has no engine
			-- GuiState, so it is a tag — and it has to ride the desired set or
			-- the next classification pass would strip it.
			errorState = handle.errorState == true,
			-- THE LAYERED EDITING YIELD (ADR-0020 R1, rs-m2). One tag on the
			-- DECORATED NODE; the package's child-combinator rules blank every
			-- layer. Same reason it lives here: syncTags owns every facet-* tag
			-- on this instance and diffs the rest away.
			chromeYield = handle.chromeYield == true,
			-- THE SWITCH'S VALUE (ADR-0020 R3 cap 10). `on` is neither a GuiState
			-- nor a selection binding, so the package's toggle art reads it from a
			-- tag — and that tag has to ride the desired set or the next
			-- classification pass would strip it, which is the Step 3.5 defect
			-- class one control down.
			toggleOn = handle.toggleOn == true,
			-- SEMANTIC ICON ART (ADR-0020 R4). The glyph suppression is a tag
			-- because TextTransparency is sheet-owned in native mode — and it
			-- rides the desired set here so a later classification pass cannot
			-- strip it and bring a "+" back on top of the plate art.
			iconArt = handle.iconArt == true,
			-- THE SILHOUETTE (feature round 2026-07-26). A circle Button's pill
			-- radius and rim are phantom ::UICorner/::UIStroke rules, so the disc
			-- costs a flat theme zero instances — and the tag has to ride the
			-- desired set or the next classification pass would square it off.
			shape = handle.shape,
			-- THE TYPOGRAPHY ROLE (F2, 2026-08-02). `FontFace` is sheet-owned, so
			-- the role a node wears reaches native paint as a tag whose generated
			-- rule carries that role's descriptor — the same descriptor the solver
			-- measured with. It rides the desired set like every other
			-- classification tag, or the next pass would strip the face back to the
			-- class default.
			typeRole = handle.typeRole,
		})
		for _, tag in CollectionService:GetTags(instance) do
			if string.sub(tag, 1, 5) == "facet-" and desired[tag] ~= true then
				CollectionService:RemoveTag(instance, tag)
			end
		end
		for tag in desired do
			if not CollectionService:HasTag(instance, tag) then
				CollectionService:AddTag(instance, tag)
			end
		end
	end

	-- §17 Phase 4 engine styling: capability detection with headless/old-
	-- engine fallback (Lune reflection knows neither UIShadow nor per-corner
	-- radii — docs/research/2026-07-20-uishadow-percorner-engine-facts.md)
	local hasUIShadow = (function(): boolean
		return (pcall(function()
			local probe = Instance.new("UIShadow" :: any)
			probe:Destroy()
		end))
	end)()
	-- the fade group's engine class (ADR-0022 Decision 2), probed the same way: an
	-- engine without it renders the node as a Frame and the group does not fade,
	-- which is a degraded visual and never a crash.
	local hasCanvasGroup = (function(): boolean
		return (pcall(function()
			local probe = Instance.new("CanvasGroup" :: any)
			probe:Destroy()
		end))
	end)()
	-- the engine-content box's three classes, probed as ONE capability (UI.Stage): a
	-- ViewportFrame without a WorldModel to hold the content or a Camera to render
	-- through is not a stage. An engine missing any of them renders the node as an
	-- ordinary Frame and `stageHost` answers nil — the documented fallback, so an
	-- author gates on the nil or presents a plate. Never a crash.
	local hasStage = (function(): boolean
		return (
			pcall(function()
				for _, className in { "ViewportFrame", "WorldModel", "Camera" } do
					local probe = Instance.new(className :: any)
					probe:Destroy()
				end
			end)
		)
	end)()
	local hasPerCornerRadii = (function(): boolean
		return (
			pcall(function()
				local probe = Instance.new("UICorner")
				local _ = (probe :: any).TopLeftRadius
				probe:Destroy()
			end)
		)
	end)()
	-- HOISTED above the decoration section on purpose: the slot-shadow
	-- materializer below needs `hasUIShadow`, and a local declared later is not
	-- an upvalue there (docs/lessons/ — this exact shape has bitten before).

	-- ===== DECORATION SLOTS / CHROME =====================================
	-- The whole materializer — decoration slots, semantic icons, the chrome text
	-- lift, slot shadows, layer stacks, the bar assembly, toggle art and the
	-- rung-2 per-view override — lives in the sibling `screen_chrome`, extracted
	-- verbatim when this file reached Studio's 200_000-byte `Source` ceiling.
	-- Only the state the REST of this target also reads stays here.
	local chromeState = chrome_slots.newState(opts and (opts :: any).themePackage)
	local handlesByPath: { [string]: any } = {}
	-- THE COMMITTED SNAPSHOT (ADR-0020 R4). The adapter needs metric values for
	-- exactly one thing: the px an icon draws at, which rides `iconSizes` so a
	-- metric package resizes icons. It arrives from the controller INSIDE the
	-- swap transaction, beside the package, rather than being read back out of
	-- the environment — the same reason `themeName` rides along, so there is no
	-- frame in which the package and the metrics that describe it disagree.
	local activeThemeSnapshot: any = nil
	-- the live focus set, hoisted above `syncChrome`: the chrome sync re-places a
	-- focused node's ring when its art appears or disappears, and a local declared
	-- later is not an upvalue (this file has been bitten by that twice).
	local focusedHandles: { [any]: string? } = {}

	-- ===== THE FOCUS TREATMENT (director review 2026-07-25) ================
	--
	-- "In parchment, the blue selection ring for the stepper looks bad. Let's
	-- make selection a glow."
	--
	-- TWO defects, stacked. (1) The ring painted itself from a STATIC accent
	-- constant captured at construction, so it stayed Studio-Neutral blue no
	-- matter which package was installed — a real theme-blindness bug quite apart
	-- from the glow. (2) A hairline ring is the wrong IDIOM under an ornate skin,
	-- where every other edge is soft and painted.
	--
	-- Both are fixed here. The COLOUR now comes from the active theme (resolved
	-- by the pure `chrome_slots.resolveFocusColor` against that theme's palette),
	-- and a package may ask for `kind = "glow"` instead of `kind = "ring"`.
	--
	-- A GLOW IS A `UIShadow` AT A HIGH BlurRadius WITH NO OFFSET. Roblox has no
	-- glow element, but this measures as one (live probe: BlurRadius 30 at
	-- Transparency 0 is an unmistakable halo). Doing it with ART instead would
	-- need an asset pipeline per theme, a fixed colour baked per asset, and a
	-- nine-sliced radial gradient whose falloff BANDS on stretched edges at sizes
	-- the author never tried. Shaped selection art stays the `selection`
	-- decoration slot's job.
	--
	-- AUTHORITY. Same note as the slot shadows: `::UIShadow` rules are silently
	-- accepted and paint nothing (m7) and the package compiler rejects the
	-- selector, so there is no rule for this to defeat. It is deliberately
	-- adapter-owned paint. The glow is in fact SAFER than the ring in native
	-- mode — a real `UIStroke` child (the ring) defeats a node's phantom
	-- `::UIStroke` modifier for as long as it exists, and a `UIShadow` child
	-- collides with nothing.
	local focusTreatment: any = { kind = "ring", color = nil }
	-- The ACTIVE theme's palette, or nil while no package is installed. Every
	-- adapter-owned paint seam that a StyleSheet rule cannot express reads it, so
	-- there is one answer to "which theme is live" rather than one per seam.
	local activeTheme: any = nil
	local setActiveTheme: (package: any?, themeName: string?) -> ()

	-- setActiveTheme(package, themeName): recompute the adapter-owned treatments
	-- and REPAINT whatever is showing one right now. The repaint is the point — a
	-- swap while a control is focused (or while a toggle is on) must recolour it,
	-- not wait for the next interaction (the same live-edit expectation every
	-- other themed surface has).
	local refreshFocusVisuals: () -> ()
	-- assigned AFTER applyToggleValue, which it calls: a local declared later is
	-- not an upvalue, and this seam has already been bitten by that once
	local refreshToggleVisuals: (() -> ())? = nil
	-- ...and the THIRD adapter-owned paint a commit has to re-resolve: the `tint`
	-- channel and a `UI.Path`'s stroke role (screen_paint.refreshThemedPaint).
	-- Forward-declared for the same upvalue reason.
	local refreshThemedPaint: (() -> ())? = nil
	--[[ THE PLAYER'S BACKGROUND TRANSPARENCY PREFERENCE (ADR-0035, owed row O-26).
		`GuiService.PreferredTransparency`, already clamped to 0..1 by the env memo,
		pushed here by the renderer at attach and on every change. 1 is the default —
		paint exactly what the theme declared — so a target that is never pushed
		behaves as it always has. Declared HERE, above `screen_paint.new`, because
		that ctx closes over it and a local declared later is not an upvalue. ]]
	local preferredTransparency = 1
	local refreshBackdropPaint: (() -> ())? = nil
	-- assigned below `activeSheetFor`, which it reads; forward-declared for the
	-- standing upvalue reason (a local declared later is not an upvalue)
	local applyBackdropPreference: () -> ()
	function setActiveTheme(package: any?, themeName: string?)
		local recipe = chrome_slots.focusRecipeOf(package)
		local theme: any = nil
		if type(package) == "table" and type(package.style) == "table" then
			local wanted = themeName or package.style.defaultTheme
			for _, entry in package.style.themes do
				if entry.name == wanted then
					theme = entry
				end
			end
		end
		local rgb = chrome_slots.resolveFocusColor(recipe, theme)
		-- no package, or a recipe that named no colour: the accent the target was
		-- constructed with, exactly as before this existed
		local color = if rgb ~= nil then toColor3(rgb) else nil
		if theme ~= nil and rgb == nil and type(theme.colors) == "table" and type(theme.colors.accent) == "table" then
			-- THE THEME-BLINDNESS FIX: a package that says nothing about focus
			-- still gets ITS OWN accent, not Studio Neutral's blue
			color = toColor3(theme.colors.accent)
		end
		focusTreatment = { kind = recipe.kind, recipe = recipe, color = color }
		activeTheme = theme
		refreshFocusVisuals()
		if refreshToggleVisuals ~= nil then
			refreshToggleVisuals()
		end
		-- THE TINT CHANNEL AND THE PATH ROLE, re-resolved in the same commit
		-- (director report 2026-08-14: "when i changed to the parchment theme, the
		-- spinner stayed blue"). See screen_paint.refreshThemedPaint for why a
		-- paint-only property survives a swap the renderer treats as a re-solve.
		if refreshThemedPaint ~= nil then
			refreshThemedPaint()
		end
	end

	function refreshFocusVisuals()
		for handle, profile in focusedHandles do
			adapter.setFocusVisual(handle, true, profile)
		end
	end

	local COLOR = {
		surface = toColor3(style.colors.surface),
		surfaceStrong = toColor3(style.colors.surfaceStrong),
		content = toColor3(style.colors.content),
		contentStrong = toColor3(style.colors.contentStrong),
		accent = toColor3(style.colors.accent),
		onAccent = toColor3(style.colors.onAccent),
		control = toColor3(style.extra.control),
		controlHover = toColor3(style.extra.controlHover),
		controlPressed = toColor3(style.extra.controlPressed),
		controlSelected = toColor3(style.extra.controlSelected),
		contentSecondary = toColor3(style.extra.contentSecondary),
		hairline = toColor3(style.extra.hairline),
		-- destructive role palette (B-BTN2); a style predating the pair falls back
		-- to the library default, gated for contrast by sheet_model.dangerPair
		danger = toColor3((select(1, sheet_model.dangerPair(style.colors)))),
		onDanger = toColor3((select(2, sheet_model.dangerPair(style.colors)))),
	}

	-- ===== THE CHROME SUBSYSTEM (src/client/screen_chrome) ================
	--
	-- Constructed HERE, below `COLOR`, for the reason this file already keeps a
	-- hoisted `hasUIShadow` probe for: a local declared later is not an upvalue,
	-- and the fallback fill reads the palette. Every call site is further down,
	-- so nothing needs it earlier.
	--
	-- The exported functions are bound to locals of their original names so the
	-- call sites throughout this file — and the source contracts that anchor on
	-- them — read exactly as they did while this code was inline.
	local chrome = screen_chrome.new({
		style = style,
		nativeMode = nativeMode,
		hasUIShadow = hasUIShadow,
		chromeState = chromeState,
		instancesByPath = instancesByPath,
		handlesByPath = handlesByPath,
		focusedHandles = focusedHandles,
		palette = COLOR,
		assertBespokePaint = assertBespokePaint,
		syncTags = syncTags,
		snapshot = function(): any
			return activeThemeSnapshot
		end,
		setFocusVisual = function(handle: any, on: boolean, profile: string?)
			adapter.setFocusVisual(handle, on, profile)
		end,
	})
	local syncChrome = chrome.syncChrome
	local setChromeAssetLoaded = chrome.setChromeAssetLoaded
	local applySkinnedSuppression = chrome.applySkinnedSuppression
	local syncToggleArt = chrome.syncToggleArt
	local applyOverrideVariantArt = chrome.applyOverrideVariantArt
	local focusArtHost = chrome.focusArtHost
	local destroyChromeText = chrome.destroyChromeText
	local destroyIconArt = chrome.destroyIconArt
	local refitIconArt = chrome.refitIconArt
	local refitFullBleed = chrome.refitFullBleed
	local destroyChromeStack = chrome.destroyChromeStack
	local destroyBarFill = chrome.destroyBarFill
	local destroyBarOrnaments = chrome.destroyBarOrnaments
	local dropChromeShadow = chrome.dropChromeShadow
	local chromeArtCensus = chrome.artCensus
	local chromePathChildEntries = chrome.chromePathChildEntries

	-- ===== THE BESPOKE PAINT SUBSYSTEM (src/client/screen_paint) ==========
	--
	-- The sibling of the chrome subsystem above: chrome is the PACKAGE-ART path,
	-- this is the BESPOKE path — surfaces, radii, hairlines, strokes, shadows,
	-- gradients, tints, the interactive-state wiring and the toggle visual. Moved
	-- out for Studio's 200_000-character `Source` write cap, which a module over
	-- the line stops live-syncing through (docs/lessons).
	--
	-- Constructed HERE, where the code it replaced stood, and BELOW `COLOR`,
	-- `chrome` and the paint-claim ledger for the same reason the chrome block
	-- says: a local declared later is not an upvalue. Every export is bound to a
	-- local of its original name, so no call site below changed.
	--
	-- `focusTreatment`, `activeTheme` and the theme snapshot are handed over as
	-- ACCESSORS: the host REASSIGNS all three (setActiveTheme, the theme install),
	-- and a captured value would freeze at construction.
	local paint = screen_paint.new({
		style = style,
		nativeMode = nativeMode,
		palette = COLOR,
		hasUIShadow = hasUIShadow,
		hasPerCornerRadii = hasPerCornerRadii,
		instancesByPath = instancesByPath,
		handlesByPath = handlesByPath,
		chrome = chrome,
		toColor3 = toColor3,
		isReducedMotion = isReducedMotion,
		claimPaint = claimPaint,
		restorePaint = restorePaint,
		assertBespokePaint = assertBespokePaint,
		syncTags = syncTags,
		-- the player's Background Transparency preference (ADR-0035). An accessor
		-- because the renderer pushes a fresh number mid-session
		preferredTransparency = function(): number
			return preferredTransparency
		end,
		focusTreatment = function(): any
			return focusTreatment
		end,
		activeTheme = function(): any
			return activeTheme
		end,
		snapshot = function(): any
			return activeThemeSnapshot
		end,
	})
	local focusColor = paint.focusColor
	local applyTint = paint.applyTint
	local applyPathRole = paint.applyPathRole
	local releaseTint = paint.releaseTint
	local applyStroke = paint.applyStroke
	local ensureScale = paint.ensureScale
	local wireNativePressDip = paint.wireNativePressDip
	local cornerRadiusFor = paint.cornerRadiusFor
	local corner = paint.corner
	local applyShadow = paint.applyShadow
	local applyGradient = paint.applyGradient
	local applyCorners = paint.applyCorners
	local hairline = paint.hairline
	local applySurface = paint.applySurface
	local wireInteractiveStates = paint.wireInteractiveStates
	local applyToggleLabelBox = paint.applyToggleLabelBox
	local buildToggleVisual = paint.buildToggleVisual
	local applyToggleValue = paint.applyToggleValue
	-- forward-declared above `setActiveTheme`, which calls it; assigned here, which
	-- is exactly where it was assigned when this code was inline
	refreshToggleVisuals = paint.refreshToggleVisuals
	refreshThemedPaint = paint.refreshThemedPaint
	refreshBackdropPaint = paint.refreshBackdropPaint

	-- §17 Phase 5: keyboardType capability detection. `TextBox.TextInputType` is
	-- the ONLY member that could summon a numeric/email/password keyboard, but it
	-- is RobloxScript-security-locked BOTH directions today — a plain game/plugin
	-- write pcall-FAILS ("lacking capability RobloxScript"), so this flag is false
	-- on shipping engines (docs/research/2026-07-20-textbox-engine-facts.md §1).
	-- The probe writes rather than merely reads because reads are locked too. When
	-- a future engine unlocks it, this flag flips true and the keyboardType write
	-- below starts working with NO other change (playbook §3.5 forward-compat).
	local canSetTextInputType = (function(): boolean
		return (
			pcall(function()
				local probe = Instance.new("TextBox");
				(probe :: any).TextInputType = Enum.TextInputType.Number
				probe:Destroy()
			end)
		)
	end)()

	-- keyboardType hint -> the closest Enum.TextInputType member NAME. The enum
	-- ships Number/Email/Phone (facts §1); default/unknown -> Default. Mirrored
	-- headlessly by tests/lib/fake_target's KEYBOARD_TYPE_ENGINE_NAME so the
	-- capability contract is provable without an engine — keep the two in lockstep.
	local KEYBOARD_TYPE_ENGINE_NAME: { [string]: string } =
		{ default = "Default", numeric = "Number", email = "Email", phone = "Phone" }

	-- theme packages (ADR-0019 §7): the FIRST root is the target's identity for
	-- per-target theming — the controller links the package sheet there, and
	-- every LATER root (modals, popups) inherits whatever sheet the base root
	-- currently links, so a themed target never presents a Neutral-painted
	-- popup over a parchment screen. With no theme installed the inherited
	-- sheet IS the legacy shared one, byte-compatible with Step 2.
	local baseRootGui: Instance? = nil
	-- EVERY live root, not just the first. A theme is installed on the TARGET,
	-- and a target is however many ScreenGuis it has opened — so repointing only
	-- the base root left every modal, popup and later screen on whatever sheet it
	-- inherited at birth (and a root created BEFORE the install on the legacy one
	-- forever). Pruned on destroy from both ends so the list never holds a dead
	-- Instance.
	local themeRoots: { Instance } = {}
	-- the package sheet a theme controller installed on this whole target, or nil
	-- while the target is on its own (legacy, shared) sheet
	local installedThemeSheet: StyleSheet? = nil
	local function legacyThemeSheet(): StyleSheet?
		return if nativeMode then nativeHandle.sheet else nil
	end
	local function activeSheetFor(): StyleSheet?
		return installedThemeSheet or legacyThemeSheet()
	end

	--[[ THE BACKDROP DIM, COMPOSED WITH THE PLAYER'S PREFERENCE (ADR-0035).

		The `Scrim backdrop` rule is the single writer of `.facet-surface-scrim`'s
		BackgroundTransparency and stays it; this moves the value that one writer
		writes, through the generator's own patch verb. No authority changed, and
		`NATIVE_SHEET_OWNED` is untouched.

		IT PATCHES `activeSheetFor()`, NOT THIS TARGET'S OWN HANDLE, and that is the
		whole reason `native_style.setRuleProperty` grew a sheet-taking form. A theme
		controller relinks every root onto a package sheet IT built; this target's
		`nativeHandle` still points at the sheet nobody is wearing, so a patch through
		the handle would succeed, change a real rule, and be invisible.

		THE BASE IS READ ONCE PER SHEET IDENTITY, before this target has written to
		it. That is not fussiness: a composition that re-reads its own output
		multiplies its own tail and converges to invisible in a handful of cycles
		(ADR-0029 probe L4 measured exactly that failure). A newly linked sheet is
		freshly generated from its package, so its rule still holds the DESIGNER's
		number — which is also why the base tracks a package swap for free, without
		this file having to be told the new package's `scrimOpacity`.

		BESPOKE MODE takes the other branch and repaints the nodes directly, because
		there is no rule there to move. ]]
	local backdropBaseSheet: StyleSheet? = nil
	local backdropBase: { [number]: number } = {}
	function applyBackdropPreference()
		if not nativeMode then
			if refreshBackdropPaint ~= nil then
				refreshBackdropPaint()
			end
			return
		end
		local sheet = activeSheetFor()
		if sheet == nil then
			return
		end
		local fresh = sheet ~= backdropBaseSheet
		backdropBaseSheet = sheet
		for i, entry in sheet_model.PREFERENCE_RULE_PROPS do
			local current = native_style.ruleProperty(sheet, entry.rule, entry.prop)
			if fresh then
				backdropBase[i] = if type(current) == "number" then current else nil
			end
			local base = backdropBase[i]
			if type(base) == "number" then
				local wanted = sheet_model.backdropTransparency(base, preferredTransparency)
				if current ~= wanted then
					native_style.setRuleProperty(sheet, entry.rule, entry.prop, wanted)
				end
			end
		end
	end

	local function trackThemeRoot(gui: Instance)
		table.insert(themeRoots, gui)
	end

	-- the theme controller's whole-target relink seam (ADR-0019 §7). `nil` puts
	-- every root back on the target's own sheet, which is what uninstall needs.
	function adapter.relinkThemeSheet(sheet: StyleSheet?)
		if not nativeMode then
			return
		end
		installedThemeSheet = sheet
		local effective = sheet or legacyThemeSheet()
		local live: { Instance } = {}
		for _, gui in themeRoots do
			if gui.Parent ~= nil then
				table.insert(live, gui)
				if effective ~= nil then
					-- repoints the existing FacetStyleLink rather than adding a
					-- second one: two links means two sheets on one tree and the
					-- cascade winner depends on load order
					native_style.linkAt(gui, effective)
				end
			end
		end
		themeRoots = live
		-- a swap installs a sheet built from the NEW package, carrying that
		-- designer's own dim and none of the player's preference: re-compose it
		-- here, or a themed session silently reverts to the authored value
		applyBackdropPreference()
	end

	function adapter.createRoot(screenId: string): any
		if opts and opts.rootFactory then
			local made = opts.rootFactory(screenId)
			if nativeMode then
				local sheet = activeSheetFor()
				if sheet ~= nil then
					native_style.link(made.gui, sheet)
				end
			end
			baseRootGui = baseRootGui or made.gui
			trackThemeRoot(made.gui)
			return { gui = made.gui, screenId = screenId }
		end
		local gui = Instance.new("ScreenGui")
		gui.Name = `Facet_{screenId}`
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		-- the target's floor against the game's own ScreenGuis; the
		-- presenter still stacks its surfaces above one another from here
		if baseDisplayOrder ~= nil then
			gui.DisplayOrder = baseDisplayOrder
		end
		if nativeMode then
			-- one StyleLink per Facet root (plan §6): the single application point
			local sheet = activeSheetFor()
			if sheet ~= nil then
				native_style.link(gui, sheet)
			end
		end
		gui.Parent = playerGui
		baseRootGui = baseRootGui or gui
		trackThemeRoot(gui)
		return { gui = gui, screenId = screenId }
	end

	-- the theme controller's install seam (ADR-0019 §7): per-target theming is
	-- one sheet + one StyleLink at the target's base root
	function adapter.themeRootGui(): Instance?
		return baseRootGui
	end

	--[[ THE TARGET'S OWN TEARDOWN (R5 review §3b-2). `destroyRoot` releases ONE
		root and, on the last one, the adapter-wide pointer globals — which meant
		an adapter that never got as far as creating a root, or a consumer holding
		several, had no way to give the target back. `client.host` needs one, and
		"call destroyRoot for each root you happen to know about" is not an API.

		Destroys every root this target created, newest first, through the same
		`destroyRoot` path — so the capture cancel, the cursor-hint release and
		`disposeGlobalPointerState` on the last one all run exactly as they do in
		a normal teardown. Idempotent. It does NOT touch a root handed in through
		`opts.rootFactory`'s caller-owned gui beyond destroying the gui it was
		given, which is what `destroyRoot` already did.

		A root that was already destroyed is skipped: `themeRoots` keeps only live
		guis (`relinkThemeSheet` compacts it), and a destroyed gui has no Parent. ]]
	function adapter.dispose()
		for i = #themeRoots, 1, -1 do
			local gui = themeRoots[i]
			if gui ~= nil and gui.Parent ~= nil then
				adapter.destroyRoot({ gui = gui })
			end
		end
		themeRoots = {}
		baseRootGui = nil
	end

	-- ===== THE PRESENTATION CHANNEL (src/client/screen_presentation) ======
	--
	-- A presentation transform composes onto the solver's rect at the WRITE, so a
	-- motion never touches solver geometry and a re-solve never loses the motion:
	-- `applyRect` is the one place a Position is written, and it adds the offset
	-- every time. The module carries that rule, the flat-tree reasoning behind the
	-- offset ACCUMULATION, the clip-host (real-parent) record it composes against,
	-- the subtree index that keeps a 60 Hz leaf motion off the whole tree, the hit
	-- expander that has to travel with the paint, and the scale/rotation half.
	--
	-- REBOUND TO THEIR ORIGINAL NAMES, so not one call site below this line moved.
	-- The three that are not a rename — `setPresentationTransform`, `dropPath`,
	-- `invalidateSubtree` — exist because `presentationCount` is a NUMBER and
	-- `subtreeCache` is REBOUND, and neither can be shared by reference the way
	-- the two record tables are. One authority for the count, the same shape as
	-- the paint-claim ledger's one authority per render property.
	local presentation = screen_presentation.new({
		handlesByPath = handlesByPath,
		refitIconArt = refitIconArt,
		ensureScale = ensureScale,
	})
	local presentationTransforms = presentation.presentationTransforms
	-- THE REGISTRATION SEAM (ADR-0032 Decision 1). The registry itself no longer
	-- comes back as a table: "which paths get registered" is the single predicate
	-- the nested-tree migration changes, so it is reached through these four and
	-- nothing else. `registerHost` is create-or-reuse, which is what the
	-- fade-group-then-`clipChildren` order needs.
	-- hosts whose origin moved during the current rect pass, drained by
	-- `settleRects` (see `adapter.setRect`)
	local movedHosts: { any } = {}
	local registerHost = presentation.registerHost
	local hostAt = presentation.hostAt
	local hostFor = presentation.hostFor
	local recomputePresentationOffset = presentation.recomputePresentationOffset
	local applyHitExpander = presentation.applyHitExpander
	local dropHitExpander = presentation.dropHitExpander
	local applyRect = presentation.applyRect
	local applyPathPoints = presentation.applyPathPoints
	local setPresentationTransform = presentation.setTransform
	local dropPresentationRecords = presentation.dropPath
	local invalidateSubtree = presentation.invalidateSubtree

	-- `decorationHint` (optional 4th argument, ADR-0019 fix round): the pure
	-- decoration hint the renderer read off the node's INTERNAL meta channel
	-- (src/tokens/chrome_slots.readHint). It arrives HERE rather than through a
	-- setter because create() skins the node as its last act — a hint delivered
	-- afterwards would build one decoration and immediately churn it for another.
	-- A target that does not skin simply ignores the argument.
	-- `createOpts` (optional 5th argument, ADR-0022 Decision 2): creation-time facts
	-- the adapter can only honour while it is choosing the engine object.
	-- `canvasGroup` decides the node's engine CLASS, so it cannot arrive as a later
	-- prop write — the instance would already exist.
	-- ---- INERT CONTAINER ELISION -------------------------------------------
	--
	-- MEASURED on the performance lab: of 137 GuiObjects on a five-row surface, **55
	-- (40%) are completely inert** — they do not paint, do not clip, are not
	-- interactive, carry no modifier children and hold no text or image. And in
	-- Facet's FLAT tree they are not even the engine parent of their children:
	-- `create` parents everything to the root and the solver positions absolutely. An
	-- inert container is an invisible, zero-child `Frame` holding a rect nothing
	-- reads. At ~12.4us of engine work each that is ~0.68ms per full window build,
	-- against a `mount` that is 67% of a fling frame.
	--
	-- So a pure layout container gets a HANDLE and no instance, and materialises the
	-- instant anything needs one. Same shape as the lazy `UIScale` that shipped
	-- alongside it: the cheap case is free, the real case is unchanged.
	--
	-- ELIGIBILITY IS CONSERVATIVE AND CREATION-TIME. `create` cannot know whether a
	-- node will later be given a surface or a handler, so it only elides classes that
	-- are layout-only by construction, and `ensureInstance` covers everything else by
	-- materialising on demand. Anything carrying a decoration hint or a canvasGroup
	-- declaration is excluded outright — both are construction-time facts that need a
	-- real object.
	-- ROLLBACK IN ONE PLACE: `opts.elideContainers = false` restores an engine object
	-- for every node. Kept because this changes which instances exist at all, and a
	-- consumer debugging a layout in the Explorer may want the full tree back.
	local elideContainers = not (opts ~= nil and (opts :: any).elideContainers == false)

	local ELIDABLE_CLASSES: { [string]: boolean } = {
		VStack = true,
		HStack = true,
		ZStack = true,
		Grid = true,
		Anchor = true,
		Spacer = true,
	}

	local buildHandle: (any, string, string, any?, any?) -> any

	function adapter.create(
		rootHandle: any,
		path: string,
		class: string,
		decorationHint: any?,
		createOpts: { canvasGroup: boolean?, instanceHost: boolean? }?
	): any
		if
			elideContainers
			and ELIDABLE_CLASSES[class]
			and decorationHint == nil
			-- ANY creation option means the node needs a real engine object: a fade
			-- group needs to BE a CanvasGroup, and a declared instance host needs to
			-- exist before anything can parent under it (ADR-0032 Decision 4). This
			-- read `createOpts.canvasGroup ~= true` while a group was the only option
			-- there was; the elided-host case would have registered a parent with no
			-- instance to be one.
			and createOpts == nil
		then
			-- the construction arguments ride along so materialisation builds exactly
			-- what an eager create would have built
			return {
				path = path,
				class = class,
				elided = true,
				elidedRoot = rootHandle,
				elidedHint = decorationHint,
				elidedOpts = createOpts,
			}
		end
		return buildHandle(rootHandle, path, class, decorationHint, createOpts)
	end

	buildHandle = function(
		rootHandle: any,
		path: string,
		class: string,
		decorationHint: any?,
		createOpts: { canvasGroup: boolean?, instanceHost: boolean? }?
	): any
		local instanceClass = CLASS_TO_INSTANCE[class] or "Frame"
		-- THE FADE GROUP (ADR-0022 Decision 2). A CanvasGroup renders its subtree
		-- into its own buffer, which is what makes `GroupTransparency` fade the GROUP
		-- rather than one node's own paint — and it is why the declaration is explicit
		-- and opt-in: the buffer is a real cost and the node becomes its subtree's
		-- real instance parent. Capability-probed, so an engine without the class
		-- degrades to a Frame (the group simply does not fade) instead of erroring.
		if createOpts ~= nil and createOpts.canvasGroup == true and hasCanvasGroup then
			instanceClass = "CanvasGroup"
		end
		if instanceClass == "ViewportFrame" and not hasStage then
			-- degraded stage: the box is still reserved and still painted, there is
			-- simply no scene in it (and `stageHost` answers nil)
			instanceClass = "Frame"
		end
		if class == "ScrollView" and opts ~= nil and opts.forceScrollFallback == true then
			-- fallback path: identical clip-host behavior with no
			-- engine scrolling — billboard targets keep this until their
			-- coordinate mapping is proven; also the A/B driver for evidence
			instanceClass = "Frame"
		end
		local instance = Instance.new(instanceClass)
		instance.Name = path
		instance.BorderSizePixel = 0
		if not nativeMode then
			-- native mode: the class-default rules own BackgroundTransparency —
			-- this explicit write would permanently defeat every surface rule
			assertBespokePaint("BackgroundTransparency")
			instance.BackgroundTransparency = 1
		end
		if instance:IsA("ScrollingFrame") then
			-- native scroll host (the native substrate; spike m1/m2): the solver owns content
			-- geometry, so the canvas NEVER auto-sizes; the engine owns the
			-- offset, physics, and bars. Region extent arrives via
			-- setScrollRegion once solved.
			instance.AutomaticCanvasSize = Enum.AutomaticSize.None
			instance.CanvasSize = UDim2.new()
			instance.ScrollBarThickness = SCROLL_BAR_THICKNESS
			if not nativeMode then
				assertBespokePaint("ScrollBarImageColor3")
				instance.ScrollBarImageColor3 = COLOR.contentSecondary -- native: "Scroll bar" rule
			end
			-- indicator policy: an auto-policy host is born HIDDEN and shows on
			-- the flash/scroll driver below; NOT a styled property (the sheet's
			-- Scroll bar rule owns the COLOR; visibility is behavior)
			if scrollIndicatorState.policy == "auto" then
				instance.ScrollBarImageTransparency = 1
			end
			instance.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
			instance.ScrollingDirection = Enum.ScrollingDirection.Y
			instance.Selectable = false -- selection policy: never selectable by default
		end
		local handle = { instance = instance, path = path, class = class }
		if instance:IsA("CanvasGroup") then
			handle.canvasGroupInstance = instance
			-- a fade group is a REAL PARENT: its descendants live inside it (which is
			-- what the buffer needs) and their window-space rects are re-based against
			-- it by exactly the instance-host machinery, whose entry is the adapter's
			-- general "this node is a real instance parent" record
			registerHost(path, instance, handle.windowRect, true)
			-- NO CLASS-DEFAULT RULE TARGETS CanvasGroup: the sheet's transparency
			-- defaults select Frame/TextLabel/TextButton/ImageLabel/TextBox/
			-- ScrollingFrame, so a group would wear the engine's own opaque grey plate.
			-- A DECLARED CLAIM makes the write legal and puts it in the dump, instead of
			-- either a silent defeat or a widened sheet nobody asked for.
			if nativeMode then
				claimPaint(handle, "BackgroundTransparency")
			end
			assertBespokePaint("BackgroundTransparency", handle)
			instance.BackgroundTransparency = 1
		end
		if createOpts ~= nil and createOpts.instanceHost == true and instance:IsA("GuiObject") then
			-- A DECLARED MOVE/COMPOSITE BOUNDARY (ADR-0032 Decision 2/4): a real
			-- instance parent so the engine carries `Rotation` and `UIScale` down the
			-- subtree, and a PLAIN one — `crops = false`, no `ClipsDescendants`, no
			-- CanvasGroup buffer. Those three costs are commonly attributed to
			-- nesting and none of them belongs to it: a move-boundary host is one
			-- extra Frame and nothing else.
			registerHost(path, instance, handle.windowRect, false)
		end
		if class == "Divider" then
			-- a Divider MUST paint: an unstyled Frame would be an invisible
			-- hairline, which is the accepted-and-ignored failure Milestone 0
			-- exists to remove. Native mode tags it so the sheet's "Divider" rule
			-- owns the fill; fallback mode writes the hairline colour directly.
			handle.nativeDivider = true
			if nativeMode then
				syncTags(handle)
			else
				assertBespokePaint("BackgroundTransparency")
				instance.BackgroundTransparency = 0
				assertBespokePaint("BackgroundColor3")
				instance.BackgroundColor3 = COLOR.hairline
			end
		end
		if class == "Stage" and instance:IsA("ViewportFrame") then
			-- NATIVE MODE CANNOT REACH A VIEWPORTFRAME (platform review M3): the
			-- style sheet's selectors cover Frame/TextLabel/TextButton/ImageLabel/
			-- TextBox/ScrollingFrame/CanvasGroup, and ViewportFrame is neither
			-- listed nor a Frame subclass — so the class-default transparency rule
			-- the nativeMode skip above defers to never fires here, and the pane
			-- rendered on an opaque grey plate. The write is unconditional for
			-- exactly this class: no sheet rule exists to defeat.
			if nativeMode then
				instance.BackgroundTransparency = 1
			end
			-- THE STAGE'S OWN TWO INSTANCES (ViewportFrame adoption 2026-08-08).
			-- A render needs a camera, and the content needs a root — so the adapter
			-- creates and OWNS both, rather than handing raw instances out or asking
			-- the caller for them. They are children of the frame, so they die with
			-- the node in `remove`/`destroyRoot` with no extra teardown.
			local world = Instance.new("WorldModel")
			world.Name = STAGE_WORLD_NAME
			world.Parent = instance
			local camera = Instance.new("Camera")
			camera.Name = STAGE_CAMERA_NAME
			camera.Parent = instance
			writeStageProp(instance, "CurrentCamera", camera)
			handle.stageWorld = world
			handle.stageCamera = camera
		end
		if class == "Foreign" then
			--[[ THE FOREIGN BOX (ADR-0034). No engine class of its own: the caller's
				instance IS the content, so the container is the plainest Frame this
				adapter makes — which is exactly why it needs no capability probe and
				no degrade path, unlike a Stage.

				TWO CREATION-TIME FACTS, both structural rather than cosmetic:

				CLIPSDESCENDANTS IS THE CONTRACT. "Facet owns the box, you own what is
				in it" is a promise only while nothing in it can paint outside it. The
				clip is what makes the solved rect the WHOLE truth about this node —
				which is also what keeps the cross-surface cover-rect alarm (ADR-0028)
				honest, since that alarm unions solved rects and would otherwise be
				blind to a foreign instance spilling past its box. It is written ONCE,
				here, and never again: `clipChildren` is a CONTAINER_LAYOUT prop and
				`UI.Foreign` does not offer it, so the renderer can never write this
				property on this class and there is no second writer.

				NOT AN INSTANCE HOST. A registered host means "Facet nodes are re-parented
				under this instance and re-based against it". A Foreign is a LEAF: no
				Facet node is ever its child, so registering one would add a rect the
				solver re-places every frame for children that cannot exist.

				`foreignBox` is what the park refusal and the disposal marker key on —
				a field rather than the class name, mirroring the Stage refusal, so the
				fake target can carry the same fact without carrying an engine. ]]
			instance.ClipsDescendants = true
			handle.foreignBox = true
		end
		if class == "Path" then
			-- stroked-path leaf: engine Path2D strokes inside a
			-- transparent holder; color comes from the style role hint
			local path2d = Instance.new("Path2D")
			path2d.Name = "Stroke"
			path2d.Thickness = 4
			path2d.Parent = instance
			handle.path2d = path2d
			-- THE DEFAULT ROLE, FROM THE LIVE THEME. `role` is optional, so for a
			-- path that never declares one this is its only paint — and a path
			-- created while a package is installed has to be BORN wearing it, not
			-- wearing the palette this target was constructed with.
			applyPathRole(handle)
		end
		if instance:IsA("TextLabel") or instance:IsA("TextButton") then
			--[[ AUTOLOCALIZE — MEASURED, AND LEFT ON BY DEFAULT.

				MEASURED on a physical device (Samsung Galaxy A10e, Android 11,
				Release 734) in the first MicroProfiler capture that ever contained
				Facet's solver scopes, 2026-08-13:

				  LocalizationService::attemptLocalization  64 calls, 39.54 ms
				  ...its parent, in ALL 64 cases                Facet/mount
				  per call                                     0.6178 ms mean, 2.52 worst
				  share of Facet/mount inclusive              25.1%
				  share of ALL Facet CPU in the capture        8.9%
				  of which Stat::send TELEMETRY                21.90 ms — 55%

				The engine runs `attemptLocalization` when a `TextLabel`/`TextButton`
				with `AutoLocalize = true` (the default) is parented or has its text
				set, and more than half of what it costs on this hardware is
				telemetry the game gets nothing from. Nothing in `src/` had ever
				touched the property — `grep -rn "AutoLocalize" src/` returned
				nothing — so every text instance Facet has ever created has paid it.

				DEFAULTING THIS OFF WAS THE WRONG CALL AND WAS REVERSED THE SAME DAY.
				The director's ruling: *"we do want to localize text."* Buying frame
				time by silently removing a capability the game wants is not a
				performance win, it is a feature regression with a good excuse. The
				default is now Roblox's own (`true`), and declining it is an explicit
				`screen_target.new({ autoLocalize = false })` for an experience that
				does not localize.

				What the measurement still buys is an INFORMED choice: the cost is
				written down, in this file, next to the only place it is paid.

				This is invisible in Studio — an M4 executes the same telemetry path
				one to two orders of magnitude faster, which is exactly why it
				survived every green suite and every Studio session until a phone
				was profiled. ]]
			-- see `Opts.autoLocalize`: default true (translation works), opt-out for
			-- an experience that does not localize and does not want to pay
			-- ~0.62 ms per materialised text instance on low-end hardware
			if not autoLocalize then
				instance.AutoLocalize = false
			end
			-- default only; a declared `textAlign` arrives through setProp, which the
			-- renderer calls for every style prop at creation and on every change
			instance.TextXAlignment = Enum.TextXAlignment.Left
			-- CENTER, not Top: the headless measurer deliberately over-reserves
			-- for scripts/wraps it cannot model, so the engine text can be
			-- shorter than its solved box — centering splits that error evenly
			-- instead of pinning text to the top (playlist name cells,
			-- director report 2026-07-20)
			instance.TextYAlignment = Enum.TextYAlignment.Center
			instance.TextWrapped = true
			-- THE ELLIPSIS FLOOR, for every text node and not just Buttons
			-- (director, 2026-07-27). A single word cannot be wrapped legally, so
			-- when its box is too small SOMETHING has to give; without this the
			-- engine simply cut the string mid-character and the result read as
			-- corruption rather than as truncation. `AtEnd` is the honest
			-- degradation and it is inert whenever the text fits.
			instance.TextTruncate = Enum.TextTruncate.AtEnd
			instance.TextSize = 16 -- layout authority default; scaled by applyTextScale
			if not nativeMode then
				-- native: "Text default"/"Button text default" rules own these
				assertBespokePaint("TextColor3")
				-- THE PRE-PAINT FLOOR, not the authority (F2, 2026-08-02). This node's
				-- FACE comes from its typography role through the `textFont` write in
				-- setProp, inside the same solve; this is only what the instance wears
				-- for the instant between creation and that write.
				instance.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json")
				instance.TextColor3 = COLOR.content
			end
		end
		if class == "Grip" then
			-- non-button Active pointer zone: sinks presses without being a
			-- GuiButton (the engine overrides MouseIcon over GuiButtons)
			instance.Active = true
		end
		if class == "Button" and instance:IsA("TextButton") then
			instance.AutoButtonColor = false
			instance.TextXAlignment = Enum.TextXAlignment.Center
			instance.TextYAlignment = Enum.TextYAlignment.Center
			instance.TextTruncate = Enum.TextTruncate.AtEnd
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, style.space.s + 4)
			pad.PaddingRight = UDim.new(0, style.space.s + 4)
			pad.Parent = instance
			if nativeMode then
				-- classify: control chrome + interaction states come from the
				-- sheet (.facet-surface-control, .facet-interactive, :Hover/:Press)
				handle.nativeSurface = "control"
				handle.nativeInteractive = true
				syncTags(handle)
				wireNativePressDip(instance, handle)
			else
				wireInteractiveStates(instance, handle)
			end
		elseif class == "Toggle" and instance:IsA("TextButton") then
			instance.AutoButtonColor = false
			if nativeMode then
				handle.nativeSurface = "control"
				handle.nativeInteractive = true
				syncTags(handle)
				wireNativePressDip(instance, handle)
			else
				wireInteractiveStates(instance, handle)
			end
			buildToggleVisual(instance, handle)
		elseif class == "TextField" and instance:IsA("TextBox") then
			-- §17 Phase 5 (UI.TextInput) single-line engine field. Load-bearing
			-- config (research 2026-07-20-textbox-engine-facts):
			--   * ClearTextOnFocus=false — engine default TRUE wipes the bound
			--     value the instant the box is focused (F10). MUST be false.
			--   * MultiLine=false + TextWrapped=false — single line only;
			--     wrap-while-typing is engine-broken on mobile (devforum 1014598),
			--     so multi-line stays unshipped/ungated.
			instance.ClearTextOnFocus = false
			instance.MultiLine = false
			instance.TextWrapped = false
			instance.TextEditable = true
			instance.Text = ""
			instance.TextXAlignment = Enum.TextXAlignment.Left
			instance.TextYAlignment = Enum.TextYAlignment.Center
			instance.TextSize = 16 -- layout authority
			if not nativeMode then
				-- native: "Field text default" + "Field — outline" rules own these
				assertBespokePaint("TextColor3")
				-- the pre-paint floor; the role's face lands via the `textFont` write
				instance.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json")
				instance.TextColor3 = COLOR.content
				instance.PlaceholderColor3 = COLOR.contentSecondary
			end
			-- reads as an input control: control fill + radius + hairline + inset
			applySurface(instance, "control", handle)
			if not nativeMode then
				hairline(instance)
			end
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, style.space.s + 4)
			pad.PaddingRight = UDim.new(0, style.space.s + 4)
			pad.Parent = instance
			-- gamepad reachability: the engine A-press on a Selected TextBox
			-- captures focus natively (engine-facts §8); Facet's own focus graph
			-- still drives the ring via setFocusVisual.
			instance.Selectable = true
		end
		-- INSTANCE-HOST PARENTING: descendants of a registered host live INSIDE it,
		-- so the engine can carry something down the subtree; everything else stays
		-- flat under the root, which is still most of the tree. FOUR triggers
		-- register one, and only the first is about cropping (ADR-0032): a
		-- ScrollView, an authored `clipChildren`, a fade group, and an authored
		-- `scale`/`rotation` on a container that has children.
		local host = hostFor(path)
		if host ~= nil then
			handle.instanceHost = host
			table.insert(host.children, handle)
			instance.Parent = host.instance
		else
			instance.Parent = rootHandle.gui
		end
		instancesByPath[path] = instance
		handlesByPath[path] = handle
		-- the subtree index is derived from this map, so it dies with any structural
		-- change rather than being patched at three sites
		invalidateSubtree()
		-- a node born INSIDE a live presentation transform (a row added to a shifted
		-- surface, a re-entering transition subtree) starts at the composed position:
		-- its first rect write must already carry the offset, or it appears at rest for
		-- a frame and jumps
		recomputePresentationOffset(handle)
		-- decoration LAST: every classification input (class, surface, the
		-- the instance-host parenting, the control's own slot hint) is settled by now, so
		-- a node is skinned once rather than built and rebuilt as its setup proceeds
		handle.decorationHint = decorationHint
		syncChrome(handle)
		return handle
	end

	-- MATERIALISE. Builds exactly what an eager `create` would have, then folds it
	-- into the handle table the renderer already holds — identity has to survive,
	-- because the renderer keys everything off this exact table.
	--
	-- Anything the node was told while it had no instance is replayed afterwards: its
	-- rect and its visibility. Those are the only two an elided node can have been
	-- given, because every other entry point materialises before it writes.
	local function ensureInstance(handle: any): Instance?
		if handle == nil then
			return nil
		end
		if handle.instance ~= nil or handle.elided ~= true then
			return handle.instance
		end
		local built = buildHandle(handle.elidedRoot, handle.path, handle.class, handle.elidedHint, handle.elidedOpts)
		local pendingRect, pendingVisible = handle.pendingRect, handle.pendingVisible
		handle.elided = nil
		handle.elidedRoot, handle.elidedHint, handle.elidedOpts = nil, nil, nil
		handle.pendingRect, handle.pendingVisible = nil, nil
		for k, v in built do
			handle[k] = v
		end
		-- `buildHandle` registered the throwaway table it made; the live handle is this
		-- one, and a stale registration would hand some later lookup a table nobody
		-- else references
		handlesByPath[handle.path] = handle
		instancesByPath[handle.path] = handle.instance
		local host = handle.instanceHost
		if host ~= nil then
			for i, child in host.children do
				if child == built then
					host.children[i] = handle
					break
				end
			end
		end
		if pendingRect ~= nil then
			adapter.setRect(handle, pendingRect)
		end
		if pendingVisible ~= nil then
			adapter.setVisible(handle, pendingVisible)
		end
		return handle.instance
	end

	function adapter.getInstance(path: string): Instance?
		return instancesByPath[path]
	end

	--[[ THE DEV DRIVE SEAM (RascalRally device round 1, the director's addition).
		Invokes the EXACT closure `setActivateHandler` registered for this node —
		the one the engine's `GuiButton.Activated` calls — so a scripted drive and
		a real press enter the framework at the same line, with the same policy
		checks, the same arm-on-tap arbitration and the same semantic dispatch
		behind them. It is not a second activation path: there is only one, and
		this is a second CALLER of it.

		WHAT IT PROVES AND WHAT IT DOES NOT: everything downstream of the engine
		edge (routing, policy, state, motion) is real evidence. Everything UPSTREAM
		— that the engine really delivers a touch to that instance at all — is not,
		and only a device pass can close it. The device defect this note records
		lived exactly there.

		Returns false when the path has no activate handler, so a caller can tell
		"nothing there" from "did nothing".

		A META-LESS DRIVE IS THE TOUCH VERB (decided 2026-08-13, redteam item 10;
		the reasoning is the codicil in `docs/lessons/a-synthesized-activate-must-
		carry-the-pointer-kind.md`). Controls read `meta == nil` as "no input facts
		at all", which is the touch branch — and since parity round 2 that branch
		OPENS a Table row that declares `onPrimaryAction` rather than selecting it.
		A real press always carries a full meta now (`pointerActivateMeta`, in
		`screen_pointer`, for both producers), so passing none here is a
		deliberately underspecified call and gets the bare-mount answer. Drive the mouse semantics explicitly
		with `{ source = "pointer", pointer = "mouse" }`.
	]]
	function adapter.driveActivate(path: string, meta: any?): boolean
		local handle = handlesByPath[path]
		if handle == nil or handle.activate == nil then
			return false
		end
		handle.activate(meta)
		return true
	end

	--[[ THE ENGINE-CONTENT SEAM (UI.Stage, ViewportFrame adoption 2026-08-08).

		A `Stage` reserves a box; what goes IN it is engine Instances, which nothing
		above `src/client/` may touch. So the seam is a per-node handle with three
		verbs and an engine-type-free boundary — plain `{x,y,z}` / `{r,g,b}` tables
		in, CFrame/Color3/Vector3 writes out — and the split of ownership is stated
		once here and repeated in api.md:

		  Facet owns  the ViewportFrame, the WorldModel, the Camera, the box, the
		               lifecycle, and every write to Ambient/LightColor/
		               LightDirection/CurrentCamera (all four declared SEAM_OWNED);
		  the CALLER   owns whatever it parents into `contentRoot()` — the framework
		               never enumerates, moves, or destroys that content, and it
		               dies with the frame when the node does.

		Cached per node, and DEAD when the node is: `remove`/`destroyRoot` clear the
		refs, and every verb then refuses by name instead of writing into a
		destroyed instance. Answers nil for anything that is not a live Stage —
		including a stage degraded to a Frame on an engine without the classes.
	]]
	function adapter.stageHost(handle: any): any?
		if handle == nil or handle.class ~= "Stage" then
			return nil
		end
		-- an elided node has no instance yet; a Stage is never elidable, but the
		-- guard keeps the seam honest if that list ever grows
		if handle.instance == nil or handle.stageWorld == nil or handle.stageCamera == nil then
			return nil
		end
		if handle.stageApi ~= nil then
			return handle.stageApi
		end
		local stagePath = handle.path
		local function live(): boolean
			return handle.stageWorld ~= nil
				and handle.stageCamera ~= nil
				and handle.instance ~= nil
				and handle.stageDisposed ~= true
		end
		local function assertLive()
			if not live() then
				error(stage_content.disposedError(stagePath), 0)
			end
		end
		local api = table.freeze({
			-- aim the owned camera. Normalized FIRST (a refusal must leave the
			-- camera exactly where it was), then two engine writes.
			setCamera = function(spec: any)
				local camera = stage_content.normalizeCamera(spec)
				assertLive()
				local eye = Vector3.new(camera.position.x, camera.position.y, camera.position.z)
				local at = Vector3.new(camera.lookAt.x, camera.lookAt.y, camera.lookAt.z)
				-- the degenerate-camera refusal now lives in the SHARED normalizer
				-- (stage_content.normalizeCamera, platform review M2) so both
				-- adapters refuse identically before any write; and the camera's
				-- own two properties go through the SAME indexed seam writer as
				-- the frame's lighting (platform review N1 declared them
				-- SEAM_OWNED, and the no-bespoke-write pin scans for literals)
				writeStageProp(handle.stageCamera, "CFrame", CFrame.lookAt(eye, at))
				if camera.fov ~= nil then
					writeStageProp(handle.stageCamera, "FieldOfView", camera.fov)
				end
			end,
			-- the scene's lighting, which lives on the FRAME (research §1) — which
			-- is precisely why a consumer may not write it directly and this seam
			-- exists. Each field is independent; absent means "leave it alone".
			setLighting = function(spec: any)
				local lighting = stage_content.normalizeLighting(spec)
				assertLive()
				if lighting.ambient ~= nil then
					local c = lighting.ambient
					writeStageProp(handle.instance, "Ambient", Color3.new(c.r, c.g, c.b))
				end
				if lighting.lightColor ~= nil then
					local c = lighting.lightColor
					writeStageProp(handle.instance, "LightColor", Color3.new(c.r, c.g, c.b))
				end
				if lighting.lightDirection ~= nil then
					local d = lighting.lightDirection
					writeStageProp(handle.instance, "LightDirection", Vector3.new(d.x, d.y, d.z))
				end
			end,
			-- the caller's content root. It is handed OUT (rather than the caller
			-- handing content in) so the framework never has to know the shape of
			-- somebody's scene — parent models here, and they die with the node.
			contentRoot = function(): Instance
				assertLive()
				return handle.stageWorld
			end,
		})
		handle.stageApi = api
		return api
	end

	--[[ THE FOREIGN-CONTENT SEAM (UI.Foreign, ADR-0034).

		Stage's 2-D sibling, and deliberately SMALLER than it. A `Foreign` reserves a
		clipping box; what goes in it is one GuiObject the CALLER created, so the
		seam is a per-node handle with ONE verb and the split of ownership is:

		  Facet owns  the container Frame, its rect, its plate, its clip and its
		               lifecycle — and makes exactly ONE claim on the adopted
		               instance, its `Parent`, declared in the authority manifest as
		               `Foreign.Parent = "host"` and gated below;
		  the CALLER   owns the instance itself: its class, every one of its
		               properties, its own children, and its lifetime. Facet never
		               enumerates it, never sizes it, never paints it, and keeps no
		               reference to it — which is why "we write nothing else" is a
		               structural fact rather than a promise. It DIES WITH THE BOX
		               (engine Destroy propagation); a caller who needs it to outlive
		               the node reparents it out on `onDisappear`.

		NO `contentRoot()`, unlike `stageHost` — and that difference is the design.
		Handing back the container would hand back a framework-owned GuiObject that
		the renderer writes a rect and a plate onto every solve, which is precisely
		the writable-handle hole `fusion-comparison.md` §5 defers `Ref` for. Adopting
		INTO the container hands back nothing at all.

		Cached per node, and DEAD when the node is (`remove`/`destroyRoot` call
		`markForeignDisposed`), so a stale handle refuses by name instead of parenting
		into a destroyed instance. Answers nil for anything that is not a live
		Foreign.
	]]
	function adapter.foreignHost(handle: any): any?
		if handle == nil or handle.class ~= "Foreign" or handle.foreignBox == nil then
			return nil
		end
		if handle.instance == nil or handle.foreignDisposed == true then
			return nil
		end
		if handle.foreignApi ~= nil then
			return handle.foreignApi
		end
		local foreignPath = handle.path
		local function assertLive()
			if handle.instance == nil or handle.foreignDisposed == true then
				error(foreign_content.disposedError(foreignPath), 0)
			end
		end
		local api = table.freeze({
			adopt = function(instance: any)
				-- LIVENESS FIRST: a dead node is about the node, not the instance
				assertLive()
				--[[ BUILD THE DESCRIPTION THE PURE LADDER JUDGES. Only an engine can
					answer these, which is the whole reason the ladder takes facts
					rather than an Instance — the headless twin states the same five
					and both adapters then refuse identically (the headless-green/device-wrong class discipline).

					`alive` is the interesting one: Roblox offers no `IsDestroyed`, and
					a destroyed instance accepts every write except a non-nil Parent
					("Parent property is locked"). So the probe IS the write, made
					against the container it is going to end up in anyway — a pcall
					that either succeeds (in which case the adoption is done) or
					fails (in which case nothing moved and the ladder says why). That
					is the same detection the recycling `adopt` above relies on
					(architecture review F9). ]]
				local isInstance = typeof(instance) == "Instance"
				local candidate: foreign_content.Candidate = {
					present = isInstance,
					className = if isInstance then (instance :: Instance).ClassName else typeof(instance),
					isGuiObject = isInstance and (instance :: Instance):IsA("GuiObject"),
					isLayerCollector = isInstance and (instance :: Instance):IsA("LayerCollector"),
					-- assume alive; the parent write below is the only real test, and
					-- the ladder is re-run with the answer if it fails
					alive = true,
				}
				foreign_content.assertAdmissible(foreignPath, candidate)
				-- THE ONE CLAIM, THROUGH THE ONE GATE. `Foreign.Parent` is the only
				-- entry in the manifest carrying the `host` authority, so a second
				-- writer for it anywhere is a loud error rather than a silent win.
				authority.assertWrite("Foreign", "Parent", "host")
				local placed = pcall(function()
					(instance :: Instance).Parent = handle.instance
				end)
				if not placed then
					candidate.alive = false
					foreign_content.assertAdmissible(foreignPath, candidate)
				end
			end,
		})
		handle.foreignApi = api
		return api
	end

	-- ENGINE TEXT PREMEASUREMENT (text-measurement milestone): the renderer
	-- hands over the WORDS its last solve could not size exactly; this measures
	-- them with the engine's own bounds API off the render path and feeds the
	-- widths back, which costs exactly one re-solve. Implementation and the
	-- reasoning live in src/client/text_premeasure.
	-- ...and the CANCEL comes back with it: a boot-window batch answers
	-- twice, up to ~12 s apart, and a renderer torn down in between must not be
	-- called back into a surface that no longer exists.
	function adapter.measureTextWidths(requests: { any }, done: (results: { any }, final: boolean?) -> ()): () -> ()
		return text_premeasure.measure(requests, done)
	end

	-- whole-surface visibility: the presenter's no-pop text gate mounts and
	-- solves a screen and only then lets it be seen. ScreenGui.Enabled, so a
	-- hidden surface costs no per-node writes and reveals in one property.
	function adapter.setRootVisible(rootHandle: any, visible: boolean)
		rootHandle.gui.Enabled = visible
	end

	-- native-style introspection + control surface (ledger the native stylesheets work/A6/A7; the
	-- scenario runner reads/drives these for the evidence artifacts)
	function adapter.nativeStyleInfo(): any
		if not nativeMode then
			return { active = false }
		end
		return {
			active = true,
			stamp = nativeHandle.stamp,
			seeded = nativeHandle.seeded,
			activeTheme = nativeHandle.activeTheme,
			sheet = nativeHandle.sheet,
			themes = nativeHandle.themes,
		}
	end
	function adapter.setNativeTheme(name: string)
		if nativeMode then
			nativeHandle.setTheme(name)
		end
	end
	function adapter.setNativeTransitionsEnabled(on: boolean)
		if nativeMode then
			nativeHandle.setTransitionsEnabled(on)
		end
	end
	--[[ THE BESPOKE half of the same fact (C1, 2026-08-12). `setNativeTransitions
		Enabled` above reaches the SHEET's declared transitions; this reaches every
		tween this file plays itself — the press dip, the state-paint fades, the
		fill crossfade, the toggle slide — all of which route through the one
		`isReducedMotion()` resolver at the top of `new`.

		Pushed by the renderer from the environment's `reducedMotion` fact, at
		attach and on every change. It is a plain flag write on purpose: nothing
		is re-painted here, because reduced motion changes how the NEXT transition
		plays, not what is currently on screen. An in-flight tween is allowed to
		finish; the alternative is snapping a control mid-animation, which is
		itself a motion event. ]]
	function adapter.setReducedMotion(reduced: boolean)
		reducedMotionPushed = reduced == true
	end

	--[[ THE PLAYER'S BACKGROUND TRANSPARENCY PREFERENCE (ADR-0035, owed row O-26).

		A sibling of the two above and a deliberate DIFFERENCE from both: reduced
		motion is a flag write because it changes how the NEXT transition plays, and
		this one repaints because it changes what is on screen right now. A player
		who opens Settings from inside a modal is looking at the backdrop while they
		move the slider.

		ONE VALUE, TWO WRITERS, NEITHER OF THEM NEW — which is why no authority moved
		and `NATIVE_SHEET_OWNED` is untouched:

		  * NATIVE — the `Scrim backdrop` StyleRule is and stays the only writer of
		    `.facet-surface-scrim`'s BackgroundTransparency. We move the RULE's value
		    through the generator's own `setRuleProperty`, exactly as a designer's
		    metric edit already does (`pushMetricRuleProps`). ADR-0029 refused rule
		    mutation for a per-node FADE — 3 frames of latency and one generated rule
		    per faded node — and neither objection survives here: a preference moves
		    at human frequency, and it is per-selector by nature, because every
		    backdrop in the session should answer it identically.
		  * BESPOKE — `screen_paint.refreshBackdropPaint`, the same explicit write
		    that already owned this property in fallback mode.

		The composed number comes from `sheet_model.backdropTransparency` in both
		cases, so the modes cannot disagree, and it composes from the MODEL's own
		recorded base rather than from the rule's current value — re-reading what we
		last wrote is how a composition eats its own tail (ADR-0029 probe L4). ]]
	function adapter.setPreferredTransparency(effective: number)
		if type(effective) ~= "number" or effective ~= effective then
			return
		end
		preferredTransparency = math.clamp(effective, 0, 1)
		applyBackdropPreference()
	end

	-- ===== decoration-slot control surface (ADR-0019 §5) ==================
	-- The theme controller drives these inside its swap transaction; the
	-- scenario reads them for the census evidence.

	-- setThemePackage(package) -> did the CHROME change? A palette-only swap
	-- re-resolves the whole package and must not churn one decoration
	-- instance, so the sweep only runs when the recipes actually differ.
	-- `themeName` (optional 2nd argument, director fix round 2026-07-25): the
	-- theme the controller just committed. It arrives with the package because
	-- the FOCUS treatment needs a palette — `chrome.focus.color = "$FocusGlow"`
	-- resolves per THEME — and the controller sets both inside one transaction,
	-- so there is no frame where the two disagree. A caller that passes only the
	-- package gets the package's own default theme.
	-- `snapshot` (optional 3rd argument, ADR-0020 R4): the metrics the controller
	-- committed in this same transaction. Icons size from `iconSizes`, so a
	-- METRIC-only difference between two packages has to reach the adapter even
	-- when `changed` is false — a package that swaps only its icon ladder still
	-- has to resize every picture.
	function adapter.setThemePackage(package: any?, themeName: string?, snapshot: any?): boolean
		local changed = chromeState.setPackage(package)
		local sizesChanged = false
		do
			local before = if type(activeThemeSnapshot) == "table" then activeThemeSnapshot.iconSizes else nil
			local after = if type(snapshot) == "table" then snapshot.iconSizes else nil
			for _, role in themePackage.ICON_SIZE_ROLES do
				local a = if type(before) == "table" then (before :: any)[role] else nil
				local b = if type(after) == "table" then (after :: any)[role] else nil
				sizesChanged = sizesChanged or a ~= b
			end
			local unitBefore = if type(activeThemeSnapshot) == "table" then activeThemeSnapshot.pixelUnit else nil
			local unitAfter = if type(snapshot) == "table" then snapshot.pixelUnit else nil
			sizesChanged = sizesChanged or unitBefore ~= unitAfter
		end
		-- A PACKAGE-ONLY CALL KEEPS THE METRICS IT HAS. The decoration surface has
		-- always been callable with just a package (the verification runner does
		-- exactly that before the controller's transaction), and clobbering a good
		-- snapshot with nil there would resize every icon to the neutral rung for
		-- a frame. Clearing the package DOES clear them: an uninstalled target has
		-- no metrics of its own to report.
		if snapshot ~= nil or package == nil then
			activeThemeSnapshot = snapshot
		end
		setActiveTheme(package, themeName)
		-- the Toggle's label column is METRIC geometry the sheet cannot express,
		-- so it has to be re-applied here or a swap leaves every switch drawing
		-- its label in the OUTGOING package's column (director round 9)
		for _, handle in handlesByPath do
			applyToggleLabelBox(handle)
		end
		if changed or sizesChanged then
			for _, handle in handlesByPath do
				syncChrome(handle)
			end
		end
		return changed
	end

	-- the content IDs the app's resource provider should resolve for a policy
	-- ("install" at install time, "lazy" on first use). No raw content ID
	-- leaves package data through any other route.
	function adapter.themeAssetsToPreload(policy: string): { { name: string, contentId: string } }
		return chrome_slots.assetsToPreload(chromeState.package(), policy)
	end

	-- the provider's answer for one asset. Idempotent in both directions: the
	-- fallback tag flips exactly once per real state change.
	function adapter.setChromeAssetLoaded(assetName: string, ok: boolean)
		setChromeAssetLoaded(assetName, ok)
	end

	-- THE SIXTH VARIANT STATE (ADR-0020 R2). `default/hover/pressed/disabled` are
	-- engine GuiState and `selected` is a binding the renderer already forwards;
	-- `error` is neither — no control publishes one today, so this is the seam a
	-- control's own error binding lands on (P3's wiring) and the seam the
	-- verification scenario drives. It flips ONE tag, through the desired set, so
	-- the package's `.facet-state-error > .<layerTag>` art rules match; a rung-2
	-- override repaints from the same flag.
	-- Returns whether the state actually changed, so a caller cannot mistake a
	-- no-op for a flip.
	function adapter.setChromeErrorState(path: string, on: boolean): boolean
		local handle = handlesByPath[path]
		if handle == nil or (handle.errorState == true) == on then
			return false
		end
		handle.errorState = on
		syncTags(handle)
		applyOverrideVariantArt(handle)
		return true
	end

	-- THE DECODE JUDGEMENT (rich-skinning v2), beside the census it explains: for every
	-- art instance this target owns, was the engine ever asked to decode it? An
	-- undecoded image the target may NOT judge is one the player cannot see (hidden,
	-- muted by a fallback, unsized, unsourced, or clipped entirely away by a scroll
	-- host), and reading that silence as asset failure is the defect this reports on.
	function adapter.chromeArtJudgement(): any
		return chromeArtCensus()
	end

	function adapter.chromeCensus(): any
		local census = chromeState.census()
		-- an independent count of what is actually in the tree, so the ledger
		-- above can be checked against the DataModel rather than trusted
		local actual = 0
		for _, handle in handlesByPath do
			if handle.chrome ~= nil and handle.chrome.Parent ~= nil then
				actual += 1
			end
		end
		census.actualInstances = actual
		-- the same independent count for slot SHADOWS: adapter-owned paint the
		-- sheet cannot express, so "a flat package pays zero shadows" has to be
		-- measurable against the DataModel too
		local actualShadows = 0
		for _, handle in handlesByPath do
			if handle.chromeShadow ~= nil and handle.chromeShadow.Parent ~= nil then
				actualShadows += 1
			end
		end
		census.actualShadows = actualShadows
		-- LAYER COST IN DATAMODEL UNITS (ledger rich-skinning v2). `census.layers` counts
		-- declared LAYERS — the authoring unit, directly comparable with
		-- chrome_slots.censusOf — while a `corners` layer is four ornaments and an
		-- `edges` layer one rail per side. Both numbers are published because both
		-- are true and neither can be derived from the other by a reader.
		local actualLayerInstances = 0
		local layeredNodes = 0
		local overhang: { [string]: any } = {}
		-- WHICH nodes, not only how many: the verification scenario has to probe
		-- the real ladders, and a path list it can iterate beats a fixture-shaped
		-- guess that goes stale the moment the fixture is edited
		local layeredPaths: { string } = {}
		for path, handle in handlesByPath do
			if handle.chromeStack == nil then
				continue
			end
			table.insert(layeredPaths, path)
			layeredNodes += 1
			for _, entry in handle.chromeStack do
				if entry.instance.Parent ~= nil then
					actualLayerInstances += 1
				end
			end
			local slotOverhang = chrome_slots.overhangFor(chromeState.package(), handle.chromeStackSlot)
			if chrome_slots.hasOverhang(slotOverhang) then
				overhang[handle.chromeStackSlot] = slotOverhang
			end
		end
		table.sort(layeredPaths)
		census.actualLayerInstances = actualLayerInstances
		census.layeredNodes = layeredNodes
		census.layeredPaths = layeredPaths
		-- WHAT PAINTS OUTSIDE THE SOLVED RECT (rs-m3). A plaque overhangs, so an
		-- ancestor that clips is a fact a reader needs at census time rather than
		-- a surprise on a phone.
		census.overhang = overhang
		-- SEMANTIC ICON PICTURES (ADR-0020 R4). Cost honesty for the icon path: a
		-- flat theme, or a theme with no icon map, pays ZERO instances because
		-- every request resolves to the glyph the control already drew. Counted
		-- from the DataModel, and paired with the requests so "declared but never
		-- resolved" is visible rather than inferred.
		local actualIcons, iconRequests = 0, 0
		local iconPaths: { string } = {}
		for path, handle in handlesByPath do
			local hint = handle.decorationHint
			if type(hint) == "table" and type(hint.icon) == "string" then
				iconRequests += 1
			end
			if handle.iconInstance ~= nil and handle.iconInstance.Parent ~= nil then
				actualIcons += 1
				table.insert(iconPaths, path)
			end
		end
		table.sort(iconPaths)
		census.iconRequests = iconRequests
		census.iconArt = actualIcons
		census.iconPaths = iconPaths
		local actualFocusGlows = 0
		for _, handle in handlesByPath do
			if handle.focusGlow ~= nil and handle.focusGlow.Parent ~= nil then
				actualFocusGlows += 1
			end
		end
		census.actualFocusGlows = actualFocusGlows
		-- lifted labels are decoration cost too: counted so the
		-- flat-theme-zero and ornate-theme-exactly-N propositions stay honest
		census.textLifts = chrome.textLifts()
		return census
	end

	-- cross-surface z (modal-dismissal spec §2.2): order whole ScreenGuis so the
	-- synthesized scrim renders beneath its owner modal (and above lower surfaces).
	function adapter.setRootDisplayOrder(rootHandle: any, n: number)
		local gui = rootHandle.gui
		if gui:IsA("ScreenGui") then
			gui.DisplayOrder = n
		end
	end

	function adapter.setRect(handle: any, rect: any)
		handle.windowRect = rect
		if handle.elided == true then
			-- NOTHING TO MOVE. An elided node paints nothing and, in this flat tree, is
			-- not the engine parent of its children — they were positioned absolutely
			-- from the same solve. The rect is recorded so materialisation can apply it
			-- if the node ever needs a real object.
			handle.pendingRect = rect
			return
		end
		-- THE ORIGIN MOVES FIRST, AND THE CHILDREN ARE RE-BASED LAST. This re-based
		-- every child of a moved host INLINE, to fix a descendant that "may have
		-- received their rects before the host did" — a real symptom of the
		-- renderer's old unordered rect hash, corrected at the cost of writing every
		-- descendant twice (measured: 240 engine Position changes on 120 nodes, and
		-- one moment per move with the subtree in the wrong place —
		-- artifacts/nested-instance-tree/live-probes.md §4). The renderer now walks
		-- in document order and the re-base waits for `settleRects`. BOTH halves are
		-- needed: ordering alone still re-bases children against their own stale
		-- rects, and deferring alone still lets the first write see a stale origin.
		-- It is kept rather than deleted because an incremental re-solve can move a
		-- host without re-emitting its children, and only this seam can place them.
		local entry = hostAt(handle.path)
		if entry ~= nil then
			entry.rect = rect
			if entry.settlePending ~= true then
				entry.settlePending = true
				table.insert(movedHosts, entry)
			end
		end
		applyRect(handle)
	end

	-- re-base the children of every host that moved this pass, once every rect has
	-- landed. Empty on the overwhelming majority of passes (nothing moved a host),
	-- and the write skip in `applyRect` makes a child that is already in the right
	-- place free.
	function adapter.settleRects()
		if #movedHosts == 0 then
			return
		end
		for _, entry in movedHosts do
			entry.settlePending = nil
			for _, child in entry.children do
				applyRect(child)
			end
		end
		table.clear(movedHosts)
	end

	-- ===== THE POINTER SEAM (src/client/screen_pointer) ==================
	--
	-- The one activate meta, the global pointer capture, the semantic cursor and
	-- the engine connection census. The module carries the whole press story and
	-- the two rulings behind it (one meta from two producers; one capture body for
	-- a control and for its minimum-target expander).
	--
	-- REBOUND TO THEIR ORIGINAL NAMES, so not one call site below this line moved.
	-- The two that are not a rename — `capturedHandle`, `disposeGlobals` — exist
	-- because `activeCapture` and the cursor hints are MUTABLE UPVALUES and cannot
	-- be shared by reference the way a record table is.
	local pointer = screen_pointer.new({ handlesByPath = handlesByPath })
	adapter.setActivateHandler = pointer.setActivateHandler
	adapter.setPointerHandlers = pointer.setPointerHandlers
	adapter.setScrollHandler = pointer.setScrollHandler
	adapter.connectionCensus = pointer.connectionCensus
	local pointerActivateMeta = pointer.pointerActivateMeta
	local connectPointerBegan = pointer.connectPointerBegan
	local endCapture = pointer.endCapture
	local capturedHandle = pointer.capturedHandle
	local disposeGlobalPointerState = pointer.disposeGlobals
	local releaseCursorHint = pointer.releaseCursorHint

	-- ===== THE SCROLL SUBSYSTEM (src/client/screen_scroll_indicators) =====
	--
	-- native scroll host seam (the native substrate; spikes m1/m2): the
	-- solver's content extent becomes the engine canvas; the ENGINE owns the
	-- live offset (wheel, touch momentum, elastic, bars); observeScroll reports
	-- engine-driven CanvasPosition changes back to the framework (windowing);
	-- setScrollPosition is the framework's programmatic keep-visible write.
	-- On the fallback path (forceScrollFallback / non-ScrollingFrame instance)
	-- these degrade to no-ops and the node stays a proven clip-only host.
	--
	-- Constructed HERE, where the code it replaced stood, and the three methods are
	-- bound onto `adapter` under their original names — the contract
	-- (src/render/target_contract) is unmoved. `scrollIndicatorState` is passed BY
	-- REFERENCE because the create path above reads `.policy` at instance birth.
	local scrollIndicators = screen_scroll_indicators.new({
		adapter = adapter,
		handlesByPath = handlesByPath,
		indicatorState = scrollIndicatorState,
		scrollBarThickness = SCROLL_BAR_THICKNESS,
		forceScrollFallback = forceScrollFallbackMode,
	})
	adapter.setScrollIndicatorPolicy = scrollIndicators.setScrollIndicatorPolicy
	adapter.setScrollRegion = scrollIndicators.setScrollRegion
	adapter.setScrollPosition = scrollIndicators.setScrollPosition

	-- readable offset (A-SV1): the ENGINE co-authors CanvasPosition, so the
	-- framework reads the live value rather than caching one of its own. This
	-- is what makes the shared scroll-to-visible substrate correct after a user
	-- fling the framework never saw.
	-- effective-target floor (B-BTN3): the framework asks for an expanded HIT area
	-- for a sub-floor control. Realised as a transparent expander BEHIND the
	-- control (lower ZIndex) that forwards activation to it, so the control's own
	-- visual rect is untouched and the control still wins where they overlap.
	-- `nil` removes the expander.
	-- hidden subtrees (A-AL1): a losing ViewThatFits candidate keeps its MOUNT so a
	-- resize re-chooses without rebuilding, but it must not paint. Visible=false
	-- hides the whole subtree in one write and is not a styled property, so it does
	-- not fight the sheet.
	-- ELIDED NODES: visibility is applied PER NODE in this flat tree, so hiding a node
	-- that owns no engine object hides nothing its children were not already told. The
	-- value is recorded in case the node later materialises.
	function adapter.setVisible(handle: any, visible: boolean)
		if handle.elided == true then
			handle.pendingVisible = visible
			return
		end
		handle.instance.Visible = visible
		-- the rich-skinning v2 decision: the expander is a SIBLING of its control (it has to be, so the
		-- control keeps winning where they overlap), which means the host's Visible
		-- does not reach it by parentage. Carry it explicitly: an activation surface
		-- must never outlive the visibility of the thing it activates. This is the
		-- structural half of the fix — the renderer also stops asking for hit
		-- geometry for a hidden node, but a future caller cannot reopen the class
		-- through this seam.
		if handle.hitExpander ~= nil then
			handle.hitExpander.Visible = visible
		end
	end

	--[[ EVERYTHING THE EXPANDER OWES ITS HOST, in one place (review F1).

		`FacetHitExpander` is a second, separate `GuiButton` — a sibling at
		`hostZ - 1`, so the control keeps winning where the two overlap — and every
		fact about the host that a consumer might read off a button has to be
		carried to it explicitly. `Visible` and `ZIndex` already are, each at its own
		seam. These two are the rest:

		  the declared sensory verb   or a consumer reads the band as UNDECLARED and
		                              gives it the generic press sensation, so a
		                              control declared `none` is silent on its face
		                              and felt in its band;
		  Active / Interactable       or a DISABLED control's band still advertises a
		                              press it will not deliver.

		Read off the host rather than passed in, so there is one truth and this can
		be called from any seam that changes either — and so a newly built expander
		can seed itself from a host that was configured before it existed. ]]
	local function mirrorToHitExpander(handle: any)
		local expander = handle.hitExpander
		local instance = handle.instance
		if expander == nil or instance == nil then
			return
		end
		pcall(function()
			expander:SetAttribute(ACTIVATION_FEEDBACK_ATTRIBUTE, instance:GetAttribute(ACTIVATION_FEEDBACK_ATTRIBUTE))
			expander.Active = instance.Active
			expander.Interactable = instance.Interactable
		end)
	end

	-- THE PER-CONTROL SENSORY VERB (director request 2026-08-13;
	-- `src/render/target_contract.luau`'s `setActivationFeedback`). An ATTRIBUTE,
	-- for the same reason `Facet_PaintClaims` is one: it is a fact about the node
	-- that something outside the renderer needs to read, and an attribute is the
	-- engine's own channel for exactly that. `src/client/haptics.luau` reads it and
	-- assigns `GuiButton.PressHapticEffect` accordingly — this adapter plays
	-- nothing and knows nothing about haptics.
	--
	-- A NIL VERB CLEARS IT. The renderer pushes the nil deliberately (recycling),
	-- and `SetAttribute(name, nil)` is the engine's own removal, so a control that
	-- adopts a commit button's instance does not adopt its sensation. Deliberately
	-- NOT `ensureInstance`: an elided node has no press to feel, so materialising
	-- one to carry an attribute nothing will read would be pure cost.
	function adapter.setActivationFeedback(handle: any, verb: string?)
		local instance = handle.instance
		if instance == nil then
			return
		end
		pcall(function()
			instance:SetAttribute(ACTIVATION_FEEDBACK_ATTRIBUTE, verb)
		end)
		-- ...AND THE EXPANDER, for the same reason `Visible` and `ZIndex` are
		-- carried explicitly (rich-skinning v2): it is a SIBLING, so nothing about the host
		-- reaches it by parentage, and it is a `GuiButton` a haptics consumer will
		-- sweep and decorate on its own. Left unmirrored it read as UNDECLARED — so
		-- a control declared `none` was silent on its face and buzzed in the 44px
		-- band outside it, which is exactly where a thumb lands on a small control
		-- (release-candidate review F1).
		mirrorToHitExpander(handle)
	end

	-- a hit rect needs a real object, so an elided node materialises here
	function adapter.setHitRect(handle: any, rect: any)
		ensureInstance(handle)
		local instance = handle.instance
		if rect == nil then
			handle.hitRectWant = nil
			dropHitExpander(handle)
			return
		end
		handle.hitRectWant = rect
		local expander = handle.hitExpander
		if expander == nil then
			expander = Instance.new("TextButton")
			expander.Name = "FacetHitExpander"
			expander.Text = ""
			expander.AutoButtonColor = false
			expander.BackgroundTransparency = 1
			expander.BorderSizePixel = 0
			expander.Selectable = false -- Facet's focus graph owns focus, not this
			expander.ZIndex = instance.ZIndex - 1
			-- born at the host's CURRENT visibility, so it cannot flash live for a
			-- control that is already hidden (rich-skinning v2)
			expander.Visible = instance.Visible
			expander.Parent = instance.Parent
			-- the SAME meta a press on the control itself carries, from its own
			-- InputObject (redteam item 2, HIGH — writeup at `pointerActivateMeta`)
			expander.Activated:Connect(function(inputObject: InputObject)
				if
					handle.activate ~= nil
					and handle.instance.Interactable ~= false
					-- ...and never activate a control the player cannot see
					and handle.instance.Visible
				then
					handle.activate(pointerActivateMeta(inputObject))
				end
			end)
			handle.hitExpander = expander
			-- born carrying its host's declared verb and disabled state, exactly as
			-- it is born at its host's visibility: a control configured before its
			-- expander existed must not get a band that disagrees with its face
			mirrorToHitExpander(handle)
			-- ...AND THE HOST'S POINTER GESTURE, for a control that has one (see
			-- `beginPointerCapture`'s header). `Activated` alone covers the tappable
			-- family only; a pointer zone's expander was inert without this, which is
			-- the whole 26px dead band the ruling above exists to close.
			if handle.pointer ~= nil and handle.hitExpanderPointerConn == nil then
				handle.hitExpanderPointerConn = connectPointerBegan(handle, expander, handle.pointer)
			end
		end
		-- re-base by the clip host exactly as applyRect does (verifier finding V11).
		-- The solver rect is WINDOW space; a child of a clip host is positioned
		-- relative to that host, so using the raw rect put the invisible activation
		-- surface off by the host origin for every sub-floor control inside a
		-- ScrollView, a clipped container, or a popup panel. It is the SHARED
		-- placement path (rich-skinning v2) so a host rect that arrives after this call
		-- re-bases the expander with the control instead of leaving it behind.
		applyHitExpander(handle)
	end

	function adapter.getScrollPosition(handle: any): { x: number, y: number }?
		local instance = handle.instance
		if instance == nil or not instance:IsA("ScrollingFrame") then
			return nil
		end
		local p = instance.CanvasPosition
		return { x = p.X, y = p.Y }
	end

	--[[ AN ELIDED HOST HAS NO INSTANCE TO OBSERVE (live showcase, 2026-08-13) ──
		Every function in this scroll seam already degrades to a no-op when the
		handle's instance is not a `ScrollingFrame` — that is the documented
		contract ("An adapter without these degrades to the clip-only fallback...
		the renderer feature-detects and never crashes", target_contract.luau) —
		and the four `indicator*` helpers above spell the test the same way. These
		four public entry points wrote `not instance:IsA(...)` and left the NIL
		case to throw.

		A nil instance is not hypothetical: the renderer ELIDES a node that paints
		nothing (`handle.elided`, no instance created), and a `Table` built with
		`scrolls = false` publishes `<root>/Main/Body` from `api.scrollPath()`
		regardless — that node is a plain block, so it is elided. The gallery
		bootstrap then auto-binds it, `observeScroll` indexed nil, and the
		SHIPPED playlist example logged "'Playlist table' failed to mount:
		screen_target:3338: attempt to index nil with 'IsA'" on the real client
		with the whole mount abandoned at that point. Reproduced on the live
		showcase place both with and without this round's `rowActions`, so it
		predates them.

		The headless suite structurally could not see it: `fake_target`'s handle
		IS the node table, so `handle.instance` never enters the picture at all,
		and its own `observeScroll` accepted the bind happily. The nil guard is
		the fix; whether a block Table should publish a scroll path it has no
		host for is the separate, larger question, recorded in ui_todo.
	]]
	function adapter.observeScroll(handle: any, fn: (pos: { x: number, y: number }) -> ()): () -> ()
		local instance = handle.instance
		if instance == nil or not instance:IsA("ScrollingFrame") then
			return function() end
		end
		local conn = instance:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			local p = instance.CanvasPosition
			fn({ x = p.X, y = p.Y })
		end)
		return function()
			conn:Disconnect()
		end
	end

	-- native drag acquisition (the native substrate; spike m3-dragdetector):
	-- attaches a UIDragDetector in CustomOffset mode so the DETECTOR never
	-- writes Position (Facet's renderer keeps that authority — the default
	-- Offset mode would fight it, measured in the spike). The engine owns
	-- acquisition + cross-input motion; handlers receive screen-space
	-- positions and feed the PURE drag-session model (src/input/drag_session).
	-- Capability-gated: engines without the class keep the raw pointer-capture
	-- fallback (setPointerHandlers) — consumers feature-detect the return.
	local hasUIDragDetector = (function()
		local ok, probe = pcall(Instance.new, "UIDragDetector")
		if ok then
			probe:Destroy()
		end
		return ok
	end)()
	function adapter.setDragDetector(
		handle: any,
		handlers: {
			onStart: ((pos: { x: number, y: number }) -> ())?,
			-- totalOffset = the CUMULATIVE DragUDim2 since DragStart (engine truth
			-- 2026-07-23) — never a per-frame delta (verifier F5)
			onContinue: ((pos: { x: number, y: number }, totalOffset: { x: number, y: number }) -> ())?,
			onEnd: ((pos: { x: number, y: number }) -> ())?,
		}
	): (() -> ())?
		if not hasUIDragDetector or opts ~= nil and (opts :: any).forceDragFallback == true then
			return nil
		end
		local instance = handle.instance
		if not instance:IsA("GuiObject") then
			return nil
		end
		local detector = Instance.new("UIDragDetector")
		detector.ResponseStyle = Enum.UIDragDetectorResponseStyle.CustomOffset
		-- ENGINE TRUTH (live drive 2026-07-23): DragStart/Continue/End pass a
		-- **Vector2** in the detector's LayerCollector coordinate space — for
		-- Facet's IgnoreGuiInset=true roots that IS the renderer's window
		-- space, so no inset correction applies (a default-inset gui reports
		-- inset-subtracted coords instead — the spike place matched injection
		-- coords for exactly that reason). Tolerate a UDim2 defensively in
		-- case the surface changes again.
		local function toPos(p: any): { x: number, y: number }
			if typeof(p) == "Vector2" then
				return { x = p.X, y = p.Y }
			end
			return { x = p.X.Offset, y = p.Y.Offset }
		end
		local connections = {
			detector.DragStart:Connect(function(p: any)
				if handlers.onStart then
					handlers.onStart(toPos(p))
				end
			end),
			detector.DragContinue:Connect(function(p: any)
				if handlers.onContinue then
					local d = detector.DragUDim2
					handlers.onContinue(toPos(p), { x = d.X.Offset, y = d.Y.Offset })
				end
			end),
			detector.DragEnd:Connect(function(p: any)
				if handlers.onEnd then
					handlers.onEnd(toPos(p))
				end
			end),
		}
		detector.Parent = instance
		handle.dragDetector = detector
		return function()
			for _, c in connections do
				c:Disconnect()
			end
			detector:Destroy()
			handle.dragDetector = nil
		end
	end

	--[[ THE POINTER'S SECONDARY BUTTON (navigation-and-menus D2) — the mouse half
		of the context-menu construct. `InputBegan` on the node's own instance, filtered to
		`MouseButton2`, which is the one input type the framework's primary-activate
		path never claims: `setActivateHandler` rides `Activated`, and a
		`GuiButton`'s `Activated` fires for the PRIMARY button and touch only, so
		these two channels cannot double-fire on one press.

		IT OBSERVES, IT DOES NOT SINK, exactly as the disclosure zones do
		(`enableDisclosure` above): a right-click that opens a menu leaves whatever
		the node already did with the left button entirely alone.

		`gameProcessedEvent` is deliberately NOT consulted — this connection is on
		the GuiObject itself, so the engine already decided the press landed here.
		Physical proof is a PENDING_PHYSICAL row: Studio's injected pointer
		arrives as `Touch`, not `MouseButton2`, so a headless or emulator pass can
		prove the wiring and never the arbitration. ]]
	function adapter.setSecondaryActivate(handle: any, fn: () -> ()): () -> ()
		local instance = handle.instance
		if not instance:IsA("GuiObject") then
			return function() end
		end
		local connection = instance.InputBegan:Connect(function(input: any)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				fn()
			end
		end)
		return function()
			connection:Disconnect()
		end
	end

	-- native touch gestures (the native substrate; corrections §2): the
	-- ENGINE recognizes; Facet normalizes into stable value objects
	-- (src/input/touch_gestures) and composes/arbitrates purely. Connection is
	-- proven headless+Studio; FIRING requires real touch (VIM touch injection
	-- is RobloxScript-locked; emulator not MCP-drivable) — ledger row the native substrate.
	function adapter.setTouchGestureHandlers(handle: any, onGesture: (gesture: any) -> ()): () -> ()
		local instance = handle.instance
		if not instance:IsA("GuiObject") then
			return function() end
		end
		local touch_gestures = require(script.Parent.Parent.input.touch_gestures) :: any
		-- `normalize(kind, args)` reads `args` POSITIONALLY — it is the engine
		-- callback's argument list, in the engine's order, not a record (the seam rule:
		-- passing named keys made a[1]..a[4] nil, so every gesture a device
		-- delivered normalized to `{ kind, state = "none", positions = {} }` with
		-- the translation/velocity/scale/rotation/direction dropped). The engine's
		-- own values go through untouched: the module reads `Vector2`/`EnumItem`
		-- userdata as well as the headless table fakes.
		--   TouchTap(positions) · TouchLongPress(positions, state)
		--   TouchPan(positions, totalTranslation, velocity, state)
		--   TouchPinch(positions, scale, velocity, state)
		--   TouchRotate(positions, rotation, velocity, state)
		--   TouchSwipe(direction, numberOfTouches)
		local connections = {
			instance.TouchTap:Connect(function(positions)
				onGesture(touch_gestures.normalize("tap", { positions }))
			end),
			instance.TouchLongPress:Connect(function(positions, state)
				onGesture(touch_gestures.normalize("longPress", { positions, state }))
			end),
			instance.TouchPan:Connect(function(positions, totalTranslation, velocity, state)
				onGesture(touch_gestures.normalize("pan", { positions, totalTranslation, velocity, state }))
			end),
			instance.TouchPinch:Connect(function(positions, scale, velocity, state)
				onGesture(touch_gestures.normalize("pinch", { positions, scale, velocity, state }))
			end),
			instance.TouchRotate:Connect(function(positions, rotation, velocity, state)
				onGesture(touch_gestures.normalize("rotate", { positions, rotation, velocity, state }))
			end),
			instance.TouchSwipe:Connect(function(direction, numberOfTouches)
				onGesture(touch_gestures.normalize("swipe", { direction, numberOfTouches }))
			end),
		}
		return function()
			for _, c in connections do
				c:Disconnect()
			end
		end
	end

	-- engine-selection bridge (the native substrate; spike m9): mirrors the
	-- LOGICAL focus to GuiService.SelectedObject for an OPTED-IN modal only
	-- (the renderer gates the calls). Measured constraints honored here: the
	-- mirrored instance must be Selectable=true while selected (the engine
	-- warns and REASSIGNS selection set on a non-selectable object) and the
	-- previous instance's Selectable is restored so nothing stays natively
	-- navigable after the mirror moves. nil clears selection entirely.
	-- restore the ORIGINAL Selectable when the mirror moves off an instance
	-- (verifier F3: TextFields are intrinsically Selectable for native A-press
	-- capture — hardcoding false would silently strip that). NOTE for the
	-- physical intrinsically-Selectable instances (TextField) give
	-- the engine's own navigator a second target while bridged — the pad test
	-- must watch for engine self-navigation onto them (review packet).
	local bridgeSelected: { handle: any, wasSelectable: boolean }? = nil
	function adapter.setEngineSelection(handle: any?)
		if bridgeSelected ~= nil and bridgeSelected.handle.instance ~= nil then
			local record = bridgeSelected
			pcall(function()
				record.handle.instance.Selectable = record.wasSelectable
			end)
			if nativeMode then
				-- restore the hover gate on the previously bridged node
				record.handle.nativeBridgeSelected = nil
				syncTags(record.handle)
			end
		end
		bridgeSelected = nil
		if handle ~= nil and handle.instance:IsA("GuiObject") then
			bridgeSelected = { handle = handle, wasSelectable = handle.instance.Selectable }
			handle.instance.Selectable = true
			GuiService.SelectedObject = handle.instance
			if nativeMode then
				-- platform verifier 2026-07-24: engine selection sets
				-- GuiState=Hover (native-substrate m9), so on a pointer-live
				-- session a bridged node would paint the :Hover fill. The
				-- bridge suppresses the pointer-live tag while it owns the
				-- node — Facet's focus visual is the selection affordance;
				-- hover stays a POINTER affordance.
				handle.nativeBridgeSelected = true
				syncTags(handle)
			end
		else
			GuiService.SelectedObject = nil
		end
	end

	-- §17 Phase 5 text-entry seam (target_contract OPTIONAL setTextInputHandlers):
	-- wire the engine TextBox's native events to the control's handlers (engine ->
	-- model). The reverse direction (model -> engine: CaptureFocus/ReleaseFocus,
	-- .Text, .PlaceholderText) rides the ordinary setProp path under binding
	-- authority. handlers = { onTextChanged(text), onFocusGained(path),
	-- onFocusLost(reason) }, reason ∈ "enter" | "focusLost" | "cancel".
	function adapter.setTextInputHandlers(handle: any, handlers: any)
		local instance = handle.instance
		if not instance:IsA("TextBox") then
			return
		end
		handle.textHandlers = handlers
		handle.lastModelText = handle.lastModelText or instance.Text
		-- engine text changes -> onTextChanged. Fires on EVERY .Text mutation
		-- including our own reconcile writes (facts §4) and DEFERRED, so a boolean
		-- guard can't gate them (see writeFieldText). Skip only the echo of the
		-- model's own value; fire on genuine user divergence.
		if handlers.onTextChanged then
			handle.textChangedConn = instance:GetPropertyChangedSignal("Text"):Connect(function()
				if instance.Text == (handle.lastModelText or "") then
					return
				end
				handlers.onTextChanged(instance.Text)
			end)
		end
		-- engine focus (native tap / gamepad A / our own CaptureFocus) ->
		-- onFocusGained. Idempotent in the control (beginEditing), so a
		-- model-initiated CaptureFocus re-firing Focused is absorbed — this is the
		-- direct-native-tap path that drives the model INTO editing.
		if handlers.onFocusGained then
			-- pass the node's full path: native-tap focus never routes through
			-- handleActivate, so the control learns its path (for keep-visible)
			-- only from this seam (F1). handle.path is set by create().
			handle.focusedConn = instance.Focused:Connect(function()
				handlers.onFocusGained(handle.path)
			end)
		end
		-- engine focus loss -> onFocusLost(reason). enterPressed is the canonical
		-- commit across physical + on-screen keyboards. A ButtonB/Escape signature
		-- on the causing input is the cancel path — load-bearing when NO
		-- actionSystem is injected (the control's ButtonB edit-context cancel is
		-- inactive then); with an actionSystem the context ends editing first and
		-- this arrives idempotent. Escape is core-reserved (D1) — reported as
		-- cancel per the contract if it ever surfaces as the causing input.
		if handlers.onFocusLost then
			handle.focusLostConn = instance.FocusLost:Connect(function(enterPressed: boolean, input: InputObject?)
				local reason = "focusLost"
				if input ~= nil and (input.KeyCode == Enum.KeyCode.ButtonB or input.KeyCode == Enum.KeyCode.Escape) then
					reason = "cancel"
				elseif enterPressed then
					reason = "enter"
				end
				handlers.onFocusLost(reason)
			end)
		end
		-- mobile / console on-screen-keyboard return: focus may still be held, so
		-- force the canonical commit through FocusLost.enterPressed (research F9).
		-- pcall-guarded: the member is absent on very old engines.
		pcall(function()
			handle.oskReturnConn = (instance :: any).ReturnPressedFromOnScreenKeyboard:Connect(function()
				if instance:IsFocused() then
					instance:ReleaseFocus(true)
				end
			end)
		end)
	end

	-- pointer hover layer (UI-PARADIGM-001, matrix R§7): wire MouseEnter to the
	-- node's hover fill. Called by the renderer ONLY for interactive nodes when
	-- the pointer class is live — a pure-touch device never reaches here, so no
	-- hover wiring is allocated. MouseLeave (resting fill + pressed-dip recovery)
	-- is wired unconditionally in wireInteractiveStates and handles the exit.
	function adapter.enableHover(handle: any)
		local instance = handle.instance
		if nativeMode then
			-- native: the pointer-live decision becomes a TAG — hover
			-- rules are compound-gated on it (.facet-pointer-live:Hover), so the
			-- sheet can only paint hover where the renderer declared a live
			-- pointer class. No connection is allocated; the engine owns the
			-- hover state itself (GuiState).
			if instance:IsA("GuiObject") and handle.nativeInteractive == true then
				handle.nativePointerLive = true
				syncTags(handle)
			end
			return
		end
		if handle.applyHoverFill == nil or not instance:IsA("GuiObject") then
			return
		end
		if handle.hoverStateConn ~= nil then
			return
		end
		handle.hoverStateConn = instance.MouseEnter:Connect(function()
			handle.applyHoverFill()
		end)
	end

	-- FULL-VALUE DISCLOSURE ENGAGEMENT (Step 8.5). The disclosed Text
	-- node itself is the zone: MouseEnter/Leave feed the presenter's hover dwell,
	-- and a stationary touch held past the threshold feeds its long-press seam.
	-- Enter/Leave fire on any visible GuiObject regardless of Active, so the
	-- label keeps sinking nothing — engagement observes input, it never claims
	-- it (which is also why a long-press release still activates the row under
	-- the label: the plate is a preview, not a capture; recorded for the
	-- physical-device row). Connections live on the label instance and die with
	-- it; the census slots below keep them countable.
	local DISCLOSE_LONG_PRESS_S = 0.4
	local DISCLOSE_SLOP_PX = 12
	function adapter.enableDisclosure(handle: any, callbacks: any)
		local instance = handle.instance
		if not instance:IsA("GuiObject") then
			return
		end
		-- MERGE, don't one-shot (architecture review F-5): a capability that
		-- turns on mid-session re-wires already-mounted labels, so each half
		-- guards itself and a later call may add the half a mount-time gate
		-- withheld
		if callbacks.hover ~= nil and handle.discloseEnterConn == nil then
			handle.discloseEnterConn = instance.MouseEnter:Connect(function()
				callbacks.hover(true)
			end)
			handle.discloseLeaveConn = instance.MouseLeave:Connect(function()
				callbacks.hover(false)
			end)
		end
		if callbacks.longPress ~= nil and handle.discloseTouchConn == nil then
			local pressToken = 0
			handle.discloseTouchConn = instance.InputBegan:Connect(function(inputObject: InputObject)
				if inputObject.UserInputType ~= Enum.UserInputType.Touch then
					return
				end
				pressToken += 1
				local token = pressToken
				local start = inputObject.Position
				local live = true
				local fired = false
				local moveConn: RBXScriptConnection? = nil
				local endConn: RBXScriptConnection? = nil
				local destroyingConn: RBXScriptConnection? = nil
				local function finish(reason: string)
					if not live then
						return
					end
					live = false
					if moveConn ~= nil then
						moveConn:Disconnect()
					end
					if endConn ~= nil then
						endConn:Disconnect()
					end
					if destroyingConn ~= nil then
						destroyingConn:Disconnect()
					end
					-- a press that dies with its label must not dismiss ANOTHER
					-- label's plate (platform review F7): the label's own death
					-- fires no release
					if fired and reason ~= "drag" and reason ~= "destroyed" then
						callbacks.longPress(false)
					end
				end
				-- ONE FINGER, THIS FINGER (platform review F6): a touch
				-- InputObject is stable for the life of its contact, so both
				-- global listeners filter to the object that began the press —
				-- a second finger panning the HUD must neither cancel the press
				-- nor dismiss the plate it raised
				moveConn = UserInputService.InputChanged:Connect(function(moveObject: InputObject)
					if moveObject ~= inputObject then
						return
					end
					local dx = moveObject.Position.X - start.X
					local dy = moveObject.Position.Y - start.Y
					if math.abs(dx) + math.abs(dy) > DISCLOSE_SLOP_PX then
						-- a moving finger is a scroll/drag, never a press: if the
						-- plate already showed, take it down with the movement
						local wasFired = fired
						finish("drag")
						if wasFired then
							callbacks.longPress(false)
						end
					end
				end)
				endConn = UserInputService.InputEnded:Connect(function(endObject: InputObject)
					if endObject == inputObject then
						finish("release")
					end
				end)
				-- the label dying mid-press ends the press silently; the timer
				-- below then finds `live` false and does nothing (the task.delay
				-- itself cannot be cancelled, so this is what defuses it)
				destroyingConn = instance.Destroying:Connect(function()
					finish("destroyed")
				end)
				task.delay(DISCLOSE_LONG_PRESS_S, function()
					if live and token == pressToken then
						fired = true
						callbacks.longPress(true)
					end
				end)
			end)
		end
	end

	-- focus ring (design §8.4: focus is never color-only — ring + hover fill).
	-- profile is the env distanceProfile (UI-PARADIGM-003, matrix D.4): on a
	-- "ten-foot" (Large) display the ring thickens AND the control scales up so
	-- focus is unmistakable across a room; "near" (or nil) keeps the hairline
	-- ring with no scale — byte-identical to the pre-expansion behavior.
	function adapter.setFocusVisual(handle: any, on: boolean, profile: string?)
		local instance = handle.instance
		if not instance:IsA("GuiObject") then
			return
		end
		local strong = profile == "ten-foot"
		-- remembered so a live theme swap can repaint whatever is focused right
		-- now (refreshFocusVisuals). Cleared on blur, so the set is exactly the
		-- live focus visuals and never a growing list of everything ever focused.
		if on then
			focusedHandles[handle] = profile or ""
		else
			focusedHandles[handle] = nil
		end
		-- grips are thin slivers: a ring alone is nearly invisible, which read
		-- as "focus went nowhere" in the director's hand test (2026-07-20) —
		-- focused grips fill with accent
		if handle.class == "Grip" then
			if nativeMode then
				-- native: the explicit write would permanently defeat the
				-- "Frame default" rule (arch verifier 2026-07-24) — the accent
				-- fill rides the "Grip focus" tag rule instead (theme-aware)
				handle.nativeGripFocus = on
				syncTags(handle)
			else
				instance.BackgroundTransparency = if on then 0 else 1
				instance.BackgroundColor3 = focusColor()
			end
		end
		-- WHERE THE VISUAL HANGS (director fix round 2026-07-25). Not the node —
		-- the DRAWN ART, when there is any. See `focusArtHost`: a Button carries a
		-- UIPadding so its engine label clears the edges, that padding insets the
		-- decoration because a decoration is a child, and a ring on the node
		-- therefore left a band of empty air on each side of the plate it was
		-- outlining (measured live: a 53px stepper button, a 29px plate).
		-- Hit geometry is untouched — it was never this instance's Size.
		local host: GuiObject = if on then focusArtHost(handle) or instance else instance
		-- a glow whose host was destroyed under it (a swap that removed the art)
		-- is GONE: a Destroy()'d instance cannot be re-parented, and its census
		-- entry would otherwise never fall
		if handle.focusGlow ~= nil and handle.focusGlow.Parent == nil then
			handle.focusGlow = nil
			chromeState.noteFocusGlow(false)
		end
		local previous: GuiObject? = handle.focusVisualHost
		if previous ~= nil and previous ~= host then
			-- the art appeared, moved or was destroyed under a focused node: clear
			-- the old host before deciding, or a swap leaves two rings
			local stale = previous:FindFirstChild("FocusRing")
			if stale ~= nil then
				stale:Destroy()
			end

			if handle.focusGlow ~= nil and handle.focusGlow.Parent == previous then
				handle.focusGlow:Destroy()
				handle.focusGlow = nil
				chromeState.noteFocusGlow(false)
			end
		end
		handle.focusVisualHost = if on then host else nil
		local ringFloat: Frame? = handle.focusRingFloat
		if ringFloat ~= nil and ringFloat.Parent == nil then
			handle.focusRingFloat = nil
			ringFloat = nil
		end
		local ring = host:FindFirstChild("FocusRing")
			or (if ringFloat ~= nil then ringFloat:FindFirstChild("FocusRing") else nil)
		local glow = handle.focusGlow
		-- WHICH TREATMENT. `glow` needs the engine to have UIShadow at all; on an
		-- engine (or a headless target) without it the package's glow degrades to
		-- the ring rather than to nothing, because §8.4 says focus is never
		-- optional. Switching treatments tears the other one down first, so a
		-- swap from ring to glow while a control is focused cannot leave both.
		local wantGlow = on and focusTreatment.kind == "glow" and hasUIShadow
		if ring ~= nil and (not on or wantGlow) then
			ring:Destroy()
			ring = nil
		end
		if ringFloat ~= nil and (not on or wantGlow) then
			ringFloat:Destroy()
			handle.focusRingFloat = nil
			ringFloat = nil
		end
		if glow ~= nil and (not on or not wantGlow) then
			glow:Destroy()
			handle.focusGlow = nil
			glow = nil
			chromeState.noteFocusGlow(false)
		end
		if on and wantGlow then
			-- ONE UIShadow child, named so a Studio reader can tell a focus glow
			-- from a slot shadow at a glance. The ten-foot profile scales blur UP
			-- and transparency DOWN, which is the glow's answer to the same §8.4
			-- requirement the ring answers by thickening.
			local spec = chrome_slots.focusShadowSpec(focusTreatment.recipe, strong)
			local okSpec, normalized = pcall(styling.normalizeShadow, spec, style)
			if okSpec then
				if glow == nil then
					glow = Instance.new("UIShadow" :: any)
					glow.Name = "FocusGlow"
					handle.focusGlow = glow
					chromeState.noteFocusGlow(true)
				end
				local g: any = normalized
				glow.BlurRadius = UDim.new(g.blurRadius.scale, g.blurRadius.offset)
				glow.Color = focusColor()
				glow.Transparency = g.transparency
				glow.Offset = UDim2.new(g.offset.x.scale, g.offset.x.offset, g.offset.y.scale, g.offset.y.offset)
				glow.Spread = UDim2.new(g.spread.x.scale, g.spread.x.offset, g.spread.y.scale, g.spread.y.offset)
				glow.ZIndex = g.zIndex
				glow.Enabled = true
				glow.Parent = host
			end
		end
		if on then
			local thickness = if strong then style.extra.tenFootFocusRingThickness else style.extra.focusRingThickness
			if not wantGlow then
				-- THE FLOAT RING (director round three, ROOT CAUSE). The instance
				-- tree is FLAT with ZIndexBehavior=Sibling, so on a stacked row:
				-- an OUTWARD Border ring paints in the neighbors' territory (the
				-- next row covers its bottom, the canvas clips its sides, only the
				-- top arc survived) and any ring parented UNDER the hit is covered
				-- by every higher-z sibling regardless of its own ZIndex. The one
				-- placement that works is a SIBLING of the row's instances: a
				-- transparent frame parented to the CLIP HOST itself, topmost-z,
				-- positioned over the focused rect and inset by the ring's own
				-- thickness so no scroll edge can cut it. It scrolls with the
				-- canvas because it lives in it; applyRect re-aims it when the
				-- row itself moves. Unclipped nodes keep the outward ring.
				local strokeParent: GuiObject = host
				-- ...AND ONLY UNDER A HOST THAT CROPS (ADR-0032). The float exists
				-- because a ring drawn under a clipping or buffered parent gets cut;
				-- a plain move-boundary host cuts nothing, so a node inside one keeps
				-- the ordinary outward ring rather than growing a second instance to
				-- solve a problem it does not have.
				if handle.instanceHost ~= nil and handle.instanceHost.crops and handle.instanceHost.instance ~= nil then
					local float = ringFloat
					if float == nil then
						float = Instance.new("Frame")
						float.Name = "FocusRingFloat"
						float.BackgroundTransparency = 1
						local corner = host:FindFirstChildOfClass("UICorner")
						if corner ~= nil then
							corner:Clone().Parent = float
						end
						float.Parent = handle.instanceHost.instance
						handle.focusRingFloat = float
					end
					local f = float :: Frame
					local rect = handle.windowRect
					local origin = handle.instanceHost.rect
					if rect ~= nil and origin ~= nil then
						f.Position = UDim2.fromOffset(rect.x - origin.x + thickness, rect.y - origin.y + thickness)
						f.Size = UDim2.fromOffset(rect.w - 2 * thickness, rect.h - 2 * thickness)
					end
					f.ZIndex = 9999
					strokeParent = f
				end
				if ring == nil then
					local stroke = Instance.new("UIStroke")
					stroke.Name = "FocusRing"
					-- THEMED, not the constant this used to capture: a package's
					-- own accent, live, so a parchment ring is ink-and-gold rather
					-- than Studio Neutral's blue
					stroke.Color = focusColor()
					stroke.Thickness = thickness
					stroke.Transparency = 0
					stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					stroke.Parent = strokeParent
				else
					(ring :: UIStroke).Thickness = thickness;
					(ring :: UIStroke).Color = focusColor()
				end
			end
			-- ten-foot: a dedicated UIScale lifts the focused control (kept
			-- separate from the pressed-dip uiScale so the two never fight). A
			-- near display never creates it, so resting geometry is untouched.
			-- LIFT CAP (director live find, Xbox emulator 2026-07-21): the lift
			-- is a CARD idiom — it applies only when the lifted bounds still fit
			-- the screen. A near-full-width surface (the playlist filter field:
			-- 1888 x 1.05 = 1982 > 1920) keeps the strong ring with NO scale,
			-- or it overflows the viewport. UIScale grows about the anchor
			-- (top-left in this stack), so the check is right/bottom edges.
			-- Measured pre-lift: FocusScale is 1 whenever this branch runs on a
			-- fresh focus (blur resets it below).
			local lift = false
			if strong then
				local screenGui = instance:FindFirstAncestorWhichIsA("ScreenGui")
				if screenGui ~= nil then
					-- bounds = the solved ROOT node's frame (the SAFE content rect,
					-- inside the overscan margins), not the raw canvas: a TV clips
					-- the margin, so a lift poking into it can vanish on real
					-- hardware. Matches the fake_target mirror exactly (its screen
					-- bounds are the root node's solved rect). Rendering is FLAT
					-- (siblings named by path), so the root is looked up by the
					-- path's first segment, never by ancestry.
					local rootSegment = string.match(handle.path or "", "^(/[^/]+)")
					local rootFrame = if rootSegment ~= nil then screenGui:FindFirstChild(rootSegment) else nil
					local boundsSource: GuiObject = if rootFrame ~= nil and rootFrame:IsA("GuiObject")
						then rootFrame
						else screenGui :: any
					local scale = style.extra.tenFootFocusScale
					local pos = instance.AbsolutePosition
					local size = instance.AbsoluteSize
					local boundsPos = boundsSource.AbsolutePosition
					local bounds = boundsSource.AbsoluteSize
					lift = pos.X + size.X * scale <= boundsPos.X + bounds.X
						and pos.Y + size.Y * scale <= boundsPos.Y + bounds.Y
				end
			end
			if strong and lift then
				local focusScale = handle.focusScale
				if focusScale == nil then
					focusScale = Instance.new("UIScale")
					focusScale.Name = "FocusScale"
					focusScale.Parent = instance
					handle.focusScale = focusScale
				end
				focusScale.Scale = style.extra.tenFootFocusScale
			elseif handle.focusScale ~= nil then
				handle.focusScale.Scale = 1
			end
		else
			if handle.focusScale ~= nil then
				handle.focusScale.Scale = 1
			end
		end
	end

	-- §17 Phase 5 TextField .Text write policy (research F4/F5/F7 + facts §4).
	-- The engine buffer is authoritative WHILE the user composes: never echo the
	-- model's per-keystroke value back onto a focused box (IME-corrupting). We
	-- write .Text only when it actually DIFFERS from the engine buffer — which is
	-- exactly the two legitimate cases: (a) not focused (any external/model set),
	-- and (b) focused-reconcile (maxLength clamp / cancel-revert produced a value
	-- the box does not yet hold). During plain composition the model value equals
	-- the buffer, so this is a no-op.
	--
	-- `lastModelText` is the VALUE-BASED re-entrancy guard the change-signal
	-- reader consults. A boolean "writing now" flag does NOT work: Roblox
	-- property-changed signals are DEFERRED (SignalBehavior.Deferred), so the
	-- flag is already reset by the time GetPropertyChangedSignal("Text") fires —
	-- proven live 2026-07-20 (the reconcile write leaked a spurious onTextChanged).
	-- Recording the authoritative text instead lets the reader skip the echo
	-- (box.Text == lastModelText) yet still fire on genuine user divergence.
	-- Recorded on EVERY model set (even the skipped no-op) so a later keystroke
	-- that returns the buffer to the model value is not mistaken for an echo.
	-- Cursor auto-clamps to the truncated end on a shorter rewrite (facts §4) —
	-- no manual CursorPosition needed.
	local function writeFieldText(handle: any, str: string)
		local box = handle.instance :: TextBox
		handle.lastModelText = str
		if box.Text ~= str then
			box.Text = str
		end
	end

	-- a property write needs a real object, so an elided node materialises here
	function adapter.setProp(handle: any, prop: string, value: any, _authority: string)
		ensureInstance(handle)
		local instance = handle.instance
		if prop == "surface" then
			if instance:IsA("GuiObject") then
				applySurface(instance, tostring(value), handle)
			end
		elseif prop == "role" then
			-- B-BTN2: on a BUTTON, `role` is the semantic role (default | cancel |
			-- destructive). Native mode emits a tag and the sheet's rule paints it;
			-- the fallback path writes the danger/cancel fill directly. Never a
			-- parallel paint-state system — the states below still own hover/press.
			if handle.class == "Button" then
				if nativeMode then
					handle.nativeButtonRole = if value == "default" then nil else value
					syncTags(handle)
				else
					local fill = if value == "destructive"
						then COLOR.danger
						elseif value == "cancel" then COLOR.surface
						else COLOR.control
					handle.roleFill = if value == "default" then nil else fill
					assertBespokePaint("BackgroundColor3")
					instance.BackgroundColor3 = fill
					if instance:IsA("TextButton") then
						assertBespokePaint("TextColor3")
						instance.TextColor3 = if value == "destructive"
							then COLOR.onDanger
							elseif value == "cancel" then COLOR.contentSecondary
							else COLOR.content
					end
				end
			elseif nativeMode and (instance:IsA("TextLabel") or instance:IsA("TextButton")) then
				-- native: the "Secondary text" tag rule owns the color
				handle.nativeRoleSecondary = value == "secondary"
				syncTags(handle)
			elseif instance:IsA("TextLabel") or instance:IsA("TextButton") then
				-- BOTH DIRECTIONS. `role` is a reactive prop, and the native path above
				-- already round-trips it through the tag; this fallback path used to
				-- write the receded colour and nothing else, so a label that flipped
				-- secondary -> content stayed grey for the rest of its life. A closed
				-- set whose paint is one-way is not a state, it is a latch.
				assertBespokePaint("TextColor3")
				instance.TextColor3 = if value == "secondary" then COLOR.contentSecondary else COLOR.content
			elseif handle.path2d ~= nil then
				-- Path stroke color rides the style role hint: never a raw
				-- color from screen code — and, since 2026-08-14, never the palette
				-- this target was CONSTRUCTED with either. A Path2D is adapter-owned
				-- paint in every mode (no rule can select one), so the role resolves
				-- against the LIVE theme; see screen_paint.applyPathRole.
				handle.pathRole = value
				applyPathRole(handle)
			end
		elseif prop == "points" then
			if handle.path2d ~= nil then
				handle.normPoints = value
				applyPathPoints(handle)
			end
		elseif prop == "thickness" then
			if handle.path2d ~= nil then
				handle.path2d.Thickness = value
			end
		elseif prop == "closed" then
			if handle.path2d ~= nil then
				handle.path2d.Closed = value == true
			end
		elseif prop == "clipChildren" then
			if value == true and instance:IsA("GuiObject") then
				instance.ClipsDescendants = true
				-- a node may ALREADY be a real parent (a fade group declares itself one
				-- at creation): `registerHost` is create-or-REUSE for exactly this
				-- order, because replacing the entry would strand every child already
				-- re-based against it
				registerHost(handle.path, instance, handle.windowRect, true)
			end
		elseif prop == "padding" then
			if handle.class == "Button" then
				local pad = instance:FindFirstChildOfClass("UIPadding")
				if pad ~= nil then
					-- PER-SIDE IS LEGAL AND ARRIVED AS A TABLE (found 2026-07-26 by the
					-- gallery picker's tight-vertical chip). `padding = { top = "xs" }`
					-- is an ordinary authored value on every container the schema
					-- declares, Button included, and this write passed it straight to
					-- `UDim.new`, which errors on a table — a crash on documented input.
					--
					-- The engine inset is HORIZONTAL by construction: the label centres
					-- inside the box the solver already reserved, so the vertical pair is
					-- spent on the node's SIZE and needs no instance. Sides that were not
					-- authored are 0, which is exactly what `solver.sides` measured them
					-- as — measure and paint cannot disagree about a side nobody wrote.
					local left, right = 0, 0
					if type(value) == "number" then
						left, right = value, value
					elseif type(value) == "table" then
						left = if type(value.left) == "number" then value.left else 0
						right = if type(value.right) == "number" then value.right else 0
					end
					pad.PaddingLeft = UDim.new(0, left)
					pad.PaddingRight = UDim.new(0, right)
					--[[ ...AND EVERY DECORATION THAT CANCELS THAT PADDING IS NOW STALE.
						A Button is CREATED with `style.space.s + 4` a side (below) and
						skinned at the end of `create`, so its decoration is full-bled for
						the class default; this write is where the authored number lands,
						and it used to leave the compensation pointing at the old one.

						MEASURED LIVE (Compact Pointer, the swipe tray's `Mark Read` plate,
						2026-08-13): default 12 vs authored 8 painted the decoration at
						[6.0 .. 97.0] for a plate at [10.0 .. 93.0] — 4px outside its own
						box a side — and the plate's left edge sits exactly on the Table
						body's clip edge, so the left border and both left corners were cut
						away. `refitFullBleed`'s own comment carries the full measurement. ]]
					refitFullBleed(handle)
				end
			elseif handle.class == "Text" and instance:IsA("TextLabel") then
				-- A PADDED `Text` LEAF (device report 2026-08-12, IMG_3691). The solver
				-- adds a Text's authored padding to its reserved box and then returns at
				-- the leaf without insetting anything — a container spends its padding
				-- by placing children at rect + padding, and a leaf has none — so the
				-- glyphs were drawn across the WHOLE padded box, flush against its
				-- leading edge. The showcase's stat tiles are the shape that shows it:
				-- a 27px plate holding a 15px label with 6px of padding a side, and the
				-- label sitting on the plate's own rounded corner.
				--
				-- ALL FOUR SIDES, unlike Button's horizontal-only pair: a Button centres
				-- its single line in the box the solver reserved, so its vertical
				-- padding is already spent on the node's size, while a Text can wrap,
				-- can be top/bottom aligned, and is the node whose own box this is. The
				-- padding written here is exactly the padding `contentSize` measured
				-- with, so measure and paint agree on every side.
				local pad = instance:FindFirstChildOfClass("UIPadding")
				local top, right, bottom, left = 0, 0, 0, 0
				if type(value) == "number" then
					top, right, bottom, left = value, value, value, value
				elseif type(value) == "table" then
					top = if type(value.top) == "number" then value.top else 0
					right = if type(value.right) == "number" then value.right else 0
					bottom = if type(value.bottom) == "number" then value.bottom else 0
					left = if type(value.left) == "number" then value.left else 0
				end
				-- an all-zero inset on a node that never had one materializes nothing:
				-- the instance budget stays exactly where it was for every unpadded
				-- label in the tree
				if pad == nil and (top ~= 0 or right ~= 0 or bottom ~= 0 or left ~= 0) then
					pad = Instance.new("UIPadding")
					pad.Parent = instance
				end
				if pad ~= nil then
					pad.PaddingTop = UDim.new(0, top)
					pad.PaddingRight = UDim.new(0, right)
					pad.PaddingBottom = UDim.new(0, bottom)
					pad.PaddingLeft = UDim.new(0, left)
					-- the same refit as the Button branch above, for the same reason: a
					-- `Text` can carry a surface and therefore a decoration, and this
					-- write can MATERIALISE a `UIPadding` where there was none, which
					-- turns a correct identity compensation into a stale zero
					refitFullBleed(handle)
				end
			end
		elseif prop == "shape" then
			-- THE CIRCLE BUTTON (feature round 2026-07-26). Applied FIRST of the
			-- style props (renderer STYLE_PROP_ORDER) so every chrome write after it
			-- sees the shape: `corner()` reads `handle.shape`, and the surface a
			-- Button declares arrives next.
			handle.shape = if value == "circle" then "circle" else nil
			if nativeMode then
				-- the pill and the rim are the sheet's phantom modifier rules — zero
				-- new instances on a flat theme, which is the whole reason the disc
				-- rides the radii machinery the slider thumb proved
				syncTags(handle)
			else
				-- fallback half: the real UICorner already exists (adapter.create
				-- wires a Button's interactive states before any prop arrives), so
				-- re-radius what is there rather than parenting a second modifier —
				-- the engine honours ONE UICorner and a second would be dead weight
				-- whose value nobody could predict.
				assertBespokePaint("CornerRadius")
				for _, child in instance:GetChildren() do
					if child:IsA("UICorner") then
						(child :: UICorner).CornerRadius = cornerRadiusFor(handle, style.radii.control)
					end
				end
			end
		elseif prop == "icon" then
			-- SEMANTIC ICON CONTENT (ADR-0020 R4) reached from a public prop. The
			-- control's own text is already the framework's ASCII glyph (the
			-- renderer's drawnButtonText), so this is an UPGRADE, not a dependency:
			-- it tells the chrome subsystem which semantic name to look for in the
			-- installed package, and a package with no art for it changes nothing.
			--
			-- The hint table may be FROZEN (chrome_slots.attachHint freezes it), so
			-- this composes a new one rather than writing through.
			local merged: { [string]: any } = {}
			if type(handle.decorationHint) == "table" then
				for k, v in handle.decorationHint do
					merged[k] = v
				end
			end
			merged.icon = if type(value) == "string" and value ~= "" then value else nil
			handle.decorationHint = merged
			-- syncChrome is the ONE reconcile entry point and drives syncIconArt
			syncChrome(handle)
		elseif prop == "compactLabel" then
			-- THE RAW-IMAGE COMPACT FORM (compact-label stage, 2026-07-27). Only the
			-- `image` form reaches here: the `text` form is just a shorter string on
			-- the ordinary label write, and the `icon` form is raised as an `icon`
			-- request so it goes through the R4 machinery above (theme art, tint
			-- role, the ASCII floor) rather than around it.
			--
			-- A raw content id has no semantic name, so nothing can resolve a tint
			-- role or a package override for it — which is exactly why the docs
			-- point authors at `icon` and call this the escape hatch. It is carried
			-- on the decoration hint as a per-view `image`, the rung-2 override the
			-- chrome subsystem already understands, so the picture is anchored and
			-- sized by the same code that draws every other managed image.
			--
			-- The renderer clears it (passes nil) the moment the full label fits
			-- again, so the picture never outlives the verdict that raised it.
			local merged: { [string]: any } = {}
			if type(handle.decorationHint) == "table" then
				for k, v in handle.decorationHint do
					merged[k] = v
				end
			end
			merged.image = if type(value) == "table" and type(value.image) == "string" then value.image else nil
			handle.decorationHint = merged
			syncChrome(handle)
		elseif prop == "shadow" then
			applyShadow(instance, value, handle)
		elseif prop == "gradient" then
			applyGradient(instance, value, handle)
		elseif prop == "corners" then
			applyCorners(instance, value)
		elseif prop == "stroke" then
			applyStroke(instance, value, handle)
		elseif prop == "tint" then
			-- THE CONTINUOUS-COLOUR CHANNEL. The renderer applies this LAST at
			-- creation and re-applies it after any write that repaints what it claimed
			-- (see the tail of this function), so the tint is always the final word on
			-- the property it owns.
			if value == nil then
				releaseTint(handle)
			else
				handle.tint = value
				applyTint(handle)
			end
		elseif prop == "scaleMode" then
			-- HOW THE PICTURE FILLS ITS BOX. `ScaleType` is sheet-owned in native mode
			-- (a skinned slot's rule sets it), so an authored one CLAIMS it — the same
			-- mechanism the tint uses, for the same reason: no rule can carry a
			-- per-node authored value.
			if instance:IsA("ImageLabel") then
				if value == nil then
					restorePaint(handle, "ScaleType")
				else
					local mapped = SCALE_MODE_ENGINE[tostring(value)]
					if mapped ~= nil then
						claimPaint(handle, "ScaleType")
						assertBespokePaint("ScaleType", handle)
						instance.ScaleType = mapped
					end
				end
			end
		elseif prop == "transform" then
			-- THE PRESENTATION TRANSFORM (ADR-0022 Decision 2; fixes the headless-green/device-wrong class — this
			-- branch simply did not exist, so every keep-visible shift was a headless
			-- green that never moved a device). The whole body is
			-- `screen_presentation.setTransform`, because it is the one writer of that
			-- module's `presentationCount`.
			setPresentationTransform(handle, value)
		elseif prop == "dragHeld" then
			-- THE HELD DRAG SOURCE (director round five). Native: the tag rides
			-- syncTags and the sheet's `.facet-drag-held` rule empties the label
			-- (TextTransparency is sheet-owned there — same channel as iconArt).
			-- Bespoke: the write is ours, so it is direct — with the node's own
			-- resting transparency restored on release.
			local held = value == true
			handle.dragHeld = held
			if nativeMode then
				syncTags(handle)
			elseif instance:IsA("TextButton") or instance:IsA("TextLabel") or instance:IsA("TextBox") then
				instance.TextTransparency = if held then 1 else 0
			end
		elseif prop == "transparency" then
			-- PRESENTATION TRANSPARENCY IS A GROUP FACT: one engine property, on a
			-- node that declared itself a fade group, that no style rule owns — so a
			-- subtree fade never contests native-sheet paint. The renderer refuses the
			-- write for an undeclared node, and this guard is the adapter's half of the
			-- same contract.
			if handle.canvasGroupInstance ~= nil then
				handle.canvasGroupInstance.GroupTransparency = if type(value) == "number"
					then math.clamp(value, 0, 1)
					else 0
			end
		elseif prop == "textAlign" then
			-- paint-only and reactive: an unset or unrecognised value falls back to
			-- Left, which is what this adapter hard-coded before the prop existed
			if instance:IsA("TextLabel") or instance:IsA("TextButton") then
				instance.TextXAlignment = TEXT_ALIGN_MAP[value] or Enum.TextXAlignment.Left
			end
		elseif prop == "textSize" then
			if instance:IsA("TextLabel") or instance:IsA("TextButton") then
				instance.TextSize = value -- layout authority in BOTH modes
				-- ...AND the Toggle's lifted label, which is the thing that
				-- actually draws that text (director round 9). It was pinned at 16
				-- from construction while the SOLVER measured the row at the
				-- theme's `body` size — classic-desktop measures "Music" at 13
				-- (28 px) and the engine drew it at 16 (35 px) into a 20 px box.
				-- Same accepted-and-ignored class as director defect 3, one
				-- control down.
				if handle.labelInstance ~= nil then
					handle.labelInstance.TextSize = value
				end
				if nativeMode then
					-- native: heading-scale emphasis rides the "Strong text" tag rule
					handle.nativeStrong = value >= style.type.heading
					syncTags(handle)
				elseif value >= style.type.heading then
					assertBespokePaint("TextColor3")
					instance.TextColor3 = COLOR.contentStrong
				end
			end
		elseif prop == "textFont" then
			-- THE TYPOGRAPHY ROLE'S FACE (F2, 2026-08-02). The renderer resolves the
			-- node's effective role against the SAME snapshot the solver measured with
			-- and hands the descriptor here, so the family/weight the engine draws is
			-- the family/weight the box was reserved for. Before this the adapter wrote
			-- one hardcoded face at creation and nothing ever moved it — which is why a
			-- `weight` PROP would have been the wrong shape: a face that reaches only
			-- one seam is exactly what `Text.font` was deprecated for.
			--
			-- NATIVE MODE MUST NOT WRITE IT. `FontFace` is sheet-owned
			-- (authority.nativeSheetOwned) and an explicit write permanently defeats the
			-- rule, so in native mode the role rides a `facet-type-<role>` TAG whose
			-- generated rule carries the same descriptor.
			local descriptor = if type(value) == "table" then value else nil
			if nativeMode then
				handle.typeRole = if descriptor ~= nil then descriptor.role else nil
				syncTags(handle)
			elseif descriptor ~= nil then
				local face = fontFaceFor(descriptor)
				if face ~= nil then
					if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
						assertBespokePaint("FontFace")
						instance.FontFace = face
					end
					-- ...and the Toggle's lifted label, for exactly the reason `textSize`
					-- reaches it: that instance is the thing that draws the text
					if handle.labelInstance ~= nil then
						assertBespokePaint("FontFace")
						handle.labelInstance.FontFace = face
					end
				end
			end
		elseif prop == "text" or prop == "label" then
			if handle.class == "TextField" and instance:IsA("TextBox") then
				writeFieldText(handle, tostring(value))
			elseif handle.labelInstance ~= nil then
				handle.labelInstance.Text = tostring(value)
			elseif instance:IsA("TextLabel") or instance:IsA("TextButton") then
				instance.Text = tostring(value)
			end
			-- ONE LINE FOR A WORD, WRAPPING FOR A PHRASE (director round 13,
			-- 2026-07-27: fantasy-parchment's Edit/Done toggle drew "Don" over
			-- "e"). A content-sized button is measured to EXACTLY its label, so a
			-- one-pixel disagreement with the engine's own measurement does not
			-- clip a pixel — it BREAKS THE WORD. A word has no legal break point,
			-- so an ellipsis is the honest degradation; a phrase has one, and the
			-- theme picker's "Classic Desktop" chips wrap to two lines on a narrow
			-- phone on purpose.
			--
			-- It rides the LABEL WRITE, not creation, because the label is a
			-- reactive binding: the table's own toggle flips Edit <-> Done, and
			-- both seams have to re-decide from the same string. The solver makes
			-- the identical call (renderer.luau `isSingleWord`).
			--
			-- GENERALISED TO EVERY TEXT NODE (director, 2026-07-27). This was
			-- gated on `handle.class == "Button"`, so a plain `UI.Text` — a table
			-- cell, a list row, any label — kept the creation default
			-- `TextWrapped = true` and had NO `TextTruncate` at all. The framework
			-- therefore had no opinion about how such a node degrades: with a box
			-- too small the engine was free to break a word or clip mid-character
			-- with no ellipsis, which is what the playlist's name column showed
			-- ("Neon Straightawa"). The rule was never Button-specific — breaking a
			-- WORD is damage wherever it happens — so the gate was the bug.
			--
			-- ...AND HALF THE RULE LIVES IN THE SOLVE (director ruling 5, 2026-08-13).
			-- "Has a legal break" is all this seam can see; whether the break can
			-- SUCCEED needs the drawable width, and a phrase wrapped into a column
			-- narrower than one of its own words is broken mid-word exactly as a
			-- single word would be. The solver measures that (`textFacts.wraps`) and
			-- the renderer carries the verdict here as `textWrapped`; `handle.wraps`
			-- is that verdict, `nil` until a solve has spoken. Both halves are ANDed,
			-- so whichever of the two writes lands last, the answer is the same one.
			if instance:IsA("TextLabel") or instance:IsA("TextButton") then
				instance.TextWrapped = handle.wraps ~= false and string.find(tostring(value), "%s") ~= nil
			end
		elseif prop == "textWrapped" then
			-- the other half of the same rule; re-applied against the string the
			-- instance is currently drawing, because the two writes are independent
			handle.wraps = value ~= false
			if instance:IsA("TextLabel") or instance:IsA("TextButton") then
				local drawn = if handle.labelInstance ~= nil then handle.labelInstance.Text else instance.Text
				instance.TextWrapped = handle.wraps and string.find(drawn, "%s") ~= nil
			end
		elseif prop == "placeholder" then
			if instance:IsA("TextBox") then
				instance.PlaceholderText = tostring(value)
			end
		elseif prop == "editing" then
			-- the editing binding is the CaptureFocus/ReleaseFocus channel (WP2
			-- seam): model enters edit -> capture; leaves -> release. Guarded by
			-- IsFocused so an engine-initiated focus (native tap / A-press, which
			-- already drove the model into editing via onFocusGained) does not
			-- redundantly re-capture, and a model-exit after the engine already
			-- released (Enter fired FocusLost first) is a harmless skip.
			if instance:IsA("TextBox") then
				if value == true then
					if not instance:IsFocused() then
						instance:CaptureFocus()
					end
				else
					if instance:IsFocused() then
						instance:ReleaseFocus(false)
					end
				end
			end
		elseif prop == "keyboardType" then
			-- best-effort engine hint: map numeric/email/phone -> the closest
			-- Enum.TextInputType; default/unknown -> Default. Degrades to the default
			-- keyboard when the security-locked TextInputType is unreachable (facts
			-- §1: RobloxScript-locked, so canSetTextInputType is false on shipping
			-- game/plugin scripts and this whole branch is skipped — forward-
			-- compatible when a future engine unlocks it). The declaration always
			-- stays valid data on the model side regardless.
			if instance:IsA("TextBox") and canSetTextInputType then
				local name = KEYBOARD_TYPE_ENGINE_NAME[tostring(value)] or "Default"
				pcall(function()
					(instance :: any).TextInputType = (Enum.TextInputType :: any)[name]
				end)
			end
		elseif prop == "maxLength" then
			-- no engine property enforces this; the value model clamps by Unicode
			-- scalar (WP2). Nothing to write to the TextBox — data-only.
		elseif prop == "selected" then
			-- a node that DECLARES a selection binding is a selection surface,
			-- whatever the current value is: the slot is the node's semantics
			-- and the value is the state a tint rule paints over one base image
			if handle.hasSelectionBinding ~= true then
				handle.hasSelectionBinding = true
				syncChrome(handle)
			end
			if instance:IsA("TextButton") then
				handle.isSelected = value == true
				-- a rung-2 map may declare `selected` art; nothing else repaints an
				-- untagged decoration
				applyOverrideVariantArt(handle)
				if nativeMode then
					-- native: the tag flip IS the state change — the
					-- "Selected row" rule paints it (and transitions animate it)
					syncTags(handle)
				elseif handle.applyRestingFill ~= nil then
					handle.applyRestingFill()
				else
					assertBespokePaint("BackgroundColor3")
					instance.BackgroundColor3 = if value == true then COLOR.controlSelected else COLOR.control
				end
			end
		elseif prop == "value" then
			applyToggleValue(handle, value == true)
		elseif prop == "enabled" then
			if instance:IsA("TextBox") then
				instance.TextEditable = value == true
				if nativeMode then
					-- native: Interactable drives GuiState.NonInteractable (spike
					-- m1 — Active does NOT); the :NonInteractable rule owns the
					-- disabled text transparency
					(instance :: any).Interactable = value == true
				else
					assertBespokePaint("TextTransparency")
					instance.TextTransparency = if value == true then 0 else style.extra.disabledContentOpacity
				end
			elseif instance:IsA("TextButton") then
				instance.Active = value == true
				if nativeMode then
					(instance :: any).Interactable = value == true
				else
					assertBespokePaint("TextTransparency")
					instance.TextTransparency = if value == true then 0 else style.extra.disabledContentOpacity
				end
			end
			--[[ THE BAND GOES WITH THE FACE (review F1, and its fix-1 residual): a
				disabled control whose 44px expander still advertises a press is a
				promise it does not keep, and the expander is a SIBLING so nothing
				about `enabled` reaches it by parentage.

				OUTSIDE THE CLASS CHAIN, deliberately. The chain above is about which
				engine PROPERTY says "disabled" for each instance class; the expander
				is a different question entirely — `setHitRect` builds one for whatever
				host asked for a hit rect, and four control classes declare a hit floor
				(Button and Toggle are TextButtons, TextField is a TextBox, Grip is
				neither). Gating this on `TextButton` left a disabled TextField's band
				carrying whatever it was born with. `mirrorToHitExpander` already
				guards on "does this handle have an expander", which is the same
				predicate `setHitRect` writes — so the condition is derived from that
				one guard rather than restated here as a class list that would drift
				the moment a fifth class declares a floor. ]]
			mirrorToHitExpander(handle)
		elseif prop == "active" then
			if instance:IsA("GuiObject") then
				instance.Active = value == true
			end
		elseif prop == "image" then
			if instance:IsA("ImageLabel") then
				instance.Image = tostring(value)
			end
		elseif prop == "cursorHint" then
			handle.cursorHint = tostring(value)
		end
		-- THE TINT IS THE LAST WORD ON THE PROPERTY IT CLAIMED. Everything in this
		-- set repaints a fill or a glyph colour on the bespoke path — a reactive
		-- `surface` swap, a role change, a selection flip, a disable — and a claimed
		-- property that gets quietly overwritten is a bound colour the author can see
		-- stop working. Declared as a set rather than a line inside each branch, so a
		-- new repainting write cannot forget it.
		if handle.tint ~= nil and TINT_REPAINTING_PROPS[prop] then
			applyTint(handle)
		end
	end

	-- an elided node has nothing on screen to order
	function adapter.setZOrder(handle: any, z: number)
		if handle.elided == true then
			return
		end
		local instance = handle.instance
		if instance:IsA("GuiObject") then
			instance.ZIndex = z
			-- the expander must stay exactly one BEHIND its control (rich-skinning v2-D1b:
			-- the two must never disagree). A structural sync can re-assign z
			-- without moving any rect, so the mirror belongs here too.
			if handle.hitExpander ~= nil then
				handle.hitExpander.ZIndex = z - 1
			end
		end
	end

	-- ---- INSTANCE RECYCLING (optional, feature-detected, default ON) ---------
	--
	-- MEASURED, on this engine, in this Studio session: building one virtualized
	-- row (24 GuiObjects) costs 0.252 ms and destroying it 0.045 ms, while
	-- REWRITING the same 24 objects' properties costs 0.024 ms. **Twelve times
	-- cheaper**, and `Facet/mount` — the structural pass — was measured at
	-- 0.66-0.97 ms/frame at every viewport, the largest single component of the
	-- framework's frame after the L-9 measure fix. A scrolling list churns rows
	-- for no reason other than that their PATH changed.
	--
	-- WHICH HANDLES ARE ELIGIBLE (L-28 widened this from "bare only"). Chrome IS
	-- eligible now: a themed control's decoration, lifted label, icon, layer
	-- ladder, bar parts and toggle assembly are all handle-keyed instances whose
	-- ONLY path-keyed state is their `instancesByPath` registration — which
	-- `park` releases and `adopt` re-keys through the one enumeration
	-- (`chromePathChildEntries`). That is where the prize was: under a skinned
	-- package every control failed the old bare test by construction (5-11
	-- chrome children each), so recycling delivered -32% on flat and a small
	-- LOSS under `fantasy_ornate` while `mount` ran 5.44 ms/call there (L-27:
	-- 249 refusals against 96 parks).
	--
	-- STILL REFUSED, each for a stated reason:
	--   clip-host ROLE / presentation transform — path-keyed records a recycled
	--     node would inherit with nothing driving them (membership in a clip
	--     host is fine: released on park, re-established on adopt);
	--   motion scale — a transient animation mid-flight, keyed to the old
	--     identity's gesture;
	--   canvas group wrapper — construction-time class decision;
	--   hit expander / float focus ring — SIBLINGS of the instance (parented to
	--     the clip host), so unparenting the node does not take them off screen;
	--   a focused handle (or one carrying a glow) — focus visuals must never
	--     ride into a new identity;
	--   a STAGE — its WorldModel holds content the CALLER parented there, so
	--     recycling one would hand a new identity somebody else's scene (and its
	--     live handle names the old path). Refused on both adapters.
	local function parkEligible(handle: any): boolean
		if handle == nil or handle.instance == nil then
			return false
		end
		-- A CORPSE CANNOT TRAVEL. The removal loop visits `handles` in hash
		-- order, and a clip host is never parkable (below) — so when a host is
		-- destroyed before the loop reaches its descendants, engine Destroy
		-- propagation has already killed the descendants' instances. Every write
		-- park makes is legal on a destroyed instance (Parent = nil included),
		-- so without this gate the pool collects corpses whose ONLY symptom is
		-- adopt's non-nil Parent write throwing "Parent property is locked"
		-- (found live 2026-08-08: theme install relayout parked a destroyed
		-- card, the next section switch adopted it and the mount crashed).
		-- A live handle's instance always has a non-nil Parent here — creation
		-- parents it under its clip host or the root gui and nothing else
		-- unparents it before removal.
		if handle.instance.Parent == nil then
			return false
		end
		local path = handle.path
		if handle.stageWorld ~= nil then
			return false
		end
		--   a FOREIGN box — same reason as a Stage's, one step stronger: its
		--     container holds an instance the CALLER created, so recycling one
		--     would hand a new identity somebody else's content, and unlike a
		--     Stage there is no degrade case that turns it into an ordinary
		--     Frame. Refused whether or not anything has been adopted yet,
		--     because a caller may adopt at any time. Refused on both adapters.
		if handle.foreignBox ~= nil then
			return false
		end
		if
			handle.motionScale ~= nil
			or handle.canvasGroupInstance ~= nil
			or handle.hitExpander ~= nil
			or handle.focusRingFloat ~= nil
			or handle.focusGlow ~= nil
			or focusedHandles[handle] ~= nil
			or hostAt(path) ~= nil
			or presentationTransforms[path] ~= nil
		then
			return false
		end
		return true
	end

	-- while parked a handle keeps NO live path: `discardParked`'s teardown
	-- helpers clear `instancesByPath[handle.path .. "/" .. name]` internally, and
	-- a successor node may have re-registered those very keys under the old path
	-- — so the parked path is a sentinel nobody else can collide with
	local PARKED_PATH = "\0FacetParked"

	-- PARK: take a dying node out of the tree without destroying it. Returns false
	-- if the node is not eligible, and the caller then removes it normally — so a
	-- refusal is always safe and never silent.
	function adapter.park(handle: any): boolean
		if handle ~= nil and handle.elided == true then
			-- an elided node owns no engine object: there is nothing to park, and
			-- nothing to gain by pooling a table. It is simply dropped.
			return false
		end
		if not parkEligible(handle) then
			return false
		end
		if capturedHandle() == handle then
			return false
		end
		local path = handle.path
		-- RELEASE CLIP-HOST MEMBERSHIP. The host keeps an array of its children and
		-- re-bases their window rects against itself; a parked node left in that
		-- array is a corpse the host goes on re-placing every solve.
		local host = handle.instanceHost
		if host ~= nil then
			for i, child in host.children do
				if child == handle then
					table.remove(host.children, i)
					break
				end
			end
			handle.instanceHost = nil
		end
		instancesByPath[path] = nil
		handlesByPath[path] = nil
		-- ...and every chrome child registered under this path (L-28): the same
		-- enumeration `adopt` re-keys, or a recycled node's chrome becomes
		-- unreachable and a LATER node at this path inherits a dead registration
		for name in chromePathChildEntries(handle) do
			instancesByPath[path .. "/" .. name] = nil
		end
		-- the chrome facts the node was built against (package + asset ledger,
		-- one integer — chrome_slots `chromeEpoch`). A parked handle has left
		-- `handlesByPath`, so neither `setThemePackage`'s every-handle resync
		-- nor the fallback refresh can reach it — `adopt` refuses the handle if
		-- this no longer matches, and an equal stamp is what makes adopting
		-- WITHOUT a chrome reconcile sound.
		handle.parkedChromeEpoch = chromeState.epoch()
		handle.path = PARKED_PATH
		invalidateSubtree()
		-- OFF THE SCREEN, not merely invisible: a parked instance must cost no
		-- layout, no paint and no hit test, and must not appear in any census that
		-- counts what the surface is holding
		-- UNPARENTED IS ENOUGH, and `Visible` is deliberately left alone. The renderer
		-- caches the last visibility it wrote per path; if park flipped it here, that
		-- cache would disagree with the instance and the property diff on adoption
		-- below could skip a write the node needs.
		handle.instance.Parent = nil
		handle.parked = true
		return true
	end

	--[[ ADOPT: give a parked node a new identity. Every property the new node
		declares is written by the renderer immediately afterwards (its per-path
		caches were dropped when the old path died), so only IDENTITY is restored
		here — the paint state is the renderer's job either way.

		`rootHandle` IS THE SURFACE THIS ADOPTION BELONGS TO, and it is a parameter
		because it has to be (NM-H4a, root-caused 2026-08-17 from the director's
		phone). `park` unparents; `adopt` has to parent again, and until this
		argument existed the only root in reach was a module-scope local holding
		whichever root had `create`d LAST — anywhere on the adapter.

		One adapter hosts EVERY surface. The gallery presents its showcase screen
		on top of a scenario's, the `hud` demo mounts a probe plate on a third, and
		the ··· sink opens a fourth. So "the last root that created something" was
		the right answer only by luck of ordering, and when the luck ran out a node
		was re-parented into another surface's ScreenGui: same rect, same ZIndex,
		`Visible = true`, and drawn either on the wrong layer or — once that surface
		was disabled or destroyed — nowhere at all, permanently, because nothing
		re-parents a node that already exists.

		Every model-side instrument agreed with itself throughout, which is why 288
		headless replays, 144 viewport pairs and 36 live Studio combinations all
		diverged by zero: none of them asked what an instance's PARENT was.
	]]
	function adapter.adopt(handle: any, newPath: string, newClass: string, hint: any, rootHandle: any): boolean
		if handle == nil or handle.parked ~= true then
			return false
		end
		if handle.class ~= newClass then
			return false
		end
		-- THE HINT GATE (L-28). The decoration hint arrives through `create` and
		-- no later setter re-plans it (pinned elsewhere), so a node adopted under
		-- a DIFFERENT hint would keep the wrong chrome plan forever. REFUSED, not
		-- re-planned: a re-plan is a rebuild, which costs what the fresh create
		-- costs, so a mismatch adoption is never a win — and re-planning here
		-- would be a second planning path beside the create-time one. Content,
		-- never address (chrome_slots.hintKey): the renderer rebuilds hint tables
		-- on every window slide.
		if chrome_slots.hintKey(handle.decorationHint) ~= chrome_slots.hintKey(hint) then
			return false
		end
		-- ...and the EPOCH GATE: a package swap or an asset-ledger movement while
		-- this handle sat in the pool never reached it (both walk
		-- `handlesByPath`, which the handle has left), so its chrome would be
		-- stale with nothing left to fix it. A refusal falls through to a fresh
		-- create — chosen over reconciling here because a reconcile on the hot
		-- adopt path costs every adoption something to heal a case that is
		-- rare by construction.
		if handle.parkedChromeEpoch ~= chromeState.epoch() then
			return false
		end
		local savedEpoch = handle.parkedChromeEpoch
		handle.parked = nil
		handle.parkedChromeEpoch = nil
		handle.indicatorFlashed = nil -- a recycled instance's NEW identity flashes again
		handle.path = newPath
		handle.instance.Name = newPath
		local host = hostFor(newPath)
		-- BELT AND BRACES for the corpse gate in `parkEligible`: a destroyed
		-- instance accepts every write except a non-nil Parent, so this is the
		-- one seam that can still detect one. Refuse the adoption (restore the
		-- parked identity IN FULL — epoch stamp included — so the handle the
		-- caller's discard tears down still satisfies every parked invariant;
		-- architecture review F9).
		local reparented = pcall(function()
			if host ~= nil then
				handle.instance.Parent = host.instance
			else
				handle.instance.Parent = rootHandle.gui
			end
		end)
		if not reparented then
			handle.parked = true
			handle.parkedChromeEpoch = savedEpoch
			handle.path = PARKED_PATH
			return false
		end
		if host ~= nil then
			handle.instanceHost = host
			table.insert(host.children, handle)
		end
		instancesByPath[newPath] = handle.instance
		handlesByPath[newPath] = handle
		-- re-key the chrome children under the new identity — the SAME enumeration
		-- `park` released, so the two seams cannot drift apart
		for name, child in chromePathChildEntries(handle) do
			instancesByPath[newPath .. "/" .. name] = child
		end
		invalidateSubtree()
		recomputePresentationOffset(handle)
		-- NO chrome reconcile here, deliberately: the epoch gate above proves no
		-- plan-deciding fact moved while the handle was parked, the hint gate
		-- proves the plan itself matches, and every node-side fact that could
		-- differ (surface, value, selection) re-syncs its own chrome through the
		-- property writes the renderer is about to make. A reconcile on this
		-- path would charge every adoption for a case the gates already refuse.
		return true
	end

	-- DISCARD: a parked node the pool never reused. Destroying it is the whole
	-- point of the pool being bounded — and since a parked node can carry CHROME
	-- now (L-28), the teardown must be the census-correct one: its decorations
	-- stayed COUNTED while parked (that is what keeps `decoratedNodes` honest),
	-- so every census has to fall here or it can never show a leak. The path-map
	-- writes inside these helpers hit the PARKED_PATH sentinel, never a live
	-- path, so a successor node's registrations cannot be clobbered.
	function adapter.discardParked(handle: any)
		if handle == nil or handle.instance == nil then
			return
		end
		destroyChromeText(handle)
		destroyIconArt(handle)
		if handle.chrome ~= nil then
			chromeState.noteDestroyed(handle.chromeSlot)
			handle.chrome, handle.chromeSlot = nil, nil
		end
		destroyChromeStack(handle)
		destroyBarFill(handle)
		destroyBarOrnaments(handle)
		if handle.chromeOverrideConn ~= nil then
			handle.chromeOverrideConn:Disconnect()
			handle.chromeOverrideConn = nil
		end
		dropChromeShadow(handle)
		if handle.strokeInstance ~= nil then
			handle.strokeInstance:Destroy()
			handle.strokeInstance = nil
		end
		handle.instance:Destroy()
		handle.instance = nil
	end

	function adapter.remove(handle: any)
		if handle ~= nil and handle.elided == true then
			-- never built anything, so there is nothing to unwind; the path-keyed
			-- records below were never written for it either
			instancesByPath[handle.path] = nil
			handlesByPath[handle.path] = nil
			return
		end
		if capturedHandle() == handle then
			-- never leave a global capture pointing at a dead node — unless
			-- the drag itself removed it (lift) and asks to keep the capture
			endCapture("removed")
		end
		instancesByPath[handle.path] = nil
		instancesByPath[handle.path .. "/" .. chrome_slots.DECORATION_NAME] = nil
		-- the PRESENTATION record and the REAL-PARENT record both die with the node
		-- (screen_presentation.dropPath, which owns the count)
		dropPresentationRecords(handle.path)
		if handle.motionScale ~= nil then
			handle.motionScale:Destroy()
			handle.motionScale = nil
		end
		if handle.strokeInstance ~= nil then
			handle.strokeInstance:Destroy()
			handle.strokeInstance = nil
		end
		-- the toggle assembly's path entries die with the node too, or a destroyed
		-- knob stays reachable and a probe reads geometry off a corpse
		for name in chrome_slots.TOGGLE_PARTS do
			instancesByPath[handle.path .. "/" .. chrome_slots.TOGGLE_PARTS[name]] = nil
		end
		handlesByPath[handle.path] = nil
		invalidateSubtree()
		-- the LIFTED LABEL is decoration too: without this its connections stayed
		-- live, `census.textLifts` only ever grew across remounts, and
		-- `instancesByPath[path .. "/FacetChromeText"]` retained a destroyed
		-- label — a census that cannot fall cannot show a leak
		destroyChromeText(handle)
		-- ...and so is the managed ICON picture (ADR-0020 R4): its path entry and
		-- its census have to fall with the node for exactly the same reason
		destroyIconArt(handle)
		if handle.chrome ~= nil then
			-- counted, not just dropped: a census whose `live` never falls is a
			-- census that cannot show a leak
			chromeState.noteDestroyed(handle.chromeSlot)
			handle.chrome, handle.chromeSlot = nil, nil
		end
		-- the LADDER is decoration too: its instances, its path entries and its
		-- per-kind census all have to fall with the node
		destroyChromeStack(handle)
		-- ...and so are the VALUE DISPLAYS (ADR-0020 R3). The clip window holds an
		-- AbsoluteSize connection on the track, which would otherwise outlive the
		-- bar and keep resizing a destroyed label.
		destroyBarFill(handle)
		destroyBarOrnaments(handle)
		if handle.chromeOverrideConn ~= nil then
			handle.chromeOverrideConn:Disconnect()
			handle.chromeOverrideConn = nil
		end
		dropChromeShadow(handle)
		if handle.focusGlow ~= nil then
			handle.focusGlow:Destroy()
			handle.focusGlow = nil
			chromeState.noteFocusGlow(false)
		end
		-- THE FLOAT RING OUTLIVES ITS NODE UNLESS SOMETHING KILLS IT. Every other
		-- focus visual is a CHILD of the focused instance and falls with it; the
		-- float is deliberately a sibling parented to the CLIP HOST (see the ring's
		-- own comment — an outward Border ring is clipped away on a stacked row), so
		-- destroying the row leaves an orphan accent rectangle floating in the
		-- canvas at the rect the row used to have. A windowed list slides rows in
		-- and out under a live focus constantly, which is how a shipped capture came
		-- to show TWO accent rings at once — one real, one a ghost of a row that had
		-- scrolled away (found 2026-07-31 in the parallel-Sponsor review).
		if handle.focusRingFloat ~= nil then
			handle.focusRingFloat:Destroy()
			handle.focusRingFloat = nil
		end
		handle.focusVisualHost = nil
		focusedHandles[handle] = nil
		dropHitExpander(handle)
		-- THE STAGE SEAM DIES WITH ITS NODE. The WorldModel and Camera are children
		-- of the frame, so the Destroy below takes them; what has to happen HERE is
		-- the HANDLE going dead, or a consumer still holding it would go on aiming a
		-- camera nothing renders and parenting content into a destroyed world.
		markStageDisposed(handle)
		-- ...and the FOREIGN seam, for exactly the same reason (ADR-0034)
		markForeignDisposed(handle)
		handle.instance:Destroy()
	end

	function adapter.destroyRoot(rootHandle: any)
		-- whole-root teardown mid-drag: cancel the capture (its global UIS
		-- connections outlive the gui otherwise) — but ONLY when the capture
		-- actually belongs to THIS root. An adapter hosts several roots at
		-- once (this function's own per-node loop below already says so), and
		-- the capture is a SINGLE adapter-wide slot — unconditionally ending
		-- it here would cancel a gesture some OTHER, still-live root owns
		-- (row-actions Task 10, live-found: the presenter's own transient
		-- popup-catcher root is mounted/retired reactively as any
		-- `outsideDismiss.active` readable changes — including a row's own
		-- tray closing via the shared coordinator, itself triggered from
		-- INSIDE a SECOND row's still-live gesture; disposing the popup
		-- catcher unconditionally cancelled that second row's own capture out
		-- from under it, one frame into its drag). Release any cursor hint
		-- regardless — a hint from a capture on another root would already
		-- be stale as of this root's own teardown.
		local captured = capturedHandle()
		if captured ~= nil and (captured.instance :: Instance):IsDescendantOf(rootHandle.gui) then
			endCapture("destroyed")
		end
		--[[ THE CURSOR HINT IS THIS ROOT'S; THE MENU CONNECTION IS THE ADAPTER'S.
			An adapter hosts several roots at once — the presenter mounts
			and retires a transient popup-catcher root reactively — so disconnecting
			`GuiService.MenuOpened` here used to kill drag-abort-on-menu for every
			OTHER live root the first time any root came down. The hint really does
			go with the root (a hint set by a capture on a root that is being
			destroyed is stale as of now); the connection goes with the LAST one. ]]
		releaseCursorHint()
		local remainingRoots = 0
		for _, gui in themeRoots do
			if gui ~= rootHandle.gui then
				remainingRoots += 1
			end
		end
		if remainingRoots == 0 then
			disposeGlobalPointerState()
		end
		for path, node in instancesByPath do
			if node:IsDescendantOf(rootHandle.gui) then
				instancesByPath[path] = nil
				-- the same two per-node records `remove` drops, on the whole-root path:
				-- a target hosts several roots at once, so this cannot be a blanket reset
				dropPresentationRecords(path)
				local handle = handlesByPath[path]
				if handle ~= nil then
					-- the stage seam, on the whole-root path (same reason as in `remove`)
					markStageDisposed(handle)
					markForeignDisposed(handle)
					handle.motionScale = nil
					handle.strokeInstance = nil
					destroyChromeText(handle)
					destroyIconArt(handle)
					if handle.chrome ~= nil then
						chromeState.noteDestroyed(handle.chromeSlot)
						handle.chrome, handle.chromeSlot = nil, nil
					end
					destroyChromeStack(handle)
					-- ...and the VALUE DISPLAYS, in `remove`'s reverse order
					-- (runtime + platform verifier F5). Without these the bar
					-- family's `noteCreated` was unpaired on the whole-root path:
					-- its census could never fall, and the clip window's
					-- AbsoluteSize connection survived on a destroyed track.
					destroyBarFill(handle)
					destroyBarOrnaments(handle)
					if handle.chromeOverrideConn ~= nil then
						handle.chromeOverrideConn:Disconnect()
						handle.chromeOverrideConn = nil
					end
					-- the ledger and the strong reference both, or a torn-down root
					-- leaves a census that can never fall and a handle a live table
					-- still pins (the same class of leak B13 closed for the lift)
					dropChromeShadow(handle)
					if handle.focusGlow ~= nil then
						handle.focusGlow = nil
						chromeState.noteFocusGlow(false)
					end
					handle.focusVisualHost = nil
					focusedHandles[handle] = nil
				end
				handlesByPath[path] = nil
				invalidateSubtree()
			end
		end
		for index, gui in themeRoots do
			if gui == rootHandle.gui then
				table.remove(themeRoots, index)
				break
			end
		end
		rootHandle.gui:Destroy()
	end

	return adapter
end

return screen_target
