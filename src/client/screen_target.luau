--!strict
-- ScreenTarget (design §13; CLIENT-ONLY — the only module that reaches engine
-- Instances for rendering, per ADR-0003's seam rule; check_boundary enforces
-- that non-client code never requires this). Implements the same
-- RenderTargetAdapter interface as tests/lib/fake_target: createRoot/create/
-- setRect/setProp/remove/destroyRoot (+ setActivateHandler/setFocusVisual/
-- getInstance). Renders under PlayerGui with ZIndexBehavior=Sibling and
-- IgnoreGuiInset=true: LuauUI solves insets itself (§8.1).
--
-- STYLE: applies the "Studio Neutral" default style (src/tokens/default_style)
-- or a game-compiled override passed via new({ style = ... }). All visual
-- writes here are the STYLE authority (design §7.3): surfaces, radii,
-- hairlines, state colors, focus ring, motion. Data writes (text/value/
-- enabled) remain the binding authority in setProp. Motion honors
-- reducedMotion via opts.isReducedMotion (wired from the environment).

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
local text_premeasure = require("./text_premeasure")
local authority = require("../render/authority")

-- The engine draws a ScrollingFrame's bar INSIDE the region, over whatever the
-- solver placed there. The solver reserves this off the cross axis when a region
-- actually scrolls, so the number has to be one value shared by both seams.
local SCROLL_BAR_THICKNESS = 8

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

-- authored `scaleMode` -> engine ScaleType (ADR-0022 Decision 6, row SF-P2).
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
	ScrollView = "ScrollingFrame", -- native scroll host (NS-A2); opts.forceScrollFallback keeps a Frame
	-- Path (NS-A7) renders as a transparent Frame holder + child Path2D
	-- containers and everything else render as Frames
}

