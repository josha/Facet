--!strict
--[[
	VIEW LIFECYCLE HOOKS and the SPACE-RESERVING HIDE
	(docs/plans/parity-round3.md, item D — the completeness audit's
	ranked gaps #12 and #16).

	Two shared box props, both of which the audit found Facet had no spelling
	for at all:

	  · `onAppear(path)` / `onDisappear(path)` — the `onAppear(perform:)` pair
	    and `onDisappear(perform:)`. `grep -rn "onAppear" src/` returned ZERO
	    hits before this change, even though mount scopes have owned the
	    lifetime for a year: the tracking existed, the author-facing hook did
	    not.
	  · `hidden` — the space-reserving hide: "invisible and can't receive or respond
	    to interactions. However, they do remain in the view hierarchy and
	    affect layout." NEITHER of Facet's two existing answers is that.
	    `UI.When` REMOVES the node (the siblings close up), and the engine's own
	    `Visible = false` frees the layout slot inside a `UIListLayout` — which
	    is why this framework, which arranges absolutely and ships no
	    `UIListLayout` at all, is the one place the engine's behaviour does not
	    apply and a real `.hidden()` is one prop.

	WHAT EACH BLOCK WOULD CATCH, because "a callback fired" proves very little:

	  · "fires after the first solve"   -> the ordering decision. A hook that
	    fired between structuralSync and solveAndApply gets a node with NO rect,
	    which is the useless half of the capability ("measure the card you just
	    revealed"). Asserted from INSIDE the callback, which is the only place
	    the ordering is observable.
	  · "the node is already gone"      -> the mirror decision for disappear. A
	    hook that fired while the handle still existed would let a consumer
	    resurrect a dying node, and the guarantee "the path is not mounted"
	    would be a comment rather than a fact.
	  · "exactly once"                  -> the failure mode a lifetime hook has:
	    re-firing on every re-solve, or on a theme commit, or on a viewport
	    change. Each of those runs solveAndApply.
	  · "a parked node still disappears"-> instance RECYCLING. A retiring node
	    whose Instance is pooled for reuse took a different branch of the
	    removal sweep, and a hook wired to `adapter.remove` alone would silently
	    stop firing the moment recycling was switched on.
	  · "teardown fires every hook"     -> "stop the engine sound when the panel
	    closes" is the whole point, and a surface dismissal is the most common
	    way a panel closes.
	  · "hidden keeps the box"          -> the ONE thing that distinguishes this
	    prop from `UI.When`. If a sibling moves, this is just a slower `When`.
	  · "hidden takes the subtree"      -> a hidden container whose children
	    still painted would be the defect, not the feature.
	  · "hidden leaves focus order"     -> the standard wording, and the half a
	    paint-only implementation silently omits: an invisible control that
	    still takes Tab and still activates.
	  · "hidden retracts the hit floor" -> RS-A16-D1's defect class exactly: a
	    sub-floor control inside a hidden subtree keeps an EXPANDED hit rect at
	    the ScreenGui root, i.e. a live activation surface for something nobody
	    can see.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local UI = require("../src/blueprint")
local schema = require("../src/blueprint_schema")
local customFactory = require("../src/core/custom")
local environment = require("../src/env/environment")
local mountLib = require("../src/mount")
local rendererLib = require("../src/render/renderer")
local fake_target = require("./lib/fake_target")

local function fixed(px: number): any
	return { type = "fixed", px = px }
end

local function world(screen: any, w: number?, h: number?): (any, any, any, any)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = w or 400, h = h or 400 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local root = mountLib.mount(core, screen)
	local adapter = fake_target.new()
	local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return adapter, controller, core, env
end

local function failure(fn: () -> any): string
	local ok, err = pcall(fn)
	if ok then
		return "NO ERROR"
	end
	return tostring(err)
end

local function contains(haystack: string, needle: string): boolean
	return string.find(haystack, needle, 1, true) ~= nil
end

-- ===========================================================================
-- 1. THE DECLARATIONS
-- ===========================================================================
describe("lifecycle hooks: the schema declaration", function()
	it("onAppear/onDisappear/hidden are SHARED box props — every rendered class has them", function()
		for _, class in { "Box", "Text", "VStack", "HStack", "ZStack", "Button", "Image", "ScrollView" } do
			local props = (schema.forClass(class) :: any).props
			for _, prop in { "onAppear", "onDisappear", "hidden" } do
				expect(`{class}.{prop}: {props[prop] ~= nil}`).toBe(`{class}.{prop}: true`)
				expect(`{class}.{prop} shared: {props[prop].shared}`).toBe(`{class}.{prop} shared: true`)
			end
		end
	end)

	it("the hooks are NOT reactive — a lifetime is not a value that changes", function()
		local props = (schema.forClass("Box") :: any).props
		expect(props.onAppear.reactive).toBe(false)
		expect(props.onDisappear.reactive).toBe(false)
		-- ...but `hidden` IS: the useful form is "reserve the slot until the
		-- value arrives", and the standard answer for the conditional case —
		-- an `if` statement — REMOVES the node from layout, which is what
		-- Facet's `UI.When` already does.
		expect(props.hidden.reactive).toBe(true)
		-- `arrange`, not `paint`. The solver already publishes a per-rect `hidden`
		-- verdict (a losing `ViewThatFits` candidate), and this prop merges into
		-- that SAME set — so it inherits the paint walk, the hit-rect retraction,
		-- `hiddenRoots`, and the structure-epoch bump that makes the focus map
		-- notice. A paint-only channel would have reached none of those.
		expect(`{#props.hidden.dirty}:{props.hidden.dirty[1]}`).toBe("1:arrange")
	end)

	it("a non-function hook and a non-boolean hidden are construction errors", function()
		expect(contains(
			failure(function()
				return UI.Box({ id = "B", onAppear = "yes" } :: any)
			end),
			"onAppear"
		)).toBe(true)
		expect(contains(
			failure(function()
				return UI.Box({ id = "B", onDisappear = 3 } :: any)
			end),
			"onDisappear"
		)).toBe(true)
		expect(contains(
			failure(function()
				return UI.Box({ id = "B", hidden = "yes" } :: any)
			end),
			"hidden"
		)).toBe(true)
	end)
end)

-- ===========================================================================
-- 2. onAppear
-- ===========================================================================
describe("onAppear", function()
	it("fires once, with the node's path, for a node present at the first render", function()
		local seen: { string } = {}
		world(UI.Screen({
			id = "S",
			children = {
				UI.Box({
					id = "A",
					width = fixed(50) :: any,
					height = fixed(50) :: any,
					onAppear = function(path: string)
						table.insert(seen, path)
					end,
				}),
			},
		}))
		expect(table.concat(seen, ",")).toBe("/S/A")
	end)

	it("fires AFTER the first layout solve — the callback can read its own rect", function()
		-- THE ORDERING DECISION, asserted where it is observable. The standard
		-- contract is that "the action closure completes before the first
		-- rendered frame appears"; Facet draws nothing until the refresh
		-- returns, so firing after the solve is still pre-first-frame AND hands
		-- the callback a solved box instead of a nil.
		local rectInside: string = "NEVER CALLED"
		local ctrlRef: any = nil
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.Box({
					id = "A",
					width = fixed(120) :: any,
					height = fixed(30) :: any,
					onAppear = function(path: string)
						local r = ctrlRef.rectOf(path)
						rectInside = if r == nil then "NO RECT" else `{r.w}x{r.h}`
					end,
				}),
			},
		})
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local root = mountLib.mount(core, screen)
		ctrlRef = rendererLib.attach(core, root, env, fake_target.new(), { rootPolicy = "edgeToEdge" })
		ctrlRef.initialRender()
		expect(rectInside).toBe("120x30")
	end)

	it("does NOT fire again on a re-solve that changes no structure", function()
		local count = 0
		local _, controller, _, env = world(UI.Screen({
			id = "S",
			children = {
				UI.Box({
					id = "A",
					width = fixed(50) :: any,
					height = fixed(50) :: any,
					onAppear = function()
						count += 1
					end,
				}),
			},
		}))
		env:set("viewportRect", { x = 0, y = 0, w = 500, h = 500 })
		controller.refresh()
		env:set("viewportRect", { x = 0, y = 0, w = 320, h = 640 })
		controller.refresh()
		expect(count).toBe(1)
	end)

	it("fires for a node that arrives later, and again after it leaves and returns", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local shown = core:signal(false)
		local log: { string } = {}
		local controllerRef: any = nil
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.When({
					id = "W",
					condition = shown,
					thenView = function()
						return UI.Box({
							id = "L",
							width = fixed(20) :: any,
							height = fixed(20) :: any,
							onAppear = function(path: string)
								-- the ordering guard for `refresh` as well as for the
								-- first render: a drain placed before the solve hands
								-- this hook a node with no rect at all
								local r = controllerRef.rectOf(path)
								table.insert(log, if r == nil then "appear(NO RECT)" else `appear({r.w}x{r.h})`)
							end,
							onDisappear = function()
								table.insert(log, "disappear")
							end,
						})
					end,
				}),
			},
		})
		local root = mountLib.mount(core, screen)
		local controller = rendererLib.attach(core, root, env, fake_target.new(), { rootPolicy = "edgeToEdge" })
		controllerRef = controller
		controller.initialRender()
		expect(table.concat(log, ",")).toBe("")
		shown:set(true)
		controller.refresh()
		expect(table.concat(log, ",")).toBe("appear(20x20)")
		shown:set(false)
		controller.refresh()
		expect(table.concat(log, ",")).toBe("appear(20x20),disappear")
		shown:set(true)
		controller.refresh()
		expect(table.concat(log, ",")).toBe("appear(20x20),disappear,appear(20x20)")
	end)
