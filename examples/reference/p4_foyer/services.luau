--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Readable<T> = { peek: (Readable<T>) -> T }
type Cell<T> = Readable<T> & { set: (Cell<T>, T) -> (), update: (Cell<T>, (T) -> T) -> () }
type Use = <T>(Readable<T>) -> T

local seed = require("./content/seed")

export type CommandStatus = "idle" | "pending" | "confirmed" | "rejected"
export type Section = { id: string, titleKey: string, layout: string, tiles: { seed.Tile } }

local services = {}

function services.new(deps: { Compose: ComposeModule })
	local Compose = deps.Compose

	local page = 0
	local idle: CommandStatus = "idle"
	local nothing: string? = nil
	local noIds: { [string]: boolean } = {}
	local sections: Cell<{ Section }> = Compose.cell(seed.sections(page))
	local refreshStatus: Cell<CommandStatus> = Compose.cell(idle)
	local refreshReason: Cell<string?> = Compose.cell(nothing)
	local visitStatus: Cell<CommandStatus> = Compose.cell(idle)
	local visitPendingId: Cell<string?> = Compose.cell(nothing)
	local continueIds: Cell<{ [string]: boolean }> = Compose.cell(noIds)
	local self = {
		sections = sections,
		charted = seed.charted(),
		continueIds = continueIds,
		noticeCount = Compose.cell(#seed.notices),
		notices = seed.notices,
		refreshStatus = refreshStatus,
		refreshReason = refreshReason,
		visitStatus = visitStatus,
		visitPendingId = visitPendingId,
		friends = seed.friends,
		inviteCount = Compose.cell(seed.inviteCount),
	}

	local rejectNext: { [string]: string? } = {}
	function self.scriptRejection(command: string, reason: string?)
		rejectNext[command] = reason or "err.generic"
	end

	local settleQueue: { () -> () } = {}
	function self.settle()
		local q = settleQueue
		settleQueue = {}
		for _, fn in q do
			fn()
		end
	end
	function self.pendingSettles(): number
		return #settleQueue
	end

	function self.refresh()
		if self.refreshStatus:peek() == "pending" then
			return
		end
		self.refreshReason:set(nil)
		self.refreshStatus:set("pending")
		table.insert(settleQueue, function()
			local reason = rejectNext.refresh
			if reason ~= nil then
				rejectNext.refresh = nil
				self.refreshReason:set(reason)
				self.refreshStatus:set("rejected")
				return
			end
			page += 1
			self.sections:set(seed.sections(page))
			self.refreshStatus:set("confirmed")
		end)
	end

	function self.visit(tileId: string)
		if self.visitStatus:peek() == "pending" then
			return
		end
		self.visitPendingId:set(tileId)
		self.visitStatus:set("pending")
		table.insert(settleQueue, function()
			local reason = rejectNext.visit
			if reason ~= nil then
				rejectNext.visit = nil
				self.visitStatus:set("rejected")
				self.visitPendingId:set(nil)
				return
			end
			local ids = table.clone(self.continueIds:peek())
			ids[tileId] = true
			self.continueIds:set(ids)
			self.visitStatus:set("confirmed")
			self.visitPendingId:set(nil)
		end)
	end

	function self.clearNotices()
		self.noticeCount:set(0)
	end

	function self.currentPage(): number
		return page
	end

	function self.filterMemo(query: Readable<string>)
		return Compose.formula(function(use: Use): { seed.Tile }
			local q = string.lower(use(query))
			if q == "" then
				return {}
			end
			local out: { seed.Tile } = {}
			local sects = use(self.sections)
			local seen: { [string]: boolean } = {}
			for _, section in sects do
				for _, tile in section.tiles do
					if not seen[tile.id] then
						seen[tile.id] = true
						if
							string.find(string.lower(tile.title), q, 1, true) ~= nil
							or string.find(string.lower(tile.creator), q, 1, true) ~= nil
						then
							out[#out + 1] = tile
						end
					end
				end
			end
			return out
		end)
	end

	function self.tileById(id: string): seed.Tile?
		for _, section in self.sections:peek() do
			for _, tile in section.tiles do
				if tile.id == id then
					return tile
				end
			end
		end
		for _, section in self.charted do
			for _, tile in section.tiles do
				if tile.id == id then
					return tile
				end
			end
		end
		return nil
	end

	return self
end

return services
