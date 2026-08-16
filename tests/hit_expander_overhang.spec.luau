--!strict
--[[ THE HIT-EXPANDER OVERHANG LIFT — the rule, not the table it was found in.

	A control under the touch floor gets an invisible hit expander at
	`hostZ - 1` (`src/client/screen_target.luau`), and the engine delivers input
	to the TOPMOST interactive object only. A sibling walked later therefore
	outranks the expander, and wherever the expander reaches PAST its host into
	that sibling it advertises a band it cannot deliver. The renderer's z walk
	answers by walking the host's whole branch AFTER the branches its expander
	reaches into (`src/render/renderer.luau`, `hitLiftAfter`).

	MEASURED FIRST, on a real engine, before any of this was written:
	artifacts/hit-expander-overhang/corpus-measurement.md — 48 scenarios, 86 hit
	expanders, 82 overhang relations, ZERO painted-rect overlaps among them, which
	is what makes the paint reorder invisible and lets the rule ship with no
	per-class exception.

	THREE CLAUSES, ONE PER CASE BELOW:

	  · it lifts — the divider outranks the NEIGHBOUR column it reaches into
	    (`table_columns`, the reported defect), and every sub-floor row outranks
	    the row below it (`keyboard_navigation`, a NON-table expander that carried
	    the same defect silently);
	  · it stops at the host — a target the host's own painted rect already
	    overlaps is not "past its host" and is never lifted over. That clause is
	    what keeps the 8px divider ON TOP of the 28px header cell it sits inside,
	    and it is pinned by name in `tests/table_columns.spec.luau` ("the resize
	    grip's hit floor lands on top of its own header button");
	  · it leaves expander-vs-expander alone — two sub-floor controls whose FLOORS
	    overlap each other, and nothing else, keep their declared order. Without
	    that qualifier the rule is circular for exactly the population it governs.

	...and it is stable: the constraint set is read from the BASE order only, so a
	tiled list cannot flip its paint order on every solve.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local UI = require("../src/blueprint")
local fake_target = require("../tests/lib/fake_target")
local tableScenario = require("../examples/gallery/scenarios/table_columns") :: any
local keyboardScenario = require("../examples/gallery/scenarios/keyboard_navigation") :: any

type World = { core: any, env: any, adapter: any, pres: any, built: any }

-- the showcase host's own fixture mount (`examples/gallery/client/init.client.luau`)
local function mount(scenario: any, w: number, h: number): World
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = w, h = h })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)
	local built = scenario.build({
		LuauUI = LuauUI,
		core = core,
		env = env,
		actionSystem = system,
		presenter = pres,
		adapter = adapter,
		record = function() end,
		bindResourceTransport = function()
			return function() end
		end,
	})
	built.handle = pres.present(built.screen, built.present)
	pres.refresh()
	return { core = core, env = env, adapter = adapter, pres = pres, built = built }
end

local function overlaps(a: any, b: any): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- what the engine would let through: the classes the adapter realises as a real
-- input sinker (`INPUT_SINKING` in the renderer), tested against the expander's
-- own rect at the z the adapter derives for it (`hostZ - 1`)
local SINKS: { [string]: boolean } = { Button = true, Toggle = true, TextField = true, Grip = true }
local function thievesOf(adapter: any, hostPath: string): { string }
	local host = adapter.node(hostPath)
	local hit = host.hitRect
	local out: { string } = {}
	for _, path in adapter.paths() do
		local node = adapter.node(path)
		if
			path ~= hostPath
			and node.rect ~= nil
			and SINKS[node.class]
			and node.z > host.z - 1
			and overlaps(hit, node.rect)
			-- ...only where the expander reaches PAST its host: a sibling the host
			-- is drawn on top of keeps the authored order and is not a thief
			and not overlaps(host.rect, node.rect)
		then
			table.insert(out, path)
		end
	end
	return out
end

local TABLE_HEADER = "/TableColumns/TablePane/Entrants/Main/Header"

