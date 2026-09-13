--!strict
-- The structural-transition COORDINATOR (ui-designer spec
-- §2.1). It is the mount layer's `transitions` collaborator,
-- implemented over exactly two things: the motion clock (P1) and the renderer's
-- per-node presentation channel (P2).
--
-- WHY IT LIVES UNDER src/render/ AND NOT src/present/. Everything it does is a
-- presentation write — `controller.setPresentationTransform` /
-- `setPresentationTransparency`, the framework's whole motion write surface — and
-- it needs the renderer's node/handle knowledge to make them. It owns no surface
-- lifetime, no focus scope and no input policy, which is what `src/present/` is
-- for; the presenter merely CONSUMES it (and `present` already depends on
-- `render`, so the direction is the established one).
--
-- ONE SPRING PER TRANSITION: 1 = at rest
-- (fully present), 0 = fully absent. Enter aims at 1, exit aims at 0, and a
-- re-entry mid-exit simply re-aims the SAME spring — which is why reversal keeps
-- both the value and the velocity and needs no case of its own. Every visual form
-- (offset, scale, transparency) is derived from that one number, so a form can
-- never disagree with itself half way through.
-- Redirected pure slides may temporarily use progress outside [0, 1] to keep
-- their painted position and velocity when their travel direction changes.
--
-- THE ABSENT PLACE IS THE SAME FOR A MIRROR PAIR. A form names the direction of
-- TRAVEL: an enter travels toward rest, an exit travels away from it. `slide-up`
-- entering starts BELOW; `slide-down` exiting ends BELOW — the same displacement,
-- so the default (mirrored) exit reverses through one continuous motion.
--
-- THE HARD CAP (disposition F8): no exit may defer disposal beyond 500 ms of CLOCK
-- time. Flat, non-overridable, and enforced here because this is where time is —
-- `mount.luau` is engine-free and must not grow a clock. A clock nobody steps
-- stops the cap too; that is a stopped surface, not a leak.
--
-- REDUCED MOTION NEEDS NO CODE HERE. A MotionValue under `reduced` places itself
-- at the terminal value and fires the same settle event on the same frame, so an
-- enter lands instantly and still emits `arrive`, and an exit completes — and
-- disposes — on the frame it began. Information parity comes from the authority,
-- not from a branch in every consumer.

local schema = require("../blueprint_schema")
local themeSnapshot = require("../themes/snapshot")

local transitions = {}

-- ui-designer spec §2.1 / disposition F8: flat and non-overridable
local EXIT_CAP_SECONDS = 0.5
--[[ THE EXIT ENDS WHEN IT IS VISUALLY ABSENT, NOT WHEN THE SOLVER IS BORED
	(task 7 item 1). A spring settles on `|x - target| <= eps AND |v| <= eps`,
	and for a critically damped spring it is the VELOCITY half that decides by a
	wide margin: `dismiss` (ζ1.0 / 0.2 s) is numerically zero — 0.27% of its
	travel — at frame 18 and still carries 0.061 progress/s, so at the default
	1e-3 it "settles" at frame 30. Measured, that put disposal at 0.500 s: the
	flat cap to the frame, with `container` one frame behind it. The cap is a
	SAFETY NET for a motion that cannot land (a stalled clock, a class whose
	response genuinely exceeds it); when it is also the ordinary end of every
	exit, the exit classes are indistinguishable at the one moment a player can
	see — when the instances go — and a faster class buys only a faster fade.

	So the EXIT phase builds its spring at a coarser epsilon while the ENTER
	keeps the default: an enter's settle fires `arrive`, a semantic event whose
	frame is a fact rather than a tolerance, and an exit's settle only decides
	when something already invisible stops existing.

	WHY 0.02 IS INVISIBLE, stated over the quantity it actually bounds and over
	the cases that can actually REACH it. This epsilon is in PROGRESS, and every
	form is derived from that one number, so the most it can truncate is 2 % of a
	transition's travel: 2 % alpha, 0.48 px of the themed 24 px slide, 0.08 % of
	the 0.96→1 materialize.

	Reaching that 2 % needs a spring whose VALUE, not its velocity, is the
	binding half — AND one that settles before the cap ends it anyway, which is
	the half the first draft of this comment got wrong (review N4). It named
	ζ2.0 / 2 s, the far corner of the authored range; that class settles at frame
	285 and is ended by the 30-frame cap every time, so its settle tolerance is
	never consulted. The reachable worst case is a FAST, mildly overdamped class:
	measured, ζ1.2 / 0.08 s settles at frame 7 with x = 0.0199. Every shipped
	class is velocity-bound instead and lands far finer: `dismiss` at x = 0.0007,
	`object` 0.0011, `container` 0.0014, `decay` 0.0019 — two tenths of one
	percent of the travel or less.

	THE BOUND IS THEREFORE: an exit ends when at most 2 % of its travel remains,
	OR at the 500 ms cap, whichever comes first. It is deliberately NOT "half a
	pixel of travel left" (review D3). A round of this fix tried exactly that —
	clamping the epsilon to `0.5 / distance` for a travelling form — and it made
	a full-width slide UNABLE to settle at all: `dismiss` at `distance = 1920`
	went from disposing on frame 22 to frame 31, the cap, which is the very
	defect the epsilon exists to remove, re-entered through the caller most
	likely to declare a long slide. `NavigationStack` passes `distance =
	stackWidth`, so every push and pop would have run to the cap.

	And the residue the clamp was buying is not visible anyway:
	`screen_presentation.luau` rounds a presentation offset to whole pixels
	before it reaches the engine, and `UDim.Offset` is an integer, so anything
	under half a pixel is written as the same number either way. What the cap
	truncates is a far larger number than what the epsilon does — measured at
	1920 px, `container` is cap-ended with 5.1 px left and `decay` with 32.7 px
	— and NavigationStack pins `container`, so its full-width push is cap-ended
	TODAY, before and after this round. That is a pre-existing question about the
	cap, not about this tolerance.

	Measured: frames to dispose (60 fps, `enter = "fade"`) `dismiss` 22,
	`object` 28, `container` 31, `decay` 31. The last two are the two classes
	whose settle (33 and 44 frames) genuinely outruns the 30-frame cap, which is
	the net doing its job — and the reason `dismiss`, not `container`, is
	`DEFAULT_EXIT_CLASS`. ]]
