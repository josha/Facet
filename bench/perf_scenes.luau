--!strict
local nativeApp = require("./native_app")
local workloads = require("../examples/performance/lab/workloads")
local dataset = require("../examples/performance/lab/dataset")
local rows = require("../examples/performance/lab/rows")
local parchment = require("../examples/themes/fantasy_parchment")
local compactPointer = require("../examples/themes/compact_pointer")
local glossyTouch = require("../examples/themes/glossy_touch")
local ornate = require("../examples/themes/fantasy_ornate")
local sampling = {
	["virtual-list-scroll"] = { 160, 40 },
	["native-scroll-drag"] = { 160, 40 },
	["dense-hud"] = { 160, 40 },
	["stylesheet-state-churn"] = { 160, 40 },
	["async-image-grid"] = { 120, 30 },
	["screen-lifecycle-churn"] = { 120, 30 },
	["theme-swap-flat"] = { 160, 40 },
	["theme-swap-metrics"] = { 160, 40 },
	["dense-motion"] = { 160, 40 },
	["control-motion"] = { 160, 40 },
	["theme-swap-assets"] = { 160, 40 },
	["lab-dense-scroll"] = { 120, 30 },
	["lab-collection-churn"] = { 100, 25 },
	["adaptive-navigation-images"] = { 120, 20 },
	["navigation-customization"] = { 120, 20 },
	["alert-present-dismiss"] = { 120, 30 },
	["picker-menu-open-close"] = { 120, 30 },
	["picker-segmented-textsize"] = { 120, 30 },
	["radial-menu-open-close"] = { 120, 30 },
}
local requirements = {
	["alert-present-dismiss"] = "UI-LIFE-002",
	["collection-mutation"] = "UI-RUNTIME-002",
	["lab-collection-churn"] = "UI-RUNTIME-002",
	["locale-textsize-change"] = "UI-ENV-001",
	["native-scroll-drag"] = "UI-NATIVE-001",
	["picker-segmented-textsize"] = "UI-ENV-001",
	["screen-lifecycle-churn"] = "UI-LIFE-002",
	["scroll-focus-traversal"] = "UI-FOCUS-001",
	["settings-churn"] = "UI-LIFE-002",
	["shadow-storm"] = "UI-STYLE-001",
	["stylesheet-state-churn"] = "UI-STYLE-001",
	["theme-swap-assets"] = "UI-PERF-002",
	["theme-swap-flat"] = "UI-PERF-002",
	["theme-swap-metrics"] = "UI-PERF-002",
	["virtual-list-scroll"] = "UI-RUNTIME-002",
}
local scenes = {}
for _, name in workloads.ORDER do
	local counts = sampling[name] or { 240, 60 }
	table.insert(scenes, {
		name = name,
		requirement = requirements[name] or "UI-PERF-001",
		dataset = workloads.DATASETS[name],
		samples = counts[1],
		warmup = counts[2],
		setup = function(profile)
			local world = nativeApp({ viewport = profile.viewport })
			world.rowBuilder = rows.build
			world.rowSize = rows.estimate(world)
			if name == "theme-swap-flat" then
				local package = parchment.build(world.Facet.themes)
				world.themePackages = { package, package }
				world.themeNames = { "Daylight", "Candlelight" }
			elseif name == "theme-swap-metrics" then
				world.themePackages = {
					compactPointer.build(world.Facet.themes),
					(glossyTouch.build(world.Facet.themes)),
				}
			elseif name == "theme-swap-assets" then
				world.themePackages = { world.Facet.themes.neutralPackage(), (ornate.build(world.Facet.themes)) }
			end
			local workload
			world.runtime.mount(function()
				workload = workloads.create(world, name, dataset)
				return world.Host.ScreenGui({ workload.build() })
			end, world.target)
			world.workload = workload
			if name == "radial-menu-open-close" then
				for _ = 1, 3 do
					world.frame()
				end
			end
			if name == "adaptive-navigation-images" or name == "navigation-customization" then
				world.frame()
			end
			return world
		end,
		run = function(state)
			return state.workload.step()
		end,
		afterRun = function(state)
			if state.workload.afterRun then
				state.workload.afterRun()
			end
		end,
		asyncStats = function(state)
			return state.workload.async or { completed = 0, stale = 0, dropped = 0 }
		end,
		teardown = function(state)
			state.dispose()
		end,
		extras = function(state)
			return {
				workloadVersion = workloads.VERSION,
				datasetVersion = dataset.VERSION,
				logicalRows = if state.workload.rows then #state.workload.rows:peek() else nil,
				windowedRows = if state.workload.status then state.workload.status:peek().retained else nil,
				contentBuilds = state.workload.contentBuilds,
				motionSteps = state.workload.motionSteps,
				motionTransactions = state.workload.motionTransactions,
				staggerHeld = state.workload.staggerHeld,
				flipsSeen = state.workload.flipsSeen,
				shakesSeen = state.workload.shakesSeen,
				popsSeen = state.workload.popsSeen,
				beats = state.workload.beats,
				themeSwap = if string.sub(name, 1, 11) == "theme-swap-"
					then {
						measured = false,
						reason = "Native StyleSheet property and art changes are timed; Engine geometry, paint resolution and asset loading are not measured headlessly.",
					}
					else nil,
				geometryMeasured = false,
				activationCount = if state.workload.boosts then state.workload.boosts:peek() else nil,
				activationText = if state.workload.boostText then state.workload.boostText.Text else nil,
				measurementChange = if name == "shadow-storm"
					then "100 unchanged native shadows and runtime settle. Removed Facet presenter refresh/style_lint have no replacement CPU phase; Engine shadow painting is unmeasured. This is not a shadow rendering speedup."
					else "Compose and control property/event cost only. Roblox layout, text measurement, native selection, StyleSheet resolution and image fetching require Studio/retail evidence.",
			}
		end,
	})
end
return scenes
