--!strict
local t = require("./lib/testkit")
local worlds = require("./lib/content_world")
local lune = require("@lune/roblox")
local UDim2 = lune.UDim2

local function act(label: string): any
	return { id = string.lower(label), label = label, onSelect = function() end }
end

local function menuNotes(items: { any }): { string }
	local controls: any = {}
	local world = worlds.new(function(UI, Host)
		return Host.Frame({
			Name = "S",
			Size = UDim2.fromOffset(800, 600),
			UI.Menu { label = "Options", items = items, controls = controls },
		})
	end, { reducedMotion = true })
	local notes = controls.diagnostics()
	world.stop()
	return notes
end

t.describe("Menu diagnostics (restored from 0.11)", function()
	t.it("a three-level tree builds, and depth 2 is advice rather than a refusal", function()
		local notes = table.concat(
			menuNotes({
				{
					id = "adjust",
					label = "Adjust",
					children = { { id = "wear", label = "Wear", children = { act("Hat") } } },
				},
			}),
			" | "
		)
		t.expect(string.find(notes, "nests 2 levels deep", 1, true) ~= nil).toBe(true)
		t.expect(string.find(notes, "single level", 1, true) ~= nil).toBe(true)
	end)

	t.it("one level of submenu is silent", function()
		t.expect(#menuNotes({ { id = "adjust", label = "Adjust", children = { act("Head") } } })).toBe(0)
	end)

	t.it("a level of more than about five items is advised to become its own menu", function()
		local many = {}
		for index = 1, 6 do
			table.insert(many, act(`Item {index}`))
		end
		local notes = table.concat(menuNotes(many), " | ")
		t.expect(string.find(notes, "consider a new menu", 1, true) ~= nil).toBe(true)
		t.expect(#menuNotes({ act("A"), act("B"), act("C"), act("D"), act("E") })).toBe(0)
	end)

	t.it("a destructive item that is not last is diagnosed", function()
		local delete = act("Delete")
		delete.role = "destructive"
		local notes = table.concat(menuNotes({ delete, act("Keep") }), " | ")
		t.expect(string.find(notes, "at the end of the menu", 1, true) ~= nil).toBe(true)
		t.expect(#menuNotes({ act("Keep"), delete })).toBe(0)
	end)
end)
