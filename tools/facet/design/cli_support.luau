--!strict

local fs = require("@std/fs")
local process = require("@std/process")
local Schema = require("../lib/schema")
local Values = require("./values")
local Wire = require("./wire")

local Support = {}

function Support.root(): string
	local found = Schema.findRoot()
	local base = found or tostring(process.cwd())
	return (string.gsub(base, "\\", "/"))
end

function Support.schema(root: string): Schema.Schema?
	local ok, schema = pcall(Schema.load, root)
	if ok then
		return schema :: Schema.Schema
	end
	return nil
end

function Support.version(root: string): string
	local path = root .. "/src/init.luau"
	if not fs.exists(path) then
		return "0.0.0"
	end
	local source = fs.readFileToString(path)
	return string.match(source, 'local VERSION = "([^"]+)"') or "0.0.0"
end

function Support.author(flag: string?, kind: string): string
	if flag and flag ~= "" then
		return flag
	end
	local user = process.env.USER or process.env.USERNAME or "local"
	local clean = string.gsub(string.lower(user), "[^%w_%-%.]", "-")
	return kind .. ":" .. clean
end

function Support.readJson(argument: string): (boolean, unknown)
	local text = argument
	if string.sub(argument, 1, 1) == "@" then
		local path = string.sub(argument, 2)
		if not fs.exists(path) then
			return false, "cannot read " .. path
		end
		text = fs.readFileToString(path)
	elseif not string.match(argument, "^%s*[%[{]") and fs.exists(argument) then
		text = fs.readFileToString(argument)
	end
	return Wire.decode(text)
end

function Support.valueText(value: { [string]: unknown }): string
	local kind = value.kind
	if kind == "string" then
		return Values.quote(tostring(value.value))
	elseif kind == "token" then
		return tostring(value.value)
	elseif kind == "number" or kind == "boolean" then
		return tostring(value.value)
	elseif kind == "nil" then
		return "nil"
	elseif kind == "binding" then
		local prefix = if value.source == "item" then "@item" else "@model"
		local path = tostring(value.path or "")
		return prefix .. (if path ~= "" then "." .. path else "")
	end
	local text = value.text
	if type(text) == "string" then
		local single = string.gsub(text, "%s+", " ")
		if #single > 48 then
			return string.sub(single, 1, 45) .. "..."
		end
		return single
	end
	return "<" .. tostring(kind) .. ">"
end

function Support.treeText(node: { [string]: unknown }, depth: number, lines: { string })
	local indent = string.rep("  ", depth)
	local id = tostring(node.id)
	local kind = node.kind
	local head = indent .. id
	if node.type == "control" then
		head ..= "  " .. tostring(kind)
	elseif node.type == "keyed" then
		head ..= "  keyed"
	else
		local text = tostring(node.text or "")
		local single = string.gsub(text, "%s+", " ")
		head ..= "  code " .. (if #single > 60 then string.sub(single, 1, 57) .. "..." else single)
	end
	local props = node.props
	if type(props) == "table" then
		local parts: { string } = {}
		for _, prop in props :: { { [string]: unknown } } do
			table.insert(parts, tostring(prop.name) .. "=" .. Support.valueText(prop.value :: { [string]: unknown }))
		end
		if #parts > 0 then
			head ..= "  " .. table.concat(parts, " ")
		end
	end
	table.insert(lines, head)
	local children = node.children
	if type(children) == "table" then
		for _, child in children :: { { [string]: unknown } } do
			Support.treeText(child, depth + 1, lines)
		end
	end
end

return table.freeze(Support)
