--!strict
-- PROBE-EXEMPT: a benchmark WORKLOAD and its shared fixtures — INSTRUMENT, NOT
-- EXAMPLE. The gallery scenarios are the teaching surface.
--
-- THE TRANSIENT SURFACES (perf round 2026-09-11). Three player-visible landings
-- shipped after the last device capture with no workload aimed at them: the
-- Alert (a role-ordered action row that stacks under compact width, ten-foot
-- distance and large text), the Picker's menu style (an anchored popover that
-- materializes with a fade-and-grow — the phone and desktop default for every
-- settings row) and the radial menu (sector geometry that animates through the
-- solver while it opens). Each is a present/dismiss or open/close pair, which is
-- the shape no list workload prices: a surface's whole mount, its enter
-- transition's first frames, and its teardown, on one player event.
--
-- ONE FIXTURE PER LANDING, SHARED WITH THE HEADLESS BENCHMARK. `bench/perf_scenes`
-- builds the same three fixtures through `build`, so the trend gate and the
-- Studio capture price the same tree — the `navigation_inventory` precedent.
--
-- ENGINE-FREE, like every lab module: no `game`, no `Instance`, no `debug`. Every
-- seam arrives in `deps`. The passes obey the four rules `levers.luau` states:
-- one lap fits a 60-frame window, the arm identity is the pass name, every rep
-- yields through `telemetry.step()` outside the timed region, and every rep
-- provokes real solves.

local transientSurfaces = {}

transientSurfaces.PICKER_OPTIONS = 6
transientSurfaces.RADIAL_ITEMS = 6

export type Fixture = {
	-- mount the base surface this fixture opens over (idempotent)
	present: (pres: any) -> (),
	-- one player event each: the surface appears / goes away, with the presenter
	-- refreshed and ticked so the enter/exit transition's first frames are paid
	open: (pres: any) -> (),
	close: (pres: any) -> (),
	-- the proof counters a capture row carries beside the number
	proof: (pres: any) -> any,
	dispose: () -> (),
}

local function tickAndRefresh(pres: any, ticks: number)
	pres.refresh()
	for _ = 1, ticks do
		pres.tick(1 / 60)
		pres.refresh()
	end
end

-- the base every fixture opens over: one button, so the surface underneath has
-- a focusable to give focus back to
local function base(Facet: any, id: string)
	local UI = Facet.UI
	return UI.Screen({ id = id, padding = 12, children = { UI.Button({ id = "Open", label = "Open" }) } })
end

local function buildAlert(Facet: any, core: any): Fixture
	local alert = Facet.Controls.Alert(core, {
		id = "Confirm",
		title = "Delete this save?",
		message = "The save slot is cleared and the run restarts from the last checkpoint.",
		actions = {
			{ id = "Delete", label = "Delete", role = "destructive" },
			{ id = "Keep", label = "Keep a copy" },
			{ id = "Cancel", label = "Cancel", role = "cancel" },
		},
	})
	local baseHandle: any = nil
	local handle: any = nil
	local presents = 0
	return {
		present = function(pres)
			if baseHandle == nil then
				baseHandle = pres.present(base(Facet, "AlertBase"))
				pres.refresh()
				pres.focus.focusOn("/AlertBase/Open")
			end
		end,
		open = function(pres)
			handle = alert.present(pres)
			tickAndRefresh(pres, 1)
			presents += 1
		end,
		close = function(pres)
			pres.dismiss(handle)
			handle = nil
			tickAndRefresh(pres, 1)
		end,
		proof = function(_pres)
			return { presents = presents, actions = 3 }
		end,
		dispose = function()
			alert.dispose()
		end,
	}
end

