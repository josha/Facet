--!strict
-- Scenario runner: the engine-touching half of the verification surface
-- (fable-execution-contract §5). Mounts ONE named scenario through the real
-- presenter/adapter, exposes deterministic drive + observation seams to the
-- Studio MCP, and exports a machine-readable report keyed to acceptance rows.
--
-- The runner NEVER counterfeits hardware input: steps are state/action drivers
-- and are labeled as such in the report. Native-input rows use real/injected
-- input through the MCP input tools, then read the same report for effects.
--
-- MCP contract (execute_luau, Client datamodel):
--   _G.LuauUIScenario.list()          -> registered scenario names
--   _G.LuauUIScenario.step(name)      -> run a named scenario step, returns its result
--   _G.LuauUIScenario.report(opts?)   -> JSON string (luauui-scenario/1)
--   _G.LuauUIScenario.reset()         -> teardown + rebuild the scenario fresh
--   _G.LuauUIScenario.freezeEnv()     -> detach live engine env binding so
--                                        env:set(...) overrides hold steady
-- Workspace attributes: LuauUI_Scenario (selection, set BEFORE Play),
-- LuauUI_ScenarioReady, LuauUI_ScenarioState, LuauUI_SourceStamp (injector),
-- LuauUI_Version.

local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

local ENV_FACT_KEYS = {
	"viewportRect",
	"deviceSafeInsets",
	"coreSafeInsets",
	"topbarInset",
	"preferredInput",
	"capabilities",
	"reducedMotion",
	"preferredTextSize",
	"displaySize",
	"overscanInsets",
}
local ENV_DERIVED_KEYS = {
	"typographyScale",
	"sizeClass",
	"distanceProfile",
	"interactionClasses",
	-- the ten-foot row's headline is that a TV really gets inset content, and
	-- `overscanInsets` is the AUTHORED fact (zero unless a game sets it) while
	-- `effectiveOverscanInsets` is what the presentation actually applies. A row
	-- that recorded only the authored value would show 0,0,0,0 on a console and
	-- read as if the margins never engaged.
	"effectiveOverscanInsets",
	-- flat vs world presentation (ADR-0021); "screen" on every row today, and
	-- recorded so the day it is not, the rows say so
	"presentationProfile",
}

local function serializeValue(v: any): any
	local t = typeof(v)
	if t == "Vector2" then
		return { x = v.X, y = v.Y }
	elseif t == "Rect" then
		return { minX = v.Min.X, minY = v.Min.Y, maxX = v.Max.X, maxY = v.Max.Y }
	elseif t == "UDim2" then
		return tostring(v)
	elseif t == "Color3" then
		return string.format("#%02x%02x%02x", v.R * 255 + 0.5, v.G * 255 + 0.5, v.B * 255 + 0.5)
	elseif t == "EnumItem" then
		return tostring(v)
	elseif t == "table" then
		local out = {}
		for k, vv in v do
			out[tostring(k)] = serializeValue(vv)
		end
		return out
	elseif t == "Instance" then
		return v:GetFullName()
	end
	return v
end

-- style-authority telemetry (native-stylesheets NSS-A2/A3): resolved styled
-- values via GetStyled — the instrument that tracks the ACTUAL winner (an
-- explicit write shows up as styled ~= sheet-resolved; spike m10)
local STYLED_PROPS: { [string]: { string } } = {
	Frame = { "BackgroundColor3", "BackgroundTransparency" },
	TextButton = { "BackgroundColor3", "BackgroundTransparency", "TextColor3", "TextTransparency" },
	TextLabel = { "BackgroundColor3", "BackgroundTransparency", "TextColor3" },
	TextBox = { "BackgroundColor3", "BackgroundTransparency", "TextColor3", "TextTransparency" },
	-- the IMAGE properties joined the list for rich-skinning-v2 (ADR-0020 R1/R2):
	-- a layer's picture is RULE-owned, so a plain `.Image` read is blind and only
	-- `GetStyled` reports the winner. The pair is the defeat-detection instrument
	-- — `d.image` (plain) next to `d.styled.Image` (resolved).
	ImageLabel = {
		"BackgroundColor3",
		"BackgroundTransparency",
		"Image",
		"ImageColor3",
		"ImageTransparency",
		"ScaleType",
		"SliceCenter",
		"SliceScale",
		"TileSize",
	},
	ScrollingFrame = { "BackgroundColor3", "BackgroundTransparency", "ScrollBarImageColor3" },
}

local function dumpGuiInstance(inst: Instance): { [string]: any }?
	if not inst:IsA("GuiObject") and not inst:IsA("ScreenGui") and not inst:IsA("Path2D") then
		return nil
	end
	local d: { [string]: any } = { class = inst.ClassName, name = inst.Name }
	if inst:IsA("GuiObject") then
		d.absPos = serializeValue(inst.AbsolutePosition)
		d.absSize = serializeValue(inst.AbsoluteSize)
		d.visible = inst.Visible
		d.zIndex = inst.ZIndex
		d.clips = inst.ClipsDescendants
		local tags = game:GetService("CollectionService"):GetTags(inst)
		if #tags > 0 then
			table.sort(tags)
			d.tags = tags
		end
		-- modifier-instance telemetry (arch verifier 2026-07-24): phantom-chrome
		-- claims must be machine-checkable — count REAL UICorner/UIStroke
		-- children per node (native mode: zero except declared overrides, which
		-- carry the LuauUI_DeclaredOverride attribute)
		local corners, strokes = 0, 0
		for _, c in inst:GetChildren() do
			if c:IsA("UICorner") then
				corners += 1
			elseif c:IsA("UIStroke") then
				strokes += 1
			end
		end
		if corners > 0 or strokes > 0 then
			d.modifierChildren = { UICorner = corners, UIStroke = strokes }
		end
		if inst:GetAttribute("LuauUI_DeclaredOverride") == true then
			d.declaredOverride = true
		end
		-- PAINT CLAIMS (ADR-0022 Decision 6): the engine properties this node took
		-- from the sheet because no rule can carry their value (a `tint` blend, an
		-- identity hue, an authored `scaleMode`). Dumped BESIDE `styled` on purpose —
		-- a claimed property is EXPECTED to diverge from the sheet-resolved value, and
		-- this is what tells the defeat audit that the divergence was declared.
		local claims = inst:GetAttribute("LuauUI_PaintClaims")
		if type(claims) == "string" and claims ~= "" then
			d.paintClaims = claims
		end
		local styledProps = STYLED_PROPS[inst.ClassName]
		if styledProps ~= nil then
			local styled = {}
			for _, prop in styledProps do
				local ok, v = pcall(function()
					return (inst :: any):GetStyled(prop)
				end)
				if ok then
					styled[prop] = serializeValue(v)
				end
			end
			d.styled = styled
			local okState, guiState = pcall(function()
				return tostring((inst :: any).GuiState)
			end)
			if okState then
				d.guiState = guiState
			end
		end
		if inst:IsA("ScrollingFrame") then
			d.canvasPosition = serializeValue(inst.CanvasPosition)
			d.absCanvasSize = serializeValue(inst.AbsoluteCanvasSize)
			d.scrollingEnabled = inst.ScrollingEnabled
		end
		if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
			d.text = (inst :: any).ContentText
			d.textBounds = serializeValue((inst :: any).TextBounds)
			d.textFits = (inst :: any).TextFits
		end
		if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
			d.image = (inst :: any).Image
			d.isLoaded = (inst :: any).IsLoaded
		end
		if inst.Selectable then
			d.selectable = true
		end
	elseif inst:IsA("Path2D") then
		d.controlPoints = #inst:GetControlPoints()
		d.thickness = inst.Thickness
		d.color = serializeValue(inst.Color3)
		d.visible = inst.Visible
	end
	return d