end)

-- ===========================================================================
-- 3. onDisappear
-- ===========================================================================
describe("onDisappear", function()
	local function whenWorld(recycle: boolean?): (any, any, any, { string }, any)
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local shown = core:signal(true)
		local log: { string } = {}
		local ctrl: any = nil
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.When({
					id = "W",
					condition = shown,
					thenView = function()
						return UI.Box({
							id = "L",
							width = fixed(20) :: any,
							height = fixed(20) :: any,
							onDisappear = function(path: string)
								table.insert(log, `{path} rect=${tostring(ctrl.rectOf(path))}`)
							end,
						})
					end,
				}),
			},
		})
		local root = mountLib.mount(core, screen)
		local adapter = fake_target.new()
		ctrl = rendererLib.attach(core, root, env, adapter, {
			rootPolicy = "edgeToEdge",
			-- recycling is ON by default; the non-parking cases switch it off so
			-- the two removal branches are each exercised on purpose
			recycleInstances = recycle == true,
		})
		ctrl.initialRender()
		return adapter, ctrl, shown, log, core
	end

	it("fires AFTER the handle is released: the path is no longer mounted", function()
		local _, controller, shown, log = whenWorld()
		shown:set(false)
		controller.refresh()
		expect(#log).toBe(1)
		-- the whole guarantee in one string: the hook is handed a path whose
		-- rect the controller no longer knows
		expect(log[1]).toBe("/S/W/then/L rect=$nil")
	end)

	it("fires exactly once even when the surface is torn down right after", function()
		local _, controller, shown, log = whenWorld()
		shown:set(false)
		controller.refresh()
		controller.dispose()
		expect(#log).toBe(1)
	end)

	it("fires for a node whose Instance was PARKED for recycling, not destroyed", function()
		-- a hook wired to `adapter.remove` alone silently stops firing here
		local adapter, controller, shown, log = whenWorld(true)
		shown:set(false)
		controller.refresh()
		expect(#log).toBe(1)
		expect(controller.stats().parked > 0).toBe(true)
		expect(adapter ~= nil).toBe(true)
	end)

	it("surface teardown fires every still-mounted hook, so a cleanup is never dropped", function()
		local log: { string } = {}
		local _, controller = world(UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "V",
					onDisappear = function(path: string)
						table.insert(log, path)
					end,
					children = {
						UI.Box({
							id = "A",
							width = fixed(10) :: any,
							height = fixed(10) :: any,
							onDisappear = function(path: string)
								table.insert(log, path)
							end,
						}),
					},
				}),
			},
		}))
		expect(#log).toBe(0)
		controller.dispose()
		table.sort(log)
		expect(table.concat(log, ",")).toBe("/S/V,/S/V/A")
		-- ...and a second dispose is idempotent, like every other teardown here
		controller.dispose()
		expect(#log).toBe(2)
	end)
end)

