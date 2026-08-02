--!strict
-- Milestone B — completing Button as the base control (docs/plans/swiftui-parity-next.md
-- investment 3; acceptance rows B-BTN1..B-BTN4).
--
-- The plan's rule for a finished control: "a control is unfinished until its
-- layout, reachability, platform idiom, focus, disabled behavior, preferred-text
-- behavior, and teardown are proven." Input is driven through the REAL paths
-- (adapter.tap / system.deviceKey), never by calling a callback.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local rendererLib = require("../src/render/renderer")
local presenterLib = require("../src/present/presenter")
local actionsLib = require("../src/input/actions")
local sheetModel = require("../src/tokens/sheet_model")
local defaultStyle = require("../src/tokens/default_style")
local fake_target = require("../tests/lib/fake_target")

local function fixed(px: number)
	return { type = "fixed", px = px }
end
local function fill(weight: number?)
	return { type = "fill", weight = weight or 1 }
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

local function renderOnly(screen: any, w: number?, h: number?)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = w or 400, h = h or 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local root = mountLib.mount(core, screen)
	local adapter = fake_target.new()
	local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return core, adapter, controller, root
end

describe("B-BTN1: Button supports custom content behind one activation surface", function()
	it("renders its children inside the button", function()
		local _, adapter = renderOnly(UI.Screen({
			id = "S",
			children = {
				UI.Button({
					id = "Icony",
					label = "Save",
					width = fixed(120),
					height = fixed(44),
					children = {
						UI.Image({ id = "Glyph", image = "rbxassetid://1", width = fixed(20), height = fixed(20) }),
						UI.Text({ id = "Caption", text = "Save" }),
					},
				}),
			},
		}))
		expect(adapter.node("/S/Icony/Glyph") ~= nil).toBe(true)
		expect(adapter.node("/S/Icony/Caption") ~= nil).toBe(true)
	end)

	it("keeps the label as SEMANTICS only when content is present (the button draws no text of its own)", function()
		local _, adapter = renderOnly(UI.Screen({
			id = "S",
			children = {
				UI.Button({
					id = "Icony",
					label = "Save",
					width = fixed(120),
					height = fixed(44),
					children = { UI.Text({ id = "Caption", text = "Save" }) },
				}),
			},
		}))
		-- the label would otherwise be painted UNDER the custom content
		expect(adapter.node("/S/Icony").props.label).toBe("")
		-- ...while the mounted node keeps it for the contract/dump
		expect(adapter.node("/S/Icony/Caption").props.text).toBe("Save")
	end)

	it("a plain Button still paints its label", function()
		local _, adapter = renderOnly(UI.Screen({
			id = "S",
			children = { UI.Button({ id = "Plain", label = "Go" }) },
		}))
		expect(adapter.node("/S/Plain").props.label).toBe("Go")
	end)

	it("the label stays REQUIRED even for an icon-only button", function()
		expect(pcall(function()
			return UI.Button({ id = "B", children = { UI.Image({ id = "I", image = "x" }) } })
		end)).toBe(false)
	end)

	it("a focusable inside the content is rejected: one activation surface, one focus site", function()
		local ok, err = pcall(function()
			return UI.Button({
				id = "B",
				label = "Outer",
				children = { UI.Button({ id = "Inner", label = "Inner" }) },
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "one activation surface", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "Inner", 1, true) ~= nil).toBe(true)
	end)

	it("a focusable nested DEEPER in the content is also rejected", function()
		expect(pcall(function()
			return UI.Button({
				id = "B",
				label = "Outer",
				children = {
					UI.HStack({ id = "Row", children = { UI.Toggle({ id = "T", label = "t" }) } }),
				},
			})
		end)).toBe(false)
	end)

	it("a content button exposes exactly ONE focusable and activates once", function()
		local fired = 0
		local _, _, adapter, system, pres = present(UI.Screen({
			id = "S",
			children = {
				UI.Button({
					id = "Icony",
					label = "Save",
					height = fixed(44),
					width = fixed(120),
					onActivate = function()
						fired += 1
					end,
					children = { UI.Text({ id = "Caption", text = "Save" }) },
				}),
			},
		}))
		-- real pointer tap through the adapter
		adapter.tap("/S/Icony")
		pres.refresh()
		expect(fired).toBe(1)
		-- ...and the keyboard path hits the same single site
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		pres.refresh()
		expect(fired).toBe(2)
	end)
end)

describe("B-BTN2: semantic roles ride tags and style rules", function()
	it("accepts the three documented roles and rejects anything else", function()
		for _, role in { "default", "cancel", "destructive" } do
			expect(UI.Button({ id = "B", label = "x", role = role }).props.role).toBe(role)
		end
		local ok, err = pcall(function()
			return UI.Button({ id = "B", label = "x", role = "scary" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "default | cancel | destructive", 1, true) ~= nil).toBe(true)
	end)

	it("the role reaches the adapter as a style write, not a paint write", function()
		local _, adapter = renderOnly(UI.Screen({
			id = "S",
			children = { UI.Button({ id = "Del", label = "Delete", role = "destructive" }) },
		}))
		expect(adapter.node("/S/Del").props.role).toBe("destructive")
	end)

	it("a reactive role re-applies (it is a style prop, not a create-time write)", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		local role = core:signal("default")
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = { UI.Button({ id = "B", label = "x", role = role }) },
			})
		)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		expect(adapter.node("/S/B").props.role).toBe("default")
		role:set("destructive")
		controller.refresh()
		expect(adapter.node("/S/B").props.role).toBe("destructive")
	end)

	it("REGRESSION: a role rule is ordered AFTER the base fills so it owns the resting fill", function()
		-- found live: placed before "Control fill", the destructive rule lost its
		-- BackgroundColor3 to it (white text on a neutral fill) because the measured
		-- cascade is Priority then INSERTION ORDER, with no selector specificity
		local model = sheetModel.build({ themes = { { name = "Dark", style = defaultStyle } } })
		local indexOf: { [string]: number } = {}
		for i, rule in model.rules do
			indexOf[rule.name] = i
		end
		expect(indexOf["Destructive button"] > indexOf["Control fill"]).toBe(true)
		expect(indexOf["Destructive button"] > indexOf["Selected row"]).toBe(true)
		-- ...and before the engine state rules, so hover/press still layer on top
		expect(indexOf["Destructive button"] < indexOf["Control — hover"]).toBe(true)
		expect(indexOf["Cancel button"] < indexOf["Control — pressed"]).toBe(true)
	end)

	it("verifier V14: a role carries its OWN hover and press rules", function()
		-- the generic Control hover/press rules key on the interactive tag, not the
		-- role, so without role-specific ones a hovered destructive button repainted
		-- neutral and the role visually vanished at the moment of the click
		local model = sheetModel.build({ themes = { { name = "Dark", style = defaultStyle } } })
		local byName: { [string]: any } = {}
		local indexOf: { [string]: number } = {}
		for i, rule in model.rules do
			byName[rule.name] = rule
			indexOf[rule.name] = i
		end
		expect(byName["Destructive — hover"] ~= nil).toBe(true)
		expect(byName["Destructive — pressed"] ~= nil).toBe(true)
		expect(byName["Destructive — hover"].props.BackgroundColor3).toBe("$DangerHover")
		-- and they must come AFTER the generic state rules to win the cascade
		expect(indexOf["Destructive — hover"] > indexOf["Control — hover"]).toBe(true)
		expect(indexOf["Destructive — pressed"] > indexOf["Control — pressed"]).toBe(true)
		-- the tokens exist in every theme
		for _, theme in model.themes do
			expect(theme.tokens.DangerHover ~= nil).toBe(true)
			expect(theme.tokens.DangerPressed ~= nil).toBe(true)
		end
	end)

	it("verifier V14: a role + selected combination is a KNOWN limitation, recorded not hidden", function()
		-- "Selected row" is inserted BEFORE the role rules, so a control that is both
		-- selected and role-tagged paints the ROLE and loses its selection feedback.
		-- Selection is a LuauUI tag, not an engine pseudo-state, so it cannot layer.
		-- This is deliberate for now (a destructive control is not a selectable row in
		-- any shipped surface) and is asserted so the ordering cannot drift silently.
		local model = sheetModel.build({ themes = { { name = "Dark", style = defaultStyle } } })
		local indexOf: { [string]: number } = {}
		for i, rule in model.rules do
			indexOf[rule.name] = i
		end
		expect(indexOf["Selected row"] < indexOf["Destructive button"]).toBe(true)
	end)

	it("the sheet carries a rule per role, so paint stays sheet-owned", function()
		local model = sheetModel.build({ themes = { { name = "Dark", style = defaultStyle } } })
		local names = {}
		for _, rule in model.rules do
			names[rule.name] = rule
		end
		expect(names["Destructive button"] ~= nil).toBe(true)
		expect(names["Cancel button"] ~= nil).toBe(true)
		-- and the destructive fill is a TOKEN reference, never a literal colour
		expect(names["Destructive button"].props.BackgroundColor3).toBe("$Danger")
	end)

	it("the classifier maps roles to tags purely", function()
		local tags = sheetModel.classifyTags({ buttonRole = "destructive" })
		expect(tags["luau-role-destructive"]).toBe(true)
		expect(sheetModel.classifyTags({ buttonRole = "cancel" })["luau-role-cancel"]).toBe(true)
		-- "default" adds no tag: the class default already describes it
		expect(next(sheetModel.classifyTags({ buttonRole = "default" }))).toBe(nil)
	end)

	it("every theme's danger pair passes the contrast gate", function()
		local model = sheetModel.build({ themes = { { name = "Dark", style = defaultStyle } } })
		local sawDanger = false
		for _, theme in model.themes do
			expect(theme.contrast.ok).toBe(true)
			for _, entry in theme.contrast.pairs do
				if string.find(entry.pair, "onDanger", 1, true) then
					sawDanger = true
					expect(entry.ratio >= 4.5).toBe(true)
				end
			end
		end
		expect(sawDanger).toBe(true)
	end)
