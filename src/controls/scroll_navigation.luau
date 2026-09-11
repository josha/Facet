--!strict
-- Optional mounted ScrollView behavior. Geometry is indexed after layout; native
-- samples read that index, never walk the tree or schedule an idle frame loop.
local guard = require("../spec_guard")
local snap = require("./scroll_snap")
local navigation = {}
function navigation.validate(spec)
	guard.assertKnownKeys(
		"ScrollView.navigation",
		spec,
		guard.keySet({ "targets", "target", "snap", "progress", "threshold", "onVisibilityChanged", "focus" }),
		"navigation"
	)
	assert(
		type(spec.targets) == "table",
		"ScrollView.navigation.targets must be an array of descendant IDs or relative paths"
	)
	local seen = {}
	for index, id in spec.targets do
		assert(
			type(index) == "number" and index >= 1 and index <= #spec.targets and index % 1 == 0,
			"ScrollView.navigation.targets must be a dense array"
		)
		assert(
			type(id) == "string" and id ~= "" and not seen[id],
			"ScrollView.navigation targets must be unique nonempty names"
		)
		seen[id] = true
	end
	assert(spec.snap == nil or type(spec.snap) == "boolean", "ScrollView.navigation.snap must be boolean")
	assert(
		spec.focus == nil or spec.focus == "preserve" or spec.focus == "target",
		"ScrollView.navigation.focus must be preserve | target"
	)
	local threshold = spec.threshold or 0.5
	assert(
		type(threshold) == "number" and threshold > 0 and threshold <= 1,
		"ScrollView.navigation.threshold must be in (0, 1]"
	)
	for _, name in { "target", "progress" } do
		local v = spec[name]
		assert(
			v == nil
				or (type(v) == "table" and type(v.get) == "function" and (name ~= "progress" or v.kind == "signal")),
			"ScrollView.navigation: " .. name .. " must be a readable (progress must be a signal)"
		)
	end
	assert(
		spec.onVisibilityChanged == nil or type(spec.onVisibilityChanged) == "function",
		"ScrollView.navigation.onVisibilityChanged must be a function"
	)
