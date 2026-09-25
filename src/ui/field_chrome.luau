--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")

export type Mark = "required" | "optional"
export type Appearance = "standard" | "contrast" | "utility"
export type Corners = "pill" | "square"
export type Options = {
	label: Shared.Value<string>?,
	requiredMark: Mark?,
	hint: Shared.Value<string>?,
	errorText: Shared.Value<string>?,
	controlSize: Shared.Value<Shared.ControlSize>?,
	appearance: Shared.Value<string>?,
	corners: Corners?,
}
export type Wrap = {
	control: string,
	spec: Options,
	plate: GuiObject,
	focus: () -> (),
	enabled: (ComposeTypes.Use?) -> boolean,
	message: ComposeTypes.Readable<string>?,
	native: Shared.FrameNativeProps,
}
export type Chrome = {
	KEYS: { string },
	present: (Options) -> boolean,
	check: (string, Options) -> (),
	labelText: (Options, ComposeTypes.Use?) -> string,
	errorOf: (Options, ComposeTypes.Readable<string>?) -> (ComposeTypes.Use?) -> string,
	paint: (string, GuiObject, Options, ((ComposeTypes.Use?) -> boolean)?) -> (),
	wrap: (Wrap) -> Frame,
}

local KEYS = table.freeze({ "label", "requiredMark", "hint", "errorText", "controlSize", "appearance", "corners" })
local APPEARANCE: { [string]: string } = {
	standard = "facet-field",
	contrast = "facet-control",
	utility = "facet-appearance-utility",
}

local REFIT_FRAMES = 30

