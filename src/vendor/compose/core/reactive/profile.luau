--!strict

local Weak = require "../weak"
local stats = require "./stats"

export type Options = {
	maxNodes: number?,
	maxDrains: number?,
}

export type NodeRow = {
	id: number,
	kind: string,
	label: string?,
	writes: number,
	writesSuppressed: number,
	recomputations: number,
	recomputationsSuppressed: number,
	runs: number,
	schedules: number,
	schedulesCoalesced: number,
	hostWrites: number,
	peakFanOut: number,

	wakes: { [number]: number },
}

export type DrainRow = {
	runs: number,
	seconds: number,
	cause: string?,
}

export type Report = {
	active: boolean,
	seconds: number,
	nodes: { NodeRow },
	drains: { DrainRow },

	droppedRecords: number,
	totals: { [string]: number },
}

export type WakeData = {
	to: number,
	count: number,
}

export type NodeData = {
	id: number,
	kind: string,
	label: string?,
	name: string,
	writes: number,
	writesSuppressed: number,
	recomputations: number,
	recomputationsPublished: number,
	runs: number,
	schedules: number,
	schedulesCoalesced: number,
	hostWrites: number,
	peakFanOut: number,
	wakes: { WakeData },
}

export type DrainData = {
	runs: number,
	seconds: number,
	cause: string?,
}

export type Data = {
	schemaVersion: number,
	active: boolean,
	seconds: number,
	droppedRecords: number,
	totals: { [string]: number },
	nodes: { NodeData },
	drains: { DrainData },
}

type Shape = {
	derived: boolean?,
	enqueue: unknown,
}

local DEFAULT_MAX_NODES = 4096
local DEFAULT_MAX_DRAINS = 256
local MAX_WAKE_TARGETS = 32

local UNKNOWN_KIND = "node"

local function kindOf(node: unknown): string
	local shape = node :: Shape
	local derived = shape.derived
	if derived == true then
		return "formula"
	elseif derived == false then
		return "cell"
	elseif shape.enqueue ~= nil then
		return "watch"
	end
	return UNKNOWN_KIND
end

type State = {
	rows: { [unknown]: NodeRow },
	ordered: { NodeRow },
	nextId: number,
	droppedRecords: number,
	maxNodes: number,
	maxDrains: number,
	drains: { DrainRow },
	drainCursor: number,
	startedAt: number,
	cause: string?,
	running: NodeRow?,
	pendingLabel: string?,

	broken: boolean,
}

local state: State? = nil

local restoreCounters = false
local clock: (() -> number)? = nil

local function rowFor(node: unknown, kind: string): NodeRow?
	local held = state
	if held == nil then
		return nil
	end
	local existing = held.rows[node]
	if existing ~= nil then
		if existing.kind == UNKNOWN_KIND and kind ~= UNKNOWN_KIND then
			existing.kind = kind
		end
		return existing
	end
	if #held.ordered >= held.maxNodes then
		held.droppedRecords += 1
		return nil
	end
	held.nextId += 1
	local row: NodeRow = {
		id = held.nextId,
		kind = kind,
		label = nil,
		writes = 0,
		writesSuppressed = 0,
		recomputations = 0,
		recomputationsSuppressed = 0,
		runs = 0,
		schedules = 0,
		schedulesCoalesced = 0,
		hostWrites = 0,
		peakFanOut = 0,
		wakes = {},
	}
	held.rows[node] = row
	table.insert(held.ordered, row)
	return row
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

local function write(cell: unknown, suppressed: boolean)
	guarded(function()
		local row = rowFor(cell, "cell")
		if row == nil then
			return
		end
		if suppressed then
			row.writesSuppressed += 1
		else
			row.writes += 1
			(state :: State).cause = row.label or ("cell#%d"):format(row.id)
		end
	end)
end

local function wake(producer: unknown, kind: string, count: number)
	guarded(function()
		local row = rowFor(producer, kind)
		if row == nil then
			return
		end
		if count > row.peakFanOut then
			row.peakFanOut = count
		end
	end)
end

local function edge(producer: unknown, producerKind: string, consumer: unknown)
	guarded(function()
		local from = rowFor(producer, producerKind)
		local to = rowFor(consumer, kindOf(consumer))
		if from == nil or to == nil then
			return
		end
		local seen = from.wakes[to.id]
		if seen == nil then
			local count = 0
			for _ in from.wakes do
				count += 1
			end
			if count >= MAX_WAKE_TARGETS then
				return
			end
		end
		from.wakes[to.id] = (seen or 0) + 1
	end)
end

local function recompute(formula: unknown)
	guarded(function()
		local row = rowFor(formula, "formula")
		if row ~= nil then
			row.recomputations += 1
		end
	end)
end

local function suppressedRecompute(formula: unknown)
	guarded(function()
		local row = rowFor(formula, "formula")
		if row ~= nil then
			row.recomputationsSuppressed += 1
		end
	end)
