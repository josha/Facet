--!strict
-- Destination-owned lightweight bookmarks. Observe mounted native scroll hosts;
-- retain keys/offsets, never instances or page scopes after eviction.
local contribution = require("../input/contribution")
local bookmarks = {}
function bookmarks.captureIndex(index, keyAt, offset)
	if index.count == 0 then
		return { index = 1, delta = 0, offset = 0 }
	end
	local slot = math.clamp((index.window(offset, 0, 0)), 1, index.count)
	return { key = keyAt(slot), index = slot, delta = offset - index.offsetOf(slot), offset = offset }
end
function bookmarks.restoreIndex(index, slotOf, state, viewport)
	if index.count == 0 then
		return 0
	end
	local slot = math.clamp(slotOf(state.key) or state.index or 1, 1, index.count)
	return math.clamp(index.offsetOf(slot) + (state.delta or 0), 0, math.max(0, index.content - viewport))
end
function bookmarks.new(scope)
	local saved, watching = {}, {}
	local previousRoot, previousEpoch, previousGeometry
	scope:own(function()
		for _, watch in watching do
			watch.off()
		end
		table.clear(watching)
		table.clear(saved)
	end)
	local function anchors(controller, node, host)
		local rows = {}
		local function walk(n)
			if n ~= node then
				local rect = controller.screenRectOf(n.path)
				if rect then
					local start = (if host.axis == "x" then rect.x - host.rect.x else rect.y - host.rect.y)
						+ host.offset
					table.insert(rows, { key = string.sub(n.path, #node.path + 2), start = start })
				end
				if n.class == "ScrollView" then
					return
				end
			end
			for _, child in n.children or {} do
				walk(child)
			end
		end
		walk(node)
		table.sort(rows, function(a, b)
			return if a.start == b.start then a.key < b.key else a.start < b.start
		end)
		return rows
	end
	return {
		sync = function(controller, root)
			if not controller or not root then
				return
			end
			local epoch, geometry = controller.structureEpoch(), controller.geometryEpoch()
			if root == previousRoot and epoch == previousEpoch and geometry == previousGeometry then
				return
			end
			previousRoot, previousEpoch, previousGeometry = root, epoch, geometry

			local live = {}
			local function walk(node)
				if node.class == "ScrollView" then
					local path = node.path
					live[path] = true
					local watch = watching[path]
					if watch and watch.node ~= node then
						watch.off()
						watching[path] = nil
						watch = nil
					end
					local host = controller.scrollHostFor(path, true)
					if host then
						local bundle = contribution.read(node)
						local rows = if bundle and bundle.captureScrollBookmark
							then {}
							else anchors(controller, node, host)
						if not watch then
							watch = { node = node, rows = rows, restoring = false }
							watching[path] = watch
							local function capture()
								if watch.restoring then
									return
								end
								if bundle and bundle.captureScrollBookmark then
									saved[path] = bundle.captureScrollBookmark(controller, node)
									return
								end
								local current = controller.scrollHostFor(path, true)
								if not current then
									return
								end
								local index = 1
								for i, row in watch.rows do
									if row.start <= current.offset then
										index = i
									else
										break
									end
								end
								local row = watch.rows[index]
								saved[path] = {
									key = row and row.key,
									index = index,
									delta = if row then current.offset - row.start else 0,
									offset = current.offset,
								}
							end
							watch.off = controller.observeScroll(path, capture)
							local state = saved[path]
							if state then
								watch.restoring = true
								if bundle and bundle.restoreScrollBookmark then
									bundle.restoreScrollBookmark(controller, node, state)
								else
									local anchor
									for _, row in rows do
										if row.key == state.key then
											anchor = row
											break
										end
									end
									anchor = anchor or rows[math.clamp(state.index or 1, 1, math.max(1, #rows))]
									local value = math.clamp(
										if anchor then anchor.start + state.delta else state.offset,
										0,
										host.maxScroll
									)
									controller.scrollTo(path, {
										x = if host.axis == "x" then value else 0,
										y = if host.axis == "x" then 0 else value,
									})
								end
								watch.restoring = false
							end
							capture()
						else
							watch.rows = rows
						end
					end
				end
				for _, child in node.children or {} do
					walk(child)
				end
			end
			walk(root)
			for path, watch in watching do
				if not live[path] then
					watch.off()
					watching[path] = nil
				end
			end
		end,
	}
end
return bookmarks
