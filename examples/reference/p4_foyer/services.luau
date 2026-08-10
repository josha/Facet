--!strict
-- Foyer proof fake services (RA-P4, responsibility ledger): FeedService,
-- FriendsService, SearchService. Pure and deterministic — injectable clock and
-- seed page, commands run idle → pending → confirmed | rejected with scripted
-- rejection fixtures, no wall clock, no math.random, no network. The command
-- pending window resolves on an explicit `settle()` tick (the scenario/step
-- layer owns time), so a headless test can observe the pending face.

local seed = require("./content/seed")

export type CommandStatus = "idle" | "pending" | "confirmed" | "rejected"

local services = {}

function services.new(deps: { core: any })
	local core = deps.core

	local self = {} :: any

	-- ── FeedService ────────────────────────────────────────────────────────
	local page = 0
	self.sections = core:signal(seed.sections(page))
	self.charted = seed.charted()
	self.continueIds = core:signal({} :: { [string]: boolean })
	self.noticeCount = core:signal(#seed.notices)
	self.notices = seed.notices

	self.refreshStatus = core:signal("idle" :: CommandStatus)
	self.refreshReason = core:signal(nil :: string?)
	self.visitStatus = core:signal("idle" :: CommandStatus)
	self.visitPendingId = core:signal(nil :: string?)

	-- scripted rejection fixtures: the NEXT command of that name rejects once
	local rejectNext: { [string]: string? } = {}
	function self.scriptRejection(command: string, reason: string?)
		rejectNext[command] = reason or "err.generic"
	end

	-- pending commands resolve on settle(), never inline — pending must be an
	-- observable state on every input class
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
		if self.refreshStatus:get() == "pending" then
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
		if self.visitStatus:get() == "pending" then
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
			local ids = table.clone(self.continueIds:get())
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

	-- ── FriendsService ─────────────────────────────────────────────────────
	self.friends = seed.friends
	self.inviteCount = core:signal(seed.inviteCount)

	-- ── SearchService ──────────────────────────────────────────────────────
	-- filter(queryReadable) -> memo of matching tiles (title OR creator,
	-- case-folded substring), deterministic order = seed order
	function self.filterMemo(query: any)
		return core:memo(function(use)
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

	-- lookup for the detail surface
	function self.tileById(id: string): seed.Tile?
		for _, section in self.sections:get() :: { any } do
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