end

local function schedule(watch: unknown, coalesced: boolean)
	guarded(function()
		local row = rowFor(watch, "watch")
		if row == nil then
			return
		end
		if coalesced then
			row.schedulesCoalesced += 1
		else
			row.schedules += 1
		end
	end)
end

local function enterRun(watch: unknown)
	local held = state
	if held == nil or held.broken then
		return
	end
	guarded(function()
		local row = rowFor(watch, "watch")
		if row == nil then
			return
		end
		row.runs += 1
		held.running = row
	end)
end

local function hostWrite()
	local held = state
	if held == nil or held.broken then
		return
	end
	local row = held.running
	if row ~= nil then
		row.hostWrites += 1
	end
end

local function drain(runs: number, seconds: number)
	guarded(function()
		local held = state :: State
		local row: DrainRow = { runs = runs, seconds = seconds, cause = held.cause }
		held.cause = nil
		if #held.drains < held.maxDrains then
			table.insert(held.drains, row)
		else
			held.drainCursor = (held.drainCursor % held.maxDrains) + 1
			held.drains[held.drainCursor] = row
		end
	end)
end

local function label(node: unknown, name: string)
	guarded(function()
		local row = rowFor(node, kindOf(node))
		if row ~= nil then
			row.label = name
		end
	end)
end

local function naming(name: string?)
	local held = state
	if held ~= nil and not held.broken then
		held.pendingLabel = name
	end
end

local function born(node: unknown, name: string?)
	guarded(function()
		local held = state :: State
		local row = rowFor(node, "watch")
		if row ~= nil and row.label == nil then
			row.label = name or held.pendingLabel
		end
	end)
end

local function isActive(): boolean
	return state ~= nil
end

local function start(now: () -> number, options: Options?)
	local settings: Options = options or ({} :: Options)
	restoreCounters = stats.state.enabled
	stats.setEnabled(true)
	clock = now
	state = {
		rows = Weak.keys() :: { [unknown]: NodeRow },
		ordered = {},
		nextId = 0,
		droppedRecords = 0,
		maxNodes = settings.maxNodes or DEFAULT_MAX_NODES,
		maxDrains = settings.maxDrains or DEFAULT_MAX_DRAINS,
		drains = {},
		drainCursor = 0,
		startedAt = now(),
		cause = nil,
		running = nil,
		pendingLabel = nil,
		broken = false,
	}
end

local function nowOrNil(): number?
	local reading = clock
	if state == nil or reading == nil then
		return nil
	end
	return reading()
end

local function stop(): Report
	local held = state
	local reading = clock
	state = nil
	clock = nil
	stats.setEnabled(restoreCounters)
	if held == nil then
		return {
			active = false,
			seconds = 0,
			nodes = {},
			drains = {},
			droppedRecords = 0,
			totals = {},
		}
	end

	local totals: { [string]: number } = {
		writes = 0,
		writesSuppressed = 0,
		recomputations = 0,
		recomputationsSuppressed = 0,
		runs = 0,
		schedules = 0,
		schedulesCoalesced = 0,
		hostWrites = 0,
	}
	for _, row in held.ordered do
		totals.writes += row.writes
		totals.writesSuppressed += row.writesSuppressed
		totals.recomputations += row.recomputations
		totals.recomputationsSuppressed += row.recomputationsSuppressed
		totals.runs += row.runs
		totals.schedules += row.schedules
		totals.schedulesCoalesced += row.schedulesCoalesced
		totals.hostWrites += row.hostWrites
	end
	totals.broken = if held.broken then 1 else 0

	return {
		active = true,
		seconds = if reading ~= nil then reading() - held.startedAt else 0,
		nodes = held.ordered,
		drains = held.drains,
		droppedRecords = held.droppedRecords,
		totals = totals,
	}
end

local function nameOf(row: NodeRow): string
	return row.label or ("%s#%d"):format(row.kind, row.id)
end

local function weight(row: NodeRow): number
	return row.writes + row.recomputations + row.runs + row.hostWrites
end

