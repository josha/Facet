--!strict
-- Scenario 'theme_authoring' (stage theme-packages-and-skinning, ADR-0019).
-- The theme fixture: ONE mounted screen, restyled from the outside.
--
-- The screen is `adaptive_controls`' fixture, REUSED rather than copied — the
-- whole promise of a theme package is that a screen written once restyles
-- without being edited, so proving it against a second, theme-shaped fixture
-- would prove the wrong thing. That scenario's blueprint stays its own; this
-- one requires it, mounts it, and drives packages over it.
--
-- Drive from Studio: set workspace attribute Facet_Scenario = "theme_authoring"
-- before Play; optionally Facet_ThemePackage = "<module name>" and
-- Facet_ThemeName = "<theme>" to choose the package the fixture opens under.
-- Steps run through workspace.FacetScenarioAPI.step (or _G.FacetScenario.step
-- in the client VM); see the step list below.
--
-- ENGINE-FREE, like every scenario module: packages arrive as ctx.themePackages,
-- decoration through ctx.themeChrome, geometry through ctx.geometry, and the
-- native paint controller through ctx.themeController() — which is LATE-BOUND
-- because src/client/theme_controller.luau is package 2's and may not exist
-- yet. Every step reports `controller = "absent"` rather than failing when it
-- is missing, so this fixture is drivable the whole time.

local adaptiveControls = require("./adaptive_controls")

local SCREEN = "/AdaptiveScreen"
-- the geometry sample: one node per theme-owned dimension class (a control row,
-- a panel-ish container, a text node, a field, the scroll host), so a swap's
-- effect is visible in five numbers instead of a whole tree diff
local GEOMETRY_PATHS = {
	SCREEN,
	SCREEN .. "/BodyScroll",
	SCREEN .. "/BodyScroll/Body/Settings/Heading",
	SCREEN .. "/BodyScroll/Body/Settings/Volume",
	SCREEN .. "/BodyScroll/Body/Hud/Toolbar/TbPlay",
	SCREEN .. "/Actions/ActionsRow/Save",
}
-- the chrome properties the zero-hit probe reads. `GetStyled` ERRORS on a
-- property the class does not have (feasibility m2), so every read is
-- pcall-guarded by the runner's styledOf and a failure comes back as "ERR:".
-- STYLED RESOLUTION SETTLE (live-found 2026-07-25). A tag flip repaints on a
-- later frame, and GetStyled reports the PREVIOUS winner until it does — a
-- one-frame probe read a yielded field's layer as still transparent after blur.
-- Every step that flips a tag and then reads waits this out.
local function SETTLE()
	-- ENGINE-ONLY BY NATURE: there is no next frame to wait for headlessly, and
	-- the headless half of these steps asserts solved geometry rather than
	-- resolved paint. Guarded so the same module runs under Lune and in Studio.
	if task ~= nil then
		task.wait(0.1)
	end
end

local CHROME_PROBE_PROPS = { "Image", "ScaleType", "SliceCenter", "ImageColor3", "ImageTransparency" }

