--!strict
local guard = require("../spec_guard")
local contract = require("../class_contract")
local chrome = require("../tokens/chrome_slots")
local themePackage = require("../themes/package")
local toggle = {}
local KEYS = guard.keySet({ "id", "label", "value", "mixed", "presentation", "enabled", "onChange", "children" })
function toggle.build(Facet, core, spec)
	guard.assertKnownKeys("Controls.Toggle", spec, KEYS, "spec")
	local presentation = spec.presentation or "switch"
	assert(
		presentation == "switch" or presentation == "checkbox" or presentation == "button",
		"Controls.Toggle: presentation must be switch | checkbox | button"
	)
	assert(
		type(spec.value) == "table" and spec.value.kind == "signal" and type(spec.value:get()) == "boolean",
		"Controls.Toggle: value must be a caller-owned Signal<boolean>"
	)
	assert(
		spec.mixed == nil
			or (
				presentation == "checkbox"
				and type(spec.mixed) == "table"
				and spec.mixed.kind == "signal"
				and type(spec.mixed:get()) == "boolean"
			),
		"Controls.Toggle: mixed must be a caller-owned Signal<boolean> on a checkbox"
	)
	assert(
		spec.children == nil or presentation == "button",
		"Controls.Toggle: children require the button presentation"
	)
	assert(spec.onChange == nil or type(spec.onChange) == "function", "Controls.Toggle: onChange must be a function")
	local UI = Facet.UI
	local scope = core:scope("toggle")
	local disposed = false
	scope:own(function()
		disposed = true
	end)
	local function activate()
		if disposed or not contract.enabledNow(spec.enabled) then
			return
		end
		core:transaction(function()
			local nextValue = if spec.mixed and spec.mixed:get() then true else not spec.value:get()
			if spec.mixed then
				spec.mixed:set(false)
			end
			spec.value:set(nextValue)
			if spec.onChange then
				spec.onChange(nextValue)
			end
		end)
	end
	local selected = scope:own(core:memo(function(use)
		return use(spec.value) or (spec.mixed ~= nil and use(spec.mixed))
	end))
	local props = {
		id = spec.id or "Toggle",
		label = spec.label or "",
		enabled = spec.enabled,
		height = { type = "minMax", min = "targetSizes.minimum" },
		onActivate = activate,
	}
	local blueprint
	if presentation == "switch" then
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
							return use(spec.value) and not (spec.mixed and use(spec.mixed))
						end,
					},
					{
						"Mixed",
						"decrement",
						function(use)
							return spec.mixed ~= nil and use(spec.mixed)
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
							hidden = scope:own(core:memo(function(use)
								return not item[3](use)
							end)),
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
			value = spec.value:get(),
			mixed = spec.mixed ~= nil and spec.mixed:get(),
			presentation = presentation,
			enabled = contract.enabledNow(spec.enabled),
		}
	end
	return table.freeze({
		blueprint = blueprint,
		dump = dump,
		dispose = function()
			scope:dispose()
		end,
	})
end
return toggle