local function format(report: Report, limit: number?): string
	local out: { string } = {}
	local function line(text: string)
		table.insert(out, text)
	end

	if not report.active then
		return "compose profile: not running\n"
	end

	line(("compose profile: %.3f s, %d node(s) tracked"):format(report.seconds, #report.nodes))
	if report.droppedRecords > 0 then
		line(("  capture dropped %d time(s) at the node cap; counts are incomplete"):format(report.droppedRecords))
	end
	if (report.totals.broken or 0) > 0 then
		line "  the recorder failed part-way and stopped; counts below are incomplete"
	end
	line ""
	line(
		("  writes %d (%d suppressed) | recomputations %d (%d published) | watch runs %d | host writes %d"):format(
			report.totals.writes,
			report.totals.writesSuppressed,
			report.totals.recomputations,
			report.totals.recomputations - report.totals.recomputationsSuppressed,
			report.totals.runs,
			report.totals.hostWrites
		)
	)
	line(("  schedules %d (%d coalesced)"):format(report.totals.schedules, report.totals.schedulesCoalesced))
	line ""

	local ranked = table.clone(report.nodes)
	table.sort(ranked, function(left: NodeRow, right: NodeRow): boolean
		local a, b = weight(left), weight(right)
		if a == b then
			return left.id < right.id
		end
		return a > b
	end)

	local byId: { [number]: NodeRow } = {}
	for _, row in report.nodes do
		byId[row.id] = row
	end

	line "hottest:"
	local shown = limit or 12
	for index = 1, math.min(shown, #ranked) do
		local row = ranked[index]
		local parts: { string } = {}
		if row.writes > 0 then
			table.insert(parts, ("%d write%s"):format(row.writes, if row.writes == 1 then "" else "s"))
		end
		if row.writesSuppressed > 0 then
			table.insert(parts, ("%d suppressed"):format(row.writesSuppressed))
		end
		if row.recomputations > 0 then
			table.insert(
				parts,
				("%d recompute%s (%d published)"):format(
					row.recomputations,
					if row.recomputations == 1 then "" else "s",
					row.recomputations - row.recomputationsSuppressed
				)
			)
		end
		if row.runs > 0 then
			table.insert(parts, ("%d run%s"):format(row.runs, if row.runs == 1 then "" else "s"))
		end
		if row.schedulesCoalesced > 0 then
			table.insert(parts, ("%d coalesced"):format(row.schedulesCoalesced))
		end
		if row.hostWrites > 0 then
			table.insert(parts, ("%d host write%s"):format(row.hostWrites, if row.hostWrites == 1 then "" else "s"))
		end
		if row.peakFanOut > 0 then
			table.insert(parts, ("fan-out %d"):format(row.peakFanOut))
		end
		if #parts == 0 then
			table.insert(parts, "no recorded work")
		end
		line(("  %-34s %s"):format(nameOf(row), table.concat(parts, ", ")))

		local targets: { number } = {}
		for id in row.wakes do
			table.insert(targets, id)
		end
		table.sort(targets)
		for _, id in targets do
			local target = byId[id]
			if target ~= nil then
				line(("      -> %-30s x%d"):format(nameOf(target), row.wakes[id]))
			end
		end
	end

	if #report.drains > 0 then
		local sorted = table.clone(report.drains)
		table.sort(sorted, function(left: DrainRow, right: DrainRow): boolean
			return left.seconds > right.seconds
		end)
		line ""
		line(("longest drains (of %d recorded):"):format(#report.drains))
		for index = 1, math.min(5, #sorted) do
			local row = sorted[index]
			line(
				("  %8.3f ms  %d run%s  %s"):format(
					row.seconds * 1000,
					row.runs,
					if row.runs == 1 then "" else "s",
					row.cause or "cause not recorded"
				)
			)
		end
	end

	return table.concat(out, "\n") .. "\n"
end

local function data(report: Report): Data
	local nodes = table.create(#report.nodes) :: { NodeData }
	for index, row in report.nodes do
		local wakes: { WakeData } = {}
		local targets: { number } = {}
		for id in row.wakes do
			table.insert(targets, id)
		end
		table.sort(targets)
		for _, id in targets do
			table.insert(wakes, { to = id, count = row.wakes[id] })
		end
		nodes[index] = {
			id = row.id,
			kind = row.kind,
			label = row.label,
			name = nameOf(row),
			writes = row.writes,
			writesSuppressed = row.writesSuppressed,
			recomputations = row.recomputations,
			recomputationsPublished = row.recomputations - row.recomputationsSuppressed,
			runs = row.runs,
			schedules = row.schedules,
			schedulesCoalesced = row.schedulesCoalesced,
			hostWrites = row.hostWrites,
			peakFanOut = row.peakFanOut,
			wakes = wakes,
		}
	end
	local drains = table.create(#report.drains) :: { DrainData }
	for index, row in report.drains do
		drains[index] = { runs = row.runs, seconds = row.seconds, cause = row.cause }
	end
	return {
		schemaVersion = 1,
		active = report.active,
		seconds = report.seconds,
		droppedRecords = report.droppedRecords,
		totals = report.totals,
		nodes = nodes,
		drains = drains,
	}
end

return {
	start = start,
	stop = stop,
	label = label,
	isActive = isActive,
	format = format,
	data = data,

	write = write,
	wake = wake,
	edge = edge,
	recompute = recompute,
	suppressedRecompute = suppressedRecompute,
	schedule = schedule,
	enterRun = enterRun,
	hostWrite = hostWrite,
	drain = drain,
	naming = naming,
	born = born,
	nowOrNil = nowOrNil,
}
