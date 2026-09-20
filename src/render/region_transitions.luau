--!strict
-- Structural regions with a declared `transition`. Compose owns identity and
-- lifetime: `presence` holds a When branch through its exit and reclaims it on a
-- reversal, and a keyed source retains a leaving row until its exit lands. The
-- surface's transition coordinator owns every presentation write.
local Compose = require("../vendor/compose/core")
local transitions = require("./transitions")

local regions = {}

-- The enters of one region. A branch builds detached, so its path and its
-- coordinator exist only once the enclosing insert lands: an enter waits for
-- the reactive pass after that insert, or for the surface to bind.
local function motionOf(declared: any)
	-- A plain declaration is refused where it is written. A readable is sampled
	-- and validated when an operation starts.
	if not Compose.isReadable(declared) then
		transitions.resolve(declared)
	end
	local waiting: { any } = {}
	local coordinators: { [any]: any } = {}
	local tick = Compose.cell(0)
	local motion = {}

	local function begin(mounted: any): boolean
		local coordinator = transitions.coordinatorOf(mounted)
		if mounted.path == nil or coordinator == nil then
			return false
		end
		coordinators[mounted] = coordinator
		if not mounted.retiring then
			coordinator.beginEnter(mounted.path, mounted, declared)
		end
		return true
	end

	function motion.drain()
		local index = 1
		while index <= #waiting do
			if begin(waiting[index]) then
				table.remove(waiting, index)
			else
				index += 1
			end
		end
	end

	function motion.enter(mounted: any)
		if not begin(mounted) then
			table.insert(waiting, mounted)
			tick:set(tick:peek() + 1)
		end
	end

	-- nil when the subtree leaves at once: no coordinator, or an instant exit
	function motion.exit(mounted: any, done: () -> ()): boolean
		local coordinator = transitions.coordinatorOf(mounted)
		local spec = if coordinator ~= nil and mounted.path ~= nil
			then coordinator.shouldRetire(mounted.path, mounted)
			else nil
		if spec == nil then
			return false
		end
		coordinators[mounted] = coordinator
		coordinator.beginExit(mounted.path, mounted, spec, done)
		return true
	end

	function motion.cancelExit(mounted: any)
		local coordinator = coordinators[mounted]
		if coordinator ~= nil then
			coordinator.cancelExit(mounted.path)
		end
	end

	function motion.release(mounted: any)
		local at = table.find(waiting, mounted)
		if at ~= nil then
			table.remove(waiting, at)
		end
		local coordinator = coordinators[mounted]
		coordinators[mounted] = nil
		if coordinator ~= nil then
			if coordinator.release ~= nil then
				coordinator.release(mounted.path)
			else
				coordinator.cancelExit(mounted.path)
			end
		end
	end

	Compose.watch(function(use)
		use(tick)
		motion.drain()
	end)
	return motion
end

local function branch(gate: () -> any, motion: any, declared: any, condition: any, segment: string?, view: () -> any)
	return Compose.presence(condition, function(phase)
		local mounted = view()
		mounted.collectionKey = segment
		mounted.transition = declared
		Compose.cleanup(function()
			motion.release(mounted)
		end)
		Compose.watch(function(use)
			if use(phase.exiting) then
				mounted.retiring = true
			else
				if mounted.retiring then
					motion.cancelExit(mounted)
				end
				mounted.retiring = nil
				motion.enter(mounted)
			end
			local region = gate()
			if region ~= nil then
				transitions.markStructure(region)
			end
		end)
		return mounted
	end, {
		exit = function(nodes)
			local completed = Compose.cell(false)
			if not motion.exit(nodes[1], function()
				completed:set(true)
			end) then
				completed:set(true)
			end
			return { completed = completed }
		end,
	})
end

-- An ANONYMOUS region is legal: Compose's constructor takes either a name or the
-- props table, and `ctor(nil)` is neither.
local function named(ctor: any, id: any): any
	return if id ~= nil then ctor(id) else ctor
