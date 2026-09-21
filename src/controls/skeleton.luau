--!strict
-- Loading silhouettes share one decorative clock entry and two dimension
-- tables per frame per clock. Render hooks count mounted sweeps, not visible pixels.
local Compose = require("../vendor/compose/core")
local guard = require("../spec_guard")
local selection = require("../selection_model")
local surfaceEnv = require("../env/surface_env")
local vocabulary = require("./control_vocabulary")
local specTypes = require("../spec_types/skeleton")
export type Spec = specTypes.Spec
local skeleton = {}
local KEYS = guard.keySet({ "id", "form", "width", "height", "lines", "corners", "controlSize" })
local FORMS = guard.keySet({ "box", "line", "circle" })
local FILL = table.freeze({ type = "fill", weight = 1 })
local PLATE = table.freeze({ role = "control", blend = 1 })
local BAND = table.freeze({ role = "contentSecondary", blend = 1, transparency = 0.85 })
local drivers: { [any]: any } = {}
local function triangle(phase)
	return if phase <= 0.5 then phase * 2 else (1 - phase) * 2
end
function skeleton.liveDrivers(): number
	local count = 0
	for _ in drivers do
		count += 1
	end
	return count
end
local function start(driver)
	driver.phase:snap(0)
	driver.phase:setTarget(1)
end
local function hold(clock, reactor)
	local driver = drivers[clock]
	if not driver then
		-- Independent of the first acquiring branch: another branch may outlive it.
		local owner = Compose.createOwner(reactor)
		local ok, result = pcall(Compose.withOwner, owner, function()
			local phase = clock:glide(0, { duration = 1.2, kind = "decorative" })
			Compose.cleanup(function()
				phase:dispose()
			end)
			local entry = { owner = owner, clock = clock, phase = phase, refs = 0, visible = 0 }
			entry.lead = Compose.formula(function(use)
				return { type = "percent", fraction = triangle(use(phase)) * 0.65 }
			end)
			entry.trail = Compose.formula(function(use)
				return { type = "percent", fraction = (1 - triangle(use(phase))) * 0.65 }
			end)
			Compose.cleanup(phase:onSettle(function()
				if drivers[clock] == entry and entry.visible > 0 and not clock:isReduced() then
					start(entry)
				end
			end))
			return entry
		end)
		if not ok then
			owner.dispose()
			error(result, 0)
		end
		driver = result
		drivers[clock] = driver
	end
	driver.refs += 1
	return driver
end
local function release(driver: any)
	if drivers[driver.clock] ~= driver then
		return
	end
	driver.refs -= 1
	if driver.refs == 0 then
		drivers[driver.clock] = nil
		driver.visible = 0
		driver.owner.dispose()
	end
