--!strict
--[[ THE CLIENT HOST — one blessed way to stand a Facet surface up on Roblox and
	drive it (reuse audit REUSE-109/115; ARCH boundary list; api.md §Client entry
	points).

	WHAT WAS WRONG. Standing up a surface takes six steps in a fixed order — a
	core, an environment, the environment BOUND to the engine, a render target, an
	input system, a presenter — and then one per-frame drive. There was no
	framework entry that did it, so every consumer wrote its own: NINE of them —
	four in the shipped game, three in this repository's examples, and TWO in the
	guide (`03-getting-started.md` and `08-without-rojo.md`, the page an adopter
	without Rojo lands on). This census said eight and missed the ninth, which was
	still teaching the defect below when the R5 review found it.
	THREE OF THE FOUR GAME BOOTSTRAPS DROVE ONLY `refresh()`. `refresh`
	re-solves whatever the frame dirtied; `tick` advances the MOTION CLOCK that
	every transition, toast schedule, spring and timer rides. So on those surfaces
	a toast never expired, a transition never completed and a spring never
	settled — and nothing said so, because a frozen clock and a settled one look
	identical in a dump.

	The root cause was framework-side and is the reason this module exists rather
	than a round of fixes: `docs/guide/03-getting-started.md` TAUGHT
	`RunService.Heartbeat:Connect(function() presenter.refresh() end)` and never
	mentioned `tick` at all. Fixing four call sites would have left the next
	author copying the same lesson out of the same page.

	PreRender, NOT Heartbeat — `src/client/motion_driver.luau` states the rule:
	Heartbeat runs AFTER render, so everything the tick drives arrives a frame
	late. The one surface that had it right (RascalRally's `FacetSponsor`) is the
	idiom this module encodes, comment for comment.

	YOUR PER-FRAME WORK GOES ON `presenter.onTick`, NOT ON A SECOND CONNECTION.
	`presenter.onTick` already calls itself "the one sanctioned frame source
	outside the motion clock itself — a second RunService connection in a consumer
	is the bug class this prevents", and the audit counted thirteen game modules
	across three different RunService signals for what is conceptually one UI
	frame (REUSE-115). Hooks run after the motion step, so they read this frame's
	settled values, and they are quarantined: a throwing hook cannot starve its
	siblings or escape into the render thread.

	THE ADAPTIVE FACTS COME WITH THE HOST (ADAPT-1, 2026-08-18). `host.new` builds
	the environment (step two of the six), and an environment publishes itself
	against the core it was built on — so every control this host's presenter goes
	on to mount finds the size class, the live interaction classes and the
	keyboard-occlusion rect with NO authoring at all. That is the whole of the
	audit's spine finding: adaptation used to be a fact the AUTHOR handed to each
	control, silently taking the large-screen, pointer answer when nobody did, and
	the census found zero of seventeen shipped `Picker` call sites relying on the
	adaptive default. A hosted screen now gets the adaptive answer by standing up,
	and a control that CANNOT get its facts says so at construction rather than
	presenting the wrong idiom (`src/env/surface_env.luau`).

	The publication lives in `environment.new`, not here, so a headless world, an
	Edit-mode preview and a consumer's own bootstrap behave identically — this host
	is the blessed path, not a privileged one. A consumer that supplies its own
	core through `newCore` still gets it, because the environment this module
	builds is built on THAT core.

	NOTHING ENGINE-ONLY IS REQUIRED AT MODULE SCOPE, deliberately — the
	`roblox_env.bind` / `text_premeasure.textService` idiom. `screen_target` and
	`roblox_input` resolve inside `new`, so this module can be REQUIRED and driven
	headlessly with the seams below; that is what lets the frame contract this
	whole module exists to fix have a test at all.
]]

local specGuard = require("../spec_guard")
local customCore = require("../core/custom")
local environment = require("../env/environment")
local presenterLib = require("../present/presenter")

local host = {}

export type Opts = {
	-- ===== render target (forwarded to `screen_target.new`) ================
	-- opt in to the Roblox StyleSheet paint path; nil = the library default
	nativeStyle: boolean?,
	style: any?,
	-- the PlayerGui to parent roots under; nil = the local player's own
	-- (Studio Edit-mode previews pass an explicit host, which has no LocalPlayer)
	parent: Instance?,
	autoLocalize: boolean?,
	themePackage: any?,
	--[[ WHERE THIS SURFACE SITS AGAINST THE GAME'S OWN `ScreenGui`s (REUSE-122).
		Facet roots were created with `DisplayOrder` unset — which is 0, and the
		audit found seventeen hand-made game `ScreenGui`s carrying scattered
		numbers between 90 and 100, so every native surface floated above every
		Facet surface by default and nobody had decided that. Stating it here is
		how a consumer LAYERS instead of discovering. ]]
	displayOrder: number?,

	-- ===== presenter =======================================================
	--[[ the presenter's wall clock. The toast schedule's dwell and the renderer's
		one-activation-per-press guard both ride it, so a headless spec injects one
		to put two real presses either side of the echo window. ]]
	now: (() -> number)?,

	-- ===== seams (headless, Edit mode, or a consumer that owns a piece) =====
	newCore: (() -> any)?,
	bindEnv: ((env: any) -> () -> ())?,
	newAdapter: (() -> any)?,
	newInputSystem: ((core: any) -> any)?,
	--[[ the frame source. Takes the per-frame function and returns its
		disconnect. Absent = `RunService.PreRender`, which is the answer for every
		shipped consumer; a spec passes one so it can step frames by hand. ]]
	connectFrame: ((fn: (dt: number) -> ()) -> () -> ())?,
}

export type Host = {
	core: any,
	env: any,
	adapter: any,
	inputSystem: any,
	presenter: any,
	dispose: () -> (),
}

local OPTS_KEYS = specGuard.keySet({
	"nativeStyle",
	"style",
	"parent",
	"autoLocalize",
	"themePackage",
	"displayOrder",
	"now",
	"newCore",
	"bindEnv",
	"newAdapter",
	"newInputSystem",
	"connectFrame",
})

--[[ The engine collaborators, resolved HERE rather than at module scope, so
	requiring this file stays legal off-engine (see the header). Each is behind
	its own seam above, so a headless caller never reaches any of them. ]]
local function engineAdapter(opts: Opts): any
	local screen_target = require("./screen_target") :: any
	return screen_target.new({
		nativeStyle = opts.nativeStyle,
		style = opts.style,
		parent = opts.parent,
		autoLocalize = opts.autoLocalize,
		themePackage = opts.themePackage,
		displayOrder = opts.displayOrder,
	})
end

local function engineInputSystem(core: any): any
	local roblox_input = require("./roblox_input") :: any
	return roblox_input.newSystem(core)
end

local function engineBindEnv(env: any): () -> ()
	local roblox_env = require("./roblox_env") :: any
	return roblox_env.bind(env)
end

local function engineConnectFrame(fn: (dt: number) -> ()): () -> ()
	local RunService = game:GetService("RunService")
	local conn = RunService.PreRender:Connect(fn)
	return function()
		conn:Disconnect()
	end
end

--[[ Stand up a Facet client surface, bound and driven.

	Returns the six pieces a consumer needs plus `dispose`. Present your
	blueprints on `presenter`; register per-frame work with `presenter.onTick`.

	`dispose()` releases what the host BUILT — the frame connection, the input
	system, the render target and the environment binding, in that order — and
	nothing else. It is idempotent, and a piece you supplied through a seam with
	no `dispose` of its own is left untouched.

	CONSTRUCTION IS ALL-OR-NOTHING. A failure halfway through must not leave a
	bound environment or a live root behind — a half-built host is exactly the
	state whose teardown nobody writes — so every step that has already succeeded
	is undone before the error is re-raised.
]]
function host.new(opts: Opts?): Host
	specGuard.assertKnownKeys("client.host.new", opts, OPTS_KEYS, "opts")
	local o: Opts = opts or {}

	local core = (if o.newCore then o.newCore() else customCore.new()) :: any
	local env = environment.new(core)

	-- undo stack, innermost last: whatever succeeded is what gets torn down
	local undo: { () -> () } = {}
	local function unwind()
		for i = #undo, 1, -1 do
			pcall(undo[i])
		end
		table.clear(undo)
	end

	local built: any = nil
	local ok, err = pcall(function()
		local unbindEnv = if o.bindEnv then o.bindEnv(env) else engineBindEnv(env)
		table.insert(undo, unbindEnv)

		--[[ EVERY BUILT THING GOES ON THE STACK AS IT IS BUILT (R5 review §3b-2).
			The first version pushed only the env binding and the frame connection,
			which had two consequences and hid both: a throw from `newInputSystem` —
			reachable, `roblox_input` asserts after a 5 s `PlayerScripts` wait —
			abandoned a fully constructed render target whose pointer seam had
			already opened an adapter-wide `GuiService.MenuOpened` connection, and a
			SUCCESSFUL `dispose()` leaked the same two objects. `unwind` is the same
			list both paths run, so there is one answer to "what did the host hold"
			rather than two.

			GUARDED, because these are seams: a consumer may hand in an adapter or
			an input system it owns and intends to keep (a billboard target, one
			system shared across surfaces). No `dispose` method means the host built
			nothing to release and touches nothing. ]]
		local function ownIfDisposable(thing: any)
			if type(thing) == "table" and type(thing.dispose) == "function" then
				table.insert(undo, function()
					thing.dispose()
				end)
			end
		end

		local adapter = if o.newAdapter then o.newAdapter() else engineAdapter(o)
		ownIfDisposable(adapter)
		local inputSystem = if o.newInputSystem then o.newInputSystem(core) else engineInputSystem(core)
		ownIfDisposable(inputSystem)
		local presenter = presenterLib.new(core, env, adapter, inputSystem, { now = o.now })

		--[[ THE FRAME, AND BOTH HALVES OF IT. `tick(dt)` first: it steps the
			motion clock and then runs the registered `onTick` hooks, so a hook reads
			this frame's settled values. `refresh()` last: it re-solves whatever this
			frame dirtied, including whatever the hooks just wrote, and is a no-op
			when nothing is dirty. Reversing them costs every hook a frame of
			latency, which is the same defect as driving `refresh` alone, one frame
			smaller. ]]
		--[[ ONE CLOCK, ONE DRIVER (R5 review §3b-3). Claimed BEFORE the connection
			exists, so a presenter already driven by `motion_driver.bind` refuses the
			host rather than quietly double-ticking, and a later `motion_driver.bind`
			on this host's presenter refuses too. On the undo stack like everything
			else, so a torn-down surface can be stood back up. ]]
		table.insert(undo, presenter.claimFrameDriver("client.host"))

		local disposed = false
		local disconnect = (if o.connectFrame then o.connectFrame else engineConnectFrame)(function(dt: number)
			if disposed then
				return
			end
			presenter.tick(dt)
			presenter.refresh()
		end)
		table.insert(undo, disconnect)

		built = {
			core = core,
			env = env,
			adapter = adapter,
			inputSystem = inputSystem,
			presenter = presenter,
			--[[ IDEMPOTENT, AND THE FRAME GOES FIRST. `unwind` runs the stack in
				reverse, so the order is: frame connection, input system, render
				target, environment binding. A frame that landed between the unbind
				and the disconnect would drive a presenter whose environment has
				stopped answering, which is the one ordering that turns a clean
				teardown into a mid-frame error.

				WHAT IT DOES NOT DISPOSE, stated because the first version of this
				comment over-promised: the PRESENTER and the CORE. Neither has a
				teardown seam — the presenter's state is owned by the core's reactive
				graph, and the core may be the caller's own (`opts.newCore`). Nor does
				it dismiss what you presented; a handle is the consumer's. ]]
			dispose = function()
				if disposed then
					return
				end
				disposed = true
				unwind()
			end,
		}
	end)
	if not ok then
		unwind()
		error(err, 0)
	end
	return built :: Host
end

return host
