--!nocheck
--[[ WHAT A WAIVED OVERFLOW COSTS A PLAYER — the instrument behind the director's
	ruling of 2026-08-15, "fix the ones that hide text; waive the rest".

	  lune run tools/lune/triage_overflow_waivers
	  -> artifacts/swiftui-parity-round3/waiver-readability.txt

	WHY IT EXISTS. `tests/overflow_sweep.spec.luau` answers "does anything paint
	outside its box". That is not the same question as "can a player still READ
	this", and the difference is the whole ruling: a shadow past a plate edge and a
	label past the screen edge are the same sentence from the solver. Triaging 42
	waivers by reading their prose is a rubber stamp; this reads the SOLVE.

	THE THREE VERDICTS, per finding, at every cell it fires in:
	  * TEXT-UNREACHABLE / LEAF-UNREACHABLE(class) — a painting leaf whose rect
	    leaves the band a player can reach. The band is the screen minus the
	    showcase chrome, narrowed by every ScrollView ancestor's window (a scroll
	    host CLIPS) and widened again along the axis that host SCROLLS, because
	    content you can scroll to is content you can read. A labelled Button counts:
	    its label is copy and its target is reach.
	  * TEXT-TRUNCATED — the solver's own verdict that the string was cut, AND no
	    `disclose` to open it. Truncation with a way back is the degrade cascade
	    working (`text_audit.clippedEssential` draws the same line); truncation
	    without one is lost copy.
	  * TEXT-COVERED — a later-painted OPAQUE node over a quarter of the glyph
	    band. Opaque is measured, not assumed: a `Hit` Button carries no surface
	    and no label and covers nothing a player can see, and counting one is how
	    this probe manufactured its first false positives.
	    "LATER" IS THE RENDERER'S OWN Z, NOT A PATH SORT (fixed 2026-08-15). This
	    probe used to take paint order from `adapter.paths()`, whose docstring says
	    *sorted* — alphabetically, by path. That is not paint order and is not even
	    correlated with it: `BellZ/BadgeWhen/.../Count` sorts before its sibling
	    `BellZ/Bell` while the renderer paints the badge ON TOP of the bell, so the
	    probe reported a notification count "covered by" the button it decorates.
	    `syncZOrder` walks `(zIndex, declaration order)` depth-first and hands every
	    node an integer through `adapter.setZOrder`; `node.z` is that integer, and it
	    is the only thing here entitled to the word "later".

	A finding with none of the three is a bleed — a box, a plate or a decoration
	painting past its own edge with every character on screen, whole and uncovered.
	That is what "cosmetic" means in the waiver list, and it is a measurement
	rather than a judgement.

	IT RUNS TWO PASSES, the same two the sweep does: the neutral corpus, and the
	1.4x `xa` expansion on the surfaces that have a locale form (O-19). It is a
	TOOL, not a spec: it fails nothing, it prints what it measured.
]]
local Facet = require("../../src") :: any
local fake_target = require("../../tests/lib/fake_target")
local demo_picker = require("../../examples/gallery/client/demo_picker") :: any
local device_views = require("../../tests/lib/device_views")
local large_text = require("../../tests/lib/large_text")
local fs = require("@lune/fs")

local VIEWS = table.clone(device_views.VIEWS)
if _G.PROBE_ADD_390 ~= false then
	table.insert(VIEWS, { id = "phone-390x844", w = 390, h = 844, displaySize = "Small", input = "Touch" })
end
local CAPABILITIES = device_views.CAPABILITIES
local SHOWCASE_TOP = demo_picker.barReservation(device_views.CORE_TOP, nil, 8)

local OFFSETS: { number } = {}
for _, preference in large_text.PREFERENCES do
	table.insert(OFFSETS, preference.offset)
end
table.sort(OFFSETS)

local SETTLE_FRAMES = 3
local function settle(presenter: any)
	for _ = 1, SETTLE_FRAMES do
		presenter.refresh()
	end
end

local function world(view: any): any
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	env:set("coreSafeInsets", { top = SHOWCASE_TOP, bottom = 0, left = 0, right = 0 })
	env:set("displaySize", view.displaySize)
	env:set("preferredInput", view.input)
	env:set("capabilities", CAPABILITIES[view.input])
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new();
	(adapter :: any).scrollBarThickness = fake_target.SCROLL_BAR_THICKNESS
	local presenter = Facet.newPresenter(core, env, adapter, system)
	return { core = core, env = env, adapter = adapter, presenter = presenter, system = system }
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

