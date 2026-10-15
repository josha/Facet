--!strict
local Types = require("./types")
local ComposeTypes = require("../vendor/compose/core")

local pending = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [Instance]: number }

local function begin(node: Instance): () -> ()
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
	[Instance]: ComposeTypes.AcquireSharedResource<ComposeTypes.Readable<Vector2>>,
}

local function createNatural(
	ctx: Types.Context,
	label: TextLabel | TextButton | TextBox,
	fallback: (() -> ComposeTypes.Readable<Vector2>)?,
	revision: ComposeTypes.Cell<number>?
): ComposeTypes.Readable<Vector2>
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
	local thread: thread? = nil
	local function cancel()
		if thread and coroutine.status(thread) == "suspended" and task then
			pcall(task.cancel, thread)
		end
		thread = nil
	end
	Compose.cleanup(function()
		alive = false
		cancel()
		completed()
	end)
	Compose.watch(function(use: ComposeTypes.Use)
		if revision then
			use(revision)
		end
		local words = if text then use(text) else label.Text
		local markup = if rich then use(rich) else label.RichText
		local face = if font then use(font) else label:GetStyled("FontFace") :: Font
		local size = if points then use(points) else label:GetStyled("TextSize") :: number
		local key = `{#words}:{words}|{markup}|{face.Family}|{face.Weight.Name}|{face.Style.Name}|{size}`
		if key == last then
			return
		end
		last = key
		serial += 1
		local ticket = serial
		cancel()
		local completed = begin(label)
		release = completed
		if revision then
			bounds:set(ctx.types.Vector2.new(math.huge, 0))
		end
		params.Text, params.RichText, params.Font, params.Size = words, markup, face, size
		local function measure()
			local ok, value = pcall(function(): Vector2
				return service:GetTextBoundsAsync(params)
			end)
			if alive and ticket == serial then
				if ok then
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
	begin = begin,
	natural = function(
		ctx: Types.Context,
		label: TextLabel | TextButton | TextBox,
		fallback: (() -> ComposeTypes.Readable<Vector2>)?,
		revision: ComposeTypes.Cell<number>?
	): ComposeTypes.Readable<Vector2>
		if ctx.config.services.TextService == nil then
			return if fallback then fallback() else ctx.Compose.cell(ctx.types.Vector2.new(math.huge, 0))
		end
		local acquire = shared[label]
		if not acquire then
			acquire = ctx.Compose.createSharedResource(function()
				ctx.Compose.cleanup(function()
					shared[label] = nil
				end)
				return createNatural(ctx, label, nil, revision)
			end)
			shared[label] = acquire
		end
		return acquire()
	end,
	ready = function(node: Instance): boolean
		if pending[node] ~= nil then
			return false
		end
		if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
			local automatic = node.AutomaticSize.Name
			if
				node.Text ~= ""
				and node.TextWrapped
				and node.TextTruncate.Name == "None"
				and (automatic == "Y" or automatic == "XY")
			then
				return node.TextFits
			end
		end
		return true
	end,
}
