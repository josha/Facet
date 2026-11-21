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
	local textDirection = require("../src/ui/text_direction")
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
				expect(w.styled(badge, "TextSize")):toBe(16)
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
				local clamp = long:FindFirstChild("LineClamp") :: UISizeConstraint?
				expect(clamp ~= nil and short:FindFirstChild("LineClamp") ~= nil):toBe(true)
				local s, l = short.AbsoluteSize, long.AbsoluteSize
				local bound = if clamp then clamp.MaxSize.Y else 0
				local fits = s.Y > 0 and l.X > 0 and l.X <= 160 and l.Y <= math.max(bound, s.Y) and bound < 4 * s.Y
				expect(if fits then "fits" else `short {s.X}x{s.Y}, long {l.X}x{l.Y}, clamp {bound}`):toBe("fits")
				expect(long.TextWrapped):toBe(true)
				expect(long.TextTruncate):toBe(E.TextTruncate.AtEnd)
				w.stop()
			end,
		})
	end)

	describe("text alignment and direction", function()
		local function alignments(build: (Facet.Controls) -> { Facet.Child }): { [string]: string }
			local w = world(function(UI: Facet.Controls): { Facet.Child }
				return build(UI)
			end)
			local found: { [string]: string } = {}
			for _, node in w.screen:GetDescendants() do
				if node:IsA("TextLabel") then
					found[node.Name] = node.TextXAlignment.Name
				end
			end
			w.stop()
			return found
		end

		it("maps start, center and end to the edges of left-to-right text", {
			id = "native_text_roles::text alignment and direction::maps start, center and end to the edges of left-to-right text",
			run = function()
				local found = alignments(function(UI: Facet.Controls): { Facet.Child }
					return {
						UI.Text "Start" { text = "Ready", textAlign = "start" },
						UI.Text "Center" { text = "Ready", textAlign = "center" },
						UI.Text "End" { text = "Ready", textAlign = "end" },
					}
				end)
				expect(found):toEqual({ Start = "Left", Center = "Center", End = "Right" })
			end,
		})

		it("puts start at the right edge when direction is rtl", {
			id = "native_text_roles::text alignment and direction::puts start at the right edge when direction is rtl",
			run = function()
				local found = alignments(function(UI: Facet.Controls): { Facet.Child }
					return {
						UI.Text "RtlStart" { text = "Ready", textAlign = "start", direction = "rtl" },
						UI.Text "RtlEnd" { text = "Ready", textAlign = "end", direction = "rtl" },
						UI.Text "RtlCenter" { text = "Ready", textAlign = "center", direction = "rtl" },
					}
				end)
				expect(found):toEqual({ RtlStart = "Right", RtlEnd = "Left", RtlCenter = "Center" })
			end,
		})

		it("aligns a right-to-left string to its start when direction is auto", {
			id = "native_text_roles::text alignment and direction::aligns a right-to-left string to its start when direction is auto",
			run = function()
				local copy = Facet.Compose.cell("Ready")
				local w = world(function(UI: Facet.Controls): { Facet.Child }
					return {
						UI.Text "Auto" { text = copy, textAlign = "start", direction = "auto" },
						UI.Text "Unset" { text = copy, textAlign = "start" },
						UI.Text "Pinned" { text = copy, textAlign = "start", direction = "ltr" },
					}
				end)
				copy:set("\u{05E9}\u{05DC}\u{05D5}\u{05DD}")
				local found: { [string]: string } = {}
				for _, name in { "Auto", "Unset", "Pinned" } do
					found[name] = (w.find(name) :: TextLabel).TextXAlignment.Name
				end
				w.stop()
				expect(found):toEqual({ Auto = "Right", Unset = "Right", Pinned = "Left" })
			end,
		})

		it("resolves the base direction from the first strong character", {
			id = "native_text_roles::text alignment and direction::resolves the base direction from the first strong character",
			run = function()
				local base = textDirection.base
				local hebrew = "\u{05E9}\u{05DC}\u{05D5}\u{05DD}"
				local arabic = "\u{0645}\u{0631}\u{062D}\u{0628}\u{0627}"
				expect({
					hebrew = base(`{hebrew} Rally`, false),
					arabic = base(arabic, false),
					latin = base(`Rally {hebrew}`, false),
					accented = base(`\u{00C9}t\u{00E9} {hebrew}`, false),
					digits = base(`12 - {hebrew}`, false),
					arabicDigits = base(`\u{0661}\u{0662} Rally`, false),
					neutral = base("12 - 34", false),
					empty = base("", false),
					emoji = base(`\u{1F3C1} {hebrew}`, false),
					markup = base(`<b>{hebrew}</b>`, true),
					literal = base(`<b>{hebrew}</b>`, false),
					entity = base(`&amp; {hebrew}`, true),
					isolated = base(`\u{2066}Rally\u{2069} {hebrew}`, false),
					unclosed = base(`\u{2067}{hebrew}`, false),
					rightMark = base("\u{200F}Rally", false),
					leftMark = base(`\u{200E}{hebrew}`, false),
					broken = base("\xFF\xFE", false),
					brokenLate = base(`{hebrew}\xFF`, false),
					ordinal = base(`\u{00AA}{hebrew}`, false),
					combining = base("\u{05B0}Rally", false),
					arabicComma = base("\u{060C}Rally", false),
					roman = base(`\u{2163} {hebrew}`, false),
					braille = base(`\u{2801} {hebrew}`, false),
					iteration = base(`\u{3005}{hebrew}`, false),
					fullwidthBracket = base(`\u{FF3B}{hebrew}`, false),
					numericEntity = base("&#1513;&#x05DC; Rally", true),
				}):toEqual({
					hebrew = "rtl",
					arabic = "rtl",
					latin = "ltr",
					accented = "ltr",
					digits = "rtl",
					arabicDigits = "ltr",
					neutral = "ltr",
					empty = "ltr",
					emoji = "rtl",
					markup = "rtl",
					literal = "ltr",
					entity = "rtl",
					isolated = "rtl",
					unclosed = "ltr",
					rightMark = "rtl",
					leftMark = "ltr",
					broken = "ltr",
					brokenLate = "rtl",
					ordinal = "ltr",
					combining = "ltr",
					arabicComma = "ltr",
					roman = "ltr",
					braille = "ltr",
					iteration = "ltr",
					fullwidthBracket = "rtl",
					numericEntity = "rtl",
				})
			end,
		})

		it("follows bound text and a bound alignment", {
			id = "native_text_roles::text alignment and direction::follows bound text and a bound alignment",
			run = function()
				local copy = Facet.Compose.cell("Ready")
				local align = Facet.Compose.cell("start" :: "start" | "center" | "end")
				local w = world(function(UI: Facet.Controls): { Facet.Child }
					return { UI.Text "Bound" { text = copy, textAlign = align } }
				end)
				local label = w.find("Bound") :: TextLabel
				expect(label.TextXAlignment):toBe(E.TextXAlignment.Left)
				copy:set("\u{05E9}\u{05DC}\u{05D5}\u{05DD}")
				expect(label.TextXAlignment):toBe(E.TextXAlignment.Right)
				align:set("end")
				expect(label.TextXAlignment):toBe(E.TextXAlignment.Left)
				w.stop()
			end,
		})

		it("follows text given as a function", {
			id = "native_text_roles::text alignment and direction::follows text given as a function",
			run = function()
				local copy = Facet.Compose.cell("Ready")
				local reads = 0
				local w = world(function(UI: Facet.Controls): { Facet.Child }
					return {
						UI.Text "Counted" {
							text = function(use: Facet.Use): string
								reads += 1
								return use(copy)
							end,
							textAlign = "start",
						},
					}
				end)
				local label = w.find("Counted") :: TextLabel
				local start = label.TextXAlignment.Name
				copy:set("\u{05E9}\u{05DC}\u{05D5}\u{05DD}")
				expect(`{start} {label.TextXAlignment.Name} {reads > 0}`):toBe("Left Right true")
				w.stop()
			end,
		})

		it("refuses the native alignment and direction and names the Facet options", {
			id = "native_text_roles::text alignment and direction::refuses the native alignment and direction and names the Facet options",
			run = function()
				local alignOk, alignProblem = pcall(world, function(UI: Facet.Controls): { Facet.Child }
					return { UI.Text "Native" { text = "Ready", TextXAlignment = E.TextXAlignment.Center } }
				end)
				local flowOk, flowProblem = pcall(world, function(UI: Facet.Controls): { Facet.Child }
					return { UI.Text "Native" { text = "Ready", TextDirection = E.TextDirection.RightToLeft } }
				end)
				expect(alignOk):toBe(false)
				expect(string.find(tostring(alignProblem), "set the alignment with textAlign", 1, true) ~= nil):toBe(
					true
				)
				expect(flowOk):toBe(false)
				expect(string.find(tostring(flowProblem), "set the direction with direction", 1, true) ~= nil):toBe(
					true
				)
			end,
		})
	end)
end
