--!strict
-- Semantic ROLE resolution end to end (ADR-0019 §2/§6): blueprint props name a
-- typography role, a spacing step or a theme metric; the renderer's layout-node
-- builder and the solver's measure path turn those names into pixels through the
-- CURRENT `themeMetrics` snapshot. The two properties that matter:
--   * under Studio Neutral every migrated control solves to the literal it
--     shipped with (the compatibility bar — nothing moved);
--   * a themeMetrics commit RE-SOLVES a mounted screen with zero factory reruns,
--     creates or removes (the swap is never a rebuild).

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local solver = require("../src/layout/solver")
local text_metrics = require("../src/layout/text_metrics")
local themes = require("../src/themes/package")
local snapshot = require("../src/themes/snapshot")
local defaultStyle = require("../src/tokens/default_style")
local fake_target = require("../tests/lib/fake_target")

local function world(build: (core: any) -> any, w: number?, h: number?)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = w or 800, h = h or 600 })
	local root = mountLib.mount(core, build(core))
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {})
	controller.initialRender()
	return core, env, root, adapter, controller
end

-- a presenter-driven world: the PopupButton's open/close rides an input
-- contribution, which only the presenter dispatches
local function presentedWorld(build: (core: any) -> any, w: number?, h: number?)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = w or 800, h = h or 600 })
	local adapter = fake_target.new()
	local system = LuauUI.newActionSystem(core)
	local presenter = LuauUI.newPresenter(core, env, adapter, system)
	presenter.present(UI.Screen({ id = "S", padding = 0, children = { build(core) } }))
	presenter.refresh()
	return core, env, adapter, presenter
end

local function derive(metrics: any, id: string): any
	local pkg, report = themes.define({
		base = snapshot.neutralPackage(),
		identity = { id = id, displayName = id, schemaVersion = themes.SCHEMA, version = "1.0.0" },
		metrics = metrics,
	})
	assert(pkg ~= nil, "derive failed: " .. (if report.errors[1] then report.errors[1].message else "?"))
	return snapshot.resolve(pkg, nil, {})
end

