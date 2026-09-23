--!strict
local catalogModule = require("./catalog")
local chatModule = require("./chat_model")
local model = {}

function model.new(Compose: any)
	local self: any = {
		catalog = catalogModule.new(Compose),
		chat = chatModule.new(Compose),
		mode = Compose.cell("Spatial"),
		selectedTab = Compose.cell("Discover"),
		focused = Compose.cell("Overview"),
		dark = Compose.cell(true),
		query = Compose.cell(""),
		searchSelection = Compose.cell(""),
		featuredIndex = Compose.cell(1),
		discoveryScroll = Compose.cell(0),
		savedScroll = Compose.cell(0),
		chatScroll = Compose.cell(nil),
		genre = Compose.cell("all"),
		sort = Compose.cell("recommended"),
		shelf = Compose.cell("browse"),
		selectedGame = Compose.cell(nil),
		detailTab = Compose.cell("about"),
		saved = Compose.cell({}),
		savedOrder = Compose.cell({}),
		savedSelection = Compose.cell({}),
		savedSort = Compose.cell(nil),
		savedWidths = Compose.cell({}),
		notes = Compose.cell({}),
		ratings = Compose.cell({}),
		palette = Compose.cell("sage"),
		hat = Compose.cell(true),
		angle = Compose.cell(-15),
		turnStep = Compose.cell(30),
		autoSpin = Compose.cell(0),
		followChat = Compose.cell(true),
		avatarSummary = Compose.cell(false),
		avatarSummaryDetent = Compose.cell("medium"),
		avatarSettingsExpanded = Compose.cell(true),
		avatarTipsExpanded = Compose.cell(false),
		chatPromptUsed = Compose.cell(false),
		detailPath = Compose.cell({}),
		featuredSelection = Compose.cell("1"),
		resetAvatarPresented = Compose.cell(false),
		modeChosen = false,
	}
	Compose.watch(function(use)
		use(self.query)
		use(self.genre)
		use(self.sort)
		self.discoveryScroll:set(0)
	end)
	self.visibleGames = Compose.formula(function(use)
		local query, genre, order = use(self.query):lower(), use(self.genre), use(self.sort)
		local result = {}
		for _, item in use(self.catalog.items) do
			if (genre == "all" or item.genre == genre) and (query == "" or item.title:lower():find(query, 1, true)) then
				table.insert(result, item)
			end
		end
		if order ~= "recommended" then
			local field = if order == "rating" then "percent" else "playing"
			table.sort(result, function(a, b)
				return if a[field] == b[field] then a.index < b.index else a[field] > b[field]
			end)
		end
		return result
	end)
	self.savedGames = Compose.formula(function(use)
		local saved, byId, result = use(self.saved), {}, {}
		for _, item in use(self.catalog.items) do
			byId[item.id] = item
		end
		for _, id in use(self.savedOrder) do
			if saved[id] and byId[id] then
				table.insert(result, byId[id])
			end
		end
		return result
	end)
	self.toggleSaved = function(id)
		local saved = table.clone(self.saved:peek())
		saved[id] = if saved[id] then nil else true
		local order = table.clone(self.savedOrder:peek())
		local index = table.find(order, id)
		if saved[id] and not index then
			table.insert(order, id)
		elseif index then
			table.remove(order, index)
		end
		self.savedOrder:set(order)
		self.saved:set(saved)
	end
	self.reorderSaved = function(keys, slot)
		local moving, rest, ordered = {}, {}, {}
		for _, id in keys do
			moving[id] = true
		end
		for _, id in self.savedOrder:peek() do
			if moving[id] then
				table.insert(ordered, id)
			else
				table.insert(rest, id)
			end
		end
		local index = math.clamp(slot, 0, #rest)
		for offset, id in ordered do
			table.insert(rest, index + offset, id)
		end
		self.savedOrder:set(rest)
	end
	self.setNote = function(id, value)
		self.notes:update(function(current)
			local nextValue = table.clone(current)
			nextValue[id] = value
			return nextValue
		end)
	end
	self.rate = function(id, value)
		self.ratings:update(function(current)
			local nextValue = table.clone(current)
			nextValue[id] = math.clamp(value, 1, 5)
			return nextValue
		end)
	end
	self.selectGame = function(item)
		self.detailTab:set("about")
		self.detailPath:set({})
		self.selectedGame:set(item)
	end
	self.toggleMode = function()
		self.modeChosen = true
		local focused = self.focused:peek()
		if self.mode:peek() == "Spatial" and focused ~= "Overview" then
			self.selectedTab:set(focused)
		end
		self.focused:set(self.selectedTab:peek())
		self.mode:set(if self.mode:peek() == "Spatial" then "Screen" else "Spatial")
	end
	self.focus = function(name)
		self.focused:set(if self.focused:peek() == name then "Overview" else name)
	end
	self.turn = function(direction)
		self.angle:set((self.angle:peek() + direction * self.turnStep:peek() + 180) % 360 - 180)
	end
	self.resetAvatar = function()
		self.palette:set("sage")
		self.hat:set(true)
		self.angle:set(-15)
	end
	self.prompt = function(value)
		self.chatPromptUsed:set(true)
		self.chat.draft:set(value)
	end
	self.step = function(dt, reducedMotion)
		self.catalog.step()
		self.chat.step(dt)
		if not reducedMotion and self.autoSpin:peek() > 0 then
			local rate = ({ 0, 30, 75, 150 })[self.autoSpin:peek() + 1]
			self.angle:set((self.angle:peek() + rate * math.min(dt, 0.1) + 180) % 360 - 180)
		end
	end
	self.dispose = function()
		self.catalog.dispose()
		self.chat.dispose()
	end
	return self
end

return model
