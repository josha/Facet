--!strict
local Compose = require("../vendor/compose/core")
local Types = require("./types")
type SnapOptions = { direction: Compose.OrderedCollectionDirection?, reducedMotion: Types.Value<boolean>? }
return function<K>(
	ctx: Types.Context,
	spec: SnapOptions,
	root: ScrollingFrame,
	controls: Compose.OrderedCollectionControls<K>,
	status: Compose.Cell<Compose.OrderedCollectionStatus>,
	viewport: Compose.Cell<Compose.OrderedCollectionViewport>,
	setOffset: (number) -> (),
	frameworkWrite: () -> boolean
): ()
	local Compose, runtime, E = ctx.Compose, ctx.runtime, ctx.types.Enum
	local frames = assert(runtime.host.frames)
	local clock = frames.now
	local motion = runtime.timeline({ duration = 0.18, autoplay = false })
	local held, running, writing = false, false, false
	local stopWait: Compose.Dispose? = nil
	local idle, from, target = 0, 0, 0
	local previous, previousTime, velocity, gestureStart = 0, clock(), 0, 0
	local function cancel()
		running = false
		motion:pause()
		if stopWait then
			stopWait()
			stopWait = nil
		end
	end
	local function write(value: number): ()
		writing = true
		setOffset(value)
		writing = false
	end
	local function lowerBound(offset: number, total: number): number
		local low, high = 1, total + 1
		while low < high do
			local middle = math.floor((low + high) / 2)
			if assert(controls.placementOf)(middle).offset < offset then
				low = middle + 1
			else
				high = middle
			end
		end
		return low
	end
	local function settle()
		local current, box = status:peek(), viewport:peek()
		if current == nil or current.total == nil or current.total == 0 then
			return
		end
		local maximum = math.max(0, current.extent - box.size)
		local index = lowerBound(box.offset, current.total)
		local before = assert(controls.placementOf)(math.max(1, index - 1))
		if
			before.size > box.size or (index <= current.total and assert(controls.placementOf)(index).size > box.size)
		then
			return
		end
		local desired, distance = maximum, math.abs(maximum - box.offset)
		for _, at in { math.max(1, index - 1), math.min(current.total, index) } do
			local boundary = math.clamp(assert(controls.placementOf)(at).offset, 0, maximum)
			local difference = math.abs(boundary - box.offset)
			if difference < distance then
				desired, distance = boundary, difference
			end
		end
		if math.abs(velocity) > 350 and clock() - previousTime < 0.25 then
			if velocity > 0 and desired <= gestureStart then
				local nextIndex = lowerBound(gestureStart + 0.01, current.total)
				desired = if nextIndex <= current.total
					then math.min(maximum, assert(controls.placementOf)(nextIndex).offset)
					else maximum
			elseif velocity < 0 and desired >= gestureStart then
				local previousIndex = lowerBound(gestureStart, current.total) - 1
				desired = if previousIndex > 0 then assert(controls.placementOf)(previousIndex).offset else 0
			end
		end
		velocity = 0
		if math.abs(desired - box.offset) < 0.5 then
			return
		end
		if ctx.read(if spec.reducedMotion == nil then ctx.config.reducedMotion else spec.reducedMotion) then
			write(desired)
		else
			from, target, running = box.offset, desired, true
			motion:restart()
		end
	end
	local function waitForRest()
		idle = 0
		if stopWait then
			return
		end
		stopWait = frames.onFrame(function(delta)
			idle += delta
			if idle >= 0.12 and not held then
				local stop = stopWait
				stopWait = nil
				assert(stop)()
				settle()
			end
		end)
	end
	Compose.watch(function(use: Compose.Use)
		local progress = use(motion.progress)
		if running then
			write(from + (target - from) * (1 - (1 - progress) ^ 3))
			if progress >= 1 then
				running = false
			end
		end
	end)
	Compose.cleanup(assert(runtime.host.observation).observeProperty(root, "CanvasPosition", function()
		local offset = if spec.direction == "horizontal" then root.CanvasPosition.X else root.CanvasPosition.Y
		if writing then
			return
		end
		if frameworkWrite() then
			cancel()
			previous, velocity, gestureStart = offset, 0, offset
			return
		end
		if running then
			cancel()
		end
		local now = clock()
		if now > previousTime then
			velocity = (offset - previous) / (now - previousTime)
		end
		previous, previousTime = offset, now
		if not held then
			waitForRest()
		end
	end))
	local function begin(input: InputObject): ()
		if input.UserInputType == E.UserInputType.Touch or input.UserInputType == E.UserInputType.MouseButton1 then
			cancel()
			held, gestureStart, previous, previousTime, velocity =
				true, viewport:peek().offset, viewport:peek().offset, clock(), 0
		end
	end
	local function finish(input: InputObject): ()
		if
			held
			and (input.UserInputType == E.UserInputType.Touch or input.UserInputType == E.UserInputType.MouseButton1)
		then
			held = false
			if input.UserInputState == E.UserInputState.Cancel then
				cancel()
			else
				waitForRest()
			end
		end
	end
	runtime.connect(root, "InputBegan", begin)
	runtime.connect(ctx.config.userInputService or root, "InputEnded", finish)
	if ctx.config.userInputService then
		runtime.connect(ctx.config.userInputService, "WindowFocusReleased", function()
			held = false
			cancel()
		end)
	end
	Compose.cleanup(cancel)
end
