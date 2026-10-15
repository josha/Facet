--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type StringCell = typeof(require("@repo/tools/typecheck/aliases").StringCell)
type RobloxTypes = typeof(require("@repo/tools/typecheck/aliases").RobloxTypes)
type Runtime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type MotionLevel = typeof(require("@repo/examples/types").MotionLevel)
type Cell<T> = Readable<T> & { set: (Cell<T>, T) -> (), update: (Cell<T>, (T) -> T) -> () }
type InputChoice = {
	preferredInput: string,
	mouseEnabled: boolean,
	keyboardEnabled: boolean,
	touchEnabled: boolean,
	gamepadEnabled: boolean,
}
type Device = { logical: { width: number, height: number }, scale: number, fit: number, simulated: boolean }
export type Settings = {
	cells: { [string]: StringCell },
	CHOICES: { [string]: { string } },
	transparency: Readable<number>,
	hover: Readable<boolean>,
	scale: Readable<number>,
	viewport: Cell<Vector2?>,
	environment: typeof(require("@repo/tools/typecheck/aliases").ControlOptions.environment),
	device: (Use, { width: number, height: number }) -> Device,
	set: (string, string) -> { [string]: string | boolean },
	reset: () -> (),
	lines: Readable<string>,
	status: () -> { [string]: string },
}

export type Context = {
	Compose: ComposeModule,
	types: RobloxTypes,
	runtime: Runtime,
	guiService: GuiService,
	viewingDistance: StringCell,
	previewScale: Readable<number>,
	motionPreference: Cell<MotionLevel?>,
	motionLevel: Readable<MotionLevel>,
}

local lab_settings = {}

local PRESETS: { [string]: { w: number, h: number } } = {
	desktop = { w = 1440, h = 900 },
	tablet = { w = 1180, h = 820 },
	phone = { w = 844, h = 390 },
	tv = { w = 1920, h = 1080 },
}
lab_settings.CHOICES = {
	platform = { "automatic", "desktop", "tablet", "phone", "tv" },
	orientation = { "automatic", "landscape", "portrait" },
	distance = { "automatic", "near", "ten-foot" },
	motion = { "automatic", "normal", "limited", "none" },
	transparency = { "automatic", "default", "reduced", "opaque" },
	hover = { "automatic", "on", "off" },
	input = { "automatic", "pointer", "touch", "gamepad" },
	text = { "automatic", "Medium", "Large", "Larger", "Largest" },
}

local INPUT: { [string]: InputChoice } = {
	pointer = {
		preferredInput = "KeyboardAndMouse",
		mouseEnabled = true,
		keyboardEnabled = true,
		touchEnabled = false,
		gamepadEnabled = false,
	},
	touch = {
		preferredInput = "Touch",
		mouseEnabled = false,
		keyboardEnabled = false,
		touchEnabled = true,
		gamepadEnabled = false,
	},
	gamepad = {
		preferredInput = "Gamepad",
		mouseEnabled = false,
		keyboardEnabled = false,
		touchEnabled = false,
		gamepadEnabled = true,
	},
}
local DEVICE_INPUT = { phone = "touch", tablet = "touch", desktop = "pointer", tv = "gamepad" }
local DISPLAY = { phone = "Small", tablet = "Medium", desktop = "Medium", tv = "Large" }
local TRANSPARENCY = { default = 1, reduced = 0.5, opaque = 0 }

