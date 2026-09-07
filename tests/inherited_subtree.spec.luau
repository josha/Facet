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
--[[ THE SHARED HEADLESS WORLD, not a builder of this file's own (R12's follow-up
	trigger: "the next spec file that ADDS a builder migrates its file"). Eleven
	presenter setups in this file were eleven copies of the same six lines, and two
	of them had already drifted into a different argument spelling. `renderOnly`
	below stays hand-rolled because it deliberately has NO presenter — it drives the
	renderer straight, which is the only way to read what actually reached the
	adapter. ]]
local worldLib = require("./lib/world")
local classContract = require("../src/class_contract")
local sheet_model = require("../src/tokens/sheet_model")
local chrome_slots = require("../src/tokens/chrome_slots")
local default_style = require("../src/tokens/default_style")
local light_style = require("../src/tokens/default_light_style")
local fake_target = require("../tests/lib/fake_target")

local function fixed(px: number)
	return { type = "fixed", px = px }
end

local ZERO_INSETS = { top = 0, bottom = 0, left = 0, right = 0 }
local GUARD_OFF =
	"a focus/paint fixture: these screens are stacks of fixed-size buttons and are never asked to contain text"

local function newWorld(w: number?, h: number?): any
	return worldLib.new({
		viewport = { x = 0, y = 0, w = w or 400, h = h or 600 },
		safeInsets = ZERO_INSETS,
		overflowGuardOff = GUARD_OFF,
	})
end

