--!strict
--[[ A FORMULA THAT BELONGS TO AN OWNER, which is the only kind Facet builds.

	`Compose.formula` adopts whichever owner is ACTIVE when it runs, so a control
	deriving a value outside its own build body has to enter the owner first.
	Spelled out, that is two nested closures and five lines per formula:

		local widthPx = Compose.withOwner(owner, function()
			return Compose.formula(function(use)
				return use(metrics).width
			end)
		end)

	Facet had a hundred and fourteen of those, and one control had already
	written this helper privately rather than go on reading them. It is the same
	two calls in one, so the body sits at the indentation of the value it
	computes.

	`equals` passes straight through to `Compose.formula`, so a formula that
	suppresses equal values goes on suppressing them.

	It lives in core because it is Compose interop, and because core is what the
	areas that build formulas — controls, present, render — are allowed to
	require. `layout` may not require core (a solve runs on a frozen snapshot),
	so the one site in `layout/adaptive.luau` keeps the long spelling.
]]
local Compose = require("../vendor/compose/core")

local function ownedFormula<T>(owner: any, body: (use: Compose.Use) -> T, equals: Compose.Equals<T>?): Compose.Formula<T>
	return Compose.withOwner(owner, function()
		return Compose.formula(body, equals)
	end)
end

return ownedFormula
