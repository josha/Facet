--!strict
--[[ NM-H4a round 4 — THE PLATE SAYS 14 OF 14 PAINTING OVER A SCREEN THAT IS NOT.

	`a1.jpeg`, 2026-08-17: the right-hand rail is back (the band fix), and the whole
	LEFT column — Objective, the round discs, Tasks, Health, Feed, ScoreHome — is
	still gone. The plate reads `14 of 14 rows wanted / 14 of 14 painting`.
	Toggling the URL bar in landscape repairs it.

	`enginePaints` compares the engine's rect against the solver's on `w`/`h` ONLY,
	and calls a difference a NOTE rather than a verdict. It never looks at `x`/`y`
	and never asks whether the box is on the screen at all. So a node the engine
	draws at a stale POSITION — or off the bottom of a rotated window — reports
	painting, at full size, forever.

	This asks the question the instrument does not: after the sequence, does every
	node's ENGINE rect still equal the rect the solver gave it?

	Usage: lune run tools/lune/_probe_h4f
]]

local LuauUI = require("../../src") :: any
local fake_target = require("../../tests/lib/fake_target")
local hud = require("../../examples/gallery/scenarios/hud") :: any

local PORTRAIT = {
	viewportRect = { x = 0, y = 0, w = 393, h = 852 },
	coreSafeInsets = { top = 58, right = 0, bottom = 0, left = 0 },
	deviceSafeInsets = { top = 59, right = 0, bottom = 34, left = 0 },
	topbarSafeInsets = { top = 0, bottom = 852 - 58, left = 164, right = 0 },
	topbarInset = { x = 164, y = 0, w = 229, h = 58 },
}
local LANDSCAPE = {
	viewportRect = { x = 0, y = 0, w = 734, h = 393 },
	coreSafeInsets = { top = 120, right = 0, bottom = 0, left = 0 },
	deviceSafeInsets = { top = 0, right = 59, bottom = 21, left = 59 },
	topbarSafeInsets = { top = 0, bottom = 393 - 58, left = 164, right = 0 },
	topbarInset = { x = 164, y = 0, w = 570, h = 58 },
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
	for k, v in view do
		env:set(k, v)
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

local function setView(w: any, view: any, splitFrames: boolean)
	if splitFrames then
		-- the engine updates the camera and the inset areas on different frames
		w.env:set("viewportRect", view.viewportRect)
		w.presenter.refresh()
		w.env:set("coreSafeInsets", view.coreSafeInsets)
		w.env:set("deviceSafeInsets", view.deviceSafeInsets)
		w.env:set("topbarSafeInsets", view.topbarSafeInsets)
		w.env:set("topbarInset", view.topbarInset)
		w.presenter.refresh()
		w.presenter.refresh()
	else
		for k, v in view do
			w.env:set(k, v)
		end
		w.presenter.refresh()
		w.presenter.refresh()
	end
end

--[[ THE QUESTION THE PROBE DOES NOT ASK. For every node the surface owns, compare
	what the SOLVER says its screen rect is against what the ENGINE was actually
	told. They must be equal; a difference is a write that never landed. ]]
local function auditRects(w: any, built: any, label: string)
	local ctrl = built.handle.controller
	local bad, total = 0, 0
	local samples: { string } = {}
	local offscreen = 0
	local vp = w.env:get("viewportRect"):get() :: any
	for _, path in w.adapter.paths() do
		if string.find(path, "^/HudScreen") == nil then
			continue
		end
		local node = w.adapter.node(path)
		local want = ctrl.screenRectOf(path)
		if node == nil or node.rect == nil or want == nil then
			continue
		end
		total += 1
		local dx = math.abs(node.rect.x - want.x)
		local dy = math.abs(node.rect.y - want.y)
		if dx > 1 or dy > 1 then
			bad += 1
			if #samples < 10 then
				table.insert(
					samples,
					string.format(
						"%s engine=%d,%d solver=%d,%d",
						path,
						math.floor(node.rect.x),
						math.floor(node.rect.y),
						math.floor(want.x),
						math.floor(want.y)
					)
				)
			end
		end
		-- ...and the other half the instrument never asks: is the box on screen?
		if
			node.rect.x + node.rect.w <= 0
			or node.rect.y + node.rect.h <= 0
			or node.rect.x >= vp.w
			or node.rect.y >= vp.h
		then
			offscreen += 1
		end
	end
	print(string.format("%-44s %3d nodes, %d at a stale position, %d off screen", label, total, bad, offscreen))
	for _, s in samples do
		print(`     {s}`)
	end
	return bad, offscreen
end

for _, split in { false, true } do
	print(`=== the director's sequence, insets on ` .. (if split then "a LATER frame" else "the same frame") .. " ===")
	local w = world(PORTRAIT)
	local built = mount(w)
	auditRects(w, built, "portrait, mounted")

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
	auditRects(w, built, "portrait, after the steps")

	setView(w, LANDSCAPE, split)
	auditRects(w, built, "LANDSCAPE — the failing frame")

	-- the director's own repair: toggle the URL bar in landscape
	built.steps.openUrlBar(built)
	w.presenter.refresh()
	built.steps.closeUrlBar(built)
	w.presenter.refresh()
	auditRects(w, built, "...after toggling the URL bar (the repair)")
	built.dispose()
	print("")
end
