--!strict
--[[ THE NUMERIC FIELD — the text engine with the number contract on top, through
	the public `UI.NumberInput` preset. What is proved is only what is new: the
	draft grammar, what a commit reports, rounding and bounds, units beside the
	editor, and the two step buttons. Typing goes through the adapter's text seam;
	buttons through `adapter.tap`/`touchTap` and the action system's keys. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local world = require("./lib/world")
local arithmetic = require("../src/arithmetic")
local snapshot = require("../src/themes/snapshot")

local FLOOR = snapshot.neutral().targetSizes.minimum
local ROW = "/S/Laps/Input/Row"
local FIELD, DEC, INC = ROW .. "/Field", ROW .. "/Decrement", ROW .. "/Increment"
local PLAIN_FIELD = "/S/Laps/Input/Field"

local function numberWorld(spec: any?): any
	local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 400 } })
	local Compose = w.Compose
	local o = spec or {}
	w.draft = Compose.cell(o.draft or "3")
	w.number = Compose.cell(o.number or 3)
	w.commits = {}
	w.changes = {}
	local merged: any = {
		value = w.draft,
		numericValue = w.number,
		onCommit = function(value: any, reason: string)
			table.insert(w.commits, { value = value, reason = reason })
		end,
		onChange = function(text: string)
			table.insert(w.changes, text)
		end,
		ref = function(record)
			w.control = record
		end,
	}
	for key, entry in o do
		if key ~= "draft" and key ~= "number" then
			merged[key] = entry
		end
	end
	w.present(function()
		return w.UI.Screen("S")({ w.UI.NumberInput("Laps")(merged) })
	end, { sinkNavigation = true })
	return w
end

-- the draft is written the way the owner's cell holds it, so the commit sees
-- exactly `text` (the fake's buffer starts from the value already shown)
local function editAndCommit(w: any, path: string, text: string)
	w.adapter.tap(path)
	w.adapter.focusText(path)
	w.draft:set(text)
	w.adapter.commitText(path)
	w.settle()
end

local function press(w: any, input: string, path: string)
	if input == "pointer" then
		w.adapter.tap(path)
	elseif input == "touch" then
		w.adapter.touchTap(path)
	else
		w.pres.focus.focusOn(path)
		w.pres.refresh()
		w.press(if input == "keyboard" then "Return" else "ButtonA")
	end
	w.settle()
end

describe("NumberInput: the preset is the presentation", function()
	it("it is the text engine with the number contract, and refuses a second presentation", function()
		local w = numberWorld()
		expect(w.control.dump().presentation).toBe("number")
		local ok, err = pcall(function()
			w.scoped(function()
				return w.UI.NumberInput("Other")({
					value = w.Compose.cell("1"),
					numericValue = w.Compose.cell(1),
					presentation = "search",
				})
			end)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "IS the number presentation", 1, true) ~= nil).toBe(true)
	end)

	it("step must be finite and above zero, precision a whole count of places, units strings", function()
		local w = world.new()
		for _, bad in
			{
				{ step = 0 },
				{ step = -1 },
				{ step = math.huge },
				{ precision = 1.5 },
				{ precision = 11 },
				{ prefix = 4 },
			}
		do
			local ok = pcall(function()
				w.scoped(function()
					local spec: any = { value = w.Compose.cell("1"), numericValue = w.Compose.cell(1) }
					for key, entry in bad do
						spec[key] = entry
					end
					return w.UI.NumberInput("N")(spec)
				end)
			end)
			expect(ok).toBe(false)
		end
		-- ...and the number keys belong to the number presentation only
		local ok = pcall(function()
			w.scoped(function()
				return w.UI.TextInput("T")({ value = w.Compose.cell(""), stepButtons = true })
			end)
		end)
		expect(ok).toBe(false)
	end)
end)

