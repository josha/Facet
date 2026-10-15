--!strict

local Case = require("../lib/case")
local Cli = require("../lib/cli")
local DocsIndex = require("../lib/docs_index")
local Project = require("../lib/project")

local USAGE = [[usage: lute run tools/facet docs [name...] [--full] [--outline] [--search TEXT] [--list] [--json]

Prints only the documentation that a task needs. Read a section here instead of
the whole API reference. With no name, prints project files, task recipes,
typed state and control call shapes in one bounded response.

  <name>         A control, function or topic heading, for example Button, Sheet,
                 Mounting, Toast or "Text fit". Prints that section and its
                 subsections. Give several names to print several sections.
                 Long sections print a short excerpt and subsection names.
                 Query a subsection for details, or use --full for the full text.
  --full         Print full sections without the default 2400-token text budget.
  --outline      With a name, prints the subsection headings and their sizes only.
  --search TEXT  Lists the sections that mention TEXT, most mentions first.
  --list         Lists every section heading with its file and size in tokens.

Examples:
  lute run tools/facet docs Button Sheet
  lute run tools/facet docs Table --outline
  lute run tools/facet docs --search MaxVisibleGraphemes]]

local function heading(section: DocsIndex.Section): string
	return ("%s %s  (%s#%s, %d tokens)"):format(
		string.rep("#", section.level),
		section.title,
		section.file,
		section.anchor,
		DocsIndex.tokens(section.body)
	)
end

