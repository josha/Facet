--!strict
local Verify = require("../../vendor/verify/src/core")

local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Rule = require("../lib/rule")
local Run = require("../lib/run")
local Strip = require("../lib/strip")

type Change = { path: string, updated: string, line: number }

type Survey = { changes: { Change }, problems: { string } }

local FULL = { "tier:full" }

local SUFFIXES: { [string]: boolean } = { [".luau"] = true, [".lua"] = true, [".sh"] = true }

local function transform(source: string, relative: string): (string?, string?, number)
	local extension = Files.extension(relative)
	if extension == ".luau" or extension == ".lua" then
		return Strip.luau(source)
	elseif extension == ".sh" then
		return Strip.shell(source)
	end
	return source, nil, 0
end

local function sourcePaths(context: Rule.Context, selections: { string }): ({ string }?, string?)
	local arguments = { "-C", context.root, "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--" }
	for _, selection in selections do
		table.insert(arguments, selection)
	end
	local listed = Run.git(arguments)
	if not listed.ok then
		local message = string.gsub(listed.stderr, "%s+$", "")
		return nil, "cannot list the repository files: " .. message
	end
	local unique: { [string]: boolean } = {}
	local found: { string } = {}
	for _, relative in string.split(listed.stdout, "\0") do
		if relative == "" or unique[relative] then
			continue
		end
		unique[relative] = true
		if
			SUFFIXES[Files.extension(relative)]
			and not Files.vendored(relative)
			and Files.isFile(context.path(relative))
		then
			table.insert(found, relative)
		end
	end
	table.sort(found)
	return found, nil
end

local function survey(context: Rule.Context, selections: { string }): Survey
	local result: Survey = { changes = {}, problems = {} }
	local paths, problem = sourcePaths(context, selections)
	if paths == nil then
		table.insert(result.problems, problem or "cannot list the repository files")
		return result
	end
	for _, relative in paths do
		local original = Files.read(context.path(relative))
		if utf8.len(original) == nil then
			table.insert(result.problems, relative .. ": the file is not valid UTF-8")
			continue
		end
		local ok, updated, failure, line = pcall(transform, original, relative)
		if not ok then
			table.insert(result.problems, ("%s: %s"):format(relative, tostring(updated)))
		elseif updated == nil then
			table.insert(result.problems, ("%s: %s"):format(relative, failure or "cannot strip comments"))
		elseif updated ~= original then
			table.insert(result.changes, { path = relative, updated = updated, line = line })
		end
	end
	return result
end

local function check(context: Rule.Context): { string }
	local result = survey(context, {})
	local findings = table.clone(result.problems)
	for _, change in result.changes do
		table.insert(
			findings,
			("%s:%d: a comment that is not a directive or legal notice; run `lute run tools/facet check comments --write`"):format(
				change.path,
				change.line
			)
		)
	end
	return findings
end

local function selections(invocation: Cli.Invocation): { string }
	return invocation.repeated.path or {}
end

