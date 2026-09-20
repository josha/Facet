--!strict
-- Facet Gallery client bootstrap (design §17 Phase 1): the complete path —
-- replicated semantic state -> adapters -> blueprint -> mount -> solve ->
-- ScreenTarget, with real IAS input and the presenter. The "server" here is a
-- local loopback of semantic state (the gallery is single-place); games wire
-- the same adapters to their replication layer.
-- Studio verification reads workspace attributes Facet_* (checkpoints).

-- string requires do NOT wait for replication (platform research 2026-07-19)
if not game:IsLoaded() then
	game.Loaded:Wait()
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Facet = require(ReplicatedStorage:WaitForChild("Facet")) :: any
local screen_target = require(ReplicatedStorage.Facet.client.screen_target) :: any
local roblox_env = require(ReplicatedStorage.Facet.client.roblox_env) :: any
local roblox_input = require(ReplicatedStorage.Facet.client.roblox_input) :: any
local gamepad_contention = require(ReplicatedStorage.Facet.client.gamepad_contention) :: any
local responder_effects = require(ReplicatedStorage.Facet.client.responder_effects) :: any

local boot_mode = require(script:WaitForChild("boot_mode")) :: any
local demo_host = require(script:WaitForChild("demo_host")) :: any
local bootDecision = boot_mode.decide({
	showcase = workspace:GetAttribute("Facet_Showcase"),
	scenario = workspace:GetAttribute("Facet_Scenario"),
	example = workspace:GetAttribute("Facet_Example"),
})

