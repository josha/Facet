--!strict

local Nodes = require "./nodes"

export type Options = {
	maxOwners: number?,
	maxNodes: number?,
}

export type OwnerReport = {
	id: number,
	label: string?,
	holding: number,
	disposed: boolean,
	owned: number,
	adopted: number,
	borrowed: number,
	watches: number,
	cleanups: number,
	children: { OwnerReport },
	totalHolding: number,
	totalOwned: number,
	totalAdopted: number,
	totalBorrowed: number,
	totalWatches: number,
	totalCleanups: number,
	descendants: number,
	unclassified: number,
}

export type NodeReport = {
	custody: string,
	label: string?,
	ownerId: number?,
	ownerLabel: string?,
	because: string,
}

export type Report = {
	active: boolean,
	mounts: { OwnerReport },
	detached: { OwnerReport },
	outstandingMounts: number,

	trackedNodes: number,
	pending: number,
	droppedOwners: number,
	droppedNodes: number,
}

local DEFAULT_MAX_OWNERS = 4096
local DEFAULT_MAX_NODES = 16384

local WEAK_KEYS = table.freeze { __mode = "k" }

export type Record = {
	id: number,
	label: string?,
	owned: number,
	adopted: number,
	borrowed: number,
	watches: number,
	cleanups: number,

	children: { [any]: true },
	childCount: number,
	isChild: boolean,
	isMount: boolean,
}

export type State = {
	records: { [any]: Record },

	ordered: { [number]: any },
	orderedCount: number,
	nextId: number,
	maxOwners: number,
	maxNodes: number,
	droppedOwners: number,
	droppedNodes: number,
	nodes: number,
	nodeOwner: { [any]: Record },
	broken: boolean,
}

local state: State? = nil

local function isActive(): boolean
	return state ~= nil
end

local function guarded(body: () -> ())
	local held = state
	if held == nil or held.broken then
		return
	end
	local ok = pcall(body)
	if not ok then
		held.broken = true
	end
end

local function recordFor(owner: any): Record?
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
	local record: Record = {
		id = held.nextId,
		label = nil,
		owned = 0,
		adopted = 0,
		borrowed = 0,
		watches = 0,
		cleanups = 0,
		children = (setmetatable({}, WEAK_KEYS) :: any) :: { [any]: true },
		childCount = 0,
		isChild = false,
		isMount = false,
	}
	held.records[owner] = record
	held.orderedCount += 1
	held.ordered[held.orderedCount] = owner
	return record
end

local function node(owner: any, subject: any, custody: string)
	guarded(function()
		local held = state :: State
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

local function mount(owner: any)
	guarded(function()
		local record = recordFor(owner)
		if record ~= nil then
			record.isMount = true
		end
	end)
end

local function watch(owner: any)
	guarded(function()
		local record = recordFor(owner)
		if record ~= nil then
			record.watches += 1
		end
	end)
end

local function cleanup(owner: any)
	guarded(function()
		local record = recordFor(owner)
		if record ~= nil then
			record.cleanups += 1
		end
	end)
end

local function child(parent: any, subject: any)
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

local function label(owner: any, name: string)
	guarded(function()
		local record = recordFor(owner)
		if record ~= nil then
			record.label = name
		end
	end)
end

local function start(options: Options?)
	local settings: Options = options or ({} :: Options)
	state = {
		records = (setmetatable({}, WEAK_KEYS) :: any) :: { [any]: Record },
		ordered = (setmetatable({}, table.freeze { __mode = "v" }) :: any) :: { [number]: any },
		orderedCount = 0,
		nextId = 0,
		maxOwners = settings.maxOwners or DEFAULT_MAX_OWNERS,
		maxNodes = settings.maxNodes or DEFAULT_MAX_NODES,
		droppedOwners = 0,
		droppedNodes = 0,
		nodes = 0,
		nodeOwner = (setmetatable({}, WEAK_KEYS) :: any) :: { [any]: Record },
		broken = false,
	}
end

local function stop()
	state = nil
	Nodes.resetCharges()
end

return {
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
