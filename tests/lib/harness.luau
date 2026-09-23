--!strict
--[[ IS: a spec-side adapter over a REAL core, presenter and control library —
	it lets a spec build nodes outside a component (`harness.UI.X`,
	`harness.Controls.X(core, spec)`) through THAT core's own library, and hands
	back the `{ api, dump }` record `ref` gives an application.
	IS NOT: a second authoring path, and not production's shape (an application
	builds inside a mount). What a case builds here is held by that CASE's owner,
	released when the case ends, and what is left behind fails the case. ]]
local Facet = require("../../src") :: any
local Compose = Facet.Compose
local blueprint = require("../../src/blueprint")
local testkit = require("./testkit")
local services = require("../../src/core/services")
local presenterLib = require("../../src/present/presenter")
local sceneLib = require("../../src/render/compose_scene")
local controlsLib = require("../../src/render/compose_controls")
local observeChange = require("../../src/core/on_change")
local cleanup = require("../../src/core/cleanup")

local harness = {}

-- The pure helpers construct no node and read no runtime, so they answer
-- straight off `blueprint` rather than through any core's library.
local PURE_HELPERS: { [string]: boolean } = {
	fill = true,
	hug = true,
	cornersData = true,
	shadowData = true,
	gradientData = true,
	strokeData = true,
	sortedEntries = true,
	schema = true,
}

local stages: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any
local activeCore: any = nil
local inCase = false
-- the fallback core for a construction that names none (see `currentCore`)
local ambientCore: any = nil

--[[ ── THE ONE REMAINING DECORATION, AND WHAT IT IS FOR ───────────────────────
	A `build(library, core, spec)` a spec calls DIRECTLY — `virtual_list.build(
	Facet, core, {...})`, the shape ~110 spec files use to reach a control's
	arithmetic without a surface — hands `Facet` where a control expects the
	LIBRARY (`library.UI`, `library.Controls`, `library.runtime`). `Facet` is the
	package table and has none of those, so the call would index nil.

	So a direct call is REDIRECTED to the active core's own library. This is a
	construction adapter and nothing else: it no longer records what was built.
	The control's record reaches a spec the way it reaches an application, off
	`ref` — see `harness.Controls` below. ]]
local CONTROL_MODULES = {
	"alert",
	"async_image",
	"button",
	"callout",
	"chip",
	"collapsible_view",
	"combo_box",
	"disclosure_group",
	"label",
	"shortcut_hint",
	"badge",
	"skeleton",
	"status_indicator",
	"avatar",
	"avatar_group",
	"level_picker",
	"menu",
	"navigation_stack",
	"page_view",
	"picker",
	"picker_menu",
	"popover",
	"dialog",
	"notice",
	"snackbar",
	"progress_view",
	"radial_menu",
	"rating",
	"row_actions",
	"sheet",
	"slider",
	"split_button",
	"stepper",
	"tab_view",
	"table",
	"text_input",
	"toggle",
	"virtual_list",
	"virtual_grid",
}
for _, name in CONTROL_MODULES do
	local module = require("../../src/controls/" .. name) :: any
	local original = module.build
	module.build = function(library, core, ...)
		if library ~= Facet then
			return original(library, core, ...)
		end
		local args = table.pack(...)
		return harness.owned(function()
			return original(select(3, harness.libraryOf(core)), core, table.unpack(args, 1, args.n))
		end)
	end
end

-- ONE UI RUNTIME PER CORE, as an application has: the core adopts its runtime's
-- reactor, so a write settles that surface and a failure inside it is contained
-- by that core's boundary rather than by whichever core happened to be built
-- first.
local function newDomain(): (any, { [any]: boolean })
	local frames: { [any]: boolean } = {}
	return sceneLib.new({
		onFrame = function(callback)
			frames[callback] = true
			return function()
				frames[callback] = nil
			end
		end,
		now = os.clock,
	}),
		frames
end

--[[ ── THE PER-CASE LEDGER ───────────────────────────────────────────────────
	Every core a case builds is recorded here, with the owner that holds what the
	case constructed outside a component. `release` runs at the end of the case
	(registered once with testkit below), disposes those owners, and REPORTS what
	did not come back — a control whose teardown throws, or a mount root the case
	opened and never stopped, is a leak this harness used to make invisible by
	hanging everything off one process-wide owner that was never disposed. ]]
