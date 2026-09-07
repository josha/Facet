--!strict
--[[ INHERITED `tint` AND INHERITED DISABLED SUBTREES (stabilization pass, stream C;
	design note `docs/superpowers/specs/2026-09-07-inherited-tint-disabled.md`).

	Two properties that used to live only on leaves now live on the containers too,
	and a container's value reaches its whole subtree:

	  * `enabled = false` on any container disables everything under it. Disabled is
	    a CONJUNCTION down the tree — a descendant that declares `false` can never be
	    re-enabled by an ancestor, and an ancestor that says `false` cannot be talked
	    out of it by a descendant that says `true`.
	  * `tint` on a container is the tint its subtree paints with. NEAREST
	    DECLARATION WINS: the node's own tint beats an inherited one, and a nested
	    container's tint replaces the outer one for its own subtree.

	Input is driven through the REAL paths (adapter.tap / system.deviceKey), never by
	calling a callback, because the whole point of the disabled cascade is that it
	blocks every one of them.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local rendererLib = require("../src/render/renderer")
local presenterLib = require("../src/present/presenter")
local actionsLib = require("../src/input/actions")
local classContract = require("../src/class_contract")
local sheet_model = require("../src/tokens/sheet_model")
local chrome_slots = require("../src/tokens/chrome_slots")
local default_style = require("../src/tokens/default_style")
local light_style = require("../src/tokens/default_light_style")
local fake_target = require("../tests/lib/fake_target")

local function fixed(px: number)
	return { type = "fixed", px = px }
end

local function present(screen: any)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local adapter = fake_target.new()
	local system = actionsLib.newSystem(core)
	local pres = presenterLib.new(core, env, adapter, system)
	local handle = pres.present(screen)
	pres.refresh()
	return core, env, adapter, system, pres, handle
end

local function renderOnly(screen: any)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local root = mountLib.mount(core, screen)
	local adapter = fake_target.new()
	local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return core, adapter, controller, root
end

local function nodeAt(root: any, path: string): any
	local function walk(node: any): any
		if node.path == path then
			return node
		end
		for _, child in node.children or {} do
			local found = walk(child)
			if found ~= nil then
				return found
			end
		end
		return nil
	end
	return walk(root.node)
end

local ACCENT = { role = "accent", blend = 1 }
local DANGER = { role = "danger", blend = 1 }

-- ===== 1. authoring ========================================================

describe("C: a container accepts `enabled` and `tint`", function()
	it("a VStack takes `enabled`", function()
		local bp = UI.VStack({ id = "V", enabled = false, children = {} })
		expect(bp.props.enabled).toBe(false)
	end)

	it("a VStack takes `tint`", function()
		local bp = UI.VStack({ id = "V", tint = ACCENT, children = {} })
		expect((bp.props.tint :: any).role).toBe("accent")
	end)

	it("every layout container that carries the shared container props carries both", function()
		local schema = require("../src/blueprint_schema")
		for _, class in { "Screen", "VStack", "HStack", "ZStack", "ScrollView", "Anchor", "Grid", "AdaptiveStack" } do
			local props = (schema.forClass(class) :: any).props
			expect(props.enabled ~= nil).toBe(true)
			expect(props.tint ~= nil).toBe(true)
		end
	end)

	it("an illegal tint on a container is refused with the same sentence a leaf gets", function()
		local ok, err = pcall(function()
			return UI.VStack({ id = "V", tint = { role = "nope", blend = 1 }, children = {} })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "nope", 1, true) ~= nil).toBe(true)
	end)
end)

-- ===== 2. precedence =======================================================

describe("C2: disabled is a conjunction down the tree", function()
	it("a disabled container disables a Button nested two levels below it", function()
		local _, _, _, root = renderOnly(UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "Panel",
					enabled = false,
					children = {
						UI.HStack({
							id = "Row",
							children = { UI.Button({ id = "B", label = "x", height = fixed(44) }) },
						}),
					},
				}),
			},
		}))
		expect(classContract.isDisabled(nodeAt(root, "/S/Panel/Row/B"))).toBe(true)
		expect(classContract.isDisabled(nodeAt(root, "/S/Panel/Row"))).toBe(true)
		expect(classContract.isDisabled(nodeAt(root, "/S"))).toBe(false)
	end)

	it("an ancestor cannot re-enable a descendant that declares enabled = false", function()
		local _, _, _, root = renderOnly(UI.Screen({
			id = "S",
			enabled = true,
			children = {
				UI.VStack({
					id = "Panel",
					enabled = true,
					children = { UI.Button({ id = "B", label = "x", enabled = false, height = fixed(44) }) },
				}),
			},
		}))
		expect(classContract.isDisabled(nodeAt(root, "/S/Panel/B"))).toBe(true)
	end)

	it("a descendant cannot re-enable itself under a disabled ancestor", function()
		local _, _, _, root = renderOnly(UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "Panel",
					enabled = false,
					children = { UI.Button({ id = "B", label = "x", enabled = true, height = fixed(44) }) },
				}),
			},
		}))
		expect(classContract.isDisabled(nodeAt(root, "/S/Panel/B"))).toBe(true)
	end)

	it("a sibling subtree is untouched", function()
		local _, _, _, root = renderOnly(UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "Off",
					enabled = false,
					children = { UI.Button({ id = "A", label = "a", height = fixed(44) }) },
				}),
				UI.VStack({
					id = "On",
					children = { UI.Button({ id = "B", label = "b", height = fixed(44) }) },
				}),
			},
		}))
		expect(classContract.isDisabled(nodeAt(root, "/S/Off/A"))).toBe(true)
		expect(classContract.isDisabled(nodeAt(root, "/S/On/B"))).toBe(false)
	end)
