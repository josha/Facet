--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type ScreenGuiConstructor = typeof(require("@repo/tools/typecheck/aliases").ScreenGuiConstructor)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type FolderConstructor = typeof(require("@repo/tools/typecheck/aliases").FolderConstructor)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local ThemeTypes = require("../src/ui/theme_types")
	local cells = require("./lib/cells")
	local FixtureComposeTypes = require("../src/vendor/compose/core")
	local FixtureNavigationTypes = require("../src/ui/navigation_types")
	local FixtureCollectionTypes = require("../src/ui/collection_types")

	local Facet = require("../src")
	local engines = require("./lib/native_engine")
	local Roblox = require("@lune/roblox")
	local Vector2, UDim2 = Roblox.Vector2, Roblox.UDim2
	local Compose: ComposeModule = Facet.Compose
	local themes = Facet.themes
	local expect = Verify.expect

	local function find(root: any, name: string): any
		if root == nil then
			return nil
		end
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

	local function world(build: (any, any, any) -> any, options: { [string]: any }?): any
		local o: { [string]: any } = options or {}
		local engine: any = engines.new({
			measureText = function(node: any): any
				local text = node.Text or ""
				return Vector2.new(#text * 11, if #text > 0 then 20 else 0)
			end,
		})
		local gui = engine.new("GuiService")
		local input = engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local UI: any = Facet.controls(
			runtime,
			{
				types = engine.types,
				services = { GuiService = gui, UserInputService = input },
				theme = o.theme,
				environment = o.environment,
			} :: any
		)
		local stop, screen: any = runtime.mount(function()
			return ((runtime.constructors.ScreenGui :: unknown) :: ScreenGuiConstructor)({
				build(UI, runtime.constructors, engine),
			})
		end, engine.new("Folder"))
		return {
			engine = engine,
			runtime = runtime,
			screen = screen,
			UI = UI,
			step = function(count: number?)
				for _ = 1, count or 1 do
					engine.heartbeat.fire(1 / 60)
				end
			end,
			stop = function()
				stop()
				runtime:dispose()
			end,
		}
	end

	local function sheetFor(w: any, package: any): any
		local _, sheet = w.runtime.mount(function()
			return themes.createStyleSheet(
				w.runtime,
				package,
				{
					types = w.engine.types,
					preferredTransparency = 1,
					motionLevel = "normal",
				} :: any
			)
		end, w.engine.new("Folder"))
		return sheet
	end

	local function rule(sheet: any, selector: string): any
		for _, node in sheet:GetChildren() do
			if node.Selector == selector then
				return node
			end
		end
		return nil
	end

	verifyHarness:suite("Toggle switch follows controlSize", function()
		verifyHarness:case("each rung draws its own track and knob; no rung keeps the 38 by 24 switch", {
			id = "native_ported_behaviours::Toggle switch follows controlSize::each rung draws its own track and knob; no rung keeps the 38 by 24 switch",
			run = function()
				local rung = Compose.cell("compact" :: "compact" | "large" | "regular" | "xsmall")
				local w = world(function(UI: FacetControls)
					return UI.VStack {
						UI.Toggle "Plain" { value = Compose.cell(true), label = "Sound" } :: unknown,
						UI.Toggle "Sized" { value = Compose.cell(true), label = "Music", controlSize = rung },
					}
				end)
				local plain = find(find(w.screen, "Plain"), "Indicator")
				expect(plain.Size.X.Offset .. "x" .. plain.Size.Y.Offset):toBe("38x24")
				local indicator = find(find(w.screen, "Sized"), "Indicator")
				local mark = find(indicator, "Mark")
				expect(indicator.Size.X.Offset .. "x" .. indicator.Size.Y.Offset):toBe("32x20")
				expect(mark.Size.X.Offset):toBe(14)
				expect(indicator.Position.X.Offset):toBe(-40)
				rung:set("large")
				w.step()
				expect(indicator.Size.X.Offset .. "x" .. indicator.Size.Y.Offset):toBe("44x28")
				expect(mark.Size.X.Offset):toBe(22)
				expect(find(indicator, "UICorner").CornerRadius.Offset):toBe(14)
				rung:set("regular")
				w.step()
				expect(indicator.Size.X.Offset .. "x" .. indicator.Size.Y.Offset):toBe("38x24")
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("voice and contrast statuses", function()
		verifyHarness:case(
			"StatusIndicator and Badge take voice and contrast; voice defaults between warning and danger",
			{
				id = "native_ported_behaviours::voice and contrast statuses::StatusIndicator and Badge take voice and contrast; voice defaults between warning and danger",
				run = function()
					local status = Compose.cell(
						"voice" :: "accent" | "contrast" | "error" | "info" | "neutral" | "success" | "voice" | "warning"
					)
					local w = world(function(UI: FacetControls)
						return UI.VStack {
							UI.StatusIndicator "Dot" { status = status } :: unknown,
							UI.Badge "Tag" { label = "Live", status = "contrast" :: "contrast" },
						}
					end)
					local dot = find(w.screen, "Dot")
					expect((dot:HasTag("facet-status-voice"))):toBe(true)
					status:set("contrast")
					expect((dot:HasTag("facet-status-contrast"))):toBe(true)
					expect((dot:HasTag("facet-status-voice"))):toBe(false)
					expect((find(w.screen, "Tag"):HasTag("facet-status-contrast"))):toBe(true)
					local package = themes.neutralPackage()
					local sheet = sheetFor(w, package)
					local colors = package.style.themes[1].colors
					local warning, danger = colors.warning :: any, colors.danger :: any
					local voice = rule(sheet, ".facet-status-voice"):GetProperties().BackgroundColor3
					expect(math.abs(voice.R - (warning.r + danger.r) / 2) < 1e-6):toBe(true)
					expect(math.abs(voice.G - (warning.g + danger.g) / 2) < 1e-6):toBe(true)
					local strong = colors.contentStrong :: any
					local contrast = rule(sheet, ".facet-status-contrast"):GetProperties().BackgroundColor3
					expect(math.abs(contrast.R - strong.r) < 1e-6):toBe(true)
					assert(package.style.themes[1].extra).voice = { r = 0.1, g = 0.2, b = 0.3 }
					local authored = rule(sheetFor(w, package), ".facet-status-voice"):GetProperties().BackgroundColor3
					expect(math.abs(authored.B - 0.3) < 1e-6):toBe(true)
					w.stop()
				end,
			}
		)
	end)

	verifyHarness:suite("Avatar faces, in-experience ring and background", function()
		verifyHarness:case("an icon face replaces the initials, also for a group member", {
			id = "native_ported_behaviours::Avatar faces, in-experience ring and background::an icon face replaces the initials, also for a group member",
			run = function()
				local w = world(function(UI: FacetControls)
					return UI.VStack {
						UI.Avatar "Guest" { name = "Guest Player", icon = "person" } :: unknown,
						UI.AvatarGroup "Group" { items = { { id = "g", name = "Guest", icon = "person" } } },
					}
				end)
				local guest = find(w.screen, "Guest")
				expect(find(guest, "Face") ~= nil):toBe(true)
				expect(find(guest, "Initials").Visible):toBe(false)
				local member = find(find(w.screen, "Group"), "g")
				expect(find(member, "Face") ~= nil):toBe(true)
				expect(find(member, "Initials").Visible):toBe(false)
				expect(function()
					w.UI.Avatar { name = "A", icon = "person", image = "rbxassetid://1" }
				end):toThrow()
				w.stop()
			end,
		})

		verifyHarness:case("inExperience rings the face in accent with a surface gap and no corner mark", {
			id = "native_ported_behaviours::Avatar faces, in-experience ring and background::inExperience rings the face in accent with a surface gap and no corner mark",
			run = function()
				local presence: FixtureComposeTypes.Cell<("away" | "busy" | "inExperience" | "offline" | "online")?> =
					cells.presence("inExperience")
				local w = world(function(UI: FacetControls)
					return UI.Avatar "A" { name = "Ada", presence = presence, background = "success" }
				end)
				local avatar = find(w.screen, "A")
				local ring = find(avatar, "PresenceRing")
				expect(ring.Visible):toBe(true)
				expect((ring:FindFirstChildWhichIsA("UIStroke"):HasTag("facet-avatar-ring"))):toBe(true)
				expect((find(ring, "Gap"):FindFirstChildWhichIsA("UIStroke"):HasTag("facet-avatar-ring-gap"))):toBe(
					true
				)
				expect(find(avatar, "Presence").Visible):toBe(false)
				expect((avatar:HasTag("facet-avatar-background-success"))):toBe(true)
				presence:set("online")
				expect(ring.Visible):toBe(false)
				expect(find(avatar, "Presence").Visible):toBe(true)
				local sheet = sheetFor(w, themes.neutralPackage())
				expect(rule(sheet, ".facet-avatar-ring"):GetProperties().Transparency):toBe(0)
				expect(rule(sheet, ".facet-avatar-background-success") ~= nil):toBe(true)
				expect(function()
					w.UI.Avatar { name = "A", background = "rainbow" }
				end):toThrow()
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("Alert suppression", function()
		verifyHarness:case("the do-not-ask-again checkbox sits below the actions", {
			id = "native_ported_behaviours::Alert suppression::the do-not-ask-again checkbox sits below the actions",
			run = function()
				local w = world(function(UI: FacetControls)
					return UI.Alert {
						isPresented = Compose.cell(true),
						title = "Delete save?",
						suppression = { isSuppressed = Compose.cell(false) },
						actions = {
							{ id = "Delete", label = "Delete", role = "destructive" :: "destructive" } :: FixtureNavigationTypes.AlertAction<any>,
							{ id = "Keep", label = "Keep", role = "cancel" :: "cancel" } :: FixtureNavigationTypes.AlertAction<any>,
						},
					}
				end)
				w.step(30)
				local toggle = find(w.screen, "Suppression")
				local actions = find(w.screen, "Actions")
				expect((find(find(w.screen, "AlertContent"), "Suppression"))):toBe(nil)
				expect(toggle.Parent):toBe(actions.Parent)
				expect(toggle.LayoutOrder > actions.LayoutOrder):toBe(true)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("Card ring", function()
		verifyHarness:case(
			"a selected card keeps the live shared focus look and asks it to reach the whole card, or the artwork",
			{
				id = "native_ported_behaviours::Card ring::a selected card keeps the live shared focus look and asks it to reach the whole card, or the artwork",
				run = function()
					for _, target in { "card", "media" } do
						local w = world(function(UI: FacetControls)
							return UI.Card "C" {
								image = "rbxassetid://1",
								title = "Track",
								onActivate = function() end,
								primaryAction = { label = "Play", onActivate = function() end },
								ringTarget = if target == "media" then "media" :: "media" else nil,
								Size = UDim2.fromOffset(160, 0),
							}
						end)
						w.step(5)
						local body = find(w.screen, "Body")
						expect((find(w.screen, "CardRingPaint"))):toBe(nil)
						find(w.screen, "C").AbsoluteSize = Vector2.new(160, 200)
						body.AbsoluteSize = Vector2.new(160, 150)
						find(w.screen, "Artwork").AbsoluteSize = Vector2.new(160, 90)
						w.step()
						body.SelectionGained.fire()
						expect(body.SelectionImageObject):toBe(nil)
						local height = body:GetAttribute("FacetFocusHeight")
						expect(math.abs(height - (if target == "card" then 200 else 90) / 150) < 1e-5):toBe(true)
						w.stop()
					end
					expect(function()
						local w = world(function(UI: FacetControls)
							return UI.Card({ image = "rbxassetid://1", title = "T", ringTarget = "shadow" } :: any)
						end)
						w.stop()
					end):toThrow()
				end,
			}
		)
	end)

	verifyHarness:suite("Slider contained", function()
		verifyHarness:case("contained paints a knob-thick pill rail and fill", {
			id = "native_ported_behaviours::Slider contained::contained paints a knob-thick pill rail and fill",
			run = function()
				local w = world(function(UI: FacetControls)
					return UI.VStack {
						UI.Slider "Plain" { value = Compose.cell(0.5) } :: unknown,
						UI.Slider "Contained" { value = Compose.cell(0.5), contained = true },
					}
				end)
				local plain = find(find(w.screen, "Plain"), "Rail")
				local rail = find(find(w.screen, "Contained"), "Rail")
				local fill = find(find(w.screen, "Contained"), "Fill")
				expect(plain.Size.Y.Offset):toBe(6)
				expect(rail.Size.Y.Offset):toBe(24)
				expect(fill.Size.Y.Offset):toBe(24)
				expect(find(rail, "UICorner").CornerRadius.Scale):toBe(1)
				expect(function()
					w.UI.Slider { value = Compose.cell(0.5), contained = "yes" }
				end):toThrow()
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("Skeleton corners", function()
		verifyHarness:case("control and panel read the theme radii", {
			id = "native_ported_behaviours::Skeleton corners::control and panel read the theme radii",
			run = function()
				local package = themes.neutralPackage()
				local w = world(function(UI: FacetControls)
					return UI.VStack {
						UI.Skeleton "Control" { corners = "control" :: "control" } :: unknown,
						UI.Skeleton "Panel" { corners = "panel" :: "panel" },
					}
				end, { theme = package })
				expect(find(find(w.screen, "Control"), "UICorner").CornerRadius.Offset):toBe(
					package.metrics.radii.control
				)
				expect(find(find(w.screen, "Panel"), "UICorner").CornerRadius.Offset):toBe(package.metrics.radii.panel)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("ShortcutHint label", function()
		verifyHarness:case("the label sits after the keys by default and before them with labelPosition start", {
			id = "native_ported_behaviours::ShortcutHint label::the label sits after the keys by default and before them with labelPosition start",
			run = function()
				local w = world(function(UI: FacetControls)
					return UI.VStack {
						UI.ShortcutHint "End" { keys = { { "E" } }, label = "Interact" } :: unknown,
						UI.ShortcutHint "Start" {
							keys = { { "Q" } },
							label = "Back",
							labelPosition = "start" :: "start",
						},
					}
				end)
				local function order(root: any): string
					local names = {}
					for _, child in root:GetChildren() do
						if child:IsA("GuiObject") then
							table.insert(names, { child.LayoutOrder, child.Name })
						end
					end
					table.sort(names, function(a, b)
						return a[1] < b[1]
					end)
					local out = {}
					for _, entry in names do
						table.insert(out, entry[2])
					end
					return table.concat(out, ",")
				end
				local ending, starting = find(w.screen, "End"), find(w.screen, "Start")
				expect((order(ending))):toBe("Keys,Label")
				expect((order(starting))):toBe("Label,Keys")
				expect(find(ending, "Label").Text):toBe("Interact")
				expect(find(ending, "Keys").Text):toBe("E")
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("filled icon names", function()
		verifyHarness:case("<name>.fill uses package art, else the regular icon", {
			id = "native_ported_behaviours::filled icon names::<name>.fill uses package art, else the regular icon",
			run = function()
				local package = themes.neutralPackage()
				local regular = themes.resolveIcon(package, "checkmark")
				expect(regular ~= nil):toBe(true)
				expect((themes.resolveIcon(package, "checkmark.fill"))):toBe(regular)
				package.icons = { ["checkmark.fill"] = "rbxassetid://42" } :: { [string]: ThemeTypes.IconEntry }
				expect((themes.resolveIcon(package, "checkmark.fill"))):toBe("rbxassetid://42")
				expect((themes.resolveIcon(package, "nothing.fill"))):toBe(nil)
			end,
		})
	end)

	verifyHarness:suite("NavBar surface", function()
		verifyHarness:case("surface paints a plate through the theme role tag", {
			id = "native_ported_behaviours::NavBar surface::surface paints a plate through the theme role tag",
			run = function()
				local w = world(function(UI: FacetControls)
					return UI.VStack {
						UI.NavBar "Bar" { title = "Garage", surface = "panel" :: "panel" } :: unknown,
						UI.NavBar "Bare" { title = "Garage" },
					}
				end)
				expect((find(w.screen, "Bar"):HasTag("facet-panel"))):toBe(true)
				expect((find(w.screen, "Bare"):HasTag("facet-panel"))):toBe(false)
				expect(function()
					w.UI.NavBar { title = "X", surface = "glass" }
				end):toThrow()
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("app.refusal", function()
		verifyHarness:case("answers the refusal words without mounting, and nil for an accepted spec", {
			id = "native_ported_behaviours::app.refusal::answers the refusal words without mounting, and nil for an accepted spec",
			run = function()
				local engine: any = engines.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local app = Facet.app({ runtime = runtime, types = engine.types, parent = engine.new("Folder") })
				expect((app.refusal("Button", { label = "Go", onActivate = function() end }))):toBe(nil)
				local words = app.refusal("Slider", { value = Compose.cell(0.5), contained = "yes" })
				expect(words):toBe("Facet UI.Slider: contained must be a boolean")
				expect(
					string.find(app.refusal("Button", { lable = "Go" }) or "", "Did you mean 'label'", 1, true) ~= nil
				):toBe(true)
				expect(function()
					app.refusal("Nothing", {})
				end):toThrow()
				app.dispose()
				runtime:dispose()
			end,
		})
	end)

	verifyHarness:suite("Table editable cells", function()
		verifyHarness:case("each editor proposes through onCellChange, a no-op commit proposes nothing, rows re-seed", {
			id = "native_ported_behaviours::Table editable cells::each editor proposes through onCellChange, a no-op commit proposes nothing, rows re-seed",
			run = function()
				local rows = Compose.cell({
					{ id = "a", name = "Ada", laps = 3, ready = false, tier = "gold" },
					{ id = "b", name = "Bo", laps = 5, ready = true, tier = "silver" },
				})
				local proposals = {}
				local w = world(function(UI: FacetControls)
					return UI.Table "T" {
						from = rows,
						key = "id",
						scrolls = false,
						columns = {
							{ id = "name", label = "Name", editor = "text" } :: FixtureCollectionTypes.TableColumn<any, any>,
							{ id = "laps", label = "Laps", editor = "number", min = 0, max = 99 } :: FixtureCollectionTypes.TableColumn<any, any>,
							{ id = "ready", label = "Ready", editor = "toggle" } :: FixtureCollectionTypes.TableColumn<any, any>,
							{
								id = "tier",
								label = "Tier",
								editor = "menu",
								options = { { value = "gold", label = "Gold" }, { value = "silver", label = "Silver" } },
							} :: FixtureCollectionTypes.TableColumn<any, any>,
						},
						onCellChange = function(key, column, value)
							table.insert(proposals, `{key}.{column}={tostring(value)}`)
							local nextRows = table.clone(rows:peek())
							for index, row in nextRows do
								if row.id == key then
									local copy = table.clone(row)
									copy[column] = value
									nextRows[index] = copy
								end
							end
							rows:set(nextRows)
						end,
					}
				end)
				w.step(3)
				local function editor(column: string): any
					local found
					local function walk(node: any)
						if
							found == nil
							and node.Name == "CellEditor"
							and node.Parent
							and node.Parent.Name == "Inset"
							and node.Parent.Parent.Name == column
						then
							for _, edit in require("../src/ui/activation").edits(node) do
								edit.onActivate()
							end
							found = node:FindFirstChild("Editor", true)
						end
						for _, child in node:GetChildren() do
							walk(child)
						end
					end
					walk(w.screen)
					return found
				end
				local name = editor("name")
				local box = if name:IsA("TextBox") then name else name:FindFirstChildWhichIsA("TextBox", true)
				expect(box.Text):toBe("Ada")
				box:CaptureFocus()
				box:ReleaseFocus(true)
				expect(#proposals):toBe(0)
				box:CaptureFocus()
				box.Text = "Ava"
				box:ReleaseFocus(true)
				expect(proposals[1]):toBe("a.name=Ava")
				expect(box.Text):toBe("Ava")
				local laps = editor("laps")
				local lapsBox = if laps:IsA("TextBox") then laps else laps:FindFirstChildWhichIsA("TextBox", true)
				lapsBox:CaptureFocus()
				lapsBox.Text = "120"
				lapsBox:ReleaseFocus(true)
				expect(proposals[#proposals]):toBe("a.laps=99")
				local ready = editor("ready")
				ready.Activated.fire()
				expect(proposals[#proposals]):toBe("a.ready=true")
				local tier = editor("tier")
				local trigger = find(tier, "Trigger") or tier
				expect((trigger:HasTag("facet-appearance-utility"))):toBe(true)
				expect(tier.Parent.Parent.Parent.ClipsDescendants):toBe(true)
				trigger.Activated.fire()
				w.step(10)
				local option = find(w.screen, "silver")
				expect(option ~= nil):toBe(true)
				option.Activated.fire()
				w.step(10)
				expect(proposals[#proposals]):toBe("a.tier=silver")
				rows:set({ { id = "a", name = "Zed", laps = 1, ready = false, tier = "silver" } })
				w.step()
				expect(box.Text):toBe("Zed")
				expect(function()
					w.UI.Table {
						from = rows,
						key = "id",
						columns = { { id = "x", editor = "text" } :: FixtureCollectionTypes.TableColumn<any, any> },
					}
				end):toThrow()
				expect(function()
					w.UI.Table {
						from = rows,
						key = "id",
						onCellChange = print,
						columns = { { id = "x", editor = "menu" } :: FixtureCollectionTypes.TableColumn<any, any> },
					}
				end):toThrow()
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("Table row paint", function()
		verifyHarness:case("the header band and every row carry theme tags, and alternatingRows tags the even rows", {
			id = "native_ported_behaviours::Table row paint::the header band and every row carry theme tags, and alternatingRows tags the even rows",
			run = function()
				local rows = Compose.cell({ { id = "a", n = 3 }, { id = "b", n = 1 }, { id = "c", n = 2 } })
				local sort = cells.sort(nil)
				local w = world(function(UI: FacetControls)
					return UI.VStack {
						UI.Table "Striped" {
							from = rows,
							key = "id",
							scrolls = false,
							sort = sort,
							alternatingRows = true,
							columns = {
								{ id = "id" } :: FixtureCollectionTypes.TableColumn<any, any>,
								{ id = "n" } :: FixtureCollectionTypes.TableColumn<any, any>,
							},
						} :: unknown,
						UI.Table "Plain" {
							from = rows,
							key = "id",
							scrolls = false,
							columns = { { id = "id" } :: FixtureCollectionTypes.TableColumn<any, any> },
						},
					}
				end)
				w.step(3)
				local function rowsOf(name: string): { [string]: any }
					local found = {}
					for _, node in find(w.screen, name):GetDescendants() do
						if node.Name == "DisclosingRow" then
							found[node.Parent.Parent.Name] = node
						end
					end
					return found
				end
				local header = find(find(w.screen, "Striped"), "HeaderBand")
				expect((header:HasTag("facet-tablehead"))):toBe(true)
				expect(header.BackgroundTransparency):toBe(0)
				local striped = rowsOf("Striped")
				expect((striped.a:HasTag("facet-tablerow"))):toBe(true)
				expect(striped.a.BackgroundTransparency):toBe(0)
				expect((striped.a:HasTag("facet-tablerow-alternate"))):toBe(false)
				expect((striped.b:HasTag("facet-tablerow-alternate"))):toBe(true)
				expect((striped.c:HasTag("facet-tablerow-alternate"))):toBe(false)
				sort:set({ column = "n", direction = "ascending" :: "ascending" })
				w.step(3)
				expect((striped.c:HasTag("facet-tablerow-alternate"))):toBe(true)
				expect((striped.b:HasTag("facet-tablerow-alternate"))):toBe(false)
				for _, row in rowsOf("Plain") do
					expect((row:HasTag("facet-tablerow"))):toBe(true)
					expect((row:HasTag("facet-tablerow-alternate"))):toBe(false)
				end
				local sheet = sheetFor(w, themes.neutralPackage())
				local function paint(selector: string): any
					return rule(sheet, selector):GetProperties().BackgroundColor3
				end
				expect((paint(".facet-tablehead"))):toBe(paint(".facet-control"))
				expect((paint(".facet-tablerow"))):toBe(paint(".facet-control"))
				expect(paint(".facet-tablerow-alternate") ~= paint(".facet-tablerow")):toBe(true)
				expect(paint(".facet-tablerow") ~= paint(".facet-surface")):toBe(true)
				expect((find(striped.a, "Divider"))):toBe(nil)
				expect(striped.a.Size):toBe(w.engine.types.UDim2.fromScale(1, 1))
				local corner = themes.neutralPackage().metrics.radii.control
				expect(rule(sheet, ".facet-tablerow::UICorner"):GetProperties().CornerRadius.Offset):toBe(corner)
				expect(rule(sheet, ".facet-tablehead::UICorner"):GetProperties().CornerRadius.Offset):toBe(corner)
				expect(rule(sheet, ".facet-tablerow::UIStroke"):GetProperties().Color):toBe(paint(".facet-surface"))
				expect(rule(sheet, ".facet-row-action::UIStroke"):GetProperties().Color):toBe(paint(".facet-surface"))
				local sortButton = find(find(find(w.screen, "Striped"), "Header"), "Sort")
				expect((sortButton:HasTag("facet-appearance-utility"))):toBe(false)
				expect((sortButton:HasTag("facet-button"))):toBe(true)
				local neutral = themes.neutralPackage()
				local dark = neutral.style.themes[1]
				local extra = table.clone(dark.extra :: any)
				extra.tableHeader = { r = 0.9, g = 0.1, b = 0.1 }
				extra.tableRow = { r = 0.1, g = 0.9, b = 0.1 }
				extra.tableRowAlternate = { r = 0.1, g = 0.1, b = 0.9 }
				local package = assert(themes.define({
					base = neutral,
					identity = { id = "rows", displayName = "Rows", schemaVersion = themes.SCHEMA, version = "1.0.0" },
					style = { defaultTheme = "Ink", themes = { { name = "Ink", colors = dark.colors, extra = extra } } },
				} :: any))
				local authored = sheetFor(w, package)
				expect(rule(authored, ".facet-tablehead"):GetProperties().BackgroundColor3.R):toBeCloseTo(0.9, 3)
				expect(rule(authored, ".facet-tablerow"):GetProperties().BackgroundColor3.G):toBeCloseTo(0.9, 3)
				expect(rule(authored, ".facet-tablerow-alternate"):GetProperties().BackgroundColor3.B):toBeCloseTo(
					0.9,
					3
				)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("Table edit mode", function()
		local function editableTable(input: string, editing: any?): (any, { string })
			local rows = Compose.cell({ { id = "a", ready = false } })
			local proposals = {}
			local w = world(function(UI: FacetControls)
				return UI.Table "T" {
					from = rows,
					key = "id",
					scrolls = false,
					reorderable = true,
					onReorder = function() end,
					editing = editing,
					columns = {
						{ id = "id" } :: FixtureCollectionTypes.TableColumn<any, any>,
						{ id = "ready", editor = "toggle" } :: FixtureCollectionTypes.TableColumn<any, any>,
					},
					onCellChange = function(key, column, value)
						table.insert(proposals, `{key}.{column}={tostring(value)}`)
					end,
				}
			end, { environment = { preferredInput = input } })
			w.step(3)
			return w, proposals
		end
		local function editorOf(w: any): any
			for _, node in w.screen:GetDescendants() do
				if
					node.Name == "CellEditor"
					and node.Parent
					and node.Parent.Name == "Inset"
					and node.Parent.Parent.Name == "ready"
				then
					return node:FindFirstChild("Editor")
				end
			end
			return nil
		end
		verifyHarness:case("touch and gamepad fields stay editable independently of collection Edit and Done", {
			id = "native_ported_behaviours::Table edit mode::touch and gamepad fields stay editable independently of collection Edit and Done",
			run = function()
				for _, input in { "Touch", "Gamepad" } do
					local w, proposals = editableTable(input)
					local button = find(w.screen, "Edit")
					expect(button ~= nil):toBe(true)
					expect(button.Text):toBe("Edit")
					editorOf(w).Activated.fire()
					expect(#proposals):toBe(1)
					button.Activated.fire()
					w.step()
					expect(button.Text):toBe("Done")
					editorOf(w).Activated.fire()
					expect(proposals[1]):toBe("a.ready=true")
					button.Activated.fire()
					w.step()
					expect(button.Text):toBe("Edit")
					editorOf(w).Activated.fire()
					expect(#proposals):toBe(3)
					w.stop()
				end
			end,
		})
		verifyHarness:case(
			"a pointer edits cells in place and gets no Edit toggle; a caller's editing cell owns the mode",
			{
				id = "native_ported_behaviours::Table edit mode::a pointer edits cells in place and gets no Edit toggle; a caller's editing cell owns the mode",
				run = function()
					local w, proposals = editableTable("KeyboardAndMouse")
					editorOf(w).Activated.fire()
					expect(proposals[1]):toBe("a.ready=true")
					expect((find(w.screen, "Edit"))):toBe(nil)
					w.stop()
					local owned = editableTable("Touch", Compose.cell(false))
					expect((find(owned.screen, "Edit"))):toBe(nil)
					owned.stop()
				end,
			}
		)
		verifyHarness:case("a table that neither reorders nor deletes has no Edit button and keeps its cells live", {
			id = "native_ported_behaviours::Table edit mode::a table that neither reorders nor deletes has no Edit button and keeps its cells live",
			run = function()
				local w = world(function(UI: FacetControls)
					return UI.Table "T" {
						from = { { id = "a" } },
						key = "id",
						scrolls = false,
						columns = { { id = "id" } :: FixtureCollectionTypes.TableColumn<any, any> },
					}
				end, { environment = { preferredInput = "Touch" } })
				w.step(3)
				expect((find(w.screen, "Edit"))):toBe(nil)
				expect(function()
					w.UI.Table {
						from = { { id = "a" } },
						key = "id",
						editable = true,
						header = false,
						columns = { { id = "id" } :: FixtureCollectionTypes.TableColumn<any, any> },
					}
				end):toThrow()
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("environment preview", function()
		verifyHarness:case(
			"the environment option overrides the observed engine facts for controls and UI.environment",
			{
				id = "native_ported_behaviours::environment preview::the environment option overrides the observed engine facts for controls and UI.environment",
				run = function()
					local engine: any = engines.new()
					local input = engine.new("UserInputService")
					local gui = engine.new("GuiService")
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local forced = cells.optionalString("Touch")
					local size = Compose.cell(engine.types.Vector2.new(390, 844))
					local UI: any = Facet.controls(
						runtime,
						{
							types = engine.types,
							services = { GuiService = gui, UserInputService = input },
							environment = {
								preferredInput = forced,
								touchEnabled = true,
								viewportSize = size,
								preferredTextSize = "Largest",
								displaySize = "Large",
							},
						} :: any
					)
					local seen: any
					local stop = runtime.mount(function()
						seen = UI.environment()
						return ((runtime.constructors.Folder :: unknown) :: FolderConstructor)({})
					end, engine.new("Folder"))
					expect(seen.interactionClasses:peek().primary):toBe("touch")
					expect((seen.sizeClass:peek())):toBe("compact")
					expect((seen.preferredTextSize:peek())):toBe("Largest")
					expect((seen.displaySize:peek())):toBe("Large")
					forced:set("Gamepad")
					expect(seen.interactionClasses:peek().primary):toBe("gamepad")
					forced:set(nil)
					expect(seen.interactionClasses:peek().primary):toBe("touch")
					size:set(engine.types.Vector2.new(1920, 1080))
					expect((seen.sizeClass:peek())):toBe("wide")
					stop()
					expect(function()
						Facet.controls(runtime, { types = engine.types, environment = { inputKind = "Touch" } } :: any)
					end):toThrow()
					runtime:dispose()
				end,
			}
		)
	end)

	verifyHarness:suite("lab-found defects", function()
		verifyHarness:case("a Divider leaves its transparency to the facet-divider rule", {
			id = "native_ported_behaviours::lab-found defects::a Divider leaves its transparency to the facet-divider rule",
			run = function()
				local w = world(function(UI: FacetControls)
					return UI.VStack { UI.Divider "Line" {} }
				end)
				local line = find(w.screen, "Line")
				expect((line:HasTag("facet-divider"))):toBe(true)
				expect(line.BackgroundTransparency):toBe(0)
				local sheet = sheetFor(w, themes.neutralPackage())
				expect(rule(sheet, ".facet-divider"):GetProperties().BackgroundTransparency < 1):toBe(true)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("collection status seed", function()
		verifyHarness:case("a status cell that starts empty is filled with the empty status record", {
			id = "native_ported_behaviours::collection status seed::a status cell that starts empty is filled with the empty status record",
			run = function()
				for _, kind in { "VirtualList", "Table" } :: { "Table" | "VirtualList" } do
					local status = cells.emptyCollectionStatus()
					local w = world(function(UI: FacetControls, Host: RobloxHost)
						if kind == "Table" then
							return UI.Table {
								from = { { id = "a" } },
								key = "id",
								columns = { { id = "id" } :: FixtureCollectionTypes.TableColumn<any, any> },
								status = status,
							}
						end
						return UI.VirtualList {
							from = { { id = "a" } },
							key = "id",
							status = status,
							render = function(): GuiObject
								return Host.Frame {}
							end,
						}
					end)
					w.step(2)
					expect(type(status:peek()) == "table" and type(assert(status:peek()).total) == "number"):toBe(true)
					w.stop()
				end
			end,
		})
	end)

	verifyHarness:suite("bounded text buttons", function()
		verifyHarness:case(
			"a text Button or Toggle with an authored width wraps inside it; any text button truncates at its box",
			{
				id = "native_ported_behaviours::bounded text buttons::a text Button or Toggle with an authored width wraps inside it; any text button truncates at its box",
				run = function()
					local w = world(function(UI: FacetControls, Host: RobloxHost, engine)
						local engineEnum = engine.types.Enum
						local w0Enum = engineEnum.AutomaticSize
						return Host.Frame {
							Size = UDim2.fromOffset(180, 400),
							UI.Toggle "Long" {
								value = Compose.cell(false),
								label = "Allow friends to join my race from the lobby",
								Size = UDim2.fromScale(1, 0),
							} :: unknown,
							UI.Button "Cell" {
								label = "A very long button label",
								Size = UDim2.fromOffset(80, 44),
								AutomaticSize = w0Enum.None,
							},
							UI.Button "Hug" { label = "Go" },
						}
					end)
					local long, cell, hug = find(w.screen, "Long"), find(w.screen, "Cell"), find(w.screen, "Hug")
					expect(long.TextWrapped):toBe(true)
					expect(long.AutomaticSize.Name):toBe("Y")
					expect(cell.TextTruncate.Name):toBe("AtEnd")
					expect(cell.AutomaticSize.Name):toBe("None")
					expect(hug.AutomaticSize.Name):toBe("XY")
					w.stop()
				end,
			}
		)

		verifyHarness:case("a text button whose width follows its label never truncates it", {
			id = "native_ported_behaviours::bounded text buttons::a text button whose width follows its label never truncates it",
			run = function()
				local w = world(function(UI: FacetControls)
					return UI.VStack {
						UI.Button "Hug" { label = "Go" } :: unknown,
						UI.Toggle "Wide" { value = Compose.cell(false), label = "Label", Size = UDim2.fromScale(1, 0) },
						UI.Picker "Segments" {
							style = "segmented" :: "segmented",
							label = "Mode",
							selected = Compose.cell("a"),
							options = {
								{ value = "a", label = string.rep("long ", 16) } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "B" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						},
					}
				end)
				expect(find(w.screen, "Hug").TextTruncate.Name):toBe("None")
				expect(find(w.screen, "Wide").TextTruncate.Name):toBe("AtEnd")
				local segment = find(find(w.screen, "Segments"), "a")
				expect(segment.AutomaticSize.Name):toBe("X")
				expect(segment.TextTruncate.Name):toBe("None")
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("outline disclosure header", function()
		verifyHarness:case("an outline DisclosureGroup header leads with its chevron and label", {
			id = "native_ported_behaviours::outline disclosure header::an outline DisclosureGroup header leads with its chevron and label",
			run = function()
				local w = world(function(UI: FacetControls)
					return UI.DisclosureGroup "Tree" {
						label = "Components",
						appearance = "outline" :: "outline",
						expanded = Compose.cell(false),
						content = function(): Instance
							return UI.Text { text = "Body" }
						end,
					}
				end)
				local header = find(w.screen, "Header")
				local layout = find(header, "Content"):FindFirstChildWhichIsA("UIListLayout")
				expect(layout.HorizontalAlignment.Name):toBe("Left")
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("StepIndicator room", function()
		verifyHarness:case("the underline sits below the copy, and a long description counts toward the fit", {
			id = "native_ported_behaviours::StepIndicator room::the underline sits below the copy, and a long description counts toward the fit",
			run = function()
				local w = world(function(UI: FacetControls)
					return UI.StepIndicator "Steps" {
						steps = {
							{ id = "a", label = "Cart" },
							{ id = "b", label = "Ship", description = "Address and speed of delivery for the order" },
						},
						current = "a",
						sizing = "fill" :: "fill",
					}
				end)
				local root = find(w.screen, "Steps")
				local row = find(root, "Row")
				expect(row:FindFirstChildWhichIsA("UIPadding").PaddingBottom.Offset >= 2):toBe(true)
				root.AbsoluteSize = Vector2.new(300, 80)
				w.step()
				expect((root:GetAttribute("FacetForm"))):toBe("summary")
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("plate-less appearances in skinned themes", function()
		verifyHarness:case("utility and link Buttons take no control skin; a standard Button does", {
			id = "native_ported_behaviours::plate-less appearances in skinned themes::utility and link Buttons take no control skin; a standard Button does",
			run = function()
				local package = themes.neutralPackage()
				package.assets = package.assets or {}
				assert(package.assets).controlArt = { content = "rbxassetid://123" }
				assert(package.chrome).control = { kind = "nineSlice" :: "nineSlice", asset = "controlArt" }
				local appearance = Compose.cell("utility")
				local w = world(function(UI: FacetControls)
					return UI.VStack {
						UI.Button "Plated" { label = "Go" } :: unknown,
						UI.Button "Utility" { label = "Row", appearance = "utility" },
						UI.Button "Link" { label = "More", appearance = "link" },
						UI.Button "Live" { label = "Live", appearance = appearance },
					}
				end, { theme = package })
				expect(find(w.screen, "Plated"):FindFirstChild("SkinBoundary") ~= nil):toBe(true)
				expect((find(w.screen, "Utility"):FindFirstChild("SkinBoundary"))):toBeNil()
				expect((find(w.screen, "Link"):FindFirstChild("SkinBoundary"))):toBeNil()
				expect((find(w.screen, "Live"):FindFirstChild("SkinBoundary"))):toBeNil()
				appearance:set("standard")
				expect(find(w.screen, "Live"):FindFirstChild("SkinBoundary") ~= nil):toBe(true)
				appearance:set("link")
				expect((find(w.screen, "Live"):FindFirstChild("SkinBoundary"))):toBeNil()
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("the focus ring", function()
		verifyHarness:case(
			"an app gives its PlayerGui one theme ring for engine selection, shown only for keys and pads",
			{
				id = "native_ported_behaviours::the focus ring::an app gives its PlayerGui one theme ring for engine selection, shown only for keys and pads",
				run = function()
					local engine: any = engines.new()
					local E = engine.types.Enum
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local input = engine.new("UserInputService")
					input.GetFocusedTextBox = function()
						return nil
					end
					local gui = engine.new("GuiService")
					local playerGui = engine.new("PlayerGui")
					local app = Facet.app({
						runtime = runtime,
						types = engine.types,
						parent = playerGui,
						services = { UserInputService = input, GuiService = gui },
					})
					local stop = app.mount(function()
						return app.UI.Button { label = "Go" }
					end)
					local ring = playerGui.SelectionImageObject
					expect(ring ~= nil):toBe(true)
					expect(ring.Parent):toBeNil()
					local stroke = ring:FindFirstChildWhichIsA("UIStroke")
					expect(stroke.BorderStrokePosition):toBe(E.BorderStrokePosition.Inner)
					expect(ring:FindFirstChildWhichIsA("UICorner") ~= nil):toBe(true)
					input.LastInputTypeChanged.fire(E.UserInputType.MouseButton1)
					expect(stroke.Transparency):toBe(1)
					input.LastInputTypeChanged.fire(E.UserInputType.Keyboard)
					expect(stroke.Transparency):toBe(0)
					input.LastInputTypeChanged.fire(E.UserInputType.Touch)
					expect(stroke.Transparency):toBe(1)
					input.LastInputTypeChanged.fire(E.UserInputType.Gamepad1)
					expect(stroke.Transparency):toBe(0)
					stop()
					expect(playerGui.SelectionImageObject):toBeNil()
					app.dispose()
					runtime:dispose()
				end,
			}
		)
	end)

	verifyHarness:suite("skins on laid-out plates", function()
		verifyHarness:case("a skinned plate that lays out its children keeps its art out of the list", {
			id = "native_ported_behaviours::skins on laid-out plates::a skinned plate that lays out its children keeps its art out of the list",
			run = function()
				local package = themes.neutralPackage()
				package.assets = package.assets or {}
				assert(package.assets).fieldArt = { content = "rbxassetid://123" }
				assert(package.chrome).field = { kind = "nineSlice" :: "nineSlice", asset = "fieldArt" }
				local w = world(function(UI: FacetControls)
					return UI.TextInput "Search" { value = Compose.cell(""), placeholder = "Search", label = "Find" }
				end, { theme = package })
				local plate = find(w.screen, "Input")
				expect(plate:FindFirstChildWhichIsA("UIListLayout") ~= nil):toBe(true)
				local boundary = find(plate, "SkinBoundary")
				expect(boundary ~= nil):toBe(true)
				expect(boundary.Parent.ClassName):toBe("Folder")
				expect(boundary.Parent.Parent):toBe(plate)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("toggle art", function()
		verifyHarness:case("the switch track and knob art paint a switch, never a checkbox box", {
			id = "native_ported_behaviours::toggle art::the switch track and knob art paint a switch, never a checkbox box",
			run = function()
				local package = themes.neutralPackage()
				package.assets = package.assets or {}
				assert(package.assets).trackArt = { content = "rbxassetid://123" }
				assert(package.assets).knobArt = { content = "rbxassetid://124" }
				assert(package.chrome).toggleTrack = { kind = "nineSlice" :: "nineSlice", asset = "trackArt" }
				assert(package.chrome).toggleKnob = { kind = "nineSlice" :: "nineSlice", asset = "knobArt" }
				local w = world(function(UI: FacetControls)
					return UI.VStack {
						UI.Toggle "Switch" { value = Compose.cell(true), label = "On" } :: unknown,
						UI.Toggle "Box" {
							value = Compose.cell(true),
							label = "Box",
							presentation = "checkbox" :: "checkbox",
							controlSize = "compact" :: "compact",
						},
					}
				end, { theme = package })
				expect((find(find(w.screen, "Switch"), "Indicator"):HasTag("facet-skinned"))):toBe(true)
				local box = find(find(w.screen, "Box"), "Indicator")
				expect((box:HasTag("facet-skinned"))):toBe(false)
				expect((find(box, "SkinBoundary"))):toBeNil()
				w.stop()
			end,
		})
	end)
end
