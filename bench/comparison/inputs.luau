--!strict

local Facet = require("../../src")
local Types = require("./types")
local S = require("./support")

local workloads: { Types.Workload } = {}

table.insert(workloads, {
	id = "settings-17-values",
	iterations = 17,
	what = "Change each of ten toggle, four slider and three segmented-picker model values; native value readouts show the result.",
	prepare = function(world: Types.World, lane: Types.Lane): Types.Scene
		local UI, Compose = world.UI, world.Compose
		local toggles: { Facet.Value<boolean> } = {}
		local sliders: { Facet.Value<number> } = {}
		local pickers: { Facet.Value<string> } = {}
		for _ = 1, 10 do
			if lane == "facet" then
				table.insert(toggles, Compose.cell(false))
			end
		end
		for _ = 1, 4 do
			if lane == "facet" then
				table.insert(sliders, Compose.cell(0))
			end
		end
		for _ = 1, 3 do
			if lane == "facet" then
				table.insert(pickers, Compose.cell("low"))
			end
		end
		local options: { Facet.PickerOption<string> } =
			{ { value = "low", label = "Low" }, { value = "high", label = "High" } }
		local bareValues: { string } = table.create(17, "0")
		local stop = S.mount(world, lane, function()
			local children: { Instance } = {}
			for i, value in toggles do
				table.insert(
					children,
					UI.Toggle("Toggle" .. i) { label = `Option {i}`, value = value, presentation = "button" }
				)
			end
			for i, value in sliders do
				table.insert(children, UI.Slider("Slider" .. i) { value = value, min = 0, max = 1, step = 0.1 })
			end
			for i, selected in pickers do
				table.insert(
					children,
					UI.Picker("Picker" .. i) { selected = assert(selected), options = options, style = "segmented" }
				)
			end
			for i = 1, 17 do
				table.insert(
					children,
					UI.Text("Value" .. i) {
						text = function(use: Facet.Use)
							if i <= 10 then
								return if use(toggles[i]) then "1" else "0"
							end
							if i <= 14 then
								return tostring(use(sliders[i - 10]))
							end
							return if use(pickers[i - 14]) == "high" then "1" else "0"
						end,
					}
				)
			end
			return UI.VStack "Settings" { width = 640, gap = 8, table.unpack(children) }
		end, function(screen)
			local root = S.stack(world, screen, "Settings")
			for i = 1, 10 do
				S.button(world, root, "Toggle" .. i, `Option {i}`, function()
					bareValues[i] = if bareValues[i] == "0" then "1" else "0"
					S.setText(world, S.find(world, "Value" .. i), bareValues[i])
				end)
			end
			for i = 1, 4 do
				local slider = S.stack(world, root, "Slider" .. i, true)
				local track =
					S.create(world, "Frame", "Track", slider, { Size = world.types.UDim2.fromOffset(240, 44) })
				S.create(world, "Frame", "Fill", track, { Size = world.types.UDim2.fromScale(0, 1) })
				local thumb = S.create(world, "Frame", "Thumb", track, { Size = world.types.UDim2.fromOffset(24, 24) })
				local drag = S.create(world, "UIDragDetector", "Drag", thumb)
				S.connect(world, drag, "DragEnd", function()
					bareValues[10 + i] = "1"
					S.setText(world, S.find(world, "Value" .. (10 + i)), "1")
				end)
			end
			for i = 1, 3 do
				local picker = S.create(world, "ScrollingFrame", "Picker" .. i, root, {
					Size = world.types.UDim2.fromOffset(240, 44),
					ScrollingDirection = world.types.Enum.ScrollingDirection.X,
				})
				S.stack(world, picker, "Segments", true)
				for _, option in options do
					local label = option.label
					assert(type(label) == "string")
					S.button(world, picker, option.value .. i, label, function()
						bareValues[14 + i] = if option.value == "high" then "1" else "0"
						S.setText(world, S.find(world, "Value" .. (14 + i)), bareValues[14 + i])
					end)
				end
			end
			for i = 1, 17 do
				S.text(world, root, "Value" .. i, "0", true)
			end
		end)
		local names = {}
		for i = 1, 17 do
			table.insert(names, "Value" .. i)
		end
		return {
			step = function(index: number)
				if lane == "facet" then
					if index <= 10 then
						toggles[index]:set(true)
					elseif index <= 14 then
						sliders[index - 10]:set(1)
					else
						pickers[index - 14]:set("high")
					end
				else
					bareValues[index] = "1"
					S.setText(world, S.find(world, "Value" .. index), "1")
					if index <= 10 then
						S.find(world, "Toggle" .. index):AddTag("facet-selected")
					elseif index <= 14 then
						local slider = S.find(world, "Slider" .. (index - 10))
						assert(slider:FindFirstChild("Fill", true)).Size = world.types.UDim2.fromScale(1, 1)
						assert(slider:FindFirstChild("Thumb", true)).Position = world.types.UDim2.fromScale(1, 0)
					end
				end
				world.frame()
			end,
			snapshot = function()
				return S.snapshot(world, names)
			end,
			stop = stop,
		}
	end,
})

