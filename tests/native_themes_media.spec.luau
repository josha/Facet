--!strict
local t = require("./lib/testkit")
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
	local runtime = Roblox.createRuntime(engine)
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

t.describe("native themes and media", function()
	t.it("keeps native theme rules reactive without writing instance paint", function()
		local engine, runtime, UI = setup()
		local selected = Compose.cell(themes.neutralPackage())
		local sheet, label
		local stop = runtime.mount(function()
			sheet = themes.createStyleSheet(runtime, selected, { types = engine.types })
			label = UI.Text({ text = "Themed" })
			return runtime.constructors.Frame({
				sheet,
				runtime.constructors.StyleLink({ StyleSheet = Compose.static(sheet) }),
				label,
			})
		end, engine.new("Folder"))
		local nextTheme = themes.neutralPackage()
		nextTheme.style.themes[1].colors.content = { r = 0.1, g = 0.2, b = 0.3 }
		selected:set(nextTheme)
		t.expect(style(sheet, ".facet-text").TextColor3).toBe(engine.types.Color3.new(0.1, 0.2, 0.3))
		t.expect(label.Text).toBe("Themed")
		stop()
		t.expect(sheet.isDestroyed()).toBe(true)
		runtime:dispose()
	end)

	t.it("scales translucent theme surfaces by the player's background transparency preference", function()
		local engine, runtime = setup()
		local preference = Compose.cell(1)
		local sheet
		local stop = runtime.mount(function()
			sheet = themes.createStyleSheet(
				runtime,
				themes.neutralPackage(),
				{ types = engine.types, preferredTransparency = preference }
			)
			return sheet
		end, engine.new("Folder"))
		local authored = style(sheet, ".facet-scrim").BackgroundTransparency
		t.expect(authored > 0 and authored < 1).toBe(true)
		preference:set(0.5)
		t.expect(style(sheet, ".facet-scrim").BackgroundTransparency).toBe(authored * 0.5)
		t.expect(style(sheet, ".facet-skinned").BackgroundTransparency).toBe(1)
		preference:set(0)
		t.expect(style(sheet, ".facet-scrim").BackgroundTransparency).toBe(0)
		preference:set(0 / 0)
		t.expect(style(sheet, ".facet-scrim").BackgroundTransparency).toBe(authored)
		preference:set(1)
		t.expect(style(sheet, ".facet-scrim").BackgroundTransparency).toBe(authored)
		stop()
		runtime:dispose()
	end)

	t.it("retargets native theme paint with shared timing and disables motion without replacing rules", function()
		local engine, runtime = setup()
		local package = themes.neutralPackage()
		package.metrics.motion.normal = 0.32
		local light = table.clone(package.style.themes[1])
		light.name = "Light"
		light.colors = table.clone(light.colors)
		light.colors.surface = { r = 0.9, g = 0.9, b = 0.9 }
		light.colors.content = { r = 0.1, g = 0.1, b = 0.1 }
		light.extra = table.clone(light.extra or {})
		light.extra.onSelected = { r = 1, g = 1, b = 1 }
		package.style.themes = { package.style.themes[1], light }
		package = themes.define(package)
		local selection, reduced, explicit = Compose.cell("Dark"), Compose.cell(false), Compose.cell(nil)
		local stop, sheet = runtime.mount(function()
			return themes.createStyleSheet(runtime, package, {
				types = engine.types,
				theme = selection,
				reducedMotion = reduced,
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
		local timing = textRule:GetPropertyTransitions().TextColor3
		t.expect(timing.Time).toBe(0.32)
		t.expect(timing.EasingStyle).toBe(engine.types.Enum.EasingStyle.Quad)
		t.expect(surfaceRule:GetPropertyTransitions().BackgroundColor3).toBe(timing)
		t.expect(surfaceRule:GetPropertyTransitions().BackgroundTransparency).toBe(timing)
		t.expect(textRule:GetPropertyTransitions().TextSize).toBe(nil)
		selection:set("Light")
		t.expect(textRule:GetProperties().TextColor3).toBe(engine.types.Color3.new(0.1, 0.1, 0.1))
		t.expect(surfaceRule:GetProperties().BackgroundColor3).toBe(engine.types.Color3.new(0.9, 0.9, 0.9))
		selection:set("Dark")
		t.expect(textRule:GetPropertyTransitions().TextColor3).toBe(timing)
		t.expect(textRule:GetProperties().TextColor3).toBe(engine.types.Color3.new(236 / 255, 239 / 255, 245 / 255))
		t.expect(sheet:GetChildren()[1]).toBe(rules[1])
		t.expect(#sheet:GetChildren()).toBe(#rules)
		t.expect(engine.heartbeat.count()).toBe(0)
		reduced:set(true)
		t.expect(textRule:GetPropertyTransitions().TextColor3.Time).toBe(0)
		t.expect(surfaceRule:GetPropertyTransitions().BackgroundColor3.Time).toBe(0)
		selection:set("Light")
		t.expect(surfaceRule:GetProperties().BackgroundColor3).toBe(engine.types.Color3.new(0.9, 0.9, 0.9))
		reduced:set(false)
		local override = engine.types.TweenInfo.new(0.6, engine.types.Enum.EasingStyle.Linear)
		explicit:set(override)
		t.expect(surfaceRule:GetPropertyTransitions().BackgroundColor3).toBe(override)
		explicit:set(false)
		t.expect(textRule:GetPropertyTransitions().TextColor3.Time).toBe(0)
		stop()
		t.expect(textRule.isDestroyed()).toBe(true)
		t.expect(surfaceRule.isDestroyed()).toBe(true)
		selection:set("Dark")
		t.expect(engine.heartbeat.count()).toBe(0)
		runtime:dispose()
	end)

	t.it("adds and removes native rules through Compose while shallow-frozen packages stay reactive", function()
		local engine, runtime = setup()
		local package = themes.neutralPackage()
		local contributed = { BackgroundTransparency = 0.25 }
		package.rules = {}
		table.freeze(package)
		local revision = Compose.cell(0)
		local stop, sheet = runtime.mount(function()
			return themes.createStyleSheet(runtime, function(use)
				use(revision)
				return package
			end, { types = engine.types })
		end, engine.new("Folder"))
		local initial = sheet:GetChildren()
		table.insert(package.rules, { selector = ".game-added", properties = contributed })
		revision:set(1)
		t.expect(#sheet:GetChildren()).toBe(#initial + 1)
		local added = sheet:GetChildren()[#initial + 1]
		t.expect(added.Selector).toBe(".game-added")
		t.expect(added:GetProperties().BackgroundTransparency).toBe(0.25)
		t.expect(added:GetPropertyTransitions().BackgroundTransparency.Time).toBe(0.2)
		contributed.BackgroundTransparency = 0.75
		revision:set(2)
		t.expect(added:GetProperties().BackgroundTransparency).toBe(0.75)
		t.expect(sheet:GetChildren()[#initial + 1]).toBe(added)
		table.clear(package.rules)
		revision:set(3)
		t.expect(added.isDestroyed()).toBe(true)
		t.expect(#sheet:GetChildren()).toBe(#initial)
		for index, rule in initial do
			t.expect(sheet:GetChildren()[index]).toBe(rule)
		end
		stop()
		for _, rule in initial do
			t.expect(rule.isDestroyed()).toBe(true)
		end
		runtime:dispose()
	end)

	t.it("keeps theme skin layers and state asset swaps inside native Compose ownership", function()
		local engine, runtime = setup()
		local package = themes.neutralPackage()
		package.assets = {
			rest = { content = "rbxassetid://1", sliceCenter = { x0 = 4, y0 = 4, x1 = 20, y1 = 20 } },
			pressed = { content = "rbxassetid://2" },
			corner = { content = "rbxassetid://3" },
		}
		package.chrome.control = {
			kind = "layered",
			layers = {
				{ kind = "fill", asset = { default = "rest", pressed = "pressed" } },
				{ kind = "corners", asset = "corner", topLeft = "corner", topRight = "corner", size = 12 },
			},
		}
		local state = Compose.cell("default")
		local stop, node = runtime.mount(function()
			return themes.skin(runtime, package, "control", { types = engine.types, state = state })
		end, engine.new("Folder"))
		t.expect(#node:GetChildren()).toBe(5)
		t.expect(node:FindFirstChild("control2bottomRight").Image).toBe("rbxassetid://3")
		local image = node:FindFirstChild("control1")
		t.expect(image.Image).toBe("rbxassetid://1")
		t.expect(image.ScaleType).toBe(engine.types.Enum.ScaleType.Slice)
		state:set("pressed")
		t.expect(image.Image).toBe("rbxassetid://2")
		t.expect(image.ScaleType).toBe(engine.types.Enum.ScaleType.Stretch)
		stop()
		t.expect(image.isDestroyed()).toBe(true)
		runtime:dispose()
	end)

	t.it("shares caller resources directly through Compose and releases the final reference", function()
		local engine, runtime, UI = setup()
		local acquired, released = 0, 0
		local resource = Compose.createSharedResource(function()
			acquired += 1
			return { state = Compose.cell("ready"), value = Compose.cell("rbxassetid://7") }, function()
				released += 1
			end
		end)
		local first = runtime.mount(function()
			return UI.AsyncImage({ resource = resource })
		end, engine.new("Folder"))
		local second = runtime.mount(function()
			return UI.AsyncImage({ resource = resource })
		end, engine.new("Folder"))
		t.expect(acquired).toBe(1)
		first()
		t.expect(released).toBe(0)
		second()
		t.expect(released).toBe(1)
		runtime:dispose()
	end)

	t.it("preserves the shipped palette, typography and art packages as native inputs", function()
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
			local module = require("../examples/themes/" .. name)
			local package, report = module.build(themes)
			t.expect(report.ok).toBe(true)
			local stop, sheet = runtime.mount(function()
				return themes.createStyleSheet(runtime, package, { types = engine.types })
			end, engine.new("Folder"))
			t.expect(#sheet:GetChildren() > 30).toBe(true)
			stop()
		end
		runtime:dispose()
	end)

	t.it("keeps async completions stale after a source change or disposal", function()
		local engine, runtime, UI = setup()
		local source, requests, states = Compose.cell("first"), {}, {}
		local cancellations = 0
		local stop, root = runtime.mount(function()
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
		t.expect(root:FindFirstChild("Image").Visible).toBe(false)
		requests.second.resolve("right")
		t.expect(root:FindFirstChild("Image").Image).toBe("right")
		t.expect(root:FindFirstChild("Image").Visible).toBe(true)
		stop()
		local count = #states
		requests.second.reject("late")
		t.expect(#states).toBe(count)
		t.expect(cancellations).toBe(2)
		runtime:dispose()
	end)

	t.it("exposes failure content and retries when the source changes", function()
		local engine, runtime, UI = setup()
		local source = Compose.cell("broken")
		local stop, root = runtime.mount(function()
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
		t.expect(found).toBe(true)
		source:set("working")
		t.expect(root:FindFirstChild("Image").Visible).toBe(true)
		stop()
		runtime:dispose()
	end)

	t.it("clamps progress, counts badges and releases stage scenes with Compose", function()
		local engine, runtime, UI = setup()
		local progress = Compose.cell(0.25)
		local count = Compose.cell(120)
		local stage, bar, badge, released = nil, nil, nil, 0
		local stop = runtime.mount(function()
			bar = UI.ProgressView({ value = progress })
			badge = UI.StatusIndicator({ count = count, status = "success" })
			stage = UI.Stage({
				content = function(sceneRuntime, world)
					return sceneRuntime.mount(function()
						return sceneRuntime.constructors.Part "Model" {}
					end, world)
				end,
			})
			Compose.cleanup(function()
				released += 1
			end)
			return runtime.constructors.Frame({ bar, badge, stage })
		end, engine.new("Folder"))
		t.expect(bar:FindFirstChild("Fill1", true).Size.X.Scale).toBe(0.25)
		progress:set(2)
		t.expect(bar:FindFirstChild("Fill1", true).Size.X.Scale).toBe(1)
		t.expect(badge.Text).toBe("99+")
		t.expect(badge.AutomaticSize).toBe(engine.types.Enum.AutomaticSize.X)
		t.expect(badge:FindFirstChildWhichIsA("UISizeConstraint").MinSize.X).toBe(24)
		t.expect(badge:FindFirstChildWhichIsA("UIAspectRatioConstraint")).toBe(nil)
		count:set(3)
		t.expect(badge.Text).toBe("3")
		local model = stage:FindFirstChild("Model", true)
		t.expect(model.ClassName).toBe("Part")
		stop()
		t.expect(model.isDestroyed()).toBe(true)
		t.expect(released).toBe(1)
		runtime:dispose()
	end)
	t.it("preserves avatar initials presence rung changes and keyed roster identity", function()
		local engine, runtime, UI = setup()
		local rung, presence = Compose.cell("compact"), Compose.cell("online")
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
			return runtime.constructors.Frame({ avatar, group })
		end, engine.new("Folder"))
		t.expect(avatar:FindFirstChild("Initials").Text).toBe("ÉN")
		t.expect(avatar.Size.X.Offset).toBe(36)
		t.expect(avatar:FindFirstChild("Initials"):FindFirstChildWhichIsA("UITextSizeConstraint").MaxTextSize).toBe(14)
		t.expect(avatar.Selectable).toBe(false)
		presence:set("busy")
		rung:set("large")
		t.expect(avatar:GetAttribute("AccessibleLabel")).toBe("Émile Noël, busy")
		t.expect(avatar.Size.X.Offset).toBe(56)
		t.expect(avatar:FindFirstChild("Initials"):FindFirstChildWhichIsA("UITextSizeConstraint").MaxTextSize).toBe(22)
		t.expect(avatar:FindFirstChild("Presence"):HasTag("facet-status-error")).toBe(true)
		t.expect(group:HasTag("facet-avatar-stack")).toBe(true)
		local first = group:FindFirstChild("a")
		roster:set({
			{ id = "b", name = "Bo Lane" },
			{ id = "a", name = "Émile Changed" },
			{ id = "c", name = "Ada Quill" },
		})
		t.expect(group:FindFirstChild("a")).toBe(first)
		t.expect(first:FindFirstChild("Initials").Text).toBe("ÉC")
		t.expect(first.LayoutOrder).toBe(2)
		local overflow = group:FindFirstChild("Overflow")
		t.expect(overflow.Text).toBe("+1")
		overflow.Activated.fire()
		t.expect(selected).toBe(1)
		stop()
		runtime:dispose()
	end)

	t.it("animates skeletons with one shared Compose clock and honors reduced motion", function()
		local engine = engineLib.new()
		local runtime = Roblox.createRuntime(engine)
		local reduced = Compose.cell(false)
		local UI = media(context(Compose, runtime, { types = engine.types, reducedMotion = reduced }))
		local first, one = runtime.mount(function()
			return UI.Skeleton({ form = "line", lines = 3 })
		end, engine.new("Folder"))
		local listeners = engine.heartbeat.count()
		local second, two = runtime.mount(function()
			return UI.Skeleton({ form = "circle" })
		end, engine.new("Folder"))
		t.expect(engine.heartbeat.count()).toBe(listeners)
		t.expect(one:FindFirstChild("Placeholder3").Size.X.Scale).toBeCloseTo(0.6)
		engine.heartbeat.fire(0.4)
		local gradient = two:FindFirstChild("Shimmer", true)
		local previous = gradient.Offset.X
		first()
		engine.heartbeat.fire(0.2)
		t.expect(gradient.Offset.X > previous).toBe(true)
		reduced:set(true)
		t.expect(gradient.Enabled).toBe(false)
		previous = gradient.Offset.X
		engine.heartbeat.fire(0.3)
		t.expect(gradient.Offset.X).toBe(previous)
		reduced:set(false)
		engine.heartbeat.fire(0.2)
		t.expect(gradient.Enabled).toBe(true)
		t.expect(gradient.Offset.X ~= previous).toBe(true)
		second()
		runtime:dispose()
		t.expect(engine.heartbeat.count()).toBe(0)
	end)

	t.it("keeps indeterminate progress stepping and trails determinate decreases", function()
		local engine = engineLib.new()
		local runtime = Roblox.createRuntime(engine)
		local UI = media(context(Compose, runtime, { types = engine.types, reducedMotion = true }))
		local value, bar, busy = Compose.cell(0.8), nil, nil
		local stop = runtime.mount(function()
			bar = UI.ProgressView({ value = value, trail = { delay = 0.2, duration = 0.4 } })
			busy = UI.ProgressView({ presentation = "spinner" })
			return runtime.constructors.Frame({ bar, busy })
		end, engine.new("Folder"))
		local dot = busy:FindFirstChild("Segment1", true)
		local before = dot.BackgroundTransparency
		engine.heartbeat.fire(0.1)
		t.expect(dot.BackgroundTransparency).toBe(before)
		engine.heartbeat.fire(0.2)
		t.expect(dot.BackgroundTransparency ~= before).toBe(true)
		value:set(0.2)
		t.expect(bar:FindFirstChild("Trail", true).Size.X.Scale).toBeCloseTo(0.2)
		stop()
		runtime:dispose()
		t.expect(engine.heartbeat.count()).toBe(0)
	end)

	t.it("keeps badges and status shapes reactive without creating focus targets", function()
		local engine, runtime, UI = setup()
		local label, status, form = Compose.cell("Online"), Compose.cell("success"), Compose.cell("dot")
		local badge, indicator
		local stop = runtime.mount(function()
			badge = UI.Badge({ label = label, status = status })
			indicator = UI.StatusIndicator({ status = status, form = form, diameter = 16 })
			return runtime.constructors.Frame({ badge, indicator })
		end, engine.new("Folder"))
		t.expect(badge.Selectable).toBe(false)
		t.expect(indicator.Selectable).toBe(false)
		label:set("Away")
		status:set("warning")
		form:set("dash")
		t.expect(badge.Text).toBe("Away")
		t.expect(indicator:HasTag("facet-status-warning")).toBe(true)
		t.expect(indicator.Size.Y.Offset < indicator.Size.X.Offset).toBe(true)
		form:set("ring")
		local ring = indicator:FindFirstChild("Ring")
		t.expect(ring:HasTag("facet-status-ring")).toBe(true)
		t.expect(ring.BorderStrokePosition).toBe(engine.types.Enum.BorderStrokePosition.Inner)
		t.expect(ring.Thickness).toBe(3)
		t.expect(indicator:HasTag("facet-status-hollow")).toBe(true)
		form:set("dot")
		t.expect(indicator:FindFirstChild("Ring")).toBe(nil)
		t.expect(indicator:HasTag("facet-status-hollow")).toBe(false)
		stop()
		runtime:dispose()
	end)

	t.it("lets the skinned tag outrank every built-in control fill", function()
		local engine, runtime = setup()
		local stop, sheet = runtime.mount(function()
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
		t.expect(skinned > highest).toBe(true)
		stop()
		runtime:dispose()
	end)

	t.it("replaces a skin state map when a derived package overrides it", function()
		local basis = themes.neutralPackage()
		basis.assets = {
			a = { content = "rbxassetid://1" },
			b = { content = "rbxassetid://2" },
			c = { content = "rbxassetid://3" },
		}
		basis.chrome.control = { kind = "fill", asset = { default = "a", pressed = "b" } }
		local base = themes.define(basis)
		local derived = themes.define({
			base = base,
			identity = { id = "derived" },
			chrome = { control = { asset = { default = "c" } } },
		})
		t.expect(derived.chrome.control.asset.default).toBe("c")
		t.expect(derived.chrome.control.asset.pressed).toBe(nil)
		t.expect(derived.chrome.control.kind).toBe("fill")
	end)

	t.it("rejects malformed type roles, unknown shadow presets and unreadable selected labels", function()
		local typed = themes.neutralPackage()
		local roles = (typed.metrics.typography :: unknown) :: { [string]: unknown }
		roles.body = 5
		t.expect((select(2, themes.define(typed))).ok).toBe(false)
		local shadowed = themes.neutralPackage()
		shadowed.chrome = { control = { kind = "native", shadow = "floating" } }
		t.expect((select(2, themes.define(shadowed))).ok).toBe(false)
		local selected = themes.neutralPackage()
		selected.style.themes[1].extra = table.clone(selected.style.themes[1].extra or {})
		selected.style.themes[1].extra.controlSelected = { r = 0.9, g = 0.9, b = 0.92 }
		t.expect((select(2, themes.define(selected))).ok).toBe(false)
		local valid = themes.neutralPackage()
		valid.chrome = { control = { kind = "native", shadow = "raised" } }
		t.expect((select(2, themes.define(valid))).ok).toBe(true)
	end)

	t.it("rejects unreadable semantic color pairs and reports contributed theme coverage", function()
		local bad = themes.neutralPackage()
		bad.style.themes[1].colors.content = bad.style.themes[1].colors.surface
		local package, report = themes.define(bad)
		t.expect(package).toBe(nil)
		t.expect(report.ok).toBe(false)
		local needs = { { name = "custom:knob", section = "metrics.radii", kind = "number" } }
		t.expect(themes.checkCoverage(themes.neutralPackage(), needs).ok).toBe(false)
		local good = themes.neutralPackage()
		good.metrics.radii["custom:knob"] = 4
		t.expect(themes.checkCoverage(good, needs).ok).toBe(true)
	end)
	t.it("keeps compiled theme data immutable and rejects callbacks or malformed values", function()
		local definition = themes.neutralPackage()
		local package = themes.define(definition)
		t.expect(table.isfrozen(package.metrics.typography)).toBe(true)
		definition.metrics.typography.body.size = 23
		t.expect(package.metrics.typography.body.size).toBe(16)
		definition.rules =
			{ { selector = ".bad", properties = {
				Text = function()
					return "not data"
				end,
			} } }
		t.expect(select(2, themes.define(definition)).ok).toBe(false)
		t.expect(select(2, themes.define(false)).ok).toBe(false)
	end)

	t.it("preserves external cameras and forwards native viewport lighting", function()
		local engine, runtime, UI = setup()
		local camera = engine.new("Camera")
		local original = engine.new("Folder")
		camera.Parent = original
		local ambient = engine.types.Color3.new(0.2, 0.3, 0.4)
		local stop, stage = runtime.mount(function()
			return UI.Stage({ camera = camera, Ambient = ambient, LightDirection = engine.types.Vector3.new(1, -1, 0) })
		end, engine.new("Folder"))
		t.expect(stage.CurrentCamera).toBe(camera)
		t.expect(stage.Ambient).toBe(ambient)
		t.expect(camera.Parent).toBe(original)
		stop()
		t.expect(camera.isDestroyed()).toBe(false)
		runtime:dispose()
	end)

	t.it("uses native image framing and rounded avatar images", function()
		local engine, runtime, UI = setup()
		local avatar, image
		local stop = runtime.mount(function()
			avatar = UI.Avatar({ name = "Ada", image = "rbxassetid://1" })
			image = UI.AsyncImage({
				image = "rbxassetid://2",
				imageProperties = {
					ScaleType = engine.types.Enum.ScaleType.Crop,
					ResampleMode = engine.types.Enum.ResamplerMode.Pixelated,
				},
			})
			return runtime.constructors.Frame({ avatar, image })
		end, engine.new("Folder"))
		t.expect(avatar:FindFirstChild("Image", true):FindFirstChildWhichIsA("UICorner").CornerRadius.Scale).toBe(1)
		t.expect(image:FindFirstChild("Image").ScaleType).toBe(engine.types.Enum.ScaleType.Crop)
		t.expect(image:FindFirstChild("Image").ResampleMode).toBe(engine.types.Enum.ResamplerMode.Pixelated)
		stop()
		runtime:dispose()
	end)

	t.it("keeps plaques edges tiling pixel resampling and chrome insets native", function()
		local engine, runtime = setup()
		local package = themes.neutralPackage()
		package.identity.rendering = "pixel"
		package.assets.art = { content = "rbxassetid://10" }
		package.chrome.control = {
			kind = "layered",
			contentInsets = { top = 4, right = 20, bottom = 6, left = 20 },
			layers = {
				{ kind = "tile", asset = "art", tileSize = { w = 8, h = 8 } },
				{ kind = "edges", asset = "art", sides = { "top", "bottom" }, thickness = 4, margin = 8 },
				{
					kind = "plaque",
					asset = "art",
					size = { w = 80, h = 20 },
					text = true,
					textInsets = {
						left = 4,
						right = 4,
					},
				},
			},
		}
		local target, skin, sheet
		local stop = runtime.mount(function()
			target = runtime.constructors.TextButton({ Text = "Captain" })
			skin =
				themes.skin(runtime, package, "control", { types = engine.types, target = target, label = "Captain" })
			sheet = themes.createStyleSheet(runtime, package, { types = engine.types })
			return runtime.constructors.Frame({ target, skin, sheet })
		end, engine.new("Folder"))
		t.expect(target:HasTag("facet-skin-caption")).toBe(true)
		t.expect(skin:FindFirstChild("PlaqueCaption", true).Text).toBe("Captain")
		t.expect(skin:FindFirstChild("control1", true).ScaleType).toBe(engine.types.Enum.ScaleType.Tile)
		t.expect(skin:FindFirstChild("control1", true).TileSize.X.Offset).toBe(8)
		t.expect(skin:FindFirstChild("control2bottom", true).AnchorPoint.Y).toBe(1)
		t.expect(skin:FindFirstChild("control1", true).ResampleMode).toBe(engine.types.Enum.ResamplerMode.Pixelated)
		t.expect(style(sheet, ".facet-button::UIPadding").PaddingLeft.Offset).toBe(20)
		stop()
		runtime:dispose()
	end)
	t.it("preserves accessible media names native constraints and caller resource sharing", function()
		local engine, runtime, UI = setup()
		local loaded, released, activated = 0, 0, 0
		local resource = Compose.createSharedResource(function()
			loaded += 1
			return { state = Compose.cell("ready"), value = Compose.cell("rbxassetid://21") }, function()
				released += 1
			end
		end)
		local avatar, group, badge, mark
		local stop = runtime.mount(function()
			avatar = UI.Avatar({
				name = "Ada",
				presence = "online",
				presenceLabel = "Disponible",
				diameter = 52,
				onActivate = function()
					activated += 1
				end,
			})
			group = UI.AvatarGroup({
				items = {
					{ id = "a", name = "Ada", resource = resource },
					{ id = "b", name = "Bo", resource = resource },
					{ id = "c", name = "Cleo" },
				},
				max = 2,
				overflow = "ellipsis",
				overflowLabel = "Otra persona",
			})
			badge = UI.Badge({ icon = "checkmark", name = "Verified" })
			mark = UI.StatusIndicator({ form = "dash", cutout = true, Size = engine.types.UDim2.fromOffset(80, 12) })
			return runtime.constructors.Frame({ avatar, group, badge, mark })
		end, engine.new("Folder"))
		t.expect(avatar:GetAttribute("AccessibleLabel")).toBe("Ada, Disponible")
		t.expect(avatar.Size.X.Offset).toBe(52)
		t.expect(avatar.Selectable).toBe(true)
		avatar.Activated.fire()
		t.expect(activated).toBe(1)
		t.expect(group:FindFirstChild("Overflow"):GetAttribute("AccessibleLabel")).toBe("Otra persona")
		t.expect(group:FindFirstChild("Overflow").Text).toBe("…")
		t.expect(loaded).toBe(1)
		t.expect(group:FindFirstChild("a"):FindFirstChild("Initials").Visible).toBe(false)
		t.expect(avatar:FindFirstChild("Initials").Visible).toBe(true)
		t.expect(badge:FindFirstChildWhichIsA("TextLabel"):GetAttribute("AccessibleLabel")).toBe("Verified")
		t.expect(badge:HasTag("facet-badge")).toBe(true)
		t.expect(badge:FindFirstChildWhichIsA("TextLabel"):HasTag("facet-badge")).toBe(false)
		t.expect(badge:FindFirstChildWhichIsA("UIListLayout").VerticalAlignment)
			.toBe(engine.types.Enum.VerticalAlignment.Center)
		local constraint = mark:FindFirstChildWhichIsA("UIAspectRatioConstraint")
		t.expect(constraint.AspectRatio).toBe(3)
		t.expect(constraint.AspectType).toBe(engine.types.Enum.AspectType.FitWithinMaxSize)
		t.expect(mark:FindFirstChild("Cutout").BorderStrokePosition).toBe(engine.types.Enum.BorderStrokePosition.Inner)
		stop()
		t.expect(released).toBe(1)
		runtime:dispose()
	end)

	t.it("follows a bound badge corner radius", function()
		local engine, runtime, UI = setup()
		local corners = Compose.cell("rounded")
		local badge
		local stop = runtime.mount(function()
			badge = UI.Badge({ label = "New", corners = corners })
			return badge
		end, engine.new("Folder"))
		local corner = badge:FindFirstChildWhichIsA("UICorner")
		t.expect(corner.CornerRadius.Offset).toBe(8)
		corners:set("square")
		t.expect(corner.CornerRadius.Offset).toBe(0)
		stop()
		runtime:dispose()
	end)

	t.it("rejects malformed media policy and retains valid reactive captions", function()
		for _, build in
			{
				function(UI)
					return UI.Badge({ label = 3 })
				end,
				function(UI)
					return UI.Badge({ icon = "checkmark" })
				end,
				function(UI)
					return UI.AvatarGroup({ items = {}, overflow = "unexpected" })
				end,
				function(UI)
					return UI.AvatarGroup({ items = { { id = "a", name = "A" }, { id = "a", name = "B" } } })
				end,
				function(UI)
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
			t.expect(ok).toBe(false)
			runtime:dispose()
		end
		local engine, runtime, UI = setup()
		local caption = Compose.cell("Ready")
		local stop, badge = runtime.mount(function()
			return UI.Badge({ label = caption })
		end, engine.new("Folder"))
		t.expect(pcall(function()
			caption:set(3)
		end)).toBe(false)
		caption:set("Recovered")
		t.expect(badge.Text).toBe("Recovered")
		stop()
		runtime:dispose()
	end)

	t.it("keeps circular progress endpoints bounded and theme metrics reactive", function()
		local engine = engineLib.new()
		local runtime = Roblox.createRuntime(engine)
		local package = Compose.cell(themes.neutralPackage())
		local UI = media(context(Compose, runtime, { types = engine.types, theme = package }))
		local value = Compose.cell(0)
		local stop, node = runtime.mount(function()
			return UI.ProgressView({ presentation = "circular", value = value })
		end, engine.new("Folder"))
		local circle = node:FindFirstChild("Indicator", true)
		local fill, track = circle:FindFirstChild("RingFill"), circle:FindFirstChild("RingTrack")
		t.expect(fill.ClassName).toBe("Path2D")
		t.expect(track.ClassName).toBe("Path2D")
		t.expect(#circle:GetChildren()).toBe(2)
		t.expect(fill.Visible).toBe(false)
		t.expect(#track:GetControlPoints()).toBe(9)
		value:set(0.5)
		t.expect(fill.Visible).toBe(true)
		local half = fill:GetControlPoints()
		t.expect(#half).toBe(5)
		t.expect(half[1].Position.X.Scale).toBeCloseTo(0.5)
		t.expect(half[1].Position.Y.Scale).toBeCloseTo(3 / 64)
		t.expect(half[5].Position.X.Scale).toBeCloseTo(0.5)
		t.expect(half[5].Position.Y.Scale).toBeCloseTo(1 - 3 / 64)
		t.expect(half[1].RightTangent.X.Scale > 0).toBe(true)
		value:set(1)
		local full = fill:GetControlPoints()
		t.expect(#full).toBe(9)
		t.expect(full[9].Position.X.Scale).toBeCloseTo(full[1].Position.X.Scale)
		t.expect(full[9].Position.Y.Scale).toBeCloseTo(full[1].Position.Y.Scale)
		local nextPackage = themes.neutralPackage()
		nextPackage.metrics.controls.progress.circularSize = 48
		nextPackage.metrics.controls.progress.circularThickness = 6
		package:set(nextPackage)
		t.expect(circle.Size.X.Offset).toBe(48)
		t.expect(fill.Thickness).toBe(6)
		t.expect(track.Thickness).toBe(6)
		t.expect(fill:GetControlPoints()[1].Position.Y.Scale).toBeCloseTo(6 / 96)
		stop()
		runtime:dispose()
	end)
	t.it("keeps native semantic icons reactive with pixel resampling and metric sizing", function()
		local engine = engineLib.new()
		local runtime = Roblox.createRuntime(engine)
		local package = Compose.cell(themes.neutralPackage())
		local ctx = context(Compose, runtime, { types = engine.types, theme = package })
		local UI = media(ctx)
		local stop, root = runtime.mount(function()
			return UI.Label({ title = "Find", icon = "facet:search" })
		end, engine.new("Folder"))
		local icon = root:FindFirstChildWhichIsA("ImageLabel")
		t.expect(string.match(icon.Image, "^rbxassetid://") ~= nil).toBe(true)
		local nextPackage = themes.neutralPackage()
		nextPackage.icons["facet:search"] = { default = "search", disabled = "dim" }
		nextPackage.assets.search = { content = "rbxassetid://23" }
		nextPackage.assets.dim = { content = "rbxassetid://24" }
		nextPackage.metrics.controlSizes.regular.iconSize = 28
		nextPackage.identity.rendering = "pixel"
		package:set(nextPackage)
		t.expect(icon.Image).toBe("rbxassetid://23")
		t.expect(icon.Size.X.Offset).toBe(28)
		t.expect(icon.ResampleMode).toBe(engine.types.Enum.ResamplerMode.Pixelated)
		t.expect(themes.resolveIcon(nextPackage, "facet:search", "disabled")).toBe("rbxassetid://24")
		stop()
		runtime:dispose()
	end)

	t.it("preserves full size progress art endcaps centers and fill direction", function()
		local engine = engineLib.new()
		local runtime = Roblox.createRuntime(engine)
		local package = themes.neutralPackage()
		package.assets = {
			fill = { content = "rbxassetid://1" },
			start = { content = "rbxassetid://2" },
			finish = { content = "rbxassetid://3" },
			center = { content = "rbxassetid://4" },
		}
		package.chrome.barFill = { kind = "nineSlice", asset = "fill", direction = "rtl" }
		package.chrome.barCap =
			{ kind = "nineSlice", startAsset = "start", endAsset = "finish", size = { w = 28, h = 36 } }
		package.chrome.barCenter = { kind = "nineSlice", asset = "center", size = { w = 36, h = 28 } }
		local selected = Compose.cell(package)
		local UI = media(context(Compose, runtime, { types = engine.types, theme = selected }))
		local value = Compose.cell(0.25)
		local stop, root = runtime.mount(function()
			return UI.ProgressView({ value = value })
		end, engine.new("Folder"))
		local fill = root:FindFirstChild("Fill1", true)
		t.expect(fill.AnchorPoint.X).toBe(1)
		t.expect(fill.Size.X.Scale).toBe(0.25)
		fill.AbsoluteSize = engine.types.Vector2.new(25, 6)
		fill:FindFirstChild("SkinBoundary").AbsoluteSize = engine.types.Vector2.new(1, 1)
		t.expect(fill:FindFirstChild("SkinBoundary").Size).toBe(engine.types.UDim2.fromOffset(1, 1))
		t.expect(fill:FindFirstChild("Skin", true).Size.X.Scale).toBe(4)
		t.expect(fill:FindFirstChild("SkinBounds", true).Size.X.Offset).toBe(25)
		t.expect(root:FindFirstChild("barCap-start", true).Position.X.Scale).toBe(1)
		t.expect(root:FindFirstChild("barCap-end", true).Image).toBe("rbxassetid://3")
		t.expect(root:FindFirstChild("barCenter", true).Size.X.Offset).toBe(36)
		value:set(0.5)
		fill.AbsoluteSize = engine.types.Vector2.new(50, 6)
		t.expect(fill:FindFirstChild("Skin", true).Size.X.Scale).toBe(2)
		t.expect(fill:FindFirstChild("SkinBounds", true).Size.X.Offset).toBe(50)
		local nextPackage = table.clone(package)
		nextPackage.chrome = table.clone(package.chrome)
		nextPackage.chrome.barFill = { kind = "nineSlice", asset = "fill", direction = "btt" }
		selected:set(nextPackage)
		t.expect(fill.AnchorPoint.Y).toBe(1)
		t.expect(fill.Size.Y.Scale).toBe(0.5)
		t.expect(root:FindFirstChild("barCap-start", true).Position.Y.Scale).toBe(1)
		stop()
		runtime:dispose()
	end)
	t.it("applies rich native skin slots to editable fields toggles steppers and sliders", function()
		local engine = engineLib.new()
		local runtime = Roblox.createRuntime(engine)
		local package = themes.neutralPackage()
		package.assets = { art = { content = "rbxassetid://30" }, selected = { content = "rbxassetid://31" } }
		for _, slot in { "field", "toggleTrack", "toggleKnob", "stepperPlate", "sliderTrack", "sliderThumb", "barFill" } do
			package.chrome[slot] = { kind = "nineSlice", asset = { default = "art", selected = "selected" } }
		end
		local UI = require("../src").controls(runtime, { types = engine.types, theme = package })
		local active = Compose.cell(false)
		local field, toggle, stepper, slider
		local stop = runtime.mount(function()
			field = UI.TextInput({ value = Compose.cell("Ada") })
			toggle = UI.Toggle({ value = active })
			stepper = UI.Stepper({ value = Compose.cell(2), min = 0, max = 10 })
			slider = UI.Slider({ value = Compose.cell(0.5), min = 0, max = 1 })
			return runtime.constructors.Frame({ field, toggle, stepper, slider })
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
			t.expect(root:FindFirstChild(slot .. "1", true).Image).toBe("rbxassetid://30")
		end
		t.expect(field.Text).toBe("Ada")
		t.expect(field:HasTag("facet-skinned")).toBe(true)
		active:set(true)
		t.expect(toggle:FindFirstChild("toggleTrack1", true).Image).toBe("rbxassetid://31")
		t.expect(toggle:FindFirstChild("toggleKnob1", true).Image).toBe("rbxassetid://31")
		stop()
		runtime:dispose()
	end)

	t.it("uses native shadows with reactive theme parameters and Compose disposal", function()
		local engine, runtime = setup()
		local package = themes.neutralPackage()
		package.chrome.control = { kind = "native", shadow = "raised" }
		local selected = Compose.cell(package)
		local target
		local stop = runtime.mount(function()
			target = runtime.constructors.TextButton({ Text = "Play" })
			runtime.mount(function()
				return themes.skin(runtime, selected, "control", { types = engine.types, target = target })
			end, target)
			return target
		end, engine.new("Folder"))
		local shadow = target:FindFirstChild("ChromeShadow")
		t.expect(shadow.ClassName).toBe("UIShadow")
		t.expect(shadow.BlurRadius.Offset).toBe(14)
		t.expect(shadow.Offset.Y.Offset).toBe(3)
		local nextPackage = themes.neutralPackage()
		nextPackage.chrome.control = {
			kind = "native",
			shadow = { blurRadius = { offset = 16 }, transparency = 0.28, color = { r = 0.05, g = 0.42, b = 0.5 } },
		}
		selected:set(nextPackage)
		t.expect(target:FindFirstChild("ChromeShadow")).toBe(shadow)
		t.expect(shadow.BlurRadius.Offset).toBe(16)
		t.expect(shadow.Transparency).toBe(0.28)
		selected:set(themes.neutralPackage())
		t.expect(shadow.Enabled).toBe(false)
		selected:set(nextPackage)
		t.expect(target:FindFirstChild("ChromeShadow")).toBe(shadow)
		t.expect(shadow.Enabled).toBe(true)
		stop()
		t.expect(shadow.isDestroyed()).toBe(true)
		runtime:dispose()
	end)
	t.it("skips static empty skin graphs while retaining later reactive art and shadows", function()
		local engine, runtime = setup()
		Compose.setWorkCounters(true)
		Compose.resetWorkCounters()
		local stop, root = runtime.mount(function()
			return themes.skin(runtime, nil, "control", { types = engine.types })
		end, engine.new("Folder"))
		local counters = Compose.readWorkCounters()
		Compose.setWorkCounters(false)
		t.expect(counters.watchRuns).toBe(0)
		t.expect(counters.formulaRecomputations).toBe(0)
		t.expect(#root:GetChildren()).toBe(0)
		stop()
		local static = themes.neutralPackage()
		static.chrome.control = { kind = "native", shadow = "raised" }
		Compose.setWorkCounters(true)
		Compose.resetWorkCounters()
		stop, root = runtime.mount(function()
			return themes.skin(runtime, static, "control", { types = engine.types })
		end, engine.new("Folder"))
		counters = Compose.readWorkCounters()
		Compose.setWorkCounters(false)
		t.expect(counters.watchRuns).toBe(0)
		t.expect(counters.formulaRecomputations).toBe(0)
		t.expect(root:FindFirstChild("ChromeShadow").BlurRadius.Offset).toBe(14)
		stop()
		local selected = Compose.cell(themes.neutralPackage())
		stop, root = runtime.mount(function()
			return themes.skin(runtime, selected, "control", { types = engine.types })
		end, engine.new("Folder"))
		t.expect(#root:GetChildren()).toBe(0)
		local art = themes.neutralPackage()
		art.assets.image = { content = "rbxassetid://30" }
		art.chrome.control = { kind = "nineSlice", asset = "image", shadow = "raised" }
		selected:set(art)
		t.expect(root:FindFirstChild("control1").Image).toBe("rbxassetid://30")
		t.expect(root:FindFirstChild("ChromeShadow") ~= nil).toBe(true)
		selected:set(themes.neutralPackage())
		t.expect(#root:GetChildren()).toBe(2)
		t.expect(root:FindFirstChild("control1").Visible).toBe(false)
		t.expect(root:FindFirstChild("ChromeShadow").Enabled).toBe(false)
		stop()
		runtime:dispose()
	end)

	t.it("uses Button interaction state for semantic icon variants", function()
		local engine, runtime = setup()
		local package = themes.neutralPackage()
		package.icons["facet:search"] =
			{ default = "rest", hover = "hot", pressed = "press", selected = "selected", disabled = "disabled" }
		for name, id in { rest = 1, hot = 2, press = 3, selected = 4, disabled = 5 } do
			package.assets[name] = { content = "rbxassetid://" .. id }
		end
		local UI = require("../src").controls(runtime, { types = engine.types, theme = package })
		local selected, enabled = Compose.cell(false), Compose.cell(true)
		local stop, button = runtime.mount(function()
			return UI.Button({ icon = "facet:search", label = "Find", selected = selected, enabled = enabled })
		end, engine.new("Folder"))
		local icon = button:FindFirstChild("LeadingIcon", true)
		t.expect(icon.Image).toBe("rbxassetid://1")
		button.GuiState = engine.types.Enum.GuiState.Hover
		t.expect(icon.Image).toBe("rbxassetid://2")
		button.GuiState = engine.types.Enum.GuiState.Press
		t.expect(icon.Image).toBe("rbxassetid://3")
		button.GuiState = engine.types.Enum.GuiState.Idle
		selected:set(true)
		t.expect(icon.Image).toBe("rbxassetid://4")
		enabled:set(false)
		t.expect(icon.Image).toBe("rbxassetid://5")
		stop()
		runtime:dispose()
	end)
	t.it("preloads the Compose owned ImageLabel after its source binding settles", function()
		local engine = engineLib.new()
		local runtime = Roblox.createRuntime(engine)
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
					PreloadAsync = function(_, instances, callback)
						table.insert(preloaded, instances[1])
						callback(instances[1].Image, engine.types.Enum.AssetFetchStatus.Success)
					end,
				},
			},
		}))
		local source = Compose.cell("rbxassetid://10")
		local stop, root = runtime.mount(function()
			return UI.AsyncImage({ source = source })
		end, engine.new("Folder"))
		t.expect(#preloaded).toBe(0)
		t.expect(coroutine.resume(pending[1])).toBe(true)
		local image = root:FindFirstChild("Image")
		t.expect(preloaded[1]).toBe(image)
		t.expect(image.Image).toBe("rbxassetid://10")
		t.expect(image.Visible).toBe(true)
		source:set("rbxassetid://20")
		t.expect(coroutine.resume(pending[2])).toBe(true)
		t.expect(preloaded[2]).toBe(image)
		t.expect(image.Image).toBe("rbxassetid://20")
		stop()
		t.expect(image.isDestroyed()).toBe(true)
		environment.task = originalTask
		runtime:dispose()
	end)

	t.it("preserves fractional segmented meter fill and mounted identities", function()
		local engine, runtime, UI = setup()
		local value = Compose.cell(0.625)
		local stop, meter = runtime.mount(function()
			return UI.ProgressView({ value = value, segments = 4 })
		end, engine.new("Folder"))
		local third = meter:FindFirstChild("Fill3", true)
		t.expect(third.Size.X.Scale).toBeCloseTo(0.125)
		t.expect(meter:FindFirstChild("Fill4", true).Size.X.Scale).toBe(0)
		value:set(0.75)
		t.expect(meter:FindFirstChild("Fill3", true)).toBe(third)
		t.expect(third.Size.X.Scale).toBeCloseTo(0.25)
		stop()
		runtime:dispose()
	end)

	t.it("holds damage trails then settles and snaps immediately on healing", function()
		local engine, runtime, UI = setup()
		local value = Compose.cell(1)
		local stop, meter = runtime.mount(function()
			return UI.ProgressView({ value = value, trail = { delay = 0.2, duration = 0.3 } })
		end, engine.new("Folder"))
		local trail = meter:FindFirstChild("Trail", true)
		value:set(0.5)
		engine.heartbeat.fire(0.1)
		t.expect(trail.Size.X.Scale).toBe(1)
		engine.heartbeat.fire(0.25)
		t.expect(trail.Size.X.Scale).toBeCloseTo(0.75)
		engine.heartbeat.fire(0.2)
		t.expect(trail.Size.X.Scale).toBeCloseTo(0.5)
		t.expect(engine.heartbeat.count()).toBe(0)
		value:set(0.25)
		value:set(0.4)
		t.expect(trail.Size.X.Scale).toBeCloseTo(0.4)
		t.expect(engine.heartbeat.count()).toBe(0)
		value:set(0.1)
		engine.heartbeat.fire(0.35)
		t.expect(trail.Size.X.Scale).toBeCloseTo(0.25)
		value:set(0.2)
		t.expect(trail.Size.X.Scale).toBeCloseTo(0.2)
		stop()
		runtime:dispose()
	end)

	t.it("centers circular readouts when native text bounds fit the ring", function()
		local engine, runtime, UI = setup()
		local value = Compose.cell(0.75)
		local stop, meter = runtime.mount(function()
			return UI.ProgressView({ value = value, presentation = "circular", diameter = 120, showValue = true })
		end, engine.new("Folder"))
		local readout, gauge = meter:FindFirstChild("Value", true), meter:FindFirstChild("Gauge", true)
		readout.TextBounds = engine.types.Vector2.new(38, 20)
		t.expect(readout.Text).toBe("75%")
		t.expect(readout.Parent).toBe(gauge)
		t.expect(readout.Position).toBe(engine.types.UDim2.new(0.5, 0, 0, 60))
		t.expect(readout.AnchorPoint).toBe(engine.types.Vector2.new(0.5, 0.5))
		t.expect(gauge.Size).toBe(engine.types.UDim2.fromOffset(120, 120))
		t.expect(gauge.ClipsDescendants).toBe(false)
		value:set(1)
		t.expect(readout.Text).toBe("100%")
		stop()
		runtime:dispose()
	end)

	t.it("rejects incompatible meter options before creating native nodes", function()
		for _, spec in
			{
				{ value = 1, segments = 0 },
				{ value = 1, segments = 2.5 },
				{ value = 1, presentation = "circular", segments = 4 },
				{ value = 1, diameter = 120 },
				{ value = 1, trail = { delay = -1 } },
				{ value = 1, trail = { duration = 0 } },
			}
		do
			local engine, runtime, UI = setup()
			local parent = engine.new("Folder")
			local count = #engine.made
			t.expect(function()
				runtime.mount(function()
					return UI.ProgressView(spec)
				end, parent)
			end).toThrow()
			t.expect(#engine.made).toBe(count)
			t.expect(engine.heartbeat.count()).toBe(0)
			runtime:dispose()
		end
	end)

	t.it("cancels pending damage trails for reduced motion and releases their clock", function()
		local engine = engineLib.new()
		local runtime = Roblox.createRuntime(engine)
		local reduced, value = Compose.cell(false), Compose.cell(1)
		local UI = media(context(Compose, runtime, { types = engine.types, reducedMotion = reduced }))
		local stop, meter = runtime.mount(function()
			return UI.ProgressView({ value = value, trail = { delay = 0.2, duration = 0.3 } })
		end, engine.new("Folder"))
		local trail = meter:FindFirstChild("Trail", true)
		value:set(0.4)
		t.expect(engine.heartbeat.count()).toBe(1)
		reduced:set(true)
		t.expect(trail.Size.X.Scale).toBeCloseTo(0.4)
		t.expect(engine.heartbeat.count()).toBe(0)
		reduced:set(false)
		t.expect(trail.Size.X.Scale).toBeCloseTo(0.4)
		value:set(0.2)
		t.expect(engine.heartbeat.count()).toBe(1)
		stop()
		t.expect(engine.heartbeat.count()).toBe(0)
		value:set(0.8)
		t.expect(trail.isDestroyed()).toBe(true)
		runtime:dispose()
	end)

	t.it("moves oversized circular readouts below the ring using native text bounds", function()
		local engine, runtime, UI = setup()
		local stop, meter = runtime.mount(function()
			return UI.ProgressView({
				value = 1,
				presentation = "circular",
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
		t.expect(readout.Text).toBe("10000 / 10000")
		t.expect(readout.Position).toBe(engine.types.UDim2.new(0.5, 0, 0, 88))
		t.expect(readout.AnchorPoint).toBe(engine.types.Vector2.new(0.5, 0))
		t.expect(readout.TextWrapped).toBe(false)
		t.expect(readout.TextXAlignment).toBe(engine.types.Enum.TextXAlignment.Center)
		t.expect(gauge.Size).toBe(engine.types.UDim2.fromOffset(190, 120))
		readout.TextBounds = engine.types.Vector2.new(40, 18)
		t.expect(readout.Position.Y.Offset).toBe(40)
		t.expect(gauge.Size).toBe(engine.types.UDim2.fromOffset(80, 80))
		stop()
		runtime:dispose()
	end)

	t.it("resets retained native image properties to valid defaults across theme recipes", function()
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
		tiled.assets.plate = { content = "rbxassetid://1" }
		tiled.chrome.control = { kind = "tile", asset = "plate", tileSize = { w = 24, h = 32 } }
		local sliced = themes.neutralPackage()
		sliced.assets.plate =
			{ content = "rbxassetid://2", sliceCenter = { x0 = 3, y0 = 4, x1 = 30, y1 = 40 }, sliceScale = 2 }
		sliced.chrome.control = { kind = "nineSlice", asset = "plate" }
		local plain = themes.neutralPackage()
		plain.assets.plate = { content = "rbxassetid://3" }
		plain.chrome.control = { kind = "fill", asset = "plate" }
		local selected = Compose.cell(tiled)
		local runtime = Roblox.createRuntime(engine)
		local ctx = context(Compose, runtime, { types = engine.types, theme = selected })
		local skin, icon
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
			return runtime.constructors.Frame(children)
		end, create("Folder"))
		local plate = skin:FindFirstChild("control1", true)
		t.expect(plate.ResampleMode).toBe(engine.types.Enum.ResamplerMode.Pixelated)
		t.expect(plate.TileSize).toBe(engine.types.UDim2.fromOffset(24, 32))
		selected:set(sliced)
		t.expect(skin:FindFirstChild("control1", true)).toBe(plate)
		t.expect(plate.ScaleType).toBe(engine.types.Enum.ScaleType.Slice)
		t.expect(plate.SliceScale).toBe(2)
		t.expect(plate.ResampleMode).toBe(defaults.ResampleMode)
		t.expect(plate.TileSize).toBe(defaults.TileSize)
		selected:set(plain)
		t.expect(skin:FindFirstChild("control1", true)).toBe(plate)
		for property in expected do
			t.expect(plate[property]).toBe(defaults[property])
		end
		t.expect(icon.ResampleMode).toBe(defaults.ResampleMode)
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
			local package = require("../examples/themes/" .. name).build(themes)
			selected:set(package)
			t.expect(icon.ResampleMode).toBe(
				if package.identity.rendering == "pixel"
					then engine.types.Enum.ResamplerMode.Pixelated
					else defaults.ResampleMode
			)
		end
		stop()
		defaults:Destroy()
		runtime:dispose()
	end)

	t.it("rotates a smooth native circular arc with reduced motion and themed stroke colors", function()
		local engine = engineLib.new()
		local runtime = Roblox.createRuntime(engine)
		local reduced, package = Compose.cell(false), Compose.cell(themes.neutralPackage())
		local UI = media(context(Compose, runtime, { types = engine.types, theme = package, reducedMotion = reduced }))
		local sheet, meter
		local stop = runtime.mount(function()
			sheet = themes.createStyleSheet(runtime, package, { types = engine.types })
			meter = UI.ProgressView({ presentation = "circular", diameter = 120, thickness = 4 })
			return runtime.constructors.Frame({ sheet, meter })
		end, engine.new("Folder"))
		local arc = meter:FindFirstChild("RingFill", true)
		t.expect(arc.Thickness).toBe(4)
		t.expect(#arc:GetControlPoints()).toBe(3)
		t.expect(#meter:FindFirstChild("Indicator"):GetDescendants()).toBe(2)
		local before = arc:GetControlPoints()[1].Position
		engine.heartbeat.fire(0.1)
		t.expect(arc:GetControlPoints()[1].Position ~= before).toBe(true)
		reduced:set(true)
		before = arc:GetControlPoints()[1].Position
		engine.heartbeat.fire(0.1)
		t.expect(arc:GetControlPoints()[1].Position).toBe(before)
		engine.heartbeat.fire(0.1)
		t.expect(arc:GetControlPoints()[1].Position ~= before).toBe(true)
		local nextPackage = themes.neutralPackage()
		nextPackage.style.themes[1].colors.accent = { r = 0.7, g = 0.2, b = 0.1 }
		nextPackage.style.themes[1].colors.control = { r = 0.3, g = 0.4, b = 0.5 }
		nextPackage.style.themes[1].colors.contentSecondary = { r = 0.6, g = 0.6, b = 0.65 }
		package:set(nextPackage)
		t.expect(style(sheet, ".facet-progress-ring-fill").Color3).toBe(engine.types.Color3.new(0.7, 0.2, 0.1))
		t.expect(style(sheet, ".facet-progress-ring-track").Color3).toBe(engine.types.Color3.new(0.3, 0.4, 0.5))
		local secondary = nextPackage.style.themes[1].colors.contentSecondary
		t.expect(style(sheet, ".facet-type-caption").TextColor3)
			.toBe(engine.types.Color3.new(secondary.r, secondary.g, secondary.b))
		t.expect(meter:FindFirstChild("RingFill", true)).toBe(arc)
		stop()
		t.expect(arc.isDestroyed()).toBe(true)
		t.expect(engine.heartbeat.count()).toBe(0)
		runtime:dispose()
	end)

	t.it("leaves unchanged native rules and running paint transitions untouched during theme updates", function()
		local engine = engineLib.new()
		local create = engine.new
		local writes, transitions = {}, {}
		engine.new = function(className)
			local node = create(className)
			if className == "StyleRule" then
				local mt = getmetatable(node)
				local index, setProperties, setTransitions = mt.__index, node.SetProperties, node.SetPropertyTransitions
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
		local runtime = Roblox.createRuntime(engine)
		local package = themes.neutralPackage()
		local contributed = { ImageTransparency = 0.2 }
		package.rules = { { selector = ".game-icon", properties = contributed } }
		local selected = Compose.cell(package)
		local stop, sheet = runtime.mount(function()
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
		local initialTiming = contributedRule:GetPropertyTransitions().ImageTransparency
		table.clear(writes)
		table.clear(transitions)
		selected:set(table.clone(package))
		t.expect(next(writes)).toBe(nil)
		t.expect(next(transitions)).toBe(nil)
		contributed.ImageTransparency = 0.7
		selected:set(table.clone(package))
		t.expect(writes[contributedRule]).toBe(1)
		t.expect(writes[textRule]).toBe(nil)
		t.expect(next(transitions)).toBe(nil)
		t.expect(contributedRule:GetProperties().ImageTransparency).toBe(0.7)
		t.expect(contributedRule:GetPropertyTransitions().ImageTransparency).toBe(initialTiming)
		contributed.ImageTransparency = nil
		contributed.ImageColor3 = engine.types.Color3.new(0.1, 0.2, 0.3)
		selected:set(table.clone(package))
		t.expect(contributedRule:GetProperties().ImageTransparency).toBe(nil)
		t.expect(contributedRule:GetPropertyTransitions().ImageTransparency).toBe(nil)
		t.expect(contributedRule:GetPropertyTransitions().ImageColor3).toBe(initialTiming)
		t.expect(transitions[contributedRule]).toBe(1)
		table.clear(writes)
		table.clear(transitions)
		package.metrics.motion.normal = 0.4
		selected:set(table.clone(package))
		t.expect(contributedRule:GetPropertyTransitions().ImageColor3.Time).toBe(0.4)
		t.expect(transitions[contributedRule]).toBe(1)
		t.expect(writes[typeRule]).toBe(nil)
		t.expect(writes[textRule]).toBe(1)
		stop()
		runtime:dispose()
	end)

	t.it("uses authored selected contrast for native buttons and their mirrored captions", function()
		local engine, runtime = setup()
		local package = themes.neutralPackage()
		package.style.themes[1].extra.controlSelected = { r = 45 / 255, g = 86 / 255, b = 65 / 255 }
		package.style.themes[1].extra.onSelected = { r = 1, g = 1, b = 1 }
		local selected = Compose.cell(package)
		local stop, sheet = runtime.mount(function()
			return themes.createStyleSheet(runtime, selected, { types = engine.types })
		end, engine.new("Folder"))
		t.expect(style(sheet, ".facet-selected").BackgroundColor3)
			.toBe(engine.types.Color3.new(45 / 255, 86 / 255, 65 / 255))
		t.expect(style(sheet, ".facet-selected").TextColor3).toBe(engine.types.Color3.new(1, 1, 1))
		t.expect(style(sheet, ".facet-selected >> .facet-text").TextColor3).toBe(engine.types.Color3.new(1, 1, 1))
		local dark = themes.neutralPackage()
		dark.style.themes[1].extra.onSelected = { r = 0.1, g = 0.2, b = 0.1 }
		selected:set(dark)
		t.expect(style(sheet, ".facet-selected").TextColor3).toBe(engine.types.Color3.new(0.1, 0.2, 0.1))
		local fallback = themes.neutralPackage()
		selected:set(fallback)
		t.expect(style(sheet, ".facet-selected").TextColor3).toBe(style(sheet, ".facet-text").TextColor3)
		t.expect(style(sheet, ".facet-selected >> .facet-text").TextColor3).toBe(style(sheet, ".facet-text").TextColor3)
		stop()
		runtime:dispose()
	end)
	t.it("shares selected contrast across rich disclosure titles and chevrons", function()
		local engine, runtime = setup()
		local factory = require("../examples/virtual_monitors/theme")
		local package = factory.create(require("../src"), "Avatar")
		local palette, expanded = Compose.cell("Dark"), Compose.cell(false)
		local UI = controls(Compose, runtime, { types = engine.types, theme = package })
		local sheet, disclosure
		local stop = runtime.mount(function()
			sheet = themes.createStyleSheet(runtime, package, { types = engine.types, theme = palette })
			disclosure = UI.DisclosureGroup({
				label = "Appearance",
				description = "Choose an avatar color",
				expanded = expanded,
				content = function()
					return UI.Text({ text = "Controls" })
				end,
			})
			return runtime.constructors.Frame({ sheet, disclosure })
		end, engine.new("Folder"))
		local header = disclosure:FindFirstChild("Header")
		t.expect(header:HasTag("facet-selected")).toBe(false)
		t.expect(header:FindFirstChild("Title", true):HasTag("facet-text")).toBe(true)
		t.expect(header:FindFirstChild("Description", true):HasTag("facet-text")).toBe(true)
		t.expect(header:FindFirstChild("LeadingIcon", true):HasTag("facet-icon")).toBe(true)
		expanded:set(true)
		t.expect(header:HasTag("facet-selected")).toBe(true)
		for _, name in { "Dark", "Light" } do
			palette:set(name)
			local foreground = style(sheet, ".facet-selected").TextColor3
			t.expect(style(sheet, ".facet-selected >> .facet-text").TextColor3).toBe(foreground)
			t.expect(style(sheet, ".facet-selected >> .facet-icon").ImageColor3).toBe(foreground)
			t.expect(foreground == style(sheet, ".facet-text").TextColor3).toBe(false)
		end
		expanded:set(false)
		t.expect(header:HasTag("facet-selected")).toBe(false)
		stop()
		runtime:dispose()
	end)

	t.it("bounds idle skin slots and disposes every retained native owner", function()
		local engine, runtime = setup()
		local package = themes.neutralPackage()
		package.assets.image = { content = "rbxassetid://99" }
		local layers = {}
		for _ = 1, 24 do
			table.insert(layers, { kind = "fill", asset = "image" })
		end
		package.chrome.control = { kind = "layered", layers = layers }
		local selected = Compose.cell(package)
		local stop, root = runtime.mount(function()
			return themes.skin(runtime, selected, "control", { types = engine.types })
		end, engine.new("Folder"))
		local initial = root:GetChildren()
		t.expect(#initial).toBe(24)
		selected:set(themes.neutralPackage())
		t.expect(#root:GetChildren()).toBe(16)
		local retained = 0
		for _, image in initial do
			if not image.isDestroyed() then
				retained += 1
				t.expect(image.Parent).toBe(root)
				t.expect(image.Visible).toBe(false)
			end
		end
		t.expect(retained).toBe(16)
		selected:set(package)
		local active = root:GetChildren()
		local reused = 0
		for _, image in active do
			if table.find(initial, image) then
				reused += 1
			end
			t.expect(image.Image).toBe("rbxassetid://99")
			t.expect(image.Visible).toBe(true)
		end
		t.expect(reused).toBe(16)
		stop()
		for _, image in initial do
			t.expect(image.isDestroyed()).toBe(true)
		end
		for _, image in active do
			t.expect(image.isDestroyed()).toBe(true)
		end
		selected:set(themes.neutralPackage())
		selected:set(package)
		runtime:dispose()
	end)

	t.it("retains bounded skin slots across frozen recipes while mutable art stays reactive", function()
		local engine, runtime = setup()
		local package = themes.neutralPackage()
		package.assets.image = { content = "rbxassetid://99" }
		package.chrome.control = { kind = "fill", asset = "image" }
		local frozen = assert(themes.define(package))
		local neutral = themes.neutralPackage()
		local selected, revision = Compose.cell(frozen), Compose.cell(0)
		local stop, root = runtime.mount(function()
			return themes.skin(runtime, function(use)
				use(revision)
				return use(selected)
			end, "control", { types = engine.types })
		end, engine.new("Folder"))
		local image = root:FindFirstChild("control1")
		for _ = 1, 50 do
			selected:set(neutral)
			t.expect(image.Visible).toBe(false)
			selected:set(frozen)
			t.expect(root:FindFirstChild("control1")).toBe(image)
			t.expect(image.Visible).toBe(true)
		end
		t.expect(#root:GetChildren()).toBe(1)
		table.freeze(package)
		selected:set(package)
		package.assets.image.content = "rbxassetid://100"
		package.chrome.control.kind = "tile"
		package.chrome.control.tileSize = { w = 11, h = 12 }
		revision:set(1)
		t.expect(image.Image).toBe("rbxassetid://100")
		t.expect(image.ScaleType).toBe(engine.types.Enum.ScaleType.Tile)
		t.expect(image.TileSize).toBe(engine.types.UDim2.fromOffset(11, 12))
		selected:set(frozen)
		t.expect(image.Image).toBe("rbxassetid://99")
		t.expect(image.ScaleType).toBe(engine.types.Enum.ScaleType.Stretch)
		stop()
		t.expect(image.isDestroyed()).toBe(true)
		runtime:dispose()
	end)

	t.it("accepts the Virtual Monitors package without optional art sections", function()
		local engine, runtime = setup()
		local factory = require("../examples/virtual_monitors/theme")
		for _, name in { "Discover", "Avatar" } do
			local package = factory.create(require("../src"), name)
			t.expect(next(package.assets or {})).toBe(nil)
			t.expect(package.chrome.monitorPanel.kind).toBe("native")
			t.expect(package.chrome.monitorPanel.shadow).toBe("raised")
			t.expect(table.isfrozen(package)).toBe(true)
			local sheet
			local stop = runtime.mount(function()
				sheet = themes.createStyleSheet(runtime, package, { types = engine.types, theme = "Light" })
				return runtime.constructors.Frame({
					sheet,
					themes.skin(runtime, package, "control", { types = engine.types }),
				})
			end, engine.new("Folder"))
			t.expect(style(sheet, ".facet-button::UIPadding").PaddingLeft.Offset).toBe(12)
			t.expect(style(sheet, ".facet-selected").TextColor3).toBe(engine.types.Color3.new(1, 1, 1))
			stop()
		end
		runtime:dispose()
	end)

	t.it("shows the showValue readout beside a ProgressView endLabel", function()
		local engine, runtime, UI = setup()
		local stop, root = runtime.mount(function()
			return UI.ProgressView "Upload" { value = 0.5, showValue = true, endLabel = "End" }
		end, engine.new("Folder"))
		local texts = {}
		for _, node in root:GetDescendants() do
			if node:IsA("TextLabel") then
				texts[node.Text] = node
			end
		end
		t.expect(texts["50%"] ~= nil).toBe(true)
		t.expect(texts["End"] ~= nil).toBe(true)
		stop()
		runtime:dispose()
	end)

	t.it("returns the Label root that api.md states, with and without an icon", function()
		local engine, runtime, UI = setup()
		local stop, root = runtime.mount(function()
			return runtime.constructors.Frame({
				UI.Text "Plain" { text = "Plain" },
				UI.Label "Iconic" { title = "Iconic", icon = "rbxassetid://1" },
			})
		end, engine.new("Folder"))
		local plain, iconic = root:FindFirstChild("Plain"), root:FindFirstChild("Iconic")
		t.expect(plain.ClassName).toBe("TextLabel")
		t.expect(iconic.ClassName).toBe("Frame")
		t.expect(iconic:FindFirstChildWhichIsA("TextLabel").Text).toBe("Iconic")
		local api = fs.readFile("docs/reference/api.md")
		t.expect(string.find(api, "`UI.Text(spec) -> TextLabel`", 1, true) ~= nil).toBe(true)
		t.expect(string.find(api, "`UI.Label(spec) -> Frame`", 1, true) ~= nil).toBe(true)
		t.expect(iconic:FindFirstChild("Title").ClassName).toBe("TextLabel")
		t.expect(iconic:FindFirstChild("Icon").ClassName).toBe("ImageLabel")
		stop()
		runtime:dispose()
	end)

	t.it("mounts the namespaced control fixtures with the current controls", function()
		local engine, runtime = setup()
		local Facet = require("../src")
		local gauge = require("../examples/themes/ornate_gauge")
		local custom = require("../examples/themes/custom_control")
		local ornate = assert(require("../examples/themes/fantasy_ornate").build(Facet.themes))
		local glossy = assert(require("../examples/themes/glossy_mobile").build(Facet.themes))
		t.expect(gauge.check(Facet.themes, ornate).ok).toBe(true)
		t.expect(custom.check(glossy).ok).toBe(true)
		local dial = gauge.resolve(ornate)
		t.expect(dial.height).toBe(56)
		t.expect(dial.ring).toBe(8)
		t.expect(dial.usedFallback.size or dial.usedFallback.ring or dial.usedFallback.needle).toBe(false)
		local track = custom.resolve(glossy)
		t.expect(track.height).toBe(28)
		t.expect(custom.resolve(nil).usedFallback.size).toBe(true)
		local UI = Facet.controls(runtime, { types = engine.types })
		local core = { Host = runtime.constructors, types = engine.types }
		local fraction = Compose.cell(0.25)
		local stop, root = runtime.mount(function()
			return runtime.constructors.Frame({
				gauge.blueprint(UI, core, dial, { id = "Boiler", fraction = fraction }),
				custom.blueprint(UI, core, track, "Meter"),
			})
		end, engine.new("Folder"))
		local needle = root:FindFirstChild("BoilerNeedle", true)
		t.expect(needle.Image).toBe(gauge.ART.needle)
		t.expect(needle.Position.X.Scale).toBe(0.25)
		fraction:set(0.75)
		t.expect(needle.Position.X.Scale).toBe(0.75)
		t.expect(root:FindFirstChild("BoilerDial", true).Size.Y.Offset).toBe(56)
		local meter = root:FindFirstChild("MeterTrack", true)
		t.expect(meter.Size.Y.Offset).toBe(28)
		t.expect(meter:HasTag("facet-control")).toBe(true)
		stop()
		runtime:dispose()
	end)
end)
