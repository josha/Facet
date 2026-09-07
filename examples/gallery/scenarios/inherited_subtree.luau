--!strict
--[[ Scenario 'inherited_subtree' — the showcase surface for the two INHERITED
	container properties (Facet stabilization pass, stream D; stream C's design
	note `docs/superpowers/specs/2026-09-07-inherited-tint-disabled.md`, its
	implementation `src/mount.luau`/`src/class_contract.luau`, and its docs at
	`docs/reference/api.md#inherited-properties-enabled-and-tint` and
	`docs/guide/05-styling.md`).

	`enabled` and `tint`, written on any layout container, now reach the WHOLE
	SUBTREE below it — not just the leaf they used to be declared on. The
	standing obligation is that every new public capability appears in a gallery
	scenario the headless suite executes and a player can actually open, and
	this is that scenario.

	WHY ITS OWN FIXTURE, RATHER THAN A CORNER OF ONE THAT ALREADY EXISTS. Every
	candidate that already teaches a nearby lesson would have muddled it:
	`adaptive_controls` is the write-once ADAPTIVE-layout proof, `native_style`
	is art-driven skinning, `keyboard_navigation` is the desktop focus CHAIN.
	None of them is about a container handing state or colour to descendants
	that never asked for it, and wedging a sixth idea into any of those would
	have cost that fixture's own legibility for no shared surface. A cascade
	through an ordinary tree, on the other hand, is the whole subject here and
	deserves the same clean room `lifecycle_hidden` and `row_capabilities` got
	for their own single ideas.

	WHAT A STILL SCREENSHOT CANNOT SHOW, and therefore what this fixture is FOR:

	  · NESTED INHERITANCE. `Panel` declares one `tint`; `Row/HeroTitle` (a
	    `Text`) and `Row/Crest` (an `Image`) are TWO LEVELS below it and name no
	    tint of their own. A screenshot of either one alone looks like an
	    ordinary coloured label — the fact that NEITHER declares the colour it
	    is wearing only shows up next to the declaration that produced it.
	  · BOTH KINDS OF OVERRIDE. `Note` is a LEAF with its own `tint` (danger);
	    `Inner` is a CONTAINER with its own `tint` (contentSecondary), and its
	    child `Sub` takes THAT value, not Panel's. Showing both is what makes
	    "the nearest declaration wins" legible rather than asserted.
	  · THE CONTROL BOUNDARY. `Go` is a `Button` inside the tinted panel with
	    its own custom content (`Caption`); its role paint and its content never
	    take the ambient tint, on purpose — a control's interior belongs to the
	    role and the state machine, never to a passing colour.
	  · THE DYNAMIC TOGGLE. `PowerToggle` drives `enabled` on `Panel` alone; when
	    it goes false every control inside stops taking a tap, a keyboard Tab,
	    or a gamepad press, and the panel dims through the THEME (never a
	    literal) — a still frame of the dimmed state looks like a normal muted
	    panel until you try to press something in it and nothing happens.
	  · FOCUS RESTORATION. This is the one beat a screenshot cannot hold at all:
	    focus has to be walked INTO the panel first (`tabInto`), and then the
	    panel disabled from under it (`disableWhileFocused`), for the ring's
	    jump to a legal node outside to be visible as a jump rather than a
	    static fact.
	  · A SECOND, REACTIVE TINT. `BlendSlider` drives the SAME container tint
	    continuously (0..1 against `accent`), so "the colour updates live, with
	    no remount" is a drag rather than a claim about two static screenshots.

	TWO THINGS THIS FIXTURE DELIBERATELY DOES NOT SHOW (docs/reference/api.md
	"Inherited properties: enabled and tint"): there is no `enabled = true`
	escape hatch anywhere inside `Panel` — a descendant cannot re-enable itself
	under a disabled ancestor, by design, so this fixture does not pretend one
	exists; and `Crest` dimming when the panel disables is not demonstrated,
	because it would not happen — the themed disabled dim is TEXT ONLY. `Crest`
	inherits `Panel`'s COLOUR tint (an independent behaviour) and keeps its own
	paint when the panel goes dark, exactly as documented.

	THEME ROLES ONLY, with one exception clearly named: `DirectDemo` uses the
	`{ direct = "#rrggbb" }` literal FORM on purpose, labelled in its own text,
	to show that the escape hatch exists beside the themable form every other
	node here uses.

	TWO HOSTS MOUNT THIS FILE, AND ONLY ONE OF THEM RUNS STEPS (the same pair
	`card_rail.luau` and `flow_wrap.luau` document): the scenario runner drives
	`steps` by name for the Studio device-matrix drive and the headless spec
	(`tests/inherited_subtree_scenario.spec.luau`); the showcase demo picker
	mounts it with a minimal ctx and no step ever runs — the toggle and slider
	are ordinary controls with their own value signals there.
]]

