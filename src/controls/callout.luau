--!strict
--[[ CALLOUT — the app-PUSHED coach mark (navigation-and-menus brief §2 D3b;
	director ruling 2026-08-16 §6.2).

	`docs/plans/reference-media/2026-08-16-roblox-app-navigation/f1-avatar-editor.jpeg`
	is this control: a styled plate hanging under a top-right `+`, its body shifted
	left to stay on screen, an arrow tail still pointing up at the button — and,
	across the whole of `r3-segmented-control.mov`, visible and unchanged while the
	player operates the controls beneath it.

	IT IS NOT A TOOLTIP, AND THE DIFFERENCE IS THE WHOLE DELIVERABLE. Apple's own
	separation, read 2026-08-16: `.help(_:)` is PLAYER-PULLED, pointer-hover-only
	and shows nothing on touch (`UI.Button{ help = … }`, D3a); TipKit's
	`popoverTip(_:arrowEdge:action:)` "presents a popover tip on the modified view…
	WHEN THE TIP BECOMES ELIGIBLE FOR DISPLAY". The app decides, from rules. It
	appears on every input class, and it retires permanently. So they are two
	constructs, and conflating them is what would have made `help` fight D2's Menu
	for the one touch gesture neither could otherwise reach. (Both carry D1's arrow
	tail since the 2026-08-16 device review — a stem says which control the words
	are about, which is a question both plates leave open without one.)

	APPLE'S WARNING SHIPS WITH IT, verbatim, because it is the design constraint
	and not a footnote: *"Use tips sparingly… Don't use tips to guide people
	through your app, or for advertising and promotion purposes."*

	PERSISTENCE IS THE CALLER'S, NEVER THE FRAMEWORK'S. This is a hard boundary.
	LuauUI has no save layer and must not grow one here, so the construct READS
	the caller's own Readables — `seen`, `sessions`, `featureUsed` — and REPORTS,
	exactly once, through the required `onRetire(reason)` that this tip should
	never be shown again. Whether anything is written, and where, is a decision
	that happens entirely outside this file. A framework that quietly persisted
	player state would be a different product, and `tests/callout.spec.luau` has
	the case that fails the day one starts.

	IT NEVER BLOCKS. It is presented, not modalled: no focus trap, no scrim, and
	the tap-away catcher runs in the presenter's NON-CONSUMING mode, so a tap
	outside the plate retires the coach mark AND reaches whatever was underneath
	it — including the very control the arrow is pointing at. That is driven in the
	spec by counting the activation, because a catcher that swallowed the tap looks
	identical from the outside.

	AT MOST ONE ON SCREEN. `presenter.presentCallout` is a driver over
	`src/present/toast_schedule.luau` (`src/present/callout_queue.luau`) — the
	shipped model that already owns priority ordering, the queue cap and the read
	floor priority may never truncate. A second request WAITS; it never stacks.

	IT CARRIES ITS OWN WAY OUT, on every input class. Tap-away answers the pointer
	and the finger; a keyboard or a pad reaches the plate's `Dismiss` button with
	one arrow press, and the ring goes back to where it was afterwards. A coach
	mark a pad player cannot retire would be a modal wearing an arrow.
]]

local contribution = require("../input/contribution")
local specGuard = require("../spec_guard")

local callout = {}

local PLATE_ID = "Plate"
local DISMISS_ID = "Dismiss"
local DUMP_SCHEMA = "luauui-callout-dump/1"

-- THEME METRICS, never bare pixels (ADR-0019 §2). The dismiss row is a real
-- target, so its floor is the theme's own minimum rather than a number written
-- here — the same `targetSizes.minimum` the segmented rail's floor rides.
local DISMISS_HEIGHT = table.freeze({ type = "minMax", min = "targetSizes.minimum" })
local PLATE_PADDING = "s"
local PLATE_GAP = "s"

local CALLOUT_KEYS = specGuard.keySet({
	"afterSessions",
	"align",
	"anchor",
	"content",
	"dismissLabel",
	"edge",
	"featureUsed",
	"id",
	"onHide",
	"onRetire",
	"onShow",
	"priority",
	"seen",
	"sessions",
	"tail",
})

