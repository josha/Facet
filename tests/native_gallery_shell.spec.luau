--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type MotionLevel = typeof(require("@repo/tools/typecheck/aliases").MotionLevel)
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

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

	verifyHarness:suite("native gallery shell parity", function()
		verifyHarness:case("reports the selected retained leaf and propagates ancestor page visibility", {
			id = "native_gallery_shell::native gallery shell parity::reports the selected retained leaf and propagates ancestor page visibility",
			run = function()
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
				button.Activated:Fire()
				find(root, "b", "TextButton").Activated:Fire()
				Verify.expect(built.report().active):toBe("b")
				Verify.expect((contexts.a.pageVisible:peek())):toBe(false)
				find(root, "a", "TextButton").Activated:Fire()
				Verify.expect(built.report().active):toBe("a")
				Verify.expect(built.report().example.clicks):toBe(1)
				Verify.expect((find(root, "aAction"))):toBe(button)
				Verify.expect(counts.a):toBe(1)
				Verify.expect((contexts.a.pageVisible:peek())):toBe(true)
				find(root, "other", "TextButton").Activated:Fire()
				Verify.expect((contexts.a.pageVisible:peek())):toBe(false)
				Verify.expect(built.report().active):toBe("other")
				ctx.pageVisible:set(false)
				Verify.expect((contexts.other.pageVisible:peek())):toBe(false)
				stop()
			end,
		})

		verifyHarness:case("toggles the combined menu with one bumper and keeps the chosen section", {
			id = "native_gallery_shell::native gallery shell parity::toggles the combined menu with one bumper and keeps the chosen section",
			run = function()
				local ctx, root, stop = fixture(function(context)
					context.demos =
						{ { id = "first", title = "First", kind = "fixture" :: "fixture", module = "first" } }
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
				Verify.expect(lb.Text):toBe("LB")
				Verify.expect((find(toolbar, "SettingsHint"))):toBe(nil)
				Verify.expect(lb.Visible):toBe(false)
				ctx.inputPreview:set("Gamepad")
				Verify.expect(lb.Visible):toBe(true)
				ctx.inputPreview:set("KeyboardAndMouse")
				local choice = find(toolbar, "ToggleSidebar", "TextButton")
				Verify.expect(choice ~= nil):toBe(true)
				Verify.expect((find(find(root, "Categories"), "UseTopTabs"))):toBe(nil)
				Verify.expect((find(find(root, "Categories"), "UseSidebar"))):toBe(nil)
				Verify.expect(choice:GetAttribute("FacetLabel") or choice.Text):toBe("Use top tabs")
				choice.Activated:Fire()
				Verify.expect(choice:GetAttribute("FacetLabel") or choice.Text):toBe("Use sidebar")
				Verify.expect((ctx.categoryPlacement:peek())):toBe("top")
				choice.Activated:Fire()
				Verify.expect((ctx.categoryPlacement:peek())):toBe("side")
				Verify.expect((find(root, "ShowcasePanel"))):toBe(nil)
				local toggle = find(ctx.inputTarget, "ShowcaseChromeGamepad")
				Verify.expect(toggle.Priority < 250):toBe(true)
				Verify.expect((find(ctx.inputTarget, "ShowcaseChromeToggle"):FindFirstChild("ActivateSettings")))
					:toBe(nil)
				Verify.expect(#toggle:GetChildren()):toBe(1)
				toggle:FindFirstChild("Activate").Pressed:Fire()
				Verify.expect((ctx.panelSection:peek())):toBe("demos")
				find(find(root, "Section"), "settings").Activated:Fire()
				toggle:FindFirstChild("Activate").Pressed:Fire()
				Verify.expect((ctx.panelOpen:peek())):toBe(false)
				toggle:FindFirstChild("Activate").Pressed:Fire()
				Verify.expect((ctx.panelSection:peek())):toBe("settings")
				local panel = find(root, "ShowcasePanel")
				Verify.expect(panel ~= nil and panel:IsDescendantOf(ctx.overlayParent)):toBe(true)
				Verify.expect(panel.ClassName):toBe("Frame")
				local expanded = find(root, "Expanded")
				local scrolling = find(expanded, "ExpandedScroll")
				Verify.expect(scrolling.ClassName):toBe("ScrollingFrame")
				Verify.expect((scrolling:HasTag("facet-panel"))):toBe(false)
				local inset = find(expanded, "ExpandedBody"):FindFirstChildWhichIsA("UIPadding")
				Verify.expect(inset.PaddingTop.Offset > 0 and inset.PaddingLeft.Offset > 0):toBe(true)
				Verify.expect((find(root, "Popover"))):toBe(nil)
				for _, name in { "Preview", "Orientation", "Input", "ResetAll", "MotionMode", "Packages" } do
					Verify.expect(`{name}: {find(panel, name) ~= nil}`):toBe(`{name}: true`)
				end
				for _, name in { "ViewingDistance", "CategoryPlacement", "TextPreview" } do
					Verify.expect(`{name}: {find(panel, name) ~= nil}`):toBe(`{name}: false`)
				end
				local preview = find(panel, "Preview")
				Verify.expect(find(preview, "Trigger") ~= nil):toBe(true)
				Verify.expect(expanded:HasTag("facet-floating") and expanded.ClipsDescendants):toBe(true)

				ctx.viewingDistance:set("ten-foot")
				preview = find(panel, "Preview")
				Verify.expect(find(preview, "Trigger") == nil and find(preview, "desktop") ~= nil):toBe(true)
				ctx.viewingDistance:set("automatic")
				ctx.devicePreview:set("phone")
				ctx.inputPreview:set("Touch")
				find(panel, "ResetAll").Activated:Fire()
				Verify.expect((ctx.devicePreview:peek())):toBe("automatic")
				Verify.expect((ctx.inputPreview:peek())):toBe("automatic")
				Verify.expect(#toggle:GetChildren()):toBe(1)
				toggle:FindFirstChild("Activate").Pressed:Fire()
				Verify.expect((ctx.panelOpen:peek())):toBe(false)
				Verify.expect((find(root, "ShowcasePanel"))):toBe(nil)
				toggle:FindFirstChild("Activate").Pressed:Fire()
				Verify.expect((ctx.panelSection:peek())):toBe("settings")
				find(find(root, "Section"), "demos").Activated:Fire()
				Verify.expect(find(root, "Demo-first") ~= nil):toBe(true)
				find(root, "DismissOutside").Activated:Fire()
				Verify.expect((find(root, "ShowcasePanel"))):toBe(nil)
				find(ctx.inputTarget, "ShowcaseChromeToggle"):FindFirstChild("Activate").Pressed:Fire()
				Verify.expect(find(root, "ShowcasePanel") ~= nil):toBe(true)
				stop()
			end,
		})

		verifyHarness:case(
			"names the Status and Menus categories on the category bar and visits every inner tab through its own bar",
			{
				id = "native_gallery_shell::native gallery shell parity::names the Status and Menus categories on the category bar and visits every inner tab through its own bar",
				run = function()
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
							Verify.expect(`{group.id} on the category bar: {tabViewOf(category) == categories}`)
								:toBe(`{group.id} on the category bar: true`)
							Verify.expect((labelOf(category))):toBe(group.label)
							category.Activated:Fire()
							Verify.expect(built.report().selected.Categories):toBe(group.id)
							local bar = find(categories, group.id, "Frame")
							for _, tab in group.tabs do
								local button = find(bar, tab.id, "TextButton")
								Verify.expect(`{tab.id} on the {group.id} bar: {tabViewOf(button) == bar}`)
									:toBe(`{tab.id} on the {group.id} bar: true`)
								Verify.expect((labelOf(button))):toBe(tab.label)
								button.Activated:Fire()
								Verify.expect(built.report().active):toBe(tab.id)
								Verify.expect(built.report().selected.Categories):toBe(group.id)
								visited += 1
							end
						end
						local expected = 0
						for _, group in scenario.groups do
							expected += #group.tabs
						end
						Verify.expect(visited):toBe(expected)
						if name == "all_controls" then
							Verify.expect(expected):toBe(24)
							local labels = {}
							for _, group in scenario.groups do
								labels[group.id] = group.label
							end
							Verify.expect(labels.indicators):toBe("Status")
							Verify.expect(labels.navigation):toBe("Menus")
							local statusCategory = find(categories, "indicators", "TextButton")
							local statusTab = find(find(categories, "indicators", "Frame"), "status", "TextButton")
							Verify.expect(statusCategory ~= statusTab and labelOf(statusCategory) == labelOf(statusTab))
								:toBe(true)
							find(categories, "navigation", "TextButton").Activated:Fire()
							local menus = find(categories, "navigation", "Frame")
							find(menus, "journey", "TextButton").Activated:Fire()
							Verify.expect(built.report().active):toBe("journey")
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
							shoulder:FindFirstChild("NextTab").Pressed:Fire()
							Verify.expect(built.report().selected.Categories):toBe("navigation")
							Verify.expect(built.report().active):toBe("pages")
						end
						stop()
					end
				end,
			}
		)
	end)
end
