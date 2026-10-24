--!strict
local Gate = require("../lib/gate")
local Verify = require("../../vendor/verify/src/core")

local stringext = require("@std/stringext")
local task = require("@std/task")
local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Run = require("../lib/run")

type Failure = { code: number, message: string }

type Session = {
	cwd: string?,
	say: (string) -> (),
	failure: Failure?,
}

type Options = {
	messageFile: string?,
	dryRun: boolean,
	repair: boolean,
	specs: { string },
}

local PREFIX = "facet git commit-isolated"
local CONTEXT = "1"

local USAGE = [[usage: lute run tools/facet git commit-isolated -m <message-file> <spec> [<spec> ...]
       lute run tools/facet git commit-isolated -m <message-file> --dry-run <spec> ...
       lute run tools/facet git commit-isolated --repair <path> [<path> ...]
       lute run tools/facet git --selftest

Commit ONLY your own hunks, through a private index, in one uninterrupted step.

    <spec> = path                    the whole file (you verified it is all yours)
             path:marker[,marker...] only hunks whose text contains a marker

    --repair <path> [<path> ...]
             no commit: just make the shared index agree with HEAD for those
             paths (the repair for phantom staged deletions -- see REPUBLISH below)

    -m and --message-file take the same message file.

WHY THIS EXISTS
---------------
Staging by name is not isolation, and four rounds of the same accident landed in
one week: with N agents in one working tree, every git command
that names a path (`add`, `commit -- <path>`, `diff --cached`) reports on a
LOCATION, and location is not ownership. The rules that grew out of those rounds
are a lock protocol implemented in etiquette, and the third occurrence proved
etiquette does not hold: the focus-graph agent ran `git diff --cached --stat`,
read back only its own eleven files, and still committed three that belonged to
someone else. The check did not fail -- the CHECK -> COMMIT interval did, and that
interval is filled by exactly what a careful agent does (composing a message,
re-reading a diff). The more conscientious the agent, the wider its window.

This command removes the interval instead of asking anyone to be quicker. It:

  * stages into a PRIVATE index (`GIT_INDEX_FILE`) seeded from HEAD, so
    `.git/index` -- the shared mutable everyone else is also writing -- is never
    touched for staging, and another agent's staged work can neither be swept
    into your commit nor destroyed by it;
  * filters your diff to the HUNKS that mention your markers, which is the only
    granularity that is actually scoped to your changes rather than to a file;
  * writes the tree, commits it with `commit-tree`, and advances the branch with
    a COMPARE-AND-SWAP on the HEAD you read, so a commit landing underneath you
    fails loudly instead of being clobbered;
  * REPUBLISHES the committed paths into the shared index (see below), which is
    not optional.

Nothing here resets, checks out, stashes, or `add -A`s. Your working tree is
never modified.

REPUBLISH -- the part that is easy to leave out and must not be
-------------------------------------------------------------
A commit made this way moves HEAD without updating `.git/index`, so the shared
index is left holding pre-commit blobs for your paths. That is not cosmetic.
MEASURED, in a scratch repo: with the index stale, another agent's ordinary
`git commit` writes the index as a tree and SILENTLY REVERTS your committed
content -- their commit lands with your file back at its old contents, green
tests and all. It also makes their `git diff --cached` show phantom DELETIONS of
your new files, which is how a concurrent agent nearly reverted three files of
this framework the day this tool was written.

So after the commit lands, each committed path's index entry is set to its blob
in the new commit, with `git update-index --cacheinfo`. That touches the shared
index for your paths only, reads no working-tree bytes (so it cannot sweep
anyone's in-flight edits), and is the surgical form of the `git reset <path>` the
standing rules forbid.

WHAT IT REFUSES
---------------
  * a named path with no change against HEAD                        -> exit 2
  * a BINARY path is staged WHOLE (there are no hunks to filter), and a
    marker filter on one is refused rather than silently ignored
  * a marker that matches no hunk (it will not commit nothing)      -> exit 2
  * HEAD moved between the read and the update-ref (a real race)    -> exit 3
    Re-run it. Your working tree is untouched, so a re-run is free.
  * it does NOT run pre-commit/commit-msg hooks (`commit-tree` bypasses them).
    This repo has none; if yours does, run them yourself first.

READING THE OUTPUT
------------------
  NEW    <path>                 untracked file, hashed whole into the commit
  KEEP   <path>  @@ -a,b +c,d @@   this hunk IS in the commit
  drop   <path>  @@ -a,b +c,d @@   this hunk is NOT (another agent's, or a later
                                   commit of your own)
  patch: <file>                 the exact bytes committed, kept for audit
  commit <sha> on <ref>
  index: republished N path(s)  the shared index now agrees with HEAD

Read the drop lines. They are the claim you are making about what is not yours.

THE HOLE THAT IS STILL OPEN
---------------------------
Hunk granularity. `git diff` merges nearby edits into one hunk, so if another
agent's change lands within the context window of yours, a marker match takes
BOTH and this command cannot tell. It diffs at `-U1` to make that window as
narrow as git allows (one line of context instead of three), but it does not
close it. When two agents are genuinely inside the same few lines, nothing short
of a separate worktree separates them -- and the `patch:` file is there so the
claim is auditable after the fact rather than merely trusted.]]

local function abort(session: Session, message: string, code: number): never
	session.failure = { code = code, message = message }
	error(message, 0)
end

local function git(session: Session, arguments: { string }, indexFile: string?): Run.Result
	local argv = { "git" }
	for _, argument in arguments do
		table.insert(argv, argument)
	end
	local environment: { [string]: string }? = nil
	if indexFile ~= nil then
		local copy = Run.environment()
		copy.GIT_INDEX_FILE = indexFile
		environment = copy
	end
	return Run.capture(argv, { cwd = session.cwd, env = environment })
end

local function must(session: Session, arguments: { string }, indexFile: string?): string
	local result = git(session, arguments, indexFile)
	if not result.ok then
		abort(session, ("`git %s` failed:\n%s"):format(table.concat(arguments, " "), stringext.trim(result.stderr)), 1)
	end
	return result.stdout
end

local function words(text: string): { string }
	local found: { string } = {}
	for word in string.gmatch(text, "%S+") do
		table.insert(found, word)
	end
	return found
end

local function located(session: Session, path: string): string
	local normalized = Files.normalize(path)
	local cwd = session.cwd
	if cwd == nil or string.sub(normalized, 1, 1) == "/" or string.match(normalized, "^%a:") then
		return normalized
	end
	return Files.join(cwd, normalized)
end

local function tracked(session: Session, path: string): boolean
	return git(session, { "ls-files", "--error-unmatch", path }).ok
end

local function splitLines(text: string): { string }
	local lines: { string } = {}
	local start = 1
	while start <= #text do
		local stop = string.find(text, "\n", start, true)
		if stop == nil then
			table.insert(lines, string.sub(text, start))
			break
		end
		table.insert(lines, string.sub(text, start, stop))
		start = stop + 1
	end
	return lines
end

local function splitHunks(diff: string): (string, { { string } })
	local lines = splitLines(diff)
	local header: { string } = {}
	local hunks: { { string } } = {}
	local current: { string }? = nil
	for _, line in lines do
		if string.sub(line, 1, 2) == "@@" then
			local hunk = { line }
			table.insert(hunks, hunk)
			current = hunk
		elseif current ~= nil then
			table.insert(current, line)
		else
			table.insert(header, line)
		end
	end
	return table.concat(header), hunks
end

local function indexBlob(session: Session, path: string): string?
	local parts = words(git(session, { "ls-files", "-s", "--", path }).stdout)
	return if #parts > 2 then parts[2] else nil
end

local function republish(
	session: Session,
	paths: { string },
	commit: string,
	was: { [string]: string | false }?
): number
	local done = 0
	for _, path in paths do
		local entry = words(git(session, { "ls-tree", commit, "--", path }).stdout)
		if #entry < 3 then
			for _ = 1, 6 do
				local result = git(session, { "update-index", "--force-remove", path })
				if result.ok or string.find(result.stderr, "index.lock", 1, true) == nil then
					done += if result.ok then 1 else 0
					break
				end
				task.wait(0.5)
			end
			continue
		end
		local mode, blob = entry[1], entry[3]
		if was ~= nil then
			local current = indexBlob(session, path)
			local before = was[path]
			if current ~= nil and current ~= before and current ~= blob then
				session.say(
					("  NOTE  %s had ANOTHER AGENT'S staged content in the shared index;\n"):format(path)
						.. "        republishing resets it to unstaged. Their working-tree file is\n"
						.. "        untouched -- they re-stage it. (Left alone, their `git commit`\n"
						.. "        would have reverted this commit instead.)"
				)
			end
		end
		local published = false
		local contended = true
		for attempt = 1, 6 do
			local result =
				git(session, { "update-index", "--add", "--cacheinfo", ("%s,%s,%s"):format(mode, blob, path) })
			if result.ok then
				done += 1
				published = true
				contended = false
				break
			end
			if string.find(result.stderr, "index.lock", 1, true) == nil then
				session.say(("  WARN  could not republish %s: %s"):format(path, stringext.trim(result.stderr)))
				contended = false
				break
			end
			task.wait(0.25 * attempt)
		end
		if not published and contended then
			session.say(
				("  WARN  %s left STALE in the shared index (lock contention).\n"):format(path)
					.. "        Another agent's plain `git commit` may revert it. Repair with:\n"
					.. ("        lute run tools/facet git commit-isolated --repair %s"):format(path)
			)
		end
	end
	return done
end

local function normalizedMessage(contents: string): string
	local lf = string.gsub(contents, "\r\n", "\n")
	local unified = string.gsub(lf, "\r", "\n")
	return unified
end

local function commit(session: Session, options: Options, workspace: string): number
	local messageFile = options.messageFile
	if messageFile == nil then
		return abort(session, "-m <message-file> is required (write the message FIRST)", 1)
	end
	local oldHead = stringext.trim(must(session, { "rev-parse", "HEAD" }))
	local index = Files.join(workspace, "index")
	must(session, { "read-tree", oldHead }, index)

	local keptPatch: { string } = {}
	local paths: { string } = {}
	local was: { [string]: string | false } = {}
	for _, spec in options.specs do
		local colon = string.find(spec, ":", 1, true)
		local path = if colon then string.sub(spec, 1, colon - 1) else spec
		local markers = if colon then string.sub(spec, colon + 1) else ""
		table.insert(paths, path)
		local headEntry = words(git(session, { "ls-tree", oldHead, "--", path }).stdout)
		local headBlob: string | false = if #headEntry > 2 then headEntry[3] else false
		was[path] = headBlob
		if not Files.exists(located(session, path)) then
			if headBlob == false then
				abort(session, ("%s is neither on disk nor in HEAD"):format(path), 1)
			end
			must(session, { "update-index", "--force-remove", path }, index)
			session.say(("  DEL    %s"):format(path))
			continue
		end
		if not tracked(session, path) then
			must(session, { "add", "--", path }, index)
			session.say(("  NEW    %s"):format(path))
			continue
		end
		local diff = must(session, { "diff", "-U" .. CONTEXT, "--binary", oldHead, "--", path })
		local header, hunks = splitHunks(diff)
		if #hunks == 0 then
			local newMode = string.match(diff, "new mode (%d+)")
			if string.find(diff, "old mode ", 1, true) ~= nil and newMode ~= nil then
				if markers ~= "" then
					abort(
						session,
						("%s is a MODE-ONLY change and markers cannot select inside one — refusing"):format(path),
						2
					)
				end
				local blob = stringext.trim(must(session, { "hash-object", "-w", path }))
				must(
					session,
					{ "update-index", "--add", "--cacheinfo", ("%s,%s,%s"):format(newMode, blob, path) },
					index
				)
				session.say(("  MODE   %s  (%s)"):format(path, newMode))
				continue
			end
			if
				string.find(diff, "GIT binary patch", 1, true) ~= nil
				or string.find(diff, "Binary files", 1, true) ~= nil
			then
				if markers ~= "" then
					abort(session, ("%s is BINARY and markers cannot select inside one — refusing"):format(path), 2)
				end
				local blob = stringext.trim(must(session, { "hash-object", "-w", path }))
				must(session, { "update-index", "--add", "--cacheinfo", ("100644,%s,%s"):format(blob, path) }, index)
				session.say(("  BINARY %s  (whole file, %d bytes of patch)"):format(path, #diff))
				continue
			end
			abort(session, ("%s has no change against HEAD — refusing"):format(path), 2)
		end
		local keep: { [number]: boolean } = {}
		if markers ~= "" then
			local wanted = string.split(markers, ",")
			local matched = false
			for position, hunk in hunks do
				local body = table.concat(hunk)
				for _, marker in wanted do
					if string.find(body, marker, 1, true) ~= nil then
						keep[position] = true
						matched = true
						break
					end
				end
			end
			if not matched then
				local quoted: { string } = {}
				for _, marker in wanted do
					table.insert(quoted, "'" .. marker .. "'")
				end
				abort(
					session,
					("no hunk of %s contains any of [%s] — refusing"):format(path, table.concat(quoted, ", ")),
					2
				)
			end
		else
			for position in hunks do
				keep[position] = true
			end
		end
		local kept: { string } = { header }
		for position, hunk in hunks do
			local tag = if keep[position] then "KEEP" else "drop"
			session.say(("  %s   %s  %s"):format(tag, path, (string.gsub(hunk[1], "%s+$", ""))))
			if keep[position] then
				table.insert(kept, table.concat(hunk))
			end
		end
		table.insert(keptPatch, table.concat(kept))
	end

	if #keptPatch > 0 then
		local patchFile = Files.join(Files.temporaryDirectory("facet-commit-isolated-patch-"), "commit_isolated.patch")
		Files.write(patchFile, table.concat(keptPatch))
		must(session, { "apply", "--cached", "--recount", "--whitespace=nowarn", patchFile }, index)
		session.say(("  patch: %s"):format(patchFile))
	end

	if options.dryRun then
		session.say(PREFIX .. ": --dry-run, nothing committed")
		return 0
	end

	local tree = stringext.trim(must(session, { "write-tree" }, index))
	local messagePath = located(session, messageFile)
	local readable, message = pcall(Files.read, messagePath)
	if not readable then
		abort(session, ("could not read the message file %s: %s"):format(messageFile, tostring(message)), 1)
	end
	local normalized = Files.join(workspace, "message")
	Files.write(normalized, normalizedMessage(message :: string))
	local sha = stringext.trim(must(session, { "commit-tree", tree, "-p", oldHead, "-F", normalized }))
	local ref = stringext.trim(must(session, { "symbolic-ref", "HEAD" }))
	local swapped = git(session, { "update-ref", ref, sha, oldHead })
	if not swapped.ok then
		abort(
			session,
			("HEAD moved under you — nothing committed.\n  %s\n  Your working tree is untouched. Re-run this exact command."):format(
				stringext.trim(swapped.stderr)
			),
			3
		)
	end
	session.say(("%s: %s on %s"):format(PREFIX, string.sub(sha, 1, 9), ref))
	session.say(("index: republished %d path(s)"):format(republish(session, paths, sha, was)))
	return 0
end

local function commitIsolated(session: Session, options: Options): number
	if options.repair then
		local count = republish(session, options.specs, "HEAD", nil)
		session.say(("index: republished %d path(s) from HEAD"):format(count))
		return 0
	end
	local workspace = Files.temporaryDirectory("facet-commit-isolated-")
	local ok, outcome = pcall(commit, session, options, workspace)
	Files.remove(workspace)
	if ok then
		return outcome :: number
	end
	local failure = session.failure
	if failure ~= nil then
		session.say(("%s: %s"):format(PREFIX, failure.message))
		return failure.code
	end
	session.say(("%s: %s"):format(PREFIX, tostring(outcome)))
	return 1
end

local function parseOptions(invocation: Cli.Invocation): (Options?, string?, boolean)
	local options: Options = {
		messageFile = Cli.flag(invocation, "message-file"),
		dryRun = Cli.switch(invocation, "dry-run"),
		repair = Cli.switch(invocation, "repair"),
		specs = {},
	}
	local positional = invocation.positional
	local index = 2
	while index <= #positional do
		local argument = positional[index]
		if argument == "-h" then
			return nil, nil, true
		elseif argument == "-m" then
			local value = positional[index + 1]
			if value == nil then
				return nil, "argument -m/--message-file: expected one argument", false
			end
			options.messageFile = value
			index += 1
		elseif string.sub(argument, 1, 2) == "-m" then
			options.messageFile = string.sub(argument, 3)
		elseif string.sub(argument, 1, 1) == "-" and argument ~= "-" then
			return nil, ("unrecognized argument %s"):format(argument), false
		else
			table.insert(options.specs, argument)
		end
		index += 1
	end
	return options, nil, false
end

local function makeRepository(test: Verify.Context): string
	local root = Files.temporaryDirectory("facet-commit-isolated-case-")
	test:defer(function()
		Files.remove(root)
	end)
	local function setup(arguments: { string })
		local result = Run.git(arguments, root)
		if not result.ok then
			error(("git %s failed: %s"):format(table.concat(arguments, " "), result.stderr), 0)
		end
	end
	setup({ "init", "-q" })
	setup({ "config", "user.name", "selftest" })
	setup({ "config", "user.email", "s@t" })
	setup({ "config", "commit.gpgsign", "false" })
	setup({ "config", "core.autocrlf", "false" })
	setup({ "commit", "-q", "--allow-empty", "-m", "root" })
	return root
end

local function commitAll(root: string, paths: { string }, message: string)
	local add = { "add", "--" }
	for _, path in paths do
		table.insert(add, path)
	end
	Run.git(add, root)
	local result = Run.git({ "commit", "-q", "-m", message }, root)
	if not result.ok then
		error("git commit failed: " .. result.stderr, 0)
	end
end

local function numberedLines(first: number, last: number, changed: { [number]: string }?): string
	local lines: { string } = {}
	for line = first, last do
		table.insert(lines, if changed and changed[line] then changed[line] else ("line %d"):format(line))
	end
	return table.concat(lines, "\n") .. "\n"
end

local function inRepository(
	test: Verify.Context,
	body: (root: string, run: (Options) -> (number, { string })) -> ()
): ()
	local root = makeRepository(test)
	local function invoke(options: Options): (number, { string })
		local said: { string } = {}
		local session: Session = {
			cwd = root,
			say = function(line: string)
				table.insert(said, line)
			end,
		}
		return commitIsolated(session, options), said
	end
	body(root, invoke)
end

local function headText(root: string, path: string): string?
	local result = Run.git({ "show", "HEAD:" .. path }, root)
	return if result.ok then result.stdout else nil
end

local function porcelain(root: string): string
	local status = string.gsub(Run.git({ "status", "--porcelain" }, root).stdout, "%s+$", "")
	return status
end

local function said(lines: { string }, fragment: string): boolean
	for _, line in lines do
		if string.find(line, fragment, 1, true) ~= nil then
			return true
		end
	end
	return false
end

local function options(messageFile: string?, specs: { string }, dryRun: boolean?, repair: boolean?): Options
	return { messageFile = messageFile, specs = specs, dryRun = dryRun == true, repair = repair == true }
end

local function register(harness: Verify.Harness, prefix: string): ()
	harness:case(prefix .. "a deletion commits and the shared index agrees", {
		id = prefix .. "a deletion commits and the shared index agrees",
		run = function(test: Verify.Context): ()
			inRepository(test, function(root: string, invoke: (Options) -> (number, { string })): ()
				Files.write(Files.join(root, "keep.txt"), "keep\n")
				Files.write(Files.join(root, "gone.txt"), "gone\n")
				commitAll(root, { "keep.txt", "gone.txt" }, "two files")
				Files.remove(Files.join(root, "gone.txt"))
				Files.write(Files.join(root, "message.txt"), "the deletion commits\r\n\r\nBody.\r\n")
				local code, lines = invoke(options("message.txt", { "gone.txt" }))
				local tree = stringext.trim(Run.git({ "ls-tree", "HEAD", "--", "gone.txt" }, root).stdout)
				local message = Run.git({ "log", "-1", "--format=%B" }, root).stdout
				Verify.expect(code):toBe(0)
				Verify.expect(said(lines, "  DEL    gone.txt")):toBeTrueWith("no DEL line")
				Verify.expect(tree):toBe("")
				Verify.expect(porcelain(root)):toBe("?? message.txt")
				Verify.expect(message):toBe("the deletion commits\n\nBody.\n\n")
			end)
		end,
	})
	harness:case(prefix .. "markers keep only the matching hunks and leave the working tree alone", {
		id = prefix .. "markers keep only the matching hunks and leave the working tree alone",
		run = function(test: Verify.Context): ()
			inRepository(test, function(root: string, invoke: (Options) -> (number, { string })): ()
				local file = Files.join(root, "shared.txt")
				Files.write(file, numberedLines(1, 20))
				commitAll(root, { "shared.txt" }, "base")
				local edited = numberedLines(1, 20, { [3] = "line 3 MINE", [15] = "line 15 THEIRS" })
				Files.write(file, edited)
				Files.write(Files.join(root, "message.txt"), "mine only\n")
				local code, lines = invoke(options("message.txt", { "shared.txt:MINE" }))
				Verify.expect(code):toBe(0)
				Verify.expect(said(lines, "  KEEP   shared.txt  @@ -2,3 +2,3 @@")):toBeTrueWith("no KEEP line")
				Verify.expect(said(lines, "  drop   shared.txt  @@ -14,3 +14,3 @@")):toBeTrueWith("no drop line")
				Verify.expect(headText(root, "shared.txt")):toBe(numberedLines(1, 20, { [3] = "line 3 MINE" }))
				Verify.expect(Files.read(file)):toBe(edited)
				Verify.expect(porcelain(root)):toBe(" M shared.txt\n?? message.txt")
			end)
		end,
	})
	harness:case(prefix .. "an untracked file commits whole and another agent's staging is reported", {
		id = prefix .. "an untracked file commits whole and another agent's staging is reported",
		run = function(test: Verify.Context): ()
			inRepository(test, function(root: string, invoke: (Options) -> (number, { string })): ()
				Files.write(Files.join(root, "other.txt"), "base\n")
				commitAll(root, { "other.txt" }, "base")
				Files.write(Files.join(root, "other.txt"), "theirs\n")
				Run.git({ "add", "other.txt" }, root)
				Files.write(Files.join(root, "other.txt"), "mine\n")
				Files.write(Files.join(root, "new.txt"), "fresh\n")
				Files.write(Files.join(root, "message.txt"), "new file\n")
				local code, lines = invoke(options("message.txt", { "new.txt", "other.txt" }))
				Verify.expect(code):toBe(0)
				Verify.expect(said(lines, "  NEW    new.txt")):toBeTrueWith("no NEW line")
				Verify.expect(said(lines, "NOTE  other.txt had ANOTHER AGENT'S")):toBeTrueWith("no NOTE line")
				Verify.expect(headText(root, "new.txt")):toBe("fresh\n")
				Verify.expect(headText(root, "other.txt")):toBe("mine\n")
				Verify.expect(porcelain(root)):toBe("?? message.txt")
				Verify.expect(said(lines, "index: republished 2 path(s)")):toBeTrueWith("no republish line")
			end)
		end,
	})
	harness:case(prefix .. "refusals keep their exit codes and commit nothing", {
		id = prefix .. "refusals keep their exit codes and commit nothing",
		run = function(test: Verify.Context): ()
			inRepository(test, function(root: string, invoke: (Options) -> (number, { string })): ()
				Files.write(Files.join(root, "same.txt"), "same\n")
				Files.write(Files.join(root, "picture.bin"), "\0\1\2\3")
				commitAll(root, { "same.txt", "picture.bin" }, "base")
				Files.write(Files.join(root, "picture.bin"), "\0\1\2\4\5")
				Files.write(Files.join(root, "message.txt"), "refused\n")
				local head = stringext.trim(Run.git({ "rev-parse", "HEAD" }, root).stdout)
				local unchanged = invoke(options("message.txt", { "same.txt" }))
				Files.write(Files.join(root, "same.txt"), "changed\n")
				local unmatched, unmatchedLines = invoke(options("message.txt", { "same.txt:NOPE" }))
				local absent = invoke(options("message.txt", { "nowhere.txt" }))
				local binary, binaryLines = invoke(options("message.txt", { "picture.bin:MARK" }))
				local noMessage = invoke(options(nil, { "same.txt" }))
				Verify.expect(unchanged):toBe(2)
				Verify.expect(unmatched):toBe(2)
				Verify.expect(said(unmatchedLines, "contains any of ['NOPE']")):toBeTrueWith("no marker message")
				Verify.expect(absent):toBe(1)
				Verify.expect(binary):toBe(2)
				Verify.expect(said(binaryLines, "is BINARY")):toBeTrueWith("no binary message")
				Verify.expect(noMessage):toBe(1)
				Verify.expect(stringext.trim(Run.git({ "rev-parse", "HEAD" }, root).stdout)):toBe(head)
			end)
		end,
	})
	harness:case(prefix .. "a binary file commits whole and --dry-run commits nothing", {
		id = prefix .. "a binary file commits whole and --dry-run commits nothing",
		run = function(test: Verify.Context): ()
			inRepository(test, function(root: string, invoke: (Options) -> (number, { string })): ()
				Files.write(Files.join(root, "picture.bin"), "\0\1\2\3")
				commitAll(root, { "picture.bin" }, "base")
				Files.write(Files.join(root, "picture.bin"), "\0\1\2\4\5")
				Files.write(Files.join(root, "message.txt"), "binary\n")
				local head = stringext.trim(Run.git({ "rev-parse", "HEAD" }, root).stdout)
				local dry, dryLines = invoke(options("message.txt", { "picture.bin" }, true))
				local after = stringext.trim(Run.git({ "rev-parse", "HEAD" }, root).stdout)
				local code, lines = invoke(options("message.txt", { "picture.bin" }))
				Verify.expect(dry):toBe(0)
				Verify.expect(said(dryLines, "--dry-run, nothing committed")):toBeTrueWith("no dry-run line")
				Verify.expect(after):toBe(head)
				Verify.expect(code):toBe(0)
				Verify.expect(said(lines, "  BINARY picture.bin")):toBeTrueWith("no BINARY line")
				Verify.expect(headText(root, "picture.bin")):toBe("\0\1\2\4\5")
			end)
		end,
	})
	harness:case(prefix .. "--repair makes the shared index agree with HEAD", {
		id = prefix .. "--repair makes the shared index agree with HEAD",
		run = function(test: Verify.Context): ()
			inRepository(test, function(root: string, invoke: (Options) -> (number, { string })): ()
				Files.write(Files.join(root, "keep.txt"), "keep\n")
				commitAll(root, { "keep.txt" }, "base")
				Run.git({ "update-index", "--force-remove", "keep.txt" }, root)
				local phantom = porcelain(root)
				local code, lines = invoke(options(nil, { "keep.txt" }, false, true))
				Verify.expect(phantom):toBe("D  keep.txt\n?? keep.txt")
				Verify.expect(code):toBe(0)
				Verify.expect(said(lines, "index: republished 1 path(s) from HEAD")):toBeTrueWith("no repair line")
				Verify.expect(porcelain(root)):toBe("")
			end)
		end,
	})
	harness:case(prefix .. "the command line accepts -m, --message-file and refuses unknown options", {
		id = prefix .. "the command line accepts -m, --message-file and refuses unknown options",
		run = function(test: Verify.Context): ()
			local short = parseOptions(Cli.parse({ "git", "commit-isolated", "-m", "msg.txt", "a.txt", "b.txt:X" }))
			local long = parseOptions(
				Cli.parse({ "git", "commit-isolated", "--message-file", "m.txt", "--dry-run", "a" }, { "message-file" })
			)
			local _, refusal = parseOptions(Cli.parse({ "git", "commit-isolated", "-x", "a" }))
			local _, missing = parseOptions(Cli.parse({ "git", "commit-isolated", "a", "-m" }))
			Verify.expect(short and short.messageFile):toBe("msg.txt")
			Verify.expect(if short then short.specs else {}):toEqual({ "a.txt", "b.txt:X" })
			Verify.expect(long and long.messageFile):toBe("m.txt")
			Verify.expect(long and long.dryRun):toBe(true)
			Verify.expect(refusal):toBe("unrecognized argument -x")
			Verify.expect(missing):toBe("argument -m/--message-file: expected one argument")
		end,
	})
end

local function run(invocation: Cli.Invocation): number
	local subcommand = invocation.positional[1]
	if Cli.switch(invocation, "selftest") then
		return Gate.selftest("tools/commands", "tools/commands::git::")
	end
	if subcommand ~= "commit-isolated" then
		print(USAGE)
		return 2
	end
	local unknown = Cli.unknownFlags(invocation, { "dry-run", "repair", "message-file" })
	if unknown ~= nil then
		print(("%s: unrecognized argument %s"):format(PREFIX, unknown))
		return 2
	end
	local parsed, problem, help = parseOptions(invocation)
	if help then
		print(USAGE)
		return 0
	end
	if parsed == nil then
		print(("%s: %s"):format(PREFIX, problem or "bad arguments"))
		return 2
	end
	if #parsed.specs == 0 then
		print(USAGE)
		return 2
	end
	return commitIsolated({ cwd = nil, say = print }, parsed)
end

local command: Cli.Command = {
	name = "git",
	summary = "Commit only your own hunks through a private index (commit-isolated).",
	usage = USAGE,
	values = { "message-file" },
	register = register,
	run = run,
}

return command
