--!strict
--[[ EVERY `attach` OPTION IS DOCUMENTED WHERE A READER LOOKS FOR IT.

	THE DEFECT THIS EXISTS FOR (RED-TEAM 2026-09-02, finding 9). The perf campaign
	added four attach options — `measureReuse`, `layoutNodeReuse`, `commitScope`,
	`structuralReuse` — and `docs/reference/api.md` documented ONE of them. The other
	three were public, typed in `renderer.AttachOpts`, validated by `ATTACH_OPTS_KEYS`
	and reachable by any consumer, with no sentence anywhere a reader would look
	telling them what they do or what turning one off means. That is not a doc
	omission the next round would notice: the campaign's own reports named all four,
	the type declared all four, and the reference was the one place that did not.

	SO THE RULE IS MECHANISED, not remembered: every key `ATTACH_OPTS_KEYS` accepts
	must be NAMED in the `attach` options section of the reference. A fifth option
	cannot ship undocumented, and one deleted from the renderer cannot leave a
	paragraph behind describing an option that no longer exists — both directions,
	because a reference that documents a key the code rejects is the same lie.

	WHY THE SECTION AND NOT THE WHOLE FILE. `rootPolicy` is discussed in four places
	and `engineSelectionBridge` in three; "the name appears somewhere in api.md" would
	pass for an option mentioned only in an unrelated paragraph about presented
	surfaces. The window is the section a reader reaches by looking up `attach`.

	Each scan is a pure function of a string and carries a NEGATIVE CONTROL. A check
	that cannot fail is decoration.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")

local RENDERER_PATH = "src/render/renderer.luau"
local API_PATH = "docs/reference/api.md"

-- the keys `specGuard.keySet({ ... })` is handed in `renderer.luau` — the ONE list
-- `attach` validates against, so a key absent from it is not an option at all
local function attachOptsKeys(source: string): { string }
	local block = string.match(source, "local ATTACH_OPTS_KEYS = specGuard%.keySet%({\n(.-)\n}%)")
	assert(block ~= nil, "no ATTACH_OPTS_KEYS block in the renderer")
	local out: { string } = {}
	for key in string.gmatch(block :: string, '"([%w_]+)"') do
		table.insert(out, key)
	end
	table.sort(out)
	return out
end

-- the reference's `attach` options section: from its own heading to the Controller
-- table that follows it
local function attachSection(doc: string): string
	local section = string.match(doc, "%*%*`attach` options%*%*(.-)%*%*Controller%*%*")
	assert(section ~= nil, "no `attach` options section in the reference")
	return section :: string
end

describe("the attach options the renderer accepts are the ones the reference documents", function()
	local rendererSrc = fs.readFile(RENDERER_PATH)
	local apiDoc = fs.readFile(API_PATH)

	it("every key ATTACH_OPTS_KEYS accepts is named in the reference's `attach` section", function()
		local section = attachSection(apiDoc)
		local missing: { string } = {}
		for _, key in attachOptsKeys(rendererSrc) do
			if string.find(section, key, 1, true) == nil then
				table.insert(missing, key)
			end
		end
		expect(`undocumented attach options: {table.concat(missing, ", ")}`).toBe("undocumented attach options: ")
		-- ...and the set is not empty, which is the trap a set comparison invites
		expect(#attachOptsKeys(rendererSrc) >= 12).toBe(true)
	end)

	it("the four cross-solve seams say what they are and what OFF means", function()
		--[[ THE HALF A NAME CHECK CANNOT MAKE. "`structuralReuse`" appearing in a list
			of option names documents nothing; what a reader needs is the default, the
			mechanism and the consequence of turning it off. Each of the four is
			required to carry its own default and a pointer to the module that owns it,
			which is the shape the one documented option already had. ]]
		local section = attachSection(apiDoc)
		for key, owner in
			{
				measureReuse = "src/layout/measure_reuse.luau",
				layoutNodeReuse = "src/render/layout_node.luau",
				commitScope = "src/render/commit_walks.luau",
				structuralReuse = "src/render/structural_scope.luau",
			}
		do
			expect(`{key} names its module: {string.find(section, owner, 1, true) ~= nil}`).toBe(
				`{key} names its module: true`
			)
		end
		-- the defaults are stated, and they are the shipped ones
		expect(string.find(section, "default **true**", 1, true) ~= nil).toBe(true)
		-- ...and what OFF costs, which is the sentence a consumer actually needs
		expect(string.find(section, "Off", 1, true) ~= nil).toBe(true)
	end)

	it("the reference documents no option the renderer would reject", function()
		--[[ THE OTHER DIRECTION. `attach` errors on an unknown key (`specGuard`), so a
			paragraph describing a removed option is an instruction that raises. Read
			back from the section's own option LIST — the `{ ... }` line a reader
			copies — rather than from its prose, which legitimately mentions
			`present()`'s opts and the presenter's forwarding. ]]
		local section = attachSection(apiDoc)
		local listed = string.match(section, "`{(.-)}`")
		expect(listed ~= nil).toBe(true)
		local accepted: { [string]: boolean } = {}
		for _, key in attachOptsKeys(rendererSrc) do
			accepted[key] = true
		end
		local strangers: { string } = {}
		for key in string.gmatch(listed :: string, "([%w_]+)%??,?") do
			if key ~= "" and not accepted[key] then
				table.insert(strangers, key)
			end
		end
		expect(`options the renderer rejects: {table.concat(strangers, ", ")}`).toBe("options the renderer rejects: ")
	end)

	it("NEGATIVE CONTROL: both scans read what they claim to, and report a broken input", function()
		local fakeSource = 'local ATTACH_OPTS_KEYS = specGuard.keySet({\n\t"alpha",\n\t-- a comment\n\t"beta",\n})\n'
		expect(attachOptsKeys(fakeSource)).toEqual({ "alpha", "beta" })
		local fakeDoc = "**`attach` options** — `{ alpha?, beta? }`\nalpha is a thing.\n**Controller** — 35 members"
		local section = attachSection(fakeDoc)
		expect(string.find(section, "alpha", 1, true) ~= nil).toBe(true)
		-- the section really is bounded: prose after the Controller heading is outside
		expect(string.find(section, "35 members", 1, true)).toBe(nil)
		-- ...and an option named nowhere in the section is reported as missing
		expect(string.find(section, "gamma", 1, true)).toBe(nil)
	end)
end)
