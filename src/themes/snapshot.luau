--!strict
-- Theme SNAPSHOT: the one effective metric authority (ADR-0019 §2).
-- PURE and engine-free. A snapshot is a deeply frozen plain-Luau table that the
-- solver, renderer, presenter, headless suite and (later) the native
-- materializer all read, so measurement can never disagree with paint about how
-- big a thing is.
--
-- It rides `environment` as the `themeMetrics` fact: one key, one signal, one
-- downstream invalidation, so committing a theme is a single atomic `env:set`
-- and every mounted screen RE-SOLVES rather than rebuilding.
--
-- Public interface
--   snapshot.resolve(package, themeName, facts, overrides?) -> frozen snapshot
--   snapshot.neutral()          the Studio Neutral snapshot (the env default)
--   snapshot.neutralPackage()   the compiled Studio Neutral package (derivation base)
--   snapshot.resolveSize(snap, value)    typography role name | number -> px
--   snapshot.resolveNumber(snap, value)  space step | metric path | number -> px
--   snapshot.resolveSides(snap, sides)   the same, per side
--   snapshot.resolveDim(snap, dim)       the same, inside a layout dimension
--   snapshot.roleOf(snap, value)         the typography role entry, when named
--   snapshot.isTypeRole / isSpaceStep / isMetricPath   (schema validation)
--   snapshot.fontKey(font)               canonical "family#weight#style"
--   snapshot.typographyScale / typographyPaintScale / measureScale / textOffset
--                                        the TEXT-SCALE POLICY, as pure
--                                        functions of the three platform facts
--                                        (see "the text-scale policy" below)
--
-- Depends on: src/themes/package (the compiler + the closed vocabulary),
-- src/tokens/default_style (the SINGLE source of the neutral numbers).
--
-- METRIC REFERENCES. Anywhere the framework accepts a theme-owned number it also
-- accepts a NAME for it, and the name resolves here on every solve — that is why
-- a theme swap moves geometry without a rebuild. Two vocabularies:
--   * a bare name — a typography role for `textSize`, a space step elsewhere;
--   * a dotted path into this snapshot ("controls.slider.thumbSize",
--     "targetSizes.minimum", "controlSizes.large.height", "strokes.hairline").
-- A literal number stays legal and is thereby EXPLICITLY theme-independent.

local pkg = require("./package")
local chrome_slots = require("../tokens/chrome_slots")
local defaultStyle = require("../tokens/default_style")
local styling = require("../tokens/styling")

local snapshot = {}

-- ===== font descriptors ====================================================
-- Measurement keys on the EFFECTIVE font, not a short family name (ADR-0019 §6),
-- so two weights of one family can never share a cached width.

local DEFAULT_WEIGHT = "Regular"
local DEFAULT_STYLE = "Normal"

function snapshot.fontKey(font: any): string
	if type(font) ~= "table" or type(font.family) ~= "string" then
		return "BuilderSans#" .. DEFAULT_WEIGHT .. "#" .. DEFAULT_STYLE
	end
	return `{font.family}#{font.weight or DEFAULT_WEIGHT}#{font.style or DEFAULT_STYLE}`
end

-- ===== Studio Neutral ======================================================
-- Everything the library already had comes from src/tokens/default_style (ONE
-- source: the numbers are not restated here). What follows are the semantic
-- roles this stage ADDED so the framework's own controls could stop hardcoding
-- literals; each names the literal it replaced so the mapping stays auditable.

local NEUTRAL_FONT = { family = "BuilderSans", weight = DEFAULT_WEIGHT, style = DEFAULT_STYLE }
-- the global line-height factor text_metrics has always applied
local NEUTRAL_LINE_HEIGHT = 1.2

local function neutralTypography(): any
	local out: any = {}
	for _, role in pkg.REQUIRED_TYPE_ROLES do
		local size = (defaultStyle.type :: any)[role]
		if size == nil then
			-- "control": the size the renderer hardcoded for Button and TextField
			-- text (18). It sits between `body` (16) and `heading` (20); the token
			-- now lives in default_style beside the rest of the ladder, and this
			-- stays as the guard for a style that predates it.
			size = 18
		end
		out[role] = { font = table.clone(NEUTRAL_FONT), size = size, lineHeight = NEUTRAL_LINE_HEIGHT }
	end
	return out
end

local function uniformInset(px: number): any
	return { top = px, right = px, bottom = px, left = px }
end

-- SEMANTIC ICON SIZES (ADR-0020 R4). The three roles a control may ask for, in
-- px, mirroring the `controlSizes` iconSize ladder below (16/20/24) because an
-- icon inside a compact row and a compact row's icon are the same thing. They
-- ride the snapshot for one reason: a metric package must be able to RESIZE
-- icons, and anything that does not ride the snapshot cannot move on a swap.
--
-- Every package answers all three whether or not it authored any, so
-- `"iconSizes.medium"` is a resolvable metric path on every theme — a control
-- naming it can never get nil back and silently draw a zero-size picture.
local NEUTRAL_ICON_SIZES = table.freeze({ small = 16, medium = 20, large = 24 })

-- THE SMALLEST SCREEN-EDGE GUTTER ANY PACKAGE MAY RESOLVE TO. 8px is the step
-- the neutral scale already names `s`, and the floor under `space.gutter` in
-- `resolve` — see the long note there for why this is a derived step rather than
-- a raised `space.s`.
local SCREEN_GUTTER_FLOOR = 8
snapshot.SCREEN_GUTTER_FLOOR = SCREEN_GUTTER_FLOOR

local function neutralDefinition(): any
	local style = defaultStyle :: any
	return {
		identity = {
			id = "studio-neutral",
			displayName = "Studio Neutral",
			schemaVersion = pkg.SCHEMA,
			version = "1.0.0",
		},
		style = {
			defaultTheme = "Dark",
			themes = { { name = "Dark", colors = style.colors, extra = style.extra } },
		},
		metrics = {
			typography = neutralTypography(),
			space = style.space,
			-- control sizes: the three row heights the framework already drew.
			-- compact 36 = PopupButton's menu row; regular 44 = its inline row and
			-- the touch floor; large 56 = its touch-sheet row. paddingX/iconSize
			-- follow the same ladder (Label's icon default was a hardcoded 20).
			controlSizes = {
				compact = { height = 36, paddingX = style.space.s, iconSize = 16 },
				regular = { height = style.targetSizes.minimum, paddingX = 12, iconSize = 20 },
				large = { height = 56, paddingX = style.space.m, iconSize = 24 },
			},
			-- per-family metrics with no existing token equivalent. Each replaces a
			-- literal that used to live inside a reusable control.
			controls = {
				button = { padding = 12 }, -- renderer Button padding default
				slider = {
					thumbSize = 20, -- slider.THUMB
					railHeight = 6, -- the groove/fill bar
					readoutMinWidth = 40, -- the value readout's stable width
				},
				progress = {
					trackHeight = 6, -- progress_view.TRACK_HEIGHT
					rowMinHeight = 20, -- progress_view.ROW_MIN_HEIGHT (even on purpose)
				},
				popup = { triggerHeight = 40 }, -- popup_button.TRIGGER_HEIGHT
				textInput = {
					fieldHeight = style.targetSizes.minimum, -- text_input.FIELD_HEIGHT (44)
					clearSize = 28, -- text_input.CLEAR_SIZE
					padding = 12, -- renderer TextField padding default
				},
				toggle = {
					minHeight = 28, -- renderer Toggle minMax floor
					trackWidth = style.targetSizes.minimum, -- the 44px track the adapter draws
					trackInset = 12, -- its inset from the row's right edge
				},
				stepper = { valueMinWidth = 32 }, -- stepper readout's stable width
				label = { gap = 6 }, -- label.luau icon->title gap (no space step is 6)
				image = { defaultSize = 48 }, -- async_image default square
				-- Table's own chrome: sizes the shared role ladder does not name,
				-- each replacing a literal that used to sit inside table.luau
				table = {
					cellTextSize = 15,
					sortMarkTextSize = 11,
					sortMarkMargin = 14, -- keeps the ▲/▼ clear of the resize grip
					headerHeight = 28,
					rowGap = 2,
					indicatorThickness = 2, -- resize preview + drop line
					editToggleInset = 2,
					editTogglePadding = 6,
					editToggleWidth = 56,
					editToggleHeight = 24,
					ghostWidth = 180,
					ghostHeight = 26,
					ghostStackWidth = 186,
					ghostStackHeight = 32,
				},
				-- Table row action tray (row-actions Task 2): a tray button never
				-- narrower than buttonMinWidth, buttonPad is its inner horizontal
				-- padding, editAffordance is the edit-mode minus-circle diameter.
				rowActions = {
					buttonMinWidth = 64,
					buttonPad = style.space.s,
					editAffordance = 28,
				},
			},
			radii = style.radii,
			strokes = style.strokes,
			targetSizes = style.targetSizes,
			-- NOTE: `iconSizes` is deliberately NOT declared here. It is filled
			-- in by `resolve` from NEUTRAL_ICON_SIZES for every package, so the
			-- resolved snapshot always answers all three roles while no
			-- package's authored `metrics` — and therefore no package's content
			-- STAMP — moves for a section it never wrote (verified: adding it
			-- to this definition moved Fantasy Parchment's stamp, which would
			-- have invalidated the stored Step 3.5 captures).
			-- decoration-slot content insets (ADR-0019 §5). Neutral is a FLAT theme:
			-- every slot is native paint, so these describe the padding a slotted
			-- surface reserves rather than any asset geometry.
			insets = {
				panel = uniformInset(style.space.m),
				control = uniformInset(12),
				field = uniformInset(12),
				selection = uniformInset(style.space.s),
				divider = uniformInset(0),
				scrollbar = uniformInset(0),
				-- sliderTrack / sliderThumb / badge are deliberately ABSENT. They
				-- are the optional-inset slots (package.REQUIRED_INSET_SLOTS): a
				-- rail, a thumb and a counter seal have no inner content to clear
				-- a painted border for, so their reservation is zero and `resolve`
				-- fills it in below. Declaring them here would add twelve metric
				-- token attributes to every package's Style-Editor sheet for
				-- values no theme would ever tune.
			},
			motion = style.motion,
		},
		chrome = {
			panel = { kind = "native" },
			control = { kind = "native" },
			field = { kind = "native" },
			selection = { kind = "native" },
			divider = { kind = "native" },
			scrollbar = { kind = "native" },
			sliderTrack = { kind = "native" },
			sliderThumb = { kind = "native" },
			badge = { kind = "native" },
		},
		assets = {},
		compatibility = { requiresSchema = pkg.SCHEMA },
	}
end

local neutralPackageCache: any = nil

function snapshot.neutralPackage(): any
	if neutralPackageCache == nil then
		local compiled, report = pkg.define(neutralDefinition())
		assert(
			compiled ~= nil,
			"Studio Neutral failed its own package gate: "
				.. (if report and report.errors and report.errors[1] then report.errors[1].message else "?")
		)
		neutralPackageCache = compiled
	end
	return neutralPackageCache
end

-- ===== resolve =============================================================

export type Facts = {
	displaySize: string?, -- Small | Medium | Large (the ten-foot class)
	preferredTextSize: number?, -- the multiplicative reservation seam
	preferredTextOffset: number?, -- the ADDITIVE engine offset, in px
}

-- ===== the text-scale policy ===============================================
-- THE ONE DERIVATION of the two text scales and the additive offset, as pure
-- functions of the three platform facts above. `environment`'s
-- `typographyScale`/`typographyPaintScale` memos call these, and so does
-- `text_fit.facts` when it is handed a SNAPSHOT rather than a live env — which
-- is what lets `composition.floorPx` reserve the same box the solver measures
-- without an env of its own. Two implementations that agree today is the exact
-- defect this feature exists to end (docs/plans/variable-item-extents.md), so
-- there is one and both seams call it.

-- the ten-foot TYPE FLOOR (input-paradigms expansion, matrix D.1): body text
-- must clear ~29pt at 3m, so a Large display class multiplies the whole type
-- ladder. A near display leaves it alone.
local function tenFootFloor(displaySize: any): number
	return if displaySize == "Large" then 1.5 else 1
end

--[[ typographyScale(displaySize, preferredTextSize) -> the MEASURE-seam scale.
	The player's accessibility preference (clamped into its legal domain: a broken
	platform fact must never leak a negative or absurd scale downstream) composed
	with the ten-foot floor. On a near display this is exactly the preference, so
	the corpus invariant `typographyScale == preferredTextSize` still holds. ]]
function snapshot.typographyScale(displaySize: any, preferredTextSize: any): number
	local base = if type(preferredTextSize) ~= "number" or preferredTextSize ~= preferredTextSize
		then 1
		else math.clamp(preferredTextSize, 0.5, 3)
	return base * tenFootFloor(displaySize)
end

--[[ typographyPaintScale(displaySize) -> the PAINT-seam scale (large-text accessibility).
	The engine applies the player's PreferredTextSize itself, as an ADDITIVE px
	offset at draw time, so paint must carry ONLY authored scale — folding the
	preference in here is the double-application defect. ]]
function snapshot.typographyPaintScale(displaySize: any): number
	return tenFootFloor(displaySize)
end

