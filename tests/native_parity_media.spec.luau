--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	type Destroyable = typeof(require("@repo/tools/typecheck/aliases").Destroyable)
	type ControlSizeValue = typeof(require("@repo/tools/typecheck/aliases").ControlSizeValue)

	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type MotionLevel = typeof(require("@repo/tools/typecheck/aliases").MotionLevel)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local ThemeTypes = require("../src/ui/theme_types")
	local FixtureNavigationTypes = require("../src/ui/navigation_types")
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local materialize = require("./lib/materialize")
	local fadeKit = require("./lib/fade")
	local Facet = require("../src")
	local icons = require("../src/ui/icons")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose
	local themes = Facet.themes

	local SHIPPED: { any } = {
		require("../examples/themes/classic_desktop"),
		require("../examples/themes/compact_pointer"),
		require("../examples/themes/fantasy_ornate"),
		require("../examples/themes/fantasy_parchment"),
		require("../examples/themes/glossy_mobile"),
		require("../examples/themes/glossy_touch"),
		require("../examples/themes/pixel_quest"),
		require("../examples/themes/scifi_hud"),
	}

	local function make(options: { [string]: any }?): (any, any, any)
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local config: { [string]: any } = {
			types = engine.types,
			guiService = gui,
			services = { GuiService = gui },
		}
		for key, value in (options or {}) :: { [string]: any } do
			config[key] = value
		end
		return engine, runtime, Facet.controls(runtime, config :: any)
	end

	local function mount(engine: any, runtime: any, build: () -> any): (() -> (), any)
		local stop, root: any = runtime.mount(build, engine.new("ScreenGui"))
		return stop, root
	end

	local function refusal(build: (any, any) -> any, options: { [string]: any }?): { [string]: any }
		local engine, runtime, UI = make(options)
		local parent = engine.new("ScreenGui")
		local before = engine.census()
		local made = #engine.made
		local ok, message = pcall(function()
			runtime.mount(function()
				return build(UI, runtime.constructors)
			end, parent)
		end)
		local after = engine.census()
		runtime:dispose()
		return {
			message = if ok then nil else tostring(message),
			created = #engine.made - made,
			live = after.live - before.live,
			connections = after.connections - before.connections,
			heartbeat = engine.heartbeat.count(),
		}
	end

	local function refusedWith(result: { [string]: any }, fragment: string): boolean
		return result.message ~= nil and string.find(result.message, fragment, 1, true) ~= nil
	end

	local function style(sheet: any, selector: string): any
		for _, node in sheet:GetChildren() do
			if node.Selector == selector then
				return node
			end
		end
		error("No rule: " .. selector)
	end

	local function color(engine: any, value: any): any
		return engine.types.Color3.new(value.r, value.g, value.b)
	end

	local function statusTags(node: any): { string }
		local found = {}
		for _, tag in node:GetTags() do
			if string.match(tag, "^facet%-status%-") then
				table.insert(found, tag)
			end
		end
		table.sort(found)
		return found
	end

	local function progressReader(presentation: string, root: any): () -> number
		if presentation == "bar" then
			local fill = root:FindFirstChild("Fill1", true)
			return function()
				return fill.Position.X.Scale
			end
		elseif presentation == "circular" then
			local arc = root:FindFirstChild("RingFill", true)
			return function()
				local point = arc:GetControlPoints()[1].Position
				return point.X.Scale * 1000 + point.Y.Scale
			end
		end
		local dot = root:FindFirstChild("Segment1", true)
		return function()
			return dot.BackgroundTransparency
		end
	end

	local function distinctReadings(presentation: string, reduced: boolean, step: number, count: number): number
		local engine, runtime, UI = make({ motionLevel = if reduced then "none" else "normal" })
		local stop, root = mount(engine, runtime, function()
			return UI.ProgressView({ presentation = presentation })
		end)
		local reading = progressReader(presentation, root)
		local seen, distinct = {}, 0
		local function record()
			local key = string.format("%.6f", reading())
			if not seen[key] then
				seen[key] = true
				distinct += 1
			end
		end
		record()
		for _ = 1, count do
			engine.heartbeat.fire(step)
			record()
		end
		stop()
		runtime:dispose()
		return distinct
	end

	verifyHarness:suite("native parity media", function()
		verifyHarness:suite("progress motion", function()
			verifyHarness:case(
				"sweeps an indeterminate bar segment inside its clipped track and repeats every second",
				{
					id = "native_parity_media::progress motion::sweeps an indeterminate bar segment inside its clipped track and repeats every second",
					run = function()
						local engine, runtime, UI = make()
						local stop, root = mount(engine, runtime, function()
							return UI.ProgressView({})
						end)
						local track = root:FindFirstChild("Track", true)
						local clip = track:FindFirstChild("FillClip")
						local fill = clip:FindFirstChild("Fill1")
						Verify.expect(track.ClipsDescendants):toBe(false)
						Verify.expect(clip.ClipsDescendants):toBe(true)
						Verify.expect(clip.Size):toBe(engine.types.UDim2.fromScale(1, 1))
						Verify.expect(fill.Parent):toBe(clip)
						Verify.expect(fill.Size.X.Scale):toBeCloseTo(0.3, 1e-4)
						Verify.expect(fill.Position.X.Scale):toBeCloseTo(-0.3, 1e-4)
						engine.heartbeat.fire(0.25)
						Verify.expect(fill.Position.X.Scale):toBeCloseTo(0.025, 1e-4)
						engine.heartbeat.fire(0.25)
						Verify.expect(fill.Position.X.Scale):toBeCloseTo(0.35, 1e-4)
						engine.heartbeat.fire(0.75)
						Verify.expect(fill.Position.X.Scale):toBeCloseTo(0.025, 1e-4)
						for _ = 1, 40 do
							engine.heartbeat.fire(0.037)
							local left = fill.Position.X.Scale
							Verify.expect(left):toBeGreaterThanOrEqual(-0.3 - 1e-6)
							Verify.expect(left):toBeLessThanOrEqual(1 + 1e-6)
							Verify.expect(left + fill.Size.X.Scale):toBeGreaterThanOrEqual(-1e-6)
							Verify.expect(fill.Size.X.Scale):toBeCloseTo(0.3, 1e-4)
						end
						Verify.expect((engine.heartbeat.count())):toBeGreaterThan(0)
						stop()
						Verify.expect((engine.heartbeat.count())):toBe(0)
						runtime:dispose()
					end,
				}
			)

			verifyHarness:case("holds a reduced-motion indeterminate bar within a quarter and then steps", {
				id = "native_parity_media::progress motion::holds a reduced-motion indeterminate bar within a quarter and then steps",
				run = function()
					local engine, runtime, UI = make({ motionLevel = "none" })
					local stop, root = mount(engine, runtime, function()
						return UI.ProgressView({})
					end)
					local fill = root:FindFirstChild("Fill1", true)
					local start = fill.Position.X.Scale
					Verify.expect(start):toBeCloseTo(0, 1e-4)
					engine.heartbeat.fire(0.1)
					Verify.expect(fill.Position.X.Scale):toBe(start)
					engine.heartbeat.fire(0.1)
					Verify.expect(fill.Position.X.Scale):toBe(start)
					engine.heartbeat.fire(0.1)
					Verify.expect(fill.Position.X.Scale):toBeCloseTo(0.25 * 0.7, 1e-4)
					engine.heartbeat.fire(0.25)
					Verify.expect(fill.Position.X.Scale):toBeCloseTo(0.5 * 0.7, 1e-4)
					stop()
					runtime:dispose()
				end,
			})

			verifyHarness:case(
				"shows four quarter poses per cycle under reduced motion for bar, circular and spinner",
				{
					id = "native_parity_media::progress motion::shows four quarter poses per cycle under reduced motion for bar, circular and spinner",
					run = function()
						for _, presentation in { "bar", "circular", "spinner" } :: { "bar" | "circular" | "spinner" } do
							Verify.expect((distinctReadings(presentation, true, 0.05, 19))):toBe(4)
							local full = distinctReadings(presentation, false, 0.02, 20)
							local reduced = distinctReadings(presentation, true, 0.02, 20)
							Verify.expect(full):toBe(21)
							Verify.expect(reduced):toBe(2)
							Verify.expect(full):toBeGreaterThan(reduced)
						end
					end,
				}
			)

			verifyHarness:case(
				"steps from the running phase when reduced motion turns on mid-cycle instead of restarting",
				{
					id = "native_parity_media::progress motion::steps from the running phase when reduced motion turns on mid-cycle instead of restarting",
					run = function()
						local reduced = Compose.cell(false)
						local engine, runtime, UI = make({
							motionLevel = (Compose.formula(function(use: Use): "normal" | "limited" | "none"
								return if use(reduced) then "none" else "normal"
							end) :: unknown) :: MotionLevel,
						})
						local stop, root = mount(engine, runtime, function()
							return UI.ProgressView({})
						end)
						local fill = root:FindFirstChild("Fill1", true)
						engine.heartbeat.fire(0.6)
						Verify.expect(fill.Position.X.Scale):toBeCloseTo(0.6 * 1.3 - 0.3, 1e-4)
						reduced:set(true)
						Verify.expect(fill.Position.X.Scale):toBeCloseTo(0.5 * 0.7, 1e-4)
						Verify.expect(math.abs(fill.Position.X.Scale) > 0.1):toBe(true)
						engine.heartbeat.fire(0.1)
						Verify.expect(fill.Position.X.Scale):toBeCloseTo(0.5 * 0.7, 1e-4)
						engine.heartbeat.fire(0.1)
						Verify.expect(fill.Position.X.Scale):toBeCloseTo(0.75 * 0.7, 1e-4)
						reduced:set(false)
						Verify.expect(fill.Position.X.Scale):toBeCloseTo(0.8 * 1.3 - 0.3, 1e-4)
						stop()
						runtime:dispose()
					end,
				}
			)

			verifyHarness:case("refuses an unknown progress presentation before creating native nodes or a clock", {
				id = "native_parity_media::progress motion::refuses an unknown progress presentation before creating native nodes or a clock",
				run = function()
					local refused = refusal(function(UI: FacetControls)
						return UI.ProgressView({ value = 1, presentation = "ring" } :: any)
					end)
					Verify.expect((refusedWith(refused, "presentation must be bar, circular or spinner"))):toBe(true)
					Verify.expect(refused.created):toBe(0)
					Verify.expect(refused.heartbeat):toBe(0)
					for _, presentation in { "bar", "circular", "spinner" } :: { "bar" | "circular" | "spinner" } do
						local accepted = refusal(function(UI: FacetControls)
							return UI.ProgressView({
								value = 1,
								presentation = presentation :: "bar" | "circular" | "spinner",
							})
						end)
						Verify.expect(accepted.message):toBeNil()
						Verify.expect(accepted.created):toBeGreaterThan(0)
					end
				end,
			})

			verifyHarness:case("authors distinct circular and spinner metrics in every shipped theme package", {
				id = "native_parity_media::progress motion::authors distinct circular and spinner metrics in every shipped theme package",
				run = function()
					local neutral = themes.neutralPackage().metrics.controls.progress
					local smallest, largest = { size = math.huge, dot = math.huge }, { size = 0, dot = 0 }
					local engine, runtime = make()
					Verify.expect(#SHIPPED):toBe(8)
					for _, module in SHIPPED do
						local package, report = module.build(themes)
						Verify.expect(report.ok):toBe(true)
						local progress = package.metrics.controls.progress
						for _, field in { "circularSize", "circularThickness", "spinnerDotSize" } do
							Verify.expect((type(progress[field]))):toBe("number")
							Verify.expect(progress[field]):toBeGreaterThan(0)
						end
						Verify.expect(
							progress.circularSize == neutral.circularSize
								and progress.circularThickness == neutral.circularThickness
								and progress.spinnerDotSize == neutral.spinnerDotSize
						):toBe(false)
						smallest.size = math.min(smallest.size, progress.circularSize)
						largest.size = math.max(largest.size, progress.circularSize)
						smallest.dot = math.min(smallest.dot, progress.spinnerDotSize)
						largest.dot = math.max(largest.dot, progress.spinnerDotSize)
						local themed: any = Facet.controls(runtime, { types = engine.types, theme = package } :: any)
						local stop, root = mount(engine, runtime, function()
							return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
								themed.ProgressView "Ring" { value = 0.5, presentation = "circular" :: "circular" } :: unknown,
								themed.ProgressView "Spinner" { presentation = "spinner" :: "spinner" },
							})
						end)
						local ring = root:FindFirstChild("Ring", true):FindFirstChild("Indicator", true)
						Verify.expect(ring.Size.X.Offset):toBe(progress.circularSize)
						Verify.expect(ring:FindFirstChild("RingFill").Thickness)
							:toBe(math.max(progress.circularThickness, math.round(progress.circularSize * 0.08)))
						Verify.expect(
							root:FindFirstChild("Spinner", true):FindFirstChild("Segment1", true).Size.X.Offset
						)
							:toBe(progress.spinnerDotSize)
						stop()
					end
					Verify.expect(largest.size / smallest.size):toBeGreaterThanOrEqual(2)
					Verify.expect(largest.dot / smallest.dot):toBeGreaterThanOrEqual(2)
					runtime:dispose()
				end,
			})
		end)

		verifyHarness:suite("badge", function()
			verifyHarness:case(
				"keeps one icon instance through every reactive status and repaints it with the partner color",
				{
					id = "native_parity_media::badge::keeps one icon instance through every reactive status and repaints it with the partner color",
					run = function()
						local engine, runtime, UI = make()
						local status = Compose.cell("neutral")
						local package = themes.neutralPackage()
						local sheet, badge: any
						local stop = mount(engine, runtime, function()
							sheet = themes.createStyleSheet(runtime, package, { types = engine.types })
							badge = UI.Badge({ label = "Ready", icon = "checkmark", status = status })
							return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
								sheet :: unknown,
								badge,
							})
						end)
						local icon = badge:FindFirstChildWhichIsA("ImageLabel")
						local label = badge:FindFirstChild("Label")
						Verify.expect((icon:HasTag("facet-icon"))):toBe(true)
						Verify.expect(icon.Parent):toBe(badge)
						Verify.expect(label.Parent):toBe(badge)
						local palette: any = package.style.themes[1]
						local partners = {
							neutral = palette.colors.surface,
							info = palette.colors.onAccent,
							success = palette.colors.onSuccess,
							warning = palette.colors.onWarning,
							error = palette.colors.onDanger,
							accent = palette.colors.onAccent,
						}
						for _, name in { "info", "success", "warning", "error", "accent", "neutral" } do
							status:set(name)
							Verify.expect((statusTags(badge))):toEqual({ "facet-status-" .. name })
							Verify.expect((badge:FindFirstChildWhichIsA("ImageLabel"))):toBe(icon)
							Verify.expect((badge:FindFirstChild("Label"))):toBe(label)
							Verify.expect(label.Text):toBe("Ready")
							Verify.expect(icon.Image):toBe(icons.ART.checkmark.contentId)
							Verify.expect(
								style(sheet, ".facet-status-" .. name .. " > .facet-icon"):GetProperties().ImageColor3
							)
								:toBe(color(engine, partners[name]))
						end
						Verify.expect(color(engine, partners.warning) ~= color(engine, palette.colors.content))
							:toBe(true)
						Verify.expect((pcall(function()
							status:set("danger")
						end))):toBe(false)
						status:set("warning")
						Verify.expect((statusTags(badge))):toEqual({ "facet-status-warning" })
						stop()
						runtime:dispose()
					end,
				}
			)

			verifyHarness:case("gives an icon badge the plain caption height and orders the icon by its position", {
				id = "native_parity_media::badge::gives an icon badge the plain caption height and orders the icon by its position",
				run = function()
					local engine, runtime, UI = make()
					local stop, root = mount(engine, runtime, function()
						return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
							UI.Badge "Plain" { label = "Ranked" } :: unknown,
							UI.Badge "Leading" { label = "Ranked", icon = "checkmark" },
							UI.Badge "Trailing" { label = "Ranked", icon = "checkmark", iconPosition = "trailing" },
							UI.Badge "Large" { label = "Ranked", icon = "checkmark", controlSize = "large" :: "large" },
						})
					end)
					local plain = root:FindFirstChild("Plain", true)
					local leading = root:FindFirstChild("Leading", true)
					local trailing = root:FindFirstChild("Trailing", true)
					local large = root:FindFirstChild("Large", true)
					Verify.expect(plain.ClassName):toBe("TextLabel")
					Verify.expect(plain.Size.Y.Offset):toBe(24)
					Verify.expect(leading.Size.Y.Offset):toBe(plain.Size.Y.Offset)
					Verify.expect(trailing.Size.Y.Offset):toBe(plain.Size.Y.Offset)
					Verify.expect(large.Size.Y.Offset):toBe(28)
					for _, badge in { leading, trailing } do
						Verify.expect(badge.ClassName):toBe("Frame")
						Verify.expect((badge:HasTag("facet-badge"))):toBe(true)
						Verify.expect(#badge:GetChildren()):toBe(3)
						Verify.expect(badge:FindFirstChildWhichIsA("UIListLayout").SortOrder)
							:toBe(engine.types.Enum.SortOrder.LayoutOrder)
						Verify.expect(badge:FindFirstChildWhichIsA("ImageLabel").Size)
							:toBe(engine.types.UDim2.fromOffset(14, 14))
					end
					Verify.expect(large:FindFirstChildWhichIsA("ImageLabel").Size)
						:toBe(engine.types.UDim2.fromOffset(17, 17))
					local leadingIcon, leadingLabel =
						leading:FindFirstChildWhichIsA("ImageLabel"), leading:FindFirstChild("Label")
					local trailingIcon, trailingLabel =
						trailing:FindFirstChildWhichIsA("ImageLabel"), trailing:FindFirstChild("Label")
					Verify.expect(leadingIcon.LayoutOrder):toBeLessThan(leadingLabel.LayoutOrder)
					Verify.expect(trailingIcon.LayoutOrder):toBeGreaterThan(trailingLabel.LayoutOrder)
					stop()
					runtime:dispose()
				end,
			})

			verifyHarness:case(
				"paints the status appearance as a neutral pill with a leading dot and utility as plateless",
				{
					id = "native_parity_media::badge::paints the status appearance as a neutral pill with a leading dot and utility as plateless",
					run = function()
						local engine, runtime, UI = make()
						local appearance = Compose.cell("status")
						local package = themes.neutralPackage()
						local sheet, badge: any
						local stop = mount(engine, runtime, function()
							sheet = themes.createStyleSheet(runtime, package, { types = engine.types })
							badge = UI.Badge({ label = "Live", status = "error", appearance = appearance })
							return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
								sheet :: unknown,
								badge,
							})
						end)
						local palette: any = package.style.themes[1]
						local statusRule, errorRule =
							style(sheet, ".facet-badge-status"), style(sheet, ".facet-status-error")
						Verify.expect(statusRule.Priority):toBeGreaterThan(errorRule.Priority)
						Verify.expect(statusRule:GetProperties().BackgroundColor3)
							:toBe(color(engine, palette.extra.control))
						Verify.expect(errorRule:GetProperties().BackgroundColor3)
							:toBe(color(engine, palette.colors.danger))
						Verify.expect((badge:HasTag("facet-badge-status"))):toBe(true)
						local dot = badge:FindFirstChild("Status")
						Verify.expect(dot ~= nil):toBe(true)
						Verify.expect((dot:HasTag("facet-status-error"))):toBe(true)
						Verify.expect(dot.LayoutOrder):toBe(-1)
						Verify.expect(dot.Size):toBe(engine.types.UDim2.fromOffset(8, 8))
						appearance:set("utility")
						Verify.expect((badge:HasTag("facet-badge-utility"))):toBe(true)
						Verify.expect((badge:HasTag("facet-badge-status"))):toBe(false)
						Verify.expect((badge:FindFirstChild("Status"))):toBeNil()
						Verify.expect((dot.isDestroyed())):toBe(true)
						Verify.expect(style(sheet, ".facet-badge-utility"):GetProperties().BackgroundTransparency)
							:toBe(1)
						Verify.expect(style(sheet, ".facet-badge-utility"):GetProperties().TextColor3)
							:toBe(color(engine, palette.extra.contentSecondary))
						appearance:set("standard")
						Verify.expect((badge:HasTag("facet-badge-standard"))):toBe(true)
						Verify.expect((badge:HasTag("facet-badge-utility"))):toBe(false)
						Verify.expect((badge:FindFirstChild("Status"))):toBeNil()
						appearance:set("status")
						Verify.expect((badge:FindFirstChild("Status"):HasTag("facet-status-error"))):toBe(true)
						stop()
						runtime:dispose()
					end,
				}
			)

			verifyHarness:case("mounts and clears a live caption on a named icon badge while the plate and icon stay", {
				id = "native_parity_media::badge::mounts and clears a live caption on a named icon badge while the plate and icon stay",
				run = function()
					local engine, runtime, UI = make()
					local caption = Compose.cell(nil :: string?)
					local stop, badge: any = mount(engine, runtime, function()
						return UI.Badge({ label = caption, icon = "checkmark", name = "Info" })
					end)
					local label, icon = badge:FindFirstChild("Label"), badge:FindFirstChildWhichIsA("ImageLabel")
					Verify.expect(label.Text):toBe("")
					Verify.expect((badge:GetAttribute("AccessibleLabel"))):toBe(nil)
					Verify.expect((label:GetAttribute("AccessibleLabel"))):toBe("Info")
					caption:set("Ready")
					Verify.expect(label.Text):toBe("Ready")
					Verify.expect((badge:FindFirstChild("Label"))):toBe(label)
					Verify.expect((badge:FindFirstChildWhichIsA("ImageLabel"))):toBe(icon)
					caption:set(nil)
					Verify.expect(label.Text):toBe("")
					Verify.expect((badge:FindFirstChild("Label"))):toBe(label)
					Verify.expect((badge:FindFirstChildWhichIsA("ImageLabel"))):toBe(icon)
					Verify.expect((label.isDestroyed())):toBe(false)
					Verify.expect((icon.isDestroyed())):toBe(false)
					stop()
					runtime:dispose()
				end,
			})
		end)

		verifyHarness:suite("avatar", function()
			verifyHarness:case("suppresses the presence mark but keeps presence in the accessible label", {
				id = "native_parity_media::avatar::suppresses the presence mark but keeps presence in the accessible label",
				run = function()
					local engine, runtime, UI = make()
					local members = {
						{ id = "a", name = "Ada", presence = "away" },
						{ id = "b", name = "Bo", presence = "online" },
					}
					local stop, root = mount(engine, runtime, function()
						return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
							UI.Avatar "Hidden" { name = "Ada", presence = "away", presenceMark = false } :: unknown,
							UI.Avatar "Shown" { name = "Ada", presence = "away" },
							UI.AvatarGroup "Stacked" { items = members },
							UI.AvatarGroup "Spread" { items = members, layout = "spread" },
						})
					end)
					local hidden, shown = root:FindFirstChild("Hidden", true), root:FindFirstChild("Shown", true)
					Verify.expect((hidden:FindFirstChild("Presence"))):toBeNil()
					Verify.expect((hidden:GetAttribute("AccessibleLabel"))):toBe("Ada, away")
					Verify.expect(shown:FindFirstChild("Presence") ~= nil):toBe(true)
					Verify.expect((shown:GetAttribute("AccessibleLabel"))):toBe("Ada, away")
					local stacked, spread = root:FindFirstChild("Stacked", true), root:FindFirstChild("Spread", true)
					for _, id in { "a", "b" } do
						Verify.expect((stacked:FindFirstChild(id):FindFirstChild("Presence"))):toBeNil()
						Verify.expect(spread:FindFirstChild(id):FindFirstChild("Presence") ~= nil):toBe(true)
					end
					Verify.expect((stacked:FindFirstChild("a"):GetAttribute("AccessibleLabel"))):toBe("Ada, away")
					Verify.expect(
						(spread:FindFirstChild("b"):FindFirstChild("Presence"):HasTag("facet-status-success"))
					)
						:toBe(true)
					stop()
					runtime:dispose()
				end,
			})

			verifyHarness:case("refuses an invalid name, form, presence or option before acquiring the resource", {
				id = "native_parity_media::avatar::refuses an invalid name, form, presence or option before acquiring the resource",
				run = function()
					local acquired = 0
					local function resource()
						acquired += 1
						return { state = Compose.cell("ready"), value = Compose.cell("rbxassetid://5") }
					end
					local cases: { { any } } = {
						{ {}, "Avatar name must be nonempty" },
						{ { name = "" }, "Avatar name must be nonempty" },
						{ { name = "A", form = "photo" }, "Avatar invalid form" },
						{ { name = "A", presence = "wrong" }, "Avatar invalid presence" },
						{ { name = "A", unexpected = true }, "unknown option 'unexpected'" },
					}
					for _, case in cases do
						local spec = table.clone(case[1])
						spec.resource = resource
						local refused = refusal(function(UI: FacetControls)
							return UI.Avatar(spec :: any)
						end)
						Verify.expect((refusedWith(refused, case[2]))):toBe(true)
						Verify.expect(acquired):toBe(0)
					end
					local engine, runtime, UI = make()
					local stop, avatar = mount(engine, runtime, function()
						return UI.Avatar({ name = "A", resource = resource })
					end)
					Verify.expect(acquired):toBe(1)
					Verify.expect(avatar:FindFirstChild("Image", true).Image):toBe("rbxassetid://5")
					stop()
					runtime:dispose()
				end,
			})

			verifyHarness:case("refuses a non-string overflow label and recovers the next valid label", {
				id = "native_parity_media::avatar::refuses a non-string overflow label and recovers the next valid label",
				run = function()
					local engine, runtime, UI = make()
					local label = Compose.cell("More" :: any)
					local stop, group = mount(engine, runtime, function()
						return UI.AvatarGroup({
							items = {
								{ id = "a", name = "Ada" },
								{ id = "b", name = "Bo" },
								{ id = "c", name = "Cy" },
							},
							max = 1,
							overflowLabel = label,
						})
					end)
					local overflow = group:FindFirstChild("Overflow")
					Verify.expect((overflow:GetAttribute("AccessibleLabel"))):toBe("More")
					Verify.expect(overflow.Text):toBe("+2")
					Verify.expect((pcall(function()
						label:set(42)
					end))):toBe(false)
					Verify.expect((overflow:GetAttribute("AccessibleLabel"))):toBe("More")
					label:set("Tout")
					Verify.expect((overflow:GetAttribute("AccessibleLabel"))):toBe("Tout")
					label:set(nil)
					Verify.expect((overflow:GetAttribute("AccessibleLabel"))):toBe("2 more players")
					Verify.expect((group:FindFirstChild("Overflow"))):toBe(overflow)
					stop()
					runtime:dispose()
				end,
			})
		end)

		verifyHarness:suite("skeleton and status indicator", function()
			verifyHarness:case("sizes a skeleton by a bound rung, refuses an unknown rung and recovers", {
				id = "native_parity_media::skeleton and status indicator::sizes a skeleton by a bound rung, refuses an unknown rung and recovers",
				run = function()
					local engine, runtime, UI = make()
					local rung = Compose.cell("compact" :: string?)
					local stop, root = mount(engine, runtime, function()
						return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
							UI.Skeleton "Circle" { form = "circle", controlSize = rung } :: unknown,
							UI.Skeleton "Line" { form = "line", controlSize = rung },
						})
					end)
					local circle = root:FindFirstChild("Circle", true):FindFirstChild("Placeholder1")
					local line = root:FindFirstChild("Line", true):FindFirstChild("Placeholder1")
					Verify.expect(circle.Size):toBe(engine.types.UDim2.fromOffset(36, 36))
					Verify.expect(line.Size):toBe(engine.types.UDim2.new(1, 0, 0, 16))
					rung:set("large")
					Verify.expect(circle.Size):toBe(engine.types.UDim2.fromOffset(56, 56))
					Verify.expect(line.Size):toBe(engine.types.UDim2.new(1, 0, 0, 24))
					rung:set(nil)
					Verify.expect(circle.Size):toBe(engine.types.UDim2.fromOffset(44, 44))
					Verify.expect(line.Size):toBe(engine.types.UDim2.new(1, 0, 0, 20))
					Verify.expect((pcall(function()
						rung:set("wrong")
					end))):toBe(false)
					Verify.expect(circle.Size):toBe(engine.types.UDim2.fromOffset(44, 44))
					rung:set("large")
					Verify.expect(circle.Size):toBe(engine.types.UDim2.fromOffset(56, 56))
					Verify.expect(line.Size):toBe(engine.types.UDim2.new(1, 0, 0, 24))
					stop()
					runtime:dispose()
				end,
			})

			verifyHarness:case("refuses malformed skeleton declarations and leaves no shared clock running", {
				id = "native_parity_media::skeleton and status indicator::refuses malformed skeleton declarations and leaves no shared clock running",
				run = function()
					local cases: { { any } } = {
						{ { form = "wrong" }, "Skeleton invalid form" },
						{ { form = "box", lines = 2 }, "lines require line form" },
						{ { form = "line", lines = 0 }, "lines must be positive" },
						{ { form = "line", lines = 1.5 }, "lines must be positive" },
						{ { form = "circle", corners = "pill" :: "pill" }, "circle owns its corners" },
						{ { form = "box", surprise = true }, "unknown option 'surprise'" },
					}
					for _, case in cases do
						local refused = refusal(function(UI: FacetControls)
							return UI.Skeleton(case[1])
						end)
						Verify.expect((refusedWith(refused, case[2]))):toBe(true)
						Verify.expect(refused.heartbeat):toBe(0)
						Verify.expect(refused.live):toBe(0)
					end
				end,
			})

			verifyHarness:case(
				"releases the shared skeleton clock after a construction refuses and restarts it for the next",
				{
					id = "native_parity_media::skeleton and status indicator::releases the shared skeleton clock after a construction refuses and restarts it for the next",
					run = function()
						local engine, runtime, UI = make()
						Verify.expect(function()
							mount(engine, runtime, function()
								return UI.Skeleton({ form = "box", controlSize = "wrong" :: "wrong" })
							end)
						end):toThrow()
						Verify.expect((engine.heartbeat.count())):toBe(0)
						local stop, root = mount(engine, runtime, function()
							return UI.Skeleton({ form = "box" })
						end)
						Verify.expect((engine.heartbeat.count())):toBeGreaterThan(0)
						local shimmer = root:FindFirstChild("Shimmer", true)
						local before = shimmer.Offset.X
						engine.heartbeat.fire(0.2)
						Verify.expect(shimmer.Offset.X):toBeGreaterThan(before)
						stop()
						Verify.expect((engine.heartbeat.count())):toBe(0)
						runtime:dispose()
					end,
				}
			)

			verifyHarness:case("sizes a status indicator by the checked rung metrics and falls back to regular", {
				id = "native_parity_media::skeleton and status indicator::sizes a status indicator by the checked rung metrics and falls back to regular",
				run = function()
					local engine, runtime, UI = make()
					local rung = Compose.cell("compact" :: string?)
					local stop, root = mount(engine, runtime, function()
						return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
							UI.StatusIndicator "Sized" { status = "info", controlSize = rung } :: unknown,
							UI.StatusIndicator "Plain" { status = "info" },
						})
					end)
					local sized, plain = root:FindFirstChild("Sized", true), root:FindFirstChild("Plain", true)
					local metrics = themes.neutralPackage().metrics.controlSizes
					Verify.expect(sized.Size)
						:toBe(engine.types.UDim2.fromOffset(metrics.compact.iconSize, metrics.compact.iconSize))
					Verify.expect(plain.Size):toBe(engine.types.UDim2.fromOffset(12, 12))
					rung:set("large")
					Verify.expect(sized.Size)
						:toBe(engine.types.UDim2.fromOffset(metrics.large.iconSize, metrics.large.iconSize))
					rung:set(nil)
					Verify.expect(sized.Size)
						:toBe(engine.types.UDim2.fromOffset(metrics.regular.iconSize, metrics.regular.iconSize))
					Verify.expect((pcall(function()
						rung:set("tiny")
					end))):toBe(false)
					Verify.expect(sized.Size)
						:toBe(engine.types.UDim2.fromOffset(metrics.regular.iconSize, metrics.regular.iconSize))
					Verify.expect(plain.Size):toBe(engine.types.UDim2.fromOffset(12, 12))
					stop()
					runtime:dispose()
				end,
			})
		end)

		verifyHarness:suite("async image and stage", function()
			verifyHarness:case("blends a bound dimmed image and restores it", {
				id = "native_parity_media::async image and stage::blends a bound dimmed image and restores it",
				run = function()
					local engine, runtime, UI = make()
					local dimmed = Compose.cell(false)
					local stop, root = mount(engine, runtime, function()
						return UI.AsyncImage({ image = "rbxassetid://1", dimmed = dimmed })
					end)
					local image = root:FindFirstChild("Image")
					Verify.expect(image.Image):toBe("rbxassetid://1")
					Verify.expect(image.ImageTransparency):toBe(0)
					dimmed:set(true)
					Verify.expect(image.ImageTransparency):toBe(0.35)
					dimmed:set(false)
					Verify.expect(image.ImageTransparency):toBe(0)
					Verify.expect((root:FindFirstChild("Image"))):toBe(image)
					stop()
					runtime:dispose()
				end,
			})

			verifyHarness:case(
				"places an owned stage camera by CFrame and field of view and destroys it with the stage",
				{
					id = "native_parity_media::async image and stage::places an owned stage camera by CFrame and field of view and destroys it with the stage",
					run = function()
						local engine, runtime, UI = make()
						local types = engine.types
						local first = types.CFrame.lookAt(types.Vector3.new(0, 4, 10), types.Vector3.new(0, 1, 0))
						local second = types.CFrame.lookAt(types.Vector3.new(6, 2, 0), types.Vector3.new(0, 0, 0))
						local placement, fieldOfView = Compose.cell(first), Compose.cell(55)
						local stop, stage = mount(engine, runtime, function()
							return UI.Stage({ camera = placement, fieldOfView = fieldOfView })
						end)
						local camera = stage.CurrentCamera
						Verify.expect(camera.ClassName):toBe("Camera")
						Verify.expect(camera.Parent):toBe(stage)
						Verify.expect(camera.CFrame):toBe(first)
						Verify.expect(camera.FieldOfView):toBe(55)
						fieldOfView:set(70)
						placement:set(second)
						Verify.expect(camera.FieldOfView):toBe(70)
						Verify.expect(camera.CFrame):toBe(second)
						Verify.expect(stage.CurrentCamera):toBe(camera)
						stop()
						Verify.expect((camera.isDestroyed())):toBe(true)
						local defaultStop, defaultStage = mount(engine, runtime, function()
							return UI.Stage({})
						end)
						Verify.expect(defaultStage.CurrentCamera.FieldOfView):toBe(45)
						Verify.expect(defaultStage.CurrentCamera.CFrame)
							:toBe(types.CFrame.lookAt(types.Vector3.new(0, 2, 8), types.Vector3.new(0, 0, 0)))
						defaultStop()
						runtime:dispose()
					end,
				}
			)
		end)

		verifyHarness:suite("icons", function()
			verifyHarness:case("resolves an unknown semantic icon to nothing and refuses to mount it", {
				id = "native_parity_media::icons::resolves an unknown semantic icon to nothing and refuses to mount it",
				run = function()
					local neutral = themes.neutralPackage()
					Verify.expect((themes.resolveIcon(neutral, "not.an.icon"))):toBeNil()
					Verify.expect(string.match(themes.resolveIcon(neutral, "close") or "", "^rbxassetid://%d+$") ~= nil)
						:toBe(true)
					local label = refusal(function(UI: FacetControls)
						return UI.Label({ title = "x", icon = "not.an.icon" })
					end)
					Verify.expect((refusedWith(label, "Facet UI.Label: unknown icon 'not.an.icon'"))):toBe(true)
					local button = refusal(function(UI: FacetControls)
						return UI.Button({ label = "x", icon = "nope" })
					end)
					Verify.expect((refusedWith(button, "Facet icon nope requires an image asset"))):toBe(true)
					local accepted = refusal(function(UI: FacetControls)
						return UI.Label({ title = "x", icon = "close" })
					end)
					Verify.expect(accepted.message):toBeNil()
				end,
			})

			verifyHarness:case("resolves the common framework icons to their standard art", {
				id = "native_parity_media::icons::resolves the common framework icons to their standard art",
				run = function()
					local neutral = themes.neutralPackage()
					for _, name in
						{
							"status.info",
							"status.success",
							"status.warning",
							"status.error",
							"calendar",
							"clock",
							"vote.up",
							"vote.down",
							"person",
							"chevron.first",
							"chevron.last",
						}
					do
						local art = icons.ART[name]
						Verify.expect(art ~= nil):toBe(true)
						Verify.expect(string.match(art.contentId, "^rbxassetid://%d+$") ~= nil):toBe(true)
						Verify.expect((themes.resolveIcon(neutral, name))):toBe(art.contentId)
					end
					Verify.expect(icons.ART["status.success"].contentId):toBe(icons.ART.checkmark.contentId)
					Verify.expect(icons.ART["status.warning"].contentId ~= icons.ART["status.error"].contentId)
						:toBe(true)
				end,
			})

			verifyHarness:case("treats contentId and content as the same asset spelling for skins and icons", {
				id = "native_parity_media::icons::treats contentId and content as the same asset spelling for skins and icons",
				run = function()
					for _, field in { "content", "contentId" } do
						local engine, runtime = make()
						local package: any = themes.neutralPackage()
						package.assets.panel =
							{ [field] = "rbxassetid://9", sliceCenter = { x0 = 12, y0 = 12, x1 = 52, y1 = 52 } }
						package.chrome.panel = { kind = "nineSlice" :: "nineSlice", asset = "panel" }
						package.icons["facet:search"] = { default = "panel" }
						local defined: any, report = themes.define(package)
						Verify.expect(report.ok):toBe(true)
						local stop, skin = mount(engine, runtime, function()
							return themes.skin(runtime, defined, "panel", { types = engine.types })
						end)
						local image = skin:FindFirstChild("panel1")
						Verify.expect(image.Image):toBe("rbxassetid://9")
						Verify.expect(image.ScaleType):toBe(engine.types.Enum.ScaleType.Slice)
						Verify.expect(image.SliceCenter):toBe(engine.types.Rect.new(12, 12, 52, 52))
						Verify.expect((themes.resolveIcon(defined, "facet:search"))):toBe("rbxassetid://9")
						local themed: any = Facet.controls(runtime, { types = engine.types, theme = defined } :: any)
						local labelStop, label = mount(engine, runtime, function()
							return themed.Label({ title = "Find", icon = "facet:search" })
						end)
						Verify.expect(label:FindFirstChildWhichIsA("ImageLabel").Image):toBe("rbxassetid://9")
						labelStop()
						stop()
						runtime:dispose()
					end
				end,
			})

			verifyHarness:case("frames a button image by crop by default and by fit on request", {
				id = "native_parity_media::icons::frames a button image by crop by default and by fit on request",
				run = function()
					local engine, runtime, UI = make()
					local stop, root = mount(engine, runtime, function()
						return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
							UI.Button "Default" { label = "x", image = "rbxassetid://1" } :: unknown,
							UI.Button "Crop" { label = "x", image = "rbxassetid://1", imageFraming = "crop" },
							UI.Button "Fit" { label = "x", image = "rbxassetid://1", imageFraming = "fit" },
						})
					end)
					local Enum = engine.types.Enum
					Verify.expect(root:FindFirstChild("Default", true):FindFirstChild("Image", true).ScaleType)
						:toBe(Enum.ScaleType.Crop)
					Verify.expect(root:FindFirstChild("Crop", true):FindFirstChild("Image", true).ScaleType)
						:toBe(Enum.ScaleType.Crop)
					Verify.expect(root:FindFirstChild("Fit", true):FindFirstChild("Image", true).ScaleType)
						:toBe(Enum.ScaleType.Fit)
					Verify.expect(root:FindFirstChild("Fit", true):FindFirstChild("Image", true).Image)
						:toBe("rbxassetid://1")
					stop()
					runtime:dispose()
					for _, framing in { "stretch" :: unknown, { width = 256, height = 256 } } do
						local refused = refusal(function(UI: FacetControls)
							return UI.Button({ label = "x", image = "rbxassetid://1", imageFraming = framing :: any })
						end)
						Verify.expect((refusedWith(refused, "imageFraming must be fit or crop"))):toBe(true)
						Verify.expect(refused.live):toBe(0)
						Verify.expect(refused.connections):toBe(0)
					end
				end,
			})
		end)

		verifyHarness:suite("refusals", function()
			verifyHarness:case("accepts every semantic button role and refuses an unknown one", {
				id = "native_parity_media::refusals::accepts every semantic button role and refuses an unknown one",
				run = function()
					local roles = { "default", "cancel", "destructive", "onIndicator" }
					for _, role in roles do
						local engine, runtime, UI = make()
						local stop, button = mount(engine, runtime, function()
							return UI.Button({ label = "x", role = role })
						end)
						for _, other in roles do
							Verify.expect((button:HasTag("facet-role-" .. other))):toBe(other == role)
						end
						Verify.expect((button:GetAttribute("role"))):toBe(role)
						stop()
						runtime:dispose()
					end
					Verify.expect((refusedWith(
						refusal(function(UI: FacetControls)
							return UI.Button({ label = "x", role = "danger" :: "danger" } :: any)
						end),
						"Facet.Button: invalid semantic role"
					))):toBe(true)
					local engine, runtime, UI = make()
					local role = Compose.cell("cancel")
					local stop, button = mount(engine, runtime, function()
						return UI.Button({ label = "x", role = role })
					end)
					Verify.expect((pcall(function()
						role:set("danger")
					end))):toBe(false)
					Verify.expect((button:HasTag("facet-role-cancel"))):toBe(true)
					Verify.expect((button:HasTag("facet-role-danger"))):toBe(false)
					role:set("destructive")
					Verify.expect((button:HasTag("facet-role-destructive"))):toBe(true)
					Verify.expect((button:HasTag("facet-role-cancel"))):toBe(false)
					stop()
					runtime:dispose()
				end,
			})

			verifyHarness:case("refuses an unknown or reactive button shape at construction", {
				id = "native_parity_media::refusals::refuses an unknown or reactive button shape at construction",
				run = function()
					for _, shape in { "oval", Compose.cell("circle") :: any } do
						local refused = refusal(function(UI: FacetControls)
							return UI.Button({ label = "x", shape = shape } :: any)
						end)
						Verify.expect((refusedWith(refused, "Facet.Button: shape must be rect or circle"))):toBe(true)
						Verify.expect(refused.created):toBe(0)
					end
					local engine, runtime, UI = make()
					local stop, root = mount(engine, runtime, function()
						return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
							UI.Button "Circle" { label = "x", shape = "circle" :: "circle" } :: unknown,
							UI.Button "Rect" { label = "x", shape = "rect" :: "rect" },
						})
					end)
					Verify.expect((root:FindFirstChild("Circle", true):HasTag("facet-shape-circle"))):toBe(true)
					Verify.expect((root:FindFirstChild("Rect", true):HasTag("facet-shape-circle"))):toBe(false)
					stop()
					runtime:dispose()
				end,
			})

			verifyHarness:case("refuses compactLabel on icon, image, subtitle and hint buttons", {
				id = "native_parity_media::refusals::refuses compactLabel on icon, image, subtitle and hint buttons",
				run = function()
					for _, extra in
						{
							{ icon = "rbxassetid://1" },
							{ trailingIcon = "rbxassetid://1" },
							{ image = "rbxassetid://1" },
							{ subtitle = "More" },
							{ hint = "More" },
						} :: { { [string]: any } }
					do
						local refused = refusal(function(UI: FacetControls)
							local spec: { [any]: any } = { label = "Continue", compactLabel = "Go" }
							for key, value in extra do
								spec[key] = value
							end
							return UI.Button(spec :: any)
						end)
						Verify.expect((refusedWith(refused, "Facet.Button: compactLabel requires a text button")))
							:toBe(true)
						Verify.expect(refused.live):toBe(0)
					end
					local engine, runtime, UI = make()
					local stop, button = mount(engine, runtime, function()
						return UI.Button({ label = "Continue", compactLabel = "Go" })
					end)
					Verify.expect(button:FindFirstChild("FullLabelMeasure").Text):toBe("Continue")
					Verify.expect(button.Text):toBe("Continue")
					stop()
					runtime:dispose()
				end,
			})

			verifyHarness:case("refuses a text input that supplies both enabled and disabled", {
				id = "native_parity_media::refusals::refuses a text input that supplies both enabled and disabled",
				run = function()
					local refused = refusal(function(UI: FacetControls)
						return UI.TextInput({ value = Compose.cell(""), enabled = true, disabled = false })
					end)
					Verify.expect((refusedWith(refused, "Facet.TextInput: use enabled or disabled, not both")))
						:toBe(true)
					Verify.expect(refused.created):toBe(0)
					for _, spec in { { enabled = false }, { disabled = true } } :: { { [string]: any } } do
						local engine, runtime, UI = make()
						local stop, box = mount(engine, runtime, function()
							local options = table.clone(spec)
							options.value = Compose.cell("")
							return UI.TextInput(options)
						end)
						Verify.expect(box.TextEditable):toBe(false)
						stop()
						runtime:dispose()
					end
				end,
			})

			verifyHarness:case("refuses nonfinite or inverted numeric bounds and non-function numeric callbacks", {
				id = "native_parity_media::refusals::refuses nonfinite or inverted numeric bounds and non-function numeric callbacks",
				run = function()
					local cases: { { any } } = {
						{ { min = 0 / 0 }, "numeric bounds must be finite" },
						{ { max = math.huge }, "numeric bounds must be finite" },
						{ { min = -math.huge }, "numeric bounds must be finite" },
						{ { min = "1" }, "numeric bounds must be finite" },
						{ { min = 5, max = 1 }, "min must not exceed max" },
						{ { parse = 5 }, "parse must be a function" },
						{ { format = true }, "format must be a function" },
						{ { validate = "x" }, "validate must be a function" },
					}
					for _, case in cases do
						local refused = refusal(function(UI: FacetControls)
							local spec = table.clone(case[1])
							spec.presentation = "number" :: "number"
							spec.value = Compose.cell("1")
							spec.numericValue = Compose.cell(1)
							return UI.TextInput(spec :: any)
						end)
						Verify.expect((refusedWith(refused, case[2]))):toBe(true)
						Verify.expect(refused.created):toBe(0)
					end
					local accepted = refusal(function(UI: FacetControls)
						return UI.TextInput({
							presentation = "number" :: "number",
							value = Compose.cell("1"),
							numericValue = Compose.cell(1),
							min = 1,
							max = 1,
							parse = tonumber,
							format = tostring,
						})
					end)
					Verify.expect(accepted.message):toBeNil()
				end,
			})

			verifyHarness:case("refuses an unknown control size and keeps the last legal size for a live rung", {
				id = "native_parity_media::refusals::refuses an unknown control size and keeps the last legal size for a live rung",
				run = function()
					for _, build in
						{
							function(UI: FacetControls)
								return UI.Button({ label = "Go", controlSize = ("tiny" :: unknown) :: ControlSizeValue })
							end,
							function(UI: FacetControls)
								return UI.ShortcutHint({
									keys = { { "Ctrl", "K" } },
									controlSize = ("tiny" :: unknown) :: ControlSizeValue,
								})
							end,
						} :: { (any) -> any }
					do
						Verify.expect(
							(refusedWith(refusal(build), "Facet controlSize must be xsmall, compact, regular or large"))
						)
							:toBe(true)
					end
					for _, bound in { "cell", "function" } do
						local engine, runtime, UI = make()
						local rung = Compose.cell("regular")
						local source: any = if bound == "cell"
							then rung
							else function(use: Use)
								return use(rung)
							end
						local stop, root = mount(engine, runtime, function()
							return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
								UI.Button "Go" { label = "Go", controlSize = source } :: unknown,
								UI.ShortcutHint "Hint" { keys = { { "Ctrl", "K" } }, controlSize = source },
							})
						end)
						local button, hint = root:FindFirstChild("Go", true), root:FindFirstChild("Hint", true)
						Verify.expect(button.Size.Y.Offset):toBe(44)
						Verify.expect(hint.Size.Y.Offset):toBe(28)
						Verify.expect((pcall(function()
							rung:set("tiny")
						end))):toBe(false)
						Verify.expect(button.Size.Y.Offset):toBe(44)
						Verify.expect(hint.Size.Y.Offset):toBe(28)
						rung:set("large")
						Verify.expect(button.Size.Y.Offset):toBe(56)
						Verify.expect(hint.Size.Y.Offset):toBe(32)
						rung:set("compact")
						Verify.expect(button.Size.Y.Offset):toBe(36)
						Verify.expect(hint.Size.Y.Offset):toBe(24)
						stop()
						runtime:dispose()
					end
				end,
			})

			verifyHarness:case(
				"refuses a combo box with a plain value, missing text, a non-function validator or an unknown key",
				{
					id = "native_parity_media::refusals::refuses a combo box with a plain value, missing text, a non-function validator or an unknown key",
					run = function()
						local function spec(overrides: { [string]: any }): FixtureNavigationTypes.ComboBoxSpec
							local result: FixtureNavigationTypes.ComboBoxSpec = {
								value = Compose.cell("a"),
								text = Compose.cell("A"),
								options = { { value = "a", label = "A" } },
								acceptCustom = function(_: string): (boolean, string?)
									return false, nil
								end,
							}
							for key, value in overrides do
								(result :: any)[key] = if value == "nil" then nil else value
							end
							return result
						end
						local cases: { { any } } = {
							{ { value = "a" }, "ComboBox.value requires a writable Compose cell" },
							{ { value = Compose.cell(5) }, "ComboBox.value must be a string" },
							{ { options = "nil" }, "ComboBox requires options" },
							{ { options = "a" }, "ComboBox requires options" },
							{ { text = Compose.cell(5) }, "TextInput: value must resolve to a string" },
							{ { text = "nil" }, "ComboBox.text requires a writable Compose cell" },
							{ { text = "A" }, "ComboBox.text requires a writable Compose cell" },
							{ { acceptCustom = true }, "ComboBox requires acceptCustom" },
							{ { acceptCustom = "nil" }, "ComboBox requires acceptCustom" },
							{ { bogus = 1 }, "unknown option 'bogus'" },
						}
						for _, case in cases do
							local refused = refusal(function(UI: FacetControls)
								return UI.ComboBox(spec(case[1]))
							end)
							Verify.expect((refusedWith(refused, case[2]))):toBe(true)
							Verify.expect(refused.live):toBe(0)
							Verify.expect(refused.connections):toBe(0)
						end
						Verify.expect(refusal(function(UI: FacetControls)
							return UI.ComboBox(spec({}))
						end).message):toBeNil()
						Verify.expect(refusal(function(UI: FacetControls)
							return UI.ComboBox(spec({ options = Compose.cell({ { value = "a", label = "A" } }) }))
						end).message):toBeNil()
					end,
				}
			)

			verifyHarness:case("refuses an unknown enumeration value on every documented vocabulary without leaking", {
				id = "native_parity_media::refusals::refuses an unknown enumeration value on every documented vocabulary without leaking",
				run = function()
					local function content(Host: any): () -> any
						return function()
							return Host.Frame({})
						end
					end
					local function radial(option: string): (any, any, any) -> any
						return function(UI: FacetControls, _, value)
							local spec: { [any]: any } =
								{ items = { { id = "a", label = "A", onSelect = function() end } } }
							spec[option] = value
							return UI.RadialMenu(spec)
						end
					end
					local cases: { { any } } = {
						{
							"Button shape",
							"circle",
							"oval",
							"shape must be rect or circle",
							function(UI: FacetControls, _, v)
								return UI.Button({ label = "Go", shape = v })
							end,
						},
						{
							"Button corners",
							"square",
							"rounded",
							"corners must be pill or square",
							function(UI: FacetControls, _, v)
								return UI.Button({ label = "Go", corners = v })
							end,
						},
						{
							"Button dialogAction",
							"cancel",
							"confirm",
							"invalid dialogAction",
							function(UI: FacetControls, _, v)
								return UI.Button({ label = "Go", dialogAction = v })
							end,
						},
						{
							"Button role",
							"destructive",
							"danger",
							"invalid semantic role",
							function(UI: FacetControls, _, v)
								return UI.Button({ label = "Go", role = v })
							end,
						},
						{
							"Button controlSize",
							"large",
							"tiny",
							"compact, regular or large",
							function(UI: FacetControls, _, v)
								return UI.Button({ label = "Go", controlSize = v })
							end,
						},
						{
							"Chip controlSize",
							"compact",
							"tiny",
							"compact, regular or large",
							function(UI: FacetControls, _, v)
								return UI.Chip({ label = "Go", selected = Compose.cell(false), controlSize = v })
							end,
						},
						{
							"Toggle presentation",
							"checkbox",
							"radio",
							"Toggle: invalid presentation",
							function(UI: FacetControls, _, v)
								return UI.Toggle({ value = Compose.cell(false), presentation = v })
							end,
						},
						{
							"Toggle indicatorPosition",
							"trailing",
							"above",
							"Toggle: invalid indicatorPosition",
							function(UI: FacetControls, _, v)
								return UI.Toggle({ value = Compose.cell(false), indicatorPosition = v })
							end,
						},
						{
							"TextInput presentation",
							"search",
							"email",
							"TextInput: invalid presentation",
							function(UI: FacetControls, _, v)
								return UI.TextInput({ value = Compose.cell(""), presentation = v })
							end,
						},
						{
							"TextInput clearButtonMode",
							"whileEditing",
							"often",
							"invalid clearButtonMode",
							function(UI: FacetControls, _, v)
								return UI.TextInput({ value = Compose.cell(""), clearButtonMode = v })
							end,
						},
						{
							"Rating starSize",
							"large",
							"huge",
							"invalid size",
							function(UI: FacetControls, _, v)
								return UI.Rating({ value = Compose.cell(1), starSize = v })
							end,
						},
						{
							"LevelPicker segment",
							"glyph",
							"dot",
							"invalid segment",
							function(UI: FacetControls, _, v)
								return UI.LevelPicker({ value = Compose.cell(1), segment = v })
							end,
						},
						{
							"LevelPicker segmentSize",
							"medium",
							"huge",
							"invalid size",
							function(UI: FacetControls, _, v)
								return UI.LevelPicker({ value = Compose.cell(1), segmentSize = v })
							end,
						},
						{
							"ShortcutHint controlSize",
							"large",
							"tiny",
							"compact, regular or large",
							function(UI: FacetControls, _, v)
								return UI.ShortcutHint({ keys = { { "Ctrl", "K" } }, controlSize = v })
							end,
						},
						{
							"Picker style",
							"inline",
							"carousel",
							"Unknown Picker style",
							function(UI: FacetControls, _, v)
								return UI.Picker({
									selected = Compose.cell("a"),
									options = {
										{ value = "a", label = "A" } :: FixtureNavigationTypes.PickerOption<any>,
									},
									style = v,
								})
							end,
						},
						{
							"Picker indicator",
							"underline",
							"dot",
							"Invalid Picker.indicator",
							function(UI: FacetControls, _, v)
								return UI.Picker({
									selected = Compose.cell("a"),
									options = {
										{ value = "a", label = "A" } :: FixtureNavigationTypes.PickerOption<any>,
									},
									style = "segmented" :: "segmented",
									indicator = v,
								})
							end,
						},
						{
							"Picker axis",
							"y",
							"z",
							"Picker.axis must be x or y",
							function(UI: FacetControls, _, v)
								return UI.Picker({
									selected = Compose.cell("a"),
									options = {
										{ value = "a", label = "A" } :: FixtureNavigationTypes.PickerOption<any>,
									},
									style = "segmented" :: "segmented",
									axis = v,
								})
							end,
						},
						{
							"Picker sizing",
							"hug",
							"auto",
							"Picker.sizing must be fill or hug",
							function(UI: FacetControls, _, v)
								return UI.Picker({
									selected = Compose.cell("a"),
									options = {
										{ value = "a", label = "A" } :: FixtureNavigationTypes.PickerOption<any>,
									},
									style = "segmented" :: "segmented",
									sizing = v,
								})
							end,
						},
						{
							"TabView style",
							"collapsible",
							"floating",
							"Invalid TabView.style",
							function(UI: FacetControls, Host: RobloxHost, v)
								return UI.TabView({
									selection = Compose.cell("a"),
									tabs = {
										{ id = "a", label = "A", content = content(Host) } :: FixtureNavigationTypes.Tab,
									},
									style = v,
								})
							end,
						},
						{
							"TabView retention",
							"top",
							"some",
							"TabView.retention uses Compose all or top",
							function(UI: FacetControls, Host: RobloxHost, v)
								return UI.TabView({
									selection = Compose.cell("a"),
									tabs = {
										{ id = "a", label = "A", content = content(Host) } :: FixtureNavigationTypes.Tab,
									},
									retention = v,
								})
							end,
						},
						{
							"DisclosureGroup chevronPosition",
							"trailing",
							"above",
							"Invalid DisclosureGroup.chevronPosition",
							function(UI: FacetControls, Host: RobloxHost, v)
								return UI.DisclosureGroup({
									label = "More",
									expanded = Compose.cell(false),
									content = content(Host),
									chevronPosition = v,
								})
							end,
						},
						{
							"DisclosureGroup appearance",
							"contained",
							"boxed",
							"Invalid DisclosureGroup.appearance",
							function(UI: FacetControls, Host: RobloxHost, v)
								return UI.DisclosureGroup({
									label = "More",
									expanded = Compose.cell(false),
									content = content(Host),
									appearance = v,
								})
							end,
						},
						{
							"Alert surface",
							"fullScreen",
							"sheet",
							"Alert.surface must be dialog or fullScreen",
							function(UI: FacetControls, _, v)
								return UI.Alert({
									isPresented = Compose.cell(false),
									title = "Title",
									actions = {
										{ id = "ok", label = "OK", role = "default" :: "default" } :: FixtureNavigationTypes.AlertAction<any>,
									},
									surface = v,
								})
							end,
						},
						{
							"RadialMenu appearance",
							"buttons",
							"ring",
							"RadialMenu invalid appearance",
							radial("appearance"),
						},
						{ "RadialMenu follow", "always", "never", "RadialMenu invalid follow", radial("follow") },
						{
							"RadialMenu gestureSelection",
							"direction",
							"angle",
							"RadialMenu invalid gestureSelection",
							radial("gestureSelection"),
						},
						{
							"RadialMenu contentFit",
							"radial",
							"stretch",
							"RadialMenu invalid contentFit",
							radial("contentFit"),
						},
						{
							"RadialMenu navigation",
							"expand",
							"push",
							"RadialMenu invalid navigation",
							radial("navigation"),
						},
						{
							"RadialMenu expansion",
							"ring",
							"spiral",
							"RadialMenu invalid expansion",
							radial("expansion"),
						},
						{ "RadialMenu center", "close", "middle", "RadialMenu invalid center", radial("center") },
						{
							"RadialMenu completion",
							"stay",
							"exit",
							"RadialMenu invalid completion",
							radial("completion"),
						},
						{
							"RadialMenu buttonSurface",
							"none",
							"glass",
							"RadialMenu invalid buttonSurface",
							radial("buttonSurface"),
						},
						{
							"VirtualList snap",
							"item",
							"row",
							"snap must be none or item",
							function(UI: FacetControls, Host: RobloxHost, v)
								return UI.VirtualList({ from = {}, render = content(Host), snap = v })
							end,
						},
						{
							"VirtualGrid snap",
							"none",
							"page",
							"snap must be none or item",
							function(UI: FacetControls, Host: RobloxHost, v)
								return UI.VirtualGrid({ from = {}, render = content(Host), snap = v })
							end,
						},
						{
							"Badge appearance",
							"utility",
							"loud",
							"Facet Badge invalid appearance",
							function(UI: FacetControls, _, v)
								return UI.Badge({ label = "New", appearance = v })
							end,
						},
						{
							"Badge status",
							"warning",
							"danger",
							"Facet: invalid status",
							function(UI: FacetControls, _, v)
								return UI.Badge({ label = "New", status = v })
							end,
						},
						{
							"Badge corners",
							"capsule",
							"round",
							"Facet Badge invalid corners",
							function(UI: FacetControls, _, v)
								return UI.Badge({ label = "New", corners = v })
							end,
						},
						{
							"Badge controlSize",
							"compact",
							"tiny",
							"compact, regular or large",
							function(UI: FacetControls, _, v)
								return UI.Badge({ label = "New", controlSize = v })
							end,
						},
						{
							"StatusIndicator status",
							"accent",
							"critical",
							"Facet: invalid status",
							function(UI: FacetControls, _, v)
								return UI.StatusIndicator({ status = v })
							end,
						},
						{
							"StatusIndicator form",
							"square",
							"star",
							"Facet StatusIndicator invalid form",
							function(UI: FacetControls, _, v)
								return UI.StatusIndicator({ status = "info" :: "info", form = v })
							end,
						},
						{
							"StatusIndicator controlSize",
							"large",
							"tiny",
							"compact, regular or large",
							function(UI: FacetControls, _, v)
								return UI.StatusIndicator({ status = "info" :: "info", controlSize = v })
							end,
						},
						{
							"ProgressView presentation",
							"spinner",
							"ring",
							"presentation must be bar, circular or spinner",
							function(UI: FacetControls, _, v)
								return UI.ProgressView({ value = 1, presentation = v })
							end,
						},
						{
							"ProgressView controlSize",
							"compact",
							"tiny",
							"compact, regular or large",
							function(UI: FacetControls, _, v)
								return UI.ProgressView({
									value = 1,
									presentation = "circular" :: "circular",
									controlSize = v,
								})
							end,
						},
						{
							"Skeleton form",
							"circle",
							"oval",
							"Facet Skeleton invalid form",
							function(UI: FacetControls, _, v)
								return UI.Skeleton({ form = v })
							end,
						},
						{
							"Skeleton corners",
							"pill",
							"round",
							"Facet Skeleton invalid corners",
							function(UI: FacetControls, _, v)
								return UI.Skeleton({ form = "box" :: "box", corners = v })
							end,
						},
						{
							"Skeleton controlSize",
							"large",
							"tiny",
							"compact, regular or large",
							function(UI: FacetControls, _, v)
								return UI.Skeleton({ controlSize = v })
							end,
						},
						{
							"Avatar form",
							"icon",
							"photo",
							"Facet Avatar invalid form",
							function(UI: FacetControls, _, v)
								return UI.Avatar({ name = "Ada", form = v })
							end,
						},
						{
							"Avatar presence",
							"busy",
							"idle",
							"Facet Avatar invalid presence",
							function(UI: FacetControls, _, v)
								return UI.Avatar({ name = "Ada", presence = v })
							end,
						},
						{
							"Avatar controlSize",
							"compact",
							"tiny",
							"compact, regular or large",
							function(UI: FacetControls, _, v)
								return UI.Avatar({ name = "Ada", controlSize = v })
							end,
						},
						{
							"AvatarGroup layout",
							"spread",
							"grid",
							"Facet AvatarGroup invalid layout",
							function(UI: FacetControls, _, v)
								return UI.AvatarGroup({ items = { { id = "a", name = "Ada" } }, layout = v })
							end,
						},
						{
							"AvatarGroup overflow",
							"ellipsis",
							"hidden",
							"Facet AvatarGroup invalid overflow",
							function(UI: FacetControls, _, v)
								return UI.AvatarGroup({ items = { { id = "a", name = "Ada" } }, overflow = v })
							end,
						},
						{
							"AvatarGroup controlSize",
							"large",
							"tiny",
							"compact, regular or large",
							function(UI: FacetControls, _, v)
								return UI.AvatarGroup({ items = { { id = "a", name = "Ada" } }, controlSize = v })
							end,
						},
					}
					local failures = {}
					for _, case in cases do
						local name, good, bad, fragment, build = case[1], case[2], case[3], case[4], case[5]
						local accepted = refusal(function(UI: FacetControls, Host: RobloxHost)
							return build(UI, Host, good)
						end)
						local refused = refusal(function(UI: FacetControls, Host: RobloxHost)
							return build(UI, Host, bad)
						end)
						if accepted.message ~= nil then
							table.insert(failures, `{name} refused {good}: {accepted.message}`)
						elseif not refusedWith(refused, fragment) then
							table.insert(
								failures,
								`{name} did not refuse {bad} with {fragment}: {tostring(refused.message)}`
							)
						elseif refused.live ~= 0 or refused.connections ~= 0 or refused.heartbeat ~= 0 then
							table.insert(
								failures,
								`{name} leaked {refused.live} nodes, {refused.connections} connections, {refused.heartbeat} frames`
							)
						end
					end
					Verify.expect((table.concat(failures, "\n"))):toBe("")
					Verify.expect(#cases):toBe(52)
				end,
			})
		end)

		verifyHarness:suite("controls", function()
			local function session(build: (any, any) -> any, prepare: ((any, any) -> ())?): { [string]: any }
				local engine: any = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local gui = engine.new("GuiService")
				local input = engine.new("UserInputService")
				input.GetFocusedTextBox = function()
					return nil
				end
				input.IsKeyDown = function()
					return false
				end
				if prepare then
					prepare(gui, input)
				end
				local UI = Facet.controls(
					runtime,
					{
						types = engine.types,
						guiService = gui,
						services = { GuiService = gui, UserInputService = input },
					} :: any
				)
				local Host = (runtime.constructors :: unknown) :: RobloxHost
				local stop, screen: any = runtime.mount(function()
					return Host.ScreenGui({ build(UI, Host) })
				end, engine.new("Folder"))
				return {
					engine = engine,
					runtime = runtime,
					gui = gui,
					input = input,
					screen = screen,
					find = function(name: string): any
						return screen:FindFirstChild(name, true)
					end,
					stop = function()
						stop()
						runtime:dispose()
					end,
				}
			end

			local function press(engine: any, node: any)
				local Enum = engine.types.Enum
				node.InputBegan.fire({
					UserInputType = Enum.UserInputType.MouseButton1,
					KeyCode = Enum.KeyCode:FromValue(0),
				})
			end

			local function release(engine: any, node: any)
				local Enum = engine.types.Enum
				node.InputEnded.fire({
					UserInputType = Enum.UserInputType.MouseButton1,
					KeyCode = Enum.KeyCode:FromValue(0),
				})
			end

			verifyHarness:case("adds no pop scale without pop and does not re-kick pop on held repeats", {
				id = "native_parity_media::controls::adds no pop scale without pop and does not re-kick pop on held repeats",
				run = function()
					local activations = 0
					local w = session(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.Button "Plain" { label = "x", onActivate = function() end } :: unknown,
							UI.Button "Held" {
								label = "x",
								pop = true,
								repeatInterval = 0.1,
								onActivate = function()
									activations += 1
								end,
							},
						})
					end)
					Verify.expect((w.find("Plain"):FindFirstChild("Pop"))):toBeNil()
					Verify.expect((w.find("Plain"):FindFirstChildWhichIsA("UIScale"))):toBeNil()
					local held = w.find("Held")
					local pop = held:FindFirstChild("Pop")
					Verify.expect(pop.ClassName):toBe("UIScale")
					Verify.expect(pop.Scale):toBe(1)
					press(w.engine, held)
					w.engine.heartbeat.fire(0.4)
					Verify.expect(activations):toBe(1)
					Verify.expect(pop.Scale):toBe(1)
					w.engine.heartbeat.fire(0.1)
					Verify.expect(activations):toBe(2)
					Verify.expect(pop.Scale):toBe(1)
					w.engine.heartbeat.fire(0.1)
					Verify.expect(activations):toBe(3)
					Verify.expect(pop.Scale):toBe(1)
					release(w.engine, held)
					held.Activated.fire()
					Verify.expect(activations):toBe(3)
					held.Activated.fire()
					Verify.expect(activations):toBe(4)
					w.engine.heartbeat.fire(0.1)
					Verify.expect(pop.Scale):toBeGreaterThan(1)
					w.stop()
				end,
			})

			verifyHarness:case("follows GuiService reduced motion for button pop, validation pulse and busy dots", {
				id = "native_parity_media::controls::follows GuiService reduced motion for button pop, validation pulse and busy dots",
				run = function()
					local function run(reduced: boolean): { [string]: any }
						local value, number = Compose.cell("2"), Compose.cell(2)
						local w = session(function(UI: FacetControls, Host: RobloxHost)
							return Host.Frame({
								UI.Button "Pop" { label = "Pop", pop = true, onActivate = function() end } :: unknown,
								UI.Button "Busy" { label = "Save", busy = true },
								UI.TextInput "Field" {
									value = value,
									numericValue = number,
									presentation = "number" :: "number",
									min = 1,
									max = 10,
								},
							})
						end, function(gui)
							gui.ReducedMotionEnabled = reduced
						end)
						local button = w.find("Pop")
						button.Activated.fire()
						local field = w.find("Field")
						field:CaptureFocus()
						field.Text = "1.2.3"
						field:ReleaseFocus(true)
						local dot = w.find("Busy"):FindFirstChild("Dot1", true)
						local before = dot.BackgroundTransparency
						w.engine.heartbeat.fire(0.1)
						return {
							pop = button:FindFirstChild("Pop").Scale,
							pulse = field:FindFirstChild("ValidationPulse").Scale,
							dotBefore = before,
							dotAfter = dot.BackgroundTransparency,
							invalid = field:GetAttribute("invalid"),
							w = w,
						}
					end
					local full = run(false)
					Verify.expect(full.invalid):toBe(true)
					Verify.expect(full.pop):toBeGreaterThan(1)
					Verify.expect(full.pulse):toBeLessThan(1)
					Verify.expect(full.dotBefore > 0):toBe(true)
					Verify.expect(full.dotAfter ~= full.dotBefore):toBe(true)
					full.w.gui.ReducedMotionEnabled = true
					Verify.expect(full.w.find("Pop"):FindFirstChild("Pop").Scale):toBe(1)
					Verify.expect(full.w.find("Field"):FindFirstChild("ValidationPulse").Scale):toBe(1)
					Verify.expect(full.w.find("Busy"):FindFirstChild("Dot1", true).BackgroundTransparency):toBe(0)
					full.w.stop()
					local reduced = run(true)
					Verify.expect(reduced.invalid):toBe(true)
					Verify.expect(reduced.pop):toBe(1)
					Verify.expect(reduced.pulse):toBe(1)
					Verify.expect(reduced.dotBefore):toBe(0)
					Verify.expect(reduced.dotAfter):toBe(0)
					reduced.w.gui.ReducedMotionEnabled = false
					reduced.w.find("Pop").Activated.fire()
					reduced.w.engine.heartbeat.fire(0.1)
					Verify.expect(reduced.w.find("Pop"):FindFirstChild("Pop").Scale):toBeGreaterThan(1)
					reduced.w.stop()
				end,
			})

			verifyHarness:case("keeps the busy dots inside the button plate in every shipped package", {
				id = "native_parity_media::controls::keeps the busy dots inside the button plate in every shipped package",
				run = function()
					local packages = { themes.neutralPackage() }
					for _, module in SHIPPED do
						local package, report = module.build(themes)
						Verify.expect(report.ok):toBe(true)
						table.insert(packages, package)
					end
					Verify.expect(#packages):toBe(9)
					for _, package in packages do
						local engine, runtime = make()
						local busy = Compose.cell(true)
						local themed: any = Facet.controls(runtime, { types = engine.types, theme = package } :: any)
						local sheet, button
						local stop = mount(engine, runtime, function()
							sheet = themes.createStyleSheet(runtime, package, { types = engine.types })
							button = themed.Button({ label = "Save", busy = busy })
							return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
								sheet :: unknown,
								button,
							})
						end)
						local busyRule, plainRule =
							style(sheet, ".facet-busy::UIPadding"), style(sheet, ".facet-button::UIPadding")
						local reserved = busyRule:GetProperties().PaddingRight.Offset
						local plain = plainRule:GetProperties().PaddingRight.Offset
						Verify.expect(busyRule.Priority):toBeGreaterThan(plainRule.Priority)
						Verify.expect(reserved):toBeGreaterThan(plain)
						Verify.expect((button:HasTag("facet-busy"))):toBe(true)
						Verify.expect(button.Text):toBe("Save")
						local frame = button:FindFirstChild("Busy")
						Verify.expect(frame.AnchorPoint.X):toBe(0)
						Verify.expect(frame.Position.X.Scale):toBe(1)
						local left = frame.Position.X.Offset
						local right = left + frame.Size.X.Offset
						for index = 1, 3 do
							local dot = frame:FindFirstChild("Dot" .. index)
							Verify.expect(dot.Position.X.Offset):toBeGreaterThanOrEqual(0)
							Verify.expect(dot.Position.X.Offset + dot.Size.X.Offset)
								:toBeLessThanOrEqual(frame.Size.X.Offset)
						end
						Verify.expect(left):toBeGreaterThanOrEqual(0)
						Verify.expect(right):toBeLessThanOrEqual(reserved)
						busy:set(false)
						Verify.expect((button:FindFirstChild("Busy"))):toBeNil()
						Verify.expect((button:HasTag("facet-busy"))):toBe(false)
						Verify.expect((frame.isDestroyed())):toBe(true)
						stop()
						runtime:dispose()
					end
				end,
			})

			verifyHarness:case("renders caller numeric children inside the button beside its label", {
				id = "native_parity_media::controls::renders caller numeric children inside the button beside its label",
				run = function()
					local activations = 0
					local art: any, badge: any
					local w = session(function(UI: FacetControls, Host: RobloxHost)
						art = Host.ImageLabel "Art" { Image = "rbxassetid://7" }
						badge = Host.TextLabel "Count" { Text = "3" }
						return UI.Button "Buy" {
							label = "Buy",
							onActivate = function()
								activations += 1
							end,
							art :: unknown,
							badge,
						}
					end)
					local button = w.find("Buy")
					Verify.expect(button.ClassName):toBe("TextButton")
					Verify.expect(button.Text):toBe("Buy")
					Verify.expect(art.Parent):toBe(button)
					Verify.expect(badge.Parent):toBe(button)
					Verify.expect(art.Image):toBe("rbxassetid://7")
					Verify.expect(badge.Text):toBe("3")
					button.Activated.fire()
					Verify.expect(activations):toBe(1)
					w.stop()
					Verify.expect((art.isDestroyed())):toBe(true)
					Verify.expect((badge.isDestroyed())):toBe(true)
				end,
			})

			verifyHarness:case(
				"gives a chip the rect button shape by default and orders its leading and trailing children",
				{
					id = "native_parity_media::controls::gives a chip the rect button shape by default and orders its leading and trailing children",
					run = function()
						local package = themes.neutralPackage()
						local selected, rain, toggles = Compose.cell(false), Compose.cell(false), 0
						local lead, count, sheet
						local engine, runtime = make()
						local themed: any = Facet.controls(runtime, { types = engine.types, theme = package } :: any)
						local stop, root = mount(engine, runtime, function()
							local Host = (runtime.constructors :: unknown) :: RobloxHost
							sheet = themes.createStyleSheet(runtime, package, { types = engine.types })
							lead = Host.ImageLabel "Lead" { Image = "rbxassetid://9" }
							count = Host.TextLabel "Count" { Text = "3" }
							return Host.Frame({
								sheet :: unknown,
								themed.Chip "Plain" { label = "Dry", selected = selected },
								themed.Chip "Rain" {
									label = "Rain",
									selected = rain,
									leading = lead,
									trailing = count,
									onToggle = function(value)
										toggles += 1
										rain:set(value)
									end,
								},
							})
						end)
						local plain, chip = root:FindFirstChild("Plain", true), root:FindFirstChild("Rain", true)
						for _, node in { plain, chip } do
							Verify.expect(node.ClassName):toBe("TextButton")
							Verify.expect((node:HasTag("facet-chip"))):toBe(true)
							Verify.expect((node:HasTag("facet-button"))):toBe(true)
							Verify.expect((node:HasTag("facet-shape-circle"))):toBe(false)
							Verify.expect((node:FindFirstChildWhichIsA("UICorner"))):toBeNil()
							Verify.expect((node:FindFirstChildWhichIsA("UIAspectRatioConstraint"))):toBeNil()
						end
						Verify.expect(style(sheet, ".facet-button::UICorner"):GetProperties().CornerRadius)
							:toBe(engine.types.UDim.new(0, package.metrics.radii.control))
						Verify.expect(plain.Text):toBe("Dry")
						Verify.expect(chip.Text):toBe("")
						local row = lead.Parent :: Instance
						Verify.expect(row.Parent):toBe(chip)
						Verify.expect(count.Parent):toBe(row)
						local label
						for _, child in row:GetChildren() do
							if child:IsA("TextLabel") and child ~= count then
								label = child
							end
						end
						Verify.expect(label.Text):toBe("Rain")
						Verify.expect(lead.LayoutOrder):toBeLessThan(label.LayoutOrder)
						Verify.expect(label.LayoutOrder):toBeLessThan(count.LayoutOrder)
						Verify.expect((row:FindFirstChildWhichIsA("UIListLayout") :: UIListLayout).FillDirection)
							:toBe(engine.types.Enum.FillDirection.Horizontal)
						chip.Activated.fire()
						Verify.expect(toggles):toBe(1)
						Verify.expect((rain:peek())):toBe(true)
						Verify.expect((selected:peek())):toBe(false)
						plain.Activated.fire()
						Verify.expect((selected:peek())):toBe(true)
						Verify.expect(toggles):toBe(1)
						stop()
						Verify.expect((((lead :: unknown) :: Destroyable).isDestroyed())):toBe(true)
						Verify.expect((((count :: unknown) :: Destroyable).isDestroyed())):toBe(true)
						runtime:dispose()
					end,
				}
			)

			verifyHarness:case("fires button pointer down, up and cancel once each and none while disabled", {
				id = "native_parity_media::controls::fires button pointer down, up and cancel once each and none while disabled",
				run = function()
					local calls = { down = 0, up = 0, cancel = 0, lone = 0, blocked = 0 }
					local w = session(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.Button "Tracked" {
								label = "x",
								onPointerDown = function()
									calls.down += 1
								end,
								onPointerUp = function()
									calls.up += 1
								end,
								onPointerCancel = function()
									calls.cancel += 1
								end,
							} :: unknown,
							UI.Button "Lone" {
								label = "x",
								onPointerCancel = function()
									calls.lone += 1
								end,
							},
							UI.Button "Blocked" {
								label = "x",
								enabled = false,
								onPointerDown = function()
									calls.blocked += 1
								end,
								onPointerUp = function()
									calls.blocked += 1
								end,
								onPointerCancel = function()
									calls.blocked += 1
								end,
							},
						})
					end)
					local tracked, lone, blocked = w.find("Tracked"), w.find("Lone"), w.find("Blocked")
					tracked.MouseLeave.fire()
					Verify.expect(calls.cancel):toBe(0)
					press(w.engine, tracked)
					Verify.expect(calls.down):toBe(1)
					Verify.expect(calls.up):toBe(0)
					release(w.engine, tracked)
					Verify.expect(calls.up):toBe(1)
					Verify.expect(calls.cancel):toBe(0)
					press(w.engine, tracked)
					tracked.MouseLeave.fire()
					Verify.expect(calls.down):toBe(2)
					Verify.expect(calls.cancel):toBe(1)
					release(w.engine, tracked)
					Verify.expect(calls.up):toBe(1)
					tracked.MouseLeave.fire()
					Verify.expect(calls.cancel):toBe(1)
					lone.MouseLeave.fire()
					Verify.expect(calls.lone):toBe(0)
					press(w.engine, lone)
					lone.MouseLeave.fire()
					Verify.expect(calls.lone):toBe(1)
					lone.MouseLeave.fire()
					Verify.expect(calls.lone):toBe(1)
					press(w.engine, blocked)
					release(w.engine, blocked)
					press(w.engine, blocked)
					blocked.MouseLeave.fire()
					Verify.expect(calls.blocked):toBe(0)
					w.stop()
				end,
			})

			verifyHarness:case("shows button help in an unselectable panel that wraps long text at 264 pixels", {
				id = "native_parity_media::controls::shows button help in an unselectable panel that wraps long text at 264 pixels",
				run = function()
					local long = string.rep("Posts this avatar to the shared gallery. ", 8)
					Verify.expect(#long):toBeGreaterThan(300)
					local w = session(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame "Screen" {
							UI.Button "Plus" { label = "+", help = long },
						}
					end)
					local Enum = w.engine.types.Enum
					local plus = w.find("Plus")
					w.input.PreferredInput = Enum.PreferredInput.Gamepad
					w.gui.SelectedObject = plus
					w.engine.heartbeat.fire(0.5)
					local helpText = w.find("HelpText")
					Verify.expect(helpText.Text):toBe(long)
					Verify.expect(helpText.TextWrapped):toBe(true)
					Verify.expect(helpText.AutomaticSize):toBe(Enum.AutomaticSize.XY)
					Verify.expect(helpText:FindFirstChildWhichIsA("UISizeConstraint").MaxSize.X):toBe(264)
					local panel = w.find("Help")
					Verify.expect(panel.Selectable):toBe(false)
					for _, node in panel:GetDescendants() do
						if node:IsA("GuiObject") then
							Verify.expect(node.Selectable):toBe(false)
						end
					end
					Verify.expect((panel:IsDescendantOf(plus))):toBe(false)
					Verify.expect(w.gui.SelectedObject):toBe(plus)
					w.gui.SelectedObject = panel
					Verify.expect(w.gui.SelectedObject):toBe(plus)
					w.gui.SelectedObject = nil
					Verify.expect((w.find("HelpText"))):toBeNil()
					w.stop()
				end,
			})

			verifyHarness:case("rejects an invalid UTF-8 edit and keeps the model, the text and onChange untouched", {
				id = "native_parity_media::controls::rejects an invalid UTF-8 edit and keeps the model, the text and onChange untouched",
				run = function()
					local value, bounded, requests = Compose.cell("ab"), Compose.cell("ab"), {}
					local w = session(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.TextInput "Free" { value = value } :: unknown,
							UI.TextInput "Bounded" {
								value = bounded,
								maxLength = 5,
								onChange = function(text)
									table.insert(requests, text)
									bounded:set(text)
								end,
							},
						})
					end)
					local free, limited = w.find("Free"), w.find("Bounded")
					free:CaptureFocus()
					free.Text = "ab\xff"
					Verify.expect((value:peek())):toBe("ab")
					Verify.expect(free.Text):toBe("ab")
					free.Text = "abc"
					Verify.expect((value:peek())):toBe("abc")
					Verify.expect(free.Text):toBe("abc")
					free.Text = "\xc3abc"
					Verify.expect((value:peek())):toBe("abc")
					Verify.expect(free.Text):toBe("abc")
					free:ReleaseFocus(true)
					Verify.expect((value:peek())):toBe("abc")
					limited:CaptureFocus()
					limited.Text = "abc\xff"
					Verify.expect(#requests):toBe(0)
					Verify.expect((bounded:peek())):toBe("ab")
					Verify.expect(limited.Text):toBe("ab")
					limited.Text = "abcdefg"
					Verify.expect(requests):toEqual({ "abcde" })
					Verify.expect((bounded:peek())):toBe("abcde")
					Verify.expect(limited.Text):toBe("abcde")
					limited.Text = "abcd\xff"
					Verify.expect(requests):toEqual({ "abcde" })
					Verify.expect(limited.Text):toBe("abcde")
					limited:ReleaseFocus(true)
					w.stop()
				end,
			})

			verifyHarness:case("shows the clear button at all times when clearButton is true and clears the value", {
				id = "native_parity_media::controls::shows the clear button at all times when clearButton is true and clears the value",
				run = function()
					local value, plain = Compose.cell("a"), Compose.cell("a")
					local w = session(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.TextInput "Clearable" { value = value, clearButton = true } :: unknown,
							UI.TextInput "Plain" { value = plain },
							UI.TextInput "Off" { value = plain, clearButton = false },
						})
					end)
					local field = w.find("Clearable")
					local clear = field:FindFirstChild("Clear")
					Verify.expect(clear.Visible):toBe(true)
					field:CaptureFocus()
					Verify.expect(clear.Visible):toBe(true)
					field:ReleaseFocus(false)
					Verify.expect(clear.Visible):toBe(true)
					clear.Activated.fire()
					Verify.expect((value:peek())):toBe("")
					Verify.expect(field.Text):toBe("")
					Verify.expect(clear.Visible):toBe(false)
					value:set("b")
					Verify.expect(clear.Visible):toBe(true)
					Verify.expect((w.find("Plain"):FindFirstChild("Clear"))):toBeNil()
					Verify.expect((w.find("Off"):FindFirstChild("Clear"))):toBeNil()
					w.stop()
				end,
			})

			verifyHarness:case("does not commit after parse, format or validate disables or unmounts the field", {
				id = "native_parity_media::controls::does not commit after parse, format or validate disables or unmounts the field",
				run = function()
					local function attempt(stage: string, disable: boolean): { [string]: any }
						local value, number = Compose.cell("2"), Compose.cell(2)
						local enabled, shown = Compose.cell(true), Compose.cell(true)
						local commits, armed = 0, false
						local function trip()
							if armed and disable then
								if stage == "unmount" then
									shown:set(false)
								else
									enabled:set(false)
								end
							end
						end
						local w = session(function(UI: FacetControls, Host: RobloxHost)
							return Host.Frame({
								Compose.show(shown, function()
									return UI.TextInput "Amount" {
										value = value,
										numericValue = number,
										presentation = "number" :: "number",
										enabled = enabled,
										parse = function(text)
											if stage == "parse" or stage == "unmount" then
												trip()
											end
											return tonumber(text)
										end,
										format = function(amount)
											if stage == "format" then
												trip()
											end
											return string.format("%.2f", amount)
										end,
										validate = function(text)
											if stage == "validate" then
												trip()
											end
											return text
										end,
										onCommit = function()
											commits += 1
										end,
									}
								end),
							})
						end)
						local field = w.find("Amount")
						field:CaptureFocus()
						field.Text = "5"
						armed = true
						field:ReleaseFocus(true)
						local result = {
							commits = commits,
							number = number:peek(),
							value = value:peek(),
							removed = field.isDestroyed(),
						}
						w.stop()
						return result
					end
					for _, stage in { "parse", "format", "validate", "unmount" } do
						local kept = attempt(stage, false)
						Verify.expect(kept.commits):toBe(1)
						Verify.expect(kept.number):toBe(5)
						Verify.expect(kept.value):toBe("5.00")
						Verify.expect(kept.removed):toBe(false)
						local stopped = attempt(stage, true)
						Verify.expect(stopped.commits):toBe(0)
						Verify.expect(stopped.number):toBe(2)
						Verify.expect(stopped.value):toBe("5")
						Verify.expect(stopped.removed):toBe(stage == "unmount")
					end
					for _, disable in { false, true } do
						local text, enabled, commits, armed = Compose.cell("a"), Compose.cell(true), 0, false
						local w = session(function(UI: FacetControls)
							return UI.TextInput "Plain" {
								value = text,
								enabled = enabled,
								validate = function(proposed)
									if armed and disable then
										enabled:set(false)
									end
									return string.upper(proposed)
								end,
								onCommit = function()
									commits += 1
								end,
							}
						end)
						local field = w.find("Plain")
						field:CaptureFocus()
						field.Text = "b"
						Verify.expect((text:peek())):toBe("B")
						armed = true
						field:ReleaseFocus(true)
						Verify.expect(commits):toBe(if disable then 0 else 1)
						w.stop()
					end
				end,
			})

			verifyHarness:case("takes a disabled or busy button out of native selection and restores it", {
				id = "native_parity_media::controls::takes a disabled or busy button out of native selection and restores it",
				run = function()
					local enabled, busy = Compose.cell(false), Compose.cell(false)
					local w = session(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.Button "Gated" { label = "Go", enabled = enabled } :: unknown,
							UI.Button "Working" { label = "Save", busy = busy },
						})
					end)
					local gated, working = w.find("Gated"), w.find("Working")
					Verify.expect(gated.Selectable):toBe(false)
					Verify.expect(gated.Interactable):toBe(false)
					w.gui.SelectedObject = gated
					Verify.expect(w.gui.SelectedObject):toBeNil()
					enabled:set(true)
					Verify.expect(gated.Selectable):toBe(true)
					Verify.expect(gated.Interactable):toBe(true)
					w.gui.SelectedObject = gated
					Verify.expect(w.gui.SelectedObject):toBe(gated)
					Verify.expect(working.Selectable):toBe(true)
					Verify.expect(working.Interactable):toBe(true)
					busy:set(true)
					Verify.expect(working.Selectable):toBe(false)
					Verify.expect(working.Interactable):toBe(false)
					w.gui.SelectedObject = working
					Verify.expect(w.gui.SelectedObject):toBe(gated)
					busy:set(false)
					Verify.expect(working.Selectable):toBe(true)
					Verify.expect(working.Interactable):toBe(true)
					enabled:set(false)
					Verify.expect(gated.Selectable):toBe(false)
					Verify.expect(gated.Interactable):toBe(false)
					w.stop()
				end,
			})

			verifyHarness:case(
				"restores focus through nested sheet and alert presentations in last-in first-out order",
				{
					id = "native_parity_media::controls::restores focus through nested sheet and alert presentations in last-in first-out order",
					run = function()
						local sheet, alert = Compose.cell(false), Compose.cell(false)
						local w = session(function(UI: FacetControls, Host: RobloxHost)
							return Host.Frame({
								UI.Button "Base" { label = "Base" } :: unknown,
								UI.Sheet({
									isPresented = sheet,
									detent = Compose.cell("medium"),
									title = "Outer",
									content = function(): Instance
										return UI.Button "Inner" { label = "Inner" }
									end,
								}),
								UI.Alert({
									isPresented = alert,
									title = "Confirm",
									actions = {
										{ id = "Accept", label = "Accept" } :: FixtureNavigationTypes.AlertAction<any>,
									},
								}),
							})
						end)
						local base = w.find("Base")
						w.gui.SelectedObject = base
						sheet:set(true)
						local panel = w.find("SheetPanel")
						local inner = w.find("Inner")
						Verify.expect(w.gui.SelectedObject ~= base):toBe(true)
						Verify.expect((w.gui.SelectedObject:IsDescendantOf(panel))):toBe(true)
						w.gui.SelectedObject = inner
						Verify.expect(w.gui.SelectedObject):toBe(inner)
						alert:set(true)
						local alertPanel = w.find("AlertPanel")
						Verify.expect((w.gui.SelectedObject:IsDescendantOf(alertPanel))):toBe(true)
						alert:set(false)
						Verify.expect((w.find("AlertPanel"))):toBeNil()
						Verify.expect(w.gui.SelectedObject):toBe(inner)
						sheet:set(false)
						Verify.expect((w.find("SheetPanel"))):toBeNil()
						Verify.expect(w.gui.SelectedObject):toBe(base)
						w.stop()
					end,
				}
			)

			local function facetErrors(screen: any): number
				local count = 0
				for _, node in screen:GetDescendants() do
					if node:GetAttribute("FacetError") ~= nil then
						count += 1
					end
				end
				return count
			end

			verifyHarness:case(
				"follows a readable alert source that moves in flight and keeps the last origin when it goes nil",
				{
					id = "native_parity_media::controls::follows a readable alert source that moves in flight and keeps the last origin when it goes nil",
					run = function()
						local shown = Compose.cell(false)
						local origin: any = nil
						local w = session(function(UI: FacetControls, Host: RobloxHost)
							local a = Host.Frame "CardA" {}
							local b = Host.Frame "CardB" {}
							origin = Compose.cell(a)
							return Host.Frame({
								a :: unknown,
								b,
								UI.Alert({
									isPresented = shown,
									title = "Detail",
									transition = { source = origin, seconds = 0.2 },
								}),
							})
						end)
						local V2 = w.engine.types.Vector2
						local a, b = w.find("CardA"), w.find("CardB")
						a.AbsolutePosition, a.AbsoluteSize = V2.new(20, 30), V2.new(100, 60)
						b.AbsolutePosition, b.AbsoluteSize = V2.new(500, 400), V2.new(50, 40)
						shown:set(true)
						local panel = w.find("AlertPanel")
						panel.AbsoluteSize = V2.new(440, 176)
						local scale = materialize.of(panel)
						Verify.expect(panel.Position.X.Offset):toBe(70)
						Verify.expect(panel.Position.Y.Offset):toBe(60)
						w.find("AlertModal").AbsoluteSize = V2.new(800, 600)
						w.engine.heartbeat.fire(0.1)
						local rest = 100 / 440
						local progress = (scale.Scale - rest) / (1 - rest)
						Verify.expect(progress > 0 and progress < 1):toBe(true)
						local before = panel.Position.X.Offset
						Verify.expect(math.abs(before - (70 * (1 - progress) + 400 * progress)) <= 1):toBe(true)
						a.AbsolutePosition = V2.new(220, 130)
						local moved = panel.Position.X.Offset
						Verify.expect(math.abs(moved - before - 200 * (1 - progress)) <= 1):toBe(true)
						Verify.expect(math.abs(panel.Position.Y.Offset - (160 * (1 - progress) + 300 * progress)) <= 1)
							:toBe(true)
						origin:set(nil)
						Verify.expect(panel.Position.X.Offset):toBe(moved)
						Verify.expect(scale.Scale > rest):toBe(true)
						w.engine.heartbeat.fire(0.05)
						Verify.expect(panel.Position.X.Offset > moved):toBe(true)
						w.engine.heartbeat.fire(0.2)
						Verify.expect(panel.Position.X.Offset):toBe(400)
						Verify.expect(scale.Scale):toBe(1)
						shown:set(false)
						w.engine.heartbeat.fire(0.1)
						local back = (scale.Scale - rest) / (1 - rest)
						Verify.expect(back > 0 and back < 1):toBe(true)
						Verify.expect(math.abs(panel.Position.X.Offset - (270 * (1 - back) + 400 * back)) <= 1)
							:toBe(true)
						w.engine.heartbeat.fire(0.2)
						Verify.expect((w.find("AlertPanel"))):toBeNil()
						origin:set(b)
						shown:set(true)
						local next = w.find("AlertPanel")
						Verify.expect(next ~= panel):toBe(true)
						w.find("AlertModal").AbsoluteSize = V2.new(800, 600)
						Verify.expect(next.Position.X.Offset):toBe(525)
						Verify.expect(next.Position.Y.Offset):toBe(420)
						w.engine.heartbeat.fire(0.3)
						Verify.expect(next.Position.X.Offset):toBe(400)
						b.Parent = nil
						shown:set(false)
						w.engine.heartbeat.fire(0.1)
						Verify.expect(next.Position.X.Offset):toBe(400)
						Verify.expect(next.Position.Y.Offset):toBe(300)
						Verify.expect(fadeKit.of(next) > 0 and fadeKit.of(next) < 1):toBe(true)
						w.engine.heartbeat.fire(0.2)
						Verify.expect((w.find("AlertPanel"))):toBeNil()
						Verify.expect((b.isDestroyed())):toBe(false)
						Verify.expect(a.Parent ~= nil):toBe(true)
						Verify.expect((facetErrors(w.screen))):toBe(0)
						w.stop()
					end,
				}
			)

			verifyHarness:case(
				"dismisses a full-screen alert in place and destroys its snapshot when the source is gone",
				{
					id = "native_parity_media::controls::dismisses a full-screen alert in place and destroys its snapshot when the source is gone",
					run = function()
						local shown = Compose.cell(false)
						local origin: any = nil
						local w = session(function(UI: FacetControls, Host: RobloxHost)
							local card = Host.Frame "Card" { Host.UICorner({}) }
							origin = Compose.cell(card)
							return Host.Frame({
								card :: unknown,
								UI.Alert({
									isPresented = shown,
									title = "Detail",
									surface = "fullScreen" :: "fullScreen",
									transition = { source = origin, seconds = 0.4 },
								}),
							})
						end)
						local V2 = w.engine.types.Vector2
						local card = w.find("Card")
						card.AbsolutePosition, card.AbsoluteSize = V2.new(20, 30), V2.new(120, 80)
						shown:set(true)
						local panel = w.find("AlertPanel")
						local modal = w.find("AlertModal")
						modal.AbsolutePosition, modal.AbsoluteSize = V2.new(10, 10), V2.new(800, 600)
						local snapshot = w.find("SourceSnapshot")
						Verify.expect(snapshot ~= nil and snapshot ~= card):toBe(true)
						Verify.expect(panel.Position.X.Offset):toBe(10)
						Verify.expect(panel.Position.Y.Offset):toBe(20)
						w.engine.heartbeat.fire(0.1)
						local progress = (panel.Size.X.Offset - 120) / 680
						Verify.expect(progress > 0 and progress < 1):toBe(true)
						Verify.expect(math.abs(panel.Position.X.Offset - 10 * (1 - progress)) <= 1):toBe(true)
						card.AbsolutePosition = V2.new(210, 330)
						Verify.expect(math.abs(panel.Position.X.Offset - 200 * (1 - progress)) <= 1):toBe(true)
						Verify.expect(math.abs(panel.Position.Y.Offset - 320 * (1 - progress)) <= 1):toBe(true)
						local width = panel.Size.X.Offset
						origin:set(nil)
						Verify.expect(panel.Size.X.Offset):toBe(width)
						w.engine.heartbeat.fire(0.05)
						Verify.expect(panel.Size.X.Offset > width):toBe(true)
						w.engine.heartbeat.fire(0.4)
						Verify.expect(panel.Size.X.Offset):toBe(800)
						Verify.expect(panel.Position.X.Offset):toBe(0)
						card:Destroy()
						shown:set(false)
						w.engine.heartbeat.fire(0.1)
						Verify.expect((w.find("AlertPanel"))):toBe(panel)
						Verify.expect(panel.Position.X.Offset):toBe(0)
						Verify.expect(panel.Position.Y.Offset):toBe(0)
						Verify.expect(panel.Size.X.Offset):toBe(800)
						Verify.expect(panel.Size.Y.Offset):toBe(600)
						Verify.expect(fadeKit.of(panel) > 0 and fadeKit.of(panel) < 1):toBe(true)
						Verify.expect(w.find("SourcePreview").Visible):toBe(false)
						Verify.expect((snapshot.isDestroyed())):toBe(false)
						w.engine.heartbeat.fire(0.4)
						Verify.expect((w.find("AlertPanel"))):toBeNil()
						Verify.expect((snapshot.isDestroyed())):toBe(true)
						Verify.expect((facetErrors(w.screen))):toBe(0)
						w.stop()
					end,
				}
			)
		end)

		verifyHarness:suite("icon coverage", function()
			local fs = require("@lune/fs")

			local function requested(): { [string]: string }
				local found: { [string]: string } = {}
				for _, file in fs.readDir("src/ui") do
					if string.sub(file, -5) == ".luau" then
						local source = fs.readFile("src/ui/" .. file)
						for _, pattern in
							{
								'icon%(%s*"([%w%.:_]+)"',
								'icon%s*=%s*"([%w%.:_]+)"',
								'icon or "([%w%.:_]+)"',
								'stepButton%(%s*"%a+",%s*"([%w%.:_]+)"',
							}
						do
							for name in string.gmatch(source, pattern) do
								found[name] = file
							end
						end
					end
				end
				return found
			end

			local function resolvesToArt(package: any, name: string): boolean
				local content = themes.resolveIcon(package, name)
				return type(content) == "string" and string.match(content, "^rbxasset") ~= nil
			end

			verifyHarness:case("declares standard art for every icon name a control requests", {
				id = "native_parity_media::icon coverage::declares standard art for every icon name a control requests",
				run = function()
					local names = requested()
					local count = 0
					for name, file in names do
						count += 1
						Verify.expect(`{file}: {name}: {icons.ART[name] ~= nil}`):toBe(`{file}: {name}: true`)
					end
					for _, name in
						{
							"checkmark",
							"chevron.leading",
							"chevron.trailing",
							"chevron.down",
							"status.warning",
							"increment",
							"decrement",
						}
					do
						Verify.expect(names[name] ~= nil):toBe(true)
					end
					Verify.expect(count >= 7):toBe(true)
					local broken = themes.neutralPackage()
					broken.icons = { close = "missing-asset" } :: { [string]: ThemeTypes.IconEntry }
					Verify.expect((resolvesToArt(broken, "close"))):toBe(false)
					Verify.expect((resolvesToArt(themes.neutralPackage(), "close"))):toBe(true)
				end,
			})

			verifyHarness:case("resolves every framework icon to art in every shipped theme package", {
				id = "native_parity_media::icon coverage::resolves every framework icon to art in every shipped theme package",
				run = function()
					local packages = { themes.neutralPackage() }
					for _, definition in SHIPPED do
						table.insert(packages, (assert(themes.define((definition.build(themes))))))
					end
					Verify.expect(#packages):toBe(9)
					local names = 0
					for _ in icons.ART do
						names += 1
					end
					Verify.expect(names >= 30):toBe(true)
					for _, package in packages do
						for name in icons.ART do
							Verify.expect(`{package.identity.id}: {name}: {resolvesToArt(package, name)}`)
								:toBe(`{package.identity.id}: {name}: true`)
						end
						for name in requested() do
							Verify.expect((resolvesToArt(package, name))):toBe(true)
						end
					end
				end,
			})

			verifyHarness:case("shows the package increment and decrement art on stepper buttons instead of glyphs", {
				id = "native_parity_media::icon coverage::shows the package increment and decrement art on stepper buttons instead of glyphs",
				run = function()
					local pixel = assert(themes.define((require("../examples/themes/pixel_quest").build(themes))))
					for _, case in
						{ { package = themes.neutralPackage(), own = false }, { package = pixel, own = true } }
					do
						local engine, runtime, UI = make({ theme = case.package })
						local stop, root = mount(engine, runtime, function()
							return UI.Stepper({ value = Compose.cell(2), min = 0, max = 5 })
						end)
						for name, icon in { Increase = "increment", Decrease = "decrement" } :: { [string]: string } do
							local button = assert(root:FindFirstChild(name, true))
							local image = assert(button:FindFirstChildWhichIsA("ImageLabel", true))
							Verify.expect(image.Image):toBe(themes.resolveIcon(case.package, icon))
							Verify.expect(image.Image == icons.ART[icon].contentId):toBe(not case.own)
							for _, node in button:GetDescendants() do
								if node:IsA("TextLabel") then
									Verify.expect(node.Text):toBe("")
								end
							end
							Verify.expect(button.Text):toBe("")
						end
						stop()
						runtime:dispose()
					end
				end,
			})
		end)
	end)
end
