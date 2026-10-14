--!strict
local civil = require("./civil_date")
local Shared = require("./types")
local DTP = require("./date_time_picker_types")
local ControlTypes = require("./control_types")
local InputProps = require("./input_props")
local ComposeTypes = require("../vendor/compose/core")

type CivilDate = DTP.CivilDate
type Range = DTP.Range
type Use = ComposeTypes.Use
export type Deps = {
	DateTimePicker: Shared.Constructor<InputProps.DateTimePickerProps, Frame>,
	Button: Shared.Constructor<InputProps.ButtonProps, TextButton>,
	NumberInput: Shared.Constructor<InputProps.NumberInputProps, TextBox | Frame>,
	Chip: Shared.Constructor<InputProps.ChipProps, TextButton | Frame>,
	ShortcutHint: Shared.Constructor<InputProps.ShortcutHintProps, TextLabel | Frame>,
	Menu: ControlTypes.MenuConstructor,
	Picker: ControlTypes.PickerConstructor,
	VirtualList: ControlTypes.CollectionConstructor,
}
export type Parts = {
	gui: GuiService?,
	input: UserInputService?,
	tagWhile: (Instance, string, (Use) -> boolean) -> (),
	frame: (string, Shared.FrameNativeProps?) -> Frame,
}

local CELLS = 42
local CELL = 44
local DISC = 32
local GAP = 24
local YEAR_SPAN = 50
local ROW = 44

local function span(from: CivilDate?, to: CivilDate?): Range
	return { start = from, finish = to }
end

local function monthOf(d: CivilDate): CivilDate
	return { year = d.year, month = d.month, day = 1 }
end

local function sameRange(a: Range, b: Range): boolean
	return civil.same(a.start, b.start) and civil.same(a.finish, b.finish)
end

local function new(ctx: Shared.Context): Parts
	local Host, Compose = ctx.Host, ctx.Compose
	local D2, V2 = ctx.types.UDim2, ctx.types.Vector2
	local gui = ctx.config.guiService
	local input = ctx.config.services.UserInputService

	local function tagWhile(node: Instance, tag: string, on: (Use) -> boolean)
		Compose.watch(function(use: Use)
			if on(use) then
				node:AddTag(tag)
			elseif node:HasTag(tag) then
				node:RemoveTag(tag)
			end
		end)
	end
	local function frame(name: string, properties: Shared.FrameNativeProps?): Frame
		local native: Shared.FrameNativeProps = {
			Name = name,
			BorderSizePixel = 0,
			Size = D2.fromOffset(DISC, DISC),
			AnchorPoint = V2.new(0.5, 0.5),
			Position = D2.fromScale(0.5, 0.5),
		}
		local fields = (native :: unknown) :: { [unknown]: unknown }
		for key, value in ((properties or {}) :: unknown) :: { [unknown]: unknown } do
			if type(key) == "number" then
				fields[#fields + 1] = value
			else
				fields[key] = value
			end
		end
		return Host.Frame(native)
	end

	return { gui = gui, input = input, tagWhile = tagWhile, frame = frame }
end

return {
	CELLS = CELLS,
	CELL = CELL,
	DISC = DISC,
	GAP = GAP,
	YEAR_SPAN = YEAR_SPAN,
	ROW = ROW,
	span = span,
	monthOf = monthOf,
	sameRange = sameRange,
	new = new,
}