local function buildPicker(Facet: any, core: any): Fixture
	local UI = Facet.UI
	local options = {}
	for i = 1, transientSurfaces.PICKER_OPTIONS do
		table.insert(options, { value = `q{i}`, label = `Quality {i}` })
	end
	local selected = core:signal("q3")
	local picker = Facet.Controls.Picker(core, {
		id = "Quality",
		label = "Quality",
		style = "menu",
		options = options,
		selected = selected,
	})
	local baseHandle: any = nil
	local opens = 0
	local presentation: string? = nil
	return {
		present = function(pres)
			if baseHandle == nil then
				baseHandle =
					pres.present(UI.Screen({ id = "PickerBase", padding = 12, children = { picker.blueprint } }))
				tickAndRefresh(pres, 1)
			end
		end,
		open = function(pres)
			picker.api.open()
			tickAndRefresh(pres, 1)
			local dump = picker.dump()
			assert(dump.open == true, "the picker menu must be open after api.open")
			presentation = dump.presentation
			opens += 1
		end,
		close = function(pres)
			picker.api.close()
			tickAndRefresh(pres, 1)
			assert(picker.dump().open == false, "the picker menu must be closed after api.close")
		end,
		proof = function(pres)
			return {
				opens = opens,
				options = transientSurfaces.PICKER_OPTIONS,
				presentation = presentation,
				anchoredAfter = pres.anchoredSurfaces().count,
			}
		end,
		dispose = function()
			picker.dispose()
		end,
	}
end

local function buildRadial(Facet: any, core: any): Fixture
	local UI = Facet.UI
	local items = {}
	for i, slot in { "N", "NE", "E", "S", "SW", "W" } do
		table.insert(items, { id = `act{i}`, label = `Action {i}`, slot = slot })
	end
	local menu = Facet.Controls.RadialMenu(core, {
		id = "Radial",
		preset = "donut",
		distribution = "compass",
		items = items,
	})
	local baseHandle: any = nil
	local opens = 0
	return {
		present = function(pres)
			if baseHandle == nil then
				baseHandle = pres.present(UI.Screen({ id = "RadialBase", children = { menu.blueprint } }))
				-- the launcher paints only once its position is solved (three ticks)
				tickAndRefresh(pres, 3)
			end
		end,
		open = function(pres)
			local opened = menu.api.open()
			tickAndRefresh(pres, 2)
			assert(opened == true and menu.dump().open == true, "the radial must open from its solved launcher")
			opens += 1
		end,
		close = function(pres)
			menu.api.close()
			tickAndRefresh(pres, 2)
			assert(menu.dump().open == false, "the radial must be closed after api.close")
		end,
		proof = function(_pres)
			return { opens = opens, sectors = #menu.dump().sectors }
		end,
		dispose = function()
			menu.dispose()
		end,
	}
end

-- `kind` is "alert" | "picker" | "radial"; anything else is refused by name
function transientSurfaces.build(Facet: any, core: any, kind: string): Fixture
	if kind == "alert" then
		return buildAlert(Facet, core)
	elseif kind == "picker" then
		return buildPicker(Facet, core)
	elseif kind == "radial" then
		return buildRadial(Facet, core)
	end
	error(`transient_surfaces: unknown fixture '{tostring(kind)}' (alert | picker | radial)`)
end

-- Installed in the existing lab; all UI and frame seams remain caller-owned.
-- One pass per fixture: `reps` open/close pairs, each timed as two player events
-- (open, close) with the frame yield between them outside the timed region.
function transientSurfaces.install(deps: any)
	local function pass(name: string, kind: string)
		deps.passes[name] = function(payload: string?)
			return deps.timed(name, function()
				local _, reps = deps.framesAndReps(payload, 60, 24)
				local fixture = transientSurfaces.build(deps.Facet, deps.core, kind)
				local pres = deps.ctx.presenter
				local ok, result = pcall(function()
					fixture.present(pres)
					local samples = { open = {}, close = {} }
					for _ = 1, reps do
						deps.telemetry.step()
						local start = deps.telemetry.clock()
						fixture.open(pres)
						table.insert(samples.open, (deps.telemetry.clock() - start) * 1000)
						deps.telemetry.step()
						start = deps.telemetry.clock()
						fixture.close(pres)
						table.insert(samples.close, (deps.telemetry.clock() - start) * 1000)
					end
					local proof = fixture.proof(pres)
					return {
						reps = reps,
						fixture = kind,
						openMs = deps.summarize(samples.open),
						closeMs = deps.summarize(samples.close),
						proof = proof,
					}
				end)
				fixture.dispose()
				if not ok then
					error(result, 0)
				end
				return result
			end)
		end
	end
	pass("alertPresent", "alert")
	pass("pickerMenu", "picker")
	pass("radialOpen", "radial")
end

return transientSurfaces
