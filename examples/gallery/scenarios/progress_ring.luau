--!strict
-- Scenario 'progress_ring' (parity round 3, item D2): the CIRCULAR
-- progress indicator, BOTH forms, on the one surface where a player can see the
-- difference between them.
--
--   * DETERMINATE — `presentation = "circular"` with a value. A ring that fills
--     to the value, over the unfilled capacity ring, exactly as the
--     a capacity gauge is documented ("a closed ring that's
--     partially filled in"). Drive it with the steps; the arc is `arc(0, 360 * f)`.
--   * INDETERMINATE — the same shape with no value: a fixed-sweep head whose
--     START ANGLE advances with the phase, so the ring rotates without any
--     rotation channel existing. There is no native radial primitive in the
--     engine; both forms are `UI.Path` + `Facet.pathShapes.arc`.
--   * ...and the five-dot SPINNER beside it, unchanged, because it is the
--     fallback if the arc's per-frame paint ever fails on a device, and a
--     fixture that dropped it would delete the comparison a device pass needs.
--
-- Both indeterminate views share the surface's own motion clock and this
-- scenario's scope, so the cycles retire with the fixture (the `scope` an
-- indeterminate ProgressView requires). Under reduced motion they keep advancing
-- on the quantized 250 ms tick rather than freezing — a frozen spinner and a hung
-- process look identical.
--
-- The column is hosted in a `fill` ScrollView for the reason `path_ring`'s is:
-- a short landscape phone has less vertical room than this page has content, and
-- the shipped precedent is to make it reachable rather than clip it off.
--
-- ...AND THAT SCROLLER IS THIS SURFACE'S ONE KNOWN LIVE EXPOSURE, stated here
-- rather than left for somebody to find on a phone. `ClipsDescendants` does not
-- crop a `Path2D` — measured in Studio 2026-08-14 (canary D2a), and there is no
-- property on the class by which it could — so when a ring scrolls out of this
-- page's window the ARC keeps painting while every ordinary GuiObject beside it
-- is cropped. Nothing in this repository can see that: the solver's geometry and
-- the engine's own `GetBoundingRect` both honestly report the ring in-box, which
-- is exactly why it is written down. It is not a function of the theme's ring
-- size (progress_view's header has the arithmetic that closes the size-dependent
-- half); it is a property of the primitive, and the alternative — a page that
-- clips its own content off a short phone — is worse.

-- EVERY PLAYER-VISIBLE STRING, in one table and exported, so the localization
-- case in tests/examples_gallery.spec.luau can expand all of them ~1.4x. All of
-- it is `policy = "none"` copy: it must fit and wrap, never clip.
local COPY = {
	title = "Circular progress — both forms",
	caption = "One arc on UI.Path: the value moves the sweep, the phase moves the head.",
	determinate = "Downloading",
	indeterminate = "Working",
	spinner = "Spinner (dots)",
}

return {
	title = "Circular progress indicator (round 3 D2)",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI = Facet.UI
		local core = ctx.core
		local pres = ctx.presenter
		local scope = core:scope("progress-ring")
		local clock = pres.motionClock

		local progress = scope:own(core:signal(0.25))

		local ring = Facet.Controls.ProgressView(core, {
			id = "Ring",
			label = COPY.determinate,
			value = progress,
			presentation = "circular",
		})
		-- NO `showValue` HERE, and it would be refused if it were asked for: the
		-- readout usually centred inside a ring belongs to a gauge, not a progress view, and
		-- this indicator is theme-sized and small. The percentage lives beside it
		-- as its own `UI.Text`, which is exactly what the refusal tells an author
		-- to do.
		local readout = scope:own(core:memo(function(use)
			return string.format("%d%%", use(progress) * 100 + 0.5)
		end))

		local busy = Facet.Controls.ProgressView(core, {
			id = "Busy",
			label = COPY.indeterminate,
			presentation = "circular",
			motionClock = clock,
			scope = scope,
		})
		local dots = Facet.Controls.ProgressView(core, {
			id = "Dots",
			label = COPY.spinner,
			presentation = "spinner",
			motionClock = clock,
			scope = scope,
		})

		local screen = UI.Screen({
			id = "ProgressRing",
			padding = 16,
			children = {
				UI.ScrollView({
					id = "Page",
					axis = "y",
					gap = 8,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.Text({ id = "Title", text = COPY.title, textSize = "heading" }),
						UI.Text({ id = "Caption", text = COPY.caption, textSize = "caption", role = "secondary" }),
						ring.blueprint,
						UI.Text({ id = "Readout", text = readout, textSize = "label" }),
						busy.blueprint,
						dots.blueprint,
					},
				}),
			},
		})

		local function setProgress(value: number)
			progress:set(math.clamp(value, 0, 1))
			return { progress = progress:get(), fraction = ring.dump().fraction }
		end

		return {
			screen = screen,
			present = {},
			steps = {
				setProgress10 = function()
					return setProgress(0.10)
				end,
				setProgress65 = function()
					return setProgress(0.65)
				end,
				setProgress100 = function()
					return setProgress(1.0)
				end,
				-- step the presenter's own clock so a Studio driver can watch the
				-- head travel rather than only sample its endpoints
				advance = function(_built: any, payload: string?)
					local frames = tonumber(payload or "") or 30
					for _ = 1, math.clamp(math.floor(frames), 1, 600) do
						pres.tick(1 / 60)
					end
					return { phase = busy.dump().phase, reduced = clock:isReduced() }
				end,
			},
			report = function()
				return {
					progress = progress:get(),
					fraction = ring.dump().fraction,
					busyPhase = busy.dump().phase,
					busyAnimating = busy.dump().animating,
					dotsPhase = dots.dump().phase,
					reduced = clock:isReduced(),
				}
			end,
			dispose = function()
				ring.dispose()
				busy.dispose()
				dots.dispose()
				scope:dispose()
			end,
		}
	end,
}