local function present(screen: any, opts: any?)
	local w = newWorld()
	local handle = w.present(screen, opts)
	w.pres.refresh()
	return w.core, w.env, w.adapter, w.system, w.pres, handle
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

	--[[ NEW-7: a CONTAINER tint refuses `transparency`, and a leaf keeps it.

		The alpha is not a colour, it is a CLAIM: a tint that declares one takes
		`TextTransparency` on the node it lands on, permanently — `releaseTint`
		restores the value but never gives the property back to the sheet. On a leaf
		that is a bounded, named decision the author made about one node. Inherited, a
		single container declaration would silently take that property on every `Text`
		beneath it and leave the whole subtree un-dimmable for the life of the
		surface, long after the tint itself was cleared.

		Refusing it on the container form costs nobody: the form is new, so no screen
		can be relying on it, and the leaf form — where the author names the node — is
		untouched. That is the whole reason to decide it now rather than document it. ]]
	it("a CONTAINER tint refuses `transparency`, and the refusal names the leaf form", function()
		local ok, err = pcall(function()
			return UI.VStack({
				id = "V",
				tint = { role = "accent", blend = 1, transparency = 0.5 },
				children = {},
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "transparency", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "claim", 1, true) ~= nil).toBe(true)
	end)

	--[[ N1: AND THE REFUSAL HAS A READ-SITE HALF. The schema check runs at
		construction, and a container `tint` is REACTIVE, so binding a Readable is a
		first-class authoring form the constructor never sees. Without the second half
		the bound value walked straight through and claimed `TextTransparency` on every
		`Text` in the subtree — and with a `UI.Path` down there it CRASHED the render,
		naming a class the author never wrote `transparency` on.

		`blueprint_schema.luau`'s own rule, twelve lines above the check, is that a
		property with one ruling is read at construction for a static value and by the
		reader for a reactive one, "because a reactive value that skipped the check
		would paint garbage the constructor would have refused". This is that half. ]]
	it("a REACTIVE container tint carrying the alpha is refused at present, with the same sentence", function()
		local w = newWorld()
		local hue = w.core:signal({ role = "accent", blend = 1, transparency = 0.5 })
		local ok, err = pcall(function()
			return w.present(UI.Screen({
				id = "S",
				children = {
					UI.VStack({ id = "Panel", tint = hue, children = { UI.Text({ id = "L", text = "hi" }) } }),
				},
			}))
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "inherited tint takes no `transparency`", 1, true) ~= nil).toBe(true)
	end)

	it("...and a mid-life flip to an alpha is refused too, on a presented screen", function()
		local w = newWorld()
		local hue = w.core:signal({ role = "accent", blend = 1 })
		w.present(UI.Screen({
			id = "S",
			children = { UI.VStack({ id = "Panel", tint = hue, children = { UI.Text({ id = "L", text = "hi" }) } }) },
		}))
		w.pres.refresh()
		expect(w.core:lastError()).toBeNil()
		hue:set({ role = "accent", blend = 1, transparency = 0.5 })
		--[[ a mid-life set runs inside mount's own observer, so the framework's error
			ladder QUARANTINES it (constitution §8) rather than throwing through the
			consumer's `:set`. Refused either way, and recorded where a bug report can
			read it. ]]
		expect(string.find(tostring(w.core:lastError()), "inherited tint takes no `transparency`", 1, true) ~= nil).toBe(
			true
		)
	end)

	--[[ THE OTHER HALF OF THE SAME REPRO: a `UI.Path` under a REACTIVE container tint
		with no alpha still renders. The crash this refusal prevents was a Path being
		handed a `transparency` it has no channel for; the legal form must keep
		working, or the fix would have closed the hazard by closing the feature. ]]
	it("a Path under a reactive container tint WITHOUT an alpha renders and repaints", function()
		local w = newWorld()
		local hue = w.core:signal({ role = "accent", blend = 1 })
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "Panel",
					tint = hue,
					children = {
						UI.Path({
							id = "Arc",
							points = { { x = 0, y = 0 }, { x = 10, y = 10 } },
							width = fixed(20),
							height = fixed(20),
						}),
						UI.Text({ id = "L", text = "hi" }),
					},
				}),
			},
		}))
		w.pres.refresh()
		expect(w.core:lastError()).toBeNil()
		expect((w.adapter.node("/S/Panel/Arc").props.tint :: any).role).toBe("accent")
		hue:set({ role = "danger", blend = 1 })
		w.pres.refresh()
		expect(w.core:lastError()).toBeNil()
		expect((w.adapter.node("/S/Panel/Arc").props.tint :: any).role).toBe("danger")
	end)

	it("...and a LEAF tint still accepts it", function()
		local bp = UI.Text({ id = "T", text = "hi", tint = { role = "accent", blend = 1, transparency = 0.5 } })
		expect((bp.props.tint :: any).transparency).toBe(0.5)
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

	--[[ WHO ACTUALLY NEEDS THE WRITE (RED-TEAM I3). The resolved `enabled` used to go
		to EVERY node in a disabled subtree — 26 of 26 classes, `Screen`, `VStack`,
		`Spacer`, `Divider`, `Path` and all. Two costs, one of them permanent: the
		adapter materializes an ELIDED container the moment any property is written to
		it and there is no re-elide, so switching a panel off created a real `Frame`
		per elidable container for the life of the surface — and bought a
		`facet-state-disabled` tag that no rule selects, because the one rule that
		exists selects `TextLabel`.

		So the write goes to the classes that can consume it and nowhere else: the
		three the engine gives a non-interactable state, plus `Text`, which is what the
		themed rule paints. ]]
	it("a disabled subtree writes `enabled` only where something consumes it", function()
		local _, adapter = renderOnly(UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "Panel",
					enabled = false,
					children = {
						UI.VStack({
							id = "Inner",
							children = { UI.Spacer({ id = "Sp1" }), UI.Spacer({ id = "Sp2" }) },
						}),
						UI.Box({ id = "Plate", width = fixed(10), height = fixed(10) }),
						UI.Divider({ id = "Rule" }),
						UI.Text({ id = "Label", text = "hi" }),
						UI.Button({ id = "Go", label = "go", height = fixed(44) }),
					},
				}),
			},
		}))
		-- nothing consumes it here: no write, so no elided container is materialized
		for _, path in { "/S", "/S/Panel", "/S/Panel/Inner", "/S/Panel/Inner/Sp1", "/S/Panel/Plate", "/S/Panel/Rule" } do
			expect(`{path}={tostring(adapter.node(path).props.enabled)}`).toBe(`{path}=nil`)
		end
		-- ...and the two that do
		expect(adapter.node("/S/Panel/Label").props.enabled).toBe(false)
		expect(adapter.node("/S/Panel/Go").props.enabled).toBe(false)
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
		local w = newWorld(600, 600)
		local core, env, adapter, system, pres = w.core, w.env, w.adapter, w.system, w.pres
		local on = core:signal(true)
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
		local w = newWorld(600, 600)
		local core, env, adapter, system, pres = w.core, w.env, w.adapter, w.system, w.pres
		local on = core:signal(true)
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
		local w = newWorld(600, 600)
		local core, env, adapter, system, pres = w.core, w.env, w.adapter, w.system, w.pres
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
		local w = newWorld(600, 600)
		local core, env, adapter, system, pres = w.core, w.env, w.adapter, w.system, w.pres
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

