--!strict
local Compose = require("../../../src/vendor/compose/core")
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
local function base(ctx: any, id: string)
	local UI = ctx.UI
	return UI.Screen(id)({ padding = 12, UI.Button({ id = "Open", label = "Open" }) })
end

-- present a base screen through the application's mount when the caller has one
-- (the mount is the owner its controls build under), else straight to the
-- presenter; answers the close
local function presentBase(ctx: any, pres: any, screen: () -> any): () -> ()
	if ctx.app ~= nil then
		return (ctx.app.mount(screen))
	end
	local handle = pres.present(screen())
	return function()
		pres.dismiss(handle)
	end
end

local function buildAlert(ctx: any): Fixture
	local core = ctx.core
	-- Built under this fixture's own owner, so disposing it is the teardown.
	local alert: any = nil
	local alertScope = core.owner.createChild()
	ctx.Compose.withOwner(alertScope, function()
		return ctx.UI.Alert({
			id = "Confirm",
			title = "Delete this save?",
			message = "The save slot is cleared and the run restarts from the last checkpoint.",
			actions = {
				{ id = "Delete", label = "Delete", role = "destructive" },
				{ id = "Keep", label = "Keep a copy" },
				{ id = "Cancel", label = "Cancel", role = "cancel" },
			},
			ref = function(record: any)
				alert = record.api
			end,
		})
	end)
	local baseHandle: any = nil
	local handle: any = nil
	local lastHandle: any = nil
	local presents = 0
	-- represents ONLY the transitions round bug (task-2 review, 2026-09-12):
	-- `pres.dismiss(handle)` here used to bypass the alert's OWN `dismiss()`,
	-- so its internal `handle` local (alert.luau's `if handle then return
	-- handle end`) never cleared while a real exit transition kept the old
	-- surface's scope alive — `open()` then returned the SAME handle forever,
	-- `presents` kept counting, and the scene silently measured nothing from
	-- cycle 2 on. `represents` only counts a cycle whose `open()` handed back
	-- a DIFFERENT handle than the one before it, so a stuck handle reddens
	-- `tools/check_perf_scenes.py` instead of quietly halving the number.
	local represents = 0
	return {
		present = function(pres)
			if baseHandle == nil then
				baseHandle = presentBase(ctx, pres, function()
					return base(ctx, "AlertBase")
				end)
				pres.refresh()
				pres.focus.focusOn("/AlertBase/Open")
			end
		end,
		open = function(pres)
			handle = alert.present(pres)
			tickAndRefresh(pres, 1)
			presents += 1
			if handle ~= lastHandle then
				represents += 1
				lastHandle = handle
			end
		end,
		close = function(pres)
			-- THE ALERT'S OWN `dismiss()`, not a raw `pres.dismiss(handle)`: it
			-- resets alert.luau's internal `handle` local SYNCHRONOUSLY (the same
			-- decoupled-flag pattern `buildPicker`'s `picker.api.close()` already
			-- uses), so the next `open()` re-presents for real instead of waiting
			-- out the exit transition's up-to-500ms hard cap.
			alert.dismiss()
			handle = nil
			tickAndRefresh(pres, 1)
		end,
		proof = function(_pres)
			return { presents = presents, represents = represents, actions = 3 }
		end,
		dispose = function()
			if baseHandle ~= nil then
				baseHandle()
				baseHandle = nil
			end
			alertScope:dispose()
		end,
	}
end

local function buildPicker(ctx: any): Fixture
	local core = ctx.core
	local UI = ctx.UI
	local options = {}
	for i = 1, transientSurfaces.PICKER_OPTIONS do
		table.insert(options, { value = `q{i}`, label = `Quality {i}` })
	end
	local selected = Compose.cell("q3")
	-- Picker's `menu` style wraps `pickerMenu.build` and re-exposes it as a
	-- NESTED `.api` (picker.luau's `buildMenu`), so — unlike Alert above — the
	-- composite record's `ref` gives `record.api` = that inner api, not the
	-- outer table, and does not carry `.blueprint` or `.dispose`. Building under
	-- an explicit owner (this fixture's own scope) is what makes `.dispose()`
	-- reachable: the ambient Compose owner is who `Compose.cleanup` registers
	-- the real teardown with.
	local pickerScope = core.owner.createChild()
	local pickerRecord: any = nil
	local pickerBlueprint = ctx.Compose.withOwner(pickerScope, function()
		return UI.Picker({
			id = "Quality",
			label = "Quality",
			style = "menu",
			options = options,
			selected = selected,
			ref = function(record: any)
				pickerRecord = record
			end,
		})
	end)
	local baseHandle: any = nil
	local opens = 0
	local presentation: string? = nil
	return {
		present = function(pres)
			if baseHandle == nil then
				baseHandle = presentBase(ctx, pres, function()
					return UI.Screen("PickerBase")({ padding = 12, pickerBlueprint })
				end)
				tickAndRefresh(pres, 1)
			end
		end,
		open = function(pres)
			pickerRecord.api.open()
			tickAndRefresh(pres, 1)
			local dump = pickerRecord.dump()
			assert(dump.open == true, "the picker menu must be open after api.open")
			presentation = dump.presentation
			opens += 1
		end,
		close = function(pres)
			pickerRecord.api.close()
			tickAndRefresh(pres, 1)
			assert(pickerRecord.dump().open == false, "the picker menu must be closed after api.close")
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
			if baseHandle ~= nil then
				baseHandle()
				baseHandle = nil
			end
			pickerScope:dispose()
		end,
	}
end

local function buildRadial(ctx: any): Fixture
	local core = ctx.core
	local UI = ctx.UI
	local items = {}
	for i, slot in { "N", "NE", "E", "S", "SW", "W" } do
		table.insert(items, { id = `act{i}`, label = `Action {i}`, slot = slot })
	end
	-- Same nested-`.api` shape as Picker's menu style (radial_menu.luau's own
	-- `build` sets a top-level `.api` field), so the same owner-scoped build is
	-- what makes `.dispose()` reachable.
	local radialScope = core.owner.createChild()
	local menuRecord: any = nil
	local menuBlueprint = ctx.Compose.withOwner(radialScope, function()
		return UI.RadialMenu({
			id = "Radial",
			preset = "donut",
			distribution = "compass",
			items = items,
			ref = function(record: any)
				menuRecord = record
			end,
		})
	end)
	local baseHandle: any = nil
	local opens = 0
	return {
		present = function(pres)
			if baseHandle == nil then
				baseHandle = presentBase(ctx, pres, function()
					return UI.Screen("RadialBase")({ menuBlueprint })
				end)
				-- the launcher paints only once its position is solved (three ticks)
				tickAndRefresh(pres, 3)
			end
		end,
		open = function(pres)
			local opened = menuRecord.api.open()
			tickAndRefresh(pres, 2)
			assert(opened == true and menuRecord.dump().open == true, "the radial must open from its solved launcher")
			opens += 1
		end,
		close = function(pres)
			menuRecord.api.close()
			tickAndRefresh(pres, 2)
			assert(menuRecord.dump().open == false, "the radial must be closed after api.close")
		end,
		proof = function(_pres)
			return { opens = opens, sectors = #menuRecord.dump().sectors }
		end,
		dispose = function()
			if baseHandle ~= nil then
				baseHandle()
				baseHandle = nil
			end
			radialScope:dispose()
		end,
	}
end

-- `kind` is "alert" | "picker" | "radial"; anything else is refused by name.
-- `ctx = { Facet, app, UI, Compose, env, core }` (bench/perf_scenes.luau's
-- `labContext`) — `core` arrives on it, not as its own argument.
function transientSurfaces.build(ctx: any, kind: string): Fixture
	if kind == "alert" then
		return buildAlert(ctx)
	elseif kind == "picker" then
		return buildPicker(ctx)
	elseif kind == "radial" then
		return buildRadial(ctx)
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
				local fixture = transientSurfaces.build(deps.Facet, kind)
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