--[[ EVERY PLAYER-VISIBLE STRING ON THIS SURFACE, in one table, EXPORTED as the
	module's `copy` field — the same contract `flow_wrap.luau` and
	`lifecycle_hidden.luau` carry, so a pseudo-localization pass can expand every
	string this fixture actually renders. Flat keys only. ]]
local COPY = {
	title = "Inherited enabled and tint",
	intro = "One container, two things it hands its whole subtree: a colour, and whether anything in it can be touched at all.",
	powerLabel = "Panel power",
	blendLabel = "Tint",
	heroText = "No tint declared here",
	crestLabel = "An Image two levels down — same story",
	noteText = "A leaf overrides with its own tint (danger)",
	innerSubText = "The NEAREST container's tint wins here, not Panel's",
	directText = 'direct = "#3388ff" — the literal form, named',
	goLabel = "Engage",
	goCaption = "Ready",
	controlBoundaryNote = "A control's own paint and content are never tinted — see Engage above.",
	afterLabel = "After",
	afterNote = "A legal focus stop AFTER the panel — Tab lands here straight from the slider once the panel is off.",
	statusPrefix = "Panel: ",
	statusOn = "on",
	statusOff = "off (dimmed, unreachable)",
}

local PANEL_PATH = "/InheritedSubtree/Page/Panel"
local TOGGLE_PATH = "/InheritedSubtree/Page/PowerToggle"
local SLIDER_PATH = "/InheritedSubtree/Page/BlendSlider"
local GO_PATH = PANEL_PATH .. "/Go"
local AFTER_PATH = "/InheritedSubtree/Page/After"
local HERO_PATH = PANEL_PATH .. "/Row/HeroTitle"
local CREST_PATH = PANEL_PATH .. "/Row/Crest"
local NOTE_PATH = PANEL_PATH .. "/Note"
local INNER_SUB_PATH = PANEL_PATH .. "/Inner/Sub"
local DIRECT_PATH = PANEL_PATH .. "/DirectDemo"
local CAPTION_PATH = GO_PATH .. "/Caption"

