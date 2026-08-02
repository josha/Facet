--!strict
-- Milestone 0 — trustworthy authoring (docs/plans/swiftui-parity-next.md
-- investment 1; acceptance rows M0-A1..A7).
--
-- Before this milestone the blueprint layer accepted ANY key into a node's
-- prop bag. Every case in section A below used to CONSTRUCT successfully and
-- then quietly do nothing, which is the worst failure mode for agent-written
-- screens: the tree looks right and the behavior is missing.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local schema = require("../src/blueprint_schema")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local contribution = require("../src/input/contribution")
local controlContract = require("../src/controls/contract")
local registry = require("./conformance/controls_registry")
local LuauUI = require("../src") :: any
local fake_target = require("../tests/lib/fake_target")
local propParity = require("../tools/lune/check_prop_parity")

-- capture the error message of a construction that must fail
local function failure(fn: () -> any): string
	local ok, err = pcall(fn)
	expect(ok).toBe(false)
	return tostring(err)
end

local function contains(haystack: string, needle: string): boolean
	return string.find(haystack, needle, 1, true) ~= nil
end

describe("M0-A1: invalid authoring fails at construction", function()
	it("an unknown property names the control, the property, and the valid alternatives", function()
		local err = failure(function()
			return UI.Button({ id = "B", label = "Save", enabledd = true })
		end)
		expect(contains(err, "UI.Button")).toBe(true)
		expect(contains(err, "unknown property 'enabledd'")).toBe(true)
		expect(contains(err, "Valid properties:")).toBe(true)
	end)

	it("a misspelled property suggests the intended one", function()
		local err = failure(function()
			return UI.Button({ id = "B", lable = "Save" })
		end)
		expect(contains(err, "Did you mean 'label'")).toBe(true)
	end)

	it("a property borrowed from another control is rejected, not silently frozen in", function()
		-- `columns` is a Grid property; on a VStack it used to freeze into the
		-- node and be ignored by the solver
		local err = failure(function()
			return UI.VStack({ id = "V", columns = 3 })
		end)
		expect(contains(err, "unknown property 'columns'")).toBe(true)
	end)

	it("a wrongly typed value names the expected type and the property's purpose", function()
		local err = failure(function()
			return UI.VStack({ id = "V", gap = "8" })
		end)
		expect(contains(err, "expects number")).toBe(true)
		expect(contains(err, "got string")).toBe(true)
	end)

	it("a bare number where a dimension belongs explains the dimension table", function()
		local err = failure(function()
			return UI.Box({ id = "X", width = 120 })
		end)
		expect(contains(err, "expects dim")).toBe(true)
		expect(contains(err, '{ type = "fixed", px = 120 }')).toBe(true)
	end)

	it("an unknown dimension kind is rejected", function()
		local err = failure(function()
			return UI.Box({ id = "X", width = { type = "flex", px = 10 } })
		end)
		expect(contains(err, "fixed|content|hug|fill|percent|minMax|aspect")).toBe(true)
	end)

	it("a bad padding side is rejected", function()
		local err = failure(function()
			return UI.VStack({ id = "V", padding = { top = 4, botom = 4 } })
		end)
		expect(contains(err, "unknown side 'botom'")).toBe(true)
	end)

	it("a Signal on a prop that is read once at mount is rejected", function()
		local core = customFactory.new()
		local err = failure(function()
			return UI.ScrollView({ id = "S", axis = core:signal("x") })
		end)
		expect(contains(err, "does not accept a Signal/Memo")).toBe(true)
	end)

	it("a missing required property names it and says what it is for", function()
		local err = failure(function()
			return UI.Text({ id = "T" })
		end)
		expect(contains(err, "UI.Text.text is required")).toBe(true)
		expect(contains(err, "the displayed string")).toBe(true)
	end)

	it("children on a leaf are rejected and the containers are listed", function()
		local err = failure(function()
			return UI.Text({ id = "T", text = "x", children = { UI.Box({ id = "c" }) } })
		end)
		expect(contains(err, "does not take children")).toBe(true)
		expect(contains(err, "Containers:")).toBe(true)
	end)

	it("When.condition must be a Signal/Memo, not a plain boolean", function()
		local err = failure(function()
			return UI.When({
				id = "W",
				condition = true,
				thenView = function()
					return UI.Box({ id = "c" })
				end,
			})
		end)
		expect(contains(err, "a Signal or Memo")).toBe(true)
	end)

	it("an unrecognised enum value is rejected with the closed value set", function()
		-- found LIVE: `surface = "panel"` is not a role, so it tagged the node
		-- with a selector no rule matched and the surface painted nothing. Two
		-- shipped controls carried the same mistake.
		local err = failure(function()
			return UI.VStack({ id = "V", surface = "panel" })
		end)
		expect(contains(err, "base | raised | control | chip | badge | accent | scrim | plain")).toBe(true)

		local err2 = failure(function()
			return UI.Text({ id = "T", text = "x", role = "title" })
		end)
		expect(contains(err2, "one of secondary")).toBe(true)

		local err3 = failure(function()
			return UI.ScrollView({ id = "S", axis = "vertical" })
		end)
		expect(contains(err3, "one of y | x")).toBe(true)

		local err4 = failure(function()
			return UI.Box({ id = "B", anchor = "topleft" })
		end)
		expect(contains(err4, "topLeft")).toBe(true)
	end)

	it("valid authoring is unaffected", function()
		local core = customFactory.new()
		local bp = UI.Screen({
			id = "S",
			padding = 12,
			gap = 8,
			children = {
				UI.Text({ id = "T", text = core:signal("hi"), textSize = 18, role = "secondary" }),
				UI.Button({ id = "B", label = "Go", enabled = core:signal(true) }),
				UI.Grid({ id = "G", minColumnWidth = 80, gap = 4, children = { UI.Box({ id = "c" }) } }),
			},
		})
		expect(bp.class).toBe("Screen")
		expect(#(bp.children :: any)).toBe(3)
	end)
end)

describe("M0-A4: diagnosed properties instead of silent drops", function()
	it("Text.color is diagnosed with its replacement instead of scheduling dropped paint work", function()
		local err = failure(function()
			return UI.Text({ id = "T", text = "x", color = { r = 1, g = 0, b = 0 } })
		end)
		expect(contains(err, "UI.Text.color is not supported")).toBe(true)
		expect(contains(err, "UI.Text{ role = … }")).toBe(true)
	end)

	it("Text.font is diagnosed because it reached measure but never paint", function()
		local err = failure(function()
			return UI.Text({ id = "T", text = "x", font = "Gotham" })
		end)
		expect(contains(err, "UI.Text.font is not supported")).toBe(true)
		expect(contains(err, "style authority")).toBe(true)
	end)

	it("every diagnosed property is in the ADR-0011 ledger with all required fields", function()
		local wanted = { ["UI.Text.color"] = false, ["UI.Text.font"] = false }
		for _, entry in LuauUI.DEPRECATIONS do
			expect(#entry.since > 0).toBe(true)
			expect(#entry.removeNoEarlierThan > 0).toBe(true)
			expect(#entry.replacement > 0).toBe(true)
			if wanted[entry.surface] ~= nil then
				wanted[entry.surface] = true
			end
		end
		for surface, found in wanted do
			if not found then
				error(`deprecation ledger is missing {surface}`)
			end
		end
	end)

	it("a reactive style hint is re-applied instead of being dropped by the refresh loop", function()
		-- REGRESSION: `surface`/`role` dirty "paint", but the refresh loop only
		-- re-applied BINDING_PROPS, so a bound surface repainted exactly never.
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		local surface = core:signal("panel")
		local root =
			mountLib.mount(core, UI.Screen({ id = "S", children = { UI.Box({ id = "X", surface = surface }) } }))
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, {})
		controller.initialRender()
		expect(adapter.node("/S/X").props.surface).toBe("panel")
		surface:set("raised")
		controller.refresh()
		expect(adapter.node("/S/X").props.surface).toBe("raised")
	end)

	it("a reactive `active` flag is re-applied instead of being dropped", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		local active = core:signal(false)
		local root =
			mountLib.mount(core, UI.Screen({ id = "S", children = { UI.VStack({ id = "P", active = active }) } }))
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, {})
		controller.initialRender()
		expect(adapter.node("/S/P").props.active).toBe(false)
		active:set(true)
		controller.refresh()
		expect(adapter.node("/S/P").props.active).toBe(true)
	end)
end)

describe("M0-A5: the extension seam is genuinely public", function()
	it("the input-contribution seam is exported from the library entry point", function()
		expect(type(LuauUI.contribution)).toBe("table")
		expect(type(LuauUI.contribution.attach)).toBe("function")
		expect(type(LuauUI.contribution.read)).toBe("function")
	end)

	it("an attached bundle rides the internal meta channel, never the public prop bag", function()
		local bundle = {
			handleActivate = function()
				return true
			end,
		}
		local root = contribution.attach(UI.VStack({ id = "Root" }), bundle)
		expect(root.props.__inputContribution).toBe(nil)
		expect(next(root.props)).toBe(nil) -- the public prop bag is untouched
		expect((root.meta :: any).inputContribution).toBe(bundle)
	end)

	it("mount carries meta through so the presenter still discovers the bundle", function()
		local core = customFactory.new()
		local bundle = {
			handleActivate = function()
				return true
			end,
		}
		local root = mountLib.mount(core, contribution.attach(UI.VStack({ id = "Root" }), bundle))
		expect(contribution.read(root.node)).toBe(bundle)
	end)

	it("a non-table value under the reserved key reads as no contribution", function()
		expect(contribution.read({ meta = { inputContribution = "nope" } })).toBe(nil)
		expect(contribution.read({})).toBe(nil)
	end)
end)

describe("M0-A6: every public constructor is visible to conformance", function()
	it("each UI.* constructor has a control contract and a registry row", function()
		local rowNames: { [string]: boolean } = {}
		for _, entry in registry do
			rowNames[entry.name] = true
		end
		for _, class in schema.classNames() do
			if controlContract.forClass(class) == nil then
				error(`UI.{class} has no control contract (src/controls/contract.luau)`)
			end
			if not rowNames[class] then
				error(`UI.{class} has no conformance registry row`)
			end
		end
	end)

	it("the previously invisible primitives are registered", function()
		for _, class in { "Anchor", "Grid", "Grip", "Path", "When", "ForEach", "ErrorBoundary" } do
			expect(controlContract.forClass(class) ~= nil).toBe(true)
		end
	end)

	it("Grip is registered as an INTERACTIVE control with a hit floor", function()
		local grip = controlContract.forClass("Grip") :: any
		expect(grip.focusRole).toBe("focusable")
		expect(grip.minHitSize >= 44).toBe(true)
		expect(#grip.actions > 0).toBe(true)
	end)

	it("every constructor's class exists in the schema and vice versa", function()
		for _, class in schema.classNames() do
			expect(type((UI :: any)[class])).toBe("function")
		end
		for key, value in UI :: any do
			if type(value) == "function" and string.upper(string.sub(key, 1, 1)) == string.sub(key, 1, 1) then
				if schema.forClass(key) == nil then
					error(`UI.{key} is a constructor with no schema class`)
				end
			end
		end
	end)
end)

describe("M0-A3: one reconciled property model", function()
	it("the live repository passes the property-parity check", function()
		local result = propParity.check()
		if not result.ok then
			error("prop parity: " .. table.concat(result.problems, " | "))
		end
		expect(result.counts.classes >= 19).toBe(true)
	end)

	it("it detects an undocumented property", function()
		local result = propParity.check({ dropDocsFor = "Grid.columns" })
		expect(result.ok).toBe(false)
	end)

	it("it detects a repainting property the refresh loop cannot re-apply", function()
		-- this is the exact drift that made reactive `surface` a no-op
		local result = propParity.check({ dropBindingProp = "selected" })
		expect(result.ok).toBe(false)
	end)

	it("the dirty map is derived from the schema for every class", function()
		local derived = schema.propDirty()
		for _, class in schema.classNames() do
			expect(derived[class] ~= nil).toBe(true)
			expect(UI.PROP_DIRTY[class] ~= nil).toBe(true)
		end
		expect(UI.PROP_DIRTY.Text.text[1]).toBe("paint")
	end)

	it("every reactive property declares dirty classes and vice versa", function()
		for _, class in schema.classNames() do
			for prop, spec in (schema.forClass(class) :: any).props do
				if spec.reactive then
					if spec.dirty == nil or #spec.dirty == 0 then
						error(`{class}.{prop} is reactive with no dirty class`)
					end
				elseif spec.dirty ~= nil then
					error(`{class}.{prop} declares dirty classes but is not reactive`)
				end
			end
		end
	end)
end)

describe("M0-A2: useful exported public types", function()
	it("every class exports a spec type carrying its schema fields", function()
		local source = require("@lune/fs").readFile("src/blueprint.luau")
		for _, class in schema.classNames() do
			if not contains(source, `export type {class}Spec`) then
				error(`UI.{class} has no exported {class}Spec type`)
			end
		end
	end)

	it("no public constructor takes a bare untyped spec", function()
		local source = require("@lune/fs").readFile("src/blueprint.luau")
		for _, class in schema.classNames() do
			if contains(source, `function blueprint.{class}(spec)`) then
				error(`UI.{class} still takes an untyped spec`)
			end
		end
	end)
end)
