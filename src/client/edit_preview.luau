--!strict
-- Edit-mode preview harness (director Part-2 ws2): runs a REAL application —
-- component → mount → solver → ScreenTarget — into a ScreenGui during Studio
-- Edit, sized by device profiles (src/preview/device_profiles). No engine input
-- is bound: this is a visual preview; components holding cells still
-- live-update through the heartbeat frame, and switching profiles re-solves in
-- place (rect writes only — the same contract the tests pin).
--
-- Drivable two ways:
--   * Studio MCP / command bar: require this module in the Edit DataModel and
--     call start() with a parent. PREFER CoreGui — it renders in the editor
--     viewport and is never saved into the place file. StarterGui also works
--     (and screenshots identically) but IS saved: always dispose() before
--     saving the place, or preview furniture gets committed (verifier F5).
--   * The durable plugin (tools/studio/Facet_EditPreview.plugin.lua) wraps
--     this with a toolbar (profile cycle + off) parented under CoreGui.

local RunService = game:GetService("RunService")

local screen_target = require("./screen_target")
local device_profiles = require("../preview/device_profiles")

local edit_preview = {}

export type StartOpts = {
	parent: Instance,
	-- the screen to preview: `component(app) -> node`, run inside the preview
	-- application's mount, so its cells and watches are released with the preview
	component: (app: any) -> any,
	profile: string?,
	style: any?,
}

function edit_preview.start(Facet: any, opts: StartOpts)
	assert(type(opts.component) == "function", "Facet edit_preview.start: opts.component must be a function")
	local profile = device_profiles.get(opts.profile or "desktop")
	assert(profile ~= nil, `Facet edit_preview.start: unknown device profile '{tostring(opts.profile)}'`)

	-- device-bounds decoration: an outline + caption so screenshots read
	-- which profile is active and where its viewport ends
	local deco = Instance.new("ScreenGui")
	deco.Name = "Facet_EditPreviewFrame"
	deco.IgnoreGuiInset = true
	deco.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	deco.DisplayOrder = 1000
	deco.Parent = opts.parent
	local bounds = Instance.new("Frame")
	bounds.Name = "DeviceBounds"
	bounds.BackgroundTransparency = 1
	bounds.BorderSizePixel = 0
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 170, 40)
	stroke.Thickness = 2
	stroke.Parent = bounds
	bounds.Parent = deco
	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.BackgroundColor3 = Color3.fromRGB(255, 170, 40)
	caption.TextColor3 = Color3.new(0, 0, 0)
	caption.TextSize = 14
	caption.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json")
	caption.BorderSizePixel = 0
	caption.Parent = deco

	local function applyDeco(active: any)
		bounds.Position = UDim2.fromOffset(0, 0)
		bounds.Size = UDim2.fromOffset(active.viewport.w, active.viewport.h)
		caption.Text = "  Facet preview — " .. active.title .. "  "
		local textWidth = 8 * #caption.Text -- generous; edit-only furniture
		caption.Size = UDim2.fromOffset(math.min(textWidth, active.viewport.w), 22)
		caption.Position = UDim2.fromOffset(0, active.viewport.h + 4)
	end
	applyDeco(profile)

	-- fallible section (user components throw): any failure tears down
	-- everything already parented and re-raises — start() never orphans preview
	-- furniture (verifier F1)
	--[[ THE PREVIEW OPTS OUT OF SHEET PAINT, EXPLICITLY, and after the 2026-08-21
		default flip (`native_style.DEFAULT_ENABLED = true`) that
		`false` is load-bearing rather than a restatement. This harness runs in the
		STUDIO EDIT DataModel, where `native_style.ensure` would seed a persistent
		`FacetStyle` StyleSheet that the next place save commits — which is exactly
		the furniture this module's header promises never to leave behind (verifier
		F5), and `dispose()` cannot take it back because the sheet is seed-once by
		design. It costs nothing to look at: the adoption evidence measured the two
		paint paths byte-equal on every mapped property, so a preview painted the
		explicit-write way shows what the game shows. `billboard_target` opts out
		beside it, for its own reason. ]]
	--[[ THE PREVIEW HAS A DISTANCE, AND IT IS THE PROFILE'S (fix round,
		2026-08-21). `device_profiles` ships a `console` profile whose facts carry
		`displaySize = "Large"`, and the host binds the environment — where the
		profile is applied — BEFORE it asks for the adapter, so the class being
		previewed is the class this target must paint. Without it the preview would show a television's
		spacing around a phone's corners, which is precisely the disagreement a
		preview exists to make visible.

		A LIVE `setProfile` ACROSS THE NEAR/TEN-FOOT BOUNDARY still moves the
		measure and not the paint: a target takes its class at construction, the way
		it takes its palette. Restart the preview to change distance; the growth
		seam that would make it live is not built. ]]
	local env: any = nil
	local app: any = nil
	local controller: any = nil
	local ok, startErr = pcall(function()
		app = Facet.new({
			bindEnv = function(bound: any)
				env = bound
				device_profiles.apply(env, profile.name)
				return function() end
			end,
			newAdapter = function()
				return screen_target.new({
					parent = opts.parent,
					style = opts.style,
					displaySize = env:get("displaySize"):peek(),
					nativeStyle = false,
				})
			end,
			-- a preview takes no engine input: an action system with no devices bound
			newInputSystem = function(core: any)
				return Facet.newActionSystem(core)
			end,
			connectFrame = function(frame: (dt: number) -> ())
				local connection = RunService.Heartbeat:Connect(frame)
				return function()
					connection:Disconnect()
				end
			end,
		})
		local _, _, surface = app.mount(function()
			return opts.component(app)
		end)
		controller = surface.controller
	end)
	if not ok then
		-- a host that throws unwinds itself; an application that mounted and then
		-- failed is released here
		if app ~= nil then
			pcall(app.dispose)
		end
		deco:Destroy()
		error(`Facet edit_preview.start failed (all preview instances removed): {tostring(startErr)}`, 0)
	end

	local handle = {}
	handle.app = app
	handle.controller = controller
	handle.profile = profile.name

	-- live re-render: the renderer's environment observers re-solve on the
	-- geometry change; no remount, rect writes only
	function handle.setProfile(name: string)
		local active = device_profiles.apply(env, name)
		handle.profile = active.name
		applyDeco(active)
		app.presenter.refresh()
	end

	function handle.refresh()
		app.presenter.refresh()
	end

	function handle.dispose()
		app.dispose()
		deco:Destroy()
	end

	return handle
end

return edit_preview
