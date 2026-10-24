--!strict

local Eval = require("../tools/vendor/verify/src/agent-eval")

export type Configuration = { model: string, effort: string }
export type Options = {
	execute: (Eval.Command) -> Eval.Execution,
	files: Eval.Files,
	directory: string,
	deadlineSeconds: number?,
}

local DEFAULT_CONFIGURATION: Configuration = { model = "gpt-6.1-sol", effort = "medium" }
table.freeze(DEFAULT_CONFIGURATION)

local function transport(options: Options, configuration: Configuration?): Eval.JudgeTransport
	local selected = configuration or DEFAULT_CONFIGURATION
	assert(selected.model ~= "" and selected.effort ~= "", "judge model and effort must be explicit")
	assert(
		not options.files.exists(options.directory),
		"judge directory already exists; choose a new neutral directory"
	)
	options.files.makeDirectory(options.directory)
	return Eval.judge.codexCli({
		execute = options.execute,
		files = options.files,
		directory = options.directory,
		encode = Eval.lute.encode,
		decode = Eval.lute.decode,
		model = selected.model,
		effort = selected.effort,
		deadlineSeconds = options.deadlineSeconds,
	})
end

return { DEFAULT_CONFIGURATION = DEFAULT_CONFIGURATION, transport = transport }
