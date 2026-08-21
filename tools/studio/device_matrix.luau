--!nocheck
-- THE REUSABLE STUDIO DEVICE-MATRIX DRIVER
-- (docs/plans/studio-device-verification.md "Required automation loop";
--  docs/plans/agent-execution-contract.md §5; roadmap Step 4, rows XP-B1..B7)
--
-- HOW IT RUNS. The file is checked in here and INSTALLED into the open place
-- as a transient `workspace.FacetMatrixDriver` ModuleScript, fetched verbatim
-- from `tools/lune/studio_sync`'s /driver route (so the running copy cannot
-- drift from the repository copy). It is deliberately NOT part of the sync
-- manifest and not in `src/`: the plan puts this driver in development tooling,
-- not in Facet runtime code or a shipped example. `tools/studio/install_matrix_driver`
-- creates it; the driver's `reset` mode removes it again.
--
--   local run = require(workspace.FacetMatrixDriver)
--   return run({ mode = "select", row = "console-ten-foot" })
--
-- WHAT IT IS NOT. It is not a test oracle and it is not an input synthesizer.
-- It sets up device state, reads the shared scenario surface, and reports what
-- it saw — including, loudly, what it could not see. Native input rows still
-- need a real injected event; this driver arms the observation, hands back the
-- LIVE geometry to aim at, and then reads the effect back.
--
-- MODES (args.mode):
--   catalog    enumerate the live device catalog, normalized
--   preflight  the execution contract §4 preflight, as data
--   select     resolve + select the device for one matrix row and validate it
--   observe    read the row's evidence from the shared scenario surface
--   row        select + observe + measure, composed into one stamped record
--   input      drive native input through VirtualInput at live geometry and pair
--              the raw event with the visible effect
--   keyboard   drive a SEQUENCE of raw key presses (args.keys) through
--              VirtualInput and pair each with the semantic action it produced
--   step       run one scenario step (name in args.step, payload in args.payload)
--   reset      stop device simulation and restore the session
--
-- Each mode returns a JSON string. One row = several calls, because
-- SetDeviceAsync yields and a single call that did everything would be a
-- timeout waiting to happen.

local HttpService = game:GetService("HttpService")

-- `ARGS` is per-invocation; the module returns a function, so a require cache
-- cannot freeze one row's arguments into every later call.
local ARGS: any = {}

local function json(v: any): string
	return HttpService:JSONEncode(v)
end

-- Probing a member that does not exist on a Roblox instance THROWS; it does not
-- return nil. So every capability probe goes through here — and it is
-- TRI-STATE, because a boolean cannot tell the two failures apart:
--
--   "X is not a valid member of Y"       -> the name is WRONG
--   "lacking capability PluginSecurity"  -> the name is right, we are not allowed
--
-- The first version returned a boolean and this driver published two false
-- platform facts on the strength of it: that `VirtualInput` exposes no Send
-- methods (it does — the probe used four invented names) and that
-- `StudioDeviceSimulatorService` has no stop member (it has
-- `StopSimulationAsync`). Both were wrong-NAME errors reported as security
-- refusals. The raw error text is kept so the same mistake announces itself.
local function probeMethod(instance: any, member: string): any
	local ok, value = pcall(function()
		return (instance :: any)[member]
	end)
	if ok then
		return { state = if type(value) == "function" then "present" else "notAFunction", type = typeof(value) }
	end
	local err = tostring(value)
	local state = if string.find(err, "is not a valid member", 1, true) ~= nil
		then "absent"
		elseif string.find(err, "lacking capability", 1, true) ~= nil then "blocked"
		else "error"
	return { state = state, error = err }
end

local function hasMethod(instance: any, member: string): boolean
	return probeMethod(instance, member).state == "present"
end

-- The documented VirtualInput surface (create.roblox.com/docs/reference/engine/
-- classes/VirtualInput). These are the real names; the driver previously probed
-- four that exist under no security level and concluded the class was unusable.
local VIRTUAL_INPUT_METHODS =
	{ "SendKey", "SendMouseButton", "SendMouseDelta", "SendMousePosition", "SendPointerAction", "SendTextInput" }

local function serviceOrNil(name: string): any
	local ok, svc = pcall(function()
		return game:GetService(name)
	end)
	return if ok then svc else nil
end

-- the selection POLICY is the pure module the headless suite pins; requiring it
-- from the running place is what keeps one policy rather than two that agree
-- until they do not
local function matrixRows(): any
	local ok, mod = pcall(function()
		return require(game:GetService("ReplicatedStorage").Facet.preview.matrix_rows) :: any
	end)
	return if ok then mod else nil
end

-- VirtualInput, probed with its DOCUMENTED names and reported tri-state. The
-- one real documented constraint is that its methods error if the simulated
-- input would interact with Roblox's built-in UI (CoreGui) — that is a per-CALL
-- failure, not a per-class capability, so it is recorded when it happens rather
-- than assumed up front.
-- ONE VirtualInput for the driver's lifetime. Creating a fresh one per probe
-- looked harmless and was not: the preflight's instance reported all six methods
-- present, and an instance created moments later in another mode reported the
-- same methods absent and delivered no events. Whatever the engine's ownership
-- rule is, a second live instance is not equivalent to the first — so the driver
-- creates one, caches it, and every mode uses that one.
local cachedVirtualInput: any = nil
local function virtualInputProbe(): any
	local uis = game:GetService("UserInputService")
	local okCreate, virtual = true, cachedVirtualInput
	if virtual == nil then
		okCreate, virtual = pcall(function()
			return (uis :: any):CreateVirtualInput()
		end)
		if okCreate and virtual ~= nil then
			cachedVirtualInput = virtual
		end
	end
	if not okCreate or virtual == nil then
		return { available = false, usable = false, reason = tostring(virtual) }
	end
	local methods: { [string]: any } = {}
	local usable = true
	for _, m in VIRTUAL_INPUT_METHODS do
		local probe = probeMethod(virtual, m)
		methods[m] = probe
		if probe.state ~= "present" then
			usable = false
		end
	end
	return {
		available = true,
		usable = usable,
		methods = methods,
		instance = virtual,
		note = "VirtualInput methods error when the simulated input would interact with CoreGui; that is a "
			.. "per-call failure and is recorded on the call, not assumed as a capability",
	}
