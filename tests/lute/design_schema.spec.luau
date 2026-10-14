--!strict
local Verify = require("../../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local Schema = require("../../tools/facet/lib/schema")
	local Wire = require("../../tools/facet/design/wire")
	local Fixtures = require("./design_fixtures")

	local schema = Fixtures.schema()

	local function field(control: string, name: string): Schema.Field
		local found = Schema.field(assert(schema.controls[control], "no control " .. control), name)
		return assert(found, control .. " has no " .. name)
	end

	verifyHarness:suite("Design schema", function()
		verifyHarness:case("lists every uppercase entry of the Controls type as a control", {
			id = "lute/design_schema::Design schema::lists every uppercase entry of the Controls type as a control",
			run = function()
				local source = Fixtures.read("src/ui/control_types.luau")
				local block = string.match(source, "export type Controls = (%b{})") :: string
				local expected: { string } = {}
				for name in string.gmatch(block, "\n\t(%u[%w_]*):") do
					table.insert(expected, name)
				end
				table.sort(expected)
				Verify.expect(schema.order):toEqual(expected)
				Verify.expect(#schema.order > 60):toBe(true)
				local helpers: { string } = {}
				for _, helper in schema.helpers do
					table.insert(helpers, helper.name)
				end
				Verify.expect(helpers):toContain("fill")
				Verify.expect(helpers):toContain("commandScope")
			end,
		})

		verifyHarness:case("flattens intersections into Facet and native properties", {
			id = "lute/design_schema::Design schema::flattens intersections into Facet and native properties",
			run = function()
				local vstack = schema.controls.VStack
				Verify.expect(vstack.family):toBe("layout_types")
				Verify.expect(vstack.instance):toBe("Frame")
				Verify.expect(vstack.children):toBe(true)
				Verify.expect(field("VStack", "gap").origin):toBe("layout_types")
				Verify.expect(field("VStack", "BackgroundTransparency").origin):toBe("engine_types")
				Verify.expect(Schema.describe(field("VStack", "width").shape))
					:toBe('Value<number | "fill" | "hug"> | nil')
				Verify.expect(field("Button", "onActivate").shape.kind):toBe("union")
				Verify.expect(Schema.accepts(field("Button", "onActivate").shape, "function")):toBe(true)
				Verify.expect(Schema.describe(field("Button", "Size").shape)):toBe("Value<UDim2> | nil")
				Verify.expect(Schema.describe(field("VStack", "AutomaticSize").shape))
					:toBe("Value<Enum.AutomaticSize> | nil")
			end,
		})

		verifyHarness:case("marks required properties and literal unions", {
			id = "lute/design_schema::Design schema::marks required properties and literal unions",
			run = function()
				Verify.expect(schema.controls.Text.required):toEqual({ "text" })
				Verify.expect(schema.controls.Grid.required):toEqual({ "columns" })
				Verify.expect(schema.controls.Toggle.required):toContain("value")
				Verify.expect(field("Text", "text").optional):toBe(false)
				Verify.expect(Schema.literals(field("Text", "textAlign").shape)):toEqual({ "start", "center", "end" })
				Verify.expect(Schema.accepts(field("Text", "textAlign").shape, "string")):toBe(false)
				Verify.expect(Schema.accepts(field("VStack", "gap").shape, "string")):toBe(true)
				Verify.expect(Schema.accepts(field("Toggle", "value").shape, "cell")):toBe(true)
			end,
		})

		verifyHarness:case("names theme token sets from aliased literal unions", {
			id = "lute/design_schema::Design schema::names theme token sets from aliased literal unions",
			run = function()
				Verify.expect(schema.tokens.space):toEqual({ "xs", "s", "m", "l", "xl" })
				Verify.expect(schema.tokens.typography):toContain("title")
				Verify.expect(schema.tokens.controlSize):toContain("regular")
				Verify.expect(schema.tokens.status):toContain("success")
				local gap = Schema.tokenSets(field("VStack", "gap").shape)
				Verify.expect(gap.space):toEqual(schema.tokens.space)
				local role = Schema.tokenSets(field("Text", "textRole").shape)
				Verify.expect(role.typography ~= nil):toBe(true)
				Verify.expect((next(Schema.tokenSets(field("Button", "label").shape)))):toBeNil()
			end,
		})

		verifyHarness:case("reads generic constructors written as function intersections", {
			id = "lute/design_schema::Design schema::reads generic constructors written as function intersections",
			run = function()
				for _, name in { "Picker", "Menu", "VirtualList", "Table", "NavigationStack", "Alert", "RadialMenu" } do
					local control = schema.controls[name]
					Verify.expect(control ~= nil):toBeTrueWith(name .. " is missing")
					Verify.expect(#control.props > 0):toBeTrueWith(name .. " has no properties")
				end
				Verify.expect(field("VirtualList", "from") ~= nil):toBe(true)
				Verify.expect(field("Picker", "options") ~= nil):toBe(true)
			end,
		})

		verifyHarness:case("serializes the schema and one control to JSON", {
			id = "lute/design_schema::Design schema::serializes the schema and one control to JSON",
			run = function()
				local all = Wire.encode(Schema.toJson(schema, false))
				local ok, decoded = Wire.decode(all)
				Verify.expect(ok):toBe(true)
				Verify.expect(#Wire.list(Wire.field(decoded, "controls"))):toBe(#schema.order)
				local text = Schema.controlJson(schema.controls.Text, false)
				local props = text.props :: { { [string]: unknown } }
				local names: { string } = {}
				for _, prop in props do
					table.insert(names, prop.name :: string)
					Verify.expect(prop.native):toBe(false)
				end
				Verify.expect(names):toContain("textRole")
				Verify.expect(names).never:toContain("BackgroundColor3")
				Verify.expect(#(Schema.controlJson(schema.controls.Text, true).props :: { unknown }) > #props)
					:toBe(true)
			end,
		})
	end)
end