local caseCores: { any } = {}
local caseAdapters: { { core: any, adapter: any } } = {}
local retainReason: string? = nil

--[[ THE OPT-OUT IS A STRING, NOT A FLAG. A fixture that deliberately keeps a
	surface open past the end of its case says WHY, in the case, where the next
	reader sees it — `false` with no reason is how an always-on check becomes a
	check nobody notices is off. ]]
function harness.retains(reason: string)
	assert(type(reason) == "string" and reason ~= "", "harness.retains(reason): say WHY this case keeps what it keeps")
	retainReason = reason
end

--[[ A WORLD REGISTERS ITS RENDER TARGET HERE so the release can ask it, at the
	end of the case, whether anything is still mounted on it. A target with no
	`liveCount` (a fault injector, a billboard) is simply not asked. ]]
function harness.watchAdapter(core: any, adapter: any)
	if type(adapter) == "table" and type(adapter.liveCount) == "function" then
		table.insert(caseAdapters, { core = core, adapter = adapter })
	end
end

local function stageOf(core: any): any
	local stage = stages[core]
	if stage == nil then
		local domain, frames = newDomain()
		if core ~= nil and type(core.adopt) == "function" then
			core.adopt(domain.runtime)
		end
		--[[ NOT guarded with the core's boundary, deliberately. `core.adopt` already
			puts the core's settle pass and its containment on this runtime's reactor,
			which is where a mounted surface's failures are contained. An owner-level
			boundary here would additionally swallow the refusals a spec CONSTRUCTS
			ON PURPOSE — `expect(...).toThrow()` over a malformed spec — and turn
			every one of them into a silent warning. ]]
		local owner = Compose.createOwner(domain.runtime.reactor)
		stage = {
			domain = domain,
			runtime = domain.runtime,
			surfaces = {},
			presenter = nil,
			frames = frames,
			owner = owner,
			roots = {},
			handles = {},
			services = {},
		}
		stages[core] = stage
		if core ~= ambientCore then
			table.insert(caseCores, core)
		end
	end
	return stage
end

local function libraryOf(core: any): (any, any, any)
	local stage = stageOf(core)
	if stage.api == nil then
		stage.api, stage.UI, stage.library = controlsLib.new(stage.runtime, core, stage.presenter, stage.surfaces)
	end
	return stage.api, stage.UI, stage.library
end

--[[ A NODE BUILT OUTSIDE A COMPONENT BELONGS TO THIS CASE'S OWNER — and there
	is NO CORE-LESS LIBRARY behind it any more. The previous harness kept one
	built with `controls.new(runtime, nil, nil, {})` (no core, no presenter) and
	mounted nodes from it into a different library's runtime; a failure with no
	active core became a `warn()` and the surface carried on.

	A construction with no core of its own now gets the AMBIENT core: a real
	`services.new()` with a real library, real containment and a real settle pass.
	File-scope refusal fixtures keep that registration-time core. During a case,
	implicit constructions get a tracked core instead: function arguments can
	build a node before the receiving helper calls `harness.newCore()`. ]]

local function currentCore(): any
	if activeCore ~= nil then
		return activeCore
	end
	if inCase then
		return harness.newCore()
	end
	if ambientCore == nil then
		ambientCore = services.new()
	end
	return ambientCore
end

local function owned<T...>(build: () -> T...): T...
	if Compose.currentOwner() ~= nil then
		return build()
	end
	return Compose.withOwner(stageOf(currentCore()).owner, build)
end

harness.libraryOf = libraryOf
harness.owned = owned

function harness.newCore(...)
	activeCore = services.new(...)
	libraryOf(activeCore)
	return activeCore
end

-- Selects the core that later `UI` calls construct into.
function harness.use(core: any)
	activeCore = core
end

-- Advances the core's UI runtime by one frame. A presenter does this on tick.
function harness.step(core: any, dt: number?)
	for callback in table.clone(stageOf(core).frames) do
		callback(dt or 1 / 60)
	end
end