--[[ displaySizeOf(snap) -> "Large" | "Medium" — THE DISPLAY CLASS A RESOLVED
	SNAPSHOT WAS RESOLVED AGAINST, read back off the snapshot itself.

	`resolve` and `forDisplay` both stamp `density` ("ten-foot" | "near"), and a
	caller holding only a snapshot — no env, no facts — needs the `displaySize`
	word back to spend `typographyPaintScale`/`metricScale`. Two call sites
	derived it inline before this existed (`text_fit.facts`'s snapshot branch and
	the measure seam's fit band), which is one inversion of the same mapping
	written twice: exactly how a ladder ends up disagreeing with itself. ]]
function snapshot.displaySizeOf(snap: any): string
	local density = if type(snap) == "table" then (snap :: any).density else nil
	return if density == "ten-foot" then "Large" else "Medium"
end

--[[ metricScale(displaySize) -> the METRIC ladder's ten-foot factor (director
	ruling 2026-08-20).

	THE DIRECTOR RULED AGAINST TYPE-ONLY. The framework's ten-foot policy was four
	rows — the type floor above, the sizeClass density cap, the focus
	strengthening and the overscan margins — and the audit measured the
	consequence honestly: control heights, paddings, icon sizes and the 44 px hit
	floor on a television were byte-identical to a phone's, so a screen at three
	metres grew its words inside chrome that had not moved. On ten-foot, controls,
	spacing, icons and hit floors now scale with the type, ten-foot style.

	IT IS `tenFootFloor`, NOT A SECOND CONSTANT, and that is the whole design.
	The acceptance the director set is a PROPORTION EQUALITY — every
	text-to-control proportion at ten-foot equals its near proportion — and two
	constants that agree today are exactly how a 16-in-44 becomes a 24-in-60. One
	function, two ladders, and `tests/ten_foot_metrics.spec.luau` asserts the
	identity rather than the number.

	WHY A SEPARATE NAME AT ALL, when the body is one call: the two ladders are
	different DECISIONS that happen to share a factor. A caller reading
	`typographyPaintScale` to size a button would be spending the type seam's
	answer on chrome, and the day a director splits them the split has a seam. ]]
function snapshot.metricScale(displaySize: any): number
	return tenFootFloor(displaySize)
end

--[[ reserveScale(typographyScale, typographyPaintScale) -> what a MEASURE
	reserves at, given the two SCALES (rather than the facts behind them).

	THE RESERVATION FLOOR (preferred-text sweep, 2026-07-24): the two seams above
	are only safe while measure >= paint. `typographyScale`'s legal domain starts
	at 0.5 while the paint seam carries no preference factor at all — so a sub-1
	preference reserved HALF the box the engine then drew into and every
	explicit-size text node clipped (proven live at preferredTextSize = 0.5: 10
	nodes reported TextFits == false). Over-reserving is always safe;
	under-reserving is never. Hence the max, and hence `max(typographyScale,
	typographyPaintScale)` is the thing every predicting consumer got wrong.

	THE ONE `math.max` IN THE FRAMEWORK: the renderer's measure seam and
	`text_fit.facts` both call this, on the two DERIVED env keys, so a fault
	profile that overrides either key is honoured identically by both. ]]
function snapshot.reserveScale(typographyScale: any, typographyPaintScale: any): number
	local measure = if type(typographyScale) == "number" and typographyScale == typographyScale
		then typographyScale
		else 1
	local paint = if type(typographyPaintScale) == "number" and typographyPaintScale == typographyPaintScale
		then typographyPaintScale
		else 1
	return math.max(measure, paint)
end

-- measureScale(displaySize, preferredTextSize) -> the same number, derived from
-- the FACTS. This is the form a caller holding only a theme snapshot needs.
function snapshot.measureScale(displaySize: any, preferredTextSize: any): number
	return snapshot.reserveScale(
		snapshot.typographyScale(displaySize, preferredTextSize),
		snapshot.typographyPaintScale(displaySize)
	)
end

-- the ADDITIVE engine offset, in the legal domain the renderer's measure seam
-- clamps it to. Absent/garbage = 0.
function snapshot.textOffset(preferredTextOffset: any): number
	if type(preferredTextOffset) ~= "number" or preferredTextOffset ~= preferredTextOffset then
		return 0
	end
	return math.clamp(preferredTextOffset, 0, 32)
end

local function frozenClone(t: any): any
	local out: any = {}
	for k, v in t do
		out[k] = if type(v) == "table" then frozenClone(v) else v
	end
	return table.freeze(out)
end

-- freeze IN PLACE, skipping what is already frozen (re-freezing is an error in
-- Luau). `frozenClone` above copies; this one is for a table that was just built
-- and has no other owner.
local function deepFreeze(t: any): any
	for _, v in t do
		if type(v) == "table" and not table.isfrozen(v) then
			deepFreeze(v)
		end
	end
	return table.freeze(t)
end

-- ===== the app namespace (ADR-0042) ========================================
--[[ A RESERVED `app.*` SECTION AN APPLICATION DECLARES ONCE.

	WHAT IT IS FOR. An app's own structural numbers — a tile minimum, a chart
	band, a dock height, a racer row — are not spacing steps, not control metrics
	and not type sizes, and before this section there was nowhere for them: a
	metric NAME is validated against the neutral snapshot, so a name no shipped
	package declares is a construction error. Four consumers rediscovered that
	independently and each wrote the same shim (`gap1-audit.md`), which put ~100
	numbers outside every theme, outside a package swap, and — the half that
	actually broke — outside the ten-foot ladder, so two of them re-implemented
	the distance transform by hand and one applied it to a single number out of
	four.

	WHY IT IS A DECLARATION AND NOT A PACKAGE SECTION ALONE. `isMetricPath` runs
	at CONSTRUCTION, inside `blueprint_schema`, with no snapshot in scope — that
	is the whole point of it, a typo caught when the form is built rather than
	becoming a nil size on the first solve of a themed screen. So the vocabulary
	an app adds has to be knowable without a snapshot, and a proof that must mount
	under Studio Neutral AND Fantasy Parchment with no source edit cannot carry
	its numbers on either package. One process-wide declaration answers both: the
	app OWNS the names, every resolved snapshot carries them, and a PACKAGE may
	MOVE any of them (`metrics.app`) exactly as it moves `space.m`.

	ONE GROUP PER DECLARER, AND THAT IS NOT TIDINESS. The namespace is
	process-wide, and this repo's own showcase mounts FIVE reference proofs in one
	place — so a `declareApp(metrics)` that replaced the whole section would let
	the second proof's boot silently un-spell the first proof's names, and every
	form the picker rebuilt after the switch would refuse to construct. A
	declaration therefore claims exactly one top-level GROUP
	(`declareApp("cartwheel", …)` -> `app.cartwheel.tileMin`), replaces only that
	group, and `nil` retires it. Two apps cannot collide by construction, and the
	group name is the one segment that says WHOSE number this is.

	IT IS THE ONE MUTABLE MODULE-LEVEL FACT IN THIS FILE, and it is fenced:
	`declareApp` validates, freezes and drops the neutral memo, so `neutral()`
	and every later `resolve` see the same namespace and no snapshot is ever
	half-declared. Declaring is an app-BOOT act — before the first form is built. ]]
local declaredApp: any = table.freeze({})
--[[ …and its GENERATION, which is what makes a declaration reach a snapshot that
	was resolved before it.

	The trap this closes was found migrating `p2_cartwheel`: a HOST creates the
	environment and may commit a theme package's snapshot, then the app builds and
	declares its namespace — so the snapshot every screen is measured against was
	resolved against the previous vocabulary, every `px = "app.…"` resolved to nil,
	and every band sized zero. Silently: an unresolvable metric name is a missing
	dimension, not an error.

	`forDisplay` is the ONE seam every environment read passes through, so it is
	where a stale base is refreshed — see `withCurrentApp`. A counter rather than a
	field on the snapshot, so a snapshot's own shape is byte-identical to what it
	was before this feature (the same reason `densityBases` is a side table). ]]
local declaredAppGeneration = 0
-- …and the memo `declareApp` has to drop, declared here because the declaration
-- is what decides which names `neutral()` can spell (`snapshot.neutral` below is
-- its only other writer)
local neutralCache: any = nil

-- a legal app metric segment: an identifier, because a '.' would make the dotted
-- path ambiguous and anything else cannot be spelled in a metric reference
local function isAppSegment(name: any): boolean
	return type(name) == "string" and string.match(name, "^[%a_][%w_]*$") ~= nil
end

local function checkAppNode(node: any, prefix: string)
	for key, value in node do
		assert(
			isAppSegment(key),
			`themes.declareApp: 'app.{prefix}{tostring(key)}' is not a legal metric name `
				.. `(letters, digits and underscore, starting with a letter or underscore)`
		)
		local path = `{prefix}{key}`
		if type(value) == "table" then
			checkAppNode(value, `{path}.`)
		else
			assert(
				type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge,
				`themes.declareApp: 'app.{path}' must be a finite number (got {tostring(value)})`
			)
		end
	end
end

--[[ EVERY LIVE ENVIRONMENT'S GENERATION SIGNAL, weakly.

	`forDisplay` refreshing a stale base is only HALF the answer, and the half that
	is easy to mistake for the whole one. An environment MEMOIZES its `themeMetrics`
	read, and a memo re-runs only when a signal it `use()`d changed — so a
	declaration made after the first read invalidated nothing, the memo served its
	warm value, and `px = "app.…"` went on resolving to nil. Every ten-foot test in
	this repo masked it, because setting `displaySize` invalidates that memo for an
	unrelated reason and the declaration rode in on that. The live target was
	`examples/gallery`: one environment per place at boot and a runtime picker
	between five proofs, each declaring its group long after the first read.

	So a declaration is a REACTIVE fact. `environment.new` registers one signal
	here and `use()`s it inside the memo — a DEPENDENCY, not a value. Weak keys, so
	a discarded environment's signal collects and this table never pins a core
	alive; a signal is a table, which is what makes it a legal weak key. ]]
local appGenerationSignals: any = setmetatable({}, { __mode = "k" })

--[[ observeAppDeclarations(signal) -> unsubscribe.

	`signal:set(generation)` on every real change to the app namespace.

	INTERNAL, not public surface. `env/environment.luau` is the only caller and
	the only one that should be: this is the seam that makes the environment's
	metric memo re-run, and it is registered WEAKLY, so an observer that keeps no
	reference of its own would have its edge collected out from under it with no
	diagnostic anywhere. The environment is safe because its signal lives exactly
	as long as it does; a third party holding only the returned `unsubscribe`
	(which captures the signal) is safe for the same reason. It is not exported on
	`Facet.themes` and is not classified as public surface — see ADR-0042.

	`unsubscribe` is what lets a caller retire an observer deliberately rather
	than by dropping a reference and hoping. ]]
function snapshot.observeAppDeclarations(signal: any)
	assert(
		type(signal) == "table" and type(signal.set) == "function",
		"themes.observeAppDeclarations: expected a settable signal"
	)
	appGenerationSignals[signal] = true
	return function()
		appGenerationSignals[signal] = nil
	end
end

-- the current declaration generation — the number the signals above carry.
-- INTERNAL, for the same reason `observeAppDeclarations` is.
function snapshot.appGeneration(): number
	return declaredAppGeneration
end

--[[ publish the generation to every registered signal that does not already
	carry it, and hand back the FIRST failure rather than raising it here.

	TWO PROPERTIES, AND EACH ONE CLOSES A REAL HOLE.

	IT OFFERS THE GENERATION TO EVERY SIGNAL BEFORE ANYONE HEARS ABOUT A FAILURE.
	`declareApp` WRITES reactive state, so a `set` can fail — and a loop that
	stopped at the first failure would leave the environments after it in the
	iteration order (which is ARBITRARY: this is a weak table) blind, for a reason
	having nothing to do with them. That arbitrariness is also why the guard case
	registers TWO failing observers: with one, a stop-at-first-failure bug passes
	whenever it happens to sort last (measured green in 4 runs of 8), and with two
	the earlier can never be the last.

	AND IT ONLY WRITES A SIGNAL THAT TRAILS, which is what makes the publish
	SELF-HEALING. The namespace, the generation and the dropped neutral memo are
	applied BEFORE this runs, so a failure here leaves the vocabulary live and
	unpublished — and the value-equality short-circuit would make the obvious retry
	a no-op, stranding that environment forever while `isMetricPath` answered true.
	Running this at the TOP of `declareApp` as well means the identical retry heals
	it. ]]
local function publishAppGeneration(): any
	local failure: any = nil
	for signal in appGenerationSignals do
		local current: any = nil
		if type(signal.get) == "function" then
			local ok, value = pcall(signal.get, signal)
			current = if ok then value else nil
		end
		if current ~= declaredAppGeneration then
			local ok, err = pcall(signal.set, signal, declaredAppGeneration)
			if not ok and failure == nil then
				failure = err
			end
		end
	end
	return failure
end

-- deep VALUE equality over a declaration group (numbers and nested tables only,
-- which is all `checkAppNode` lets through)
local function sameAppGroup(a: any, b: any): boolean
	if a == nil or b == nil then
		return a == b
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for key, value in a do
		if not sameAppGroup(value, (b :: any)[key]) then
			return false
		end
	end
	for key in b do
		if (a :: any)[key] == nil then
			return false
		end
	end
	return true
end

