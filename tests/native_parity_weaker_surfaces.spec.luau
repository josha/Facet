--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose

type World = {
	engine: any,
	runtime: any,
	gui: any,
	input: any,
	screen: any,
	stop: () -> (),
}

local function setup(build: (any, any, any, any, any) -> any, options: { [string]: any }?): World
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
	local config: { [string]: any } = {
		types = engine.types,
		guiService = gui,
		services = { GuiService = gui, UserInputService = input },
	}
	for key, value in (options or {}) :: { [string]: any } do
		config[key] = value
	end
	local UI = Facet.controls(runtime, config :: any)
	local Host = runtime.constructors
	local stop, screen = runtime.mount(function()
		return Host.ScreenGui({ build(UI, Host, engine, gui, runtime) })
	end, engine.new("Folder"))
	return {
		engine = engine,
		runtime = runtime,
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

local function all(root: any, name: string): { any }
	local found = {}
	for _, node in root:GetDescendants() do
		if node.Name == name then
			table.insert(found, node)
		end
	end
	return found
end

local function action(root: any, name: string): any
	local winner, priority = nil, -math.huge
	for _, node in root:GetDescendants() do
		if node:IsA("InputContext") and node.Name == "Facet" .. name and node.Enabled then
			local candidate = node:FindFirstChild(name)
			if candidate and node.Priority > priority then
				winner, priority = candidate, node.Priority
			end
		end
	end
	return winner
end

local function enabledCount(root: any, name: string): number
	local count = 0
	for _, node in root:GetDescendants() do
		if node:IsA("InputContext") and node.Name == "Facet" .. name and node.Enabled then
			count += 1
		end
	end
	return count
end

local function within(node: any, ancestor: any): boolean
	local at = node
	while at do
		if at == ancestor then
			return true
		end
		at = at.Parent
	end
	return false
end

local function mountScenario(name: string, reduced: boolean?): (any, any, any, any, any, () -> ())
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local target = engine.new("Folder")
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	local ctx: any = {
		Facet = Facet,
		Compose = Compose,
		Host = runtime.constructors,
		runtime = runtime,
		types = engine.types,
		viewport = Compose.cell({ width = 1280, height = 720 }),
		guiService = gui,
		inputTarget = target,
		worldTarget = engine.new("Folder"),
		runService = { Heartbeat = engine.heartbeat },
		reducedMotion = Compose.cell(reduced == true),
		pageVisible = Compose.cell(true),
	}
	ctx.UI = Facet.controls(
		runtime,
		{
			types = engine.types,
			viewport = ctx.viewport,
			guiService = gui,
			services = { GuiService = gui, UserInputService = input },
			inputParent = target,
			reducedMotion = ctx.reducedMotion,
		} :: any
	)
	local built: any
	local stop, node = runtime.mount(function()
		built = (require :: any)("../examples/gallery/scenarios/" .. name).build(ctx)
		if built.dispose then
			Compose.cleanup(built.dispose)
		end
		return ctx.Host.ScreenGui({ built.screen() })
	end, target)
	return built, node, ctx, engine, target, function()
		stop()
		runtime:dispose()
	end
end

local function visibleTitles(built: any): string
	local rows = {}
	for _, row in built.report().rows do
		if row.state == "visible" then
			table.insert(rows, row)
		end
	end
	table.sort(rows, function(a, b)
		return a.id < b.id
	end)
	local titles = {}
	for _, row in rows do
		table.insert(titles, row.title)
	end
	return table.concat(titles, ",")
end

local function toasts(node: any): { any }
	local cards = {}
	for _, child in find(node, "Messages"):GetChildren() do
		if child.Name == "Toast" then
			table.insert(cards, child)
		end
	end
	return cards
end

local function advance(engine: any, seconds: number, step: number?)
	local size = step or 0.05
	local remaining = seconds
	while remaining > 1e-9 do
		local delta = math.min(size, remaining)
		engine.heartbeat.fire(delta)
		remaining -= delta
	end
end

local function withMonitors(body: (any) -> ())
	local modelModule: any = require("../examples/virtual_monitors/model")
	local screens: any = require("../examples/virtual_monitors/screens")
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local target = engine.new("ScreenGui")
	local gui, input = engine.new("GuiService"), engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	input.IsKeyDown = function()
		return false
	end
	local lifetime = Compose.createRootOwner(function()
		local model = modelModule.new(Compose)
		Compose.cleanup(model.dispose)
		local views = screens.create(Facet, runtime, {
			model = model,
			types = engine.types,
			services = { GuiService = gui, UserInputService = input },
			reducedMotion = true,
		})
		local world: any = { model = model, engine = engine, target = target, gui = gui, input = input }
		for _, name in { "Discover", "Avatar" } do
			local _, node = runtime.mount(views[name], target)
			world[name] = node
		end
		body(world)
	end, runtime.reactor)
	lifetime.dispose()
	t.expect(#target:GetChildren()).toBe(0)
	runtime:dispose()
end

t.describe("presented surface strength", function()
	t.it("centers a content-sized alert card under its width bound and leads the row with cancel", function()
		for _, bound in { 440, 360 } do
			local world = setup(function(UI)
				return UI.Alert({
					isPresented = Compose.cell(true),
					title = "Delete this save?",
					message = "This cannot be undone.",
					maxWidth = if bound == 440 then nil else bound,
					actions = {
						{ id = "Delete", label = "Delete save", role = "destructive" },
						{ id = "Cancel", label = "Cancel", role = "cancel" },
					},
				})
			end)
			local V2 = world.engine.types.Vector2
			find(world.screen, "AlertModal").AbsoluteSize = V2.new(1280, 800)
			local panel = find(world.screen, "AlertPanel")
			t.expect(panel.AnchorPoint).toBe(V2.new(0.5, 0.5))
			t.expect(panel.Position.X.Scale).toBe(0.5)
			t.expect(panel.Position.Y.Scale).toBe(0.5)
			t.expect(panel.Position.X.Offset).toBe(0)
			t.expect(panel.Position.Y.Offset).toBe(0)
			t.expect(panel.AutomaticSize).toBe(world.engine.types.Enum.AutomaticSize.Y)
			t.expect(panel.Size.Y.Scale).toBe(0)
			t.expect(panel.Size.Y.Offset).toBe(0)
			local constraint = panel:FindFirstChildWhichIsA("UISizeConstraint")
			t.expect(constraint ~= nil).toBe(true)
			t.expect(constraint.MaxSize.X).toBe(bound)
			t.expect(bound < 1280 - 32).toBe(true)
			local layout = find(world.screen, "Actions"):FindFirstChildWhichIsA("UIListLayout")
			t.expect(layout.FillDirection).toBe(world.engine.types.Enum.FillDirection.Horizontal)
			t.expect(find(world.screen, "Cancel").LayoutOrder).toBe(0)
			t.expect(find(world.screen, "Delete").LayoutOrder).toBe(1)
			world.stop()
		end
	end)

	t.it("stacks more than two alert actions with the likely action on top and cancel last", function()
		local world = setup(function(UI, Host, _, gui)
			local opener = UI.Button "Opener" { label = "Open" }
			gui.SelectedObject = opener
			return Host.Frame({
				opener,
				UI.Alert({
					isPresented = Compose.cell(true),
					title = "Leave the race?",
					actions = {
						{ id = "Cancel", label = "Stay", role = "cancel" },
						{ id = "Save", label = "Save and leave" },
						{ id = "Delete", label = "Leave without saving", role = "destructive" },
					},
				}),
			})
		end)
		local Enum = world.engine.types.Enum
		find(world.screen, "AlertModal").AbsoluteSize = world.engine.types.Vector2.new(1280, 800)
		t.expect(find(world.screen, "Actions"):FindFirstChildWhichIsA("UIListLayout").FillDirection)
			.toBe(Enum.FillDirection.Vertical)
		local save, delete, cancel =
			find(world.screen, "Save"), find(world.screen, "Delete"), find(world.screen, "Cancel")
		t.expect(save.LayoutOrder < delete.LayoutOrder).toBe(true)
		t.expect(delete.LayoutOrder < cancel.LayoutOrder).toBe(true)
		for _, button in { save, delete, cancel } do
			t.expect(button.Size).toBe(world.engine.types.UDim2.new(1, 0, 0, 44))
		end
		t.expect(world.gui.SelectedObject).toBe(cancel)
		world.stop()
	end)

	t.it("binds alert presentation both ways without stacking or invoking action callbacks", function()
		local shown, calls = Compose.cell(false), 0
		local world = setup(function(UI)
			return UI.Alert({
				title = "Continue?",
				isPresented = shown,
				actions = {
					{
						id = "cancel",
						label = "Cancel",
						role = "cancel",
						onActivate = function()
							calls += 1
						end,
					},
				},
			})
		end)
		t.expect(#all(world.screen, "AlertModal")).toBe(0)
		shown:set(true)
		t.expect(#all(world.screen, "AlertModal")).toBe(1)
		local panel = find(world.screen, "AlertPanel")
		shown:set(true)
		t.expect(#all(world.screen, "AlertModal")).toBe(1)
		t.expect(find(world.screen, "AlertPanel")).toBe(panel)
		shown:set(false)
		t.expect(#all(world.screen, "AlertModal")).toBe(0)
		t.expect(calls).toBe(0)
		shown:set(true)
		find(world.screen, "ModalBack").Pressed.fire()
		t.expect(shown:peek()).toBe(false)
		t.expect(calls).toBe(1)
		t.expect(#all(world.screen, "AlertModal")).toBe(0)
		world.stop()
	end)

	t.it("owns alert content through repeated presentation and dismisses on the default action shortcut", function()
		local shown, text = Compose.cell(false), Compose.cell("Name")
		local live, built, accepted = 0, 0, 0
		local world = setup(function(UI)
			return UI.Alert "Edit" {
				title = "Edit name",
				isPresented = shown,
				content = function()
					live += 1
					built += 1
					Compose.cleanup(function()
						live -= 1
					end)
					return UI.TextInput "Name" { value = text }
				end,
				actions = {
					{
						id = "Save",
						label = "Save",
						shortcut = "defaultAction",
						onActivate = function()
							accepted += 1
						end,
					},
					{ id = "Cancel", label = "Cancel", role = "cancel" },
				},
			}
		end)
		t.expect(live).toBe(0)
		for round = 1, 2 do
			shown:set(true)
			t.expect(live).toBe(1)
			t.expect(built).toBe(round)
			t.expect(find(world.screen, "Name") ~= nil).toBe(true)
			local shortcut = action(world.screen, "Shortcut")
			t.expect(shortcut ~= nil).toBe(true)
			local keys = {}
			for _, binding in shortcut:GetChildren() do
				table.insert(keys, binding.KeyCode)
			end
			t.expect(table.find(keys, world.engine.types.Enum.KeyCode.Return) ~= nil).toBe(true)
			shortcut.Pressed.fire()
			t.expect(shown:peek()).toBe(false)
			t.expect(live).toBe(0)
			t.expect(accepted).toBe(round)
		end
		shown:set(true)
		t.expect(live).toBe(1)
		world.stop()
		t.expect(live).toBe(0)
	end)

	t.it("rebuilds sheet content on each presentation and disposes it on close and owner stop", function()
		local shown, detent = Compose.cell(false), Compose.cell("medium")
		local live, visits = 0, 0
		local world = setup(function(UI)
			return UI.Sheet "Details" {
				title = "Details",
				isPresented = shown,
				detent = detent,
				content = function()
					live += 1
					visits += 1
					Compose.cleanup(function()
						live -= 1
					end)
					return UI.Button "Body" {
						label = "Done",
						onActivate = function()
							shown:set(false)
						end,
					}
				end,
			}
		end)
		t.expect(live).toBe(0)
		for round = 1, 2 do
			shown:set(true)
			t.expect(live).toBe(1)
			t.expect(visits).toBe(round)
			t.expect(find(world.screen, "SheetPanel") ~= nil).toBe(true)
			find(world.screen, "Grabber").Activated.fire()
			t.expect(detent:peek()).toBe(if round == 1 then "large" else "medium")
			find(world.screen, "Close").Activated.fire()
			t.expect(shown:peek()).toBe(false)
			t.expect(live).toBe(0)
			t.expect(find(world.screen, "SheetPanel")).toBe(nil)
		end
		shown:set(true)
		t.expect(live).toBe(1)
		world.stop()
		t.expect(live).toBe(0)
	end)

	t.it("resolves every sheet detent to a height inside the measured available height", function()
		local detent = Compose.cell("medium")
		local world = setup(function(UI, Host)
			return UI.Sheet({
				isPresented = Compose.cell(true),
				detent = detent,
				detents = { "medium", "large", { id = "tall", height = 2000 }, { id = "fixed", height = 300 } },
				content = function()
					return Host.Frame "Body" {}
				end,
			})
		end)
		world.gui.ReducedMotionEnabled = true
		local panel = find(world.screen, "SheetPanel")
		local function height(id: string): number
			detent:set(id)
			return panel.Size.Y.Offset
		end
		t.expect(height("medium")).toBe(360)
		t.expect(height("large")).toBe(684)
		t.expect(height("tall")).toBe(720)
		t.expect(height("fixed")).toBe(300)
		find(world.screen, "Modal").AbsoluteSize = world.engine.types.Vector2.new(390, 600)
		t.expect(height("medium")).toBe(300)
		t.expect(height("large")).toBe(570)
		t.expect(height("tall")).toBe(600)
		t.expect(height("fixed")).toBe(300)
		t.expect(panel.Size.X.Offset).toBe(390)
		find(world.screen, "Modal").AbsoluteSize = world.engine.types.Vector2.new(1280, 600)
		t.expect(panel.Size.X.Offset).toBe(560)
		world.stop()
	end)

	t.it("keeps a usable minimum panel and a reachable close for tiny sheet detents", function()
		local shown, detent = Compose.cell(true), Compose.cell("peek")
		local world = setup(function(UI)
			return UI.Sheet({
				isPresented = shown,
				detent = detent,
				detents = { { id = "peek", height = 60 }, { id = "sliver", fraction = 0.05 } },
				title = "Peek",
				content = function()
					return UI.Button "Inside" { label = "Inside" }
				end,
			})
		end)
		world.gui.ReducedMotionEnabled = true
		local panel = find(world.screen, "SheetPanel")
		t.expect(panel.Size.Y.Offset).toBe(208)
		detent:set("sliver")
		t.expect(panel.Size.Y.Offset).toBe(208)
		find(world.screen, "Modal").AbsoluteSize = world.engine.types.Vector2.new(390, 180)
		t.expect(panel.Size.Y.Offset).toBe(180)
		t.expect(find(world.screen, "Inside"):IsDescendantOf(find(world.screen, "SheetContent"))).toBe(true)
		t.expect(find(world.screen, "Close").Parent.Name).toBe("Header")
		find(world.screen, "Close").Activated.fire()
		t.expect(shown:peek()).toBe(false)
		world.stop()
	end)

	t.it("hangs a callout below a top-right anchor with its arrow at the anchor and its body shifted left", function()
		local world = setup(function(UI, Host)
			local anchor = UI.Button "Plus" { label = "+" }
			return Host.Frame({
				anchor,
				UI.Callout({
					anchor = anchor,
					onRetire = function() end,
					content = function()
						return Host.TextLabel "Tip" { Text = "Post avatars to the marketplace" }
					end,
				}),
			})
		end)
		local V = world.engine.types.Vector2
		world.screen.AbsoluteSize = V.new(390, 844)
		local anchor, panel, arrow =
			find(world.screen, "Plus"), find(world.screen, "CalloutPanel"), find(world.screen, "Arrow")
		anchor.AbsolutePosition = V.new(338, 12)
		anchor.AbsoluteSize = V.new(44, 44)
		panel.AbsoluteSize = V.new(280, 96)
		advance(world.engine, 1)
		t.expect(find(panel, "PresentationScale").Scale).toBe(1)
		local left, top = panel.Position.X.Offset, panel.Position.Y.Offset
		t.expect(top).toBe(12 + 44 + 8)
		t.expect(left + 280 <= 390 - 8).toBe(true)
		t.expect(left < 338 + 22 - 140).toBe(true)
		local arrowCenterX = arrow.Position.X.Offset + 5
		t.expect(arrowCenterX >= 338 and arrowCenterX <= 338 + 44).toBe(true)
		t.expect(arrow.Position.Y.Offset).toBe(top - 5)
		t.expect(arrow.Position.Y.Offset < top).toBe(true)
		world.stop()
	end)

	t.it("carries the given callout content tree and bounds long copy to the viewport width", function()
		local long = string.rep("Pseudo-localized coaching copy that must wrap without clipping. ", 3)
		local world = setup(function(UI, Host, engine)
			local anchor = UI.Button "Anchor" { label = "Anchor" }
			return Host.Frame({
				anchor,
				UI.Callout({
					anchor = anchor,
					onRetire = function() end,
					content = function()
						return Host.Frame "Content" {
							Size = engine.types.UDim2.new(1, 0, 0, 0),
							AutomaticSize = engine.types.Enum.AutomaticSize.Y,
							Host.TextLabel "Body" {
								Text = long,
								TextWrapped = true,
								Size = engine.types.UDim2.new(1, 0, 0, 0),
								AutomaticSize = engine.types.Enum.AutomaticSize.Y,
							},
							Host.TextLabel "Sub" { Text = "Anyone can wear it" },
						}
					end,
				}),
			})
		end)
		local V = world.engine.types.Vector2
		local panel = find(world.screen, "CalloutPanel")
		local content = find(panel, "Content")
		t.expect(content ~= nil).toBe(true)
		t.expect(find(content, "Body").Text).toBe(long)
		t.expect(find(content, "Body").TextWrapped).toBe(true)
		t.expect(find(content, "Sub").Text).toBe("Anyone can wear it")
		local anchor = find(world.screen, "Anchor")
		anchor.AbsolutePosition = V.new(150, 300)
		anchor.AbsoluteSize = V.new(60, 44)
		advance(world.engine, 1)
		t.expect(find(panel, "PresentationScale").Scale).toBe(1)
		for _, extent in { 390, 240, 120 } do
			world.screen.AbsoluteSize = V.new(extent, 844)
			local width = panel.Size.X.Offset
			t.expect(width).toBe(math.min(280, extent - 16))
			t.expect(panel.Size.X.Scale).toBe(0)
			t.expect(panel.AutomaticSize).toBe(world.engine.types.Enum.AutomaticSize.Y)
			panel.AbsoluteSize = V.new(width, 180)
			t.expect(panel.Position.X.Offset >= 8).toBe(true)
			t.expect(panel.Position.X.Offset + width <= extent - 8).toBe(true)
		end
		world.stop()
	end)

	t.it("keeps a retired callout retired and unbuilt when it is presented again", function()
		local shown, used = Compose.cell(false), Compose.cell(false)
		local live, built, retired = 0, 0, 0
		local world = setup(function(UI, Host)
			local anchor = UI.Button "Anchor" {
				label = "Add",
				onActivate = function()
					used:set(true)
				end,
			}
			return Host.Frame({
				anchor,
				UI.Callout "Tip" {
					anchor = anchor,
					isPresented = shown,
					featureUsed = used,
					onRetire = function()
						retired += 1
					end,
					content = function()
						live += 1
						built += 1
						Compose.cleanup(function()
							live -= 1
						end)
						return Host.TextLabel "TipText" { Text = "Add your first item" }
					end,
				},
			})
		end)
		t.expect(live).toBe(0)
		shown:set(true)
		t.expect(live).toBe(1)
		find(world.screen, "Anchor").Activated.fire()
		t.expect(retired).toBe(1)
		t.expect(live).toBe(0)
		shown:set(false)
		shown:set(true)
		t.expect(live).toBe(0)
		t.expect(built).toBe(1)
		t.expect(retired).toBe(1)
		t.expect(find(world.screen, "CalloutPanel")).toBe(nil)
		world.stop()
		t.expect(live).toBe(0)
	end)

	t.it("adds no full-viewport cover or modal scope while a nonmodal callout is showing", function()
		local presses = 0
		local world = setup(function(UI, Host, engine)
			local anchor = UI.Button "Anchor" { label = "Anchor" }
			return Host.Frame "Live" {
				Size = engine.types.UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				anchor,
				UI.Button "Elsewhere" {
					label = "Elsewhere",
					onActivate = function()
						presses += 1
					end,
				},
				UI.Callout({
					anchor = anchor,
					onRetire = function() end,
					content = function()
						return Host.TextLabel "TipText" { Text = "Tip" }
					end,
				}),
			}
		end)
		t.expect(find(world.screen, "CalloutPanel") ~= nil).toBe(true)
		local live = find(world.screen, "Live")
		for _, node in world.screen:GetDescendants() do
			if node:IsA("GuiObject") and node ~= live and not within(node, live) then
				local covers = node.Size.X.Scale >= 1 and node.Size.Y.Scale >= 1
				t.expect(covers).toBe(false)
			end
		end
		t.expect(find(world.screen, "DismissOutside")).toBe(nil)
		t.expect(find(world.screen, "ModalBack")).toBe(nil)
		find(world.screen, "Elsewhere").Activated.fire()
		t.expect(presses).toBe(1)
		world.stop()
	end)

	t.it("makes the modal scrim the only full-viewport cover and keeps it translucent in every theme", function()
		local world = setup(function(UI, Host, engine)
			return Host.Frame "Live" {
				Size = engine.types.UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				UI.Button "Trigger" { label = "Open" },
				UI.Alert({
					isPresented = Compose.cell(true),
					title = "Leave race?",
					actions = { { id = "stay", label = "Stay", role = "cancel" } },
				}),
			}
		end)
		local live = find(world.screen, "Live")
		local covers = {}
		for _, node in world.screen:GetDescendants() do
			if
				node:IsA("GuiObject")
				and node ~= live
				and not within(node, live)
				and node.Size.X.Scale >= 1
				and node.Size.Y.Scale >= 1
				and node.Size.X.Offset >= 0
				and node.Size.Y.Offset >= 0
				and node.BackgroundTransparency < 1
			then
				table.insert(covers, node)
			end
		end
		t.expect(#covers).toBe(1)
		t.expect(covers[1].Name).toBe("DismissOutside")
		t.expect(covers[1]:HasTag("facet-scrim")).toBe(true)
		t.expect(find(world.screen, "AlertModal").BackgroundTransparency).toBe(1)
		world.stop()
		local themes = Facet.themes
		local packages = { themes.neutralPackage() }
		for _, name in
			{
				"classic_desktop",
				"compact_pointer",
				"fantasy_parchment",
				"fantasy_ornate",
				"glossy_mobile",
				"glossy_touch",
				"pixel_quest",
				"scifi_hud",
			}
		do
			local module: any = (require :: any)("../examples/themes/" .. name)
			local package, report = module.build(themes)
			t.expect(report.ok).toBe(true)
			table.insert(packages, package)
		end
		for _, package in packages do
			local engine: any = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local stop, sheet: any = runtime.mount(function()
				return themes.createStyleSheet(runtime, package, { types = engine.types })
			end, engine.new("Folder"))
			local scrim
			for _, rule in sheet:GetChildren() do
				if rule.Selector == ".facet-scrim" then
					scrim = rule:GetProperties().BackgroundTransparency
				end
			end
			t.expect(type(scrim)).toBe("number")
			t.expect(scrim > 0 and scrim < 1).toBe(true)
			stop()
			runtime:dispose()
		end
	end)

	t.it("closes every open menu level on a tap away from the automatic compact sheet", function()
		local shown = Compose.cell(true)
		local world = setup(function(UI)
			return UI.Menu({
				isPresented = shown,
				items = {
					{
						id = "adjust",
						label = "Adjust",
						children = {
							{
								id = "layer",
								label = "Layer",
								children = { { id = "leaf", label = "Leaf", onSelect = function() end } },
							},
						},
					},
				},
			})
		end)
		find(world.screen, "Modal").AbsoluteSize = world.engine.types.Vector2.new(390, 844)
		local panel = find(world.screen, "MenuPanel")
		t.expect(panel.Size.X.Scale).toBe(1)
		t.expect(panel.Size.X.Offset).toBe(-24)
		find(world.screen, "adjust").Activated.fire()
		find(world.screen, "layer").Activated.fire()
		t.expect(find(world.screen, "leaf") ~= nil).toBe(true)
		t.expect(find(world.screen, "Back") ~= nil).toBe(true)
		local catcher = find(world.screen, "DismissOutside")
		catcher.Activated.fire({ Position = world.engine.types.Vector2.new(4, 4) })
		t.expect(shown:peek()).toBe(false)
		t.expect(find(world.screen, "MenuPanel")).toBe(nil)
		t.expect(find(world.screen, "leaf")).toBe(nil)
		t.expect(find(world.screen, "DismissOutside")).toBe(nil)
		world.stop()
	end)

	t.it("dismisses through a fully transparent menu catcher", function()
		local shown = Compose.cell(true)
		local world = setup(function(UI)
			return UI.Menu({
				isPresented = shown,
				items = { { id = "Run", label = "Run", onSelect = function() end } },
			})
		end)
		local catcher = find(world.screen, "DismissOutside")
		t.expect(catcher.BackgroundTransparency).toBe(1)
		t.expect(catcher:HasTag("facet-scrim")).toBe(false)
		t.expect(catcher.Size).toBe(world.engine.types.UDim2.fromScale(1, 1))
		world.gui.PreferredTransparency = 0
		t.expect(catcher.BackgroundTransparency).toBe(1)
		catcher.Activated.fire({ Position = world.engine.types.Vector2.new(4, 4) })
		t.expect(shown:peek()).toBe(false)
		t.expect(find(world.screen, "MenuPanel")).toBe(nil)
		world.stop()
	end)

	t.it("updates the bound summary label on a choice and returns selection to the same trigger", function()
		local expanded, label, chosen = Compose.cell(false), Compose.cell("Select course"), false
		local world = setup(function(UI, Host, _, gui)
			local view = UI.CollapsibleView "View" {
				label = label,
				expanded = expanded,
				content = function()
					return UI.Button "One" {
						label = "Coastal circuit",
						onActivate = function()
							chosen = true
							label:set("Coastal circuit")
							expanded:set(false)
						end,
					}
				end,
			}
			gui.SelectedObject = view
			return Host.Frame({ view, UI.Button "Other" { label = "Unrelated" } })
		end)
		local trigger = find(world.screen, "View")
		t.expect(trigger:GetAttribute("label")).toBe("Select course")
		trigger.Activated.fire()
		t.expect(expanded:peek()).toBe(true)
		local surface = find(world.screen, "Expanded")
		t.expect(surface ~= nil).toBe(true)
		t.expect(within(world.gui.SelectedObject, surface)).toBe(true)
		find(world.screen, "One").Activated.fire()
		t.expect(chosen).toBe(true)
		t.expect(expanded:peek()).toBe(false)
		t.expect(find(world.screen, "Expanded")).toBe(nil)
		t.expect(trigger:GetAttribute("label")).toBe("Coastal circuit")
		t.expect(find(world.screen, "View")).toBe(trigger)
		t.expect(world.gui.SelectedObject).toBe(trigger)
		world.stop()
	end)

	t.it("pops one modal per outside tap, routes inside taps and never clicks through to the base", function()
		local outer, inner, barrier = Compose.cell(true), Compose.cell(true), Compose.cell(false)
		local baseHits, topHits = 0, 0
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.Button "Base" {
					label = "Base",
					onActivate = function()
						baseHits += 1
					end,
				},
				UI.Sheet({
					isPresented = outer,
					detent = Compose.cell("medium"),
					content = function()
						return UI.Button "OuterAction" { label = "Outer" }
					end,
				}),
				UI.Sheet({
					isPresented = inner,
					detent = Compose.cell("medium"),
					content = function()
						return UI.Button "InnerAction" {
							label = "Inner",
							onActivate = function()
								topHits += 1
							end,
						}
					end,
				}),
				UI.Alert({
					isPresented = barrier,
					title = "Decide",
					actions = { { id = "Keep", label = "Keep", role = "cancel" }, { id = "Go", label = "Go" } },
				}),
			})
		end)
		local base = find(world.screen, "Base")
		local catchers = all(world.screen, "DismissOutside")
		t.expect(#catchers).toBe(2)
		for _, catcher in catchers do
			t.expect(catcher.ClassName).toBe("TextButton")
			t.expect(catcher.Size).toBe(world.engine.types.UDim2.fromScale(1, 1))
			t.expect(catcher.ZIndex > base.ZIndex).toBe(true)
			t.expect(catcher.Selectable).toBe(false)
		end
		find(world.screen, "InnerAction").Activated.fire()
		t.expect(topHits).toBe(1)
		t.expect(inner:peek()).toBe(true)
		base.Activated.fire()
		t.expect(baseHits).toBe(0)
		catchers[2].Activated.fire({ Position = world.engine.types.Vector2.new(2, 2) })
		t.expect(inner:peek()).toBe(false)
		t.expect(outer:peek()).toBe(true)
		base.Activated.fire()
		t.expect(baseHits).toBe(0)
		catchers[1].Activated.fire({ Position = world.engine.types.Vector2.new(2, 2) })
		t.expect(outer:peek()).toBe(false)
		base.Activated.fire()
		t.expect(baseHits).toBe(1)
		barrier:set(true)
		local wall = find(world.screen, "DismissOutside")
		t.expect(wall.Size).toBe(world.engine.types.UDim2.fromScale(1, 1))
		wall.Activated.fire({ Position = world.engine.types.Vector2.new(2, 2) })
		t.expect(barrier:peek()).toBe(true)
		base.Activated.fire()
		t.expect(baseHits).toBe(1)
		find(world.screen, "ModalBack").Pressed.fire()
		t.expect(barrier:peek()).toBe(false)
		base.Activated.fire()
		t.expect(baseHits).toBe(2)
		world.stop()
	end)

	t.it("shows help for gamepad selection but never when a touch tap moves the selection", function()
		local world = setup(function(UI, Host)
			return Host.Frame "Screen" {
				UI.Button "Plus" { label = "+", help = "Posts this avatar" },
				UI.Button "Other" { label = "Other" },
			}
		end)
		local plus, other = find(world.screen, "Plus"), find(world.screen, "Other")
		local Enum = world.engine.types.Enum
		world.input.PreferredInput = Enum.PreferredInput.Touch
		plus.GuiState = Enum.GuiState.Press
		world.gui.SelectedObject = plus
		plus.GuiState = Enum.GuiState.Idle
		world.engine.heartbeat.fire(0.3)
		world.engine.heartbeat.fire(0.3)
		t.expect(find(world.screen, "HelpText")).toBe(nil)
		plus.GuiState = Enum.GuiState.Hover
		world.engine.heartbeat.fire(0.6)
		t.expect(find(world.screen, "HelpText")).toBe(nil)
		plus.GuiState = Enum.GuiState.Idle
		world.gui.SelectedObject = nil
		world.input.PreferredInput = Enum.PreferredInput.Gamepad
		world.gui.SelectedObject = plus
		world.engine.heartbeat.fire(0.5)
		t.expect(find(world.screen, "HelpText").Text).toBe("Posts this avatar")
		world.gui.SelectedObject = other
		t.expect(find(world.screen, "HelpText")).toBe(nil)
		world.engine.heartbeat.fire(0.6)
		t.expect(find(world.screen, "HelpText")).toBe(nil)
		world.gui.SelectedObject = nil
		world.input.PreferredInput = Enum.PreferredInput.KeyboardAndMouse
		plus.GuiState = Enum.GuiState.Hover
		world.engine.heartbeat.fire(0.5)
		t.expect(find(world.screen, "HelpText") ~= nil).toBe(true)
		plus.GuiState = Enum.GuiState.Press
		t.expect(find(world.screen, "HelpText")).toBe(nil)
		world.stop()
	end)

	t.it("keeps the top modal active when the covered surface beneath it is dismissed", function()
		local outer, inner, shortcuts, confirmed = Compose.cell(true), Compose.cell(false), 0, 0
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.Button "Background" {
					label = "Background",
					shortcut = { keyCode = "K" },
					onActivate = function()
						shortcuts += 1
					end,
				},
				UI.Sheet({
					isPresented = outer,
					detent = Compose.cell("medium"),
					content = function()
						return UI.Button "Covered" { label = "Covered" }
					end,
				}),
				UI.Alert({
					isPresented = inner,
					title = "Confirm",
					actions = {
						{
							id = "Ok",
							label = "Ok",
							onActivate = function()
								confirmed += 1
							end,
						},
						{ id = "No", label = "No", role = "cancel" },
					},
				}),
			})
		end)
		world.gui.SelectedObject = find(world.screen, "Covered")
		inner:set(true)
		local ok = find(world.screen, "Ok")
		t.expect(world.gui.SelectedObject).toBe(ok)
		t.expect(#all(world.screen, "FacetModalBack")).toBe(2)
		t.expect(enabledCount(world.screen, "ModalBack")).toBe(1)
		outer:set(false)
		t.expect(find(world.screen, "SheetPanel")).toBe(nil)
		t.expect(inner:peek()).toBe(true)
		t.expect(find(world.screen, "AlertPanel") ~= nil).toBe(true)
		t.expect(world.gui.SelectedObject).toBe(ok)
		local panel = find(world.screen, "AlertPanel")
		for _, direction in { "Up", "Down", "Left", "Right" } do
			t.expect(panel["SelectionBehavior" .. direction]).toBe(world.engine.types.Enum.SelectionBehavior.Stop)
		end
		find(world.screen, "Shortcut").Pressed.fire()
		t.expect(shortcuts).toBe(0)
		t.expect(enabledCount(world.screen, "ModalBack")).toBe(1)
		local activate = action(world.screen, "Activate")
		t.expect(activate ~= nil).toBe(true)
		activate.Pressed.fire()
		t.expect(confirmed).toBe(1)
		t.expect(inner:peek()).toBe(false)
		find(world.screen, "Shortcut").Pressed.fire()
		t.expect(shortcuts).toBe(1)
		world.stop()
	end)

	t.it("routes activation to the selected control of the top modal and survives a re-entrant dismiss", function()
		local presented, music, yes = Compose.cell(false), 0, 0
		local world = setup(function(UI, Host, _, gui)
			local base = UI.Button "Music" {
				label = "Music",
				onActivate = function()
					music += 1
				end,
			}
			gui.SelectedObject = base
			return Host.Frame({
				base,
				UI.Alert({
					isPresented = presented,
					title = "Apply?",
					actions = {
						{
							id = "Yes",
							label = "Yes",
							onActivate = function()
								yes += 1
								presented:set(false)
							end,
						},
						{ id = "No", label = "No", role = "cancel" },
					},
				}),
			})
		end)
		local base = find(world.screen, "Music")
		presented:set(true)
		local yesButton = find(world.screen, "Yes")
		t.expect(world.gui.SelectedObject).toBe(yesButton)
		local activate = action(world.screen, "Activate")
		t.expect(within(activate.Parent, world.screen)).toBe(true)
		base.Activated.fire()
		t.expect(music).toBe(0)
		activate.Pressed.fire()
		t.expect(yes).toBe(1)
		t.expect(music).toBe(0)
		t.expect(presented:peek()).toBe(false)
		t.expect(find(world.screen, "AlertModal")).toBe(nil)
		t.expect(world.gui.SelectedObject).toBe(base)
		local baseActivate = action(world.screen, "Activate")
		t.expect(baseActivate ~= nil).toBe(true)
		baseActivate.Pressed.fire()
		t.expect(music).toBe(1)
		t.expect(yes).toBe(1)
		world.stop()
	end)

	t.it("traps and cancels the confirmation tutorial and restores the delete trigger", function()
		local built: any
		local world = setup(function(UI, Host, engine, _, runtime)
			built = require("../examples/gallery/examples/04_confirm_dialog").build({
				UI = UI,
				Host = Host,
				Compose = Compose,
				types = engine.types,
				runtime = runtime,
			})
			return built.screen()
		end)
		local delete = find(world.screen, "Delete")
		world.gui.SelectedObject = delete
		for round = 1, 2 do
			local open = action(world.screen, "Activate")
			t.expect(open ~= nil).toBe(true)
			open.Pressed.fire()
			local panel = find(world.screen, "AlertPanel")
			t.expect(panel ~= nil).toBe(true)
			for _, direction in { "Up", "Down", "Left", "Right" } do
				t.expect(panel["SelectionBehavior" .. direction]).toBe(world.engine.types.Enum.SelectionBehavior.Stop)
			end
			find(world.screen, "AlertModal").AbsoluteSize = world.engine.types.Vector2.new(1280, 800)
			local cancel, confirm = find(world.screen, "Cancel"), find(world.screen, "Confirm")
			t.expect(world.gui.SelectedObject).toBe(cancel)
			t.expect(cancel.LayoutOrder < confirm.LayoutOrder).toBe(true)
			t.expect(find(world.screen, "Actions"):FindFirstChildWhichIsA("UIListLayout").FillDirection)
				.toBe(world.engine.types.Enum.FillDirection.Horizontal)
			delete.Activated.fire()
			t.expect(#all(world.screen, "AlertModal")).toBe(1)
			if round == 1 then
				find(world.screen, "ModalBack").Pressed.fire()
			else
				action(world.screen, "Activate").Pressed.fire()
			end
			t.expect(find(world.screen, "AlertModal")).toBe(nil)
			t.expect(built.result()).toBe("cancelled")
			t.expect(built.hasSave()).toBe(true)
			t.expect(world.gui.SelectedObject).toBe(delete)
		end
		world.stop()
	end)
end)

t.describe("gallery toast strength", function()
	t.it("drops exactly the least urgent newest burst toast at the queue cap and drains the rest", function()
		local built, node, _, engine, _, close = mountScenario("sponsor_toast")
		find(node, "Burst").Activated.fire()
		local report = built.report()
		t.expect(report.visible).toBe(3)
		t.expect(report.queued).toBe(8)
		t.expect(report.dropped).toBe(1)
		local titles = {}
		for _, row in report.rows do
			titles[row.title] = true
		end
		t.expect(titles["Burst 12"]).toBe(nil)
		for i = 1, 11 do
			t.expect(titles["Burst " .. i]).toBe(true)
		end
		advance(engine, 8)
		report = built.report()
		t.expect(report.visible).toBe(0)
		t.expect(report.queued).toBe(0)
		t.expect(report.exiting).toBe(0)
		t.expect(report.dropped).toBe(1)
		t.expect(#toasts(node)).toBe(0)
		close()
	end)

	t.it("keeps reduced-motion toasts on screen for the same durations as animated ones", function()
		local function run(reduced: boolean): (string, number)
			local built, node, _, engine, _, close = mountScenario("sponsor_toast", reduced)
			find(node, "Burst").Activated.fire()
			local samples = {}
			for _ = 1, 80 do
				advance(engine, 0.1)
				local report = built.report()
				table.insert(samples, report.visible .. "/" .. report.queued)
			end
			local dropped = built.report().dropped
			close()
			return table.concat(samples, ","), dropped
		end
		local full, fullDropped = run(false)
		local reduced, reducedDropped = run(true)
		t.expect(reduced).toBe(full)
		t.expect(reducedDropped).toBe(fullDropped)
		t.expect(string.sub(full, -3)).toBe("0/0")
		local built, node, _, engine, _, close = mountScenario("sponsor_toast", true)
		built.steps.send()
		t.expect(toasts(node)[1].GroupTransparency).toBe(0)
		close()
		built, node, _, engine, _, close = mountScenario("sponsor_toast", false)
		built.steps.send()
		local card = toasts(node)[1]
		t.expect(card.GroupTransparency).toBe(1)
		advance(engine, 0.3)
		t.expect(card.GroupTransparency).toBe(0)
		close()
	end)

	t.it("releases dismissed toasts within the half-second cap and returns the counters and instances", function()
		local built, node, _, engine, _, close = mountScenario("sponsor_toast")
		local baseline = #node:GetDescendants()
		for i = 1, 3 do
			built.show("Held " .. i, "Long", { duration = 20 })
		end
		t.expect(#toasts(node)).toBe(3)
		built.steps.clear()
		t.expect(built.report().exiting).toBe(3)
		t.expect(built.report().visible).toBe(0)
		advance(engine, 0.5, 1 / 60)
		local report = built.report()
		t.expect(report.visible).toBe(0)
		t.expect(report.queued).toBe(0)
		t.expect(report.exiting).toBe(0)
		t.expect(#toasts(node)).toBe(0)
		t.expect(#node:GetDescendants()).toBe(baseline)
		close()
		t.expect(engine.heartbeat.count()).toBe(0)
	end)

	t.it("leaves selection, modal scope and the control beneath untouched while a toast shows", function()
		local built, node, ctx, engine, target, close = mountScenario("sponsor_toast")
		local beneath = find(node, "Beneath")
		ctx.guiService.SelectedObject = beneath
		built.steps.send()
		engine.heartbeat.fire(1 / 60)
		t.expect(ctx.guiService.SelectedObject).toBe(beneath)
		t.expect(find(node, "DismissOutside")).toBe(nil)
		t.expect(find(node, "ModalBack")).toBe(nil)
		local messages = find(node, "Messages")
		t.expect(messages.Active).toBe(false)
		t.expect(messages.ZIndex > find(node, "Actions").ZIndex).toBe(true)
		t.expect(messages.ZIndex < 100).toBe(true)
		local seen = 0
		for _, part in messages:GetDescendants() do
			if part:IsA("GuiObject") then
				seen += 1
				t.expect(part:IsA("GuiButton") or part:IsA("TextBox")).toBe(false)
				t.expect(part.Selectable).toBe(false)
			end
		end
		t.expect(seen > 0).toBe(true)
		local activate = action(target, "Activate")
		t.expect(activate ~= nil).toBe(true)
		activate.Pressed.fire()
		t.expect(built.report().presses).toBe(1)
		t.expect(built.report().visible).toBe(1)
		built.steps.clear()
		advance(engine, 0.5)
		t.expect(ctx.guiService.SelectedObject).toBe(beneath)
		close()
	end)

	t.it("fits toast width to measured text within the floor, the cap and the available row", function()
		local built, node, ctx, _, _, close = mountScenario("sponsor_toast", true)
		local V = ctx.types.Vector2
		built.show("Saved", "Done")
		local card = toasts(node)[1]
		t.expect(card.Size).toBe(ctx.types.UDim2.new(1, 0, 0, 0))
		t.expect(card.AnchorPoint.X).toBe(0.5)
		t.expect(card.Position.X.Scale).toBe(0.5)
		for _, name in { "Title", "Detail" } do
			local text = find(card, name)
			t.expect(text.Size.X.Scale).toBe(1)
			t.expect(text.TextWrapped).toBe(true)
		end
		built.width:set("hug")
		find(card, "Measure_title").TextBounds = V.new(20, 20)
		find(card, "Measure_detail").TextBounds = V.new(30, 20)
		t.expect(card.Size.X.Offset).toBe(80)
		find(card, "Measure_detail").TextBounds = V.new(900, 20)
		t.expect(card.Size.X.Offset).toBe(560)
		find(node, "Messages").AbsoluteSize = V.new(300, 72)
		t.expect(card.Size.X.Offset).toBe(300)
		find(card, "Measure_detail").TextBounds = V.new(150, 20)
		t.expect(card.Size.X.Offset).toBe(174)
		t.expect(find(card, "Title").Size.X.Scale).toBe(1)
		close()
	end)

	t.it("docks a bottom strip that grows upward and slides top survivors into the vacated slot", function()
		local built, node, _, engine, _, close = mountScenario("sponsor_toast", true)
		local messages = find(node, "Messages")
		t.expect(messages.AnchorPoint.Y).toBe(1)
		t.expect(messages.Position).toBe(engine.types.UDim2.new(0, 8, 1, -8))
		built.show("First", "Older", { duration = 20 })
		t.expect(messages.Size.Y.Offset).toBe(72)
		built.show("Second", "Newest", { duration = 20 })
		t.expect(messages.Size.Y.Offset).toBe(152)
		local cards = toasts(node)
		local first, second = cards[1], cards[2]
		if find(first, "Title").Text ~= "First" then
			first, second = second, first
		end
		t.expect(first.Position.Y.Offset).toBe(0)
		t.expect(second.Position.Y.Offset).toBe(80)
		close()
		built, node, _, engine, _, close = mountScenario("sponsor_toast")
		built.edge:set("top")
		local leaving = built.show("First", "Leaves", { duration = 20 })
		built.show("Second", "Stays", { duration = 20 })
		messages = find(node, "Messages")
		t.expect(messages.AnchorPoint.Y).toBe(0)
		advance(engine, 1.5, 1 / 60)
		local survivor
		for _, card in toasts(node) do
			if find(card, "Title").Text == "Second" then
				survivor = card
			end
		end
		local start = survivor.Position.Y.Offset
		t.expect(start > 70).toBe(true)
		built.dismiss(leaving)
		local previous, largest = start, 0
		for _ = 1, 120 do
			engine.heartbeat.fire(1 / 60)
			local y = survivor.Position.Y.Offset
			largest = math.max(largest, math.abs(y - previous))
			previous = y
		end
		t.expect(largest < start / 2).toBe(true)
		t.expect(math.abs(previous) < 0.01).toBe(true)
		close()
	end)

	t.it("schedules toasts with per-toast timeouts that promote the queue in the same frame", function()
		local built, _, _, engine, _, close = mountScenario("sponsor_toast")
		for _, title in { "a", "b", "c", "d", "e" } do
			built.show(title, title, { duration = 2, readFloor = 0 })
		end
		t.expect(visibleTitles(built)).toBe("a,b,c")
		t.expect(built.report().queued).toBe(2)
		advance(engine, 1.9)
		t.expect(visibleTitles(built)).toBe("a,b,c")
		advance(engine, 0.2)
		t.expect(visibleTitles(built)).toBe("d,e")
		t.expect(built.report().queued).toBe(0)
		built.steps.clear()
		advance(engine, 0.5)
		built.show("short", "short", { duration = 1, readFloor = 0 })
		built.show("long", "long", { duration = 6, readFloor = 0 })
		advance(engine, 1.5)
		t.expect(visibleTitles(built)).toBe("long")
		built.steps.clear()
		advance(engine, 0.5)
		built.show("default", "default")
		local row = built.report().rows[#built.report().rows]
		t.expect(row.duration).toBe(4)
		t.expect(row.readFloor).toBe(0.5)
		t.expect(row.priority).toBe(0)
		advance(engine, 3.9)
		t.expect(visibleTitles(built)).toBe("default")
		advance(engine, 0.2)
		t.expect(visibleTitles(built)).toBe("")
		close()
	end)

	t.it("orders the toast queue by priority first in first out and preempts only the weakest showing toast", function()
		local built, _, _, engine, _, close = mountScenario("sponsor_toast")
		local held = {}
		for i = 1, 3 do
			held[i] = built.show("held" .. i, "held", { duration = 30, priority = 9 })
		end
		built.show("low", "q", { priority = 0, duration = 30 })
		built.show("high", "q", { priority = 5, duration = 30 })
		built.show("low2", "q", { priority = 0, duration = 30 })
		advance(engine, 2)
		t.expect(visibleTitles(built)).toBe("held1,held2,held3")
		built.dismiss(held[1])
		t.expect(visibleTitles(built)).toBe("held2,held3,high")
		built.dismiss(held[2])
		t.expect(visibleTitles(built)).toBe("held3,low,high")
		built.dismiss(held[3])
		t.expect(visibleTitles(built)).toBe("low,high,low2")
		close()
		built, _, _, engine, _, close = mountScenario("sponsor_toast")
		built.show("important", "p5", { priority = 5, duration = 30 })
		built.show("trivial", "p0", { priority = 0, duration = 30 })
		built.show("middle", "p3", { priority = 3, duration = 30 })
		built.show("urgent", "p9", { priority = 9 })
		t.expect(visibleTitles(built)).toBe("important,trivial,middle")
		advance(engine, 1)
		t.expect(visibleTitles(built)).toBe("important,middle,urgent")
		close()
		built, _, _, engine, _, close = mountScenario("sponsor_toast")
		for i = 1, 3 do
			built.show("showing" .. i, "p5", { priority = 5, duration = 30 })
		end
		built.show("same", "p5", { priority = 5 })
		advance(engine, 5)
		t.expect(visibleTitles(built)).toBe("showing1,showing2,showing3")
		t.expect(built.report().queued).toBe(1)
		close()
	end)

	t.it("supersedes queued toasts in place and bounds the queue without dropping a showing toast", function()
		local built, _, _, _, _, close = mountScenario("sponsor_toast")
		for i = 1, 3 do
			built.show("hold" .. i, "hold", { duration = 30, priority = 9 })
		end
		local lap = built.show("lap 1", "q", { subject = "lap" })
		t.expect(built.show("lap 2", "q", { subject = "lap" })).toBe(lap)
		local report = built.report()
		t.expect(report.queued).toBe(1)
		t.expect(report.superseded).toBe(1)
		for _, row in report.rows do
			if row.id == lap then
				t.expect(row.title).toBe("lap 2")
				t.expect(row.state).toBe("queued")
			end
		end
		built.dismiss(lap)
		t.expect(built.report().queued).toBe(0)
		for i = 1, 8 do
			built.show("q" .. i, "q", { priority = i % 4 + 1 })
		end
		t.expect(built.report().queued).toBe(8)
		t.expect(built.report().dropped).toBe(0)
		built.show("urgent", "q", { priority = 8 })
		report = built.report()
		t.expect(report.queued).toBe(8)
		t.expect(report.dropped).toBe(1)
		local kept = {}
		for _, row in report.rows do
			kept[row.title] = row.state
		end
		t.expect(kept.urgent).toBe("queued")
		t.expect(kept.q8).toBe(nil)
		t.expect(kept.q4).toBe("queued")
		built.show("least", "q", { priority = -1 })
		report = built.report()
		t.expect(report.dropped).toBe(2)
		kept = {}
		for _, row in report.rows do
			kept[row.title] = row.state
		end
		t.expect(kept.least).toBe(nil)
		for i = 1, 200 do
			built.show("spam" .. i, "spam", { priority = -1 })
		end
		report = built.report()
		t.expect(report.visible).toBe(3)
		t.expect(report.queued).toBe(8)
		t.expect(report.dropped).toBe(202)
		t.expect(visibleTitles(built)).toBe("hold1,hold2,hold3")
		close()
	end)

	t.it("dismisses showing and queued toasts by id and ignores an unknown id", function()
		local built, _, _, _, _, close = mountScenario("sponsor_toast")
		local first = built.show("a", "a", { duration = 30 })
		built.show("b", "b", { duration = 30 })
		built.show("c", "c", { duration = 30 })
		built.show("d", "d", { duration = 30 })
		local queued = built.show("e", "e", { duration = 30 })
		t.expect(built.report().queued).toBe(2)
		built.dismiss(queued)
		t.expect(visibleTitles(built)).toBe("a,b,c")
		t.expect(built.report().queued).toBe(1)
		built.dismiss(first)
		t.expect(visibleTitles(built)).toBe("b,c,d")
		t.expect(built.report().queued).toBe(0)
		t.expect(built.report().exiting).toBe(2)
		local before = built.report()
		t.expect((pcall(built.dismiss, 9999))).toBe(true)
		local after = built.report()
		t.expect(after.visible).toBe(before.visible)
		t.expect(after.queued).toBe(before.queued)
		t.expect(after.exiting).toBe(before.exiting)
		built.steps.clear()
		t.expect(built.report().visible).toBe(0)
		t.expect(built.report().queued).toBe(0)
		close()
	end)
end)

t.describe("gallery surface page strength", function()
	t.it("offers toasts under Indicators and hides and expires them after leaving the page", function()
		local built, node, _, engine, _, close = mountScenario("all_controls")
		local function visibleInTree(part: any): boolean
			local at = part
			while at and at ~= node do
				if at:IsA("GuiObject") and not at.Visible then
					return false
				end
				at = at.Parent
			end
			return true
		end
		find(node, "indicators").Activated.fire()
		find(node, "toasts").Activated.fire()
		t.expect(built.report().active).toBe("toasts")
		local toastLab = built.report().example
		t.expect(toastLab ~= nil).toBe(true)
		find(node, "Send").Activated.fire()
		local page = built.report()
		t.expect(page.example.visible).toBe(1)
		local messages = find(node, "Messages")
		t.expect(visibleInTree(toasts(node)[1])).toBe(true)
		find(node, "Beneath").Activated.fire()
		t.expect(built.report().example.presses).toBe(1)
		t.expect(built.report().example.visible).toBe(1)
		find(node, "progress").Activated.fire()
		t.expect(built.report().active).toBe("progress")
		t.expect(visibleInTree(messages)).toBe(false)
		advance(engine, 4.6)
		t.expect(find(node, "Messages")).toBe(messages)
		t.expect(#toasts(node)).toBe(0)
		find(node, "toasts").Activated.fire()
		t.expect(built.report().active).toBe("toasts")
		local back = built.report().example
		t.expect(back.visible).toBe(0)
		t.expect(back.queued).toBe(0)
		t.expect(back.presses).toBe(1)
		t.expect(find(node, "Messages")).toBe(messages)
		t.expect(visibleInTree(messages)).toBe(true)
		close()
	end)
end)

t.describe("virtual monitors surface strength", function()
	t.it("names the live look in the rich HUD and degrades it to a compact summary under space pressure", function()
		withMonitors(function(world)
			local avatar, model, V = world.Avatar, world.model, world.engine.types.Vector2
			local body = find(avatar, "AvatarBody")
			body.AbsoluteSize = V.new(1920, 1080)
			for _, id in { "Look", "Rotation", "Spin" } do
				t.expect(find(avatar, id .. "Rich") ~= nil).toBe(true)
				t.expect(find(avatar, "Expand" .. id)).toBe(nil)
			end
			t.expect(find(avatar, "LookRich").Text).toBe("Sage · Hat on")
			model.hat:set(false)
			t.expect(find(avatar, "LookRich").Text).toBe("Sage · Hat off")
			model.hat:set(true)
			body.AbsoluteSize = V.new(393, 852)
			for _, id in { "Look", "Rotation", "Spin" } do
				t.expect(find(avatar, id .. "Rich")).toBe(nil)
				t.expect(find(avatar, "Expand" .. id) ~= nil).toBe(true)
			end
			t.expect(find(avatar, "LookHUD").Size.Y.Offset).toBe(32)
			t.expect(find(avatar, "ExpandLook").Text).toBe("Sage")
			find(avatar, "ExpandLook").Activated.fire()
			t.expect(model.avatarSummary:peek()).toBe(true)
			t.expect(find(find(world.target, "SummaryPalette"), "Value").Text).toBe("Sage")
			t.expect(find(find(world.target, "SummaryHat"), "Value").Text).toBe("On")
			find(world.target, "DismissOutside").Activated.fire({ Position = V.new(4, 4) })
			t.expect(model.avatarSummary:peek()).toBe(false)
			t.expect(find(world.target, "SheetPanel")).toBe(nil)
		end)
	end)

	t.it("presents the look summary from its button and collapses tips without a leftover overlay", function()
		withMonitors(function(world)
			local avatar, model, V = world.Avatar, world.model, world.engine.types.Vector2
			find(avatar, "AvatarBody").AbsoluteSize = V.new(920, 1100)
			model.palette:set("clay")
			model.hat:set(false)
			model.angle:set(30)
			model.autoSpin:set(3)
			t.expect(find(world.target, "SheetPanel")).toBe(nil)
			find(avatar, "Summary").Activated.fire()
			local expected = { Palette = "Clay", Hat = "Off", Rotation = "30°", AutoSpin = "Fast" }
			for id, value in expected do
				t.expect(find(find(world.target, "Summary" .. id), "Value").Text).toBe(value)
			end
			find(world.target, "Done").Activated.fire()
			t.expect(find(world.target, "SheetPanel")).toBe(nil)
			t.expect(find(world.target, "TurnTips")).toBe(nil)
			find(avatar, "Tips").Activated.fire()
			t.expect(model.avatarTipsExpanded:peek()).toBe(true)
			t.expect(find(world.target, "TurnTips").Text).toBe(
				"Turn step sets the increment for Rotation and both Turn buttons. Use the stepper to choose 15°, 30°, 45° or 90°."
			)
			find(world.target, "DismissOutside").Activated.fire({ Position = V.new(4, 4) })
			t.expect(model.avatarTipsExpanded:peek()).toBe(false)
			t.expect(find(world.target, "TurnTips")).toBe(nil)
			t.expect(find(world.target, "Expanded")).toBe(nil)
			t.expect(find(world.target, "DismissOutside")).toBe(nil)
			find(avatar, "Tips").Activated.fire()
			t.expect(find(world.target, "TurnTips") ~= nil).toBe(true)
			find(find(world.target, "Expanded"), "Close").Activated.fire()
			t.expect(find(world.target, "Expanded")).toBe(nil)
		end)
	end)

	t.it("anchors the about this rating popover to its line and dismisses it on an outside tap", function()
		withMonitors(function(world)
			local model, V, Enum = world.model, world.engine.types.Vector2, world.engine.types.Enum
			world.target.AbsoluteSize = V.new(920, 640)
			find(world.Discover, "Games").AbsoluteWindowSize = V.new(850, 260)
			model.selectGame(model.catalog.items:peek()[1])
			t.expect(find(world.target, "CalloutPanel")).toBe(nil)
			local anchor = find(world.target, "AboutRating")
			anchor.AbsolutePosition = V.new(300, 200)
			anchor.AbsoluteSize = V.new(320, 36)
			anchor.Activated.fire()
			local panel = find(world.target, "CalloutPanel")
			t.expect(panel ~= nil).toBe(true)
			t.expect(find(panel, "RatingMeaning") ~= nil).toBe(true)
			panel.AbsoluteSize = V.new(280, 90)
			t.expect(panel.Position.Y.Offset).toBe(200 + 36 + 8)
			t.expect(panel.Position.X.Offset).toBe(300 + (320 - 280) / 2)
			panel.AbsolutePosition = V.new(320, 244)
			world.input.InputBegan.fire(
				{ UserInputType = Enum.UserInputType.MouseButton1, Position = V.new(400, 280) },
				false
			)
			t.expect(find(world.target, "CalloutPanel")).toBe(panel)
			world.input.InputBegan.fire({ UserInputType = Enum.UserInputType.Touch, Position = V.new(20, 600) }, false)
			t.expect(panel.isDestroyed()).toBe(true)
			t.expect(find(world.target, "RatingMeaning")).toBe(nil)
			find(world.target, "AboutRating").Activated.fire()
			t.expect(find(world.target, "RatingMeaning") ~= nil).toBe(true)
		end)
	end)
end)