describe("NumberInput: the draft grammar", function()
	it("an incomplete draft reverts in silence, and says so only when the field is required", function()
		for _, draft in { "", "-", ".", "-.", "\u{2212}" } do
			local w = numberWorld({ draft = "7", number = 7 })
			editAndCommit(w, PLAIN_FIELD, draft)
			expect(`[{draft}] {w.draft:peek()} {w.number:peek()} {#w.commits}`).toBe(`[{draft}] 7 7 0`)
			expect(w.control.dump().validationError).toBe("")
		end
		local required = numberWorld({ draft = "7", number = 7, requiredMark = "required", label = "Laps" })
		editAndCommit(required, "/S/Laps/Input/Field", "")
		expect(required.control.dump().validationError ~= "").toBe(true)
		expect(`{required.draft:peek()} {#required.commits}`).toBe("7 0")
	end)

	it("the default parser is the strict grammar, not the language's own reader", function()
		expect(arithmetic.number("42")).toBe(42)
		expect(arithmetic.number("-2.5")).toBe(-2.5)
		expect(arithmetic.number("\u{2212}2")).toBe(-2)
		for _, bad in { "1e5", "0x10", "1,000", " 7 ", "1.2.3", "inf", "nan" } do
			expect(`{bad}: {arithmetic.number(bad)}`).toBe(`{bad}: nil`)
		end
		local w = numberWorld()
		editAndCommit(w, PLAIN_FIELD, "1e5")
		expect(w.control.dump().validationError ~= "").toBe(true)
		expect(`{w.number:peek()} {w.draft:peek()} {#w.commits}`).toBe("3 1e5 0")
	end)
end)

