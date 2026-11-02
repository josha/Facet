--!strict
local Dates = require("../../src/ui/date_time_picker_types")
local DatesControls = require("../../src/ui/control_types")
local Compose = require("../../src/vendor/compose/core")

return function(UI: DatesControls.Controls): ()
	local noSession: Dates.CivilDate? = nil
	local session = Compose.cell(noSession)
	local single: Frame = UI.DateTimePicker "Session" {
		label = "Play session",
		time = true,
		minuteStep = 15,
		value = session,
		min = { year = 2026, month = 1, day = 1 },
		onChange = function(date: Dates.CivilDate?)
			session:set(date)
		end,
		onDismiss = function(reason: Dates.DismissReason)
			local closed: string = reason
			assert(closed ~= "")
		end,
	}
	local noTrip: Dates.Range = {}
	local trip: Compose.Value<Dates.Range> = Compose.cell(noTrip)
	local range: Frame = UI.DateTimePicker {
		selection = "range",
		range = trip,
		onRangeChange = function(next: Dates.Range)
			trip:set(next)
		end,
		presets = {
			{
				id = "week",
				label = "Next 7 days",
				range = function(today: Dates.CivilDate): Dates.Range
					return { start = today, finish = today }
				end,
			},
		},
	}
	single.Name, range.Name = "Single", "Range"
end