-- How many frame listeners the UI runtime holds: one per playing timeline, plus
-- one shared by every running tween and spring.
function harness.frameListeners(core: any): number
	local count = 0
	for _ in stageOf(core).frames do
		count += 1
	end
	return count
end

harness.coreFactory = { new = harness.newCore }
local function trackService(core: any, service: any)
	local ledger = stageOf(core).services
	if table.find(ledger, service) == nil then
		table.insert(ledger, service)
	end
end

function harness.newEnvironment(core: any)
	local env = Facet.newEnvironment(core)
	trackService(core, env)
	return env
end

function harness.newActionSystem(core: any)
	local system = Facet.newActionSystem(core)
	trackService(core, system)
	return system
end

-- Mounts a node, or a component function, and returns the renderer's root.
function harness.mount(core: any, content: any, _opts: any?)
	local stage = stageOf(core)
	local target = stage.domain.target()
	local component = if type(content) == "function"
		then content
		else function()
			return content
		end
	local stop = stage.runtime.mount(component, target)
	local root = stage.domain.root(target, stop)
	--[[ EVERY MOUNT THIS HARNESS OPENS IS RECORDED, because this is the ONLY
		mount site a spec reaches: `wrapped.present` and the presenter's own
		`mountComponent` both come through here. The case's release stops the ones
		the spec did not, and only then asks whether any are outstanding — so the
		check answers "did something else open a root and lose it", which is the
		leak, rather than "did this spec bother to dismiss", which is housekeeping. ]]
	table.insert(stage.roots, stop)
	-- `opts.feedback` scripts the sink a presenter supplies.
	if _opts ~= nil and _opts.feedback ~= nil then
		root.setFeedback(_opts.feedback, function(source: any, onChange: () -> ())
			return observeChange(core.owner, source, onChange)
		end)
	end
	return root
end

function harness.newPresenter(core: any, env: any, adapter: any, system: any, opts: any?)
	activeCore = core
	local stage = stageOf(core)
	trackService(core, env)
	trackService(core, system)
	local presenterOpts = table.clone(opts or {})
	-- How the presenter mounts a surface it builds for itself.
	presenterOpts.mountComponent = function(component: any)
		local _, internalUI = libraryOf(core)
		return harness.mount(core, function()
			return component(internalUI)
		end)
	end
	local pres = presenterLib.new(core, env, adapter, system, presenterOpts)
	stage.presenter = pres
	pres.onTick(function(dt)
		harness.step(core, dt)
	end)
	stage.api, stage.UI = nil, nil
	libraryOf(core)
	local wrapped = setmetatable({}, { __index = pres }) :: any
	--[[ EVERY SURFACE THIS PRESENTER OPENS IS RECORDED, for the same reason every
		mount is: the case's release dismisses the ones the spec did not, and only
		then asks the render target whether anything is left on it. A presented
		surface's host instances live until the PRESENTER lets go of it — stopping
		the mount root is not enough. ]]
	local function remember(handle: any): any
		if type(handle) == "table" then
			table.insert(stage.handles, handle)
		end
		return handle
	end
	local function present(method: string)
		return function(content: any, options: any?)
			activeCore = core
			return remember(pres[method](harness.mount(core, content), options))
		end
	end
	wrapped.present = present("present")
	wrapped.presentModal = present("presentModal")
	-- An anchored panel is a node or a component; the presenter synthesizes the
	-- surface around it and the harness mounts that surface.
	function wrapped.presentAnchored(panel: any, options: any?)
		activeCore = core
		local component = if type(panel) == "function"
			then panel
			else function()
				return panel
			end
		return remember(pres.presentAnchored(component, options, function(build, presentOptions, presentSurface)
			local _, internalUI = libraryOf(core)
			return presentSurface(
				harness.mount(core, function()
					return build(internalUI)
				end),
				presentOptions
			)
		end))
	end
	-- A toast body is a node or a component; the toast's row owns a component.
	function wrapped.presentToast(content: any, options: any?)
		activeCore = core
		return remember(pres.presentToast(
			if type(content) == "function"
				then content
				else function()
					return content
				end,
			options
		))
	end
	-- The surfaces a control opens for itself.
	local surfaces = stage.surfaces
	surfaces.modal = wrapped.presentModal
	surfaces.anchored = wrapped.presentAnchored
	function surfaces.callout(spec: any)
		return pres.presentCallout(spec, surfaces.anchored)
	end
	return wrapped
