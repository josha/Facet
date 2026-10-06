--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local Vector3 = require("@lune/roblox").Vector3
	local Facet = require("../src")
	local engines = require("./lib/native_engine")
	local scrollLock = require("../src/ui/scroll_lock")
	type Runtime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)

	local function world()
		local engine = engines.new()
		local input = engine.new("UserInputService")
		local runtime: Runtime = Facet.Roblox.createRuntime(engine)
		local UI = Facet.controls(runtime, { types = engine.types, services = { UserInputService = input } })
		local screen = engine.new("ScreenGui")
		local playerGui = engine.new("PlayerGui")
		screen.Parent = playerGui
		local root: any
		local stop = runtime.mount(function()
			root = UI.ScrollView { Name = "Outer", UI.ScrollView { Name = "Middle", UI.ScrollView { Name = "Inner" } } }
			return root
		end, screen)
		local middle = root:FindFirstChild("Middle")
		local inner = middle:FindFirstChild("Inner")
		for _, frame in { root, middle, inner } do
			frame.AbsoluteWindowSize = engine.types.Vector2.new(100, 100)
			frame.AbsoluteCanvasSize = engine.types.Vector2.new(100, 300)
			frame.CanvasPosition = engine.types.Vector2.new(0, 100)
		end
		local tile = engine.new("TextButton")
		tile.Parent = inner
		playerGui.GetGuiObjectsAtPosition = function()
			return { tile, inner, middle, root }
		end
		local function begin()
			local touch: any = {
				UserInputType = engine.types.Enum.UserInputType.Touch,
				UserInputState = engine.types.Enum.UserInputState.Begin,
				Position = Vector3.new(50, 50, 0),
			}
			input.InputBegan.fire(touch)
			return touch
		end
		local function move(touch: any, x: number, y: number)
			touch.Position = Vector3.new(x, y, 0)
			touch.UserInputState = engine.types.Enum.UserInputState.Change
			input.InputChanged.fire(touch)
		end
		return {
			engine = engine,
			input = input,
			root = root,
			middle = middle,
			inner = inner,
			screen = screen,
			playerGui = playerGui,
			begin = begin,
			move = move,
			stop = stop,
		}
	end

	verifyHarness:suite("native nested scroll handoff", function()
		verifyHarness:case("keeps a moving inner pane, then yields at either edge until touch release", {
			id = "native_scroll_chain::native nested scroll handoff::keeps a moving inner pane, then yields at either edge until touch release",
			run = function()
				for _, bottom in { false, true } do
					local w = world()
					local touch = w.begin()
					local direction = if bottom then -1 else 1
					w.move(touch, 50, 50 + direction * 20)
					Verify.expect(w.inner.ScrollingEnabled):toBe(true)
					w.inner.CanvasPosition = w.engine.types.Vector2.new(0, if bottom then 200 else 0)
					w.move(touch, 50, 50 + direction * 40)
					Verify.expect(w.inner.ScrollingEnabled):toBe(false)
					Verify.expect(w.middle.ScrollingEnabled and w.root.ScrollingEnabled):toBe(true)
					w.input.InputEnded.fire(touch)
					Verify.expect(w.inner.ScrollingEnabled):toBe(true)
					w.stop()
				end
			end,
		})

		verifyHarness:case("passes an exhausted intermediate pane and respects the scroll axis", {
			id = "native_scroll_chain::native nested scroll handoff::passes an exhausted intermediate pane and respects the scroll axis",
			run = function()
				local w = world()
				w.root.ScrollingDirection = w.engine.types.Enum.ScrollingDirection.X
				w.root.AbsoluteCanvasSize = w.engine.types.Vector2.new(300, 100)
				w.root.CanvasPosition = w.engine.types.Vector2.new(100, 0)
				local touch = w.begin()
				w.move(touch, 20, 50)
				Verify.expect(w.inner.ScrollingEnabled or w.middle.ScrollingEnabled):toBe(false)
				Verify.expect(w.root.ScrollingEnabled):toBe(true)
				w.input.InputEnded.fire(touch)
				Verify.expect(w.inner.ScrollingEnabled and w.middle.ScrollingEnabled):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("keeps root elasticity when no ancestor can move and yields empty panes", {
			id = "native_scroll_chain::native nested scroll handoff::keeps root elasticity when no ancestor can move and yields empty panes",
			run = function()
				local w = world()
				for _, frame in { w.inner, w.middle, w.root } do
					frame.CanvasPosition = w.engine.types.Vector2.zero
				end
				w.inner.AbsoluteCanvasSize = w.inner.AbsoluteWindowSize
				local touch = w.begin()
				w.move(touch, 50, 80)
				Verify.expect(w.inner.ScrollingEnabled and w.middle.ScrollingEnabled):toBe(true)
				w.root.CanvasPosition = w.engine.types.Vector2.new(0, 100)
				w.move(touch, 50, 100)
				Verify.expect(w.inner.ScrollingEnabled or w.middle.ScrollingEnabled):toBe(false)
				w.input.InputEnded.fire(touch)
				w.stop()
			end,
		})

		verifyHarness:case("does not escape a disabled ancestor or release a concurrent modal lock", {
			id = "native_scroll_chain::native nested scroll handoff::does not escape a disabled ancestor or release a concurrent modal lock",
			run = function()
				local w = world()
				w.inner.CanvasPosition = w.engine.types.Vector2.zero
				w.middle.ScrollingEnabled = false
				local touch = w.begin()
				w.move(touch, 50, 80)
				Verify.expect(w.inner.ScrollingEnabled):toBe(true)
				w.middle.ScrollingEnabled = true
				w.move(touch, 50, 100)
				Verify.expect(w.inner.ScrollingEnabled):toBe(false)
				local modal = w.engine.new("Frame")
				modal.Parent = w.screen
				scrollLock.acquire(w.screen, modal)
				w.input.InputEnded.fire(touch)
				Verify.expect(w.inner.ScrollingEnabled or w.middle.ScrollingEnabled or w.root.ScrollingEnabled)
					:toBe(false)
				scrollLock.release(w.screen, modal)
				Verify.expect(w.inner.ScrollingEnabled and w.middle.ScrollingEnabled and w.root.ScrollingEnabled)
					:toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("does not scroll through an overlay or an unowned scrolling frame", {
			id = "native_scroll_chain::native nested scroll handoff::does not scroll through an overlay or an unowned scrolling frame",
			run = function()
				for _, className in { "TextButton", "ScrollingFrame" } do
					local w = world()
					w.inner.CanvasPosition = w.engine.types.Vector2.zero
					local blocker = w.engine.new(className)
					blocker.Parent = w.screen
					w.playerGui.GetGuiObjectsAtPosition = function()
						return { blocker, w.inner, w.middle, w.root }
					end
					local touch = w.begin()
					w.move(touch, 50, 80)
					Verify.expect(w.inner.ScrollingEnabled and w.middle.ScrollingEnabled):toBe(true)
					w.input.InputEnded.fire(touch)
					w.stop()
				end
			end,
		})

		verifyHarness:case("releases gesture connections on cancellation, focus loss and disposal", {
			id = "native_scroll_chain::native nested scroll handoff::releases gesture connections on cancellation, focus loss and disposal",
			run = function()
				for _, reason in { "cancel", "blur", "dispose" } do
					local w = world()
					w.inner.CanvasPosition = w.engine.types.Vector2.zero
					local baseline = w.input.InputChanged.count()
					local touch = w.begin()
					w.move(touch, 50, 80)
					Verify.expect(w.inner.ScrollingEnabled):toBe(false)
					if reason == "cancel" then
						touch.UserInputState = w.engine.types.Enum.UserInputState.Cancel
						w.input.InputChanged.fire(touch)
					elseif reason == "blur" then
						w.input.WindowFocusReleased.fire()
					else
						w.stop()
					end
					if reason ~= "dispose" then
						Verify.expect(w.inner.ScrollingEnabled):toBe(true)
						Verify.expect((w.input.InputChanged.count())):toBe(baseline)
						w.stop()
					end
					Verify.expect((w.input.InputChanged.count())):toBe(0)
					Verify.expect((w.input.InputBegan.count())):toBe(0)
				end
			end,
		})
	end)
end
