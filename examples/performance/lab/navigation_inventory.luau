--!strict
-- PROBE-EXEMPT: shared benchmark workload, not an application tutorial.
-- Shared native/headless workload: keep the artwork, responsive grid and controls
-- identical so adapter attribution cannot silently change the work being timed.
local inventory = {}
function inventory.build(Facet: any, core: any, images: { string }): any
	local UI = Facet.UI
	local selected = core:signal("garage")
	local customization = core:signal({ order = {}, hidden = {} })
	local builds = 0
	local tabs = Facet.Controls.TabView(core, {
		id = "Tabs",
		style = "sidebarAdaptable",
		selection = selected,
		customization = customization,
		sections = { { id = "game", label = "Game" } },
		tabs = {
			{
				id = "garage",
				section = "game",
				required = true,
				label = "Garage",
				content = function(pageScope)
					builds += 1
					local cards = {}
					for i = 1, 24 do
						local b = pageScope:own(Facet.Controls.Button(core, {
							id = "Car" .. i,
							label = "Race car " .. i,
							subtitle = "Ready to race",
							image = images[(i - 1) % #images + 1],
							imageFraming = { width = 256, height = 256, focusY = 0.25 },
							onActivate = function() end,
						}))
						table.insert(cards, b.blueprint)
					end
					return UI.ScrollView({
						id = "Inventory",
						width = UI.fill(),
						height = UI.fill(),
						navigation = { targets = { "Cars" } },
						children = {
							UI.focusSection(UI.Grid({
								id = "Cars",
								minColumnWidth = 180,
								gap = "m",
								width = UI.fill(),
								children = cards,
							})),
						},
					})
				end,
			},
			{
				id = "race",
				label = "Race",
				content = function()
					return UI.Text({ text = "Race" })
				end,
			},
			{
				id = "settings",
				label = "Settings",
				content = function()
					return UI.Text({ text = "Settings" })
				end,
			},
		},
	})
	return {
		screen = UI.Screen({ id = "S", children = { tabs.blueprint } }),
		tabs = tabs,
		selected = selected,
		customization = customization,
		builds = function()
			return builds
		end,
	}
end
-- Installed in the existing lab; all UI and frame seams remain caller-owned.
function inventory.install(deps: any)
	deps.passes.navigationReflow = function(payload: string?)
		return deps.timed("navigationReflow", function()
			local _, reps = deps.framesAndReps(payload, 60, 24)
			local state = inventory.build(deps.Facet, deps.core, deps.dataset.IMAGE_KEYS)
			local pres = deps.ctx.presenter
			local handle = pres.present(state.screen)
			local ok, result = pcall(function()
				pres.refresh()
				local samples = { expand = {}, collapse = {} }
				local before = handle.controller.stats()
				for _ = 1, reps do
					for _, direction in { "expand", "collapse" } do
						deps.telemetry.step()
						local start = deps.telemetry.clock()
						if direction == "expand" then
							state.tabs.expandSidebar()
						else
							state.tabs.collapseSidebar()
						end
						pres.refresh()
						pres.tick(1 / 60)
						pres.refresh()
						table.insert(samples[direction], (deps.telemetry.clock() - start) * 1000)
						-- Match bench settling outside event timing. These are simulation
						-- ticks, not rendered frames; each event yields above.
						for _ = 1, 60 do
							pres.tick(1 / 60)
							pres.refresh()
						end
						assert(state.builds() == 1, "navigation remounted inventory")
					end
				end
				local after = handle.controller.stats()
				return {
					reps = reps,
					cards = 24,
					contentBuilds = state.builds(),
					expandMs = deps.summarize(samples.expand),
					collapseMs = deps.summarize(samples.collapse),
					solves = after.solves - before.solves,
					rectWrites = after.rectWrites - before.rectWrites,
					simulationSettleTicks = 60,
				}
			end)
			pres.dismiss(handle)
			state.tabs.dispose()
			state.selected:dispose()
			state.customization:dispose()
			if not ok then
				error(result, 0)
			end
			return result
		end)
	end
end
return inventory
