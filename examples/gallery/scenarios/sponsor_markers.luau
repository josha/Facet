--!strict
-- Scenario 'sponsor_markers' (ledger row SF-P5; ui-designer-spec §8.7): the
-- KEYED MARKER OVERLAY on fractional Anchor offsets — the minimap-dot shape.
--
-- A marker's position is a SHARE of the map (u, v in 0..1), not a pixel count, so
-- the fixture hands the framework the fraction and the arrange pass spends it
-- against the anchor's live inner box. That is the whole point of the row: a dot
-- update is an arrange write, never a re-measure and never a remount, so a
-- marker that moves 60 times a second never blinks and the mount counters do not
-- move at all.
--
-- MARKERS ARE DISPLAY-ONLY BY CONTRACT (§6.4, finding F9). Nothing here is
-- focusable and nothing is tappable: an 8 px dot cannot carry a 44 px target, and
-- a fixture quietly waiving that floor is exactly what the contract-level
-- declaration exists to prevent.

return {
	title = "Marker lab (SF-P5)",
	ledgerRows = { "SF-P5", "SF-C1", "SF-C2", "SF-C3" },
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI = Facet.UI
		local core = ctx.core
		local env = ctx.env
		local pres = ctx.presenter
		local scope = core:scope("sponsor-markers")

		local SCREEN = "/MarkerLab"
		local OVERLAY = SCREEN .. "/Stage/Overlay"

		local trace: { any } = {}
		local elapsed = 0
		local function note(kind: string, info: any?)
			table.insert(trace, { at = elapsed, kind = kind, info = info })
		end

		-- ===== the marker set ===============================================
		local START_COUNT = 12
		local factoryRuns: { [string]: number } = {}
		local positions: { [string]: any } = {}
		local updateWrites = 0

		local function makeMarker(index: number): any
			return { key = string.format("m-%02d", index), index = index }
		end

		local function makeSet(count: number): { any }
			local out = {}
			for i = 1, count do
				table.insert(out, makeMarker(i))
			end
			return out
		end

		local markers = scope:own(core:signal(makeSet(START_COUNT)))
		local orbiting = scope:own(core:signal(false))

		-- u,v live in ONE signal per marker: a jump is one write, and the two
		-- offsets read the same value, so no frame can ever show x from this update
		-- and y from the last one
		local function ensurePosition(key: string, index: number): any
			local existing = positions[key]
			if existing ~= nil then
				return existing
			end
			local angle = (index / START_COUNT) * math.pi * 2
			local signal = scope:own(core:signal({
				u = 0.5 + 0.32 * math.cos(angle),
				v = 0.5 + 0.32 * math.sin(angle),
			}))
			positions[key] = signal
			return signal
		end

		-- the demo hue for marker #12 (§6.1's `direct` form, LABELED): a colour that
		-- IS data, declared theming-exempt. Every other marker stays on roles.
		local DIRECT_HUE = "#3fa9f5"
		local MARKER: any = { type = "fixed", px = "iconSizes.small" }

		local function markerView(item: any, itemScope: any): any
			factoryRuns[item.key] = (factoryRuns[item.key] or 0) + 1
			local position = ensurePosition(item.key, item.index)
			-- the fraction is spent at ARRANGE against the anchor's inner box; the
			-- `-s` offset is half a marker (the theme's own step), so the dot is
			-- centred on its point instead of hanging off it
			local offsetX = itemScope:own(core:memo(function(use)
				return { scale = (use(position) :: any).u, offset = "-s" }
			end))
			local offsetY = itemScope:own(core:memo(function(use)
				return { scale = (use(position) :: any).v, offset = "-s" }
			end))
			local tracked = item.index == 1
			local direct = item.index == 12
			local box = UI.Box({
				id = "Dot",
				-- a fade needs a fade group, and a marker is a single plate
				canvasGroup = true,
				-- THE UNTRACKED MARKER IS NEUTRAL CONTENT, NOT A CONTROL SURFACE
				-- (§8.7; review R2-F16). `control` is the fill of a thing you press,
				-- and a map dot is not one — the neutral channel is `contentSecondary`,
				-- reached through the role-blend tint so the hue stays the THEME's.
				-- Only the tracked marker spends the accent surface, and only marker
				-- twelve declares a theming-exempt identity hue.
				surface = if tracked then "accent" else nil,
				tint = if direct
					then { direct = DIRECT_HUE }
					elseif tracked then nil
					else { role = "contentSecondary", blend = 1 },
				anchor = "topLeft",
				offsetX = offsetX,
				offsetY = offsetY,
				width = MARKER,
				height = MARKER,
			})
			-- SHAPE + HUE, never hue alone (I-5): the tracked marker is the square
			-- one; every other marker is a pill
			return if tracked then box else UI.corners(box, "pill")
		end

		local result: any = {}
		local function controller(): any
			local handle = result.handle
			return if handle ~= nil then handle.controller else nil
		end

		local function setPosition(key: string, u: number, v: number)
			local signal = positions[key]
			if signal == nil then
				return
			end
			signal:set({ u = math.clamp(u, 0, 1), v = math.clamp(v, 0, 1) })
			updateWrites += 1
		end

		local orbitPhase = 0
		scope:own(pres.onTick(function(dt: number)
			elapsed += dt
			if not orbiting:get() then
				return
			end
			orbitPhase += dt
			-- ONE transaction per frame for the whole set: twelve markers move
			-- together, so the arrange pass runs once
			core:transaction(function()
				for _, item in markers:get() :: { any } do
					local angle = (item.index / START_COUNT) * math.pi * 2 + orbitPhase * 1.2
					setPosition(item.key, 0.5 + 0.32 * math.cos(angle), 0.5 + 0.32 * math.sin(angle))
				end
			end)
		end))

		local function control(id: string, label: string, onActivate: () -> ())
			return UI.Button({
				id = id,
				label = label,
				height = { type = "minMax", min = "targetSizes.minimum" },
				onActivate = onActivate,
			})
		end

		local function toggleOrbit()
			orbiting:set(not orbiting:get())
			note("orbit", { on = orbiting:get() })
		end

		local function burst()
			core:transaction(function()
				for _, item in markers:get() :: { any } do
					local angle = item.index * 2.399963 -- the golden angle: a real scatter
					setPosition(item.key, 0.5 + 0.42 * math.cos(angle), 0.5 + 0.42 * math.sin(angle))
				end
			end)
			note("burst", { markers = #(markers:get() :: any) })
		end

		local function addRemove()
			local current = markers:get() :: { any }
			local next: { any } = {}
			for _, item in current do
				-- 3 and 4 leave...
				if item.index ~= 3 and item.index ~= 4 then
					table.insert(next, item)
				end
			end
			-- ...13 and 14 arrive, through the same keyed region
			local hasThirteen = false
			for _, item in next do
				if item.index == 13 then
					hasThirteen = true
				end
			end
			if not hasThirteen then
				table.insert(next, makeMarker(13))
				table.insert(next, makeMarker(14))
			end
			markers:set(next)
			note("addRemove", { count = #next })
		end

		local screen = UI.Screen({
			id = "MarkerLab",
			padding = "m",
			gap = "s",
			children = {
				UI.Text({ id = "Title", text = "Marker lab", textSize = "heading" }),
				UI.ZStack({
					id = "Stage",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.corners(
							UI.Box({
								id = "Map",
								surface = "raised",
								width = { type = "fill", weight = 1 },
								height = { type = "fill", weight = 1 },
							}),
							"panel"
						),
						UI.Anchor({
							id = "Overlay",
							width = { type = "fill", weight = 1 },
							height = { type = "fill", weight = 1 },
							children = {
								UI.ForEach({
									id = "Markers",
									items = markers,
									key = function(item: any)
										return item.key
									end,
									row = markerView,
									transition = { enter = "fade", class = "container" },
								}),
							},
						}),
					},
				}),
				UI.Grid({
					id = "Controls",
					-- A PACKING FLOOR, NOT A FONT GUESS, and it was measured on 2026-08-21 before
					-- being left alone. `minColumnWidth = "intrinsic"` (the default since that day)
					-- lets the WIDEST verb decide every column, so one long label costs this lab a
					-- whole column on a 320px phone: the control grid doubles in height and the
					-- `fill` stage column above it collapses to zero. This number asks the other
					-- question — how many controls fit a row — and lets a long label compact.
					minColumnWidth = 104,
					gap = "s",
					rowGap = "s",
					width = { type = "fill", weight = 1 },
					children = {
						control("BtnOrbit", "Orbit", toggleOrbit),
						control("BtnBurst", "Burst", burst),
						control("BtnAddRemove", "AddRemove", addRemove),
					},
				}),
			},
		})

		local function geometryNow(): any
			if ctx.geometry == nil then
				return nil
			end
			local paths: { string } = {}
			for _, item in markers:get() :: { any } do
				table.insert(paths, `{OVERLAY}/Markers/[{item.key}]/Dot`)
			end
			table.insert(paths, SCREEN .. "/Stage/Map")
			return ctx.geometry(paths)
		end

		local function mountCounters(): any
			local handle = result.handle
			if handle == nil or handle.root == nil then
				return nil
			end
			return handle.root.counters()
		end

		result.screen = screen
		result.present = {}
		result.steps = {
			-- SF-P5: the identity check. Every marker moves every frame; the mount
			-- counters must not move at all.
			startOrbit = function()
				local before = mountCounters()
				updateWrites = 0
				orbiting:set(true)
				note("orbit:start", { counters = before })
				return { orbiting = true, countersBefore = before, markers = #(markers:get() :: any) }
			end,
			stopOrbit = function()
				orbiting:set(false)
				return {
					orbiting = false,
					updateWrites = updateWrites,
					counters = mountCounters(),
					factoryRuns = factoryRuns,
				}
			end,
			-- all twelve jump on ONE frame: arrange-only writes, no structural change
			burst = function()
				local before = mountCounters()
				burst()
				return { countersBefore = before, countersAfter = mountCounters(), positions = geometryNow() }
			end,
			-- keyed enter/exit with fades; every survivor keeps its identity
			addRemove = function()
				local before = mountCounters()
				local beforeRuns = table.clone(factoryRuns)
				addRemove()
				pres.refresh()
				return {
					countersBefore = before,
					countersAfter = mountCounters(),
					factoryRunsBefore = beforeRuns,
					factoryRunsAfter = factoryRuns,
					keys = (function()
						local out: { string } = {}
						for _, item in markers:get() :: { any } do
							table.insert(out, item.key)
						end
						return out
					end)(),
				}
			end,
			-- the corner check the matrix WRONG names: u,v = 0 and 1 must sit exactly
			-- on the map surface's corners at any aspect ratio
			corners = function()
				local set = markers:get() :: { any }
				local aims = {
					{ key = set[1].key, u = 0, v = 0 },
					{ key = set[2].key, u = 1, v = 0 },
					{ key = set[3].key, u = 0, v = 1 },
					{ key = set[4].key, u = 1, v = 1 },
				}
				core:transaction(function()
					for _, aim in aims do
						setPosition(aim.key, aim.u, aim.v)
					end
				end)
				pres.refresh()
				-- THE CHECK IS ON CENTRES, not on top-left corners: a marker is centred
				-- on its point (the `-s` half-marker offset), so u,v = 0,0 puts the
				-- DOT'S CENTRE on the map's top-left corner. Comparing rect origins
				-- would read a correct overlay as half a marker adrift.
				local ctrl = controller()
				local map = if ctrl ~= nil then ctrl.rectOf(SCREEN .. "/Stage/Map") else nil
				local checks: { any } = {}
				if map ~= nil and ctrl ~= nil then
					for _, aim in aims do
						local rect = ctrl.rectOf(`{OVERLAY}/Markers/[{aim.key}]/Dot`)
						if rect ~= nil then
							local cx, cy = rect.x + rect.w / 2, rect.y + rect.h / 2
							table.insert(checks, {
								key = aim.key,
								u = aim.u,
								v = aim.v,
								centre = { x = cx, y = cy },
								expected = { x = map.x + aim.u * map.w, y = map.y + aim.v * map.h },
								dx = cx - (map.x + aim.u * map.w),
								dy = cy - (map.y + aim.v * map.h),
							})
						end
					end
				end
				note("corners", { checks = #checks })
				return { map = map, checks = checks, geometry = geometryNow() }
			end,
			geometry = function()
				return geometryNow()
			end,
		}
		result.report = function()
			local ctrl = controller()
			return {
				ledger = "SF-P5",
				elapsed = elapsed,
				trace = trace,
				orbiting = orbiting:get(),
				updateWrites = updateWrites,
				markerCount = #(markers:get() :: any),
				keys = (function()
					local out: { string } = {}
					for _, item in markers:get() :: { any } do
						table.insert(out, item.key)
					end
					return out
				end)(),
				-- IDENTITY, the row's whole acceptance: one factory run per key, ever
				factoryRuns = factoryRuns,
				mountCounters = mountCounters(),
				positions = (function()
					local out: { [string]: any } = {}
					for key, signal in positions do
						out[key] = signal:get()
					end
					return out
				end)(),
				geometry = geometryNow(),
				mapRect = if ctrl ~= nil then ctrl.rectOf(SCREEN .. "/Stage/Map") else nil,
				directHue = { key = "m-12", value = DIRECT_HUE, themingExempt = true },
				markerSizeMetric = "iconSizes.small",
				interactive = false,
				reducedMotion = env:get("reducedMotion"):get(),
				counters = core:counters(),
				coreError = core:lastError(),
			}
		end
		result.dispose = function()
			orbiting:set(false)
			scope:dispose()
		end
		return result
	end,
}
