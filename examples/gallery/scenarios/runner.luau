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
--   _G.FacetScenario.list()          -> registered scenario names
--   _G.FacetScenario.steps()         -> this scenario's steps, plus the generic ones
--   _G.FacetScenario.step(name)      -> run a named scenario step, returns its result
--   _G.FacetScenario.states()        -> the states this surface declares it can be
--                                        OPENED into (expand/menu/tray/disclosure)
--   _G.FacetScenario.openState(id)   -> open one of them; a sweep that only judges
--                                        the settled screen never sees the rest
--   _G.FacetScenario.report(opts?)   -> JSON string (facet-scenario/1)
--   _G.FacetScenario.reset()         -> teardown + rebuild the scenario fresh
--   _G.FacetScenario.freezeEnv()     -> detach live engine env binding so
--                                        env:set(...) overrides hold steady
-- Workspace attributes: Facet_Scenario (selection, set BEFORE Play),
-- Facet_ScenarioReady, Facet_ScenarioState, Facet_SourceStamp (injector),
-- Facet_Version.

local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

--[[ WHAT A FACET-OWNED ROOT IS NAMED. The adapter names every ScreenGui it
	creates `Facet_<screen id>` (`screen_target`; a billboard root is
	`Facet_BB_<id>`, which this prefix also covers). Named once, and every test
	for it reads its LENGTH off the literal — see the M3 census below for what a
	hand-counted six cost when the rename shortened the literal to five. ]]
local FACET_ROOT_PREFIX = "Facet_"

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
	-- flat vs world presentation; "screen" on every row today, and
	-- recorded so the day it is not, the rows say so
	"presentationProfile",
}

