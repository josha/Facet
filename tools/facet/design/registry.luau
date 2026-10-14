--!strict

local fs = require("@std/fs")
local Contract = require("./contract")
local Document = require("./document")
local Operations = require("./operations")
local Schema = require("../lib/schema")
local Workspace = require("./workspace")

type Spec = Contract.Spec

export type Input = { [string]: unknown }
export type Result = { [string]: unknown }
export type Failure = Workspace.Failure

export type Context = {
	author: string,
	root: string?,
	schema: Schema.Schema?,
}

export type Tool = {
	name: string,
	summary: string,
	input: Spec,
	mutation: Operations.Mutation,
	capability: Operations.Capability,
	target: "file" | "none",
	internal: boolean,
	run: (Context, Input) -> (Result?, Failure?),
}

local Registry = {}

local FILE = Contract.string("Path of the view module, relative to the workspace root.", { maxLength = 1024 })
local BASE = Contract.string(
	"Hash of the file version the change was made against. A different current hash rejects the change as stale.",
	{
		pattern = "^%x+$",
		maxLength = 128,
	}
)

local function failure(code: string, message: string): Failure
	return { code = code, message = message }
end

local function resolveFile(context: Context, input: Input): (string?, Failure?)
	local file = input.file
	if type(file) ~= "string" then
		return nil, failure("invalid", "file is required")
	end
	local path = string.gsub(file :: string, "\\", "/")
	if string.sub(path, -5) ~= ".luau" then
		return nil, failure("invalid", "file must be a .luau view module")
	end
	for segment in string.gmatch(path, "[^/]+") do
		if segment == ".." then
			return nil, failure("invalid", "file must stay inside the workspace root")
		end
	end
	local root = context.root
	if root and string.sub(path, 1, 1) ~= "/" and not string.match(path, "^%a:/") then
		path = (root :: string) .. "/" .. path
	elseif root and string.sub(path, 1, #(root :: string)) ~= root then
		return nil, failure("invalid", "file must stay inside the workspace root")
	end
	if not fs.exists(path) then
		return nil, failure("not_found", "cannot find " .. (file :: string))
	end
	return path, nil
end

local function strip(input: Input, names: { string }): Input
	local copy = table.clone(input)
	for _, name in names do
		copy[name] = nil
	end
	return copy
end

local function appliedJson(applied: Workspace.Applied, extra: Result?): Result
	local result: Result = {
		hash = applied.hash,
		previous = applied.previous,
		changed = applied.changed,
		entry = applied.entry,
		results = applied.results,
		touched = applied.touched,
	}
	if extra then
		for key, value in extra do
			result[key] = value
		end
	end
	return result
end

local tools: { Tool } = {}

local function add(tool: Tool)
	table.insert(tools, tool)
end

for _, definition in Operations.definitions do
	if definition.mutation == "none" then
		add({
			name = definition.name,
			summary = definition.summary,
			input = Contract.extend(definition.input, { file = FILE }, { "file" }),
			mutation = "none",
			capability = definition.capability,
			target = "file",
			internal = definition.internal == true,
			run = function(context: Context, input: Input): (Result?, Failure?)
				local file, problem = resolveFile(context, input)
				if file == nil then
					return nil, problem
				end
				local doc, hash, readProblem = Workspace.read(file :: string, context.schema)
				if doc == nil then
					return nil, readProblem
				end
				local result, reason =
					Operations.run(doc :: Document.Document, context.schema, definition.name, strip(input, { "file" }))
				if result == nil then
					return nil, failure("invalid", reason or "the query failed")
				end
				local output = result :: Result
				output.hash = hash
				return output, nil
			end,
		})
	else
		add({
			name = definition.name,
			summary = definition.summary,
			input = Contract.extend(definition.input, { file = FILE, base = BASE }, { "file" }),
			mutation = definition.mutation,
			capability = definition.capability,
			target = "file",
			internal = definition.internal == true,
			run = function(context: Context, input: Input): (Result?, Failure?)
				local file, problem = resolveFile(context, input)
				if file == nil then
					return nil, problem
				end
				local op = strip(input, { "file", "base" })
				op.op = definition.name
				local applied, reason = Workspace.apply(
					file :: string,
					{ op },
					{ author = context.author, base = input.base :: string? },
					context.schema
				)
				if applied == nil then
					return nil, reason
				end
				local output = appliedJson(applied :: Workspace.Applied)
				output.result = (applied :: Workspace.Applied).results[1]
				return output, nil
			end,
		})
	end
end

add({
	name = "apply",
	summary = "Apply an atomic batch of document operations. Every operation is checked first; one failure applies nothing.",
	input = Contract.object({
		file = FILE,
		base = BASE,
		ops = Contract.array(
			Contract.json("An operation object with op and its fields."),
			"Operations in order.",
			1,
			Operations.MAX_BATCH
		),
	}, { "file", "ops" }),
	mutation = "document",
	capability = "edit",
	target = "file",
	internal = false,
	run = function(context: Context, input: Input): (Result?, Failure?)
		local file, problem = resolveFile(context, input)
		if file == nil then
			return nil, problem
		end
		local applied, reason = Workspace.apply(
			file :: string,
			input.ops,
			{ author = context.author, base = input.base :: string? },
			context.schema
		)
		if applied == nil then
			return nil, reason
		end
		return appliedJson(applied :: Workspace.Applied), nil
	end,
})

add({
	name = "undo",
	summary = "Undo the latest edit of the calling author, or one named entry of that author.",
	input = Contract.object({
		file = FILE,
		base = BASE,
		entry = Contract.integer("History entry id. It must belong to the calling author.", 1),
	}, { "file" }),
	mutation = "document",
	capability = "edit",
	target = "file",
	internal = false,
	run = function(context: Context, input: Input): (Result?, Failure?)
		local file, problem = resolveFile(context, input)
		if file == nil then
			return nil, problem
		end
		local applied, reason = Workspace.undo(file :: string, {
			author = context.author,
			base = input.base :: string?,
			entry = input.entry :: number?,
		}, context.schema)
		if applied == nil then
			return nil, reason
		end
		return appliedJson(applied :: Workspace.Applied), nil
	end,
})

add({
	name = "redo",
	summary = "Redo the latest undo of the calling author.",
	input = Contract.object({ file = FILE, base = BASE }, { "file" }),
	mutation = "document",
	capability = "edit",
	target = "file",
	internal = false,
	run = function(context: Context, input: Input): (Result?, Failure?)
		local file, problem = resolveFile(context, input)
		if file == nil then
			return nil, problem
		end
		local applied, reason =
			Workspace.redo(file :: string, { author = context.author, base = input.base :: string? }, context.schema)
		if applied == nil then
			return nil, reason
		end
		return appliedJson(applied :: Workspace.Applied), nil
	end,
})

add({
	name = "history",
	summary = "List recent history entries with their authors, operations and state.",
	input = Contract.object({ file = FILE, limit = Contract.integer("Maximum entries.", 1, 500) }, { "file" }),
	mutation = "none",
	capability = "read",
	target = "file",
	internal = false,
	run = function(context: Context, input: Input): (Result?, Failure?)
		local file, problem = resolveFile(context, input)
		if file == nil then
			return nil, problem
		end
		local result: Result = { entries = Workspace.history(file :: string, input.limit :: number?) }
		return result, nil
	end,
})

local function commentTool(
	name: string,
	summary: string,
	fields: { [string]: Spec },
	required: { string },
	mutation: Operations.Mutation
)
	local merged = table.clone(fields)
	merged.file = FILE
	local names = table.clone(required)
	table.insert(names, "file")
	add({
		name = name,
		summary = summary,
		input = Contract.object(merged, names),
		mutation = mutation,
		capability = if mutation == "none" then "read" else "comment",
		target = "file",
		internal = false,
		run = function(context: Context, input: Input): (Result?, Failure?)
			local file, problem = resolveFile(context, input)
			if file == nil then
				return nil, problem
			end
			return Workspace.comment(
				file :: string,
				name,
				strip(input, { "file" }),
				{ author = context.author },
				context.schema
			)
		end,
	})
end

local TEXT = Contract.string("Comment text.", { maxLength = 4000 })
local THREAD = Contract.string("Comment thread id, for example t3.", { pattern = "^t%d+$" })

commentTool("comment_add", "Start a comment thread anchored to a node.", {
	node = Contract.string("Node id or unique label.", { maxLength = 512 }),
	text = TEXT,
}, { "node", "text" }, "comments")
commentTool(
	"comment_reply",
	"Reply in a comment thread.",
	{ thread = THREAD, text = TEXT },
	{ "thread", "text" },
	"comments"
)
commentTool("comment_resolve", "Resolve or reopen a comment thread.", {
	thread = THREAD,
	resolved = Contract.boolean("false reopens the thread."),
}, { "thread" }, "comments")
commentTool("comment_list", "List comment threads, optionally under one node.", {
	node = Contract.string("Only threads on this node or its descendants.", { maxLength = 512 }),
	resolved = Contract.boolean("Only resolved or only open threads."),
}, {}, "none")

local function schemaOf(context: Context): (Schema.Schema?, Failure?)
	if context.schema then
		return context.schema, nil
	end
	local ok, loaded = pcall(Schema.load, context.root)
	if not ok then
		return nil, failure("not_found", tostring(loaded))
	end
	return loaded :: Schema.Schema, nil
end

add({
	name = "schema_controls",
	summary = "List the Facet controls with their families, required properties and child support.",
	input = Contract.object({}),
	mutation = "none",
	capability = "read",
	target = "none",
	internal = false,
	run = function(context: Context, _input: Input): (Result?, Failure?)
		local schema, problem = schemaOf(context)
		if schema == nil then
			return nil, problem
		end
		local controls: { unknown } = {}
		for _, name in (schema :: Schema.Schema).order do
			local control = (schema :: Schema.Schema).controls[name]
			table.insert(controls, {
				name = control.name,
				family = control.family,
				required = control.required,
				children = control.children,
			})
		end
		local result: Result = { controls = controls, tokens = (schema :: Schema.Schema).tokens }
		return result, nil
	end,
})

add({
	name = "schema_control",
	summary = "Describe one control: every property with its type, and whether it is required.",
	input = Contract.object({
		name = Contract.string("Control name, for example Button.", { pattern = "^%u[%w_]*$" }),
		native = Contract.boolean("Include native Instance properties."),
	}, { "name" }),
	mutation = "none",
	capability = "read",
	target = "none",
	internal = false,
	run = function(context: Context, input: Input): (Result?, Failure?)
		local schema, problem = schemaOf(context)
		if schema == nil then
			return nil, problem
		end
		local control = (schema :: Schema.Schema).controls[input.name :: string]
		if control == nil then
			return nil, failure("not_found", "no control " .. tostring(input.name))
		end
		local result: Result = { control = Schema.controlJson(control, input.native == true) }
		return result, nil
	end,
})

Registry.DOCS = "docs/guide/20-design-documents.md"

add({
	name = "docs",
	summary = "Read the design document guide: the editable subset, the operations and the file formats.",
	input = Contract.object({
		topic = Contract.string("A heading to return, for example Editable subset. Empty returns the headings.", {
			maxLength = 120,
		}),
	}),
	mutation = "none",
	capability = "read",
	target = "none",
	internal = false,
	run = function(context: Context, input: Input): (Result?, Failure?)
		local path = (context.root or ".") .. "/" .. Registry.DOCS
		if not fs.exists(path) then
			return nil, failure("not_found", "cannot find " .. Registry.DOCS)
		end
		local text = fs.readFileToString(path)
		local headings: { string } = {}
		local sections: { [string]: { string } } = {}
		local current = ""
		for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
			local heading = string.match(line, "^##+%s+(.+)$")
			if heading then
				current = string.lower(heading)
				table.insert(headings, heading)
				sections[current] = { line }
			elseif sections[current] then
				table.insert(sections[current], line)
			end
		end
		local topic = input.topic
		if type(topic) == "string" and topic ~= "" then
			local lines = sections[string.lower(topic :: string)]
			if lines == nil then
				return nil,
					failure(
						"not_found",
						"no section " .. (topic :: string) .. "; sections are " .. table.concat(headings, ", ")
					)
			end
			local result: Result = { topic = topic, text = table.concat(lines, "\n") }
			return result, nil
		end
		local result: Result = { sections = headings, text = text }
		return result, nil
	end,
})

add({
	name = "list_views",
	summary = "Find view modules under a directory of the workspace.",
	input = Contract.object({ path = Contract.string("Directory or file to search.", { maxLength = 1024 }) }),
	mutation = "none",
	capability = "read",
	target = "none",
	internal = false,
	run = function(context: Context, input: Input): (Result?, Failure?)
		local root = context.root or "."
		local path = input.path
		local target = if type(path) == "string" then root .. "/" .. (path :: string) else root
		for segment in string.gmatch(target, "[^/]+") do
			if segment == ".." then
				return nil, failure("invalid", "path must stay inside the workspace root")
			end
		end
		local files = Workspace.discover({ target })
		local relative: { string } = {}
		for _, file in files do
			if string.sub(file, 1, #root + 1) == root .. "/" then
				table.insert(relative, string.sub(file, #root + 2))
			else
				table.insert(relative, file)
			end
		end
		local result: Result = { files = relative }
		return result, nil
	end,
})

local byName: { [string]: Tool } = {}
for _, tool in tools do
	byName[tool.name] = tool
end

Registry.tools = tools
Registry.byName = byName

function Registry.get(name: string): Tool?
	return byName[name]
end

function Registry.list(includeInternal: boolean?): { Tool }
	local result: { Tool } = {}
	for _, tool in tools do
		if includeInternal or not tool.internal then
			table.insert(result, tool)
		end
	end
	return result
end

function Registry.call(context: Context, name: string, input: unknown): (Result?, Failure?)
	local tool = byName[name]
	if tool == nil or tool.internal then
		return nil, failure("not_found", "unknown tool " .. name)
	end
	local arguments: Input = if type(input) == "table" then input :: Input else {}
	if input ~= nil and type(input) ~= "table" then
		return nil, failure("invalid", "tool input must be a JSON object")
	end
	local problem = Contract.check(tool.input, arguments, name)
	if problem then
		return nil, failure("invalid", problem)
	end
	local ok, result, reason = pcall(tool.run, context, arguments)
	if not ok then
		return nil, failure("internal", tostring(result))
	end
	return result, reason
end

function Registry.describe(tool: Tool): { [string]: unknown }
	return {
		name = tool.name,
		summary = tool.summary,
		mutation = tool.mutation,
		capability = tool.capability,
		target = tool.target,
		input = Contract.jsonSchema(tool.input),
	}
end

return table.freeze(Registry)