table.insert(workloads, {
	id = "text-input-200",
	iterations = 200,
	what = "Type 200 characters through a native TextBox; validation rejects punctuation and accepts letters.",
	prepare = function(world: Types.World, lane: Types.Lane): Types.Scene
		local UI = world.UI
		local value = S.model(world, lane, "")
		local accepted = ""
		local function validate(proposed: string): string?
			return if string.find(proposed, "[^a-z]") then nil else proposed
		end
		local stop = S.mount(world, lane, function()
			return UI.TextInput "Name" { value = assert(value), validate = validate, placeholder = "Player name" }
		end, function(screen)
			local input = S.create(world, "TextBox", "Name", screen, {
				Text = "",
				PlaceholderText = "Player name",
				ClearTextOnFocus = false,
				Size = world.types.UDim2.fromOffset(240, 44),
			})
			input:GetPropertyChangedSignal("Text"):Connect(function()
				local proposed = input.Text
				assert(type(proposed) == "string")
				local nextValue = validate(proposed)
				if nextValue then
					accepted = nextValue
				elseif proposed ~= accepted then
					input.Text = accepted
				end
			end)
		end)
		S.fire(world, "Name", "Focused")
		local editor = S.find(world, "Name")
		return {
			step = function(index: number)
				local text = editor.Text
				assert(type(text) == "string")
				editor.Text = text .. (if index % 10 == 0 then "!" else "a")
			end,
			snapshot = function()
				return tostring(editor.Text)
			end,
			stop = stop,
		}
	end,
})

table.insert(workloads, {
	id = "button-feedback-50",
	iterations = 3,
	what = "Set native GuiState to Hover, Press and Idle on 50 buttons; native StyleSheet transitions are outside this double's paint model.",
	prepare = function(world: Types.World, lane: Types.Lane): Types.Scene
		local UI = world.UI
		local stop = S.mount(world, lane, function()
			local children: { Instance } = {}
			for i = 1, 50 do
				table.insert(children, UI.Button("Action" .. i) { label = `Action {i}`, onActivate = function() end })
			end
			return UI.Grid "Actions" { columns = 5, gap = 8, table.unpack(children) }
		end, function(screen)
			local root = S.grid(world, screen, "Actions", 5)
			for i = 1, 50 do
				local button = S.button(world, root, "Action" .. i, `Action {i}`, function() end)
				button:GetPropertyChangedSignal("GuiState"):Connect(function()
					local state = button.GuiState
					button.BackgroundTransparency = if state == world.types.Enum.GuiState.Press
						then 0.25
						elseif state == world.types.Enum.GuiState.Hover then 0.1
						else 0
				end)
			end
		end)
		local buttons = {}
		for i = 1, 50 do
			table.insert(buttons, S.find(world, "Action" .. i))
		end
		return {
			step = function(index: number)
				local states =
					{ world.types.Enum.GuiState.Hover, world.types.Enum.GuiState.Press, world.types.Enum.GuiState.Idle }
				for _, button in buttons do
					world.engine.environment.poke(button, "GuiState", states[index])
				end
				world.frame()
			end,
			snapshot = function()
				local rows = {}
				for _, button in buttons do
					table.insert(rows, tostring(button.Text) .. ":" .. tostring(button.GuiState))
				end
				return table.concat(rows, "\n")
			end,
			stop = stop,
		}
	end,
})

