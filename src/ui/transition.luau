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
	scale: Types.ReadOnlyValue<number>?,
	apply: (GuiObject, GuiObject?) -> (),
}

local function check(spec: Nav.Transition | false?)
	if spec == nil or spec == false then
		return
	end
	assert(type(spec) == "table", "Facet transition must be a table or false")
	for key in spec do
		assert(
			table.find({ "seconds", "ease", "motion", "fade", "progress", "apply", "scale" }, tostring(key)),
			"Unknown Facet transition option: " .. tostring(key)
		)
	end
	assert(spec.apply == nil or type(spec.apply) == "function", "Transition.apply must be a function")
	assert(spec.fade == nil or type(spec.fade) == "boolean", "Transition.fade must be a boolean")
	assert(
		spec.scale == nil
			or spec.scale == true
			or type(spec.scale) == "number" and spec.scale > 0 and spec.scale < math.huge,
		"Transition.scale must be true or a positive finite number"
	)
	assert(spec.scale == nil or spec.apply == nil, "Transition.scale and Transition.apply cannot be combined")
end

local function create(
	ctx: Types.Context,
	spec: Nav.Transition,
	presented: Types.ReadOnlyValue<boolean>,
	immediate: boolean?,
	ready: Types.ReadOnlyValue<boolean>?,
	disabled: boolean?,
	targetPresented: Types.ReadOnlyValue<boolean>?,
	holdOnExit: boolean?
): Motion
	check(spec)
	local C, runtime = ctx.Compose, ctx.runtime
	local zooms = spec.scale ~= nil
	local shaped = zooms and spec.ease == nil
	local preset = if zooms and spec.motion == nil then "zoomPresent" else spec.motion or "tabFade"
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
				else ctx.metric("motion.durations." .. preset, use)
		end,
		ease = spec.ease or if shaped then C.easing.linear else ctx.motionEase("fade"),
	})
	local function shape(role: string, value: number, use: Types.Use): number
		return if shaped and not use(interacting) then ctx.motionEase(role, use)(value) else value
	end
	local opacity = C.formula(function(use: Types.Use): number
		return if disabled or level(use) == "none" then use(target) else shape("zoomFade", use(amount), use)
	end)
	local function animates(use: Types.Use): boolean
		return not disabled and level(use) == "normal" and (ready == nil or use(ready))
	end
	local progress = C.formula(function(use: Types.Use): number
		return if animates(use) then use(opacity) else 1
	end)
	local scale: Types.ReadOnlyValue<number>? = nil
	local authored = spec.scale
	if authored ~= nil then
		local growth = C.formula(function(use: Types.Use): number
			return if animates(use) then shape("zoomScale", use(amount), use) else 1
		end)
		local function origin(use: Types.Use): number
			return if type(authored) == "number" then authored else ctx.metric("motion.materialize.zoom", use)
		end
		local zoomed = C.formula(function(use: Types.Use): number
			local from, grown = origin(use), use(growth)
			return if grown >= 1 then 1 else from + (1 - from) * grown
		end)
		if holdOnExit then
			local departing: Types.Value<number?> = C.cell(nil :: number?)
			C.watch(function(use: Types.Use)
				if use(presented) then
					departing:set(nil)
				elseif departing:peek() == nil then
					departing:set(zoomed:peek())
				end
			end)
			scale = C.formula(function(use: Types.Use): number
				local kept = use(departing)
				return if kept ~= nil then kept else use(zoomed)
			end)
		else
			scale = zoomed
		end
	end
	return {
		interacting = interacting,
		scale = scale,
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
