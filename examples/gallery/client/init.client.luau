--!strict
-- LuauUI Gallery client bootstrap (design §17 Phase 1): the complete path —
-- replicated semantic state -> adapters -> blueprint -> mount -> solve ->
-- ScreenTarget, with real IAS input and the presenter. The "server" here is a
-- local loopback of semantic state (the gallery is single-place); games wire
-- the same adapters to their replication layer.
-- Studio verification reads workspace attributes LuauUI_* (checkpoints).

-- string requires do NOT wait for replication (platform research 2026-07-19)
if not game:IsLoaded() then
	game.Loaded:Wait()
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local LuauUI = require(ReplicatedStorage:WaitForChild("LuauUI")) :: any
local screen_target = require(ReplicatedStorage.LuauUI.client.screen_target) :: any
local roblox_env = require(ReplicatedStorage.LuauUI.client.roblox_env) :: any
local roblox_input = require(ReplicatedStorage.LuauUI.client.roblox_input) :: any
local gamepad_contention = require(ReplicatedStorage.LuauUI.client.gamepad_contention) :: any
local responder_effects = require(ReplicatedStorage.LuauUI.client.responder_effects) :: any

local UI = LuauUI.UI
local core = LuauUI.newCore()
local env = LuauUI.newEnvironment(core)
local unbindEnv = roblox_env.bind(env)
-- NS-I2 fallback A/B driver: set workspace attribute LuauUI_ForceScrollFallback
-- BEFORE running to exercise the clip-only ScrollView fallback in Studio
-- Native-stylesheets A/B driver (ledger NSS-A2/NSS-A10): LuauUI_NativeStyle=true
-- opts the target into sheet-owned paint; LuauUI_ForceStyleFallback wins over it
-- so the explicit-write path is exercised separately (never only headlessly)
local adapter = screen_target.new({
	forceScrollFallback = workspace:GetAttribute("LuauUI_ForceScrollFallback") == true,
	-- LuauUI_NativeTransitions opts the sheet transitions in (progressive
	-- enhancement, default OFF until the NSS-P3 publish rider clears)
	nativeStyle = (workspace:GetAttribute("LuauUI_NativeStyle") == true and workspace:GetAttribute(
		"LuauUI_ForceStyleFallback"
	) ~= true) and { transitions = workspace:GetAttribute("LuauUI_NativeTransitions") == true } or false,
})
local system = roblox_input.newSystem(core)
-- KEYBOARD NAVIGATION ON, BECAUSE THIS PLACE FREED THE KEY FOR IT
-- (example-quality-pass, 2026-08-06). The presenter's `keyboardNavigation`
-- defaults FALSE so a game that never asked keeps the input behaviour it had —
-- see PresenterOpts. This bootstrap already disables the CoreGui players list a
-- hundred lines below precisely so Tab can reach a developer InputContext, and
-- then never opted in, so Tab bound nothing and traversal was dead in all seven
-- tutorial examples: six Tab presses moved focus zero times. A UI-only gallery
-- whose whole job is demonstrating the framework's input story has to have it on.
local pres = LuauUI.newPresenter(core, env, adapter, system, { keyboardNavigation = true })

-- The presentation layer's clock (Step 5): transitions, toasts, and every
-- motion-clock consumer advance ONLY inside presenter.tick — bind it to the
-- render clock exactly once, or nothing animates live while headless stays green.
local motion_driver = require(ReplicatedStorage.LuauUI.client.motion_driver) :: any
motion_driver.bind(pres)

-- First-responder engine seam (ADR-0014): while an EXCLUSIVE (sinking) surface
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
-- convenience. Set the workspace attribute LuauUI_ThemePicker = false to hide it.
local theme_picker = require(script:WaitForChild("theme_picker")) :: any
local theme_controller = require(ReplicatedStorage.LuauUI.client.theme_controller) :: any

