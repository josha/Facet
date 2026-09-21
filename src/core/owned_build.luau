--!strict
--[[ BUILD A COMPOSITE UNDER ITS OWN OWNER, which is how every composite control
	in Facet enters the world. Twenty-one controls wrote the same nine lines:

		local parent = Compose.currentOwner()
		local owner = if parent then parent.createChild() else <one of three spellings>
		local ok, result = pcall(Compose.withOwner, owner, function()
			return build(Facet, core, spec, owner)
		end)
		if not ok then
			owner.dispose()
			error(result, 0)
		end
		return result

	The shape matters and is not incidental. A control built INSIDE a component
	becomes a child of that component's owner, so the component's teardown takes
	the control with it. A control built with no active owner needs an owner of
	its own, and the caller disposes it. Either way the build runs UNDER that
	owner, and a build that throws disposes what it had already created rather
	than stranding it — which is why the pcall is here and not at the call site.

	WITH NO ACTIVE OWNER the control becomes a child of the APPLICATION's root
	owner, and that is the whole reason this helper takes `core`. `core.owner` is
	created on `core.reactor` and guarded by the application's error boundary,
	and a child inherits both: the reactor the layout settle pass is installed
	on, so a write settles the surface inside the flush that opened it; the same
	batching as every other write on that surface; and the containment that keeps
	a throwing binding from taking the surface down.

	`Compose.createOwner()` with no reactor argument would create a PRIVATE one
	(`vendor/compose/core/ownership/owner.luau`), which has none of those three.
	Fourteen controls used to do exactly that, six took the core's reactor
	without the guard, and one was already right — so a parentless `UI.Button`
	and a parentless `UI.Callout` did not agree. `tests/parentless_build_owner.spec.luau`
	is what stops them disagreeing again.
]]
local Compose = require("../vendor/compose/core")

local function ownedBuild<T>(core: any, body: (owner: any) -> T): T
	local parent = Compose.currentOwner()
	local owner = if parent then parent.createChild() else core.owner.createChild()
	local ok, result = pcall(Compose.withOwner, owner, function()
		return body(owner)
	end)
	if not ok then
		owner.dispose()
		error(result, 0)
	end
	return result :: T
end

return ownedBuild
