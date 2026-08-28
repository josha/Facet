--!strict
-- UI-PARADIGM-003 + affordance matrix D.1/D.3/D.4: the console 10-foot
-- PRESENTATION consumers. When distanceProfile == "ten-foot" (displaySize ==
-- "Large") the presentation must (D.1) scale rendered text by the type-scale
-- floor at BOTH the layout-measure and paint seams, (D.3) cap layout density,
-- and (D.4) strengthen the focus state. A near display stays byte-identical
-- (the pre-existing tests are the regression guard). D.2 (overscan margins) is
-- already shipped (preview.spec) and is not re-proven here.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local fake_target = require("../tests/lib/fake_target")
local adaptive = require("../src/layout/adaptive")

local function attach(displaySize: string?, childrenFn: (any) -> { any })
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 720 })
	if displaySize then
		env:set("displaySize", displaySize)
	end
	local root = mountLib.mount(core, UI.Screen({ id = "S", children = childrenFn(core) }))
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {})
	controller.initialRender()
	return core, env, root, adapter, controller
end

describe("environment ten-foot derivations (matrix D.1/D.3)", function()
	it("typographyScale composes the ten-foot 1.5x multiplier over the preference", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("preferredTextSize", 2)
		expect(env:get("typographyScale"):get()).toBe(2) -- Medium: accessibility preference only
		env:set("displaySize", "Large")
		expect(env:get("typographyScale"):get()).toBe(3) -- 2 * 1.5 ten-foot floor
		env:set("preferredTextSize", 1)
		expect(env:get("typographyScale"):get()).toBe(1.5)
		env:set("displaySize", "Medium")
		expect(env:get("typographyScale"):get()).toBe(1) -- restores to preference only
	end)

	it("sizeClass caps at regular on a ten-foot Large display even on a wide viewport", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 1920, h = 1080 })
		expect(env:get("sizeClass"):get()).toBe("wide")
		env:set("displaySize", "Large")
		expect(env:get("sizeClass"):get()).toBe("regular") -- density floor: never the densest at 3m
		env:set("displaySize", "Medium")
		expect(env:get("sizeClass"):get()).toBe("wide")
	end)
end)

describe("UI-PARADIGM-003: ten-foot text scaling at the paint seam (matrix D.1)", function()
	it("a near display leaves rendered text sizes unscaled (typographyScale 1)", function()
		local _, _, _, adapter = attach("Medium", function()
			return { UI.Text({ id = "T", text = "Race", textSize = 16 }) }
		end)
		expect(adapter.node("/S/T").props.textSize).toBe(16)
	end)

	it("a ten-foot display scales rendered text sizes by 1.5x", function()
		local _, _, _, adapter = attach("Large", function()
			return { UI.Text({ id = "T", text = "Race", textSize = 16 }) }
		end)
		expect(adapter.node("/S/T").props.textSize).toBe(24) -- 16 * 1.5
	end)

	it("layout re-solves and rendered text grows when displaySize flips to Large", function()
		local _, env, _, adapter = attach("Medium", function()
			return { UI.Text({ id = "T", text = "Race", textSize = 16 }) }
		end)
		local before = adapter.node("/S/T").rect
		expect(adapter.node("/S/T").props.textSize).toBe(16)
		env:set("displaySize", "Large")
		-- paint seam updates AND layout re-solves the taller box
		expect(adapter.node("/S/T").props.textSize).toBe(24)
		expect(adapter.node("/S/T").rect.h > before.h).toBe(true)
	end)
end)

--[[ ADAPT-7 — THE FLOOR HAS TO REACH THE TEXT NOBODY SIZED.

	Every case above declares `textSize = 16`, which is the one branch that
	worked: the paint seam scaled an AUTHORED size and left an intrinsic one at
	its near-distance px, and the measure seam agreed with it. Measure and paint
	agreeing is exactly why nothing overflowed and nothing showed — the audit's
	own framing (`artifacts/release-candidate-review/adapt-audit/matrix.md`,
	ADAPT-7, critical) — and a spec family that only ever asserts an authored
	size cannot see it. So the instrument is fixed WITH the behaviour: the cases
	below declare no size at all, which is how the guide, the tutorials and every
	shipped screen write text.

	The ladder is the class's own intrinsic typography role
	(`snapshot.INTRINSIC_TEXT_ROLE`: Text/Toggle -> body, Button/TextField ->
	control) — the same role the measure seam already resolved the FACE from — so
	no new vocabulary and no per-class table: the floor applies to a role, and an
	unauthored node wears one. ]]
