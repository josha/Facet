--!strict
local Types = require("./types")
local ComposeTypes = require("../vendor/compose/core")

type Metrics = {
	face: Font,
	size: number,
	rich: boolean,
	key: string,
}
export type Style = Metrics & {
	wrapped: boolean,
	truncate: Enum.TextTruncate,
	lineHeight: number,
}

local pending: { [Instance]: number } = setmetatable({}, { __mode = "k" })

local function hold(node: Instance): () -> ()
	pending[node] = (pending[node] or 0) + 1
	local active = true
	return function()
		if active then
			active = false
			local remaining = (pending[node] or 1) - 1
			if remaining > 0 then
				pending[node] = remaining
			else
				pending[node] = nil
			end
		end
	end
end

local shared: {
	[Instance]: ComposeTypes.AcquireSharedResource<ComposeTypes.ReadOnlyValue<Vector2>>,
} = setmetatable(
	{},
	{ __mode = "k" }
)
local GENERATION = 4096
local recent: { [string]: { [string]: Vector2 } } = {}
local older: { [string]: { [string]: Vector2 } } = {}
local recentCount = 0

local function prepare(ctx: Types.Context): (string, boolean, Font, number, number) -> GetTextBoundsParams
	local params: GetTextBoundsParams? = nil
	local text: string?, rich: boolean?, font: Font?, points: number?, wide: number? = nil, nil, nil, nil, nil
	return ctx.Compose.bindOwner(
		function(words: string, markup: boolean, face: Font, size: number, width: number): GetTextBoundsParams
			local request: GetTextBoundsParams
			if params then
				request = params
				if text ~= words then
					request.Text = words
				end
				if rich ~= markup then
					request.RichText = markup
				end
				if font ~= face then
					request.Font = face
				end
				if points ~= size then
					request.Size = size
				end
				if wide ~= width then
					request.Width = width
				end
			else
				request = ctx.Host.GetTextBoundsParams {
					Text = words,
					RichText = if markup then true else nil,
					Font = face,
					Size = size,
					Width = if width ~= 0 then width else nil,
				}
				params = request
			end
			text, rich, font, points, wide = words, markup, face, size, width
			return request
		end
	)
end

local function remember(geometry: string, words: string, value: Vector2)
	if recentCount >= GENERATION then
		older, recent, recentCount = recent, {}, 0
	end
	local bucket = recent[geometry]
	if bucket == nil then
		bucket = {}
		recent[geometry] = bucket
	end
	bucket[words] = value
	recentCount += 1
end

local function recall(geometry: string, words: string): Vector2?
	local bucket = recent[geometry]
	local value = if bucket then bucket[words] else nil
	if value == nil then
		local stale = older[geometry]
		value = if stale then stale[words] else nil
		if value then
			remember(geometry, words, value)
		end
	end
	return value
end

local function inline(
	ctx: Types.Context,
	label: TextLabel | TextButton | TextBox,
	stable: boolean?,
	styling: () -> Metrics,
	wake: () -> ()
): (words: string) -> Vector2
	local Compose = ctx.Compose
	local service = assert(ctx.config.services.TextService)
	local prepare = prepare(ctx)
	local unknown = ctx.types.Vector2.new(math.huge, 0)
	local current = unknown
	local serial, alive = 0, true
	local lastWords: string?, lastGeometry = nil, ""
	local metrics, widest, tallest, heldLength = "", 0, 0, -1
	local geometry = ""
	local measurement = ""
	local thread: thread? = nil
	local release: (() -> ())? = nil
	local function cancel()
		if release then
			release()
			release = nil
		end
		if thread and coroutine.status(thread) == "suspended" and task then
			pcall(task.cancel, thread)
		end
		thread = nil
	end
	Compose.cleanup(function()
		alive = false
		cancel()
	end)
	local function publish(words: string, value: Vector2)
		if stable then
			local length = utf8.len(words) or #words
			if geometry ~= metrics or length ~= heldLength then
				metrics, widest, tallest, heldLength = geometry, 0, 0, length
			end
			widest, tallest = math.max(widest, value.X), math.max(tallest, value.Y)
			value = if current.X == widest and current.Y == tallest
				then current
				else ctx.types.Vector2.new(widest, tallest)
		end
		current = value
	end
	return function(words: string): Vector2
		local style = styling()
		geometry = style.key
		if words == lastWords and geometry == lastGeometry then
			return current
		end
		if
			stable
			and release
			and geometry == lastGeometry
			and lastWords
			and (utf8.len(words) or #words) == (utf8.len(lastWords) or #lastWords)
		then
			return current
		end
		if geometry ~= lastGeometry then
			local face = style.face
			measurement = `{face.Family}|{face.Weight.Name}|{face.Style.Name}|{style.size}|{style.rich}`
		end
		lastWords, lastGeometry = words, geometry
		serial += 1
		local ticket = serial
		cancel()
		local known = recall(measurement, words)
		if known then
			publish(words, known)
			return current
		end
		local completed = hold(label)
		release = completed
		local request = prepare(words, style.rich, style.face, style.size, 0)
		local shape = measurement
		local settled = false
		local function measure()
			local ok, value = pcall(service.GetTextBoundsAsync, service, request)
			if ok then
				remember(shape, words, value)
			end
			if alive and ticket == serial then
				if ok then
					publish(words, value)
				end
				completed()
				release = nil
				if settled then
					wake()
				end
			end
		end
		if task and task.spawn then
			thread = task.spawn(measure)
		else
			measure()
		end
		settled = true
		return current
	end
end

local function createNatural(
	ctx: Types.Context,
	label: TextLabel | TextButton | TextBox
): ComposeTypes.ReadOnlyValue<Vector2>
	local Compose = ctx.Compose
	local bounds = Compose.cell(ctx.types.Vector2.new(math.huge, 0))
	local text = ctx.observe.Text(label)
	local rich = ctx.observe.RichText(label)
	local font = ctx.observeStyled.FontFace(label)
	local points = ctx.observeStyled.TextSize(label)
	local words = ""
	local style: Metrics? = nil
	local read: (string) -> Vector2
	read = inline(ctx, label, false, function(): Metrics
		return assert(style)
	end, function()
		bounds:set(read(words))
	end)
	Compose.watch(function(use: ComposeTypes.Use)
		local markup, face, size = use(rich), use(font), use(points)
		words = use(text)
		style = {
			face = face,
			size = size,
			rich = markup,
			key = `{face.Family}|{face.Weight.Name}|{face.Style.Name}|{size}|{markup}`,
		}
		bounds:set(read(words))
	end)
	return bounds
end

return {
	hold = hold,
	prepare = prepare,
	inline = inline,
	pending = function(node: Instance): boolean
		return pending[node] ~= nil
	end,
	natural = function(
		ctx: Types.Context,
		label: TextLabel | TextButton | TextBox,
		fallback: (() -> ComposeTypes.ReadOnlyValue<Vector2>)?
	): ComposeTypes.ReadOnlyValue<Vector2>
		if ctx.config.services.TextService == nil then
			return if fallback then fallback() else ctx.Compose.cell(ctx.types.Vector2.new(math.huge, 0))
		end
		local acquire: ComposeTypes.AcquireSharedResource<ComposeTypes.ReadOnlyValue<Vector2>>? = shared[label]
		if not acquire then
			acquire = ctx.Compose.createSharedResource(function(): (ComposeTypes.ReadOnlyValue<Vector2>, (() -> ())?)
				ctx.Compose.cleanup(function()
					shared[label] = nil
				end)
				return createNatural(ctx, label), nil
			end)
			shared[label] = acquire
		end
		return assert(acquire)()
	end,
}