export type Spec = {
	id: string?,
	anchor: any, -- Blueprint, required: the node the plate points at
	content: any, -- Blueprint, required: the plate's body
	dismissLabel: string?,
	edge: string?,
	align: string?,
	tail: boolean?,
	priority: number?,
	-- the CALLER'S state, read and never written (see the header)
	seen: any?, -- boolean | Readable<boolean>
	sessions: any?, -- number | Readable<number>
	afterSessions: number?,
	featureUsed: any?, -- boolean | Readable<boolean>
	-- required: the ONLY thing this construct reports back
	onRetire: (reason: string) -> (),
	onShow: (() -> ())?,
	onHide: ((reason: string) -> ())?,
}

--[[ THE PLATE ITSELF, exported so it has exactly ONE definition. The control
	mounts it through the queue, and the large-text matrix mounts it directly —
	which is the only way that sweep can see a surface that does not exist until
	something presents it. Two copies would drift, and the drift would show up at
	the text preference nobody swept (`menu_recipe.row` is the precedent). ]]
function callout.plate(UI: any, opts: { content: any, dismissLabel: string? }): any
	return UI.VStack({
		id = PLATE_ID,
		-- the panel treatment, so the plate is themed by the ACTIVE snapshot
		surface = "raised",
		padding = PLATE_PADDING,
		gap = PLATE_GAP,
		-- HUGS ITS OWN CONTENT: a short tip gets a short plate, and a ~1.4x
		-- localized one grows rather than clipping. The safe-box clamp is D1's, so
		-- there is no ceiling to restate here.
		width = { type = "hug" },
		children = {
			opts.content,
			UI.Button({
				id = DISMISS_ID,
				label = opts.dismissLabel or "Got it",
				width = { type = "fill", weight = 1 },
				height = DISMISS_HEIGHT,
			}),
		},
	})
end

local function readFact(fact: any): any
	if type(fact) == "table" and (fact :: any).get ~= nil then
		return (fact :: any):get()
	end
	return fact
end

