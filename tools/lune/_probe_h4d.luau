--!strict
--[[ NM-H4a round 2 — `riding` IS BOUND TO A PLATFORM FACT THAT CAN GO AWAY.

	`Objective` sits behind `UI.When{ condition = riding }`, and

	    riding = ride AND platformChrome.band ~= nil
	    band   = nil whenever coreSafeInsets.top == 0, or the topbar rect is
	             missing/zero, or its intersection with the safe box is empty
	             (src/env/environment.luau:305-343)

	so the plate's `13 of 14 rows wanted / skipped: Objective` is what the model
	prints when the platform's top band is not there. 36 624 swept states never
	printed it because every one of them MOUNTED FRESH with a band present. The
	question is what happens when the band goes away UNDER a mounted surface, and
	whether it comes back.

	Usage: lune run tools/lune/_probe_h4d
]]

local LuauUI = require("../../src") :: any
local fake_target = require("../../tests/lib/fake_target")
local hud = require("../../examples/gallery/scenarios/hud") :: any

local PORTRAIT = {
	viewportRect = { x = 0, y = 0, w = 393, h = 852 },
	coreSafeInsets = { top = 58, right = 0, bottom = 0, left = 0 },
	deviceSafeInsets = { top = 59, right = 0, bottom = 34, left = 0 },
	topbarInset = { x = 164, y = 0, w = 229, h = 58 },
}
local LANDSCAPE = {
	viewportRect = { x = 0, y = 0, w = 852, h = 393 },
	coreSafeInsets = { top = 46, right = 0, bottom = 0, left = 0 },
	deviceSafeInsets = { top = 0, right = 59, bottom = 21, left = 59 },
	topbarInset = { x = 223, y = 0, w = 629, h = 46 },
}

local built0: any = nil

local function geometryFor(w: any): (paths: { string }) -> any
	return function(paths: { string }): any
		local out: { [string]: any } = {}
		for _, path in paths do
			local node = w.adapter.node(path)
			if node ~= nil and node.rect ~= nil then
				local screenId = string.match(path, "^/([^/]+)")
				out[path] = {
					x = node.rect.x,
					y = node.rect.y,
					w = node.rect.w,
					h = node.rect.h,
					visible = w.adapter.visibleOf(path) ~= false,
					enabled = if screenId ~= nil then w.adapter.rootVisibleOf(screenId) ~= false else true,
				}
			end
		end
		return out
	end
end

local function world(view: any): any
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	for key, value in view do
		env:set(key, value)
	end
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local presenter = LuauUI.newPresenter(core, env, adapter, system)
	return { core = core, env = env, adapter = adapter, presenter = presenter, system = system }
end

local function mount(w: any): any
	local built = hud.build({
		LuauUI = LuauUI,
		core = w.core,
		env = w.env,
		adapter = w.adapter,
		presenter = w.presenter,
		actionSystem = w.system,
		flags = {},
		geometry = geometryFor(w),
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

local function say(w: any, built: any, label: string)
	local r = built.report()
	local p = r.paintProbe
	local skipped = table.clone(p.skipped or {})
	table.sort(skipped)
	local rail = w.adapter.node("/HudScreen/Hud/Actions/ActionsCol/A2")
	local railR = w.adapter.node("/HudScreen/Hud/Actions/A1r")
	print(
		string.format(
			"%-46s riding=%-5s  %2d of %d rows wanted  skipped=[%s]  lost=%d  ActionsCol/A2=%s A1r=%s",
			label,
			tostring(r.riding),
			p.expected,
			p.declared,
			table.concat(skipped, ","),
			#p.lost,
			if rail ~= nil then tostring(w.adapter.visibleOf(rail.path)) else "absent",
			if railR ~= nil then tostring(w.adapter.visibleOf(railR.path)) else "absent"
		)
	)
	return r
end

print("=== the band goes away under a MOUNTED surface, then comes back ===")
local w = world(PORTRAIT)
local built = mount(w)
say(w, built, "portrait, mounted")

-- the director's steps, which is when a real client hides its topbar
built.steps.openOverflow(built)
w.presenter.refresh()
built.steps.closeOverflow(built)
w.presenter.refresh()
built.steps.openUrlBar(built)
w.presenter.refresh()
built.steps.openOverflow(built)
w.presenter.refresh()
built.steps.closeOverflow(built)
w.presenter.refresh()
built.steps.closeUrlBar(built)
w.presenter.refresh()
say(w, built, "portrait, after the director's steps")

--[[ THE ROTATION, WITH THE BAND MOMENTARILY ABSENT. A real client republishes
	`coreSafeInsets` and `topbarInset` across an orientation change; the frame
	where the top inset is 0 is the frame where `band` is nil. ]]
w.env:set("viewportRect", LANDSCAPE.viewportRect)
w.env:set("coreSafeInsets", { top = 0, right = 0, bottom = 0, left = 0 })
w.env:set("deviceSafeInsets", LANDSCAPE.deviceSafeInsets)
w.presenter.refresh()
local dark = say(w, built, "LANDSCAPE, band absent (coreTop=0)")

-- ...and the inset arrives a frame later, as it does on a device
w.env:set("coreSafeInsets", LANDSCAPE.coreSafeInsets)
w.env:set("topbarInset", LANDSCAPE.topbarInset)
w.presenter.refresh()
w.presenter.refresh()
local after = say(w, built, "LANDSCAPE, band restored (the next frame)")

-- the fresh-mount oracle at the same view
local fw = world(LANDSCAPE)
local fresh = mount(fw)
say(fw, fresh, "FRESH landscape mount (the oracle)")

print("")
print(`band-absent frame matches the phone's plate (13 wanted, skipped Objective): ` .. tostring(dark ~= nil))
built.dispose()
fresh.dispose()
