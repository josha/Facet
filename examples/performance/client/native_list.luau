--!strict
-- The MATCHED RAW-ROBLOX REFERENCE (roadmap Step 9, acceptance PL-5).
--
-- WHAT IT IS FOR. A Facet frame time on its own answers nothing: some of that
-- cost is Roblox drawing a scrolling list of composite rows, and that half would
-- be paid by any implementation. This is the same dataset, the same images, the
-- same row pitch, the same viewport and the same interactions, built with nothing
-- but Instances — so the difference between the two captures is the framework's
-- share and not a guess about it.
--
-- WHAT IT IS NOT. It is not a second UI framework and it is not expected to have
-- Facet's features: no focus graph, no theme authority, no async resource
-- lifecycle, no accessibility disclosure, no adaptive composition. Those absences
-- are the point — the reference is a FLOOR, and a comparison that reads it as
-- "Facet costs N times more than it should" without naming what the floor omits
-- is misreading it. Every omission is listed in `capabilities` below and travels
-- with the capture.
--
-- IT WINDOWS. A non-virtualized reference against a virtualized list would
-- compare two different algorithms and attribute the difference to the framework,
-- which is the single easiest way to produce a confident wrong answer here. So
-- this hand-rolls the same shape Facet's VirtualList uses: a full-extent canvas,
-- a recycled pool of row frames, and absolute offsets driven from CanvasPosition.
--
-- EXACTLY ONE IMPLEMENTATION MOUNTS AT A TIME; `perf_lab` enforces that, and this
-- module refuses a second mount of its own.

local Players = game:GetService("Players")

local native_list = {}

native_list.VERSION = "perf-native/1"

-- The honest capability ledger. Read into the capture so a reader always sees
-- what the floor does NOT do before comparing it to something that does.
native_list.CAPABILITIES = {
	has = { "scrolling", "clipping", "windowed row recycling", "images", "text", "buttons", "selection paint" },
	lacks = {
		"focus graph / keyboard traversal",
		"theme authority and style rules",
		"async resource lifecycle (images are set directly, with no provider, cache, retry or cancellation)",
		"preferred-text reflow and full-value disclosure",
		"adaptive composition and safe-area insets",
		"hit-target floor expansion",
	},
}

local active: any = nil

