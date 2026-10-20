--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local motion = require("./motion")
local completions = setmetatable({} :: { [Nav.PresencePhase]: Types.Readable<boolean> }, { __mode = "k" })

export type Motion = {
	progress: Types.Readable<number>,
	opacity: Types.Readable<number>,
	completed: Types.Readable<boolean>,
	visible: Types.Readable<boolean>,
	apply: (GuiObject, GuiObject?) -> (),
}

local function check(spec: Nav.Transition | false?)
	if spec == nil or spec == false then
		return
	end
	assert(type(spec) == "table", "Facet transition must be a table or false")
	for key in spec do
		assert(
			table.find({ "seconds", "ease", "motion", "apply" }, tostring(key)),
			"Unknown Facet transition option: " .. tostring(key)
		)
	end
	assert(spec.apply == nil or type(spec.apply) == "function", "Transition.apply must be a function")
end

local function create(
	ctx: Types.Context,
	spec: Nav.Transition,
	presented: Types.Readable<boolean>,
	immediate: boolean?,
	ready: Types.Readable<boolean>?,
	disabled: boolean?
): Motion
	check(spec)
	local C, runtime = ctx.Compose, ctx.runtime
	local level = motion.level(ctx)
	local mounted = C.cell(immediate == true)
	local target = C.formula(function(use: Types.Use): number
		return if use(presented) and (immediate or use(mounted)) and (ready == nil or use(ready)) then 1 else 0
	end)
	local amount = runtime.tween(function(use: Types.Use): number
		return use(target)
	end, {
		seconds = function(use: Types.Use): number
			if level(use) == "limited" then
				return ctx.metric("motion.reducedFade", use)
			end
			return if spec.seconds ~= nil
				then ctx.read(spec.seconds, use)
				else ctx.metric("motion.durations." .. (spec.motion or "tabFade"), use)
		end,
		ease = spec.ease or ctx.motionEase("fade"),
	})
	local opacity = C.formula(function(use: Types.Use): number
		return if disabled or level(use) == "none" then use(target) else use(amount)
	end)
	local progress = C.formula(function(use: Types.Use): number
		return if not disabled and level(use) == "normal" and (ready == nil or use(ready)) then use(opacity) else 1
	end)
	return {
		progress = progress,
		opacity = opacity,
		completed = C.formula(function(use: Types.Use): boolean
			return not use(presented) and use(opacity) == 0
		end),
		visible = C.formula(function(use: Types.Use): boolean
			return use(presented) or use(opacity) > 0
		end),
		apply = function(node: GuiObject, container: GuiObject?)
			if spec.apply then
				spec.apply(node, { progress = progress, isPresented = presented })
			end
			local parent = ctx.observe.Parent(container or node)
			C.watch(function(use: Types.Use)
				mounted:set(use(parent) ~= nil)
			end)
		end,
	}
end

return { check = check, create = create, completions = completions }
