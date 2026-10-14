--!strict

local path = require("@std/path")
local process = require("@std/process")

export type Result = {
	ok: boolean,
	code: number,
	stdout: string,
	stderr: string,
	timedOut: boolean,
}

export type Options = {
	cwd: string?,
	env: { [string]: string }?,
	timeout: number?,
}

local Run = {}

local function launch(argv: { string }, options: Options?, inherit: boolean): Result
	local settings: process.ProcessRunOptions = {
		cwd = if options then options.cwd else nil,
		env = if options then options.env else nil,
		timeout = if options then options.timeout else nil,
		stdio = if inherit then "inherit" else "default",
	}
	local launched, result = pcall(process.run, argv, settings)
	if not launched then
		return {
			ok = false,
			code = 127,
			stdout = "",
			stderr = ("could not start %s: %s"):format(argv[1] or "?", tostring(result)),
			timedOut = false,
		}
	end
	local outcome = result :: process.ProcessResult
	return {
		ok = outcome.ok,
		code = outcome.exitcode,
		stdout = outcome.stdout or "",
		stderr = outcome.stderr or "",
		timedOut = outcome.timedOut == true,
	}
end

function Run.capture(argv: { string }, options: Options?): Result
	return launch(argv, options, false)
end

function Run.inherit(argv: { string }, options: Options?): Result
	return launch(argv, options, true)
end

function Run.output(argv: { string }, options: Options?): string?
	local result = launch(argv, options, false)
	if not result.ok then
		return nil
	end
	local trimmed = string.gsub(result.stdout, "%s+$", "")
	return trimmed
end

function Run.git(arguments: { string }, cwd: string?): Result
	local argv = { "git" }
	for _, argument in arguments do
		table.insert(argv, argument)
	end
	return launch(argv, { cwd = cwd }, false)
end

function Run.gitOutput(arguments: { string }, cwd: string?): string?
	local result = Run.git(arguments, cwd)
	if not result.ok then
		return nil
	end
	local trimmed = string.gsub(result.stdout, "%s+$", "")
	return trimmed
end

function Run.lute(): string
	local executable = string.gsub(path.format(process.execPath()), "\\", "/")
	return executable
end

function Run.env(name: string): string?
	local value = process.env[name]
	if value == nil or value == "" then
		return nil
	end
	return value
end

function Run.environment(): { [string]: string }
	local copy: { [string]: string } = {}
	for key, value in process.env do
		copy[key] = value
	end
	return copy
end

return table.freeze(Run)