local function newRowFrame(parent: Instance, opts: any): any
	local row = Instance.new("Frame")
	row.Name = "NativeRow"
	row.BackgroundColor3 = Color3.fromRGB(38, 40, 44)
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, opts.rowHeight)
	row.Visible = false
	row.Parent = parent

	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.BackgroundTransparency = 1
	avatar.Size = UDim2.fromOffset(opts.imageSize, opts.imageSize)
	avatar.Position = UDim2.fromOffset(4, 4)
	avatar.Parent = row

	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextColor3 = Color3.fromRGB(235, 236, 240)
	name.TextSize = 15
	name.Position = UDim2.fromOffset(opts.imageSize + 12, 4)
	name.Size = UDim2.new(1, -(opts.imageSize + 260), 0, 20)
	name.Parent = row

	local detail = Instance.new("TextLabel")
	detail.Name = "Detail"
	detail.BackgroundTransparency = 1
	detail.TextXAlignment = Enum.TextXAlignment.Left
	detail.TextColor3 = Color3.fromRGB(170, 174, 182)
	detail.TextSize = 12
	detail.Position = UDim2.fromOffset(opts.imageSize + 12, 26)
	detail.Size = UDim2.new(1, -(opts.imageSize + 260), 0, 18)
	detail.Parent = row

	local ready = Instance.new("TextButton")
	ready.Name = "Ready"
	ready.Text = "Ready"
	ready.TextSize = 12
	ready.TextColor3 = Color3.fromRGB(235, 236, 240)
	ready.BackgroundColor3 = Color3.fromRGB(58, 62, 70)
	ready.BorderSizePixel = 0
	ready.AnchorPoint = Vector2.new(1, 0.5)
	ready.Position = UDim2.new(1, -180, 0.5, 0)
	ready.Size = UDim2.fromOffset(64, 28)
	ready.Parent = row

	-- the value control, matched in SHAPE to the Facet Stepper: a readout
	-- flanked by decrement/increment affordances
	local minus = Instance.new("TextButton")
	minus.Name = "Minus"
	minus.Text = "-"
	minus.TextSize = 14
	minus.TextColor3 = Color3.fromRGB(235, 236, 240)
	minus.BackgroundColor3 = Color3.fromRGB(58, 62, 70)
	minus.BorderSizePixel = 0
	minus.AnchorPoint = Vector2.new(1, 0.5)
	minus.Position = UDim2.new(1, -142, 0.5, 0)
	minus.Size = UDim2.fromOffset(28, 28)
	minus.Parent = row

	local readout = Instance.new("TextLabel")
	readout.Name = "Rate"
	readout.BackgroundTransparency = 1
	readout.TextSize = 12
	readout.TextColor3 = Color3.fromRGB(235, 236, 240)
	readout.AnchorPoint = Vector2.new(1, 0.5)
	readout.Position = UDim2.new(1, -104, 0.5, 0)
	readout.Size = UDim2.fromOffset(38, 28)
	readout.Parent = row

	local plus = Instance.new("TextButton")
	plus.Name = "Plus"
	plus.Text = "+"
	plus.TextSize = 14
	plus.TextColor3 = Color3.fromRGB(235, 236, 240)
	plus.BackgroundColor3 = Color3.fromRGB(58, 62, 70)
	plus.BorderSizePixel = 0
	plus.AnchorPoint = Vector2.new(1, 0.5)
	plus.Position = UDim2.new(1, -72, 0.5, 0)
	plus.Size = UDim2.fromOffset(28, 28)
	plus.Parent = row

	local open = Instance.new("TextButton")
	open.Name = "Open"
	open.Text = "Open"
	open.TextSize = 12
	open.TextColor3 = Color3.fromRGB(235, 236, 240)
	open.BackgroundColor3 = Color3.fromRGB(72, 108, 168)
	open.BorderSizePixel = 0
	open.AnchorPoint = Vector2.new(1, 0.5)
	open.Position = UDim2.new(1, -6, 0.5, 0)
	open.Size = UDim2.fromOffset(60, 28)
	open.Parent = row

	return {
		frame = row,
		avatar = avatar,
		name = name,
		detail = detail,
		ready = ready,
		readout = readout,
		key = nil :: string?,
	}
end

