--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Facet = require("../src")
local worlds = require("./lib/content_world")
local fade = require("./lib/fade")
local transitions = require("../src/ui/transition")
local context = require("../src/ui/context")
local pageLayers = require("../src/ui/nav_page_layers")
local engines = require("./lib/native_engine")

return function(h: Verify.Harness)
	h:case("a departing custom page waits for the destination's native preparation", function()
		local C = Facet.Compose
		local engine = engines.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local ctx = context(C, runtime, { types = engine.types, motionLevel = "normal" })
		local ready = C.cell(true)
		local state = C.cell({ index = 1, depthFromTop = 0, top = true, covered = false })
		local phase: Facet.TransitionContext? = nil
		local stop = runtime.mount(function()
			return pageLayers(ctx).layer({}, state, {
				seconds = 0.4,
				ease = function(t: number): number
					return t
				end,
				apply = function(_node: GuiObject, value: Facet.TransitionContext)
					phase = value
				end,
			}, nil, true, nil, ready)
		end, engine.new("Folder"))
		ready:set(false)
		state:set({ index = 1, depthFromTop = 1, top = false, covered = true })
		engine.heartbeat:Fire(0.5)
		Verify.expect(assert(phase).isPresented:peek()):toBe(false)
		Verify.expect(assert(phase).progress:peek()):toBe(1)
		ready:set(true)
		engine.heartbeat:Fire(0.2)
		Verify.expect(math.abs(assert(phase).progress:peek() - 0.5) < 0.001):toBe(true)
		stop()
		runtime:dispose()
	end)
	h:case("interactive progress follows the pointer, holds endpoints and settles without a jump", function()
		local C = Facet.Compose
		local engine = engines.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local ctx = context(C, runtime, { types = engine.types, motionLevel = "normal" })
		local held = C.cell(nil :: number?)
		local presented = C.cell(true)
		local current: transitions.Motion? = nil
		local stop = runtime.mount(function()
			local moving = transitions.create(ctx, {
				seconds = 0.4,
				progress = held,
				ease = function(t: number): number
					return t
				end,
			}, presented, true)
			current = moving
			local node = ctx.Host.Frame {}
			moving.apply(node)
			return node
		end, engine.new("Folder"))
		local moving = assert(current)
		held:set(0.3)
		Verify.expect(moving.progress:peek()):toBe(0.3)
		engine.heartbeat:Fire(2)
		Verify.expect(moving.progress:peek()):toBe(0.3)
		held:set(0.7)
		Verify.expect(moving.progress:peek()):toBe(0.7)
		held:set(nil)
		Verify.expect(moving.progress:peek()):toBe(0.7)
		engine.heartbeat:Fire(0.2)
		Verify.expect(math.abs(moving.progress:peek() - 0.85) < 0.001):toBe(true)
		engine.heartbeat:Fire(0.3)
		Verify.expect(moving.progress:peek()):toBe(1)
		runtime:batch(function()
			held:set(0)
			presented:set(false)
		end)
		Verify.expect(moving.progress:peek()):toBe(1)
		held:set(1)
		Verify.expect(moving.progress:peek()):toBe(0)
		Verify.expect(moving.completed:peek()):toBe(false)
		runtime:batch(function()
			presented:set(true)
			held:set(nil)
		end)
		Verify.expect(moving.progress:peek()):toBe(0)
		engine.heartbeat:Fire(0.5)
		Verify.expect(moving.progress:peek()):toBe(1)
		stop()
		runtime:dispose()
	end)
	h:case("custom transforms stay at rest during hidden native preparation", function()
		local C = Facet.Compose
		local engine = engines.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local ctx = context(C, runtime, { types = engine.types, motionLevel = "normal" })
		local ready = C.cell(false)
		local current: transitions.Motion? = nil
		local stop = runtime.mount(function()
			local moving = transitions.create(ctx, { seconds = 0.4 }, C.cell(true), false, ready)
			current = moving
			local node = ctx.Host.Frame {}
			moving.apply(node)
			return node
		end, engine.new("Folder"))
		local moving = assert(current)
		engine.heartbeat:Fire(1)
		Verify.expect(moving.progress:peek()):toBe(1)
		Verify.expect(moving.opacity:peek()):toBe(0)
		ready:set(true)
		Verify.expect(moving.progress:peek()):toBe(0)
		engine.heartbeat:Fire(0.5)
		Verify.expect(moving.progress:peek()):toBe(1)
		stop()
		runtime:dispose()
	end)
	h:case("a custom navigation pop retains its page until progress reaches zero", function()
		local path = Facet.Compose.cell({} :: { Facet.NavigationEntry<string> })
		local calls = 0
		local w = worlds.new(function(UI: Facet.Controls)
			return UI.NavigationStack {
				path = path,
				transition = {
					seconds = 0.4,
					apply = function(_node: GuiObject, _phase: Facet.TransitionContext)
						calls += 1
					end,
				},
				root = {
					title = "Home",
					content = function(): Instance
						return UI.Button "HomeAction" { label = "Home" }
					end,
				},
				destinations = {
					details = {
						title = "Details",
						content = function(): Instance
							return UI.Button "DetailAction" { label = "Detail" }
						end,
					},
				},
			}
		end)
		path:set({ { id = "details", value = "item" } })
		w.engine.heartbeat:Fire(0.2)
		local detail = w.find("DetailAction")
		path:set({})
		Verify.expect(w.find("DetailAction")):toBe(detail)
		w.engine.heartbeat:Fire(0.5)
		Verify.expect(w.find("DetailAction")):toBe(nil)
		Verify.expect(w.find("HomeAction") ~= nil):toBe(true)
		Verify.expect(calls):toBe(2)
		w.stop()
	end)
	h:case("retargets custom tab motion on the same content and restores input at rest", function()
		local selection = Facet.Compose.cell("a")
		local held = Facet.Compose.cell(nil :: number?)
		local calls = 0
		local progress: { [GuiObject]: Facet.TransitionContext } = {}
		local w = worlds.new(function(UI: Facet.Controls)
			return UI.TabView {
				selection = selection,
				placement = "none",
				transition = {
					seconds = 0.4,
					fade = false,
					progress = held,
					ease = function(t: number): number
						return t
					end,
					apply = function(node: GuiObject, phase: Facet.TransitionContext)
						calls += 1
						progress[node] = phase
					end,
				},
				tabs = {
					{
						id = "a",
						content = function(): Instance
							return UI.Button "A" { label = "A" }
						end,
					},
					{
						id = "b",
						content = function(): Instance
							return UI.Button "B" { label = "B" }
						end,
					},
				},
			}
		end)
		local a = w.find("A")
		local wrapper = a.Parent :: GuiObject
		Verify.expect(assert(progress[wrapper]).progress:peek()):toBe(1)
		selection:set("b")
		local b = w.find("B")
		Verify.expect((b:FindFirstAncestor("b") :: GuiObject).Interactable):toBe(false)
		w.engine.heartbeat:Fire(0.1)
		Verify.expect(fade.of(b:FindFirstAncestor("b"))):toBe(0)
		Verify.expect((b:FindFirstAncestor("b") :: GuiObject).Interactable):toBe(false)
		local partial = progress[wrapper].progress:peek()
		Verify.expect(partial > 0 and partial < 1):toBe(true)
		selection:set("a")
		Verify.expect(w.find("A")):toBe(a)
		Verify.expect(progress[wrapper].progress:peek()):toBe(partial)
		w.engine.heartbeat:Fire(0.5)
		Verify.expect((a:FindFirstAncestor("a") :: GuiObject).Interactable):toBe(true)
		held:set(1)
		Verify.expect((a:FindFirstAncestor("a") :: GuiObject).Interactable):toBe(false)
		held:set(nil)
		Verify.expect((a:FindFirstAncestor("a") :: GuiObject).Interactable):toBe(true)
		Verify.expect(calls):toBe(2)
		w.stop()
	end)
	h:case("rests custom transforms under live reduced motion and removes a departed tab", function()
		local selection = Facet.Compose.cell("a")
		local phase: Facet.TransitionContext? = nil
		local w = worlds.new(function(UI: Facet.Controls)
			return UI.TabView {
				selection = selection,
				retention = "top",
				transition = {
					seconds = 0.3,
					fade = false,
					apply = function(_node: GuiObject, value: Facet.TransitionContext)
						phase = value
					end,
				},
				tabs = {
					{
						id = "a",
						content = function(): Instance
							return UI.Button "A" { label = "A" }
						end,
					},
					{
						id = "b",
						content = function(): Instance
							return UI.Button "B" { label = "B" }
						end,
					},
				},
			}
		end)
		selection:set("b")
		w.engine.heartbeat:Fire(0.05)
		w.gui.ReducedMotionEnabled = true
		Verify.expect(assert(phase).progress:peek()):toBe(1)
		local opacity = fade.of(w.find("B"):FindFirstAncestor("b"))
		Verify.expect(opacity > 0 and opacity < 1):toBe(true)
		w.engine.heartbeat:Fire(0.5)
		Verify.expect(w.find("A")):toBe(nil)
		Verify.expect(w.find("B") ~= nil):toBe(true)
		w.stop()
	end)
	h:case("retains a custom sheet until its own exit finishes and reverses a dismissed sheet", function()
		local shown = Facet.Compose.cell(true)
		local calls = 0
		local w = worlds.new(function(UI: Facet.Controls)
			return UI.Sheet {
				isPresented = shown,
				transition = {
					seconds = 0.8,
					fade = false,
					apply = function(_node: GuiObject, _phase: Facet.TransitionContext)
						calls += 1
					end,
				},
				content = function(): Instance
					return UI.Button "Kept" { label = "Kept" }
				end,
			}
		end)
		w.find("Modal").AbsoluteSize = w.engine.types.Vector2.new(800, 720)
		for _ = 1, 90 do
			w.engine.heartbeat:Fire(1 / 60)
		end
		local content = w.find("Kept")
		Verify.expect(fade.of(w.find("SheetTransition"))):toBe(0)
		shown:set(false)
		w.engine.heartbeat:Fire(0.3)
		Verify.expect(w.find("Kept")):toBe(content)
		Verify.expect(fade.of(w.find("SheetTransition"))):toBe(0)
		Verify.expect((w.find("SheetTransition") :: GuiObject).Interactable):toBe(false)
		shown:set(true)
		w.engine.heartbeat:Fire(0.9)
		Verify.expect(w.find("Kept")):toBe(content)
		Verify.expect(calls):toBe(1)
		shown:set(false)
		w.engine.heartbeat:Fire(0.9)
		Verify.expect(w.find("Kept")):toBe(nil)
		w.stop()
	end)
end
