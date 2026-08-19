--!strict
--[[ THE ENVIRONMENT A CONTROL FINDS WHEN NOBODY HANDED IT ONE (ADAPT-1).

	WHAT WAS WRONG. Adaptation was a fact the AUTHOR had to hand to the control,
	and it failed SILENTLY. `picker.resolvePresentation(4, nil, 14)` returns
	"segmented" — four long labels crammed on a phone — where the same call with a
	size class returns "inline"; `menu_recipe.resolvePresentation` never reaches
	its touch->sheet rung without a live interaction class. The audit
	(`artifacts/release-candidate-review/adapt-audit/matrix.md`, ADAPT-1, critical)
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
	handed no facts asks. Nothing global: the key is the caller's own core, the
	table is weak on both halves, and two surfaces are two cores.

	WHY NOT A CONTRIBUTION SEAM. `src/input/contribution.luau` hands a control the
	presenter's motion clock, focus graph and present functions at PRESENT time,
	and an env seam beside them would have worked for anything read reactively.
	It would not have let a control REFUSE, which is the half of this fix that
	stops a missing fact being silent: at construction the control cannot know
	whether a present will ever come. Answering at construction means a control
	either has its facts or says so, in the same breath, the way `tab_view` does.

	AMBIGUITY IS REFUSED, NOT RESOLVED. A second environment on the same core
	marks that core ambiguous and `find` returns nil with a reason, so the control
	raises rather than picking one — a coin flip between two viewports is the
	silent failure this module exists to end. Re-publishing the SAME environment
	(a re-entrant constructor, a test rebuilding its world on a fresh core) is not
	ambiguity and is not refused.
]]

local surfaceEnv = {}

-- weak on BOTH halves: a core that nothing else references must stay collectable,
-- and so must the environment it published (an entry here is a lookup table, never
-- an owner — §6.3, every resource has exactly one owner and it is not this).
local published: { [any]: any } = setmetatable({}, { __mode = "kv" }) :: any
local ambiguous: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- publish(core, env): the environment of THIS core, for controls built on it.
-- Called by `environment.new`, so every environment — the client host's, a test
-- world's, a consumer's own — is discoverable the same way and no consumer opts
-- in. A second, DIFFERENT environment on one core makes the answer ambiguous
-- rather than replacing it (see the header).
function surfaceEnv.publish(core: any, env: any)
	if core == nil or env == nil then
		return
	end
	local existing = published[core]
	if existing ~= nil and existing ~= env then
		ambiguous[core] = true
		return
	end
	published[core] = env
end

-- find(core) -> env?, reason? — reason is "none" (nothing published) or
-- "ambiguous" (more than one environment on this core). Never raises: a caller
-- that can degrade (a headless unit mount) is a legal caller.
function surfaceEnv.find(core: any): (any?, string?)
	if core == nil then
		return nil, "none"
	end
	if ambiguous[core] == true then
		return nil, "ambiguous"
	end
	local env = published[core]
	if env == nil then
		return nil, "none"
	end
	return env, nil
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
