--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type ButtonGuideProps = typeof(require("@repo/tools/typecheck/aliases").ButtonGuideProps)
	type ButtonGuideEntry = typeof(require("@repo/tools/typecheck/aliases").ButtonGuideEntry)

	local Compose = require("../src/vendor/compose/core")
	local overlay = require("./lib/overlay_world")
	local engines = require("./lib/native_engine")
	local VerifyRoblox = require("../tools/vendor/verify/src/roblox")
	type Engine = engines.Engine

	local function selectables(root: Instance): { string }
		local found: { string } = {}
		for _, node in { root, table.unpack(root:GetDescendants()) } do
			if node:IsA("GuiObject") and (node :: GuiObject).Selectable then
				table.insert(found, node:GetFullName())
			end
		end
		return found
	end

	local guideWorld = overlay.new

	local function labels(guide: Instance): string
		local shown: { { order: number, text: string } } = {}
		for _, node in guide:GetDescendants() do
			local entry = node :: GuiObject
			if node.Name == "Entry" and entry.Visible then
				table.insert(shown, { order = entry.LayoutOrder, text = overlay.find(node, "Label").Text })
			end
		end
		table.sort(shown, function(a, b)
			return a.order < b.order
		end)
		local words: { string } = {}
		for _, entry in shown do
			table.insert(words, entry.text)
		end
		return table.concat(words, " ")
	end

	local function boundAction(engine: Engine, name: string, key: string): InputAction
		local action: InputAction, binding: InputBinding = engine.new("InputAction"), engine.new("InputBinding")
		action.Name = name
		binding.KeyCode = ((engine.types.Enum.KeyCode :: unknown) :: { [string]: Enum.KeyCode })[key]
		engine.environment.poke((action :: unknown) :: VerifyRoblox.Instance, "PreferredBinding", binding)
		return action
	end

	verifyHarness:suite("native ButtonGuide", function()
		verifyHarness:case("shows for its input class, gamepad by default, and never on touch", {
			id = "native_button_guide::input-class",
			run = function()
				local w = guideWorld(function(UI: FacetControls)
					return UI.ButtonGuide "Guide" {
						entries = { { keys = { { "E" } }, label = "Buy" }, { keys = { { "Q" } }, label = "Back" } },
					}
				end)
				local guide = w.find("Guide")
				local P = w.Enum.PreferredInput
				w.input.PreferredInput = P.Gamepad
				Verify.expect(guide.Visible):toBe(true)
				Verify.expect(labels(guide)):toBe("Buy Back")
				Verify.expect(overlay.find(guide, "Keys"):HasTag("facet-shortcut-hint-bare")):toBe(true)
				w.input.PreferredInput = P.KeyboardAndMouse
				Verify.expect(guide.Visible):toBe(false)
				w.input.PreferredInput = P.Touch
				Verify.expect(guide.Visible):toBe(false)
				w.stop()

				local both = guideWorld(function(UI: FacetControls)
					return UI.ButtonGuide "Guide" {
						inputs = { "Gamepad", "KeyboardAndMouse" },
						entries = { { keys = { { "E" } }, label = "Buy" } },
					}
				end)
				local shown = both.find("Guide")
				both.input.PreferredInput = P.KeyboardAndMouse
				Verify.expect(shown.Visible):toBe(true)
				Verify.expect(overlay.find(shown, "Keys"):HasTag("facet-shortcut-hint-bare")):toBe(false)
				both.input.PreferredInput = P.Touch
				Verify.expect(shown.Visible):toBe(false)
				both.input.PreferredInput = P.Gamepad
				Verify.expect(shown.Visible):toBe(true)
				Verify.expect(overlay.find(shown, "Keys"):HasTag("facet-shortcut-hint-bare")):toBe(true)
				both.stop()
			end,
		})

		verifyHarness:case("mouse movement within keyboard and mouse never makes the guide flash", {
			id = "native_button_guide::no-flash",
			run = function()
				local w = guideWorld(function(UI: FacetControls)
					return UI.ButtonGuide "Guide" {
						inputs = { "KeyboardAndMouse" },
						entries = { { keys = { { "E" } }, label = "Buy" } },
					}
				end)
				local P = w.Enum.PreferredInput
				w.input.PreferredInput = P.KeyboardAndMouse
				local guide = w.find("Guide")
				local entry = overlay.find(guide, "Entry")
				Verify.expect(guide.Visible):toBe(true)
				local changes = 0
				guide:GetPropertyChangedSignal("Visible"):Connect(function()
					changes += 1
				end)
				for _ = 1, 3 do
					w.input.InputChanged:Fire({ UserInputType = w.Enum.UserInputType.MouseMovement }, false)
					w.input.InputBegan:Fire({
						UserInputType = w.Enum.UserInputType.Keyboard,
						KeyCode = w.Enum.KeyCode.W,
					}, false)
					w.input.PreferredInput = P.KeyboardAndMouse
					w.advance(1 / 60)
				end
				Verify.expect(changes):toBe(0)
				Verify.expect(guide.Visible):toBe(true)
				Verify.expect(overlay.find(guide, "Entry")):toBe(entry)
				w.stop()
			end,
		})

		verifyHarness:case("refuses Touch and malformed entries", {
			id = "native_button_guide::refusals",
			run = function()
				local function build(spec: unknown): () -> ()
					return function()
						local w = guideWorld(function(UI: FacetControls)
							return UI.ButtonGuide(spec :: ButtonGuideProps)
						end)
						w.stop()
					end
				end
				local entries = { { keys = { { "E" } }, label = "Buy" } }
				Verify.expect(build({ inputs = { "Touch" }, entries = entries })):toThrow("never shows on touch")
				Verify.expect(build({ inputs = { "Gamepad", "Touch" }, entries = entries }))
					:toThrow("never shows on touch")
				Verify.expect(build({ inputs = { "Mouse" }, entries = entries })):toThrow("inputs takes")
				Verify.expect(build({ inputs = {}, entries = entries })):toThrow("nonempty")
				Verify.expect(build({})):toThrow("entries is required")
				Verify.expect(build({ entries = { { label = "Buy" } } })):toThrow("action or keys")
				Verify.expect(build({ entries = { { keys = { { "E" } } } } })):toThrow("needs a label")
				Verify.expect(build({ entries = { { action = {}, label = "Buy" } } })):toThrow("native InputAction")
				Verify.expect(build({ entries = entries, label = "Buy" })):toThrow("unknown option 'label'")
			end,
		})

		verifyHarness:case("the buttonGuides app option hides every guide", {
			id = "native_button_guide::player-setting",
			run = function()
				local setting = Compose.cell(true)
				local w = guideWorld(function(UI: FacetControls)
					return UI.ButtonGuide "Guide" {
						entries = { { keys = { { "E" } }, label = "Buy" } },
					}
				end, { buttonGuides = setting })
				w.input.PreferredInput = w.Enum.PreferredInput.Gamepad
				local guide = w.find("Guide")
				Verify.expect(guide.Visible):toBe(true)
				setting:set(false)
				Verify.expect(guide.Visible):toBe(false)
				setting:set(true)
				Verify.expect(guide.Visible):toBe(true)
				w.stop()

				local off = guideWorld(function(UI: FacetControls)
					return UI.ButtonGuide "Guide" {
						entries = { { keys = { { "E" } }, label = "Buy" } },
					}
				end, { buttonGuides = false })
				off.input.PreferredInput = off.Enum.PreferredInput.Gamepad
				Verify.expect(off.find("Guide").Visible):toBe(false)
				off.stop()
			end,
		})

		verifyHarness:case("lists only enabled actions, follows the entries and hides when none is live", {
			id = "native_button_guide::live-entries",
			run = function()
				local buy: InputAction, back: InputAction
				local entries = Compose.cell({} :: { ButtonGuideEntry })
				local label = Compose.cell("Buy")
				local w = guideWorld(function(UI: FacetControls, _, engine: Engine)
					buy, back = boundAction(engine, "Buy", "ButtonA"), boundAction(engine, "Back", "ButtonB")
					entries:set({
						{ action = buy, label = label },
						{ action = back, label = "Back" },
						{ keys = { { "LB", "RB" } }, label = "Tabs" },
					})
					return UI.ButtonGuide "Guide" { entries = entries }
				end)
				w.input.PreferredInput = w.Enum.PreferredInput.Gamepad
				local guide = w.find("Guide")
				Verify.expect(labels(guide)):toBe("Buy Back Tabs")
				buy.Enabled = false
				Verify.expect(labels(guide)):toBe("Back Tabs")
				Verify.expect(guide.Visible):toBe(true)
				buy.Enabled = true
				label:set("Sell")
				Verify.expect(labels(guide)):toBe("Sell Back Tabs")
				entries:set({ { action = back, label = "Back" }, { action = buy, label = label } })
				Verify.expect(labels(guide)):toBe("Back Sell")
				buy.Enabled, back.Enabled = false, false
				Verify.expect(guide.Visible):toBe(false)
				back.Enabled = true
				Verify.expect(guide.Visible):toBe(true)
				entries:set({})
				Verify.expect(guide.Visible):toBe(false)
				w.stop()
			end,
		})

		verifyHarness:case("an alert above the guide hides it; a guide inside the open surface stays", {
			id = "native_button_guide::modal-above",
			run = function()
				local alert = Compose.cell(false)
				local w = guideWorld(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame "Scene" {
						UI.ButtonGuide "HudGuide" { entries = { { keys = { { "Y" } }, label = "Map" } } } :: unknown,
						UI.Alert {
							isPresented = alert,
							title = "Leave the race?",
							actions = { { id = "Stay", label = "Stay", role = "cancel" :: "cancel" } },
						},
					}
				end, { motionLevel = "none" })
				w.input.PreferredInput = w.Enum.PreferredInput.Gamepad
				local guide = w.find("HudGuide")
				Verify.expect(guide.Visible):toBe(true)
				alert:set(true)
				w.advance(1 / 60, 3)
				Verify.expect(guide.Visible):toBe(false)
				alert:set(false)
				w.advance(1, 10)
				Verify.expect(guide.Visible):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("nothing in a guide is selectable or active", {
			id = "native_button_guide::readout",
			run = function()
				local w = guideWorld(function(UI: FacetControls, _, engine: Engine)
					return UI.ButtonGuide "Guide" {
						inputs = { "Gamepad", "KeyboardAndMouse" },
						Selectable = true,
						entries = {
							{ action = boundAction(engine, "Buy", "ButtonA"), label = "Buy" },
							{ keys = { { "Esc" } }, label = "Back" },
						},
					}
				end)
				for _, input in { "Gamepad", "KeyboardAndMouse" } do
					w.input.PreferredInput = w.Enum.PreferredInput[input]
					local guide = w.find("Guide")
					Verify.expect(guide.Visible):toBe(true)
					Verify.expect(guide.Active):toBe(false)
					Verify.expect(table.concat(selectables(guide), ", ")):toBe("")
				end
				w.stop()
			end,
		})

		verifyHarness:case("a Sheet guide sits on the bottom edge outside the scroller and is never a stop", {
			id = "native_button_guide::sheet-slot",
			run = function()
				local shown = Compose.cell(false)
				local buy: InputAction
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost, engine: Engine)
					buy = boundAction(engine, "Buy", "ButtonA")
					return UI.Sheet "Shop" {
						isPresented = shown,
						placement = "center",
						closeButton = true,
						title = "Shop",
						content = function(): Instance
							return Host.Frame "Shelf" {
								UI.Button "Blade" { label = "Blade" } :: unknown,
								UI.Button "Wheels" { label = "Wheels" },
							}
						end,
						actions = { { id = "Done", label = "Done", onActivate = function() end } },
						guide = {
							entries = { { action = buy, label = "Buy" }, { keys = { { "LB" } }, label = "Tabs" } },
						},
					}
				end, { motionLevel = "none" })
				w.input.PreferredInput = w.Enum.PreferredInput.Gamepad
				shown:set(true)
				w.advance(1 / 60, 3)
				local guide, room, body = w.find("ButtonGuide"), w.find("Room"), w.find("SheetContent")
				local region = guide.Parent
				Verify.expect(region.Name):toBe("Guide")
				Verify.expect(region.Parent):toBe(room)
				Verify.expect((guide:IsDescendantOf(body))):toBe(false)
				Verify.expect(region.LayoutOrder > w.find("Actions").LayoutOrder):toBe(true)
				Verify.expect(region.Visible):toBe(true)
				Verify.expect(guide.Visible):toBe(true)
				Verify.expect(table.concat(selectables(region), ", ")):toBe("")
				Verify.expect(if w.gui.SelectedObject then w.gui.SelectedObject.Name else "nil"):toBe("Blade")
				for _, key in { "DPadDown", "DPadDown", "DPadDown", "DPadUp", "DPadRight" } do
					w.input.InputBegan:Fire({ KeyCode = w.Enum.KeyCode[key] })
					w.advance(1 / 10, 3)
					local selected = w.gui.SelectedObject
					Verify.expect(selected == nil or not selected:IsDescendantOf(region)):toBe(true)
				end
				w.input.PreferredInput = w.Enum.PreferredInput.KeyboardAndMouse
				Verify.expect(region.Visible):toBe(false)
				w.input.PreferredInput = w.Enum.PreferredInput.Gamepad
				Verify.expect(region.Visible):toBe(true)
				buy.Enabled = false
				Verify.expect(labels(guide)):toBe("Tabs")
				w.stop()
			end,
		})

		verifyHarness:case("a hidden Sheet guide gives its pinned room back to the body", {
			id = "native_button_guide::sheet-room",
			run = function()
				local shown = Compose.cell(true)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Sheet "Shop" {
						isPresented = shown,
						detent = "medium",
						title = "Shop",
						content = function(): Instance
							return Host.TextLabel "Copy" { Text = "Pick a part." }
						end,
						guide = { entries = { { keys = { { "LB" } }, label = "Tabs" } } },
					}
				end, { motionLevel = "none" })
				w.engine.environment.poke(w.find("Modal"), "AbsoluteSize", w.Vector2.new(800, 600))
				w.input.PreferredInput = w.Enum.PreferredInput.Gamepad
				w.advance(1 / 300, 2)
				local region, body = w.find("Guide"), w.find("SheetContent")
				w.size(w.find("Header"), 500, 44)
				w.size(region, 500, 40)
				w.advance(1 / 60)
				local withGuide = body.Size.Y.Offset
				w.input.PreferredInput = w.Enum.PreferredInput.KeyboardAndMouse
				w.advance(1 / 60)
				Verify.expect(region.Visible):toBe(false)
				Verify.expect(body.Size.Y.Offset):toBe(withGuide + 40 + 8)
				w.stop()
			end,
		})
	end)
end
