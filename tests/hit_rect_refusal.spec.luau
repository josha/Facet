--!strict
--[[
	THE HIT-RECT WALK REFUSES WHEN IT CANNOT WRITE ANYTHING (Plan D, D6b).

	WHAT IT COST TO RUN IT ANYWAY. `commit_walks`' `hitRects` is the only one of the
	eight commit walks that visits the MOVED set, so on a structural step it walks the
	whole shifted subtree — and on every FacetBench arena workload it walks it to write
	nothing: `d4_hitrects` censused `war_room_inventory L` at **nodes=7,505
	inputSinks=0 authorSinks=0 frameworkChrome=0 hitFloorNodes=0**, and `battle_hud L`
	and `nameplates L` the same. Because it is the walk that visits the moved set, it is
	also the walk that builds C4's whole descend cache (`lastCommitScans` 7,346,
	`lastCommitProbes` 7,335) — **2.85 of 19.7 ms of Facet's own `reorder` (14.5 %)**
	and 1.05 of 9.1 on `removeItem-items`, the largest single term Task D4 found and
	the reason it was booked here rather than fixed there: the argument it needs is
	about `lastHitRects`' departure, not about a per-visit constant.

	THE GATE IS A CLAIM ABOUT THE CONTRACT, NOT ABOUT A WORKLOAD, and the first case
	below is that claim mechanised. The walk's only write is behind
	`layout_node.effectiveHitFloor(node.class, metrics)` — a function of the CLASS
	alone — so a surface whose classes can never carry a floor can never be written to
	by this walk. `render/renderer`'s `INPUT_SINKING` is that set of classes, and
	`inputSinks` is a strict superset of the paths holding them (it also files any node
	with `active = true`, whatever its class). The second term, `lastHitRects`, is what
	this surface has already ASKED the adapter for: empty means nothing stands, so the
	retraction half of the diff cannot fire either.

	AND A DEPARTURE DOES NOT NEED THIS WALK, which is the objection the fix had to
	answer before it could be built. A node that leaves the tree is never visited by
	any walk again, so if this walk were the only thing that forgot its expander, a
	refusal could strand one on screen. It is not: `render/renderer`'s `dropPath`
	clears `lastHitRects[path]` beside `lastVisible`, `solverHidden` and the rest of
	the per-path caches, and has since the hidden-candidate fix. Case 4 drives exactly
	that — a Button that unmounts — and reads the refusal coming back.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")

local ROWS = 400

type World = {
	core: any,
	controller: any,
	adapter: any,
	rows: { any },
	showButton: any,
}

--[[ THE PRODUCTION SHAPE THE COUNTER IS A FUNCTION OF: a list of rows, each row a
	container with two leaves, which is the arena's own row and the shape whose
	structural shift the walk used to follow node for node. `showButton` mounts ONE
	sub-floor Button through a `When`, so the same fixture serves the sink-free arm,
	the sink arm and the departure. ]]
local function world(opts: { button: boolean }): World
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 480, h = 720 })
	local rows: { any } = {}
	local children: { any } = {}
	for i = 1, ROWS do
		rows[i] = core:signal(`row {i}`)
		children[i] = UI.VStack({
			id = `R{i}`,
			children = {
				UI.Text({ id = "L", text = rows[i], textSize = 12 }),
				UI.Box({ id = "B", width = { type = "fixed", px = 20 }, height = { type = "fixed", px = 6 } }),
			},
		})
	end
	local showButton = core:signal(opts.button)
	local bp = UI.Screen({
		id = "S",
		children = {
			UI.When({
				id = "W",
				condition = showButton,
				thenView = function()
					-- SUB-FLOOR ON BOTH AXES, so the walk has something to write: the
					-- contract's 44 against a 20x10 box
					return UI.Button({
						id = "Tiny",
						label = "x",
						width = { type = "fixed", px = 20 },
						height = { type = "fixed", px = 10 },
					})
				end,
			}),
			UI.VStack({ id = "L", padding = 0, gap = 0, children = children }),
		},
	})
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter)
	controller.initialRender()
	return { core = core, controller = controller, adapter = adapter, rows = rows, showButton = showButton }
end

-- the walk's own visit count for the LAST commit, which is the number this task moves
local function hitVisits(w: World): number
	local by = w.controller.stats().lastCommitVisitsByWalk
	return (by.hitRects :: number?) or -1
end

describe("the hit-rect walk: the premise the refusal rests on", function()
	it("the classes that declare a hit floor are EXACTLY the classes the renderer files as sinks", function()
		--[[ A SOURCE SCAN, because this is the one thing that could make the gate
			wrong and nothing else in the suite would notice: a fifth class given a
			`minHitSize` in the contract but not added to `INPUT_SINKING` would carry a
			floor on a surface whose `inputSinks` stays empty, and the walk that would
			have written its expander would be refused. Both sets are read off the
			source rather than from a list kept here, so neither can drift under this
			claim. ]]
		local renderSrc = fs.readFile("src/render/renderer.luau")
		local declared = string.match(renderSrc, "local INPUT_SINKING: { %[string%]: boolean } = {(.-)}")
		assert(declared ~= nil, "no INPUT_SINKING declaration to read")
		local sinking: { string } = {}
		for name in string.gmatch(declared :: string, "(%w+) = true") do
			table.insert(sinking, name)
		end
		table.sort(sinking)

		local contractSrc = fs.readFile("src/class_contract.luau")
		-- each class block runs from its own `\n\tName = {` to the next one; a block
		-- that names `minHitSize` declares a floor
		local floors: { string } = {}
		local starts: { { name: string, at: number } } = {}
		for at, name in string.gmatch(contractSrc, "()\n\t(%w+) = {") do
			table.insert(starts, { name = name, at = at :: number })
		end
		for i, entry in starts do
			local stop = if starts[i + 1] ~= nil then starts[i + 1].at else #contractSrc
			if string.find(string.sub(contractSrc, entry.at, stop), "minHitSize = ", 1, true) ~= nil then
				table.insert(floors, entry.name)
			end
		end
		table.sort(floors)
		expect(`floors={table.concat(floors, ",")}`).toBe("floors=Button,Grip,TextField,Toggle")
		expect(`sinking={table.concat(sinking, ",")}`).toBe(`sinking={table.concat(floors, ",")}`)
	end)
end)

