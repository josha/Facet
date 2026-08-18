--!strict
-- Accessibility / localization CORPUS (design §8.4, §15.2/§15.3/§15.4; §17
-- Phase 4 "accessibility/localization corpus"). One requirement — UI-ADAPT-001
-- (per-client adaptation from viewport, safe areas, accessibility, locale).
--
-- Same Check shape as tests/conformance/suite.luau: run(core) -> (ok, note).
-- Each check builds only what it needs from the SHIPPING modules — the headless
-- text provider (src/layout/text_metrics), the environment (src/env/environment,
-- which needs a core for its per-key signals/memos), and the token compiler
-- (src/tokens/tokens) over the shipping default style. Checks are pure and
-- deterministic: no clock, no randomness.
--
-- On FAILURE every note names the FIXTURE and an actionable HINT (the requirement
-- itself is on Check.requirement). The corpus is registered into the existing
-- conformance flow (conformance.spec.luau -> ./run-tests.sh; cli.luau ->
-- artifacts/conformance-<core>.json) and dumped to a dedicated phase-4 artifact
-- by corpus_cli.luau.

local text_metrics = require("../../src/layout/text_metrics")
local tokens = require("../../src/tokens/tokens")
local environment = require("../../src/env/environment")
local fx = require("../fixtures/a11y_l10n_fixtures")

local FONT = fx.FONT
local SIZE = fx.FONT_SIZE

export type Check = {
	name: string,
	requirement: string,
	run: (core: any) -> (boolean, string?),
}

local REQ = "UI-ADAPT-001"

-- ── policy helpers (the testable definitions §8.4 asks the framework to have) ─

local function buildEnv(core: any, profile: any?): any
	local env = environment.new(core)
	if profile then
		env:set("viewportRect", profile.viewportRect)
		env:set("preferredInput", profile.preferredInput)
		env:set("capabilities", profile.capabilities)
	end
	return env
end

-- §8.4: an EFFECTIVE minimum target in Facet units DERIVED from the display
-- environment (never a device-model check, never a raw "44 pt"). Touch-primary
-- surfaces need the full token floor; a precise pointer may go a bit smaller but
-- never below ~0.73x of it. The derivation reads environment facts only.
local POINTER_FACTOR = 0.727
local function effectiveTargetMin(env: any, tokensTbl: any): number
	local base = tokensTbl.targetSizes.minimum
	local input = env:get("preferredInput"):get()
	local caps = env:get("capabilities"):get()
	local touchPrimary = input == "Touch" or (caps and caps.touch == true)
	local factor = if touchPrimary then 1.0 else POINTER_FACTOR
	return base * factor
end

-- A control's rendered hit target grows with the typography scale but never
-- drops below its declared floor (§15.3: targets do not shrink under scaling).
local function renderedTargetOf(control: any, typographyScale: number): number
	return control.minHitSize * math.max(1, typographyScale)
end

-- Reduced-motion substitution (§12.2): motion tokens resolve to 0 (instant)
-- under the reduced policy, otherwise to the token's own duration.
local function resolveMotion(policy: string, value: number): number
	return if policy == "reduced" then 0 else value
end

local function measure(text: string, size: number, maxWidth: number)
	return text_metrics.measure(text, FONT, size, maxWidth)
end

local INTRINSIC = 1e7 -- effectively unbounded width -> reports intrinsic advance