--[[ ===== A PRESENTED SURFACE IS ITS OWN ROOT (RED-TEAM I5) =================
	A modal, a toast, a menu, a popover and an anchored sheet are each mounted as a
	FRESH root — `mount(core, blueprint)` with no inherited record — so a surface
	presented from inside a disabled subtree does not inherit its disable. The
	TRIGGER is blocked (nothing in a disabled subtree activates), so a new one
	cannot be opened from there; what this pins is the surface that was ALREADY
	OPEN when the panel was switched off. It stays live.

	THREADING IT WAS CONSIDERED AND DECLINED for this round. Eight call sites
	across `present/` mount those roots, and only some of them have a presenting
	node to inherit FROM: an anchored surface has its anchor, a modal or a toast
	has nothing. Half a cascade — anchored surfaces inherit, modals do not — is a
	worse promise than none, and choosing per site is a design decision about what
	a modal raised from a dead panel MEANS, not a plumbing change. So the limit is
	documented in api.md and pinned here, and dismissing what a panel opened stays
	the consumer's call, which it can already express.  ]]
describe("I5: a presented surface does not inherit the presenter's disabled subtree", function()
	it("a modal opened before the panel is switched off stays live, and api.md says so", function()
		local w = newWorld(400, 600)
		local core, env, adapter, system, pres = w.core, w.env, w.adapter, w.system, w.pres
		local on = core:signal(true)
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "Panel",
					enabled = on,
					children = { UI.Button({ id = "Open", label = "open", height = fixed(44) }) },
				}),
			},
		}))
		pres.refresh()
		local fired = 0
		pres.presentModal(UI.Screen({
			id = "M",
			children = {
				UI.Button({
					id = "Confirm",
					label = "ok",
					height = fixed(44),
					onActivate = function()
						fired += 1
					end,
				}),
			},
		}))
		pres.refresh()
		on:set(false)
		pres.refresh()
		--[[ the modal that was already up is NOT disabled with the panel that raised
			it. (The panel's own button is not tapped here on purpose: a tap OUTSIDE a
			modal is a dismissal, so it would take the modal away and prove nothing.
			That the panel's button is dead is pinned by the C3 checks above.) ]]
		adapter.tap("/M/Confirm")
		pres.refresh()
		expect(fired).toBe(1)

		local fs = require("@lune/fs")
		expect(string.find(fs.readFile("docs/reference/api.md"), "A presented surface is its own root", 1, true) ~= nil).toBe(
			true
		)
	end)
end)

--[[ ===== EVERY GROUP, NOT EVERY WALK (RED-TEAM round 2, NEW-1/2/3/4) ==========
	Round 1 put the disabled test inside the three walks that BUILD navigation groups.
	That was the wrong placement, three times over:

	  * a control that contributes its own `focusGroups` — `newTable`,
	    `newVirtualList`, `newVirtualGrid`, `newTextInput` — emits them verbatim and
	    the builders never descend into it, so a disabled list kept every row in the
	    ring (NEW-1), and a consumer-declared `navigationGroups` map was never
	    filtered at all (NEW-4);
	  * removing a cell from `collectFocusables` REPACKS an inferred grid, because
	    that walk is what fills the rectangle's rows: a disabled `C5` slid `C7` up a
	    lane instead of leaving a hole (NEW-2);
	  * `hasHorizontalStructure` counts through the same walk, so disabling one row
	    could flip the WHOLE screen between the grouped and the flat derivation
	    (NEW-3).

	`hidden` — the same kind of fact — has always been filtered on the BUILT groups,
	one call, in the presenter. Disabled is filtered there now too, and the walks are
	back to answering a structural question. The two facts even share the splice:
	a disabled subtree contributes its topmost node as a ROOT, exactly as a hidden
	subtree does, so `filterGroupsHidden` does the work for both. ]]
describe("NEW-1/2/4: the disabled filter runs on the BUILT groups, so it reaches every one", function()
	local function ids(group: any): { string }
		local out: { string } = {}
		for _, entry in group.order or {} do
			local id = tostring(if type(entry) == "table" then (entry.id or entry.path) else entry)
			table.insert(out, (string.match(id, "[^/]+$")) or id)
		end
		return out
	end
	local function groupsOf(pres: any): { any }
		return pres.focus.focusMap().navigation or {}
	end
	local function ringHas(pres: any, needle: string): boolean
		for _, group in groupsOf(pres) do
			for _, entry in group.order or {} do
				local id = tostring(if type(entry) == "table" then (entry.id or entry.path) else entry)
				if string.find(id, needle, 1, true) ~= nil then
					return true
				end
			end
		end
		return false
	end
	--[[ The panel is switched off by default; every case below also builds the LIVE
		arm, because "the ring does not contain it" is worth nothing until the same
		screen with the panel on is shown to contain it. ]]
	local function panel(child: any, enabled: boolean?)
		return UI.Screen({
			id = "S",
			children = {
				UI.HStack({
					id = "Row",
					children = {
						UI.Button({ id = "A", label = "a", width = fixed(80), height = fixed(44) }),
						UI.Button({ id = "B", label = "b", width = fixed(80), height = fixed(44) }),
					},
				}),
				UI.VStack({ id = "Panel", enabled = enabled ~= false, children = { child } }),
			},
		})
	end
	-- named for what it does, not for what it wraps: `worldLib` is the world now
	local function presented(screen: any, opts: any?)
		local w = newWorld(600, 600)
		w.present(screen, opts)
		w.pres.refresh()
		return w.core, w.pres, w.adapter
	end

	--[[ Each case builds the SAME screen twice — panel live, panel off — on its own
		core, because a composite control binds to the core it was built on and the
		live arm is what stops "the ring does not contain it" from being vacuous. ]]
	local function withControl(make: (any, any) -> any, enabled: boolean): (any, any)
		local w = newWorld(600, 600)
		-- the control is built BEFORE the screen, on the world's own core
		local built = make(w.core, w.env)
		w.present(panel(built.blueprint, enabled))
		w.pres.refresh()
		return w.pres, built
	end

	local function ringCase(name: string, needle: string, make: (any, any) -> any, checkFocus: boolean)
		it(`{name}`, function()
			local livePres, live = withControl(make, true)
			expect(ringHas(livePres, needle)).toBe(true)
			live.dispose()

			local offPres, off = withControl(make, false)
			expect(ringHas(offPres, needle)).toBe(false)
			if checkFocus then
				expect(string.find(tostring(offPres.focus.focused:get()), "/S/Panel/", 1, true)).toBe(nil)
			end
			off.dispose()
		end)
	end

	ringCase(
		"a Table's contributed row groups leave the ring, and initial focus is not a row",
		"/S/Panel/T/",
		function(core, _env)
			local rows = core:signal({ { id = "r1", name = "one" }, { id = "r2", name = "two" } })
			return Facet.Controls.Table(core, {
				id = "T",
				rows = rows,
				key = function(item: any)
					return item.id
				end,
				-- a selectable table is what contributes `row:` focus groups at all
				selection = "single",
				rowHeight = 40,
				columns = {
					{
						id = "name",
						title = "Name",
						width = { type = "fill", weight = 1 },
						value = function(item: any)
							return item.name
						end,
					},
				},
			})
		end,
		true
	)

	ringCase("a VirtualList's contributed row group leaves the ring", "/S/Panel/VL/", function(core, _env)
		local items: { any } = {}
		for i = 1, 20 do
			table.insert(items, { id = `r{i}`, label = `row {i}` })
		end
		return Facet.Controls.VirtualList(core, {
			id = "VL",
			rows = core:signal(items),
			key = function(item: any)
				return item.id
			end,
			rowHeight = 40,
			viewportHeight = 200,
			cell = function(item: any)
				return UI.Text({ id = "L", text = item.label })
			end,
		})
	end, true)

	ringCase("a VirtualGrid's contributed cell group leaves the ring", "/S/Panel/VG/", function(core, _env)
		local items: { any } = {}
		for i = 1, 12 do
			table.insert(items, { id = `c{i}` })
		end
		return Facet.Controls.VirtualGrid(core, {
			id = "VG",
			items = core:signal(items),
			key = function(item: any)
				return item.id
			end,
			itemExtent = 40,
			columns = 3,
			viewportExtent = 200,
			cell = function(item: any)
				return UI.Text({ id = "C", text = item.id })
			end,
		})
	end, false)

	--[[ THE TEXT INPUT IS THE ONE THE `props.enabled` GREP COULD NOT SEE: its
		contribution gates on `controlContract.enabledNow(spec.enabled)`, the AUTHORED
		spec value, which is I1's defect in a spelling no search for `props.enabled`
		would ever have found. Filtering the built groups reaches it without the
		control knowing anything about inheritance. ]]
	ringCase("a TextInput's contributed group leaves the ring", "/S/Panel/Field", function(core, env)
		return Facet.Controls.TextInput(core, { id = "Field", value = core:signal("hello"), env = env })
	end, true)

	it("a CONSUMER-declared navigationGroups map is filtered too, exactly as `hidden` is", function()
		local _, pres = presented(
			UI.Screen({
				id = "S",
				children = {
					UI.Button({ id = "Live", label = "l", width = fixed(80), height = fixed(44) }),
					UI.VStack({
						id = "Panel",
						enabled = false,
						children = { UI.Button({ id = "Off", label = "o", width = fixed(80), height = fixed(44) }) },
					}),
				},
			}),
			{
				navigationGroups = {
					{ name = "declared", axis = "vertical", order = { "/S/Live", "/S/Panel/Off" } },
				},
			}
		)
		expect(ringHas(pres, "/S/Panel/Off")).toBe(false)
		expect(ringHas(pres, "/S/Live")).toBe(true)
	end)

	--[[ NEW-2: a disabled cell punches a HOLE, it does not repack. `hidden` has
		always behaved this way, and the comment on the filter it shares says why —
		"every entry after a removed one shifts a lane, so the perpendicular arrow
		would land confidently wrong". ]]
	it("a disabled Grid cell leaves a hole, the same shape a hidden one leaves", function()
		local function grid(mut: (any) -> ())
			local kids: { any } = {}
			for i = 1, 9 do
				local props: any = { id = `C{i}`, label = "c", width = fixed(60), height = fixed(40) }
				if i == 5 then
					mut(props)
				end
				table.insert(kids, UI.Button(props))
			end
			return UI.Screen({ id = "S", children = { UI.Grid({ id = "G", columns = 3, children = kids }) } })
		end
		local function shape(screen: any): string
			local _, pres = presented(screen)
			local parts: { string } = {}
			for _, group in groupsOf(pres) do
				table.insert(parts, "[" .. table.concat(ids(group), ",") .. "]")
			end
			return table.concat(parts, " ")
		end
		local hiddenShape = shape(grid(function(props)
			props.hidden = true
		end))
		expect(hiddenShape).toBe("[C1,C2,C3] [C4,C6] [C7,C8,C9]")
		expect(shape(grid(function(props)
			props.enabled = false
		end))).toBe(hiddenShape)
	end)
end)

--[[ NEW-3: the DERIVATION is a structural question. `hasHorizontalStructure` counts
	focusables to decide whether a screen is navigated by groups or by the flat ring,
	and while that count read the disabled state, switching off one unrelated row
	could re-derive the navigation model — and the traversal rank — for the whole
	screen, live, in both directions. ]]
--[[ N2: WHAT A FULLY DISABLED GRID ROW COSTS, pinned because it is a promise now.

	A `Grid` names its row groups' `up`/`down` exits by INDEX, so a row every cell of
	which is disabled is still the named neighbour — and it is empty, so the move
	lands nowhere. The arrows cannot pass it, and everything below it is unreachable
	by the pad. `hidden` behaves identically, and always has; what this feature
	changed is that `enabled = false` is now INHERITABLE, which puts the shape on an
	ordinary settings screen rather than a rare one.

	A STACK OF `HStack` ROWS IS CROSSED CLEANLY, which is the way around and the
	reason this pin has two arms: the same content, laid out as stacked rows rather
	than as a grid, walks straight over the dead row. Both halves are asserted so the
	documented advice cannot rot into folklore. ]]
describe("N2: a fully disabled Grid row is a wall; stacked rows are not", function()
	local function drive(screen: any, from: string, presses: number): string
		local w = newWorld(600, 600)
		w.present(screen)
		w.pres.refresh()
		w.focusOn = nil
		w.pres.focus.focusOn(from)
		w.pres.refresh()
		for _ = 1, presses do
			w.system.deviceKey("DPadDown", true)
			w.system.deviceKey("DPadDown", false)
			w.pres.refresh()
		end
		return tostring(w.pres.focus.focused:get())
	end
	local function cell(id: string, off: boolean?)
		local props: any = { id = id, label = "x", width = fixed(50), height = fixed(40) }
		if off then
			props.enabled = false
		end
		return UI.Button(props)
	end

	it("the arrows cannot cross a Grid row whose every cell is disabled", function()
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.Grid({
					id = "G",
					children = {
						UI.GridRow({ id = "R1", children = { cell("A1"), cell("A2") } }),
						UI.GridRow({ id = "R2", children = { cell("B1", true), cell("B2", true) } }),
						UI.GridRow({ id = "R3", children = { cell("D1"), cell("D2") } }),
					},
				}),
			},
		})
		expect(drive(screen, "/S/G/R1/A1", 3)).toBe("/S/G/R1/A1")
	end)

	it("...and the SAME content as stacked rows is crossed cleanly — the documented way around", function()
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.HStack({ id = "R1", children = { cell("A1"), cell("A2") } }),
				UI.HStack({ id = "R2", children = { cell("B1", true), cell("B2", true) } }),
				UI.HStack({ id = "R3", children = { cell("D1"), cell("D2") } }),
			},
		})
		expect(drive(screen, "/S/R1/A1", 1)).toBe("/S/R3/D1")
	end)

	it("the limit is written down where an author will meet it", function()
		local fs = require("@lune/fs")
		expect(string.find(fs.readFile("docs/reference/api.md"), "cannot cross a `Grid` row", 1, true) ~= nil).toBe(
			true
		)
		expect(string.find(fs.readFile("CHANGELOG.md"), "cannot cross a `Grid` row", 1, true) ~= nil).toBe(true)
	end)
