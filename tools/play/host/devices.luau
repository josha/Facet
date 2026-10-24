--!strict

export type Mode = "touch" | "mouse" | "gamepad"

export type Device = {
	id: string,
	preset: string,
	orientation: ("portrait" | "landscape")?,
	mode: Mode,
	input: { string },
	width: number,
	height: number,
	real: string,
	approximated: string,
}

local LIST: { Device } = {
	{
		id = "desktop",
		preset = "hd_1080",
		orientation = nil,
		mode = "mouse",
		input = { "mouse", "keyboard" },
		width = 1920,
		height = 1080,
		real = "The Studio Device Simulator preset hd_1080 sets the 1920 x 1080 viewport. Clicks and keys are engine VirtualInput events.",
		approximated = "The Studio window scales the view to fit, so the capture can be smaller than 1920 x 1080.",
	},
	{
		id = "phone-portrait",
		preset = "iphone_14",
		orientation = "portrait",
		mode = "touch",
		input = { "touch" },
		width = 390,
		height = 844,
		real = "The preset iphone_14 in portrait sets the screen size, the notch and home indicator insets and TouchEnabled. The simulator turns VirtualInput mouse events into Touch input.",
		approximated = "A tap is a mouse press that the simulator converts. A swipe is a mouse drag. There is no multi-touch, IME or on-screen keyboard.",
	},
	{
		id = "phone-landscape",
		preset = "iphone_14",
		orientation = "landscape",
		mode = "touch",
		input = { "touch" },
		width = 844,
		height = 390,
		real = "The preset iphone_14 in landscape sets the screen size, the side insets and TouchEnabled. The simulator turns VirtualInput mouse events into Touch input.",
		approximated = "A tap is a mouse press that the simulator converts. A swipe is a mouse drag. There is no multi-touch, IME or on-screen keyboard.",
	},
	{
		id = "tablet",
		preset = "ipad_10th_generation",
		orientation = "landscape",
		mode = "touch",
		input = { "touch" },
		width = 1180,
		height = 820,
		real = "The preset ipad_10th_generation in landscape sets the screen size and TouchEnabled. The simulator turns VirtualInput mouse events into Touch input.",
		approximated = "A tap is a mouse press that the simulator converts. A swipe is a mouse drag.",
	},
	{
		id = "console",
		preset = "xbox",
		orientation = nil,
		mode = "gamepad",
		input = { "gamepad" },
		width = 1920,
		height = 1080,
		real = "The preset xbox sets a 1920 x 1080 console viewport without touch. Engine selection navigation (GuiService.SelectedObject) moves and activates the controls.",
		approximated = "Arrow keys stand for the D-pad and Return stands for the A button. Record the observed input flags; the simulator can report GamepadEnabled without physical gamepad input. When nothing is selected, GuiService:Select(PlayerGui) stands for automatic selection. These actions do not test physical gamepad buttons or a view from 3 meters.",
	},
}

local BY_ID: { [string]: Device } = {}
for _, device in LIST do
	BY_ID[device.id] = device
end

local function get(id: string): Device
	local device = BY_ID[id]
	if device == nil then
		error("unknown device " .. id, 0)
	end
	return device
end

return {
	list = LIST,
	get = get,
}
