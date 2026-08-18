--!strict
-- Theme PACKAGE compiler (ADR-0019 §1, stage theme-packages-and-skinning).
-- PURE and engine-free: `define(def) -> (package?, report)` validates a
-- declarative theme description and returns a deeply frozen, content-stamped
-- package, or nil plus a report naming every rejection.
--
-- A package is INSPECTABLE DATA, never code. It is the versioned packaging and
-- solver bridge around native StyleSheets — it adds validation, deterministic
-- metrics, and bounded asset/chrome metadata; it is not a second style language
-- and it may not carry callbacks or component trees (ADR-0019 non-goals).
--
-- Public interface
--   package.SCHEMA                      the schema string this compiler speaks
--   package.define(def) -> (pkg?, report)
--   package.lintProperty(prop, scope?)  -> (ok, reason?)   the §4 legal-property
--                                          linter, exported so the materializer
--                                          and chrome packages reuse ONE ruling
--   package.REQUIRED_TYPE_ROLES / SPACE_STEPS / CONTROL_SIZES / SLOTS
--
-- Depends on: src/tokens/tokens (contrast + completeness gate reused verbatim),
-- src/render/authority (the property-authority manifest the linter rules from).
--
-- Report shape mirrors tokens.compile so callers can treat both the same way:
--   { ok, missing = { "<field>" }, contrast = { {pair, ratio, ok} },
--     errors = { { class, field, message, fix } } }

local tokens = require("../tokens/tokens")
local authority = require("../render/authority")
-- the bespoke shadow contract a recipe's `shadow` field is validated against.
-- PURE (styling -> default_style -> tokens); nothing in that chain reaches back
-- here, so this is not a cycle (docs/lessons/lune-circular-require-hangs.md).
local styling = require("../tokens/styling")
-- the focus vocabulary + the per-theme colour-token resolver. PURE and DOWN the
-- graph (chrome_slots -> chrome_props, and nothing there reaches back here), so
-- this is not the cycle ADR-0019's require-hazard ruling warns about.
local chrome_slots = require("../tokens/chrome_slots")
-- the framework's OWN icon art (compact-label stage): a leaf module of frozen
-- data that requires nothing at all, so it cannot be the cycle above warns about.
-- Required here rather than looked up lazily because `resolveIcon` is called on
-- every icon sync and a later `local` would be a nil global read
-- (docs/lessons/later-locals-are-not-upvalues.md).
local standard_icons = require("./standard_icons")
local num = require("../num")
local textDistance = require("../text_distance")

local package = {}

package.SCHEMA = "facet-theme/1"

-- ===== the versioned core vocabulary =======================================
-- v1 is a CLOSED set. A custom control's namespaced roles are a later
-- contribution contract (ADR-0019 §1); nothing here accepts an unknown name,
-- because an unknown name is the exact authoring mistake this compiler exists
-- to catch before play.

package.REQUIRED_TYPE_ROLES = table.freeze({ "caption", "label", "body", "heading", "title", "control" })

-- THE WEIGHT CHANNEL IS A TYPOGRAPHY ROLE (F2, racer-sort parity, 2026-08-02).
--
-- `strong` (emphasis at reading size) and `numeral` (a figure that has to read as
-- a rank/score) are the two things games kept asking a `weight` prop for. They are
-- ROLES rather than a prop for the reason `Text.font` was deprecated
-- diagnosed-not-preserved: a font that reaches only the paint seam makes measured
-- and painted bounds disagree, permanently and invisibly. A role carries size,
-- font descriptor AND line height through ONE resolution the measurer and the
-- painter both read, so the two cannot split.
--
-- OPTIONAL, and derived when absent (`package.deriveTypeRole` below, applied in
-- `snapshot.resolve`). Making them required would fail every package published
-- against the six-role vocabulary — including the reference packages — for values
-- the derivation gets right on its own. A package that wants its own emphasis
-- face simply authors the role and wins.
package.OPTIONAL_TYPE_ROLES = table.freeze({ "strong", "numeral" })

-- the whole eight-role vocabulary, in ladder order. This is the list a refusal
-- names and the list `snapshot.isTypeRole` validates a `textSize` against.
package.TYPE_ROLES = table.freeze({
	"caption",
	"label",
	"body",
	"heading",
	"title",
	"control",
	"strong",
	"numeral",
})

-- HOW AN UNAUTHORED WEIGHT ROLE IS DERIVED.
--
-- `base` names the authored role whose SIZE and font FAMILY/STYLE the derived
-- role inherits (so a package that scales its ramp scales these with it, and a
-- package with a display face keeps that face); `weight` is the only thing the
-- derivation changes. `fallbackBase` covers a hand-built metrics table missing
-- the preferred base.
--
-- WHY THESE WEIGHTS. Emphasis at reading size wants the lightest face that still
-- reads as emphasis — SemiBold — because a Bold body paragraph is shouting. A
-- numeral is a glanceable figure at control size, so it takes Bold. Neither goes
-- to ExtraBold/Heavy by default: the faces the text-measurement milestone
-- actually probed for the default family are Regular / Medium / SemiBold / Bold
-- (docs/plans/text-measurement-milestone.md), and an unshipped weight is silently
-- substituted by `Font.new` — which is exactly the class of quiet substitution
-- this channel exists to remove. A package may still author ExtraBold explicitly.
package.DERIVED_TYPE_ROLES = table.freeze({
	strong = table.freeze({ base = "body", fallbackBase = "body", weight = "SemiBold" }),
	numeral = table.freeze({ base = "control", fallbackBase = "heading", weight = "Bold" }),
})

-- deriveTypeRole(role, typography) -> { font = { family, weight, style }, size,
-- lineHeight } | nil. PURE, and the ONE derivation both the theme snapshot and a
-- game's own tooling read, so a derived face can never be computed two ways.
function package.deriveTypeRole(role: string, typography: any): any
	local rule = (package.DERIVED_TYPE_ROLES :: any)[role]
	if rule == nil or type(typography) ~= "table" then
		return nil
	end
	local base = typography[rule.base]
	if type(base) ~= "table" then
		base = typography[rule.fallbackBase]
	end
	if type(base) ~= "table" or type(base.font) ~= "table" then
		return nil
	end
	return {
		font = { family = base.font.family, weight = rule.weight, style = base.font.style },
		size = base.size,
		lineHeight = base.lineHeight,
	}
end

package.REQUIRED_SPACE_STEPS = table.freeze({ "xs", "s", "m", "l", "xl" })
--[[ ...AND THE STEPS A PACKAGE DOES NOT HAVE TO AUTHOR (DIR wave contract 6).

	`gutter` is the SCREEN-EDGE step. It is derived in `themes/snapshot.resolve`
	as `max(SCREEN_GUTTER_FLOOR, space.s)` — see the long note there for why a
	screen edge has a physical floor that the rest of a spacing ladder does not —
	and a package that authors one of its own still wins.

	It is listed here, beside the required steps, because THIS list is what
	`snapshot.isSpaceStep` and the blueprint boundary's refusal message are built
	from. A step the resolver answers but the boundary refuses is the "the
	documentation states what ships" defect the schema's own comment warns about,
	one vocabulary down. Optional, so no package's compile changes and no content
	stamp moves. ]]
package.DERIVED_SPACE_STEPS = table.freeze({ "gutter" })
package.SPACE_STEPS = table.freeze({ "xs", "s", "m", "l", "xl", "gutter" })
package.REQUIRED_CONTROL_SIZES = table.freeze({ "compact", "regular", "large" })
package.CONTROL_SIZE_FIELDS = table.freeze({ "height", "paddingX", "iconSize" })
-- THE SLOT VOCABULARY IS chrome_slots'. It used to be restated here and the two
-- lists had to be kept in step by hand; they are one list now, because a slot
-- this compiler accepts but the plan machinery does not know (or the reverse) is
-- a package that validates and paints nothing. Insets for every slot added after
-- the original six stay OPTIONAL (default 0) — see REQUIRED_INSET_SLOTS — so a
-- package published against an earlier slot list still compiles.
package.SLOTS = chrome_slots.SLOTS

-- Slots whose content insets a package MUST declare. The v1 six always did, and
-- silently defaulting one of them to zero would un-reserve space a decoration is
-- still painting over. The three slots added afterwards default to zero instead,
-- because requiring them would have broken every package already published
-- against the earlier vocabulary — and zero is the right default for chrome that
-- sits behind a fixed-size token (a thumb, a seal) or behind a rail with no
-- content of its own.
package.REQUIRED_INSET_SLOTS = table.freeze({ "panel", "control", "field", "selection", "divider", "scrollbar" })
package.REQUIRED_RADII = table.freeze({ "control", "panel", "pill" })
package.REQUIRED_STROKES = table.freeze({ "hairline" })
package.REQUIRED_MOTION = table.freeze({ "fast", "normal" })
package.INSET_SIDES = table.freeze({ "top", "right", "bottom", "left" })

-- Control families and the metric fields each owns. This is the inventory the
-- framework's composite controls resolve through, so it doubles as the list of
-- names `snapshot` accepts in a `controls.<family>.<field>` metric reference.
--
-- A family appears here ONLY for metrics with no better home. Where a control's
-- literal turned out to BE an existing role — Chip/Disclosure/Picker/Stepper's
-- 44px rows are the target floor, PopupButton's 36/44/56 rows are the three
-- control sizes — the control references that role instead, so a theme retunes
-- one number and every control that means the same thing follows.
package.CONTROL_FAMILIES = table.freeze({
	button = table.freeze({ "padding" }),
	slider = table.freeze({ "thumbSize", "railHeight", "readoutMinWidth" }),
	progress = table.freeze({ "trackHeight", "rowMinHeight" }),
	popup = table.freeze({ "triggerHeight" }),
	textInput = table.freeze({ "fieldHeight", "clearSize", "padding" }),
	toggle = table.freeze({ "minHeight", "trackWidth", "trackInset" }),
	stepper = table.freeze({ "valueMinWidth" }),
	label = table.freeze({ "gap" }),
	image = table.freeze({ "defaultSize" }),
	table = table.freeze({
		"cellTextSize",
		"sortMarkTextSize",
		"sortMarkMargin",
		"headerHeight",
		"rowGap",
		"indicatorThickness",
		"editToggleInset",
		"editTogglePadding",
		"editToggleWidth",
		"editToggleHeight",
		"ghostWidth",
		"ghostHeight",
		"ghostStackWidth",
		"ghostStackHeight",
	}),
	rowActions = table.freeze({ "buttonMinWidth", "buttonPad", "editAffordance" }),
})

-- OPTIONAL family fields: legal to declare, never required, and filled in by
-- `snapshot.resolve` when a package declares none — so every theme ANSWERS the
-- metric path while no existing package's authored data (and therefore no
-- existing package's content stamp) moves.
--
-- Exactly the shape `REQUIRED_INSET_SLOTS` already uses for the optional-inset
-- slots, and for the same reason: `controls.button.height` is the circle
-- Button's diameter (feature round 2026-07-26), a value most themes will never
-- tune, and adding it to the REQUIRED list would refuse to compile every
-- package written before it existed.
package.CONTROL_FAMILY_OPTIONAL = table.freeze({
	button = table.freeze({ "height" }),
	-- the gutter BETWEEN two adjacent tray buttons (director device round
	-- 2026-08-12: "Delete 645-777, Flag 780-905, corners touching" — two rounded
	-- plates rendered flush read as one merged slab). Optional for the reason
	-- `button.height` is: `snapshot.resolve` fills it from the theme's own `space`
	-- scale, so every package answers `controls.rowActions.trayGap` while no
	-- package's authored metrics — and therefore no package's content stamp —
	-- moves for a value nobody wrote.
	rowActions = table.freeze({ "trayGap" }),
	-- the indeterminate spinner's dot (parity round 2 §3.1). Optional for the
	-- same reason `trayGap` is: `snapshot.resolve` fills it from the theme's own
	-- `space` scale, so every package answers `controls.progress.spinnerDotSize`
	-- while no package's authored metrics — and therefore no package's content
	-- stamp — move for a value nobody wrote.
	-- ...plus the CIRCULAR indicator's diameter and stroke (parity round 3 D2),
	-- which are optional for the same reason and take the identical route. Apple
	-- publishes no numeric size for a circular progress view; the only sentence
	-- the HIG gives is "prefer an activity indicator when space is constrained",
	-- so the size is small-by-default from the theme's own `space` scale rather
	-- than a number invented here — and `circularThickness` is filled AGAINST the
	-- resolved size, because a stroke wider than the box's own inset paints
	-- outside the rect the solver measured (see snapshot.resolve).
	progress = table.freeze({ "spinnerDotSize", "circularSize", "circularThickness" }),
})

-- VALUE-DISPLAY HOSTS whose extent is a METRIC the package resolves (RS-A16-D3).
-- A slot in this table can have its content box checked at COMPILE time: the
-- framework knows how tall the rail it decorates will be, because the same
-- definition declares it. Every other slot's extent depends on the live solve
-- (a fill width, an explicit height, a content measurement) and is reported by
-- the solver instead.
--
-- `near`/`far` are the inset sides on the axis the metric describes: a progress
-- track's `trackHeight` and a slider rail's `railHeight` are both CROSS-axis
-- extents of a horizontal rail, so both are checked on y.
package.VALUE_HOST_METRICS = table.freeze({
	barTrack = table.freeze({ axis = "y", near = "top", far = "bottom", family = "progress", field = "trackHeight" }),
	sliderTrack = table.freeze({ axis = "y", near = "top", far = "bottom", family = "slider", field = "railHeight" }),
})

-- WCAG-derived accessibility floor. A theme may raise a target size; it can
-- never lower one below the platform-agnostic minimum (ADR-0019 §2 step 4).
package.MIN_TARGET_SIZE = 44

-- RESOLVABLE FONT FAMILIES. A typography role's family (which is also the
-- chrome-text font, since the lifted label's rules take `fontOf(role)`) must be
-- something BOTH halves of the system can resolve:
--   * the measurement half keys its cache on the descriptor and only knows a
--     family it has a file for;
--   * the paint half hands the family to `Font.new`, which accepts ANY string
--     and silently falls back.
-- A bare unknown name therefore measured conservative-but-wrong while painting
-- through a raw Font.new — the exact measure/paint split this stage exists to
-- prevent. So a family is either a content URL (the engine's own vocabulary) or
-- one of the aliases the client materializer maps to a file. These names mirror
-- `src/client/text_premeasure.FONT_FILES`; that module is client-only (ADR-0003
-- seam) and cannot be required from here, so a spec asserts the two agree.
package.FONT_FAMILY_ALIASES = table.freeze({ "BuilderSans", "GothamSSm", "SourceSans" })

-- the readability ceiling on a gradient's `alpha` ramp (see the rejection in
-- `define` for why an engine Transparency stop near 1 is never subtle)
package.GRADIENT_ALPHA_MAX = 0.9
local GRADIENT_ALPHA_MAX = package.GRADIENT_ALPHA_MAX

local FONT_FAMILY_PREFIXES = { "rbxasset://", "rbxassetid://" }

