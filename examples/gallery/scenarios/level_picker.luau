--!strict
--[[ Scenario 'level_picker' — ONE VALUE, `count` SEGMENTS, AND THE ± THAT IS
	NOT PART OF IT (director ruling 2026-08-16).

	THE REPRODUCTION. The reference screenshot is two level pickers stacked: a
	row of ten tall thin bars with the first two filled, flanked by a big round −
	and +, labelled "Balanced"; and under it three wide blocks with NOTHING
	filled and a + beside them, labelled "Fidelity". Both are `segment = "bar"`,
	which needs no assets at all — the same declaration paints ten thin bars and
	three wide blocks, because the marks divide whatever width they are given.
	Zero is a real state, which is what the second picker is showing.

	AND THE ± IS A SEPARATE CONTROL, WHICH IS THE POINT. It looks like part of
	the picker and it must not be: `newLevelPicker` takes ONE focus stop for one
	number, and building ± in would put two more inside it (the paint, input and
	semantics argument in `src/controls/rating.luau`'s header, which is why this
	control exists in this shape). So each row here is a `newLevelPicker` and a
	`newStepper` SHARING ONE SIGNAL — the standard composition rule for the pair:
	"A stepper sits next to a field that displays its current value, because the
	stepper itself doesn't display a value." Press the stepper and the bars move;
	drag the bars and the stepper's readout moves. Neither knows about the other.

	The pair sits in a WRAPPING row rather than a pinned one, because this
	framework's stepper is a compact unit rather than two free-floating circles:
	side by side where there is room, stacked where there is not, on the same
	declaration.

	THE OTHER TWO SEGMENTS are here so a device pass can reach all three without
	a second fixture. `glyph` is what `newRating` is (this one uses its own pair,
	to show that the glyphs are the caller's); `image` is two of this
	repository's own uploaded icons, because the control never names an asset —
	if you want art, you hand it art.

	THE TINT ROW is the last section: the same ten-segment picker with both
	halves overridden. Both defaults are theme ROLES, so swapping the package
	retints every picker above it; the overrides are `direct` hues and hold still
	while the rest of the screen moves, which is the visible difference between
	a themable tint and a theming-exempt one.

	TWO HOSTS MOUNT THIS FILE and only one runs steps: the scenario runner drives
	`steps` by name, and the showcase demo picker mounts it with a minimal ctx and
	no step ever runs. Every control is an ordinary control with its own value, so
	a player can drive the whole thing by hand. ]]

--[[ EVERY PLAYER-VISIBLE STRING, in one table and EXPORTED as `copy` — the
	contract `surface_overlap.luau` and `flow_wrap.luau` carry, because the
	gallery spec's localization case re-runs the fixture through a ~1.4x
	pseudo-localizing expansion and a check that cannot reach the strings cannot
	make that claim. Flat keys only. ]]
local COPY = {
	title = "Level pickers",
	intro = "A run of discrete segments that reads as one value. The plus and minus beside each one are a separate stepper sharing the same signal — not part of the picker.",
	balanced = "Balanced",
	fidelity = "Fidelity",
	difficulty = "Difficulty",
	trophies = "Trophies",
	tinted = "Tinted",
	balancedHint = "Ten bars, two filled. Drag across them, or step.",
	fidelityHint = "Three blocks, none filled: zero is a real state.",
	difficultyHint = "The same control with glyph segments, and the pair is the caller's.",
	trophiesHint = "Image segments: the control never names an asset, so you hand it two.",
	tintedHint = "Both halves overridden with fixed hues, so a theme swap moves everything above and not this.",
	readoutTitle = "What every picker reports",
	note = "One focus stop each: put the ring on a strip and press Left or Right, or the bumpers. At the end of the run the arrow goes back to navigation.",
}

local GLYPHS = { filled = "◆", empty = "◇" }
-- two of THIS repository's own uploaded icons (examples/themes/pixel_quest),
-- borrowed here only so the image segment has something to draw: a level picker
-- never names an asset, which is exactly what this row is showing.
local IMAGES = { filled = "rbxassetid://93821473650946", empty = "rbxassetid://76283014616825" }

return {
	title = "Level pickers",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI = Facet.UI
		local core = ctx.core
		local scope = core:scope("level-picker-scenario")

		local balanced = scope:own(core:signal(2))
		local fidelity = scope:own(core:signal(0))
		local difficulty = scope:own(core:signal(3))
		local trophies = scope:own(core:signal(1))
		local tinted = scope:own(core:signal(6))

		local controls: { any } = {}
		local function keep(control: any): any
			table.insert(controls, control)
			return control
		end

		--[[ ONE ROW = ONE PICKER + ONE STEPPER OVER ONE SIGNAL. The stepper's
			bounds are the picker's: `min` is 0 when zero is allowed and `max` is the
			count, so the two controls cannot disagree about what the value may be.
			Neither is told about the other — they both just read and write the
			signal, which is the whole claim this fixture exists to make. ]]
		local function row(id: string, label: string, hint: string, value: any, spec: any): any
			-- EVERY picker gets the live environment, which is not boilerplate: the
			-- gap between marks is derived from the theme's own icon ladder and
			-- WIDENS under touch, so a phone respaces these runs live on a hot
			-- switch. Without `env` they would all take the pointer spacing and the
			-- one thing this fixture exists to be looked at on would be missing.
			spec.env = ctx.env
			local picker = keep(Facet.Controls.LevelPicker(core, spec))
			local stepper = keep(Facet.Controls.Stepper(core, {
				id = `{id}Step`,
				value = value,
				min = if spec.allowZero == false then 1 else 0,
				max = spec.count,
			}))
			return UI.VStack({
				id = id,
				surface = "control",
				padding = "s",
				gap = 6,
				width = { type = "fill", weight = 1 },
				children = {
					UI.Text({ id = "Label", text = label, textSize = "caption" }),
					UI.Text({ id = "Hint", text = hint, textSize = "caption", role = "secondary" }),
					--[[ THE STRIP TAKES THE LEFTOVER, and that is the whole layout.
						The stepper is content-sized (two 44px targets and a readout
						whose width is a theme metric), the picker is `fill`, so the
						row IS the reference picture at every width: the ± stays put
						and the run of bars grows and shrinks against it.

						NOT `wrap = true`, and the solver said why rather than my
						guessing — the first cut wrapped, and the sweep filed the same
						finding on all five rows at every viewport: a `fill` child on a
						wrapping stack's MAIN axis takes a whole line to itself, so the
						wrap could never do anything except cost a line
						(docs/lessons/the-solver-already-told-you.md). ]]
					UI.HStack({
						id = "Pair",
						-- THEME-OPT-OUT: this row is pinned between a `fill` picker and a stepper that
						-- is content-sized from two 44px targets and a theme-metric readout, and the
						-- comment above records why it may not wrap. There is no slack for a step that
						-- grows: measured, `gap = "s"` puts all five rows 2px past their box on a
						-- 320x640 phone at +14 under glossy-touch.
						gap = 8,
						align = "center",
						width = { type = "fill", weight = 1 },
						children = { picker.blueprint, stepper.blueprint },
					}),
				},
			})
		end

		local rows = {
			row("Balanced", COPY.balanced, COPY.balancedHint, balanced, {
				id = "BalancedBars",
				value = balanced,
				count = 10,
				segment = "bar",
			}),
			row("Fidelity", COPY.fidelity, COPY.fidelityHint, fidelity, {
				id = "FidelityBars",
				value = fidelity,
				count = 3,
				segment = "bar",
			}),
			row("Difficulty", COPY.difficulty, COPY.difficultyHint, difficulty, {
				id = "DifficultyGlyphs",
				value = difficulty,
				count = 5,
				segment = "glyph",
				glyphs = GLYPHS,
			}),
			row("Trophies", COPY.trophies, COPY.trophiesHint, trophies, {
				id = "TrophyIcons",
				value = trophies,
				count = 3,
				segment = "image",
				images = IMAGES,
			}),
			row("Tinted", COPY.tinted, COPY.tintedHint, tinted, {
				id = "TintedBars",
				value = tinted,
				count = 10,
				segment = "bar",
				tint = { filled = { direct = "#7ad4a0" }, empty = { direct = "#2a3340" } },
			}),
		}

		-- THE READOUT IS `semanticText`, not the raw numbers, and that is the
		-- deliberate choice: a strip of ten rectangles says nothing to a non-visual
		-- consumer, so the one string the control publishes for them is the one
		-- printed here where a human can check it says the right thing.
		local readout = scope:own(core:memo(function(use)
			return `{COPY.balanced}: {use(balanced)} of 10  ·  {COPY.fidelity}: {use(fidelity)} of 3  ·  `
				.. `{COPY.difficulty}: {use(difficulty)} of 5  ·  {COPY.trophies}: {use(trophies)} of 3  ·  `
				.. `{COPY.tinted}: {use(tinted)} of 10`
		end))

		local page: { any } = {
			UI.Text({ id = "Title", text = COPY.title, textSize = "control" }),
			UI.Text({ id = "Intro", text = COPY.intro, textSize = "caption", role = "secondary" }),
		}
		for _, node in rows do
			table.insert(page, node)
		end
		table.insert(
			page,
			UI.VStack({
				id = "Readout",
				surface = "control",
				padding = "s",
				gap = "xs",
				width = { type = "fill", weight = 1 },
				children = {
					UI.Text({ id = "ReadoutTitle", text = COPY.readoutTitle, textSize = "caption" }),
					UI.Text({ id = "ReadoutBody", text = readout, textSize = "caption", role = "secondary" }),
				},
			})
		)
		table.insert(page, UI.Text({ id = "Note", text = COPY.note, textSize = "caption", role = "secondary" }))

		local screen = UI.Screen({
			id = "LevelPickerDemo",
			padding = 12,
			gap = "s",
			children = {
				UI.ScrollView({
					id = "Page",
					axis = "y",
					gap = "s",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = page,
				}),
			},
		})

		return {
			screen = screen,
			present = {},
			balanced = balanced,
			fidelity = fidelity,

			steps = {
				-- the two ends of the run, driven through the SIGNAL the stepper and
				-- the picker share, so a step proves the sharing rather than one
				-- control's own arithmetic
				zero = function()
					balanced:set(0)
					return { balanced = balanced:get() }
				end,
				full = function()
					balanced:set(10)
					return { balanced = balanced:get() }
				end,
				reference = function()
					balanced:set(2)
					fidelity:set(0)
					return { balanced = balanced:get(), fidelity = fidelity:get() }
				end,
				reread = function()
					local out: { any } = {}
					for _, control in controls do
						if control.dump ~= nil then
							table.insert(out, control.dump())
						end
					end
					return { dumps = out }
				end,
			},

			report = function()
				local dumps: { any } = {}
				local notes: { string } = {}
				for _, control in controls do
					if control.dump ~= nil then
						table.insert(dumps, control.dump())
					end
					if control.diagnostics ~= nil then
						for _, note in control.diagnostics() do
							table.insert(notes, note)
						end
					end
				end
				return {
					dumps = dumps,
					diagnostics = notes,
					values = {
						balanced = balanced:get(),
						fidelity = fidelity:get(),
						difficulty = difficulty:get(),
						trophies = trophies:get(),
						tinted = tinted:get(),
					},
				}
			end,

			dispose = function()
				for _, control in controls do
					control.dispose()
				end
				scope:dispose()
			end,
		}
	end,
}
