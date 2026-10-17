--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local InputProps = require("./input_props")
local NavigationProps = require("./navigation_props")
local Kit = require("./color_picker_kit")
local PickerState = require("./color_picker_state")

type Use = ComposeTypes.Use
type Hsv = Kit.Hsv

local FORMATS = { { value = "rgb", label = "RGB" }, { value = "hsv", label = "HSV" }, { value = "hex", label = "Hex" } }
local CELL, GAP = Kit.CELL, Kit.GAP

return function(ctx: Shared.Context, UI: Kit.Deps, kit: Kit.Kit, state: PickerState.State): () -> Frame
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local E, D2 = ctx.types.Enum, ctx.types.UDim2
	local color = kit.color
	local hasAlpha, held, alphaHeld, canon = state.hasAlpha, state.held, state.alphaHeld, state.canon
	local formatCell, hexError = state.formatCell, state.hexError
	local interactive, propose, commit = state.interactive, state.propose, state.commit

	local function numberField(
		name: string,
		words: string,
		max: number,
		get: (Color3, Hsv) -> number,
		with: (number) -> Hsv?
	): GuiObject
		local text, number = Compose.cell(""), Compose.cell(0)
		local function resync()
			local value = held:peek()
			local n = if value == nil then nil else get(value, canon:peek())
			number:set(n or 0)
			text:set(if n == nil then "" else tostring(n))
		end
		Compose.watch(function(use: Use)
			use(held)
			use(canon)
			resync()
		end)
		local props: InputProps.NumberInputProps = {
			Name = name,
			label = words,
			value = text,
			numericValue = number,
			min = 0,
			max = max,
			precision = 0,
			enabled = function(use: Use): boolean
				return interactive(use)
			end,
			Size = D2.fromScale(0, 0),
			onCommit = function(n: number)
				local next = with(n)
				if next ~= nil and propose(next) then
					commit()
				end
				resync()
			end,
		}
		return UI.NumberInput(props)
	end
	local function fieldsRow(fields: { Shared.Child }): Frame
		local row = ctx.row(fields, { Name = "Fields", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y })
		assert(row:FindFirstChildWhichIsA("UIListLayout")).HorizontalFlex = E.UIFlexAlignment.Fill
		return row
	end
	local function rgbFields(): Frame
		local function channel(index: number, words: string): GuiObject
			return numberField(`Field{words}`, words, 255, function(value: Color3): number
				return (select(index, color.channels(value)))
			end, function(n: number): Hsv?
				local r, g, b = color.channels(held:peek() or color.toColor(canon:peek()))
				local bytes = { r, g, b }
				bytes[index] = n
				return color.hsvOf(color.fromBytes(bytes[1], bytes[2], bytes[3]), canon:peek())
			end)
		end
		return fieldsRow({ channel(1, "R"), channel(2, "G"), channel(3, "B") })
	end
	local function hsvFields(): Frame
		local function channel(key: "h" | "s" | "v", words: string, max: number): GuiObject
			return numberField(`Field{words}`, words, max, function(_: Color3, c: Hsv): number
				local amount = if key == "h" then c.h elseif key == "s" then c.s else c.v
				return math.floor(amount * max + 0.5)
			end, function(n: number): Hsv?
				local c = table.clone(canon:peek())
				if key == "h" then
					c.h = n / max
				elseif key == "s" then
					c.s = n / max
				else
					c.v = n / max
				end
				return c
			end)
		end
		return fieldsRow({ channel("h", "H", 360), channel("s", "S", 100), channel("v", "V", 100) })
	end
	local function hexFields(): Frame
		local text = Compose.cell("")
		local function formatted(): string
			local value = held:peek()
			return if value == nil then "" else color.hex(value, if hasAlpha then alphaHeld:peek() else nil)
		end
		Compose.watch(function(use: Use)
			use(held)
			use(alphaHeld)
			use(formatCell)
			text:set(formatted())
			hexError:set("")
		end)
		local props: InputProps.TextInputProps = {
			Name = "FieldHex",
			label = "Hex",
			value = text,
			errorText = hexError,
			Size = D2.fromScale(1, 0),
			AutomaticSize = E.AutomaticSize.Y,
			enabled = function(use: Use): boolean
				return interactive(use)
			end,
			onCommit = function(typed: string)
				local parsed, a, why = color.parseHex(typed, hasAlpha)
				if parsed == nil then
					hexError:set(why or "Check this colour.")
					return
				end
				hexError:set("")
				local moved = propose(color.hsvOf(parsed, canon:peek()))
				if a ~= nil then
					moved = state.proposeAlpha(a) or moved
				end
				if moved then
					commit()
				end
				text:set(formatted())
			end,
		}
		return fieldsRow({ UI.TextInput(props) })
	end
	local function readoutView(): Frame
		local builders: { [string]: () -> Frame } = { rgb = rgbFields, hsv = hsvFields, hex = hexFields }
		local values: Shared.FrameNativeProps = {
			Name = "Values",
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}
		for _, format in FORMATS do
			local visited = Compose.cell(formatCell:peek() == format.value)
			if not visited:peek() then
				Compose.watch(function(use: Use)
					if use(formatCell) == format.value then
						visited:set(true)
					end
				end)
			end
			values[#values + 1] = Host.CanvasGroup("Fields" .. format.label)({
				BackgroundTransparency = 1,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				GroupTransparency = function(use: Use): number
					return if use(formatCell) == format.value then 0 else 1
				end,
				Interactable = function(use: Use): boolean
					return use(formatCell) == format.value
				end,
				Compose.show(visited, function()
					local fields = builders[format.value]()
					fields.Name = "Content"
					return fields
				end),
			})
		end
		local valuesNode = Host.Frame(values)
		local formatProps: NavigationProps.SinglePickerSpec<string> = {
			Name = "Format",
			selected = formatCell,
			style = "segmented" :: "segmented",
			options = FORMATS,
			Size = D2.fromOffset(0, CELL),
			AutomaticSize = E.AutomaticSize.X,
		}
		local picker = UI.Picker(formatProps)
		runtime.mount(function()
			return Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill })
		end, picker)
		local head = ctx.row({
			kit.swatch("Preview", D2.fromOffset(2 * CELL + GAP, CELL), state.currentPaint),
			picker,
		}, { Name = "Head", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y })
		assert(head:FindFirstChildWhichIsA("UIListLayout")).VerticalAlignment = E.VerticalAlignment.Center
		return ctx.column(
			{ head, valuesNode },
			{ Name = "Readout", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y }
		)
	end

	return readoutView
end