local EXIT_EPS = 0.02
-- the slide travel, as a THEME metric (`space.l` = 24 px in Facet Neutral): a
-- roomier theme slides a little further, and no call site carries a magic number
local DEFAULT_SLIDE_DISTANCE = 24
--[[ materialize (ratified: sponsor_motion §2/§8, range [0.94–0.98]).

	AND THE ENGINE FACT THAT BOUNDS IT, measured live 2026-09-13 (Studio, Play,
	BuilderSans): Roblox rasterizes text at `floor(TextSize x effectiveScale)`.
	A `UIScale` of 0.9999999 therefore paints 20px text at 19 — the SAME pixel it
	paints at 0.96 — so a scale-in over live text renders every string one whole
	pixel small for the entire flight and snaps 5% larger the instant the scale
	reaches exactly 1 (TextBounds 127.5x19 throughout [0.96, 1), 133.5x20 at 1.0;
	a CanvasGroup does not buffer it away — a UIScale above the group measures the
	same). On a card that is mostly type that snap is a visible re-flow, and it
	lands AFTER the motion has stopped because the channel holds the UIScale until
	the spring's own settle disposes it.

	The default keeps the ratified undershoot, because it is right for the plates
	and tiles it was ratified on. A surface whose content is mostly TEXT declares
	`transition.scale` instead and settles DOWN from just above 1: every scale in
	[1, 1 + 1/TextSize) floors to the same pixel, so the text lands at its final
	size on the first painted frame and never moves (`Controls.Alert`'s
	`DEFAULT_TRANSITION` is the first caller; `blueprint_schema.luau`'s `scale`
	note carries the same rule for authors). ]]
local MATERIALIZE_SCALE = 0.96
local DEFAULT_CLASS = "container"
local DEFAULT_EXIT_CLASS = "dismiss"
--[[ A LIST'S ENTRANCE IS A RHYTHM, NOT A QUEUE (spec 2F). `spec.stagger` is the
	beat between one row's enter and the next one's, and past this many rows the
	WAIT STOPS GROWING: every further row starts with row nine. The cap is on the
	number a player experiences — at a 50 ms beat, the last row of a 600-row list
	enters 400 ms in rather than half a minute later — and an uncapped beat is
	not a slower rhythm, it is a list that never finishes arriving.

	IT IS NOT A CAP ON TIMERS, and saying so would be a lie: each held row still
	books its own hold (the rows past the cap simply all book the SAME duration).
	That is the same order as the springs and the nodes a 600-row enter already
	costs, and it keeps the hold a property of the ENTRY — which is what lets
	`stopCap` tear one down without asking whether some other row still needs it. ]]
local STAGGER_CAP = 8
local TRANSITION_SPEC = (schema.forClass("ForEach") :: any).props.transition

-- travel vector per form, in screen space (+y is down)
local TRAVEL: { [string]: { x: number, y: number } } = {
	["slide-up"] = { x = 0, y = -1 },
	["slide-down"] = { x = 0, y = 1 },
	["slide-left"] = { x = -1, y = 0 },
	["slide-right"] = { x = 1, y = 0 },
}

export type Spec = {
	enter: string,
	exit: string,
	class: string,
	exitClass: string,
	fade: boolean,
	-- task-fix3 symptoms 2/3: opt-in override for `slideDistance` below, nil
	-- meaning "use the themed default" (every caller before this fix, unchanged)
	distance: number?,
	-- the scaling form's own absent scale, nil meaning `MATERIALIZE_SCALE` (see
	-- its header for the engine fact that makes this an override rather than a
	-- changed default)
	scale: number?,
	-- the corner a scaling form grows from (schema.TRANSITION_PIVOTS); nil = centre
	pivot: string?,
	-- the plate acknowledgement (schema.TRANSITION_PLATES); nil = unacknowledged,
	-- which is every caller that has not said otherwise
	plate: string?,
	-- seconds between one entering row and the next (STAGGER_CAP above); 0 = the
	-- whole batch enters together, which is every caller before this field
	stagger: number,
}

export type Opts = {
	core: any,
	clock: any,
	controller: any?,
	-- the live metric authority; defaults to Facet Neutral
	metrics: (() -> any)?,
	-- the semantic feedback sink. An ENTER that reaches rest
	-- is a motion arrival, so it emits `arrive` on that frame.
	feedback: ((event: any) -> ())?,
	surface: any?,
}

-- normalize an authored declaration. The schema already refused an unknown form,
-- so this only fills the defaults: the exit mirrors the enter unless it was
-- declared, and the motion class is `container` (large surfaces materializing).
function transitions.resolve(declared: any): Spec
	-- Read once at the structural event boundary. The mounted node retains the
	-- source; an active entry retains this validated value snapshot.
	if type(declared) == "table" and (declared.kind == "signal" or declared.kind == "memo") then
		declared = declared:get()
	end
	local valid, detail = schema.checkValue(TRANSITION_SPEC, declared)
	if not valid then
		error("Facet transition: " .. tostring(detail), 0)
	end
	local enter = declared.enter
	local exit = declared.exit or (schema.TRANSITION_MIRROR :: any)[enter]
	return {
		enter = enter,
		exit = exit,
		class = declared.class or DEFAULT_CLASS,
		exitClass = declared.exitClass or DEFAULT_EXIT_CLASS,
		fade = declared.fade == true,
		pivot = declared.pivot,
		plate = declared.plate,
		distance = if type(declared.distance) == "number" then declared.distance else nil,
		scale = if type(declared.scale) == "number" then declared.scale else nil,
		stagger = if type(declared.stagger) == "number" then declared.stagger else 0,
	}
end

local function fades(spec: Spec, form: string): boolean
	return spec.fade or (schema.TRANSITION_FADES :: any)[form] == true
end

