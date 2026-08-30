--!strict
--[[ Scenario 'flow_wrap' — THE ROW THAT RUNS OUT OF ROOM, and what it does then.

	`wrap` shipped in parity round 3 item A: Roblox's
	`UIListLayout.Wraps`, which Facet had no spelling for at all. The standing
	obligation is that every new public API appears in a gallery scenario the
	headless suite executes, and this is that scenario.

	WHAT A STILL SCREENSHOT CANNOT SHOW, and therefore what this fixture is FOR:

	  · THE TOGGLE IS THE WHOLE ARGUMENT. One switch turns wrapping off, and the
	    same fourteen tags immediately run off the right edge of their own box —
	    with `controller.diagnostics()` saying so in the status line, live. That
	    comparison is the feature; a screenshot of the wrapped state alone looks
	    like an ordinary row of chips.
	  · IT IS A PROP, SO THE FLIP IS A RE-SOLVE. `wrap` is bound to a Signal, so
	    the toggle re-arranges the SAME nodes. A separate `UI.FlowStack` class
	    behind a `UI.When` would have destroyed and rebuilt all fourteen tags on
	    every flip — the exact remount `AdaptiveStack` exists to prevent, and the
	    reason `wrap` is a prop rather than a class.
	  · WHERE THE BLOCK OF LINES SITS is a fact nobody could look up: the engine
	    does not document it, so it was PROBED live in Studio on 2026-08-13. The
	    lower panel is that probe as a surface — a fixed-height box with slack
	    around its lines and a Start/Center/End picker driving the container's
	    ordinary `align`. There is no new alignment word to demonstrate, which is
	    itself the thing being demonstrated.

	NOTHING HERE IS FIXED AGAINST AN UNFIXED VIEWPORT. `AlignBox` (below) used to
	be the one exception — a literal `360` PX, reasoned by hand from a nine-
	package sweep and then frozen — and framework-gaps-phase2 gap 3 is what
	removed it: `height = { type = "content", rows = 10, of =
	"controlSizes.compact.height" }` reproduces that same 360px margin AT
	NEUTRAL (`10 * 36`), but as a THEME-METRIC FORMULA rather than a frozen
	number, so it now grows at the ten-foot ladder the way the chips it holds
	do (`ALIGN_BOX_ROWS` below explains the row count). The tag cloud above it
	still declares no height at all — it is exactly as tall as its lines, at
	every viewport.

	TWO HOSTS MOUNT THIS FILE, AND ONLY ONE OF THEM RUNS STEPS (the same pair
	`card_rail.luau` documents): the scenario runner drives `steps` by name, and
	the showcase demo picker mounts it with a minimal ctx and NO step ever runs.
	Everything a player can do here — the toggle, the picker — is therefore an
	ordinary control with an `onActivate`/`selected` of its own, never a scripted
	drive.
]]

