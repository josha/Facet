--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

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
		node.TouchLongPress:Fire({ Vector2.new(320, 220) }, w.Enum.UserInputState.Begin)
		w.advance(0.05)
	end

	local function tap(w: any)
		w.input.InputBegan:Fire({ UserInputType = w.Enum.UserInputType.Touch }, false)
		w.advance(0.3)
	end

	verifyHarness:suite("help reachability: every input class can open every help", function()
		local function helped(): (any, { number })
			local count = { 0 }
			local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
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

		verifyHarness:case("a keyboard selection lands on the button", {
			id = "native_overlay_reach::help reachability: every input class can open every help::a keyboard selection lands on the button",
			run = function()
				local w = helped()
				w.input.PreferredInput = w.Enum.PreferredInput.KeyboardAndMouse
				w.gui.SelectedObject = w.find("Post")
				w.advance(0.5)
				Verify.expect(w.find("HelpText") ~= nil):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("a touch long-press opens it at once, and the next tap closes it", {
			id = "native_overlay_reach::help reachability: every input class can open every help::a touch long-press opens it at once, and the next tap closes it",
			run = function()
				local w, count = helped()
				w.input.PreferredInput = w.Enum.PreferredInput.Touch
				local post = w.find("Post")
				post.GuiState = w.Enum.GuiState.Hover
				w.advance(0.5)
				Verify.expect((w.find("HelpText"))):toBeNil()
				longPress(w, post)
				Verify.expect(w.find("HelpText").Text):toBe("Posts it")
				post.Activated:Fire()
				Verify.expect(count[1]):toBe(0)
				tap(w)
				Verify.expect((w.find("HelpText"))):toBeNil()
				post.InputBegan:Fire({ UserInputType = w.Enum.UserInputType.Touch })
				post.Activated:Fire()
				Verify.expect(count[1]):toBe(1)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("full-value disclosure of truncated text", function()
		local function label(spec: { [any]: any }): any
			local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
				return Host.Frame({ Name = "Screen", UI.Text "Name"(spec) })
			end, { motionLevel = "none" })
			place(w.find("Name"))
			return w
		end

		verifyHarness:case(
			"touch long-press on a truncated label shows it until the next tap (the label is not Active, so the engine long-press is hit-tested)",
			{
				id = "native_overlay_reach::full-value disclosure of truncated text::touch long-press on a truncated label shows it until the next tap (the label is not Active, so the engine long-press is hit-tested)",
				run = function()
					local w = label({ text = LONG, truncate = "end" :: "end", disclose = true })
					w.input.PreferredInput = w.Enum.PreferredInput.Touch
					local name = w.find("Name")
					name.TextFits = false
					longPress(w, name)
					Verify.expect((w.find("Disclosure"))):toBeNil()
					w.input.TouchLongPress:Fire({ Vector2.new(500, 500) }, w.Enum.UserInputState.Begin, false)
					w.advance(0.05)
					Verify.expect((w.find("Disclosure"))):toBeNil()
					w.input.TouchLongPress:Fire({ Vector2.new(320, 220) }, w.Enum.UserInputState.Begin, false)
					w.advance(0.05)
					Verify.expect(w.find("HelpText").Text):toBe(LONG)
					tap(w)
					Verify.expect((w.find("Disclosure"))):toBeNil()
					w.stop()
				end,
			}
		)

		verifyHarness:case("a keyboard or gamepad selection on the row that holds the label discloses it", {
			id = "native_overlay_reach::full-value disclosure of truncated text::a keyboard or gamepad selection on the row that holds the label discloses it",
			run = function()
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						Name = "Screen",
						UI.Button "Row" {
							label = "",
							UI.Text "Name" { text = LONG, truncate = "end" :: "end", disclose = true },
						},
					})
				end, { motionLevel = "none" })
				place(w.find("Name"))
				w.find("Name").TextFits = false
				w.input.PreferredInput = w.Enum.PreferredInput.Gamepad
				w.gui.SelectedObject = w.find("Row")
				w.advance(0.5)
				Verify.expect(w.find("HelpText").Text):toBe(LONG)
				w.stop()
			end,
		})

		verifyHarness:case("a truncated Button label outranks its help on the same engagement", {
			id = "native_overlay_reach::full-value disclosure of truncated text::a truncated Button label outranks its help on the same engagement",
			run = function()
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
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
				Verify.expect(texts):toEqual({ LONG })
				post.TextFits = true
				w.advance(0.5)
				texts = {}
				for _, node in w.findAll("HelpText") do
					table.insert(texts, node.Text)
				end
				Verify.expect(texts):toEqual({ "Posts it" })
				w.stop()
			end,
		})

		verifyHarness:case(
			"a Toggle's truncated label discloses its whole value; without disclose it stays plate-less",
			{
				id = "native_overlay_reach::full-value disclosure of truncated text::a Toggle's truncated label discloses its whole value; without disclose it stays plate-less",
				run = function()
					for _, case: { disclose: boolean?, hint: string? } in
						{ { disclose = true }, { disclose = true, hint = "Shown on the HUD" }, {} } :: { { disclose: boolean?, hint: string? } }
					do
						local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
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
						Verify.expect(`{where}: {if help then help.Text else "none"}`)
							:toBe(`{where}: {if case.disclose then LONG else "none"}`)
						w.stop()
					end
				end,
			}
		)
	end)

	verifyHarness:suite("auto reveal of truncated text (restored from 0.11)", function()
		local function revealing(count: number, reduced: boolean): any
			local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
				local children: { any } = {}
				for index = 1, count do
					table.insert(children, UI.Text("Name" .. index)({ text = LONG, reveal = "auto" :: "auto" }))
				end
				return Host.Frame({ Name = "Screen", table.unpack((children :: unknown) :: { unknown }) })
			end, { motionLevel = if reduced then "none" else "normal" })
			for index = 1, count do
				local name = w.find("Name" .. index)
				place(name)
				name.TextFits = false
			end
			return w
		end

		verifyHarness:case("rests in its ellipsis, slides its whole value left to the tail, holds, and slides back", {
			id = "native_overlay_reach::auto reveal of truncated text (restored from 0.11)::rests in its ellipsis, slides its whole value left to the tail, holds, and slides back",
			run = function()
				local w = revealing(1, false)
				local name = w.find("Name1")
				Verify.expect(name.TextTruncate):toBe(w.Enum.TextTruncate.AtEnd)
				w.advance(1, 60)
				Verify.expect((w.find("Reveal"))):toBeNil()
				w.advance(0.3, 18)
				local window = w.find("Reveal")
				Verify.expect(window ~= nil and window.ClipsDescendants):toBe(true)
				Verify.expect(window.Size.Y.Scale):toBe(0)
				local full = window:FindFirstChild("Full")
				Verify.expect(full.Text):toBe(LONG)
				Verify.expect(full.Size.Y.Scale == 1 and full.AutomaticSize == w.Enum.AutomaticSize.X):toBe(true)
				Verify.expect(name:FindFirstChild("RevealHold") ~= nil):toBe(true)
				window.AbsoluteSize, full.AbsoluteSize = Vector2.new(80, 20), Vector2.new(320, 20)
				w.advance(1, 60)
				Verify.expect(full.Position.X.Scale < 0):toBe(true)
				w.advance(10.5, 630)
				Verify.expect(math.abs(full.Position.X.Scale + 242 / 80) < 1e-4):toBe(true)
				w.advance(13, 780)
				Verify.expect((w.find("Reveal"))):toBeNil()
				Verify.expect((name:FindFirstChild("RevealHold"))):toBeNil()
				w.stop()
			end,
		})

		verifyHarness:case(
			"stays still under reduced motion, when the text fits, and while its disclosure plate shows",
			{
				id = "native_overlay_reach::auto reveal of truncated text (restored from 0.11)::stays still under reduced motion, when the text fits, and while its disclosure plate shows",
				run = function()
					local reduced = revealing(1, true)
					reduced.advance(2, 120)
					Verify.expect((reduced.find("Reveal"))):toBeNil()
					reduced.stop()
					local fits = revealing(1, false)
					fits.find("Name1").TextFits = true
					fits.advance(2, 120)
					Verify.expect((fits.find("Reveal"))):toBeNil()
					fits.stop()
					local plate = revealing(1, false)
					plate.input.PreferredInput = plate.Enum.PreferredInput.KeyboardAndMouse
					plate.find("Name1").GuiState = plate.Enum.GuiState.Hover
					plate.advance(2, 120)
					Verify.expect(plate.find("HelpText").Text):toBe(LONG)
					Verify.expect((plate.find("Reveal"))):toBeNil()
					plate.stop()
				end,
			}
		)
	end)
end
