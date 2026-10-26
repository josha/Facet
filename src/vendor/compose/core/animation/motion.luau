--!strict
--!native

local Codec = require "./codec"
local Diagnostics = require "../diagnostics"
local Easing = require "./easing"
local Host = require "../host"
local Owner = require "../ownership/owner"
local ownedFrame = require "../ownership/frame"
local Spring = require "./spring"
local Types = require "../reactive/types"
local cellModule = require "../reactive/cell"
local watchModule = require "../reactive/watch"

export type ReducedMotion = Types.Value<boolean> | Types.Value<boolean> | Types.Source<boolean>

export type SpringOptions = {
	period: number?,
	damping: number?,
	tolerance: number?,
	reducedMotion: ReducedMotion?,
}

export type Duration = Types.Input<number>

export type TweenOptions = {
	seconds: Duration?,
	ease: Easing.Easing?,
	reducedMotion: ReducedMotion?,
}

export type Motion = {
	spring: <T>(source: Types.Body<T>, options: SpringOptions?) -> Types.ReadOnlyValue<T>,
	tween: <T>(source: Types.Body<T>, options: TweenOptions?) -> Types.ReadOnlyValue<T>,
}

local DEFAULT_PERIOD = 0.5
local DEFAULT_DAMPING = 1
local DEFAULT_TOLERANCE = 1e-4
local DEFAULT_SECONDS = 0.25

local function framesOf(host: Host.Host, primitive: string): Host.Frames
	local frames = host.frames
	if frames == nil then
		error(
			Diagnostics.format("animation/no-frames", ("host %q cannot drive %s"):format(host.name, primitive), {
				contract = "animation needs a frame loop, which is the host frames capability",
				fix = "implement host.frames.onFrame and host.frames.now, or animate outside Compose",
			}),
			0
		)
	end
	return frames
end

local function policyOf(value: ReducedMotion?, primitive: string): Types.Body<boolean>?
	if value == nil then
		return nil
	end
	if type(value) == "function" then
		return value
	end
	if cellModule.isValue(value) then
		local readable = value
		return function(use: Types.Use): boolean
			return use(readable)
		end
	end
	error(
		Diagnostics.format(
			"animation/bad-reduced-motion",
			("%s cannot read this reduced motion policy"):format(primitive),
			{
				key = "reducedMotion",
				actual = Diagnostics.describe(value),
				expected = "a cell, a formula or a body returning a boolean",
				contract = "the policy is read reactively, because the setting changes while the application runs",
			}
		),
		0
	)
	return nil
end