end)

describe("B-BTN3: the hit-target floor is enforced in solved/hit geometry", function()
	it("a sub-floor button reports an expanded hit rect", function()
		local _, adapter = renderOnly(UI.Screen({
			id = "S",
			children = { UI.Button({ id = "Star", label = "*", width = fixed(22), height = fixed(22) }) },
		}))
		local node = adapter.node("/S/Star")
		-- the VISUAL rect is untouched: enforcing the floor must not silently
		-- rewrite a designed layout
		expect(node.rect.w).toBe(22)
		expect(node.rect.h).toBe(22)
		-- ...and the hit rect meets the floor, centred on the visual
		local hit = adapter.hitRectOf("/S/Star")
		expect(hit ~= nil).toBe(true)
		expect((hit :: any).w).toBe(44)
		expect((hit :: any).h).toBe(44)
		expect((hit :: any).x).toBe(node.rect.x - 11)
		expect((hit :: any).y).toBe(node.rect.y - 11)
	end)

	it("a button already at or above the floor gets NO expander", function()
		local _, adapter = renderOnly(UI.Screen({
			id = "S",
			children = { UI.Button({ id = "Big", label = "ok", width = fixed(120), height = fixed(48) }) },
		}))
		expect(adapter.hitRectOf("/S/Big")).toBe(nil)
	end)

	it("only ONE axis is expanded when only one is short", function()
		local _, adapter = renderOnly(UI.Screen({
			id = "S",
			children = { UI.Button({ id = "Thin", label = "ok", width = fixed(120), height = fixed(20) }) },
		}))
		local hit = adapter.hitRectOf("/S/Thin") :: any
		expect(hit.w).toBe(120)
		expect(hit.h).toBe(44)
	end)

	it("the floor applies to Toggle and TextField too (every focusable control)", function()
		local _, adapter = renderOnly(UI.Screen({
			id = "S",
			children = {
				UI.Toggle({ id = "T", label = "t", width = fixed(30), height = fixed(20) }),
				UI.TextField({ id = "F", text = "", width = fixed(30), height = fixed(20) }),
			},
		}))
		expect((adapter.hitRectOf("/S/T") :: any).h).toBe(44)
		expect((adapter.hitRectOf("/S/F") :: any).h).toBe(44)
	end)

	it("a NON-interactive node never gets a hit rect", function()
		local _, adapter = renderOnly(UI.Screen({
			id = "S",
			children = { UI.Box({ id = "B", width = fixed(10), height = fixed(10) }) },
		}))
		expect(adapter.hitRectOf("/S/B")).toBe(nil)
	end)

	it("the expansion follows a re-solve", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		local h = core:signal(fixed(20))
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = { UI.Button({ id = "B", label = "x", width = fixed(120), height = h }) },
			})
		)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		expect((adapter.hitRectOf("/S/B") :: any).h).toBe(44)
		h:set(fixed(60))
		controller.refresh()
		expect(adapter.hitRectOf("/S/B")).toBe(nil)
	end)

	it(
		"a disabled control still gets no smaller than the floor (the target does not move when it re-enables)",
		function()
			local _, adapter = renderOnly(UI.Screen({
				id = "S",
				children = {
					UI.Button({ id = "B", label = "x", enabled = false, width = fixed(22), height = fixed(22) }),
				},
			}))
			expect((adapter.hitRectOf("/S/B") :: any).w).toBe(44)
		end
	)
