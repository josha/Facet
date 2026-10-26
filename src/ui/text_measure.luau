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

local function createNatural(
	ctx: Types.Context,
	label: TextLabel | TextButton | TextBox,
	fallback: (() -> ComposeTypes.ReadOnlyValue<Vector2>)?,
	revision: ComposeTypes.Value<number>?,
	stable: boolean?
): ComposeTypes.ReadOnlyValue<Vector2>
	local Compose, Host = ctx.Compose, ctx.Host
	local service = ctx.config.services.TextService
	local bounds = Compose.cell(ctx.types.Vector2.new(math.huge, 0))
	if service == nil then
		return if fallback then fallback() else bounds
	end
	local params = (
		((Host :: unknown) :: { GetTextBoundsParams: ({ Width: number }) -> GetTextBoundsParams }).GetTextBoundsParams
	)({ Width = 0 })
	local text = if revision then nil else ctx.observe.Text(label)
	local rich = if revision then nil else ctx.observe.RichText(label)
	local font = if revision then nil else ctx.observeStyled.FontFace(label)
	local points = if revision then nil else ctx.observeStyled.TextSize(label)
	local serial, alive = 0, true
	local last: string? = nil
	local metrics, widest, tallest, heldLength = "", 0, 0, -1
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
	Compose.watch(function(use: ComposeTypes.Use)
		if revision then
			use(revision)
		end
		local words = if text then use(text) else label.Text
		local markup = if rich then use(rich) else label.RichText
		local face = if font then use(font) else label:GetStyled("FontFace") :: Font
		local size = if points then use(points) else label:GetStyled("TextSize") :: number
		local geometry =
			`{face.Family}|{face.Weight.Name}|{face.Style.Name}|{size}|{markup}|{label.AutomaticSize.Name}|{label:GetStyled(
				"TextWrapped"
			)}|{label:GetStyled("TextTruncate")}|{label:GetStyled("LineHeight")}`
		local key = `{#words}:{words}|{geometry}`
		if key == last then
			return
		end
		last = key
		serial += 1
		local ticket = serial
		cancel()
		local completed = hold(label)
		release = completed
		params.Text, params.RichText, params.Font, params.Size = words, markup, face, size
		local function measure()
			local ok, value = pcall(function(): Vector2
				return service:GetTextBoundsAsync(params)
			end)
			if alive and ticket == serial then
				if ok then
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
		stable: boolean?
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
				return createNatural(ctx, label, nil, revision, stable), nil
			end)
			resources[label] = acquire
		end
		return assert(acquire)()
	end,
}