end
function navigation.new(core, scope, spec)
	local controller, node, off, offIntent
	local graph, focusRequest, arrived, focusOff
	local travelTarget
	local function cancelFocus()
		focusRequest, arrived = nil, nil
	end
	local writing = false
	local frameworkOffset = nil
	local callbackError = nil
	local geometryEpoch, structureEpoch = nil, nil
	local entries, visible = {}, {}
	local pending = if spec.target then spec.target:get() else nil
	assert(pending == nil or type(pending) == "string", "ScrollView.navigation.target must contain a name or nil")
	local maxScroll, band, offset, isX = 0, 0, 0, false
	local function write(value)
		if controller and node then
			frameworkOffset = nil
			writing = true
			controller.scrollTo(node.path, { x = if isX then value else 0, y = if isX then 0 else value })
			writing = false
		end
	end
	local engine = snap.new({
		core = core,
		scope = scope,
		index = function()
			return nil
		end,
		viewport = function()
			return band
		end,
		mode = function()
			return if spec.snap then "item" else "none"
		end,
		write = write,
		onArrive = function()
			arrived = focusRequest
			travelTarget = nil
		end,
		onInterrupt = function()
			travelTarget = nil
			cancelFocus()
		end,
		resolve = function(request)
			local best = if request.offset > maxScroll / 2 then maxScroll else 0
			for _, entry in entries do
				-- Keep oversized sections freely scrollable so all their content remains reachable.
				if
					entry.size > band
					and request.offset >= entry.start
					and request.offset < entry.start + entry.size - band
				then
					return nil
				end
				local candidate = math.clamp(entry.start, 0, maxScroll)
				if math.abs(candidate - request.offset) < math.abs(best - request.offset) then
					best = candidate
				end
			end
			return best
		end,
	})
	scope:own(engine)
	local function announce(id, on)
		visible[id] = on
		local ok, err = pcall(spec.onVisibilityChanged, id, on)
		if not ok and tostring(err) ~= callbackError then
			callbackError = tostring(err)
			warn("Facet ScrollView.navigation: visibility callback quarantined: " .. callbackError)
		end
	end
	local function publish()
		if spec.progress then
			spec.progress:set(if maxScroll > 0 then math.clamp(offset / maxScroll, 0, 1) else 0)
		end
		if spec.onVisibilityChanged then
			for _, entry in entries do
				local overlap =
					math.max(0, math.min(entry.start + entry.size, offset + band) - math.max(entry.start, offset))
				local on = entry.size > 0 and overlap / math.min(entry.size, band) >= (spec.threshold or 0.5)
				if visible[entry.id] ~= on then
					announce(entry.id, on)
				end
			end
		end
	end
	local function seek(retargeting)
		if pending == nil or not controller or not node then
			return
		end
		for _, entry in entries do
			if entry.id == pending then
				pending = nil
				travelTarget = entry.id
				if not retargeting then
					focusRequest = if spec.focus == "target" and graph then entry.path else nil
				end
				engine.travel(offset, math.clamp(entry.start, 0, maxScroll))
				return
			end
		end
		if retargeting then
			-- An interrupted trip cannot regain focus when a removed target returns.
			pending, travelTarget = nil, nil
			cancelFocus()
		end
	end
	if spec.target then
		scope:own(core:observe(spec.target, function(id)
			assert(id == nil or type(id) == "string", "ScrollView.navigation.target must contain a name or nil")
			pending = id
			cancelFocus()
		end))
	end
	scope:own(function()
		if focusOff then
			focusOff()
		end
		if offIntent then
			offIntent()
			offIntent = nil
		end
		if off then
			off()
			off = nil
		end
	end)
	return {
		bindFocusGraph = function(g)
			if graph == g then
				return
			end
			if focusOff then
				focusOff()
			end
			graph = g
			focusOff = core:observe(g.focused, cancelFocus)
		end,
		bindInputScope = function(input)
			scope:own(input.onTick(function()
				if not arrived or not graph then
					return
				end
				local path = arrived
				cancelFocus()
				local map = graph.focusMap()
				for _, entry in (map and map.traversal) or {} do
					if
						(entry.path == path or string.sub(entry.path, 1, #path + 1) == path .. "/")
						and graph.focusOn(entry.path)
					then
						break
					end
				end
			end))
		end,
		bindController = function(c)
			controller = c
		end,
		bindMotion = function(clock)
			engine.bindMotion(clock)
		end,
		syncGeometry = function(_, root)
			if not controller or not root then
				return
			end
			if node ~= root then
				if off then
					off()
				end
				node = root
				geometryEpoch = nil
				if offIntent then
					offIntent()
				end
				offIntent = controller.observeScrollIntent(node.path, function(pos)
					if not writing then
						cancelFocus()
						frameworkOffset = math.clamp(if isX then pos.x else pos.y, 0, maxScroll)
						engine.rest(frameworkOffset)
					end
				end)
				off = controller.observeScroll(node.path, function(pos)
					offset = if isX then pos.x else pos.y
					if frameworkOffset ~= nil and math.abs(offset - frameworkOffset) <= 0.5 then
						engine.rest(offset)
					else
						frameworkOffset = nil
						engine.sample(offset)
					end
					publish()
				end)
			end
			local structure, geometry = controller.structureEpoch(), controller.geometryEpoch()
			if geometryEpoch == geometry and structureEpoch == structure then
				seek()
				return
			end
			geometryEpoch, structureEpoch = geometry, structure

			local host = controller.scrollHostFor(root.path, true)
			if not host then
				return
			end
			local changedAxis = isX ~= (host.axis == "x")
			local retargeting = changedAxis and pending == nil and travelTarget ~= nil
			local retainedFocus = if retargeting then focusRequest else nil
			if changedAxis then
				pending = pending or travelTarget
				frameworkOffset = nil
				cancelFocus()
				engine.rest(host.offset)
			end
			isX = host.axis == "x"
			maxScroll = host.maxScroll
			band = if isX then host.rect.w else host.rect.h
			offset = host.offset
			local paths = {}
			local function walk(n)
				if n ~= root then
					paths[n.id] = paths[n.id] or n.path
					paths[string.sub(n.path, #root.path + 2)] = n.path
					if n.class == "ScrollView" then
						return
					end
				end
				for _, child in n.children or {} do
					walk(child)
				end
			end
			walk(root)
			entries = {}
			for _, id in spec.targets do
				local rect = paths[id] and controller.screenRectOf(paths[id])
				if rect then
					table.insert(entries, {
						id = id,
						path = paths[id],
						start = (if isX then rect.x - host.rect.x else rect.y - host.rect.y) + offset,
						size = if isX then rect.w else rect.h,
					})
				end
			end
			local present = {}
			for _, entry in entries do
				present[entry.id] = true
			end
			for id, on in visible do
				if not present[id] then
					if on then
						announce(id, false)
					end
					visible[id] = nil
				end
			end
			if focusRequest then
				local found = false
				for _, entry in entries do
					if entry.path == focusRequest then
						found = true
					end
				end
				if not found then
					cancelFocus()
				end
			end
			publish()
			if retargeting then
				focusRequest = retainedFocus
			end
			seek(retargeting)
		end,
	}
end
function navigation.attach(core, scope, bp)
	local contribution = require("../input/contribution")
	local bundle = table.clone(contribution.read(bp) or {})
	for name, callback in navigation.new(core, scope, bp.meta.scrollNavigation) do
		local previous = bundle[name]
		bundle[name] = if previous
			then function(...)
				previous(...)
				return callback(...)
			end
			else callback
	end
	return contribution.attach(bp, bundle)
end
return navigation