describe("hit-expander overhang: the table divider's floor is reachable", function()
	it("the divider outranks the NEIGHBOUR column its 44px floor reaches into", function()
		local w = mount(tableScenario, 900, 640)
		local grip = w.adapter.node(`{TABLE_HEADER}/Head-name/Grip`)
		local neighbour = w.adapter.node(`{TABLE_HEADER}/Head-team/Column`)
		-- the floor really does reach into the neighbour: without this the case
		-- below would pass on a table whose columns had drifted apart
		expect(`reaches:{overlaps(grip.hitRect, neighbour.rect)}`).toBe("reaches:true")
		expect(`grip:{grip.rect.w}x{grip.rect.h} hit:{grip.hitRect.w}x{grip.hitRect.h}`).toBe("grip:8x28 hit:44x44")
		-- the expander sits one BELOW its host (hover is wired on the host), so
		-- this is the number that decides whether the band is deliverable
		expect(`expander>neighbour:{grip.z - 1 > neighbour.z}`).toBe("expander>neighbour:true")
		-- ...which is a real reorder of the two header cells, not an accident of
		-- declaration: `Head-name` is declared FIRST and walked last
		expect(`lifted:{w.adapter.node(`{TABLE_HEADER}/Head-name`).z > w.adapter.node(`{TABLE_HEADER}/Head-team`).z}`).toBe(
			"lifted:true"
		)
		w.built.dispose()
	end)

	it("nothing is left that can take the band: the whole 44px belongs to the divider", function()
		local w = mount(tableScenario, 900, 640)
		expect(table.concat(thievesOf(w.adapter, `{TABLE_HEADER}/Head-name/Grip`), " ")).toBe("")
		expect(table.concat(thievesOf(w.adapter, `{TABLE_HEADER}/Head-team/Grip`), " ")).toBe("")
		w.built.dispose()
	end)
end)

describe("hit-expander overhang: a NON-table expander carried the same defect", function()
	it("every sub-floor row outranks the row its floor reaches into", function()
		local w = mount(keyboardScenario, 900, 900)
		local checked = 0
		for i = 1, 11 do
			local row = w.adapter.node(`/KbdNav/Body/List/Row{i}`)
			local below = w.adapter.node(`/KbdNav/Body/List/Row{i + 1}`)
			if row ~= nil and below ~= nil and row.hitRect ~= nil then
				expect(`row{i}reaches:{overlaps(row.hitRect, below.rect)}`).toBe(`row{i}reaches:true`)
				expect(`row{i}above:{row.z - 1 > below.z}`).toBe(`row{i}above:true`)
				checked += 1
			end
		end
		-- a fixture that stopped mounting its list would otherwise pass with an
		-- empty loop
		expect(`checked:{checked}`).toBe("checked:11")
	end)
end)

describe("hit-expander overhang: the qualifier and the stability it buys", function()
	it("two floors that overlap ONLY each other keep their declared order", function()
		-- 20x20 buttons 16px apart: each floor reaches 12px past its own button,
		-- so the two FLOORS overlap while neither floor reaches the other's
		-- button. Under an unqualified rule each would want to outrank the other.
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 200 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.HStack({
					id = "Row",
					gap = 16,
					children = {
						UI.Button({
							id = "A",
							label = "",
							width = { type = "fixed", px = 20 },
							height = { type = "fixed", px = 20 },
						}),
						UI.Button({
							id = "B",
							label = "",
							width = { type = "fixed", px = 20 },
							height = { type = "fixed", px = 20 },
						}),
					},
				}),
			},
		}))
		pres.refresh()
		local a = adapter.node("/S/Row/A")
		local b = adapter.node("/S/Row/B")
		expect(`floorsMeet:{overlaps(a.hitRect, b.hitRect)}`).toBe("floorsMeet:true")
		expect(`floorMissesButton:{overlaps(a.hitRect, b.rect)}`).toBe("floorMissesButton:false")
		expect(`declaredOrder:{a.z < b.z}`).toBe("declaredOrder:true")
	end)

	it("the lift is read from the base order, so a second solve moves nothing", function()
		local w = mount(keyboardScenario, 900, 900)
		local before: { [string]: number } = {}
		for _, path in w.adapter.paths() do
			before[path] = w.adapter.node(path).z
		end
		w.pres.refresh()
		w.pres.refresh()
		local moved: { string } = {}
		for path, z in before do
			local node = w.adapter.node(path)
			if node ~= nil and node.z ~= z then
				table.insert(moved, path)
			end
		end
		expect(table.concat(moved, " ")).toBe("")
	end)
end)
