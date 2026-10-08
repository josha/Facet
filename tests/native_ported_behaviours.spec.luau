--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type ScreenGuiConstructor = typeof(require("@repo/tools/typecheck/aliases").ScreenGuiConstructor)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local cells = require("./lib/cells")
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
					engine.heartbeat:Fire(1 / 60)
				end
			end,
			stop = function()
				stop()
				runtime:dispose()
			end,
		}
	end

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
						body.SelectionGained:Fire()
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
				expect(editor("name")):toBe(name)
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
				ready.Activated:Fire()
				expect(proposals[#proposals]):toBe("a.ready=true")
				local tier = editor("tier")
				local trigger = find(tier, "Trigger") or tier
				expect((trigger:HasTag("facet-appearance-utility"))):toBe(true)
				expect(tier.Parent.Parent.Parent.ClipsDescendants):toBe(true)
				trigger.Activated:Fire()
				w.step(10)
				local option = find(w.screen, "silver")
				expect(option ~= nil):toBe(true)
				option.Activated:Fire()
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
					editorOf(w).Activated:Fire()
					expect(#proposals):toBe(1)
					button.Activated:Fire()
					w.step()
					expect(button.Text):toBe("Done")
					editorOf(w).Activated:Fire()
					expect(proposals[1]):toBe("a.ready=true")
					button.Activated:Fire()
					w.step()
					expect(button.Text):toBe("Edit")
					editorOf(w).Activated:Fire()
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
					editorOf(w).Activated:Fire()
					expect(proposals[1]):toBe("a.ready=true")
					expect((find(w.screen, "Edit"))):toBe(nil)
					w.stop()
					local owned = editableTable("Touch", Compose.cell(false))
					expect((find(owned.screen, "Edit"))):toBe(nil)
					owned.stop()
				end,
			}
		)
	end)

	verifyHarness:suite("bounded text buttons", function()
		verifyHarness:case(
			"a long Button label wraps in a supplied phone cell width and keeps its natural width without one",
			{
				id = "native_ported_behaviours::bounded text buttons::a long Button label wraps in a supplied phone cell width and keeps its natural width without one",
				run = function()
					local w = world(function(UI: FacetControls, Host: RobloxHost)
						local label = "Allow friends to join my race from the lobby and choose their next race"
						return Host.Frame {
							Size = UDim2.fromOffset(180, 400),
							UI.Button "BoundedLong" { label = label, Size = UDim2.fromScale(1, 0) },
							UI.Button "NaturalLong" { label = label },
						}
					end)
					local bounded, natural = find(w.screen, "BoundedLong"), find(w.screen, "NaturalLong")
					expect(bounded.Size.X.Scale):toBe(1)
					expect(bounded.AutomaticSize.Name):toBe("Y")
					expect(bounded.TextWrapped):toBe(true)
					expect(natural.AutomaticSize.Name):toBe("XY")
					expect(natural.TextTruncate.Name):toBe("None")
					w.stop()
				end,
			}
		)
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
					input.LastInputTypeChanged:Fire(E.UserInputType.MouseButton1)
					expect(stroke.Transparency):toBe(1)
					input.LastInputTypeChanged:Fire(E.UserInputType.Keyboard)
					expect(stroke.Transparency):toBe(0)
					input.LastInputTypeChanged:Fire(E.UserInputType.Touch)
					expect(stroke.Transparency):toBe(1)
					input.LastInputTypeChanged:Fire(E.UserInputType.Gamepad1)
					expect(stroke.Transparency):toBe(0)
					stop()
					expect(playerGui.SelectionImageObject):toBeNil()
					app.dispose()
					runtime:dispose()
				end,
			}
		)
	end)
end