describe("the hit-rect walk: a surface with nothing to write does not walk", function()
	it("a 400-row list with no sink refuses the walk outright, on a structural step", function()
		local w = world({ button = false })
		--[[ THE STRUCTURAL STEP IS THE POINT. A row's text write moves one leaf; a
			row REMOVED shifts every row below it, and this walk followed all of them.
			ARM A (the gate absent, read off the run at `0cb8bc0a`) reads
			`hitRects=1203` on the mount and `hitRects=1203` again on the shift — one
			visit per node of the whole list — against `hitRects=0` here. ]]
		expect(`mount={hitVisits(w)}`).toBe("mount=0")
		for i = 1, ROWS do
			w.rows[i]:set(`shifted {i}`)
		end
		w.controller.refresh()
		expect(`after a whole-list write={hitVisits(w)}`).toBe("after a whole-list write=0")
		-- ...and nothing was asked for, which is what makes the refusal exact rather
		-- than merely cheap: the walk had no write to make on any of those nodes
		expect(`hit rect on a row={tostring(w.adapter.hitRectOf("/S/L/R1"))}`).toBe("hit rect on a row=nil")
		w.controller.dispose()
	end)

	it("...and ONE sub-floor Button on the same tree keeps the walk, and its expander", function()
		--[[ THE OTHER DIRECTION, and it is the case that keeps the pins this task
			moved elsewhere honest: the walk is refused for want of a WRITE, never
			because a structural step is cheap. The same 400 rows, one Button, and the
			walk visits the tree exactly as it always did. ]]
		local w = world({ button = true })
		local mounted = hitVisits(w)
		expect(`walked={tostring(mounted > ROWS)}`).toBe("walked=true")
		local hit = w.adapter.hitRectOf("/S/W/then/Tiny") :: any
		expect(`expander={if hit ~= nil then `{hit.w}x{hit.h}` else "-"}`).toBe("expander=44x44")
		w.controller.dispose()
	end)

	it("...and a Box the author made `active` keeps it too, though it writes nothing", function()
		--[[ THE SUPERSET DIRECTION. `inputSinks` is not the floor set: it also files
			any node with `active = true`, whatever its class, and the gate reads THAT
			table. So a backdrop that sinks presses without declaring a floor keeps the
			walk running and the walk writes nothing — strictly the safe side of the
			same question, and stated here so nobody narrows the gate to the four
			classes and calls it equivalent. ]]
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 480, h = 720 })
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.Box({ id = "Back", active = true }),
					UI.Text({ id = "T", text = "x", textSize = 12 }),
				},
			})
		)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter)
		controller.initialRender()
		local by = controller.stats().lastCommitVisitsByWalk
		expect(`walked={tostring((by.hitRects :: number) > 0)} asked={tostring(adapter.hitRectOf("/S/Back"))}`).toBe(
			"walked=true asked=nil"
		)
		controller.dispose()
	end)
end)

describe("the hit-rect walk: a sink that LEAVES is forgotten by the sweep, not by the walk", function()
	it("the Button unmounts, its expander goes with it, and the refusal comes back", function()
		--[[ THE CORRECTNESS ARGUMENT THE GATE NEEDED, driven. If this walk were the
			only thing that forgot `lastHitRects`, refusing it on a surface whose last
			sink has just left would leave that entry standing forever — the table would
			never be empty again, so the refusal would never fire, and (worse) the
			departed path would keep a live activation surface. `render/renderer`'s
			`dropPath` is what actually forgets it, so the departure empties the table
			and the NEXT commit refuses. ]]
		local w = world({ button = true })
		expect(`before={tostring(w.adapter.hitRectOf("/S/W/then/Tiny") ~= nil)}`).toBe("before=true")
		w.showButton:set(false)
		w.controller.refresh()
		expect(`gone={tostring(w.adapter.hitRectOf("/S/W/then/Tiny"))}`).toBe("gone=nil")
		--[[ ...AND THE COMMIT AFTER THE DEPARTURE IS THE ONE THAT REFUSES. The
			departing commit itself still walks: `lastHitRects` is emptied by the sweep
			inside it, and the gate is read at the top. A refusal one commit later is
			the honest shape and pinning it is what proves the table really was
			emptied. ]]
		w.rows[1]:set("moved")
		w.controller.refresh()
		expect(`after the departure={hitVisits(w)}`).toBe("after the departure=0")

		-- ...and the sink COMING BACK re-asks: the refusal is a state, never a latch
		w.showButton:set(true)
		w.controller.refresh()
		local hit = w.adapter.hitRectOf("/S/W/then/Tiny") :: any
		expect(`back={if hit ~= nil then `{hit.w}x{hit.h}` else "-"} walked={tostring(hitVisits(w) > 0)}`).toBe(
			"back=44x44 walked=true"
		)
		w.controller.dispose()
	end)
end)
