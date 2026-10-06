--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
	type TextLabelConstructor = typeof(require("@repo/tools/typecheck/aliases").TextLabelConstructor)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local FixtureComposeTypes = require("../src/vendor/compose/core")
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local Compose = require("../src/vendor/compose/core")
	local Roblox = require("../src/vendor/compose/roblox")
	local context = require("../src/ui/context")
	local register = require("../src/ui/inputs")
	local themes = require("../src/ui/themes")
	local engineLib = require("./lib/native_engine")
	local expect = Verify.expect

	local function world(build: (any, any, any) -> any, options: any?): any
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Roblox.createRuntime(engine)
		local UI: any = {}
		local gui, input = engine.new("GuiService"), engine.new("UserInputService")
		local config: any = options or {}
		config.types = engine.types
		config.services = { GuiService = gui, UserInputService = input, RunService = config.runService }
		config.guiService = gui
		local ctx = context(Compose, runtime, config)
		register(ctx, UI)
		local screen = engine.new("ScreenGui")
		local stop, node: any = runtime.mount(function()
			return build(UI, engine, runtime)
		end, screen)
		return {
			node = node,
			stop = stop,
			engine = engine,
			runtime = runtime,
			gui = gui,
			input = input,
			screen = screen,
			E = engine.types.Enum,
		}
	end

	local function find(root: any, path: string): any
		local at = root
		for name in string.gmatch(path, "[^/]+") do
			if at == nil then
				return nil
			end
			local found = nil
			for _, child in at:GetChildren() do
				if child.Name == name then
					found = child
					break
				end
			end
			at = found
		end
		return at
	end

	local function deep(root: any, name: string): any
		if root.Name == name then
			return root
		end
		for _, child in root:GetChildren() do
			local found = deep(child, name)
			if found then
				return found
			end
		end
		return nil
	end

	local function refused(build: (any) -> any): string?
		local ok, err = pcall(function()
			local w = world(function(UI: FacetControls)
				return build(UI)
			end)
			w.stop()
		end)
		return if ok then nil else tostring(err)
	end

	local function selectable(root: any): { string }
		local out = {}
		local function visit(node: any)
			if node:IsA("GuiObject") and node.Selectable == true and node.Visible ~= false then
				table.insert(out, node.Name)
			end
			for _, child in node:GetChildren() do
				visit(child)
			end
		end
		visit(root)
		return out
	end

	local function vector(engine: any, x: number, y: number): any
		return engine.types.Vector3.new(x, y, 0)
	end

	verifyHarness:suite("native field chrome", function()
		verifyHarness:case("a field with no chrome keys keeps its native TextBox root", {
			id = "native_fields::native field chrome::a field with no chrome keys keeps its native TextBox root",
			run = function()
				local w = world(function(UI: FacetControls)
					return UI.TextInput("Name")({ value = Compose.cell(""), placeholder = "Your name" })
				end)
				expect(w.node.ClassName):toBe("TextBox")
				expect(w.node.Name):toBe("Name")
				expect((w.node:HasTag("facet-field"))):toBe(true)
				expect((find(w.node, "Label"))):toBeNil()
				expect((find(w.node, "Message"))):toBeNil()
				expect((find(w.node, "Input"))):toBeNil()
				w.stop()
			end,
		})

		verifyHarness:case("the label sits above its field, and a tap or a finger on it puts the caret in the field", {
			id = "native_fields::native field chrome::the label sits above its field, and a tap or a finger on it puts the caret in the field",
			run = function()
				for _, route in { "pointer", "touch" } do
					local w = world(function(UI: FacetControls)
						return UI.TextInput("Name")({ value = Compose.cell(""), label = "Display name" })
					end)
					local label, plate = find(w.node, "Label"), find(w.node, "Input")
					local field = find(plate, "Field")
					expect(w.node.ClassName):toBe("Frame")
					expect(label.LayoutOrder < plate.LayoutOrder):toBe(true)
					expect((field:IsFocused())):toBe(false)
					label.Activated.fire({
						UserInputType = if route == "pointer"
							then w.E.UserInputType.MouseButton1
							else w.E.UserInputType.Touch,
					})
					expect(`{route}: {field:IsFocused()}`):toBe(`{route}: true`)
					expect(find(label, "Title").AnchorPoint.Y):toBe(0)
					w.stop()
				end
			end,
		})

		verifyHarness:case("a disabled field's label follows it: no press or hover affordance, live both ways", {
			id = "native_fields::native field chrome::a disabled field's label follows it: no press or hover affordance, live both ways",
			run = function()
				local enabled = Compose.cell(false)
				local w = world(function(UI: FacetControls)
					return UI.TextInput("Name")({ value = Compose.cell(""), label = "Display name", enabled = enabled })
				end)
				local label, field = find(w.node, "Label"), find(w.node, "Input/Field")
				expect(label.Interactable):toBe(false)
				expect(label.AutoButtonColor):toBe(false)
				label.Activated.fire()
				expect((field:IsFocused())):toBe(false)
				enabled:set(true)
				expect(label.Interactable):toBe(true)
				label.Activated.fire()
				expect((field:IsFocused())):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("the label fits its text and adds no focus stop", {
			id = "native_fields::native field chrome::the label fits its text and adds no focus stop",
			run = function()
				local w = world(function(UI: FacetControls)
					return UI.TextInput("Name")({ value = Compose.cell(""), label = "Display name" })
				end)
				expect((table.concat(selectable(w.node), " "))):toBe("Field")
				local label = find(w.node, "Label")
				expect(label.Selectable):toBe(false)
				expect(label.Size.Y.Offset):toBe(0)
				expect(label.AutomaticSize):toBe(w.E.AutomaticSize.Y)
				expect(find(label, "Title").AutomaticSize):toBe(w.E.AutomaticSize.Y)
				expect(label.Parent == find(w.node, "Input").Parent):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("the required mark is part of the label's words, bound or static; optional paints no word", {
			id = "native_fields::native field chrome::the required mark is part of the label's words, bound or static; optional paints no word",
			run = function()
				local words = Compose.cell("Display name")
				local w = world(function(UI: FacetControls, _, runtime)
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						UI.TextInput("Static")({
							value = Compose.cell(""),
							label = "Display name",
							requiredMark = "required" :: "required",
						}) :: unknown,
						UI.TextInput("Bound")({
							value = Compose.cell(""),
							label = function(use: Use)
								return use(words)
							end,
							requiredMark = "required" :: "required",
						}),
						UI.TextInput("Optional")({
							value = Compose.cell(""),
							label = "Display name",
							requiredMark = "optional" :: "optional",
						}),
					})
				end)
				expect(find(w.node, "Static/Label/Title").Text):toBe("Display name *")
				expect((deep(find(w.node, "Static"), "RequiredMark"))):toBeNil()
				expect(find(w.node, "Bound/Label/Title").Text):toBe("Display name *")
				words:set("Anzeigename")
				expect(find(w.node, "Bound/Label/Title").Text):toBe("Anzeigename *")
				expect(find(w.node, "Bound/Label/Title").TextWrapped):toBe(true)
				expect(find(w.node, "Optional/Label/Title").Text):toBe("Display name")
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native field message line", function()
		verifyHarness:case("an error replaces the hint, in the danger role, beside a mark, and the field holds still", {
			id = "native_fields::native field message line::an error replaces the hint, in the danger role, beside a mark, and the field holds still",
			run = function()
				local failure = Compose.cell("")
				local w = world(function(UI: FacetControls)
					return UI.TextInput("Name")({
						value = Compose.cell(""),
						hint = "Shown to other players",
						errorText = failure,
					})
				end)
				local line, mark = find(w.node, "Message/Validation"), find(w.node, "Message/MessageMark")
				local plate = find(w.node, "Input")
				expect(line.Text):toBe("Shown to other players")
				expect(mark.Visible):toBe(false)
				expect((line:HasTag("facet-validation"))):toBe(false)
				expect((line:HasTag("facet-type-caption"))):toBe(true)
				local before = plate.Size
				failure:set("That name is taken.")
				expect(line.Text):toBe("That name is taken.")
				expect(mark.Visible):toBe(true)
				expect((line:HasTag("facet-validation"))):toBe(true)
				expect((plate:HasTag("facet-invalid"))):toBe(true)
				expect(plate.Size == before):toBe(true)
				expect((find(plate, "ValidationPulse"))):toBeNil()
				failure:set("")
				expect(line.Text):toBe("Shown to other players")
				expect(mark.Visible):toBe(false)
				expect((plate:HasTag("facet-invalid"))):toBe(false)
				w.stop()
			end,
		})

		verifyHarness:case("the error mark is floored at the icon rung and painted the message's colour", {
			id = "native_fields::native field message line::the error mark is floored at the icon rung and painted the message's colour",
			run = function()
				local w = world(function(UI: FacetControls)
					return UI.TextInput("Name")({
						value = Compose.cell(""),
						hint = "Shown to other players",
						errorText = "That name is taken.",
					})
				end)
				local mark = find(w.node, "Message/MessageMark")
				local line = find(w.node, "Message/Validation")
				line.TextSize = 12
				expect(mark.Size.X.Offset):toBe(16)
				expect(mark.Size.Y.Offset):toBe(12)
				line.TextSize = 20
				expect(mark.Size.Y.Offset):toBe(20)
				expect((mark:HasTag("facet-icon-error"))):toBe(true)
				local sheet = nil
				local e: any = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(e)
				local rules: { [string]: any } = {}
				local stop = runtime.mount(function()
					sheet = themes(Compose).createStyleSheet(runtime, nil, { types = e.types })
					return sheet
				end, e.new("Folder"))
				for _, rule in (sheet :: any):GetChildren() do
					rules[rule.Selector] = rule:GetProperties()
				end
				expect(rules[".facet-icon-error"].ImageColor3 ~= nil):toBe(true)
				expect(rules[".facet-validation"].TextColor3 == rules[".facet-icon-error"].ImageColor3):toBe(true)
				expect(rules[".facet-validation"].TextColor3 ~= rules[".facet-text"].TextColor3):toBe(true)
				stop()
				w.stop()
			end,
		})

		verifyHarness:case("the caller's error outranks the numeric field's own rejection line", {
			id = "native_fields::native field message line::the caller's error outranks the numeric field's own rejection line",
			run = function()
				local failure = Compose.cell("")
				local w = world(function(UI: FacetControls)
					return UI.TextInput("Laps")({
						value = Compose.cell("3"),
						numericValue = Compose.cell(3),
						presentation = "number" :: "number",
						min = 1,
						max = 9,
						errorText = failure,
					})
				end)
				local field, line = find(w.node, "Input/Field"), find(w.node, "Message/Validation")
				field:CaptureFocus()
				field.Text = "1.2.3"
				field:ReleaseFocus(true)
				expect(line.Text):toBe("Enter a valid number.")
				failure:set("The server refused that number.")
				expect(line.Text):toBe("The server refused that number.")
				failure:set("")
				expect(line.Text):toBe("Enter a valid number.")
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native field accessories", function()
		local function accessories(pasted: { count: number }, value: any): any
			return world(function(UI: FacetControls, _, runtime)
				return UI.TextInput("Name")({
					value = value,
					clearButtonMode = "always" :: "always",
					leading = ((runtime.constructors.TextLabel :: unknown) :: TextLabelConstructor)({
						Name = "Mark",
						Text = "@",
					}),
					trailing = UI.Button("Paste")({
						label = "Paste",
						onActivate = function()
							pasted.count += 1
						end,
					}),
				})
			end)
		end

		verifyHarness:case("both accessories sit inside the plate, and the clear keeps its room between them", {
			id = "native_fields::native field accessories::both accessories sit inside the plate, and the clear keeps its room between them",
			run = function()
				local w = accessories({ count = 0 }, Compose.cell("Ada"))
				local plate = find(w.node, "Input")
				local leading, field, clear, trailing =
					find(plate, "Leading"), find(plate, "Field"), find(plate, "Clear"), find(plate, "Trailing")
				expect(leading ~= nil and field ~= nil and clear ~= nil and trailing ~= nil):toBe(true)
				expect(plate:FindFirstChildWhichIsA("UIListLayout").FillDirection):toBe(w.E.FillDirection.Horizontal)
				expect(leading.LayoutOrder < field.LayoutOrder):toBe(true)
				expect(field.LayoutOrder < clear.LayoutOrder):toBe(true)
				expect(clear.LayoutOrder < trailing.LayoutOrder):toBe(true)
				expect(find(leading, "Mark").Text):toBe("@")
				w.stop()
			end,
		})

		verifyHarness:case(
			"a static leading mark is not a stop; the clear and the trailing action are, in that order",
			{
				id = "native_fields::native field accessories::a static leading mark is not a stop; the clear and the trailing action are, in that order",
				run = function()
					local w = accessories({ count = 0 }, Compose.cell("Ada"))
					local plate = find(w.node, "Input")
					local order = {}
					for _, name in selectable(plate) do
						table.insert(order, name)
					end
					table.sort(order, function(a, b)
						local function at(name: string): number
							local node = find(plate, name) or find(plate, "Trailing/" .. name)
							return node.LayoutOrder
								+ (if node.Parent.Name == "Trailing" then node.Parent.LayoutOrder else 0)
						end
						return at(a) < at(b)
					end)
					expect((table.concat(order, " "))):toBe("Field Clear Paste")
					w.stop()
				end,
			}
		)

		verifyHarness:case("the trailing action and the clear fire on activation without changing the other", {
			id = "native_fields::native field accessories::the trailing action and the clear fire on activation without changing the other",
			run = function()
				local pasted = { count = 0 }
				local value = Compose.cell("Ada")
				local w = accessories(pasted, value)
				local paste = find(w.node, "Input/Trailing/Paste")
				paste.Activated.fire()
				paste.Activated.fire()
				expect(pasted.count):toBe(2)
				expect((value:peek())):toBe("Ada")
				find(w.node, "Input/Clear").Activated.fire()
				expect((value:peek())):toBe("")
				expect(pasted.count):toBe(2)
				w.stop()
			end,
		})

		verifyHarness:case("a plain search field draws its leading search mark", {
			id = "native_fields::native field accessories::a plain search field draws its leading search mark",
			run = function()
				local w = world(function(UI: FacetControls)
					return UI.TextInput("Find")({ value = Compose.cell(""), presentation = "search" :: "search" })
				end)
				local glyph = w.node:FindFirstChild("SearchIcon", true)
				expect(glyph ~= nil):toBe(true)
				expect(glyph.Selectable):toBe(false)
				w.stop()
			end,
		})

		verifyHarness:case("a search field keeps its leading mark beside a trailing action, and refuses a second one", {
			id = "native_fields::native field accessories::a search field keeps its leading mark beside a trailing action, and refuses a second one",
			run = function()
				local w = world(function(UI: FacetControls)
					return UI.TextInput("Find")({
						value = Compose.cell("rally"),
						presentation = "search" :: "search",
						trailing = UI.Button("Filter")({ label = "Filter", onActivate = function() end }),
					})
				end)
				local plate = find(w.node, "Input")
				local glyph, field = find(plate, "SearchIcon"), find(plate, "Field")
				expect(glyph ~= nil):toBe(true)
				expect(glyph.LayoutOrder < field.LayoutOrder):toBe(true)
				expect(glyph.Selectable):toBe(false)
				w.stop()
				local ok, err = pcall(function()
					local nested = world(function(UI: FacetControls, _, runtime)
						return UI.TextInput("Twice")({
							value = Compose.cell(""),
							presentation = "search" :: "search",
							leading = ((runtime.constructors.TextLabel :: unknown) :: TextLabelConstructor)({
								Text = "@",
							}),
						})
					end)
					nested.stop()
				end)
				expect(ok):toBe(false)
				err = tostring(err)
				expect(err ~= nil and string.find(err, "already leads", 1, true) ~= nil):toBe(true)
			end,
		})
	end)

	verifyHarness:suite("native field vocabulary", function()
		verifyHarness:case("appearance paints the plate a published surface; a bound word repaints in place", {
			id = "native_fields::native field vocabulary::appearance paints the plate a published surface; a bound word repaints in place",
			run = function()
				for word, tag in
					{ standard = "facet-field", contrast = "facet-control", utility = "facet-appearance-utility" } :: { [string]: string }
				do
					local w = world(function(UI: FacetControls)
						return UI.TextInput("Name")({ value = Compose.cell(""), appearance = word })
					end)
					expect(`{word}: {find(w.node, "Input"):HasTag(tag)}`):toBe(`{word}: true`)
					w.stop()
				end
				local word = Compose.cell("standard")
				local w = world(function(UI: FacetControls)
					return UI.TextInput("Name")({ value = Compose.cell(""), appearance = word })
				end)
				local plate = find(w.node, "Input")
				word:set("contrast")
				expect((plate:HasTag("facet-control"))):toBe(true)
				expect((plate:HasTag("facet-field"))):toBe(false)
				word:set("utility")
				expect((plate:HasTag("facet-appearance-utility"))):toBe(true)
				expect(find(w.node, "Input") == plate):toBe(true)
				local ok, err = pcall(function()
					word:set("emphasis")
				end)
				expect(ok):toBe(false)
				expect(string.find(tostring(err), "standard | contrast | utility", 1, true) ~= nil):toBe(true)
				expect((plate:HasTag("facet-appearance-utility"))):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("corners ride a native UICorner, and square is a radius of zero", {
			id = "native_fields::native field vocabulary::corners ride a native UICorner, and square is a radius of zero",
			run = function()
				local function corner(word: ("pill" | "square")?): any
					local w = world(function(UI: FacetControls)
						return UI.TextInput("Name")({ value = Compose.cell(""), corners = word, label = "Name" })
					end)
					local found = find(w.node, "Input/Corners")
					local radius = if found then found.CornerRadius else nil
					w.stop()
					return radius
				end
				expect(corner("pill").Scale):toBe(1)
				expect(corner("square").Scale):toBe(0)
				expect(corner("square").Offset):toBe(0)
				expect((corner(nil))):toBeNil()
			end,
		})

		verifyHarness:case("a named rung shrinks the plate, reserves a whole target, and the label still focuses", {
			id = "native_fields::native field vocabulary::a named rung shrinks the plate, reserves a whole target, and the label still focuses",
			run = function()
				local w = world(function(UI: FacetControls)
					return UI.TextInput("Name")({
						value = Compose.cell(""),
						controlSize = "compact" :: "compact",
						label = "Name",
					})
				end)
				local target = find(w.node, "Input+target")
				local plate = find(target, "Input")
				expect(plate.Size.Y.Offset):toBe(36)
				expect(plate.Size.Y.Offset < 44):toBe(true)
				expect(target.Size.Y.Offset >= 44):toBe(true)
				find(w.node, "Label").Activated.fire()
				expect((find(plate, "Field"):IsFocused())):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("an unknown chrome word is a build error that names the key", {
			id = "native_fields::native field vocabulary::an unknown chrome word is a build error that names the key",
			run = function()
				for key, bad in
					{
						appearance = "emphasis",
						corners = "rounded" :: "rounded",
						requiredMark = "maybe" :: "maybe",
						hint = 4,
						controlSize = "tiny" :: "tiny",
					} :: {
						[string]: any,
					}
				do
					local err = refused(function(UI: FacetControls)
						local spec: any = { value = Compose.cell("") }
						spec[key] = bad
						return UI.TextInput("Name")(spec)
					end)
					expect(`{key}: {err ~= nil}`):toBe(`{key}: true`)
					expect(`{key}: {string.find(tostring(err), key, 1, true) ~= nil}`):toBe(`{key}: true`)
				end
			end,
		})

		verifyHarness:case("closing the screen leaves no field node or connection behind", {
			id = "native_fields::native field vocabulary::closing the screen leaves no field node or connection behind",
			run = function()
				local engine: any = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local UI: any = {}
				local input = engine.new("UserInputService")
				local ctx = context(Compose, runtime, { types = engine.types, services = { UserInputService = input } })
				register(ctx, UI)
				local screen = engine.new("ScreenGui")
				local before = engine.census()
				local stop = runtime.mount(function()
					return UI.NumberInput("Fee")({
						value = Compose.cell("1"),
						numericValue = Compose.cell(1),
						label = "Fee",
						hint = "Per lap",
						errorText = "Wrong",
						controlSize = "compact" :: "compact",
						stepButtons = true,
						prefix = "$",
						scrub = true,
						selectOnFocus = "all",
						min = 0,
						max = 9,
					})
				end, screen)
				stop()
				local after = engine.census()
				expect(#screen:GetChildren()):toBe(0)
				expect(after.connections):toBe(before.connections)
				expect(after.live - before.live):toBe(0)
				runtime:dispose()
			end,
		})
	end)

	verifyHarness:suite("native TextInput readOnly, selectOnFocus and visibleLines", function()
		verifyHarness:case("a read-only field keeps its stop and contrast, refuses every edit and commits nothing", {
			id = "native_fields::native TextInput readOnly, selectOnFocus and visibleLines::a read-only field keeps its stop and contrast, refuses every edit and commits nothing",
			run = function()
				local value, commits = Compose.cell("Ada"), 0
				local w = world(function(UI: FacetControls)
					return UI.TextInput("Name")({
						value = value,
						readOnly = true,
						clearButtonMode = "always" :: "always",
						onCommit = function()
							commits += 1
						end,
					})
				end)
				local field = w.node
				expect(field.TextEditable):toBe(false)
				expect(field.Selectable):toBe(true)
				expect((field:HasTag("facet-disabled"))):toBe(false)
				expect(find(field, "Clear").Visible):toBe(false)
				expect((field:GetAttribute("readOnly"))):toBe(true)
				field:CaptureFocus()
				field.Text = "xyz"
				expect((value:peek())):toBe("Ada")
				expect(field.Text):toBe("Ada")
				field:ReleaseFocus(true)
				expect(`{value:peek()} {commits}`):toBe("Ada 0")
				w.stop()
			end,
		})

		verifyHarness:case("a function readOnly flips live on the same editor, keeping the draft and the edit", {
			id = "native_fields::native TextInput readOnly, selectOnFocus and visibleLines::a function readOnly flips live on the same editor, keeping the draft and the edit",
			run = function()
				local lock, value = Compose.cell(false), Compose.cell("Ada")
				local w = world(function(UI: FacetControls)
					return UI.TextInput("Name")({
						value = value,
						readOnly = function(use: Use)
							return use(lock)
						end,
					})
				end)
				local field = w.node
				field:CaptureFocus()
				field.Text = "Ada!"
				expect((value:peek())):toBe("Ada!")
				lock:set(true)
				expect(w.node == field):toBe(true)
				expect(field.TextEditable):toBe(false)
				expect((field:IsFocused())):toBe(true)
				field.Text = "Ada!?"
				expect((value:peek())):toBe("Ada!")
				lock:set(false)
				expect(field.TextEditable):toBe(true)
				field.Text = "Ada!?"
				expect((value:peek())):toBe("Ada!?")
				w.stop()
			end,
		})

		verifyHarness:case("enabled and readOnly compose onto TextEditable in either order and recover", {
			id = "native_fields::native TextInput readOnly, selectOnFocus and visibleLines::enabled and readOnly compose onto TextEditable in either order and recover",
			run = function()
				local enabled, lock = Compose.cell(true), Compose.cell(true)
				local w = world(function(UI: FacetControls)
					return UI.TextInput("Name")({ value = Compose.cell(""), enabled = enabled, readOnly = lock })
				end)
				local field = w.node
				expect(field.TextEditable):toBe(false)
				enabled:set(false)
				lock:set(false)
				expect(field.TextEditable):toBe(false)
				enabled:set(true)
				expect(field.TextEditable):toBe(true)
				lock:set(true)
				enabled:set(false)
				lock:set(false)
				expect(field.TextEditable):toBe(false)
				enabled:set(true)
				expect(field.TextEditable):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("readOnly refuses anything but a boolean", {
			id = "native_fields::native TextInput readOnly, selectOnFocus and visibleLines::readOnly refuses anything but a boolean",
			run = function()
				expect(refused(function(UI: FacetControls)
					return UI.TextInput("Name")({ value = Compose.cell(""), readOnly = "yes" :: any })
				end) ~= nil):toBe(true)
			end,
		})

		verifyHarness:case(
			"the selectOnFocus policy lands on the same editor, live, and an illegal live word keeps the last",
			{
				id = "native_fields::native TextInput readOnly, selectOnFocus and visibleLines::the selectOnFocus policy lands on the same editor, live, and an illegal live word keeps the last",
				run = function()
					local policy = Compose.cell("all" :: "all" | "end" | "none")
					local w = world(function(UI: FacetControls)
						return UI.TextInput("Name")({ value = Compose.cell("12.5 km"), selectOnFocus = policy })
					end)
					local field = w.node
					expect((field:GetAttribute("selectOnFocus"))):toBe("all")
					policy:set("end")
					expect((field:GetAttribute("selectOnFocus"))):toBe("end")
					expect(w.node == field):toBe(true)
					local ok, err = pcall(function()
						policy:set("everything" :: any)
					end)
					expect(ok):toBe(false)
					expect(string.find(tostring(err), "selectOnFocus: one of none | all | end", 1, true) ~= nil):toBe(
						true
					)
					expect((field:GetAttribute("selectOnFocus"))):toBe("end")
					field:CaptureFocus()
					expect(`{field.CursorPosition} {field.SelectionStart}`):toBe("8 -1")
					w.stop()
					local plain = world(function(UI: FacetControls)
						return UI.TextInput("Name")({ value = Compose.cell("") })
					end)
					expect((plain.node:GetAttribute("selectOnFocus"))):toBeNil()
					plain.stop()
				end,
			}
		)

		verifyHarness:case("an unknown initial selectOnFocus word fails before mount", {
			id = "native_fields::native TextInput readOnly, selectOnFocus and visibleLines::an unknown initial selectOnFocus word fails before mount",
			run = function()
				for _, word in { "everything", 1 :: any } do
					local err = refused(function(UI: FacetControls)
						return UI.TextInput("Name")({ value = Compose.cell(""), selectOnFocus = word :: any })
					end)
					expect(`{tostring(word)} {err ~= nil}`):toBe(`{tostring(word)} true`)
				end
			end,
		})

		verifyHarness:case("the box is the count of lines it was told; one line is shorter and still multiline", {
			id = "native_fields::native TextInput readOnly, selectOnFocus and visibleLines::the box is the count of lines it was told; one line is shorter and still multiline",
			run = function()
				local heights = {}
				for _, count in { 1, 3, 5 } do
					local w = world(function(UI: FacetControls)
						return UI.TextInput("Name")({ value = Compose.cell(""), multiline = true, visibleLines = count })
					end)
					local viewport = find(w.node, "Input/Viewport")
					heights[count] = viewport.Size.Y.Offset
					expect(find(viewport, "Measure/Flow/Field").MultiLine):toBe(true)
					w.stop()
				end
				expect(`{heights[1] < heights[3]} {heights[3] < heights[5]}`):toBe("true true")
			end,
		})

		verifyHarness:case("past the count the box holds still while the editor grows inside it, on the same editor", {
			id = "native_fields::native TextInput readOnly, selectOnFocus and visibleLines::past the count the box holds still while the editor grows inside it, on the same editor",
			run = function()
				local value = Compose.cell("")
				local w = world(function(UI: FacetControls)
					return UI.TextInput("Name")({ value = value, multiline = true, visibleLines = 3 })
				end)
				local viewport = find(w.node, "Input/Viewport")
				local field = find(viewport, "Measure/Flow/Field")
				local before = viewport.Size
				value:set(string.rep("a line of notes\n", 20))
				expect(viewport.Size == before):toBe(true)
				expect(viewport.ClassName):toBe("ScrollingFrame")
				expect(viewport.AutomaticCanvasSize):toBe(w.E.AutomaticSize.None)
				expect(field.AutomaticSize):toBe(w.E.AutomaticSize.Y)
				local measure = find(viewport, "Measure")
				expect(measure.AutomaticSize):toBe(w.E.AutomaticSize.None)
				expect(measure.Size.Y.Offset >= 10000):toBe(true)
				find(viewport, "Measure/Flow").AbsoluteSize = w.engine.types.Vector2.new(300, 420)
				expect(viewport.CanvasSize.Y.Offset):toBe(420)
				expect(find(viewport, "Measure/Flow/Field") == field):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case(
			"the caret line stays in view: at the end the box shows the last line, back at the top the first",
			{
				id = "native_fields::native TextInput readOnly, selectOnFocus and visibleLines::the caret line stays in view: at the end the box shows the last line, back at the top the first",
				run = function()
					local value = Compose.cell(string.rep("a line of notes\n", 20))
					local w = world(function(UI: FacetControls)
						return UI.TextInput("Name")({ value = value, multiline = true, visibleLines = 3 })
					end)
					local V = w.engine.types.Vector2
					local viewport = find(w.node, "Input/Viewport")
					local field = find(viewport, "Measure/Flow/Field")
					viewport.AbsoluteWindowSize = V.new(300, 60)
					viewport.AbsoluteCanvasSize = V.new(300, 420)
					field.TextBounds = V.new(280, 420)
					field.CursorPosition = #field.Text + 1
					expect(viewport.CanvasPosition.Y):toBe(360)
					field.CursorPosition = 1
					expect(viewport.CanvasPosition.Y):toBe(0)
					w.stop()
				end,
			}
		)

		verifyHarness:case("a title that the engine left shorter than its text is measured again on the next frame", {
			id = "native_fields::native TextInput readOnly, selectOnFocus and visibleLines::a title that the engine left shorter than its text is measured again on the next frame",
			run = function()
				local listeners: { () -> () } = {}
				local frames = {
					Heartbeat = {
						Connect = function(_, callback: () -> ())
							table.insert(listeners, callback)
							return {
								Disconnect = function()
									local at = table.find(listeners, callback)
									if at then
										table.remove(listeners, at)
									end
								end,
							}
						end,
					},
				}
				local w = world(function(UI: FacetControls)
					return UI.TextInput("Name")({ value = Compose.cell(""), label = "Handle" })
				end, { runService = frames })
				local V = w.engine.types.Vector2
				local title = find(w.node, "Label/Title")
				local before = title.Size
				local changes = 0
				title:GetPropertyChangedSignal("Size"):Connect(function()
					changes += 1
				end)
				title.AbsoluteSize = V.new(200, 12)
				title.TextBounds = V.new(80, 14)
				expect(#listeners):toBe(1)
				listeners[1]()
				expect(title.Size.Y.Offset):toBe(before.Y.Offset + 1)
				listeners[1]()
				expect(title.Size == before):toBe(true)
				expect(changes):toBe(2)
				expect(#listeners):toBe(0)
				w.stop()
			end,
		})

		verifyHarness:case("an authored root size wins over the line count", {
			id = "native_fields::native TextInput readOnly, selectOnFocus and visibleLines::an authored root size wins over the line count",
			run = function()
				local w = world(function(UI: FacetControls, engine)
					return UI.TextInput("Name")({
						value = Compose.cell(""),
						multiline = true,
						visibleLines = 3,
						Size = engine.types.UDim2.fromOffset(300, 200),
					})
				end)
				expect(w.node.Size.Y.Offset):toBe(200)
				w.stop()
			end,
		})

		verifyHarness:case("a line count is a multiline fact and a whole number of at least one", {
			id = "native_fields::native TextInput readOnly, selectOnFocus and visibleLines::a line count is a multiline fact and a whole number of at least one",
			run = function()
				for _, bad in
					{
						{ visibleLines = 3 },
						{ multiline = true, visibleLines = 0 },
						{ multiline = true, visibleLines = 1.5 },
					}
				do
					local err = refused(function(UI: FacetControls)
						local spec: any = { value = Compose.cell("") }
						for key, entry in bad do
							spec[key] = entry
						end
						return UI.TextInput("Name")(spec)
					end)
					expect(err ~= nil):toBe(true)
				end
			end,
		})

		verifyHarness:case("a focused field scrolls its page up out from under the touch keyboard", {
			id = "native_fields::native TextInput readOnly, selectOnFocus and visibleLines::a focused field scrolls its page up out from under the touch keyboard",
			run = function()
				local worlds = require("./lib/content_world")
				local w = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.ScrollingFrame({
						Name = "Page",
						UI.TextInput("Name")({ value = Compose.cell("Ada") }),
					})
				end)
				local V2 = w.engine.types.Vector2
				local page, field = w.find("Page"), w.find("Name")
				page.AbsolutePosition, page.AbsoluteWindowSize, page.AbsoluteCanvasSize =
					V2.new(0, 0), V2.new(400, 800), V2.new(400, 1400)
				field.AbsolutePosition, field.AbsoluteSize = V2.new(0, 700), V2.new(400, 44)
				w.input.OnScreenKeyboardPosition = V2.new(0, 500)
				field.Focused.fire()
				expect(page.CanvasPosition.Y):toBe(0)
				w.input.OnScreenKeyboardVisible = true
				expect(page.CanvasPosition.Y >= 700 + 44 + 8 - 500):toBe(true)
				w.stop()
			end,
		})
	end)
end