end)

describe("C2: tint is a nearest-declaration cascade", function()
	local function tintOf(root: any, path: string): any
		local node = nodeAt(root, path)
		return if node.props.tint ~= nil then node.props.tint else node.inheritedTint
	end

	it("a container's tint reaches a Text two levels below it", function()
		local _, adapter, _, root = renderOnly(UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "Team",
					tint = ACCENT,
					children = {
						UI.HStack({ id = "Row", children = { UI.Text({ id = "T", text = "hi" }) } }),
					},
				}),
			},
		}))
		expect((tintOf(root, "/S/Team/Row/T") :: any).role).toBe("accent")
		-- ...and it reaches the ADAPTER as an ordinary tint write
		expect((adapter.node("/S/Team/Row/T").props.tint :: any).role).toBe("accent")
	end)

	it("a node's own tint overrides the inherited one", function()
		local _, _, _, root = renderOnly(UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "Team",
					tint = ACCENT,
					children = { UI.Text({ id = "T", text = "hi", tint = DANGER }) },
				}),
			},
		}))
		expect((tintOf(root, "/S/Team/T") :: any).role).toBe("danger")
	end)

	it("the NEAREST container wins over a farther one", function()
		local _, _, _, root = renderOnly(UI.Screen({
			id = "S",
			tint = ACCENT,
			children = {
				UI.VStack({
					id = "Inner",
					tint = DANGER,
					children = { UI.Text({ id = "T", text = "hi" }) },
				}),
				UI.Text({ id = "Outer", text = "hi" }),
			},
		}))
		expect((tintOf(root, "/S/Inner/T") :: any).role).toBe("danger")
		expect((tintOf(root, "/S/Outer") :: any).role).toBe("accent")
	end)

	it("the cascade does not enter a control's interior", function()
		local _, adapter, _, root = renderOnly(UI.Screen({
			id = "S",
			tint = ACCENT,
			children = {
				UI.Button({
					id = "B",
					label = "x",
					height = fixed(44),
					children = { UI.Text({ id = "Caption", text = "x" }) },
				}),
			},
		}))
		expect(tintOf(root, "/S/B/Caption")).toBe(nil)
		expect(adapter.node("/S/B/Caption").props.tint).toBe(nil)
	end)

	it("a container carrying a tint emits no tint of its own", function()
		local _, adapter = renderOnly(UI.Screen({
			id = "S",
			children = {
				UI.VStack({ id = "Team", tint = ACCENT, children = { UI.Text({ id = "T", text = "hi" }) } }),
			},
		}))
		expect(adapter.node("/S/Team").props.tint).toBe(nil)
	end)