return function(ctx: Shared.Context): Chrome
	local Host, Compose, runtime, read = ctx.Host, ctx.Compose, ctx.runtime, ctx.read
	local E, D, D2, V2 = ctx.types.Enum, ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2
	local chrome = {} :: Chrome
	chrome.KEYS = KEYS
	local function dynamic(source: unknown): boolean
		return Compose.isReadable(source) or type(source) == "function"
	end
	function chrome.present(spec: Options): boolean
		for _, key in KEYS do
			if ((spec :: unknown) :: { [string]: unknown })[key] ~= nil then
				return true
			end
		end
		return false
	end
	local function appearanceWord(control: string, word: unknown): Appearance
		if word == nil then
			return "standard"
		end
		if type(word) ~= "string" or APPEARANCE[word] == nil then
			error(`Facet UI.{control}: appearance must be standard | contrast | utility (got {tostring(word)})`, 0)
		end
		return word :: Appearance
	end
	function chrome.check(control: string, spec: Options)
		local mark: unknown = spec.requiredMark
		if mark ~= nil and mark ~= "required" and mark ~= "optional" then
			error(`Facet UI.{control}: requiredMark must be required | optional (got {tostring(mark)})`, 0)
		end
		for _, key in { "label", "hint", "errorText" } do
			local value = read(((spec :: unknown) :: { [string]: Shared.Value<unknown> })[key])
			if value ~= nil and type(value) ~= "string" then
				error(`Facet UI.{control}: {key} must be a string or a readable string (got {typeof(value)})`, 0)
			end
		end
		local corners: unknown = spec.corners
		if corners ~= nil and corners ~= "pill" and corners ~= "square" then
			error(`Facet UI.{control}: corners must be pill | square (got {tostring(corners)})`, 0)
		end
		appearanceWord(control, read(spec.appearance))
		if spec.controlSize ~= nil then
			ctx.controlSize(spec.controlSize, "height")
		end
	end
	function chrome.labelText(spec: Options, use: ComposeTypes.Use?): string
		local words = read(spec.label, use) or ""
		return if spec.requiredMark == "required" then words .. " *" else words
	end
	function chrome.errorOf(spec: Options, internal: ComposeTypes.Readable<string>?): (ComposeTypes.Use?) -> string
		return function(use: ComposeTypes.Use?): string
			local authored = read(spec.errorText, use)
			if type(authored) == "string" and authored ~= "" then
				return authored
			end
			local own = if internal then read(internal, use) else nil
			return if type(own) == "string" then own else ""
		end
	end
	local function refit(label: TextLabel): TextLabel
		local frames = ctx.config.services and ctx.config.services.RunService
		if frames == nil then
			return label
		end
		local size = ctx.observe.AbsoluteSize(label)
		local pending: RBXScriptConnection? = nil
		local function release()
			if pending then
				pending:Disconnect()
				pending = nil
			end
		end
		ctx.Compose.cleanup(release)
		ctx.Compose.watch(function(use: ComposeTypes.Use)
			use(size)
			if pending ~= nil then
				return
			end
			local count = 0
			local original: UDim2? = nil
			pending = frames.Heartbeat:Connect(function()
				count += 1
				local base = original
				if base then
					release()
					label.Size = base
				elseif label.TextBounds.Y > label.AbsoluteSize.Y + 0.5 then
					local current = label.Size
					original = current
					label.Size = D2.new(current.X.Scale, current.X.Offset, current.Y.Scale, current.Y.Offset + 1)
				elseif count >= REFIT_FRAMES then
					release()
				end
			end)
		end)
		return label
	end
	local function tagWhile(node: Instance, tag: string, on: boolean)
		if on then
			node:AddTag(tag)
		elseif node:HasTag(tag) then
			node:RemoveTag(tag)
		end
	end
	function chrome.paint(control: string, plate: GuiObject, spec: Options, failing: ((ComposeTypes.Use?) -> boolean)?)
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
	function chrome.wrap(options: Wrap): Frame
		local spec, plate = options.spec, options.plate
		local failure = chrome.errorOf(spec, options.message)
		local function line(use: ComposeTypes.Use?): string
			local text = failure(use)
			return if text ~= "" then text else read(spec.hint, use) or ""
		end
		local parts: { ComposeTypes.Child } = {}
		if spec.label ~= nil then
			local label = Host.TextButton "Label" {
				Text = "",
				AutoButtonColor = false,
				Selectable = false,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = D2.new(1, 0, 0, 44),
				AutomaticSize = E.AutomaticSize.Y,
				Interactable = function(use: ComposeTypes.Use)
					return options.enabled(use)
				end,
				Activated = function()
					if options.enabled() then
						options.focus()
					end
				end,
				refit(ctx.styled(
					ctx.text({
						Name = "Title",
						Text = function(use: ComposeTypes.Use)
							return chrome.labelText(spec, use)
						end,
						Size = D2.new(1, 0, 0, 0),
						AutomaticSize = E.AutomaticSize.Y,
						AnchorPoint = V2.new(0, 1),
						Position = D2.fromScale(0, 1),
						TextWrapped = true,
					}),
					"type-label"
				)),
			}
			table.insert(parts, label)
		end
		local body: GuiObject = plate
		if spec.controlSize ~= nil then
			runtime.decorate(plate, {
				AnchorPoint = V2.new(0, 0.5),
				Position = D2.fromScale(0, 0.5),
				Size = function(use: ComposeTypes.Use)
					return D2.new(1, 0, 0, ctx.controlSize(spec.controlSize, "height", use))
				end,
				AutomaticSize = E.AutomaticSize.None,
			})
			body = Host.Frame(plate.Name .. "+target")({
				BackgroundTransparency = 1,
				Size = function(use: ComposeTypes.Use)
					return D2.new(1, 0, 0, math.max(44, (ctx.controlSize(spec.controlSize, "height", use))))
				end,
				plate :: ComposeTypes.Child,
			})
		end
		table.insert(parts, body)
		local words = ctx.styled(
			ctx.text({
				Name = "Validation",
				Text = line,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				TextWrapped = true,
				Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }) :: ComposeTypes.Child,
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
		table.insert(parts, message)
		local native = options.native
		native.BackgroundTransparency = 1
		native.Size = native.Size or D2.new(1, 0, 0, 0)
		native.AutomaticSize = native.AutomaticSize or E.AutomaticSize.Y
		local root = ctx.column(parts, native)
		assert(root:FindFirstChildWhichIsA("UIListLayout")).Padding = D.new(0, 4)
		return root
	end
	return chrome
end