--[[ BACKDROP-BEFORE-CONTENT (framework-gaps-phase2-followups task POP, director
	item 10 + mandate b). `GroupTransparency` is ONE scalar Roblox composites over
	a CanvasGroup's WHOLE rendered subtree, so an opaque plate (an authored
	`surface` or an opaque `Box` `tint` — fix round 1 widened this from
	`surface` alone, see `paintsBackdrop` below) declared INSIDE the node a fade
	targets reaches full opacity at the exact instant its content does — "the
	backdrop is legible no later than the content" is then impossible BY
	CONSTRUCTION, not merely unlikely. Measured
	headlessly (task POP): four Glade modals shared one helper that put
	`surface = "raised"` on a descendant of the one canvasGroup `presentModal`
	targets; `GroupTransparency` sampled across a 30-tick materialize read
	1, 0.73, 0.23, 0.003 and the plate rode every one of those numbers alongside
	its own text.

	Pure, module-level and engine-free on purpose (mirrors `src/render/
	surface_overlap.luau`'s own shape): a mounted node's `.props`/`.children` are
	all either function needs, so both the live coordinator below and a headless
	gate can call them directly over a `tests/lib/fake_target` tree with nothing
	else wired up. ]]
local NON_PAINTING_SURFACE: { [string]: boolean } = { plain = true }
--[[ task POP fix round 1 (review finding 2): the FIRST shipped detector only
	read `props.surface` — provably blind to a plate painted with `tint`
	instead (RascalRally's own house style: `StartCountdown.CountdownScrim`,
	`Ticker.EntryPlate`, `TableScreen.TablePlate`, and more, swept this round).
	`tint` is not by itself proof of an opaque BACKDROP, though: `blueprint_
	schema.luau` gives `tint` to `Text`, `Image`, `Path` and `Stage` too, where
	it colours a GLYPH, a picture, a stroke or a scene clear-colour — never a
	background rect a sibling could be hidden behind. `Box` is the one class
	whose `tint` is a straight `BackgroundColor3` fill (the exact channel
	`surface` also writes), so a tint-based finding is scoped to it — a
	general fact about the ONE class that paints a full-bleed rect this way,
	not a hand-list of the sites that happen to hit it today. ]]
local TINT_PAINTS_BACKDROP: { [string]: boolean } = { Box = true }
local function paintsBackdrop(child: any): (boolean, string?)
	local props = child.props
	if props == nil then
		return false
	end
	local surface = props.surface
	if type(surface) == "string" and not NON_PAINTING_SURFACE[surface] then
		return true, "surface"
	end
	if TINT_PAINTS_BACKDROP[child.class] then
		local tint = props.tint
		if type(tint) == "table" then
			-- `styling.checkTint`'s own vocabulary: "0 is opaque (the default),
			-- 1 is invisible". A REACTIVE tint (a Bound value, still a plain
			-- table at this layer — see `core:memo`'s `makeReadable`) carries no
			-- readable `.transparency` at all; treating "unreadable" the same as
			-- "opaque" is the safe direction (a `surface = "plain"`-style miss
			-- would hide a real finding, a spurious one just asks for a look).
			local alpha = tint.transparency
			if not (type(alpha) == "number" and alpha >= 1) then
				return true, "tint"
			end
		end
	end
	return false
end

-- every `canvasGroup = true` descendant of `node`, stopping descent at each one
-- found (a nested INDEPENDENT fade group is its own compositing boundary, not a
-- candidate one level further in).
local function collectCanvasGroups(node: any, out: { any })
	for _, child in node.children or {} do
		if child.props ~= nil and child.props.canvasGroup == true then
			table.insert(out, child)
		else
			collectCanvasGroups(child, out)
		end
	end
end

--[[ THE ONE FADE GROUP UNDER A NODE — nil when there is not exactly one.

	The single definition of "which node does a transition over this subtree
	really act on". `resolveAlphaTarget` below routes `GroupTransparency` here,
	and the presenter routes a SURFACE's whole transition node here (task A2)
	rather than re-deriving it: two derivations of the same question is how the
	scale half ended up writing to a node the alpha half had already left. ]]
function transitions.soleFadeGroup(node: any): any?
	if node == nil then
		return nil
	end
	local candidates: { any } = {}
	collectCanvasGroups(node, candidates)
	return if #candidates == 1 then candidates[1] else nil
end

--[[ THE FIX SPLITS THE WRITE, NOT THE TRANSITION. Position/scale still target
	the node the caller declared — a plain `UIScale`/offset moves a background
	plate and its content as one rigid unit, canvasGroup or not, so a
	`materialize` card still scales and slides as a whole. Alpha alone needs the
	group: when the declared node is not itself one, this finds the ONE
	canvasGroup in its subtree and routes `GroupTransparency` there instead — the
	backdrop is then never a descendant of what fades, so it paints at its own,
	immediate opacity from the first frame. Zero or more than one candidate falls
	back to the declared node itself — exactly today's construction, and
	`assertFadeCapable`'s refusal still fires for it unchanged.

	THE SELF-CASE IS TRUSTED, NOT REPAIRED (review finding 3, fix round 1
	honesty note). When the DECLARED node already IS the canvasGroup, this
	returns it unchanged — on the reasoning that a node an author explicitly
	marked `canvasGroup = true` is the one they meant to fade. If that SAME
	node also composes an opaque `surface`/`tint` as one of its own direct
	children (RascalRally's `MessageLayer.ribbon`'s pre-fix `HostRibbon`/
	`RibbonPlate` was measured in exactly this shape), this function does
	NOTHING to separate them — there is no OTHER node here to redirect the
	write to; splitting a self-case apart is a BLUEPRINT edit (the plate moves
	to a sibling, its former content moves one level into a NEW inner group),
	not something this resolver can do for you. `findBackdropFindings` still
	SEES a self-case exactly as it sees any other (it reads whatever node
	`resolveAlphaTarget` hands it, self or resolved, with no special case of
	its own) — detection and repair are two different questions, and only the
	second one has a boundary here. ]]
local function resolveAlphaTarget(path: string, node: any): (string, any)
	if node == nil or node.props == nil or node.props.canvasGroup == true then
		return path, node
	end
	local only = transitions.soleFadeGroup(node)
	if only ~= nil then
		return only.path, only
	end
	return path, node
end

