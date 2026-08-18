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
