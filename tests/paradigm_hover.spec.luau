--!strict
-- UI-PARADIGM-001 (affordance matrix R§7 "three feedback layers"): the pointer
-- HOVER layer. Interactive nodes gain a hover state on pointer, gated on the
-- LIVE pointer class (env interactionClasses.pointer) — a pure-touch device
-- allocates NO hover wiring, and nothing essential lives behind hover (it is a
-- free preview channel only). Headless proof through the FakeTarget's synthetic
-- hover seam (enableHover + hover/unhover), mirroring what ScreenTarget wires to
-- real MouseEnter/MouseLeave.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local fake_target = require("../tests/lib/fake_target")
local defaultStyle = require("../src/tokens/default_style")

local POINTER_CAPS = { keyboard = true, mouse = true, touch = false, gamepad = false }
local TOUCH_CAPS = { keyboard = false, mouse = false, touch = true, gamepad = false }

local function build(caps: any, preferredInput: string, childrenFn: (any) -> { any }, opts: any?)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("capabilities", caps)
	env:set("preferredInput", preferredInput)
	local root = mountLib.mount(core, UI.Screen({ id = "S", children = childrenFn(core) }))
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, opts or {})
	controller.initialRender()
	return core, env, root, adapter, controller
end

describe("UI-PARADIGM-001: pointer hover layer", function()
	it("the default style defines a hover role distinct from the control rest fill", function()
		expect(defaultStyle.extra.controlHover ~= nil).toBe(true)
		local rest, hover = defaultStyle.extra.control, defaultStyle.extra.controlHover
		expect(rest.r == hover.r and rest.g == hover.g and rest.b == hover.b).toBe(false)
	end)

	it("a pointer-live renderer enables hover on interactive nodes and synthetic hover flips their state", function()
		local _, _, _, adapter = build(POINTER_CAPS, "KeyboardAndMouse", function(core)
			return {
				UI.Button({ id = "Go", label = "Go" }),
				UI.Toggle({ id = "Flag", label = "Flag", value = core:signal(false) }),
			}
		end)
		expect(adapter.node("/S/Go").hoverEnabled).toBe(true)
		expect(adapter.node("/S/Flag").hoverEnabled).toBe(true)
		adapter.hover("/S/Go")
		expect(adapter.node("/S/Go").hovered).toBe(true)
		adapter.unhover("/S/Go")
		expect(adapter.node("/S/Go").hovered).toBe(false)
	end)

	it("a pure-touch device never allocates hover wiring, and nothing essential lives behind hover", function()
		local activated: { [string]: boolean } = {}
		local _, _, _, adapter = build(TOUCH_CAPS, "Touch", function()
			return { UI.Button({ id = "Go", label = "Go" }) }
		end, {
			onNodeTap = function(path: string)
				activated[path] = true
			end,
		})
		-- pointer class is NOT live -> no hover wiring allocated
		expect(adapter.node("/S/Go").hoverEnabled ~= true).toBe(true)
		adapter.hover("/S/Go")
		expect(adapter.node("/S/Go").hovered ~= true).toBe(true)
		-- activation still reaches the control: hover is a free preview, never a gate
		adapter.tap("/S/Go")
		expect(activated["/S/Go"]).toBe(true)
	end)

	it("non-interactive nodes never get hover wiring even on pointer", function()
		local _, _, _, adapter = build(POINTER_CAPS, "KeyboardAndMouse", function()
			return { UI.Text({ id = "Label", text = "hello", textSize = 16 }) }
		end)
		expect(adapter.node("/S/Label").hoverEnabled ~= true).toBe(true)
	end)
end)

-- =============================================================================
-- Verifier finding F3 (architecture review, 2026-07-21): hover is a hot-switch
-- CARRY idiom — a mouse ARRIVING mid-session must add hover to nodes that
-- already exist, not only to nodes created after the flip.
-- =============================================================================
describe("verifier F3: a pointer arriving mid-session enables hover on existing nodes", function()
	it("a pure-touch tree gains hover wiring on its mounted Buttons when a mouse joins", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		env:set("preferredInput", "Touch")
		env:set("capabilities", { keyboard = false, mouse = false, touch = true, gamepad = false })
		local root =
			mountLib.mount(core, UI.Screen({ id = "S", children = { UI.Button({ id = "Go", label = "Go" }) } }))
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, {})
		controller.initialRender()
		expect(adapter.node("/S/Go").hoverEnabled ~= true).toBe(true) -- touch: no hover wiring
		-- the handheld docks: a mouse joins mid-session
		env:set("capabilities", { keyboard = true, mouse = true, touch = true, gamepad = false })
		expect(adapter.node("/S/Go").hoverEnabled).toBe(true)
		local _ = controller
	end)
end)
