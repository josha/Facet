--!strict
local Types = require("./types")
local ComposeTypes = require("../vendor/compose/core")
local reducedMotion = require("./motion")

local PAUSE, GLYPHS_PER_SECOND, SLACK = 1.2, 3, 2

local moving = setmetatable({} :: { [Types.Context]: TextLabel? }, { __mode = "k" })

return function(ctx: Types.Context, label: TextLabel, plateShown: ComposeTypes.Readable<boolean>)
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local D2 = ctx.types.UDim2
	local frames = runtime.host.frames
	if frames == nil then
		return
	end
	local reduced = reducedMotion(ctx)
	local fits, text = ctx.observe.TextFits(label), ctx.observe.Text(label)
	local travel = Compose.cell(0)
	local phase, clock = "rest", 0
	local seconds: number? = nil
	local unmount: (() -> ())? = nil
	local stopFrames: (() -> ())? = nil
	local function release()
		if unmount then
			unmount()
			unmount = nil
		end
		if moving[ctx] == label then
			moving[ctx] = nil
		end
		seconds = nil
	end
	local function strip(): { Instance }
		local full = ctx.text({
			Name = "Full",
			Text = function(use: ComposeTypes.Use): string
				return use(text)
			end,
			Size = D2.fromScale(0, 1),
			AutomaticSize = ctx.types.Enum.AutomaticSize.X,
			TextYAlignment = label.TextYAlignment,
			RichText = label.RichText,
		})
		for _, tag in label:GetTags() do
			full:AddTag(tag)
		end
		local bounds = ctx.observe.TextBounds(label)
		local window = Host.Frame "Reveal" {
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Size = function(use: ComposeTypes.Use): UDim2
				return D2.new(1, 0, 0, use(bounds).Y)
			end,
			full,
		}
		local room, width = ctx.observe.AbsoluteSize(window), ctx.observe.AbsoluteSize(full)
		runtime.decorate(full, {
			Position = function(use: ComposeTypes.Use): UDim2
				local inside = use(room).X
				local over = math.max(0, use(width).X - inside)
				over += if over > 0 then SLACK else 0
				return D2.fromScale(if inside > 0 then -over / inside * use(travel) else 0, 0)
			end,
		})
		Compose.watch(function(use: ComposeTypes.Use)
			local inside, whole = use(room).X, use(width).X
			local glyphs = utf8.len(use(text)) or 0
			seconds = if whole > 0 then math.max(0, whole - inside) / whole * glyphs / GLYPHS_PER_SECOND else nil
		end)
		return { window, Host.UIGradient "RevealHold" { Transparency = ctx.types.NumberSequence.new(1) } }
	end
	local function step(delta: number)
		clock += delta
		if phase == "rest" then
			if clock >= PAUSE and moving[ctx] == nil then
				moving[ctx] = label
				unmount = runtime.mountFragment(strip, label)
				phase, clock = "out", 0
			end
		elseif phase == "end" then
			if clock >= PAUSE then
				phase, clock = "back", 0
			end
		elseif seconds == nil then
			clock = 0
		else
			local total = seconds :: number
			local progress = if total > 0 then math.min(1, clock / total) else 1
			travel:set(if phase == "out" then progress else 1 - progress)
			if progress >= 1 then
				if phase == "back" then
					release()
				end
				phase, clock = if phase == "out" then "end" else "rest", 0
			end
		end
	end
	local function reset()
		if stopFrames then
			stopFrames()
			stopFrames = nil
		end
		release()
		phase, clock = "rest", 0
		travel:set(0)
	end
	Compose.watch(function(use: ComposeTypes.Use)
		use(text)
		local active = not use(fits) and not reduced(use) and not use(plateShown)
		reset()
		if active then
			stopFrames = frames.onFrame(step)
		end
	end)
	Compose.cleanup(reset)
end