table.insert(workloads, {
	id = "stepper-segments-100",
	iterations = 100,
	what = "Change a bounded quantity and a segmented choice 100 times through the application model.",
	prepare = function(world: Types.World, lane: Types.Lane): Types.Scene
		local UI, Compose = world.UI, world.Compose
		local quantity, selected = S.model(world, lane, 0), S.model(world, lane, "a")
		local options: { Facet.PickerOption<string> } =
			{ { value = "a", label = "Solo" }, { value = "b", label = "Team" } }
		local stop = S.mount(world, lane, function()
			return UI.VStack "Choices" {
				width = 640,
				gap = 8,
				UI.Stepper "Quantity" { value = assert(quantity), min = 0, max = 100 },
				UI.Picker "Mode" { selected = assert(selected), options = options, style = "segmented" },
				UI.Text "Summary" {
					text = function(use: Facet.Use)
						return `{use(assert(quantity))}:{use(assert(selected))}`
					end,
				},
			}
		end, function(screen)
			local root = S.stack(world, screen, "Choices")
			local stepper = S.stack(world, root, "Quantity", true)
			local count = 0
			S.button(world, stepper, "Decrease", "−", function()
				count = math.max(0, count - 1)
				S.setText(world, S.find(world, "Value"), tostring(count))
			end)
			S.text(world, stepper, "Value", "0", true)
			S.button(world, stepper, "Increase", "+", function()
				count = math.min(100, count + 1)
				S.setText(world, S.find(world, "Value"), tostring(count))
			end)
			local mode =
				S.create(world, "ScrollingFrame", "Mode", root, { Size = world.types.UDim2.fromOffset(240, 44) })
			S.stack(world, mode, "Segments", true)
			for _, option in options do
				local label = option.label
				assert(type(label) == "string")
				S.button(world, mode, option.value, label, function() end)
			end
			S.text(world, root, "Summary", "0:a", true)
		end)
		return {
			step = function(index: number)
				local choice = if index % 2 == 0 then "a" else "b"
				if lane == "facet" then
					assert(quantity):set(index)
					assert(selected):set(choice)
				else
					S.setText(world, S.find(world, "Value"), tostring(index))
					S.setText(world, S.find(world, "Summary"), `{index}:{choice}`)
					local chosen, other = S.find(world, choice), S.find(world, if choice == "a" then "b" else "a")
					if not chosen:HasTag("facet-selected") then
						chosen:AddTag("facet-selected")
					end
					if other:HasTag("facet-selected") then
						other:RemoveTag("facet-selected")
					end
					local decrease, increase = S.find(world, "Decrease"), S.find(world, "Increase")
					if (index <= 0) ~= decrease:HasTag("facet-disabled") then
						if index <= 0 then
							decrease:AddTag("facet-disabled")
						else
							decrease:RemoveTag("facet-disabled")
						end
					end
					if (index >= 100) ~= increase:HasTag("facet-disabled") then
						if index >= 100 then
							increase:AddTag("facet-disabled")
						else
							increase:RemoveTag("facet-disabled")
						end
					end
				end
			end,
			snapshot = function()
				return tostring(S.find(world, "Summary").Text)
			end,
			stop = stop,
		}
	end,
})

return workloads