describe("ADAPT-7: the ten-foot type floor reaches UNAUTHORED text (matrix D.1)", function()
	it("an unsized Text rides the body role: 16 near, 24 at ten-foot", function()
		local _, _, _, near = attach("Medium", function()
			return { UI.Text({ id = "T", text = "Race" }) }
		end)
		expect(near.node("/S/T").props.textSize).toBe(16)
		local _, _, _, far = attach("Large", function()
			return { UI.Text({ id = "T", text = "Race" }) }
		end)
		expect(far.node("/S/T").props.textSize).toBe(24) -- 16 * 1.5, the same floor
	end)

	it("an unsized Button label rides the control role, and a Toggle the body role", function()
		local _, _, _, near = attach("Medium", function(core)
			return {
				UI.Button({ id = "B", label = "Play" }),
				UI.Toggle({ id = "G", label = "Music", value = core:signal(false) }),
			}
		end)
		local _, _, _, far = attach("Large", function(core)
			return {
				UI.Button({ id = "B", label = "Play" }),
				UI.Toggle({ id = "G", label = "Music", value = core:signal(false) }),
			}
		end)
		expect(far.node("/S/B").props.textSize).toBe(near.node("/S/B").props.textSize * 1.5)
		expect(far.node("/S/G").props.textSize).toBe(near.node("/S/G").props.textSize * 1.5)
	end)

	--[[ THE PROPERTY THAT MUST SURVIVE THE FIX. The asymmetry was silent because
		the two seams agreed; scaling paint alone would make a button label draw
		27px inside a box reserved for 18. So the box grows too, and it grows on
		the SAME flip. ]]
	it("measure agrees: the unsized box grows on the flip, exactly as the sized one does", function()
		local _, env, _, adapter = attach("Medium", function()
			return { UI.Text({ id = "T", text = "Race" }) }
		end)
		local before = adapter.node("/S/T").rect
		env:set("displaySize", "Large")
		expect(adapter.node("/S/T").props.textSize).toBe(24)
		expect(adapter.node("/S/T").rect.h > before.h).toBe(true)
	end)

	it("a near display is byte-identical: the floor is a ten-foot rung, not a rescale", function()
		local _, _, _, adapter = attach("Medium", function()
			return { UI.Text({ id = "T", text = "Race" }) }
		end)
		expect(adapter.node("/S/T").props.textSize).toBe(16)
	end)
end)

describe("UI-PARADIGM-003: ten-foot focus strengthening (matrix D.4)", function()
	it("focus visuals differ between a Large display and a Medium display", function()
		local _, _, _, adapterBig, ctlBig = attach("Large", function()
			return { UI.Button({ id = "B", label = "Go" }) }
		end)
		ctlBig.setFocusPath("/S/B")
		local _, _, _, adapterNear, ctlNear = attach("Medium", function()
			return { UI.Button({ id = "B", label = "Go" }) }
		end)
		ctlNear.setFocusPath("/S/B")
		expect(adapterBig.node("/S/B").focusProfile).toBe("ten-foot")
		expect(adapterNear.node("/S/B").focusProfile).toBe("near")
		expect(adapterBig.node("/S/B").focusProfile ~= adapterNear.node("/S/B").focusProfile).toBe(true)
	end)

	it("a near display keeps the focus profile at near (2px-ring semantics unchanged)", function()
		local _, _, _, adapter, ctl = attach("Medium", function()
			return { UI.Button({ id = "B", label = "Go" }) }
		end)
		ctl.setFocusPath("/S/B")
		expect(adapter.node("/S/B").focused).toBe(true)
		expect(adapter.node("/S/B").focusProfile).toBe("near")
	end)
end)

