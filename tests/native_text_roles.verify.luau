--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Bdd = require("../tools/vendor/verify/src/bdd")
local VerifyRoblox = require("../tools/vendor/verify/src/roblox")

return function(verifyHarness: Verify.Harness)
	local test = Bdd.create(verifyHarness)
	local describe, it, expect = test.describe, test.it, test.expect
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local FixtureCollectionProps = require("../src/ui/collection_props")
	local FixtureComposeTypes = require("../src/vendor/compose/core")
	local Facet = require("../src")
	local engines = require("./lib/native_engine")
	local types = engines.types
	local E, D2 = types.Enum, types.UDim2

	type World = {
		screen: Instance,
		styled: (Instance, string) -> unknown,
		find: (string) -> Instance,
		stop: () -> (),
	}

	local LONG = "Midnight harbor racing league finals with friends"

	local function world(build: (Facet.Controls, RobloxHost) -> { Facet.Child }): World
		local roots: { VerifyRoblox.Instance } = {}
		local engine, bridge = engines.new({
			layout = {
				roots = function()
					return roots
				end,
				viewport = function()
					return { X = 800, Y = 600 }
				end,
			},
		})
		local runtime = Facet.Roblox.createRuntime(engine)
		local gui, input = engine.new("GuiService"), engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		input.IsKeyDown = function()
			return false
		end
		local UI = Facet.controls(runtime, {
			types = engine.types,
			services = { GuiService = gui, UserInputService = input },
			motionLevel = "none",
		})
		local Host: RobloxHost = Facet.host(runtime)
		local parent = engine.new("Folder")
		local stop, mounted = runtime.mount(function()
			local sheet =
				Facet.themes.createStyleSheet(runtime, Facet.themes.neutralPackage(), { types = engine.types })
			return Host.ScreenGui {
				Name = "Screen",
				sheet,
				Host.StyleLink { StyleSheet = Facet.Compose.static(sheet) },
				table.unpack(build(UI, Host)),
			}
		end, parent)
		local screen = (mounted :: unknown) :: Instance
		table.insert(roots, (screen :: unknown) :: VerifyRoblox.Instance)
		local layout = assert(bridge.layout)
		layout.step()
		for _, node in screen:GetDescendants() do
			if node:IsA("ScrollingFrame") then
				engine.environment.poke(
					(node :: unknown) :: VerifyRoblox.Instance,
					"AbsoluteWindowSize",
					node.AbsoluteSize
				)
			end
		end
		for _ = 1, 4 do
			layout.step()
		end
		local ui = assert(bridge.ui)
		return {
			screen = screen,
			styled = function(node: Instance, property: string): unknown
				return ui.styled((node :: unknown) :: VerifyRoblox.Instance, property)
			end,
			find = function(name: string): Instance
				return assert(screen:FindFirstChild(name, true), name)
			end,
			stop = function()
				stop()
				runtime:dispose()
				parent:Destroy()
			end,
		}
	end

	local function roles(node: Instance): { string }
		local found: { string } = {}
		for _, tag in node:GetTags() do
			if string.sub(tag, 1, 11) == "facet-type-" then
				table.insert(found, string.sub(tag, 12))
			end
		end
		return found
	end

	local function grid(
		UI: Facet.Controls,
		Host: RobloxHost,
		overflow: ("visible" | "clip" | "grow")?,
		render: (number) -> GuiObject
	): Frame
		local spec: FixtureCollectionProps.KeyedCollectionSpec<number, number> = {
			from = { 1, 2, 3, 4 },
			key = function(value: number): number
				return value
			end,
			columns = 2,
			itemSize = 120,
			mode = "all",
			contentOverflow = overflow,
			render = function(current: FixtureComposeTypes.ReadOnlyValue<number>): GuiObject
				return render(current:peek())
			end,
		}
		return Host.Frame "Page" {
			Size = D2.fromOffset(320, 600),
			BackgroundTransparency = 1,
			UI.VirtualGrid(spec),
		}
	end

	describe("text size roles", function()
		it("keeps a pixel text size that equals the engine default", {
			id = "native_text_roles::text size roles::keeps a pixel text size that equals the engine default",
			run = function()
				local w = world(function(UI: Facet.Controls): { Facet.Child }
					return { UI.Text "Small" { text = "Owned", textSize = 14 } }
				end)
				local label = w.find("Small")
				expect(#roles(label)):toBe(0)
				expect(w.styled(label, "TextSize")):toBe(14)
				w.stop()
			end,
		})

		it("draws a Badge label at the caption role size in the content colour", {
			id = "native_text_roles::text size roles::draws a Badge label at the caption role size in the content colour",
			run = function()
				local w = world(function(UI: Facet.Controls): { Facet.Child }
					return { UI.Badge "Badge" { label = "New" }, UI.Text "Plain" { text = "Plain" } }
				end)
				local badge = w.find("Badge")
				expect(roles(badge)):toEqual({ "caption" })
				expect(w.styled(badge, "TextSize")):toBe(14)
				expect(w.styled(badge, "TextColor3")):toBe(w.styled(w.find("Plain"), "TextColor3"))
				w.stop()
			end,
		})

		it("gives every Facet text node one type role", {
			id = "native_text_roles::text size roles::gives every Facet text node one type role",
			run = function()
				local w = world(function(UI: Facet.Controls): { Facet.Child }
					return {
						UI.Badge "Badge" { label = "New" },
						UI.Chip "Chip" { label = "Fast", onRemove = function() end },
						UI.Card "Card" { title = "Course", caption = "Friends playing" },
						UI.Text "Hint" { text = "Hint", textRole = "caption" },
					}
				end)
				for _, node in w.screen:GetDescendants() do
					if node:HasTag("facet-text") then
						expect(`{node:GetFullName()} {#roles(node)}`):toBe(`{node:GetFullName()} 1`)
					end
				end
				expect(roles(w.find("Hint"))):toEqual({ "caption" })
				w.stop()
			end,
		})
	end)

	describe("text and row widths", function()
		it("fills the width of a sized parent and grows only in height", {
			id = "native_text_roles::text and row widths::fills the width of a sized parent and grows only in height",
			run = function()
				local w = world(function(UI: Facet.Controls, Host: RobloxHost): { Facet.Child }
					return {
						Host.Frame "Cell" {
							Size = D2.fromOffset(120, 40),
							BackgroundTransparency = 1,
							UI.Text "Title" { text = LONG },
						},
					}
				end)
				local label = w.find("Title") :: TextLabel
				expect(label.AutomaticSize):toBe(E.AutomaticSize.Y)
				expect(label.Size):toBe(D2.fromScale(1, 0))
				expect(label.AbsoluteSize.X):toBe(120)
				w.stop()
			end,
		})

		it("hugs its text inside a hugging stack", {
			id = "native_text_roles::text and row widths::hugs its text inside a hugging stack",
			run = function()
				local w = world(function(UI: Facet.Controls): { Facet.Child }
					return { UI.HStack { UI.Text "Name" { text = "Name" }, UI.Text "Value" { text = "Value" } } }
				end)
				local name, value = w.find("Name") :: TextLabel, w.find("Value") :: TextLabel
				expect(name.AutomaticSize):toBe(E.AutomaticSize.XY)
				expect(value.AbsolutePosition.X > name.AbsolutePosition.X):toBe(true)
				expect(value.AbsolutePosition.X < 200):toBe(true)
				w.stop()
			end,
		})

		it("keeps a collection row at its cell width and lets it grow only in height", {
			id = "native_text_roles::text and row widths::keeps a collection row at its cell width and lets it grow only in height",
			run = function()
				local w = world(function(UI: Facet.Controls, Host: RobloxHost): { Facet.Child }
					return {
						grid(UI, Host, nil, function(index: number): GuiObject
							return UI.Text(`Item{index}`) { text = LONG }
						end),
					}
				end)
				local item = w.find("Item1") :: TextLabel
				local content = assert(item:FindFirstAncestor("Content")) :: CanvasGroup
				expect(content.AutomaticSize):toBe(E.AutomaticSize.Y)
				expect(item.AbsoluteSize.X > 0):toBe(true)
				expect(item.AbsoluteSize.X <= 160):toBe(true)
				expect(content.AbsoluteSize.X <= 160):toBe(true)
				w.stop()
			end,
		})

		it("grows a collection row on both axes only when its spec opts in", {
			id = "native_text_roles::text and row widths::grows a collection row on both axes only when its spec opts in",
			run = function()
				local w = world(function(UI: Facet.Controls, Host: RobloxHost): { Facet.Child }
					return {
						grid(UI, Host, "grow", function(index: number): GuiObject
							return UI.Text(`Item{index}`) { text = "Short", AutomaticSize = E.AutomaticSize.XY }
						end),
					}
				end)
				local content = assert(w.find("Item1"):FindFirstAncestor("Content")) :: CanvasGroup
				expect(content.AutomaticSize):toBe(E.AutomaticSize.XY)
				w.stop()
			end,
		})

		it("keeps a long Card title in a narrow cell to two lines", {
			id = "native_text_roles::text and row widths::keeps a long Card title in a narrow cell to two lines",
			run = function()
				local w = world(function(UI: Facet.Controls, Host: RobloxHost): { Facet.Child }
					return {
						grid(UI, Host, nil, function(index: number): GuiObject
							return UI.Card(`Card{index}`) {
								title = if index == 1 then "Course" else `{LONG} {LONG} {LONG}`,
							}
						end),
					}
				end)
				local short = w.find("Card1"):FindFirstChild("Title", true) :: TextLabel
				local long = w.find("Card2"):FindFirstChild("Title", true) :: TextLabel
				expect(short.AbsoluteSize.Y > 0):toBe(true)
				expect(long.AbsoluteSize.X > 0):toBe(true)
				expect(long.AbsoluteSize.X <= 160):toBe(true)
				expect(long.AbsoluteSize.Y > short.AbsoluteSize.Y):toBe(true)
				expect(long.AbsoluteSize.Y <= 2 * short.AbsoluteSize.Y):toBe(true)
				expect(long.TextTruncate):toBe(E.TextTruncate.AtEnd)
				w.stop()
			end,
		})
	end)
end
