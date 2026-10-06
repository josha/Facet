--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	local FixtureNavigationTypes = require("../src/ui/navigation_types")

	local Facet = require("../src") :: any
	local engineLib = require("./lib/native_engine")
	local styleRules = require("./lib/style_rules")
	local Compose: ComposeModule = Facet.Compose
	local themes = Facet.themes

	local function world(options: { [string]: any }?, distant: boolean?)
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local input = engine.new("UserInputService")
		local T = engine.types
		gui.GetGuiInset = function()
			return T.Vector2.zero, T.Vector2.zero
		end
		input.MouseEnabled = not distant
		if distant then
			gui.ViewportDisplaySize = T.Enum.DisplaySize.Large
		end
		local config: { [string]: any } = {
			types = T,
			guiService = gui,
			userInputService = input,
			services = { GuiService = gui, UserInputService = input },
		}
		for key, value in (options or {} :: { [string]: any }) do
			config[key] = value
		end
		local UI = Facet.controls(runtime, config)
		local function dock(distant: boolean)
			gui.ViewportDisplaySize = if distant then T.Enum.DisplaySize.Large else T.Enum.DisplaySize.Medium
			input.MouseEnabled = not distant
		end
		local function mount(body: () -> any): any
			local root: any
			runtime.mount(function()
				root = body()
				return root
			end, engine.new("ScreenGui"))
			return root
		end
		return { engine = engine, runtime = runtime, UI = UI, T = T, dock = dock, mount = mount, gui = gui }
	end

	verifyHarness:suite("themes.forDistance: the ten-foot metric ladder", function()
		verifyHarness:case("is the identity near and scales every length by 1.5 at ten feet, rounding radii", {
			id = "native_ten_foot::themes.forDistance: the ten-foot metric ladder::is the identity near and scales every length by 1.5 at ten feet, rounding radii",
			run = function()
				local base = themes.forDistance(themes.neutralPackage(), "near")
				local package = assert(themes.define({ identity = { id = "ladder" } } :: any))
				Verify.expect((themes.forDistance(package, "near"))):toBe(package)
				local far = themes.forDistance(package, "ten-foot")
				local m = far.metrics
				Verify.expect(m.space.m):toBe(24)
				Verify.expect(m.targetSizes.minimum):toBe(66)
				Verify.expect(m.controlSizes.regular.height):toBe(66)
				Verify.expect(m.controlSizes.compact.paddingX):toBe(12)
				Verify.expect(m.iconSizes.medium):toBe(30)
				Verify.expect(m.radii.control):toBe(12)
				Verify.expect(m.radii.panel):toBe(18)
				Verify.expect(m.strokes.hairline):toBe(1.5)
				Verify.expect(m.typography.body.size):toBe(24)
				Verify.expect(m.typography.caption.size):toBe(18)
				Verify.expect(m.motion.normal):toBe(package.metrics.motion.normal)
				Verify.expect(m.controls.alert.maxWidth):toBe(840)
				Verify.expect(far.style):toBe(package.style)
				Verify.expect(base.metrics.space.m):toBe(16)
			end,
		})
		verifyHarness:case("is idempotent and reversible, and caches one ladder per package", {
			id = "native_ten_foot::themes.forDistance: the ten-foot metric ladder::is idempotent and reversible, and caches one ladder per package",
			run = function()
				local package = assert(themes.define({ identity = { id = "round-trip" } } :: any))
				local far = themes.forDistance(package, "ten-foot")
				Verify.expect((themes.forDistance(package, "ten-foot"))):toBe(far)
				Verify.expect((themes.forDistance(far, "ten-foot"))):toBe(far)
				Verify.expect((themes.forDistance(far, "near"))):toBe(package)
				Verify.expect((table.isfrozen(far.metrics.space))):toBe(true)
				Verify.expect((pcall(themes.forDistance, package, "far"))):toBe(false)
			end,
		})
		verifyHarness:case("leaves a count, ratio or text size in a control family alone", {
			id = "native_ten_foot::themes.forDistance: the ten-foot metric ladder::leaves a count, ratio or text size in a control family alone",
			run = function()
				local package = assert(themes.define({
					identity = { id = "families" },
					metrics = {
						controls = { meter = { barHeight = 10, labelTextSize = 14, fillRatio = 0.5, dotCount = 3 } },
					},
				} :: any))
				local meter = themes.forDistance(package, "ten-foot").metrics.controls.meter
				Verify.expect(meter.barHeight):toBe(15)
				Verify.expect(meter.labelTextSize):toBe(14)
				Verify.expect(meter.fillRatio):toBe(0.5)
				Verify.expect(meter.dotCount):toBe(3)
			end,
		})
	end)

	verifyHarness:suite("ten-foot controls follow the distance fact", function()
		verifyHarness:case("a control takes the ladder at ten feet, and follows a live preview of the distance", {
			id = "native_ten_foot::ten-foot controls follow the distance fact::a control takes the ladder at ten feet, and follows a live preview of the distance",
			run = function()
				local w = world({ theme = assert(themes.define({ identity = { id = "live" } } :: any)) })
				local button = w.mount(function()
					return w.UI.Button { label = "Play" }
				end)
				local stack = w.mount(function()
					return w.UI.VStack { gap = "m", w.UI.Text { text = "A" } }
				end)
				local list = stack:FindFirstChildWhichIsA("UIListLayout")
				Verify.expect(button.Size.Y.Offset):toBe(44)
				Verify.expect(list.Padding.Offset):toBe(16)
				w.runtime:dispose()
				local display = Compose.cell("Medium")
				local live = world({
					theme = Compose.cell(assert(themes.define({ identity = { id = "live-cell" } } :: any))),
					environment = { displaySize = display },
				})
				live.dock(true)
				display:set("Medium")
				local docked = live.mount(function()
					return live.UI.Button { label = "Play" }
				end)
				Verify.expect(docked.Size.Y.Offset):toBe(44)
				display:set("Large")
				Verify.expect(docked.Size.Y.Offset):toBe(66)
				display:set("Small")
				Verify.expect(docked.Size.Y.Offset):toBe(44)
				live.runtime:dispose()
				local bare = world(nil, true)
				local distant = bare.mount(function()
					return bare.UI.VStack { gap = "m", bare.UI.Button { label = "Play" } }
				end)
				Verify.expect(distant:FindFirstChildWhichIsA("UIListLayout").Padding.Offset):toBe(24)
				Verify.expect(distant:FindFirstChildWhichIsA("TextButton").Size.Y.Offset):toBe(66)
				bare.runtime:dispose()
			end,
		})
		verifyHarness:case("floors a width-only Button at the control height, near and at ten feet", {
			id = "native_ten_foot::ten-foot controls follow the distance fact::floors a width-only Button at the control height, near and at ten feet",
			run = function()
				for _, distant in { false, true } do
					local w = world(nil, distant)
					local D2 = w.T.UDim2
					local root = w.mount(function()
						return w.UI.VStack {
							w.UI.Button "Zero" { label = "Play", Size = D2.new(1, 0, 0, 0) },
							w.UI.Button "Thirds" { label = "Play", Size = D2.new(1 / 3, -6, 0, 0) },
						}
					end)
					local floor = if distant then 66 else 44
					for _, name in { "Zero", "Thirds" } do
						local button = root:FindFirstChild(name)
						Verify.expect(`{name} {button.Size.Y.Offset} {button.AutomaticSize.Name}`)
							:toBe(`{name} {floor} Y`)
					end
					w.runtime:dispose()
				end
			end,
		})
		verifyHarness:case("an authored viewingDistance scales a mouse desktop and keeps a console near", {
			id = "native_ten_foot::ten-foot controls follow the distance fact::an authored viewingDistance scales a mouse desktop and keeps a console near",
			run = function()
				local distance = Compose.cell("ten-foot")
				local w = world({
					theme = assert(themes.define({ identity = { id = "authored" } } :: any)),
					environment = { viewingDistance = distance },
				})
				local button = w.mount(function()
					return w.UI.Button { label = "Play" }
				end)
				Verify.expect(button.Size.Y.Offset):toBe(66)
				distance:set("near")
				w.dock(true)
				Verify.expect(button.Size.Y.Offset):toBe(44)
				w.runtime:dispose()
			end,
		})
		verifyHarness:case("a StyleSheet compiles the ten-foot type ramp from its tenFoot option", {
			id = "native_ten_foot::ten-foot controls follow the distance fact::a StyleSheet compiles the ten-foot type ramp from its tenFoot option",
			run = function()
				local w = world()
				local distant = Compose.cell(false)
				local sheet: any
				w.runtime.mount(function()
					sheet = themes.createStyleSheet(w.runtime, nil, { types = w.T, tenFoot = distant })
					return sheet
				end, w.engine.new("Folder"))
				local label = w.engine.new("TextLabel")
				label:AddTag("facet-type-body")
				local function size(): number?
					return styleRules.resolve(sheet, label, "TextSize")
				end
				Verify.expect((size())):toBe(16)
				distant:set(true)
				Verify.expect((size())):toBe(24)
				w.runtime:dispose()
			end,
		})
	end)

	verifyHarness:suite("ten-foot overscan margins on a Screen", function()
		verifyHarness:case("insets a Screen by the console proportion at ten feet and not near", {
			id = "native_ten_foot::ten-foot overscan margins on a Screen::insets a Screen by the console proportion at ten feet and not near",
			run = function()
				local near = world()
				local screen = near.mount(function()
					return near.UI.Screen {}
				end)
				Verify.expect(screen:FindFirstChildWhichIsA("UIPadding").PaddingLeft):toBe(near.T.UDim.new(0, 16))
				near.runtime:dispose()
				local w = world(nil, true)
				local padding = w.mount(function()
					return w.UI.Screen {}
				end):FindFirstChildWhichIsA("UIPadding")
				Verify.expect(padding.PaddingLeft):toBe(w.T.UDim.new(90 / 1920, 24))
				Verify.expect(padding.PaddingTop):toBe(w.T.UDim.new(60 / 1080, 24))
				w.runtime:dispose()
			end,
		})
		verifyHarness:case("a top bar TabView starts its pages below its own band at every distance", {
			id = "native_ten_foot::ten-foot overscan margins on a Screen::a top bar TabView starts its pages below its own band at every distance",
			run = function()
				for _, distant in { false, true } do
					local w = world(nil, distant)
					local root = w.mount(function()
						return w.UI.TabView {
							style = "collapsible" :: "collapsible",
							selection = Compose.cell("a"),
							tabs = {
								{
									id = "a",
									label = "A",
									content = function(): Instance
										return w.UI.Text { text = "A" }
									end,
								} :: FixtureNavigationTypes.Tab,
							},
						}
					end)
					local band = if distant then 66 else 44
					Verify.expect(root:FindFirstChild("Content").Position.Y.Offset):toBe(band + 8)
					w.runtime:dispose()
				end
			end,
		})

		verifyHarness:case("adds authored margins in pixels and none opts out", {
			id = "native_ten_foot::ten-foot overscan margins on a Screen::adds authored margins in pixels and none opts out",
			run = function()
				local margins = Compose.cell({ top = 10, left = 20, bottom = 10, right = 20 } :: any)
				local w = world({ environment = { overscanInsets = margins } }, true)
				local screen = w.mount(function()
					return w.UI.Screen {}
				end)
				local padding = screen:FindFirstChildWhichIsA("UIPadding")
				Verify.expect(padding.PaddingLeft):toBe(w.T.UDim.new(0, 44))
				margins:set("none")
				Verify.expect(padding.PaddingLeft):toBe(w.T.UDim.new(0, 24))
				w.runtime:dispose()
			end,
		})
	end)
end
