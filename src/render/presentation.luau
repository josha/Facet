--!strict
--[[ presentation — the PRESENTATION CHANNEL'S ARITHMETIC (ADR-0026).

	WHAT THIS IS FOR (read this first if you have never met the channel). Facet
	paints a node at its solved rect. Three things can then bend that paint without
	touching the layout: a fade, a scale and a rotation. Two different people ask
	for them:

	  · the FRAMEWORK — a transition fading a toast out, the keyboard shifting a
	    surface up, a button's press dip, a drag ghost's pickup pop;
	  · the AUTHOR — `UI.Box{ opacity = 0.4 }`, `scale`, `rotation`.

	Both want the same three engine properties, and the authority manifest
	(`render/authority.luau`) permits exactly ONE writer per engine property per
	class — because the engine will not police a second one: an explicit write
	silently defeats a StyleRules rule and fires no signal.

	So the authored value is not a writer. It is a second TERM, composed with the
	framework's value into ONE write, at one site. This module owns that
	arithmetic; `render/renderer.luau` owns the state and makes the write.

	PUBLIC INTERFACE (all pure — no upvalues, no engine, no adapter):

	  readAuthored(props, class, path) -> { opacity?, scale?, rotation? }?
	      the authored triple off a mounted node's resolved props, domain-checked.
	      Errors (loudly, naming the path) on a reactive value outside its domain.
	  effective(entry, rec, p)         -> opacity?, scale?, rotation?
	      that triple with this frame's `withAnimation` offset folded in.
	  composeTransform(t, scale, rot)  -> transform table | nil
	  composeAlpha(channelT, opacity)  -> number | nil
	      the two composition rules, in engine units.
	  transformsEqual(a, b)            -> boolean
	      the write memo's comparison, over every field a transform carries.

	THE COMPOSITION RULE, which is the whole design (ADR-0026 Decision 2):

	  | property | composes by | identity |
	  |----------|-------------|----------|
	  | opacity  | MULTIPLY    | 1        |
	  | scale    | MULTIPLY    | 1        |
	  | rotation | ADD         | 0        |

	One rule, not three: compose in the transform's own group. Two scalings
	multiply their factors, two rotations add their angles, two alpha-over
	composites multiply their alphas. Anything else makes nesting non-associative —
	a subtree scaled 2x inside a container scaled 2x has to read 4x.

	Opacity is also the one Apple writes down, and Facet took the rule from there:
	applying `opacity(_:)` to a view "that has already had its opacity transformed…
	multiplies the effect of the underlying opacity transformation"
	(developer.apple.com/documentation/swiftui/view/opacity(_:), read 2026-08-14;
	cited as [SW-141] in docs/reference/swiftui-parity.md §16).

	UNITS. Roblox's channel is TRANSPARENCY — 0 opaque, 1 invisible. SwiftUI's
	authored value is OPACITY — 1 opaque. `composeAlpha` is the multiply written in
	the units the engine takes, and the two never mix anywhere else.

	WHAT DOES NOT COMPOSE HERE. The channel also carries `x`, `y`, `w`, `h` — a
	positional offset and a painted size delta. Those stay additive and stay
	framework-only: there is no authored counterpart, because a node's authored
	position and size is the solver's output, not a paint value.

	Depends on: `../blueprint_schema` (for the three domain rulings, so the
	constructor and this read site can never disagree). Nothing else. ]]

local schema = require("../blueprint_schema")

local presentation = {}

export type Authored = { opacity: number?, scale: number?, rotation: number? }

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
	local o, s, r = props.opacity, props.scale, props.rotation
	if o == nil and s == nil and r == nil then
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
	return { opacity = o, scale = s, rotation = r }
end

function presentation.sameAuthored(a: Authored?, b: Authored?): boolean
	if a == nil or b == nil then
		return a == nil and b == nil
	end
	return a.opacity == b.opacity and a.scale == b.scale and a.rotation == b.rotation
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
	node behaves): each missing term falls back to its identity. ]]
function presentation.effective(entry: Authored?, rec: any, p: number): (number?, number?, number?)
	if rec == nil or not rec.paints then
		if entry == nil then
			return nil, nil, nil
		end
		return entry.opacity, entry.scale, entry.rotation
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
	return o, s, r
end

--[[ THE TRANSFORM HALF. `t` is the framework's channel value (or nil); `scale`
	and `rotation` are the effective authored ones (or nil).

	Returns `t` BY IDENTITY when there is nothing authored — same table, no
	allocation, and the caller's memo compare then short-circuits on the first
	field. That identity return is the off-path guarantee ADR-0026 Decision 9
	promises, so do not "tidy" it into an unconditional table build. ]]
function presentation.composeTransform(t: any, scale: number?, rotation: number?): any
	if scale == nil and rotation == nil then
		return t
	end
	if t == nil then
		-- a pure paint transform: no offset to declare, which is why x/y are zero
		-- rather than absent (the adapter reads both fields unconditionally)
		return { x = 0, y = 0, scale = scale, rotation = rotation }
	end
	return {
		x = t.x,
		y = t.y,
		w = t.w,
		h = t.h,
		scale = (t.scale or 1) * (scale or 1),
		rotation = (t.rotation or 0) + (rotation or 0),
	}
end

--[[ THE TRANSPARENCY HALF, in engine units:

	    T_effective = 1 - (1 - T_channel) x opacity_authored

	which is `opacity_effective = opacity_channel x opacity_authored` — Apple's
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