describe("role resolution: renderer layout-node construction", function()
	it("a typography role resolves to the same box a literal size does", function()
		local _, _, _, byRole = world(function()
			return UI.Screen({
				id = "S",
				padding = 0,
				children = { UI.Text({ id = "T", text = "Volume", textSize = "body" }) },
			})
		end)
		local _, _, _, byNumber = world(function()
			return UI.Screen({
				id = "S",
				padding = 0,
				children = { UI.Text({ id = "T", text = "Volume", textSize = defaultStyle.type.body }) },
			})
		end)
		expect(byRole.node("/S/T").rect.w).toBe(byNumber.node("/S/T").rect.w)
		expect(byRole.node("/S/T").rect.h).toBe(byNumber.node("/S/T").rect.h)
	end)

	it("a role also PAINTS its resolved size, so measure and paint agree", function()
		local _, _, _, adapter = world(function()
			return UI.Screen({
				id = "S",
				padding = 0,
				children = { UI.Text({ id = "T", text = "Hi", textSize = "heading" }) },
			})
		end)
		expect(adapter.node("/S/T").props.textSize).toBe(defaultStyle.type.heading)
	end)

	-- CHANGED BY THE DIRECTOR FIX ROUND 2026-07-25. This used to assert that an
	-- absent `textSize` painted NOTHING, leaving the adapter's hardcoded 16. That
	-- was the bug: the measure seam resolved the class's typography ROLE from the
	-- snapshot and the paint seam ignored it, so a package that moved
	-- `type.control.size` was reserved for at one size and drawn at another — and
	-- compact-pointer's 13px control role wrapped a one-line "Play" into "Pla"/"y"
	-- inside a box the solver had sized correctly. The intrinsic role now paints.
	it("an ABSENT textSize paints the class's INTRINSIC role, so measure and paint agree", function()
		local _, _, _, adapter = world(function()
			return UI.Screen({
				id = "S",
				padding = 0,
				children = {
					UI.Text({ id = "T", text = "Hi" }),
					UI.Button({ id = "B", label = "Play" }),
					UI.Box({ id = "Plain", width = { type = "fixed", px = 10 }, height = { type = "fixed", px = 10 } }),
					-- a CONTENT button draws no text of its own: it must not be
					-- given a size it never paints
					UI.Button({ id = "Content", label = "Content", children = { UI.Text({ id = "In", text = "x" }) } }),
				},
			})
		end)
		local neutral = snapshot.neutral()
		expect(adapter.node("/S/T").props.textSize).toBe(neutral.type.body.size)
		expect(adapter.node("/S/B").props.textSize).toBe(neutral.type.control.size)
		expect(adapter.node("/S/Plain").props.textSize).toBeNil()
		expect(adapter.node("/S/Content").props.textSize).toBeNil()
		-- ...and it is the SAME number the measure seam used: one table, both seams
		expect(snapshot.intrinsicTextSize(neutral, "Button")).toBe(neutral.type.control.size)
		expect(snapshot.intrinsicTextSize(neutral, "TextField")).toBe(neutral.type.control.size)
		expect(snapshot.intrinsicTextSize(neutral, "Toggle")).toBe(neutral.type.body.size)
		expect(snapshot.intrinsicTextSize(neutral, "Box")).toBeNil()
	end)

	it("a package that moves the control role moves the DRAWN button label", function()
		-- the compact-pointer shape, reduced: a 13px control role. Before the fix
		-- the adapter drew 16 here no matter what the package said.
		local pkg = require("../examples/themes/compact_pointer").build(LuauUI.themes)
		local snap = snapshot.resolve(pkg, nil, {})
		local _, env, _, adapter, controller = world(function()
			return UI.Screen({ id = "S", padding = 0, children = { UI.Button({ id = "B", label = "Play" }) } })
		end)
		expect(adapter.node("/S/B").props.textSize).toBe(snapshot.neutral().type.control.size)
		env:set("themeMetrics", snap)
		controller.refresh()
		expect(adapter.node("/S/B").props.textSize).toBe(snap.type.control.size)
		expect(snap.type.control.size ~= snapshot.neutral().type.control.size).toBe(true)
	end)

	it("spacing steps resolve for gap and padding", function()
		local _, _, _, adapter = world(function()
			return UI.Screen({
				id = "S",
				padding = "m",
				gap = "s",
				children = {
					UI.Box({ id = "A", width = { type = "fixed", px = 10 }, height = { type = "fixed", px = 10 } }),
					UI.Box({ id = "B", width = { type = "fixed", px = 10 }, height = { type = "fixed", px = 10 } }),
				},
			})
		end)
		expect(adapter.node("/S/A").rect.x).toBe(defaultStyle.space.m)
		expect(adapter.node("/S/B").rect.y - adapter.node("/S/A").rect.y).toBe(10 + defaultStyle.space.s)
	end)

	it("a metric path resolves inside a dimension, and its negation inside an offset", function()
		local _, _, _, adapter = world(function()
			return UI.Screen({
				id = "S",
				padding = 0,
				children = {
					UI.Anchor({
						id = "Host",
						width = { type = "fill", weight = 1 },
						height = { type = "fixed", px = "controls.popup.triggerHeight" },
						children = {
							UI.Box({
								id = "Pin",
								anchor = "right",
								offsetX = "-s",
								width = { type = "fixed", px = "controls.textInput.clearSize" },
								height = { type = "minMax", min = "targetSizes.minimum" },
							}),
						},
					}),
				},
			})
		end)
		expect(adapter.node("/S/Host").rect.h).toBe(40)
		expect(adapter.node("/S/Host/Pin").rect.w).toBe(28)
		expect(adapter.node("/S/Host/Pin").rect.h).toBe(44)
		-- pinned to the right edge and pulled in by one small step
		expect(adapter.node("/S/Host/Pin").rect.x).toBe(800 - 28 - defaultStyle.space.s)
	end)

	it("the solver's measure path resolves a role handed straight to it", function()
		local byRole = solver.solve(
			{ kind = "text", id = "T", text = "Volume", textSize = "heading" },
			{ w = 400, h = 400 }
		)
		local byNumber = solver.solve(
			{ kind = "text", id = "T", text = "Volume", textSize = defaultStyle.type.heading },
			{ w = 400, h = 400 }
		)
		expect(byRole.rects["T"].rect.w).toBe(byNumber.rects["T"].rect.w)
		expect(byRole.rects["T"].rect.h).toBe(byNumber.rects["T"].rect.h)
	end)

	it("the solver measures against the snapshot it is HANDED, not a global", function()
		local big = derive(
			{ typography = { body = { font = { family = "BuilderSans" }, size = 32, lineHeight = 1.2 } } },
			"big-body"
		)
		local neutral = solver.solve(
			{ kind = "text", id = "T", text = "Volume", textSize = "body" },
			{ w = 400, h = 400 }
		)
		local themed = solver.solve(
			{ kind = "text", id = "T", text = "Volume", textSize = "body" },
			{ w = 400, h = 400 },
			{ metrics = big }
		)
		expect(themed.rects["T"].rect.h > neutral.rects["T"].rect.h).toBe(true)
	end)
end)