end)

describe("B-BTN4: disabled is consistent across focus, activation, appearance and semantics", function()
	it("a disabled button is skipped by focus navigation", function()
		local _, _, _, system, pres = present(UI.Screen({
			id = "S",
			children = {
				UI.Button({ id = "First", label = "1", height = fixed(44) }),
				UI.Button({ id = "Off", label = "2", enabled = false, height = fixed(44) }),
				UI.Button({ id = "Third", label = "3", height = fixed(44) }),
			},
		}))
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
		expect(string.find(seen, "Third", 1, true) ~= nil).toBe(true)
		expect(string.find(seen, "/S/Off", 1, true)).toBe(nil)
	end)

	it("a disabled button does not activate on a pointer tap", function()
		local fired = 0
		local _, _, adapter, _, pres = present(UI.Screen({
			id = "S",
			children = {
				UI.Button({
					id = "Off",
					label = "x",
					enabled = false,
					height = fixed(44),
					onActivate = function()
						fired += 1
					end,
				}),
			},
		}))
		adapter.tap("/S/Off")
		pres.refresh()
		expect(fired).toBe(0)
	end)

	it("a disabled button does not activate on the keyboard or gamepad path either", function()
		local fired = 0
		local _, _, _, system, pres = present(UI.Screen({
			id = "S",
			children = {
				UI.Button({ id = "On", label = "a", height = fixed(44) }),
				UI.Button({
					id = "Off",
					label = "x",
					enabled = false,
					height = fixed(44),
					onActivate = function()
						fired += 1
					end,
				}),
			},
		}))
		for _, key in { "Return", "ButtonA" } do
			system.deviceKey("DPadDown", true)
			system.deviceKey("DPadDown", false)
			system.deviceKey(key, true)
			system.deviceKey(key, false)
			pres.refresh()
		end
		expect(fired).toBe(0)
	end)

	it("re-enabling restores focus reachability with no remount", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local enabled = core:signal(false)
		local adapter = fake_target.new()
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.Button({ id = "A", label = "a", height = fixed(44) }),
				UI.Button({ id = "Gate", label = "g", enabled = enabled, height = fixed(44) }),
			},
		}))
		pres.refresh()
		local createsBefore = adapter.liveCount()
		enabled:set(true)
		pres.refresh()
		local seen = ""
		for _ = 1, 3 do
			system.deviceKey("DPadDown", true)
			system.deviceKey("DPadDown", false)
			pres.refresh()
			local f = pres.focus.focused:get()
			if f ~= nil then
				seen ..= f .. ","
			end
		end
		expect(string.find(seen, "Gate", 1, true) ~= nil).toBe(true)
		expect(adapter.liveCount()).toBe(createsBefore)
	end)

	it("a disabled destructive button is still disabled (role does not re-enable it)", function()
		local fired = 0
		local _, _, adapter, _, pres = present(UI.Screen({
			id = "S",
			children = {
				UI.Button({
					id = "Del",
					label = "Delete",
					role = "destructive",
					enabled = false,
					height = fixed(44),
					onActivate = function()
						fired += 1
					end,
				}),
			},
		}))
		adapter.tap("/S/Del")
		pres.refresh()
		expect(fired).toBe(0)
	end)

	it("teardown returns the registry to its baseline", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		local adapter = fake_target.new()
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.Button({
						id = "B",
						label = "x",
						role = "destructive",
						width = fill(),
						children = { UI.Text({ id = "C", text = "x" }) },
					}),
				},
			})
		)
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		-- baseline AFTER the long-lived harness (env memos, renderer attach scope):
		-- only the CONTROL must be neutral (house pattern, tests/table.spec.luau)
		local baseline = core:counters()
		local root2 = mountLib.mount(core, UI.Button({ id = "B2", label = "y", role = "cancel" }))
		root2.dispose()
		local after = core:counters()
		expect(after.scopes).toBe(baseline.scopes)
		expect(after.observers).toBe(baseline.observers)
	end)
