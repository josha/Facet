--!strict
local guard = require("../spec_guard")
local contract = require("../class_contract")
local chrome = require("../tokens/chrome_slots")
local themePackage = require("../themes/package")
local menuRecipe = require("./menu_recipe")
local Compose = require("../vendor/compose/core")
local read = require("../selection_model").read
local toggle = {}
local KEYS = guard.keySet({ "id", "label", "value", "mixed", "presentation", "enabled", "onChange", "children", "row" })
function toggle.build(Facet, core, spec)
	guard.assertKnownKeys("UI.Toggle", spec, KEYS, "spec")
	assert(spec.row == nil or spec.children == nil, "UI.Toggle.row cannot combine with children")
	local presentation = spec.presentation or "switch"
	assert(
		presentation == "switch" or presentation == "checkbox" or presentation == "button",
		"UI.Toggle: presentation must be switch | checkbox | button"
	)
	assert(
		Compose.isReadable(spec.value) and type(spec.value.set) == "function" and type(read(spec.value)) == "boolean",
		"UI.Toggle: value must be a caller-owned boolean cell"
	)
	assert(
		spec.mixed == nil
			or (
				presentation == "checkbox"
				and Compose.isReadable(spec.mixed)
				and type(spec.mixed.set) == "function"
				and type(read(spec.mixed)) == "boolean"
			),
		"UI.Toggle: mixed must be a writable Compose cell holding a boolean on a checkbox"
	)
	assert(spec.children == nil or presentation == "button", "UI.Toggle: children require the button presentation")
	assert(spec.onChange == nil or type(spec.onChange) == "function", "UI.Toggle: onChange must be a function")
	local UI = Facet.UI
	local disposed = false
	local function activate()
		if disposed or not contract.enabledNow(spec.enabled) then
			return
		end
		core.reactor:batch(function()
			local nextValue = if spec.mixed and read(spec.mixed) then true else not read(spec.value)
			if spec.mixed then
				spec.mixed:set(false)
			end
			spec.value:set(nextValue)
			if spec.onChange then
				spec.onChange(nextValue)
			end
		end)
	end
	local selected = function(use)
		return read(spec.value, use) or (spec.mixed ~= nil and read(spec.mixed, use))
	end
	local props = {
		id = spec.id or "Toggle",
		label = spec.label or "",
		enabled = spec.enabled,
		height = { type = "minMax", min = "targetSizes.minimum" },
		onActivate = activate,
	}
	local blueprint
	if spec.row then
		assert(spec.row.value == nil, "UI.Toggle.row: value is supplied by the toggle")
		local valueText = function(use)
			return if spec.mixed and read(spec.mixed, use) then "Mixed" elseif read(spec.value, use) then "On" else "Off"
		end
		props.width = UI.fill()
		props.selected = selected
		props.children = menuRecipe.semantic(UI, spec.label, spec.row, valueText)
		blueprint = UI.Button(props)
	elseif presentation == "switch" then
		props.value = spec.value
		blueprint = UI.Toggle(props)
	else
		props.selected = selected
		props.children = spec.children
		if presentation == "checkbox" then
			props.width = UI.fill()
			local marks = {}
			for _, item in
				{
					{
						"Check",
						"checkmark",
						function(use)
							return read(spec.value, use) and not (spec.mixed and read(spec.mixed, use))
						end,
					},
					{
						"Mixed",
						"decrement",
						function(use)
							return spec.mixed ~= nil and read(spec.mixed, use)
						end,
					},
				}
			do
				table.insert(
					marks,
					chrome.attachHint(
						UI.Text({
							id = item[1],
							text = themePackage.iconGlyph(item[2]) or (if item[1] == "Check" then "x" else "-"),
							textSize = "control",
							hidden = function(use)
								return not item[3](use)
							end,
						}),
						{ icon = item[2] }
					)
				)
			end
			props.children = {
				UI.HStack({
					gap = "s",
					width = UI.fill(),
					children = {
						UI.corners(
							UI.ZStack({
								id = "Indicator",
								alignH = "center",
								alignV = "center",
								surface = "control",
								width = { type = "minMax", min = "l" },
								height = { type = "minMax", min = "l" },
								children = marks,
							}),
							"control"
						),
						UI.Text({ id = "Label", text = spec.label or "", textSize = "control", width = UI.fill() }),
					},
				}),
			}
		end
		blueprint = UI.Button(props)
	end
	local function dump()
		return {
			schema = "facet-toggle-dump/1",
			value = read(spec.value),
			mixed = spec.mixed ~= nil and read(spec.mixed),
			presentation = presentation,
			enabled = contract.enabledNow(spec.enabled),
		}
	end
	return table.freeze({
		blueprint = blueprint,
		dump = dump,
		dispose = function()
			disposed = true
		end,
	})
end
return toggle
