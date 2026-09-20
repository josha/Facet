--!strict
-- `Facet.motion.newTextReveal` — the shape an app repeats whenever text
-- arrives a piece at a time: a codepoint-safe prefix, a placeholder that is
-- never mistaken for the value, and a reduced-motion landing.
local t = require("./lib/testkit")
local Facet = require("../src")
local Compose = Facet.Compose

t.describe("motion.newTextReveal", function()
	t.it("paints the placeholder until the first character, then the value", function()
		local value = Compose.cell("")
		local reveal = Facet.motion.newTextReveal({ value = value, placeholder = "Thinking…" })
		t.expect(reveal.text()).toBe("Thinking…")
		t.expect(reveal.revealed()).toBe(false)
		value:set("Hi")
		t.expect(reveal.text()).toBe("Hi")
		t.expect(reveal.revealed()).toBe(true)
		t.expect(reveal.complete()).toBe(true)
	end)

	t.it("never splits a codepoint as the cursor walks past it", function()
		local value = "héllo ✦"
		local cursor = Compose.cell(0)
		local reveal = Facet.motion.newTextReveal({ value = value, cursor = cursor })
		local seen = {}
		for index = 0, utf8.len(value) :: number do
			cursor:set(index)
			local shown = reveal.text()
			-- every published prefix is valid UTF-8 and exactly `index` characters
			t.expect(utf8.len(shown)).toBe(index)
			table.insert(seen, shown)
		end
		t.expect(seen[2]).toBe("h")
		t.expect(seen[3]).toBe("hé")
		t.expect(seen[#seen]).toBe(value)
		t.expect(reveal.complete()).toBe(true)
	end)

	t.it("holds the prefix when the cursor runs ahead of a value still arriving", function()
		local value = Compose.cell("abc")
		local cursor = Compose.cell(10)
		local reveal = Facet.motion.newTextReveal({ value = value, cursor = cursor })
		t.expect(reveal.text()).toBe("abc")
		t.expect(reveal.complete()).toBe(true)
		value:set("abcdefghijkl")
		t.expect(reveal.text()).toBe("abcdefghij")
		t.expect(reveal.complete()).toBe(false)
	end)

	t.it("lands the whole value under reduced motion", function()
		local policy = Compose.cell("full")
		local reveal = Facet.motion.newTextReveal({
			value = "a long reply",
			cursor = Compose.cell(1),
			placeholder = "Thinking…",
			policy = policy,
		})
		t.expect(reveal.text()).toBe("a")
		policy:set("reduced")
		t.expect(reveal.text()).toBe("a long reply")
		t.expect(reveal.complete()).toBe(true)
	end)

	t.it("reads through a binding's `use`, so a Text rebinds when the value changes", function()
		local app, adapter, settle = require("./lib/native_world")({ x = 0, y = 0, w = 320, h = 240 })
		local content = Compose.cell("")
		local reveal = Facet.motion.newTextReveal({
			value = function(use)
				return use(content)
			end,
			placeholder = "Thinking…",
		})
		app.mount(function()
			return app.controls.Screen("S")({ app.controls.Text("Reply")({ text = reveal.text }) })
		end)
		settle(2)
		t.expect(adapter.node("/S/Reply").props.text).toBe("Thinking…")
		content:set("Here it is")
		settle(2)
		t.expect(adapter.node("/S/Reply").props.text).toBe("Here it is")
		app.dispose()
	end)
end)
