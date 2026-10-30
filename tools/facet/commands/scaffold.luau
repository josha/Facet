--!strict
local Verify = require("../../vendor/verify/src/core")

local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Rule = require("../lib/rule")
local Scaffold = require("../lib/scaffold")

local USAGE = [[usage: lute run tools/facet scaffold control <lower_snake_name>

Writes src/ui/<name>.luau and registers the control in src/ui/init.luau,
src/ui/control_types.luau and src/init.luau. It refuses to overwrite a control file.]]

local NEXT_STEPS =
	"Implement the control, add a native behavior spec and gallery scenario, and document its API before running lute run tools/facet gate full."

local function message(failure: unknown): string
	local text = string.gsub(tostring(failure), "^.-:%d+: ", "")
	return text
end

local function scaffold(root: string, kind: string, name: string): (boolean, { string })
	local planned, plan = pcall(Scaffold.plan, kind, name)
	if not planned then
		return false, { message(plan) }
	end
	local writes: { Scaffold.File } = {}
	for _, file in plan.files do
		if Files.exists(Files.join(root, file.path)) then
			return false, { `Refusing to overwrite {file.path}` }
		end
		table.insert(writes, file)
	end
	for _, edit in plan.edits do
		local target = Files.join(root, edit.path)
		if not Files.isFile(target) then
			return false, { `Registration target missing in {edit.path}` }
		end
		local edited, content = pcall(Scaffold.applyEdit, Files.read(target), edit)
		if not edited then
			return false, { message(content) }
		end
		table.insert(writes, { path = edit.path, content = content })
	end
	local lines: { string } = {}
	for _, file in writes do
		Files.write(Files.join(root, file.path), file.content)
		table.insert(lines, `wrote {file.path}`)
	end
	return true, lines
end

local function run(invocation: Cli.Invocation): number
	local unknown = Cli.unknownFlags(invocation, {})
	if unknown ~= nil or #invocation.positional ~= 2 then
		if unknown ~= nil then
			print("facet scaffold: unknown flags " .. unknown)
		end
		print(USAGE)
		return 2
	end
	local ok, lines = scaffold(".", invocation.positional[1], invocation.positional[2])
	for _, line in lines do
		print(if ok then line else "facet scaffold: " .. line)
	end
	if not ok then
		return 1
	end
	print(NEXT_STEPS)
	return 0
end

local REGISTRY: { [string]: string } = {
	["src/ui/init.luau"] = "return function(ctx, UI)\n\tlocal groups = {\n\t}\n\n\tlocal all: { () -> () } = {}\nend\n",
	["src/ui/control_types.luau"] = "export type Controls = {\n}\n",
	["src/init.luau"] = "export type ButtonProps = {}\n",
}

