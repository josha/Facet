--!strict
--[[ NUMBER PREDICATES, ONCE (one home for a shared predicate).

	`isFinite` existed SEVENTEEN times, byte-identical, across `async/`,
	`controls/`, `input/`, `motion/`, `present/`, `render/`, `themes/` and
	`tokens/`. Sixteen of the seventeen carried no reasoning at all; the
	seventeenth, `src/motion/spring.luau`, carried the only sentence that explains
	why any of them exist — a non-finite value "would pin a driver awake forever
	writing NaN into a property — which blanks the surface permanently". That
	sentence is the module header now, so the next author reads it once instead of
	inheriting a predicate with no story.

	THIS MODULE REQUIRES NOTHING, deliberately, exactly like `src/spec_guard.luau`
	(39 consumers across six directories). A leaf with zero requires is legal from
	every layer — `render/` may require it without depending on `layout/`, `motion/`
	keeps its "depends only on the contract types" promise — which is why the prior
	pass's objection to consolidating these ("fifteen new inter-module edges") was
	backwards: the edge is to a leaf, and a leaf is the one thing anything may
	depend on.

	HOT PATHS BIND IT LOCALLY. The motion drivers call `isFinite` per frame and the
	solver rounds per node; `local isFinite = num.isFinite` at module scope is one
	upvalue lookup, which is what those call sites had before and what they keep.
]]

local num = {}

--[[ "Is this a real number?" — the guard every value that reaches a driver, a
	spring, a solver dimension or a theme metric has to pass. NaN and ±inf both
	fail: NaN because it compares unequal to itself and so can never settle, ±inf
	because arithmetic on it produces NaN one step later. A non-number fails
	first, so callers may hand this an unvalidated spec field. ]]
function num.isFinite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

--[[ Round to a whole pixel, half away from zero for positives — the rule the
	solver, the composition resolver, the grid and the surface-overlap loop each
	wrote inline sixty-one times and only `composition.roundRect` ever named.

	It is `floor(v + 0.5)` and not `math.round`: they differ at negative halves
	(`math.round(-0.5)` is -1, this is 0) and the layout code was written against
	this one. Changing which way a half rounds moves pixels on real screens, so
	the equivalence is deliberate rather than incidental. ]]
function num.roundPx(v: number): number
	return math.floor(v + 0.5)
end

return num