-- opts: { items, rowHeight, rowGap, imageSize, viewportHeight, overscan }
function native_list.mount(opts: any): any
	assert(active == nil, "[native reference] already mounted; exactly one implementation may be live during a capture")

	local items = opts.items
	local pitch = opts.rowHeight + opts.rowGap
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- NAME IT WITHOUT THE `Facet` PREFIX ON PURPOSE. The runner's instance census
	-- counts `Facet*` ScreenGuis as Facet's own and everything else as foreign;
	-- this tree is emphatically NOT Facet's, and a name that made it look like it
	-- would inflate the framework's own cost in exactly the comparison this
	-- reference exists to make honest.
	local gui = Instance.new("ScreenGui")
	gui.Name = "NativeReferenceList"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	local head = Instance.new("TextLabel")
	head.Name = "Head"
	head.BackgroundTransparency = 1
	head.TextXAlignment = Enum.TextXAlignment.Left
	head.TextColor3 = Color3.fromRGB(235, 236, 240)
	head.TextSize = 14
	head.Text = `raw Roblox reference · {#items} rows`
	head.Position = UDim2.fromOffset(8, 8)
	head.Size = UDim2.new(1, -16, 0, 20)
	head.Parent = gui

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.Position = UDim2.fromOffset(8, 34)
	scroll.Size = UDim2.new(1, -16, 0, opts.viewportHeight)
	scroll.BackgroundColor3 = Color3.fromRGB(24, 26, 30)
	scroll.BorderSizePixel = 0
	scroll.ClipsDescendants = true
	scroll.ScrollBarThickness = 8
	scroll.CanvasSize = UDim2.fromOffset(0, math.max(0, #items * pitch - opts.rowGap))
	scroll.Parent = gui

	local poolSize = math.ceil(opts.viewportHeight / pitch) + 2 * opts.overscan + 2
	local pool: { any } = table.create(poolSize)
	for _ = 1, poolSize do
		table.insert(pool, newRowFrame(scroll, opts))
	end

	local selected: string? = nil
	local overrides: { [string]: string } = {}
	local valueOverrides: { [string]: number } = {}

	local function paint(slot: any, index: number)
		local item = items[index]
		if item == nil then
			slot.frame.Visible = false
			slot.key = nil
			return
		end
		slot.key = item.id
		slot.frame.Position = UDim2.fromOffset(0, (index - 1) * pitch)
		slot.frame.Size = UDim2.new(1, -8, 0, opts.rowHeight)
		slot.frame.Visible = true
		slot.frame.BackgroundColor3 = if selected == item.id
			then Color3.fromRGB(60, 78, 118)
			else Color3.fromRGB(38, 40, 44)
		slot.name.Text = overrides[item.id] or item.name
		slot.detail.Text = item.detail
		slot.avatar.Image = item.imageKey
		slot.readout.Text = string.format("%d%%", math.floor((valueOverrides[item.id] or item.value) * 100 + 0.5))
		slot.ready.BackgroundColor3 = if item.enabled then Color3.fromRGB(72, 108, 168) else Color3.fromRGB(58, 62, 70)
	end

	local firstIndex = -1
	local function window()
		local top = scroll.CanvasPosition.Y
		local start = math.max(1, math.floor(top / pitch) + 1 - opts.overscan)
		if start == firstIndex then
			return
		end
		firstIndex = start
		for i, slot in pool do
			paint(slot, start + i - 1)
		end
	end
	window()

	local conn = scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(window)

	local api = {}

	function api.mountedRows(): number
		local n = 0
		for _, slot in pool do
			if slot.frame.Visible then
				n += 1
			end
		end
		return n
	end

	function api.canvasPosition(): number
		return scroll.CanvasPosition.Y
	end

	function api.scrollTo(y: number)
		scroll.CanvasPosition = Vector2.new(0, y)
		-- the engine coalesces the property change signal, so the window is
		-- refreshed synchronously here too: a driven scroll must do the same work
		-- a player's scroll does, in the same call, or the comparison is unfair to
		-- Facet (whose windowing IS synchronous with the refresh)
		window()
	end

	function api.select(key: string)
		selected = key
		for _, slot in pool do
			if slot.key ~= nil then
				slot.frame.BackgroundColor3 = if selected == slot.key
					then Color3.fromRGB(60, 78, 118)
					else Color3.fromRGB(38, 40, 44)
			end
		end
	end

	function api.updateOne(key: string, text: string)
		overrides[key] = text
		for _, slot in pool do
			if slot.key == key then
				slot.name.Text = text
			end
		end
	end

	function api.updateBatch(seed: number)
		for i, slot in pool do
			if slot.key ~= nil then
				local v = ((seed + i) % 20) / 20
				valueOverrides[slot.key] = v
				slot.readout.Text = string.format("%d%%", math.floor(v * 100 + 0.5))
			end
		end
	end

	function api.dispose()
		conn:Disconnect()
		gui:Destroy()
		active = nil
	end

	api.capabilities = native_list.CAPABILITIES
	api.version = native_list.VERSION
	active = api
	return api
end

function native_list.mounted(): boolean
	return active ~= nil
end

return native_list