-- Path2D control-point application (NS-A7; spike m5-path2d.json): normalized
-- points (unit box, tangents relative to the point) scale into the CURRENT
-- solved rect. Engine truths: max 100 control points; no Transparency
-- property; left tangent = incoming handle, right = outgoing.
local function applyPathPoints(handle: any)
	local path2d = handle.path2d
	local rect = handle.windowRect
	local points = handle.normPoints
	if path2d == nil or rect == nil or points == nil then
		return
	end
	local w, h = math.max(rect.w, 1), math.max(rect.h, 1)
	local cps = table.create(#points)
	for _, p in points do
		table.insert(
			cps,
			Path2DControlPoint.new(
				UDim2.fromOffset(p.x * w, p.y * h),
				UDim2.fromOffset(p.inX * w, p.inY * h),
				UDim2.fromOffset(p.outX * w, p.outY * h)
			)
		)
	end
	path2d:SetControlPoints(cps)
end

local function toColor3(c: any): Color3
	return Color3.new(c.r, c.g, c.b)
end

export type Opts = {
	style: any?,
	isReducedMotion: (() -> boolean)?,
	parent: Instance?,
	-- root override (ADR-0009): everything below the root is target-agnostic
	-- flat instance rendering, so BillboardTarget swaps ONLY the root — the
	-- factory returns { gui = <the container all nodes parent under> }
	rootFactory: ((screenId: string) -> { gui: Instance })?,
	-- native-substrate NS-A2/NS-I2: render ScrollView nodes as plain Frame clip
	-- hosts (no engine scrolling). Billboard targets set this until proven;
	-- the gallery sets it from the LuauUI_ForceScrollFallback attribute so the
	-- fallback path is exercised separately in Studio (never only headlessly).
	forceScrollFallback: boolean?,
	-- native-substrate NS-A5/NS-I2: force setDragDetector to return nil so the
	-- raw pointer-capture fallback is exercised separately (A/B evidence runs)
	forceDragFallback: boolean?,
	-- native-stylesheets stage (ledger NSS-A2, plan §7 Phase 2): OPT-IN native
	-- paint. When set and the engine has StyleSheets, the adapter stops
	-- explicit-writing every handed-off style property and instead CLASSIFIES
	-- nodes (class + luau-* tags, sheet_model.classifyTags) under one
	-- StyleLink per root; the DataModel sheet (seed-once, native_style.ensure)
	-- owns fills, chrome, text paint, and interaction-state paint. Absent or
	-- unsupported -> the explicit-write path below runs unchanged (NSS-A10
	-- fallback parity). `true` builds the built-in Dark+Light model; a table
	-- passes { model | handle, host, theme }.
	-- table form also takes `transitions = true` to opt into sheet transitions
	-- (progressive enhancement; default OFF until the NSS-P3 publish rider clears)
	nativeStyle: (boolean | { model: any?, handle: any?, host: Instance?, theme: string?, transitions: boolean? })?,
	-- theme-packages stage (ADR-0019 §5): the installed ThemePackage whose
	-- chrome recipes decide DECORATION SLOTS. A package whose slots are all
	-- native — every reference package except an asset-backed one — creates
	-- zero instances, so this is free to leave unset. The theme controller
	-- swaps it at runtime through `adapter.setThemePackage`.
	themePackage: any?,
}

function screen_target.new(opts: Opts?)
	local style: any = (opts and opts.style) or defaultStyle
	local isReducedMotion = (opts and opts.isReducedMotion) or function()
		return false
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
	adapter.scrollBarThickness = if opts ~= nil and opts.forceScrollFallback == true then 0 else SCROLL_BAR_THICKNESS

	-- native-paint mode resolution (NSS-A2): capability-probed and opt-in.
	local nativeHandle: any = nil
	do
		local nativeOpt: any = opts and (opts :: any).nativeStyle
		if nativeOpt == nil then
			-- the one-toggle default (promotion plan): unset means "library
			-- default", which is native_style.DEFAULT_ENABLED; an explicit
			-- `false` is the per-target escape hatch either way
			nativeOpt = native_style.DEFAULT_ENABLED
		end
		if nativeOpt ~= nil and nativeOpt ~= false and native_style.available() then
			if type(nativeOpt) == "table" and nativeOpt.handle ~= nil then
				nativeHandle = nativeOpt.handle
			else
				local model = (type(nativeOpt) == "table" and nativeOpt.model) or nil
				if model == nil then
					-- built-in model: the passed style is the default theme; the
					-- built-in Light theme ships only when running Studio Neutral
					-- (a game style carries no light variant to derive)
					local themes = { { name = "Dark", style = style } }
					if style == defaultStyle then
						table.insert(themes, { name = "Light", style = defaultLightStyle })
					end
					model = sheet_model.build({ themes = themes })
				end
				-- transitions are progressive-enhancement OPT-IN (NSS-P3 rider:
				-- publish status unconfirmed; default = instant change), and
				-- reduced motion always wins over the opt
				nativeHandle = native_style.ensure(model, {
					host = if type(nativeOpt) == "table" then nativeOpt.host else nil,
					theme = if type(nativeOpt) == "table" then nativeOpt.theme else nil,
					transitionsEnabled = type(nativeOpt) == "table"
						and nativeOpt.transitions == true
						and not isReducedMotion(),
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
	local CLAIM_ATTRIBUTE = "LuauUI_PaintClaims"

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

	-- CENTRAL native-authority gate (arch verifier 2026-07-24, NSS-I2): every
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
			error(`LuauUI native-style: bespoke write to sheet-owned {engineProp} in native mode`, 0)
		end
	end

	-- tag synchronization: the ONLY channel by which LuauUI state reaches
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
			-- layer. Same reason it lives here: syncTags owns every luau-* tag
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
			if string.sub(tag, 1, 5) == "luau-" and desired[tag] ~= true then
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
	end

	function refreshFocusVisuals()
		for handle, profile in focusedHandles do
			adapter.setFocusVisual(handle, true, profile)
		end
	end

	-- semantic cursor requests (ADR-0008): the framework names an intent
	-- ("colResize"); this table maps it to uploaded cursor art. No first-party
	-- cursor set exists — assets are a rider; an unmapped hint keeps the
	-- default arrow but the seam (hover + capture persistence) is live.
	local CURSOR_ART: { [string]: string } = {}
	local hoverHint: string? = nil
	local captureHint: string? = nil
	local function applyCursor()
		local hint = captureHint or hoverHint
		UserInputService.MouseIcon = (hint and CURSOR_ART[hint]) or ""
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
	local destroyChromeStack = chrome.destroyChromeStack
	local destroyBarFill = chrome.destroyBarFill
	local destroyBarOrnaments = chrome.destroyBarOrnaments
	local dropChromeShadow = chrome.dropChromeShadow
	local chromeArtCensus = chrome.artCensus
	local chromePathChildEntries = chrome.chromePathChildEntries

	-- the colour a focus visual paints, in ONE place so the ring and the glow can
	-- never disagree about which accent is live. DECLARED BELOW `COLOR` on
	-- purpose: a local declared later is NOT an upvalue — placed above the
	-- table, this function captured a nil GLOBAL `COLOR` and crashed the first
	-- real boot (docs/lessons; the fake adapter never runs this file, so only a
	-- Studio session can catch it).
	local function focusColor(): Color3
		return focusTreatment.color or COLOR.accent
	end

	-- THE TOGGLE PALETTE, resolved live. Same shape and same reason as
	-- `focusColor` above, and DECLARED IN THE SAME PLACE for the same reason: it
	-- captures `COLOR`, so it must sit below the table.
	--
	-- The toggle's knob-and-track is value-driven paint, and a StyleSheet rule
	-- cannot see a value — so these two colours stay bespoke writes in BOTH modes
	-- (the `Toggle chrome` rule owns only their opacity). That is precisely why
	-- they were still painting from constants captured at construction, and why a
	-- parchment toggle rendered a Studio-Neutral blue pill.
	--
	-- WITH NO PACKAGE INSTALLED this returns exactly today's COLOR.* values, so
	-- every existing game and every existing test is byte-identical. The mapping
	-- itself lives in the pure `sheet_model.togglePalette` (which states why each
	-- role was chosen) so the adapter and the specs cannot disagree about it.
	local function togglePalette(): { trackOn: Color3, trackOff: Color3, knobOn: Color3, knobOff: Color3 }
		if activeTheme == nil then
			return { trackOn = COLOR.accent, trackOff = COLOR.surface, knobOn = COLOR.content, knobOff = COLOR.content }
		end
		local p = sheet_model.togglePalette(activeTheme)
		return {
			trackOn = toColor3(p.trackOn),
			trackOff = toColor3(p.trackOff),
			knobOn = toColor3(p.knobOn),
			knobOff = toColor3(p.knobOff),
		}
	end

	-- THE PALETTE A CONTINUOUS VALUE RESOLVES AGAINST: the installed package theme,
	-- or the style this target was constructed with — the same two-step
	-- `togglePalette` above uses, so a tint resolves identically whether or not a
	-- package is installed, and a target with none is byte-identical to before.
	local function paletteTheme(): any
		return activeTheme or { colors = style.colors, extra = style.extra }
	end

	-- THE CONTINUOUS-COLOUR WRITE (ADR-0022 Decision 6, rows SF-P1/SF-P2).
	--
	-- One engine property per class — the one paint channel that class owns — and
	-- each is claimed before it is written (see claimPaint): the sheet cannot express
	-- a value, so the node takes the property and the dump says it did.
	--
	-- `Box` claims its TRANSPARENCY as well as its colour, and that is a decision
	-- rather than an oversight: a Frame is transparent until a surface says
	-- otherwise (the class-default rule in native mode, an explicit write in
	-- fallback), so a tint that only set BackgroundColor3 would paint an invisible
	-- fill — accepted and ignored, the failure class this framework keeps closing.
	-- A tinted Box paints. Text and Image claim only their colour, leaving
	-- TextTransparency to the disabled state and ImageTransparency to a dim
	-- treatment.
	--
	-- The resolution itself is PURE (`sheet_model.tintColor`) and shared with the
	-- headless FakeTarget, so the two adapters cannot disagree about the colour.
	local function applyTint(handle: any)
		local tint = handle.tint
		local instance = handle.instance
		if tint == nil then
			return
		end
		local color = toColor3(sheet_model.tintColor(paletteTheme(), tint, handle.class))
		-- THE TINT'S OWN ALPHA (2026-07-31). Absent it resolves to 0, which is what
		-- every branch below already wrote (Box) or left alone (Text/Image), so a
		-- tint that does not declare one is byte-identical. Declared, it claims the
		-- matching transparency property beside the colour — one channel, one claim
		-- pair, never a second opacity authority.
		local alpha = sheet_model.tintTransparency(tint, handle.class)
		local hasAlpha = (tint :: any).transparency ~= nil
		if handle.path2d ~= nil then
			-- a Path2D is not a GuiObject and no rule can select one: no claim needed.
			-- Its pre-tint colour is recorded here rather than through claimPaint,
			-- which reads GuiObject properties, so a release restores the role's stroke
			-- instead of guessing at the default.
			if handle.tintPathRestore == nil then
				handle.tintPathRestore = handle.path2d.Color3
			end
			handle.path2d.Color3 = color
			return
		end
		if instance:IsA("ImageLabel") then
			claimPaint(handle, "ImageColor3")
			assertBespokePaint("ImageColor3", handle)
			instance.ImageColor3 = color
			if hasAlpha then
				claimPaint(handle, "ImageTransparency")
				assertBespokePaint("ImageTransparency", handle)
				instance.ImageTransparency = alpha
			end
		elseif instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
			claimPaint(handle, "TextColor3")
			assertBespokePaint("TextColor3", handle)
			instance.TextColor3 = color
			if hasAlpha then
				claimPaint(handle, "TextTransparency")
				assertBespokePaint("TextTransparency", handle)
				instance.TextTransparency = alpha
				if handle.labelInstance ~= nil then
					handle.labelInstance.TextTransparency = alpha
				end
			end
			-- ...AND THE LIFTED LABEL, which is the instance that actually draws the
			-- glyphs on a skinned node (the node's own text is suppressed under the
			-- art). Same reason the `textSize` write below reaches both: a tint on the
			-- node and an untinted label is measure-versus-paint one layer down.
			if handle.labelInstance ~= nil then
				handle.labelInstance.TextColor3 = color
			end
		elseif instance:IsA("GuiObject") then
			claimPaint(handle, "BackgroundColor3")
			claimPaint(handle, "BackgroundTransparency")
			assertBespokePaint("BackgroundColor3", handle)
			assertBespokePaint("BackgroundTransparency", handle)
			instance.BackgroundColor3 = color
			instance.BackgroundTransparency = alpha
		end
	end

	-- releasing a tint restores what the property held when the claim was taken.
	-- The claim itself does not come back to the sheet — the engine has no such
	-- operation (see the claims block above), which the reference states.
	local function releaseTint(handle: any)
		handle.tint = nil
		if handle.path2d ~= nil then
			if handle.tintPathRestore ~= nil then
				handle.path2d.Color3 = handle.tintPathRestore
				handle.tintPathRestore = nil
			end
			return
		end
		for _, prop in
			{
				"ImageColor3",
				"ImageTransparency",
				"TextColor3",
				"TextTransparency",
				"BackgroundColor3",
				"BackgroundTransparency",
			}
		do
			restorePaint(handle, prop)
		end
		if handle.labelInstance ~= nil and handle.paintRestore ~= nil and handle.paintRestore.TextColor3 ~= nil then
			handle.labelInstance.TextColor3 = handle.paintRestore.TextColor3
		end
	end

	-- normalized UI.stroke data -> ONE bespoke UIStroke under the node (style
	-- authority). Named from the manifest's own constant, reused rather than
	-- re-created (a reactive pulse must never stack two borders), and destroyed when
	-- the declaration goes away.
	--
	-- NO `assertBespokePaint`: an authored stroke is a DECLARED override, the same
	-- standing UI.corners/UI.shadow have. It coexists with a theme's phantom
	-- ::UIStroke rule — the engine renders both (ADR-0020 R8) — so it never
	-- suppresses theme chrome and never has to fight for it.
	local function applyStroke(instance: Instance, stroke: any, handle: any)
		if not instance:IsA("GuiObject") then
			return
		end
		if stroke == nil then
			if handle.strokeInstance ~= nil then
				handle.strokeInstance:Destroy()
				handle.strokeInstance = nil
			end
			return
		end
		local live = handle.strokeInstance
		if live == nil then
			live = Instance.new("UIStroke")
			live.Name = authority.INSTANCE_NAMES.stroke
			handle.strokeInstance = live
		end
		live.Color = toColor3(stroke.color)
		live.Transparency = stroke.transparency
		live.Thickness = stroke.thickness
		-- Border, ALWAYS: ApplyStrokeMode defaults to Contextual, which on a text
		-- node strokes the GLYPHS instead of the box (the same engine truth the
		-- phantom stroke rules carry)
		live.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		live.Parent = instance
	end

	local function motionInfo(duration: number): TweenInfo
		return TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end

	-- THE PRESS DIP'S UIScale, CREATED ON FIRST PRESS AND NOT BEFORE.
	--
	-- Measured on the performance lab: a 5-row window held 249 instances, and **all 25
	-- UIScale objects sat at Scale = 1.0** — one per interactive control, created at
	-- construction for a dip that had not happened and on most controls never will.
	-- That is 10% of every instance on the surface doing nothing, and it is paid by
	-- every LuauUI consumer with buttons on screen, not just this fixture.
	--
	-- ONE SCALE, SHARED WITH THE MOTION CHANNEL. The engine honours a single UIScale
	-- per instance, so the press dip and a running motion must not each own one — the
	-- existing "the motion scale SHARES the press dip's UIScale" contract. This
	-- accessor is the single place either path gets one, so laziness cannot
	-- accidentally produce two.
	local function ensureScale(instance: Instance, handle: any): UIScale
		local existing = handle.motionScale or handle.uiScale
		if existing ~= nil then
			return existing
		end
		local scale = Instance.new("UIScale")
		scale.Name = authority.INSTANCE_NAMES.motionScale
		scale.Parent = instance
		handle.uiScale = scale
		return scale
	end

	-- pressed-dip presentation for native mode: the fills belong to the sheet
	-- (:Press rules), but the quick UIScale dip is value-driven presentation
	-- and stays bespoke (plan §6.5) — wired WITHOUT any fill writes.
	local function wireNativePressDip(button: TextButton, handle: any)
		local function recover()
			-- nothing to recover if no dip ever happened, and nothing to create either
			local scale = handle.motionScale or handle.uiScale
			if scale == nil then
				return
			end
			if not isReducedMotion() and not handle.suppressStates then
				TweenService:Create(scale, motionInfo(style.motion.fast), { Scale = 1 }):Play()
			else
				scale.Scale = 1
			end
		end
		button.MouseButton1Down:Connect(function()
			if not isReducedMotion() and not handle.suppressStates then
				TweenService:Create(
					ensureScale(button, handle),
					motionInfo(style.motion.fast),
					{ Scale = style.extra.pressedScale }
				):Play()
			end
		end)
		button.MouseButton1Up:Connect(recover)
		button.MouseLeave:Connect(recover)
	end

	-- THE DISC'S RADIUS, FALLBACK HALF (feature round 2026-07-26). In native mode
	-- the pill is the sheet's phantom `.luau-shape-circle::UICorner` rule; on the
	-- bespoke path the adapter owns the real UICorner, so the SAME fact has to
	-- reach it here. One function, so "a circle is UDim(0.5, 0)" is one decision
	-- across both paint paths rather than two that drift.
	local function cornerRadiusFor(handle: any, radius: number): UDim
		if type(handle) == "table" and handle.shape == "circle" then
			return UDim.new(0.5, 0)
		end
		return UDim.new(0, radius)
	end

	-- sanctionedOverride: the toggle knob-track assembly's declared real-child
	-- chrome (authority.luau native-owned notes) — the ONLY callers allowed to
	-- materialize modifier instances in native mode
	local function corner(instance: Instance, radius: number, sanctionedOverride: boolean?, handle: any?)
		if not sanctionedOverride then
			assertBespokePaint("CornerRadius")
		end
		local uiCorner = Instance.new("UICorner")
		uiCorner.CornerRadius = cornerRadiusFor(handle, radius)
		uiCorner.Parent = instance
	end

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

	-- normalized UI.shadow data -> a UIShadow instance under the node (style
	-- authority; purely visual — never enters layout). No-capability engines
	-- keep the declaration as data only (headless fallback).
	local function applyShadow(instance: Instance, shadow: any, handle: any)
		if not hasUIShadow or not instance:IsA("GuiObject") then
			return
		end
		local shadowInstance = handle.shadowInstance
		if shadowInstance == nil then
			shadowInstance = Instance.new("UIShadow" :: any)
			handle.shadowInstance = shadowInstance
		end
		shadowInstance.BlurRadius = UDim.new(shadow.blurRadius.scale, shadow.blurRadius.offset)
		shadowInstance.Color = Color3.new(shadow.color.r, shadow.color.g, shadow.color.b)
		shadowInstance.Transparency = shadow.transparency
		shadowInstance.Offset =
			UDim2.new(shadow.offset.x.scale, shadow.offset.x.offset, shadow.offset.y.scale, shadow.offset.y.offset)
		shadowInstance.Spread =
			UDim2.new(shadow.spread.x.scale, shadow.spread.x.offset, shadow.spread.y.scale, shadow.spread.y.offset)
		shadowInstance.ZIndex = shadow.zIndex
		shadowInstance.Enabled = shadow.enabled
		shadowInstance.Parent = instance
	end

	-- normalized UI.gradient data -> ONE UIGradient under the node (style
	-- authority; purely visual — never enters layout).
	--
	-- WHY AN INSTANCE AND NOT A RULE (the whole rung-2 argument). A theme's
	-- gradients are phantom `::UIGradient` MODIFIER rules with zero children: a
	-- rule matches a CLASS of nodes, which is exactly right for a theme and
	-- exactly wrong for "this one card". So the per-view modifier follows
	-- `UI.shadow`'s architecture — a bespoke adapter-owned child — and the real
	-- child is what makes the view win on this node (measured live, ADR-0020 R8).
	--
	-- Named so it is identifiable in a live tree, and REUSED rather than
	-- re-created, so a reactive gradient (or a theme swap that re-applies style
	-- props) can never leave two ramps stacked on one node.
	local function applyGradient(instance: Instance, gradient: any, handle: any)
		if not instance:IsA("GuiObject") then
			return
		end
		local live = handle.gradientInstance
		if live == nil then
			live = Instance.new("UIGradient")
			live.Name = "LuauUIGradient"
			handle.gradientInstance = live
		end
		local keypoints: { ColorSequenceKeypoint } = {}
		for _, stop in gradient.colors do
			table.insert(keypoints, ColorSequenceKeypoint.new(stop.t, Color3.new(stop.r, stop.g, stop.b)))
		end
		live.Color = ColorSequence.new(keypoints)
		if gradient.transparency ~= nil then
			local alpha: { NumberSequenceKeypoint } = {}
			for _, stop in gradient.transparency do
				table.insert(alpha, NumberSequenceKeypoint.new(stop.t, stop.v))
			end
			live.Transparency = NumberSequence.new(alpha)
		else
			live.Transparency = NumberSequence.new(0)
		end
		live.Rotation = gradient.rotation
		live.Enabled = gradient.enabled
		live.Parent = instance
	end

	-- normalized UI.corners data -> ONE UICorner in exactly ONE form
	-- (uniform alias or four per-corner radii — never both; engine hazard)
	local function applyCorners(instance: Instance, corners: any)
		if not instance:IsA("GuiObject") then
			return
		end
		local uiCorner = instance:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
		if corners.form == "uniform" then
			uiCorner.CornerRadius = UDim.new(0, corners.radius)
		elseif hasPerCornerRadii then
			(uiCorner :: any).TopLeftRadius = UDim.new(0, corners.topLeft);
			(uiCorner :: any).TopRightRadius = UDim.new(0, corners.topRight);
			(uiCorner :: any).BottomLeftRadius = UDim.new(0, corners.bottomLeft);
			(uiCorner :: any).BottomRightRadius = UDim.new(0, corners.bottomRight)
		else
			-- old-engine fallback: alias with the largest declared radius
			local top = math.max(corners.topLeft, corners.topRight, corners.bottomLeft, corners.bottomRight)
			uiCorner.CornerRadius = UDim.new(0, top)
		end
		uiCorner.Parent = instance
	end

	-- A STROKE NOBODY CAN SEE IS NOT WORTH AN INSTANCE. A theme package may set
	-- `strokes.hairline = 0` or a fully transparent hairline; both shipped themes
	-- keep it visible, so this saves nothing on them — but a theme that turns
	-- hairlines off would otherwise pay 30 invisible `UIStroke` objects per five
	-- rows (measured shape: 30 strokes on a 137-GuiObject surface). The guard is one
	-- comparison at construction and cannot change what is on screen: if it declines
	-- to build the stroke, the stroke would have drawn nothing.
	local function hairlineWouldShow(): boolean
		local thickness = style.strokes.hairline
		local opacity = style.extra.hairlineOpacity
		if type(thickness) == "number" and thickness <= 0 then
			return false
		end
		if type(opacity) == "number" and opacity >= 1 then
			return false
		end
		return true
	end

	local function hairline(instance: Instance, sanctionedOverride: boolean?)
		if not hairlineWouldShow() then
			return
		end
		if not sanctionedOverride then
			assertBespokePaint("StrokeColor")
		end
		local stroke = Instance.new("UIStroke")
		stroke.Name = "Hairline"
		stroke.Color = COLOR.hairline
		stroke.Transparency = style.extra.hairlineOpacity
		stroke.Thickness = style.strokes.hairline
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = instance
	end

	-- surface roles for containers/rows (style authority; opted in via the
	-- blueprint `surface` prop): raised | control | scrim
	--
	-- NATIVE MODE (NSS-A2): the surface hint becomes a tag, never a write —
	-- the sheet's surface rules own fills/transparency and its ::UICorner/
	-- ::UIStroke rules CREATE the phantom chrome (spike m2: materializing a
	-- real modifier instance here would silently defeat those rules).
	local function applySurfaceNative(instance: GuiObject, surface: string, handle: any)
		handle.nativeSurface = if surface == "plain" then nil else surface
		if surface == "plain" or surface == "scrim" then
			handle.suppressStates = true
			handle.nativeInteractive = false
		else
			handle.suppressStates = false
			handle.nativeInteractive = handle.class == "Button" or handle.class == "Toggle"
			if surface == "accent" and instance:IsA("TextButton") then
				-- primary-action treatment: sheet rules carry accent fill + label
				handle.surfaceKind = "accent"
			end
		end
		if surface == "badge" and instance:IsA("ImageLabel") then
			instance.ScaleType = Enum.ScaleType.Crop -- not a styled property
		end
		syncTags(handle)
	end

	local function applySurface(instance: GuiObject, surface: string, handle: any?)
		if handle ~= nil then
			-- recorded in BOTH modes: decoration-slot classification is a
			-- semantic decision and must not depend on whether paint is native
			handle.declaredSurface = surface
			syncChrome(handle)
		end
		if nativeMode and handle ~= nil then
			applySurfaceNative(instance, surface, handle)
			return
		end
		assertBespokePaint("BackgroundColor3")
		if surface == "base" then
			instance.BackgroundTransparency = 0
			instance.BackgroundColor3 = COLOR.surface
		elseif surface == "raised" then
			instance.BackgroundTransparency = 0
			instance.BackgroundColor3 = COLOR.surfaceStrong
			corner(instance, style.radii.panel, nil, handle)
			hairline(instance)
		elseif surface == "control" then
			instance.BackgroundTransparency = 0
			instance.BackgroundColor3 = COLOR.control
			corner(instance, style.radii.control, nil, handle)
		elseif surface == "badge" then
			-- circular identity badges (racer headshots / initial chips):
			-- surface-raised fill behind a cropped circle — matches the game's
			-- avatar-badge convention (fallback fill visible until art loads)
			instance.BackgroundTransparency = 0
			instance.BackgroundColor3 = COLOR.surfaceStrong
			local circle = Instance.new("UICorner")
			circle.CornerRadius = UDim.new(0.5, 0)
			circle.Parent = instance
			if instance:IsA("ImageLabel") then
				instance.ScaleType = Enum.ScaleType.Crop
			end
		elseif surface == "chip" then
			-- floating drag chips: control fill + a hairline OUTLINE so a
			-- stacked group reads as distinct cards (director 2026-07-20)
			instance.BackgroundTransparency = 0
			instance.BackgroundColor3 = COLOR.control
			corner(instance, style.radii.control, nil, handle)
			hairline(instance)
		elseif surface == "plain" then
			-- chrome-less control: ONLY the content shows (in-cell glyph
			-- buttons like the playlist stars). No fill, no corner, no
			-- hairline, no hover/pressed treatment; the focus ring still
			-- applies for gamepad reachability.
			instance.BackgroundTransparency = 1
			local chrome = instance:FindFirstChild("Hairline")
			if chrome then
				chrome:Destroy()
			end
			for _, child in instance:GetChildren() do
				if child:IsA("UICorner") then
					child:Destroy()
				end
			end
			if handle ~= nil then
				handle.suppressStates = true
			end
		elseif surface == "accent" then
			-- on a Button this is the PRIMARY-ACTION treatment: accent fill,
			-- high-contrast label, hover/pressed states in accent space
			-- (director report 2026-07-20: the neutral control fill did not
			-- read as a button). On plain frames it stays the flat indicator
			-- fill (table resize preview, drop indicator).
			instance.BackgroundTransparency = 0
			instance.BackgroundColor3 = COLOR.accent
			if handle ~= nil and instance:IsA("TextButton") then
				handle.surfaceKind = "accent"
				instance.TextColor3 = COLOR.onAccent
				if handle.applyRestingFill ~= nil then
					handle.applyRestingFill()
				end
			end
		elseif surface == "scrim" then
			-- a scrim is a backdrop, not a control: dimmed fill, no chrome,
			-- and no hover/pressed feedback even when it is a Button
			instance.BackgroundTransparency = style.extra.scrimOpacity
			instance.BackgroundColor3 = toColor3(style.colors.surface)
			local chrome = instance:FindFirstChild("Hairline")
			if chrome then
				chrome:Destroy()
			end
			for _, child in instance:GetChildren() do
				if child:IsA("UICorner") then
					child:Destroy()
				end
			end
			if handle ~= nil then
				handle.suppressStates = true
			end
		end
		-- THE IMAGE IS THE BUTTON, again: every branch above just painted a
		-- plate, a corner and possibly a hairline, and on a skinned node all
		-- three sit UNDER the art. Re-suppress here rather than branching inside
		-- each case, so no future surface can quietly reintroduce the border the
		-- director asked us to remove.
		if handle ~= nil and handle.chrome ~= nil then
			applySkinnedSuppression(instance, true)
		end
	end

	-- interactive state feedback for Buttons and Toggle rows: rest/hover/
	-- pressed fills + a quick pressed dip (UIScale), reduced-motion aware
	local function wireInteractiveStates(button: TextButton, handle: any)
		assertBespokePaint("BackgroundColor3")
		button.BackgroundTransparency = 0
		button.BackgroundColor3 = COLOR.control
		corner(button, style.radii.control, nil, handle)
		hairline(button)
		-- resting fill honors selection: hover-leave on a selected row must
		-- restore controlSelected, never strip the tint (live-found 2026-07-19)
		local function restingFill(): Color3
			if handle.surfaceKind == "accent" then
				return COLOR.accent
			end
			return if handle.isSelected then COLOR.controlSelected else COLOR.control
		end
		local function hoverFill(): Color3
			if handle.surfaceKind == "accent" then
				return COLOR.accent:Lerp(Color3.new(1, 1, 1), 0.12)
			end
			return COLOR.controlHover
		end
		local function pressedFill(): Color3
			if handle.surfaceKind == "accent" then
				return COLOR.accent:Lerp(Color3.new(0, 0, 0), 0.18)
			end
			return COLOR.controlPressed
		end
		local function setFill(color: Color3, instant: boolean?, chromeState_: string?)
			if handle.suppressStates then
				return
			end
			-- THE IMAGE IS THE BUTTON (fallback mode). A skinned node's plate is
			-- suppressed, so painting a fill on it would either do nothing or
			-- punch a coloured rectangle out from behind the art. The interaction
			-- feedback is the decoration's TINT instead — the same ladder the
			-- native `Chrome — <slot> hover/pressed` rules apply.
			if handle.chrome ~= nil then
				if chromeState_ ~= nil then
					local tint = (chrome_slots.TINT :: any)[chromeState_]
					if tint ~= nil then
						handle.chrome.ImageColor3 = Color3.new(tint, tint, tint)
					end
				end
				return
			end
			if instant or isReducedMotion() then
				button.BackgroundColor3 = color
			else
				TweenService:Create(button, motionInfo(style.motion.fast), { BackgroundColor3 = color }):Play()
			end
		end
		handle.applyRestingFill = function()
			setFill(restingFill(), true, "rest")
		end
		-- the hover FILL is exposed for enableHover (UI-PARADIGM-001): the renderer
		-- wires MouseEnter to it ONLY when the pointer class is live, so a
		-- pure-touch device allocates no hover wiring. Pressed + the leave-recovery
		-- below stay unconditional (touch presses fire MouseButton1Down/Up too).
		handle.applyHoverFill = function()
			if button.Active ~= false then
				setFill(hoverFill(), nil, "hover")
			end
		end
		button.MouseLeave:Connect(function()
			setFill(restingFill(), nil, "rest")
			-- the pressed dip must ALWAYS recover: MouseButton1Up never fires
			-- when the button is released off-target (or the row is dragged
			-- away), which left rows visibly shrunken (director hand-test
			-- 2026-07-20: "one row is narrower than the others")
			local scale = handle.motionScale or handle.uiScale
			if scale ~= nil then
				if not isReducedMotion() and not handle.suppressStates then
					TweenService:Create(scale, motionInfo(style.motion.fast), { Scale = 1 }):Play()
				else
					scale.Scale = 1
				end
			end
		end)
		button.MouseButton1Down:Connect(function()
			setFill(pressedFill(), true, "pressed")
			if not isReducedMotion() and not handle.suppressStates then
				TweenService:Create(
					ensureScale(button, handle),
					motionInfo(style.motion.fast),
					{ Scale = style.extra.pressedScale }
				):Play()
			end
		end)
		button.MouseButton1Up:Connect(function()
			-- verifier F4: the release fill is hover ONLY where hover is wired
			-- (pointer live). Touch taps fire MouseButton1Down/Up too, and a
			-- pure-touch device has no MouseLeave to recover a leaked hover
			-- tint — release must return to RESTING there.
			if handle.hoverStateConn ~= nil then
				setFill(hoverFill(), nil, "hover")
			else
				setFill(restingFill(), nil, "rest")
			end
			TweenService:Create(scale, motionInfo(style.motion.fast), { Scale = 1 }):Play()
		end)
	end

	-- THE KNOB'S TWO STOPS, written against the BUTTON (see buildToggleVisual).
	-- The track is 44 wide with its right edge at `width - 12`, so its left edge is
	-- `width - 56` and the knob's old `+2`/`+22` offsets inside it are these two
	-- numbers. Named constants because "travel is byte-identical, skinned or flat"
	-- is an assertion this stage makes, and a magic number in two places is how a
	-- travel assertion quietly stops being about the same geometry.
	local TOGGLE_KNOB_OFF = UDim2.new(1, -54, 0.5, 0)
	local TOGGLE_KNOB_ON = UDim2.new(1, -34, 0.5, 0)

	-- THE LABEL COLUMN IS THE COLUMN THE SOLVER RESERVED (director round 9,
	-- found live 2026-07-26). It used to be built from `style.space.*` — the
	-- style captured when this ScreenTarget was CONSTRUCTED — while the measure
	-- seam reserved it from the LIVE snapshot. Under Studio Neutral the two
	-- agree to the byte (space.s + 4 = 12 = trackInset, space.m = 16), which is
	-- why it survived four stages; under classic-desktop the solver reserved 28
	-- px and this drew 20, and the label read "Mu".
	--
	-- One description, two consumers: `themeSnapshot.toggleRowPadding` is what
	-- the renderer's measure seam uses. Falling back to the boot style when no
	-- package is installed keeps the flat default byte-identical, because that
	-- fallback IS the neutral snapshot's answer.
	local function toggleLabelBox(): (UDim2, UDim2)
		local snap = activeThemeSnapshot
		if type(snap) ~= "table" then
			snap = { controls = { toggle = { trackWidth = 44, trackInset = 12 } }, space = style.space }
		end
		local pad = themeSnapshot.toggleRowPadding(snap)
		return UDim2.fromOffset(pad.left, 0), UDim2.new(1, -(pad.left + pad.right), 1, 0)
	end

	-- re-applied on a theme swap: the label column moves with the metrics that
	-- reserved it, and a Toggle built under one package must not keep another's
	local function applyToggleLabelBox(handle: any)
		local label = handle.labelInstance
		if label == nil or handle.class ~= "Toggle" then
			return
		end
		local pos, size = toggleLabelBox()
		label.Position = pos
		label.Size = size
	end

	-- Toggle rows get a real knob-track (pill track right-aligned, animated
	-- knob, accent fill when on). The label lives in a DEDICATED child
	-- TextLabel sized to clear the track — the button's own text region does
	-- not reliably honor UIPadding, which let labels run under the track
	-- (director report 2026-07-19).
	local function buildToggleVisual(button: TextButton, handle: any)
		button.Text = ""
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		local labelPos, labelSize = toggleLabelBox()
		label.Position = labelPos
		label.Size = labelSize
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Center
		-- ONE LINE, NEVER A BROKEN WORD (director finding 13, measured live
		-- 2026-07-26). The reserved label column is `ceil(the engine's own
		-- measurement)` and the engine draws exactly that, so under four of the
		-- nine reference packages the column and the drawn bounds are EQUAL to
		-- the pixel (Studio Neutral 35/35, classic-desktop 28/28, and the
		-- ValueProbe's "Candlelight" at 67/67 and 73/73). With `TextWrapped` a
		-- one-pixel shortfall does not clip a pixel — it BREAKS THE WORD:
		-- perturbing the live Music row by −1 px collapsed `TextBounds` from
		-- 35x16 to 28x16, which is "Musi" over "c", the second line clipped by a
		-- 28 px row. That is the director's "Musi c" exactly, and the row IS
		-- perturbed on every flip, because the press affordance scales the whole
		-- control by `extra.pressedScale` (0.985 — measured live at 104 -> 102.44
		-- -> 104 under classic-desktop).
		--
		-- Single-line with an end ellipsis is the same floor a Button's label
		-- gets: the measured width is a floor the row grows to where it can, and
		-- where it cannot the label ellipsizes instead of breaking. The SOLVER
		-- measures one line too (`singleLine` on the layout node), so the two
		-- seams cannot disagree about how many lines this is.
		label.TextWrapped = false
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.TextSize = 16
		if not nativeMode then
			-- native: the "Text default" class rule owns label paint (a write
			-- here would pin the label's color across theme swaps)
			assertBespokePaint("TextColor3")
			-- the pre-paint floor; the Toggle's role face reaches this lifted label
			-- through the `textFont` write, exactly as its `textSize` does
			label.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json")
			label.TextColor3 = COLOR.content
		end
		label.Parent = button
		handle.labelInstance = label
		-- AN IMAGELABEL, NOT A FRAME (ADR-0020 R3 cap 10). With no `Image` it is a
		-- Frame in every observable way — same background, same UICorner, same
		-- UIStroke — and it is what lets a package's `toggleTrack` recipe paint the
		-- switch as ART without the adapter creating a second instance to hold it.
		local track = Instance.new("ImageLabel")
		track.Name = "Track"
		track.AnchorPoint = Vector2.new(1, 0.5)
		track.Position = UDim2.new(1, -12, 0.5, 0)
		track.Size = UDim2.fromOffset(44, 24)
		track.ZIndex = 1
		track.BackgroundColor3 = togglePalette().trackOff
		-- opacity: bespoke keeps the plain write; native mode CANNOT — writes
		-- made before the instance joins the styled tree are STOMPED when
		-- styling first applies (director live find 2026-07-24, spike
		-- addendum: defeat is order-sensitive), so the "Toggle chrome" tag
		-- rule owns transparency there. The value-driven COLOR writes happen
		-- after styling with no competing rule and stay bespoke in both modes.
		track.BackgroundTransparency = 0
		if nativeMode then
			CollectionService:AddTag(track, "luau-toggle-chrome")
		end
		track.BorderSizePixel = 0
		corner(track, style.radii.pill, true)
		hairline(track, true)
		-- THE KNOB IS A SIBLING OF THE TRACK, not its child (ADR-0020 R3 cap 10).
		-- Every per-state rule a package emits is a CHILD COMBINATOR off the
		-- interactive node (`.luau-interactive:Press > .luau-chrome-toggleKnob`),
		-- and a knob one level deeper could not be reached by one — so per-state
		-- knob art would have been emitted and never applied, which is exactly the
		-- defect class this stage exists to remove.
		--
		-- TRAVEL IS BYTE-IDENTICAL. The track's right edge is `width - 12` and it is
		-- 44 wide, so its left edge is `width - 56`; the knob's two stops were
		-- `+2` and `+22` inside it, i.e. `width - 54` and `width - 34` here. Art
		-- never moves geometry — the same two absolute positions, written against
		-- the button.
		local knob = Instance.new("ImageLabel")
		knob.Name = "Knob"
		knob.AnchorPoint = Vector2.new(0, 0.5)
		knob.Position = TOGGLE_KNOB_OFF
		knob.Size = UDim2.fromOffset(20, 20)
		knob.ZIndex = 2 -- above the track it used to be parented inside
		-- the resolver, not a captured constant: a toggle built while a package is
		-- installed must be born in that package's palette, not repainted into it
		-- on its first value change
		knob.BackgroundColor3 = togglePalette().knobOff
		knob.BackgroundTransparency = 0 -- bespoke path; native rides the tag rule
		if nativeMode then
			CollectionService:AddTag(knob, "luau-toggle-chrome")
		end
		knob.BorderSizePixel = 0
		corner(knob, style.radii.pill, true)
		track.Parent = button
		knob.Parent = button
		handle.track = track
		handle.knob = knob
		-- addressable by PATH, like every other managed child: the knob's travel and
		-- the track's resolved art are what "art never moves geometry" is asserted
		-- from, and a probe that has to walk the tree to find them is a probe that
		-- silently stops finding them
		for name, part in { Track = track, Knob = knob } do
			instancesByPath[handle.path .. "/" .. name] = part
		end
		-- the package's toggle recipes, applied the moment the assembly exists —
		-- not only on the next classification pass, or a toggle built while a
		-- skinned package is installed would be born palette-true and stay that way
		syncToggleArt(handle)
	end

	-- applyToggleValue(handle, on): the ONE value-driven paint site for a toggle,
	-- and now the one that reads the live palette rather than constants captured
	-- when the adapter was built.
	--
	-- MID-TWEEN RECOLOUR. A theme swap can land while the ON/OFF tween is still
	-- running toward the OLD colour. A Tween keeps writing its own target until
	-- it completes, so simply setting the new colour would be overwritten a frame
	-- later and the pill would settle on the outgoing theme's accent. The colour
	-- tween is therefore CANCELLED before a new one is issued, and a recolour
	-- (`retheme = true`) SNAPS rather than animating: the value did not change,
	-- so there is nothing to animate — a theme swap that visibly slides its
	-- colours reads as a state change that never happened.
	local function applyToggleValue(handle: any, on: boolean, retheme: boolean?)
		local track: Frame? = handle.track
		local knob: Frame? = handle.knob
		if track == nil or knob == nil then
			return
		end
		-- remembered so a live retheme can repaint the CURRENT state without the
		-- caller having to know it (and without touching the value)
		handle.toggleOn = on
		-- ON/OFF IS A VALUE, AND ART READS IT AS A TAG (ADR-0020 R3 cap 10). No
		-- engine GuiState reports a value — which is exactly why `togglePalette`
		-- stayed a bespoke colour write — so the package's `selected` variant rules
		-- key on `luau-toggle-on`, flipped at the same site and from the same fact
		-- the colours are. It goes through syncTags (and therefore through
		-- classifyTags' desired set) because every `luau-*` tag on this instance is
		-- diffed away otherwise — the Step 3.5 fix round's exact lesson.
		syncTags(handle)
		-- the FALLBACK-mode half: with no sheet there is no rule to swap the
		-- picture, so the same variant map is resolved here
		syncToggleArt(handle)
		local palette = togglePalette()
		local trackColor = if on then palette.trackOn else palette.trackOff
		local knobColor = if on then palette.knobOn else palette.knobOff
		local knobPos = if on then TOGGLE_KNOB_ON else TOGGLE_KNOB_OFF
		if handle.toggleTrackTween ~= nil then
			handle.toggleTrackTween:Cancel()
			handle.toggleTrackTween = nil
		end
		if retheme == true or isReducedMotion() then
			track.BackgroundColor3 = trackColor
			knob.BackgroundColor3 = knobColor
			if retheme ~= true then
				knob.Position = knobPos
			end
		else
			local tween = TweenService:Create(track, motionInfo(style.motion.normal), { BackgroundColor3 = trackColor })
			handle.toggleTrackTween = tween
			tween:Play()
			-- the KNOB's colour snaps while its position slides: the two states'
			-- knob colours are a contrast pair, and interpolating between them
			-- passes through the middle, where it is readable against neither
			knob.BackgroundColor3 = knobColor
			TweenService:Create(knob, motionInfo(style.motion.normal), { Position = knobPos }):Play()
		end
	end

	-- ASSIGNED HERE, not beside its declaration: it calls `applyToggleValue`
	-- above, and a local declared later is not an upvalue.
	function refreshToggleVisuals()
		for _, handle in handlesByPath do
			if handle.track ~= nil and handle.knob ~= nil then
				applyToggleValue(handle, handle.toggleOn == true, true)
			end
		end
	end

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
					-- repoints the existing LuauUIStyleLink rather than adding a
					-- second one: two links means two sheets on one tree and the
					-- cascade winner depends on load order
					native_style.linkAt(gui, effective)
				end
			end
		end
		themeRoots = live
	end

	local lastRootHandle: any = nil

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
		gui.Name = `LuauUI_{screenId}`
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		if nativeMode then
			-- one StyleLink per LuauUI root (plan §6): the single application point
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

	-- real clipping (touch-scroll design 2026-07-20): a node whose blueprint
	-- declares clipChildren=true becomes a CLIP HOST — its descendants parent
	-- under it (engine hierarchy) with positions relative to the host, so
	-- ClipsDescendants crops partial overflow (scrolled table rows). Window-
	-- space rects stay the renderer contract; the subtraction happens here.
	-- `path` joined the entry for the presentation channel (ADR-0022 Decision 2): an
	-- offset accumulating down a subtree stops at the nearest REAL PARENT, whose own
	-- move already carries its children, and this is how a child knows where that is.
	local clipHosts: { [string]: { instance: Instance, rect: any?, children: { any }, path: string } } = {}
	local function hostFor(path: string): any
		local best: any = nil
		local bestLen = -1
		for hostPath, entry in clipHosts do
			if #hostPath > bestLen and string.sub(path, 1, #hostPath + 1) == hostPath .. "/" then
				best = entry
				bestLen = #hostPath
			end
		end
		return best
	end
	-- the effective-target expander (B-BTN3) lives beside its control, so it must be
	-- re-based from the SAME clip-host origin — and re-based AGAIN whenever that
	-- origin arrives or moves. RS-A16-D1b (found live 2026-07-26): the renderer pushes
	-- hit rects BEFORE the commit that writes rects, so on a fresh build a clip host's
	-- rect is not yet current when the expander is first placed, and the renderer's
	-- own cache (which stores only the WANTED rect) never asks again. Measured after a
	-- scenario `reset()`: an expander 74px below the button it belongs to. Placing it
	-- here, in the one function that re-bases a node, is what makes the two unable to
	-- disagree.
	-- ===== THE PRESENTATION CHANNEL (ADR-0022 Decision 2) =================
	--
	-- A presentation transform composes onto the solver's rect at the WRITE, so a
	-- motion never touches solver geometry and a re-solve never loses the motion:
	-- `applyRect` is the one place a Position is written, and it adds the offset
	-- every time.
	--
	-- THE INSTANCE TREE IS FLAT (docs/lessons/screen-target-tree-is-flat.md), and
	-- that is the load-bearing fact here. Every node parents under the root gui
	-- unless a REAL PARENT claimed it (a clip host, or the new canvas group), so
	-- moving a container's own instance moves nothing but that container — the
	-- keyboard keep-visible shift on the root node would have moved one transparent
	-- frame and nothing the player can see. So the offset ACCUMULATES down the
	-- subtree: a node pays its own transform plus every ancestor's, stopping at its
	-- real parent, whose own move already carries it. One rule, and the root case
	-- (the whole surface shifts) falls out of it.
	local presentationTransforms: { [string]: any } = {}
	local presentationCount = 0
	-- path -> the handles a transform on that path composes into (itself first).
	-- A motion writes EVERY FRAME while it runs, and scanning every handle on the
	-- target per write would make a leaf's 60 Hz motion cost the whole tree. Built
	-- once per animated path and dropped wholesale on any structural change, which is
	-- rare next to a frame.
	local subtreeCache: { [string]: { any } } = {}
	local function subtreeOf(path: string): { any }
		local hit = subtreeCache[path]
		if hit ~= nil then
			return hit
		end
		local prefix = path .. "/"
		local out: { any } = {}
		for otherPath, other in handlesByPath do
			if otherPath == path or string.sub(otherPath, 1, #prefix) == prefix then
				table.insert(out, other)
			end
		end
		subtreeCache[path] = out
		return out
	end

	-- cached on the handle so `applyRect` — the hot path — adds two numbers instead
	-- of walking a path. Recomputed for the affected subtree when a transform moves,
	-- and once at creation for a node born under a live one.
	local function recomputePresentationOffset(handle: any)
		local ox, oy = 0, 0
		if presentationCount > 0 then
			local own = presentationTransforms[handle.path]
			if own ~= nil then
				ox += own.x or 0
				oy += own.y or 0
			end
			-- ancestors, down to (and excluding) the real parent
			local stop = if handle.clipHost ~= nil then #handle.clipHost.path else 0
			local path = handle.path
			local i = #path
			while i > 1 do
				if string.sub(path, i, i) == "/" then
					local ancestor = string.sub(path, 1, i - 1)
					if #ancestor <= stop then
						break
					end
					local t = presentationTransforms[ancestor]
					if t ~= nil then
						ox += t.x or 0
						oy += t.y or 0
					end
				end
				i -= 1
			end
		end
		handle.presentationOffsetX = ox
		handle.presentationOffsetY = oy
	end

	local function applyHitExpander(handle: any)
		local expander = handle.hitExpander
		local rect = handle.hitRectWant
		if expander == nil or rect == nil then
			return
		end
		local ox, oy = 0, 0
		if handle.clipHost ~= nil and handle.clipHost.rect ~= nil then
			ox, oy = handle.clipHost.rect.x, handle.clipHost.rect.y
		end
		-- the expander is this control's HIT surface, so it travels with the paint:
		-- a shifted control whose target stayed behind would be a control you can see
		-- and cannot press
		expander.Position = UDim2.fromOffset(
			rect.x - ox + (handle.presentationOffsetX or 0),
			rect.y - oy + (handle.presentationOffsetY or 0)
		)
		expander.Size = UDim2.fromOffset(rect.w, rect.h)
		expander.ZIndex = handle.instance.ZIndex - 1
	end

	local function applyRect(handle: any)
		local rect = handle.windowRect
		if rect == nil then
			return
		end
		local ox, oy = 0, 0
		if handle.clipHost ~= nil and handle.clipHost.rect ~= nil then
			ox, oy = handle.clipHost.rect.x, handle.clipHost.rect.y
		end
		if handle.motionAnchorCentered then
			-- a live motion scale re-anchored this instance to its center so the
			-- UIScale pivots there (director fix round: pops and the drag ghost grew
			-- down-right from the top-left) — same rect, written as its center
			handle.instance.Position = UDim2.fromOffset(
				rect.x - ox + (handle.presentationOffsetX or 0) + rect.w / 2,
				rect.y - oy + (handle.presentationOffsetY or 0) + rect.h / 2
			)
		else
			handle.instance.Position = UDim2.fromOffset(
				rect.x - ox + (handle.presentationOffsetX or 0),
				rect.y - oy + (handle.presentationOffsetY or 0)
			)
		end
		handle.instance.Size = UDim2.fromOffset(rect.w, rect.h)
		applyHitExpander(handle)
		if handle.focusRingFloat ~= nil and handle.focusRingFloat.Parent ~= nil then
			-- the float ring rides the focused rect (it lives in the clip host,
			-- so a row that re-arranges must carry its ring along)
			local t = handle.focusRingFloat:FindFirstChild("FocusRing")
			local thickness = if t ~= nil and t:IsA("UIStroke") then t.Thickness else 2
			handle.focusRingFloat.Position = UDim2.fromOffset(
				rect.x - ox + thickness + (handle.presentationOffsetX or 0),
				rect.y - oy + thickness + (handle.presentationOffsetY or 0)
			)
			handle.focusRingFloat.Size = UDim2.fromOffset(rect.w - 2 * thickness, rect.h - 2 * thickness)
		end
		-- a semantic icon is clamped to the box this node actually has, so a rect
		-- that lands after the picture did has to re-fit it (director report
		-- 2026-07-28). No-op for every node carrying no icon art.
		refitIconArt(handle)
		if handle.path2d ~= nil then
			-- normalized control points re-scale with the solved rect (NS-A7)
			applyPathPoints(handle)
		end
	end

	-- the paint half of a transform: SCALE and ROTATION reach only the node's own
	-- instance (and whatever is really parented under it), which is why the
	-- reference points a subtree-scaling caller at a `canvasGroup` node.
	--
	-- `UIScale` IS SHARED WITH THE PRESS DIP. The engine honours ONE UIScale per
	-- object, so a second instance would make the winner unpredictable — a
	-- pressable control's motion scale therefore writes the dip's own instance, and
	-- the last writer wins by design rather than by accident.
	local function applyPresentationPaint(handle: any, t: any)
		local instance = handle.instance
		if not instance:IsA("GuiObject") then
			return
		end
		local scale = if type(t) == "table" and type(t.scale) == "number" then t.scale else nil
		local existing = handle.motionScale or handle.uiScale
		if scale ~= nil and scale ~= 1 then
			local live = existing
			if live == nil then
				live = ensureScale(instance, handle)
				handle.motionScale = live
			end
			live.Scale = scale
			-- CENTERED PIVOT (director fix round, RR parity): UIScale scales around
			-- the AnchorPoint, and the flat tree anchors top-left, so every pop and
			-- the drag ghost's pickup grow crawled down-right. While a motion scale
			-- is live the instance is re-anchored to its center; applyRect writes
			-- the same rect as its center point, so nothing else moves.
			if not handle.motionAnchorCentered then
				handle.motionAnchorCentered = true
				instance.AnchorPoint = Vector2.new(0.5, 0.5)
			end
		elseif existing ~= nil then
			existing.Scale = 1
			if handle.motionScale ~= nil then
				handle.motionScale:Destroy()
				handle.motionScale = nil
			end
			if handle.motionAnchorCentered then
				handle.motionAnchorCentered = nil
				instance.AnchorPoint = Vector2.new(0, 0)
			end
		end
		-- Rotation is paint-only in Roblox (it never moves layout or hit geometry),
		-- and no rule writes it, so it needs no claim
		local rotation = if type(t) == "table" and type(t.rotation) == "number" then t.rotation else 0
		instance.Rotation = rotation
	end

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
	-- LuauUI's FLAT tree they are not even the engine parent of their children:
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
		createOpts: { canvasGroup: boolean? }?
	): any
		if
			elideContainers
			and ELIDABLE_CLASSES[class]
			and decorationHint == nil
			and (createOpts == nil or createOpts.canvasGroup ~= true)
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
		createOpts: { canvasGroup: boolean? }?
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
		if class == "ScrollView" and opts ~= nil and opts.forceScrollFallback == true then
			-- fallback path (NS-A2/NS-I2): identical clip-host behavior with no
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
			-- native scroll host (NS-A2; spike m1/m2): the solver owns content
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
			instance.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
			instance.ScrollingDirection = Enum.ScrollingDirection.Y
			instance.Selectable = false -- selection policy (NS-A11): never selectable by default
		end
		local handle = { instance = instance, path = path, class = class }
		-- the surface a recycled node is re-parented back under. Kept in a module
		-- local, NOT on the handle: a field there is walked by the subtree index and
		-- by the presentation channel, and adding one changed a motion's subtree
		-- count from 3 to 5 before any of the recycling code even ran.
		lastRootHandle = rootHandle
		if instance:IsA("CanvasGroup") then
			handle.canvasGroupInstance = instance
			-- a fade group is a REAL PARENT: its descendants live inside it (which is
			-- what the buffer needs) and their window-space rects are re-based against
			-- it by exactly the clip-host machinery, whose entry is the adapter's
			-- general "this node is a real instance parent" record
			clipHosts[path] = { instance = instance, rect = handle.windowRect, children = {}, path = path }
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
		if class == "Path" then
			-- stroked-path leaf (NS-A7): engine Path2D strokes inside a
			-- transparent holder; color comes from the style role hint
			local path2d = Instance.new("Path2D")
			path2d.Name = "Stroke"
			path2d.Thickness = 4
			path2d.Color3 = COLOR.content
			path2d.Parent = instance
			handle.path2d = path2d
		end
		if instance:IsA("TextLabel") or instance:IsA("TextButton") then
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
				-- sheet (.luau-surface-control, .luau-interactive, :Hover/:Press)
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
			-- captures focus natively (engine-facts §8); LuauUI's own focus graph
			-- still drives the ring via setFocusVisual.
			instance.Selectable = true
		end
		-- clip-host parenting: descendants of a clip host live INSIDE it so
		-- the engine crops them; everything else stays flat under the root
		local host = hostFor(path)
		if host ~= nil then
			handle.clipHost = host
			table.insert(host.children, handle)
			instance.Parent = host.instance
		else
			instance.Parent = rootHandle.gui
		end
		instancesByPath[path] = instance
		handlesByPath[path] = handle
		-- the subtree index is derived from this map, so it dies with any structural
		-- change rather than being patched at three sites
		subtreeCache = {}
		-- a node born INSIDE a live presentation transform (a row added to a shifted
		-- surface, a re-entering transition subtree) starts at the composed position:
		-- its first rect write must already carry the offset, or it appears at rest for
		-- a frame and jumps
		recomputePresentationOffset(handle)
		-- decoration LAST: every classification input (class, surface, the
		-- clip-host parenting, the control's own slot hint) is settled by now, so
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
		local host = handle.clipHost
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
		and only a device pass can close it. DB-4 lived exactly there.

		Returns false when the path has no activate handler, so a caller can tell
		"nothing there" from "did nothing".
	]]
	function adapter.driveActivate(path: string, meta: any?): boolean
		local handle = handlesByPath[path]
		if handle == nil or handle.activate == nil then
			return false
		end
		handle.activate(meta)
		return true
	end

	-- ENGINE TEXT PREMEASUREMENT (text-measurement milestone): the renderer
	-- hands over the WORDS its last solve could not size exactly; this measures
	-- them with the engine's own bounds API off the render path and feeds the
	-- widths back, which costs exactly one re-solve. Implementation and the
	-- reasoning live in src/client/text_premeasure.
	function adapter.measureTextWidths(requests: { any }, done: (results: { any }, final: boolean?) -> ())
		text_premeasure.measure(requests, done)
	end

	-- whole-surface visibility: the presenter's no-pop text gate mounts and
	-- solves a screen and only then lets it be seen. ScreenGui.Enabled, so a
	-- hidden surface costs no per-node writes and reveals in one property.
	function adapter.setRootVisible(rootHandle: any, visible: boolean)
		rootHandle.gui.Enabled = visible
	end

	-- native-style introspection + control surface (ledger NSS-A2/A6/A7; the
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
	-- the package's `.luau-state-error > .<layerTag>` art rules match; a rung-2
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

	-- THE DECODE JUDGEMENT (RS-A16-D5), beside the census it explains: for every
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
		-- LAYER COST IN DATAMODEL UNITS (ledger RS-A17). `census.layers` counts
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
		-- lifted labels are decoration cost too (TP-M8): counted so the
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
		applyRect(handle)
		-- a clip host that moved re-bases every child (children may have
		-- received their rects before the host did)
		local entry = clipHosts[handle.path]
		if entry ~= nil then
			entry.rect = rect
			for _, child in entry.children do
				applyRect(child)
			end
		end
	end

	function adapter.setActivateHandler(handle: any, fn: (meta: any?) -> ())
		local instance = handle.instance
		-- kept on the handle so the effective-target hit expander (B-BTN3) can
		-- forward to the SAME activation path rather than becoming a second one
		handle.activate = fn
		if instance:IsA("GuiButton") then
			handle.activatedConn = instance.Activated:Connect(function(inputObject: InputObject)
				-- activate meta: pointer kind + held modifiers, so list
				-- semantics (replace/toggle/range vs touch additive) resolve
				-- per device (ADR-0008)
				local userInputType = inputObject and inputObject.UserInputType
				local pointer = "mouse"
				if userInputType == Enum.UserInputType.Touch then
					pointer = "touch"
				elseif userInputType ~= nil and string.find(tostring(userInputType), "Gamepad") ~= nil then
					pointer = "gamepad"
				elseif userInputType == Enum.UserInputType.Keyboard then
					-- NOT A POINTER AT ALL (roadmap Step 8). The engine fires the
					-- SELECTED GuiButton's Activated for a keyboard press too, and
					-- that arrived here classified as a mouse click — so the one
					-- signal that identifies an engine-selection echo of an IAS
					-- Activate was indistinguishable from a real click. Naming it
					-- is what lets the presenter collapse the pair and nothing else
					-- (see dispatchActivate).
					pointer = "keyboard"
				end
				local function down(keyCode: Enum.KeyCode): boolean
					return UserInputService:IsKeyDown(keyCode)
				end
				-- window-space tap position rides the meta so the presenter can run
				-- the modal Zone-A geometry (a scrim/catcher tap; modal-dismissal
				-- spec §3.2). InputObject.Position is inset-subtracted gui space
				-- (this ScreenGui renders IgnoreGuiInset), so add the inset.
				local tapPos = inputObject and inputObject.Position
				local guiInset = GuiService:GetGuiInset()
				fn({
					source = "pointer",
					pointer = pointer,
					x = if tapPos ~= nil then tapPos.X + guiInset.X else nil,
					y = if tapPos ~= nil then tapPos.Y + guiInset.Y else nil,
					shift = down(Enum.KeyCode.LeftShift) or down(Enum.KeyCode.RightShift),
					toggle = down(Enum.KeyCode.LeftControl) or down(Enum.KeyCode.RightControl) or down(
						Enum.KeyCode.LeftMeta
					) or down(Enum.KeyCode.RightMeta),
				})
			end)
		end
	end

	-- pointer capture (ADR-0008): down on the zone captures; global move/up
	-- route to it until release, and the zone's cursor hint stays applied
	local activeCapture: any = nil
	local function endCapture(cancelReason: string?)
		if activeCapture == nil then
			return
		end
		local captured = activeCapture
		if cancelReason ~= nil and captured.handle.pointer and captured.handle.pointer.cancel then
			local keep = captured.handle.pointer.cancel(cancelReason)
			if keep == true and cancelReason == "removed" then
				-- a drag-owned LIFT unmounted its own origin row: the capture
				-- (global UIS connections + closured handlers) stays alive so
				-- the drag can finish (ADR-0008)
				return
			end
		end
		for _, connection in captured.connections do
			connection:Disconnect()
		end
		activeCapture = nil
		captureHint = nil
		applyCursor()
	end

	-- Escape opens the Roblox CoreGui menu and CANNOT be intercepted (engine
	-- truth D1: the key is permanently core-reserved). The next best drag UX
	-- (director round 2): the moment the menu opens, ANY live pointer capture
	-- aborts — no stuck drags behind the menu. Adapter-level: every draggable
	-- gets this, not just tables. Disconnected on destroyRoot.
	local menuConn = GuiService.MenuOpened:Connect(function()
		endCapture("interrupted")
	end)

	-- ENGINE TRUTH (verified live 2026-07-19): InputObject.Position is in the
	-- inset-subtracted gui space (topbar excluded) while this adapter renders
	-- with IgnoreGuiInset=true, whose AbsolutePositions are window space — so
	-- pointer positions must add the gui inset before reaching drag math,
	-- which compares against solver rects (window space).
	local function toWindowSpace(
		position: Vector3,
		pointerType: string?
	): { x: number, y: number, pointerType: string? }
		local inset = GuiService:GetGuiInset()
		return { x = position.X + inset.X, y = position.Y + inset.Y, pointerType = pointerType }
	end
	local function pointerTypeOf(inputObject: InputObject): string
		return if inputObject.UserInputType == Enum.UserInputType.Touch then "touch" else "mouse"
	end

	-- ENGINE CONNECTION CENSUS (roadmap Step 4, metric M4). Read-only.
	--
	-- The slot list is derived from the REAL assignment sites, not invented: the
	-- first version of this function counted four names that exist nowhere in
	-- the repository (they were permanently 0) while missing nine connections
	-- that do exist — a census that could only ever undercount, reported as if
	-- it were complete. The platform review caught it; the list below is grepped
	-- from `handle.<name>Conn* = ...:Connect(` in this file and screen_chrome.
	--
	-- What it counts: adapter-held RBXScriptConnections reachable from a handle.
	-- What it does NOT count, and says so: connections held in closures rather
	-- than on a handle (the pointer-capture list, UIDragDetector handlers, touch
	-- gesture handlers and the scroll-position observer all return a detach
	-- function and keep their connections captured), and anything the engine
	-- allocates internally, which no script can see.
	local CENSUS_SLOTS = {
		"activatedConn",
		"pointerBeganConn",
		"hoverEnterConn",
		"hoverLeaveConn",
		"hoverStateConn",
		"discloseEnterConn",
		"discloseLeaveConn",
		"discloseTouchConn",
		"scrollConn",
		"textChangedConn",
		"focusedConn",
		"focusLostConn",
		"oskReturnConn",
		"chromeOverrideConn",
		"barConn",
		"barWindowConn",
		-- a LIST of connections rather than one (screen_chrome's text lift)
		"chromeTextConns",
	}
	function adapter.connectionCensus(): any
		local perSlot: { [string]: number } = {}
		for _, slot in CENSUS_SLOTS do
			perSlot[slot] = 0
		end
		local nodes = 0
		for _, handle in handlesByPath do
			nodes += 1
			for _, slot in CENSUS_SLOTS do
				local v = (handle :: any)[slot]
				if type(v) == "table" then
					perSlot[slot] += #v
				elseif v ~= nil then
					perSlot[slot] += 1
				end
			end
		end
		local handleTotal = 0
		for _, n in perSlot do
			handleTotal += n
		end
		-- the adapter's own always-on connection, counted by LIVENESS rather
		-- than as a constant 1
		local global = if menuConn ~= nil and menuConn.Connected then 1 else 0
		local captureHeld = 0
		if activeCapture ~= nil and activeCapture.connections ~= nil then
			captureHeld = #activeCapture.connections
		end
		return {
			nodes = nodes,
			perSlot = perSlot,
			handleTotal = handleTotal,
			global = global,
			captureHeld = captureHeld,
			total = handleTotal + global + captureHeld,
			excluded = {
				"connections captured in closures rather than stored on a handle: UIDragDetector "
					.. "(setDragDetector), touch gestures (setTouchGestureHandlers) and the CanvasPosition "
					.. "observer (observeScroll) each return a detach function and hold their connection there",
				"anything the engine allocates internally, which is not observable from script",
			},
			note = "adapter-held RBXScriptConnections reachable from a handle, plus the live global and any "
				.. "in-flight pointer capture. An undercount by construction, and the exclusions are listed "
				.. "rather than implied.",
		}
	end

	function adapter.setPointerHandlers(handle: any, handlers: any)
		local instance = handle.instance
		if not instance:IsA("GuiObject") then
			return
		end
		handle.pointer = handlers
		handle.pointerBeganConn = instance.InputBegan:Connect(function(inputObject: InputObject)
			if
				inputObject.UserInputType ~= Enum.UserInputType.MouseButton1
				and inputObject.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end
			-- a live capture OWNS the pointer until it ends: crossing another
			-- pointer zone mid-drag fires that zone's InputBegan, which used
			-- to silently kill the capture (no cancel reason -> stuck ghost,
			-- no drop commit; live-found in the playlist place 2026-07-20)
			if activeCapture ~= nil then
				return
			end
			local connections = {}
			activeCapture = { handle = handle, connections = connections }
			captureHint = handle.cursorHint
			applyCursor()
			table.insert(
				connections,
				UserInputService.InputChanged:Connect(function(moveObject: InputObject)
					if
						moveObject.UserInputType == Enum.UserInputType.MouseMovement
						or moveObject.UserInputType == Enum.UserInputType.Touch
					then
						if handlers.move then
							handlers.move(
								toWindowSpace(
									moveObject.Position,
									if moveObject.UserInputType == Enum.UserInputType.Touch then "touch" else "mouse"
								)
							)
						end
					end
				end)
			)
			table.insert(
				connections,
				UserInputService.InputEnded:Connect(function(endObject: InputObject)
					if
						endObject.UserInputType == Enum.UserInputType.MouseButton1
						or endObject.UserInputType == Enum.UserInputType.Touch
					then
						if handlers.up then
							handlers.up(toWindowSpace(endObject.Position, pointerTypeOf(endObject)))
						end
						endCapture()
					end
				end)
			)
			if handlers.down then
				local claimed = handlers.down(toWindowSpace(inputObject.Position, pointerTypeOf(inputObject)))
				-- a zone may DECLINE (return false): dissolve this capture so
				-- the engine's next InputBegan (another zone under the same
				-- point, e.g. the edit handle above a row body) can claim it
				if claimed == false then
					for _, connection in connections do
						connection:Disconnect()
					end
					activeCapture = nil
					captureHint = nil
					applyCursor()
				end
			end
		end)
		-- hover: request/clear the zone's semantic cursor
		if handle.class == "Grip" then
			handle.hoverEnterConn = instance.MouseEnter:Connect(function()
				hoverHint = handle.cursorHint
				applyCursor()
			end)
			handle.hoverLeaveConn = instance.MouseLeave:Connect(function()
				hoverHint = nil
				applyCursor()
			end)
		end
	end

	-- wheel scrolling (Phase 4 touch-scroll design): hover-wheel input on a
	-- scroll container routes to the renderer-wired handler
	function adapter.setScrollHandler(handle: any, fn: (number) -> ())
		local instance = handle.instance
		if not instance:IsA("GuiObject") then
			return
		end
		handle.scrollConn = instance.InputChanged:Connect(function(inputObject: InputObject)
			if inputObject.UserInputType == Enum.UserInputType.MouseWheel then
				fn(inputObject.Position.Z)
			end
		end)
	end

	-- native scroll host seam (native-substrate NS-A2; spikes m1/m2): the
	-- solver's content extent becomes the engine canvas; the ENGINE owns the
	-- live offset (wheel, touch momentum, elastic, bars); observeScroll reports
	-- engine-driven CanvasPosition changes back to the framework (windowing);
	-- setScrollPosition is the framework's programmatic keep-visible write.
	-- On the fallback path (forceScrollFallback / non-ScrollingFrame instance)
	-- these degrade to no-ops and the node stays a proven clip-only host.
	function adapter.setScrollRegion(handle: any, region: any)
		local instance = handle.instance
		if not instance:IsA("ScrollingFrame") then
			return
		end
		if region == nil then
			instance.CanvasSize = UDim2.new()
			return
		end
		instance.ScrollingDirection = if region.axis == "x"
			then Enum.ScrollingDirection.X
			else Enum.ScrollingDirection.Y
		instance.CanvasSize = UDim2.fromOffset(region.contentW, region.contentH)
	end

	function adapter.setScrollPosition(handle: any, pos: { x: number, y: number })
		local instance = handle.instance
		if instance:IsA("ScrollingFrame") then
			instance.CanvasPosition = Vector2.new(pos.x, pos.y)
		end
	end

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
		-- RS-A16-D1: the expander is a SIBLING of its control (it has to be, so the
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

	-- a hit rect needs a real object, so an elided node materialises here
	function adapter.setHitRect(handle: any, rect: any)
		ensureInstance(handle)
		local instance = handle.instance
		if rect == nil then
			handle.hitRectWant = nil
			if handle.hitExpander ~= nil then
				handle.hitExpander:Destroy()
				handle.hitExpander = nil
			end
			return
		end
		handle.hitRectWant = rect
		local expander = handle.hitExpander
		if expander == nil then
			expander = Instance.new("TextButton")
			expander.Name = "LuauUIHitExpander"
			expander.Text = ""
			expander.AutoButtonColor = false
			expander.BackgroundTransparency = 1
			expander.BorderSizePixel = 0
			expander.Selectable = false -- LuauUI's focus graph owns focus, not this
			expander.ZIndex = instance.ZIndex - 1
			-- born at the host's CURRENT visibility, so it cannot flash live for a
			-- control that is already hidden (RS-A16-D1)
			expander.Visible = instance.Visible
			expander.Parent = instance.Parent
			expander.Activated:Connect(function()
				if
					handle.activate ~= nil
					and handle.instance.Interactable ~= false
					-- ...and never activate a control the player cannot see
					and handle.instance.Visible
				then
					handle.activate({ source = "hitExpander" })
				end
			end)
			handle.hitExpander = expander
		end
		-- re-base by the clip host exactly as applyRect does (verifier finding V11).
		-- The solver rect is WINDOW space; a child of a clip host is positioned
		-- relative to that host, so using the raw rect put the invisible activation
		-- surface off by the host origin for every sub-floor control inside a
		-- ScrollView, a clipped container, or a popup panel. It is the SHARED
		-- placement path (RS-A16-D1b) so a host rect that arrives after this call
		-- re-bases the expander with the control instead of leaving it behind.
		applyHitExpander(handle)
	end

	function adapter.getScrollPosition(handle: any): { x: number, y: number }?
		local instance = handle.instance
		if not instance:IsA("ScrollingFrame") then
			return nil
		end
		local p = instance.CanvasPosition
		return { x = p.X, y = p.Y }
	end

	function adapter.observeScroll(handle: any, fn: (pos: { x: number, y: number }) -> ()): () -> ()
		local instance = handle.instance
		if not instance:IsA("ScrollingFrame") then
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

	-- native drag acquisition (native-substrate NS-A5; spike m3-dragdetector):
	-- attaches a UIDragDetector in CustomOffset mode so the DETECTOR never
	-- writes Position (LuauUI's renderer keeps that authority — the default
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
		-- LuauUI's IgnoreGuiInset=true roots that IS the renderer's window
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

	-- native touch gestures (native-substrate NS-A6; corrections §2): the
	-- ENGINE recognizes; LuauUI normalizes into stable value objects
	-- (src/input/touch_gestures) and composes/arbitrates purely. Connection is
	-- proven headless+Studio; FIRING requires real touch (VIM touch injection
	-- is RobloxScript-locked; emulator not MCP-drivable) — ledger row NS-P2.
	function adapter.setTouchGestureHandlers(handle: any, onGesture: (gesture: any) -> ()): () -> ()
		local instance = handle.instance
		if not instance:IsA("GuiObject") then
			return function() end
		end
		local touch_gestures = require(script.Parent.Parent.input.touch_gestures) :: any
		-- `normalize(kind, args)` reads `args` POSITIONALLY — it is the engine
		-- callback's argument list, in the engine's order, not a record (SEAM-3:
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

	-- engine-selection bridge (native-substrate NS-A12; spike m9): mirrors the
	-- LOGICAL focus to GuiService.SelectedObject for an OPTED-IN modal only
	-- (the renderer gates the calls). Measured constraints honored here: the
	-- mirrored instance must be Selectable=true while selected (the engine
	-- warns and REASSIGNS selection set on a non-selectable object) and the
	-- previous instance's Selectable is restored so nothing stays natively
	-- navigable after the mirror moves. nil clears selection entirely.
	-- restore the ORIGINAL Selectable when the mirror moves off an instance
	-- (verifier F3: TextFields are intrinsically Selectable for native A-press
	-- capture — hardcoding false would silently strip that). NOTE for the
	-- physical row NS-P1: intrinsically-Selectable instances (TextField) give
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
				-- node — LuauUI's focus visual is the selection affordance;
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
			-- native (NSS-A4): the pointer-live decision becomes a TAG — hover
			-- rules are compound-gated on it (.luau-pointer-live:Hover), so the
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

	-- FULL-VALUE DISCLOSURE ENGAGEMENT (Step 8.5, LTN-4). The disclosed Text
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
				if handle.clipHost ~= nil and handle.clipHost.instance ~= nil then
					local float = ringFloat
					if float == nil then
						float = Instance.new("Frame")
						float.Name = "FocusRingFloat"
						float.BackgroundTransparency = 1
						local corner = host:FindFirstChildOfClass("UICorner")
						if corner ~= nil then
							corner:Clone().Parent = float
						end
						float.Parent = handle.clipHost.instance
						handle.focusRingFloat = float
					end
					local f = float :: Frame
					local rect = handle.windowRect
					local origin = handle.clipHost.rect
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
				-- Path stroke color rides the style role hint (NS-A7): never a
				-- raw color from screen code
				handle.path2d.Color3 = if value == "accent"
					then COLOR.accent
					elseif value == "secondary" then COLOR.contentSecondary
					else COLOR.content
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
				-- at creation): reuse that entry rather than replacing it, or the
				-- children already registered in it would stop being re-based
				if clipHosts[handle.path] == nil then
					clipHosts[handle.path] =
						{ instance = instance, rect = handle.windowRect, children = {}, path = handle.path }
				end
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
			-- THE PRESENTATION TRANSFORM (ADR-0022 Decision 2; fixes SF-M9 — this
			-- branch simply did not exist, so every keep-visible shift was a headless
			-- green that never moved a device). Offset composes onto the solver's rect
			-- for this node AND its subtree (the tree is flat — see
			-- recomputePresentationOffset); scale and rotation are paint on its own
			-- instance. `nil` clears.
			local previous = presentationTransforms[handle.path]
			if value == nil then
				if previous ~= nil then
					presentationCount -= 1
				end
				presentationTransforms[handle.path] = nil
			else
				if previous == nil then
					presentationCount += 1
				end
				presentationTransforms[handle.path] = value
			end
			applyPresentationPaint(handle, value)
			for _, other in subtreeOf(handle.path) do
				recomputePresentationOffset(other)
				applyRect(other)
			end
		elseif prop == "dragHeld" then
			-- THE HELD DRAG SOURCE (director round five). Native: the tag rides
			-- syncTags and the sheet's `.luau-drag-held` rule empties the label
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
			-- rule, so in native mode the role rides a `luau-type-<role>` TAG whose
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
			if instance:IsA("TextLabel") or instance:IsA("TextButton") then
				instance.TextWrapped = string.find(tostring(value), "%s") ~= nil
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
				-- a RUNG-2 map may declare `selected` art; nothing else repaints an
				-- untagged decoration
				applyOverrideVariantArt(handle)
				if nativeMode then
					-- native (NSS-A5): the tag flip IS the state change — the
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
			-- the expander must stay exactly one BEHIND its control (RS-A16-D1b:
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
	-- cheaper**, and `LuauUI/mount` — the structural pass — was measured at
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
	--     ride into a new identity.
	local function parkEligible(handle: any): boolean
		if handle == nil or handle.instance == nil then
			return false
		end
		local path = handle.path
		if
			handle.motionScale ~= nil
			or handle.canvasGroupInstance ~= nil
			or handle.hitExpander ~= nil
			or handle.focusRingFloat ~= nil
			or handle.focusGlow ~= nil
			or focusedHandles[handle] ~= nil
			or clipHosts[path] ~= nil
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
	local PARKED_PATH = "\0LuauUIParked"

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
		if activeCapture ~= nil and activeCapture.handle == handle then
			return false
		end
		local path = handle.path
		-- RELEASE CLIP-HOST MEMBERSHIP. The host keeps an array of its children and
		-- re-bases their window rects against itself; a parked node left in that
		-- array is a corpse the host goes on re-placing every solve.
		local host = handle.clipHost
		if host ~= nil then
			for i, child in host.children do
				if child == handle then
					table.remove(host.children, i)
					break
				end
			end
			handle.clipHost = nil
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
		subtreeCache = {}
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

	-- ADOPT: give a parked node a new identity. Every property the new node
	-- declares is written by the renderer immediately afterwards (its per-path
	-- caches were dropped when the old path died), so only IDENTITY is restored
	-- here — the paint state is the renderer's job either way.
	function adapter.adopt(handle: any, newPath: string, newClass: string, hint: any): boolean
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
		handle.parked = nil
		handle.parkedChromeEpoch = nil
		handle.path = newPath
		handle.instance.Name = newPath
		local host = hostFor(newPath)
		if host ~= nil then
			handle.clipHost = host
			table.insert(host.children, handle)
			handle.instance.Parent = host.instance
		else
			handle.instance.Parent = lastRootHandle.gui
		end
		instancesByPath[newPath] = handle.instance
		handlesByPath[newPath] = handle
		-- re-key the chrome children under the new identity — the SAME enumeration
		-- `park` released, so the two seams cannot drift apart
		for name, child in chromePathChildEntries(handle) do
			instancesByPath[newPath .. "/" .. name] = child
		end
		subtreeCache = {}
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
		if activeCapture ~= nil and activeCapture.handle == handle then
			-- never leave a global capture pointing at a dead node — unless
			-- the drag itself removed it (lift) and asks to keep the capture
			endCapture("removed")
		end
		instancesByPath[handle.path] = nil
		instancesByPath[handle.path .. "/" .. chrome_slots.DECORATION_NAME] = nil
		-- the PRESENTATION record dies with the node, or a re-created path inherits a
		-- transform nothing is driving any more (and `presentationCount` — the
		-- zero-cost fast path every rect write consults — would never fall back to 0)
		if presentationTransforms[handle.path] ~= nil then
			presentationTransforms[handle.path] = nil
			presentationCount -= 1
		end
		-- ...and so does its REAL-PARENT record. A stale entry keeps re-parenting new
		-- nodes into a destroyed instance, which is the one way a flat tree can lose a
		-- whole subtree silently.
		clipHosts[handle.path] = nil
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
		subtreeCache = {}
		-- the LIFTED LABEL is decoration too: without this its connections stayed
		-- live, `census.textLifts` only ever grew across remounts, and
		-- `instancesByPath[path .. "/LuauUIChromeText"]` retained a destroyed
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
		if handle.hitExpander ~= nil then
			handle.hitExpander:Destroy()
			handle.hitExpander = nil
		end
		handle.instance:Destroy()
	end

	function adapter.destroyRoot(rootHandle: any)
		-- whole-root teardown mid-drag: cancel the capture (its global UIS
		-- connections outlive the gui otherwise) and release any cursor hint
		endCapture("destroyed")
		menuConn:Disconnect()
		hoverHint = nil
		applyCursor()
		for path, node in instancesByPath do
			if node:IsDescendantOf(rootHandle.gui) then
				instancesByPath[path] = nil
				-- the same two per-node records `remove` drops, on the whole-root path:
				-- a target hosts several roots at once, so this cannot be a blanket reset
				if presentationTransforms[path] ~= nil then
					presentationTransforms[path] = nil
					presentationCount -= 1
				end
				clipHosts[path] = nil
				local handle = handlesByPath[path]
				if handle ~= nil then
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
				subtreeCache = {}
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
