--!strict

local crypto = require("@lute/crypto")
local fs = require("@std/fs")
local task = require("@std/task")
local Comments = require("./comments")
local Document = require("./document")
local Edit = require("./edit")
local Operations = require("./operations")
local Schema = require("../lib/schema")
local Wire = require("./wire")

type Document = Document.Document

export type Failure = { code: string, message: string }

export type Entry = {
	id: number,
	author: string,
	time: number,
	kind: "edit" | "undo" | "redo",
	target: number?,
	undone: boolean,
	base: string,
	result: string,
	ops: { { [string]: unknown } },
	inverse: { { [string]: unknown } },
}

export type History = { version: number, next: number, entries: { Entry } }

export type Applied = {
	file: string,
	hash: string,
	previous: string,
	changed: boolean,
	entry: number?,
	results: { { [string]: unknown } },
	touched: { string },
	doc: Document,
	source: string,
}

export type Options = { author: string, base: string?, entry: number?, now: (() -> number)? }

local Workspace = {}

Workspace.MAX_HISTORY = 500
Workspace.AUTHOR_PATTERN = "^[%w_%-%.:@]+$"

function Workspace.hash(text: string): string
	local digest = crypto.digest(crypto.hash.sha256, text)
	local parts = table.create(buffer.len(digest))
	for index = 0, buffer.len(digest) - 1 do
		parts[index + 1] = string.format("%02x", buffer.readu8(digest, index))
	end
	return table.concat(parts)
end

function Workspace.historyPath(file: string): string
	return file .. ".history.json"
end

function Workspace.commentsPath(file: string): string
	return file .. ".comments.json"
end

local function failure(code: string, message: string): Failure
	return { code = code, message = message }
end

function Workspace.checkAuthor(author: string): Failure?
	if #author == 0 or #author > 64 or string.match(author, Workspace.AUTHOR_PATTERN) == nil then
		return failure("invalid", "an author is 1 to 64 letters, digits or _-.:@, for example agent:claude")
	end
	return nil
end

local function now(options: Options?): number
	if options and options.now then
		return (options.now :: () -> number)()
	end
	return os.time()
end

local function readText(path: string): string?
	if not fs.exists(path) then
		return nil
	end
	local ok, text = pcall(fs.readFileToString, path)
	if not ok then
		return nil
	end
	return text :: string
end

function Workspace.writeText(path: string, text: string)
	local temporary = path .. ".facet-tmp"
	fs.writeStringToFile(temporary, text)
	local moved = pcall(fs.move, temporary, path)
	if not moved then
		fs.writeStringToFile(path, text)
		pcall(fs.remove, temporary)
	end
end

local function acquire(file: string): (() -> ())?
	local lockPath = file .. ".lock"
	for _ = 1, 200 do
		local exclusive: fs.HandleMode = "x"
		local opened, handle = pcall(fs.open, lockPath, exclusive)
		if opened then
			pcall(fs.write, handle, tostring(os.time()))
			pcall(fs.close, handle)
			return function()
				pcall(fs.remove, lockPath)
			end
		end
		local statted, meta = pcall(fs.metadata, lockPath)
		local modified = if statted then tonumber(tostring((meta :: fs.FileMetadata).modified)) else nil
		if modified and os.time() - modified > 30 then
			pcall(fs.remove, lockPath)
		else
			task.wait(0.025)
		end
	end
	return nil
end

function Workspace.withLock<T>(file: string, body: () -> (T?, Failure?)): (T?, Failure?)
	local release = acquire(file)
	if release == nil then
		return nil, failure("locked", "another writer holds " .. file .. ".lock")
	end
	local ok, result, problem = pcall(body)
	release()
	if not ok then
		return nil, failure("internal", tostring(result))
	end
	return result, problem
end

function Workspace.read(file: string, schema: Schema.Schema?): (Document?, string?, Failure?)
	local source = readText(file)
	if source == nil then
		return nil, nil, failure("not_found", "cannot read " .. file)
	end
	return Document.parse(source :: string, schema), Workspace.hash(source :: string), nil