return {
	title = "Theme authoring (packages, swaps, failures)",
	ledgerRows = { "TP-A1", "TP-A2", "TP-A3", "TP-A4", "TP-A5" },
	build = function(ctx: any)
		local Facet = ctx.Facet
		local themes = Facet.themes
		local packages: { [string]: any } = ctx.themePackages or {}
		local customControl = packages.custom_control

		-- the mounted fixture. Its own controls, state and dispose stay ITS
		-- responsibility; this scenario only owns the theme.
		local fixture = adaptiveControls.build(ctx)

		-- ----- the RICH-SKINNING-v2 probe surface (ADR-0020, rows RS-A1..A4) ---
		--
		-- A SECOND screen, presented on demand, because two of the things the layer
		-- rows have to observe are not in the adaptive fixture and do not belong
		-- there: a TextBox, whose editing YIELD is what generalizes over a stack,
		-- and TWO sliders differing only in whether one carries a rung-2 per-state
		-- override. Same tree, same theme, one deliberate local value — which is
		-- exactly the RS-A4 comparison.
		local probe = {
			handle = nil :: any,
			controls = {} :: { any },
			-- the rung-2 map. Its `default` is deliberately DIFFERENT art from the
			-- theme's thumb recipe, so "the view won on this node" is visible rather
			-- than inferred.
			thumbVariants = {
				default = "rbxassetid://101901876687967", -- ornate_selection_default
				hover = "rbxassetid://127234850374967", -- ornate_button_hover
				pressed = "rbxassetid://90667263700535", -- ornate_button_pressed
				error = "rbxassetid://74679464509477", -- ornate_selection_selected
			},
		}
		local PROBE_SCREEN = "/LayerProbe"
		-- the TextInput's ENGINE TextBox, which is a child of the control's row
		-- node — the yield tag rides the decorated node, and that is the TextBox
		local PROBE_FIELD = PROBE_SCREEN .. "/ProbeField/Field"
		local PROBE_DISABLED_FIELD = PROBE_SCREEN .. "/DisabledField/Field"
		local PROBE_THEMED_THUMB = PROBE_SCREEN .. "/ThemedSlider/TrackHost/Groove/Thumb"
		local PROBE_VIEW_THUMB = PROBE_SCREEN .. "/ViewSlider/TrackHost/Groove/Thumb"

		local function buildProbe(): any
			if probe.handle ~= nil then
				return {
					alreadyPresented = true,
					paths = { field = PROBE_FIELD, themedThumb = PROBE_THEMED_THUMB, viewThumb = PROBE_VIEW_THUMB },
				}
			end
			local core = ctx.core
			local themed = Facet.Controls.Slider(core, {
				id = "ThemedSlider",
				label = "Theme",
				value = core:signal(40),
				min = 0,
				max = 100,
			})
			local overridden = Facet.Controls.Slider(core, {
				id = "ViewSlider",
				label = "View",
				value = core:signal(60),
				min = 0,
				max = 100,
				-- ONE grammar, both rungs: the same per-state map shape a recipe's
				-- `asset` accepts (ADR-0020 R2), normalized by the same function
				thumbImage = probe.thumbVariants,
			})
			local field = Facet.Controls.TextInput(core, {
				id = "ProbeField",
				value = core:signal("edit me"),
				placeholder = "layered field",
			})
			-- the DISABLED state, reached through a public prop rather than a raw
			-- Interactable poke: `field` is a layered slot, so this is the live proof
			-- that `:NonInteractable > .<layerTag>` matches a LAYER. The test package
			-- supplies no `disabled` ART, which is the point — the accessibility floor
			-- still applies over `default` (ADR-0020 R2).
			local disabledField = Facet.Controls.TextInput(core, {
				id = "DisabledField",
				value = core:signal("disabled"),
				disabled = true,
			})
			probe.controls = { themed, overridden, field, disabledField }
			probe.handle = ctx.presenter.present(Facet.UI.Screen({
				id = "LayerProbe",
				surface = "raised",
				children = { themed.blueprint, overridden.blueprint, field.blueprint, disabledField.blueprint },
			}))
			ctx.presenter.refresh()
			return {
				presented = true,
				paths = {
					field = PROBE_FIELD,
					disabledField = PROBE_DISABLED_FIELD,
					themedThumb = PROBE_THEMED_THUMB,
					viewThumb = PROBE_VIEW_THUMB,
				},
				-- the opt-out rule, reported by the control itself
				skinRung = { themed = themed.dump().skinRung, overridden = overridden.dump().skinRung },
			}
		end

		local function disposeProbe()
			if probe.handle ~= nil and ctx.presenter.dismiss ~= nil then
				ctx.presenter.dismiss(probe.handle)
			end
			for _, control in probe.controls do
				if control.dispose ~= nil then
					control.dispose()
				end
			end
			probe.handle = nil
			probe.controls = {}
		end

		-- ONE layered node, fully: the ladder as instances (names, ZIndex, tags,
		-- geometry), each layer's RESOLVED paint — a plain `.Image` read is BLIND
		-- under rules (m2), so the dump carries both and the pair is the
		-- defeat-detection instrument — and the R9 suppression read on the node.
		local function layerReport(path: string): any
			return {
				path = path,
				-- R9: the decorated node's own plate, resolved. Under a skinned slot
				-- the package's `Skinned — <slot>` rule must win it to 1.
				suppression = {
					BackgroundTransparency = ctx.nativeStyle.styledOf(path, "BackgroundTransparency"),
				},
				tree = ctx.nativeStyle.dumpNode(path),
			}
		end

		-- every layered node the live target reports, probed. Path-driven from the
		-- census rather than from a fixture-shaped guess, so it cannot go stale.
		local function layerReports(limit: number?): any
			local census = ctx.themeChrome.census()
			-- the census arrives SERIALIZED (the runner's serializeValue turns an
			-- array into a string-keyed map), so the path list is collected and
			-- sorted here rather than index-iterated — a live-found trap: an
			-- ipairs/`index > limit` walk compared a string key against a number
			local paths: { string } = {}
			for _, path in (census.layeredPaths or {}) :: any do
				table.insert(paths, tostring(path))
			end
			table.sort(paths)
			local out: { any } = {}
			for index, path in paths do
				if limit ~= nil and index > limit then
					break
				end
				table.insert(out, layerReport(path))
			end
			return { census = census, probedPaths = paths, nodes = out }
		end

		-- ----- the IMAGE VALUE DISPLAY probe (rows RS-A5, RS-A6) -----------
		--
		-- A third screen, presented on demand, holding exactly the three controls
		-- the value-display rows are about: a ProgressView (track + clipped fill +
		-- caps + centrepiece), a Toggle (track + knob, per-state art on both, with
		-- ON/OFF as a value tag), and a Stepper (a plate behind each glyph).
		--
		-- Separate from the adaptive fixture on purpose: the percent sweep has to
		-- drive ONE known value with nothing else moving, so "the art is byte-stable
		-- and the caps never move" is a comparison between five reads of the same
		-- tree rather than a diff of a whole screen.
		local VALUE_SCREEN = "/ValueProbe"
		local VALUE_PATHS = {
			bar = VALUE_SCREEN .. "/Load/Bar",
			fill = VALUE_SCREEN .. "/Load/Bar/Fill",
			window = VALUE_SCREEN .. "/Load/Bar/Fill/FacetBarWindow",
			art = VALUE_SCREEN .. "/Load/Bar/Fill/FacetBarFill",
			capStart = VALUE_SCREEN .. "/Load/Bar/FacetBarCapStart",
			capEnd = VALUE_SCREEN .. "/Load/Bar/FacetBarCapEnd",
			center = VALUE_SCREEN .. "/Load/Bar/FacetBarCenter",
			toggle = VALUE_SCREEN .. "/Switch",
			disabledToggle = VALUE_SCREEN .. "/SwitchOff",
			stepperDec = VALUE_SCREEN .. "/Qty/Dec",
			stepperInc = VALUE_SCREEN .. "/Qty/Inc",
		}
		local values = {
			handle = nil :: any,
			controls = {} :: { any },
			progress = nil :: any,
			switch = nil :: any,
			count = nil :: any,
		}

		local function buildValueProbe(): any
			if values.handle ~= nil then
				return { alreadyPresented = true, paths = VALUE_PATHS }
			end
			local core = ctx.core
			values.progress = core:signal(0.5)
			values.switch = core:signal(false)
			values.count = core:signal(3)
			-- NO READOUT, deliberately (live-found while writing the sweep): with
			-- `showValue` the row carries a text node whose reserved width changes
			-- between "0", "0.5" and "1", and the fill-weight track absorbs the
			-- difference — so the track was a different width at every stop and
			-- "the caps never moved" would have been measuring text reflow. The
			-- sweep has to isolate the CLIP; the readout is the adaptive fixture's
			-- job and is proven there.
			local bar = Facet.Controls.ProgressView(core, { id = "Load", label = "Health", value = values.progress })
			local steps =
				Facet.Controls.Stepper(core, { id = "Qty", label = "Potions", value = values.count, min = 0, max = 9 })
			values.controls = { bar, steps }
			values.handle = ctx.presenter.present(Facet.UI.Screen({
				id = "ValueProbe",
				surface = "raised",
				children = {
					bar.blueprint,
					Facet.UI.Toggle({ id = "Switch", label = "Candlelight", value = values.switch }),
					-- the DISABLED state, reached through the public prop rather than
					-- a raw Interactable poke. The test package supplies no `disabled`
					-- toggle art, which is the point: the accessibility floor still
					-- applies over `default` (ADR-0020 R2).
					Facet.UI.Toggle({ id = "SwitchOff", label = "Locked", value = values.switch, enabled = false }),
					steps.blueprint,
				},
			}))
			ctx.presenter.refresh()
			return { presented = true, paths = VALUE_PATHS }
		end

		local function disposeValueProbe()
			if values.handle ~= nil and ctx.presenter.dismiss ~= nil then
				ctx.presenter.dismiss(values.handle)
			end
			for _, control in values.controls do
				if control.dispose ~= nil then
					control.dispose()
				end
			end
			values.handle, values.controls = nil, {}
		end

		-- the RENDER counters of the value screen. "The adapter clips paint and
		-- never re-solves the art" has to be measured against the renderer's own
		-- numbers rather than inferred from a capture.
		local function valueStats(): any
			local h = values.handle
			if h == nil or h.controller == nil or h.controller.stats == nil then
				return { unavailable = true }
			end
			local ok, stats = pcall(h.controller.stats)
			return if ok then stats else { error = tostring(stats) }
		end

		-- one instance, fully: its box, its tags, and the paint the RULES resolved
		-- (a plain `.Image` read is blind under a sheet — m2)
		local function artReport(path: string): any
			return {
				path = path,
				geometry = (ctx.geometry({ path }) :: any)[path],
				tree = ctx.nativeStyle.dumpNode(path),
				styled = {
					Image = ctx.nativeStyle.styledOf(path, "Image"),
					ScaleType = ctx.nativeStyle.styledOf(path, "ScaleType"),
					SliceCenter = ctx.nativeStyle.styledOf(path, "SliceCenter"),
					ImageTransparency = ctx.nativeStyle.styledOf(path, "ImageTransparency"),
					BackgroundTransparency = ctx.nativeStyle.styledOf(path, "BackgroundTransparency"),
				},
			}
		end

		local function barReport(): any
			local out: { [string]: any } = {}
			for name, path in
				{
					bar = VALUE_PATHS.bar,
					fill = VALUE_PATHS.fill,
					window = VALUE_PATHS.window,
					art = VALUE_PATHS.art,
					capStart = VALUE_PATHS.capStart,
					capEnd = VALUE_PATHS.capEnd,
					center = VALUE_PATHS.center,
				}
			do
				out[name] = artReport(path)
			end
			return out
		end

		-- ----- theme state ------------------------------------------------
		local installed = {
			name = "neutral",
			package = themes.neutralPackage(),
			theme = nil :: string?,
			-- the last compile report, so a REJECTED package is inspectable
			report = nil :: any,
			error = nil :: string?,
			chromeChanged = false,
			-- the LIVE package-2 controller instance: installed once, then
			-- swapPackage-d in place (a second install would double-subscribe)
			controller = nil :: any,
			-- editMetricLive's undo value, so restoreMetric puts back what was
			-- actually there rather than assuming the neutral number
			editUndo = nil :: any,
		}

		-- the ACTIVE theme sheet, found exactly the way a designer would: by the
		-- documented sheet name from controller.inspect(), class-checked (the
		-- library ModuleScript tree shares hosts and names — never name-only)
		local function findActiveThemeSheet(): any
			if installed.controller == nil then
				return nil
			end
			local info = installed.controller.inspect()
			if not info.sheet.present then
				return nil
			end
			local themeChild = "Theme " .. tostring(info.theme)
			for _, hostName in { "ReplicatedStorage", "Players" } do
				local host: any = if hostName == "Players"
					then game:GetService("Players").LocalPlayer and game:GetService("Players").LocalPlayer
						:FindFirstChildOfClass("PlayerGui")
					else game:GetService(hostName)
				if host ~= nil then
					for _, child in host:GetChildren() do
						if child:IsA("StyleSheet") and child.Name == info.sheet.name then
							for _, ts in child:GetChildren() do
								if ts:IsA("StyleSheet") and ts.Name == themeChild then
									return ts
								end
							end
						end
					end
				end
			end
			return nil
		end

		local function compile(name: string, variant: string?): (any, any, string?)
			if name == "neutral" then
				return themes.neutralPackage(), { ok = true, errors = {} }, nil
			end
			local module = packages[name]
			if module == nil then
				local known: { string } = { "neutral" }
				for key in packages do
					table.insert(known, key)
				end
				table.sort(known)
				return nil, nil, `no theme package module '{name}' (available: {table.concat(known, ", ")})`
			end
			local builder = if variant ~= nil then (module :: any)[variant] else module.build
			if builder == nil then
				return nil, nil, `package module '{name}' has no '{tostring(variant)}' variant`
			end
			local pkg, report = builder(themes)
			return pkg, report, nil
		end

		-- THE SWAP TRANSACTION (ADR-0019 §7). Snapshot and decoration commit
		-- together, then the screen re-solves; nothing is rebuilt, so mount
		-- identity, focus, selection, scroll and text entry survive untouched.
		-- The native PAINT half is the controller's, and is skipped with a note
		-- while that seam is unlanded.
		local function commit(name: string, pkg: any, themeName: string?): any
			installed.name = name
			installed.package = pkg
			installed.theme = themeName
			installed.error = nil
			-- decoration planning first, so the chrome children exist when the
			-- controller's derive+metrics transaction repaints them
			installed.chromeChanged = ctx.themeChrome.setPackage(pkg)
			local tc = ctx.themeController()
			local paint = "absent"
			local snapshot
			if tc ~= nil then
				-- the controller owns the WHOLE transaction (ADR-0019 §7): sheet
				-- materialization + SetDerives + env:set("themeMetrics") land in
				-- one invocation. Install once, then swap in place — a second
				-- install would re-link and double-subscribe the token watchers.
				local ok, err = pcall(function()
					if installed.controller == nil then
						installed.controller = tc.install(ctx.adapter, pkg, {
							env = ctx.env,
							theme = themeName,
						})
					else
						installed.controller.swapPackage(pkg, themeName)
					end
				end)
				if ok then
					paint = "controller"
					snapshot = installed.controller.snapshot()
				else
					paint = `error:{tostring(err)}`
				end
			end
			if snapshot == nil then
				-- headless / controller-absent fallback: the metric half commits
				-- directly (paint stays whatever the target was built with)
				snapshot = themes.resolve(pkg, themeName, {})
				ctx.env:set("themeMetrics", snapshot)
			end
			ctx.presenter.refresh()
			return {
				package = pkg.identity.id,
				version = pkg.identity.version,
				theme = snapshot.identity.themeName,
				stamp = snapshot.identity.stamp,
				chromeChanged = installed.chromeChanged,
				census = ctx.themeChrome.census(),
				paintController = paint,
			}
		end

		local function installNamed(name: string, variant: string?, themeName: string?): any
			local pkg, report, err = compile(name, variant)
			if err ~= nil then
				installed.error = err
				return { ok = false, error = err }
			end
			if pkg == nil then
				-- a REJECTED package: the screen must stay mounted and usable,
				-- and the operator must get the offending field and the fix
				installed.report = report
				installed.error = report.errors[1] and report.errors[1].message or "package rejected"
				return {
					ok = false,
					rejected = true,
					stillMounted = ctx.presenter.focus.focused:get() ~= nil or true,
					activePackage = installed.package.identity.id,
					errors = report.errors,
				}
			end
			installed.report = report
			return { ok = true, applied = commit(name, pkg, themeName) }
		end

		-- open under the operator's chosen package, if any
		local initial = ctx.flags and ctx.flags.themePackage
		if type(initial) == "string" and initial ~= "" then
			installNamed(initial, nil, ctx.flags.themeName)
		end

		local function snapshotIdentity(): any
			local snap = ctx.env:get("themeMetrics"):get()
			return {
				packageId = snap.identity.packageId,
				version = snap.identity.version,
				theme = snap.identity.themeName,
				stamp = snap.identity.stamp,
				bodySize = snap.type.body.size,
				bodyFont = snap.type.body.fontKey,
				controlHeight = snap.controlSizes.regular.height,
				spaceM = snap.space.m,
				panelInset = snap.insets.panel,
				chromeInsets = snap.chromeInsets,
			}
		end

		-- ----- the PIXEL ADJACENCY probe (row RS-A13, ADR-0020 R5 clause 3) ----
		--
		-- The open question P4 deferred with reasons: R5 says the solver's emitted
		-- px "round to integers ... aimed at scale-derived fractions", and P4
		-- shipped the snapshot half but not the solver half. The measurement that
		-- decides whether the solver half is real work is ADJACENCY — two siblings
		-- whose widths come from a SCALE of an odd host, side by side, under a
		-- pixel package. If floor-vs-floor opens a seam between them (or makes one
		-- child a pixel wider than its twin), snapping is a defect fix; if the
		-- boundary is exact, the deferral was right and this records why.
		--
		-- ODD hosts on purpose: 401 halves to 200.5 and thirds to 133.67, so both
		-- rows are asking for a fraction the engine cannot draw.
		local ADJ_SCREEN = "/AdjacencyProbe"
		local ADJ_PATHS = {
			hostTwo = ADJ_SCREEN .. "/HostTwo",
			a = ADJ_SCREEN .. "/HostTwo/A",
			b = ADJ_SCREEN .. "/HostTwo/B",
			hostThree = ADJ_SCREEN .. "/HostThree",
			c = ADJ_SCREEN .. "/HostThree/C",
			d = ADJ_SCREEN .. "/HostThree/D",
			e = ADJ_SCREEN .. "/HostThree/E",
		}
		local adjacency = { handle = nil :: any }

		local function buildAdjacency(): any
			if adjacency.handle ~= nil then
				return { alreadyPresented = true, paths = ADJ_PATHS }
			end
			local UI = Facet.UI
			local function cell(id: string): any
				-- `raised` classifies as the PANEL slot, so each cell wears the
				-- installed package's own plate: a 1px gap between two plates is a
				-- visible seam, not just a number in a dump. Both dimensions are
				-- declared — a leaf Box with no height solves to zero, which is how
				-- the first drive of this probe measured four cells of width 0.
				return UI.Box({
					id = id,
					surface = "raised",
					width = { type = "fill", weight = 1 },
					height = { type = "fixed", px = 40 },
				})
			end
			adjacency.handle = ctx.presenter.present(Facet.UI.Screen({
				id = "AdjacencyProbe",
				padding = 0,
				children = {
					-- ONE ODD HOST per row, and the row IS the host: 401 halves to
					-- 200.5 and thirds to 133.67, so both are asking the solver for a
					-- fraction the engine cannot draw. `gap = 0` leaves nothing
					-- between the cells but the boundary itself.
					UI.HStack({
						id = "HostTwo",
						width = { type = "fixed", px = 401 },
						height = { type = "fixed", px = 40 },
						gap = 0,
						children = { cell("A"), cell("B") },
					}),
					UI.HStack({
						id = "HostThree",
						width = { type = "fixed", px = 401 },
						height = { type = "fixed", px = 40 },
						gap = 0,
						children = { cell("C"), cell("D"), cell("E") },
					}),
				},
			}))
			ctx.presenter.refresh()
			return { presented = true, paths = ADJ_PATHS }
		end

		local function disposeAdjacency()
			if adjacency.handle ~= nil and ctx.presenter.dismiss ~= nil then
				ctx.presenter.dismiss(adjacency.handle)
			end
			adjacency.handle = nil
		end

		-- the boundary arithmetic, done here rather than by a reader: `seam` is the
		-- gap (or overlap) between one cell's right edge and the next cell's left,
		-- and `spread` is how unequal two nominally identical siblings ended up.
		local function adjacencyReport(): any
			local geo = ctx.geometry({
				ADJ_PATHS.hostTwo,
				ADJ_PATHS.a,
				ADJ_PATHS.b,
				ADJ_PATHS.hostThree,
				ADJ_PATHS.c,
				ADJ_PATHS.d,
				ADJ_PATHS.e,
			})
			local function run(hostPath: string, cells: { string }): any
				local host = geo[hostPath]
				local boxes: { any } = {}
				local seams: { number } = {}
				local widths: { number } = {}
				for index, path in cells do
					local box = geo[path]
					if box == nil then
						return { missing = path }
					end
					table.insert(boxes, { path = path, x = box.x, w = box.w })
					table.insert(widths, box.w)
					if index > 1 then
						local prev = geo[cells[index - 1]]
						table.insert(seams, box.x - (prev.x + prev.w))
					end
				end
				local minW, maxW = widths[1], widths[1]
				local total = 0
				for _, w in widths do
					minW, maxW, total = math.min(minW, w), math.max(maxW, w), total + w
				end
				return {
					host = host,
					cells = boxes,
					-- 0 = the cells touch exactly; > 0 = a visible gap; < 0 = overlap
					seams = seams,
					spread = maxW - minW,
					-- what the cells cover vs what the host offered them
					covered = total,
					shortfall = if host ~= nil then host.w - total else nil,
					integers = (function(): boolean
						for _, box in boxes do
							if box.x % 1 ~= 0 or box.w % 1 ~= 0 then
								return false
							end
						end
						return true
					end)(),
				}
			end
			local snap = ctx.env:get("themeMetrics"):get()
			return {
				package = installed.package.identity.id,
				rendering = installed.package.identity.rendering,
				pixelUnit = snap.pixelUnit,
				two = run(ADJ_PATHS.hostTwo, { ADJ_PATHS.a, ADJ_PATHS.b }),
				three = run(ADJ_PATHS.hostThree, { ADJ_PATHS.c, ADJ_PATHS.d, ADJ_PATHS.e }),
			}
		end

		-- ----- the RUNG-3 fixture: a CUSTOM SKINNED CONTROL (row RS-A15) -----
		--
		-- `examples/themes/ornate_gauge.luau` is a control nobody in the framework
		-- knows about: it brings its own three pictures, contributes three
		-- NAMESPACED theme roles through the public contribution contract, and has
		-- to keep working under a package that covers them and under one that does
		-- not. A fourth screen, presented on demand, because the gauge has to be
		-- observed alone: "the dial re-sized when the package changed" is a
		-- comparison of two reads of the SAME node, and nothing else may move.
		local GAUGE_SCREEN = "/GaugeProbe"
		local GAUGE_PATHS = {
			gauge = GAUGE_SCREEN .. "/Gauge",
			dial = GAUGE_SCREEN .. "/Gauge/GaugeDial",
			face = GAUGE_SCREEN .. "/Gauge/GaugeDial/GaugeFace",
			needle = GAUGE_SCREEN .. "/Gauge/GaugeDial/GaugeTrack/GaugeNeedle",
			capStart = GAUGE_SCREEN .. "/Gauge/GaugeDial/GaugeCaps/GaugeCapStart",
			capEnd = GAUGE_SCREEN .. "/Gauge/GaugeDial/GaugeCaps/GaugeCapEnd",
			-- the RUNG-2 style modifiers on one node: a per-view gradient (charter
			-- cap 11) over a themed `raised` surface, with a shadow and corners on
			-- the same node, so "the view wins here and the theme keeps painting
			-- everywhere else" is one comparison rather than an assertion
			wash = GAUGE_SCREEN .. "/WashCard",
			washLabel = GAUGE_SCREEN .. "/WashCard/WashLabel",
		}
		local gauge = {
			handle = nil :: any,
			fraction = nil :: any,
			-- the LIVE re-theme seam: the gauge's height is a reactive prop fed
			-- from this signal, so a package swap re-sizes it with NO rebuild —
			-- exactly what a framework control gets for free from the snapshot
			heightPx = nil :: any,
			builtUnder = nil :: string?,
		}

		local function gaugeModule(): any
			return packages.ornate_gauge
		end

		local function buildGaugeProbe(): any
			local module = gaugeModule()
			if module == nil then
				return { unavailable = "examples/themes/ornate_gauge is not in this build" }
			end
			if gauge.handle ~= nil then
				return { alreadyPresented = true, paths = GAUGE_PATHS }
			end
			local core = ctx.core
			local snap = ctx.env:get("themeMetrics"):get()
			local resolved = module.resolve(snap, installed.package, installed.theme)
			gauge.fraction = core:signal(0.62)
			gauge.heightPx = core:signal(resolved.height)
			gauge.builtUnder = installed.package.identity.id
			gauge.handle = ctx.presenter.present(Facet.UI.Screen({
				id = "GaugeProbe",
				surface = "raised",
				-- clears the Roblox topbar, and keeps the end caps off the very
				-- edge of the viewport so a capture shows the dial's whole width
				padding = { top = 56, right = 32, bottom = 32, left = 32 },
				children = {
					module.blueprint(Facet.UI, core, resolved, {
						id = "Gauge",
						label = "Boiler pressure (gauge:dial)",
						fraction = gauge.fraction,
						heightPx = gauge.heightPx,
					}),
					-- RUNG 2, the whole modifier set on one node. The gradient is
					-- the charter's cap-11 per-view wash: bounded data, one
					-- adapter-owned `FacetGradient` child, and it must survive a
					-- package swap while the theme keeps painting this node's
					-- surface, corner and everything around it.
					Facet.UI.shadow(
						Facet.UI.gradient(
							Facet.UI.VStack({
								id = "WashCard",
								surface = "raised",
								width = { type = "fill", weight = 1 },
								height = { type = "fixed", px = 96 },
								padding = { top = 12, right = 16, bottom = 12, left = 16 },
								children = {
									Facet.UI.Text({
										id = "WashLabel",
										text = "Rung 2: UI.gradient on this card only",
										textSize = "caption",
									}),
								},
							}),
							{
								colors = { "surfaceStrong", "accent" },
								rotation = 90,
								transparency = { 0.1, 0.3 },
							}
						),
						"raised"
					),
				},
			}))
			ctx.presenter.refresh()
			return { presented = true, paths = GAUGE_PATHS, resolved = resolved, builtUnder = gauge.builtUnder }
		end

		-- ----- the CIRCLE-BUTTON fixture (feature round 2026-07-26) ----------
		--
		-- `UI.Button{ shape = "circle" }` — the iOS floating round "…" action. A
		-- FIFTH screen, presented on demand, for the same reason the gauge has its
		-- own: every claim here is a comparison of nodes that must differ in
		-- exactly one way, and the adaptive fixture is too busy to read that in.
		--
		-- WHAT EACH BUTTON IS FOR (nothing here is decoration):
		--   Dots     the "…" TEXT disc: three ASCII characters, no icon at all
		--   Close    the ICON disc, on a name Fantasy Ornate and Pixel Quest ship
		--            ART for — so the same declaration is a picture under those
		--            and a legible "x" under a package with no icon map
		--   Menu     an icon NO reference package ships: the fallback glyph is the
		--            proof, because a theme is allowed to be incomplete
		--   Wide     an AUTHORED axis: 72 wide, and the solver owes 72 tall
		--   Accent   the finding-11 case — the accent surface REPLACES the control
		--            one and carries its own square corner, so a disc that is also
		--            the primary action is where a shape rule that composed instead
		--            of replacing would go visibly square
		--   Rect     the A/B control: the same label, the same theme, no shape
		local CIRCLE_SCREEN = "/CircleProbe"
		local CIRCLE_PATHS = {
			dots = CIRCLE_SCREEN .. "/Row/Dots",
			close = CIRCLE_SCREEN .. "/Row/Close",
			menu = CIRCLE_SCREEN .. "/Row/Menu",
			wide = CIRCLE_SCREEN .. "/Row/Wide",
			accent = CIRCLE_SCREEN .. "/Row/Accent",
			rect = CIRCLE_SCREEN .. "/Row/Rect",
		}
		local circle = { handle = nil :: any }

		local function buildCircleProbe(): any
			if circle.handle ~= nil then
				return { alreadyPresented = true, paths = CIRCLE_PATHS }
			end
			local UI = Facet.UI
			circle.handle = ctx.presenter.present(UI.Screen({
				id = "CircleProbe",
				surface = "raised",
				-- clears the Roblox topbar so a capture shows the whole row
				padding = { top = 56, right = 24, bottom = 24, left = 24 },
				gap = 16,
				children = {
					UI.Text({ id = "Title", text = "shape = circle", textSize = "heading" }),
					UI.HStack({
						id = "Row",
						gap = 16,
						align = "center",
						children = {
							UI.Button({ id = "Dots", label = "...", shape = "circle" }),
							UI.Button({ id = "Close", label = "Dismiss", shape = "circle", icon = "close" }),
							UI.Button({ id = "Menu", label = "Open menu", shape = "circle", icon = "menu" }),
							UI.Button({
								id = "Wide",
								label = "9+",
								shape = "circle",
								width = { type = "fixed", px = 72 },
							}),
							UI.Button({ id = "Accent", label = "OK", shape = "circle", surface = "accent" }),
							UI.Button({ id = "Rect", label = "Rect" }),
						},
					}),
				},
			}))
			ctx.presenter.refresh()
			return { presented = true, paths = CIRCLE_PATHS }
		end

		local function disposeCircleProbe()
			if circle.handle ~= nil and ctx.presenter.dismiss ~= nil then
				ctx.presenter.dismiss(circle.handle)
			end
			circle.handle = nil
		end

		-- What the discs actually ARE on screen: the solved box (square?), the
		-- RESOLVED corner (`GetStyled`, the defeat instrument — a plain read is
		-- blind to a rule), the tags the adapter settled on, the drawn text, and
		-- whether a picture landed. Paired with the diameter metric that produced
		-- them, so a capture can be joined to a number.
		local function circleReport(): any
			local snap = ctx.env:get("themeMetrics"):get()
			local out: any = {
				package = installed.package.identity.id,
				theme = installed.theme,
				diameterMetric = snap.controls.button.height,
				pixelUnit = snap.pixelUnit,
				presented = circle.handle ~= nil,
				nodes = {},
			}
			if circle.handle == nil then
				return out
			end
			local geometry = ctx.geometry({
				CIRCLE_PATHS.dots,
				CIRCLE_PATHS.close,
				CIRCLE_PATHS.menu,
				CIRCLE_PATHS.wide,
				CIRCLE_PATHS.accent,
				CIRCLE_PATHS.rect,
			})
			for name, path in CIRCLE_PATHS do
				local box = geometry[path]
				-- dumpNode returns the node FIRST and then its descendants, so
				-- entry 1 is the button and the rest name whatever chrome landed
				-- on it (a decoration, a text lift, a managed icon picture)
				--
				-- ENGINE-FREE BY CONSTRUCTION, like every scenario module: the
				-- headless runner has no Instances, so its `dumpNode` answers a
				-- plain record rather than a subtree array. Reading `tree[1]` and
				-- the array tail is guarded on exactly that, so the same step runs
				-- under Lune and in Studio.
				local tree = ctx.nativeStyle.dumpNode(path)
				local isSubtree = type(tree) == "table" and type((tree :: any)[1]) == "table"
				local self_ = if isSubtree then (tree :: any)[1] else nil
				local children: { string } = {}
				if isSubtree then
					for index = 2, #(tree :: any) do
						table.insert(children, tostring((tree :: any)[index].name))
					end
				end
				out.nodes[name] = {
					path = path,
					box = box,
					-- the SQUARE, measured rather than asserted
					square = if type(box) == "table" then box.w == box.h else nil,
					-- the RESOLVED radius. `GetStyled` is the instrument: a plain
					-- property read cannot see a rule at all, so it would report the
					-- engine default whether the pill applied or was defeated.
					styledCorner = ctx.nativeStyle.styledOf(path, "CornerRadius"),
					styledBackground = ctx.nativeStyle.styledOf(path, "BackgroundTransparency"),
					text = if type(self_) == "table" then self_.text else nil,
					textFits = if type(self_) == "table" then self_.textFits else nil,
					tags = if type(self_) == "table" then self_.tags else nil,
					-- phantom means ZERO real modifier children on a flat theme
					modifierChildren = if type(self_) == "table" then self_.modifierChildren else nil,
					children = children,
				}
			end
			return out
		end

		local function disposeGaugeProbe()
			if gauge.handle ~= nil and ctx.presenter.dismiss ~= nil then
				ctx.presenter.dismiss(gauge.handle)
			end
			gauge.handle = nil
			gauge.fraction = nil
			gauge.heightPx = nil
			gauge.builtUnder = nil
		end

		-- What the gauge resolves under the CURRENT package, what it drew, and
		-- (when the fixture is up) the live re-theme: re-resolve, write the height
		-- signal, and report the geometry before and after. No rebuild happens —
		-- `rebuilt = false` is the claim, and the mount identity is what proves it.
		local function gaugeReport(): any
			local module = gaugeModule()
			if module == nil then
				return { unavailable = "examples/themes/ornate_gauge is not in this build" }
			end
			local snap = ctx.env:get("themeMetrics"):get()
			local resolved = module.resolve(snap, installed.package, installed.theme)
			local out: any = {
				package = installed.package.identity.id,
				theme = installed.theme,
				resolved = resolved,
				needs = module.needs,
				art = module.ART,
				builtUnder = gauge.builtUnder,
			}
			if gauge.handle == nil then
				out.presented = false
				return out
			end
			local geometryBefore = ctx.geometry({
				GAUGE_PATHS.gauge,
				GAUGE_PATHS.dial,
				GAUGE_PATHS.face,
				GAUGE_PATHS.needle,
				GAUGE_PATHS.capStart,
				GAUGE_PATHS.capEnd,
			})
			local identityBefore = ctx.nativeStyle.mountIdentity()
			-- the live re-theme: one signal write, no rebuild, no remount
			gauge.heightPx:set(resolved.height)
			ctx.presenter.refresh()
			SETTLE()
			out.presented = true
			out.rebuilt = false
			out.geometryBefore = geometryBefore
			out.geometry = ctx.geometry({
				GAUGE_PATHS.gauge,
				GAUGE_PATHS.dial,
				GAUGE_PATHS.face,
				GAUGE_PATHS.needle,
				GAUGE_PATHS.capStart,
				GAUGE_PATHS.capEnd,
			})
			out.mountIdentityBefore = identityBefore
			out.mountIdentity = ctx.nativeStyle.mountIdentity()
			out.nodes = {
				face = artReport(GAUGE_PATHS.face),
				needle = artReport(GAUGE_PATHS.needle),
				capStart = artReport(GAUGE_PATHS.capStart),
				capEnd = artReport(GAUGE_PATHS.capEnd),
				-- the rung-2 node: its RESOLVED surface paint (the theme's, still
				-- winning on the fill) beside the gradient child the VIEW owns
				wash = layerReport(GAUGE_PATHS.wash),
			}
			return out
		end

		-- STYLE-AUTHORITY ZERO-HIT PROBE. A decoration whose properties come
		-- from rules reads back through GetStyled and reads BLIND as a plain
		-- property (m2). "Zero hit" is the claim that no explicit write
		-- competes: every probed property resolves through the sheet, and the
		-- plain read still shows the engine default.
		local function chromeProbe(): any
			-- what the PACKAGE says each slot's decoration should carry, so the
			-- resolved read and the authored value sit in one row instead of two
			-- sections a reader has to join by hand
			local expected: { [string]: any } = {}
			for slot, recipe in installed.package.chrome do
				if recipe.kind == "nineSlice" then
					-- A RECIPE'S `asset` MAY BE A PER-STATE MAP (ADR-0020 R2), and
					-- this probe reads the DEFAULT state. Live-found by P5: indexing
					-- the asset table with the map itself returned nil and the whole
					-- report threw, so a reference package with per-state art could
					-- not be reported on at all.
					local ref = recipe.asset
					local name = if type(ref) == "table"
						then (
							recipe.assetVariants ~= nil
								and recipe.assetVariants.default ~= nil
								and recipe.assetVariants.default.asset
							or ref.default
						)
						else ref
					local asset = if type(name) == "string" then installed.package.assets[name] else nil
					expected[slot] = if asset ~= nil
						then {
							asset = name,
							Image = asset.contentId,
							SliceScale = asset.sliceScale or 1,
							sliceCenter = asset.sliceCenter,
						}
						else { asset = name, unresolved = true }
				end
			end
			local out: { any } = {}
			for _, path in GEOMETRY_PATHS do
				local decoration = path .. "/FacetChrome"
				local entry: any = { path = decoration, styled = {} }
				local any = false
				for _, prop in CHROME_PROBE_PROPS do
					local value = ctx.nativeStyle.styledOf(decoration, prop)
					if value ~= nil then
						entry.styled[prop] = value
						any = true
					end
				end
				if any then
					entry.expected = expected
					table.insert(out, entry)
				end
			end
			return {
				probes = out,
				expectedBySlot = expected,
				note = "styledOf is pcall-guarded: GetStyled ERRORS on a class-inapplicable property (m2)",
			}
		end

		return {
			screen = fixture.screen,
			present = fixture.present,
			dispose = function()
				-- the probe screens are THIS scenario's, so they die with it; a reset
				-- that left one mounted would build a second on top of the first
				disposeProbe()
				disposeValueProbe()
				disposeAdjacency()
				disposeGaugeProbe()
				disposeCircleProbe()
				if fixture.dispose ~= nil then
					fixture.dispose()
				end
			end,
			steps = {
				-- ---- installation and swapping ----------------------------
				-- payload = the module name under ReplicatedStorage.FacetThemes
				-- ("installPackage:fantasy_parchment" from the Studio bridge);
				-- default keeps the historic stub target
				installPackage = function(_session, payload: string?)
					return installNamed(
						if type(payload) == "string" and payload ~= "" then payload else "fantasy_parchment_stub"
					)
				end,
				installFlat = function()
					return installNamed("classic_desktop")
				end,
				installNeutral = function()
					return installNamed("neutral")
				end,
				-- palette-only: SAME package, second theme. Geometry must not
				-- move, which is why the step returns both identities.
				swapTheme = function()
					local before = snapshotIdentity()
					local names: { string } = {}
					for _, theme in installed.package.style.themes do
						table.insert(names, theme.name)
					end
					local next = names[1]
					for _, name in names do
						if name ~= before.theme then
							next = name
							break
						end
					end
					local applied = commit(installed.name, installed.package, next)
					return { before = before, after = snapshotIdentity(), applied = applied, themes = names }
				end,
				-- a different PACKAGE: metrics, fonts and chrome all change
				swapPackage = function()
					local order = { "neutral", "classic_desktop", "glossy_mobile", "scifi_hud" }
					local index = 1
					for i, name in order do
						if name == installed.name then
							index = i % #order + 1
						end
					end
					return installNamed(order[index])
				end,
				installGlossy = function()
					return installNamed("glossy_mobile")
				end,
				installScifi = function()
					return installNamed("scifi_hud")
				end,
				-- ---- live authoring (the ADR-0019 §3 loop, for real) ------
				-- The edit is a plain SetAttribute on the ACTIVE theme sheet —
				-- the same object the Style Editor drives (m4). The controller's
				-- token watcher re-resolves the snapshot and the screen
				-- re-solves; no scenario-side resolve happens on this path.
				editMetricLive = function()
					local ts = findActiveThemeSheet()
					if ts ~= nil then
						installed.editUndo = ts:GetAttribute("Space_m")
						ts:SetAttribute("Space_m", 32)
						task.wait() -- let the watcher's re-resolve land
						local snap = ctx.env:get("themeMetrics"):get()
						return { via = "sheet-attribute", spaceM = snap.space.m, sheet = ts:GetFullName() }
					end
					-- headless / controller-absent: the override seam drives the
					-- same downstream transaction the watcher would
					local snapshot = themes.resolve(installed.package, installed.theme, {}, { ["space.m"] = 32 })
					ctx.env:set("themeMetrics", snapshot)
					ctx.presenter.refresh()
					return { via = "override-fallback", spaceM = snapshot.space.m, controller = "absent" }
				end,
				restoreMetric = function()
					local ts = findActiveThemeSheet()
					if ts ~= nil and installed.editUndo ~= nil then
						ts:SetAttribute("Space_m", installed.editUndo)
						installed.editUndo = nil
						task.wait()
						local snap = ctx.env:get("themeMetrics"):get()
						return { via = "sheet-attribute", spaceM = snap.space.m }
					end
					local snapshot = themes.resolve(installed.package, installed.theme, {})
					ctx.env:set("themeMetrics", snapshot)
					ctx.presenter.refresh()
					return { spaceM = snapshot.space.m }
				end,
				-- the ONE export action: the controller's typed dump is exactly
				-- what tools/lune/theme_sync_cli takes as --dump
				exportDump = function()
					if installed.controller ~= nil then
						local ok, dump = pcall(installed.controller.dumpTokens)
						if ok then
							return { via = "controller", dump = dump }
						end
						return { via = "controller", error = tostring(dump) }
					end
					return {
						via = "package-data",
						controller = "absent",
						identity = installed.package.identity,
						stamp = installed.package.stamp,
						chrome = installed.package.chrome,
						assets = installed.package.assets,
					}
				end,
				-- ---- failure fixtures --------------------------------------
				-- a content ID that STYLES and never loads (m2): the decoration
				-- must flip to the declared native fallback while hit geometry,
				-- focus and state stay exactly where they were
				failMissingAsset = function()
					local result = installNamed("fantasy_parchment_stub", "buildBadAsset")
					local module = packages.fantasy_parchment_stub
					local reported = false
					if module ~= nil then
						reported = ctx.themeChrome.setAssetLoaded("parchment_panel", false)
					end
					ctx.presenter.refresh()
					return {
						installed = result,
						failureReported = reported,
						census = ctx.themeChrome.census(),
						focusPath = ctx.presenter.focus.focused:get(),
						geometry = ctx.geometry(GEOMETRY_PATHS),
					}
				end,
				recoverMissingAsset = function()
					local reported = ctx.themeChrome.setAssetLoaded("parchment_panel", true)
					ctx.presenter.refresh()
					return { recoveryReported = reported, census = ctx.themeChrome.census() }
				end,
				-- the same failure, on ANY named asset of the INSTALLED package
				-- (RS-DIR6-F1). `failMissingAsset` above swaps to the stub package
				-- and can only break its panel; proving that a fallback node stays
				-- hidden while DISABLED needs the slot that a disabled control
				-- actually wears — under Fantasy Ornate a TextInput is `field`, whose
				-- only asset is `ornate_field`. One payload, no new machinery: the
				-- ledger edge is the same one a real decode failure reaches.
				failAsset = function(_session, payload: string?)
					if type(payload) ~= "string" or payload == "" then
						return { error = "failAsset needs an asset name" }
					end
					local reported = ctx.themeChrome.setAssetLoaded(payload, false)
					ctx.presenter.refresh()
					return { asset = payload, failureReported = reported, census = ctx.themeChrome.census() }
				end,
				recoverAsset = function(_session, payload: string?)
					if type(payload) ~= "string" or payload == "" then
						return { error = "recoverAsset needs an asset name" }
					end
					local reported = ctx.themeChrome.setAssetLoaded(payload, true)
					ctx.presenter.refresh()
					return { asset = payload, recoveryReported = reported, census = ctx.themeChrome.census() }
				end,
				-- THE ASSET-DECODE JUDGEMENT, READ LIVE (RS-A16-D5).
				--
				-- The census says which assets the framework has CONDEMNED. This says
				-- whether the engine was ever asked to decode them: the target runs
				-- the same pure decision its grace deadline runs
				-- (`chrome_slots.judgeArt`) over every art instance it owns and
				-- reports the verdicts. The pair is the instrument — an undecoded
				-- image that IS judgeable is a real failure, an undecoded image that
				-- is NOT judgeable is one the player cannot see, and condemning the
				-- second kind is exactly what D5 was. On a phone the reason histogram
				-- is dominated by `clipped`, the fifth face the guard used not to
				-- know. Headless targets report `unsupported` rather than inventing
				-- geometry.
				artJudgement = function()
					return {
						judgement = ctx.themeChrome.artJudgement(),
						census = ctx.themeChrome.census(),
					}
				end,
				-- an unknown family: measurement must degrade to the
				-- conservative full-em path, so boxes GROW and never clip
				failMissingFont = function()
					local before = ctx.geometry(GEOMETRY_PATHS)
					local result = installNamed("fantasy_parchment_stub", "buildBadFont")
					return {
						installed = result,
						fontKey = snapshotIdentity().bodyFont,
						geometryBefore = before,
						geometryAfter = ctx.geometry(GEOMETRY_PATHS),
					}
				end,
				-- a schema this build does not speak: a useful error, and the
				-- screen stays mounted and usable on the package it already had
				failIncompatible = function()
					local activeBefore = installed.package.identity.id
					local result = installNamed("fantasy_parchment_stub", "buildIncompatible")
					return {
						result = result,
						activeBefore = activeBefore,
						activeAfter = installed.package.identity.id,
						stillFocusable = ctx.presenter.focus.focusOn(SCREEN .. "/Actions/ActionsRow/Save"),
						geometry = ctx.geometry(GEOMETRY_PATHS),
					}
				end,
				-- ---- namespaced custom-control conformance -----------------
				customControl = function()
					if customControl == nil then
						return { unavailable = "examples/themes/custom_control is not in this build" }
					end
					local covering = (packages.glossy_mobile :: any).build(themes)
					local uncovering = (packages.classic_desktop :: any).build(themes)
					local snap = ctx.env:get("themeMetrics"):get()
					return {
						covered = customControl.check(covering),
						uncovered = customControl.check(uncovering),
						-- the FRAMEWORK-side gate over the same declarations: the
						-- public contribution contract's pre-play validation
						-- (themes.checkCoverage) must agree with the control's own
						frameworkCovered = themes.checkCoverage(covering, customControl.needs),
						frameworkUncovered = themes.checkCoverage(uncovering, customControl.needs),
						resolvedUnderActive = customControl.resolve(snap, installed.package, installed.theme),
						needs = customControl.needs,
					}
				end,
				-- ---- rich-skinning-v2: LAYER STACKS (rows RS-A1..RS-A4) ----
				-- the layered TEST package (examples/themes/layered_test) — one slot
				-- with the whole R1 vocabulary, one with per-state art, one whose
				-- SELECTED state is a different picture, one layered field
				installLayered = function()
					return installNamed("layered_test")
				end,
				-- the ladder as it actually exists in the DataModel: per-node
				-- instances, ZIndex order, tags, resolved paint, suppression
				layerCensus = function(_session, payload: string?)
					return layerReports(tonumber(payload or "") or 6)
				end,
				-- ONE node, by path (the state walk's read: drive a real hover or
				-- press with the MCP mouse, then take this)
				layerProbe = function(_session, payload: string?)
					if type(payload) ~= "string" or payload == "" then
						return { error = "layerProbe needs a node path" }
					end
					return layerReport(payload)
				end,
				-- the sixth variant state. No control publishes one yet (P3's
				-- wiring), so the adapter's seam is driven here — which is what makes
				-- the `luau-state-error` art rules provably APPLIED.
				setError = function(_session, payload: string?)
					if type(payload) ~= "string" or payload == "" then
						return { error = "setError needs a node path" }
					end
					local flipped = ctx.themeChrome.setErrorState(payload, true)
					-- A TAG FLIP RESOLVES ON A LATER FRAME (live-found here, and
					-- consistent with rs-m6's next-frame paint): a same-frame
					-- GetStyled still reports the PREVIOUS winner, so a probe taken
					-- without this yield reads blind and looks like a defect.
					SETTLE()
					return { flipped = flipped, probe = layerReport(payload) }
				end,
				clearError = function(_session, payload: string?)
					if type(payload) ~= "string" or payload == "" then
						return { error = "clearError needs a node path" }
					end
					local flipped = ctx.themeChrome.setErrorState(payload, false)
					SETTLE() -- same settle rule as setError above
					return { flipped = flipped, probe = layerReport(payload) }
				end,
				-- THE STACK YIELD. One tag on the DECORATED NODE; the package's
				-- child-combinator rules blank the whole ladder so the engine caret
				-- (parent-drawn, non-negotiable) is visible.
				yieldField = function()
					local focused = ctx.nativeStyle.focusTextBox(PROBE_FIELD, true)
					-- MORE THAN ONE FRAME (live-found): a rule-driven tag flip's GetStyled
					-- resolution can lag a single task.wait(), so a one-frame probe reads
					-- the PREVIOUS winner and looks like a product defect
					SETTLE()
					return { focused = focused, probe = layerReport(PROBE_FIELD) }
				end,
				unyieldField = function()
					local released = ctx.nativeStyle.focusTextBox(PROBE_FIELD, false)
					SETTLE()
					return { released = released, probe = layerReport(PROBE_FIELD) }
				end,
				-- a MIDDLE layer's art is bogus: the whole stack falls back as a unit,
				-- because a half-painted ladder reads as broken rather than degraded.
				-- `payload` names the PACKAGE (default `layered_test`, the P2 fixture);
				-- P5's `fantasy_ornate` exposes the same two fields, so one step drives the
				-- reference package's own fallback and its recovery as well.
				failLayerAsset = function(_session, payload: string?)
					local which = if type(payload) == "string" and payload ~= "" then payload else "layered_test"
					local result = installNamed(which, "buildBadLayer")
					local module = packages[which]
					local reported = false
					if module ~= nil then
						reported = ctx.themeChrome.setAssetLoaded(module.BROKEN_ASSET, false)
					end
					ctx.presenter.refresh()
					return {
						package = which,
						installed = result,
						failureReported = reported,
						layers = layerReports(2),
						focusPath = ctx.presenter.focus.focused:get(),
						geometry = ctx.geometry(GEOMETRY_PATHS),
					}
				end,
				recoverLayerAsset = function(_session, payload: string?)
					local which = if type(payload) == "string" and payload ~= "" then payload else "layered_test"
					local module = packages[which]
					local reported = false
					if module ~= nil then
						reported = ctx.themeChrome.setAssetLoaded(module.BROKEN_ASSET, true)
					end
					ctx.presenter.refresh()
					return { package = which, recoveryReported = reported, layers = layerReports(2) }
				end,
				-- ---- rung 2: the per-view override (RS-A4) -----------------------
				presentRungFixture = function()
					return buildProbe()
				end,
				dismissRungFixture = function()
					disposeProbe()
					return { dismissed = true }
				end,
				-- both thumbs, same tree, same theme: the themed one takes the
				-- package's `sliderThumb` recipe, the overridden one takes its own map
				-- — and neither may half-apply
				rungWalk = function()
					return {
						variants = probe.thumbVariants,
						themed = layerReport(PROBE_THEMED_THUMB),
						overridden = layerReport(PROBE_VIEW_THUMB),
					}
				end,
				-- ---- rich-skinning-v2: IMAGE VALUE DISPLAYS (RS-A5, RS-A6) ----
				presentValueFixture = function()
					return buildValueProbe()
				end,
				dismissValueFixture = function()
					disposeValueProbe()
					return { dismissed = true }
				end,
				-- ---- rung 3: a CUSTOM SKINNED CONTROL (RS-A15) ----------------
				-- Mounts `examples/themes/ornate_gauge.luau` — a control the
				-- framework does not know about, with its own art and its own
				-- namespaced roles — under whatever package is installed.
				presentGaugeFixture = function()
					return buildGaugeProbe()
				end,
				-- ---- the CIRCLE BUTTON (feature round 2026-07-26) -------------
				-- Six buttons that differ in exactly one way each: see the fixture
				-- above for what every one of them is for.
				presentCircleFixture = function()
					return buildCircleProbe()
				end,
				dismissCircleFixture = function()
					disposeCircleProbe()
					return { dismissed = true }
				end,
				-- The discs under the CURRENT package: the solved box (square?),
				-- the RESOLVED corner through GetStyled (a plain read is blind to a
				-- rule), the drawn text, the tags the adapter settled on, and the
				-- chrome children that landed. Install a package, call this, swap,
				-- call it again.
				circleProbe = function()
					return circleReport()
				end,
				dismissGaugeFixture = function()
					disposeGaugeProbe()
					return { dismissed = true }
				end,
				-- The gauge under the CURRENT package: what it resolved, what it
				-- drew, and the live re-theme (one signal write, no rebuild).
				-- Install a package, call this, swap package, call it again — the
				-- dial's height moves and the mount identity does not.
				gaugeProbe = function()
					return gaugeReport()
				end,
				-- CONFORMANCE, BOTH DIRECTIONS. The same declarations against a
				-- package that covers the gauge and one that does not: `ok = true`
				-- with three covered roles, versus `ok = false` with a message that
				-- names the role, says what the player would see, and gives the
				-- line to add. The control's own `check` is a thin call into
				-- `themes.checkCoverage`, so both come back from one gate.
				gaugeCoverage = function(_session, payload: string?)
					local module = gaugeModule()
					if module == nil then
						return { unavailable = "examples/themes/ornate_gauge is not in this build" }
					end
					local coveringName, uncoveringName = "fantasy_ornate", "classic_desktop"
					if type(payload) == "string" and payload ~= "" then
						local a, b = string.match(payload, "^([^,]+),([^,]+)$")
						if a ~= nil then
							coveringName, uncoveringName = a, b :: string
						end
					end
					local covering = (packages[coveringName] :: any).build(themes)
					local uncovering = (packages[uncoveringName] :: any).build(themes)
					return {
						covering = covering.identity.id,
						uncovering = uncovering.identity.id,
						covered = module.check(themes, covering),
						uncovered = module.check(themes, uncovering),
						-- the framework gate over the same declarations: the
						-- control's `check` IS this call, so they cannot disagree
						frameworkCovered = themes.checkCoverage(covering, module.needs),
						frameworkUncovered = themes.checkCoverage(uncovering, module.needs),
						needs = module.needs,
					}
				end,
				-- THE PERCENT SWEEP. One value, five stops, and the same seven reads
				-- at each: the art must be byte-stable (same size, same slice, same
				-- picture) while only the WINDOW moves, and the caps and the crown
				-- must not shift by a pixel. The renderer's own counters ride along,
				-- so "what did the value cost" is a number rather than a claim.
				barSweep = function(_session, payload: string?)
					if values.progress == nil then
						return { error = "presentValueFixture first" }
					end
					local stops: { number } = {}
					for token in string.gmatch(payload or "0,0.01,0.5,0.99,1", "[^,]+") do
						local n = tonumber(token)
						if n ~= nil then
							table.insert(stops, n)
						end
					end
					local before = valueStats()
					local rows: { any } = {}
					for _, fraction in stops do
						values.progress:set(fraction)
						ctx.presenter.refresh()
						-- a rule-driven repaint resolves on a LATER frame, so a
						-- same-frame GetStyled reports the previous winner
						SETTLE()
						table.insert(rows, { fraction = fraction, nodes = barReport(), stats = valueStats() })
					end
					return { stops = rows, statsBefore = before, statsAfter = valueStats(), paths = VALUE_PATHS }
				end,
				-- the bar under whatever package is installed, once (the flat read)
				barProbe = function()
					return { nodes = barReport(), stats = valueStats(), census = ctx.themeChrome.census() }
				end,
				-- THE SWITCH'S VALUE. `on` is not a GuiState and not a selection, so
				-- it is set here and the ART has to follow through the tag — while
				-- the knob's TRAVEL comes back in the same read, because "art never
				-- moves geometry" is only worth anything as a comparison.
				setToggle = function(_session, payload: string?)
					if values.switch == nil then
						return { error = "presentValueFixture first" }
					end
					-- THE NO-REFLOW ASSERTION, ON THE WALK ITSELF (director finding
					-- 13, 2026-07-26). A value change is PAINT: the flip may repaint
					-- the track, swap the art and move the knob, and it may not move
					-- one solved rect. That is asserted headlessly across every
					-- reference package, and it is asserted HERE because only the
					-- engine can show a label re-rasterizing inside a box the solver
					-- never touched. The label geometry rides along, because the
					-- defect the director reported was the LABEL breaking mid-word
					-- inside a box that was the right size all along.
					local WATCHED = {
						VALUE_PATHS.toggle,
						VALUE_PATHS.toggle .. "/Label",
						VALUE_PATHS.toggle .. "/Track",
						VALUE_PATHS.toggle .. "/Knob",
						VALUE_PATHS.disabledToggle,
						VALUE_PATHS.bar,
					}
					local function boxes(): { [string]: any }
						return ctx.geometry(WATCHED)
					end
					local function labelText(): any
						local a = ctx.adapter :: any
						local inst = a.getInstance and a.getInstance(VALUE_PATHS.toggle)
						local label = if inst ~= nil then inst:FindFirstChild("Label") else nil
						if label == nil then
							return nil
						end
						return {
							textSize = label.TextSize,
							bounds = { x = label.TextBounds.X, y = label.TextBounds.Y },
							fits = label.TextFits,
							wrapped = label.TextWrapped,
							truncate = tostring(label.TextTruncate),
							-- ONE LINE is the claim: the drawn height is a single line
							-- of the drawn size, never two
							lines = if label.TextSize > 0
								then math.floor(label.TextBounds.Y / label.TextSize + 0.5)
								else 0,
						}
					end
					local before, labelBefore = boxes(), labelText()
					values.switch:set(payload ~= "off")
					ctx.presenter.refresh()
					SETTLE()
					local after, labelAfter = boxes(), labelText()
					local moved: { string } = {}
					for _, path in WATCHED do
						local a, b = before[path], after[path]
						if a ~= nil and b ~= nil then
							if a.x ~= b.x or a.y ~= b.y or a.w ~= b.w or a.h ~= b.h then
								table.insert(moved, `{path}: {a.x},{a.y} {a.w}x{a.h} -> {b.x},{b.y} {b.w}x{b.h}`)
							end
						end
					end
					return {
						on = values.switch:get(),
						noReflow = {
							-- the verdict a matrix row can read without joining two dumps
							ok = #moved == 0,
							moved = moved,
							watched = #WATCHED,
							before = before,
							after = after,
						},
						label = { before = labelBefore, after = labelAfter },
						toggle = artReport(VALUE_PATHS.toggle),
						track = artReport(VALUE_PATHS.toggle .. "/Track"),
						knob = artReport(VALUE_PATHS.toggle .. "/Knob"),
					}
				end,
				-- the same read with no state change: what the MCP mouse's hover and
				-- press walks are sampled with
				toggleProbe = function()
					return {
						on = if values.switch ~= nil then values.switch:get() else nil,
						toggle = artReport(VALUE_PATHS.toggle),
						track = artReport(VALUE_PATHS.toggle .. "/Track"),
						knob = artReport(VALUE_PATHS.toggle .. "/Knob"),
						-- the DISABLED sibling, same value and same package: the
						-- accessibility floor applies over `default` art the theme
						-- supplied no `disabled` variant for
						disabled = artReport(VALUE_PATHS.disabledToggle),
						disabledTrack = artReport(VALUE_PATHS.disabledToggle .. "/Track"),
						disabledKnob = artReport(VALUE_PATHS.disabledToggle .. "/Knob"),
					}
				end,
				-- both stepper plates, whichever slot the installed package resolved
				-- them to (a package with no `stepperPlate` keeps painting them
				-- through its `control` recipe — ADR-0020 R3)
				stepperProbe = function()
					return {
						dec = artReport(VALUE_PATHS.stepperDec),
						inc = artReport(VALUE_PATHS.stepperInc),
						decChrome = artReport(VALUE_PATHS.stepperDec .. "/FacetChrome"),
						incChrome = artReport(VALUE_PATHS.stepperInc .. "/FacetChrome"),
					}
				end,
				-- ---- P4: icons, pixel mode, content A/B, tile, selectBy ----
				installPixel = function()
					return installNamed("pixel_quest")
				end,
				-- the SAME package with its icon map removed: the stepper's glyphs
				-- must fall back to the framework's ASCII characters rather than
				-- becoming empty plates (RS-A7's fallback half)
				installPixelNoIcons = function()
					return installNamed("pixel_quest", "buildWithoutIcons")
				end,
				installContent = function()
					return installNamed("content_alias_test")
				end,
				installContentAlias = function()
					return installNamed("content_alias_test", "buildAlias")
				end,
				-- SEMANTIC ICONS (RS-A7). The managed picture, the glyph underneath
				-- it, and the census — a glyph answer must create NOTHING, so the
				-- absent-instance case is reported rather than inferred.
				iconProbe = function()
					local function iconReport(nodePath: string): any
						local iconPath = nodePath .. "/FacetIcon"
						return {
							node = {
								path = nodePath,
								tree = ctx.nativeStyle.dumpNode(nodePath),
								-- the GLYPH the control drew, and whether the art
								-- turned it off (sheet-owned: styled, never plain)
								text = ctx.nativeStyle.styledOf(nodePath, "Text"),
								TextTransparency = ctx.nativeStyle.styledOf(nodePath, "TextTransparency"),
							},
							icon = {
								path = iconPath,
								present = ctx.nativeStyle.dumpNode(iconPath),
								geometry = (ctx.geometry({ iconPath }) :: any)[iconPath],
								styled = {
									Image = ctx.nativeStyle.styledOf(iconPath, "Image"),
									ImageColor3 = ctx.nativeStyle.styledOf(iconPath, "ImageColor3"),
									ResampleMode = ctx.nativeStyle.styledOf(iconPath, "ResampleMode"),
								},
							},
						}
					end
					local snap = ctx.env:get("themeMetrics"):get()
					return {
						package = installed.package.identity.id,
						iconSizes = snap.iconSizes,
						pixelUnit = snap.pixelUnit,
						declaredIcons = installed.package.icons,
						inc = iconReport(VALUE_PATHS.stepperInc),
						dec = iconReport(VALUE_PATHS.stepperDec),
						census = ctx.themeChrome.census(),
					}
				end,
				-- PIXEL MODE (RS-A8). The snapshot's own numbers, so "every length
				-- is a multiple of the unit" is arithmetic on a dump rather than a
				-- claim about a capture.
				pixelProbe = function()
					local snap = ctx.env:get("themeMetrics"):get()
					local offGrid: { string } = {}
					local unit = snap.pixelUnit
					if type(unit) == "number" then
						for _, name in { "space", "radii", "strokes", "targetSizes", "iconSizes" } do
							for key, value in (snap :: any)[name] do
								if type(value) == "number" and value % unit ~= 0 then
									table.insert(offGrid, `{name}.{key}={value}`)
								end
							end
						end
						table.sort(offGrid)
					end
					return {
						package = installed.package.identity.id,
						rendering = installed.package.identity.rendering,
						pixelUnit = unit,
						offGrid = offGrid,
						metrics = {
							space = snap.space,
							radii = snap.radii,
							strokes = snap.strokes,
							targetSizes = snap.targetSizes,
							iconSizes = snap.iconSizes,
							insets = snap.insets,
							motion = snap.motion,
							typeBody = snap.type.body,
						},
						-- SliceScale and the Pixelated stamp, read off the LIVE
						-- decoration rather than off the model that emitted them
						plate = artReport(VALUE_PATHS.stepperInc .. "/FacetChrome"),
						plateSliceScale = ctx.nativeStyle.styledOf(
							VALUE_PATHS.stepperInc .. "/FacetChrome",
							"SliceScale"
						),
						plateResample = ctx.nativeStyle.styledOf(
							VALUE_PATHS.stepperInc .. "/FacetChrome",
							"ResampleMode"
						),
						barTrack = artReport(VALUE_PATHS.bar),
						barTrackResample = ctx.nativeStyle.styledOf(VALUE_PATHS.bar, "ResampleMode"),
					}
				end,
				-- CONTENT A/B (RS-A9): the one node both packages paint, read the
				-- same way under each
				contentProbe = function()
					local node = VALUE_PATHS.stepperInc
					return {
						package = installed.package.identity.id,
						stamp = installed.package.stamp,
						assets = installed.package.assets,
						control = artReport(node),
						chrome = artReport(node .. "/FacetChrome"),
						icon = {
							Image = ctx.nativeStyle.styledOf(node .. "/FacetIcon", "Image"),
							ImageColor3 = ctx.nativeStyle.styledOf(node .. "/FacetIcon", "ImageColor3"),
						},
					}
				end,
				-- TILE (RS-A11). `tile` shipped as a layer kind on rs-m1's verdict;
				-- this reads TileSize back off the LIVE layer, because a plain read
				-- is blind for it exactly as it is for every other styled property.
				tileProbe = function()
					local census = ctx.themeChrome.census()
					local out: { any } = {}
					for _, path in (census.layeredPaths or {}) :: { string } do
						for index = 1, 8 do
							local layer = `{path}/FacetChromeL{index}`
							local scaleType = ctx.nativeStyle.styledOf(layer, "ScaleType")
							if type(scaleType) == "string" and string.find(scaleType, "Tile", 1, true) ~= nil then
								table.insert(out, {
									path = layer,
									geometry = (ctx.geometry({ layer }) :: any)[layer],
									styled = {
										ScaleType = scaleType,
										TileSize = ctx.nativeStyle.styledOf(layer, "TileSize"),
										Image = ctx.nativeStyle.styledOf(layer, "Image"),
										ResampleMode = ctx.nativeStyle.styledOf(layer, "ResampleMode"),
									},
									plain = ctx.nativeStyle.dumpNode(layer),
								})
							end
						end
					end
					return {
						package = installed.package.identity.id,
						probe = "rs-m1",
						perKind = census.layersPerKind,
						tiledLayers = out,
					}
				end,
				-- selectBy (RS-A10). The rule is installed on a SECOND controller
				-- over the same adapter is not possible (one controller per
				-- environment), so the fixture's own controller is re-installed
				-- with the rule — which is also how a game would author it.
				selectByInstall = function()
					local tc = ctx.themeController()
					if tc == nil then
						return { controller = "absent" }
					end
					local touch, _touchReport, touchErr = compile("pixel_quest")
					local pointer, _pointerReport, pointerErr = compile("classic_desktop")
					local fallbackPkg = compile("neutral")
					if touch == nil or pointer == nil or fallbackPkg == nil then
						return { error = `a selectBy package failed to compile: {tostring(touchErr or pointerErr)}` }
					end
					if installed.controller ~= nil then
						installed.controller.uninstall()
						installed.controller = nil
					end
					local ok, made = pcall(function()
						return tc.install(ctx.adapter, fallbackPkg, {
							env = ctx.env,
							core = ctx.core,
							selectBy = { touch = touch, pointer = pointer },
						})
					end)
					if not ok then
						return { error = tostring(made) }
					end
					installed.controller = made
					installed.name = "selectBy"
					local activeId = made.inspect().package.id
					installed.package = if activeId == touch.identity.id
						then touch
						elseif activeId == pointer.identity.id then pointer
						else fallbackPkg
					installed.chromeChanged = ctx.themeChrome.setPackage(installed.package)
					ctx.presenter.refresh()
					return {
						profile = (ctx.env:get("interactionClasses"):get() :: any).primary,
						inspect = made.inspect().selectBy,
						package = made.inspect().package.id,
						identity = ctx.nativeStyle.mountIdentity(),
						focusPath = ctx.presenter.focus.focused:get(),
					}
				end,
				-- the FORCED PARADIGM seam (input-paradigms): a fact change, not a
				-- synthesized device. selectBy subscribes to exactly this.
				forceParadigm = function(_session, payload: string?)
					local wanted = if type(payload) == "string" and payload ~= "" then payload else "Touch"
					local caps: any = { mouse = false, touch = false, gamepad = false, keyboard = false }
					if wanted == "Touch" then
						caps.touch = true
					elseif wanted == "Gamepad" then
						caps.gamepad = true
					else
						caps.mouse, caps.keyboard = true, true
					end
					ctx.env:set("capabilities", caps)
					ctx.env:set("preferredInput", wanted)
					-- THE DEBOUNCE HAS TO ELAPSE. selectBy settles a profile before
					-- it swaps (one swap per settlement, never one per hybrid flap),
					-- so a probe that reads sooner than `selectBySettleSeconds`
					-- reads the PREVIOUS package and calls it a failure — which is
					-- exactly what a 0.2s wait did on the first drive of this step.
					local settleSeconds = 0.25
					if installed.controller ~= nil then
						local info = installed.controller.inspect().selectBy
						if type(info) == "table" and type(info.settleSeconds) == "number" then
							settleSeconds = info.settleSeconds
						end
					end
					if task ~= nil then
						task.wait(settleSeconds + 0.25)
					end
					ctx.presenter.refresh()
					return {
						preferredInput = wanted,
						classes = ctx.env:get("interactionClasses"):get(),
						snapshot = snapshotIdentity(),
						identity = ctx.nativeStyle.mountIdentity(),
						focusPath = ctx.presenter.focus.focused:get(),
						selectBy = if installed.controller ~= nil then installed.controller.inspect().selectBy else nil,
					}
				end,
				selectByProbe = function()
					if installed.controller == nil then
						return { controller = "absent" }
					end
					local info = installed.controller.inspect()
					return {
						package = info.package.id,
						selectBy = info.selectBy,
						snapshot = snapshotIdentity(),
						geometry = ctx.geometry(GEOMETRY_PATHS),
						identity = ctx.nativeStyle.mountIdentity(),
						focusPath = ctx.presenter.focus.focused:get(),
						census = ctx.themeChrome.census(),
					}
				end,
				-- ---- P5: THE REFERENCE PACKAGES (rows RS-A12, RS-A13, RS-A14) ----
				-- Fantasy Ornate — the centerpiece. Everything the earlier steps in
				-- this file already do (layerCensus, the state walk, barSweep,
				-- setToggle, stepperProbe, iconProbe, tileProbe, yieldField,
				-- failLayerAsset) applies to it unchanged, which is the point: the
				-- reference package is driven by the SAME instruments the schema
				-- fixtures were, and nothing here is bespoke to it.
				installOrnate = function(_session, payload: string?)
					return installNamed("fantasy_ornate", nil, if payload ~= "" then payload else nil)
				end,
				installGlossyTouch = function()
					return installNamed("glossy_touch")
				end,
				installCompactPointer = function()
					return installNamed("compact_pointer")
				end,
				-- THE PLATFORM PAIR under one declaration (RS-A14). Same shape as
				-- `selectByInstall`, different packages: this is the authoring a
				-- game writes once so a docked player gets the pointer skin.
				-- `forceParadigm` + `selectByProbe` then drive and read the swap.
				selectByPair = function()
					local tc = ctx.themeController()
					if tc == nil then
						return { controller = "absent" }
					end
					local touch, _t, touchErr = compile("glossy_touch")
					local pointer, _p, pointerErr = compile("compact_pointer")
					if touch == nil or pointer == nil then
						return { error = `a pair package failed to compile: {tostring(touchErr or pointerErr)}` }
					end
					if installed.controller ~= nil then
						installed.controller.uninstall()
						installed.controller = nil
					end
					local ok, made = pcall(function()
						return tc.install(ctx.adapter, touch, {
							env = ctx.env,
							core = ctx.core,
							-- gamepad shares the pointer half: a ten-foot player is
							-- not a finger, and the pair says so rather than falling
							-- through to the positional default
							selectBy = { touch = touch, pointer = pointer, gamepad = pointer },
						})
					end)
					if not ok then
						return { error = tostring(made) }
					end
					installed.controller = made
					installed.name = "selectByPair"
					local activeId = made.inspect().package.id
					installed.package = if activeId == touch.identity.id then touch else pointer
					installed.chromeChanged = ctx.themeChrome.setPackage(installed.package)
					ctx.presenter.refresh()
					return {
						profile = (ctx.env:get("interactionClasses"):get() :: any).primary,
						inspect = made.inspect().selectBy,
						package = made.inspect().package.id,
						snapshot = snapshotIdentity(),
						geometry = ctx.geometry(GEOMETRY_PATHS),
						identity = ctx.nativeStyle.mountIdentity(),
						focusPath = ctx.presenter.focus.focused:get(),
						census = ctx.themeChrome.census(),
					}
				end,
				-- ---- P5: PIXEL ADJACENCY (RS-A13, ADR-0020 R5 clause 3) ----
				presentAdjacency = function()
					return buildAdjacency()
				end,
				dismissAdjacency = function()
					disposeAdjacency()
					return { dismissed = true }
				end,
				-- the boundary between scale-derived siblings, measured. Take it
				-- under a pixel package AND under a non-pixel one: the comparison
				-- is what says whether pixel mode changed anything.
				adjacencyProbe = function()
					return adjacencyReport()
				end,
				-- ---- inspection --------------------------------------------
				inspect = function()
					-- the LIVE controller instance, not the module: inspect() is
					-- instance API (module-level has no state to report)
					local fromController: any = nil
					if installed.controller ~= nil then
						local ok, value = pcall(installed.controller.inspect)
						fromController = if ok then value else `error:{tostring(value)}`
					end
					return {
						installedName = installed.name,
						identity = snapshotIdentity(),
						compatibility = installed.package.compatibility,
						chrome = installed.package.chrome,
						assetsToPreload = {
							install = ctx.themeChrome.assetsToPreload("install"),
							lazy = ctx.themeChrome.assetsToPreload("lazy"),
						},
						census = ctx.themeChrome.census(),
						lastError = installed.error,
						controller = if installed.controller == nil then "absent" else "installed",
						controllerInspect = fromController,
					}
				end,
				focusSave = function()
					return ctx.presenter.focus.focusOn(SCREEN .. "/Actions/ActionsRow/Save")
				end,
				-- FOCUS ANY NODE, AND SEE WHERE ITS VISUAL LANDED (director fix
				-- round 2026-07-25). The ring used to hang off the node, so it
				-- wrapped the padded solved rect instead of the plate the package
				-- actually draws; it now rides the ART. The instrument is the
				-- existing subtree dump, which already counts UIStroke children per
				-- instance and reports every rect — so "the ring is on the art, and
				-- the art is the box it hugs" is one machine read rather than a
				-- pixel judgement. payload = the Facet path (default: the stepper's
				-- decrement, which is the node the defect was reported on).
				focusNode = function(_session, payload: string?)
					local path = if type(payload) == "string" and payload ~= ""
						then payload
						else SCREEN .. "/BodyScroll/Body/Settings/Volume/Dec"
					local ok = ctx.presenter.focus.focusOn(path)
					SETTLE()
					return { path = path, focused = ok, subtree = ctx.nativeStyle.dumpNode(path) }
				end,
				identity = function()
					return ctx.nativeStyle.mountIdentity()
				end,
			},
			report = function()
				return {
					-- the pairing the acceptance rows need: what was solved, the
					-- theme that produced it, what it cost in instances, and
					-- whether the mount survived
					geometry = ctx.geometry(GEOMETRY_PATHS),
					snapshot = snapshotIdentity(),
					census = ctx.themeChrome.census(),
					focusPath = ctx.presenter.focus.focused:get(),
					mountIdentity = ctx.nativeStyle.mountIdentity(),
					chromeProbe = chromeProbe(),
					installed = {
						name = installed.name,
						chromeChanged = installed.chromeChanged,
						error = installed.error,
					},
					controller = if installed.controller ~= nil
						then "installed"
						elseif ctx.themeController() ~= nil then "available"
						else "absent",
					fixture = fixture.report ~= nil and fixture.report() or nil,
				}
			end,
		}
	end,
}
