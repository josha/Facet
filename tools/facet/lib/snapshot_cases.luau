--!strict
local Verify = require("../../vendor/verify/src/core")

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

local function within(test: Verify.Context, body: (root: string) -> ())
	local root = Files.temporaryDirectory("facet-snapshot-")
	test:defer(function()
		Files.remove(root)
	end)
	body(root)
end

local function unavailable(
	_config: Snapshot.Config,
	_scratch: string,
	_pin: Snapshot.Pin
): (Snapshot.Entries, Snapshot.Entries)
	error("upstream history is unavailable")
end

local function trackedWithoutHistory(test: Verify.Context, nested: boolean): ()
	within(test, function(root)
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
				error(("sync (check=%s) needed upstream history: %s"):format(tostring(check), message), 0)
			end
		end
		local pin = readPin(config)
		Files.write(Files.join(root, "vendor/src/init.luau"), "modified")
		if Snapshot.verify(config, pin) then
			error("a modified file verified", 0)
		end
		local code = Snapshot.sync(config, { check = true, materialize = unavailable })
		if code == 0 then
			error("--check passed a modified file", 0)
		end
		Snapshot.writeSnapshot(config, files, docs)
		Files.write(Files.join(root, config.docsDestination, "extra.md"), "unexpected")
		if Snapshot.verify(config, pin) then
			error("an extra guide file verified", 0)
		end
		Snapshot.writeSnapshot(config, files, docs)
		Files.makeDirectory(Files.join(root, "vendor/empty"))
		if Snapshot.verify(config, pin) then
			error("an empty directory verified", 0)
		end
		return
	end)
end

local function bumpAndRepair(test: Verify.Context): ()
	return within(test, function(root)
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
			error("bump failed: " .. message, 0)
		end
		local recorded = readPin(config)
		if recorded.commit ~= string.rep("b", 40) then
			error("the bump did not record the commit", 0)
		end
		if not Snapshot.verify(config, recorded) then
			error("the bumped snapshot does not verify", 0)
		end
		local before = Files.read(Files.join(root, "vendor/UPSTREAM.lock"))
		Files.write(Files.join(root, "vendor/src/init.luau"), "damaged")
		local repaired = Snapshot.sync(config, { check = false, materialize = archive })
		if repaired ~= 0 or Files.read(Files.join(root, "vendor/src/init.luau")) ~= "return {}" then
			error("the repair did not restore the file", 0)
		end
		if Files.read(Files.join(root, "vendor/UPSTREAM.lock")) ~= before then
			error("the repair changed the pin", 0)
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
			error("a wrong archive was accepted", 0)
		end
		return
	end)
end

local function relocation(test: Verify.Context): ()
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
	return Verify.expect(Snapshot.relocateGuide(config, guide, ".agents/skills/compose/SKILL.md", pin)):toBe(expected)
end

local function unsafeInputs(test: Verify.Context): ()
	local config = fixture(".", "guide")
	for _, value in { "main", "--upload-pack=bad", string.rep("a", 39) } do
		local pin = Snapshot.checkedPin(config, { commit = value, repository = "https://github.com/voidmeld/verify" })
		Verify.expect(pin):toBeNil()
	end
	for _, value in { "https://example.com/a/b", "https://github.com/a", "git@github.com:a/b" } do
		local pin = Snapshot.checkedPin(config, { commit = string.rep("a", 40), repository = value })
		Verify.expect(pin):toBeNil()
	end
	for _, value in { "../escape", "/absolute", "C:\\escape", "nested/../../escape" } do
		local name = Snapshot.safeMemberName(config, value)
		Verify.expect(name):toBeNil()
	end
	Verify.expect((Snapshot.safeMemberName(config, "src/core/init.luau"))):toBe("src/core/init.luau")
end

local function lineEndings(test: Verify.Context): ()
	return within(test, function(root)
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
			error("a CRLF checkout of an LF-pinned file did not verify", 0)
		end
		Files.write(Files.join(root, "vendor/src/init.luau"), "return {\r\n\r\n}\r\n")
		if Snapshot.verify(config, pin) then
			error("a changed CRLF file verified", 0)
		end
		return
	end)
end

function SnapshotCases.register(harness: Verify.Harness, prefix: string): ()
	harness:case(prefix .. "a tracked snapshot needs no upstream history", {
		id = prefix .. "a tracked snapshot needs no upstream history",
		run = function(test: Verify.Context)
			trackedWithoutHistory(test, false)
		end,
	})
	harness:case(prefix .. "a tracked snapshot with nested guides needs no upstream history", {
		id = prefix .. "a tracked snapshot with nested guides needs no upstream history",
		run = function(test: Verify.Context)
			trackedWithoutHistory(test, true)
		end,
	})
	harness:case(prefix .. "bump and repair materialize the same inventory", {
		id = prefix .. "bump and repair materialize the same inventory",
		run = bumpAndRepair,
	})
	harness:case(prefix .. "only links outside the copied guide are relocated", {
		id = prefix .. "only links outside the copied guide are relocated",
		run = relocation,
	})
	harness:case(prefix .. "unsafe commits, repositories and archive paths are refused", {
		id = prefix .. "unsafe commits, repositories and archive paths are refused",
		run = unsafeInputs,
	})
	harness:case(prefix .. "a CRLF checkout of LF-pinned text verifies", {
		id = prefix .. "a CRLF checkout of LF-pinned text verifies",
		run = lineEndings,
	})
end

return table.freeze(SnapshotCases)