return {
	title = "Inherited enabled and tint",
	ledgerRows = {},
	copy = COPY,
	-- published for the headless spec, so it asserts against the SAME paths
	-- this file declares rather than a re-typed copy of them
	paths = {
		panel = PANEL_PATH,
		toggle = TOGGLE_PATH,
		slider = SLIDER_PATH,
		go = GO_PATH,
		after = AFTER_PATH,
		hero = HERO_PATH,
		crest = CREST_PATH,
		note = NOTE_PATH,
		innerSub = INNER_SUB_PATH,
		direct = DIRECT_PATH,
		caption = CAPTION_PATH,
	},
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI = Facet.UI
		local core = ctx.core
		local scope = core:scope("inherited-subtree")

		-- the panel's OWN state: whether it is on, and how far its tint blends
		-- toward `accent`. `blendPercent` is the SLIDER's own value (a whole
		-- percentage, like every other slider this gallery ships — a fractional
		-- 0..1 track with a two-decimal readout overflowed its own readout
		-- column at 320px under two shipped packages, caught by
		-- `tests/lib/world`'s containment guard); `blend` is the 0..1 fraction
		-- the public `tint` value actually wants, derived from it.
		local live = scope:own(core:signal(true))
		local blendPercent = scope:own(core:signal(35))
		local blend = scope:own(core:memo(function(use)
			return use(blendPercent) / 100
		end))
		-- how many times `Go` has actually fired Activate — the observable proof
		-- that the panel being "on" is not merely a paint state: this is what a
		-- pointer, a touch, a keyboard Return or a gamepad A actually reaches
		-- when the panel is enabled, and never reaches when it is not.
		local engaged = scope:own(core:signal(0))

		local panelTint = scope:own(core:memo(function(use)
			return { role = "accent", blend = use(blend) }
		end))

		local status = scope:own(core:memo(function(use)
			local pct = use(blendPercent)
			return `{COPY.statusPrefix}{if use(live) then COPY.statusOn else COPY.statusOff} — blend {pct}%`
		end))

		local slider = Facet.Controls.Slider(core, {
			id = "BlendSlider",
			label = COPY.blendLabel,
			value = blendPercent,
			min = 0,
			max = 100,
			step = 5,
		})

		local screen = UI.Screen({
			id = "InheritedSubtree",
			padding = 12,
			gap = "s",
			children = {
				-- THE PAGE SCROLLS, for the reason every other fixture here does: a
				-- title, two controls, a seven-node panel and a status line do not fit
				-- the ~200px a 640x320 landscape phone has left once the showcase
				-- reserves its chip strip.
				UI.ScrollView({
					id = "Page",
					axis = "y",
					gap = "s",
					width = UI.fill(),
					height = UI.fill(),
					children = {
						UI.Text({ id = "Title", text = COPY.title, textSize = "control" }),
						UI.Text({ id = "Intro", text = COPY.intro, textSize = "caption", role = "secondary" }),
						UI.Toggle({ id = "PowerToggle", label = COPY.powerLabel, value = live }),
						slider.blueprint,
						UI.VStack({
							id = "Panel",
							-- THE TWO INHERITED PROPS, ON ONE CONTAINER. Everything below
							-- this line that names no `tint`/`enabled` of its own takes
							-- these; anything that names its own wins over them.
							enabled = live,
							tint = panelTint,
							surface = "control",
							padding = "s",
							gap = "tight",
							width = UI.fill(),
							children = {
								-- BEAT 1: NESTED INHERITANCE, two levels below Panel.
								UI.HStack({
									id = "Row",
									gap = "s",
									-- a `fill` child needs a determinate parent to fill: a
									-- `hug` HStack sizes to its content, so `HeroTitle`'s
									-- `fill` had nothing to expand into and solved to a
									-- zero-width box (caught by `tests/lib/world`'s
									-- containment guard, not by `controller.diagnostics()`,
									-- which reports overflow, never underflow)
									width = UI.fill(),
									children = {
										UI.Text({
											id = "HeroTitle",
											text = COPY.heroText,
											textSize = "control",
											width = UI.fill(),
										}),
										UI.Image({
											id = "Crest",
											width = { type = "fixed", px = 28 },
											height = { type = "fixed", px = 28 },
										}),
									},
								}),
								UI.Text({
									id = "CrestCaption",
									text = COPY.crestLabel,
									textSize = "caption",
									role = "secondary",
								}),
								-- BEAT 2a: LEAF OVERRIDE — its own tint beats the inherited one.
								UI.Text({
									id = "Note",
									text = COPY.noteText,
									textSize = "caption",
									tint = { role = "danger", blend = 1 },
								}),
								-- BEAT 2b: NESTED-CONTAINER OVERRIDE — `Inner`'s own tint
								-- replaces `Panel`'s for everything under `Inner`; `Sub`
								-- names none of its own, so it takes `Inner`'s, not `Panel`'s.
								UI.VStack({
									id = "Inner",
									tint = { role = "contentSecondary", blend = 1 },
									gap = "tight",
									children = {
										UI.Text({ id = "Sub", text = COPY.innerSubText, textSize = "caption" }),
									},
								}),
								-- THE ONE LITERAL FORM, CLEARLY LABELLED. Every other tint on
								-- this screen is a theme role; this is the `direct` escape
								-- hatch, named in its own text so nobody mistakes it for the
								-- rule rather than the exception.
								UI.Text({
									id = "DirectDemo",
									text = COPY.directText,
									textSize = "caption",
									tint = { direct = "#3388ff" },
								}),
								-- BEAT 3: THE CONTROL BOUNDARY. `Go`'s role paint and its own
								-- `Caption` content take neither `Panel`'s tint nor a
								-- descendant's — a control's interior is not tinted, ever.
								UI.Button({
									id = "Go",
									label = COPY.goLabel,
									onActivate = function()
										engaged:set(engaged:get() + 1)
									end,
									children = { UI.Text({ id = "Caption", text = COPY.goCaption }) },
								}),
								UI.Text({
									id = "ControlNote",
									text = COPY.controlBoundaryNote,
									textSize = "caption",
									role = "secondary",
								}),
							},
						}),
						UI.Text({ id = "Status", text = status, textSize = "caption", role = "secondary" }),
						-- BEATS 4/5: a legal focus stop AFTER the panel. With the panel on,
						-- Tab from `BlendSlider` stops at `Go` first; with it off, Tab lands
						-- here directly — the panel is skipped, not merely unreachable by
						-- one route.
						UI.Button({ id = "After", label = COPY.afterLabel }),
						UI.Text({ id = "AfterNote", text = COPY.afterNote, textSize = "caption", role = "secondary" }),
					},
				}),
			},
		})

		return {
			screen = screen,
			-- keyboard Tab traversal is opt-in on a presented surface (director
			-- playtest 2026-08-03: the keys it claims default off so a live game
			-- world keeps them). This fixture's own subject is what Tab and a
			-- gamepad both do to a disabled subtree, so it opts in exactly like
			-- `keyboard_navigation.luau` does.
			present = { keyboardNavigation = true },
			-- published for the headless suite: the signals a spec drives and
			-- reads directly, rather than a re-implementation of them
			live = live,
			blend = blend,
			engaged = engaged,

			steps = {
				-- the toggle, as the player's own press fires it. payload "on"/"off"
				-- pins a direction; anything else flips the current value.
				toggleEnabled = function(_built: any, payload: string?)
					if payload == "on" then
						live:set(true)
					elseif payload == "off" then
						live:set(false)
					else
						live:set(not live:get())
					end
					ctx.presenter.refresh()
					return { enabled = live:get() }
				end,

				-- the reactive tint's driver. payload is the blend fraction as text
				-- ("0".."1"), the same public unit `report().blend` and `tint.blend`
				-- use; an unparsable payload leaves the value untouched and says so,
				-- rather than guessing. Internally drives the SLIDER's own whole
				-- percentage, which is what the readout actually paints.
				setBlend = function(_built: any, payload: string?)
					local v = if payload ~= nil then tonumber(payload) else nil
					if v ~= nil then
						blendPercent:set(math.clamp(v, 0, 1) * 100)
					end
					ctx.presenter.refresh()
					return { blend = blend:get(), applied = v ~= nil }
				end,

				-- REAL Tab presses (the keyboard Traverse action), from a known
				-- start, until focus reaches `Go` or the hop budget runs out —
				-- robust to how many stops the slider itself occupies rather than
				-- assuming an exact hop count. This is the same input path a
				-- keyboard or gamepad player uses, not a `focusOn` shortcut.
				tabInto = function(_built: any, payload: string?)
					local hops = tonumber(payload or "") or 8
					ctx.presenter.focus.focusOn(TOGGLE_PATH)
					ctx.presenter.focus.setFocusOrigin("navigation")
					ctx.presenter.refresh()
					for _ = 1, hops do
						if ctx.presenter.focus.focused:get() == GO_PATH then
							break
						end
						ctx.actionSystem.deviceKey("Tab", true)
						ctx.actionSystem.deviceKey("Tab", false)
						ctx.presenter.refresh()
					end
					return { focus = ctx.presenter.focus.focused:get() }
				end,

				-- BEAT 5, as one atomic step: call this AFTER `tabInto` has put
				-- focus inside the panel. It disables the panel out from under
				-- the focused node and reports both sides of the jump, which is
				-- the only way this beat is visible at all.
				disableWhileFocused = function(_built: any, _payload: string?)
					local before = ctx.presenter.focus.focused:get()
					live:set(false)
					ctx.presenter.refresh()
					local after = ctx.presenter.focus.focused:get()
					return { before = before, after = after }
				end,
			},

			report = function()
				return {
					enabled = live:get(),
					blend = blend:get(),
					engaged = engaged:get(),
					focus = ctx.presenter.focus.focused:get(),
					-- WHAT THIS SCENARIO ITSELF DECLARED, not a re-derivation of an
					-- internal predicate: the panel is disabled exactly when `live`
					-- is false, by construction, and everything under it inherits
					-- that same verdict.
					disabled = { panelPath = PANEL_PATH, panel = not live:get() },
					-- the tint this container is CURRENTLY cascading to `HeroTitle`
					-- and `Crest`, two levels down, by declaration — the same value
					-- `panelTint` hands the framework this frame.
					heroTint = { role = "accent", blend = blend:get(), path = HERO_PATH },
				}
			end,

			dispose = function()
				scope:dispose()
			end,
		}
	end,
}
