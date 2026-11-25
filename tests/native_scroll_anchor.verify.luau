--!strict
local Verify = require("@verify/src/core")
local Bdd = require("@verify/src/bdd")
local VerifyRoblox = require("@verify/src/roblox")
local Facet = require("../src")

return function(verifyHarness: Verify.Harness)
	local test = Bdd.create(verifyHarness)
	local describe, it, expect = test.describe, test.it, test.expect
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	local engineLib = require("./lib/native_engine")

	local function build(): (any, any, () -> ())
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = (engine.new("GuiService") :: unknown) :: GuiService
		engine.environment.fakeOn(VerifyRoblox.assertInstance(gui), "GetGuiInset", function()
			return engine.types.Vector2.zero, engine.types.Vector2.zero
		end)
		local UI = Facet.controls(runtime, { types = engine.types, guiService = gui, services = { GuiService = gui } })
		local Host = Facet.host(runtime)
		local root: any
		local unmount = runtime.mount(function()
			root = UI.ScrollView "Page" {
				Host.Frame "Log" {},
				Host.Frame "Rows" {},
			}
			return root
		end, engine.new("ScreenGui"))
		return root, engine, function()
			unmount()
			runtime:dispose()
		end
	end

	describe("ScrollView", function()
		it("keeps the content in view still when content above it changes height", {
			id = "native_scroll_anchor::ScrollView::keeps the content in view still when content above it changes height",
			run = function()
				local frame, engine, stop = build()
				local V2 = engine.types.Vector2
				local poke = engine.environment.poke
				local origin = frame:FindFirstChild("LayoutUnitContainer"):FindFirstChild("LayoutUnit")
				local log, rows = frame:FindFirstChild("Log"), frame:FindFirstChild("Rows")
				poke(origin, "AbsoluteSize", V2.new(100, 1))
				poke(frame, "AbsolutePosition", V2.new(0, 0))
				poke(frame, "AbsoluteWindowSize", V2.new(400, 300))
				poke(frame, "AbsoluteCanvasSize", V2.new(400, 1000))
				local function place(scroll: number, logHeight: number)
					poke(origin, "AbsolutePosition", V2.new(0, -scroll))
					poke(log, "AbsoluteSize", V2.new(400, logHeight))
					poke(log, "AbsolutePosition", V2.new(0, -scroll))
					poke(rows, "AbsoluteSize", V2.new(400, 800))
					poke(rows, "AbsolutePosition", V2.new(0, logHeight - scroll))
				end
				place(300, 100)
				frame.CanvasPosition = V2.new(0, 300)
				expect(frame.CanvasPosition):toBe(V2.new(0, 300))

				poke(log, "AbsoluteSize", V2.new(400, 120))
				poke(rows, "AbsolutePosition", V2.new(0, -180))
				poke(frame, "AbsoluteCanvasSize", V2.new(400, 1020))
				expect(frame.CanvasPosition):toBe(V2.new(0, 320))

				place(320, 120)
				poke(log, "AbsoluteSize", V2.new(400, 110))
				poke(rows, "AbsolutePosition", V2.new(0, -210))
				expect(frame.CanvasPosition):toBe(V2.new(0, 310))

				place(310, 110)
				frame.CanvasPosition = V2.new(0, 0)
				place(0, 110)
				place(0, 140)
				poke(frame, "AbsoluteCanvasSize", V2.new(400, 1040))
				expect(frame.CanvasPosition):toBe(V2.new(0, 0))
				stop()
			end,
		})
	end)
end