-- `collapsible` is passed only by the showcase place: see theme_picker's
-- MountOpts for why it is opt-in rather than the default.
local function mountThemePicker(collapsible: boolean?, composed: boolean?)
	if workspace:GetAttribute(theme_picker.ATTRIBUTE) == false then
		return nil
	end
	-- the reference packages replicate as ModuleScripts under
	-- ReplicatedStorage.LuauUIThemes (examples/gallery.project.json); each
	-- exposes `build(themes) -> (package, report)` through the PUBLIC surface
	local folder = ReplicatedStorage:FindFirstChild("LuauUIThemes")
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
				return if theme_picker.isPickable(m) then (m.build(LuauUI.themes)) else nil
			end)
			if ok and built ~= nil then
				packages[module.Name] = built
			end
		end
	end
	local mounted = theme_picker.mount({
		LuauUI = LuauUI,
		core = core,
		env = env,
		adapter = adapter,
		presenter = pres,
		packages = packages,
		themeController = theme_controller,
		collapsible = collapsible,
		-- composed: hand back the chip and the panel instead of presenting an
		-- overlay, so the showcase host can lay both pickers out in one surface
		composed = composed,
		warn = warn,
	})
	if mounted ~= nil then
		workspace:SetAttribute("LuauUI_ThemePickerReady", true)
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
-- not in LuauUI: hiding a game's leaderboard to win a key is the same trade the
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