end)

-- ===== 3. reactivity =======================================================

describe("C: an ancestor signal flips the subtree with no remount", function()
	it("disabling and re-enabling a container moves every descendant, and mounts nothing", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local on = core:signal(true)
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.VStack({
						id = "Panel",
						enabled = on,
						children = { UI.Button({ id = "B", label = "x", height = fixed(44) }) },
					}),
				},
			})
		)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local mountedBefore = root.counters().mounted
		local runsBefore = root.counters().factoryRuns

		expect(classContract.isDisabled(nodeAt(root, "/S/Panel/B"))).toBe(false)
		on:set(false)
		controller.refresh()
		expect(classContract.isDisabled(nodeAt(root, "/S/Panel/B"))).toBe(true)
		expect(adapter.node("/S/Panel/B").props.enabled).toBe(false)

		on:set(true)
		controller.refresh()
		expect(classContract.isDisabled(nodeAt(root, "/S/Panel/B"))).toBe(false)
		expect(adapter.node("/S/Panel/B").props.enabled).toBe(true)

		-- re-solve, never rebuild
		expect(root.counters().mounted).toBe(mountedBefore)
		expect(root.counters().factoryRuns).toBe(runsBefore)
	end)

	it("a bound container tint repaints every inheriting descendant", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local hue = core:signal(ACCENT)
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.VStack({
						id = "Team",
						tint = hue,
						children = {
							UI.Text({ id = "T", text = "hi" }),
							UI.Text({ id = "Own", text = "hi", tint = DANGER }),
						},
					}),
				},
			})
		)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		expect((adapter.node("/S/Team/T").props.tint :: any).role).toBe("accent")

		hue:set(DANGER)
		controller.refresh()
		expect((adapter.node("/S/Team/T").props.tint :: any).role).toBe("danger")
		-- the node that declared its own tint never followed the ancestor
		expect((adapter.node("/S/Team/Own").props.tint :: any).role).toBe("danger")
		hue:set(ACCENT)
		controller.refresh()
		expect((adapter.node("/S/Team/T").props.tint :: any).role).toBe("accent")
		expect((adapter.node("/S/Team/Own").props.tint :: any).role).toBe("danger")
	end)

	it("a branch mounted later by UI.When inherits the CURRENT value", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local on = core:signal(false)
		local shown = core:signal(false)
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.VStack({
						id = "Panel",
						enabled = on,
						children = {
							UI.When({
								id = "W",
								condition = shown,
								thenView = function()
									return UI.Button({ id = "B", label = "x", height = fixed(44) })
								end,
							}),
						},
					}),
				},
			})
		)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		shown:set(true)
		controller.refresh()
		expect(classContract.isDisabled(nodeAt(root, "/S/Panel/W/then/B"))).toBe(true)
		on:set(true)
		controller.refresh()
		expect(classContract.isDisabled(nodeAt(root, "/S/Panel/W/then/B"))).toBe(false)
	end)
end)

-- ===== 4. every input path ================================================

