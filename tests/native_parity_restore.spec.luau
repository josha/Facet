--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	local FixtureCollectionTypes = require("../src/ui/collection_types")

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local Roblox = require("@lune/roblox")
	type Readable<T> = { peek: (Readable<T>) -> T }
	local Compose: ComposeModule = Facet.Compose

	type World = {
		engine: any,
		runtime: any,
		UI: any,
		Host: any,
		gui: any,
		input: any,
		screen: any,
		stop: () -> (),
	}

	local function world(build: (any, any, any) -> any, options: { [string]: any }?, engineOptions: any?): World
		local engine: any = engineLib.new(engineOptions)
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local input = engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		input.IsKeyDown = function()
			return false
		end
		local config: { [string]: any } = {
			types = engine.types,
			guiService = gui,
			motionLevel = "none",
			services = { GuiService = gui, UserInputService = input },
		}
		for key, value in (options or {}) :: { [string]: any } do
			config[key] = value
		end
		local UI = Facet.controls(runtime, config :: any)
		local Host = (runtime.constructors :: unknown) :: RobloxHost
		local stop, screen: any = runtime.mount(function()
			return Host.ScreenGui({ build(UI, Host, engine) })
		end, engine.new("Folder"))
		return {
			engine = engine,
			runtime = runtime,
			UI = UI,
			Host = Host,
			gui = gui,
			input = input,
			screen = screen,
			stop = function()
				stop()
				runtime:dispose()
			end,
		}
	end

	local function find(root: any, name: string): any
		if root.Name == name then
			return root
		end
		for _, child in root:GetChildren() do
			local found = find(child, name)
			if found then
				return found
			end
		end
		return nil
	end

	verifyHarness:suite("native parity restore: ErrorBoundary", function()
		verifyHarness:case("renders its view when healthy and does not mount the fallback", {
			id = "native_parity_restore::native parity restore: ErrorBoundary::renders its view when healthy and does not mount the fallback",
			run = function()
				local w = world(function(UI, Host)
					return UI.ErrorBoundary "EB" {
						view = function()
							return Host.TextLabel "Happy" { Text = "ok" }
						end,
						fallback = function()
							return Host.TextLabel "Fallback" { Text = "broken" }
						end,
					}
				end)
				local boundary = find(w.screen, "EB")
				Verify.expect(boundary ~= nil):toBe(true)
				Verify.expect(find(boundary, "Happy") ~= nil):toBe(true)
				Verify.expect((find(w.screen, "Fallback"))):toBeNil()
				Verify.expect((boundary:GetAttribute("FacetError"))):toBeNil()
				w.stop()
			end,
		})

		verifyHarness:case("swaps a view that throws at mount to its fallback, reports once and keeps siblings", {
			id = "native_parity_restore::native parity restore: ErrorBoundary::swaps a view that throws at mount to its fallback, reports once and keeps siblings",
			run = function()
				local reported: { string } = {}
				local w = world(function(UI, Host)
					return Host.Frame "Column" {
						Host.TextLabel "Sibling" { Text = "alive" } :: unknown,
						UI.ErrorBoundary({
							Name = "EB",
							view = function()
								error("factory exploded", 0)
							end,
							fallback = function(failure)
								return Host.TextLabel "Fallback" { Text = tostring(failure) }
							end,
							onError = function(failure)
								table.insert(reported, tostring(failure))
							end,
						}),
					}
				end)
				Verify.expect(find(w.screen, "Sibling") ~= nil):toBe(true)
				local fallback = find(find(w.screen, "EB"), "Fallback")
				Verify.expect(fallback ~= nil):toBe(true)
				Verify.expect(fallback.Text):toBe("factory exploded")
				Verify.expect(reported):toEqual({ "factory exploded" })
				Verify.expect((find(w.screen, "EB"):GetAttribute("FacetError"))):toBe("factory exploded")
				w.stop()
			end,
		})

		verifyHarness:case("trips at runtime when a structural rebuild inside it throws, and the writer survives", {
			id = "native_parity_restore::native parity restore: ErrorBoundary::trips at runtime when a structural rebuild inside it throws, and the writer survives",
			run = function()
				local explode = Compose.cell(false)
				local viewCleanups = 0
				local w = world(function(UI, Host)
					return UI.ErrorBoundary "EB" {
						view = function()
							Compose.cleanup(function()
								viewCleanups += 1
							end)
							return Host.Frame "V" {
								Compose.show(explode, function()
									error("branch exploded", 0)
								end) :: unknown,
								Host.TextLabel "Content" { Text = "fine" },
							}
						end,
						fallback = function(failure)
							return Host.TextLabel "Fallback" { Text = tostring(failure) }
						end,
					}
				end)
				Verify.expect(find(w.screen, "Content") ~= nil):toBe(true)
				local ok = pcall(function()
					explode:set(true)
				end)
				Verify.expect(ok):toBe(true)
				Verify.expect((find(w.screen, "Content"))):toBeNil()
				Verify.expect(find(w.screen, "Fallback").Text):toBe("branch exploded")
				Verify.expect(viewCleanups):toBe(1)
				local probe = Compose.cell(1)
				probe:set(2)
				Verify.expect((probe:peek())):toBe(2)
				w.stop()
			end,
		})

		verifyHarness:case("retries the view from the fallback and clears the reported error", {
			id = "native_parity_restore::native parity restore: ErrorBoundary::retries the view from the fallback and clears the reported error",
			run = function()
				local broken = true
				local w = world(function(UI, Host)
					return UI.ErrorBoundary "EB" {
						view = function()
							if broken then
								error("not ready", 0)
							end
							return Host.TextLabel "Ready" { Text = "ready" }
						end,
						fallback = function(_, retry)
							return Host.TextButton "Retry" {
								Text = "Retry",
								Activated = retry,
							}
						end,
					}
				end)
				local boundary = find(w.screen, "EB")
				Verify.expect((boundary:GetAttribute("FacetError"))):toBe("not ready")
				find(boundary, "Retry").Activated.fire()
				Verify.expect(find(boundary, "Retry") ~= nil):toBe(true)
				broken = false
				find(boundary, "Retry").Activated.fire()
				Verify.expect((find(boundary, "Retry"))):toBeNil()
				Verify.expect(find(boundary, "Ready") ~= nil):toBe(true)
				Verify.expect((boundary:GetAttribute("FacetError"))):toBeNil()
				w.stop()
			end,
		})

		verifyHarness:case("sends a failure to the factory onError when the boundary has no onError", {
			id = "native_parity_restore::native parity restore: ErrorBoundary::sends a failure to the factory onError when the boundary has no onError",
			run = function()
				local reported: { string } = {}
				local w = world(function(UI, Host)
					return UI.ErrorBoundary "EB" {
						view = function()
							error("unowned", 0)
						end,
						fallback = function()
							return Host.Frame "Fallback" {}
						end,
					}
				end, {
					onError = function(failure)
						table.insert(reported, tostring(failure))
					end,
				})
				Verify.expect(reported):toEqual({ "unowned" })
				w.stop()
			end,
		})

		verifyHarness:case("contains a throwing keyed row factory and releases every owner on disposal", {
			id = "native_parity_restore::native parity restore: ErrorBoundary::contains a throwing keyed row factory and releases every owner on disposal",
			run = function()
				local rows = Compose.cell({ { id = "a" }, { id = "b" } })
				local live = 0
				local w = world(function(UI, Host)
					return UI.ErrorBoundary "EB" {
						view = function()
							return Host.Frame "Rows" {
								Compose.keyed({
									from = rows,
									key = function(row)
										return row.id
									end,
									render = function(row: Readable<{ id: string }>): GuiObject
										if row:peek().id == "c" then
											error("row factory throws for c", 0)
										end
										live += 1
										Compose.cleanup(function()
											live -= 1
										end)
										return Host.TextLabel({ Name = row:peek().id })
									end,
								}),
							}
						end,
						fallback = function()
							live += 1
							Compose.cleanup(function()
								live -= 1
							end)
							return Host.TextLabel "Fallback" { Text = "broken" }
						end,
					}
				end)
				Verify.expect(live):toBe(2)
				rows:set({ { id = "a" }, { id = "c" } })
				Verify.expect(find(w.screen, "Fallback") ~= nil):toBe(true)
				Verify.expect((find(w.screen, "a"))):toBeNil()
				Verify.expect(live):toBe(1)
				w.stop()
				Verify.expect(live):toBe(0)
			end,
		})

		verifyHarness:case("leaves a failure outside any boundary a hard mount error", {
			id = "native_parity_restore::native parity restore: ErrorBoundary::leaves a failure outside any boundary a hard mount error",
			run = function()
				local engine: any = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local Host = (runtime.constructors :: unknown) :: RobloxHost
				local ok, message = pcall(function()
					runtime.mount(function()
						return Host.Frame({
							Compose.show(Compose.cell(true), function()
								error("no boundary here", 0)
							end),
						})
					end, engine.new("ScreenGui"))
				end)
				runtime:dispose()
				Verify.expect(ok):toBe(false)
				Verify.expect(string.find(tostring(message), "no boundary here", 1, true) ~= nil):toBe(true)
			end,
		})

		verifyHarness:case("accepts both construction forms and refuses a boundary without a view or a fallback", {
			id = "native_parity_restore::native parity restore: ErrorBoundary::accepts both construction forms and refuses a boundary without a view or a fallback",
			run = function()
				local w = world(function(UI, Host)
					return Host.Frame({
						UI.ErrorBoundary({
							Name = "Healthy",
							view = function()
								return Host.TextLabel "Ok" { Text = "ok" }
							end,
							fallback = function()
								return Host.TextLabel "HealthyFallback" {}
							end,
						}) :: unknown,
						UI.ErrorBoundary "Broken" {
							view = function(): any
								error("factory exploded", 0)
							end,
							fallback = function()
								return Host.TextLabel "BrokenFallback" {}
							end,
						},
					})
				end)
				Verify.expect(find(find(w.screen, "Healthy"), "Ok") ~= nil):toBe(true)
				Verify.expect((find(w.screen, "HealthyFallback"))):toBeNil()
				Verify.expect(find(find(w.screen, "Broken"), "BrokenFallback") ~= nil):toBe(true)
				for _, spec in
					{
						{ fallback = function() end },
						{ view = function() end },
					} :: { any }
				do
					local refused = pcall(function()
						local probe = world(function(UI)
							return UI.ErrorBoundary(spec)
						end)
						probe.stop()
					end)
					Verify.expect(refused):toBe(false)
				end
				w.stop()
			end,
		})
	end)

	local function ratio(first: any, second: any): number
		local function luminance(value: any): number
			local function linear(channel: number): number
				return if channel <= 0.04045 then channel / 12.92 else ((channel + 0.055) / 1.055) ^ 2.4
			end
			return 0.2126 * linear(value.r) + 0.7152 * linear(value.g) + 0.0722 * linear(value.b)
		end
		local a, b = luminance(first), luminance(second)
		return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05)
	end

	local function sortedKeys(value: { [string]: any }): { string }
		local keys: { string } = {}
		for key in value do
			table.insert(keys, key)
		end
		table.sort(keys)
		return keys
	end

	verifyHarness:suite("native parity restore: Facet Neutral Light", function()
		verifyHarness:case("declares Dark then Light and both palettes pass the contrast gate", {
			id = "native_parity_restore::native parity restore: Facet Neutral Light::declares Dark then Light and both palettes pass the contrast gate",
			run = function()
				local themes = Facet.themes
				local neutral = themes.neutralPackage()
				Verify.expect(neutral.style.defaultTheme):toBe("Dark")
				Verify.expect(#neutral.style.themes):toBe(2)
				local dark, light = neutral.style.themes[1], neutral.style.themes[2]
				Verify.expect(dark.name):toBe("Dark")
				Verify.expect(light.name):toBe("Light")
				Verify.expect((sortedKeys(light.colors))):toEqual(sortedKeys(dark.colors))
				Verify.expect((sortedKeys(assert(light.extra)))):toEqual(sortedKeys(assert(dark.extra)))
				local defined, report = themes.define(neutral)
				Verify.expect(defined ~= nil):toBe(true)
				Verify.expect(report.ok):toBe(true)
				Verify.expect(#report.contrast):toBe(14)
				for _, result in report.contrast do
					Verify.expect(result.ok):toBe(true)
				end
				for _, pair in
					{ { "content", "surface" }, { "contentStrong", "surfaceStrong" }, { "onAccent", "accent" } }
				do
					Verify.expect(ratio(light.colors[pair[1]], light.colors[pair[2]]) >= 4.5):toBe(true)
				end
				Verify.expect(ratio(light.colors.content, assert(light.extra).controlSelected) >= 4.5):toBe(true)
				Verify.expect(ratio(assert(light.extra).contentSecondary, light.colors.surface) >= 4.5):toBe(true)
				Verify.expect(ratio(light.colors.content, assert(light.extra).control) >= 4.5):toBe(true)
				Verify.expect(ratio(light.colors.surface, dark.colors.surface) > 10):toBe(true)
			end,
		})

		verifyHarness:case("keeps a derived package to its own palettes and inherits only the first", {
			id = "native_parity_restore::native parity restore: Facet Neutral Light::keeps a derived package to its own palettes and inherits only the first",
			run = function()
				local themes = Facet.themes
				local plain = assert(themes.define({
					identity = { id = "derived", displayName = "Derived", version = "1.0.0" },
				} :: any))
				Verify.expect(#plain.style.themes):toBe(1)
				Verify.expect(plain.style.themes[1].name):toBe("Dark")
				local based = assert(themes.define({
					base = themes.neutralPackage(),
					identity = { id = "based", displayName = "Based", version = "1.0.0" },
				} :: any))
				Verify.expect(#based.style.themes):toBe(1)
				local paired = assert(themes.define({
					identity = { id = "paired", displayName = "Paired", version = "1.0.0" },
					style = { defaultTheme = "Day", themes = { { name = "Day" }, { name = "Night" } } },
				} :: any))
				Verify.expect(#paired.style.themes):toBe(2)
				Verify.expect(#themes.neutralPackage().style.themes):toBe(2)
			end,
		})

		verifyHarness:case("paints each Neutral palette through the native sheet and follows a palette change", {
			id = "native_parity_restore::native parity restore: Facet Neutral Light::paints each Neutral palette through the native sheet and follows a palette change",
			run = function()
				local themes = Facet.themes
				local engine: any = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local neutral = themes.neutralPackage()
				local selected = Compose.cell("Dark")
				local stop, sheet: any = runtime.mount(function()
					return themes.createStyleSheet(runtime, neutral, { types = engine.types, theme = selected } :: any)
				end, engine.new("Folder"))
				local function textColor(): any
					for _, rule in sheet:GetChildren() do
						if rule.Selector == ".facet-text" then
							return rule:GetProperties().TextColor3
						end
					end

					return nil
				end
				local function expected(palette: any): any
					local value = palette.colors.content
					return engine.types.Color3.new(value.r, value.g, value.b)
				end
				Verify.expect((textColor())):toBe(expected(neutral.style.themes[1]))
				selected:set("Light")
				Verify.expect((textColor())):toBe(expected(neutral.style.themes[2]))
				stop()
				runtime:dispose()
			end,
		})
	end)

	verifyHarness:suite("native parity restore: Table multi-select keys", function()
		local held: { [string]: boolean } = {}
		local function racers(): { { id: string, name: string } }
			return {
				{ id = "razz", name = "Razz" },
				{ id = "bolt", name = "Bolt" },
				{ id = "josh", name = "Josh" },
				{ id = "mint", name = "Mint" },
				{ id = "nova", name = "Nova" },
			}
		end
		local function tableWorld(mode: ("single" | "multiple" | "none")?, editing: boolean?): (World, any, any)
			table.clear(held)
			local selection = Compose.cell({})
			local focus: FixtureCollectionTypes.FocusControls<any> = {}
			local w = world(function(UI: FacetControls)
				return UI.Table "Racers" {
					from = racers(),
					key = "id",
					itemSize = 40,
					focus = focus,
					selection = selection,
					selectionMode = mode or ("multiple" :: "multiple"),
					editing = editing,
					columns = {
						{
							id = "name",
							label = "Racer",
							value = function(item)
								return item.name
							end,
						} :: FixtureCollectionTypes.TableColumn<any, any>,
					},
				}
			end)
			w.input.IsKeyDown = function(_, key: any)
				return held[key.Name] == true
			end
			local body = find(w.screen, "Body")
			body.AbsoluteWindowSize = w.engine.types.Vector2.new(300, 400)
			return w, selection, focus
		end
		local function hit(w: World, key: string): any
			return find(find(w.screen, "Body"), key):FindFirstChild("RowHit", true)
		end
		local function click(w: World, key: string, ...: string)
			for _, name in { ... } do
				held[name] = true
			end
			hit(w, key).Activated.fire({ UserInputType = w.engine.types.Enum.UserInputType.MouseButton1 }, 0)
			table.clear(held)
		end
		local function tap(w: World, key: string)
			hit(w, key).Activated.fire({ UserInputType = w.engine.types.Enum.UserInputType.Touch }, 1)
		end
		local function returnKey(w: World, key: string)
			local E = w.engine.types.Enum
			hit(w, key).Activated.fire({ UserInputType = E.UserInputType.Keyboard, KeyCode = E.KeyCode.Return }, 1)
		end
		local function arrow(w: World, name: string)
			w.screen:FindFirstChild("FacetCollection" .. name):FindFirstChild("Collection" .. name).Pressed.fire()
		end
		local function selected(selection: any): { string }
			local out: { string } = {}
			for key, on in selection:peek() do
				if on then
					table.insert(out, key)
				end
			end
			table.sort(out)
			return out
		end

		verifyHarness:case("replaces a multi selection on a plain mouse click", {
			id = "native_parity_restore::native parity restore: Table multi-select keys::replaces a multi selection on a plain mouse click",
			run = function()
				local w, selection = tableWorld()
				click(w, "razz")
				click(w, "bolt", "LeftControl")
				Verify.expect((selected(selection))):toEqual({ "bolt", "razz" })
				click(w, "josh")
				Verify.expect((selected(selection))):toEqual({ "josh" })
				w.stop()
			end,
		})

		verifyHarness:case("toggles rows in and out of a multi selection on a Ctrl-click and a Cmd-click", {
			id = "native_parity_restore::native parity restore: Table multi-select keys::toggles rows in and out of a multi selection on a Ctrl-click and a Cmd-click",
			run = function()
				for _, modifier in { "LeftControl", "RightControl", "LeftMeta", "RightMeta", "LeftSuper" } do
					local w, selection = tableWorld()
					click(w, "razz")
					click(w, "josh", modifier)
					Verify.expect((selected(selection))):toEqual({ "josh", "razz" })
					click(w, "razz", modifier)
					Verify.expect((selected(selection))):toEqual({ "josh" })
					w.stop()
				end
			end,
		})

		verifyHarness:case(
			"extends a contiguous range from the anchor on a Shift-click and re-ranges from the same anchor",
			{
				id = "native_parity_restore::native parity restore: Table multi-select keys::extends a contiguous range from the anchor on a Shift-click and re-ranges from the same anchor",
				run = function()
					local w, selection = tableWorld()
					click(w, "razz")
					click(w, "josh", "LeftShift")
					Verify.expect((selected(selection))):toEqual({ "bolt", "josh", "razz" })
					click(w, "bolt", "RightShift")
					Verify.expect((selected(selection))):toEqual({ "bolt", "razz" })
					w.stop()
				end,
			}
		)

		verifyHarness:case("selects a reversed range when a Shift-click goes from a later row to an earlier one", {
			id = "native_parity_restore::native parity restore: Table multi-select keys::selects a reversed range when a Shift-click goes from a later row to an earlier one",
			run = function()
				local w, selection = tableWorld()
				click(w, "josh")
				click(w, "razz", "LeftShift")
				Verify.expect((selected(selection))):toEqual({ "bolt", "josh", "razz" })
				w.stop()
			end,
		})

		verifyHarness:case("keeps Ctrl-toggled rows when a Shift-click ranges from a toggled anchor", {
			id = "native_parity_restore::native parity restore: Table multi-select keys::keeps Ctrl-toggled rows when a Shift-click ranges from a toggled anchor",
			run = function()
				local w, selection = tableWorld()
				click(w, "razz")
				click(w, "josh", "LeftControl")
				click(w, "nova", "LeftShift")
				Verify.expect((selected(selection))):toEqual({ "josh", "mint", "nova", "razz" })
				w.stop()
			end,
		})

		verifyHarness:case("drops a row that the model deselected from the base of a later Shift range", {
			id = "native_parity_restore::native parity restore: Table multi-select keys::drops a row that the model deselected from the base of a later Shift range",
			run = function()
				local w, selection = tableWorld()
				click(w, "razz")
				click(w, "nova", "LeftControl")
				selection:set({ nova = true })
				click(w, "mint", "LeftShift")
				Verify.expect((selected(selection))):toEqual({ "mint", "nova" })
				w.stop()
			end,
		})

		verifyHarness:case("keeps the additive toggle for a touch tap and a gamepad press in edit mode", {
			id = "native_parity_restore::native parity restore: Table multi-select keys::keeps the additive toggle for a touch tap and a gamepad press in edit mode",
			run = function()
				local w, selection = tableWorld(nil, true)
				tap(w, "razz")
				tap(w, "josh")
				Verify.expect((selected(selection))):toEqual({ "josh", "razz" })
				local E = w.engine.types.Enum
				hit(w, "razz").Activated.fire(
					{ UserInputType = E.UserInputType.Gamepad1, KeyCode = E.KeyCode.ButtonA },
					1
				)
				Verify.expect((selected(selection))):toEqual({ "josh" })
				w.stop()
			end,
		})

		verifyHarness:case("honors held modifiers on a keyboard Return", {
			id = "native_parity_restore::native parity restore: Table multi-select keys::honors held modifiers on a keyboard Return",
			run = function()
				local w, selection = tableWorld()
				returnKey(w, "razz")
				Verify.expect((selected(selection))):toEqual({ "razz" })
				held.LeftControl = true
				returnKey(w, "razz")
				Verify.expect((selected(selection))):toEqual({})
				table.clear(held)
				returnKey(w, "bolt")
				held.LeftShift = true
				returnKey(w, "mint")
				Verify.expect((selected(selection))):toEqual({ "bolt", "josh", "mint" })
				w.stop()
			end,
		})

		verifyHarness:case("extends the selection from the anchor with Shift and an arrow, and moves focus with it", {
			id = "native_parity_restore::native parity restore: Table multi-select keys::extends the selection from the anchor with Shift and an arrow, and moves focus with it",
			run = function()
				local w, selection, focus = tableWorld()
				assert(focus.focus)("bolt")
				Verify.expect(w.gui.SelectedObject):toBe(hit(w, "bolt"))
				returnKey(w, "bolt")
				Verify.expect((selected(selection))):toEqual({ "bolt" })
				held.LeftShift = true
				arrow(w, "Down")
				arrow(w, "Down")
				Verify.expect((assert(focus.current):peek())):toBe("mint")
				Verify.expect((selected(selection))):toEqual({ "bolt", "josh", "mint" })
				arrow(w, "Up")
				Verify.expect((selected(selection))):toEqual({ "bolt", "josh" })
				arrow(w, "Up")
				arrow(w, "Up")
				Verify.expect((assert(focus.current):peek())):toBe("razz")
				Verify.expect((selected(selection))):toEqual({ "bolt", "razz" })
				w.stop()
			end,
		})

		verifyHarness:case("extends to the first and the last row with Shift and Home or End", {
			id = "native_parity_restore::native parity restore: Table multi-select keys::extends to the first and the last row with Shift and Home or End",
			run = function()
				local w, selection, focus = tableWorld()
				assert(focus.focus)("josh")
				returnKey(w, "josh")
				held.LeftShift = true
				arrow(w, "Last")
				Verify.expect((assert(focus.current):peek())):toBe("nova")
				Verify.expect((selected(selection))):toEqual({ "josh", "mint", "nova" })
				arrow(w, "First")
				Verify.expect((selected(selection))):toEqual({ "bolt", "josh", "razz" })
				w.stop()
			end,
		})

		verifyHarness:case("starts a keyboard range at the focused row when nothing anchors it", {
			id = "native_parity_restore::native parity restore: Table multi-select keys::starts a keyboard range at the focused row when nothing anchors it",
			run = function()
				local w, selection, focus = tableWorld()
				assert(focus.focus)("josh")
				held.RightShift = true
				arrow(w, "Down")
				Verify.expect((selected(selection))):toEqual({ "josh", "mint" })
				w.stop()
			end,
		})

		verifyHarness:case("moves focus with Ctrl and an arrow and with a plain arrow without changing the selection", {
			id = "native_parity_restore::native parity restore: Table multi-select keys::moves focus with Ctrl and an arrow and with a plain arrow without changing the selection",
			run = function()
				local w, selection, focus = tableWorld()
				assert(focus.focus)("razz")
				returnKey(w, "razz")
				held.LeftControl = true
				arrow(w, "Down")
				arrow(w, "Down")
				Verify.expect((assert(focus.current):peek())):toBe("josh")
				Verify.expect((selected(selection))):toEqual({ "razz" })
				table.clear(held)
				arrow(w, "Down")
				Verify.expect((assert(focus.current):peek())):toBe("mint")
				Verify.expect((selected(selection))):toEqual({ "razz" })
				w.stop()
			end,
		})

		verifyHarness:case("replaces in single mode whatever the modifiers and ignores a Shift-arrow", {
			id = "native_parity_restore::native parity restore: Table multi-select keys::replaces in single mode whatever the modifiers and ignores a Shift-arrow",
			run = function()
				local w, selection, focus = tableWorld("single")
				click(w, "razz")
				click(w, "josh", "LeftControl")
				Verify.expect((selected(selection))):toEqual({ "josh" })
				click(w, "mint", "LeftShift")
				Verify.expect((selected(selection))):toEqual({ "mint" })
				assert(focus.focus)("mint")
				held.LeftShift = true
				arrow(w, "Down")
				Verify.expect((selected(selection))):toEqual({ "mint" })
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native parity restore: RowActions outside tap", function()
		local function rowsWorld(options: { [string]: any }?): (World, { [string]: any })
			local settings: { [string]: any } = options or {}
			local state: { [string]: any } = {
				open = { a = Compose.cell(nil), b = Compose.cell(nil) },
				coordinator = Compose.cell(nil),
				fired = {},
				outside = 0,
			}
			local w = world(function(UI: FacetControls, Host: RobloxHost)
				local function row(name: string)
					return UI.RowActions({
						Name = name,
						open = state.open[name],
						onOpenChange = settings.onOpenChange,
						coordinator = state.coordinator,
						content = function(): GuiObject
							return Host.TextButton "Content" { Text = name }
						end,
						trailing = {
							{
								id = "Delete",
								label = "Delete",
								role = settings.role,
								onActivate = function()
									table.insert(state.fired, name)
								end,
							} :: FixtureCollectionTypes.RowAction,
						},
					})
				end
				return Host.Frame "List" {
					row("a") :: unknown,
					row("b"),
					Host.TextButton "Outside" {
						Text = "Outside",
						Activated = function()
							state.outside += 1
						end,
					},
				}
			end, { motionLevel = settings.motionLevel or "none" })
			local V2 = w.engine.types.Vector2
			local a, b = find(w.screen, "a"), find(w.screen, "b")
			a.AbsolutePosition, a.AbsoluteSize = V2.new(0, 0), V2.new(300, 44)
			b.AbsolutePosition, b.AbsoluteSize = V2.new(0, 44), V2.new(300, 44)
			return w, state
		end
		local function press(w: World, x: number, y: number, kind: string?, processed: boolean?)
			local E = w.engine.types.Enum
			w.input.InputBegan.fire({
				UserInputType = (E.UserInputType :: any)[kind or "MouseButton1"],
				UserInputState = E.UserInputState.Begin,
				Position = w.engine.types.Vector3.new(x, y, 0),
			}, processed == true)
		end
		local function catchers(w: World): number
			local count = 0
			for _, node in w.screen:GetDescendants() do
				if node:IsA("GuiObject") and node.Active and node.Size.X.Scale >= 1 and node.Size.Y.Scale >= 1 then
					count += 1
				end
			end
			return count
		end

		verifyHarness:case("closes an open tray on a tap outside the row and never swallows that tap", {
			id = "native_parity_restore::native parity restore: RowActions outside tap::closes an open tray on a tap outside the row and never swallows that tap",
			run = function()
				local w, state = rowsWorld()
				local before = catchers(w)
				state.open.a:set("trailing")
				Verify.expect((catchers(w))):toBe(before)
				press(w, 150, 400, "MouseButton1", true)
				Verify.expect((state.open.a:peek())):toBeNil()
				find(w.screen, "Outside").Activated.fire()
				Verify.expect(state.outside):toBe(1)
				Verify.expect(#state.fired):toBe(0)
				state.open.a:set("trailing")
				press(w, 150, 400, "Touch")
				Verify.expect((state.open.a:peek())):toBeNil()
				w.stop()
			end,
		})

		verifyHarness:case("closes the open row when another row is pressed and keeps it open for a press inside it", {
			id = "native_parity_restore::native parity restore: RowActions outside tap::closes the open row when another row is pressed and keeps it open for a press inside it",
			run = function()
				local w, state = rowsWorld()
				state.open.a:set("trailing")
				press(w, 280, 20)
				Verify.expect((state.open.a:peek())):toBe("trailing")
				press(w, 100, 60)
				Verify.expect((state.open.a:peek())):toBeNil()
				Verify.expect((state.open.b:peek())):toBeNil()
				w.stop()
			end,
		})

		verifyHarness:case("ignores a press while no tray is open, a keyboard press and a secondary button", {
			id = "native_parity_restore::native parity restore: RowActions outside tap::ignores a press while no tray is open, a keyboard press and a secondary button",
			run = function()
				local requests: { any } = {}
				local w, state = rowsWorld({
					onOpenChange = function(edge)
						table.insert(requests, edge or "closed")
					end,
				})
				press(w, 150, 400)
				Verify.expect(#requests):toBe(0)
				state.open.a:set("trailing")
				press(w, 150, 400, "Keyboard")
				press(w, 150, 400, "MouseButton2")
				Verify.expect(#requests):toBe(0)
				press(w, 150, 400)
				Verify.expect(requests):toEqual({ "closed" })
				Verify.expect((state.open.a:peek())):toBe("trailing")
				w.stop()
			end,
		})

		verifyHarness:case("lets a commit in flight finish once when an outside tap arrives", {
			id = "native_parity_restore::native parity restore: RowActions outside tap::lets a commit in flight finish once when an outside tap arrives",
			run = function()
				local w, state = rowsWorld({ role = "destructive" :: "destructive", motionLevel = "normal" })
				state.open.a:set("trailing")
				w.engine.heartbeat.fire(0.3)
				find(find(w.screen, "a"), "Delete").Activated.fire()
				Verify.expect(state.fired):toEqual({})
				press(w, 150, 400)
				find(w.screen, "Outside").Activated.fire()
				Verify.expect(state.outside):toBe(1)
				w.engine.heartbeat.fire(0.3)
				Verify.expect(state.fired):toEqual({ "a" })
				w.stop()
			end,
		})

		verifyHarness:case("adds the top bar inset when the screen ignores it", {
			id = "native_parity_restore::native parity restore: RowActions outside tap::adds the top bar inset when the screen ignores it",
			run = function()
				local w, state = rowsWorld()
				w.screen.IgnoreGuiInset = true
				w.gui.GetGuiInset = function()
					return w.engine.types.Vector2.new(0, 58), w.engine.types.Vector2.zero
				end
				local a = find(w.screen, "a")
				a.AbsolutePosition = w.engine.types.Vector2.new(0, 58)
				state.open.a:set("trailing")
				press(w, 280, 10)
				Verify.expect((state.open.a:peek())):toBe("trailing")
				press(w, 100, 60)
				Verify.expect((state.open.a:peek())):toBeNil()
				w.stop()
			end,
		})

		verifyHarness:case("releases its input listener with the row", {
			id = "native_parity_restore::native parity restore: RowActions outside tap::releases its input listener with the row",
			run = function()
				local w, state = rowsWorld()
				local before = w.input.InputBegan.count()
				state.open.a:set("trailing")
				Verify.expect((w.input.InputBegan.count())):toBe(before + 1)
				state.open.a:set(nil)
				Verify.expect((w.input.InputBegan.count())):toBe(before)
				state.open.a:set("trailing")
				w.stop()
				Verify.expect((w.input.InputBegan.count())):toBe(0)
			end,
		})
	end)

	verifyHarness:suite("native parity restore: Label text fit and middle truncation", function()
		local ELLIPSIS = "\u{2026}"
		local VALUE = "Coastal circuit reverse night lap 14"
		local measures = 0
		local function glyphWidth(text: string, size: number): number
			return (utf8.len(text) or #text) * size * 0.5
		end
		local function measure(node: any): any
			measures += 1
			return Roblox.Vector2.new(glyphWidth(node.Text, node.TextSize), node.TextSize)
		end
		local function labelWorld(spec: { [any]: any }, options: { [string]: any }?): (World, any)
			local w = world(function(UI: FacetControls)
				return UI.Text(spec)
			end, options, { measureText = measure })
			local label = w.screen:FindFirstChildWhichIsA("TextLabel", true)
			return w, label
		end
		local function resize(w: World, label: any, width: number)
			label.AbsoluteSize = w.engine.types.Vector2.new(width, 20)
		end

		verifyHarness:case("keeps the head and the tail and fits the width at three widths", {
			id = "native_parity_restore::native parity restore: Label text fit and middle truncation::keeps the head and the tail and fits the width at three widths",
			run = function()
				for _, width in { 60, 120, 200 } do
					local w, label = labelWorld({ text = VALUE, truncate = "middle" :: "middle", TextSize = 16 })
					resize(w, label, width)
					local painted = label.Text
					Verify.expect(glyphWidth(painted, label.TextSize) <= width):toBe(true)
					Verify.expect(glyphWidth(painted, label.TextSize) + label.TextSize * 0.5 > width):toBe(true)
					Verify.expect(string.find(painted, ELLIPSIS, 1, true) ~= nil):toBe(true)
					Verify.expect((string.sub(painted, 1, 1))):toBe("C")
					Verify.expect((string.sub(painted, -2))):toBe("14")
					w.stop()
				end
			end,
		})

		verifyHarness:case("clamps wrapped text to a number of lines and ends it with an ellipsis", {
			id = "native_parity_restore::native parity restore: Label text fit and middle truncation::clamps wrapped text to a number of lines and ends it with an ellipsis",
			run = function()
				local w, label = labelWorld({ text = string.rep("word ", 60), lines = 2, TextSize = 16 })
				Verify.expect(label.TextWrapped):toBe(true)
				Verify.expect(label.TextTruncate):toBe(w.engine.types.Enum.TextTruncate.AtEnd)
				Verify.expect(label.AutomaticSize):toBe(w.engine.types.Enum.AutomaticSize.Y)
				local clamp = label:FindFirstChild("LineClamp")
				Verify.expect(clamp.MaxSize.Y):toBe(math.ceil(2 * 16 * label.LineHeight))
				label.TextSize = 20
				Verify.expect(clamp.MaxSize.Y):toBe(math.ceil(2 * 20 * label.LineHeight))
				w.stop()
				Verify.expect((pcall(labelWorld, { text = "x", lines = 0 }))):toBe(false)
				Verify.expect((pcall(labelWorld, { text = "x", lines = 2, truncate = "middle" }))):toBe(false)
			end,
		})

		verifyHarness:case("forwards rich text and refuses a non-boolean flag or a middle cut", {
			id = "native_parity_restore::native parity restore: Label text fit and middle truncation::forwards rich text and refuses a non-boolean flag or a middle cut",
			run = function()
				local w, label = labelWorld({ text = "<b>Win</b>", rich = true })
				Verify.expect(label.RichText):toBe(true)
				Verify.expect(label.Text):toBe("<b>Win</b>")
				w.stop()
				Verify.expect((Facet.richText.escape(`<b>Ann & "Bo"'s</b>`)))
					:toBe("&lt;b&gt;Ann &amp; &quot;Bo&quot;&apos;s&lt;/b&gt;")
				Verify.expect((Facet.richText.escape("plain words"))):toBe("plain words")
				Verify.expect((table.isfrozen(Facet.richText))):toBe(true)
				Verify.expect((pcall(labelWorld, { text = "x", rich = "yes" }))):toBe(false)
				Verify.expect((pcall(labelWorld, { text = "x", rich = true, truncate = "middle" }))):toBe(false)
			end,
		})

		verifyHarness:case("cuts the middle to the padded text area, not the outer box", {
			id = "native_parity_restore::native parity restore: Label text fit and middle truncation::cuts the middle to the padded text area, not the outer box",
			run = function()
				local w = world(function(UI: FacetControls, Host: RobloxHost, engine)
					return UI.Text {
						text = VALUE,
						truncate = "middle" :: "middle",
						TextSize = 16,
						Host.UIPadding {
							PaddingLeft = engine.types.UDim.new(0, 20),
							PaddingRight = engine.types.UDim.new(0, 20),
						},
					}
				end, nil, { measureText = measure })
				local label = w.screen:FindFirstChildWhichIsA("TextLabel", true)
				resize(w, label, 120)
				local painted = label.Text
				Verify.expect(glyphWidth(painted, label.TextSize) <= 80):toBe(true)
				Verify.expect(string.find(painted, ELLIPSIS, 1, true) ~= nil):toBe(true)
				label:FindFirstChildWhichIsA("UIPadding"):Destroy()
				Verify.expect(glyphWidth(label.Text, label.TextSize) > 80):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("paints the whole value when it fits and the bare mark when nothing fits", {
			id = "native_parity_restore::native parity restore: Label text fit and middle truncation::paints the whole value when it fits and the bare mark when nothing fits",
			run = function()
				local w, label = labelWorld({ text = "Lap 3", truncate = "middle" })
				resize(w, label, 400)
				Verify.expect(label.Text):toBe("Lap 3")
				resize(w, label, 1)
				Verify.expect(label.Text):toBe(ELLIPSIS)
				resize(w, label, 0)
				Verify.expect(label.Text):toBe("Lap 3")
				w.stop()
			end,
		})

		verifyHarness:case("never cuts inside a multi-byte character", {
			id = "native_parity_restore::native parity restore: Label text fit and middle truncation::never cuts inside a multi-byte character",
			run = function()
				local w, label = labelWorld({ text = "Piloté circuit côtier — réservé", truncate = "middle" })
				for width = 20, 200, 7 do
					resize(w, label, width)
					Verify.expect(utf8.len(label.Text) ~= nil):toBe(true)
				end
				w.stop()
			end,
		})

		verifyHarness:case("recomputes on a width or text change and on nothing else, and restores the whole value", {
			id = "native_parity_restore::native parity restore: Label text fit and middle truncation::recomputes on a width or text change and on nothing else, and restores the whole value",
			run = function()
				local value = Compose.cell(VALUE)
				local order = Compose.cell(1)
				local w, label = labelWorld({ text = value, truncate = "middle" :: "middle", LayoutOrder = order })
				resize(w, label, 120)
				local narrow = label.Text
				local before = measures
				order:set(2)
				Verify.expect(measures):toBe(before)
				Verify.expect(label.Text):toBe(narrow)
				resize(w, label, 240)
				Verify.expect(measures > before):toBe(true)
				Verify.expect(label.Text ~= narrow):toBe(true)
				value:set("Harbor loop 9")
				Verify.expect(label.Text):toBe("Harbor loop 9")
				value:set(VALUE)
				resize(w, label, 600)
				Verify.expect(label.Text):toBe(VALUE)
				w.stop()
			end,
		})

		verifyHarness:case("re-derives the cut when the painted size changes", {
			id = "native_parity_restore::native parity restore: Label text fit and middle truncation::re-derives the cut when the painted size changes",
			run = function()
				local size = Compose.cell(16)
				local w, label = labelWorld({ text = VALUE, truncate = "middle" :: "middle", TextSize = size })
				resize(w, label, 160)
				local at16 = label.Text
				size:set(8)
				Verify.expect(label.Text ~= at16):toBe(true)
				Verify.expect(glyphWidth(label.Text, 8) <= 160):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("stays on one line and refuses rich text, wrapping and an unknown truncation", {
			id = "native_parity_restore::native parity restore: Label text fit and middle truncation::stays on one line and refuses rich text, wrapping and an unknown truncation",
			run = function()
				local w, label = labelWorld({ text = VALUE, truncate = "middle" })
				Verify.expect(label.TextWrapped):toBe(false)
				Verify.expect(label.AutomaticSize):toBe(w.engine.types.Enum.AutomaticSize.Y)
				Verify.expect(label.Size.X.Scale):toBe(1)
				w.stop()
				local endWorld, ended = labelWorld({ text = VALUE, truncate = "end" })
				Verify.expect(ended.TextTruncate):toBe(endWorld.engine.types.Enum.TextTruncate.AtEnd)
				for _, spec in
					{
						{ text = "<b>x</b>", truncate = "middle" :: "middle", RichText = true },
						{ text = VALUE, truncate = "middle" :: "middle", TextWrapped = true },
						{ text = VALUE, truncate = "centre" },
					} :: { any }
				do
					local ok = pcall(function()
						labelWorld(spec)
					end)
					Verify.expect(ok):toBe(false)
				end
			end,
		})

		verifyHarness:case("fits the text to its box between the role size and the caption floor", {
			id = "native_parity_restore::native parity restore: Label text fit and middle truncation::fits the text to its box between the role size and the caption floor",
			run = function()
				local w, label = labelWorld({ text = "Go", textSize = "fit" })
				Verify.expect(label.TextScaled):toBe(true)
				Verify.expect(label.AutomaticSize):toBe(w.engine.types.Enum.AutomaticSize.None)
				local constraint = label:FindFirstChildWhichIsA("UITextSizeConstraint")
				Verify.expect(constraint.MaxTextSize):toBe(16)
				Verify.expect(constraint.MinTextSize):toBe(12)
				w.stop()
				local _, titled = labelWorld({ text = "Go", textRole = "title" :: "title", textSize = "fit" })
				Verify.expect(titled:FindFirstChildWhichIsA("UITextSizeConstraint").MaxTextSize):toBe(24)
			end,
		})

		verifyHarness:case("honors an explicit cap and floor by role or pixels and follows the theme", {
			id = "native_parity_restore::native parity restore: Label text fit and middle truncation::honors an explicit cap and floor by role or pixels and follows the theme",
			run = function()
				local theme = Compose.cell(Facet.themes.neutralPackage())
				local w, label = labelWorld({ text = "Go", textSize = { fit = { cap = "title", floor = 10 } } }, {
					theme = theme,
				})
				local constraint = label:FindFirstChildWhichIsA("UITextSizeConstraint")
				Verify.expect(constraint.MaxTextSize):toBe(24)
				Verify.expect(constraint.MinTextSize):toBe(10)
				local larger = Facet.themes.neutralPackage()
				larger.metrics.typography.title.size = 30
				theme:set(larger)
				Verify.expect(constraint.MaxTextSize):toBe(30)
				w.stop()
				local _, pixels = labelWorld({ text = "Go", textSize = { fit = { cap = 40 } } })
				Verify.expect(pixels:FindFirstChildWhichIsA("UITextSizeConstraint").MaxTextSize):toBe(40)
				Verify.expect(pixels:FindFirstChildWhichIsA("UITextSizeConstraint").MinTextSize):toBe(12)
			end,
		})

		verifyHarness:case("refuses a misspelled fit option, a cap that is not a size and an unknown size", {
			id = "native_parity_restore::native parity restore: Label text fit and middle truncation::refuses a misspelled fit option, a cap that is not a size and an unknown size",
			run = function()
				for _, textSize in { { fit = { max = 24 } }, { fit = { cap = true } }, -1, "huge" } :: { any } do
					local ok, message = pcall(function()
						labelWorld({ text = "x", textSize = textSize })
					end)
					Verify.expect(ok):toBe(false)
					if type(textSize) == "table" and textSize.fit.max then
						Verify.expect(string.find(tostring(message), "cap and floor", 1, true) ~= nil):toBe(true)
					end
				end
			end,
		})
	end)

	verifyHarness:suite("native parity restore: Path", function()
		local shapes = Facet.pathShapes

		verifyHarness:case("strokes pathShapes points on a native Path2D and follows new points without a remount", {
			id = "native_parity_restore::native parity restore: Path::strokes pathShapes points on a native Path2D and follows new points without a remount",
			run = function()
				local points = Compose.cell(shapes.arc(0, 90))
				local w = world(function(UI: FacetControls)
					return UI.Path "Gauge" { points = points, width = 64 }
				end)
				local frame = w.screen:FindFirstChild("Gauge")
				local stroke = frame:FindFirstChild("Stroke")
				Verify.expect(stroke.ClassName):toBe("Path2D")
				Verify.expect(frame.Size):toBe(w.engine.types.UDim2.fromOffset(64, 64))
				local first = shapes.arc(0, 90)
				Verify.expect(#stroke:GetControlPoints()):toBe(#first)
				local top = stroke:GetControlPoints()[1].Position
				Verify.expect(top):toBe(w.engine.types.UDim2.fromScale(first[1].x, first[1].y))
				points:set(shapes.needle(90, { innerRadius = 0.2 }))
				Verify.expect(#stroke:GetControlPoints()):toBe(2)
				Verify.expect((frame:FindFirstChild("Stroke"))):toBe(stroke)
				w.stop()
			end,
		})

		verifyHarness:case("takes its colour from a theme role or a tint, and its thickness from pixels or a metric", {
			id = "native_parity_restore::native parity restore: Path::takes its colour from a theme role or a tint, and its thickness from pixels or a metric",
			run = function()
				local role = Compose.cell("accent" :: "accent" | "content" | "secondary")
				local w = world(function(UI: FacetControls, Host: RobloxHost, engine)
					return Host.Frame {
						UI.Path "Role" { points = shapes.ring(), role = role, thickness = 3, closed = true } :: unknown,
						UI.Path "Plain" { points = shapes.ring() },
						UI.Path "Tinted" {
							points = shapes.ring(),
							tint = engine.types.Color3.fromRGB(10, 200, 30),
							thickness = "strokes.hairline",
						},
					}
				end)
				local roleStroke = w.screen:FindFirstChild("Role", true):FindFirstChild("Stroke")
				Verify.expect((roleStroke:HasTag("facet-path"))):toBe(true)
				Verify.expect((roleStroke:HasTag("facet-path-accent"))):toBe(true)
				Verify.expect(roleStroke.Thickness):toBe(3)
				Verify.expect(roleStroke.Closed):toBe(true)
				role:set("secondary")
				Verify.expect((roleStroke:HasTag("facet-path-accent"))):toBe(false)
				Verify.expect((roleStroke:HasTag("facet-path-secondary"))):toBe(true)
				local plain = w.screen:FindFirstChild("Plain", true):FindFirstChild("Stroke")
				Verify.expect((plain:HasTag("facet-path-content"))):toBe(true)
				Verify.expect(plain.Closed):toBe(false)
				local tinted = w.screen:FindFirstChild("Tinted", true):FindFirstChild("Stroke")
				Verify.expect(tinted.Color3):toBe(w.engine.types.Color3.fromRGB(10, 200, 30))
				Verify.expect(tinted.Thickness > 0):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("refuses missing points, more than the engine's 100 points and an unknown role", {
			id = "native_parity_restore::native parity restore: Path::refuses missing points, more than the engine's 100 points and an unknown role",
			run = function()
				Verify.expect((pcall(world, function(UI: FacetControls)
					return UI.Path({} :: any)
				end))):toBe(false)
				Verify.expect((pcall(world, function(UI: FacetControls)
					return UI.Path { points = shapes.arc(0, 360, { segments = 99 }), role = "danger" :: any }
				end))):toBe(false)
				Verify.expect((pcall(shapes.arc, 0, 360, { segments = 100 }))):toBe(false)
				Verify.expect(shapes.MAX_CONTROL_POINTS):toBe(100)
				Verify.expect((table.isfrozen(shapes))):toBe(true)
			end,
		})
	end)
end
