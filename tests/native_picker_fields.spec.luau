--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type ScreenGuiConstructor = typeof(require("@repo/tools/typecheck/aliases").ScreenGuiConstructor)
	type PickerOption = typeof(require("@repo/tools/typecheck/aliases").PickerOption)

	local Compose = require("../src/vendor/compose/core")
	local Roblox = require("../src/vendor/compose/roblox")
	local controls = require("../src/ui")
	local engines = require("./lib/native_engine")
	local expect = Verify.expect

	local THREE = {
		{ value = "easy", label = "Easy" },
		{ value = "normal", label = "Normal" },
		{ value = "hard", label = "Hard" },
	}

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
		local out = {}
		for _, node in root:GetDescendants() do
			if node.Name == name then
				table.insert(out, node)
			end
		end
		return out
	end

	local function world(spec: any, preferred: string?, tenFoot: boolean?): any
		local engine: any = engines.new()
		local gui = engine.new("GuiService")
		if tenFoot then
			gui.IsTenFootInterface = function()
				return true
			end
		end
		local input = engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		input.PreferredInput = engine.types.Enum.PreferredInput[preferred or "KeyboardAndMouse"]
		local runtime: ComposeRuntime = Roblox.createRuntime(engine)
		local UI: any = controls(Compose, runtime, {
			types = engine.types,
			services = { GuiService = gui, UserInputService = input },
		})
		local built = table.clone(spec)
		built.selected = built.selected or Compose.cell("normal")
		built.options = built.options or THREE
		local target = engine.new("Folder")
		local stop, screen: any = runtime.mount(function()
			return ((runtime.constructors.ScreenGui :: unknown) :: ScreenGuiConstructor)({ UI.Picker("P")(built) })
		end, target)
		return {
			engine = engine,
			gui = gui,
			input = input,
			runtime = runtime,
			screen = screen,
			selected = built.selected,
			E = engine.types.Enum,
			stop = function()
				stop()
				runtime:dispose()
			end,
		}
	end

	local function open(w: any)
		find(w.screen, "Trigger").Activated.fire()
	end

	verifyHarness:suite("native Picker menu field", function()
		verifyHarness:case(
			"the required mark rides the label and the error replaces the hint beside a danger trigger",
			{
				id = "native_picker_fields::native Picker menu field::the required mark rides the label and the error replaces the hint beside a danger trigger",
				run = function()
					local failure = Compose.cell("")
					local w = world({
						style = "menu" :: "menu",
						label = "Difficulty",
						requiredMark = "required" :: "required",
						hint = "Change it any time",
						errorText = failure,
					})
					expect(find(w.screen, "Label").Text):toBe("Difficulty *")
					local line, mark = find(w.screen, "Validation"), find(w.screen, "MessageMark")
					expect(line.Text):toBe("Change it any time")
					expect(mark.Visible):toBe(false)
					local trigger = find(w.screen, "Trigger")
					expect((trigger:HasTag("facet-invalid"))):toBe(false)
					local before = trigger.Size
					failure:set("Pick a difficulty to continue.")
					expect(line.Text):toBe("Pick a difficulty to continue.")
					expect((line:HasTag("facet-validation"))):toBe(true)
					expect(mark.Visible):toBe(true)
					expect((trigger:HasTag("facet-invalid"))):toBe(true)
					expect(trigger.Size == before):toBe(true)
					failure:set("")
					expect((trigger:HasTag("facet-invalid"))):toBe(false)
					w.stop()
				end,
			}
		)

		verifyHarness:case("a labelled menu picker stands its title above a trigger at the leading edge", {
			id = "native_picker_fields::native Picker menu field::a labelled menu picker stands its title above a trigger at the leading edge",
			run = function()
				local w = world({ style = "menu" :: "menu", label = "Driver" })
				local label = find(w.screen, "Label")
				local menu = find(w.screen, "Value")
				expect(label.Parent == menu.Parent):toBe(true)
				expect(label.LayoutOrder < menu.LayoutOrder):toBe(true)
				expect(label.Parent:FindFirstChildWhichIsA("UIListLayout").FillDirection):toBe(
					w.E.FillDirection.Vertical
				)
				expect(menu.AnchorPoint.X):toBe(0)
				expect(find(w.screen, "Trigger").Text):toBe("Normal")
				w.stop()
			end,
		})

		verifyHarness:case("appearance maps onto the trigger's paint live, and a word outside the family is refused", {
			id = "native_picker_fields::native Picker menu field::appearance maps onto the trigger's paint live, and a word outside the family is refused",
			run = function()
				local word = Compose.cell("standard")
				local w = world({ style = "menu" :: "menu", appearance = word })
				local trigger = find(w.screen, "Trigger")
				expect((trigger:HasTag("facet-accent"))):toBe(false)
				word:set("contrast")
				expect((trigger:HasTag("facet-accent"))):toBe(true)
				word:set("utility")
				expect((trigger:HasTag("facet-appearance-utility"))):toBe(true)
				expect(find(w.screen, "Trigger") == trigger):toBe(true)
				pcall(function()
					word:set("filled")
				end)
				expect((trigger:HasTag("facet-appearance-utility"))):toBe(true)
				w.stop()
				for _, bad: { style: "menu" | "inline", appearance: "stroke" | "utility" } in
					{
						{ style = "menu" :: "menu", appearance = "stroke" :: "stroke" },
						{ style = "inline" :: "inline", appearance = "utility" :: "utility" },
					} :: { { style: "menu" | "inline", appearance: "stroke" | "utility" } }
				do
					expect((pcall(world, bad))):toBe(false)
				end
			end,
		})

		verifyHarness:case("a named rung shrinks the trigger, corners reach it, and it still opens", {
			id = "native_picker_fields::native Picker menu field::a named rung shrinks the trigger, corners reach it, and it still opens",
			run = function()
				local w = world({
					style = "menu" :: "menu",
					controlSize = "compact" :: "compact",
					corners = "pill" :: "pill",
				})
				local trigger = find(w.screen, "Trigger")
				expect(trigger.Size.Y.Offset):toBe(36)
				expect(trigger:FindFirstChildWhichIsA("UICorner").CornerRadius.Scale):toBe(1)
				open(w)
				expect(find(w.screen, "normal") ~= nil):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("the hint line belongs to the picker: disposal releases it for every style", {
			id = "native_picker_fields::native Picker menu field::the hint line belongs to the picker: disposal releases it for every style",
			run = function()
				for _, style in
					{ "menu", "segmented", "cards", "inline" } :: { "cards" | "inline" | "menu" | "segmented" }
				do
					local engine: any = engines.new()
					local runtime: ComposeRuntime = Roblox.createRuntime(engine)
					local UI: any = controls(Compose, runtime, { types = engine.types })
					local before = engine.census()
					local stop = runtime.mount(function()
						return UI.Picker("P")({
							style = style :: "cards" | "inline" | "menu" | "segmented",
							selected = Compose.cell("normal"),
							options = THREE,
							hint = "Change it any time",
						})
					end, engine.new("ScreenGui"))
					stop()
					expect(`{style} {engine.census().connections - before.connections}`):toBe(`{style} 0`)
					runtime:dispose()
				end
			end,
		})
	end)

	verifyHarness:suite("native Picker menu panel", function()
		local LONG = {}
		for i = 1, 30 do
			table.insert(LONG, { value = `v{i}`, label = `Option {i}` })
		end

		verifyHarness:case("maxHeight bounds the whole panel, ordinary and searchable, and a bad cap is refused", {
			id = "native_picker_fields::native Picker menu panel::maxHeight bounds the whole panel, ordinary and searchable, and a bad cap is refused",
			run = function()
				local w =
					world({ style = "menu" :: "menu", options = LONG, maxHeight = 96, selected = Compose.cell("v1") })
				open(w)
				local panel = find(w.screen, "MenuPanel")
				find(panel, "MenuRows").AbsoluteSize = w.engine.types.Vector2.new(280, 30 * 44)
				expect(panel.Size.Y.Offset <= 96):toBe(true)
				w.stop()
				local searchable = world({
					style = "navigationLink" :: "navigationLink",
					options = LONG,
					query = Compose.cell(""),
					maxHeight = 96,
					selected = Compose.cell("v1"),
				})
				searchable.screen.AbsoluteSize = searchable.engine.types.Vector2.new(800, 600)
				find(searchable.screen, "P").Activated.fire()
				local body = find(find(searchable.screen, "PopoverModal"), "Body")
				expect(find(body, "Choices") ~= nil):toBe(true)
				find(body, "Flow").AbsoluteSize = searchable.engine.types.Vector2.new(400, 1320)
				expect(body.Size.Y.Offset):toBe(96 - 16)
				searchable.stop()
				local tiny = world({ style = "menu" :: "menu", options = LONG, maxHeight = 10 })
				open(tiny)
				local tinyPanel = find(tiny.screen, "MenuPanel")
				find(tinyPanel, "MenuRows").AbsoluteSize = tiny.engine.types.Vector2.new(280, 30 * 44)
				expect(tinyPanel.Size.Y.Offset >= 44):toBe(true)
				tiny.stop()
				for _, bad in { 0, math.huge, 0 / 0, "96" } :: { any } do
					expect((pcall(world, { style = "menu" :: "menu", maxHeight = bad }))):toBe(false)
				end
				expect((pcall(world, { style = "segmented" :: "segmented", maxHeight = 96 }))):toBe(false)
			end,
		})

		verifyHarness:case("opening lands on the selected row with gamepad or keyboard selection", {
			id = "native_picker_fields::native Picker menu panel::opening lands on the selected row with gamepad or keyboard selection",
			run = function()
				for _, preferred in { "Gamepad", "KeyboardAndMouse" } do
					local w = world(
						{ style = "menu" :: "menu", options = LONG, maxHeight = 200, selected = Compose.cell("v25") },
						preferred
					)
					w.gui.SelectedObject = find(w.screen, "Trigger")
					open(w)
					local target = w.gui.SelectedObject
					expect(`{preferred} {target and target.Name}`):toBe(`{preferred} v25`)
					w.stop()
				end
			end,
		})
	end)

	verifyHarness:suite("native Picker menu rows", function()
		verifyHarness:case("an option avatar's keys are closed: a misspelt one is refused by name", {
			id = "native_picker_fields::native Picker menu rows::an option avatar's keys are closed: a misspelt one is refused by name",
			run = function()
				local ok, err = pcall(function()
					local w = world({
						style = "menu" :: "menu",
						options = { { value = "a", label = "Ada", avatar = { name = "Ada", userID = 1 } } },
					})
					open(w)
				end)
				expect(ok):toBe(false)
				expect(string.find(tostring(err), "userID", 1, true) ~= nil):toBe(true)
			end,
		})

		verifyHarness:case(
			"an avatar leads its row without a second stop or press, and a disabled row is unreachable",
			{
				id = "native_picker_fields::native Picker menu rows::an avatar leads its row without a second stop or press, and a disabled row is unreachable",
				run = function()
					local selected = Compose.cell("a")
					local w = world({
						style = "menu" :: "menu",
						selected = selected,
						options = {
							{ value = "a", label = "Ada", avatar = { name = "Ada" } },
							{ value = "b", label = "Bo", avatar = { name = "Bo" }, badge = 2 },
							{ value = "c", label = "Cy", avatar = { name = "Cy" }, enabled = false },
						},
					})
					open(w)
					local row = find(w.screen, "b")
					local avatar = find(row, "Avatar")
					expect(avatar ~= nil):toBe(true)
					expect(avatar.Selectable):toBe(false)
					expect(avatar.Active):toBe(false)
					expect(avatar.Interactable):toBe(false)
					expect(
						avatar.LayoutOrder
							< find(row, "Content"):FindFirstChildWhichIsA("TextLabel", true).LayoutOrder + 100
					):toBe(true)
					expect(find(find(row, "Accessories"), "Count").Text):toBe("2")
					local disabled = find(w.screen, "c")
					expect(disabled.Interactable):toBe(false)
					disabled.Activated.fire()
					expect((selected:peek())):toBe("a")
					row.Activated.fire()
					expect((selected:peek())):toBe("b")
					w.stop()
				end,
			}
		)

		verifyHarness:case("badge, meta and sectionTitle reach the menu engine from an automatic picker", {
			id = "native_picker_fields::native Picker menu rows::badge, meta and sectionTitle reach the menu engine from an automatic picker",
			run = function()
				local w = world({
					options = {
						{ value = "easy", label = "Easy", sectionTitle = "Casual" } :: PickerOption,
						{ value = "normal", label = "Normal", badge = 3, meta = "Crew" } :: PickerOption,
						{ value = "hard", label = "Hard", sectionTitle = "Ranked", badge = "New" } :: PickerOption,
					},
				})
				find(w.screen, "LabelMeasure").TextBounds = w.engine.types.Vector2.new(190, 18)
				find(w.screen, "P").AbsoluteSize = w.engine.types.Vector2.new(200, 44)
				open(w)
				expect(find(find(find(w.screen, "normal"), "Accessories"), "Count").Text):toBe("3")
				expect(find(find(w.screen, "normal"), "Meta").Text):toBe("Crew")
				local headings = {}
				for _, node in all(w.screen, "SectionTitle") do
					table.insert(headings, node.Text)
					expect(node.ClassName):toBe("TextLabel")
				end
				table.sort(headings)
				expect((table.concat(headings, " "))):toBe("Casual Ranked")
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native Picker segmented vocabulary and the radio mark", function()
		verifyHarness:case("appearance paints the track filled, stroked or not at all, live, and refuses a menu word", {
			id = "native_picker_fields::native Picker segmented vocabulary and the radio mark::appearance paints the track filled, stroked or not at all, live, and refuses a menu word",
			run = function()
				local word = Compose.cell("filled")
				local w = world({ style = "segmented" :: "segmented", appearance = word })
				local track = find(w.screen, "P")
				expect((track:HasTag("facet-segmented"))):toBe(true)
				expect((track:HasTag("facet-segmented-stroke"))):toBe(false)
				word:set("stroke")
				expect((track:HasTag("facet-segmented-stroke"))):toBe(true)
				word:set("utility")
				expect((track:HasTag("facet-segmented-utility"))):toBe(true)
				expect((track:HasTag("facet-segmented-stroke"))):toBe(false)
				pcall(function()
					word:set("contrast")
				end)
				expect((track:HasTag("facet-segmented-utility"))):toBe(true)
				w.stop()
				expect((pcall(world, { style = "segmented" :: "segmented", appearance = "contrast" }))):toBe(false)
			end,
		})

		verifyHarness:case("an automatic picker keeps its appearance intent across a live family switch", {
			id = "native_picker_fields::native Picker segmented vocabulary and the radio mark::an automatic picker keeps its appearance intent across a live family switch",
			run = function()
				local w = world({ appearance = "contrast" }, "KeyboardAndMouse")
				find(w.screen, "LabelMeasure").TextBounds = w.engine.types.Vector2.new(190, 18)
				find(w.screen, "P").AbsoluteSize = w.engine.types.Vector2.new(200, 44)
				local presentation = find(w.screen, "Presentation")
				local trigger = find(presentation, "Trigger")
				expect(trigger ~= nil and trigger:HasTag("facet-accent")):toBe(true)
				find(w.screen, "P").AbsoluteSize = w.engine.types.Vector2.new(800, 44)
				local strip = find(w.screen, "Presentation")
				expect((strip:HasTag("facet-segmented-stroke"))):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case(
			"automatic modes use segments on a phone when the measured labels fit and keep selection through fallback",
			{
				id = "native_picker_fields::native Picker segmented vocabulary and the radio mark::automatic modes use segments on a phone when the measured labels fit and keep selection through fallback",
				run = function()
					local w = world({
						options = {
							{ value = "swatches", label = "Swatches" },
							{ value = "spectrum", label = "Spectrum" },
							{ value = "sliders", label = "Sliders" },
							{ value = "brick", label = "Bricks" },
						},
						selected = Compose.cell("swatches"),
					}, "Touch")
					local picker, measure = find(w.screen, "P"), find(w.screen, "LabelMeasure")
					measure.TextBounds = w.engine.types.Vector2.new(220, 18)
					picker.AbsoluteSize = w.engine.types.Vector2.new(341, 44)
					expect((find(w.screen, "Presentation"):HasTag("facet-segmented"))):toBe(true)
					find(w.screen, "spectrum").Activated.fire()
					expect((w.selected:peek())):toBe("spectrum")
					picker.AbsoluteSize = w.engine.types.Vector2.new(330, 44)
					expect(find(w.screen, "Trigger").Text):toBe("Spectrum")
					picker.AbsoluteSize = w.engine.types.Vector2.new(341, 44)
					measure.TextBounds = w.engine.types.Vector2.new(300, 24)
					expect(find(w.screen, "Trigger").Text):toBe("Spectrum")
					measure.TextBounds = w.engine.types.Vector2.new(220, 18)
					expect((find(w.screen, "Presentation"):HasTag("facet-segmented"))):toBe(true)
					expect((w.selected:peek())):toBe("spectrum")
					w.stop()
				end,
			}
		)

		verifyHarness:case("corners reach the strip, and a rung shrinks the segments", {
			id = "native_picker_fields::native Picker segmented vocabulary and the radio mark::corners reach the strip, and a rung shrinks the segments",
			run = function()
				local pill = world({ style = "segmented" :: "segmented", corners = "pill" :: "pill" })
				expect(find(pill.screen, "Corners").CornerRadius.Scale):toBe(1)
				pill.stop()
				local square = world({ style = "segmented" :: "segmented", corners = "square" :: "square" })
				expect(find(square.screen, "Corners").CornerRadius.Scale):toBe(0)
				square.stop()
				local compact = world({ style = "segmented" :: "segmented", controlSize = "compact" :: "compact" })
				expect(find(compact.screen, "P").Size.Y.Offset):toBe(36)
				for _, key in { "easy", "normal", "hard" } do
					expect(find(compact.screen, key).Size.Y.Scale):toBe(1)
				end
				compact.stop()
			end,
		})

		verifyHarness:case(
			"indicatorPosition moves the radio mark to either edge, and belongs to the radio group only",
			{
				id = "native_picker_fields::native Picker segmented vocabulary and the radio mark::indicatorPosition moves the radio mark to either edge, and belongs to the radio group only",
				run = function()
					for _, edge in { "leading", "trailing" } :: { "leading" | "trailing" } do
						local w = world({
							style = "radioGroup" :: "radioGroup",
							indicatorPosition = edge :: "leading" | "trailing",
						})
						local mark = find(find(w.screen, "normal"), "Indicator")
						local title = find(find(w.screen, "normal"), "Captions")
						expect(mark.Parent):toBe(title.Parent)
						expect(`{edge}: {mark.LayoutOrder > title.LayoutOrder}`):toBe(`{edge}: {edge == "trailing"}`)
						expect(find(mark, "Dot").Visible):toBe(true)
						expect(find(find(find(w.screen, "easy"), "Indicator"), "Dot").Visible):toBe(false)
						w.stop()
					end
					expect(
						(
							pcall(
								world,
								{ style = "segmented" :: "segmented", indicatorPosition = "trailing" :: "trailing" }
							)
						)
					):toBe(false)
				end,
			}
		)
	end)

	verifyHarness:suite("native Picker cards", function()
		local CARDS = {
			{ value = "sprint", label = "Sprint", description = "Three short laps", meta = "3 laps", icon = "flag" },
			{ value = "endurance", label = "Endurance", description = "A long race", meta = "20 laps", icon = "flag" },
			{
				value = "locked",
				label = "Night",
				description = "Unlocks at level 10",
				meta = "Soon",
				icon = "flag",
				enabled = false,
			},
		}

		verifyHarness:case("each option is a bordered card with its meta, the chosen one plated, on every input", {
			id = "native_picker_fields::native Picker cards::each option is a bordered card with its meta, the chosen one plated, on every input",
			run = function()
				local selected = Compose.cell("sprint")
				local w = world({ style = "cards" :: "cards", options = CARDS, selected = selected })
				local card = find(w.screen, "Card-endurance")
				expect((card:HasTag("facet-card-option"))):toBe(true)
				expect((find(w.screen, "Card-sprint"):HasTag("facet-accent"))):toBe(true)
				expect((card:HasTag("facet-accent"))):toBe(false)
				expect(find(card, "Meta").Text):toBe("20 laps")
				card.Activated.fire()
				expect((selected:peek())):toBe("endurance")
				expect((card:HasTag("facet-accent"))):toBe(true)
				local locked = find(w.screen, "Card-locked")
				expect(locked.Selectable):toBe(false)
				locked.Activated.fire()
				expect((selected:peek())):toBe("endurance")
				w.stop()
			end,
		})

		verifyHarness:case("choosing the chosen card again clears it only when the selection is not required", {
			id = "native_picker_fields::native Picker cards::choosing the chosen card again clears it only when the selection is not required",
			run = function()
				local optional = Compose.cell("sprint")
				local w = world({ style = "cards" :: "cards", options = CARDS, selected = optional, required = false })
				find(w.screen, "Card-sprint").Activated.fire()
				expect((optional:peek())):toBeNil()
				w.stop()
				local kept = Compose.cell("sprint")
				local w2 = world({ style = "cards" :: "cards", options = CARDS, selected = kept })
				find(w2.screen, "Card-sprint").Activated.fire()
				expect((kept:peek())):toBe("sprint")
				w2.stop()
			end,
		})

		verifyHarness:case("a long radio or card label wraps inside its row instead of running past it", {
			id = "native_picker_fields::native Picker cards::a long radio or card label wraps inside its row instead of running past it",
			run = function()
				local LONG = { { value = "a", label = string.rep("A long label ", 12) }, { value = "b", label = "B" } }
				for _, style in { "radioGroup", "cards" } :: { "cards" | "radioGroup" } do
					local w =
						world({ style = style :: "cards" | "radioGroup", options = LONG, selected = Compose.cell("b") })
					local button = find(w.screen, if style == "cards" then "Card-a" else "a")
					local box = if style == "cards" then button else find(w.screen, "P")
					box.AbsoluteSize = w.engine.types.Vector2.new(300, 44)
					local title = find(button, "Title")
					expect(`{style} {title.TextWrapped}`):toBe(`{style} true`)
					local limit = title:FindFirstChildWhichIsA("UISizeConstraint")
					expect(`{style} {limit ~= nil and limit.MaxSize.X < 300}`):toBe(`{style} true`)
					w.stop()
				end
			end,
		})

		verifyHarness:case("a row of cards wraps and long copy wraps inside its card; cards take no appearance", {
			id = "native_picker_fields::native Picker cards::a row of cards wraps and long copy wraps inside its card; cards take no appearance",
			run = function()
				local w = world({ style = "cards" :: "cards", options = CARDS, axis = "x" :: "x" })
				local layout = find(w.screen, "Cards"):FindFirstChildWhichIsA("UIListLayout")
				expect(layout.FillDirection):toBe(w.E.FillDirection.Horizontal)
				expect(layout.Wraps):toBe(true)
				local card = find(w.screen, "Card-sprint")
				expect(card.AutomaticSize):toBe(w.E.AutomaticSize.Y)
				w.stop()
				expect((pcall(world, { style = "cards" :: "cards", options = CARDS, appearance = "utility" }))):toBe(
					false
				)
			end,
		})
	end)

	verifyHarness:suite("native Picker option indicator and search rows", function()
		verifyHarness:case("follows the caller's live option record: status changes and a removed mark goes", {
			id = "native_picker_fields::native Picker option indicator and search rows::follows the caller's live option record: status changes and a removed mark goes",
			run = function()
				local function options(indicator: any?)
					return {
						{ value = "easy", label = "Easy" },
						{ value = "normal", label = "Normal", indicator = indicator },
						{ value = "hard", label = "Hard" },
					}
				end
				local list = Compose.cell(options({ status = "warning" }))
				local w = world({ style = "radioGroup" :: "radioGroup", options = list })
				local function status(): string
					local mark = find(find(w.screen, "normal"), "Status")
					if mark == nil then
						return "none"
					end
					for _, tag in mark:GetTags() do
						if string.sub(tag, 1, 13) == "facet-status-" and tag ~= "facet-status-hollow" then
							return tag
						end
					end
					return "untagged"
				end
				expect((status())):toBe("facet-status-warning")
				list:set(options({ status = "error" }))
				expect((status())):toBe("facet-status-error")
				list:set(options(nil))
				expect((status())):toBe("none")
				w.stop()
			end,
		})

		verifyHarness:case("a searchable list's chosen row paints no wash and wears a check instead", {
			id = "native_picker_fields::native Picker option indicator and search rows::a searchable list's chosen row paints no wash and wears a check instead",
			run = function()
				local w = world({ label = "Track", query = Compose.cell("") }, "Touch")
				find(w.screen, "Presentation").Activated.fire()
				local row = find(find(w.screen, "Choices"), "normal")
				expect((row:HasTag("facet-selected"))):toBe(false)
				expect((row:HasTag("facet-choice-current"))):toBe(false)
				expect(find(row, "TrailingIcon").Visible):toBe(true)
				expect(find(find(find(w.screen, "Choices"), "easy"), "TrailingIcon").Visible):toBe(false)
				w.stop()
			end,
		})

		verifyHarness:case("a navigation link keeps its title and value in one row", {
			id = "native_picker_fields::native Picker option indicator and search rows::a navigation link keeps its title and value in one row",
			run = function()
				local w = world({ label = "Track", style = "navigationLink" :: "navigationLink" })
				local trigger = find(w.screen, "P")
				local value = find(trigger, "Trailing")
				expect(value.Text):toBe("Normal")
				expect(value.Parent == find(trigger, "Content")):toBe(true)
				local button = if trigger:IsA("GuiButton")
					then trigger
					else trigger:FindFirstChildWhichIsA("GuiButton", true)
				expect(button.Size.Y.Offset >= 44):toBe(true)
				expect(button.Size.X.Scale):toBe(1)
				expect(find(trigger, "TrailingIcon").LayoutOrder > value.LayoutOrder):toBe(true)
				w.selected:set("hard")
				expect(value.Text):toBe("Hard")
				w.stop()
			end,
		})

		verifyHarness:case("a segment whose live options carry no description centres its caption like a plain label", {
			id = "native_picker_fields::native Picker option indicator and search rows::a segment whose live options carry no description centres its caption like a plain label",
			run = function()
				local w = world({ style = "segmented" :: "segmented", options = Compose.cell(THREE) })
				local content = find(find(w.screen, "hard"), "Content")
				expect(content.Size.X.Scale):toBe(1)
				expect(content:FindFirstChildWhichIsA("UIListLayout").HorizontalAlignment):toBe(
					w.E.HorizontalAlignment.Center
				)
				w.stop()
			end,
		})

		verifyHarness:case("a vertical segmented strip grows to its segments and spreads them over a taller box", {
			id = "native_picker_fields::native Picker option indicator and search rows::a vertical segmented strip grows to its segments and spreads them over a taller box",
			run = function()
				local w = world({
					style = "segmented" :: "segmented",
					axis = "y" :: "y",
					iconOnly = true,
					options = {
						{ value = "easy", label = "Easy", icon = "edit" },
						{ value = "normal", label = "Normal", icon = "flag" },
					},
					Size = engines.new().types.UDim2.fromOffset(52, 60),
				})
				local strip = find(w.screen, "P")
				expect(strip.AutomaticSize):toBe(w.E.AutomaticSize.Y)
				expect(strip:FindFirstChildWhichIsA("UIListLayout").VerticalFlex):toBe(w.E.UIFlexAlignment.Fill)
				expect(find(strip, "easy").AutomaticSize):toBe(w.E.AutomaticSize.Y)
				w.stop()
			end,
		})

		verifyHarness:case("an automatic picker lists its options as rows at ten feet, whatever the pointer", {
			id = "native_picker_fields::native Picker option indicator and search rows::an automatic picker lists its options as rows at ten feet, whatever the pointer",
			run = function()
				local five = table.clone(THREE)
				table.insert(five, { value = "expert", label = "Expert" })
				table.insert(five, { value = "master", label = "Master" })
				local near = world({ options = five }, "KeyboardAndMouse")
				near.screen.AbsoluteSize = near.engine.types.Vector2.new(300, 600)
				expect(find(near.screen, "Trigger") ~= nil):toBe(true)
				near.stop()
				local far = world({ options = five }, "KeyboardAndMouse", true)
				expect((find(far.screen, "Trigger"))):toBeNil()
				expect(find(far.screen, "master") ~= nil):toBe(true)
				far.stop()
			end,
		})
		verifyHarness:case(
			"a navigation link opens its list in a panel attached to the control, without dimming the page",
			{
				id = "native_picker_fields::native Picker option indicator and search rows::a navigation link opens its list in a panel attached to the control, without dimming the page",
				run = function()
					local w = world({ label = "Track", style = "navigationLink" :: "navigationLink" })
					w.screen.AbsoluteSize = w.engine.types.Vector2.new(800, 600)
					local trigger = find(w.screen, "P")
					trigger.AbsolutePosition = w.engine.types.Vector2.new(100, 100)
					trigger.AbsoluteSize = w.engine.types.Vector2.new(300, 44)
					trigger.Activated.fire()
					local modal = find(w.screen, "PopoverModal")
					expect(modal ~= nil):toBe(true)
					local backdrop = find(modal, "DismissOutside")
					expect(backdrop.BackgroundTransparency):toBe(1)
					expect((backdrop:HasTag("facet-scrim"))):toBe(false)
					local panel = find(modal, "Panel")
					expect((panel:HasTag("facet-panel"))):toBe(true)
					panel.AbsoluteSize = w.engine.types.Vector2.new(344, 200)
					local left = panel.Position.X.Offset - panel.AnchorPoint.X * 344
					local top = panel.Position.Y.Offset - panel.AnchorPoint.Y * 200
					expect(math.abs(left + 344 - 400) < 1):toBe(true)
					expect(top > 144):toBe(true)
					expect(find(panel, "PickerSearch") ~= nil):toBe(true)
					expect(find(modal, "Tail") ~= nil):toBe(true)
					find(find(panel, "Choices"), "hard").Activated.fire()
					expect((w.selected:peek())):toBe("hard")
					expect((find(w.screen, "PopoverModal"))):toBeNil()
					w.stop()
				end,
			}
		)
	end)
end
