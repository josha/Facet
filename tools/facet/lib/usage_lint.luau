--!strict

export type Severity = "error" | "warning"

export type Finding = {
	rule: string,
	severity: Severity,
	file: string,
	line: number,
	text: string,
	message: string,
}

type Rule = {
	id: string,
	severity: Severity,
	patterns: { string },
	message: string,
	facetOnly: boolean?,
}

local UsageLint = {}

local GUI_CLASSES = {
	"Frame",
	"TextLabel",
	"TextButton",
	"TextBox",
	"ImageLabel",
	"ImageButton",
	"ScrollingFrame",
	"ScreenGui",
	"UIListLayout",
	"UIGridLayout",
	"UICorner",
	"UIStroke",
	"UIPadding",
}

local RULES: { Rule } = {
	{
		id = "any-cast",
		severity = "error",
		patterns = { "::%s*any%f[^%w_]" },
		message = 'Remove the any cast. The named form UI.Control "Name" { ... } type-checks every option.',
	},
	{
		id = "reserved-key",
		severity = "error",
		patterns = { "Enum%.KeyCode%.Escape", "Enum%.KeyCode%.ButtonStart" },
		message = "Roblox reserves Escape and the gamepad Start button for its menu. Bind another key, or let the control own Back and Cancel.",
	},
	{
		id = "deprecated-scheduler",
		severity = "error",
		patterns = { "%f[%w_.:]wait%s*%(", "%f[%w_.:]spawn%s*%(", "%f[%w_.:]delay%s*%(" },
		message = "Use task.wait, task.spawn and task.delay, or a Compose watch or runtime.tween for interface timing.",
	},
	{
		id = "dot-cell-method",
		severity = "warning",
		patterns = { "[%w_%]%)]%.set%s*%(", "[%w_%]%)]%.update%s*%(", "[%w_%]%)]%.peek%s*%(" },
		message = "Call cell methods with a colon: cell:set(value), cell:update(fn), cell:peek().",
	},
	{
		id = "native-gui-object",
		severity = "warning",
		patterns = {},
		message = "Make interface objects with a Facet control or Host.<Class> { ... } (Host = app.runtime.constructors), not Instance.new. Compose then owns their lifetime.",
		facetOnly = true,
	},
	{
		id = "literal-paint",
		severity = "warning",
		patterns = { "Color3%.fromRGB%s*%(", "Color3%.new%s*%(", "Color3%.fromHex%s*%(" },
		message = "Let the theme paint controls: use appearance, tone and textRole. Put a game color in a theme package, not in a control.",
		facetOnly = true,
	},
	{
		id = "literal-font",
		severity = "warning",
		patterns = { "Enum%.Font%.", "Font%.new%s*%(", "Font%.fromEnum%s*%(", "TextScaled%s*=%s*true" },
		message = "Use textRole (title, heading, body, caption) so that the theme sets the font and size, and text fit keeps it readable.",
		facetOnly = true,
	},
	{
		id = "literal-motion",
		severity = "warning",
		patterns = { "TweenInfo%.new%s*%(", "TweenService" },
		message = "Motion timing belongs to the theme. Use the control motion, runtime.tween with a theme motion token, or runtime.spring.",
		facetOnly = true,
	},
	{
		id = "device-branch",
		severity = "warning",
		patterns = {
			"%.TouchEnabled",
			"%.GamepadEnabled",
			"%.KeyboardEnabled",
			"IsTenFootInterface",
			"GetLastInputType",
		},
		message = "Do not branch on the device. Read UI.environment (viewport class, input class, safe insets) or use an adaptive control.",
		facetOnly = true,
	},
	{
		id = "raw-input",
		severity = "warning",
		patterns = { "UserInputService%.InputBegan", "ContextActionService" },
		message = "Let controls own activation, Back and Cancel. For a game shortcut, read the docs for commandScope and Facet.inputPriority.",
		facetOnly = true,
	},
}

for _, rule in RULES do
	if rule.id == "native-gui-object" then
		for _, class in GUI_CLASSES do
			table.insert(rule.patterns, 'Instance%.new%s*%(%s*"' .. class .. '"')
		end
	end
end

local function stripped(line: string): string
	local code = string.gsub(line, "%-%-.*$", "")
	code = string.gsub(code, '"[^"]*"', '""')
	code = string.gsub(code, "'[^']*'", "''")
	code = string.gsub(code, "`[^`]*`", "``")
	return code
end

local function usesFacet(source: string): boolean
	return string.find(source, "Facet", 1, true) ~= nil or string.find(source, "UI%.%u") ~= nil
end

local function codeLines(source: string): { [number]: string }
	local code: { [number]: string } = {}
	local block = false
	for index, raw in string.split(string.gsub(source, "\r\n", "\n"), "\n") do
		if block then
			block = string.find(raw, "%]%]") == nil
		elseif string.find(raw, "^%s*%-%-%[%[") ~= nil then
			block = string.find(raw, "%]%]") == nil
		else
			code[index] = stripped(raw)
		end
	end
	return code
end

