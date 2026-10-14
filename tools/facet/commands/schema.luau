--!strict

local Cli = require("../lib/cli")
local Schema = require("../lib/schema")
local Support = require("../design/cli_support")
local Wire = require("../design/wire")

local USAGE = table.concat({
	"usage: lute run tools/facet schema [--control=NAME] [--native] [--json]",
	"",
	"Print the control schema that src/ui/control_types.luau declares.",
	"--control prints one control. --native includes native Instance properties.",
}, "\n")

local function run(invocation: Cli.Invocation): number
	local root = Support.root()
	local ok, loaded = pcall(Schema.load, root)
	if not ok then
		print("facet: " .. tostring(loaded))
		return 1
	end
	local schema = loaded :: Schema.Schema
	local native = Cli.switch(invocation, "native")
	local name = Cli.flag(invocation, "control")
	if name then
		local control = Schema.control(schema, name)
		if control == nil then
			print("facet: no control " .. name)
			return 1
		end
		if Cli.switch(invocation, "json") then
			print(Wire.encode(Schema.controlJson(control, native), true))
			return 0
		end
		print(
			("%s (%s, %s)%s"):format(
				control.name,
				control.family,
				control.instance,
				if control.children then ", children" else ""
			)
		)
		for _, field in control.props do
			if native or field.origin ~= "engine_types" then
				print(
					("  %s%s: %s"):format(field.name, if field.optional then "?" else "", Schema.describe(field.shape))
				)
			end
		end
		return 0
	end
	if Cli.switch(invocation, "json") then
		print(Wire.encode(Schema.toJson(schema, native), true))
		return 0
	end
	for _, controlName in schema.order do
		local control = schema.controls[controlName]
		local required = if #control.required > 0 then "  requires " .. table.concat(control.required, ", ") else ""
		print(("%-20s %-28s%s"):format(control.name, control.family, required))
	end
	local helpers: { string } = {}
	for _, helper in schema.helpers do
		table.insert(helpers, helper.name)
	end
	print("helpers: " .. table.concat(helpers, ", "))
	return 0
end

local command: Cli.Command = {
	name = "schema",
	summary = "Print the control schema extracted from the control types.",
	usage = USAGE,
	run = run,
}

return command
