--!strict
local Inputs = require("../../src/ui/input_types")
local Compose = require("../../src/vendor/compose/core")

return function(UI: Inputs.InputControls, action: InputAction): ()
	local text, value, checked = Compose.cell(""), Compose.cell(0.5), Compose.cell(false)
	local button: TextButton = UI.Button("Save")({
		label = text,
		onActivate = function(input, clicks)
			local nativeInput: InputObject? = input
			local clickCount: number? = clicks
			if nativeInput and clickCount then
				text:set(nativeInput.UserInputType.Name)
			end
		end,
	})
	local toggle: TextButton = UI.Toggle({
		value = checked,
		onChange = function(nextValue)
			checked:set(nextValue)
		end,
	})
	local field: TextBox = UI.TextInput({
		value = text,
		presentation = "number" :: "number",
		numericValue = value,
		onCommit = function(nextText, reason)
			local commit: Inputs.CommitReason = reason
			if commit == "submit" then
				text:set(nextText)
			end
		end,
	})
	local stepper: Frame = UI.Stepper({ value = value, min = 0, max = 1, step = 0.1 })
	local slider: Frame = UI.Slider("Volume")({
		value = function(use: Compose.Use): number
			return use(value)
		end,
		onChange = function(nextValue)
			value:set(nextValue)
		end,
	})
	local rating: TextButton = UI.Rating({ value = 3, readOnly = true :: true })
	local level: TextButton = UI.LevelPicker({ value = value, segment = "bar" :: "bar" })
	local chip: GuiObject = UI.Chip({
		selected = checked,
		onRemove = function() end,
		ref = function(node: TextButton | Frame)
			local native: GuiObject = node
			native.Name = "SelectedChip"
		end,
	})
	local keyHint: GuiObject = UI.ShortcutHint({ keys = { { "Control", "S" } } })
	local actionHint: GuiObject = UI.ShortcutHint({
		action = action,
		ref = function(node: TextLabel | Frame)
			local native: GuiObject = node
			native.Name = "ActionHint"
		end,
	})
	button.Text = "Saved"
	toggle.Selected = true
	field.Text = "0.5"
	stepper.Visible = true
	slider.Visible = true
	rating.Text = "Rating"
	level.Text = "Level"
	chip.Visible = true
	keyHint.Visible = true
	actionHint.Visible = true
end