local function act(context: Rule.Context, invocation: Cli.Invocation, write: boolean): number
	local result = survey(context, selections(invocation))
	if #result.problems > 0 then
		for _, problem in result.problems do
			print("comments: " .. problem)
		end
		return 2
	end
	for _, change in result.changes do
		print(change.path)
		if write then
			Files.write(context.path(change.path), change.updated)
		end
	end
	print(("comments: %d file(s) %s"):format(#result.changes, if write then "updated" else "need changes"))
	return 0
end

local function equalText(actual: string?, expected: string, _label: string)
	Verify.expect(actual):toBe(expected)
end

local function contains(text: string?, fragment: string): boolean
	return text ~= nil and string.find(text, fragment, 1, true) ~= nil
end

local function luau(source: string): string?
	local result, problem = Strip.luau(source)
	if result == nil then
		error(problem or "cannot strip", 0)
	end
	return result
end

local function shell(source: string): string?
	local result, problem = Strip.shell(source)
	if result == nil then
		error(problem or "cannot strip", 0)
	end
	return result
end

local function bashOutput(script: string): string
	local result = Run.capture({ "bash", "-c", script }, { timeout = 60 })
	return ("%d:%s"):format(result.code, result.stdout)
end

local function sameBehavior(source: string, result: string?)
	Verify.expect(result):toBeOk()
	local before, after = bashOutput(source), bashOutput(assert(result))
	Verify.expect(string.sub(before, 1, 2)):toBe("0:")
	Verify.expect(after):toBe(before)
end

local function register(harness: Verify.Harness, prefix: string): ()
	harness:case(prefix .. "nested interpolation only strips expression comments", {
		id = prefix .. "nested interpolation only strips expression comments",
		run = function(test: Verify.Context)
			local source = "local s = `text -- literal {`nested {({ value = 4 -- remove\n }).value}`} end`\n"
			equalText(
				luau(source),
				"local s = `text -- literal {`nested {({ value = 4\n }).value}`} end`\n",
				"stripped"
			)
		end,
	})
	harness:case(prefix .. "strings, long brackets and escapes are unchanged", {
		id = prefix .. "strings, long brackets and escapes are unchanged",
		run = function(test: Verify.Context)
			local source = 'local a = "a\\"--b"\nlocal b = [==[--[[ ]]\n-- text\n]==]\nlocal c = `\\{--literal\\}`\n'
			equalText(luau(source), source, "stripped")
		end,
	})
	harness:case(prefix .. "long comments do not join tokens", {
		id = prefix .. "long comments do not join tokens",
		run = function(test: Verify.Context)
			equalText(luau("return not--[====[ ignored ]] ]=] ]====]bar\n"), "return not bar\n", "stripped")
		end,
	})
	harness:case(prefix .. "directives and legal blocks survive", {
		id = prefix .. "directives and legal blocks survive",
		run = function(test: Verify.Context)
			local result = luau(
				"--!strict\n--!native\n-- stylua: ignore\n-- theme_sync:begin metrics\n-- Copyright (c) 2026 Example\n-- All rights reserved.\n\n-- remove\nreturn {}\n"
			)
			Verify.expect(contains(result, "--!strict\n--!native\n-- stylua: ignore"))
				:toBeTrueWith("directives were removed")
			Verify.expect(contains(result, "-- All rights reserved.")):toBeTrueWith("the legal block was removed")
			Verify.expect(contains(result, "-- theme_sync:begin metrics"))
				:toBeTrueWith("the theme_sync marker was removed")
			Verify.expect(not contains(result, "-- remove")):toBeTrueWith("a plain comment survived")
		end,
	})
	harness:case(prefix .. "a licence notice protects the three comments before it", {
		id = prefix .. "a licence notice protects the three comments before it",
		run = function(test: Verify.Context)
			local source =
				"--!strict\n\n-- Source: list\n--   https://example.com\n--   SHA-256 0\n-- Licence and required notices: PROVENANCE.md\n\n-- remove\nreturn {}\n"
			equalText(
				luau(source),
				"--!strict\n\n-- Source: list\n--   https://example.com\n--   SHA-256 0\n-- Licence and required notices: PROVENANCE.md\n\n\nreturn {}\n",
				"stripped"
			)
		end,
	})
	harness:case(prefix .. "unclosed lexical constructs fail closed", {
		id = prefix .. "unclosed lexical constructs fail closed",
		run = function(test: Verify.Context)
			for _, source in { "--[=[oops", "[[oops", "local s = `a { b", 'local s = "oops' } do
				local result = Strip.luau(source)
				if result ~= nil then
					error(("%q was accepted"):format(source), 0)
				end
			end
		end,
	})
	harness:case(prefix .. "CRLF and string whitespace are preserved", {
		id = prefix .. "CRLF and string whitespace are preserved",
		run = function(test: Verify.Context)
			equalText(
				luau("local x = [[first   \r\nlast   ]] -- gone\r\n"),
				"local x = [[first   \r\nlast   ]]\r\n",
				"stripped"
			)
		end,
	})
	harness:case(prefix .. "a block comment before code on the same line leaves one space", {
		id = prefix .. "a block comment before code on the same line leaves one space",
		run = function(test: Verify.Context)
			equalText(luau("local a = 1 --[[ x ]] + 2\n"), "local a = 1   + 2\n", "stripped")
		end,
	})
	harness:case(prefix .. "comments after list separators are stripped", {
		id = prefix .. "comments after list separators are stripped",
		run = function(test: Verify.Context)
			equalText(
				luau("local x = f(\n\ta,\n\t0, -- one\n\t40\n)\n"),
				"local x = f(\n\ta,\n\t0,\n\t40\n)\n",
				"call arguments"
			)
			equalText(
				luau("local a, -- two\n\tb = 1, --[[three]] 2\n"),
				"local a,\n\tb = 1,   2\n",
				"local names and values"
			)
			equalText(luau("local function g(a, -- four\n\tb) end\n"), "local function g(a,\n\tb) end\n", "parameters")
			equalText(luau("local t = { 1, -- five\n\t2 }\n"), "local t = { 1,\n\t2 }\n", "table entries")
		end,
	})
	harness:case(prefix .. "the facet tool sources only hold directives", {
		id = prefix .. "the facet tool sources only hold directives",
		run = function(test: Verify.Context)
			local source = '--!strict\n\nlocal Rule = require("../lib/rule")\n\nreturn Rule\n'
			equalText(luau(source), source, "stripped")
		end,
	})
	harness:case(prefix .. "shell literals, expansions, arithmetic and the shebang survive", {
		id = prefix .. "shell literals, expansions, arithmetic and the shebang survive",
		run = function(test: Verify.Context)
			local result =
				shell('#!/usr/bin/env bash\n# remove\nx="a#b"\necho "${x#prefix}" ${#x} foo#bar $((16#ff)) # gone\n')
			Verify.expect(not contains(result, "# remove")):toBeTrueWith("a whole-line comment survived")
			Verify.expect(not contains(result, "# gone")):toBeTrueWith("a trailing comment survived")
			Verify.expect(contains(result, "${x#prefix}")):toBeTrueWith("a parameter expansion was cut")
			Verify.expect(contains(result, "${#x} foo#bar $((16#ff))")):toBeTrueWith("a literal hash was cut")
			Verify.expect(result ~= nil and string.sub(result, 1, 20) == "#!/usr/bin/env bash\n")
				:toBeTrueWith("the shebang was removed")
		end,
		tags = FULL,
	})
	harness:case(prefix .. "heredoc bodies and multiple delimiters are unchanged", {
		id = prefix .. "heredoc bodies and multiple delimiters are unchanged",
		run = function(test: Verify.Context)
			local result =
				shell("cat <<'ONE' <<-TWO # remove\n# body\n$(echo '#literal')\nONE\n\t# body two\n\tTWO\n# after\n")
			Verify.expect(contains(result, "# body\n$(echo '#literal')")):toBeTrueWith("the first heredoc body changed")
			Verify.expect(contains(result, "\t# body two")):toBeTrueWith("the second heredoc body changed")
			Verify.expect(not contains(result, "# remove")):toBeTrueWith("the command comment survived")
			Verify.expect(not contains(result, "# after")):toBeTrueWith("the comment after the heredocs survived")
		end,
		tags = FULL,
	})
	harness:case(prefix .. "command substitution and nested quotes", {
		id = prefix .. "command substitution and nested quotes",
		run = function(test: Verify.Context)
			local source = 'value="$(echo "$(echo \'#keep\')" # remove\n)"\necho "$value"\n'
			local result = shell(source)
			Verify.expect(not contains(result, "# remove")):toBeTrueWith("the substitution comment survived")
			sameBehavior(source, result)
		end,
		tags = FULL,
	})
	harness:case(prefix .. "a heredoc in a quoted command substitution", {
		id = prefix .. "a heredoc in a quoted command substitution",
		run = function(test: Verify.Context)
			local source = 'x="$(cat <<\'EOF\' # remove\n# literal\nEOF\n)"\nprintf "%s" "$x"\n'
			local result = shell(source)
			Verify.expect(not contains(result, "# remove")):toBeTrueWith("the substitution comment survived")
			sameBehavior(source, result)
		end,
		tags = FULL,
	})
	harness:case(prefix .. "continuations and ANSI quotes", {
		id = prefix .. "continuations and ANSI quotes",
		run = function(test: Verify.Context)
			local source = "echo $'escaped \\' # literal' \\\n'# still literal' # remove\n"
			local result = shell(source)
			Verify.expect(not contains(result, "# remove")):toBeTrueWith("the trailing comment survived")
			sameBehavior(source, result)
		end,
		tags = FULL,
	})
	harness:case(prefix .. "a shellcheck directive survives", {
		id = prefix .. "a shellcheck directive survives",
		run = function(test: Verify.Context)
			local result = shell("# shellcheck disable=SC2086\necho $value # remove\n")
			Verify.expect(contains(result, "# shellcheck disable=SC2086")):toBeTrueWith("the directive was removed")
		end,
		tags = FULL,
	})
	harness:case(prefix .. "removed shell comments trim only unescaped code whitespace", {
		id = prefix .. "removed shell comments trim only unescaped code whitespace",
		run = function(test: Verify.Context)
			local source = 'printf "%s\\n" "a  "  # remove\nprintf "%s\\n" escaped\\  # remove\n'
			local result = shell(source)
			Verify.expect(contains(result, '"a  "\n')):toBeTrueWith("the quoted whitespace changed")
			sameBehavior(source, result)
		end,
		tags = FULL,
	})
	harness:case(prefix .. "unterminated shell constructs fail closed", {
		id = prefix .. "unterminated shell constructs fail closed",
		run = function(test: Verify.Context)
			for _, source in { "echo 'oops\n", 'echo "oops\n', "echo $(oops\n", "cat <<EOF\nbody\n" } do
				local result = Strip.shell(source)
				if result ~= nil then
					error(("%q was accepted"):format(source), 0)
				end
			end
		end,
	})
	harness:case(prefix .. "check, dry run and write are idempotent and skip vendor files", {
		id = prefix .. "check, dry run and write are idempotent and skip vendor files",
		run = function(test: Verify.Context)
			Rule.within(test, {
				["src/main.luau"] = '--!strict\n-- remove\nreturn "-- keep"\n',
				["src/vendor/keep.luau"] = "-- do not touch\nreturn {}\n",
				["tools/run.sh"] = "#!/usr/bin/env bash\necho ok # remove\n",
				["notes.md"] = "-- not source\n",
			}, function(context)
				local initialized = Run.git({ "init", "-q", context.root })
				if not initialized.ok then
					error("git init failed: " .. initialized.stderr, 0)
				end
				local findings = check(context)
				local planned = survey(context, {})
				local listed: { string } = {}
				for _, change in planned.changes do
					table.insert(listed, change.path)
				end
				Verify.expect(listed):toEqual({ "src/main.luau", "tools/run.sh" })
				Verify.expect(Rule.contains(findings, "src/main.luau:2: a comment"))
					:toBeTrueWith("check: " .. Rule.describe(findings))
				Verify.expect(contains(Files.read(context.path("src/main.luau")), "-- remove"))
					:toBeTrueWith("the survey wrote a file")
				for _, change in planned.changes do
					Files.write(context.path(change.path), change.updated)
				end
				equalText(Files.read(context.path("src/main.luau")), '--!strict\n\nreturn "-- keep"\n', "src/main.luau")
				equalText(Files.read(context.path("tools/run.sh")), "#!/usr/bin/env bash\necho ok\n", "tools/run.sh")
				equalText(
					Files.read(context.path("src/vendor/keep.luau")),
					"-- do not touch\nreturn {}\n",
					"the vendor file"
				)
				Verify.expect(check(context)):toEqual({})
			end)
		end,
		tags = FULL,
	})
	harness:case(prefix .. "an unparsable source is a finding", {
		id = prefix .. "an unparsable source is a finding",
		run = function(test: Verify.Context)
			Rule.within(test, { ["src/broken.luau"] = "local = \n" }, function(context)
				local initialized = Run.git({ "init", "-q", context.root })
				if not initialized.ok then
					error("git init failed: " .. initialized.stderr, 0)
				end
				local findings = check(context)
				Verify.expect(Rule.contains(findings, "src/broken.luau: cannot parse Luau"))
					:toBeTrueWith("findings: " .. Rule.describe(findings))
			end)
		end,
		tags = FULL,
	})
end

local rule: Rule.Rule = {
	name = "comments",
	summary = "First-party Luau and shell sources hold no comments except directives and legal notices.",
	check = check,
	register = register,
	values = { "path" },
	actions = {
		write = {
			summary = "Remove the comments in place (limit with --path <pathspec>).",
			run = function(context: Rule.Context, invocation: Cli.Invocation): number
				return act(context, invocation, true)
			end,
		},
		["dry-run"] = {
			summary = "List the files that need comment removal (limit with --path <pathspec>).",
			run = function(context: Rule.Context, invocation: Cli.Invocation): number
				return act(context, invocation, false)
			end,
		},
	},
}

return rule
