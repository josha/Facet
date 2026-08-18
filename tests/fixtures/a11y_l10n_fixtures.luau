--!strict
-- Accessibility / localization CORPUS fixtures (design §8.4, §15.2/§15.3/§15.4;
-- §17 Phase 4 "accessibility/localization corpus"). Pure, deterministic data +
-- the deterministic pseudo-localization generator. No clock, no randomness.
--
-- These fixtures feed tests/conformance/a11y_l10n_corpus.luau. They deliberately
-- reuse the SHIPPING token schema (src/tokens/default_style) and the SHIPPING
-- control contracts (src/controls/contract) so the corpus asserts real product
-- surfaces, not invented ones.
--
-- Where the HEADLESS text provider (src/layout/text_metrics) cannot represent a
-- script fact, the fixture still exists and carries `declaredFallback` — the
-- corpus asserts that declared behavior instead of silently skipping the entry
-- (§8.4 "...where supported"; the unrepresentable facts are enumerated per
-- fixture and surfaced in the corpus artifact for the phase gate).

local defaultStyle = require("../../src/tokens/default_style")
local controlContract = require("../../src/controls/contract")

local fixtures = {}

-- The one font/size the corpus measures at. BuilderSans is a KNOWN font in the
-- headless provider, so metrics take the "ready" (calibrated) path.
fixtures.FONT = "BuilderSans"
fixtures.FONT_SIZE = 24

-- ── Pseudo-localization ──────────────────────────────────────────────────────
-- Deterministic accented expansion. Two effects a real pseudo-locale has:
--   (1) every Latin letter becomes an accented pseudo-glyph (visual proof the
--       string went through localization), and
--   (2) the string expands in length (German/Finnish-class expansion). We target
--       ~1.3–1.4x by appending a deterministic padding run. Accented glyphs are
--       single codepoints (<0x1100) so they measure at the same advance as their
--       base — the WIDTH expansion therefore comes entirely from the added
--       length, which is exactly the layout risk pseudo-loc is meant to expose.

-- Padding fraction of source length. THIS is the knob the corpus asserts against.
fixtures.PSEUDO_PAD_FACTOR = 0.35

local ACCENT: { [string]: string } = {
	a = "á",
	b = "ƀ",
	c = "ç",
	d = "ð",
	e = "é",
	f = "ƒ",
	g = "ĝ",
	h = "ĥ",
	i = "í",
	j = "ĵ",
	k = "ķ",
	l = "ļ",
	m = "ɱ",
	n = "ñ",
	o = "ó",
	p = "þ",
	q = "ǫ",
	r = "ŕ",
	s = "ş",
	t = "ţ",
	u = "ú",
	v = "ṽ",
	w = "ŵ",
	x = "ẋ",
	y = "ý",
	z = "ž",
	A = "Á",
	B = "Ɓ",
	C = "Ç",
	D = "Ð",
	E = "É",
	F = "Ƒ",
	G = "Ĝ",
	H = "Ĥ",
	I = "Í",
	J = "Ĵ",
	K = "Ķ",
	L = "Ļ",
	M = "Ṁ",
	N = "Ñ",
	O = "Ó",
	P = "Þ",
	Q = "Ǫ",
	R = "Ŕ",
	S = "Ş",
	T = "Ţ",
	U = "Ú",
	V = "Ṽ",
	W = "Ŵ",
	X = "Ẋ",
	Y = "Ý",
	Z = "Ž",
}