local function present(w: any, built: any): any
	if built.handle == nil and built.screen ~= nil then
		built.handle = w.presenter.present(built.screen, built.present)
	end
	return built
end

-- ── the corpus, same three lists the sweep carries ───────────────────────────
local SCENARIOS = {}
do
	local src = fs.readFile("tests/overflow_sweep.spec.luau")
	local block = string.match(src, "local SCENARIOS = (%b{})")
	for line in string.gmatch(block, "[^\n]+") do
		local entry = string.match(line, '^%s*"([^"]+)",%s*$')
		if entry ~= nil then
			table.insert(SCENARIOS, entry)
		end
	end
end
local EXAMPLES = {
	"01_temperature_converter",
	"02_playlist_table",
	"03_settings_sync",
	"04_confirm_dialog",
	"05_word_game",
	"06_tile_game",
	"07_match3",
}
-- FOUR, NOT FIVE, SINCE 2026-08-30 (Wardrobe retirement): this list is a
-- hand-kept copy of `tests/overflow_sweep.spec.luau`'s, and the two must agree.
local PROOFS = { "p1_glade", "p2_cartwheel", "p3_sipworks", "p4_foyer" }
local VARIANTS: { [string]: { step: string, values: { string } } } = {
	row_actions = { step = "mode", values = { "list", "table", "vlist" } },
}

-- ── the sweep's own key derivation, copied verbatim ──────────────────────────
local SIG_MAX = 44
local function signature(issue: string): string
	local s = string.gsub(issue, "%d+", "N")
	s = string.gsub(s, "'[^']*'", "'X'")
	if #s <= SIG_MAX then
		return s
	end
	return string.match(string.sub(s, 1, SIG_MAX + 1), "^(.*)%s") or string.sub(s, 1, SIG_MAX)
end
local function normalizePath(path: string): string
	local out: { string } = {}
	local prevKey: string? = nil
	for segment in string.gmatch(path, "[^/]+") do
		local key = string.match(segment, "^%[(.*)%]$")
		local restates = prevKey ~= nil
			and (
				segment == prevKey
				or string.find(segment, string.match(prevKey :: string, "^%w+") or "\0", 1, true) ~= nil
			)
		if key ~= nil then
			table.insert(out, "[*]")
			prevKey = key
		elseif restates then
			table.insert(out, "*")
			prevKey = nil
		else
			table.insert(out, segment)
			prevKey = nil
		end
	end
	return "/" .. table.concat(out, "/")
end

