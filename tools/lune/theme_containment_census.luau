--!strict
--[[ THE THEMED-CONTAINMENT CENSUS, as a runnable instrument (task THEME fix
	round, 2026-08-28; review finding I1).

	    lune run tools/lune/theme_containment_census
	    lune run tools/lune/theme_containment_census -- --neutral   (the control arm)
	    lune run tools/lune/theme_containment_census -- --rect      (the OLD vocabulary)

	THE THREE ARMS, and they are the three numbers this class is made of:
	  --neutral   no package installed at all: what the suite used to ask.
	  --rect      every package INSTALLED, judged against the plain RECT: what the
	              guard could have seen before it was taught a themed edge. The
	              difference between this and the default arm is the vocabulary.
	  (default)   every package installed, judged against the THEMED content box
	              and the sibling plate: the class, in full.

	WHY IT IS COMMITTED. The round that taught `tests/lib/overflow_guard.luau` what
	a themed edge is booked a backlog against a corpus number — and the probe that
	produced it was never committed, so the number appeared three different ways in
	the tree (494 in a source comment, 494 and 253 in one ADR, 484 in the task
	report) and a fresh-context reviewer rebuilding the collector faithfully got
	none of them. A number nobody can reproduce is not a measurement; it is a
	claim. This file IS the number now: every figure in ADR-0059, in
	`render/layout_node.luau`'s sibling-plate comment and in the task report quotes
	one run of it, with its dedup rule named.

	WHAT IT ASKS. `overflow_guard.violations(adapter, ledger, snapshot)` — "is this
	node's rect inside the box it lives in", where the box is the boundary's THEMED
	content box and a full-bleed surfaced sibling counts as the boundary its stack
	really has — over the whole showcase corpus at every swept viewport, under
	every package the showcase's theme picker offers.

	HOW IT IS THE SAME QUESTION `tests/overflow_sweep.spec.luau` ASKS, and it must
	stay so or the two drift:
	  * the SURFACE list is derived from `scenarios/init.luau`'s own `ORDER` block
	    the way that file's RULE 4 coverage case derives it (delegations excluded —
	    `examples` and every `ref_*` resolve their real module through a replicated
	    folder, and those modules are mounted here directly), plus the tutorial
	    examples and the five reference proofs read from their directories;
	  * the VIEWPORTS are `tests/lib/device_views.luau`'s, all of them;
	  * the WORLD is built the same way, including the fake adapter's scroll-bar
	    thickness (a sweep without it lays out 8px wider than the device);
	  * the PACKAGE is SWUNG onto a standing mount with `env:set("themeMetrics")`,
	    which is the seam the theme picker itself drives and the one the sweep
	    already proved equivalent to a fresh mount over its whole cross product.

	WHAT IT DELIBERATELY DOES NOT DO. No preference axis, no locale axis, no state
	walk: this counts the SETTLED screen at the default preference. Those axes
	multiply the cell count without changing what the class IS, and the number this
	instrument exists to make reproducible is the corpus-wide count of themed
	containment escapes, not a superset of the sweep.

	THE DEDUP RULES it prints, because "distinct" is a choice and the ADR has to
	name which one it quotes:
	  total                every (surface, view, package, node) hit
	  by (surface, node)   ONE construction = one defect: the same leaf on the same
	                       plate at nine viewports under five carving packages is
	                       one thing to fix. THIS is the number the ADR books
	                       against.
	  by (surface, pkg, node) / (surface, view, node)   printed so a reader can see
	                       what the choice costs. ]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Facet = require("../../src") :: any
local fake_target = require("../../tests/lib/fake_target")
local overflow_guard = require("../../tests/lib/overflow_guard")
local device_views = require("../../tests/lib/device_views")
local demo_picker = require("../../examples/gallery/client/demo_picker") :: any

local NEUTRAL_ONLY = false
local RECT_ONLY = false
for _, arg in process.args do
	if arg == "--neutral" then
		NEUTRAL_ONLY = true
	elseif arg == "--rect" then
		RECT_ONLY = true
	end
end
assert(not (NEUTRAL_ONLY and RECT_ONLY), "--neutral and --rect are two different arms; pass one")

local SHOWCASE_TOP = demo_picker.barReservation(device_views.CORE_TOP, nil, 8)

-- ── the corpus ───────────────────────────────────────────────────────────────

