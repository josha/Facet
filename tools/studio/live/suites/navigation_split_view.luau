--!strict
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local function api(command: string, argument: any?): any
	return (workspace:WaitForChild("FacetShowcaseAPI") :: any):Invoke(command, argument)
end
local cases: { any } = {
	{
		id = "files-grid-action-bounds",
		contracts = {},
		run = function(t: any)
			for _, theme in t.themes do
				local stage = t.mount(function(UI: any, Host: any, C: any, env: any)
					return require(game.ReplicatedStorage.FacetScenarios.collection_workbench)
						.build(t.context(UI, Host, C, env))
						.screen()
				end, {
					theme = theme.package,
					size = Vector2.new(393, 844),
					environment = { preferredInput = "Touch", viewportSize = Vector2.new(393, 844) },
				})
				local menu = t.find(stage, "ViewOptions")
				t.check(theme.name .. " view choices stay visible", t.visible(menu) and t.find(stage, "Filters") == nil)
				t.inside(theme.name .. " Views button bounds", menu, stage)
				local count = 0
				for _, button in t.all(stage, "CellActions") do
					if not button.Visible then
						continue
					end
					local cell = button.Parent:FindFirstChild("FileCell", true)
					if not cell then
						continue
					end
					count += 1
					local label = theme.name .. " card " .. count
					t.inside(label .. " action stays inside", button, button.Parent)
					t.near(label .. " content keeps full width", cell.AbsoluteSize.X, button.Parent.AbsoluteSize.X)
					t.check(
						label .. " content clears action",
						cell.AbsolutePosition.Y + cell.AbsoluteSize.Y <= button.AbsolutePosition.Y + 0.5
					)
				end
				t.check(theme.name .. " checked editable tiles", count >= 2)
			end
		end,
	},
	{
		id = "resize-options",
		contracts = {},
		run = function(t: any)
			for _, theme in t.themes do
				for _, axis in { "x", "y" } do
					local C = t.Facet.Compose
					local resizable, always = C.cell(true), C.cell(true)
					local stage = t.mount(function(UI: any)
						return UI.NavigationSplitView {
							Name = "OptionsSplit",
							axis = axis,
							resizable = resizable,
							alwaysShowResizeHandle = always,
							sidebar = function()
								return UI.Button { Name = "Source", label = "Files" }
							end,
							detail = function()
								return UI.Button { Name = "Result", label = "Inbox" }
							end,
						}
					end, {
						theme = theme.package,
						size = Vector2.new(1000, 640),
						environment = { viewingDistance = "near", preferredInput = "KeyboardAndMouse" },
					})
					local root = t.find(stage, "OptionsSplit")
					local name = theme.name .. axis
					t.check(name .. " persistent grip", root.Resize.Grip.Pill.Visible)
					t.inside(name .. " grip bounds", root.Resize.Grip, root.Resize)
					GuiService.SelectedObject = t.find(root.Sidebar, "Source")
					GuiService.SelectedObject = root.Resize
					resizable:set(false)
					t.settle()
					t.check(
						name .. " disabled input",
						not root.Resize.Selectable
							and not root.Resize.Active
							and not root.Resize:FindFirstChildWhichIsA("UIDragDetector").Enabled
					)
					t.check(name .. " disabled grip", not root.Resize.Grip.Visible)
					t.check(name .. " focus leaves divider", GuiService.SelectedObject ~= root.Resize)
					t.near(
						name .. " thin separator",
						if axis == "x" then root.Resize.AbsoluteSize.X else root.Resize.AbsoluteSize.Y,
						1
					)
					GuiService.SelectedObject = t.find(root.Detail, "Result")
					t.check(
						name .. " direct pane traversal",
						GuiService.SelectedObject == t.find(root.Detail, "Result")
					)
					resizable:set(true)
					t.settle()
					t.check(name .. " resizing restored", root.Resize.Selectable and root.Resize.Grip.Visible)
				end
			end
		end,
	},
	{
		id = "files-editor-first-focus",
		contracts = {},
		run = function(t: any)
			for _, theme in t.themes do
				if theme.name ~= "Neutral" and theme.name ~= "fantasy_parchment" then
					continue
				end
				local stage = t.mount(function(UI: any, Host: any, C: any, env: any)
					local built = require(game.ReplicatedStorage.FacetScenarios.collection_workbench).build(
						t.context(UI, Host, C, env)
					)
					built.model.linked:set(true)
					built.model.transfers:set(true)
					return built.screen()
				end, { theme = theme.package, size = Vector2.new(1340, 850) })
				local editor = t.find(t.find(stage, "PrimaryView"), "Rename")
				t.check(theme.name .. " starts without a field", editor:FindFirstChildWhichIsA("TextBox", true) == nil)
				require(game.ReplicatedStorage.Facet.ui.activation).edits(editor)[1].onActivate()
				t.settle()
				local field = editor:FindFirstChildWhichIsA("TextBox", true)
				t.check(theme.name .. " first edit stays open", editor.EditorHost.Visible and not editor.Value.Visible)
				t.check(
					theme.name .. " first edit owns native focus",
					field:IsFocused() and GuiService.SelectedObject == field
				)
				field:ReleaseFocus(false)
				t.settle()
				t.check(
					theme.name .. " closing keeps the editor",
					editor:FindFirstChildWhichIsA("TextBox", true) == field
				)
				t.check(theme.name .. " closing restores row focus", GuiService.SelectedObject ~= field)
			end
		end,
	},
	{
		id = "inline-editor-retention",
		contracts = {},
		run = function(t: any)
			for _, theme in t.themes do
				if theme.name ~= "Neutral" and theme.name ~= "fantasy_parchment" then
					continue
				end
				local Compose = t.Facet.Compose
				local editing, input = Compose.cell(false), Compose.cell("KeyboardAndMouse")
				local editor
				local stage = t.mount(function(UI: any)
					editor = UI.CellEditor {
						editor = "text",
						value = "A long file name for the linked view",
						editing = editing,
						onChange = function() end,
					}
					return editor
				end, {
					theme = theme.package,
					size = Vector2.new(240, 100),
					environment = { preferredInput = input },
				})
				t.settle()
				t.check(
					theme.name .. " display has no native editor",
					editor:FindFirstChildWhichIsA("TextBox", true) == nil
				)
				local field
				for _, kind in { "KeyboardAndMouse", "Touch", "Gamepad" } do
					input:set(kind)
					t.settle()
					local height = editor.AbsoluteSize.Y
					editing:set(true)
					t.settle()
					local current = editor:FindFirstChildWhichIsA("TextBox", true)
					t.check(theme.name .. kind .. " mounts editor", current ~= nil)
					t.check(theme.name .. kind .. " retains editor", field == nil or field == current)
					field = current
					t.near(theme.name .. kind .. " editing height", editor.AbsoluteSize.Y, height)
					t.inside(theme.name .. kind .. " field inside cell", current, editor)
					editing:set(false)
					t.settle()
					t.near(theme.name .. kind .. " display height", editor.AbsoluteSize.Y, height)
					t.check(
						theme.name .. kind .. " field retained after editing",
						editor:FindFirstChildWhichIsA("TextBox", true) == field
					)
					t.inside(theme.name .. kind .. " cell inside viewport", editor, stage)
				end
			end
		end,
	},
	{
		id = "three-pane-layout",
		contracts = {},
		run = function(t: any)
			for _, theme in t.themes do
				if theme.name ~= "Neutral" and theme.name ~= "fantasy_parchment" then
					continue
				end
				local Compose = t.Facet.Compose
				local size, distance, input =
					Compose.cell(Vector2.new(1340, 850)), Compose.cell("near"), Compose.cell("KeyboardAndMouse")
				local stage = t.mount(function(UI: any, Host: any, C: any, env: any)
					local built = require(game.ReplicatedStorage.FacetScenarios.collection_workbench).build(
						t.context(UI, Host, C, env)
					)
					built.model.linked:set(true)
					built.model.transfers:set(true)
					return built.screen()
				end, {
					theme = theme.package,
					size = size,
					environment = { viewingDistance = distance, preferredInput = input },
				})
				local outer, inner = t.find(stage, "Views"), t.find(stage, "PrimaryViews")
				local files, inbox, linked =
					t.find(stage, "PrimaryView"), t.find(stage, "InboxView"), t.find(stage, "LinkedView")
				for _, device in
					{
						{
							name = "desktop",
							size = Vector2.new(1340, 850),
							distance = "near",
							input = "KeyboardAndMouse",
						},
						{ name = "tablet", size = Vector2.new(1024, 768), distance = "near", input = "Touch" },
						{ name = "phone", size = Vector2.new(390, 844), distance = "near", input = "Touch" },
						{ name = "landscape", size = Vector2.new(844, 390), distance = "near", input = "Touch" },
						{ name = "console", size = Vector2.new(1920, 1080), distance = "ten-foot", input = "Gamepad" },
					}
				do
					size:set(device.size)
					distance:set(device.distance)
					input:set(device.input)
					t.settle(12)
					local label = theme.name .. " " .. device.name
					for _, split in { outer, inner } do
						local collapsed = split:GetAttribute("FacetSplitCollapsed")
						t.check(
							label .. " divider matches layout " .. split.Name,
							split.Resize.Visible == not collapsed
						)
						for _, pane in { split.Sidebar, split.Detail } do
							if pane.Visible then
								t.inside(label .. " pane bounds " .. split.Name .. pane.Name, pane, split)
							end
						end
					end
					if device.name == "desktop" then
						t.check(
							label .. " all three visible",
							t.visible(files) and t.visible(inbox) and t.visible(linked)
						)
					elseif device.name == "phone" or device.name == "console" then
						t.check(
							label .. " both splits collapse",
							outer:GetAttribute("FacetSplitCollapsed") and inner:GetAttribute("FacetSplitCollapsed")
						)
					end
					t.check(
						label .. " panes retained",
						t.find(stage, "PrimaryView") == files
							and t.find(stage, "InboxView") == inbox
							and t.find(stage, "LinkedView") == linked
					)
				end
			end
		end,
	},
	{
		id = "stacked-layout-and-retention",
		contracts = {},
		run = function(t: any)
			for _, theme in t.themes do
				local C = t.Facet.Compose
				local size, height, column = C.cell(Vector2.new(900, 640)), C.cell(240), C.cell("sidebar")
				local stage = t.mount(function(UI: any)
					return UI.NavigationSplitView {
						Name = "Stacked",
						axis = "y",
						sidebarHeight = height,
						preferredCompactColumn = column,
						sidebar = function()
							return UI.Button { Name = "TopItem", label = "Files" }
						end,
						detail = function()
							return UI.Button { Name = "BottomItem", label = "Inbox" }
						end,
					}
				end, { theme = theme.package, size = size, environment = { viewingDistance = "near" } })
				local root = t.find(stage, "Stacked")
				local top, bottom = root.Sidebar, root.Detail
				t.check(theme.name .. " stacked panes visible", top.Visible and bottom.Visible and root.Resize.Visible)
				t.near(theme.name .. " top height", top.AbsoluteSize.Y, 240)
				t.inside(theme.name .. " top bounds", top, root)
				t.inside(theme.name .. " bottom bounds", bottom, root)
				t.check(
					theme.name .. " stacked panes do not overlap",
					top.AbsolutePosition.Y + top.AbsoluteSize.Y <= root.Resize.AbsolutePosition.Y
						and root.Resize.AbsolutePosition.Y + root.Resize.AbsoluteSize.Y <= bottom.AbsolutePosition.Y
				)
				t.check(
					theme.name .. " horizontal focus grip",
					root.Resize.Grip.AbsoluteSize.X > root.Resize.Grip.AbsoluteSize.Y
				)
				size:set(Vector2.new(390, 640))
				t.settle(20)
				t.check(theme.name .. " portrait keeps stacked panes", not root:GetAttribute("FacetSplitCollapsed"))
				height:set(10000)
				t.settle(20)
				t.check(theme.name .. " bottom keeps minimum height", bottom.AbsoluteSize.Y >= 120)
				size:set(Vector2.new(844, 310))
				t.settle(20)
				t.check(theme.name .. " short panes still fit", top.Visible and bottom.Visible and root.Resize.Visible)
				t.check(
					theme.name .. " short panes keep minimums",
					top.AbsoluteSize.Y >= 120 and bottom.AbsoluteSize.Y >= 120
				)
				column:set("detail")
				size:set(Vector2.new(844, 230))
				t.settle(20)
				t.check(
					theme.name .. " short layout collapses",
					root:GetAttribute("FacetSplitCollapsed")
						and not top.Visible
						and bottom.Visible
						and not root.Resize.Visible
				)
				size:set(Vector2.new(900, 640))
				t.settle(20)
				t.check(
					theme.name .. " stacked panes retained",
					root.Sidebar == top and root.Detail == bottom and top.Visible and bottom.Visible
				)
			end
		end,
	},
	{
		id = "geometry-feedback",
		contracts = {},
		run = function(t: any)
			local observe = require(game.ReplicatedStorage.Facet.ui.geometry_observation)
			local node, size
			t.mount(function(_UI: any, Host: any, Compose: any, env: any)
				node = Host.Frame { Size = UDim2.fromOffset(100, 40) }
				size = observe(Compose, env.runtime, node, "AbsoluteSize")
				Compose.watch(function(use: any)
					local width = use(size).X
					if width > 0 and width < 200 then
						node.Size = UDim2.fromOffset(width + 1, 40)
					end
				end)
				return node
			end)
			t.settle(220)
			t.check("feedback survives the deferred callback depth limit", (size:peek() :: Vector2).X == 200)
			node.Size = UDim2.fromOffset(240, 40)
			t.settle()
			t.check("geometry still updates after feedback", (size:peek() :: Vector2).X == 240)
		end,
	},
	{
		id = "geometry-publication",
		contracts = {},
		run = function(t: any)
			local observe = require(game.ReplicatedStorage.Facet.ui.geometry_observation)
			local first, second, firstSize, secondSize, shown
			local runs, lastFirst, lastSecond = 0, 0, 0
			local order = {}
			t.mount(function(_UI: any, Host: any, Compose: any, env: any)
				shown = Compose.cell(true)
				return Host.Frame {
					Size = UDim2.fromScale(1, 1),
					Compose.show(shown, function()
						first = Host.Frame { Size = UDim2.fromOffset(100, 40) }
						second = Host.Frame { Size = UDim2.fromOffset(200, 40) }
						local observation = env.runtime.host.observation
						local read = observation.readProperty
						observation.readProperty = function(node: Instance, property: string)
							if (node == first or node == second) and property == "AbsoluteSize" then
								table.insert(order, "read")
							end
							return read(node, property)
						end
						Compose.cleanup(function()
							observation.readProperty = read
						end)
						firstSize = observe(Compose, env.runtime, first, "AbsoluteSize")
						secondSize = observe(Compose, env.runtime, second, "AbsoluteSize")
						local other = t.Facet.Roblox.createRuntime()
						local subscriber = Compose.createRootOwner(function()
							Compose.watch(function(use: any)
								use(firstSize)
								use(secondSize)
								table.insert(order, "publish")
							end)
						end, other.reactor)
						Compose.cleanup(function()
							subscriber.dispose()
							other:dispose()
						end)
						t.check(
							"initial geometry uses the native snapshot",
							(firstSize:peek() :: Vector2) == first.AbsoluteSize
								and (secondSize:peek() :: Vector2) == second.AbsoluteSize
						)
						Compose.watch(function(use: any)
							runs += 1
							lastFirst, lastSecond = use(firstSize).X, use(secondSize).X
						end)
						return Host.Frame { first, second }
					end),
				}
			end)
			t.check("initial geometry is published", lastFirst == 100 and lastSecond == 200)
			local before = runs
			table.clear(order)
			first.Size = UDim2.fromOffset(150, 40)
			second.Size = UDim2.fromOffset(250, 40)
			t.check("native geometry changed", first.AbsoluteSize.X == 150 and second.AbsoluteSize.X == 250)
			first.Size = UDim2.fromOffset(175, 40)
			t.check("native geometry changed again", first.AbsoluteSize.X == 175)
			t.check("layout dispatch does not run bindings", runs == before)
			t.settle()
			t.check(
				"reads geometry before publishing to another reactor",
				order[1] == "read" and order[2] == "read" and order[3] == "publish"
			)
			t.check("geometry publishes together once", runs == before + 1 and lastFirst == 175 and lastSecond == 250)
			first.Size = UDim2.fromOffset(180, 40)
			t.check("disposal has a pending measurement", first.AbsoluteSize.X == 180)
			shown:set(false)
			before = runs
			t.settle()
			t.check("disposed geometry does not publish", runs == before and (firstSize:peek() :: Vector2).X == 175)
		end,
	},
	{
		id = "split-layout-and-retention",
		contracts = {},
		run = function(t: any)
			for _, theme in t.themes do
				local width, column, size, distance, shown
				local count = 0
				local stage = t.mount(
					function(UI: any, Host: any, Compose: any)
						width, column, shown = Compose.cell(360), Compose.cell("sidebar"), Compose.cell(true)
						size, distance = Compose.cell(Vector2.new(1000, 600)), Compose.cell("near")
						return UI.NavigationSplitView {
							Name = "Split",
							sidebarWidth = width,
							preferredCompactColumn = column,
							detailVisible = shown,
							Size = function(use: any)
								local s = use(size)
								return UDim2.fromOffset(s.X, s.Y)
							end,
							sidebar = function()
								count += 1
								return UI.Button { Name = "Source", label = "Files" }
							end,
							detail = function()
								count += 1
								return UI.Button { Name = "Result", label = "Linked files" }
							end,
						}
					end,
					{ theme = theme.package, size = Vector2.new(1100, 800), environment = { viewingDistance = "near" } }
				)
				local root = t.find(stage, "Split")
				local sidebar, detail = root.Sidebar, root.Detail
				t.near(theme.name .. " initial sidebar", sidebar.AbsoluteSize.X, 360)
				width:set(10000)
				t.settle()
				t.near(theme.name .. " max width", sidebar.AbsoluteSize.X, 600)
				t.check(theme.name .. " detail minimum", detail.AbsoluteSize.X >= 320)
				size:set(Vector2.new(640, 360))
				t.settle()
				t.check(
					theme.name .. " landscape panes still fit",
					sidebar.Visible and detail.Visible and root.Resize.Visible
				)
				t.check(
					theme.name .. " landscape pane minimums",
					sidebar.AbsoluteSize.X >= 240 and detail.AbsoluteSize.X >= 320
				)
				t.inside(theme.name .. " landscape sidebar bounds", sidebar, root)
				t.inside(theme.name .. " landscape detail bounds", detail, root)
				column:set("detail")
				size:set(Vector2.new(390, 650))
				t.settle()
				t.check(
					theme.name .. " compact detail only",
					not sidebar.Visible and detail.Visible and not root.Resize.Visible
				)
				t.inside(theme.name .. " compact detail bounds", detail, root)
				column:set("sidebar")
				t.settle()
				t.check(theme.name .. " compact sidebar only", sidebar.Visible and not detail.Visible)
				size:set(Vector2.new(1000, 600))
				t.settle()
				t.check(
					theme.name .. " retained panes",
					root.Sidebar == sidebar and root.Detail == detail and count == 2
				)
				t.check(
					theme.name .. " divider focus part",
					root.Resize:GetAttribute("FacetFocusPart") == "Grip"
						and not root.Resize.Grip.Selectable
						and not root.Resize.Grip.Active
						and root.Resize.Grip:IsA("Frame")
				)
				shown:set(false)
				t.settle()
				t.near(theme.name .. " single pane fills", sidebar.AbsoluteSize.X, root.AbsoluteSize.X)
			end
		end,
	},
	{
		id = "files-theme-bounds",
		contracts = {},
		run = function(t: any)
			local stage = t.mount(function(UI: any, Host: any, C: any, env: any)
				local built = require(game.ReplicatedStorage.FacetScenarios.collection_workbench).build(
					t.context(UI, Host, C, env)
				)
				built.model.linked:set(true)
				return built.screen()
			end, { size = Vector2.new(1340, 850), environment = { preferredInput = "Touch" }, frames = 20 })
			t.settle(20)
			local root = t.find(stage, "Views")
			t.check("Files uses NavigationSplitView", root ~= nil and root:GetAttribute("FacetSplitCollapsed") ~= nil)
			if not root then
				return
			end
			local detail = root:FindFirstChild("Detail")
			t.check("linked detail exists", detail ~= nil)
			if not detail then
				return
			end
			t.inside("detail stays inside split", detail, root)
			local checked = 0
			for _, button in detail:GetDescendants() do
				if button.Name ~= "CellActions" or not button:IsA("GuiObject") or not button.Visible then
					continue
				end
				local details = button.Parent:FindFirstChild("FileCell", true)
				if details and details:IsA("GuiObject") and details.Visible then
					checked += 1
					t.check(
						"row actions do not cover details " .. checked,
						details.AbsolutePosition.X + details.AbsoluteSize.X <= button.AbsolutePosition.X + 0.5
					)
					t.inside("row actions stay inside row " .. checked, button, button.Parent)
				end
			end
			t.check("checked compact row actions", checked > 0)
		end,
	},
	{
		id = "files-linked-input",
		contracts = {},
		keepGallery = true,
		setup = function(t: any)
			api("show", "files")
			t.settle(20)
			local layer = Players.LocalPlayer.PlayerGui:WaitForChild("FacetGallery")
			local root = t.find(layer, "Views")
			t.check("Files uses NavigationSplitView", root ~= nil and root:GetAttribute("FacetSplitCollapsed") ~= nil)
			return { root = root, layer = layer, width = 360 }
		end,
		steps = {
			wide = function(t: any, s: any)
				t.check(
					"linked columns are visible",
					s.root.Sidebar.Visible and s.root.Detail.Visible and s.root.Resize.Visible
				)
				t.inside("sidebar bounds", s.root.Sidebar, s.root)
				t.inside("detail bounds", s.root.Detail, s.root)
				s.width = s.root.Sidebar.AbsoluteSize.X
			end,
			resized = function(t: any, s: any)
				t.check(
					"real input resized the split",
					math.abs(s.width - s.root.Sidebar.AbsoluteSize.X) >= 8,
					{ before = s.width, after = s.root.Sidebar.AbsoluteSize.X }
				)
				t.check("focus stays on divider", GuiService.SelectedObject == s.root.Resize)
			end,
			divider = function(t: any, s: any)
				t.check(
					"pane crossing stops at divider",
					GuiService.SelectedObject == s.root.Resize,
					GuiService.SelectedObject
				)
				t.check("ring targets grip", s.root.Resize:GetAttribute("FacetFocusPart") == "Grip")
			end,
			compact = function(t: any, s: any)
				t.check("collapsed", s.root:GetAttribute("FacetSplitCollapsed") == true)
				t.check(
					"only detail shown",
					s.root.Detail.Visible and not s.root.Sidebar.Visible and not s.root.Resize.Visible
				)
				t.check("Back available", t.find(s.root, "Back") ~= nil)
			end,
			back = function(t: any, s: any)
				t.check("Back shows source", s.root.Sidebar.Visible and not s.root.Detail.Visible)
				local selected = GuiService.SelectedObject
				t.check("Back restores sidebar focus", selected ~= nil and selected:IsDescendantOf(s.root.Sidebar))
				t.check("can reopen linked view", t.find(s.root, "ShowDetail") ~= nil)
				t.check("folder root has no Back", not t.find(s.root.Parent.Parent.NavigationBar, "Back"))
			end,
		},
	},
}

return cases
