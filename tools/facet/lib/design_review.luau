--!strict
local Audit = require("../../vendor/verify/src/roblox/ui-audit")
local Rules = require("../../../src/ui/review_rules")

export type Report = Rules.ReviewReport
export type Snapshot = Rules.ReviewSnapshot

local DesignReview = {}

function DesignReview.snapshot(dump: Audit.Dump): Snapshot
	local elements: { Rules.ReviewElement } = {}
	for _, element in dump.elements do
		local text: Rules.ReviewText? = nil
		local source = element.text
		if source ~= nil then
			local description: Rules.ReviewText = {
				content = source.content,
				size = source.size,
				bold = source.bold,
				font = source.font,
				color = source.color,
				transparency = source.transparency,
			}
			text = description
		end
		local image = element.image
		table.insert(elements, {
			index = element.index,
			parent = element.parent,
			class = element.class,
			path = element.path,
			rect = element.rect,
			visible = element.visible,
			interactive = element.interactive,
			fill = element.background.color,
			fillTransparency = element.background.transparency,
			image = element.class == "ViewportFrame" or (image ~= nil and image.transparency < 0.9),
			text = text,
		})
	end
	local input: { string } = dump.screen.input or {}
	return {
		width = dump.screen.width,
		height = dump.screen.height,
		elements = elements,
		touch = table.find(input, "touch") ~= nil,
	}
end

function DesignReview.analyze(dump: Audit.Dump): Report
	return Rules.analyze(DesignReview.snapshot(dump))
end

function DesignReview.lines(report: Report, printed: { [string]: boolean }?, all: boolean?): { string }
	local lines: { string } = {}
	local order: { string } = {}
	local grouped: { [string]: { Rules.ReviewFinding } } = {}
	local shown = 0
	for _, finding in report.findings do
		if finding.severity == "low" and all == false then
			continue
		end
		shown += 1
		local list = grouped[finding.rule]
		if list == nil then
			list = {}
			grouped[finding.rule] = list
			table.insert(order, finding.rule)
		end
		table.insert(list, finding)
	end
	if #order == 0 then
		return lines
	end
	table.insert(
		lines,
		("  design (%d): patterns that make a screen look generic; they do not change the score"):format(shown)
	)
	for _, rule in order do
		local list = grouped[rule]
		local seen = printed ~= nil and printed["design:" .. rule] == true
		local fix = if seen then "" else ": " .. (Rules.fixes[rule] or "")
		table.insert(lines, ("    %s %s (%d)%s"):format(list[1].severity, rule, #list, fix))
		if printed ~= nil then
			printed["design:" .. rule] = true
		end
		for index, finding in list do
			if index > 3 then
				table.insert(lines, ("        ... %d more"):format(#list - 3))
				break
			end
			table.insert(lines, "        " .. finding.detail)
		end
	end
	return lines
end

DesignReview.fixes = Rules.fixes

return table.freeze(DesignReview)
