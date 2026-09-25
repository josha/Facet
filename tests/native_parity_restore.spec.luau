--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Roblox = require("@lune/roblox")
local Compose = Facet.Compose

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
	local runtime = Facet.Roblox.createRuntime(engine)
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
		reducedMotion = true,
		services = { GuiService = gui, UserInputService = input },
	}
	for key, value in (options or {}) :: { [string]: any } do
		config[key] = value
	end
	local UI = Facet.controls(runtime, config :: any)
	local Host = runtime.constructors
	local stop, screen = runtime.mount(function()
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

t.describe("native parity restore: ErrorBoundary", function()
	t.it("renders its view when healthy and does not mount the fallback", function()
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
		t.expect(boundary ~= nil).toBe(true)
		t.expect(find(boundary, "Happy") ~= nil).toBe(true)
		t.expect(find(w.screen, "Fallback")).toBeNil()
		t.expect(boundary:GetAttribute("FacetError")).toBeNil()
		w.stop()
	end)

	t.it("swaps a view that throws at mount to its fallback, reports once and keeps siblings", function()
		local reported: { string } = {}
		local w = world(function(UI, Host)
			return Host.Frame "Column" {
				Host.TextLabel "Sibling" { Text = "alive" },
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
		t.expect(find(w.screen, "Sibling") ~= nil).toBe(true)
		local fallback = find(find(w.screen, "EB"), "Fallback")
		t.expect(fallback ~= nil).toBe(true)
		t.expect(fallback.Text).toBe("factory exploded")
		t.expect(reported).toEqual({ "factory exploded" })
		t.expect(find(w.screen, "EB"):GetAttribute("FacetError")).toBe("factory exploded")
		w.stop()
	end)

	t.it("trips at runtime when a structural rebuild inside it throws, and the writer survives", function()
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
						end),
						Host.TextLabel "Content" { Text = "fine" },
					}
				end,
				fallback = function(failure)
					return Host.TextLabel "Fallback" { Text = tostring(failure) }
				end,
			}
		end)
		t.expect(find(w.screen, "Content") ~= nil).toBe(true)
		local ok = pcall(function()
			explode:set(true)
		end)
		t.expect(ok).toBe(true)
		t.expect(find(w.screen, "Content")).toBeNil()
		t.expect(find(w.screen, "Fallback").Text).toBe("branch exploded")
		t.expect(viewCleanups).toBe(1)
		local probe = Compose.cell(1)
		probe:set(2)
		t.expect(probe:peek()).toBe(2)
		w.stop()
	end)

	t.it("retries the view from the fallback and clears the reported error", function()
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
		t.expect(boundary:GetAttribute("FacetError")).toBe("not ready")
		find(boundary, "Retry").Activated.fire()
		t.expect(find(boundary, "Retry") ~= nil).toBe(true)
		broken = false
		find(boundary, "Retry").Activated.fire()
		t.expect(find(boundary, "Retry")).toBeNil()
		t.expect(find(boundary, "Ready") ~= nil).toBe(true)
		t.expect(boundary:GetAttribute("FacetError")).toBeNil()
		w.stop()
	end)

	t.it("sends a failure to the factory onError when the boundary has no onError", function()
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
		t.expect(reported).toEqual({ "unowned" })
		w.stop()
	end)

	t.it("contains a throwing keyed row factory and releases every owner on disposal", function()
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
							render = function(row)
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
		t.expect(live).toBe(2)
		rows:set({ { id = "a" }, { id = "c" } })
		t.expect(find(w.screen, "Fallback") ~= nil).toBe(true)
		t.expect(find(w.screen, "a")).toBeNil()
		t.expect(live).toBe(1)
		w.stop()
		t.expect(live).toBe(0)
	end)

	t.it("leaves a failure outside any boundary a hard mount error", function()
		local engine: any = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local Host = runtime.constructors
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
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(message), "no boundary here", 1, true) ~= nil).toBe(true)
	end)

	t.it("accepts both construction forms and refuses a boundary without a view or a fallback", function()
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
				}),
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
		t.expect(find(find(w.screen, "Healthy"), "Ok") ~= nil).toBe(true)
		t.expect(find(w.screen, "HealthyFallback")).toBeNil()
		t.expect(find(find(w.screen, "Broken"), "BrokenFallback") ~= nil).toBe(true)
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
			t.expect(refused).toBe(false)
		end
		w.stop()
	end)
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

