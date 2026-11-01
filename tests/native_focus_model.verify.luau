--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Bdd = require("../tools/vendor/verify/src/bdd")

return function(verifyHarness: Verify.Harness)
	local test = Bdd.create(verifyHarness)
	local describe, it, expect = test.describe, test.it, test.expect
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

	local Facet = require("../src")
	local EnvironmentTypes = require("../src/ui/environment_types")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose

	local function setup(build: (Facet.Controls, RobloxHost) -> Facet.Child, options: Facet.ControlOptions?)
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local input = engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		input.IsKeyDown = function()
			return false
		end
		engine.environment.poke(input, "KeyboardEnabled", true)
		local parent = engine.new("Folder")
		local config: { [string]: any } = {
			types = engine.types,
			guiService = gui,
			inputParent = parent,
			services = { GuiService = gui, UserInputService = input },
		}
		for key, value in (options or {} :: { [string]: any }) do
			config[key] = value
		end
		local UI = Facet.controls(runtime, config)
		local Host = Facet.host(runtime)
		local stop, screen: any = runtime.mount(function()
			return Host.ScreenGui { build(UI, Host) }
		end, parent)
		local world = { engine = engine, runtime = runtime, gui = gui, input = input, screen = screen, parent = parent }
		function world.find(name: string, root: any?): any
			local at = root or screen
			if at.Name == name then
				return at
			end
			for _, child in at:GetChildren() do
				local found = world.find(name, child)
				if found then
					return found
				end
			end
			return nil
		end
		function world.tab()
			world.find("Traverse", parent).Pressed:Fire()
		end
		function world.selected(): string
			return if gui.SelectedObject then gui.SelectedObject.Name else "nil"
		end
		function world.activateKeys(): { string }
			local keys = {}
			local context = world.find("FacetActivate", parent)
			if context and context.Enabled then
				for _, binding in context:FindFirstChild("Activate"):GetChildren() do
					table.insert(keys, binding.KeyCode.Name)
				end
			end
			table.sort(keys)
			return keys
		end
		function world.stop()
			stop()
			runtime:dispose()
		end
		return world
	end

	describe("Tab traversal priority and the keyboard opt-in", function()
		it("only the runtime that owns selection handles a shared native Tab binding", {
			id = "native_focus_model::Tab traversal priority and the keyboard opt-in::only the runtime that owns selection handles a shared native Tab binding",
			run = function()
				local w = setup(function(UI)
					return UI.Screen "First" {
						UI.Button "OldA" { label = "Old A" },
						UI.Button "OldB" { label = "Old B" },
					}
				end)
				local first = w.find("FacetTraversal", w.parent)
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(w.engine)
				local UI = Facet.controls(runtime, {
					types = w.engine.types,
					guiService = w.gui,
					inputParent = w.parent,
					services = { GuiService = w.gui, UserInputService = w.input },
				})
				local Host = Facet.host(runtime)
				local stop, screen: any = runtime.mount(function()
					return Host.ScreenGui {
						UI.Button "A" { label = "A" },
						UI.Button "B" { label = "B" },
						UI.Button "C" { label = "C" },
					}
				end, w.parent)
				local contexts = {}
				for _, node in w.parent:GetChildren() do
					if node.Name == "FacetTraversal" then
						table.insert(contexts, node)
					end
				end
				expect(contexts):toHaveLength(2)
				w.gui.SelectedObject = w.find("A", screen)
				expect(first.Enabled):toBe(false)
				for _, context in contexts do
					if context.Enabled then
						context.Traverse.Pressed:Fire()
					end
				end
				expect(w.selected()):toBe("B")
				w.gui.SelectedObject = w.find("OldA")
				expect(first.Enabled):toBe(true)
				for _, context in contexts do
					if context.Enabled then
						context.Traverse.Pressed:Fire()
					end
				end
				expect(w.selected()):toBe("OldB")
				stop()
				runtime:dispose()
				w.stop()
			end,
		})
		it("keeps native buttons inside an explicit responder in its Tab scope", {
			id = "native_focus_model::Tab traversal priority and the keyboard opt-in::keeps native buttons inside an explicit responder in its Tab scope",
			run = function()
				local w = setup(function(UI, Host)
					local panel = Host.Frame "NativeResponder" {
						Host.TextButton "NativeA" { Text = "A", Selectable = true },
						Host.TextButton "NativeB" { Text = "B", Selectable = true },
					}
					UI.responder(panel, { passive = false })
					return Host.Frame {
						panel,
						UI.Button "Outside" { label = "Outside" },
					}
				end)
				w.gui.SelectedObject = w.find("NativeA")
				expect(w.find("FacetTraversal", w.parent).Enabled):toBe(true)
				w.tab()
				expect(w.selected()):toBe("NativeB")
				w.stop()
			end,
		})

		it("walks Tab by SelectionOrder tier, then document order within a tier", {
			id = "native_focus_model::Tab traversal priority and the keyboard opt-in::walks Tab by SelectionOrder tier, then document order within a tier",
			run = function()
				local w = setup(function(UI)
					return UI.Screen "Page" {
						UI.Button "A" { label = "A" },
						UI.Button "Late" { label = "Late", SelectionOrder = 5 },
						UI.Button "B" { label = "B" },
						UI.Button "First" { label = "First", SelectionOrder = -1 },
					}
				end)
				local names = {}
				for _ = 1, 4 do
					w.tab()
					table.insert(names, w.selected())
				end
				expect(names):toEqual({ "First", "A", "B", "Late" })
				w.tab()
				expect((w.selected())):toBe("First")
				w.stop()
			end,
		})
		it("binds Tab only while a keyboard is live and keyboardNavigation is not false", {
			id = "native_focus_model::Tab traversal priority and the keyboard opt-in::binds Tab only while a keyboard is live and keyboardNavigation is not false",
			run = function()
				local w = setup(function(UI)
					return UI.Button "A" { label = "A" }
				end)
				local context = w.find("FacetTraversal", w.parent)
				expect(context.Enabled):toBe(true)
				w.engine.environment.poke(w.input, "KeyboardEnabled", false)
				expect(context.Enabled):toBe(false)
				w.engine.environment.poke(w.input, "KeyboardEnabled", true)
				expect(context.Enabled):toBe(true)
				w.stop()
				local off = setup(function(UI)
					return UI.Button "A" { label = "A" }
				end, { keyboardNavigation = false })
				expect(off.find("FacetTraversal", off.parent).Enabled):toBe(false)
				off.stop()
			end,
		})
	end)

	describe("stick entry", function()
		it("a left-stick push enters the selection like a D-pad press; a drift does not", {
			id = "native_focus_model::stick entry::a left-stick push enters the selection like a D-pad press; a drift does not",
			run = function()
				local w = setup(function(UI)
					return UI.Screen "Page" {
						UI.Button "A" { label = "A" },
						UI.Button "B" { label = "B" },
					}
				end)
				local V2 = w.engine.types.Vector2
				local context = w.find("FacetEntry", w.parent)
				expect(context.Sink):toBe(false)
				local enter = context:FindFirstChild("Enter")
				enter.StateChanged:Fire(V2.new(0.2, -0.1))
				expect((w.selected())):toBe("nil")
				enter.StateChanged:Fire(V2.new(0, -1))
				expect((w.selected())):toBe("A")
				w.stop()
			end,
		})
	end)

	describe("leaving the gamepad", function()
		it("drops a pad selection when the preferred input leaves the gamepad, so the engine cannot eat typed WASD", {
			id = "native_focus_model::leaving the gamepad::drops a pad selection when the preferred input leaves the gamepad, so the engine cannot eat typed WASD",
			run = function()
				local w = setup(function(UI)
					return UI.Screen "Page" {
						UI.Button "Q" { label = "Q" },
						UI.Button "W" { label = "W" },
					}
				end)
				local E = w.engine.types.Enum
				local last = E.UserInputType.Gamepad1
				w.input.GetLastInputType = function()
					return last
				end
				w.engine.environment.poke(w.input, "PreferredInput", E.PreferredInput.Gamepad)
				w.find("FacetEntry", w.parent)
					:FindFirstChild("Enter").StateChanged
					:Fire(w.engine.types.Vector2.new(0, -1))
				expect((w.selected())):toBe("Q")
				w.engine.environment.poke(w.input, "PreferredInput", E.PreferredInput.KeyboardAndMouse)
				expect((w.selected())):toBe("nil")
				last = E.UserInputType.Keyboard
				w.tab()
				expect((w.selected())):toBe("Q")
				w.engine.environment.poke(w.input, "PreferredInput", E.PreferredInput.Gamepad)
				w.engine.environment.poke(w.input, "PreferredInput", E.PreferredInput.KeyboardAndMouse)
				expect((w.selected())):toBe("Q")
				w.stop()
			end,
		})

		it("keeps a first Tab that lands before the preferred input leaves the gamepad", {
			id = "native_focus_model::leaving the gamepad::keeps a first Tab that lands before the preferred input leaves the gamepad",
			run = function()
				local w = setup(function(UI)
					return UI.Screen "Page" {
						UI.Button "Q" { label = "Q" },
						UI.Button "W" { label = "W" },
					}
				end)
				local E = w.engine.types.Enum
				w.input.GetLastInputType = function()
					return E.UserInputType.Keyboard
				end
				w.engine.environment.poke(w.input, "PreferredInput", E.PreferredInput.Gamepad)
				w.tab()
				expect((w.selected())):toBe("Q")
				w.engine.environment.poke(w.input, "PreferredInput", E.PreferredInput.KeyboardAndMouse)
				expect((w.selected())):toBe("Q")
				w.stop()
			end,
		})

		it("leaves a game's own pad selection outside Facet alone", {
			id = "native_focus_model::leaving the gamepad::leaves a game's own pad selection outside Facet alone",
			run = function()
				local own: any
				local w = setup(function(UI, Host)
					own = Host.TextButton { Name = "GameMenu", Selectable = true }
					return Host.Frame {
						Name = "Legacy",
						own,
						UI.Screen "Page" { UI.Button "Q" { label = "Q" } },
					}
				end)
				local E = w.engine.types.Enum
				w.input.GetLastInputType = function()
					return E.UserInputType.Gamepad1
				end
				w.engine.environment.poke(w.input, "PreferredInput", E.PreferredInput.Gamepad)
				w.gui.SelectedObject = own
				w.engine.environment.poke(w.input, "PreferredInput", E.PreferredInput.KeyboardAndMouse)
				expect((w.selected())):toBe("GameMenu")
				w.stop()
			end,
		})
	end)

	describe("focusSection entry rules", function()
		local function sections(options: EnvironmentTypes.FocusSectionOptions?)
			local w = setup(function(UI, Host)
				local shelf = UI.HStack "Shelf" {
					UI.Button "One" { label = "One" },
					UI.Button "Two" { label = "Two" },
					UI.Button "Three" { label = "Three" },
				}
				UI.focusSection(shelf, options)
				return Host.Frame "Page" {
					UI.Button "Outside" { label = "Outside" },
					shelf,
				}
			end)
			return w
		end
		it("restores the remembered item, and a preferred item wins the first entry", {
			id = "native_focus_model::focusSection entry rules::restores the remembered item, and a preferred item wins the first entry",
			run = function()
				local w = sections({ preferred = "Two" })
				w.gui.SelectedObject = w.find("Outside")
				w.gui.SelectedObject = w.find("Three")
				expect((w.selected())):toBe("Two")
				w.gui.SelectedObject = w.find("One")
				w.gui.SelectedObject = w.find("Outside")
				w.gui.SelectedObject = w.find("Three")
				expect((w.selected())):toBe("One")
				w.stop()
			end,
		})
		it("entry first lands on the first item every time; nearest leaves the engine's choice", {
			id = "native_focus_model::focusSection entry rules::entry first lands on the first item every time; nearest leaves the engine's choice",
			run = function()
				local first = sections({ entry = "first" })
				first.gui.SelectedObject = first.find("Outside")
				first.gui.SelectedObject = first.find("Three")
				expect((first.selected())):toBe("One")
				first.gui.SelectedObject = first.find("Two")
				first.gui.SelectedObject = first.find("Outside")
				first.gui.SelectedObject = first.find("Three")
				expect((first.selected())):toBe("One")
				first.stop()
				local nearest = sections({ entry = "nearest", preferred = "Two" })
				nearest.gui.SelectedObject = nearest.find("One")
				nearest.gui.SelectedObject = nearest.find("Outside")
				nearest.gui.SelectedObject = nearest.find("Three")
				expect((nearest.selected())):toBe("Three")
				nearest.stop()
			end,
		})
	end)

	describe("focusSection focusOnAppear and returnFocus", function()
		it("lands on the appearing branch and returns to the row that opened it", {
			id = "native_focus_model::focusSection focusOnAppear and returnFocus::lands on the appearing branch and returns to the row that opened it",
			run = function()
				local open = Compose.cell(false)
				local w = setup(function(UI, Host)
					return Host.Frame "Page" {
						UI.Button "Row" { label = "Row" },
						Compose.show(open, function()
							local detail = UI.VStack "Detail" {
								UI.Button "Title" { label = "Title" },
								UI.Button "Back" { label = "Back" },
							}
							UI.focusSection(detail, { focusOnAppear = "Back", returnFocus = true })
							return detail
						end),
					}
				end)
				w.gui.SelectedObject = w.find("Row")
				open:set(true)
				expect((w.selected())):toBe("Back")
				open:set(false)
				expect((w.selected())):toBe("Row")
				w.stop()
			end,
		})
		it("does not take the selection when nothing is selected (a touch or mouse player)", {
			id = "native_focus_model::focusSection focusOnAppear and returnFocus::does not take the selection when nothing is selected (a touch or mouse player)",
			run = function()
				local open = Compose.cell(false)
				local w = setup(function(UI, Host)
					return Host.Frame "Page" {
						UI.Button "Row" { label = "Row" },
						Compose.show(open, function()
							local detail = UI.VStack "Detail" { UI.Button "Back" { label = "Back" } }
							UI.focusSection(detail, { focusOnAppear = true, returnFocus = true })
							return detail
						end),
					}
				end)
				open:set(true)
				expect((w.selected())):toBe("nil")
				open:set(false)
				expect((w.selected())):toBe("nil")
				w.stop()
			end,
		})
		it("without the keys the selection stays where the engine left it", {
			id = "native_focus_model::focusSection focusOnAppear and returnFocus::without the keys the selection stays where the engine left it",
			run = function()
				local open = Compose.cell(false)
				local w = setup(function(UI, Host)
					return Host.Frame "Page" {
						UI.Button "Row" { label = "Row" },
						Compose.show(open, function()
							local detail = UI.VStack "Detail" { UI.Button "Back" { label = "Back" } }
							UI.focusSection(detail)
							return detail
						end),
					}
				end)
				w.gui.SelectedObject = w.find("Row")
				open:set(true)
				expect((w.selected())):toBe("Row")
				w.stop()
			end,
		})
	end)

	describe("responder: engage, resign and the gameplay guard (DK-13/DK-15)", function()
		local function form(options: EnvironmentTypes.ResponderOptions?)
			local responder: any
			local presses: { [string]: number } = {}
			local w = setup(function(UI)
				local hud = UI.Screen "Hud" {
					UI.Button "One" {
						label = "One",
						onActivate = function()
							presses.one = (presses.one or 0) + 1
						end,
					},
					UI.Button "Two" {
						label = "Two",
						onActivate = function()
							presses.two = (presses.two or 0) + 1
						end,
					},
					UI.Button "Three" { label = "Three" },
				}
				responder = UI.responder(hud, options)
				return hud
			end)
			local function traversal(): boolean
				return w.find("FacetTraversal", w.parent).Enabled
			end
			local function guard(): boolean
				local guard = w.find("FacetGameplayGuard", w.parent)
				return guard ~= nil and guard.Enabled
			end
			local function tap(hits: { any }, kind: string?)
				w.parent.GetGuiObjectsAtPosition = function()
					return hits
				end
				local E = w.engine.types.Enum
				w.input.InputBegan:Fire({
					UserInputType = if kind == "touch" then E.UserInputType.Touch else E.UserInputType.MouseButton1,
					KeyCode = E.KeyCode:FromValue(0),
					Position = w.engine.types.Vector3.new(10, 10, 0),
				}, true)
			end
			return w, { responder = responder, presses = presses, traversal = traversal, guard = guard, tap = tap }
		end
		it("a passive surface at rest binds no Tab and no guard: the game keeps the keys", {
			id = "native_focus_model::responder: engage, resign and the gameplay guard (DK-13/DK-15)::a passive surface at rest binds no Tab and no guard: the game keeps the keys",
			run = function()
				local w, formState = form()
				expect((formState.responder.state:peek())):toBe("passive")
				expect((formState.traversal())):toBe(false)
				expect((formState.guard())):toBe(false)
				local E = w.engine.types.Enum
				w.input.InputBegan:Fire(
					{ UserInputType = E.UserInputType.Gamepad1, KeyCode = E.KeyCode.DPadDown },
					false
				)
				expect((w.selected())):toBe("nil")
				w.stop()
			end,
		})
		it("engage() binds Tab and the guard; the first Tab enters, resign() gives the keys back", {
			id = "native_focus_model::responder: engage, resign and the gameplay guard (DK-13/DK-15)::engage() binds Tab and the guard; the first Tab enters, resign() gives the keys back",
			run = function()
				local w, formState = form()
				formState.responder.engage()
				expect((formState.responder.state:peek())):toBe("engaged")
				expect((formState.traversal())):toBe(true)
				expect((formState.guard())):toBe(true)
				w.tab()
				expect((w.selected())):toBe("One")
				w.tab()
				expect((w.selected())):toBe("Two")
				formState.responder.resign()
				expect((formState.responder.state:peek())):toBe("passive")
				expect((w.selected())):toBe("nil")
				expect((formState.traversal())):toBe(false)
				expect((formState.guard())):toBe(false)
				w.stop()
			end,
		})
		it("a tap on the surface engages on the tapped control; a tap outside resigns", {
			id = "native_focus_model::responder: engage, resign and the gameplay guard (DK-13/DK-15)::a tap on the surface engages on the tapped control; a tap outside resigns",
			run = function()
				local w, formState = form()
				formState.tap({ w.find("One") })
				expect((formState.responder.state:peek())):toBe("engaged")
				expect((w.selected())):toBe("One")
				w.tab()
				expect((w.selected())):toBe("Two")
				formState.tap({}, "touch")
				expect((formState.responder.state:peek())):toBe("passive")
				expect((w.selected())):toBe("nil")
				expect((formState.traversal())):toBe(false)
				w.stop()
			end,
		})
		it("the selection entering the surface engages it; Cancel resigns it", {
			id = "native_focus_model::responder: engage, resign and the gameplay guard (DK-13/DK-15)::the selection entering the surface engages it; Cancel resigns it",
			run = function()
				local w, formState = form()
				w.gui.SelectedObject = w.find("Two")
				expect((formState.responder.state:peek())):toBe("engaged")
				local cancel = w.find("FacetResponderCancel", w.parent)
				expect(cancel.Sink):toBe(false)
				cancel:FindFirstChild("Cancel").Pressed:Fire()
				expect((formState.responder.state:peek())):toBe("passive")
				expect((w.selected())):toBe("nil")
				w.stop()
			end,
		})

		it("resignOnActivate gives the selection back to the game after an A press on a button", {
			id = "native_focus_model::responder: engage, resign and the gameplay guard (DK-13/DK-15)::resignOnActivate gives the selection back to the game after an A press on a button",
			run = function()
				local E
				for _, wanted in { false, true } do
					local w, formState = form(if wanted then { resignOnActivate = true } else nil)
					E = w.engine.types.Enum
					w.gui.SelectedObject = w.find("Two")
					w.input.InputEnded:Fire(
						{ UserInputType = E.UserInputType.Gamepad1, KeyCode = E.KeyCode.ButtonX },
						true
					)
					expect((w.selected())):toBe("Two")
					w.input.InputEnded:Fire(
						{ UserInputType = E.UserInputType.Gamepad1, KeyCode = E.KeyCode.ButtonA },
						true
					)
					expect((w.selected())):toBe(if wanted then "nil" else "Two")
					expect((formState.responder.state:peek())):toBe(if wanted then "passive" else "engaged")
					w.stop()
				end
			end,
		})
		it("a Composition HUD button returns the selection to the game after A", {
			id = "native_focus_model::responder: engage, resign and the gameplay guard (DK-13/DK-15)::a Composition HUD button returns the selection to the game after A",
			run = function()
				local boosts = 0
				local w = setup(function(UI)
					return UI.Composition "Hud" {
						UI.Region "Boost" {
							zone = "bottomRight",
							rank = 1,
							UI.Button "Boost" {
								label = "Boost",
								onActivate = function()
									boosts += 1
								end,
							},
						},
					}
				end)
				local E = w.engine.types.Enum
				local boost = w.find("Boost", w.find("Hud"))
				while boost and not boost:IsA("GuiButton") do
					boost = boost:FindFirstChild("Boost", true)
				end
				w.gui.SelectedObject = boost
				w.input.InputEnded:Fire({ UserInputType = E.UserInputType.Gamepad1, KeyCode = E.KeyCode.ButtonA }, true)
				expect(w.gui.SelectedObject):toBeNil()
				w.stop()
			end,
		})

		it("gameplayGuard = false binds neither the guard nor Space on its buttons", {
			id = "native_focus_model::responder: engage, resign and the gameplay guard (DK-13/DK-15)::gameplayGuard = false binds neither the guard nor Space on its buttons",
			run = function()
				local w, formState = form({ gameplayGuard = false })
				formState.responder.engage()
				expect((formState.guard())):toBe(false)
				w.gui.SelectedObject = w.find("One")
				expect((w.activateKeys())):toEqual({ "Return" })
				w.stop()
			end,
		})
	end)

	describe("a passive HUD (Composition)", function()
		local function hud(passive: boolean?)
			return setup(function(UI)
				return UI.Screen "Page" {
					UI.Composition "Hud" {
						passive = passive,
						UI.Region "Wallet" {
							zone = "topLeft",
							rank = 1,
							UI.Button "Shop" { label = "Shop" },
						},
					},
				}
			end)
		end
		it("engageOnPress = false: a tap on the surface leaves it at rest and selects nothing", {
			id = "native_focus_model::a passive HUD (Composition)::engageOnPress = false: a tap on the surface leaves it at rest and selects nothing",
			run = function()
				local state = function(): string
					return "none"
				end
				local w = setup(function(UI)
					local surface = UI.Screen "Hud" {
						UI.Button "One" { label = "One" },
						UI.Button "Two" { label = "Two" },
					}
					local responder = UI.responder(surface, { engageOnPress = false })
					state = function(): string
						return responder.state:peek()
					end
					return surface
				end)
				w.parent.GetGuiObjectsAtPosition = function()
					return { w.find("One") }
				end
				local E = w.engine.types.Enum
				w.input.InputBegan:Fire({
					UserInputType = E.UserInputType.MouseButton1,
					KeyCode = E.KeyCode:FromValue(0),
					Position = w.engine.types.Vector3.new(10, 10, 0),
				}, true)
				expect(state()):toBe("passive")
				expect((w.selected())):toBe("nil")
				w.gui.SelectedObject = w.find("One")
				expect(state()):toBe("engaged")
				w.parent.GetGuiObjectsAtPosition = function()
					return { w.find("Two") }
				end
				w.input.InputBegan:Fire({
					UserInputType = E.UserInputType.MouseButton1,
					KeyCode = E.KeyCode:FromValue(0),
					Position = w.engine.types.Vector3.new(10, 10, 0),
				}, true)
				expect((w.selected())):toBe("Two")
				w.stop()
			end,
		})
		it("the movement stick and the D-pad drive the game: neither enters a Composition HUD", {
			id = "native_focus_model::a passive HUD (Composition)::the movement stick and the D-pad drive the game: neither enters a Composition HUD",
			run = function()
				local w = hud()
				local E = w.engine.types.Enum
				w.input.InputBegan:Fire(
					{ UserInputType = E.UserInputType.Gamepad1, KeyCode = E.KeyCode.DPadDown },
					false
				)
				expect((w.selected())):toBe("nil")
				w.find("FacetEntry", w.parent)
					:FindFirstChild("Enter").StateChanged
					:Fire(w.engine.types.Vector2.new(0, -1))
				expect((w.selected())):toBe("nil")
				expect(w.find("FacetTraversal", w.parent).Enabled):toBe(false)
				w.stop()
			end,
		})
		it("passive = false makes a Composition an ordinary screen the D-pad enters", {
			id = "native_focus_model::a passive HUD (Composition)::passive = false makes a Composition an ordinary screen the D-pad enters",
			run = function()
				local w = hud(false)
				local E = w.engine.types.Enum
				w.input.InputBegan:Fire(
					{ UserInputType = E.UserInputType.Gamepad1, KeyCode = E.KeyCode.DPadDown },
					false
				)
				expect((w.selected())):toBe("Shop")
				w.stop()
			end,
		})
		it("a resting HUD beside an always-engaged screen keeps Tab, and the D-pad enters that screen", {
			id = "native_focus_model::a passive HUD (Composition)::a resting HUD beside an always-engaged screen keeps Tab, and the D-pad enters that screen",
			run = function()
				local w = setup(function(UI)
					local page = UI.Screen "Page" {
						UI.Composition "Hud" {
							UI.Region "Wallet" { zone = "topLeft", rank = 1, UI.Button "Shop" { label = "Shop" } },
						},
						UI.Button "Play" { label = "Play" },
					}
					UI.responder(page, { passive = false })
					return page
				end)
				expect(w.find("FacetTraversal", w.parent).Enabled):toBe(true)
				local E = w.engine.types.Enum
				w.input.InputBegan:Fire(
					{ UserInputType = E.UserInputType.Gamepad1, KeyCode = E.KeyCode.DPadDown },
					false
				)
				expect((w.selected())):toBe("Play")
				w.stop()
			end,
		})
		it("the game puts the selection in a Composition HUD; Space still reaches the game", {
			id = "native_focus_model::a passive HUD (Composition)::the game puts the selection in a Composition HUD; Space still reaches the game",
			run = function()
				local w = hud()
				w.gui.SelectedObject = w.find("Shop")
				expect(w.find("FacetTraversal", w.parent).Enabled):toBe(true)
				expect((w.activateKeys())):toEqual({ "Return" })
				local guard = w.find("FacetGameplayGuard", w.parent)
				expect(guard == nil or not guard.Enabled):toBe(true)
				w.stop()
			end,
		})
	end)

	describe("traversalWrap (DK-3)", function()
		it("traversalWrap = false stops Tab at the last control and Shift+Tab at the first", {
			id = "native_focus_model::traversalWrap (DK-3)::traversalWrap = false stops Tab at the last control and Shift+Tab at the first",
			run = function()
				local w = setup(function(UI)
					local page = UI.Screen "Page" {
						UI.Button "A" { label = "A" },
						UI.Button "B" { label = "B" },
					}
					UI.responder(page, { passive = false, traversalWrap = false })
					return page
				end)
				w.tab()
				w.tab()
				expect((w.selected())):toBe("B")
				w.tab()
				expect((w.selected())):toBe("B")
				w.input.IsKeyDown = function()
					return true
				end
				w.tab()
				expect((w.selected())):toBe("A")
				w.tab()
				expect((w.selected())):toBe("A")
				w.stop()
			end,
		})
	end)

	describe("keyboardNavigation = false", function()
		it("binds no Tab and no Space; Return still activates", {
			id = "native_focus_model::keyboardNavigation = false::binds no Tab and no Space; Return still activates",
			run = function()
				local w = setup(function(UI)
					return UI.Screen "Page" { UI.Button "A" { label = "A" } }
				end, { keyboardNavigation = false })
				w.gui.SelectedObject = w.find("A")
				expect(w.find("FacetTraversal", w.parent).Enabled):toBe(false)
				expect((w.activateKeys())):toEqual({ "Return" })
				w.stop()
			end,
		})
		it("true (and the default) binds Tab, and Space next to Return on a selected Button", {
			id = "native_focus_model::keyboardNavigation = false::true (and the default) binds Tab, and Space next to Return on a selected Button",
			run = function()
				local options: { Facet.ControlOptions } = { {}, { keyboardNavigation = true } }
				for _, options in options do
					local w = setup(function(UI)
						return UI.Screen "Page" { UI.Button "A" { label = "A" } }
					end, options)
					expect(w.find("FacetTraversal", w.parent).Enabled):toBe(true)
					w.gui.SelectedObject = w.find("A")
					expect((w.activateKeys())):toEqual({ "Return", "Space" })
					w.stop()
				end
			end,
		})
	end)
end