local function register(harness: Verify.Harness, prefix: string): ()
	harness:case(prefix .. "a control plan writes one file and three registrations", {
		id = prefix .. "a control plan writes one file and three registrations",
		run = function(test: Verify.Context)
			local plan = Scaffold.plan("control", "proof_control")
			Verify.expect(#plan.files):toBe(1)
			Verify.expect(#plan.edits):toBe(3)
			Verify.expect(plan.files[1].path):toBe("src/ui/proof_control.luau")
			Verify.expect(string.find(plan.files[1].content, "UI.ProofControl = ctx.construct", 1, true) ~= nil)
				:toBeTrueWith("the generated control does not register ProofControl")
		end,
	})
	harness:case(prefix .. "other kinds and names that are not lower_snake_case are refused", {
		id = prefix .. "other kinds and names that are not lower_snake_case are refused",
		run = function(test: Verify.Context)
			for _, kind in { "primitive", "target", "mode" } do
				if pcall(Scaffold.plan, kind, "proof") then
					error(`kind {kind} was accepted`, 0)
				end
			end
			for _, name in { "ProofControl", "1proof", "proof-control", "" } do
				if pcall(Scaffold.plan, "control", name) then
					error(`name '{name}' was accepted`, 0)
				end
			end
		end,
	})
	harness:case(prefix .. "a refused name is reported without a source location", {
		id = prefix .. "a refused name is reported without a source location",
		run = function(test: Verify.Context)
			local ok, lines = scaffold(".", "control", "BadName")
			Verify.expect(not ok):toBeTrueWith("the name was accepted")
			Verify.expect(lines):toEqual({ "Use a lower_snake_case control name" })
		end,
	})
	harness:case(prefix .. "an applied edit is idempotent", {
		id = prefix .. "an applied edit is idempotent",
		run = function(test: Verify.Context)
			local plan = Scaffold.plan("control", "proof_control")
			for _, edit in plan.edits do
				local once = Scaffold.applyEdit(REGISTRY[edit.path], edit)
				if Scaffold.applyEdit(once, edit) ~= once then
					error(`the edit of {edit.path} is not idempotent`, 0)
				end
			end
		end,
	})
	harness:case(prefix .. "a scaffold writes and registers the control and refuses to overwrite it", {
		id = prefix .. "a scaffold writes and registers the control and refuses to overwrite it",
		run = function(test: Verify.Context)
			Rule.within(test, REGISTRY, function(context: Rule.Context): ()
				local ok, lines = scaffold(context.root, "control", "proof_control")
				if not ok then
					error("the first scaffold failed: " .. table.concat(lines, "; "), 0)
				end
				local registry = Files.read(context.path("src/ui/init.luau"))
				local types = Files.read(context.path("src/ui/control_types.luau"))
				local again, refusal = scaffold(context.root, "control", "proof_control")
				Verify.expect(#lines):toBe(4)
				Verify.expect(Files.isFile(context.path("src/ui/proof_control.luau"))):toBeTrueWith("no control file")
				Verify.expect(string.find(registry, 'require("@self/proof_control")(ctx, UI)', 1, true) ~= nil)
					:toBeTrueWith("the runtime registration is missing")
				Verify.expect(string.find(types, "ProofControl: ProofControl.Constructor", 1, true) ~= nil)
					:toBeTrueWith("the type registration is missing")
				Verify.expect(not again):toBeTrueWith("the second scaffold overwrote the control")
				Verify.expect(string.find(refusal[1] or "", "Refusing to overwrite", 1, true) ~= nil)
					:toBeTrueWith("the refusal does not name the overwrite")
			end)
		end,
	})
	harness:case(prefix .. "a missing registration target is reported and nothing is written", {
		id = prefix .. "a missing registration target is reported and nothing is written",
		run = function(test: Verify.Context)
			Rule.within(test, {
				["src/ui/init.luau"] = REGISTRY["src/ui/init.luau"],
				["src/ui/control_types.luau"] = "export type Other = {}\n",
				["src/init.luau"] = REGISTRY["src/init.luau"],
			}, function(context: Rule.Context): ()
				local ok, lines = scaffold(context.root, "control", "proof_control")
				Verify.expect(not ok):toBeTrueWith("the scaffold accepted a tree without its registration target")
				Verify.expect(string.find(lines[1] or "", "src/ui/control_types.luau", 1, true) ~= nil)
					:toBeTrueWith("the refusal does not name the file")
				Verify.expect(not Files.exists(context.path("src/ui/proof_control.luau")))
					:toBeTrueWith("the control file was written")
			end)
		end,
	})
	harness:case(prefix .. "the repository registries still hold every registration target", {
		id = prefix .. "the repository registries still hold every registration target",
		run = function(test: Verify.Context)
			local plan = Scaffold.plan("control", "proof_control")
			for _, edit in plan.edits do
				if not Files.isFile(edit.path) then
					error(`{edit.path} is missing`, 0)
				end
				local edited = pcall(Scaffold.applyEdit, Files.read(edit.path), edit)
				if not edited then
					error(`{edit.path} lost the target '{edit.before}'`, 0)
				end
			end
		end,
	})
end

local command: Cli.Command = {
	name = "scaffold",
	summary = "Scaffold a native control and register it.",
	usage = USAGE,
	register = register,
	run = run,
}

return command
