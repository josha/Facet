--!strict
-- Facet PERFORMANCE LAB bootstrap (roadmap Step 9,
-- docs/plans/performance-stress-places.md; acceptance PL-1/PL-10/PL-13).
--
-- The engine half of the lab. It wires the same production path every other
-- Facet place uses — replicated source -> real adapter -> presenter -> the
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

--[[ THE MODULE-LOAD MEMORY MARKS (director's memory ask, wave T15).

	Facet's `require` graph is not free: measured headless, a `require` of the root
	retains ~2.76 MB of Lua heap, of which the four DEFERRED composites are 228 KB
	[131..313] and all nineteen would be 860 KB [762..860]
	(artifacts/release-candidate-review/perf/requalification.md §7 — an earlier
	draft of this comment said 831 KB, which was subset arithmetic and is
	retracted). Headless is
	the wrong host to make that claim on, though — it has no engine, no
	ModuleScript instances and a different collector — so the number a decision
	should rest on is the one this place reads on the CLIENT.

	Three marks, and the first one has to be taken HERE, above the requires: once
	`require(Facet)` has run there is no way back to a before. `collectgarbage`
	accepts "count" on the Roblox VM and returns kilobytes of Lua heap; it is the
	same quantity `Stats` reports as LuaHeap, read without a service round trip.

	THE THIRD MARK IS THE LAB'S, not this file's — it is taken after the first
	workload mounts, because "what does requiring Facet cost" and "what does the
	first surface cost on top of it" are different questions and a single number
	answers neither. ]]
local heapBeforeRequireKb = collectgarbage("count")

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Facet = require(ReplicatedStorage:WaitForChild("Facet")) :: any
local screen_target = require(ReplicatedStorage.Facet.client.screen_target) :: any
local roblox_env = require(ReplicatedStorage.Facet.client.roblox_env) :: any
local roblox_input = require(ReplicatedStorage.Facet.client.roblox_input) :: any
local motion_driver = require(ReplicatedStorage.Facet.client.motion_driver) :: any
local gamepad_contention = require(ReplicatedStorage.Facet.client.gamepad_contention) :: any
-- INTERNAL REACH, DECLARED. `src/core/profile` is not a blessed client entry
-- point; the lab reaches it through the named exemption in
-- tools/lune/check_boundary.luau so the scenario driver's scopes and the
-- framework's phases are literally the same wrapper (PLN-2).
local profile = require(ReplicatedStorage.Facet.core.profile) :: any

local native_list = require(script:WaitForChild("native_list")) :: any
--[[ THE OPT-IN HAPTICS ADAPTER (task 11), handed to the lab through `ctx.lab` for
	`select:haptics=on`. It is required HERE, with the other client entry points,
	rather than inside `lab/init.luau`: that file is the scenario REGISTRY and its
	module list is asserted against the built place by `tools/check_perf_place.py`,
	and the adapter is not one of its modules — it is the framework's own client
	adapter living in the replicated Facet tree. pcall'd, because a place built
	without it must still open with the setting simply unavailable. ]]
local hapticsModule: any = (function(): any
	local ok, mod = pcall(function(): any
		return require(ReplicatedStorage.Facet.client.haptics)
	end)
	return if ok then mod else nil
end)()

-- THE LAB TURNS THE SCOPES ON. They ship OFF (src/core/profile.luau): a framework that
-- pcall-wraps every phase in production to instrument a session nobody is reading has
-- the default backwards. This place exists to read them, so it opts in explicitly, and
-- every capture row records `profilerScopes` so a number taken with the annotation
-- overhead is never compared against one taken without it.
profile.setEnabled(true)

local core = Facet.newCore()
local env = Facet.newEnvironment(core)
local unbindEnv = roblox_env.bind(env)
-- THE LAB OPTS OUT ON PURPOSE, and after the 2026-08-21 default flip (ADR-0040
-- B-15) that `false` is doing real work rather than restating the default. Every
-- budget (bench/perf_budgets.json) and capture
-- (artifacts/performance-stress-places/) was measured with the adapter as the
-- only writer of every paint property; taking the sheet path here would move the
-- instance counts and the paint timings under numbers recorded against the other
-- painter, so the lab keeps the explicit-write arm until a re-baseline says
-- otherwise. `Facet_NativeStyle = true` still A/Bs it (the place file ships the
-- attribute set to `false` so the opt-out is visible in Studio, not implied).
local adapter = screen_target.new({
	-- the distance the lab is watched from: the paint family scales at ten-foot
	-- and a target takes its class at construction. Near is the IDENTITY, so every
	-- budget in bench/perf_budgets.json was measured at the value this now states.
	displaySize = env:get("displaySize"):get(),
	nativeStyle = workspace:GetAttribute("Facet_NativeStyle") == true and { transitions = false } or false,
})
local system = roblox_input.newSystem(core)
local pres = Facet.newPresenter(core, env, adapter, system)
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

local heapAfterRequireKb = collectgarbage("count")

local host = {
	profile = profile,
	nativeList = native_list,

	-- the Lua heap, live, so the lab can take its own third mark after the first
	-- workload mounts without knowing how this VM spells it
	heapKb = function(): number
		return collectgarbage("count")
	end,

	--[[ What requiring Facet cost THIS client, in kilobytes of Lua heap. Both marks
		come from this file because only this file has a "before" — and both are
		reported rather than only their difference, so a reader can tell a small
		delta on a loaded heap from a small delta on an empty one. ]]
	heapMarks = function(): any
		return {
			measured = true,
			beforeRequireKb = heapBeforeRequireKb,
			afterRequireKb = heapAfterRequireKb,
			requireCostKb = heapAfterRequireKb - heapBeforeRequireKb,
		}
	end,

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
			sourceStamp = tostring(workspace:GetAttribute("Facet_SourceStamp") or "unstamped"),
			placeName = tostring(workspace:GetAttribute("Facet_PerfLabPlace") or "Facet-PerformanceLab"),
			viewport = `{math.floor(viewport.X)}x{math.floor(viewport.Y)}`,
			orientation = if viewport.X >= viewport.Y then "landscape" else "portrait",
			graphicsQualityLevel = tostring(quality),
			-- THE FRAME TARGET IS NOT READABLE FROM A LOCALSCRIPT, so it is DECLARED,
			-- not guessed. It used to default to "uncapped/unknown", which the tightened
			-- admissibility rule correctly refuses — a non-answer dressed as a value
			-- (phase-gate review F-7). "not recorded" is the honest default: an explicit
			-- statement that nobody set it. The operator sets
			-- `workspace.Facet_PerfFrameTarget` on the device, where it actually
			-- matters; the measured cadence is separately available in the capture's
			-- `frame.heartbeatInterval`.
			frameTarget = tostring(workspace:GetAttribute("Facet_PerfFrameTarget") or "not recorded"),
			studioVersion = tostring(studioVersion),
			deviceLabel = if RunService:IsStudio()
				then `Studio host · touch={tostring(UserInputService.TouchEnabled)}`
				else "retail client",
			thermalNote = tostring(workspace:GetAttribute("Facet_PerfThermalNote") or "not recorded"),
			-- device-class fields stay nil in Studio ON PURPOSE: a Studio row that
			-- carried them would look admissible as a device row
			deviceModel = nil,
			osVersion = nil,
			clientVersion = nil,
			powerState = nil,
			capturePath = tostring(workspace:GetAttribute("Facet_PerfCapturePath") or "not captured in this run"),
			summaryPath = tostring(workspace:GetAttribute("Facet_PerfSummaryPath") or "not derived in this run"),
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
local registry = require(ReplicatedStorage:WaitForChild("FacetScenarios")) :: any
local runner = require(registry.runner) :: any

-- ONE frame scope around the lab's own driving. `Facet/scenario` is a declared
-- phase, so the capture shows the driver's per-frame share beside the framework's
-- — which is what stops "the lab is slow" from being mistaken for "Facet is slow".
--[[ THE TICK IS NOT DRIVEN HERE — `motion_driver.bind(pres)` above already does
	it, on PreRender, which is where it belongs (Heartbeat runs AFTER render, so
	ticking there adds a frame of latency to every visual the tick drives).

	IT USED TO BE DRIVEN IN BOTH PLACES, and the first physical-device capture is
	what made that visible (game director, 2026-08-13, Galaxy A10e). The dump
	showed `Facet/present` and `Facet/tick` each occurring SIXTY times across
	thirty frames — twice per frame — with `Facet/scenario` wrapping exactly one
	of each pair. Measured cost of the duplication on that device: 0.072 ms/frame
	of duplicate tick plus 0.208 ms/frame of duplicate present+focusmap, i.e.
	0.279 ms/frame, which was 45% of ALL Facet time in the capture.

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
	Facet = Facet,
	registry = registry,
	scenarioName = "perf_lab",
	core = core,
	env = env,
	adapter = adapter,
	presenter = pres,
	actionSystem = system,
	unbindEnv = unbindEnv,
	host = host,
	lab = (function(): any
		local supplied = table.clone(registry.lab)
		supplied.haptics = hapticsModule
		return supplied
	end)(),
})

workspace:SetAttribute("Facet_PerfLabReady", true)
workspace:SetAttribute("Facet_Version", Facet.VERSION)
print(
	`[Facet PerfLab] {Facet.VERSION} ready — scopes engine={tostring(profile.available())}; `
		.. `drive via workspace.FacetScenarioAPI (list/steps/step/report/reset)`
)

local _keep = { heartbeat, api, unbindEnv, Players.LocalPlayer }
