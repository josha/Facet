--!strict
--[[ AUTHORED PRESENTATION — `opacity`, `scale`, `rotation` (ADR-0026).

	The director's ruling, 2026-08-14: *"should opacity, transparency, and scale
	get owned/influenced by facet? it seems like we should be able to animate
	those."*

	THE WHOLE DESIGN IN ONE SENTENCE, and every case below defends one clause of
	it: an authored value is an **input to the presentation authority**, never a
	second writer — the renderer composes (channel value x authored value) at ONE
	write site, and `withAnimation` adds a third term to that same composition.

	So the cases split four ways:

	  A. AUTHORING — the props exist, they are reactive, and the refusals are
	     loud (a leaf cannot fade; a scale of zero is not a small view).
	  B. COMPOSITION — the arithmetic the comparison document cites ([SW-141]): opacity and scale
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

local Facet = require("../src") :: any
local schema = require("../src/blueprint_schema") :: any
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
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	if options.reducedMotion then
		env:set("reducedMotion", true)
	end
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)

	local opacity = core:signal(options.opacity or 1)
	local scale = core:signal(options.scale or 1)
	local rotation = core:signal(options.rotation or 0)
	-- the GEOMETRIC half, so one call can move a node and fade another and the
	-- shared-spring case can compare their progress
	local tall = core:signal(false)
	local faderHeight = core:memo(function(use: any)
		return { type = "fixed", px = if use(tall) then 200 else 100 }
	end)

	local UI = Facet.UI
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
		local UI = Facet.UI
		local ok, err = pcall(function()
			return UI.Text({ text = "hi", opacity = 0.5 })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "opacity", 1, true) ~= nil).toBe(true)
	end)

	--[[ THE REFUSAL IS LEGIBLE (ADR-0029, director round 2026-08-15). ADR-0026
		refused the leaf and left the message to the generic unknown-property
		path: *"unknown property 'opacity'. Valid properties: …"* — which reads
		as an oversight in the schema, sends the author to a list that does not
		contain the answer, and never mentions the one-line spelling that works.
		A capability that is refused has to say so at the point of use. ]]
	it("THE DISABLED-DIMMING CASE: the refusal names the defeat it exists to prevent", function()
		local UI = Facet.UI
		local ok, err = pcall(function()
			return UI.Text({ text = "hi", opacity = 0.5 })
		end)
		expect(ok).toBe(false)
		local msg = tostring(err)
		-- it is REFUSED, not missing — the word that separates a decision from a gap
		expect(`refused:{string.find(msg, "REFUSED", 1, true) ~= nil}`).toBe("refused:true")
		-- ...and it names the measured consequence (probe L1/L4, 2026-08-15): the
		-- disabled dimming dies from the first faded frame
		expect(`dimming:{string.find(msg, "stop dimming when disabled", 1, true) ~= nil}`).toBe("dimming:true")
		-- ...and the fact underneath it: the sheet's value stops being READABLE,
		-- so the composition loses its base term rather than merely losing a race
		expect(`unreadable:{string.find(msg, "GetStyled", 1, true) ~= nil}`).toBe("unreadable:true")
	end)

	it("...and it names the WORKAROUND, spelled out, not a doc reference", function()
		local UI = Facet.UI
		local _, err = pcall(function()
			return UI.Text({ text = "hi", opacity = 0.5 })
		end)
		local msg = tostring(err)
		expect(`wrap:{string.find(msg, "UI.ZStack{ opacity = 0.4, children = ", 1, true) ~= nil}`).toBe("wrap:true")
	end)

	it("`canvasGroup` on a leaf is refused with the SAME message — one fact, both spellings", function()
		local UI = Facet.UI
		local _, err = pcall(function()
			return UI.Text({ text = "hi", canvasGroup = true })
		end)
		local msg = tostring(err)
		expect(`refused:{string.find(msg, "REFUSED", 1, true) ~= nil}`).toBe("refused:true")
		expect(`wrap:{string.find(msg, "UI.ZStack{ opacity = 0.4, children = ", 1, true) ~= nil}`).toBe("wrap:true")
	end)

	it("a genuinely unknown property is UNCHANGED — the refusal did not swallow the suggester", function()
		local UI = Facet.UI
		local _, err = pcall(function()
			return UI.Text({ text = "hi", opactiy = 0.5 })
		end)
		local msg = tostring(err)
		expect(`unknown:{string.find(msg, "unknown property 'opactiy'", 1, true) ~= nil}`).toBe("unknown:true")
		expect(`valid list:{string.find(msg, "Valid properties:", 1, true) ~= nil}`).toBe("valid list:true")
	end)

	--[[ THE ASYMMETRY, AS AN INVARIANT RATHER THAN A SPOT CHECK (ADR-0029).
		`scale` and `rotation` shipped on every rendered class and `opacity` on
		two, and until now nothing said why. One rule decides all three: a term is
		offerable on a class when ONE engine property that no style rule owns
		expresses it for that class's whole painted output. `UIScale.Scale` and
		`GuiObject.Rotation` are that property on every GuiObject; the only such
		property for alpha is `CanvasGroup.GroupTransparency`, and only a node whose
		engine instance can BE a CanvasGroup has one. ]]
	it("THE ASYMMETRY: `opacity` is on exactly two classes and every other one refuses it BY NAME", function()
		local offered: { string } = {}
		local refused = 0
		for _, className in schema.classNames() do
			local spec = schema.forClass(className)
			-- `scale` marks the classes that paint an engine instance — exactly the
			-- set where "why not opacity too?" is a real question
			if spec.props.scale == nil then
				continue
			end
			if spec.props.opacity ~= nil then
				table.insert(offered, className)
			else
				refused += 1
				expect(`{className} refuses by name:{schema.refusal(className, "opacity") ~= nil}`).toBe(
					`{className} refuses by name:true`
				)
			end
		end
		table.sort(offered)
		expect(table.concat(offered, ",")).toBe("Box,ZStack")
		expect(`refused count > 15:{refused > 15}`).toBe("refused count > 15:true")
		-- ...and the two that HAVE it refuse nothing: a class that offers the prop
		-- must never also claim to have declined it
		expect(`Box:{schema.refusal("Box", "opacity")}`).toBe("Box:nil")
		expect(`ZStack:{schema.refusal("ZStack", "opacity")}`).toBe("ZStack:nil")
		expect(`Box canvasGroup:{schema.refusal("Box", "canvasGroup")}`).toBe("Box canvasGroup:nil")
	end)

	--[[ A STRUCTURAL REGION IS NOT REFUSED A FADE — it has no engine instance to
		fade in the first place, so the fade message would be a wrong answer to a
		real question. `UI.When{ opacity = … }` stays a plain unknown property, and
		the honest fix there is to put the prop on the branch's own root. ]]
	it("a STRUCTURAL class is not given the fade refusal — it has no instance to fade", function()
		for _, className in { "When", "ForEach", "Region", "GridRow", "ErrorBoundary" } do
			expect(`{className}:{schema.refusal(className, "opacity")}`).toBe(`{className}:nil`)
			expect(`{className} cg:{schema.refusal(className, "canvasGroup")}`).toBe(`{className} cg:nil`)
		end
		local UI = Facet.UI
		local _, err = pcall(function()
			return UI.When({
				condition = true,
				opacity = 0.5,
				thenView = function()
					return UI.Text({ text = "x" })
				end,
			})
		end)
		expect(`plain unknown:{string.find(tostring(err), "unknown property 'opacity'", 1, true) ~= nil}`).toBe(
			"plain unknown:true"
		)
	end)

	it("...and `scale`/`rotation` are offered on EVERY rendered class and refused on none", function()
		local missing: { string } = {}
		for _, className in schema.classNames() do
			local spec = schema.forClass(className)
			if spec.props.scale == nil then
				continue
			end
			if spec.props.rotation == nil then
				table.insert(missing, className)
			end
			-- never refused: there is nothing to refuse, so the table must not name them
			expect(`{className}.scale refusal:{schema.refusal(className, "scale")}`).toBe(
				`{className}.scale refusal:nil`
			)
			expect(`{className}.rotation refusal:{schema.refusal(className, "rotation")}`).toBe(
				`{className}.rotation refusal:nil`
			)
		end
		expect(table.concat(missing, ",")).toBe("")
	end)

	it("`scale` and `rotation` ARE offered on a leaf — neither touches a sheet-owned property", function()
		local UI = Facet.UI
		expect(function()
				return UI.Text({ text = "hi", scale = 1.2, rotation = 8 })
			end)
			.never()
			.toThrow()
	end)

	--[[ THE WRAP THE REFUSAL NAMES, ACTUALLY WORKING. The refusal is only honest
		if the spelling it offers does the job, so this is the positive half: the
		wrap fades the group through the ONE property no rule owns, and writes
		NOTHING on the control inside it — which is what leaves the sheet's
		disabled dimming alive underneath. (That the sheet then still dims is an
		engine fact headless cannot see; it is measured live — probe W1, and
		artifacts/leaf-opacity/live-probes.md.) ]]
	it("the wrap fades the GROUP and writes nothing at all on the control inside it", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local UI = Facet.UI
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.ZStack({
					id = "Wrap",
					opacity = 0.4,
					children = { UI.Button({ id = "Btn", label = "Buy", enabled = false }) },
				}),
			},
		}))
		pres.refresh()
		-- the group carries the whole fade, in engine units
		local group = adapter.node("/S/Wrap")
		expect(group.canvasGroupInstance ~= nil).toBe(true)
		expect(group.canvasGroupInstance.groupTransparency).toBeCloseTo(0.6)
		-- ...and the control inside it was never told about any of it: no fade group
		-- of its own, and not one transparency write on its path. THAT is what keeps
		-- the sheet's `:NonInteractable` rule the only writer of its TextTransparency.
		expect(adapter.node("/S/Wrap/Btn").canvasGroupInstance).toBeNil()
		local childFades: { string } = {}
		for _, op in adapter.takeOps() do
			if string.find(op, "/S/Wrap/Btn", 1, true) and string.find(op, "transparency", 1, true) then
				table.insert(childFades, op)
			end
		end
		expect(table.concat(childFades, " | ")).toBe("")
	end)

	it("the authored domain is refused rather than clamped: opacity outside 0..1, scale <= 0", function()
		local UI = Facet.UI
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
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local UI = Facet.UI
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
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local UI = Facet.UI
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

	--[[ THE REFUSAL COSTS A VALID SURFACE NOTHING, and it is GATED rather than
		asserted (ADR-0026 Decision 9's shape, ADR-0029). There is no runtime path to
		measure here at all, and that is the claim: `schema.refusal` is reached from
		exactly one place, and that place — `unknownPropError` — only runs once a
		property is already absent from the class, i.e. on a construction that is
		about to throw. A valid `UI.Text{ text = … }` never enters it.

		Measured anyway, ABBA-interleaved (2026-08-15, 12 runs): with the branch,
		construct median 117.8 ms / mount median 79.0 ms; without it, 118.9 / 79.4 —
		the "with" arm is faster than the "without" arm by less than its own spread
		(construct 114.6-119.3, mount 77.6-83.1). A plain A-then-B ordering had
		reported mount +3.1% before the interleave erased it. ]]
	it("the refusal is on the ERROR PATH ONLY — one caller, and it is the failing constructor", function()
		local fs = require("@lune/fs")
		local bp = fs.readFile("src/blueprint.luau")
		local calls = 0
		for line in string.gmatch(bp .. "\n" .. fs.readFile("src/blueprint_schema.luau"), "[^\n]+") do
			-- `function schema.refusal(` is the DEFINITION, not a call
			if string.find(line, "schema.refusal(", 1, true) and not string.find(line, "function ", 1, true) then
				calls += 1
			end
		end
		expect(`callers of schema.refusal: {calls}`).toBe("callers of schema.refusal: 1")
		-- ...and that one caller is inside `unknownPropError`, which by construction
		-- only runs for a key the class does not have
		local from = string.find(bp, "local function unknownPropError(", 1, true)
		expect(from ~= nil).toBe(true)
		local body = string.sub(bp, from :: number, (from :: number) + 900)
		expect(`inside unknownPropError: {string.find(body, "schema.refusal(", 1, true) ~= nil}`).toBe(
			"inside unknownPropError: true"
		)
	end)

	it("ONE SITE writes each presentation engine property — the manifest's promise, in the source", function()
		-- the renderer as ONE text: three files since the 200k `Source` write-cap
		-- split, and the count is only a promise about the whole family. The write
		-- site lives in `render/presentation_channel.luau` now
		-- (tests/lib/renderer_source names the parts and says why).
		local source = require("./lib/renderer_source").all()
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
		local body = adapter_source.bodyOf(source, "local function applyPresentationPaint(handle: any, t: any)")
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