function callout.build(LuauUI: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("newCallout", spec, CALLOUT_KEYS, "spec")
	local UI = LuauUI.UI
	local id = spec.id or "Callout"
	local scope = core:scope(`callout-{id}`)

	if type(spec.anchor) ~= "table" then
		error(
			`LuauUI newCallout('{id}'): \`anchor\` is the blueprint the plate points at — ANY node. The `
				.. "contribution rides it; its layout is untouched.",
			0
		)
	end
	if type(spec.content) ~= "table" then
		error(
			`LuauUI newCallout('{id}'): \`content\` is a BLUEPRINT, not a string. The reference plate is styled `
				.. "and holds more than one line, and a string-only tip could not express it.",
			0
		)
	end
	--[[ THE PERSISTENCE BOUNDARY, ENFORCED AT AUTHORING TIME. A callout with no
		way to report its retirement is a callout that comes back every session, and
		the author would find that out from a player. The framework will not write
		the fact for them, so it refuses to pretend the question does not exist. ]]
	if type(spec.onRetire) ~= "function" then
		error(
			`LuauUI newCallout('{id}'): \`onRetire(reason)\` is REQUIRED. LuauUI has no save layer and will `
				.. "not grow one: this construct reads your `seen`/`sessions`/`featureUsed` Readables and reports "
				.. "back exactly once when the tip should never be shown again. Persisting that is yours.",
			0
		)
	end

	-- ===== state ==========================================================
	local isShowing = scope:own(core:signal(false))
	local retired = scope:own(core:signal(false))
	local queued = scope:own(core:signal(false))
	local reported = false
	local anchorPath: string? = nil
	local presentCalloutFn: ((any) -> number)? = nil
	local releaseCalloutFn: ((number, string?) -> boolean)? = nil
	local entryId: number? = nil

	local api = {} :: any

	--[[ ELIGIBILITY — TipKit's actual contribution, and the only rules that are
		this construct's rather than the placement's:
		  * show once per player      (`seen`, the caller's record)
		  * or only after N sessions  (`sessions` + `afterSessions`)
		  * or only until the feature is used (`featureUsed`)
		Each is a READ of something the caller owns. Nothing here counts anything,
		remembers anything between sessions, or writes anything. ]]
	function api.eligible(): boolean
		if retired:get() then
			return false
		end
		if readFact(spec.seen) == true then
			return false
		end
		if readFact(spec.featureUsed) == true then
			return false
		end
		if spec.afterSessions ~= nil then
			local count = readFact(spec.sessions)
			if type(count) ~= "number" or count < spec.afterSessions then
				return false
			end
		end
		return true
	end

	local function retire(reason: string)
		if reported then
			return
		end
		reported = true
		retired:set(true)
		queued:set(false)
		isShowing:set(false)
		if entryId ~= nil and releaseCalloutFn ~= nil then
			local id2 = entryId
			entryId = nil
			releaseCalloutFn(id2, reason)
		end
		entryId = nil
		-- THE ONE REPORT. Quarantined, because a caller's save path throwing must
		-- not leave this control believing it is still on screen.
		pcall(spec.onRetire, reason)
	end

	--[[ BUILD THE PLATE WHEN THIS REQUEST'S TURN COMES, not when it is made: a
		queued callout whose anchor scrolled away or unmounted should be discovered
		at present time rather than mounted against a stale rect. The queue calls
		this and mounts what it returns. ]]
	local function buildPanel(): (any?, any?)
		if anchorPath == nil then
			return nil, nil
		end
		local panel = callout.plate(UI, { content = spec.content, dismissLabel = spec.dismissLabel })
		local attached = contribution.attach(panel, {
			handleActivate = function(path: string, _meta: any?): boolean
				if string.match(path, `/{PLATE_ID}/{DISMISS_ID}$`) == nil then
					return false
				end
				api.dismiss()
				return true
			end,
			--[[ THE NON-CONSUMING TAP-AWAY (brief §2 D3b). The catcher is
				`presenter.syncPopupCatcher`'s — the same one every other transient
				surface uses, never a second one — and `consume = false` is the
				framework's own word for "closing must not swallow unrelated clicks".

				WHAT IT DOES AND DOES NOT DO HERE, stated because a mutation of this
				line was run and did NOT bite, which is worth knowing rather than
				hiding. On the CATCHER path the two modes are currently
				indistinguishable by construction: `catchers.onPopupCatcherTap` reads
				`consume`, dismisses, and returns either way, because an empty-space
				tap pressed no rendered node and there is nothing to forward it to.
				The mode is load-bearing on the presenter's RENDERED-SIBLING path
				(`onNodeTap`), which iterates the contributions of the handle that owns
				the tapped node — and this contribution rides the CALLOUT's own
				surface, not the screen underneath, so a tap on the pointed-at control
				never reaches it at all.

				That is why the plate stays up when the `+` is pressed, and it is the
				reference behaviour rather than a gap: `r3-segmented-control.mov` keeps
				the coach mark on screen while the player works the controls beneath
				it. What retires it is the app noticing its feature was used. The
				declaration stays because it is the TRUE statement about this surface —
				it must never swallow a click it did not mean to — not because a test
				caught it. ]]
			outsideDismiss = {
				active = isShowing,
				dismiss = function()
					api.dismiss()
				end,
				consume = false,
			},
			handleCancel = function(_focusedPath: string?): boolean
				if not isShowing:get() then
					return false
				end
				api.dismiss()
				return true
			end,
		})
		return attached,
			{
				source = { path = anchorPath },
				edge = spec.edge or "bottom",
				align = spec.align or "center",
				-- A COACH MARK POINTS — and so, since the 2026-08-16 device review, does
				-- the player-pulled help plate. Both stems come from this one seam; what
				-- tells the two constructs apart is who raises them, never the arrow.
				tail = spec.tail ~= false,
			}
	end

	function api.present(): boolean
		if not api.eligible() or isShowing:get() or queued:get() then
			return false
		end
		if presentCalloutFn == nil or anchorPath == nil then
			return false -- no presenter, or not mounted yet: nothing to present onto
		end
		queued:set(true)
		entryId = presentCalloutFn({
			id = id,
			priority = spec.priority,
			build = buildPanel,
			onShow = function()
				queued:set(false)
				isShowing:set(true)
				if spec.onShow ~= nil then
					pcall(spec.onShow)
				end
			end,
			onHide = function(reason: string)
				isShowing:set(false)
				queued:set(false)
				if spec.onHide ~= nil then
					pcall(spec.onHide, reason)
				end
			end,
		})
		return true
	end

	--[[ THE PLAYER PUT IT AWAY. Invalidation is permanent BY CONTRACT rather than
		by state: `retire` reports once and `eligible()` refuses forever after, so a
		second `present()` in the same session cannot bring it back. What happens in
		the NEXT session is the caller's answer to the report. ]]
	function api.dismiss(reason: string?)
		retire(reason or "dismissed")
	end

	function api.invalidate(reason: string?)
		retire(reason or "invalidated")
	end

	--[[ A NEW SESSION (device review 2026-08-16, F2). Retirement is permanent
		WITHIN a session and that is not being weakened here: nothing inside this
		construct can un-retire itself, no `present()` can argue with the latch, and
		the app still owns the record. What this adds is the only thing that was
		missing — the caller's word that the session it persisted for is over.

		WHY IT HAS TO BE THE FRAMEWORK'S. The showcase's own reset had no way to say
		it, so it re-created the constructs instead, inside a keyed `ForEach` — and
		re-creating a callout re-creates the node it POINTS AT, whose path is its
		identity. Measured: after one reset the anchors moved from `[gen-1]/…` to
		`[gen-2]/…` and the focus-driven help plate, re-presented against a path that
		did not exist yet, was placed at the viewport origin on top of the button it
		belonged under. The right shape is a screen whose furniture never moves and
		coach marks that re-arm in place, which is TipKit's own model
		(`Tips.resetDatastore()`): the tips reset, the app does not.

		ORDER MATTERS AND IS THE CALLER'S: clear the persisted facts FIRST. `seen`
		and `featureUsed` are READ, never written, so a rearm with `seen` still true
		leaves the callout ineligible — honestly, and without a second latch to
		explain. A showing or queued plate is released on the way, because a fresh
		session cannot start with the last one still on the glass. ]]
	function api.rearm()
		if entryId ~= nil and releaseCalloutFn ~= nil then
			local id2 = entryId
			entryId = nil
			releaseCalloutFn(id2, "rearmed")
		end
		entryId = nil
		reported = false
		retired:set(false)
		queued:set(false)
		isShowing:set(false)
	end

	function api.state(): string
		if retired:get() then
			return "retired"
		elseif isShowing:get() then
			return "showing"
		elseif queued:get() then
			return "queued"
		end
		return "waiting"
	end

	api.isShowing = isShowing
	api.retired = retired

	--[[ THE FEATURE BEING USED IS AN INVALIDATION, WHEREVER IT HAPPENS. Observed
		rather than polled, so a callout dies on the frame the player does the thing
		it was pointing at — including while it is on screen, which is the case that
		would otherwise leave a tip explaining something already done. `seen` is
		observed for the same reason and never written. ]]
	if spec.featureUsed ~= nil and type(spec.featureUsed) == "table" then
		scope:own(core:observe(spec.featureUsed, function(used: any)
			if used == true then
				retire("featureUsed")
			end
		end))
	end
	if spec.seen ~= nil and type(spec.seen) == "table" then
		scope:own(core:observe(spec.seen, function(value: any)
			if value == true then
				retire("seen")
			end
		end))
	end
	-- a callout the caller has already ruled out never enters the queue at all,
	-- and reports nothing: there is nothing new to persist about it
	if readFact(spec.seen) == true or readFact(spec.featureUsed) == true then
		reported = true
		retired:set(true)
	end

	--[[ THE RETURNED BLUEPRINT IS THE CALLER'S OWN ANCHOR NODE carrying an input
		contribution — no wrapper, no layout change, the shape `newMenu` established.
		`syncGeometry` is how the control learns its own mounted path, because the
		caller's tree decides it. ]]
	local blueprint = contribution.attach(spec.anchor, {
		syncGeometry = function(_rectOf: (string) -> any, rootNode: any?)
			if rootNode ~= nil and anchorPath == nil then
				anchorPath = rootNode.path
			end
		end,
		bindPresent = function(_presentModal: any, _dismiss: any, _presentAnchored: any, present: any, release: any)
			presentCalloutFn = present
			releaseCalloutFn = release
		end,
	})

	local function dump()
		local state = api.state()
		return {
			schema = DUMP_SCHEMA,
			id = id,
			state = state,
			eligible = api.eligible(),
			showing = isShowing:get(),
			retired = retired:get(),
			reported = reported,
			priority = spec.priority or 0,
			edge = spec.edge or "bottom",
			align = spec.align or "center",
			tail = spec.tail ~= false,
			anchorPath = anchorPath,
			afterSessions = spec.afterSessions,
			sessions = readFact(spec.sessions),
			seen = readFact(spec.seen) == true,
			featureUsed = readFact(spec.featureUsed) == true,
			text = `callout '{id}': {state}` .. (if state == "retired"
				then " (reported to the caller, never shown again)"
				else "") .. `, anchored {spec.edge or "bottom"}/{spec.align or "center"} of {tostring(anchorPath)}`,
		}
	end

	return {
		blueprint = blueprint,
		api = api,
		dump = dump,
		dispose = function()
			if entryId ~= nil and releaseCalloutFn ~= nil then
				local id2 = entryId
				entryId = nil
				releaseCalloutFn(id2, "manual")
			end
			scope:dispose()
		end,
	}
end

return callout
