--!strict
-- Scenario 'native_style' (ledger NSS-A2..A7, NSS-A10): the native-stylesheet
-- E3 fixture. One representative screen exercising every handed-off property
-- group — surfaces (base/raised/control/accent/scrim-free variants), selected
-- rows, disabled controls, secondary/strong text, a TextField, a ScrollView —
-- through the REAL adapter with `Facet_NativeStyle=true` (or the explicit-
-- write fallback when `Facet_ForceStyleFallback=true`, the NSS-A10 A/B).
--
-- Steps drive Facet state (tags follow), runtime designer-edits (the SAME
-- DataModel objects the Style Editor edits), theme swaps, and the transition
-- strip. The runner's report carries per-node tags + GetStyled resolution +
-- GuiState + mount identity, which is the property-authority telemetry the
-- acceptance rows require. Engine-free module: all engine access rides the
-- ctx.nativeStyle seams the runner owns.

return {
	title = "Native stylesheet paint",
	ledgerRows = { "NSS-A2", "NSS-A3", "NSS-A4", "NSS-A5", "NSS-A6", "NSS-A7", "NSS-A10" },
	build = function(ctx: any)
		local UI = ctx.Facet.UI
		local core = ctx.core
		local selectedA = core:signal(true)
		local selectedB = core:signal(false)
		local rowBEnabled = core:signal(true)
		local toggleOn = core:signal(true)
		local fieldText = core:signal("styled")
		local field = ctx.Facet.Controls.TextInput(core, {
			id = "Field",
			value = fieldText,
			placeholder = "type here",
			env = ctx.env,
			actionSystem = ctx.actionSystem,
		})

		-- The body SCROLLS (overflow sweep, 2026-08-12): Title + Subtitle + Panel +
		-- SurfaceRow + the nested Scroll demo ran 61-352px past the screen on a
		-- narrow phone and on every landscape phone, with nothing to move it — the
		-- adaptive_controls "BodyScroll" shape (fill-width/fill-height ScrollView
		-- absorbing the whole column). This adds one path segment under every
		-- descendant (`/NativeStyle/Body/...`), so every path this module and
		-- `tests/native_style_scenario.spec.luau` reference moved with it.
		local screen = UI.Screen({
			id = "NativeStyle",
			padding = 16,
			gap = 8,
			surface = "base",
			children = {
				UI.ScrollView({
					id = "Body",
					axis = "y",
					gap = 8,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.Text({ id = "Title", text = "Native stylesheet fixture", textSize = 24 }),
						UI.Text({ id = "Subtitle", text = "secondary text", textSize = 14, role = "secondary" }),
						UI.VStack({
							id = "Panel",
							surface = "raised",
							padding = 12,
							gap = 8,
							children = {
								UI.Button({ id = "RowA", label = "Row A (selected)", selected = selectedA }),
								UI.Button({
									id = "RowB",
									label = "Row B",
									selected = selectedB,
									enabled = rowBEnabled,
								}),
								UI.Button({ id = "Primary", label = "Primary action", surface = "accent" }),
								UI.Toggle({ id = "Music", label = "Music", value = toggleOn }),
								field.blueprint,
							},
						}),
						-- remaining handed-off surfaces (arch verifier 2026-07-24: chip/
						-- badge/scrim/plain were headless-only) + a focusable Grip for
						-- the native grip-focus tag rule.
						--
						-- A Grid rather than the original HStack (overflow sweep,
						-- 2026-08-12): five fixed-width chips ran 43-82px past a narrow
						-- phone's width with nothing to wrap them. Each surface keeps its
						-- own declared size (a non-fill Grid cell keeps content sizing,
						-- per the solver), so this only changes how many sit on one row —
						-- never what they look like.
						UI.Grid({
							id = "SurfaceRow",
							minColumnWidth = 90,
							gap = 8,
							children = {
								UI.Box({
									id = "Chip",
									surface = "chip",
									width = { type = "fixed", px = 90 },
									height = { type = "fixed", px = 56 },
								}),
								UI.Image({
									id = "Badge",
									surface = "badge",
									width = { type = "fixed", px = 56 },
									height = { type = "fixed", px = 56 },
								}),
								UI.Box({
									id = "ScrimPatch",
									surface = "scrim",
									width = { type = "fixed", px = 90 },
									height = { type = "fixed", px = 56 },
								}),
								UI.Button({
									id = "PlainBtn",
									label = "plain",
									surface = "plain",
									width = { type = "fixed", px = 90 },
									height = { type = "fixed", px = 56 },
								}),
								UI.Grip({
									id = "Grip",
									focusable = true,
									width = { type = "fixed", px = 12 },
									height = { type = "fixed", px = 56 },
								}),
							},
						}),
						UI.ScrollView({
							id = "Scroll",
							height = { type = "fixed", px = 120 },
							children = (function()
								local rows = {}
								for i = 1, 8 do
									table.insert(
										rows,
										UI.Text({
											id = "ScrollRow" .. i,
											text = "Scroll row " .. i,
											textSize = 16,
											height = { type = "fixed", px = 28 },
										})
									)
								end
								return rows
							end)(),
						}),
					},
				}),
			},
		})

		return {
			screen = screen,
			present = {
				onActivate = function(path: string)
					if path == "/NativeStyle/Body/Panel/RowA" then
						selectedA:set(not selectedA:get())
					elseif path == "/NativeStyle/Body/Panel/RowB" then
						selectedB:set(not selectedB:get())
					elseif path == "/NativeStyle/Body/Panel/Music" then
						toggleOn:set(not toggleOn:get())
					end
				end,
			},
			steps = {
				-- NSS-A2: mode + authority probe data (full tree rides the report)
				probe = function()
					return ctx.nativeStyle.info()
				end,
				-- NSS-A5: the selected binding flip IS a tag flip in native mode
				selectRowB = function()
					selectedB:set(true)
					return true
				end,
				deselectRowB = function()
					selectedB:set(false)
					return true
				end,
				-- disabled state (native: Interactable=false -> :NonInteractable)
				disableRowB = function()
					rowBEnabled:set(false)
					return true
				end,
				enableRowB = function()
					rowBEnabled:set(true)
					return true
				end,
				-- NSS-A3: runtime designer-edits of the live sheet objects
				editTokenLive = function()
					return ctx.nativeStyle.editToken("Dark", "Control", 0.85, 0.1, 0.85)
				end,
				restoreToken = function()
					return ctx.nativeStyle.editToken("Dark", "Control", 41 / 255, 45 / 255, 58 / 255)
				end,
				editRuleLive = function()
					return ctx.nativeStyle.editRuleProperty(
						"Raised panel",
						"BackgroundColor3",
						{ r = 0.05, g = 0.45, b = 0.4 }
					)
				end,
				restoreRule = function()
					return ctx.nativeStyle.editRuleProperty("Raised panel", "BackgroundColor3", "$SurfaceStrong")
				end,
				-- NSS-A6: runtime theme swap (no remount / no focus loss)
				themeLight = function()
					ctx.nativeStyle.setTheme("Light")
					return ctx.nativeStyle.info()
				end,
				themeDark = function()
					ctx.nativeStyle.setTheme("Dark")
					return ctx.nativeStyle.info()
				end,
				-- NSS-A7: reduced-motion strip / restore
				stripTransitions = function()
					ctx.nativeStyle.setTransitionsEnabled(false)
					return true
				end,
				restoreTransitions = function()
					ctx.nativeStyle.setTransitionsEnabled(true)
					return true
				end,
				-- NSS-A3/A6: mount identity snapshot (compare across edits/swaps)
				identity = function()
					return ctx.nativeStyle.mountIdentity()
				end,
				-- grip focus: native mode must paint via the "Grip focus" tag
				-- rule, never an explicit write (arch verifier fix)
				focusGrip = function()
					return ctx.presenter.focus.focusOn("/NativeStyle/Body/SurfaceRow/Grip")
				end,
				focusRowA = function()
					return ctx.presenter.focus.focusOn("/NativeStyle/Body/Panel/RowA")
				end,
				styledExtras = function()
					return {
						chip = ctx.nativeStyle.styledOf("/NativeStyle/Body/SurfaceRow/Chip", "BackgroundColor3"),
						badge = ctx.nativeStyle.styledOf("/NativeStyle/Body/SurfaceRow/Badge", "BackgroundColor3"),
						scrimT = ctx.nativeStyle.styledOf(
							"/NativeStyle/Body/SurfaceRow/ScrimPatch",
							"BackgroundTransparency"
						),
						plainT = ctx.nativeStyle.styledOf(
							"/NativeStyle/Body/SurfaceRow/PlainBtn",
							"BackgroundTransparency"
						),
						gripFill = ctx.nativeStyle.styledOf("/NativeStyle/Body/SurfaceRow/Grip", "BackgroundColor3"),
						gripT = ctx.nativeStyle.styledOf("/NativeStyle/Body/SurfaceRow/Grip", "BackgroundTransparency"),
					}
				end,
				-- resolved styled reads for the probe matrix
				styledPanel = function()
					return {
						panel = ctx.nativeStyle.styledOf("/NativeStyle/Body/Panel", "BackgroundColor3"),
						rowA = ctx.nativeStyle.styledOf("/NativeStyle/Body/Panel/RowA", "BackgroundColor3"),
						rowB = ctx.nativeStyle.styledOf("/NativeStyle/Body/Panel/RowB", "BackgroundColor3"),
						primary = ctx.nativeStyle.styledOf("/NativeStyle/Body/Panel/Primary", "BackgroundColor3"),
						title = ctx.nativeStyle.styledOf("/NativeStyle/Body/Title", "TextColor3"),
						subtitle = ctx.nativeStyle.styledOf("/NativeStyle/Body/Subtitle", "TextColor3"),
						rowBText = ctx.nativeStyle.styledOf("/NativeStyle/Body/Panel/RowB", "TextTransparency"),
					}
				end,
				resolveTokens = function()
					return {
						darkControl = ctx.nativeStyle.resolveToken("Dark", "Control"),
						darkSurfaceStrong = ctx.nativeStyle.resolveToken("Dark", "SurfaceStrong"),
						lightControl = ctx.nativeStyle.resolveToken("Light", "Control"),
					}
				end,
			},
			dispose = nil,
			report = function()
				return {
					native = ctx.nativeStyle.info(),
					selectedA = selectedA:get(),
					selectedB = selectedB:get(),
					rowBEnabled = rowBEnabled:get(),
				}
			end,
		}
	end,
}