function lab_settings.new(ctx: Context, input: UserInputService): Settings
	local Compose: ComposeModule = ctx.Compose
	local Enum = ctx.types.Enum
	local gui = ctx.guiService
	local cells: { [string]: StringCell } = {
		platform = Compose.cell("automatic"),
		orientation = Compose.cell("automatic"),
		distance = ctx.viewingDistance,
		motion = Compose.cell("automatic"),
		transparency = Compose.cell("automatic"),
		hover = Compose.cell("automatic"),
		input = Compose.cell("automatic"),
		text = Compose.cell("automatic"),
	}

	local function live<T>(object: Instance, property: string, read: () -> T): Cell<T>
		local value = Compose.cell(read())
		local connection = object:GetPropertyChangedSignal(property):Connect(function()
			value:set(read())
		end)
		Compose.cleanup(function()
			connection:Disconnect()
		end)
		return value
	end
	local realTransparency = live(gui, "PreferredTransparency", function()
		return gui.PreferredTransparency
	end)
	local realInput = live(input, "PreferredInput", function()
		return input.PreferredInput
	end)
	local realText = live(gui, "PreferredTextSize", function()
		return gui.PreferredTextSize
	end)

	local function effectiveInput(use: Use): string
		local choice = use(cells.input)
		return if choice == "automatic" then DEVICE_INPUT[use(cells.platform)] or "automatic" else choice
	end
	local self = ({ cells = cells, CHOICES = lab_settings.CHOICES } :: unknown) :: Settings
	self.transparency = Compose.formula(function(use: Use)
		local choice = use(cells.transparency)
		return if choice == "automatic" then use(realTransparency) else TRANSPARENCY[choice]
	end)
	self.hover = Compose.formula(function(use: Use)
		local choice = use(cells.hover)
		if choice ~= "automatic" then
			return choice == "on"
		end

		local forced = effectiveInput(use)
		return if forced ~= "automatic" then forced ~= "touch" else use(realInput) ~= Enum.PreferredInput.Touch
	end)

	self.scale = ctx.previewScale

	self.viewport = Compose.cell(nil :: Vector2?)

	local function forced<T>(read: (InputChoice) -> T): (Use) -> T?
		return function(use: Use): T?
			local class = INPUT[effectiveInput(use)]
			return if class then read(class) else nil
		end
	end
	self.environment = {
		preferredInput = forced(function(choice)
			return choice.preferredInput
		end),
		mouseEnabled = forced(function(choice)
			return choice.mouseEnabled
		end),
		keyboardEnabled = forced(function(choice)
			return choice.keyboardEnabled
		end),
		touchEnabled = forced(function(choice)
			return choice.touchEnabled
		end),
		gamepadEnabled = forced(function(choice)
			return choice.gamepadEnabled
		end),
		preferredTextSize = function(use: Use): string?
			local text = use(cells.text)
			return if text == "automatic" then nil else text
		end,
		displaySize = function(use: Use): string?
			return DISPLAY[use(cells.platform)]
		end,
		viewportSize = function(use: Use): Vector2?
			return if use(cells.platform) == "automatic" then nil else use(self.viewport)
		end,
	}

	function self.device(use: Use, avail: { width: number, height: number })
		local platform, orientation, scale = use(cells.platform), use(cells.orientation), use(self.scale)
		if platform == "automatic" then
			return {
				logical = { width = avail.width / scale, height = avail.height / scale },
				scale = scale,
				fit = 1,
				simulated = false,
			}
		end
		local preset = PRESETS[platform]
		local w, h = preset.w, preset.h
		if orientation == "portrait" then
			w, h = h, w
		end
		local fit = math.min(1, avail.width / w, avail.height / h)
		return {
			logical = { width = math.floor(w / scale), height = math.floor(h / scale) },
			scale = scale * fit,
			fit = fit,
			simulated = true,
		}
	end

	function self.set(key: string, value: string)
		local cell = cells[key]
		if cell == nil or not table.find(lab_settings.CHOICES[key], value) then
			return { ok = false, reason = "unknown setting or value" }
		end
		ctx.runtime:batch(function()
			cell:set(value)
			if key == "motion" then
				ctx.motionPreference:set(if value == "automatic" then nil else value :: MotionLevel)
			elseif key == "platform" then
				cells.distance:set(if value == "tv" then "ten-foot" else "automatic")
			end
		end)
		return { ok = true, [key] = value }
	end

	function self.reset()
		ctx.runtime:batch(function()
			for key in cells do
				self.set(key, "automatic")
			end
		end)
	end

	self.lines = Compose.formula(function(use: Use)
		local function word(v: unknown): string
			return (string.gsub(tostring(v), "^Enum%.%w+%.", ""))
		end
		local out = {}
		local platform = use(cells.platform)
		table.insert(
			out,
			if platform == "automatic"
				then "Screen: this window (real)"
				else `Screen: {platform} {use(cells.orientation)} — simulated frame and viewport, including overlays`
		)
		table.insert(
			out,
			if use(cells.distance) == "automatic"
				then "Viewing distance: near (real)"
				else `Viewing distance: {use(cells.distance)} — simulated scale {use(self.scale)}×`
		)
		local input = effectiveInput(use)
		table.insert(
			out,
			if input == "automatic"
				then `Input: {word(use(realInput))} (real)`
				else `Input: {input} — simulated; the device reports {word(use(realInput))} (its real input still arrives)`
		)
		local text = use(cells.text)
		table.insert(
			out,
			if text == "automatic"
				then `Text size: {word(use(realText))} (real)`
				else `Text size: {text} — simulated for Facet's text decisions; the engine still renders {word(
					use(realText)
				)}`
		)
		local display = DISPLAY[platform]
		table.insert(out, if display then `Display size: {display} — simulated` else "Display size: real")
		local level = use(ctx.motionLevel)
		table.insert(out, `Motion: {level}{if use(cells.motion) == "automatic" then " (real)" else " — simulated"}`)
		table.insert(
			out,
			`Transparency: {use(self.transparency)}{if use(cells.transparency) == "automatic"
				then " (real)"
				else " — simulated"}`
		)
		table.insert(
			out,
			`Hover paint: {if use(self.hover) then "on" else "off"}{if use(cells.hover) == "automatic"
				then " (automatic)"
				else " — forced"}`
		)
		return table.concat(out, "\n")
	end)

	function self.status(): { [string]: string }
		local out: { [string]: string } = { lines = self.lines:peek() }
		for key, cell in cells do
			out[key] = cell:peek()
		end
		return out
	end
	return self
end

return lab_settings
