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

--[[ THE BRANCH SCOPE (react-lua-comparison.md §5 rank 2). `ForEach` hands each
	row `(item, itemScope)`; `When.thenView` was handed NOTHING, even though
	`mountWhen` builds a `branchScope` on the line above the factory call and
	disposes it on branch exit. The consequence was not theoretical: a panel that
	wants a MotionValue, a timer or an async handle had to hoist it to the
	enclosing scope, where it OUTLIVES the panel — the exact leak shape the item
	scope exists to prevent.

	AND THE FLIP-FLOP IS THE CASE THAT DECIDES THE SHAPE. Every entry gets a
	FRESH scope (`scope:child(branchPath)`), so a resource the panel owned last
	time cannot survive into this time. That is also the answer to "should an
	`elseView` share this scope" — it must not, and the framework does not have
	an `elseView` to share it with; see the ruling in src/mount.luau. ]]
describe("mount: When hands its branch the branch scope", function()
	-- a When whose factory records every scope it is handed and owns a signal on it
	local function branchFixture(initial: boolean)
		local core = customFactory.new()
		local on = core:signal(initial)
		local handed: { any } = {}
		local released = 0
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.Text({ id = "Always", text = "hi" }),
				UI.When({
					id = "Panel",
					condition = on,
					thenView = function(branchScope)
						table.insert(handed, branchScope)
						-- the whole point: an owned, releasable, branch-lifetime resource
						branchScope:own(function()
							released += 1
						end)
						return UI.Text({ id = "Body", text = "body" })
					end,
				}),
			},
		})
		return core, on, mountLib.mount(core, bp), handed, function()
			return released
		end
	end

	it("thenView is handed the BRANCH scope — labelled with the branch path", function()
		local _core, on, root, handed = branchFixture(false)
		expect(#handed).toBe(0)
		on:set(true)
		expect(#handed).toBe(1)
		-- the label is what makes this the BRANCH's scope rather than the screen's:
		-- an enclosing scope handed over by mistake would read "/S" or nil
		expect(handed[1].label).toBe("/S/Panel/then")
		expect(handed[1]:isDisposed()).toBe(false)
		root.dispose()
	end)

	it("the initial-true mount hands the same scope the later flip does", function()
		-- mountWhen has TWO factory call sites (the observer and the initial read);
		-- a fix applied to one of them passes the case above and fails here
		local _core, _on, root, handed = branchFixture(true)
		expect(#handed).toBe(1)
		expect(handed[1].label).toBe("/S/Panel/then")
		root.dispose()
	end)

	it("a resource owned on the handed scope is released when the branch closes", function()
		local core, on, root, handed, released = branchFixture(false)
		local baseline = core:counters().scopes
		on:set(true)
		expect(released()).toBe(0)
		on:set(false)
		expect(released()).toBe(1) -- released WITH the branch, not at root disposal
		expect(handed[1]:isDisposed()).toBe(true)
		expect(core:counters().scopes).toBe(baseline)
		root.dispose()
		expect(released()).toBe(1) -- and not a second time
		expect(core:lastError()).toBeNil()
	end)

	it("a flip back gets a FRESH scope: nothing from the previous entry survives", function()
		--[[ This is the elseView argument as a test. If two entries (or two
			branches) shared one scope, a resource from the closed panel would still
			be alive and owned when the panel re-opened — the leak in a new costume,
			and harder to see than the hoisted-signal one because the counters look
			balanced. ]]
		local core, on, root, handed, released = branchFixture(false)
		local baseline = core:counters().scopes
		on:set(true)
		on:set(false)
		on:set(true)
		expect(#handed).toBe(2)
		expect(handed[2]).never().toBe(handed[1])
		expect(handed[1]:isDisposed()).toBe(true)
		expect(handed[2]:isDisposed()).toBe(false)
		expect(released()).toBe(1) -- entry 1's resource is gone; entry 2's is live
		-- exactly ONE branch scope is live, not two: the first entry's was not
		-- carried forward, it was replaced
		expect(core:counters().scopes).toBe(baseline + 1)
		root.dispose()
		expect(released()).toBe(2)
		expect(core:lastError()).toBeNil()
	end)

	it("fifty open/close cycles leave no scope and no cleanup behind", function()
		local core, on, root, handed, released = branchFixture(false)
		local baseline = core:counters().scopes
		for _ = 1, 50 do
			on:set(true)
			on:set(false)
		end
		expect(#handed).toBe(50)
		expect(released()).toBe(50)
		expect(core:counters().scopes).toBe(baseline)
		root.dispose()
		expect(core:lastError()).toBeNil()
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
