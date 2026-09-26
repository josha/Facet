--!strict
local t = require("./lib/testkit")
local worlds = require("./lib/content_world")
local overlay = require("./lib/overlay_world")
local lune = require("@lune/roblox")
local UDim2, Vector2 = lune.UDim2, lune.Vector2

local LONG = "Coastal circuit, reverse layout, lap fourteen"

local function place(node: any)
	node.AbsolutePosition = Vector2.new(300, 200)
	node.AbsoluteSize = Vector2.new(80, 44)
end

local function longPress(w: any, node: any)
	node.TouchLongPress.fire({ Vector2.new(320, 220) }, w.Enum.UserInputState.Begin)
	w.advance(0.05)
end

local function tap(w: any)
	w.input.InputBegan.fire({ UserInputType = w.Enum.UserInputType.Touch }, false)
	w.advance(0.3)
end

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

t.describe("help reachability: every input class can open every help", function()
	local function helped(): (any, { number })
		local count = { 0 }
		local w = overlay.new(function(UI, Host)
			return Host.Frame({
				Name = "Screen",
				UI.Button "Post" {
					label = "Post",
					help = "Posts it",
					onActivate = function()
						count[1] += 1
					end,
				},
			})
		end, { reducedMotion = true })
		place(w.find("Post"))
		return w, count
	end

	t.it("a pointer rests on the button", function()
		local w = helped()
		w.input.PreferredInput = w.Enum.PreferredInput.KeyboardAndMouse
		w.find("Post").GuiState = w.Enum.GuiState.Hover
		w.advance(0.5)
		t.expect(w.find("HelpText").Text).toBe("Posts it")
		w.stop()
	end)

	t.it("a keyboard selection lands on the button", function()
		local w = helped()
		w.input.PreferredInput = w.Enum.PreferredInput.KeyboardAndMouse
		w.gui.SelectedObject = w.find("Post")
		w.advance(0.5)
		t.expect(w.find("HelpText") ~= nil).toBe(true)
		w.stop()
	end)

	t.it("a touch long-press opens it at once, and the next tap closes it", function()
		local w, count = helped()
		w.input.PreferredInput = w.Enum.PreferredInput.Touch
		local post = w.find("Post")
		post.GuiState = w.Enum.GuiState.Hover
		w.advance(0.5)
		t.expect(w.find("HelpText")).toBeNil()
		longPress(w, post)
		t.expect(w.find("HelpText").Text).toBe("Posts it")
		post.Activated.fire()
		t.expect(count[1]).toBe(0)
		tap(w)
		t.expect(w.find("HelpText")).toBeNil()
		post.InputBegan.fire({ UserInputType = w.Enum.UserInputType.Touch })
		post.Activated.fire()
		t.expect(count[1]).toBe(1)
		w.stop()
	end)
end)

t.describe("full-value disclosure of truncated text", function()
	local function label(spec: { [string]: any }): any
		local w = overlay.new(function(UI, Host)
			return Host.Frame({ Name = "Screen", UI.Text "Name"(spec) })
		end, { reducedMotion = true })
		place(w.find("Name"))
		return w
	end

	t.it("a pointer resting on a truncated label reads the whole value", function()
		local w = label({ text = LONG, truncate = "end", disclose = true })
		local name = w.find("Name")
		name.TextFits = false
		name.GuiState = w.Enum.GuiState.Hover
		w.advance(0.5)
		t.expect(w.find("Disclosure") ~= nil).toBe(true)
		t.expect(w.find("HelpText").Text).toBe(LONG)
		name.TextFits = true
		w.advance(0.3)
		t.expect(w.find("Disclosure")).toBeNil()
		w.stop()
	end)

	t.it("a label that fits discloses nothing", function()
		local w = label({ text = "Short", truncate = "end", disclose = true })
		local name = w.find("Name")
		name.TextFits = true
		name.GuiState = w.Enum.GuiState.Hover
		w.advance(0.5)
		t.expect(w.find("Disclosure")).toBeNil()
		w.stop()
	end)

	t.it("touch long-press on a truncated label shows it until the next tap", function()
		local w = label({ text = LONG, truncate = "end", disclose = true })
		w.input.PreferredInput = w.Enum.PreferredInput.Touch
		local name = w.find("Name")
		name.TextFits = false
		longPress(w, name)
		t.expect(w.find("HelpText").Text).toBe(LONG)
		tap(w)
		t.expect(w.find("Disclosure")).toBeNil()
		w.stop()
	end)

	t.it("a keyboard or gamepad selection on the row that holds the label discloses it", function()
		local w = overlay.new(function(UI, Host)
			return Host.Frame({
				Name = "Screen",
				UI.Button "Row" {
					label = "",
					UI.Text "Name" { text = LONG, truncate = "end", disclose = true },
				},
			})
		end, { reducedMotion = true })
		place(w.find("Name"))
		w.find("Name").TextFits = false
		w.input.PreferredInput = w.Enum.PreferredInput.Gamepad
		w.gui.SelectedObject = w.find("Row")
		w.advance(0.5)
		t.expect(w.find("HelpText").Text).toBe(LONG)
		w.stop()
	end)

	t.it("a truncated Button label outranks its help on the same engagement", function()
		local w = overlay.new(function(UI, Host)
			return Host.Frame({
				Name = "Screen",
				UI.Button "Post" { label = LONG, disclose = true, help = "Posts it" },
			})
		end, { reducedMotion = true })
		local post = w.find("Post")
		place(post)
		post.TextFits = false
		w.gui.SelectedObject = post
		w.advance(0.5)
		local texts = {}
		for _, node in w.findAll("HelpText") do
			table.insert(texts, node.Text)
		end
		t.expect(texts).toEqual({ LONG })
		post.TextFits = true
		w.advance(0.5)
		texts = {}
		for _, node in w.findAll("HelpText") do
			table.insert(texts, node.Text)
		end
		t.expect(texts).toEqual({ "Posts it" })
		w.stop()
	end)

	t.it("a middle cut discloses the whole value", function()
		local w = label({ text = LONG, truncate = "middle", disclose = true })
		local name = w.find("Name")
		name.Text = "Coastal…fourteen"
		name.GuiState = w.Enum.GuiState.Hover
		w.advance(0.5)
		t.expect(w.find("HelpText").Text).toBe(LONG)
		w.stop()
	end)

	t.it("disclose is a boolean", function()
		t.expect(pcall(function()
			label({ text = LONG, disclose = "yes" }).stop()
		end)).toBe(false)
	end)
end)
