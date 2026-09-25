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
		launch = Compose.cell(nil),
		avatarPath = Compose.cell({}),
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
		hatTint = Compose.cell({ 218, 195, 145 }),
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
		hidden = Compose.cell({}),
		sessions = Compose.cell({}),
		similarPage = Compose.cell(1),
		presence = Compose.cell("online"),
		chatUnread = Compose.cell(0),
		toasts = { Discover = Compose.cell(nil), Chat = Compose.cell(nil) },
		presentations = {},
		modeChosen = false,
	}
	local serial = 0
	self.notify = function(app, message, undo)
		serial += 1
		self.toasts[app]:set({ serial = serial, message = message, undo = undo })
	end
	self.dismissToast = function(app, id)
		local current = self.toasts[app]:peek()
		if current and current.serial == id then
			self.toasts[app]:set(nil)
		end
	end
	Compose.watch(function(use)
		use(self.query)
		use(self.genre)
		use(self.sort)
		self.discoveryScroll:set(0)
	end)
	self.visibleGames = Compose.formula(function(use)
		local query, genre, order = use(self.query):lower(), use(self.genre), use(self.sort)
		local hidden, result = use(self.hidden), {}
		for _, item in use(self.catalog.items) do
			if
				not hidden[item.id]
				and (genre == "all" or item.genre == genre)
				and (query == "" or item.title:lower():find(query, 1, true))
			then
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
	self.save = function(item)
		local wasSaved = self.saved:peek()[item.id] == true
		self.toggleSaved(item.id)
		if not wasSaved then
			self.notify("Discover", `Saved {item.title}`, function()
				if self.saved:peek()[item.id] then
					self.toggleSaved(item.id)
				end
			end)
		end
	end
	self.hide = function(item)
		self.hidden:update(function(current)
			local nextHidden = table.clone(current)
			nextHidden[item.id] = true
			return nextHidden
		end)
		self.notify("Discover", `{item.title} is hidden`, function()
			self.hidden:update(function(current)
				local nextHidden = table.clone(current)
				nextHidden[item.id] = nil
				return nextHidden
			end)
		end)
	end
	self.schedule = function(id, date)
		self.sessions:update(function(current)
			local nextSessions = table.clone(current)
			nextSessions[id] = date
			return nextSessions
		end)
	end
	self.launchGame = function(id, mode)
		self.launch:set({ id = id, mode = mode, stage = 1, elapsed = 0 })
	end
	self.deleteMessage = function(id)
		local removed, index = self.chat.remove(id)
		if removed then
			self.notify("Chat", "Message deleted", function()
				self.chat.restore(removed, index)
			end)
		end
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
		self.similarPage:set(1)
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
		self.hatTint:set({ 218, 195, 145 })
		self.angle:set(-15)
	end
	self.prompt = function(value)
		self.chatPromptUsed:set(true)
		self.chat.draft:set(value)
	end
	local function chatVisible()
		local mode, focused = self.mode:peek(), self.focused:peek()
		return if mode == "Screen"
			then self.selectedTab:peek() == "Chat"
			else focused == "Chat" or focused == "Overview"
	end
	Compose.watch(function(use)
		use(self.mode)
		use(self.focused)
		use(self.selectedTab)
		if chatVisible() and self.chatUnread:peek() > 0 then
			self.chatUnread:set(0)
		end
	end)
	local answered = self.chat.completed:peek()
	Compose.watch(function(use)
		local completed = use(self.chat.completed)
		if completed > answered and not chatVisible() then
			self.chatUnread:set(self.chatUnread:peek() + completed - answered)
		end
		answered = completed
	end)
	self.step = function(dt, reducedMotion)
		self.catalog.step()
		self.chat.step(dt)
		local launch = self.launch:peek()
		if launch and launch.stage <= 3 then
			local elapsed = launch.elapsed + math.min(dt, 0.1)
			local stage = launch.stage
			if elapsed >= 0.9 then
				elapsed, stage = 0, stage + 1
			end
			self.launch:set({ id = launch.id, mode = launch.mode, stage = stage, elapsed = elapsed })
		end
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