describe("a themeMetrics commit RE-SOLVES a mounted screen — never a rebuild", function()
	local function screen(core: any)
		return UI.Screen({
			id = "S",
			padding = 0,
			gap = "m",
			children = {
				UI.Text({ id = "Title", text = "Settings", textSize = "title" }),
				UI.Button({ id = "Go", label = "Go", height = { type = "minMax", min = "targetSizes.minimum" } }),
			},
		})
	end

	it("new metrics move the geometry with zero factory reruns, creates or removes", function()
		local _, env, root, adapter, controller = world(screen)
		local titleBefore = adapter.node("/S/Title").rect.h
		local buttonBefore = adapter.node("/S/Go").rect.h
		local gapBefore = adapter.node("/S/Go").rect.y - (adapter.node("/S/Title").rect.y + titleBefore)
		local factoryRunsBefore = root.counters().factoryRuns
		local mountedBefore = root.counters().mounted
		local createsBefore = controller.stats().creates
		adapter.takeOps()

		env:set(
			"themeMetrics",
			derive({
				typography = { title = { font = { family = "BuilderSans" }, size = 40, lineHeight = 1.2 } },
				space = { m = 40 },
				targetSizes = { minimum = 60 },
			}, "roomy")
		)
		controller.refresh()

		-- the layout actually changed, on all three axes the theme touched
		expect(adapter.node("/S/Title").rect.h > titleBefore).toBe(true)
		expect(adapter.node("/S/Go").rect.h).toBe(60)
		expect(adapter.node("/S/Go").rect.h > buttonBefore).toBe(true)
		local gapAfter = adapter.node("/S/Go").rect.y
			- (adapter.node("/S/Title").rect.y + adapter.node("/S/Title").rect.h)
		expect(gapAfter).toBe(40)
		expect(gapAfter > gapBefore).toBe(true)
		-- ...and NOTHING was rebuilt: mount identity, focus, selection, scroll and
		-- text entry all survive because no node was touched structurally
		expect(root.counters().factoryRuns).toBe(factoryRunsBefore)
		expect(root.counters().mounted).toBe(mountedBefore)
		expect(controller.stats().creates).toBe(createsBefore)
		expect(controller.stats().removes).toBe(0)
	end)

	it("the paint seam follows the same commit, so painted size tracks measured size", function()
		local _, env, _, adapter, controller = world(screen)
		expect(adapter.node("/S/Title").props.textSize).toBe(defaultStyle.type.title)
		env:set(
			"themeMetrics",
			derive({
				typography = { title = { font = { family = "BuilderSans" }, size = 40, lineHeight = 1.2 } },
			}, "big-title")
		)
		controller.refresh()
		expect(adapter.node("/S/Title").props.textSize).toBe(40)
	end)

	it("a themed target floor raises the enforced HIT rect (floors clamp up)", function()
		local _, env, _, adapter, controller = world(function()
			return UI.Screen({
				id = "S",
				padding = 0,
				children = {
					UI.Button({
						id = "Tiny",
						label = "x",
						width = { type = "fixed", px = 20 },
						height = { type = "fixed", px = 20 },
					}),
				},
			})
		end)
		expect(adapter.hitRectOf("/S/Tiny").w).toBe(44)
		env:set("themeMetrics", derive({ targetSizes = { minimum = 60 } }, "big-targets"))
		controller.refresh()
		expect(adapter.hitRectOf("/S/Tiny").w).toBe(60)
		expect(adapter.hitRectOf("/S/Tiny").h).toBe(60)
		-- the VISUAL rect is untouched: flooring the painted size would silently
		-- rewrite shipped design (B-BTN3)
		expect(adapter.node("/S/Tiny").rect.w).toBe(20)
	end)
end)