local function show(sections: { DocsIndex.Section }, name: string, outline: boolean, budget: number?): (boolean, string)
	local matches = DocsIndex.find(sections, name)
	if #matches == 0 then
		local near = DocsIndex.search(sections, name, 5)
		if #near == 0 then
			for word in string.gmatch(name, "%w+") do
				if #word > 3 then
					near = DocsIndex.find(sections, word)
					if #near > 0 then
						break
					end
				end
			end
		end
		local lines = { ("facet docs: no section is named '%s'."):format(name) }
		if #near > 0 then
			table.insert(lines, "Closest sections:")
			for index, match in near do
				if index > 5 then
					break
				end
				table.insert(lines, "  " .. heading(match.section))
			end
		end
		table.insert(lines, "Start with: lute run tools/facet docs (task recipes and call shapes).")
		return true, table.concat(lines, "\n")
	end
	local chosen = matches[1].section
	local text = DocsIndex.extent(sections, chosen)
	local lines: { string } = {}
	local bounded = budget ~= nil and DocsIndex.tokens(text) > math.min(budget, 1200)
	if bounded then
		table.insert(lines, `facet docs: {chosen.title} excerpt; query a subsection, or use --full.`)
		if not outline then
			local excerpt: { string } = {}
			local fenced = false
			local size = 0
			for _, line in string.split(chosen.body, "\n") do
				if size + #line > math.min(1600, (budget or 2400) * 2) then
					break
				end
				table.insert(excerpt, line)
				size += #line + 1
				if string.match(line, "^%s*```") then
					fenced = not fenced
				end
			end
			if fenced then
				table.insert(excerpt, "```")
			end
			table.insert(lines, table.concat(excerpt, "\n"))
		end
	end
	if outline or bounded then
		local inside = false
		local count = 0
		for _, section in sections do
			if section == chosen then
				inside = true
			elseif inside and (section.file ~= chosen.file or section.level <= chosen.level) then
				break
			end
			if inside then
				count += 1
				if bounded and not outline and count > math.min(12, math.max(1, math.floor((budget or 2400) / 70))) then
					table.insert(lines, `More headings: lute run tools/facet docs "{chosen.title}" --outline`)
					break
				end
				table.insert(lines, heading(section))
			end
		end
	else
		table.insert(lines, ("<!-- %s#%s, %d tokens -->"):format(chosen.file, chosen.anchor, DocsIndex.tokens(text)))
		table.insert(lines, text)
	end
	local others: { string } = {}
	for index = 2, math.min(#matches, 4) do
		if matches[index].score >= 50 then
			table.insert(others, heading(matches[index].section))
		end
	end
	if #others > 0 then
		table.insert(lines, "")
		table.insert(lines, "Other sections with this name:")
		for _, other in others do
			table.insert(lines, "  " .. other)
		end
	end
	return true, table.concat(lines, "\n")
end

local function run(invocation: Cli.Invocation): number
	local unknown = Cli.unknownFlags(invocation, { "search", "list", "outline", "full" })
	local search = Cli.flag(invocation, "search")
	local list = Cli.switch(invocation, "list")
	if unknown ~= nil then
		if unknown ~= nil then
			print("facet docs: unknown flags " .. unknown)
		end
		print(USAGE)
		return 2
	end
	local sections = DocsIndex.load(".")
	if #sections == 0 then
		print("facet docs: no documentation found under docs/")
		return 1
	end
	if #invocation.positional == 0 and search == nil and not list then
		print(Project.report())
		local start = DocsIndex.find(sections, "Start a game screen")[1]
		if start == nil then
			print("facet docs: start guide is missing; reinstall the author kit")
			return 1
		end
		print(DocsIndex.extent(sections, start.section))
		return 0
	end
	if list then
		local lines: { string } = {}
		for _, section in sections do
			table.insert(lines, heading(section))
		end
		print(table.concat(lines, "\n"))
		return 0
	end
	if search ~= nil then
		local matches = DocsIndex.search(sections, search, 15)
		if #matches == 0 then
			print(("facet docs: no section mentions '%s'"):format(search))
			print("Start with: lute run tools/facet docs")
			return 0
		end
		for _, match in matches do
			print(("%3d  %s"):format(match.score, heading(match.section)))
		end
		return 0
	end
	local failed = false
	local seen: { [string]: boolean } = {}
	local remaining = 2400
	for index, name in invocation.positional do
		if remaining <= 0 and not Cli.switch(invocation, "full") and not Cli.switch(invocation, "outline") then
			print("facet docs: response budget reached; query the remaining names in a separate call.")
			break
		end
		local found = DocsIndex.find(sections, name)
		local chosen = if #found > 0 then found[1].section else nil
		if chosen ~= nil then
			local key = chosen.file .. "#" .. chosen.anchor
			if seen[key] then
				continue
			end
			seen[key] = true
		end
		local ok, text = show(
			sections,
			name,
			Cli.switch(invocation, "outline"),
			if Cli.switch(invocation, "full") then nil else remaining
		)
		if
			not Cli.switch(invocation, "full")
			and not Cli.switch(invocation, "outline")
			and DocsIndex.tokens(text) > remaining
		then
			print(`facet docs: response budget reached; query "{name}" separately.`)
			break
		end
		remaining = math.max(0, remaining - DocsIndex.tokens(text))
		if index > 1 then
			print("")
		end
		print(text)
		failed = failed or not ok
	end
	return if failed then 1 else 0
end

local SAMPLE = table.concat({
	"# Sample",
	"## Actions",
	"### Button",
	"Press it.",
	"```luau",
	"# not a heading",
	"```",
	"#### Button icons",
	"Icons go here.",
	"### Toggle",
	"Flip it.",
	"## Media",
	"### Text",
	"Words. A Button can hold Text.",
}, "\n")

local function cases(): { Case.Case }
	return {
		{
			name = "a long contract gives a closed excerpt and scoped discovery while full text stays available",
			run = function()
				local source = "# Long\nA useful call shape.\n```luau\n"
					.. string.rep("local value = 1\n", 500)
					.. "```\n## Detail\nThe missing option."
				local sections = DocsIndex.parse("docs/reference/api.md", source)
				local _, short = show(sections, "Long", false, 2400)
				local _, full = show(sections, "Long", false)
				local fences = select(2, string.gsub(short, "```", ""))
				return Case.first(
					Case.expect(
						string.find(short, "A useful call shape.", 1, true) ~= nil,
						"the excerpt has no call shape"
					),
					Case.expect(string.find(short, "## Detail", 1, true) ~= nil, "scoped discovery is missing"),
					Case.equal(fences % 2, 0, "unclosed code fence"),
					Case.expect(#short < 4800, "the bounded response is too large"),
					Case.expect(
						string.find(full, "The missing option.", 1, true) ~= nil,
						"the full contract is missing"
					)
				)
			end,
		},
		{
			name = "a section holds its subsections and stops at the next peer heading",
			run = function()
				local sections = DocsIndex.parse("docs/reference/api.md", SAMPLE)
				local match = DocsIndex.find(sections, "Button")[1]
				local text = DocsIndex.extent(sections, match.section)
				return Case.first(
					Case.equal(#sections, 7, "sections"),
					Case.equal(match.section.title, "Button", "title"),
					Case.expect(string.find(text, "Icons go here.", 1, true) ~= nil, "the subsection is missing"),
					Case.expect(string.find(text, "# not a heading", 1, true) ~= nil, "the fenced line was dropped"),
					Case.expect(string.find(text, "Flip it.", 1, true) == nil, "the peer section leaked in")
				)
			end,
		},
		{
			name = "a UI. prefix and case do not matter, and an exact title wins over a longer one",
			run = function()
				local sections = DocsIndex.parse("docs/reference/api.md", SAMPLE)
				local exact = DocsIndex.find(sections, "ui.button")
				return Case.first(
					Case.equal(exact[1].section.title, "Button", "first"),
					Case.equal(exact[2].section.title, "Button icons", "second")
				)
			end,
		},
		{
			name = "search ranks sections by mentions",
			run = function()
				local sections = DocsIndex.parse("docs/reference/api.md", SAMPLE)
				local found = DocsIndex.search(sections, "button", 10)
				return Case.first(
					Case.expect(#found >= 2, "search found too little"),
					Case.equal(found[1].section.title, "Button", "best match")
				)
			end,
		},
		{
			name = "the repository reference answers the common control names",
			run = function()
				local sections = DocsIndex.load(".")
				for _, name in { "Button", "Sheet", "Toast", "VirtualList", "Mounting", "Text", "TabView" } do
					local found = DocsIndex.find(sections, name)
					if #found == 0 or found[1].section.file ~= "docs/reference/api.md" then
						return `{name} does not resolve to the API reference`
					end
					if DocsIndex.tokens(DocsIndex.extent(sections, found[1].section)) > 12000 then
						return `{name} prints more than 12000 tokens`
					end
				end
				return nil
			end,
		},
		{
			name = "an unknown name suggests sections without a command failure",
			run = function()
				local ok, text = show(DocsIndex.parse("docs/reference/api.md", SAMPLE), "Words", false)
				return Case.first(
					Case.expect(ok, "an unknown name failed"),
					Case.expect(string.find(text, "### Text", 1, true) ~= nil, "the mention is not listed")
				)
			end,
		},
	}
end

local command: Cli.Command = {
	name = "docs",
	summary = "Print the documentation section of a control or topic, or search the documentation.",
	usage = USAGE,
	values = { "search" },
	cases = cases,
	run = run,
}

return command