function UsageLint.usage(sources: { { file: string, source: string } }): { [string]: number }
	local counts: { [string]: number } = {}
	local function add(name: string)
		counts[name] = (counts[name] or 0) + 1
	end
	for _, entry in sources do
		local code = codeLines(entry.source)
		local aliases: { [string]: boolean } = { UI = true }
		for _, line in code do
			local alias = string.match(line, "local%s+([%w_]+)%s*=%s*[%w_%.]*%.UI%f[^%w_]")
				or string.match(line, "local%s+([%w_]+)%s*=%s*[%w_%.]*Facet%.controls%s*%(")
			if alias ~= nil then
				aliases[alias] = true
			end
		end
		for _, line in code do
			for owner, name in string.gmatch(line, "([%w_]+)%.([%a_][%w_]*)") do
				if aliases[owner] and name ~= nil then
					add("UI." .. name)
				end
			end
			for name in string.gmatch(line, "Facet%.format%.([%a_][%w_]*)") do
				add("Facet.format." .. tostring(name))
			end
			for name in string.gmatch(line, "Facet%.(%l[%w_]*)") do
				if name ~= nil and name ~= "format" then
					add("Facet." .. name)
				end
			end
		end
	end
	return counts
end

function UsageLint.controls(controlTypes: string): { string }
	local names: { string } = {}
	local inside = false
	for _, raw in string.split(string.gsub(controlTypes, "\r\n", "\n"), "\n") do
		if string.find(raw, "^export type Controls = {") ~= nil then
			inside = true
		elseif inside and string.find(raw, "^}") ~= nil then
			break
		elseif inside then
			local name = string.match(raw, "^\t([%a_][%w_]*):")
			if name ~= nil then
				table.insert(names, "UI." .. name)
			end
		end
	end
	table.sort(names)
	return names
end

function UsageLint.check(file: string, source: string): { Finding }
	local findings: { Finding } = {}
	local facet = usesFacet(source)
	local lines = string.split(string.gsub(source, "\r\n", "\n"), "\n")
	if not string.find(lines[1] or "", "^%-%-!strict") then
		local finding: Finding = {
			rule = "strict",
			severity = "error",
			file = file,
			line = 1,
			text = lines[1] or "",
			message = "Start the file with --!strict.",
		}
		table.insert(findings, finding)
	end
	local block = false
	for index, raw in lines do
		if block then
			if string.find(raw, "%]%]") ~= nil then
				block = false
			end
			continue
		end
		if string.find(raw, "^%s*%-%-%[%[") ~= nil then
			block = string.find(raw, "%]%]") == nil
			continue
		end
		local code = stripped(raw)
		for _, rule in RULES do
			if rule.facetOnly and not facet then
				continue
			end
			local subject = if rule.id == "native-gui-object" then string.gsub(raw, "%-%-.*$", "") else code
			for _, pattern in rule.patterns do
				if string.find(subject, pattern) ~= nil then
					local finding: Finding = {
						rule = rule.id,
						severity = rule.severity,
						file = file,
						line = index,
						text = (string.gsub(raw, "^%s+", "")),
						message = rule.message,
					}
					table.insert(findings, finding)
					break
				end
			end
		end
	end
	return findings
end

local ONE_TREE =
	"Create one runtime and mount one root. Make each screen, panel and overlay a Compose.show branch or a portal of that tree."

function UsageLint.project(sources: { { file: string, source: string } }): { Finding }
	local findings: { Finding } = {}
	local runtimes: { Finding } = {}
	local mounts: { Finding } = {}
	for _, entry in sources do
		local lines = string.split(string.gsub(entry.source, "\r\n", "\n"), "\n")
		local owners: { [string]: boolean } = {}
		for _, raw in lines do
			local code = stripped(raw)
			local name = string.match(code, "local%s+([%w_]+)%s*=%s*[%w_%.]*Facet%.app%s*%(")
				or string.match(code, "local%s+([%w_]+)%s*=%s*[%w_%.]*createRuntime%s*%(")
			if name ~= nil then
				owners[name] = true
			end
		end
		for index, raw in lines do
			local code = stripped(raw)
			local function note(list: { Finding }, rule: string, message: string)
				table.insert(list, {
					rule = rule,
					severity = "warning",
					file = entry.file,
					line = index,
					text = (string.gsub(raw, "^%s+", "")),
					message = message,
				})
			end
			if string.find(code, "Facet%.app%s*%(") ~= nil or string.find(code, "createRuntime%s*%(") ~= nil then
				note(runtimes, "one-runtime", "This project makes more than one runtime or app. " .. ONE_TREE)
			end
			for owner in string.gmatch(code, "([%w_]+)%.mount%s*%(") do
				if owners[owner] then
					note(mounts, "one-root", "This project mounts more than one root. " .. ONE_TREE)
				end
			end
		end
	end
	for _, list in { runtimes, mounts } do
		if #list > 1 then
			for _, finding in list do
				table.insert(findings, finding)
			end
		end
	end
	return findings
end

function UsageLint.rules(): { { id: string, severity: Severity, message: string } }
	local list: { { id: string, severity: Severity, message: string } } = {
		{ id = "strict", severity = "error", message = "Start the file with --!strict." },
		{ id = "one-runtime", severity = "warning", message = ONE_TREE },
		{ id = "one-root", severity = "warning", message = ONE_TREE },
	}
	for _, rule in RULES do
		table.insert(list, { id = rule.id, severity = rule.severity, message = rule.message })
	end
	return list
end

return table.freeze(UsageLint)
