--!strict
-- Native-sheet MODEL builder (native-stylesheets stage; plan §6.1/§6.2, ledger
-- NSS-A1). PURE and engine-free: compiles LuauUI token styles into a
-- declarative StyleSheet model — token names, theme token sets, ordered rules,
-- transitions, and layout-reference mirrors — that the client materializer
-- (src/client/native_style.luau) turns into DataModel instances. Everything a
-- headless test needs to assert (names, values, order, contrast, coverage)
-- lives here; nothing here touches an Instance.
--
-- Engine truths this encodes (docs/research/2026-07-24-native-stylesheet-spike.md):
--   * cascade = Priority first, then INSERTION ORDER (later wins); selector
--     specificity does not participate — so rules[] order is load-bearing:
--     base -> surfaces -> selected -> hover -> pressed -> disabled;
--   * ::UICorner/::UIStroke rules CREATE phantom modifiers — the adapter must
--     NOT materialize those instances in native mode (a real child defeats
--     the phantom);
--   * theme tokens live ONLY in theme sheets (a base-sheet attribute would
--     defeat every derive); the base sheet holds rules + read-only mirrors;
--   * hover rules are compound-gated on the pointer-live tag so a touch
--     paradigm can never match them (:Hover alone has no paradigm gate);
--   * :NonInteractable keys on GuiObject.Interactable=false.

local tokens = require("./tokens")
local chrome_props = require("./chrome_props")
local chrome_slots = require("./chrome_slots")
-- the pure style-modifier layer: `tint`'s value vocabulary and its hex escape
-- live there (it is dependency-light and the public schema validates against it),
-- and this module resolves those roles against a theme's palette
local styling = require("./styling")
local themePackage = require("../themes/package")

local sheet_model = {}

-- The classification vocabulary shared with the adapter (Phase 2): tags are
-- the ONLY channel by which LuauUI states/roles reach native selectors.
sheet_model.TAGS = table.freeze({
	surfacePrefix = "luau-surface-", -- + base|raised|control|chip|badge|accent|scrim
	selected = "luau-selected",
	interactive = "luau-interactive",
	pointerLive = "luau-pointer-live",
	-- THE SHAPE TAG (feature round 2026-07-26). A SURFACE says what a node is
	-- made of; a SHAPE says what silhouette it is cut to, and the two are
	-- independent — a circle button is still a `control` surface and still takes
	-- every role, state and skin a rectangle does. So the disc's chrome is its
	-- own tag with its own phantom ::UICorner/::UIStroke rules rather than a
	-- seventh surface, which is what keeps `shape` from having to re-declare a
	-- fill, a label colour and a hover treatment it does not change.
	shapePrefix = "luau-shape-", -- + circle (the only non-default shape)
	-- THE TYPOGRAPHY ROLE TAG (F2, 2026-08-02). `FontFace` is sheet-owned in
	-- native mode, so a node's typography role — which carries the FACE as well as
	-- the size — cannot reach paint as an explicit write. It reaches it as this
	-- tag, one generated rule per role, each carrying the descriptor the solver
	-- measured with. Distinct from `luau-role-strong`, which is the CONTENT-COLOUR
	-- emphasis a heading-scale size earns: one names a face, the other a colour.
	typePrefix = "luau-type-", -- + caption|label|body|heading|title|control|strong|numeral
	--[[ THE TINTED FILL (director report 2026-08-15, `canvas-group`).

		A `tint` claims `BackgroundColor3` — a colour is per-node DATA and no rule
		can carry it — but it cannot claim the FILL beside it. The tint's default
		alpha is 0, which is exactly `Frame.BackgroundTransparency`'s class default,
		and the engine decides "explicit" BY VALUE: a write equal to the default
		never marks the property explicit, so the `Frame default` rule kept
		ownership and every tinted Box with no `surface` painted nothing at all.
		Measured on the live plate 2026-08-15 — raw 0 / GetStyled 1; write 0.001 ->
		GetStyled 0.001; write 0 again -> GetStyled 1
		(docs/lessons/a-default-valued-write-never-claims.md).

		So "this node has a tinted fill" reaches paint as a TAG, which is what
		`gripFocus` below already does for the identical reason. It is emitted in
		the `base` group so a surface, a value slot and a scrim all still out-rank
		it: this is the floor under an otherwise invisible node, never a new
		authority over one that was already painted. ]]
	tintFill = "luau-tint-fill",
})

--[[ THE BACKDROP RULE, named once (ADR-0035). Both sheet builders emit it and the
	adapter patches it live when the player moves their Background Transparency
	preference, so the string is a constant rather than three literals. ]]
sheet_model.SCRIM_RULE = "Scrim backdrop"

--[[ THE PLAYER'S BACKGROUND-TRANSPARENCY PREFERENCE, composed with a theme's own
	backdrop dim (ADR-0035, owed row O-26).

	`GuiService.PreferredTransparency` is a 0..1 scalar the player moves in
	Settings; 1 is "paint what the designer said" and 0 is "I want opaque
	backgrounds". Roblox's own reference page states the recipe — *"Multiplying a
	UI element's BackgroundTransparency with PreferredTransparency is the
	recommended approach, such that backgrounds become more opaque as
	PreferredTransparency approaches 0"* — and a multiply is also the only
	composition that preserves a theme's RELATIVE intent: a package that dims at
	0.62 stays darker than one that dims at 0.35 at every setting.

	ONE FUNCTION, TWO WRITERS. The native sheet patches the `Scrim backdrop` rule
	through this; the bespoke painter writes its scrim fill through this. Same
	shape as `chrome_slots.DISABLED_CONTENT_OPACITY` and for the same reason — two
	paint vocabularies that agree today drift apart the moment either is edited
	alone.

	IDENTITY ON GARBAGE. The env memo already clamps, but this is also called from
	the adapter with a value that crossed a seam, and a NaN written into
	`BackgroundTransparency` is a backdrop nobody can see. An unusable preference
	means "leave the theme's value alone", never "guess". ]]
function sheet_model.backdropTransparency(base: number, preference: number): number
	if type(preference) ~= "number" or preference ~= preference then
		return base
	end
	return math.clamp(base * math.clamp(preference, 0, 1), 0, 1)
end

--[[ WHICH RULE PROPS THE PLAYER'S PREFERENCE IS ALLOWED TO MOVE — the same shape
	`metricRuleProps` already uses, for the same reason: the value is baked into a
	rule as a LITERAL (a preference is not a `$Token` any sheet can derive), so a
	mid-session change has to reach the installed rule through the generator's own
	`setRuleProperty`.

	IT IS A LIST WITH ONE ENTRY, AND THE LIST IS THE POINT. The audit that
	commissioned ADR-0035 walked every rule both builders emit and found exactly one
	`BackgroundTransparency` strictly between 0 and 1 — every other framework
	background is already opaque (a surface) or already invisible (a class default),
	and multiplying either is respectively a no-op or a defect that REVEALS hidden
	plates. `tests/preferred_transparency.spec.luau` re-derives that set from a
	built sheet and asserts it equals this declaration, so a second translucent
	background cannot appear on either side without a decision.

	NO BASE HERE, DELIBERATELY. The number the preference composes against is the
	AUTHORED value of the sheet that is actually linked, which after a theme swap is
	a different designer's number than any model this constant could carry. The
	adapter reads it off the live rule once per sheet, before it has written to it
	(screen_target.applyBackdropPreference). ]]
sheet_model.PREFERENCE_RULE_PROPS = table.freeze({
	table.freeze({ rule = sheet_model.SCRIM_RULE, prop = "BackgroundTransparency" }),
})

-- A theme token is a colour in the Step 2 vocabulary. `buildPackage` also emits
-- number and sequence tokens (gradient ramps, gradient rotation) — every one of
-- them a type Roblox accepts as a StyleSheet ATTRIBUTE, which is what makes it
-- theme-swappable at all.
export type TokenValue = any -- { kind = "color"|"number"|"colorseq"|"numseq", ... }
export type Theme = { name: string, tokens: { [string]: TokenValue }, contrast: any }
export type RuleProp = any -- "$Token" | { kind = "color"|"udim"|"number"|"font"|"enum"|"rect"|"colorseq"|"numseq", ... }
export type Rule = {
	name: string,
	selector: string,
	props: { [string]: RuleProp },
	-- propName -> motion token name ("fast" | "normal"); materialized as
	-- SetPropertyTransitions(TweenInfo(motion[token])) when transitions are on
	transitions: { [string]: string }?,
	-- buildPackage only: the explicit cascade position (index * 10) and the
	-- ordered group it belongs to. `build` leaves both nil and the materializer
	-- derives the same priority from the index — identical numbers, so an
	-- existing sheet is unaffected.
	priority: number?,
	group: string?,
}
export type Model = {
	schema: string,
	stamp: string,
	defaultTheme: string,
	themes: { Theme },
	rules: { Rule },
	mirrors: { { name: string, value: number } },
	motion: { fast: number, normal: number },
	-- buildPackage only: rule props baked from metrics (corner radii, stroke
	-- thickness) so a live metric edit can repaint them (ADR-0019 §3)
	metricRuleProps: { { path: string, rule: string, prop: string, form: string } }?,
	-- buildPackage only: what this package's skin COSTS, counted at compile
	-- (ADR-0020 process rulings; ledger RS-A17). Zero in every field for a flat
	-- package, which is what makes "flat pays nothing" a measurement.
	census: ModelCensus?,
}

export type ModelCensus = {
	-- rules carrying an `Image`, and how many of those carry the Pixelated
	-- stamp. For a pixel package the two are EQUAL, which is the assertable
	-- form of "every image-bearing rule is nearest-neighbour" (rs-m5).
	imageRules: number,
	pixelatedRules: number,
	-- generated native-paint suppression rules (three per skinned slot)
	suppressionRules: number,
	-- per-state art rules and the distinct non-default assets they name
	variantRules: number,
	variantAssets: number,
	-- layer paint rules, layer instances per decorated node, and the per-KIND
	-- breakdown that is the bench guard against an unbounded stack
	layerRules: number,
	layers: number,
	layersPerKind: { [string]: number },
	layeredSlots: { string },
	-- what a stack paints OUTSIDE its solved rect, per slot (rs-m3): a
	-- compile-visible fact for any ancestor that clips
	overhang: { [string]: { top: number, right: number, bottom: number, left: number } },
}

-- classifyTags: the PURE hint->tag mapping the native adapter applies with
-- CollectionService (Phase 2, ledger NSS-A2/NSS-A5). Headlessly tested so the
-- classification decisions never depend on an engine. `plain` and `scrim`
-- surfaces suppress interaction chrome exactly like the bespoke path
-- (suppressStates); `plain` carries no surface tag at all (chrome-less).
export type ClassifyInput = {
	surface: string?, -- base|raised|control|chip|badge|accent|scrim|plain
	selected: boolean?,
	roleSecondary: boolean?,
	strong: boolean?, -- textSize >= heading (bespoke: contentStrong upgrade)
	interactive: boolean?, -- Button/Toggle state chrome (false for scrim/plain)
	pointerLive: boolean?, -- renderer's pointer-class-live decision (hover gate)
	-- focused Grip accent fill (arch verifier 2026-07-24: the bespoke explicit
	-- write would permanently defeat the Frame-default rule in native mode, so
	-- the affordance rides a tag rule instead — theme-aware for free)
	gripFocus: boolean?,
	-- this node carries a `tint` whose colour landed on its BACKGROUND (a Box, a
	-- ZStack, a fade group — never a Text/Image/Path, whose tint claims a colour
	-- the class default already paints). Drives `luau-tint-fill`: see TAGS above
	-- for why the fill cannot be an explicit write.
	tinted: boolean?,
	-- the decoration slot this node is CURRENTLY skinned with (nil = not
	-- skinned). Drives `luau-skinned-<slot>`, which the package's suppression
	-- rules key on so the native plate stops drawing under the art.
	skinnedSlot: string?,
	-- the slot this node DECLARED through the internal decoration hint, skinned
	-- or not. Drives `luau-slot-<slot>`, which is what gives a value control's
	-- chrome its own native paint instead of borrowing a public surface's.
	slotHint: string?,
	-- the sixth variant state (ADR-0020 R2). `default/hover/pressed/selected/
	-- disabled` all ride an engine GuiState or a tag the renderer already emits;
	-- `error` has no engine state, so a control that has one publishes it here.
	errorState: boolean?,
	-- ONE PARENT TAG HIDES THE WHOLE STACK (ADR-0020 R1, probe rs-m2). The
	-- single-decoration editing yield tags the DECORATION, which syncTags never
	-- touches; a layered node's yield has to ride the DECORATED NODE, and every
	-- `luau-*` tag on that node is diffed against this desired set. A yield tag
	-- added anywhere else would survive exactly until the next classification
	-- pass — the Step 3.5 fix round's defect class, one slot down.
	chromeYield: boolean?,
	-- A SWITCH'S VALUE (ADR-0020 R3 cap 10). `on` is neither an engine GuiState
	-- nor a selection binding — it is the control's value, and a rule cannot see
	-- a value — so the package's toggle art keys on this tag, flipped from the
	-- same fact `togglePalette` paints its colours from.
	toggleOn: boolean?,
	-- SEMANTIC ICON ART REPLACED THIS NODE'S GLYPH (ADR-0020 R4). A control that
	-- requests an icon draws the framework's ASCII glyph itself, so the node
	-- always has legible text; when the installed package declares real art the
	-- adapter parents a picture over it and this tag turns the glyph off. It is a
	-- tag rather than an explicit write because TextTransparency is sheet-owned
	-- in native mode, so a bespoke write would be defeated by the next rule pass.
	iconArt: boolean?,
	-- the node a live drag session is carrying (registry-driven): its label
	-- empties until the drop lands or the return flight arrives
	dragHeld: boolean?,
	-- THE SILHOUETTE (feature round 2026-07-26): "rect" (or nil) is the default
	-- every Button already had; "circle" earns `luau-shape-circle`, which the
	-- disc's phantom corner and hairline rules key on.
	shape: string?,
	-- THE TYPOGRAPHY ROLE this text node resolved to (F2, 2026-08-02): the name,
	-- not the descriptor — the FACE lives in the generated rule, so measurement and
	-- paint read the one ramp. nil for a node that draws no text.
	typeRole: string?,
}

function sheet_model.classifyTags(input: ClassifyInput): { [string]: boolean }
	local T = sheet_model.TAGS
	local tags: { [string]: boolean } = {}
	local surface = input.surface
	local suppressed = surface == "plain" or surface == "scrim"
	if surface ~= nil and surface ~= "plain" then
		tags[T.surfacePrefix .. surface] = true
	end
	if input.interactive == true and not suppressed then
		tags[T.interactive] = true
		if input.pointerLive == true then
			tags[T.pointerLive] = true
		end
	end
	if input.selected == true and not suppressed then
		tags[T.selected] = true
	end
	if input.roleSecondary == true then
		tags["luau-role-secondary"] = true
	end
	if input.strong == true then
		tags["luau-role-strong"] = true
	end
	if input.gripFocus == true then
		tags["luau-grip-focus"] = true
	end
	-- the tinted fill (see TAGS): the colour is a claim, the fill is a tag, because
	-- an explicit write of the class default never takes the property
	if input.tinted == true then
		tags[T.tintFill] = true
	end
	-- the ERROR state's tag (ADR-0020 R2). Emitted only when a control says so,
	-- so nothing a package published before this stage renders can carry it.
	if input.errorState == true then
		tags[chrome_slots.TAGS.stateError] = true
	end
	-- the layered editing yield (see chromeYield above): one tag, and the
	-- child-combinator rules blank the whole ladder
	if input.chromeYield == true then
		tags[chrome_slots.TAGS.stackYield] = true
	end
	-- the switch's ON state (see toggleOn above). Deliberately NOT `luau-selected`:
	-- that tag carries the row-selection treatment (`TextButton.luau-selected`
	-- repaints the whole button), and a toggle being on is not a row being chosen.
	if input.toggleOn == true then
		tags[chrome_slots.TOGGLE_ON_TAG] = true
	end
	-- the icon-art glyph suppression (see iconArt above). Rides the desired set
	-- for the same reason every other v2 tag does: a tag added outside it lives
	-- exactly until the next classification pass.
	if input.iconArt == true then
		tags[chrome_slots.TAGS.iconArt] = true
	end
	if input.dragHeld == true then
		tags[chrome_slots.TAGS.dragHeld] = true
	end
	-- THE SHAPE (feature round 2026-07-26). "rect" adds no tag for exactly the
	-- reason the "default" button role adds none: the class default already
	-- describes it, and an extra tag would be a rule with nothing to say. It
	-- rides the desired set like every other classification tag, so a later pass
	-- cannot strip a disc back to a rectangle.
	if input.shape ~= nil and input.shape ~= "rect" then
		tags[T.shapePrefix .. input.shape] = true
	end
	-- THE TYPOGRAPHY ROLE (F2). Emitted for every role a text node resolves to,
	-- including the class defaults: a rule that restates the class default is inert
	-- under a package whose ramp shares one face (Studio Neutral, every existing
	-- screen) and load-bearing the moment a package gives one role its own.
	if type(input.typeRole) == "string" and input.typeRole ~= "" then
		tags[T.typePrefix .. input.typeRole] = true
	end
	-- Divider (A-LV3): the hairline is sheet-painted, so a designer can restyle
	-- every separator in one rule. Never a bespoke fill in native mode.
	if input.divider == true then
		tags["luau-divider"] = true
	end
	-- semantic button role (B-BTN2). "default" adds no tag: the class default
	-- already describes it, and an extra tag would be a rule with nothing to say.
	if input.buttonRole == "destructive" then
		tags["luau-role-destructive"] = true
	elseif input.buttonRole == "cancel" then
		tags["luau-role-cancel"] = true
	end
	-- THE IMAGE IS THE BUTTON: the node carries its skinned-slot tag so the
	-- package's suppression rules can turn off the plate, the corner and the
	-- hairline it now sits under. Kept in the SAME desired-set the adapter
	-- diffs against, or the next classification pass would strip it.
	if type(input.skinnedSlot) == "string" then
		tags[chrome_slots.skinnedTagFor(input.skinnedSlot :: string)] = true
	end
	-- THE SLOT IDENTITY TAG. Emitted for the value-control family only: those
	-- slots are reached solely through the hint, so nothing else paints them.
	-- A node that reaches a slot through a public surface (a badge, a raised
	-- panel) already has that surface's rules and must not get a second set.
	if chrome_slots.hasOwnPaint(input.slotHint) then
		tags[chrome_slots.slotTagFor(input.slotHint :: string)] = true
	end
	return tags
