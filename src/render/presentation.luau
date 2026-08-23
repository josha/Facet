--!strict
--[[ presentation — the PRESENTATION CHANNEL'S ARITHMETIC (ADR-0026).

	WHAT THIS IS FOR (read this first if you have never met the channel). Facet
	paints a node at its solved rect. Four things can then bend that paint without
	touching the layout: a fade, a scale, a rotation, and a translation. Two
	different people ask for them:

	  · the FRAMEWORK — a transition fading a toast out, the keyboard shifting a
	    surface up, a button's press dip, a drag ghost's pickup pop;
	  · the AUTHOR — `UI.Box{ opacity = 0.4 }`, `scale`, `rotation`, `offset`.

	Both want the same two engine properties (`transform` bundles scale/rotation/
	offset into one `UIScale`+`Rotation`+position write; `transparency` is the
	other), and the authority manifest (`render/authority.luau`) permits exactly
	ONE writer per engine property per class — because the engine will not police
	a second one: an explicit write silently defeats a StyleRules rule and fires
	no signal.

	So the authored value is not a writer. It is a second TERM, composed with the
	framework's value into ONE write, at one site. This module owns that
	arithmetic; `render/renderer.luau` owns the state and makes the write.

	PUBLIC INTERFACE (all pure — no upvalues, no engine, no adapter):

	  readAuthored(props, class, path) -> { opacity?, scale?, rotation?, offsetX?, offsetY? }?
	      the authored quad off a mounted node's resolved props, domain-checked.
	      Errors (loudly, naming the path) on a reactive value outside its domain.
	  effective(entry, rec, p)         -> opacity?, scale?, rotation?, offsetX?, offsetY?
	      that quad with this frame's `withAnimation` offset folded in (offset
	      excepted — see its own header note).
	  composeTransform(t, scale, rot, offsetX, offsetY)  -> transform table | nil
	  composeAlpha(channelT, opacity)  -> number | nil
	      the two composition rules, in engine units.
	  transformsEqual(a, b)            -> boolean
	      the write memo's comparison, over every field a transform carries.

	THE COMPOSITION RULE, which is the whole design (ADR-0026 Decision 2, offset
	added by amendment, gap 16 framework-gaps-phase2):

	  | property | composes by | identity |
	  |----------|-------------|----------|
	  | opacity  | MULTIPLY    | 1        |
	  | scale    | MULTIPLY    | 1        |
	  | rotation | ADD         | 0        |
	  | offset   | ADD         | 0        |

	One rule, not four: compose in the transform's own group. Two scalings
	multiply their factors, two rotations (or two offsets) add, two alpha-over
	composites multiply their alphas. Anything else makes nesting non-associative —
	a subtree scaled 2x inside a container scaled 2x has to read 4x.

	Opacity is the one term with a written-down rule elsewhere, and Facet took
	that rule: applying an opacity to a view that has already had its opacity
	transformed MULTIPLIES the effect of the underlying transformation. The
	citation lives in the comparison document (§16, read 2026-08-14).

	UNITS. Roblox's channel is TRANSPARENCY — 0 opaque, 1 invisible. The authored
	value is OPACITY — 1 opaque. `composeAlpha` is the multiply written in
	the units the engine takes, and the two never mix anywhere else.

	WHAT STILL DOES NOT COMPOSE HERE. The channel also carries `w`, `h` — a
	painted SIZE delta. That stays additive and stays framework-only: there is no
	authored counterpart, because a node's authored SIZE is the solver's output
	(`width`/`height`), not a paint value — the same ruling `x`/`y` used to carry
	until this amendment. The distinction the amendment draws: `offset` never lets
	an author say WHERE a node's box is (that is still `width`/`height`/`margin`/
	`Anchor`, decided once by the solver); it lets them say how far to NUDGE the
	already-solved paint, exactly the boundary `scale`/`rotation` already draw for
	size and angle. A `size`-shaped equivalent would reopen the "size-shaped fade"
	failure mode the original ruling named and is not proposed here.

	Depends on: `../blueprint_schema` (for the domain rulings, so the
	constructor and this read site can never disagree). Nothing else. ]]

local schema = require("../blueprint_schema")

local presentation = {}

export type Authored = { opacity: number?, scale: number?, rotation: number?, offsetX: number?, offsetY: number? }

