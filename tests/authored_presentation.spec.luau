--!strict
--[[ AUTHORED PRESENTATION — `opacity`, `scale`, `rotation` (ADR-0026).

	The director's ruling, 2026-08-14: *"should opacity, transparency, and scale
	get owned/influenced by luauui? it seems like we should be able to animate
	those."*

	THE WHOLE DESIGN IN ONE SENTENCE, and every case below defends one clause of
	it: an authored value is an **input to the presentation authority**, never a
	second writer — the renderer composes (channel value x authored value) at ONE
	write site, and `withAnimation` adds a third term to that same composition.

	So the cases split four ways:

	  A. AUTHORING — the props exist, they are reactive, and the refusals are
	     loud (a leaf cannot fade; a scale of zero is not a small view).
	  B. COMPOSITION — the arithmetic Apple states ([SW-141]): opacity and scale
	     MULTIPLY, rotation ADDS, and clearing one contributor leaves the other
	     standing rather than snapping the node to identity.
	  C. ANIMATION — all three travel on the SAME progress spring the position
	     and size halves already use, and reduced motion deletes the flight and
	     never the destination.
	  D. COST AND AUTHORITY — a surface that authors none of the three pays
	     nothing, and there is still exactly ONE site in the renderer that writes
	     each of the two presentation engine properties.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local fake_target = require("./lib/fake_target")

local FRAME = 1 / 60

local function settle(pres: any)
	for _ = 1, 120 do
		pres.tick(FRAME)
	end
end

-- The shared world: a Screen holding one fade-capable Box whose three authored
-- presentation values are signal-driven, plus a plain sibling that authors none
-- of them (the off-path control).
local function world(opts: any?)
	local options = opts or {}
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	if options.reducedMotion then
		env:set("reducedMotion", true)
	end
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)

	local opacity = core:signal(options.opacity or 1)
	local scale = core:signal(options.scale or 1)
	local rotation = core:signal(options.rotation or 0)
	-- the GEOMETRIC half, so one call can move a node and fade another and the
	-- shared-spring case can compare their progress
	local tall = core:signal(false)
	local faderHeight = core:memo(function(use: any)
		return { type = "fixed", px = if use(tall) then 200 else 100 }
	end)

	local UI = LuauUI.UI
	local screen = UI.Screen({
		id = "S",
		padding = 0,
		gap = 0,
		children = {
			UI.Box({
				id = "Fader",
				height = faderHeight,
				opacity = opacity,
				scale = scale,
				rotation = rotation,
			}),
			UI.Box({ id = "Plain", height = { type = "fixed", px = 100 } }),
		},
	})
	local handle = pres.present(screen)
	pres.refresh()
	return {
		core = core,
		env = env,
		adapter = adapter,
		pres = pres,
		handle = handle,
		opacity = opacity,
		scale = scale,
		rotation = rotation,
		tall = tall,
	}
end

-- what the engine would actually be told: GroupTransparency on the fade group
local function groupAlpha(w: any, path: string): any
	local node = w.adapter.node(path)
	if node == nil or node.canvasGroupInstance == nil then
		return nil
	end
	return node.canvasGroupInstance.groupTransparency
end

local function paintedScale(w: any, path: string): number
	local node = w.adapter.node(path)
	if node == nil or node.motionScaleInstance == nil then
		return 1
	end
	return node.motionScaleInstance.scale
end

local function paintedRotation(w: any, path: string): number
	local node = w.adapter.node(path)
	return (node ~= nil and node.rotation) or 0
end

describe("authored presentation A — the props, and the refusals", function()
	it("declaring `opacity` makes the node a fade group with no `canvasGroup` beside it", function()
		local w = world({ opacity = 0.5 })
		-- the node materialized as a CanvasGroup even though nothing said so
		expect(w.adapter.node("/S/Fader").canvasGroupInstance).never().toBeNil()
		-- ...and it is painted at the authored alpha, in ENGINE units (1 - opacity)
		expect(groupAlpha(w, "/S/Fader")).toBeCloseTo(0.5)
	end)

	it("a plain sibling is NOT promoted to a fade group", function()
		local w = world()
		expect(w.adapter.node("/S/Plain").canvasGroupInstance).toBeNil()
	end)

	it("all three are reactive, and a change repaints without a remount", function()
		local w = world()
		w.adapter.takeOps()
		w.opacity:set(0.25)
		w.scale:set(2)
		w.rotation:set(30)
		w.pres.refresh()
		expect(groupAlpha(w, "/S/Fader")).toBeCloseTo(0.75)
		expect(paintedScale(w, "/S/Fader")).toBeCloseTo(2)
		expect(paintedRotation(w, "/S/Fader")).toBeCloseTo(30)
		local created = 0
		for _, op in w.adapter.takeOps() do
			if string.find(op, "create ", 1, true) == 1 then
				created += 1
			end
		end
		expect(created).toBe(0)
	end)

	it("`opacity` on a LEAF is refused at construction, because a leaf fade would defeat the sheet", function()
		local UI = LuauUI.UI
		local ok, err = pcall(function()
			return UI.Text({ text = "hi", opacity = 0.5 })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "opacity", 1, true) ~= nil).toBe(true)
	end)

	it("`scale` and `rotation` ARE offered on a leaf — neither touches a sheet-owned property", function()
		local UI = LuauUI.UI
		expect(function()
				return UI.Text({ text = "hi", scale = 1.2, rotation = 8 })
			end)
			.never()
			.toThrow()
	end)

	it("the authored domain is refused rather than clamped: opacity outside 0..1, scale <= 0", function()
		local UI = LuauUI.UI
		expect(function()
			return UI.Box({ opacity = 1.5 })
		end).toThrow()
		expect(function()
			return UI.Box({ opacity = -0.1 })
		end).toThrow()
		expect(function()
			return UI.Box({ scale = 0 })
		end).toThrow()
		expect(function()
			return UI.Box({ scale = -1 })
		end).toThrow()
	end)

	it("a REACTIVE value out of domain is refused at the read site too, not silently painted", function()
		local w = world()
		local ok = pcall(function()
			w.opacity:set(4)
			w.pres.refresh()
		end)
		expect(ok).toBe(false)
	end)
end)