function package.isResolvableFontFamily(family: any): boolean
	if type(family) ~= "string" or family == "" then
		return false
	end
	for _, prefix in FONT_FAMILY_PREFIXES do
		if string.sub(family, 1, #prefix) == prefix then
			return true
		end
	end
	for _, alias in package.FONT_FAMILY_ALIASES do
		if family == alias then
			return true
		end
	end
	return false
end

local SECTIONS: { [string]: boolean } = {
	base = true,
	identity = true,
	style = true,
	metrics = true,
	chrome = true,
	assets = true,
	compatibility = true,
	-- SEMANTIC ICONS (ADR-0020 R4): name -> asset reference. Controls request an
	-- icon by MEANING; a raw asset id in control code stays forbidden.
	icons = true,
}

-- `standardIcons = false` declines the framework's own icon art (see
-- `resolveIcon`), leaving every name this package does not declare on the ASCII
-- glyph. It is the escape hatch for a pixel package, whose grid a smooth
-- silhouette would break, and for the two packages whose glyph fallback is the
-- point of the demonstration.
local IDENTITY_FIELDS: { [string]: boolean } = {
	id = true,
	displayName = true,
	schemaVersion = true,
	version = true,
	rendering = true,
	pixelUnit = true,
	standardIcons = true,
}
local METRIC_SECTIONS: { [string]: boolean } = {
	typography = true,
	space = true,
	controlSizes = true,
	controls = true,
	radii = true,
	strokes = true,
	targetSizes = true,
	insets = true,
	motion = true,
	-- icon METRIC roles (ADR-0020 R4). Optional: a package that declares no
	-- icons has no sizes to declare either, and every package published before
	-- this stage has neither.
	iconSizes = true,
}
local TYPOGRAPHY_FIELDS: { [string]: boolean } = { font = true, size = true, lineHeight = true }
local FONT_FIELDS: { [string]: boolean } = { family = true, weight = true, style = true }
-- `content` is the CANONICAL asset field (ADR-0020 R6); `contentId` stays a
-- legal alias. Both normalize to one plain string at define time, so there is
-- exactly one resolution path downstream and exports stay serializable —
-- rs-m7 measured that even a rule authored with Content.fromUri round-trips as
-- a string, so no materialization machinery exists on the normal path at all.
local ASSET_FIELDS: { [string]: boolean } = {
	content = true,
	contentId = true,
	sliceCenter = true,
	sliceScale = true,
	preload = true,
	fallback = true,
	tintRole = true,
	-- the SOURCE's pixel size. Optional, because a package can name art it did
	-- not author; declared, it turns the slice-geometry checks below from
	-- "the centre must not be inverted" into "the centre must not be EMPTY",
	-- which is the failure the art lane hit twice while authoring real assets.
	width = true,
	height = true,
}
local SLICE_CORNERS = table.freeze({ "x0", "y0", "x1", "y1" })
local COMPATIBILITY_FIELDS: { [string]: boolean } = { requiresSchema = true, capabilities = true, fallbacks = true }
-- `chrome.focus` is a RESERVED NON-SLOT key: the focus treatment is applied to
-- whichever node currently has focus, not to a decoration surface, so it has no
-- plan, no census of instances and no skinned tag. It rides `chrome` because
-- that is where "how this package paints its chrome" lives, and it is validated
-- by its own branch below (see src/tokens/chrome_slots for the full reasoning).
package.CHROME_RESERVED_KEYS = table.freeze({ "focus" })
local FOCUS_FIELDS: { [string]: boolean } = {
	kind = true,
	color = true,
	blurRadius = true,
	transparency = true,
	spread = true,
	offset = true,
	zIndex = true,
}

local CHROME_FIELDS: { [string]: boolean } = {
	kind = true,
	asset = true,
	contentInsets = true,
	fallback = true,
	-- `layers = { … }`: the bounded decoration STACK (ADR-0020 R1), legal only
	-- on a `kind = "layered"` recipe
	layers = true,
	-- GENERATOR-WRITTEN (see normalizeVariant): the canonical per-state map a
	-- variant `asset` compiles to. Accepted as INPUT only because a package
	-- derived from a compiled base inherits it; it is re-derived from `asset` on
	-- every compile, so an inherited one is overwritten rather than trusted.
	assetVariants = true,
	-- `sliced = false` paints the asset WHOLE (no ScaleType=Slice, no
	-- SliceCenter). Omitted, the slot's own nature decides — a thumb and a badge
	-- seal are fixed-size tokens, everything else is a stretchable frame.
	sliced = true,
	-- `shadow = "raised" | "overlay" | { … }`: adapter-owned depth for this slot
	-- (::UIShadow rules are inert, feasibility m7), validated here against the
	-- same styling.normalizeShadow contract the adapter materializes.
	shadow = true,
	-- ===== the BAR family's declared geometry (ADR-0020 R3) ================
	-- `direction = "ltr" | "rtl" | "ttb" | "btt"` on `barFill`: which axis the
	-- clip window reveals and which edge of the art is pinned to its origin.
	direction = true,
	-- `size = { w, h }` on `barCap` / `barCenter`: a whole-image ornament has no
	-- intrinsic size the solver knows, so the recipe states it (the plaque idiom).
	size = true,
	-- per-END art on `barCap`, the per-corner idiom one control down: the shared
	-- `asset` paints both caps unless an end names its own.
	startAsset = true,
	endAsset = true,
}
-- Recipe fields that are legal only on the slots that can act on them. A field
-- accepted everywhere and honoured in one place is a field authors put in the
-- wrong recipe and never find out about.
local CHROME_FIELD_SLOTS: { [string]: { [string]: boolean } } = {
	direction = { barFill = true },
	size = { barCap = true, barCenter = true },
	startAsset = { barCap = true },
	endAsset = { barCap = true },
}
-- rs-m4 REJECTED the ImageRect crop for sliced art: `ImageRect` and
-- `ScaleType = Slice` both address the texture, so composing them re-derives the
-- nine-patch from the CROPPED rect and the end cap is cut out of mid-texture.
-- The probe's verdict is encoded here rather than left as prose, so a package
-- that reaches for the rejected mechanism is told which measurement says no.
local REJECTED_CROP_FIELDS: { [string]: boolean } = { imageRect = true, imageRectOffset = true, imageRectSize = true }
-- GENERATOR-WRITTEN layer keys, accepted as input for the same reason
-- `assetVariants` is on CHROME_FIELDS: a package derived from a compiled base
-- inherits them, and they are re-derived from the authored reference on every
-- compile rather than trusted.
local LAYER_KIND_SET: { [string]: boolean } = {}
for _, kind in chrome_slots.LAYER_KINDS do
	LAYER_KIND_SET[kind] = true
end

local LAYER_GENERATED_FIELDS: { [string]: boolean } = {
	assetVariants = true,
	topLeftVariants = true,
	topRightVariants = true,
	bottomLeftVariants = true,
	bottomRightVariants = true,
}

local THEME_FIELDS: { [string]: boolean } = { name = true, colors = true, extra = true }
local STYLE_FIELDS: { [string]: boolean } = { themes = true, defaultTheme = true }

