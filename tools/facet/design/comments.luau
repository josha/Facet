--!strict

local Wire = require("./wire")

export type Message = { id: string, author: string, text: string, time: number }

export type Thread = {
	id: string,
	node: string,
	resolved: boolean,
	created: number,
	messages: { Message },
}

export type Store = { version: number, next: number, threads: { Thread } }

export type Remap = { from: string, to: string }

local Comments = {}

Comments.MAX_TEXT = 4000
Comments.MAX_THREADS = 1000

function Comments.empty(): Store
	return { version = 1, next = 1, threads = {} }
end

local function asString(value: unknown, fallback: string): string
	return if type(value) == "string" then value else fallback
end

local function asNumber(value: unknown, fallback: number): number
	return if type(value) == "number" then value else fallback
end

function Comments.decode(text: string): (Store?, string?)
	local ok, value = Wire.decode(text)
	if not ok or type(value) ~= "table" then
		return nil, "the comments file is not valid JSON"
	end
	local store = Comments.empty()
	store.next = math.max(1, asNumber(Wire.field(value, "next"), 1))
	for _, raw in Wire.list(Wire.field(value, "threads")) do
		local messages: { Message } = {}
		for _, message in Wire.list(Wire.field(raw, "messages")) do
			table.insert(messages, {
				id = asString(Wire.field(message, "id"), ""),
				author = asString(Wire.field(message, "author"), "unknown"),
				text = asString(Wire.field(message, "text"), ""),
				time = asNumber(Wire.field(message, "time"), 0),
			})
		end
		table.insert(store.threads, {
			id = asString(Wire.field(raw, "id"), ""),
			node = asString(Wire.field(raw, "node"), ""),
			resolved = Wire.field(raw, "resolved") == true,
			created = asNumber(Wire.field(raw, "created"), 0),
			messages = messages,
		})
	end
	return store, nil
end

function Comments.encode(store: Store): string
	return Wire.encode(Comments.json(store), true) .. "\n"
end

function Comments.threadJson(thread: Thread, known: { [string]: boolean }?): { [string]: unknown }
	local messages: { unknown } = {}
	for _, message in thread.messages do
		table.insert(messages, { id = message.id, author = message.author, text = message.text, time = message.time })
	end
	local result: { [string]: unknown } = {
		id = thread.id,
		node = thread.node,
		resolved = thread.resolved,
		created = thread.created,
		messages = messages,
	}
	if known then
		result.orphaned = not known[thread.node]
	end
	return result
end

function Comments.json(store: Store): { [string]: unknown }
	local threads: { unknown } = {}
	for _, thread in store.threads do
		table.insert(threads, Comments.threadJson(thread))
	end
	return { version = store.version, next = store.next, threads = threads }
end

local function checkText(text: string)
	if text == "" or #text > Comments.MAX_TEXT then
		error("a comment needs 1 to " .. Comments.MAX_TEXT .. " bytes of text", 0)
	end
end

function Comments.find(store: Store, id: string): Thread?
	for _, thread in store.threads do
		if thread.id == id then
			return thread
		end
	end
	return nil
end

function Comments.add(store: Store, node: string, text: string, author: string, time: number): Thread
	checkText(text)
	if #store.threads >= Comments.MAX_THREADS then
		error("a file allows at most " .. Comments.MAX_THREADS .. " comment threads", 0)
	end
	local id = "t" .. store.next
	store.next += 1
	local thread: Thread = {
		id = id,
		node = node,
		resolved = false,
		created = time,
		messages = { { id = id .. ".1", author = author, text = text, time = time } },
	}
	table.insert(store.threads, thread)
	return thread
end

function Comments.reply(store: Store, threadId: string, text: string, author: string, time: number): Thread
	checkText(text)
	local thread = Comments.find(store, threadId)
	if thread == nil then
		error("no comment thread " .. threadId, 0)
	end
	local found = thread :: Thread
	table.insert(found.messages, {
		id = found.id .. "." .. (#found.messages + 1),
		author = author,
		text = text,
		time = time,
	})
	return found
end

function Comments.resolve(store: Store, threadId: string, resolved: boolean): Thread
	local thread = Comments.find(store, threadId)
	if thread == nil then
		error("no comment thread " .. threadId, 0)
	end
	local found = thread :: Thread
	found.resolved = resolved
	return found
end

function Comments.remap(store: Store, remaps: { Remap }): boolean
	local changed = false
	for _, remap in remaps do
		for _, thread in store.threads do
			if thread.node == remap.from then
				thread.node = remap.to
				changed = true
			elseif string.sub(thread.node, 1, #remap.from + 1) == remap.from .. "/" then
				thread.node = remap.to .. string.sub(thread.node, #remap.from + 1)
				changed = true
			end
		end
	end
	return changed
end

function Comments.list(store: Store, node: string?, resolved: boolean?, known: { [string]: boolean }?): { unknown }
	local threads: { unknown } = {}
	for _, thread in store.threads do
		if node ~= nil and thread.node ~= node and string.sub(thread.node, 1, #node + 1) ~= node .. "/" then
			continue
		end
		if resolved ~= nil and thread.resolved ~= resolved then
			continue
		end
		table.insert(threads, Comments.threadJson(thread, known))
	end
	return threads
end

return table.freeze(Comments)
