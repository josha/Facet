--!strict
-- The structural-transition COORDINATOR (ADR-0022 Decision 3; ui-designer spec
-- §2.1; acceptance row SF-M6). It is the mount layer's `transitions` collaborator,
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
			"LuauUI transition: a transition is a table { enter = <form>, exit? , class?, fade? } — "
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
	}
end

local function fades(spec: Spec, form: string): boolean
	return spec.fade or (schema.TRANSITION_FADES :: any)[form] == true
end

function transitions.new(opts: Opts)
	assert(type(opts) == "table" and opts.core ~= nil, "LuauUI transitions: a core is required")
	assert(opts.clock ~= nil, "LuauUI transitions: a motion clock is required (LuauUI.motion.newClock)")
	local core = opts.core
	local clock = opts.clock
	local controller: any = opts.controller
	local metricsOf = opts.metrics or themeSnapshot.neutral
	local emit = opts.feedback
	local surface = opts.surface

	local entries: { [string]: any } = {}
	local disposed = false

	local function slideDistance(): number
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
			local d = slideDistance()
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
			`LuauUI transition: {path} declares a '{form}' transition, which fades — but the node it applies to `
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
			controller.setPresentationTransparency(entry.path, absent.alpha * k)
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
			controller.setPresentationTransparency(entry.path, nil)
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

	local function entryFor(path: string, node: any, spec: Spec, initial: number): any
		local existing = entries[path]
		if existing ~= nil then
			existing.node = node
			existing.spec = spec
			return existing
		end
		local entry: any = {
			path = path,
			node = node,
			spec = spec,
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

	function self.beginEnter(path: string, node: any, declared: any)
		if disposed then
			return
		end
		local spec = transitions.resolve(declared)
		assertFadeCapable(path, node, spec, spec.enter)
		assertFadeCapable(path, node, spec, spec.exit)
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
		local entry = entryFor(path, node, spec, 0)
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
		assertFadeCapable(path, node, spec, spec.exit)
		return spec
	end

	function self.beginExit(path: string, node: any, spec: Spec, done: () -> ())
		if disposed then
			done()
			return
		end
		local entry = entryFor(path, node, spec, 1)
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
