--!strict

local profiles = {
	{ name = "Phone", width = 390, height = 844, input = "Touch", display = "Small", distance = "near" },
	{ name = "Tablet", width = 820, height = 1180, input = "Touch", display = "Medium", distance = "near" },
	{ name = "Desktop", width = 1280, height = 800, input = "KeyboardAndMouse", display = "Medium", distance = "near" },
	{ name = "Television", width = 1920, height = 1080, input = "Gamepad", display = "Large", distance = "ten-foot" },
}

return table.freeze(profiles)
