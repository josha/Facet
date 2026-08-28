--!strict
-- The structural-transition COORDINATOR (ADR-0022 Decision 3; ui-designer spec
-- §2.1). It is the mount layer's `transitions` collaborator,
-- implemented over exactly two things: the motion clock (P1) and the renderer's
-- per-node presentation channel (P2).
--
-- WHY IT LIVES UNDER src/render/ AND NOT src/present/. Everything it does is a
-- presentation write — `controller.setPresentationTransform` /
-- `setPresentationTransparency`, the framework's whole motion write surface — and
-- it needs the renderer's node/handle knowledge to make them. It owns no surface
-- lifetime, no focus scope and no input policy, which is what `src/present/` is
-- for; the presenter merely CONSUMES it (and `present` already depends on
-- `render`, so the direction is the established one).
--
-- ONE SPRING PER TRANSITION, and it is a PROGRESS spring in [0, 1]: 1 = at rest
-- (fully present), 0 = fully absent. Enter aims at 1, exit aims at 0, and a
-- re-entry mid-exit simply re-aims the SAME spring — which is why reversal keeps
-- both the value and the velocity and needs no case of its own. Every visual form
-- (offset, scale, transparency) is derived from that one number, so a form can
-- never disagree with itself half way through.
--
-- THE ABSENT PLACE IS THE SAME FOR A MIRROR PAIR. A form names the direction of
-- TRAVEL: an enter travels toward rest, an exit travels away from it. `slide-up`
-- entering starts BELOW; `slide-down` exiting ends BELOW — the same displacement,
-- so the default (mirrored) exit reverses through one continuous motion.
--
-- THE HARD CAP (disposition F8): no exit may defer disposal beyond 500 ms of CLOCK
-- time. Flat, non-overridable, and enforced here because this is where time is —
-- `mount.luau` is engine-free and must not grow a clock. A clock nobody steps
-- stops the cap too; that is a stopped surface, not a leak.
--
-- REDUCED MOTION NEEDS NO CODE HERE. A MotionValue under `reduced` places itself
-- at the terminal value and fires the same settle event on the same frame, so an
-- enter lands instantly and still emits `arrive`, and an exit completes — and
-- disposes — on the frame it began. Information parity comes from the authority,
-- not from a branch in every consumer.

local schema = require("../blueprint_schema")
local themeSnapshot = require("../themes/snapshot")

local transitions = {}

-- ui-designer spec §2.1 / disposition F8: flat and non-overridable
local EXIT_CAP_SECONDS = 0.5
-- the slide travel, as a THEME metric (`space.l` = 24 px in Studio Neutral): a
-- roomier theme slides a little further, and no call site carries a magic number
local DEFAULT_SLIDE_DISTANCE = 24
-- materialize (ratified: sponsor_motion §2/§8, range [0.94–0.98])
local MATERIALIZE_SCALE = 0.96
local DEFAULT_CLASS = "container"

-- travel vector per form, in screen space (+y is down)
local TRAVEL: { [string]: { x: number, y: number } } = {
	["slide-up"] = { x = 0, y = -1 },
	["slide-down"] = { x = 0, y = 1 },
	["slide-left"] = { x = -1, y = 0 },
	["slide-right"] = { x = 1, y = 0 },
}

export type Spec = {
	enter: string,
	exit: string,
	class: string,
	fade: boolean,
	-- task-fix3 symptoms 2/3: opt-in override for `slideDistance` below, nil
	-- meaning "use the themed default" (every caller before this fix, unchanged)
	distance: number?,
}

export type Opts = {
	core: any,
	clock: any,
	controller: any?,
	-- the live metric authority (ADR-0019 §2); defaults to Studio Neutral
	metrics: (() -> any)?,
	-- the semantic feedback sink (ADR-0022 Decision 7). An ENTER that reaches rest
	-- is a motion arrival, so it emits `arrive` on that frame.
	feedback: ((event: any) -> ())?,
	surface: any?,
}

-- normalize an authored declaration. The schema already refused an unknown form,
-- so this only fills the defaults: the exit mirrors the enter unless it was
-- declared, and the motion class is `container` (large surfaces materializing).
function transitions.resolve(declared: any): Spec
	if type(declared) ~= "table" then
		error(
			"Facet transition: a transition is a table { enter = <form>, exit? , class?, fade? } — "
				.. `got {typeof(declared)}`,
			0
		)
	end
	local enter = declared.enter
	local exit = declared.exit or (schema.TRANSITION_MIRROR :: any)[enter]
	return {
		enter = enter,
		exit = exit,
		class = declared.class or DEFAULT_CLASS,
		fade = declared.fade == true,
		distance = if type(declared.distance) == "number" then declared.distance else nil,
	}
