--!strict
-- NM-H4a probe: replay the director's sequence and compare the WHOLE engine-side
-- record against a fresh mount, not just `visible` + `rect`.
--
-- `tests/hud_paint_probe.spec` already drives this sequence and compares
-- visibility and geometry, and diverges by zero. Everything else the adapter
-- holds — ZIndex, the composed presentation offset/size, the CanvasGroup's
-- transparency, the hit rect, the root's enabled bit, every prop — has never
-- been compared at all. A defect in any of those paints nothing while every
-- model-side instrument agrees with itself, which is the signature.
--
-- Usage: lune run tools/lune/_probe_h4a

local LuauUI = require("../../src") :: any
local fake_target = require("../../tests/lib/fake_target")
local hud = require("../../examples/gallery/scenarios/hud") :: any

local PORTRAIT = {
	viewportRect = { x = 0, y = 0, w = 393, h = 852 },
	coreSafeInsets = { top = 58, right = 0, bottom = 0, left = 0 },
	deviceSafeInsets = { top = 59, right = 0, bottom = 34, left = 0 },
	topbarInset = { x = 164, y = 0, w = 229, h = 58 },
}
local LANDSCAPE = {
	viewportRect = { x = 0, y = 0, w = 852, h = 393 },
	coreSafeInsets = { top = 46, right = 0, bottom = 0, left = 0 },
	deviceSafeInsets = { top = 0, right = 59, bottom = 21, left = 59 },
	topbarInset = { x = 223, y = 0, w = 629, h = 46 },
}

local function world(view: any): any
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	for key, value in view do
		env:set(key, value)
	end
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local presenter = LuauUI.newPresenter(core, env, adapter, system)
	return { core = core, env = env, adapter = adapter, presenter = presenter, system = system }
end

local function geometryFor(w: any): (paths: { string }) -> any
	return function(paths: { string }): any
		local out: { [string]: any } = {}
		for _, path in paths do
			local node = w.adapter.node(path)
			if node ~= nil and node.rect ~= nil then
				local screenId = string.match(path, "^/([^/]+)")
				local rootOn = if screenId ~= nil then w.adapter.rootVisibleOf(screenId) ~= false else true
				out[path] = {
					x = node.rect.x,
					y = node.rect.y,
					w = node.rect.w,
					h = node.rect.h,
					visible = w.adapter.visibleOf(path) ~= false,
					enabled = rootOn,
				}
			end
		end
		return out
	end
end

local function ctxFor(w: any): any
	return {
		LuauUI = LuauUI,
		core = w.core,
		env = w.env,
		adapter = w.adapter,
		presenter = w.presenter,
		actionSystem = w.system,
		flags = {},
		geometry = geometryFor(w),
	}
end

local function mount(w: any): any
	local built = hud.build(ctxFor(w))
	built.handle = w.presenter.present(built.screen, built.present)
	w.presenter.refresh()
	w.presenter.refresh()
	return built
end

local function rotate(w: any, view: any)
	w.env:set("viewportRect", view.viewportRect)
	w.presenter.refresh()
	w.env:set("coreSafeInsets", view.coreSafeInsets)
	w.env:set("deviceSafeInsets", view.deviceSafeInsets)
	w.env:set("topbarInset", view.topbarInset)
	w.presenter.refresh()
	w.presenter.refresh()
end

-- THE WIDE READBACK. Every engine-side fact the fake target holds for a node,
-- rendered as one comparable string.
local function fmtRect(r: any): string
	if r == nil then
		return "nil"
	end
	return string.format(
		"%d,%d %dx%d",
		math.floor((r.x or 0) + 0.5),
		math.floor((r.y or 0) + 0.5),
		math.floor((r.w or 0) + 0.5),
		math.floor((r.h or 0) + 0.5)
	)
end

local function stableProps(node: any): string
	local keys: { string } = {}
	for k in node.props do
		table.insert(keys, k)
	end
	table.sort(keys)
	local parts: { string } = {}
	for _, k in keys do
		local v = node.props[k]
		local rendered
		if type(v) == "table" then
			local inner: { string } = {}
			local ik: { string } = {}
			for kk in v do
				if type(kk) == "string" then
					table.insert(ik, kk)
				end
			end
			table.sort(ik)
			for _, kk in ik do
				local vv = (v :: any)[kk]
				if type(vv) ~= "table" and type(vv) ~= "function" then
					table.insert(inner, `{kk}={tostring(vv)}`)
				end
			end
			rendered = "{" .. table.concat(inner, ",") .. "}"
		elseif type(v) == "function" then
			rendered = "fn"
		else
			rendered = tostring(v)
		end
		table.insert(parts, `{k}={rendered}`)
	end
	return table.concat(parts, " ")