-- =============================================================================
-- Verifier findings (architecture review, 2026-07-21)
-- =============================================================================
describe("verifier F1: Toggle honors an explicit textSize at the MEASURE seam", function()
	it("a Toggle with an explicit textSize measures taller than the 16pt default (measure/paint agree)", function()
		local _, _, _, adapter = attach(nil, function(core)
			return {
				UI.Toggle({ id = "Small", label = "Music", value = core:signal(false) }),
				UI.Toggle({ id = "Big", label = "Music", value = core:signal(false), textSize = 32 }),
			}
		end)
		local small = adapter.node("/S/Small").rect
		local big = adapter.node("/S/Big").rect
		-- pre-fix both measured at a hardcoded 16 -> identical heights; the
		-- explicit 32 must reserve a taller box AND paint at 32 (scale 1)
		expect(big.h > small.h).toBe(true)
		expect(adapter.node("/S/Big").props.textSize).toBe(32)
	end)
end)

describe("verifier F2: a displaySize flip re-strengthens the RESTING focus visual", function()
	it("focus already on a control adopts the ten-foot profile when the display docks to Large", function()
		local _, env, _, adapter, controller = attach(nil, function(core)
			return { UI.Button({ id = "Go", label = "Go" }) }
		end)
		controller.setFocusPath("/S/Go")
		expect(adapter.node("/S/Go").focusProfile).toBe("near")
		env:set("displaySize", "Large") -- handheld docks to the TV; focus does not move
		expect(adapter.node("/S/Go").focusProfile).toBe("ten-foot")
		env:set("displaySize", "Medium")
		expect(adapter.node("/S/Go").focusProfile).toBe("near")
	end)
end)

-- =============================================================================
-- Director live find (Xbox One emulator, 2026-07-21): the ten-foot focus LIFT
-- scaled a full-width filter field past the screen edge (1888 x 1.05 = 1982 >
-- 1920). The lift is a CARD idiom — it must apply only when the lifted bounds
-- still fit the screen; oversized surfaces keep the strong ring with no scale.
-- Engine truth from the same session: the Xbox One device emulator DOES report
-- ViewportDisplaySize.Large, so the ten-foot profile is live in emulation.
-- =============================================================================
describe("ten-foot focus lift is capped to bounds that fit the screen (director live find)", function()
	it("a small control lifts; a full-width control keeps the strong ring with NO lift", function()
		local _, _, _, adapter, controller = attach("Large", function(core)
			return {
				UI.Button({
					id = "Small",
					label = "Go",
					width = { type = "fixed", px = 120 },
					height = { type = "fixed", px = 44 },
				}),
				UI.Button({
					id = "Wide",
					label = "Filter",
					width = { type = "fill", weight = 1 },
					height = { type = "fixed", px = 44 },
				}),
			}
		end)
		controller.setFocusPath("/S/Small")
		expect(adapter.node("/S/Small").focusProfile).toBe("ten-foot")
		expect(adapter.node("/S/Small").focusLift).toBe(true)
		controller.setFocusPath("/S/Wide")
		expect(adapter.node("/S/Wide").focusProfile).toBe("ten-foot")
		expect(adapter.node("/S/Wide").focusLift).toBe(false) -- lifted bounds would overflow
	end)

	it("a near display never lifts regardless of size", function()
		local _, _, _, adapter, controller = attach(nil, function(core)
			return {
				UI.Button({
					id = "Small",
					label = "Go",
					width = { type = "fixed", px = 120 },
					height = { type = "fixed", px = 44 },
				}),
			}
		end)
		controller.setFocusPath("/S/Small")
		expect(adapter.node("/S/Small").focusLift ~= true).toBe(true)
	end)
end)

