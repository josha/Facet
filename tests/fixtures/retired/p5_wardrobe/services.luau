--!strict
-- Wardrobe proof fake services (RA-P5): InventoryService (owned set),
-- EquipService (worn set + undo/redo history), WalletService (balance +
-- purchase command with scripted fixtures). Deterministic, injectable, no wall
-- clock / RNG / network. Purchases resolve on an explicit settle() tick so the
-- pending face is observable on every input class.

local seed = require("./content/seed")

local services = {}

function services.new(deps: { core: any })
	local core = deps.core
	local self = {} :: any

	-- ── InventoryService ───────────────────────────────────────────────────
	local ownedSet: { [string]: boolean } = {}
	for _, id in seed.owned do
		ownedSet[id] = true
	end
	self.owned = core:signal(ownedSet)
	function self.owns(id: string): boolean
		return self.owned:get()[id] == true
	end

	-- ── EquipService ───────────────────────────────────────────────────────
	-- worn = { [category] = itemId }; history = undo/redo stack of worn states
	self.worn = core:signal({} :: { [string]: string })
	local past: { { [string]: string } } = {}
	local future: { { [string]: string } } = {}
	self.canUndo = core:signal(false)
	self.canRedo = core:signal(false)

	local function publishHistoryFacts()
		self.canUndo:set(#past > 0)
		self.canRedo:set(#future > 0)
	end

	local function commitWorn(next: { [string]: string })
		table.insert(past, self.worn:get())
		table.clear(future)
		self.worn:set(next)
		publishHistoryFacts()
	end

	function self.equip(id: string)
		local item = seed.itemById(id)
		if item == nil then
			return
		end
		local now = self.worn:get()
		local next = table.clone(now)
		if now[item.category] == id then
			next[item.category] = nil -- toggle off
		else
			next[item.category] = id
		end
		commitWorn(next)
	end

	function self.undo()
		local prev = table.remove(past)
		if prev == nil then
			return
		end
		table.insert(future, self.worn:get())
		self.worn:set(prev)
		publishHistoryFacts()
	end

	function self.redo()
		local next = table.remove(future)
		if next == nil then
			return
		end
		table.insert(past, self.worn:get())
		self.worn:set(next)
		publishHistoryFacts()
	end

	function self.historyDepths(): (number, number)
		return #past, #future
	end

	-- ── WalletService ──────────────────────────────────────────────────────
	self.balance = core:signal(seed.balance)
	self.purchaseStatus = core:signal("idle")
	self.purchaseReason = core:signal(nil :: string?)
	self.purchasePendingId = core:signal(nil :: string?)

	local soldOutSpent: { [string]: boolean } = {}
	local settleQueue: { () -> () } = {}
	function self.settle()
		local q = settleQueue
		settleQueue = {}
		for _, fn in q do
			fn()
		end
	end

	function self.purchase(id: string)
		if self.purchaseStatus:get() == "pending" then
			return
		end
		local item = seed.itemById(id)
		if item == nil or item.price == nil then
			return
		end
		self.purchaseReason:set(nil)
		self.purchasePendingId:set(id)
		self.purchaseStatus:set("pending")
		table.insert(settleQueue, function()
			local fixture = seed.fixtures[id]
			if fixture == "insufficient" or (item.price :: number) > self.balance:get() then
				self.purchaseReason:set("err.buy.insufficient")
				self.purchaseStatus:set("rejected")
				self.purchasePendingId:set(nil)
				return
			end
			if fixture == "soldout-once" and not soldOutSpent[id] then
				soldOutSpent[id] = true
				self.purchaseReason:set("err.buy.soldout")
				self.purchaseStatus:set("rejected")
				self.purchasePendingId:set(nil)
				return
			end
			self.balance:set(self.balance:get() - (item.price :: number))
			local owned = table.clone(self.owned:get())
			owned[id] = true
			self.owned:set(owned)
			self.purchaseStatus:set("confirmed")
			self.purchasePendingId:set(nil)
		end)
	end

	-- ── filters ────────────────────────────────────────────────────────────
	self.ownedOnly = core:signal(false)
	self.sort = core:signal("featured")

	function self.visibleItems(category: any)
		return core:memo(function(use)
			local cat = use(category)
			local ownedOnly = use(self.ownedOnly)
			local sortId = use(self.sort)
			local owned = use(self.owned)
			local out: { seed.Item } = {}
			for _, item in seed.items do
				if (cat == "all" or item.category == cat) and (not ownedOnly or owned[item.id] == true) then
					out[#out + 1] = item
				end
			end
			if sortId == "price" then
				table.sort(out, function(a, b)
					local pa, pb = a.price or 0, b.price or 0
					if pa ~= pb then
						return pa < pb
					end
					return a.id < b.id
				end)
			elseif sortId == "newest" then
				-- deterministic "newest" = reverse seed order
				local rev: { seed.Item } = {}
				for i = #out, 1, -1 do
					rev[#rev + 1] = out[i]
				end
				out = rev
			end
			return out
		end)
	end

	-- the worn set as rig content (pure): mannequin + every worn piece
	function self.rigContent(): { seed.PartSpec }
		local parts: { seed.PartSpec } = {}
		for _, p in seed.mannequin do
			parts[#parts + 1] = p
		end
		for _, id in self.worn:get() :: { [string]: string } do
			local item = seed.itemById(id)
			if item ~= nil and item.rig ~= nil then
				for _, p in item.rig do
					parts[#parts + 1] = p
				end
			end
		end
		return parts
	end

	return self
end

return services
