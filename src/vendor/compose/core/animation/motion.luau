--!strict
--!native

local Codec = require "./codec"
local Diagnostics = require "../diagnostics"
local Easing = require "./easing"
local Host = require "../host"
local Owner = require "../ownership/owner"
local Reactor = require "../reactive/reactor"
local Spring = require "./spring"
local Types = require "../reactive/types"
local cellModule = require "../reactive/cell"
local watchModule = require "../reactive/watch"

export type ReducedMotion = Types.Cell<boolean> | Types.Formula<boolean> | Types.Source<boolean>

export type SpringOptions = {
	period: number?,
	damping: number?,
	tolerance: number?,
	reducedMotion: ReducedMotion?,
}

export type Duration = Types.Value<number>

export type TweenOptions = {
	seconds: Duration?,
	ease: Easing.Easing?,
	reducedMotion: ReducedMotion?,
}

export type Motion = {
	spring: <T>(source: Types.Body<T>, options: SpringOptions?) -> Types.Readable<T>,
	tween: <T>(source: Types.Body<T>, options: TweenOptions?) -> Types.Readable<T>,
}

local DEFAULT_PERIOD = 0.5
local DEFAULT_DAMPING = 1
local DEFAULT_TOLERANCE = 1e-4
local DEFAULT_SECONDS = 0.25

local function framesOf(host: Host.Host, primitive: string): Host.Frames
	local frames = host.frames
	if frames == nil then
		Diagnostics.raise("animation/no-frames", ("host %q cannot drive %s"):format(host.name, primitive), {
			contract = "animation needs a frame loop, which is the host frames capability",
			fix = "implement host.frames.onFrame and host.frames.now, or animate outside Compose",
		})
	end
	return frames :: Host.Frames
end

local function policyOf(value: ReducedMotion?, primitive: string): Types.Body<boolean>?
	if value == nil then
		return nil
	end
	if type(value) == "function" then
		return value :: Types.Body<boolean>
	end
	if cellModule.isReadable(value) then
		local readable = value :: Types.Readable<boolean>
		return function(use: Types.Use): boolean
			return use(readable)
		end
	end
	Diagnostics.raise("animation/bad-reduced-motion", ("%s cannot read this reduced motion policy"):format(primitive), {
		key = "reducedMotion",
		actual = Diagnostics.describe(value),
		expected = "a cell, a formula or a body returning a boolean",
		contract = "the policy is read reactively, because the setting changes while the application runs",
	})
	return nil
end

type HubMember = {
	active: boolean,
	callback: (delta: number) -> (),
}

