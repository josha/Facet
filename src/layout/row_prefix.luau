--!strict
-- Repositions a clean permutation using the previous row extents. Hosted rows
-- retain their complete entry and move only their origin; descendants stay local.
-- All refusal checks precede writes. The ordinary stack remains the oracle.
local permutation = require("./row_permutation")
local alignOffset = require("./placement").alignOffset
local prefix = {}
local ENABLED = true -- counter-only arm validates then takes the ordinary stack

function prefix.overflow(node: any, deficit: number, shrinkOrder: string?): any
	local issue = string.format(
		"content overflows this %s by %dpx on the main axis; it will paint outside its box "
			.. "(wrap it in a ScrollView, or give it room)",
		node.kind,
		deficit
	)
	if shrinkOrder ~= nil then
		issue ..= string.format(
			" — every shrinkable child is already at its floor (layoutPriority order tried: %s), "
				.. "so the box CLIPPED the remaining %dpx",
			shrinkOrder,
			deficit
		)
	end
	return { node = node.id, issue = issue }
end

function prefix.try(
	ctx: any,
	node: any,
	x: number,
	y: number,
	gap: number,
	order: any,
	place: any,
	out: any,
	enabled: boolean?,
	deps: any?
): boolean
	local memo = node.cmemo
	if
		order == nil
		or memo.pInnerX ~= x
		or memo.pInnerY ~= y
		or memo.pGap ~= gap
		or memo.pAlign ~= node.align
		or memo.pDistribute ~= node.distribute
		or (node.distribute ~= nil and node.distribute ~= "start")
		or memo.pNoted == true
		or gap % 1 ~= 0
	then
		return false
	end
	local children = node.children
	local isH = node.kind == "hstack"
	local inserted = memo.pN < #children
	local appended = inserted and (memo.pN == 0 or order[memo.pN] == memo.pN)
	local previous = ctx.reuse.previous.rects
	local contains = ctx.reuse.dirtyContains
	local hosts = 0
	for i, child in children do
		local old = order[i]
		if old == 0 then
			-- New rows use normal measurement; flexible main/aspect dimensions
			-- need the full pass.
			local main = deps.mainDimOf(child, isH)
			local cross = deps.dim(child, if isH then "h" else "w")
			local mt, mr, mb, ml = deps.sides(child.margin)
			if
				previous[child.id] ~= nil
				or (main.type ~= "fixed" and main.type ~= "content")
				or (cross.type ~= "fill" and cross.type ~= "fixed" and cross.type ~= "content")
				or mt ~= 0
				or mr ~= 0
				or mb ~= 0
				or ml ~= 0
			then
				return false
			end
			continue
		end
		local rect = memo.pRect[old]
		local entry = previous[child.id]
		local flag = memo.pFlag[old]
		if
			contains[child.id] == true
			or memo.pMarg[old] ~= false
			or rect == nil
			or entry == nil
			or entry.rect.x ~= rect.x
			or entry.rect.y ~= rect.y
			or entry.rect.w ~= rect.w
			or entry.rect.h ~= rect.h
			or (flag ~= 0 and flag ~= 2)
			or memo.pMain[old] % 1 ~= 0
		then
			return false
		end
		if child.hostSpace == true then
			hosts += 1
		end
	end
	if not ENABLED or enabled == false or hosts < 2 then
		return false
	end
	local savedCuts = memo.pCuts
	-- Invalidate before measurement/placement can throw; publish the key last.
	memo.pCuts = nil
	if inserted and not appended then
		-- Order-preserving insertion only shifts old slots to the right. Walking
		-- backwards keeps every unread answer intact without copying seven arrays.
		for _, field in { "pMain", "pCross", "pIds", "pMarg", "pAl", "pFlag", "pCuts" } do
			local values = if field == "pCuts" then savedCuts else memo[field]
			for i = #children, 1, -1 do
				values[i] = values[order[i]]
			end
		end
	end
	local cursor = if isH then x else y
	local rects, index = {}, {}
	local cuts = 0
	for i, child in children do
		local old = order[i]
		if old == 0 then
			local before = ctx.fitCuts
			local w, h = deps.measure(ctx, child, memo.pInnerW, memo.pInnerH)
			savedCuts[i] = ctx.fitCuts - before
			local main = if isH then w else h
			local crossAvail = math.max(0, if isH then memo.pInnerH else memo.pInnerW)
			local crossFill = deps.dim(child, if isH then "h" else "w").type == "fill"
			local align = child.lineAlign or child.align or node.align
			local cross = if crossFill or align == "stretch"
				then crossAvail
				else math.min(if isH then h else w, crossAvail)
			local offset = alignOffset(align, crossAvail, cross)
			local rect = {
				x = if isH then cursor else x + offset,
				y = if isH then y + offset else cursor,
				w = if isH then main else cross,
				h = if isH then cross else main,
			}
			place(ctx, child, rect, out)
			rects[i], index[child.id] = rect, i
			memo.pMain[i], memo.pCross[i] = main, if isH then h else w
			memo.pIds[i], memo.pMarg[i] = child.id, false
			memo.pAl[i], memo.pFlag[i] = align, if crossFill then 2 else 0
			cursor += main + gap
			continue
		end
		local was = memo.pRect[old]
		local slot = if inserted then i else old
		local rect = if appended or cursor == (if isH then was.x else was.y)
			then was
			else { x = if isH then cursor else was.x, y = if isH then was.y else cursor, w = was.w, h = was.h }
		cursor += memo.pMain[slot] + gap
		if child.kind == "text" then
			-- Republish text fit/wrap verdicts at the unchanged offer.
			local before = ctx.fitCuts
			deps.measure(ctx, child, memo.pInnerW, memo.pInnerH)
			savedCuts[slot] = ctx.fitCuts - before
		else
			cuts += savedCuts[slot] or 0
		end
		ctx.offers[child.wKey or (child.id .. "|w")] = memo.pInnerW
		ctx.offers[child.hKey or (child.id .. "|h")] = memo.pInnerH
		if rect.x == was.x and rect.y == was.y and child.kind ~= "text" then
			rects[i] = was
			ctx.placeSkipped += 1
		elseif child.hostSpace == true then
			local prev = previous[child.id]
			local entry = table.clone(prev)
			entry.rect = table.freeze(rect)
			entry.moveOnly = true
			entry.prev = prev
			prev.prev = nil
			out[child.id] = entry
			local from = #ctx.translatedPaths + 1
			ctx.translatedRoots[child.id] = { dx = rect.x - was.x, dy = rect.y - was.y, from = from, to = from - 1 }
			ctx.arranged += 1
			ctx.rectInserts += 1
			rects[i] = rect
		else
			place(ctx, child, rect, out)
			rects[i] = rect
		end
		index[child.id] = i
	end
	ctx.fitCuts += cuts
	ctx.placeScanned += #children
	-- Refile unchanged container findings; integer, zero-margin contributions keep
	-- the total identical under permutation. Cross containment was absent above.
	if memo.pN ~= #children then
		local total = cursor - (if isH then x else y) - (if #children > 0 then gap else 0)
		local deficit = total - (if isH then memo.pInnerW else memo.pInnerH)
		memo.pShort = deficit > 0
		memo.pIssues = if deficit > 0 and ctx.hiddenDepth == 0 then { prefix.overflow(node, deficit, nil) } else nil
	end
	for _, finding in memo.pIssues or {} do
		table.insert(ctx.diagnostics, finding)
	end
	if not inserted then
		for _, field in { "pMain", "pCross", "pIds", "pMarg", "pAl", "pFlag" } do
			memo[field] = permutation.remap(memo[field], order)
		end
		savedCuts = permutation.remap(savedCuts, order)
	end
	memo.pN = #children
	memo.pRect = rects
	memo.pToken = node.kidToken
	memo.pIdx = index
	memo.pIdxToken = node.kidToken
	memo.pCuts = savedCuts
	return true
end

return prefix
