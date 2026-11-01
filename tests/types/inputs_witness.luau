--!strict
local Inputs = require("../../src/ui/input_types")
local InputProps = require("../../src/ui/input_props")
local InputsControls = require("../../src/ui/control_types")
local Compose = require("../../src/vendor/compose/core")

return function(UI: InputsControls.Controls, action: InputAction): ()
	local text, value, checked = Compose.cell(""), Compose.cell(0.5), Compose.cell(false)
	local button: TextButton = UI.Button "Save" {
		label = text,
		onActivate = function(input, clicks)
			local nativeInput: InputObject? = input
			local clickCount: number? = clicks
			if nativeInput and clickCount then
				text:set(nativeInput.UserInputType.Name)
			end
		end,
	}
	local toggle: TextButton = UI.Toggle {
		value = checked,
		onChange = function(nextValue)
			checked:set(nextValue)
		end,
	}
	local field: GuiObject = UI.TextInput {
		value = text,
		label = "Name",
		requiredMark = "required",
		selectOnFocus = "all",
		onCommit = function(nextText, reason)
			local commit: Inputs.TextCommitReason = reason
			if commit == "submit" then
				text:set(nextText)
			end
		end,
	}
	local laps = Compose.cell(3)
	local number: GuiObject = UI.NumberInput {
		value = text,
		numericValue = laps,
		stepButtons = true,
		precision = 1,
		onCommit = function(committed, reason)
			local commit: Inputs.CommitReason = reason
			if commit == "clamped" then
				laps:set(committed)
			end
		end,
	}
	local numericProps: InputProps.TextInputNumberCellPropsInput = {
		value = text,
		presentation = "number",
		numericValue = laps,
		onCommit = function(committed, _)
			laps:set(committed)
		end,
	}
	local numeric: GuiObject = UI.TextInput(numericProps)
	local stepper: Frame = UI.Stepper { value = value, min = 0, max = 1, step = 0.1 }
	local slider: Frame = UI.Slider "Volume" {
		value = function(use: Compose.Use): number
			return use(value)
		end,
		onChange = function(nextValue)
			value:set(nextValue)
		end,
	}
	local rating: TextButton = UI.Rating { value = 3, readOnly = true }
	local level: TextButton = UI.LevelPicker { value = value, segment = "bar" }
	local chip: GuiObject = UI.Chip {
		selected = checked,
		onRemove = function() end,
		ref = function(node: TextButton | Frame)
			local native: GuiObject = node
			native.Name = "SelectedChip"
		end,
	}
	local keyHint: GuiObject = UI.ShortcutHint { keys = { { "Control", "S" } } }
	local actionHint: GuiObject = UI.ShortcutHint {
		action = action,
		ref = function(node: TextLabel | Frame)
			local native: GuiObject = node
			native.Name = "ActionHint"
		end,
	}
	local guideEntries: { Inputs.ButtonGuideEntry } = {
		{ action = action, label = "Buy" },
		{ keys = { { "Ctrl", "S" } }, label = "Save" },
		{ keyCode = { Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1 }, label = "Tabs" },
		{ keyCode = Enum.KeyCode.ButtonY, label = text },
	}
	local guide: Frame = UI.ButtonGuide {
		entries = guideEntries,
		inputs = { "Gamepad", "KeyboardAndMouse" },
		controlSize = "compact",
		LayoutOrder = 2,
	}
	local link: TextButton =
		UI.Button { label = "Terms", appearance = "inverse", underline = "hover", textSize = "label" }
	local hinted: TextButton = UI.Button { label = "Boost", icon = "flag", caption = "Boost", shortcutHint = action }
	local plain: TextButton = UI.Toggle {
		value = checked,
		presentation = "checkbox",
		appearance = "plain",
		controlSize = "xsmall",
		textSize = 14,
	}
	link.Visible = true
	hinted.Visible = true
	plain.Visible = true
	button.Text = "Saved"
	toggle.Selected = true
	field.Visible = true
	number.Visible = true
	numeric.Visible = true
	stepper.Visible = true
	slider.Visible = true
	rating.Text = "Rating"
	level.Text = "Level"
	chip.Visible = true
	keyHint.Visible = true
	actionHint.Visible = true
	guide.Visible = true
end
