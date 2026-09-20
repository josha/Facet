--!strict

local Inspect = require "./inspect"
local Nodes = require "./nodes"
local Root = require "./root"

export type OwnerReport = Inspect.OwnerReport
export type NodeReport = Inspect.NodeReport
export type Report = Inspect.Report
export type OwnedCounts = Nodes.OwnedCounts

local EMPTY: Report = {
	active = false,
	mounts = {},
	detached = {},
	outstandingMounts = 0,
	trackedNodes = 0,
	pending = 0,
	droppedOwners = 0,
	droppedNodes = 0,
}

local function describe(owner: any, record: Inspect.Record, seen: { [any]: true }): OwnerReport
	if seen[owner] then
		return {
			id = record.id,
			label = record.label,
			holding = 0,
			disposed = false,
			owned = 0,
			adopted = 0,
			borrowed = 0,
			watches = 0,
			cleanups = 0,
			children = {},
			totalHolding = 0,
			totalOwned = 0,
			totalAdopted = 0,
			totalBorrowed = 0,
			totalWatches = 0,
			totalCleanups = 0,
			descendants = 0,
			unclassified = 0,
		}
	end
	seen[owner] = true

	local held = Inspect.__state()
	local holding = 0
	local disposed = false
	local ok = pcall(function()
		holding = owner.size()
		disposed = owner.isDisposed()
	end)
	if not ok then
		holding = 0
	end

	local children: { OwnerReport } = {}
	if held ~= nil then
		local sorted: { any } = {}
		for candidate in record.children do
			table.insert(sorted, candidate)
		end
		table.sort(sorted, function(left: any, right: any): boolean
			local leftRecord, rightRecord = held.records[left], held.records[right]
			local leftId = if leftRecord ~= nil then leftRecord.id else 0
			local rightId = if rightRecord ~= nil then rightRecord.id else 0
			return leftId < rightId
		end)
		for _, candidate in sorted do
			local childRecord = held.records[candidate]
			if childRecord ~= nil then
				table.insert(children, describe(candidate, childRecord, seen))
			end
		end
	end

	local classified = record.owned
		+ record.adopted
		+ record.borrowed
		+ record.watches
		+ record.cleanups
		+ record.childCount

	local totalHolding = holding
	local totalOwned = record.owned
	local totalAdopted = record.adopted
	local totalBorrowed = record.borrowed
	local totalWatches = record.watches
	local totalCleanups = record.cleanups
	local descendants = #children
	for _, subject in children do
		totalHolding += subject.totalHolding
		totalOwned += subject.totalOwned
		totalAdopted += subject.totalAdopted
		totalBorrowed += subject.totalBorrowed
		totalWatches += subject.totalWatches
		totalCleanups += subject.totalCleanups
		descendants += subject.descendants
	end

	return {
		id = record.id,
		label = record.label,
		holding = holding,
		disposed = disposed,
		owned = record.owned,
		adopted = record.adopted,
		borrowed = record.borrowed,
		watches = record.watches,
		cleanups = record.cleanups,
		children = children,
		totalHolding = totalHolding,
		totalOwned = totalOwned,
		totalAdopted = totalAdopted,
		totalBorrowed = totalBorrowed,
		totalWatches = totalWatches,
		totalCleanups = totalCleanups,
		descendants = descendants,
		unclassified = math.max(0, holding - classified),
	}
end

local function snapshot(): Report
	local held = Inspect.__state()
	if held == nil then
		return EMPTY
	end

	local mounts: { OwnerReport } = {}
	local detached: { OwnerReport } = {}
	local seen: { [any]: true } = {}
	for index = 1, held.orderedCount do
		local owner = held.ordered[index]
		if owner == nil then
			continue
		end
		local record = held.records[owner]
		if record == nil or seen[owner] then
			continue
		end
		if record.isMount then
			table.insert(mounts, describe(owner, record, seen))
		elseif not record.isChild then
			table.insert(detached, describe(owner, record, seen))
		end
	end

	return {
		active = true,
		mounts = mounts,
		detached = detached,
		outstandingMounts = Root.size(),
		trackedNodes = Nodes.trackedCount(),
		pending = 0,
		droppedOwners = held.droppedOwners,
		droppedNodes = held.droppedNodes,
	}
end

local function node(subject: any): NodeReport
	local custody = Nodes.custodyOf(subject)
	local label = Nodes.labelOf(subject)
	local held = Inspect.__state()
	local record = if held ~= nil then held.nodeOwner[subject] else nil
	local subjectName = if label ~= nil then ("%q"):format(label) else "this node"

	if custody == "borrowed" then
		return {
			custody = custody,
			label = label,
			ownerId = if record ~= nil then record.id else nil,
			ownerLabel = if record ~= nil then record.label else nil,
			because = ("Compose will never destroy %s: it is borrowed. Whatever created it "):format(subjectName)
				.. "is what has to end it.",
		}
	end

	if record == nil then
		return {
			custody = custody,
			label = label,
			ownerId = nil,
			ownerLabel = nil,
			because = ("Compose will destroy this node when its owner is disposed (custody %q), but "):format(custody)
				.. "which owner holds it was not recorded -- the inspector was not running when it was taken on.",
		}
	end

	local name = record.label or ("owner#%d"):format(record.id)
	return {
		custody = custody,
		label = label,
		ownerId = record.id,
		ownerLabel = record.label,
		because = ("Compose will destroy this node when %s is disposed (custody %q). It is alive "):format(
			name,
			custody
		) .. "because that owner is.",
	}
