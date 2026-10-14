--!strict

local Case = require("./case")
local Files = require("./files")
local Json = require("./json")
local Snapshot = require("./snapshot")

local SnapshotCases = {}

local function fixture(root: string, docsDestination: string): Snapshot.Config
	return {
		name = "Fixture",
		root = root,
		destination = "vendor",
		docsSource = "guide",
		docsDestination = docsDestination,
		paths = {},
		stripPrefix = "",
		relocateDocs = false,
	}
end

local function writePin(config: Snapshot.Config, pin: { [string]: unknown })
	Files.write(Files.join(config.root, config.destination, "UPSTREAM.lock"), Json.encode(pin))
end

local function readPin(config: Snapshot.Config): Snapshot.Pin
	local document = Json.decode(Files.read(Files.join(config.root, config.destination, "UPSTREAM.lock")))
	local pin, problem = Snapshot.checkedPin(config, document)
	assert(pin, problem)
	return pin
end

local function within(body: (root: string) -> string?): string?
	local root = Files.temporaryDirectory("facet-snapshot-")
	local ok, result = pcall(body, root)
	Files.remove(root)
	if not ok then
		return "raised: " .. tostring(result)
	end
	return result
end

local function unavailable(
	_config: Snapshot.Config,
	_scratch: string,
	_pin: Snapshot.Pin
): (Snapshot.Entries, Snapshot.Entries)
	error("upstream history is unavailable")
end

local function trackedWithoutHistory(nested: boolean): string?
	return within(function(root)
		local config = fixture(root, if nested then "vendor/guide" else "guide")
		local files: Snapshot.Entries = { ["src/init.luau"] = "return {}" }
		local docs: Snapshot.Entries = { ["SKILL.md"] = "Use the public API." }
		Snapshot.writeSnapshot(config, files, docs)
		writePin(config, {
			repository = "https://github.com/voidmeld/deleted-history",
			commit = string.rep("a", 40),
			sha256 = Snapshot.inventory(files),
			docs = Snapshot.inventory(docs),
		})
		for _, check in { true, false } do
			local code, message = Snapshot.sync(config, { check = check, materialize = unavailable })
			if code ~= 0 then
				return ("sync (check=%s) needed upstream history: %s"):format(tostring(check), message)
			end
		end
		local pin = readPin(config)
		Files.write(Files.join(root, "vendor/src/init.luau"), "modified")
		if Snapshot.verify(config, pin) then
			return "a modified file verified"
		end
		local code = Snapshot.sync(config, { check = true, materialize = unavailable })
		if code == 0 then
			return "--check passed a modified file"
		end
		Snapshot.writeSnapshot(config, files, docs)
		Files.write(Files.join(root, config.docsDestination, "extra.md"), "unexpected")
		if Snapshot.verify(config, pin) then
			return "an extra guide file verified"
		end
		Snapshot.writeSnapshot(config, files, docs)
		Files.makeDirectory(Files.join(root, "vendor/empty"))
		if Snapshot.verify(config, pin) then
			return "an empty directory verified"
		end
		return nil
	end)
end

local function bumpAndRepair(): string?
	return within(function(root)
		local config = fixture(root, "guide")
		Files.makeDirectory(Files.join(root, "vendor"))
		writePin(config, {
			repository = "https://github.com/voidmeld/verify",
			commit = string.rep("a", 40),
			sha256 = Json.object(),
			docs = Json.object(),
		})
		local files: Snapshot.Entries = { ["src/init.luau"] = "return {}" }
		local docs: Snapshot.Entries = { ["SKILL.md"] = "Public API" }
		local function archive(
			_config: Snapshot.Config,
			_scratch: string,
			_pin: Snapshot.Pin
		): (Snapshot.Entries, Snapshot.Entries)
			return files, docs
		end
		local code, message =
			Snapshot.sync(config, { check = false, bump = string.rep("b", 40), materialize = archive })
		if code ~= 0 then
			return "bump failed: " .. message
		end
		local recorded = readPin(config)
		if recorded.commit ~= string.rep("b", 40) then
			return "the bump did not record the commit"
		end
		if not Snapshot.verify(config, recorded) then
			return "the bumped snapshot does not verify"
		end
		local before = Files.read(Files.join(root, "vendor/UPSTREAM.lock"))
		Files.write(Files.join(root, "vendor/src/init.luau"), "damaged")
		local repaired = Snapshot.sync(config, { check = false, materialize = archive })
		if repaired ~= 0 or Files.read(Files.join(root, "vendor/src/init.luau")) ~= "return {}" then
			return "the repair did not restore the file"
		end
		if Files.read(Files.join(root, "vendor/UPSTREAM.lock")) ~= before then
			return "the repair changed the pin"
		end
		Files.remove(Files.join(root, "vendor/src/init.luau"))
		local function wrong(
			_config: Snapshot.Config,
			_scratch: string,
			_pin: Snapshot.Pin
		): (Snapshot.Entries, Snapshot.Entries)
			return { ["src/init.luau"] = "wrong archive" }, docs
		end
		local refused = Snapshot.sync(config, { check = false, materialize = wrong })
		if refused == 0 then
			return "a wrong archive was accepted"
		end
		return nil
	end)