describe("ten-foot default overscan margins (director live find: edge-flush UI on a TV-class display)", function()
	it("effectiveOverscanInsets defaults to the ten-foot 60/90 under Large when none are authored", function()
		local core = customFactory.new()
		local env = environment.new(core)
		expect(env:get("effectiveOverscanInsets"):get().left).toBe(0) -- near: no margins
		env:set("displaySize", "Large")
		local insets = env:get("effectiveOverscanInsets"):get()
		expect(insets.top).toBe(60)
		expect(insets.bottom).toBe(60)
		expect(insets.left).toBe(90)
		expect(insets.right).toBe(90)
		-- authored values win
		env:set("overscanInsets", { top = 10, bottom = 10, left = 20, right = 20 })
		expect(env:get("effectiveOverscanInsets"):get().left).toBe(20)
		-- explicit opt-out
		env:set("overscanInsets", "none")
		expect(env:get("effectiveOverscanInsets"):get().left).toBe(0)
	end)

	it("an unauthored Large display insets the solved tree by the default margins", function()
		local _, env, _, adapter = attach(nil, function(core)
			return {
				UI.VStack({
					id = "Panel",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {},
				}),
			}
		end)
		expect(adapter.node("/S/Panel").rect.x).toBe(0)
		env:set("displaySize", "Large")
		local rect = adapter.node("/S/Panel").rect
		expect(rect.x).toBe(90)
		expect(rect.w).toBe(1280 - 180)
	end)
end)

--[[ ADAPT-10 · THE TELEVISION GOT THE DENSEST ROW THE FRAMEWORK SHIPS.

	THE AUDIT'S MEASUREMENT (matrix ADAPT-10, high): `table.luau` asked
	`if classes.touch then "touch" else "pointer"`, and a gamepad is neither — so
	the ten-foot combo resolved `paradigm = pointer` and got the 36px row, at three
	metres. `snapshot.luau` published exactly two rungs, `pointer` and `touch`, so
	there was nothing else for the selection to reach even if it had looked.

	IT BIT DURING THE ADAPT-FIX WAVE, on a shipped surface: making unauthored text
	1.5x on a Large display put a 41px button inside Cartwheel's 36px brews-table
	row, five pixels of overflow on all twenty-four visible rows at 1920x1080, and
	the example had to absorb it with an authored `textSize`. That authored size is
	deleted in the same commit as this rung.

	THE AXIS IS DISTANCE, NOT THE PAD. A controller in your hands sixty centimetres
	from a monitor is a NEAR session and gets the near ladder; what makes a row
	unreadable is three metres, and `metrics.density` ("ten-foot" iff the display
	class is Large) is the framework's one fact for it — the same fact ADAPT-23's
	grid-lane cap already selects on. So the rung is `tenFoot` and a gamepad class
	is not consulted at all, which is the honest reading of the defect the audit
	measured rather than the one its title suggests. ]]