export type BackdropFinding = {
	path: string,
	backdropPath: string,
	-- populated for a `surface`-painted finding; nil for a `tint`-painted one
	-- (task POP fix round 1) — `via` always names which channel tripped it
	surface: string?,
	via: string, -- "surface" | "tint" | "acknowledged-plate"
}

--[[ THE ACKNOWLEDGED SHAPE IS STILL SEEN, IT IS JUST NOT A DEFECT (task 7 item
	3). A modal card or a menu popover IS its own plate, and the backdrop the
	invariant is about is the presenter's scrim BEHIND the whole surface — so
	`GroupTransparency` dimming the card's face with the card's text is the shape
	working, not failing. Nothing in the TREE says so: `tests/backdrop_fade.spec
	.luau`'s `buggyScreen` (a full-bleed page whose plate is its sole child, the
	measured `shop.wisp` root cause) is byte-identical. So the surface DECLARES
	it, `transition.plate = "fades"`, and the finder records the shape under its
	own `via` instead of going blind to it: `self.findings()` still carries it, so
	a reader can see which surfaces made the claim. `countsAsBackdropIssue` is
	the ONE place that decides whether a finding is a defect; the reference-app
	sweep asks it, and `backdropIssue` — a message FORMATTER, which decides
	nothing — reads it only so it can never render an acknowledged shape as a
	complaint.

	SOLE-CHILD ONLY. A group with a sibling beside the plate has content the
	plate is genuinely a backdrop FOR, and no declaration reaches that: the
	acknowledgement is about a surface that IS its plate, which is a claim only
	the one-child shape can make. That is what keeps the gate's teeth. ]]
local ACKNOWLEDGED_PLATE = "acknowledged-plate"
transitions.ACKNOWLEDGED_PLATE = ACKNOWLEDGED_PLATE

function transitions.countsAsBackdropIssue(finding: BackdropFinding): boolean
	return type(finding) == "table" and finding.via ~= ACKNOWLEDGED_PLATE
end

--[[ THE FORMATTER'S OWN GUARD (review N10). `countsAsBackdropIssue(nil)`
	answers false — a non-table is not a finding — so `backdropIssue(nil)` used
	to fall into the acknowledged branch and index it. Nothing in `src/` hands
	it one, but it is a PUBLIC formatter over a list a caller filters, and
	"formats whatever you filtered down to" should not have a nil trap in it. ]]
local function isFinding(finding: any): boolean
	return type(finding) == "table" and type(finding.path) == "string" and type(finding.backdropPath) == "string"
end

-- the STRUCTURAL half of the same finding, usable with no coordinator at all:
-- does the node that will actually fade (post `resolveAlphaTarget`) itself
-- COMPOSE an opaque `surface` as one of its own DIRECT children? Zero frames
-- stepped, zero engine — a pure tree read, which is the honest answer to
-- mandate (b): this whole class is visible headlessly, with nothing animated
-- at all.
--
-- ONE LEVEL, DELIBERATELY — not every `surface` anywhere in the subtree. The
-- bug this catches is "the plate meant to hide whatever is BEHIND THE WHOLE
-- FADING SURFACE is itself inside it" (`shop.wisp`'s `Panel`, `page()`'s old
-- `Page`, both direct children of the node the transition targeted); a card's
-- OWN thumbnail or a chip three levels into its content also carries a
-- `surface`, and flagging those too would bury the real finding in ordinary
-- content that was always going to fade in with the rest of the modal — a
-- plate a level down is content the plate above it ALREADY made opaque, not a
-- second backdrop. `tests/backdrop_fade.spec.luau` pins both directions: the
-- unfixed shape reddens this, and legitimate nested content (a card two levels
-- into a fixed page) never does.
local function collectBackdrops(node: any, out: { { node: any, via: string, sole: boolean } })
	local children = node.children or {}
	local sole = #children == 1
	for _, child in children do
		local paints, via = paintsBackdrop(child)
		if paints then
			table.insert(out, { node = child, via = via :: string, sole = sole })
		end
	end
end

-- `alphaNode` is what `resolveAlphaTarget` returns for a DECLARED fade — pass
-- the node as declared (self or a resolved content group) plus the resolved
-- path, so a finding names the same path the coordinator would actually fade.
-- `acknowledged` is `spec.plate == "fades"` — the surface's own declaration that
-- its plate is meant to fade with its content. It re-kinds the SOLE-CHILD shape
-- and nothing else (see ACKNOWLEDGED_PLATE above); omitted, this answers exactly
-- as it always did.
function transitions.findBackdropFindings(
	alphaPath: string,
	alphaNode: any,
	acknowledged: boolean?
): { BackdropFinding }
	local out: { BackdropFinding } = {}
	if alphaNode == nil then
		return out
	end
	local backdrops: { { node: any, via: string, sole: boolean } } = {}
	collectBackdrops(alphaNode, backdrops)
	for _, b in backdrops do
		local via = if acknowledged == true and b.sole then ACKNOWLEDGED_PLATE else b.via
		table.insert(out, {
			path = alphaPath,
			backdropPath = b.node.path,
			surface = if b.via == "surface" then b.node.props.surface else nil,
			via = via,
		})
	end
	return out
end

function transitions.backdropIssue(finding: BackdropFinding): string
	if not isFinding(finding) then
		return `Facet transition: backdropIssue expected a finding (transitions.findBackdropFindings returns them), got {typeof(
			finding
		)}`
	end
	if not transitions.countsAsBackdropIssue(finding) then
		-- an acknowledged plate is not a defect and must never be rendered as
		-- one; it is still reported, so a reader can see the claim was made
		return string.format(
			'%s declares `transition.plate = "fades"`: %s is the surface\'s own plate, meant to fade with its '
				.. "content (the modal/popover shape, whose backdrop is the scrim behind the whole surface). "
				.. "Not a finding.",
			finding.path,
			finding.backdropPath
		)
	end
	local paint = if finding.via == "tint"
		then "opaque `tint`"
		else string.format("opaque `surface = %q`", finding.surface)
	return string.format(
		"%s declares a fading transition whose fade group still composes %s's %s — "
			.. "GroupTransparency dims the two together, so the backdrop can never be legible ahead of the "
			.. "content it sits behind. Move the backdrop OUTSIDE the fade group (a sibling, not a descendant); "
			.. "`src/render/transitions.luau`'s header names the shape.",
		finding.path,
		finding.backdropPath,
		paint
	)
