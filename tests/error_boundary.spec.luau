--!strict
-- Phase 4 error boundaries with critical-screen fallback (design §17 Phase 4;
-- UI-RUNTIME-003): UI.ErrorBoundary quarantines factory errors inside its
-- subtree — at mount AND during later structural rebuilds — and swaps to its
-- fallback view instead of taking down the screen. The presenter's critical-
-- screen path presents a declared fallback screen when a screen's mount or
-- render throws. Outside a boundary the existing hard-error contract is
-- unchanged.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local mountLib = require("../src/mount")
local fake_target = require("../tests/lib/fake_target")

local UI = Facet.UI

describe("error boundaries (§17 Phase 4)", function()
	it("renders its view when healthy; the fallback is not mounted", function()
		local core = Facet.newCore()
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.ErrorBoundary({
						id = "EB",
						view = function()
							return UI.Text({ id = "Happy", text = "ok", textSize = 12 })
						end,
						fallback = function()
							return UI.Text({ id = "Fallback", text = "broken", textSize = 12 })
						end,
					}),
				},
			})
		)
		local dump = root.dump()
		local flat = {}
		local function walk(node: any)
			flat[node.path] = true
			for _, child in node.children or {} do
				walk(child)
			end
		end
		walk(dump.tree)
		expect(flat["/S/EB/view/Happy"]).toBeTruthy()
		expect(flat["/S/EB/fallback/Fallback"]).toBeFalsy()
		root.dispose()
	end)

	it("a throwing view factory at mount swaps to the fallback; siblings survive", function()
		local core = Facet.newCore()
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.Text({ id = "Sibling", text = "alive", textSize = 12 }),
					UI.ErrorBoundary({
						id = "EB",
						view = function()
							error("factory exploded")
						end,
						fallback = function(err: any)
							return UI.Text({ id = "Fallback", text = tostring(err), textSize = 12 })
						end,
					}),
				},
			})
		)
		local flat = {}
		local function walk(node: any)
			flat[node.path] = node
			for _, child in node.children or {} do
				walk(child)
			end
		end
		walk(root.dump().tree)
		expect(flat["/S/Sibling"] ~= nil).toBeTruthy()
		expect(flat["/S/EB/fallback/Fallback"] ~= nil).toBeTruthy()
		root.dispose()
	end)

	it("a structural rebuild that throws INSIDE the boundary trips it at runtime", function()
		local core = Facet.newCore()
		local explode = core:signal(false)
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.ErrorBoundary({
						id = "EB",
						view = function()
							return UI.VStack({
								id = "V",
								children = {
									UI.When({
										id = "W",
										condition = explode,
										thenView = function()
											error("branch exploded")
										end,
									}),
									UI.Text({ id = "Content", text = "fine", textSize = 12 }),
								},
							})
						end,
						fallback = function(err: any)
							return UI.Text({ id = "Fallback", text = tostring(err), textSize = 12 })
						end,
					}),
				},
			})
		)
		-- healthy first
		local function paths(): { [string]: boolean }
			local flat = {}
			local function walk(node: any)
				flat[node.path] = true
				for _, child in node.children or {} do
					walk(child)
				end
			end
			walk(root.dump().tree)
			return flat
		end
		expect(paths()["/S/EB/view/V/Content"]).toBeTruthy()
		explode:set(true) -- the writer must NOT crash
		local after = paths()
		expect(after["/S/EB/fallback/Fallback"]).toBeTruthy()
		expect(after["/S/EB/view/V/Content"]).toBeFalsy()
		-- scheduler alive
		local probe = core:signal(1)
		probe:set(2)
		expect(probe:get()).toBe(2)
		root.dispose()
		explode:dispose()
		probe:dispose()
	end)

	it("boundary trips are registry-clean: dispose returns to baseline", function()
		local core = Facet.newCore()
		local baseline = core:counters()
		local explode = core:signal(false)
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.ErrorBoundary({
						id = "EB",
						view = function()
							return UI.When({
								id = "W",
								condition = explode,
								thenView = function()
									error("boom")
								end,
							})
						end,
						fallback = function()
							return UI.Text({ id = "Fallback", text = "broken", textSize = 12 })
						end,
					}),
				},
			})
		)
		explode:set(true)
		root.dispose()
		explode:dispose()
		local after = core:counters()
		for key, value in baseline :: { [string]: number } do
			expect(after[key]).toBe(value)
		end
	end)

	it("critical screen: a throwing screen presents its declared fallback screen", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local handle = pres.presentCritical(function()
			error("screen construction failed")
		end, {
			fallbackScreen = function(err: any)
				return UI.Screen({
					id = "SafeMode",
					children = {
						UI.Text({ id = "Message", text = tostring(err), textSize = 14 }),
						UI.Button({ id = "Retry", label = "Retry" }),
					},
				})
			end,
		})
		expect(pres.depth()).toBe(1)
		expect(handle.blueprint.id).toBe("SafeMode")
		expect(pres.focus.focused:get()).toBe("/SafeMode/Retry")
		pres.dismiss(handle)
	end)

	--[[ ARCH-1/ARCH-2 (release-candidate review, 2026-08-17). A `ForEach` row
		factory that throws with NO boundary above it used to unwind `apply` from
		the middle of the add phase — after the remove phase had disposed the rows
		that left. `node.children` kept pointing at those disposed rows and no
		`structure` dirty was pushed, so `structuralSync` (which only runs on a
		`structure` entry) left their Instances on screen frozen for the session.
		The three cases below are the whole contract: the survivors' tree is
		consistent AND announced, the throwing key is retried on the next update,
		and the boundary path is untouched. ]]
	local function forEachFixture(core: any, boundary: boolean, throwOn: { [string]: boolean })
		local cards = core:signal({ { id = "a" }, { id = "b" } })
		local rows = UI.ForEach({
			id = "Rows",
			items = cards,
			key = function(c: any)
				return c.id
			end,
			row = function(c: any)
				if throwOn[c.id] then
					error(`row factory throws for {c.id}`, 0)
				end
				return UI.Text({ id = `Row-{c.id}`, text = c.id, textSize = 12 })
			end,
		})
		local child = if boundary
			then UI.ErrorBoundary({
				id = "EB",
				view = function()
					return rows
				end,
				fallback = function()
					return UI.Text({ id = "Fallback", text = "broken", textSize = 12 })
				end,
			})
			else rows
		local root = mountLib.mount(core, UI.Screen({ id = "S", children = { child } }))
		return root, cards
	end

	local function childPaths(node: any): { string }
		local out: { string } = {}
		for _, ch in node.children do
			table.insert(out, ch.path)
		end
		return out
	end

	local function findForEach(node: any): any
		if node.class == "ForEach" then
			return node
		end
		for _, ch in node.children or {} do
			local found = findForEach(ch)
			if found ~= nil then
				return found
			end
		end
		return nil
	end

	it("a throwing row factory outside a boundary leaves the surviving tree consistent (ARCH-1)", function()
		local core = Facet.newCore()
		local throwOn: { [string]: boolean } = {}
		local root, cards = forEachFixture(core, false, throwOn)
		local forEach = findForEach(root.node)
		expect(#childPaths(forEach)).toBe(2)
		expect(root.counters().mounted).toBe(4)
		root.takeDirty()

		throwOn.c = true
		-- containment is unchanged: the writer returns, the core records it
		local ok = pcall(function()
			cards:set({ { id = "a" }, { id = "c" } })
		end)
		expect(ok).toBe(true)

		-- b LEFT and stays gone; c never arrived; nothing disposed is still linked
		expect(childPaths(forEach)).toEqual({ "/S/Rows/[a]/Row-a" })
		expect(root.counters().mounted).toBe(3)
		-- ...and the renderer is TOLD, or the Instances never come off screen
		local dirty = root.takeDirty()
		local structural = 0
		for _, entry in dirty do
			if entry.class == "structure" then
				structural += 1
			end
		end
		expect(structural >= 1).toBe(true)
		expect(string.find(tostring(core:lastError()), "row factory throws for c", 1, true) ~= nil).toBe(true)
		root.dispose()
	end)

	it("the row that threw is retried on the next update (ARCH-1)", function()
		local core = Facet.newCore()
		local throwOn: { [string]: boolean } = {}
		local root, cards = forEachFixture(core, false, throwOn)
		local forEach = findForEach(root.node)
		throwOn.c = true
		pcall(function()
			cards:set({ { id = "a" }, { id = "c" } })
		end)
		throwOn.c = nil
		cards:set({ { id = "a" }, { id = "c" } })
		expect(childPaths(forEach)).toEqual({ "/S/Rows/[a]/Row-a", "/S/Rows/[c]/Row-c" })
		expect(root.counters().mounted).toBe(4)
		root.dispose()
	end)

	it("with a boundary the fallback path is unchanged (ARCH-1)", function()
		local core = Facet.newCore()
		local throwOn: { [string]: boolean } = {}
		local root, cards = forEachFixture(core, true, throwOn)
		throwOn.c = true
		cards:set({ { id = "a" }, { id = "c" } })
		local flat: { [string]: boolean } = {}
		local function walk(node: any)
			flat[node.path] = true
			for _, ch in node.children or {} do
				walk(ch)
			end
		end
		walk(root.dump().tree)
		expect(flat["/S/EB/fallback/Fallback"]).toBeTruthy()
		expect(flat["/S/EB/view/Rows/[a]/Row-a"]).toBeFalsy()
		root.dispose()
	end)

	it("outside a boundary the mount-time hard-error contract is unchanged", function()
		local core = Facet.newCore()
		local ok, err = pcall(
			mountLib.mount,
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.When({
						id = "W",
						condition = core:signal(true),
						thenView = function()
							error("no boundary here")
						end,
					}),
				},
			})
		)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "no boundary here") ~= nil).toBe(true)
	end)
end)