end

local function dumpTree(root: Instance): { any }
	local out: { any } = {}
	local function walk(inst: Instance, depth: number)
		local d = dumpGuiInstance(inst)
		if d then
			d.depth = depth
			table.insert(out, d)
		end
		for _, c in inst:GetChildren() do
			walk(c, depth + 1)
		end
	end
	walk(root, 0)
	return out
end

local Runner = {}

function Runner.start(deps: { [string]: any })
	local LuauUI = deps.LuauUI
	local registry = deps.registry
	local name = deps.scenarioName :: string
	local mod = registry.modules[name]
	-- the shared foreign-content materializer (ADR-0034); see the note at
	-- `applyForeignContent` below for why it is not a local in this file
	local foreign_instances = require(registry.foreignInstances) :: any
	if mod == nil then
		workspace:SetAttribute("LuauUI_ScenarioState", "failed:unknown-scenario:" .. name)
		error(`[LuauUI Scenario] unknown scenario '{name}' (registered: {table.concat(registry.order, ",")})`)
	end

	local scenario = require(mod) :: any
	local session = {
		stepLog = {} :: { { step: string, at: number, result: any } },
		built = nil :: any,
		envFrozen = false,
	}
	-- mount-identity registry (NSS-A3/A6): weak-keyed so removed instances GC
	local identityIds: { [Instance]: string } = setmetatable({}, { __mode = "k" }) :: any
	local identityCounter = 0

	-- Shared stage-content materializer (swiftui-reference-app-validation): the
	-- one engine-side seam that turns a proof's plain-table stage content into
	-- Parts/camera/lighting through the public stage host. Used by the
	-- post-present pass below and by ctx.stage.apply (live re-dress).
	local function applyStageContent(controller: any, nodePath: string, content: any): string
		local host = if controller ~= nil and controller.stageHost ~= nil then controller.stageHost(nodePath) else nil
		if host == nil then
			return "no-host"
		end
		if content.lighting ~= nil then
			host.setLighting(content.lighting)
		end
		if content.camera ~= nil then
			host.setCamera(content.camera)
		end
		local root = host.contentRoot()
		if typeof(root) == "Instance" then
			if content.replace ~= false then
				for _, child in root:GetChildren() do
					child:Destroy()
				end
			end
			if content.parts ~= nil then
				for _, p in content.parts :: { any } do
					local part = Instance.new("Part")
					part.Anchored = true
					part.CanCollide = false
					part.CanQuery = false
					part.CanTouch = false
					part.CastShadow = false
					part.Shape = if p.shape == "ball"
						then Enum.PartType.Ball
						elseif p.shape == "cylinder" then Enum.PartType.Cylinder
						else Enum.PartType.Block
					part.Size = Vector3.new(p.size[1], p.size[2], p.size[3])
					part.Color = Color3.new(p.color[1], p.color[2], p.color[3])
					if p.transparency ~= nil then
						part.Transparency = p.transparency
					end
					local pos = Vector3.new(p.cframe.pos[1], p.cframe.pos[2], p.cframe.pos[3])
					part.CFrame = if p.cframe.lookAt ~= nil
						then CFrame.lookAt(pos, Vector3.new(p.cframe.lookAt[1], p.cframe.lookAt[2], p.cframe.lookAt[3]))
						else CFrame.new(pos)
					part.Parent = root
				end
				return "materialized"
			end
			return "no-parts"
		end
		return "stub-root"
	end

	-- FOREIGN CONTENT (UI.Foreign, ADR-0034) is materialized by a SHARED sibling
	-- module rather than by a local like `applyStageContent` above, because the
	-- shipped showcase host needs the identical capability and a runner-only
	-- version would make the test rig more correct than the thing a player opens
	-- (the C2 failure this file's own `present`-opts comment records). See
	-- `foreign_instances.luau`.
	local function applyForeignContent(controller: any, nodePath: string, content: any): string
		return foreign_instances.adopt(controller, nodePath, content)
	end

	local function build()
		local ctx = {
			LuauUI = LuauUI,
			-- HOST SEAMS (roadmap Step 9). A scenario module is engine-free by
			-- contract, and the runner owns every engine seam it needs — but a stage
			-- can need one this runner has no business knowing about (the performance
			-- lab's raw-Roblox reference list, its host environment facts, its
			-- profiler handle). `host` is the generic passthrough for those: whatever
			-- the BOOTSTRAP hands `runner.start` arrives here untouched. `nil` in the
			-- gallery, which is why every existing scenario is unaffected.
			host = deps.host,
			-- ...and the sibling modules a registry chose to expose, for the same
			-- reason: a scenario that required `script.Parent` would be Roblox-only.
			lab = deps.lab,
			core = deps.core,
			env = deps.env,
			adapter = deps.adapter,
			presenter = deps.presenter,
			actionSystem = deps.actionSystem,
			record = function(key: string, value: any)
				table.insert(
					session.stepLog,
					{ step = "record:" .. key, at = os.clock(), result = serializeValue(value) }
				)
			end,
			-- engine seams stay runner-owned so scenario modules remain
			-- engine-free: binds the Roblox resource transport (NS-A13)
			bindResourceTransport = function(provider: any): () -> ()
				local transport = require(game:GetService("ReplicatedStorage").LuauUI.client.roblox_resources) :: any
				return transport.bind(provider)
			end,
			-- WORLD-ANCHORED PRESENTATION (ADR-0009; row SF-W1). A BillboardGui, a
			-- world Part and a second render target are all engine objects, so they
			-- stay runner-owned exactly like the resource transport above: the
			-- scenario declares the blueprint and drives the steps, and this is the
			-- only place that touches an Instance on its behalf. Every method answers
			-- a table rather than throwing, so a scenario degrades honestly on a host
			-- that has no engine at all (the headless suite).
			billboard = (function()
				local state: any = nil
				local api: any = {}
				function api.available(): boolean
					return true
				end
				function api.mount(spec: any): any
					if state ~= nil then
						return api.dump()
					end
					local ok, built = pcall(function()
						local ReplicatedStorage = game:GetService("ReplicatedStorage")
						local billboardTarget = require(ReplicatedStorage.LuauUI.client.billboard_target) :: any
						local canvas = spec.canvas or { w = 320, h = 220 }
						local part = Instance.new("Part")
						part.Name = "LuauUI_BillboardAnchor"
						part.Anchored = true
						part.CanCollide = false
						part.CanQuery = false
						part.Size = Vector3.new(2, 2, 2)
						part.Transparency = 0.6
						part.CFrame = workspace.CurrentCamera.CFrame * CFrame.new(0, 0, -18)
						part.Parent = workspace
						-- display-only, but PlayerGui-parented with an Adornee: that is the
						-- documented topology (ADR-0009), and a fixture that used another
						-- parent would be proving a path no consumer uses
						local adapter = billboardTarget.new({
							parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
							adornee = part,
							canvas = canvas,
							alwaysOnTop = true,
						})
						-- the solver's world IS the canvas (scale units mean studs here)
						local billboardEnv = LuauUI.newEnvironment(deps.core)
						billboardEnv:set("viewportRect", billboardTarget.canvasRect(canvas))
						local root = LuauUI.mount(deps.core, spec.blueprint)
						local controller = LuauUI.renderer.attach(
							deps.core,
							root,
							billboardEnv,
							adapter,
							{ rootPolicy = "edgeToEdge" }
						)
						controller.initialRender()
						return {
							part = part,
							adapter = adapter,
							env = billboardEnv,
							root = root,
							controller = controller,
							canvas = canvas,
						}
					end)
					if not ok then
						return { mounted = false, error = tostring(built) }
					end
					state = built
					return api.dump()
				end
				function api.refresh(): boolean
					if state == nil then
						return false
					end
					state.controller.refresh()
					return true
				end
				function api.moveAnchor(dx: number, dy: number, dz: number): any
					if state == nil then
						return { moved = false }
					end
					state.part.CFrame = state.part.CFrame * CFrame.new(dx or 0, dy or 0, dz or 0)
					return { moved = true, position = serializeValue(state.part.Position) }
				end
				-- the LIFECYCLE READ a teardown row needs: how many billboard GUIs the
				-- client actually carries, and whether the adornee is still in the world
				function api.dump(): any
					local guiCount, descendants = 0, 0
					local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
					if playerGui ~= nil then
						for _, gui in playerGui:GetChildren() do
							if gui:IsA("BillboardGui") then
								guiCount += 1
								descendants += #gui:GetDescendants()
							end
						end
					end
					local anchors = 0
					for _, inst in workspace:GetChildren() do
						if inst.Name == "LuauUI_BillboardAnchor" then
							anchors += 1
						end
					end
					if state == nil then
						return { mounted = false, billboardGuis = guiCount, anchors = anchors }
					end
					return {
						mounted = true,
						canvas = state.canvas,
						adorneePresent = state.part.Parent ~= nil,
						adorneePosition = serializeValue(state.part.Position),
						billboardGuis = guiCount,
						billboardDescendants = descendants,
						anchors = anchors,
						rootCounters = state.root.counters(),
					}
				end
				function api.teardown(): any
					if state == nil then
						return { torn = false, after = api.dump() }
					end
					local dying = state
					state = nil
					pcall(function()
						dying.controller.dispose()
					end)
					pcall(function()
						dying.root.dispose()
					end)
					pcall(function()
						dying.part:Destroy()
					end)
					return { torn = true, after = api.dump() }
				end
				return api
			end)(),
			-- test-run flags (engine attribute reads stay runner-owned)
			flags = {
				forceDragFallback = workspace:GetAttribute("LuauUI_ForceDragFallback") == true,
				forceScrollFallback = workspace:GetAttribute("LuauUI_ForceScrollFallback") == true,
				-- theme-packages stage: the package/theme a Studio operator
				-- selects BEFORE Play, so the five-view matrix can be driven
				-- against a chosen skin without editing a scenario
				themePackage = workspace:GetAttribute("LuauUI_ThemePackage"),
				themeName = workspace:GetAttribute("LuauUI_ThemeName"),
				-- roadmap Step 10: which tutorial example the `examples` scenario
				-- opens on, selected the same way and for the same reason as the
				-- theme package above — an operator picks it BEFORE Play and the
				-- matrix re-selects at runtime through the scenario step
				example = workspace:GetAttribute("LuauUI_Example"),
			},
			-- REFERENCE THEME PACKAGES (theme-packages-and-skinning). They are
			-- ModuleScripts under ReplicatedStorage.LuauUIThemes here and files
			-- under examples/themes/ headlessly, so resolving them is runner
			-- work exactly like the resource transport and the calibration seam
			-- — the scenario module stays engine-free and path-free.
			-- THE TUTORIAL EXAMPLE MODULES, resolved the same way and for the same
			-- reason as the theme packages below: they are ModuleScripts under
			-- ReplicatedStorage.LuauUIExamples here and files under
			-- examples/gallery/examples headlessly, so finding them is runner work
			-- and the `examples` scenario stays path-free.
			exampleModules = game:GetService("ReplicatedStorage"):FindFirstChild("LuauUIExamples"),
			-- THE REFERENCE PROOF MODULES (swiftui-reference-app-validation):
			-- ModuleScripts under ReplicatedStorage.LuauUIReference here, files
			-- under examples/reference/ headlessly — resolved by the runner for the
			-- same reason as the tutorial examples above, so the ref_* scenarios
			-- stay engine-free and path-free.
			referenceModules = game:GetService("ReplicatedStorage"):FindFirstChild("LuauUIReference"),
			-- Live stage re-dress seam for the reference proofs: the proof hands
			-- DATA, the runner does the engine work through the same shared
			-- materializer the post-present pass uses. Resolves the controller
			-- lazily so an observer wired at build time works after present.
			stage = {
				apply = function(nodePath: string, content: any): string
					local built = session.built
					if built == nil or built.handle == nil then
						return "not-presented"
					end
					return applyStageContent((built.handle :: any).controller, nodePath, content)
				end,
			},
			-- ...and the same live seam for a FOREIGN box (ADR-0034), so a scenario's
			-- own buttons can adopt (and be refused) while the surface is up
			foreign = {
				adopt = function(nodePath: string, content: any): string
					local built = session.built
					if built == nil or built.handle == nil then
						return "not-presented"
					end
					return applyForeignContent((built.handle :: any).controller, nodePath, content)
				end,
			},
			themePackages = (function(): { [string]: any }
				local out: { [string]: any } = {}
				local folder = game:GetService("ReplicatedStorage"):FindFirstChild("LuauUIThemes")
				if folder ~= nil then
					for _, mod in folder:GetChildren() do
						if mod:IsA("ModuleScript") then
							out[mod.Name] = require(mod) :: any
						end
					end
				end
				return out
			end)(),
			-- The adapter's decoration-slot surface (ADR-0019 §5, package 3).
			themeChrome = {
				setPackage = function(package: any?): boolean
					local a = deps.adapter :: any
					return if a.setThemePackage ~= nil then a.setThemePackage(package) else false
				end,
				census = function(): any
					local a = deps.adapter :: any
					return if a.chromeCensus ~= nil then serializeValue(a.chromeCensus()) else { unsupported = true }
				end,
				-- the decode judgement beside the ledger it explains (RS-A16-D5):
				-- whether the engine was ever ASKED to decode each art instance, so a
				-- condemned asset can be told from art the player cannot see
				artJudgement = function(): any
					local a = deps.adapter :: any
					return if a.chromeArtJudgement ~= nil
						then serializeValue(a.chromeArtJudgement())
						else { unsupported = true }
				end,
				setAssetLoaded = function(name: string, ok: boolean): boolean
					local a = deps.adapter :: any
					if a.setChromeAssetLoaded == nil then
						return false
					end
					a.setChromeAssetLoaded(name, ok)
					return true
				end,
				assetsToPreload = function(policy: string): any
					local a = deps.adapter :: any
					return if a.themeAssetsToPreload ~= nil then a.themeAssetsToPreload(policy) else {}
				end,
				-- THE SIXTH VARIANT STATE (ADR-0020 R2). No control publishes an
				-- error state yet (P3's wiring), so the adapter exposes the seam and
				-- the scenario drives it — which is what lets the `luau-state-error`
				-- art rules be proven APPLIED rather than merely emitted.
				setErrorState = function(path: string, on: boolean): boolean
					local a = deps.adapter :: any
					return if a.setChromeErrorState ~= nil then a.setChromeErrorState(path, on) else false
				end,
			},
			-- ENGINE TELEMETRY (roadmap Step 4, metric ledger M1..M5). Runner-owned
			-- like every other engine seam, so scenario modules stay engine-free.
			-- This is the ONLY place in the repository that can answer M1 (real
			-- frame work) at all — headless Lune renders no frame — and it answers
			-- it honestly: a fixed window of Heartbeat deltas on THIS host, with
			-- the sentence that says so travelling with the number.
			telemetry = {
				-- p50/p95/p99 of Heartbeat deltas over `frames` frames. This is
				-- WHOLE-frame work (everything the client does), not LuauUI's
				-- share; the two are recorded separately and never added.
				frameWork = function(frames: number?): any
					local RunService = game:GetService("RunService")
					local Stats = game:GetService("Stats")
					local n = math.clamp(frames or 90, 10, 600)
					-- TWO DIFFERENT QUANTITIES, kept apart. A Heartbeat delta is the
					-- frame INTERVAL: under a frame-rate cap it is floor-limited by
					-- the cap and cannot resolve any work below it — which is why
					-- every row in the first capture read ~16.6ms regardless of what
					-- was on screen. The Stats timers are the engine's own frame
					-- WORK. Publishing only the interval and calling it frame work
					-- was the review's finding; both now travel together.
					local interval = table.create(n)
					local frameTime, cpu, gpu = table.create(n), table.create(n), table.create(n)
					for i = 1, n do
						interval[i] = RunService.Heartbeat:Wait() * 1000
						frameTime[i] = Stats.FrameTime * 1000
						cpu[i] = Stats.RenderCPUFrameTime * 1000
						gpu[i] = Stats.RenderGPUFrameTime * 1000
					end
					local function summarize(samples: { number }, label: string): any
						table.sort(samples)
						local sum = 0
						for _, v in samples do
							sum += v
						end
						return {
							measured = true,
							frames = n,
							p50_ms = samples[math.max(1, math.ceil(0.5 * n))],
							p95_ms = samples[math.max(1, math.ceil(0.95 * n))],
							p99_ms = samples[math.max(1, math.ceil(0.99 * n))],
							mean_ms = sum / n,
							what = label,
						}
					end
					local cpuSummary = summarize(table.clone(cpu), "headline")
					return {
						measured = true,
						frames = n,
						-- THE HEADLINE IS NAMED. Roblox exposes several frame
						-- quantities and they do not agree: in this session
						-- Stats.FrameTime read ~67ms p50 while the Heartbeat
						-- interval read ~16.7ms, and nothing here can adjudicate
						-- that. So the top-level number is the one that is
						-- unambiguous and is what a UI framework actually loads —
						-- RenderCPUFrameTime — and every other series is published
						-- beside it under its own name rather than averaged in.
						headline = "Stats.RenderCPUFrameTime",
						p50_ms = cpuSummary.p50_ms,
						p95_ms = cpuSummary.p95_ms,
						p99_ms = cpuSummary.p99_ms,
						frameTime = summarize(
							frameTime,
							"Stats.FrameTime — published under its own name and NOT called frame work: across these "
								.. "captures it read a pinned multiple of the frame interval, which looks like a units or "
								.. "cadence artifact rather than a measurement of this screen"
						),
						renderCpu = summarize(cpu, "Stats.RenderCPUFrameTime"),
						renderGpu = summarize(gpu, "Stats.RenderGPUFrameTime"),
						heartbeatInterval = summarize(
							interval,
							"RunService.Heartbeat delta — the frame INTERVAL, floor-limited by any frame-rate "
								.. "cap; NOT frame work"
						),
						-- COMPUTED, not asserted. An early capture saw Stats.FrameTime
						-- read ~67ms p50 against a ~16.7ms Heartbeat interval; a later
						-- one saw them agree. A hardcoded sentence about a
						-- disagreement would have been wrong half the time, so the
						-- record states the ratio it actually measured.
						seriesAgreement = (function()
							local ft = summarize(table.clone(frameTime), "x").p50_ms
							local hb = summarize(table.clone(interval), "x").p50_ms
							local ratio = if hb > 0 then ft / hb else 0
							return {
								frameTimeOverHeartbeatP50 = ratio,
								agree = math.abs(ratio - 1) < 0.25,
								suspiciouslyPinned = math.abs(ratio - math.floor(ratio + 0.5)) < 0.1 and ratio >= 2,
								note = "Stats.FrameTime and the Heartbeat interval measure different things and "
									.. "do not always agree; when they diverge, nothing here adjudicates it, so "
									.. "both are published under their own names and neither is called 'the' "
									.. "frame work",
							}
						end)(),
						note = "measured in a Studio Play session on the development host. It is not the frame "
							.. "work of any device, and it is not LuauUI's share of the frame — that is M2.",
					}
				end,
				-- M3: the real Instance census under the mounted surfaces.
				-- LuauUI-OWNED roots are counted separately from everything else
				-- in PlayerGui. The first live capture counted Roblox's own
				-- Freecam ScreenGui into "LuauUI's instances", which is the kind of
				-- quiet contamination that makes a cost number mean nothing.
				instances = function(): any
					local lp = Players.LocalPlayer
					local byClass: { [string]: number } = {}
					local guiObjects, roots = 0, 0
					local foreignRoots, foreignGuiObjects = {}, 0
					for _, gui in lp.PlayerGui:GetChildren() do
						if not gui:IsA("ScreenGui") then
							continue
						end
						local mine = string.sub(gui.Name, 1, 6) == "LuauUI"
						local count = 0
						for _, inst in gui:GetDescendants() do
							if inst:IsA("GuiObject") then
								count += 1
							end
							if mine then
								byClass[inst.ClassName] = (byClass[inst.ClassName] or 0) + 1
							end
						end
						if mine then
							roots += 1
							guiObjects += count
						else
							table.insert(foreignRoots, gui.Name)
							foreignGuiObjects += count
						end
					end
					return {
						measured = true,
						screenGuis = roots,
						guiObjects = guiObjects,
						byClass = byClass,
						foreign = {
							roots = foreignRoots,
							guiObjects = foreignGuiObjects,
							note = "GUIs in PlayerGui that LuauUI does not own (Roblox core scripts, other systems); "
								.. "counted separately so they never inflate LuauUI's cost",
						},
					}
				end,
				-- M4: the adapter's own connection census (screen_target). Absent
				-- on a target that does not implement it, which is RECORDED rather
				-- than reported as zero.
				connections = function(): any
					local a = deps.adapter :: any
					if a.connectionCensus == nil then
						return { measured = false, reason = "this render target implements no connection census" }
					end
					local census = a.connectionCensus()
					census.measured = true
					return census
				end,
				-- M5: memory. Stats is not answerable from every security context,
				-- so each half is probed independently and a failure is a reason
				-- rather than a zero.
				memory = function(): any
					local out: any = { measured = true, luaHeapKb = gcinfo() }
					local ok, total = pcall(function()
						return game:GetService("Stats"):GetTotalMemoryUsageMb()
					end)
					if ok then
						out.totalMb = total
					else
						out.totalMbUnavailable = tostring(total)
					end
					-- Enum.DeveloperMemoryTag.Gui, not GuiInstance — the latter does
					-- not exist, so the call threw and the pcall swallowed it: the
					-- figure was silently never taken. A failing branch now records
					-- WHY, like the total does.
					out.memoryTrackingEnabled = game:GetService("Stats").MemoryTrackingEnabled
					local okGui, guiMb = pcall(function()
						return game:GetService("Stats"):GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Gui)
					end)
					if okGui then
						out.guiMb = guiMb
						-- UNCONDITIONAL. This is the engine's whole Gui memory tag for
						-- the client process, not LuauUI's share — the same figure came
						-- back byte-identical across three different presets, viewports
						-- and layouts, which is what it looks like when a number is not
						-- about your screen. Only the DELTA around a mount is
						-- attributable. Gating this on a failure mode meant no published
						-- row ever carried it.
						out.guiMbNote = "Stats' whole Gui memory tag for the client process, NOT LuauUI's share; "
							.. "only guiMbDelta (the change across the workload) is attributable"
						if out.memoryTrackingEnabled == false then
							out.guiMbNote = out.guiMbNote
								.. ". Stats.MemoryTrackingEnabled is false, so per-tag figures are not being collected"
						end
					else
						out.guiMbUnavailable = tostring(guiMb)
					end
					out.totalMbNote = "totalMb is the whole client process on the development host, not LuauUI's share"
					return out
				end,
				clock = function(): number
					return os.clock()
				end,
				-- M6's OTHER half: when the paint actually happened. Timing
				-- "arm, inject, read" across MCP round-trips measures the
				-- orchestration, not the interaction — the first live run
				-- produced a 7.8-SECOND "input-to-visible" number that was
				-- entirely the gap between two tool calls. So both ends are
				-- timestamped INSIDE engine callbacks in the client VM: the raw
				-- event above, and the property write here. What is left between
				-- them is the interaction.
				paintWatch = (function()
					local armedAt: number? = nil
					local firstChangeAt: number? = nil
					local conn: RBXScriptConnection? = nil
					local watching: string? = nil
					return {
						arm = function(instance: Instance?, prop: string): boolean
							if conn ~= nil then
								conn:Disconnect()
								conn = nil
							end
							-- clear the WHOLE tuple together: setting armedAt before
							-- bailing on a nil instance let a later read() pair a fresh
							-- armedAt with a stale firstChangeAt from the previous arm
							armedAt, firstChangeAt, watching = nil, nil, nil
							if instance == nil then
								return false
							end
							armedAt = os.clock()
							watching = instance:GetFullName() .. "." .. prop
							conn = instance:GetPropertyChangedSignal(prop):Connect(function()
								if firstChangeAt == nil then
									firstChangeAt = os.clock()
								end
							end)
							return true
						end,
						read = function(): any
							return { armedAt = armedAt, firstChangeAt = firstChangeAt, watching = watching }
						end,
						disarm = function(): boolean
							if conn ~= nil then
								conn:Disconnect()
								conn = nil
							end
							armedAt, firstChangeAt, watching = nil, nil, nil
							return true
						end,
					}
				end)(),
				-- M6: the raw-input half of input-to-visible. A scenario can time
				-- its own handler and its own painted result, but it cannot see
				-- the NATIVE event that started the chain — that is
				-- UserInputService, which is engine, which is runner-owned.
				-- `arm()` starts listening and `last()` returns the most recent
				-- raw event with the clock reading taken inside the engine
				-- callback, so the subtraction a scenario does is real.
				-- BOTH ENDS of the gesture are recorded. An activation fires on
				-- RELEASE, so timing from InputBegan alone folds the injector's own
				-- press-to-release dwell into the result — measured live at ~100ms
				-- of a 119ms "latency", i.e. most of it. `began` and `ended` are
				-- reported separately and the latency is taken from the event that
				-- actually completed the gesture.
				rawInput = (function()
					local UserInputService = game:GetService("UserInputService")
					local began: any, ended: any = nil, nil
					local conns: { RBXScriptConnection } = {}
					local function record(input: InputObject, gameProcessed: boolean): any
						return {
							at = os.clock(),
							userInputType = tostring(input.UserInputType),
							keyCode = tostring(input.KeyCode),
							position = { x = input.Position.X, y = input.Position.Y },
							gameProcessed = gameProcessed,
						}
					end
					return {
						arm = function(): boolean
							began, ended = nil, nil
							if #conns == 0 then
								table.insert(
									conns,
									UserInputService.InputBegan:Connect(function(input, gameProcessed)
										began = record(input, gameProcessed)
									end)
								)
								table.insert(
									conns,
									UserInputService.InputEnded:Connect(function(input, gameProcessed)
										ended = record(input, gameProcessed)
									end)
								)
							end
							return true
						end,
						last = function(): any
							return began
						end,
						pair = function(): any
							return {
								began = began,
								ended = ended,
								dwellMs = if began ~= nil and ended ~= nil then (ended.at - began.at) * 1000 else nil,
							}
						end,
						disarm = function(): boolean
							for _, c in conns do
								c:Disconnect()
							end
							conns = {}
							began, ended = nil, nil
							return true
						end,
					}
				end)(),
				-- KEY LOG (roadmap Step 8). `rawInput` above keeps only the most
				-- recent began/ended pair, which is right for a single press but
				-- blind to a SEQUENCE — and a keyboard row is a sequence by
				-- definition (Tab, Tab, Shift+Tab, Space). This appends every
				-- keyboard event, in order, with the `gameProcessed` flag beside
				-- it: that flag is the free second opinion on whether the engine
				-- considered the press consumed by the UI, and it is the one
				-- signal that separates "our binding fired" from "the key also
				-- went somewhere else".
				keyLog = (function()
					local UserInputService = game:GetService("UserInputService")
					local events: { any } = {}
					local conns: { RBXScriptConnection } = {}
					local function record(phase: string, input: InputObject, gameProcessed: boolean)
						if input.UserInputType ~= Enum.UserInputType.Keyboard then
							return
						end
						table.insert(events, {
							n = #events + 1,
							phase = phase,
							at = os.clock(),
							keyCode = tostring(input.KeyCode),
							userInputType = tostring(input.UserInputType),
							gameProcessed = gameProcessed,
						})
					end
					return {
						arm = function(): boolean
							table.clear(events)
							if #conns == 0 then
								table.insert(
									conns,
									UserInputService.InputBegan:Connect(function(input, processed)
										record("began", input, processed)
									end)
								)
								table.insert(
									conns,
									UserInputService.InputEnded:Connect(function(input, processed)
										record("ended", input, processed)
									end)
								)
							end
							return true
						end,
						read = function(): { any }
							return events
						end,
						disarm = function(): boolean
							for _, c in conns do
								c:Disconnect()
							end
							conns = {}
							table.clear(events)
							return true
						end,
					}
				end)(),
				-- one frame, so a caller can order "write, then let the engine
				-- draw, then read" without importing RunService
				step = function(): number
					return game:GetService("RunService").Heartbeat:Wait() * 1000
				end,
			},
			-- the mounted Instance for a LuauUI path. Engine access stays
			-- runner-owned; a scenario uses this only to hand an instance BACK to
			-- another runner seam (paintWatch), never to write to it.
			instanceAt = function(path: string): Instance?
				local a = deps.adapter :: any
				return if a.getInstance ~= nil then a.getInstance(path) else nil
			end,
			-- solved geometry for named paths, so a scenario's own report can
			-- PAIR geometry with the theme identity that produced it instead of
			-- leaving the reader to join two sections of the dump by hand
			geometry = function(paths: { string }): { [string]: any }
				local out: { [string]: any } = {}
				local a = deps.adapter :: any
				for _, path in paths do
					local inst = a.getInstance and a.getInstance(path)
					if inst ~= nil and inst:IsA("GuiObject") then
						out[path] = {
							x = inst.AbsolutePosition.X,
							y = inst.AbsolutePosition.Y,
							w = inst.AbsoluteSize.X,
							h = inst.AbsoluteSize.Y,
						}
					end
				end
				return out
			end,
			-- the last solve's COMPOSITION RESOLUTION for a node (ADR-0023), so a
			-- scenario's own report can say which arrangement won and why every
			-- richer candidate lost — the one piece of an adaptive screen a
			-- screenshot structurally cannot show. Same lazy-handle read the
			-- report's `diagnostics` block makes, and nil when nothing resolved.
			composition = function(path: string?): any
				local handle = session.built and session.built.handle
				local controller = handle and handle.controller
				if controller == nil or controller.compositionAt == nil then
					return nil
				end
				local ok, d = pcall(controller.compositionAt, path)
				return if ok then d else nil
			end,
			-- TODO(package-2 seam): src/client/theme_controller.luau —
			-- install/swap/current/inspect/onChange (ADR-0019 §7). LATE-BOUND on
			-- purpose: this package must not import a module that may not exist
			-- yet, and the scenario must degrade to "controller absent" rather
			-- than failing to mount. Delete the pcall the day the module lands.
			themeController = function(): any
				local ok, module = pcall(function()
					return require(game:GetService("ReplicatedStorage").LuauUI.client.theme_controller) :: any
				end)
				return if ok then module else nil
			end,
			-- engine text calibration (NS-A10): yields; returns the applied table
			runTextCalibration = function(fonts: { string }?): { [string]: number }
				local calibration = require(game:GetService("ReplicatedStorage").LuauUI.client.text_calibration) :: any
				return calibration.run(fonts)
			end,
			-- native-stylesheets seams (NSS-A2..A7): runner-owned so scenario
			-- modules stay engine-free. These edit the SAME DataModel objects
			-- the Style Editor edits (rule SetProperties / token attributes) —
			-- the automated stand-in for a designer edit (NSS-A3); the human
			-- editor-workflow check remains NSS-P1.
			nativeStyle = {
				info = function(): any
					local info = (deps.adapter :: any).nativeStyleInfo and (deps.adapter :: any).nativeStyleInfo()
						or { active = false }
					return {
						active = info.active,
						stamp = info.stamp,
						seeded = info.seeded,
						activeTheme = info.activeTheme,
					}
				end,
				resolveToken = function(theme: string, name: string): any
					local info = (deps.adapter :: any).nativeStyleInfo()
					local ts = info.themes and info.themes[theme]
					return if ts ~= nil then serializeValue(ts:GetAttribute(name)) else nil
				end,
				editToken = function(theme: string, name: string, r: number, g: number, b: number): boolean
					local info = (deps.adapter :: any).nativeStyleInfo()
					local ts = info.themes and info.themes[theme]
					if ts == nil then
						return false
					end
					ts:SetAttribute(name, Color3.new(r, g, b))
					return true
				end,
				-- value: { r, g, b } literal or a "$Token" reference string —
				-- the same edit surface the Style Editor's property rows drive
				editRuleProperty = function(ruleName: string, prop: string, value: any): boolean
					local info = (deps.adapter :: any).nativeStyleInfo()
					if info.sheet == nil then
						return false
					end
					for _, child in info.sheet:GetChildren() do
						if child:IsA("StyleRule") and child.Name == ruleName then
							local props = child:GetProperties()
							props[prop] = if type(value) == "string"
								then value
								else Color3.new(value.r, value.g, value.b)
							child:SetProperties(props)
							return true
						end
					end
					return false
				end,
				setTheme = function(name: string)
					(deps.adapter :: any).setNativeTheme(name)
				end,
				setTransitionsEnabled = function(on: boolean)
					(deps.adapter :: any).setNativeTransitionsEnabled(on)
				end,
				-- THE WHOLE SUBTREE of a mounted node, by LuauUI path: names,
				-- ZIndex, tags, geometry, plain-vs-styled reads. A layer ladder is
				-- N children of one node, so "the adapter built what the plan asked
				-- for" is one read rather than N (rich-skinning-v2 RS-A1/A2/A3).
				dumpNode = function(path: string): any
					local inst = (deps.adapter :: any).getInstance and (deps.adapter :: any).getInstance(path)
					if inst == nil then
						return { missing = path }
					end
					return dumpTree(inst)
				end,
				-- drive the ENGINE's own text focus, which is what fires the
				-- TextBox Focused/FocusLost the chrome yield listens to. A scripted
				-- CaptureFocus is downstream-action evidence for the CARET, but the
				-- yield itself is engine-event-driven and observed through the tag.
				focusTextBox = function(path: string, on: boolean): boolean
					local inst = (deps.adapter :: any).getInstance and (deps.adapter :: any).getInstance(path)
					if inst == nil or not inst:IsA("TextBox") then
						return false
					end
					if on then
						(inst :: TextBox):CaptureFocus()
					else
						(inst :: TextBox):ReleaseFocus()
					end
					return true
				end,
				-- resolved styled read for a mounted node (by LuauUI path)
				styledOf = function(path: string, prop: string): any
					local inst = (deps.adapter :: any).getInstance and (deps.adapter :: any).getInstance(path)
					if inst == nil then
						return nil
					end
					local ok, v = pcall(function()
						return (inst :: any):GetStyled(prop)
					end)
					return if ok then serializeValue(v) else "ERR:" .. tostring(v)
				end,
				-- mount identity: stable per-REFERENCE ids from a runner-owned
				-- registry (GetDebugId is plugin-locked in play), so a
				-- repaint-vs-remount claim is machine-checkable: same instance
				-- object => same id; a recreated instance gets a new id
				mountIdentity = function(): { [string]: string }
					local out: { [string]: string } = {}
					local lp = Players.LocalPlayer
					for _, gui in lp.PlayerGui:GetChildren() do
						if gui:IsA("ScreenGui") then
							for _, inst in gui:GetDescendants() do
								if inst:IsA("GuiObject") then
									local id = identityIds[inst]
									if id == nil then
										identityCounter += 1
										id = "i" .. identityCounter
										identityIds[inst] = id
									end
									out[inst.Name] = id
								end
							end
						end
					end
					return out
				end,
			},
		}
		session.built = scenario.build(ctx)
		if session.built.screen ~= nil and session.built.handle == nil then
			session.built.handle = deps.presenter.present(session.built.screen, session.built.present)
		end
		-- A KEYBOARD-FIRST SCENARIO RELEASES THE DEFAULT CAMERA'S ARROW KEYS.
		-- Roblox's default CameraModule binds Left/Right (action name
		-- `RbxCameraKeypress`) and SINKS them, so horizontal arrow navigation dies
		-- in any place running the default camera (api.md `newPresenter`; measured
		-- 2026-08-06). A scenario that declares `keyboardFirst = true` is a
		-- UI-driven surface with no camera of its own, so the runner — the one
		-- engine-side seam — releases the binding for the session. Opt-in per
		-- scenario, so prior gates' scenarios keep the environment they passed in.
		if (scenario :: any).keyboardFirst == true then
			pcall(function()
				game:GetService("ContextActionService"):UnbindAction("RbxCameraKeypress")
			end)
		end
		-- STAGE CONTENT, MATERIALIZED BY THE RUNNER (swiftui-reference-app-validation).
		-- A reference proof stays engine-free, so its 3D stage content arrives as
		-- DATA: `built.stageContent = { [nodePath] = { camera?, lighting?, parts? } }`
		-- ({ shape, size = {x,y,z}, color = {r,g,b}, cframe = { pos, lookAt? },
		-- transparency? }). A nil host (headless twin, adapter without the seam)
		-- is recorded, never an error — the proof's declared fallback plate is
		-- the visible behavior there.
		if session.built.stageContent ~= nil and session.built.handle ~= nil then
			local controller = (session.built.handle :: any).controller
			local applied: { [string]: string } = {}
			for nodePath, content in session.built.stageContent :: { [string]: any } do
				applied[nodePath] = applyStageContent(controller, nodePath, content)
			end
			session.built.stageApplied = applied
		end
		-- FOREIGN CONTENT, same contract (ADR-0034): `built.foreignContent =
		-- { [nodePath] = { kind, … } }`. A nil host is recorded as a status string,
		-- never an error — the declared fallback there is the box's own plate.
		if session.built.foreignContent ~= nil and session.built.handle ~= nil then
			local controller = (session.built.handle :: any).controller
			local applied: { [string]: string } = {}
			for nodePath, content in session.built.foreignContent :: { [string]: any } do
				applied[nodePath] = applyForeignContent(controller, nodePath, content)
			end
			session.built.foreignApplied = applied
		end
	end

	local function teardown()
		if session.built == nil then
			return
		end
		-- BOTH, not either/or (director review 2026-07-24). A scenario's `dispose`
		-- releases the CONTROLS it owns; the presenter handle owns the mounted
		-- ScreenGui. The `elseif` meant that any scenario declaring a dispose (all
		-- the interesting ones) never had its handle dismissed, so `reset()` built a
		-- second tree on top of the first and left both live and painting. It showed
		-- up as ghosted glyphs — a stale "10" behind a fresh "6" — and any geometry
		-- read after a reset was being taken from a screen with two overlapping UIs.
		if session.built.dispose ~= nil then
			session.built.dispose()
		end
		-- `dismiss` is a PRESENTER method taking the handle, not a method on the
		-- handle. The old `session.built.handle.dismiss()` branch referenced a
		-- field that has never existed, so it could not fire even when it was
		-- reached: every reset() left its ScreenGui mounted and painting.
		if session.built.handle ~= nil and deps.presenter.dismiss ~= nil then
			deps.presenter.dismiss(session.built.handle)
		end
		session.built = nil
	end

	local api = {}

	function api.list(): { string }
		return registry.order
	end

	function api.steps(): { string }
		local names = {}
		if session.built and session.built.steps then
			for stepName in session.built.steps do
				table.insert(names, stepName)
			end
			table.sort(names)
		end
		return names
	end

	function api.step(stepName: string, payload: string?): any
		assert(session.built, "scenario not built")
		local fn = session.built.steps and session.built.steps[stepName]
		assert(fn ~= nil, `no step '{stepName}' in scenario '{name}'`)
		workspace:SetAttribute("LuauUI_ScenarioState", "running:" .. stepName)
		local ok, result = pcall(fn, session.built, payload)
		table.insert(session.stepLog, {
			step = stepName,
			at = os.clock(),
			result = if ok then serializeValue(result) else "ERROR:" .. tostring(result),
		})
		workspace:SetAttribute("LuauUI_ScenarioState", if ok then "ready" else "failed:" .. stepName)
		if not ok then
			error(result)
		end
		deps.presenter.refresh()
		return result
	end

	function api.freezeEnv()
		if not session.envFrozen and deps.unbindEnv ~= nil then
			deps.unbindEnv()
			session.envFrozen = true
		end
		return session.envFrozen
	end

	-- declared env seam (contract §5: "change supported viewport, orientation,
	-- environment, accessibility, and fixture facts through declared test seams").
	-- The five-view device matrix drives each RESOLVED preset's facts through here.
	-- Requires freezeEnv() first, or the live engine binding overwrites them.
	-- Deserialises the shapes the environment expects (rects and inset tables).
	function api.setEnv(facts: { [string]: any })
		-- LOUD, not lossy (platform review N4): an unfrozen env means the live
		-- engine binding will overwrite these facts on the next signal — the
		-- write would look applied and silently revert, which is exactly the
		-- instrument failure that left a device row proving the wrong input
		-- class. And a fact the environment refuses is REPORTED, not dropped:
		-- the caller sees { applied, failed } and can gate its row on both.
		if not session.envFrozen then
			error(
				"runner.setEnv: freezeEnv() first — an unfrozen env re-overwrites every fact on the next engine signal",
				0
			)
		end
		local applied: { string } = {}
		local failed: { [string]: string } = {}
		for key, value in facts do
			local ok, err = pcall(function()
				deps.env:set(key, value)
			end)
			if ok then
				table.insert(applied, key)
			else
				failed[key] = tostring(err)
			end
		end
		table.sort(applied)
		deps.presenter.refresh()
		return { applied = applied, failed = failed }
	end

	function api.reset()
		teardown()
		session.stepLog = {}
		build()
		deps.presenter.refresh()
		workspace:SetAttribute("LuauUI_ScenarioState", "ready")
		return true
	end

	function api.report(opts: { tree: boolean? }?): string
		deps.presenter.refresh()
		local lp = Players.LocalPlayer
		local envFacts: { [string]: any } = {}
		for _, k in ENV_FACT_KEYS do
			local ok, sig = pcall(function()
				return deps.env:get(k)
			end)
			if ok and sig ~= nil then
				envFacts[k] = serializeValue(sig:get())
			end
		end
		local envDerived: { [string]: any } = {}
		for _, k in ENV_DERIVED_KEYS do
			local ok, sig = pcall(function()
				return deps.env:get(k)
			end)
			if ok and sig ~= nil then
				envDerived[k] = serializeValue(sig:get())
			end
		end
		local trees = {}
		if opts == nil or opts.tree ~= false then
			for _, gui in lp.PlayerGui:GetChildren() do
				if gui:IsA("ScreenGui") then
					table.insert(trees, { root = gui.Name, nodes = dumpTree(gui) })
				end
			end
		end
		-- SOLVER DIAGNOSTICS (preferred-text sweep, 2026-07-24): the report used
		-- to carry geometry but never the solver's own complaints about it, so a
		-- tree that overflowed its screen looked identical to one that fit. A row
		-- claiming a layout is correct must be able to show the solver agreed.
		local diagnostics: { any }? = nil
		do
			local handle = session.built and session.built.handle
			local controller = handle and handle.controller
			if controller ~= nil and controller.diagnostics ~= nil then
				local ok, d = pcall(controller.diagnostics)
				if ok then
					diagnostics = d
				end
			end
		end
		-- EXACT TEXT MEASUREMENT (text-measurement milestone): the vocabulary the
		-- engine has actually measured for this session. A row claiming its boxes
		-- match what the engine draws has to be able to show the widths it used,
		-- rather than leaving the reader to infer them from geometry. Requires
		-- the SAME module instance the solver uses, which is why it is read here
		-- (the runner shares the client VM) and not from the MCP command VM.
		local textMeasurement: any = nil
		do
			local ok, tm = pcall(function()
				return require(game:GetService("ReplicatedStorage").LuauUI.layout.text_metrics) :: any
			end)
			if ok and tm ~= nil and tm.measuredDump ~= nil then
				textMeasurement = { measuredWords = tm.measuredCount(), words = tm.measuredDump() }
				-- and the corrections the settled re-read made to the engine's
				-- boot answers: without these the widths above would be the
				-- wrong-but-stable ones the API hands out during startup
				local okp, premeasure = pcall(function()
					return require(game:GetService("ReplicatedStorage").LuauUI.client.text_premeasure) :: any
				end)
				if okp and premeasure ~= nil and premeasure.corrections ~= nil then
					textMeasurement.bootWindowCorrections = premeasure.corrections
				end
			end
		end
		-- the per-text-node facts of the last solve (font, lines, truncated,
		-- disclose/reveal, policy) so an instrument judging TextFits can tell a
		-- DECLARED truncation-with-disclosure from a genuine unfit finding
		-- (swiftui-reference-app-validation matrix, 2026-08-08)
		local textPolicies: any = nil
		do
			local handle = session.built and session.built.handle
			local controller = handle and (handle :: any).controller
			if controller ~= nil and controller.textAt ~= nil then
				local ok2, facts = pcall(controller.textAt)
				if ok2 and type(facts) == "table" then
					local out: { [string]: any } = {}
					for path, f in facts do
						out[path] = {
							truncated = (f :: any).truncated,
							disclose = (f :: any).disclose,
							reveal = (f :: any).reveal,
							policy = (f :: any).policy,
						}
					end
					textPolicies = out
				end
			end
		end
		local report = {
			schema = "luauui-scenario/1",
			scenario = name,
			diagnostics = diagnostics,
			textPolicies = textPolicies,
			textMeasurement = textMeasurement,
			ledgerRows = scenario.ledgerRows or {},
			version = LuauUI.VERSION,
			sourceStamp = workspace:GetAttribute("LuauUI_SourceStamp"),
			viewport = serializeValue(workspace.CurrentCamera.ViewportSize),
			envFrozen = session.envFrozen,
			env = envFacts,
			derived = envDerived,
			focusPath = deps.presenter.focus.focused:get(),
			selectedObject = if GuiService.SelectedObject then GuiService.SelectedObject:GetFullName() else nil,
			stepLog = session.stepLog,
			custom = if session.built and session.built.report then session.built.report() else nil,
			instanceTrees = trees,
		}
		return HttpService:JSONEncode(report)
	end

	build()
	_G.LuauUIScenario = api
	-- The MCP's execute_luau runs in a DIFFERENT Luau VM than this LocalScript,
	-- so _G does not cross. Publish the API as BindableFunctions the command VM
	-- can Invoke (same client DataModel). JSON-in/JSON-out for table safety.
	local apiFolder = Instance.new("Folder")
	apiFolder.Name = "LuauUIScenarioAPI"
	for fnName, impl in
		{
			list = function(_arg: string?)
				return HttpService:JSONEncode(api.list())
			end,
			steps = function(_arg: string?)
				return HttpService:JSONEncode(api.steps())
			end,
			step = function(arg: string?)
				-- "name" or "name:payload" — BindableFunction Invoke carries ONE
				-- string here, so a parameterized step rides a colon suffix
				-- (e.g. "installPackage:fantasy_parchment")
				local stepName, payload = string.match(arg :: string, "^([^:]+):(.*)$")
				if stepName == nil then
					stepName = arg :: string
				end
				return HttpService:JSONEncode({ result = api.step(stepName :: string, payload) })
			end,
			report = function(arg: any)
				local opts = if type(arg) == "table"
					then arg
					elseif type(arg) == "string" and arg ~= "" then HttpService:JSONDecode(arg)
					else nil
				return api.report(opts)
			end,
			reset = function(_arg: string?)
				return HttpService:JSONEncode({ ok = api.reset() })
			end,
			freezeEnv = function(_arg: string?)
				return HttpService:JSONEncode({ frozen = api.freezeEnv() })
			end,
			-- EXACT TEXT MEASUREMENT instrument (text-measurement milestone): run
			-- the ADAPTER'S OWN premeasurement path, in the client VM the solver
			-- runs in, for an arbitrary word. Without this, a stored width can
			-- only be compared against a measurement taken in the MCP's separate
			-- command VM, which conflates "the store is stale" with "the two VMs
			-- measure differently" — and those need different fixes.
			measureNow = function(arg: string?)
				local spec = HttpService:JSONDecode(arg :: string)
				local premeasure = require(game:GetService("ReplicatedStorage").LuauUI.client.text_premeasure) :: any
				local done = false
				local results: any = nil
				premeasure.measure(spec.requests, function(r)
					results = r
					done = true
				end)
				local waited = 0
				while not done and waited < 600 do
					task.wait()
					waited += 1
				end
				return HttpService:JSONEncode({ results = results, frames = waited })
			end,
			setEnv = function(arg: string?)
				local facts = HttpService:JSONDecode(arg :: string)
				-- rebuild the plain shapes the environment expects from JSON
				if facts.viewportRect ~= nil then
					local r = facts.viewportRect
					facts.viewportRect = { x = r.x, y = r.y, w = r.w, h = r.h }
				end
				return HttpService:JSONEncode(api.setEnv(facts))
			end,
		} :: { [string]: (string?) -> string }
	do
		local bf = Instance.new("BindableFunction")
		bf.Name = fnName
		bf.OnInvoke = impl
		bf.Parent = apiFolder
	end
	apiFolder.Parent = workspace
	workspace:SetAttribute("LuauUI_ScenarioReady", true)
	workspace:SetAttribute("LuauUI_ScenarioState", "ready")
	workspace:SetAttribute("LuauUI_Version", LuauUI.VERSION)
	print(`[LuauUI Scenario] '{name}' ready ({LuauUI.VERSION}); steps: {table.concat(api.steps(), ",")}`)
	return api
end

return Runner
