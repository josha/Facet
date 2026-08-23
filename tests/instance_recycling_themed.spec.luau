--!strict
--[[
	THEMED INSTANCE RECYCLING (optimization-log L-28).

	L-27 measured the prize and the refusal: under `fantasy_ornate` every control
	fails `isBare` by construction (5-11 chrome children per control), so recycling
	delivered -32% on flat and a small LOSS under the one theme where `mount` is
	5.44 ms/call. Park must release the chrome's path-keyed registrations and adopt
	must re-key them — and an adoption across a DIFFERENT decoration hint must be
	refused, because the hint arrives through `create` and is never re-planned by a
	later setter (that invariant is pinned elsewhere; re-planning on adopt would be
	a second planning path AND would rebuild the chrome, forfeiting exactly the
	construction cost recycling exists to avoid).

	`screen_target.luau` cannot load headless (engine globals at load), so the live
	adapter is pinned the way render_target_contract pins it: its source is the
	contract. The BEHAVIOUR is proven live in Studio (perf lab, theme=fantasy_ornate,
	visual scroll + counters + the measurement recipe in L-28).
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")

local Facet = require("../src") :: any
local virtual_list = require("../src/controls/virtual_list")
local chrome_slots = require("../src/tokens/chrome_slots")
local fake_target = require("../tests/lib/fake_target")

local ROW_HEIGHT = 56
local VIEWPORT = { w = 360, h = 640 }
-- the per-edge floor every content policy applies (ADR-0046 / ADR-0040 §B-24):
-- the box a Screen actually receives is the viewport less this on each side, and
-- this default-policy surface reports no platform inset at all
local CONTENT_GUTTER = (require("../src/themes/snapshot").neutral().space :: any).gutter

local function makeItems(n: number)
	local out = {}
	for i = 1, n do
		table.insert(out, { id = `r{i}`, label = `Row {i}` })
	end
	return out
end

local function assertClean(handle: any, where: string)
	local findings = handle.controller.diagnostics()
	if #findings > 0 then
		local first = findings[1]
		error(`layout finding at {where}: {tostring(first.node)}: {tostring(first.issue)}`, 2)
	end
end

-- A world whose every row carries a HINTED node. The hint table is built fresh by
-- `cell` on every window slide — which is exactly what a real list does — so a pool
-- bucket keyed by the hint table's ADDRESS can never match across a slide, and a
-- bucket keyed by the hint's CONTENT always can.
local function hintedWorld(recycle: boolean)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = VIEWPORT.w, h = VIEWPORT.h })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local rows = core:signal(makeItems(400))
	local list = virtual_list.build(Facet, core, {
		id = "VL",
		rows = rows,
		key = function(item: any)
			return item.id
		end,
		rowHeight = ROW_HEIGHT,
		viewportHeight = VIEWPORT.h - CONTENT_GUTTER * 2,
		overscan = 2,
		cell = function(item: any)
			return Facet.UI.HStack({
				id = "Row",
				gap = 6,
				children = {
					chrome_slots.attachHint(
						Facet.UI.Box({
							id = "Deco",
							width = { type = "fixed", px = 24 },
							height = { type = "fixed", px = 24 },
						}),
						{ slot = "control" }
					),
					Facet.UI.Text({ id = "Name", text = item.label, textSize = 15 }),
					Facet.UI.Box({ id = "Pad", width = { type = "fill", weight = 1 } }),
				},
			})
		end,
	})
	local screen = Facet.UI.Screen({ id = "S", children = { list.blueprint } })
	local handle = pres.present(screen, { recycleInstances = recycle })
	pres.refresh()
	list.bindNativeScroll(handle.controller)
	assertClean(handle, "mount")
	return {
		core = core,
		pres = pres,
		list = list,
		adapter = adapter,
		handle = handle,
		dispose = function()
			list.dispose()
		end,
	}
end

local function valueOf(v: any): string
	if type(v) ~= "table" then
		return tostring(v)
	end
	local parts = {}
	for k, inner in v do
		table.insert(parts, `{tostring(k)}={if type(inner) == "table" then "{...}" else tostring(inner)}`)
	end
	table.sort(parts)
	return `\{{table.concat(parts, ",")}\}`
end