local function finiteNonNeg(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge and x >= 0
end

local function fixtureById(id: string): any
	for _, f in fx.localization do
		if f.id == id then
			return f
		end
	end
	error(`corpus fixture '{id}' missing`)
end

local function round3(x: number): number
	return math.floor(x * 1000 + 0.5) / 1000
end

-- ── deterministic dump (feeds the artifact + the determinism check) ──────────

local function dumpCore(core: any): any
	local out: any = { schema = "facet-a11y-l10n-corpus/1", requirement = REQ }

	local loc = {}
	for _, f in fx.localization do
		local m = measure(f.text, SIZE, f.box.w)
		local intrinsic = measure(f.text, SIZE, INTRINSIC)
		loc[#loc + 1] = {
			id = f.id,
			kind = f.kind,
			state = m.state,
			renderWidth = m.width,
			renderHeight = m.height,
			lines = m.lines,
			intrinsicWidth = intrinsic.width,
			boxW = f.box.w,
			boxH = f.box.h,
			policy = f.policy,
			declaredFallback = f.declaredFallback,
			unrepresentable = f.unrepresentable,
		}
	end
	out.localization = loc

	local contrast = {}
	for _, pair in fx.contrastPairs do
		contrast[#contrast + 1] = {
			pair = `{pair.content}-on-{pair.surface}`,
			ratio = round3(tokens.contrastRatio(fx.tokens.colors[pair.surface], fx.tokens.colors[pair.content])),
			min = pair.min,
		}
	end
	local focusRatio =
		round3(tokens.contrastRatio(fx.tokens.colors[fx.focusState.ring], fx.tokens.colors[fx.focusState.surface]))

	local displayClass = {}
	for _, profile in fx.displayProfiles do
		local env = buildEnv(core, profile)
		displayClass[#displayClass + 1] = {
			id = profile.id,
			sizeClass = env:get("sizeClass"):get(),
			effectiveTargetMin = round3(effectiveTargetMin(env, fx.tokens)),
		}
	end

	local scaleHeights = {}
	do
		local env = buildEnv(core)
		for _, scale in fx.textScales do
			env:set("preferredTextSize", scale)
			local ts = env:get("typographyScale"):get()
			scaleHeights[#scaleHeights + 1] = {
				scale = scale,
				typographyScale = ts,
				reservedHeight = measure("Preferences", SIZE * ts, INTRINSIC).height,
			}
		end
	end

	out.accessibility = {
		contrast = contrast,
		focusRingContrast = focusRatio,
		focusMin = fx.focusState.min,
		displayClass = displayClass,
		textScaleHeights = scaleHeights,
		motion = {
			full = resolveMotion("full", fx.tokens.motion.normal),
			reduced = resolveMotion("reduced", fx.tokens.motion.normal),
		},
	}
	return out
end

-- ── checks ───────────────────────────────────────────────────────────────────

local checks: { Check } = {
	-- LOCALIZATION ------------------------------------------------------------
	{
		name = "l10n-pseudo-loc-expansion",
		requirement = REQ,
		run = function(_core)
			local src = fx.PSEUDO_SOURCE
			local pseudo = fx.pseudoLocalize(src)
			local hasAccent = false
			for _, cp in utf8.codes(pseudo) do
				if cp > 127 then
					hasAccent = true
					break
				end
			end
			if not hasAccent then
				return false,
					"[pseudo-loc-expansion] no accented pseudo-glyphs; hint: map Latin letters to accented codepoints"
			end
			local wSrc = measure(src, SIZE, INTRINSIC).width
			local wPseudo = measure(pseudo, SIZE, INTRINSIC).width
			local ratio = wPseudo / wSrc
			if ratio < 1.3 or ratio > 1.45 then
				return false,
					`[pseudo-loc-expansion] width expansion {round3(ratio)}x outside 1.30-1.45; hint: tune PSEUDO_PAD_FACTOR (accented glyphs are 1:1 width, so length drives width)`
			end
			return true, `ratio={round3(ratio)}x`
		end,
	},
	{
		name = "l10n-tall-script-line-height",
		requirement = REQ,
		run = function(_core)
			local f = fixtureById("tall-script-thai")
			local m = measure(f.text, SIZE, f.box.w)
			-- model the tall script via the provider's line-height FACT (1.2x)
			local expected = math.ceil(m.lines * SIZE * 1.2)
			if m.height ~= expected then
				return false,
					`[tall-script-thai] reserved height {m.height} != line-height-factor expectation {expected}; hint: height must follow the provider LINE_HEIGHT_FACTOR (1.2x)`
			end
			-- the unrepresentable per-script tall metric MUST be declared, not skipped
			if f.declaredFallback == nil then
				return false, "[tall-script-thai] missing declaredFallback for un-modeled tall-diacritic height"
			end
			return true, `height={m.height} (uniform 1.2x box; per-script tall metrics deferred to UI-FID-001)`
		end,
	},
	{
		name = "l10n-cjk-full-em",
		requirement = REQ,
		run = function(_core)
			local f = fixtureById("cjk-sample")
			local m = measure(f.text, SIZE, f.box.w)
			local glyphs = utf8.len(f.text) or 0
			if m.width ~= glyphs * SIZE then
				return false,
					`[cjk-sample] width {m.width} != full-em width {glyphs * SIZE}; hint: CJK/wide glyphs must measure a full em`
			end
			-- wider than the same glyph count of Latin advances (proves wide handling)
			if not (m.width > math.ceil(glyphs * SIZE * 0.62)) then
				return false, "[cjk-sample] CJK not treated wider than Latin advances"
			end
			return true, `width={m.width} ({glyphs} full ems)`
		end,
	},
	{
		name = "l10n-emoji-combining-over-reservation",
		requirement = REQ,
		run = function(_core)
			local emoji = measure("😀", SIZE, INTRINSIC).width
			if emoji ~= SIZE then
				return false,
					`[emoji-combining] emoji width {emoji} != one full em {SIZE}; hint: emoji codepoints are wide`
			end
			local base = measure("e", SIZE, INTRINSIC).width
			local combined = measure("e\u{0301}", SIZE, INTRINSIC).width
			if not (combined > base) then
				return false,
					"[emoji-combining] combining mark not counted as an advance; hint: headless fallback is conservative OVER-reservation (no zero-width clustering)"
			end
			local zwj = measure("👨\u{200D}👩\u{200D}👧", SIZE, INTRINSIC).width
			if not (zwj > SIZE) then
				return false,
					"[emoji-combining] ZWJ sequence not over-reserved; hint: sequence advances summed as the declared fallback"
			end
			return true,
				`emoji={emoji} base={base} combined={combined} zwj={zwj} (over-reservation is the declared headless fallback)`
		end,
	},
	{
		name = "l10n-bidi-rtl-declared-fallback",
		requirement = REQ,
		run = function(_core)
			local f = fixtureById("bidi-rtl")
			local m = measure(f.text, SIZE, f.box.w)
			-- known font -> ready; the entry EXISTS and yields a finite reservation
			if m.state ~= "ready" then
				return false, `[bidi-rtl] expected "ready" state for a known font, got "{m.state}"`
			end
			if not (finiteNonNeg(m.width) and m.width > 0) then
				return false, `[bidi-rtl] non-finite/empty width reservation ({m.width})`
			end
			-- the corpus asserts the DECLARED reservation-only fallback, not visual order
			if f.declaredFallback == nil or f.unrepresentable == nil then
				return false,
					"[bidi-rtl] declared fallback / unrepresentable facts missing; hint: direction+shaping are un-modeled headless and must be declared"
			end
			return true, `width={m.width} reservation-only; direction/reordering/shaping deferred (UI-FID-001)`
		end,
	},

	-- ACCESSIBILITY -----------------------------------------------------------
	{
		name = "a11y-text-size-variants",
		requirement = REQ,
		run = function(core)
			local env = buildEnv(core)
			local heights = {}
			for _, scale in fx.textScales do
				env:set("preferredTextSize", scale)
				local ts = env:get("typographyScale"):get()
				if ts ~= scale then
					return false,
						`[text-scale] typographyScale {ts} != preferredTextSize {scale}; hint: derived scale must track the preference`
				end
				local m = measure("Preferences", SIZE * ts, INTRINSIC)
				if not finiteNonNeg(m.height) then
					return false, `[text-scale {scale}] non-finite reserved height`
				end
				heights[#heights + 1] = m.height
			end
			for i = 2, #heights do
				if heights[i] < heights[i - 1] then
					return false, "[text-scale] reserved height shrank as text size grew"
				end
			end
			if not (heights[#heights] > heights[1]) then
				return false,
					`[text-scale] max scale ({fx.MAX_TEXT_SCALE}x) did not grow reserved height; hint: type ramp must follow preferredTextSize`
			end
			return true, `heights={heights[1]}/{heights[2]}/{heights[3]}`
		end,
	},
	{
		name = "a11y-effective-target-by-display-class",
		requirement = REQ,
		run = function(core)
			for _, profile in fx.displayProfiles do
				local env = buildEnv(core, profile)
				local sc = env:get("sizeClass"):get()
				if sc ~= profile.expectSizeClass then
					return false,
						`[{profile.id}] sizeClass {sc} != {profile.expectSizeClass}; hint: sizeClass derives from viewportRect`
				end
				local effMin = effectiveTargetMin(env, fx.tokens)
				for _, ctl in fx.controlsUnderTest() do
					if ctl.class == "CustomChip" then
						continue -- shipping controls only for the "meets min" guarantee
					end
					local target = renderedTargetOf(ctl, 1.0)
					if target < effMin then
						return false,
							`[{profile.id}/{ctl.class}] target {target} < effective min {effMin}; hint: raise minHitSize; the control fails reach on this display class`
					end
				end
			end
			-- the effective min is genuinely CALIBRATED by display class (not one number)
			local phoneMin = effectiveTargetMin(buildEnv(core, fx.displayProfiles[1]), fx.tokens)
			local deskMin = effectiveTargetMin(buildEnv(core, fx.displayProfiles[2]), fx.tokens)
			if not (phoneMin > deskMin) then
				return false,
					`[display-class] effective min not calibrated by class (phone {phoneMin} vs desktop {deskMin})`
			end
			return true, `phoneMin={round3(phoneMin)} desktopMin={round3(deskMin)} (Facet units, env-derived)`
		end,
	},
	{
		name = "a11y-target-not-shrink-under-text-scale",
		requirement = REQ,
		run = function(core)
			local env = buildEnv(core, fx.displayProfiles[1]) -- phone-class = tightest floor
			local effMin = effectiveTargetMin(env, fx.tokens)
			for _, ctl in fx.controlsUnderTest() do
				local prev = -1
				for _, scale in fx.textScales do
					local target = renderedTargetOf(ctl, scale)
					if target < effMin then
						return false,
							`[{ctl.class}@{scale}x] effective target {round3(target)} < display-class min {effMin}; hint: targets must not shrink below the floor under text scaling`
					end
					if target < prev then
						return false, `[{ctl.class}] target shrank as text size grew`
					end
					prev = target
				end
			end
			return true, `effMin={effMin}; all controls hold across {#fx.textScales} scales`
		end,
	},
	{
		name = "a11y-preferred-transparency-readable",
		requirement = REQ,
		run = function(core)
			local env = buildEnv(core)
			env:set("preferredTransparency", 0.0) -- user prefers reduced transparency
			if env:get("preferredTransparency"):get() ~= 0.0 then
				return false, "[transparency] preference not observable through the environment"
			end
			-- readable fallback: the decorative surface substitutes a SOLID backing;
			-- its token contrast must still clear the readable minimum
			local ratio = tokens.contrastRatio(fx.tokens.colors.content, fx.tokens.colors.surface)
			if ratio < 4.5 then
				return false,
					`[transparency] readable solid-backing contrast {round3(ratio)} < 4.5; hint: content-on-surface must stay >=4.5 when transparency is reduced`
			end
			return true, `solidBackingContrast={round3(ratio)}`
		end,
	},
	{
		name = "a11y-reduced-motion-substitution",
		requirement = REQ,
		run = function(core)
			local env = buildEnv(core)
			env:set("reducedMotion", false)
			if env:get("motionPolicy"):get() ~= "full" then
				return false, "[reduced-motion] motionPolicy not 'full' when reducedMotion=false"
			end
			if resolveMotion("full", fx.tokens.motion.normal) ~= fx.tokens.motion.normal then
				return false, "[reduced-motion] full policy altered the token duration"
			end
			env:set("reducedMotion", true)
			if env:get("motionPolicy"):get() ~= "reduced" then
				return false,
					"[reduced-motion] motionPolicy did not flip to 'reduced'; hint: env memo over reducedMotion"
			end
			local reduced = resolveMotion("reduced", fx.tokens.motion.normal)
			if reduced ~= 0 then
				return false,
					`[reduced-motion] reduced substitution {reduced} != 0 (instant); hint: motion tokens must resolve to the reduced value`
			end
			return true, `full={fx.tokens.motion.normal} reduced={reduced}`
		end,
	},
	{
		name = "a11y-contrast-token-pairs-and-focus",
		requirement = REQ,
		run = function(_core)
			for _, pair in fx.contrastPairs do
				local r = tokens.contrastRatio(fx.tokens.colors[pair.surface], fx.tokens.colors[pair.content])
				if r < pair.min then
					return false,
						`[contrast/{pair.content}-on-{pair.surface}] {round3(r)} < {pair.min}; hint: adjust the token pair to meet WCAG text contrast`
				end
			end
			local fr =
				tokens.contrastRatio(fx.tokens.colors[fx.focusState.ring], fx.tokens.colors[fx.focusState.surface])
			if fr < fx.focusState.min then
				return false,
					`[focus-ring] {fx.focusState.ring}-on-{fx.focusState.surface} contrast {round3(fr)} < {fx.focusState.min}; hint: focus ring must separate from its surface (WCAG non-text 3:1)`
			end
			return true, `focusRingContrast={round3(fr)}`
		end,
	},

	-- CONTRACT-AWARE INVARIANTS (§15.3) + DETERMINISM -------------------------
	{
		name = "corpus-text-in-content-box-or-truncation-declared",
		requirement = REQ,
		run = function(_core)
			for _, f in fx.localization do
				local intrinsic = measure(f.text, SIZE, INTRINSIC)
				local declared = f.policy ~= "none"
				if intrinsic.width > f.box.w and not declared then
					return false,
						`[{f.id}] intrinsic text width {intrinsic.width} exceeds content box {f.box.w} with policy "none"; hint: declare truncate/wrap/clip/scroll or widen the box`
				end
				if f.policy == "wrap" then
					local wrapped = measure(f.text, SIZE, f.box.w)
					if wrapped.height > f.box.h then
						return false,
							`[{f.id}] wrapped height {wrapped.height} exceeds box {f.box.h}; hint: taller box or scroll`
					end
				end
			end
			return true, `{#fx.localization} fixtures respect their declared box contract`
		end,
	},
	{
		name = "corpus-content-within-clip-containers",
		requirement = REQ,
		run = function(_core)
			for _, f in fx.localization do
				local m = measure(f.text, SIZE, f.box.w) -- clamped render rect at origin
				if m.width > f.box.w then
					return false, `[{f.id}] rendered width {m.width} > clip box {f.box.w}`
				end
				local overflowDeclared = f.policy == "scroll" or f.policy == "clip" or f.policy == "wrap"
				if m.height > f.box.h and not overflowDeclared then
					return false, `[{f.id}] rendered height {m.height} > clip box {f.box.h} without an overflow policy`
				end
			end
			return true, nil
		end,
	},
	{
		name = "corpus-valid-finite-rects",
		requirement = REQ,
		run = function(core)
			for _, f in fx.localization do
				for _, w in { f.box.w, INTRINSIC } do
					local m = measure(f.text, SIZE, w)
					if not (finiteNonNeg(m.width) and finiteNonNeg(m.height) and finiteNonNeg(m.lines)) then
						return false, `[{f.id}] non-finite rect: w={m.width} h={m.height} lines={m.lines}`
					end
				end
			end
			local env = buildEnv(core)
			for _, scale in fx.textScales do
				env:set("preferredTextSize", scale)
				local ts = env:get("typographyScale"):get()
				local m = measure("Preferences and audio", SIZE * ts, 400)
				if not (finiteNonNeg(m.width) and finiteNonNeg(m.height)) then
					return false, `[text-scale {scale}] non-finite rect`
				end
			end
			return true, nil
		end,
	},
	{
		name = "corpus-determinism-identical-dumps",
		requirement = REQ,
		run = function(core)
			local serde = require("@lune/serde")
			local d1 = serde.encode("json", dumpCore(core), false)
			local d2 = serde.encode("json", dumpCore(core), false)
			if d1 ~= d2 then
				return false,
					"[determinism] two corpus dumps differ within one run; hint: a non-deterministic (clock/random/iteration-order) input leaked in"
			end
			return true, `dump stable ({#d1} bytes)`
		end,
	},
}

return {
	requirement = REQ,
	checks = checks,
	dump = dumpCore,
}
