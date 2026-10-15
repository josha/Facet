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

local function natural(ctx: Types.Context, label: TextLabel): ComposeTypes.Readable<Vector2>
	local Compose, Host = ctx.Compose, ctx.Host
	local service = ctx.config.services.TextService
	local bounds = Compose.cell(ctx.types.Vector2.new(math.huge, 0))
	if service == nil then
		return bounds
	end
	local params = (
		((Host :: unknown) :: { GetTextBoundsParams: ({ Width: number }) -> GetTextBoundsParams }).GetTextBoundsParams
	)({ Width = 0 })
	local text, rich = ctx.observe.Text(label), ctx.observe.RichText(label)
	local font, points = ctx.observeStyled.FontFace(label), ctx.observeStyled.TextSize(label)
	local serial, alive = 0, true
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
		local words, markup, face, size = use(text), use(rich), use(font), use(points)
		serial += 1
		local ticket = serial
		cancel()
		local completed = begin(label)
		release = completed
		params.Text, params.RichText, params.Font, params.Size = words, markup, face, size
		local function measure()
			local ok, value = pcall(function(): Vector2
				return service:GetTextBoundsAsync(params)
			end)
			if alive and ticket == serial then
				if ok then
					bounds:set(value)
				end
			end
			completed()
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
	natural = natural,
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