end

local function decodeList(value: unknown): { { [string]: unknown } }
	local result: { { [string]: unknown } } = {}
	for _, item in Wire.list(value) do
		if type(item) == "table" then
			table.insert(result, item :: { [string]: unknown })
		end
	end
	return result
end

function Workspace.loadHistory(file: string): History
	local text = readText(Workspace.historyPath(file))
	local history: History = { version = 1, next = 1, entries = {} }
	if text == nil then
		return history
	end
	local ok, value = Wire.decode(text :: string)
	if not ok or type(value) ~= "table" then
		return history
	end
	local nextId = Wire.field(value, "next")
	history.next = if type(nextId) == "number" then nextId else 1
	for _, raw in Wire.list(Wire.field(value, "entries")) do
		local id = Wire.field(raw, "id")
		local author = Wire.text(raw, "author")
		local kind = Wire.text(raw, "kind")
		if type(id) ~= "number" or author == nil or (kind ~= "edit" and kind ~= "undo" and kind ~= "redo") then
			continue
		end
		local target = Wire.field(raw, "target")
		local time = Wire.field(raw, "time")
		table.insert(history.entries, {
			id = id,
			author = author :: string,
			time = if type(time) == "number" then time else 0,
			kind = kind :: "edit" | "undo" | "redo",
			target = if type(target) == "number" then target else nil,
			undone = Wire.field(raw, "undone") == true,
			base = Wire.text(raw, "base") or "",
			result = Wire.text(raw, "result") or "",
			ops = decodeList(Wire.field(raw, "ops")),
			inverse = decodeList(Wire.field(raw, "inverse")),
		})
		history.next = math.max(history.next, id + 1)
	end
	return history
end

function Workspace.entryJson(entry: Entry, full: boolean?): { [string]: unknown }
	local result: { [string]: unknown } = {
		id = entry.id,
		author = entry.author,
		time = entry.time,
		kind = entry.kind,
		undone = entry.undone,
		base = entry.base,
		result = entry.result,
	}
	if entry.target then
		result.target = entry.target
	end
	if full then
		result.ops = entry.ops
		result.inverse = entry.inverse
	else
		local names: { string } = {}
		for _, op in entry.ops do
			table.insert(names, tostring(op.op))
		end
		result.ops = names
	end
	return result
end

local function saveHistory(file: string, history: History)
	while #history.entries > Workspace.MAX_HISTORY do
		table.remove(history.entries, 1)
	end
	local entries: { unknown } = {}
	for _, entry in history.entries do
		table.insert(entries, Workspace.entryJson(entry, true))
	end
	Workspace.writeText(
		Workspace.historyPath(file),
		Wire.encode({ version = history.version, next = history.next, entries = entries }, true) .. "\n"
	)
end

function Workspace.loadComments(file: string): Comments.Store
	local text = readText(Workspace.commentsPath(file))
	if text == nil then
		return Comments.empty()
	end
	local store = Comments.decode(text :: string)
	return store or Comments.empty()
end

local function saveComments(file: string, store: Comments.Store)
	Workspace.writeText(Workspace.commentsPath(file), Comments.encode(store))
end