local function scenarioNames(): { string }
	local source = fs.readFile("examples/gallery/scenarios/init.luau")
	local order = string.match(source, "local ORDER = (%b{})")
	assert(order ~= nil, "scenarios/init.luau no longer has a `local ORDER = { ... }` block")
	local out: { string } = {}
	-- ENTRIES, NOT EVERY QUOTED STRING (the same trap `overflow_sweep`'s RULE 4
	-- case records: the ORDER table's comments quote surface names in prose)
	for line in string.gmatch(order :: string, "[^\n]+") do
		local entry = string.match(line, '^%s*"([^"]+)",%s*$')
		if entry == nil then
			continue
		end
		if entry == "examples" or string.sub(entry, 1, 4) == "ref_" then
			continue -- a delegation; the module it delegates to is mounted directly
		end
		table.insert(out, entry)
	end
	return out
end

local function exampleNames(): { string }
	local out: { string } = {}
	for _, name in fs.readDir("examples/gallery/examples") do
		local stem = string.match(name, "^(%d%d_[%w_]+)%.luau$")
		if stem ~= nil then
			table.insert(out, stem)
		end
	end
	table.sort(out)
	return out
end

local function proofNames(): { string }
	local out: { string } = {}
	for _, name in fs.readDir("examples/reference") do
		if string.match(name, "^p%d_%w+$") ~= nil then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

--[[ EVERY PACKAGE THE PICKER OFFERS A PLAYER, which is `overflow_sweep`'s own
	`PACKAGE_MODULES` list: the two `testOnly` fixtures are absent for the reason
	the picker hides them, and `ornate_gauge`/`custom_control` are control
	CONTRIBUTIONS rather than packages. Named rather than globbed because that
	distinction is not visible in a directory listing. ]]
local PACKAGE_MODULES = {
	"classic_desktop",
	"compact_pointer",
	"fantasy_ornate",
	"fantasy_parchment",
	"glossy_mobile",
	"glossy_touch",
	"pixel_quest",
	"scifi_hud",
}

local PACKAGES: { { id: string, snapshot: any, carves: boolean } } = {}
for _, id in PACKAGE_MODULES do
	local module = require(`../../examples/themes/{id}`) :: any
	local pkg, report = module.build(Facet.themes)
	assert(pkg ~= nil, `{id} failed its own package gate: {report and report.errors[1] and report.errors[1].message}`)
	local snapshot = Facet.themes.resolve(pkg, nil, {})
	-- "carves anything" = publishes a non-zero inset on ANY slot. A flat package's
	-- all-zero `chromeInsets` makes both themed rules free rather than merely
	-- cheap, so it can only ever report what the neutral pass already reports.
	local carves = false
	for _, ins in (snapshot.chromeInsets or {}) :: any do
		if type(ins) == "table" then
			for _, side in { "top", "right", "bottom", "left" } do
				if type((ins :: any)[side]) == "number" and (ins :: any)[side] > 0 then
					carves = true
				end
			end
		end
	end
	table.insert(PACKAGES, { id = id, snapshot = snapshot, carves = carves })
end

-- ── the world (`overflow_sweep.spec.luau`'s, field for field) ────────────────

local function world(view: any): any
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	env:set("coreSafeInsets", { top = SHOWCASE_TOP, bottom = 0, left = 0, right = 0 })
	env:set("displaySize", view.displaySize)
	env:set("preferredInput", view.input)
	env:set("capabilities", device_views.CAPABILITIES[view.input])
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new() :: any
	adapter.scrollBarThickness = fake_target.SCROLL_BAR_THICKNESS
	local presenter = Facet.newPresenter(core, env, adapter, system)
	return { core = core, env = env, adapter = adapter, presenter = presenter, system = system }
end

local function settle(w: any)
	for _ = 1, 3 do
		w.presenter.refresh()
	end
end

local function present(w: any, built: any): any
	if built.handle == nil and built.screen ~= nil then
		built.handle = w.presenter.present(built.screen, built.present)
	end
	return built
end

local function scenarioCtx(w: any): any
	return {
		Facet = Facet,
		core = w.core,
		env = w.env,
		adapter = w.adapter,
		presenter = w.presenter,
		actionSystem = w.system,
		record = function() end,
		flags = {},
		geometry = function(paths: { string }): { [string]: any }
			local out: { [string]: any } = {}
			for _, path in paths do
				local node = w.adapter.node(path)
				if node ~= nil and node.rect ~= nil then
					out[path] = node.rect
				end
			end
			return out
		end,
		bindResourceTransport = function()
			return function() end
		end,
	}
end

type Surface = { kind: string, name: string, mount: (any) -> any }

local SURFACES: { Surface } = {}
for _, name in scenarioNames() do
	local module = require(`../../examples/gallery/scenarios/{name}`) :: any
	table.insert(SURFACES, {
		kind = "scenario",
		name = name,
		mount = function(w)
			return present(w, module.build(scenarioCtx(w)))
		end,
	})
end
for _, name in exampleNames() do
	local module = require(`../../examples/gallery/examples/{name}`) :: any
	table.insert(SURFACES, {
		kind = "example",
		name = name,
		mount = function(w)
			return present(
				w,
				module.build(
					Facet,
					w.core,
					{ env = w.env, actionSystem = w.system, presenter = w.presenter, adapter = w.adapter }
				)
			)
		end,
	})
end
for _, name in proofNames() do
	local module = require(`../../examples/reference/{name}`) :: any
	table.insert(SURFACES, {
		kind = "proof",
		name = name,
		mount = function(w)
			return present(
				w,
				module.build(
					Facet,
					w.core,
					{ env = w.env, actionSystem = w.system, presenter = w.presenter, adapter = w.adapter }
				)
			)
		end,
	})
end

-- ── the run ──────────────────────────────────────────────────────────────────

local total = 0
local bySurfaceNode: { [string]: boolean } = {}
local bySurfacePkgNode: { [string]: boolean } = {}
local bySurfaceViewNode: { [string]: boolean } = {}
local byPackage: { [string]: number } = {}
local byKind: { [string]: number } = {}
local cells = 0
local carvingPackages = 0
for _, pkg in PACKAGES do
	byPackage[pkg.id] = 0
	if pkg.carves then
		carvingPackages += 1
	end
end

local function count(surface: Surface, view: any, pkgId: string, found: { any })
	for _, v in found do
		total += 1
		byPackage[pkgId] = (byPackage[pkgId] or 0) + 1
		byKind[v.kind] = (byKind[v.kind] or 0) + 1
		bySurfaceNode[`{surface.name}|{v.node}`] = true
		bySurfacePkgNode[`{surface.name}|{pkgId}|{v.node}`] = true
		bySurfaceViewNode[`{surface.name}|{view.id}|{v.node}`] = true
	end
end

local started = os.clock()
for _, surface in SURFACES do
	for _, view in device_views.VIEWS do
		local w = world(view)
		local ok, err = pcall(function()
			surface.mount(w)
		end)
		if not ok then
			print(`  SKIP {surface.kind} '{surface.name}' at {view.id}: {err}`)
			continue
		end
		settle(w)
		if NEUTRAL_ONLY then
			cells += 1
			count(surface, view, "neutral", overflow_guard.violations(w.adapter, overflow_guard.newLedger({}), nil))
			continue
		end
		for _, pkg in PACKAGES do
			w.env:set("themeMetrics", pkg.snapshot)
			settle(w)
			cells += 1
			-- `--rect` withholds the SNAPSHOT from the oracle while the package is
			-- installed: same tree, old vocabulary. Every themed rule reads the
			-- snapshot and nothing else, so nil is exactly "untaught".
			local judgedWith = if RECT_ONLY then nil else pkg.snapshot
			count(surface, view, pkg.id, overflow_guard.violations(w.adapter, overflow_guard.newLedger({}), judgedWith))
		end
	end
end

local function size(set: { [string]: boolean }): number
	local n = 0
	for _ in set do
		n += 1
	end
	return n
end

local arm = if NEUTRAL_ONLY
	then "NEUTRAL (no package installed)"
	elseif RECT_ONLY then "THEMED, judged against the plain RECT (the vocabulary before the themed rules)"
	else "THEMED (every package the picker offers)"
print("")
print(`theme_containment_census — {arm}`)
print(
	`  corpus: {#SURFACES} surfaces x {#device_views.VIEWS} viewports x `
		.. `{if NEUTRAL_ONLY then 1 else #PACKAGES} pass(es) = {cells} cells, {string.format(
			"%.1f",
			os.clock() - started
		)}s`
)
if not NEUTRAL_ONLY then
	print(`  packages that carve anything: {carvingPackages} of {#PACKAGES}`)
end
print(`  total violations                     {total}`)
print(`  distinct by (surface, node)          {size(bySurfaceNode)}   <- the number the ADR books against`)
print(`  distinct by (surface, package, node) {size(bySurfacePkgNode)}`)
print(`  distinct by (surface, view, node)    {size(bySurfaceViewNode)}`)
local kinds: { string } = {}
for kind, n in byKind do
	table.insert(kinds, `{kind}={n}`)
end
table.sort(kinds)
print(`  by kind: {table.concat(kinds, "  ")}`)
if not NEUTRAL_ONLY then
	local rows: { string } = {}
	for _, pkg in PACKAGES do
		table.insert(rows, `{pkg.id}={byPackage[pkg.id]}{if pkg.carves then "" else " (flat)"}`)
	end
	print(`  by package: {table.concat(rows, "  ")}`)
end
print("")
