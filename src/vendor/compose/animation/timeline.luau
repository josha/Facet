--!strict

local Diagnostics = require "../diagnostics"
local Host = require "../host"
local Owner = require "../ownership/owner"
local Types = require "../reactive/types"
local cellModule = require "../reactive/cell"

export type Direction = "normal" | "alternate"

export type Options = {
	duration: number?,
	delay: number?,
	repeats: number?,
	direction: Direction?,
	scale: number?,
	autoplay: boolean?,
}

export type Timeline = {
	progress: Types.Readable<number>,
	elapsed: Types.Readable<number>,
	moving: Types.Readable<boolean>,
	completed: Types.Readable<boolean>,
	play: (self: Timeline) -> (),
	pause: (self: Timeline) -> (),
	seek: (self: Timeline, seconds: number) -> (),
	restart: (self: Timeline) -> (),
	setScale: (self: Timeline, scale: number) -> (),
}

local function positive(name: string, value: number)
	local infinite = value == math.huge
	if value ~= value or value <= 0 or (infinite and name ~= "repeats") then
		Diagnostics.raise("animation/timeline-option", ("timeline %s must be greater than zero"):format(name), {
			option = name,
			actual = tostring(value),
			expected = "a number greater than zero",
		})
	end
end

local function createTimelines(host: Host.Host, ownerOf: (primitive: string) -> Owner.Owner)
	local function timeline(options: Options?): Timeline
		local frames = host.frames
		if frames == nil then
			Diagnostics.raise("animation/no-frames", ("host %q cannot drive a timeline"):format(host.name), {
				contract = "a timeline needs a frame loop, which is the host frames capability",
				fix = "implement host.frames.onFrame and host.frames.now, or drive time outside Compose",
			})
		end
		local loop = frames :: Host.Frames
		local owner = ownerOf "timeline"

		local settings: Options = if options ~= nil then options else {}
		local duration = if settings.duration ~= nil then settings.duration else 1
		local delay = if settings.delay ~= nil then settings.delay else 0
		local repeats = if settings.repeats ~= nil then settings.repeats else 1
		local direction: Direction = if settings.direction ~= nil then settings.direction else "normal"
		local scale = if settings.scale ~= nil then settings.scale else 1
		positive("duration", duration)
		positive("repeats", repeats)
		positive("scale", scale)
		if delay < 0 or delay ~= delay then
			Diagnostics.raise("animation/timeline-option", "timeline delay must not be negative", {
				option = "delay",
				actual = tostring(delay),
				expected = "zero or more seconds",
			})
		end

		local progress = cellModule.cell(0)
		local elapsed = cellModule.cell(0)
		local moving = cellModule.cell(false)
		local completed = cellModule.cell(false)

		local clock = 0
		local unsubscribe: Host.Unsubscribe? = nil
		local disposed = false

		local function publish(): boolean
			local since = clock - delay
			if since < 0 then
				progress:set(0)
				elapsed:set(0)
				return false
			end
			elapsed:set(since)

			local run = since / duration
			local finished = run >= repeats
			local index: number
			local fraction: number
			if finished then
				local whole = math.floor(repeats)
				if repeats == whole then
					index = whole - 1
					fraction = 1
				else
					index = whole
					fraction = repeats - whole
				end
			else
				index = math.floor(run)
				fraction = run - index
			end
			if direction == "alternate" and index % 2 == 1 then
				fraction = 1 - fraction
			end
			progress:set(fraction)
			return finished
		end

		local function stop()
			local active = unsubscribe
			if active ~= nil then
				unsubscribe = nil
				active()
			end
			if moving:peek() then
				moving:set(false)
			end
		end

		local function publishAtomically(body: () -> ())
			owner.reactor:batch(body)
		end

		local function onFrame(delta: number)
			if disposed then
				return
			end
			publishAtomically(function()
				clock += delta * scale
				if publish() then
					completed:set(true)
					stop()
				end
			end)
		end

		local function start()
			if disposed or unsubscribe ~= nil or completed:peek() then
				return
			end
			unsubscribe = loop.onFrame(onFrame)
			moving:set(true)
		end

		owner.own(function()
			disposed = true
			stop()
		end)

		local self = {} :: Timeline
		self.progress = progress
		self.elapsed = elapsed
		self.moving = moving
		self.completed = completed

		function self.play()
			publishAtomically(start)
		end

		function self.pause()
			publishAtomically(stop)
		end

		function self.seek(_self: Timeline, seconds: number)
			if disposed then
				return
			end
			publishAtomically(function()
				clock = math.max(0, seconds) + delay
				local finished = publish()
				completed:set(finished)
				if finished then
					stop()
				end
			end)
		end

		function self.restart()
			if disposed then
				return
			end
			publishAtomically(function()
				clock = 0
				completed:set(false)
				publish()
				start()
			end)
		end

		function self.setScale(_self: Timeline, next: number)
			positive("scale", next)
			scale = next
		end

		publishAtomically(function()
			publish()
			if settings.autoplay ~= false then
				start()
			end
		end)
		return self
	end

	return { timeline = timeline }
end

return {
	createTimelines = createTimelines,
}
