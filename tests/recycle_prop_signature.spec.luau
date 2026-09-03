--!strict
--[[ W1 — A RECYCLED INSTANCE KEEPS A STYLE PROP IT NEVER DECLARED.

	`propSigCache` (`renderer.luau:885-905`) is keyed on the props TABLE identity
	and is never invalidated, while `mount.luau:637` mutates that same table in
	place on every reactive write. A reactive prop whose value crosses nil
	therefore ADDS or REMOVES a key after the signature was cached:

	  reactive `shadow` starts nil -> no `shadow` key -> sig "…,color", cached,
	  and `recycleKeyOf[path]` frozen from it (`:1042-1043`);
	  the signal fires a shadow table -> the key appears -> `applyStyleProp`
	  materialises a real `UIShadow` (`screen_paint.luau:554-573`);
	  at park the handle goes into the bucket for the STALE "…,color" key;
	  a fresh node declaring only `color` adopts it, adoption writes only the
	  properties that DIFFER (`:1377-1391` — an ABSENT prop raises no write at
	  all), and the `UIShadow` survives onto a node that never asked for one.

	The whole safety argument for carrying property caches across an adoption is
	that "every property on the instance is one the new node also declares"
	(`renderer.luau:866-884`), and a stale signature is exactly the case where
	that is false.

	(Anchors above are the brief's; re-grepped post-Phase-0: the cache WAS
	`renderer.luau:956-973`, the safety comment `:922-935`, the two call sites
	`:1063` and `:1108`, `recycleKeyOf[path]` read/clear `:2492-2493`,
	`applyShadow` is `src/client/screen_paint.luau:554`, and the three in-place
	writes are `mount.luau:634/637/644` — `:637` is the reactive one.)

	INVESTIGATION FINDING (self-review, Step 7, before this spec's cases were
		finalised) — READ THIS BEFORE TRUSTING THE HEADER ABOVE AS "WHAT THIS FIX
		CLOSES". Built the brief's exact scenario (a `core:signal(nil)`-wired
		`shadow` on a ragged virtualized-list's odd rows, flipped while mounted,
		parked, and a later create offered the pooled handle) and instrumented
		`propSignature` directly (temporary, reverted — never shipped):

		  * `propSignature` is called exactly twice per node CREATE and ZERO times
		    on any later frame — confirmed on a 200-frame nameplates all-dirty run,
		    1503 creates -> 3006 calls at mount, +0 over 200 ticks. Matches the
		    fix's own comment exactly.
		  * EVERY cache hit recorded (3846 on this fixture, 3489 on
		    `instance_recycling.spec` alone) is the SECOND of a node's own two
		    create-time calls — i.e. a hit on the value its OWN first call just
		    computed, nothing mutates in between. Zero cross-node hits, zero
		    hits separated by a reactive write, in either suite.
		  * `recycleKeyOf[path]` (`:919`, write `:1117`, read+clear `:2492-2493`)
		    is written EXACTLY ONCE, at that same create event, and is never
		    revisited while the node stays mounted — `handles[node.path] == nil`
		    (`:1010`) is the only gate into the block that calls `propSignature`
		    at all, and the only site that ever nils a mounted node's handle is
		    the departure sweep itself (`:2529`), which tears the framework node
		    down in the same pass. So a reactive prop that crosses nil AFTER
		    create, while the node stays mounted, is invisible to
		    `recycleKeyOf` — WHETHER OR NOT `propSignature` caches its answer.

		CONCLUSION, MEASURED RATHER THAN ASSUMED: deleting `propSigCache` changes
		no observable outcome in this codebase's current call graph (confirmed:
		the full existing `instance_recycling*` + `instance_park_corpse` suites
		and this file's own differential below are byte-identical with the cache
		present or absent). The brief's own two-case scenario (built verbatim,
		churned hard enough to force real recycling — `parked > 0`, `recycled >
		0`) reproduces the described leak on BOTH sides of this fix: the actual
		staleness lives in `recycleKeyOf` being frozen at CREATE, not in whether
		`propSignature` memoises. The deletion is still correct and still ships
		(a strong, never-cleared, per-mounted-node table is real defensive/memory
		cleanup, and the brief's own rejected-alternative paragraph is the reason
		a smarter key is out of scope here) — it is just not, by itself, the fix
		the header above claims. Reported to the controller as a finding; not
		something this task is authorized to close (ruling: "no alternative
		key"). The two reproduction cases are not shipped running (a permanently
		red case cannot sit in this gate), and are preserved in
		`.superpowers/sdd/2026-09-02-wicked-fast-B-facet/task-8-report.md` with
		the exact bodies, the measured offender lists, and the call-count/cache-
		hit instrumentation output. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")
local Facet = require("../src") :: any
local virtual_list = require("../src/controls/virtual_list")
local world = require("./lib/world")

