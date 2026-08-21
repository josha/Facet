--!strict
-- Milestone 0 — trustworthy authoring (docs/plans/parity-next.md
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
local controlContract = require("../src/class_contract")
local registry = require("./conformance/controls_registry")
local Facet = require("../src") :: any
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
		for _, entry in Facet.DEPRECATIONS do
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
		local surface = core:signal("control")
		local root =
			mountLib.mount(core, UI.Screen({ id = "S", children = { UI.Box({ id = "X", surface = surface }) } }))
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, {})
		controller.initialRender()
		expect(adapter.node("/S/X").props.surface).toBe("control")
		surface:set("raised")
		controller.refresh()
		expect(adapter.node("/S/X").props.surface).toBe("raised")
	end)

	-- THE REACTIVE DOOR INTO THE CLOSED SET (found live 2026-08-06, tutorial
	-- example 05: thirty board tiles bound `surface` to "tileEmpty"/"tileCorrect"/…
	-- and every one rendered at BackgroundTransparency = 1).
	--
	-- The construction check above only sees a STATIC value. `tint` already refused
	-- a malformed bound value at the write site for exactly this reason; these pin
	-- the same rule for every enum prop, on the first render AND on a later set.
	it("a BOUND enum value outside the closed set is refused at the write site, not silently ignored", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		local surface = core:signal("tileEmpty")
		local root =
			mountLib.mount(core, UI.Screen({ id = "S", children = { UI.Box({ id = "X", surface = surface }) } }))
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, {})
		local err = failure(function()
			controller.initialRender()
			return nil
		end)
		expect(contains(err, "'tileEmpty' is not one of")).toBe(true)
		expect(contains(err, "base | raised | control | chip | badge | accent | scrim | plain")).toBe(true)
		expect(contains(err, "paints nothing")).toBe(true)
	end)

	it("...and a LATER set into an illegal value is refused too, so a valid first frame proves nothing", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		local surface = core:signal("control")
		local root =
			mountLib.mount(core, UI.Screen({ id = "S", children = { UI.Box({ id = "X", surface = surface }) } }))
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, {})
		controller.initialRender()
		expect(adapter.node("/S/X").props.surface).toBe("control")
		surface:set("tileCorrect")
		local err = failure(function()
			controller.refresh()
			return nil
		end)
		expect(contains(err, "'tileCorrect' is not one of")).toBe(true)
	end)

	it("a legal bound enum value on a NON-surface prop is unaffected", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		local role = core:signal("secondary")
		local root =
			mountLib.mount(core, UI.Screen({ id = "S", children = { UI.Text({ id = "T", text = "x", role = role }) } }))
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, {})
		controller.initialRender()
		expect(adapter.node("/S/T").props.role).toBe("secondary")
		role:set("content")
		controller.refresh()
		expect(adapter.node("/S/T").props.role).toBe("content")
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
		expect(type(Facet.contribution)).toBe("table")
		expect(type(Facet.contribution.attach)).toBe("function")
		expect(type(Facet.contribution.read)).toBe("function")
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
				error(`UI.{class} has no control contract (src/class_contract.luau)`)
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

	--[[ A COMMENT IS NOT A FIELD, AND THE SCANNER USED TO THINK IT WAS.

		`recordFields` walks a type body looking for `name:`, and a comment inside
		that body was ordinary text to it. A plain-language line of the natural
		shape `term: explanation` therefore invented a field on the type — and on
		every type that intersects it. Measured once for real: one reworded comment
		inside `BoxProps` invented `hide` on twenty-two spec types.

		This plants that exact shape and requires the checker to stay green. It
		reads the real file so the fixture cannot drift away from the type it is
		about. ]]
	it("a plain-language comment inside a record type is not read as a field", function()
		local source = require("@lune/fs").readFile("src/blueprint.luau")
		local anchor = "export type BoxProps = {"
		expect(string.find(source, anchor, 1, true) ~= nil).toBe(true)
		local planted = string.gsub(
			source,
			anchor,
			anchor .. "\n\t-- the space-reserving hide: keep the layout box, stop painting",
			1
		)
		expect(planted ~= source).toBe(true)
		local result = propParity.check({ blueprintOverride = planted })
		if not result.ok then
			error("a comment invented a field: " .. table.concat(result.problems, " | "))
		end
		expect(result.ok).toBe(true)
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

	-- VIEW 7 (ARCH-8): the renderer's private BINDING_PROP_CLASSES allowlist and
	-- authority.luau's per-class manifest are two records of the same fact, and
	-- nothing derived one from the other — so the F-19/BP-F12 defect (a solver-
	-- consumed prop dispatched as a binding write) could recur silently. Both
	-- directions of the disagreement are injected here.
	it("it detects a restricted class the authority manifest does not back", function()
		-- `Divider` is the real case: it CONSUMES thickness in the solver and
		-- declares no binding authority for it, so restricting the emit to Divider
		-- must be caught rather than shipped
		local result = propParity.check({ bindingPropClass = "thickness=Divider" })
		expect(result.ok).toBe(false)
		expect(table.concat(result.problems, " | "):find("Divider.thickness", 1, true) ~= nil).toBe(true)
	end)

	it("it detects a class left OUTSIDE a restriction that still claims the binding", function()
		-- restrict `thickness` to a class that does declare it a binding, leaving
		-- Path — which also declares it — outside: the allowlist would then be a
		-- lie about who may write it
		local result = propParity.check({ bindingPropClass = "tint=Image" })
		expect(result.ok).toBe(false)
		expect(table.concat(result.problems, " | "):find("Path.tint", 1, true) ~= nil).toBe(true)
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

-- ===========================================================================
-- api-architecture-consistency (0.8.0) — the blueprint-layer repairs.
-- Each block below pins one ruling from
-- artifacts/api-architecture-consistency/dispositions.md §A, and every one of
-- them started as a RED test against the shipped behaviour recorded in
-- ledger/blueprints.md.
-- ===========================================================================

describe("F-6 (BP-F5): the schema authority tables are frozen", function()
	it("a consumer of the tooling seam cannot disable framework validation", function()
		local all = schema.all()
		expect(pcall(function()
			(all.Text.props.text :: any).required = false
		end)).toBe(false)
		expect(pcall(function()
			(all.Text.props :: any).invented = {}
		end)).toBe(false)
		expect(pcall(function()
			(all :: any).Invented = {}
		end)).toBe(false)
		-- ...and the rule the mutation was reaching for still bites
		expect(pcall(function()
			return UI.Text({})
		end)).toBe(false)
	end)

	it("forClass hands out the same deeply frozen spec", function()
		local spec = schema.forClass("Divider") :: any
		expect(table.isfrozen(spec)).toBe(true)
		expect(table.isfrozen(spec.props)).toBe(true)
		expect(table.isfrozen(spec.props.thickness)).toBe(true)
		expect(table.isfrozen(spec.props.thickness.types)).toBe(true)
		expect(table.isfrozen(spec.props.thickness.dirty)).toBe(true)
		expect(table.isfrozen((schema.forClass("VStack") :: any).props.surface.enum)).toBe(true)
	end)

	it("the derived accessors still hand out FRESH tables the caller may keep", function()
		local before = #schema.propNames("Text")
		local names = schema.propNames("Text")
		table.insert(names, "invented")
		expect(#schema.propNames("Text")).toBe(before)
		local rows = schema.deprecations()
		local rowsBefore = #rows
		table.insert(rows, { surface = "x", since = "0", removeNoEarlierThan = "0", replacement = "y" })
		expect(#schema.deprecations()).toBe(rowsBefore)
	end)
end)

describe("F-34 (BP-F17/BP-F19): UI.PROP_DIRTY is frozen", function()
	it("the published dirty map cannot be rewritten", function()
		expect(pcall(function()
			(UI.PROP_DIRTY :: any).Invented = {}
		end)).toBe(false)
		expect(pcall(function()
			(UI.PROP_DIRTY.Text :: any).text = {}
		end)).toBe(false)
		expect(pcall(function()
			table.insert(UI.PROP_DIRTY.Text.text, "measure")
		end)).toBe(false)
	end)

	it("mount.luau only READS it", function()
		local source = require("@lune/fs").readFile("src/mount.luau")
		expect(string.find(source, "PROP_DIRTY%[[^%]]*%]%s*=[^=]")).toBeNil()
		expect(string.find(source, "PROP_DIRTY%.%w+%s*=[^=]")).toBeNil()
		expect(contains(source, "blueprintLib.PROP_DIRTY[bp.class]")).toBe(true)
	end)
end)

describe("F-22 (BP-F18): a blueprint is immutable all the way down", function()
	it("props cannot be rewritten after construction", function()
		local bp = UI.Box({ id = "B" })
		expect(pcall(function()
			(bp.props :: any).surface = "control"
		end)).toBe(false)
	end)

	it("children cannot be inserted into after construction", function()
		local bp = UI.VStack({ id = "V", children = { UI.Box({ id = "B" }) } })
		expect(pcall(function()
			table.insert(bp.children :: any, UI.Box({ id = "C" }))
		end)).toBe(false)
		expect(pcall(function()
			(bp.children :: any)[1] = UI.Box({ id = "C" })
		end)).toBe(false)
	end)

	it("a modifier's copy is frozen too — a shared template cannot be mutated through it", function()
		local styled = UI.frame(UI.Box({ id = "B" }), { width = 10 })
		expect(table.isfrozen(styled.props)).toBe(true)
		expect(pcall(function()
			(styled.props :: any).height = { type = "fixed", px = 4 }
		end)).toBe(false)
	end)

	it("UI.background's inflated backing layer is frozen too", function()
		local wrapper = UI.background(UI.Text({ id = "T", text = "hi" }), UI.Box({ id = "P" }))
		local backing = (wrapper.children :: any)[1]
		expect(table.isfrozen(backing.props)).toBe(true)
	end)
end)

describe("F-7 (BP-F4): a modifier error names the modifier the author typed", function()
	local function structural()
		local core = customFactory.new()
		return UI.When({
			id = "W",
			condition = core:signal(true),
			thenView = function()
				return UI.Box({ id = "c" })
			end,
		})
	end

	it("UI.alignment on a UI.When names UI.alignment AND UI.When", function()
		local err = failure(function()
			return UI.alignment(structural(), "center")
		end)
		expect(contains(err, "UI.alignment on UI.When")).toBe(true)
		expect(contains(err, "alignH")).toBe(true)
		expect(contains(err, "Valid properties:")).toBe(true)
	end)

	it("UI.frame on a UI.When names UI.frame", function()
		local err = failure(function()
			return UI.frame(structural(), { width = 40 })
		end)
		expect(contains(err, "UI.frame on UI.When")).toBe(true)
		expect(contains(err, "width")).toBe(true)
	end)

	it("a WRONG-TYPE write through a modifier names the modifier too", function()
		local err = failure(function()
			return UI.alignment(UI.Box({ id = "B" }), "middle")
		end)
		expect(contains(err, "UI.alignment on UI.Box")).toBe(true)
		expect(contains(err, "alignH")).toBe(true)
	end)

	it("a DIRECT constructor error is unchanged — no modifier is named", function()
		local err = failure(function()
			return UI.VStack({ id = "V", columns = 3 })
		end)
		expect(contains(err, "Facet UI.VStack: unknown property 'columns'")).toBe(true)
		expect(contains(err, " on UI.")).toBe(false)
	end)
end)

describe('F-19 (BP-F11): overflow = "clip" implies clipChildren', function()
	it("a VStack that declares clip becomes a clip host", function()
		local bp = UI.VStack({ id = "V", overflow = "clip", children = {} })
		expect(bp.props.clipChildren).toBe(true)
	end)

	it("an explicitly authored clipChildren always wins", function()
		local bp = UI.VStack({ id = "V", overflow = "clip", clipChildren = false, children = {} })
		expect(bp.props.clipChildren).toBe(false)
	end)

	it("every other overflow value stays declared intent and drives nothing", function()
		expect(UI.VStack({ id = "V", overflow = "scroll", children = {} }).props.clipChildren).toBeNil()
		expect(UI.VStack({ id = "V", overflow = "visible", children = {} }).props.clipChildren).toBeNil()
		expect(UI.VStack({ id = "V", overflow = "intentionalOverlap", children = {} }).props.clipChildren).toBeNil()
		expect(UI.VStack({ id = "V", children = {} }).props.clipChildren).toBeNil()
	end)

	it("a BOUND overflow implies nothing — clipChildren is construction-only", function()
		local core = customFactory.new()
		local bp = UI.VStack({ id = "V", overflow = core:signal("clip"), children = {} })
		expect(bp.props.clipChildren).toBeNil()
	end)
end)

describe("F-20 (BP-F12): Divider/Path thickness take the metric-name grammar", function()
	it("UI.Divider takes a theme metric name", function()
		expect(pcall(function()
			return UI.Divider({ id = "D", thickness = "strokes.hairline" })
		end)).toBe(true)
		expect(pcall(function()
			return UI.Path({ id = "P", points = { { x = 0, y = 0 }, { x = 1, y = 1 } }, thickness = "strokes.hairline" })
		end)).toBe(true)
	end)

	it("a bogus name errors naming the metric vocabulary", function()
		local err = failure(function()
			return UI.Divider({ id = "D", thickness = "strokes.hairlin" })
		end)
		expect(contains(err, "names no theme metric")).toBe(true)
		local perr = failure(function()
			return UI.Path({ id = "P", points = { { x = 0, y = 0 } }, thickness = "nope.nope" })
		end)
		expect(contains(perr, "names no theme metric")).toBe(true)
	end)

	it("a metric-named Divider thickness SOLVES to the theme's number", function()
		local function heightOf(thickness: any): number
			local rule = if thickness == nil
				then UI.Divider({ id = "D" })
				else UI.Divider({ id = "D", thickness = thickness })
			local core = customFactory.new()
			local env = environment.new(core)
			env:set("viewportRect", { x = 0, y = 0, w = 300, h = 300 })
			env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
			local root = mountLib.mount(core, UI.Screen({ id = "S", padding = 0, children = { rule } }))
			local adapter = fake_target.new()
			local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
			controller.initialRender()
			return adapter.node("/S/D").rect.h
		end
		-- the metric name resolves to exactly what the default (the same metric) is
		expect(heightOf("strokes.hairline")).toBe(heightOf(nil))
		expect(heightOf("strokes.hairline") > 0).toBe(true)
		-- ...and an EXPLICIT number still wins, unresolved
		expect(heightOf(3)).toBe(3)
	end)

	it("an authored Divider thickness reaches the solve at all", function()
		-- found while giving this prop the metric grammar: `thickness` is a BINDING
		-- prop name (Path's engine stroke width) and the renderer's binding
		-- dispatch was class-blind, so ANY authored Divider thickness — number or
		-- name — died at first render on "no declared authority for
		-- Divider.thickness". The Divider consumes it in the SOLVER; no adapter
		-- ever sees it.
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 300, h = 300 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local root =
			mountLib.mount(core, UI.Screen({ id = "S", children = { UI.Divider({ id = "D", thickness = 4 }) } }))
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		expect(pcall(controller.initialRender)).toBe(true)
		expect(adapter.node("/S/D").props.thickness).toBeNil()
	end)

	it("the schema doc states the TRUTHFUL default, not '1 px'", function()
		local doc = (schema.forClass("Divider") :: any).props.thickness.doc
		expect(contains(doc, "strokes.hairline")).toBe(true)
		expect(contains(doc, "default 1")).toBe(false)
	end)
end)

describe("F-21 (BP-F14): the suggester knows the two reserved keys", function()
	it("a typo'd `id` suggests it", function()
		local err = failure(function()
			return UI.Text({ idd = "x", text = "hi" })
		end)
		expect(contains(err, "Did you mean")).toBe(true)
		expect(contains(err, "'id'")).toBe(true)
	end)

	it("a typo'd `children` suggests it", function()
		local err = failure(function()
			return UI.VStack({ id = "V", childern = {} })
		end)
		expect(contains(err, "'children'")).toBe(true)
	end)
end)
