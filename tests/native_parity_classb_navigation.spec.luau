--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose
local themes = Facet.themes

type World = {
	engine: any,
	runtime: any,
	gui: any,
	input: any,
	inputParent: any,
	screen: any,
	stop: () -> (),
}

local function setup(build: (any, any, any) -> any, options: { [string]: any }?): World
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	input.IsKeyDown = function()
		return false
	end
	local inputParent = engine.new("Folder")
	local config: { [string]: any } = {
		types = engine.types,
		guiService = gui,
		inputParent = inputParent,
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
		gui = gui,
		input = input,
		inputParent = inputParent,
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

local function tagged(root: any, tag: string): { any }
	local out = {}
	for _, node in root:GetDescendants() do
		if node:HasTag(tag) then
			table.insert(out, node)
		end
	end
	return out
end

local function within(node: any, ancestor: any): boolean
	while node do
		if node == ancestor then
			return true
		end
		node = node.Parent
	end
	return false
end

local function sheetFor(engine: any, runtime: any, package: any): (any, () -> ())
	local stop, sheet = runtime.mount(function()
		return themes.createStyleSheet(runtime, package, { types = engine.types, reducedMotion = true } :: any)
	end, engine.new("Folder"))
	return sheet, stop
end

local function rule(sheet: any, selector: string): { [string]: any }?
	local found
	for _, node in sheet:GetChildren() do
		if node.Selector == selector then
			found = node
		end
	end
	return if found then found:GetProperties() else nil
end

local function priority(sheet: any, selector: string): number
	local best = -math.huge
	for _, node in sheet:GetChildren() do
		if node.Selector == selector then
			best = math.max(best, node.Priority)
		end
	end
	return best
end

local function radiusPackage(control: number): any
	return assert(themes.define({
		identity = { id = `classb-radius-{control}` },
		metrics = { radii = { control = control, panel = 12, pill = 999 } },
	} :: any))
end

local function skinnedPackage(): any
	local package = themes.neutralPackage()
	package.assets = package.assets or {}
	package.assets.controlArt = { content = "rbxassetid://7" }
	package.chrome.control = { kind = "nineSlice", asset = "controlArt" }
	return package
end

t.describe("native parity classb navigation", function()
	t.it("mounts a nameplate in a BillboardGui and updates its health text in place", function()
		local health = Compose.cell("100")
		local billboard
		local world = setup(function(UI, Host, engine)
			billboard = Host.BillboardGui({
				Name = "Nameplate",
				Size = engine.types.UDim2.fromOffset(300, 96),
				UI.VStack("Plate")({
					padding = 8,
					gap = 4,
					width = "fill",
					UI.Text("Name")({ text = "Razz Raccoon", TextSize = 18 }),
					UI.Text("Health")({ text = health, TextSize = 14 }),
				}),
			})
			return billboard
		end)
		t.expect(billboard.ClassName).toBe("BillboardGui")
		local plate = find(billboard, "Plate")
		local padding = plate:FindFirstChildWhichIsA("UIPadding")
		t.expect(padding.PaddingLeft.Offset).toBe(8)
		t.expect(padding.PaddingTop.Offset).toBe(8)
		t.expect(padding.PaddingRight.Offset).toBe(8)
		t.expect(plate:FindFirstChildWhichIsA("UIListLayout").Padding.Offset).toBe(4)
		local label = find(plate, "Health")
		t.expect(label.Text).toBe("100")
		t.expect(find(plate, "Name").LayoutOrder < label.LayoutOrder).toBe(true)
		local made = #world.engine.made
		health:set("87")
		t.expect(label.Text).toBe("87")
		t.expect(find(plate, "Health")).toBe(label)
		t.expect(#world.engine.made).toBe(made)
		world.stop()
	end)

	t.it("insets the segment corner by the 3 pixel inset of the track for square, rounded and round themes", function()
		for _, control in { 0, 8, 999 } do
			local world = setup(function()
				return nil
			end)
			local sheet, stop = sheetFor(world.engine, world.runtime, radiusPackage(control))
			local track = rule(sheet, ".facet-segmented::UICorner")
			local fill = rule(sheet, ".facet-segment::UICorner")
			t.expect(track and track.CornerRadius.Offset).toBe(control + 2)
			t.expect(fill and fill.CornerRadius.Offset).toBe(math.max(0, control + 2 - 3))
			local padding = rule(sheet, ".facet-segmented::UIPadding")
			t.expect(padding and padding.PaddingTop.Offset).toBe(3)
			stop()
			world.stop()
		end
	end)

	t.it("gives the segments of a pill strip a capsule corner and of a square strip a square corner", function()
		for _, corners in { "pill", "square" } do
			local world = setup(function(UI)
				return UI.Picker({
					selected = Compose.cell("a"),
					style = "segmented",
					corners = corners,
					options = { { value = "a", label = "One" }, { value = "b", label = "Two" } },
				})
			end)
			local strip = tagged(world.screen, "facet-segmented")[1]
			t.expect(strip:HasTag("facet-segmented-" .. corners)).toBe(true)
			t.expect(find(strip, "Corners").CornerRadius.Scale).toBe(if corners == "pill" then 1 else 0)
			local sheet, stop = sheetFor(world.engine, world.runtime, radiusPackage(8))
			local inner = rule(sheet, ".facet-segmented-" .. corners .. " >> .facet-segment::UICorner")
			t.expect(inner and inner.CornerRadius.Scale).toBe(if corners == "pill" then 1 else 0)
			t.expect(inner and inner.CornerRadius.Offset).toBe(0)
			t.expect(
				priority(sheet, ".facet-segmented-" .. corners .. " >> .facet-segment::UICorner")
					> priority(sheet, ".facet-segment::UICorner")
			).toBe(true)
			stop()
			world.stop()
		end
		local plain = setup(function(UI)
			return UI.Picker({
				selected = Compose.cell("a"),
				style = "segmented",
				options = { { value = "a", label = "One" }, { value = "b", label = "Two" } },
			})
		end)
		local strip = tagged(plain.screen, "facet-segmented")[1]
		t.expect(strip:HasTag("facet-segmented-pill") or strip:HasTag("facet-segmented-square")).toBe(false)
		plain.stop()
	end)

	t.it("keeps the accent plate and hides the control art under the current segment of a skinned theme", function()
		local package = skinnedPackage()
		local world = setup(function(UI)
			return UI.Picker({
				selected = Compose.cell("full"),
				style = "segmented",
				options = { { value = "full", label = "Full" }, { value = "reduced", label = "Reduced" } },
			})
		end, { theme = package })
		local current = tagged(world.screen, "facet-segment-current")
		t.expect(#current).toBe(1)
		t.expect(current[1]:HasTag("facet-skinned")).toBe(true)
		t.expect(current[1]:FindFirstChild("SkinBoundary") ~= nil).toBe(true)
		local sheet, stop = sheetFor(world.engine, world.runtime, package)
		local plate = rule(sheet, ".facet-segment-current.facet-skinned")
		t.expect(plate and plate.BackgroundTransparency).toBe(0)
		t.expect(priority(sheet, ".facet-segment-current.facet-skinned") > priority(sheet, ".facet-skinned")).toBe(true)
		local art = rule(sheet, ".facet-segment-current > #SkinBoundary")
		t.expect(art and art.Visible).toBe(false)
		local accent = rule(sheet, ".facet-segment-current")
		local ink = rule(sheet, ".facet-segment-current >> .facet-button-caption")
		t.expect(accent and accent.BackgroundTransparency).toBe(0)
		t.expect(ink and ink.TextColor3).toEqual(accent and accent.TextColor3)
		stop()
		world.stop()
	end)

	t.it("parents the underline to the chosen option in whichever home the strip mounts", function()
		local atTop, selected = Compose.cell(true), Compose.cell("a")
		local world = setup(function(UI, Host)
			local function strip()
				return UI.Picker("Strip")({
					selected = selected,
					style = "inline",
					indicator = "underline",
					axis = "x",
					options = { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } },
				})
			end
			return Host.Frame({
				Host.Frame({ Name = "Top", Compose.show(atTop, strip) }),
				Host.Frame({
					Name = "Bottom",
					Compose.show(function(use)
						return not use(atTop)
					end, strip),
				}),
			})
		end)
		local function underline(): any
			local found = {}
			for _, node in world.screen:GetDescendants() do
				if node.Name == "SelectionIndicator" then
					table.insert(found, node)
				end
			end
			t.expect(#found).toBe(1)
			return found[1]
		end
		local top = find(world.screen, "Top")
		local bottom = find(world.screen, "Bottom")
		local first = underline()
		t.expect(first.Parent.Name).toBe("a")
		t.expect(within(first, top)).toBe(true)
		atTop:set(false)
		t.expect(find(top, "Strip")).toBeNil()
		local moved = underline()
		t.expect(within(moved, bottom)).toBe(true)
		t.expect(moved.Parent.Name).toBe("a")
		t.expect(moved.Size.X.Scale).toBe(1)
		selected:set("b")
		local after = underline()
		t.expect(within(after, bottom)).toBe(true)
		t.expect(after.Parent.Name).toBe("b")
		world.stop()
	end)

	t.it("reorders customized tabs by moving the same buttons without rebuilding the page", function()
		local order, builds = Compose.cell({ "home", "feed", "me" }), 0
		local world = setup(function(UI)
			return UI.TabView({
				selection = Compose.cell("home"),
				placement = "bottomBar",
				customization = function(use)
					return { order = use(order) }
				end,
				tabs = {
					{
						id = "home",
						label = "Home",
						content = function()
							builds += 1
							return UI.Button("First")({ label = "First" })
						end,
					},
					{
						id = "feed",
						label = "Feed",
						content = function()
							return UI.Text({ text = "Feed" })
						end,
					},
					{
						id = "me",
						label = "Me",
						content = function()
							return UI.Text({ text = "Me" })
						end,
					},
				},
			})
		end)
		local strip = find(world.screen, "Tabs")
		local buttons = {
			home = strip:FindFirstChild("home"),
			feed = strip:FindFirstChild("feed"),
			me = strip:FindFirstChild("me"),
		}
		local first = find(world.screen, "First")
		t.expect(buttons.home.LayoutOrder < buttons.me.LayoutOrder).toBe(true)
		order:set({ "me", "feed", "home" })
		t.expect(strip:FindFirstChild("home")).toBe(buttons.home)
		t.expect(strip:FindFirstChild("me")).toBe(buttons.me)
		t.expect(buttons.me.LayoutOrder < buttons.feed.LayoutOrder).toBe(true)
		t.expect(buttons.feed.LayoutOrder < buttons.home.LayoutOrder).toBe(true)
		t.expect(find(world.screen, "First")).toBe(first)
		t.expect(builds).toBe(1)
		world.stop()
	end)

	t.it("lets Tab walk both nested tab strips and the page in one open order without a trap", function()
		local outerSelection, innerSelection = Compose.cell("discover"), Compose.cell("foryou")
		local world = setup(function(UI)
			return UI.TabView("App")({
				selection = outerSelection,
				placement = "bottomBar",
				tabs = {
					{
						id = "discover",
						label = "Discover",
						content = function()
							return UI.TabView("Inner")({
								selection = innerSelection,
								tabs = {
									{
										id = "foryou",
										label = "For you",
										content = function()
											return UI.Button("Play")({ label = "Play" })
										end,
									},
									{
										id = "charts",
										label = "Charts",
										content = function()
											return UI.Text({ text = "Charts" })
										end,
									},
								},
							})
						end,
					},
					{
						id = "me",
						label = "Me",
						content = function()
							return UI.Text({ text = "Me" })
						end,
					},
				},
			})
		end)
		local app = find(world.screen, "App")
		local inner = find(world.screen, "Inner")
		local outerStrip = app:FindFirstChild("Tabs")
		local innerStrip = inner:FindFirstChild("Tabs")
		t.expect(outerStrip.Position.Y.Scale).toBe(1)
		t.expect(innerStrip.Position.Y.Scale).toBe(0)
		local traverse
		for _, node in world.inputParent:GetDescendants() do
			if node.Name == "Traverse" then
				traverse = node
			end
		end
		local visited = {}
		for _ = 1, 12 do
			traverse.Pressed.fire()
			local selected = world.gui.SelectedObject
			local label = if within(selected, innerStrip)
				then "inner:" .. selected.Name
				elseif within(selected, outerStrip) then "outer:" .. selected.Name
				else "page:" .. selected.Name
			if visited[1] == label then
				break
			end
			table.insert(visited, label)
		end
		table.sort(visited)
		t.expect(visited).toEqual({ "inner:charts", "inner:foryou", "outer:discover", "outer:me", "page:Play" })
		local innerAt, pageAt = nil, nil
		world.gui.SelectedObject = nil
		for index = 1, 5 do
			traverse.Pressed.fire()
			local selected = world.gui.SelectedObject
			if within(selected, innerStrip) and innerAt == nil then
				innerAt = index
			elseif selected.Name == "Play" then
				pageAt = index
			end
		end
		t.expect(innerAt ~= nil and pageAt ~= nil and innerAt < pageAt).toBe(true)
		for _, node in { app, inner, outerStrip, innerStrip } do
			t.expect(
				node.SelectionGroup == true
					and node.SelectionBehaviorUp == world.engine.types.Enum.SelectionBehavior.Stop
			)
				.toBe(false)
			t.expect(node:GetAttribute("FacetSelectionOwner")).toBeNil()
		end
		world.stop()
	end)

	t.it("paints the ring fill above its track by explicit Path2D ZIndex", function()
		local world = setup(function(UI)
			return UI.ProgressView({ presentation = "circular", value = Compose.cell(0.5) })
		end)
		local track = find(world.screen, "RingTrack")
		local fill = find(world.screen, "RingFill")
		t.expect(track.ClassName).toBe("Path2D")
		t.expect(fill.ClassName).toBe("Path2D")
		t.expect(track.Parent).toBe(fill.Parent)
		t.expect(track.ZIndex).toBe(1)
		t.expect(fill.ZIndex).toBe(2)
		t.expect(fill.ZIndex > track.ZIndex).toBe(true)
		world.stop()
	end)

	t.it("leaves the engine selection image in place on selectable controls in every theme", function()
		local packages = { themes.neutralPackage() }
		for _, name in { "fantasy_ornate", "scifi_hud", "fantasy_parchment" } do
			table.insert(packages, ((require :: any)("../examples/themes/" .. name).build(themes)))
		end
		for _, package in packages do
			local world = setup(function(UI, Host)
				return Host.Frame({
					UI.Button({ label = "Go" }),
					UI.Toggle({ label = "Sound", value = Compose.cell(true) }),
					UI.Picker({
						selected = Compose.cell("a"),
						style = "segmented",
						options = { { value = "a", label = "A" }, { value = "b", label = "B" } },
					}),
					UI.Slider({ value = Compose.cell(0.5) }),
				})
			end, { theme = package })
			local selectable = 0
			for _, node in world.screen:GetDescendants() do
				if node:IsA("GuiObject") and node.Selectable then
					selectable += 1
					t.expect(node.SelectionImageObject).toBeNil()
				end
			end
			t.expect(selectable >= 5).toBe(true)
			world.stop()
		end
	end)
end)
