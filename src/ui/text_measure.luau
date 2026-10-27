--!strict
local Types = require("./types")
local ComposeTypes = require("../vendor/compose/core")

local pending = setmetatable({} :: { [Instance]: number }, { __mode = "k" })

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

local shared = (setmetatable({}, { __mode = "k" }) :: unknown) :: {
	[Instance]: ComposeTypes.AcquireSharedResource<ComposeTypes.ReadOnlyValue<Vector2>>,
}
local readouts = (setmetatable({}, { __mode = "k" }) :: unknown) :: {
	[Instance]: ComposeTypes.AcquireSharedResource<ComposeTypes.ReadOnlyValue<Vector2>>,
}
local GENERATION = 4096
local recent: { [string]: { [string]: Vector2 } } = {}
local older: { [string]: { [string]: Vector2 } } = {}
local recentCount = 0

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

local function createNatural(
	ctx: Types.Context,
	label: TextLabel | TextButton | TextBox,
	fallback: (() -> ComposeTypes.ReadOnlyValue<Vector2>)?,
	revision: ComposeTypes.Value<number>?,
	stable: boolean?,
	styling: ComposeTypes.Value<number>?,
	content: ComposeTypes.ReadOnlyValue<string>?
): ComposeTypes.ReadOnlyValue<Vector2>
	local Compose, Host = ctx.Compose, ctx.Host
	local shaper: GetTextBoundsParams? = nil
	local makeShaper = Compose.bindOwner(function()
		shaper = (
			((Host :: unknown) :: { GetTextBoundsParams: ({ Width: number }) -> GetTextBoundsParams }).GetTextBoundsParams
		)({ Width = 0 })
	end)
	local service = ctx.config.services.TextService
	local bounds = Compose.cell(ctx.types.Vector2.new(math.huge, 0))
	if service == nil then
		return if fallback then fallback() else bounds
	end
	local text = if revision then nil else ctx.observe.Text(label)
	local rich = if revision then nil else ctx.observe.RichText(label)
	local font = if revision then nil else ctx.observeStyled.FontFace(label)
	local points = if revision then nil else ctx.observeStyled.TextSize(label)
	local serial, alive = 0, true
	local lastWords: string?, lastGeometry = nil, ""
	local metrics, widest, tallest, heldLength = "", 0, 0, -1
	local styledAt = -1
	local markup: boolean = false
	local face: Font = label.FontFace
	local size: number = 0
	local geometry = ""
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
			value = ctx.types.Vector2.new(widest, tallest)
		end
		bounds:set(value)
	end
	Compose.watch(function(use: ComposeTypes.Use)
		if revision then
			use(revision)
		end
		local words = if text then use(text) elseif content then use(content) else label.Text
		if styling == nil or styling:peek() ~= styledAt or text ~= nil then
			styledAt = if styling then styling:peek() else -1
			markup = if rich then use(rich) else label.RichText
			face = if font then use(font) else label:GetStyled("FontFace") :: Font
			size = if points then use(points) else label:GetStyled("TextSize") :: number
			geometry =
				`{face.Family}|{face.Weight.Name}|{face.Style.Name}|{size}|{markup}|{label.AutomaticSize.Name}|{label:GetStyled(
					"TextWrapped"
				)}|{label:GetStyled("TextTruncate")}|{label:GetStyled("LineHeight")}`
		end
		if words == lastWords and geometry == lastGeometry then
			return
		end
		lastWords, lastGeometry = words, geometry
		serial += 1
		local ticket = serial
		cancel()
		local known = recall(geometry, words)
		if known then
			publish(words, known)
			return
		end
		local completed = hold(label)
		release = completed
		if shaper == nil then
			makeShaper()
		end
		local request = assert(shaper)
		request.Text, request.RichText, request.Font, request.Size, request.Width = words, markup, face, size, 0
		local shape = geometry
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
			end
		end
		if task and task.spawn then
			thread = task.spawn(measure)
		else
			measure()
		end
	end)
	return bounds
end

return {
	hold = hold,
	pending = function(node: Instance): boolean
		return pending[node] ~= nil
	end,
	natural = function(
		ctx: Types.Context,
		label: TextLabel | TextButton | TextBox,
		fallback: (() -> ComposeTypes.ReadOnlyValue<Vector2>)?,
		revision: ComposeTypes.Value<number>?,
		stable: boolean?,
		styling: ComposeTypes.Value<number>?,
		content: ComposeTypes.ReadOnlyValue<string>?
	): ComposeTypes.ReadOnlyValue<Vector2>
		if ctx.config.services.TextService == nil then
			return if fallback then fallback() else ctx.Compose.cell(ctx.types.Vector2.new(math.huge, 0))
		end
		local resources: { [Instance]: ComposeTypes.AcquireSharedResource<ComposeTypes.ReadOnlyValue<Vector2>> } = if stable
			then readouts
			else shared
		local acquire: ComposeTypes.AcquireSharedResource<ComposeTypes.ReadOnlyValue<Vector2>>? = resources[label]
		if not acquire then
			acquire = ctx.Compose.createSharedResource(function(): (ComposeTypes.ReadOnlyValue<Vector2>, (() -> ())?)
				ctx.Compose.cleanup(function()
					resources[label] = nil
				end)
				return createNatural(ctx, label, nil, revision, stable, styling, content), nil
			end)
			resources[label] = acquire
		end
		return assert(acquire)()
	end,
}