describe("C3: a disabled subtree blocks every input path", function()
	local function screen(onActivate: () -> ())
		return UI.Screen({
			id = "S",
			children = {
				UI.Button({ id = "Live", label = "live", height = fixed(44) }),
				UI.VStack({
					id = "Panel",
					enabled = false,
					children = {
						UI.Button({ id = "Off", label = "off", height = fixed(44), onActivate = onActivate }),
					},
				}),
			},
		})
	end

	it("pointer / touch: a tap inside the subtree activates nothing", function()
		local fired = 0
		local _, _, adapter, _, pres = present(screen(function()
			fired += 1
		end))
		adapter.tap("/S/Panel/Off")
		pres.refresh()
		expect(fired).toBe(0)
	end)

	it("keyboard and gamepad: Activate is consumed and does nothing", function()
		local fired = 0
		local _, _, _, system, pres = present(screen(function()
			fired += 1
		end))
		pres.focus.focusOn("/S/Panel/Off")
		pres.refresh()
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		system.deviceKey("ButtonA", true)
		system.deviceKey("ButtonA", false)
		pres.refresh()
		expect(fired).toBe(0)
	end)

	it("focus: navigation never lands inside the subtree", function()
		local _, _, _, system, pres = present(screen(function() end))
		local seen = ""
		for _ = 1, 4 do
			system.deviceKey("DPadDown", true)
			system.deviceKey("DPadDown", false)
			pres.refresh()
			local f = pres.focus.focused:get()
			if f ~= nil then
				seen ..= f .. ","
			end
		end
		expect(string.find(seen, "/S/Panel/Off", 1, true)).toBe(nil)
	end)

	it("traversal: Tab never stops inside the subtree", function()
		local _, _, _, _, pres = present(screen(function() end))
		local map = pres.focus.focusMap()
		for _, entry in map.traversal do
			local id = if type(entry) == "table" then entry.id else entry
			expect(string.find(tostring(id), "/S/Panel/", 1, true)).toBe(nil)
		end
	end)

	it("a focusable Grip inside the subtree is out of the focus order too", function()
		local _, _, _, _, pres = present(UI.Screen({
			id = "S",
			children = {
				UI.Button({ id = "Live", label = "live", height = fixed(44) }),
				UI.VStack({
					id = "Panel",
					enabled = false,
					children = {
						UI.Grip({ id = "G", focusable = true, width = fixed(44), height = fixed(44) }),
					},
				}),
			},
		}))
		local map = pres.focus.focusMap()
		for _, entry in map.traversal do
			local id = if type(entry) == "table" then entry.id else entry
			expect(tostring(id)).never().toBe("/S/Panel/G")
		end
	end)

	--[[ THE SECONDARY ACTIONS — a row's swipe tray, a long-press menu, a drag — are
		not separate gates. Every one of them is routed by the two seams below, so
		pinning the seams pins the verbs: `controller.tapAt` is the hit test every
		pointer and touch gesture starts from, and `isSourceEnabled` is what the drag
		registry asks before it will acquire anything. ]]
	it("the hit test finds nothing inside the subtree, so no gesture can start there", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local taps: { string } = {}
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.Button({ id = "Live", label = "live", width = fixed(100), height = fixed(44) }),
					UI.VStack({
						id = "Panel",
						enabled = false,
						children = {
							UI.Button({ id = "Off", label = "off", width = fixed(100), height = fixed(44) }),
						},
					}),
				},
			})
		)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, {
			rootPolicy = "edgeToEdge",
			onNodeTap = function(path: string)
				table.insert(taps, path)
			end,
		})
		controller.initialRender()
		local off = adapter.node("/S/Panel/Off").rect
		expect(controller.tapAt(off.x + 2, off.y + 2)).toBeNil()
		local live = adapter.node("/S/Live").rect
		expect(controller.tapAt(live.x + 2, live.y + 2)).toBe("/S/Live")
		expect(#taps).toBe(1)
	end)

	it("a drag source inside the subtree acquires nothing", function()
		local _, _, controller = renderOnly(UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "Panel",
					enabled = false,
					children = {
						UI.draggable(
							UI.Box({ id = "Card", width = fixed(100), height = fixed(60) }),
							{ payload = "card" }
						),
					},
				}),
				UI.draggable(UI.Box({ id = "Free", width = fixed(100), height = fixed(60) }), { payload = "free" }),
			},
		}))
		local registry = controller.dragRegistry()
		-- `arm` is the acquisition every input class funnels into, and it refuses a
		-- source the host reports disabled
		expect(registry.arm("/S/Panel/Card")).toBe(false)
		expect(registry.arm("/S/Free")).toBe(true)
	end)

	--[[ A `Button` IS A CONTAINER, so its own `enabled = false` now reaches the custom
		content it draws inside its one activation surface. Before the cascade the
		content kept full contrast beside a plate the engine had already dimmed, which
		is the same inconsistency B-BTN4 closed for the button's own label. Recorded in
		the changelog because it is visible on a screen nobody edited. ]]
	it("a disabled Button's custom content is disabled with it", function()
		local _, adapter, _, root = renderOnly(UI.Screen({
			id = "S",
			children = {
				UI.Button({
					id = "B",
					label = "save",
					enabled = false,
					height = fixed(44),
					children = { UI.Text({ id = "Caption", text = "Save" }) },
				}),
			},
		}))
		expect(classContract.isDisabled(nodeAt(root, "/S/B/Caption"))).toBe(true)
		expect(adapter.node("/S/B/Caption").props.enabled).toBe(false)
	end)

	it("the engine is told: the resolved value reaches the adapter as enabled = false", function()
		local _, adapter = renderOnly(screen(function() end))
		expect(adapter.node("/S/Panel/Off").props.enabled).toBe(false)
		expect(adapter.node("/S/Live").props.enabled).never().toBe(false)
	end)