-- pseudoLocalize(source) -> expanded string (accented + padded). Deterministic.
function fixtures.pseudoLocalize(source: string): string
	local out = {}
	for _, cp in utf8.codes(source) do
		local ch = utf8.char(cp)
		out[#out + 1] = ACCENT[ch] or ch
	end
	local sourceLen = utf8.len(source) or #source
	local padCount = math.floor(sourceLen * fixtures.PSEUDO_PAD_FACTOR + 0.5)
	if padCount > 0 then
		out[#out + 1] = " "
		out[#out + 1] = string.rep("·", padCount) -- U+00B7 middle dot: fraction-width filler
	end
	return table.concat(out)
end

fixtures.PSEUDO_SOURCE = "Settings and audio options"

-- ── Localization fixtures ───────────────────────────────────────────────────
-- box = the content box the string is laid into. policy = declared overflow
-- contract for that box (§15.3): "none" means the text MUST fit; "truncate" /
-- "wrap" / "clip" / "scroll" declare an intentional handling of overflow.
export type L10nFixture = {
	id: string,
	text: string,
	box: { w: number, h: number },
	policy: string, -- "none" | "truncate" | "wrap" | "clip" | "scroll"
	kind: string, -- classification for the corpus
	declaredFallback: string?, -- present iff a script fact is not representable headless
	unrepresentable: { string }?, -- enumerated facts the headless provider cannot model
}

fixtures.localization = {
	{
		id = "pseudo-loc-expansion",
		text = fixtures.pseudoLocalize(fixtures.PSEUDO_SOURCE),
		box = { w = 2000, h = 200 },
		policy = "none",
		kind = "pseudo",
	},
	{
		-- Long German-compound-style expansion: one unbroken word that overruns a
		-- realistic label box. The headless provider does NOT hyphenate/break a
		-- word, so this MUST declare truncation (or a wider box) to be valid.
		id = "german-compound",
		text = "Höchstgeschwindigkeitsbegrenzungsschild",
		box = { w = 240, h = 120 },
		policy = "truncate", -- one unbroken word overruns the box; truncation declared (§15.3)
		kind = "expansion",
	},
	{
		-- Thai-like tall diacritics (stacked tone marks over tall ascenders).
		id = "tall-script-thai",
		text = "ก้ำน้ำใจที่สูงส่ง",
		box = { w = 2000, h = 200 },
		policy = "none",
		kind = "tall",
		declaredFallback = "line height is the provider's uniform 1.2x factor; per-script "
			.. "ascender/descender and STACKED-diacritic extra height are NOT modeled headless "
			.. "(deferred to Studio/device fixtures, UI-FID-001)",
		unrepresentable = { "per-script line-box height", "stacked combining-mark vertical extent" },
	},
	{
		id = "cjk-sample",
		text = "速度制限標識と設定画面",
		box = { w = 2000, h = 200 },
		policy = "none",
		kind = "cjk",
		declaredFallback = "CJK glyphs measure at a full em (correct advance), but per-character "
			.. "line-break opportunities are NOT modeled (the provider only breaks on whitespace); "
			.. "a long CJK run therefore over-reserves/clamps rather than breaking mid-run",
		unrepresentable = { "CJK inter-character line-break opportunities" },
	},
	{
		id = "emoji-combining",
		-- base+combining ("é" as e + U+0301), a plain emoji, and a ZWJ family
		-- sequence — three grapheme-cluster cases in one fixture.
		text = "e\u{0301} 😀 👨\u{200D}👩\u{200D}👧",
		box = { w = 2000, h = 200 },
		policy = "none",
		kind = "emoji",
		declaredFallback = "no grapheme-cluster shaping headless: combining marks and ZWJ "
			.. "sequences are counted as separate advances (conservative OVER-reservation) "
			.. "rather than collapsed to one glyph advance; true cluster width deferred to the "
			.. "engine text provider (UI-FID-001)",
		unrepresentable = { "grapheme clustering", "zero-advance combining marks", "ZWJ emoji sequences" },
	},
	{
		id = "bidi-rtl",
		text = "مرحبا שלום",
		box = { w = 2000, h = 200 },
		policy = "none",
		kind = "bidi",
		declaredFallback = "the headless provider has NO directionality or shaping: it returns a "
			.. "left-to-right advance-SUM width reservation only. Base direction, bidi reordering "
			.. "(logical<->visual), Arabic cursive joining + contextual forms, and mixed-direction "
			.. "runs are deferred to the engine text provider + platform adapter (UI-FID-001). The "
			.. "corpus asserts THIS reservation-only fallback, not visual order.",
		unrepresentable = {
			"base text direction / RTL",
			"bidi reordering (logical to visual)",
			"Arabic cursive joining and contextual forms",
			"mixed-direction run resolution",
		},
	},
} :: { L10nFixture }

-- ── Accessibility fixtures ──────────────────────────────────────────────────
-- Reuse the shipping compiled token schema (colors, targetSizes, motion).
fixtures.tokens = defaultStyle

-- Required semantic surface/content pairs the corpus contrast-validates.
fixtures.contrastPairs = {
	{ surface = "surface", content = "content", min = 4.5 },
	{ surface = "surfaceStrong", content = "contentStrong", min = 4.5 },
	{ surface = "accent", content = "onAccent", min = 4.5 },
}

-- Focus state: the accent focus ring must separate from the surface it draws on.
-- WCAG non-text UI-component contrast minimum is 3.0.
fixtures.focusState = { ring = "accent", surface = "surface", min = 3.0 }

-- Preferred text-size variants (§8.4): 1.0x baseline, 1.3x, and a maximum.
fixtures.textScales = { 1.0, 1.3, 2.0 }
fixtures.MAX_TEXT_SCALE = 2.0

-- Display-class profiles (§15.4) as raw environment facts. sizeClass is DERIVED
-- from viewportRect by the environment; the corpus never checks a device model.
export type DisplayProfile = {
	id: string,
	viewportRect: { x: number, y: number, w: number, h: number },
	preferredInput: string,
	capabilities: { keyboard: boolean, mouse: boolean, touch: boolean, gamepad: boolean },
	expectSizeClass: string,
}

fixtures.displayProfiles = {
	{
		id = "phone-class",
		viewportRect = { x = 0, y = 0, w = 390, h = 844 },
		preferredInput = "Touch",
		capabilities = { keyboard = false, mouse = false, touch = true, gamepad = false },
		expectSizeClass = "compact",
	},
	{
		id = "desktop-class",
		viewportRect = { x = 0, y = 0, w = 1920, h = 1080 },
		preferredInput = "KeyboardAndMouse",
		capabilities = { keyboard = true, mouse = true, touch = false, gamepad = false },
		expectSizeClass = "wide",
	},
} :: { DisplayProfile }

-- Controls under test for effective-target checks: the shipping focusable
-- controls (Button, Toggle) plus a small custom chip. The chip's declared floor
-- is the knob the target-size corpus asserts against.
-- A compliant custom chip: meets the phone-class effective floor (44 Facet units).
fixtures.SMALL_CONTROL_TARGET = 44

function fixtures.controlsUnderTest(): { { class: string, minHitSize: number } }
	local out = {}
	for _, class in { "Button", "Toggle" } do
		local c = controlContract.forClass(class)
		if c and c.minHitSize then
			out[#out + 1] = { class = class, minHitSize = c.minHitSize }
		end
	end
	out[#out + 1] = { class = "CustomChip", minHitSize = fixtures.SMALL_CONTROL_TARGET }
	return out
end

return fixtures