describe("ADAPT-10: the table row box has a ten-foot rung, and distance selects it", function()
	local snapshot = require("../src/themes/snapshot")

	it("the snapshot publishes THREE rungs, and the ten-foot floor is the largest", function()
		local metrics = snapshot.neutral()
		local family = (metrics.controls :: any).table
		expect(type(family.rowHeight.pointer)).toBe("number")
		expect(type(family.rowHeight.touch)).toBe("number")
		expect(type(family.rowHeight.tenFoot)).toBe("number")
		expect(family.rowHeight.tenFoot > family.rowHeight.pointer).toBe(true)
		expect(family.rowHeight.tenFoot >= family.rowHeight.touch).toBe(true)
		-- ...and the line count is the paradigm constant beside it, so the rung is
		-- a description of a row rather than a pixel somebody liked
		expect(type(family.rowLines.tenFoot)).toBe("number")
	end)

	it("a table on a Large display gets a TALLER row than the same table near", function()
		local Facet = require("../src") :: any
		local function rowHeight(displaySize: string?): number
			local core = Facet.newCore()
			local env = Facet.newEnvironment(core)
			env:set("viewportRect", { x = 0, y = 0, w = 1920, h = 1080 })
			if displaySize ~= nil then
				env:set("displaySize", displaySize)
			end
			local system = Facet.newActionSystem(core)
			local adapter = fake_target.new()
			local pres = Facet.newPresenter(core, env, adapter, system)
			local tbl = Facet.Controls.Table(core, {
				id = "T",
				rows = core:signal({ { id = "a", name = "Aria" } }),
				key = function(item: any)
					return item.id
				end,
				columns = {
					{
						id = "name",
						width = { type = "fill", weight = 1 },
						value = function(item: any)
							return item.name
						end,
					},
				},
				selection = "single",
				env = env,
			})
			pres.present(UI.Screen({ id = "S", children = { tbl.blueprint } }))
			pres.refresh()
			local row = adapter.node("/S/T/Main/Body/Rows/[a@0]/Row")
			expect(`row solved: {row ~= nil}`).toBe("row solved: true")
			return row.rect.h
		end
		local near = rowHeight("Medium")
		local tenFoot = rowHeight("Large")
		expect(tenFoot > near).toBe(true)
		-- the number the audit measured is the one that must not come back
		expect(near).toBe(36)
		expect(tenFoot > 36).toBe(true)
	end)

	it("a 41px control fits inside a ten-foot row — the defect that measured it", function()
		--[[ Cartwheel's brews table reported 5px of overflow on all 24 visible rows
			at 1920x1080 once unauthored text became 1.5x: a 41px button inside a 36px
			row. The row is what was wrong, so the row is what this asserts — against
			the same button height, at the same display class. ]]
		local metrics = snapshot.neutral()
		local family = (metrics.controls :: any).table
		expect(family.rowHeight.tenFoot >= 41).toBe(true)
	end)
end)