-- ── the readability audit ────────────────────────────────────────────────────
local function isUnder(prefix: string, path: string): boolean
	return path == prefix or string.sub(path, 1, #prefix + 1) == prefix .. "/"
end

local function overlapArea(a: any, b: any): number
	local x = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
	local y = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
	if x <= 1 or y <= 1 then
		return 0
	end
	return x * y
end

-- WHAT IS ACTUALLY ON GLASS FOR THIS NODE, THIS FRAME: its rect intersected with
-- every ScrollView ancestor's window, because a scroll host mounts a real clip
-- host and paints nothing outside it. The occlusion pass needs this and the
-- reachability pass must NOT use it — "can the player scroll to it" and "is it
-- drawn right now" are different questions, and conflating them is how a row
-- clipped away by its own list got reported as covered by a neighbour (measured
-- 2026-08-15: `/ScrollHost/List/Row10`, whose list box had collapsed).
local function paintedRect(w: any, path: string, rect: any): any?
	local x0, y0, x1, y1 = rect.x, rect.y, rect.x + rect.w, rect.y + rect.h
	local cursor = path
	while true do
		local cut = string.find(cursor, "/[^/]*$")
		if cut == nil or cut == 1 then
			break
		end
		cursor = string.sub(cursor, 1, cut - 1)
		local n = w.adapter.node(cursor)
		if n == nil or n.class ~= "ScrollView" then
			continue
		end
		local box = n.windowRect or n.rect
		if box == nil then
			continue
		end
		x0, y0 = math.max(x0, box.x), math.max(y0, box.y)
		x1, y1 = math.min(x1, box.x + box.w), math.min(y1, box.y + box.h)
	end
	if x1 - x0 <= 1 or y1 - y0 <= 1 then
		return nil
	end
	return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

-- A NODE THAT PAINTS NOTHING CANNOT COVER ANYTHING. A `Hit` Button is a
-- transparent target (`label = ""`, no `surface`) and a ScrollView is a window;
-- counting either as an occluder manufactures a hidden-text verdict out of a
-- node the player never sees.
local function paints(n: any): boolean
	local props = n.props or {}
	-- ...AND `plain` IS THE SECOND TRANSPARENT CLASS (found 2026-08-15, the same
	-- shape as the `Hit` Button above). `surface = "plain"` is the caller saying
	-- NO PLATE: `chrome_slots.classify` returns nil for it before any class rule
	-- ("AN EXPLICIT `plain` PAINTS NOTHING", chrome_slots.luau:844) and the native
	-- path clears `nativeSurface` with it, so the node carries a stroke and a
	-- shape and no fill at all. Counting one is how this probe reported an
	-- avatar's initial as covered by the hairline RIM drawn around it.
	if props.surface ~= nil and props.surface ~= "plain" then
		return true
	end
	if n.class == "Image" then
		return true
	end
	if n.class == "Button" then
		return props.label ~= nil and props.label ~= ""
	end
	return false
end

-- REACHABILITY, per axis. A ScrollView CLIPS (the adapter mounts a real clip
-- host), so a rect outside its window is cut — but along the axis it SCROLLS the
-- player can bring it back, so only the cross axis is a hidden-text verdict.
-- With no scroll ancestor the bound is the visible band of the screen itself.
local function axisBounds(
	w: any,
	view: any,
	path: string
): {
	x: { lo: number, hi: number, scrolls: boolean },
	y: { lo: number, hi: number, scrolls: boolean },
}
	local bounds = {
		x = { lo = 0, hi = view.w, scrolls = false },
		y = { lo = SHOWCASE_TOP, hi = view.h, scrolls = false },
	}
	local cursor = path
	while true do
		local cut = string.find(cursor, "/[^/]*$")
		if cut == nil or cut == 1 then
			break
		end
		cursor = string.sub(cursor, 1, cut - 1)
		local n = w.adapter.node(cursor)
		if n == nil or n.class ~= "ScrollView" then
			continue
		end
		local region = n.scrollRegion
		local box = n.windowRect or n.rect
		if box == nil then
			continue
		end
		local scrollAxis = if region ~= nil then region.axis else nil
		for _, axis in { "x", "y" } do
			local lo = if axis == "x" then box.x else box.y
			local hi = if axis == "x" then box.x + box.w else box.y + box.h
			if scrollAxis == axis then
				bounds[axis].scrolls = true
			elseif not bounds[axis].scrolls then
				bounds[axis].lo = math.max(bounds[axis].lo, lo)
				bounds[axis].hi = math.min(bounds[axis].hi, hi)
			end
		end
	end
	return bounds
end

-- text nodes under `node` that a player cannot fully read, and why
local function unreadable(w: any, view: any, nodePath: string): { string }
	local hidden = w.controller.hiddenRoots()
	local facts = w.controller.textAt()
	local paths = w.adapter.paths()
	local out: { string } = {}
	-- every painting node, for the occlusion pass
	local painting: { { path: string, rect: any, class: string, order: number } } = {}
	for _, path in paths do
		local n = w.adapter.node(path)
		if n == nil or n.rect == nil or n.visible == false then
			continue
		end
		local isHidden = false
		for root, flag in hidden do
			if flag == true and isUnder(root, path) then
				isHidden = true
				break
			end
		end
		if isHidden then
			continue
		end
		table.insert(painting, {
			path = path,
			rect = n.rect,
			class = n.class,
			-- the renderer's own paint order (see the header): a node the z walk
			-- never reached cannot be shown to be on top of anything, so it sorts
			-- to the bottom rather than borrowing an alphabetical rank
			order = n.z or -1,
			opaque = paints(n),
			label = (n.props or {}).label,
			painted = paintedRect(w, path, n.rect),
		})
	end
	-- ...and every node under the finding, whatever its class: a control pushed
	-- off the band is not text, but it is not cosmetic either.
	local verdicts: { { kind: string, line: string } } = {}
	local textUnder = 0
	for _, entry in painting do
		local inside = isUnder(nodePath, entry.path)
		local r = entry.rect
		local f = facts[entry.path]
		if entry.class == "Text" and inside then
			textUnder += 1
		end
		if inside then
			local bounds = axisBounds(w, view, entry.path)
			local worst, axisName = 0, ""
			for _, axis in { "x", "y" } do
				if bounds[axis].scrolls then
					continue
				end
				local lo = if axis == "x" then r.x else r.y
				local hi = if axis == "x" then r.x + r.w else r.y + r.h
				local gone = math.max(bounds[axis].lo - lo, hi - bounds[axis].hi)
				if gone > worst then
					worst, axisName = gone, axis
				end
			end
			-- a container is unreachable only in the sense its children are; report
			-- the LEAVES (a node with no painting child under it)
			local isLeaf = true
			for _, other in painting do
				if other.path ~= entry.path and isUnder(entry.path, other.path) then
					isLeaf = false
					break
				end
			end
			if worst > 1 and isLeaf then
				local kind = if entry.class == "Text" then "TEXT-UNREACHABLE" else `LEAF-UNREACHABLE({entry.class})`
				table.insert(verdicts, {
					kind = kind,
					line = `{entry.path} [{entry.class} {r.w}x{r.h} at {r.x},{r.y}] "{(f and f.text) or entry.label or ""}" — off {axisName} by {math.floor(
						worst
					)}px`,
				})
			end
			-- TRUNCATION WITH A WAY BACK IS NOT HIDDEN TEXT. `disclose` is the
			-- framework's own escape (a plate that shows the whole string), and
			-- `text_audit.clippedEssential` draws the same line: a cut string a
			-- player can still open is a designed degrade, not lost copy.
			if entry.class == "Text" and f ~= nil and f.truncated == true and f.disclose ~= true then
				table.insert(verdicts, {
					kind = "TEXT-TRUNCATED",
					line = `{entry.path} [{r.w}x{r.h}] "{f.text or ""}" — truncated, no disclose`,
				})
			end
			-- ...and whether anything painted LATER covers this copy, wherever it
			-- lives (the overflowing node's own text is the usual victim: a row that
			-- outgrew its slot is painted over by the next row's plate)
			if entry.class == "Text" then
				for _, other in painting do
					if
						other.class == "Text"
						or isUnder(entry.path, other.path)
						or isUnder(other.path, entry.path)
						or other.order <= entry.order
					then
						continue
					end
					local victim, over = entry.painted, other.painted
					if
						victim ~= nil
						and over ~= nil
						and other.opaque
						and overlapArea(victim, over) > 0.25 * (victim.w * victim.h)
					then
						table.insert(verdicts, {
							kind = "TEXT-COVERED",
							line = `{entry.path} "{(f and f.text) or ""}" — covered by {other.path} [{other.class}]`,
						})
						break
					end
				end
			end
			continue
		end
		-- the other half: does the overflowing subtree paint OVER somebody's copy?
		if entry.class ~= "Text" then
			continue
		end
		for _, other in painting do
			if
				other.class == "Text"
				or not isUnder(nodePath, other.path)
				or isUnder(entry.path, other.path)
				or isUnder(other.path, entry.path)
				or other.order <= entry.order
			then
				continue
			end
			local victim, over = entry.painted, other.painted
			if
				victim ~= nil
				and over ~= nil
				and other.opaque
				and overlapArea(victim, over) > 0.25 * (victim.w * victim.h)
			then
				table.insert(verdicts, {
					kind = "TEXT-COVERED",
					line = `{entry.path} "{(f and f.text) or ""}" — covered by {other.path}`,
				})
				break
			end
		end
	end
	return verdicts, textUnder
end

-- ── the run ──────────────────────────────────────────────────────────────────
local report: { [string]: any } = {}
local PASS = "neutral"

local function record(surface: string, variantValue: string, view: any, offset: number, w: any, built: any)
	for _, finding in built.handle.controller.diagnostics() do
		if finding.designed == true then
			continue
		end
		local key = `{PASS}|{surface}|{variantValue}|{normalizePath(finding.node)}|{signature(finding.issue)}`
		local row = report[key]
		if row == nil then
			row = { key = key, cells = 0, counts = {}, samples = {}, textUnder = 0 }
			report[key] = row
		end
		row.cells += 1
		local verdicts, textUnder = unreadable(w, view, finding.node)
		row.textUnder = math.max(row.textUnder, textUnder)
		for _, v in verdicts do
			row.counts[v.kind] = (row.counts[v.kind] or 0) + 1
			if row.samples[v.kind] == nil then
				row.samples[v.kind] = `{view.id}@+{offset}: {v.line}`
			end
		end
	end
end

local l10n = require("../../tests/fixtures/a11y_l10n_fixtures")

-- THE LOCALE FORM OF A SURFACE, by the two mechanisms that exist: a fixture step
-- that swings its own string table, or an exported `copy` table this can expand
-- in place the way tests/examples_gallery.spec already does.
local function localeApply(module: any, built: any): (() -> ())?
	if built.steps ~= nil and built.steps.locale ~= nil then
		built.steps.locale(built, "xa")
		return function()
			built.steps.locale(built, "en")
		end
	end
	return nil
end

local function pseudoCopy(module: any): (() -> ())?
	if type(module.copy) ~= "table" then
		return nil
	end
	local original: { [string]: string } = {}
	for key, value in module.copy do
		if type(value) == "string" then
			original[key] = value
			module.copy[key] = l10n.pseudoLocalize(value)
		end
	end
	return function()
		for key, value in original do
			module.copy[key] = value
		end
	end
end

local function sweepOne(kind: string, name: string, mount: (any) -> any, module: any?, locale: boolean?)
	local variant = VARIANTS[name]
	local restoreCopy: (() -> ())? = nil
	if locale == true and module ~= nil then
		restoreCopy = pseudoCopy(module)
	end
	for _, view in VIEWS do
		local w = world(view)
		local built = mount(w)
		local restoreStep: (() -> ())? = nil
		if locale == true and module ~= nil then
			restoreStep = localeApply(module, built)
			if restoreStep == nil and restoreCopy == nil then
				break -- this surface has no locale form at all
			end
		end
		settle(w.presenter)
		w.controller = built.handle.controller
		for _, offset in OFFSETS do
			w.env:set("preferredTextOffset", offset)
			settle(w.presenter)
			if variant == nil then
				record(name, "-", view, offset, w, built)
			else
				for _, value in variant.values do
					built.steps[variant.step](built, value)
					settle(w.presenter)
					record(name, value, view, offset, w, built)
				end
			end
		end
	end
end

for _, name in SCENARIOS do
	local module = require(`../../examples/gallery/scenarios/{name}`) :: any
	sweepOne("scenario", name, function(w)
		return present(w, module.build(scenarioCtx(w)))
	end)
end
for _, name in EXAMPLES do
	local module = require(`../../examples/gallery/examples/{name}`) :: any
	sweepOne("example", name, function(w)
		return present(
			w,
			module.build(
				Facet,
				w.core,
				{ env = w.env, actionSystem = w.system, presenter = w.presenter, adapter = w.adapter }
			)
		)
	end)
end
for _, name in PROOFS do
	local module = require(`../../examples/reference/{name}`) :: any
	sweepOne("proof", name, function(w)
		return present(
			w,
			module.build(
				Facet,
				w.core,
				{ env = w.env, actionSystem = w.system, presenter = w.presenter, adapter = w.adapter }
			)
		)
	end)
end

-- ── THE LOCALE PASS ──────────────────────────────────────────────────────────
PASS = "xa"
for _, name in SCENARIOS do
	local module = require(`../../examples/gallery/scenarios/{name}`) :: any
	sweepOne("scenario", name, function(w)
		return present(w, module.build(scenarioCtx(w)))
	end, module, true)
end
for _, name in PROOFS do
	local module = require(`../../examples/reference/{name}`) :: any
	sweepOne("proof", name, function(w)
		return present(
			w,
			module.build(
				Facet,
				w.core,
				{ env = w.env, actionSystem = w.system, presenter = w.presenter, adapter = w.adapter, locale = "xa" }
			)
		)
	end, module, true)
end

local keys: { string } = {}
for key in report do
	table.insert(keys, key)
end
table.sort(keys)
local lines: { string } = {}
for _, key in keys do
	local row = report[key]
	local counts: { string } = {}
	for kind, n in row.counts do
		table.insert(counts, `{kind}={n}`)
	end
	table.sort(counts)
	table.insert(lines, `{key}\n   cells={row.cells} textNodes={row.textUnder} {table.concat(counts, " ")}`)
	local kinds: { string } = {}
	for kind in row.samples do
		table.insert(kinds, kind)
	end
	table.sort(kinds)
	for _, kind in kinds do
		table.insert(lines, `     [{kind}] {row.samples[kind]}`)
	end
end
fs.writeFile("artifacts/swiftui-parity-round3/waiver-readability.txt", table.concat(lines, "\n"))
print(`wrote {#keys} finding keys`)