end
local function build(library, core, spec, owner)
	guard.assertKnownKeys("UI.Skeleton", spec, KEYS, "spec")
	local UI, id = library.UI, spec.id or "Skeleton"
	local form = spec.form
	assert(FORMS[form] == true, "Facet UI.Skeleton: form must be box | line | circle")
	if spec.lines ~= nil then
		assert(form == "line", "Facet UI.Skeleton: lines belongs to form line")
		assert(
			type(spec.lines) == "number" and spec.lines >= 1 and spec.lines % 1 == 0,
			"Facet UI.Skeleton: lines must be a positive whole number"
		)
	end
	assert(
		form ~= "circle" or (spec.height == nil and spec.corners == nil),
		"Facet UI.Skeleton: circle takes width alone, without height or corners"
	)
	vocabulary.assertCorners("UI.Skeleton", spec.corners)
	vocabulary.assertSize("UI.Skeleton", spec.controlSize)
	local function rungDim(rung)
		return {
			type = "fixed",
			px = vocabulary.metricPath(rung or "regular", if form == "line" then "iconSize" else "height"),
		}
	end
	local sized = vocabulary.deriveSize("UI.Skeleton", spec.controlSize, rungDim) or rungDim("regular")
	local env = surfaceEnv.find(core)
	local clock = if library.presenter then library.presenter.motionClock else nil
	local driver, sweeping
	local shown, released = 0, false
	if env and clock then
		sweeping = Compose.formula(function(use)
			return use(env:get("motionPolicy")) ~= "reduced"
		end)
		driver = hold(clock, owner.reactor)
		Compose.cleanup(function()
			released = true
			-- A build can be disposed before render disappearance callbacks run.
			driver.visible = math.max(0, driver.visible - shown)
			shown = 0
			if driver.visible == 0 then
				driver.phase:snap(0)
			end
			release(driver)
		end)
	end
	local function appear()
		if released then
			return
		end
		shown += 1
		driver.visible += 1
		if driver.visible == 1 then
			start(driver)
		end
	end
	local function disappear()
		if released then
			return
		end
		shown -= 1
		driver.visible -= 1
		if driver.visible == 0 then
			driver.phase:snap(0)
		end
	end
	local radius = if spec.corners
		then vocabulary.cornerRadiusFor(spec.corners)
		elseif form == "box" then "control"
		else "pill"
	local function plate(plateId, width, height)
		local children = { UI.corners(UI.Box({ id = "Plate", width = FILL, height = FILL, tint = PLATE }), radius) }
		if driver then
			table.insert(
				children,
				UI.When({
					id = "Shimmer",
					condition = sweeping,
					thenView = function()
						-- Fill absorbs independent percent rounding; the band cannot overrun.
						local sweep = UI.HStack({
							id = "Sweep",
							width = FILL,
							height = FILL,
							onAppear = appear,
							onDisappear = disappear,
							children = {
								UI.Spacer({ id = "Lead", width = driver.lead, height = FILL }),
								UI.corners(UI.Box({ id = "Band", tint = BAND, width = FILL, height = FILL }), radius),
								UI.Spacer({ id = "Trail", width = driver.trail, height = FILL }),
							},
						})
						-- Rounded sibling paint is not a mask. The native CanvasGroup
						-- clips the moving band to this circle; reduced motion owns none.
						return if form == "circle"
							then UI.corners(
								UI.ZStack({
									id = "Mask",
									width = FILL,
									height = FILL,
									canvasGroup = true,
									children = { sweep },
								}),
								"pill"
							)
							else sweep
					end,
				})
			)
		end
		return UI.ZStack({ id = plateId, width = width, height = height, children = children })
	end
	local blueprint
	if form == "line" and (spec.lines or 1) > 1 then
		local bars = {}
		local width = spec.width or UI.fill()
		for index = 1, spec.lines do
			table.insert(
				bars,
				plate(
					`Line{index}`,
					if index == spec.lines then { type = "percent", fraction = 0.6 } else FILL,
					spec.height or sized
				)
			)
		end
		blueprint = UI.VStack({ id = id, width = width, gap = "s", children = bars })
	elseif form == "circle" then
		local diameter = spec.width or sized
		blueprint = plate(id, diameter, { type = "aspect", ratio = 1 })
	else
		blueprint = plate(id, spec.width or UI.fill(), spec.height or sized)
	end
	local function dump()
		return {
			schema = "facet-skeleton-dump/1",
			id = id,
			form = form,
			lines = if form == "line" then spec.lines or 1 else nil,
			corners = spec.corners,
			controlSize = selection.read(spec.controlSize),
			animating = shown > 0,
			reducedMotion = if sweeping then not sweeping:peek() else nil,
		}
	end
	return { blueprint = blueprint, dispose = owner.dispose, dump = dump }
end
function skeleton.build(library: any, core: any, spec: Spec)
	local parent = Compose.currentOwner()
	local owner = if parent then parent.createChild() else Compose.createOwner(core.scene.reactor)
	local ok, result = pcall(Compose.withOwner, owner, function()
		return build(library, core, spec, owner)
	end)
	if not ok then
		owner.dispose()
		error(result, 0)
	end
	return result
end
return skeleton
