--!strict
return {
	{
		id = "haptics-requests-after-real-input",
		contracts = { "risk:haptics" },
		run = function(t)
			local built = t.held()
			if not built then
				t.check("feedback demo held from haptics_setup", false)
				return
			end
			local history = built.steps.readHistory()
			local kinds = {}
			for _, line in history do
				local kind = string.match(line, "%d+%. (%a+)")
				if kind then
					kinds[kind] = true
				end
			end
			t.note("history", history)
			t.note("report", built.report())
			for _, kind in { "press", "release", "selection", "custom" } do
				t.check(`{kind} feedback requested by real input`, kinds[kind] == true, history)
			end
			local haptics = game:GetService("HapticService")
			local motors = {}
			for _, input in { Enum.UserInputType.Gamepad1, Enum.UserInputType.Touch } do
				local ok, supported = pcall(function()
					return haptics:IsVibrationSupported(input)
				end)
				motors[tostring(input)] = if ok then supported else "unavailable"
			end
			t.note("host vibration support", motors)
			t.check("motor output is not claimed by Studio", built.report().motorConfirmed == false)
		end,
	},
}