end

local function color(c: any): TokenValue
	return { kind = "color", r = c.r, g = c.g, b = c.b }
end

-- The destructive role's palette (B-BTN2) was added after games already shipped
-- custom styles, so a style that predates it must keep working. These are the
-- library defaults, used only when the style omits the pair; the contrast gate
-- then runs on the EFFECTIVE pair, so a custom style can never end up with an
-- ungated destructive colour.
-- single source moved to tokens.dangerPair (2026-07-25): the theme-package
-- compiler gates the same pair at define time, and requiring sheet_model from
-- there is a cycle (sheet_model already requires ../themes/package)
local dangerPair = tokens.dangerPair
sheet_model.dangerPair = dangerPair

local function lerp(a: any, b: { r: number, g: number, b: number }, t: number): TokenValue
	return {
		kind = "color",
		r = a.r + (b.r - a.r) * t,
		g = a.g + (b.g - a.g) * t,
		b = a.b + (b.b - a.b) * t,
	}
end

local WHITE = { r = 1, g = 1, b = 1 }
local BLACK = { r = 0, g = 0, b = 0 }

-- THE PHANTOM STROKE'S MODE (director round 10, found live 2026-07-26).
--
-- `UIStroke.ApplyStrokeMode` defaults to **Contextual**, and on a TextButton or
-- TextLabel that means the stroke is drawn around the GLYPHS, not around the
-- border. Every stroke this compiler emits is a border hairline, so every one of
-- them has to say so: the bespoke path always did (`hairline()` in
-- screen_target writes `ApplyStrokeMode.Border` explicitly), the rule-owned path
-- inherited the engine default, and the two diverged silently.
--
-- What it looked like: under classic-desktop the picker's chip outline never
-- drew at all and every chip LABEL grew a hairline-coloured halo — measured at
-- the shipped stamp as a 3.35x larger mid-tone (halo) pixel fraction and 17%
-- softer glyph edges than the same frame with Border. Under Studio Neutral the
-- hairline is white and the label is white, so it hid for two whole stages.
local STROKE_BORDER: RuleProp = { kind = "enum", enum = "ApplyStrokeMode", item = "Border" }
sheet_model.STROKE_BORDER = STROKE_BORDER

-- THE SELECTED STATE'S CONTENT COLOUR (director round 8, ADR-0019 palette
-- contract; the 3.5 `togglePalette` ruling is the precedent).
--
-- A theme guarantees exactly two readable pairs: surface/content and
-- accent/onAccent, both gated at 4.5:1 by `gateTheme`. The SELECTED state is a
-- third surface — `extra.controlSelected`, the colour the framework's own
-- `Selected row` rule paints and the colour a package's selected ART is
-- declaring itself to be — and nothing ever paired a content colour with it. So
-- a selected label kept `$Content` whatever the plate underneath became:
-- measured live under glossy-touch at 3.74:1 on its blue gel, which is what the
-- director could not read.
--
-- THE MAPPING, and why each half is what it is:
--
--   content   the status quo, and the answer wherever it still clears the
--             contract's own 4.5 floor against the selected surface — which is
--             every reference theme except pixel-quest. Preferring it (rather
--             than taking whichever scores HIGHER) is what keeps Studio Neutral
--             and every flat package byte-identical: neutral's selected surface
--             reads content at 9.74:1 and onAccent at 11.22:1, and switching it
--             would have been a visible change with no defect behind it.
--   onAccent  the GUARANTEED partner, taken only when content fails. It is the
--             one colour a theme promises is readable against its accent, and a
--             selected surface is an accent-washed control by construction
--             (`effectiveExtra` derives it as control lerped 35% toward accent).
--             Measured on pixel-quest's gold plate: content 1.75:1, onAccent
--             8.47:1.
--
-- A theme whose selected surface can carry NEITHER is a palette defect, not a
-- resolver case: `gateSelectedPair` below refuses it at define time, exactly as
-- `gateTheme` refuses an unreadable accent pair.
--
-- Pure, exported, and read by ONE token (`$OnSelected`) so the skinned lift and
-- the unskinned row resolve the same decision.
local SELECTED_CONTRAST_FLOOR = 4.5

local function selectedSurfaceOf(theme: any): { r: number, g: number, b: number }
	local c = theme.colors
	local x = theme.extra or {}
	if type(x.controlSelected) == "table" then
		return x.controlSelected
	end
	local control = if type(x.control) == "table" then x.control else c.surfaceStrong
	return lerp(control, c.accent, 0.35) :: any
end
sheet_model.selectedSurfaceOf = selectedSurfaceOf

function sheet_model.selectedContentColor(theme: any): { r: number, g: number, b: number }
	local c = theme.colors
	local surface = selectedSurfaceOf(theme)
	if tokens.contrastRatio(c.content, surface) >= SELECTED_CONTRAST_FLOOR then
		return { r = c.content.r, g = c.content.g, b = c.content.b }
	end
	return { r = c.onAccent.r, g = c.onAccent.g, b = c.onAccent.b }
end

-- the gate the resolver leans on: SOME content role must be readable on the
-- selected surface, or the theme has published a state nobody can read
function sheet_model.selectedPairReport(theme: any): any
	local c = theme.colors
	local surface = selectedSurfaceOf(theme)
	local content = tokens.contrastRatio(c.content, surface)
	local onAccent = tokens.contrastRatio(c.onAccent, surface)
	return {
		surface = surface,
		content = math.floor(content * 100) / 100,
		onAccent = math.floor(onAccent * 100) / 100,
		picked = if content >= SELECTED_CONTRAST_FLOOR then "content" else "onAccent",
		ok = math.max(content, onAccent) >= SELECTED_CONTRAST_FLOOR,
		floor = SELECTED_CONTRAST_FLOOR,
	}
end

-- theme token set from a compiled LuauUI style (plan §6.1 naming: schema keys
-- PascalCased so the Style Editor shows words designers know from the docs)
local function themeTokens(style: any): { [string]: TokenValue }
	local c, x = style.colors, style.extra
	return {
		Danger = color((select(1, dangerPair(c)))),
		OnDanger = color((select(2, dangerPair(c)))),
		-- role interaction tokens, precomputed with the same edge lerp the control
		-- tokens use so a destructive button's states read as the same family
		DangerHover = lerp((select(1, dangerPair(c))), { r = 1, g = 1, b = 1 }, 0.12),
		DangerPressed = lerp((select(1, dangerPair(c))), { r = 0, g = 0, b = 0 }, 0.12),
		Surface = color(c.surface),
		SurfaceStrong = color(c.surfaceStrong),
		Content = color(c.content),
		ContentStrong = color(c.contentStrong),
		Accent = color(c.accent),
		OnAccent = color(c.onAccent),
		-- the SELECTED state's readable partner (director round 8). Derived, per
		-- theme, from the theme's own selected surface — never a hardcode, and
		-- never a second palette role an author has to remember to declare.
		OnSelected = color(sheet_model.selectedContentColor(style)),
		Control = color(x.control),
		ControlHover = color(x.controlHover),
		ControlPressed = color(x.controlPressed),
		ControlSelected = color(x.controlSelected),
		ContentSecondary = color(x.contentSecondary),
		Hairline = color(x.hairline),
		-- precomputed accent interaction states (bespoke path computes these
		-- with Color3:Lerp at the edge; the sheet needs them as real tokens)
		AccentHover = lerp(c.accent, WHITE, 0.12),
		AccentPressed = lerp(c.accent, BLACK, 0.18),
	}
end

-- every theme's palette re-passes the library contrast gate before it may be
-- selected (§6.7): surface/content, surfaceStrong/contentStrong, accent/onAccent
local function gateTheme(name: string, style: any)
	local report = { ok = true, pairs = {} }
	for _, pair in
		{
			{ "surface", "content" },
			{ "surfaceStrong", "contentStrong" },
			{ "accent", "onAccent" },
			{ "danger", "onDanger" },
		}
	do
		local a, b = style.colors[pair[1]], style.colors[pair[2]]
		if pair[1] == "danger" then
			a, b = dangerPair(style.colors)
		end
		local ratio = tokens.contrastRatio(a, b)
		local ok = ratio >= 4.5
		if not ok then
			report.ok = false
		end
		table.insert(report.pairs, { pair = `{pair[2]} on {pair[1]}`, ratio = math.floor(ratio * 100) / 100, ok = ok })
	end
	assert(report.ok, `sheet_model: theme '{name}' fails the contrast gate`)
	return report
end

local BUILDER_SANS: RuleProp = { kind = "font", family = "rbxasset://fonts/families/BuilderSans.json" }
-- the two WEIGHT-ROLE faces of the same family (F2, 2026-08-02). SemiBold for
-- `strong` and Bold for `numeral`, which is exactly what
-- `themes.package.deriveTypeRole` derives — stated in both places because the
-- token-style path has no font descriptors to derive FROM, and asserted equal by
-- a spec so the two can never drift.
local BUILDER_SANS_SEMIBOLD: RuleProp =
	{ kind = "font", family = "rbxasset://fonts/families/BuilderSans.json", weight = "SemiBold", style = "Normal" }
local BUILDER_SANS_BOLD: RuleProp =
	{ kind = "font", family = "rbxasset://fonts/families/BuilderSans.json", weight = "Bold", style = "Normal" }
local function udim(scale: number, offset: number): RuleProp
	return { kind = "udim", scale = scale, offset = offset }
end
local function num(v: number): RuleProp
	return { kind = "number", value = v }
end

-- THE class-default naming vocabulary. The engine class is not the name a
-- designer reads: `Label default` and `Field default` are what the styling
-- guide, the Style Editor and every saved edit already call these rules, and
-- `build` established that vocabulary. `buildPackage` applies this map so it
-- cannot drift from it; `sheet_model.spec` asserts the two name sets agree.
local CLASS_DEFAULT_NAME: { [string]: string } = {
	Frame = "Frame",
	TextLabel = "Label",
	TextButton = "Button",
	ImageLabel = "Image",
	TextBox = "Field",
	ScrollingFrame = "Scroll",
	-- the mask wrapper a `mask`ed layer is built in (R1, probe rs-m9). It is a
	-- SILHOUETTE, and a silhouette that paints its own background would put a
	-- solid pill behind the very art it is shaping — found live at stamp
	-- 62b6cdeb-1689276, where the fresh CanvasGroup sat at BackgroundTransparency
	-- 0 because no class rule reached it. Owned by a RULE, not an adapter write,
	-- for the same reason every other class default is (spike m10).
	CanvasGroup = "Canvas",
}
sheet_model.CLASS_DEFAULT_NAME = CLASS_DEFAULT_NAME

-- deterministic FNV-1a over the serialized model content (no clock, resumable)
local function stampOf(parts: { string }): string
	local hash = 2166136261
	for _, s in parts do
		for i = 1, #s do
			hash = bit32.bxor(hash, string.byte(s, i))
			hash = bit32.band(hash * 16777619, 0xFFFFFFFF)
		end
	end
	return string.format("%08x", hash)
end

