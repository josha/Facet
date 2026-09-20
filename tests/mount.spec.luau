--!strict
local harness = require("./lib/harness")
-- Mounted-graph tests (UI-RUNTIME-001/002, UI-LIFE-002, UI-DIAG-001):
-- factory-once mounting, per-prop dirty classes, structural regions with
-- keyed identity, duplicate-name/key hard errors, churn neutrality.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local Compose = (require("../src") :: any).Compose

local customFactory = harness.coreFactory
local UI = harness.UI
local mountLib = harness

local function settingsSubset(core: any)
	local music = Compose.cell(false)
	local title = Compose.cell("Settings")
	-- A component: the mount owns every node it builds.
	local function bp()
		return UI.Screen({
			id = "Settings",
			children = {
				UI.Text({ id = "Title", text = title, textSize = 24 }),
				UI.Toggle({ id = "Music", label = "Music", value = music }),
				UI.Button({ id = "Save", label = "Save" }),
			},
		})
	end
	return bp, music, title
end

describe("mount: factory-once and dirty classes", function()
	it("property getters can clear optional paint but cannot omit required values", function()
		local core = customFactory.new()
		local tint = Compose.cell({ role = "accent", blend = 1 })
		local root = mountLib.mount(
			core,
			UI.Text({
				id = "Label",
				text = "Label",
				tint = function(use)
					return use(tint)
				end,
			})
		)
		expect(root.node.props.tint.role).toBe("accent")
		tint:set(nil)
		expect(root.node.props.tint).toBeNil()
		tint:set({ role = "content", blend = 1 })
		expect(root.node.props.tint.role).toBe("content")
		root.dispose()
		local ok, err = pcall(function()
			mountLib.mount(
				core,
				UI.Button({
					label = function()
						return nil
					end,
				})
			)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "Button.label", 1, true) ~= nil).toBe(true)
	end)
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
		local ok, err = pcall(mountLib.mount, core, function()
			return UI.VStack({
				id = "Root",
				children = {
					UI.Box({ id = "Same" }),
					UI.Box({ id = "Same" }),
				},
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "duplicate child name 'Same'", 1, true) ~= nil).toBe(true)
	end)
end)