end

function transitions.new(opts: Opts)
	assert(type(opts) == "table" and opts.core ~= nil, "Facet transitions: a core is required")
	assert(opts.clock ~= nil, "Facet transitions: a motion clock is required (Facet.motion.newClock)")
	local core = opts.core
	local clock = opts.clock
	local controller: any = opts.controller
	local metricsOf = opts.metrics or themeSnapshot.neutral
	local emit = opts.feedback
	local surface = opts.surface

	local entries: { [string]: any } = {}
	local disposed = false
	-- task POP, mandate (b)'s gate: every backdrop-inside-fade-group shape ever
	-- DECLARED through this coordinator, deduplicated by (path, backdrop) so a
	-- surface re-entered many times over a session reports once. Read-only for
	-- everyone but `self.findings()`; nothing here costs off that read.
	local foundBackdrops: { BackdropFinding } = {}
	local seenBackdropKeys: { [string]: boolean } = {}
	local function recordBackdropFindings(alphaPath: string, alphaNode: any, acknowledged: boolean?)
		for _, finding in transitions.findBackdropFindings(alphaPath, alphaNode, acknowledged) do
			local key = finding.path .. "\0" .. finding.backdropPath
			if not seenBackdropKeys[key] then
				seenBackdropKeys[key] = true
				table.insert(foundBackdrops, finding)
			end
		end
	end

	--[[ WHO ENTERS TOGETHER (spec 2F). A stagger is a rhythm over the rows of ONE
		list arriving in ONE frame, so the index a row's delay is multiplied by is
		its place in THAT batch — not its place in the list, and not a global
		counter that would make the tenth list of a session start ten beats late.

		THE FRAME is `clock:stats().steps`, the count of steps that did work. Every
		enter of one structural pass is booked before the clock can step again, so
		they read the same count; the next pass reads a moved one and starts over.
		The one shape this cannot separate is two batches with NO work-doing step
		between them — which needs the first batch to have animated nothing, and an
		enter always animates (a spring it aims, or a hold it books).

		THE LIST is the path with the row's own segment AND the keyed segment above
		it removed. `mount.luau` builds a ForEach row at `<list>/[key]/<rowId>`, so
		stripping only the last segment would hand every row its own private batch
		and no row would ever wait for another. A region that is not keyed (a `When`
		branch) keeps its parent, which is the right answer for it: a lone branch is
		the first of its batch and waits for nothing.

		THE KEYED SEGMENT IS "A `[`, ANYTHING AT ALL, A `]`", TAKEN AT THE RIGHTMOST
		SLASH THAT CAN START ONE. A key is the author's own string, so neither a `/`
		NOR a bracket in it is unusual — a route, an asset id, `world/moss`, `a]b`.
		Two narrower forms have each failed here in turn, and both failed the same
		way: the match missed, the row kept its own parent, it became the first of
		its own private batch, and the rows still entered — all at once, with nothing
		said. `/%[[^/]*%]$` (brackets around anything but a slash) lost every
		path-shaped key. `%b[]` (a BALANCED group) fixed those and lost every
		UNBALANCED one instead: `"a]b"` builds `<list>/[a]b]`, where `%b[]` matches
		`[a]` and then fails the anchor, and `"a[b"` builds `<list>/[a[b]`, which
		never balances at all. `%[.*%]` has nothing left to be unbalanced about, and
		the GREEDY `(.*)` before it is what keeps a nested keyed list honest: it
		takes the rightmost slash whose remainder is still a bracket group, so
		`<list>/[A]/Row/Inner/[two]` resolves to the INNER list and each outer row
		keeps its own rhythm. ]]
	local staggerStep, staggerCounts = -1, {} :: { [string]: number }
	local function batchKey(path: string): string
		local parent = string.match(path, "^(.*)/[^/]+$") or ""
		return string.match(parent, "^(.*)/%[.*%]$") or parent
	end
	local function staggerDelay(path: string, spec: Spec): number
		if spec.stagger <= 0 then
			return 0
		end
		-- REDUCED MOTION HAS NO RHYTHM TO DELETE. The authority already lands every
		-- row on the spot, and a hold would only postpone that landing: a decorative
		-- timer under reduced motion holds its VALUE immediately but defers its
		-- settle EVENT to the next step (`motion.luau`'s autoStart branch, which
		-- does that deliberately so a consumer subscribing on the next line cannot
		-- miss it). One frame of every row absent is exactly the pop this whole
		-- setting exists to remove, so the rhythm is asked for here instead.
		if clock:isReduced() then
			return 0
		end
		local step = clock:stats().steps
		if step ~= staggerStep then
			staggerStep, staggerCounts = step, {}
		end
		local key = batchKey(path)
		local n = staggerCounts[key] or 0
		staggerCounts[key] = n + 1
		return math.min(n, STAGGER_CAP) * spec.stagger
	end

	-- task-fix3 symptoms 2/3 (director device round, 2026-08-23): "slides a few
	-- pixels then pops out" / "pops in then slides a few pixels". `space.l` (24px
	-- neutral) is the right size for a DECORATIVE nudge — a toast easing in from
	-- its own edge — and the wrong one for a full-viewport surface push/pop,
	-- where the node needs to travel far enough to read as leaving/entering the
	-- screen: measured, a 390px-wide compact detail sheet sliding 24px stayed
	-- ~94% on screen for its whole enter, then (on exit) the flat 500ms cap
	-- disposed it after ~24px of travel — visually indistinguishable from an
	-- instant pop either way. `spec.distance` (declared per transition, gap 16's
	-- sibling `offset`'s own shape: an opt-in AUTHORED override, never a changed
	-- default) is the fix a caller reaches for when its slide IS the surface
	-- leaving the screen rather than a nudge; nil keeps every existing caller
	-- (toasts included) on the themed default, unchanged.
	local function slideDistance(spec: Spec): number
		if type(spec.distance) == "number" and spec.distance > 0 then
			return spec.distance
		end
		local snap = metricsOf()
		local space = if type(snap) == "table" then (snap :: any).space else nil
		local step = if type(space) == "table" then (space :: any).l else nil
		return if type(step) == "number" and step > 0 then step else DEFAULT_SLIDE_DISTANCE
	end

	-- where the node sits when it is fully ABSENT, for this form in this phase.
	-- Enter travels toward rest (so it starts against the travel direction); exit
	-- travels away from it (so it ends along the travel direction).
	local function absentFor(spec: Spec, form: string, phase: string): any
		local absent: any = { x = 0, y = 0 }
		local travel = TRAVEL[form]
		if travel ~= nil then
			local d = slideDistance(spec)
			local sign = if phase == "enter" then -1 else 1
			absent.x = travel.x * d * sign
			absent.y = travel.y * d * sign
		end
		if form == "materialize" then
			-- the caller's own band wins, exactly as `slideDistance` lets a caller
			-- own its travel (see `MATERIALIZE_SCALE`'s header for why a text-heavy
			-- surface has to)
			absent.scale = if type(spec.scale) == "number" then spec.scale else MATERIALIZE_SCALE
			absent.pivot = spec.pivot
		end
		if fades(spec, form) then
			absent.alpha = 1
		end
		return absent
	end

	-- a fading form needs a declared fade GROUP, and the refusal names the fix —
	-- the same rule (and the same reason) as the presentation channel's own
	-- refusal, raised here so an author hears it at the declaration rather than on
	-- the first frame of the first exit.
	local function assertFadeCapable(path: string, node: any, spec: Spec, form: string)
		if not fades(spec, form) then
			return
		end
		if node ~= nil and node.props ~= nil and node.props.canvasGroup == true then
			return
		end
		error(
			`Facet transition: {path} declares a '{form}' transition, which fades — but the node it applies to `
				.. `is not a fade group. Make the region's child a UI.ZStack\{ canvasGroup = true } (or a `
				.. "UI.Box{ canvasGroup = true } for a single plate) and put the content inside it: "
				.. "GroupTransparency is the one engine property no style rule owns, while per-node transparency "
				.. "would contest native-sheet paint. A slide or `instant` form needs no group.",
			0
		)
	end

	local function writeEntry(entry: any)
		if controller == nil or entry.disposed then
			return
		end
		local p = entry.progress:get()
		local k = 1 - p
		local absent = entry.absent
		-- A newly sampled form may stop fading (or resolve a different group).
		-- Clear the channel we actually wrote, rather than infer ownership from
		-- the new form. Transform writes already replace the whole scale/offset.
		if entry.writtenAlphaPath ~= nil and (absent.alpha == nil or entry.writtenAlphaPath ~= entry.alphaPath) then
			controller.setPresentationTransparency(entry.writtenAlphaPath, nil)
			entry.writtenAlphaPath = nil
		end
		controller.setPresentationTransform(entry.path, {
			x = absent.x * k,
			y = absent.y * k,
			scale = if absent.scale ~= nil then 1 + (absent.scale - 1) * k else nil,
			pivot = if absent.scale ~= nil then absent.pivot else nil,
		})
		if absent.alpha ~= nil then
			controller.setPresentationTransparency(entry.alphaPath, absent.alpha * k)
			entry.writtenAlphaPath = entry.alphaPath
		end
	end

	local function setAbsent(entry: any, absent: any)
		local old = entry.absent
		local oldDistance, newDistance = nil, nil
		-- A collinear pure slide can change direction or distance using the same
		-- spring. Preserve pixels and pixel velocity, not the progress fraction.
		-- Fade/materialize keep their existing shared progress semantics: their
		-- alpha/scale vectors are not collinear when a slide direction reverses.
		if old.alpha == nil and absent.alpha == nil and old.scale == nil and absent.scale == nil then
			if old.y == 0 and absent.y == 0 and old.x ~= 0 and absent.x ~= 0 then
				oldDistance, newDistance = old.x, absent.x
			elseif old.x == 0 and absent.x == 0 and old.y ~= 0 and absent.y ~= 0 then
				oldDistance, newDistance = old.y, absent.y
			end
		end
		if oldDistance ~= nil and newDistance ~= nil and oldDistance ~= newDistance then
			local ratio = oldDistance / newDistance
			local p = 1 - ratio * (1 - entry.progress:get())
			local velocity = ratio * entry.progress:getVelocity()
			core:transaction(function()
				entry.absent = absent
				entry.progress:snap(p)
				entry.progress:setVelocity(velocity)
			end)
		else
			entry.absent = absent
		end
	end

	-- clear the presentation writes: a node at rest owes nothing to the channel, so
	-- the transient UIScale and the group's transparency go away with the motion
	local function clearEntry(entry: any)
		if controller == nil then
			return
		end
		controller.setPresentationTransform(entry.path, nil)
		if entry.writtenAlphaPath ~= nil then
			controller.setPresentationTransparency(entry.writtenAlphaPath, nil)
			entry.writtenAlphaPath = nil
		end
	end

	-- `entry.cap` is whichever alarm this entry is currently holding: the exit's
	-- hard cap, or the enter's stagger hold. One slot, because an entry is in one
	-- phase at a time and every phase change comes through here first.
	local function stopCap(entry: any)
		if entry.cap ~= nil then
			entry.cap:dispose()
			entry.cap = nil
		end
	end

	local function disposeEntry(entry: any)
		if entry.disposed then
			return
		end
		entry.disposed = true
		stopCap(entry)
		if entry.unobserve ~= nil then
			entry.unobserve()
			entry.unobserve = nil
		end
		entry.progress:dispose()
		if entries[entry.path] == entry then
			entries[entry.path] = nil
		end
	end

	local function finishEnter(entry: any)
		if entry.disposed or entry.phase ~= "enter" then
			return
		end
		clearEntry(entry)
		disposeEntry(entry)
		if emit ~= nil then
			-- the causal frame: the thing finished travelling THIS frame
			emit({ type = "arrive", path = entry.path, surface = surface, context = { phase = "enter" } })
		end
	end

	local function finishExit(entry: any)
		if entry.disposed or entry.phase ~= "exit" then
			return
		end
		local done = entry.done
		entry.done = nil
		disposeEntry(entry)
		if done ~= nil then
			done()
		end
	end

	-- the progress spring's two listeners, wired once per spring (entryFor builds
	-- the first; retune builds a replacement when the phase's class differs)
	local function listen(entry: any)
		entry.unobserve = core:observe(entry.progress, function()
			writeEntry(entry)
		end)
		entry.progress:onSettle(function()
			if entry.phase == "enter" then
				finishEnter(entry)
			elseif entry.phase == "exit" then
				finishExit(entry)
			end
		end)
	end

	-- ONE SPRING PER TRANSITION still holds; what changes between phases is its
	-- CLASS. A MotionValue's class is fixed at construction, so a phase that
	-- wants a different one gets a fresh spring seeded with the old value AND
	-- velocity — the reversal keeps its momentum exactly as before.
	local function retune(entry: any, class: string, eps: number?)
		if entry.class == class and entry.eps == eps then
			return
		end
		local old = entry.progress
		local fresh = clock:spring(old:get(), class, { eps = eps })
		fresh:setVelocity(old:getVelocity())
		if entry.unobserve ~= nil then
			entry.unobserve()
			entry.unobserve = nil
		end
		old:dispose()
		entry.progress = fresh
		entry.class = class
		entry.eps = eps
		listen(entry)
	end

	-- `class`/`eps` are the phase's, not the spec's: a FRESH entry is built with
	-- the spring the caller is about to aim, so the `retune` that follows no-ops
	-- (review finding 9 — the old shape constructed `spec.class` unconditionally
	-- and threw it away one line later, which on a 600-row retire is 600
	-- MotionValues built, observed and disposed for nothing).
	local function entryFor(
		path: string,
		node: any,
		spec: Spec,
		initial: number,
		alphaPath: string,
		class: string,
		eps: number?
	): any
		local existing = entries[path]
		if existing ~= nil then
			existing.node = node
			existing.spec = spec
			existing.alphaPath = alphaPath
			return existing
		end
		local entry: any = {
			path = path,
			node = node,
			spec = spec,
			alphaPath = alphaPath,
			phase = "idle",
			absent = { x = 0, y = 0 },
			progress = clock:spring(initial, class, { eps = eps }),
			class = class,
			eps = eps,
			disposed = false,
		}
		entries[path] = entry
		-- the write rides the VALUE, not the clock step, so an instant placement
		-- (reduced motion) lands exactly like a stepped one — and inside the clock's
		-- single per-frame transaction when it is stepped
		listen(entry)
		return entry
	end

	local self = {}

	-- the controller does not exist until `renderer.attach` + `initialRender`, and
	-- a transition declared at mount time has already seeded its values. Binding
	-- flushes them, so the first painted frame is the seeded one rather than a
	-- frame at rest followed by a jump.
	function self.bindController(c: any)
		controller = c
		self.flush()
	end

	-- re-assert every running transition's presentation values. A structural
	-- refresh CREATES the handles for a subtree that was mounted since the last
	-- one, and the seed written at mount time had nothing to land on — so without
	-- this a branch entering mid-session paints one frame at rest and then jumps.
	function self.flush()
		for _, entry in entries do
			writeEntry(entry)
		end
	end

	-- task POP mandate (b)'s gate reads this: every backdrop-inside-fade-group
	-- shape any transition on this surface has ever DECLARED, a pure structural
	-- fact with zero frames stepped. A copy, like `controller.stats()` (F-30).
	function self.findings(): { BackdropFinding }
		return table.clone(foundBackdrops)
	end

	function self.beginEnter(path: string, node: any, declared: any)
		if disposed then
			return
		end
		local spec = transitions.resolve(declared)
		local alphaPath, alphaNode = resolveAlphaTarget(path, node)
		assertFadeCapable(alphaPath, alphaNode, spec, spec.enter)
		assertFadeCapable(alphaPath, alphaNode, spec, spec.exit)
		--[[ task POP fix round 1 (sweep found this real, against the GATE
			itself): a PURE slide (no `fade`) never writes `GroupTransparency`
			anywhere — `resolveAlphaTarget`'s own "zero candidates" fallback
			then names the DECLARED node, which was never meant to be an alpha
			target at all, and a backdrop check against it is checking a
			property nothing ever animates. Measured: `p5_wardrobe`'s BuyBar
			(`{enter = "slide-up"}`, no fade) flagged its own `Buy` button as
			an "opaque backdrop" — true of the shape, meaningless for the bug,
			since GroupTransparency is never written here at all. Gated on
			`spec.enter` actually fading, matching what this transition will
			really do to the node. ]]
		if fades(spec, spec.enter) then
			recordBackdropFindings(alphaPath, alphaNode, spec.plate == "fades")
		end
		if spec.enter == "instant" then
			-- a hard place: nothing to animate, but the arrival is still a fact the
			-- feedback seam owes its subscribers (information parity)
			local existing = entries[path]
			if existing ~= nil then
				clearEntry(existing)
				disposeEntry(existing)
			end
			if emit ~= nil then
				emit({ type = "arrive", path = path, surface = surface, context = { phase = "enter" } })
			end
			return
		end
		--[[ A REVERSAL IS NOT AN ENTRANCE. An entry that already exists is
			mid-flight — exiting, or parked by `cancelExit` — and therefore ON
			SCREEN right now. Holding one would freeze a visible row at whatever
			alpha its exit had reached and then resume it, which reads as a
			stutter rather than a rhythm; and counting it into the batch would
			push the rows that really are arriving a beat further out. Only a row
			travelling from the absent place waits, and only those are counted. ]]
		local reversal = entries[path] ~= nil
		local entry = entryFor(path, node, spec, 0, alphaPath, spec.class, nil)
		retune(entry, spec.class, nil)
		stopCap(entry)
		entry.done = nil
		entry.phase = "enter"
		setAbsent(entry, absentFor(spec, spec.enter, "enter"))
		writeEntry(entry) -- seed the absent place before the first step
		local delay = if reversal then 0 else staggerDelay(path, spec)
		if delay <= 0 then
			entry.progress:setTarget(1)
			return
		end
		--[[ HOLD AT THE ABSENT PLACE, THEN AIM. The row is already painted absent
			(the seed above), so the wait is invisible: a row that has not started
			yet, never a row stalled part way. The hold rides `entry.cap`, the same
			slot the exit cap uses, because the two can never be live at once — and
			because every teardown path already clears that slot, so an exit,
			a re-entry or a disposal arriving DURING the wait cancels the wait with
			no code of its own (`stopCap`, which `beginExit`/`cancelExit`/
			`disposeEntry` all call; `stopCap` above has just freed it for us).

			`from = to = 0` BECAUSE THE RAMP IS NOT THE POINT (review, task 8). A
			MotionValue IS a core signal, so a 0→1 ramp does a real `value:set` and
			a `countWrite()` on every frame of a wait that nobody observes — the
			only thing read here is the settle EVENT. `driver.settled()` is
			elapsed-based (`motion/motion.luau`'s timer driver), so a flat timer
			settles on exactly the same frame, while the value's write gate
			("an unmoved motion writes nothing") suppresses every write in between:
			a 600-row stagger stops spending ~14k writes on a number with no
			reader. `clock:stats().writes` is a measured gate, not a curiosity. ]]
		local hold = clock:timer({ from = 0, to = 0, duration = delay, kind = "decorative" })
		entry.cap = hold
		hold:onSettle(function()
			if entry.cap == hold then
				entry.cap = nil
			end
			if entry.phase == "enter" and not entry.disposed then
				entry.progress:setTarget(1)
			end
			-- the hold is spent; drop it from the clock's owned set rather than
			-- leave it there until the whole surface's clock is disposed
			hold:dispose()
		end)
	end

	-- nil = "dispose now" (no declared transition, or an `instant` exit): the mount
	-- layer then takes its ordinary removal path and nothing is retired.
	function self.shouldRetire(path: string, node: any): any?
		if disposed then
			return nil
		end
		local declared = node ~= nil and node.transition
		if declared == nil or declared == false then
			return nil
		end
		local spec = transitions.resolve(declared)
		if spec.exit == "instant" then
			return nil
		end
		local alphaPath, alphaNode = resolveAlphaTarget(path, node)
		assertFadeCapable(alphaPath, alphaNode, spec, spec.exit)
		-- the enter-side twin's own reasoning: an exit that does not fade
		-- never writes GroupTransparency, so a backdrop check against it is
		-- checking a property nothing here ever animates
		if fades(spec, spec.exit) then
			recordBackdropFindings(alphaPath, alphaNode, spec.plate == "fades")
		end
		return spec
	end

	function self.beginExit(path: string, node: any, spec: Spec, done: () -> ())
		if disposed then
			done()
			return
		end
		local alphaPath = resolveAlphaTarget(path, node)
		local entry = entryFor(path, node, spec, 1, alphaPath, spec.exitClass, EXIT_EPS)
		retune(entry, spec.exitClass, EXIT_EPS)
		entry.phase = "exit"
		entry.done = done
		setAbsent(entry, absentFor(spec, spec.exit, "exit"))
		writeEntry(entry)
		-- THE HARD CAP, armed before the aim so an instant form (reduced motion)
		-- disposes it on the way out rather than leaving a timer behind. Flat
		-- (`from = to = 0`) for the same reason the enter hold above is: only its
		-- settle FRAME is read, and a ramp nobody observes is 30 signal writes per
		-- exit charged to a gate that counts them.
		stopCap(entry)
		local cap = clock:timer({ from = 0, to = 0, duration = EXIT_CAP_SECONDS, kind = "decorative" })
		entry.cap = cap
		cap:onSettle(function()
			finishExit(entry)
		end)
		-- an aim that completes on the spot (reduced motion) disposes the entry —
		-- and the cap with it — before this returns
		entry.progress:setTarget(0)
	end

	--[[ the exit is off: park the motion where it stands so the enter that follows
		reverses from this value AND this velocity. `release` is the teardown twin.

		PARKED MEANS RE-AIMED, not merely unwatched. Stopping the cap and clearing
		the completion leaves the SPRING still aimed at 0 — the exit's own target —
		so a "parked" motion went right on travelling to absent. Both callers in
		`mount.luau` follow this with `beginEnter` on the next line, whose aim
		replaces that one, so no shipped path ever saw it; the seam is public on
		the coordinator all the same, and the aim is what the sentence above claims.
		Re-aiming at the current value keeps that value AND the velocity a retarget
		carries, which is exactly what the reversal needs. ]]
	function self.cancelExit(path: string)
		local entry = entries[path]
		if entry == nil then
			return
		end
		stopCap(entry)
		entry.done = nil
		entry.phase = "parked"
		entry.progress:setTarget(entry.progress:get())
	end

	function self.release(path: string)
		local entry = entries[path]
		if entry ~= nil then
			entry.done = nil
			disposeEntry(entry)
		end
	end

	function self.dispose()
		if disposed then
			return
		end
		disposed = true
		local held: { any } = {}
		for _, entry in entries do
			table.insert(held, entry)
		end
		for _, entry in held do
			entry.done = nil
			disposeEntry(entry)
		end
		entries = {}
	end

	return self
end

transitions.EXIT_CAP_SECONDS = EXIT_CAP_SECONDS
-- so a consumer that must mirror the default (navigation_stack.luau's two-page
-- lockstep, which pins exitClass to the SAME class rather than let it drift
-- onto DEFAULT_EXIT_CLASS) reads this instead of copying the string by hand.
transitions.DEFAULT_CLASS = DEFAULT_CLASS
transitions.DEFAULT_EXIT_CLASS = DEFAULT_EXIT_CLASS
-- the exit phase's settle epsilon (see its definition above), published for the
-- same reason the classes are: `tests/transitions.spec.luau` reads it to say how
-- much of its travel an exit may end with, rather than re-deriving the number
transitions.EXIT_EPS = EXIT_EPS
-- how far a list's stagger may accumulate before every further row rides in with
-- the last delayed one (see STAGGER_CAP above)
transitions.STAGGER_CAP = STAGGER_CAP

return transitions
