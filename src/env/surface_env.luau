--!strict
--[[ THE ENVIRONMENT A CONTROL FINDS WHEN NOBODY HANDED IT ONE .

	WHAT WAS WRONG. Adaptation was a fact the AUTHOR had to hand to the control,
	and it failed SILENTLY. `picker.resolvePresentation(4, nil, 14)` returns
	"segmented" — four long labels crammed on a phone — where the same call with a
	size class returns "inline"; `menu_recipe.resolvePresentation` never reaches
	its touch->sheet rung without a live interaction class. The audit
	(`artifacts/release-candidate-review/adapt-audit/matrix.md`)
	counted the consequence: of seventeen `Picker` call sites in `examples/`, eight
	wire the fact, ten disable adaptation outright, and ZERO rely on the adaptive
	default. A ladder that is exported, pure and unit-tested was chosen by no
	shipped surface, which is exactly why the nil-fact path was never caught.

	`tab_view` is the control that got it right — an automatic placement with no
	facts REFUSES to construct, naming the fix — and the standing director ruling
	behind all of this is older than either: "each control/tool must ship with the
	right interaction for ALL supported inputs … verified per input in tests, with
	NO CONSUMER WIRING" (`ui_todo.md` §0, 2026-07-20).

	SO THE FACTS ARRIVE BY THEMSELVES, AND THE CORE IS THE CHANNEL. Every Facet
	environment is built on a core (`environment.new(core)`), every control is
	built on a core (`Facet.Controls.Picker(core, spec)`), and on any real surface
	they are the SAME core — the reactive root that owns the whole surface. So an
	environment publishes itself against its core here, and a control that was
	handed no facts asks. Nothing global at all: the registration lives ON the core
	under one reserved key (see below), so two surfaces are two cores and a
	collected surface takes its own answer with it.

	WHY NOT A CONTRIBUTION SEAM. `src/input/contribution.luau` hands a control the
	presenter's motion clock, focus graph and present functions at PRESENT time,
	and an env seam beside them would have worked for anything read reactively.
	It would not have let a control REFUSE, which is the half of this fix that
	stops a missing fact being silent: at construction the control cannot know
	whether a present will ever come. Answering at construction means a control
	either has its facts or says so, in the same breath, the way `tab_view` does.

	A CORE THAT DELEGATES ANSWERS WITH WHAT IT DELEGATES TO. A host is free to hand
	a control a PROXY of its core — the showcase does, so that everything a demo
	allocates is owned by a scope it can dispose — and such a proxy is the core for
	every other purpose. The registration is READ through an ordinary index for
	exactly that reason and WRITTEN raw, so there is still one owner and one
	registration; `visible` below carries the measurement that bought the rule.

	AMBIGUITY IS REFUSED, NOT RESOLVED — AND IT IS NOT PERMANENT. Two live
	environments on one core make `find` answer nil with a reason, so the control
	raises rather than picking one: a coin flip between two viewports is the silent
	failure this module exists to end. Re-publishing the SAME environment (a
	re-entrant constructor, a caller re-asserting a registration) is not ambiguity.
	`unpublish` takes a registration back, so a surface that tears down — or a core
	whose environment is rebuilt — returns to an unambiguous answer instead of being
	bricked for the rest of the session.
]]

local surfaceEnv = {}

--[[ THE REGISTRATION LIVES ON THE CORE ITSELF — there is no module table at all.

	THE FIRST VERSION was a module-level table, weak on both halves. That is the
	right OWNERSHIP answer and the wrong LIFETIME one (re-review MEDIUM-3): a core
	that outlived every other reference to its environment lost the fact at an
	arbitrary collection, and every adaptive control built afterwards on that live
	core hard-refused. The refusal message itself teaches the exposed pattern —
	build a core, build an environment on it, build controls later — without saying
	the environment has to be retained.

	THE OBVIOUS REPAIR IS A TRAP, AND IT WAS MEASURED RATHER THAN ASSUMED. A strong
	VALUE under a weak KEY does not behave like an ephemeron in Luau: a value that
	references its own key keeps the entry alive. Probed three ways in this VM after
	forcing collection by churning 40 x 20 000 tables through the allocator — a
	weak-key table whose value points back at the key retained 1 of 1; the same
	table with an unrelated value retained 0 of 1; and an environment DOES reference
	its core (it is built from `core:signal`). So "strong value, weak key" would have
	pinned every core and every environment ever created, for the process lifetime.

	SO THE CORE HOLDS ITS OWN REGISTRATION, under one reserved key. The core is the
	surface's reactive root, it is a plain unfrozen table, and every control on the
	surface is built with it — so the fact is exactly as available as the thing that
	owns the surface, and it dies with it because there is nothing else pointing at
	either. No process-global store, nothing to collect, and no GC timing anywhere
	in the answer.

	A CORE THE FRAMEWORK CANNOT ANNOTATE (not a table, or frozen) simply has no
	registration: `find` answers "none" and the control refuses with the message
	that names `env`. That is the loud failure, not a silent bind to somebody else's
	environment — and a frozen core cannot work today for reasons that have nothing
	to do with this module.

	A LIST, NOT A SLOT, so ambiguity is a COUNT rather than a latch. The first
	version set a flag nothing could ever clear, which bricked every adaptive
	control on a core whose environment was rebuilt — permanently, with a build
	error. Holding the live registrations means `unpublish` restores the
	unambiguous answer by arithmetic rather than by a second rule.
]]
local SLOT = "__facetSurfaceEnv"

--[[ THE REGISTRATIONS THIS CORE OWNS — a RAW read, and only the owner may write.
	`publish` and `unpublish` go through here, so a registration always lands on,
	and leaves, the exact table it was made against. ]]