end

local function owner(subject: any): OwnerReport?
	local held = Inspect.__state()
	if held == nil then
		return nil
	end
	local record = held.records[subject]
	if record == nil then
		return nil
	end
	return describe(subject, record, {})
end

local function owned(subject: any): OwnedCounts?
	if Inspect.__state() == nil then
		return nil
	end
	return Nodes.ownedCounts(subject)
end

local function indent(depth: number): string
	return string.rep("  ", depth)
end

local function line(out: { string }, text: string)
	table.insert(out, text)
end

local function renderOwner(out: { string }, entry: OwnerReport, depth: number)
	local name = entry.label or ("owner#%d"):format(entry.id)
	line(
		out,
		("%s%s  holding %d%s"):format(indent(depth), name, entry.holding, if entry.disposed then "  (disposed)" else "")
	)

	if depth == 1 and entry.descendants > 0 then
		line(
			out,
			("%s  tree: %d node%s owned, %d adopted, %d borrowed, %d watch%s, %d cleanup%s, %d owner%s"):format(
				indent(depth),
				entry.totalOwned,
				if entry.totalOwned == 1 then "" else "s",
				entry.totalAdopted,
				entry.totalBorrowed,
				entry.totalWatches,
				if entry.totalWatches == 1 then "" else "es",
				entry.totalCleanups,
				if entry.totalCleanups == 1 then "" else "s",
				entry.descendants,
				if entry.descendants == 1 then "" else "s"
			)
		)
	end

	local parts: { string } = {}
	if entry.owned > 0 then
		table.insert(parts, ("%d owned node%s"):format(entry.owned, if entry.owned == 1 then "" else "s"))
	end
	if entry.adopted > 0 then
		table.insert(parts, ("%d adopted"):format(entry.adopted))
	end
	if entry.borrowed > 0 then
		table.insert(parts, ("%d borrowed"):format(entry.borrowed))
	end
	if entry.watches > 0 then
		table.insert(parts, ("%d watch%s"):format(entry.watches, if entry.watches == 1 then "" else "es"))
	end
	if entry.cleanups > 0 then
		table.insert(parts, ("%d cleanup%s"):format(entry.cleanups, if entry.cleanups == 1 then "" else "s"))
	end
	if #entry.children > 0 then
		table.insert(parts, ("%d child owner%s"):format(#entry.children, if #entry.children == 1 then "" else "s"))
	end
	if #parts > 0 then
		line(out, ("%s  %s"):format(indent(depth), table.concat(parts, ", ")))
	end
	if entry.unclassified > 0 then
		line(
			out,
			("%s  %d unclassified -- registered before the inspector started, or a kind it does "):format(
				indent(depth),
				entry.unclassified
			) .. "not track"
		)
	end

	for _, subject in entry.children do
		renderOwner(out, subject, depth + 1)
	end
end

local function format(report: Report): string
	if not report.active then
		return "compose inspect: not running\n"
	end

	local out: { string } = {}
	line(
		out,
		("compose inspect: %d outstanding mount(s), %d node(s) with recorded custody, %d pending"):format(
			report.outstandingMounts,
			report.trackedNodes,
			report.pending
		)
	)
	if report.droppedOwners > 0 or report.droppedNodes > 0 then
		line(
			out,
			("  capture dropped at the cap: %d owner(s), %d node(s); counts below are incomplete"):format(
				report.droppedOwners,
				report.droppedNodes
			)
		)
	end
	line(out, "")

	if #report.mounts == 0 then
		line(out, "mounts: none")
	else
		line(out, "mounts:")
		for _, entry in report.mounts do
			renderOwner(out, entry, 1)
		end
	end

	if #report.detached > 0 then
		line(out, "")
		line(out, "owners held outside any mount:")
		for _, entry in report.detached do
			renderOwner(out, entry, 1)
		end
	end

	return table.concat(out, "\n") .. "\n"
end

local function data(report: Report): { [string]: any }
	local function shape(entry: OwnerReport): { [string]: any }
		local children: { any } = table.create(#entry.children)
		for index, subject in entry.children do
			children[index] = shape(subject)
		end
		return {
			id = entry.id,
			label = entry.label,
			holding = entry.holding,
			disposed = entry.disposed,
			owned = entry.owned,
			adopted = entry.adopted,
			borrowed = entry.borrowed,
			watches = entry.watches,
			cleanups = entry.cleanups,
			unclassified = entry.unclassified,
			totalHolding = entry.totalHolding,
			totalOwned = entry.totalOwned,
			totalAdopted = entry.totalAdopted,
			totalBorrowed = entry.totalBorrowed,
			totalWatches = entry.totalWatches,
			totalCleanups = entry.totalCleanups,
			descendants = entry.descendants,
			children = children,
		}
	end
	local mounts: { any } = table.create(#report.mounts)
	for index, entry in report.mounts do
		mounts[index] = shape(entry)
	end
	local detached: { any } = table.create(#report.detached)
	for index, entry in report.detached do
		detached[index] = shape(entry)
	end
	return {
		schemaVersion = 1,
		active = report.active,
		outstandingMounts = report.outstandingMounts,
		trackedNodes = report.trackedNodes,
		pending = report.pending,
		droppedOwners = report.droppedOwners,
		droppedNodes = report.droppedNodes,
		mounts = mounts,
		detached = detached,
	}
end

return {
	snapshot = snapshot,
	node = node,
	owner = owner,
	owned = owned,
	format = format,
	data = data,
}