end)

-- ===== verifier findings V10 / V11 / V12 / V13 =============================
-- Each of these defects sat inside a row this stage had already marked PASS, and
-- none was visible to the suite. That is the finding behind the finding: the
-- tests exercised the paths the implementation happened to take.

describe("verifier V12: a disabled control refuses the CONSUMER OVERRIDE too", function()
	it("opts.onActivate does not fire for a disabled node", function()
		-- the override used to be dispatched BEFORE the disabled gate, so the most
		-- common integration (the gallery client's own) activated disabled controls
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		local fired = {}
		pres.present(
			UI.Screen({
				id = "S",
				children = {
					UI.Button({ id = "On", label = "on", height = fixed(44) }),
					UI.Button({ id = "Off", label = "off", enabled = false, height = fixed(44) }),
				},
			}),
			{
				onActivate = function(path: string)
					table.insert(fired, path)
				end,
			}
		)
		pres.refresh()
		adapter.tap("/S/Off")
		pres.refresh()
		expect(#fired).toBe(0)
		-- ...and the enabled sibling still reaches the override
		adapter.tap("/S/On")
		pres.refresh()
		expect(#fired).toBe(1)
		expect(fired[1]).toBe("/S/On")
	end)
end)

describe("verifier V10: structural remount forgets the per-path caches", function()
	local rendererLib2 = require("../src/render/renderer")

	it("a path re-created while still hidden is written hidden again", function()
		-- paths are REUSED across a remount, so a stale `lastVisible` made a fresh
		-- instance (Visible defaults true) inherit "already hidden" and paint
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 200, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local show = core:signal(true)
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.When({
						id = "Region",
						condition = show,
						thenView = function()
							return UI.ViewThatFits({
								id = "Fits",
								width = fill(),
								children = {
									UI.Box({ id = "Wide", width = fixed(500), height = fixed(20) }),
									UI.Box({ id = "Narrow", width = fixed(50), height = fixed(20) }),
								},
							})
						end,
					}),
				},
			})
		)
		local adapter = fake_target.new()
		local controller = rendererLib2.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local function pathEnding(suffix: string): string
			for _, path in adapter.paths() do
				if string.sub(path, -#suffix) == suffix then
					return path
				end
			end
			error(`no mounted path ending in {suffix}; live paths: {table.concat(adapter.paths(), ", ")}`)
		end
		local widePath = pathEnding("/Fits/Wide")
		expect(adapter.visibleOf(widePath)).toBe(false)
		-- unmount and remount the SAME paths
		show:set(false)
		controller.refresh()
		show:set(true)
		controller.refresh()
		expect(adapter.node(widePath) ~= nil).toBe(true)
		expect(adapter.visibleOf(widePath)).toBe(false)
	end)

	it("a sub-floor control re-created at the same path keeps its hit expander", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local show = core:signal(true)
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.When({
						id = "Region",
						condition = show,
						thenView = function()
							return UI.Button({ id = "Tiny", label = "x", width = fixed(22), height = fixed(22) })
						end,
					}),
				},
			})
		)
		local adapter = fake_target.new()
		local controller = rendererLib2.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local function pathEnding(suffix: string): string
			for _, p2 in adapter.paths() do
				if string.sub(p2, -#suffix) == suffix then
					return p2
				end
			end
			error(`no mounted path ending in {suffix}; live paths: {table.concat(adapter.paths(), ", ")}`)
		end
		local path = pathEnding("/Tiny")
		expect((adapter.hitRectOf(path) :: any).w).toBe(44)
		show:set(false)
		controller.refresh()
		show:set(true)
		controller.refresh()
		expect(adapter.hitRectOf(path) ~= nil).toBe(true)
		expect((adapter.hitRectOf(path) :: any).w).toBe(44)
	end)
end)
