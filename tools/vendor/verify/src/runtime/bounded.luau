--!strict

local Binding = require "./binding"

export type Result = {
	ok: boolean,
	exitcode: number,
	stdout: string,
	stderr: string,
	timedOut: boolean,
}

export type Runner = (argv: { string }, options: Binding.RunOptions?) -> Binding.ProcessResult

local CAPABILITY = "posix-process-groups"

local MARKER = "verify_bounded_timeout"

local WATCHDOG = table.concat({
	'set -m; limit=$1; shift; "$@" & child=$!',
	'( sleep "$limit" >/dev/null 2>&1; kill -KILL -- "-$child" 2>/dev/null && echo ' .. MARKER .. " >&2 ) &",
	'dog=$!; wait "$child"; status=$?; kill "$dog" 2>/dev/null; exit "$status"',
}, "\n")

local function run(argv: { string }, seconds: number, runner: Runner, options: Binding.RunOptions?): Result
	assert(#argv > 0 and seconds > 0 and seconds < math.huge, "bounded run needs a command and a positive limit")
	local command = { "sh", "-c", WATCHDOG, "verify-bounded", tostring(math.ceil(seconds)) }
	for _, value in argv do
		table.insert(command, value)
	end
	local called, result = pcall(runner, command, options)
	if not called then
		return { ok = false, exitcode = -1, stdout = "", stderr = tostring(result), timedOut = false }
	end
	local ran = result :: Binding.ProcessResult
	local stderr = string.gsub(ran.stderr, "%[%d+%][%+%-]?%s+[^\n]*\n?", "")
	local timedOut = string.find(stderr, MARKER, 1, true) ~= nil
	return {
		ok = ran.exitcode == 0 and not timedOut,
		exitcode = ran.exitcode,
		stdout = ran.stdout,
		stderr = if timedOut then string.gsub(stderr, MARKER .. "\n?", "") else stderr,
		timedOut = timedOut,
	}
end

return {
	CAPABILITY = CAPABILITY,
	run = run,
}
