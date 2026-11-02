--!strict
local FixtureRoblox = require("../tools/vendor/verify/src/roblox")
local Verify = require("../tools/vendor/verify/src/core")
local Bdd = require("../tools/vendor/verify/src/bdd")
local Shared = require("../src/ui/types")
local Facet = require("../src")

return function(verifyHarness: Verify.Harness)
	local test = Bdd.create(verifyHarness)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("sound icon catalog", function()
		it("provides bundled sound placeholders and preserves theme overrides", {
			id = "native_themes_media::sound icon catalog::provides bundled sound placeholders and preserves theme overrides",
			run = function()
				local icons = require("../src/ui/icons")
				local themes = require("../src").themes
				for _, name in { "speaker", "volume", "mute" } do
					local entry = assert(icons.resolve(name))
					expect(string.find(entry.contentId, "rbxasset://textures/ui/VoiceChat/SpeakerLight/", 1, true) == 1):toBe(
						true
					)
					expect(themes.resolveIcon({}, name)):toBe(entry.contentId)
				end
				local ThemeTypes = require("../src/ui/theme_types")
				local catalog: { [string]: ThemeTypes.IconEntry } = { mute = "rbxassetid://123" }
				local override: ThemeTypes.IconRegistry = { icons = catalog }
				expect(themes.resolveIcon(override, "mute")):toBe("rbxassetid://123")
			end,
		})
	end)
	describe("game glyph catalog", function()
		it("registers game glyphs as standard art below theme icons", {
			id = "native_themes_media::game glyph catalog::registers game glyphs as standard art below theme icons",
			run = function()
				local icons = require("../src/ui/icons")
				local themes = require("../src").themes
				local ThemeTypes = require("../src/ui/theme_types")
				for _, name in
					{
						"star",
						"heart",
						"chat",
						"gift",
						"coin",
						"gem",
						"bag",
						"trophy",
						"crown",
						"lock",
						"bolt",
						"wrench",
						"timer",
						"car",
					}
				do
					local art = assert(icons.ART[name], name)
					expect(art.assetName):toBe("facet_icon_" .. name)
					expect(art.tintRole):toBe("content")
					expect(themes.resolveIcon({}, name)):toBe(art.contentId)
					expect(themes.resolveIcon({}, name .. ".fill")):toBe(art.contentId)
					local catalog: { [string]: ThemeTypes.IconEntry } = { [name] = "rbxassetid://7" }
					local themed: ThemeTypes.IconRegistry = { icons = catalog }
					expect(themes.resolveIcon(themed, name)):toBe("rbxassetid://7")
				end
				expect(themes.resolveIcon({}, "person")):toBe(icons.ART.person.contentId)
				expect(themes.resolveIcon({}, "kart")):toBe(nil)
			end,
		})
	end)
	type AvatarMember = typeof(require("@repo/tools/typecheck/aliases").AvatarMember)
	type FixtureShadow = typeof(require("@repo/tools/typecheck/aliases").FixtureShadow)

	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
	type MotionLevel = typeof(require("@repo/tools/typecheck/aliases").MotionLevel)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type TextButtonConstructor = typeof(require("@repo/tools/typecheck/aliases").TextButtonConstructor)
	local FixtureComposeTypes = require("../src/vendor/compose/core")
	local FixtureMediaTypes = require("../src/ui/media_types")
	local FixtureMediaProps = require("../src/ui/media_props")
	local FixtureInputProps = require("../src/ui/input_props")
	local FixtureThemeTypes = require("../src/ui/theme_types")
	type Use = FixtureComposeTypes.Use

	local transitionOf = require("./lib/transition")
	local styleProperties = require("./lib/style_properties")
	local Compose = require("../src/vendor/compose/core")
	local Roblox = require("../src/vendor/compose/roblox")
	local context = require("../src/ui/context")
	local controls = require("../src/ui")
	local media = require("../src/ui/media")
	local themes: FixtureThemeTypes.Themes = require("../src/ui/themes")(Compose)
	local engineLib = require("./lib/native_engine")

	local function setup()
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Roblox.createRuntime(engine)
		local UI = media(context(Compose, runtime, { types = engine.types }))
		return engine, runtime, UI
	end

	local function themeState(
		package: FixtureThemeTypes.ReadOnlyThemePackage
	): FixtureComposeTypes.Value<FixtureThemeTypes.ReadOnlyThemePackage>
		return Compose.cell(package)
	end

	local function style(sheet: StyleSheet, selector: string)
		for _, node in sheet:GetChildren() do
			local rule = node :: StyleRule
			if table.find(string.split(rule.Selector, ", "), selector) ~= nil then
				return styleProperties(rule)
			end
		end
		error("No rule: " .. selector)
	end

	describe("native themes and media", function()
		it("updates a row icon's art across button states beside a static trailing icon", {
			id = "native_themes_media::row-icon-button-states",
			run = function()
				for _, withTrailing in { true, false } do
					local engine = engineLib.new()
					local runtime: ComposeRuntime = Roblox.createRuntime(engine)
					local package = themes.neutralPackage()
					package.icons = {
						rowState = {
							default = "rbxassetid://100",
							hover = "rbxassetid://101",
							pressed = "rbxassetid://102",
							disabled = "rbxassetid://103",
						},
						fixed = "rbxassetid://104",
					}
					local enabled = Compose.cell(true)
					local UI = controls(Compose, runtime, { types = engine.types, theme = package })
					local button: TextButton
					local stop = runtime.mount(function()
						local props: FixtureInputProps.ButtonProps = {
							row = { title = "Row", icon = "rowState" },
							trailingIcon = if withTrailing then "fixed" else nil,
							enabled = enabled,
							onActivate = function() end,
						}
						button = UI.Button "Row"(props)
						return button
					end, engine.new("ScreenGui"))
					local icon = assert(button:FindFirstChild("LeadingIcon", true))
					assert(icon:IsA("ImageLabel"))
					expect(icon.Image):toBe("rbxassetid://100")
					engine.environment.poke(
						FixtureRoblox.assertInstance(button),
						"GuiState",
						engine.types.Enum.GuiState.Hover
					)
					expect(icon.Image):toBe("rbxassetid://101")
					engine.environment.poke(
						FixtureRoblox.assertInstance(button),
						"GuiState",
						engine.types.Enum.GuiState.Press
					)
					expect(icon.Image):toBe("rbxassetid://102")
					enabled:set(false)
					expect(icon.Image):toBe("rbxassetid://103")
					enabled:set(true)
					engine.environment.poke(
						FixtureRoblox.assertInstance(button),
						"GuiState",
						engine.types.Enum.GuiState.Idle
					)
					expect(icon.Image):toBe("rbxassetid://100")
					if withTrailing then
						local trailing = assert(button:FindFirstChild("TrailingIcon", true))
						assert(trailing:IsA("ImageLabel"))
						expect(trailing.Image):toBe("rbxassetid://104")
					end
					stop()
					runtime:dispose()
				end
			end,
		})

		it("scales the caption outline at ten feet and keeps its opacity", function()
			local package = themes.neutralPackage()
			local far = themes.forDistance(package, "ten-foot").metrics.controls.button
			local near = package.metrics.controls.button
			expect(far.captionStroke):toBeGreaterThan(near.captionStroke)
			expect(far.captionStrokeOpacity):toBe(near.captionStrokeOpacity)
		end)
		it("ten-foot text never drops below the console reading floors", {
			id = "native_themes_media::ten-foot-text-floors",
			run = function()
				local definition: FixtureThemeTypes.ThemeDefinition =
					{ identity = { id = "floors", displayName = "Floors" } }
				local package = assert((themes.define(definition)))
				local far = themes.forDistance(package, "ten-foot").metrics.typography
				local near = package.metrics.typography
				local smallest = math.huge
				for _, entry in near do
					smallest = math.min(smallest, entry.size)
				end
				for role, entry in far do
					local size = near[role].size
					expect(entry.size >= (if size == smallest then 24 else 28)):toBe(true)
					expect(entry.size >= math.floor(size * 1.5 + 0.5)):toBe(true)
					for other, peer in far do
						if near[other].size < size then
							expect(peer.size < entry.size):toBe(true)
						elseif near[other].size == size then
							expect(peer.size):toBe(entry.size)
						end
					end
				end
			end,
		})

		it("keeps each fade stroke presence selector on its theme motion token", {
			id = "native_themes_media::native themes and media::keeps each fade stroke presence selector on its theme motion token",
			run = function()
				local engine = engineLib.new()
				local runtime = Roblox.createRuntime(engine)
				local package = themes.neutralPackage()
				local hoverProperties: FixtureThemeTypes.AuthoredRuleProperties = { Thickness = 2 }
				local pressProperties: FixtureThemeTypes.AuthoredRuleProperties = { Thickness = 3 }
				local rules: { FixtureThemeTypes.Rule } = {
					{ selector = ".facet-button:Hover::UIStroke", properties = hoverProperties },
					{ selector = ".facet-button:Press::UIStroke", properties = pressProperties },
				}
				package.rules = rules
				local stop, sheet = runtime.mount(function()
					return themes.createStyleSheet(runtime, package, { types = engine.types })
				end, engine.new("Folder"))
				local checked = 0
				for _, child in (sheet :: StyleSheet):GetChildren() do
					local rule = child :: StyleRule
					if string.find(rule.Name, "presence", 1, true) then
						for _, selector in string.split(rule.Selector, ", ") do
							local role = if string.find(selector, ":Press", 1, true)
								then "Press"
								elseif string.find(selector, ":Hover", 1, true) then "Hover"
								else "Normal"
							expect(rule:GetPropertyTransitions().Transparency):toBe("$FacetMotion" .. role)
							checked += 1
						end
					end
				end
				expect(checked > 0):toBe(true)
				stop()
				runtime:dispose()
			end,
		})
		it("keeps disabled emphasis text readable after a consumer changes its accent pair", {
			id = "native_themes_media::native themes and media::keeps disabled emphasis text readable after a consumer changes its accent pair",
			run = function()
				local engine = engineLib.new()
				local runtime = Roblox.createRuntime(engine)
				local package = themes.neutralPackage()
				package.style.themes[1].colors.accent = { r = 0.76, g = 0.96, b = 0.27 }
				package.style.themes[1].colors.onAccent = { r = 0.06, g = 0.09, b = 0.12 }
				local stop, sheet = runtime.mount(function()
					return themes.createStyleSheet(runtime, package, { types = engine.types })
				end, engine.new("Folder"))
				local node = engine.new("TextButton")
				node:AddTag("facet-accent")
				node:AddTag("facet-disabled")
				local styleRules = require("./lib/style_rules")
				local opacity = styleRules.resolve(sheet, node, "TextTransparency") :: number
				local ink = engine.types.Color3.new(0.06, 0.09, 0.12)
				local background = engine.types.Color3.new(0.76, 0.96, 0.27)
				expect(opacity < 0.4):toBe(true)
				expect(require("../src/ui/theme_support").contrast(ink:Lerp(background, opacity), background) >= 4.5):toBe(
					true
				)
				stop()
				runtime:dispose()
			end,
		})
		it("installs motion tokens before a palette token starts a theme transition", {
			id = "native_themes_media::native themes and media::installs motion tokens before a palette token starts a theme transition",
			run = function()
				local engine, runtime = setup()
				local nextPackage = themes.neutralPackage()
				nextPackage.metrics.motion.normal = 0.4
				nextPackage.style.themes[1].colors.content = { r = 0.8, g = 0.8, b = 0.8 }
				local source = Compose.cell(assert((themes.define(themes.neutralPackage()))))
				local stop, result = runtime.mount(function()
					return themes.createStyleSheet(runtime, source, { types = engine.types })
				end, engine.new("Folder"))
				local sheet = result :: StyleSheet
				local observed: number? = nil
				local connection = sheet:GetAttributeChangedSignal("FacetColor_content"):Connect(function()
					for _, child in sheet:GetChildren() do
						local rule = child :: StyleRule
						if rule.Selector == ".facet-text" then
							observed = transitionOf(rule, "TextColor3").Time
						end
					end
				end)
				source:set(assert((themes.define(nextPackage))))
				expect(observed):toBeFloat32(0.4)
				connection:Disconnect()
				stop()
				runtime:dispose()
			end,
		})

		it("swaps a palette with one token write and no control or rule work", {
			id = "native_themes_media::native themes and media::swaps a palette with one token write and no control or rule work",
			run = function()
				local engine, runtime = setup()
				local first = assert((themes.define(themes.neutralPackage())))
				local tinted = themes.neutralPackage()
				tinted.style.themes[1].colors.content = { r = 0.8, g = 0.9, b = 1 }
				local second = assert((themes.define(tinted)))
				local source = Compose.cell(first)
				local UI = Facet.controls(runtime, { types = engine.types, theme = source })
				local Host = Facet.host(runtime)
				local stop, result = runtime.mount(function()
					return Host.Folder "Screen" {
						themes.createStyleSheet(runtime, source, { types = engine.types }),
						UI.Button "Action" { label = "Action", onActivate = function() end },
					}
				end, engine.new("Folder"))
				local sheet = assert((result :: Instance):FindFirstChildWhichIsA("StyleSheet"))
				source:set(second)
				source:set(first)
				local writes: { string } = {}
				local observer = engine.environment.observe(function(event)
					if event.operation == "setProperty" or event.operation == "setAttribute" then
						table.insert(writes, `{event.object.ClassName}.{tostring(event.member)}`)
					end
				end)
				source:set(second)
				observer:Disconnect()
				expect(writes):toEqual({ "StyleSheet.FacetColor_content" })
				expect(sheet:GetAttribute("FacetColor_content")):toBe(engine.types.Color3.new(0.8, 0.9, 1))
				source:set(first)
				expect(sheet:GetAttribute("FacetColor_content") == engine.types.Color3.new(0.8, 0.9, 1)):toBe(false)
				stop()
				runtime:dispose()
			end,
		})

		it("mounts a rule only once an instance carries every class its selector names", {
			id = "native_themes_media::native themes and media::mounts a rule only once an instance carries every class its selector names",
			run = function()
				local engine, runtime = setup()
				type Listener = { callback: (Instance) -> (), connected: boolean }
				local tagged: { [string]: boolean } = { ["facet-text"] = true }
				local listeners: { [string]: { Listener } } = {}
				local fake = {
					GetTagged = function(_: unknown, class: string): { Instance }
						return if tagged[class] then { engine.new("Frame") } else {}
					end,
					GetInstanceAddedSignal = function(_: unknown, class: string)
						return {
							Connect = function(_: unknown, callback: (Instance) -> ())
								local listener: Listener = { callback = callback, connected = true }
								listeners[class] = listeners[class] or {}
								table.insert(listeners[class], listener)
								return {
									Disconnect = function()
										listener.connected = false
									end,
								}
							end,
						}
					end,
				}
				local function arrive(class: string)
					tagged[class] = true
					local waiting: { Listener } = listeners[class] or {}
					for _, listener in waiting do
						if listener.connected then
							listener.callback(engine.new("Frame"))
						end
					end
				end
				local function has(sheet: StyleSheet, selector: string): boolean
					for _, child in sheet:GetChildren() do
						if table.find(string.split((child :: StyleRule).Selector, ", "), selector) ~= nil then
							return true
						end
					end
					return false
				end
				local stopAll, everything = runtime.mount(function()
					return themes.createStyleSheet(runtime, themes.neutralPackage(), { types = engine.types })
				end, engine.new("Folder"))
				local stop, result = runtime.mount(function()
					return themes.createStyleSheet(runtime, themes.neutralPackage(), {
						types = engine.types,
						collectionService = (fake :: unknown) :: CollectionService,
					})
				end, engine.new("Folder"))
				local sheet = result :: StyleSheet
				expect(has(sheet, ".facet-text")):toBe(true)
				expect(has(sheet, ".facet-validation")):toBe(false)
				expect(#sheet:GetChildren() < #(everything :: StyleSheet):GetChildren()):toBe(true)
				arrive("facet-validation")
				expect(has(sheet, ".facet-validation")):toBe(true)
				expect(style(sheet, ".facet-validation").TextColor3):toBe(
					style(everything :: StyleSheet, ".facet-validation").TextColor3
				)
				stop()
				local open = 0
				for _, list in listeners do
					for _, listener in list do
						if listener.connected then
							open += 1
						end
					end
				end
				expect(open):toBe(0)
				stopAll()
				runtime:dispose()
			end,
		})

		it("keeps palette roles distinct and updates their native tokens without rewriting color rules", {
			id = "native_themes_media::native themes and media::keeps palette roles distinct and updates their native tokens without rewriting color rules",
			run = function()
				local engine, runtime = setup()
				local package = themes.neutralPackage()
				package.style.themes[1].colors.accent = package.style.themes[1].colors.danger
				local alternate = table.clone(package.style.themes[1])
				alternate.name = "Alternate"
				alternate.colors = table.clone(alternate.colors)
				alternate.colors.accent = { r = 0.2, g = 0.3, b = 0.4 }
				table.insert(package.style.themes, alternate)
				local palette = Compose.cell(package.style.defaultTheme)
				local definition = assert((themes.define(package)))
				local stop, result = runtime.mount(function()
					return themes.createStyleSheet(runtime, definition, {
						types = engine.types,
						theme = palette,
					})
				end, engine.new("Folder"))
				local sheet = result :: StyleSheet
				local writes = 0
				for _, child in sheet:GetChildren() do
					local rule = child :: StyleRule
					if rule.Selector ~= ".facet-text" and rule.Selector ~= ".facet-accent-text" then
						continue
					end
					local methods = (
						rule :: unknown
					) :: { SetProperties: (StyleRule, FixtureThemeTypes.RuleProperties) -> () }
					local set = methods.SetProperties
					methods.SetProperties = function(self, properties)
						writes += 1
						set(self, properties)
					end
				end
				local content = style(sheet, ".facet-validation").TextColor3
				palette:set("Alternate")
				expect(style(sheet, ".facet-validation").TextColor3):toBe(content)
				expect(style(sheet, ".facet-accent-text").TextColor3):toBe(engine.types.Color3.new(0.2, 0.3, 0.4))
				expect(writes):toBe(0)
				palette:set(package.style.defaultTheme)
				expect(style(sheet, ".facet-accent-text").TextColor3):toBe(content)
				expect(writes):toBe(0)
				stop()
				runtime:dispose()
			end,
		})

		it("resolves authored metric rules through distance and theme changes", {
			id = "native_themes_media::native themes and media::resolves authored metric rules through distance and theme changes",
			run = function()
				local engine, runtime = setup()
				local definition = themes.neutralPackage()
				definition.metrics.strokes.outline = 3
				definition.rules = {
					{
						selector = ".toy::UIStroke",
						properties = { Thickness = { metric = "strokes.outline" } } :: FixtureThemeTypes.AuthoredRuleProperties,
					} :: FixtureThemeTypes.Rule,
					{
						selector = ".toy",
						properties = { TextSize = { metric = "typography.title.size" }, Rotation = 3 } :: FixtureThemeTypes.AuthoredRuleProperties,
					} :: FixtureThemeTypes.Rule,
				}
				local package = assert((themes.define(definition)))
				local chosen, distant = themeState(package), Compose.cell(false)
				local stop, mounted = runtime.mount(function()
					return themes.createStyleSheet(runtime, chosen, { types = engine.types, tenFoot = distant })
				end, engine.new("ScreenGui"))
				local sheet = mounted :: StyleSheet
				expect(style(sheet, ".toy::UIStroke").Thickness):toBe(3)
				distant:set(true)
				expect(style(sheet, ".toy::UIStroke").Thickness):toBe(4.5)
				expect(style(sheet, ".toy").TextSize):toBe(
					themes.forDistance(package, "ten-foot").metrics.typography.title.size
				)
				expect(style(sheet, ".toy").Rotation):toBe(3)
				definition.metrics.strokes.outline = 4
				chosen:set((assert((themes.define(definition)))))
				expect(style(sheet, ".toy::UIStroke").Thickness):toBe(6)
				distant:set(false)
				expect(style(sheet, ".toy::UIStroke").Thickness):toBe(4)
				stop()
				runtime:dispose()
			end,
		})
		it("rejects malformed or nonnumeric authored metric references", {
			id = "native_themes_media::native themes and media::rejects malformed or nonnumeric authored metric references",
			run = function()
				for _, path in
					{ "strokes.missing", "strokes", "strokes..hairline", ".strokes.hairline", "motion.easing.fade" }
				do
					local definition = themes.neutralPackage()
					definition.rules = {
						{
							selector = ".toy::UIStroke",
							properties = { Thickness = { metric = path } } :: FixtureThemeTypes.AuthoredRuleProperties,
						} :: FixtureThemeTypes.Rule,
					}
					local package, report = themes.define(definition)
					expect(package):toBe(nil)
					expect(report.ok):toBe(false)
					expect(report.errors[1].field):toBe("rules.1.properties.Thickness")
				end
			end,
		})

		it("uses an end ellipsis for bounded disclosure text without changing wrap or authored truncation", {
			id = "native_themes_media::native themes and media::uses an end ellipsis for bounded disclosure text without changing wrap or authored truncation",
			run = function()
				local engine, runtime, UI = setup()
				local labels: { TextLabel } = {}
				local stop = runtime.mount(function()
					local text = "A deliberately long label that has to wrap or truncate honestly in every theme"
					local specs: { FixtureMediaProps.TextProps } = {
						{ text = text, disclose = true },
						{ text = text, disclose = true, wrap = true },
						{ text = text, disclose = true, TextTruncate = engine.types.Enum.TextTruncate.None },
						{ text = text, disclose = true, truncate = "middle" :: "middle" },
					}
					for index, spec in specs do
						local props = table.clone(spec)
						props.Size = engine.types.UDim2.fromOffset(200, 24)
						labels[index] = (UI.Text(props) :: unknown) :: TextLabel
					end
					return labels
				end, engine.new("Frame"))
				expect(labels[1].TextTruncate):toBe(engine.types.Enum.TextTruncate.AtEnd)
				expect(labels[2].TextWrapped):toBe(true)
				expect(labels[2].TextTruncate):toBe(engine.types.Enum.TextTruncate.None)
				expect(labels[3].TextTruncate):toBe(engine.types.Enum.TextTruncate.None)
				expect(labels[4].TextTruncate):toBe(engine.types.Enum.TextTruncate.None)
				stop()
				runtime:dispose()
			end,
		})

		it("paints a cached image with its prepared row without a second entrance", function(_own, t)
			for _, grouped in { true, false } do
				local native = engineLib.new()
				local runtime = Roblox.createRuntime(native)
				local Host = Facet.host(runtime)
				local image: ImageLabel? = nil
				local provider = {
					GetAssetFetchStatus = function(_self: unknown, _content: string): Enum.AssetFetchStatus
						return native.types.Enum.AssetFetchStatus.Success
					end,
				}
				local stop = runtime.mount(function()
					local ctx = context(Compose, runtime, {
						types = native.types,
						motionLevel = "normal",
						services = { ContentProvider = (provider :: unknown) :: ContentProvider },
					})
					local row = if grouped then Host.CanvasGroup { GroupTransparency = 1 } else Host.Frame {}
					row:SetAttribute("FacetCollectionRow", true)
					row:SetAttribute("FacetCollectionReady", false)
					local artwork = Host.ImageLabel { Image = "rbxassetid://10" }
					image = artwork
					native.environment.poke(
						FixtureRoblox.assertInstance(artwork),
						"AbsoluteSize",
						native.types.Vector2.new(28, 28)
					)
					native.environment.poke(FixtureRoblox.assertInstance(artwork), "IsLoaded", false)
					require("../src/ui/media_readiness")(ctx, artwork)
					artwork.Parent = row
					return row
				end, native.new("ScreenGui"))
				t:defer(function()
					stop()
					runtime:dispose()
				end)
				expect(assert(image):GetAttribute("FacetMediaReady")):toBe(true)
				expect(assert(image).ImageTransparency):toBe(0)
			end
		end)

		it("reveals a fetched collection image when native IsLoaded stays false", function(_own, t)
			local prepare = require("../src/ui/media_readiness")
			local callable: unknown = prepare
			assert(type(callable) == "function")
			local environment = getfenv(callable)
			local originalTask = environment.task
			local pending: { thread } = {}
			environment.task = {
				defer = function(callback: () -> ()): thread
					local thread = coroutine.create(callback)
					table.insert(pending, thread)
					return thread
				end,
				cancel = function(thread: thread)
					coroutine.close(thread)
				end,
			}
			t:defer(function()
				environment.task = originalTask
			end)
			local native = engineLib.new()
			local now = 0
			native.clock = function()
				return now
			end
			local runtime = Roblox.createRuntime(native)
			local Host = Facet.host(runtime)
			local fetched: Instance? = nil
			local provider = {
				PreloadAsync = function(
					_self: unknown,
					instances: { Instance },
					callback: (string, Enum.AssetFetchStatus) -> ()
				)
					fetched = instances[1]
					callback("rbxassetid://10", native.types.Enum.AssetFetchStatus.Success)
				end,
			}
			local image: ImageLabel? = nil
			local stop = runtime.mount(function()
				local ctx = context(Compose, runtime, {
					types = native.types,
					motionLevel = "none",
					services = { ContentProvider = (provider :: unknown) :: ContentProvider },
				})
				local row = Host.Frame {}
				row:SetAttribute("FacetCollectionRow", true)
				local artwork = Host.ImageLabel { Image = "rbxassetid://10" }
				image = artwork
				local loading = (artwork :: unknown) :: { IsLoaded: boolean }
				native.environment.poke(FixtureRoblox.assertInstance(loading), "IsLoaded", false)
				prepare(ctx, artwork)
				artwork.Parent = row
				return row
			end, native.new("ScreenGui"))
			t:defer(function()
				stop()
				runtime:dispose()
			end)
			local artwork = assert(image)
			local geometry = (artwork :: unknown) :: { AbsoluteSize: Vector2 }
			native.environment.poke(
				FixtureRoblox.assertInstance(geometry),
				"AbsoluteSize",
				native.types.Vector2.new(240, 180)
			)
			expect(#pending > 0):toBe(true)
			local function flush()
				for _, queued in pending do
					if coroutine.status(queued) == "suspended" then
						expect(coroutine.resume(queued)):toBe(true)
					end
				end
			end
			flush()
			expect(fetched):toBe(artwork)
			for _ = 1, 30 do
				now += 1 / 60
				native.heartbeat:Fire(1 / 60)
				flush()
			end
			expect(artwork.IsLoaded):toBe(false)
			expect(artwork:GetAttribute("FacetMediaReady")):toBe(true)
			expect(artwork.ImageTransparency):toBe(0)
		end)
		it("keeps a newly materialized stage on its current styled colour throughout media reveal", {
			id = "native_themes_media::native themes and media::keeps a newly materialized stage on its current styled colour throughout media reveal",
			run = function()
				for _, rgb in { { 32, 30, 44 }, { 242, 244, 248 } } do
					local engine = engineLib.new()
					local now = 0
					engine.clock = function()
						return now
					end
					local runtime: ComposeRuntime = Roblox.createRuntime(engine)
					local ctx = context(Compose, runtime, { types = engine.types })
					local Host = Facet.host(runtime)
					local grey = engine.types.Color3.fromRGB(163, 162, 165)
					local themed = engine.types.Color3.fromRGB(rgb[1], rgb[2], rgb[3])
					local resolved = Compose.cell(grey)
					local observed = ctx.observeStyled.BackgroundColor3
					local stage: ViewportFrame? = nil
					ctx.observeStyled.BackgroundColor3 = function(node: GuiObject)
						return if node == stage then resolved else observed(node)
					end
					local stop = runtime.mount(function()
						local row = Host.Frame { BackgroundColor3 = themed }
						row:SetAttribute("FacetCollectionRow", true)
						local viewport = Host.ViewportFrame { BackgroundColor3 = grey }
						stage = viewport
						local styled = (viewport :: unknown) :: { GetStyled: (Instance, string) -> unknown }
						styled.GetStyled = function(_self: Instance, property: string): unknown
							assert(property == "BackgroundColor3")
							return if viewport.BackgroundColor3 == grey
								then resolved:peek()
								else viewport.BackgroundColor3
						end
						require("../src/ui/media_readiness")(ctx, viewport)
						viewport.Parent = row
						return row
					end, engine.new("ScreenGui"))
					local node = assert(stage)
					local baseline = engine.new("ViewportFrame") :: ViewportFrame
					local originalStyle = (baseline :: unknown) :: { GetStyled: (Instance, string) -> unknown }
					originalStyle.GetStyled = function(_self: Instance, property: string): unknown
						assert(property == "BackgroundColor3")
						return resolved:peek()
					end
					resolved:set(themed)
					local geometry = (node :: unknown) :: { AbsoluteSize: Vector2 }
					engine.environment.poke(
						FixtureRoblox.assertInstance(geometry),
						"AbsoluteSize",
						engine.types.Vector2.new(240, 180)
					)
					for _ = 1, 30 do
						now += 1 / 60
						engine.heartbeat:Fire(1 / 60)
						expect(node:GetStyled("BackgroundColor3")):toBe(themed)
						expect(node:GetStyled("BackgroundColor3")):toBe(baseline:GetStyled("BackgroundColor3"))
					end
					baseline:Destroy()
					stop()
					runtime:dispose()
				end
			end,
		})

		it("keeps field ink separate from row selection and uses readable link ink", {
			id = "native_themes_media::native themes and media::keeps field ink separate from row selection and uses readable link ink",
			run = function()
				local engine, runtime = setup()
				local stop, sheet: any = runtime.mount(function()
					return themes.createStyleSheet(runtime, themes.neutralPackage(), { types = engine.types })
				end, engine.new("Folder"))
				local content = style(sheet, ".facet-text").TextColor3
				expect(style(sheet, ".facet-selected >> .facet-text.facet-field").TextColor3):toBe(content)
				local link = style(sheet, ".facet-appearance-link >> .facet-button-caption").TextColor3
				local function luminance(color)
					local function linear(value)
						return if value <= 0.04045 then value / 12.92 else ((value + 0.055) / 1.055) ^ 2.4
					end
					return linear(color.R) * 0.2126 + linear(color.G) * 0.7152 + linear(color.B) * 0.0722
				end
				local surface = style(sheet, ".facet-panel").BackgroundColor3
				local a, b = luminance(link :: Color3), luminance(surface :: Color3)
				expect((math.max(a, b) + 0.05) / (math.min(a, b) + 0.05)):toBeGreaterThanOrEqual(4.5)
				stop()
				runtime:dispose()
			end,
		})

		it("reserves the full radial target for its native single line label", {
			id = "native_themes_media::native themes and media::reserves the full radial target for its native single line label",
			run = function()
				local engine, runtime = setup()
				local stop, sheet: any = runtime.mount(function()
					return themes.createStyleSheet(runtime, themes.neutralPackage(), { types = engine.types })
				end, engine.new("Folder"))
				for _, side in { "Left", "Right", "Top", "Bottom" } do
					expect(
						(style(sheet, ".facet-button.facet-radial-label::UIPadding")["Padding" .. side] :: UDim).Offset
					):toBe(0)
				end
				stop()
				runtime:dispose()
			end,
		})
		it("gives a text badge a native padding child for its status dot inset", {
			id = "native_themes_media::native themes and media::gives a text badge a native padding child for its status dot inset",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local UI = require("../src").controls(runtime, { types = engine.types })
				local badge: GuiObject? = nil
				local stop = runtime.mount(function()
					badge = UI.Badge "Coins" { label = "120 coins", appearance = "status", status = "warning" }
					return badge
				end, engine.new("Folder"))
				expect(assert(badge):FindFirstChildWhichIsA("UIPadding") ~= nil):toBe(true)
				stop()
				runtime:dispose()
			end,
		})
		it("calendar scroll padding reserves only the panel artwork", {
			id = "native_themes_media::native themes and media::calendar scroll padding reserves only the panel artwork",
			run = function()
				local engine, runtime = setup()
				for _, inset in { 0, 24 } do
					local package = themes.neutralPackage()
					package.chrome =
						{ panel = { contentInsets = { left = inset, right = inset, top = inset, bottom = inset } } }
					local stop, sheet = runtime.mount(function()
						return themes.createStyleSheet(runtime, package, { types = engine.types })
					end, engine.new("Folder"))
					for _, side in { "Left", "Right", "Top", "Bottom" } do
						expect(
							(
								style(sheet :: StyleSheet, ".facet-panel.facet-calendar-scroll::UIPadding")["Padding" .. side] :: UDim
							).Offset
						):toBe(inset)
					end
					stop()
				end
				runtime:dispose()
			end,
		})
		it("pins artwork and captions to the observed automatic layout origin", {
			id = "native_themes_media::native themes and media::pins artwork and captions to the observed automatic layout origin",
			run = function()
				local engine, runtime = setup()
				local Host = Facet.host(runtime)
				local decoration = require("../src/ui/native_decoration")
				local stop, target: any = runtime.mount(function()
					return Host.TextButton {
						AutomaticSize = engine.types.Enum.AutomaticSize.XY,
						Host.UIPadding {
							PaddingLeft = engine.types.UDim.new(0, 28),
							PaddingRight = engine.types.UDim.new(0, 28),
						},
					}
				end, engine.new("Folder"))
				local boundary: GuiObject?
				runtime.mount(function()
					boundary = decoration(Compose, runtime, engine.types, target, Host.Frame { Name = "Skin" })
					return boundary
				end, target)
				assert(boundary)
				engine.environment.poke(target, "AbsolutePosition", engine.types.Vector2.new(1744, 104))
				engine.environment.poke(target, "AbsoluteSize", engine.types.Vector2.new(65, 38))
				engine.environment.poke(
					FixtureRoblox.assertInstance(boundary),
					"AbsoluteSize",
					engine.types.Vector2.new(1, 1)
				)
				engine.environment.poke(
					FixtureRoblox.assertInstance(boundary),
					"AbsolutePosition",
					engine.types.Vector2.new(1809, 131)
				)
				local bounds: any = boundary:FindFirstChild("SkinBounds")
				engine.environment.poke(bounds, "AbsoluteSize", engine.types.Vector2.new(65, 38))
				local origin = boundary.AbsolutePosition
					+ engine.types.Vector2.new(bounds.Position.X.Offset, bounds.Position.Y.Offset)
					- bounds.AbsoluteSize
				expect(origin):toBe(target.AbsolutePosition)
				stop()
				runtime:dispose()
			end,
		})
		it("applies a live text preference to every typography role", {
			id = "native_themes_media::native themes and media::applies a live text preference to every typography role",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local preference = Compose.cell("Medium")
				context(Compose, runtime, { types = engine.types, environment = { preferredTextSize = preference } })
				local stop, sheet: any = runtime.mount(function()
					return themes.createStyleSheet(runtime, themes.neutralPackage(), { types = engine.types })
				end, engine.new("Folder"))
				local base = style(sheet, ".facet-text").TextSize :: number
				preference:set("Largest")
				expect(style(sheet, ".facet-text").TextSize):toBe(base + 6)
				expect(style(sheet, ".facet-type-control").TextSize):toBe(
					themes.neutralPackage().metrics.typography.control.size + 6
				)
				preference:set("Medium")
				expect(style(sheet, ".facet-text").TextSize):toBe(base)
				stop()
				runtime:dispose()
			end,
		})
		it("keeps native theme rules reactive without writing instance paint", {
			id = "native_themes_media::native themes and media::keeps native theme rules reactive without writing instance paint",
			run = function()
				local engine, runtime, UI = setup()
				local selected = themeState(themes.neutralPackage())
				local sheet: any, label: any
				local stop = runtime.mount(function()
					sheet = themes.createStyleSheet(runtime, selected, { types = engine.types })
					label = UI.Text { text = "Themed" }
					return Facet.host(runtime).Frame({
						sheet,
						runtime.constructors.StyleLink { StyleSheet = Compose.static(sheet) },
						label,
					})
				end, engine.new("Folder"))
				local nextTheme = themes.neutralPackage()
				nextTheme.style.themes[1].colors.content = { r = 0.1, g = 0.2, b = 0.3 }
				selected:set(nextTheme)
				expect(style(sheet, ".facet-text").TextColor3):toBe(engine.types.Color3.new(0.1, 0.2, 0.3))
				expect(label.Text):toBe("Themed")
				stop()
				expect((sheet:isDestroyed())):toBe(true)
				runtime:dispose()
			end,
		})

		it("retargets native theme paint with shared timing and disables motion without replacing rules", {
			id = "native_themes_media::native themes and media::retargets native theme paint with shared timing and disables motion without replacing rules",
			run = function()
				local engine, runtime = setup()
				local package = themes.neutralPackage()
				package.metrics.motion.normal = 0.32
				local light = table.clone(package.style.themes[1])
				light.name = "Light"
				light.colors = table.clone(light.colors)
				light.colors.surface = { r = 0.9, g = 0.9, b = 0.9 }
				light.colors.content = { r = 0.1, g = 0.1, b = 0.1 }
				light.extra = if light.extra then table.clone(light.extra) else {}
				assert(light.extra).onSelected = { r = 1, g = 1, b = 1 }
				package.style.themes = { package.style.themes[1], light }
				package = assert((themes.define(package)))
				local selection, reduced, explicit: FixtureComposeTypes.Value<(TweenInfo | false)?> =
					Compose.cell("Dark"), Compose.cell(false), Compose.cell(nil :: TweenInfo | false | nil)
				local stop, sheet: any = runtime.mount(function()
					return themes.createStyleSheet(runtime, package, {
						types = engine.types,
						theme = selection,
						motionLevel = (Compose.formula(function(use: Use): "normal" | "limited" | "none"
							return if use(reduced) then "none" else "normal"
						end) :: unknown) :: MotionLevel,
						transition = explicit,
					})
				end, engine.new("Folder"))
				local rules = sheet:GetChildren()
				local textRule, surfaceRule
				for _, rule in rules do
					if rule.Selector == ".facet-text" then
						textRule = rule
					elseif rule.Selector == ".facet-surface" then
						surfaceRule = rule
					end
				end
				local timing = transitionOf(textRule, "TextColor3")
				expect(timing.Time):toBeFloat32(0.32)
				expect(timing.EasingStyle):toBe(engine.types.Enum.EasingStyle.Quad)
				expect((transitionOf(surfaceRule, "BackgroundColor3"))):toBe(timing)
				expect((transitionOf(surfaceRule, "BackgroundTransparency"))):toBe(timing)
				expect((transitionOf(textRule, "TextSize"))):toBe(nil)
				selection:set("Light")
				expect(styleProperties(textRule).TextColor3):toBe(engine.types.Color3.new(0.1, 0.1, 0.1))
				expect(styleProperties(surfaceRule).BackgroundColor3):toBe(engine.types.Color3.new(0.9, 0.9, 0.9))
				selection:set("Dark")
				expect((transitionOf(textRule, "TextColor3"))):toBe(timing)
				expect(styleProperties(textRule).TextColor3):toBe(
					engine.types.Color3.new(236 / 255, 239 / 255, 245 / 255)
				)
				expect(sheet:GetChildren()[1]):toBe(rules[1])
				expect(#sheet:GetChildren()):toBe(#rules)
				expect((engineLib.connections(engine.heartbeat))):toBe(0)
				reduced:set(true)
				expect(transitionOf(textRule, "TextColor3").Time):toBe(0)
				expect(transitionOf(surfaceRule, "BackgroundColor3").Time):toBe(0)
				selection:set("Light")
				expect(styleProperties(surfaceRule).BackgroundColor3):toBe(engine.types.Color3.new(0.9, 0.9, 0.9))
				reduced:set(false)
				local override = engine.types.TweenInfo.new(0.6, engine.types.Enum.EasingStyle.Linear)
				explicit:set(override)
				expect((transitionOf(surfaceRule, "BackgroundColor3"))):toBe(override)
				explicit:set(false :: false)
				expect(transitionOf(textRule, "TextColor3").Time):toBe(0)
				stop()
				expect((textRule:isDestroyed())):toBe(true)
				expect((surfaceRule:isDestroyed())):toBe(true)
				selection:set("Dark")
				expect((engineLib.connections(engine.heartbeat))):toBe(0)
				runtime:dispose()
			end,
		})

		it("adds and removes native rules through Compose while shallow-frozen packages stay reactive", {
			id = "native_themes_media::native themes and media::adds and removes native rules through Compose while shallow-frozen packages stay reactive",
			run = function()
				local engine, runtime = setup()
				local package: FixtureThemeTypes.ThemePackage = themes.neutralPackage()
				local contributed: FixtureThemeTypes.AuthoredRuleProperties = { BackgroundTransparency = 0.25 }
				local rules: { FixtureThemeTypes.Rule } = {}
				package.rules = rules
				table.freeze(package)
				local revision = Compose.cell(0)
				local stop, sheet: any = runtime.mount(function()
					return (themes.createStyleSheet :: any)(runtime, function(use: Use)
						use(revision)
						return package
					end, { types = engine.types })
				end, engine.new("Folder"))
				local initial = sheet:GetChildren()
				table.insert(rules, { selector = ".game-added", properties = contributed })
				revision:set(1)
				expect(#sheet:GetChildren()):toBe(#initial + 1)
				local added = sheet:GetChildren()[#initial + 1]
				expect(added.Selector):toBe(".game-added")
				expect(added:GetProperties().BackgroundTransparency):toBe(0.25)
				expect(transitionOf(added, "BackgroundTransparency").Time):toBeFloat32(0.2)
				contributed.BackgroundTransparency = 0.75
				revision:set(2)
				expect(added:GetProperties().BackgroundTransparency):toBe(0.75)
				expect(sheet:GetChildren()[#initial + 1]):toBe(added)
				table.clear(rules)
				revision:set(3)
				expect((added:isDestroyed())):toBe(true)
				expect(#sheet:GetChildren()):toBe(#initial)
				for index, rule in initial do
					expect(sheet:GetChildren()[index]):toBe(rule)
				end
				stop()
				for _, rule in initial do
					expect((rule:isDestroyed())):toBe(true)
				end
				runtime:dispose()
			end,
		})

		it("keeps theme skin layers and state asset swaps inside native Compose ownership", {
			id = "native_themes_media::native themes and media::keeps theme skin layers and state asset swaps inside native Compose ownership",
			run = function()
				local engine, runtime = setup()
				local package = themes.neutralPackage()
				package.assets = {
					rest = { content = "rbxassetid://1", sliceCenter = { x0 = 4, y0 = 4, x1 = 20, y1 = 20 } },
					pressed = { content = "rbxassetid://2" },
					corner = { content = "rbxassetid://3" },
				}
				assert(package.chrome).control = {
					kind = "layered" :: "layered",
					layers = {
						{ kind = "fill" :: "fill", asset = { default = "rest", pressed = "pressed" } } :: FixtureThemeTypes.SkinLayer,
						{
							kind = "corners" :: "corners",
							asset = "corner",
							topLeft = "corner",
							topRight = "corner",
							size = 12,
						} :: FixtureThemeTypes.SkinLayer,
					},
				}
				local state = Compose.cell("default" :: FixtureThemeTypes.SkinState)
				local stop, node: any = runtime.mount(function()
					return themes.skin(runtime, package, "control", { types = engine.types, state = state })
				end, engine.new("Folder"))
				expect(#node:GetChildren()):toBe(5)
				expect(node:FindFirstChild("control2bottomRight").Image):toBe("rbxassetid://3")
				local image = node:FindFirstChild("control1")
				expect(image.Image):toBe("rbxassetid://1")
				expect(image.ScaleType):toBe(engine.types.Enum.ScaleType.Slice)
				state:set("pressed")
				expect(image.Image):toBe("rbxassetid://2")
				expect(image.ScaleType):toBe(engine.types.Enum.ScaleType.Stretch)
				stop()
				expect((image:isDestroyed())):toBe(true)
				runtime:dispose()
			end,
		})

		it("shares caller resources directly through Compose and releases the final reference", {
			id = "native_themes_media::native themes and media::shares caller resources directly through Compose and releases the final reference",
			run = function()
				local engine, runtime, UI = setup()
				local acquired, released = 0, 0
				local resource = Compose.createSharedResource(function(): (FixtureMediaTypes.ImageResource, (() -> ())?)
					acquired += 1
					local image: FixtureMediaTypes.ImageResource = {
						state = Compose.cell("ready" :: "loading" | "ready" | "failed"),
						value = Compose.cell("rbxassetid://7"),
					}
					return image, function()
						released += 1
					end
				end)
				local first: any = runtime.mount(function()
					return UI.AsyncImage {
						resource = function()
							return resource()
						end,
					}
				end, engine.new("Folder"))
				local second = runtime.mount(function()
					return UI.AsyncImage {
						resource = function()
							return resource()
						end,
					}
				end, engine.new("Folder"))
				expect(acquired):toBe(1)
				first()
				expect(released):toBe(0)
				second()
				expect(released):toBe(1)
				runtime:dispose()
			end,
		})

		it("keeps async completions stale after a source change or disposal", {
			id = "native_themes_media::native themes and media::keeps async completions stale after a source change or disposal",
			run = function()
				local engine, runtime, UI = setup()
				local source, requests, states = Compose.cell("first" :: string?), {}, {}
				local cancellations = 0
				local stop, root: any = runtime.mount(function()
					return UI.AsyncImage {
						source = source,
						loader = function(content, resolve, reject)
							requests[content] = { resolve = resolve, reject = reject }
							return function()
								cancellations += 1
							end
						end,
						onStatus = function(status)
							table.insert(states, status)
						end,
					}
				end, engine.new("Folder"))
				source:set("second")
				requests.first.resolve("wrong")
				expect(root:FindFirstChild("Image").Visible):toBe(false)
				requests.second.resolve("right")
				expect(root:FindFirstChild("Image").Image):toBe("right")
				expect(root:FindFirstChild("Image").Visible):toBe(true)
				stop()
				local count = #states
				requests.second.reject("late")
				expect(#states):toBe(count)
				expect(cancellations):toBe(2)
				runtime:dispose()
			end,
		})

		it("clamps progress, counts badges and releases stage scenes with Compose", {
			id = "native_themes_media::native themes and media::clamps progress, counts badges and releases stage scenes with Compose",
			run = function()
				local engine, runtime, UI = setup()
				local progress = Compose.cell(0.25)
				local count = Compose.cell(120 :: number?)
				local stage: ViewportFrame? = nil
				local bar: Frame? = nil
				local badge: TextLabel? = nil
				local released = 0
				local stop = runtime.mount(function()
					bar = UI.ProgressView { value = progress }
					badge = UI.StatusIndicator { count = count, status = "success" :: "success" }
					stage = UI.Stage {
						content = function(sceneRuntime: FixtureComposeTypes.Runtime, world: WorldModel): (() -> ())?
							local Host = Facet.host(sceneRuntime)
							Host.Part "Direct" {
								Parent = Compose.static(world),
							}
							local stop = sceneRuntime.mount(function(): Part
								return Host.Part "Model" {}
							end, world)
							return stop
						end,
					}
					Compose.cleanup(function()
						released += 1
					end)
					return Facet.host(runtime).Frame({
						bar,
						badge,
						stage,
					})
				end, engine.new("Folder"))
				local stage, bar, badge = assert(stage), assert(bar), assert(badge)
				expect((bar:FindFirstChild("Fill1", true) :: any).Size.X.Scale):toBe(0.25)
				progress:set(2)
				expect((bar:FindFirstChild("Fill1", true) :: any).Size.X.Scale):toBe(1)
				expect(badge.Text):toBe("99+")
				expect(badge.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.XY)
				expect(assert(badge:FindFirstChildWhichIsA("UISizeConstraint")).MinSize.X):toBe(24)
				expect((badge:FindFirstChildWhichIsA("UIAspectRatioConstraint"))):toBe(nil)
				count:set(3)
				expect(badge.Text):toBe("3")
				local model: any = stage:FindFirstChild("Model", true)
				expect(model.ClassName):toBe("Part")
				local direct = assert(stage:FindFirstChild("Direct", true))
				expect(direct.Parent):toBe(model.Parent)
				stop()
				expect(direct.Parent):toBe(nil)
				expect((model:isDestroyed())):toBe(true)
				expect(released):toBe(1)
				runtime:dispose()
			end,
		})
		it("preserves avatar initials presence rung changes and keyed roster identity", {
			id = "native_themes_media::native themes and media::preserves avatar initials presence rung changes and keyed roster identity",
			run = function()
				local engine, runtime, UI = setup()
				local rung: FixtureComposeTypes.Value<"compact" | "large" | "regular" | "xsmall">, presence =
					Compose.cell("compact" :: "compact" | "large" | "regular" | "xsmall"),
					Compose.cell("online" :: ("away" | "busy" | "inExperience" | "offline" | "online")?)
				local members: { FixtureMediaTypes.AvatarMember } = {
					{ id = "a", name = "Émile Noël" },
					{ id = "b", name = "Bo Lane" },
					{ id = "c", name = "Ada Quill" },
				}
				local roster = Compose.cell(members)
				local avatar: TextButton? = nil
				local group: Frame? = nil
				local selected = 0
				local stop = runtime.mount(function()
					avatar = UI.Avatar { name = "Émile Noël", presence = presence, controlSize = rung }
					group = UI.AvatarGroup {
						items = roster,
						max = 2,
						onOverflow = function()
							selected += 1
						end,
					}
					return Facet.host(runtime).Frame({ avatar, group })
				end, engine.new("Folder"))
				local avatar, group = assert(avatar), assert(group)
				expect((avatar:FindFirstChild("Initials") :: any).Text):toBe("ÉN")
				expect(avatar.Size.X.Offset):toBe(36)
				expect(
					((avatar:FindFirstChild("Initials") :: any):FindFirstChildWhichIsA("UITextSizeConstraint") :: any).MaxTextSize
				):toBe(14)
				expect(avatar.Selectable):toBe(false)
				presence:set("busy")
				rung:set("large")
				expect((avatar:GetAttribute("AccessibleLabel"))):toBe("Émile Noël, busy")
				expect(avatar.Size.X.Offset):toBe(56)
				expect(
					((avatar:FindFirstChild("Initials") :: any):FindFirstChildWhichIsA("UITextSizeConstraint") :: any).MaxTextSize
				):toBe(22)
				expect((avatar:FindFirstChild("Presence") :: any):HasTag("facet-status-error") :: any):toBe(true)
				expect((group:HasTag("facet-avatar-stack"))):toBe(true)
				local first: any = group:FindFirstChild("a")
				roster:set({
					{ id = "b", name = "Bo Lane" },
					{ id = "a", name = "Émile Changed" },
					{ id = "c", name = "Ada Quill" },
				})
				expect((group:FindFirstChild("a"))):toBe(first)
				expect((first:FindFirstChild("Initials") :: any).Text):toBe("ÉC")
				expect(first.LayoutOrder):toBe(2)
				local overflow: any = group:FindFirstChild("Overflow")
				expect(overflow.Text):toBe("+1")
				overflow.Activated:Fire()
				expect(selected):toBe(1)
				stop()
				runtime:dispose()
			end,
		})

		it("animates skeletons with one shared Compose clock and honors reduced motion", {
			id = "native_themes_media::native themes and media::animates skeletons with one shared Compose clock and honors reduced motion",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local reduced = Compose.cell(false)
				local UI = media(context(Compose, runtime, {
					types = engine.types,
					motionLevel = (Compose.formula(function(use: Use): "normal" | "limited" | "none"
						return if use(reduced) then "none" else "normal"
					end) :: unknown) :: MotionLevel,
				}))
				local first: any, one: any = runtime.mount(function()
					return UI.Skeleton { form = "line" :: "line", lines = 3 }
				end, engine.new("Folder"))
				local listeners = engineLib.connections(engine.heartbeat)
				local second, two: any = runtime.mount(function()
					return UI.Skeleton { form = "circle" :: "circle" }
				end, engine.new("Folder"))
				expect((engineLib.connections(engine.heartbeat))):toBe(listeners)
				expect(one:FindFirstChild("Placeholder3").Size.X.Scale):toBeCloseTo(0.6, 1e-4)
				engine.heartbeat:Fire(0.4)
				local gradient = two:FindFirstChild("Shimmer", true)
				local previous = gradient.Offset.X
				first()
				engine.heartbeat:Fire(0.2)
				expect(gradient.Offset.X > previous):toBe(true)
				reduced:set(true)
				expect(gradient.Enabled):toBe(false)
				previous = gradient.Offset.X
				engine.heartbeat:Fire(0.3)
				expect(gradient.Offset.X):toBe(previous)
				reduced:set(false)
				engine.heartbeat:Fire(0.2)
				expect(gradient.Enabled):toBe(true)
				expect(gradient.Offset.X ~= previous):toBe(true)
				second()
				runtime:dispose()
				expect((engineLib.connections(engine.heartbeat))):toBe(0)
			end,
		})

		it("keeps indeterminate progress stepping and trails determinate decreases", {
			id = "native_themes_media::native themes and media::keeps indeterminate progress stepping and trails determinate decreases",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local UI = media(context(Compose, runtime, { types = engine.types, motionLevel = "none" }))
				local value = Compose.cell(0.8)
				local bar: Frame? = nil
				local busy: Frame? = nil
				local stop = runtime.mount(function()
					bar = UI.ProgressView { value = value, trail = { delay = 0.2, duration = 0.4 } }
					busy = UI.ProgressView { presentation = "spinner" :: "spinner" }
					return Facet.host(runtime).Frame({ bar, busy })
				end, engine.new("Folder"))
				local bar, busy = assert(bar), assert(busy)
				local dot: any = busy:FindFirstChild("Segment1", true)
				local before = dot.BackgroundTransparency
				engine.heartbeat:Fire(0.1)
				expect(dot.BackgroundTransparency):toBe(before)
				engine.heartbeat:Fire(0.2)
				expect(dot.BackgroundTransparency ~= before):toBe(true)
				value:set(0.2)
				expect((bar:FindFirstChild("Trail", true) :: any).Size.X.Scale):toBeCloseTo(0.2, 1e-4)
				stop()
				runtime:dispose()
				expect((engineLib.connections(engine.heartbeat))):toBe(0)
			end,
		})

		it("rejects malformed type roles, unknown shadow presets and unreadable selected labels", {
			id = "native_themes_media::native themes and media::rejects malformed type roles, unknown shadow presets and unreadable selected labels",
			run = function()
				local typed = themes.neutralPackage()
				local roles = (typed.metrics.typography :: unknown) :: { [string]: unknown }
				roles.body = 5
				expect((select(2, themes.define(typed))).ok):toBe(false)
				local shadowed = themes.neutralPackage()
				shadowed.chrome = { control = { kind = "native" :: "native", shadow = "floating" } }
				expect((select(2, themes.define(shadowed))).ok):toBe(false)
				local selected = themes.neutralPackage()
				local palette = selected.style.themes[1]
				palette.extra = if palette.extra then table.clone(palette.extra) else {}
				assert(selected.style.themes[1].extra).controlSelected = { r = 0.9, g = 0.9, b = 0.92 }
				expect((select(2, themes.define(selected))).ok):toBe(false)
				local valid = themes.neutralPackage()
				valid.chrome = { control = { kind = "native" :: "native", shadow = "raised" } }
				expect((select(2, themes.define(valid))).ok):toBe(true)
			end,
		})

		it("validates the dimensions and overlap of panel arrow artwork", {
			id = "native_themes_media::panel-tail-validation",
			run = function()
				for _, values in
					{
						{ 64, 64, 24, true },
						{ 0, 64, 24, false },
						{ math.huge, 64, 24, false },
						{ 64, 0, 24, false },
						{ 64, 64, 0, false },
						{ 64, 64, 65, false },
						{ 64, 64, 0 / 0, false },
						{ 32, 20, 12, true, 30 },
						{ 32, 20, 12, false, -1 },
						{ 32, 20, 12, false, math.huge },
						{ 32, 20, 12, false, 0 / 0 },
					} :: { { number | boolean } }
				do
					local package = themes.neutralPackage()
					package.assets = { arrow = { content = "rbxassetid://123" } }
					package.chrome = {
						panelTail = {
							kind = "fill",
							asset = "arrow",
							size = { w = values[1] :: number, h = values[2] :: number },
							overhang = values[3] :: number,
							margin = if type(values[5]) == "number" then values[5] else nil,
						},
					}
					expect(select(2, themes.define(package)).ok):toBe(values[4])
				end
			end,
		})

		it("keeps compiled theme data immutable and rejects callbacks or malformed values", {
			id = "native_themes_media::native themes and media::keeps compiled theme data immutable and rejects callbacks or malformed values",
			run = function()
				local definition = themes.neutralPackage()
				local package = themes.define(definition)
				expect((table.isfrozen(assert(package).metrics.typography))):toBe(true)
				definition.metrics.typography.body.size = 23
				expect(assert(package).metrics.typography.body.size):toBe(16)
				local malformedDefinition = definition :: any
				malformedDefinition.rules = {
					{
						selector = ".bad",
						properties = {
							Text = function()
								return "not data"
							end,
						},
					},
				}
				expect(select(2, themes.define(definition)).ok):toBe(false)
				expect(select(2, themes.define(false :: any)).ok):toBe(false)
			end,
		})

		it("preserves external cameras and forwards native viewport lighting", {
			id = "native_themes_media::native themes and media::preserves external cameras and forwards native viewport lighting",
			run = function()
				local engine, runtime, UI = setup()
				local camera = engine.new("Camera")
				local original = engine.new("Folder")
				camera.Parent = original
				local ambient = engine.types.Color3.new(0.2, 0.3, 0.4)
				local stop, stage: any = runtime.mount(function()
					return UI.Stage {
						camera = camera,
						Ambient = ambient,
						LightDirection = engine.types.Vector3.new(1, -1, 0),
					}
				end, engine.new("Folder"))
				expect(stage.CurrentCamera):toBe(camera)
				expect(stage.Ambient):toBe(ambient)
				expect(camera.Parent):toBe(original)
				stop()
				expect((camera:isDestroyed())):toBe(false)
				runtime:dispose()
			end,
		})

		it("preserves accessible media names native constraints and caller resource sharing", {
			id = "native_themes_media::native themes and media::preserves accessible media names native constraints and caller resource sharing",
			run = function()
				local engine, runtime, UI = setup()
				local loaded, released, activated = 0, 0, 0
				local resource = Compose.createSharedResource(function(): (FixtureMediaTypes.ImageResource, (() -> ())?)
					loaded += 1
					local image: FixtureMediaTypes.ImageResource = {
						state = Compose.cell("ready" :: "loading" | "ready" | "failed"),
						value = Compose.cell("rbxassetid://21" :: string?),
					}
					return image, function()
						released += 1
					end
				end)
				local avatar: any, group: any, badge: any, mark: any
				local stop = runtime.mount(function()
					avatar = UI.Avatar {
						name = "Ada",
						presence = "online" :: "online",
						presenceLabel = "Disponible",
						diameter = 52,
						onActivate = function()
							activated += 1
						end,
					}
					group = UI.AvatarGroup {
						items = {
							{
								id = "a",
								name = "Ada",
								resource = function()
									return resource()
								end,
							} :: FixtureMediaTypes.AvatarMember,
							{
								id = "b",
								name = "Bo",
								resource = function()
									return resource()
								end,
							} :: FixtureMediaTypes.AvatarMember,
							{ id = "c", name = "Cleo" } :: FixtureMediaTypes.AvatarMember,
						},
						max = 2,
						overflow = "ellipsis" :: "ellipsis",
						overflowLabel = "Otra persona",
					}
					badge = UI.Badge { icon = "checkmark", name = "Verified" }
					mark = UI.StatusIndicator {
						form = "dash" :: "dash",
						cutout = true,
						Size = engine.types.UDim2.fromOffset(80, 12),
					}
					return Facet.host(runtime).Frame({
						avatar,
						group,
						badge,
						mark,
					})
				end, engine.new("Folder"))
				expect((avatar:GetAttribute("AccessibleLabel"))):toBe("Ada, Disponible")
				expect(avatar.Size.X.Offset):toBe(52)
				expect(avatar.Selectable):toBe(true)
				avatar.Activated:Fire()
				expect(activated):toBe(1)
				expect((group:FindFirstChild("Overflow") :: any):GetAttribute("AccessibleLabel") :: any):toBe(
					"Otra persona"
				)
				expect((group:FindFirstChild("Overflow") :: any).Text):toBe("…")
				expect(loaded):toBe(1)
				expect(((group:FindFirstChild("a") :: any):FindFirstChild("Initials") :: any).Visible):toBe(false)
				expect((avatar:FindFirstChild("Initials") :: any).Visible):toBe(true)
				expect((badge:FindFirstChildWhichIsA("TextLabel"):GetAttribute("AccessibleLabel"))):toBe("Verified")
				expect((badge:HasTag("facet-badge"))):toBe(true)
				expect((badge:FindFirstChildWhichIsA("TextLabel"):HasTag("facet-badge"))):toBe(false)
				expect(badge:FindFirstChildWhichIsA("UIListLayout").VerticalAlignment):toBe(
					engine.types.Enum.VerticalAlignment.Center
				)
				local constraint = mark:FindFirstChildWhichIsA("UIAspectRatioConstraint")
				expect(constraint.AspectRatio):toBe(3)
				expect(constraint.AspectType):toBe(engine.types.Enum.AspectType.FitWithinMaxSize)
				expect((mark:FindFirstChild("Cutout") :: any).BorderStrokePosition):toBe(
					engine.types.Enum.BorderStrokePosition.Inner
				)
				stop()
				expect(released):toBe(1)
				runtime:dispose()
			end,
		})

		it("rejects malformed media policy and retains valid reactive captions", {
			id = "native_themes_media::native themes and media::rejects malformed media policy and retains valid reactive captions",
			run = function()
				local builders: { (media.MediaControls) -> GuiObject } = {
					function(UI: media.MediaControls): GuiObject
						return UI.Badge({ label = 3 } :: any)
					end,
					function(UI: media.MediaControls): GuiObject
						return UI.Badge { icon = "checkmark" }
					end,
					function(UI: media.MediaControls): GuiObject
						return UI.AvatarGroup({ items = {}, overflow = "unexpected" } :: any)
					end,
					function(UI: media.MediaControls): GuiObject
						return UI.AvatarGroup { items = { { id = "a", name = "A" }, { id = "a", name = "B" } } }
					end,
					function(UI: media.MediaControls): GuiObject
						return UI.StatusIndicator { count = 1, max = -1 }
					end,
				}
				for _, build in builders do
					local engine, runtime, UI = setup()
					local ok = pcall(function()
						runtime.mount(function()
							return build(UI)
						end, engine.new("Folder"))
					end)
					expect(ok):toBe(false)
					runtime:dispose()
				end
				local engine, runtime, UI = setup()
				local caption = Compose.cell("Ready")
				local stop, badge: any = runtime.mount(function()
					return UI.Badge { label = caption }
				end, engine.new("Folder"))
				expect((pcall(function()
					caption:set(3 :: any)
				end))):toBe(false)
				caption:set("Recovered")
				expect(badge.Text):toBe("Recovered")
				stop()
				runtime:dispose()
			end,
		})

		it("hides a Badge while its bound label is empty and refuses a fixed empty label", {
			id = "native_themes_media::native themes and media::hides a Badge while its bound label is empty and refuses a fixed empty label",
			run = function()
				local function refused(spec: FixtureMediaProps.BadgeProps): boolean
					local engine, runtime, UI = setup()
					local ok = pcall(function()
						runtime.mount(function()
							return UI.Badge(spec)
						end, engine.new("Folder"))
					end)
					runtime:dispose()
					return not ok
				end
				expect(refused({ label = "" })):toBe(true)
				expect(refused({})):toBe(true)
				expect(refused({ icon = "checkmark", label = "" })):toBe(true)
				expect(refused({ label = "New" })):toBe(false)
				local engine, runtime, UI = setup()
				local caption = Compose.cell(nil :: string?)
				local shown = Compose.cell(true)
				local sale: GuiObject?, owned: GuiObject?, verified: GuiObject?
				local stop = runtime.mount(function()
					sale = UI.Badge { label = caption, Visible = shown }
					owned = UI.Badge {
						label = function(): string?
							return nil
						end,
					}
					verified = UI.Badge { icon = "checkmark", name = "Verified", label = caption }
					return Facet.host(runtime).Frame({
						sale,
						owned,
						verified,
					})
				end, engine.new("Folder"))
				local badge, empty, named = assert(sale), assert(owned), assert(verified)
				expect(badge.Visible):toBe(false)
				expect(empty.Visible):toBe(false)
				expect(named.Visible):toBe(true)
				caption:set("Sale")
				expect(badge.Visible):toBe(true)
				expect((badge :: TextLabel).Text):toBe("Sale")
				shown:set(false)
				expect(badge.Visible):toBe(false)
				shown:set(true)
				caption:set("")
				expect(badge.Visible):toBe(false)
				expect(named.Visible):toBe(true)
				stop()
				runtime:dispose()
			end,
		})

		it("preserves full size progress art endcaps centers and fill direction", {
			id = "native_themes_media::native themes and media::preserves full size progress art endcaps centers and fill direction",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local package = themes.neutralPackage()
				package.assets = {
					fill = { content = "rbxassetid://1" },
					start = { content = "rbxassetid://2" },
					finish = { content = "rbxassetid://3" },
					center = { content = "rbxassetid://4" },
				}
				assert(package.chrome).barFill =
					{ kind = "nineSlice" :: "nineSlice", asset = "fill", direction = "rtl" :: "rtl" }
				assert(package.chrome).barCap = {
					kind = "nineSlice" :: "nineSlice",
					startAsset = "start",
					endAsset = "finish",
					size = { w = 28, h = 36 },
				}
				assert(package.chrome).barCenter =
					{ kind = "nineSlice" :: "nineSlice", asset = "center", size = { w = 36, h = 28 } }
				local selected = themeState(package)
				local UI = media(context(Compose, runtime, { types = engine.types, theme = selected }))
				local value = Compose.cell(0.25)
				local stop, root: any = runtime.mount(function()
					return UI.ProgressView { value = value, thickness = 36 }
				end, engine.new("Folder"))
				local fill = root:FindFirstChild("Fill1", true)
				expect(fill.AnchorPoint.X):toBe(1)
				expect(fill.Size.X.Scale):toBe(0.25)
				engine.environment.poke(fill, "AbsoluteSize", engine.types.Vector2.new(25, 6))
				engine.environment.poke(
					fill:FindFirstChild("SkinBoundary"),
					"AbsoluteSize",
					engine.types.Vector2.new(1, 1)
				)
				expect(fill:FindFirstChild("SkinBoundary").Size):toBe(engine.types.UDim2.fromOffset(1, 1))
				expect(fill:FindFirstChild("Skin", true).Size.X.Scale):toBe(4)
				expect(fill:FindFirstChild("SkinBounds", true).Size.X.Offset):toBe(25)
				expect(root:FindFirstChild("barCap-start", true).Position.X.Scale):toBe(1)
				expect(root:FindFirstChild("barCap-end", true).Image):toBe("rbxassetid://3")
				expect(root:FindFirstChild("barCenter", true).Size.X.Offset):toBe(36)
				value:set(0.5)
				engine.environment.poke(fill, "AbsoluteSize", engine.types.Vector2.new(50, 6))
				expect(fill:FindFirstChild("Skin", true).Size.X.Scale):toBe(2)
				expect(fill:FindFirstChild("SkinBounds", true).Size.X.Offset):toBe(50)
				local nextPackage = table.clone(package)
				nextPackage.chrome = table.clone(package.chrome)
				assert(nextPackage.chrome).barFill =
					{ kind = "nineSlice" :: "nineSlice", asset = "fill", direction = "btt" :: "btt" }
				selected:set(nextPackage)
				expect(fill.AnchorPoint.Y):toBe(1)
				expect(fill.Size.Y.Scale):toBe(0.5)
				expect(root:FindFirstChild("barCap-start", true).Position.Y.Scale):toBe(1)
				stop()
				runtime:dispose()
			end,
		})
		it("sizes spanning progress fill art to the filled length so both ends of the art show", {
			id = "native_themes_media::native themes and media::sizes spanning progress fill art to the filled length so both ends of the art show",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local package = themes.neutralPackage()
				package.assets = { fill = { content = "rbxassetid://1" } }
				assert(package.chrome).barFill =
					{ kind = "nineSlice" :: "nineSlice", asset = "fill", span = "fill" :: "fill" }
				local UI = media(context(Compose, runtime, { types = engine.types, theme = package }))
				local value = Compose.cell(0.25)
				local holder = engine.new("Folder")
				local stop = runtime.mount(function()
					return UI.ProgressView { value = value, thickness = 12 }
				end, holder)
				local fill = holder:FindFirstChild("Fill1", true)
				expect(fill.Size.X.Scale):toBe(0.25)
				engine.environment.poke(fill, "AbsoluteSize", engine.types.Vector2.new(25, 6))
				engine.environment.poke(
					fill:FindFirstChild("SkinBoundary"),
					"AbsoluteSize",
					engine.types.Vector2.new(1, 1)
				)
				expect(fill:FindFirstChild("Skin", true).Size.X.Scale):toBe(1)
				expect(fill:FindFirstChild("SkinBounds", true).Size.X.Offset):toBe(25)
				value:set(0.5)
				engine.environment.poke(fill, "AbsoluteSize", engine.types.Vector2.new(50, 6))
				expect(fill:FindFirstChild("Skin", true).Size.X.Scale):toBe(1)
				expect(fill:FindFirstChild("SkinBounds", true).Size.X.Offset):toBe(50)
				stop()
				runtime:dispose()
			end,
		})
		it("applies rich native skin slots to editable fields toggles steppers and sliders", {
			id = "native_themes_media::native themes and media::applies rich native skin slots to editable fields toggles steppers and sliders",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local package = themes.neutralPackage()
				package.assets = { art = { content = "rbxassetid://30" }, selected = { content = "rbxassetid://31" } }
				local asset: FixtureThemeTypes.AssetVariants = { default = "art", selected = "selected" }
				for _, slot in
					{ "field", "toggleTrack", "toggleKnob", "stepperPlate", "sliderTrack", "sliderThumb", "barFill" }
				do
					assert(package.chrome)[slot] = { kind = "nineSlice" :: "nineSlice", asset = asset }
				end
				local UI = require("../src").controls(runtime, { types = engine.types, theme = package })
				local active = Compose.cell(false)
				local field: GuiObject? = nil
				local toggle: TextButton? = nil
				local stepper: Frame? = nil
				local slider: Frame? = nil
				local fieldProps: FixtureInputProps.TextInputCellProps = { value = Compose.cell("Ada"), label = "Name" }
				local toggleProps: FixtureInputProps.ToggleCellProps = { value = active }
				local stepperProps: FixtureInputProps.StepperCellProps = { value = Compose.cell(2), min = 0, max = 10 }
				local sliderProps: FixtureInputProps.SliderCellProps = { value = Compose.cell(0.5), min = 0, max = 1 }
				local stop = runtime.mount(function()
					field = UI.TextInput(fieldProps)
					toggle = UI.Toggle(toggleProps)
					stepper = UI.Stepper(stepperProps)
					slider = UI.Slider(sliderProps)
					return Facet.host(runtime).Frame({
						field,
						toggle,
						stepper,
						slider,
					})
				end, engine.new("Folder"))
				local field, toggle, stepper, slider = assert(field), assert(toggle), assert(stepper), assert(slider)
				local roots: { [string]: GuiObject } = {
					field = field,
					toggleTrack = toggle,
					toggleKnob = toggle,
					stepperPlate = stepper,
					sliderTrack = slider,
					sliderThumb = slider,
					barFill = slider,
				}
				for slot, root in roots do
					local image = assert(root:FindFirstChild(slot .. "1", true))
					assert(image:IsA("ImageLabel"))
					expect(image.Image):toBe("rbxassetid://30")
				end
				expect((field:FindFirstChild("Field", true) :: any).Text):toBe("Ada")
				expect((field:FindFirstChild("Input", true) :: any):HasTag("facet-skinned") :: any):toBe(true)
				active:set(true)
				expect((toggle:FindFirstChild("toggleTrack1", true) :: any).Image):toBe("rbxassetid://31")
				expect((toggle:FindFirstChild("toggleKnob1", true) :: any).Image):toBe("rbxassetid://31")
				stop()
				runtime:dispose()
			end,
		})

		it("uses native shadows with reactive theme parameters and Compose disposal", {
			id = "native_themes_media::native themes and media::uses native shadows with reactive theme parameters and Compose disposal",
			run = function()
				local engine, runtime = setup()
				local package = themes.neutralPackage()
				assert(package.chrome).control = { kind = "native" :: "native", shadow = "raised" }
				local selected = themeState(package)
				local target: TextButton? = nil
				local stop = runtime.mount(function()
					target = Facet.host(runtime).TextButton({ Text = "Play" })
					runtime.mount(function()
						return themes.skin(
							runtime,
							selected,
							"control",
							{ types = engine.types, target = target :: GuiObject }
						)
					end, target)
					return target
				end, engine.new("Folder"))
				local target = assert(target)
				local shadow = target:FindFirstChild("ChromeShadow") :: FixtureShadow
				expect(shadow.ClassName):toBe("UIShadow")
				expect(shadow.BlurRadius.Offset):toBe(14)
				expect(shadow.Offset.Y.Offset):toBe(3)
				local nextPackage = themes.neutralPackage()
				assert(nextPackage.chrome).control = {
					kind = "native" :: "native",
					shadow = {
						blurRadius = { offset = 16 },
						transparency = 0.28,
						color = { r = 0.05, g = 0.42, b = 0.5 },
					},
				}
				selected:set(nextPackage)
				expect((target:FindFirstChild("ChromeShadow"))):toBe(shadow)
				expect(shadow.BlurRadius.Offset):toBe(16)
				expect(shadow.Transparency):toBe(0.28)
				selected:set(themes.neutralPackage())
				expect(shadow.Enabled):toBe(false)
				selected:set(nextPackage)
				expect((target:FindFirstChild("ChromeShadow"))):toBe(shadow)
				expect(shadow.Enabled):toBe(true)
				stop()
				expect((shadow:isDestroyed())):toBe(true)
				runtime:dispose()
			end,
		})
		it("defers reactive control decoration until a theme needs it", {
			id = "native_themes_media::native themes and media::defers reactive control decoration until a theme needs it",
			run = function()
				local engine, runtime = setup()
				local selected = themeState(themes.neutralPackage())
				local ctx = context(Compose, runtime, { types = engine.types, theme = selected })
				local stop, target = runtime.mount(function()
					local node = ctx.Host.Frame { Size = engine.types.UDim2.fromOffset(200, 44) }
					ctx.skin(node, "control")
					return node
				end, engine.new("Folder"))
				local node = target :: Frame
				expect(#node:GetDescendants()):toBe(2)
				expect(node:FindFirstChildWhichIsA("UIPadding") ~= nil):toBe(true)
				expect(node:FindFirstChild("SkinBoundary", true)):toBeNil()
				local art = themes.neutralPackage()
				assert(art.assets).image = { content = "rbxassetid://30" }
				assert(art.chrome).control = { kind = "nineSlice" :: "nineSlice", asset = "image", shadow = "raised" }
				selected:set(art)
				local image = assert(node:FindFirstChild("control1", true)) :: ImageLabel
				expect(image.Image):toBe("rbxassetid://30")
				expect(node:FindFirstChild("ChromeShadow") ~= nil):toBe(true)
				selected:set(themes.neutralPackage())
				expect(image.Visible):toBe(false)
				selected:set(art)
				expect(node:FindFirstChild("control1", true)):toBe(image)
				expect(image.Visible):toBe(true)
				stop()
				expect(node.Parent):toBeNil()
				runtime:dispose()
			end,
		})
		it("skips static empty skin graphs while retaining later reactive art and shadows", {
			id = "native_themes_media::native themes and media::skips static empty skin graphs while retaining later reactive art and shadows",
			run = function()
				local engine, runtime = setup()
				Compose.setWorkCounters(true)
				Compose.resetWorkCounters()
				local stop, root: any = runtime.mount(function()
					return themes.skin(runtime, nil, "control", { types = engine.types })
				end, engine.new("Folder"))
				local counters = Compose.readWorkCounters()
				Compose.setWorkCounters(false)
				expect(counters.watchRuns):toBe(0)
				expect(counters.formulaRecomputations):toBe(0)
				expect(#root:GetChildren()):toBe(0)
				stop()
				local static = themes.neutralPackage()
				assert(static.chrome).control = { kind = "native" :: "native", shadow = "raised" }
				Compose.setWorkCounters(true)
				Compose.resetWorkCounters()
				stop, root = runtime.mount(function()
					return themes.skin(runtime, static, "control", { types = engine.types })
				end, engine.new("Folder"))
				counters = Compose.readWorkCounters()
				Compose.setWorkCounters(false)
				expect(counters.watchRuns):toBe(0)
				expect(counters.formulaRecomputations):toBe(0)
				expect(root:FindFirstChild("ChromeShadow").BlurRadius.Offset):toBe(14)
				stop()
				local selected = themeState(themes.neutralPackage())
				stop, root = runtime.mount(function()
					return themes.skin(runtime, selected, "control", { types = engine.types })
				end, engine.new("Folder"))
				expect(#root:GetChildren()):toBe(0)
				local art = themes.neutralPackage()
				assert(art.assets).image = { content = "rbxassetid://30" }
				assert(art.chrome).control = { kind = "nineSlice" :: "nineSlice", asset = "image", shadow = "raised" }
				selected:set(art)
				expect(root:FindFirstChild("control1").Image):toBe("rbxassetid://30")
				expect(root:FindFirstChild("ChromeShadow") ~= nil):toBe(true)
				selected:set(themes.neutralPackage())
				expect(#root:GetChildren()):toBe(2)
				expect(root:FindFirstChild("control1").Visible):toBe(false)
				expect(root:FindFirstChild("ChromeShadow").Enabled):toBe(false)
				stop()
				runtime:dispose()
			end,
		})

		it("preloads the Compose owned ImageLabel after its source binding settles", {
			id = "native_themes_media::native themes and media::preloads the Compose owned ImageLabel after its source binding settles",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local loader: unknown = require("../src/ui/media_async_image")
				assert(type(loader) == "function")
				local environment: { task: { defer: (() -> ()) -> thread, cancel: (thread) -> () } } = getfenv(loader)
				local originalTask = environment.task
				local pending: { thread } = {}
				environment.task = {
					defer = function(callback: () -> ()): thread
						local thread = coroutine.create(callback)
						table.insert(pending, thread)
						return thread
					end,
					cancel = function(thread: thread)
						coroutine.close(thread)
					end,
				}
				local preloaded: { { read Image: string } } = {}
				local UI = media(context(Compose, runtime, {
					types = engine.types,
					services = {
						ContentProvider = {
							PreloadAsync = function(_, instances, callback: (string, any) -> ())
								table.insert(preloaded, instances[1])
								callback(instances[1].Image, engine.types.Enum.AssetFetchStatus.Success)
							end,
						} :: any,
					},
				}))
				local source = Compose.cell("rbxassetid://10" :: string?)
				local stop, root: any = runtime.mount(function()
					return UI.AsyncImage { source = source }
				end, engine.new("Folder"))
				expect(#preloaded):toBe(0)
				expect((coroutine.resume(pending[1]))):toBe(true)
				local image = root:FindFirstChild("Image")
				expect(preloaded[1]):toBe(image)
				expect(image.Image):toBe("rbxassetid://10")
				expect(image.Visible):toBe(true)
				source:set("rbxassetid://20")
				expect((coroutine.resume(pending[2]))):toBe(true)
				expect(preloaded[2]):toBe(image)
				expect(image.Image):toBe("rbxassetid://20")
				stop()
				expect((image:isDestroyed())):toBe(true)
				environment.task = originalTask
				runtime:dispose()
			end,
		})

		it("holds damage trails then settles and snaps immediately on healing", {
			id = "native_themes_media::native themes and media::holds damage trails then settles and snaps immediately on healing",
			run = function()
				local engine, runtime, UI = setup()
				local value = Compose.cell(1)
				local stop, meter: any = runtime.mount(function()
					return UI.ProgressView { value = value, trail = { delay = 0.2, duration = 0.3 } }
				end, engine.new("Folder"))
				local trail = meter:FindFirstChild("Trail", true)
				value:set(0.5)
				engine.heartbeat:Fire(0.1)
				expect(trail.Size.X.Scale):toBe(1)
				engine.heartbeat:Fire(0.25)
				expect(trail.Size.X.Scale):toBeCloseTo(0.75, 1e-4)
				engine.heartbeat:Fire(0.2)
				expect(trail.Size.X.Scale):toBeCloseTo(0.5, 1e-4)
				expect((engineLib.connections(engine.heartbeat))):toBe(0)
				value:set(0.25)
				value:set(0.4)
				expect(trail.Size.X.Scale):toBeCloseTo(0.4, 1e-4)
				expect((engineLib.connections(engine.heartbeat))):toBe(0)
				value:set(0.1)
				engine.heartbeat:Fire(0.35)
				expect(trail.Size.X.Scale):toBeCloseTo(0.25, 1e-4)
				value:set(0.2)
				expect(trail.Size.X.Scale):toBeCloseTo(0.2, 1e-4)
				stop()
				runtime:dispose()
			end,
		})

		it("centers circular readouts when native text bounds fit the ring", {
			id = "native_themes_media::native themes and media::centers circular readouts when native text bounds fit the ring",
			run = function()
				local engine, runtime, UI = setup()
				local value = Compose.cell(0.75)
				local stop, meter: any = runtime.mount(function()
					return UI.ProgressView {
						value = value,
						presentation = "circular" :: "circular",
						diameter = 120,
						showValue = true,
					}
				end, engine.new("Folder"))
				local readout, gauge = meter:FindFirstChild("Value", true), meter:FindFirstChild("Gauge", true)
				engine.environment.poke(readout, "TextBounds", engine.types.Vector2.new(38, 20))
				expect(readout.Text):toBe("75%")
				expect(readout.Parent):toBe(gauge)
				expect(readout.Position):toBe(engine.types.UDim2.new(0.5, 0, 0, 60))
				expect(readout.AnchorPoint):toBe(engine.types.Vector2.new(0.5, 0.5))
				expect(gauge.Size):toBe(engine.types.UDim2.fromOffset(120, 120))
				expect(gauge.ClipsDescendants):toBe(false)
				value:set(1)
				expect(readout.Text):toBe("100%")
				stop()
				runtime:dispose()
			end,
		})

		it("keeps the value and end label of an unlabelled bar on the bar's row", {
			id = "native_themes_media::native themes and media::keeps the value and end label of an unlabelled bar on the bar's row",
			run = function()
				local engine, runtime, UI = setup()
				local stop, meter = runtime.mount(function()
					return UI.ProgressView { value = 0.4, showValue = true, endLabel = "mowed" }
				end, engine.new("Folder"))
				local root = meter :: Instance
				local line, track = root:FindFirstChild("Line"), root:FindFirstChild("Track", true)
				expect(line ~= nil):toBe(true)
				local row = line :: Instance
				local bar = track :: Instance
				expect(bar.Parent):toBe(row)
				local flex = bar:FindFirstChildWhichIsA("UIFlexItem") :: UIFlexItem
				expect(flex.FlexMode):toBe(engine.types.Enum.UIFlexMode.Fill)
				expect((root:FindFirstChild("Value", true) :: Instance).Parent):toBe(row)
				expect((root:FindFirstChild("EndLabel", true) :: Instance).Parent):toBe(row)
				local layout = row:FindFirstChildWhichIsA("UIListLayout") :: UIListLayout
				expect(layout.FillDirection):toBe(engine.types.Enum.FillDirection.Horizontal)
				stop()
				runtime:dispose()
			end,
		})

		it("cancels pending damage trails for reduced motion and releases their clock", {
			id = "native_themes_media::native themes and media::cancels pending damage trails for reduced motion and releases their clock",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local reduced, value = Compose.cell(false), Compose.cell(1)
				local UI = media(context(Compose, runtime, {
					types = engine.types,
					motionLevel = (Compose.formula(function(use: Use): "normal" | "limited" | "none"
						return if use(reduced) then "none" else "normal"
					end) :: unknown) :: MotionLevel,
				}))
				local stop, meter: any = runtime.mount(function()
					return UI.ProgressView { value = value, trail = { delay = 0.2, duration = 0.3 } }
				end, engine.new("Folder"))
				local trail = meter:FindFirstChild("Trail", true)
				value:set(0.4)
				expect((engineLib.connections(engine.heartbeat))):toBe(1)
				reduced:set(true)
				expect(trail.Size.X.Scale):toBeCloseTo(0.4, 1e-4)
				expect((engineLib.connections(engine.heartbeat))):toBe(0)
				reduced:set(false)
				expect(trail.Size.X.Scale):toBeCloseTo(0.4, 1e-4)
				value:set(0.2)
				expect((engineLib.connections(engine.heartbeat))):toBe(1)
				stop()
				expect((engineLib.connections(engine.heartbeat))):toBe(0)
				value:set(0.8)
				expect((trail:isDestroyed())):toBe(true)
				runtime:dispose()
			end,
		})

		it("moves oversized circular readouts below the ring using native text bounds", {
			id = "native_themes_media::native themes and media::moves oversized circular readouts below the ring using native text bounds",
			run = function()
				local engine, runtime, UI = setup()
				local stop, meter: any = runtime.mount(function()
					return UI.ProgressView {
						value = 1,
						presentation = "circular" :: "circular",
						diameter = 80,
						showValue = true,
						label = "Shield",
						format = function()
							return "10000 / 10000"
						end,
					}
				end, engine.new("Folder"))
				local readout, gauge = meter:FindFirstChild("Value", true), meter:FindFirstChild("Gauge", true)
				engine.environment.poke(readout, "TextBounds", engine.types.Vector2.new(190, 32))
				expect(readout.Text):toBe("10000 / 10000")
				expect(readout.Position):toBe(engine.types.UDim2.new(0.5, 0, 0, 88))
				expect(readout.AnchorPoint):toBe(engine.types.Vector2.new(0.5, 0))
				expect(readout.TextWrapped):toBe(false)
				expect(readout.TextXAlignment):toBe(engine.types.Enum.TextXAlignment.Center)
				expect(gauge.Size):toBe(engine.types.UDim2.fromOffset(190, 120))
				engine.environment.poke(readout, "TextBounds", engine.types.Vector2.new(40, 18))
				expect(readout.Position.Y.Offset):toBe(40)
				expect(gauge.Size):toBe(engine.types.UDim2.fromOffset(80, 80))
				stop()
				runtime:dispose()
			end,
		})

		it("rotates a smooth native circular arc with reduced motion and themed stroke colors", {
			id = "native_themes_media::native themes and media::rotates a smooth native circular arc with reduced motion and themed stroke colors",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local reduced, package = Compose.cell(false), themeState(themes.neutralPackage())
				local UI = media(context(Compose, runtime, {
					types = engine.types,
					theme = package,
					motionLevel = (Compose.formula(function(use: Use): "normal" | "limited" | "none"
						return if use(reduced) then "none" else "normal"
					end) :: unknown) :: MotionLevel,
				}))
				local sheet: any, meter: any
				local stop = runtime.mount(function()
					sheet = themes.createStyleSheet(runtime, package, { types = engine.types })
					meter = UI.ProgressView { presentation = "circular" :: "circular", diameter = 120, thickness = 4 }
					return Facet.host(runtime).Frame({ sheet, meter })
				end, engine.new("Folder"))
				local arc = meter:FindFirstChild("RingFill", true)
				expect(arc.Thickness):toBe(4)
				expect(#arc:GetControlPoints()):toBe(3)
				expect(#((meter:FindFirstChild("Indicator") :: any):GetDescendants() :: any)):toBe(2)
				local before = arc:GetControlPoints()[1].Position
				engine.heartbeat:Fire(0.1)
				expect(arc:GetControlPoints()[1].Position ~= before):toBe(true)
				reduced:set(true)
				before = arc:GetControlPoints()[1].Position
				engine.heartbeat:Fire(0.1)
				expect(arc:GetControlPoints()[1].Position):toBe(before)
				engine.heartbeat:Fire(0.1)
				expect(arc:GetControlPoints()[1].Position ~= before):toBe(true)
				local nextPackage = themes.neutralPackage()
				nextPackage.style.themes[1].colors.accent = { r = 0.7, g = 0.2, b = 0.1 }
				nextPackage.style.themes[1].colors.control = { r = 0.3, g = 0.4, b = 0.5 }
				nextPackage.style.themes[1].colors.contentSecondary = { r = 0.6, g = 0.6, b = 0.65 }
				package:set(nextPackage)
				expect(style(sheet, ".facet-progress-ring-fill").Color3):toBe(engine.types.Color3.new(0.7, 0.2, 0.1))
				expect(style(sheet, ".facet-progress-ring-track").Color3):toBe(engine.types.Color3.new(0.3, 0.4, 0.5))
				local secondary = nextPackage.style.themes[1].colors.contentSecondary
				expect(style(sheet, ".facet-type-caption").TextColor3):toBe(
					engine.types.Color3.new(secondary.r, secondary.g, secondary.b)
				)
				expect((meter:FindFirstChild("RingFill", true))):toBe(arc)
				stop()
				expect((arc:isDestroyed())):toBe(true)
				expect((engineLib.connections(engine.heartbeat))):toBe(0)
				runtime:dispose()
			end,
		})

		it("draws a gauge arc and a needle that follow the value across the sweep", {
			id = "native_themes_media::native themes and media::draws a gauge arc and a needle that follow the value across the sweep",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local package = themeState(themes.neutralPackage())
				local UI = media(context(Compose, runtime, { types = engine.types, theme = package }))
				local value = Compose.cell(0)
				local made: { sheet: StyleSheet?, meter: Instance? } = { sheet = nil, meter = nil }
				local stop = runtime.mount(function()
					made.sheet = themes.createStyleSheet(runtime, package, { types = engine.types })
					made.meter = UI.ProgressView {
						presentation = "gauge" :: "gauge",
						value = value,
						max = 100,
						sweep = 180,
						diameter = 100,
						thickness = 6,
					}
					return Facet.host(runtime).Frame({
						made.sheet,
						made.meter,
					})
				end, engine.new("Folder"))
				local meter = made.meter :: Instance
				local sheet = made.sheet :: StyleSheet
				local trackFound = meter:FindFirstChild("GaugeTrack", true)
				local fill = meter:FindFirstChild("GaugeFill", true)
				local needleFound = meter:FindFirstChild("GaugeNeedle", true)
				local hub = meter:FindFirstChild("GaugeHub", true)
				expect(trackFound ~= nil and fill ~= nil and needleFound ~= nil and hub ~= nil):toBe(true)
				local track = trackFound :: Path2D
				local needle = needleFound :: Path2D
				expect((meter:FindFirstChild("RingTrack", true))):toBe(nil)
				local function tip(): (number, number)
					local points = needle:GetControlPoints()
					local p = points[#points].Position
					return p.X.Scale, p.Y.Scale
				end
				local x0, y0 = tip()
				expect(x0 < 0.2 and math.abs(y0 - 0.5) < 0.01):toBe(true)
				value:set(50)
				local x1, y1 = tip()
				expect(math.abs(x1 - 0.5) < 0.01 and y1 < 0.2):toBe(true)
				value:set(100)
				local x2, y2 = tip()
				expect(x2 > 0.8 and math.abs(y2 - 0.5) < 0.01):toBe(true)
				local trackPoints = track:GetControlPoints()
				expect(trackPoints[1].Position.X.Scale < 0.1):toBe(true)
				expect(trackPoints[#trackPoints].Position.X.Scale > 0.9):toBe(true)
				expect(style(sheet, ".facet-progress-gauge-needle").Color3 ~= nil):toBe(true)
				stop()
				runtime:dispose()
			end,
		})

		it("refuses a needle or a sweep outside the gauge", {
			id = "native_themes_media::native themes and media::refuses a needle or a sweep outside the gauge",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local UI = media(context(Compose, runtime, { types = engine.types }))
				local function mount(build: () -> GuiObject)
					local stop = runtime.mount(build, engine.new("Folder"))
					stop()
				end
				expect(function()
					mount(function()
						return UI.ProgressView { presentation = "circular" :: "circular", value = 0.5, sweep = 180 }
					end)
				end):toThrow("sweep requires the gauge presentation")
				expect(function()
					mount(function()
						return UI.ProgressView { presentation = "gauge" :: "gauge", value = 0.5, sweep = 20 }
					end)
				end):toThrow("sweep must be")
				expect(function()
					mount(function()
						return UI.ProgressView { presentation = "gauge" :: "gauge" }
					end)
				end):toThrow("gauge requires a value")
				runtime:dispose()
			end,
		})

		it("bounds idle skin slots and disposes every retained native owner", {
			id = "native_themes_media::native themes and media::bounds idle skin slots and disposes every retained native owner",
			run = function()
				local engine, runtime = setup()
				local package = themes.neutralPackage()
				assert(package.assets).image = { content = "rbxassetid://99" }
				local layers: { FixtureThemeTypes.SkinLayer } = {}
				for _ = 1, 24 do
					table.insert(layers, { kind = "fill" :: "fill", asset = "image" })
				end
				assert(package.chrome).control = { kind = "layered" :: "layered", layers = layers }
				local selected = themeState(package)
				local stop, root: any = runtime.mount(function()
					return themes.skin(runtime, selected, "control", { types = engine.types })
				end, engine.new("Folder"))
				local initial = root:GetChildren()
				expect(#initial):toBe(24)
				selected:set(themes.neutralPackage())
				expect(#root:GetChildren()):toBe(16)
				local retained = 0
				for _, image in initial do
					if not image:isDestroyed() then
						retained += 1
						expect(image.Parent):toBe(root)
						expect(image.Visible):toBe(false)
					end
				end
				expect(retained):toBe(16)
				selected:set(package)
				local active = root:GetChildren()
				local reused = 0
				for _, image in active do
					if table.find(initial, image) then
						reused += 1
					end
					expect(image.Image):toBe("rbxassetid://99")
					expect(image.Visible):toBe(true)
				end
				expect(reused):toBe(16)
				stop()
				for _, image in initial do
					expect((image:isDestroyed())):toBe(true)
				end
				for _, image in active do
					expect((image:isDestroyed())):toBe(true)
				end
				selected:set(themes.neutralPackage())
				selected:set(package)
				runtime:dispose()
			end,
		})

		it("retains bounded skin slots across frozen recipes while mutable art stays reactive", {
			id = "native_themes_media::native themes and media::retains bounded skin slots across frozen recipes while mutable art stays reactive",
			run = function()
				local engine, runtime = setup()
				local package: FixtureThemeTypes.ThemePackage = themes.neutralPackage()
				local assets = assert(package.assets)
				local chrome = assert(package.chrome)
				assets.image = { content = "rbxassetid://99" }
				chrome.control = { kind = "fill" :: "fill", asset = "image" }
				local frozen = assert((themes.define(package)))
				local neutral = themes.neutralPackage()
				local selected, revision = themeState(frozen), Compose.cell(0)
				local stop, root: any = runtime.mount(function()
					return themes.skin(runtime, function(use: Use)
						use(revision)
						return use(selected)
					end, "control", { types = engine.types })
				end, engine.new("Folder"))
				local image = root:FindFirstChild("control1")
				for _ = 1, 50 do
					selected:set(neutral)
					expect(image.Visible):toBe(false)
					selected:set(frozen)
					expect((root:FindFirstChild("control1"))):toBe(image)
					expect(image.Visible):toBe(true)
				end
				expect(#root:GetChildren()):toBe(1)
				table.freeze(package)
				selected:set(package :: any)
				assets.image.content = "rbxassetid://100"
				chrome.control.kind = "tile" :: "tile"
				chrome.control.tileSize = { w = 11, h = 12 }
				revision:set(1)
				expect(image.Image):toBe("rbxassetid://100")
				expect(image.ScaleType):toBe(engine.types.Enum.ScaleType.Tile)
				expect(image.TileSize):toBe(engine.types.UDim2.fromOffset(11, 12))
				selected:set(frozen)
				expect(image.Image):toBe("rbxassetid://99")
				expect(image.ScaleType):toBe(engine.types.Enum.ScaleType.Stretch)
				stop()
				expect((image:isDestroyed())):toBe(true)
				runtime:dispose()
			end,
		})

		it("skin art follows a host inset that code writes, not only one a style rule writes", {
			id = "native_themes_media::native themes and media::skin art follows a host inset that code writes, not only one a style rule writes",
			run = function()
				local engine = engineLib.new({ styleOnlySignals = true })
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local decorate = require("../src/ui/native_decoration")
				local Host = Facet.host(runtime)
				local stop, host: any = runtime.mount(function()
					return Host.Frame { Name = "Panel", Host.UIPadding {} }
				end, engine.new("Folder"))
				local boundary: GuiObject? = nil
				runtime.mount(function()
					boundary = decorate(Compose, runtime, engine.types, host, Host.Frame { Name = "Skin" })
					return boundary
				end, host)
				local boundary = assert(boundary)
				engine.environment.poke(host, "AbsoluteSize", engine.types.Vector2.new(200, 100))
				engine.environment.poke(
					FixtureRoblox.assertInstance(boundary),
					"AbsoluteSize",
					engine.types.Vector2.new(1, 1)
				)
				host:FindFirstChildWhichIsA("UIPadding").PaddingRight = engine.types.UDim.new(0, 24)
				host:FindFirstChildWhichIsA("UIPadding").PaddingBottom = engine.types.UDim.new(0, 24)
				engine.environment.poke(
					FixtureRoblox.assertInstance(boundary),
					"AbsolutePosition",
					engine.types.Vector2.new(175, 75)
				)
				local bounds: any = boundary:FindFirstChild("SkinBounds")
				expect(`{bounds.Position.X.Offset} {bounds.Position.Y.Offset}`):toBe("25 25")
				stop()
				runtime:dispose()
			end,
		})

		it("skin art on a scrolling host stays pinned to the window, not the scrolled canvas", {
			id = "native_themes_media::native themes and media::skin art on a scrolling host stays pinned to the window, not the scrolled canvas",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local decorate = require("../src/ui/native_decoration")
				local Host = Facet.host(runtime)
				local stop, host: any = runtime.mount(function()
					return Host.ScrollingFrame { Name = "Surface" }
				end, engine.new("Folder"))
				local boundary: GuiObject? = nil
				runtime.mount(function()
					boundary = decorate(Compose, runtime, engine.types, host, Host.Frame { Name = "Skin" })
					return boundary
				end, host)
				local boundary = assert(boundary)
				engine.environment.poke(host, "AbsoluteSize", engine.types.Vector2.new(300, 400))
				engine.environment.poke(
					FixtureRoblox.assertInstance(boundary),
					"AbsoluteSize",
					engine.types.Vector2.new(1, 1)
				)
				host.CanvasPosition = engine.types.Vector2.new(0, 48)
				expect(`{boundary.Position.X.Offset} {boundary.Position.Y.Offset} {boundary.Position.Y.Scale}`):toBe(
					"300 448 0"
				)
				stop()
				runtime:dispose()
			end,
		})
	end)

	describe("native Avatar and AvatarGroup per-input rules", function()
		local function inputWorld(touch: boolean)
			local engine = engineLib.new()
			local runtime: ComposeRuntime = Roblox.createRuntime(engine)
			local gui, input = engine.new("GuiService"), engine.new("UserInputService")
			engine.environment.poke(input, "TouchEnabled", touch)
			engine.environment.poke(input, "MouseEnabled", not touch)
			local UI = controls(Compose, runtime, {
				types = engine.types,
				guiService = gui,
				userInputService = input,
				services = { GuiService = gui, UserInputService = input },
			})
			return engine, runtime, UI, gui
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

		it("lights only the avatar under the pointer and leaves passive faces out of input", {
			id = "native_themes_media::native Avatar and AvatarGroup per-input rules::lights only the avatar under the pointer and leaves passive faces out of input",
			run = function()
				local engine, runtime, UI = inputWorld(false)
				local screen = engine.new("ScreenGui")
				local stop = runtime.mount(function()
					return Facet.host(runtime).Frame({
						UI.Avatar "Passive" { name = "Pat Lane" },
						UI.Avatar "Ada" { name = "Ada Quill", onActivate = function() end },
						UI.Avatar "Bo" { name = "Bo Lane", onActivate = function() end },
					})
				end, screen)
				local passive, ada, bo = find(screen, "Passive"), find(screen, "Ada"), find(screen, "Bo")
				expect(passive.Interactable):toBe(false)
				expect(ada.Interactable):toBe(true)
				local adaRing, boRing = find(ada, "HoverRing"), find(bo, "HoverRing")
				expect((adaRing:HasTag("facet-avatar-hover"))):toBe(true)
				expect(adaRing.Transparency):toBe(1)
				engine.environment.poke(ada, "GuiState", engine.types.Enum.GuiState.Hover)
				expect(adaRing.Transparency):toBe(0)
				expect(boRing.Transparency):toBe(1)
				expect((find(passive, "HoverRing"))):toBe(nil)
				stop()
				runtime:dispose()
			end,
		})

		it("keeps the touch overflow chip its own whole target clear of the stacked faces", {
			id = "native_themes_media::native Avatar and AvatarGroup per-input rules::keeps the touch overflow chip its own whole target clear of the stacked faces",
			run = function()
				local engine, runtime, UI = inputWorld(true)
				local screen = engine.new("ScreenGui")
				local roster: { FixtureMediaTypes.AvatarMember } = {}
				for index = 1, 6 do
					roster[index] = { id = `p{index}`, name = `Player {index}` }
				end
				local stop = runtime.mount(function()
					return UI.AvatarGroup "Team" {
						items = roster,
						max = 3,
						controlSize = "compact" :: "compact",
						onOverflow = function() end,
					}
				end, screen)
				local group = find(screen, "Team")
				local chip, gap = group:FindFirstChild("Overflow"), group:FindFirstChild("OverflowGap")
				local padding = group:FindFirstChildWhichIsA("UIListLayout").Padding.Offset
				expect(padding < 0):toBe(true)
				expect(find(group, "p1").Interactable):toBe(false)
				expect(gap.LayoutOrder < chip.LayoutOrder and gap.LayoutOrder > find(group, "p3").LayoutOrder):toBe(
					true
				)
				expect(gap.Size.X.Offset + 2 * padding > 0):toBe(true)
				local floor = chip:FindFirstChildWhichIsA("UISizeConstraint")
				expect(floor.MinSize):toBe(engine.types.Vector2.new(44, 44))
				stop()
				runtime:dispose()
			end,
		})

		it("keeps a display-only touch overflow chip at the face size", {
			id = "native_themes_media::native Avatar and AvatarGroup per-input rules::keeps a display-only touch overflow chip at the face size",
			run = function()
				local engine, runtime, UI = inputWorld(true)
				local screen = engine.new("ScreenGui")
				local roster: { FixtureMediaTypes.AvatarMember } = {}
				for index = 1, 4 do
					roster[index] = { id = `p{index}`, name = `Player {index}` }
				end
				local stop = runtime.mount(function()
					return UI.AvatarGroup "Friends" {
						items = roster,
						max = 3,
						diameter = 28,
					}
				end, screen)
				local chip = find(find(screen, "Friends"), "Overflow")
				expect(chip.Selectable):toBe(false)
				expect(chip:FindFirstChildWhichIsA("UISizeConstraint").MinSize):toBe(engine.types.Vector2.new(0, 0))
				stop()
				runtime:dispose()
			end,
		})

		it("lets gamepad B pass through a selected overflow chip", {
			id = "native_themes_media::native Avatar and AvatarGroup per-input rules::lets gamepad B pass through a selected overflow chip",
			run = function()
				local engine, runtime, UI, gui = inputWorld(false)
				local screen = engine.new("ScreenGui")
				local calls = 0
				local stop = runtime.mount(function()
					return UI.AvatarGroup "Team" {
						items = {
							{ id = "a", name = "A" },
							{ id = "b", name = "B" },
							{ id = "c", name = "C" },
						} :: { AvatarMember },
						max = 1,
						onOverflow = function()
							calls += 1
						end,
					}
				end, screen)
				local chip = find(screen, "Overflow")
				gui.SelectedObject = chip
				for _, node in screen:GetDescendants() do
					if node:IsA("InputBinding") then
						expect(node.KeyCode == engine.types.Enum.KeyCode.ButtonB):toBe(false)
					end
				end
				chip.Activated:Fire()
				expect(calls):toBe(1)
				stop()
				runtime:dispose()
			end,
		})
	end);
	(function(verifyHarness: Verify.Harness)
		type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
		type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
		type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
		local ThemeTypes = require("../src/ui/theme_types")
		local FixtureNavigationTypes = require("../src/ui/navigation_types")

		local engineLib = require("./lib/native_engine")
		local Compose: ComposeModule = Facet.Compose
		local themes = Facet.themes

		type Harness = {
			engine: any,
			runtime: any,
			UI: any,
			Host: any,
			gui: any,
			dispose: () -> (),
		}

		local function harness(options: { [string]: any }?): Harness
			local engine: any = engineLib.new()
			local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
			local gui = engine.new("GuiService")
			local config: { [string]: any } =
				{ types = engine.types, guiService = gui, services = { GuiService = gui } }
			for key, value in (options or {}) :: { [string]: any } do
				config[key] = value
			end
			local UI = Facet.controls(runtime, config :: any)
			return {
				engine = engine,
				runtime = runtime,
				UI = UI,
				Host = Facet.host(runtime),
				gui = gui,
				dispose = function()
					runtime:dispose()
				end,
			}
		end

		local function mount(h: Harness, build: () -> any): (any, () -> ())
			local stop, root = h.runtime.mount(function()
				return h.Host.Frame { build() }
			end, h.engine.new("ScreenGui"))
			return root, stop
		end

		local function sheetFor(h: Harness, package: any, options: { [string]: any }?): (any, () -> ())
			local settings: { [string]: any } =
				{ types = h.engine.types, preferredTransparency = 1, motionLevel = "normal" }
			for key, value in (options or {}) :: { [string]: any } do
				settings[key] = value
			end
			local stop, sheet = h.runtime.mount(function()
				return themes.createStyleSheet(h.runtime, package, settings :: any)
			end, h.engine.new("Folder"))
			return sheet, stop
		end

		local function ruleNode(sheet: any, selector: string): any
			local found
			for _, node in sheet:GetChildren() do
				if table.find(string.split(node.Selector, ", "), selector) ~= nil then
					found = node
				end
			end
			assert(found, "No rule: " .. selector)
			return found
		end

		local function style(sheet: any, selector: string): { [string]: any }
			return styleProperties(ruleNode(sheet, selector))
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

		local function color(engine: any, value: any): any
			return engine.types.Color3.new(value.r, value.g, value.b)
		end

		local function neutralColors(): ({ [string]: any }, { [string]: any })
			local palette = themes.neutralPackage().style.themes[1]
			return palette.colors, assert(palette.extra)
		end

		local SHIPPED = {
			"classic_desktop",
			"compact_pointer",
			"fantasy_ornate",
			"fantasy_parchment",
			"glossy_mobile",
			"glossy_touch",
			"pixel_quest",
			"scifi_hud",
		}

		it("keeps every shipped typography scale readable on every device", {
			id = "native_themes_media::typography::readable shipped scales",
			run = function()
				local packages = { themes.neutralPackage() }
				for _, descriptor in
					{
						require("../examples/themes/classic_desktop"),
						require("../examples/themes/compact_pointer"),
						require("../examples/themes/fantasy_ornate"),
						require("../examples/themes/fantasy_parchment"),
						require("../examples/themes/glossy_mobile"),
						require("../examples/themes/glossy_touch"),
						require("../examples/themes/pixel_quest"),
						require("../examples/themes/scifi_hud"),
					}
				do
					table.insert(packages, (descriptor.build(themes)))
				end
				table.insert(packages, (assert((require("../examples/facet-lab/themes/foundation").build(themes)))))
				for _, package in packages do
					for _, device in { "desktop", "phone-portrait", "phone-landscape", "tablet", "console" } do
						local scaled = themes.forDistance(package, if device == "console" then "ten-foot" else "near")
						local engine = engineLib.new()
						local runtime = Roblox.createRuntime(engine)
						local preference = Compose.cell("Medium")
						context(
							Compose,
							runtime,
							{ types = engine.types, environment = { preferredTextSize = preference } }
						)
						local stop, sheet = runtime.mount(function()
							return themes.createStyleSheet(runtime, scaled, { types = engine.types })
						end, engine.new("Folder"))
						for _, role in themes.TYPE_ROLES do
							expect(scaled.metrics.typography[role].size >= 14):toBe(true)
							for _, size in { "Medium", "Large", "Larger", "Largest" } do
								preference:set(size)
								expect((style(sheet :: StyleSheet, ".facet-type-" .. role).TextSize :: number) >= 14):toBe(
									true
								)
							end
						end
						stop()
						runtime:dispose()
					end
				end
				local definition = themes.neutralPackage()
				definition.metrics.typography.caption.size = 12
				definition.metrics.typography.body.size = 15
				local resolved = assert((themes.define(definition)))
				expect(resolved.metrics.typography.caption.size):toBe(14)
				expect(resolved.metrics.typography.body.size):toBe(15)
				expect(definition.metrics.typography.caption.size):toBe(12)
			end,
		})

		local SCANNED_CALLS: { [string]: number? } = { styled = nil, paintedPart = 3 }

		local function luminance(value: any): number
			local function linear(channel: number): number
				return if channel <= 0.04045 then channel / 12.92 else ((channel + 0.055) / 1.055) ^ 2.4
			end
			return 0.2126 * linear(value.r) + 0.7152 * linear(value.g) + 0.0722 * linear(value.b)
		end

		describe("native parity paint", function()
			it("compiles the button role and appearance vocabulary to palette rules above their base states", {
				id = "native_themes_media::native parity paint::compiles the button role and appearance vocabulary to palette rules above their base states",
				run = function()
					local h = harness()
					local colors, extra = neutralColors()
					local package = themeState(themes.neutralPackage())
					local sheet, stop = sheetFor(h, package)
					local function expectColor(selector: string, property: string, value: any)
						expect(style(sheet, selector)[property]):toBe(color(h.engine, value))
					end
					expectColor(".facet-role-destructive", "BackgroundColor3", colors.danger)
					expectColor(".facet-role-destructive", "TextColor3", colors.onDanger)
					expectColor(".facet-role-destructive:Hover", "BackgroundColor3", colors.danger)
					expectColor(".facet-role-destructive:Press", "BackgroundColor3", colors.danger)
					expectColor(".facet-role-destructive >> .facet-button-caption", "TextColor3", colors.onDanger)
					expectColor(".facet-role-cancel >> .facet-button-caption", "TextColor3", extra.contentSecondary)
					expectColor(".facet-role-onIndicator >> .facet-button-caption", "TextColor3", colors.onAccent)
					expectColor(".facet-accent", "BackgroundColor3", colors.accent)
					expectColor(".facet-accent", "TextColor3", colors.onAccent)
					expectColor(".facet-accent >> .facet-button-caption", "TextColor3", colors.onAccent)
					expectColor(".facet-appearance-soft", "BackgroundColor3", colors.accent)
					expect(style(sheet, ".facet-appearance-soft").BackgroundTransparency):toBe(0.8)
					expect(style(sheet, ".facet-appearance-soft:Hover").BackgroundTransparency):toBe(0.7)
					expect(style(sheet, ".facet-appearance-soft:Press").BackgroundTransparency):toBe(0.6)
					expectColor(".facet-appearance-soft >> .facet-button-caption", "TextColor3", colors.content)
					expectColor(".facet-appearance-soft >> .facet-icon", "ImageColor3", colors.content)
					expectColor(".facet-appearance-soft >> .facet-text", "TextColor3", colors.content)
					expectColor(".facet-appearance-soft.facet-selected", "BackgroundColor3", colors.accent)
					expect(style(sheet, ".facet-appearance-soft.facet-selected").BackgroundTransparency):toBe(0)
					expectColor(
						".facet-appearance-soft.facet-selected >> .facet-button-caption",
						"TextColor3",
						colors.onAccent
					)
					expectColor(".facet-appearance-soft.facet-selected >> .facet-text", "TextColor3", colors.onAccent)
					expect(style(sheet, ".facet-appearance-utility").BackgroundTransparency):toBe(1)
					expectColor(".facet-appearance-utility:Hover", "BackgroundColor3", extra.controlHover)
					expect(style(sheet, ".facet-appearance-utility:Hover").BackgroundTransparency):toBe(0)
					expectColor(".facet-appearance-utility:Press", "BackgroundColor3", extra.controlPressed)
					expect(style(sheet, ".facet-appearance-link").BackgroundTransparency):toBe(1)
					expectColor(".facet-appearance-link", "TextColor3", colors.content)
					expectColor(".facet-appearance-link >> .facet-button-caption", "TextColor3", colors.content)
					expectColor(".facet-appearance-link >> .facet-icon", "ImageColor3", colors.content)
					expect(style(sheet, ".facet-appearance-link::UIPadding").PaddingLeft):toBe(
						h.engine.types.UDim.new(0, 0)
					)
					expectColor(".facet-quiet-destructive", "TextColor3", colors.danger)
					expectColor(".facet-quiet-destructive >> .facet-button-caption", "TextColor3", colors.danger)
					expectColor(".facet-selected", "BackgroundColor3", extra.controlSelected)
					expectColor(".facet-selected", "TextColor3", colors.content)
					expect(style(sheet, ".facet-disabled").TextTransparency):toBe(extra.disabledContentOpacity)
					expect(style(sheet, ".facet-disabled >> .facet-button-caption").TextTransparency):toBe(
						extra.disabledContentOpacity
					)
					expectColor(".facet-button:Hover", "BackgroundColor3", extra.controlHover)
					expectColor(".facet-button:Press", "BackgroundColor3", extra.controlPressed)
					local function priority(selector: string): number
						return ruleNode(sheet, selector).Priority
					end
					for _, base in
						{
							".facet-role-destructive",
							".facet-appearance-soft",
							".facet-appearance-utility",
							".facet-appearance-link",
						}
					do
						for _, state in { ":Hover", ":Press" } do
							expect(priority(base .. state) > priority(base)):toBe(true)
							expect(priority(base .. state) > priority(".facet-button" .. state)):toBe(true)
						end
					end
					expect(priority(".facet-button:Hover") > priority(".facet-button")):toBe(true)
					expect(style(sheet, ".facet-disabled >> .facet-toggle-indicator").BackgroundTransparency):toBe(
						extra.disabledContentOpacity
					)
					expect(priority(".facet-disabled >> .facet-toggle-indicator") > priority(".facet-toggle-indicator")):toBe(
						true
					)
					for _, state in { ":Hover", ":Press" } do
						local disabled = ".facet-menu-destructive.facet-disabled" .. state
						expect(style(sheet, disabled).BackgroundTransparency):toBe(1)
						expect(priority(disabled) > priority(".facet-menu-destructive" .. state)):toBe(true)
					end
					for _, state in { "", ":Hover", ":Press" } do
						expect(
							priority(".facet-appearance-soft.facet-selected")
								> priority(".facet-appearance-soft" .. state)
						):toBe(true)
					end
					expect(priority(".facet-quiet-destructive") > priority(".facet-appearance-utility")):toBe(true)
					expect(
						priority(".facet-quiet-destructive >> .facet-button-caption")
							> priority(".facet-appearance-link >> .facet-button-caption")
					):toBe(true)
					local destructive = ruleNode(sheet, ".facet-role-destructive")
					local retuned = themes.neutralPackage()
					retuned.style.themes[1].colors.danger = { r = 0.5, g = 0, b = 0.1 }
					package:set(retuned)
					expect((ruleNode(sheet, ".facet-role-destructive"))):toBe(destructive)
					expect(styleProperties(destructive).BackgroundColor3):toBe(h.engine.types.Color3.new(0.5, 0, 0.1))
					stop()
					h.dispose()
				end,
			})

			it("derives control hover and pressed plates from the palette's own control", {
				id = "native_themes_media::native parity paint::derives control hover and pressed plates from the palette's own control",
				run = function()
					type Plates = { control: ThemeTypes.RGB, hover: ThemeTypes.RGB, pressed: ThemeTypes.RGB }
					local function rgb(r: number, g: number, b: number): ThemeTypes.RGB
						return { r = r / 255, g = g / 255, b = b / 255 }
					end
					local function plates(extra: ThemeTypes.PaletteExtra?): Plates
						local resolved = assert(extra)
						return {
							control = assert(resolved.control),
							hover = assert(resolved.controlHover),
							pressed = assert(resolved.controlPressed),
						}
					end
					local function step(from: ThemeTypes.RGB, to: ThemeTypes.RGB): number
						return (luminance(to) + 0.05) / (luminance(from) + 0.05)
					end
					local function follows(derived: Plates, reference: Plates)
						local hover = step(reference.control, reference.hover)
						local pressed = step(reference.control, reference.pressed)
						expect(step(derived.control, derived.hover)):toBeCloseTo(hover)
						expect(step(derived.control, derived.pressed)):toBeCloseTo(pressed)
						for _, plate in { derived.hover, derived.pressed } do
							expect(plate.r > plate.g and plate.g > plate.b):toBe(true)
						end
					end
					local h = harness()
					local function paint(package: ThemeTypes.ThemePackage?, selector: string): unknown
						local sheet, stop = sheetFor(h, package)
						local value = style(sheet, selector).BackgroundColor3
						stop()
						return value
					end
					local neutral = themes.neutralPackage()
					local neutralDark = plates(neutral.style.themes[1].extra)
					local neutralLight = plates(neutral.style.themes[2].extra)

					local definition: ThemeTypes.ThemeDefinition = {
						base = themes.neutralPackage(),
						identity = { id = "derived-control-states" },
						style = {
							defaultTheme = "Game",
							themes = { { name = "Game", extra = { control = rgb(168, 114, 47) } } },
						},
					}
					local game, report = themes.define(definition)
					expect(report.ok):toBe(true)
					expect(#report.contrast):toBeGreaterThan(0)
					local dark = plates(assert(game).style.themes[1].extra)
					expect(luminance(dark.hover)):toBeGreaterThan(luminance(dark.control))
					expect(luminance(dark.pressed)):toBeLessThan(luminance(dark.control))
					follows(dark, neutralDark)
					expect(neutralDark.hover.b > neutralDark.hover.r):toBe(true)
					expect(paint(game, ".facet-button:Hover")):toBe(color(h.engine, dark.hover))
					expect(paint(game, ".facet-button:Press")):toBe(color(h.engine, dark.pressed))

					local package = themes.neutralPackage()
					local parchment = assert(package.style.themes[2].extra)
					parchment.control = rgb(214, 194, 156)
					parchment.controlHover = nil
					parchment.controlPressed = nil
					local light = plates(assert((themes.define(package))).style.themes[2].extra)
					expect(luminance(light.hover)):toBeLessThan(luminance(light.control))
					expect(luminance(light.pressed)):toBeLessThan(luminance(light.hover))
					follows(light, neutralLight)

					local explicit = themes.neutralPackage()
					local partial = assert(explicit.style.themes[1].extra)
					partial.control = rgb(168, 114, 47)
					partial.controlHover = rgb(200, 40, 40)
					partial.controlPressed = nil
					local resolved = assert((themes.define(explicit)))
					local kept = plates(resolved.style.themes[1].extra)
					expect(kept.hover):toEqual(rgb(200, 40, 40))
					expect(kept.pressed):toEqual(dark.pressed)
					expect(plates(resolved.style.themes[2].extra)):toEqual(neutralLight)

					local plain: ThemeTypes.ThemeDefinition = {
						base = themes.neutralPackage(),
						identity = { id = "plain-control-states" },
						style = {
							defaultTheme = "Game",
							themes = { { name = "Game", extra = { contentSecondary = rgb(150, 160, 170) } } },
						},
					}
					local untouched, plainReport = themes.define(plain)
					expect(plainReport.ok):toBe(true)
					local unset = assert(assert(untouched).style.themes[1].extra)
					expect(unset.controlHover):toBeNil()
					expect(unset.controlPressed):toBeNil()
					expect(paint(untouched, ".facet-button:Hover")):toBe(color(h.engine, neutralDark.hover))
					expect(paint(untouched, ".facet-button:Press")):toBe(color(h.engine, neutralDark.pressed))

					local undefined = themes.neutralPackage()
					local sand = assert(undefined.style.themes[1])
					sand.colors.surface = rgb(240, 232, 214)
					local sandExtra = assert(sand.extra)
					sandExtra.controlHover = nil
					sandExtra.controlPressed = nil
					expect(paint(undefined, ".facet-button:Hover")):toBe(color(h.engine, neutralLight.hover))
					expect(paint(undefined, ".facet-button:Press")):toBe(color(h.engine, neutralLight.pressed))
					h.dispose()
				end,
			})

			it("keeps the contrast step on a saturated control plate", {
				id = "native_themes_media::native parity paint::keeps the contrast step on a saturated control plate",
				run = function()
					local function step(from: ThemeTypes.RGB, to: ThemeTypes.RGB): number
						return (luminance(to) + 0.05) / (luminance(from) + 0.05)
					end
					local base = assert(themes.neutralPackage().style.themes[1].extra)
					local up = step(assert(base.control), assert(base.controlHover))
					local down = step(assert(base.control), assert(base.controlPressed))
					local plates: { ThemeTypes.RGB } = {
						{ r = 1, g = 0, b = 0 },
						{ r = 1, g = 120 / 255, b = 0 },
						{ r = 1, g = 200 / 255, b = 0 },
					}
					for _, plate in plates do
						local definition: ThemeTypes.ThemeDefinition = {
							base = themes.neutralPackage(),
							identity = { id = "saturated-control-states" },
							style = {
								defaultTheme = "Game",
								themes = { { name = "Game", extra = { control = plate } } },
							},
						}
						local package, report = themes.define(definition)
						expect(report.ok):toBe(true)
						local extra = assert(assert(package).style.themes[1].extra)
						local lighter, darker = assert(extra.controlHover), assert(extra.controlPressed)
						expect(step(plate, lighter)):toBeCloseTo(up)
						expect(step(plate, darker)):toBeCloseTo(down)
						expect(lighter.r):toBeCloseTo(1)
						expect(lighter.g > plate.g and lighter.b > plate.b):toBe(true)
						expect(darker.r < 1 and darker.r > darker.g):toBe(true)
					end
				end,
			})
		end)
	end)(verifyHarness)
end
