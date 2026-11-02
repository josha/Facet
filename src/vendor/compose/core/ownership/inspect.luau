--!strict
local Weak = require "../weak"

local Types = require "../reactive/types"
local Nodes = require "./nodes"

export type Options = Types.InspectOptions
export type OwnerReport = Types.InspectOwnerReport
export type NodeReport = Types.InspectNodeReport
export type Report = Types.InspectReport
export type Data = Types.InspectData

local DEFAULT_MAX_OWNERS = 4096
local DEFAULT_MAX_NODES = 16384

export type Record = {
	id: number,
	label: string?,
	owned: number,
	adopted: number,
	borrowed: number,
	watches: number,
	cleanups: number,

	children: { [Types.Owner]: true },
	childCount: number,
	isChild: boolean,
	isMount: boolean,
}

export type State = {
	records: { [Types.Owner]: Record },

	ordered: { [number]: Types.Owner },
	orderedCount: number,
	nextId: number,
	maxOwners: number,
	maxNodes: number,
	droppedOwners: number,
	droppedNodes: number,
	nodes: number,
	nodeOwner: { [unknown]: Record },
	broken: boolean,
}

local state: State? = nil
local flag = Nodes.inspecting

local function isActive(): boolean
	return state ~= nil
end

local function guarded(body: (State) -> ())
	local held = state
	if held == nil or held.broken then
		return
	end
	local ok = pcall(body, held)
	if not ok then
		held.broken = true
	end
end

local function recordFor(owner: Types.Owner): Record?
	local held = state
	if held == nil then
		return nil
	end
	local existing = held.records[owner]
	if existing ~= nil then
		return existing
	end
	if held.orderedCount >= held.maxOwners then
		held.droppedOwners += 1
		return nil
	end
	held.nextId += 1
	local children: { [Types.Owner]: true } = {}
	Weak.keys(children)
	local record: Record = {
		id = held.nextId,
		label = nil,
		owned = 0,
		adopted = 0,
		borrowed = 0,
		watches = 0,
		cleanups = 0,
		children = children,
		childCount = 0,
		isChild = false,
		isMount = false,
	}
	held.records[owner] = record
	held.orderedCount += 1
	held.ordered[held.orderedCount] = owner
	return record
end

local function node(owner: Types.Owner, subject: unknown, custody: string)
	guarded(function(held)
		local record = recordFor(owner)
		if record == nil then
			return
		end
		if custody == "owned" then
			record.owned += 1
		elseif custody == "adopted" then
			record.adopted += 1
		else
			record.borrowed += 1
		end
		if held.nodes >= held.maxNodes then
			held.droppedNodes += 1
			return
		end
		held.nodes += 1
		held.nodeOwner[subject] = record
	end)
end

local function mount(owner: Types.Owner)
	guarded(function()
		local record = recordFor(owner)
		if record ~= nil then
			record.isMount = true
		end
	end)
end

local function watch(owner: Types.Owner)
	guarded(function()
		local record = recordFor(owner)
		if record ~= nil then
			record.watches += 1
		end
	end)
end

local function cleanup(owner: Types.Owner)
	guarded(function()
		local record = recordFor(owner)
		if record ~= nil then
			record.cleanups += 1
		end
	end)
end

local function child(parent: Types.Owner, subject: Types.Owner)
	guarded(function()
		local parentRecord = recordFor(parent)
		local childRecord = recordFor(subject)
		if parentRecord == nil or childRecord == nil then
			return
		end
		if parentRecord.children[subject] == nil then
			parentRecord.children[subject] = true
			parentRecord.childCount += 1
		end
		childRecord.isChild = true
	end)
end

local function label(owner: Types.Owner, name: string)
	guarded(function()
		local record = recordFor(owner)
		if record ~= nil then
			record.label = name
		end
	end)
end

local function start(options: Options?)
	local settings: Options = options or {}
	local records: { [Types.Owner]: Record } = {}
	Weak.keys(records)
	local ordered: { [number]: Types.Owner } = {}
	Weak.values(ordered)
	local nodeOwner: { [unknown]: Record } = {}
	Weak.keys(nodeOwner)
	state = {
		records = records,
		ordered = ordered,
		orderedCount = 0,
		nextId = 0,
		maxOwners = settings.maxOwners or DEFAULT_MAX_OWNERS,
		maxNodes = settings.maxNodes or DEFAULT_MAX_NODES,
		droppedOwners = 0,
		droppedNodes = 0,
		nodes = 0,
		nodeOwner = nodeOwner,
		broken = false,
	}
	flag.active = true
end

local function stop()
	state = nil
	flag.active = false
	Nodes.resetCharges()
end

return {
	flag = flag,
	isActive = isActive,
	start = start,
	stop = stop,
	label = label,

	node = node,
	mount = mount,
	watch = watch,
	cleanup = cleanup,
	child = child,

	__state = function(): State?
		return state
	end,
}
