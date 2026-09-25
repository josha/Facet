--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local gallery = require("../examples/gallery/client/screen")
local demoTabs = require("../examples/gallery/scenarios/demo_tabs")
local Compose = Facet.Compose

local function find(root, name, class)
	if root.Name == name and (not class or root:IsA(class)) then
		return root
	end
	for _, child in root:GetChildren() do
		local found = find(child, name, class)
		if found then
			return found
		end
	end
	return nil
end

local function fixture(build)
	local engine = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local target, gui = engine.new("Folder"), engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
	function input:GetFocusedTextBox()
		return nil
	end
	local ctx = {
		Facet = Facet,
		Compose = Compose,
		runtime = runtime,
		Host = runtime.constructors,
		types = engine.types,
		viewport = Compose.cell({ width = 1280, height = 720 }),
		inputTarget = target,
		guiService = gui,
		runService = { Heartbeat = engine.heartbeat },
		selection = Compose.cell("first"),
		theme = Compose.cell(Facet.themes.neutralPackage()),
		themeMode = Compose.cell("light"),
	}
	ctx.packages = { Neutral = ctx.theme:peek() }
	local stop, root = runtime.mount(function()
		gallery.configure(ctx)
		ctx.UI = Facet.controls(runtime, {
			types = engine.types,
			viewport = ctx.viewport,
			inputParent = target,
			services = { GuiService = gui, UserInputService = input },
			theme = ctx.theme,
			reducedMotion = ctx.reducedMotion,
		})
		return ctx.Host.ScreenGui "GalleryTest" { build(ctx) }
	end, target)
	return ctx, root, function()
		stop()
		runtime:dispose()
	end
end

local function scenarioGroup(scenario: any, name: string): boolean
	for _, group in scenario.groups do
		if group.id == name then
			return true
		end
	end
	return false
end

