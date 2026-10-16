--!strict
local Analyzer = require("./analyzer")
local Luau = require("./luau")
local Files = require("./files")

export type Finding = {
	rule: string,
	message: string,
	hint: string?,
	severity: "error" | "warning",
	location: string,
}

local Static = {}

function Static.option(message: string): string?
	return string.match(message, "^Expected this to be 'EventKey | number', but got '\"([^\"]+)\"'")
end

function Static.layoutHint(option: string): string?
	if option == "width" then
		return 'width belongs to containers. For cross-axis width use align = "stretch" on the parent VStack; for main-axis width put UI.fill() inside the child of an HStack. For explicit width use Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y. Read docs Layout-options.'
	elseif option == "height" then
		return 'height belongs to containers. For cross-axis height use align = "stretch" on the parent HStack; for main-axis height put UI.fill() inside the child of a VStack. For explicit height use Size = UDim2.fromOffset(0, 48), AutomaticSize = Enum.AutomaticSize.X. For a fixed box set Size and AutomaticSize = Enum.AutomaticSize.None. Read docs Layout-options.'
	elseif option == "gap" then
		return "gap belongs to containers. Put gap on the parent VStack or HStack; it sets UIListLayout.Padding between children. Read docs Layout-options."
	elseif option == "padding" then
		return "padding belongs to containers. Put padding on the parent stack. For padding inside a leaf, add Host.UIPadding { PaddingLeft = UDim.new(0, 8) } as a child (local Host = app.runtime.constructors). Read docs Layout-options."
	elseif option == "align" then
		return "align belongs to containers. Put align on the parent VStack or HStack for cross-axis alignment through UIListLayout. For text inside a Text control, use textAlign. Read docs Layout-options."
	elseif option == "distribute" then
		return "distribute belongs to containers. Put distribute on the parent VStack or HStack for main-axis alignment and flex through UIListLayout. Read docs Layout-options."
	elseif option == "maxWidth" then
		return "maxWidth belongs to containers. Put it on the parent stack, or add Host.UISizeConstraint { MaxSize = Vector2.new(480, math.huge) } inside the leaf (local Host = app.runtime.constructors). Read docs Layout-options."
	end
	return nil
end

function Static.render(findings: { Finding }, warningCounts: boolean?): { string }
	local groups: { { Finding } } = {}
	local byKey: { [string]: { Finding } } = {}
	for _, finding in findings do
		local key = table.concat({ finding.severity, finding.rule, finding.message, finding.hint or "" }, "\0")
		local group = byKey[key]
		if group == nil then
			group = {}
			byKey[key] = group
			table.insert(groups, group)
		end
		table.insert(group, finding)
	end
	local lines: { string } = {}
	for _, group in groups do
		local first = group[1]
		if warningCounts and first.severity == "warning" then
			table.insert(lines, `warning [{first.rule}] {#group} finding(s); read artifacts/facet-lint/report.txt`)
			continue
		end
		local message = first.message
		if #message > 600 then
			message = string.sub(message, 1, 400) .. " ... [shortened]"
		end
		table.insert(lines, `{first.severity} [{first.rule}] {message} ({#group} finding(s))`)
		if first.hint then
			table.insert(lines, "    hint: " .. first.hint)
		end
		for index = 1, math.min(5, #group) do
			table.insert(lines, "    " .. group[index].location)
		end
		if #group > 5 then
			table.insert(lines, `    and {#group - 5} more`)
		end
	end
	return lines
end

local function contains(location: Luau.Location, diagnostic: Analyzer.Diagnostic): boolean
	return (
		diagnostic.line > location.beginLine
		or (diagnostic.line == location.beginLine and diagnostic.column >= location.beginColumn)
	)
		and (
			diagnostic.line < location.endLine
			or (diagnostic.line == location.endLine and diagnostic.column < location.endColumn)
		)
end

function Static.cascades(diagnostics: { Analyzer.Diagnostic }, sources: { [string]: string }): { [number]: boolean }
	local hidden: { [number]: boolean } = {}
	local function identity(file: string): string
		local absolute = Files.absolute(file)
		return if string.match(absolute, "^%a:/") then string.lower(absolute) else absolute
	end
	local names: { [Analyzer.Diagnostic]: string } = {}
	for _, diagnostic in diagnostics do
		names[diagnostic] = identity(diagnostic.file)
	end
	for file, source in sources do
		local key = identity(file)
		local parsed = Luau.parse(source)
		if parsed == nil then
			continue
		end
		for _, call in Luau.calls(parsed) do
			local location = Luau.location(call.node)
			local overload = false
			for _, diagnostic in diagnostics do
				if
					names[diagnostic] == key
					and diagnostic.line == location.beginLine
					and diagnostic.column == location.beginColumn
					and string.find(diagnostic.message, "Available overloads: (StackProps)", 1, true)
				then
					overload = true
				end
			end
			if not overload then
				continue
			end
			local explained = false
			for _, argument in call.arguments do
				if Luau.tag(argument) ~= "table" then
					continue
				end
				for _, entry in Luau.items(argument, "entries") do
					local value = Luau.child(entry, "value")
					if Luau.kind(entry) ~= "list" or value == nil then
						continue
					end
					for _, diagnostic in diagnostics do
						if
							names[diagnostic] == key
							and Static.option(diagnostic.message) ~= nil
							and contains(Luau.location(value), diagnostic)
						then
							explained = true
						end
					end
				end
			end
			if explained then
				for index, diagnostic in diagnostics do
					if
						names[diagnostic] == key
						and diagnostic.line == location.beginLine
						and diagnostic.column == location.beginColumn
						and (
							string.find(diagnostic.message, "None of the overloads", 1, true) == 1
							or string.find(diagnostic.message, "Available overloads: (StackProps)", 1, true) == 1
						)
					then
						hidden[index] = true
					end
				end
			end
		end
	end
	return hidden
end

return table.freeze(Static)