end

harness.presenterLib = setmetatable({ new = harness.newPresenter }, { __index = presenterLib })

--[[ `harness.UI.X` builds through the LIBRARY THE ACTIVE CORE USES — there is no
	second, core-less library standing behind it any more. The pure helpers, which
	construct no node, answer straight off `blueprint` and need no core. ]]
harness.UI = setmetatable({}, {
	__index = function(_, name: string)
		--[[ A non-function member (`PROP_DIRTY`, `schema`) and a pure helper both
			answer off `blueprint`: neither constructs a node, so neither needs a
			runtime. Everything else is a constructor or a modifier and goes through
			the library the core actually uses. ]]
		local base = (blueprint :: any)[name]
		if base ~= nil and (type(base) ~= "function" or PURE_HELPERS[name]) then
			return base
		end
		return function(...)
			local _, UI = libraryOf(currentCore())
			local member = UI[name]
			if type(member) ~= "function" then
				return member
			end
			local args = table.pack(...)
			return owned(function()
				return member(table.unpack(args, 1, args.n))
			end)
		end
	end,
}) :: any

--[[ `Controls.Name(core, spec)` builds the control THE WAY AN APPLICATION DOES —
	through the composite constructor, taking the record off `ref` — and returns
	`{ api, dump, blueprint }`. The record reads through to `api`, so a spec keeps
	spelling `control.verb()`; the node it built is `blueprint`.

	`dispose` is the CASE'S OWN OWNER for this construction, not the control's
	internal disposer: `composite()` registers that one with `Compose.cleanup`,
	so releasing the owner is what an application's surface does at unmount and
	is the only correct way for a spec to end a control's life. ]]
harness.Controls = setmetatable({}, {
	__index = function(_, name: string)
		return function(core: any, spec: any)
			activeCore = core
			local api = libraryOf(core)
			--[[ THE CONTROL BELONGS TO WHOEVER IS BUILDING IT. Inside a component —
				which is where an application builds one — that is the mount's own
				owner, so the control dies with the surface exactly as it does in
				production. Outside every component it is this CASE's owner, which the
				release disposes. Either way the harness interposes a CHILD, so a spec
				whose subject IS disposal has one handle to pull. ]]
			local stage = stageOf(core)
			local parent = Compose.currentOwner() or stage.owner
			local scope = parent.createChild()
			local captured: any = nil
			local supplied = table.clone(spec or {})
			assert(supplied.ref == nil, `harness.Controls.{name}: the harness owns \`ref\`; read the record it returns`)
			supplied.ref = function(record: any)
				captured = record
			end
			local ok, node = pcall(Compose.withOwner, scope, function()
				return api[name](supplied)
			end)
			if not ok then
				scope.dispose()
				error(node, 0)
			end
			local record = {
				blueprint = node,
				api = if captured ~= nil then captured.api else nil,
				dump = if captured ~= nil then captured.dump else nil,
				dispose = scope.dispose,
			}
			return setmetatable(record, {
				__index = function(_, key: string)
					local inner = record.api
					return if type(inner) == "table" then (inner :: any)[key] else nil
				end,
			}) :: any
		end
	end,
}) :: any

--[[ ── THE RELEASE, AT THE END OF EVERY CASE ─────────────────────────────────
	`harnessOwner` used to be one process-wide owner that was never disposed, so
	`Compose.cleanup(built.dispose)` registered on an immortal owner and NOTHING a
	spec built out here was ever released — a control leak was invisible by
	construction. Each case now gets its own owners, and this releases them:
	surfaces first (every mount this harness opened), then the constructions the
	surfaces were built from.

	TWO THINGS ARE ASKED AFTERWARDS, and either FAILS the case:

	  · did a teardown THROW? A disposer that raises has left something behind,
	    and the owner's own containment would otherwise swallow it whole;
	  · is the render target EMPTY? `adapter.liveCount()` is the count of host
	    instances the surface still holds. A case that opened a surface and lost
	    the handle leaves them behind, and the next case inherits them — which is
	    the leak the previous harness could not see at all.

	A fixture that means to keep what it keeps says so with `harness.retains`. ]]
local EXIT_FRAME_BUDGET = 180

-- every watched target of THIS core reports nothing mounted
local function adaptersEmpty(adapters: { { core: any, adapter: any } }, core: any): boolean
	for _, entry in adapters do
		if entry.core ~= core then
			continue
		end
		local ok, live = pcall(entry.adapter.liveCount)
		if ok and type(live) == "number" and live > 0 then
			return false
		end
	end
	return true
end

local function releaseCase()
	local cores, adapters, reason = caseCores, caseAdapters, retainReason
	caseCores, caseAdapters, retainReason = {}, {}, nil
	local failures: { string } = {}
	local resources = {}
	for _, core in cores do
		local stage = stages[core]
		if stage == nil then
			continue
		end
		--[[ The presenter lets go of its surfaces first, then the mounts under them,
			and last the constructions those were built from.

			AND THE EXIT IS RUN OUT. `dismiss` starts a surface's exit transition; the
			host instances go when it lands, so a target read on the dismissing frame
			still holds them and a leak check reading it there would accuse every
			animated surface in the suite. Frames are pumped until the target is empty
			or the budget is spent — far more than any shipped exit takes, and nothing
			at all for a case that opened no surface. ]]
		local pres = stage.presenter
		for index = #stage.handles, 1, -1 do
			local handle = stage.handles[index]
			-- a toast carries its OWN dismiss (it retires on a schedule, so the
			-- presenter's surface stack never held it); everything else goes back
			-- through the presenter
			if type(handle.dismiss) == "function" then
				pcall(handle.dismiss)
			elseif pres ~= nil and type(pres.dismiss) == "function" then
				pcall(pres.dismiss, handle)
			end
		end
		if pres ~= nil and #stage.handles > 0 and type(pres.tick) == "function" then
			for _ = 1, EXIT_FRAME_BUDGET do
				if adaptersEmpty(adapters, core) then
					break
				end
				local ok = pcall(function()
					pres.tick(1 / 60)
					pres.refresh()
				end)
				if not ok then
					break
				end
			end
		end
		if pres ~= nil then
			local ok, err = pcall(pres.dispose)
			if not ok then
				table.insert(failures, `presenter shutdown threw: {tostring(err)}`)
			end
		end
		for index = #stage.roots, 1, -1 do
			local ok, err = pcall(stage.roots[index])
			if not ok then
				table.insert(failures, `a surface teardown threw while releasing the case: {tostring(err)}`)
			end
		end
		local releases = {
			stage.owner.dispose,
			function()
				stage.runtime:dispose()
			end,
		}
		for index = #stage.services, 1, -1 do
			table.insert(releases, stage.services[index].dispose)
		end
		table.insert(releases, core.settlePass.dispose)
		table.insert(releases, core.owner.dispose)
		for _, release in releases do
			table.insert(resources, release)
		end
	end
	-- A later core can mount nodes that read an earlier core's state. Close
	-- every surface and mount before releasing any of those state owners.
	local ok, err = pcall(cleanup, resources)
	if not ok then
		table.insert(failures, `a teardown threw while releasing the case's resources: {tostring(err)}`)
	end
	-- Tick and cleanup callbacks still resolve this core's original stage.
	for _, core in cores do
		stages[core] = nil
	end
	activeCore = nil
	if reason ~= nil then
		return failures
	end
	for _, entry in adapters do
		local ok, live = pcall(entry.adapter.liveCount)
		if ok and type(live) == "number" and live > 0 then
			table.insert(
				failures,
				`the render target still holds {live} host instance(s) after everything this case built was `
					.. 'released. Close what the case opened, or say why it keeps it with harness.retains("<reason>").'
			)
		end
	end
	return failures
end

testkit.beforeEach(function()
	inCase = true
end)

testkit.afterEach(function()
	local failures = releaseCase()
	inCase = false
	if #failures > 0 then
		error("Facet harness leak check:\n  " .. table.concat(failures, "\n  "), 0)
	end
end)

return harness
