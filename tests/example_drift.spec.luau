--!strict
-- EXAMPLE PROPERTY-AUTHORITY DRIFT LINT (roadmap Step 10). A literal in a
-- tutorial example is invisible in review and invisible to the suite — 24 is
-- still 24 under Studio Neutral — while making that example immune to the very
-- theme picker mounted beside it. So the check runs here, AND it is proven to
-- FAIL: a lint nobody has watched fail is a lint nobody knows works.
--
-- The negative controls matter more here than usual, because this lint's whole
-- claim is that it understands property AUTHORITY rather than banning numbers.
-- Each case below injects one shape of violation and requires the lint to name
-- it, and the last two require it NOT to fire on the legal forms.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local drift = require("../tools/lune/check_example_drift")

local EXAMPLE = "examples/gallery/examples/01_temperature_converter.luau"

local function inject(line: string)
	return drift.check({ injectFile = EXAMPLE, injectLine = line })
end

local function names(result: any, needle: string): boolean
	for _, problem in result.problems do
		if string.find(problem, needle, 1, true) ~= nil then
			return true
		end
	end
	return false
end

describe("no tutorial example bypasses property authority", function()
	it("the seven examples are clean", function()
		local result = drift.check()
		local detail = if result.ok then "" else "\n" .. table.concat(result.problems, "\n")
		expect(result.ok and true or error(`example drift lint FAILED:{detail}`, 2)).toBe(true)
	end)

	it("it actually scanned the examples, and saw real semantic values there", function()
		local result = drift.check()
		expect(result.counts.files >= 7).toBe(true)
		expect(result.counts.lines > 1500).toBe(true)
		-- the discriminator between "clean" and "nothing to check": the examples
		-- really do carry semantic roles/steps, in quantity
		expect(result.counts.roleUses >= 40).toBe(true)
	end)

	it("the allowlist is not a mute: every entry carries a reason", function()
		expect(#drift.ALLOWLIST >= 1).toBe(true)
		for _, entry in drift.ALLOWLIST do
			expect(#entry.why > 40).toBe(true)
			expect(#entry.match > 0).toBe(true)
		end
	end)
end)

describe("the example drift lint bites", function()
	it("R1: a px text size", function()
		local result = inject("local bad = UI.Text({ id = 'X', text = 'x', textSize = 24 })")
		expect(result.ok).toBe(false)
		expect(names(result, "[R1]")).toBe(true)
		expect(names(result, "textSize = 24")).toBe(true)
	end)

	it("R1: a numeric padding and a numeric gap", function()
		expect(inject("local bad = UI.VStack({ id = 'X', padding = 16 })").ok).toBe(false)
		expect(inject("local bad = UI.VStack({ id = 'X', gap = 8 })").ok).toBe(false)
	end)

	it("R1: a fixed-pixel dimension", function()
		local result = inject('local bad = { type = "fixed", px = 48 }')
		expect(result.ok).toBe(false)
		expect(names(result, "dimension px = 48")).toBe(true)
	end)

	it("R1 does NOT fire on zero spacing, which is structure rather than style", function()
		expect(inject("local ok = UI.VStack({ id = 'X', padding = 0, gap = 0 })").ok).toBe(true)
	end)

	it("R2: an INVENTED surface token — the defect that made the word-game board invisible", function()
		local result = inject('local bad = UI.ZStack({ id = "X", surface = "tileCorrect" })')
		expect(result.ok).toBe(false)
		expect(names(result, "[R2]")).toBe(true)
		expect(names(result, "tileCorrect")).toBe(true)
	end)

	it("R2: a typography role that does not exist", function()
		local result = inject('local bad = UI.Text({ id = "X", text = "x", textSize = "gigantic" })')
		expect(result.ok).toBe(false)
		expect(names(result, "gigantic")).toBe(true)
	end)

	it("R2: a tint naming a palette role the framework does not resolve", function()
		local result = inject('local bad = { tint = { role = "sparkly", blend = 1 } }')
		expect(result.ok).toBe(false)
		expect(names(result, "sparkly")).toBe(true)
	end)

	it("R2 does NOT fire on the legal vocabularies", function()
		-- read from the framework, so this passes only while the lint really is
		-- asking the framework rather than carrying its own copy of the list
		expect(inject('local ok = UI.Text({ id = "X", text = "x", textSize = "title" })').ok).toBe(true)
		expect(inject('local ok = UI.Box({ id = "X", surface = "raised" })').ok).toBe(true)
		expect(inject('local ok = { tint = { role = "accent", blend = 0.5 } }').ok).toBe(true)
		expect(inject('local ok = UI.Text({ id = "X", text = "x", role = "secondary" })').ok).toBe(true)
		-- ...and on a theme METRIC PATH, which is the other legal spelling
		expect(inject('local ok = { type = "fixed", px = "targetSizes.minimum" }').ok).toBe(true)
		expect(inject('local ok = UI.VStack({ id = "X", padding = "m", gap = "xs" })').ok).toBe(true)
	end)

	it("R3: a raw colour, in each of its three spellings", function()
		expect(inject("local bad = Color3.fromRGB(120, 200, 90)").ok).toBe(false)
		expect(inject('local bad = { tint = { direct = "#3aa0ff" } }').ok).toBe(false)
		expect(inject("local bad = { r = 0.2, g = 0.6, b = 0.9 }").ok).toBe(false)
	end)

	it("R4: an engine or adapter reach-around", function()
		expect(inject('local bad = Instance.new("Frame")').ok).toBe(false)
		expect(inject('local bad = game:GetService("UserInputService")').ok).toBe(false)
		expect(inject('adapter.setProp(handle, "text", "x", "binding")').ok).toBe(false)
		expect(inject("local bad = TweenService:Create(x, y, z)").ok).toBe(false)
		expect(inject('local bad = workspace:GetAttribute("Thing")').ok).toBe(false)
	end)

	it("R4: a platform branch is refused by name", function()
		local result = inject("if input.UserInputType == Enum.UserInputType.Touch then end")
		expect(result.ok).toBe(false)
		expect(names(result, "platform branch")).toBe(true)
	end)

	it("the allowlist suppresses ONLY its own line, in its own file", function()
		-- the same text injected into a DIFFERENT example is still a violation:
		-- an allowlist entry is a statement about one place, not a global mute
		local result = drift.check({
			injectFile = "examples/gallery/examples/01_temperature_converter.luau",
			injectLine = 'local bad = { width = { type = "fixed", px = 144 } }',
		})
		expect(result.ok).toBe(false)
	end)
end)