local function commitBatch(
	file: string,
	schema: Schema.Schema?,
	ops: unknown,
	options: Options,
	kind: "edit" | "undo" | "redo",
	internal: boolean,
	before: ((History, Document) -> Failure?)?,
	after: ((History, Entry) -> ())?
): (Applied?, Failure?)
	local authorProblem = Workspace.checkAuthor(options.author)
	if authorProblem then
		return nil, authorProblem
	end
	return Workspace.withLock(file, function(): (Applied?, Failure?)
		local doc, hash, problem = Workspace.read(file, schema)
		if doc == nil or hash == nil then
			return nil, problem
		end
		local base = options.base
		if base ~= nil and base ~= hash then
			return nil,
				failure(
					"stale",
					"the file changed since the base version: expected "
						.. (base :: string)
						.. ", found "
						.. hash :: string
				)
		end
		local history = Workspace.loadHistory(file)
		if before then
			local refused = before(history, doc :: Document)
			if refused then
				return nil, refused
			end
		end
		local result, reason = Operations.apply(doc :: Document, schema, ops, internal)
		if result == nil then
			local code = if reason and string.find(reason, "changed after this edit", 1, true)
				then "conflict"
				else "invalid"
			return nil, failure(code, reason or "the batch failed")
		end
		local source = result.doc.source
		local changed = source ~= (doc :: Document).source
		local newHash = Workspace.hash(source)
		local entryId: number? = nil
		if changed then
			Workspace.writeText(file, source)
			local entry: Entry = {
				id = history.next,
				author = options.author,
				time = now(options),
				kind = kind,
				undone = false,
				base = hash :: string,
				result = newHash,
				ops = decodeList(ops),
				inverse = Operations.restoreOps(result.inverse),
			}
			history.next += 1
			if after then
				after(history, entry)
			end
			table.insert(history.entries, entry)
			saveHistory(file, history)
			entryId = entry.id
			if #result.remap > 0 then
				local store = Workspace.loadComments(file)
				if Comments.remap(store, result.remap) then
					saveComments(file, store)
				end
			end
		end
		return {
			file = file,
			hash = newHash,
			previous = hash :: string,
			changed = changed,
			entry = entryId,
			results = result.results,
			touched = result.touched,
			doc = result.doc,
			source = source,
		},
			nil
	end)
end

function Workspace.apply(file: string, ops: unknown, options: Options, schema: Schema.Schema?): (Applied?, Failure?)
	return commitBatch(file, schema, ops, options, "edit", false, nil, nil)
end

local function lastEntry(history: History, author: string, wanted: number?, kinds: { string }): Entry?
	for index = #history.entries, 1, -1 do
		local entry = history.entries[index]
		if wanted ~= nil then
			if entry.id == wanted then
				return entry
			end
		elseif entry.author == author and not entry.undone and table.find(kinds, entry.kind) then
			return entry
		end
	end
	return nil
end

function Workspace.undo(file: string, options: Options, schema: Schema.Schema?): (Applied?, Failure?)
	local history = Workspace.loadHistory(file)
	local target = lastEntry(history, options.author, options.entry, { "edit", "redo" })
	if target == nil then
		return nil, failure("not_found", "no edit by " .. options.author .. " to undo")
	end
	local found = target :: Entry
	if found.author ~= options.author then
		return nil,
			failure(
				"forbidden",
				"entry " .. found.id .. " belongs to " .. found.author .. "; an author can undo only its own edits"
			)
	end
	if found.undone or found.kind == "undo" then
		return nil, failure("invalid", "entry " .. found.id .. " is not an applied edit")
	end
	local targetId = found.id
	return commitBatch(file, schema, found.inverse, options, "undo", true, nil, function(current: History, entry: Entry)
		entry.target = targetId
		for _, existing in current.entries do
			if existing.id == targetId then
				existing.undone = true
			end
		end
	end)
end

function Workspace.redo(file: string, options: Options, schema: Schema.Schema?): (Applied?, Failure?)
	local history = Workspace.loadHistory(file)
	local undoEntry: Entry? = nil
	for index = #history.entries, 1, -1 do
		local entry = history.entries[index]
		if entry.author == options.author then
			if entry.kind == "edit" then
				break
			elseif entry.kind == "undo" and not entry.undone then
				undoEntry = entry
				break
			end
		end
	end
	if undoEntry == nil then
		return nil, failure("not_found", "no undo by " .. options.author .. " to redo")
	end
	local found = undoEntry :: Entry
	local undoId = found.id
	return commitBatch(file, schema, found.inverse, options, "redo", true, nil, function(current: History, entry: Entry)
		entry.target = found.target
		for _, existing in current.entries do
			if existing.id == undoId then
				existing.undone = true
			end
		end
	end)
end

