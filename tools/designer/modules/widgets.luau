--!strict

local widgets = {}

function widgets.new(Facet: any, runtime: any, model: any, options: any): any
	local Host, Compose = runtime.constructors, Facet.Compose
	local kit = {}
	kit.colors = {
		text = Color3.fromRGB(30, 40, 57),
		muted = Color3.fromRGB(110, 122, 142),
		blue = Color3.fromRGB(45, 112, 231),
		line = Color3.fromRGB(220, 225, 234),
	}
	function kit.corner(radius: number?)
		return Host.UICorner { CornerRadius = UDim.new(0, radius or 7) }
	end
	function kit.padding(amount: number)
		return Host.UIPadding {
			PaddingTop = UDim.new(0, amount),
			PaddingBottom = UDim.new(0, amount),
			PaddingLeft = UDim.new(0, amount),
			PaddingRight = UDim.new(0, amount),
		}
	end
	local theme = Facet.themes.define(Facet.themes.neutralPackage())
	local UI = Facet.controls(
		runtime,
		{ theme = theme, keyboardNavigation = options.keyboardNavigation == true, inputParent = options.inputParent }
	)
	kit.UI = UI
	function kit.sheet()
		return Facet.themes.createStyleSheet(runtime, theme, { theme = "Light" })
	end
	function kit.text(name: string, value: any, size: number?, height: number?): TextLabel
		return UI.Text(name) {
			text = value,
			textSize = size or 12,
			wrap = false,
			AutomaticSize = Enum.AutomaticSize.None,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, height or 24),
			TextTruncate = Enum.TextTruncate.AtEnd,
		}
	end
	function kit.button(
		name: string,
		value: any,
		width: number,
		callback: () -> (),
		primary: any?,
		enabled: any?,
		selected: any?
	): TextButton
		local menu = table.find(
			{ "Device", "Palette", "TextSize", "Compare", "Zoom", "Templates", "Saved", "MoveInto" },
			name
		) ~= nil or string.sub(name, 1, 15) == "ChoiceProperty_"

		return UI.Button(name) {
			label = if type(value) == "function"
				then function(use)
					return string.gsub(value(use), "%s*▾", "")
				end
				else string.gsub(value, "%s*▾", ""),
			trailingIcon = if menu then "chevron.down" else nil,
			selected = selected,
			appearance = if type(primary) == "function"
				then function(use)
					return if primary(use) then "soft" else "utility"
				end
				else if primary then "emphasis" else "standard",
			controlSize = function(use)
				return if use(model).compact then "regular" else "compact"
			end,
			AutomaticSize = Enum.AutomaticSize.None,
			onActivate = callback,
			enabled = if enabled == nil then true else enabled,
			Size = function(use)
				return if width == -1
					then UDim2.new(1, -10, 0, if use(model).compact then 44 else 32)
					else UDim2.fromOffset(width, if use(model).compact then 44 else 32)
			end,
		}
	end
	function kit.input(name: string, value: any, callback: (string) -> (), width: any?): TextBox
		local draft = Compose.cell("")
		local baseline = ""
		Compose.watch(function(use)
			baseline = tostring(if type(value) == "function" then value(use) else value)
			draft:set(baseline)
		end)
		return UI.TextInput(name) {
			value = draft,
			onCommit = function(proposed)
				if proposed ~= baseline then
					callback(proposed)
				end
			end,
			controlSize = function(use)
				return if use(model).compact then "regular" else "compact"
			end,
			Size = function(use)
				local size = width or UDim2.new(1, 0, 0, 34)
				return if use(model).compact then UDim2.new(size.X.Scale, size.X.Offset, 0, 44) else size
			end,
			maxLength = 10000,
		}
	end
	function kit.search(value: any, callback: (string) -> ()): TextBox
		return UI.TextInput "MenuSearch" {
			value = value,
			onChange = callback,
			presentation = "search",
			placeholder = "Search…",
			clearButton = true,
			controlSize = "regular",
			Size = UDim2.new(1, 0, 0, 44),
		}
	end

	function kit.row(name: string, children: any, height: number?, wrap: boolean?): Frame
		for index, child in children do
			runtime.decorate(child, { LayoutOrder = index })
		end
		return UI.HStack(name) {
			width = "fill",
			Size = UDim2.new(1, 0, 0, height or 0),
			gap = 6,
			align = "center",
			wrap = wrap,
			BackgroundTransparency = 1,
			table.unpack(children),
		}
	end
	return kit
end

return widgets