--[[ DIRECTOR ITEM 5 (ADR-0058): PHYSICAL-SIZE-AWARE TEN-FOOT CLASSING.

	The director's report: a ROG Ally (a Windows PC handheld) reads fonts too
	small, suspected classed as console/ten-foot BY INPUT rather than by
	screen size. Measured directly (ADR-0058 quotes the Studio session in
	full): the engine's own `GuiService.ViewportDisplaySize` is not reliable
	enough alone — an ordinary windowed desktop viewport, measured live in
	Studio Play, reported "Large", the SAME bucket a real console reports.

	The fix reads `effectiveDisplaySize` everywhere ten-foot TREATMENT is
	decided (see `adaptive.effectiveDisplaySize`'s header): "Large" only earns
	ten-foot when touch capability is NOT ALSO live, because a real ten-foot
	session — a console on a TV, from a couch — never has a touchscreen, and a
	PC handheld small enough to misreport "Large" has one on every shipping
	example.

	EVERY CASE BELOW IS A REGRESSION PIN OR AN EXTENSION, NEVER A WEAKENING:
	the PS5-shaped case pins a genuine console UNCHANGED, and every case above
	this block already exercises `displaySize = "Small"`/`"Medium"` untouched
	(the correction only ever fires on "Large" + touch), so the whole
	phone/tablet/desktop ladder those pin is provably unaffected by
	construction — touch is never checked unless the raw fact is already
	"Large". ]]
describe("director item 5: a ROG-Ally-shaped device does NOT get console/ten-foot treatment", function()
	local function envFor(displaySize: string, touch: boolean, gamepad: boolean): (any, any)
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 1920, h = 1080 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		env:set("displaySize", displaySize)
		env:set("capabilities", { touch = touch, gamepad = gamepad, keyboard = false, mouse = false })
		env:set("preferredInput", if gamepad then "Gamepad" else "KeyboardAndMouse")
		return core, env
	end

	-- THE ROG-ALLY-SHAPED CASE (the brief's own shape): 1920x1080, gamepad
	-- preferred, touch enabled, and — the worst case this round's platform
	-- research could not rule out on a PC handheld — the engine itself
	-- reporting "Large".
	it(
		"1920x1080 + gamepad + touch + engine-reported Large reads NEAR, with handheld-appropriate (1x) type scale",
		function()
			local _, env = envFor("Large", true, true)
			expect(env:get("effectiveDisplaySize"):get()).toBe("Medium")
			expect(env:get("distanceProfile"):get()).toBe("near")
			expect(env:get("typographyScale"):get()).toBe(1) -- NOT 1.5 — the director's own ask
			expect(env:get("typographyPaintScale"):get()).toBe(1)
			expect(env:get("themeMetrics"):get().metricScale).toBe(1) -- the whole ladder, not just type
			expect(env:get("effectiveOverscanInsets"):get()).toEqual({ top = 0, bottom = 0, left = 0, right = 0 })
			-- the WIDTH-only breakpoint is untouched by this fix — it is a
			-- separate axis (raw viewport pixels), deliberately out of this
			-- round's scope; see the ADR's own scoping note
			expect(env:get("sizeClass"):get()).toBe("wide")
		end
	)

	-- THE PS5-SHAPED REGRESSION PIN: same viewport, same gamepad, same
	-- engine-reported "Large" — but NO touchscreen, because a real console
	-- does not have one. This must stay byte-identical to today.
	it("a PS5-shaped device (1920x1080, gamepad, NO touch) stays ten-foot — unchanged", function()
		local _, env = envFor("Large", false, true)
		expect(env:get("effectiveDisplaySize"):get()).toBe("Large")
		expect(env:get("distanceProfile"):get()).toBe("ten-foot")
		expect(env:get("typographyScale"):get()).toBe(1.5)
		expect(env:get("themeMetrics"):get().metricScale).toBe(1.5)
		expect(env:get("effectiveOverscanInsets"):get()).toEqual({ top = 60, bottom = 60, left = 90, right = 90 })
		expect(env:get("sizeClass"):get()).toBe("regular") -- the pre-existing density cap
	end)

	-- THE DIRECTOR'S OWN SUSPICION, DIRECTLY DISPROVED: gamepad input alone
	-- never changes the classing — only touch does. A keyboard+mouse session
	-- at the same engine-reported "Large" is classed identically to a
	-- gamepad one; the input class was never the variable.
	it("gamepad input alone never changes the classing (the director's suspicion, measured false)", function()
		local _, gamepadSession = envFor("Large", false, true)
		local _, keyboardSession = envFor("Large", false, false)
		expect(gamepadSession:get("distanceProfile"):get()).toBe(keyboardSession:get("distanceProfile"):get())
		expect(gamepadSession:get("distanceProfile"):get()).toBe("ten-foot")
	end)

	-- A DEVICE THE ENGINE HONESTLY REPORTS AS SMALL (the happy path a real
	-- handheld likely already gets, per Roblox's own documented "Small = most
	-- tablet/mobile/handheld devices") is untouched either way — nothing here
	-- depends on the correction firing.
	it("an honestly-reported Small handheld is untouched by the correction", function()
		local _, env = envFor("Small", true, true)
		expect(env:get("effectiveDisplaySize"):get()).toBe("Small")
		expect(env:get("distanceProfile"):get()).toBe("near")
	end)

	-- ITEM 5.4'S OWN NAMED EXAMPLE, AUDITED: "what Large means for a
	-- gamepad+small-screen device" reaches `adaptive.navPlacement` through
	-- `adaptive.conditions` (what a real screen binds). Checked, not altered:
	-- the gamepad branch's own "Medium or Large -> topBar" rule (a SEPARATE,
	-- more specific tablet-vs-phone placement question this round does not
	-- touch) means the Large-to-Medium correction does not cross the
	-- boundary that would flip its outcome — recorded honestly rather than
	-- claimed as a fix, and booked as a possible follow-up in the ADR.
	it("navPlacement's gamepad branch is unchanged by this fix (audited, not altered)", function()
		local coreAlly, envAlly = envFor("Large", true, true)
		local corePs5, envPs5 = envFor("Large", false, true)
		expect(adaptive.conditions(coreAlly, envAlly).navPlacement:get()).toBe("topBar")
		expect(adaptive.conditions(corePs5, envPs5).navPlacement:get()).toBe("topBar")
	end)
end)
