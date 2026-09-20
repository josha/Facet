--!strict
--[[ Scenario 'surface_overlap' — TWO SURFACES, AND WHO SAID SO.

	The director, 2026-08-14, watching a leftover debug probe interleave with a
	real fixture in his live Studio session, both starting at x=16: *"the
	framework should stop this from happening."*

	WHAT A STILL SCREENSHOT CANNOT SHOW, and therefore what this fixture is FOR.
	Two surfaces on top of each other look the same however they got there — the
	pixels of a modal covering a HUD and the pixels of a forgotten probe covering
	a HUD are identical. The difference is entirely in what was DECLARED, and this
	screen is that difference made visible: one probe surface, three declarations,
	and the framework's own sentence about each.

	  · LAYERED (the default, and why the sweep is green). The probe is moved into
	    the band above with `controller.setDisplayOrder(SURFACE_LAYER.toast + 100)`.
	    A different band is a declaration — the bands exist precisely so a toast is
	    above every base screen and below every modal whatever order they arrived
	    in — so the framework has nothing to say.
	  · DECORATION. The probe is re-presented `rootPolicy = "edgeToEdge"`, the
	    renderer's own word for "a DECORATION layer, not content". Also silent, for
	    a different reason: a scrim means to cover, and means to be covered.
	  · UNDECLARED. Same pixels, same geometry, nothing said. The alarm fires, on
	    BOTH surfaces, and the readout below is `controller.diagnostics()` read
	    straight off the probe's controller with no interpretation in between.

	AND THE FOURTH BUTTON IS THE POINT THE COMPOSITION HANDED OVER: an INVISIBLE probe.
	It is still mounted, still solved, still occupying exactly the same box — and
	it covers nothing a player can see, so the alarm is silent. A geometry-only
	test would report a collision nobody could ever find.

	THE PROBE IS SCOPE-OWNED AND DISMISSED ON THE WAY OUT, on every path. That is
	not incidental tidiness: a probe surface left behind by a fixture is the exact
	thing that commissioned this file.

	TWO HOSTS MOUNT THIS FILE and only one of them runs steps (the pair
	`lifecycle_hidden.luau` documents): the scenario runner drives `steps` by name,
	and the showcase demo picker mounts it with a minimal ctx and no step ever
	runs. The four buttons are ordinary controls with their own callbacks, so the
	fixture is fully drivable by a player with nothing scripted.
]]

--[[ EVERY PLAYER-VISIBLE STRING, in one table and EXPORTED as `copy` — the same
	contract `lifecycle_hidden.luau` and `flow_wrap.luau` carry, because
	`tests/examples_gallery.spec.luau`'s localization case re-runs the whole
	fixture through a ~1.4x pseudo-localizing expansion and a check that cannot
	reach the strings cannot make that claim. Flat keys only. ]]
local COPY = {
	title = "Two surfaces, and who said so",
	intro = "One probe surface sits over this screen. The pixels are the same in all four states — only the declaration changes.",
	pick = "How the probe is presented",
	layered = "Layered",
	decoration = "Decoration",
	undeclared = "Undeclared",
	invisible = "Invisible",
	stateTitle = "Live declaration",
	findingsTitle = "What the framework says",
	quiet = "Nothing — the pair is declared, so there is no defect to report.",
	quietHidden = "Nothing — the probe covers nothing a player can see, so it is in no pair.",
	note = "A modal SHOULD cover a HUD. The alarm fires only when two surfaces overlap and neither said it meant to.",
	probe = "debug probe",
	probeHint = "x=16, on top of everything",
}

-- what each button declares, in the framework's own vocabulary
local DECLARATIONS = {
	layered = "a display band above (setDisplayOrder)",
	decoration = 'rootPolicy = "edgeToEdge"',
	undeclared = "nothing at all",
	invisible = "nothing — and it covers nothing (hidden)",
}

