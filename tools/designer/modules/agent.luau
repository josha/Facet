--!strict

local document = require("./document")
local source = require("./source")
local export = require("./export")

local agent = {}

local function resolve(value: any, selector: string): string
	assert(type(selector) == "string" and selector ~= "", "Choose a node ID or layer name")
	if document.find(value.root, selector) then
		return selector
	end
	local matches = {}
	for _, row in document.rows(value.root) do
		if row.name == selector then
			table.insert(matches, row.id)
		end
	end
	assert(#matches == 1, "Select a node ID or a unique layer name: " .. selector)
	return matches[1]
end

function agent.apply(value: any, operations: { any }): any
	local nextValue = document.copy(document.validate(value))
	assert(type(operations) == "table" and #operations > 0 and #operations <= 100, "Use 1 to 100 edit operations")
	for key in operations do
		assert(
			type(key) == "number" and key >= 1 and key <= #operations and key % 1 == 0,
			"Operations must be a dense array"
		)
	end
	for _, operation in operations do
		assert(type(operation) == "table", "Invalid edit operation")
		local command = operation.op
		if command == "renameDesign" then
			nextValue.name = operation.name
			document.validate(nextValue)
		else
			local id = resolve(nextValue, operation.node)
			if command == "set" then
				nextValue = document.change(nextValue, id, operation.property, operation.value)
			elseif command == "reset" then
				nextValue = document.change(nextValue, id, operation.property, nil)
			elseif command == "insert" then
				nextValue = document.insert(nextValue, id, operation.kind)
			elseif command == "remove" then
				nextValue = document.remove(nextValue, id)
			elseif command == "duplicate" then
				nextValue = document.duplicate(nextValue, id)
			elseif command == "move" then
				nextValue = document.move(nextValue, id, resolve(nextValue, operation.destination), operation.before)
			else
				error("Unsupported edit operation: " .. tostring(command), 0)
			end
		end
	end
	return document.validate(nextValue)
end

function agent.patch(code: string, operations: { any }, name: string?): (string, any)
	local value = agent.apply(source.parse(code, name or "Untitled design"), operations)
	return export.component(value), value
end

return agent
