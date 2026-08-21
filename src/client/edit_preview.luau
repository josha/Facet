--!strict
-- Edit-mode preview harness (director Part-2 ws2): runs the REAL pipeline —
-- blueprint → mount → solver → ScreenTarget — into a ScreenGui during Studio
-- Edit, sized by device profiles (src/preview/device_profiles). No presenter
-- or input contexts: this is a visual preview; blueprints holding signals
-- still live-update through the heartbeat refresh, and switching profiles
-- re-solves in place (rect writes only — the same contract the tests pin).
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
	-- a Blueprint, or a factory (Facet, core) -> Blueprint so entries can
	-- create signals/memos on the preview's core
	blueprint: any,
	profile: string?,
	style: any?,
}

function edit_preview.start(Facet: any, opts: StartOpts)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	local profile = device_profiles.apply(env, opts.profile or "desktop")

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

	-- fallible section (user blueprint factories throw): any failure tears
	-- down everything already parented and re-raises — start() never orphans
	-- preview furniture (verifier F1)
	--[[ THE PREVIEW OPTS OUT OF SHEET PAINT, EXPLICITLY, and after the 2026-08-21
		default flip (`native_style.DEFAULT_ENABLED = true`, ADR-0040 row B-15) that
		`false` is load-bearing rather than a restatement. This harness runs in the
		STUDIO EDIT DataModel, where `native_style.ensure` would seed a persistent
		`FacetStyle` StyleSheet that the next place save commits — which is exactly
		the furniture this module's header promises never to leave behind (verifier
		F5), and `dispose()` cannot take it back because the sheet is seed-once by
		design. It costs nothing to look at: the adoption evidence measured the two
		paint paths byte-equal on every mapped property, so a preview painted the
		explicit-write way shows what the game shows. `billboard_target` opts out
		beside it, for its own reason. ]]
	local adapter = screen_target.new({ parent = opts.parent, style = opts.style, nativeStyle = false })
	local root: any = nil
	local controller: any = nil
	local ok, startErr = pcall(function()
		local blueprint = if type(opts.blueprint) == "function" then opts.blueprint(Facet, core) else opts.blueprint
		root = Facet.mount(core, blueprint)
		controller = Facet.renderer.attach(core, root, env, adapter, {})
		controller.initialRender()
	end)
	if not ok then
		if controller ~= nil then
			pcall(controller.dispose)
		end
		if root ~= nil then
			pcall(root.dispose)
		end
		deco:Destroy()
		error(`Facet edit_preview.start failed (all preview instances removed): {tostring(startErr)}`, 0)
	end

	local heartbeat = RunService.Heartbeat:Connect(function()
		controller.refresh()
	end)

	local handle = {}
	handle.controller = controller
	handle.profile = profile.name

	-- live re-render: the renderer's environment observers re-solve on the
	-- geometry change; no remount, rect writes only
	function handle.setProfile(name: string)
		local active = device_profiles.apply(env, name)
		handle.profile = active.name
		applyDeco(active)
		controller.refresh()
	end

	function handle.refresh()
		controller.refresh()
	end

	function handle.dispose()
		heartbeat:Disconnect()
		controller.dispose()
		root.dispose()
		deco:Destroy()
	end

	return handle
end

return edit_preview