end

local function sourceOf(source: any): (use: any) -> any
	if type(source) == "function" then
		return source
	elseif Compose.isReadable(source) then
		return function(use)
			return use(source)
		end
	end
	return function()
		return source
	end
end

function regions.when(region: any, spec: any)
	local declared = spec.transition
	local motion = motionOf(declared)
	local condition = sourceOf(spec.condition)
	local node
	local function gate()
		return node
	end
	node = named(region, spec.id)({
		branch(gate, motion, declared, condition, "then", spec.thenView),
		if spec.elseView
			then branch(gate, motion, declared, function(use)
				return not condition(use)
			end, "else", spec.elseView)
			else nil,
	})
	node.drainTransitions = motion.drain
	return node
end

-- The enters and exits of nodes a control holds itself. The control marks its
-- container with `drainTransitions = motion.drain`.
regions.motion = motionOf

-- A transitioned branch placed straight into a control's own container, with
-- no region node and no path segment. `adopt` names that container once it
-- exists: it carries the retiring structure marks and the waiting enters.
function regions.branch(declared: any, condition: any, view: () -> any): (any, (host: any) -> ())
	local motion = motionOf(declared)
	local host
	local directive = branch(function()
		return host
	end, motion, declared, condition, nil, view)
	return directive,
		function(node: any)
			host = node
			local inner = node.drainTransitions
			node.drainTransitions = if inner ~= nil
				then function()
					inner()
					motion.drain()
				end
				else motion.drain
		end
end

function regions.forEach(region: any, spec: any)
	local declared = spec.transition
	local motion = motionOf(declared)
	local items = sourceOf(spec.items)
	local entries: { [any]: any } = {}
	local retiring: { [any]: any } = {}
	local wake = Compose.cell(0)
	local node

	-- The authored items, plus every row still playing its exit, each held at
	-- the slot it is leaving from.
	local function retained(use)
		use(wake)
		local current = items(use)
		local wanted, result = {}, table.clone(current)
		for _, item in current do
			wanted[spec.key(item)] = true
		end
		local touched = false
		for key, entry in entries do
			local held = retiring[key]
			if wanted[key] then
				if held then
					held.finished = true
					retiring[key] = nil
					motion.cancelExit(entry.mounted)
					entry.mounted.retiring = nil
					motion.enter(entry.mounted)
					touched = true
				end
			elseif not held then
				local record =
					{ index = table.find(node.children, entry.mounted) or 1, entry = entry, finished = false }
				local starting = true
				local retired = motion.exit(entry.mounted, function()
					if not record.finished then
						record.finished = true
						-- an exit that lands as it starts leaves in this same pass
						if not starting then
							wake:set(wake:peek() + 1)
						end
					end
				end)
				starting = false
				if retired and not record.finished then
					retiring[key] = record
					entry.mounted.retiring = true
					touched = true
				end
			end
		end
		if touched then
			transitions.markStructure(node)
		end
		local held = {}
		for _, record in retiring do
			if not record.finished then
				table.insert(held, record)
			end
		end
		table.sort(held, function(a, b)
			return a.index < b.index
		end)
		for _, record in held do
			table.insert(result, math.min(record.index, #result + 1), record.entry.value:peek())
		end
		return result
	end

	node = named(region, spec.id)({
		Compose.keyed({
			from = retained,
			key = spec.key,
			render = function(item, _, key)
				local mounted = spec.row(item:peek(), nil, item)
				mounted.collectionKey = `[{key}]`
				mounted.transition = declared
				local entry = { mounted = mounted, value = item }
				entries[key] = entry
				Compose.cleanup(function()
					local held = retiring[key]
					if held then
						held.finished = true
					end
					if entries[key] == entry then
						entries[key] = nil
					end
					retiring[key] = nil
					motion.release(mounted)
				end)
				motion.enter(mounted)
				return mounted
			end,
		}),
	})
	node.drainTransitions = motion.drain
	return node
end

return regions