local Compose = Facet.Compose
local environment_preview = require(ReplicatedStorage.Facet.client.environment_preview) :: any
-- One application stands the surface up. Its seams hand this bootstrap the
-- pieces it configures itself: the environment binding, the render target and
-- the input system. The application drives the frame: clock, then solve.
local core: any, env: any, adapter: any, system: any
local displayPreview: any = nil
-- Stops the platform feeding the environment, once. A scenario freezes its
-- facts with it; the application calls it again, harmlessly, when it is disposed.
local unbindEnv: () -> ()
-- NS-I2 fallback A/B driver: set workspace attribute Facet_ForceScrollFallback
-- BEFORE running to exercise the clip-only ScrollView fallback in Studio
-- Native-stylesheets A/B driver (ledger NSS-A2/NSS-A10). The PRECEDENCE — forced
-- fallback over an explicit opt-in over the library default — is a decision, not
-- an expression: it lives in `paint_mode.luau` beside `boot_mode.luau`, for the
-- same reason and with the same spec technique, because a client script's argument
-- list has no witness. Facet_NativeTransitions may explicitly disable the
-- native paint transitions; an absent attribute follows the library default.
local paint_mode = require(script:WaitForChild("paint_mode")) :: any
-- KEYBOARD NAVIGATION ON, BECAUSE THIS PLACE FREED THE KEY FOR IT
-- (example-quality-pass, 2026-08-06). The presenter's `keyboardNavigation`
-- defaults FALSE so a game that never asked keeps the input behaviour it had —
-- see PresenterOpts. This bootstrap already disables the CoreGui players list a
-- hundred lines below precisely so Tab can reach a developer InputContext, and
-- then never opted in, so Tab bound nothing and traversal was dead in all seven
-- tutorial examples: six Tab presses moved focus zero times. A UI-only gallery
-- whose whole job is demonstrating the framework's input story has to have it on.
local app = Facet.new({
	keyboardNavigation = true,
	bindEnv = function(bound: any)
		env = bound
		displayPreview = if bootDecision.mode == "showcase" then environment_preview.new(bound) else nil
		local unbindPlatform = roblox_env.bind(if displayPreview ~= nil then displayPreview.source else bound)
		local unbound = false
		unbindEnv = function()
			if unbound then
				return
			end
			unbound = true
			unbindPlatform()
			if displayPreview ~= nil then
				displayPreview.dispose()
			end
		end
		return unbindEnv
	end,
	newAdapter = function()
		adapter = screen_target.new({
			--[[ THE DISTANCE THIS PLACE IS WATCHED FROM (fix round, 2026-08-21, found on
				a live console row at stamp e0d6afd5). At ten-foot the paint family —
				corner radii and hairlines — scales with the metric ladder, and a target
				takes that class at construction; this bootstrap builds its own target
				instead of taking `client.host`, so the fact has to be handed over by hand
				or the showcase MEASURES at three metres and PAINTS at arm's length. The
				verify read it exactly that way: a capsule painting `0, 999` where the
				derivation says 1499. Read after the environment is bound, so it is the
				engine's own `ViewportDisplaySize`. ]]
			displaySize = env:get("displaySize"):peek(),
			forceScrollFallback = workspace:GetAttribute("Facet_ForceScrollFallback") == true,
			nativeStyle = paint_mode.decide({
				native = workspace:GetAttribute("Facet_NativeStyle") == true,
				fallback = workspace:GetAttribute("Facet_ForceStyleFallback") == true,
				transitions = workspace:GetAttribute("Facet_NativeTransitions"),
			}),
		})
		return adapter
	end,
	newInputSystem = function(value: any)
		core = value
		system = roblox_input.newSystem(value)
		return system
	end,
})
local UI = app.controls
local pres = app.presenter

-- First-responder engine seam: while an EXCLUSIVE (sinking) surface
-- is up — a modal, or an engaged-from-passive HUD — hide the mobile touch
-- controls. This gallery is a UI-only place whose default screen presents no
-- modal, so the effect is inert here; the call proves the one-line wiring shape
-- a real game (RascalRally) uses. Client-only module (like gamepad_contention),
-- required directly from src/client — see docs/guide/07-input.md §7.3.
local unbindResponderEffects = responder_effects.bind(core, pres)

-- NATIVE-SCROLL AUTO-BIND (native-substrate NS-A3/NS-A4). A control riding the
-- engine canvas cannot reach the render controller at build time, so the CONSUMER
-- binds the mirror after present(). The seam has TWO shipped spellings —
-- VirtualList publishes `bindNativeScroll` flat, Table publishes it under `api` —
-- and probing only the flat one left every returned Table unbound, which is
-- exactly what happened to 02_playlist_table's body scroll (CTRL-05a). Probe both
-- until the 1.0 return-shape pass unifies them.
local function nativeScrollBinderOf(value: any): ((controller: any) -> any)?
	if type(value) ~= "table" then
		return nil
	end
	if type(value.bindNativeScroll) == "function" then
		return value.bindNativeScroll
	end
	if type(value.api) == "table" and type(value.api.bindNativeScroll) == "function" then
		return value.api.bindNativeScroll
	end
	return nil
end

-- THEME PICKER (director review 2026-07-25: "no idea how to swap themes").
-- A gallery-only overlay — see examples/gallery/client/theme_picker.luau for
-- why it is an example and not library code. Mounted for the DEMO and TUTORIAL
-- paths only: a scenario run owns its own theme controller (the runner installs
-- and swaps packages as acceptance steps), and `themeMetrics` is ONE env fact,
-- so a second controller there would be a capability error rather than a
-- convenience. Set the workspace attribute Facet_ThemePicker = false to hide it.
local theme_picker = require(script:WaitForChild("theme_picker")) :: any
local theme_controller = require(ReplicatedStorage.Facet.client.theme_controller) :: any

-- `collapsible` is passed only by the showcase place: see theme_picker's
-- MountOpts for why it is opt-in rather than the default.
local function mountThemePicker(collapsible: boolean?, composed: boolean?)
	if workspace:GetAttribute(theme_picker.ATTRIBUTE) == false then
		return nil
	end
	-- the reference packages replicate as ModuleScripts under
	-- ReplicatedStorage.FacetThemes (examples/gallery.project.json); each
	-- exposes `build(themes) -> (package, report)` through the PUBLIC surface
	local folder = ReplicatedStorage:FindFirstChild("FacetThemes")
	local packages: { [string]: any } = {}
	if folder ~= nil then
		for _, module in folder:GetChildren() do
			if not module:IsA("ModuleScript") then
				continue
			end
			local ok, built = pcall(function()
				local m = require(module) :: any
				-- `testOnly` fixtures stay out of the list (theme_picker.isPickable):
				-- the acceptance scenarios install those by name, and a picker whose
				-- rows are broken-on-purpose packages misrepresents the framework
				return if theme_picker.isPickable(m) then (m.build(Facet.themes)) else nil
			end)
			if ok and built ~= nil then
				packages[module.Name] = built
			end
		end
	end
	local mounted = theme_picker.mount({
		Facet = Facet,
		app = app,
		env = env,
		adapter = adapter,
		packages = packages,
		themeController = theme_controller,
		collapsible = collapsible,
		-- composed: hand back the chip and the panel instead of presenting an
		-- overlay, so the showcase host can lay both pickers out in one surface
		composed = composed,
		warn = warn,
	})
	if mounted ~= nil then
		workspace:SetAttribute("Facet_ThemePickerReady", true)
	end
	return mounted
end

-- ENGINE TRUTH (ui_todo.md §3, live gamepad 2026-07-20): the legacy control
-- scripts bind gamepad ButtonA to jumpAction UNCONDITIONALLY — even with no
-- character — silently consuming the button (gameProcessed) before the Input
-- Action System sees it. These gallery places are UI-only, so free ButtonA
-- through the shared helper (ONE implementation:
-- src/client/gamepad_contention.luau; full story in docs/guide/07-input.md).
-- Real games keep their controls and either run the IAS player-script stack
-- (RascalRally does) or accept A-contention while a character can jump.
-- UI-only place: real games keep avatar input and rely on IAS arbitration —
-- docs/guide/07-input.md.
task.defer(function()
	gamepad_contention.disableLegacyControls()
end)

-- ...AND FREE THE TAB KEY, for the same reason and with the same scope limit
-- (director playtest 2026-08-03, confirmed on a physical keyboard: with the
-- players list enabled, Tab does nothing at all).
--
-- Tab is the CoreGui players-list shortcut. Roblox documents it as reserved
-- "unless you disable the respective feature", and disabling that feature is the
-- only sanctioned way to let a developer InputContext receive the key — no
-- InputContext priority is documented to outrank CoreGui. These gallery places
-- are UI-only and have no leaderboard worth keeping, so the trade is free HERE.
--
-- IT IS NOT FREE IN A GAME, which is why this lives in the gallery bootstrap and
-- not in Facet: hiding a game's leaderboard to win a key is the same trade the
-- gamepad_contention scope note refuses for avatar controls, and the library
-- never makes it for a consumer. A game decides for itself, and
-- `gamepad_contention.traversalKeyContended()` tells it what the current answer
-- is. Full story in docs/guide/07-input.md §7.4.
task.defer(function()
	pcall(function()
		game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)
end)

-- ENGINE TEXT CALIBRATION (NS-A10, UI-FID-001) IS STILL NOT RUN HERE, and no
-- longer needs to be: the ScreenTarget adapter now measures text per WORD with
-- the engine's own bounds API (src/client/text_premeasure), so boxes match what
-- is drawn without any average-glyph model at all.
--
-- The calibration seam remains for targets that want a cheap per-font tightening,
-- but it cannot be the answer on its own and that is worth remembering: measured
-- live 2026-07-24 on the SAME font at the SAME size, "Brightness" runs 0.391
-- em/glyph and "Volume" 0.469. A single fraction that bounds the wide one wastes
-- space on the narrow one; one that fits the narrow one clips the wide one.
-- Turning it on did exactly that — "Brightness" lost its final s and "Download"
-- was cut off. The problem was never the font, it was VARIANCE, and no average
-- can bound a specific short string.

-- ===== WHICH SURFACE THIS PLACE BOOTS =====================================
--
-- Four surfaces share this one client script, and which of them runs used to be
-- decided by the ORDER of three `if` blocks a hundred lines apart. That order
-- was wrong in the one place a device pass opens: the showcase branch came
-- first, `tools/build_places.sh` bakes `Facet_Showcase = true` into the showcase
-- place, and so the §5 verification selectors below it were unreachable there —
-- setting `Facet_Scenario` produced no `workspace.FacetScenarioAPI`, no error
-- and no warning, just the ordinary showcase boot line (found live 2026-08-20).
--
-- The decision is now taken ONCE, up here, by a pure module a spec can drive
-- (`boot_mode.luau`, `tests/gallery_boot_mode.spec.luau`). Its two rules: a
-- verification selector OUTRANKS the demo shell, and a selector that was set and
-- cannot be honoured WARNS with the reason instead of quietly booting something
-- that would look like a passing run.
for _, refusal in bootDecision.refusals do
	warn(refusal)
end

-- ===== SHOWCASE MODE (the hands-on device place) ==========================
--
-- One place you publish once and open on a phone, a tablet, a desktop and a
-- console, with BOTH the demo and the theme switchable in-game. Every other
-- selector in this file needs a workspace attribute set before Play and a
-- republish to change — a fine developer affordance and a useless one on a
-- device you are holding.
--
-- The showcase place sets `Facet_Showcase = true` in its own Rojo project
-- (tools/build_places.sh), so nobody has to touch an attribute; the branch is
-- inert in every other place — and it yields to a §5 selector when one is set,
-- which is what makes the showcase place drivable without editing its build.
if bootDecision.mode == "showcase" then
	local demo_picker = require(script:WaitForChild("demo_picker")) :: any
	local settings_panel = require(script:WaitForChild("settings_panel")) :: any
	local showcase_chrome = require(script:WaitForChild("showcase_chrome")) :: any

	-- RESERVE THE BAR, DO NOT FLOAT OVER IT.
	--
	-- The first attempt floated both pickers over the demo and nudged them apart
	-- with offsets. That is a losing game: every demo puts content somewhere, so
	-- a fixed overlay always covers SOMETHING — the all-controls fixture's own
	-- title and its stepper both ended up underneath a chip.
	--
	-- Facet already has the right mechanism, and it is the one the CoreGui
	-- topbar itself uses: an inset fact is read on every solve, so reserving the
	-- bar makes the SOLVER lay every demo out below it. Nothing overlaps because
	-- nothing floats.
	--
	-- IT IS THE HOST'S OWN FACT, NOT THE PLATFORM'S (owner ruling 2026-09-13).
	-- This row is APP chrome — the showcase drew it, over its own content — and it
	-- goes into `appChromeInsets`, the four-edge reservation a host declares beside
	-- the rect it publishes through `appChromeRects` below. `coreSafeInsets` means
	-- the device safe area and the platform adapter is its only author again.
	--
	-- WHAT THAT BUYS, and why the fold into `coreSafeInsets` had to end: a MODAL
	-- honours the device safe area alone. Folded into one fact, every alert the
	-- showcase raised centred in the space UNDER this strip — high-shouldered
	-- against a backdrop covering the whole window. Content still yields the band;
	-- the alert now centres on the true screen.
	--
	-- AND THE FOUR-EDGE TRAP GOES WITH IT. The old write had to carry the adapter's
	-- other three edges through by hand (on a notched phone in landscape they are
	-- the notch and the home indicator), because writing a table with three zeroes
	-- in it looks like "reserving the top" and is actually "deleting every other
	-- edge". This fact is the host's alone, so three zeroes are the truth: the
	-- showcase reserves a top strip and nothing else.
	--
	-- THE RESERVATION IS STILL ABSOLUTE, and the subtraction below is what keeps it
	-- so. `barReservation` answers in WINDOW space (it is measured from the chip
	-- row's own solved bottom edge), while this fact is what content must clear
	-- BELOW the platform's row — so the platform's row comes off it, read from the
	-- SAME fact the renderer will add back. Before the adapter has published it
	-- that fact is zero and the whole reservation is spent here, which is exactly
	-- the absolute number the engine-read version produced; when the adapter
	-- publishes 58 the next frame re-asserts and the sum is unchanged.
	local GuiService = game:GetService("GuiService")
	-- ...AND IT RESERVES WHAT THE CHIPS ACTUALLY MEASURE, NOT A LITERAL.
	--
	-- `demo_picker.BAR_HEIGHT` was the whole answer, and it was a number tuned once
	-- against Facet Neutral ("the taller chip's measured 46px, plus padding"). A
	-- chip is a THEMED control whose height is its theme's chrome plus its label at
	-- the player's own text size, so the literal was only ever right for the theme
	-- and the device it was measured on: under Pixel Quest, on a phone, the chip
	-- came out taller than the strip that was supposed to hold it and its plate
	-- painted over the top of the demo's own page title (device report 2026-07-27).
	-- The file's standing excuse — "a literal because two separate surfaces cannot
	-- measure each other" — stopped being true twice over: the showcase composes
	-- BOTH chips into one surface it owns (see the chrome block below), and the
	-- presenter feeds `onGeometry(rectOf)` after the first solve and every refresh.
	--
	-- SO IT MEASURES. `chipsBottom` is the solved bottom edge of the chip row, fed
	-- back from the chrome surface. It is stable under this reservation — the Bar is
	-- placed at `coreTopSignal`, the live Roblox topbar inset, and NOT at the
	-- reservation — so reserving from it cannot chase its own tail. The literal
	-- survives only as the first-frame value, for the one frame before any geometry
	-- exists, and as the standalone (non-composed) pickers' own strip.
	local chipsBottom = Compose.cell(nil :: number?)
	local backdropHandle: any = nil
	-- the live core-topbar height, published as a signal because the CHROME is
	-- presented edge-to-edge (it owns the strip) and therefore has to place
	-- itself below the Roblox buttons itself, reactively
	local coreTopSignal = Compose.cell(GuiService:GetGuiInset().Y)
	local function reserveBar()
		local coreTop = GuiService:GetGuiInset().Y
		if coreTopSignal:peek() ~= coreTop then
			coreTopSignal:set(coreTop)
		end
		-- the same space step the chrome pads itself with, so the demo below starts
		-- clear of the chips instead of flush against them — MAX'D AGAINST THE
		-- ACTIVE PACKAGE'S OWN CHROME GLOW (task SHOWCASE3, director repro: S22
		-- Ultra preset, Glossy Mobile — the chip row's own `shadow = "raised"`
		-- glow got cropped by the demo screen's opaque background painting over
		-- its tail, because the plain rhythm step (10px under Glossy Mobile) was
		-- less than the glow's own reach (17px). See `demo_picker.reservationSlack`
		-- for the full measurement and the `math.max`-not-`+` reasoning.
		local metrics = env:get("themeMetrics"):peek()
		local baseSlack = if type(metrics) == "table" then metrics.space.s else 8
		local chromeBleed = if type(metrics) == "table" then metrics.chromeBleed else nil
		local slack = demo_picker.reservationSlack(baseSlack, chromeBleed)
		--[[ THE TEN-FOOT MARGIN IS SPENT ONCE (director round 4, 2026-08-21). The
			chips now sit inside the overscan insets on a television (`showcase_chrome`
			§"AND IN PAST THE TELEVISION'S BEZEL"), so their measured bottom edge
			already carries the margin — and `renderer.luau` adds the SAME margin to
			every content surface on top of whatever this publishes. Reserving the raw
			number would open a sixty-pixel dead band under the strip. Zero on every
			near display, where the renderer adds nothing. ]]
		local overscanTop = showcase_chrome.overscanEdge(
			env:get("distanceProfile"):peek(),
			env:get("effectiveOverscanInsets"):peek(),
			"top"
		)
		--[[ ONE AUTHORITY FOR THE PLATFORM'S ROW, ON BOTH SIDES OF THE SUBTRACTION
			(review 2026-09-13). `barReservation`'s floor is `platformTop + BAR_HEIGHT`
			and the band published below is `want - platformTop`, so if the two came
			from different places — `GetGuiInset()` for the floor and the fact for the
			subtrahend — a frame in which they disagreed would publish a band that is
			wrong by the difference. They cannot disagree if there is one of them.

			The fact is also the RIGHT one: it is what the renderer will add back, and
			before the adapter has published it reads zero, so the whole window-space
			number is spent here — exactly the absolute reservation the engine read
			produced, which is what the "compute it from the engine" rule above was
			protecting. `coreTopSignal` keeps reading the engine directly, because
			that one is not part of this sum: it PLACES the chip row. ]]
		local platform = env:get("coreSafeInsets"):peek()
		local platformTop = if type(platform) == "table" then math.max(0, tonumber(platform.top) or 0) else 0
		local want = demo_picker.barReservation(platformTop, chipsBottom:peek(), slack, overscanTop)
		local band = math.max(0, want - platformTop)
		local live = env:get("appChromeInsets"):peek()
		if type(live) == "table" and live.top == band then
			return
		end
		env:set("appChromeInsets", { top = band, bottom = 0, left = 0, right = 0 })
	end
	reserveBar()
	local examplesFolder = ReplicatedStorage:WaitForChild("FacetExamples", 10)
	local scenariosFolder = ReplicatedStorage:FindFirstChild("FacetScenarios")
	-- the engine-side materializer BOTH hosts share. Required here and
	-- not inside `mountDemo` so a missing module is a loud boot failure rather than
	-- a demo that silently mounts empty panes.
	local foreignInstances = if scenariosFolder ~= nil
		then require(scenariosFolder:WaitForChild("foreign_instances")) :: any
		else nil

	--[[ HOW A DEMO MOUNTS is `demo_host.mount`: one build contract for fixtures
		and tutorial examples alike, presented through the application and released
		with its screen. It is a module rather than a local here because it is the
		one piece of this mount path a headless spec can drive, and
		`tests/gallery_demo_host.spec.luau` drives that one rather than a copy. ]]
	local activeBuilt: any = nil
	local activeNavigation = Compose.cell(nil :: any)
	local function mountDemo(demo: any): any
		local folder = if demo.kind == "fixture" then scenariosFolder else examplesFolder
		assert(folder ~= nil, `showcase: the {demo.kind} modules are not replicated`)
		local mod = require(folder:FindFirstChild(demo.module)) :: any
		local built: any = nil
		--[[ THE CONTEXT EVERY DEMO BUILDS AGAINST, the build-time subset of the
			scenario runner's. Nothing a demo reads at build may be absent.

			The `foreign` seam rides along (UI.Foreign): a fixture whose panes hold
			caller-owned instances declares them as data and adopts them through
			`ctx.foreign.adopt`. It resolves the demo's own controller lazily, because
			the handle does not exist until the demo is presented. ]]
		local ctx = {

			Facet = Facet,
			app = app,
			UI = UI,
			Compose = Compose,
			core = core,
			env = env,
			adapter = adapter,
			actionSystem = system,
			presenter = pres,
			worldActions = function(triggered)
				return require(script:WaitForChild("world_actions_demo")).mount(
					{ core = core, presenter = pres },
					function(value)
						-- The world and its cover must switch in the same render frame.
						-- Keep the backdrop solved and styled while the camera is exposed.
						backdropHandle.controller.setRootVisible(not value)
					end,
					triggered
				)
			end,
			foreign = {
				adopt = function(nodePath: string, content: any): string
					if built == nil or built.handle == nil then
						return "not-presented"
					end
					return foreignInstances.adopt(built.handle.controller, nodePath, content)
				end,
			},
			--[[ THE RESOURCE TRANSPORT, the runner's other engine-owned seam
					(NS-A13, `scenarios/runner.luau`). A scenario stays engine-free, so
					the host is what hands it `ContentProvider:PreloadAsync` — and
					`async_images` calls this at BUILD, not in a step, which is why the
					seam has to be in the minimal ctx rather than deferred.

					It is here because `async-images` joined the picker (round-3 O-30):
					`newAsyncImage` was demonstrated by a fixture no player could select.
					Without this the demo would take the pcall in `show()` and warn.
					`sponsor_avatars` reads the same seam and degrades honestly when it is
					absent, which is what a headless run still exercises. ]]
			bindResourceTransport = function(provider: any): () -> ()
				local transport = require(ReplicatedStorage.Facet.client.roblox_resources) :: any
				return transport.bind(provider)
			end,
			--[[ THE ENGINE'S OWN PAINT BIT, WHICH ONLY THE TEST RIG USED TO CARRY
					(NM-H4a, 2026-08-16). Byte-identical to `scenarios/runner.luau`'s seam
					of the same name — solved rects plus `Visible`, for named paths, read
					on the host side so the fixture stays engine-free.

					It is in the MINIMAL ctx for the reason the `foreign` and `present`
					comments above record twice over: the fixture a player actually opens
					runs HERE, and a seam only the runner carries is a seam no device pass
					can use. The HUD's paint probe is the instrument for a defect reported
					from a real phone and reproduced by nothing in this repository; without
					this line it would degrade to the model-only readout on the one host
					that matters, which is the same failure as having no instrument. ]]
			--[[ ...AND `enabled` IS THE SURFACE ROOT, the half a GuiObject cannot
					carry (2026-08-16). A surface is hidden with `ScreenGui.Enabled`, which
					is a different property on a different class: every path a caller can
					name resolves to a GuiObject, so a whole screen goes dark with every one
					of its nodes still reporting `Visible = true`. A probe that reads only
					the paint bit calls that screen healthy — which is exactly what the
					HUD's plate did on the reported phone. ]]
			geometry = function(paths: { string }): { [string]: any }
				local out: { [string]: any } = {}
				for _, path in paths do
					local inst = (adapter :: any).getInstance and (adapter :: any).getInstance(path)
					if inst ~= nil and inst:IsA("GuiObject") then
						local layer = inst:FindFirstAncestorWhichIsA("LayerCollector")
						--[[ ...AND THE TWO WAYS A PERFECT RECT PAINTS NOTHING (2026-08-17).
								The plate reported `14 of 14 painting` over a screen missing six
								zones, with every rect, size, `Visible` and `Enabled` correct. What
								it had never read is the pair of engine facts that make a node
								invisible WITHOUT touching any of those:

								  * a `CanvasGroup` ancestor at `GroupTransparency = 1` — the
								    framework's own fade group, whose subtree renders into a buffer
								    that is then drawn at nothing;
								  * an ancestor that CLIPS and does not contain this node — the
								    node keeps its absolute rect and is simply not drawn.

								Both are read off the live tree here rather than inferred, because
								the engine is the only thing that knows them. ]]
						local groupAlpha = 0
						local clippedBy: string? = nil
						local pos, size = inst.AbsolutePosition, inst.AbsoluteSize
						local up: Instance? = inst.Parent
						while up ~= nil and not up:IsA("LayerCollector") do
							if up:IsA("CanvasGroup") then
								groupAlpha = math.max(groupAlpha, (up :: any).GroupTransparency)
							end
							if up:IsA("GuiObject") and (up :: any).ClipsDescendants then
								local p, s = (up :: any).AbsolutePosition, (up :: any).AbsoluteSize
								if
									pos.X + size.X <= p.X
									or pos.Y + size.Y <= p.Y
									or pos.X >= p.X + s.X
									or pos.Y >= p.Y + s.Y
								then
									clippedBy = clippedBy or up.Name
								end
							end
							up = up.Parent
						end
						out[path] = {
							x = pos.X,
							y = pos.Y,
							w = size.X,
							h = size.Y,
							visible = inst.Visible,
							enabled = if layer ~= nil then (layer :: any).Enabled else true,
							groupAlpha = groupAlpha,
							clippedBy = clippedBy,
						}
					end
				end
				return out
			end,
		}
		-- The demo's `present` options are part of the demo: `demo_host.mount`
		-- passes them, so a fixture's `onGeometry` reaches the presenter.
		built = demo_host.mount(ctx, mod)
		local releases: { () -> () } = {}
		if built.handle ~= nil then
			--[[ THE NATIVE-SCROLL MIRROR. A virtualized collection cannot reach the
				render controller at build, so the consumer wires `bindNativeScroll`
				after the demo is presented. Without it the engine moves its canvas and
				the control never hears. A double bind is harmless and a missing one is
				not; the unbind is released with the demo. ]]
			for _, value in built :: any do
				local bind = nativeScrollBinderOf(value)
				if bind ~= nil then
					local unbind = bind(built.handle.controller)
					if type(unbind) == "function" then
						table.insert(releases, unbind)
					end
				end
			end
			-- The declared half of the foreign seam: whatever `built.foreignContent`
			-- names is adopted now, and the per-node status is kept for the report.
			if built.foreignContent ~= nil then
				built.foreignApplied = foreignInstances.applyAll(built.handle.controller, built.foreignContent)
			end
		end
		-- A demo whose loopback transport answers promptly exposes `server.flush`.
		-- Example 03 delivers through its own visible button and exposes none.
		if built.server ~= nil and type(built.server.flush) == "function" then
			table.insert(
				releases,
				app.onFrame(function()
					built.server.flush()
				end)
			)
		end

		local dispose = built.dispose
		activeBuilt = built
		activeNavigation:set(built.navigationLayout)
		built.dispose = function()
			if activeBuilt == built then
				activeBuilt = nil
				activeNavigation:set(nil)
			end
			for _, release in releases do
				release()
			end
			table.clear(releases)
			dispose()
		end
		return built
	end

	-- A BACKDROP, PRESENTED FIRST AND NEVER RE-PRESENTED.
	--
	-- Every demo screen is transparent, which was invisible in Studio over a
	-- plain grey baseplate and unusable on a phone over a textured 3D world: the
	-- playlist's hint row was illegible against the sky, and the confirm dialog
	-- had no boundary at all. A showcase is a UI place — the world behind it is
	-- scenery, not content.
	--
	-- Z-ORDER IS PRESENT ORDER (presenter §2.2), so presenting this ONCE, before
	-- anything else, keeps it underneath every demo and the chrome without any
	-- notion of "send to back". It is never raised, and that is the mechanism.
	local _, _, mountedBackdrop = app.mount(
		function()
			return UI.Screen("ShowcaseBackdrop")({
				UI.Box("Fill")({
					surface = "base",
					width = UI.fill(),
					height = UI.fill(),
				}),
			})
		end,
		-- edgeToEdge: a backdrop that respects the safe area is a rectangle with
		-- the world showing around it (device capture, 2026-07-26)
		{ responder = "passive", rootPolicy = "edgeToEdge" }
	)
	backdropHandle = mountedBackdrop

	-- THE CHROME: A STRIP THAT NEVER MOVES, AND A PANEL THAT COMES AND GOES.
	--
	-- The structural half lives in `showcase_chrome.luau`, where it can be
	-- required and driven headlessly — this file is a client script and reaches
	-- engine globals at load, so anything built inline here can only ever be
	-- checked by reading its source text. Read that module's header for the two
	-- findings behind the shape: the chrome was unreachable by keyboard and
	-- gamepad (nothing outside the presenter's tap handler ever calls `engage()`),
	-- and the old always-on-top chrome owned the focus SCOPE, so no key could
	-- reach the demo on screen either.
	--
	-- What survives from the composed-chrome round is the reason it exists: the
	-- two chips are laid out by ONE solver, so they can never overlap the way two
	-- separately-presented surfaces held apart by a hard-coded offset did on a
	-- real phone. What changed is that the open PANEL is its own surface,
	-- which is what lets the strip sit permanently underneath the demos.
	local showcasePicker: any = nil
	local demos: any = nil
	local settings: any = nil
	local chrome: any = nil

	demos = demo_picker.mount({
		Facet = Facet,
		app = app,
		env = env,
		composed = true,
		mountDemo = mountDemo,
		-- PANEL PRESENCE IS THE CHROME'S, so the chip asks and the row's choice
		-- takes the panel down. `open` is handed in for the chip's own label
		-- ("Close" while its section is showing).
		onChip = function()
			chrome.request("demos")
		end,
		onChose = function()
			chrome.close()
		end,
		-- THE SETTING OUTLIVES THE DEMO. A demo may drive `reducedMotion` while it
		-- is on screen (`scenarios/with_animation.luau` does, deliberately, and
		-- restores what it found on dispose) — re-applying the preference after
		-- every mount is what makes the settings control a SETTING rather than
		-- something the next demo swap silently reverts.
		onRaise = function()
			if settings ~= nil then
				settings.apply()
			end
		end,
		warn = warn,
	})
	showcasePicker = mountThemePicker(true, true)
	settings = settings_panel.mount({
		preview = displayPreview,
		Facet = Facet,
		app = app,
		env = env,
		-- theme is a SETTING and lives in here now (CONCERNS 16); nil when no
		-- package replicated, which leaves settings with just its motion section
		themeSections = if showcasePicker ~= nil then showcasePicker.sections else nil,
		-- stamped by tools/build_places.sh at build time; nil in a Rojo-served
		-- session, where the source on disk IS the running source and the
		-- question this answers cannot arise.
		buildStamp = workspace:GetAttribute("Facet_Build"),
	})

	chrome = showcase_chrome.mount({
		Facet = Facet,
		app = app,
		core = core,
		env = env,
		actionSystem = system,
		demos = demos,
		settings = settings,
		coreTop = coreTopSignal,
		navigationLayout = activeNavigation,
		-- THE MEASUREMENT THAT REPLACED THE LITERAL (see reserveBar). Fed after the
		-- first solve and after every refresh, so a theme swap, an orientation
		-- change or a raised text preference re-reports the chip row's real bottom
		-- edge and the reserved strip follows it.
		onChipsBottom = function(bottom: number)
			if chipsBottom:peek() ~= bottom then
				chipsBottom:set(bottom)
			end
		end,
		--[[ ...AND THE SAME ROW, DECLARED AS APP CHROME (director 2026-08-15, item 4).
			`appChromeInsets.top` above is that row's BOUNDING BOX and stays exactly as
			it was — every demo still starts below the chips, which is what a demo
			wants; the two facts are one declaration read two ways (how much content
			must clear, and where the chrome actually is). This
			publishes the row's real RECT through `appChromeRects`, the env fact
			`platformChrome` merges alongside the PLATFORM's own cluster, so a surface
			that means to reserve per column (the screen-anchored HUD does) can sit
			LEVEL with the chips in the columns they do not cover instead of below them
			everywhere. Written only on change: it feeds a derived memo. ]]
		onChipsRect = function(rect: any)
			local declared = { { x = rect.x, y = rect.y, w = rect.w, h = rect.h } }
			local live = env:get("appChromeRects"):peek()
			local was = if type(live) == "table" then (live :: any)[1] else nil
			if type(was) == "table" and was.x == rect.x and was.y == rect.y and was.w == rect.w and was.h == rect.h then
				return
			end
			env:set("appChromeRects", declared)
		end,
	})

	-- the strip is up; now mount the demo it advertises
	demos.show(demos.current())

	-- Re-assert the reservation before each solve: the platform adapter rewrites
	-- coreSafeInsets on orientation and topbar changes, which this band is stated
	-- relative to. The write is idempotent, so this simply keeps the strip reserved.
	local showcaseHeartbeat = app.onFrame(reserveBar)
	-- A HANDLE FOR THE ROOM. The scenario runner already publishes its API this
	-- way (examples/gallery/scenarios/runner.luau) and for the same reason: the
	-- Studio MCP's execute_luau runs in a DIFFERENT Luau VM than this
	-- client script, so `_G` does not cross but a BindableFunction in the shared
	-- DataModel does. It is what lets the demo be advanced without a pointer,
	-- which matters while the injected-input limitation (XP-B3) stands.
	_G.FacetShowcase = {
		list = demo_picker.list,
		current = demos.current,
		mounted = demos.mounted,
		showNext = demos.showNext,
		chrome = chrome,
		settings = settings,
	}
	--[[ WHAT THIS API OWES A CALLER: THE ID IT DELIVERED, NOT THE ID IT WAS ASKED
		FOR.

		`showNext` used to answer `{ current = <the id it advanced to> }` and nothing
		else — a claim about the SELECTION, written in the grammar of a claim about
		the screen. The two come apart whenever `mountDemo` throws: `demo_picker.show`
		pcalls it, so a fixture module that is not replicated ends as a client-console
		`warn` no MCP caller ever sees, while this handle answers with the demo's id
		as though it were up.

		MEASURED, 2026-08-15, showcase place: with `FacetScenarios.measured_extents`
		renamed out from under it, `showNext` returned `{"current":"measured-extents"}`,
		`current` agreed, and PlayerGui held only the backdrop and the chrome. That
		answer is worse than an error, because it AGREES with whoever is driving — a
		sweep taken through it scanned a leftover surface 21 times and reported a
		clean bill of health for 21 demos it never looked at
		(artifacts/hit-expander-overhang/corpus-measurement.md).

		So every answer carries all three facts: what is SELECTED, what is MOUNTED
		(`false` when the last mount failed), and whether they agree. `ok` is
		derivable from the other two on purpose — a caller that reads only one field
		should land on the honest one. ]]
	local function demoState(): { [string]: any }
		local delivered = demos.mounted()
		return { current = demos.current(), mounted = delivered or false, ok = delivered == demos.current() }
	end
	local showcaseApi = Instance.new("Folder")
	showcaseApi.Name = "FacetShowcaseAPI"
	for fnName, impl in
		{
			report = function(_arg: string?)
				return HttpService:JSONEncode(
					if activeBuilt and activeBuilt.report then activeBuilt.report() else { available = false }
				)
			end,
			step = function(arg: string?)
				local fn = activeBuilt and activeBuilt.steps and activeBuilt.steps[arg]
				if type(fn) ~= "function" then
					return HttpService:JSONEncode({ ok = false })
				end
				fn()
				return HttpService:JSONEncode({ ok = true })
			end,
			list = function(_arg: string?)
				return HttpService:JSONEncode(demo_picker.list())
			end,
			current = function(_arg: string?)
				return HttpService:JSONEncode(demoState())
			end,
			showNext = function(arg: string?)
				demos.showNext(tonumber(arg) or 1)
				return HttpService:JSONEncode(demoState())
			end,
			-- the theme half of the same handle, for the same reason: with no
			-- scriptable pointer (XP-B3) this is how a themed view gets driven
			themes = function(_arg: string?)
				if showcasePicker == nil then
					return HttpService:JSONEncode({ entries = {} })
				end
				local ids = {}
				for _, entry in showcasePicker.entries do
					table.insert(ids, entry.id)
				end
				return HttpService:JSONEncode({ entries = ids, current = showcasePicker.selection:peek() })
			end,
			pickTheme = function(arg: string?)
				if showcasePicker == nil then
					return HttpService:JSONEncode({ ok = false })
				end
				-- `dispatch` is GONE: behaviour moved onto the nodes (handoff §4.1)
				-- and this went on calling it, so pickTheme errored with "attempt to
				-- call a nil value" and there was no working route to switch theme
				-- from a script at all. `pickPackage` is the same call the chips'
				-- own onActivate makes.
				local ok = showcasePicker.pickPackage(tostring(arg))
				return HttpService:JSONEncode({ ok = ok, current = showcasePicker.selection:peek() })
			end,
			-- THE SAME CALL A CHIP PRESS AND THE TOGGLE KEY MAKE. Theme now lives
			-- inside settings (CONCERNS 16), so "open the themes" is "open the
			-- settings section" — one route, not a parallel one that can rot.
			toggleThemes = function(_arg: string?)
				chrome.request("settings")
				return HttpService:JSONEncode({ open = chrome.isOpen(), section = chrome.kind:peek() })
			end,
			chrome = function(arg: string?)
				if arg == "demos" or arg == "settings" then
					chrome.request(arg)
				else
					chrome.request(nil)
				end
				return HttpService:JSONEncode({
					open = chrome.isOpen(),
					section = chrome.kind:peek(),
					engaged = chrome.panelHandle() ~= nil and chrome.panelHandle().responder:peek() or "none",
				})
			end,
			-- Display and input settings use the same routes as their Pickers.
			preview = function(arg: string?)
				local ok = if arg ~= nil then settings.setPreview(arg) else true
				return HttpService:JSONEncode({
					ok = ok,
					profile = settings.previewProfile:peek(),
					viewport = env:get("viewportRect"):peek(),
				})
			end,
			orientation = function(arg: string?)
				local ok = if arg ~= nil then settings.setOrientation(arg) else true
				return HttpService:JSONEncode({ ok = ok, orientation = settings.previewOrientation:peek() })
			end,
			input = function(arg: string?)
				local ok = if arg ~= nil then settings.setInput(arg) else true
				return HttpService:JSONEncode({
					ok = ok,
					input = settings.previewInput:peek(),
					resolved = env:get("interactionClasses"):peek().primary,
				})
			end,
			distance = function(arg: string?)
				if arg ~= nil then
					settings.setViewingDistance(arg)
				end
				return HttpService:JSONEncode({
					preference = env:get("viewingDistance"):peek(),
					resolved = env:get("distanceProfile"):peek(),
					source = env:get("distanceProfileSource"):peek(),
				})
			end,
			motion = function(arg: string?)
				if arg == "full" or arg == "reduced" then
					settings.setMode(arg)
				end
				return HttpService:JSONEncode({
					motion = settings.mode:peek(),
					setting = settings.setting:peek(),
					reduced = env:get("reducedMotion"):peek() == true,
				})
			end,
		} :: { [string]: (string?) -> string }
	do
		local bf = Instance.new("BindableFunction")
		bf.Name = fnName
		bf.OnInvoke = impl
		bf.Parent = showcaseApi
	end
	showcaseApi.Parent = workspace
	workspace:SetAttribute("Facet_GalleryReady", true)
	workspace:SetAttribute("Facet_ShowcaseReady", true)
	print(
		`[Facet Showcase] {Facet.VERSION} — {#demo_picker.list()} demos, theme picker {if showcasePicker ~= nil
			then "on"
			else "unavailable"}; chrome: {showcase_chrome.TOGGLE_KEYBOARD} on a keyboard, `
			.. `{showcase_chrome.SECTION_GAMEPAD.demos}/{showcase_chrome.SECTION_GAMEPAD.settings} on a pad`
	)
	local _keep = { showcaseHeartbeat, demos, showcasePicker, settings, chrome, unbindEnv, unbindResponderEffects }
	return
end

-- Verification-scenario selector (fable-execution-contract §5): set the
-- workspace STRING attribute Facet_Scenario to a registered scenario name
-- BEFORE running to mount that deterministic fixture instead of the demo.
-- The runner exposes _G.FacetScenario (list/steps/step/report/reset) for the
-- Studio MCP and stamps Facet_ScenarioReady/Facet_ScenarioState attributes.
--
-- EVERY WAY THIS CAN FAIL SAYS SO. The folder is not replicated, the name is not
-- registered, the runner throws on the way up: each of those leaves a driver
-- polling `Facet_ScenarioReady` forever, and an ABSENT attribute cannot be told
-- apart from "still booting". So a refusal warns with its reason AND stamps
-- `Facet_ScenarioState`, and a throw is re-raised after the stamp rather than
-- swallowed — a verification surface that no-ops quietly is worse than one that
-- errors, because the run it produces still looks like evidence.
local function refuseScenario(reason: string)
	workspace:SetAttribute("Facet_ScenarioState", boot_mode.refusedState(reason))
	warn(boot_mode.refusal("Facet_Scenario", reason))
end
if bootDecision.mode == "scenario" then
	local scenarioName = bootDecision.scenario :: string
	local registryModule = ReplicatedStorage:WaitForChild("FacetScenarios", 10)
	if registryModule ~= nil then
		local registry = require(registryModule) :: any
		local runner = require(registry.runner) :: any
		local started, result = pcall(runner.start, {
			Facet = Facet,
			registry = registry,
			scenarioName = scenarioName,
			app = app,
			core = core,
			env = env,
			adapter = adapter,
			actionSystem = system,
			unbindEnv = unbindEnv,
		})
		if not started then
			-- the runner stamps its OWN state for the failures it can name (an
			-- unregistered scenario); this covers the ones it cannot, and then puts
			-- the error back so the console goes red too. A pcall that SWALLOWED
			-- this would reproduce the very defect this branch was rewired to fix.
			if workspace:GetAttribute("Facet_ScenarioState") == nil then
				workspace:SetAttribute("Facet_ScenarioState", boot_mode.refusedState("start-failed"))
			end
			warn(boot_mode.refusal("Facet_Scenario", `mounting '{scenarioName}' threw: {tostring(result)}`))
			error(result, 0)
		end
		local _keep = { result, unbindResponderEffects }
		return
	else
		refuseScenario("FacetScenarios is not replicated into this place, so no scenario can be mounted")
	end
end

-- Tutorial example selector (§17 Phase 4 documentation deliverable): set the
-- workspace attribute Facet_Example to 1..7 BEFORE running to present that
-- gallery example instead of the default settings demo. The examples are the
-- exact engine-free modules the tutorial (docs/guide/04-tutorial-examples.md)
-- walks through — they run here as written.
-- only places that SET the attribute wait for the examples folder; the plain
-- settings-demo place must not stall on a folder it never mapped
local EXAMPLES = if bootDecision.mode == "example"
	then ReplicatedStorage:WaitForChild("FacetExamples", 10)
	else ReplicatedStorage:FindFirstChild("FacetExamples")
if bootDecision.mode == "example" then
	local selected = bootDecision.example :: number
	-- the SAME silent-failure rule as the scenario branch above: an example that
	-- was asked for and cannot be found says which piece is missing, rather than
	-- dropping through to a settings demo that looks like the example booted
	local exampleModule = if EXAMPLES ~= nil then EXAMPLES:FindFirstChild(bootDecision.exampleModule :: string) else nil
	if exampleModule == nil then
		warn(
			boot_mode.refusal(
				"Facet_Example",
				if EXAMPLES == nil
					then "FacetExamples is not replicated into this place"
					else `FacetExamples has no module named '{bootDecision.exampleModule}'`
			)
		)
	else
		local example = require(exampleModule) :: any
		-- Two build styles (docs/guide/04-tutorial-examples.md): examples 1-4
		-- answer `{ screen, present }` for the host to present; the game examples
		-- (5-7) present themselves and answer `{ handle }`.
		local built = demo_host.mount({
			Facet = Facet,
			app = app,
			UI = UI,
			Compose = Compose,
			core = core,
			env = env,
			adapter = adapter,
			actionSystem = system,
			presenter = pres,
		}, example)
		-- Controls riding the native canvas expose `bindNativeScroll`; the consumer
		-- binds after present so engine CanvasPosition feeds their window.
		if built.handle ~= nil then
			for _, value in built :: any do
				local bind = nativeScrollBinderOf(value)
				if bind ~= nil then
					bind(built.handle.controller)
				end
			end
		end
		-- COLLAPSED, because the picker is gallery chrome and the example is the
		-- subject (example-quality-pass, found live 2026-08-06). Expanded, its
		-- panel measured `x 339..899, y 8..219` on desktop and covered most of
		-- example 01's text field (`x 16..891, y 78..122`); on a 360x691 phone it
		-- covered the example entirely. It now docks as a chip in the top-right
		-- and opens on demand -- the same restyling reach, none of the occlusion.
		local examplePicker = mountThemePicker(true)
		workspace:SetAttribute("Facet_GalleryReady", true)
		workspace:SetAttribute("Facet_ExampleTitle", example.title)
		print(`[Facet Gallery] example {selected}: {example.title}`)
		local _keep = { unbindEnv, built, examplePicker }
		return
	end
end

-- semantic state: authoritative snapshot + draft + mutation (loopback server)
local snapshot = Facet.replication.snapshot(core, 1, { music = false, sfx = true })
local draftMusic = Compose.cell(false)
local saveStatus = Compose.cell("idle")
local mutation = Facet.replication.mutation(core, {
	optimistic = {
		apply = function(payload)
			draftMusic:set(payload.music)
		end,
		restore = function()
			draftMusic:set(snapshot.binding:peek().music)
		end,
	},
})

-- The replication model survives the view; the mounted component owns the
-- readout calculations and Studio checkpoint subscriptions.
local function Settings()
	local preferredInput = env:get("effectiveInput")
	local hint = Compose.formula(function(use)
		local preferred = use(preferredInput)
		return if preferred == "Touch"
			then "Tap Save to apply"
			elseif preferred == "Gamepad" then "Press A to apply"
			else "Press Enter to apply"
	end)
	local statusLine = Compose.formula(function(use)
		return `music={tostring(use(draftMusic))} save={use(saveStatus)}`
	end)
	Compose.watch(function(use)
		workspace:SetAttribute("Facet_Status", use(statusLine))
	end)
	Compose.watch(function(use)
		workspace:SetAttribute("Facet_Hint", use(hint))
	end)
	Compose.watch(function(use)
		workspace:SetAttribute("Facet_Focused", use(pres.focus.focused) or "")
	end)
	return UI.Screen("GallerySettings")({
		padding = "m",
		gap = "s",
		UI.Text("Title")({ text = "Facet Gallery — Settings", textSize = "title" }),
		UI.Text("Hint")({ text = hint, textSize = "label" }),
		UI.Toggle("Music")({ label = "Music", value = draftMusic }),
		UI.Text("Status")({ text = statusLine, textSize = "label" }),
		UI.Spacer("Gap")({ height = UI.fill() }),
		UI.Button("Save")({
			label = "Save",
			onActivate = function()
				local envelope = mutation.send({ music = draftMusic:peek() }, snapshot.revision())
				saveStatus:set("pending")
				task.defer(function()
					snapshot.ingest(snapshot.revision() + 1, { music = envelope.payload.music, sfx = true })
					mutation.confirm(envelope.requestId, "ok")
					saveStatus:set("confirmed")
					mutation.reset()
				end)
			end,
		}),
	})
end
local _, _, handle = app.mount(Settings)

local picker = mountThemePicker()

-- Studio verification checkpoints
workspace:SetAttribute("Facet_GalleryReady", true)
workspace:SetAttribute("Facet_Version", Facet.VERSION)
-- factory-rerun counter for the no-remount proof: mounted total is stable
-- unless structure genuinely changes
task.defer(function()
	workspace:SetAttribute("Facet_FactoryRuns", handle.root.counters().factoryRuns)
end)

print(`[Facet Gallery] running {Facet.VERSION}; focus={pres.focus.focused:peek()}`)

-- keep references alive for the session
local _keep = { unbindEnv, mutation, unbindResponderEffects, picker }
