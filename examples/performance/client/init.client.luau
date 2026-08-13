--!strict
-- LuauUI PERFORMANCE LAB bootstrap (roadmap Step 9,
-- docs/plans/performance-stress-places.md; acceptance PL-1/PL-10/PL-13).
--
-- The engine half of the lab. It wires the same production path every other
-- LuauUI place uses — replicated source -> real adapter -> presenter -> the
-- gallery's scenario runner — and adds exactly three things the lab needs and no
-- other place does:
--
--   1. the HOST SEAMS (`deps.host`): the raw-Roblox reference list, the
--      environment facts a capture must record, a content preload, and the
--      framework's own profiler wrapper, so driver scopes and framework scopes
--      come from one implementation;
--   2. the LAB MODULES (`deps.lab`): the engine-free dataset/row/capture/overlay
--      modules, handed in so `perf_lab` never touches `script`;
--   3. a MicroProfiler-visible frame scope around the presenter tick, so a
--      capture can see the lab's own driving separately from the framework's
--      phases.
--
-- IT PUBLISHES NOTHING TO PLAYERS. This is a development place; there is no
-- game, no character, and no player-facing surface.

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LuauUI = require(ReplicatedStorage:WaitForChild("LuauUI")) :: any
local screen_target = require(ReplicatedStorage.LuauUI.client.screen_target) :: any
local roblox_env = require(ReplicatedStorage.LuauUI.client.roblox_env) :: any
local roblox_input = require(ReplicatedStorage.LuauUI.client.roblox_input) :: any
local motion_driver = require(ReplicatedStorage.LuauUI.client.motion_driver) :: any
local gamepad_contention = require(ReplicatedStorage.LuauUI.client.gamepad_contention) :: any
-- INTERNAL REACH, DECLARED. `src/core/profile` is not a blessed client entry
-- point; the lab reaches it through the named exemption in
-- tools/lune/check_boundary.luau so the scenario driver's scopes and the
-- framework's phases are literally the same wrapper (PLN-2).
local profile = require(ReplicatedStorage.LuauUI.core.profile) :: any

local native_list = require(script:WaitForChild("native_list")) :: any

-- THE LAB TURNS THE SCOPES ON. They ship OFF (src/core/profile.luau): a framework that
-- pcall-wraps every phase in production to instrument a session nobody is reading has
-- the default backwards. This place exists to read them, so it opts in explicitly, and
-- every capture row records `profilerScopes` so a number taken with the annotation
-- overhead is never compared against one taken without it.
profile.setEnabled(true)

local core = LuauUI.newCore()
local env = LuauUI.newEnvironment(core)
local unbindEnv = roblox_env.bind(env)
local adapter = screen_target.new({
	nativeStyle = workspace:GetAttribute("LuauUI_NativeStyle") == true and { transitions = false } or false,
})
local system = roblox_input.newSystem(core)
local pres = LuauUI.newPresenter(core, env, adapter, system)
motion_driver.bind(pres)

-- UI-only place: free ButtonA and the Tab key exactly as the gallery does, for
-- the same reason and with the same scope limit (docs/guide/07-input.md §7.3/§7.4).
task.defer(function()
	gamepad_contention.disableLegacyControls()
	pcall(function()
		game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)
end)

-- ---- host seams -----------------------------------------------------------
-- Everything engine-shaped the lab needs and the gallery runner has no business
-- knowing about. Handed to `runner.start` as `deps.host` and surfaced to the
-- scenario as `ctx.host`.
local function isoNow(): string
	-- os.date is available on the client; the capture needs a wall-clock stamp so
	-- two runs of the same workload can be ordered, and "unknown" would make the
	-- row inadmissible by design
	local ok, stamp = pcall(function()
		return os.date("!%Y-%m-%dT%H:%M:%SZ")
	end)
	return if ok then tostring(stamp) else "unknown"
end

