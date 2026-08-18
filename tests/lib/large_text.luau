--!strict
--[[ THE LARGE-TEXT MATRIX HARNESS (docs/plans/large-text-accessibility.md
	"Verification matrix"; acceptance rows LT-6 and LT-8).

	One mounted slice, one audit map, one sweep — shared by the three
	large_text_* specs so that the CONTROL sweep, the LAYOUT sweep and the
	HOT-SWAP cases all read the same facts from the same seams.

	WHAT THE PREFERENCE IS. `preferredTextOffset` is an ADDITIVE px offset the
	engine paints every text node with, measured live 2026-08-03 as exactly
	{ Medium = 0, Large = 4, Larger = 10, Largest = 14 } — uniform across font,
	weight and size (artifacts/large-text-accessibility/probe/preference-probe.json,
	decision LTN-1). Headless, it is one env fact, so every row of the plan's
	matrix is computable at suite speed. These are the ONLY four values a player
	can select, so the sweep enumerates them rather than sampling a range.

	WHY THE AUDIT MAP IS BUILT HERE. `src/layout/text_audit` is pure — it takes a
	table of solved entries, never a mounted tree — and the renderer's controller
	publishes the three halves of that table separately: `rectOf`/the adapter's
	node rects (geometry), `textAt()` (the per-text measurement facts), and
	`hiddenRoots()` (which subtrees do not paint). `auditRects` is the one place
	they are joined, so a spec never re-derives them and two specs can never
	disagree about what "the solve" was.

	THE TWO MIRRORS IN THIS FILE, AND WHY EACH IS SAFE:

	  1. `KIND` maps a mounted CLASS onto the solver KIND `text_audit.overlaps`
	     reads. Only the LAYERING kinds matter to it (`zstack`/`anchor` — a pair
	     of children of one of those is stacking, not collision), so the map is
	     exactly those two classes and everything else is a non-layering token.
	     Get this wrong and every Slider, Rating and list Row reports four
	     "overlaps" for its own thumb, fill and hit surface — which is precisely
	     what the first draft of this sweep did.

	  2. `hitFloorOf` mirrors `renderer.effectiveHitFloor`: the control contract
	     declares the floor, the active theme clamps it UP. The solve carries the
	     result as `entry.hitFloor` and the renderer does not expose that entry,
	     so the audit map has to recompute it — and a mirror nobody checks is
	     fiction, so `large_text_matrix.spec` pins it against the renderer's OWN
	     expanded hit rect (the expander's short axis IS the floor).

	DETERMINISM. No clock, no randomness, no `os`/`math.random`, no engine: the
	corpus strings come from tests/fixtures/a11y_l10n_fixtures (the shipping
	pseudo-localizer and its declared locale entries), the themes from the two
	reference packages, and every sweep is a plain nested loop over sorted keys.
]]

local Facet = require("../../src") :: any
local snapshot = require("../../src/themes/snapshot")
local controlContract = require("../../src/class_contract")
local audit = require("../../src/layout/text_audit")
local fixtures = require("../fixtures/a11y_l10n_fixtures")
local fake_target = require("./fake_target")

local large_text = {}

-- ── the four preferences ────────────────────────────────────────────────────
-- name + the measured additive px offset. Ordered Medium -> Largest, because
-- several assertions are about MONOTONICITY along this list.
export type Preference = { name: string, offset: number }

local PREFERENCES: { Preference } = {
	{ name = "Medium", offset = 0 },
	{ name = "Large", offset = 4 },
	{ name = "Larger", offset = 10 },
	{ name = "Largest", offset = 14 },
}
large_text.PREFERENCES = PREFERENCES
large_text.LARGEST = 14

-- ── the two reference theme packages ────────────────────────────────────────
-- Studio Neutral is `themeMetrics`' own default (no package installed); Fantasy
-- Parchment is the second reference package — a wider face, a taller control
-- rhythm and its own nine-slice chrome, which is exactly the axis the plan
-- names ("a theme with wider fonts or larger controls must receive the same
-- guarantee"). Resolved ONCE: a ThemeSnapshot is frozen data, so sharing it
-- across rows costs nothing and cannot drift between them.
local parchmentPackage = (require)("../../examples/themes/fantasy_parchment").build(Facet.themes)

export type Theme = { id: string, metrics: any }

local THEMES: { Theme } = {
	{ id = "studio-neutral", metrics = nil },
	{ id = "fantasy-parchment", metrics = snapshot.resolve(parchmentPackage, nil, {}) },
}
large_text.THEMES = THEMES

-- ── the two compact viewports the plan names ────────────────────────────────
-- 390x844 is the compact phone in portrait; 667x375 is the small-landscape
-- Sponsor fixture (acceptance LT-9). Both are the geometry the live rows were
-- recorded at, so a headless finding and a Studio capture talk about one screen.
large_text.PHONE_PORTRAIT = { x = 0, y = 0, w = 390, h = 844 }
large_text.SMALL_LANDSCAPE = { x = 0, y = 0, w = 667, h = 375 }

-- ── the corpus ──────────────────────────────────────────────────────────────
-- Reused from tests/fixtures/a11y_l10n_fixtures rather than re-invented: the
-- pseudo-localizer is the shipping one (accented + ~1.35x expansion) and the
-- locale entries carry their own declared policy, so a string used here means
-- the same thing it means in the conformance corpus.
local function fixtureText(id: string): string
	for _, entry in fixtures.localization do
		if entry.id == id then
			return entry.text
		end
	end
	error(`large_text: no locale fixture '{id}' in tests/fixtures/a11y_l10n_fixtures`, 0)
end

-- an expanded PHRASE (has legal break opportunities: the reflow rung applies)
large_text.PSEUDO = fixtures.pseudoLocalize(fixtures.PSEUDO_SOURCE)
-- ...and a short one, for an action label that must survive at every preference
large_text.PSEUDO_ACTION = fixtures.pseudoLocalize("Save changes")
large_text.PSEUDO_SECONDARY = fixtures.pseudoLocalize("Not now")
-- one unbroken German compound: NO legal break, so wrapping cannot help it and
-- the only honest degradations are a wider box or truncation-with-disclosure
large_text.GERMAN_COMPOUND = fixtureText("german-compound")
large_text.CJK = fixtureText("cjk-sample")
large_text.EMOJI = fixtureText("emoji-combining")
-- mixed-script line: CJK + emoji + latin in ONE string, which is what a real
-- roster of player names looks like
large_text.MIXED = `{large_text.CJK} {large_text.EMOJI} {large_text.PSEUDO_ACTION}`

-- ── the mounted slice ───────────────────────────────────────────────────────

-- CLASS -> the solver kind `text_audit.overlaps` consults. See the header: only
-- the layering pair is load-bearing.
--[[ ...and `Region` joined the two layering classes in wave REVEAL, for the
	reason `text_audit`'s own LAYERING_KIND note gives: a region paints exactly ONE
	of its forms, so the only painted-sibling pair it can produce is the
	framework's own expand affordance over the form it discloses. Without this the
	sweep reports the cover as a collision on every stepped-down region. ]]
local KIND: { [string]: string } = { ZStack = "zstack", Anchor = "anchor", Region = "region" }

local TOUCH_PHONE = { keyboard = false, mouse = false, touch = true, gamepad = false }
local DESKTOP = { keyboard = true, mouse = true, touch = false, gamepad = false }

export type WorldOpts = {
	viewport: { x: number, y: number, w: number, h: number }?,
	offset: number?,
	theme: Theme?,
	reducedMotion: boolean?,
	input: string?, -- "touch" (default) | "desktop"
}

--[[ world(opts) -> a presented-nothing world.

	The PRESENTER is the driver on purpose: it is the public way a screen is put
	on a target, it auto-wires every composite's four-input story (ADR-0013) with
	no consumer opts, and it owns focus — so the same world answers the control
	sweep, the layout sweep and the hot-swap focus/scroll cases without any spec
	reaching past the public surface.
]]
function large_text.world(opts: WorldOpts?)
	local options: WorldOpts = opts or {}
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", options.viewport or large_text.PHONE_PORTRAIT)
	-- the sweep is about TEXT, so the surface starts flush: a device inset would
	-- change the box every row is measured against and prove nothing about the
	-- preference
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	env:set("preferredTextOffset", options.offset or 0)
	if options.reducedMotion == true then
		env:set("reducedMotion", true)
	end
	if options.input == "desktop" then
		env:set("preferredInput", "KeyboardAndMouse")
		env:set("capabilities", DESKTOP)
	else
		env:set("preferredInput", "Touch")
		env:set("capabilities", TOUCH_PHONE)
	end
	local theme = options.theme
	if theme ~= nil and theme.metrics ~= nil then
		env:set("themeMetrics", theme.metrics)
	end
	local adapter = fake_target.new()
	local system = Facet.newActionSystem(core)
	local pres = Facet.newPresenter(core, env, adapter, system)

	local w: any = { core = core, env = env, adapter = adapter, system = system, pres = pres }

	function w.present(screen: any, presentOpts: any?)
		w.handle = pres.present(screen, presentOpts)
		pres.refresh()
		w.controller = w.handle.controller
		return w.handle
	end

	function w.metrics(): any
		return env:get("themeMetrics"):get()
	end

	return w
end

-- the effective target floor for a class under the live theme. Mirrors
-- renderer.effectiveHitFloor exactly: declared by the contract, clamped UP by
-- the theme, nil for everything the player is not meant to hit.
function large_text.hitFloorOf(class: string, metrics: any): number?
	local c = controlContract.forClass(class)
	local declared = if c ~= nil then c.minHitSize else nil
	return if declared ~= nil then math.max(declared, metrics.targetSizes.minimum) else nil
end

--[[ auditRects(w, rootPrefix?) -> the table the five pure checks read.

	One entry per PAINTABLE node under `rootPrefix` (default "/S", the screen the
	specs mount): its solved rect, the layering kind, the effective target floor,
	the per-text measurement facts, and whether it is inside a subtree that does
	not paint.

	HIDDEN IS TAKEN FROM TWO SEAMS AND UNIONED. `controller.hiddenRoots()` is the
	SOLVER's verdict (a losing ViewThatFits candidate, a dropped Composition
	region); `node.visible == false` is what the renderer actually pushed, which
	additionally catches a stroked Path culled outside its clip host. Either one
	means "nobody can see this", and auditing what nobody can see is how a
	diagnostic earns being ignored.
]]
function large_text.auditRects(w: any, rootPrefix: string?): { [string]: any }
	local prefix = rootPrefix or "/S"
	local metrics = w.metrics()
	local hidden = w.controller.hiddenRoots()
	local facts = w.controller.textAt()
	local out: { [string]: any } = {}
	for _, path in w.adapter.paths() do
		if path ~= prefix and string.sub(path, 1, #prefix + 1) ~= prefix .. "/" then
			continue -- another root (a modal, the disclosure plate) is its own audit
		end
		local node = w.adapter.node(path)
		if node == nil or node.rect == nil then
			continue
		end
		out[path] = {
			rect = node.rect,
			kind = KIND[node.class] or "box",
			class = node.class,
			hidden = if hidden[path] == true or node.visible == false then true else nil,
			hitFloor = large_text.hitFloorOf(node.class, metrics),
			textFacts = facts[path],
		}
	end
	return out
end

export type Sweep = {
	overlaps: { any },
	clipped: { any },
	hitFloor: { any },
	rects: { [string]: any },
}

-- run the three whole-screen checks over one solve
function large_text.sweep(w: any, rootPrefix: string?, opts: any?): Sweep
	local rects = large_text.auditRects(w, rootPrefix)
	local options: any = opts or {}
	return {
		overlaps = audit.overlaps(rects, options.overlaps),
		clipped = audit.clippedEssential(rects, options.clipped),
		hitFloor = audit.hitFloor(rects),
		rects = rects,
	}
end

-- a findings list rendered for an assertion message: a failure has to name the
-- row AND the node, or the sweep reports "expected 0, got 3" and the reader has
-- to re-run it by hand to learn anything
function large_text.describeFindings(row: string, found: { any }): string
	local lines: { string } = {}
	for _, f in found do
		table.insert(
			lines,
			`  [{row}] {f.check} {f.node}{if f.other ~= nil then " x " .. f.other else ""} — {tostring(f.detail)}`
		)
	end
	return table.concat(lines, "\n")
end

-- the sorted path set of a findings list (the shape subset/equality claims read)
function large_text.pathsOf(found: { any }): { string }
	local out: { string } = {}
	for _, f in found do
		table.insert(out, f.node)
	end
	table.sort(out)
	return out
end

function large_text.contains(list: { string }, needle: string): boolean
	return table.find(list, needle) ~= nil
end

-- every solved rect under the root, keyed by path — the comparable value the
-- hot-swap cases use for "byte-identical geometry"
function large_text.geometryOf(w: any, rootPrefix: string?): { [string]: string }
	local out: { [string]: string } = {}
	for path, entry in large_text.auditRects(w, rootPrefix) do
		local r = entry.rect
		out[path] = string.format("%d,%d %dx%d", r.x, r.y, r.w, r.h)
	end
	return out
end

-- the paths under `prefix` whose text the solve reports TRUNCATED and that
-- actually PAINT (the LT-6 subject). A losing ViewThatFits candidate keeps its
-- measured facts, and reading its verdict as if it were on screen is how an
-- overflow-order rule fires on a layout nobody can see.
function large_text.truncatedUnder(w: any, prefix: string): { string }
	local out: { string } = {}
	for path, entry in large_text.auditRects(w, prefix) do
		local facts = entry.textFacts
		if entry.hidden ~= true and type(facts) == "table" and facts.truncated == true then
			table.insert(out, path)
		end
	end
	table.sort(out)
	return out
end

-- structural ops only: a preference change is GEOMETRY, so a `create` or
-- `remove` in the log means the tree was rebuilt rather than re-solved
function large_text.structuralOps(ops: { string }): { string }
	local out: { string } = {}
	for _, op in ops do
		local head = string.match(op, "^(%a+)")
		if head == "create" or head == "remove" or head == "createRoot" or head == "destroyRoot" then
			table.insert(out, op)
		end
	end
	return out
end

return large_text
