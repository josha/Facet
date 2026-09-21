--!strict
-- Passive shape, palette pair and optional count. All readers share one checked
-- answer; a refused source value never splits the mounted paint from its ref.
local Compose = require("../vendor/compose/core")
local guard = require("../spec_guard")
local selection = require("../selection_model")
local vocabulary = require("./control_vocabulary")
local specTypes = require("../spec_types/status_indicator")
export type Spec = specTypes.Spec
local status_indicator = {}
local KEYS =
	guard.keySet({ "id", "form", "status", "count", "max", "cutout", "name", "controlSize", "width", "height" })
local FORMS = guard.keySet({ "dot", "ring", "square", "dash" })
status_indicator.STATUSES = table.freeze({ "neutral", "info", "success", "warning", "error", "accent" })
status_indicator.STATUS_SET = guard.keySet(status_indicator.STATUSES)
local PLATE = {
	neutral = "contentSecondary",
	info = "accent",
	success = "accent",
	warning = "content",
	error = "danger",
	accent = "accent",
}
local ON = {
	neutral = "surface",
	info = "onAccent",
	success = "onAccent",
	warning = "surface",
	error = "onDanger",
	accent = "onAccent",
}
local FILL = table.freeze({ type = "fill", weight = 1 })
local ROUND_HEIGHT = table.freeze({ type = "aspect", ratio = 1 })
-- Percent dimensions round to the nearest pixel; subtracting half a pixel
-- floors the offered axis so an aspect-paired circle stays inside fractional offers.
local ROUND_AXIS = table.freeze({ type = "percent", fraction = 1, offset = -0.5 })
local ZERO = table.freeze({ type = "fixed", px = 0 })
local SURFACE = table.freeze({ role = "surface", blend = 1 })
local GUTTER = table.freeze({ type = "percent", fraction = 0.1, max = "strokes.hairline" })
local INSET = table.freeze({
	left = "strokes.hairline",
	right = "strokes.hairline",
	top = "strokes.hairline",
	bottom = "strokes.hairline",
})
function status_indicator.paintRoles(word: string): (string, string)
	return PLATE[word], ON[word]
end
function status_indicator.countText(count: number, max: number): string
	return if count > max then `{max}+` else `{count}`
end
local function whole(value, minimum)
	return type(value) == "number" and value >= minimum and value < math.huge and value % 1 == 0
