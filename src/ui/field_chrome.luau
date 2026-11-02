--!strict
local ThemeTypes = require("./theme_types")
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")

export type Mark = "required" | "optional"
export type Appearance = "standard" | "contrast" | "utility"
export type Corners = "pill" | "square"
export type Options = {
	read label: Shared.Input<string>?,
	requiredMark: Mark?,
	hint: Shared.Input<string>?,
	errorText: Shared.Input<string>?,
	read controlSize: Shared.Input<Shared.ControlSize?>?,
	appearance: Shared.Input<string>?,
	corners: Corners?,
}
export type Wrap = {
	control: string,
	spec: Options,
	plate: GuiObject,
	focus: () -> (),
	enabled: (ComposeTypes.Use?) -> boolean,
	message: ComposeTypes.ReadOnlyValue<string>?,
	native: Shared.FrameProps,
}
export type Chrome = {
	KEYS: { string },
	present: (Options) -> boolean,
	check: (string, Options) -> (),
	labelText: (Options, ComposeTypes.Use?) -> string,
	errorOf: (Options, ComposeTypes.ReadOnlyValue<string>?) -> (ComposeTypes.Use?) -> string,
	paint: (string, GuiObject, Options, ((ComposeTypes.Use?) -> boolean)?) -> (),
	wrap: (Wrap) -> Frame,
}

local KEYS: { string } = { "label", "requiredMark", "hint", "errorText", "controlSize", "appearance", "corners" }
table.freeze(KEYS)
local APPEARANCE: { [string]: string } = {
	standard = "facet-field",
	contrast = "facet-control",
	utility = "facet-appearance-utility",
}