-- The lower panel's box. It exists to have SLACK: `align` can only be seen when
-- the lines do not fill their container.
--
-- THIS NUMBER WAS MEASURED, NOT GUESSED (a px height fixed against unfixed
-- content is a defect class). Its history, kept because the
-- reasoning is still the margin: 200 was reasoned from Studio Neutral's
-- ~36px chip, then the nine-package sweep in `tests/flow_wrap.spec.luau`
-- found four packages overflowing it on the cross axis at 320px wide
-- (glossy_touch by 33, fantasy_parchment by 33, fantasy_ornate by 49,
-- pixel_quest by 88 — their control faces are taller than Neutral's, so the
-- same four tags take more lines and each line is taller), and 360 —
-- `200 + 88` plus a line of headroom — is what survived that sweep.
--
-- CONTENT-TERMS, 2026-08-23 (framework-gaps-phase2 gap 3): that 360 is now
-- `ALIGN_BOX_ROWS` rows of `controlSizes.compact.height`, not a frozen
-- literal — `10 * 36 = 360` reproduces the identical margin AT NEUTRAL,
-- value-for-value, but as a FORMULA over a theme metric rather than a number
-- nobody re-derives. Ten rows for four short-tag lines reads oddly next to
-- each other, and that is the honest shape of the number it replaces: the
-- margin was ALWAYS bigger than "how many lines the content needs" — it is
-- "how many lines the WORST SHIPPED PACKAGE's chips need, plus headroom" —
-- and a formula that reproduces a margin exactly reproduces its shape too.
-- What DOES change: `controlSizes.compact.height` is a THEME METRIC, so
-- under the ten-foot ladder (`metricScale`) this box now grows
-- with it — 36 -> 54 at Large, box -> 540 — where the frozen 360 never did.
-- The cross-package worst-case margin the sweep measures (still 82px short
-- under four packages per `tests/lib/theme_sweep_ledger.luau`'s own waiver)
-- is UNCHANGED by this migration: `compact.height` does not track a
-- package's actual chip content any more precisely than the old literal did
-- — that is a different, already-ledgered gap, not this one's to close.
local ALIGN_BOX_ROWS = 10

-- The tag cloud's own spacing. ONE number, because a wrapping stack spaces its
-- items and its lines with the same `gap` — exactly as `UIListLayout` has one
-- `Padding` for both. It is a literal rather than a spacing token because the
-- header's arithmetic above has to be checkable by reading this file.
local TAG_GAP = 6

--[[ EVERY PLAYER-VISIBLE STRING ON THIS SURFACE, in one table, EXPORTED as the
	module's `copy` field — the same contract `card_rail.luau` and
	`with_animation.luau` carry, and for the same reason: the localization case in
	`tests/examples_gallery.spec.luau` re-runs the whole fixture with all of them
	put through a ~1.4x pseudo-localizing expansion, and a check that cannot reach
	the strings cannot make that claim.

	THE TAGS ARE IN HERE TOO, and that is not an oversight. They are the content
	being wrapped: a pseudo-localized tag is a WIDER tag, which is precisely the
	case a wrapping row has to survive — fewer per line, more lines, and nothing
	clipped. Everything here is `policy = "none"` text (§15.3): it must fit,
	wrapping where it has to, and never clip.

	...AND THEY ARE FLAT KEYS, `tag1`..`tag14`, rather than an array. The
	pseudo-localizer walks `copy` and expands every VALUE; handed a nested table it
	would throw, and handed a table it skipped it would leave the fixture's real
	content in English while claiming to have localized the surface. Flat keys are
	the shape that cannot do either. `TAG_COUNT`/`SHORT_COUNT` below are how the
	fixture and its tests iterate them without re-listing them. ]]
local TAG_COUNT = 14
local SHORT_COUNT = 4
local COPY = {
	title = "wrap — the row that runs out of room",
	wrapLabel = "Wrap the tags",
	cloudCaption = "Fourteen tags in one HStack. Turn wrapping off and watch them leave the box.",
	alignCaption = "Where the BLOCK of lines sits — the container's ordinary `align`, no new word.",
	alignLabel = "Block",
	alignStart = "Start",
	alignCenter = "Center",
	alignEnd = "End",
	fitting = "Fitting: the solver reports nothing.",
	overflowing = "Overflowing: the solver is reporting it, live.",
	tag1 = "Rally",
	tag2 = "Drift",
	tag3 = "Circuit",
	tag4 = "Sprint",
	tag5 = "Endurance",
	tag6 = "Time attack",
	tag7 = "Hill climb",
	tag8 = "Rallycross",
	tag9 = "Autocross",
	tag10 = "Gymkhana",
	tag11 = "Touge",
	tag12 = "Karting",
	tag13 = "Formula",
	tag14 = "Off-road",
	short1 = "One",
	short2 = "Two",
	short3 = "Three",
	short4 = "Four",
}

return {
	title = "Flow wrap (UI.HStack wrap = true)",
	ledgerRows = {},
	copy = COPY,
	-- how many of each the fixture builds, so a test iterates them without
	-- re-listing the labels (and cannot drift from the fixture by one)
	tagCount = TAG_COUNT,
	shortCount = SHORT_COUNT,
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI = Facet.UI
		local core = ctx.core
		local scope = core:scope("flow-wrap")

		local wrapping = scope:own(core:signal(true))
		local blockAlign = scope:own(core:signal("start"))

		-- THE STATUS LINE IS A CLAIM ABOUT THE SOLVER, and it is derived from the
		-- one fact that decides it rather than from a diagnostics read a scenario
		-- has no controller for. Fourteen tags cannot fit one line at any supported
		-- viewport, so `wrap = false` here IS the overflowing state — and
		-- `tests/flow_wrap.spec.luau` asserts the solver agrees, in both directions,
		-- so this sentence cannot quietly become false.
		local status = scope:own(core:memo(function(use)
			return if use(wrapping) then COPY.fitting else COPY.overflowing
		end))

		local alignPicker = Facet.Controls.Picker(core, {
			id = "BlockAlign",
			label = COPY.alignLabel,
			-- SEGMENTED, declared: three peers, and the whole point is that they are
			-- the SAME three words `align` has always taken on a stack
			presentation = "segmented",
			options = {
				{ value = "start", label = COPY.alignStart },
				{ value = "center", label = COPY.alignCenter },
				{ value = "end", label = COPY.alignEnd },
			},
			selected = blockAlign,
		})

		-- A TAG IS A BUTTON, and a Button's own label is already measured and drawn
		-- on ONE line when it is a single word (`isSingleWord`, `renderer.luau`) —
		-- which is what a tag in a wrapping row needs: the ROW wraps, and a tag that
		-- re-flowed internally would change its own main extent between the measure
		-- that broke the lines and the paint. The two-word tags here ("Time attack",
		-- "Hill climb") deliberately keep the wrapping reading, so the pseudo-
		-- localized run proves a tag that grows still fits its own plate.
		local function tag(id: string, label: string): any
			return UI.Button({ id = id, label = label, surface = "chip" })
		end

		local cloudTags = {}
		for i = 1, TAG_COUNT do
			table.insert(cloudTags, tag(`T{i}`, (COPY :: any)[`tag{i}`]))
		end
		local shortTags = {}
		for i = 1, SHORT_COUNT do
			table.insert(shortTags, tag(`S{i}`, (COPY :: any)[`short{i}`]))
		end

		local screen = UI.Screen({
			id = "FlowWrap",
			padding = 12,
			gap = "s",
			children = {
				-- THE PAGE SCROLLS, for the reason every other fixture here does: a
				-- title, a toggle, two panels and a picker do not fit the ~200px a
				-- 640x320 landscape phone has left once the showcase reserves its chip
				-- strip, and content that overflows with nothing to scroll it is this
				-- repo's named recurring defect.
				UI.ScrollView({
					id = "Page",
					axis = "y",
					gap = "s",
					width = UI.fill(),
					height = UI.fill(),
					children = {
						UI.Text({ id = "Title", text = COPY.title, textSize = "control" }),
						UI.Toggle({ id = "WrapToggle", label = COPY.wrapLabel, value = wrapping }),
						UI.Text({ id = "Status", text = status, textSize = "caption", role = "secondary" }),
						UI.Text({
							id = "CloudCaption",
							text = COPY.cloudCaption,
							textSize = "caption",
							role = "secondary",
						}),
						-- THE FIXTURE ITSELF. No height: it is exactly as tall as its
						-- own lines, at every viewport, which is what makes the tag
						-- count safe on a 320px phone.
						UI.HStack({
							id = "Cloud",
							wrap = wrapping,
							gap = TAG_GAP,
							width = UI.fill(),
							children = cloudTags,
						}),
						UI.Text({
							id = "AlignCaption",
							text = COPY.alignCaption,
							textSize = "caption",
							role = "secondary",
						}),
						alignPicker.blueprint,
						-- ...and the probe, as a surface. `surface = "control"` so the
						-- box the block is aligned INSIDE is visible; without it the
						-- picker would appear to move the tags for no reason.
						UI.HStack({
							id = "AlignBox",
							wrap = true,
							align = blockAlign,
							gap = TAG_GAP,
							surface = "control",
							padding = "s",
							width = UI.fill(),
							height = { type = "content", rows = ALIGN_BOX_ROWS, of = "controlSizes.compact.height" },
							children = shortTags,
						}),
					},
				}),
			},
		})

		return {
			screen = screen,
			present = {},
			-- published for the headless suite: the signals a test drives, rather
			-- than a re-implementation of them
			wrapping = wrapping,
			blockAlign = blockAlign,

			steps = {
				-- the toggle, as the player's own press fires it
				setWrap = function(_built: any, payload: string?)
					wrapping:set(payload ~= "off")
					return { wrap = wrapping:get() }
				end,
				setAlign = function(_built: any, payload: string?)
					local value = if payload == "center" or payload == "end" then payload else "start"
					blockAlign:set(value)
					return { align = value }
				end,
			},

			report = function()
				return {
					wrap = wrapping:get(),
					align = blockAlign:get(),
					tags = TAG_COUNT,
				}
			end,

			dispose = function()
				alignPicker.dispose()
				scope:dispose()
			end,
		}
	end,
}