local function serializeValue(v: any, seen: { [any]: boolean }?): any
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
		-- CYCLE GUARD (2026-08-21): a step that returns a self-referential table
		-- used to chase this function into a stack overflow that killed the whole
		-- api.step call — the serializer is a REPORTER, so a bad value must come
		-- back named, never take the bridge down with it
		local marks = seen or {}
		if marks[v] then
			return "<cycle>"
		end
		marks[v] = true
		local out = {}
		for k, vv in v do
			out[tostring(k)] = serializeValue(vv, marks)
		end
		marks[v] = nil
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
	-- the IMAGE properties joined the list for rich-skinning-v2:
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
		-- carry the Facet_DeclaredOverride attribute)
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
		if inst:GetAttribute("Facet_DeclaredOverride") == true then
			d.declaredOverride = true
		end
		-- PAINT CLAIMS: the engine properties this node took
		-- from the sheet because no rule can carry their value (a `tint` blend, an
		-- identity hue, an authored `scaleMode`). Dumped BESIDE `styled` on purpose —
		-- a claimed property is EXPECTED to diverge from the sheet-resolved value, and
		-- this is what tells the defeat audit that the divergence was declared.
		local claims = inst:GetAttribute("Facet_PaintClaims")
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
	local Facet = deps.Facet
	local registry = deps.registry
	local name = deps.scenarioName :: string
	local mod = registry.modules[name]
	-- the shared foreign-content materializer; see the note at
	-- `applyForeignContent` below for why it is not a local in this file
	local foreign_instances = require(registry.foreignInstances) :: any
	if mod == nil then
		workspace:SetAttribute("Facet_ScenarioState", "failed:unknown-scenario:" .. name)
		error(`[Facet Scenario] unknown scenario '{name}' (registered: {table.concat(registry.order, ",")})`)
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

	-- Shared stage-content materializer (reference-app-validation): the
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

	-- FOREIGN CONTENT (UI.Foreign) is materialized by a SHARED sibling
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
			Facet = Facet,
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
				local transport = require(game:GetService("ReplicatedStorage").Facet.client.roblox_resources) :: any
				return transport.bind(provider)
			end,
			-- WORLD-ANCHORED PRESENTATION (row SF-W1). A BillboardGui, a
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
						local billboardTarget = require(ReplicatedStorage.Facet.client.billboard_target) :: any
						local canvas = spec.canvas or { w = 320, h = 220 }
						local part = Instance.new("Part")
						part.Name = "Facet_BillboardAnchor"
						part.Anchored = true
						part.CanCollide = false
						part.CanQuery = false
						part.Size = Vector3.new(2, 2, 2)
						part.Transparency = 0.6
						part.CFrame = workspace.CurrentCamera.CFrame * CFrame.new(0, 0, -18)
						part.Parent = workspace
						-- display-only, but PlayerGui-parented with an Adornee: that is the
						-- documented topology, and a fixture that used another
						-- parent would be proving a path no consumer uses
						local adapter = billboardTarget.new({
							parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
							adornee = part,
							canvas = canvas,
							alwaysOnTop = true,
						})
						-- the solver's world IS the canvas (scale units mean studs here)
						local billboardEnv = Facet.newEnvironment(deps.core)
						billboardEnv:set("viewportRect", billboardTarget.canvasRect(canvas))
						local root = Facet.mount(deps.core, spec.blueprint)
						local controller =
							Facet.renderer.attach(deps.core, root, billboardEnv, adapter, { rootPolicy = "edgeToEdge" })
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
						if inst.Name == "Facet_BillboardAnchor" then
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
			--[[ ── THE WORLD SURFACE (design §4, §5, §10) ──────────────────

				A CONSOLE A PLAYER WALKS UP TO AND USES, and everything about it that
				touches an Instance is here rather than in the scenario, exactly as
				`ctx.billboard` above is: the scenario declares the terminal and drives
				the steps, and this is the only place that reaches the engine on its
				behalf. On a host with no engine the seam is simply absent and every
				scenario step says so instead of pretending it ran.

				WHAT THIS ONE OWNS THAT THE BILLBOARD DOES NOT. A billboard is
				display-only, so it can live on a raw `renderer.attach`. This surface is
				OPERATED, so it needs a whole second Facet host — its own core, env,
				render target, input system and presenter — and the reason it needs its
				OWN CORE rather than sharing `deps.core` is not style: `environment.new`
				publishes onto the core it is built on, and two live environments on one
				core make `surface_env.find` answer "ambiguous", at which point every
				adaptive control REFUSES TO CONSTRUCT. `client.host` assembles all six
				pieces and disposes them in the right order, so this seam uses it rather
				than re-deriving the sequence.

				THE FIXTURE ITSELF IS THE SERVER'S (design §10). A console this client
				built would be a console only this client can see and a door only this
				client can open, so `examples/gallery/server` builds the outpost, owns
				the allocation, and is asked for a character — `CharacterAutoLoads` is
				false in the showcase and only a server can load one anyway.
			]]
			surface = (function()
				local state: any = nil
				local api: any = {}
				local pending: { any } = {}
				local exitLog: { any } = {}

				--[[ MEASURED, so nobody has to re-derive it: for an unrotated part
					`Front` is the -Z face, which is why a camera looking along -Z sees
					`Back`. A surface on the wrong face renders perfectly, measures
					perfectly, and can never be clicked — indistinguishable from an
					engine that does not support this at all. ]]
				local FACE_NORMALS: { [string]: Vector3 } = {
					Front = Vector3.new(0, 0, -1),
					Back = Vector3.new(0, 0, 1),
					Left = Vector3.new(-1, 0, 0),
					Right = Vector3.new(1, 0, 0),
					Top = Vector3.new(0, 1, 0),
					Bottom = Vector3.new(0, -1, 0),
				}

				-- the device facts the world surface mirrors from the SCREEN host's
				-- environment. Not the viewport and not the insets: the solver's world
				-- IS the canvas, and a console has no notch.
				local MIRRORED_FACTS =
					{ "preferredInput", "capabilities", "reducedMotion", "preferredTextSize", "displaySize" }

				function api.available(): boolean
					return true
				end

				local function note(kind: string, info: any?)
					table.insert(exitLog, { kind = kind, at = os.clock(), info = serializeValue(info) })
				end

				local function remote(): any
					return game:GetService("ReplicatedStorage"):FindFirstChild("Facet_Outpost")
				end

				function api.command(kind: string, payload: any?): any
					local ev = remote()
					if ev == nil then
						return { sent = false, reason = "no Facet_Outpost RemoteEvent (is the server side mapped?)" }
					end
					local body = if payload ~= nil then table.clone(payload) else {}
					body.kind = kind
					if state ~= nil and body.token == nil then
						body.token = state.token
					end
					ev:FireServer(body)
					return { sent = true, kind = kind }
				end

				local function characterDistance(): number?
					if state == nil or state.console == nil or state.console.Parent == nil then
						return nil
					end
					local character = Players.LocalPlayer.Character
					local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
					if root == nil or not root:IsA("BasePart") then
						return nil
					end
					return (root.Position - state.console.Position).Magnitude
				end

				--[[ THE FACE ASSERTION, run before anything is measured. The spike lost
					two rounds to a face error, so the fixture states which way its chosen
					face actually points and the report carries the number. ]]
				function api.faceCheck(): any
					if state == nil or state.console == nil or state.console.Parent == nil then
						return { checked = false, reason = "no console" }
					end
					local console = state.console
					local normal = console.CFrame:VectorToWorldSpace(FACE_NORMALS[state.faceName])
					local character = Players.LocalPlayer.Character
					local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
					local from = if root ~= nil and root:IsA("BasePart")
						then root.Position
						else workspace.CurrentCamera.CFrame.Position
					local toViewer = (from - console.Position)
					local dot = if toViewer.Magnitude > 0 then normal:Dot(toViewer.Unit) else 0
					return {
						checked = true,
						face = state.faceName,
						worldNormal = serializeValue(normal),
						viewer = if root ~= nil then "character" else "camera",
						dot = dot,
						-- the whole point: a face whose normal points AWAY from where a
						-- player stands is the silent failure this check exists to catch
						pointsAtViewer = dot > 0,
					}
				end

				local function mirrorFacts(target: any)
					for _, fact in MIRRORED_FACTS do
						local ok, value = pcall(function()
							return deps.env:get(fact):get()
						end)
						if ok then
							target:set(fact, value)
						end
					end
				end

				--[[ EVERY EXIT LANDS HERE. Cancel, the Exit control, walking out of
					range, losing line of sight, a removed character, a destroyed or
					streamed-out adornee, a scenario switch and teardown: eight ways in,
					one way out. Each resigns the responder, cancels in-flight input, and
					tells the scenario which one it was. ]]
				function api.release(reason: string): any
					if state == nil then
						return { released = false, reason = "not open" }
					end
					if not state.engaged then
						return { released = false, reason = "not engaged", last = state.lastExit }
					end
					state.engaged = false
					state.lastExit = reason
					-- 1. the framework's own resign: context disabled, sink dropped,
					--    focus scope no longer the one receiving Navigate/Activate
					if state.handle ~= nil and state.handle.responder:get() == "engaged" then
						pcall(function()
							state.handle.resign()
						end)
					end
					-- 2. any armed press on the surface is cancelled rather than left
					--    holding the pointer
					if state.handle ~= nil and state.handle.controller ~= nil then
						pcall(function()
							state.handle.controller.cancelArmed("surface-exit")
						end)
					end
					-- 3. the terminal's own state machine, which also resets a request
					--    the server may never answer
					if state.built ~= nil and state.built.onExit ~= nil then
						pcall(state.built.onExit, reason)
					end
					-- 4. and the server stops believing this client holds the console
					api.command("release")
					note("release", { reason = reason })
					if state.spec.onRelease ~= nil then
						pcall(state.spec.onRelease, reason)
					end
					return { released = true, reason = reason }
				end

				function api.engage(source: string?): any
					if state == nil then
						return { engaged = false, reason = "not open" }
					end
					if state.engaged then
						return { engaged = true, already = true }
					end
					state.engaged = true
					state.lastExit = nil
					if state.handle ~= nil then
						pcall(function()
							state.handle.engage()
						end)
					end
					if state.built ~= nil and state.built.onEngage ~= nil then
						pcall(state.built.onEngage, state.allocation)
					end
					note("engage", { source = source or "step" })
					if state.spec.onEngage ~= nil then
						pcall(state.spec.onEngage, source)
					end
					return { engaged = true, source = source or "step" }
				end

				local function handleReply(payload: any)
					if state == nil or type(payload) ~= "table" then
						return
					end
					table.insert(pending, serializeValue(payload))
					if payload.kind == "session" then
						state.token = payload.token
						state.allocation = payload.allocation
						api.engage("prompt")
					elseif payload.kind == "state" then
						state.allocation = payload.allocation
						if state.built ~= nil and state.built.onState ~= nil then
							pcall(state.built.onState, payload)
						end
					elseif payload.kind == "verdict" then
						if state.built ~= nil and state.built.onVerdict ~= nil then
							pcall(state.built.onVerdict, payload)
						end
						if payload.allocation ~= nil then
							state.allocation = payload.allocation
						end
					elseif payload.kind == "closed" then
						api.release(payload.reason or "closed")
					elseif payload.kind == "character" then
						state.character = payload.loaded == true
					end
				end

				local function wireConsole(spec: any)
					local outpost = workspace:FindFirstChild("Outpost")
					local console = if outpost ~= nil then outpost:FindFirstChild("Console") else nil
					if console == nil or not console:IsA("BasePart") then
						return nil
					end
					state.console = console
					local attachment = console:FindFirstChild("PromptAttachment")
					local prompt = if attachment ~= nil then attachment:FindFirstChild("UsePrompt") else nil
					state.prompt = prompt
					if prompt ~= nil and prompt:IsA("ProximityPrompt") then
						--[[ THE WALK-UP, AND NOTHING IS BOUND FOR IT. `Triggered` is the
							platform's own cross-input invitation — keyboard, gamepad and
							touch, with no branch written here — and the client's copy fires
							only for the player who triggered it. Facet does not wrap it, and
							this example binds nothing through ContextActionService or
							UserInputService. ]]
						table.insert(
							state.connections,
							prompt.Triggered:Connect(function(player: Player)
								if player ~= Players.LocalPlayer then
									return
								end
								--[[ THE LOCAL ECHO IS A NOTE, NOT THE ENGAGEMENT. The same
									event reached the SERVER with the same player, and the server
									answers with a session token — engaging on that token rather
									than on this event is what makes "who is at this console" the
									server's fact instead of this client's claim. ]]
								note("prompt:triggered", { player = player.Name })
							end)
						)
						--[[ TWO EXITS OUT OF ONE NATIVE SIGNAL, told apart by the thing
							that distinguishes them. `PromptHidden` fires for both walking out
							of `MaxActivationDistance` and for losing line of sight, so the
							distance is measured at the moment it hides: past the range is
							"out of range", inside it is "line of sight". ]]
						table.insert(
							state.connections,
							prompt.PromptHidden:Connect(function()
								if state == nil or not state.engaged then
									return
								end
								local distance = characterDistance()
								local out = distance == nil or distance > (spec.range or 10)
								api.release(if out then "out-of-range" else "line-of-sight")
							end)
						)
					end
					return console
				end

				--[[ `open(spec)` — ask the server for the outpost, build the second
					Facet host on the console's face, mount the terminal, and wire the
					walk-up. Everything after this is engage/resign on a surface that
					stays mounted, which is what makes repeated trigger-then-cancel cheap
					and safe. ]]
				function api.open(spec: any): any
					if state ~= nil then
						return api.dump()
					end
					local ok, built = pcall(function()
						local ReplicatedStorage = game:GetService("ReplicatedStorage")
						local clientHost = require(ReplicatedStorage.Facet.client.host) :: any
						local surfaceTarget = require(ReplicatedStorage.Facet.client.surface_target) :: any
						local canvas = spec.canvas or { w = 640, h = 480 }
						local faceName = spec.face or "Back"
						assert(FACE_NORMALS[faceName] ~= nil, `surface: unknown face '{tostring(faceName)}'`)

						state = {
							spec = spec,
							canvas = canvas,
							faceName = faceName,
							connections = {},
							engaged = false,
							token = nil,
							allocation = nil,
							character = false,
							lastExit = nil,
						}
						--[[ WAITED FOR, NOT RACED. The fixture is the SERVER's — see the
							seam header — so every one of these arrives by replication a frame
							or more after it is asked for, and a `FindFirstChild` on the frame
							the scenario mounts would find nothing and report "no server". Each
							wait is bounded, so a place genuinely missing the server side fails
							with a sentence instead of hanging. ]]
						local transport = ReplicatedStorage:WaitForChild("Facet_Outpost", 10)
						assert(
							transport ~= nil,
							"surface: ReplicatedStorage.Facet_Outpost is not here — this place has no server side "
								.. "(examples/gallery.project.json maps examples/gallery/server to ServerScriptService)"
						)
						table.insert(
							state.connections,
							(transport :: any).OnClientEvent:Connect(function(payload: any)
								handleReply(payload)
							end)
						)
						api.command("open")
						api.command("character", { action = "load" })
						local outpost = workspace:WaitForChild("Outpost", 10)
						assert(outpost ~= nil, "surface: Workspace.Outpost never replicated after the open command")
						assert(
							outpost:WaitForChild("Console", 10) ~= nil,
							"surface: Workspace.Outpost.Console never replicated"
						)
						local console = wireConsole(spec)
						assert(console ~= nil, "surface: Workspace.Outpost.Console is not a BasePart")

						local hostHandle = clientHost.new({
							newAdapter = function(): any
								return surfaceTarget.new({
									parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
									adornee = console,
									face = (Enum.NormalId :: any)[faceName],
									canvas = canvas,
									maxDistance = spec.maxDistance,
									--[[ `.Adornee` STILL NAMES A DESTROYED PART (measured), so
										the reference outlives the instance and polling it can
										never notice. This is the adapter telling us; resigning
										is ours to do. ]]
									onAdorneeLost = function()
										api.release("adornee-lost")
									end,
								})
							end,
							--[[ NOT `roblox_env.bind`, and this is the load-bearing line of
								the whole seam. That binder republishes `viewportRect` from
								`Camera.ViewportSize` on every viewport and topbar change, which
								would overwrite the canvas rect with the player's screen and
								re-solve the terminal against a rectangle it does not live in.
								The solver's world IS the canvas here. The DEVICE facts are
								still real — mirrored below, every frame, so a hot switch from
								keyboard to gamepad moves this surface exactly as it moves a
								screen. ]]
							bindEnv = function(env: any): () -> ()
								env:set("viewportRect", surfaceTarget.canvasRect(canvas))
								env:set("presentationSpace", "world")
								mirrorFacts(env)
								return function() end
							end,
						})
						state.host = hostHandle

						local surfaceCtx = {
							Facet = Facet,
							core = hostHandle.core,
							env = hostHandle.env,
							adapter = hostHandle.adapter,
							presenter = hostHandle.presenter,
							actionSystem = hostHandle.inputSystem,
							canvas = canvas,
							-- the wire, and the only one the terminal ever sees
							send = function(envelope: any)
								api.command("apply", {
									requestId = envelope.requestId,
									allocation = envelope.payload.allocation,
									expectedRevision = envelope.expectedRevision,
								})
							end,
							exit = function(reason: string?)
								api.release(reason or "exit-control")
							end,
						}
						local terminal = spec.build(surfaceCtx)
						state.built = terminal
						state.handle = hostHandle.presenter.present(terminal.screen, terminal.present)

						--[[ THE RESPONDER IS WATCHED, NOT ASSUMED. Cancel and the platform
							back action resign an engaged-from-passive surface inside the
							presenter, so the only honest way to learn the session ended that
							way is to observe the handle's own signal. ]]
						table.insert(
							state.connections,
							{
								Disconnect = hostHandle.core:observe(state.handle.responder, function(value: string)
									if value ~= "engaged" and state ~= nil and state.engaged then
										api.release("cancel")
									end
								end),
							} :: any
						)
						-- the device facts, kept live on the surface's own frame
						hostHandle.presenter.onTick(function()
							if state ~= nil then
								mirrorFacts(hostHandle.env)
							end
						end)
						--[[ CHARACTER REMOVAL IS A REAL EXIT PATH HERE, not a hypothetical
							one: the scenario's own teardown removes the character, so the
							control that switches demos exercises it. ]]
						table.insert(
							state.connections,
							Players.LocalPlayer.CharacterRemoving:Connect(function()
								api.release("character-removed")
							end)
						)
						return true
					end)
					if not ok then
						local message = tostring(built)
						api.teardown()
						return { open = false, error = message }
					end
					return api.dump()
				end

				--[[ THE LIFECYCLE READ every teardown row needs: how many surfaces this
					client actually carries, whether the adornee is still in the world, and
					whether anything is still holding the responder. ]]
				function api.dump(): any
					local surfaceGuis, descendants = 0, 0
					local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
					if playerGui ~= nil then
						for _, gui in playerGui:GetChildren() do
							if gui:IsA("SurfaceGui") then
								surfaceGuis += 1
								descendants += #gui:GetDescendants()
							end
						end
					end
					local outposts = 0
					for _, inst in workspace:GetChildren() do
						if inst.Name == "Outpost" then
							outposts += 1
						end
					end
					if state == nil then
						return {
							open = false,
							surfaceGuis = surfaceGuis,
							outposts = outposts,
							connections = 0,
							character = Players.LocalPlayer.Character ~= nil,
						}
					end
					return {
						open = true,
						canvas = state.canvas,
						face = state.faceName,
						faceCheck = api.faceCheck(),
						engaged = state.engaged,
						responder = if state.handle ~= nil then state.handle.responder:get() else nil,
						lastExit = state.lastExit,
						token = state.token,
						allocation = state.allocation,
						adorneePresent = state.console ~= nil and state.console.Parent ~= nil,
						promptEnabled = if state.prompt ~= nil then state.prompt.Enabled else nil,
						distance = characterDistance(),
						surfaceGuis = surfaceGuis,
						surfaceDescendants = descendants,
						outposts = outposts,
						connections = #state.connections,
						character = Players.LocalPlayer.Character ~= nil,
						replies = #pending,
						exits = exitLog,
						terminal = if state.built ~= nil and state.built.report ~= nil
							then serializeValue(state.built.report())
							else nil,
					}
				end

				function api.replies(): any
					return pending
				end

				--[[ THE TERMINAL'S OWN DRIVE SURFACE, reached through the seam. The
					content module lives on the SURFACE host's core, which the scenario
					has no handle on — this is the one door, and it answers a table rather
					than throwing when there is nothing behind it. ]]
				function api.terminalStep(name: string, a: any?, b: any?): any
					if state == nil or state.built == nil or state.built.steps == nil then
						return { ok = false, reason = "no terminal mounted" }
					end
					local fn = state.built.steps[name]
					if fn == nil then
						return { ok = false, reason = `the terminal has no step '{name}'` }
					end
					local ok, result = pcall(fn, a, b)
					return { ok = ok, result = if ok then serializeValue(result) else tostring(result) }
				end

				--[[ WALK AWAY, ON PURPOSE. The design's third refusal drive is "a player
					who walked away between pressing and arriving", and the only honest way
					to produce it is to actually move the character — the server measures
					the distance itself, from the character it can see, so a faked number
					would prove nothing about the check. Answers the distance it achieved
					rather than the one it was asked for. ]]
				function api.placeCharacter(studs: number): any
					if state == nil or state.console == nil then
						return { moved = false, reason = "not open" }
					end
					local character = Players.LocalPlayer.Character
					if character == nil then
						return { moved = false, reason = "no character" }
					end
					local target = (state.console :: BasePart).CFrame * CFrame.new(0, -2, studs);
					(character :: Model):PivotTo(target)
					return { moved = true, requested = studs, distance = characterDistance() }
				end

				--[[ TEARDOWN, IN THE ORDER THAT LEAVES NOTHING. Resign first (so the
					responder is not holding input while its tree is being taken apart),
					then dismiss the surface, then dispose the host — which releases the
					frame connection, the input system's contexts, the render target and
					the environment binding — then hand the outpost and the character back
					to the server. ]]
				function api.teardown(): any
					if state == nil then
						return { torn = false, after = api.dump() }
					end
					api.release("teardown")
					local dying = state
					state = nil
					for _, connection in dying.connections do
						pcall(function()
							connection:Disconnect()
						end)
					end
					if dying.built ~= nil and dying.built.dispose ~= nil then
						pcall(dying.built.dispose)
					end
					if dying.host ~= nil and dying.handle ~= nil then
						pcall(function()
							dying.host.presenter.dismiss(dying.handle)
						end)
					end
					if dying.host ~= nil then
						pcall(function()
							dying.host.dispose()
						end)
					end
					local ev = remote()
					if ev ~= nil then
						ev:FireServer({ kind = "character", action = "remove" })
						ev:FireServer({ kind = "close" })
					end
					return { torn = true, after = api.dump() }
				end

				return api
			end)(),
			-- test-run flags (engine attribute reads stay runner-owned)
			flags = {
				forceDragFallback = workspace:GetAttribute("Facet_ForceDragFallback") == true,
				forceScrollFallback = workspace:GetAttribute("Facet_ForceScrollFallback") == true,
				-- theme-packages stage: the package/theme a Studio operator
				-- selects BEFORE Play, so the five-view matrix can be driven
				-- against a chosen skin without editing a scenario
				themePackage = workspace:GetAttribute("Facet_ThemePackage"),
				themeName = workspace:GetAttribute("Facet_ThemeName"),
				-- roadmap Step 10: which tutorial example the `examples` scenario
				-- opens on, selected the same way and for the same reason as the
				-- theme package above — an operator picks it BEFORE Play and the
				-- matrix re-selects at runtime through the scenario step
				example = workspace:GetAttribute("Facet_Example"),
			},
			-- REFERENCE THEME PACKAGES (theme-packages-and-skinning). They are
			-- ModuleScripts under ReplicatedStorage.FacetThemes here and files
			-- under examples/themes/ headlessly, so resolving them is runner
			-- work exactly like the resource transport and the calibration seam
			-- — the scenario module stays engine-free and path-free.
			-- THE TUTORIAL EXAMPLE MODULES, resolved the same way and for the same
			-- reason as the theme packages below: they are ModuleScripts under
			-- ReplicatedStorage.FacetExamples here and files under
			-- examples/gallery/examples headlessly, so finding them is runner work
			-- and the `examples` scenario stays path-free.
			exampleModules = game:GetService("ReplicatedStorage"):FindFirstChild("FacetExamples"),
			-- THE REFERENCE PROOF MODULES (reference-app-validation):
			-- ModuleScripts under ReplicatedStorage.FacetReference here, files
			-- under examples/reference/ headlessly — resolved by the runner for the
			-- same reason as the tutorial examples above, so the ref_* scenarios
			-- stay engine-free and path-free.
			referenceModules = game:GetService("ReplicatedStorage"):FindFirstChild("FacetReference"),
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
			-- ...and the same live seam for a FOREIGN box, so a scenario's
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
				local folder = game:GetService("ReplicatedStorage"):FindFirstChild("FacetThemes")
				if folder ~= nil then
					for _, mod in folder:GetChildren() do
						if mod:IsA("ModuleScript") then
							out[mod.Name] = require(mod) :: any
						end
					end
				end
				return out
			end)(),
			-- The adapter's decoration-slot surface.
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
				-- THE SIXTH VARIANT STATE. No control publishes an
				-- error state yet (P3's wiring), so the adapter exposes the seam and
				-- the scenario drives it — which is what lets the `facet-state-error`
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
				-- WHOLE-frame work (everything the client does), not Facet's
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
							.. "work of any device, and it is not Facet's share of the frame — that is M2.",
					}
				end,
				-- M3: the real Instance census under the mounted surfaces.
				-- Facet-OWNED roots are counted separately from everything else
				-- in PlayerGui. The first live capture counted Roblox's own
				-- Freecam ScreenGui into "Facet's instances", which is the kind of
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
						-- THE LENGTH IS READ OFF THE LITERAL (SCREEN-X, 2026-08-22).
						-- This compared SIX characters against `"Facet"`, which is
						-- five, so `mine` was constantly false: Facet's own
						-- `Facet_<id>` roots were filed under `foreign` and this
						-- census reported ZERO GuiObjects for the framework. Seven
						-- RC-requalification capture rows carry that zero.
						local mine = string.sub(gui.Name, 1, #FACET_ROOT_PREFIX) == FACET_ROOT_PREFIX
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
							note = "GUIs in PlayerGui that Facet does not own (Roblox core scripts, other systems); "
								.. "counted separately so they never inflate Facet's cost",
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
						-- the client process, not Facet's share — the same figure came
						-- back byte-identical across three different presets, viewports
						-- and layouts, which is what it looks like when a number is not
						-- about your screen. Only the DELTA around a mount is
						-- attributable. Gating this on a failure mode meant no published
						-- row ever carried it.
						out.guiMbNote = "Stats' whole Gui memory tag for the client process, NOT Facet's share; "
							.. "only guiMbDelta (the change across the workload) is attributable"
						if out.memoryTrackingEnabled == false then
							out.guiMbNote = out.guiMbNote
								.. ". Stats.MemoryTrackingEnabled is false, so per-tag figures are not being collected"
						end
					else
						out.guiMbUnavailable = tostring(guiMb)
					end
					out.totalMbNote = "totalMb is the whole client process on the development host, not Facet's share"
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
			-- the mounted Instance for a Facet path. Engine access stays
			-- runner-owned; a scenario uses this only to hand an instance BACK to
			-- another runner seam (paintWatch), never to write to it.
			instanceAt = function(path: string): Instance?
				local a = deps.adapter :: any
				return if a.getInstance ~= nil then a.getInstance(path) else nil
			end,
			--[[ solved geometry for named paths, so a scenario's own report can
				PAIR geometry with the theme identity that produced it instead of
				leaving the reader to join two sections of the dump by hand.

				`visible` IS THE ENGINE'S OWN PAINT BIT, and it is here because nothing
				else in this repository can answer "did this node paint" from OUTSIDE
				the framework's own model (NM-H4a). Rects, `hiddenRoots` and the
				composition resolution all report what the framework DECIDED; a defect
				where the decision is right and the write never landed is invisible to
				every one of them, which is why 288 headless replays of the reported
				sequence diverged by zero. This is the other side of that seam, and it
				stays runner-owned exactly like every other engine read here.

				It is the node's OWN flag, never an effective one: Roblox has no
				`AbsoluteVisible`, and the renderer's visibility walk writes the
				inherited verdict onto EVERY node individually (`pushVisible`), so the
				own flag and the effective one agree whenever that walk completed. A
				caller that has to survive a walk which did NOT complete asks for the
				ancestor paths too and reads them the same way — which is the whole
				reason the disagreement is legible instead of invisible.

				A path with no GuiObject is still OMITTED, unchanged. That answer is
				ambiguous by construction — an ELIDED container (VStack/HStack/ZStack/
				Grid/Anchor/Spacer with nothing of its own to paint) has no Instance at
				all, and neither does an unmounted node — so a caller that needs the
				distinction names non-elidable classes. ]]
			--[[ ...AND `enabled` IS THE OTHER HALF OF THE SAME ANSWER (2026-08-16). A
				surface root is hidden with `ScreenGui.Enabled` — a different property on
				a class no path resolves to — so `Visible` alone reports every node of a
				dark screen as painting. It rides each node's record rather than an entry
				of its own so that a caller reading one path still gets the whole
				verdict; it is the node's nearest `LayerCollector` ancestor, and `true`
				when there is none. ]]
			geometry = function(paths: { string }): { [string]: any }
				local out: { [string]: any } = {}
				local a = deps.adapter :: any
				for _, path in paths do
					local inst = a.getInstance and a.getInstance(path)
					if inst ~= nil and inst:IsA("GuiObject") then
						local layer = inst:FindFirstAncestorWhichIsA("LayerCollector")
						-- ...and the two ways a perfect rect paints nothing: a `CanvasGroup`
						-- ancestor faded to nothing, and an ancestor that CLIPS and does not
						-- contain this node. The shipped host reads the same pair; see the
						-- long note beside it in `examples/gallery/client/init.client.luau`.
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
			-- the last solve's COMPOSITION RESOLUTION for a node, so a
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
			-- install/swap/current/inspect/onChange. LATE-BOUND on
			-- purpose: this package must not import a module that may not exist
			-- yet, and the scenario must degrade to "controller absent" rather
			-- than failing to mount. Delete the pcall the day the module lands.
			themeController = function(): any
				local ok, module = pcall(function()
					return require(game:GetService("ReplicatedStorage").Facet.client.theme_controller) :: any
				end)
				return if ok then module else nil
			end,
			-- engine text calibration (NS-A10): yields; returns the applied table
			runTextCalibration = function(fonts: { string }?): { [string]: number }
				local calibration = require(game:GetService("ReplicatedStorage").Facet.client.text_calibration) :: any
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
				-- THE WHOLE SUBTREE of a mounted node, by Facet path: names,
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
				-- resolved styled read for a mounted node (by Facet path)
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
		-- STAGE CONTENT, MATERIALIZED BY THE RUNNER (reference-app-validation).
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
		-- FOREIGN CONTENT, same contract: `built.foreignContent =
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

	--[[ THE STEPS EVERY SCENARIO HAS WITHOUT WRITING ONE. `expand` was the gap
		this registry had: `presenter.expand(path)` is the framework's own second
		route to a region's disclosure — the same longest-prefix dispatch an
		Activate takes — and until now the only way to reach it from a driver was
		for a fixture to have hand-written a step for it. A generic step is right
		here rather than in each fixture precisely because the seam is the
		framework's; a per-fixture copy is a second thing to keep in step.

		It is a STATE DRIVER, not counterfeited input, and is labelled as such by
		the same rule the rest of this file follows: the affordance's own Activate
		is native-input territory and rides the MCP input tools. ]]
	local GENERIC_STEPS: { [string]: (any, string?) -> any } = {
		expand = function(_built: any, payload: string?)
			assert(payload ~= nil and payload ~= "", "step 'expand' needs a region path payload")
			local opened = deps.presenter.expand(payload)
			return { path = payload, opened = opened }
		end,
	}

	function api.list(): { string }
		return registry.order
	end

	function api.steps(): { string }
		local names = {}
		local seen: { [string]: boolean } = {}
		if session.built and session.built.steps then
			for stepName in session.built.steps do
				seen[stepName] = true
				table.insert(names, stepName)
			end
		end
		-- ...AND THE GENERIC ONES, because a driver discovers what it can do from
		-- this list and a step it cannot see is a step nobody drives
		for stepName in GENERIC_STEPS do
			if not seen[stepName] then
				table.insert(names, stepName)
			end
		end
		table.sort(names)
		return names
	end

	--[[ THE OPENABLE STATES OF THIS SURFACE (overflow guard layer 3, 2026-08-21).

		A sweep mounts a demo, settles it, and judges what is on screen. Everything
		that exists only after a TAP — an expand plate, a menu, a tray, a disclosure
		sink — is invisible to it, and that is not a hypothetical: the region-expand
		plate painted its `9` 8px past its own panel edge, live, through a green
		180-cell demo sweep and a green suite, because the plate is not on the
		screen the sweep looked at (commit 27af00f).

		A scenario declares `states` — a function returning `{ id, kind, open }` —
		and a driver walks it. The list is a FUNCTION rather than a table because
		which states exist depends on the configuration: at desktop nothing steps
		down and there is nothing to expand, so the honest list at that viewport is
		shorter, and `open()` returning false is the answer for a state that is not
		reachable here. ]]
	function api.states(): { { id: string, kind: string } }
		local out: { { id: string, kind: string } } = {}
		local declare = if session.built then session.built.states else nil
		if type(declare) ~= "function" then
			return out
		end
		for _, state in declare() do
			table.insert(out, { id = state.id, kind = state.kind })
		end
		return out
	end

	function api.openState(id: string): any
		assert(session.built, "scenario not built")
		local declare = session.built.states
		assert(type(declare) == "function", `scenario '{name}' declares no openable states`)
		for _, state in declare() do
			if state.id == id then
				workspace:SetAttribute("Facet_ScenarioState", "opening:" .. id)
				local ok, opened = pcall(state.open)
				workspace:SetAttribute("Facet_ScenarioState", if ok then "ready" else "failed:open:" .. id)
				if not ok then
					error(opened)
				end
				deps.presenter.refresh()
				return { id = id, opened = opened == true }
			end
		end
		error(`no state '{id}' in scenario '{name}'`)
	end

	function api.step(stepName: string, payload: string?): any
		assert(session.built, "scenario not built")
		local fn = session.built.steps and session.built.steps[stepName]
		if fn == nil then
			fn = GENERIC_STEPS[stepName]
		end
		assert(fn ~= nil, `no step '{stepName}' in scenario '{name}'`)
		workspace:SetAttribute("Facet_ScenarioState", "running:" .. stepName)
		local ok, result = pcall(fn, session.built, payload)
		table.insert(session.stepLog, {
			step = stepName,
			at = os.clock(),
			result = if ok then serializeValue(result) else "ERROR:" .. tostring(result),
		})
		workspace:SetAttribute("Facet_ScenarioState", if ok then "ready" else "failed:" .. stepName)
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
		workspace:SetAttribute("Facet_ScenarioState", "ready")
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
				return require(game:GetService("ReplicatedStorage").Facet.layout.text_metrics) :: any
			end)
			if ok and tm ~= nil and tm.measuredDump ~= nil then
				textMeasurement = { measuredWords = tm.measuredCount(), words = tm.measuredDump() }
				-- and the corrections the settled re-read made to the engine's
				-- boot answers: without these the widths above would be the
				-- wrong-but-stable ones the API hands out during startup
				local okp, premeasure = pcall(function()
					return require(game:GetService("ReplicatedStorage").Facet.client.text_premeasure) :: any
				end)
				if okp and premeasure ~= nil and premeasure.corrections ~= nil then
					textMeasurement.bootWindowCorrections = premeasure.corrections
				end
			end
		end
		-- the per-text-node facts of the last solve (font, lines, truncated,
		-- disclose/reveal, policy) so an instrument judging TextFits can tell a
		-- DECLARED truncation-with-disclosure from a genuine unfit finding
		-- (reference-app-validation matrix, 2026-08-08)
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
			schema = "facet-scenario/1",
			scenario = name,
			diagnostics = diagnostics,
			textPolicies = textPolicies,
			textMeasurement = textMeasurement,
			ledgerRows = scenario.ledgerRows or {},
			version = Facet.VERSION,
			sourceStamp = workspace:GetAttribute("Facet_SourceStamp"),
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
	_G.FacetScenario = api
	-- The MCP's execute_luau runs in a DIFFERENT Luau VM than this client script,
	-- so _G does not cross. Publish the API as BindableFunctions the command VM
	-- can Invoke (same client DataModel). JSON-in/JSON-out for table safety.
	local apiFolder = Instance.new("Folder")
	apiFolder.Name = "FacetScenarioAPI"
	for fnName, impl in
		{
			list = function(_arg: string?)
				return HttpService:JSONEncode(api.list())
			end,
			steps = function(_arg: string?)
				return HttpService:JSONEncode(api.steps())
			end,
			-- the openable states this surface declares, and the driver that opens
			-- one (overflow guard layer 3): a sweep that only ever judges the settled
			-- screen cannot see a plate that exists after a tap
			states = function(_arg: string?)
				return HttpService:JSONEncode(api.states())
			end,
			openState = function(arg: string?)
				return HttpService:JSONEncode(api.openState(arg :: string))
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
				local premeasure = require(game:GetService("ReplicatedStorage").Facet.client.text_premeasure) :: any
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
	workspace:SetAttribute("Facet_ScenarioReady", true)
	workspace:SetAttribute("Facet_ScenarioState", "ready")
	workspace:SetAttribute("Facet_Version", Facet.VERSION)
	print(`[Facet Scenario] '{name}' ready ({Facet.VERSION}); steps: {table.concat(api.steps(), ",")}`)
	return api
end

return Runner
