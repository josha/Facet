--!strict
local t = require("./lib/testkit")
local worlds = require("./lib/content_world")
local Compose = require("../src/vendor/compose/core")
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
	end, { motionLevel = "none" })
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
		end, { motionLevel = "none" })
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
		end, { motionLevel = "none" })
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

	t.it(
		"touch long-press on a truncated label shows it until the next tap (the label is not Active, so the engine long-press is hit-tested)",
		function()
			local w = label({ text = LONG, truncate = "end", disclose = true })
			w.input.PreferredInput = w.Enum.PreferredInput.Touch
			local name = w.find("Name")
			name.TextFits = false
			longPress(w, name)
			t.expect(w.find("Disclosure")).toBeNil()
			w.input.TouchLongPress.fire({ Vector2.new(500, 500) }, w.Enum.UserInputState.Begin, false)
			w.advance(0.05)
			t.expect(w.find("Disclosure")).toBeNil()
			w.input.TouchLongPress.fire({ Vector2.new(320, 220) }, w.Enum.UserInputState.Begin, false)
			w.advance(0.05)
			t.expect(w.find("HelpText").Text).toBe(LONG)
			tap(w)
			t.expect(w.find("Disclosure")).toBeNil()
			w.stop()
		end
	)

	t.it("a keyboard or gamepad selection on the row that holds the label discloses it", function()
		local w = overlay.new(function(UI, Host)
			return Host.Frame({
				Name = "Screen",
				UI.Button "Row" {
					label = "",
					UI.Text "Name" { text = LONG, truncate = "end", disclose = true },
				},
			})
		end, { motionLevel = "none" })
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
		end, { motionLevel = "none" })
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

	t.it("a Toggle's truncated label discloses its whole value; without disclose it stays plate-less", function()
		for _, case in { { disclose = true }, { disclose = true, hint = "Shown on the HUD" }, {} } do
			local w = overlay.new(function(UI, Host)
				return Host.Frame({
					Name = "Screen",
					UI.Toggle "Music" {
						label = LONG,
						value = Compose.cell(false),
						disclose = case.disclose,
						hint = case.hint,
					},
				})
			end, { motionLevel = "none" })
			local music = w.find("Music")
			place(music)
			local title = music:FindFirstChild("Title", true)
			music.TextFits = title ~= nil
			if title then
				title.TextFits = false
			end
			w.input.PreferredInput = w.Enum.PreferredInput.Gamepad
			w.gui.SelectedObject = music
			w.advance(0.5)
			local help = w.find("HelpText")
			local where = if case.hint then "hint" elseif case.disclose then "plain" else "undisclosed"
			t.expect(`{where}: {if help then help.Text else "none"}`)
				.toBe(`{where}: {if case.disclose then LONG else "none"}`)
			w.stop()
		end
	end)

	t.it("a disclosing Button or Toggle with an authored width keeps one line that truncates", function()
		local w = overlay.new(function(UI, Host)
			return Host.Frame({
				Name = "Screen",
				UI.Toggle "Music" {
					label = LONG,
					value = Compose.cell(false),
					disclose = true,
					Size = UDim2.fromOffset(200, 44),
				},
				UI.Button "Post" { label = LONG, disclose = true, Size = UDim2.fromOffset(120, 44) },
			})
		end, { motionLevel = "none" })
		for _, name in { "Music", "Post" } do
			local node = w.find(name)
			t.expect(`{name}: {node.TextTruncate.Name} {node.TextWrapped}`).toBe(`{name}: AtEnd false`)
		end
		w.stop()
	end)

	t.it("disclose is a boolean", function()
		t.expect(pcall(function()
			label({ text = LONG, disclose = "yes" }).stop()
		end)).toBe(false)
	end)
end)

t.describe("auto reveal of truncated text (restored from 0.11)", function()
	local function revealing(count: number, reduced: boolean): any
		local w = overlay.new(function(UI, Host)
			local children: { any } = {}
			for index = 1, count do
				table.insert(children, UI.Text("Name" .. index)({ text = LONG, reveal = "auto" }))
			end
			return Host.Frame({ Name = "Screen", table.unpack(children) })
		end, { motionLevel = if reduced then "none" else "normal" })
		for index = 1, count do
			local name = w.find("Name" .. index)
			place(name)
			name.TextFits = false
		end
		return w
	end

	t.it("rests in its ellipsis, slides its whole value left to the tail, holds, and slides back", function()
		local w = revealing(1, false)
		local name = w.find("Name1")
		t.expect(name.TextTruncate).toBe(w.Enum.TextTruncate.AtEnd)
		w.advance(1, 60)
		t.expect(w.find("Reveal")).toBeNil()
		w.advance(0.3, 18)
		local window = w.find("Reveal")
		t.expect(window ~= nil and window.ClipsDescendants).toBe(true)
		t.expect(window.Size.Y.Scale).toBe(0)
		local full = window:FindFirstChild("Full")
		t.expect(full.Text).toBe(LONG)
		t.expect(full.Size.Y.Scale == 1 and full.AutomaticSize == w.Enum.AutomaticSize.X).toBe(true)
		t.expect(name:FindFirstChild("RevealHold") ~= nil).toBe(true)
		window.AbsoluteSize, full.AbsoluteSize = Vector2.new(80, 20), Vector2.new(320, 20)
		w.advance(1, 60)
		t.expect(full.Position.X.Scale < 0).toBe(true)
		w.advance(10.5, 630)
		t.expect(math.abs(full.Position.X.Scale + 242 / 80) < 1e-4).toBe(true)
		w.advance(13, 780)
		t.expect(w.find("Reveal")).toBeNil()
		t.expect(name:FindFirstChild("RevealHold")).toBeNil()
		w.stop()
	end)

	t.it("stays still under reduced motion, when the text fits, and while its disclosure plate shows", function()
		local reduced = revealing(1, true)
		reduced.advance(2, 120)
		t.expect(reduced.find("Reveal")).toBeNil()
		reduced.stop()
		local fits = revealing(1, false)
		fits.find("Name1").TextFits = true
		fits.advance(2, 120)
		t.expect(fits.find("Reveal")).toBeNil()
		fits.stop()
		local plate = revealing(1, false)
		plate.input.PreferredInput = plate.Enum.PreferredInput.KeyboardAndMouse
		plate.find("Name1").GuiState = plate.Enum.GuiState.Hover
		plate.advance(2, 120)
		t.expect(plate.find("HelpText").Text).toBe(LONG)
		t.expect(plate.find("Reveal")).toBeNil()
		plate.stop()
	end)

	t.it("moves one strip at a time", function()
		local w = revealing(2, false)
		w.advance(1.5, 90)
		t.expect(#w.findAll("Reveal")).toBe(1)
		w.stop()
	end)

	t.it("reveal is auto and needs one line", function()
		for _, bad in { { reveal = "yes" }, { reveal = "auto", wrap = true }, { reveal = "auto", truncate = "middle" } } do
			bad.text = LONG
			t.expect(pcall(function()
				overlay
					.new(function(UI, Host)
						return Host.Frame({ UI.Text "Name"(bad) })
					end, { motionLevel = "none" })
					.stop()
			end)).toBe(false)
		end
	end)
end)
