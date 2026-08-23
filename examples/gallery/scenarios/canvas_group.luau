--!strict
--[[ Scenario 'canvas_group' — ONE FADE, OR THREE (ADR-0026, ADR-0029).

	`canvasGroup` and its reactive twin `opacity` are the framework's fade group:
	the node is materialized as an engine `CanvasGroup`, so its whole subtree is
	composited ONCE and then faded as a single image
	(`CanvasGroup.GroupTransparency` — the one alpha property no style rule owns).

	WHAT THIS FIXTURE IS FOR, and why a picker entry rather than a paragraph in
	api.md. Both panels below hold the SAME three overlapping plates and are
	handed the SAME opacity value, and at 100% they are identical. Move the value
	down and they stop being identical, because the two declarations mean
	different things:

	  · ONE GROUP. `UI.ZStack{ opacity = f }` — the three plates are painted into
	    one buffer first, so the small plate stays solid ON TOP of the big one and
	    the whole picture fades. The overlaps never appear.
	  · THREE GROUPS. The same fade written on each plate — which is what an
	    author reaches for first — fades each one against WHAT IS BEHIND IT, so
	    every overlap composes twice and the plates dissolve into each other.
	    ADR-0026: an authored opacity MULTIPLIES with the fade under it.

	This is the one demonstration in this catalogue that a still screenshot CAN
	hold — which is the point. The difference is a picture, and until now no
	surface a player can select painted it.

	AND THE OTHER HALF OF THE PROP: `canvasGroup = true` with NO opacity beside
	it. A fading transition needs the node arriving or leaving to BE a group
	already (`blueprint_schema`: "Fading forms need the child to be a declared
	canvasGroup node"), so the third panel declares the group and never writes an
	opacity — the `enter = "fade"` transition writes it.

	...AND THE REFUSAL, VERBATIM. `opacity` lives on `Box` and `ZStack` and
	nowhere else, and every other class answers a reach for it by NAME rather than
	through the unknown-property path (ADR-0029). The sentence on screen is
	captured at BUILD from a real refused construction — the framework's own
	words, not a paraphrase this file could let go stale.

	NOTHING HERE IS FIXED AGAINST AN UNFIXED VIEWPORT: the plates are fixed px
	inside a page that scrolls, the two panels sit in an `AdaptiveStack` that
	becomes a column on a narrow phone, and no panel declares a height.

	TWO HOSTS MOUNT THIS FILE and only one runs steps (the pair
	`branch_scope.luau` documents): the scenario runner drives `steps` by name,
	and the showcase demo picker mounts it with a minimal ctx and no step ever
	runs. Every control here is an ordinary button, so a player drives all of it.
]]

-- The four stops the chips offer. 1 is the resting state (the two panels must be
-- indistinguishable there, which is what makes the difference below it legible);
-- 0.15 is low enough that a doubled overlap is unmistakable and high enough that
-- the plates are still on screen.
local STOPS = { 1, 0.7, 0.4, 0.15 }

-- Three concentric plates. Concentric rather than scattered because EVERY pixel
-- of the two smaller ones then sits over another plate, so the composed-twice
-- region is the whole of them rather than a corner somebody has to hunt for.
local PLATES = {
	{ id = "Back", px = 132, role = "accent" },
	{ id = "Mid", px = 92, role = "danger" },
	{ id = "Front", px = 52, role = "content" },
}

--[[ EVERY PLAYER-VISIBLE STRING, in one table and EXPORTED as `copy` — the same
	contract `branch_scope.luau` and `flow_wrap.luau` carry, because the
	localization case in `tests/examples_gallery.spec.luau` re-runs the whole
	fixture through a ~1.4x pseudo-localizing expansion and a check that cannot
	reach the strings cannot make that claim. Flat keys only. ]]
local COPY = {
	title = "One fade, or three",
	intro = "Both panels hold the same three plates and the same opacity. At 100% they are identical.",
	oneTitle = "One group — UI.ZStack{ opacity = f }",
	oneNote = "Painted once, then faded. The small plate stays on top of the big one.",
	manyTitle = "Three groups — the same fade on each plate",
	manyNote = "Each plate fades against what is behind it, so every overlap composes twice.",
	stopsLabel = "Opacity",
	transitionTitle = "A group with no opacity of its own",
	transitionNote = 'enter = "fade" needs the arriving node to already BE a group. This one declares it and writes no opacity.',
	transitionButton = "Show / hide the fading panel",
	transitionBody = "canvasGroup = true, and the transition owns the alpha.",
	refusalTitle = "Where the prop is refused, and what it says",
	statusLabel = "Now",
}

return {
	title = "Canvas group: one fade, or three (ADR-0026)",
	ledgerRows = {},
	copy = COPY,
	stops = STOPS,
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI = Facet.UI
		local core = ctx.core
		local scope = core:scope("canvas-group")
		-- ADAPT-L4: the comparison below claims to go side by side where there is
		-- room, and until 2026-08-21 it never did — `UI.AdaptiveStack` defaulted to
		-- a column and stayed one on a television. The axis is the surface's own
		-- fact now; the class refuses to construct without it. `scope` owns the
		-- memos `conditions` builds (RR-8), so they die with the fixture.
		local conditions = Facet.adaptive.conditions(core, ctx.env, { scope = scope })

		local opacity = scope:own(core:signal(STOPS[3]))
		local showFading = scope:own(core:signal(false))

		--[[ THE REFUSAL, CAPTURED FROM THE FRAMEWORK AT BUILD (ADR-0029).

			A construction is the whole check: `opacity` on any class other than Box
			or ZStack throws BY NAME, at the point of use, before anything is
			mounted. Quoting the message into this file would have made it a string
			that ages; reading it here means the panel says whatever the framework
			says today, including "not missing", which is the part that matters. ]]
		local _, refusalError = pcall(function()
			return UI.Text({ id = "NeverMounted", text = COPY.title, opacity = 0.5 })
		end)
		local refusal = tostring(refusalError)

		local status = scope:own(core:memo(function(use)
			return `{COPY.statusLabel}: {math.floor(use(opacity) * 100 + 0.5)}%`
		end))

		local function plate(spec: any): any
			return UI.Box({
				id = spec.id,
				width = { type = "fixed", px = spec.px },
				height = { type = "fixed", px = spec.px },
				alignH = "center",
				alignV = "center",
				tint = { role = spec.role, blend = 1 },
			})
		end

		-- ONE fade group over all three plates: the opacity is on the STACK.
		local onePanel = UI.ZStack({
			id = "OneGroup",
			opacity = opacity,
			width = { type = "fill", weight = 1 },
			height = { type = "fixed", px = PLATES[1].px },
			children = { plate(PLATES[1]), plate(PLATES[2]), plate(PLATES[3]) },
		})

		-- THREE fade groups over one plate each: the same value, one wrap lower.
		-- The wrapper is a ZStack for the reason the refusal above gives — it is
		-- one of the two classes that can BE a group, so this is the shape an
		-- author gets when they fade "the plate" instead of "the picture".
		local manyPanel = UI.ZStack({
			id = "ThreeGroups",
			width = { type = "fill", weight = 1 },
			height = { type = "fixed", px = PLATES[1].px },
			children = (function()
				local kids = {}
				for _, spec in PLATES do
					table.insert(
						kids,
						UI.ZStack({
							id = `{spec.id}Group`,
							opacity = opacity,
							alignH = "center",
							alignV = "center",
							children = { plate(spec) },
						})
					)
				end
				return kids
			end)(),
		})

		local function panel(id: string, title: string, note: string, body: any): any
			return UI.VStack({
				id = id,
				surface = "control",
				padding = "s",
				gap = "tight",
				width = { type = "fill", weight = 1 },
				children = {
					UI.Text({ id = "Title", text = title, textSize = "caption" }),
					body,
					UI.Text({ id = "Note", text = note, textSize = "caption", role = "secondary" }),
				},
			})
		end

		local stopChips = {}
		for _, stop in STOPS do
			table.insert(
				stopChips,
				UI.Button({
					id = `Stop{math.floor(stop * 100 + 0.5)}`,
					label = `{math.floor(stop * 100 + 0.5)}%`,
					selected = scope:own(core:memo(function(use)
						return use(opacity) == stop
					end)),
					onActivate = function()
						opacity:set(stop)
					end,
				})
			)
		end

		local screen = UI.Screen({
			id = "CanvasGroup",
			padding = 12,
			gap = "s",
			children = {
				-- THE PAGE SCROLLS, for the reason every other fixture here does: two
				-- 132px panels, a chip row, a transition panel and the framework's own
				-- refusal sentence do not fit the ~200px a 640x320 landscape phone has
				-- left once the showcase reserves its chip strip.
				UI.ScrollView({
					id = "Page",
					axis = "y",
					gap = "s",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.Text({ id = "Title", text = COPY.title, textSize = "control" }),
						UI.Text({ id = "Intro", text = COPY.intro, textSize = "caption", role = "secondary" }),
						UI.HStack({
							id = "Stops",
							gap = "tight",
							wrap = true,
							width = { type = "fill", weight = 1 },
							children = (function()
								local row =
									{ UI.Text({ id = "StopsLabel", text = COPY.stopsLabel, textSize = "caption" }) }
								for _, chip in stopChips do
									table.insert(row, chip)
								end
								return row
							end)(),
						}),
						UI.Text({ id = "Status", text = status, textSize = "caption", role = "secondary" }),
						-- side by side where there is room, a column where there is not:
						-- the two panels are only a comparison while both are visible,
						-- and a 320px phone cannot hold two 132px plates in one line
						UI.AdaptiveStack({
							id = "Panels",
							axis = conditions.axis,
							gap = "s",
							width = { type = "fill", weight = 1 },
							children = {
								panel("One", COPY.oneTitle, COPY.oneNote, onePanel),
								panel("Many", COPY.manyTitle, COPY.manyNote, manyPanel),
							},
						}),

						UI.VStack({
							id = "Transition",
							surface = "control",
							padding = "s",
							gap = "tight",
							width = { type = "fill", weight = 1 },
							children = {
								UI.Text({ id = "Title", text = COPY.transitionTitle, textSize = "caption" }),
								UI.Button({
									id = "ToggleFading",
									label = COPY.transitionButton,
									onActivate = function()
										showFading:set(not showFading:get())
									end,
								}),
								UI.When({
									id = "FadingGate",
									condition = showFading,
									transition = { enter = "fade", class = "container" },
									thenView = function()
										-- a ZStack rather than a Box because this one holds
										-- content: `UI.Box` is the plate form of the same
										-- capability and takes neither padding nor children
										return UI.ZStack({
											id = "FadingPanel",
											surface = "raised",
											-- THE DECLARATION, with no opacity beside it
											canvasGroup = true,
											padding = "s",
											width = { type = "fill", weight = 1 },
											children = {
												UI.Text({
													id = "Body",
													text = COPY.transitionBody,
													textSize = "caption",
												}),
											},
										})
									end,
								}),
								UI.Text({
									id = "Note",
									text = COPY.transitionNote,
									textSize = "caption",
									role = "secondary",
								}),
							},
						}),

						UI.Text({ id = "RefusalTitle", text = COPY.refusalTitle, textSize = "caption" }),
						UI.Text({ id = "Refusal", text = refusal, textSize = "caption", role = "secondary" }),
					},
				}),
			},
		})

		return {
			screen = screen,
			present = {},
			-- published for the headless suite: the live signal and the framework's
			-- own refusal text, rather than a re-implementation of either
			opacity = opacity,
			showFading = showFading,
			refusal = refusal,

			steps = {
				setOpacity = function(_built: any, payload: string?)
					local value = tonumber(payload or "") or STOPS[#STOPS]
					opacity:set(value)
					return { opacity = opacity:get() }
				end,
				toggleFading = function()
					showFading:set(not showFading:get())
					return { showing = showFading:get() }
				end,
				refusal = function()
					return { refused = refusal }
				end,
			},

			report = function()
				return {
					opacity = opacity:get(),
					showing = showFading:get(),
					plates = #PLATES,
					refusalNamesTheClass = string.find(refusal, "REFUSED on UI.Text", 1, true) ~= nil,
				}
			end,

			dispose = function()
				scope:dispose()
			end,
		}
	end,
}