return function(ctx: Shared.Context): Chrome
	local Host, Compose, runtime, read = ctx.Host, ctx.Compose, ctx.runtime, ctx.read
	local E, D, D2, V2 = ctx.types.Enum, ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2
	local readString = read<<string?>>
	local function dynamic(source: unknown): boolean
		return Compose.isValue(source) or type(source) == "function"
	end
	local function present(spec: Options): boolean
		return spec.label ~= nil
			or spec.requiredMark ~= nil
			or spec.hint ~= nil
			or spec.errorText ~= nil
			or spec.controlSize ~= nil
			or spec.appearance ~= nil
			or spec.corners ~= nil
	end
	local function appearanceWord(control: string, word: unknown): Appearance
		if word == nil then
			return "standard"
		end
		if word ~= "standard" and word ~= "contrast" and word ~= "utility" then
			error(`Facet UI.{control}: appearance must be standard | contrast | utility (got {tostring(word)})`, 0)
		end
		return word
	end
	local function checkString(control: string, key: string, source: Shared.Input<string>?)
		local value = readString(source)
		if value ~= nil and type(value) ~= "string" then
			error(`Facet UI.{control}: {key} must be a string or a readable string (got {typeof(value)})`, 0)
		end
	end
	local function check(control: string, spec: Options)
		local mark: unknown = spec.requiredMark
		if mark ~= nil and mark ~= "required" and mark ~= "optional" then
			error(`Facet UI.{control}: requiredMark must be required | optional (got {tostring(mark)})`, 0)
		end
		checkString(control, "label", spec.label)
		checkString(control, "hint", spec.hint)
		checkString(control, "errorText", spec.errorText)
		local corners: unknown = spec.corners
		if corners ~= nil and corners ~= "pill" and corners ~= "square" then
			error(`Facet UI.{control}: corners must be pill | square (got {tostring(corners)})`, 0)
		end
		appearanceWord(control, read(spec.appearance))
		if spec.controlSize ~= nil then
			ctx.controlSize(spec.controlSize, "height")
		end
	end
	local function labelText(spec: Options, use: ComposeTypes.Use?): string
		local words = readString(spec.label, use) or ""
		return if spec.requiredMark == "required" then words .. " *" else words
	end
	local function errorOf(spec: Options, internal: ComposeTypes.ReadOnlyValue<string>?): (ComposeTypes.Use?) -> string
		return function(use: ComposeTypes.Use?): string
			local authored = read(spec.errorText, use)
			if type(authored) == "string" and authored ~= "" then
				return authored
			end
			local own = if internal then read(internal, use) else nil
			return if type(own) == "string" then own else ""
		end
	end
	local function tagWhile(node: Instance, tag: string, on: boolean)
		if on then
			node:AddTag(tag)
		elseif node:HasTag(tag) then
			node:RemoveTag(tag)
		end
	end
	local function paint(control: string, plate: GuiObject, spec: Options, failing: ((ComposeTypes.Use?) -> boolean)?)
		local applied: string? = nil
		local function apply(use: ComposeTypes.Use?)
			local tag = APPEARANCE[appearanceWord(control, read(spec.appearance, use))]
			if applied ~= tag then
				if applied then
					plate:RemoveTag(applied)
				end
				plate:AddTag(tag)
				applied = tag
			end
		end
		if dynamic(spec.appearance) then
			Compose.watch(apply)
		else
			apply()
		end
		if spec.corners then
			runtime.mountFragment(function()
				return { Host.UICorner "Corners" { CornerRadius = D.new(if spec.corners == "pill" then 1 else 0, 0) } }
			end, plate)
		end
		if failing then
			Compose.watch(function(use: ComposeTypes.Use)
				tagWhile(plate, "facet-invalid", failing(use))
			end)
		end
	end
	local function wrap(options: Wrap): Frame
		local spec, plate = options.spec, options.plate
		local failure = errorOf(spec, options.message)
		local function line(use: ComposeTypes.Use?): string
			local text = failure(use)
			return if text ~= "" then text else readString(spec.hint, use) or ""
		end
		local parts: { ComposeTypes.Child } = {}
		if spec.label ~= nil then
			local label = Host.TextButton "Label" {
				Text = "",
				AutoButtonColor = false,
				Selectable = false,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				Interactable = function(use: ComposeTypes.Use)
					return options.enabled(use)
				end,
				Activated = function()
					if options.enabled() then
						options.focus()
					end
				end,
				ctx.styled(
					ctx.text({
						Name = "Title",
						Text = function(use: ComposeTypes.Use)
							return labelText(spec, use)
						end,
						Size = D2.new(1, 0, 0, 0),
						AutomaticSize = E.AutomaticSize.Y,
						TextWrapped = true,
					}),
					"type-label"
				),
			}
			table.insert(parts, label)
		end
		local inputKind = ctx.effectiveInput()
		local function targetFloor(use: ComposeTypes.Use?): number
			return if read(spec.appearance, use) == "utility" and inputKind(use) == "KeyboardAndMouse"
				then 0
				else math.max(44, ctx.metric("targetSizes.minimum", use))
		end
		local body: GuiObject = plate
		if spec.controlSize ~= nil then
			local function plateHeight(use: ComposeTypes.Use): number
				local package = read<<ThemeTypes.ReadOnlyThemePackage?>>(ctx.config.theme, use)
				local skin = package and package.chrome and package.chrome.field
				local carve: { top: number?, bottom: number? } = if skin
						and read(spec.appearance, use) ~= "utility"
						and skin.kind ~= "native"
						and skin.kind ~= "none"
					then skin.contentInsets or {}
					else {}
				local line = ctx.controlSize(spec.controlSize, "iconSize", use)
				return math.max(
					ctx.controlSize(spec.controlSize, "height", use),
					(carve.top or 0) + (carve.bottom or 0) + line
				)
			end
			runtime.decorate(plate, {
				AnchorPoint = V2.new(0, 0.5),
				Position = D2.fromScale(0, 0.5),
				Size = function(use: ComposeTypes.Use)
					return D2.new(1, 0, 0, plateHeight(use))
				end,
				AutomaticSize = E.AutomaticSize.None,
			})
			body = Host.Frame(plate.Name .. "+target")({
				BackgroundTransparency = 1,
				Size = function(use: ComposeTypes.Use)
					return D2.new(1, 0, 0, math.max(targetFloor(use), plateHeight(use)))
				end,
				plate,
			})
		end
		table.insert(parts, body)
		local messageAttached = false
		table.insert(
			parts,
			Compose.show(function(use: ComposeTypes.Use): boolean
				messageAttached = messageAttached or line(use) ~= ""
				return messageAttached
			end, function()
				local words = ctx.styled(
					ctx.text({
						Name = "Validation",
						Text = line,
						Size = D2.new(1, 0, 0, 0),
						AutomaticSize = E.AutomaticSize.Y,
						TextWrapped = true,
						Host.UIFlexItem { FlexMode = E.UIFlexMode.Fill },
					}),
					"type-caption"
				)
				Compose.watch(function(use: ComposeTypes.Use)
					tagWhile(words, "facet-validation", failure(use) ~= "")
				end)
				local lineSize = ctx.observeStyled.TextSize(words)
				local mark = ctx.icon("status.error", {
					Name = "MessageMark",
					Visible = function(use: ComposeTypes.Use)
						return failure(use) ~= ""
					end,
					ScaleType = E.ScaleType.Fit,
					Size = function(use: ComposeTypes.Use)
						local size = ctx.metric("iconSizes.small", use)
						local line = use(lineSize)
						return D2.fromOffset(size, if line > 0 then line else size)
					end,
				})
				mark:AddTag("facet-icon-error")
				local message = ctx.row({ mark, words }, {
					Name = "Message",
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
					Visible = function(use: ComposeTypes.Use)
						return line(use) ~= ""
					end,
				})
				assert(message:FindFirstChildWhichIsA("UIListLayout")).Padding = D.new(0, 4)
				return message
			end)
		)
		local native = options.native
		native.BackgroundTransparency = 1
		native.Size = native.Size or D2.new(1, 0, 0, 0)
		native.AutomaticSize = native.AutomaticSize or E.AutomaticSize.Y
		local root = ctx.column(parts, native)
		assert(root:FindFirstChildWhichIsA("UIListLayout")).Padding = D.new(0, 4)
		return root
	end
	return {
		KEYS = KEYS,
		present = present,
		check = check,
		labelText = labelText,
		errorOf = errorOf,
		paint = paint,
		wrap = wrap,
	}
end