local function registrations(core: any): { any }?
	if type(core) ~= "table" then
		return nil
	end
	local live = rawget(core :: any, SLOT)
	return if type(live) == "table" then live else nil
end

--[[ ...AND THE REGISTRATIONS THIS CORE CAN SEE, which is not the same question and
	cost two shipped demos to learn (live Studio session, 2026-08-20).

	A HOST MAY HAND A CONTROL A CORE THAT DELEGATES. The showcase gives every demo a
	PROXY of its one core so that everything the demo allocates is owned by a
	per-demo scope it can dispose (`examples/gallery/client/demo_host.luau`); the
	proxy forwards every method, so it IS the core for every purpose a control has —
	`core:signal`, `core:memo`, `core:scope` all work through it. Then `find` asked
	`rawget`, saw nothing, and every adaptive control built on a demo core refused to
	construct: `card-rail` and `sorted-entries` both failed to mount in the shipped
	showcase while the whole suite was green, because every spec builds a bare core
	and nothing exercised the path where the fact has to travel one hop.

	SO THE READ IS AN ORDINARY INDEX. A core that delegates answers with what it
	delegates to, which is what "the facts arrive by themselves" has to mean for any
	host that wraps a core rather than passing it. Nothing is copied and nothing is
	republished: there is still exactly ONE registration, on the core the environment
	was built against, and disposal and ambiguity stay answerable in one place.

	A NEARER REGISTRATION WINS, by the same arithmetic that makes it work at all: a
	proxy that published its own is read before the one it delegates to, exactly as a
	local shadows what it closes over.

	IT IS PCALLED because an index is a call now. A proxy free to compute `__index`
	is free to raise on a key it does not know, and a core the framework cannot
	interrogate has no registration — the same answer it already gives for a frozen
	or non-table core. It must never be the thing that takes a construction down. ]]
local function visible(core: any): { any }?
	if type(core) ~= "table" then
		return nil
	end
	local ok, live = pcall(function()
		return (core :: any)[SLOT]
	end)
	if not ok then
		return nil
	end
	return if type(live) == "table" then live else nil
end

-- publish(core, env): the environment of THIS core, for controls built on it.
-- Called by `environment.new`, so every environment — the client host's, a test
-- world's, a consumer's own — is discoverable the same way and no consumer opts
-- in. Publishing the SAME environment twice is not ambiguity (a re-entrant
-- constructor, a caller re-asserting the registration); a second, DIFFERENT one
-- makes the answer ambiguous until one of them is unpublished.
function surfaceEnv.publish(core: any, env: any)
	if type(core) ~= "table" or env == nil or table.isfrozen(core :: any) then
		return
	end
	local live = registrations(core)
	if live == nil then
		rawset(core :: any, SLOT, { env })
		return
	end
	if table.find(live, env) ~= nil then
		return
	end
	table.insert(live, env)
end

--[[ unpublish(core, env) -> boolean — this environment's surface is gone.

	Returns whether an entry was removed, so a caller that releases twice (an
	idempotent `dispose`) is a no-op rather than an error. The only shipped caller
	is `client.host.new`'s teardown, which releases what the host BUILT; a consumer
	standing surfaces up by hand releases by letting the CORE go, which takes the
	registration with it because that is where it lives. ]]
function surfaceEnv.unpublish(core: any, env: any): boolean
	local live = registrations(core)
	if live == nil or env == nil then
		return false
	end
	local at = table.find(live, env)
	if at == nil then
		return false
	end
	table.remove(live, at)
	if #live == 0 then
		rawset(core :: any, SLOT, nil)
	end
	return true
end

-- find(core) -> env?, reason? — reason is "none" (nothing published) or
-- "ambiguous" (more than one LIVE environment on this core). Never raises: a
-- caller that can degrade (a headless unit mount) is a legal caller.
function surfaceEnv.find(core: any): (any?, string?)
	-- what this core can SEE, not only what it owns: a delegating core (a host's
	-- per-demo proxy) answers with its owner's environment. See `visible` above.
	local live = visible(core)
	if live == nil or #live == 0 then
		return nil, "none"
	end
	if #live > 1 then
		return nil, "ambiguous"
	end
	return live[1], nil
end

--[[ resolve(control, id, core, specEnv, need) -> env, source

	The refusal, spelled once for every control that adopts it, in `tab_view`'s
	shape: say what the control was asked to decide, say what it needs, and name
	the two ways to give it — the host that publishes the environment for free,
	and the explicit key for a control whose core is not that surface's.

	`source` is "spec" or "core", and controls report it on their dump so a screen
	can be audited for wiring it never had to do.
]]
function surfaceEnv.resolve(control: string, id: string, core: any, specEnv: any, need: string): (any, string)
	if specEnv ~= nil then
		return specEnv, "spec"
	end
	local env, reason = surfaceEnv.find(core)
	if env ~= nil then
		return env, "core"
	end
	if reason == "ambiguous" then
		error(
			`Facet {control}('{id}'): {need}, and this core has MORE THAN ONE environment, so the framework `
				.. "will not guess which surface this control belongs to. Pass `env` (or the fact itself) "
				.. "explicitly, or build the second surface on its own core.",
			0
		)
	end
	error(
		`Facet {control}('{id}'): {need}, and no environment was found. A surface stood up with `
			.. "`Facet.client.host.new` publishes its environment on the core it builds, and every control "
			.. "on that core then adapts with no wiring at all; a headless caller gets the same by building "
			.. "one with `Facet.newEnvironment(core)` before the control. Or pass `env` — and a control that "
			.. "must NOT adapt says so by declaring the fixed answer instead.",
		0
	)
end

return surfaceEnv
