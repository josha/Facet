--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local motionLevels = require("./motion")

export type SurfaceParts = {
	body: (Nav.Content) -> Instance,
	empty: (Types.FrameProps, { string }, string) -> Frame,
	revealMotion: (
		ComposeTypes.Cell<boolean>
	) -> ((ComposeTypes.Use?) -> number, ComposeTypes.Readable<boolean>, (ComposeTypes.Use) -> number),
	unroll: (
		(ComposeTypes.Use?) -> number,
		ComposeTypes.Readable<Vector2>
	) -> ((ComposeTypes.Use) -> Enum.AutomaticSize, (ComposeTypes.Use) -> number?),
}

return function(ctx: Types.Context): SurfaceParts
	local Host, runtime, read = ctx.Host, ctx.runtime, ctx.read
	local E, D2 = ctx.types.Enum, ctx.types.UDim2
	local function body(content: Nav.Content): Instance
		return if type(content) == "function" then content() else content
	end
	local function empty(spec: Types.FrameProps, keys: { string }, name: string): Frame
		return Host.Frame(
			ctx.props(spec, keys, { Name = name, BackgroundTransparency = 1, Size = D2.fromOffset(0, 0) })
		)
	end
	local function revealMotion(expanded: ComposeTypes.Cell<boolean>): ((ComposeTypes.Use?) -> number, ComposeTypes.Readable<boolean>, (
		ComposeTypes.Use
	) -> number)
		local level = motionLevels.level(ctx)
		local reveal, fade = ctx.motionTiming("reveal"), ctx.motionEase("fade")
		local function motion(
			share: (ComposeTypes.Use) -> number,
			ease: ComposeTypes.Easing?,
			fades: boolean
		): (ComposeTypes.Use?) -> number
			local value = runtime.tween(function(use: ComposeTypes.Use): number
				return if use(expanded) then 1 else 0
			end, {
				seconds = function(use: ComposeTypes.Use): number
					if fades and level() == "limited" then
						return ctx.metric("motion.reducedFade", use)
					end
					return share(use) * (if expanded:peek() then reveal.enter else reveal.exit)
				end,
				ease = ease,
			})
			return function(use: ComposeTypes.Use?): number
				local current = level(use)
				if current == "none" or (current == "limited" and not fades) then
					return if read(expanded, use) then 1 else 0
				end
				return read(value, use)
			end
		end
		local progress, opacity =
			motion(function()
				return 1
			end, ctx.motionEase("present"), false), motion(function(use: ComposeTypes.Use): number
				return ctx.metric("motion.revealFadeShare", use)
			end, function(t: number): number
				return if level() == "limited" then fade(t) else t
			end, true)
		return progress,
			ctx.Compose.formula(function(use: ComposeTypes.Use): boolean
				return progress(use) <= 0
			end),
			function(use: ComposeTypes.Use): number
				return 1 - opacity(use)
			end
	end
	local function unroll(progress: (ComposeTypes.Use?) -> number, natural: ComposeTypes.Readable<Vector2>)
		return function(use: ComposeTypes.Use): Enum.AutomaticSize
			return if progress(use) >= 1 then E.AutomaticSize.Y else E.AutomaticSize.None
		end, function(use: ComposeTypes.Use): number?
			local amount = progress(use)
			return if amount >= 1 then nil else math.floor(use(natural).Y * amount + 0.5)
		end
	end
	return { body = body, empty = empty, revealMotion = revealMotion, unroll = unroll }
end