end)

--[[ ===== THE GROUPED DERIVATION (RED-TEAM C2) ==============================
	Everything above this block drives a VERTICAL screen, and a vertical screen is
	served by `focusWalk` — one of TWO derivations the presenter runs. The moment a
	screen has horizontal structure (an `HStack` run of two focusables, a `Grid`),
	`hasHorizontalStructure` engages and the member set becomes the NAVIGATION
	GROUPS, built by `autoGroups`/`layoutGroups` over `collectFocusables`. Those
	walks had their own copies of "is this a focus stop" and none of them asked
	`isDisabled`, so a disabled panel beside a live row stayed fully navigable:
	`DPadRight` landed on it, `initialFocus` landed on it, focus already inside it
	stayed there when the panel was switched off, and a Slider inside it still moved
	its owner's value.

	The constitution's rule is that the two verbs walk the SAME set (§9, "one focus
	map, read two ways"), so every C3 claim above owes a grouped arm. These are
	those arms. ]]
describe("C3 (grouped): a disabled subtree is out of the GROUPED derivation too", function()
	local function grouped(panelEnabled: any, panelChildren: { any })
		return UI.Screen({
			id = "S",
			children = {
				UI.HStack({
					id = "Row",
					children = {
						UI.Button({ id = "A", label = "a", width = fixed(80), height = fixed(44) }),
						UI.VStack({ id = "Panel", enabled = panelEnabled, children = panelChildren }),
						UI.Button({ id = "B", label = "b", width = fixed(80), height = fixed(44) }),
					},
				}),
			},
		})
	end
	local function offButton()
		return { UI.Button({ id = "Off", label = "off", width = fixed(80), height = fixed(44) }) }
	end
	local function pathsOf(entries: { any }): { string }
		local out: { string } = {}
		for _, e in entries do
			table.insert(out, tostring(if type(e) == "table" then (e.path or e.id) else e))
		end
		return out
	end
	local function has(list: { string }, needle: string): boolean
		for _, v in list do
			if string.find(v, needle, 1, true) ~= nil then
				return true
			end
		end
		return false
	end

	it("the horizontal run's traversal skips it, exactly as the flat walk does", function()
		local _, _, _, _, pres = present(grouped(false, offButton()))
		local map = pres.focus.focusMap()
		expect(has(pathsOf(map.traversal), "/S/Row/Panel/Off")).toBe(false)
		expect(has(pathsOf(map.traversal), "/S/Row/A")).toBe(true)
	end)

	it("no navigation group carries it either — the two readings agree", function()
		local _, _, _, _, pres = present(grouped(false, offButton()))
		for _, group in pres.focus.focusMap().navigation or {} do
			expect(has(pathsOf(group.order or {}), "/S/Row/Panel/Off")).toBe(false)
		end
	end)

	it("DPadRight walks past it to the live button on the far side", function()
		local _, _, _, system, pres = present(grouped(false, offButton()))
		pres.focus.focusOn("/S/Row/A")
		pres.refresh()
		system.deviceKey("DPadRight", true)
		system.deviceKey("DPadRight", false)
		pres.refresh()
		expect(pres.focus.focused:get()).toBe("/S/Row/B")
	end)

	it("initialFocus does not land inside it", function()
		local _, _, _, _, pres = present(grouped(false, offButton()))
		expect(tostring(pres.focus.focused:get())).never().toBe("/S/Row/Panel/Off")
	end)

	it("focus already inside it LEAVES when the panel is switched off", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 600, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local on = core:signal(true)
		local adapter = fake_target.new()
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		pres.present(grouped(on, offButton()))
		pres.refresh()
		pres.focus.focusOn("/S/Row/Panel/Off")
		pres.refresh()
		expect(pres.focus.focused:get()).toBe("/S/Row/Panel/Off")
		on:set(false)
		pres.refresh()
		expect(tostring(pres.focus.focused:get())).never().toBe("/S/Row/Panel/Off")
	end)

	it("...and the same holds when the live siblings are a Grid rather than a row", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 600, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local on = core:signal(true)
		local adapter = fake_target.new()
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.Grid({
					id = "G",
					columns = 2,
					children = {
						UI.Button({ id = "A", label = "a", width = fixed(80), height = fixed(44) }),
						UI.Button({ id = "B", label = "b", width = fixed(80), height = fixed(44) }),
						UI.VStack({
							id = "Panel",
							enabled = on,
							children = {
								UI.Button({ id = "Off", label = "off", width = fixed(80), height = fixed(44) }),
							},
						}),
					},
				}),
			},
		}))
		pres.refresh()
		pres.focus.focusOn("/S/G/Panel/Off")
		pres.refresh()
		on:set(false)
		pres.refresh()
		expect(tostring(pres.focus.focused:get())).never().toBe("/S/G/Panel/Off")
		for _, group in pres.focus.focusMap().navigation or {} do
			expect(has(pathsOf(group.order or {}), "/S/G/Panel/Off")).toBe(false)
		end
	end)

	--[[ A VALUE CONTROL IS THE SHARPEST ARM: the Adjust verb is bound only while
		focus sits on its declared target, so "the track is still in the ring" and
		"the owner's signal still moves" are the same defect seen from two ends. The
		Slider's track is a focusable `Grip`, which is the branch that had no
		`isDisabled` in EITHER grouped walk. ]]
	it("a Slider inside the subtree keeps its owner's value, on both Adjust keys", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 600, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		local value = core:signal(0.5)
		local slider = Facet.Controls.Slider(core, { id = "Vol", value = value, min = 0, max = 1 })
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.HStack({
					id = "Row",
					children = {
						UI.Button({ id = "A", label = "a", width = fixed(80), height = fixed(44) }),
						UI.Button({ id = "B", label = "b", width = fixed(80), height = fixed(44) }),
					},
				}),
				UI.VStack({ id = "Panel", enabled = false, children = { slider.blueprint } }),
			},
		}))
		pres.refresh()
		for _, group in pres.focus.focusMap().navigation or {} do
			expect(has(pathsOf(group.order or {}), "/S/Panel/Vol")).toBe(false)
		end
		pres.focus.focusOn("/S/Panel/Vol/TrackHost/Track")
		pres.refresh()
		for _ = 1, 3 do
			system.deviceKey("Right", true)
			system.deviceKey("Right", false)
			pres.refresh()
		end
		for _ = 1, 3 do
			system.deviceKey("DPadRight", true)
			system.deviceKey("DPadRight", false)
			pres.refresh()
		end
		expect(value:get()).toBe(0.5)
		slider.dispose()
	end)

	it("a Stepper inside the subtree is not a dead stop the pad can reach", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 600, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		local qty = core:signal(3)
		local stepper = Facet.Controls.Stepper(core, { id = "Qty", label = "Qty", value = qty, min = 0, max = 9 })
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.Button({ id = "A", label = "a", width = fixed(80), height = fixed(44) }),
				UI.VStack({ id = "Panel", enabled = false, children = { stepper.blueprint } }),
			},
		}))
		pres.refresh()
		for _ = 1, 6 do
			system.deviceKey("DPadDown", true)
			system.deviceKey("DPadDown", false)
			pres.refresh()
		end
		expect(string.find(tostring(pres.focus.focused:get()), "/S/Panel/", 1, true)).toBe(nil)
		for _, group in pres.focus.focusMap().navigation or {} do
			expect(has(pathsOf(group.order or {}), "/S/Panel/Qty")).toBe(false)
		end
		expect(qty:get()).toBe(3)
		stepper.dispose()
	end)
