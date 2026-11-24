--!strict
local Verify = require("@verify/src/core")

local Files = require("./files")
local Run = require("./run")
local Snapshot = require("./snapshot")

local SnapshotCases = {}

local COMMIT = string.rep("a", 40)

local function fixture(root: string, docsDestination: string): Snapshot.Config
	return {
		name = "Fixture",
		alias = "fixture",
		root = root,
		destination = "vendor",
		docsSource = ".agents/skills/fixture",
		docsDestination = docsDestination,
		paths = { "src/core", "LICENSE" },
		stripPrefix = "src/",
		relocateDocs = false,
	}
end

local function installed(root: string): Snapshot.Source
	local directory = Files.join(root, ".lpm/fixture@" .. COMMIT)
	Files.write(Files.join(directory, "src/core/init.luau"), "return {}\n")
	Files.write(Files.join(directory, "src/core/nested/leaf.luau"), "return 1\n")
	Files.write(Files.join(directory, "src/other/skipped.luau"), "return 2\n")
	Files.write(Files.join(directory, "LICENSE"), "MIT\n")
	Files.write(Files.join(directory, ".agents/skills/fixture/SKILL.md"), "Use the public API.\n")
	return {
		directory = directory,
		docs = Files.join(directory, ".agents/skills/fixture"),
		repository = "https://github.com/voidmeld/fixture",
		commit = COMMIT,
	}
end

local function within(test: Verify.Context, body: (root: string) -> ())
	local root = Files.temporaryDirectory("facet-snapshot-")
	test:defer(function()
		Files.remove(root)
	end)
	body(root)
end

local function copiesAndChecks(test: Verify.Context, nested: boolean): ()
	within(test, function(root)
		local config = fixture(root, if nested then "vendor/guide" else "guide")
		local source = installed(root)
		Files.write(Files.join(root, "vendor/README.md"), "Owned by the consumer.\n")
		Files.write(Files.join(root, "vendor/stale.luau"), "return nil\n")
		local code, message = Snapshot.sync(config, { check = false, source = source })
		test:expect(code):toBe(0)
		test:expect(string.find(message, "copied", 1, true) ~= nil):toBe(true)
		test:expect(Files.read(Files.join(root, "vendor/core/nested/leaf.luau"))):toBe("return 1\n")
		test:expect(Files.read(Files.join(root, "vendor/license.luau"))):toBe("--!strict\nreturn [=[\nMIT\n\n]=]\n")
		test:expect(Files.read(Files.join(root, config.docsDestination, "SKILL.md"))):toBe("Use the public API.\n")
		test:expect(Files.read(Files.join(root, "vendor/README.md"))):toBe("Owned by the consumer.\n")
		test:expect(Files.exists(Files.join(root, "vendor/stale.luau"))):toBe(false)
		test:expect(Files.exists(Files.join(root, "vendor/other"))):toBe(false)
		test:expect((Snapshot.sync(config, { check = true, contentOnly = true, source = source }))):toBe(0)
	end)
end

local function checkRefusesDrift(test: Verify.Context): ()
	within(test, function(root)
		local config = fixture(root, "guide")
		local source = installed(root)
		test:expect((Snapshot.sync(config, { check = false, source = source }))):toBe(0)
		local edited = Files.join(root, "vendor/core/init.luau")
		Files.write(edited, "return { edited = true }\n")
		local code, message = Snapshot.sync(config, { check = true, contentOnly = true, source = source })
		test:expect(code):toBe(1)
		test:expect(string.find(message, "vendor/core/init.luau differs", 1, true) ~= nil):toBe(true)
		test:expect(Files.read(edited)):toBe("return { edited = true }\n")
		Files.write(edited, "return {}\n")
		Files.write(Files.join(root, "vendor/core/extra.luau"), "return {}\n")
		local extra, extraMessage = Snapshot.sync(config, { check = true, contentOnly = true, source = source })
		test:expect(extra):toBe(1)
		test:expect(string.find(extraMessage, "not in the installed package", 1, true) ~= nil):toBe(true)
		Files.remove(Files.join(root, "vendor/core/extra.luau"))
		Files.remove(Files.join(root, "guide/SKILL.md"))
		local missing, missingMessage = Snapshot.sync(config, { check = true, contentOnly = true, source = source })
		test:expect(missing):toBe(1)
		test:expect(string.find(missingMessage, "guide/SKILL.md is missing", 1, true) ~= nil):toBe(true)
	end)
end