-- ===== §4 legal-property linter ============================================
-- A theme rule may write ONLY the native paint set (Step 2's nativeSheetOwned)
-- and, inside a chrome recipe, the decoration child's image properties
-- (feasibility m2). Everything else belongs to the solver, a data binding, the
-- presentation transform, or a UI.Custom host — and the ENGINE will not police
-- it: an explicit write silently defeats a StyleRule and fires no signal, so a
-- themed `Size` would break layout with no error anywhere. That is why this
-- runs at COMPILE time.

-- image chrome: EXACTLY the six properties feasibility m2 measured rule-ownable
-- end to end. The set is closed at what was proven, not at what ImageLabel
-- happens to expose — an unmeasured image property in a rule is the same
-- accepted-and-ignored failure `::UIShadow` was (silently accepted, paints
-- nothing), and a nine-slice recipe has no use for rect/tile/resample anyway:
-- the slice geometry IS SliceCenter + SliceScale.
--
-- v2 (ADR-0020) adds exactly three, each measured in this stage's probes and
-- not one more: `ImageContent` (rs-m7 — rules COERCE a plain string onto it, so
-- authored data never has to become a Content value), `ResampleMode` (rs-m5 —
-- Pixelated composes with Slice in one rule) and `TileSize` (rs-m1 — fully
-- rule-settable, per state, composing with both of the above). `ImageRectOffset`
-- and `ImageRectSize` stay OUT: rs-m4 measured rect cropping re-deriving the
-- nine-patch from the cropped rect, which smears a sliced fill at mid-percent.
local IMAGE_CHROME: { [string]: boolean } = {
	Image = true,
	ImageContent = true,
	ScaleType = true,
	SliceCenter = true,
	SliceScale = true,
	ImageColor3 = true,
	ImageTransparency = true,
	ResampleMode = true,
	TileSize = true,
}

-- engine property -> the authority-manifest key that owns it, so a rejection
-- can NAME the owner instead of saying "not allowed"
local ENGINE_TO_AUTHORITY_KEY: { [string]: string } = {
	Size = "size",
	Position = "position",
	AnchorPoint = "anchorPoint",
	CanvasSize = "canvasSize",
	ZIndex = "zIndex",
	ClipsDescendants = "clipChildren",
	TextSize = "textSize",
	Text = "text",
	PlaceholderText = "placeholder",
	Active = "active",
	Image = "image",
	Transparency = "transparency",
	Rotation = "transform",
	Visible = "transparency", -- presentation authority: visibility is a render output
}

-- lintProperty(prop, scope) -> (ok, reason?). scope: "rule" (default) | "chrome".
function package.lintProperty(prop: string, scope: string?): (boolean, string?)
	if type(prop) ~= "string" or prop == "" then
		return false, "a rule property name must be a non-empty string"
	end
	-- TWO DIFFERENT QUESTIONS, one manifest. `nativeSheetOwned` answers "must the
	-- ADAPTER keep its hands off this in native mode" and, since the fix round
	-- added the eight image properties to it (platform verifier F4), it now
	-- includes image paint. This function answers a narrower one — "may a theme
	-- write this on any rule it likes" — and image paint is legal only inside a
	-- chrome recipe, where the slot is what makes the picture meaningful. So the
	-- image family is excluded here and re-admitted by the scope check below.
	if authority.nativeSheetOwned(prop) and not IMAGE_CHROME[prop] then
		return true
	end
	if scope == "chrome" and IMAGE_CHROME[prop] then
		return true
	end
	local key = ENGINE_TO_AUTHORITY_KEY[prop]
	-- the manifest is per class with a `common` fallback, and a themed property
	-- is class-agnostic: an owner ANYWHERE in it is an owner (Text is declared on
	-- Text/Button/TextField, Size only on common), so the search covers both.
	local owner: any = nil
	if key ~= nil then
		owner = authority.authorityFor("common", key)
		if owner == nil then
			for class in authority.manifest() do
				owner = owner or authority.authorityFor(class, key)
			end
		end
	end
	if owner ~= nil then
		return false,
			`'{prop}' is {owner} authority in Facet (render/authority.luau) — a theme may never write it; `
				.. `remove it from the recipe`
	end
	if IMAGE_CHROME[prop] then
		return false, `'{prop}' is image chrome and is only legal inside a nineSlice chrome recipe`
	end
	return false,
		`'{prop}' is not in the themeable property set (native paint: `
			.. `BackgroundColor3/BackgroundTransparency/TextColor3/TextTransparency/PlaceholderColor3/FontFace/`
			.. `ScrollBarImageColor3/CornerRadius/Stroke*) — remove it or express the intent as a metric`
end

-- ===== helpers =============================================================

local isFiniteNumber = num.isFinite

-- a { w, h } px size: a plaque's plate, a tile's repeat. Both are real geometry
-- the adapter anchors from, so zero is as wrong as absent.
local function isPositiveSize(v: any): boolean
	return type(v) == "table" and isFiniteNumber(v.w) and isFiniteNumber(v.h) and v.w > 0 and v.h > 0
end

-- "did you mean" for an unknown key, cheap and bounded (Levenshtein <= 2)
-- distance <= 2, case-SENSITIVE — the same policy `src/spec_guard.luau` states,
-- and now the same arithmetic (ARCH-17). The separator differs on purpose: a
-- theme property list reads as alternatives.
local NEAREST_MAX_DISTANCE = 2

local function nearest(bad: string, allowed: { [string]: boolean }): string?
	return textDistance.nearest(bad, allowed, NEAREST_MAX_DISTANCE)
end

local function sortedNames(allowed: { [string]: boolean }): string
	return textDistance.listOf(allowed, " | ")
end

local function deepFreeze(t: any): any
	if type(t) ~= "table" then
		return t
	end
	for _, v in t do
		if type(v) == "table" then
			deepFreeze(v)
		end
	end
	-- a definition may legitimately reuse an ALREADY frozen table (deriving from a
	-- compiled base, or reusing default_style's frozen palette): re-freezing one
	-- is an error in Luau, so the guard is load-bearing, not defensive noise.
	return if table.isfrozen(t) then t else table.freeze(t)
end

-- an unfrozen deep copy: tokens.compile freezes what it is handed, so the gate
-- input must never alias a frozen table the caller still owns
local function deepCopy(t: any): any
	if type(t) ~= "table" then
		return t
	end
	local out: any = {}
	for k, v in t do
		out[k] = deepCopy(v)
	end
	return out
end

-- merge `over` onto `base`: present keys win, absent keys inherit. Recurses
-- into plain tables so a package overriding metrics.space.m keeps every other
-- step. There is deliberately no delete: inheriting a role you did not think
-- about is the point of derivation (ADR-0019 §1).
local function inherit(base: any, over: any): any
	if type(over) ~= "table" then
		return if over == nil then base else over
	end
	if type(base) ~= "table" then
		return over
	end
	local out: any = {}
	for k, v in base do
		out[k] = if type(v) == "table" then table.clone(v) else v
	end
	for k, v in over do
		out[k] = inherit(base[k], v)
	end
	return out
end

-- deterministic FNV-1a over the canonical serialization (same algorithm as
-- sheet_model.stampOf, so both stamps read alike in artifacts)
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

-- canonical (sorted, typed) serialization of any plain data value
local function serialize(value: any, out: { string })
	local kind = type(value)
	if kind == "table" then
		local keys: { string } = {}
		for k in value do
			table.insert(keys, tostring(k))
		end
		table.sort(keys)
		table.insert(out, "{")
		for _, k in keys do
			table.insert(out, k .. "=")
			local raw = (value :: any)[k]
			if raw == nil then
				raw = (value :: any)[tonumber(k) :: any]
			end
			serialize(raw, out)
			table.insert(out, ",")
		end
		table.insert(out, "}")
	elseif kind == "number" then
		table.insert(out, string.format("%.6f", value))
	else
		table.insert(out, tostring(value))
	end
end

-- ===== define ==============================================================

export type Error = { class: string, field: string, message: string, fix: string }

-- ===== per-state asset VARIANTS (ADR-0020 R2) ==============================
--
-- ONE GRAMMAR, ONE NORMALIZER. Everywhere an asset reference is legal — a
-- recipe's `asset`, a layer's `asset`, a per-corner override, a rung-2 view prop
-- — a bare string stays legal (same art in every state) and a per-state table
-- becomes legal. Both rungs call THIS function; the prop schema must never fork
-- from the recipe schema, because two grammars for one idea is how a per-view
-- override ends up half-applying across states.
--
-- Focus is deliberately NOT a state: it stays the `selection` slot plus
-- `chrome.focus` (ADR-0019), which is a treatment over whatever has focus rather
-- than a second appearance of the control.
package.VARIANT_STATES = table.freeze({ "default", "hover", "pressed", "selected", "disabled", "error" })

local VARIANT_STATE_SET: { [string]: boolean } = {}
for _, state in package.VARIANT_STATES do
	VARIANT_STATE_SET[state] = true
end
local VARIANT_ENTRY_FIELDS: { [string]: boolean } = { asset = true, contentInsets = true }

-- the axis a side belongs to, for the no-reflow message. An author thinks in
-- sides; the INVARIANT is per axis (the box the solver reserved), so the error
-- names both.
local INSET_AXIS: { [string]: string } = { top = "y", bottom = "y", left = "x", right = "x" }

-- a { top, right, bottom, left } px box: every declared side finite and >= 0,
-- and nothing else in the table (a typo'd side is a padding that silently is not
-- there). Shared by every place a px inset is authored.
local function isPxInsets(v: any): boolean
	if type(v) ~= "table" then
		return false
	end
	for side, value in v :: any do
		if INSET_AXIS[side] == nil then
			return false
		end
		if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
			return false
		end
	end
	return true
end

-- normalizeVariant(value, field) -> (variant?, errors)
--   variant = { [state] = { asset = <string>, contentInsets = { … }? } }
-- `field` is the full path of the reference being normalized, so every error
-- names the slot it came from. A bare string yields `{ default = { asset } }` —
-- the SAME shape — so a caller has exactly one thing to read.
function package.normalizeVariant(value: any, field: string): (any, { Error })
	local errors: { Error } = {}
	local function reject(class: string, message: string, fix: string)
		table.insert(errors, { class = class, field = field, message = message, fix = fix })
	end
	if type(value) == "string" then
		if value == "" then
			reject("unknownField", "an asset reference may not be the empty string", "name a declared asset")
			return nil, errors
		end
		return { default = { asset = value } }, errors
	end
	if type(value) ~= "table" then
		reject(
			"unknownField",
			`an asset reference must be a name or a per-state map (got {type(value)})`,
			'use asset = "name", or asset = { default = "name", hover = "name-hot" }'
		)
		return nil, errors
	end
	for key in value do
		if not VARIANT_STATE_SET[tostring(key)] then
			reject(
				"unknownField",
				`unknown state '{tostring(key)}' in a per-state asset map`,
				`states: {table.concat(package.VARIANT_STATES, " | ")} `
					.. "(focus is not a state — it rides the selection slot and chrome.focus)"
			)
		end
	end
	if value.default == nil then
		reject(
			"missingRole",
			"a per-state asset map must declare `default`",
			"every unstated state falls back to `default`, so it is the one state that cannot be missing"
		)
	end
	local out: { [string]: any } = {}
	local declared: { string } = {}
	for _, state in package.VARIANT_STATES do
		local entry = value[state]
		if entry == nil then
			continue
		end
		table.insert(declared, state)
		if type(entry) == "string" then
			if entry == "" then
				reject("unknownField", `state '{state}' names the empty string`, "name a declared asset")
			else
				out[state] = { asset = entry }
			end
			continue
		end
		if type(entry) ~= "table" then
			reject(
				"unknownField",
				`state '{state}' must be an asset name or an \{ asset, contentInsets } table (got {type(entry)})`,
				'e.g. hover = "panel-hot", or hover = { asset = "panel-hot" }'
			)
			continue
		end
		for key in entry do
			if not VARIANT_ENTRY_FIELDS[tostring(key)] then
				reject(
					"unknownField",
					`unknown variant field '{tostring(key)}' on state '{state}'`,
					`fields: {sortedNames(VARIANT_ENTRY_FIELDS)}`
				)
			end
		end
		if type(entry.asset) ~= "string" or entry.asset == "" then
			reject("missingRole", `state '{state}' declares no asset`, 'add asset = "name"')
			continue
		end
		local ci = entry.contentInsets
		if ci ~= nil then
			if type(ci) ~= "table" then
				reject(
					"invalidInset",
					`state '{state}' contentInsets must be a \{ top, right, bottom, left } table`,
					"use px numbers"
				)
				ci = nil
			else
				for _, side in package.INSET_SIDES do
					local v = (ci :: any)[side]
					if not isFiniteNumber(v) or v < 0 then
						reject(
							"invalidInset",
							`state '{state}' contentInsets.{side} must be a finite, non-negative number `
								.. `(got {tostring(v)})`,
							"content insets reserve space; a negative or NaN inset would corrupt every solve"
						)
					end
				end
			end
		end
		out[state] = { asset = entry.asset, contentInsets = if ci ~= nil then deepCopy(ci) else nil }
	end
	-- NO REFLOW ON A STATE CHANGE. An image swap moves zero geometry in the
	-- engine (rs-m6 measured AbsoluteSize byte-stable across 30 frames), so the
	-- only way a hover could relayout the tree is a variant reserving a
	-- different content box. A state that declares no insets is compared as
	-- ZERO, which is what it would reserve — so "only one state declared them"
	-- fails here rather than on a device.
	local anyInsets = false
	for _, state in declared do
		anyInsets = anyInsets or (out[state] ~= nil and out[state].contentInsets ~= nil)
	end
	if anyInsets then
		local reference: any = nil
		local referenceState = ""
		for _, state in declared do
			local entry = out[state]
			if entry == nil then
				continue
			end
			local ci = entry.contentInsets or { top = 0, right = 0, bottom = 0, left = 0 }
			if reference == nil then
				reference, referenceState = ci, state
				continue
			end
			for _, side in package.INSET_SIDES do
				if (ci[side] or 0) ~= (reference[side] or 0) then
					reject(
						"invalidInset",
						`state '{state}' reserves {tostring(ci[side] or 0)}px on '{side}' where state `
							.. `'{referenceState}' reserves {tostring(reference[side] or 0)}px — a variant may declare `
							.. `contentInsets only if they are identical across states on axis '{INSET_AXIS[side]}', `
							.. "because a differing reservation would RELAYOUT the tree on hover",
						`give every state the same {side} inset, or move the reservation to the recipe's own `
							.. "contentInsets and let the art differ inside it"
					)
				end
			end
		end
	end
	if #errors > 0 then
		return nil, errors
	end
	return out, errors
end

-- variantAsset(variant, state) -> the asset name painted in `state`. Unstated
-- states fall back to `default` (with the existing per-state TINT rules still
-- applying on top of the defaulted art), which is what lets an author supply
-- exactly as much art as they have.
function package.variantAsset(variant: any, state: string?): string?
	if type(variant) ~= "table" then
		return nil
	end
	local entry = if state ~= nil then variant[state] else nil
	entry = entry or variant.default
	return if type(entry) == "table" then entry.asset else nil
end

-- the states a variant declares, in the canonical order (never hash order, so
-- rule emission and stamps are deterministic)
function package.variantStates(variant: any): { string }
	local out: { string } = {}
	if type(variant) ~= "table" then
		return out
	end
	for _, state in package.VARIANT_STATES do
		if variant[state] ~= nil then
			table.insert(out, state)
		end
	end
	return out
end

-- ===== semantic ICONS (ADR-0020 R4) ========================================
--
-- THE FALLBACK GLYPH TABLE. A theme with no icon for a requested name renders
-- the glyph through the theme's own font, so a control never has to know an
-- asset id and a package never has to be complete.
--
-- EVERY GLYPH IS PLAIN ASCII, and that is the whole point. The sci-fi package's
-- follow-ups caret was a PRIVATE-USE codepoint: nothing in the font had it, the
-- engine drew tofu, and no test could see it. Geometric-shape codepoints (▸ ▾)
-- are the same hazard one step milder — present in some faces, missing in
-- others. ASCII is the only range every Roblox font is guaranteed to draw, so
-- the fallback is legible by construction rather than by luck.
package.ICON_FALLBACK_GLYPHS = table.freeze({
	["chevron.leading"] = "<",
	["chevron.trailing"] = ">",
	["chevron.up"] = "^",
	["chevron.down"] = "v",
	-- a tick is a v-stroke; the same character reads correctly in a checkbox
	["checkmark"] = "v",
	["close"] = "x",
	["increment"] = "+",
	["decrement"] = "-",
	["menu"] = "=",
	["more"] = "...",
	-- a pencil reduced to its dominant stroke, the same move that made the
	-- checkmark a `v` and the menu an `=`. Chosen 2026-07-27 with the standard
	-- icon set; it is the ONE name the framework added, so it is the one mark
	-- that had to be invented rather than inherited. It collides with nothing
	-- already in this table.
	["edit"] = "/",
	-- row-actions stage, 2026-08-11; CORRECTED after the device bug round
	-- 2026-08-12 (finding A4). These shipped as `U` and `P` — argued at the time
	-- as "a waste bin's own silhouette" and "a pole with a pennant". On a real
	-- phone, under Pixel Quest (a package that declines the framework art rung,
	-- so the character is what renders), they read as exactly what they are:
	-- the letters U and P sitting where an icon belongs. A letter in an icon's
	-- place is a SILENT wrong result — nothing errors, nothing is missing, the
	-- control simply says something else — which is the class this library ranks
	-- above every missing convenience.
	--
	-- THE RULE THIS TABLE NOW KEEPS (pinned by tests/compact_label.spec.luau):
	-- no entry may contain an UPPERCASE ASCII letter. A lowercase mark can be a
	-- stroke shape the eye reads as a picture — `v` is a tick, `x` is a cross,
	-- both centuries older than this table — but a capital reads as an INITIAL
	-- standing in for a word, which is a caption, not an icon. `\_/` is an open,
	-- tapered container (the bin), `|>` is a pole flying a pennant (the flag);
	-- multi-character marks are already precedented here by `more`'s `...`.
	-- Neither collides with anything already in this table.
	["trash"] = "\\_/",
	["flag"] = "|>",
})

-- isSafeGlyph(s): plain ASCII and nothing else. Falsifiable — a private-use
-- codepoint, a geometric shape and an emoji all fail it.
function package.isSafeGlyph(glyph: any): boolean
	if type(glyph) ~= "string" or glyph == "" then
		return false
	end
	for i = 1, #glyph do
		local byte = string.byte(glyph, i)
		if byte < 32 or byte > 126 then
			return false
		end
	end
	return true
end

-- an icon name is a framework semantic name or a namespaced `ns:name` (the same
-- contribution convention checkCoverage speaks). Anything else is a typo, and a
-- typo'd icon name is an icon that silently never resolves.
function package.isIconName(name: any): boolean
	if type(name) ~= "string" or name == "" then
		return false
	end
	if (package.ICON_FALLBACK_GLYPHS :: any)[name] ~= nil then
		return true
	end
	return string.match(name, "^[%a][%w_]*:[%a][%w_%.]*$") ~= nil
end

-- resolveIcon(pkg, name, state?) -> what to draw for a semantic icon name.
--   { source = "asset", name, state, assetName, contentId, tintRole? }
--   { source = "glyph", name, glyph }
--   nil                                    the name means nothing at all
-- PURE and O(1): the adapter calls this on every icon sync and paints the answer.
-- Per-state variants fall back to `default` exactly as slot art does.
--
-- IT READS A COMPILED SIBLING, NOT THE AUTHORED MAP (architecture verifier F6).
-- `themes.define` normalizes every icon reference through `normalizeAssetRef` —
-- the same wall slot art goes through, rejecting a map with no `default` and a
-- state naming an undeclared asset — and stores the RESOLVED art beside the
-- authored `icons` field. So this function has nothing left to validate: it used
-- to re-run the normalizer per call and then silently fall through to the glyph
-- when the entry looked wrong, which meant a malformed entry that got past
-- `define` would have rendered as "no theme art" rather than as a compile error.
-- The authored `icons` field is untouched, so exported data and stamps do not
-- move.
function package.resolveIcon(pkg: any, name: string, state: string?): any
	local art = if type(pkg) == "table" and type(pkg.iconArt) == "table" then pkg.iconArt else nil
	local resolved = if art ~= nil then (art :: any)[name] else nil
	if resolved ~= nil then
		local declaredState = if state ~= nil and resolved[state] ~= nil then state else "default"
		local entry = resolved[declaredState]
		return {
			source = "asset",
			name = name,
			state = declaredState,
			assetName = entry.assetName,
			contentId = entry.contentId,
			tintRole = entry.tintRole,
		}
	end
	-- THE FRAMEWORK RUNG (compact-label stage, 2026-07-27). A package that
	-- declares nothing for this name used to mean "draw the ASCII character";
	-- it now means "draw the framework's own picture, and keep the character as
	-- the floor beneath it". The package still wins outright above, so this can
	-- only ever fill a gap. `identity.standardIcons = false` declines the rung,
	-- which is how a pixel package (whose smooth-art problem is real) and the two
	-- deliberate glyph demonstrations keep drawing characters.
	--
	-- The framework's own art carries no per-state variants: it is one silhouette
	-- the theme tints, so every state resolves to the same picture. A package that
	-- wants a hover variant declares one and takes the rung above.
	local identity = if type(pkg) == "table" then pkg.identity else nil
	local optedOut = type(identity) == "table" and (identity :: any).standardIcons == false
	if not optedOut then
		local framework = standard_icons.resolve(name)
		if framework ~= nil then
			return {
				source = "asset",
				name = name,
				state = "default",
				assetName = framework.assetName,
				contentId = framework.contentId,
				tintRole = framework.tintRole,
			}
		end
	end
	local glyph = package.iconGlyph(name)
	if glyph ~= nil then
		return { source = "glyph", name = name, glyph = glyph }
	end
	return nil
end

-- iconGlyph(name): the framework's ASCII-safe character for a semantic icon
-- name, or nil for a name it does not know.
--
-- THIS IS WHAT A CONTROL DRAWS. A control authors the glyph as its own node text
-- and declares the semantic name beside it on the decoration hint; the adapter
-- then paints theme ART over it when the installed package declares any. That
-- order is deliberate and is the whole tofu fix: the legible character is in the
-- tree from the moment the control is built, chosen from a table that is plain
-- ASCII by construction, and NO resolution has to succeed for it to render. The
-- sci-fi caret was the opposite arrangement — a codepoint the control chose,
-- present in some faces and absent in the one that package installed.
function package.iconGlyph(name: string): string?
	local known = (package.ICON_FALLBACK_GLYPHS :: any)[name]
	if known ~= nil then
		return known
	end
	-- THE NAMESPACED RUNG (2026-08-08, reference-app matrix). The api contract
	-- has always said a `ns:name` icon draws an ASCII-safe glyph immediately so
	-- the affordance is legible before any package ships art — but only the
	-- table names ever resolved, and the renderer's `or props.label` fallback
	-- painted a full accessible label into a 44px disc. A namespaced name now
	-- derives its floor: the first LETTER after the namespace, uppercased —
	-- ASCII by construction, curated names above always win, and a plain
	-- unknown name stays nil (the schema keeps it a construction error).
	local after = string.match(name, "^[%w_%-]+:(.+)$")
	if after ~= nil then
		local ch = string.match(after, "%a")
		if ch ~= nil then
			return string.upper(ch)
		end
	end
	return nil
end

package.ICON_SIZE_ROLES = table.freeze({ "small", "medium", "large" })

-- ===== PIXEL-ART mode (ADR-0020 R5) ========================================

package.RENDERING_MODES = table.freeze({ "standard", "pixel" })

function package.isPixelPackage(pkg: any): boolean
	return type(pkg) == "table" and type(pkg.identity) == "table" and pkg.identity.rendering == "pixel"
end

-- the declared integer coordinate system, or nil for a package that never asked
-- for one (so a caller can skip the whole path rather than snap to 1)
function package.pixelUnitOf(pkg: any): number?
	if not package.isPixelPackage(pkg) then
		return nil
	end
	local unit = (pkg.identity :: any).pixelUnit
	return if isFiniteNumber(unit) then unit else nil
end

-- snapToPixelUnit(value, unit): the snapshot-metric snap. UP to the next unit
-- multiple, never down — the ADR-0019 precedent that floors clamp up, so an
-- accessibility floor survives the snap instead of being rounded through.
-- The epsilon exists because a metric that is ALREADY a multiple must not be
-- bumped a whole unit by float noise (44/4 = 10.999999999999998 in the wrong
-- arithmetic order is how that happens).
function package.snapToPixelUnit(value: number, unit: number): number
	assert(isFiniteNumber(value), "package.snapToPixelUnit: value must be a finite number")
	assert(
		isFiniteNumber(unit) and unit >= 1 and unit % 1 == 0,
		`package.snapToPixelUnit: the pixel unit must be an integer >= 1 (got {tostring(unit)})`
	)
	return math.ceil(value / unit - 1e-9) * unit
end

function package.define(def: any): (any, any)
	local errors: { Error } = {}
	local missing: { string } = {}
	local function reject(class: string, field: string, message: string, fix: string)
		table.insert(errors, { class = class, field = field, message = message, fix = fix })
	end
	local function need(field: string, value: any, fix: string)
		if value == nil then
			table.insert(missing, field)
			reject("missingRole", field, `required value '{field}' is missing`, fix)
			return false
		end
		return true
	end

	if type(def) ~= "table" then
		reject("unknownField", "<root>", "a theme package definition must be a table", "pass a plain Luau table")
		return nil, { ok = false, missing = missing, contrast = {}, errors = errors }
	end

	-- (0) NO CALLBACKS ANYWHERE. Checked first and over the WHOLE definition: a
	-- theme must stay inspectable, serializable and safe for an agent to edit, and
	-- one stray function would make every downstream promise conditional.
	-- DEPTH 64, not 12: a real authoring tree (a derived base, a builder's own
	-- nesting, a namespaced control section) passes 12 easily, and a function at
	-- depth 15 compiled CLEAN — the scan simply stopped looking. The visited set
	-- is what makes the deeper walk safe: a definition holding a back-pointer to
	-- itself would otherwise re-walk to the cap on every reference.
	local scanned: { [any]: boolean } = {}
	local function scanForFunctions(node: any, path: string, depth: number)
		if depth > 64 or scanned[node] then
			return
		end
		scanned[node] = true
		for k, v in node do
			local where = `{path}.{tostring(k)}`
			if type(v) == "function" then
				reject(
					"callback",
					where,
					"a theme package may not contain functions — themes are declarative data",
					"remove the callback; express the intent as a metric, a chrome recipe, or a style rule"
				)
			elseif type(v) == "table" then
				scanForFunctions(v, where, depth + 1)
			end
		end
	end
	scanForFunctions(def, "def", 0)

	for key in def do
		if not SECTIONS[tostring(key)] then
			local hint = nearest(tostring(key), SECTIONS)
			reject(
				"unknownField",
				tostring(key),
				`unknown package section '{tostring(key)}'`,
				if hint ~= nil
					then `did you mean '{hint}'? sections: {sortedNames(SECTIONS)}`
					else `sections: {sortedNames(SECTIONS)}`
			)
		end
	end

	-- (1) derivation: everything below validates the MERGED definition, so a
	-- derived package is gated exactly as strictly as a standalone one.
	local base = def.base
	if base ~= nil and (type(base) ~= "table" or base.schema ~= package.SCHEMA) then
		reject(
			"schemaVersion",
			"base",
			"`base` must be a package compiled by themes.define",
			"pass the value themes.define(...) returned (or Facet.themes.neutralPackage())"
		)
		base = nil
	end
	local merged: any = {
		identity = def.identity,
		style = if base ~= nil then inherit(base.style, def.style) else def.style,
		metrics = if base ~= nil then inherit(base.metrics, def.metrics) else def.metrics,
		chrome = if base ~= nil then inherit(base.chrome, def.chrome) else def.chrome,
		assets = if base ~= nil then inherit(base.assets, def.assets) else def.assets,
		-- a derived package inherits its base's icon map and overrides by name,
		-- exactly as it does with chrome recipes
		icons = if base ~= nil then inherit(base.icons, def.icons) else def.icons,
		compatibility = if base ~= nil then inherit(base.compatibility, def.compatibility) else def.compatibility,
	}

	-- (2) identity
	local identity = merged.identity
	if type(identity) ~= "table" then
		reject(
			"missingRole",
			"identity",
			"identity section is required",
			"add { id, displayName, schemaVersion, version }"
		)
		identity = {}
	else
		for key in identity do
			if not IDENTITY_FIELDS[tostring(key)] then
				reject(
					"unknownField",
					`identity.{tostring(key)}`,
					`unknown identity field '{tostring(key)}'`,
					`fields: {sortedNames(IDENTITY_FIELDS)}`
				)
			end
		end
	end
	need("identity.id", identity.id, 'a stable slug, e.g. "fantasy-parchment"')
	need("identity.displayName", identity.displayName, "the name a designer sees in the Style Editor")
	need("identity.version", identity.version, 'a semver string, e.g. "1.0.0"')
	if identity.schemaVersion ~= nil and identity.schemaVersion ~= package.SCHEMA then
		reject(
			"schemaVersion",
			"identity.schemaVersion",
			`package declares schema '{tostring(identity.schemaVersion)}' but this Facet speaks '{package.SCHEMA}'`,
			`set schemaVersion = "{package.SCHEMA}" and re-validate the package against this version`
		)
	elseif identity.schemaVersion == nil then
		need("identity.schemaVersion", nil, `set schemaVersion = "{package.SCHEMA}"`)
	end

	-- PIXEL-ART MODE (ADR-0020 R5). Three generation rules follow from these two
	-- fields — Pixelated on every image rule, integer SliceScale, and metric
	-- snapping to the unit — so both are checked here, before any of them runs.
	local rendering = identity.rendering
	local pixelUnit = identity.pixelUnit
	if rendering ~= nil and rendering ~= "standard" and rendering ~= "pixel" then
		reject(
			"unknownField",
			"identity.rendering",
			`unknown rendering mode '{tostring(rendering)}'`,
			`rendering is {table.concat(package.RENDERING_MODES, " | ")} (omit it for "standard")`
		)
	elseif rendering == "pixel" then
		if pixelUnit == nil then
			reject(
				"missingRole",
				"identity.pixelUnit",
				'a pixel package must declare its pixel unit: rendering = "pixel" is what turns on integer '
					.. "metric snapping, and the snap has nothing to snap to without a unit",
				"pixelUnit = 2 (a 2x pixel-art package), 3, 4 …"
			)
			table.insert(missing, "identity.pixelUnit")
		elseif not isFiniteNumber(pixelUnit) or pixelUnit < 1 or (pixelUnit :: number) % 1 ~= 0 then
			reject(
				"unknownField",
				"identity.pixelUnit",
				`pixelUnit must be an integer >= 1 (got {tostring(pixelUnit)})`,
				"the unit is the package's integer coordinate system; a fractional one would snap metrics to "
					.. "fractions, which is the blur this mode exists to remove"
			)
		end
	elseif pixelUnit ~= nil then
		reject(
			"unknownField",
			"identity.pixelUnit",
			"pixelUnit does nothing without a pixel package — metric snapping, the Pixelated stamp and the "
				.. "integer SliceScale lock all key on rendering",
			'add rendering = "pixel", or remove pixelUnit'
		)
	end

	-- (3) compatibility
	local compatibility = merged.compatibility
	if compatibility ~= nil then
		if type(compatibility) ~= "table" then
			reject("unknownField", "compatibility", "compatibility must be a table", "use { requiresSchema = ... }")
			compatibility = nil
		else
			for key in compatibility do
				if not COMPATIBILITY_FIELDS[tostring(key)] then
					reject(
						"unknownField",
						`compatibility.{tostring(key)}`,
						`unknown compatibility field '{tostring(key)}'`,
						`fields: {sortedNames(COMPATIBILITY_FIELDS)}`
					)
				end
			end
			if compatibility.requiresSchema ~= nil and compatibility.requiresSchema ~= package.SCHEMA then
				reject(
					"schemaVersion",
					"compatibility.requiresSchema",
					`package requires schema '{tostring(compatibility.requiresSchema)}'; this Facet provides '{package.SCHEMA}'`,
					"upgrade Facet, or republish the package against the schema this build speaks"
				)
			end
		end
	end

	-- (4) metrics
	local metrics = merged.metrics
	if type(metrics) ~= "table" then
		reject(
			"missingRole",
			"metrics",
			"metrics section is required",
			"start from Facet.themes.neutralPackage() as `base`"
		)
		metrics = {}
	else
		for key in metrics do
			if not METRIC_SECTIONS[tostring(key)] then
				local hint = nearest(tostring(key), METRIC_SECTIONS)
				reject(
					"unknownField",
					`metrics.{tostring(key)}`,
					`unknown metrics section '{tostring(key)}'`,
					if hint ~= nil then `did you mean '{hint}'?` else `sections: {sortedNames(METRIC_SECTIONS)}`
				)
			end
		end
	end

	local typography = if type(metrics.typography) == "table" then metrics.typography else {}
	for _, role in package.TYPE_ROLES do
		local entry = typography[role]
		-- an OPTIONAL weight role (`strong`/`numeral`) that was not authored is
		-- derived in `snapshot.resolve`, so its absence is not a gap; anything the
		-- package DID author is validated exactly as a required role is
		if entry == nil and (package.DERIVED_TYPE_ROLES :: any)[role] ~= nil then
			continue
		end
		if
			not need(
				`metrics.typography.{role}`,
				entry,
				"{ font = { family = ... }, size = <px>, lineHeight = <factor> }"
			)
		then
			continue
		end
		if type(entry) ~= "table" then
			reject(
				"missingRole",
				`metrics.typography.{role}`,
				"a typography role must be a table",
				"{ font = { family = ... }, size = <px>, lineHeight = <factor> }"
			)
			continue
		end
		for key in entry do
			if not TYPOGRAPHY_FIELDS[tostring(key)] then
				reject(
					"unknownField",
					`metrics.typography.{role}.{tostring(key)}`,
					`unknown typography field '{tostring(key)}'`,
					`fields: {sortedNames(TYPOGRAPHY_FIELDS)}`
				)
			end
		end
		if not isFiniteNumber(entry.size) or entry.size <= 0 then
			reject(
				"missingRole",
				`metrics.typography.{role}.size`,
				`size must be a positive number (got {tostring(entry.size)})`,
				"give the role its authored pixel size, e.g. size = 16"
			)
		end
		if not isFiniteNumber(entry.lineHeight) or entry.lineHeight <= 0 then
			reject(
				"missingRole",
				`metrics.typography.{role}.lineHeight`,
				`lineHeight must be a positive factor (got {tostring(entry.lineHeight)})`,
				"1.2 is the Facet default line-height factor"
			)
		end
		if type(entry.font) ~= "table" or type(entry.font.family) ~= "string" or entry.font.family == "" then
			reject(
				"missingRole",
				`metrics.typography.{role}.font`,
				"font must be { family = <string>, weight? , style? }",
				"declare the family so measurement can key on the effective font descriptor"
			)
		else
			for key in entry.font do
				if not FONT_FIELDS[tostring(key)] then
					reject(
						"unknownField",
						`metrics.typography.{role}.font.{tostring(key)}`,
						`unknown font field '{tostring(key)}'`,
						`fields: {sortedNames(FONT_FIELDS)}`
					)
				end
			end
			if not package.isResolvableFontFamily(entry.font.family) then
				reject(
					"fontFamily",
					`metrics.typography.{role}.font.family`,
					`font family '{tostring(entry.font.family)}' cannot be resolved: measurement knows only the `
						.. `registered aliases and paint hands anything else to Font.new, which accepts it and `
						.. "silently substitutes — so the solver would reserve one face while the engine drew another",
					`use a content URL ("rbxasset://fonts/families/<Family>.json" or "rbxassetid://<id>"), or one of `
						.. `the registered aliases: {table.concat(package.FONT_FAMILY_ALIASES, ", ")}`
				)
			end
		end
	end
	for role in typography do
		local known = false
		for _, name in package.TYPE_ROLES do
			known = known or name == role
		end
		if not known then
			reject(
				"unknownField",
				`metrics.typography.{tostring(role)}`,
				`unknown typography role '{tostring(role)}'`,
				`v1 roles: {table.concat(package.TYPE_ROLES, " | ")}`
			)
		end
	end

	local space = if type(metrics.space) == "table" then metrics.space else {}
	for _, step in package.REQUIRED_SPACE_STEPS do
		if
			need(`metrics.space.{step}`, space[step], "a pixel step, e.g. xs = 4") and not isFiniteNumber(space[step])
		then
			reject(
				"invalidInset",
				`metrics.space.{step}`,
				`space step must be a finite number (got {tostring(space[step])})`,
				"use a positive pixel value"
			)
		end
	end

	local controlSizes = if type(metrics.controlSizes) == "table" then metrics.controlSizes else {}
	for _, size in package.REQUIRED_CONTROL_SIZES do
		local entry = controlSizes[size]
		if not need(`metrics.controlSizes.{size}`, entry, "{ height, paddingX, iconSize }") then
			continue
		end
		for _, field in package.CONTROL_SIZE_FIELDS do
			if not isFiniteNumber((entry :: any)[field]) then
				reject(
					"missingRole",
					`metrics.controlSizes.{size}.{field}`,
					`controlSizes.{size}.{field} must be a finite number`,
					"declare height, paddingX and iconSize for every control size"
				)
			end
		end
	end

	local controls = if type(metrics.controls) == "table" then metrics.controls else {}
	for family, fields in package.CONTROL_FAMILIES do
		local entry = controls[family]
		if entry == nil then
			reject(
				"missingRole",
				`metrics.controls.{family}`,
				`no metrics for the '{family}' control family`,
				`declare {table.concat(fields, ", ")} (or derive from Facet.themes.neutralPackage())`
			)
			table.insert(missing, `metrics.controls.{family}`)
			continue
		end
		for _, field in fields do
			if not isFiniteNumber((entry :: any)[field]) then
				reject(
					"missingRole",
					`metrics.controls.{family}.{field}`,
					`controls.{family}.{field} must be a finite number`,
					`the '{family}' control resolves this metric on every solve`
				)
			end
		end
		local optional: { string } = (package.CONTROL_FAMILY_OPTIONAL :: any)[family] or {}
		for _, field in optional do
			-- optional to DECLARE, but a declared one is still a metric: a
			-- non-number here would resolve to nil and silently zero a size
			if (entry :: any)[field] ~= nil and not isFiniteNumber((entry :: any)[field]) then
				reject(
					"missingRole",
					`metrics.controls.{family}.{field}`,
					`controls.{family}.{field} must be a finite number`,
					`omit it to inherit the framework default, or give it a number`
				)
			end
		end
		for key in entry do
			local known = false
			for _, field in fields do
				known = known or field == key
			end
			for _, field in optional do
				known = known or field == key
			end
			if not known then
				reject(
					"unknownField",
					`metrics.controls.{family}.{tostring(key)}`,
					`unknown '{family}' metric '{tostring(key)}'`,
					`fields: {table.concat(fields, " | ")}`
						.. (if #optional > 0 then ` (optional: {table.concat(optional, " | ")})` else "")
				)
			end
		end
	end
	for family in controls do
		if package.CONTROL_FAMILIES[family] == nil then
			reject(
				"unknownField",
				`metrics.controls.{tostring(family)}`,
				`unknown control family '{tostring(family)}'`,
				"v1 families are closed; a custom control registers namespaced roles instead"
			)
		end
	end

	for _, name in package.REQUIRED_RADII do
		if metrics.radii == nil or not isFiniteNumber(metrics.radii[name]) then
			reject("missingRole", `metrics.radii.{name}`, `radii.{name} must be a finite number`, "e.g. control = 8")
			table.insert(missing, `metrics.radii.{name}`)
		end
	end
	for _, name in package.REQUIRED_STROKES do
		if metrics.strokes == nil or not isFiniteNumber(metrics.strokes[name]) then
			reject(
				"missingRole",
				`metrics.strokes.{name}`,
				`strokes.{name} must be a finite number`,
				"e.g. hairline = 1"
			)
			table.insert(missing, `metrics.strokes.{name}`)
		end
	end
	for _, name in package.REQUIRED_MOTION do
		if metrics.motion == nil or not isFiniteNumber(metrics.motion[name]) then
			reject(
				"missingRole",
				`metrics.motion.{name}`,
				`motion.{name} must be a finite duration`,
				"e.g. fast = 0.12"
			)
			table.insert(missing, `metrics.motion.{name}`)
		end
	end

	-- ICON METRIC ROLES (ADR-0020 R4). Optional as a section — a package with no
	-- icons sizes nothing — but closed once declared: an unknown role is a size
	-- no control will ever ask for.
	if metrics.iconSizes ~= nil then
		if type(metrics.iconSizes) ~= "table" then
			reject(
				"unknownField",
				"metrics.iconSizes",
				"iconSizes must be a table of metric roles",
				`roles: {table.concat(package.ICON_SIZE_ROLES, " | ")} — e.g. iconSizes = \{ small = 12, large = 24 }`
			)
		else
			for role, value in metrics.iconSizes do
				local known = false
				for _, name in package.ICON_SIZE_ROLES do
					known = known or name == role
				end
				if not known then
					reject(
						"unknownField",
						`metrics.iconSizes.{tostring(role)}`,
						`unknown icon size role '{tostring(role)}'`,
						`roles: {table.concat(package.ICON_SIZE_ROLES, " | ")}`
					)
				elseif not isFiniteNumber(value) or value <= 0 then
					reject(
						"missingRole",
						`metrics.iconSizes.{tostring(role)}`,
						`iconSizes.{tostring(role)} must be a positive number (got {tostring(value)})`,
						"icons resize with the snapshot, so this is the px an icon in that role draws at"
					)
				end
			end
		end
	end

	local minimum = if type(metrics.targetSizes) == "table" then metrics.targetSizes.minimum else nil
	if not isFiniteNumber(minimum) then
		reject(
			"missingRole",
			"metrics.targetSizes.minimum",
			"targetSizes.minimum must be a finite number",
			`declare the effective target floor (never below {package.MIN_TARGET_SIZE})`
		)
		table.insert(missing, "metrics.targetSizes.minimum")
	elseif (minimum :: number) < package.MIN_TARGET_SIZE then
		reject(
			"targetTooSmall",
			"metrics.targetSizes.minimum",
			`targetSizes.minimum is {tostring(minimum)}; the accessibility floor is {package.MIN_TARGET_SIZE}`,
			`raise it to at least {package.MIN_TARGET_SIZE} — the floor clamps UP, so a lower value would never take effect anyway`
		)
	end

	local insets = if type(metrics.insets) == "table" then metrics.insets else {}
	local insetRequired: { [string]: boolean } = {}
	for _, slot in package.REQUIRED_INSET_SLOTS do
		insetRequired[slot] = true
	end
	for _, slot in package.SLOTS do
		local entry = insets[slot]
		-- an OPTIONAL slot's absent inset means zero (see REQUIRED_INSET_SLOTS);
		-- a declared one is validated exactly like the rest
		if entry == nil and not insetRequired[slot] then
			continue
		end
		if not need(`metrics.insets.{slot}`, entry, "{ top, right, bottom, left } in px") then
			continue
		end
		if type(entry) ~= "table" then
			reject(
				"invalidInset",
				`metrics.insets.{slot}`,
				"an inset must be a { top, right, bottom, left } table",
				"use px numbers"
			)
			continue
		end
		for _, side in package.INSET_SIDES do
			local v = (entry :: any)[side]
			if not isFiniteNumber(v) or v < 0 then
				reject(
					"invalidInset",
					`metrics.insets.{slot}.{side}`,
					`inset must be a finite, non-negative number (got {tostring(v)})`,
					"content insets reserve space; a negative or NaN inset would corrupt every solve on this slot"
				)
			end
		end
		for key in entry do
			local known = false
			for _, side in package.INSET_SIDES do
				known = known or side == key
			end
			if not known then
				reject(
					"unknownField",
					`metrics.insets.{slot}.{tostring(key)}`,
					`unknown inset side '{tostring(key)}'`,
					`sides: {table.concat(package.INSET_SIDES, " | ")}`
				)
			end
		end
	end
	for slot in insets do
		local known = false
		for _, name in package.SLOTS do
			known = known or name == slot
		end
		if not known then
			reject(
				"unknownField",
				`metrics.insets.{tostring(slot)}`,
				`unknown decoration slot '{tostring(slot)}'`,
				`v1 slots: {table.concat(package.SLOTS, " | ")}`
			)
		end
	end

	-- (5) assets. CONTENT ADOPTION (ADR-0020 R6): `content` is canonical,
	-- `contentId` is the kept alias, and both land on ONE plain string in the
	-- compiled package — `contentId`, because that is the field every existing
	-- reader already resolves and forking the name would fork the resolution
	-- path this ruling exists to keep single.
	local assets = if type(merged.assets) == "table" then merged.assets else {}
	local normalizedAssets: { [string]: any } = {}
	for name, entry in assets do
		if type(entry) ~= "table" then
			reject(
				"unknownField",
				`assets.{tostring(name)}`,
				"an asset entry must be a table",
				`fields: {sortedNames(ASSET_FIELDS)}`
			)
			continue
		end
		local declared = entry.content
		if declared ~= nil and entry.contentId ~= nil then
			reject(
				"unknownField",
				`assets.{tostring(name)}.content`,
				"an asset declares both `content` and `contentId`; they are the same field under two names, "
					.. "so two values here is two sources of truth for one string",
				"keep `content` (the canonical name) and delete `contentId`"
			)
		end
		if declared == nil then
			declared = entry.contentId
		end
		if type(declared) ~= "string" or declared == "" then
			reject(
				"missingRole",
				`assets.{tostring(name)}.content`,
				"an asset must declare its content URI",
				'e.g. content = "rbxassetid://123" (contentId is the legacy alias for the same field)'
			)
		end
		for key in entry do
			if not ASSET_FIELDS[tostring(key)] then
				reject(
					"unknownField",
					`assets.{tostring(name)}.{tostring(key)}`,
					`unknown asset field '{tostring(key)}'`,
					`fields: {sortedNames(ASSET_FIELDS)}`
				)
			end
		end
		-- SLICE GEOMETRY. A nine-slice's centre rect is what stretches; if it is
		-- empty or inverted the engine paints a silent blank middle and reports
		-- nothing — the art lane hit exactly that twice, at `2*border == the
		-- sliced dimension`. Checked here, where the numbers are, rather than in
		-- the adapter assert that fires on a device.
		--
		-- The recommended authoring shape for pixel art is a sliced axis of
		-- `2*border + 1` design pixels: the centre is then ONE pixel wide, which
		-- stretches uniformly by construction and structurally cannot produce the
		-- sharp-but-uneven artefact rs-m5 measured. Recommended, not enforced —
		-- a wider centre is legal and often right for non-pixel art.
		for _, side in { "width", "height" } do
			local v = (entry :: any)[side]
			if v ~= nil and (not isFiniteNumber(v) or v <= 0) then
				reject(
					"invalidSlice",
					`assets.{tostring(name)}.{side}`,
					`{side} must be a positive number of source pixels (got {tostring(v)})`,
					"declare the art's real pixel size, or omit both width and height"
				)
			end
		end
		local sc = entry.sliceCenter
		if sc ~= nil then
			local shapeOk = type(sc) == "table"
			if shapeOk then
				for _, corner in SLICE_CORNERS do
					if not isFiniteNumber((sc :: any)[corner]) then
						shapeOk = false
					end
				end
			end
			if not shapeOk then
				reject(
					"invalidSlice",
					`assets.{tostring(name)}.sliceCenter`,
					"a slice centre must be { x0, y0, x1, y1 } in source pixels",
					"measure the inner rectangle that may stretch; everything outside it holds its authored size"
				)
			else
				if sc.x1 <= sc.x0 or sc.y1 <= sc.y0 then
					reject(
						"invalidSlice",
						`assets.{tostring(name)}.sliceCenter`,
						`the slice centre has no extent ({sc.x0},{sc.y0} -> {sc.x1},{sc.y1}) — an empty centre `
							.. "stretches nothing and the engine paints a blank middle with no error anywhere",
						"reduce the border or enlarge the source so x1 > x0 and y1 > y0"
					)
				end
				local width, height = entry.width, entry.height
				if isFiniteNumber(width) and isFiniteNumber(height) then
					for _, axis in
						{
							{ name = "x", size = width, near = sc.x0, far = sc.x1, dimension = "width" },
							{ name = "y", size = height, near = sc.y0, far = sc.y1, dimension = "height" },
						}
					do
						local lead = axis.near
						local trail = axis.size - axis.far
						if lead < 0 or trail < 0 then
							reject(
								"invalidSlice",
								`assets.{tostring(name)}.sliceCenter`,
								`the slice centre falls outside the source on axis '{axis.name}' `
									.. `({axis.dimension} {tostring(axis.size)}, centre {tostring(axis.near)}..`
									.. `{tostring(axis.far)})`,
								`keep 0 <= the centre <= {axis.dimension}`
							)
						elseif lead + trail >= axis.size then
							reject(
								"invalidSlice",
								`assets.{tostring(name)}.sliceCenter`,
								`the slice borders ({tostring(lead)} + {tostring(trail)}) leave no centre on axis `
									.. `'{axis.name}' ({axis.dimension} {tostring(axis.size)}) — at `
									.. "2*border == the dimension the centre rect is EMPTY and the engine paints a "
									.. "silent blank middle",
								`reduce the border or enlarge the source: the borders must sum to less than the `
									.. `{axis.dimension}. For pixel art, a sliced axis of 2*border + 1 leaves a `
									.. "one-pixel centre, which stretches uniformly by construction"
							)
						elseif identity.rendering == "pixel" then
							local unit = identity.pixelUnit
							if isFiniteNumber(unit) and (unit :: number) >= 1 then
								for _, border in { { at = "leading", v = lead }, { at = "trailing", v = trail } } do
									if border.v % (unit :: number) ~= 0 then
										reject(
											"pixelSliceBorder",
											`assets.{tostring(name)}.sliceCenter`,
											`the {border.at} '{axis.name}' border is {tostring(border.v)}px, which is `
												.. `not a multiple of the package's pixelUnit ({tostring(unit)}) — a `
												.. "border off the pixel grid lands its art between device pixels no "
												.. "matter how the metrics snap",
											`use a multiple of {tostring(unit)}`
										)
									end
								end
							end
						end
					end
				end
			end
		end
		local out: any = {}
		for key, value in entry do
			if key ~= "content" then
				out[key] = value
			end
		end
		out.contentId = declared
		normalizedAssets[name] = out
	end
	assets = normalizedAssets

	-- (6) chrome recipes (SHAPE only here; materialization is the chrome package)
	local chrome = if type(merged.chrome) == "table" then merged.chrome else {}
	-- the NORMALIZED chrome the compiled package carries: identical to the
	-- authored table except that every asset reference written as a per-state map
	-- gains its canonical `<field>Variants` sibling. A recipe that named a bare
	-- string is copied through untouched, which is what keeps every package
	-- published before this stage byte-identical down to its content stamp.
	local chromeOut: { [string]: any } = {}
	-- assetName -> the fields that use it as SLICED art, for the pixel-mode
	-- integer SliceScale lock (a fractional scale is sharp-but-UNEVEN, rs-m5 —
	-- the worst failure mode, because captures still look crisp)
	local slicedAssetUses: { [string]: { string } } = {}
	local function noteSlicedAsset(name: any, where: string)
		if type(name) ~= "string" then
			return
		end
		local uses = slicedAssetUses[name]
		if uses == nil then
			uses = {}
			slicedAssetUses[name] = uses
		end
		table.insert(uses, where)
	end

	-- ONE asset reference, through the ONE shared normalizer (ADR-0020 R2), plus
	-- the check the normalizer cannot make: that every state's name is an asset
	-- this package actually declares. `class` is the rejection class for an
	-- undeclared name, so the nineSlice path keeps reporting exactly what it
	-- always has.
	local function normalizeAssetRef(value: any, field: string, class: string): any
		local variant, variantErrors = package.normalizeVariant(value, field)
		for _, entry in variantErrors do
			table.insert(errors, entry)
		end
		if variant == nil then
			return nil
		end
		for _, state in package.variantStates(variant) do
			local name = variant[state].asset
			if assets[name] == nil then
				reject(
					class,
					field,
					`state '{state}' names asset '{tostring(name)}', which the package does not declare`,
					"add the asset to the `assets` section (name -> { content, ... })"
				)
			end
		end
		return variant
	end

	-- The canonical sibling is written when — and only when — the author wrote a
	-- MAP. A bare string is copied through with no extra field, no extra rules
	-- and no stamp movement, which is the whole back-compatibility story; a map
	-- always gets one, even a default-only map, so every downstream reader has
	-- exactly one place to look for "which asset does this reference resolve to".
	local function variantsFor(authored: any, normalized: any): any
		return if type(authored) == "table" then normalized else nil
	end

	-- the raw theme list, for the focus colour token. Read from the MERGED style
	-- rather than from section (7)'s validated `themes`, because that runs after
	-- this one and a later-declared local is not an upvalue here — the exact
	-- shape docs/lessons/lune-circular-require-hangs.md and every review round
	-- since keeps catching.
	local function themesForFocus(): { any }
		local style_ = merged.style
		if type(style_) ~= "table" or type(style_.themes) ~= "table" then
			return {}
		end
		return style_.themes
	end

	-- THE FOCUS TREATMENT (director review 2026-07-25). Two kinds:
	--   { kind = "ring" }  the default — a hairline accent stroke, byte-identical
	--                      to what every package shipped with
	--   { kind = "glow" }  a soft halo, materialized as a UIShadow (::UIShadow
	--                      RULES are inert on 0.731, m7, so this is adapter-owned
	--                      paint exactly like a slot shadow)
	--
	-- The glow's parameters go through the SAME `styling.normalizeShadow` contract
	-- a slot shadow does, so a positive zIndex or a negative blur is a compile
	-- error rather than a throw inside the render path on a device. The COLOUR is
	-- checked separately and against EVERY theme: a `$Token` that resolves in
	-- Daylight and not in Candlelight is a glow that vanishes on a swap, and
	-- nothing about that is visible until someone looks at a device.
	local function validateFocus(recipe: any, themeList: { any })
		if type(recipe) ~= "table" then
			reject(
				"unknownField",
				"chrome.focus",
				"the focus treatment must be a table",
				'{ kind = "ring" } (the default) or { kind = "glow", color = "$Accent", blurRadius = { offset = 26 } }'
			)
			return
		end
		for key in recipe do
			if not FOCUS_FIELDS[tostring(key)] then
				reject(
					"unknownField",
					`chrome.focus.{tostring(key)}`,
					`unknown focus field '{tostring(key)}'`,
					`fields: {sortedNames(FOCUS_FIELDS)}`
				)
			end
		end
		local kind = recipe.kind
		if not chrome_slots.FOCUS_KINDS[tostring(kind)] then
			reject(
				"unknownField",
				"chrome.focus.kind",
				`unknown focus kind '{tostring(kind)}'`,
				'kind is "ring" (a hairline accent stroke) or "glow" (a soft UIShadow halo)'
			)
			return
		end
		if kind ~= "glow" then
			return -- a ring takes no parameters: it is the shipped treatment
		end
		local ok, err = pcall(styling.normalizeShadow, chrome_slots.focusShadowSpec(recipe, false))
		if not ok then
			reject(
				"invalidShadow",
				"chrome.focus",
				`the glow parameters are not a valid shadow spec: {tostring(err)}`,
				"blurRadius = { scale?, offset } is clamped non-negative and zIndex must be NEGATIVE "
					.. "(a glow renders below its node, like every UIShadow)"
			)
		end
		-- and the same check on the TEN-FOOT variant, which scales blur up: a
		-- package that passes near and fails across a room would only fail on a TV
		local okStrong, errStrong = pcall(styling.normalizeShadow, chrome_slots.focusShadowSpec(recipe, true))
		if not okStrong then
			reject(
				"invalidShadow",
				"chrome.focus",
				`the ten-foot glow variant is not a valid shadow spec: {tostring(errStrong)}`,
				"the strong profile scales blur up and transparency down; keep the near values inside the "
					.. "engine's ranges so both profiles are legal"
			)
		end
		if recipe.color == nil then
			return -- no colour declared: the adapter falls back to the accent
		end
		if type(recipe.color) == "table" then
			if chrome_slots.resolveFocusColor(recipe, {}) == nil then
				reject(
					"missingRole",
					"chrome.focus.color",
					"a literal focus colour must be { r, g, b } with three numbers",
					'use { r = .., g = .., b = .. }, or a per-theme token like "$Accent"'
				)
			end
			return
		end
		if type(recipe.color) ~= "string" then
			reject(
				"unknownField",
				"chrome.focus.color",
				`focus colour must be a "$Token" name or an \{ r, g, b } table (got {type(recipe.color)})`,
				'e.g. color = "$Accent", or a per-theme role you declared in every theme\'s `extra`'
			)
			return
		end
		if chrome_slots.paletteRoleOf(recipe.color) == nil then
			reject(
				"unknownField",
				"chrome.focus.color",
				`'{tostring(recipe.color)}' is not a token reference`,
				'a token is "$Name" — the PascalCase spelling of a palette role, e.g. "$Accent" or "$FocusGlow"'
			)
			return
		end
		local uncovered: { string } = {}
		for _, theme in themeList do
			if type(theme) == "table" and type(theme.name) == "string" then
				if chrome_slots.resolveFocusColor(recipe, theme) == nil then
					table.insert(uncovered, theme.name)
				end
			end
		end
		if #uncovered > 0 then
			reject(
				"missingRole",
				"chrome.focus.color",
				`focus colour '{tostring(recipe.color)}' resolves to nothing in theme(s) `
					.. `{table.concat(uncovered, ", ")} — a glow whose token is missing paints NOTHING, and `
					.. "that is invisible in review and obvious only on a device",
				`declare the role in every theme's \`colors\` or \`extra\` (the same place `
					.. '`chromeGradient` lives), or use a colour every theme already has such as "$Accent"'
			)
		end
	end
	-- THE LAYER STACK (ADR-0020 R1). A bounded array of layers, ordered back to
	-- front, each a fixed kind with a CLOSED geometry vocabulary. Everything this
	-- function refuses is a thing that would otherwise compile clean and paint
	-- wrong: an unknown kind (no adapter branch builds it), a field from another
	-- kind (silently ignored), a stack past the cap (unbounded instance cost), a
	-- hole in the array (a layer the adapter would skip), a sliced layer whose
	-- asset declares no slice centre (a skin that looks almost right at one size).
	local function validateLayered(slot: string, recipe: any)
		local field = `chrome.{slot}`
		if slot == "scrollbar" then
			reject(
				"unknownField",
				`{field}.kind`,
				"the scrollbar slot cannot take a layered recipe for the same reason it cannot take a nineSlice "
					.. "one: a ScrollingFrame's children live in CANVAS space, so the decoration would scroll away "
					.. "from the bar",
				'use { kind = "native" } for `scrollbar`'
			)
		end
		if slot == "barFill" then
			-- The fill is CLIPPED ART, not a layer host (rs-m4, ADR-0020 R3): its
			-- image lives inside the adapter's ClipsDescendants window at FULL
			-- track size so a percent change is one window write. The adapter
			-- therefore takes the value-display branch for this slot and returns
			-- BEFORE the layer-stack branch, so a stack declared here compiles
			-- clean and paints nothing at all — the silent-inert class this stage
			-- exists to remove. Found in P5 review, made loud here.
			reject(
				"unknownField",
				`{field}.kind`,
				"the barFill slot cannot take a layered recipe: a bar's fill is clipped whole art inside the "
					.. "adapter's percent window (rs-m4), not a layer stack, so declared layers would PAINT NOTHING",
				"put the decorative layers on `barTrack` (which is a normal decorated node and hosts a stack) and "
					.. 'keep barFill = { kind = "nineSlice", asset = … } — the `glossy-touch` package '
					.. "(examples/themes/glossy_touch.luau) is the shipped precedent: its stripe tile rides the "
					.. "TRACK, over a plain sliced fill"
			)
		end
		if recipe.asset ~= nil then
			reject(
				"layerField",
				`{field}.asset`,
				"a layered recipe carries its art on its LAYERS; a top-level asset would be a second source for "
					.. "the same paint",
				'move it into layers = { { kind = "fill", asset = … } }'
			)
		end
		if recipe.fallback ~= "native" then
			reject(
				"nineSliceFallback",
				`{field}.fallback`,
				'a layered recipe must declare fallback = "native"',
				"asset loads fail; without a declared native fallback the slot would paint nothing"
			)
		end
		local ci = recipe.contentInsets
		if ci == nil and not insetRequired[slot] then
			-- an optional-inset slot reserves nothing by default
		elseif type(ci) ~= "table" then
			reject(
				"invalidInset",
				`{field}.contentInsets`,
				"a layered recipe must declare contentInsets",
				"{ top, right, bottom, left } — these feed the snapshot and the solver"
			)
		else
			for _, side in package.INSET_SIDES do
				local v = (ci :: any)[side]
				if not isFiniteNumber(v) or v < 0 then
					reject(
						"invalidInset",
						`{field}.contentInsets.{side}`,
						`contentInsets.{side} must be a finite, non-negative number (got {tostring(v)})`,
						"the solver reserves these; a negative or NaN value would corrupt layout"
					)
				end
			end
		end

		local layers = recipe.layers
		if type(layers) ~= "table" then
			reject(
				"layerKind",
				`{field}.layers`,
				`a layered recipe must declare layers as an array (got {type(layers)})`,
				'layers = { { kind = "fill", asset = "panel" }, { kind = "frame", asset = "panel-frame" } }'
			)
			return
		end
		local count = #layers
		local keyCount = 0
		for _ in layers do
			keyCount += 1
		end
		if count == 0 then
			reject(
				"layerBounds",
				`{field}.layers`,
				"a layered recipe declares an empty stack, which paints nothing at all",
				'declare at least one layer, or use { kind = "native" }'
			)
			return
		end
		if keyCount ~= count then
			reject(
				"layerBounds",
				`{field}.layers`,
				`layers must be a contiguous array (found {keyCount} entries but {count} in sequence) — z-order IS `
					.. "array order, so a hole is a layer the adapter would silently skip",
				"declare the layers in one list with no gaps and no string keys"
			)
		end
		if count > chrome_slots.MAX_LAYERS then
			reject(
				"layerBounds",
				`{field}.layers`,
				`a slot may declare at most {chrome_slots.MAX_LAYERS} layers (got {count}) — every layer is a real `
					.. "instance per decorated node, and an unbounded stack is unbounded cost",
				`fold the stack into {chrome_slots.MAX_LAYERS} layers, or bake the constant parts into one asset`
			)
		end

		local layersOut: { any } = {}
		for index, layer in ipairs(layers) do
			local lf = `{field}.layers[{index}]`
			if type(layer) ~= "table" then
				reject("layerKind", lf, `a layer must be a table (got {type(layer)})`, '{ kind = "fill", asset = … }')
				continue
			end
			if not chrome_slots.isLayerKind(layer.kind) then
				local hint = nearest(tostring(layer.kind), LAYER_KIND_SET)
				reject(
					"layerKind",
					`{lf}.kind`,
					`unknown layer kind '{tostring(layer.kind)}'`,
					if hint ~= nil
						then `did you mean '{hint}'? kinds: {table.concat(chrome_slots.LAYER_KINDS, " | ")}`
						else `kinds: {table.concat(chrome_slots.LAYER_KINDS, " | ")}`
				)
				continue
			end
			local kind: string = layer.kind
			local allowed: any = (chrome_slots.LAYER_FIELDS :: any)[kind]
			for key in layer do
				local name = tostring(key)
				if name == "kind" or name == "asset" or allowed[name] == true or LAYER_GENERATED_FIELDS[name] then
					continue
				end
				reject(
					"layerField",
					`{lf}.{name}`,
					`a '{kind}' layer has no '{name}' field — each kind's anchoring vocabulary is closed, so a `
						.. "field from another kind would be accepted and never read",
					`fields for a '{kind}' layer: kind | asset`
						.. (if next(allowed) ~= nil then ` | {sortedNames(allowed)}` else "")
				)
			end

			local variant = normalizeAssetRef(layer.asset, `{lf}.asset`, "missingAsset")
			local scaleType = chrome_slots.layerScaleType(layer)
			local out: any = { kind = kind, asset = layer.asset }
			out.assetVariants = variantsFor(layer.asset, variant)
			for key in allowed do
				out[key] = layer[key]
			end

			-- a SLICED layer stretches, so its asset has to say where. Guessing a
			-- slice centre produces art that looks almost right at one size.
			if variant ~= nil and scaleType == "Slice" then
				for _, state in package.variantStates(variant) do
					local name = variant[state].asset
					local asset = assets[name]
					noteSlicedAsset(name, lf)
					if type(asset) == "table" and type(asset.sliceCenter) ~= "table" then
						reject(
							"nineSliceFallback",
							`{lf}.asset`,
							`a '{kind}' layer stretches, so it is nine-sliced — but asset '{tostring(name)}' `
								.. "declares no sliceCenter",
							`add sliceCenter = \{ x0, y0, x1, y1 } to assets.{tostring(name)}, or use a layer kind `
								.. "that paints whole art (corners, plaque)"
						)
					end
				end
			end

			-- THE FULL-BLEED INSET (director round 5b). Shared by the three kinds
			-- that paint the whole rect, validated once here rather than three
			-- times below: `{ x = px, y = px }`, both optional, both non-negative
			-- finite numbers, and NO other key — an `inset = { left = 6 }` that
			-- compiled and did nothing would be the accepted-and-ignored class the
			-- closed vocabulary exists to prevent. The other three kinds reject the
			-- field entirely through `LAYER_FIELDS`, above.
			if layer.inset ~= nil then
				local ok = type(layer.inset) == "table"
				if ok then
					for key, value in layer.inset :: any do
						if (key ~= "x" and key ~= "y") or not isFiniteNumber(value) or value < 0 then
							ok = false
						end
					end
				end
				if not ok then
					reject(
						"layerField",
						`{lf}.inset`,
						`inset must be a \{ x = px, y = px } table of finite, non-negative numbers `
							.. `(got {if type(layer.inset) == "table"
								then "a table with other keys or bad values"
								else type(layer.inset)})`,
						"inset = { x = 6, y = 2 } shrinks the layer symmetrically on each axis, so a repeating "
							.. "texture stops short of the plate's rounded corners"
					)
				end
			end

			-- THE FULL-BLEED MASK (director round 5c, probe rs-m9). A closed set of
			-- ONE value, for the reason PLAQUE_EDGES is one edge: rs-m9 measured a
			-- pill (UICorner scale 0.5) clipping a tiled child and measured nothing
			-- else, and a vocabulary that ships unmeasured mask shapes is how a skin
			-- ends up almost right. The other three kinds reject the field entirely
			-- through `LAYER_FIELDS`, above.
			if layer.mask ~= nil and not chrome_slots.isLayerMask(layer.mask) then
				reject(
					"layerField",
					`{lf}.mask`,
					`unknown layer mask '{tostring(layer.mask)}' — a mask decides the layer's SILHOUETTE and the `
						.. "adapter materializes one CanvasGroup per masked layer, so the set is closed to the "
						.. "shapes that have been measured",
					`masks: {table.concat(chrome_slots.LAYER_MASKS, " | ")}`
				)
			end

			-- per-kind GEOMETRY
			if kind == "corners" then
				if not isFiniteNumber(layer.size) or layer.size <= 0 then
					reject(
						"layerField",
						`{lf}.size`,
						`a corners layer must declare its ornament size in px (got {tostring(layer.size)})`,
						"size = 24 — the four ornaments are fixed-size and anchored, never stretched"
					)
				end
				for _, corner in chrome_slots.CORNER_FIELDS do
					if layer[corner] == nil then
						continue
					end
					local override = normalizeAssetRef(layer[corner], `{lf}.{corner}`, "missingAsset")
					out[`{corner}Variants`] = variantsFor(layer[corner], override)
				end
			elseif kind == "edges" then
				local sides = layer.sides
				if type(sides) ~= "table" or #sides == 0 then
					reject(
						"layerField",
						`{lf}.sides`,
						"an edges layer must name the sides it rails",
						`sides = \{ "top", "bottom" } (any of {table.concat(chrome_slots.LAYER_SIDES, " | ")})`
					)
				else
					local seen: { [string]: boolean } = {}
					for _, side in sides do
						local known = false
						for _, name in chrome_slots.LAYER_SIDES do
							known = known or name == side
						end
						if not known then
							reject(
								"layerField",
								`{lf}.sides`,
								`'{tostring(side)}' is not an edge`,
								`sides: {table.concat(chrome_slots.LAYER_SIDES, " | ")}`
							)
						elseif seen[side] then
							reject(
								"layerField",
								`{lf}.sides`,
								`side '{tostring(side)}' is declared twice, which would build the rail twice`,
								"name each side once"
							)
						end
						seen[tostring(side)] = true
					end
				end
				if not isFiniteNumber(layer.thickness) or layer.thickness <= 0 then
					reject(
						"layerField",
						`{lf}.thickness`,
						`an edges layer must declare its rail thickness in px (got {tostring(layer.thickness)})`,
						"thickness = 8"
					)
				end
				if layer.margin ~= nil and (not isFiniteNumber(layer.margin) or layer.margin < 0) then
					reject(
						"layerField",
						`{lf}.margin`,
						`margin must be a finite, non-negative number of px (got {tostring(layer.margin)})`,
						"margin = 24 insets the rail from both ends of its edge"
					)
				end
				if layer.tile ~= nil and (not isFiniteNumber(layer.tile) or layer.tile <= 0) then
					reject(
						"layerField",
						`{lf}.tile`,
						`tile must be a positive px repeat length (got {tostring(layer.tile)})`,
						"tile = 32 repeats the rail art every 32px instead of slicing it"
					)
				end
			elseif kind == "plaque" then
				local size = layer.size
				if not isPositiveSize(size) then
					reject(
						"layerField",
						`{lf}.size`,
						"a plaque layer must declare its size in px",
						"size = { w = 140, h = 36 }"
					)
				end
				local edge = if layer.edge == nil then "top" else layer.edge
				local edgeOk = false
				for _, name in chrome_slots.PLAQUE_EDGES do
					edgeOk = edgeOk or name == edge
				end
				if not edgeOk then
					reject(
						"layerField",
						`{lf}.edge`,
						`a plaque anchors to '{table.concat(chrome_slots.PLAQUE_EDGES, "' | '")}' in v1 (got `
							.. `'{tostring(edge)}') — the other edges are unproven, not forbidden: rs-m3 measured `
							.. "the top-centre overhang and nothing else",
						'edge = "top"'
					)
				end
				if layer.overhang ~= nil and (not isFiniteNumber(layer.overhang) or layer.overhang < 0) then
					reject(
						"layerField",
						`{lf}.overhang`,
						`overhang must be a finite, non-negative number of px (got {tostring(layer.overhang)})`,
						"overhang = 18 renders that much of the plaque OUTSIDE the decorated rect (rs-m3)"
					)
				end
				if layer.text ~= nil and type(layer.text) ~= "boolean" then
					reject(
						"layerField",
						`{lf}.text`,
						`text must be a boolean (got {type(layer.text)})`,
						"text = true gives the plaque a lifted label sub-slot"
					)
				end
				-- THE NAMEPLATE'S PADDING (arch verifier F2). Only meaningful with
				-- `text = true`: silently accepting it otherwise is exactly the
				-- accepted-and-ignored class this fix round exists to close.
				if layer.textInsets ~= nil then
					if layer.text ~= true then
						reject(
							"layerField",
							`{lf}.textInsets`,
							"textInsets pads the plaque's TEXT sub-slot, and this plaque declares no text",
							"add `text = true`, or remove textInsets"
						)
					elseif not isPxInsets(layer.textInsets) then
						reject(
							"layerField",
							`{lf}.textInsets`,
							`textInsets must be a \{ top, right, bottom, left } px table `
								.. `(got {type(layer.textInsets)})`,
							"textInsets = { top = 6, right = 12, bottom = 4, left = 12 } keeps a carved "
								.. "banner's border off its own title"
						)
					end
				end
			elseif kind == "tile" then
				local size = layer.tileSize
				if not isPositiveSize(size) then
					reject(
						"layerField",
						`{lf}.tileSize`,
						"a tile layer must declare its repeat size in px",
						"tileSize = { w = 32, h = 32 } — px offsets are the canonical authoring form (rs-m1 "
							.. "measured scale components as a fraction of the LABEL, not of the texture)"
					)
				end
			end
			layersOut[index] = out
		end

		local recipeOut: any = {}
		for key, value in recipe do
			recipeOut[key] = value
		end
		recipeOut.layers = layersOut
		chromeOut[slot] = recipeOut
	end

	for slot, recipe in chrome do
		-- the reserved non-slot key: validated here and skipped by everything
		-- below, which is all about decoration surfaces
		if slot == "focus" then
			validateFocus(recipe, themesForFocus())
			chromeOut[slot] = recipe
			continue
		end
		chromeOut[slot] = recipe
		local slotOk = false
		for _, name in package.SLOTS do
			slotOk = slotOk or name == slot
		end
		if not slotOk then
			reject(
				"unknownField",
				`chrome.{tostring(slot)}`,
				`unknown decoration slot '{tostring(slot)}'`,
				`v1 slots: {table.concat(package.SLOTS, " | ")} `
					.. `(plus the reserved key '{table.concat(package.CHROME_RESERVED_KEYS, "', '")}')`
			)
			continue
		end
		if type(recipe) ~= "table" then
			reject("unknownField", `chrome.{tostring(slot)}`, "a chrome recipe must be a table", '{ kind = "native" }')
			continue
		end
		for key in recipe do
			local name = tostring(key)
			if REJECTED_CROP_FIELDS[name] then
				reject(
					"unknownField",
					`chrome.{tostring(slot)}.{name}`,
					`'{name}' asks for an ImageRect crop, which probe rs-m4 REJECTED for sliced art: ImageRect and `
						.. "ScaleType=Slice both address the texture, so the nine-patch re-derives from the cropped "
						.. "rect and the end cap is cut out of mid-texture",
					"a percent fill is clipped by the adapter's ClipsDescendants window over a FULL-track-size fill "
						.. '(ADR-0020 R3); declare direction = "ltr" and let the window do it'
				)
			elseif not CHROME_FIELDS[name] then
				reject(
					"unknownField",
					`chrome.{tostring(slot)}.{name}`,
					`unknown recipe field '{name}'`,
					`fields: {sortedNames(CHROME_FIELDS)}`
				)
			elseif CHROME_FIELD_SLOTS[name] ~= nil and not CHROME_FIELD_SLOTS[name][tostring(slot)] then
				reject(
					"unknownField",
					`chrome.{tostring(slot)}.{name}`,
					`'{name}' is not a field of the '{tostring(slot)}' recipe`,
					`'{name}' is legal on: {sortedNames(CHROME_FIELD_SLOTS[name])}`
				)
			end
		end
		-- the bar family's declared geometry, checked against the vocabulary the
		-- adapter can actually anchor with
		if recipe.direction ~= nil and not chrome_slots.isBarDirection(recipe.direction) then
			reject(
				"unknownField",
				`chrome.{tostring(slot)}.direction`,
				`unknown fill direction '{tostring(recipe.direction)}'`,
				`directions: {table.concat(chrome_slots.BAR_DIRECTIONS, " | ")} — the window reveals that axis and `
					.. "the art pins its origin edge to it"
			)
		end
		-- an ornament's px box is REQUIRED, not defaulted: `barCap` and `barCenter`
		-- are whole-image tokens with no intrinsic size the solver knows about, and
		-- a 0x0 instance paints nothing while looking installed
		local needsSize = (slot == "barCap" or slot == "barCenter") and recipe.kind == "nineSlice"
		if (needsSize or recipe.size ~= nil) and not isPositiveSize(recipe.size) then
			reject(
				"invalidInset",
				`chrome.{tostring(slot)}.size`,
				`a '{tostring(slot)}' ornament must declare its px box (got {type(recipe.size)})`,
				"size = { w = 28, h = 36 } — a whole-image ornament has no intrinsic size, and a 0x0 instance "
					.. "paints nothing while looking installed"
			)
		end
		for _, field in { "startAsset", "endAsset" } do
			local named = (recipe :: any)[field]
			if named ~= nil and (type(named) ~= "string" or assets[named] == nil) then
				reject(
					"missingAsset",
					`chrome.{tostring(slot)}.{field}`,
					`{field} names '{tostring(named)}', which the package does not declare`,
					"declare it under `assets`, or omit the override and both caps paint the recipe's `asset`"
				)
			end
		end
		-- SLOT SHADOWS, on either kind of recipe. Validated HERE, against the
		-- exact contract the adapter materializes, because a shadow spec that is
		-- wrong (a positive zIndex, a negative blur) throws inside the render
		-- path on a device and nowhere else.
		if recipe.shadow ~= nil then
			if type(recipe.shadow) ~= "string" and type(recipe.shadow) ~= "table" then
				reject(
					"unknownField",
					`chrome.{tostring(slot)}.shadow`,
					`shadow must be a preset name or a parameter table (got {type(recipe.shadow)})`,
					'use shadow = "raised" | "overlay", or a { blurRadius = { offset = .. }, zIndex = -1, … } table'
				)
			else
				local ok, err = pcall(styling.normalizeShadow, recipe.shadow)
				if not ok then
					reject(
						"invalidShadow",
						`chrome.{tostring(slot)}.shadow`,
						`shadow is not a valid shadow spec: {tostring(err)}`,
						'the presets are "raised" and "overlay"; an explicit table needs blurRadius = { scale?, offset? } '
							.. "and a NEGATIVE zIndex (shadows render below the parent)"
					)
				end
			end
		end
		if recipe.sliced ~= nil and type(recipe.sliced) ~= "boolean" then
			reject(
				"unknownField",
				`chrome.{tostring(slot)}.sliced`,
				`sliced must be a boolean (got {type(recipe.sliced)})`,
				"sliced = false paints the asset whole; omit it and the slot's own nature decides"
			)
		end
		-- LAYERS BELONG TO A LAYERED RECIPE (ADR-0020 R1). Accepting them on a
		-- native or nineSlice recipe would compile a stack that never gets built:
		-- `planFor` keys on the kind, so the layers would be inert data.
		if recipe.layers ~= nil and recipe.kind ~= "layered" then
			reject(
				"layerKind",
				`chrome.{tostring(slot)}.layers`,
				`a '{tostring(recipe.kind)}' recipe cannot carry layers — only a layered recipe builds a stack`,
				'set kind = "layered" (a single-asset nineSlice recipe is exactly layers = { { kind = "fill", '
					.. "asset = … } }, so either form is legal — but the kind has to say which one this is)"
			)
		end
		if recipe.kind == "native" then
			-- nothing more to check: native recipes create zero instances
		elseif recipe.kind == "layered" then
			validateLayered(slot, recipe)
		elseif recipe.kind == "nineSlice" then
			-- the scrollbar is the one slot a decoration CHILD cannot skin: the
			-- ScrollingFrame's children live in CANVAS space, so the nine-slice
			-- would scroll away from the bar it was meant to be. Native paint (the
			-- ScrollBarImageColor3 rule) is the only correct treatment.
			if slot == "scrollbar" then
				reject(
					"unknownField",
					`chrome.{tostring(slot)}.kind`,
					"the scrollbar slot cannot take a nineSlice recipe: a ScrollingFrame's children are positioned "
						.. "in CANVAS space, so the decoration would scroll away from the bar",
					'use { kind = "native" } for `scrollbar` — the bar is painted by the sheet\'s ScrollBarImageColor3 rule'
				)
			end
			-- the asset reference goes through the ONE variant normalizer, so a
			-- nineSlice recipe takes a bare name (same art in every state) or a
			-- per-state map (ADR-0020 R2) with identical validation either way
			local variant = normalizeAssetRef(recipe.asset, `chrome.{tostring(slot)}.asset`, "nineSliceFallback")
			local recipeOut: any = {}
			for key, value in recipe do
				recipeOut[key] = value
			end
			recipeOut.assetVariants = variantsFor(recipe.asset, variant)
			chromeOut[slot] = recipeOut
			if variant ~= nil then
				local sliced = if type(recipe.sliced) == "boolean"
					then recipe.sliced
					else not chrome_slots.isWholeImageSlot(slot)
				if sliced then
					for _, state in package.variantStates(variant) do
						noteSlicedAsset(variant[state].asset, `chrome.{tostring(slot)}.asset`)
					end
				end
			end
			if recipe.fallback ~= "native" then
				reject(
					"nineSliceFallback",
					`chrome.{tostring(slot)}.fallback`,
					'a nineSlice recipe must declare fallback = "native"',
					"asset loads fail; without a declared native fallback the slot would paint nothing"
				)
			end
			local ci = recipe.contentInsets
			if ci == nil and not insetRequired[slot] then
				-- an optional-inset slot (a thumb, a seal, a rail) reserves nothing
				-- by default: there is no content inside it to clear a border for
			elseif type(ci) ~= "table" then
				reject(
					"invalidInset",
					`chrome.{tostring(slot)}.contentInsets`,
					"a nineSlice recipe must declare contentInsets",
					"{ top, right, bottom, left } — these feed the snapshot and the solver"
				)
			else
				for _, side in package.INSET_SIDES do
					local v = (ci :: any)[side]
					if not isFiniteNumber(v) or v < 0 then
						reject(
							"invalidInset",
							`chrome.{tostring(slot)}.contentInsets.{side}`,
							`contentInsets.{side} must be a finite, non-negative number (got {tostring(v)})`,
							"the solver reserves these; a negative or NaN value would corrupt layout"
						)
					end
				end
			end
		else
			reject(
				"unknownField",
				`chrome.{tostring(slot)}.kind`,
				`unknown chrome kind '{tostring(recipe.kind)}'`,
				'kind is "native", "nineSlice" or "layered"'
			)
		end
	end

	-- (6a-pre) A SLOT WHOSE PAINT IS THE INFORMATION TAKES NO ART (director round
	-- 2026-08-14; the criterion and the whole chain of facts live on
	-- `chrome_slots.acceptsArt`). The dot spinner's five plates differ ONLY in the
	-- tint the control writes each frame, and art suppresses the plate that tint
	-- paints — so a skinned spinner is five identical images that never move, with
	-- no diagnostic anywhere. Refused at compile time, with the working knobs
	-- named, rather than accepted into a rule that silently freezes the animation.
	for slot, recipe in (if type(merged.chrome) == "table" then merged.chrome else {}) :: any do
		if
			chrome_slots.isSlot(slot)
			and not chrome_slots.acceptsArt(slot)
			and type(recipe) == "table"
			and recipe.kind ~= nil
			and recipe.kind ~= "native"
		then
			reject(
				"unknownField",
				`chrome.{tostring(slot)}`,
				`'{tostring(slot)}' carries a LIVE value in its own colour — the control rewrites its tint every `
					.. "frame — and art suppresses the plate that tint paints, so a skinned one would be a frozen "
					.. "picture with nothing to report that it had stopped",
				`retune it instead: {tostring(chrome_slots.artRefusalAlternative(slot))}`
			)
		end
	end

	-- (6a) INSETS THAT LEAVE NO CONTENT BOX (RS-A16-D3, found live under
	-- pixel-quest). A value display's host extent is a METRIC the package itself
	-- resolves, so "these insets leave nothing inside" is knowable at COMPILE
	-- time — and it has to be caught somewhere, because the consequence is
	-- silent: pixel-quest declared `barTrack.contentInsets = { 8, 8, 8, 8 }` over a
	-- track this same definition resolves to 8px tall, the fill solved to
	-- max(0, 8 - 16) = 0, and the download bar drew a trough, two heart caps and
	-- no value at all with `solverDiagnostics` still reading 0.
	--
	-- Only the pairs whose extent is a resolved metric are checked here; the
	-- solver reports the rest on the live solve (an explicitly sized control, a
	-- percent extent). The metric is read from the MERGED definition and snapped
	-- like the snapshot snaps it, so the number in the message is the number the
	-- solver will use.
	for slot, host in package.VALUE_HOST_METRICS do
		local recipe = if type(merged.chrome) == "table" then merged.chrome[slot] else nil
		local ci = if type(recipe) == "table" then recipe.contentInsets else nil
		if type(ci) ~= "table" then
			continue
		end
		local near, far = (ci :: any)[host.near], (ci :: any)[host.far]
		if not isFiniteNumber(near) or not isFiniteNumber(far) then
			continue -- already rejected as an invalid inset
		end
		local family = if type(merged.metrics) == "table" and type(merged.metrics.controls) == "table"
			then merged.metrics.controls[host.family]
			else nil
		local declared = if type(family) == "table" then family[host.field] else nil
		if not isFiniteNumber(declared) then
			continue -- no metric to measure against; the solver reports it live
		end
		local unit = package.pixelUnitOf({ identity = identity })
		local extent = if unit ~= nil then package.snapToPixelUnit(declared, unit) else declared
		local eaten = if unit ~= nil
			then package.snapToPixelUnit(near, unit) + package.snapToPixelUnit(far, unit)
			else near + far
		if eaten >= extent then
			local metricPath = `controls.{host.family}.{host.field}`
			reject(
				"insetsExceedHost",
				`chrome.{slot}.contentInsets`,
				`contentInsets {host.near} + {host.far} = {eaten}px leave no content inside the {host.axis} extent `
					.. `this package resolves for {metricPath} ({extent}px), so {slot}'s content solves to ZERO `
					.. "and the control shows no value",
				`raise {metricPath} above {eaten} (the art's own minimum is 2 * its slice border + 1), `
					.. `or lower chrome.{slot}.contentInsets`
			)
		end
	end

	-- (6b) SEMANTIC ICONS (ADR-0020 R4). A map from MEANING to art, so a control
	-- asks for `chevron.trailing` and never for an asset id. A name the framework
	-- does not know (and that is not namespaced) is a typo, and a typo'd icon
	-- name is an icon that silently never resolves.
	local icons = if type(merged.icons) == "table" then merged.icons else nil
	local iconsOut: { [string]: any }? = nil
	-- the RESOLVED sibling `resolveIcon` reads (arch verifier F6): one entry per
	-- declared state, already carrying the content id and the tint role, so the
	-- adapter's per-sync call is a lookup rather than a re-normalization. Never
	-- serialized into the stamp — it is derived from `icons` + `assets`, both of
	-- which are.
	local iconArtOut: { [string]: any }? = nil
	if merged.icons ~= nil and icons == nil then
		reject(
			"unknownField",
			"icons",
			`the icons section must be a table of name -> asset reference (got {type(merged.icons)})`,
			'icons = { ["chevron.trailing"] = "caret", ["close"] = { default = "x", hover = "x-hot" } }'
		)
	elseif icons ~= nil then
		iconsOut = {}
		for name, ref in icons do
			local key = tostring(name)
			if not package.isIconName(key) then
				local known: { [string]: boolean } = {}
				for glyphName in package.ICON_FALLBACK_GLYPHS :: any do
					known[glyphName] = true
				end
				local hint = nearest(key, known)
				reject(
					"unknownField",
					`icons.{key}`,
					`'{key}' is not a semantic icon name`,
					(if hint ~= nil then `did you mean '{hint}'? ` else "")
						.. `framework names: {sortedNames(known)} — a custom control contributes a namespaced `
						.. "name instead ('ns:name'), which is the same convention themes.checkCoverage speaks"
				)
				continue
			end
			local variant = normalizeAssetRef(ref, `icons.{key}`, "missingAsset")
			if variant ~= nil then
				(iconsOut :: any)[key] = ref
				local art: { [string]: any } = {}
				for _, state in package.variantStates(variant) do
					local assetName = variant[state].asset
					local asset: any = assets[assetName]
					if type(asset) == "table" and type(asset.contentId) == "string" then
						art[state] = {
							assetName = assetName,
							contentId = asset.contentId,
							tintRole = asset.tintRole,
						}
					end
				end
				if art.default ~= nil then
					iconArtOut = iconArtOut or {}
					(iconArtOut :: any)[key] = art
				end
			end
		end
	end

	-- (6c) PIXEL MODE cross-checks (ADR-0020 R5, rs-m5). A FRACTIONAL SliceScale
	-- under Pixelated stays hard-edged but visibly UNEVEN — a thinner border on
	-- one side, non-uniform cells — which is the worst failure mode of the three
	-- because a capture still looks crisp at a glance. Locked at compile.
	if identity.rendering == "pixel" then
		local names: { string } = {}
		for name in slicedAssetUses do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in names do
			local asset = assets[name]
			local scale = if type(asset) == "table" then asset.sliceScale else nil
			if scale ~= nil and (not isFiniteNumber(scale) or (scale :: number) % 1 ~= 0) then
				reject(
					"pixelSliceScale",
					`assets.{name}.sliceScale`,
					`a pixel package slices '{name}' at {tostring(scale)}; SliceScale locks to integers under `
						.. `rendering = "pixel" (used by {table.concat(slicedAssetUses[name], ", ")}) — a `
						.. "fractional scale renders sharp-but-UNEVEN, which reads as crisp in a capture and "
						.. "wrong on the pixel grid",
					`use a whole number (the package's pixelUnit is {tostring(identity.pixelUnit)})`
				)
			end
		end
	end

	-- (7) style: colors per theme, gated by the SAME contrast/completeness rules
	-- the library's own token compiler applies (never a second, weaker gate).
	local style = merged.style
	local contrast: { any } = {}
	local themes: { any } = {}
	if type(style) ~= "table" or type(style.themes) ~= "table" or #style.themes == 0 then
		reject(
			"missingRole",
			"style.themes",
			"style.themes must be a non-empty ordered array of { name, colors }",
			'declare at least one theme, e.g. { { name = "Dark", colors = { ... } } }'
		)
	else
		for key in style do
			if not STYLE_FIELDS[tostring(key)] then
				reject(
					"unknownField",
					`style.{tostring(key)}`,
					`unknown style field '{tostring(key)}'`,
					`fields: {sortedNames(STYLE_FIELDS)}`
				)
			end
		end
		local seen: { [string]: boolean } = {}
		for index, theme in style.themes do
			if type(theme) ~= "table" or type(theme.name) ~= "string" or theme.name == "" then
				reject("missingRole", `style.themes[{index}].name`, "each theme needs a name", 'e.g. name = "Dark"')
				continue
			end
			for key in theme do
				if not THEME_FIELDS[tostring(key)] then
					reject(
						"unknownField",
						`style.themes[{index}].{tostring(key)}`,
						`unknown theme field '{tostring(key)}'`,
						`fields: {sortedNames(THEME_FIELDS)}`
					)
				end
			end
			if seen[theme.name] then
				reject(
					"unknownField",
					`style.themes[{index}].name`,
					`duplicate theme name '{theme.name}'`,
					"theme names select the active variant, so they must be unique"
				)
			end
			seen[theme.name] = true
			-- the contract gate: colors + the completeness sections tokens.compile
			-- requires, fed from this package's own metrics so ONE gate covers both
			local typeSizes: { [string]: number } = {}
			for role, entry in typography do
				if type(entry) == "table" then
					typeSizes[role] = entry.size
				end
			end
			-- only the REPORT is used: every contrast/missing-role failure is turned
			-- into an authoring error by the two loops below
			local _, report = tokens.compile(deepCopy({
				colors = theme.colors,
				type = typeSizes,
				space = space,
				radii = metrics.radii,
				strokes = metrics.strokes,
				targetSizes = metrics.targetSizes,
				motion = metrics.motion,
			}))
			for _, entry in report.contrast do
				table.insert(contrast, { theme = theme.name, pair = entry.pair, ratio = entry.ratio, ok = entry.ok })
				if not entry.ok then
					reject(
						"contrast",
						`style.themes[{index}].colors`,
						`theme '{theme.name}': {entry.pair} contrast is {entry.ratio}:1, below the 4.5:1 gate`,
						"darken the surface or lighten the content until the pair clears 4.5:1"
					)
				end
			end
			-- the danger pair rides the SAME gate sheet_model asserts at build
			-- time (using its documented library fallbacks when a theme omits the
			-- pair) — found live: a package that passed define() then threw
			-- inside sheet_model.gateTheme, which is the wrong place to learn it
			do
				local danger, onDanger = tokens.dangerPair(theme.colors)
				local ratio = tokens.contrastRatio(danger, onDanger)
				local ok = ratio >= 4.5
				table.insert(contrast, {
					theme = theme.name,
					pair = "onDanger on danger",
					ratio = math.floor(ratio * 100) / 100,
					ok = ok,
				})
				if not ok then
					reject(
						"contrast",
						`style.themes[{index}].colors.danger`,
						`theme '{theme.name}': onDanger on danger contrast is {math.floor(ratio * 100) / 100}:1, below the 4.5:1 gate`,
						"darken danger or lighten onDanger until the pair clears 4.5:1"
					)
				end
			end
			for _, field in report.missing do
				if string.sub(field, 1, 7) == "colors." then
					reject(
						"missingRole",
						`style.themes[{index}].{field}`,
						`theme '{theme.name}' is missing {field}`,
						"every theme must declare the full contract palette"
					)
					table.insert(missing, `style.themes[{index}].{field}`)
				end
			end
			-- GRADIENT READABILITY. `alpha` states engine `UIGradient.Transparency`
			-- semantics (0 = the ramp paints fully, 1 = it vanishes), which is the
			-- right authoring vocabulary — but UIGradient fades the parent's ENTIRE
			-- rendering, its engine-drawn text included. A near-1 stop therefore does
			-- not "make the wash subtle": it ghosts the whole control, label and all.
			-- Found in the stored captures at 0.72–0.96, where every themed screen
			-- read as washed out. The ceiling is a compile error because the failure
			-- is invisible in code review and obvious only on a device.
			local gradients = (theme.extra or {}).chromeGradient
			if type(gradients) == "table" then
				for slotName, entry in gradients do
					-- A WASH MAY NEVER REACH A VALUE CONTROL'S CHROME (director
					-- follow-up 2026-07-25). A gradient is a SURFACE treatment
					-- and its alpha is exactly what made a slider thumb
					-- translucent enough to see the fill through. Refused here,
					-- with the reason, rather than accepted into a rule that
					-- silently is not emitted.
					if chrome_slots.isSlot(slotName) and not chrome_slots.isGradientable(tostring(slotName)) then
						reject(
							"unknownField",
							`style.themes[{index}].extra.chromeGradient.{tostring(slotName)}`,
							`'{tostring(slotName)}' is a value control's own chrome and can never carry a gradient: `
								.. "a wash's alpha would make it see-through, and whatever the control draws behind "
								.. "it would read straight through the glass",
							`gradient the surfaces an author opted into instead `
								.. `({table.concat(package.SLOTS, ", ")} minus the value-control slots), or retune `
								.. "the slot's flat colour"
						)
					end
					if type(entry) == "table" and type(entry.alpha) == "table" then
						for index, stop in entry.alpha do
							local v = if type(stop) == "table" then stop.v else nil
							if isFiniteNumber(v) and (v :: number) > GRADIENT_ALPHA_MAX then
								reject(
									"gradientAlpha",
									`style.themes[{index}].extra.chromeGradient.{tostring(slotName)}.alpha[{index}]`,
									`theme '{theme.name}': gradient alpha stop {tostring(v)} is above the `
										.. `{GRADIENT_ALPHA_MAX} ceiling — UIGradient.Transparency fades the parent's `
										.. "ENTIRE rendering, its engine-drawn text included, so a near-1 stop ghosts "
										.. "the whole control rather than softening the wash",
									`keep every alpha stop at or below {GRADIENT_ALPHA_MAX}; a subtle ramp is 0.1–0.35`
								)
							end
						end
					end
				end
			end
			table.insert(themes, { name = theme.name, colors = theme.colors, extra = theme.extra })
		end
		if style.defaultTheme ~= nil and not seen[style.defaultTheme] then
			reject(
				"missingRole",
				"style.defaultTheme",
				`defaultTheme '{tostring(style.defaultTheme)}' names no declared theme`,
				`declared themes: {sortedNames(seen)}`
			)
		end
	end

	local report = {
		ok = #errors == 0,
		missing = missing,
		contrast = contrast,
		errors = errors,
	}
	if not report.ok then
		return nil, report
	end

	-- DEEP-COPIED, then frozen. Without the copy `deepFreeze` reached through the
	-- merged tree into the CALLER's own definition and froze it in place (found
	-- live: a builder that defines, then edits its definition and defines again,
	-- threw "attempt to modify a readonly table" from its own module). A compiled
	-- package is immutable inspectable data; the definition it was built from
	-- belongs to whoever wrote it.
	local compiled: any = {
		schema = package.SCHEMA,
		identity = deepCopy(identity),
		style = deepCopy({ defaultTheme = style.defaultTheme or themes[1].name, themes = themes }),
		metrics = deepCopy(metrics),
		-- the NORMALIZED chrome (per-state maps carry their canonical
		-- `<field>Variants` sibling); a package that named bare strings is
		-- copied through unchanged, stamp included
		chrome = deepCopy(chromeOut),
		assets = deepCopy(assets),
		icons = if iconsOut ~= nil then deepCopy(iconsOut) else nil,
		iconArt = if iconArtOut ~= nil then deepCopy(iconArtOut) else nil,
		compatibility = deepCopy(compatibility or { requiresSchema = package.SCHEMA }),
		derivedFrom = if base ~= nil then base.identity.id else nil,
	}
	local parts: { string } = {}
	serialize({
		identity = compiled.identity,
		style = compiled.style,
		metrics = compiled.metrics,
		chrome = compiled.chrome,
		assets = compiled.assets,
		-- absent for every package that declares no icons, so their stamps do
		-- not move (a nil field contributes no key to the serialization)
		icons = compiled.icons,
		compatibility = compiled.compatibility,
	}, parts)
	compiled.stamp = stampOf(parts)
	return deepFreeze(compiled), report
end

-- ===== namespaced contribution coverage (ADR-0019 §1) ======================
-- The pre-play gate for contributed controls: a control DECLARES its
-- namespaced theme needs (name "ns:role", kind, section, fields?, authority,
-- capability, fallback) and asks whether a package covers them. `define`
-- deliberately passes namespaced entries through unvalidated (they are not the
-- closed core vocabulary), so without this check a package that FORGETS a
-- contributed control is indistinguishable from one that covers it.
--
-- checkCoverage(pkg, declarations) ->
--   { ok, covered = { name }, missing = { { name, message, fix } } }
function package.checkCoverage(pkg: any, declarations: { any }): any
	assert(type(pkg) == "table" and pkg.schema == package.SCHEMA, "checkCoverage: expected a compiled package")
	assert(type(declarations) == "table", "checkCoverage: expected a list of contribution declarations")
	local covered: { string } = {}
	local missing: { any } = {}
	local function fail(name: string, message: string, fix: string)
		table.insert(missing, { name = name, message = message, fix = fix })
	end
	for index, need in declarations do
		if type(need) ~= "table" or type(need.name) ~= "string" or not string.find(need.name, ":", 1, true) then
			fail(
				`declarations[{index}]`,
				"a contribution declaration needs a namespaced `name` like 'demo:gauge'",
				"declare { name = 'ns:role', kind, section, authority, capability, fallback }"
			)
		elseif need.kind == "controlSize" then
			local entry = ((pkg.metrics or {}).controlSizes or {})[need.name]
			if type(entry) ~= "table" then
				fail(
					need.name,
					`package '{pkg.identity.id}' declares no '{need.name}' control size; the contributed control `
						.. `falls back to its built-in metrics and stops following the theme`,
					`add metrics.controlSizes["{need.name}"] = \{ height = .., paddingX = .., iconSize = .. }`
				)
			else
				local incomplete: { string } = {}
				for _, field in (need.fields or package.CONTROL_SIZE_FIELDS) :: { string } do
					if not isFiniteNumber(entry[field]) then
						table.insert(incomplete, field)
					end
				end
				if #incomplete > 0 then
					fail(
						need.name,
						`'{need.name}' is missing {table.concat(incomplete, ", ")}`,
						`declare every declared field ({table.concat(need.fields or package.CONTROL_SIZE_FIELDS, ", ")})`
					)
				else
					table.insert(covered, need.name)
				end
			end
		elseif need.kind == "color" then
			local uncovered: { string } = {}
			for _, theme in pkg.style.themes do
				local v = (theme.extra or {})[need.name]
				if
					type(v) ~= "table"
					or not isFiniteNumber(v.r)
					or not isFiniteNumber(v.g)
					or not isFiniteNumber(v.b)
				then
					table.insert(uncovered, theme.name)
				end
			end
			if #uncovered > 0 then
				fail(
					need.name,
					`theme(s) {table.concat(uncovered, ", ")} of package '{pkg.identity.id}' declare no `
						.. `'{need.name}', so the contributed control paints its built-in colour and ignores the palette`,
					`add extra["{need.name}"] = \{ r = .., g = .., b = .. } to every theme`
				)
			else
				table.insert(covered, need.name)
			end
		elseif need.kind == "number" then
			local section: any = pkg.metrics
			for part in string.gmatch(tostring(need.section or ""), "[^%.]+") do
				if part ~= "metrics" then
					section = if type(section) == "table" then section[part] else nil
				end
			end
			local v = if type(section) == "table" then section[need.name] else nil
			if not isFiniteNumber(v) then
				fail(
					need.name,
					`package '{pkg.identity.id}' declares no '{need.name}' in {tostring(need.section)}`,
					`add {tostring(need.section)}["{need.name}"] = <number>`
				)
			else
				table.insert(covered, need.name)
			end
		else
			fail(
				need.name or `declarations[{index}]`,
				`unknown contribution kind '{tostring(need.kind)}'`,
				"declare kind = 'controlSize' | 'color' | 'number'"
			)
		end
	end
	return { ok = #missing == 0, covered = covered, missing = missing }
end

return package