end

-- the shared scenario surface, reached through the BindableFunctions the runner
-- publishes (the MCP command VM is a different Luau VM, so _G does not cross)
local function scenarioApi(): any
	local folder = workspace:FindFirstChild("FacetScenarioAPI")
	if folder == nil then
		return nil
	end
	local api = {}
	for _, bf in folder:GetChildren() do
		if bf:IsA("BindableFunction") then
			local name = bf.Name
			api[name] = function(arg: any)
				return bf:Invoke(arg)
			end
		end
	end
	return api
end

-- Enum values and Vector2s do not survive JSONEncode; the live getters return
-- both. Flatten them at the edge rather than losing them.
local function serializeAny(v: any): any
	local t = typeof(v)
	if t == "EnumItem" then
		return tostring(v)
	elseif t == "Vector2" then
		return { w = v.X, h = v.Y }
	end
	return v
end

local function decode(s: any): any
	if type(s) ~= "string" then
		return s
	end
	local ok, v = pcall(function()
		return HttpService:JSONDecode(s)
	end)
	return if ok then v else s
end

-- ===========================================================================
-- catalog: normalize GetDeviceInfoAsync into the shape matrix_rows expects
-- ===========================================================================
local function catalog(): any
	local svc = serviceOrNil("StudioDeviceSimulatorService")
	if svc == nil then
		return { ok = false, reason = "StudioDeviceSimulatorService unavailable at this security level" }
	end
	local okList, list = pcall(function()
		return svc:GetDeviceListAsync()
	end)
	if not okList then
		return { ok = false, reason = "GetDeviceListAsync failed: " .. tostring(list) }
	end
	local entries = {}
	for _, id in ipairs(list) do
		local ok, info = pcall(function()
			return svc:GetDeviceInfoAsync(id)
		end)
		if ok and type(info) == "table" then
			table.insert(entries, {
				id = tostring(info.DeviceId or id),
				name = tostring(info.Name),
				-- the ENUM NAME, so the pure policy stays engine-free
				form = (tostring(info.DeviceForm):gsub("Enum%.DeviceForm%.", "")),
				w = info.Width,
				h = info.Height,
				scale = info.ResolutionScale,
				dpi = info.PixelDensity,
				isCustom = info.IsCustom,
				portraitKeyboardHeight = info.PortraitKeyboardHeight,
				landscapeKeyboardHeight = info.LandscapeKeyboardHeight,
			})
		end
	end
	return { ok = true, count = #entries, entries = entries }
end

-- ===========================================================================
-- preflight: prove the instrument works BEFORE trusting anything it says
-- (execution contract §4). Every item is data, not a print: a row's stored
-- evidence has to be able to show the instrument was healthy when it ran.
-- ===========================================================================
local function preflight(): any
	local out: any = { ok = true, problems = {} }
	local function problem(s: string)
		out.ok = false
		table.insert(out.problems, s)
	end

	out.studioVersion = tostring(version())
	out.placeId = game.PlaceId
	out.runMode = if game:GetService("RunService"):IsRunning() then "running" else "edit"

	-- 3. the viewport is not the 1x1 blind instrument
	local cam = workspace.CurrentCamera
	out.viewport = if cam then { w = cam.ViewportSize.X, h = cam.ViewportSize.Y } else nil
	if out.viewport == nil or out.viewport.w <= 1 or out.viewport.h <= 1 then
		problem("CurrentCamera.ViewportSize is 1x1 or absent — the instrument is blind (see docs/lessons)")
	end

	-- 2. the running place carries the source state just built
	out.sourceStamp = workspace:GetAttribute("Facet_SourceStamp")
	out.version = workspace:GetAttribute("Facet_Version")
	if ARGS.expectStamp ~= nil and out.sourceStamp ~= ARGS.expectStamp then
		problem(
			`source stamp is '{tostring(out.sourceStamp)}' but this run was built from '{tostring(ARGS.expectStamp)}' `
				.. "— the place is stale; do not diagnose the framework from it"
		)
	end

	-- 5. the expected Facet target and presenter mounted exactly once
	local lp = game:GetService("Players").LocalPlayer
	local screenGuis = {}
	if lp ~= nil and lp:FindFirstChild("PlayerGui") ~= nil then
		for _, gui in lp.PlayerGui:GetChildren() do
			if gui:IsA("ScreenGui") then
				table.insert(screenGuis, gui.Name)
			end
		end
	end
	out.screenGuis = screenGuis
	out.scenario = workspace:GetAttribute("Facet_Scenario")
	out.scenarioReady = workspace:GetAttribute("Facet_ScenarioReady")
	out.scenarioState = workspace:GetAttribute("Facet_ScenarioState")
	if out.scenarioReady ~= true then
		problem(`the scenario surface is not ready (state '{tostring(out.scenarioState)}')`)
	end
	local api = scenarioApi()
	out.scenarioApi = api ~= nil
	if api == nil then
		problem("workspace.FacetScenarioAPI is absent — there is nothing to drive")
	end

	-- 1. the device simulator's actual configuration, recorded
	local svc = serviceOrNil("StudioDeviceSimulatorService")
	out.deviceSimulator = { available = svc ~= nil, members = {} }
	if svc ~= nil then
		for _, member in
			{
				"SetDeviceAsync",
				"SetOrientationAsync",
				"SetResolutionAsync",
				"SetScalingModeAsync",
				"StopSimulationAsync",
				"GetDeviceAsync",
				"GetResolutionAsync",
				"GetScalingModeAsync",
				"GetOrientationAsync",
				"GetPixelDensityAsync",
			}
		do
			out.deviceSimulator.members[member] = probeMethod(svc, member)
		end
	end

	-- VirtualInput: probed with its DOCUMENTED member names, never assumed.
	out.virtualInput = virtualInputProbe()

	-- 4. mark the log boundary so new warnings belong to this run
	out.logBoundary = `Facet matrix boundary {os.clock()}`
	print(out.logBoundary)

	return out
end

-- ===========================================================================
-- select: resolve the row through the PURE policy, then apply and validate
-- ===========================================================================
local function selectRow(): any
	local rows = matrixRows()
	if rows == nil then
		return { ok = false, reason = "ReplicatedStorage.Facet.preview.matrix_rows is absent — sync the place" }
	end
	local svc = serviceOrNil("StudioDeviceSimulatorService")
	if svc == nil then
		return { ok = false, reason = "StudioDeviceSimulatorService unavailable" }
	end

	local cat = catalog()
	if not cat.ok then
		return cat
	end

	local pinned: any = nil
	if ARGS.pinnedDeviceId ~= nil then
		for _, e in cat.entries do
			if e.id == ARGS.pinnedDeviceId then
				pinned = e
			end
		end
	end

	local resolution = rows.resolve(cat.entries, ARGS.row, pinned)
	local attempts = {}
	-- probed through the SAME cached, documented-name probe every other mode
	-- uses. This line is why the first correction did not take: the preflight
	-- was fixed and this one was not, so every row kept publishing "VirtualInput
	-- is not usable here" from an invented member name while the artifact one
	-- directory away said all six methods were present. Fixing the producer and
	-- missing the consumer is the failure mode; one probe, one cache, one answer.
	local vi = virtualInputProbe()

	for _, candidate in resolution.candidates do
		local entry = candidate.entry
		local attempt: any = { deviceId = entry.id, why = candidate.why }

		-- CONNECT BEFORE THE SETTERS. Roblox documents ConfigurationChanged as
		-- firing on exactly the calls below, so a connection opened after them
		-- observes a window in which nothing changes and reports `false` — five
		-- rows once published that guaranteed false negative. Same shape as the
		-- wrong-name probes, expressed as timing.
		local configChanged = false
		local conn: RBXScriptConnection? = nil
		local okSignal = pcall(function()
			conn = (svc :: any).ConfigurationChanged:Connect(function()
				configChanged = true
			end)
		end)

		local okSet, setErr = pcall(function()
			svc:SetDeviceAsync(entry.id)
		end)
		attempt.selected = okSet
		if not okSet then
			attempt.error = tostring(setErr)
			if conn ~= nil then
				conn:Disconnect()
			end
			table.insert(attempts, attempt)
			continue
		end

		local orientation = resolution.row.orientation
		if orientation ~= "Default" then
			local okOrient, orientErr = pcall(function()
				svc:SetOrientationAsync(Enum.ScreenOrientation[orientation])
			end)
			attempt.orientation = { requested = orientation, applied = okOrient }
			if not okOrient then
				attempt.orientation.error = tostring(orientErr)
			end
		else
			attempt.orientation = { requested = "Default", applied = true }
		end

		-- SCALING MODE decides whether the emulated viewport is the resolution you
		-- asked for. `ActualResolution` renders at exact pixel resolution;
		-- `FitToWindow` scales to fill the pane, which is why a request for
		-- 1280x720 came back as 1280x719 and was misfiled as "the emulator
		-- reports a fitted viewport". Set it explicitly, and RECORD it, so a row
		-- never has to be explained by an unstated mode.
		-- AFTER SetDeviceAsync, never before: SetScalingModeAsync errors with
		-- "no device is active" when no preset is selected (measured after a
		-- StopSimulationAsync). The setter order in this loop is deliberate.
		if hasMethod(svc, "SetScalingModeAsync") then
			local okScale, scaleErr = pcall(function()
				svc:SetScalingModeAsync(Enum.DeviceSimulatorScalingMode.ActualResolution)
			end)
			attempt.scalingMode = { requested = "ActualResolution", applied = okScale }
			if not okScale then
				attempt.scalingMode.error = tostring(scaleErr)
			end
		end

		-- the row may pin an exact viewport (the desktop row does)
		local wantViewport = resolution.row.requires.viewport
		if wantViewport ~= nil then
			local okRes = pcall(function()
				svc:SetResolutionAsync(wantViewport.w, wantViewport.h)
			end)
			attempt.resolutionOverride = { w = wantViewport.w, h = wantViewport.h, applied = okRes }
		end

		-- settle: the plan requires waiting for ConfigurationChanged and THEN a
		-- stable non-1x1 viewport — the signal says the service applied the
		-- change, the poll says the engine finished resizing. Neither alone is
		-- enough, and a fixed sleep is neither.
		local cam = workspace.CurrentCamera
		local settled, last = false, Vector2.new(0, 0)
		for _ = 1, 60 do
			game:GetService("RunService").Heartbeat:Wait()
			local size = cam.ViewportSize
			if size.X > 1 and size.Y > 1 and size == last then
				settled = true
				break
			end
			last = size
		end
		if conn ~= nil then
			conn:Disconnect()
		end
		attempt.configurationChanged = {
			observed = configChanged,
			signalAvailable = okSignal,
			note = "connected BEFORE SetDeviceAsync/SetOrientationAsync/SetResolutionAsync/SetScalingModeAsync, "
				.. "which are the calls Roblox documents as firing it; the viewport poll remains the confirmation "
				.. "that the engine finished resizing",
		}
		attempt.viewportSettled = settled
		attempt.viewport = { w = cam.ViewportSize.X, h = cam.ViewportSize.Y }

		-- SETTLE THE FACTS, NOT JUST THE PIXELS. The viewport stabilises before
		-- the engine has finished publishing the input and display facts that
		-- follow from the new preset: reading immediately after a console
		-- selection returned PreferredInput = KeyboardAndMouse, while the same
		-- preset read a second later returned Gamepad. A row that recorded the
		-- early value would have said the ten-foot session had no gamepad.
		local api = scenarioApi()
		local report: any = nil
		local factsSettledFrames = 0
		if api ~= nil then
			local previous: string? = nil
			local stableFor = 0
			for i = 1, 90 do
				game:GetService("RunService").Heartbeat:Wait()
				report = decode(api.report(json({ tree = false })))
				local facts = report and report.env or {}
				local signature = `{tostring(facts.preferredInput)}|{tostring(facts.displaySize)}`
				if signature == previous then
					stableFor += 1
					if stableFor >= 6 then
						factsSettledFrames = i
						break
					end
				else
					stableFor = 0
					previous = signature
				end
				factsSettledFrames = i
			end
		end
		attempt.factsSettledFrames = factsSettledFrames
		-- RE-READ the viewport after the facts settled. The first read happens as
		-- soon as the size stops changing, which on an orientation change is
		-- before the engine has finished: the landscape row recorded the PORTRAIT
		-- viewport (360x691) beside a correctly-landscape env (678x339), i.e. the
		-- row's headline number and its own environment disagreed.
		attempt.viewport = { w = cam.ViewportSize.X, h = cam.ViewportSize.Y }
		attempt.viewportBeforeFactsSettled = { w = last.X, h = last.Y }
		-- WHAT THE SESSION SAYS, not what the catalog said. The first version
		-- built `observed` out of the catalog entry the policy had already
		-- filtered on, which made three of the six requirement checks
		-- tautological: they re-asserted the filter. These are the live getters.
		local live: any = { source = "StudioDeviceSimulatorService getters" }
		local function ask(member: string, key: string)
			if not hasMethod(svc, member) then
				live[key] = { unavailable = probeMethod(svc, member) }
				return
			end
			local ok, value = pcall(function()
				return (svc :: any)[member](svc)
			end)
			live[key] = if ok then serializeAny(value) else { error = tostring(value) }
		end
		ask("GetDeviceAsync", "deviceId")
		ask("GetResolutionAsync", "resolution")
		ask("GetPixelDensityAsync", "dpi")
		ask("GetOrientationAsync", "orientation")
		ask("GetScalingModeAsync", "scalingMode")
		attempt.live = live

		-- TWO DIFFERENT DENSITIES. GetPixelDensityAsync returns the EFFECTIVE
		-- density (catalog dpi / ResolutionScale: 501/4 = 125.25 on the phone,
		-- 264/2 = 132 on the tablet), while the selection policy filtered the pool
		-- on the CATALOG density. Testing the live number against the same
		-- thresholds would silently compare two quantities. The requirement check
		-- gets the catalog value it was written for; the live one is recorded
		-- beside it under its own name.
		local liveDpi = if type(live.dpi) == "number" then live.dpi else nil
		local observed = {
			-- DeviceForm has no live getter; it is a catalog property of the
			-- selected preset, and the row records that it came from there
			form = entry.form,
			formSource = "catalog (DeviceForm has no live getter)",
			dpi = entry.dpi,
			dpiSource = "catalog (the quantity the selection policy filtered on)",
			effectiveDpi = liveDpi,
			effectiveDpiSource = "live GetPixelDensityAsync = catalog dpi / ResolutionScale",
			deviceId = if type(live.deviceId) == "string" then live.deviceId else entry.id,
			catalogDeviceId = entry.id,
			viewport = attempt.viewport,
			envViewport = report and report.env and report.env.viewportRect,
			displaySize = report and report.env and report.env.displaySize,
			preferredInput = report and report.env and report.env.preferredInput,
			keyboardHeight = if resolution.row.orientation == "Portrait"
				then entry.portraitKeyboardHeight
				else entry.landscapeKeyboardHeight,
		}
		attempt.observed = observed
		local check = rows.checkRequirements(resolution.row, observed)
		attempt.requirements = check
		table.insert(attempts, attempt)

		if check.ok and settled then
			-- BOUNDARY NOTES. Facts about the instrument, recorded on the row
			-- rather than in a reader's memory. The first is load-bearing: touch
			-- is decided at Play START from the then-selected preset and does NOT
			-- follow a mid-session SetDeviceAsync, so a phone-shaped viewport in a
			-- desktop-booted session still reports pointer input. The row's
			-- LAYOUT evidence is unaffected; its INPUT-CLASS evidence is not
			-- available and must not be implied.
			local boundaryNotes = {}
			if entry.form == "Phone" or entry.form == "Tablet" then
				if observed.preferredInput ~= "Touch" then
					table.insert(
						boundaryNotes,
						`the session reports preferredInput='{tostring(observed.preferredInput)}' on a `
							.. `{entry.form} preset: touch is a BOOT-TIME fact and does not follow a mid-session `
							.. "device change. This row's geometry is valid; its touch-class behaviour is not "
							.. "evidenced here and physical touch remains E4."
					)
				end
			end
			if vi.usable then
				table.insert(
					boundaryNotes,
					"VirtualInput is available and every documented method (SendKey, SendMouseButton, "
						.. "SendMouseDelta, SendMousePosition, SendPointerAction, SendTextInput) is present and "
						.. "callable. Where a row's input trace came from the Studio MCP injector instead, the "
						.. "trace says so in `input.path` and why."
				)
			else
				table.insert(
					boundaryNotes,
					`VirtualInput is not usable here ({tostring(vi.reason)}), so native input for this row comes `
						.. "from injected input, recorded separately"
				)
			end
			return {
				ok = true,
				row = ARGS.row,
				boundaryNotes = boundaryNotes,
				chosen = entry,
				why = candidate.why,
				orientation = attempt.orientation,
				viewport = attempt.viewport,
				observed = observed,
				configurationChanged = attempt.configurationChanged,
				live = live,
				scalingMode = attempt.scalingMode,
				factsSettledFrames = factsSettledFrames,
				derived = report and report.derived,
				env = report and report.env,
				excluded = resolution.excluded,
				attempts = attempts,
				candidatesConsidered = #resolution.candidates,
				cannotProve = resolution.row.cannotProve,
			}
		end
	end

	return {
		ok = false,
		row = ARGS.row,
		reason = "no candidate satisfied the row's requirements in the running session",
		excluded = resolution.excluded,
		attempts = attempts,
		cannotProve = resolution.row.cannotProve,
	}
end

-- ===========================================================================
-- observe: bounded geometry / state / focus evidence for the current row
-- ===========================================================================
local MAX_NODES = 400

local function observe(): any
	local api = scenarioApi()
	if api == nil then
		return { ok = false, reason = "no scenario API" }
	end
	local report = decode(api.report(json({ tree = true })))
	if type(report) ~= "table" then
		return { ok = false, reason = "scenario report did not decode" }
	end

	-- BOUNDED: a full tree dump of a 200-row fixture is not evidence, it is a
	-- haystack. Keep the counts, the diagnostics, the offenders and a capped
	-- sample rather than everything.
	local nodes = 0
	local offscreen = {}
	local unfitText = {}
	local invisible = 0
	local clippedNodes = 0
	local cam = workspace.CurrentCamera
	local vw, vh = cam.ViewportSize.X, cam.ViewportSize.Y
	-- JUDGE FACET'S OWN TREES, NOT ROBLOX'S (example-quality-pass, 2026-08-06).
	-- The runner dumps EVERY ScreenGui under PlayerGui, which on a live client
	-- includes the CoreGui chat window. Its nodes reported `textFits = false`
	-- ("MessageMode", "Leave channel <XX>?", a Confirm and a Cancel) on every
	-- single row, so every example failed a check about Roblox's chat rather than
	-- about the example — six phantom unfit entries per row, identical everywhere,
	-- which is exactly what an always-firing check looks like.
	--
	-- The discriminator is the tree ROOT: a Facet surface's ScreenGui is named
	-- `Facet_<screen id>` by the adapter, and its descendants carry the flat
	-- `/path` names. Anything else in PlayerGui belongs to the platform.
	local judgedTrees = 0
	local skippedTrees = {}
	for _, tree in report.instanceTrees or {} do
		if type(tree.root) ~= "string" or string.sub(tree.root, 1, 6) ~= "Facet" then
			table.insert(skippedTrees, tostring(tree.root))
			continue
		end
		judgedTrees += 1
		-- CLIPPING ANCESTRY. The dump is a flat depth-ordered walk, so a stack of
		-- "is some ancestor a clip host" is enough. Without it the first live run
		-- flagged a virtual list's 8800px canvas as off-screen content, which is
		-- exactly what a scroll canvas is SUPPOSED to be: it is inside a
		-- ScrollingFrame, and the engine clips it. Reporting that as a layout
		-- defect would have made the check useless by making it always fire.
		local clipDepth: number? = nil
		for _, d in tree.nodes do
			nodes += 1
			local depth = d.depth or 0
			if clipDepth ~= nil and depth <= clipDepth then
				clipDepth = nil
			end
			local insideClip = clipDepth ~= nil
			if insideClip then
				clippedNodes += 1
			end
			if d.clips == true and clipDepth == nil then
				clipDepth = depth
			end
			if d.visible == false then
				invisible += 1
			end
			if d.absPos ~= nil and d.absSize ~= nil and d.visible ~= false and not insideClip then
				local right, bottom = d.absPos.x + d.absSize.x, d.absPos.y + d.absSize.y
				if
					(d.absSize.x > 0 and d.absSize.y > 0)
					and (d.absPos.x < -1 or d.absPos.y < -1 or right > vw + 1 or bottom > vh + 1)
					and #offscreen < 20
				then
					table.insert(offscreen, {
						name = d.name,
						class = d.class,
						pos = d.absPos,
						size = d.absSize,
					})
				end
			end
			-- a ZERO-RECT node cannot be unfit: a losing ViewThatFits candidate
			-- (and any hidden-by-rect form) keeps its mount with a 0x0 box and
			-- its text legitimately "does not fit" nothing
			local sized = d.absSize ~= nil and d.absSize.x > 0 and d.absSize.y > 0
			if d.textFits == false and sized and #unfitText < 20 then
				-- a truncation the AUTHOR DECLARED (disclose/reveal) is the
				-- framework's legal overflow policy with a full-value affordance —
				-- evidence, not a failure. The runner publishes the facts channel
				-- as report.textPolicies keyed by the same flat path names.
				local policy = (report.textPolicies or {})[d.name]
				if policy == nil and type(d.name) == "string" then
					-- instance names cap at 100 chars, so a deep node's flat name
					-- is a PREFIX of its real path — and that prefix can cover the
					-- whole card subtree (several text nodes). The judgement only
					-- concerns nodes that actually TRUNCATED, so: gather the
					-- prefix-matched policies whose facts say truncated, and the
					-- finding is declared only if every one of them declares a
					-- full-value affordance. Zero truncated hits keeps it
					-- undeclared (the facts channel does not know this node).
					local truncatedHits = 0
					local allDeclared = true
					for path, pol in report.textPolicies or {} do
						if string.sub(path, 1, #d.name) == d.name and (pol :: any).truncated == true then
							truncatedHits += 1
							if not ((pol :: any).disclose == true or (pol :: any).reveal ~= nil) then
								allDeclared = false
							end
						end
					end
					if truncatedHits > 0 and allDeclared then
						policy = { disclose = true, policy = "disclose(prefix)" }
					end
				end
				local declared = policy ~= nil and ((policy :: any).disclose == true or (policy :: any).reveal ~= nil)
				table.insert(unfitText, {
					name = d.name,
					text = d.text,
					declared = if declared then (policy :: any).policy or "disclose" else nil,
				})
			end
		end
	end

	return {
		ok = true,
		scenario = report.scenario,
		version = report.version,
		sourceStamp = report.sourceStamp,
		viewport = report.viewport,
		envFrozen = report.envFrozen,
		env = report.env,
		derived = report.derived,
		focusPath = report.focusPath,
		selectedObject = report.selectedObject,
		custom = report.custom,
		diagnostics = report.diagnostics,
		solverDiagnostics = if report.diagnostics ~= nil then #report.diagnostics else 0,
		nodes = nodes,
		nodesCapped = nodes > MAX_NODES,
		invisibleNodes = invisible,
		clippedNodes = clippedNodes,
		offscreenNodes = offscreen,
		judgedTrees = judgedTrees,
		skippedTrees = skippedTrees,
		unfitText = unfitText,
	}
end

-- ===========================================================================
-- input: drive native input through VirtualInput, at LIVE geometry, and pair
-- the raw event with the visible effect.
--
-- Signatures verified live (Studio 0.731):
--   SendMousePosition(Vector2)
--   SendMouseButton(Vector2, Enum.UserInputType, isPressed: boolean)
--   SendKey(isPressed: boolean, Enum.KeyCode)
--   SendTextInput(string)
-- Every one of them errors if the simulated input would interact with CoreGui;
-- that is a per-call failure and is recorded on the call.
--
-- This runs INSIDE the session, so there is no round-trip between arming and
-- pressing: the whole arm → press → read chain is one call, and the latency it
-- reports is the interaction rather than the orchestration.
local function driveInput(): any
	local api = scenarioApi()
	if api == nil then
		return { ok = false, reason = "no scenario API" }
	end
	local vi = virtualInputProbe()
	if not vi.usable then
		return {
			ok = false,
			path = "unsupported",
			virtualInput = { available = vi.available, usable = false, methods = vi.methods, reason = vi.reason },
			reason = "VirtualInput cannot drive this path; native input evidence must come from injected input, "
				.. "recorded separately and labelled as such",
		}
	end

	local armed = decode(api.step("armInput"))
	local result = armed and armed.result or armed
	local aim = result and result.aimPoint
	if aim == nil then
		return { ok = false, reason = "the scenario returned no aim point" }
	end

	local calls: { any } = {}
	local function call(label: string, fn: () -> ())
		local ok, err = pcall(fn)
		table.insert(calls, { call = label, ok = ok, error = if ok then nil else tostring(err) })
		return ok
	end
	local function press(at: Vector2, label: string)
		-- VirtualInput tracks button STATE and refuses a duplicate
		-- ("duplicate button state"), so a run that left the button down makes
		-- the next press a silent no-op with a real-looking trace. Clear first.
		pcall(function()
			(vi.instance :: any):SendMouseButton(at, Enum.UserInputType.MouseButton1, false)
		end)
		call(`{label}: SendMousePosition({at.X}, {at.Y})`, function()
			(vi.instance :: any):SendMousePosition(at)
		end)
		game:GetService("RunService").Heartbeat:Wait()
		call(`{label}: SendMouseButton down`, function()
			(vi.instance :: any):SendMouseButton(at, Enum.UserInputType.MouseButton1, true)
		end)
		game:GetService("RunService").Heartbeat:Wait()
		call(`{label}: SendMouseButton up`, function()
			(vi.instance :: any):SendMouseButton(at, Enum.UserInputType.MouseButton1, false)
		end)
		game:GetService("RunService").Heartbeat:Wait()
	end

	-- CALIBRATE, THEN AIM. Injected pointer coordinates and the coordinates the
	-- engine reports are offset by an amount that depends on the emulated
	-- configuration — and it differs by injector too (measured: 47px for the MCP
	-- injector on one preset, 105px for VirtualInput on another). A remembered
	-- constant silently aims the click somewhere else and the capture still
	-- looks right, so the offset is MEASURED every time: press once, read what
	-- the engine said, aim compensated.
	local aimPoint = Vector2.new(aim.x, aim.y)
	press(aimPoint, "calibration")
	local calProbe = decode(api.step("calibrateInput:" .. tostring(aim.y)))
	local cal = calProbe and calProbe.result or calProbe
	local offsetY = if cal ~= nil and type(cal.offsetY) == "number" then cal.offsetY else 0
	local calibration = {
		requestedY = aim.y,
		reportedY = cal and cal.rawEvent and cal.rawEvent.position and cal.rawEvent.position.y,
		offsetY = offsetY,
		method = "one throwaway press at the aim point; the engine's reported Y minus the requested Y is the offset",
	}
	local point = Vector2.new(aim.x, aim.y + offsetY)

	-- re-arm so the measured press is the one that counts
	armed = decode(api.step("armInput"))
	result = armed and armed.result or armed
	press(point, "measured")

	local read = decode(api.step("readInput"))
	local effect = read and read.result or read
	local ok = effect ~= nil and effect.inputToVisibleMs ~= nil and effect.inputToVisibleMs.measured == true
	return {
		ok = ok,
		path = "VirtualInput (UserInputService:CreateVirtualInput)",
		virtualInput = { available = true, usable = true, methods = vi.methods },
		aimPoint = aim,
		calibration = calibration,
		injectedAt = { x = point.X, y = point.Y },
		aimSource = "the mounted control's live AbsolutePosition/AbsoluteSize, read back through the scenario",
		calls = calls,
		before = { boosts = result.boostsBefore, boostText = result.boostTextBefore },
		rawEvent = effect and effect.rawPair,
		effect = effect and { boosts = effect.boosts, boostText = effect.boostText },
		inputToVisibleMs = effect and effect.inputToVisibleMs,
		cannotProve = {
			"physical touch targeting, gestures or feel — a VirtualInput pointer event is not a finger (E4)",
			"real gamepad delivery or platform arbitration — VirtualInput synthesizes no gamepad input class (E4)",
			"display latency — no instrument here sees scan-out",
		},
	}
end

-- ===========================================================================
-- keyboard: drive a SEQUENCE of raw key presses through VirtualInput and pair
-- each one with the semantic action, focus, scroll and state it produced
-- (roadmap Step 8, acceptance row DK-17).
--
-- WHY A SEQUENCE AND NOT A PRESS. Every claim in this stage is about what the
-- Nth press does GIVEN the N-1 before it — Tab, Tab, Shift+Tab lands where it
-- started; Tab out of an editing field commits and only then advances. A
-- one-press driver can only ever prove the first of those.
--
-- `args.keys` is a list of key specs, each `"Tab"` or `"Shift+Tab"` (any
-- KeyCode name; the `Shift+` prefix holds LeftShift across the press). The
-- scenario's `armKeys`/`readKeys` steps bracket the run, so the raw log, the
-- action log and the focus log all cover exactly these presses and nothing else.
--
-- WHAT IT CANNOT PROVE: that a PHYSICAL keyboard delivers the same events. See
-- the honest-evidence boundary in docs/plans/studio-device-verification.md —
-- VirtualInput is player-like, not hardware.
local function driveKeyboard(): any
	local api = scenarioApi()
	if api == nil then
		return { ok = false, reason = "no scenario API" }
	end
	local vi = virtualInputProbe()
	if not vi.usable then
		return {
			ok = false,
			path = "unsupported",
			virtualInput = { available = vi.available, usable = false, methods = vi.methods, reason = vi.reason },
			reason = "VirtualInput cannot drive this path; a keyboard row cannot be closed from here",
		}
	end
	local keys = ARGS.keys
	if type(keys) ~= "table" or #keys == 0 then
		return { ok = false, reason = "args.keys must be a non-empty list of key specs" }
	end

	local armed = decode(api.step("armKeys"))
	local before = armed and armed.result or armed

	local calls: { any } = {}
	local function sendKey(name: string, pressed: boolean): boolean
		local keyCode = (Enum.KeyCode :: any)[name]
		if keyCode == nil then
			table.insert(calls, { call = name, ok = false, error = `no KeyCode named '{name}'` })
			return false
		end
		local ok, err = pcall(function()
			(vi.instance :: any):SendKey(pressed, keyCode)
		end)
		table.insert(
			calls,
			{ call = `SendKey({tostring(pressed)}, {name})`, ok = ok, error = if ok then nil else tostring(err) }
		)
		game:GetService("RunService").Heartbeat:Wait()
		return ok
	end

	for _, spec in keys do
		local text = tostring(spec)
		local modifier, key = string.match(text, "^(%a+)%+(.+)$")
		if modifier ~= nil then
			-- "Shift+Tab" — hold the modifier across the whole press so
			-- UserInputService:IsKeyDown, which is what the presenter reads for
			-- the traversal direction, sees it at the moment the key goes down
			local held = if string.lower(modifier) == "shift" then "LeftShift" else modifier
			sendKey(held, true)
			sendKey(key, true)
			sendKey(key, false)
			sendKey(held, false)
		else
			sendKey(text, true)
			sendKey(text, false)
		end
	end

	local read = decode(api.step("readKeys"))
	local after = read and read.result or read
	local rawCount = if after ~= nil and type(after.rawInput) == "table" then #after.rawInput else 0
	local actionCount = if after ~= nil and type(after.actions) == "table" then #after.actions else 0
	return {
		ok = rawCount > 0 and actionCount > 0,
		path = "VirtualInput:SendKey (UserInputService:CreateVirtualInput)",
		virtualInput = { available = true, usable = true, methods = vi.methods },
		keys = keys,
		calls = calls,
		before = before,
		after = after,
		pairing = {
			rawEvents = rawCount,
			semanticActions = actionCount,
			note = "a row is only closed when BOTH are non-empty: raw events prove the press reached the "
				.. "engine, semantic actions prove it reached the intended verb. Either alone is blind.",
		},
		cannotProve = {
			"that a PHYSICAL keyboard delivers these events — VirtualInput is player-like, not hardware (E4)",
			"a real mobile operating-system keyboard on a touch device (E4)",
			"native arbitration against a real avatar control stack outside this place",
		},
	}
end

-- ===========================================================================
local function stepScenario(): any
	local api = scenarioApi()
	if api == nil then
		return { ok = false, reason = "no scenario API" }
	end
	local arg = if ARGS.payload ~= nil then `{ARGS.step}:{ARGS.payload}` else ARGS.step
	local ok, result = pcall(function()
		return decode(api.step(arg))
	end)
	return { ok = ok, step = ARGS.step, result = if ok then result else tostring(result) }
end

-- RESET. `StopSimulationAsync()` is the documented way to end simulation, and
-- it works here. An earlier version of this driver reported "the service
-- exposes no stop member" — that was a wrong-NAME probe (`StopDeviceAsync`,
-- which does not exist) reported as a security refusal, and the claim reached a
-- guide, a plan and three artifacts before the platform review caught it. The
-- probe is tri-state now so the same mistake announces itself.
local function resetSimulation(): any
	local svc = serviceOrNil("StudioDeviceSimulatorService")
	if svc == nil then
		return { ok = false, reason = "StudioDeviceSimulatorService unavailable" }
	end
	local stopProbe = probeMethod(svc, "StopSimulationAsync")
	local stopped, stopErr = false, nil
	if stopProbe.state == "present" then
		local ok, err = pcall(function()
			(svc :: any):StopSimulationAsync()
		end)
		stopped = ok
		if not ok then
			stopErr = tostring(err)
		end
	end
	local cam = workspace.CurrentCamera
	return {
		ok = stopped,
		stopped = stopped,
		stopProbe = stopProbe,
		error = stopErr,
		viewportAfter = if cam then { w = cam.ViewportSize.X, h = cam.ViewportSize.Y } else nil,
		note = "simulation stopped via StudioDeviceSimulatorService:StopSimulationAsync(); "
			.. 'SetDeviceAsync("default") is the documented equivalent',
	}
end

-- ===========================================================================
-- row: the whole automated half of one matrix row in ONE call — select the
-- device, observe the fixture, take the performance capture, and stamp the
-- result with the identity a reader needs to trust it. Native input is
-- deliberately NOT part of this: it needs an external injector, so the caller
-- runs `step armInput`, injects, and runs `step readInput`, and this record
-- carries whatever the injection produced if it already happened.
local function rowRecord(): any
	local selected = selectRow()
	if not selected.ok then
		return { ok = false, row = ARGS.row, evidenceClass = "studio-emulated", evidenceLevel = "E3", select = selected }
	end
	local observed = observe()
	local api = scenarioApi()
	local measure: any = nil
	if ARGS.measure ~= false and api ~= nil then
		local ok, result = pcall(function()
			return decode(api.step(`measure:{tostring(ARGS.frames or 60)}`))
		end)
		measure = if ok then (result.result or result) else { error = tostring(result) }
	end
	return {
		-- `judgedTrees > 0` is the anti-vacuity clause: a tree filter that matched
		-- nothing would report a clean layout for an empty set
		ok = observed.ok
			and (observed.judgedTrees or 0) > 0
			and #observed.offscreenNodes == 0
			and observed.solverDiagnostics == 0
			-- DECLARED truncation (disclose/reveal) is the framework's legal
			-- overflow policy with a full-value affordance; only an UNDECLARED
			-- unfit is a row failure
			and (function(): boolean
				for _, u in observed.unfitText do
					if (u :: any).declared == nil then
						return false
					end
				end
				return true
			end)(),
		row = ARGS.row,
		-- EVIDENCE CLASS on every row, for the same reason the perf runner
		-- stamps it: this is a Studio session on a development host, and it is
		-- never a device result
		evidenceClass = "studio-emulated",
		evidenceLevel = "E3",
		cannotProve = selected.cannotProve,
		boundaryNotes = selected.boundaryNotes,
		identity = {
			studioVersion = tostring(version()),
			sourceStamp = workspace:GetAttribute("Facet_SourceStamp"),
			libraryVersion = workspace:GetAttribute("Facet_Version"),
			scenario = workspace:GetAttribute("Facet_Scenario"),
			placeId = game.PlaceId,
		},
		device = {
			factsSettledFrames = selected.factsSettledFrames,
			observed = selected.observed,
			configurationChanged = selected.configurationChanged,
			live = selected.live,
			scalingMode = selected.scalingMode,
			id = selected.chosen.id,
			name = selected.chosen.name,
			form = selected.chosen.form,
			catalogResolution = { w = selected.chosen.w, h = selected.chosen.h },
			scale = selected.chosen.scale,
			dpi = selected.chosen.dpi,
			why = selected.why,
			candidatesConsidered = selected.candidatesConsidered,
			excluded = selected.excluded,
			orientation = selected.orientation,
			reportedViewport = selected.viewport,
		},
		env = observed.env,
		derived = observed.derived,
		geometry = {
			nodes = observed.nodes,
			clippedNodes = observed.clippedNodes,
			invisibleNodes = observed.invisibleNodes,
			offscreenNodes = observed.offscreenNodes,
			unfitText = observed.unfitText,
			judgedTrees = observed.judgedTrees,
			skippedTrees = observed.skippedTrees,
			solverDiagnostics = observed.solverDiagnostics,
			focusPath = observed.focusPath,
		},
		fixture = observed.custom,
		metrics = measure,
	}
end

-- ===========================================================================
local function run(args: any): string
	ARGS = args or {}
	local mode = ARGS.mode or "catalog"
	if mode == "catalog" then
		return json(catalog())
	elseif mode == "preflight" then
		return json(preflight())
	elseif mode == "select" then
		return json(selectRow())
	elseif mode == "observe" then
		return json(observe())
	elseif mode == "row" then
		return json(rowRecord())
	elseif mode == "step" then
		return json(stepScenario())
	elseif mode == "input" then
		return json(driveInput())
	elseif mode == "keyboard" then
		return json(driveKeyboard())
	elseif mode == "reset" then
		local result = resetSimulation()
		local installed = workspace:FindFirstChild("FacetMatrixDriver")
		if installed ~= nil and ARGS.uninstall == true then
			installed:Destroy()
			result.uninstalled = true
		end
		return json(result)
	end
	return json({ ok = false, reason = `unknown mode '{tostring(mode)}'` })
end

return run