end)

describe("NEW-3: disabling a row does not flip the screen between derivations", function()
	it("the live column keeps its own group when the row beside it is switched off", function()
		local function screen(rowEnabled: boolean)
			return UI.Screen({
				id = "S",
				children = {
					UI.HStack({
						id = "Row",
						enabled = rowEnabled,
						children = {
							UI.Button({ id = "X", label = "x", width = fixed(60), height = fixed(40) }),
							UI.Button({ id = "Y", label = "y", width = fixed(60), height = fixed(40) }),
						},
					}),
					UI.VStack({
						id = "Col",
						children = {
							UI.Button({ id = "P", label = "p", width = fixed(60), height = fixed(40) }),
							UI.Button({ id = "Q", label = "q", width = fixed(60), height = fixed(40) }),
						},
					}),
				},
			})
		end
		local function names(enabled: boolean): string
			local w = newWorld(600, 600)
			local core, env, pres = w.core, w.env, w.pres
			pres.present(screen(enabled))
			pres.refresh()
			local out: { string } = {}
			for _, group in pres.focus.focusMap().navigation or {} do
				table.insert(out, tostring(group.name))
			end
			table.sort(out)
			return table.concat(out, " | ")
		end
		-- the same groups, whatever the row's state: only their MEMBERS change
		expect(names(false)).toBe(names(true))
		expect(string.find(names(false), "auto-v", 1, true) ~= nil).toBe(true)
	end)
end)