local function sourceFromLock(test: Verify.Context): ()
	within(test, function(root)
		local config = fixture(root, "guide")
		installed(root)
		Files.write(
			Files.join(root, "pkg.lock.luau"),
			'return { version = 5, dependencies = {}, devDependencies = { fixture = "fixture@'
				.. COMMIT
				.. '" }, packages = { ["fixture@'
				.. COMMIT
				.. '"] = { name = "fixture", rev = "'
				.. COMMIT
				.. '", source = "https://github.com/voidmeld/fixture", sourceKind = "github", installPath = "@pkg/fixture/.", dependencies = {} } } }\n'
		)
		local source, problem = Snapshot.source(config)
		test:expect(problem):toBeNil()
		assert(source ~= nil)
		test:expect(source.commit):toBe(COMMIT)
		test:expect(source.directory):toBe(Files.join(root, ".lpm/fixture@" .. COMMIT))
		test:expect(source.docs):toBe(Files.join(root, ".lpm/fixture@" .. COMMIT, ".agents/skills/fixture"))
		Files.remove(Files.join(root, ".lpm"))
		local absent, absentProblem = Snapshot.source(config)
		test:expect(absent):toBeNil()
		test:expect(string.find(absentProblem or "", "lute pkg install --vendor", 1, true) ~= nil):toBe(true)
	end)
end

local function relocation(test: Verify.Context): ()
	local config = Snapshot.config(".", "compose")
	local source: Snapshot.Source = {
		directory = ".",
		repository = "https://github.com/voidmeld/compose.git",
		commit = COMMIT,
	}
	local guide =
		"[API](../../../docs/api.md#runtime) [peer](references/ownership.md#owner) [web](https://example.com) [here](#here)"
	local expected = "[API](https://github.com/voidmeld/compose/blob/"
		.. COMMIT
		.. "/docs/api.md#runtime) [peer](references/ownership.md#owner) [web](https://example.com) [here](#here)"
	return Verify.expect(Snapshot.relocateGuide(config, guide, ".agents/skills/compose/SKILL.md", source))
		:toBe(expected)
end

local function lineEndings(test: Verify.Context): ()
	return within(test, function(root)
		local config = fixture(root, "guide")
		local source = installed(root)
		test:expect((Snapshot.sync(config, { check = false, source = source }))):toBe(0)
		local path = Files.join(root, "vendor/core/init.luau")
		Files.write(path, "return {}\r\n")
		test:expect((Snapshot.sync(config, { check = true, contentOnly = true, source = source }))):toBe(0)
		Files.write(path, "return {\r\n}\r\n")
		test:expect((Snapshot.sync(config, { check = true, contentOnly = true, source = source }))):toBe(1)
	end)
end

local function executableModes(test: Verify.Context)
	within(test, function(root)
		local config = fixture(root, "guide")
		local source = installed(root)
		test:expect((Snapshot.sync(config, { check = false, source = source }))):toBe(0)
		assert(Run.git({ "init", "-q" }, root).ok, "git init failed")
		assert(Run.git({ "add", "vendor", "guide" }, root).ok, "git add failed")
		assert(Run.git({ "update-index", "--chmod=+x", "--", "vendor/core/init.luau" }, root).ok, "chmod failed")
		local executables = Snapshot.executables(config)
		test:expect(table.find(executables, "vendor/core/init.luau") ~= nil):toBe(true)
		local code, message = Snapshot.sync(config, { check = true, source = source })
		test:expect(code):toBe(1)
		test:expect(string.find(message, "mode 100644", 1, true) ~= nil):toBe(true)
		test:expect((Snapshot.sync(config, { check = true, contentOnly = true, source = source }))):toBe(0)
		local repaired = Snapshot.sync(config, { check = false, source = source })
		test:expect(repaired):toBe(0)
		test:expect(Snapshot.executables(config)):toEqual({})
		test:expect((Snapshot.sync(config, { check = true, source = source }))):toBe(0)
	end)
end

function SnapshotCases.register(harness: Verify.Harness, prefix: string): ()
	harness:case(prefix .. "sync copies the installed package and check accepts the copy", {
		id = prefix .. "sync copies the installed package and check accepts the copy",
		run = function(test: Verify.Context)
			copiesAndChecks(test, false)
		end,
	})
	harness:case(prefix .. "sync copies nested guides and check accepts the copy", {
		id = prefix .. "sync copies nested guides and check accepts the copy",
		run = function(test: Verify.Context)
			copiesAndChecks(test, true)
		end,
	})
	harness:case(prefix .. "check refuses edited, extra and missing files without writing", {
		id = prefix .. "check refuses edited, extra and missing files without writing",
		run = checkRefusesDrift,
	})
	harness:case(prefix .. "the source is the locked package in .lpm", {
		id = prefix .. "the source is the locked package in .lpm",
		run = sourceFromLock,
	})
	harness:case(prefix .. "only links outside the copied guide are relocated", {
		id = prefix .. "only links outside the copied guide are relocated",
		run = relocation,
	})
	harness:case(prefix .. "generated files keep mode 100644", {
		id = prefix .. "generated files keep mode 100644",
		run = executableModes,
	})
	harness:case(prefix .. "a CRLF checkout of LF text verifies", {
		id = prefix .. "a CRLF checkout of LF text verifies",
		run = lineEndings,
	})
end

return table.freeze(SnapshotCases)
