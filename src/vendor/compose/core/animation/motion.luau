--!strict
--!native

local CoreTypes = require "../types"
local Ramp = require "./ramp"
local Codec = require "./codec"
local Diagnostics = require "../diagnostics"
local Dynamic = require "../dynamic"
local Easing = require "./easing"
local Host = require "../host"
local Owner = require "../ownership/owner"
local Spring = require "./spring"
local Types = require "../reactive/types"
local cellModule = require "../reactive/cell"
local watchModule = require "../reactive/watch"

export type ReducedMotion = CoreTypes.ReducedMotion

export type SpringOptions = CoreTypes.SpringOptions

export type Duration = CoreTypes.Duration

export type TweenOptions = CoreTypes.TweenOptions

export type Motion<T> = CoreTypes.Motion<T>

local DEFAULT_PERIOD = 0.5
local DEFAULT_DAMPING = 1
local DEFAULT_TOLERANCE = 1e-4
local DEFAULT_SECONDS = 0.25

local function framesOf(host: Host.Host, primitive: string): Host.Frames
	local frames = host.frames
	if frames == nil then
		return Diagnostics.raise("animation/no-frames", ("host %q cannot drive %s"):format(host.name, primitive), {
			contract = "animation needs a frame loop, which is the host frames capability",
			fix = "implement host.frames.onFrame and host.frames.now, or animate outside Compose",
		})
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

type Settings = {
	[number]: number,
	ease: Easing.Easing?,
	duration: (() -> number)?,
}

type State<T> = Spring.State & {
	current: { number },
	target: { number },
	reference: { number },
	output: Types.Value<T>,
	settings: Settings,
}

local function advance<T>(state: State<T>, delta: number, codec: Codec.Codec<T>): boolean
	local current, target, reference = state.current, state.target, state.reference
	local settings = state.settings
	local arrived: boolean
	if settings.ease == nil then
		Spring.advance(state, target, delta, settings[1], settings[2])
		arrived = Spring.atRest(state, target, reference, settings[3])
		if arrived then
			Spring.settle(state, target)
		end
		if state.position ~= current then
			for index = 1, codec.arity do
				current[index] = state.position[index]
			end
		end
	else
		settings[1] = math.min(settings[1] + delta, settings[2])
		arrived = settings[1] >= settings[2]
		local t = (settings.ease or Easing.linear)(settings[1] / settings[2])
		for index = 1, codec.arity do
			current[index] = if arrived
				then target[index]
				else reference[index] + (target[index] - reference[index]) * t
		end
	end
	local normalise = codec.normalise
	if normalise ~= nil then
		normalise(current)
	end
	state.output:set(codec.decode(current))
	return arrived
end