local function createMotion(
	host: Host.Host,
	ownerOf: (primitive: string) -> Owner.Owner,
	reactor: Reactor.Reactor
): Motion
	local hubMembers: { HubMember } = {}
	local hubLive = 0
	local hubUnsubscribe: Host.Unsubscribe? = nil
	local hubDispatching = false
	local hubDelta = 0

	local function runMembers(): ...unknown
		local count = #hubMembers
		for index = 1, count do
			local member = hubMembers[index]
			if member.active then
				member.callback(hubDelta)
			end
		end
	end

	local function hubCompact()
		if hubLive == #hubMembers then
			return
		end
		local write = 0
		for read = 1, #hubMembers do
			local member = hubMembers[read]
			if member.active then
				write += 1
				hubMembers[write] = member
			end
		end
		for index = #hubMembers, write + 1, -1 do
			hubMembers[index] = nil
		end
	end

	local function hubStop()
		if hubLive > 0 then
			return
		end
		local active = hubUnsubscribe
		if active ~= nil then
			hubUnsubscribe = nil
			active()
		end
	end

	local function hubStep(delta: number)
		hubDelta = delta
		hubDispatching = true
		local ok, err: unknown = pcall(reactor.batch, reactor, runMembers)
		hubDispatching = false
		hubCompact()
		hubStop()
		if not ok then
			error(err, 0)
		end
	end

	local function hubAdd(frames: Host.Frames, callback: (delta: number) -> ()): HubMember
		local member: HubMember = { active = true, callback = callback }
		table.insert(hubMembers, member)
		hubLive += 1
		if hubUnsubscribe == nil then
			hubUnsubscribe = frames.onFrame(hubStep)
		end
		return member
	end

	local function hubRemove(member: HubMember)
		if not member.active then
			return
		end
		member.active = false
		hubLive -= 1
		if not hubDispatching then
			hubCompact()
			hubStop()
		end
	end
	local function animate<T>(
		primitive: string,
		source: Types.Body<T>,
		makeAdvance: (
			codec: Codec.Codec<any>,
			current: { number },
			target: { number },
			reference: { number }
		) -> ((delta: number) -> boolean, (() -> ())?),
		onRetarget: (() -> ())?,
		reducedMotion: Types.Body<boolean>?
	): Types.Readable<T>
		local frames = framesOf(host, primitive)
		local owner = ownerOf(primitive)

		local codec: Codec.Codec<any>
		local arity = 0
		local current: { number }
		local target: { number }
		local reference: { number }
		local advance: (delta: number) -> boolean
		local settleNow: (() -> ())?
		local output: Types.Cell<T>
		local typeName = ""

		local hubMember: HubMember? = nil
		local disposed = false

		local function publish()
			local normalise = codec.normalise
			if normalise ~= nil then
				normalise(current)
			end
			output:set(codec.decode(current))
		end

		local function stop()
			local active = hubMember
			if active ~= nil then
				hubMember = nil
				hubRemove(active)
			end
		end

		local function onFrame(delta: number)
			if disposed then
				return
			end
			local arrived = advance(delta)
			publish()
			if arrived then
				stop()
			end
		end

		local function start()
			if disposed or hubMember ~= nil then
				return
			end
			hubMember = hubAdd(frames, onFrame)
		end

		owner.own(function()
			disposed = true
			stop()
		end)

		owner.watch(function(use)
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
				Diagnostics.raise(
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

			for index = 1, arity do
				reference[index] = current[index]
			end
			codec.encode(wanted, target)
			if reduced then
				stop()
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
			start()
		end)

		return output
	end

	local function spring<T>(source: Types.Body<T>, options: SpringOptions?): Types.Readable<T>
		local period = if options ~= nil and options.period ~= nil then options.period else DEFAULT_PERIOD
		local damping = if options ~= nil and options.damping ~= nil then options.damping else DEFAULT_DAMPING
		local tolerance = if options ~= nil and options.tolerance ~= nil then options.tolerance else DEFAULT_TOLERANCE

		if period <= 0 then
			Diagnostics.raise("animation/bad-period", "a spring needs a positive period", {
				actual = tostring(period),
				expected = "seconds for one undamped oscillation, e.g. 0.4",
			})
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

	local function tween<T>(source: Types.Body<T>, options: TweenOptions?): Types.Readable<T>
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
				Diagnostics.raise("animation/bad-duration", "a tween needs a positive duration", {
					actual = tostring(seconds),
					expected = "seconds, e.g. 0.25",
				})
			end
		elseif cellModule.isReadable(wanted) then
			local readable = wanted :: Types.Readable<number>
			durations = function(): number
				return readable:peek()
			end
		elseif type(wanted) == "function" then
			local body = wanted :: Types.Body<number>
			durations = function(): number
				return watchModule.sample(function()
					return body(nil :: any)
				end)
			end
		else
			Diagnostics.raise("animation/bad-duration", "a tween duration must be seconds or a source of seconds", {
				actual = type(wanted),
				expected = "a number, a cell, a formula, or a body, e.g. 0.25",
				contract = "TweenOptions.seconds is a number or a source of one",
			})
		end

		local elapsed = 0
		local onRetarget: () -> ()
		if durations == nil then
			onRetarget = function()
				elapsed = 0
			end
		else
			local sampleSeconds = durations :: () -> number
			onRetarget = function()
				local length = sampleSeconds()
				if type(length) ~= "number" or length <= 0 then
					Diagnostics.raise("animation/bad-duration", "a tween's duration source produced a bad length", {
						actual = tostring(length),
						expected = "positive seconds, e.g. 0.25",
						contract = "a duration source yields positive seconds at every retarget",
					})
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
