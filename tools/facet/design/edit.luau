--!strict

local Cst = require("./cst")
local Document = require("./document")
local SourceMap = require("./source_map")
local Values = require("./values")

type Document = Document.Document
type Node = Document.Node
type Span = SourceMap.Span

export type Splice = { start: number, finish: number, text: string }

export type Restore = {
	op: "restore_entries" | "restore_value" | "restore_label" | "restore_expr",
	node: string?,
	start: number?,
	count: number?,
	prop: string?,
	whole: boolean?,
	text: string,
	expect: string,
}

export type Change = { splice: Splice, anchor: number, inverse: Restore }

export type Block = {
	lead: string,
	core: string,
	trail: string,
	base: string,
	leadFixed: { [number]: boolean },
	coreFixed: { [number]: boolean },
}

export type Item = {
	start: number,
	coreFinish: number,
	finish: number,
	separator: boolean,
}

export type Regions = {
	tableExpr: Cst.Table,
	open: Span,
	close: Span,
	expanded: boolean,
	items: { Item },
	boundaries: { [number]: number },
	childIndent: string,
	lineIndent: string,
	comments: boolean,
}

local Edit = {}

local function fail(message: string): never
	error(message, 0)
end

Edit.fail = fail

function Edit.lineStart(source: string, offset: number): number
	local index = offset
	while index > 0 and string.byte(source, index) ~= 10 do
		index -= 1
	end
	return index
end

function Edit.indentAt(source: string, offset: number): (string, boolean)
	local start = Edit.lineStart(source, offset)
	local prefix = string.sub(source, start + 1, offset)
	local indent = string.match(prefix, "^[ \t]*") or ""
	return indent, #indent == #prefix
end

local function lineIndent(source: string, offset: number): string
	local start = Edit.lineStart(source, offset)
	return string.match(string.sub(source, start + 1), "^[ \t]*") or ""
end