--[[ THE AUTHORED TRIPLE, off a mounted node's RESOLVED props.

	The mount layer resolves a reactive prop into `node.props`, so this reads plain
	numbers — but a reactive value never passed through the constructor's domain
	check, so it is checked HERE, at the read, exactly as `styling.checkTint` is at
	its write site. Without that, a NaN opacity is an invisible node with no error
	anywhere and a negative scale is an absent one.

	Returns nil when the node authors none of the three, which is almost every node
	on almost every surface — the caller's off-path gate keys on that nil. ]]
function presentation.readAuthored(props: any, class: string, path: string): Authored?
	if props == nil then
		return nil
	end
	local o, s, r, off = props.opacity, props.scale, props.rotation, props.offset
	if o == nil and s == nil and r == nil and off == nil then
		return nil
	end
	if o ~= nil then
		local ok, why = schema.checkOpacity(o)
		if not ok then
			error(`Facet {class}.opacity at {path}: expects {why}`, 0)
		end
	end
	if s ~= nil then
		local ok, why = schema.checkScaleFactor(s)
		if not ok then
			error(`Facet {class}.scale at {path}: expects {why}`, 0)
		end
	end
	if r ~= nil then
		local ok, why = schema.checkDegrees(r)
		if not ok then
			error(`Facet {class}.rotation at {path}: expects {why}`, 0)
		end
	end
	local offsetX, offsetY = nil, nil
	if off ~= nil then
		local ok, why = schema.checkPresentationOffset(off)
		if not ok then
			error(`Facet {class}.offset at {path}: expects {why}`, 0)
		end
		offsetX, offsetY = (off :: any).x, (off :: any).y
	end
	return { opacity = o, scale = s, rotation = r, offsetX = offsetX, offsetY = offsetY }
end

function presentation.sameAuthored(a: Authored?, b: Authored?): boolean
	if a == nil or b == nil then
		return a == nil and b == nil
	end
	return a.opacity == b.opacity
		and a.scale == b.scale
		and a.rotation == b.rotation
		and a.offsetX == b.offsetX
		and a.offsetY == b.offsetY
end

--[[ THE AUTHORED TRIPLE PLUS THIS FRAME'S FLIGHT (ADR-0026 Decision 7).

	A `withAnimation` record carries `o`/`s`/`r` deltas beside its four rect
	numbers, and the painted authored value is `destination + delta x p` for the one
	progress `p` that already drives position and size. That shared `p` is what
	makes a card which slides, grows and fades land on a single frame.

	The interpolation is LINEAR IN THE AUTHORED VALUE — opacity 0 -> 1 is linear
	alpha, scale 1 -> 1.4 is linear scale — and never in the composed engine number,
	so a flight looks the same whether or not the framework happens to be fading the
	same node at the time.

	`rec` may be nil (no flight) and `entry` may be nil (a pure flight on a node
	that authors nothing, which is how an enter/exit fade of an authored-default
	node behaves): each missing term falls back to its identity.

	`offsetX`/`offsetY` (gap 16) ride straight through, UNCHANGED by `rec`: a
	`withAnimation` flight's `x`/`y` deltas are the FRAMEWORK's own rect-move
	term (already folded into the channel value `t` that `composeTransform`
	takes separately) and never a flight of the AUTHORED offset itself — no
	consumer has asked to animate a change of authored offset yet, so this
	keeps the two terms from being conflated rather than inventing an
	interpolation nothing exercises. ]]
function presentation.effective(entry: Authored?, rec: any, p: number): (number?, number?, number?, number?, number?)
	local offsetX = if entry ~= nil then entry.offsetX else nil
	local offsetY = if entry ~= nil then entry.offsetY else nil
	if rec == nil or not rec.paints then
		if entry == nil then
			return nil, nil, nil, nil, nil
		end
		return entry.opacity, entry.scale, entry.rotation, offsetX, offsetY
	end
	local o, s, r = nil, nil, nil
	if entry ~= nil then
		o, s, r = entry.opacity, entry.scale, entry.rotation
	end
	if rec.o ~= 0 then
		o = (o or 1) + rec.o * p
	end
	if rec.s ~= 0 then
		s = (s or 1) + rec.s * p
	end
	if rec.r ~= 0 then
		r = (r or 0) + rec.r * p
	end
	return o, s, r, offsetX, offsetY
end

--[[ THE TRANSFORM HALF. `t` is the framework's channel value (or nil); `scale`
	and `rotation` are the effective authored ones (or nil).

	Returns `t` BY IDENTITY when there is nothing authored — same table, no
	allocation, and the caller's memo compare then short-circuits on the first
	field. That identity return is the off-path guarantee ADR-0026 Decision 9
	promises, so do not "tidy" it into an unconditional table build.

	`offsetX`/`offsetY` (gap 16) are the authored TRANSLATION term, composed
	ADDITIVELY into `x`/`y` — the same rule `rotation` uses, and for the same
	reason: an offset has no "unscaled" identity to multiply against, only a
	zero to add against. This does not reopen ADR-0026's original refusal of an
	authored `x`/`y` (`"the authored position and size of a node is the
	solver's output, not a paint value"`): that ruling is about WHERE a node's
	box IS, decided once by the solver every rendered class already has; this
	is a decorative nudge FROM that solved position, the same boundary
	`scale`/`rotation` already draw for size and angle. ]]
function presentation.composeTransform(
	t: any,
	scale: number?,
	rotation: number?,
	offsetX: number?,
	offsetY: number?
): any
	if scale == nil and rotation == nil and offsetX == nil and offsetY == nil then
		return t
	end
	if t == nil then
		-- a pure paint transform: the framework channel is silent, so the
		-- authored offset (if any) IS the whole x/y
		return { x = offsetX or 0, y = offsetY or 0, scale = scale, rotation = rotation }
	end
	return {
		x = t.x + (offsetX or 0),
		y = t.y + (offsetY or 0),
		w = t.w,
		h = t.h,
		scale = (t.scale or 1) * (scale or 1),
		rotation = (t.rotation or 0) + (rotation or 0),
	}
end

--[[ THE TRANSPARENCY HALF, in engine units:

	    T_effective = 1 - (1 - T_channel) x opacity_authored

	which is `opacity_effective = opacity_channel x opacity_authored` — the same
	multiply, written the way `GroupTransparency` takes it. A framework fade to
	nothing (T_channel = 1) stays invisible whatever the author declared; an
	author's 50% stays 50% of whatever the framework is currently painting.

	nil in both means nil out: nothing is fading this node, so nothing is written. ]]
function presentation.composeAlpha(channelT: number?, opacity: number?): number?
	if channelT == nil and opacity == nil then
		return nil
	end
	return 1 - (1 - (channelT or 0)) * (opacity or 1)
end

-- the write memo's comparison. Every field a transform carries is compared,
-- because a memo that missed one would swallow exactly the contributor that
-- moved.
function presentation.transformsEqual(a: any, b: any): boolean
	if a == nil or b == nil then
		return a == nil and b == nil
	end
	return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h and a.scale == b.scale and a.rotation == b.rotation
end

return presentation