local function createMotion(host: Host.Host, ownerOf: (primitive: string) -> Owner.Owner): Motion
	local function animate<T>(
		primitive: string,
		source: Types.Body<T>,
		makeAdvance: (
			codec: Codec.Codec<T>,
			current: { number },
			target: { number },
			reference: { number }
		) -> ((delta: number) -> boolean, (() -> ())?),
		onRetarget: (() -> ())?,
		reducedMotion: Types.Body<boolean>?
	): Types.ReadOnlyValue<T>
		local frames = framesOf(host, primitive)
		local owner = ownerOf(primitive)

		local codec: Codec.Codec<T>
		local arity = 0
		local current: { number }
		local target: { number }
		local reference: { number }
		local advance: (delta: number) -> boolean
		local settleNow: (() -> ())?
		local output: Types.Value<T>
		local typeName = ""

		local function publish()
			local normalise = codec.normalise
			if normalise ~= nil then
				normalise(current)
			end
			output:set(codec.decode(current))
		end

		local pump: ownedFrame.Pump
		local function onFrame(delta: number)
			local arrived = advance(delta)
			publish()
			if arrived then
				pump.stop()
			end
		end
		pump = ownedFrame(owner, frames.onFrame, onFrame)

		Owner.watch(owner, function(use)
			local wanted = source(use)
			local reduced = reducedMotion ~= nil and reducedMotion(use) == true

			if arity == 0 then
				typeName = Host.typeNameOf(host, wanted)
				codec = Codec.codecFor(typeName)
				arity = codec.arity
				current = table.create(arity, 0)
				target = table.create(arity, 0)
				reference = table.create(arity, 0)
				codec.encode(wanted, current)
				codec.encode(wanted, target)
				codec.encode(wanted, reference)
				output = cellModule.cell(wanted)
				advance, settleNow = makeAdvance(codec, current, target, reference)

				return
			end

			if Host.typeNameOf(host, wanted) ~= typeName then
				error(
					Diagnostics.format(
						"animation/type-changed",
						("%s was given a different type mid-flight"):format(primitive),
						{
							expected = typeName,
							actual = Host.typeNameOf(host, wanted),
							contract = "an animated value keeps one type for its lifetime",
							fix = "use show or switch to swap between differently-typed values",
						}
					),
					0
				)
			end

			for index = 1, arity do
				reference[index] = current[index]
			end
			codec.encode(wanted, target)
			if reduced then
				pump.stop()
				if settleNow ~= nil then
					settleNow()
				end
				for index = 1, arity do
					current[index] = target[index]
					reference[index] = target[index]
				end
				publish()
				return
			end
			if onRetarget ~= nil then
				onRetarget()
			end
			pump.start()
		end)

		return output
	end

	local function spring<T>(source: Types.Body<T>, options: SpringOptions?): Types.ReadOnlyValue<T>
		local period = if options ~= nil and options.period ~= nil then options.period else DEFAULT_PERIOD
		local damping = if options ~= nil and options.damping ~= nil then options.damping else DEFAULT_DAMPING
		local tolerance = if options ~= nil and options.tolerance ~= nil then options.tolerance else DEFAULT_TOLERANCE

		if period <= 0 then
			error(
				Diagnostics.format("animation/bad-period", "a spring needs a positive period", {
					actual = tostring(period),
					expected = "seconds for one undamped oscillation, e.g. 0.4",
				}),
				0
			)
		end

		return animate("spring", source, function(codec, current, target, reference)
			local live = Spring.createState(current, codec.arity)
			local function settle()
				Spring.settle(live, target)
			end
			return function(delta: number): boolean
				Spring.step(live, target, delta, period, damping)
				for index = 1, codec.arity do
					current[index] = live.position[index]
				end
				if Spring.atRest(live, target, reference, tolerance) then
					Spring.settle(live, target)
					for index = 1, codec.arity do
						current[index] = target[index]
					end
					return true
				end
				return false
			end,
				settle
		end, nil, policyOf(if options ~= nil then options.reducedMotion else nil, "spring"))
	end

	local function tween<T>(source: Types.Body<T>, options: TweenOptions?): Types.ReadOnlyValue<T>
		local wanted: Duration = if options ~= nil and options.seconds ~= nil then options.seconds else DEFAULT_SECONDS
		local ease: Easing.Easing
		if options ~= nil and options.ease ~= nil then
			ease = options.ease
		else
			ease = Easing.linear
		end

		local durations: (() -> number)? = nil
		local seconds = DEFAULT_SECONDS
		if type(wanted) == "number" then
			seconds = wanted
			if seconds <= 0 then
				error(
					Diagnostics.format("animation/bad-duration", "a tween needs a positive duration", {
						actual = tostring(seconds),
						expected = "seconds, e.g. 0.25",
					}),
					0
				)
			end
		elseif cellModule.isValue(wanted) then
			local readable = wanted :: Types.ReadOnlyValue<number>
			durations = function(): number
				return readable:peek()
			end
		elseif type(wanted) == "function" then
			local body = wanted
			durations = function(): number
				return watchModule.sample(function()
					return ((body :: unknown) :: (nil) -> number)(nil)
				end)
			end
		else
			error(
				Diagnostics.format(
					"animation/bad-duration",
					"a tween duration must be seconds or a source of seconds",
					{
						actual = type(wanted),
						expected = "a number, a cell, a formula, or a body, e.g. 0.25",
						contract = "TweenOptions.seconds is a number or a source of one",
					}
				),
				0
			)
		end

		local elapsed = 0
		local onRetarget: () -> ()
		if durations == nil then
			onRetarget = function()
				elapsed = 0
			end
		else
			local sampleSeconds = durations
			onRetarget = function()
				local length = sampleSeconds()
				if type(length) ~= "number" or length <= 0 then
					error(
						Diagnostics.format(
							"animation/bad-duration",
							"a tween's duration source produced a bad length",
							{
								actual = tostring(length),
								expected = "positive seconds, e.g. 0.25",
								contract = "a duration source yields positive seconds at every retarget",
							}
						),
						0
					)
				end
				seconds = length
				elapsed = 0
			end
		end

		return animate("tween", source, function(codec, current, target, reference)
			return function(delta: number): boolean
				elapsed = math.min(elapsed + delta, seconds)
				local t = ease(elapsed / seconds)
				for index = 1, codec.arity do
					current[index] = reference[index] + (target[index] - reference[index]) * t
				end
				if elapsed >= seconds then
					for index = 1, codec.arity do
						current[index] = target[index]
					end
					return true
				end
				return false
			end,
				nil
		end, onRetarget, policyOf(if options ~= nil then options.reducedMotion else nil, "tween"))
	end

	return {
		spring = spring,
		tween = tween,
	}
end

return {
	createMotion = createMotion,
}