local function fixedLines(doc: Document, start: number, text: string): { [number]: boolean }
	local fixed: { [number]: boolean } = {}
	local map = doc.map
	if map == nil then
		return fixed
	end
	local literals = SourceMap.protected(map, start, start + #text)
	if #literals == 0 then
		return fixed
	end
	local line = 1
	local offset = start
	for index = 1, #text do
		if string.byte(text, index) == 10 then
			line += 1
			local lineOffset = offset + index
			for _, span in literals do
				if span.start < lineOffset and lineOffset < span.finish then
					fixed[line] = true
				end
			end
		end
	end
	return fixed
end

function Edit.reindent(text: string, fixed: { [number]: boolean }, from: string, to: string, skipFirst: boolean): string
	if from == to or text == "" then
		return text
	end
	local lines = string.split(text, "\n")
	for index, line in lines do
		if (index == 1 and skipFirst) or fixed[index] or line == "" or line == "\r" then
			continue
		end
		if from == "" then
			lines[index] = to .. line
		elseif string.sub(line, 1, #from) == from then
			lines[index] = to .. string.sub(line, #from + 1)
		end
	end
	return table.concat(lines, "\n")
end

function Edit.newBlock(core: string, base: string): Block
	return { lead = "", core = core, trail = "", base = base, leadFixed = {}, coreFixed = {} }
end

function Edit.formatBlock(block: Block, indent: string, newline: string): string
	local lead = Edit.reindent(block.lead, block.leadFixed, block.base, indent, false)
	local core = Edit.reindent(block.core, block.coreFixed, block.base, indent, true)
	return lead .. indent .. core .. "," .. block.trail .. newline
end

function Edit.regions(doc: Document, tableExpr: Cst.Table): Regions
	local map = assert(doc.map, "the document has no source map")
	local source = doc.source
	local open = SourceMap.token(map, tableExpr.openBrace)
	local close = SourceMap.token(map, tableExpr.closeBrace)
	local items: { Item } = {}
	for _, entry in tableExpr.entries do
		local whole = SourceMap.item(map, entry)
		local core = SourceMap.core(map, entry)
		table.insert(items, {
			start = whole.start,
			coreFinish = core.finish,
			finish = whole.finish,
			separator = entry.separator ~= nil,
		})
	end
	local firstStart = if #items > 0 then items[1].start else close.start
	local expanded = string.find(string.sub(source, open.finish + 1, firstStart), "\n", 1, true) ~= nil
	local boundaries: { [number]: number } = {}
	boundaries[0] = if expanded then SourceMap.lineEnd(source, open.finish) else open.finish
	for index, item in items do
		boundaries[index] = if expanded then SourceMap.lineEnd(source, item.finish) else item.finish
	end
	local outer = lineIndent(source, open.start)
	local childIndent = outer .. doc.style.unit
	if expanded and #items > 0 then
		local indent, first = Edit.indentAt(source, items[1].start)
		if first then
			childIndent = indent
		end
	end
	local comments = false
	if not expanded then
		local cursor = open.finish
		for _, item in items do
			if string.find(string.sub(source, cursor + 1, item.start), "--", 1, true) then
				comments = true
			end
			cursor = item.finish
		end
		if string.find(string.sub(source, cursor + 1, close.start), "--", 1, true) then
			comments = true
		end
	end
	return {
		tableExpr = tableExpr,
		open = open,
		close = close,
		expanded = expanded,
		items = items,
		boundaries = boundaries,
		childIndent = childIndent,
		lineIndent = outer,
		comments = comments,
	}
end

function Edit.extract(doc: Document, regions: Regions, index: number): Block
	local source = doc.source
	local item = regions.items[index]
	local core = string.sub(source, item.start + 1, item.coreFinish)
	local indent, first = Edit.indentAt(source, item.start)
	if not regions.expanded then
		return {
			lead = "",
			core = core,
			trail = "",
			base = indent,
			leadFixed = {},
			coreFixed = fixedLines(doc, item.start, core),
		}
	end
	local regionStart = regions.boundaries[index - 1]
	local itemLine = if first then Edit.lineStart(source, item.start) else item.start
	local lead = if first and itemLine > regionStart then string.sub(source, regionStart + 1, itemLine) else ""
	local trailStart = if item.separator then item.finish else item.coreFinish
	local trail = string.sub(source, trailStart + 1, regions.boundaries[index])
	trail = string.gsub(trail, "\r?\n$", "")
	return {
		lead = lead,
		core = core,
		trail = trail,
		base = indent,
		leadFixed = fixedLines(doc, regionStart, lead),
		coreFixed = fixedLines(doc, item.start, core),
	}
end

local function restOfLine(source: string, offset: number): string
	local newline = string.find(source, "\n", offset + 1, true)
	local finish = if newline then newline - 1 else #source
	return string.sub(source, offset + 1, finish)
end

function Edit.renderTable(doc: Document, regions: Regions, blocks: { Block }): string
	if #blocks == 0 then
		return "{}"
	end
	local source = doc.source
	local inline = true
	local cores: { string } = {}
	for _, block in blocks do
		if block.lead ~= "" or block.trail ~= "" or string.find(block.core, "\n", 1, true) then
			inline = false
		end
		table.insert(cores, block.core)
	end
	if inline then
		local candidate = "{ " .. table.concat(cores, ", ") .. " }"
		local lineStart = Edit.lineStart(source, regions.open.start)
		local prefix = string.sub(source, lineStart + 1, regions.open.start)
		local suffix = restOfLine(source, regions.close.finish)
		local width = Values.visualWidth(prefix) + Values.visualWidth(candidate) + Values.visualWidth(suffix)
		if width <= doc.style.width then
			return candidate
		end
	end
	local newline = doc.style.newline
	local indent = regions.lineIndent .. doc.style.unit
	local parts = { "{" .. newline }
	for _, block in blocks do
		table.insert(parts, Edit.formatBlock(block, indent, newline))
	end
	table.insert(parts, regions.lineIndent .. "}")
	return table.concat(parts)
end

local function ownerTable(node: Node): Cst.Table
	local tableExpr = node.table
	if tableExpr == nil then
		fail("node " .. node.id .. " has no property table")
	end
	return tableExpr :: Cst.Table
end

function Edit.entries(doc: Document, owner: Node, start: number, count: number, blocks: { Block }): Change
	local source = doc.source
	local regions = Edit.regions(doc, ownerTable(owner))
	local items = regions.items
	local total = #items
	if start < 1 or start > total + 1 or count < 0 or start + count - 1 > total then
		fail("entry range " .. start .. "+" .. count .. " is outside node " .. owner.id)
	end
	if regions.comments then
		fail("node " .. owner.id .. " has comments inside a one-line table; edit it as code")
	end
	if regions.expanded and not (count == total and #blocks == 0 and total > 0) then
		local newline = doc.style.newline
		local preStart = start
		local from = regions.boundaries[start - 1]
		local to = regions.boundaries[start + count - 1]
		local parts: { string } = {}
		local widened = 0
		if #blocks > 0 and count == 0 and start == total + 1 and total >= 1 and not items[total].separator then
			local last = items[total]
			from = regions.boundaries[total - 1]
			preStart = total
			widened = 1
			table.insert(
				parts,
				string.sub(source, from + 1, last.coreFinish) .. "," .. string.sub(source, last.coreFinish + 1, to)
			)
		end
		if #blocks > 0 and to > 0 and string.byte(source, to) ~= 10 and from == to then
			table.insert(parts, newline)
		end
		for _, block in blocks do
			table.insert(parts, Edit.formatBlock(block, regions.childIndent, newline))
		end
		local text = table.concat(parts)
		local old = string.sub(source, from + 1, to)
		return {
			splice = { start = from, finish = to, text = text },
			anchor = owner.span.start,
			inverse = {
				op = "restore_entries",
				start = preStart,
				count = #blocks + widened,
				text = old,
				expect = text,
				whole = false,
			},
		}
	end
	local all: { Block } = {}
	for index = 1, start - 1 do
		table.insert(all, Edit.extract(doc, regions, index))
	end
	for _, block in blocks do
		table.insert(all, block)
	end
	for index = start + count, total do
		table.insert(all, Edit.extract(doc, regions, index))
	end
	local text = Edit.renderTable(doc, regions, all)
	local old = string.sub(source, regions.open.start + 1, regions.close.finish)
	return {
		splice = { start = regions.open.start, finish = regions.close.finish, text = text },
		anchor = owner.span.start,
		inverse = { op = "restore_entries", whole = true, text = old, expect = text },
	}
end

function Edit.restoreEntries(
	doc: Document,
	owner: Node,
	start: number,
	count: number,
	whole: boolean,
	text: string,
	expect: string
): Change
	local source = doc.source
	local regions = Edit.regions(doc, ownerTable(owner))
	local from: number
	local to: number
	if whole then
		from, to = regions.open.start, regions.close.finish
	else
		if not regions.expanded or start < 1 or start + count - 1 > #regions.items then
			fail("node " .. owner.id .. " changed after this edit")
		end
		from = regions.boundaries[start - 1]
		to = regions.boundaries[start + count - 1]
	end
	local current = string.sub(source, from + 1, to)
	if current ~= expect then
		fail("node " .. owner.id .. " changed after this edit")
	end
	local inverse: Restore = { op = "restore_entries", whole = whole, text = current, expect = text }
	if not whole then
		inverse.start = start
		inverse.count = Edit.countEntries(text)
	end
	return { splice = { start = from, finish = to, text = text }, anchor = owner.span.start, inverse = inverse }
end

function Edit.countEntries(text: string): number
	if text == "" then
		return 0
	end
	local ok, parsed = pcall(Cst.parseExpr, "{\n" .. text .. "}")
	if not ok then
		fail("restored entries do not parse")
	end
	local expr = parsed :: Cst.Expr
	if expr.tag ~= "table" then
		fail("restored entries do not parse")
	end
	return #(expr :: Cst.Table).entries
end

function Edit.value(doc: Document, node: Node, prop: Document.Prop, text: string): Change
	local map = assert(doc.map, "the document has no source map")
	local span = SourceMap.expr(map, prop.item.value)
	local old = string.sub(doc.source, span.start + 1, span.finish)
	return {
		splice = { start = span.start, finish = span.finish, text = text },
		anchor = node.span.start,
		inverse = { op = "restore_value", prop = prop.name, text = old, expect = text },
	}
end

function Edit.restoreValue(doc: Document, node: Node, prop: Document.Prop, text: string, expect: string): Change
	local map = assert(doc.map, "the document has no source map")
	local span = SourceMap.expr(map, prop.item.value)
	local current = string.sub(doc.source, span.start + 1, span.finish)
	if current ~= expect then
		fail("property " .. prop.name .. " of " .. node.id .. " changed after this edit")
	end
	return {
		splice = { start = span.start, finish = span.finish, text = text },
		anchor = node.span.start,
		inverse = { op = "restore_value", prop = prop.name, text = current, expect = text },
	}
end

local function labelRegion(doc: Document, node: Node): (number, number)
	local map = assert(doc.map, "the document has no source map")
	local head = node.head
	if head == nil then
		fail("node " .. node.id .. " has no label")
	end
	local headSpan = SourceMap.expr(map, head :: Cst.Expr)
	local labelString = node.labelString
	if labelString then
		return headSpan.finish, SourceMap.expr(map, labelString).finish
	end
	return headSpan.finish, headSpan.finish
end

function Edit.label(doc: Document, node: Node, label: string): Change
	local map = assert(doc.map, "the document has no source map")
	local from, to = labelRegion(doc, node)
	local old = string.sub(doc.source, from + 1, to)
	local text: string
	local labelString = node.labelString
	if labelString then
		local span = SourceMap.expr(map, labelString)
		local quote = if labelString.quoteStyle == "single" then "'" else '"'
		text = string.sub(doc.source, from + 1, span.start) .. quote .. label .. quote
	else
		text = ' "' .. label .. '"'
	end
	return {
		splice = { start = from, finish = to, text = text },
		anchor = node.span.start,
		inverse = { op = "restore_label", text = old, expect = text },
	}
end

function Edit.restoreLabel(doc: Document, node: Node, text: string, expect: string): Change
	local from, to = labelRegion(doc, node)
	local current = string.sub(doc.source, from + 1, to)
	if current ~= expect then
		fail("the label of " .. node.id .. " changed after this edit")
	end
	return {
		splice = { start = from, finish = to, text = text },
		anchor = node.span.start,
		inverse = { op = "restore_label", text = current, expect = text },
	}
end

function Edit.expr(doc: Document, node: Node, text: string): Change
	local old = string.sub(doc.source, node.span.start + 1, node.span.finish)
	return {
		splice = { start = node.span.start, finish = node.span.finish, text = text },
		anchor = node.span.start,
		inverse = { op = "restore_expr", text = old, expect = text },
	}
end

function Edit.restoreExpr(doc: Document, node: Node, text: string, expect: string): Change
	local current = string.sub(doc.source, node.span.start + 1, node.span.finish)
	if current ~= expect then
		fail("node " .. node.id .. " changed after this edit")
	end
	return {
		splice = { start = node.span.start, finish = node.span.finish, text = text },
		anchor = node.span.start,
		inverse = { op = "restore_expr", text = current, expect = text },
	}
end

function Edit.apply(source: string, splice: Splice): string
	return string.sub(source, 1, splice.start) .. splice.text .. string.sub(source, splice.finish + 1)
end

function Edit.childIndent(doc: Document, node: Node): string
	return Edit.regions(doc, ownerTable(node)).childIndent
end

function Edit.nodeBlock(doc: Document, node: Node): Block
	local parent = node.parent
	if node.slot == "entry" and parent and parent.table and node.entry then
		local regions = Edit.regions(doc, parent.table :: Cst.Table)
		return Edit.extract(doc, regions, node.entry :: number)
	end
	local core = Document.text(doc, node.span)
	local indent = Edit.indentAt(doc.source, node.span.start)
	return {
		lead = "",
		core = core,
		trail = "",
		base = indent,
		leadFixed = {},
		coreFixed = fixedLines(doc, node.span.start, core),
	}
end

function Edit.relabel(doc: Document, node: Node, block: Block, label: string): Block
	local map = assert(doc.map, "the document has no source map")
	local head = node.head
	if head == nil then
		fail("node " .. node.id .. " cannot take a label")
	end
	local parent = node.parent
	local coreStart = node.span.start
	if node.slot == "entry" and parent and parent.table and node.entry then
		local regions = Edit.regions(doc, parent.table :: Cst.Table)
		coreStart = regions.items[node.entry :: number].start
	end
	local from, to = labelRegion(doc, node)
	local replacement: string
	local labelString = node.labelString
	if labelString then
		local span = SourceMap.expr(map, labelString)
		local quote = if labelString.quoteStyle == "single" then "'" else '"'
		replacement = string.sub(doc.source, from + 1, span.start) .. quote .. label .. quote
	else
		replacement = ' "' .. label .. '"'
	end
	local relativeFrom = from - coreStart
	local relativeTo = to - coreStart
	local core = string.sub(block.core, 1, relativeFrom) .. replacement .. string.sub(block.core, relativeTo + 1)
	return {
		lead = block.lead,
		core = core,
		trail = block.trail,
		base = block.base,
		leadFixed = block.leadFixed,
		coreFixed = block.coreFixed,
	}
end

return table.freeze(Edit)