-- ===== SHOWCASE MODE (the hands-on device place) ==========================
--
-- One place you publish once and open on a phone, a tablet, a desktop and a
-- console, with BOTH the demo and the theme switchable in-game. Every other
-- selector in this file needs a workspace attribute set before Play and a
-- republish to change — a fine developer affordance and a useless one on a
-- device you are holding.
--
-- The showcase place sets `LuauUI_Showcase = true` in its own Rojo project
-- (tools/build_places.sh), so nobody has to touch an attribute; the branch is
-- inert in every other place.
if workspace:GetAttribute("LuauUI_Showcase") == true then
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
	-- LuauUI already has the right mechanism, and it is the one the CoreGui
	-- topbar itself uses: `coreSafeInsets` is read on every solve, so a top inset
	-- of (core topbar + bar) makes the SOLVER lay every demo out below both.
	-- Nothing overlaps because nothing floats.
	--
	-- THE TOP EDGE ONLY. `coreSafeInsets` is a FOUR-EDGE fact and the platform
	-- adapter is its author: on a notched phone in landscape the left and right
	-- edges are the notch and the home indicator, and on some devices `bottom` is
	-- real too. Writing a whole table with three zeroes in it looks like
	-- "reserving the top" and is actually "deleting every other edge" — content
	-- would sit under CoreGui-reserved regions on exactly the landscape and
	-- notched rows the device matrix drives. So the other three edges are carried
	-- through from whatever the adapter last published.
	--
	-- THE TOP IS COMPUTED FROM THE ENGINE, NOT FROM THE FACT. Deriving it by
	-- adding to whatever `coreSafeInsets` currently holds looks equivalent and is
	-- not: this ran before the adapter had published the real 58px topbar, so it
	-- reserved 0+40 and the demo's content started at y=40 — ABOVE the Roblox
	-- buttons, with the chips underneath them. Reading GetGuiInset directly makes
	-- the reservation absolute, and re-asserting it each frame makes it
	-- idempotent and immune to the adapter rewriting the fact underneath us.
	local GuiService = game:GetService("GuiService")
	-- ...AND IT RESERVES WHAT THE CHIPS ACTUALLY MEASURE, NOT A LITERAL.
	--
	-- `demo_picker.BAR_HEIGHT` was the whole answer, and it was a number tuned once
	-- against Studio Neutral ("the taller chip's measured 46px, plus padding"). A
	-- chip is a THEMED control whose height is its theme's chrome plus its label at
	-- the player's own text size, so the literal was only ever right for the theme
	-- and the device it was measured on: under Pixel Quest, on an iPhone, the chip
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
	local chipsBottom = core:signal(nil :: number?)
	-- the live core-topbar height, published as a signal because the CHROME is
	-- presented edge-to-edge (it owns the strip) and therefore has to place
	-- itself below the Roblox buttons itself, reactively
	local coreTopSignal = core:signal(GuiService:GetGuiInset().Y)
	local function reserveBar()
		local coreTop = GuiService:GetGuiInset().Y
		if coreTopSignal:get() ~= coreTop then
			coreTopSignal:set(coreTop)
		end
		-- the same space step the chrome pads itself with, so the demo below starts
		-- clear of the chips instead of flush against them
		local metrics = env:get("themeMetrics"):get()
		local slack = if type(metrics) == "table" then metrics.space.s else 8
		local want = demo_picker.barReservation(coreTop, chipsBottom:get(), slack)
		local live = env:get("coreSafeInsets"):get()
		local other = if type(live) == "table" then live else {}
		if type(live) == "table" and live.top == want then
			return
		end
		env:set("coreSafeInsets", {
			top = want,
			bottom = other.bottom or 0,
			left = other.left or 0,
			right = other.right or 0,
		})
	end
	reserveBar()
	local examplesFolder = ReplicatedStorage:WaitForChild("LuauUIExamples", 10)
	local scenariosFolder = ReplicatedStorage:FindFirstChild("LuauUIScenarios")
	-- the engine-side materializer BOTH hosts share (ADR-0034). Required here and
	-- not inside `mountDemo` so a missing module is a loud boot failure rather than
	-- a demo that silently mounts empty panes.
	local foreignInstances = if scenariosFolder ~= nil
		then require(scenariosFolder:WaitForChild("foreign_instances")) :: any
		else nil

	-- EVERY DEMO GETS ITS OWN SCOPE, AND THE HOST INSTALLS IT.
	--
	-- Ownership in this core is EXPLICIT (`scope:own`) — there is no ambient
	-- scope a signal joins by being created — and the tutorial examples create
	-- signals and memos straight on the core they are handed and return no
	-- `dispose`. So dismissing their screens reclaimed the Instances and left
	-- their reactive state behind: after eight swaps, eight demos' worth of
	-- signals were still live on the shared core.
	--
	-- The fix belongs HERE, not in the examples: the examples are what the guide
	-- walks through line by line, and a showcase requirement has no business
	-- changing them. They take the core as an argument, so the host hands them a
	-- proxy whose allocating methods own into a per-demo scope. Disposing that
	-- scope reclaims everything the demo made, whatever it made it with.
	local function scopedCore(scope: any): any
		return setmetatable({}, {
			__index = function(_, key: string)
				local value = (core :: any)[key]
				if type(value) ~= "function" then
					return value
				end
				-- the allocating surface: what these return is what leaks
				if key == "signal" or key == "memo" or key == "observe" or key == "effect" or key == "scope" then
					return function(_self, ...)
						return scope:own(value(core, ...))
					end
				end
				return function(_self, ...)
					return value(core, ...)
				end
			end,
		})
	end

	-- HOW A DEMO MOUNTS is the host's job, because the two contracts differ:
	-- a tutorial example takes (LuauUI, core, opts) and may present itself; a
	-- scenario fixture takes one ctx table and returns a screen for us to
	-- present. The picker knows neither, which is what keeps it a picker.
	local function mountDemo(demo: any): any
		local demoScope = core:scope(`showcase-demo-{demo.id}`)
		local demoCore = scopedCore(demoScope)
		local built: any
		if demo.kind == "fixture" then
			assert(scenariosFolder ~= nil, "showcase: LuauUIScenarios is not replicated")
			local mod = require(scenariosFolder:FindFirstChild(demo.module)) :: any
			-- the MINIMAL ctx: the build-time subset of the runner's ctx. The
			-- adaptive-controls fixture reads {LuauUI, core, env}; row_actions
			-- additionally binds `presenter.onTick` at build (its VirtualList
			-- waits for a mounted scroll path). `actionSystem` rides along for
			-- the same reason it does in the runner — a fixture's steps never
			-- run here, but nothing a fixture reads at BUILD may be absent.
			--[[ THE `foreign` SEAM RIDES ALONG (UI.Foreign, ADR-0034), for exactly
				the reason the `present`-opts comment below records. A fixture whose
				panes hold caller-owned instances declares them as DATA and adopts
				them through `ctx.foreign.adopt` — a seam only the scenario RUNNER
				had. Without this the showcase a player actually opens would mount
				`foreign_content`'s three panes EMPTY while the runner and the sweep
				showed them full: the test rig more correct than the shipped host,
				which is the failure this file has already shipped once.

				It resolves the demo's own controller lazily, because the handle does
				not exist until `present` returns two dozen lines below and the
				fixture's buttons are pressed long after that. ]]
			local demoHandle: any = nil
			built = mod.build({
				LuauUI = LuauUI,
				core = demoCore,
				env = env,
				actionSystem = system,
				presenter = pres,
				foreign = {
					adopt = function(nodePath: string, content: any): string
						if demoHandle == nil then
							return "not-presented"
						end
						return foreignInstances.adopt(demoHandle.controller, nodePath, content)
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
					local transport = require(ReplicatedStorage.LuauUI.client.roblox_resources) :: any
					return transport.bind(provider)
				end,
			})
			--[[ A FIXTURE'S `present` OPTS ARE PART OF THE FIXTURE (C2, 2026-08-12).
				This dropped the second argument, so every `present` table a fixture
				declared was silently discarded HERE and nowhere else: the scenario
				runner passes it (`scenarios/runner.luau`), the overflow sweep passes
				it (`tests/overflow_sweep.spec.luau`), and the tutorial branch eleven
				lines below passes it — the test rigs were more correct than the
				shipped host, which is the failure mode
				docs/lessons/the-solver-already-told-you.md is named after.

				It was load-bearing the day it was found: `scenarios/row_actions.luau`
				derives its hosted VirtualList's window from its own solved pane
				through `present.onGeometry`, so in the showcase that window stayed
				frozen at the pre-geometry literal and the list painted past its pane
				on a landscape phone — the very defect that seam was added to fix.
				`present` is nil for a fixture that declares none, which is exactly
				what `present(screen)` meant before. ]]
			built.handle = pres.present(built.screen, built.present)
			demoHandle = built.handle
			--[[ THE NATIVE-SCROLL MIRROR, WHICH THIS BRANCH NEVER BOUND (measured live
				in Studio 2026-08-15, showcase place, `virtual_grid`: an engine scroll to
				`CanvasPosition.Y = 2000` left the mounted window still showing `c1..c16`).

				THE SAME OMISSION, A THIRD TIME. A virtualized collection cannot reach the
				render controller at build, so the CONSUMER wires `bindNativeScroll` after
				`present` — and the loop that does it existed in the tutorial branch below
				and in the single-demo path, and nowhere here. Without it `scrollTop` is
				written by nothing: the engine moves its canvas, the control never hears,
				and the window stays pinned on its first line while the player flings a
				list that visibly does not move.

				FIVE PICKER DEMOS WERE DEAD ON THIS PATH, not one — `virtual_grid`,
				`virtual_hgrid`, `variable_extents`, `measured_extents` and
				`table_virtualized` all publish their control flat (or under `api`) and
				bind nowhere else. The four that worked (`card_rail`, `row_actions`,
				`sponsor_list`, `sponsor_drop`) bind themselves from `presenter.onTick`,
				which is why the defect was invisible in the fixtures a device pass drove.
				`scenarios/virtual_grid.luau:318-321` publishes `grid` in as many words
				"for the showcase host's native-scroll auto-bind" — against a loop that
				did not exist for fixtures.

				It is the same shape as the `present`-opts defect eleven lines above (C2)
				and the `foreign` seam below it: the fixture branch keeps arriving at a
				capability the runner, the sweep and the tutorial branch already have. The
				general fix — making the omission impossible or loud in the CONTROL — is
				booked as a framework defect (`ui_todo.md`, "the bind you can forget"),
				because it belongs in the presenter's contribution seam and not in a
				showcase host.

				A DOUBLE BIND IS HARMLESS AND A MISSING ONE IS NOT: a fixture that also
				binds itself ends with two `observeScroll` callbacks writing the same
				position into the same signal. The unbind is owned by the demo's scope, so
				it is released when the player picks the next demo. ]]
			for _, value in built :: any do
				local bind = nativeScrollBinderOf(value)
				if bind ~= nil then
					demoScope:own(bind(built.handle.controller))
				end
			end
			-- ...and the DECLARED half, the exact parallel of the runner's
			-- post-present pass (ADR-0034): whatever `built.foreignContent` names is
			-- adopted now, and the per-node status is kept so a fixture can report it
			if built.foreignContent ~= nil then
				built.foreignApplied = foreignInstances.applyAll(built.handle.controller, built.foreignContent)
			end
		else
			local mod = require(examplesFolder:FindFirstChild(demo.module)) :: any
			built = mod.build(LuauUI, demoCore, {
				env = env,
				actionSystem = system,
				presenter = pres,
				adapter = adapter,
			})
			-- examples 1-4 hand back a screen to present; 5-7 present themselves
			if built.handle == nil and built.screen ~= nil then
				local presented = pres.present(built.screen, built.present)
				for _, value in built :: any do
					local bind = nativeScrollBinderOf(value)
					if bind ~= nil then
						bind(presented.controller)
					end
				end
				built.handle = presented
			end
		end
		-- DELIVER THE LOOPBACK SERVER'S RESPONSES.
		--
		-- THE HOST NO LONGER ANSWERS FOR THE PLAYER (example-quality-pass,
		-- 2026-08-06). This used to flush any `built.server.flush` every frame,
		-- because example 03's first change otherwise went pending and stayed
		-- pending. That fixed the symptom and destroyed the lesson: the pending
		-- state — the whole point of an optimistic-apply example — was answered
		-- before a player could ever see it, and the accept/reject/rollback path
		-- had no on-screen route at all.
		--
		-- Example 03 now owns delivery through a visible "Deliver server reply"
		-- button and exposes `server.deliver`, not `server.flush`, so it does not
		-- opt into this auto-answer. The hook stays, nil-guarded, for any FUTURE
		-- example whose transport really should answer promptly without a control.
		if built.server ~= nil and type(built.server.flush) == "function" then
			demoScope:own(RunService.Heartbeat:Connect(function()
				built.server.flush()
			end))
		end

		-- the picker calls `dispose` before it drops a demo; chain the example's
		-- own teardown (when it has one) ahead of the scope's
		local ownDispose = built.dispose
		built.dispose = function()
			if ownDispose ~= nil then
				pcall(ownDispose)
			end
			demoScope:dispose()
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
	pres.present(
		UI.Screen({
			id = "ShowcaseBackdrop",
			surface = "base",
			children = {
				UI.Spacer({
					id = "Fill",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
				}),
			},
		}),
		-- edgeToEdge: a backdrop that respects the safe area is a rectangle with
		-- the world showing around it (device capture, 2026-07-26)
		{ responder = "passive", rootPolicy = "edgeToEdge" }
	)

	-- THE CHROME: A STRIP THAT NEVER MOVES, AND A PANEL THAT COMES AND GOES.
	--
	-- The structural half lives in `showcase_chrome.luau`, where it can be
	-- required and driven headlessly — this file is a LocalScript and reaches
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
	-- real iPhone 15 Pro. What changed is that the open PANEL is its own surface,
	-- which is what lets the strip sit permanently underneath the demos.
	local showcasePicker: any = nil
	local demos: any = nil
	local settings: any = nil
	local chrome: any = nil

	demos = demo_picker.mount({
		LuauUI = LuauUI,
		core = core,
		env = env,
		presenter = pres,
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
		LuauUI = LuauUI,
		core = core,
		env = env,
		-- theme is a SETTING and lives in here now (CONCERNS 16); nil when no
		-- package replicated, which leaves settings with just its motion section
		themeSections = if showcasePicker ~= nil then showcasePicker.sections else nil,
		onChip = function()
			chrome.request("settings")
		end,
		-- stamped by tools/build_places.sh at build time; nil in a Rojo-served
		-- session, where the source on disk IS the running source and the
		-- question this answers cannot arise.
		buildStamp = workspace:GetAttribute("LuauUI_Build"),
	})

	chrome = showcase_chrome.mount({
		LuauUI = LuauUI,
		core = core,
		env = env,
		presenter = pres,
		actionSystem = system,
		demos = demos,
		settings = settings,
		coreTop = coreTopSignal,
		-- THE MEASUREMENT THAT REPLACED THE LITERAL (see reserveBar). Fed after the
		-- first solve and after every refresh, so a theme swap, an orientation
		-- change or a raised text preference re-reports the chip row's real bottom
		-- edge and the reserved strip follows it.
		onChipsBottom = function(bottom: number)
			if chipsBottom:get() ~= bottom then
				chipsBottom:set(bottom)
			end
		end,
		--[[ ...AND THE SAME ROW, DECLARED AS APP CHROME (director 2026-08-15, item 4).
			`coreSafeInsets.top` above is a bounding box and stays exactly as it was —
			every demo still starts below the chips, which is what a demo wants. This
			publishes the row's real RECT through `appChromeRects`, the env fact
			`platformChrome` merges alongside the PLATFORM's own cluster, so a surface
			that means to reserve per column (the screen-anchored HUD does) can sit
			LEVEL with the chips in the columns they do not cover instead of below them
			everywhere. Written only on change: it feeds a derived memo. ]]
		onChipsRect = function(rect: any)
			local declared = { { x = rect.x, y = rect.y, w = rect.w, h = rect.h } }
			local live = env:get("appChromeRects"):get()
			local was = if type(live) == "table" then (live :: any)[1] else nil
			if type(was) == "table" and was.x == rect.x and was.y == rect.y and was.w == rect.w and was.h == rect.h then
				return
			end
			env:set("appChromeRects", declared)
		end,
	})

	-- the strip is up; now mount the demo it advertises
	demos.show(demos.current())

	local showcaseHeartbeat = RunService.Heartbeat:Connect(function()
		-- re-assert the reservation before the solve: the platform adapter
		-- rewrites coreSafeInsets on orientation and topbar changes, and the
		-- write above is idempotent, so this simply keeps the strip reserved
		reserveBar()
		pres.refresh()
	end)
	-- A HANDLE FOR THE ROOM. The scenario runner already publishes its API this
	-- way (examples/gallery/scenarios/runner.luau) and for the same reason: the
	-- Studio MCP's execute_luau runs in a DIFFERENT Luau VM than this
	-- LocalScript, so `_G` does not cross but a BindableFunction in the shared
	-- DataModel does. It is what lets the demo be advanced without a pointer,
	-- which matters while the injected-input limitation (XP-B3) stands.
	_G.LuauUIShowcase = {
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

		MEASURED, 2026-08-15, showcase place: with `LuauUIScenarios.measured_extents`
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
	showcaseApi.Name = "LuauUIShowcaseAPI"
	for fnName, impl in
		{
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
				return HttpService:JSONEncode({ entries = ids, current = showcasePicker.selection:get() })
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
				return HttpService:JSONEncode({ ok = ok, current = showcasePicker.selection:get() })
			end,
			-- THE SAME CALL A CHIP PRESS AND THE TOGGLE KEY MAKE. Theme now lives
			-- inside settings (CONCERNS 16), so "open the themes" is "open the
			-- settings section" — one route, not a parallel one that can rot.
			toggleThemes = function(_arg: string?)
				chrome.request("settings")
				return HttpService:JSONEncode({ open = chrome.isOpen(), section = chrome.kind:get() })
			end,
			chrome = function(arg: string?)
				if arg == "demos" or arg == "settings" then
					chrome.request(arg)
				else
					chrome.request(nil)
				end
				return HttpService:JSONEncode({
					open = chrome.isOpen(),
					section = chrome.kind:get(),
					engaged = chrome.panelHandle() ~= nil and chrome.panelHandle().responder:get() or "none",
				})
			end,
			-- the reduced-motion axis of a device canary, reachable without a
			-- pointer and WITHOUT the one demo that used to own it being on screen
			motion = function(arg: string?)
				if arg == "full" or arg == "reduced" then
					settings.setMode(arg)
				end
				return HttpService:JSONEncode({
					motion = settings.mode:get(),
					setting = settings.setting:get(),
					reduced = env:get("reducedMotion"):get() == true,
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
	workspace:SetAttribute("LuauUI_GalleryReady", true)
	workspace:SetAttribute("LuauUI_ShowcaseReady", true)
	print(
		`[LuauUI Showcase] {LuauUI.VERSION} — {#demo_picker.list()} demos, theme picker {if showcasePicker ~= nil
			then "on"
			else "unavailable"}; chrome toggle: {showcase_chrome.TOGGLE_KEYBOARD} / {showcase_chrome.TOGGLE_GAMEPAD}`
	)
	local _keep = { showcaseHeartbeat, demos, showcasePicker, settings, chrome, unbindEnv, unbindResponderEffects }
	return
end

-- Verification-scenario selector (fable-execution-contract §5): set the
-- workspace STRING attribute LuauUI_Scenario to a registered scenario name
-- BEFORE running to mount that deterministic fixture instead of the demo.
-- The runner exposes _G.LuauUIScenario (list/steps/step/report/reset) for the
-- Studio MCP and stamps LuauUI_ScenarioReady/LuauUI_ScenarioState attributes.
local scenarioName = workspace:GetAttribute("LuauUI_Scenario")
if type(scenarioName) == "string" and scenarioName ~= "" then
	local registryModule = ReplicatedStorage:WaitForChild("LuauUIScenarios", 10)
	if registryModule ~= nil then
		local registry = require(registryModule) :: any
		local runner = require(registry.runner) :: any
		local scenarioHeartbeat = RunService.Heartbeat:Connect(function(dt: number)
			-- tick BEFORE refresh: presenter.tick advances time-based presenter
			-- state (toast clocks, the disclosure hover dwell — Step 8.5), and
			-- refresh then paints its outcome in the same frame. The scenario
			-- path used to refresh only, so a hover dwell could never elapse in
			-- a live scenario session while every headless case passed (found
			-- driving the disclosure plate in the device matrix, 2026-08-03).
			pres.tick(dt)
			pres.refresh()
		end)
		local api = runner.start({
			LuauUI = LuauUI,
			registry = registry,
			scenarioName = scenarioName,
			core = core,
			env = env,
			adapter = adapter,
			presenter = pres,
			actionSystem = system,
			unbindEnv = unbindEnv,
		})
		local _keep = { scenarioHeartbeat, api, unbindResponderEffects }
		return
	else
		warn("[LuauUI Scenario] LuauUIScenarios not present in ReplicatedStorage; falling through to demo")
	end
end

-- Tutorial example selector (§17 Phase 4 documentation deliverable): set the
-- workspace attribute LuauUI_Example to 1..7 BEFORE running to present that
-- gallery example instead of the default settings demo. The examples are the
-- exact engine-free modules the tutorial (docs/guide/04-tutorial-examples.md)
-- walks through — they run here as written.
-- only places that SET the attribute wait for the examples folder; the plain
-- settings-demo place must not stall on a folder it never mapped
local selectedExample = workspace:GetAttribute("LuauUI_Example")
local EXAMPLES = if selectedExample ~= nil
	then ReplicatedStorage:WaitForChild("LuauUIExamples", 10)
	else ReplicatedStorage:FindFirstChild("LuauUIExamples")
local EXAMPLE_MODULES = {
	"01_temperature_converter",
	"02_playlist_table",
	"03_settings_sync",
	"04_confirm_dialog",
	"05_word_game",
	"06_tile_game",
	"07_match3",
}
local selected = selectedExample
if type(selected) == "number" and EXAMPLE_MODULES[selected] ~= nil and EXAMPLES ~= nil then
	local exampleModule = EXAMPLES:FindFirstChild(EXAMPLE_MODULES[selected])
	if exampleModule ~= nil then
		local example = require(exampleModule) :: any
		local built = example.build(LuauUI, core, {
			env = env,
			actionSystem = system,
			presenter = pres,
			adapter = adapter,
		})
		-- two build styles (documented in docs/guide/04-tutorial-examples.md):
		-- examples 1-4 return { screen, present } for the caller to present;
		-- the game examples (5-7) present THEMSELVES and return { handle }
		if built.handle == nil and built.screen ~= nil then
			local presented = pres.present(built.screen, built.present)
			-- native-scroll consumer wiring (native-substrate NS-A3/NS-A4):
			-- controls riding the native canvas expose bindNativeScroll; the
			-- CONSUMER binds after present so engine CanvasPosition feeds
			-- their windowing/keep-visible mirror
			for _, value in built :: any do
				local bind = nativeScrollBinderOf(value)
				if bind ~= nil then
					bind(presented.controller)
				end
			end
			built.handle = presented
		end
		local exampleHeartbeat = RunService.Heartbeat:Connect(function()
			pres.refresh()
		end)
		-- COLLAPSED, because the picker is gallery chrome and the example is the
		-- subject (example-quality-pass, found live 2026-08-06). Expanded, its
		-- panel measured `x 339..899, y 8..219` on desktop and covered most of
		-- example 01's text field (`x 16..891, y 78..122`); on a 360x691 phone it
		-- covered the example entirely. It now docks as a chip in the top-right
		-- and opens on demand -- the same restyling reach, none of the occlusion.
		local examplePicker = mountThemePicker(true)
		workspace:SetAttribute("LuauUI_GalleryReady", true)
		workspace:SetAttribute("LuauUI_ExampleTitle", example.title)
		print(`[LuauUI Gallery] example {selected}: {example.title}`)
		local _keep = { exampleHeartbeat, unbindEnv, built, examplePicker }
		return
	end
end

-- semantic state: authoritative snapshot + draft + mutation (loopback server)
local snapshot = LuauUI.replication.snapshot(core, 1, { music = false, sfx = true })
local draftMusic = core:signal(false)
local saveStatus = core:signal("idle")
local mutation = LuauUI.replication.mutation(core, {
	optimistic = {
		apply = function(payload)
			draftMusic:set(payload.music)
		end,
		restore = function()
			draftMusic:set(snapshot.binding:get().music)
		end,
	},
})

-- hint text derives from the environment's preferred input (no remount:
-- it is a plain binding on an existing Text node — ADR-0004's phase-1 proof)
local hint = core:memo(function(use)
	local preferred = use(env:get("effectiveInput"))
	return if preferred == "Touch"
		then "Tap Save to apply"
		elseif preferred == "Gamepad" then "Press A to apply"
		else "Press Enter to apply"
end)

local statusLine = core:memo(function(use)
	return `music={tostring(use(draftMusic))} save={use(saveStatus)}`
end)

local screen = UI.Screen({
	id = "GallerySettings",
	padding = 16,
	gap = 8,
	children = {
		UI.Text({ id = "Title", text = "LuauUI Gallery — Settings", textSize = 24 }),
		UI.Text({ id = "Hint", text = hint, textSize = 14 }),
		UI.Toggle({ id = "Music", label = "Music", value = draftMusic }),
		UI.Text({ id = "Status", text = statusLine, textSize = 14 }),
		UI.Spacer({ id = "Gap", height = { type = "fill", weight = 1 } }),
		UI.Button({ id = "Save", label = "Save" }),
	},
})

local handle = pres.present(screen, {
	onActivate = function(path: string)
		if path == "/GallerySettings/Music" then
			draftMusic:set(not draftMusic:get())
		elseif path == "/GallerySettings/Save" then
			local envelope = mutation.send({ music = draftMusic:get() }, snapshot.revision())
			saveStatus:set("pending")
			-- loopback "server": validate + replicate + confirm next frame
			task.defer(function()
				snapshot.ingest(snapshot.revision() + 1, { music = envelope.payload.music, sfx = true })
				mutation.confirm(envelope.requestId, "ok")
				saveStatus:set("confirmed")
				mutation.reset()
			end)
		end
	end,
})

local picker = mountThemePicker()

-- frame-coalesced refresh (design §6.2: production coalesces to a frame)
local heartbeat = RunService.Heartbeat:Connect(function()
	pres.refresh()
end)

-- Studio verification checkpoints
workspace:SetAttribute("LuauUI_GalleryReady", true)
workspace:SetAttribute("LuauUI_Version", LuauUI.VERSION)
core:observe(pres.focus.focused, function(path)
	workspace:SetAttribute("LuauUI_Focused", path or "")
end)
workspace:SetAttribute("LuauUI_Focused", pres.focus.focused:get() or "")
core:observe(statusLine, function(line)
	workspace:SetAttribute("LuauUI_Status", line)
end)
workspace:SetAttribute("LuauUI_Status", statusLine:get())
core:observe(hint, function(text)
	workspace:SetAttribute("LuauUI_Hint", text)
end)
workspace:SetAttribute("LuauUI_Hint", hint:get())

-- factory-rerun counter for the no-remount proof: mounted total is stable
-- unless structure genuinely changes
task.defer(function()
	workspace:SetAttribute("LuauUI_FactoryRuns", handle.root.counters().factoryRuns)
end)

print(`[LuauUI Gallery] running {LuauUI.VERSION}; focus={pres.focus.focused:get()}`)

-- keep references alive for the session
local _keep = { unbindEnv, heartbeat, mutation, unbindResponderEffects, picker }