local function snapshot(adapter: any): string
	local rows = {}
	for path, node in adapter.liveNodes() do
		local props = {}
		for k, v in node.props or {} do
			table.insert(props, `{k}={valueOf(v)}`)
		end
		table.sort(props)
		local r = node.rect
		table.insert(
			rows,
			`{path}|{node.class}|{if r then `{r.x},{r.y},{r.w},{r.h}` else "-"}|{table.concat(props, ",")}`
		)
	end
	table.sort(rows)
	return table.concat(rows, "\n")
end

local function scrollTo(w: any, y: number)
	w.handle.controller.scrollTo("/S/VL", { x = 0, y = y })
	w.pres.refresh()
	assertClean(w.handle, `scroll to {y}`)
end

describe("themed recycling: hinted nodes reach the pool and come back correct", function()
	it("a HINT-carrying node is recycled across a window slide (bucket by content, not address)", function()
		local w = hintedWorld(true)
		local decoAdopts = 0
		for i = 1, 20 do
			scrollTo(w, i * 61)
			for _, op in w.adapter.takeOps() do
				if string.match(op, "^adopt .*/Deco ") ~= nil then
					decoAdopts += 1
				end
			end
		end
		-- the discriminating count: the row's BARE nodes recycle either way, so
		-- `stats.recycled > 0` would pass on a build that still refuses every
		-- hinted node. Only an adoption OF the hinted path proves the bucket
		-- matched across two separately built hint tables.
		expect(decoAdopts > 0).toBe(true)
		w.dispose()
	end)

	it("DIFFERENTIAL: hinted rows land byte-identical with recycling on and off", function()
		local a, b = hintedWorld(true), hintedWorld(false)
		for i = 1, 20 do
			scrollTo(a, i * 61)
			scrollTo(b, i * 61)
			expect(snapshot(a.adapter)).toBe(snapshot(b.adapter))
		end
		scrollTo(a, 0)
		scrollTo(b, 0)
		expect(snapshot(a.adapter)).toBe(snapshot(b.adapter))
		a.dispose()
		b.dispose()
	end)
end)

describe("adopt refuses a decoration-hint mismatch (the fake mirrors the live rule)", function()
	-- The rule: a parked node adopted under a DIFFERENT hint would keep the wrong
	-- chrome plan, because the hint arrives through `create` and no later setter
	-- re-plans it. Refusal — not re-planning — is the ruling: a re-plan is a
	-- rebuild, which costs what a fresh create costs, so there is nothing to win.
	it("refuses when the hint content differs", function()
		local adapter = fake_target.new() :: any
		local root = adapter.createRoot("S")
		local h = adapter.create(root, "/S/a", "Button", { slot = "control", icon = "gear" })
		expect(adapter.park(h)).toBe(true)
		expect(adapter.adopt(h, "/S/b", "Button", { slot = "selection" })).toBe(false)
	end)

	it("refuses across hinted and bare, in both directions", function()
		local adapter = fake_target.new() :: any
		local root = adapter.createRoot("S")
		local hinted = adapter.create(root, "/S/a", "Button", { slot = "control" })
		expect(adapter.park(hinted)).toBe(true)
		expect(adapter.adopt(hinted, "/S/b", "Button", nil)).toBe(false)
		local bare = adapter.create(root, "/S/c", "Button", nil)
		expect(adapter.park(bare)).toBe(true)
		expect(adapter.adopt(bare, "/S/d", "Button", { slot = "control" })).toBe(false)
	end)

	it("accepts a CONTENT-equal hint carried by a different table", function()
		-- two window slides build two hint tables; equal content must adopt, or
		-- the whole themed prize is refused at the adapter after the renderer's
		-- bucket already matched
		local adapter = fake_target.new() :: any
		local root = adapter.createRoot("S")
		local h = adapter.create(root, "/S/a", "Button", { slot = "control", icon = "gear", iconSize = "small" })
		expect(adapter.park(h)).toBe(true)
		expect(adapter.adopt(h, "/S/b", "Button", { slot = "control", icon = "gear", iconSize = "small" })).toBe(true)
	end)
end)