--[[ NEW-5: `initialFocus` naming a disabled control is a REFUSAL, on both
	derivations. The flat one always refused; the grouped one did not, because it
	never excluded the node in the first place. That alignment is a behaviour change
	an author can trip over — "focus the primary action, which starts disabled until
	the form is valid" is an ordinary pattern — so it has a release note and a pin. ]]
describe("NEW-5: initialFocus naming a disabled control refuses, and says what IS available", function()
	local function presentWith(structure: boolean)
		local w = newWorld(600, 600)
		local core, env, pres = w.core, w.env, w.pres
		local children: { any } = {
			UI.Button({ id = "Confirm", label = "ok", enabled = false, width = fixed(80), height = fixed(44) }),
			UI.Button({ id = "Cancel", label = "no", width = fixed(80), height = fixed(44) }),
		}
		local body = if structure
			then UI.HStack({ id = "Row", children = children })
			else UI.VStack({ id = "Col", children = children })
		pres.present(UI.Screen({ id = "S", children = { body } }), { initialFocus = "Confirm" })
	end

	for _, arm in { { "grouped", true }, { "flat", false } } do
		it(`the {arm[1]} derivation refuses, naming the legal set`, function()
			local ok, err = pcall(presentWith, arm[2] :: any)
			expect(ok).toBe(false)
			expect(string.find(tostring(err), "names no focusable on this surface", 1, true) ~= nil).toBe(true)
			expect(string.find(tostring(err), "Cancel", 1, true) ~= nil).toBe(true)
		end)
	end

	it("the release note says so", function()
		local fs = require("@lune/fs")
		local changelog = fs.readFile("CHANGELOG.md")
		expect(string.find(changelog, "initialFocus` names a disabled control", 1, true) ~= nil).toBe(true)
	end)
end)

describe("C3: focus restoration when the focused subtree is switched off", function()
	it("focus leaves for a legal node and does not come back on re-enable", function()
		local w = newWorld(400, 600)
		local core, env, adapter, system, pres = w.core, w.env, w.adapter, w.system, w.pres
		local on = core:signal(true)
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

	--[[ WHEN A TINT'S OWN ALPHA MEETS THE DISABLED DIM (RED-TEAM I4), the tint wins,
		and it wins by the rule the framework already had rather than by a new one.

		A `tint` that declares `transparency` CLAIMS `TextTransparency` on that node
		(`screen_paint`'s `claimPaint`) — an intentional, recorded defeat of the sheet,
		permanent for the instance's lifetime, published as `Facet_PaintClaims` so the
		authority audit reads a hand-off instead of an accident. The themed disabled
		state is a RULE. A rule never beats a claim; that is what a claim is.

		So the author who writes `tint = { …, transparency = 0 }` on a label has taken
		that property, and switching an ancestor off cannot dim it. Without the alpha
		— every tint written before it existed, and every one that does not need it —
		nothing is claimed and the dim applies normally. Both halves are pinned here,
		and api.md's inheritance section says which wins in public. ]]
	it("a tint WITHOUT its own alpha claims no transparency, so the dim reaches the label", function()
		local _, adapter = renderOnly(UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "Panel",
					enabled = false,
					tint = ACCENT,
					children = { UI.Text({ id = "Label", text = "hi" }) },
				}),
			},
		}))
		local emitted = adapter.node("/S/Panel/Label").props.tint
		expect((emitted :: any).role).toBe("accent")
		expect((emitted :: any).transparency).toBe(nil)
		expect(sheet_model.tintTransparency(emitted, "Text")).toBe(0)
		-- the node still takes the resolved disable, so the sheet's rule selects it
		expect(adapter.node("/S/Panel/Label").props.enabled).toBe(false)
	end)

	--[[ The alpha is declared on the LEAF, because a CONTAINER tint refuses it
		(NEW-7): the claim is per-node and permanent, so the author names the node.
		This is the composition that remains, and it is the one that matters — a
		claimed `TextTransparency` inside a disabled subtree. ]]
	it("a tint WITH its own alpha carries it, and that is the value the claim writes", function()
		local hue = { role = "accent", blend = 1, transparency = 0 }
		local _, adapter = renderOnly(UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "Panel",
					enabled = false,
					children = { UI.Text({ id = "Label", text = "hi", tint = hue }) },
				}),
			},
		}))
		local emitted = adapter.node("/S/Panel/Label").props.tint
		expect((emitted :: any).transparency).toBe(0)
		-- 0 is opaque: the claim writes full contrast, and the themed dim cannot
		-- reach a property the node has taken
		expect(sheet_model.tintTransparency(emitted, "Text")).toBe(0)
		expect(adapter.node("/S/Panel/Label").props.enabled).toBe(false)
	end)

	it("the rule that decides it is stated in public", function()
		local fs = require("@lune/fs")
		local api = fs.readFile("docs/reference/api.md")
		expect(string.find(api, "claim outranks the disabled dim", 1, true) ~= nil).toBe(true)
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

--[[ THE CREATE KEY AND THE PARK KEY ARE THE SAME QUESTION (RED-TEAM M2). The
	create-time signature was read off the AUTHORED props while the park key is built
	from what was actually WORN, and the two inherited channels break that equality
	in both directions: a node that inherited a disable carries no authored `enabled`
	and gets one written, and a CONTAINER that authored a `tint` carries the prop and
	emits nothing. Either way a parked instance landed in a bucket the create lookup
	could never name — unreachable, and holding a pool slot until the cap evicted it. ]]
describe("M2: an inherited node's recycle key matches what it actually wears", function()
	local recycle_key = require("../src/render/recycle_key")

	it("a node that INHERITED a disable signs `enabled`, which is what it wears", function()
		local rk = recycle_key.new()
		local node = { class = "Text", props = {}, disabled = true }
		expect(rk.signature(node)).toBe("enabled")
		rk.declareParts(node.class, node.class, nil, "leaf")
		rk.noteWorn(node.class, "enabled", false)
		expect(rk.parkKey(node.class)).toBe(rk.key(node.class, nil, "leaf", rk.signature(node)))
	end)

	it("a CONTAINER that authored a tint signs nothing, which is also what it wears", function()
		local rk = recycle_key.new()
		local node = { class = "VStack", props = { tint = ACCENT } }
		expect(rk.signature(node)).toBe("")
		rk.declareParts("/V", node.class, nil, "container")
		expect(rk.parkKey("/V")).toBe(rk.key(node.class, nil, "container", rk.signature(node)))
	end)

	it("...and a leaf that PAINTS the inherited tint signs it", function()
		local rk = recycle_key.new()
		expect(rk.signature({ class = "Text", props = {}, inheritedTint = ACCENT })).toBe("tint")
	end)
end)

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