--[[ declareApp(namespace, metrics) -> the whole frozen `app` section.

	`metrics = nil` RETIRES that group, which is how a test puts the process back
	the way it found it. Returns the whole section rather than the group, because
	the whole section is what `isMetricPath` spells against and what a caller
	inspecting the namespace wants to see.

	CALL IT AT BOOT, FROM ORDINARY CODE — never from inside a memo, an effect body
	or anything else the reactive core is evaluating. It WRITES reactive state (the
	generation every environment's metric memo subscribes to) and the core refuses
	a write made during an evaluation.

	AND THAT FAILURE IS QUIET, WHICH IS THE REASON THIS PARAGRAPH IS LONG. An
	earlier draft of this comment said the call "raises" — it does when you call it
	DIRECTLY, and that is not the shape that happens. Inside a memo, `core`'s
	`pull` `pcall`s the compute (`core/custom.luau`: "Never throws to the caller:
	compute errors, cycles, and illegal writes quarantine the node"), so what you
	actually get is: the memo QUARANTINED with its old value, `m:get()` answering
	as if nothing happened, and ONE artifact — `core:lastError()`.

	The vocabulary is live by then (the namespace, the generation and the dropped
	neutral memo are applied before the publish), so an environment that missed its
	notification is blind while `isMetricPath` answers true. That is why the publish
	below is SELF-HEALING rather than merely careful: it is the only thing standing
	between a mistake nobody can see and a permanently wrong surface. Any later
	`declareApp` — including one for an unrelated group — catches the stranded
	observer up. Guard: `tests/app_metrics.spec.luau`, "a declaration made inside a
	memo is quarantined, recorded, and healed later".

	AN IDENTICAL RE-DECLARATION IS NOT A CHANGE, and the short-circuit is not
	tidiness. `TableMetrics.installTypeRamp` and `ResultsParts.declareMetrics`
	re-declare the same constant table on every presenter build; without this, each
	build bumps the generation, drops the neutral memo, forces every snapshot
	behind it to re-resolve and re-runs every `themeMetrics` memo in the process —
	churn for a value nobody moved. ]]
function snapshot.declareApp(namespace: any, metrics: any): any
	assert(
		isAppSegment(namespace),
		`themes.declareApp: '{tostring(namespace)}' is not a legal app namespace `
			.. `(letters, digits and underscore, starting with a letter or underscore) — `
			.. `it is the group your metrics live under, e.g. declareApp("cartwheel", \{ tileMin = 96 })`
	)
	assert(
		metrics == nil or type(metrics) == "table",
		`themes.declareApp('{namespace}'): expected a table of app metrics or nil, got {type(metrics)}`
	)
	if metrics ~= nil then
		checkAppNode(metrics, `{namespace}.`)
	end
	--[[ HEAL BEFORE ANYTHING ELSE. A previous call may have applied the vocabulary
		and then failed to publish it (see `publishAppGeneration`), and the retry an
		author reaches for is the SAME table — which the short-circuit below would
		eat, leaving that environment blind forever. Any signal that trails is caught
		up here, before the early return can happen. ]]
	local pending = publishAppGeneration()
	-- VALIDATE FIRST, THEN COMPARE: a malformed re-declaration is an authoring
	-- error whether or not it happens to match, and refusing it is the only way
	-- the author hears about it
	if sameAppGroup(declaredApp[namespace], metrics) then
		if pending ~= nil then
			error(pending, 0)
		end
		return declaredApp
	end
	local next_: any = {}
	for group, entries in declaredApp do
		next_[group] = entries
	end
	next_[namespace] = if metrics == nil then nil else frozenClone(metrics)
	declaredApp = table.freeze(next_)
	declaredAppGeneration += 1
	-- the neutral snapshot is what `isMetricPath` spells names against, so it
	-- cannot outlive the vocabulary it was resolved with
	neutralCache = nil
	--[[ …and every live environment's metric memo has to be told, or it serves the
		warm value it computed before the vocabulary existed (see the note above).

		THE FAILURE IS REPORTED — re-raised to a DIRECT caller, and recorded on
		`core:lastError()` when the call came from inside a memo (see `declareApp`'s
		header: the core quarantines rather than propagates, so "loud" is only true
		of the direct shape). Either way the state stays applied and the next
		`declareApp` — including the identical retry — heals whoever missed it.
		Swallowing it here would leave the quarantined shape with NO artifact at
		all. ]]
	local failure = publishAppGeneration()
	if failure ~= nil then
		error(failure, 0)
	end
	return declaredApp
end

-- the declared namespace, frozen. `{}` until an app declares a group.
function snapshot.appMetrics(): any
	return declaredApp
end

-- a MUTABLE deep copy of the declaration. `resolve` publishes it and then writes
-- a package's `metrics.app`, the pixel snap and the overrides into it, so the
-- copy has to be writable all the way down.
local function appBase(node: any): any
	local copy: any = {}
	for k, v in node do
		copy[k] = if type(v) == "table" then appBase(v) else v
	end
	return copy
end

-- write `value` at a dotted path inside a mutable metric tree; returns false when
-- the path names nothing (an override for a metric that does not exist is an
-- authoring error, not a silent no-op)
local function writePath(tree: any, path: string, value: any): boolean
	local parts: { string } = {}
	for part in string.gmatch(path, "[^%.]+") do
		table.insert(parts, part)
	end
	if #parts == 0 then
		return false
	end
	local node = tree
	for i = 1, #parts - 1 do
		node = node[parts[i]]
		if type(node) ~= "table" then
			return false
		end
	end
	local leaf = parts[#parts]
	if node[leaf] == nil then
		return false
	end
	node[leaf] = value
	return true
end

-- does this dotted path name something in the tree? The read-only half of
-- `writePath`, so a package's ten-foot declaration is validated against the
-- snapshot it will be applied to rather than against a hand-kept name list.
local function hasPath(tree: any, path: string): boolean
	local node: any = tree
	local seen = false
	for part in string.gmatch(path, "[^%.]+") do
		if type(node) ~= "table" then
			return false
		end
		node = node[part]
		seen = true
	end
	return seen and type(node) == "number"
end

-- ===== the ten-foot metric ladder ==========================================
--[[ WHICH PUBLISHED NUMBERS ARE LENGTHS (director ruling 2026-08-20).

	The ten-foot factor multiplies LENGTHS and nothing else, and "and nothing
	else" is the hard half: a snapshot publishes durations in seconds, line
	heights as ratios, line COUNTS, the player's own text preference and the type
	ladder the type floor already scales at the measure seam. An "every number"
	rule turns a 0.12 s fade into 0.18 s and paints text at 2.25x.

	SO EVERY NUMERIC LEAF IS CLASSIFIED BY ITS PATH, and the classification is
	published (`snapshot.densityClassOf`) because two readers need it: the
	transform below, and `tests/ten_foot_metrics.spec.luau`, which walks every
	shipped configuration and FAILS on a leaf that classifies to nothing. An
	unclassified metric is EXEMPT at runtime — the safe direction, because a new
	duration silently multiplied is worse than a new length silently not — and a
	test failure at the commit that introduces it. ]]

-- flat sections where every leaf is a length
local DENSITY_LENGTH_SECTIONS: { [string]: boolean } = {
	space = true,
	targetSizes = true,
	iconSizes = true,
	iconRunGap = true,
	-- the PAINT family's float half — see the paint-family note below
	strokes = true,
}
--[[ THE PAINT FAMILY — corner radii and stroke thickness, which scale WITH the
	ladder (DIRECTOR RULING, 2026-08-21, decided on a live A/B capture of a
	television at three metres).

	THIS SUPERSEDES THE EXEMPTION THAT STOOD HERE, and it supersedes it in the
	RESULT while keeping the doctrine that produced it word for word:

		A METRIC MAY ONLY SCALE WHERE THE FRAMEWORK OWNS THE PAINT.

	The exemption existed because a corner radius is not painted from this
	snapshot: it is painted from a SECOND authority — `ctx.style` on the bespoke
	path, and the StyleSheet rules `tokens/sheet_model` bakes it into as literals
	on the native one — and scaling here alone made the MEASURED corner disagree
	with the PAINTED one (12 measured against 18 painted on the default package,
	10 against 15 under Fantasy Ornate). The old comment named the fix as
	sheet-GENERATION work rather than a reclassification here. That work is what
	this round did: `snapshot.paintForDisplay` below is ONE derivation, and BOTH
	authorities call it — `sheet_model.buildPackage` for the literal it bakes, and
	`screen_target` for the `ctx.style` it hands `screen_paint`/`screen_chrome`.
	So the reclassification is now honest: measure and paint move together, off
	the same `metricScale`, and the callout tail `present/anchored` shapes from
	`radii.panel` lands on the corner the engine actually draws.

	TWO CLASSES, BECAUSE THE TWO ENGINE PROPERTIES ARE DIFFERENT TYPES.
	`UICorner.CornerRadius` is a `UDim` whose Offset is an INTEGER, so a scaled
	radius is rounded to a whole pixel here rather than handed to the engine as a
	10.5 it will silently round itself — a reservation must be the number the
	paint will be, and half a pixel of disagreement is the same defect one step
	smaller. `UIStroke.Thickness` is a float, so a hairline scales exactly:
	1 -> 1.5 at the director's 1.5. ]]
local DENSITY_WHOLE_PIXEL_SECTIONS: { [string]: boolean } = { radii = true }
--[[ ART GEOMETRY IS NOT A METRIC LADDER, and this is the sharpest line in the
	classification. `chromeInsets`, `chromeOutsets` and `chromeBleed` describe
	PIXELS THE ENGINE ACTUALLY PAINTS: a nine-slice recipe's border is drawn at
	`SliceCenter`/`SliceScale`, both authored by the package and neither varied by
	display class, and a shadow's blur radius is a declared px figure the engine
	renders unchanged. Reserving 1.5x of a border that is still 16 px wide is a
	reservation for pixels that do not exist — the exact inverse of the
	"painted at a size nobody measured" defect this framework already names, and
	the reason a reservation must always be the number the paint will be.

	A package that wants a heavier frame at three metres ships heavier art (or a
	different `sliceScale`); it does not get one by arithmetic here. ]]
local DENSITY_ART_SECTIONS: { [string]: boolean } = { chromeInsets = true, chromeOutsets = true }
--[[ sections that are NOT metric ladders at all:
	 `type`       the TYPE ladder — `typographyPaintScale` scales it at the
	              renderer's measure/paint seams, so scaling it here is the
	              2.25x double-application defect (and `lineHeight` is a ratio);
	 `motion`     seconds. Motion stays TIME-TRUE at every distance, and
	              reduced-motion is untouched;
	 `preferredText` the player's own reservation inputs, applied once at the
	              measure seam — the same double-application rule as `type`;
	 `overrides`  a RECORD of what a caller overrode, not a live metric (the
	              metric itself sits in its own section and scales there);
	 `tenFoot`    a package's ABSOLUTE ten-foot declarations (see below);
	 `identity`   package/theme/stamp. ]]
local DENSITY_EXEMPT_SECTIONS: { [string]: boolean } = {
	type = true,
	motion = true,
	preferredText = true,
	overrides = true,
	tenFoot = true,
	identity = true,
}
-- whole-package scalars. `chromeBleed` is art (the deepest shadow reach any slot
-- declares), so it is exempt for the reason above.
local DENSITY_LENGTH_SCALARS: { [string]: boolean } = {}
local DENSITY_EXEMPT_SCALARS: { [string]: boolean } = {
	pixelUnit = true,
	metricScale = true,
	chromeBleed = true,
}
-- `controlSizes` entries: the three px fields, and nothing a future field adds
-- until it is named here
local CONTROL_SIZE_LENGTHS: { [string]: boolean } = { height = true, paddingX = true, iconSize = true }
--[[ A CONTROL-FAMILY METRIC IS A LENGTH UNLESS ITS NAME SAYS OTHERWISE. The
	family tables are open — a package may author `controls.<family>.<anything>` —
	so the rule has to be a default plus a vocabulary rather than a list nobody
	will maintain. Each suffix carries its reason:
	  `*TextSize`   a TYPE size living inside a control family
	                (`controls.table.cellTextSize` is the trap: it reaches the
	                same `typographyPaintScale` seam every other type size does);
	  `*Lines`/`*Count`  a count of things, not a measure of them;
	  `*Duration`/`*Seconds`  time;
	  `*Ratio`/`*Fraction`/`*Scale`/`*Opacity`/`*Weight`  dimensionless. ]]
local CONTROL_NON_LENGTH_SUFFIXES = {
	"TextSize",
	"Lines",
	"Count",
	"Duration",
	"Seconds",
	"Ratio",
	"Fraction",
	"Scale",
	"Opacity",
	"Weight",
}
--[[ …and the one control metric whose snap direction is DOWN. A Path2D stroke is
	centred on its curve, so the ring's thickness is a BUDGET against the box
	(`resolve` computes it as `(1 - CIRCULAR_RADIUS)` of the diameter and
	pre-snaps it down for exactly this reason); snapping a scaled budget UP onto a
	pixel package's grid paints outside the box the solver measured. ]]
local CONTROL_BUDGET_KEYS: { [string]: boolean } = { circularThickness = true }

local function endsWith(s: string, suffix: string): boolean
	return #s >= #suffix and string.sub(s, -#suffix) == suffix
end

--[[ densityClassOf(path) -> "scale" | "scaleWhole" | "scaleDown" | "exempt" | nil.
	`nil` means "nobody has said", which the transform treats as exempt and the
	spec treats as a failure. ]]
function snapshot.densityClassOf(path: any): string?
	if type(path) ~= "string" then
		return nil
	end
	local parts: { string } = {}
	for part in string.gmatch(path, "[^%.]+") do
		table.insert(parts, part)
	end
	if #parts == 0 then
		return nil
	end
	local root = parts[1]
	if #parts == 1 then
		if DENSITY_LENGTH_SCALARS[root] then
			return "scale"
		end
		return if DENSITY_EXEMPT_SCALARS[root] then "exempt" else nil
	end
	if DENSITY_LENGTH_SECTIONS[root] then
		return "scale"
	end
	if DENSITY_WHOLE_PIXEL_SECTIONS[root] then
		return "scaleWhole"
	end
	if DENSITY_EXEMPT_SECTIONS[root] or DENSITY_ART_SECTIONS[root] then
		return "exempt"
	end
	--[[ A SLOT INSET IS A COMPOSITE, and the framework already publishes the
		split. `resolve` adds a recipe's `contentInsets` onto the slot's AUTHORED
		inset and records the art half separately in `chromeInsets`, so the honest
		transform scales the authored half and leaves the art half where the paint
		will be:  (inset - art) * factor + art.  A flat package's art half is zero,
		so its slot padding scales outright; an ornate package's frame stays the
		thickness it is drawn at. Applied in `forDisplay`'s named step, because it
		is the one leaf whose new value is not a function of its own old one. ]]
	if root == "insets" then
		return "scaleAuthored"
	end
	if root == "controlSizes" then
		return if CONTROL_SIZE_LENGTHS[parts[#parts]] then "scale" else nil
	end
	if root == "controls" then
		-- the vocabulary is checked on EVERY segment below the family, not only on
		-- the leaf: `controls.table.rowLines.pointer` is a count one level down
		for i = 2, #parts do
			for _, suffix in CONTROL_NON_LENGTH_SUFFIXES do
				if endsWith(parts[i], suffix) then
					return "exempt"
				end
			end
		end
		return if CONTROL_BUDGET_KEYS[parts[#parts]] then "scaleDown" else "scale"
	end
	--[[ THE APP NAMESPACE TAKES `controls`' RULE, WORD FOR WORD (ADR-0042). Both
		sections are OPEN — an app authors `app.<anything>` the way a package
		authors `controls.<family>.<anything>` — so the classification has to be a
		default plus a vocabulary rather than a list nobody outside this repo could
		maintain. The default is LENGTH because that is what an app declares here:
		the four shims this section replaced held tile minimums, chart bands, row
		heights and dock bands, and every one of them was a length that failed to
		scale on a television.

		The escape is the SAME suffix vocabulary, checked on every segment, and it
		earns its keep immediately: a `mapFraction` multiplied by 1.5 is 0.78 of a
		viewport, a `listRowCount` of 8 becomes 12, a `toastDurationSeconds` of 2.5
		becomes 3.75, and a `rowNameTextSize` scaled here is the 2.25x double
		application the type floor already guards at the measure seam. One
		vocabulary, so an app author who has read `controls` has read this. ]]
	if root == "app" then
		for i = 2, #parts do
			for _, suffix in CONTROL_NON_LENGTH_SUFFIXES do
				if endsWith(parts[i], suffix) then
					return "exempt"
				end
			end
		end
		return "scale"
	end
	return nil
end

--[[ THE BASE A DISTANCE-ADAPTED SNAPSHOT WAS DERIVED FROM.

	Recorded in a weak-keyed side table rather than as a field, so a snapshot's
	own shape — what a dump serializes, what `isMetricPath` can spell, what a
	sheet export walks — is byte-identical to what it was before this feature.
	The entry lives exactly as long as the adapted snapshot that keys it.

	It exists so the transform is applied FROM THE BASE, always, and never
	composed onto its own output. That is what makes a display-class change
	reversible without drift: a pixel package snaps its lengths onto an integer
	grid, so 44 -> 66 -> 68 -> 45.33 is what a ratio-composed round trip would
	do, while a re-derivation from the base is exact in both directions. ]]
local densityBases: any = setmetatable({}, { __mode = "k" })
--[[ THE APP-DECLARATION GENERATION EACH RESOLVED SNAPSHOT WAS BUILT WITH, and
	the refreshed form of a stale one. Both weak-keyed side tables, for
	`densityBases`' reason: a snapshot's own shape stays byte-identical to what it
	was before the app namespace existed. ]]
local appGenerations: any = setmetatable({}, { __mode = "k" })
local appRefreshed: any = setmetatable({}, { __mode = "k" })

--[[ withCurrentApp(base) -> a base whose `app` section can spell every name the
	app has declared.

	THE IDENTITY IN THE STEADY STATE, which is every read after boot: the
	generation matches and this is one weak-table lookup returning the argument.

	IT IS NOT THE IDENTITY WHEN A DECLARATION CAME LATER, and that is the point.
	A host creates the environment and may commit a package snapshot; the app then
	builds and declares. Without this the app's own names are missing from the very
	snapshot its screens are measured against, and a missing metric name is a
	missing dimension rather than an error — the whole proof silently measures
	zero.

	THE MERGE DIRECTION IS "BASE WINS": a value already in the snapshot was put
	there by the package's `metrics.app`, an override or the pixel snap, and it is
	that snapshot's answer. Only names the base has never heard of are added, from
	the declaration. A name RETIRED since is left where it is — a stale answer for
	a name nobody spells any more is harmless, and dropping it would make a
	still-mounted screen's dimension vanish. ]]
local function withCurrentApp(base: any): any
	local generation = if type(base) == "table" then appGenerations[base] else nil
	--[[ ONLY A SNAPSHOT `resolve` PRODUCED IS REFRESHED, and the guard is load
		bearing twice. `forDisplay` is TOTAL — it takes whatever the `themeMetrics`
		fact holds, including a hand-built metrics table from a fixture or a broken
		adapter (its header's type-guard note) — and such a table has no generation,
		never had an `app` section, and is still OWNED BY ITS CALLER: freezing the
		subtables it shares with a refreshed copy would silently make the caller's
		own data immutable. It also keeps the steady-state path to one weak lookup
		for the tables that are not ours to touch. ]]
	if generation == nil or generation == declaredAppGeneration then
		return base
	end
	--[[ KEYED BY GENERATION, not merely by base. Found live: the showcase mounts
		several proofs, so `p2_cartwheel` declares (generation N), a stale base is
		refreshed and cached, and then `p3_sipworks` declares (N+1) — and every read
		of that base got the cached N form back, which knows `app.cartwheel` and has
		never heard of `app.sip`. A cache that cannot say which vocabulary it holds
		is a stale answer with a fast path in front of it. ]]
	local cached = appRefreshed[base]
	if cached ~= nil and cached.generation == declaredAppGeneration then
		return cached.snapshot
	end
	local merged: any = appBase(if type(base.app) == "table" then base.app else {})
	local function fill(node: any, into: any)
		for key, value in node do
			if type(value) == "table" then
				if type(into[key]) ~= "table" then
					into[key] = {}
				end
				fill(value, into[key])
			elseif into[key] == nil then
				into[key] = value
			end
		end
	end
	fill(declaredApp, merged)
	--[[ …AND WHAT ARRIVED LATE TAKES THE PACKAGE'S GRID, exactly as `resolve` step
		4b puts an authored app length on it. Only the leaves this merge ADDED can
		be off the grid — everything the base already carried was snapped when it
		was resolved — and only the ones the ladder calls a length: snapping a 0.52
		map fraction onto a 4px unit is 4, which is not a smaller number, it is a
		corrupt solve. Without this a pixel package's late-declared metric measured
		off a different coordinate system from its neighbours at near distance and
		back on it at ten-foot, which is the measure/paint disagreement in miniature. ]]
	local unit: any = if type(base.pixelUnit) == "number" then base.pixelUnit else nil
	if unit ~= nil then
		local function snapLate(node: any, from: any, prefix: string)
			for key, value in node do
				local path = `{prefix}{tostring(key)}`
				if type(value) == "table" then
					snapLate(value, if type(from) == "table" then (from :: any)[key] else nil, `{path}.`)
				elseif type(value) == "number" and (type(from) ~= "table" or (from :: any)[key] == nil) then
					local class = snapshot.densityClassOf(`app.{path}`)
					if class == "scale" or class == "scaleWhole" then
						node[key] = pkg.snapToPixelUnit(value, unit :: number)
					end
				end
			end
		end
		snapLate(merged, base.app, "")
	end
	local out: any = {}
	for key, value in base do
		out[key] = value
	end
	out.app = deepFreeze(merged)
	-- every other branch came off a frozen snapshot, so ONE freeze finishes it —
	-- and nothing shared with the base is written to
	local frozen = table.freeze(out)
	appGenerations[frozen] = declaredAppGeneration
	appRefreshed[base] = { generation = declaredAppGeneration, snapshot = frozen }
	return frozen
end
-- per-base memo of the adapted forms, keyed by factor. A snapshot is frozen, so
-- an adapted form can never go stale for a given base.
local densityCache: any = setmetatable({}, { __mode = "k" })

function snapshot.baseOf(snap: any): any
	if type(snap) ~= "table" then
		return snap
	end
	local base = densityBases[snap]
	return if base ~= nil then base else snap
end

--[[ wholePixel(scaled, unit) -> the number the ENGINE will paint.

	A pixel package's grid wins where it has one (`snapToPixelUnit` is the same
	ceil the resolver spends, so a scaled radius stays on the package's own
	coordinate system); off the grid it is the NEAREST whole pixel, because a
	`UDim` Offset is an integer and nearest is the smallest disagreement with the
	derived value a rounding can leave. Not `ceil`: a radius is not an
	accessibility floor, and rounding a whole family up would fatten every corner
	on the screen by up to a pixel for nothing. ]]
local function wholePixel(scaled: number, unit: number?): number
	return if unit ~= nil then pkg.snapToPixelUnit(scaled, unit :: number) else math.round(scaled)
end

local function scaleInto(node: any, out: any, prefix: string, factor: number, unit: number?)
	for key, value in node do
		local path = if prefix == "" then tostring(key) else `{prefix}.{tostring(key)}`
		if type(value) == "number" then
			local class = snapshot.densityClassOf(path)
			if class == "scale" then
				local scaled = value * factor
				out[key] = if unit ~= nil then pkg.snapToPixelUnit(scaled, unit :: number) else scaled
			elseif class == "scaleWhole" then
				out[key] = wholePixel(value * factor, unit)
			elseif class == "scaleDown" then
				local scaled = value * factor
				out[key] = if unit ~= nil
					then math.max(unit :: number, math.floor(scaled / (unit :: number)) * (unit :: number))
					else scaled
			else
				out[key] = value
			end
		elseif type(value) == "table" then
			local child: any = {}
			out[key] = child
			scaleInto(value, child, path, factor, unit)
		else
			out[key] = value
		end
	end
end

--[[ forDisplay(snapshot, displaySize) -> the snapshot AS PRESENTED at that
	display class. Pure, total, idempotent and reversible.

	THIS IS THE ONE APPLICATION SITE, and it is called from the environment's
	`themeMetrics` memo — the same seam, over the same fact, that applies the type
	floor through `typographyScale`/`typographyPaintScale`. That placement is
	the fix, not an implementation detail: the density half used to ride
	`resolve`'s recorded `density`, and the environment's default snapshot is
	`neutral()`, resolved with no facts at all, so a television with no theme
	package installed measured 10 grid lanes against a desktop's 9 while painting
	1.5x type into them. Display facts must flow without a theme opt-in, and the
	environment is where display facts live.

	`resolve` therefore still records `density` and still re-applies nothing — the
	snapshot remains the AUTHORED authority, which is what lets this function
	derive both directions from it.

	AT A NEAR DISPLAY THIS IS THE IDENTITY — the same table, not a copy — so no
	near-distance geometry moves by a pixel and no allocation happens on the path
	every phone, tablet and desktop takes. ]]
function snapshot.forDisplay(snap: any, displaySize: any): any
	if type(snap) ~= "table" then
		return snap
	end
	local base = withCurrentApp(snapshot.baseOf(snap))
	local factor = snapshot.metricScale(displaySize)
	local density = if displaySize == "Large" then "ten-foot" else "near"
	if factor == 1 and base.density == density then
		return base
	end
	local cached = densityCache[base]
	if cached ~= nil and cached[factor] ~= nil then
		return cached[factor]
	end
	local unit: number? = if type(base.pixelUnit) == "number" then base.pixelUnit else nil
	local out: any = {}
	scaleInto(base, out, "", factor, unit)
	--[[ the composite step: a slot inset's AUTHORED half scales, its ART half
		stays the thickness the engine draws (see `densityClassOf`'s `insets` note).

		TYPE-GUARDED, like every seam that reads the `themeMetrics` fact (§8.2: a
		broken adapter fact must never leak past the seam that read it). This
		function runs inside the environment's memo, and a memo that THROWS makes
		the key read `nil` — which is a mounted surface going silently deaf, not an
		error anybody sees. A snapshot-shaped argument takes the step; anything else
		is scaled leaf-by-leaf and passed on for `currentMetrics` to reject. ]]
	if type(out.insets) == "table" and type(base.chromeInsets) == "table" then
		for slot, sides in out.insets do
			if type(sides) ~= "table" then
				continue
			end
			local art: any = (base.chromeInsets :: any)[slot]
			for side, px in sides do
				if type(px) ~= "number" then
					continue
				end
				local artPx = if type(art) == "table" and type(art[side]) == "number" then art[side] else 0
				local scaled = (px - artPx) * factor + artPx
				sides[side] = if unit ~= nil then pkg.snapToPixelUnit(scaled, unit :: number) else scaled
			end
		end
	end
	--[[ 2. AUTHORED BEATS DERIVED — the rule `space.gutter` already spends. A
		package that wants a bespoke television ladder declares
		`metrics.tenFoot = { ["space.m"] = 40, … }` and owns the consequence; the
		derived scale slots in wherever it is silent. The values are ABSOLUTE
		ten-foot pixels, not multipliers, for the same reason an override is: a
		number a package wrote is a number a package meant. ]]
	if factor ~= 1 and type(base.tenFoot) == "table" then
		for path, value in base.tenFoot do
			local px = if unit ~= nil and type(value) == "number"
				then pkg.snapToPixelUnit(value, unit :: number)
				else value
			writePath(out, path, px)
		end
		-- …and a declaration may not defeat the accessibility floor, exactly as an
		-- override may not (`resolve` step 5)
		if type(out.targetSizes) == "table" and type(out.targetSizes.minimum) == "number" then
			out.targetSizes.minimum = math.max(pkg.MIN_TARGET_SIZE, out.targetSizes.minimum)
		end
	end
	out.density = density
	out.metricScale = factor
	local frozen = deepFreeze(out)
	densityBases[frozen] = base
	if cached == nil then
		cached = {}
		densityCache[base] = cached
	end
	cached[factor] = frozen
	return frozen
end

--[[ paintForDisplay(metricsLike, displaySize, pixelUnit?) -> the PAINT FAMILY,
	as the engine will draw it at that display class.

	THE SECOND HALF OF THE LOCKSTEP, and the reason the paint family may scale at
	all. `forDisplay` above adapts the snapshot every MEASURE reads; this adapts
	the `radii`/`strokes` every PAINT authority reads, from the same
	`snapshot.metricScale`, with the same whole-pixel rule and the same pixel
	grid. Two callers, one derivation:

	  * `tokens/sheet_model.buildPackage` — the literal baked into the phantom
	    `::UICorner`/`::UIStroke` rules the engine paints from;
	  * `client/screen_target` — `ctx.style`, which `screen_paint`,
	    `screen_chrome` and `tokens/styling`'s `"panel"`/`"control"`/`"pill"`
	    token resolution all write from.

	IT TAKES A METRICS-SHAPED TABLE, not a snapshot, because the two authorities
	hold different shapes: a package's authored `metrics`, or a compiled token
	`style` (`tokens/default_style`). Everything outside `radii`/`strokes` is
	passed through BY REFERENCE — this function has no opinion about colours,
	type, motion or spacing, and a caller that hands it a whole style gets its
	own style back with two sections re-derived.

	WHY IT SNAPS BEFORE IT SCALES. `resolve` puts a pixel package's authored
	lengths on its grid (step 4b) and `forDisplay` scales what `resolve`
	published, so a paint authority reading the UNSNAPPED authored number would
	drift from the measure on any package whose radius is not already a multiple
	of its unit. Snapping first reproduces the resolver's own answer exactly, and
	`tests/ten_foot_metrics.spec.luau` compares the two derivations leaf by leaf
	on all nine shipped configurations rather than taking this paragraph's word
	for it.

	AUTHORED WINS, HERE TOO. A package may declare ABSOLUTE ten-foot pixels
	(`metrics.tenFoot`), and that channel can name a paint metric — so it is
	applied here for the same reason `forDisplay` applies it: a number a package
	wrote is a number a package meant, and reading it on one side only is exactly
	the measure/paint disagreement this whole design exists to prevent.

	AT A NEAR DISPLAY THIS IS THE IDENTITY — the same table, not a copy — so
	nothing on a phone, tablet or desktop moves by a pixel, and the built-in
	sheet's `style == defaultStyle` identity check still holds. ]]
function snapshot.paintForDisplay(metricsLike: any, displaySize: any, pixelUnit: any): any
	if type(metricsLike) ~= "table" then
		return metricsLike
	end
	local factor = snapshot.metricScale(displaySize)
	if factor == 1 then
		return metricsLike
	end
	local unit: number? = if type(pixelUnit) == "number" then pixelUnit else nil
	local function snapped(value: number): number
		return if unit ~= nil then pkg.snapToPixelUnit(value, unit :: number) else value
	end
	local out: any = table.clone(metricsLike)
	for section, whole in { radii = true, strokes = false } do
		local src = (metricsLike :: any)[section]
		if type(src) ~= "table" then
			continue
		end
		local dst: any = {}
		for key, value in src do
			if type(value) == "number" then
				local scaled = snapped(value) * factor
				dst[key] = if whole then wholePixel(scaled, unit) else snapped(scaled)
			else
				dst[key] = value
			end
		end
		out[section] = dst
	end
	if type((metricsLike :: any).tenFoot) == "table" then
		for path, value in (metricsLike :: any).tenFoot do
			local section, key = string.match(tostring(path), "^([^%.]+)%.([^%.]+)$")
			if (section == "radii" or section == "strokes") and type(out[section]) == "table" then
				out[section][key] = if type(value) == "number" then snapped(value) else value
			end
		end
	end
	-- ONLY the two tables this function authored are frozen. Everything else in
	-- the clone is the CALLER'S table, held by reference: freezing those would
	-- reach back through the copy and change the input.
	for section in { radii = true, strokes = true } do
		if type(out[section]) == "table" then
			out[section] = table.freeze(out[section])
		end
	end
	return table.freeze(out)
end

-- resolve(package, themeName, facts, overrides?) -> frozen ThemeSnapshot.
--
-- Composition happens EXACTLY ONCE, in ADR-0019 §2 order:
--   1. the package's authored metrics for the active theme;
--   2. display/density policy;
--   3. preferred-text reservation inputs;
--   4. accessibility and minimum-hit-target floors (clamp UP, never down);
--   5. explicit local overrides.
--
-- Steps 2 and 3 deliberately do NOT scale anything here, and that is still true
-- after ADR-0039 gave the ten-foot ladder a METRIC half. The environment composes
-- the ten-foot type floor into `typographyScale`/`typographyPaintScale`, the
-- preferred-text offset into the renderer's measure seam, and the ten-foot METRIC
-- factor into its own `themeMetrics` read (`snapshot.forDisplay`); applying any of
-- them again here would DOUBLE them. The snapshot therefore carries the AUTHORED
-- values plus the facts that produced it, and the existing seams keep multiplying
-- at measure, at paint and at the metric read.
function snapshot.resolve(package: any, themeName: string?, facts: Facts?, overrides: { [string]: any }?): any
	assert(
		type(package) == "table" and package.schema == pkg.SCHEMA,
		"themes.resolve: expected a package compiled by themes.define"
	)
	local f = facts or {}
	local name = themeName or package.style.defaultTheme
	local theme: any = nil
	for _, entry in package.style.themes do
		if entry.name == name then
			theme = entry
		end
	end
	assert(theme ~= nil, `themes.resolve: package '{package.identity.id}' has no theme named '{tostring(name)}'`)

	local metrics = package.metrics
	-- 1. authored base
	local out: any = {
		type = {},
		space = {},
		controlSizes = {},
		controls = {},
		radii = {},
		strokes = {},
		targetSizes = {},
		iconSizes = {},
		insets = {},
		motion = {},
	}
	-- ICON SIZES (ADR-0020 R4). Authored roles win; every unauthored role falls
	-- back to the neutral ladder, so a control that names `iconSizes.medium`
	-- always resolves a number and a package that declares only `large` is not
	-- half-broken.
	for _, role in pkg.ICON_SIZE_ROLES do
		local authored = if type(metrics.iconSizes) == "table" then (metrics.iconSizes :: any)[role] else nil
		out.iconSizes[role] = if type(authored) == "number" then authored else (NEUTRAL_ICON_SIZES :: any)[role]
	end
	local function publishRole(role: string, entry: any)
		out.type[role] = {
			fontKey = snapshot.fontKey(entry.font),
			font = {
				family = entry.font.family,
				weight = entry.font.weight or DEFAULT_WEIGHT,
				style = entry.font.style or DEFAULT_STYLE,
			},
			size = entry.size,
			lineHeight = entry.lineHeight,
		}
	end
	for role, entry in metrics.typography do
		publishRole(role, entry)
	end
	-- THE WEIGHT ROLES, derived when a package did not author them (F2,
	-- 2026-08-02). `strong` and `numeral` answer every package — an authored one
	-- wins, an unauthored one takes its base role's size/family/style with the
	-- derivation's weight (`pkg.deriveTypeRole`) — so `textSize = "strong"` can
	-- never resolve to nil and silently fall back to `body`.
	--
	-- DERIVED HERE AND NOT IN THE NEUTRAL DEFINITION, for exactly the reason the
	-- `iconSizes` note above records: a new authored `metrics.*` entry would move
	-- every derived package's content STAMP and invalidate stored capture
	-- evidence, for values no package wrote. Studio Neutral therefore gains the
	-- two roles without a single authored byte moving.
	for _, role in pkg.OPTIONAL_TYPE_ROLES do
		if out.type[role] == nil then
			local derived = pkg.deriveTypeRole(role, metrics.typography)
			if derived ~= nil then
				publishRole(role, derived)
			end
		end
	end
	for _, section in { "space", "radii", "strokes", "targetSizes", "motion" } do
		for k, v in (metrics :: any)[section] do
			out[section][k] = v
		end
	end
	for size, entry in metrics.controlSizes do
		out.controlSizes[size] = { height = entry.height, paddingX = entry.paddingX, iconSize = entry.iconSize }
	end
	for family, entry in metrics.controls do
		local copy: any = {}
		for k, v in entry do
			copy[k] = v
		end
		out.controls[family] = copy
	end
	for slot, entry in metrics.insets do
		out.insets[slot] = { top = entry.top, right = entry.right, bottom = entry.bottom, left = entry.left }
	end
	--[[ 1b. THE APP NAMESPACE (ADR-0042). The APP owns the names — it declared
		them once, before anything mounted — and every package publishes them, so a
		proof that has to run under Studio Neutral and under Fantasy Parchment keeps
		its geometry either way. A package may then MOVE any of them: `metrics.app`
		is a THEME's answer for an app number, exactly as `metrics.space.m` is its
		answer for a spacing step.

		REFUSE, DON'T GUESS, on the package side. A package that names an app metric
		the app never declared is authoring against a namespace it does not own, and
		the failure mode of accepting it is the worst one available: a number that
		silently never moves, on a surface nobody thought to check. Validated HERE
		rather than in `themes.define` for `metrics.tenFoot`'s reason — the
		declaration is a runtime fact and `define` may legitimately run before an app
		has made it. ]]
	out.app = appBase(declaredApp)
	if type(metrics.app) == "table" then
		local paths: { string } = {}
		local function collect(node: any, prefix: string)
			for key, value in node do
				local path = `{prefix}{tostring(key)}`
				if type(value) == "table" then
					collect(value, `{path}.`)
				else
					table.insert(paths, path)
				end
			end
		end
		collect(metrics.app, "")
		table.sort(paths)
		for _, path in paths do
			local value: any = metrics.app
			for part in string.gmatch(path, "[^%.]+") do
				value = value[part]
			end
			assert(
				writePath(out.app, path, value),
				`themes.resolve: metrics.app['{path}'] names no app metric this app declared `
					.. `(themes.declareApp reserves the names a package may move)`
			)
		end
	end
	-- every v1 slot always has an inset entry, even when the package declared
	-- none: the optional-inset slots (ADR-0019 fix round) default to zero, and a
	-- missing table here would silently drop that slot's chrome reservation
	-- below.
	for _, slot in pkg.SLOTS do
		if out.insets[slot] == nil then
			out.insets[slot] = { top = 0, right = 0, bottom = 0, left = 0 }
		end
	end
	-- chrome content insets are solver-visible: a nineSlice slot reserves them on
	-- top of the slot's authored inset (ADR-0019 §5). Recorded so the solver and
	-- the chrome materializer read ONE number.
	-- The CHROME-ONLY portion is recorded separately as well (package 3 seam):
	-- the renderer adds exactly this to a slotted node's padding, and it must
	-- not add the slot's authored inset, which describes padding the framework
	-- has never applied. Empty for every flat package — including Studio
	-- Neutral — so existing geometry is byte-identical.
	--
	-- EVERY RECIPE KIND THAT MATERIALIZES ART (director round 7, 2026-07-25).
	-- This loop used to read `kind == "nineSlice"` only, while the ADAPTER boxes
	-- a decorated node's lifted label by `contentInsets` for a LAYERED recipe
	-- too (`chrome_slots.liftGeometry`, fed the stack plan). So a layered
	-- package's insets were applied at paint and reserved by nobody: measured
	-- live under fantasy-ornate, whose `control` is a two-layer stack with
	-- `contentInsets = { 10, 14, 10, 14 }`, the toolbar's content-sized "Play"
	-- button solved to 48px (padding 24 + its own text) and its lift resolved to
	-- **-4 x 27** — a negative box, which is why the label was not merely clipped
	-- but ABSENT. The wide buttons in the same package were the other half of the
	-- same defect: a lift 28px narrower than the box the solver measured for.
	--
	-- The zero-slack watch recorded in the round-5 packet is why it surfaced now:
	-- once a content button measures exactly its engine bounds, an inset applied
	-- at paint and not at measure has nowhere left to hide.
	local INSET_BEARING_KINDS: { [string]: boolean } = { nineSlice = true, layered = true }
	out.chromeInsets = {}
	-- ...and EVERY slot answers, zero for the ones no art reserves (director
	-- round 10, 2026-07-26). This table used to hold only the slots a skinning
	-- package touched, which made `chromeInsets.<slot>.<side>` unresolvable as a
	-- theme METRIC NAME — `isMetricPath` validates against the neutral snapshot,
	-- and neutral reserved nothing, so the path did not exist to validate.
	--
	-- That mattered because the framework's own reservation is a one-way street:
	-- the renderer adds these insets to the padding of the node that CARRIES the
	-- slot, and a control whose painted surface and whose content are different
	-- nodes (a Table row is a full-bleed hit Button with a sibling cell stack)
	-- had no way to ask how much room the art wanted. It could only guess, and a
	-- guess about a theme's border is wrong in every theme but the one it was
	-- written against. Declaring the zeros here is what makes it askable.
	--
	-- Filled in `resolve`, NOT in the neutral DEFINITION, for the reason the
	-- `iconSizes` note above gives: a package's authored `metrics` — and so its
	-- content stamp — must not move for a section no package ever wrote.
	for _, slot in pkg.SLOTS do
		out.chromeInsets[slot] = { top = 0, right = 0, bottom = 0, left = 0 }
	end
	for slot, recipe in package.chrome do
		if INSET_BEARING_KINDS[recipe.kind] and type(recipe.contentInsets) == "table" and out.insets[slot] ~= nil then
			out.chromeInsets[slot] = {}
			for _, side in pkg.INSET_SIDES do
				out.insets[slot][side] += recipe.contentInsets[side]
				out.chromeInsets[slot][side] = recipe.contentInsets[side]
				if recipe.contentInsets[side] ~= 0 then
					out.hasChromeInsets = true
				end
			end
		end
	end
	-- HOW FAR A SLOT'S DEPTH CUE PAINTS OUTSIDE ITS OWN RECT (director round 11,
	-- root-caused 2026-07-27 from a landscape capture).
	--
	-- A `shadow` recipe is adapter-owned depth: the engine draws it around the
	-- node, outside the rect the solver assigned, by roughly its blur plus its
	-- offset. Layout is right to ignore that — a glow is meant to OVERLAP its
	-- neighbours, and reserving it as margin would space a themed screen out by
	-- 24px in every direction. But one consumer is not: a scroll canvas is built
	-- from the content's RECTS, so the last element's glow falls outside the
	-- canvas and is unreachable however far you scroll. Sci-Fi HUD declares a
	-- centred 24px glow on `panel` and 16px on `control`, and a landscape capture
	-- showed exactly that: scrollbar at the bottom of its track, last panel's
	-- bottom edge still cut off.
	--
	-- Published as ONE number — the deepest reach any slot declares — because it
	-- is spent as a canvas allowance, not as per-node geometry. Zero for every
	-- package that declares no shadow, so nothing without depth moves at all.
	local bleed = 0
	for _, recipe in package.chrome do
		if recipe.shadow ~= nil then
			local ok, shadow = pcall(styling.normalizeShadow, recipe.shadow)
			if ok and type(shadow) == "table" and shadow.enabled ~= false then
				local blur = shadow.blurRadius.offset or 0
				local reach = math.max(
					blur + math.abs(shadow.offset.y.offset or 0) + (shadow.spread.y.offset or 0),
					blur + math.abs(shadow.offset.x.offset or 0) + (shadow.spread.x.offset or 0)
				)
				bleed = math.max(bleed, reach)
			end
		end
	end
	out.chromeBleed = bleed

	-- THE OPTICAL GAP BETWEEN ADJACENT ICONS IN A RUN, per rung and per input
	-- paradigm (director, 2026-07-27: "it's a little too tight on compact
	-- pointer… if we're on a touch input, part of the paradigm should be slightly
	-- wider spacing for touch targets vs. what we can do with a pointer").
	--
	-- WHY IT IS NOT A SPACE STEP. A run of glyphs is spaced against the GLYPH, not
	-- against the page's rhythm, and the two ladders disagree wildly: Compact
	-- Pointer's `xs` is 2px against a 12px star (a 17% gap, which is what "too
	-- tight" looks like) while Glossy Mobile's is 6px against 16px (37%). Naming a
	-- step gives one package a comfortable run and another a smear, and no single
	-- step is right for both.
	--
	-- WHY IT IS DERIVED AND NOT AUTHORED. A new `metrics.*` section would move
	-- every derived package's content stamp and invalidate stored capture
	-- evidence — the same reason `rating.luau` declined to add `controls.rating.*`.
	-- This is computed from `iconSizes`, exactly as `chromeBleed` is computed from
	-- the chrome recipes, so a package that resizes its icon ladder moves its icon
	-- gaps with it and authors nothing.
	--
	-- THE TWO RUNGS ARE THE PARADIGM AXIS. Touch buys a wider gap because the
	-- whole run is one drag target and the gap is what makes an individual star
	-- reachable with a fingertip; a pointer lands where it is aimed and can afford
	-- the tighter, better-looking run. The ratios are deliberate literals — a
	-- proportion of a theme metric IS theme-owned, and this is the documented
	-- exception `check_theme_drift` allows.
	local iconRunGap: any = {}
	for _, rung in pkg.ICON_SIZE_ROLES do
		local px = (out.iconSizes :: any)[rung]
		iconRunGap[rung] = {
			pointer = math.max(1, math.round(px * 0.30)),
			touch = math.max(2, math.round(px * 0.45)),
		}
	end
	out.iconRunGap = iconRunGap

	-- WHICH SEMANTIC NAMES ACTUALLY PAINT A PICTURE (director report 2026-07-28).
	--
	-- An icon request is an UPGRADE, not a dependency: the control draws the
	-- framework's ASCII character itself and a package's art paints over it. That
	-- arrangement is right, and it left one thing unanswered — the picture is a
	-- FIXED px square from `iconSizes`, and the node under it was measured as the
	-- character. `">"` is 6px wide; Fantasy Ornate's `medium` rung is 32. So the
	-- picture painted 13px outside its own node on every side, reaching the frame
	-- beside it and the label after it. Measured live under all nine reference
	-- configurations: SEVEN overhang, Studio Neutral included.
	--
	-- The measure seam has to reserve the picture's box, and to do that it must
	-- know whether there IS a picture — because the two packages that looked
	-- correct (glossy-touch, compact-pointer) are correct precisely because they
	-- draw no art, and reserving 20px of nothing for them would fix seven packages
	-- by breaking the two that were already right.
	--
	-- The solver holds the SNAPSHOT, never the package, so the answer rides here.
	-- DERIVED, exactly like `chromeBleed` above and `iconRunGap` beside it: no new
	-- authored `metrics.*` section, so no package's content stamp moves and no
	-- stored capture evidence is invalidated (the constraint the `iconSizes` note
	-- at the top of this function records).
	--
	-- The vocabulary is the union of the framework's own glyph table (every name a
	-- control may request) and whatever else the package mapped art at, so a
	-- package that invents a name still gets its box.
	local iconArt: { [string]: boolean } = {}
	local function noteIcon(name: string)
		local resolved = pkg.resolveIcon(package, name)
		if type(resolved) == "table" and resolved.source == "asset" then
			iconArt[name] = true
		end
	end
	for name in pkg.ICON_FALLBACK_GLYPHS :: any do
		noteIcon(name)
	end
	if type(package.iconArt) == "table" then
		for name in package.iconArt :: any do
			noteIcon(name)
		end
	end
	out.iconArt = iconArt

	-- THE TABLE ROW BOX, per input paradigm (director, 2026-07-27: "generally, we
	-- likely want taller table cells on mobile for touch targeting. that seems like
	-- the paradigm adaptation facet should handle").
	--
	-- A ROW IS DESCRIBED BY THE LINES IT HOLDS, not by a pixel count, and that is
	-- the whole idea. `rowLines` is the paradigm constant — a pointer table is the
	-- dense one-line list every desktop table has been since the Finder, and a touch
	-- table gets two, because the columns a thumb-width phone leaves are narrow
	-- enough that a real title wraps (measured: "Drift City Nights" takes three at
	-- 15px in the 136px the playlist's name column gets at 393pt). `rowHeight` is
	-- then the FLOOR that description implies at the theme's own authored text size,
	-- and `Table` re-derives the live height from it once the accessibility text
	-- offset and the ten-foot scale are known — which the snapshot cannot see.
	--
	-- WHY A FLOOR AND NOT THE ANSWER: `targetSizes.minimum` has to win on touch even
	-- for a theme whose cell text is tiny, or the paradigm adaptation would hand a
	-- fingertip a 30px row. And `controlSizes.compact.height` is the pointer floor
	-- because a table row IS a compact control row — the same rung PopupButton's menu
	-- uses — so a table sitting beside other controls keeps the theme's own rhythm.
	--
	-- DERIVED AND NOT AUTHORED, for exactly `iconRunGap`'s reasons: a new authored
	-- `metrics.*` key would move every derived package's content stamp and invalidate
	-- stored capture evidence, while every input here (`cellTextSize`, the body role's
	-- line height, `targetSizes`, `controlSizes`, `space`) is already theme-owned — so
	-- a package that enlarges its cell text or its touch floor moves its rows with it
	-- and authors nothing.
	local tableFamily: any = (out.controls :: any).table
	if type(tableFamily) == "table" then
		local cellSize = if type(tableFamily.cellTextSize) == "number"
			then tableFamily.cellTextSize
			else (out.type :: any).body.size
		local lineBox = math.ceil(cellSize * (out.type :: any).body.lineHeight)
		-- the row's own vertical breathing room, one space step at each edge
		local padV = (out.space :: any).xs
		--[[ THREE RUNGS, AND THE THIRD IS DISTANCE (2026-08-18). There
			were two — `pointer` and `touch` — and a television resolved `pointer`,
			the densest row the framework ships, at three metres. The audit measured
			it as a 41px button inside a 36px row on a shipped example once the
			ten-foot type floor reached unauthored text.

			`tenFoot` HOLDS ONE LINE, like the pointer rung: at a Large display class
			the line itself is already 1.5x, so a second line is not what a TV row
			needs. What it needs is the FLOOR of a control you operate from a sofa,
			and this framework already names that box — `controlSizes.large.height`,
			the same rung a large button takes. Derived like its two neighbours, from
			metrics the theme already owns, so a package that enlarges its controls
			moves its distant rows with it and authors nothing.

			THE ORDER IS A CONSEQUENCE, NOT A CHOICE: `large` > `minimum` > `compact`
			in every legal package (a large control cannot be smaller than the touch
			floor, which cannot be smaller than a compact row), so the ten-foot rung
			is the tallest without this file asserting it. ]]
		local lines = { pointer = 1, touch = 2, tenFoot = 1 }
		tableFamily.rowLines = lines
		tableFamily.rowPadding = padV
		tableFamily.rowHeight = {
			pointer = math.max((out.controlSizes :: any).compact.height, lines.pointer * lineBox + 2 * padV),
			touch = math.max((out.targetSizes :: any).minimum, lines.touch * lineBox + 2 * padV),
			tenFoot = math.max((out.controlSizes :: any).large.height, lines.tenFoot * lineBox + 2 * padV),
		}
	end

	-- ...and the ONE-WORD ANSWER to "does any slot reserve anything at all?".
	-- The renderer asks this per NODE to decide whether to classify at all, and
	-- it used to ask it as `next(chromeInsets) ~= nil` — which was free only
	-- while the table was empty for flat packages. Now that every slot answers
	-- (see above), the cheap exit has to be a fact the snapshot carries rather
	-- than a shape it happens to have, or a flat theme would pay a slot
	-- classification on every node of every solve.
	out.hasChromeInsets = out.hasChromeInsets == true
	-- CHROME OUTSETS: what a slot's art paints OUTSIDE its own rect, published so
	-- the solver can clear the NEIGHBOURS (director fix round 2026-07-25 — a bar
	-- cap sat on the label at one end, the readout at the other and the row
	-- above). `chromeInsets` above reserves INWARD, for this node's own content;
	-- this reserves OUTWARD, as the node's margin, and the renderer adds exactly
	-- one of them at each seam.
	--
	-- EVERY SLOT FAMILY THAT PAINTS OUTSIDE ITS RECT (the rich-skinning v2 decision, found live: the
	-- ornate plaque's declared `overhang` was validated, painted and censused
	-- while this table had a single writer — the bar branch — so the nameplate
	-- painted through the label of the row above it, 792 px2 at desktop). Both
	-- families are DERIVED, never authored, from the boxes the adapter
	-- materializes: `chrome_slots.outwardExtents` reads the layer stacks (the same
	-- per-slot numbers `census.overhang` publishes) and
	-- `chrome_slots.barReservation` reads the cap/centrepiece against the track's
	-- resolved cross extent. A package with no plaque and no bar ornament reserves
	-- nothing and this table stays EMPTY — the flat/Studio-Neutral case,
	-- byte-identical by construction.
	-- (filled in below, after the pixel snap: an extent is measured against
	-- RESOLVED metrics, so it has to see the snapped numbers)
	out.chromeOutsets = {}

	--[[ 2. display/density policy: recorded, never re-applied (see the note above).
		WHAT "RE-APPLIED" NOW MEANS (ADR-0039). The director's ten-foot ruling gave
		this fact a consequence — the whole metric ladder scales by 1.5 at a Large
		display — and it is applied in `snapshot.forDisplay`, called from the
		ENVIRONMENT's `themeMetrics` memo over the LIVE display fact, never here.
		That is not tidiness: a snapshot's facts are whatever it happened to be
		resolved with, and the environment's default snapshot is `neutral()`,
		resolved with no facts at all, so a television with no theme controller
		installed would carry `near` forever. The value below stays as
		the record of THIS resolve, which is what a caller holding only a snapshot
		and no environment reads (`text_fit.facts({ metrics = … })`). ]]
	out.density = if f.displaySize == "Large" then "ten-foot" else "near"
	-- 3. preferred-text reservation inputs: carried for inspection, applied once
	-- at the renderer's measure seam
	out.preferredText = {
		multiplier = if type(f.preferredTextSize) == "number" then f.preferredTextSize else 1,
		offset = if type(f.preferredTextOffset) == "number" then f.preferredTextOffset else 0,
	}

	-- 4. accessibility floors, clamping UP only
	out.targetSizes.minimum = math.max(pkg.MIN_TARGET_SIZE, out.targetSizes.minimum or 0)

	-- 4a. THE CIRCLE BUTTON'S DIAMETER (`shape = "circle"`, feature round
	-- 2026-07-26). A disc is sized by ONE control metric so the author never does
	-- the math: `controls.button.height`, resolved here exactly as `iconSizes` is,
	-- and for the same recorded reason (see the NOTE beside `iconSizes` in
	-- `neutralDefinition`). Declaring it in the neutral DEFINITION would move the
	-- authored metrics — and therefore the content STAMP — of every package
	-- derived from Studio Neutral, invalidating stored captures for a value no
	-- package wrote. Filling it in here means every theme answers
	-- `controls.button.height` while nobody's authored data moves.
	--
	-- The default is the 44px touch floor above, so it is one number with the hit
	-- floor rather than a second literal that can drift from it; a metric package
	-- that authors its own wins, and the pixel snap below rounds it onto the grid.
	local buttonFamily = out.controls.button
	if type(buttonFamily) ~= "table" then
		buttonFamily = {}
		out.controls.button = buttonFamily
	end
	if type(buttonFamily.height) ~= "number" then
		buttonFamily.height = out.targetSizes.minimum
	end

	--[[ 4a-ante. THE SCREEN-EDGE GUTTER, WITH A FLOOR (DIR wave contract 6,
		2026-08-18; device round 2026-08-17).

		THE STEP EVERY SURFACE WAS SPENDING WAS `space.s`, and a screen edge is not
		a spacing decision — it is a physical one. `space.s` is what a package
		chooses for "the small gap between two things"; a phone's rounded corner and
		its bezel eat a fixed number of pixels whatever a package thinks a small gap
		is. Under `classic_desktop` (`s = 4`) and `compact_pointer` (`s = 6`) the
		showcase's own chip strip therefore stood 4px and 6px off the glass, and the
		director photographed its left border clipped.

		WHY THIS IS A DERIVED STEP AND NOT A RAISED `space.s` — MEASURED, not
		preferred. Raising `classic_desktop.space.s` from 4 to 8 was tried first and
		run through the whole suite: it re-widened every gap, every
		`chromeInsets.selection` and every derived row gutter in the package, and
		FOUR unrelated showcase surfaces (`sponsor_drop`, `row_actions`,
		`p2_cartwheel`, `p4_foyer`) began overflowing their own boxes under
		classic-desktop at the swept viewports. A dense desktop package's 4px gaps
		between rows are correct; its 4px screen EDGE is not, and one token cannot
		carry both answers.

		So `gutter` is a sixth, DERIVED space step: a package's own `s` unless that
		is under the floor. A package that breathes more keeps its own number
		(glossy_mobile and glossy_touch stay at 10), and a package may author
		`space.gutter` outright to say something different — an authored value still
		wins, exactly as it does for `controls.rowActions.trayGap` below.

		FILLED HERE, NOT IN THE NEUTRAL DEFINITION, for the reason every derived
		metric under this comment carries: an authored `metrics.*` entry would move
		the authored metrics — and therefore the CONTENT STAMP — of every package
		derived from Studio Neutral, for a value no package wrote. It is above the
		pixel-unit snap below, so a pixel package's gutter lands on its own grid.

		The guard is `tests/gallery_chrome.spec.luau` ("no package's screen-edge
		step is under the 8px floor"), which asserts the METRIC and the SOLVED strip
		so neither half can drift away from the other. ]]
	if type(out.space.gutter) ~= "number" then
		out.space.gutter = math.max(SCREEN_GUTTER_FLOOR, out.space.s)
	end

	-- 4a-bis. THE ROW-ACTION TRAY'S OWN GUTTER (director device round 2026-08-12).
	-- Two rounded tray plates drawn flush read as one merged slab, and mid-flight
	-- the sliding row content merged with the first of them. The separation is a
	-- SPACING decision, so it comes from the theme's own space scale rather than a
	-- literal in the control — `space.xs`, the smallest step the scale names, which
	-- is the hairline-to-4px gutter convention for swipe actions.
	--
	-- Filled in HERE, exactly as `controls.button.height` above and for the same
	-- recorded reason: declaring it in the neutral DEFINITION would move the
	-- authored metrics (and the content stamp) of every package derived from
	-- Studio Neutral. A package that authors its own wins; the pixel snap below
	-- rounds it onto the grid.
	local rowActionsFamily = out.controls.rowActions
	if type(rowActionsFamily) ~= "table" then
		rowActionsFamily = {}
		out.controls.rowActions = rowActionsFamily
	end
	if type(rowActionsFamily.trayGap) ~= "number" then
		rowActionsFamily.trayGap = out.space.xs
	end
	-- ...and the gutter between the ROW and the band beside it (device BUG round
	-- 2026-08-12, findings A1a/A2: "the trash tray butts straight against the row
	-- with zero negative space", and the edit-mode minus doing the same on the
	-- leading edge). One step up the same scale from `trayGap`, because it is a
	-- different decision: `xs` separates two plates INSIDE one group, `s`
	-- separates the group from the surface it sits against — without that
	-- difference the band reads as part of the row it is acting on. Filled here
	-- for the same stamp reason `trayGap` is.
	if type(rowActionsFamily.rowGutter) ~= "number" then
		rowActionsFamily.rowGutter = out.space.s
	end
	-- ...and the indeterminate spinner's dot (parity round 2 §3.1). Filled here
	-- for the same stamp reason the two above are. `space.s` rather than a fresh
	-- literal: a spinner dot is a token on the same scale as every other small
	-- inter-element measure, and a package that authors its own still wins.
	local progressFamily = out.controls.progress
	if type(progressFamily) == "table" and type(progressFamily.spinnerDotSize) ~= "number" then
		progressFamily.spinnerDotSize = out.space.s
	end
	-- ...and the CIRCULAR indicator (parity round 3 D2), filled here for the same
	-- stamp reason. `space.l` because the only size guidance is "prefer an
	-- activity indicator when space is constrained" — so it is the small end of
	-- the theme's own scale, not a number this control invented.
	--
	-- THE THICKNESS IS FILLED AGAINST THE SIZE, and that is the whole reason it is
	-- computed HERE rather than picked in the control. A Path2D stroke is centred
	-- on its curve, so a ring drawn at radius fraction R inside a box of D paints
	-- out to `R*D/2 + thickness/2`; a stroke thicker than `(1-R)*D` paints outside
	-- the box the solver measured, which is the "painted at a size nobody
	-- measured" family and is invisible to every headless diagnostic. The control
	-- receives both numbers only as METRIC NAMES (it never resolves a snapshot),
	-- so this function — where both numbers exist — is the only place the
	-- relationship can be guaranteed rather than hoped for. A package that authors
	-- its own thickness still wins; it also owns the consequence.
	if type(progressFamily) == "table" then
		if type(progressFamily.circularSize) ~= "number" then
			progressFamily.circularSize = out.space.l
		end
		if type(progressFamily.circularThickness) ~= "number" then
			-- (1 - CIRCULAR_RADIUS) = 0.2 of the diameter is the stroke's whole
			-- budget; `space.xs` unless the theme's small step is wider than that.
			local budget = math.floor(progressFamily.circularSize * 0.2)
			local thickness = math.max(1, math.min(out.space.xs, budget))
			-- ...and it is pre-snapped DOWN onto a pixel theme's grid, because 4b
			-- below snaps every published length UP: a value that is already a
			-- multiple of the unit is left alone, while one that is not would be
			-- rounded up past the budget this line just computed.
			local unit = pkg.pixelUnitOf(package)
			if unit ~= nil then
				thickness = math.max(unit, math.floor(thickness / unit) * unit)
			end
			progressFamily.circularThickness = thickness
		end
	end

	-- 4b. PIXEL SNAP (ADR-0020 R5, generation rule 3; probe rs-m5). A pixel
	-- package declares an integer coordinate system, and every LENGTH the
	-- snapshot publishes snaps UP to the next multiple of it. Up, never down, for
	-- the ADR-0019 reason floors clamp up: rounding a 44px target floor down to 40
	-- would defeat an accessibility guarantee with a rendering flag.
	--
	-- WHY LENGTHS ONLY. `motion` is seconds and `lineHeight` is a ratio — snapping
	-- either to a multiple of 4 would turn a 0.12s fade into a 4-second one. The
	-- sections below are exactly the px-valued ones; a `type` role's SIZE is a
	-- length (a pixel font is drawn on the same grid) while its lineHeight is not.
	--
	-- Placed AFTER the floors and BEFORE the overrides on purpose: an explicit
	-- override is documented as marking that value theme-independent, so it stays
	-- the exact number the caller asked for rather than being quietly moved.
	local pixelUnit = pkg.pixelUnitOf(package)
	if pixelUnit ~= nil then
		local unit: number = pixelUnit
		local function snap(value: any): any
			return if type(value) == "number" then pkg.snapToPixelUnit(value, unit) else value
		end
		for _, section in { "space", "radii", "strokes", "targetSizes", "iconSizes" } do
			for key, value in out[section] do
				out[section][key] = snap(value)
			end
		end
		for _, entry in out.controlSizes do
			entry.height, entry.paddingX, entry.iconSize =
				snap(entry.height), snap(entry.paddingX), snap(entry.iconSize)
		end
		for _, family in out.controls do
			for key, value in family do
				family[key] = snap(value)
			end
		end
		for _, group in { out.insets, out.chromeInsets } do
			for _, sides in group do
				for _, side in pkg.INSET_SIDES do
					sides[side] = snap(sides[side])
				end
			end
		end
		for _, role in out.type do
			role.size = snap(role.size)
		end
		--[[ …AND THE APP SECTION, BY CLASSIFICATION (ADR-0042). It is the one
			section here whose leaves are not all lengths — an app declares fractions,
			counts and seconds beside its boxes — so this walk asks
			`densityClassOf` rather than snapping everything it finds. Snapping a
			0.52 map fraction onto a 4px grid is 4, which is not a smaller number,
			it is a corrupt solve.

			IT MATTERS EVEN THOUGH `forDisplay` SNAPS AGAIN: `forDisplay` scales from
			this snapshot, so an app length that skipped the grid here would be the
			one number in the package measured off it, and the near answer would
			disagree with the distant one about which coordinate system it is on. ]]
		local function snapApp(node: any, prefix: string)
			for key, value in node do
				local path = `{prefix}{tostring(key)}`
				if type(value) == "table" then
					snapApp(value, `{path}.`)
				elseif type(value) == "number" then
					local class = snapshot.densityClassOf(`app.{path}`)
					if class == "scale" or class == "scaleWhole" then
						node[key] = snap(value)
					end
				end
			end
		end
		snapApp(out.app, "")
		-- published so the adapter can stamp Pixelated on the images it creates
		-- OUTSIDE the sheet (icons), and so a dump can assert the unit that
		-- produced these numbers rather than inferring it
		out.pixelUnit = unit
	end

	-- 4c. THE OUTWARD RESERVATIONS, one writer for every slot family (director fix
	-- round 2026-07-25 for the bar; the rich-skinning v2 decision for the layer stacks). Both are
	-- derived from the boxes the adapter materializes and both are measured
	-- against RESOLVED metrics — which is why this runs here, after 4b snapped
	-- them, rather than beside `chromeInsets`.
	--
	-- ONE LOOP, so a family cannot be added to the census and forgotten here: the
	-- layer half reads `chrome_slots.outwardExtents`, which is the same
	-- `layerPlanFor(...).overhang` the census publishes, and a spec asserts that
	-- every censused extent has a reservation.
	do
		local progress = out.controls.progress
		local trackHeight = if type(progress) == "table" and type(progress.trackHeight) == "number"
			then progress.trackHeight
			else 0
		local families: { { [string]: any } } = {
			-- LAYER STACKS: a plaque's declared `overhang` renders outside the
			-- decorated rect (rs-m3), so the neighbours have to move
			chrome_slots.outwardExtents(package),
			-- THE BAR ORNAMENTS: a cap is centred ON the track's end and the
			-- centrepiece on its middle, so both extend past the rail
			{ barTrack = chrome_slots.barReservation(package, trackHeight) },
		}
		for _, extents in families do
			for slot, declared in extents do
				local reserved = { top = 0, right = 0, bottom = 0, left = 0 }
				local any = false
				for _, side in pkg.INSET_SIDES do
					local px = declared[side] or 0
					if pixelUnit ~= nil then
						px = pkg.snapToPixelUnit(px, pixelUnit :: number)
					end
					reserved[side] = px
					any = any or px > 0
				end
				if any then
					out.chromeOutsets[slot] = reserved
				end
			end
		end
	end

	-- 5. explicit overrides. Each one marks that property THEME-INDEPENDENT: the
	-- next package swap re-resolves everything else and re-applies these, so an
	-- override is a deliberate opt-out rather than a value that silently drifts.
	local applied: { any } = {}
	if overrides ~= nil then
		local paths: { string } = {}
		for path in overrides do
			table.insert(paths, path)
		end
		table.sort(paths)
		for _, path in paths do
			local value = overrides[path]
			assert(
				writePath(out, path, value),
				`themes.resolve: override '{path}' names no metric in this snapshot `
					.. `(use a dotted path such as "space.m" or "controls.slider.thumbSize")`
			)
			table.insert(applied, { path = path, value = value })
		end
		-- an override may not defeat the accessibility floor
		out.targetSizes.minimum = math.max(pkg.MIN_TARGET_SIZE, out.targetSizes.minimum)
	end
	out.overrides = applied

	--[[ 6. THE PACKAGE'S OWN TEN-FOOT LADDER, carried but not applied (the
		metric-ladder contract, clause 2). `metrics.tenFoot` is a map of dotted metric paths to ABSOLUTE
		ten-foot pixel values — the same vocabulary `resolve`'s own `overrides`
		parameter takes, deliberately, so a package author spells a television
		metric the way they already spell a local one.

		VALIDATED HERE, against THIS package's finished snapshot rather than against
		neutral: a path is checked for existing and for naming a NUMBER, so a typo
		("space.enormous") is an authoring error at resolve time instead of a silent
		no-op on a television nobody in the studio owns. It is checked after the
		floors, the pixel snap and the overrides for the same reason `writePath`
		runs there — those are the numbers the declaration replaces.

		APPLIED in `forDisplay`, which is the only place a ten-foot value means
		anything; a near display never reads this table. `resolve` goes on recording
		display facts and re-applying none of them. ]]
	local declared: any = {}
	if type(metrics.tenFoot) == "table" then
		local paths: { string } = {}
		for path in metrics.tenFoot :: any do
			table.insert(paths, tostring(path))
		end
		table.sort(paths)
		for _, path in paths do
			local value = (metrics.tenFoot :: any)[path]
			assert(
				hasPath(out, path),
				`themes.resolve: metrics.tenFoot['{path}'] names no metric in this package's snapshot `
					.. `(use a dotted path such as "space.m" or "targetSizes.minimum")`
			)
			assert(
				type(value) == "number" and value == value,
				`themes.resolve: metrics.tenFoot['{path}'] must be a number of pixels at ten-foot distance`
			)
			declared[path] = value
		end
	end
	out.tenFoot = declared
	-- the factor THIS snapshot carries. An authored base is always 1: it is the
	-- near ladder, and `forDisplay` is what publishes 1.5.
	out.metricScale = 1

	out.identity = {
		packageId = package.identity.id,
		version = package.identity.version,
		themeName = name,
		stamp = package.stamp,
	}
	local frozen = frozenClone(out)
	-- the vocabulary this snapshot was resolved against (see `withCurrentApp`):
	-- a later declaration is what makes it stale, and `forDisplay` is where that
	-- is noticed
	appGenerations[frozen] = declaredAppGeneration
	return frozen
end

--[[ EVERY NEUTRAL THIS MODULE HAS EVER ISSUED, weakly.

	`declareApp` drops the memo, so a process that declares a namespace produces a
	SECOND neutral — and an environment created before that declaration is holding
	the first one, resolved against a vocabulary that no longer exists. This set is
	how the environment recognises "nobody has committed a theme here, this is
	still the framework's own default" and reads the current one instead
	(`env/environment.luau`'s `themeMetrics` memo). Weak, so a dropped neutral
	collects; membership, not identity with the LIVE one, because there may be
	several generations alive at once. ]]
local neutralsIssued: any = setmetatable({}, { __mode = "k" })

-- the snapshot every screen gets for free: Studio Neutral, no facts, no
-- overrides. Values are byte-identical to the literals the framework shipped
-- before theme packages existed.
function snapshot.neutral(): any
	if neutralCache == nil then
		neutralCache = snapshot.resolve(snapshot.neutralPackage(), nil, {}, nil)
		neutralsIssued[neutralCache] = true
	end
	return neutralCache
end

--[[ is this snapshot one `neutral()` produced — i.e. has NOBODY committed a
	theme to the surface holding it?

	The one caller is the environment's `themeMetrics` memo, and the question it is
	really asking is "may I re-read the default?". A package snapshot must never be
	silently replaced; the framework's own default may be, because it is the value
	the environment seeded ITSELF with and its whole content is derivable. ]]
function snapshot.isFrameworkDefault(snap: any): boolean
	return type(snap) == "table" and neutralsIssued[snap] == true
end

-- ===== metric-reference resolution =========================================

-- a dotted path into a snapshot; nil when it names nothing numeric
local function lookupPath(snap: any, path: string): number?
	local node: any = snap
	for part in string.gmatch(path, "[^%.]+") do
		if type(node) ~= "table" then
			return nil
		end
		node = node[part]
	end
	return if type(node) == "number" then node else nil
end

-- Per-snapshot memo for string metric resolution (integration find,
-- 2026-07-25): migrated controls resolve names like
-- "controls.table.cellTextSize" inside MEASURE loops, and per-call gmatch
-- parsing put the table-mutation bench 2x over its pinned p95 baseline.
-- A snapshot is frozen, so a name's resolution can never change for a given
-- snapshot; `false` caches a miss. Weak keys let dead snapshots collect.
local resolveMemo: any = setmetatable({}, { __mode = "k" })

local function memoFor(snap: any): any
	local m = resolveMemo[snap]
	if m == nil then
		m = {}
		resolveMemo[snap] = m
	end
	return m
end

function snapshot.isTypeRole(name: any): boolean
	if type(name) ~= "string" then
		return false
	end
	for _, role in pkg.TYPE_ROLES do
		if role == name then
			return true
		end
	end
	return false
end

function snapshot.isSpaceStep(name: any): boolean
	if type(name) ~= "string" then
		return false
	end
	-- the RESOLVABLE vocabulary, which is the required steps plus the derived ones
	-- (`gutter`): every one of these answers a number on every snapshot, and a
	-- name a solve resolves but the blueprint boundary refuses would be a metric
	-- nobody could spell
	for _, step in pkg.SPACE_STEPS do
		if step == name then
			return true
		end
	end
	return false
end

-- does this string name a metric in the CANONICAL (neutral) namespace? The
-- schema validates against neutral because neutral defines the v1 vocabulary
-- every package inherits, so a typo is caught at construction rather than
-- becoming a nil size on the first solve of a themed screen.
function snapshot.isMetricPath(name: any): boolean
	if type(name) ~= "string" then
		return false
	end
	if string.find(name, "%.") == nil then
		-- A TOP-LEVEL numeric fact is a metric too (2026-07-27). The dot was a
		-- cheap proxy for "this names a section entry", and it held while every
		-- number lived inside `space` / `radii` / `controls` / … — but the
		-- snapshot also publishes whole-package scalars, and `chromeBleed` (how
		-- far a package's shadow paints outside its box) is one a layout has to be
		-- able to NAME: a clipper insets its content by it, and a Table's header
		-- has to name the same thing to stay aligned with rows that do.
		--
		-- Still closed, and still validated against the neutral snapshot: a name
		-- only passes if it resolves there AND resolves to a NUMBER, so a typo or
		-- a table-valued section (`insets`, `type`) is rejected exactly as before.
		-- Space steps are dotless too and keep their own branch below.
		return type(lookupPath(snapshot.neutral(), name)) == "number"
	end
	return lookupPath(snapshot.neutral(), name) ~= nil
end

-- resolveNumber: a literal number passes through; a space step or dotted path
-- resolves against `snap`. Returns nil for an unresolvable name so the caller
-- can decide (the schema rejects at construction; the renderer falls back).
function snapshot.resolveNumber(snap: any, value: any): number?
	if type(value) == "number" then
		return value
	end
	if type(value) ~= "string" then
		return nil
	end
	local memo = memoFor(snap)
	local hit = memo[value]
	if hit ~= nil then
		return if hit == false then nil else hit
	end
	local result: number?
	-- a leading "-" negates the metric. Offsets pull INWARD from an anchored
	-- edge, so the sign belongs to the call site while the magnitude stays
	-- theme-owned; without this a control would have to keep the number.
	if string.sub(value, 1, 1) == "-" then
		local magnitude = snapshot.resolveNumber(snap, string.sub(value, 2))
		result = if magnitude ~= nil then -magnitude else nil
	elseif snapshot.isSpaceStep(value) then
		result = (snap.space :: any)[value]
	else
		result = lookupPath(snap, value)
	end
	memo[value] = if result == nil then false else result
	return result
end

-- the typography role entry named by `value`, or nil when it is a literal size
function snapshot.roleOf(snap: any, value: any): any
	if type(value) ~= "string" then
		return nil
	end
	return (snap.type :: any)[value]
end

-- THE INTRINSIC TEXT ROLE, per class — the typography role a text-bearing node
-- draws at when its author named no `textSize` (director fix round 2026-07-25).
--
-- WHY IT IS A PUBLISHED TABLE AND NOT TWO SETS OF LITERALS. The measure seam
-- resolved these roles and the PAINT seam did not: the adapter wrote a hardcoded
-- TextSize 16 at creation, and no rule and no prop ever moved it. So a package's
-- `type.control.size` was accepted at compile, reserved by the solver, and then
-- ignored by the engine — the accepted-and-ignored class, and the root cause of
-- the compact-pointer "Pla/y" wrap: the solver reserved 20px for "Play" at that
-- package's 13px control role while the engine drew it at 16px (24px wide) into
-- a 20px lifted box. Measured live at desktop, stamp 38ee8cf3-1659732.
--
-- One table, read by the renderer's measure seam AND written by its paint seam,
-- so the two cannot disagree again. A class absent here draws no text of its own.
snapshot.INTRINSIC_TEXT_ROLE = table.freeze({
	Text = "body",
	Button = "control", -- a LABEL button; a content button draws no text
	Toggle = "body",
	TextField = "control",
})

-- effectiveTypeRole(snap, class, textSize) -> (roleName, roleEntry) — THE
-- typography role a text-bearing node actually wears, or nil for neither.
--
-- ONE FUNCTION, TWO SEAMS (F2, 2026-08-02). The measure seam reads it to key
-- `text_metrics` on the role's font DESCRIPTOR, and the paint seam reads it to
-- write the node's FontFace. That is the whole reason the weight channel is a
-- role rather than a `weight` prop: `Text.font` reached measurement and never
-- paint, so an authored face made the reserved box and the drawn glyphs disagree
-- (its deprecation entry says so verbatim). Two call sites resolving the role
-- independently would rebuild that split one level up, so they share this.
--
-- A NAMED role wins; otherwise the class's intrinsic role (`Text` -> body,
-- `Button` -> control, …); a literal px size names no role at all, and gets the
-- class's intrinsic face so a size override never silently changes the family.
function snapshot.effectiveTypeRole(snap: any, class: string?, textSize: any): (string?, any)
	if type(snap) ~= "table" or type(snap.type) ~= "table" then
		return nil, nil
	end
	if type(textSize) == "string" then
		local entry = (snap.type :: any)[textSize]
		if entry ~= nil then
			return textSize, entry
		end
	end
	local role = if type(class) == "string" then (snapshot.INTRINSIC_TEXT_ROLE :: any)[class] else nil
	if role == nil then
		return nil, nil
	end
	local entry = (snap.type :: any)[role]
	return (if entry ~= nil then role else nil), entry
end

-- intrinsicTextSize(snap, class) -> the px a class draws unstyled text at, or
-- nil when the class has no intrinsic text.
function snapshot.intrinsicTextSize(snap: any, class: string?): number?
	local role = if type(class) == "string" then (snapshot.INTRINSIC_TEXT_ROLE :: any)[class] else nil
	if role == nil or type(snap) ~= "table" or type(snap.type) ~= "table" then
		return nil
	end
	local entry = (snap.type :: any)[role]
	return if type(entry) == "table" then entry.size else nil
end

-- toggleRowPadding(snap): the ONE description of a Toggle row's box —
-- label column on the left, the switch reserved on the right.
--
-- WHY IT IS A FUNCTION AND NOT TWO COPIES (director round 9, found live
-- 2026-07-26). The renderer's measure seam built this table from the LIVE
-- snapshot while the adapter boxed the label from constants captured when the
-- ScreenTarget was CONSTRUCTED — `style.space.s + 4` and `style.space.m` of
-- whatever package was installed at boot. Under Studio Neutral the two happen
-- to agree exactly (space.s = 8 -> 12 = trackInset, space.m = 16), so the
-- divergence was invisible for four stages. Under classic-desktop (space.m = 8)
-- the solver reserved a 28 px label column and the adapter drew a 20 px one;
-- under sci-fi (space.m = 14) it reserved 40 and drew 38. The label clipped to
-- "Mu" and "Musi" respectively — the director's report, exactly.
--
-- Every number is theme-owned, and both consumers now read this.
function snapshot.toggleRowPadding(snap: any): { top: number, right: number, bottom: number, left: number }
	local toggle = ((if type(snap) == "table" then snap.controls else nil) or {}).toggle or {}
	local space = (if type(snap) == "table" then snap.space else nil) or {}
	local trackWidth = if type(toggle.trackWidth) == "number" then toggle.trackWidth else 44
	local trackInset = if type(toggle.trackInset) == "number" then toggle.trackInset else 12
	local gap = if type(space.m) == "number" then space.m else 16
	local pad = if type(space.xs) == "number" then space.xs else 8
	return {
		top = pad,
		bottom = pad,
		left = trackInset,
		right = trackWidth + trackInset + gap,
	}
end

-- ===== the circle Button's two shared decisions ============================
--
-- `UI.Button{ shape = "circle" }` is a TRUE 1:1 disc whose diameter is a control
-- metric, so a metric package resizes it and a pixel package snaps it without
-- any call site doing arithmetic. Both facts below have MORE THAN ONE consumer —
-- the renderer's measure seam, its paint seam, and the headless specs — and the
-- toggle row three functions up is the recorded reason they are functions: two
-- copies of the same theme arithmetic silently disagreed for four stages.

-- circleDiameter: the px a circle Button is BOTH wide and tall. `resolve` fills
-- `controls.button.height` in for every package (see step 4a there), so this
-- fallback only covers a hand-built metrics table in a test.
function snapshot.circleDiameter(snap: any): number
	local button = ((if type(snap) == "table" then snap.controls else nil) or {}).button or {}
	if type(button.height) == "number" and button.height > 0 then
		return button.height
	end
	local targets = (if type(snap) == "table" then snap.targetSizes else nil) or {}
	return if type(targets.minimum) == "number" then targets.minimum else 44
end

-- buttonPadding: the effective padding of a Button, authored value first.
--
-- A CIRCLE'S DEFAULT IS ZERO and a rectangle's is the theme's button padding.
-- The diameter IS the box: a disc that also reserved 12 px on each side would
-- have 20 px of content room inside a 44 px target, which is less than the
-- three characters the shape is documented to hold. An authored `padding` still
-- wins on either shape — that is the escape hatch, and it is explicit.
function snapshot.buttonPadding(snap: any, props: any): any
	local authored = snapshot.resolveSides(snap, if type(props) == "table" then props.padding else nil)
	if authored ~= nil then
		return authored
	end
	if type(props) == "table" and props.shape == "circle" then
		return 0
	end
	local controls = (if type(snap) == "table" then snap.controls else nil) or {}
	local button = controls.button or {}
	return if type(button.padding) == "number" then button.padding else 12
end

-- resolveSize: a typography role name or a literal px size
function snapshot.resolveSize(snap: any, value: any): number?
	if type(value) == "number" then
		return value
	end
	local role = snapshot.roleOf(snap, value)
	if role ~= nil then
		return role.size
	end
	return snapshot.resolveNumber(snap, value)
end

-- resolveSides: number | metric name | { top?, right?, bottom?, left? } whose
-- side values may themselves be metric names. Returns the same SHAPE (so the
-- solver's `sides()` and the adapter's padding write behave exactly as before).
function snapshot.resolveSides(snap: any, value: any): any
	if value == nil or type(value) == "number" then
		return value
	end
	if type(value) == "string" then
		return snapshot.resolveNumber(snap, value)
	end
	if type(value) ~= "table" then
		return value
	end
	local resolved: any = nil
	for side, raw in value do
		if type(raw) == "string" then
			resolved = resolved or table.clone(value)
			resolved[side] = snapshot.resolveNumber(snap, raw)
		elseif type(raw) == "table" then
			-- A SIDE MAY ADD SEVERAL METRICS TOGETHER (2026-07-27). The vocabulary
			-- could say "this side is a theme metric" and "this side is a number",
			-- but not "this side is one PLUS the other" — and three separate things
			-- were blocked on exactly that wall, `table.luau`'s own edit-mode
			-- comment among them ("a metric name and a number cannot be added
			-- here"). A control cannot pre-compute it either, because metrics
			-- resolve per solve and a control builds its blueprint once.
			--
			-- The case that forced it: a clipping ScrollView insets its content by
			-- the package's shadow reach so the glow is not cut at its edge, and a
			-- Table's header sits OUTSIDE that viewport yet has to line its columns
			-- up with rows that are inset by the viewport's gutter AND by their own
			-- card's carved border. Two gutters at two nesting levels, so the
			-- header's inset is their SUM — `chromeBleed + chromeInsets.selection.left`.
			--
			-- Every entry is resolved the same way a bare side is, so an unknown
			-- name inside a list fails at construction exactly as it would outside
			-- one, and a package that declares neither pays zero.
			local total = 0
			for _, entry in raw do
				local n = if type(entry) == "string" then snapshot.resolveNumber(snap, entry) else entry
				if type(n) == "number" then
					total += n
				end
			end
			resolved = resolved or table.clone(value)
			resolved[side] = total
		end
	end
	return resolved or value
end

local DIM_METRIC_FIELDS = { "px", "min", "max", "preferred" }

-- resolveDim: a layout dimension whose numeric fields may be metric names
function snapshot.resolveDim(snap: any, dim: any): any
	if type(dim) ~= "table" then
		return dim
	end
	local resolved: any = nil
	for _, field in DIM_METRIC_FIELDS do
		if type(dim[field]) == "string" then
			resolved = resolved or table.clone(dim)
			resolved[field] = snapshot.resolveNumber(snap, dim[field])
		elseif type(dim[field]) == "table" then
			-- A DIMENSION MAY ADD SEVERAL METRICS TOGETHER, exactly as a padding
			-- side already can (see `resolveSides` above, 2026-07-27). Same
			-- grammar, same rule that an entry may be a raw number, so one
			-- vocabulary covers both.
			--
			-- THE CASE THAT FORCED IT (director report 2026-07-28, defect 3). An
			-- author sizing a deliberately-narrow control had no way to say "as
			-- wide as this theme's own border, plus room for content" — only a
			-- literal px. A literal is wrong for every theme but the one it was
			-- measured against: the showcase's compact row asked for 52px, which
			-- is less than the 56px of pure chrome a Pixel Quest Button costs, so
			-- the content box was NEGATIVE before it was clamped to zero and the
			-- control drew nothing. Written as a sum, the same declaration means
			-- the same THING under every package instead of the same number.
			local total = 0
			for _, entry in dim[field] do
				local n = if type(entry) == "string" then snapshot.resolveNumber(snap, entry) else entry
				if type(n) == "number" then
					total += n
				end
			end
			resolved = resolved or table.clone(dim)
			resolved[field] = total
		end
	end
	return resolved or dim
end

return snapshot
