--!strict
-- LARGE-TEXT AUTHORING SAFETY (docs/plans/large-text-accessibility.md
-- "Diagnostics and authoring safety"; LTN-4/LTN-5). Six pure checks over a
-- solve result, each answering one question a screenshot cannot:
--
--   overlaps          do painted siblings collide?
--   clippedEssential  did text truncate with no way back to the full string?
--   helpRoutes        does anything still REACH a `help` string, and does the
--                     screen say it anywhere a touch player can read?
--   hitFloor          did reflow push an interactive box under the target floor?
--   movingText        is more than one moving text surface running?
--   focusVisibility   is the focused rect outside the region that clips it?
--   outOfBounds       did unclipped content leave the declared bounds?
--
-- VERIFICATION SURFACE, NOT PUBLIC API. This module is deliberately absent from
-- src/init.luau: it is required by path from tests and tools. A consumer screen
-- has nothing to do with it — the checks exist to fail a gate, and a diagnostic
-- that ships as API acquires compatibility obligations it should never have.
--
-- PURE, and pure in the strong sense: no ownership, no state, no clock, no
-- dependency on the mounted tree. Every function is (solve output -> findings),
-- so a fixture built by hand and a real solve are indistinguishable to it —
-- which is what makes the negative controls in the spec meaningful. It runs
-- under Lune and touches no Instance (UI-BOUND-001).
--
-- A FINDING NAMES THE NODE, THE CONTRACT AND THE LIKELY FIX (the plan's own
-- rule). "Overlap at /S/Row" is a fact; "…and nothing clips an HStack, so give
-- the box room or declare the overlap" is actionable. The list is ORDERED
-- deterministically — two runs over equal input produce equal output — because a
-- diff of two audit runs is how a reflow regression is read.
--
-- THE CRUDE GLOBAL CHECK MUST NOT FALSE-FAIL A DECLARED CASE. Overlap is the one
-- check where the honest answer depends on intent, so `overlaps` skips three
-- declared relationships before it skips anything else: a layering container
-- (`zstack`/`anchor`, whose whole job is to stack), a container that declared
-- `overflow = "intentionalOverlap"`, and any pair the caller allowed through
-- `opts.declaredOverlays`. Without that, a screen with one deliberate badge over
-- one avatar produces a permanent finding, and a permanent finding is a finding
-- people learn to ignore.

local specGuard = require("../spec_guard")

local text_audit = {}

export type Rect = { x: number, y: number, w: number, h: number }

-- `check` names which of the five produced it; `node` is the solver path (the
-- same key `rects` is indexed by); `other` is the second party where the finding
-- is about a PAIR; `detail` carries the measured numbers that made it true.
export type Finding = {
	check: string,
	node: string,
	other: string?,
	contract: string,
	fix: string,
	detail: string?,
}

export type Viewport = { path: string, rect: Rect }
export type Focus = { path: string?, rect: Rect }

-- containers whose job IS to stack children over one another. A pair of children
-- of one of these is not an overlap finding at any epsilon (solver kinds).
local LAYERING_KIND: { [string]: boolean } = { zstack = true, anchor = true }

local OVERLAP_KEYS = specGuard.keySet({ "epsilon", "declaredOverlays" })
local CLIPPED_KEYS = specGuard.keySet({ "nonEssential" })
local HELP_KEYS = specGuard.keySet({ "convenience" })

local function sortFindings(out: { Finding })
	table.sort(out, function(a: Finding, b: Finding): boolean
		if a.check ~= b.check then
			return a.check < b.check
		end
		if a.node ~= b.node then
			return a.node < b.node
		end
		return (a.other or "") < (b.other or "")
	end)
end

local function finish(out: { Finding }): { Finding }
	sortFindings(out)
	for _, f in out do
		table.freeze(f)
	end
	return table.freeze(out)
end

local function parentOf(path: string): string?
	local cut = string.find(path, "/[^/]*$")
	if cut == nil or cut == 1 then
		return nil -- a root has no sibling set
	end
	return string.sub(path, 1, cut - 1)
end

