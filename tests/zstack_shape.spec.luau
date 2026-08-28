--!strict
-- THE CIRCLE SHAPE, GENERALIZED FROM BUTTON TO ZSTACK (task PAINT, director
-- item 12: OddOverlapNotRound.png + whatisthis.png — "circles need a better
-- approach than what we have"). `tests/button_shape.spec.luau` proved the
-- doctrine on `UI.Button`; this file proves the SAME guarantee reaches
-- `UI.ZStack`, which is the primitive a `UI.Path`-based ring/disc composite
-- (this round's Glade supply rings) is actually built from.
--
-- What generalized and what did not, and this file's job is to prove each:
--
--   1. the SCHEMA BOUNDARY accepts `shape` on ZStack with the same closed set,
--      the same non-reactive rule, the same STYLE authority — one shared spec,
--      not a second copy (`blueprint_schema.SHAPE`, promoted `authority.common`);
--   2. the SOLVER enforces the 1:1 box exactly as it does for a circle Button:
--      neither axis authored -> the control metric, one axis authored -> the
--      other follows, both authored -> refused at construction
--      (`assertCircleSquare`, shared with Button's own refusal — same message
--      shape, the class name substituted);
--   3. the PAINT side needed NO new rule: `sheet_model.classifyTags` and the
--      `.facet-shape-circle` phantom rules already read `shape` with no class
--      check at all (see `tests/button_shape.spec.luau`'s own paint section,
--      which this file does not repeat) — a ZStack that carries the tag gets
--      the identical corner treatment a circle Button does, for free.
--
-- Nothing existing may move: `shape` is absent from every ZStack that predates
-- it, and `check_flat_baseline` proves the flat render dump is unchanged.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local UI = require("../src/blueprint")
local customFactory = require("../src/core/custom")
local environment = require("../src/env/environment")
local mountLib = require("../src/mount")
local rendererLib = require("../src/render/renderer")
local authority = require("../src/render/authority")
local schema = require("../src/blueprint_schema")
local snapshot = require("../src/themes/snapshot")
local sheet_model = require("../src/tokens/sheet_model")
local fake_target = require("./lib/fake_target")

local CIRCLE_TAG = sheet_model.TAGS.shapePrefix .. "circle"

local function render(screen: any, metrics: any?, w: number?, h: number?)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = w or 400, h = h or 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	if metrics ~= nil then
		env:set("themeMetrics", metrics)
	end
	local root = mountLib.mount(core, screen)
	local adapter = fake_target.new()
	local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return adapter, controller, core
end

local function rectOf(adapter: any, path: string): any
	local node = adapter.node(path)
	return if node ~= nil then node.rect else nil
end

local function fails(fn: () -> ()): string
	local ok, err = pcall(fn)
	expect(ok).toBe(false)
	return tostring(err)
end

-- ===========================================================================
-- 1. THE SCHEMA BOUNDARY
-- ===========================================================================

describe("circle ZStack: the accept classes", function()
	it("takes shape = circle and constructs", function()
		local bp = UI.ZStack({ id = "Ring", shape = "circle" })
		expect(bp.props.shape).toBe("circle")
	end)

	it("takes shape = rect explicitly, which is what every ZStack already was", function()
		expect(UI.ZStack({ id = "Z", shape = "rect" }).props.shape).toBe("rect")
	end)

	it("leaves an ordinary ZStack untouched: no shape prop at all", function()
		expect(UI.ZStack({ id = "Z" }).props.shape).toBe(nil)
	end)

	it("takes ONE authored axis on either side", function()
		expect(UI.ZStack({ id = "W", shape = "circle", width = { type = "fixed", px = 56 } }) ~= nil).toBe(true)
		expect(UI.ZStack({ id = "H", shape = "circle", height = { type = "fixed", px = 34 } }) ~= nil).toBe(true)
	end)
end)

describe("circle ZStack: the reject classes name the field, the rule and the fix", function()
	it("refuses BOTH authored axes — the same rule the circle Button refuses by", function()
		local err = fails(function()
			UI.ZStack({
				id = "Z",
				shape = "circle",
				width = { type = "fixed", px = 56 },
				height = { type = "fixed", px = 56 },
			})
		end)
		expect(string.find(err, "UI.ZStack", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "at most ONE of", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "1:1", 1, true) ~= nil).toBe(true)
	end)

	it("refuses an unknown shape with the closed set", function()
		local err = fails(function()
			UI.ZStack({ id = "Z", shape = "pill" })
		end)
		expect(string.find(err, "circle", 1, true) ~= nil).toBe(true)
	end)

	it("refuses a REACTIVE shape: a shape is what the container is, not a state it passes through", function()
		local core = customFactory.new()
		local err = fails(function()
			UI.ZStack({ id = "Z", shape = core:signal("circle") })
		end)
		expect(string.find(err, "Signal/Memo", 1, true) ~= nil).toBe(true)
	end)
end)

describe("circle ZStack: the schema declares it the way the parity checker requires, sharing Button's spec", function()
	it(
		"shape is a closed style-authority set that is not reactive, and it is the SAME spec object as Button's",
		function()
			local zstackSpec = (schema.forClass("ZStack") :: any).props.shape
			local buttonSpec = (schema.forClass("Button") :: any).props.shape
			expect(zstackSpec.reactive).toBe(false)
			expect(zstackSpec.channel).toBe("style")
			expect(table.concat(zstackSpec.enum, "|")).toBe("rect|circle")
			expect(zstackSpec).toBe(buttonSpec) -- one shared PropSpec, not a copy that can drift
			expect(authority.authorityFor("ZStack", "shape")).toBe("style")
		end
	)

	it("promoting shape to `common` did not move Button's own authority", function()
		expect(authority.authorityFor("Button", "shape")).toBe("style")
	end)
end)

-- ===========================================================================
-- 2. THE SOLVER ENFORCES THE SQUARE (identical to the circle Button)
-- ===========================================================================

describe("circle ZStack geometry: a true 1:1 box from the control metric", function()
	it("with neither axis authored, both come from controls.button.height", function()
		local adapter = render(UI.Screen({
			id = "S",
			children = { UI.ZStack({ id = "Ring", shape = "circle" }) },
		}))
		local rect = rectOf(adapter, "/S/Ring")
		expect(rect.w).toBe(44)
		expect(rect.h).toBe(44)
	end)

	it("an authored WIDTH drives the height, and an authored HEIGHT drives the width", function()
		local adapter = render(UI.Screen({
			id = "S",
			children = {
				UI.ZStack({ id = "W", shape = "circle", width = { type = "fixed", px = 56 } }),
				UI.ZStack({ id = "H", shape = "circle", height = { type = "fixed", px = 34 } }),
			},
		}))
		expect(rectOf(adapter, "/S/W").w).toBe(56)
		expect(rectOf(adapter, "/S/W").h).toBe(56)
		expect(rectOf(adapter, "/S/H").w).toBe(34)
		expect(rectOf(adapter, "/S/H").h).toBe(34)
	end)

	it(
		"a FILL width still squares: the paired axis takes the extent the parent offered (the aspect+fill pairing)",
		function()
			local adapter = render(
				UI.Screen({
					id = "S",
					padding = 0,
					children = {
						UI.HStack({
							id = "Row",
							width = { type = "fixed", px = 120 },
							children = {
								UI.ZStack({ id = "Big", shape = "circle", width = { type = "fill", weight = 1 } }),
							},
						}),
					},
				}),
				nil,
				300,
				300
			)
			local rect = rectOf(adapter, "/S/Row/Big")
			expect(rect.w).toBe(120)
			expect(rect.h).toBe(120)
		end
	)

	it("a rectangular ZStack is byte-unchanged: no shape prop, no square enforcement", function()
		local adapter = render(UI.Screen({
			id = "S",
			children = {
				UI.ZStack({
					id = "Z",
					width = { type = "fixed", px = 200 },
					height = { type = "fixed", px = 40 },
				}),
			},
		}))
		local rect = rectOf(adapter, "/S/Z")
		expect(rect.w).toBe(200)
		expect(rect.h).toBe(40)
	end)

	it(
		"a metric package with a bigger button height makes a bigger circle ZStack too — one metric, two consumers",
		function()
			local pkg = (require("../src/themes/package") :: any).define({
				base = snapshot.neutralPackage(),
				identity = {
					id = "zstack-circle-test",
					displayName = "ZStack Circle Test",
					schemaVersion = (require("../src/themes/package") :: any).SCHEMA,
					version = "1.0.0",
				},
				metrics = { controls = { button = { height = 64 } } },
			})
			local metrics = snapshot.resolve(pkg, nil, {})
			local adapter =
				render(UI.Screen({ id = "S", children = { UI.ZStack({ id = "Ring", shape = "circle" }) } }), metrics)
			expect(rectOf(adapter, "/S/Ring").w).toBe(64)
			expect(rectOf(adapter, "/S/Ring").h).toBe(64)
		end
	)
end)

-- ===========================================================================
-- 3. THE PAINT SIDE NEEDED NO NEW RULE (already class-agnostic)
-- ===========================================================================

describe("circle ZStack paint: the SAME phantom rule a circle Button uses, no new sheet code", function()
	it("classifyTags earns facet-shape-circle from the prop alone — no class field even accepted", function()
		expect(sheet_model.classifyTags({ shape = "circle" })[CIRCLE_TAG]).toBe(true)
		expect(sheet_model.classifyTags({ shape = "rect" })[CIRCLE_TAG]).toBe(nil)
	end)

	it("the render tree's ZStack node carries the shape prop through to the adapter, same as Button's", function()
		local adapter = render(UI.Screen({
			id = "S",
			children = { UI.ZStack({ id = "Ring", shape = "circle" }) },
		}))
		expect(adapter.node("/S/Ring").props.shape).toBe("circle")
	end)
end)