describe("authored presentation B — the composition rule (ADR-0026 Decision 2)", function()
	it("OPACITY MULTIPLIES: authored 0.5 under a framework fade of 0.5 paints 0.25 opacity", function()
		local w = world({ opacity = 0.5 })
		-- the framework's own fade — a transition, a toast retiring — on the same node
		w.handle.controller.setPresentationTransparency("/S/Fader", 0.5)
		-- effective opacity 0.5 x 0.5 = 0.25, i.e. transparency 0.75
		expect(groupAlpha(w, "/S/Fader")).toBeCloseTo(0.75)
	end)

	it("SCALE MULTIPLIES: authored 2 under a presentation scale of 1.5 paints 3", function()
		local w = world({ scale = 2 })
		w.handle.controller.setPresentationTransform("/S/Fader", { x = 0, y = 0, scale = 1.5 })
		expect(paintedScale(w, "/S/Fader")).toBeCloseTo(3)
	end)

	it("ROTATION ADDS: authored 30 under a presentation rotation of 15 paints 45", function()
		local w = world({ rotation = 30 })
		w.handle.controller.setPresentationTransform("/S/Fader", { x = 0, y = 0, rotation = 15 })
		expect(paintedRotation(w, "/S/Fader")).toBeCloseTo(45)
	end)

	it("clearing the FRAMEWORK's contribution leaves the AUTHORED value standing", function()
		local w = world({ opacity = 0.5, scale = 2, rotation = 30 })
		w.handle.controller.setPresentationTransparency("/S/Fader", 0.5)
		w.handle.controller.setPresentationTransform("/S/Fader", { x = 0, y = 0, scale = 1.5, rotation = 15 })
		w.handle.controller.setPresentationTransparency("/S/Fader", nil)
		w.handle.controller.setPresentationTransform("/S/Fader", nil)
		-- a second WRITER would have stomped these back to identity; a second TERM
		-- does not
		expect(groupAlpha(w, "/S/Fader")).toBeCloseTo(0.5)
		expect(paintedScale(w, "/S/Fader")).toBeCloseTo(2)
		expect(paintedRotation(w, "/S/Fader")).toBeCloseTo(30)
	end)

	it("the offset half is untouched by an authored scale: x/y still compose onto the rect", function()
		local w = world({ scale = 2 })
		local before = w.adapter.node("/S/Fader").rect.y
		w.handle.controller.setPresentationTransform("/S/Fader", { x = 0, y = -20 })
		expect(w.adapter.node("/S/Fader").presentedPosition.y).toBe(before - 20)
		-- ...and the authored scale survived the transform write that carried no scale
		expect(paintedScale(w, "/S/Fader")).toBeCloseTo(2)
	end)

	it("NESTED groups do NOT double-compose: the engine multiplies across nodes, the framework within one", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local UI = LuauUI.UI
		pres.present(UI.Screen({
			id = "S",
			padding = 0,
			gap = 0,
			children = {
				UI.ZStack({
					id = "Outer",
					opacity = 0.5,
					children = { UI.ZStack({ id = "Inner", opacity = 0.5, children = { UI.Text({ text = "x" }) } }) },
				}),
			},
		}))
		pres.refresh()
		-- each node carries ONLY its own authored alpha. The visible 0.25 is the
		-- engine's, because a fade group is genuinely its subtree's instance parent.
		expect(adapter.node("/S/Outer").canvasGroupInstance.groupTransparency).toBeCloseTo(0.5)
		expect(adapter.node("/S/Outer/Inner").canvasGroupInstance.groupTransparency).toBeCloseTo(0.5)
	end)
end)

