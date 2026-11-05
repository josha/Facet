--!strict

local Core = require "../core"
local Types = require "./types"
local Source = require "./source"
local Library = require "./library"

export type Import = {
	source: Core.ReadOnlyValue<string>,
	call: string,
	prelude: { string }?,
	library: Types.Library?,
	save: ((expected: string, generated: string) -> boolean)?,
}

local function fieldsOf(contract: Types.Contract, nameInput: string): { [string]: Types.Field }
	local fields: { [string]: Types.Field } = {}
	for _, input in contract.inputs do
		if input.id == nameInput then
			continue
		end
		local typed: Types.FieldType = "value"
		if input.type == "slot" then
			typed = "content"
		elseif
			input.type == "number"
			or input.type == "string"
			or input.type == "boolean"
			or input.type == "vector3"
		then
			typed = input.type
		end
		fields[input.id] = { type = typed }
	end
	for _, output in contract.outputs do
		fields[output.id] = { type = "event" }
	end
	return fields
end

local function extend(base: Types.Library, imports: { [string]: Import }): Types.Library
	local kinds: { [string]: Types.Kind } = {}
	local prelude: { string } = {}
	local calls: { [string]: boolean } = {}
	for _, kind in base.kinds do
		calls[kind.call] = true
	end
	local names: { string } = {}
	for name in imports do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local imported = imports[name]
		local library = imported.library or base
		local value = Source.parse(imported.source:peek(), library)
		local nameInput = assert(value.root.nameInput, "Imported Designs need a root name input")
		local naming: Types.Input? = nil
		for _, input in value.contract.inputs do
			if input.id == nameInput then
				naming = input
			end
		end
		assert(naming and naming.required == true, "Imported Designs need a required root name input")
		assert(string.match(imported.call, "^[%a_][%w_%.]*$") ~= nil, "Imported Designs need a component call")
		assert(not calls[imported.call], "Imported Design calls must be distinct")
		assert(
			string.sub(imported.call, -1) ~= "." and not string.find(imported.call, "..", 1, true),
			"Imported Design calls have no empty path segments"
		)
		calls[imported.call] = true
		for segment in string.gmatch(imported.call, "[^%.]+") do
			assert(string.match(segment, "^[%a_][%w_]*$") ~= nil, "Imported Design calls have identifier path segments")
		end
		kinds[name] = {
			fields = fieldsOf(value.contract, nameInput),
			children = "none",
			call = imported.call,
			design = {
				source = imported.source,
				library = library,
				nameInput = nameInput,
				contract = value.contract,
				save = imported.save,
			},
			build = function(): unknown
				error("Imported Designs build through Design.render", 0)
			end,
		}
		for _, line in imported.prelude or {} do
			if not table.find(prelude, line) then
				table.insert(prelude, line)
			end
		end
	end
	return Library.extend(base, { kinds = kinds, prelude = prelude })
end

local function sameList<T>(before: { T }?, after: { T }?): boolean
	if before == nil or after == nil then
		return before == after
	end
	if #before ~= #after then
		return false
	end
	for index, value in before do
		if value ~= after[index] then
			return false
		end
	end
	return true
end

local function sameFields(before: { Types.ItemField }?, after: { Types.ItemField }?): boolean
	if before == nil or after == nil then
		return before == after
	end
	if #before ~= #after then
		return false
	end
	for index, field in before do
		local other = after[index]
		if
			field.id ~= other.id
			or field.type ~= other.type
			or field.luauType ~= other.luauType
			or not sameFields(field.fields, other.fields)
			or not sameList(field.options, other.options)
		then
			return false
		end
	end
	return true
end

local function read(imported: Types.ImportedDesign, use: Core.Use?): Types.Document
	local value = Source.parse(if use then use(imported.source) else imported.source:peek(), imported.library)
	local before, after = imported.contract, value.contract
	assert(#before.inputs == #after.inputs and #before.outputs == #after.outputs, "Imported Design contract changed")
	assert(value.root.nameInput == imported.nameInput, "Imported Design root name input changed")
	for index, input in before.inputs do
		local other = after.inputs[index]
		assert(
			input.id == other.id
				and input.type == other.type
				and input.kind == other.kind
				and input.required == other.required
				and input.luauType == other.luauType
				and sameFields(input.fields, other.fields)
				and sameList(input.options, other.options),
			"Imported Design contract changed"
		)
	end
	for index, output in before.outputs do
		local other = after.outputs[index]
		assert(
			output.id == other.id and output.row == other.row and sameList(output.args, other.args),
			"Imported Design contract changed"
		)
	end
	return value
end

return { extend = extend, read = read }