describe("W1: the cache is gone, structurally", function()
	it("`propSigCache` no longer exists anywhere in the renderer", function()
		local source = fs.readFile("src/render/renderer.luau")
		expect(string.find(source, "propSigCache", 1, true)).toBe(nil)
	end)

	it("`propSignature` computes fresh every call — no memo table anywhere near it", function()
		local source = fs.readFile("src/render/renderer.luau")
		local body = string.match(source, "local function propSignature%(node: any%): string(.-)\n\tend")
		assert(body ~= nil, "propSignature's body was not found to read")
		-- no `[` index read against anything but `props` itself inside the body —
		-- the shape a reintroduced cache (`propSigCache[props]`, or any other
		-- table keyed on the props identity) would have to take
		for line in string.gmatch(body :: string, "[^\n]+") do
			local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
			if string.find(trimmed, "%[", 1, false) ~= nil then
				expect(`propSignature line indexes something: {trimmed}`).toBe(
					"propSignature line indexes something: \tfor name in props do"
				)
			end
		end
	end)
end)

-- The brief's own ragged-shadow world, reused for the ONE claim this fix DOES
-- hold: a row whose `shadow` value never crosses nil is at no risk at all,
-- with or without the cache — the differential Step 7 asks for ("does dropping
-- the cache change any recycle key for a node whose props never cross nil?").
local ROW_HEIGHT = 56
local VIEWPORT = { w = 360, h = 640 }
local ROW_COUNT = 200

local function makeItems(n: number)
	local out = {}
	for i = 1, n do
		table.insert(out, { id = `r{i}`, label = `Row {i}`, detail = `detail {i * 7 % 13}` })
	end
	return out
end

-- `alwaysReal`: when true, every odd row's `shadow` signal is seeded with a
-- real value BEFORE mount (never nil, never crosses), so the row's DECLARED
-- set is stable for its whole life — the case the safety argument was always
-- meant to cover. When false (the default), it is never wired at all.
--
-- Built on `tests/lib/world.luau` (reuse audit REUSE-88, controller ruling
-- R12's follow-up trigger: the next spec file that adds a hand-rolled builder
-- migrates its file onto the shared substrate instead of adding one).
local function makeWorld(alwaysReal: boolean?)
	local items = makeItems(ROW_COUNT)
	local shadowSignals: { [string]: any } = {}
	local w = world.new({ viewport = { x = 0, y = 0, w = VIEWPORT.w, h = VIEWPORT.h } })
	if alwaysReal then
		for _, item in items do
			local n = tonumber(string.match(item.id, "%d+")) :: number
			if n % 3 == 0 then
				shadowSignals[item.id] = w.core:signal(Facet.UI.shadowData({ blurRadius = { scale = 0, offset = 8 } }))
			end
		end
	end
	local rows = w.core:signal(items)
	local list = virtual_list.build(Facet, w.core, {
		id = "VL",
		rows = rows,
		key = function(item: any)
			return item.id
		end,
		rowHeight = ROW_HEIGHT,
		viewportHeight = VIEWPORT.h,
		overscan = 2,
		cell = function(item: any)
			return Facet.UI.HStack({
				id = "Row",
				gap = 6,
				shadow = shadowSignals[item.id],
				children = {
					Facet.UI.Text({ id = "Name", text = item.label, textSize = 15 }),
					Facet.UI.Text({ id = "Detail", text = item.detail, textSize = 12 }),
				},
			})
		end,
	})
	local screen = Facet.UI.Screen({ id = "S", children = { list.blueprint } })
	w.present(screen)
	list.bindNativeScroll(w.controller)
	local wAny = w :: any
	wAny.listDispose = list.dispose
	return w
end

local function scrollTo(w: any, y: number)
	w.controller.scrollTo("/S/VL", { x = 0, y = y })
	w.pres.refresh()
	w.overflowGuard()
end

local function churn(w: any)
	local content = ROW_COUNT * ROW_HEIGHT
	for _, top in { 0, content, content // 2 } do
		scrollTo(w, top)
		local y = top
		for _ = 1, 30 do
			y = (y + 173) % content
			scrollTo(w, y)
		end
	end
end

describe("W1: no risk at all when a row's declared props never cross nil", function()
	it("recycles hard, and no row ever carries a shadow it did not itself declare as real", function()
		local w = makeWorld(true)
		churn(w)
		expect(w.controller.stats().parked > 0).toBe(true)
		expect(w.controller.stats().recycled > 0).toBe(true)

		local offenders: { string } = {}
		for path, node in w.adapter.liveNodes() do
			local n = tonumber(string.match(path, "%[r(%d+)%]/Row/Row$"))
			local hasShadow = (node.props :: any).shadow ~= nil
			-- every `n % 3 == 0` row declared a REAL shadow from birth and every
			-- other row never declared one at all — so `hasShadow` must agree
			-- with `n % 3 == 0` for every single live row, no exceptions
			if n ~= nil and hasShadow ~= (n % 3 == 0) then
				table.insert(offenders, path)
			end
		end
		table.sort(offenders)
		local message = `rows whose shadow disagrees with their own declaration: {table.concat(offenders, ",")}`
		expect(message).toBe("rows whose shadow disagrees with their own declaration: ")
		local wAny = w :: any
		wAny.listDispose()
	end)
end)
