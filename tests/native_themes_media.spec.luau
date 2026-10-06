--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type FixtureShadow = typeof(require("@repo/tools/typecheck/aliases").FixtureShadow)
	type Destroyable = typeof(require("@repo/tools/typecheck/aliases").Destroyable)

	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
	type MotionLevel = typeof(require("@repo/tools/typecheck/aliases").MotionLevel)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type TextButtonConstructor = typeof(require("@repo/tools/typecheck/aliases").TextButtonConstructor)
	local FixtureComposeTypes = require("../src/vendor/compose/core")
	local requireDynamic = require :: (any) -> any
	local FixtureMediaTypes = require("../src/ui/media_types")
	local FixtureThemeTypes = require("../src/ui/theme_types")
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local transitionOf = require("./lib/transition")
	local Compose = require("../src/vendor/compose/core")
	local Roblox = require("../src/vendor/compose/roblox")
	local context = require("../src/ui/context")
	local controls = require("../src/ui")
	local media = require("../src/ui/media")
	local themes = require("../src/ui/themes")(Compose)
	local engineLib = require("./lib/native_engine")
	local fs = require("@lune/fs")

	local function setup()
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Roblox.createRuntime(engine)
		local UI = media(context(Compose, runtime, { types = engine.types }))
		return engine, runtime, UI
	end

	local function style(sheet, selector)
		for _, node in sheet:GetChildren() do
			if node.Selector == selector then
				return node:GetProperties()
			end
		end
		error("No rule: " .. selector)
	end

	verifyHarness:suite("native themes and media", function()
		verifyHarness:case("keeps native theme rules reactive without writing instance paint", {
			id = "native_themes_media::native themes and media::keeps native theme rules reactive without writing instance paint",
			run = function()
				local engine, runtime, UI = setup()
				local selected = Compose.cell(themes.neutralPackage())
				local sheet: any, label: any
				local stop = runtime.mount(function()
					sheet = themes.createStyleSheet(runtime, selected, { types = engine.types })
					label = UI.Text({ text = "Themed" })
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						sheet :: unknown,
						runtime.constructors.StyleLink({ StyleSheet = Compose.static(sheet) }),
						label,
					})
				end, engine.new("Folder"))
				local nextTheme = themes.neutralPackage()
				nextTheme.style.themes[1].colors.content = { r = 0.1, g = 0.2, b = 0.3 }
				selected:set(nextTheme)
				Verify.expect(style(sheet, ".facet-text").TextColor3):toBe(engine.types.Color3.new(0.1, 0.2, 0.3))
				Verify.expect(label.Text):toBe("Themed")
				stop()
				Verify.expect((sheet.isDestroyed())):toBe(true)
				runtime:dispose()
			end,
		})

		verifyHarness:case("scales translucent theme surfaces by the player's background transparency preference", {
			id = "native_themes_media::native themes and media::scales translucent theme surfaces by the player's background transparency preference",
			run = function()
				local engine, runtime = setup()
				local preference = Compose.cell(1)
				local sheet: any
				local stop = runtime.mount(function()
					sheet = themes.createStyleSheet(
						runtime,
						themes.neutralPackage(),
						{ types = engine.types, preferredTransparency = preference }
					)
					return sheet
				end, engine.new("Folder"))
				local authored = style(sheet, ".facet-scrim").BackgroundTransparency
				Verify.expect(authored > 0 and authored < 1):toBe(true)
				preference:set(0.5)
				Verify.expect(style(sheet, ".facet-scrim").BackgroundTransparency):toBe(authored * 0.5)
				Verify.expect(style(sheet, ".facet-skinned").BackgroundTransparency):toBe(1)
				preference:set(0)
				Verify.expect(style(sheet, ".facet-scrim").BackgroundTransparency):toBe(0)
				preference:set(0 / 0)
				Verify.expect(style(sheet, ".facet-scrim").BackgroundTransparency):toBe(authored)
				preference:set(1)
				Verify.expect(style(sheet, ".facet-scrim").BackgroundTransparency):toBe(authored)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case(
			"retargets native theme paint with shared timing and disables motion without replacing rules",
			{
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
					light.extra = table.clone(light.extra or {})
					assert(light.extra).onSelected = { r = 1, g = 1, b = 1 }
					package.style.themes = { package.style.themes[1], light }
					package = assert(themes.define(package))
					local selection, reduced, explicit: FixtureComposeTypes.Cell<(TweenInfo | false)?> =
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
					Verify.expect(timing.Time):toBe(0.32)
					Verify.expect(timing.EasingStyle):toBe(engine.types.Enum.EasingStyle.Quad)
					Verify.expect((transitionOf(surfaceRule, "BackgroundColor3"))):toBe(timing)
					Verify.expect((transitionOf(surfaceRule, "BackgroundTransparency"))):toBe(timing)
					Verify.expect((transitionOf(textRule, "TextSize"))):toBe(nil)
					selection:set("Light")
					Verify.expect(textRule:GetProperties().TextColor3):toBe(engine.types.Color3.new(0.1, 0.1, 0.1))
					Verify.expect(surfaceRule:GetProperties().BackgroundColor3)
						:toBe(engine.types.Color3.new(0.9, 0.9, 0.9))
					selection:set("Dark")
					Verify.expect((transitionOf(textRule, "TextColor3"))):toBe(timing)
					Verify.expect(textRule:GetProperties().TextColor3)
						:toBe(engine.types.Color3.new(236 / 255, 239 / 255, 245 / 255))
					Verify.expect(sheet:GetChildren()[1]):toBe(rules[1])
					Verify.expect(#sheet:GetChildren()):toBe(#rules)
					Verify.expect((engine.heartbeat.count())):toBe(0)
					reduced:set(true)
					Verify.expect(transitionOf(textRule, "TextColor3").Time):toBe(0)
					Verify.expect(transitionOf(surfaceRule, "BackgroundColor3").Time):toBe(0)
					selection:set("Light")
					Verify.expect(surfaceRule:GetProperties().BackgroundColor3)
						:toBe(engine.types.Color3.new(0.9, 0.9, 0.9))
					reduced:set(false)
					local override = engine.types.TweenInfo.new(0.6, engine.types.Enum.EasingStyle.Linear)
					explicit:set(override)
					Verify.expect((transitionOf(surfaceRule, "BackgroundColor3"))):toBe(override)
					explicit:set(false :: false)
					Verify.expect(transitionOf(textRule, "TextColor3").Time):toBe(0)
					stop()
					Verify.expect((textRule.isDestroyed())):toBe(true)
					Verify.expect((surfaceRule.isDestroyed())):toBe(true)
					selection:set("Dark")
					Verify.expect((engine.heartbeat.count())):toBe(0)
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case(
			"adds and removes native rules through Compose while shallow-frozen packages stay reactive",
			{
				id = "native_themes_media::native themes and media::adds and removes native rules through Compose while shallow-frozen packages stay reactive",
				run = function()
					local engine, runtime = setup()
					local package = themes.neutralPackage()
					local contributed: FixtureThemeTypes.RuleProperties = { BackgroundTransparency = 0.25 }
					package.rules = {}
					table.freeze(package)
					local revision = Compose.cell(0)
					local stop, sheet: any = runtime.mount(function()
						return themes.createStyleSheet(runtime, function(use: Use)
							use(revision)
							return package
						end, { types = engine.types })
					end, engine.new("Folder"))
					local initial = sheet:GetChildren()
					table.insert(assert(package.rules), { selector = ".game-added", properties = contributed })
					revision:set(1)
					Verify.expect(#sheet:GetChildren()):toBe(#initial + 1)
					local added = sheet:GetChildren()[#initial + 1]
					Verify.expect(added.Selector):toBe(".game-added")
					Verify.expect(added:GetProperties().BackgroundTransparency):toBe(0.25)
					Verify.expect(transitionOf(added, "BackgroundTransparency").Time):toBe(0.2)
					contributed.BackgroundTransparency = 0.75
					revision:set(2)
					Verify.expect(added:GetProperties().BackgroundTransparency):toBe(0.75)
					Verify.expect(sheet:GetChildren()[#initial + 1]):toBe(added)
					table.clear(assert(package.rules))
					revision:set(3)
					Verify.expect((added.isDestroyed())):toBe(true)
					Verify.expect(#sheet:GetChildren()):toBe(#initial)
					for index, rule in initial do
						Verify.expect(sheet:GetChildren()[index]):toBe(rule)
					end
					stop()
					for _, rule in initial do
						Verify.expect((rule.isDestroyed())):toBe(true)
					end
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case("keeps theme skin layers and state asset swaps inside native Compose ownership", {
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
				Verify.expect(#node:GetChildren()):toBe(5)
				Verify.expect(node:FindFirstChild("control2bottomRight").Image):toBe("rbxassetid://3")
				local image = node:FindFirstChild("control1")
				Verify.expect(image.Image):toBe("rbxassetid://1")
				Verify.expect(image.ScaleType):toBe(engine.types.Enum.ScaleType.Slice)
				state:set("pressed")
				Verify.expect(image.Image):toBe("rbxassetid://2")
				Verify.expect(image.ScaleType):toBe(engine.types.Enum.ScaleType.Stretch)
				stop()
				Verify.expect((image.isDestroyed())):toBe(true)
				runtime:dispose()
			end,
		})

		verifyHarness:case("shares caller resources directly through Compose and releases the final reference", {
			id = "native_themes_media::native themes and media::shares caller resources directly through Compose and releases the final reference",
			run = function()
				local engine, runtime, UI = setup()
				local acquired, released = 0, 0
				local resource = Compose.createSharedResource(function(): (FixtureMediaTypes.ImageResource, (() -> ())?)
					acquired += 1
					return {
						state = Compose.cell("ready" :: "loading" | "ready" | "failed"),
						value = Compose.cell("rbxassetid://7"),
					}, function()
						released += 1
					end
				end)
				local first: any = runtime.mount(function()
					return UI.AsyncImage({
						resource = function()
							return resource()
						end,
					})
				end, engine.new("Folder"))
				local second = runtime.mount(function()
					return UI.AsyncImage({
						resource = function()
							return resource()
						end,
					})
				end, engine.new("Folder"))
				Verify.expect(acquired):toBe(1)
				first()
				Verify.expect(released):toBe(0)
				second()
				Verify.expect(released):toBe(1)
				runtime:dispose()
			end,
		})

		verifyHarness:case("preserves the shipped palette, typography and art packages as native inputs", {
			id = "native_themes_media::native themes and media::preserves the shipped palette, typography and art packages as native inputs",
			run = function()
				local engine, runtime = setup()
				for _, name in
					{
						"classic_desktop",
						"compact_pointer",
						"fantasy_ornate",
						"fantasy_parchment",
						"glossy_mobile",
						"glossy_touch",
						"pixel_quest",
						"scifi_hud",
						"layered_test",
					}
				do
					local module = requireDynamic("../examples/themes/" .. name)
					local package, report = module.build(themes)
					Verify.expect(report.ok):toBe(true)
					local stop, sheet: any = runtime.mount(function()
						return themes.createStyleSheet(runtime, package, { types = engine.types })
					end, engine.new("Folder"))
					Verify.expect(#sheet:GetChildren() > 30):toBe(true)
					stop()
				end
				runtime:dispose()
			end,
		})

		verifyHarness:case("keeps async completions stale after a source change or disposal", {
			id = "native_themes_media::native themes and media::keeps async completions stale after a source change or disposal",
			run = function()
				local engine, runtime, UI = setup()
				local source, requests, states = Compose.cell("first" :: string?), {}, {}
				local cancellations = 0
				local stop, root: any = runtime.mount(function()
					return UI.AsyncImage({
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
					})
				end, engine.new("Folder"))
				source:set("second")
				requests.first.resolve("wrong")
				Verify.expect(root:FindFirstChild("Image").Visible):toBe(false)
				requests.second.resolve("right")
				Verify.expect(root:FindFirstChild("Image").Image):toBe("right")
				Verify.expect(root:FindFirstChild("Image").Visible):toBe(true)
				stop()
				local count = #states
				requests.second.reject("late")
				Verify.expect(#states):toBe(count)
				Verify.expect(cancellations):toBe(2)
				runtime:dispose()
			end,
		})

		verifyHarness:case("exposes failure content and retries when the source changes", {
			id = "native_themes_media::native themes and media::exposes failure content and retries when the source changes",
			run = function()
				local engine, runtime, UI = setup()
				local source = Compose.cell("broken" :: string?)
				local stop, root: any = runtime.mount(function()
					return UI.AsyncImage({
						source = source,
						failureLabel = "Unavailable",
						loader = function(content, resolve, reject)
							if content == "broken" then
								reject("missing")
							else
								resolve(content)
							end
						end,
					})
				end, engine.new("Folder"))
				local found = false
				for _, node in root:GetDescendants() do
					if node:IsA("TextLabel") and node.Text == "Unavailable" then
						found = true
					end
				end
				Verify.expect(found):toBe(true)
				source:set("working")
				Verify.expect(root:FindFirstChild("Image").Visible):toBe(true)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("clamps progress, counts badges and releases stage scenes with Compose", {
			id = "native_themes_media::native themes and media::clamps progress, counts badges and releases stage scenes with Compose",
			run = function()
				local engine, runtime, UI = setup()
				local progress = Compose.cell(0.25)
				local count = Compose.cell(120 :: number?)
				local stage, bar, badge, released = nil, nil, nil, 0
				local stop = runtime.mount(function()
					bar = UI.ProgressView({ value = progress })
					badge = UI.StatusIndicator({ count = count, status = "success" :: "success" })
					stage = UI.Stage({
						content = function(sceneRuntime: FixtureComposeTypes.Runtime, world: WorldModel): (() -> ())?
							local Host = (sceneRuntime.constructors :: unknown) :: RobloxHost
							local stop = sceneRuntime.mount(function(): Part
								return Host.Part "Model" {}
							end, world)
							return stop
						end,
					})
					Compose.cleanup(function()
						released += 1
					end)
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						bar :: unknown,
						badge,
						stage,
					})
				end, engine.new("Folder"))
				Verify.expect((bar:FindFirstChild("Fill1", true) :: any).Size.X.Scale):toBe(0.25)
				progress:set(2)
				Verify.expect((bar:FindFirstChild("Fill1", true) :: any).Size.X.Scale):toBe(1)
				Verify.expect(badge.Text):toBe("99+")
				Verify.expect(badge.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.X)
				Verify.expect(assert(badge:FindFirstChildWhichIsA("UISizeConstraint")).MinSize.X):toBe(24)
				Verify.expect((badge:FindFirstChildWhichIsA("UIAspectRatioConstraint"))):toBe(nil)
				count:set(3)
				Verify.expect(badge.Text):toBe("3")
				local model: any = stage:FindFirstChild("Model", true)
				Verify.expect(model.ClassName):toBe("Part")
				stop()
				Verify.expect((model.isDestroyed())):toBe(true)
				Verify.expect(released):toBe(1)
				runtime:dispose()
			end,
		})
		verifyHarness:case("preserves avatar initials presence rung changes and keyed roster identity", {
			id = "native_themes_media::native themes and media::preserves avatar initials presence rung changes and keyed roster identity",
			run = function()
				local engine, runtime, UI = setup()
				local rung: FixtureComposeTypes.Cell<"compact" | "large" | "regular" | "xsmall">, presence =
					Compose.cell("compact" :: "compact" | "large" | "regular" | "xsmall"),
					Compose.cell("online" :: ("away" | "busy" | "inExperience" | "offline" | "online")?)
				local roster = Compose.cell({
					{ id = "a", name = "Émile Noël" },
					{ id = "b", name = "Bo Lane" },
					{ id = "c", name = "Ada Quill" },
				})
				local avatar, group, selected = nil, nil, 0
				local stop = runtime.mount(function()
					avatar = UI.Avatar({ name = "Émile Noël", presence = presence, controlSize = rung })
					group = UI.AvatarGroup({
						items = roster,
						max = 2,
						onOverflow = function()
							selected += 1
						end,
					})
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({ avatar :: unknown, group })
				end, engine.new("Folder"))
				Verify.expect((avatar:FindFirstChild("Initials") :: any).Text):toBe("ÉN")
				Verify.expect(avatar.Size.X.Offset):toBe(36)
				Verify.expect(
					((avatar:FindFirstChild("Initials") :: any):FindFirstChildWhichIsA("UITextSizeConstraint") :: any).MaxTextSize
				):toBe(14)
				Verify.expect(avatar.Selectable):toBe(false)
				presence:set("busy")
				rung:set("large")
				Verify.expect((avatar:GetAttribute("AccessibleLabel"))):toBe("Émile Noël, busy")
				Verify.expect(avatar.Size.X.Offset):toBe(56)
				Verify.expect(
					((avatar:FindFirstChild("Initials") :: any):FindFirstChildWhichIsA("UITextSizeConstraint") :: any).MaxTextSize
				):toBe(22)
				Verify.expect((avatar:FindFirstChild("Presence") :: any):HasTag("facet-status-error") :: any):toBe(true)
				Verify.expect((group:HasTag("facet-avatar-stack"))):toBe(true)
				local first: any = group:FindFirstChild("a")
				roster:set({
					{ id = "b", name = "Bo Lane" },
					{ id = "a", name = "Émile Changed" },
					{ id = "c", name = "Ada Quill" },
				})
				Verify.expect((group:FindFirstChild("a"))):toBe(first)
				Verify.expect((first:FindFirstChild("Initials") :: any).Text):toBe("ÉC")
				Verify.expect(first.LayoutOrder):toBe(2)
				local overflow: any = group:FindFirstChild("Overflow")
				Verify.expect(overflow.Text):toBe("+1")
				overflow.Activated.fire()
				Verify.expect(selected):toBe(1)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("animates skeletons with one shared Compose clock and honors reduced motion", {
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
					return UI.Skeleton({ form = "line" :: "line", lines = 3 })
				end, engine.new("Folder"))
				local listeners = engine.heartbeat.count()
				local second, two: any = runtime.mount(function()
					return UI.Skeleton({ form = "circle" :: "circle" })
				end, engine.new("Folder"))
				Verify.expect((engine.heartbeat.count())):toBe(listeners)
				Verify.expect(one:FindFirstChild("Placeholder3").Size.X.Scale):toBeCloseTo(0.6, 1e-4)
				engine.heartbeat.fire(0.4)
				local gradient = two:FindFirstChild("Shimmer", true)
				local previous = gradient.Offset.X
				first()
				engine.heartbeat.fire(0.2)
				Verify.expect(gradient.Offset.X > previous):toBe(true)
				reduced:set(true)
				Verify.expect(gradient.Enabled):toBe(false)
				previous = gradient.Offset.X
				engine.heartbeat.fire(0.3)
				Verify.expect(gradient.Offset.X):toBe(previous)
				reduced:set(false)
				engine.heartbeat.fire(0.2)
				Verify.expect(gradient.Enabled):toBe(true)
				Verify.expect(gradient.Offset.X ~= previous):toBe(true)
				second()
				runtime:dispose()
				Verify.expect((engine.heartbeat.count())):toBe(0)
			end,
		})

		verifyHarness:case("keeps indeterminate progress stepping and trails determinate decreases", {
			id = "native_themes_media::native themes and media::keeps indeterminate progress stepping and trails determinate decreases",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local UI = media(context(Compose, runtime, { types = engine.types, motionLevel = "none" }))
				local value, bar, busy = Compose.cell(0.8), nil, nil
				local stop = runtime.mount(function()
					bar = UI.ProgressView({ value = value, trail = { delay = 0.2, duration = 0.4 } })
					busy = UI.ProgressView({ presentation = "spinner" :: "spinner" })
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({ bar :: unknown, busy })
				end, engine.new("Folder"))
				local dot: any = busy:FindFirstChild("Segment1", true)
				local before = dot.BackgroundTransparency
				engine.heartbeat.fire(0.1)
				Verify.expect(dot.BackgroundTransparency):toBe(before)
				engine.heartbeat.fire(0.2)
				Verify.expect(dot.BackgroundTransparency ~= before):toBe(true)
				value:set(0.2)
				Verify.expect((bar:FindFirstChild("Trail", true) :: any).Size.X.Scale):toBeCloseTo(0.2, 1e-4)
				stop()
				runtime:dispose()
				Verify.expect((engine.heartbeat.count())):toBe(0)
			end,
		})

		verifyHarness:case("keeps badges and status shapes reactive without creating focus targets", {
			id = "native_themes_media::native themes and media::keeps badges and status shapes reactive without creating focus targets",
			run = function()
				local engine, runtime, UI = setup()
				local label, status, form =
					Compose.cell("Online"),
					Compose.cell(
						"success" :: "accent" | "contrast" | "error" | "info" | "neutral" | "success" | "voice" | "warning"
					),
					Compose.cell("dot" :: "dash" | "dot" | "ring" | "square")
				local badge: any, indicator
				local stop = runtime.mount(function()
					badge = UI.Badge({ label = label, status = status })
					indicator = UI.StatusIndicator({ status = status, form = form, diameter = 16 })
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({ badge :: unknown, indicator })
				end, engine.new("Folder"))
				Verify.expect(badge.Selectable):toBe(false)
				Verify.expect(indicator.Selectable):toBe(false)
				label:set("Away")
				status:set("warning")
				form:set("dash")
				Verify.expect(badge.Text):toBe("Away")
				Verify.expect((indicator:HasTag("facet-status-warning"))):toBe(true)
				Verify.expect(indicator.Size.Y.Offset < indicator.Size.X.Offset):toBe(true)
				form:set("ring")
				local ring: any = indicator:FindFirstChild("Ring")
				Verify.expect((ring:HasTag("facet-status-ring"))):toBe(true)
				Verify.expect(ring.BorderStrokePosition):toBe(engine.types.Enum.BorderStrokePosition.Inner)
				Verify.expect(ring.Thickness):toBe(3)
				Verify.expect((indicator:HasTag("facet-status-hollow"))):toBe(true)
				form:set("dot")
				Verify.expect((indicator:FindFirstChild("Ring"))):toBe(nil)
				Verify.expect((indicator:HasTag("facet-status-hollow"))):toBe(false)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("lets the skinned tag outrank every built-in control fill", {
			id = "native_themes_media::native themes and media::lets the skinned tag outrank every built-in control fill",
			run = function()
				local engine, runtime = setup()
				local stop, sheet: any = runtime.mount(function()
					return themes.createStyleSheet(runtime, themes.neutralPackage(), { types = engine.types })
				end, engine.new("Folder"))
				local skinned, highest = nil, 0
				for _, rule in sheet:GetChildren() do
					if rule.Selector == ".facet-skinned" then
						skinned = rule.Priority
					elseif
						string.match(rule.Selector, "^%.facet%-[%w%-]+$")
						and rule:GetProperties().BackgroundTransparency ~= nil
					then
						highest = math.max(highest, rule.Priority)
					end
				end
				Verify.expect(skinned > highest):toBe(true)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("replaces a skin state map when a derived package overrides it", {
			id = "native_themes_media::native themes and media::replaces a skin state map when a derived package overrides it",
			run = function()
				local basis = themes.neutralPackage()
				basis.assets = {
					a = { content = "rbxassetid://1" },
					b = { content = "rbxassetid://2" },
					c = { content = "rbxassetid://3" },
				}
				assert(basis.chrome).control = { kind = "fill" :: "fill", asset = { default = "a", pressed = "b" } }
				local base = assert(themes.define(basis))
				local definition: FixtureThemeTypes.ThemeDefinition = {
					base = base,
					identity = { id = "derived" },
					chrome = { control = { asset = { default = "c" } } },
				}
				local derived = themes.define(definition)
				Verify.expect((assert(assert(derived).chrome).control.asset :: FixtureThemeTypes.AssetVariants).default)
					:toBe("c")
				Verify.expect((assert(assert(derived).chrome).control.asset :: FixtureThemeTypes.AssetVariants).pressed)
					:toBe(nil)
				Verify.expect(assert(assert(derived).chrome).control.kind):toBe("fill")
			end,
		})

		verifyHarness:case("rejects malformed type roles, unknown shadow presets and unreadable selected labels", {
			id = "native_themes_media::native themes and media::rejects malformed type roles, unknown shadow presets and unreadable selected labels",
			run = function()
				local typed = themes.neutralPackage()
				local roles = (typed.metrics.typography :: unknown) :: { [string]: unknown }
				roles.body = 5
				Verify.expect((select(2, themes.define(typed))).ok):toBe(false)
				local shadowed = themes.neutralPackage()
				shadowed.chrome = { control = { kind = "native" :: "native", shadow = "floating" } }
				Verify.expect((select(2, themes.define(shadowed))).ok):toBe(false)
				local selected = themes.neutralPackage()
				selected.style.themes[1].extra = table.clone(selected.style.themes[1].extra or {})
				assert(selected.style.themes[1].extra).controlSelected = { r = 0.9, g = 0.9, b = 0.92 }
				Verify.expect((select(2, themes.define(selected))).ok):toBe(false)
				local valid = themes.neutralPackage()
				valid.chrome = { control = { kind = "native" :: "native", shadow = "raised" } }
				Verify.expect((select(2, themes.define(valid))).ok):toBe(true)
			end,
		})

		verifyHarness:case("rejects unreadable semantic color pairs and reports contributed theme coverage", {
			id = "native_themes_media::native themes and media::rejects unreadable semantic color pairs and reports contributed theme coverage",
			run = function()
				local bad = themes.neutralPackage()
				bad.style.themes[1].colors.content = bad.style.themes[1].colors.surface
				local package, report = themes.define(bad)
				Verify.expect(package):toBe(nil)
				Verify.expect(report.ok):toBe(false)
				local needs = { { name = "custom:knob", section = "metrics.radii", kind = "number" :: "number" } }
				Verify.expect(themes.checkCoverage(themes.neutralPackage(), needs).ok):toBe(false)
				local good = themes.neutralPackage()
				good.metrics.radii["custom:knob"] = 4
				Verify.expect(themes.checkCoverage(good, needs).ok):toBe(true)
			end,
		})
		verifyHarness:case("keeps compiled theme data immutable and rejects callbacks or malformed values", {
			id = "native_themes_media::native themes and media::keeps compiled theme data immutable and rejects callbacks or malformed values",
			run = function()
				local definition = themes.neutralPackage()
				local package = themes.define(definition)
				Verify.expect((table.isfrozen(assert(package).metrics.typography))):toBe(true)
				definition.metrics.typography.body.size = 23
				Verify.expect(assert(package).metrics.typography.body.size):toBe(16)
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
				Verify.expect(select(2, themes.define(definition)).ok):toBe(false)
				Verify.expect(select(2, themes.define(false :: any)).ok):toBe(false)
			end,
		})

		verifyHarness:case("preserves external cameras and forwards native viewport lighting", {
			id = "native_themes_media::native themes and media::preserves external cameras and forwards native viewport lighting",
			run = function()
				local engine, runtime, UI = setup()
				local camera = engine.new("Camera")
				local original = engine.new("Folder")
				camera.Parent = original
				local ambient = engine.types.Color3.new(0.2, 0.3, 0.4)
				local stop, stage: any = runtime.mount(function()
					return UI.Stage({
						camera = camera,
						Ambient = ambient,
						LightDirection = engine.types.Vector3.new(1, -1, 0),
					})
				end, engine.new("Folder"))
				Verify.expect(stage.CurrentCamera):toBe(camera)
				Verify.expect(stage.Ambient):toBe(ambient)
				Verify.expect(camera.Parent):toBe(original)
				stop()
				Verify.expect((camera.isDestroyed())):toBe(false)
				runtime:dispose()
			end,
		})

		verifyHarness:case("uses native image framing and rounded avatar images", {
			id = "native_themes_media::native themes and media::uses native image framing and rounded avatar images",
			run = function()
				local engine, runtime, UI = setup()
				local avatar: any, image: any
				local stop = runtime.mount(function()
					avatar = UI.Avatar({ name = "Ada", image = "rbxassetid://1" })
					image = UI.AsyncImage({
						image = "rbxassetid://2",
						imageProperties = {
							ScaleType = engine.types.Enum.ScaleType.Crop,
							ResampleMode = engine.types.Enum.ResamplerMode.Pixelated,
						},
					})
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({ avatar :: unknown, image })
				end, engine.new("Folder"))
				Verify.expect(
					((avatar:FindFirstChild("Image", true) :: any):FindFirstChildWhichIsA("UICorner") :: any).CornerRadius.Scale
				):toBe(1)
				Verify.expect((image:FindFirstChild("Image") :: any).ScaleType):toBe(engine.types.Enum.ScaleType.Crop)
				Verify.expect((image:FindFirstChild("Image") :: any).ResampleMode)
					:toBe(engine.types.Enum.ResamplerMode.Pixelated)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("keeps plaques edges tiling pixel resampling and chrome insets native", {
			id = "native_themes_media::native themes and media::keeps plaques edges tiling pixel resampling and chrome insets native",
			run = function()
				local engine, runtime = setup()
				local package = themes.neutralPackage()
				package.identity.rendering = "pixel"
				assert(package.assets).art = { content = "rbxassetid://10" }
				assert(package.chrome).control = {
					kind = "layered" :: "layered",
					contentInsets = { top = 4, right = 20, bottom = 6, left = 20 },
					layers = {
						{ kind = "tile" :: "tile", asset = "art", tileSize = { w = 8, h = 8 } } :: FixtureThemeTypes.SkinLayer,
						{
							kind = "edges" :: "edges",
							asset = "art",
							sides = { "top", "bottom" } :: { "top" | "right" | "bottom" | "left" },
							thickness = 4,
							margin = 8,
						} :: FixtureThemeTypes.SkinLayer,
						{
							kind = "plaque" :: "plaque",
							asset = "art",
							size = { w = 80, h = 20 },
							text = true,
							textInsets = {
								left = 4,
								right = 4,
							},
						} :: FixtureThemeTypes.SkinLayer,
					},
				}
				local target, skin: any, sheet: any
				local stop = runtime.mount(function()
					target = ((runtime.constructors.TextButton :: unknown) :: TextButtonConstructor)({
						Text = "Captain",
					})
					skin = themes.skin(
						runtime,
						package,
						"control",
						{ types = engine.types, target = target :: GuiObject, label = "Captain" }
					)
					sheet = themes.createStyleSheet(runtime, package, { types = engine.types })
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						target :: unknown,
						skin,
						sheet,
					})
				end, engine.new("Folder"))
				Verify.expect((target:HasTag("facet-skin-caption"))):toBe(true)
				Verify.expect((skin:FindFirstChild("PlaqueCaption", true) :: any).Text):toBe("Captain")
				Verify.expect((skin:FindFirstChild("control1", true) :: any).ScaleType)
					:toBe(engine.types.Enum.ScaleType.Tile)
				Verify.expect((skin:FindFirstChild("control1", true) :: any).TileSize.X.Offset):toBe(8)
				Verify.expect((skin:FindFirstChild("control2bottom", true) :: any).AnchorPoint.Y):toBe(1)
				Verify.expect((skin:FindFirstChild("control1", true) :: any).ResampleMode)
					:toBe(engine.types.Enum.ResamplerMode.Pixelated)
				Verify.expect(style(sheet, ".facet-button::UIPadding").PaddingLeft.Offset):toBe(32)
				stop()
				runtime:dispose()
			end,
		})
		verifyHarness:case("preserves accessible media names native constraints and caller resource sharing", {
			id = "native_themes_media::native themes and media::preserves accessible media names native constraints and caller resource sharing",
			run = function()
				local engine, runtime, UI = setup()
				local loaded, released, activated = 0, 0, 0
				local resource = Compose.createSharedResource(function(): (FixtureMediaTypes.ImageResource, (() -> ())?)
					loaded += 1
					return {
						state = Compose.cell("ready" :: "loading" | "ready" | "failed"),
						value = Compose.cell("rbxassetid://21" :: string?),
					}, function()
						released += 1
					end
				end)
				local avatar: any, group: any, badge: any, mark: any
				local stop = runtime.mount(function()
					avatar = UI.Avatar({
						name = "Ada",
						presence = "online" :: "online",
						presenceLabel = "Disponible",
						diameter = 52,
						onActivate = function()
							activated += 1
						end,
					})
					group = UI.AvatarGroup({
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
					})
					badge = UI.Badge({ icon = "checkmark", name = "Verified" })
					mark = UI.StatusIndicator({
						form = "dash" :: "dash",
						cutout = true,
						Size = engine.types.UDim2.fromOffset(80, 12),
					})
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						avatar :: unknown,
						group,
						badge,
						mark,
					})
				end, engine.new("Folder"))
				Verify.expect((avatar:GetAttribute("AccessibleLabel"))):toBe("Ada, Disponible")
				Verify.expect(avatar.Size.X.Offset):toBe(52)
				Verify.expect(avatar.Selectable):toBe(true)
				avatar.Activated.fire()
				Verify.expect(activated):toBe(1)
				Verify.expect((group:FindFirstChild("Overflow") :: any):GetAttribute("AccessibleLabel") :: any)
					:toBe("Otra persona")
				Verify.expect((group:FindFirstChild("Overflow") :: any).Text):toBe("…")
				Verify.expect(loaded):toBe(1)
				Verify.expect(((group:FindFirstChild("a") :: any):FindFirstChild("Initials") :: any).Visible)
					:toBe(false)
				Verify.expect((avatar:FindFirstChild("Initials") :: any).Visible):toBe(true)
				Verify.expect((badge:FindFirstChildWhichIsA("TextLabel"):GetAttribute("AccessibleLabel")))
					:toBe("Verified")
				Verify.expect((badge:HasTag("facet-badge"))):toBe(true)
				Verify.expect((badge:FindFirstChildWhichIsA("TextLabel"):HasTag("facet-badge"))):toBe(false)
				Verify.expect(badge:FindFirstChildWhichIsA("UIListLayout").VerticalAlignment)
					:toBe(engine.types.Enum.VerticalAlignment.Center)
				local constraint = mark:FindFirstChildWhichIsA("UIAspectRatioConstraint")
				Verify.expect(constraint.AspectRatio):toBe(3)
				Verify.expect(constraint.AspectType):toBe(engine.types.Enum.AspectType.FitWithinMaxSize)
				Verify.expect((mark:FindFirstChild("Cutout") :: any).BorderStrokePosition)
					:toBe(engine.types.Enum.BorderStrokePosition.Inner)
				stop()
				Verify.expect(released):toBe(1)
				runtime:dispose()
			end,
		})

		verifyHarness:case("follows a bound badge corner radius", {
			id = "native_themes_media::native themes and media::follows a bound badge corner radius",
			run = function()
				local engine, runtime, UI = setup()
				local corners = Compose.cell("rounded" :: "capsule" | "rounded" | "square" | number)
				local badge: any
				local stop = runtime.mount(function()
					badge = UI.Badge({ label = "New", corners = corners })
					return badge
				end, engine.new("Folder"))
				local corner = badge:FindFirstChildWhichIsA("UICorner")
				Verify.expect(corner.CornerRadius.Offset):toBe(8)
				corners:set("square")
				Verify.expect(corner.CornerRadius.Offset):toBe(0)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("rejects malformed media policy and retains valid reactive captions", {
			id = "native_themes_media::native themes and media::rejects malformed media policy and retains valid reactive captions",
			run = function()
				for _, build in
					{
						function(UI: typeof(media(nil :: any)))
							return UI.Badge({ label = 3 } :: any)
						end,
						function(UI: typeof(media(nil :: any)))
							return UI.Badge({ icon = "checkmark" })
						end,
						function(UI: typeof(media(nil :: any)))
							return UI.AvatarGroup({ items = {}, overflow = "unexpected" } :: any)
						end,
						function(UI: typeof(media(nil :: any)))
							return UI.AvatarGroup({ items = { { id = "a", name = "A" }, { id = "a", name = "B" } } })
						end,
						function(UI: typeof(media(nil :: any)))
							return UI.StatusIndicator({ count = 1, max = -1 })
						end,
					}
				do
					local engine, runtime, UI = setup()
					local ok = pcall(function()
						runtime.mount(function()
							return build(UI)
						end, engine.new("Folder"))
					end)
					Verify.expect(ok):toBe(false)
					runtime:dispose()
				end
				local engine, runtime, UI = setup()
				local caption = Compose.cell("Ready")
				local stop, badge: any = runtime.mount(function()
					return UI.Badge({ label = caption })
				end, engine.new("Folder"))
				Verify.expect((pcall(function()
					caption:set(3 :: any)
				end))):toBe(false)
				caption:set("Recovered")
				Verify.expect(badge.Text):toBe("Recovered")
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("keeps circular progress endpoints bounded and theme metrics reactive", {
			id = "native_themes_media::native themes and media::keeps circular progress endpoints bounded and theme metrics reactive",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local package = Compose.cell(themes.neutralPackage())
				local UI = media(context(Compose, runtime, { types = engine.types, theme = package }))
				local value = Compose.cell(0)
				local stop, node: any = runtime.mount(function()
					return UI.ProgressView({ presentation = "circular" :: "circular", value = value })
				end, engine.new("Folder"))
				local circle = node:FindFirstChild("Indicator", true)
				local fill, track = circle:FindFirstChild("RingFill"), circle:FindFirstChild("RingTrack")
				Verify.expect(fill.ClassName):toBe("Path2D")
				Verify.expect(track.ClassName):toBe("Path2D")
				Verify.expect(#circle:GetChildren()):toBe(2)
				Verify.expect(fill.Visible):toBe(false)
				Verify.expect(#track:GetControlPoints()):toBe(9)
				value:set(0.5)
				Verify.expect(fill.Visible):toBe(true)
				local half = fill:GetControlPoints()
				Verify.expect(#half):toBe(5)
				Verify.expect(half[1].Position.X.Scale):toBeCloseTo(0.5, 1e-4)
				Verify.expect(half[1].Position.Y.Scale):toBeCloseTo(3 / 64, 1e-4)
				Verify.expect(half[5].Position.X.Scale):toBeCloseTo(0.5, 1e-4)
				Verify.expect(half[5].Position.Y.Scale):toBeCloseTo(1 - 3 / 64, 1e-4)
				Verify.expect(half[1].RightTangent.X.Scale > 0):toBe(true)
				value:set(1)
				local full = fill:GetControlPoints()
				Verify.expect(#full):toBe(9)
				Verify.expect(full[9].Position.X.Scale):toBeCloseTo(full[1].Position.X.Scale, 1e-4)
				Verify.expect(full[9].Position.Y.Scale):toBeCloseTo(full[1].Position.Y.Scale, 1e-4)
				local nextPackage = themes.neutralPackage()
				nextPackage.metrics.controls.progress.circularSize = 48
				nextPackage.metrics.controls.progress.circularThickness = 6
				package:set(nextPackage)
				Verify.expect(circle.Size.X.Offset):toBe(48)
				Verify.expect(fill.Thickness):toBe(6)
				Verify.expect(track.Thickness):toBe(6)
				Verify.expect(fill:GetControlPoints()[1].Position.Y.Scale):toBeCloseTo(6 / 96, 1e-4)
				stop()
				runtime:dispose()
			end,
		})
		verifyHarness:case("keeps native semantic icons reactive with pixel resampling and metric sizing", {
			id = "native_themes_media::native themes and media::keeps native semantic icons reactive with pixel resampling and metric sizing",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local package = Compose.cell(themes.neutralPackage())
				local ctx = context(Compose, runtime, { types = engine.types, theme = package })
				local UI = media(ctx)
				local stop, root: any = runtime.mount(function()
					return UI.Label({ title = "Find", icon = "facet:search" })
				end, engine.new("Folder"))
				local icon = root:FindFirstChildWhichIsA("ImageLabel")
				Verify.expect(string.match(icon.Image, "^rbxassetid://") ~= nil):toBe(true)
				local nextPackage = themes.neutralPackage()
				assert(nextPackage.icons)["facet:search"] = { default = "search", disabled = "dim" }
				assert(nextPackage.assets).search = { content = "rbxassetid://23" }
				assert(nextPackage.assets).dim = { content = "rbxassetid://24" }
				nextPackage.metrics.controlSizes.regular.iconSize = 28
				nextPackage.identity.rendering = "pixel"
				package:set(nextPackage)
				Verify.expect(icon.Image):toBe("rbxassetid://23")
				Verify.expect(icon.Size.X.Offset):toBe(28)
				Verify.expect(icon.ResampleMode):toBe(engine.types.Enum.ResamplerMode.Pixelated)
				Verify.expect((themes.resolveIcon(nextPackage, "facet:search", "disabled"))):toBe("rbxassetid://24")
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("preserves full size progress art endcaps centers and fill direction", {
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
				local selected = Compose.cell(package)
				local UI = media(context(Compose, runtime, { types = engine.types, theme = selected }))
				local value = Compose.cell(0.25)
				local stop, root: any = runtime.mount(function()
					return UI.ProgressView({ value = value, thickness = 36 })
				end, engine.new("Folder"))
				local fill = root:FindFirstChild("Fill1", true)
				Verify.expect(fill.AnchorPoint.X):toBe(1)
				Verify.expect(fill.Size.X.Scale):toBe(0.25)
				fill.AbsoluteSize = engine.types.Vector2.new(25, 6)
				fill:FindFirstChild("SkinBoundary").AbsoluteSize = engine.types.Vector2.new(1, 1)
				Verify.expect(fill:FindFirstChild("SkinBoundary").Size):toBe(engine.types.UDim2.fromOffset(1, 1))
				Verify.expect(fill:FindFirstChild("Skin", true).Size.X.Scale):toBe(4)
				Verify.expect(fill:FindFirstChild("SkinBounds", true).Size.X.Offset):toBe(25)
				Verify.expect(root:FindFirstChild("barCap-start", true).Position.X.Scale):toBe(1)
				Verify.expect(root:FindFirstChild("barCap-end", true).Image):toBe("rbxassetid://3")
				Verify.expect(root:FindFirstChild("barCenter", true).Size.X.Offset):toBe(36)
				value:set(0.5)
				fill.AbsoluteSize = engine.types.Vector2.new(50, 6)
				Verify.expect(fill:FindFirstChild("Skin", true).Size.X.Scale):toBe(2)
				Verify.expect(fill:FindFirstChild("SkinBounds", true).Size.X.Offset):toBe(50)
				local nextPackage = table.clone(package)
				nextPackage.chrome = table.clone(package.chrome)
				assert(nextPackage.chrome).barFill =
					{ kind = "nineSlice" :: "nineSlice", asset = "fill", direction = "btt" :: "btt" }
				selected:set(nextPackage)
				Verify.expect(fill.AnchorPoint.Y):toBe(1)
				Verify.expect(fill.Size.Y.Scale):toBe(0.5)
				Verify.expect(root:FindFirstChild("barCap-start", true).Position.Y.Scale):toBe(1)
				stop()
				runtime:dispose()
			end,
		})
		verifyHarness:case("applies rich native skin slots to editable fields toggles steppers and sliders", {
			id = "native_themes_media::native themes and media::applies rich native skin slots to editable fields toggles steppers and sliders",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local package = themes.neutralPackage()
				package.assets = { art = { content = "rbxassetid://30" }, selected = { content = "rbxassetid://31" } }
				for _, slot in
					{ "field", "toggleTrack", "toggleKnob", "stepperPlate", "sliderTrack", "sliderThumb", "barFill" }
				do
					assert(package.chrome)[slot] =
						{ kind = "nineSlice" :: "nineSlice", asset = { default = "art", selected = "selected" } }
				end
				local UI = require("../src").controls(runtime, { types = engine.types, theme = package })
				local active = Compose.cell(false)
				local field: any, toggle: any, stepper, slider
				local stop = runtime.mount(function()
					field = UI.TextInput({ value = Compose.cell("Ada"), label = "Name" })
					toggle = UI.Toggle({ value = active })
					stepper = UI.Stepper({ value = Compose.cell(2), min = 0, max = 10 })
					slider = UI.Slider({ value = Compose.cell(0.5), min = 0, max = 1 })
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						field :: unknown,
						toggle,
						stepper,
						slider,
					})
				end, engine.new("Folder"))
				for slot, root in
					{
						field = field,
						toggleTrack = toggle,
						toggleKnob = toggle,
						stepperPlate = stepper,
						sliderTrack = slider,
						sliderThumb = slider,
						barFill = slider,
					}
				do
					Verify.expect(
						(assert((root :: GuiObject):FindFirstChild((slot :: string) .. "1", true)) :: ImageLabel).Image
					)
						:toBe("rbxassetid://30")
				end
				Verify.expect((field:FindFirstChild("Field", true) :: any).Text):toBe("Ada")
				Verify.expect((field:FindFirstChild("Input", true) :: any):HasTag("facet-skinned") :: any):toBe(true)
				active:set(true)
				Verify.expect((toggle:FindFirstChild("toggleTrack1", true) :: any).Image):toBe("rbxassetid://31")
				Verify.expect((toggle:FindFirstChild("toggleKnob1", true) :: any).Image):toBe("rbxassetid://31")
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("uses native shadows with reactive theme parameters and Compose disposal", {
			id = "native_themes_media::native themes and media::uses native shadows with reactive theme parameters and Compose disposal",
			run = function()
				local engine, runtime = setup()
				local package = themes.neutralPackage()
				assert(package.chrome).control = { kind = "native" :: "native", shadow = "raised" }
				local selected = Compose.cell(package)
				local target
				local stop = runtime.mount(function()
					target = ((runtime.constructors.TextButton :: unknown) :: TextButtonConstructor)({ Text = "Play" })
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
				local shadow = target:FindFirstChild("ChromeShadow") :: FixtureShadow
				Verify.expect(shadow.ClassName):toBe("UIShadow")
				Verify.expect(shadow.BlurRadius.Offset):toBe(14)
				Verify.expect(shadow.Offset.Y.Offset):toBe(3)
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
				Verify.expect((target:FindFirstChild("ChromeShadow"))):toBe(shadow)
				Verify.expect(shadow.BlurRadius.Offset):toBe(16)
				Verify.expect(shadow.Transparency):toBe(0.28)
				selected:set(themes.neutralPackage())
				Verify.expect(shadow.Enabled):toBe(false)
				selected:set(nextPackage)
				Verify.expect((target:FindFirstChild("ChromeShadow"))):toBe(shadow)
				Verify.expect(shadow.Enabled):toBe(true)
				stop()
				Verify.expect((shadow.isDestroyed())):toBe(true)
				runtime:dispose()
			end,
		})
		verifyHarness:case("skips static empty skin graphs while retaining later reactive art and shadows", {
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
				Verify.expect(counters.watchRuns):toBe(0)
				Verify.expect(counters.formulaRecomputations):toBe(0)
				Verify.expect(#root:GetChildren()):toBe(0)
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
				Verify.expect(counters.watchRuns):toBe(0)
				Verify.expect(counters.formulaRecomputations):toBe(0)
				Verify.expect(root:FindFirstChild("ChromeShadow").BlurRadius.Offset):toBe(14)
				stop()
				local selected = Compose.cell(themes.neutralPackage())
				stop, root = runtime.mount(function()
					return themes.skin(runtime, selected, "control", { types = engine.types })
				end, engine.new("Folder"))
				Verify.expect(#root:GetChildren()):toBe(0)
				local art = themes.neutralPackage()
				assert(art.assets).image = { content = "rbxassetid://30" }
				assert(art.chrome).control = { kind = "nineSlice" :: "nineSlice", asset = "image", shadow = "raised" }
				selected:set(art)
				Verify.expect(root:FindFirstChild("control1").Image):toBe("rbxassetid://30")
				Verify.expect(root:FindFirstChild("ChromeShadow") ~= nil):toBe(true)
				selected:set(themes.neutralPackage())
				Verify.expect(#root:GetChildren()):toBe(2)
				Verify.expect(root:FindFirstChild("control1").Visible):toBe(false)
				Verify.expect(root:FindFirstChild("ChromeShadow").Enabled):toBe(false)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("uses Button interaction state for semantic icon variants", {
			id = "native_themes_media::native themes and media::uses Button interaction state for semantic icon variants",
			run = function()
				local engine, runtime = setup()
				local package = themes.neutralPackage()
				assert(package.icons)["facet:search"] =
					{ default = "rest", hover = "hot", pressed = "press", selected = "selected", disabled = "disabled" }
				for name, id in { rest = 1, hot = 2, press = 3, selected = 4, disabled = 5 } :: { [string]: number } do
					assert(package.assets)[name] = { content = "rbxassetid://" .. id }
				end
				local UI = require("../src").controls(runtime, { types = engine.types, theme = package })
				local selected, enabled = Compose.cell(false), Compose.cell(true)
				local stop, button: any = runtime.mount(function()
					return UI.Button({ icon = "facet:search", label = "Find", selected = selected, enabled = enabled })
				end, engine.new("Folder"))
				local icon = button:FindFirstChild("LeadingIcon", true)
				Verify.expect(icon.Image):toBe("rbxassetid://1")
				button.GuiState = engine.types.Enum.GuiState.Hover
				Verify.expect(icon.Image):toBe("rbxassetid://2")
				button.GuiState = engine.types.Enum.GuiState.Press
				Verify.expect(icon.Image):toBe("rbxassetid://3")
				button.GuiState = engine.types.Enum.GuiState.Idle
				selected:set(true)
				Verify.expect(icon.Image):toBe("rbxassetid://4")
				enabled:set(false)
				Verify.expect(icon.Image):toBe("rbxassetid://5")
				stop()
				runtime:dispose()
			end,
		})
		verifyHarness:case("preloads the Compose owned ImageLabel after its source binding settles", {
			id = "native_themes_media::native themes and media::preloads the Compose owned ImageLabel after its source binding settles",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local environment = getfenv(media)
				local originalTask = environment.task
				local pending = {}
				environment.task = {
					defer = function(callback)
						local thread = coroutine.create(callback)
						table.insert(pending, thread)
						return thread
					end,
					cancel = function(thread)
						coroutine.close(thread)
					end,
				}
				local preloaded = {}
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
					return UI.AsyncImage({ source = source })
				end, engine.new("Folder"))
				Verify.expect(#preloaded):toBe(0)
				Verify.expect((coroutine.resume(pending[1]))):toBe(true)
				local image = root:FindFirstChild("Image")
				Verify.expect(preloaded[1]):toBe(image)
				Verify.expect(image.Image):toBe("rbxassetid://10")
				Verify.expect(image.Visible):toBe(true)
				source:set("rbxassetid://20")
				Verify.expect((coroutine.resume(pending[2]))):toBe(true)
				Verify.expect(preloaded[2]):toBe(image)
				Verify.expect(image.Image):toBe("rbxassetid://20")
				stop()
				Verify.expect((image.isDestroyed())):toBe(true)
				environment.task = originalTask
				runtime:dispose()
			end,
		})

		verifyHarness:case("preserves fractional segmented meter fill and mounted identities", {
			id = "native_themes_media::native themes and media::preserves fractional segmented meter fill and mounted identities",
			run = function()
				local engine, runtime, UI = setup()
				local value = Compose.cell(0.625)
				local stop, meter: any = runtime.mount(function()
					return UI.ProgressView({ value = value, segments = 4 })
				end, engine.new("Folder"))
				local third = meter:FindFirstChild("Fill3", true)
				Verify.expect(third.Size.X.Scale):toBeCloseTo(0.125, 1e-4)
				Verify.expect(meter:FindFirstChild("Fill4", true).Size.X.Scale):toBe(0)
				value:set(0.75)
				Verify.expect((meter:FindFirstChild("Fill3", true))):toBe(third)
				Verify.expect(third.Size.X.Scale):toBeCloseTo(0.25, 1e-4)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("holds damage trails then settles and snaps immediately on healing", {
			id = "native_themes_media::native themes and media::holds damage trails then settles and snaps immediately on healing",
			run = function()
				local engine, runtime, UI = setup()
				local value = Compose.cell(1)
				local stop, meter: any = runtime.mount(function()
					return UI.ProgressView({ value = value, trail = { delay = 0.2, duration = 0.3 } })
				end, engine.new("Folder"))
				local trail = meter:FindFirstChild("Trail", true)
				value:set(0.5)
				engine.heartbeat.fire(0.1)
				Verify.expect(trail.Size.X.Scale):toBe(1)
				engine.heartbeat.fire(0.25)
				Verify.expect(trail.Size.X.Scale):toBeCloseTo(0.75, 1e-4)
				engine.heartbeat.fire(0.2)
				Verify.expect(trail.Size.X.Scale):toBeCloseTo(0.5, 1e-4)
				Verify.expect((engine.heartbeat.count())):toBe(0)
				value:set(0.25)
				value:set(0.4)
				Verify.expect(trail.Size.X.Scale):toBeCloseTo(0.4, 1e-4)
				Verify.expect((engine.heartbeat.count())):toBe(0)
				value:set(0.1)
				engine.heartbeat.fire(0.35)
				Verify.expect(trail.Size.X.Scale):toBeCloseTo(0.25, 1e-4)
				value:set(0.2)
				Verify.expect(trail.Size.X.Scale):toBeCloseTo(0.2, 1e-4)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("centers circular readouts when native text bounds fit the ring", {
			id = "native_themes_media::native themes and media::centers circular readouts when native text bounds fit the ring",
			run = function()
				local engine, runtime, UI = setup()
				local value = Compose.cell(0.75)
				local stop, meter: any = runtime.mount(function()
					return UI.ProgressView({
						value = value,
						presentation = "circular" :: "circular",
						diameter = 120,
						showValue = true,
					})
				end, engine.new("Folder"))
				local readout, gauge = meter:FindFirstChild("Value", true), meter:FindFirstChild("Gauge", true)
				readout.TextBounds = engine.types.Vector2.new(38, 20)
				Verify.expect(readout.Text):toBe("75%")
				Verify.expect(readout.Parent):toBe(gauge)
				Verify.expect(readout.Position):toBe(engine.types.UDim2.new(0.5, 0, 0, 60))
				Verify.expect(readout.AnchorPoint):toBe(engine.types.Vector2.new(0.5, 0.5))
				Verify.expect(gauge.Size):toBe(engine.types.UDim2.fromOffset(120, 120))
				Verify.expect(gauge.ClipsDescendants):toBe(false)
				value:set(1)
				Verify.expect(readout.Text):toBe("100%")
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("rejects incompatible meter options before creating native nodes", {
			id = "native_themes_media::native themes and media::rejects incompatible meter options before creating native nodes",
			run = function()
				for
					_,
					spec: {
					value: number,
					segments: number?,
					presentation: "circular"?,
					diameter: number?,
					trail: { delay: typeof(-1)?, duration: number? }?,
				}
				in
					{
						{ value = 1, segments = 0 },
						{ value = 1, segments = 2.5 },
						{ value = 1, presentation = "circular" :: "circular", segments = 4 },
						{ value = 1, diameter = 120 },
						{ value = 1, trail = { delay = -1 } },
						{ value = 1, trail = { duration = 0 } },
					} :: {
						{
							value: number,
							segments: number?,
							presentation: "circular"?,
							diameter: number?,
							trail: { delay: typeof(-1)?, duration: number? }?,
						}
					}
				do
					local engine, runtime, UI = setup()
					local parent = engine.new("Folder")
					local count = #engine.made
					Verify.expect(function()
						runtime.mount(function()
							return UI.ProgressView(spec :: any)
						end, parent)
					end):toThrow()
					Verify.expect(#engine.made):toBe(count)
					Verify.expect((engine.heartbeat.count())):toBe(0)
					runtime:dispose()
				end
			end,
		})

		verifyHarness:case("cancels pending damage trails for reduced motion and releases their clock", {
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
					return UI.ProgressView({ value = value, trail = { delay = 0.2, duration = 0.3 } })
				end, engine.new("Folder"))
				local trail = meter:FindFirstChild("Trail", true)
				value:set(0.4)
				Verify.expect((engine.heartbeat.count())):toBe(1)
				reduced:set(true)
				Verify.expect(trail.Size.X.Scale):toBeCloseTo(0.4, 1e-4)
				Verify.expect((engine.heartbeat.count())):toBe(0)
				reduced:set(false)
				Verify.expect(trail.Size.X.Scale):toBeCloseTo(0.4, 1e-4)
				value:set(0.2)
				Verify.expect((engine.heartbeat.count())):toBe(1)
				stop()
				Verify.expect((engine.heartbeat.count())):toBe(0)
				value:set(0.8)
				Verify.expect((trail.isDestroyed())):toBe(true)
				runtime:dispose()
			end,
		})

		verifyHarness:case("moves oversized circular readouts below the ring using native text bounds", {
			id = "native_themes_media::native themes and media::moves oversized circular readouts below the ring using native text bounds",
			run = function()
				local engine, runtime, UI = setup()
				local stop, meter: any = runtime.mount(function()
					return UI.ProgressView({
						value = 1,
						presentation = "circular" :: "circular",
						diameter = 80,
						showValue = true,
						label = "Shield",
						format = function()
							return "10000 / 10000"
						end,
					})
				end, engine.new("Folder"))
				local readout, gauge = meter:FindFirstChild("Value", true), meter:FindFirstChild("Gauge", true)
				readout.TextBounds = engine.types.Vector2.new(190, 32)
				Verify.expect(readout.Text):toBe("10000 / 10000")
				Verify.expect(readout.Position):toBe(engine.types.UDim2.new(0.5, 0, 0, 88))
				Verify.expect(readout.AnchorPoint):toBe(engine.types.Vector2.new(0.5, 0))
				Verify.expect(readout.TextWrapped):toBe(false)
				Verify.expect(readout.TextXAlignment):toBe(engine.types.Enum.TextXAlignment.Center)
				Verify.expect(gauge.Size):toBe(engine.types.UDim2.fromOffset(190, 120))
				readout.TextBounds = engine.types.Vector2.new(40, 18)
				Verify.expect(readout.Position.Y.Offset):toBe(40)
				Verify.expect(gauge.Size):toBe(engine.types.UDim2.fromOffset(80, 80))
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("resets retained native image properties to valid defaults across theme recipes", {
			id = "native_themes_media::native themes and media::resets retained native image properties to valid defaults across theme recipes",
			run = function()
				local engine = engineLib.new()
				local create = engine.new
				local expected = {
					ScaleType = "EnumItem",
					ResampleMode = "EnumItem",
					TileSize = "UDim2",
					SliceCenter = "Rect",
					SliceScale = "number",
				}
				engine.new = function(className)
					local node = create(className)
					if className == "ImageLabel" then
						local mt = getmetatable(node)
						local assign = mt.__newindex
						mt.__newindex = function(target, key, value)
							if expected[key] then
								assert(
									typeof(value) == expected[key],
									`ImageLabel.{key} expected {expected[key]}, got {typeof(value)}`
								)
							end
							return assign(target, key, value)
						end
					end
					return node
				end
				local defaults = create("ImageLabel")
				local tiled = themes.neutralPackage()
				tiled.identity.rendering = "pixel"
				assert(tiled.assets).plate = { content = "rbxassetid://1" }
				assert(tiled.chrome).control =
					{ kind = "tile" :: "tile", asset = "plate", tileSize = { w = 24, h = 32 } }
				local sliced = themes.neutralPackage()
				assert(sliced.assets).plate =
					{ content = "rbxassetid://2", sliceCenter = { x0 = 3, y0 = 4, x1 = 30, y1 = 40 }, sliceScale = 2 }
				assert(sliced.chrome).control = { kind = "nineSlice" :: "nineSlice", asset = "plate" }
				local plain = themes.neutralPackage()
				assert(plain.assets).plate = { content = "rbxassetid://3" }
				assert(plain.chrome).control = { kind = "fill" :: "fill", asset = "plate" }
				local selected = Compose.cell(tiled)
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local ctx = context(Compose, runtime, { types = engine.types, theme = selected })
				local skin: any, icon
				local stop = runtime.mount(function()
					skin = themes.skin(runtime, selected, "control", { types = engine.types })
					icon = ctx.icon("facet:search")
					local children = { skin, icon }
					for _, slot in
						{
							"field",
							"toggleTrack",
							"toggleKnob",
							"stepperPlate",
							"sliderTrack",
							"sliderThumb",
							"barTrack",
							"barFill",
							"barCap",
							"barCenter",
						}
					do
						table.insert(children, themes.skin(runtime, selected, slot, { types = engine.types }))
					end
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)(children)
				end, create("Folder"))
				local plate = skin:FindFirstChild("control1", true)
				Verify.expect(plate.ResampleMode):toBe(engine.types.Enum.ResamplerMode.Pixelated)
				Verify.expect(plate.TileSize):toBe(engine.types.UDim2.fromOffset(24, 32))
				selected:set(sliced)
				Verify.expect((skin:FindFirstChild("control1", true))):toBe(plate)
				Verify.expect(plate.ScaleType):toBe(engine.types.Enum.ScaleType.Slice)
				Verify.expect(plate.SliceScale):toBe(2)
				Verify.expect(plate.ResampleMode):toBe(defaults.ResampleMode)
				Verify.expect(plate.TileSize):toBe(defaults.TileSize)
				selected:set(plain)
				Verify.expect((skin:FindFirstChild("control1", true))):toBe(plate)
				for property in expected do
					Verify.expect(plate[property]):toBe(defaults[property])
				end
				Verify.expect(icon.ResampleMode):toBe(defaults.ResampleMode)
				for _, name in
					{
						"pixel_quest",
						"fantasy_parchment",
						"classic_desktop",
						"compact_pointer",
						"fantasy_ornate",
						"glossy_mobile",
						"glossy_touch",
						"scifi_hud",
						"layered_test",
						"pixel_quest",
						"fantasy_parchment",
					}
				do
					local package = requireDynamic("../examples/themes/" .. name).build(themes)
					selected:set(package)
					Verify.expect(icon.ResampleMode):toBe(
						if package.identity.rendering == "pixel"
							then engine.types.Enum.ResamplerMode.Pixelated
							else defaults.ResampleMode
					)
				end
				stop()
				defaults:Destroy()
				runtime:dispose()
			end,
		})

		verifyHarness:case("rotates a smooth native circular arc with reduced motion and themed stroke colors", {
			id = "native_themes_media::native themes and media::rotates a smooth native circular arc with reduced motion and themed stroke colors",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local reduced, package = Compose.cell(false), Compose.cell(themes.neutralPackage())
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
					meter = UI.ProgressView({ presentation = "circular" :: "circular", diameter = 120, thickness = 4 })
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({ sheet :: unknown, meter })
				end, engine.new("Folder"))
				local arc = meter:FindFirstChild("RingFill", true)
				Verify.expect(arc.Thickness):toBe(4)
				Verify.expect(#arc:GetControlPoints()):toBe(3)
				Verify.expect(#((meter:FindFirstChild("Indicator") :: any):GetDescendants() :: any)):toBe(2)
				local before = arc:GetControlPoints()[1].Position
				engine.heartbeat.fire(0.1)
				Verify.expect(arc:GetControlPoints()[1].Position ~= before):toBe(true)
				reduced:set(true)
				before = arc:GetControlPoints()[1].Position
				engine.heartbeat.fire(0.1)
				Verify.expect(arc:GetControlPoints()[1].Position):toBe(before)
				engine.heartbeat.fire(0.1)
				Verify.expect(arc:GetControlPoints()[1].Position ~= before):toBe(true)
				local nextPackage = themes.neutralPackage()
				nextPackage.style.themes[1].colors.accent = { r = 0.7, g = 0.2, b = 0.1 }
				nextPackage.style.themes[1].colors.control = { r = 0.3, g = 0.4, b = 0.5 }
				nextPackage.style.themes[1].colors.contentSecondary = { r = 0.6, g = 0.6, b = 0.65 }
				package:set(nextPackage)
				Verify.expect(style(sheet, ".facet-progress-ring-fill").Color3)
					:toBe(engine.types.Color3.new(0.7, 0.2, 0.1))
				Verify.expect(style(sheet, ".facet-progress-ring-track").Color3)
					:toBe(engine.types.Color3.new(0.3, 0.4, 0.5))
				local secondary = nextPackage.style.themes[1].colors.contentSecondary
				Verify.expect(style(sheet, ".facet-type-caption").TextColor3)
					:toBe(engine.types.Color3.new(secondary.r, secondary.g, secondary.b))
				Verify.expect((meter:FindFirstChild("RingFill", true))):toBe(arc)
				stop()
				Verify.expect((arc.isDestroyed())):toBe(true)
				Verify.expect((engine.heartbeat.count())):toBe(0)
				runtime:dispose()
			end,
		})

		verifyHarness:case(
			"leaves unchanged native rules and running paint transitions untouched during theme updates",
			{
				id = "native_themes_media::native themes and media::leaves unchanged native rules and running paint transitions untouched during theme updates",
				run = function()
					local engine = engineLib.new()
					local create = engine.new
					local writes, transitions = {}, {}
					engine.new = function(className)
						local node = create(className)
						if className == "StyleRule" then
							local mt = getmetatable(node)
							local index, setProperties, setTransitions =
								mt.__index, node.SetProperties, node.SetPropertyTransitions
							local write = function(self, properties)
								writes[self] = (writes[self] or 0) + 1
								return setProperties(self, properties)
							end
							local timing = function(self, properties)
								transitions[self] = (transitions[self] or 0) + 1
								return setTransitions(self, properties)
							end
							mt.__index = function(self, key)
								return if key == "SetProperties"
									then write
									elseif key == "SetPropertyTransitions" then timing
									else index(self, key)
							end
						end
						return node
					end
					local runtime: ComposeRuntime = Roblox.createRuntime(engine)
					local package = themes.neutralPackage()
					local contributed: FixtureThemeTypes.RuleProperties = { ImageTransparency = 0.2 }
					package.rules = { { selector = ".game-icon", properties = contributed } }
					local selected = Compose.cell(package)
					local stop, sheet: any = runtime.mount(function()
						return themes.createStyleSheet(runtime, selected, { types = engine.types })
					end, create("Folder"))
					local contributedRule, typeRule, textRule
					for _, rule in sheet:GetChildren() do
						if rule.Selector == ".game-icon" then
							contributedRule = rule
						end
						if rule.Selector == ".facet-type-body" then
							typeRule = rule
						end
						if rule.Selector == ".facet-text" then
							textRule = rule
						end
					end
					local initialTiming = transitionOf(contributedRule, "ImageTransparency")
					table.clear(writes)
					table.clear(transitions)
					selected:set(table.clone(package))
					Verify.expect((next(writes))):toBe(nil)
					Verify.expect((next(transitions))):toBe(nil)
					contributed.ImageTransparency = 0.7
					selected:set(table.clone(package))
					Verify.expect(writes[contributedRule]):toBe(1)
					Verify.expect(writes[textRule]):toBe(nil)
					Verify.expect((next(transitions))):toBe(nil)
					Verify.expect(contributedRule:GetProperties().ImageTransparency):toBe(0.7)
					Verify.expect((transitionOf(contributedRule, "ImageTransparency"))):toBe(initialTiming)
					contributed.ImageTransparency = nil
					contributed.ImageColor3 = engine.types.Color3.new(0.1, 0.2, 0.3)
					selected:set(table.clone(package))
					Verify.expect(contributedRule:GetProperties().ImageTransparency):toBe(nil)
					Verify.expect((transitionOf(contributedRule, "ImageTransparency"))):toBe(nil)
					Verify.expect((transitionOf(contributedRule, "ImageColor3"))):toBe(initialTiming)
					Verify.expect(transitions[contributedRule]):toBe(1)
					table.clear(writes)
					table.clear(transitions)
					package.metrics.motion.normal = 0.4
					selected:set(table.clone(package))
					Verify.expect(transitionOf(contributedRule, "ImageColor3").Time):toBe(0.4)
					Verify.expect(sheet:GetAttribute("FacetMotionNormal").Time):toBe(0.4)
					Verify.expect((next(transitions))):toBe(nil)
					Verify.expect(writes[typeRule]):toBe(nil)
					Verify.expect(writes[textRule]):toBe(nil)
					stop()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case("uses authored selected contrast for native buttons and their mirrored captions", {
			id = "native_themes_media::native themes and media::uses authored selected contrast for native buttons and their mirrored captions",
			run = function()
				local engine, runtime = setup()
				local package = themes.neutralPackage()
				assert(package.style.themes[1].extra).controlSelected = { r = 45 / 255, g = 86 / 255, b = 65 / 255 }
				assert(package.style.themes[1].extra).onSelected = { r = 1, g = 1, b = 1 }
				local selected = Compose.cell(package)
				local stop, sheet: any = runtime.mount(function()
					return themes.createStyleSheet(runtime, selected, { types = engine.types })
				end, engine.new("Folder"))
				Verify.expect(style(sheet, ".facet-selected").BackgroundColor3)
					:toBe(engine.types.Color3.new(45 / 255, 86 / 255, 65 / 255))
				Verify.expect(style(sheet, ".facet-selected").TextColor3):toBe(engine.types.Color3.new(1, 1, 1))
				Verify.expect(style(sheet, ".facet-selected >> .facet-text").TextColor3)
					:toBe(engine.types.Color3.new(1, 1, 1))
				local dark = themes.neutralPackage()
				assert(dark.style.themes[1].extra).onSelected = { r = 0.1, g = 0.2, b = 0.1 }
				selected:set(dark)
				Verify.expect(style(sheet, ".facet-selected").TextColor3):toBe(engine.types.Color3.new(0.1, 0.2, 0.1))
				local fallback = themes.neutralPackage()
				selected:set(fallback)
				Verify.expect(style(sheet, ".facet-selected").TextColor3):toBe(style(sheet, ".facet-text").TextColor3)
				Verify.expect(style(sheet, ".facet-selected >> .facet-text").TextColor3)
					:toBe(style(sheet, ".facet-text").TextColor3)
				stop()
				runtime:dispose()
			end,
		})
		verifyHarness:case("shares selected contrast across rich disclosure titles and chevrons", {
			id = "native_themes_media::native themes and media::shares selected contrast across rich disclosure titles and chevrons",
			run = function()
				local engine, runtime = setup()
				local factory = require("../examples/virtual_monitors/theme")
				local package = factory.create(require("../src"), "Avatar")
				local palette, expanded = Compose.cell("Dark"), Compose.cell(false)
				local UI = controls(Compose, runtime, { types = engine.types, theme = package })
				local sheet: any, disclosure
				local stop = runtime.mount(function()
					sheet = themes.createStyleSheet(runtime, package, { types = engine.types, theme = palette })
					disclosure = UI.DisclosureGroup({
						label = "Appearance",
						description = "Choose an avatar color",
						expanded = expanded,
						content = function(): Instance
							return UI.Text({ text = "Controls" })
						end,
					})
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						sheet :: unknown,
						disclosure,
					})
				end, engine.new("Folder"))
				local header: any = disclosure:FindFirstChild("Header")
				Verify.expect((header:HasTag("facet-selected"))):toBe(false)
				Verify.expect((header:FindFirstChild("Title", true) :: any):HasTag("facet-text") :: any):toBe(true)
				Verify.expect((header:FindFirstChild("Description", true) :: any):HasTag("facet-text") :: any)
					:toBe(true)
				Verify.expect((header:FindFirstChild("LeadingIcon", true) :: any):HasTag("facet-icon") :: any)
					:toBe(true)
				expanded:set(true)
				Verify.expect((header:HasTag("facet-selected"))):toBe(true)
				for _, name in { "Dark", "Light" } do
					palette:set(name)
					local foreground = style(sheet, ".facet-selected").TextColor3
					Verify.expect(style(sheet, ".facet-selected >> .facet-text").TextColor3):toBe(foreground)
					Verify.expect(style(sheet, ".facet-selected >> .facet-icon").ImageColor3):toBe(foreground)
					Verify.expect(foreground == style(sheet, ".facet-text").TextColor3):toBe(false)
				end
				expanded:set(false)
				Verify.expect((header:HasTag("facet-selected"))):toBe(false)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("bounds idle skin slots and disposes every retained native owner", {
			id = "native_themes_media::native themes and media::bounds idle skin slots and disposes every retained native owner",
			run = function()
				local engine, runtime = setup()
				local package = themes.neutralPackage()
				assert(package.assets).image = { content = "rbxassetid://99" }
				local layers = {}
				for _ = 1, 24 do
					table.insert(layers, { kind = "fill" :: "fill", asset = "image" })
				end
				assert(package.chrome).control = { kind = "layered" :: "layered", layers = layers }
				local selected = Compose.cell(package)
				local stop, root: any = runtime.mount(function()
					return themes.skin(runtime, selected, "control", { types = engine.types })
				end, engine.new("Folder"))
				local initial = root:GetChildren()
				Verify.expect(#initial):toBe(24)
				selected:set(themes.neutralPackage())
				Verify.expect(#root:GetChildren()):toBe(16)
				local retained = 0
				for _, image in initial do
					if not image.isDestroyed() then
						retained += 1
						Verify.expect(image.Parent):toBe(root)
						Verify.expect(image.Visible):toBe(false)
					end
				end
				Verify.expect(retained):toBe(16)
				selected:set(package)
				local active = root:GetChildren()
				local reused = 0
				for _, image in active do
					if table.find(initial, image) then
						reused += 1
					end
					Verify.expect(image.Image):toBe("rbxassetid://99")
					Verify.expect(image.Visible):toBe(true)
				end
				Verify.expect(reused):toBe(16)
				stop()
				for _, image in initial do
					Verify.expect((image.isDestroyed())):toBe(true)
				end
				for _, image in active do
					Verify.expect((image.isDestroyed())):toBe(true)
				end
				selected:set(themes.neutralPackage())
				selected:set(package)
				runtime:dispose()
			end,
		})

		verifyHarness:case("retains bounded skin slots across frozen recipes while mutable art stays reactive", {
			id = "native_themes_media::native themes and media::retains bounded skin slots across frozen recipes while mutable art stays reactive",
			run = function()
				local engine, runtime = setup()
				local package = themes.neutralPackage()
				assert(package.assets).image = { content = "rbxassetid://99" }
				assert(package.chrome).control = { kind = "fill" :: "fill", asset = "image" }
				local frozen = assert(themes.define(package))
				local neutral = themes.neutralPackage()
				local selected, revision = Compose.cell(frozen), Compose.cell(0)
				local stop, root: any = runtime.mount(function()
					return themes.skin(runtime, function(use: Use)
						use(revision)
						return use(selected)
					end, "control", { types = engine.types })
				end, engine.new("Folder"))
				local image = root:FindFirstChild("control1")
				for _ = 1, 50 do
					selected:set(neutral)
					Verify.expect(image.Visible):toBe(false)
					selected:set(frozen)
					Verify.expect((root:FindFirstChild("control1"))):toBe(image)
					Verify.expect(image.Visible):toBe(true)
				end
				Verify.expect(#root:GetChildren()):toBe(1)
				table.freeze(package)
				selected:set(package)
				assert(package.assets).image.content = "rbxassetid://100"
				assert(package.chrome).control.kind = "tile" :: "tile"
				assert(package.chrome).control.tileSize = { w = 11, h = 12 }
				revision:set(1)
				Verify.expect(image.Image):toBe("rbxassetid://100")
				Verify.expect(image.ScaleType):toBe(engine.types.Enum.ScaleType.Tile)
				Verify.expect(image.TileSize):toBe(engine.types.UDim2.fromOffset(11, 12))
				selected:set(frozen)
				Verify.expect(image.Image):toBe("rbxassetid://99")
				Verify.expect(image.ScaleType):toBe(engine.types.Enum.ScaleType.Stretch)
				stop()
				Verify.expect((image.isDestroyed())):toBe(true)
				runtime:dispose()
			end,
		})

		verifyHarness:case("accepts the Virtual Monitors package without optional art sections", {
			id = "native_themes_media::native themes and media::accepts the Virtual Monitors package without optional art sections",
			run = function()
				local engine, runtime = setup()
				local factory = require("../examples/virtual_monitors/theme")
				for _, name in { "Discover", "Avatar" } do
					local package = factory.create(require("../src"), name)
					Verify.expect((next(package.assets or {}))):toBe(nil)
					Verify.expect(package.chrome.monitorPanel.kind):toBe("native")
					Verify.expect(package.chrome.monitorPanel.shadow):toBe("raised")
					Verify.expect((table.isfrozen(package))):toBe(true)
					local sheet: any
					local stop = runtime.mount(function()
						sheet = themes.createStyleSheet(runtime, package, { types = engine.types, theme = "Light" })
						return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
							sheet :: unknown,
							themes.skin(runtime, package, "control", { types = engine.types }),
						})
					end, engine.new("Folder"))
					Verify.expect(style(sheet, ".facet-button::UIPadding").PaddingLeft.Offset):toBe(12)
					Verify.expect(style(sheet, ".facet-selected").TextColor3):toBe(engine.types.Color3.new(1, 1, 1))
					stop()
				end
				runtime:dispose()
			end,
		})

		verifyHarness:case("shows the showValue readout beside a ProgressView endLabel", {
			id = "native_themes_media::native themes and media::shows the showValue readout beside a ProgressView endLabel",
			run = function()
				local engine, runtime, UI = setup()
				local stop, root: any = runtime.mount(function()
					return UI.ProgressView "Upload" { value = 0.5, showValue = true, endLabel = "End" }
				end, engine.new("Folder"))
				local texts = {}
				for _, node in root:GetDescendants() do
					if node:IsA("TextLabel") then
						texts[node.Text] = node
					end
				end
				Verify.expect(texts["50%"] ~= nil):toBe(true)
				Verify.expect(texts["End"] ~= nil):toBe(true)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("returns the Label root that api.md states, with and without an icon", {
			id = "native_themes_media::native themes and media::returns the Label root that api.md states, with and without an icon",
			run = function()
				local engine, runtime, UI = setup()
				local stop, root: any = runtime.mount(function()
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						UI.Text "Plain" { text = "Plain" } :: unknown,
						UI.Label "Iconic" { title = "Iconic", icon = "rbxassetid://1" },
					})
				end, engine.new("Folder"))
				local plain, iconic = root:FindFirstChild("Plain"), root:FindFirstChild("Iconic")
				Verify.expect(plain.ClassName):toBe("TextLabel")
				Verify.expect(iconic.ClassName):toBe("Frame")
				Verify.expect(iconic:FindFirstChildWhichIsA("TextLabel").Text):toBe("Iconic")
				local api = fs.readFile("docs/reference/api.md")
				Verify.expect(string.find(api, "`UI.Text(spec) -> TextLabel`", 1, true) ~= nil):toBe(true)
				Verify.expect(string.find(api, "`UI.Label(spec) -> Frame`", 1, true) ~= nil):toBe(true)
				Verify.expect(iconic:FindFirstChild("Title").ClassName):toBe("TextLabel")
				Verify.expect(iconic:FindFirstChild("Icon").ClassName):toBe("ImageLabel")
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("mounts the namespaced control fixtures with the current controls", {
			id = "native_themes_media::native themes and media::mounts the namespaced control fixtures with the current controls",
			run = function()
				local engine, runtime = setup()
				local Facet = require("../src")
				local gauge = require("../examples/themes/ornate_gauge")
				local custom = require("../examples/themes/custom_control")
				local ornate = assert(require("../examples/themes/fantasy_ornate").build(Facet.themes))
				local glossy = assert(require("../examples/themes/glossy_mobile").build(Facet.themes))
				Verify.expect(gauge.check(Facet.themes, ornate).ok):toBe(true)
				Verify.expect(custom.check(glossy).ok):toBe(true)
				local dial = gauge.resolve(ornate)
				Verify.expect(dial.height):toBe(56)
				Verify.expect(dial.ring):toBe(8)
				Verify.expect(dial.usedFallback.size or dial.usedFallback.ring or dial.usedFallback.needle):toBe(false)
				local track = custom.resolve(glossy)
				Verify.expect(track.height):toBe(28)
				Verify.expect(custom.resolve(nil).usedFallback.size):toBe(true)
				local UI = Facet.controls(runtime, { types = engine.types })
				local core = {
					Host = (runtime.constructors :: unknown) :: RobloxHost,
					types = engine.types,
				}
				local fraction = Compose.cell(0.25)
				local stop, root: any = runtime.mount(function()
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						gauge.blueprint(UI, core, dial, { id = "Boiler", fraction = fraction }) :: unknown,
						custom.blueprint(UI, core, track, "Meter"),
					})
				end, engine.new("Folder"))
				local needle = root:FindFirstChild("BoilerNeedle", true)
				Verify.expect(needle.Image):toBe(gauge.ART.needle)
				Verify.expect(needle.Position.X.Scale):toBe(0.25)
				fraction:set(0.75)
				Verify.expect(needle.Position.X.Scale):toBe(0.75)
				Verify.expect(root:FindFirstChild("BoilerDial", true).Size.Y.Offset):toBe(56)
				local meter = root:FindFirstChild("MeterTrack", true)
				Verify.expect(meter.Size.Y.Offset):toBe(28)
				Verify.expect((meter:HasTag("facet-control"))):toBe(true)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("skin art follows a host inset that code writes, not only one a style rule writes", {
			id = "native_themes_media::native themes and media::skin art follows a host inset that code writes, not only one a style rule writes",
			run = function()
				local engine = engineLib.new({ styleOnlySignals = true })
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local decorate = require("../src/ui/native_decoration")
				local Host = (runtime.constructors :: unknown) :: RobloxHost
				local stop, host: any = runtime.mount(function()
					return Host.Frame({ Name = "Panel", Host.UIPadding({}) })
				end, engine.new("Folder"))
				local boundary
				runtime.mount(function()
					boundary = decorate(Compose, runtime, engine.types, host, Host.Frame({ Name = "Skin" }))
					return boundary
				end, host)
				host.AbsoluteSize = engine.types.Vector2.new(200, 100)
				boundary.AbsoluteSize = engine.types.Vector2.new(1, 1)
				host:FindFirstChildWhichIsA("UIPadding").PaddingRight = engine.types.UDim.new(0, 24)
				host:FindFirstChildWhichIsA("UIPadding").PaddingBottom = engine.types.UDim.new(0, 24)
				local bounds: any = boundary:FindFirstChild("SkinBounds")
				Verify.expect(`{bounds.Position.X.Offset} {bounds.Position.Y.Offset}`):toBe("25 25")
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("skin art on a scrolling host stays pinned to the window, not the scrolled canvas", {
			id = "native_themes_media::native themes and media::skin art on a scrolling host stays pinned to the window, not the scrolled canvas",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local decorate = require("../src/ui/native_decoration")
				local Host = (runtime.constructors :: unknown) :: RobloxHost
				local stop, host: any = runtime.mount(function()
					return Host.ScrollingFrame({ Name = "Surface" })
				end, engine.new("Folder"))
				local boundary
				runtime.mount(function()
					boundary = decorate(Compose, runtime, engine.types, host, Host.Frame({ Name = "Skin" }))
					return boundary
				end, host)
				host.AbsoluteSize = engine.types.Vector2.new(300, 400)
				boundary.AbsoluteSize = engine.types.Vector2.new(1, 1)
				host.CanvasPosition = engine.types.Vector2.new(0, 48)
				Verify.expect(`{boundary.Position.X.Offset} {boundary.Position.Y.Offset} {boundary.Position.Y.Scale}`)
					:toBe("300 448 0")
				stop()
				runtime:dispose()
			end,
		})
	end)

	verifyHarness:suite("native Avatar and AvatarGroup per-input rules", function()
		local function inputWorld(touch: boolean)
			local engine = engineLib.new()
			local runtime: ComposeRuntime = Roblox.createRuntime(engine)
			local gui, input = engine.new("GuiService"), engine.new("UserInputService")
			input.TouchEnabled = touch
			input.MouseEnabled = not touch
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

		verifyHarness:case("lights only the avatar under the pointer and leaves passive faces out of input", {
			id = "native_themes_media::native Avatar and AvatarGroup per-input rules::lights only the avatar under the pointer and leaves passive faces out of input",
			run = function()
				local engine, runtime, UI = inputWorld(false)
				local screen = engine.new("ScreenGui")
				local stop = runtime.mount(function()
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						UI.Avatar "Passive" { name = "Pat Lane" } :: unknown,
						UI.Avatar "Ada" { name = "Ada Quill", onActivate = function() end },
						UI.Avatar "Bo" { name = "Bo Lane", onActivate = function() end },
					})
				end, screen)
				local passive, ada, bo = find(screen, "Passive"), find(screen, "Ada"), find(screen, "Bo")
				Verify.expect(passive.Interactable):toBe(false)
				Verify.expect(ada.Interactable):toBe(true)
				local adaRing, boRing = find(ada, "HoverRing"), find(bo, "HoverRing")
				Verify.expect((adaRing:HasTag("facet-avatar-hover"))):toBe(true)
				Verify.expect(adaRing.Transparency):toBe(1)
				ada.GuiState = engine.types.Enum.GuiState.Hover
				Verify.expect(adaRing.Transparency):toBe(0)
				Verify.expect(boRing.Transparency):toBe(1)
				Verify.expect((find(passive, "HoverRing"))):toBe(nil)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("keeps the touch overflow chip its own whole target clear of the stacked faces", {
			id = "native_themes_media::native Avatar and AvatarGroup per-input rules::keeps the touch overflow chip its own whole target clear of the stacked faces",
			run = function()
				local engine, runtime, UI = inputWorld(true)
				local screen = engine.new("ScreenGui")
				local roster = {}
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
				Verify.expect(padding < 0):toBe(true)
				Verify.expect(find(group, "p1").Interactable):toBe(false)
				Verify.expect(gap.LayoutOrder < chip.LayoutOrder and gap.LayoutOrder > find(group, "p3").LayoutOrder)
					:toBe(true)
				Verify.expect(gap.Size.X.Offset + 2 * padding > 0):toBe(true)
				local floor = chip:FindFirstChildWhichIsA("UISizeConstraint")
				Verify.expect(floor.MinSize):toBe(engine.types.Vector2.new(44, 44))
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("lets gamepad B pass through a selected overflow chip", {
			id = "native_themes_media::native Avatar and AvatarGroup per-input rules::lets gamepad B pass through a selected overflow chip",
			run = function()
				local engine, runtime, UI, gui = inputWorld(false)
				local screen = engine.new("ScreenGui")
				local calls = 0
				local stop = runtime.mount(function()
					return UI.AvatarGroup "Team" {
						items = { { id = "a", name = "A" }, { id = "b", name = "B" }, { id = "c", name = "C" } },
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
						Verify.expect(node.KeyCode == engine.types.Enum.KeyCode.ButtonB):toBe(false)
					end
				end
				chip.Activated.fire()
				Verify.expect(calls):toBe(1)
				stop()
				runtime:dispose()
			end,
		})
	end)
end