function Workspace.history(file: string, limit: number?): { unknown }
	local history = Workspace.loadHistory(file)
	local result: { unknown } = {}
	local count = limit or 50
	for index = #history.entries, math.max(1, #history.entries - count + 1), -1 do
		table.insert(result, Workspace.entryJson(history.entries[index]))
	end
	return result
end

function Workspace.comment(
	file: string,
	action: string,
	input: { [string]: unknown },
	options: Options,
	schema: Schema.Schema?
): ({ [string]: unknown }?, Failure?)
	local authorProblem = Workspace.checkAuthor(options.author)
	if authorProblem then
		return nil, authorProblem
	end
	local doc, _, problem = Workspace.read(file, schema)
	if doc == nil then
		return nil, problem
	end
	local known: { [string]: boolean } = {}
	for id in (doc :: Document).nodes do
		known[id] = true
	end
	if action == "comment_list" then
		local store = Workspace.loadComments(file)
		local node = input.node
		local resolved = input.resolved
		local listed: { [string]: unknown } = {
			threads = Comments.list(
				store,
				if type(node) == "string" then node else nil,
				if type(resolved) == "boolean" then resolved else nil,
				known
			),
		}
		return listed, nil
	end
	return Workspace.withLock(file .. ".comments", function(): ({ [string]: unknown }?, Failure?)
		local store = Workspace.loadComments(file)
		local ok, result = pcall(function(): Comments.Thread
			if action == "comment_add" then
				local node = input.node :: string
				if not known[node] then
					local matches: { string } = {}
					for _, candidate in (doc :: Document).order do
						if candidate.label == node then
							table.insert(matches, candidate.id)
						end
					end
					if #matches ~= 1 then
						error("no node " .. node, 0)
					end
					node = matches[1]
				end
				return Comments.add(store, node, input.text :: string, options.author, now(options))
			elseif action == "comment_reply" then
				return Comments.reply(store, input.thread :: string, input.text :: string, options.author, now(options))
			end
			local resolved = input.resolved
			return Comments.resolve(
				store,
				input.thread :: string,
				if type(resolved) == "boolean" then resolved else true
			)
		end)
		if not ok then
			return nil, failure("invalid", tostring(result))
		end
		saveComments(file, store)
		local saved: { [string]: unknown } = { thread = Comments.threadJson(result :: Comments.Thread, known) }
		return saved, nil
	end)
end

function Workspace.isView(file: string): boolean
	local source = readText(file)
	if source == nil or not string.find(source :: string, "return%s+function") then
		return false
	end
	local doc = Document.parse(source :: string)
	return doc.root ~= nil
end

local SKIP: { [string]: boolean } = {
	[".git"] = true,
	["node_modules"] = true,
	vendor = true,
	artifacts = true,
	build = true,
	[".lute"] = true,
	[".claude"] = true,
}

function Workspace.discover(roots: { string }, limit: number?): { string }
	local found: { string } = {}
	local maximum = limit or 2000
	local function walk(path: string, depth: number)
		if #found >= maximum or depth > 24 then
			return
		end
		local ok, entries = pcall(fs.listDirectory, path)
		if not ok then
			return
		end
		local list = entries :: { fs.DirectoryEntry }
		table.sort(list, function(left: fs.DirectoryEntry, right: fs.DirectoryEntry): boolean
			return left.name < right.name
		end)
		for _, entry in list do
			local child = if path == "." then entry.name else path .. "/" .. entry.name
			if entry.type == "dir" then
				if not SKIP[entry.name] then
					walk(child, depth + 1)
				end
			elseif string.sub(entry.name, -5) == ".luau" and Workspace.isView(child) then
				table.insert(found, child)
			end
		end
	end
	for _, root in roots do
		local normalized = string.gsub(root, "\\", "/")
		if fs.exists(normalized) and fs.type(normalized) == "file" then
			table.insert(found, normalized)
		else
			walk(normalized, 0)
		end
	end
	return found
end

Workspace.restoreOps = Operations.restoreOps
Workspace.fail = Edit.fail

return table.freeze(Workspace)