-- is `prefix` this path, or an ancestor of it? Compared on the SEPARATOR so
-- "/S/Row" never matches "/S/RowTwo" — the false-positive every prefix test in
-- this repository has had to be fixed for at least once.
local function isPathPrefix(prefix: string, path: string): boolean
	if prefix == path then
		return true
	end
	return string.sub(path, 1, #prefix + 1) == prefix .. "/"
end

-- THE HIDDEN SET IS A SUBTREE, NOT A NODE. The solver marks the ROOT of an
-- unchosen candidate (`entry.hidden`) and leaves its descendants their solved
-- rects, so a check that read `entry.hidden` alone would audit a subtree that
-- does not paint — and report overlaps between things nobody can see. Carried
-- down by prefix, exactly as the renderer's visibility walk carries it.
local function hiddenRoots(rects: { [string]: any }): { string }
	local roots: { string } = {}
	for path, entry in rects do
		if type(entry) == "table" and entry.hidden == true then
			table.insert(roots, path)
		end
	end
	table.sort(roots)
	return roots
end

local function isHidden(roots: { string }, path: string): boolean
	for _, root in roots do
		if isPathPrefix(root, path) then
			return true
		end
	end
	return false
end

local function rectOf(entry: any): Rect?
	local r = if type(entry) == "table" then entry.rect else nil
	if type(r) ~= "table" or type(r.x) ~= "number" or type(r.w) ~= "number" then
		return nil
	end
	return r
end

-- the overlap of two rects on each axis; negative or zero means "they do not"
local function overlapOf(a: Rect, b: Rect): (number, number)
	local ow = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
	local oh = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
	return ow, oh
end

-- an allowlist entry is a path-PREFIX pair (either orientation) or a predicate.
-- Prefixes, not exact paths, because the declaration an author can actually
-- write is "this panel may sit over this list", not one line per mounted row.
local function allowedPair(declared: any, a: string, b: string): boolean
	if declared == nil then
		return false
	end
	if type(declared) == "function" then
		return declared(a, b) == true
	end
	for _, pair in declared :: { any } do
		local pa = if type(pair) == "table" then (pair.a or pair[1]) else nil
		local pb = if type(pair) == "table" then (pair.b or pair[2]) else nil
		if type(pa) == "string" and type(pb) == "string" then
			if (isPathPrefix(pa, a) and isPathPrefix(pb, b)) or (isPathPrefix(pa, b) and isPathPrefix(pb, a)) then
				return true
			end
		end
	end
	return false
end

--[[ overlaps(rects, opts?) -> { Finding }

	Painted SIBLINGS that intersect on both axes by more than `opts.epsilon`
	(default 1px — a one-pixel seam from independent rounding is not a collision).
	Siblings only: a child inside its own parent is containment, not overlap.

	opts.epsilon          px slack on each axis, default 1
	opts.declaredOverlays array of { a = prefix, b = prefix } (or positional
	                      { prefix, prefix }) pairs, or a predicate
	                      (pathA, pathB) -> boolean. Either orientation matches.
]]
function text_audit.overlaps(rects: { [string]: any }, opts: any?): { Finding }
	specGuard.assertKnownKeys("text_audit.overlaps", opts, OVERLAP_KEYS, "opts")
	local options: any = opts or {}
	local epsilon = if type(options.epsilon) == "number" then options.epsilon else 1
	local declared = options.declaredOverlays
	local out: { Finding } = {}
	local roots = hiddenRoots(rects)

	-- group the paintable nodes by parent, deterministically
	local byParent: { [string]: { string } } = {}
	local parents: { string } = {}
	for path, entry in rects do
		local rect = rectOf(entry)
		if rect == nil or rect.w <= 0 or rect.h <= 0 or isHidden(roots, path) then
			continue
		end
		local parent = parentOf(path)
		if parent == nil then
			continue
		end
		if byParent[parent] == nil then
			byParent[parent] = {}
			table.insert(parents, parent)
		end
		table.insert(byParent[parent], path)
	end
	table.sort(parents)

	for _, parent in parents do
		local parentEntry = rects[parent]
		local parentKind = if type(parentEntry) == "table" then parentEntry.kind else nil
		local parentOverflow = if type(parentEntry) == "table" then parentEntry.overflow else nil
		if LAYERING_KIND[tostring(parentKind)] or parentOverflow == "intentionalOverlap" then
			continue -- a DECLARED layering relationship: stacking is the job
		end
		local children = byParent[parent]
		table.sort(children)
		for i = 1, #children - 1 do
			for j = i + 1, #children do
				local a, b = children[i], children[j]
				if allowedPair(declared, a, b) then
					continue
				end
				local ra, rb = rectOf(rects[a]) :: Rect, rectOf(rects[b]) :: Rect
				local ow, oh = overlapOf(ra, rb)
				if ow > epsilon and oh > epsilon then
					table.insert(out, {
						check = "overlaps",
						node = a,
						other = b,
						contract = "painted siblings must not overlap; nothing clips them, so whichever "
							.. "paints later covers the other",
						fix = "give the boxes room (a `minMax` FLOOR rather than a fixed cap, a wrap, or a "
							.. "smaller compact form), or declare the relationship — "
							.. '`overflow = "intentionalOverlap"` on the parent, or an opts.declaredOverlays pair',
						detail = string.format("overlap %dx%dpx inside %s", math.floor(ow), math.floor(oh), parent),
					})
				end
			end
		end
	end
	return finish(out)
end

--[[ clippedEssential(rects, opts?) -> { Finding }

	Text the solve reports TRUNCATED that neither declares `disclose` nor appears
	in the caller's non-essential allowlist. This is the plan's rung 3 stated as a
	check: truncation is permitted only for bounded secondary/identity text, and
	only with a full-value path.

	opts.nonEssential  array of path prefixes, or a predicate (path) -> boolean:
	                   text the CALLER declares as flavour, where an ellipsis
	                   loses nothing. Declared, never inferred.
]]
function text_audit.clippedEssential(rects: { [string]: any }, opts: any?): { Finding }
	specGuard.assertKnownKeys("text_audit.clippedEssential", opts, CLIPPED_KEYS, "opts")
	local options: any = opts or {}
	local allow = options.nonEssential
	local out: { Finding } = {}
	local roots = hiddenRoots(rects)

	local function allowed(path: string): boolean
		if allow == nil then
			return false
		end
		if type(allow) == "function" then
			return allow(path) == true
		end
		for _, prefix in allow :: { any } do
			if type(prefix) == "string" and isPathPrefix(prefix, path) then
				return true
			end
		end
		return false
	end

	for path, entry in rects do
		local facts = if type(entry) == "table" then entry.textFacts else nil
		if type(facts) ~= "table" or facts.truncated ~= true then
			continue
		end
		-- a declared full-value path satisfies the ladder: the LTN-4 plate
		-- (`disclose`) or the auto reveal's travel (`reveal`, 2026-08-04)
		if facts.disclose == true or facts.reveal == true or allowed(path) or isHidden(roots, path) then
			continue
		end
		table.insert(out, {
			check = "clippedEssential",
			node = path,
			contract = "truncated text must expose its full value: only bounded secondary/identity text "
				.. "may be cut, and only with a way back to the whole string",
			fix = "reflow or scroll instead, or declare `UI.Text{ disclose = true }` so engaging it "
				.. "presents the full value — or list it in opts.nonEssential if the ellipsis loses nothing",
			detail = string.format(
				"policy %s, %d of %d lines drawn at %dpx",
				tostring(facts.policy),
				tonumber(facts.lines) or 0,
				tonumber(facts.naturalLines) or 0,
				math.floor(tonumber(facts.size) or 0)
			),
		})
	end
	return finish(out)
end

--[[ helpRoutes(declarations, rects, opts?) -> { Finding }

	The check `help` owes the round, and the reason it is not a second
	`clippedEssential`.

	`help` (navigation-and-menus D3a) shows NOTHING on touch, by specification:
	Apple binds no gesture to it on any platform, and D2 left the one candidate
	gesture with the full-value disclosure plate. That is only defensible while
	`help` is never the only route to something a player needs, so this is that
	claim made mechanical. It asks TWO questions, and keeps them separate on
	purpose:

	  helpNoRoute    nothing engages this help on ANY input class. Not a
	                 duplication question and NOT WAIVABLE: a sentence no gesture
	                 reaches is not "convenience", it is dead weight in the tree.
	  helpOnlyRoute  the screen says this nowhere else, so a player who never
	                 hovers — every touch player, and every pad player who does not
	                 land the ring here — cannot read it.

	WHY THE SPLIT IS THE POINT. `clippedEssential` above accepts the DECLARATION
	`disclose = true` as proof and stops; it never asks whether the gesture that
	reaches the plate still exists, which is exactly how D2's long-press decision
	could have been made invisibly. So here a waiver may answer the authoring
	question ("this repeats nothing and that is fine") and may NEVER answer the
	reachability one. The routes are measured, not declared: `hover` is the LIVE
	pointer class as the renderer wired it, `focus` is whether the ring can land on
	this node or on something containing it — `presenter.helpDeclarations()`
	reports both off the mounted tree.

	declarations  { [path] = { text: string, hover: boolean, focus: boolean } }
	rects         the solve output, read for what the screen actually PAINTS
	opts.convenience  array of path prefixes, or a predicate (path) -> boolean:
	                  help the caller declares as a pointer convenience. It
	                  silences `helpOnlyRoute` and nothing else.
]]
function text_audit.helpRoutes(declarations: { [string]: any }, rects: { [string]: any }, opts: any?): { Finding }
	specGuard.assertKnownKeys("text_audit.helpRoutes", opts, HELP_KEYS, "opts")
	local options: any = opts or {}
	local allow = options.convenience
	local out: { Finding } = {}
	local roots = hiddenRoots(rects)

	local function waived(path: string): boolean
		if allow == nil then
			return false
		end
		if type(allow) == "function" then
			return allow(path) == true
		end
		for _, prefix in allow :: { any } do
			if type(prefix) == "string" and isPathPrefix(prefix, path) then
				return true
			end
		end
		return false
	end

	-- WHAT THE SCREEN ACTUALLY SAYS: painted text only. A hidden candidate does
	-- not say anything (the F-1 class), and neither does a TRUNCATED label — an
	-- ellipsis is not the sentence, which is the whole finding of the check above.
	local spoken: { string } = {}
	for path, entry in rects do
		local facts = if type(entry) == "table" then entry.textFacts else nil
		if type(facts) ~= "table" or facts.truncated == true or isHidden(roots, path) then
			continue
		end
		if type(facts.text) == "string" then
			table.insert(spoken, string.lower(facts.text :: string))
		end
	end

	local paths: { string } = {}
	for path in declarations do
		table.insert(paths, path)
	end
	table.sort(paths)

	for _, path in paths do
		local decl = declarations[path]
		if type(decl) ~= "table" or type(decl.text) ~= "string" then
			continue
		end
		if decl.hover ~= true and decl.focus ~= true then
			table.insert(out, {
				check = "helpNoRoute",
				node = path,
				contract = "a `help` string must be reachable by at least one live input class — the pointer "
					.. "hover zone or the focus ring. Touch shows nothing by specification",
				fix = "put the help on the focusable control rather than on a decoration, or accept that this "
					.. "sentence can never be read and delete it. No opts.convenience waiver applies here: a "
					.. "declaration cannot answer whether a gesture exists",
				detail = string.format(
					"hover %s, focus %s",
					tostring(decl.hover == true),
					tostring(decl.focus == true)
				),
			})
			continue
		end
		if waived(path) then
			continue
		end
		local wanted = string.lower(decl.text)
		local echoed = false
		for _, line in spoken do
			if string.find(line, wanted, 1, true) ~= nil then
				echoed = true
				break
			end
		end
		if echoed then
			continue
		end
		table.insert(out, {
			check = "helpOnlyRoute",
			node = path,
			contract = "`help` shows nothing on touch, so it must never be the only route to something a "
				.. "player needs: this sentence appears nowhere the screen actually paints",
			fix = "say it on screen as well (a caption, a secondary label, a Callout), or list it in "
				.. "opts.convenience if a touch player genuinely loses nothing by never seeing it",
			detail = string.format("%q is painted by no visible, untruncated text node", decl.text),
		})
	end
	return finish(out)
end

--[[ hitFloor(rects, floorPx?) -> { Finding }

	Interactive nodes — the ones the solve carries an `hitFloor` for, which is the
	control contract's declared floor clamped up by the theme — whose PAINTED box
	fell below the floor.

	The painted box, deliberately, and not the expanded hit rect: the renderer
	already inflates sub-floor hit geometry, so an audit of the hit rect could
	never fire. What reflow actually produces is a control the player can hit and
	cannot see, whose invisible activation surface now overlaps its neighbours —
	which is the defect, and it is invisible to every other check here.

	`floorPx` overrides the per-node floor (audit the whole screen against 44).
]]
function text_audit.hitFloor(rects: { [string]: any }, floorPx: number?): { Finding }
	local out: { Finding } = {}
	local roots = hiddenRoots(rects)
	for path, entry in rects do
		local declared = if type(entry) == "table" then entry.hitFloor else nil
		if type(declared) ~= "number" then
			continue
		end
		local rect = rectOf(entry)
		if rect == nil or isHidden(roots, path) then
			continue
		end
		local floor = if type(floorPx) == "number" then floorPx else declared
		if rect.w >= floor and rect.h >= floor then
			continue
		end
		table.insert(out, {
			check = "hitFloor",
			node = path,
			contract = string.format("an interactive control must paint at least %dpx on both axes", floor),
			fix = "let the row reflow (wrap the label, drop to a compact form, or stack the group) rather "
				.. "than compressing the control — the renderer expands the HIT rect, which puts an "
				.. "invisible activation surface over its neighbours",
			detail = string.format("painted %dx%dpx", math.floor(rect.w), math.floor(rect.h)),
		})
	end
	return finish(out)
end

--[[ movingText(count, max?) -> { Finding }

	At most `max` (default 1) moving text surfaces may run in the active
	presentation. Trivial by design: the counter is the presenter's, this is only
	the rule, and having the rule pure is what stops a future engaged reveal from
	proliferating silently (LTN-2 shipped a STATIC disclosure precisely so the
	count is zero today).
]]
function text_audit.movingText(count: number, max: number?): { Finding }
	local allowed = if type(max) == "number" then max else 1
	local n = if type(count) == "number" then count else 0
	if n <= allowed then
		return finish({})
	end
	return finish({
		{
			check = "movingText",
			node = "(presentation)",
			contract = string.format("at most %d moving text surface(s) may run at once", allowed),
			fix = "engage the reveal for the focused/hovered item only, and stop the others — or use the "
				.. "static full-value disclosure, which moves nothing and is reduced-motion-safe by construction",
			detail = string.format("%d running", n),
		},
	})
end

--[[ focusVisibility(focus, viewports) -> { Finding }

	A focused rect that lies FULLY outside a clipping viewport that contains it is
	a finding: focus moved somewhere the player cannot see, which reads as focus
	having vanished.

	`focus`     { path = string?, rect = Rect }; nil means nothing is focused
	`viewports` { { path = string, rect = Rect }, … } — the clipping regions
	            (ScrollView viewports). When `focus.path` is given, only the
	            viewports that CONTAIN it apply (a sibling scroller clipping
	            nothing of ours is not evidence of anything); with no path, every
	            supplied viewport is treated as applicable.
]]
function text_audit.focusVisibility(focus: Focus?, viewports: { Viewport }?): { Finding }
	local out: { Finding } = {}
	if focus == nil or viewports == nil then
		return finish(out)
	end
	local fr = if type(focus) == "table" then focus.rect else nil
	if type(fr) ~= "table" or type(fr.x) ~= "number" then
		return finish(out)
	end
	local applicable: { Viewport } = {}
	for _, vp in viewports do
		if type(vp) ~= "table" or type(vp.rect) ~= "table" or type(vp.path) ~= "string" then
			continue
		end
		if focus.path == nil or isPathPrefix(vp.path, focus.path) then
			table.insert(applicable, vp)
		end
	end
	table.sort(applicable, function(a, b)
		return a.path < b.path
	end)
	for _, vp in applicable do
		local ow, oh = overlapOf(fr, vp.rect)
		if ow > 0 and oh > 0 then
			continue
		end
		table.insert(out, {
			check = "focusVisibility",
			node = focus.path or "(focused)",
			other = vp.path,
			contract = "the focused node must be visible inside the region that clips it",
			fix = "scroll the focused node into view before/with the focus move (the framework's "
				.. "keep-visible path), or exclude it from focus order while it is off-screen",
			detail = string.format(
				"focused rect (%d,%d %dx%d) is outside viewport (%d,%d %dx%d)",
				math.floor(fr.x),
				math.floor(fr.y),
				math.floor(fr.w),
				math.floor(fr.h),
				math.floor(vp.rect.x),
				math.floor(vp.rect.y),
				math.floor(vp.rect.w),
				math.floor(vp.rect.h)
			),
		})
	end
	return finish(out)
end

--[[ outOfBounds(rects, bounds, opts?) -> { Finding }

	A painted node that leaves the DECLARED bounds (normally the viewport's safe
	content rect) is a finding: an unclipped stack that outgrew its screen renders
	off the edge and no per-node check sees it — measured during the Step 8.5
	matrix build, where a content-sized HStack overflowed a 390px phone by 195px
	and produced zero findings from the four checks above (the plan's own
	diagnostics list names "leaving their declared bounds"; this closes that hole).

	`bounds` is the box everything must stay inside. Legal escapes are declared,
	never guessed: `opts.scrollHosts` lists path prefixes whose DESCENDANTS may
	exceed the bounds (a scroll canvas exists to be bigger than its window — the
	reachability question for those is focusVisibility's, not this one's);
	`opts.epsilon` (default 1px) forgives antialiasing slop.
]]
local OUT_OF_BOUNDS_KEYS = specGuard.keySet({ "epsilon", "scrollHosts" })

function text_audit.outOfBounds(rects: { [string]: any }, bounds: Rect, opts: any?): { Finding }
	specGuard.assertKnownKeys("text_audit.outOfBounds", opts, OUT_OF_BOUNDS_KEYS, "opts")
	local o: any = opts or {}
	local epsilon = if type(o.epsilon) == "number" then o.epsilon else 1
	local hosts: { string } = {}
	for _, prefix in (o.scrollHosts :: { string }?) or {} do
		if type(prefix) == "string" then
			table.insert(hosts, prefix)
		end
	end
	local out: { Finding } = {}
	local roots = hiddenRoots(rects)
	for path, entry in rects do
		local rect = rectOf(entry)
		if rect == nil or isHidden(roots, path) then
			continue
		end
		local inScroll = false
		for _, prefix in hosts do
			if isPathPrefix(prefix, path) and prefix ~= path then
				inScroll = true
				break
			end
		end
		if inScroll then
			continue
		end
		local overLeft = bounds.x - rect.x
		local overTop = bounds.y - rect.y
		local overRight = (rect.x + rect.w) - (bounds.x + bounds.w)
		local overBottom = (rect.y + rect.h) - (bounds.y + bounds.h)
		local worst = math.max(overLeft, overTop, overRight, overBottom)
		if worst <= epsilon then
			continue
		end
		table.insert(out, {
			check = "outOfBounds",
			node = path,
			contract = "a painted node must stay inside the declared bounds unless a scroll region owns it",
			fix = "give the content a reflow candidate (wrap, stack, step the composition down) or put it "
				.. "inside a scrolling region declared in opts.scrollHosts — content past the edge is "
				.. "unreachable on every input class",
			detail = string.format(
				"exceeds bounds by %dpx (rect %d,%d %dx%d vs bounds %d,%d %dx%d)",
				math.ceil(worst),
				math.floor(rect.x),
				math.floor(rect.y),
				math.floor(rect.w),
				math.floor(rect.h),
				math.floor(bounds.x),
				math.floor(bounds.y),
				math.floor(bounds.w),
				math.floor(bounds.h)
			),
		})
	end
	return finish(out)
end

return text_audit
