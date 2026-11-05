--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local Facet = require("../src")
	local VerifyRoblox = require("../tools/vendor/verify/src/roblox")
	local ThemeTypes = require("../src/ui/theme_types")
	local context = require("../src/ui/context")
	local engineLib = require("./lib/native_engine")
	local worlds = require("./lib/content_world")
	local styleRules = require("./lib/style_rules")
	local Compose = require("../src/vendor/compose/core")
	local themes = Facet.themes
	local expect = Verify.expect

	local COIN: ThemeTypes.IconGlyph = { font = { family = "rbxassetid://9001" }, codepoint = 0xE001 }
	local STAR: ThemeTypes.IconGlyph = { font = { family = "rbxassetid://9001" }, codepoint = 0xE002 }
	local LIT: ThemeTypes.IconGlyph = { font = { family = "rbxassetid://9001" }, codepoint = 0xE003 }
	local STATES: ThemeTypes.IconEntry = { default = STAR, hover = LIT, selected = "rbxassetid://5" }
	local ICONS: { [string]: ThemeTypes.IconEntry } = {
		["game:coin"] = COIN,
		["game:star"] = STATES,
	}

	local function glyphOf(icon: Instance): TextLabel
		local glyph = icon:FindFirstChild("Glyph")
		assert(glyph and glyph:IsA("TextLabel"), `{icon.Name} draws no glyph`)
		return glyph
	end

	verifyHarness:suite("font glyph icons", function()
		verifyHarness:case("resolves a glyph entry and its state variants through the icon registry", {
			id = "native_glyph_icons::font glyph icons::resolves a glyph entry and its state variants through the icon registry",
			run = function()
				local registry: ThemeTypes.IconRegistry = { icons = ICONS }
				expect(themes.resolveIcon(registry, "game:coin") == COIN):toBe(true)
				expect(themes.resolveIcon(registry, "game:coin.fill") == COIN):toBe(true)
				expect(themes.resolveIcon(registry, "game:star") == STAR):toBe(true)
				expect(themes.resolveIcon(registry, "game:star", "hover") == LIT):toBe(true)
				expect(themes.resolveIcon(registry, "game:star", "pressed") == STAR):toBe(true)
				expect(themes.resolveIcon(registry, "game:star", "selected")):toBe("rbxassetid://5")
				local definition: ThemeTypes.ThemeDefinition = { identity = { id = "glyph-icons" }, icons = ICONS }
				local package, report = themes.define(definition)
				expect(report.ok):toBe(true)
				expect(package ~= nil and themes.resolveIcon(package, "game:coin") ~= nil):toBe(true)
				local bad: ThemeTypes.IconGlyph = { font = { family = "rbxassetid://9001" }, codepoint = 1.5 }
				local broken: { [string]: ThemeTypes.IconEntry } = { ["game:bad"] = bad }
				local invalid: ThemeTypes.ThemeDefinition = { identity = { id = "glyph-icons-bad" }, icons = broken }
				local rejected, problems = themes.define(invalid)
				expect(rejected == nil):toBe(true)
				expect(problems.errors[1] and problems.errors[1].field):toBe("icons.game:bad.codepoint")
			end,
		})

		verifyHarness:case("draws a glyph given to the icon helper at the short side of its box", {
			id = "native_glyph_icons::font glyph icons::draws a glyph given to the icon helper at the short side of its box",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local Host: RobloxHost = Facet.host(runtime)
				local ctx = context(Compose, runtime, { types = engine.types })
				local D2 = engine.types.UDim2
				local fixed: ImageLabel? = nil
				local scaled: ImageLabel? = nil
				local stop = runtime.mount(function()
					local first = ctx.icon(COIN, { Name = "Fixed", Size = D2.fromOffset(30, 20) })
					local second = ctx.icon(COIN, { Name = "Scaled", Size = D2.fromScale(0.5, 0.5) })
					fixed, scaled = first, second
					return Host.Frame { first, second }
				end, engine.new("Folder"))
				local icon = assert(fixed)
				expect(icon.Image):toBe("")
				local glyph = glyphOf(icon)
				expect(glyph.Text):toBe(utf8.char(0xE001))
				expect(glyph.FontFace.Family):toBe("rbxassetid://9001")
				expect(glyph.TextSize):toBe(20)
				expect(glyph.TextScaled):toBe(false)
				expect(glyph.AutoLocalize):toBe(false)
				expect(glyph:HasTag("facet-icon-glyph")):toBe(true)
				local box = assert(scaled)
				local scaledGlyph = glyphOf(box)
				engine.environment.poke(
					(box :: unknown) :: VerifyRoblox.Instance,
					"AbsoluteSize",
					engine.types.Vector2.new(40, 24)
				)
				expect(scaledGlyph.TextSize):toBe(24)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("follows theme state variants and switches between glyph and image art", {
			id = "native_glyph_icons::font glyph icons::follows theme state variants and switches between glyph and image art",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local Host: RobloxHost = Facet.host(runtime)
				local ctx = context(Compose, runtime, { types = engine.types, icons = ICONS })
				local state = Compose.cell("default" :: ThemeTypes.SkinState)
				local made: ImageLabel? = nil
				local stop = runtime.mount(function()
					local star = ctx.icon("game:star", { Name = "Star" }, state)
					made = star
					return Host.Frame { star }
				end, engine.new("Folder"))
				local icon = assert(made)
				expect(glyphOf(icon).Text):toBe(utf8.char(0xE002))
				state:set("hover")
				expect(glyphOf(icon).Text):toBe(utf8.char(0xE003))
				state:set("selected")
				expect(icon.Image):toBe("rbxassetid://5")
				expect(icon:FindFirstChild("Glyph") == nil):toBe(true)
				state:set("default")
				expect(icon.Image):toBe("")
				expect(glyphOf(icon).Text):toBe(utf8.char(0xE002))
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("draws a registered glyph name in each control that takes an icon", {
			id = "native_glyph_icons::font glyph icons::draws a registered glyph name in each control that takes an icon",
			run = function()
				local world = worlds.new(function(UI: Facet.Controls, Host: RobloxHost): Facet.Child
					return Host.Frame {
						UI.Button "Buy" { label = "Buy", icon = "game:coin" },
						UI.Button "Lone" { name = "Coins", icon = "game:coin" },
						UI.Label "Wallet" { title = "Wallet", icon = "game:coin" },
						UI.Badge "Owned" { label = "Owned", icon = "game:coin" },
					}
				end, { icons = ICONS })
				local iconSize = assert(themes.neutralPackage().metrics.controlSizes.regular).iconSize
				for _, name in { "Buy", "Lone" } do
					local icon = world.find("LeadingIcon", world.find(name))
					local glyph = glyphOf(icon)
					expect(`{name} {glyph.Text} {glyph.TextSize}`):toBe(`{name} {utf8.char(0xE001)} {iconSize}`)
				end
				expect(glyphOf(world.find("Icon", world.find("Wallet"))).Text):toBe(utf8.char(0xE001))
				local badge = world.find("Owned")
				local drawn = false
				for _, node in badge:GetDescendants() do
					drawn = drawn or (node.Name == "Glyph" and node.Text == utf8.char(0xE001))
				end
				expect(drawn):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("tints a glyph with the theme paint of its icon in each state", {
			id = "native_glyph_icons::font glyph icons::tints a glyph with the theme paint of its icon in each state",
			run = function()
				local world = worlds.new(function(UI: Facet.Controls, Host: RobloxHost): Facet.Child
					return Host.Frame {
						UI.Button "Buy" { label = "Buy", icon = "game:coin" },
					}
				end, { icons = ICONS })
				local stop, mounted = world.runtime.mount(function()
					return themes.createStyleSheet(world.runtime, nil, { types = world.engine.types })
				end, world.engine.new("Folder"))
				local sheet = assert(mounted)
				local button = world.find("Buy")
				local icon = world.find("LeadingIcon", button)
				local glyph = glyphOf(icon)
				local function paint(property: string): unknown
					local value: unknown = styleRules.resolve(sheet, icon, property)
					if type(value) == "string" and string.sub(value, 1, 1) == "$" then
						return sheet:GetAttribute(string.sub(value, 2))
					end
					return value
				end
				local function check(label: string)
					local ink, fade = paint("ImageColor3"), paint("ImageTransparency")
					expect(`{label} ink {typeof(ink)}`):toBe(`{label} ink Color3`)
					icon.ImageColor3 = ink
					icon.ImageTransparency = if type(fade) == "number" then fade else 0
					expect(`{label} {tostring(glyph.TextColor3)}`):toBe(`{label} {tostring(ink)}`)
					expect(`{label} {glyph.TextTransparency}`):toBe(`{label} {icon.ImageTransparency}`)
				end
				check("resting")
				for _, tag in
					{
						"facet-selected",
						"facet-role-destructive",
						"facet-appearance-soft",
						"facet-accent",
						"facet-disabled",
					}
				do
					button:AddTag(tag)
					check(tag)
					button:RemoveTag(tag)
				end
				stop()
				world.stop()
			end,
		})
	end)
end
