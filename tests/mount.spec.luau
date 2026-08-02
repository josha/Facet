--!strict
-- P1.1 mounted-graph tests (UI-RUNTIME-001/002, UI-LIFE-002, UI-DIAG-001):
-- factory-once mounting, per-prop dirty classes, structural regions with
-- keyed identity, duplicate-id/key hard errors, churn neutrality, dump
-- determinism.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local serde = require("@lune/serde")

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")

local function settingsSubset(core: any)
	local music = core:signal(false)
	local title = core:signal("Settings")
	local bp = UI.Screen({
		id = "Settings",
		children = {
			UI.Text({ id = "Title", text = title, textSize = 24 }),
			UI.Toggle({ id = "Music", label = "Music", value = music }),
			UI.Button({ id = "Save", label = "Save" }),
		},
	})
	return bp, music, title
end

describe("mount: factory-once and dirty classes", function()
	it("mounts each node exactly once with stable paths", function()
		local core = customFactory.new()
		local bp = settingsSubset(core)
		local root = mountLib.mount(core, bp)
		expect(root.counters().mounted).toBe(4)
		expect(root.counters().factoryRuns).toBe(4)
		expect(root.node.children[1].path).toBe("/Settings/Title")
		root.dispose()
		expect(root.counters().mounted).toBe(0)
	end)

	it("a non-structural prop change dirties ONLY its node with declared classes and reruns no factory", function()
		local core = customFactory.new()
		local bp, music, title = settingsSubset(core)
		local root = mountLib.mount(core, bp)
		root.takeDirty()
		title:set("Options")
		local dirty = root.takeDirty()
		expect(#dirty).toBe(2) -- text -> paint + measure
		expect(dirty[1].path).toBe("/Settings/Title")
		music:set(true)
		local dirty2 = root.takeDirty()
		expect(#dirty2).toBe(2) -- value -> paint + semantics
		expect(dirty2[1].path).toBe("/Settings/Music")
		expect(root.counters().factoryRuns).toBe(4) -- unchanged: no rerun
		expect(root.node.children[1].props.text).toBe("Options")
		root.dispose()
	end)

	it("duplicate explicit sibling ids are a hard error", function()
		local core = customFactory.new()
		local bp = UI.VStack({
			id = "Root",
			children = {
				UI.Box({ id = "Same" }),
				UI.Box({ id = "Same" }),
			},
		})
		local ok, err = pcall(mountLib.mount, core, bp)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "duplicate child id") ~= nil).toBe(true)
	end)
end)

describe("mount: When region", function()
	it("mounts/unmounts the branch scope and dirties only the region", function()
		local core = customFactory.new()
		local showAdvanced = core:signal(false)
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.Text({ id = "Always", text = "hi" }),
				UI.When({
					id = "Advanced",
					condition = showAdvanced,
					thenView = function()
						return UI.Text({ id = "Secret", text = "advanced" })
					end,
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local base = root.counters().mounted
		local whenNode = root.node.children[2]
		expect(#whenNode.children).toBe(0)
		showAdvanced:set(true)
		expect(#whenNode.children).toBe(1)
		expect(whenNode.children[1].path).toBe("/S/Advanced/then/Secret")
		expect(root.counters().mounted).toBe(base + 1)
		local dirty = root.takeDirty()
		expect(dirty[#dirty].class).toBe("structure")
		expect(dirty[#dirty].path).toBe("/S/Advanced")
		showAdvanced:set(false)
		expect(#whenNode.children).toBe(0)
		expect(root.counters().mounted).toBe(base)
		root.dispose()
	end)
end)

describe("mount: ForEach region", function()
	local function cardList(core: any, initial: { { id: string, name: string } })
		local cards = core:signal(initial)
		local bp = UI.ForEach({
			id = "Cards",
			items = cards,
			key = function(card)
				return card.id
			end,
			row = function(card)
				return UI.Text({ id = "Row-" .. card.id, text = card.name })
			end,
		})
		return bp, cards
	end

	it("applies add/remove/move with keyed scopes; moves never remount", function()
		local core = customFactory.new()
		local bp, cards = cardList(core, {
			{ id = "a", name = "Alpha" },
			{ id = "b", name = "Beta" },
			{ id = "c", name = "Gamma" },
		})
		local root = mountLib.mount(core, bp)
		local runsAfterMount = root.counters().factoryRuns
		local firstA = root.node.children[1]
		-- pure move
		cards:set({
			{ id = "c", name = "Gamma" },
			{ id = "a", name = "Alpha" },
			{ id = "b", name = "Beta" },
		})
		expect(root.counters().factoryRuns).toBe(runsAfterMount)
		expect(root.node.children[2]).toBe(firstA) -- same mounted node object
		-- remove b, add d
		cards:set({
			{ id = "a", name = "Alpha" },
			{ id = "c", name = "Gamma" },
			{ id = "d", name = "Delta" },
		})
		expect(root.counters().factoryRuns).toBe(runsAfterMount + 1)
		expect(root.node.itemsByKey.b).toBe(nil)
		expect(#root.node.children).toBe(3)
		root.dispose()
		expect(root.counters().mounted).toBe(0)
	end)

	it("duplicate keys are a hard error", function()
		local core = customFactory.new()
		local bp = cardList(core, {
			{ id = "x", name = "One" },
			{ id = "x", name = "Two" },
		})
		local ok, err = pcall(mountLib.mount, core, bp)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "duplicate key") ~= nil).toBe(true)
	end)
end)

describe("mount: churn and dumps", function()
	it("50 mount/dispose cycles return mount and core registries to baseline", function()
		local core = customFactory.new()
		local coreBaseline = core:counters()
		for _ = 1, 50 do
			local bp, music = settingsSubset(core)
			local root = mountLib.mount(core, bp)
			music:set(true)
			root.takeDirty()
			root.dispose()
			expect(root.counters().mounted).toBe(0)
		end
		local after = core:counters()
		-- signals created by settingsSubset stay (test-owned); observers and
		-- scopes created by mount must return to baseline
		expect(after.observers).toBe(coreBaseline.observers)
		expect(after.scopes).toBe(coreBaseline.scopes)
	end)

	it("dumps are deterministic and carry dirty flags", function()
		local core = customFactory.new()
		local bp, music = settingsSubset(core)
		local root = mountLib.mount(core, bp)
		music:set(true)
		local d1 = serde.encode("json", root.dump(), true)
		local d2 = serde.encode("json", root.dump(), true)
		expect(d1).toBe(d2)
		expect(string.find(d1, "semantics") ~= nil).toBe(true)
		root.dispose()
	end)
end)