end

local function wideTree(w: any, prefix: string): { [string]: string }
	local out: { [string]: string } = {}
	for _, path in w.adapter.paths() do
		if string.find(path, prefix) ~= nil then
			local n = w.adapter.node(path)
			if n ~= nil then
				local cg = n.canvasGroupInstance
				out[path] = table.concat({
					`class={n.class}`,
					`vis={tostring(w.adapter.visibleOf(path))}`,
					`rect={fmtRect(n.rect)}`,
					`z={tostring(n.z)}`,
					`presPos={fmtRect(n.presentedPosition)}`,
					`presSize={if n.presentedSize ~= nil then `{n.presentedSize.w}x{n.presentedSize.h}` else "nil"}`,
					`presOff={if n.presentationOffset ~= nil
						then `{n.presentationOffset.x},{n.presentationOffset.y}`
						else "nil"}`,
					`groupT={if cg ~= nil then tostring(cg.groupTransparency) else "none"}`,
					`hit={fmtRect(n.hitRect)}`,
					`elided={tostring(n.elided)}`,
					`parked={tostring(n.parked)}`,
					`alive={tostring(n.alive)}`,
					`props[{stableProps(n)}]`,
				}, " | ")
			end
		end
	end
	return out
end

local function driveTheSequence(w: any, built: any)
	built.steps.openOverflow(built)
	w.presenter.refresh()
	built.steps.closeOverflow(built)
	w.presenter.refresh()

	rotate(w, LANDSCAPE)
	built.steps.openUrlBar(built)
	w.presenter.refresh()
	built.steps.closeUrlBar(built)
	w.presenter.refresh()

	rotate(w, PORTRAIT)
	built.steps.openUrlBar(built)
	w.presenter.refresh()
	built.steps.closeUrlBar(built)
	w.presenter.refresh()

	rotate(w, LANDSCAPE)
end