return {
	title = "Cross-surface overlap",
	ledgerRows = {},
	copy = COPY,
	declarations = DECLARATIONS,
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local app = ctx.app

		local mode = Compose.cell("layered")
		local declaration = Compose.cell(DECLARATIONS.layered)
		local findings = Compose.cell(COPY.quiet)
		local probeHidden = Compose.cell(false)

		-- THE PROBE SURFACE. A small plate hard against the top-left of the
		-- screen — 16px in, which is where the director's real one was.
		local function probeScreen(): any
			return UI.Screen("SurfaceOverlapProbe")({
				padding = "m",

				UI.VStack("Plate")({
					surface = "control",
					padding = "s",
					gap = "xs",
					hidden = probeHidden,

					UI.Text("Label")({ text = COPY.probe, textSize = "caption" }),
					UI.Text("Hint")({ text = COPY.probeHint, textSize = "caption", role = "secondary" }),
				}),
			})
		end

		local probeHandle: any = nil
		local closeProbe: (() -> ())? = nil

		-- SCOPE-OWNED, ON EVERY PATH. `dispose` below runs it, and it runs before
		-- every re-present, so no state of this fixture can leave two probes on
		-- screen — which is the defect the fixture is about.
		local function dropProbe()
			if closeProbe ~= nil then
				closeProbe()
			end
			closeProbe, probeHandle = nil, nil
		end

		local function raiseProbe(edgeToEdge: boolean, layered: boolean)
			dropProbe()
			if app == nil then
				return
			end
			local _
			closeProbe, _, probeHandle = app.mount(probeScreen, {
				-- passive: a second base surface shares ONE focus graph with the
				-- screen behind it, and a debug overlay must never take the Tab ring
				responder = "passive",
				rootPolicy = if edgeToEdge then "edgeToEdge" else "coreSafeContent",
			})
			if layered then
				-- the band above, which is the declaration itself
				probeHandle.controller.setDisplayOrder(ctx.presenter.SURFACE_LAYER.toast + 100)
			end
		end

		-- THE READOUT IS `controller.diagnostics()`, UNINTERPRETED. It is filed on
		-- both surfaces of a pair with the identical sentence, so reading the
		-- probe's controller and reading this screen's give the same answer.
		local function readFindings()
			local lines: { string } = {}
			if probeHandle ~= nil then
				for _, finding in probeHandle.controller.diagnostics() do
					if string.find(finding.issue, "independently mounted surfaces", 1, true) ~= nil then
						table.insert(lines, finding.issue)
					end
				end
			end
			if #lines == 0 then
				findings:set(if probeHidden:peek() then COPY.quietHidden else COPY.quiet)
			else
				findings:set(table.concat(lines, "\n"))
			end
		end

		local function choose(next: string)
			mode:set(next)
			probeHidden:set(next == "invisible")
			raiseProbe(next == "decoration", next == "layered")
			declaration:set(DECLARATIONS[next] or "")
			readFindings()
		end

		choose("layered")

		local function screen()
			return UI.Screen("SurfaceOverlap")({
				padding = 12,
				gap = "s",

				-- the page scrolls for the reason every fixture here does: a title,
				-- a control row and two readouts do not fit the ~200px a 640x320
				-- landscape phone has left once the showcase reserves its chip strip
				UI.ScrollView("Page")({
					axis = "y",
					gap = "s",
					width = UI.fill(),
					height = UI.fill(),

					UI.Text("Title")({ text = COPY.title, textSize = "control" }),
					UI.Text("Intro")({ text = COPY.intro, textSize = "caption", role = "secondary" }),
					UI.Text("PickLabel")({ text = COPY.pick, textSize = "caption" }),
					-- one value among four, so the choice is a picker
					UI.Picker("Picks")({
						label = COPY.pick,
						selected = mode,
						style = "segmented",
						options = {
							{ value = "layered", label = COPY.layered },
							{ value = "decoration", label = COPY.decoration },
							{ value = "undeclared", label = COPY.undeclared },
							{ value = "invisible", label = COPY.invisible },
						},
						onChange = choose,
					}),
					UI.VStack("State")({
						surface = "control",
						padding = "s",
						gap = "xs",
						width = UI.fill(),

						UI.Text("StateTitle")({ text = COPY.stateTitle, textSize = "caption" }),
						UI.Text("Declaration")({
							text = declaration,
							textSize = "caption",
							role = "secondary",
						}),
					}),
					UI.VStack("Findings")({
						surface = "control",
						padding = "s",
						gap = "xs",
						width = UI.fill(),

						UI.Text("FindingsTitle")({ text = COPY.findingsTitle, textSize = "caption" }),
						UI.Text("FindingsBody")({
							text = findings,
							textSize = "caption",
							role = "secondary",
						}),
					}),
					UI.Text("Note")({ text = COPY.note, textSize = "caption", role = "secondary" }),
				}),
			})
		end

		return {
			screen = screen,
			present = {},
			mode = mode,
			findings = findings,

			steps = {
				-- one step, taking the same four values the four buttons do
				declare = function(_built: any, payload: string?)
					choose(payload or "layered")
					return { mode = mode:peek() }
				end,
				-- re-read after the host has settled a frame (a `hidden` swing needs
				-- the solve that retires the rect before the union can shrink)
				reread = function()
					readFindings()
					return { findings = findings:peek() }
				end,
			},

			report = function()
				return {
					mode = mode:peek(),
					declaration = declaration:peek(),
					findings = findings:peek(),
				}
			end,

			dispose = function()
				dropProbe()
			end,
		}
	end,
}