t.describe("native parity restore: Facet Neutral Light", function()
	t.it("declares Dark then Light and both palettes pass the contrast gate", function()
		local themes = Facet.themes
		local neutral = themes.neutralPackage()
		t.expect(neutral.style.defaultTheme).toBe("Dark")
		t.expect(#neutral.style.themes).toBe(2)
		local dark, light = neutral.style.themes[1], neutral.style.themes[2]
		t.expect(dark.name).toBe("Dark")
		t.expect(light.name).toBe("Light")
		t.expect(sortedKeys(light.colors)).toEqual(sortedKeys(dark.colors))
		t.expect(sortedKeys(light.extra)).toEqual(sortedKeys(dark.extra))
		local defined, report = themes.define(neutral)
		t.expect(defined ~= nil).toBe(true)
		t.expect(report.ok).toBe(true)
		t.expect(#report.contrast).toBe(14)
		for _, result in report.contrast do
			t.expect(result.ok).toBe(true)
		end
		for _, pair in { { "content", "surface" }, { "contentStrong", "surfaceStrong" }, { "onAccent", "accent" } } do
			t.expect(ratio(light.colors[pair[1]], light.colors[pair[2]]) >= 4.5).toBe(true)
		end
		t.expect(ratio(light.colors.content, light.extra.controlSelected) >= 4.5).toBe(true)
		t.expect(ratio(light.extra.contentSecondary, light.colors.surface) >= 4.5).toBe(true)
		t.expect(ratio(light.colors.content, light.extra.control) >= 4.5).toBe(true)
		t.expect(ratio(light.colors.surface, dark.colors.surface) > 10).toBe(true)
	end)

	t.it("keeps a derived package to its own palettes and inherits only the first", function()
		local themes = Facet.themes
		local plain = assert(themes.define({
			identity = { id = "derived", displayName = "Derived", version = "1.0.0" },
		} :: any))
		t.expect(#plain.style.themes).toBe(1)
		t.expect(plain.style.themes[1].name).toBe("Dark")
		local based = assert(themes.define({
			base = themes.neutralPackage(),
			identity = { id = "based", displayName = "Based", version = "1.0.0" },
		} :: any))
		t.expect(#based.style.themes).toBe(1)
		local paired = assert(themes.define({
			identity = { id = "paired", displayName = "Paired", version = "1.0.0" },
			style = { defaultTheme = "Day", themes = { { name = "Day" }, { name = "Night" } } },
		} :: any))
		t.expect(#paired.style.themes).toBe(2)
		t.expect(#themes.neutralPackage().style.themes).toBe(2)
	end)

	t.it("paints each Neutral palette through the native sheet and follows a palette change", function()
		local themes = Facet.themes
		local engine: any = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local neutral = themes.neutralPackage()
		local selected = Compose.cell("Dark")
		local stop, sheet = runtime.mount(function()
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
		t.expect(textColor()).toBe(expected(neutral.style.themes[1]))
		selected:set("Light")
		t.expect(textColor()).toBe(expected(neutral.style.themes[2]))
		stop()
		runtime:dispose()
	end)
end)

t.describe("native parity restore: Table multi-select keys", function()
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
	local function tableWorld(mode: string?): (World, any, any)
		table.clear(held)
		local selection = Compose.cell({})
		local focus: any = {}
		local w = world(function(UI)
			return UI.Table "Racers" {
				from = racers(),
				key = "id",
				itemSize = 40,
				focus = focus,
				selection = selection,
				selectionMode = mode or "multi",
				columns = {
					{
						id = "name",
						label = "Racer",
						value = function(item)
							return item.name
						end,
					},
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
		hit(w, key).Activated.fire({ UserInputType = w.engine.types.Enum.UserInputType.MouseButton1 }, 1)
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

	t.it("replaces a multi selection on a plain mouse click", function()
		local w, selection = tableWorld()
		tap(w, "razz")
		tap(w, "bolt")
		t.expect(selected(selection)).toEqual({ "bolt", "razz" })
		click(w, "josh")
		t.expect(selected(selection)).toEqual({ "josh" })
		w.stop()
	end)

	t.it("toggles rows in and out of a multi selection on a Ctrl-click and a Cmd-click", function()
		for _, modifier in { "LeftControl", "RightControl", "LeftMeta", "RightMeta", "LeftSuper" } do
			local w, selection = tableWorld()
			click(w, "razz")
			click(w, "josh", modifier)
			t.expect(selected(selection)).toEqual({ "josh", "razz" })
			click(w, "razz", modifier)
			t.expect(selected(selection)).toEqual({ "josh" })
			w.stop()
		end
	end)

	t.it("extends a contiguous range from the anchor on a Shift-click and re-ranges from the same anchor", function()
		local w, selection = tableWorld()
		click(w, "razz")
		click(w, "josh", "LeftShift")
		t.expect(selected(selection)).toEqual({ "bolt", "josh", "razz" })
		click(w, "bolt", "RightShift")
		t.expect(selected(selection)).toEqual({ "bolt", "razz" })
		w.stop()
	end)

	t.it("selects a reversed range when a Shift-click goes from a later row to an earlier one", function()
		local w, selection = tableWorld()
		click(w, "josh")
		click(w, "razz", "LeftShift")
		t.expect(selected(selection)).toEqual({ "bolt", "josh", "razz" })
		w.stop()
	end)

	t.it("keeps Ctrl-toggled rows when a Shift-click ranges from a toggled anchor", function()
		local w, selection = tableWorld()
		click(w, "razz")
		click(w, "josh", "LeftControl")
		click(w, "nova", "LeftShift")
		t.expect(selected(selection)).toEqual({ "josh", "mint", "nova", "razz" })
		w.stop()
	end)

	t.it("drops a row that the model deselected from the base of a later Shift range", function()
		local w, selection = tableWorld()
		click(w, "razz")
		click(w, "nova", "LeftControl")
		selection:set({ nova = true })
		click(w, "mint", "LeftShift")
		t.expect(selected(selection)).toEqual({ "mint", "nova" })
		w.stop()
	end)

	t.it("keeps the additive toggle for a touch tap and a gamepad press", function()
		local w, selection = tableWorld()
		tap(w, "razz")
		tap(w, "josh")
		t.expect(selected(selection)).toEqual({ "josh", "razz" })
		local E = w.engine.types.Enum
		hit(w, "razz").Activated.fire({ UserInputType = E.UserInputType.Gamepad1, KeyCode = E.KeyCode.ButtonA }, 1)
		t.expect(selected(selection)).toEqual({ "josh" })
		w.stop()
	end)

	t.it("honors held modifiers on a keyboard Return", function()
		local w, selection = tableWorld()
		returnKey(w, "razz")
		t.expect(selected(selection)).toEqual({ "razz" })
		held.LeftControl = true
		returnKey(w, "razz")
		t.expect(selected(selection)).toEqual({})
		table.clear(held)
		returnKey(w, "bolt")
		held.LeftShift = true
		returnKey(w, "mint")
		t.expect(selected(selection)).toEqual({ "bolt", "josh", "mint" })
		w.stop()
	end)

	t.it("extends the selection from the anchor with Shift and an arrow, and moves focus with it", function()
		local w, selection, focus = tableWorld()
		focus.focus("bolt")
		t.expect(w.gui.SelectedObject).toBe(hit(w, "bolt"))
		returnKey(w, "bolt")
		t.expect(selected(selection)).toEqual({ "bolt" })
		held.LeftShift = true
		arrow(w, "Down")
		arrow(w, "Down")
		t.expect(focus.current:peek()).toBe("mint")
		t.expect(selected(selection)).toEqual({ "bolt", "josh", "mint" })
		arrow(w, "Up")
		t.expect(selected(selection)).toEqual({ "bolt", "josh" })
		arrow(w, "Up")
		arrow(w, "Up")
		t.expect(focus.current:peek()).toBe("razz")
		t.expect(selected(selection)).toEqual({ "bolt", "razz" })
		w.stop()
	end)

	t.it("extends to the first and the last row with Shift and Home or End", function()
		local w, selection, focus = tableWorld()
		focus.focus("josh")
		returnKey(w, "josh")
		held.LeftShift = true
		arrow(w, "Last")
		t.expect(focus.current:peek()).toBe("nova")
		t.expect(selected(selection)).toEqual({ "josh", "mint", "nova" })
		arrow(w, "First")
		t.expect(selected(selection)).toEqual({ "bolt", "josh", "razz" })
		w.stop()
	end)

	t.it("starts a keyboard range at the focused row when nothing anchors it", function()
		local w, selection, focus = tableWorld()
		focus.focus("josh")
		held.RightShift = true
		arrow(w, "Down")
		t.expect(selected(selection)).toEqual({ "josh", "mint" })
		w.stop()
	end)

	t.it("moves focus with Ctrl and an arrow and with a plain arrow without changing the selection", function()
		local w, selection, focus = tableWorld()
		focus.focus("razz")
		returnKey(w, "razz")
		held.LeftControl = true
		arrow(w, "Down")
		arrow(w, "Down")
		t.expect(focus.current:peek()).toBe("josh")
		t.expect(selected(selection)).toEqual({ "razz" })
		table.clear(held)
		arrow(w, "Down")
		t.expect(focus.current:peek()).toBe("mint")
		t.expect(selected(selection)).toEqual({ "razz" })
		w.stop()
	end)

	t.it("replaces in single mode whatever the modifiers and ignores a Shift-arrow", function()
		local w, selection, focus = tableWorld("single")
		click(w, "razz")
		click(w, "josh", "LeftControl")
		t.expect(selected(selection)).toEqual({ "josh" })
		click(w, "mint", "LeftShift")
		t.expect(selected(selection)).toEqual({ "mint" })
		focus.focus("mint")
		held.LeftShift = true
		arrow(w, "Down")
		t.expect(selected(selection)).toEqual({ "mint" })
		w.stop()
	end)
end)

t.describe("native parity restore: RowActions outside tap", function()
	local function rowsWorld(options: { [string]: any }?): (World, { [string]: any })
		local settings: { [string]: any } = options or {}
		local state: { [string]: any } = {
			open = { a = Compose.cell(nil), b = Compose.cell(nil) },
			coordinator = Compose.cell(nil),
			fired = {},
			outside = 0,
		}
		local w = world(function(UI, Host)
			local function row(name: string)
				return UI.RowActions({
					Name = name,
					open = state.open[name],
					onOpenChange = settings.onOpenChange,
					coordinator = state.coordinator,
					content = function()
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
						},
					},
				})
			end
			return Host.Frame "List" {
				row("a"),
				row("b"),
				Host.TextButton "Outside" {
					Text = "Outside",
					Activated = function()
						state.outside += 1
					end,
				},
			}
		end, { reducedMotion = settings.reducedMotion ~= false })
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

	t.it("closes an open tray on a tap outside the row and never swallows that tap", function()
		local w, state = rowsWorld()
		local before = catchers(w)
		state.open.a:set("trailing")
		t.expect(catchers(w)).toBe(before)
		press(w, 150, 400, "MouseButton1", true)
		t.expect(state.open.a:peek()).toBeNil()
		find(w.screen, "Outside").Activated.fire()
		t.expect(state.outside).toBe(1)
		t.expect(#state.fired).toBe(0)
		state.open.a:set("trailing")
		press(w, 150, 400, "Touch")
		t.expect(state.open.a:peek()).toBeNil()
		w.stop()
	end)

	t.it("closes the open row when another row is pressed and keeps it open for a press inside it", function()
		local w, state = rowsWorld()
		state.open.a:set("trailing")
		press(w, 280, 20)
		t.expect(state.open.a:peek()).toBe("trailing")
		press(w, 100, 60)
		t.expect(state.open.a:peek()).toBeNil()
		t.expect(state.open.b:peek()).toBeNil()
		w.stop()
	end)

	t.it("ignores a press while no tray is open, a keyboard press and a secondary button", function()
		local requests: { any } = {}
		local w, state = rowsWorld({
			onOpenChange = function(edge)
				table.insert(requests, edge or "closed")
			end,
		})
		press(w, 150, 400)
		t.expect(#requests).toBe(0)
		state.open.a:set("trailing")
		press(w, 150, 400, "Keyboard")
		press(w, 150, 400, "MouseButton2")
		t.expect(#requests).toBe(0)
		press(w, 150, 400)
		t.expect(requests).toEqual({ "closed" })
		t.expect(state.open.a:peek()).toBe("trailing")
		w.stop()
	end)

	t.it("lets a commit in flight finish once when an outside tap arrives", function()
		local w, state = rowsWorld({ role = "destructive", reducedMotion = false })
		state.open.a:set("trailing")
		w.engine.heartbeat.fire(0.3)
		find(find(w.screen, "a"), "Delete").Activated.fire()
		t.expect(state.fired).toEqual({})
		press(w, 150, 400)
		find(w.screen, "Outside").Activated.fire()
		t.expect(state.outside).toBe(1)
		w.engine.heartbeat.fire(0.3)
		t.expect(state.fired).toEqual({ "a" })
		w.stop()
	end)

	t.it("adds the top bar inset when the screen ignores it", function()
		local w, state = rowsWorld()
		w.screen.IgnoreGuiInset = true
		w.gui.GetGuiInset = function()
			return w.engine.types.Vector2.new(0, 58), w.engine.types.Vector2.zero
		end
		local a = find(w.screen, "a")
		a.AbsolutePosition = w.engine.types.Vector2.new(0, 58)
		state.open.a:set("trailing")
		press(w, 280, 10)
		t.expect(state.open.a:peek()).toBe("trailing")
		press(w, 100, 60)
		t.expect(state.open.a:peek()).toBeNil()
		w.stop()
	end)

	t.it("releases its input listener with the row", function()
		local w, state = rowsWorld()
		local before = w.input.InputBegan.count()
		state.open.a:set("trailing")
		t.expect(w.input.InputBegan.count()).toBe(before + 1)
		state.open.a:set(nil)
		t.expect(w.input.InputBegan.count()).toBe(before)
		state.open.a:set("trailing")
		w.stop()
		t.expect(w.input.InputBegan.count()).toBe(0)
	end)
end)

t.describe("native parity restore: Label text fit and middle truncation", function()
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
	local function labelWorld(spec: { [string]: any }, options: { [string]: any }?): (World, any)
		local w = world(function(UI)
			return UI.Text(spec)
		end, options, { measureText = measure })
		local label = w.screen:FindFirstChildWhichIsA("TextLabel", true)
		return w, label
	end
	local function resize(w: World, label: any, width: number)
		label.AbsoluteSize = w.engine.types.Vector2.new(width, 20)
	end

	t.it("keeps the head and the tail and fits the width at three widths", function()
		for _, width in { 60, 120, 200 } do
			local w, label = labelWorld({ text = VALUE, truncate = "middle", TextSize = 16 })
			resize(w, label, width)
			local painted = label.Text
			t.expect(glyphWidth(painted, label.TextSize) <= width).toBe(true)
			t.expect(glyphWidth(painted, label.TextSize) + label.TextSize * 0.5 > width).toBe(true)
			t.expect(string.find(painted, ELLIPSIS, 1, true) ~= nil).toBe(true)
			t.expect(string.sub(painted, 1, 1)).toBe("C")
			t.expect(string.sub(painted, -2)).toBe("14")
			w.stop()
		end
	end)

	t.it("clamps wrapped text to a number of lines and ends it with an ellipsis", function()
		local w, label = labelWorld({ text = string.rep("word ", 60), lines = 2, TextSize = 16 })
		t.expect(label.TextWrapped).toBe(true)
		t.expect(label.TextTruncate).toBe(w.engine.types.Enum.TextTruncate.AtEnd)
		t.expect(label.AutomaticSize).toBe(w.engine.types.Enum.AutomaticSize.Y)
		local clamp = label:FindFirstChild("LineClamp")
		t.expect(clamp.MaxSize.Y).toBe(math.ceil(2 * 16 * label.LineHeight))
		label.TextSize = 20
		t.expect(clamp.MaxSize.Y).toBe(math.ceil(2 * 20 * label.LineHeight))
		w.stop()
		t.expect(pcall(labelWorld, { text = "x", lines = 0 })).toBe(false)
		t.expect(pcall(labelWorld, { text = "x", lines = 2, truncate = "middle" })).toBe(false)
	end)

	t.it("forwards rich text and refuses a non-boolean flag or a middle cut", function()
		local w, label = labelWorld({ text = "<b>Win</b>", rich = true })
		t.expect(label.RichText).toBe(true)
		t.expect(label.Text).toBe("<b>Win</b>")
		w.stop()
		t.expect(Facet.richText.escape(`<b>Ann & "Bo"'s</b>`))
			.toBe("&lt;b&gt;Ann &amp; &quot;Bo&quot;&apos;s&lt;/b&gt;")
		t.expect(Facet.richText.escape("plain words")).toBe("plain words")
		t.expect(table.isfrozen(Facet.richText)).toBe(true)
		t.expect(pcall(labelWorld, { text = "x", rich = "yes" })).toBe(false)
		t.expect(pcall(labelWorld, { text = "x", rich = true, truncate = "middle" })).toBe(false)
	end)

	t.it("cuts the middle to the padded text area, not the outer box", function()
		local w = world(function(UI, Host, engine)
			return UI.Text {
				text = VALUE,
				truncate = "middle",
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
		t.expect(glyphWidth(painted, label.TextSize) <= 80).toBe(true)
		t.expect(string.find(painted, ELLIPSIS, 1, true) ~= nil).toBe(true)
		label:FindFirstChildWhichIsA("UIPadding"):Destroy()
		t.expect(glyphWidth(label.Text, label.TextSize) > 80).toBe(true)
		w.stop()
	end)

	t.it("paints the whole value when it fits and the bare mark when nothing fits", function()
		local w, label = labelWorld({ text = "Lap 3", truncate = "middle" })
		resize(w, label, 400)
		t.expect(label.Text).toBe("Lap 3")
		resize(w, label, 1)
		t.expect(label.Text).toBe(ELLIPSIS)
		resize(w, label, 0)
		t.expect(label.Text).toBe("Lap 3")
		w.stop()
	end)

	t.it("never cuts inside a multi-byte character", function()
		local w, label = labelWorld({ text = "Piloté circuit côtier — réservé", truncate = "middle" })
		for width = 20, 200, 7 do
			resize(w, label, width)
			t.expect(utf8.len(label.Text) ~= nil).toBe(true)
		end
		w.stop()
	end)

	t.it("recomputes on a width or text change and on nothing else, and restores the whole value", function()
		local value = Compose.cell(VALUE)
		local order = Compose.cell(1)
		local w, label = labelWorld({ text = value, truncate = "middle", LayoutOrder = order })
		resize(w, label, 120)
		local narrow = label.Text
		local before = measures
		order:set(2)
		t.expect(measures).toBe(before)
		t.expect(label.Text).toBe(narrow)
		resize(w, label, 240)
		t.expect(measures > before).toBe(true)
		t.expect(label.Text ~= narrow).toBe(true)
		value:set("Harbor loop 9")
		t.expect(label.Text).toBe("Harbor loop 9")
		value:set(VALUE)
		resize(w, label, 600)
		t.expect(label.Text).toBe(VALUE)
		w.stop()
	end)

	t.it("re-derives the cut when the painted size changes", function()
		local size = Compose.cell(16)
		local w, label = labelWorld({ text = VALUE, truncate = "middle", TextSize = size })
		resize(w, label, 160)
		local at16 = label.Text
		size:set(8)
		t.expect(label.Text ~= at16).toBe(true)
		t.expect(glyphWidth(label.Text, 8) <= 160).toBe(true)
		w.stop()
	end)

	t.it("stays on one line and refuses rich text, wrapping and an unknown truncation", function()
		local w, label = labelWorld({ text = VALUE, truncate = "middle" })
		t.expect(label.TextWrapped).toBe(false)
		t.expect(label.AutomaticSize).toBe(w.engine.types.Enum.AutomaticSize.Y)
		t.expect(label.Size.X.Scale).toBe(1)
		w.stop()
		local endWorld, ended = labelWorld({ text = VALUE, truncate = "end" })
		t.expect(ended.TextTruncate).toBe(endWorld.engine.types.Enum.TextTruncate.AtEnd)
		for _, spec in
			{
				{ text = "<b>x</b>", truncate = "middle", RichText = true },
				{ text = VALUE, truncate = "middle", TextWrapped = true },
				{ text = VALUE, truncate = "centre" },
			} :: { any }
		do
			local ok = pcall(function()
				labelWorld(spec)
			end)
			t.expect(ok).toBe(false)
		end
	end)

	t.it("fits the text to its box between the role size and the caption floor", function()
		local w, label = labelWorld({ text = "Go", textSize = "fit" })
		t.expect(label.TextScaled).toBe(true)
		t.expect(label.AutomaticSize).toBe(w.engine.types.Enum.AutomaticSize.None)
		local constraint = label:FindFirstChildWhichIsA("UITextSizeConstraint")
		t.expect(constraint.MaxTextSize).toBe(16)
		t.expect(constraint.MinTextSize).toBe(12)
		w.stop()
		local _, titled = labelWorld({ text = "Go", textRole = "title", textSize = "fit" })
		t.expect(titled:FindFirstChildWhichIsA("UITextSizeConstraint").MaxTextSize).toBe(24)
	end)

	t.it("honors an explicit cap and floor by role or pixels and follows the theme", function()
		local theme = Compose.cell(Facet.themes.neutralPackage())
		local w, label = labelWorld({ text = "Go", textSize = { fit = { cap = "title", floor = 10 } } }, {
			theme = theme,
		})
		local constraint = label:FindFirstChildWhichIsA("UITextSizeConstraint")
		t.expect(constraint.MaxTextSize).toBe(24)
		t.expect(constraint.MinTextSize).toBe(10)
		local larger = Facet.themes.neutralPackage()
		larger.metrics.typography.title.size = 30
		theme:set(larger)
		t.expect(constraint.MaxTextSize).toBe(30)
		w.stop()
		local _, pixels = labelWorld({ text = "Go", textSize = { fit = { cap = 40 } } })
		t.expect(pixels:FindFirstChildWhichIsA("UITextSizeConstraint").MaxTextSize).toBe(40)
		t.expect(pixels:FindFirstChildWhichIsA("UITextSizeConstraint").MinTextSize).toBe(12)
	end)

	t.it("refuses a misspelled fit option, a cap that is not a size and an unknown size", function()
		for _, textSize in { { fit = { max = 24 } }, { fit = { cap = true } }, -1, "huge" } :: { any } do
			local ok, message = pcall(function()
				labelWorld({ text = "x", textSize = textSize })
			end)
			t.expect(ok).toBe(false)
			if type(textSize) == "table" and textSize.fit.max then
				t.expect(string.find(tostring(message), "cap and floor", 1, true) ~= nil).toBe(true)
			end
		end
	end)
end)

t.describe("native parity restore: Path", function()
	local shapes = Facet.pathShapes

	t.it("strokes pathShapes points on a native Path2D and follows new points without a remount", function()
		local points = Compose.cell(shapes.arc(0, 90))
		local w = world(function(UI)
			return UI.Path "Gauge" { points = points, width = 64 }
		end)
		local frame = w.screen:FindFirstChild("Gauge")
		local stroke = frame:FindFirstChild("Stroke")
		t.expect(stroke.ClassName).toBe("Path2D")
		t.expect(frame.Size).toBe(w.engine.types.UDim2.fromOffset(64, 64))
		local first = shapes.arc(0, 90)
		t.expect(#stroke:GetControlPoints()).toBe(#first)
		local top = stroke:GetControlPoints()[1].Position
		t.expect(top).toBe(w.engine.types.UDim2.fromScale(first[1].x, first[1].y))
		points:set(shapes.needle(90, { innerRadius = 0.2 }))
		t.expect(#stroke:GetControlPoints()).toBe(2)
		t.expect(frame:FindFirstChild("Stroke")).toBe(stroke)
		w.stop()
	end)

	t.it("takes its colour from a theme role or a tint, and its thickness from pixels or a metric", function()
		local role = Compose.cell("accent")
		local w = world(function(UI, Host, engine)
			return Host.Frame {
				UI.Path "Role" { points = shapes.ring(), role = role, thickness = 3, closed = true },
				UI.Path "Plain" { points = shapes.ring() },
				UI.Path "Tinted" {
					points = shapes.ring(),
					tint = engine.types.Color3.fromRGB(10, 200, 30),
					thickness = "strokes.hairline",
				},
			}
		end)
		local roleStroke = w.screen:FindFirstChild("Role", true):FindFirstChild("Stroke")
		t.expect(roleStroke:HasTag("facet-path")).toBe(true)
		t.expect(roleStroke:HasTag("facet-path-accent")).toBe(true)
		t.expect(roleStroke.Thickness).toBe(3)
		t.expect(roleStroke.Closed).toBe(true)
		role:set("secondary")
		t.expect(roleStroke:HasTag("facet-path-accent")).toBe(false)
		t.expect(roleStroke:HasTag("facet-path-secondary")).toBe(true)
		local plain = w.screen:FindFirstChild("Plain", true):FindFirstChild("Stroke")
		t.expect(plain:HasTag("facet-path-content")).toBe(true)
		t.expect(plain.Closed).toBe(false)
		local tinted = w.screen:FindFirstChild("Tinted", true):FindFirstChild("Stroke")
		t.expect(tinted.Color3).toBe(w.engine.types.Color3.fromRGB(10, 200, 30))
		t.expect(tinted.Thickness > 0).toBe(true)
		w.stop()
	end)

	t.it("refuses missing points, more than the engine's 100 points and an unknown role", function()
		t.expect(pcall(world, function(UI)
			return UI.Path({} :: any)
		end)).toBe(false)
		t.expect(pcall(world, function(UI)
			return UI.Path { points = shapes.arc(0, 360, { segments = 99 }), role = "danger" :: any }
		end)).toBe(false)
		t.expect(pcall(shapes.arc, 0, 360, { segments = 100 })).toBe(false)
		t.expect(shapes.MAX_CONTROL_POINTS).toBe(100)
		t.expect(table.isfrozen(shapes)).toBe(true)
	end)
end)
