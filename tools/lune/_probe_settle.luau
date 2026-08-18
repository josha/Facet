--!strict
-- L-31 probe: the measure->publish feedback loop, reproduced headless in the
-- GENERAL shape (a dock surface that publishes its measured height as a safe
-- area inset, and a content surface that lays out inside what is left).
-- Two arms: WITH the reservation dance and WITHOUT it, so the loop's cost is a
-- difference rather than an attribution.
-- Usage: lune run tools/lune/_probe_settle

local Facet = require("../../src") :: any
local fake_target = require("../../tests/lib/fake_target")
local profile = require("../../src/core/profile")

local spans: { [string]: number } = {}
local trace: { string } = {}
local tracing = false
profile.setEnabled(true)
profile.setHooks(function(label: string)
	spans[label] = (spans[label] or 0) + 1
	if tracing and (label == "Facet/react" or label == "Facet/arrange" or label == "Facet/mount") then
		table.insert(trace, (label:gsub("Facet/", "")))
	end
end, function() end)

local SHAPES = {
	{ w = 360, h = 691 },
	{ w = 500, h = 800 },
	{ w = 390, h = 844 },
	{ w = 700, h = 600 },
}

local function arm(withDance: boolean, withForget: boolean?)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 900, h = 700 })
	local system = Facet.newActionSystem(core)
	local pres = Facet.newPresenter(core, env, fake_target.new(), system)

	local rows = {}
	for i = 1, 40 do
		table.insert(
			rows,
			Facet.UI.HStack({
				id = "R" .. i,
				width = { type = "fill", weight = 1 },
				children = {
					Facet.UI.Text({ id = "A", text = "Row " .. i }),
					Facet.UI.Spacer({ id = "S" }),
					Facet.UI.Text({ id = "B", text = "value " .. i }),
				},
			})
		)
	end
	local workload =
		pres.present(Facet.UI.Screen({ id = "W", children = { Facet.UI.VStack({ id = "List", children = rows }) } }))

	local reservedBottom = 0
	local function reserveBottom(px: number)
		local want = math.max(0, math.floor(px))
		local live = env:get("coreSafeInsets"):get()
		local other = if type(live) == "table" then live else {}
		reservedBottom = want
		if (other.bottom or 0) == want then
			return
		end
		env:set("coreSafeInsets", {
			top = other.top or 0,
			bottom = want,
			left = other.left or 0,
			right = other.right or 0,
		})
	end
	local function forgetReservation()
		reservedBottom = -1
		reserveBottom(0)
	end
	if withDance and withForget ~= false then
		core:observe(env:get("viewportRect"), forgetReservation)
		core:observe(env:get("typographyScale"), forgetReservation)
	end

	local dock = pres.present(
		Facet.UI.Screen({
			id = "D",
			children = {
				Facet.UI.VStack({
					id = "Dock",
					children = {
						Facet.UI.Spacer({ id = "Push" }),
						Facet.UI.VStack({
							id = "Panel",
							height = { type = "percent", fraction = 0.34, min = 96, max = 260 },
							children = {
								Facet.UI.Text({ id = "T1", text = "perf lab overlay" }),
								Facet.UI.Text({ id = "T2", text = "scenario picker" }),
							},
						}),
					},
				}),
			},
		}),
		{
			responder = "passive",
			rootPolicy = "edgeToEdge",
			onGeometry = if withDance
				then function(rectOf: (string) -> any)
					local r = rectOf("/D/Dock/Panel")
					if type(r) == "table" and type(r.h) == "number" then
						reserveBottom(r.h + 8)
					end
				end
				else nil,
		}
	)
	pres.refresh()

	local function solves(h: any): number
		return ((h.controller.stats() :: any).solves :: number) or 0
	end

	local w0, d0 = solves(workload), solves(dock)
	local s0 = { react = spans["Facet/react"] or 0, arrange = spans["Facet/arrange"] or 0 }
	tracing = true
	trace = {}
	for _, shape in SHAPES do
		env:batch(function()
			env:set("viewportRect", { x = 0, y = 0, w = shape.w, h = shape.h })
			env:set("coreSafeInsets", { top = 36, bottom = 0, left = 0, right = 0 })
			env:set("deviceSafeInsets", { top = 44, bottom = 34, left = 0, right = 0 })
			env:set("topbarSafeInsets", { top = 36, bottom = 0, left = 0, right = 0 })
			env:set("topbarInset", { x = 0, y = 0, w = shape.w, h = 36 })
			env:set("displaySize", "Medium")
		end)
		local afterBatch = workload.controller.rectOf("/W")
		pres.refresh()
		local afterRefresh = workload.controller.rectOf("/W")
		table.insert(trace, `|h={afterBatch and afterBatch.h} then {afterRefresh and afterRefresh.h}|`)
	end
	tracing = false

	local n = #SHAPES
	print(
		`dance={tostring(withDance)} forget={tostring(withForget)}  workloadSolves/step={(solves(workload) - w0) / n}  dockSolves/step={(solves(
			dock
		) - d0) / n}`
			.. `  arrange/step={((spans["Facet/arrange"] or 0) - s0.arrange) / n}`
			.. `  react/step={((spans["Facet/react"] or 0) - s0.react) / n}`
	)
	print(`  trace: {table.concat(trace, " ")}`)
	print(`  lastError = {tostring(core:lastError())}`)
end

arm(false)
arm(true, false)
arm(true, true)