describe("the LIVE adapter's themed park/adopt (its source is the contract)", function()
	local live = fs.readFile("src/client/screen_target.luau")
	local chromeSrc = fs.readFile("src/client/screen_chrome.luau")

	it("adopt takes the incoming hint — the mismatch rule needs it", function()
		expect(
			string.find(
				live,
				"function adapter.adopt(handle: any, newPath: string, newClass: string, hint: any",
				1,
				true
			) ~= nil
		).toBe(true)
	end)

	it("park no longer refuses a node for merely having child instances", function()
		-- the old rule `#handle.instance:GetChildren() > 0` is what refused every
		-- themed control by construction (L-27: 249 refusals against 96 parks)
		expect(string.find(live, "GetChildren() > 0", 1, true)).toBe(nil)
	end)

	it("ONE ruling enumerates the chrome's path-keyed children, used by park AND adopt", function()
		-- the recurring defect shape here is a ruling that lives at one call site
		-- (applyFullBleed, the chrome z-ladder). The enumeration lives in
		-- screen_chrome as `chromePathChildEntries`, and screen_target consumes it
		-- from the chrome API at both seams.
		expect(string.find(chromeSrc, "local function chromePathChildEntries", 1, true) ~= nil).toBe(true)
		local uses = 0
		for _ in string.gmatch(live, "chromePathChildEntries") do
			uses += 1
		end
		expect(uses >= 2).toBe(true)
	end)

	it("the enumeration covers every chrome family: decoration, lift, icon, layers+masks, bar, toggle", function()
		local body = string.match(chromeSrc, "local function chromePathChildEntries.-\n\tend")
		expect(body ~= nil).toBe(true)
		for _, needle in
			{
				"DECORATION_NAME", -- the single-decoration path
				"TEXT_LIFT_NAME", -- the lifted label
				"ICON_NAME", -- the managed semantic icon
				"chromeStack", -- the layer ladder...
				"entry.mask", -- ...including a MASKED layer's CanvasGroup, whose
				-- ImageLabel is parented to the mask and NOT to the host — so
				-- iterating direct children could never find this set
				"BAR_WINDOW_NAME",
				"BAR_FILL_NAME",
				"barOrnaments",
				"TOGGLE_PARTS", -- Track and Knob
			}
		do
			expect(string.find(body :: string, needle, 1, true) ~= nil).toBe(true)
		end
	end)

	it("discardParked tears chrome down census-correctly, not just Destroy()", function()
		local body = string.match(live, "function adapter%.discardParked.-\n\tend")
		expect(body ~= nil).toBe(true)
		-- a parked node's chrome stayed COUNTED while parked (that is what keeps
		-- `decoratedNodes` honest); discarding it must make every census fall, or
		-- a census that cannot fall cannot show a leak
		for _, needle in { "destroyChromeStack", "destroyChromeText", "destroyBarFill", "noteDestroyed" } do
			expect(string.find(body :: string, needle, 1, true) ~= nil).toBe(true)
		end
	end)

	it("adopt refuses chrome facts that moved while the node was parked", function()
		-- a parked handle has left `handlesByPath`, so neither `setThemePackage`'s
		-- every-handle resync nor the fallback refresh can reach it; adopting it
		-- after either moved would resurrect stale art with nothing left to fix
		-- it. The gate is ONE integer (chrome_slots `chromeEpoch`, bumped on a
		-- package swap and on an asset-ledger movement), stamped at park and
		-- compared at adopt — chosen over reconciling on adopt, which would
		-- charge every adoption to heal a case that is rare by construction.
		expect(string.find(live, "parkedChromeEpoch", 1, true) ~= nil).toBe(true)
		expect(string.find(live, "chromeState.epoch()", 1, true) ~= nil).toBe(true)
	end)

	it("the epoch moves on a package swap AND on an asset-ledger movement", function()
		local state = chrome_slots.newState(nil)
		local e0 = state.epoch()
		-- a ledger movement (an asset condemned) is a chrome-plan fact
		expect(state.setAssetLoaded("art/frame", false)).toBe(true)
		expect(state.epoch() > e0).toBe(true)
		-- ...and a repeated report that changes nothing must NOT move it: an
		-- epoch that creeps on no-ops would refuse every adoption for free
		local e1 = state.epoch()
		expect(state.setAssetLoaded("art/frame", false)).toBe(false)
		expect(state.epoch()).toBe(e1)
	end)
end)
