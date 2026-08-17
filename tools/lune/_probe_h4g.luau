--!strict
--[[ Why is the probe plate's text cut off, and is that LuauUI's fault or the
	fixture's? (director, 2026-08-17: "why isn't luauui handling the overlap in the
	popup so that it's not cutoff right?")

	`c2.jpeg`: `734x393 s15 HELD / 14 of 14 rows wanted / 6 of 14 NOT PAINTED /`
	and the fourth line — the one that says WHY — sitting underneath the
	`Live again` button.

	This dumps the plate's own geometry out of the fake target and asks three
	questions the fixture never asked:
	  1. does the text node's box overlap the button's?
	  2. is the text taller than the box it was given?
	  3. did the SOLVER already say so? (docs/lessons/the-solver-already-told-you.md)

	Usage: lune run tools/lune/_probe_h4g
]]

local LuauUI = require("../../src") :: any
local fake_target = require("../../tests/lib/fake_target")
local hud = require("../../examples/gallery/scenarios/hud") :: any

local LANDSCAPE = {
	viewportRect = { x = 0, y = 0, w = 734, h = 393 },
	coreSafeInsets = { top = 120, right = 0, bottom = 0, left = 0 },
	deviceSafeInsets = { top = 0, right = 59, bottom = 21, left = 59 },
	topbarSafeInsets = { top = 0, bottom = 393 - 58, left = 164, right = 0 },
	topbarInset = { x = 164, y = 0, w = 570, h = 58 },
}

local RING = "/HudScreen/Hud/Clock/ClockStack/TimerPod/TimerRow/TimerRingBox/TimerRing/Ring/Track"
local built0: any = nil

local function world(): any
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	for k, v in LANDSCAPE do
		env:set(k, v)
	end
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local presenter = LuauUI.newPresenter(core, env, adapter, system)
	return { core = core, env = env, adapter = adapter, presenter = presenter, system = system }
end

local function mount(w: any, lie: ((path: string) -> any)?): any
	local built = hud.build({
		LuauUI = LuauUI,
		core = w.core,
		env = w.env,
		adapter = w.adapter,
		presenter = w.presenter,
		actionSystem = w.system,
		flags = {},
		geometry = function(paths: { string }): any
			local out: { [string]: any } = {}
			for _, path in paths do
				local node = w.adapter.node(path)
				if node ~= nil and node.rect ~= nil then
					local screenId = string.match(path, "^/([^/]+)")
					local forced = if lie ~= nil then lie(path) else nil
					out[path] = {
						x = node.rect.x,
						y = node.rect.y,
						w = node.rect.w,
						h = node.rect.h,
						visible = if type(forced) == "boolean" then forced else w.adapter.visibleOf(path) ~= false,
						enabled = if screenId ~= nil then w.adapter.rootVisibleOf(screenId) ~= false else true,
					}
				end
			end
			return out
		end,
		composition = function(path: string)
			return built0 ~= nil and built0.handle ~= nil and built0.handle.controller.compositionAt(path) or nil
		end,
	})
	built0 = built
	built.handle = w.presenter.present(built.screen, built.present)
	w.presenter.refresh()
	w.presenter.refresh()
	return built
end

local w = world()
-- lose six-plus rows, which is the shape the director photographed
local built = mount(w, function(path: string)
	if string.find(path, "^/HudScreen/Hud/") ~= nil and path ~= RING then
		return false
	end
	return nil
end)
built.steps.sampleProbe(built)
built.steps.sampleProbe(built)

local probe = built.report().paintProbe
print(`lost = {#probe.lost}`)
print("the plate, verbatim:")
for _, line in string.split(probe.plate, "\n") do
	print(`   |{line}`)
end

print("")
print("== the plate's own geometry ==")
local function box(path: string): any
	local n = w.adapter.node(path)
	return if n ~= nil then n.rect else nil
end
local ROOT = "/PaintProbe/ProbeField/ProbeSlot/ProbePlate"
for _, leaf in { "", "/ProbeBody", "/ProbeBody/ProbeHead", "/ProbeBody/ProbeLines", "/ProbeBody/ProbeHold" } do
	local p = ROOT .. leaf
	local r = box(p)
	print(
		string.format(
			"  %-46s %s",
			(if leaf == "" then "ProbePlate" else string.sub(leaf, 2)),
			if r == nil then "ABSENT" else string.format("%d,%d %dx%d", r.x, r.y, r.w, r.h)
		)
	)
end

local lines = box(ROOT .. "/ProbeBody/ProbeLines")
local hold = box(ROOT .. "/ProbeBody/ProbeHold")
local body = box(ROOT .. "/ProbeBody")
if lines ~= nil and hold ~= nil then
	local overlap = math.min(lines.y + lines.h, hold.y + hold.h) - math.max(lines.y, hold.y)
	print(`  text/button vertical overlap = {overlap}px  (>0 means the button is drawn over the text)`)
end
if lines ~= nil and body ~= nil then
	print(`  text bottom = {lines.y + lines.h}, body bottom = {body.y + body.h}`)
end

print("")
print("== what the SOLVER said about it ==")
local findings = built.handle.controller.diagnostics()
print(`  HUD surface: {#findings} finding(s)`)
for _, f in findings do
	print(`   {tostring(f.node)}: {tostring(f.issue)}`)
end
print("  (the plate is on its OWN surface, so the HUD's diagnostics cannot see it —")
print("   which is itself the answer to 'why did nobody notice')")

-- how many lines does the plate actually have, and how many fit?
local textLines = #string.split(probe.plate, "\n")
print("")
print(`  plate lines = {textLines}`)
if lines ~= nil then
	print(`  ProbeLines box height = {lines.h}px for {textLines - 1} body line(s)`)
end

built.dispose()