describe("authored presentation C — withAnimation reaches all three", function()
	it("an OPACITY change seeds at the old value and travels to the new", function()
		local w = world({ opacity = 1 })
		w.pres.withAnimation("container", function()
			w.opacity:set(0)
		end)
		-- seeded synchronously: it must not paint one frame at the destination
		expect(groupAlpha(w, "/S/Fader")).toBeCloseTo(0)
		for _ = 1, 6 do
			w.pres.tick(FRAME)
		end
		local mid = groupAlpha(w, "/S/Fader")
		expect(mid).toBeGreaterThan(0)
		expect(mid).toBeLessThan(1)
		settle(w.pres)
		expect(groupAlpha(w, "/S/Fader")).toBeCloseTo(1)
	end)

	it("a SCALE change travels", function()
		local w = world({ scale = 1 })
		w.pres.withAnimation("container", function()
			w.scale:set(2)
		end)
		expect(paintedScale(w, "/S/Fader")).toBeCloseTo(1)
		for _ = 1, 6 do
			w.pres.tick(FRAME)
		end
		local mid = paintedScale(w, "/S/Fader")
		expect(mid).toBeGreaterThan(1)
		expect(mid).toBeLessThan(2)
		settle(w.pres)
		expect(paintedScale(w, "/S/Fader")).toBeCloseTo(2)
	end)

	it("a ROTATION change travels", function()
		local w = world({ rotation = 0 })
		w.pres.withAnimation("container", function()
			w.rotation:set(90)
		end)
		expect(paintedRotation(w, "/S/Fader")).toBeCloseTo(0)
		for _ = 1, 6 do
			w.pres.tick(FRAME)
		end
		local mid = paintedRotation(w, "/S/Fader")
		expect(mid).toBeGreaterThan(0)
		expect(mid).toBeLessThan(90)
		settle(w.pres)
		expect(paintedRotation(w, "/S/Fader")).toBeCloseTo(90)
	end)

	it("ONE SPRING: a fade and a move started in the same call are at the same FRACTION every frame", function()
		local w = world({ opacity = 1 })
		local startMove = w.adapter.node("/S/Plain").presentedPosition.y
		w.pres.withAnimation("container", function()
			-- the Fader grows (which displaces Plain below it) AND fades
			w.tall:set(true)
			w.opacity:set(0)
		end)
		local endMove = w.adapter.node("/S/Plain").rect.y
		expect(endMove).never().toBe(startMove)
		local sampled = 0
		for _ = 1, 40 do
			w.pres.tick(FRAME)
			local alphaFrac = groupAlpha(w, "/S/Fader") -- 0 -> 1 transparency
			local moved = w.adapter.node("/S/Plain").presentedPosition.y
			local moveFrac = (moved - startMove) / (endMove - startMove)
			-- SAME progress, not merely "both finished": three independent springs
			-- would drift apart here and no end-state assertion would notice
			expect(math.abs(alphaFrac - moveFrac)).toBeLessThan(1e-6)
			if alphaFrac > 0.05 and alphaFrac < 0.95 then
				sampled += 1
			end
		end
		-- ...and the comparison was made while both were genuinely mid-flight
		expect(sampled).toBeGreaterThan(3)
	end)

	it("the record is RELEASED on settle — an animated fade leaks nothing", function()
		local w = world({ opacity = 1 })
		w.pres.withAnimation("container", function()
			w.opacity:set(0.2)
		end)
		expect(w.pres.animationRecordCount()).toBeGreaterThan(0)
		settle(w.pres)
		expect(w.pres.animationRecordCount()).toBe(0)
		expect(groupAlpha(w, "/S/Fader")).toBeCloseTo(0.8)
	end)

	it("REDUCED MOTION deletes the flight and never the destination", function()
		local w = world({ reducedMotion = true, opacity = 1, scale = 1, rotation = 0 })
		w.pres.withAnimation("container", function()
			w.opacity:set(0.25)
			w.scale:set(1.5)
			w.rotation:set(45)
		end)
		-- instantly at the destination, with no record installed at all
		expect(w.pres.animationRecordCount()).toBe(0)
		expect(groupAlpha(w, "/S/Fader")).toBeCloseTo(0.75)
		expect(paintedScale(w, "/S/Fader")).toBeCloseTo(1.5)
		expect(paintedRotation(w, "/S/Fader")).toBeCloseTo(45)
	end)

	it("an UNARMED change lands instantly: only an armed commit installs a record", function()
		local w = world({ opacity = 1 })
		w.opacity:set(0.5)
		w.pres.refresh()
		expect(w.pres.animationRecordCount()).toBe(0)
		expect(groupAlpha(w, "/S/Fader")).toBeCloseTo(0.5)
	end)
end)

