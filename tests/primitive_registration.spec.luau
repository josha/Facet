--!strict
--[[
	ADDING A BLUEPRINT PRIMITIVE HAS A CHECKER NOW (MAINT-5).

	A primitive — a class the adapter materialises, not a composite built from
	existing ones — touches four registries, and nothing compared them: the
	schema, `controls/contract.luau`, `CLASS_TO_INSTANCE`, and the adapter's own
	`create()` branch. `docs/extending/new-control.md` deferred the case to
	`new-engine-feature.md`, which only covers the property/modifier path, so the
	whole class of change had no playbook and no check. A class could be declared
	and be invisible to every conformance rule — which is exactly how `Grip`, a
	focusable pointer-handling control, shipped unseen — or a mapping could
	outlive the class it names, and the suite stayed green either way.

	`docs/extending/new-primitive.md` is the playbook. `tools/lune/check_primitives`
	is the check, and the mutation cases below are what say it works.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local check_primitives = require("../tools/lune/check_primitives")

describe("primitive registration (agentic maintainability, MAINT-5)", function()
	it("the live repository passes every primitive-registration rule", function()
		local result = check_primitives.check()
		local detail = if result.ok then "" else "\n" .. table.concat(result.problems, "\n")
		expect(result.ok and true or error(`check_primitives FAILED:{detail}`, 2)).toBe(true)
	end)

	it("it actually walked the surface it claims to cover", function()
		local result = check_primitives.check()
		-- 27 classes, 7 of them mapped to a non-Frame engine instance, 24 that a
		-- target has to materialise (the other three are structural regions)
		expect(result.counts.classes >= 24).toBe(true)
		expect(result.counts.mapped >= 5).toBe(true)
		expect(result.counts.materialised >= 20).toBe(true)
	end)

	it("CLASS_TO_INSTANCE is READ, not assumed — an unreadable table is a loud failure", function()
		-- the vacuous-pass guard: a parse that finds nothing must refuse rather
		-- than report "no stale mappings" over an empty set
		local ok, err = pcall(check_primitives.classToInstance, "-- an adapter with no mapping table at all")
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "no readable CLASS_TO_INSTANCE", 1, true) ~= nil).toBe(true)

		local live = check_primitives.classToInstance(require("@lune/fs").readFile("src/client/screen_target.luau"))
		expect(live.Text).toBe("TextLabel")
		expect(live.ScrollView).toBe("ScrollingFrame")
	end)

	-- NEGATIVE PROOFS: inject each shape of drift and watch the checker catch it
	it("catches a STALE MAPPING: an engine instance for a class the schema dropped", function()
		local result = check_primitives.check({ extraMapping = "Ghost" })
		expect(result.ok).toBe(false)
		expect(string.find(result.problems[1], "maps 'Ghost'", 1, true) ~= nil).toBe(true)
		expect(string.find(result.problems[1], "cannot exist", 1, true) ~= nil).toBe(true)
	end)

	it("catches an UNREGISTERED PRIMITIVE: a schema class with no contract row", function()
		local result = check_primitives.check({ extraSchemaClass = "Unregistered" })
		expect(result.ok).toBe(false)
		local named = false
		for _, problem in result.problems do
			if string.find(problem, "'Unregistered' has no row in src/controls/contract.luau", 1, true) ~= nil then
				named = true
				-- the message says WHY it matters, not just that it happened
				expect(string.find(problem, "Grip", 1, true) ~= nil).toBe(true)
			end
		end
		expect(named).toBe(true)
	end)

	it("catches a GHOST CONTRACT ROW: a contract for a class the schema does not declare", function()
		local result = check_primitives.check({ extraContractClass = "Phantom" })
		expect(result.ok).toBe(false)
		local named = false
		for _, problem in result.problems do
			if string.find(problem, "declares 'Phantom'", 1, true) ~= nil then
				named = true
			end
		end
		expect(named).toBe(true)
	end)

	it("the playbook it points at exists and covers the whole path", function()
		local source = require("@lune/fs").readFile("docs/extending/new-primitive.md")
		for _, step in
			{
				"blueprint_schema",
				"CLASS_TO_INSTANCE",
				"create()",
				"layout contract",
				"contract.luau",
				"check_primitives",
			}
		do
			expect(`{step}: {tostring(string.find(source, step, 1, true) ~= nil)}`).toBe(`{step}: true`)
		end
	end)
end)
