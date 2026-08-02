local text_metrics = require("../../src/layout/text_metrics")
for _, w in { 100, 112, 119, 120, 121, 130, 200, 328 } do
	local m = text_metrics.measure("Save changes", "audit", 16, w, 1.2)
	print(w, m.width, m.height, m.lines)
end
local m = text_metrics.measure("Save changes", "audit", 16, math.huge, 1.2)
print("huge", m.width, m.height, m.lines)
