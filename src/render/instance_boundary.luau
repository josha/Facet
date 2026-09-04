--!strict
--[[ WHICH NODES EARN A REAL ENGINE OBJECT, AND OF WHAT KIND.

	This is the one predicate the nested-instance-tree migration changes.
	Its thesis is that switching Facet from a flat instance tree to a
	nested one "is not a rewrite of the renderer... it is a change to one
	predicate: which paths get registered". A predicate that is the whole content
	of a migration needs somewhere to live, and it was two inline branches in
	`ensureTree` — the busiest function in a 4,000-line file.

	IT LEFT THE RENDERER FOR A SECOND REASON, AND THAT ONE IS MEASURED.
	`renderer.luau` stood at 198,731 characters against Studio's 200,000-character
	`Script.Source` WRITE cap — 1,269 characters of headroom, which is not enough
	to explain a decision in. Over that cap a module silently stops live-syncing
	into an open Studio session, so every live check against it tests the place
	file rather than the edits on disk. The migration's own record says the cap
	"no longer applies" and that "every step of this migration can be canaried
	live" — which was true when it was written at
	185,633 characters and had quietly stopped being true. Moving the predicate out
	buys the renderer back its headroom and puts the rule where a reader looking
	for it would go.

	THE RULE, stated once:

	    Register a container as a real instance parent when the engine can carry
	    something down its subtree that the framework would otherwise compute per
	    descendant — it moves as a unit, or it composites as a unit. Otherwise
	    leave it unregistered and elidable.

	That second sentence is the half that keeps elision alive, and it is worth as
	much as the first. A `VStack` that exists only to say "these three things are
	in a column" never moves independently and composites nothing: the solver
	already places its children absolutely, so materialising it buys one instance
	and saves nothing. Measured on a 20-row list, elision removes 61 of 142
	GuiObjects — 43% — and mirroring the whole blueprint into Instances costs
	+75.3%. `tools/lune/check_elision_census` holds both numbers, and the rotated
	fixture there charges Decision 4 for the instances it does spend.

	TWO KINDS, AND THE DIFFERENCE IS A RENDER BUFFER.

	  `group` — a `CanvasGroup`. The node's subtree renders into an offscreen
	    buffer its own size, which is what makes `GroupTransparency` fade a group
	    rather than each node's own paint. Declared by `canvasGroup = true`, and
	    implied by an authored `opacity`, because a fade IS a GroupTransparency
	    fact and the node carrying one has to BE the group.
	    The buffer is a real cost, so nothing gets one it did not ask for.

	  `host` — a plain `Frame` that happens to be a real parent. No buffer, no
	    clipping, no ordering cost beyond the one every real parent has under
	    `ZIndexBehavior.Sibling`. One extra instance and nothing else.

	The three costs people attribute to nesting belong to `CanvasGroup`,
	`ClipsDescendants`, and `Sibling` respectively — not to having a parent. Which
	is why `scale`/`rotation` take the cheap kind: the engine composes both terms
	down any real subtree, and only `opacity` actually needs the buffer.

	WHY IT IS A FREE FUNCTION AND NOT A METHOD ON ANYTHING. It reads a mounted
	node and returns a plain table or nil. No state, no adapter, no engine — so
	the headless suite drives it directly, and the fake target and the live
	adapter answer to the same rule rather than to two copies of it.
]]

local instance_boundary = {}

export type CreateOpts = { canvasGroup: boolean?, instanceHost: boolean?, hostSpace: boolean? }