describe("mount: When region", function()
	it("mounts/unmounts the branch and dirties only the region", function()
		local core = customFactory.new()
		local showAdvanced = Compose.cell(false)
		local root = mountLib.mount(core, function()
			return UI.Screen({
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
		end)
		local base = root.counters().mounted
		local whenNode = root.node.children[2]
		expect(#whenNode.children).toBe(0)
		showAdvanced:set(true)
		-- the branch region, and the branch's node inside it
		expect(#whenNode.children).toBe(1)
		expect(whenNode.children[1].path).toBe("/S/Advanced/then")
		expect(whenNode.children[1].children[1].path).toBe("/S/Advanced/then/Secret")
		expect(root.counters().mounted).toBe(base + 2)
		local dirty = root.takeDirty()
		expect(dirty[#dirty].class).toBe("structure")
		expect(dirty[#dirty].path).toBe("/S/Advanced")
		showAdvanced:set(false)
		expect(#whenNode.children).toBe(0)
		expect(root.counters().mounted).toBe(base)
		root.dispose()
	end)
end)

-- A branch owns what its `thenView` registers: each entry has a fresh owner,
-- released when the branch closes.
describe("mount: a When branch owns its resources", function()
	local function branchFixture(initial: boolean)
		local core = customFactory.new()
		local on = Compose.cell(initial)
		local entries = 0
		local released = 0
		local root = mountLib.mount(core, function()
			return UI.Screen({
				id = "S",
				children = {
					UI.Text({ id = "Always", text = "hi" }),
					UI.When({
						id = "Panel",
						condition = on,
						thenView = function()
							entries += 1
							Compose.cleanup(function()
								released += 1
							end)
							return UI.Text({ id = "Body", text = "body" })
						end,
					}),
				},
			})
		end)
		return core, on, root, function()
			return entries
		end, function()
			return released
		end
	end

	it("thenView runs when the branch opens, not before", function()
		local _core, on, root, entries = branchFixture(false)
		expect(entries()).toBe(0)
		on:set(true)
		expect(entries()).toBe(1)
		root.dispose()
	end)

	it("the initial-true mount builds the branch once", function()
		local _core, _on, root, entries = branchFixture(true)
		expect(entries()).toBe(1)
		root.dispose()
	end)

	it("a resource owned by the branch is released when the branch closes", function()
		local core, on, root, _entries, released = branchFixture(false)
		on:set(true)
		expect(released()).toBe(0)
		on:set(false)
		expect(released()).toBe(1) -- released WITH the branch, not at root disposal
		root.dispose()
		expect(released()).toBe(1) -- and not a second time
		expect(core.lastError()).toBeNil()
	end)

	it("a flip back gets a FRESH owner: nothing from the previous entry survives", function()
		local core, on, root, entries, released = branchFixture(false)
		on:set(true)
		on:set(false)
		on:set(true)
		expect(entries()).toBe(2)
		expect(released()).toBe(1) -- entry 1's resource is gone; entry 2's is live
		root.dispose()
		expect(released()).toBe(2)
		expect(core.lastError()).toBeNil()
	end)

	it("fifty open/close cycles leave no cleanup behind", function()
		local core, on, root, entries, released = branchFixture(false)
		local mounted = root.counters().mounted
		for _ = 1, 50 do
			on:set(true)
			on:set(false)
		end
		expect(entries()).toBe(50)
		expect(released()).toBe(50)
		expect(root.counters().mounted).toBe(mounted)
		root.dispose()
		expect(core.lastError()).toBeNil()
	end)
end)

describe("mount: ForEach region", function()
	local function cardList(core: any, initial: { { id: string, name: string } })
		local cards = Compose.cell(initial)
		local function bp()
			return UI.ForEach({
				id = "Cards",
				items = cards,
				key = function(card)
					return card.id
				end,
				row = function(card)
					return UI.Text({ id = "Row-" .. card.id, text = card.name })
				end,
			})
		end
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
		local ids = {}
		for index, child in root.node.children do
			ids[index] = child.id
		end
		expect(table.concat(ids, ",")).toBe("Row-a,Row-c,Row-d")
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
		expect(string.find(tostring(err), "structure/duplicate-key", 1, true) ~= nil).toBe(true)
	end)
end)

describe("mount: churn", function()
	it("50 mount/dispose cycles return mount and core registries to baseline", function()
		local core = customFactory.new()
		local coreBaseline = core.owner.size()
		for _ = 1, 50 do
			local bp, music = settingsSubset(core)
			local root = mountLib.mount(core, bp)
			music:set(true)
			root.takeDirty()
			root.dispose()
			expect(root.counters().mounted).toBe(0)
		end
		local after = core.owner.size()
		-- signals created by settingsSubset stay (test-owned); observers and
		-- scopes created by mount must return to baseline
		expect(after).toBe(coreBaseline)
		expect(after).toBe(coreBaseline)
	end)
end)

describe("mount: retained dirty history", function()
	it("returns ordered suffix snapshots without draining or including earlier entries", function()
		local core = customFactory.new()
		local bp, music, title = settingsSubset(core)
		local root = mountLib.mount(core, bp)
		root.takeDirty()
		local start = root.dirtySeq()
		title:set("Options")
		local middle = root.dirtySeq()
		local first = root.dirtySince(start)
		expect(#first).toBe(2)
		music:set(true)
		local suffix = root.dirtySince(middle)
		expect(#suffix).toBe(2)
		expect(suffix[1].path).toBe("/Settings/Music")
		expect(suffix[1].class).toBe("paint")
		expect(suffix[2].class).toBe("semantics")
		expect(#first).toBe(2)
		expect(first[1].path).toBe("/Settings/Title")
		local all = root.takeDirty()
		expect(#all).toBe(4)
		expect(all[1]).toBe(first[1])
		expect(all[3]).toBe(suffix[1])
		expect(#root.takeDirty()).toBe(0)
		expect(#first).toBe(2)
		root.dispose()
	end)

	it("distinguishes unavailable drained history from an empty current suffix", function()
		local core = customFactory.new()
		local bp, music, title = settingsSubset(core)
		local root = mountLib.mount(core, bp)
		root.takeDirty()
		local start = root.dirtySeq()
		title:set("Options")
		root.takeDirty()
		local drained = root.dirtySeq()
		expect(root.dirtySince(start)).toBeNil()
		expect(#root.dirtySince(drained)).toBe(0)
		music:set(true)
		expect(root.dirtySince(start)).toBeNil()
		expect(#root.dirtySince(drained)).toBe(2)
		expect(#root.dirtySince(root.dirtySeq())).toBe(0)
		expect(root.dirtySince(root.dirtySeq() + 1)).toBeNil()
		root.dispose()
	end)
end)