t.describe("native gallery shell parity", function()
	t.it("reports the selected retained leaf and propagates ancestor page visibility", function()
		local built, contexts, counts = nil, {}, {}
		local function entry(id)
			return {
				id = id,
				label = id,
				scenario = {
					build = function(ctx)
						counts[id] = (counts[id] or 0) + 1
						contexts[id] = ctx
						local clicks = Compose.cell(0)
						return {
							screen = function()
								return ctx.UI.Button({
									Name = id .. "Action",
									label = id,
									onActivate = function()
										clicks:update(function(value)
											return value + 1
										end)
									end,
								})
							end,
							report = function()
								return { clicks = clicks:peek() }
							end,
						}
					end,
				},
			}
		end
		local ctx, root, stop = fixture(function(context)
			context.pageVisible = Compose.cell(true)
			built = demoTabs(context, "TabsTest", {
				{ id = "group", label = "Group", tabs = { entry("a"), entry("b") } },
				entry("other"),
			})
			return built.screen()
		end)
		local button = find(root, "aAction")
		button.Activated.fire()
		find(root, "b", "TextButton").Activated.fire()
		t.expect(built.report().active).toBe("b")
		t.expect(contexts.a.pageVisible:peek()).toBe(false)
		find(root, "a", "TextButton").Activated.fire()
		t.expect(built.report().active).toBe("a")
		t.expect(built.report().example.clicks).toBe(1)
		t.expect(find(root, "aAction")).toBe(button)
		t.expect(counts.a).toBe(1)
		t.expect(contexts.a.pageVisible:peek()).toBe(true)
		find(root, "other", "TextButton").Activated.fire()
		t.expect(contexts.a.pageVisible:peek()).toBe(false)
		t.expect(built.report().active).toBe("other")
		ctx.pageVisible:set(false)
		t.expect(contexts.other.pageVisible:peek()).toBe(false)
		stop()
	end)

	t.it("keeps API theme and palette choices consistent and rejects invalid demos", function()
		local ctx, root, stop = fixture(function(context)
			local second = Facet.themes.neutralPackage()
			second.style.defaultTheme = "evening"
			second.style.themes = { table.clone(second.style.themes[1]) }
			second.style.themes[1].name = "evening"
			context.packages.Second = second
			context.demos = {
				{ id = "first", title = "First", kind = "fixture", module = "first" },
				{ id = "second", title = "Second", kind = "fixture", module = "second" },
			}
			context.load = function(_, name)
				return {
					build = function(page)
						return {
							screen = function()
								return page.Host.Frame({ Name = name })
							end,
						}
					end,
				}
			end
			return gallery.build(context)
		end)
		local before = find(root, "first")
		local surface = find(root, "Gallery")
		local scale = find(surface, "ViewingDistance", "UIScale")
		ctx.viewingDistance:set("ten-foot")
		t.expect(scale.Scale).toBe(1.5)
		t.expect(math.abs(surface.Size.X.Scale * scale.Scale - 1) < 0.000001).toBe(true)
		t.expect(find(root, "first")).toBe(before)
		ctx.viewingDistance:set("near")
		t.expect(scale.Scale).toBe(1)
		ctx.viewingDistance:set("automatic")
		t.expect(scale.Scale).toBe(1)
		local bad = gallery.dispatch(ctx, "show", "missing")
		t.expect(bad.ok).toBe(false)
		t.expect(ctx.selection:peek()).toBe("first")
		t.expect(find(root, "first")).toBe(before)
		local changed = gallery.dispatch(ctx, "theme", "Second")
		t.expect(changed.ok).toBe(true)
		t.expect(changed.theme).toBe("Second")
		t.expect(changed.palette).toBe("evening")
		t.expect(ctx.theme:peek()).toBe(ctx.packages.Second)
		t.expect(gallery.dispatch(ctx, "theme", "missing").ok).toBe(false)
		t.expect(ctx.themeName:peek()).toBe("Second")
		find(root, "Settings", "TextButton").Activated.fire()
		local themePicker = find(root, "Theme")
		local trigger = find(themePicker, "Trigger")
		if trigger then
			t.expect(trigger.Text).toBe("Second")
		else
			t.expect(find(themePicker, "Second"):GetAttribute("selected")).toBe(true)
		end
		gallery.dispatch(ctx, "next")
		t.expect(ctx.active:peek()).toBe("second")
		stop()
	end)

	t.it("keeps gallery motion preview synchronized with native accessibility preferences", function()
		local ctx, _, stop = fixture(function(context)
			return context.Host.Frame "MotionTest" {}
		end)
		t.expect(ctx.reducedMotion:peek()).toBe(false)
		ctx.motionPreference:set(true)
		t.expect(ctx.reducedMotion:peek()).toBe(true)
		ctx.motionPreference:set(nil)
		t.expect(ctx.reducedMotion:peek()).toBe(false)
		ctx.guiService.ReducedMotionEnabled = true
		t.expect(ctx.reducedMotion:peek()).toBe(true)
		ctx.motionPreference:set(false)
		t.expect(ctx.reducedMotion:peek()).toBe(true)
		ctx.guiService.ReducedMotionEnabled = false
		t.expect(ctx.reducedMotion:peek()).toBe(false)
		stop()
	end)

	t.it(
		"names the Status and Menus categories on the category bar and visits every inner tab through its own bar",
		function()
			for _, name in { "all_controls", "collections", "motion_layout" } do
				local scenario = require("../examples/gallery/scenarios/" .. name) :: any
				local built
				local ctx, root, stop = fixture(function(context)
					context.pageVisible = Compose.cell(true)
					built = scenario.build(context)
					return built.screen()
				end)
				local categories = find(root, "Categories", "Frame")
				local function tabViewOf(node: any): any
					local at = node.Parent
					while
						at and not (at:IsA("Frame") and (at.Name == "Categories" or scenarioGroup(scenario, at.Name)))
					do
						at = at.Parent
					end
					return at
				end
				local function labelOf(button: any): string
					return button:GetAttribute("FacetLabel") or button.Text
				end
				local visited = 0
				for _, group in scenario.groups do
					local category = find(categories, group.id, "TextButton")
					t.expect(`{group.id} on the category bar: {tabViewOf(category) == categories}`)
						.toBe(`{group.id} on the category bar: true`)
					t.expect(labelOf(category)).toBe(group.label)
					category.Activated.fire()
					t.expect(built.report().selected.Categories).toBe(group.id)
					local bar = find(categories, group.id, "Frame")
					for _, tab in group.tabs do
						local button = find(bar, tab.id, "TextButton")
						t.expect(`{tab.id} on the {group.id} bar: {tabViewOf(button) == bar}`)
							.toBe(`{tab.id} on the {group.id} bar: true`)
						t.expect(labelOf(button)).toBe(tab.label)
						button.Activated.fire()
						t.expect(built.report().active).toBe(tab.id)
						t.expect(built.report().selected.Categories).toBe(group.id)
						visited += 1
					end
				end
				local expected = 0
				for _, group in scenario.groups do
					expected += #group.tabs
				end
				t.expect(visited).toBe(expected)
				if name == "all_controls" then
					t.expect(expected).toBe(24)
					local labels = {}
					for _, group in scenario.groups do
						labels[group.id] = group.label
					end
					t.expect(labels.indicators).toBe("Status")
					t.expect(labels.navigation).toBe("Menus")
					local statusCategory = find(categories, "indicators", "TextButton")
					local statusTab = find(find(categories, "indicators", "Frame"), "status", "TextButton")
					t.expect(statusCategory ~= statusTab and labelOf(statusCategory) == labelOf(statusTab)).toBe(true)
					find(categories, "navigation", "TextButton").Activated.fire()
					local menus = find(categories, "navigation", "Frame")
					find(menus, "journey", "TextButton").Activated.fire()
					t.expect(built.report().active).toBe("journey")
					ctx.guiService.SelectedObject = find(menus, "journey", "TextButton")
					local shoulder
					for _, node in ctx.inputTarget:GetDescendants() do
						if
							node:IsA("InputContext")
							and node.Name == "FacetNextTab"
							and node.Enabled
							and (shoulder == nil or node.Priority > shoulder.Priority)
						then
							shoulder = node
						end
					end
					assert(shoulder, "the Menus tabs bind ButtonR1")
					shoulder:FindFirstChild("NextTab").Pressed.fire()
					t.expect(built.report().selected.Categories).toBe("navigation")
					t.expect(built.report().active).toBe("pages")
				end
				stop()
			end
		end
	)
end)