--[[ The creation-time facts the adapter can only honour while it is CHOOSING the
	engine object — which is why they ride `create`'s fifth argument rather than
	arriving as a later prop write. By then the instance exists and its class is
	settled. A target that does not nest ignores the argument entirely.
]]
function instance_boundary.createOptsFor(node: any, opts: any?): CreateOpts?
	local props = node.props
	if props == nil then
		return nil
	end
	if props.canvasGroup == true or props.opacity ~= nil then
		return { canvasGroup = true }
	end
	--[[ AN AUTHORED `scale`/`rotation` ON A CONTAINER IS A REAL-PARENT DECLARATION
		TOO, and until this landed it was the one presentation
		term the flat tree got visibly WRONG rather than merely incomplete.

		Measured live through this framework: two identical `UI.ZStack`s at
		`rotation = 30, scale = 1.5` with identical 80x40 children. Flat, the
		children stay 80x40 with `Rotation = 0` — a rotated plate with its contents
		sitting bolt upright beside it. Given a real parent they are 120x60 and ride
		the parent's pivot, and no framework code does that; the engine composes
		both terms for a subtree it can see.

		So this needs no new mechanism, which is the migration's whole thesis: the
		adapter already writes `Rotation` and a `UIScale` on the node's own
		instance. The only thing missing was that the subtree was not inside it.

		`#children > 0` because the rule is "the engine can carry something DOWN A
		SUBTREE". A rotated leaf has no subtree: it already rotates correctly, and
		registering it would buy an instance-pool refusal and deliver nothing.
	]]
	if (props.scale ~= nil or props.rotation ~= nil) and node.children ~= nil and #node.children > 0 then
		return { instanceHost = true }
	end
	--[[ A REACTIVE PLACEMENT ON A CONTAINER IS A COORDINATE-SPACE DECLARATION.
		A node whose `offsetX`/`offsetY`/`anchor` is a signal or memo will MOVE, per
		frame, as a unit — and under a flat tree every move rewrote every
		descendant's `Position` (1,488 engine writes for 250 nameplates, measured in
		`FacetBench/docs/profiling/2026-09-02-nameplates-attribution.md`). Given a
		real parent AND rects stored relative to it, a move is one rect and one
		write; the public readers compose the origin back on read.

		`dynamicProps`, NOT `props`: by the time this runs, `mount` has resolved the
		signal into `props` and the reactive FACT survives only there.

		AN ADAPTER-REGISTERED HOST KEEPS THE ABSOLUTE SCHEME.
		`offsetX`/`offsetY`/`anchor` are `shared = true` props, so a `ScrollView` or
		a `clipChildren` container reaches this branch — and a ScrollView also READS
		`offsetX/Y` for its own axis, while `scroll_into_view` subtracts a raw host
		rect from a raw target rect. Making either a coordinate space would change
		the meaning of every raw-rect reader inside every list Facet ships. Refused
		outright, above the trigger.

		THERE IS NO COMPOSITION SCAN: a create-time scan is a one-shot snapshot —
		mount nodes start with `children = {}` and a `When`/`ForEach` can mount a
		`Composition` under an already-registered host later, at which point the
		gate silently stops holding. The solver instead carries the absolute origin
		(`ctx.spaceOX`/`ctx.spaceOY`) and hands `composition_resolve` a window-space
		origin, which is exact at any time.

		THE SAME KNOWN LIMIT THE `scale`/`rotation` TRIGGER HAS: `#children > 0` is
		read ONCE — see the memo below — and mount nodes start with `children = {}`
		with regions mounting children later, so a container that is EMPTY when the
		question is first asked never becomes a host. It stays correct (it is simply
		not a host); it is stated so nobody reads a missing host as a bug.

		`props` is ALREADY bound above, with the nil early-return, so this branch
		neither re-declares it nor re-guards it. ]]
	if node.class == "ScrollView" or props.clipChildren == true then
		return nil
	end
	if opts ~= nil and opts.translateHosts == false then
		return nil
	end
	--[[ ...AND THE ANSWER IS MEMOISED ON THE MOUNTED NODE, because TWO callers ask
		it and neither is guaranteed to ask first (found by measurement, not by
		reasoning: a card rail's rows read absolute rects under a registered
		coordinate-space host). `renderer.ensureTree` asks when it chooses the engine
		object; `render/layout_node` asks when it builds the solver's node, and a
		re-solve driven from inside a settle — a virtual list widening its window off
		the geometry it was just fed — builds nodes for rows whose handles do not
		exist yet. If the two ever answered differently the solver would store a
		subtree relative to a parent the adapter never made, or absolutely under one
		it did. Whoever asks first fixes it, which is also exactly the "fixed for the
		node's lifetime" property this flag is documented to have. ]]
	local decided = node.hostSpace
	if decided == nil then
		local dyn = node.dynamicProps
		decided = dyn ~= nil
			and (dyn.offsetX ~= nil or dyn.offsetY ~= nil or dyn.anchor ~= nil)
			and node.children ~= nil
			and #node.children > 0
		node.hostSpace = decided
	end
	if decided then
		return { instanceHost = true, hostSpace = true }
	end
	return nil
end

--[[ THE RECYCLE-BUCKET DISCRIMINATOR, and it names the ENGINE OBJECT rather than
	answering "were there any options".

	It was `tostring(createOpts ~= nil)` while `canvasGroup` was the only option
	there could be. A second option that produces a DIFFERENT class would have
	shared a bucket with the first, and a pooled `Frame` could be adopted where a
	`CanvasGroup` was asked for. Both kinds are refused by `parkEligible` today —
	a registered host cannot be recycled — so neither reaches a bucket at all, and
	this is the belt to that brace: a key that is only correct because something
	else is correct is the one that fails the day the something else changes.
]]
function instance_boundary.kindOf(createOpts: CreateOpts?): string
	if createOpts == nil then
		return "plain"
	elseif createOpts.canvasGroup == true then
		return "group"
	end
	return "host"
end

return instance_boundary