local function compare(label: string, driven: { [string]: string }, fresh: { [string]: string })
	local seen: { [string]: boolean } = {}
	for p in driven do
		seen[p] = true
	end
	for p in fresh do
		seen[p] = true
	end
	local keys: { string } = {}
	for p in seen do
		table.insert(keys, p)
	end
	table.sort(keys)
	local n = 0
	local byField: { [string]: number } = {}
	local sample: { [string]: string } = {}
	for _, p in keys do
		if driven[p] ~= fresh[p] then
			n += 1
			local dparts = string.split(tostring(driven[p]), " | ")
			local fparts = string.split(tostring(fresh[p]), " | ")
			local m = math.max(#dparts, #fparts)
			for i = 1, m do
				if dparts[i] ~= fparts[i] then
					local field = string.match(dparts[i] or fparts[i] or "?", "^([%w%[]+)") or "?"
					byField[field] = (byField[field] or 0) + 1
					if sample[field] == nil then
						sample[field] = `{p}\n      driven: {tostring(dparts[i])}\n      fresh : {tostring(fparts[i])}`
					end
				end
			end
		end
	end
	print(`{label}: {n} divergence(s) over {#keys} paths`)
	local fk: { string } = {}
	for f in byField do
		table.insert(fk, f)
	end
	table.sort(fk)
	for _, f in fk do
		print(`   field {f}: {byField[f]} node(s); first: {sample[f]}`)
	end
	return n
end

local CYCLES = tonumber((require("@lune/process") :: any).args[1] or "2") or 2

local function driveN(w: any, built: any, cycles: number)
	built.steps.openOverflow(built)
	w.presenter.refresh()
	built.steps.closeOverflow(built)
	w.presenter.refresh()
	for _ = 1, cycles do
		rotate(w, LANDSCAPE)
		built.steps.openUrlBar(built)
		w.presenter.refresh()
		built.steps.closeUrlBar(built)
		w.presenter.refresh()
		rotate(w, PORTRAIT)
		built.steps.openUrlBar(built)
		w.presenter.refresh()
		built.steps.closeUrlBar(built)
		w.presenter.refresh()
	end
	rotate(w, LANDSCAPE)
end

-- ARM 1: the sequence, wide readback, against a fresh landscape mount.
local w = world(PORTRAIT)
local built = mount(w)
if CYCLES == 2 then
	driveTheSequence(w, built)
else
	driveN(w, built, CYCLES)
end
local drivenHud = wideTree(w, "^/HudScreen")
local drivenAll = wideTree(w, "^/")
local drivenReport = built.report()

local fw = world(LANDSCAPE)
local fresh = mount(fw)
local freshHud = wideTree(fw, "^/HudScreen")
local freshAll = wideTree(fw, "^/")
local freshReport = fresh.report()

print(`== ARM 1: wide engine-side record, driven ({CYCLES} cycles) vs fresh ==`)
compare("/HudScreen only", drivenHud, freshHud)
compare("every surface", drivenAll, freshAll)

-- THE Z LEDGER. Which paths exist in only one arm, and what the z delta is per
-- path in document order — a uniform delta is a shifted band, a delta that
-- CHANGES along document order is a reordering.
print("")
print("== presence and z ledger ==")
local onlyDriven, onlyFresh = {}, {}
for p in drivenAll do
	if freshAll[p] == nil then
		table.insert(onlyDriven, p)
	end
end
for p in freshAll do
	if drivenAll[p] == nil then
		table.insert(onlyFresh, p)
	end
end
table.sort(onlyDriven)
table.sort(onlyFresh)
print(`only in driven ({#onlyDriven}):`)
for _, p in onlyDriven do
	print(`   {p}`)
end
print(`only in fresh ({#onlyFresh}):`)
for _, p in onlyFresh do
	print(`   {p}`)
end

local function zOf(w2: any, path: string): number?
	local n = w2.adapter.node(path)
	return if n ~= nil then n.z else nil
end
local shared: { string } = {}
for p in drivenAll do
	if freshAll[p] ~= nil then
		table.insert(shared, p)
	end
end
table.sort(shared, function(a, b)
	local za, zb = zOf(fw, a) or -1, zOf(fw, b) or -1
	if za == zb then
		return a < b
	end
	return za < zb
end)
local deltas: { [number]: number } = {}
local prevDelta: number? = nil
print("z delta transitions (fresh-z order):")
for _, p in shared do
	local zd, zf = zOf(w, p), zOf(fw, p)
	if zd ~= nil and zf ~= nil then
		local d = zd - zf
		deltas[d] = (deltas[d] or 0) + 1
		if d ~= prevDelta then
			print(`   at fresh z={zf} driven z={zd} delta={d}  {p}`)
			prevDelta = d
		end
	end
end
local dk: { number } = {}
for d in deltas do
	table.insert(dk, d)
end
table.sort(dk)
for _, d in dk do
	print(`   delta {d}: {deltas[d]} node(s)`)
end

--[[ THE ADOPTION LEDGER.

	`screen_target.adopt` has NO root parameter. When the adopted node has no
	instance host it is parented under `lastRootHandle.gui` — a module-scope local
	set by the LAST `create` on this adapter, whichever SURFACE that create
	belonged to (screen_target.luau:987, :1212, :3708). The fake target has no
	parent model at all, which is why every headless replay so far has been blind
	to this.

	The op log carries everything needed to replay the live rule exactly: walk it,
	track the surface of the last `create`, and every `adopt` whose own surface
	differs is a node the live adapter parents into ANOTHER surface's ScreenGui. ]]
local function adoptionLedger(label: string, w2: any)
	local lastCreateSurface: string? = nil
	local mis, total = 0, 0
	local firstFew: { string } = {}
	for _, op in w2.adapter.ops() do
		local createPath = string.match(op, "^create (%S+)")
		if createPath ~= nil then
			lastCreateSurface = string.match(createPath, "^/[^/]+")
		end
		local adoptPath = string.match(op, "^adopt (%S+)")
		if adoptPath ~= nil then
			total += 1
			local surface = string.match(adoptPath, "^/[^/]+")
			if surface ~= lastCreateSurface then
				mis += 1
				if #firstFew < 12 then
					table.insert(firstFew, `{adoptPath}  -> parented under {tostring(lastCreateSurface)}`)
				end
			end
		end
	end
	print(`{label}: {total} adoption(s), {mis} into the WRONG surface root`)
	for _, line in firstFew do
		print(`   {line}`)
	end
end

print("")
print("== adoption ledger (the live adapter's lastRootHandle rule, replayed) ==")
adoptionLedger("driven", w)
adoptionLedger("fresh", fw)

-- ...and the same question asked of the target's own parent record, which is the
-- form a regression can assert.
local function rootAudit(label: string, w2: any)
	local wrong = 0
	for _, p in w2.adapter.paths() do
		local own = string.match(p, "^/([^/]+)")
		local under = w2.adapter.rootIdOf(p)
		if under ~= nil and own ~= nil and under ~= own then
			wrong += 1
			if wrong <= 12 then
				print(`   {p} is parented under root '{under}'`)
			end
		end
	end
	print(`{label}: {wrong} node(s) under the wrong surface root`)
end
rootAudit("driven", w)
rootAudit("fresh", fw)

print("")
print("== watchlist, full record both arms ==")
for _, p in
	{
		"/HudScreen/Hud/Rounds/RoundStrip/R1",
		"/HudScreen/Hud/Rounds/RoundStrip/R2",
		"/HudScreen/Hud/Rounds/RoundStrip/R3",
		"/HudScreen/Hud/Tasks/TasksOne/TasksOneBody",
		"/HudScreen/Drivers/UrlBar",
	}
do
	print(`  {p}`)
	print(`    driven: {tostring(drivenAll[p])}`)
	print(`    fresh : {tostring(freshAll[p])}`)
end

-- IS THE Z BAND MONOTONIC IN DOCUMENT ORDER? A duplicate or an inversion is what
-- turns a shifted band into an occlusion.
local function zAudit(label: string, w2: any)
	local seen: { [number]: string } = {}
	local dupes = 0
	for _, p in w2.adapter.paths() do
		local n = w2.adapter.node(p)
		if n ~= nil and n.z ~= nil then
			local key = string.match(p, "^/[^/]+") or ""
			local id = `{key}#{n.z}`
			if seen[id :: any] ~= nil then
				dupes += 1
				if dupes <= 10 then
					print(`   {label} DUPLICATE z {n.z} on {key}: {seen[id :: any]} and {p}`)
				end
			else
				seen[id :: any] = p
			end
		end
	end
	print(`{label}: {dupes} duplicate z within a surface`)
end
zAudit("driven", w)
zAudit("fresh", fw)

print("")
print("== renderer stats ==")
local function stats(label: string, b: any)
	local r = b.report()
	local s = r.stats
	if s == nil then
		print(`{label}: no stats in report; keys:`)
		local ks: { string } = {}
		for k in r do
			table.insert(ks, k)
		end
		table.sort(ks)
		print("  " .. table.concat(ks, ", "))
		return
	end
	print(
		`{label}: creates={s.creates} recycled={s.recycled} parked={s.parked} parkRefused={s.parkRefused} elided={s.elided}`
	)
end
stats("driven", built)
stats("fresh", fresh)

print("")
print("== paint probe ==")
local function probeLine(label: string, r: any)
	local p = r.paintProbe
	if p == nil then
		print(`{label}: no paintProbe`)
		return
	end
	print(
		`{label}: latches={p.latches} held={tostring(p.held)} engine={tostring(p.engine)} expected={p.expected} lost={#p.lost}`
	)
	for _, name in p.lost do
		print(`   lost: {name}`)
	end
end
probeLine("driven", drivenReport)
probeLine("fresh", freshReport)

built.dispose()
fresh.dispose()

--[[ ARM 2 — THE CONFIGURATION THE PHONE ACTUALLY RUNS.

	The gallery presents its own showcase screen ON TOP of the scenario's
	(`examples/gallery/client/init.client.luau:961` after `:444`), so the adapter
	hosts at least three live surfaces: the scenario, the showcase chrome, and the
	`hud` demo's own paint-probe plate. ARM 1's world has only two, and its
	orderings happen to be safe.

	The rule under test is `screen_target.adopt`'s: an adopted node with no
	instance host is parented under whatever root created LAST, anywhere on the
	adapter. A second surface that also re-solves on rotation is all it takes for
	that root to belong to somebody else.
]]
local UI = require("../../src/blueprint")

local function chromeScreen(core: any, env: any): any
	local kids: { any } = {}
	local wide = (env:get("viewportRect"):get() :: any).w > 500
	for i = 1, if wide then 6 else 3 do
		table.insert(kids, UI.Text({ id = `ChromeItem{i}`, text = `item {i}` }))
	end
	return UI.Screen({
		id = "Showcase",
		children = {
			UI.VStack({ id = "ChromeCol", children = kids }),
		},
	})
end

print("")
print("== ARM 2: the HUD with a second live surface above it ==")
local w2 = world(PORTRAIT)
local built2 = mount(w2)
-- presented AFTER the scenario, exactly as the gallery does
local chromeHandle = w2.presenter.present(chromeScreen(w2.core, w2.env), {})
w2.presenter.refresh()
if CYCLES == 2 then
	driveTheSequence(w2, built2)
else
	driveN(w2, built2, CYCLES)
end
adoptionLedger("arm2", w2)
rootAudit("arm2", w2)
w2.presenter.dismiss(chromeHandle)
built2.dispose()
