--!strict
local harness = require("./lib/harness")
--[[
	A NODE REPLACED AT A LIVE PATH IS SWEPT — AND NOT BECAUSE THE COLLECTOR
	HAPPENED TO BE LATE.

	`renderer.luau`'s `ensureTree` decides "a DIFFERENT node is at this path now"
	by comparing the arriving node with the one the path last held. That record
	was a WEAK-VALUED map, so the comparison was only ever true while the old
	node was still reachable: collect it first — which nothing prevents, because
	the branch that built it has already been disposed by then — and the entry is
	gone, the occupant reads nil, and the replacement sweep is skipped IN
	SILENCE. The old subtree's handles then stay mounted under the new occupant,
	which is the "retired branch went on painting beside the new branch's" defect
	the sweep exists to prevent, reintroduced as a race.

	Lune cannot force a collection (`collectgarbage` accepts only "count" here),
	so the race itself is not reproducible in-process. What IS provable, and is
	what actually fixes it, is that the decision no longer reads a weak table at
	all: identity is a number from a never-reused counter, held strongly for as
	long as the path holds a handle and dropped with it. The structural case
	below says so against the source; the behavioural case says the sweep still
	does its job.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")

local Facet = require("../src") :: any
local Compose = require("../src/vendor/compose/core")
local fake_target = require("./lib/fake_target")

local UI = harness.UI

describe("the replaced-occupant decision does not ride the collector", function()
	it("keeps no weak record of the node a path last held", function()
		local source = fs.readFile("src/render/renderer.luau")
		local declaration = string.match(source, "\n\tlocal handleNodes[^\n]*\n")
		expect(declaration ~= nil).toBe(true)
		--[[ The whole fix in one line: the map a live-path replacement is decided
			against is strong. A weak one reintroduces the race whatever the rest of
			the file does, which is why this reads the declaration rather than the
			behaviour. ]]
		expect(string.find(declaration :: string, "__mode", 1, true)).toBeNil()
		-- ...and it is released with the handle, so a strong map cannot grow forever
		expect(string.find(source, "handleNodes[path] = nil", 1, true) ~= nil).toBe(true)
	end)

	it("sweeps the old subtree when a branch puts a different node at the same path", function()
		local core = harness.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		local adapter = fake_target.new()
		local flag = Compose.cell(true)
		local function slot(which: string)
			return UI.VStack({
				id = "Slot",
				children = { UI.Text({ id = which, text = which }) },
			})
		end
		local root = harness.mount(core, function()
			return UI.Screen({
				id = "S",
				children = {
					Compose.show(flag, function()
						return slot("Alpha")
					end, function()
						return slot("Beta")
					end),
				},
			})
		end)
		local controller = require("../src/render/renderer").attach(core, root, env, adapter, {
			rootPolicy = "edgeToEdge",
		})
		controller.initialRender()
		expect(adapter.node("/S/Slot/Alpha") ~= nil).toBe(true)
		expect(adapter.node("/S/Slot/Beta")).toBeNil()
		flag:set(false)
		controller.refresh()
		-- the replacement is there...
		expect(adapter.node("/S/Slot/Beta") ~= nil).toBe(true)
		-- ...and the retired branch's child is GONE, not painting beside it
		expect(adapter.node("/S/Slot/Alpha")).toBeNil()
		controller.dispose()
		root.dispose()
		expect(adapter.liveCount()).toBe(0)
	end)
end)
