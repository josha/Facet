--!strict
--[[ Scenario 'canvas_group' — ONE FADE, OR THREE.

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
	    An authored opacity MULTIPLIES with the fade under it.

	This is the one demonstration in this catalogue that a still screenshot CAN
	hold — which is the point. The difference is a picture, and until now no
	surface a player can select painted it.

	AND THE ARRIVING PANEL: a branch that fades in. The third panel is a declared
	group whose opacity follows an `app.runtime.tween`, so the whole panel arrives
	as one image rather than as three fading children.

	...AND THE REFUSAL, VERBATIM. `opacity` lives on `Box` and `ZStack` and
	nowhere else, and every other class answers a reach for it by NAME rather than
	through the unknown-property path. The sentence on screen is
	captured at MOUNT from a real refused construction — the framework's own
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
	transitionTitle = "A group that fades in as it arrives",
	transitionNote = "The arriving panel is one group, so a tween on its opacity fades the whole panel at once.",
	transitionButton = "Show / hide the fading panel",
	transitionBody = "canvasGroup = true, and a tween owns the alpha.",
	refusalTitle = "Where the prop is refused, and what it says",
	statusLabel = "Now",
}

return {
	title = "Canvas group: one fade, or three",
	ledgerRows = {},
	copy = COPY,
	stops = STOPS,
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI, Compose = ctx.UI, ctx.Compose

		local opacity = Compose.cell(STOPS[3])
		local showFading = Compose.cell(false)

		--[[ THE REFUSAL, CAPTURED FROM THE FRAMEWORK AT MOUNT.

			A construction is the whole check: `opacity` on any class other than Box
			or ZStack throws BY NAME, at the point of use. Reading the message here
			means the panel says whatever the framework says today, including "not
			missing", which is the part that matters. A constructor needs an owner,
			so the screen captures the sentence as it mounts. ]]
		local refusal = Compose.cell("")

		local status = Compose.formula(function(use)
			return `{COPY.statusLabel}: {math.floor(use(opacity) * 100 + 0.5)}%`
		end)

		local function plate(spec: any): any
			return UI.Box(spec.id)({
				width = { type = "fixed", px = spec.px },
				height = { type = "fixed", px = spec.px },
				alignH = "center",
				alignV = "center",
				tint = { role = spec.role, blend = 1 },
			})
		end

		-- ONE fade group over all three plates: the opacity is on the STACK.
		-- The arriving panel's alpha: a tween from clear to solid that starts when the
		-- branch mounts. A host without an application runtime shows it solid.
		local function arrival(): any
			local runtime = ctx.app and ctx.app.runtime
			if runtime == nil then
				return 1
			end
			local shown = Compose.cell(0)
			local fade = runtime.tween(function(use)
				return use(shown)
			end, { seconds = 0.2 })
			shown:set(1)
			return fade
		end

		local function Example()
			-- The axis is the surface's own fact: side by side where there is room.
			local conditions = Facet.adaptive.conditions(ctx.env)
			local _, refusalError = pcall(function()
				return UI.Text("NeverMounted")({ text = COPY.title, opacity = 0.5 })
			end)
			refusal:set(tostring(refusalError))

			local onePanel = UI.ZStack("OneGroup")({
				opacity = opacity,
				width = UI.fill(),
				height = { type = "fixed", px = PLATES[1].px },
				plate(PLATES[1]),
				plate(PLATES[2]),
				plate(PLATES[3]),
			})

			-- THREE fade groups over one plate each: the same value, one wrap lower.
			-- The wrapper is a ZStack for the reason the refusal above gives — it is
			-- one of the two classes that can BE a group, so this is the shape an
			-- author gets when they fade "the plate" instead of "the picture".
			local manyProps: { [any]: any } = { width = UI.fill(), height = { type = "fixed", px = PLATES[1].px } }
			for _, spec in PLATES do
				table.insert(
					manyProps,
					UI.ZStack(`{spec.id}Group`)({
						opacity = opacity,
						alignH = "center",
						alignV = "center",
						plate(spec),
					})
				)
			end
			local manyPanel = UI.ZStack("ThreeGroups")(manyProps)

			local function panel(id: string, title: string, note: string, body: any): any
				return UI.VStack(id)({
					surface = "control",
					padding = "s",
					gap = "tight",
					width = UI.fill(),

					UI.Text("Title")({ text = title, textSize = "caption" }),
					body,
					UI.Text("Note")({ text = note, textSize = "caption", role = "secondary" }),
				})
			end

			return UI.Screen("CanvasGroup")({
				padding = 12,
				gap = "s",

				-- THE PAGE SCROLLS, for the reason every other fixture here does: two
				-- 132px panels, a chip row, a transition panel and the framework's own
				-- refusal sentence do not fit the ~200px a 640x320 landscape phone has
				-- left once the showcase reserves its chip strip.
				UI.ScrollView("Page")({
					axis = "y",
					gap = "s",
					width = UI.fill(),
					height = UI.fill(),

					UI.Text("Title")({ text = COPY.title, textSize = "control" }),
					UI.Text("Intro")({ text = COPY.intro, textSize = "caption", role = "secondary" }),
					UI.Picker("Stops")({
						label = COPY.stopsLabel,
						style = "segmented",
						selected = opacity,
						options = (function()
							local options = {}
							for _, stop in STOPS do
								table.insert(options, { value = stop, label = `{math.floor(stop * 100 + 0.5)}%` })
							end
							return options
						end)(),
					}),
					UI.Text("Status")({ text = status, textSize = "caption", role = "secondary" }),
					-- side by side where there is room, a column where there is not:
					-- the two panels are only a comparison while both are visible,
					-- and a 320px phone cannot hold two 132px plates in one line
					UI.AdaptiveStack("Panels")({
						axis = conditions.axis,
						gap = "s",
						width = UI.fill(),

						panel("One", COPY.oneTitle, COPY.oneNote, onePanel),
						panel("Many", COPY.manyTitle, COPY.manyNote, manyPanel),
					}),

					UI.VStack("Transition")({
						surface = "control",
						padding = "s",
						gap = "tight",
						width = UI.fill(),

						UI.Text("Title")({ text = COPY.transitionTitle, textSize = "caption" }),
						UI.Button("ToggleFading")({
							label = COPY.transitionButton,
							onActivate = function()
								showFading:set(not showFading:peek())
							end,
						}),
						UI.When("FadingGate")({
							Compose.show(showFading, function()
								return UI.ZStack("FadingPanel")({
									surface = "raised",
									canvasGroup = true,
									opacity = arrival(),
									padding = "s",
									width = UI.fill(),

									UI.Text("Body")({ text = COPY.transitionBody, textSize = "caption" }),
								})
							end),
						}),
						UI.Text("Note")({
							text = COPY.transitionNote,
							textSize = "caption",
							role = "secondary",
						}),
					}),

					UI.Text("RefusalTitle")({ text = COPY.refusalTitle, textSize = "caption" }),
					UI.Text("Refusal")({ text = refusal, textSize = "caption", role = "secondary" }),
				}),
			})
		end

		return {
			screen = Example,
			present = {},
			-- published for the headless suite: the live signal and the framework's
			-- own refusal text, rather than a re-implementation of either
			opacity = opacity,
			showFading = showFading,
			-- the framework's sentence, readable once the screen has mounted
			refusal = refusal,

			steps = {
				setOpacity = function(_built: any, payload: string?)
					local value = tonumber(payload or "") or STOPS[#STOPS]
					opacity:set(value)
					return { opacity = opacity:peek() }
				end,
				toggleFading = function()
					showFading:set(not showFading:peek())
					return { showing = showFading:peek() }
				end,
				refusal = function()
					return { refused = refusal:peek() }
				end,
			},

			report = function()
				return {
					opacity = opacity:peek(),
					showing = showFading:peek(),
					plates = #PLATES,
					refusalNamesTheClass = string.find(refusal:peek(), "REFUSED on UI.Text", 1, true) ~= nil,
				}
			end,

			dispose = function() end,
		}
	end,
}