local function createMotion<T>(
	host: Host.Host,
	ownerOf: (primitive: string) -> Owner.Owner,
	codec: Codec.Codec<T>
): Motion<T>
	Codec.validate(codec)
	local active: { State<T>? } = {}
	local count, live = 0, 0
	local unsubscribe: Host.Unsubscribe? = nil
	local dispatching = false
	local cursor, limit = 0, 0

	local function compact()
		if dispatching or count == live then
			return
		end
		local write = 0
		for index = 1, count do
			local state = active[index]
			if state then
				write += 1
				active[write] = state
				state.settings[4] = write
			end
		end
		for index = count, write + 1, -1 do
			active[index] = nil
		end
		count = write
	end

	local function stop(subject: unknown)
		local index = Dynamic.raw(subject, 4)
		if type(index) ~= "number" then
			return
		end
		local state = active[index]
		if state == nil or state.settings ~= subject then
			return
		end
		active[index] = nil
		state.settings[4] = 0
		live -= 1
		if live == 0 and unsubscribe then
			local release = unsubscribe
			unsubscribe = nil
			release()
		end
	end

	local function sweep(delta: number)
		while cursor < limit do
			cursor += 1
			local state = active[cursor]
			if state and advance(state, delta, codec) then
				stop(state.settings)
			end
		end
	end

	local function onFrame(delta: number)
		local previousCursor, previousLimit, previousDispatching = cursor, limit, dispatching
		cursor, limit, dispatching = 0, count, true
		local failures: { unknown }? = nil
		while true do
			local ok, problem: unknown = pcall(sweep, delta)
			if ok then
				break
			end
			local collected = failures or {}
			failures = collected
			table.insert(collected, problem)
		end
		cursor, limit, dispatching = previousCursor, previousLimit, previousDispatching
		compact()
		if failures then
			Owner.raiseAll(failures)
		end
	end

	local function animate(
		primitive: string,
		source: Types.Body<T>,
		settings: Settings,
		reducedMotion: Types.Body<boolean>?
	): Types.ReadOnlyValue<T>
		local frames = framesOf(host, primitive)
		local owner = ownerOf(primitive)
		settings[4] = 0
		local state: State<T>? = nil
		local typeName = ""
		Owner.watch(owner, function(use)
			local wanted = source(use)
			local reduced = reducedMotion ~= nil and reducedMotion(use) == true
			local currentState = state
			if currentState == nil then
				typeName = Host.typeNameOf(host, wanted)
				local current = table.create(codec.arity, 0)
				local target = table.create(codec.arity, 0)
				local reference = table.create(codec.arity, 0)
				codec.encode(wanted, current)
				codec.encode(wanted, target)
				codec.encode(wanted, reference)
				local created: State<T> = {
					current = current,
					target = target,
					reference = reference,
					position = if settings.ease == nil and codec.normalise then table.clone(current) else current,
					velocity = if settings.ease then reference else table.create(codec.arity, 0),
					arity = codec.arity,
					output = cellModule.cell(wanted),
					settings = settings,
				}
				state = created
				Owner.holdSubject(owner, stop, settings)
				return
			end
			if Host.typeNameOf(host, wanted) ~= typeName then
				return Diagnostics.raise(
					"animation/type-changed",
					("%s was given a different type mid-flight"):format(primitive),
					{
						expected = typeName,
						actual = Host.typeNameOf(host, wanted),
						contract = "an animated value keeps one type for its lifetime",
						fix = "use show or switch to swap between differently-typed values",
					}
				)
			end
			local current, target, reference = currentState.current, currentState.target, currentState.reference
			for index = 1, codec.arity do
				reference[index] = current[index]
			end
			codec.encode(wanted, target)
			if reduced then
				stop(settings)
				if settings.ease == nil then
					Spring.settle(currentState, target)
				end
				for index = 1, codec.arity do
					current[index], reference[index] = target[index], target[index]
				end
				local normalise = codec.normalise
				if normalise then
					normalise(current)
				end
				currentState.output:set(codec.decode(current))
				return
			end
			local duration = settings.duration
			if duration then
				local seconds = duration()
				if type(seconds) ~= "number" or seconds <= 0 then
					return Diagnostics.raise(
						"animation/bad-duration",
						"a tween's duration source produced a bad length",
						{
							actual = tostring(seconds),
							expected = "positive seconds, e.g. 0.25",
							contract = "a duration source yields positive seconds at every retarget",
						}
					)
				end
				settings[2] = seconds
			end
			if settings.ease then
				settings[1] = 0
			end
			if settings[4] == 0 and not Owner.isDisposed(owner) then
				compact()
				count += 1
				live += 1
				settings[4] = count
				active[count] = currentState
				if unsubscribe == nil then
					unsubscribe = frames.onFrame(onFrame)
				end
			end
		end)
		local output: Types.ReadOnlyValue<T>
		if state ~= nil then
			output = state.output
		end
		return output
	end

	local function spring(source: Types.Body<T>, options: SpringOptions?): Types.ReadOnlyValue<T>
		local period = if options ~= nil and options.period ~= nil then options.period else DEFAULT_PERIOD
		local damping = if options ~= nil and options.damping ~= nil then options.damping else DEFAULT_DAMPING
		if period <= 0 then
			return Diagnostics.raise("animation/bad-period", "a spring needs a positive period", {
				actual = tostring(period),
				expected = "seconds for one undamped oscillation, e.g. 0.4",
			})
		end
		local stiffness, drag = Spring.coefficients(period, damping)
		return animate("spring", source, {
			stiffness,
			drag,
			if options ~= nil and options.tolerance ~= nil then options.tolerance else DEFAULT_TOLERANCE,
		}, policyOf(if options ~= nil then options.reducedMotion else nil, "spring"))
	end

	local function tween(source: Types.Body<T>, options: TweenOptions?): Types.ReadOnlyValue<T>
		local wanted: Duration = if options ~= nil and options.seconds ~= nil then options.seconds else DEFAULT_SECONDS
		local settings: Settings = {
			0,
			DEFAULT_SECONDS,
			ease = if options and options.ease then options.ease else Easing.linear,
		}
		if type(wanted) == "number" then
			settings[2] = wanted
			if wanted <= 0 then
				return Diagnostics.raise("animation/bad-duration", "a tween needs a positive duration", {
					actual = tostring(wanted),
					expected = "seconds, e.g. 0.25",
				})
			end
		elseif type(wanted) == "function" then
			settings.duration = function(): number
				return watchModule.sample(function()
					return wanted(function<S>(value: Types.ReadOnlyValue<S>): S
						return value:peek()
					end)
				end)
			end
		elseif cellModule.isValue(wanted) then
			settings.duration = function(): number
				return wanted:peek()
			end
		else
			return Diagnostics.raise(
				"animation/bad-duration",
				"a tween duration must be seconds or a source of seconds",
				{
					actual = type(wanted),
					expected = "a number, a cell, a formula, or a body, e.g. 0.25",
					contract = "TweenOptions.seconds is a number or a source of one",
				}
			)
		end
		return animate(
			"tween",
			source,
			settings,
			policyOf(if options ~= nil then options.reducedMotion else nil, "tween")
		)
	end

	return { spring = spring, tween = tween, ramp = Ramp.createRamps(tween, ownerOf) }
end

return {
	createMotion = createMotion,
}