-- ===========================================================================
-- 4. hidden
-- ===========================================================================
describe("hidden — the space-reserving hide", function()
	local function twoBoxes(hiddenValue: any): (any, any)
		return world(UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "V",
					gap = 0,
					children = {
						UI.Box({ id = "a", width = fixed(40) :: any, height = fixed(30) :: any, hidden = hiddenValue }),
						UI.Box({ id = "b", width = fixed(40) :: any, height = fixed(30) :: any }),
					},
				}),
			},
		}))
	end

	it("keeps its layout box: the sibling below does NOT move up", function()
		local visible = twoBoxes(nil)
		local hidden = twoBoxes(true)
		expect(`{visible.node("/S/V/b").rect.y}`).toBe("30")
		expect(`{hidden.node("/S/V/b").rect.y}`).toBe("30")
		-- ...and the hidden node still HAS its box; it is only unpainted
		expect(`{hidden.node("/S/V/a").rect.h}`).toBe("30")
	end)

	it("...which is the whole difference from `UI.When`, whose sibling DOES move up", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local shown = core:signal(false)
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "V",
					gap = 0,
					children = {
						UI.When({
							id = "W",
							condition = shown,
							thenView = function()
								return UI.Box({ id = "a", width = fixed(40) :: any, height = fixed(30) :: any })
							end,
						}),
						UI.Box({ id = "b", width = fixed(40) :: any, height = fixed(30) :: any }),
					},
				}),
			},
		})
		local root = mountLib.mount(core, screen)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		expect(`{adapter.node("/S/V/b").rect.y}`).toBe("0")
		shown:set(true)
		controller.refresh()
		expect(`{adapter.node("/S/V/b").rect.y}`).toBe("30")
	end)

	it("is not painted, and neither is its subtree", function()
		local adapter = world(UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "V",
					hidden = true,
					children = {
						UI.Box({ id = "a", width = fixed(10) :: any, height = fixed(10) :: any }),
						UI.Text({ id = "t", text = "deep" }),
					},
				}),
			},
		}))
		expect(adapter.visibleOf("/S/V")).toBe(false)
		expect(adapter.visibleOf("/S/V/a")).toBe(false)
		expect(adapter.visibleOf("/S/V/t")).toBe(false)
	end)

	it("flips live off a signal, with no remount", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local ghost = core:signal(true)
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.Box({ id = "a", width = fixed(40) :: any, height = fixed(30) :: any, hidden = ghost }),
			},
		})
		local root = mountLib.mount(core, screen)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local creates = controller.stats().creates
		expect(adapter.visibleOf("/S/a")).toBe(false)
		ghost:set(false)
		controller.refresh()
		expect(adapter.visibleOf("/S/a")).toBe(true)
		ghost:set(true)
		controller.refresh()
		expect(adapter.visibleOf("/S/a")).toBe(false)
		-- no remount: the same Instance carried all three states
		expect(controller.stats().creates).toBe(creates)
	end)

	it("does not survive its own node's removal: a remount is born visible", function()
		-- paths are REUSED across a structural remount, so a hide left behind in
		-- the renderer's set would make a FRESH node — one whose `hidden` is now
		-- false — never paint. Exactly the class the `lastVisible` / `lastCompact`
		-- clears in the removal sweep exist for, and invisible from a single mount.
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local branch = core:signal(true)
		local ghost = core:signal(true)
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.When({
					id = "W",
					condition = branch,
					thenView = function()
						return UI.Box({
							id = "L",
							width = fixed(20) :: any,
							height = fixed(20) :: any,
							hidden = ghost,
						})
					end,
				}),
			},
		})
		local root = mountLib.mount(core, screen)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		expect(adapter.visibleOf("/S/W/then/L")).toBe(false)
		-- the whole branch leaves...
		branch:set(false)
		controller.refresh()
		-- ...and comes back at the SAME path, now asking to be visible
		ghost:set(false)
		branch:set(true)
		controller.refresh()
		expect(adapter.visibleOf("/S/W/then/L")).toBe(true)
	end)

	it("leaves focus order — 'can't receive or respond to interactions'", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local ghost = core:signal(false)
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "V",
					hidden = ghost,
					children = { UI.Button({ id = "go", label = "Go" }) },
				}),
			},
		})
		local root = mountLib.mount(core, screen)
		local controller = rendererLib.attach(core, root, env, fake_target.new(), { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		expect(controller.hiddenRoots()["/S/V"]).toBe(nil)
		local epoch = controller.structureEpoch()
		ghost:set(true)
		controller.refresh()
		expect(controller.hiddenRoots()["/S/V"]).toBe(true)
		-- the focus map is cached on the epoch; a hide that did not bump it
		-- would leave navigation landing on an invisible button
		expect(controller.structureEpoch() > epoch).toBe(true)
	end)

	it("takes no tap — the sentence is two halves and this is the second", function()
		-- the hit expander (below) is only the SUB-FLOOR case. A full-size button
		-- inside a hidden subtree keeps a full-size box on purpose, so nothing about
		-- its geometry stops the engine delivering an Activated to it.
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local ghost = core:signal(false)
		local taps = 0
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "V",
					hidden = ghost,
					children = {
						UI.Button({ id = "go", label = "Go", width = fixed(120) :: any, height = fixed(44) :: any }),
					},
				}),
			},
		})
		local root = mountLib.mount(core, screen)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, {
			rootPolicy = "edgeToEdge",
			onNodeTap = function()
				taps += 1
			end,
		})
		controller.initialRender()
		adapter.tap("/S/V/go")
		expect(taps).toBe(1)
		ghost:set(true)
		controller.refresh()
		adapter.tap("/S/V/go")
		expect(taps).toBe(1)
		-- ...and it comes back, because a hide is a state and not a demolition
		ghost:set(false)
		controller.refresh()
		adapter.tap("/S/V/go")
		expect(taps).toBe(2)
	end)

	it("...and so does a losing ViewThatFits candidate, which is the SAME verdict", function()
		--[[ FOUND BY A LIVE GAME SUITE, 2026-08-13, and it is the wider half of the
			finding. The tap gate above reads `solverHidden` — the MERGED verdict —
			so it covers the solver's own hidden nodes as well as authored ones. That
			turned out to be a behaviour change: Rascal Rally's sponsor results spec
			was driving `adapter.tap` into a CTA inside a LOSING `ViewThatFits`
			candidate (measured: rect 170x0, its candidate root in `hiddenRoots`,
			while the sibling column candidate was the one on screen), and the
			framework was dispatching it.

			No player could ever produce that tap — the node is `Visible = false`
			with zero painted height — so this is a synthetic drive reaching content
			nobody can see, the class the round-2 orchestration notes name ("a test
			can be satisfied by a hidden copy"). The framework's own recorded intent
			was already this rule: RS-A16-D1 retracts the hit expander from hidden
			nodes precisely so there is no "live activation surface for a control the
			player cannot see". It was a consequence of geometry there, and it is a
			rule here. ]]
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 200, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local taps: { string } = {}
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.ViewThatFits({
					id = "Fit",
					children = {
						-- 400px of buttons cannot fit a 200px screen: this candidate loses
						UI.HStack({
							id = "Wide",
							gap = 0,
							children = {
								UI.Button({ id = "a", label = "A", width = fixed(200) :: any }),
								UI.Button({ id = "b", label = "B", width = fixed(200) :: any }),
							},
						}),
						UI.Button({ id = "narrow", label = "A", width = fixed(120) :: any }),
					},
				}),
			},
		})
		local root = mountLib.mount(core, screen)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, {
			rootPolicy = "edgeToEdge",
			onNodeTap = function(path: string)
				table.insert(taps, path)
			end,
		})
		controller.initialRender()
		-- the loser is still MOUNTED, with its props intact — that is what makes a
		-- re-choose free, and what makes a path assertion against it pass
		expect(controller.hiddenRoots()["/S/Fit/Wide"]).toBe(true)
		expect(adapter.node("/S/Fit/Wide/a") ~= nil).toBe(true)
		adapter.tap("/S/Fit/Wide/a")
		expect(table.concat(taps, ",")).toBe("")
		-- ...while the candidate that WON takes its tap exactly as before
		adapter.tap("/S/Fit/narrow")
		expect(table.concat(taps, ",")).toBe("/S/Fit/narrow")
	end)

	it("retracts the sub-floor hit expander it would otherwise leave live", function()
		-- RS-A16-D1's class: a control under the theme's minimum target size
		-- gets an EXPANDED hit rect. Inside a hidden subtree that is an
		-- activation surface for something nobody can see.
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local ghost = core:signal(false)
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "V",
					hidden = ghost,
					children = {
						UI.Button({ id = "tiny", label = "x", width = fixed(8) :: any, height = fixed(8) :: any }),
					},
				}),
			},
		})
		local root = mountLib.mount(core, screen)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		expect(adapter.hitRectOf("/S/V/tiny") ~= nil).toBe(true)
		ghost:set(true)
		controller.refresh()
		expect(adapter.hitRectOf("/S/V/tiny")).toBe(nil)
	end)
end)
