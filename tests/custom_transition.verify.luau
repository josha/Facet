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
	for _, variant in { "default", "crossfade", "zoom" } do
		h:case(`a {variant} push yields focus that another surface claims before the page arrives`, function()
			local path = Facet.Compose.cell({} :: { Facet.NavigationEntry<string> })
			local w = worlds.new(function(UI: Facet.Controls)
				return UI.VStack {
					UI.Button "Start" { label = "Start" } :: Instance,
					UI.Button "Hud" { label = "Hud" } :: Instance,
					UI.NavigationStack {
						path = path,
						chrome = "hidden",
						transition = if variant == "zoom"
							then { scale = 0.5 }
							elseif variant == "crossfade" then { seconds = 0.3 }
							else nil,
						root = {
							content = function(): Instance
								return UI.Button "HomeAction" { label = "Home" }
							end,
						},
						destinations = {
							match = {
								content = function(): Instance
									return UI.Button "MatchAction" { label = "Match" }
								end,
							},
						},
					},
				}
			end)
			w.gui.SelectedObject = w.find("Start")
			path:set({ { id = "match", value = "one" } })
			w.gui.SelectedObject = w.find("Hud")
			for _ = 1, 60 do
				w.engine.heartbeat:Fire(1 / 60)
			end
			local selected = w.gui.SelectedObject
			Verify.expect(if selected then selected.Name else "nil"):toBe("Hud")
			w.stop()
		end)
	end
	local function zoomOf(node: Instance): UIScale?
		local found = node:FindFirstChild("TransitionScale", true)
		return if found and found:IsA("UIScale") then found else nil
	end
	local function near(value: number, expected: number): boolean
		return math.abs(value - expected) < 0.001
	end
	local function textStable(page: Instance): boolean
		local texts = 0
		for _, node in page:GetDescendants() do
			if node:IsA("TextLabel") or node:IsA("TextButton") then
				texts += 1
				local at: Instance? = node
				while at and at ~= page.Parent do
					if at:FindFirstChildWhichIsA("UIScale") then
						return false
					end
					at = at.Parent
				end
			end
		end
		return texts > 0
	end
	local function stackWorld(transition: Facet.Transition, opaque: boolean, theme: Facet.ThemePackage?)
		local path = Facet.Compose.cell({} :: { Facet.NavigationEntry<string> })
		local w = worlds.new(function(UI: Facet.Controls, Host, engine)
			return Host.Frame {
				Name = "Backdrop",
				BackgroundTransparency = if opaque then 0 else 1,
				BackgroundColor3 = engine.types.Color3.new(0.2, 0.3, 0.4),
				Size = engine.types.UDim2.fromScale(1, 1),
				UI.NavigationStack {
					path = path,
					chrome = "hidden",
					transition = transition,
					root = {
						content = function(): Instance
							return UI.Button "HomeAction" { label = "Home" }
						end,
					},
					destinations = {
						details = {
							content = function(): Instance
								return UI.Button "DetailAction" { label = "Detail" }
							end,
						},
					},
				},
			}
		end, if theme then { theme = theme } else nil)
		return w, path
	end
	h:case("a zoom scales only the page backdrop plate while the content fades at full size", function()
		local w, path = stackWorld({
			scale = 0.5,
			seconds = 0.4,
			ease = function(t: number): number
				return t
			end,
		}, true)
		path:set({ { id = "details", value = "item" } })
		local detail = w.find("DetailAction")
		local page = assert(detail:FindFirstAncestor("details"))
		local plate = assert(page:FindFirstChild("TransitionPlate", true)) :: Frame
		local scale = assert(zoomOf(page))
		Verify.expect(scale.Parent):toBe(plate)
		Verify.expect(near(plate.BackgroundColor3.R, 0.2) and near(plate.BackgroundColor3.B, 0.4)):toBe(true)
		Verify.expect(plate.BackgroundTransparency):toBe(0)
		Verify.expect(plate.AnchorPoint.X + plate.AnchorPoint.Y):toBe(1)
		Verify.expect(textStable(page)):toBe(true)
		Verify.expect(scale.Scale):toBe(0.5)
		w.engine.heartbeat:Fire(0.2)
		Verify.expect(near(scale.Scale, 0.75)):toBe(true)
		Verify.expect(near(fade.of(page), 0.5)):toBe(true)
		Verify.expect(textStable(page)):toBe(true)
		Verify.expect(page.Interactable):toBe(false)
		w.engine.heartbeat:Fire(0.3)
		Verify.expect(zoomOf(page)):toBe(nil)
		Verify.expect(page:FindFirstChild("TransitionPlate", true)):toBe(nil)
		Verify.expect(fade.groups(page)):toBe(0)
		Verify.expect(fade.of(page)):toBe(0)
		Verify.expect(page.Interactable):toBe(true)
		path:set({})
		w.engine.heartbeat:Fire(0.2)
		Verify.expect(w.find("DetailAction")):toBe(detail)
		local leaving = assert(zoomOf(page))
		Verify.expect(near(leaving.Scale, 0.75)):toBe(true)
		Verify.expect(near(fade.of(page), 0.5)):toBe(true)
		Verify.expect(textStable(page)):toBe(true)
		w.engine.heartbeat:Fire(0.3)
		Verify.expect(w.find("DetailAction")):toBe(nil)
		Verify.expect(zoomOf(w.screen)):toBe(nil)
		Verify.expect(fade.groups(w.screen)):toBe(0)
		w.stop()
	end)
	h:case("a zoom without an opaque backdrop is a pure fade", function()
		local w, path = stackWorld({ scale = 0.5, seconds = 0.4 }, false)
		path:set({ { id = "details", value = "item" } })
		local page = w.find("DetailAction"):FindFirstAncestor("details")
		w.engine.heartbeat:Fire(0.2)
		Verify.expect(zoomOf(w.screen)):toBe(nil)
		Verify.expect(w.screen:FindFirstChild("TransitionPlate", true)):toBe(nil)
		Verify.expect(fade.of(page) > 0 and fade.of(page) < 1):toBe(true)
		w.engine.heartbeat:Fire(0.3)
		Verify.expect(fade.of(page)):toBe(0)
		Verify.expect(fade.groups(w.screen)):toBe(0)
		w.stop()
	end)
	h:case("the default zoom takes its plate range, duration and fade-led curves from theme tokens", function()
		local package = assert(Facet.themes.define({
			metrics = {
				motion = {
					durations = { zoomPresent = 0.5 },
					easing = { zoomFade = "linear", zoomScale = "inQuad" },
					materialize = { zoom = 0.8 },
				},
			},
		}))
		local w, path = stackWorld({ scale = true }, true, package)
		path:set({ { id = "details", value = "item" } })
		local page = w.find("DetailAction"):FindFirstAncestor("details")
		local scale = assert(zoomOf(page))
		Verify.expect(near(scale.Scale, 0.8)):toBe(true)
		w.engine.heartbeat:Fire(0.25)
		Verify.expect(near(fade.of(page), 0.5)):toBe(true)
		Verify.expect(near(scale.Scale, 0.85)):toBe(true)
		Verify.expect(textStable(page)):toBe(true)
		w.engine.heartbeat:Fire(0.2)
		Verify.expect(zoomOf(page) ~= nil):toBe(true)
		w.engine.heartbeat:Fire(0.05)
		Verify.expect(zoomOf(page)):toBe(nil)
		Verify.expect(fade.of(page)):toBe(0)
		w.stop()
	end)
	h:case("the neutral zoom leads with opacity and keeps a small scale range", function()
		local motionTokens = assert(Facet.themes.neutralPackage().metrics.motion)
		local ease = Facet.Compose.easing
		local fadeEase = ease[assert(assert(motionTokens.easing).zoomFade)]
		local scaleEase = ease[assert(assert(motionTokens.easing).zoomScale)]
		local from = assert(assert(motionTokens.materialize).zoom)
		local seconds = assert(assert(motionTokens.durations).zoomPresent)
		Verify.expect(from >= 0.85 and from < 1):toBe(true)
		Verify.expect(seconds > 0.22):toBe(true)
		for frame = 1, math.ceil(seconds * 30) do
			local t = math.min(1, frame / 30 / seconds)
			local previous = math.max(0, (frame - 1) / 30 / seconds)
			Verify.expect(fadeEase(t) >= scaleEase(t)):toBe(true)
			Verify.expect((1 - from) * (scaleEase(t) - scaleEase(previous)) < 0.03):toBe(true)
		end
	end)
	h:case("a compact split view zooms only the incoming pane plate while the outgoing pane fades in place", function()
		local column = Facet.Compose.cell("sidebar" :: "sidebar" | "detail")
		local shown = Facet.Compose.cell(true)
		local w = worlds.new(function(UI: Facet.Controls, Host, engine)
			return Host.Frame {
				Name = "Backdrop",
				BackgroundTransparency = 0,
				Size = engine.types.UDim2.fromScale(1, 1),
				UI.NavigationSplitView {
					preferredCompactColumn = column,
					detailVisible = shown,
					detailLabel = false,
					transition = { scale = 0.5 },
					sidebar = function(): Instance
						return UI.Button "File" { label = "File" }
					end,
					detail = function(): Instance
						return UI.Button "Inspector" { label = "Inspector" }
					end,
				},
			}
		end)
		local split = w.find("NavigationSplitView")
		w.engine.environment.poke(split, "AbsoluteSize", w.engine.types.Vector2.new(400, 600))
		local sidebar, detail = w.find("Sidebar"), w.find("Detail")
		local inspector = w.find("Inspector")
		local function scaleOf(pane: Instance): number
			local found = zoomOf(pane)
			return if found then found.Scale else 1
		end
		Verify.expect(sidebar.Visible and zoomOf(sidebar) == nil):toBe(true)
		Verify.expect(detail.Visible):toBe(false)
		column:set("detail")
		Verify.expect(detail.Visible):toBe(true)
		Verify.expect(scaleOf(detail)):toBe(0.5)
		for _ = 1, 5 do
			w.engine.heartbeat:Fire(0.03)
			Verify.expect(scaleOf(sidebar)):toBe(1)
			Verify.expect(textStable(detail)):toBe(true)
			Verify.expect(textStable(sidebar)):toBe(true)
		end
		Verify.expect(scaleOf(detail) > 0.5 and scaleOf(detail) < 1):toBe(true)
		Verify.expect(sidebar.Visible and fade.of(sidebar) > 0):toBe(true)
		w.engine.heartbeat:Fire(0.2)
		Verify.expect(zoomOf(detail)):toBe(nil)
		Verify.expect(fade.groups(detail)):toBe(0)
		Verify.expect(sidebar.Visible):toBe(false)
		shown:set(false)
		for _ = 1, 5 do
			w.engine.heartbeat:Fire(0.03)
			Verify.expect(scaleOf(detail)):toBe(1)
			Verify.expect(textStable(detail)):toBe(true)
			Verify.expect(textStable(sidebar)):toBe(true)
		end
		Verify.expect(w.find("Inspector")):toBe(inspector)
		Verify.expect(scaleOf(sidebar) > 0.5 and scaleOf(sidebar) < 1):toBe(true)
		Verify.expect(sidebar.Visible):toBe(true)
		w.engine.heartbeat:Fire(0.2)
		Verify.expect(w.find("Inspector")):toBe(nil)
		Verify.expect(zoomOf(split)):toBe(nil)
		Verify.expect(fade.groups(split)):toBe(0)
		w.stop()
	end)
	h:case("a split view without a transition changes its compact column at once", function()
		local column = Facet.Compose.cell("sidebar" :: "sidebar" | "detail")
		local w = worlds.new(function(UI: Facet.Controls)
			return UI.NavigationSplitView {
				preferredCompactColumn = column,
				detailLabel = false,
				sidebar = function(): Instance
					return UI.Button "File" { label = "File" }
				end,
				detail = function(): Instance
					return UI.Button "Inspector" { label = "Inspector" }
				end,
			}
		end)
		w.engine.environment.poke(w.find("NavigationSplitView"), "AbsoluteSize", w.engine.types.Vector2.new(400, 600))
		column:set("detail")
		Verify.expect(w.find("Detail").Visible):toBe(true)
		Verify.expect(w.find("Sidebar").Visible):toBe(false)
		Verify.expect(w.find("Detail"):IsA("CanvasGroup")):toBe(false)
		Verify.expect(w.find("TransitionScale")):toBe(nil)
		w.stop()
	end)
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
		w.engine.environment.poke(w.gui, "ReducedMotionEnabled", true)
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
		w.engine.environment.poke(w.find("Modal"), "AbsoluteSize", w.engine.types.Vector2.new(800, 720))
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