-- ===========================================================================
-- THE VALUE-CONTROL OWN-PAINT FAMILY — ONE EMITTER, BOTH BUILDERS
-- (RS-A16-D4, found live 2026-07-26)
-- ===========================================================================
--
-- These four surfaces (`chrome_slots.OWN_PAINT_SLOTS`: a slider's rail and
-- thumb, a progress bar's track and fill) are reached ONLY through the internal
-- decoration hint, never through a public `surface` — so nothing else paints
-- them and the sheet has to. `Frame default` sets BackgroundTransparency = 1,
-- which means "no rule" does not read as "unstyled": it reads as INVISIBLE.
--
-- WHY THIS IS A SHARED FUNCTION AND NOT A LOOP INSIDE ONE BUILDER. It used to
-- be a loop inside `buildPackage`, whose own comment said "emitted for every
-- package including the flat ones — a value control has to be visible under
-- Studio Neutral too". Studio Neutral was the one path it was not emitted on:
-- with no package installed the live sheet is `build`'s base seed, which emitted
-- none of the family, so the default Download bar painted nothing at all
-- (pixel-identical at 0% and 100%) and the default Brightness slider had no rail
-- and no thumb. Two builders, one requirement, one emitter — a second copy is
-- how this defect class breeds.
--
-- The token map is the same `SLOT_FILL_TOKEN` the asset-failure fallback and the
-- bespoke path (`src/client/screen_chrome.luau`'s `chromeFillOf`) read, so a
-- slot's flat appearance is ONE decision on all three paths.

-- what a slot's declared NATIVE fallback paints when its asset fails to load,
-- and what the own-paint family paints when nothing skins it at all
local SLOT_FILL_TOKEN: { [string]: string } = {
	panel = "$SurfaceStrong",
	control = "$Control",
	field = "$Control",
	selection = "$ControlSelected",
	divider = "$Hairline",
	scrollbar = "$Control",
	sliderTrack = "$Control",
	sliderThumb = "$SurfaceStrong",
	badge = "$SurfaceStrong",
	-- v2 value displays (ADR-0020 R3). The track is a control surface and the
	-- fill is the accent, which is what a flat progress bar already looks like;
	-- the caps and the centrepiece are ornaments with no unskinned counterpart,
	-- so their fallback is the accent they decorate rather than a shape of their
	-- own. A toggle's flat truth stays `togglePalette`; these tokens only paint
	-- if its ART fails to load.
	barTrack = "$Control",
	barFill = "$Accent",
	barCap = "$Accent",
	barCenter = "$Accent",
	stepperPlate = "$Control",
	toggleTrack = "$Control",
	toggleKnob = "$SurfaceStrong",
	-- the indeterminate spinner's dot (parity round 2 §3.1): an unskinned
	-- spinner is a ring of accent dots, the same flat truth `barFill` carries
	spinner = "$Accent",
}
-- slots whose fallback shape is a CIRCLE (a thumb, a counter seal, a switch
-- knob): a square fallback under round art reads as a different control, not as
-- a degraded one
local SLOT_ROUND: { [string]: boolean } = { sliderThumb = true, badge = true, toggleKnob = true, spinner = true }

local function slotRadius(metrics: any, slot: string): number
	if slot == "panel" then
		return metrics.radii.panel
	elseif slot == "divider" or slot == "scrollbar" then
		return 0
	end
	return metrics.radii.control
end

-- emitOwnSlotPaint: the three rules that make ONE value slot visible without
-- art — fill, phantom ::UICorner radius, phantom ::UIStroke hairline — keyed on
-- the slot IDENTITY tag (`luau-slot-<slot>`), which the renderer applies whether
-- or not a package skins the node.
--
-- `emit` takes the rule (the caller decides which ordered group it lands in);
-- `fromMetric` is optional because only the package builder can push a live
-- metric edit onto a baked literal.
local function emitOwnSlotPaint(
	slot: string,
	metrics: any,
	hairlineT: RuleProp,
	hairlineW: RuleProp,
	emit: (Rule) -> (),
	fromMetric: ((string, string, string, string) -> ())?
)
	local tag = chrome_slots.slotTagFor(slot)
	emit({
		name = `Slot — {slot}`,
		selector = `.{tag}`,
		props = { BackgroundColor3 = SLOT_FILL_TOKEN[slot], BackgroundTransparency = num(0) },
	})
	emit({
		name = `Slot — {slot} corner`,
		selector = `.{tag}::UICorner`,
		props = {
			CornerRadius = if SLOT_ROUND[slot] then udim(0.5, 0) else udim(0, slotRadius(metrics, slot)),
		},
	})
	if fromMetric ~= nil and not SLOT_ROUND[slot] then
		fromMetric("radii.control", `Slot — {slot} corner`, "CornerRadius", "udimOffset")
	end
	-- the hairline uses the package's OWN stroke vocabulary, so a theme that
	-- thickened its hairlines gets a thumb that matches its buttons
	emit({
		name = `Slot — {slot} outline`,
		selector = `.{tag}::UIStroke`,
		props = {
			Color = "$Hairline",
			Transparency = hairlineT,
			Thickness = hairlineW,
			ApplyStrokeMode = STROKE_BORDER,
		},
	})
	if fromMetric ~= nil then
		fromMetric("strokes.hairline", `Slot — {slot} outline`, "Thickness", "number")
	end
end

-- emitSlotSuppression: the mirror image — the three rules that STOP the native
-- plate being drawn once art covers the node (`luau-skinned-<slot>`). Shared for
-- the same reason the paint is: the pre-arm the base seed needs and the per-slot
-- suppression a package's recipes need are the same three rules.
local function emitSlotSuppression(slot: string, emit: (Rule) -> ())
	local skinnedTag = chrome_slots.skinnedTagFor(slot)
	emit({
		name = `Skinned — {slot}`,
		selector = `.{skinnedTag}`,
		props = { BackgroundTransparency = num(1) },
	})
	emit({
		name = `Skinned — {slot} corner`,
		selector = `.{skinnedTag}::UICorner`,
		props = { CornerRadius = udim(0, 0) },
	})
	emit({
		name = `Skinned — {slot} outline`,
		selector = `.{skinnedTag}::UIStroke`,
		props = { Thickness = num(0), Transparency = num(1), ApplyStrokeMode = STROKE_BORDER },
	})
end

-- ===========================================================================
-- THE CIRCLE BUTTON'S CHROME — ONE EMITTER, BOTH BUILDERS
-- (feature round 2026-07-26; `UI.Button{ shape = "circle" }`)
-- ===========================================================================
--
-- A disc's silhouette is the pill radius the slider thumb already proved:
-- `CornerRadius = UDim(0.5, 0)` on a phantom `::UICorner`, which costs a FLAT
-- theme zero new instances because the rule creates the modifier. Its rim is a
-- hairline on a phantom `::UIStroke` — and it carries `ApplyStrokeMode = Border`
-- explicitly, because the engine default is `Contextual`, which on a TextButton
-- strokes the GLYPHS instead of the border (director round 10, measured live:
-- every chip label grew a hairline halo and no outline drew at all).
--
-- WHY EXACTLY TWO RULES AND NOT ONE PER STATE. The cascade is Priority first,
-- then insertion order, with NO selector specificity — so a rule that sits after
-- every surface corner beats every surface corner, whichever surface the node
-- happens to wear. That is the finding-11 requirement ("a new surface/shape must
-- carry its own corner rule") satisfied at its source: the SHAPE carries the
-- corner, instead of every surface having to learn about the shape. Duplicating
-- it into the hover/press/disabled groups would be worse than redundant: a rule
-- NAME IS IDENTITY here (see `emitSuppression` below), so five same-named rules
-- are five Style-Editor entries a designer's edit picks between at random. What
-- makes one rule sufficient is an invariant, not a coincidence, so it is
-- asserted rather than assumed: `tests/button_shape.spec.luau` fails if ANY rule
-- after this one writes CornerRadius on a selector a circle Button matches,
-- except the skinned-slot suppression, which must win (see below).
--
-- THE ONE RULE THAT BEATS IT, ON PURPOSE. `Skinned — control corner` sits in the
-- `chrome` group and zeroes the radius of a node whose art has taken over. That
-- is the image-is-the-element posture (ADR-0020 R9) and it is correct for a
-- circle too: once a package dresses the button, the ART is the silhouette and
-- the node's own plate is invisible underneath it, so its radius means nothing.
local function emitShapeChrome(
	metrics: any,
	hairlineT: RuleProp,
	hairlineW: RuleProp,
	emit: (Rule) -> (),
	fromMetric: ((string, string, string, string) -> ())?
)
	local circle = sheet_model.TAGS.shapePrefix .. "circle"
	emit({
		name = "Circle button — corner",
		selector = `.{circle}::UICorner`,
		props = { CornerRadius = udim(0.5, 0) },
	})
	emit({
		name = "Circle button — hairline",
		selector = `.{circle}::UIStroke`,
		props = {
			Color = "$Hairline",
			Transparency = hairlineT,
			Thickness = hairlineW,
			ApplyStrokeMode = STROKE_BORDER,
		},
	})
	if fromMetric ~= nil then
		fromMetric("strokes.hairline", "Circle button — hairline", "Thickness", "number")
	end
end

export type BuildOpts = {
	-- ordered; the FIRST theme is the base/default unless defaultTheme names another
	themes: { { name: string, style: any } },
	defaultTheme: string?,
}

function sheet_model.build(opts: BuildOpts): Model
	assert(
		type(opts) == "table" and type(opts.themes) == "table" and #opts.themes >= 1,
		"sheet_model.build: themes required"
	)
	local themes: { Theme } = {}
	for _, entry in opts.themes do
		table.insert(themes, {
			name = entry.name,
			tokens = themeTokens(entry.style),
			contrast = gateTheme(entry.name, entry.style),
		})
	end
	local base = opts.themes[1].style
	local x = base.extra
	local T = sheet_model.TAGS
	local S = T.surfacePrefix

	-- Numeric config shared by rules (literals in rules, editable per-rule in
	-- the editor; colors ride $tokens — the designer-editable palette)
	local numbers = {
		HairlineTransparency = x.hairlineOpacity,
		ScrimTransparency = x.scrimOpacity,
		DisabledContentTransparency = x.disabledContentOpacity,
	}

	-- ORDERED rules. Insertion order IS the cascade (later wins on overlap):
	-- class defaults -> surfaces (+phantom chrome) -> selected -> hover ->
	-- pressed -> disabled. Names are what the Style Editor shows (§6.1).
	--
	-- The class-default transparency rules exist because the adapter must NOT
	-- write BackgroundTransparency at create in native mode (an explicit write
	-- would permanently defeat every surface rule's transparency, spike m10) —
	-- so "invisible until a surface says otherwise" is itself sheet-owned.
	local rules: { Rule } = {
		{ name = "Frame default", selector = "Frame", props = { BackgroundTransparency = num(1) } },
		{ name = "Label default", selector = "TextLabel", props = { BackgroundTransparency = num(1) } },
		{ name = "Button default", selector = "TextButton", props = { BackgroundTransparency = num(1) } },
		{ name = "Image default", selector = "ImageLabel", props = { BackgroundTransparency = num(1) } },
		{ name = "Field default", selector = "TextBox", props = { BackgroundTransparency = num(1) } },
		{ name = "Scroll default", selector = "ScrollingFrame", props = { BackgroundTransparency = num(1) } },
		-- ...and the ONE exception to "invisible until a surface says otherwise":
		-- a node the author tinted. Directly under the class defaults it beats and
		-- above every surface, slot and scrim, whose own alphas still win. See
		-- TAGS.tintFill for why this is a rule and not the explicit write it looks
		-- like it should be.
		{ name = "Tint fill", selector = "." .. T.tintFill, props = { BackgroundTransparency = num(0) } },
		{ name = "Text default", selector = "TextLabel", props = { TextColor3 = "$Content", FontFace = BUILDER_SANS } },
		{
			name = "Button text default",
			selector = "TextButton",
			props = { TextColor3 = "$Content", FontFace = BUILDER_SANS },
		},
		{
			name = "Field text default",
			selector = "TextBox",
			props = { TextColor3 = "$Content", PlaceholderColor3 = "$ContentSecondary", FontFace = BUILDER_SANS },
		},
		{
			name = "Divider",
			selector = ".luau-divider",
			props = { BackgroundColor3 = "$Hairline", BackgroundTransparency = num(0) },
		},
		{ name = "Secondary text", selector = ".luau-role-secondary", props = { TextColor3 = "$ContentSecondary" } },
		{ name = "Strong text", selector = ".luau-role-strong", props = { TextColor3 = "$ContentStrong" } },
		-- THE TYPOGRAPHY-ROLE FACES (F2, 2026-08-02). One rule per role that wears
		-- a face this builder can name. A compiled TOKEN style carries sizes only —
		-- font descriptors live in a theme PACKAGE (`buildPackage` below emits all
		-- eight from `type.<role>.font`) — so the built-in model states exactly what
		-- the neutral snapshot derives: the six ladder roles keep the family's
		-- Regular face (already the class default, so these rules are inert and no
		-- existing screen moves) and the two weight roles take the derived faces.
		{ name = "Type — strong", selector = ".luau-type-strong", props = { FontFace = BUILDER_SANS_SEMIBOLD } },
		{ name = "Type — numeral", selector = ".luau-type-numeral", props = { FontFace = BUILDER_SANS_BOLD } },
		{ name = "Scroll bar", selector = "ScrollingFrame", props = { ScrollBarImageColor3 = "$ContentSecondary" } },
		{
			name = "Base surface",
			selector = "." .. S .. "base",
			props = { BackgroundColor3 = "$Surface", BackgroundTransparency = num(0) },
		},
		{
			name = "Raised panel",
			selector = "." .. S .. "raised",
			props = { BackgroundColor3 = "$SurfaceStrong", BackgroundTransparency = num(0) },
		},
		{
			name = "Raised panel — corner",
			selector = "." .. S .. "raised::UICorner",
			props = { CornerRadius = udim(0, base.radii.panel) },
		},
		{
			name = "Raised panel — hairline",
			selector = "." .. S .. "raised::UIStroke",
			props = {
				Color = "$Hairline",
				Transparency = num(numbers.HairlineTransparency),
				Thickness = num(base.strokes.hairline),
				ApplyStrokeMode = STROKE_BORDER,
			},
		},
		{
			name = "Control fill",
			selector = "." .. S .. "control",
			props = { BackgroundColor3 = "$Control", BackgroundTransparency = num(0) },
		},
		{
			name = "Control — corner",
			selector = "." .. S .. "control::UICorner",
			props = { CornerRadius = udim(0, base.radii.control) },
		},
		{
			name = "Field — outline",
			selector = "TextBox." .. S .. "control::UIStroke",
			props = {
				Color = "$Hairline",
				Transparency = num(numbers.HairlineTransparency),
				Thickness = num(base.strokes.hairline),
				ApplyStrokeMode = STROKE_BORDER,
			},
		},
		{
			name = "Chip",
			selector = "." .. S .. "chip",
			props = { BackgroundColor3 = "$Control", BackgroundTransparency = num(0) },
		},
		{
			name = "Chip — corner",
			selector = "." .. S .. "chip::UICorner",
			props = { CornerRadius = udim(0, base.radii.control) },
		},
		{
			name = "Chip — outline",
			selector = "." .. S .. "chip::UIStroke",
			props = {
				Color = "$Hairline",
				Transparency = num(numbers.HairlineTransparency),
				Thickness = num(base.strokes.hairline),
				ApplyStrokeMode = STROKE_BORDER,
			},
		},
		{
			name = "Badge",
			selector = "." .. S .. "badge",
			props = { BackgroundColor3 = "$SurfaceStrong", BackgroundTransparency = num(0) },
		},
		{
			name = "Badge — circle",
			selector = "." .. S .. "badge::UICorner",
			props = { CornerRadius = udim(0.5, 0) },
		},
		{
			name = "Primary button",
			selector = "." .. S .. "accent",
			props = { BackgroundColor3 = "$Accent", BackgroundTransparency = num(0) },
		},
		-- THE ACCENT SURFACE'S CORNER (director round 11, found live under
		-- glossy-mobile). Per-surface rules REPLACE, they do not compose: a chip
		-- that becomes the primary action drops `.luau-surface-chip` for
		-- `.luau-surface-accent`, and this rule set carried a fill and a label
		-- colour and no corner — so the selected button went hard square while
		-- every sibling stayed a pill at `radii.control = 16`. The bespoke path
		-- never showed it because `wireInteractiveStates` gives every Button a
		-- REAL UICorner before `applySurface` runs.
		{
			name = "Primary button — corner",
			selector = "." .. S .. "accent::UICorner",
			props = { CornerRadius = udim(0, base.radii.control) },
		},
		{
			name = "Primary button label",
			selector = "TextButton." .. S .. "accent",
			props = { TextColor3 = "$OnAccent" },
		},
	}
	local function push(rule: Rule)
		table.insert(rules, rule)
	end
	local function pushAll(more: { Rule })
		for _, rule in more do
			push(rule)
		end
	end

	-- VALUE-CONTROL CHROME: ITS OWN PAINT (RS-A16-D4). The same three rules per
	-- slot the package builder emits, from the same shared emitter, at the same
	-- cascade position: after every surface fill it must beat, and before the
	-- scrim and the `Grip focus` accent that must still beat IT.
	local hairlineT, hairlineW = num(numbers.HairlineTransparency), num(base.strokes.hairline)
	-- THE DISC'S CHROME, immediately after every surface corner it has to beat
	-- and before anything that changes only colour (see emitShapeChrome)
	emitShapeChrome(base, hairlineT, hairlineW, push)
	for _, slot in chrome_slots.OWN_PAINT_SLOTS do
		emitOwnSlotPaint(slot, base, hairlineT, hairlineW, push)
	end

	pushAll({
		{
			name = sheet_model.SCRIM_RULE,
			selector = "." .. S .. "scrim",
			props = { BackgroundColor3 = "$Surface", BackgroundTransparency = num(numbers.ScrimTransparency) },
		},
		{
			name = "Grip focus",
			selector = ".luau-grip-focus",
			props = { BackgroundColor3 = "$Accent", BackgroundTransparency = num(0) },
		},
		-- toggle knob-track chrome (director live find 2026-07-24): the
		-- assembly's PRE-PARENT transparency writes are STOMPED when styling
		-- first applies (defeat is order-sensitive — see the spike addendum),
		-- so opacity is sheet-owned via this tag; the value-driven COLOR writes
		-- happen after styling and have no competing rule, so they stay bespoke
		{
			name = "Toggle chrome",
			selector = ".luau-toggle-chrome",
			props = { BackgroundTransparency = num(0) },
		},
		{
			name = "Selected row",
			selector = "TextButton." .. T.selected,
			-- the label pairs with the plate it now sits on (director round 8).
			-- `$OnSelected` resolves to $Content wherever content still clears the
			-- 4.5 floor against this theme's selected surface — which is every
			-- flat reference theme, so this is a no-op there — and to $OnAccent,
			-- the contract's one guaranteed partner, where it does not.
			props = { BackgroundColor3 = "$ControlSelected", TextColor3 = "$OnSelected" },
			transitions = { BackgroundColor3 = "fast" },
		},
		-- semantic button roles (B-BTN2): tag-driven, sheet-painted. No parallel
		-- paint-state system — these are ordinary rules a designer can retheme.
		--
		-- ORDER MATTERS and was found live: the measured cascade is Priority first,
		-- then INSERTION ORDER (later wins), with no selector specificity. Placed
		-- before "Control fill" these rules lost their BackgroundColor3 to it while
		-- TextColor3 survived — a destructive button with white text on a neutral
		-- fill. They therefore sit after the base/surface/selected fills and before
		-- the hover/press rules, so a role owns the resting fill while the engine
		-- states still layer on top.
		{
			name = "Destructive button",
			selector = ".luau-role-destructive",
			props = { BackgroundColor3 = "$Danger", TextColor3 = "$OnDanger" },
		},
		{
			name = "Cancel button",
			selector = ".luau-role-cancel",
			props = { BackgroundColor3 = "$Surface", TextColor3 = "$ContentSecondary" },
		},
	})

	-- A SKINNED VALUE SLOT SUPPRESSES ITS OWN PAINT TOO — PRE-ARMED, exactly as
	-- in `buildPackage` (director round 5). The base seed needs it for the same
	-- reason a flat package does: the RUNG-2 per-view override (a Slider's
	-- `thumbImage`) skins a node with NO package installed at all, and a node that
	-- earns `luau-skinned-<slot>` with no rule to match it keeps a solid plate
	-- showing through every transparent pixel of the author's own art.
	--
	-- After the paint above (a floor is only lifted by art) and before the
	-- interaction states, which only change colour — so an invisible plate stays
	-- invisible through hover and press.
	for _, slot in chrome_slots.OWN_PAINT_SLOTS do
		emitSlotSuppression(slot, push)
	end

	pushAll({
		{
			name = "Control — hover",
			selector = "TextButton." .. T.interactive .. "." .. T.pointerLive .. ":Hover",
			props = { BackgroundColor3 = "$ControlHover" },
			transitions = { BackgroundColor3 = "fast" },
		},
		{
			name = "Primary — hover",
			selector = "TextButton." .. S .. "accent." .. T.pointerLive .. ":Hover",
			props = { BackgroundColor3 = "$AccentHover" },
			transitions = { BackgroundColor3 = "fast" },
		},
		{
			name = "Control — pressed",
			selector = "TextButton." .. T.interactive .. ":Press",
			props = { BackgroundColor3 = "$ControlPressed" },
		},
		{
			name = "Primary — pressed",
			selector = "TextButton." .. S .. "accent:Press",
			props = { BackgroundColor3 = "$AccentPressed" },
		},
		-- role-aware interaction states (verifier finding V14): the generic
		-- "Control — hover/pressed" rules are keyed on the interactive tag, NOT on
		-- the role, so without these a hovered destructive button repainted itself
		-- neutral and the role visually vanished at the moment of the click.
		{
			name = "Destructive — hover",
			selector = "TextButton.luau-role-destructive." .. T.pointerLive .. ":Hover",
			props = { BackgroundColor3 = "$DangerHover" },
			transitions = { BackgroundColor3 = "fast" },
		},
		{
			name = "Destructive — pressed",
			selector = "TextButton.luau-role-destructive:Press",
			props = { BackgroundColor3 = "$DangerPressed" },
		},
		{
			name = "Disabled button",
			selector = "TextButton:NonInteractable",
			props = { TextTransparency = num(numbers.DisabledContentTransparency) },
		},
		{
			name = "Disabled field",
			selector = "TextBox:NonInteractable",
			props = { TextTransparency = num(numbers.DisabledContentTransparency) },
		},
		-- SEMANTIC ICON ART (ADR-0020 R4). Last in the `disabled` group and so
		-- last in the whole cascade: the node's glyph is a fallback the control
		-- always draws, and when real art covers it the glyph must go — including
		-- over the 0.45 disabled value, which would otherwise leave a ghost "+"
		-- showing through a disabled stepper's plate art.
		{
			name = "Semantic icon replaces the glyph",
			selector = `.{chrome_slots.TAGS.iconArt}`,
			props = { TextTransparency = num(1) },
		},
		-- THE HELD SOURCE EMPTIES (director round five): while a drag session
		-- carries this node's payload, its label is blank — the ghost is the
		-- card's face now, and two faces read as "still here"
		{
			name = "Held drag source empties its label",
			selector = `.{chrome_slots.TAGS.dragHeld}`,
			props = { TextTransparency = num(1) },
		},
	})

	-- Layout-reference MIRRORS (§6.9 Fallback B): editor-VISIBLE, generator-
	-- owned attributes regenerated on every apply. Editing them in the editor
	-- does nothing to layout (the solver reads the Luau tokens) — the styling
	-- guide labels them read-only-reference; the freshness check re-stamps them.
	local mirrors: { { name: string, value: number } } = {}
	for _, m in
		{
			{ "Space", base.space, { "xs", "s", "m", "l", "xl" } },
			{ "Type", base.type, { "caption", "label", "body", "heading", "title" } },
			{ "Radius", base.radii, { "control", "panel", "pill" } },
		}
	do
		local prefix, tbl, keys = m[1] :: string, m[2] :: any, m[3] :: { string }
		for _, key in keys do
			if tbl[key] ~= nil then
				table.insert(mirrors, { name = prefix .. key:sub(1, 1):upper() .. key:sub(2), value = tbl[key] })
			end
		end
	end
	table.insert(mirrors, { name = "TargetMinimum", value = base.targetSizes.minimum })
	table.insert(mirrors, { name = "MotionFast", value = base.motion.fast })
	table.insert(mirrors, { name = "MotionNormal", value = base.motion.normal })

	-- deterministic stamp over everything the generator writes
	local parts: { string } = {}
	for _, th in themes do
		local names = {}
		for k in th.tokens do
			table.insert(names, k)
		end
		table.sort(names)
		for _, k in names do
			local v = th.tokens[k]
			table.insert(parts, string.format("%s.%s=%.4f,%.4f,%.4f", th.name, k, v.r, v.g, v.b))
		end
	end
	for _, r in rules do
		table.insert(parts, r.selector)
		local pnames = {}
		for k in r.props do
			table.insert(pnames, k)
		end
		table.sort(pnames)
		for _, k in pnames do
			local v = r.props[k]
			table.insert(
				parts,
				k
					.. "="
					.. (
						if type(v) == "string"
							then v
							else tostring(v.kind) .. tostring(v.value or v.offset or v.family or "")
					)
			)
		end
	end
	for _, m in mirrors do
		table.insert(parts, m.name .. "=" .. tostring(m.value))
	end

	return {
		schema = "luauui-native-sheet/1",
		stamp = stampOf(parts),
		defaultTheme = opts.defaultTheme or opts.themes[1].name,
		themes = themes,
		rules = rules,
		mirrors = mirrors,
		motion = { fast = base.motion.fast, normal = base.motion.normal },
	}
end

-- ===========================================================================
-- buildPackage: a compiled ThemePackage -> the ordered sheet model
-- (ADR-0019 §5, theme-packages-and-skinning package 3)
-- ===========================================================================
--
-- `build` above compiles ONE LuauUI token style and is the legacy path; it is
-- unchanged and byte-stable. `buildPackage` compiles a package's `style` and
-- `chrome` sections, which adds three things `build` cannot express:
--
--   * per-theme TYPOGRAPHY — the package's typography roles carry the font
--     descriptor, so a theme can change the family (build pinned Builder Sans);
--   * NINE-SLICE CHROME — the six image properties on the decoration child's
--     slot tag, plus per-state tint rules that modulate ONE base image rather
--     than swapping to a second asset (feasibility m2);
--   * GRADIENTS — `::UIGradient` phantom rules, confirmed to render with zero
--     child instances (feasibility m7).
--
-- PSEUDO-SELECTOR ALLOWLIST. Only `::UICorner`, `::UIStroke` and `::UIGradient`
-- are proven. `::UIShadow` is accepted by `SetProperties`, reports no
-- `SelectorError`, and paints NOTHING on 0.731 (m7) — a rule that looks correct
-- everywhere except on screen. Every selector this compiler emits or accepts is
-- checked, and an inert pseudo selector is a compile error naming itself.
--
-- CASCADE. Priority is explicit and equals index * 10 (the same number
-- `native_style.priorityFor` computes, so the two can never disagree), and the
-- group order IS the design: base -> surfaces -> roles -> chrome -> hover ->
-- press -> disabled. Chrome sits after roles because the decoration image is
-- the resting appearance a role may not repaint, and before hover/press
-- because interaction state must always win over rest.

sheet_model.ALLOWED_PSEUDO = table.freeze({ UICorner = true, UIStroke = true, UIGradient = true })

-- A phantom-modifier selector addresses a DIFFERENT class's property namespace:
-- `Color` on a `::UIStroke` rule is UIStroke.Color, which is not any GuiObject
-- property and therefore is not in `render/authority`'s manifest (that manifest
-- names them StrokeColor/StrokeTransparency/StrokeThickness, the LuauUI-side
-- prop names, which is the right vocabulary for the adapter and the wrong one
-- for a rule). So the property gate for a pseudo selector is this closed set,
-- and `package.lintProperty` governs everything else.
sheet_model.PHANTOM_PROPS = table.freeze({
	UICorner = table.freeze({ CornerRadius = true }),
	UIStroke = table.freeze({
		Color = true,
		Transparency = true,
		Thickness = true,
		ApplyStrokeMode = true,
		LineJoinMode = true,
		Enabled = true,
	}),
	UIGradient = table.freeze({
		Color = true,
		Transparency = true,
		Rotation = true,
		Offset = true,
		Enabled = true,
	}),
})

-- the ordered rule groups; the array position is the cascade position
sheet_model.RULE_GROUPS = table.freeze({ "base", "surfaces", "roles", "chrome", "hover", "press", "disabled" })

-- checkSelector(selector, ruleName): every `::Pseudo` in a selector must be on
-- the proven list. Returns the selector so call sites read as assertions.
function sheet_model.checkSelector(selector: string, ruleName: string): string
	for pseudo in string.gmatch(selector, "::([%w_]+)") do
		if not (sheet_model.ALLOWED_PSEUDO :: any)[pseudo] then
			local why = if pseudo == "UIShadow"
				then "it is SILENTLY ACCEPTED and paints nothing on 0.731 "
					.. "(artifacts/theme-packages-and-skinning/feasibility/m7-gradient-shadow-phantoms.json) — "
					.. "theme shadows stay on the bespoke UIShadow path behind its capability probe"
				else "only the phantom modifiers proven to render may be styled"
			error(
				`sheet_model.buildPackage: rule '{ruleName}' names the inert pseudo selector '::{pseudo}' — {why}. `
					.. `Allowed pseudo selectors: ::UICorner, ::UIStroke, ::UIGradient.`,
				0
			)
		end
	end
	return selector
end

-- checkContentValue(ruleName, prop, value): a rule that paints art carries a
-- plain STRING and nothing else (ADR-0020 R6, probe rs-m7).
--
-- Strings coerce on `Image` and on `ImageContent` alike — even a rule authored
-- with `Content.fromUri` round-trips as a string through `GetProperties`, which
-- is why this stage ships zero Content materialization machinery. An
-- OBJECT-sourced Content is the trap: `SetProperties` ACCEPTS it, reports no
-- selector error, resolves to `Content{SourceType=None}` and paints nothing —
-- the fourth accepted-but-silently-inert engine behaviour this project has
-- catalogued (after ::UIShadow, the Global ZIndex default and the pre-join
-- write defeat). EditableImage skins therefore stay an ADAPTER INSTANCE write,
-- declared as such, and never a rule value.
local CONTENT_PROPS: { [string]: boolean } = { Image = true, ImageContent = true }

function sheet_model.checkContentValue(ruleName: string, prop: string, value: any)
	if not CONTENT_PROPS[prop] then
		return
	end
	if type(value) == "string" then
		return
	end
	local what = if type(value) == "table" and type((value :: any).kind) == "string"
		then `a '{(value :: any).kind}' value`
		else `a {type(value)}`
	error(
		`sheet_model.buildPackage: rule '{ruleName}' sets {prop} to {what} — a theme rule may carry only a plain `
			.. "string URI there. The engine COERCES a string onto ImageContent (rs-m7), but an object-sourced "
			.. "Content in a rule is accepted, reports no error, and paints NOTHING. An EditableImage skin is an "
			.. "adapter instance write, declared in the authority manifest, never a rule value.",
		0
	)
end

-- The slot -> selector map: which nodes a slot's NATIVE paint and gradient
-- apply to. The decoration child carries `.luau-chrome-<slot>`; the slot's
-- native treatment lands on the node the renderer already classified, which is
-- why these reuse the Step 2 surface tags rather than inventing a parallel set.
local SLOT_SELECTOR: { [string]: string } = {
	panel = ".luau-surface-raised",
	control = ".luau-surface-control",
	field = "TextBox.luau-surface-control",
	selection = "TextButton.luau-selected",
	divider = ".luau-divider",
	scrollbar = "ScrollingFrame",
	badge = ".luau-surface-badge",
	-- sliderTrack / sliderThumb are ABSENT on purpose. SLOT_SELECTOR is the
	-- gradient target map, and a wash may never reach a value control's chrome
	-- (chrome_slots.isGradientable) — its alpha is exactly what made the thumb
	-- see-through. Their node-level paint is the shared `Slot — <slot>` family
	-- (emitOwnSlotPaint, above both builders), keyed on the hint tag.
}
local SLOT_STROKED: { [string]: boolean } = { panel = true, control = true, field = true }

local function pascal(name: string): string
	return name:sub(1, 1):upper() .. name:sub(2)
end

-- A palette role a recipe may name as its resting tint, mapped to the theme
-- token that carries it. Anything else is an authoring error rather than a
-- silent white, because a tint that silently does nothing is invisible in
-- review and obvious only on a device.
local TINT_ROLE_TOKEN: { [string]: string } = {
	surface = "$Surface",
	surfaceStrong = "$SurfaceStrong",
	content = "$Content",
	contentStrong = "$ContentStrong",
	contentSecondary = "$ContentSecondary",
	accent = "$Accent",
	control = "$Control",
	controlSelected = "$ControlSelected",
	danger = "$Danger",
	hairline = "$Hairline",
}

-- The chrome tint ladder lives in chrome_slots, because the explicit-write
-- fallback path needs the same resting value these rules paint. Every slot
-- shares it, so a package retunes three numbers rather than three per slot.
local CHROME_TINT_REST = chrome_slots.TINT.rest
local CHROME_TINT_HOVER = chrome_slots.TINT.hover
local CHROME_TINT_PRESSED = chrome_slots.TINT.pressed

local function greyToken(v: number): TokenValue
	return { kind = "color", r = v, g = v, b = v }
end

-- A package theme may omit `extra` (the non-contract paint roles). Rather than
-- fail — a third-party package should not have to restate the interaction ramp
-- to change a palette — derive the missing roles from the contract colours with
-- the same lerps the library's own style uses.
local function effectiveExtra(theme: any): any
	local c = theme.colors
	local x: any = {}
	for k, v in (theme.extra or {}) :: any do
		x[k] = v
	end
	local function fill(key: string, value: any)
		if x[key] == nil then
			x[key] = value
		end
	end
	fill("control", { r = c.surfaceStrong.r, g = c.surfaceStrong.g, b = c.surfaceStrong.b })
	fill("controlHover", lerp(x.control, WHITE, 0.12))
	fill("controlPressed", lerp(x.control, BLACK, 0.12))
	fill("controlSelected", lerp(x.control, c.accent, 0.35))
	fill("contentSecondary", lerp(c.content, c.surface, 0.35))
	fill("hairline", { r = 1, g = 1, b = 1 })
	fill("scrimOpacity", 0.45)
	fill("hairlineOpacity", 0.92)
	-- shared with the rung-2 adapter path so the accessibility floor is ONE number
	-- (chrome_slots.DISABLED_CONTENT_OPACITY; arch verifier F3)
	fill("disabledContentOpacity", chrome_slots.DISABLED_CONTENT_OPACITY)
	fill("focusRingThickness", 2)
	fill("pressedScale", 0.985)
	fill("tenFootFocusRingThickness", 4)
	fill("tenFootFocusScale", 1.05)
	-- the lerps above return TokenValue tables ({kind="color", ...}); the paint
	-- consumers want plain rgb, and both shapes carry r/g/b, so nothing to strip
	return x
end

-- ===== THE CONTINUOUS-COLOUR CHANNEL (`tint`, ADR-0022 Decision 6) =========
--
-- The tint is the SAME class of thing the toggle palette below is, and for the
-- same stated reason: a rule cannot see a VALUE. A blend driven by an energy
-- signal, or an identity hue that arrives as game data, can never be a selector
-- — so the adapter writes it, and this is the pure resolver both the engine
-- adapter and the headless FakeTarget go through, so "the fake and the live
-- target agree about the colour" is a fact rather than a hope.
--
-- The ROLE VOCABULARY IS THE ONE `TINT_ROLE_TOKEN` ALREADY DECLARES for a chrome
-- recipe's resting tint (a role that resolves against a theme's palette), and
-- `styling.TINT_ROLES` is the copy the public schema validates against — the two
-- are asserted equal at load, because a role the schema accepts and this
-- resolver cannot resolve would be a tint that paints nothing.
do
	local declared: { [string]: boolean } = {}
	for _, role in styling.TINT_ROLES do
		declared[role] = true
		assert(TINT_ROLE_TOKEN[role] ~= nil, `styling.TINT_ROLES names '{role}', which no theme token carries`)
	end
	for role in TINT_ROLE_TOKEN do
		assert(declared[role], `TINT_ROLE_TOKEN carries '{role}', which styling.TINT_ROLES does not offer`)
	end
end
sheet_model.TINT_ROLES = styling.TINT_ROLES

-- The base a role-blend tint blends FROM when the author names no `from`, per
-- blueprint class. It is the class's IDENTITY paint — the value that makes
-- `blend = 0` mean "unchanged" — and never an inferred surface fill (see
-- styling.checkTint for why the surface mapping is deliberately not consulted).
--   Box    the page colour: a Box with no surface paints nothing, so a wash rises
--          out of the background it sits on
--   Text   the primary content role, which is what a label already draws in
--   Path   the same, matching UI.Path's default stroke role
--   Image  WHITE, the identity for ImageColor3 — the engine multiplies the
--          picture by it, so white is "the picture as authored"
sheet_model.TINT_IDENTITY = table.freeze({
	Box = "surface",
	Text = "content",
	Path = "content",
	Image = "white",
	-- a Stage tints its rendered SCENE through the same ImageColor3 multiply an
	-- Image uses, so its identity is white for the same reason: white multiplies
	-- to the picture the engine already drew
	Stage = "white",
})

-- paletteColor(theme, role) -> { r, g, b }: a declared tint role resolved
-- against a theme's contract colours and then its (derived) extra roles — the
-- same two-step order every other paint decision in this module uses.
function sheet_model.paletteColor(theme: any, role: string): any
	if role == "white" then
		return { r = WHITE.r, g = WHITE.g, b = WHITE.b }
	end
	local c = if type(theme) == "table" then theme.colors else nil
	local direct = if type(c) == "table" then c[role] else nil
	if type(direct) == "table" and type(direct.r) == "number" then
		return { r = direct.r, g = direct.g, b = direct.b }
	end
	-- `effectiveExtra` DERIVES the missing interaction roles from the contract
	-- colours, so a package theme that never declared `control` still resolves one
	-- — but it reads those contract colours, so a theme without them falls back to
	-- whatever `extra` it does carry rather than crashing a paint write.
	local x = if type(c) == "table"
			and type(c.surfaceStrong) == "table"
			and type(c.content) == "table"
		then effectiveExtra(theme)
		elseif type(theme) == "table" and type(theme.extra) == "table" then theme.extra
		else {}
	local extra = x[role]
	if type(extra) == "table" and type(extra.r) == "number" then
		return { r = extra.r, g = extra.g, b = extra.b }
	end
	if role == "danger" then
		local danger = dangerPair(if type(c) == "table" then c else {})
		return { r = danger.r, g = danger.g, b = danger.b }
	end
	error(`LuauUI tint: theme carries no colour for role '{role}'`, 0)
end

-- tintColor(theme, tint, class) -> { r, g, b }. `theme` is one entry of
-- `package.style.themes` ({ colors, extra }) — or, with no package installed,
-- the style the target was built with, which has the same shape. A malformed
-- value is a LOUD error at the write site and not a silent no-op: a bound tint is
-- read long after construction, so this is the only place a reactive one is ever
-- checked.
function sheet_model.tintColor(theme: any, tint: any, class: string): any
	local ok, detail = styling.checkTint(tint)
	if not ok then
		error(`LuauUI tint on a {class}: {tostring(detail)}`, 0)
	end
	local direct = tint.direct
	if direct ~= nil then
		local hex = styling.hexRgb(direct)
		if hex ~= nil then
			return hex
		end
		return { r = direct.r, g = direct.g, b = direct.b }
	end
	local identity = (sheet_model.TINT_IDENTITY :: any)[class] or "surface"
	local base = sheet_model.paletteColor(theme, tint.from or identity)
	local target = sheet_model.paletteColor(theme, tint.role)
	local blended = lerp(base, target, tint.blend)
	return { r = blended.r, g = blended.g, b = blended.b }
end

-- tintTransparency(tint, class) -> number. The tint's own alpha, engine-true
-- (0 opaque, 1 invisible), defaulting to opaque so every tint authored before the
-- channel existed writes exactly what it wrote before.
--
-- A `Path` is REFUSED rather than silently ignored: the engine's Path2D carries a
-- colour and a thickness and no transparency at all, so an accepted-and-dropped
-- alpha would be precisely the failure class this framework keeps closing. The
-- message names the working idiom (fade the Path's own container).
function sheet_model.tintTransparency(tint: any, class: string): number
	local alpha = if type(tint) == "table" then (tint :: any).transparency else nil
	if alpha == nil then
		return styling.TINT_TRANSPARENCY_DEFAULT
	end
	if class == "Path" then
		error(
			"LuauUI tint on a Path: `transparency` has no channel here — a Path2D stroke carries a colour "
				.. "and a thickness only. Fade the path's container instead (a `canvasGroup` ZStack/Box).",
			0
		)
	end
	return alpha :: number
end

-- THE TOGGLE PALETTE (director follow-up 2026-07-25). PURE, and exported so the
-- adapter and the specs resolve one mapping rather than two.
--
-- The toggle's knob-and-track is the last piece of value-driven paint the sheet
-- cannot own: its transparency rides the `Toggle chrome` tag rule, but the
-- COLOURS change with the VALUE, and a rule cannot see a value. They were
-- therefore written from constants captured at adapter construction — so a
-- parchment toggle rendered a Studio-Neutral BLUE pill (director screenshot).
-- This is the resolver those two write sites now go through.
--
-- THE MAPPING, and why each half is what it is:
--
--   trackOn  = colors.accent        the palette's "this is active" colour, and
--                                   the only one every theme guarantees a
--                                   readable partner for
--   knobOn   = colors.onAccent      that guaranteed partner. The contract gates
--                                   the accent/onAccent pair at 4.5:1 in every
--                                   theme, which is exactly the job the knob
--                                   needs done: measured 5.54–11.47:1 across the
--                                   five reference packages.
--   trackOff = extra.controlPressed a control surface, RECESSED — which is what
--                                   an off switch's well is. Deliberately NOT
--                                   `colors.surface`, the value this used to
--                                   paint: `surface` is darker than the row on a
--                                   dark palette and LIGHTER on a light one
--                                   (Parchment Daylight surface 226,210,176 vs
--                                   control 214,194,156), so an off track would
--                                   read as a well in one theme and a raised bump
--                                   in another. `controlPressed` is derived as
--                                   control lerped toward black, so it is darker
--                                   than the row it sits in BY CONSTRUCTION, in
--                                   every theme including ones that never
--                                   declared it.
--   knobOff  = colors.content       the primary content role, which is also what
--                                   the knob already painted — so a target with
--                                   no package installed is byte-identical.
--                                   Measured 6.81–14.34:1 against trackOff across
--                                   the reference corpus, i.e. clears the 3:1
--                                   non-text floor by at least 2.2x everywhere.
--
-- Returns plain rgb tables; the adapter converts. `theme` is one entry of
-- package.style.themes ({ colors, extra }).
function sheet_model.togglePalette(theme: any): any
	local c = theme.colors
	local x = effectiveExtra(theme)
	local function rgb(v: any)
		return { r = v.r, g = v.g, b = v.b }
	end
	return {
		trackOn = rgb(c.accent),
		trackOff = rgb(x.controlPressed),
		knobOn = rgb(c.onAccent),
		knobOff = rgb(c.content),
	}
end

-- gradientOf(theme, slot): the per-theme gradient declaration for a slot.
-- A chrome RECIPE cannot carry it — `package.define` closes recipe fields to
-- { kind, asset, contentInsets, fallback } — and it should not: a gradient is
-- colour, and colour is per theme. It therefore rides the theme's `extra`
-- section, which `define` passes through unvalidated for exactly this class of
-- non-contract paint role.
--
--   style.themes[i].extra.chromeGradient.<slot> = {
--       rotation = <degrees>,
--       stops = { { t = 0, r = .., g = .., b = .. }, ... },   -- >= 2
--       alpha = { { t = 0, v = 0 }, ... },                    -- optional
--   }
local function gradientOf(theme: any, slot: string): any
	local declared = (theme.extra or {}).chromeGradient
	if type(declared) ~= "table" then
		return nil
	end
	local entry = declared[slot]
	return if type(entry) == "table" then entry else nil
end

export type BuildPackageOpts = {
	defaultTheme: string?,
	-- Extra author-supplied rules, appended to the chrome group. This is the
	-- surface a Style-Editor round-trip feeds back, and it is why the pseudo
	-- allowlist and the §4 property linter run on INPUT and not only on what
	-- this compiler happens to emit.
	rules: { Rule }?,
}

function sheet_model.buildPackage(package: any, opts: BuildPackageOpts?): Model
	assert(
		type(package) == "table" and package.schema == themePackage.SCHEMA,
		"sheet_model.buildPackage: expected a package compiled by themes.define"
	)
	local metrics = package.metrics
	local o = opts or {}

	-- ----- metric-derived rule props (live-edit repaint map) ---------------
	-- Corner radii and stroke thickness are baked into rules as LITERALS (a
	-- number-typed metric attribute cannot be a UDim `$Token`), so a designer's
	-- Radii_*/Strokes_* sheet edit would re-solve layout while the paint kept
	-- the seeded value. This map records every rule prop derived from a metric
	-- so the controller's token watcher can push the fresh value onto the live
	-- rules — the paint follows the SAME edit the snapshot does.
	local metricRuleProps: { { path: string, rule: string, prop: string, form: string } } = {}
	local function fromMetric(path: string, rule: string, prop: string, form: string)
		table.insert(metricRuleProps, { path = path, rule = rule, prop = prop, form = form })
	end

	-- ----- which slots need which chrome ----------------------------------
	local ninePlans: { [string]: any } = {}
	local stacks: { [string]: any } = {}
	local gradientSlots: { [string]: boolean } = {}
	for _, slot in chrome_slots.SLOTS do
		local plan = chrome_slots.planFor(package, slot)
		if plan ~= nil then
			ninePlans[slot] = plan
		end
		-- a LAYERED recipe (ADR-0020 R1) plans a whole ladder instead of one
		-- decoration; `planFor` returns nil for it, which is what keeps every
		-- existing caller and every flat package byte-identical
		local stack = chrome_slots.layerPlanFor(package, slot)
		if stack ~= nil then
			stacks[slot] = stack
		end
		-- a wash may never reach a value control's chrome (see SLOT_SELECTOR);
		-- `themes.define` rejects the declaration, so this is belt-and-braces
		if chrome_slots.isGradientable(slot) then
			for _, theme in package.style.themes do
				if gradientOf(theme, slot) ~= nil then
					gradientSlots[slot] = true
				end
			end
		end
	end

	-- ----- themes ---------------------------------------------------------
	local themes: { Theme } = {}
	local extraByTheme: { [string]: any } = {}
	for _, entry in package.style.themes do
		local x = effectiveExtra(entry)
		local styleLike = { colors = entry.colors, extra = x }
		extraByTheme[entry.name] = x
		local tokenSet = themeTokens(styleLike)
		-- chrome tint ladder (shared across slots — see CHROME_TINT_* above)
		tokenSet.ChromeTint = greyToken(CHROME_TINT_REST)
		tokenSet.ChromeTintHover = greyToken(CHROME_TINT_HOVER)
		tokenSet.ChromeTintPressed = greyToken(CHROME_TINT_PRESSED)
		tokenSet.ChromeTintSelected = lerp({ r = 1, g = 1, b = 1 }, entry.colors.accent, 0.35)
		-- ROLE TINTS (director review 2026-07-25: "a tint like on delete profile
		-- should tint the IMAGE, not give a random button behind it"). With the
		-- native plate suppressed under the art there is no coloured slab left to
		-- paint a role on, so the role has to reach the ART itself: `ImageColor3`
		-- multiplies the skin, and a red multiplier turns the parchment slab
		-- dangerous while keeping its grain, its torn edge and its ornament.
		--
		-- Each is lifted toward white BEFORE it multiplies: a raw danger colour
		-- multiplied into mid-tone parchment lands almost black, and a warning
		-- nobody can read is not a warning. The hover/press pair uses the same
		-- edge lerps the fill tokens use, so a destructive button's states read
		-- as one family whether it is skinned or flat. Emitted on EVERY theme,
		-- always — a `$Token` that resolves in one theme and not another is a
		-- rule that stops painting on a swap.
		local dangerColor = (select(1, dangerPair(entry.colors)))
		local dangerTint = lerp(dangerColor, WHITE, 0.3)
		tokenSet.ChromeTintDanger = dangerTint
		tokenSet.ChromeTintDangerHover = lerp(dangerTint, WHITE, 0.18)
		tokenSet.ChromeTintDangerPressed = lerp(dangerTint, BLACK, 0.18)
		-- cancel reads RECESSIVE: the resting grey pulled toward the surface, so
		-- a cancel slab sits back from its destructive neighbour
		tokenSet.ChromeTintCancel = lerp(greyToken(CHROME_TINT_REST), entry.colors.surface, 0.45)
		-- the primary action reads as the accent, lifted exactly as danger is
		tokenSet.ChromeTintAccent = lerp(entry.colors.accent, WHITE, 0.3)
		-- gradient tokens. EVERY theme carries a token for every gradient slot
		-- any theme declares: a `$Token` that resolves in one theme and not in
		-- another is a rule that stops painting on a swap, so a theme that
		-- declared nothing gets an inert flat-white ramp instead of a hole.
		for slot in gradientSlots do
			local key = "Gradient" .. pascal(slot)
			local declared = gradientOf(entry, slot)
			if declared ~= nil then
				tokenSet[key] = chrome_props.colorSeq(declared.stops)
				tokenSet[key .. "Rotation"] = { kind = "number", value = declared.rotation or 90 }
				tokenSet[key .. "Alpha"] = chrome_props.numSeq(declared.alpha or { { t = 0, v = 0 }, { t = 1, v = 0 } })
			else
				tokenSet[key] = chrome_props.colorSeq({
					{ t = 0, r = 1, g = 1, b = 1 },
					{ t = 1, r = 1, g = 1, b = 1 },
				})
				tokenSet[key .. "Rotation"] = { kind = "number", value = 0 }
				tokenSet[key .. "Alpha"] = chrome_props.numSeq({ { t = 0, v = 0 }, { t = 1, v = 0 } })
			end
		end
		table.insert(themes, {
			name = entry.name,
			tokens = tokenSet,
			contrast = gateTheme(entry.name, styleLike),
		})
	end

	local defaultTheme = o.defaultTheme or package.style.defaultTheme or themes[1].name
	local baseExtra = extraByTheme[defaultTheme] or extraByTheme[themes[1].name]
	local S = sheet_model.TAGS.surfacePrefix
	local T = sheet_model.TAGS

	-- THE FACE FOR A ROLE, authored or DERIVED (F2, 2026-08-02). `strong` and
	-- `numeral` are optional in a package, and the theme SNAPSHOT derives an
	-- unauthored one (`themePackage.deriveTypeRole`) — so the sheet has to derive
	-- it the same way or native paint would draw a face the solver did not measure,
	-- which is the whole split this channel exists to close.
	local function fontOf(role: string): RuleProp
		local entry = metrics.typography[role]
			or themePackage.deriveTypeRole(role, metrics.typography)
			or metrics.typography.body
		return { kind = "font", family = entry.font.family, weight = entry.font.weight, style = entry.font.style }
	end

	-- ----- v2 census + the pixel stamp (ADR-0020 R1/R2/R5/R9) --------------
	-- RS-A17 reads these: cost honesty is a counted number per kind, not an
	-- impression. A flat package leaves every ART number at zero; the one number
	-- it does not is `suppressionRules`, which carries the value family's
	-- pre-armed 4x3 baseline (director round 5 — see the OWN_PAINT loop in the
	-- chrome section). Counted rather than hidden: it is twelve real rules in
	-- every sheet, and a census that quietly excused its own baseline would be
	-- the impression this table exists to replace.
	local census: any = {
		imageRules = 0,
		pixelatedRules = 0,
		suppressionRules = 0,
		variantRules = 0,
		variantAssets = 0,
		layerRules = 0,
		layers = 0,
		layersPerKind = {},
		layeredSlots = {},
		overhang = {},
	}
	local pixelUnit = themePackage.pixelUnitOf(package)
	-- rs-m5 generation rule 1: EVERY image-bearing rule a pixel package emits
	-- carries ResampleMode=Pixelated. Censused on both sides so a missed rule is
	-- a counted defect (`pixelatedRules == imageRules`) rather than a visual hunt.
	-- The engine ENUM is `ResamplerMode`; the PROPERTY is `ResampleMode`.
	local PIXELATED: RuleProp = { kind = "enum", enum = "ResamplerMode", item = "Pixelated" }
	local function imageProps(props: { [string]: RuleProp }): { [string]: RuleProp }
		census.imageRules += 1
		if pixelUnit ~= nil then
			props.ResampleMode = PIXELATED
			census.pixelatedRules += 1
		end
		return props
	end
	-- distinct art a package reaches for across states, counted once per content
	-- id (the preload seam's cost, ADR-0020 R2)
	local variantSeen: { [string]: boolean } = {}
	local function noteVariantAsset(contentId: string)
		if not variantSeen[contentId] then
			variantSeen[contentId] = true
			census.variantAssets += 1
		end
	end

	-- ----- the ordered groups ---------------------------------------------
	local groups: { [string]: { Rule } } = {}
	for _, name in sheet_model.RULE_GROUPS do
		groups[name] = {}
	end
	local function emit(group: string, rule: Rule)
		rule.group = group
		table.insert(groups[group], rule)
	end

	-- ----- per-state ART (ADR-0020 R2) -------------------------------------
	-- One state, one rule, carrying `Image` and nothing else. The per-state TINT
	-- rules are separate rules on separate props, so they still apply on top —
	-- which is exactly the ADR semantics: an unstated state falls back to the
	-- default art WITH its tint, and a supplied `disabled` art still gets the
	-- disabled transparency treatment (the accessibility floor is not a variant's
	-- to remove). The decoration is Active=false and reports no GuiState of its
	-- own, so every selector reads the state from the PARENT through the child
	-- combinator, exactly as the tint rules do.
	--
	-- `error` is the one state with no engine pseudo and no renderer tag today —
	-- it keys on `luau-state-error`, which `classifyTags` emits when a control
	-- publishes it. P3's control wiring is what makes that tag appear; until
	-- then the rule is emitted and matches nothing, which is visible in the
	-- census rather than hidden.
	local VARIANT_RULES: { [string]: { group: string, prefix: string } } = {
		hover = { group = "hover", prefix = `.{T.interactive}.{T.pointerLive}:Hover > ` },
		pressed = { group = "press", prefix = `.{T.interactive}:Press > ` },
		selected = { group = "chrome", prefix = `.{T.selected} > ` },
		disabled = { group = "disabled", prefix = ":NonInteractable > " },
		error = { group = "chrome", prefix = `.{chrome_slots.TAGS.stateError} > ` },
	}

	-- ON/OFF IS A VALUE, NOT A GuiState (ADR-0020 R3 cap 10). Every other variant
	-- state rides an engine pseudo or a tag the renderer already emits; a switch's
	-- ON state is the control's VALUE, and no rule can see a value — which is
	-- exactly why `togglePalette` stayed a bespoke colour write. The art therefore
	-- keys on a tag the adapter flips beside those same colour writes, and the
	-- toggle slots read `selected` as that tag instead of the row-selection one.
	local SLOT_SELECTED_TAG: { [string]: string } =
		{ toggleTrack = chrome_slots.TOGGLE_ON_TAG, toggleKnob = chrome_slots.TOGGLE_ON_TAG }

	local function emitVariantArt(baseName: string, tag: string, variants: any, selectedTag: string?)
		if variants == nil then
			return
		end
		for _, state in themePackage.VARIANT_STATES do
			local entry = variants[state]
			if entry == nil then
				continue
			end
			if state == "default" then
				continue -- the resting rule already paints it
			end
			-- counted per DISTINCT non-default asset: this is the extra art a
			-- per-state map costs the preload seam, which is the number RS-A17
			-- wants and the base art is not part of
			noteVariantAsset(entry.contentId)
			local spec = VARIANT_RULES[state]
			local prefix = if state == "selected" and selectedTag ~= nil then `.{selectedTag} > ` else spec.prefix
			emit(spec.group, {
				name = `{baseName} {state} art`,
				selector = `{prefix}.{tag}`,
				props = imageProps({ Image = entry.contentId }),
			})
			census.variantRules += 1
		end
	end

	-- THE IMAGE IS THE ELEMENT (ADR-0020 R9, extending the Step 3.5 machinery).
	-- Before art can BE the control, the control's native plate has to stop being
	-- drawn under it: fill, ::UICorner radius and ::UIStroke hairline all go to
	-- nothing on the DECORATED NODE. Emitted per skinned slot — nine-slice and
	-- layered alike — never globally, so a slot the package paints natively keeps
	-- every bit of its Studio-Neutral chrome.
	--
	-- ONCE PER SLOT. A RULE NAME IS IDENTITY (see the base group below), so the
	-- same slot reaching this twice — a value slot that is both pre-armed below
	-- and declared by a recipe — must produce ONE rule, not a duplicate pair the
	-- Style Editor lists twice and `setRuleProperty` picks between at random.
	local suppressed: { [string]: boolean } = {}
	local function emitSuppression(slot: string)
		if suppressed[slot] then
			return
		end
		suppressed[slot] = true
		-- the same three rules `build`'s base seed pre-arms, from the same shared
		-- emitter (RS-A16-D4): a package sheet and the base sheet must suppress a
		-- skinned value slot identically or a rung-2 override reads differently
		-- depending on whether a package happens to be installed
		emitSlotSuppression(slot, function(rule: Rule)
			emit("chrome", rule)
		end)
		census.suppressionRules += 3
	end

	-- base: class defaults + text/font defaults. As in `build`, the
	-- BackgroundTransparency defaults are RULES rather than adapter writes,
	-- because an explicit write at create would permanently defeat every
	-- surface rule (spike m10).
	-- A RULE NAME IS IDENTITY, not a label. It is what the Style Editor lists,
	-- what a designer's saved edit is keyed to, and what `setRuleProperty` looks
	-- up — so the package builder must speak the SAME vocabulary the legacy
	-- builder taught (`Label default`, never `TextLabel default`). A renamed rule
	-- reads as a deleted rule plus a new one: the designer's edit is orphaned and
	-- every metric push silently misses.
	for _, class in { "Frame", "TextLabel", "TextButton", "ImageLabel", "TextBox", "ScrollingFrame", "CanvasGroup" } do
		emit("base", {
			name = `{CLASS_DEFAULT_NAME[class]} default`,
			selector = class,
			props = { BackgroundTransparency = num(1) },
		})
	end
	-- ...and the tinted fill, in the SAME cascade position the legacy builder gives
	-- it (see that rule, and TAGS.tintFill). A floor only one builder emits is a
	-- floor that vanishes the moment a player picks a package — RS-A16-D4's defect,
	-- one rule over.
	emit("base", { name = "Tint fill", selector = `.{T.tintFill}`, props = { BackgroundTransparency = num(0) } })
	emit("base", {
		name = "Text default",
		selector = "TextLabel",
		props = { TextColor3 = "$Content", FontFace = fontOf("body") },
	})
	-- A FONT is a metric-derived rule prop exactly like a corner radius is: the
	-- descriptor is baked into the rule as a literal Font, so a designer's
	-- Type_*_font edit re-keyed MEASUREMENT while the paint kept the seeded
	-- face — the solver reserving one family and the engine drawing another,
	-- which is the split this stage exists to close.
	fromMetric("type.body.font", "Text default", "FontFace", "font")
	emit("base", {
		name = "Button text default",
		selector = "TextButton",
		props = { TextColor3 = "$Content", FontFace = fontOf("control") },
	})
	fromMetric("type.control.font", "Button text default", "FontFace", "font")
	emit("base", {
		name = "Field text default",
		selector = "TextBox",
		props = {
			TextColor3 = "$Content",
			PlaceholderColor3 = "$ContentSecondary",
			FontFace = fontOf("control"),
		},
	})
	fromMetric("type.control.font", "Field text default", "FontFace", "font")
	-- THE PER-ROLE FACES (F2, 2026-08-02). A node's typography role reaches native
	-- paint as `luau-type-<role>`; this is the rule that gives that tag its face,
	-- from the SAME `type.<role>.font` the solver measured with. Emitted for all
	-- eight roles, class defaults included, so a role always beats the class rule
	-- it sits on (a `strong` Text inside a TextButton, a `body` Button label) — and
	-- inert wherever the package's ramp shares one face, which is every flat
	-- reference package and Studio Neutral.
	--
	-- The live-edit push (`fromMetric`) is registered only for an AUTHORED role: a
	-- derived one has no `type.<role>.font` token attribute for the watcher to read.
	for _, role in themePackage.TYPE_ROLES do
		local ruleName = `Type — {role}`
		emit("base", { name = ruleName, selector = `.{T.typePrefix}{role}`, props = { FontFace = fontOf(role) } })
		if metrics.typography[role] ~= nil then
			fromMetric(`type.{role}.font`, ruleName, "FontFace", "font")
		end
	end
	emit("base", {
		name = "Scroll bar",
		selector = "ScrollingFrame",
		props = { ScrollBarImageColor3 = "$ContentSecondary" },
	})

	-- surfaces (+ the phantom corner/stroke modifiers)
	local hairlineT = num(baseExtra.hairlineOpacity)
	local hairlineW = num(metrics.strokes.hairline)
	emit("surfaces", {
		name = "Base surface",
		selector = "." .. S .. "base",
		props = { BackgroundColor3 = "$Surface", BackgroundTransparency = num(0) },
	})
	emit("surfaces", {
		name = "Raised panel",
		selector = "." .. S .. "raised",
		props = { BackgroundColor3 = "$SurfaceStrong", BackgroundTransparency = num(0) },
	})
	emit("surfaces", {
		name = "Raised panel — corner",
		selector = "." .. S .. "raised::UICorner",
		props = { CornerRadius = udim(0, metrics.radii.panel) },
	})
	fromMetric("radii.panel", "Raised panel — corner", "CornerRadius", "udimOffset")
	emit("surfaces", {
		name = "Raised panel — hairline",
		selector = "." .. S .. "raised::UIStroke",
		props = {
			Color = "$Hairline",
			Transparency = hairlineT,
			Thickness = hairlineW,
			ApplyStrokeMode = STROKE_BORDER,
		},
	})
	fromMetric("strokes.hairline", "Raised panel — hairline", "Thickness", "number")
	emit("surfaces", {
		name = "Control fill",
		selector = "." .. S .. "control",
		props = { BackgroundColor3 = "$Control", BackgroundTransparency = num(0) },
	})
	emit("surfaces", {
		name = "Control — corner",
		selector = "." .. S .. "control::UICorner",
		props = { CornerRadius = udim(0, metrics.radii.control) },
	})
	fromMetric("radii.control", "Control — corner", "CornerRadius", "udimOffset")
	emit("surfaces", {
		name = "Field — outline",
		selector = "TextBox." .. S .. "control::UIStroke",
		props = {
			Color = "$Hairline",
			Transparency = hairlineT,
			Thickness = hairlineW,
			ApplyStrokeMode = STROKE_BORDER,
		},
	})
	fromMetric("strokes.hairline", "Field — outline", "Thickness", "number")
	emit("surfaces", {
		name = "Chip",
		selector = "." .. S .. "chip",
		props = { BackgroundColor3 = "$Control", BackgroundTransparency = num(0) },
	})
	emit("surfaces", {
		name = "Chip — corner",
		selector = "." .. S .. "chip::UICorner",
		props = { CornerRadius = udim(0, metrics.radii.control) },
	})
	fromMetric("radii.control", "Chip — corner", "CornerRadius", "udimOffset")
	emit("surfaces", {
		name = "Chip — outline",
		selector = "." .. S .. "chip::UIStroke",
		props = {
			Color = "$Hairline",
			Transparency = hairlineT,
			Thickness = hairlineW,
			ApplyStrokeMode = STROKE_BORDER,
		},
	})
	fromMetric("strokes.hairline", "Chip — outline", "Thickness", "number")
	emit("surfaces", {
		name = "Badge",
		selector = "." .. S .. "badge",
		props = { BackgroundColor3 = "$SurfaceStrong", BackgroundTransparency = num(0) },
	})
	emit("surfaces", {
		name = "Badge — circle",
		selector = "." .. S .. "badge::UICorner",
		props = { CornerRadius = udim(0.5, 0) },
	})
	emit("surfaces", {
		name = "Primary button",
		selector = "." .. S .. "accent",
		props = { BackgroundColor3 = "$Accent", BackgroundTransparency = num(0) },
	})
	-- see the base seed: the accent surface REPLACES the chip/control one, so it
	-- has to carry its own corner or a selected button goes square (round 11)
	emit("surfaces", {
		name = "Primary button — corner",
		selector = "." .. S .. "accent::UICorner",
		props = { CornerRadius = udim(0, metrics.radii.control) },
	})
	fromMetric("radii.control", "Primary button — corner", "CornerRadius", "udimOffset")
	emit("surfaces", {
		name = "Primary button label",
		selector = "TextButton." .. S .. "accent",
		props = { TextColor3 = "$OnAccent" },
	})
	-- VALUE-CONTROL CHROME: ITS OWN PAINT (director follow-up 2026-07-25).
	--
	-- "in glossy_shadows, the slider button should be solid." The thumb used to
	-- declare `surface = "raised"` to get a fill, which subscribed it to the
	-- whole PANEL treatment — including Glossy's panel gradient, whose alpha made
	-- it translucent so the accent fill behind it read through. A rail is not a
	-- button and a thumb is not a panel.
	--
	-- These rules are the replacement: keyed on the hint tag (present whether or
	-- not the package skins the slot), SOLID by construction, and drawing their
	-- colour from the SAME `SLOT_FILL_TOKEN` map the asset-failure fallback uses,
	-- so a slot's flat appearance is one decision rather than two that drift.
	-- Emitted for every package including the flat ones — and, since RS-A16-D4,
	-- by `build`'s base seed through this same shared emitter, because a value
	-- control has to be visible under Studio Neutral too and that is the one path
	-- this loop used not to reach.
	-- the disc's chrome, in the group right after the surfaces whose corners it
	-- replaces and right before `chrome`, whose skinned-slot suppression must
	-- still beat it (see emitShapeChrome)
	emitShapeChrome(metrics, hairlineT, hairlineW, function(rule: Rule)
		emit("roles", rule)
	end, fromMetric)
	for _, slot in chrome_slots.OWN_PAINT_SLOTS do
		emitOwnSlotPaint(slot, metrics, hairlineT, hairlineW, function(rule: Rule)
			emit("surfaces", rule)
		end, fromMetric)
	end
	emit("surfaces", {
		name = sheet_model.SCRIM_RULE,
		selector = "." .. S .. "scrim",
		props = { BackgroundColor3 = "$Surface", BackgroundTransparency = num(baseExtra.scrimOpacity) },
	})

	-- roles
	emit("roles", {
		name = "Divider",
		selector = ".luau-divider",
		props = { BackgroundColor3 = "$Hairline", BackgroundTransparency = num(0) },
	})
	emit(
		"roles",
		{ name = "Secondary text", selector = ".luau-role-secondary", props = { TextColor3 = "$ContentSecondary" } }
	)
	emit("roles", { name = "Strong text", selector = ".luau-role-strong", props = { TextColor3 = "$ContentStrong" } })
	emit("roles", {
		name = "Grip focus",
		selector = ".luau-grip-focus",
		props = { BackgroundColor3 = "$Accent", BackgroundTransparency = num(0) },
	})
	emit(
		"roles",
		{ name = "Toggle chrome", selector = ".luau-toggle-chrome", props = { BackgroundTransparency = num(0) } }
	)
	emit("roles", {
		name = "Selected row",
		selector = "TextButton." .. T.selected,
		-- see the base seed: one token, one decision, both builders
		props = { BackgroundColor3 = "$ControlSelected", TextColor3 = "$OnSelected" },
		transitions = { BackgroundColor3 = "fast" },
	})
	emit("roles", {
		name = "Destructive button",
		selector = ".luau-role-destructive",
		props = { BackgroundColor3 = "$Danger", TextColor3 = "$OnDanger" },
	})
	emit("roles", {
		name = "Cancel button",
		selector = ".luau-role-cancel",
		props = { BackgroundColor3 = "$Surface", TextColor3 = "$ContentSecondary" },
	})

	-- A SKINNED VALUE SLOT SUPPRESSES ITS OWN PAINT TOO (director round 5,
	-- 2026-07-25). The three `Slot — <slot>` rules above are the ACCESSIBILITY
	-- floor for a value control nothing else paints — and a floor is for a node
	-- with no art on it. The moment a node carries `luau-skinned-<slot>` the art
	-- IS the element (R9), and a solid slab behind it shows through every
	-- transparent pixel the art has: measured live on the rung-2 slider thumb,
	-- whose view-supplied picture sat inside a ring of its own `$SurfaceStrong`
	-- plate (`GetStyled` 0 -> 1 across the fix; capture
	-- `RS-DIR5_zoom6x_rung2-thumb_before-after.png`).
	--
	-- PRE-ARMED, not recipe-driven, which is the whole point. A node earns the
	-- skinned tag from THREE routes — a package nine-slice recipe, a layer stack,
	-- and the rung-2 per-view override — and only the first two run through the
	-- loops below. Under `glossy-touch` (no `sliderThumb` recipe at all) a view
	-- that supplied its own thumb image got the tag and no rule to match it.
	-- Emitting here means the rule exists for every package, flat ones included,
	-- and matches exactly when a node is actually skinned.
	--
	-- The GRADIENT ban is untouched and still a compile error: the hazard the
	-- Step 3.5 ruling was written for was a native wash riding value chrome, not
	-- an author's own art. An unskinned slot carries no skinned tag, so its solid
	-- paint is byte-identical to before.
	for _, slot in chrome_slots.OWN_PAINT_SLOTS do
		emitSuppression(slot)
	end

	-- chrome: gradients first (they paint the node itself), then the
	-- nine-slice decoration child, then its fallback and its selected tint
	for _, slot in chrome_slots.SLOTS do
		if gradientSlots[slot] then
			local key = "Gradient" .. pascal(slot)
			emit("chrome", {
				name = `Gradient — {slot}`,
				selector = SLOT_SELECTOR[slot] .. "::UIGradient",
				props = {
					Color = "$" .. key,
					Rotation = "$" .. key .. "Rotation",
					Transparency = "$" .. key .. "Alpha",
				},
			})
		end
	end
	for _, slot in chrome_slots.SLOTS do
		local plan = ninePlans[slot]
		if plan == nil then
			continue
		end
		local asset = package.assets[plan.assetName]
		local restingTint = "$ChromeTint"
		if type(asset.tintRole) == "string" then
			local token = TINT_ROLE_TOKEN[asset.tintRole]
			assert(
				token ~= nil,
				`sheet_model.buildPackage: asset '{plan.assetName}' names tintRole '{asset.tintRole}', `
					.. "which is not a palette role — a tint that resolves to nothing paints the art unchanged "
					.. "and is invisible until a device shows it"
			)
			restingTint = token
		end
		-- THE IMAGE IS THE BUTTON (director fix round; ADR-0020 R9 generalizes it
		-- to every image-bearing slot and to layer stacks). Sits in the chrome
		-- group, i.e. AFTER every surface rule it has to beat and before the
		-- interaction states (which only change colour, so an invisible plate
		-- stays invisible through hover and press).
		emitSuppression(slot)
		-- WHOLE IMAGE vs NINE SLICE. A sliced recipe owns all six image
		-- properties; a whole-image one (a thumb, a counter seal) owns four and
		-- must NOT name SliceCenter/SliceScale — a slice centre on a 28px token
		-- smears its one centre pixel across the whole middle.
		local restProps: { [string]: RuleProp } = {
			Image = plan.contentId,
			ScaleType = {
				kind = "enum",
				enum = "ScaleType",
				item = if plan.sliced then "Slice" else "Stretch",
			},
			ImageColor3 = restingTint,
			ImageTransparency = num(0),
		}
		if plan.sliced then
			restProps.SliceCenter = plan.sliceCenter
			restProps.SliceScale = num(plan.sliceScale)
		end
		emit("chrome", {
			name = `Chrome — {slot}`,
			selector = "." .. plan.tag,
			props = imageProps(restProps),
		})
		emitVariantArt(`Chrome — {slot}`, plan.tag, plan.variants, SLOT_SELECTED_TAG[slot])
		-- PER-END CAP ART (ADR-0020 R3). One recipe paints both ends; an end that
		-- named its own asset gets a second tag whose rule lands later in insertion
		-- order and therefore wins on that one instance — the per-corner idiom.
		if slot == "barCap" then
			local recipe = package.chrome.barCap
			for _, which in chrome_slots.BAR_ENDS do
				local named = chrome_slots.barCapAssetOf(recipe, which)
				if named == nil or named == plan.assetName then
					continue
				end
				local capAsset = package.assets[named]
				assert(
					type(capAsset) == "table",
					`sheet_model.buildPackage: chrome.barCap names cap asset '{named}', `
						.. "which the package does not declare"
				)
				emit("chrome", {
					name = `Chrome — barCap {which}`,
					selector = `.{chrome_slots.barCapTagFor(which)}`,
					props = imageProps({ Image = capAsset.contentId }),
				})
			end
		end
		-- the declared native fallback: tag-driven, so a failed asset repaints
		-- without touching hit geometry, focus or state (ADR-0019 §5)
		emit("chrome", {
			name = `Chrome — {slot} fallback`,
			selector = `.{plan.tag}.{chrome_slots.TAGS.fallback}`,
			props = {
				BackgroundColor3 = SLOT_FILL_TOKEN[slot],
				BackgroundTransparency = num(0),
			},
		})
		-- THE HIDE IS A SECOND TAG (RS-A16-D5). The fill above lands on every art
		-- instance of a fallen-back slot; the hide lands only on the ones whose own
		-- asset is NOT the failed one, because `ImageTransparency = 1` is the
		-- engine's "do not decode" signal and using it on the condemned art
		-- destroyed the only instrument that could report its recovery. Emitted
		-- after the fill so insertion order still puts it above the resting art.
		emit("chrome", {
			name = `Chrome — {slot} fallback hide`,
			selector = `.{plan.tag}.{chrome_slots.TAGS.mute}`,
			props = { ImageTransparency = num(1) },
		})
		emit("chrome", {
			name = `Chrome — {slot} fallback corner`,
			selector = `.{plan.tag}.{chrome_slots.TAGS.fallback}::UICorner`,
			props = {
				CornerRadius = if SLOT_ROUND[slot] then udim(0.5, 0) else udim(0, slotRadius(metrics, slot)),
			},
		})
		if slot ~= "divider" and slot ~= "scrollbar" and not SLOT_ROUND[slot] then
			fromMetric(
				if slot == "panel" then "radii.panel" else "radii.control",
				`Chrome — {slot} fallback corner`,
				"CornerRadius",
				"udimOffset"
			)
		end
		if SLOT_STROKED[slot] then
			emit("chrome", {
				name = `Chrome — {slot} fallback hairline`,
				selector = `.{plan.tag}.{chrome_slots.TAGS.fallback}::UIStroke`,
				props = {
					Color = "$Hairline",
					Transparency = hairlineT,
					Thickness = hairlineW,
					ApplyStrokeMode = STROKE_BORDER,
				},
			})
			fromMetric("strokes.hairline", `Chrome — {slot} fallback hairline`, "Thickness", "number")
		end
		-- SELECTED is a tint over the base image. A package that wants selection
		-- to change the PICTURE declares a `selected` variant (ADR-0020 R2); the
		-- tint then rides on top of that art, so both idioms compose.
		emit("chrome", {
			name = `Chrome — {slot} selected`,
			selector = `.{SLOT_SELECTED_TAG[slot] or T.selected} > .{plan.tag}`,
			props = { ImageColor3 = "$ChromeTintSelected" },
			transitions = { ImageColor3 = "fast" },
		})
	end

	-- ----- LAYER STACKS (ADR-0020 R1) --------------------------------------
	-- Z-order IS array order, and the adapter assigns ZIndex 1..N from it. Every
	-- paint property here is RULE-owned from birth: rs-m2 measured that a value
	-- written on the instance BEFORE it joins the styled tree survives and
	-- permanently defeats a rule that only starts matching later, which is
	-- precisely what a per-state art swap is.
	for _, slot in chrome_slots.SLOTS do
		local stack = stacks[slot]
		if stack == nil then
			continue
		end
		table.insert(census.layeredSlots, slot)
		emitSuppression(slot)
		if chrome_slots.hasOverhang(stack.overhang) then
			census.overhang[slot] = stack.overhang
		end
		for _, layer in stack.layers do
			census.layers += 1
			census.layersPerKind[layer.kind] = (census.layersPerKind[layer.kind] or 0) + 1
			local asset = package.assets[layer.assetName]
			local restingTint = "$ChromeTint"
			if type(asset.tintRole) == "string" then
				local token = TINT_ROLE_TOKEN[asset.tintRole]
				assert(
					token ~= nil,
					`sheet_model.buildPackage: asset '{layer.assetName}' names tintRole '{asset.tintRole}', `
						.. "which is not a palette role — a tint that resolves to nothing paints the art unchanged "
						.. "and is invisible until a device shows it"
				)
				restingTint = token
			end
			local props: { [string]: RuleProp } = {
				Image = layer.contentId,
				ScaleType = { kind = "enum", enum = "ScaleType", item = layer.scaleType },
				ImageColor3 = restingTint,
				ImageTransparency = num(0),
			}
			if layer.sliced then
				props.SliceCenter = layer.sliceCenter
				props.SliceScale = num(layer.sliceScale)
			end
			if layer.scaleType == "Tile" then
				-- rs-m1: offset components are PIXELS, scale components are a
				-- fraction of the label. The schema authors px, so the rule does.
				local size = layer.geometry.tileSize
				local repeatPx = layer.geometry.tile
				local w = if type(size) == "table" then size.w else repeatPx
				local h = if type(size) == "table" then size.h else repeatPx
				props.TileSize = chrome_props.udim2(0, w or 0, 0, h or 0)
			end
			local baseName = `Chrome — {slot} L{layer.index} {layer.kind}`
			emit("chrome", { name = baseName, selector = `.{layer.tag}`, props = imageProps(props) })
			census.layerRules += 1
			emitVariantArt(baseName, layer.tag, layer.variants, SLOT_SELECTED_TAG[slot])
			-- PER-CORNER ORNAMENTS. The layer tag paints all four; a corner that
			-- declared its own art gets a second tag whose rule lands later in
			-- insertion order and therefore wins on that one instance.
			if layer.kind == "corners" then
				for _, corner in chrome_slots.CORNER_FIELDS do
					local variants = layer.cornerVariants[corner]
					if variants == nil then
						continue
					end
					local cornerName = `{baseName} {corner}`
					local cornerTag = chrome_slots.cornerTagFor(slot, layer.index, corner)
					emit("chrome", {
						name = cornerName,
						selector = `.{cornerTag}`,
						props = imageProps({ Image = variants.default.contentId }),
					})
					census.layerRules += 1
					emitVariantArt(cornerName, cornerTag, variants, SLOT_SELECTED_TAG[slot])
				end
			end
			-- the declared native fallback. The ladder hides; the BACK layer carries
			-- the native paint, because a stack that half-paints reads as a broken
			-- skin rather than a degraded one. THE HIDE IS THE SECOND TAG
			-- (RS-A16-D5): "hide the healthy siblings" is exactly what this rule is
			-- for, and the broken layer — which draws nothing anyway — keeps its art
			-- rules so its `IsLoaded` can still report a recovery.
			local fallbackProps: { [string]: RuleProp } = {}
			if layer.index == 1 then
				fallbackProps.BackgroundColor3 = SLOT_FILL_TOKEN[slot]
				fallbackProps.BackgroundTransparency = num(0)
			end
			if next(fallbackProps) ~= nil then
				emit("chrome", {
					name = `{baseName} fallback`,
					selector = `.{layer.tag}.{chrome_slots.TAGS.fallback}`,
					props = fallbackProps,
				})
			end
			emit("chrome", {
				name = `{baseName} fallback hide`,
				selector = `.{layer.tag}.{chrome_slots.TAGS.mute}`,
				props = { ImageTransparency = num(1) },
			})
			if layer.index == 1 then
				emit("chrome", {
					name = `{baseName} fallback corner`,
					selector = `.{layer.tag}.{chrome_slots.TAGS.fallback}::UICorner`,
					props = {
						CornerRadius = if SLOT_ROUND[slot] then udim(0.5, 0) else udim(0, slotRadius(metrics, slot)),
					},
				})
			end
			emit("chrome", {
				name = `{baseName} selected`,
				selector = `.{SLOT_SELECTED_TAG[slot] or T.selected} > .{layer.tag}`,
				props = { ImageColor3 = "$ChromeTintSelected" },
				transitions = { ImageColor3 = "fast" },
			})
			-- ONE PARENT TAG YIELDS THE WHOLE STACK (rs-m2). Today's only user is
			-- the TextBox editing yield, which has to reveal the engine caret
			-- drawn at the parent layer — with N layers over it, per-layer tagging
			-- would be N tag writes for one decision.
			if slot == "field" then
				emit("chrome", {
					name = `{baseName} editing`,
					selector = `.{chrome_slots.TAGS.stackYield} > .{layer.tag}`,
					props = { ImageTransparency = num(1), BackgroundTransparency = num(1) },
				})
			end
		end
	end
	-- SEMANTIC ROLE TINTS ON THE ART (director fix round; see the ChromeTint*
	-- role tokens above). These sit AFTER the resting `Chrome — control` rule so
	-- they own the resting appearance of a roled button, and before the
	-- interaction states, which layer on top exactly as they do for a flat fill.
	-- Only the `control` slot carries them: a role is a property of an
	-- interactive control, and painting a panel's art red because a descendant
	-- is destructive would be a bug, not a theme.
	-- the control slot's paint surface: one decoration tag, or EVERY layer of a
	-- layered control (a role has to reach whatever art is actually drawn, and a
	-- stack whose frame stayed neutral while its fill turned red is a worse
	-- answer than either)
	local controlTags: { string } = {}
	if ninePlans.control ~= nil then
		table.insert(controlTags, ninePlans.control.tag)
	end
	if stacks.control ~= nil then
		for _, layer in stacks.control.layers do
			table.insert(controlTags, layer.tag)
		end
	end
	for index, controlTag in controlTags do
		local suffix = if #controlTags > 1 then ` L{index}` else ""
		emit("chrome", {
			name = `Chrome role — destructive{suffix}`,
			selector = `.luau-role-destructive > .{controlTag}`,
			props = { ImageColor3 = "$ChromeTintDanger" },
			transitions = { ImageColor3 = "fast" },
		})
		emit("chrome", {
			name = `Chrome role — cancel{suffix}`,
			selector = `.luau-role-cancel > .{controlTag}`,
			props = { ImageColor3 = "$ChromeTintCancel" },
			transitions = { ImageColor3 = "fast" },
		})
		emit("chrome", {
			name = `Chrome role — accent{suffix}`,
			selector = `.{S}accent > .{controlTag}`,
			props = { ImageColor3 = "$ChromeTintAccent" },
			transitions = { ImageColor3 = "fast" },
		})
	end
	-- the chrome TEXT LIFT (TP-M8, ADR-0019 integration rulings): a text-bearing
	-- node under nine-slice chrome paints its label on a managed
	-- `.luau-chrome-text` child ABOVE the decoration (under Sibling z-behavior a
	-- child covers the parent's own engine-drawn text at any ZIndex). The lifted
	-- label is a TextLabel, so "Text default" already gives it $Content + the
	-- body font; these rules add the control-role font and the parent-tag
	-- variants via child combinators (selector validity measured in TP-M8).
	-- Emitted only when a text-bearing slot is actually skinned — flat themes
	-- carry none of this.
	-- SELECTION counts: a selectable row is a TextButton, so a selection-only skin
	-- lifts labels exactly like a control skin does. Leaving it out of the
	-- condition produced lifted labels with NO rules to paint them — the label
	-- inherited only "Text default" and every parent-role variant went missing.
	-- BADGE counts too (director fix round): a badge is a TextLabel, its count
	-- paints under the seal without a lift, and "3" was the exact value the
	-- director could not read.
	if
		ninePlans.control ~= nil
		or ninePlans.field ~= nil
		or ninePlans.selection ~= nil
		or ninePlans.badge ~= nil
		-- a LAYERED text-bearing slot lifts its label for exactly the same
		-- reason, and with a stack over it the reason is stronger
		or stacks.control ~= nil
		or stacks.field ~= nil
		or stacks.selection ~= nil
		or stacks.badge ~= nil
	then
		local liftTag = chrome_slots.TAGS.text
		-- THE SELECTED PLATE'S LABEL (director round 8). Emitted FIRST among the
		-- lift's colour rules, and deliberately: on the ART, a role/surface tint
		-- (`Chrome role — accent`, `… destructive`, `… cancel`) is emitted after
		-- the selected tint and therefore wins the picture, so it has to win the
		-- label too. `$OnSelected` is the theme's own decision (see
		-- `selectedContentColor`): $Content wherever it still clears the 4.5
		-- floor against the theme's selected surface, $OnAccent where it does not.
		emit("chrome", {
			name = "Chrome text — selected",
			selector = `.{T.selected} > .{liftTag}`,
			props = { TextColor3 = "$OnSelected" },
		})
		emit("chrome", {
			name = "Chrome text — button font",
			selector = `TextButton > .{liftTag}`,
			props = { FontFace = fontOf("control") },
		})
		fromMetric("type.control.font", "Chrome text — button font", "FontFace", "font")
		emit("chrome", {
			name = "Chrome text — field font",
			selector = `TextBox > .{liftTag}`,
			props = { FontFace = fontOf("control") },
		})
		fromMetric("type.control.font", "Chrome text — field font", "FontFace", "font")
		emit("chrome", {
			name = "Chrome text — accent",
			selector = `.{S}accent > .{liftTag}`,
			props = { TextColor3 = "$OnAccent" },
		})
		emit("chrome", {
			name = "Chrome text — destructive",
			selector = `.luau-role-destructive > .{liftTag}`,
			props = { TextColor3 = "$OnDanger" },
		})
		emit("chrome", {
			name = "Chrome text — cancel",
			selector = `.luau-role-cancel > .{liftTag}`,
			props = { TextColor3 = "$ContentSecondary" },
		})
		emit("chrome", {
			name = "Chrome text — secondary",
			selector = `.{liftTag}.luau-role-secondary`,
			props = { TextColor3 = "$ContentSecondary" },
		})
		-- The two role tags the RENDERER puts on the PARENT (classifyTags:
		-- `strong` for heading-and-above text, `roleSecondary` for the secondary
		-- role). Their unlifted counterparts — "Strong text"/"Secondary text" —
		-- match the parent node, whose own text is hidden under the decoration, so
		-- without these the lifted label ignored the role entirely and every
		-- skinned heading painted plain $Content.
		emit("chrome", {
			name = "Chrome text — strong",
			selector = `.luau-role-strong > .{liftTag}`,
			props = { TextColor3 = "$ContentStrong" },
		})
		emit("chrome", {
			name = "Chrome text — parent secondary",
			selector = `.luau-role-secondary > .{liftTag}`,
			props = { TextColor3 = "$ContentSecondary" },
		})
		emit("chrome", {
			name = "Chrome text — disabled button",
			selector = `TextButton:NonInteractable > .{liftTag}`,
			props = { TextTransparency = num(baseExtra.disabledContentOpacity) },
		})
		emit("chrome", {
			name = "Chrome text — disabled field",
			selector = `TextBox:NonInteractable > .{liftTag}`,
			props = { TextTransparency = num(baseExtra.disabledContentOpacity) },
		})
	end
	if ninePlans.field ~= nil then
		-- a TextBox YIELDS its chrome while editing: the engine caret is drawn
		-- at the parent layer and must be visible, so the decoration flattens to
		-- the native fill (same shape as the asset-failure fallback) while the
		-- adapter's editing tag is present
		-- FULL yield, not a repaint. The decoration is a CHILD, and under `Sibling`
		-- z-behavior any opaque child draws over its parent's engine text and
		-- caret — so painting the native fill here (BackgroundTransparency 0) hid
		-- exactly what the yield exists to reveal. The decoration goes completely
		-- transparent instead and the TextBox's own sheet-owned fill
		-- ("Control fill" / "Field — outline") is what shows while editing.
		emit("chrome", {
			name = "Chrome — field editing",
			selector = `.{ninePlans.field.tag}.{chrome_slots.TAGS.editing}`,
			props = {
				ImageTransparency = num(1),
				BackgroundTransparency = num(1),
			},
		})
	end
	-- ...AND THE NODE UNDERNEATH HAS TO PAINT AGAIN (director round 10, found
	-- live 2026-07-26 on a phone: "when I tap the filter field there's no
	-- background").
	--
	-- The yield above and `emitSlotSuppression` were each right and together
	-- wrong. Suppression turns the native plate OFF whenever art covers a node,
	-- because the art is meant to BE the surface. The yield turns the art off
	-- while the engine draws its caret at the parent layer. Both fire at once on
	-- a focused skinned field, and the comment above — "the TextBox's own
	-- sheet-owned fill is what shows while editing" — described a fill that
	-- `.luau-skinned-field` had already switched off. Nothing painted: bare text
	-- on the page, no field at all, self-healing on blur, which is exactly what
	-- the device capture shows.
	--
	-- Two rules, keyed on BOTH tags, so they can only ever match a skinned field
	-- that is currently yielding — and emitted only when the package actually
	-- skins `field`, because a flat package must emit NO chrome rules at all.
	-- Emitted last, and the cascade is Priority-then-insertion-order with no
	-- specificity (native-stylesheets), so being last is what makes them win over
	-- the suppression they are undoing.
	if ninePlans.field ~= nil or stacks.field ~= nil then
		emit("chrome", {
			name = "Chrome — field editing, own fill",
			selector = `.{chrome_slots.TAGS.stackYield}.{chrome_slots.skinnedTagFor("field")}`,
			props = { BackgroundColor3 = "$Control", BackgroundTransparency = num(0) },
		})
		emit("chrome", {
			name = "Chrome — field editing, own corner",
			selector = `.{chrome_slots.TAGS.stackYield}.{chrome_slots.skinnedTagFor("field")}::UICorner`,
			props = { CornerRadius = udim(0, metrics.radii.control) },
		})
		fromMetric("radii.control", "Chrome — field editing, own corner", "CornerRadius", "udimOffset")
	end
	-- author-supplied rules ride the chrome group, after everything this
	-- compiler emits, so an author can override a generated decision
	for _, rule in o.rules or {} do
		emit("chrome", {
			name = rule.name,
			selector = rule.selector,
			props = rule.props,
			transitions = rule.transitions,
		})
	end

	-- hover (compound-gated on the pointer-live tag: a touch paradigm must
	-- never match, and :Hover alone carries no paradigm gate)
	emit("hover", {
		name = "Control — hover",
		selector = `TextButton.{T.interactive}.{T.pointerLive}:Hover`,
		props = { BackgroundColor3 = "$ControlHover" },
		transitions = { BackgroundColor3 = "fast" },
	})
	emit("hover", {
		name = "Primary — hover",
		selector = `TextButton.{S}accent.{T.pointerLive}:Hover`,
		props = { BackgroundColor3 = "$AccentHover" },
		transitions = { BackgroundColor3 = "fast" },
	})
	emit("hover", {
		name = "Destructive — hover",
		selector = `TextButton.luau-role-destructive.{T.pointerLive}:Hover`,
		props = { BackgroundColor3 = "$DangerHover" },
		transitions = { BackgroundColor3 = "fast" },
	})
	emit("press", {
		name = "Control — pressed",
		selector = `TextButton.{T.interactive}:Press`,
		props = { BackgroundColor3 = "$ControlPressed" },
	})
	emit("press", {
		name = "Primary — pressed",
		selector = `TextButton.{S}accent:Press`,
		props = { BackgroundColor3 = "$AccentPressed" },
	})
	emit("press", {
		name = "Destructive — pressed",
		selector = "TextButton.luau-role-destructive:Press",
		props = { BackgroundColor3 = "$DangerPressed" },
	})
	-- Chrome interaction states. The decoration child is Active=false and can
	-- never report a GuiState of its own, so the state is read from its PARENT
	-- and reaches the child through the child combinator. One base image, four
	-- tints — never four assets.
	for _, slot in chrome_slots.SLOTS do
		-- one decoration, or every layer of a stack: the whole ladder responds as
		-- one control, which is what a player sees. rs-m2 proved a compound tag
		-- can single one layer out when a package wants that instead.
		local tags: { { name: string, tag: string } } = {}
		if ninePlans[slot] ~= nil then
			table.insert(tags, { name = `Chrome — {slot}`, tag = chrome_slots.tagFor(slot) })
		end
		if stacks[slot] ~= nil then
			for _, layer in stacks[slot].layers do
				table.insert(tags, { name = `Chrome — {slot} L{layer.index} {layer.kind}`, tag = layer.tag })
			end
		end
		for _, entry in tags do
			emit("hover", {
				name = `{entry.name} hover`,
				selector = `.{T.interactive}.{T.pointerLive}:Hover > .{entry.tag}`,
				props = { ImageColor3 = "$ChromeTintHover" },
				transitions = { ImageColor3 = "fast" },
			})
			emit("press", {
				name = `{entry.name} pressed`,
				selector = `.{T.interactive}:Press > .{entry.tag}`,
				props = { ImageColor3 = "$ChromeTintPressed" },
			})
			emit("disabled", {
				name = `{entry.name} disabled`,
				selector = `:NonInteractable > .{entry.tag}`,
				props = { ImageTransparency = num(baseExtra.disabledContentOpacity) },
			})
			-- RS-DIR6-F1 (director round 6, live-found): A BROKEN ASSET STAYS
			-- HIDDEN IN EVERY STATE.
			--
			-- `Chrome — <slot> fallback hide` hides the art of a fallen-back
			-- slot (`ImageTransparency = 1`) while `Chrome — <slot> fallback`
			-- repaints the declared native fill underneath — one rule until
			-- RS-A16-D5 split the hide onto its own tag. Both ride the CHROME
			-- group, and the disabled rule
			-- immediately above rides the DISABLED group — and the cascade is
			-- Priority first, then insertion order, with NO selector specificity
			-- (ADR-0018; priority is pinned by this generator, so group order IS
			-- the answer). So on a node that was BOTH disabled and in fallback the
			-- 0.4 dim won on the same property and re-revealed exactly the broken
			-- art the fallback existed to hide, at 60% opacity, over the native
			-- fill and rounded phantom corner that had replaced it.
			--
			-- Fixed by PRIORITY, not by scoping the disabled rule off fallback
			-- nodes: a StyleSheet selector has no negation, so "everything except
			-- a fallback node" is not expressible — and re-asserting the hide
			-- above the state rules is the same shape the fallback rule already
			-- uses to beat the resting art. It carries the HIDE and nothing else,
			-- so it moved onto the mute tag with it (RS-A16-D5): art whose OWN asset
			-- failed is not hidden, and a disabled node must not re-reveal art that a
			-- healthy-sibling mute is hiding;
			-- the fill and the corner are the chrome-group rule's and nothing
			-- contests those. Emitted per entry, so one slot's protection can
			-- never be undercut by a later slot's disabled rule (different tag,
			-- different instance).
			emit("disabled", {
				name = `{entry.name} fallback over states`,
				selector = `.{entry.tag}.{chrome_slots.TAGS.mute}`,
				props = { ImageTransparency = num(1) },
			})
		end
	end
	-- ROLE-AWARE chrome states (the same finding V14 that produced the flat
	-- role hover/press rules, one level down). The generic `Chrome — control
	-- hover/pressed` rules key on the interactive tag, NOT on the role, so
	-- without these a hovered destructive slab repainted itself neutral grey and
	-- the role visually vanished at the moment of the click. Emitted AFTER the
	-- loop above so insertion order puts them on top of it.
	if ninePlans.control ~= nil then
		local controlTag = ninePlans.control.tag
		emit("hover", {
			name = "Chrome role — destructive hover",
			selector = `.luau-role-destructive.{T.pointerLive}:Hover > .{controlTag}`,
			props = { ImageColor3 = "$ChromeTintDangerHover" },
			transitions = { ImageColor3 = "fast" },
		})
		emit("press", {
			name = "Chrome role — destructive pressed",
			selector = `.luau-role-destructive:Press > .{controlTag}`,
			props = { ImageColor3 = "$ChromeTintDangerPressed" },
		})
	end
	-- ----- SEMANTIC ICON PAINT (ADR-0020 R4) -------------------------------
	--
	-- The authority split, stated once: the ADAPTER picks WHICH picture (a content
	-- id per node is not something a rule can decide) and HOW BIG (from the
	-- snapshot's `iconSizes`, so a metric package resizes icons); the SHEET owns
	-- the two paint properties, so an icon re-tints on a theme change inside one
	-- package with no Luau at all, and a pixel package's icons are nearest-
	-- neighbour by the same counted rule every other image is.
	--
	-- One rule per icon name that RESOLVES TO ART, emitted only when it has
	-- something to say.
	--
	-- IT ASKS `resolveIcon`, IT DOES NOT READ THE AUTHORED MAP (found live in
	-- Studio, 2026-07-27). This loop used to iterate `package.icons`, which was
	-- correct while a package's own map was the only place art could come from.
	-- The compact-label stage added a rung below it — the framework's own icon set
	-- — so a package that declares NO icons now still draws pictures, and this
	-- emitter skipped every one of them: measured in the running showcase, Studio
	-- Neutral produced 70 rules and ZERO icon rules while `resolveIcon` happily
	-- returned `source = "asset"` with `tintRole = "content"` for the same names.
	-- `ImageColor3` is sheet-owned in native mode and the adapter may not write
	-- it, so those icons painted pure WHITE — invisible on the five light theme
	-- variants, and only a real engine could show it.
	--
	-- So the vocabulary is the union of what the package declared (which may
	-- include namespaced `ns:name` art) and what the framework itself knows, and
	-- the ANSWER for each comes from the one resolution ruling every other
	-- consumer asks. A package that declines the framework set gets a glyph back
	-- and is skipped below, exactly as an undeclared name always was.
	do
		local iconNames: { string } = {}
		local seenName: { [string]: boolean } = {}
		local function addName(name: string)
			if not seenName[name] then
				seenName[name] = true
				table.insert(iconNames, name)
			end
		end
		if type(package.icons) == "table" then
			for name in package.icons do
				addName(tostring(name))
			end
		end
		for name in themePackage.ICON_FALLBACK_GLYPHS :: any do
			addName(tostring(name))
		end
		table.sort(iconNames)
		for _, name in iconNames do
			local resolved = themePackage.resolveIcon(package, name)
			if type(resolved) ~= "table" or resolved.source ~= "asset" then
				continue -- a glyph answer paints no picture, so it needs no rule
			end
			local props: { [string]: RuleProp } = {}
			if type(resolved.tintRole) == "string" then
				local token = TINT_ROLE_TOKEN[resolved.tintRole]
				assert(
					token ~= nil,
					`sheet_model.buildPackage: icon '{name}' names tintRole '{resolved.tintRole}', which is not `
						.. "a palette role — a tint that resolves to nothing paints the art unchanged and is "
						.. "invisible until a device shows it"
				)
				props.ImageColor3 = token
			end
			if props.ImageColor3 == nil and pixelUnit == nil then
				continue -- nothing to own: no tint role and no pixel stamp
			end
			emit("chrome", {
				name = `Icon — {name}`,
				selector = "." .. chrome_slots.iconTagFor(name),
				props = imageProps(props),
			})
		end
	end

	emit("disabled", {
		name = "Disabled button",
		selector = "TextButton:NonInteractable",
		props = { TextTransparency = num(baseExtra.disabledContentOpacity) },
	})
	emit("disabled", {
		name = "Disabled field",
		selector = "TextBox:NonInteractable",
		props = { TextTransparency = num(baseExtra.disabledContentOpacity) },
	})
	-- SEMANTIC ICON ART (ADR-0020 R4), emitted by EVERY package — including a
	-- package that declares no icons at all, because the tag only ever lands on a
	-- node whose icon actually resolved to art. Emitting it unconditionally is
	-- what keeps the suppression working across a swap: a package with icons and
	-- one without must not disagree about whether the rule exists.
	emit("disabled", {
		name = "Semantic icon replaces the glyph",
		selector = `.{chrome_slots.TAGS.iconArt}`,
		props = { TextTransparency = num(1) },
	})

	-- THE HELD SOURCE EMPTIES (director round five) — emitted by every package
	-- for the same swap-consistency reason as the icon rule above
	emit("disabled", {
		name = "Held drag source empties its label",
		selector = `.{chrome_slots.TAGS.dragHeld}`,
		props = { TextTransparency = num(1) },
	})

	-- ----- flatten, gate, and pin the cascade ------------------------------
	local rules: { Rule } = {}
	for _, group in sheet_model.RULE_GROUPS do
		for _, rule in groups[group] do
			sheet_model.checkSelector(rule.selector, rule.name)
			local pseudo = string.match(rule.selector, "::([%w_]+)$")
			if pseudo ~= nil then
				local allowed = (sheet_model.PHANTOM_PROPS :: any)[pseudo]
				for prop in rule.props do
					assert(
						allowed[prop] == true,
						`sheet_model.buildPackage: rule '{rule.name}' writes '{prop}', which ::{pseudo} does not have`
					)
				end
			else
				-- The chrome scope is what unlocks the six image properties, and it
				-- is earned by the SELECTOR, never by the group. Author-supplied
				-- rules ride the chrome group (that is where they must land in the
				-- cascade), so keying on the group handed every author rule the
				-- image-chrome allowance — a rule selecting `.luau-surface-raised`
				-- could set `Image` and compile clean, on a node that has no
				-- decoration to carry it. Every rule this compiler emits into the
				-- chrome group names the slot prefix in its selector, so the
				-- narrower test costs the generated rules nothing.
				local isChrome = string.find(rule.selector, chrome_slots.TAGS.slotPrefix, 1, true) ~= nil
				for prop, value in rule.props do
					local ok, reason = themePackage.lintProperty(prop, if isChrome then "chrome" else "rule")
					assert(ok, `sheet_model.buildPackage: rule '{rule.name}' — {tostring(reason)}`)
					sheet_model.checkContentValue(rule.name, prop, value)
				end
			end
			table.insert(rules, rule)
			rule.priority = #rules * 10
		end
	end

	-- ----- mirrors: what the Style Editor SHOWS about this package ---------
	local mirrors: { { name: string, value: number } } = {}
	for _, step in themePackage.REQUIRED_SPACE_STEPS do
		table.insert(mirrors, { name = "Space" .. pascal(step), value = metrics.space[step] })
	end
	for _, role in themePackage.REQUIRED_TYPE_ROLES do
		table.insert(mirrors, { name = "Type" .. pascal(role), value = metrics.typography[role].size })
	end
	for _, radius in themePackage.REQUIRED_RADII do
		table.insert(mirrors, { name = "Radius" .. pascal(radius), value = metrics.radii[radius] })
	end
	table.insert(mirrors, { name = "TargetMinimum", value = metrics.targetSizes.minimum })
	table.insert(mirrors, { name = "MotionFast", value = metrics.motion.fast })
	table.insert(mirrors, { name = "MotionNormal", value = metrics.motion.normal })

	-- ----- the content stamp ----------------------------------------------
	-- Includes the package's own stamp, so a package edit ALWAYS migrates the
	-- sheet even if two different packages happened to compile to the same
	-- rules; and the chrome kinds, via chrome_props.describe.
	local parts: { string } = { `package={package.identity.id}@{package.identity.version}#{package.stamp}` }
	for _, theme in themes do
		local names = {}
		for k in theme.tokens do
			table.insert(names, k)
		end
		table.sort(names)
		for _, k in names do
			local v = theme.tokens[k]
			local described = chrome_props.describe(v)
			if described ~= nil then
				table.insert(parts, `{theme.name}.{k}={described}`)
			elseif v.kind == "number" then
				table.insert(parts, string.format("%s.%s=%.4f", theme.name, k, v.value))
			else
				table.insert(parts, string.format("%s.%s=%.4f,%.4f,%.4f", theme.name, k, v.r, v.g, v.b))
			end
		end
	end
	for _, rule in rules do
		table.insert(parts, `{rule.priority}:{rule.selector}`)
		local pnames = {}
		for k in rule.props do
			table.insert(pnames, k)
		end
		table.sort(pnames)
		for _, k in pnames do
			local v = rule.props[k]
			local described = if type(v) == "table" then chrome_props.describe(v) else nil
			table.insert(
				parts,
				k
					.. "="
					.. (
						if type(v) == "string"
							then v
							elseif described ~= nil then described
							else tostring(v.kind) .. tostring(v.value or v.offset or v.family or v.item or "")
					)
			)
		end
	end
	for _, m in mirrors do
		table.insert(parts, `{m.name}={m.value}`)
	end

	return {
		schema = "luauui-native-sheet/1",
		stamp = stampOf(parts),
		defaultTheme = defaultTheme,
		themes = themes,
		rules = rules,
		mirrors = mirrors,
		motion = { fast = metrics.motion.fast, normal = metrics.motion.normal },
		-- live-edit repaint map (see fromMetric above): which rule props a
		-- Radii_*/Strokes_* sheet edit must refresh, consumed by the controller
		metricRuleProps = metricRuleProps,
		-- what this skin costs, counted at compile (see the census locals)
		census = census,
	}
end

return sheet_model
