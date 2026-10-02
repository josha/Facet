--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type MotionLevel = typeof(require("@repo/tools/typecheck/aliases").MotionLevel)
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local gallery = require("../examples/gallery/client/screen")
local demoTabs = require("../examples/gallery/scenarios/demo_tabs")
local Compose: ComposeModule = Facet.Compose

local function find(root: any, name: string, class: string?): any
	if root.Name == name and (not class or root:IsA(class)) and not root:GetAttribute("FacetTabPage") then
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

local function disabled(node: any): boolean
	if node:HasTag("facet-disabled") then
		return true
	end
	for _, child in node:GetDescendants() do
		if child:HasTag("facet-disabled") then
			return true
		end
	end
	return false
end

local function openSettings(root: any)
	local function seek(node: any, name: string): any
		if node.Name == name then
			return node
		end
		for _, child in node:GetChildren() do
			local found = seek(child, name)
			if found then
				return found
			end
		end
		return nil
	end
	local layer = root:FindFirstAncestorWhichIsA("LayerCollector") or root
	seek(layer, "Showcase").Activated.fire()
	seek(seek(layer, "Section"), "settings").Activated.fire()
end

local function fixture(build)
	local engine = engineLib.new()
	local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
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
		Host = (runtime.constructors :: unknown) :: RobloxHost,
		types = engine.types,
		viewport = Compose.cell({ width = 1280, height = 720 }),
		inputTarget = target,
		guiService = gui,
		runService = { Heartbeat = engine.heartbeat },
		selection = Compose.cell("first"),
		theme = Compose.cell(Facet.themes.neutralPackage()),
		themeMode = Compose.cell("light"),
	}
	ctx.packages = { Neutral = ctx.theme:peek() } :: { [string]: Facet.ThemePackage }
	local stop, root: any = runtime.mount(function()
		gallery.configure(ctx)
		ctx.UI = Facet.controls(runtime, {
			types = engine.types,
			viewport = ctx.viewport,
			inputParent = target,
			services = { GuiService = gui, UserInputService = input },
			theme = ctx.theme,
			motionLevel = (Compose.formula(function(use: Use): "normal" | "limited" | "none"
				return if ctx.reducedMotion and use(ctx.reducedMotion) then "none" else "normal"
			end) :: unknown) :: MotionLevel,
			environment = ctx.environment,
			overlayParent = ctx.overlayParent,
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
		local function entry(id: string)
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

	t.it("previews a phone, tablet or TV as a device frame that feeds the gallery environment", function()
		local env
		local ctx, root, stop = fixture(function(context)
			context.demos = { { id = "first", title = "First", kind = "fixture" :: "fixture", module = "first" } }
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
			env = context.UI.environment()
			return gallery.build(context)
		end)
		local surface = find(root, "Gallery")
		local scale = find(surface, "ViewingDistance", "UIScale")
		local function expectDevice(width, height, display, input)
			t.expect(surface.Size.X.Offset).toBe(width)
			t.expect(surface.Size.Y.Offset).toBe(height)
			t.expect(surface.Size.X.Scale).toBe(0)
			t.expect(env.viewportSize:peek().X).toBe(width)
			t.expect(env.viewportSize:peek().Y).toBe(height)
			t.expect(ctx.previewViewport:peek().width).toBe(width)
			t.expect(ctx.sceneViewport:peek().height).toBe(height / env.metricScale:peek())
			t.expect(env.displaySize:peek()).toBe(display)
			t.expect(env.effectiveInput:peek()).toBe(input)
		end
		openSettings(root)
		t.expect(find(root, "Preview") ~= nil).toBe(true)
		t.expect(disabled(find(root, "Orientation"))).toBe(true)
		ctx.devicePreview:set("phone")
		expectDevice(389, 762, "Small", "Touch")
		t.expect(disabled(find(root, "Orientation"))).toBe(false)
		t.expect(surface:HasTag("facet-floating")).toBe(true)
		ctx.orientationPreview:set("landscape")
		expectDevice(762, 389, "Small", "Touch")
		ctx.devicePreview:set("tablet")
		expectDevice(1024, 768, "Small", "Touch")
		ctx.orientationPreview:set("portrait")
		expectDevice(768, 1024, "Small", "Touch")
		t.expect(math.abs(scale.Scale - 720 / 1024) < 0.000001).toBe(true)
		local gui: any = ctx.guiService
		local top = 58
		function gui:GetGuiInset()
			return ctx.types.Vector2.new(0, top), ctx.types.Vector2.new(0, 0)
		end
		gui.TopbarInset = top
		t.expect(math.abs(scale.Scale - (720 - 58) / 1024) < 0.000001).toBe(true)
		top = 0
		gui.TopbarInset = top
		ctx.devicePreview:set("tv")
		expectDevice(1920, 1080, "Large", "Gamepad")
		t.expect(disabled(find(root, "Orientation"))).toBe(true)
		t.expect(math.abs(scale.Scale - 2 / 3) < 0.000001).toBe(true)
		ctx.inputPreview:set("KeyboardAndMouse")
		t.expect(env.effectiveInput:peek()).toBe("KeyboardAndMouse")
		ctx.inputPreview:set("automatic")
		ctx.devicePreview:set("automatic")
		t.expect(surface.Size.X.Scale).toBe(1)
		t.expect(scale.Scale).toBe(1)
		t.expect(ctx.previewViewport:peek().width).toBe(1280)
		t.expect(env.effectiveInput:peek()).toBe("KeyboardAndMouse")
		t.expect(surface:HasTag("facet-floating")).toBe(false)
		stop()
	end)

	t.it("toggles the combined menu with one bumper and keeps the chosen section", function()
		local ctx, root, stop = fixture(function(context)
			context.demos = { { id = "first", title = "First", kind = "fixture" :: "fixture", module = "first" } }
			context.load = function()
				return {
					build = function(page)
						return demoTabs(page, "TabsTest", {
							{
								id = "one",
								label = "One",
								scenario = {
									build = function(inner)
										return {
											screen = function()
												return inner.Host.Frame({ Name = "OnePage" })
											end,
										}
									end,
								},
							},
							{
								id = "two",
								label = "Two",
								scenario = {
									build = function(inner)
										return {
											screen = function()
												return inner.Host.Frame({ Name = "TwoPage" })
											end,
										}
									end,
								},
							},
						})
					end,
				}
			end
			return gallery.build(context)
		end)
		find(root, "Categories").AbsoluteSize = ctx.types.Vector2.new(1200, 640)
		local toolbar = find(root, "Toolbar")
		local lb = find(toolbar, "MenuHint")
		t.expect(lb.Text).toBe("LB")
		t.expect(find(toolbar, "SettingsHint")).toBe(nil)
		t.expect(lb.Visible).toBe(false)
		ctx.inputPreview:set("Gamepad")
		t.expect(lb.Visible).toBe(true)
		ctx.inputPreview:set("KeyboardAndMouse")
		local choice = find(toolbar, "ToggleSidebar", "TextButton")
		t.expect(choice ~= nil).toBe(true)
		t.expect(find(find(root, "Categories"), "UseTopTabs")).toBe(nil)
		t.expect(find(find(root, "Categories"), "UseSidebar")).toBe(nil)
		t.expect(choice:GetAttribute("FacetLabel") or choice.Text).toBe("Use top tabs")
		choice.Activated.fire()
		t.expect(choice:GetAttribute("FacetLabel") or choice.Text).toBe("Use sidebar")
		t.expect(ctx.categoryPlacement:peek()).toBe("top")
		choice.Activated.fire()
		t.expect(ctx.categoryPlacement:peek()).toBe("side")
		t.expect(find(root, "ShowcasePanel")).toBe(nil)
		local toggle = find(ctx.inputTarget, "ShowcaseChromeGamepad")
		t.expect(toggle.Priority < 250).toBe(true)
		t.expect(find(ctx.inputTarget, "ShowcaseChromeToggle"):FindFirstChild("ActivateSettings")).toBe(nil)
		t.expect(#toggle:GetChildren()).toBe(1)
		toggle:FindFirstChild("Activate").Pressed.fire()
		t.expect(ctx.panelSection:peek()).toBe("demos")
		find(find(root, "Section"), "settings").Activated.fire()
		toggle:FindFirstChild("Activate").Pressed.fire()
		t.expect(ctx.panelOpen:peek()).toBe(false)
		toggle:FindFirstChild("Activate").Pressed.fire()
		t.expect(ctx.panelSection:peek()).toBe("settings")
		local panel = find(root, "ShowcasePanel")
		t.expect(panel ~= nil and panel:IsDescendantOf(toolbar)).toBe(true)
		t.expect(find(root, "Popover")).toBe(nil)
		for _, name in { "Preview", "Orientation", "Input", "ResetAll", "MotionMode", "Packages" } do
			t.expect(`{name}: {find(panel, name) ~= nil}`).toBe(`{name}: true`)
		end
		for _, name in { "ViewingDistance", "CategoryPlacement", "TextPreview" } do
			t.expect(`{name}: {find(panel, name) ~= nil}`).toBe(`{name}: false`)
		end
		local preview = find(panel, "Preview")
		t.expect(find(preview, "Trigger") ~= nil).toBe(true)
		t.expect(panel:HasTag("facet-floating") and panel:FindFirstChildWhichIsA("UIStroke") ~= nil).toBe(true)

		ctx.viewingDistance:set("ten-foot")
		preview = find(panel, "Preview")
		t.expect(find(preview, "Trigger") == nil and find(preview, "desktop") ~= nil).toBe(true)
		ctx.viewingDistance:set("automatic")
		ctx.devicePreview:set("phone")
		ctx.inputPreview:set("Touch")
		find(panel, "ResetAll").Activated.fire()
		t.expect(ctx.devicePreview:peek()).toBe("automatic")
		t.expect(ctx.inputPreview:peek()).toBe("automatic")
		t.expect(#toggle:GetChildren()).toBe(1)
		toggle:FindFirstChild("Activate").Pressed.fire()
		t.expect(ctx.panelOpen:peek()).toBe(false)
		t.expect(find(root, "ShowcasePanel")).toBe(nil)
		toggle:FindFirstChild("Activate").Pressed.fire()
		t.expect(ctx.panelSection:peek()).toBe("settings")
		find(find(root, "Section"), "demos").Activated.fire()
		t.expect(find(root, "Demo-first") ~= nil).toBe(true)
		find(root, "ShowcaseDismiss").Activated.fire()
		t.expect(find(root, "ShowcasePanel")).toBe(nil)
		find(ctx.inputTarget, "ShowcaseChromeToggle"):FindFirstChild("Activate").Pressed.fire()
		t.expect(find(root, "ShowcasePanel") ~= nil).toBe(true)
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
				{ id = "first", title = "First", kind = "fixture" :: "fixture", module = "first" },
				{ id = "second", title = "Second", kind = "fixture" :: "fixture", module = "second" },
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
		local settings = find(root, "Showcase", "TextButton")
		local near = settings.Size.Y.Offset
		t.expect(ctx.environment.viewingDistance).toBe(ctx.viewingDistance)
		ctx.viewingDistance:set("ten-foot")
		t.expect(scale.Scale).toBe(1)
		t.expect(settings.Size.Y.Offset).toBe(near * 1.5)
		t.expect(find(root, "first")).toBe(before)
		ctx.viewingDistance:set("near")
		t.expect(settings.Size.Y.Offset).toBe(near)
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
		openSettings(root)
		t.expect(find(root, "P_Second"):GetAttribute("selected")).toBe(true)
		t.expect(find(root, "P_Neutral"):GetAttribute("selected")).toBe(false)
		gallery.dispatch(ctx, "next")
		t.expect(ctx.active:peek()).toBe("second")
		stop()
	end)

	t.it("keeps gallery motion preview synchronized with native accessibility preferences", function()
		local ctx, _, stop = fixture(function(context)
			return context.Host.Frame "MotionTest" {}
		end)
		t.expect(ctx.reducedMotion:peek()).toBe(false)
		ctx.motionPreference:set("none")
		t.expect(ctx.reducedMotion:peek()).toBe(true)
		t.expect(ctx.motionLevel:peek()).toBe("none")
		ctx.motionPreference:set(nil)
		t.expect(ctx.reducedMotion:peek()).toBe(false)
		ctx.guiService.ReducedMotionEnabled = true
		t.expect(ctx.reducedMotion:peek()).toBe(true)
		t.expect(ctx.motionLevel:peek()).toBe("limited")
		ctx.motionPreference:set("normal")
		t.expect(ctx.reducedMotion:peek()).toBe(true)
		t.expect(ctx.motionLevel:peek()).toBe("limited")
		ctx.motionPreference:set(nil)
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
						at
						and not (
							at:IsA("Frame")
							and not at:GetAttribute("FacetTabPage")
							and (at.Name == "Categories" or scenarioGroup(scenario, at.Name))
						)
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