local host = {
	profile = profile,
	nativeList = native_list,

	-- Preload the deterministic image set so the WARM pass measures steady-state
	-- framework cost rather than network and decode. Returns how many contents
	-- were actually asked for, which is what the capture records — a preload that
	-- silently did nothing would turn the cold/warm split into noise.
	preload = function(keys: { string }): number
		local contents: { any } = {}
		for _, key in keys do
			local image = Instance.new("ImageLabel")
			image.Image = key
			table.insert(contents, image)
		end
		local ok = pcall(function()
			ContentProvider:PreloadAsync(contents)
		end)
		for _, image in contents do
			image:Destroy()
		end
		return if ok then #contents else 0
	end,

	-- The CONDITIONS half of every capture row (PL-9). Recorded from the live
	-- session rather than typed into an artifact by hand, because a hand-typed
	-- condition is the one that goes stale first.
	facts = function(): any
		local camera = workspace.CurrentCamera
		local viewport = if camera ~= nil then camera.ViewportSize else Vector2.new(0, 0)
		-- GRAPHICS QUALITY, read the way a CLIENT can read it. `settings()` is a
		-- plugin/Studio global and is nil in a LocalScript, so the first attempt
		-- returned "unknown" — and the capture checker correctly refused the row,
		-- which is how this was found rather than shipped. `UserGameSettings` is the
		-- player-visible setting and is readable from the client; `SavedQualityLevel`
		-- is what the player chose (Automatic reports as such) and `QualityLevel` is
		-- what is actually in force.
		local quality: any = "unknown"
		pcall(function()
			local gs = UserSettings():GetService("UserGameSettings")
			quality = tostring(gs.SavedQualityLevel)
		end)
		local studioVersion: any = "n/a"
		if RunService:IsStudio() then
			pcall(function()
				studioVersion = version()
			end)
		end
		return {
			-- THE CLASS IS DECIDED BY THE HOST, NOT BY THE OPERATOR. A Studio
			-- session cannot produce a device row by being labelled one, and this
			-- is the only place the label is minted.
			evidenceClass = if RunService:IsStudio() then "studio" else "desktop-retail",
			capturedAtIso = isoNow(),
			sourceStamp = tostring(workspace:GetAttribute("LuauUI_SourceStamp") or "unstamped"),
			placeName = tostring(workspace:GetAttribute("LuauUI_PerfLabPlace") or "LuauUI-PerformanceLab"),
			viewport = `{math.floor(viewport.X)}x{math.floor(viewport.Y)}`,
			orientation = if viewport.X >= viewport.Y then "landscape" else "portrait",
			graphicsQualityLevel = tostring(quality),
			-- THE FRAME TARGET IS NOT READABLE FROM A LOCALSCRIPT, so it is DECLARED,
			-- not guessed. It used to default to "uncapped/unknown", which the tightened
			-- admissibility rule correctly refuses — a non-answer dressed as a value
			-- (phase-gate review F-7). "not recorded" is the honest default: an explicit
			-- statement that nobody set it. The operator sets
			-- `workspace.LuauUI_PerfFrameTarget` on the device, where it actually
			-- matters; the measured cadence is separately available in the capture's
			-- `frame.heartbeatInterval`.
			frameTarget = tostring(workspace:GetAttribute("LuauUI_PerfFrameTarget") or "not recorded"),
			studioVersion = tostring(studioVersion),
			deviceLabel = if RunService:IsStudio()
				then `Studio host · touch={tostring(UserInputService.TouchEnabled)}`
				else "retail client",
			thermalNote = tostring(workspace:GetAttribute("LuauUI_PerfThermalNote") or "not recorded"),
			-- device-class fields stay nil in Studio ON PURPOSE: a Studio row that
			-- carried them would look admissible as a device row
			deviceModel = nil,
			osVersion = nil,
			clientVersion = nil,
			powerState = nil,
			capturePath = tostring(workspace:GetAttribute("LuauUI_PerfCapturePath") or "not captured in this run"),
			summaryPath = tostring(workspace:GetAttribute("LuauUI_PerfSummaryPath") or "not derived in this run"),
		}
	end,

	-- MicroProfiler control, so a capture window can be started and stopped from
	-- the same driver that runs the workload. Feature-detected: LibMP is reachable
	-- from Studio MCP / the command bar, not from an ordinary LocalScript, so this
	-- reports honestly rather than pretending.
	profilerControl = function(): any
		local ok, LibMP = pcall(function()
			return require("@rbx/LibMP" :: any) :: any
		end)
		if not ok or LibMP == nil then
			return {
				available = false,
				reason = "LibMP is not requirable from this VM; drive it from Studio MCP execute_luau or the "
					.. "command bar (see docs/guide/09-performance-lab.md)",
			}
		end
		return { available = true, LibMP = LibMP }
	end,
}

-- ---- the scenario surface --------------------------------------------------
local registry = require(ReplicatedStorage:WaitForChild("LuauUIScenarios")) :: any
local runner = require(registry.runner) :: any

-- ONE frame scope around the lab's own driving. `LuauUI/scenario` is a declared
-- phase, so the capture shows the driver's per-frame share beside the framework's
-- — which is what stops "the lab is slow" from being mistaken for "LuauUI is slow".
--[[ THE TICK IS NOT DRIVEN HERE — `motion_driver.bind(pres)` above already does
	it, on PreRender, which is where it belongs (Heartbeat runs AFTER render, so
	ticking there adds a frame of latency to every visual the tick drives).

	IT USED TO BE DRIVEN IN BOTH PLACES, and the first physical-device capture is
	what made that visible (game director, 2026-08-13, Galaxy A10e). The dump
	showed `LuauUI/present` and `LuauUI/tick` each occurring SIXTY times across
	thirty frames — twice per frame — with `LuauUI/scenario` wrapping exactly one
	of each pair. Measured cost of the duplication on that device: 0.072 ms/frame
	of duplicate tick plus 0.208 ms/frame of duplicate present+focusmap, i.e.
	0.279 ms/frame, which was 45% of ALL LuauUI time in the capture.

	`motion_driver`'s own header already called this out — "a second bind of the
	same presenter is a mistake the double-tick would make visible, so it is
	rejected loudly" — but its guard only refuses a second BIND. A bind plus a
	hand-rolled `tick` on another signal walks straight past it, which is what
	happened here. Recorded rather than only fixed, because the guard's shape is
	the reusable finding: a rule that polices one spelling does not police the
	behaviour.

	NOTE FOR THE NEXT CAPTURE: `present` was ALSO occurring twice per frame, and
	only one of those is the `refresh` below. The second has not been traced to
	its call site and is NOT claimed fixed by this change — re-read the scope
	counts on the next device dump and see whether `present` is 30 or 60. ]]
local heartbeat = RunService.Heartbeat:Connect(function(_dt: number)
	profile.span("scenario", function()
		pres.refresh()
	end)
end)

local api = runner.start({
	LuauUI = LuauUI,
	registry = registry,
	scenarioName = "perf_lab",
	core = core,
	env = env,
	adapter = adapter,
	presenter = pres,
	actionSystem = system,
	unbindEnv = unbindEnv,
	host = host,
	lab = registry.lab,
})

workspace:SetAttribute("LuauUI_PerfLabReady", true)
workspace:SetAttribute("LuauUI_Version", LuauUI.VERSION)
print(
	`[LuauUI PerfLab] {LuauUI.VERSION} ready — scopes engine={tostring(profile.available())}; `
		.. `drive via workspace.LuauUIScenarioAPI (list/steps/step/report/reset)`
)

local _keep = { heartbeat, api, unbindEnv, Players.LocalPlayer }