end

local function relocation(): string?
	local config: Snapshot.Config = {
		name = "Compose",
		root = ".",
		destination = "vendor",
		docsSource = ".agents/skills/compose",
		docsDestination = "guide",
		paths = {},
		stripPrefix = "",
		relocateDocs = true,
	}
	local pin: Snapshot.Pin = {
		repository = "https://github.com/voidmeld/compose.git",
		commit = string.rep("a", 40),
		sha256 = {},
		docs = {},
		document = Json.object(),
	}
	local guide =
		"[API](../../../docs/api.md#runtime) [peer](references/ownership.md#owner) [web](https://example.com) [here](#here)"
	local expected = "[API](https://github.com/voidmeld/compose/blob/"
		.. pin.commit
		.. "/docs/api.md#runtime) [peer](references/ownership.md#owner) [web](https://example.com) [here](#here)"
	return Case.equal(Snapshot.relocateGuide(config, guide, ".agents/skills/compose/SKILL.md", pin), expected)
end

local function unsafeInputs(): string?
	local config = fixture(".", "guide")
	for _, value in { "main", "--upload-pack=bad", string.rep("a", 39) } do
		local pin = Snapshot.checkedPin(config, { commit = value, repository = "https://github.com/voidmeld/verify" })
		if pin ~= nil then
			return "accepted the commit " .. value
		end
	end
	for _, value in { "https://example.com/a/b", "https://github.com/a", "git@github.com:a/b" } do
		local pin = Snapshot.checkedPin(config, { commit = string.rep("a", 40), repository = value })
		if pin ~= nil then
			return "accepted the repository " .. value
		end
	end
	for _, value in { "../escape", "/absolute", "C:\\escape", "nested/../../escape" } do
		local name = Snapshot.safeMemberName(config, value)
		if name ~= nil then
			return "accepted the archive member " .. value
		end
	end
	if Snapshot.safeMemberName(config, "src/core/init.luau") == nil then
		return "refused a safe archive member"
	end
	return nil
end

local function lineEndings(): string?
	return within(function(root)
		local config = fixture(root, "guide")
		local files: Snapshot.Entries = { ["src/init.luau"] = "return {\n}\n" }
		local docs: Snapshot.Entries = { ["SKILL.md"] = "Guide\n" }
		Snapshot.writeSnapshot(config, files, docs)
		writePin(config, {
			repository = "https://github.com/voidmeld/verify",
			commit = string.rep("a", 40),
			sha256 = Snapshot.inventory(files),
			docs = Snapshot.inventory(docs),
		})
		Files.write(Files.join(root, "vendor/src/init.luau"), "return {\r\n}\r\n")
		local pin = readPin(config)
		if not Snapshot.verify(config, pin) then
			return "a CRLF checkout of an LF-pinned file did not verify"
		end
		Files.write(Files.join(root, "vendor/src/init.luau"), "return {\r\n\r\n}\r\n")
		if Snapshot.verify(config, pin) then
			return "a changed CRLF file verified"
		end
		return nil
	end)
end

function SnapshotCases.cases(): { Case.Case }
	return {
		{
			name = "a tracked snapshot needs no upstream history",
			run = function()
				return trackedWithoutHistory(false)
			end,
		},
		{
			name = "a tracked snapshot with nested guides needs no upstream history",
			run = function()
				return trackedWithoutHistory(true)
			end,
		},
		{ name = "bump and repair materialize the same inventory", run = bumpAndRepair },
		{ name = "only links outside the copied guide are relocated", run = relocation },
		{ name = "unsafe commits, repositories and archive paths are refused", run = unsafeInputs },
		{ name = "a CRLF checkout of LF-pinned text verifies", run = lineEndings },
	}
end

return table.freeze(SnapshotCases)
