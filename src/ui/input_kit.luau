--!strict
local layoutKit = require("./layout_kit")
local valueModel = require("./input_value")
local inputAdjustment = require("./input_adjustment")
local Shared = require("./types")
local ComposeTypes = require("../vendor/compose/core")

export type NumberSpec = {
	read value: Shared.Input<number>,
	read onChange: ((number) -> ())?,
	read readOnly: boolean?,
}
type Unskinned = { [unknown]: boolean }
export type Kit = {
	lists: layoutKit.Kit,
	noKey: Enum.KeyCode,
	unskinned: Unskinned,
	typeRoles: { [string]: boolean },
	repeatDelay: number,
	repeatInterval: number,
	repeatHeld: inputAdjustment.RepeatHeld,
	dynamic: (unknown) -> boolean,
	hasText: (Shared.Input<string>?, ComposeTypes.Use?) -> boolean,
	enabled: (inputAdjustment.EnabledSource, ComposeTypes.Use?) -> boolean,
	stopEnabled: (inputAdjustment.EnabledSource, ComposeTypes.Use?) -> boolean,
	writable: (unknown) -> boolean,
	requireValue: (NumberSpec, "boolean" | "number" | "string", string) -> (),
	changed: (NumberSpec, number) -> boolean,
	attributes: (Instance, Shared.Attributes) -> Instance,
	valueAttributes: (GuiObject, NumberSpec, valueModel.Model) -> (),
	adjustment: inputAdjustment.Adjustment,
	paintedPart: (Shared.FrameProps, Shared.Input<string>?, string, string) -> Frame,
}

local REPEAT_DELAY, REPEAT_INTERVAL = 0.4, 0.1

local function repeatHeld(
	frames: { onFrame: ((number) -> ()) -> () -> () },
	delay: number,
	interval: number,
	keep: () -> boolean,
	fire: () -> ()
): () -> ()
	local elapsed, deadline = 0, delay
	return frames.onFrame(function(delta: number)
		if not keep() then
			return
		end
		elapsed += delta
		local steps = 0
		while elapsed >= deadline and steps < 5 do
			fire()
			deadline += interval
			steps += 1
		end
		if steps == 5 then
			deadline = elapsed + interval
		end
	end)
end

return function(ctx: Shared.Context): Kit
	local lists = layoutKit.of(ctx)
	local runtime, Host, Compose = ctx.runtime, ctx.Host, ctx.Compose
	local read = ctx.read
	local D2, E = ctx.types.UDim2, ctx.types.Enum
	local noKey: Enum.KeyCode = assert(E.KeyCode:FromValue(0))
	local unskinned: Unskinned = setmetatable({}, { __mode = "k" })
	local typeRoles: { [string]: boolean } = {
		caption = true,
		label = true,
		body = true,
		heading = true,
		title = true,
		control = true,
		strong = true,
		numeral = true,
	}
	local function dynamic(source: unknown): boolean
		return Compose.isValue(source) or type(source) == "function"
	end
	local function hasText(source: Shared.Input<string>?, use: ComposeTypes.Use?): boolean
		local value = read(source, use)
		return value ~= nil and value ~= ""
	end
	local function enabled(spec: inputAdjustment.EnabledSource, use: ComposeTypes.Use?): boolean
		return read(spec.enabled, use) ~= false and read(spec.disabled, use) ~= true and read(spec.busy, use) ~= true
	end
	local function stopEnabled(spec: inputAdjustment.EnabledSource, use: ComposeTypes.Use?): boolean
		return read(spec.enabled, use) ~= false and read(spec.disabled, use) ~= true
	end
	local function writable(source: unknown): boolean
		return type(source) == "table"
			and Compose.isValue(source)
			and type((source :: { [string]: unknown }).set) == "function"
	end
	local function requireValue(spec: NumberSpec, kind: "boolean" | "number" | "string", name: string): ()
		assert(type(read(spec.value)) == kind, `Facet.{name}: value must resolve to a {kind}`)
		assert(
			writable(spec.value) or type(spec.onChange) == "function" or spec.readOnly == true,
			`Facet.{name}: editing a read-only value requires onChange`
		)
	end

	local function changed(spec: NumberSpec, nextValue: number): boolean
		if read(spec.value) == nextValue then
			return false
		end
		if spec.onChange then
			spec.onChange(nextValue)
		else
			(spec.value :: ComposeTypes.Value<number>):set(nextValue)
		end
		return read(spec.value) == nextValue
	end
	local function attributes(node: Instance, values: Shared.Attributes): Instance
		runtime.decorate(node, { Attributes = values })
		return node
	end
	local function mapValue<T>(source: Shared.Input<number>, transform: (number) -> T): Shared.Input<T>
		if type(source) == "number" then
			return transform(source)
		elseif type(source) == "function" then
			return function(use: ComposeTypes.Use): T
				return transform(source(use))
			end
		end
		return Compose.map(source, transform)
	end
	local function valueAttributes(node: GuiObject, spec: NumberSpec, model: valueModel.Model): ()
		attributes(node, {
			value = mapValue(spec.value, model.quantize),
			minimum = model.min,
			maximum = model.max,
			semanticValue = mapValue(spec.value, function(value: number): string
				return `{model.format(value)} of {model.min} to {model.max}`
			end),
		})
	end
	local adjustment = inputAdjustment(ctx, {
		attributes = attributes,
		enabled = enabled,
		stopEnabled = stopEnabled,
		repeatHeld = repeatHeld,
		repeatDelay = REPEAT_DELAY,
		repeatInterval = REPEAT_INTERVAL,
	})
	local function paintedPart(
		native: Shared.FrameProps,
		image: Shared.Input<string>?,
		role: string,
		slot: string
	): Frame
		if image then
			native[#native + 1] = Host.ImageLabel "Artwork" {
				Image = image,
				BackgroundTransparency = 1,
				Size = D2.fromScale(1, 1),
				ScaleType = E.ScaleType.Stretch,
			}
		end
		local node = ctx.styled(Host.Frame(native), role)
		if not image then
			ctx.skin(node, slot)
		end
		return node
	end
	return {
		lists = lists,
		noKey = noKey,
		unskinned = unskinned,
		typeRoles = typeRoles,
		repeatDelay = REPEAT_DELAY,
		repeatInterval = REPEAT_INTERVAL,
		repeatHeld = repeatHeld,
		dynamic = dynamic,
		hasText = hasText,
		enabled = enabled,
		stopEnabled = stopEnabled,
		writable = writable,
		requireValue = requireValue,
		changed = changed,
		attributes = attributes,
		valueAttributes = valueAttributes,
		adjustment = adjustment,
		paintedPart = paintedPart,
	}
end