describe("NumberInput: what a commit reports", function()
	it("a commit reports the NUMBER first, and the string is only how it is written", function()
		local w = numberWorld({ draft = "", number = 0 })
		editAndCommit(w, PLAIN_FIELD, "12")
		expect(#w.commits).toBe(1)
		expect(`{w.commits[1].value} {typeof(w.commits[1].value)} {w.commits[1].reason}`).toBe("12 number enter")
		expect(w.number:peek()).toBe(12)
	end)

	it("an out-of-range commit clamps and says `clamped` rather than refusing", function()
		local w = numberWorld({ draft = "", number = 1, min = 1, max = 9 })
		editAndCommit(w, PLAIN_FIELD, "99")
		expect(`{w.commits[1].value} {w.commits[1].reason} {w.draft:peek()}`).toBe("9 clamped 9")
		expect(w.control.dump().validationError).toBe("")
		local low = numberWorld({ draft = "", number = 5, min = 1, max = 9 })
		editAndCommit(low, PLAIN_FIELD, "-4")
		expect(`{low.commits[1].value} {low.commits[1].reason}`).toBe("1 clamped")
	end)

	it("precision rounds half away from zero, at commit and never while typing", function()
		local w = numberWorld({ draft = "", number = 0, precision = 1 })
		w.adapter.tap(PLAIN_FIELD)
		w.adapter.focusText(PLAIN_FIELD)
		w.adapter.typeText(PLAIN_FIELD, "0.15")
		w.settle()
		expect(w.draft:peek()).toBe("0.15")
		w.adapter.commitText(PLAIN_FIELD)
		w.settle()
		expect(`{w.number:peek()} {w.draft:peek()}`).toBe("0.2 0.2")
		local negative = numberWorld({ draft = "", number = 0, precision = 1 })
		editAndCommit(negative, PLAIN_FIELD, "-0.15")
		expect(negative.number:peek()).toBe(-0.2)
		-- a finite value too large to shift keeps its value rather than becoming inf
		local huge = numberWorld({ draft = "", number = 0, precision = 10 })
		editAndCommit(huge, PLAIN_FIELD, "1" .. string.rep("0", 300))
		expect(`{huge.number:peek() == 1e300} {#huge.commits}`).toBe("true 1")
	end)

	it("a callback that disposes the control mid-commit leaves nothing half-written", function()
		for _, callback in { "parse", "format" } do
			local w = world.new()
			local draft, number = w.Compose.cell("1"), w.Compose.cell(1)
			local visible = w.Compose.cell(true)
			local commits = 0
			local spec: any = {
				value = draft,
				numericValue = number,
				onCommit = function()
					commits += 1
				end,
			}
			spec[callback] = function(input: any)
				visible:set(false)
				w.settle()
				return if callback == "parse" then tonumber(input) else tostring(input)
			end
			w.present(function()
				return w.UI.Screen("S")({
					w.UI.When({
						condition = visible,
						thenView = function()
							return w.UI.NumberInput("Laps")(spec)
						end,
					}),
				})
			end, { sinkNavigation = true })
			local path: string? = nil
			for _, candidate in w.adapter.paths() do
				if string.sub(candidate, -#"/Laps/Input/Field") == "/Laps/Input/Field" then
					path = candidate
				end
			end
			assert(path ~= nil, "no mounted numeric field")
			w.adapter.tap(path)
			w.adapter.focusText(path)
			draft:set("2")
			w.adapter.commitText(path)
			w.settle()
			expect(`{callback}: {number:peek()} {commits}`).toBe(`{callback}: 1 0`)
			expect(w.core.lastError()).toBeNil()
		end
	end)
end)

describe("NumberInput: units and step buttons", function()
	it("a prefix and a suffix stand beside the editor and never enter the draft", function()
		local w = numberWorld({ draft = "", number = 0, prefix = "$", suffix = "/lap" })
		local prefix, suffix = w.adapter.node(ROW .. "/Prefix"), w.adapter.node(ROW .. "/Suffix")
		local field = w.adapter.node(FIELD).rect
		expect(prefix.rect.x + prefix.rect.w <= field.x).toBe(true)
		expect(suffix.rect.x >= field.x + field.w).toBe(true)
		w.adapter.tap(FIELD)
		w.adapter.focusText(FIELD)
		w.adapter.typeText(FIELD, "12")
		w.settle()
		expect(w.draft:peek()).toBe("12")
	end)

	it("a step button moves the value by one step on pointer, touch, keyboard and gamepad", function()
		for _, input in { "pointer", "touch", "keyboard", "gamepad" } do
			local w = numberWorld({ draft = "4", number = 4, stepButtons = true, step = 2, min = 0, max = 20 })
			press(w, input, INC)
			expect(`{input}: {w.number:peek()} {w.draft:peek()}`).toBe(`{input}: 6 6`)
			local last = w.commits[#w.commits]
			expect(`{input}: {last.value} {last.reason} {w.changes[#w.changes]}`).toBe(`{input}: 6 submit 6`)
			press(w, input, DEC)
			expect(`{input}: {w.number:peek()}`).toBe(`{input}: 4`)
		end
	end)

	it("a press goes through the typed path's rounding and clamping, bounded or not", function()
		-- 0.1 + 0.2 is not 0.3 in floating point; the press rounds like a commit
		local open = numberWorld({ draft = "0.1", number = 0.1, stepButtons = true, step = 0.2, precision = 1 })
		press(open, "pointer", INC)
		expect(`{open.number:peek() == 0.3} {open.draft:peek()}`).toBe("true 0.3")
		editAndCommit(open, FIELD, "0.25")
		expect(open.number:peek() == 0.3).toBe(true)
		-- bounded, the step grid is the value family's own, measured from `min`
		local bounded = numberWorld({
			draft = "0.8",
			number = 0.8,
			stepButtons = true,
			step = 0.2,
			min = 0,
			max = 1,
			precision = 1,
		})
		press(bounded, "pointer", INC)
		expect(`{bounded.number:peek() == 1} {bounded.draft:peek()}`).toBe("true 1.0")
		expect(bounded.adapter.node(INC).props.enabled).toBe(false)
	end)

	it("the step buttons are square targets that meet the touch floor and never share a pixel", function()
		local w = numberWorld({ stepButtons = true, min = 0, max = 20 })
		local dec, inc = w.adapter.node(DEC).rect, w.adapter.node(INC).rect
		for _, rect in { dec, inc } do
			expect(rect.w >= FLOOR and rect.h >= FLOOR).toBe(true)
		end
		expect(w.adapter.hitRectOf(DEC)).toBeNil()
		expect(w.adapter.hitRectOf(INC)).toBeNil()
		expect(dec.x + dec.w <= inc.x).toBe(true)
	end)

	it("the step buttons are ordinary focus stops, after the editor and its clear", function()
		local w =
			numberWorld({ draft = "4", number = 4, stepButtons = true, clearButtonMode = "always", min = 0, max = 20 })
		local order: { string } = {}
		for _, entry in w.handle.focusOrder().traversal do
			table.insert(order, tostring(entry.path))
		end
		expect(table.concat(order, " ")).toBe(`{FIELD} {ROW}/Clear {DEC} {INC}`)
		w.pres.focus.focusOn(DEC)
		w.pres.refresh()
		w.press("Right")
		w.settle()
		expect(w.number:peek()).toBe(4) -- the arrow navigated; it did not adjust
	end)

	it("at the end of its range, read-only or disabled, the button SAYS so and refuses on every input", function()
		local cases = {
			{ name = "at max", spec = { draft = "20", number = 20 }, path = INC },
			{ name = "at min", spec = { draft = "0", number = 0 }, path = DEC },
			{ name = "read-only", spec = { draft = "8", number = 8, readOnly = true }, path = INC },
			{ name = "disabled", spec = { draft = "8", number = 8, enabled = false }, path = INC },
		}
		for _, case in cases do
			for _, input in { "pointer", "touch", "keyboard", "gamepad" } do
				local spec: any = { stepButtons = true, step = 5, min = 0, max = 20 }
				for key, entry in case.spec do
					spec[key] = entry
				end
				local w = numberWorld(spec)
				local before = w.number:peek()
				expect(`{case.name}: {w.adapter.node(case.path).props.enabled}`).toBe(`{case.name}: false`)
				press(w, input, case.path)
				expect(`{case.name}/{input}: {w.number:peek()} {#w.commits}`).toBe(`{case.name}/{input}: {before} 0`)
			end
		end
		local low = numberWorld({ draft = "0", number = 0, stepButtons = true, step = 5, min = 0, max = 20 })
		expect(low.adapter.node(INC).props.enabled).toBe(true)
	end)

	it("closing the screen releases the numeric field and its buttons", function()
		local w = numberWorld({ stepButtons = true, prefix = "$", min = 0, max = 9, label = "Fee", hint = "Per lap" })
		w.close()
		expect(w.adapter.liveCount()).toBe(0)
		expect(w.core.lastError()).toBeNil()
	end)
end)

describe("NumberInput: the arithmetic recipe", function()
	it("a field handed the recipe commits the answer, and never runs the text", function()
		local w = numberWorld({ draft = "", number = 0, parse = Facet.recipes.arithmetic.parse })
		editAndCommit(w, PLAIN_FIELD, "3 + 5")
		expect(`{w.number:peek()} {w.draft:peek()}`).toBe("8 8")
	end)

	it("four operators, parentheses, both spellings, and no division by zero", function()
		local parse = Facet.recipes.arithmetic.parse
		expect(parse("2*3")).toBe(6)
		expect(parse("10/4")).toBe(2.5)
		expect(parse("(1+2)*3")).toBe(9)
		expect(parse("6 \u{00F7} 2")).toBe(3)
		expect(parse("3 \u{00D7} 4")).toBe(12)
		expect(parse("\u{2212}4")).toBe(-4)
		for _, bad in { "1/0", "2 +", "(1+2", "print('hi')", "1e5", "" } do
			expect(`{bad}: {parse(bad)}`).toBe(`{bad}: nil`)
		end
	end)

	it("it is TOTAL: length and nesting are bounded, so a hostile string answers nil", function()
		local parse = Facet.recipes.arithmetic.parse
		expect(parse(string.rep("(", 5000) .. "1" .. string.rep(")", 5000))).toBeNil()
		expect(parse(string.rep("-", 5000) .. "1")).toBeNil()
		expect(parse(string.rep("1+", 500) .. "1")).toBeNil()
		expect(parse(string.rep("9", 400))).toBeNil()
		expect(parse("(((1 + 2)))")).toBe(3)
		expect(parse("---4")).toBe(-4)
		expect(parse(string.rep("1+", 60) .. "1")).toBe(61)
	end)
end)
