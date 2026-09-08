--!strict
-- Repositions a clean permutation using the previous row extents. Hosted rows
-- retain their complete entry and move only their origin; descendants stay local.
-- All refusal checks precede writes. The ordinary stack remains the oracle.
local permutation = require("./row_permutation")
local prefix = {}
local ENABLED = true -- counter-only arm validates then takes the ordinary stack

function prefix.try(ctx: any, node: any, x: number, y: number, gap: number, order: any, place: any, out: any): boolean
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
	local previous = ctx.reuse.previous.rects
	local contains = ctx.reuse.dirtyContains
	local hosts = 0
	for i, child in children do
		local old = order[i]
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
	if not ENABLED or hosts < 2 then
		return false
	end
	local isH = node.kind == "hstack"
	local cursor = if isH then x else y
	local rects, index = {}, {}
	local cuts = 0
	for i, child in children do
		local old = order[i]
		local was = memo.pRect[old]
		local rect = { x = if isH then cursor else was.x, y = if isH then was.y else cursor, w = was.w, h = was.h }
		cursor += memo.pMain[old] + gap
		cuts += memo.pCuts[old] or 0
		ctx.offers[child.wKey or (child.id .. "|w")] = memo.pInnerW
		ctx.offers[child.hKey or (child.id .. "|h")] = memo.pInnerH
		if rect.x == was.x and rect.y == was.y then
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
	for _, finding in memo.pIssues or {} do
		table.insert(ctx.diagnostics, finding)
	end
	for _, field in { "pMain", "pCross", "pIds", "pMarg", "pAl", "pFlag", "pCuts" } do
		memo[field] = permutation.remap(memo[field], order)
	end
	memo.pRect = rects
	memo.pToken = node.kidToken
	memo.pIdx = index
	memo.pIdxToken = node.kidToken
	return true
end

return prefix