describe("authored presentation D — off-path cost, and one write site", function()
	it("a surface authoring NONE of the three writes no presentation property at all", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local UI = LuauUI.UI
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.VStack({ id = "L", children = { UI.Text({ text = "a" }), UI.Text({ text = "b" }) } }),
			},
		}))
		pres.refresh()
		local wrote = false
		for _, op in adapter.takeOps() do
			if string.find(op, ".transform=", 1, true) or string.find(op, ".transparency=", 1, true) then
				wrote = true
			end
		end
		expect(wrote).toBe(false)
	end)

	it("ONE SITE writes each presentation engine property — the manifest's promise, in the source", function()
		local source = require("@lune/fs").readFile("src/render/renderer.luau")
		local transform, transparency = 0, 0
		for line in string.gmatch(source, "[^\n]+") do
			if string.find(line, "adapter.setProp(", 1, true) then
				if string.find(line, '"transform"', 1, true) then
					transform += 1
				end
				if string.find(line, '"transparency"', 1, true) then
					transparency += 1
				end
			end
		end
		expect(transform).toBe(1)
		expect(transparency).toBe(1)
	end)
end)

--[[ ── E. THE PRESS DIP AND THE AUTHORED SCALE ────────────────────────────────

	ADR-0026 shipped with this booked rather than fixed: the engine honours ONE
	`UIScale` per object, so an authored `scale` and a `Button`'s press dip write
	the same instance, and the dip's recovery tweened to an ABSOLUTE `1`. The
	first release of a scaled Button therefore destroyed the authored value
	permanently — the renderer's write is memoized on the composed value, which
	had not changed, so nothing re-asserted it. It was recorded rather than fixed
	because `src/client/screen_paint.luau` was an uncommitted in-flight extraction
	owned by another agent; that landed in `38e47e2`, and this is the fix.

	IT IS PINNED AS SOURCE TEXT AND THAT IS SAID OUT LOUD. Neither
	`screen_paint.luau` nor `screen_target.luau` can load under Lune — they reach
	engine globals at load time — so this whole family of pins reads them as text
	through `tests/lib/adapter_source.luau`. What that CAN prove is exactly what
	this defect was: an absolute literal where a variable belonged. What it cannot
	prove is that a tween runs, which is the device round's job.
]]
describe("authored presentation E — an authored scale survives a press", function()
	local adapter_source = require("./lib/adapter_source")
	local fs = require("@lune/fs")

	it("NO press-dip target in screen_paint is an absolute 1 — every one derives from the resting scale", function()
		local paint = fs.readFile("src/client/screen_paint.luau")
		local offenders: { string } = {}
		local line = 0
		for text in string.gmatch(paint, "[^\n]*") do
			line += 1
			-- code only: the file's own header quotes "all 25 UIScale objects sat
			-- at Scale = 1.0", and a comment is not a write
			if string.match(text, "^%s*%-%-") ~= nil then
				continue
			end
			if string.find(text, "Scale = 1 }", 1, true) ~= nil or string.match(text, "%.Scale = 1%s*$") ~= nil then
				table.insert(offenders, `{line}: {text}`)
			end
		end
		expect(table.concat(offenders, "\n")).toBe("")
	end)

	it("...and all FOUR sites read it through one named helper, not four literals", function()
		local paint = fs.readFile("src/client/screen_paint.luau")
		local _, defs = string.gsub(paint, "local function restingScale%(", "")
		expect(defs).toBe(1)
		-- two dips (native + bespoke) and two recoveries (native + bespoke): four
		-- call sites, which is the whole population of press-dip Scale targets
		local _, calls = string.gsub(paint, "restingScale%(handle%)", "")
		expect(calls).toBe(4)
		-- the dip is RELATIVE: resting x pressedScale, never pressedScale alone
		local _, dips = string.gsub(paint, "restingScale%(handle%) %* style%.extra%.pressedScale", "")
		expect(dips).toBe(2)
		local _, bare = string.gsub(paint, "{ Scale = style%.extra%.pressedScale }", "")
		expect(bare).toBe(0)
	end)

	it("the presentation authority RECORDS the resting scale at the moment it writes it", function()
		local source = adapter_source.live()
		local from = string.find(source, "local function applyPresentationPaint(handle: any, t: any)", 1, true)
		expect(from ~= nil).toBe(true)
		local body = string.sub(source, from :: number, (from :: number) + 1200)
		-- recorded from the COMPOSED value the renderer sent, and cleared rather
		-- than pinned to 1 when nothing is scaling
		expect(
			string.find(body, "handle.restingScale = if scale ~= nil and scale ~= 1 then scale else nil", 1, true)
				~= nil
		).toBe(true)
		-- exactly one writer of the field, and it is this authority
		local _, writes = string.gsub(source, "handle%.restingScale =", "")
		expect(writes).toBe(1)
	end)
end)