end

local function fades(spec: Spec, form: string): boolean
	return spec.fade or (schema.TRANSITION_FADES :: any)[form] == true
end

--[[ BACKDROP-BEFORE-CONTENT (framework-gaps-phase2-followups task POP, director
	item 10 + mandate b). `GroupTransparency` is ONE scalar Roblox composites over
	a CanvasGroup's WHOLE rendered subtree, so an opaque plate (an authored
	`surface`) declared INSIDE the node a fade targets reaches full opacity at the
	exact instant its content does — "the backdrop is legible no later than the
	content" is then impossible BY CONSTRUCTION, not merely unlikely. Measured
	headlessly (task POP): four Glade modals shared one helper that put
	`surface = "raised"` on a descendant of the one canvasGroup `presentModal`
	targets; `GroupTransparency` sampled across a 30-tick materialize read
	1, 0.73, 0.23, 0.003 and the plate rode every one of those numbers alongside
	its own text.

	Pure, module-level and engine-free on purpose (mirrors `src/render/
	surface_overlap.luau`'s own shape): a mounted node's `.props`/`.children` are
	all either function needs, so both the live coordinator below and a headless
	gate can call them directly over a `tests/lib/fake_target` tree with nothing
	else wired up. ]]
local NON_PAINTING_SURFACE: { [string]: boolean } = { plain = true }
local function paintsBackdrop(surface: any): boolean
	return type(surface) == "string" and not NON_PAINTING_SURFACE[surface]
end

-- every `canvasGroup = true` descendant of `node`, stopping descent at each one
-- found (a nested INDEPENDENT fade group is its own compositing boundary, not a
-- candidate one level further in).
local function collectCanvasGroups(node: any, out: { any })
	for _, child in node.children or {} do
		if child.props ~= nil and child.props.canvasGroup == true then
			table.insert(out, child)
		else
			collectCanvasGroups(child, out)
		end
	end
end

