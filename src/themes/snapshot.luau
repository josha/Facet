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

local function frozenClone(t: any): any
	local out: any = {}
	for k, v in t do
		out[k] = if type(v) == "table" then frozenClone(v) else v
	end
	return table.freeze(out)
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

-- resolve(package, themeName, facts, overrides?) -> frozen ThemeSnapshot.
--
-- Composition happens EXACTLY ONCE, in ADR-0019 §2 order:
--   1. the package's authored metrics for the active theme;
--   2. display/density policy;
--   3. preferred-text reservation inputs;
--   4. accessibility and minimum-hit-target floors (clamp UP, never down);
--   5. explicit local overrides.
--
-- Steps 2 and 3 deliberately do NOT scale anything here. The environment already
-- composes the ten-foot type floor into `typographyScale`/`typographyPaintScale`
-- and the preferred-text offset into the renderer's measure seam; applying them
-- again in the snapshot would DOUBLE them. The snapshot therefore carries the
-- AUTHORED values plus the facts that produced it, and the existing scale seams
-- keep multiplying at measure and paint.
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
	-- the paradigm adaptation luauui should handle").
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
		local lines = { pointer = 1, touch = 2 }
		tableFamily.rowLines = lines
		tableFamily.rowPadding = padV
		tableFamily.rowHeight = {
			pointer = math.max((out.controlSizes :: any).compact.height, lines.pointer * lineBox + 2 * padV),
			touch = math.max((out.targetSizes :: any).minimum, lines.touch * lineBox + 2 * padV),
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
	-- EVERY SLOT FAMILY THAT PAINTS OUTSIDE ITS RECT (RS-A16-D2, found live: the
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

	-- 2. display/density policy: recorded, never re-applied (see the note above)
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
		-- published so the adapter can stamp Pixelated on the images it creates
		-- OUTSIDE the sheet (icons), and so a dump can assert the unit that
		-- produced these numbers rather than inferring it
		out.pixelUnit = unit
	end

	-- 4c. THE OUTWARD RESERVATIONS, one writer for every slot family (director fix
	-- round 2026-07-25 for the bar; RS-A16-D2 for the layer stacks). Both are
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

	out.identity = {
		packageId = package.identity.id,
		version = package.identity.version,
		themeName = name,
		stamp = package.stamp,
	}
	return frozenClone(out)
end

local neutralCache: any = nil

-- the snapshot every screen gets for free: Studio Neutral, no facts, no
-- overrides. Values are byte-identical to the literals the framework shipped
-- before theme packages existed.
function snapshot.neutral(): any
	if neutralCache == nil then
		neutralCache = snapshot.resolve(snapshot.neutralPackage(), nil, {}, nil)
	end
	return neutralCache
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
	for _, step in pkg.REQUIRED_SPACE_STEPS do
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