end
local function build(library: any, _core: any, spec: any, owner: any)
	guard.assertKnownKeys("UI.StatusIndicator", spec, KEYS, "spec")
	local UI, id = library.UI, spec.id or "StatusIndicator"
	local counted, cap = spec.count ~= nil, spec.max or 99
	assert(
		spec.max == nil or (counted and whole(spec.max, 1)),
		"Facet StatusIndicator: max requires count and must be a positive whole number"
	)
	assert(spec.cutout == nil or type(spec.cutout) == "boolean", "Facet StatusIndicator: cutout must be boolean")
	assert(
		spec.name == nil or (type(spec.name) == "string" and spec.name ~= ""),
		"Facet StatusIndicator: name must be a nonempty string"
	)
	local facts = Compose.formula(function(use)
		local form = selection.read(spec.form, use)
		local status = selection.read(spec.status, use)
		form = if form == nil then "dot" else form
		status = if status == nil then "neutral" else status
		local count = selection.read(spec.count, use)
		local rung = selection.read(spec.controlSize, use)
		assert(FORMS[form], "Facet StatusIndicator: form must be dot | ring | square | dash")
		assert(
			status_indicator.STATUS_SET[status],
			"Facet StatusIndicator: status must be neutral | info | success | warning | error | accent"
		)
		assert(not counted or whole(count, 0), "Facet StatusIndicator: count must be a finite whole number, 0 or more")
		assert(
			not counted or (form == "dot" or form == "square"),
			"Facet StatusIndicator: counted marks require dot or square form"
		)
		vocabulary.assertSize("StatusIndicator", rung)
		return {
			form = form,
			status = status,
			count = if counted then status_indicator.countText(count, cap) else nil,
			controlSize = rung,
		}
	end)
	facts:peek()
	local function field(key)
		return function(use)
			return use(facts)[key]
		end
	end
	local function size(use)
		return { type = "fixed", px = vocabulary.metricPath(use(facts).controlSize or "compact", "iconSize") }
	end
	local function corners(use)
		return UI.cornersData(if use(facts).form == "square" then 0 else "pill")
	end
	local function plateTint(use)
		return { role = PLATE[use(facts).status], blend = 1 }
	end
	-- Shape is construction-only. Each owned branch builds an actual circle or
	-- rectangle; theme pill radii cannot turn the circle into a rounded square.
	local function mark(name: string, tint)
		return UI.When({
			id = name .. "Shape",
			condition = function(use)
				return use(facts).form == "square"
			end,
			thenView = function()
				return UI.Box({ id = name, shape = "rect", width = FILL, height = FILL, tint = tint })
			end,
			elseView = function()
				return UI.Box({ id = name, shape = "circle", width = ROUND_AXIS, tint = tint })
			end,
		})
	end
	local function layers()
		local body
		if counted then
			body = UI.background(
				UI.ZStack({
					id = "Seal",
					padding = { left = "xs", right = "xs" },
					alignH = "center",
					alignV = "center",
					height = if spec.height ~= nil
						then FILL
						else function(use)
							return {
								type = "minMax",
								min = vocabulary.metricPath(use(facts).controlSize or "compact", "iconSize"),
							}
						end,
					children = {
						UI.Text({
							id = "Count",
							text = field("count"),
							textSize = "caption",
							textAlign = "center",
							lineLimit = 1,
							tint = function(use)
								return { role = ON[use(facts).status], blend = 1 }
							end,
						}),
					},
				}),
				UI.Box({ id = "Plate", tint = plateTint, corners = corners })
			)
		else
			local function detailDim(axis)
				return function(use)
					local form = use(facts).form
					return if form == "ring"
						then { type = "percent", fraction = 0.46 }
						elseif form == "dash" then {
							type = "percent",
							fraction = if axis == "w" then 0.62 else 0.22,
						}
						else ZERO
				end
			end
			local function detailTint(use)
				local form = use(facts).form
				return { role = "surface", blend = 1, transparency = if form == "ring" or form == "dash" then 0 else 1 }
			end
			body = UI.ZStack({
				id = "Body",
				width = FILL,
				height = FILL,
				children = {
					mark("Mark", plateTint),
					UI.ZStack({
						id = "DetailFrame",
						width = FILL,
						height = FILL,
						alignH = "center",
						alignV = "center",
						children = {
							UI.When({
								id = "DetailShape",
								condition = function(use)
									return use(facts).form == "ring"
								end,
								thenView = function()
									return UI.Box({
										id = "Detail",
										shape = "circle",
										width = detailDim("w"),
										tint = detailTint,
									})
								end,
								elseView = function()
									return UI.Box({
										id = "Detail",
										shape = "rect",
										width = detailDim("w"),
										height = detailDim("h"),
										tint = detailTint,
									})
								end,
							}),
						},
					}),
				},
			})
		end
		local children = { body }
		if spec.cutout then
			children = {
				if counted
					then UI.Box({ id = "Cutout", tint = SURFACE, corners = corners, width = FILL, height = FILL })
					else mark("Cutout", SURFACE),
				if counted
					then UI.ZStack({ id = "Inset", width = FILL, height = FILL, padding = INSET, children = { body } })
					else UI.HStack({
						id = "Inset",
						width = FILL,
						height = FILL,
						gap = 0,
						children = {
							UI.Spacer({ id = "Leading", width = GUTTER }),
							UI.VStack({
								id = "Center",
								width = FILL,
								height = FILL,
								gap = 0,
								children = {
									UI.Spacer({ id = "Top", height = GUTTER }),
									body,
									UI.Spacer({ id = "Bottom", height = GUTTER }),
								},
							}),
							UI.Spacer({ id = "Trailing", width = GUTTER }),
						},
					}),
			}
		end
		return children
	end
	local function roundCandidate(name, fromWidth)
		return UI.ZStack({
			id = name,
			width = FILL,
			height = FILL,
			alignH = "center",
			alignV = "center",
			children = {
				UI.ZStack({
					id = "Circle",
					width = if fromWidth then ROUND_AXIS else ROUND_HEIGHT,
					height = if fromWidth then ROUND_HEIGHT else ROUND_AXIS,
					children = layers(),
				}),
			},
		})
	end
	local children = if counted
		then layers()
		else {
			UI.When({
				id = "Footprint",
				condition = function(use)
					return use(facts).form == "square"
				end,
				thenView = function()
					return UI.ZStack({ id = "Rectangle", width = FILL, height = FILL, children = layers() })
				end,
				elseView = function()
					-- Two passive candidates share checked facts; only the fitting square paints.
					return UI.ViewThatFits({
						id = "Fit",
						width = FILL,
						height = FILL,
						children = { roundCandidate("FromWidth", true), roundCandidate("FromHeight", false) },
					})
				end,
			}),
		}
	local root = UI.ZStack({
		id = id,
		width = spec.width or (if counted then nil else size),
		height = spec.height or (if counted then nil else size),
		children = children,
	})
	local semantic = Compose.formula(function(use)
		local value = use(facts)
		local name = spec.name or value.status
		return if counted then `{name}, {value.count}` else name
	end)
	local function dump()
		local value = facts:peek()
		return {
			schema = "facet-status-indicator-dump/1",
			id = id,
			form = value.form,
			status = value.status,
			count = value.count,
			controlSize = value.controlSize,
			max = if counted then cap else nil,
			cutout = spec.cutout == true,
			name = spec.name,
			semanticText = semantic:peek(),
		}
	end
	return { blueprint = root, dump = dump, semanticText = semantic, dispose = owner.dispose }
end
function status_indicator.build(library: any, core: any, spec: Spec)
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
return status_indicator
