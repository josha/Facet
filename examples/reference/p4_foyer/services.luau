--!strict

local seed = require("./content/seed")

export type CommandStatus = "idle" | "pending" | "confirmed" | "rejected"

local services = {}

function services.new(deps: { Compose: any })
	local Compose = deps.Compose

	local self = {} :: any

	local page = 0
	self.sections = Compose.cell(seed.sections(page))
	self.charted = seed.charted()
	self.continueIds = Compose.cell({} :: { [string]: boolean })
	self.noticeCount = Compose.cell(#seed.notices)
	self.notices = seed.notices

	self.refreshStatus = Compose.cell("idle" :: CommandStatus)
	self.refreshReason = Compose.cell(nil :: string?)
	self.visitStatus = Compose.cell("idle" :: CommandStatus)
	self.visitPendingId = Compose.cell(nil :: string?)

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

	self.friends = seed.friends
	self.inviteCount = Compose.cell(seed.inviteCount)

	function self.filterMemo(query: any)
		return Compose.formula(function(use)
			local q = string.lower(use(query))
			if q == "" then
				return {}
			end
			local out: { seed.Tile } = {}
			local sects = use(self.sections)
			local seen: { [string]: boolean } = {}
			for _, section in sects :: { any } do
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
		for _, section in self.sections:peek() :: { any } do
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