end)

describe("C3: focus restoration when the focused subtree is switched off", function()
	it("focus leaves for a legal node and does not come back on re-enable", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local on = core:signal(true)
		local adapter = fake_target.new()
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.Button({ id = "Live", label = "live", height = fixed(44) }),
				UI.VStack({
					id = "Panel",
					enabled = on,
					children = { UI.Button({ id = "Off", label = "off", height = fixed(44) }) },
				}),
			},
		}))
		pres.refresh()
		pres.focus.focusOn("/S/Panel/Off")
		pres.refresh()
		expect(pres.focus.focused:get()).toBe("/S/Panel/Off")

		on:set(false)
		pres.refresh()
		local landed = pres.focus.focused:get()
		expect(landed).never().toBe("/S/Panel/Off")
		expect(landed).toBe("/S/Live")
	end)
end)

-- ===== 5. themed paint ====================================================

describe("C4/C6: the disabled state is themed, through the sheet", function()
	local NEUTRAL = sheet_model.build({
		themes = { { name = "Dark", style = default_style }, { name = "Light", style = light_style } },
	})

	local function ruleFor(model: any, selector: string): any
		local found: any = nil
		for _, rule in model.rules do
			if rule.selector == selector then
				found = rule
			end
		end
		return found
	end

	it("classifyTags mints the state tag, and only when the node is disabled", function()
		local tag = chrome_slots.TAGS.stateDisabled
		expect(type(tag)).toBe("string")
		expect(sheet_model.classifyTags({ disabled = true })[tag]).toBe(true)
		expect(sheet_model.classifyTags({ disabled = false })[tag]).toBe(nil)
		expect(sheet_model.classifyTags({})[tag]).toBe(nil)
	end)

	local SELECTOR = `TextLabel.{chrome_slots.TAGS.stateDisabled}`

	it("Studio Neutral dims the tagged node's text from the theme's own number", function()
		local rule = ruleFor(NEUTRAL, SELECTOR)
		expect(rule ~= nil).toBe(true)
		expect(rule.props.TextTransparency.kind).toBe("number")
		-- ...the SAME number the engine-state rule for a disabled button uses, so a
		-- control that wears both is dimmed once
		local button = ruleFor(NEUTRAL, "TextButton:NonInteractable")
		expect(rule.props.TextTransparency.value).toBe(button.props.TextTransparency.value)
	end)

	it("a reference theme package emits the same rule, retuned by its own metric", function()
		local pkg = (require)("../examples/themes/pixel_quest").build(Facet.themes)
		local model = sheet_model.buildPackage(pkg)
		local rule = ruleFor(model, SELECTOR)
		expect(rule ~= nil).toBe(true)
		expect(rule.props.TextTransparency.kind).toBe("number")
		local button = ruleFor(model, "TextButton:NonInteractable")
		expect(rule.props.TextTransparency.value).toBe(button.props.TextTransparency.value)
	end)

	it("the rule is in the `disabled` group, so it beats hover and press", function()
		local disabledIndex, hoverIndex = 0, 0
		for index, rule in NEUTRAL.rules do
			if rule.selector == SELECTOR then
				disabledIndex = index
			elseif string.find(rule.selector, ":Hover", 1, true) ~= nil then
				hoverIndex = math.max(hoverIndex, index)
			end
		end
		expect(disabledIndex > hoverIndex).toBe(true)
	end)

	--[[ THE STYLED READ, HEADLESS. Paint itself is a live check, but "which rule owns
		this node's TextTransparency, and what number does it supply" is answerable from
		the built sheet: classify the node exactly as the adapter does, walk the rules in
		`(priority, insertion)` order — the order the engine reads — and report the last
		one that writes the property. The same oracle shape `popup_catcher_paint.spec`
		uses, for the same reason. ]]
	local function resolvedTextTransparency(model: any, disabled: boolean): (number?, string?)
		local tags = sheet_model.classifyTags({ disabled = disabled })
		local ordered: { { rule: any, index: number, priority: number } } = {}
		for index, rule in model.rules do
			local class, rest = string.match(rule.selector, "^(%a+)%.([%w%-%.]+)$")
			if class ~= "TextLabel" or rest == nil then
				continue -- this oracle asks about a plain label and nothing else
			end
			local matches = true
			for tag in string.gmatch(rest, "[^%.]+") do
				matches = matches and tags[tag] == true
			end
			if matches then
				local priority = if type(rule.priority) == "number" then rule.priority else index
				table.insert(ordered, { rule = rule, index = index, priority = priority })
			end
		end
		table.sort(ordered, function(a, b)
			if a.priority ~= b.priority then
				return a.priority < b.priority
			end
			return a.index < b.index
		end)
		local value: number?, owner: string? = nil, nil
		for _, entry in ordered do
			local prop = entry.rule.props.TextTransparency
			if type(prop) == "table" and prop.kind == "number" then
				value, owner = prop.value, entry.rule.name
			end
		end
		return value, owner
	end

	it("a plain label in a disabled subtree resolves to the theme's dim, and an enabled one to nothing", function()
		local dim, owner = resolvedTextTransparency(NEUTRAL, true)
		expect(owner).toBe("Disabled subtree text")
		expect(type(dim)).toBe("number")
		expect(dim > 0).toBe(true)
		expect(resolvedTextTransparency(NEUTRAL, false)).toBe(nil)
	end)

	it("the tag rides the classification the adapter syncs, not a bespoke write", function()
		local fs = require("@lune/fs")
		local sync = fs.readFile("src/client/screen_target.luau")
		expect(string.find(sync, "disabled = handle.disabledState", 1, true) ~= nil).toBe(true)
	end)
end)

describe("C6: an inherited tint resolves against the ACTIVE theme, not a literal", function()
	it("the same inherited tint resolves to different colours under two themes", function()
		local dark = sheet_model.tintColor(default_style, ACCENT, "Text")
		local light = sheet_model.tintColor(light_style, ACCENT, "Text")
		expect(type(dark.r)).toBe("number")
		expect(dark.r ~= light.r or dark.g ~= light.g or dark.b ~= light.b).toBe(true)
	end)
end)

-- ===== 6. lifecycle =======================================================

describe("C: teardown", function()
	it("disposing while a subtree is disabled leaves nothing live", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local on = core:signal(true)
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.VStack({
						id = "Panel",
						enabled = on,
						tint = ACCENT,
						children = { UI.Text({ id = "T", text = "hi" }) },
					}),
				},
			})
		)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		on:set(false)
		controller.refresh()
		controller.dispose()
		root.dispose()
		expect(root.counters().mounted).toBe(0)
		expect(adapter.liveCount()).toBe(0)
	end)
end)
