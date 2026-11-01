--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local motion = require("./motion")
local fontReadiness = require("./font_readiness")
local arrival = require("./overlay_arrival")
local textMeasure = require("./text_measure")
type Departure = { exit: ({ ComposeTypes.Node }) -> ComposeTypes.Exiting }

export type Presence = {
	appearance: (Nav.PresencePhase?, Nav.MotionTiming, ComposeTypes.ReadOnlyValue<boolean>?) -> Nav.Presence,
	atRest: (
		Nav.Appearance,
		ComposeTypes.Value<boolean>,
		{ GuiObject },
		((ComposeTypes.Use) -> string)?
	) -> ({ ComposeTypes.ReadOnlyValue<Vector2> }, ComposeTypes.ReadOnlyValue<boolean>),
	departure: (Nav.MotionTiming, GuiObject, () -> boolean) -> Departure,
}

return function(ctx: Types.Context): Presence
	local Compose, runtime = ctx.Compose, ctx.runtime
	local function appearance(
		phase: Nav.PresencePhase?,
		timing: Nav.MotionTiming,
		ready: ComposeTypes.ReadOnlyValue<boolean>?
	): Nav.Presence
		local level = motion.level(ctx)
		local arrivalReady = arrival.ready(phase)
		local function placed(use: ComposeTypes.Use?): boolean
			return (ready == nil or ctx.readSource(ready, use))
				and (arrivalReady == nil or ctx.readSource(arrivalReady, use))
		end
		local exiting: ComposeTypes.ReadOnlyValue<boolean> = if phase then phase.exiting else Compose.cell(false)
		local shown = Compose.cell(false)
		local fadeIn, fadeOut = ctx.metric("motion.presentFadeIn"), ctx.metric("motion.presentFadeOut")
		local present, fade = ctx.motionEase("present"), ctx.motionEase("fade")
		local progress = runtime.tween(function(use: ComposeTypes.Use): number
			return if use(exiting) or not use(shown) or not placed(use) then 0 else 1
		end, {
			seconds = function(_: ComposeTypes.Use): number
				if level() == "limited" then
					return ctx.metric("motion.reducedFade")
				end
				return if exiting:peek() then timing.exit else timing.enter
			end,
			ease = function(t: number): number
				return if level() == "limited" then fade(t) else present(t)
			end,
		})
		shown:set(true)
		local function raw(use: ComposeTypes.Use?): number
			if not placed(use) then
				return 0
			end
			return if level(use) == "none" then 1 else ctx.readSource(progress, use)
		end
		local function travel(use: ComposeTypes.Use?): number
			if not placed(use) then
				return 0
			end
			return if level(use) == "normal" then ctx.readSource(progress, use) else 1
		end
		local last = 0
		type Anchor = { p: number, o: number }
		local anchor = Compose.cell<<Anchor>>({ p = 0, o = 0 })
		local function opacity(use: ComposeTypes.Use?): number
			local p = raw(use)
			if level(use) ~= "normal" then
				last = p
				return p
			end
			local from: Anchor = if use then use(anchor) else anchor:peek()
			local value
			if ctx.read(exiting, use) then
				local cleared = 1 - present(fadeOut)
				value = if from.p > cleared
					then from.o * math.clamp((p - cleared) / (from.p - cleared), 0, 1)
					elseif from.p > 0 then from.o * math.clamp(p / from.p, 0, 1)
					else 0
			else
				local opaque = math.max(present(fadeIn), from.p + 1e-3)
				value = from.o + (1 - from.o) * math.clamp((p - from.p) / (opaque - from.p), 0, 1)
			end
			last = value
			return value
		end
		Compose.watch(function(use: ComposeTypes.Use)
			use(exiting)
			anchor:set({ p = raw(), o = last })
		end)
		return { opacity = opacity, travel = travel }
	end
	local function atRest(
		amount: Nav.Appearance,
		ready: ComposeTypes.Value<boolean>,
		nodes: { GuiObject },
		restart: ((ComposeTypes.Use) -> string)?
	): ({ ComposeTypes.ReadOnlyValue<Vector2> }, ComposeTypes.ReadOnlyValue<boolean>)
		local live: { ComposeTypes.ReadOnlyValue<Vector2> } = {}
		for index, node in nodes do
			live[index] = ctx.observeNative.AbsoluteSize(node)
		end
		local fontsReady = fontReadiness(ctx, nodes)
		local sampled: { Vector2 } = {}
		local snapshot, complete = "", false
		local allowed: boolean? = nil
		local rested = ctx.runtime.settled {
			sample = function(): string
				return snapshot
			end,
			ready = function(): boolean
				local parts: { string } = {}
				local filled = false
				local measured = true
				local origin = nodes[1].AbsolutePosition
				local descendants = nodes[1]:GetDescendants()
				for index, node in nodes do
					table.insert(descendants, node)
					local size = node.AbsoluteSize
					sampled[index] = size
					filled = filled or (size.X > 0 and size.Y > 0)
				end
				for _, node in descendants do
					measured = measured and not textMeasure.pending(node)
					if node:IsA("GuiObject") then
						local value = `{node.AbsolutePosition - origin}:{node.AbsoluteSize}:{node.Visible}`
						if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
							value ..= `:{node.TextBounds}`
						end
						table.insert(parts, value)
					end
				end
				snapshot, complete, allowed =
					table.concat(parts, ";"), filled, nodes[1].Visible and fontsReady() and measured
				return allowed ~= false
			end,
			equals = function(a: string, b: string): boolean
				return complete and a == b
			end,
			restart = restart,
			timeout = ctx.metric("motion.restLimit"),
		}
		local held: { ComposeTypes.ReadOnlyValue<Vector2> } = {}
		local naturalSizes: { ComposeTypes.Value<Vector2> } = {}
		for index, size in live do
			local natural = Compose.cell(size:peek())
			naturalSizes[index] = natural
			held[index] = natural
			Compose.watch(function(use: ComposeTypes.Use)
				local value = use(size)
				local resting = use(rested)
				if not resting or amount() >= 1 then
					natural:set(if resting then nodes[index].AbsoluteSize else value)
				end
			end)
		end
		Compose.watch(function(use: ComposeTypes.Use)
			if use(rested) then
				for index, natural in naturalSizes do
					natural:set(sampled[index])
				end
				ready:set(true)
			end
		end)
		return held, rested
	end
	local function attached(anchor: GuiObject): boolean
		local at: Instance? = anchor
		while at do
			if at:IsA("GuiObject") and not at.Visible then
				return false
			end
			if at:IsA("LayerCollector") then
				return at.Enabled
			end
			at = at.Parent
		end
		return false
	end
	local function departure(timing: Nav.MotionTiming, anchor: GuiObject, shown: () -> boolean): Departure
		local level = motion.level(ctx)
		local scheduler = runtime.scheduler()
		return {
			exit = function(_nodes: { ComposeTypes.Node })
				local current = level()
				if not shown() or not attached(anchor) or current == "none" then
					scheduler.cancel("exit")
					return { completed = Compose.cell(true) }
				end
				local completed = Compose.cell(false)
				scheduler.replace(
					"exit",
					if current == "limited" then ctx.metric("motion.reducedFade") else timing.exit,
					function()
						completed:set(true)
					end
				)
				return { completed = completed }
			end,
		}
	end
	return { appearance = appearance, atRest = atRest, departure = departure }
end
