--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local motion = require("./motion")
local completions = setmetatable({} :: { [Nav.PresencePhase]: Types.ReadOnlyValue<boolean> }, { __mode = "k" })

export type Motion = {
	progress: Types.ReadOnlyValue<number>,
	opacity: Types.ReadOnlyValue<number>,
	transparency: Types.ReadOnlyValue<number>,
	completed: Types.ReadOnlyValue<boolean>,
	visible: Types.ReadOnlyValue<boolean>,
	interacting: Types.ReadOnlyValue<boolean>,
	apply: (GuiObject, GuiObject?) -> (),
}

local function check(spec: Nav.Transition | false?)
	if spec == nil or spec == false then
		return
	end
	assert(type(spec) == "table", "Facet transition must be a table or false")
	for key in spec do
		assert(
			table.find({ "seconds", "ease", "motion", "fade", "progress", "apply" }, tostring(key)),
			"Unknown Facet transition option: " .. tostring(key)
		)
	end
	assert(spec.apply == nil or type(spec.apply) == "function", "Transition.apply must be a function")
	assert(spec.fade == nil or type(spec.fade) == "boolean", "Transition.fade must be a boolean")
end

local function create(
	ctx: Types.Context,
	spec: Nav.Transition,
	presented: Types.ReadOnlyValue<boolean>,
	immediate: boolean?,
	ready: Types.ReadOnlyValue<boolean>?,
	disabled: boolean?,
	targetPresented: Types.ReadOnlyValue<boolean>?
): Motion
	check(spec)
	local C, runtime = ctx.Compose, ctx.runtime
	local level = motion.level(ctx)
	local mounted = C.cell(immediate == true)
	local held = C.formula(function(use: Types.Use): number?
		local value = if spec.progress then use(spec.progress) else nil
		assert(value == nil or (value >= 0 and value <= 1), "Transition.progress must be nil or a number from 0 to 1")
		return value
	end)
	local interacting = C.formula(function(use: Types.Use): boolean
		return use(held) ~= nil
	end)
	local target = C.formula(function(use: Types.Use): number
		return if use(targetPresented or presented)
				and (immediate or use(mounted))
				and (ready == nil or use(ready))
			then 1
			else 0
	end)
	local amount = runtime.tween(function(use: Types.Use): number
		local value = use(held)
		if value ~= nil and level(use) == "normal" and (ready == nil or use(ready)) then
			return if use(presented) then value else 1 - value
		end
		return use(target)
	end, {
		reducedMotion = C.formula(function(use: Types.Use): boolean
			return use(interacting) and level(use) == "normal"
		end),
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
		interacting = interacting,
		progress = progress,
		opacity = opacity,
		transparency = C.formula(function(use: Types.Use): number
			local alpha = use(opacity)
			return if spec.fade == false and level(use) == "normal" and alpha > 0 then 0 else 1 - alpha
		end),
		completed = C.formula(function(use: Types.Use): boolean
			return not use(interacting) and not use(presented) and use(opacity) == 0
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