--[[ THE FIX SPLITS THE WRITE, NOT THE TRANSITION. Position/scale still target
	the node the caller declared — a plain `UIScale`/offset moves a background
	plate and its content as one rigid unit, canvasGroup or not, so a
	`materialize` card still scales and slides as a whole. Alpha alone needs the
	group: when the declared node is not itself one, this finds the ONE
	canvasGroup in its subtree and routes `GroupTransparency` there instead — the
	backdrop is then never a descendant of what fades, so it paints at its own,
	immediate opacity from the first frame. Zero or more than one candidate falls
	back to the declared node itself — exactly today's construction, and
	`assertFadeCapable`'s refusal still fires for it unchanged. ]]
local function resolveAlphaTarget(path: string, node: any): (string, any)
	if node == nil or node.props == nil or node.props.canvasGroup == true then
		return path, node
	end
	local candidates: { any } = {}
	collectCanvasGroups(node, candidates)
	if #candidates == 1 then
		local only = candidates[1]
		return only.path, only
	end
	return path, node
end

export type BackdropFinding = { path: string, backdropPath: string, surface: string }

-- the STRUCTURAL half of the same finding, usable with no coordinator at all:
-- does the node that will actually fade (post `resolveAlphaTarget`) itself
-- COMPOSE an opaque `surface` as one of its own DIRECT children? Zero frames
-- stepped, zero engine — a pure tree read, which is the honest answer to
-- mandate (b): this whole class is visible headlessly, with nothing animated
-- at all.
--
-- ONE LEVEL, DELIBERATELY — not every `surface` anywhere in the subtree. The
-- bug this catches is "the plate meant to hide whatever is BEHIND THE WHOLE
-- FADING SURFACE is itself inside it" (`shop.wisp`'s `Panel`, `page()`'s old
-- `Page`, both direct children of the node the transition targeted); a card's
-- OWN thumbnail or a chip three levels into its content also carries a
-- `surface`, and flagging those too would bury the real finding in ordinary
-- content that was always going to fade in with the rest of the modal — a
-- plate a level down is content the plate above it ALREADY made opaque, not a
-- second backdrop. `tests/backdrop_fade.spec.luau` pins both directions: the
-- unfixed shape reddens this, and legitimate nested content (a card two levels
-- into a fixed page) never does.
local function collectBackdrops(node: any, out: { any })
	for _, child in node.children or {} do
		if child.props ~= nil and paintsBackdrop(child.props.surface) then
			table.insert(out, child)
		end
	end
end

-- `alphaNode` is what `resolveAlphaTarget` returns for a DECLARED fade — pass
-- the node as declared (self or a resolved content group) plus the resolved
-- path, so a finding names the same path the coordinator would actually fade.
function transitions.findBackdropFindings(alphaPath: string, alphaNode: any): { BackdropFinding }
	local out: { BackdropFinding } = {}
	if alphaNode == nil then
		return out
	end
	local backdrops: { any } = {}
	collectBackdrops(alphaNode, backdrops)
	for _, b in backdrops do
		table.insert(out, { path = alphaPath, backdropPath = b.path, surface = b.props.surface })
	end
	return out
end

function transitions.backdropIssue(finding: BackdropFinding): string
	return string.format(
		"%s declares a fading transition whose fade group still composes %s's opaque `surface = %q` — "
			.. "GroupTransparency dims the two together, so the backdrop can never be legible ahead of the "
			.. "content it sits behind. Move the backdrop OUTSIDE the fade group (a sibling, not a descendant); "
			.. "`src/render/transitions.luau`'s header names the shape.",
		finding.path,
		finding.backdropPath,
		finding.surface
	)
end

function transitions.new(opts: Opts)
	assert(type(opts) == "table" and opts.core ~= nil, "Facet transitions: a core is required")
	assert(opts.clock ~= nil, "Facet transitions: a motion clock is required (Facet.motion.newClock)")
	local core = opts.core
	local clock = opts.clock
	local controller: any = opts.controller
	local metricsOf = opts.metrics or themeSnapshot.neutral
	local emit = opts.feedback
	local surface = opts.surface

	local entries: { [string]: any } = {}
	local disposed = false
	-- task POP, mandate (b)'s gate: every backdrop-inside-fade-group shape ever
	-- DECLARED through this coordinator, deduplicated by (path, backdrop) so a
	-- surface re-entered many times over a session reports once. Read-only for
	-- everyone but `self.findings()`; nothing here costs off that read.
	local foundBackdrops: { BackdropFinding } = {}
	local seenBackdropKeys: { [string]: boolean } = {}
	local function recordBackdropFindings(alphaPath: string, alphaNode: any)
		for _, finding in transitions.findBackdropFindings(alphaPath, alphaNode) do
			local key = finding.path .. "\0" .. finding.backdropPath
			if not seenBackdropKeys[key] then
				seenBackdropKeys[key] = true
				table.insert(foundBackdrops, finding)
			end
		end
	end

	-- task-fix3 symptoms 2/3 (director device round, 2026-08-23): "slides a few
	-- pixels then pops out" / "pops in then slides a few pixels". `space.l` (24px
	-- neutral) is the right size for a DECORATIVE nudge — a toast easing in from
	-- its own edge — and the wrong one for a full-viewport surface push/pop,
	-- where the node needs to travel far enough to read as leaving/entering the
	-- screen: measured, a 390px-wide compact detail sheet sliding 24px stayed
	-- ~94% on screen for its whole enter, then (on exit) the flat 500ms cap
	-- disposed it after ~24px of travel — visually indistinguishable from an
	-- instant pop either way. `spec.distance` (declared per transition, gap 16's
	-- sibling `offset`'s own shape: an opt-in AUTHORED override, never a changed
	-- default) is the fix a caller reaches for when its slide IS the surface
	-- leaving the screen rather than a nudge; nil keeps every existing caller
	-- (toasts included) on the themed default, unchanged.
	local function slideDistance(spec: Spec): number
		if type(spec.distance) == "number" and spec.distance > 0 then
			return spec.distance
		end
		local snap = metricsOf()
		local space = if type(snap) == "table" then (snap :: any).space else nil
		local step = if type(space) == "table" then (space :: any).l else nil
		return if type(step) == "number" and step > 0 then step else DEFAULT_SLIDE_DISTANCE
	end

	-- where the node sits when it is fully ABSENT, for this form in this phase.
	-- Enter travels toward rest (so it starts against the travel direction); exit
	-- travels away from it (so it ends along the travel direction).
	local function absentFor(spec: Spec, form: string, phase: string): any
		local absent: any = { x = 0, y = 0 }
		local travel = TRAVEL[form]
		if travel ~= nil then
			local d = slideDistance(spec)
			local sign = if phase == "enter" then -1 else 1
			absent.x = travel.x * d * sign
			absent.y = travel.y * d * sign
		end
		if form == "materialize" then
			absent.scale = MATERIALIZE_SCALE
		end
		if fades(spec, form) then
			absent.alpha = 1
		end
		return absent
	end

	-- a fading form needs a declared fade GROUP, and the refusal names the fix —
	-- the same rule (and the same reason) as the presentation channel's own
	-- refusal, raised here so an author hears it at the declaration rather than on
	-- the first frame of the first exit.
	local function assertFadeCapable(path: string, node: any, spec: Spec, form: string)
		if not fades(spec, form) then
			return
		end
		if node ~= nil and node.props ~= nil and node.props.canvasGroup == true then
			return
		end
		error(
			`Facet transition: {path} declares a '{form}' transition, which fades — but the node it applies to `
				.. `is not a fade group. Make the region's child a UI.ZStack\{ canvasGroup = true } (or a `
				.. "UI.Box{ canvasGroup = true } for a single plate) and put the content inside it: "
				.. "GroupTransparency is the one engine property no style rule owns, while per-node transparency "
				.. "would contest native-sheet paint. A slide or `instant` form needs no group.",
			0
		)
	end

	local function writeEntry(entry: any)
		if controller == nil or entry.disposed then
			return
		end
		local p = entry.progress:get()
		local k = 1 - p
		local absent = entry.absent
		controller.setPresentationTransform(entry.path, {
			x = absent.x * k,
			y = absent.y * k,
			scale = if absent.scale ~= nil then 1 + (absent.scale - 1) * k else nil,
		})
		if absent.alpha ~= nil then
			controller.setPresentationTransparency(entry.alphaPath, absent.alpha * k)
		end
	end

	-- clear the presentation writes: a node at rest owes nothing to the channel, so
	-- the transient UIScale and the group's transparency go away with the motion
	local function clearEntry(entry: any)
		if controller == nil then
			return
		end
		controller.setPresentationTransform(entry.path, nil)
		if entry.absent.alpha ~= nil then
			controller.setPresentationTransparency(entry.alphaPath, nil)
		end
	end

	local function stopCap(entry: any)
		if entry.cap ~= nil then
			entry.cap:dispose()
			entry.cap = nil
		end
	end

	local function disposeEntry(entry: any)
		if entry.disposed then
			return
		end
		entry.disposed = true
		stopCap(entry)
		if entry.unobserve ~= nil then
			entry.unobserve()
			entry.unobserve = nil
		end
		entry.progress:dispose()
		if entries[entry.path] == entry then
			entries[entry.path] = nil
		end
	end

	local function finishEnter(entry: any)
		if entry.disposed or entry.phase ~= "enter" then
			return
		end
		clearEntry(entry)
		disposeEntry(entry)
		if emit ~= nil then
			-- the causal frame: the thing finished travelling THIS frame
			emit({ type = "arrive", path = entry.path, surface = surface, context = { phase = "enter" } })
		end
	end

	local function finishExit(entry: any)
		if entry.disposed or entry.phase ~= "exit" then
			return
		end
		local done = entry.done
		entry.done = nil
		disposeEntry(entry)
		if done ~= nil then
			done()
		end
	end

	local function entryFor(path: string, node: any, spec: Spec, initial: number, alphaPath: string): any
		local existing = entries[path]
		if existing ~= nil then
			existing.node = node
			existing.spec = spec
			existing.alphaPath = alphaPath
			return existing
		end
		local entry: any = {
			path = path,
			node = node,
			spec = spec,
			alphaPath = alphaPath,
			phase = "idle",
			absent = { x = 0, y = 0 },
			progress = clock:spring(initial, spec.class),
			disposed = false,
		}
		entries[path] = entry
		-- the write rides the VALUE, not the clock step, so an instant placement
		-- (reduced motion) lands exactly like a stepped one — and inside the clock's
		-- single per-frame transaction when it is stepped
		entry.unobserve = core:observe(entry.progress, function()
			writeEntry(entry)
		end)
		entry.progress:onSettle(function()
			if entry.phase == "enter" then
				finishEnter(entry)
			elseif entry.phase == "exit" then
				finishExit(entry)
			end
		end)
		return entry
	end

	local self = {}

	-- the controller does not exist until `renderer.attach` + `initialRender`, and
	-- a transition declared at mount time has already seeded its values. Binding
	-- flushes them, so the first painted frame is the seeded one rather than a
	-- frame at rest followed by a jump.
	function self.bindController(c: any)
		controller = c
		self.flush()
	end

	-- re-assert every running transition's presentation values. A structural
	-- refresh CREATES the handles for a subtree that was mounted since the last
	-- one, and the seed written at mount time had nothing to land on — so without
	-- this a branch entering mid-session paints one frame at rest and then jumps.
	function self.flush()
		for _, entry in entries do
			writeEntry(entry)
		end
	end

	-- task POP mandate (b)'s gate reads this: every backdrop-inside-fade-group
	-- shape any transition on this surface has ever DECLARED, a pure structural
	-- fact with zero frames stepped. A copy, like `controller.stats()` (F-30).
	function self.findings(): { BackdropFinding }
		return table.clone(foundBackdrops)
	end

	function self.beginEnter(path: string, node: any, declared: any)
		if disposed then
			return
		end
		local spec = transitions.resolve(declared)
		local alphaPath, alphaNode = resolveAlphaTarget(path, node)
		assertFadeCapable(alphaPath, alphaNode, spec, spec.enter)
		assertFadeCapable(alphaPath, alphaNode, spec, spec.exit)
		recordBackdropFindings(alphaPath, alphaNode)
		if spec.enter == "instant" then
			-- a hard place: nothing to animate, but the arrival is still a fact the
			-- feedback seam owes its subscribers (information parity)
			local existing = entries[path]
			if existing ~= nil then
				clearEntry(existing)
				disposeEntry(existing)
			end
			if emit ~= nil then
				emit({ type = "arrive", path = path, surface = surface, context = { phase = "enter" } })
			end
			return
		end
		local entry = entryFor(path, node, spec, 0, alphaPath)
		stopCap(entry)
		entry.done = nil
		entry.phase = "enter"
		entry.absent = absentFor(spec, spec.enter, "enter")
		writeEntry(entry) -- seed the absent place before the first step
		entry.progress:setTarget(1)
	end

	-- nil = "dispose now" (no declared transition, or an `instant` exit): the mount
	-- layer then takes its ordinary removal path and nothing is retired.
	function self.shouldRetire(path: string, node: any): any?
		if disposed then
			return nil
		end
		local declared = node ~= nil and node.transition
		if declared == nil or declared == false then
			return nil
		end
		local spec = transitions.resolve(declared)
		if spec.exit == "instant" then
			return nil
		end
		local alphaPath, alphaNode = resolveAlphaTarget(path, node)
		assertFadeCapable(alphaPath, alphaNode, spec, spec.exit)
		recordBackdropFindings(alphaPath, alphaNode)
		return spec
	end

	function self.beginExit(path: string, node: any, spec: Spec, done: () -> ())
		if disposed then
			done()
			return
		end
		local alphaPath = resolveAlphaTarget(path, node)
		local entry = entryFor(path, node, spec, 1, alphaPath)
		entry.phase = "exit"
		entry.done = done
		entry.absent = absentFor(spec, spec.exit, "exit")
		writeEntry(entry)
		-- THE HARD CAP, armed before the aim so an instant form (reduced motion)
		-- disposes it on the way out rather than leaving a timer behind
		stopCap(entry)
		local cap = clock:timer({ from = 0, to = 1, duration = EXIT_CAP_SECONDS, kind = "decorative" })
		entry.cap = cap
		cap:onSettle(function()
			finishExit(entry)
		end)
		-- an aim that completes on the spot (reduced motion) disposes the entry —
		-- and the cap with it — before this returns
		entry.progress:setTarget(0)
	end

	-- the exit is off: park the motion where it stands so the enter that follows
	-- reverses from this value AND this velocity. `release` is the teardown twin.
	function self.cancelExit(path: string)
		local entry = entries[path]
		if entry == nil then
			return
		end
		stopCap(entry)
		entry.done = nil
		entry.phase = "parked"
	end

	function self.release(path: string)
		local entry = entries[path]
		if entry ~= nil then
			entry.done = nil
			disposeEntry(entry)
		end
	end

	function self.dispose()
		if disposed then
			return
		end
		disposed = true
		local held: { any } = {}
		for _, entry in entries do
			table.insert(held, entry)
		end
		for _, entry in held do
			entry.done = nil
			disposeEntry(entry)
		end
		entries = {}
	end

	return self
end

transitions.EXIT_CAP_SECONDS = EXIT_CAP_SECONDS

return transitions
