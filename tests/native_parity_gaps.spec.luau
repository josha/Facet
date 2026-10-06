--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type SheetDetent = typeof(require("@repo/tools/typecheck/aliases").SheetDetent)
	local FixtureCollectionTypes = require("../src/ui/collection_types")
	local FixtureNavigationTypes = require("../src/ui/navigation_types")

	local fs = require("@lune/fs")
	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
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

	local helpers: { [string]: boolean } = {
		fill = true,
		badged = true,
		environment = true,
		worldAnchor = true,
		scrollTo = true,
		scrollToVisible = true,
		focusRing = true,
		adjustable = true,
		feedback = true,
		focusSection = true,
		focusQuery = true,
		responder = true,
		draggable = true,
		dropTarget = true,
	}

	local function world(build: (any, any, any) -> any, options: { [string]: any }?): World
		local engine: any = engineLib.new()
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

	local function mountError(build: (any, any) -> any): string?
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local UI =
			Facet.controls(runtime, { types = engine.types, guiService = gui, services = { GuiService = gui } } :: any)
		local Host = (runtime.constructors :: unknown) :: RobloxHost
		local ok, message = pcall(function()
			local stop = runtime.mount(function()
				return Host.Frame({ build(UI, Host) })
			end, engine.new("ScreenGui"))
			stop()
		end)
		runtime:dispose()
		return if ok then nil else tostring(message)
	end

	local function records(count: number): { { id: number, label: string } }
		local values = {}
		for index = 1, count do
			values[index] = { id = index, label = `Row {index}` }
		end
		return values
	end

	local function minimalSpecs(Host: any): { [string]: () -> { [any]: any } }
		local function content()
			return Host.Frame({})
		end
		local items = {
			{
				id = "a",
				label = "A",
				onSelect = function() end,
			},
		}
		return {
			Screen = function()
				return {}
			end,
			VStack = function()
				return {}
			end,
			HStack = function()
				return {}
			end,
			ZStack = function()
				return {}
			end,
			ScrollView = function()
				return {}
			end,
			Grid = function()
				return { columns = 2 }
			end,
			AdaptiveStack = function()
				return {}
			end,
			ViewThatFits = function()
				return { Host.Frame({}) }
			end,
			Region = function()
				return { zone = "top" :: "top", rank = 1, Host.Frame({}) }
			end,
			Composition = function()
				return {}
			end,
			Alert = function()
				return {
					isPresented = Compose.cell(false),
					title = "Title",
					message = "Message",
					actions = { { id = "ok", label = "OK", role = "default" :: "default" } },
				}
			end,
			Dialog = function()
				return { isPresented = Compose.cell(false), closeButton = false, title = "Title" }
			end,
			Toast = function()
				return { message = "Saved" }
			end,
			Notice = function()
				return { message = "Saved" }
			end,
			NavBar = function()
				return { title = "Tracks" }
			end,
			Popover = function()
				return {
					isPresented = Compose.cell(false),
					source = { rect = { x = 0, y = 0, w = 10, h = 10 } },
					content = function(): Instance
						return Host.Frame({})
					end,
				}
			end,
			AsyncImage = function()
				return { image = "rbxassetid://1" }
			end,
			Avatar = function()
				return { name = "Ada" }
			end,
			AvatarGroup = function()
				return { items = { { id = "a", name = "Ada" } } }
			end,
			Badge = function()
				return { label = "New" }
			end,
			Button = function()
				return { label = "Go" }
			end,
			Callout = function()
				return {
					anchor = Host.Frame({}),
					content = content,
					onRetire = function() end,
				}
			end,
			Chip = function()
				return { label = "Chip", selected = Compose.cell(false) }
			end,
			CollapsibleView = function()
				return { expanded = Compose.cell(false), content = content }
			end,
			ColorPicker = function()
				return { value = Compose.cell(require("@lune/roblox").Color3.new(1, 0, 0)) }
			end,
			ComboBox = function()
				return {
					value = Compose.cell(""),
					text = Compose.cell(""),
					options = { { value = "a", label = "A" } },
					acceptCustom = function()
						return nil
					end,
				}
			end,
			DateTimePicker = function()
				return { value = Compose.cell(nil), onChange = function() end }
			end,
			DisclosureGroup = function()
				return { expanded = Compose.cell(false), content = content }
			end,
			Text = function()
				return { text = "Text" }
			end,
			Label = function()
				return { title = "Label", icon = "checkmark" }
			end,
			Image = function()
				return { image = "rbxassetid://1" }
			end,
			Divider = function()
				return {}
			end,
			Spacer = function()
				return { minLength = "m" }
			end,
			LevelPicker = function()
				return { value = Compose.cell(1) }
			end,
			Menu = function()
				return { items = items }
			end,
			NavigationSplitView = function()
				return { sidebar = content, detail = content }
			end,
			NavigationStack = function()
				return {
					path = Compose.cell({}),
					root = { title = "Root", content = content },
					destinations = {},
				}
			end,
			PageView = function()
				return {
					selection = Compose.cell("a"),
					pages = { { id = "a", content = content } :: FixtureNavigationTypes.Tab },
				}
			end,
			Picker = function()
				return { selected = Compose.cell("a"), options = { { value = "a", label = "A" } } }
			end,
			ProgressView = function()
				return { value = 0.5 }
			end,
			RadialMenu = function()
				return { items = items }
			end,
			Rating = function()
				return { value = Compose.cell(1) }
			end,
			RowActions = function()
				return { content = content }
			end,
			Sheet = function()
				return {
					isPresented = Compose.cell(false),
					detent = Compose.cell("medium"),
					title = "Sheet",
					content = content,
				}
			end,
			ShortcutHint = function()
				return { keys = { { "Ctrl", "K" } } }
			end,
			Skeleton = function()
				return {}
			end,
			Slider = function()
				return { value = Compose.cell(0.5) }
			end,
			SplitButton = function()
				return { label = "Primary", onActivate = function() end, items = items }
			end,
			Stage = function()
				return {}
			end,
			ErrorBoundary = function()
				return { view = content, fallback = content }
			end,
			Pagination = function()
				return { page = Compose.cell(3), pageCount = 10, onChange = function() end }
			end,
			Card = function()
				return {
					image = "rbxassetid://1",
					title = "Card",
					onActivate = function() end,
					primaryAction = { label = "Play", onActivate = function() end },
				}
			end,
			Vote = function()
				return { value = Compose.cell("none"), onChange = function() end }
			end,
			StepIndicator = function()
				return {
					steps = {
						{ id = "a", label = "A", navigable = true } :: { id: string, label: string, navigable: boolean? },
						{ id = "b", label = "B" },
					},
					current = "a",
					onSelect = function() end,
				}
			end,
			StatusIndicator = function()
				return { status = "info" }
			end,
			Path = function()
				return { points = Facet.pathShapes.ring() }
			end,
			Stepper = function()
				return { value = Compose.cell(1), max = 5 }
			end,
			TabView = function()
				return {
					selection = Compose.cell("a"),
					tabs = { { id = "a", label = "A", content = content } :: FixtureNavigationTypes.Tab },
				}
			end,
			CellEditor = function()
				return { editor = "text", value = "Name", onChange = function() end }
			end,
			Table = function()
				return {
					from = {},
					key = function(item)
						return item.id
					end,
					columns = {
						{
							id = "c",
							label = "C",
							value = function(item)
								return item.id
							end,
						} :: FixtureCollectionTypes.TableColumn<any, any>,
					},
				}
			end,
			TextInput = function()
				return { value = Compose.cell("") }
			end,
			NumberInput = function()
				return { value = Compose.cell("1"), numericValue = Compose.cell(1) }
			end,
			Toggle = function()
				return { value = Compose.cell(false) }
			end,
			VirtualGrid = function()
				return { from = {}, render = content }
			end,
			Outline = function()
				return { from = {}, children = "children", render = content }
			end,
			VirtualList = function()
				return { from = {}, render = content }
			end,
		}
	end

	verifyHarness:suite("native parity gaps", function()
		verifyHarness:case("refuses an unknown lower-case option on every public constructor", {
			id = "native_parity_gaps::native parity gaps::refuses an unknown lower-case option on every public constructor",
			run = function()
				local probe: any = engineLib.new()
				local names: { string } = {}
				for name in
					(Facet.controls(Facet.Roblox.createRuntime(probe), { types = probe.types } :: any) :: unknown) :: { [string]: unknown }
				do
					if not helpers[name] then
						table.insert(names, name :: string)
					end
				end
				table.sort(names)
				local published: { string } = {}
				for name in
					string.gmatch(fs.readFile("tools/public_surface.txt"), "controls%(runtime%)%.([%w_]+) : function")
				do
					if not helpers[name] then
						table.insert(published, name)
					end
				end
				table.sort(published)
				Verify.expect((table.concat(names, " "))):toBe(table.concat(published, " "))
				for _, name in names do
					local accepted = mountError(function(UI: FacetControls, Host: RobloxHost)
						local spec = assert(minimalSpecs(Host)[name], `no minimal spec for {name}`)()
						local node = UI[name](spec)
						return if spec.anchor
							then Host.Frame({ Host.Frame({ spec.anchor :: unknown }) :: unknown, node })
							else node
					end)
					Verify.expect(accepted):toBeNil()
					local refused = mountError(function(UI: FacetControls, Host: RobloxHost)
						local spec = minimalSpecs(Host)[name]()
						spec.definitelyNotAKey = true
						local node = UI[name](spec)
						return if spec.anchor
							then Host.Frame({ Host.Frame({ spec.anchor :: unknown }) :: unknown, node })
							else node
					end)
					Verify.expect(
						refused ~= nil and string.find(refused, "unknown option 'definitelyNotAKey'", 1, true) ~= nil
					)
						:toBe(true)
					local native = mountError(function(UI: FacetControls, Host: RobloxHost)
						local spec = minimalSpecs(Host)[name]()
						spec.LayoutOrder = 3
						local node = UI[name](spec)
						return if spec.anchor
							then Host.Frame({ Host.Frame({ spec.anchor :: unknown }) :: unknown, node })
							else node
					end)
					Verify.expect(native):toBeNil()
				end
			end,
		})

		verifyHarness:case("names the control and the nearest option in authoring errors", {
			id = "native_parity_gaps::native parity gaps::names the control and the nearest option in authoring errors",
			run = function()
				local invalidCases: { { any } } = {
					{
						"Facet UI.Button: unknown option 'lable'. Did you mean 'label'?",
						function(UI: FacetControls)
							return UI.Button({ lable = "Go" })
						end,
					},
					{
						"Facet UI.Text: unknown option 'zzzzzz'.",
						function(UI: FacetControls)
							return UI.Text({ text = "Go", zzzzzz = true })
						end,
					},
					{
						"Facet UI.Button: expected a property table, got number",
						function(UI: FacetControls)
							return UI.Button(42 :: any)
						end,
					},
					{
						"Facet UI.Menu: two items at one level share the id 'a'",
						function(UI: FacetControls)
							return UI.Menu({
								items = {
									{ id = "a", label = "A", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
									{ id = "a", label = "B", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
								},
							})
						end,
					},
					{
						"Facet UI.Picker: options must be an array of { value, label } entries",
						function(UI: FacetControls)
							return UI.Picker({ selected = Compose.cell("a") } :: any)
						end,
					},
				}
				table.insert(invalidCases, {
					"Facet UI.Text: set the text with text. Remove label and Text." :: unknown,
					function(UI: FacetControls)
						return UI.Text({ text = "a", label = "b" })
					end,
				})
				table.insert(invalidCases, {
					"Facet UI.Text: set the text with text." :: unknown,
					function(UI: FacetControls)
						return UI.Text({ text = "a", Text = "b" })
					end,
				})
				table.insert(invalidCases, {
					"Sise is not a valid member of TextButton" :: unknown,
					function(UI: FacetControls)
						return UI.Button({ label = "Go", Sise = 1 })
					end,
				})
				for _, case in invalidCases do
					local message = mountError(case[2])
					Verify.expect(message ~= nil and string.find(message, case[1], 1, true) ~= nil):toBe(true)
				end
				local unrelated = mountError(function(UI: FacetControls)
					return UI.Text({ text = "Go", zzzzzz = true })
				end)
				Verify.expect(unrelated ~= nil and string.find(unrelated, "Did you mean", 1, true) == nil):toBe(true)
			end,
		})

		verifyHarness:case("refuses malformed documented options with a named error", {
			id = "native_parity_gaps::native parity gaps::refuses malformed documented options with a named error",
			run = function()
				local function content(Host: any): () -> any
					return function()
						return Host.Frame({})
					end
				end
				local invalidCases: { { any } } = {
					{
						"Picker options require unique values or ids",
						function(UI: FacetControls)
							return UI.Picker({
								selected = Compose.cell("a"),
								options = {
									{ value = "a", label = "A" } :: FixtureNavigationTypes.PickerOption<any>,
									{ value = "a", label = "B" } :: FixtureNavigationTypes.PickerOption<any>,
								},
							})
						end,
					},
					{
						"Unknown Picker style",
						function(UI: FacetControls)
							return UI.Picker({
								selected = Compose.cell("a"),
								style = "wheel",
								options = { { value = "a", label = "A" } },
							} :: any)
						end,
					},
					{
						"Facet UI.Menu: two items at one level share the id 'a'",
						function(UI: FacetControls)
							return UI.Menu({
								items = {
									{ id = "a", label = "A", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
									{ id = "a", label = "B", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
								},
							})
						end,
					},
					{
						"cannot have both children and onSelect",
						function(UI: FacetControls)
							return UI.Menu({
								items = {
									{
										id = "a",
										label = "A",
										onSelect = function() end,
										children = { { id = "b", label = "B", onSelect = function() end } },
									} :: any,
								},
							})
						end,
					},
					{
						"Menu items require an action, submenu, or selection state",
						function(UI: FacetControls)
							return UI.Menu({ items = { { id = "a", label = "A" } } } :: any)
						end,
					},
					{
						"Picker.selected requires a writable Compose cell",
						function(UI: FacetControls)
							return UI.Picker({ selected = "a", options = { { value = "a", label = "A" } } } :: any)
						end,
					},
					{
						"TabView.selection requires a writable Compose cell",
						function(UI: FacetControls, Host: RobloxHost)
							return UI.TabView(
								{ selection = "a", tabs = { { id = "a", label = "A", content = content(Host) } } } :: any
							)
						end,
					},
					{
						"PageView requires entries",
						function(UI: FacetControls)
							return UI.PageView({ selection = Compose.cell("a"), pages = {} })
						end,
					},
					{
						"PageView entries require unique string ids",
						function(UI: FacetControls, Host: RobloxHost)
							return UI.PageView({
								selection = Compose.cell("a"),
								pages = {
									{ id = "a", content = content(Host) } :: FixtureNavigationTypes.Tab,
									{ id = "a", content = content(Host) } :: FixtureNavigationTypes.Tab,
								},
							})
						end,
					},
					{
						"Sheet.detent requires a writable Compose cell",
						function(UI: FacetControls, Host: RobloxHost)
							return UI.Sheet({
								isPresented = Compose.cell(false),
								detent = "medium",
								title = "Sheet",
								content = content(Host),
							} :: any)
						end,
					},
					{
						"TabView entries require unique string ids",
						function(UI: FacetControls, Host: RobloxHost)
							return UI.TabView({
								selection = Compose.cell("a"),
								tabs = {
									{ id = "a", label = "A", content = content(Host) } :: FixtureNavigationTypes.Tab,
									{ id = "a", label = "B", content = content(Host) } :: FixtureNavigationTypes.Tab,
								},
							})
						end,
					},
					{
						"TabView.selection must name an entry",
						function(UI: FacetControls, Host: RobloxHost)
							return UI.TabView({
								selection = Compose.cell("missing"),
								tabs = {
									{ id = "a", label = "A", content = content(Host) } :: FixtureNavigationTypes.Tab,
								},
							})
						end,
					},
					{
						"PageView.selection must name an entry",
						function(UI: FacetControls, Host: RobloxHost)
							return UI.PageView({
								selection = Compose.cell("missing"),
								pages = { { id = "a", content = content(Host) } :: FixtureNavigationTypes.Tab },
							})
						end,
					},
					{
						"snap must be none or item",
						function(UI: FacetControls, Host: RobloxHost)
							return UI.VirtualList({ from = {}, render = content(Host), snap = "page" } :: any)
						end,
					},
					{
						"finite min must be below max",
						function(UI: FacetControls)
							return UI.Stepper({ value = Compose.cell(1), min = 5, max = 5 })
						end,
					},
					{
						"step must be positive",
						function(UI: FacetControls)
							return UI.Slider({ value = Compose.cell(0.5), step = 0 })
						end,
					},
					{
						"exactly one of fraction or height",
						function(UI: FacetControls, Host: RobloxHost)
							return UI.Sheet({
								isPresented = Compose.cell(false),
								detent = Compose.cell("half"),
								detents = (
										{ { id = "half", fraction = 0.5, height = 100 } } :: unknown
									) :: { SheetDetent },
								title = "Sheet",
								content = content(Host),
							} :: any)
						end,
					},
					{
						"count must be a positive integer",
						function(UI: FacetControls)
							return UI.Rating({ value = Compose.cell(1), count = 2.5 })
						end,
					},
					{
						"invalid clearButtonMode",
						function(UI: FacetControls)
							return UI.TextInput({ value = Compose.cell(""), clearButtonMode = "sometimes" } :: any)
						end,
					},
					{
						"shape must be rect or circle",
						function(UI: FacetControls)
							return UI.Button({ label = "Go", shape = "star" } :: any)
						end,
					},
					{
						"corners must be pill or square",
						function(UI: FacetControls)
							return UI.Button({ label = "Go", corners = "round" } :: any)
						end,
					},
					{
						"segments require bar presentation",
						function(UI: FacetControls)
							return UI.ProgressView({
								value = 0.5,
								presentation = "circular" :: "circular",
								segments = 4,
							})
						end,
					},
					{
						"supply either a constructor name or Name",
						function(UI: FacetControls)
							return UI.Button("First")({ label = "Go", Name = "Second" })
						end,
					},
				}
				for _, case in invalidCases do
					local message = mountError(case[2])
					Verify.expect(message ~= nil and string.find(message, case[1], 1, true) ~= nil):toBe(true)
				end
			end,
		})

		verifyHarness:case("reports a failed alert body to the onError factory option and dismisses once", {
			id = "native_parity_gaps::native parity gaps::reports a failed alert body to the onError factory option and dismisses once",
			run = function()
				local presented, failures = Compose.cell(true), {}
				local w = world(function(UI: FacetControls)
					return UI.Alert("Broken")({
						isPresented = presented,
						title = "Broken",
						actions = {
							{ id = "ok", label = "OK", role = "default" :: "default" } :: FixtureNavigationTypes.AlertAction<any>,
						},
						content = function(): Instance
							error("content exploded", 0)
						end,
					})
				end, {
					onError = function(failure)
						table.insert(failures, tostring(failure))
					end,
				})
				Verify.expect(#failures):toBe(1)
				Verify.expect(string.find(failures[1], "content exploded", 1, true) ~= nil):toBe(true)
				Verify.expect((presented:peek())):toBe(false)
				Verify.expect(find(w.screen, "Broken"):GetAttribute("FacetError") ~= nil):toBe(true)
				Verify.expect((find(w.screen, "AlertPanel"))):toBeNil()
				w.stop()
				Verify.expect(#failures):toBe(1)
			end,
		})

		verifyHarness:case("keeps at most the documented number of pooled row hosts", {
			id = "native_parity_gaps::native parity gaps::keeps at most the documented number of pooled row hosts",
			run = function()
				for _, limit in { 32, 4 } do
					local source = Compose.cell(records(100))
					local w = world(function(UI: FacetControls, Host: RobloxHost)
						return UI.VirtualList({
							from = source,
							key = function(item)
								return item.id
							end,
							itemSize = 10,
							overscan = 0,
							maxRetained = if limit == 32 then nil else limit,
							render = function(): GuiObject
								return Host.Frame({ Name = "Cell" })
							end,
						})
					end)
					local list = w.screen:FindFirstChildWhichIsA("ScrollingFrame")
					list.AbsoluteWindowSize = w.engine.types.Vector2.new(100, 600)
					Verify.expect(#list:FindFirstChild("Items"):GetChildren()):toBe(60)
					local function parked()
						local count = 0
						for _, node in w.engine.made do
							if
								node.ClassName == "Frame"
								and node.Name ~= "Cell"
								and node.Parent == nil
								and not node:isDestroyed()
							then
								count += 1
							end
						end
						return count
					end
					source:set({})
					Verify.expect(#list:FindFirstChild("Items"):GetChildren()):toBe(0)
					Verify.expect((parked())):toBe(limit)
					w.stop()
					Verify.expect((parked())):toBe(0)
				end
			end,
		})

		verifyHarness:case("fills the controls table with indexOfKey, placementOf and offsetOf", {
			id = "native_parity_gaps::native parity gaps::fills the controls table with indexOfKey, placementOf and offsetOf",
			run = function()
				local source, controls = Compose.cell(records(100)), {} :: { [string]: any }
				local w = world(function(UI: FacetControls, Host: RobloxHost)
					return UI.VirtualList({
						from = source,
						key = function(item)
							return item.id
						end,
						itemSize = 10,
						gap = 2,
						controls = controls,
						render = function(): GuiObject
							return Host.Frame({})
						end,
					})
				end)
				local list = w.screen:FindFirstChildWhichIsA("ScrollingFrame")
				list.AbsoluteWindowSize = w.engine.types.Vector2.new(100, 100)
				Verify.expect((controls.indexOfKey(5))):toBe(5)
				Verify.expect((controls.indexOfKey(1000))):toBeNil()
				Verify.expect(controls.placementOf(5).offset):toBe(48)
				Verify.expect((controls.offsetOf(5, "start"))):toBe(48)
				Verify.expect((controls.offsetOf(5, "end", 30))):toBe(28)
				Verify.expect((controls.offsetOf(5, "center", 30))):toBe(38)
				Verify.expect((controls.offsetOf(100, "start", 100))):toBe(1098)
				local reversed = records(100)
				table.sort(reversed, function(a: any, b: any)
					return a.id > b.id
				end)
				source:set(reversed)
				Verify.expect((controls.indexOfKey(1))):toBe(100)
				Verify.expect((controls.indexOfKey(100))):toBe(1)
				w.stop()
			end,
		})

		verifyHarness:case("delivers onActivate with the item and key and skips disabled rows", {
			id = "native_parity_gaps::native parity gaps::delivers onActivate with the item and key and skips disabled rows",
			run = function()
				local activated: { any } = {}
				local w = world(function(UI: FacetControls, Host: RobloxHost)
					return UI.VirtualList({
						from = records(10),
						key = function(item)
							return `k{item.id}`
						end,
						itemSize = 20,
						disabled = function(item)
							return item.id == 2
						end,
						onActivate = function(item, key)
							table.insert(activated, { item = item, key = key })
						end,
						render = function(): GuiObject
							return Host.Frame({})
						end,
					})
				end)
				local list = w.screen:FindFirstChildWhichIsA("ScrollingFrame")
				list.AbsoluteWindowSize = w.engine.types.Vector2.new(100, 200)
				find(find(list, "k3"), "RowHit").Activated.fire()
				Verify.expect(#activated):toBe(1)
				Verify.expect(activated[1].key):toBe("k3")
				Verify.expect(activated[1].item.id):toBe(3)
				local blocked = find(find(list, "k2"), "RowHit")
				Verify.expect(blocked.Interactable):toBe(false)
				blocked.Activated.fire()
				Verify.expect(#activated):toBe(1)
				w.stop()
			end,
		})

		verifyHarness:case("shows button help when gamepad selection rests on the button and hides it on deselection", {
			id = "native_parity_gaps::native parity gaps::shows button help when gamepad selection rests on the button and hides it on deselection",
			run = function()
				local w = world(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame("Screen")({
						UI.Button("Plus")({ label = "+", help = "Posts this avatar" }),
					})
				end)
				local Enum = w.engine.types.Enum
				local plus = find(w.screen, "Plus")
				w.input.PreferredInput = Enum.PreferredInput.Gamepad
				w.gui.SelectedObject = plus
				w.engine.heartbeat.fire(0.3)
				Verify.expect((find(w.screen, "HelpText"))):toBeNil()
				w.engine.heartbeat.fire(0.2)
				Verify.expect(find(w.screen, "HelpText").Text):toBe("Posts this avatar")
				w.gui.SelectedObject = nil
				Verify.expect((find(w.screen, "HelpText"))):toBeNil()
				w.input.PreferredInput = Enum.PreferredInput.Touch
				w.gui.SelectedObject = plus
				w.engine.heartbeat.fire(0.6)
				Verify.expect((find(w.screen, "HelpText"))):toBeNil()
				w.stop()
			end,
		})

		verifyHarness:case("disables a stepper direction at its bound and refuses the step", {
			id = "native_parity_gaps::native parity gaps::disables a stepper direction at its bound and refuses the step",
			run = function()
				local value, changes = Compose.cell(0), 0
				local w = world(function(UI: FacetControls)
					return UI.Stepper({
						value = value,
						min = 0,
						max = 2,
						onChange = function(nextValue)
							changes += 1
							value:set(nextValue)
						end,
					})
				end)
				local decrease, increase = find(w.screen, "Decrease"), find(w.screen, "Increase")
				Verify.expect(decrease.Interactable):toBe(false)
				Verify.expect(increase.Interactable):toBe(true)
				decrease.Activated.fire()
				Verify.expect((value:peek())):toBe(0)
				increase.Activated.fire()
				increase.Activated.fire()
				Verify.expect((value:peek())):toBe(2)
				Verify.expect(increase.Interactable):toBe(false)
				Verify.expect(decrease.Interactable):toBe(true)
				increase.Activated.fire()
				Verify.expect((value:peek())):toBe(2)
				Verify.expect(changes):toBe(2)
				w.stop()
			end,
		})

		verifyHarness:case("wraps rating activation to zero only when allowZero and ignores a disabled rating", {
			id = "native_parity_gaps::native parity gaps::wraps rating activation to zero only when allowZero and ignores a disabled rating",
			run = function()
				local open, closed, blocked = Compose.cell(5), Compose.cell(5), Compose.cell(2)
				local w = world(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Rating("Open")({ value = open }) :: unknown,
						UI.Rating("Closed")({ value = closed, allowZero = false }),
						UI.Rating("Blocked")({ value = blocked, enabled = false }),
					})
				end)
				find(w.screen, "Open").Activated.fire()
				Verify.expect((open:peek())):toBe(0)
				find(w.screen, "Open").Activated.fire()
				Verify.expect((open:peek())):toBe(1)
				find(w.screen, "Closed").Activated.fire()
				Verify.expect((closed:peek())):toBe(1)
				local disabled = find(w.screen, "Blocked")
				Verify.expect(disabled.Interactable):toBe(false)
				Verify.expect(disabled.Selectable):toBe(false)
				disabled.Activated.fire()
				Verify.expect((blocked:peek())):toBe(2)
				w.stop()
			end,
		})

		verifyHarness:case("tags a disabled button for the theme disabled rule and lets a package retune it", {
			id = "native_parity_gaps::native parity gaps::tags a disabled button for the theme disabled rule and lets a package retune it",
			run = function()
				local enabled = Compose.cell(false)
				local w = world(function(UI: FacetControls)
					return UI.Button("Go")({ label = "Go", enabled = enabled })
				end)
				local button = find(w.screen, "Go")
				Verify.expect((button:HasTag("facet-disabled"))):toBe(true)
				Verify.expect(button.Interactable):toBe(false)
				enabled:set(true)
				Verify.expect((button:HasTag("facet-disabled"))):toBe(false)
				Verify.expect(button.Interactable):toBe(true)
				w.stop()
				local engine: any = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local function disabledRule(package: any): number?
					local stop, sheet: any = runtime.mount(function()
						return Facet.themes.createStyleSheet(runtime, package, { types = engine.types })
					end, engine.new("Folder"))
					local found
					for _, rule in sheet:GetChildren() do
						if rule.Selector == ".facet-disabled" then
							found = rule:GetProperties().TextTransparency
						end
					end
					stop()
					return found
				end
				local neutral = Facet.themes.neutralPackage()
				Verify.expect((disabledRule(neutral)))
					:toBe((neutral.style.themes[1].extra :: any).disabledContentOpacity)
				local custom = Facet.themes.neutralPackage()
				for _, palette in custom.style.themes do
					(palette.extra :: any).disabledContentOpacity = 0.6
				end
				local package, report = Facet.themes.define(custom :: any)
				Verify.expect(report.ok):toBe(true)
				Verify.expect((disabledRule(package))):toBe(0.6)
				runtime:dispose()
			end,
		})

		verifyHarness:case(
			"estimates table rows from a regular control height that falls back when the theme metric is missing or not finite",
			{
				id = "native_parity_gaps::native parity gaps::estimates table rows from a regular control height that falls back when the theme metric is missing or not finite",
				run = function()
					local empty = Facet.themes.neutralPackage()
					empty.metrics.controlSizes = {} :: any
					local nan = Facet.themes.neutralPackage()
					nan.metrics.controlSizes.regular.height = 0 / 0
					local huge = Facet.themes.neutralPackage()
					huge.metrics.controlSizes.regular.height = math.huge
					local short = Facet.themes.neutralPackage()
					short.metrics.controlSizes.regular.height = 30
					for _, case in
						{
							{ theme = empty, row = 44 },
							{ theme = nan, row = 44 },
							{ theme = huge, row = 44 },
							{ theme = short, row = 40 },
						}
					do
						local controls = {} :: { [string]: any }
						local w = world(function(UI: FacetControls)
							return UI.Table({
								from = records(3),
								key = function(item)
									return item.id
								end,
								controls = controls,
								columns = {
									{ id = "label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
								},
							})
						end, { theme = case.theme })
						local body = find(w.screen, "Body")
						body.AbsoluteWindowSize = w.engine.types.Vector2.new(300, 300)
						Verify.expect(controls.placementOf(2).offset):toBe(case.row)
						Verify.expect(controls.placementOf(3).offset):toBe(case.row * 2)
						w.stop()
					end
				end,
			}
		)

		verifyHarness:case("refuses picker selection and disclosure toggling while disabled and resumes when enabled", {
			id = "native_parity_gaps::native parity gaps::refuses picker selection and disclosure toggling while disabled and resumes when enabled",
			run = function()
				local selected, changes = Compose.cell("a"), 0
				local pickerEnabled, groupEnabled = Compose.cell(false), Compose.cell(false)
				local expanded, toggles = Compose.cell(false), 0
				local w = world(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Picker({
							selected = selected,
							style = "segmented" :: "segmented",
							enabled = pickerEnabled,
							options = {
								{ value = "a", label = "A" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "B" } :: FixtureNavigationTypes.PickerOption<any>,
							},
							onChange = function()
								changes += 1
							end,
						}) :: unknown,
						UI.DisclosureGroup({
							label = "Advanced",
							expanded = expanded,
							enabled = groupEnabled,
							onToggle = function()
								toggles += 1
							end,
							content = function(): Instance
								return Host.Frame("Body")({})
							end,
						}),
					})
				end)
				local picker = find(w.screen, "Picker")
				local option = find(picker, "b")
				Verify.expect(option.Interactable):toBe(false)
				option.Activated.fire()
				Verify.expect((selected:peek())):toBe("a")
				Verify.expect(changes):toBe(0)
				local header = find(find(w.screen, "DisclosureGroup"), "Header")
				Verify.expect(header.Interactable):toBe(false)
				Verify.expect(header.Selectable):toBe(false)
				header.Activated.fire()
				Verify.expect((expanded:peek())):toBe(false)
				Verify.expect(toggles):toBe(0)
				Verify.expect((find(w.screen, "Body"))):toBe(nil)
				pickerEnabled:set(true)
				groupEnabled:set(true)
				Verify.expect(find(picker, "b").Interactable):toBe(true)
				find(picker, "b").Activated.fire()
				Verify.expect((selected:peek())):toBe("b")
				Verify.expect(changes):toBe(1)
				Verify.expect(header.Interactable):toBe(true)
				header.Activated.fire()
				Verify.expect((expanded:peek())):toBe(true)
				Verify.expect(toggles):toBe(1)
				Verify.expect(find(w.screen, "Body") ~= nil):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("keeps the value when custom combo box validation unmounts the control", {
			id = "native_parity_gaps::native parity gaps::keeps the value when custom combo box validation unmounts the control",
			run = function()
				local value, text, changes = Compose.cell("a"), Compose.cell("Alpha"), 0
				local stopRef: { stop: () -> () } = {
					stop = function() end,
				}
				local failure: string? = nil
				local w = world(function(UI: FacetControls)
					return UI.ComboBox({
						value = value,
						text = text,
						commitOnFocusLost = true,
						options = { { value = "a", label = "Alpha" } :: FixtureNavigationTypes.PickerOption<string> },
						acceptCustom = function()
							stopRef.stop()
							return true
						end,
						onChange = function()
							changes += 1
						end,
					})
				end)
				stopRef.stop = w.stop
				local editor = find(w.screen, "Editor")
				local ok, message = pcall(function()
					editor:CaptureFocus()
					editor.Text = "Custom"
					editor:ReleaseFocus(true)
				end)
				if not ok then
					failure = tostring(message)
				end
				Verify.expect(failure):toBe(nil)
				Verify.expect((value:peek())):toBe("a")
				Verify.expect(changes):toBe(0)
				Verify.expect(editor.Parent):toBe(nil)
			end,
		})

		verifyHarness:case("keeps the changelog release heading equal to Facet.VERSION", {
			id = "native_parity_gaps::native parity gaps::keeps the changelog release heading equal to Facet.VERSION",
			run = function()
				local changelog = fs.readFile("CHANGELOG.md")
				local heading = string.match(changelog, "\n## (%d+%.%d+%.%d+)")
				Verify.expect(heading):toBe(Facet.VERSION)
				Verify.expect(string.match(Facet.VERSION, "^%d+%.%d+%.%d+$") ~= nil):toBe(true)
			end,
		})
	end)
end
