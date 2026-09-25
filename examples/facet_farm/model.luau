--!strict
local model = {}

export type CropId = "wheat" | "carrot" | "strawberry" | "pumpkin"
export type Crop = {
	id: CropId,
	label: string,
	cost: number,
	grow: number,
	sell: number,
	xp: number,
	unlock: number,
}
export type PlotState = "grass" | "plowed" | "growing" | "ready" | "withered"
export type Plot = { id: string, index: number, state: PlotState, crop: CropId?, planted: number? }
export type Tool = "plow" | "plant" | "harvest"

model.CROPS = {
	{ id = "wheat", label = "Wheat", cost = 5, grow = 20, sell = 14, xp = 1, unlock = 1 },
	{ id = "carrot", label = "Carrot", cost = 15, grow = 40, sell = 38, xp = 2, unlock = 2 },
	{ id = "strawberry", label = "Strawberry", cost = 25, grow = 60, sell = 70, xp = 3, unlock = 3 },
	{ id = "pumpkin", label = "Pumpkin", cost = 40, grow = 90, sell = 115, xp = 5, unlock = 4 },
} :: { Crop }
model.COLUMNS, model.ROWS = 6, 4
model.PLOW_COST = 2
model.WITHER_AFTER = 3

local byId: { [string]: Crop } = {}
for _, crop in model.CROPS do
	byId[crop.id] = crop
end

function model.crop(id: string): Crop
	return assert(byId[id], "unknown crop " .. id)
end

function model.xpFor(level: number): number
	return math.floor(10 * (level - 1) ^ 1.6)
end

function model.levelOf(xp: number): number
	local level = 1
	while xp >= model.xpFor(level + 1) do
		level += 1
	end
	return level
end

function model.progress(plot: Plot, now: number): number
	if plot.state ~= "growing" and plot.state ~= "ready" then
		return 0
	end
	local crop = model.crop(plot.crop :: string)
	return math.clamp((now - (plot.planted :: number)) / crop.grow, 0, 1)
end

function model.stateAt(plot: Plot, now: number): PlotState
	if plot.state ~= "growing" and plot.state ~= "ready" then
		return plot.state
	end
	local crop = model.crop(plot.crop :: string)
	local age = now - (plot.planted :: number)
	if age >= crop.grow * model.WITHER_AFTER then
		return "withered"
	elseif age >= crop.grow then
		return "ready"
	end
	return "growing"
end

function model.new(Compose: any, clock: (() -> number)?)
	local time = clock or os.clock
	local plots: { Plot } = {}
	for index = 1, model.COLUMNS * model.ROWS do
		table.insert(plots, { id = "Plot" .. index, index = index, state = "grass" })
	end
	local self = {
		coins = Compose.cell(120),
		xp = Compose.cell(0),
		plots = Compose.cell(plots),
		now = Compose.cell(time()),
		tool = Compose.cell("plow" :: Tool),
		seed = Compose.cell("wheat" :: CropId),
		marketOpen = Compose.cell(false),
		view = Compose.cell("2d" :: "2d" | "3d"),
		music = Compose.cell(true),
		levelUp = Compose.cell(false),
		toast = Compose.cell(nil :: { serial: number, message: string }?),
		harvested = Compose.cell(0),

		cue = Compose.cell(nil :: { serial: number, name: string }?),
	}
	local serial = 0
	local function cue(name: string)
		serial += 1
		self.cue:set({ serial = serial, name = name })
	end
	local function say(message: string)
		serial += 1
		self.toast:set({ serial = serial, message = message })
	end
	self.level = Compose.formula(function(use): number
		return model.levelOf(use(self.xp))
	end)
	function self.tick()
		self.now:set(time())
	end
	local function update(index: number, change: (Plot) -> Plot)
		self.plots:update(function(current: { Plot }): { Plot }
			local copy = table.clone(current)
			copy[index] = change(table.clone(current[index]))
			return copy
		end)
	end
	function self.unlocked(crop: Crop): boolean
		return self.level:peek() >= crop.unlock
	end
	function self.act(index: number): boolean
		local plot = self.plots:peek()[index]
		local now = time()
		self.now:set(now)
		local state = model.stateAt(plot, now)
		local tool = self.tool:peek()
		if state == "ready" or (tool == "harvest" and state == "ready") then
			local crop = model.crop(plot.crop :: string)
			local before = self.level:peek()
			self.coins:update(function(value: number): number
				return value + crop.sell
			end)
			self.xp:update(function(value: number): number
				return value + crop.xp
			end)
			self.harvested:update(function(value: number): number
				return value + 1
			end)
			update(index, function(next: Plot): Plot
				next.state, next.crop, next.planted = "plowed", nil, nil
				return next
			end)
			cue("harvest")
			say(`+{crop.sell} coins from {crop.label}`)
			if self.level:peek() > before then
				self.levelUp:set(true)
			end
			return true
		elseif state == "withered" then
			update(index, function(next: Plot): Plot
				next.state, next.crop, next.planted = "grass", nil, nil
				return next
			end)
			cue("plow")
			say("Cleared a withered crop")
			return true
		elseif state == "grass" and (tool == "plow" or tool == "plant") then
			if self.coins:peek() < model.PLOW_COST then
				say("Not enough coins to plow")
				return false
			end
			self.coins:update(function(value: number): number
				return value - model.PLOW_COST
			end)
			update(index, function(next: Plot): Plot
				next.state = "plowed"
				return next
			end)
			cue("plow")
			return true
		elseif state == "plowed" and tool ~= "harvest" then
			local crop = model.crop(self.seed:peek())
			if not self.unlocked(crop) then
				say(`{crop.label} unlocks at level {crop.unlock}`)
				return false
			end
			if self.coins:peek() < crop.cost then
				say(`{crop.label} seeds cost {crop.cost} coins`)
				return false
			end
			self.coins:update(function(value: number): number
				return value - crop.cost
			end)
			update(index, function(next: Plot): Plot
				next.state, next.crop, next.planted = "growing", crop.id, now
				return next
			end)
			cue("plant")
			return true
		end
		return false
	end
	function self.harvestAll(): number
		local count = 0
		for index, plot in self.plots:peek() do
			if model.stateAt(plot, time()) == "ready" and self.act(index) then
				count += 1
			end
		end
		return count
	end
	return self
end

return model