describe("closed-set validation for the semantic prop forms", function()
	it("an unknown typography role is a construction error naming the vocabulary", function()
		local ok, err = pcall(function()
			UI.Text({ id = "T", text = "x", textSize = "subtitle" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "body", 1, true) ~= nil).toBe(true)
	end)

	it("an unknown spacing step on gap or padding is a construction error", function()
		expect(function()
			UI.VStack({ id = "V", gap = "enormous" })
		end).toThrow()
		expect(function()
			UI.VStack({ id = "V", padding = "enormous" })
		end).toThrow()
		expect(function()
			UI.VStack({ id = "V", padding = { left = "enormous" } })
		end).toThrow()
	end)

	it("an unknown metric path inside a dimension or an offset is a construction error", function()
		expect(function()
			UI.Box({ id = "B", width = { type = "fixed", px = "controls.slider.nope" } })
		end).toThrow()
		expect(function()
			UI.Box({ id = "B", offsetY = "controls.nope.nope" })
		end).toThrow()
	end)

	it("literal numbers stay legal everywhere — the documented theme-independent escape", function()
		expect(function()
				UI.VStack({
					id = "V",
					gap = 7,
					padding = { left = 3 },
					offsetX = -5,
					children = { UI.Text({ id = "T", text = "x", textSize = 13 }) },
				})
			end)
			.never()
			.toThrow()
	end)
end)

describe("text_metrics: canonical font-descriptor keys (ADR-0019 §6)", function()
	it("a short family name and its full descriptor are ONE key", function()
		text_metrics.resetCalibration()
		text_metrics.resetMeasured()
		text_metrics.calibrate("BuilderSans", 0.5)
		expect(text_metrics.calibrationTable()["BuilderSans#Regular#Normal"]).toBe(0.5)
		expect(text_metrics.calibrationTable()["BuilderSans"]).toBe(0.5) -- alias mirrored back
		text_metrics.calibrate("BuilderSans#Regular#Normal", 0.4)
		expect(text_metrics.calibrationTable()["BuilderSans"]).toBe(0.4)
		text_metrics.resetCalibration()
	end)

	it("measured word widths are shared between the alias and the descriptor", function()
		text_metrics.resetMeasured()
		expect(text_metrics.setMeasured("BuilderSans", 16, "Volume", 45)).toBe(true)
		expect(text_metrics.measuredWidth("BuilderSans#Regular#Normal", 16, "Volume")).toBe(45)
		expect(text_metrics.measure("Volume", "BuilderSans#Regular#Normal", 16, math.huge).width).toBe(45)
		text_metrics.resetMeasured()
	end)

	it("another WEIGHT of a known family is a different, uncalibrated descriptor", function()
		text_metrics.resetMeasured()
		local regular = text_metrics.measure("Volume", "BuilderSans", 16, math.huge)
		local bold = text_metrics.measure("Volume", "BuilderSans#Bold#Normal", 16, math.huge)
		expect(regular.state).toBe("ready")
		-- an unknown descriptor takes the conservative full-em path: never clips
		expect(bold.state).toBe("pending")
		expect(bold.width > regular.width).toBe(true)
	end)

	it("lineHeight is per call and defaults to the historic 1.2", function()
		text_metrics.resetMeasured()
		local implied = text_metrics.measure("Volume", "BuilderSans", 20, math.huge)
		local explicit = text_metrics.measure("Volume", "BuilderSans", 20, math.huge, 1.2)
		local roomy = text_metrics.measure("Volume", "BuilderSans", 20, math.huge, 1.6)
		expect(explicit.height).toBe(implied.height)
		expect(roomy.height).toBe(math.ceil(20 * 1.6))
		-- garbage is ignored rather than trusted (the seam enforces its own safety)
		expect(text_metrics.measure("Volume", "BuilderSans", 20, math.huge, 0 / 0).height).toBe(implied.height)
		expect(text_metrics.measure("Volume", "BuilderSans", 20, math.huge, -1).height).toBe(implied.height)
	end)

	it("a role's line height reaches the measurer through the layout node", function()
		local tight = solver.solve({ kind = "text", id = "T", text = "Volume", textSize = 20 }, { w = 400, h = 400 })
		local roomy = solver.solve(
			{ kind = "text", id = "T", text = "Volume", textSize = 20, lineHeight = 2 },
			{ w = 400, h = 400 }
		)
		expect(roomy.rects["T"].rect.h > tight.rects["T"].rect.h).toBe(true)
	end)
end)

-- ===== the compatibility bar ==============================================
-- Every migrated control, solved under the DEFAULT (neutral) snapshot, must
-- report the exact geometry it reported before it spoke roles. These assertions
-- pin the effective value of each literal the migration replaced.

describe("migrated controls: byte-parity under Studio Neutral", function()
	local function controlWorld(build: (core: any) -> any)
		return world(function(core)
			return UI.Screen({ id = "S", padding = 0, children = { build(core) } })
		end, 800, 900)
	end

	it("Slider: 44px track, 20px thumb, 6px rail, 16px label gap, 40px readout", function()
		local core, _, _, adapter = controlWorld(function(core)
			return LuauUI.newSlider(
				LuauUI,
				core,
				{ id = "V", label = "Volume", value = core:signal(5), min = 0, max = 10 }
			).blueprint
		end)
		expect(core ~= nil).toBe(true)
		expect(adapter.node("/S/V/TrackHost").rect.h).toBe(44)
		expect(adapter.node("/S/V/TrackHost/Groove/Thumb").rect.w).toBe(20)
		expect(adapter.node("/S/V/TrackHost/Groove/Thumb").rect.h).toBe(20)
		expect(adapter.node("/S/V/TrackHost/Groove/Rail").rect.h).toBe(6)
		expect(adapter.node("/S/V/TrackHost/Groove/Fill").rect.h).toBe(6)
		expect(adapter.node("/S/V/Label").props.textSize).toBe(16)
		expect(adapter.node("/S/V/Value").props.textSize).toBe(16)
		expect(adapter.node("/S/V/Value").rect.w >= 40).toBe(true)
		-- the label -> track gap is the `m` step (16), not the generic `s`
		local label = adapter.node("/S/V/Label").rect
		expect(adapter.node("/S/V/TrackHost").rect.x - (label.x + label.w)).toBe(16)
	end)

	it("ProgressView: 6px track, 20px row floor, 14px label text, 8px row gap", function()
		local _, _, _, adapter = controlWorld(function(core)
			return LuauUI.newProgressView(LuauUI, core, { id = "P", label = "Load", value = 0.5, showValue = true }).blueprint
		end)
		expect(adapter.node("/S/P/Bar").rect.h).toBe(6)
		expect(adapter.node("/S/P").rect.h >= 20).toBe(true)
		expect(adapter.node("/S/P/Label").props.textSize).toBe(14)
		local label = adapter.node("/S/P/Label").rect
		expect(adapter.node("/S/P/Bar").rect.x - (label.x + label.w)).toBe(8)
	end)

	it("PopupButton: 40px trigger, and 36/44/56 rows per presentation", function()
		local _, _, adapter, presenter = presentedWorld(function(core)
			return LuauUI.newPopupButton(LuauUI, core, {
				id = "M",
				options = { { id = "a", label = "Alpha" }, { id = "b", label = "Beta" } },
				value = core:signal("a"),
				presentation = "menu",
			}).blueprint
		end)
		expect(adapter.node("/S/M/Trigger").rect.h).toBe(40)
		adapter.tap("/S/M/Trigger")
		presenter.refresh()
		expect(adapter.node("/S/M/PopupWhen/then/Popup/Opt-a").rect.h).toBe(36)
		-- the panel sits exactly one trigger height below the trigger
		expect(adapter.node("/S/M/PopupWhen/then/Popup").rect.y - adapter.node("/S/M").rect.y).toBe(40)
	end)

	it("PopupButton inline rows are 44 and sheet rows are 56", function()
		for presentation, height in { inline = 44, sheet = 56 } do
			local _, _, adapter, presenter = presentedWorld(function(core)
				return LuauUI.newPopupButton(LuauUI, core, {
					id = "M",
					options = { { id = "a", label = "Alpha" } },
					value = core:signal("a"),
					presentation = presentation,
				}).blueprint
			end)
			adapter.tap("/S/M/Trigger")
			presenter.refresh()
			expect(adapter.node("/S/M/PopupWhen/then/Popup/Opt-a").rect.h).toBe(height)
		end
	end)

	it("TextInput: 44px field, 28px clear button inset 8px from the right edge", function()
		local _, _, _, adapter = controlWorld(function(core)
			return LuauUI.newTextInput(LuauUI, core, {
				id = "F",
				value = core:signal("Ada"),
				placeholder = "name",
				clearButton = true,
			}).blueprint
		end)
		expect(adapter.node("/S/F").rect.h).toBe(44)
		local clear = adapter.node("/S/F/ClearWhen/then/Clear").rect
		expect(clear.w).toBe(28)
		expect(clear.h).toBe(28)
		expect(adapter.node("/S/F").rect.x + adapter.node("/S/F").rect.w - (clear.x + clear.w)).toBe(8)
	end)

	it("Toggle: 28px minimum height and the 44+12+16 track reservation", function()
		local _, _, _, adapter = controlWorld(function(core)
			return UI.Toggle({ id = "T", label = "Music", value = core:signal(true) })
		end)
		expect(adapter.node("/S/T").rect.h >= 28).toBe(true)
		-- the measured box = label + right-hand track reservation (44 track,
		-- 12 inset, 16 label margin) + the 12px left inset
		local plain = solver.solve({ kind = "text", id = "L", text = "Music", textSize = 16 }, { w = 800, h = 900 })
		expect(adapter.node("/S/T").rect.w).toBe(plain.rects["L"].rect.w + 12 + 44 + 12 + 16)
	end)

	it("Stepper: square 44px buttons, 32px readout, 8px row gap, 16px label", function()
		local _, _, _, adapter = controlWorld(function(core)
			return LuauUI.newStepper(LuauUI, core, {
				id = "C",
				label = "Count",
				value = core:signal(3),
				min = 0,
				max = 9,
				step = 1,
			}).blueprint
		end)
		-- the floor bites on the NARROW axis (a "−" is far thinner than 44); the
		-- height grows past it with the 18px label plus the 12px button padding,
		-- exactly as it did before the migration
		expect(adapter.node("/S/C/Dec").rect.w).toBe(44)
		expect(adapter.node("/S/C/Dec").rect.h).toBe(46)
		expect(adapter.node("/S/C/Inc").rect.w).toBe(44)
		expect(adapter.node("/S/C/Value").rect.w).toBe(32)
		expect(adapter.node("/S/C/Label").props.textSize).toBe(16)
		expect(adapter.node("/S/C/Value").rect.x - (adapter.node("/S/C/Dec").rect.x + 44)).toBe(8)
	end)

	it("Chip, DisclosureGroup and Picker rows all sit on the 44px target floor", function()
		local _, _, _, chip = controlWorld(function(core)
			return LuauUI.newChip(LuauUI, core, { id = "C", label = "Tag", selected = core:signal(false) }).blueprint
		end)
		expect(chip.node("/S/C").rect.h).toBe(46) -- the 44 floor plus the button's own text box

		local _, _, _, group = controlWorld(function(core)
			return LuauUI.newDisclosureGroup(LuauUI, core, {
				id = "D",
				label = "More",
				expanded = core:signal(false),
				content = function()
					return UI.Text({ id = "B", text = "x" })
				end,
			}).blueprint
		end)
		expect(group.node("/S/D/Header").rect.h).toBe(46)

		local _, _, _, picker = controlWorld(function(core)
			return LuauUI.newPicker(LuauUI, core, {
				id = "Q",
				label = "Quality",
				options = { { label = "Low", value = "low" }, { label = "High", value = "high" } },
				selected = core:signal("low"),
			}).blueprint
		end)
		expect(picker.node("/S/Q/Options/Opt1").rect.h).toBe(46)
		-- a two-option picker is segmented, so the `xs` step separates them across
		local opt1 = picker.node("/S/Q/Options/Opt1").rect
		expect(picker.node("/S/Q/Options/Opt2").rect.x - (opt1.x + opt1.w)).toBe(defaultStyle.space.xs)
		expect(picker.node("/S/Q/Label").props.textSize).toBe(14)
	end)

	it("Label: 20px icon, 6px gap, 16px title", function()
		local _, _, _, adapter = controlWorld(function(core)
			return LuauUI.newLabel(LuauUI, core, { id = "L", title = "Save", icon = "rbxassetid://1" }).blueprint
		end)
		expect(adapter.node("/S/L/Icon").rect.w).toBe(20)
		expect(adapter.node("/S/L/Icon").rect.h).toBe(20)
		expect(adapter.node("/S/L/Title").props.textSize).toBe(16)
		local icon = adapter.node("/S/L/Icon").rect
		expect(adapter.node("/S/L/Title").rect.x - (icon.x + icon.w)).toBe(6)
	end)

	it("renderer defaults: Text 16, Button 18 with 12px padding, TextField 18", function()
		local _, _, _, adapter = world(function()
			return UI.Screen({
				id = "S",
				padding = 0,
				children = {
					UI.Text({ id = "T", text = "Volume" }),
					UI.Button({ id = "B", label = "Save" }),
					UI.TextField({ id = "F", placeholder = "name" }),
					UI.Divider({ id = "D" }),
				},
			})
		end)
		local plain16 = solver.solve({ kind = "text", id = "L", text = "Volume", textSize = 16 }, { w = 800, h = 600 })
		expect(adapter.node("/S/T").rect.w).toBe(plain16.rects["L"].rect.w)
		local plain18 = solver.solve({ kind = "text", id = "L", text = "Save", textSize = 18 }, { w = 800, h = 600 })
		expect(adapter.node("/S/B").rect.w).toBe(plain18.rects["L"].rect.w + 24) -- 12px padding either side
		expect(adapter.node("/S/B").props.padding).toBe(12)
		local plainField = solver.solve({ kind = "text", id = "L", text = "name", textSize = 18 }, { w = 800, h = 600 })
		expect(adapter.node("/S/F").rect.w).toBe(plainField.rects["L"].rect.w + 24)
		expect(adapter.node("/S/D").rect.h).toBe(1) -- the hairline stroke weight
	end)

	it("AsyncImage: the default 48px square", function()
		local _, _, _, adapter = controlWorld(function(core)
			-- `{ load = … }` used to sit here: a key the provider never had, accepted
			-- and ignored for the life of this test. The transport is driven through
			-- `pendingRequests`/`complete`, never a `load` callback (ARCH-1).
			local provider = LuauUI.newResourceProvider(core)
			return LuauUI.newAsyncImage(LuauUI, core, {
				id = "I",
				provider = provider,
				scope = core:scope("img"),
				key = "rbxassetid://1",
			}).blueprint
		end)
		expect(adapter.node("/S/I").rect.w).toBe(48)
		expect(adapter.node("/S/I").rect.h).toBe(48)
	end)

	it("Table: 28px header, 15px cell text, 2px row gap, 8px cell inset", function()
		local _, _, _, adapter = world(function(core)
			local control = LuauUI.newTable(LuauUI, core, {
				id = "T",
				rows = core:signal({ { id = "a", name = "Apex" } }),
				key = function(row: any)
					return row.id
				end,
				rowHeight = 32,
				columns = {
					{
						id = "name",
						title = "Name",
						width = { type = "fill", weight = 1 },
						value = function(row: any)
							return row.name
						end,
					},
				},
			})
			return UI.Screen({ id = "S", padding = 0, children = { control.blueprint } })
		end)
		expect(adapter.node("/S/T/Main/Header/Head-name").rect.h).toBe(28)
		expect(adapter.node("/S/T/Main/Header/Head-name/Title").props.textSize).toBe(14)
		local header = adapter.node("/S/T/Main/Header").rect
		expect(adapter.node("/S/T/Main/Body").rect.y - (header.y + header.h)).toBe(2)
	end)
end)
