--!strict
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local world = require("./lib/world")
local Facet = require("../src") :: any
local UI = Facet.UI
local function fixture(opts: any?, transition: any?): any
	local w = world.new(opts)
	local path = w.core:signal({})
	local built
	local visits, releases = 0, 0
	local function content(scope: any, entry: any)
		visits += 1
		scope:own(function()
			releases += 1
		end)
		return UI.VStack({
			id = "Body",
			width = UI.fill(),
			children = {
				UI.Button({
					id = "Next",
					label = "Continue",
					onActivate = function()
						built.api.push({ id = "step", value = (if entry then entry.value or 0 else 0) + 1 })
					end,
				}),
				UI.Button({ id = "Other", label = "Other" }),
			},
		})
	end
	built = Facet.Controls.NavigationStack(w.core, {
		id = "Nav",
		path = path,
		root = { title = "Start", content = content },
		destinations = { step = { title = "Step", content = content } },
		backLabel = "Back",
		env = w.env,
		transition = transition,
	})
	w.path, w.nav = path, built
	w.counts = function()
		return visits, releases
	end
	w.present(UI.Screen({ id = "S", children = { built.blueprint } }))
	return w
end
local function find(w: any, suffix: string): string
	for _, path in w.adapter.paths() do
		if path:sub(-#suffix) == suffix then
			return path
		end
	end
	error("missing " .. suffix)
end
describe("NavigationStack state and lifetime", function()
	it("push, repeated routes, pop and root preserve caller-owned path and release every page", function()
		local w = fixture()
		expect(w.nav.dump().depth).toBe(0)
		w.nav.api.push({ id = "step", value = 1 })
		w.settle()
		local first = w.nav.dump().current.key
		w.nav.api.push({ id = "step", value = 2 })
		w.settle()
		expect(w.nav.dump().current.key ~= first).toBe(true)
		expect(#w.path:get()).toBe(2)
		w.nav.api.pop()
		w.settle()
		expect(w.nav.dump().current.key).toBe(first)
		w.nav.api.popToRoot()
		w.settle()
		expect(w.nav.api.back()).toBe(false)
		w.pres.dismiss(w.handle)
		w.nav.dispose()
		w.nav.dispose()
		local visits, releases = w.counts()
		expect(visits).toBe(releases)
	end)
	it("quarantines invalid external paths and recovers on the next valid write", function()
		local w = fixture()
		w.path:set({ { id = "missing" } })
		w.settle()
		expect(w.nav.dump().depth).toBe(0)
		expect(w.nav.dump().lastError ~= nil).toBe(true)
		w.path:set({ { id = "step", value = 3 } })
		w.settle()
		expect(w.nav.dump().depth).toBe(1)
		expect(w.nav.dump().quarantined).toBe(false)
		expect(w.nav.dump().lastError ~= nil).toBe(true)
	end)
	it("restores the previous page's legal focused path on pop", function()
		local w = fixture({ capabilities = { keyboard = true, mouse = true, touch = false, gamepad = false } })
		local old = find(w, "/Other")
		w.pres.focus.focusOn(old)
		w.nav.api.push({ id = "step" })
		w.settle()
		w.nav.api.pop()
		w.settle()
		expect(w.pres.focus.focused:get()).toBe(old)
	end)
end)

describe("NavigationStack public contract and input", function()
	it("rejects malformed initial specs paths and route entries without creating a page", function()
		local w = world.new()
		local function spec()
			return {
				path = w.core:signal({}),
				root = {
					content = function()
						return UI.Box({})
					end,
				},
				destinations = { step = {
					content = function()
						return UI.Box({})
					end,
				} },
				backLabel = "Back",
			}
		end
		for _, mutate in
			{
				function(s)
					s.unknown = true
				end,
				function(s)
					s.path = w.core:memo(function()
						return {}
					end)
				end,
				function(s)
					s.path:set({ [2] = { id = "step" } })
				end,
				function(s)
					s.path:set({ { id = "step", extra = true } })
				end,
				function(s)
					s.path:set({ { id = "missing" } })
				end,
				function(s)
					s.root.content = "invalid"
				end,
				function(s)
					s.root.title = 2
				end,
				function(s)
					s.root.extra = true
				end,
				function(s)
					s.destinations.step.content = nil
				end,
				function(s)
					s.backLabel = ""
				end,
				function(s)
					s.transition = { unknown = true }
				end,
			}
		do
			local s = spec()
			mutate(s)
			expect(function()
				Facet.Controls.NavigationStack(w.core, s)
			end).toThrow()
		end
	end)
	it("callback faults release partial content and keep Back available with a sticky error", function()
		local w = world.new()
		local released = 0
		local nav = Facet.Controls.NavigationStack(w.core, {
			path = w.core:signal({}),
			backLabel = "Back",
			root = {
				content = function()
					return UI.Button({ id = "Start", label = "Start" })
				end,
			},
			destinations = {
				bad = {
					title = "Failed step",
					content = function(scope)
						scope:own(function()
							released += 1
						end)
						error("test destination failure")
					end,
				},
			},
		})
		w.present(UI.Screen({ id = "S", children = { nav.blueprint } }))
		nav.api.push({ id = "bad" })
		w.settle()
		expect(nav.dump().quarantined).toBe(true)
		expect(nav.dump().lastError:find("test destination failure", 1, true) ~= nil).toBe(true)
		expect(released).toBe(1)
		w.adapter.tap(find(w, "/NavBar/Back"))
		w.settle()
		expect(nav.dump().depth).toBe(0)
		expect(nav.dump().quarantined).toBe(false)
		expect(nav.dump().lastError ~= nil).toBe(true)
		w.pres.dismiss(w.handle)
		nav.dispose()
		expect(released).toBe(1)
	end)
	it("pointer Back has hover and touch Back has a minimum target through the shared navBar", function()
		for _, input in { "pointer", "touch" } do
			local w = fixture({
				capabilities = {
					keyboard = input == "pointer",
					mouse = input == "pointer",
					touch = input == "touch",
					gamepad = false,
				},
				preferredInput = if input == "touch" then "Touch" else "KeyboardAndMouse",
			})
			local nextPath = find(w, "/Next")
			if input == "touch" then
				w.adapter.touchTap(nextPath)
			else
				w.adapter.tap(nextPath)
			end
			w.settle()
			expect(w.nav.dump().depth).toBe(1)
			local back = find(w, "/NavBar/Back")
			local node = w.adapter.node(back)
			if input == "touch" then
				local hit = w.adapter.hitRectOf(back) or node.rect
				expect(hit.w >= 44 and hit.h >= 44).toBe(true)
				w.adapter.touchTap(back)
			else
				w.adapter.hover(back)
				expect(node.hovered).toBe(true)
				w.adapter.tap(back)
			end
			w.settle()
			expect(w.nav.dump().depth).toBe(0)
			w.pres.dismiss(w.handle)
			w.nav.dispose()
		end
	end)
	it("keyboard and ten-foot gamepad use shared focus Activate and Back controls", function()
		for _, input in { "keyboard", "gamepad" } do
			local w = fixture({
				viewport = { x = 0, y = 0, w = 1280, h = 720 },
				displaySize = if input == "gamepad" then "Large" else "Medium",
				capabilities = {
					keyboard = input == "keyboard",
					mouse = false,
					touch = false,
					gamepad = input == "gamepad",
				},
				preferredInput = if input == "gamepad" then "Gamepad" else "KeyboardAndMouse",
			})
			local nextPath = find(w, "/Next")
			w.pres.focus.focusOn(nextPath)
			w.tick(0)
			expect(w.adapter.node(nextPath).focused).toBe(true)
			w.press(if input == "keyboard" then "Return" else "ButtonA")
			w.settle()
			expect(w.nav.dump().depth).toBe(1)
			local back = find(w, "/NavBar/Back")
			w.pres.focus.focusOn(back)
			w.tick(0)
			expect(w.adapter.node(back).focused).toBe(true)
			w.press(if input == "keyboard" then "Return" else "ButtonB")
			w.settle()
			expect(w.nav.dump().depth).toBe(0)
			w.pres.dismiss(w.handle)
			w.nav.dispose()
		end
	end)
	it("modal Cancel wins over the underlying stack and root Back remains unconsumed", function()
		local w = fixture({
			capabilities = { keyboard = false, mouse = false, touch = false, gamepad = true },
			preferredInput = "Gamepad",
		})
		w.nav.api.push({ id = "step" })
		w.settle()
		local modal =
			w.pres.presentModal(UI.Screen({ id = "Modal", children = { UI.Button({ id = "OK", label = "OK" }) } }))
		w.settle()
		expect(w.pres.focus.focused:get()).toBe("/Modal/OK")
		w.press("ButtonB")
		w.settle()
		expect(modal.context.destroyed).toBe(true)
		expect(w.nav.dump().depth).toBe(1)
		w.press("ButtonB")
		w.settle()
		expect(w.nav.dump().depth).toBe(0)
		expect(w.nav.api.back()).toBe(false)
	end)
	it("nested stack Cancel pops the focused child before its containing route", function()
		local w = world.new({
			capabilities = { keyboard = false, mouse = false, touch = false, gamepad = true },
			preferredInput = "Gamepad",
		})
		local inner
		local function button()
			return UI.Button({ id = "Go", label = "Go" })
		end
		local outer = Facet.Controls.NavigationStack(w.core, {
			id = "Outer",
			path = w.core:signal({ { id = "child" } }),
			backLabel = "Back",
			root = { content = button },
			destinations = {
				child = {
					content = function(scope)
						inner = Facet.Controls.NavigationStack(w.core, {
							id = "Inner",
							path = w.core:signal({ { id = "step" } }),
							backLabel = "Back",
							root = { content = button },
							destinations = { step = { content = button } },
						})
						scope:own(inner)
						return inner.blueprint
					end,
				},
			},
		})
		w.present(UI.Screen({ id = "S", children = { outer.blueprint } }))
		w.pres.focus.focusOn(find(w, "/Go"))
		w.press("ButtonB")
		w.settle()
		expect(inner.dump().depth).toBe(0)
		expect(outer.dump().depth).toBe(1)
		w.press("ButtonB")
		w.settle()
		expect(outer.dump().depth).toBe(0)
		expect(inner.dump().disposed).toBe(true)
		w.pres.dismiss(w.handle)
		outer.dispose()
	end)
	it("viewport theme input and reduced-motion switches retain the mounted current page", function()
		local w = fixture()
		w.nav.api.push({ id = "step", value = 8 })
		w.settle()
		local old = w.adapter.node(find(w, "/Next"))
		local visits = w.counts()
		local compactTitleHeight = w.adapter.node(find(w, "/NavBar/Title")).rect.h
		local snapshot = require("../src/themes/snapshot")
		for _, width in { 390, 834, 1280 } do
			w.env:set("viewportRect", { x = 0, y = 0, w = width, h = 844 })
			w.env:set("themeMetrics", snapshot.resolve(snapshot.neutralPackage(), nil, {}, { ["space.m"] = 20 }))
			w.env:set("preferredInput", "Gamepad")
			w.env:set("capabilities", { keyboard = true, mouse = true, touch = true, gamepad = true })
			w.env:set("reducedMotion", true)
			w.settle()
			expect(w.adapter.node(find(w, "/Next"))).toBe(old)
			expect(w.nav.dump().depth).toBe(1)
			expect(w.counts()).toBe(visits)
			if width == 1280 then
				expect(w.adapter.node(find(w, "/NavBar/Title")).rect.h > compactTitleHeight).toBe(true)
			end
		end
		w.pres.dismiss(w.handle)
		w.nav.dispose()
	end)
end)

describe("NavigationStack cleanup and accessibility", function()
	it("shared transitions retire pages and reduced motion settles without retaining work", function()
		for _, reduced in { false, true } do
			local w = fixture({ reducedMotion = reduced }, { enter = "fade", exit = "fade" })
			w.settle(60)
			w.nav.api.push({ id = "step" })
			expect(w.pres.motionClock:activeCount() > 0).toBe(not reduced)
			if not reduced then
				expect(w.nav.dump().livePages > 1).toBe(true)
			end
			w.settle(60)
			expect(w.nav.dump().livePages).toBe(1)
			local visits, releases = w.counts()
			expect(visits - releases).toBe(1)
			expect(w.pres.motionClock:activeCount()).toBe(0)
			w.nav.api.popToRoot()
			w.settle(60)
			expect(w.nav.dump().livePages).toBe(1)
			w.pres.dismiss(w.handle)
			w.nav.dispose()
			visits, releases = w.counts()
			expect(visits).toBe(releases)
			expect(w.pres.motionClock:activeCount()).toBe(0)
		end
	end)
	it(
		"remounting the same stack does not accumulate focus observers and disposal ignores later path writes",
		function()
			local w = fixture()
			local initial = w.core:counters().observers
			for _ = 1, 3 do
				w.pres.dismiss(w.handle)
				w.present(UI.Screen({ id = "S", children = { w.nav.blueprint } }))
				expect(w.core:counters().observers).toBe(initial)
			end
			w.pres.dismiss(w.handle)
			w.nav.dispose()
			local after = w.core:counters().observers
			w.path:set({ { id = "step" } })
			w.settle()
			expect(w.core:counters().observers).toBe(after)
			expect(w.nav.dump().depth).toBe(0)
			expect(w.nav.dump().livePages).toBe(0)
			expect(w.nav.api.push({ id = "step" })).toBe(false)
		end
	)
	it("a remembered target disabled while away falls back to the current legal focus order", function()
		local w = world.new({ capabilities = { keyboard = true, mouse = false, touch = false, gamepad = false } })
		local enabled = w.core:signal(true)
		local nav = Facet.Controls.NavigationStack(w.core, {
			path = w.core:signal({}),
			backLabel = "Back",
			root = {
				content = function()
					return UI.VStack({
						children = {
							UI.Button({ id = "First", label = "First" }),
							UI.Button({ id = "Remember", label = "Remember", enabled = enabled }),
						},
					})
				end,
			},
			destinations = {
				step = {
					content = function()
						return UI.Button({ id = "Step", label = "Step" })
					end,
				},
			},
		})
		w.present(UI.Screen({ id = "S", children = { nav.blueprint } }))
		w.pres.focus.focusOn(find(w, "/Remember"))
		nav.api.push({ id = "step" })
		w.settle()
		enabled:set(false)
		nav.api.pop()
		w.settle()
		expect(w.pres.focus.focused:get()).toBe(find(w, "/First"))
		w.pres.dismiss(w.handle)
		nav.dispose()
	end)
end)

describe("NavigationStack external route changes", function()
	it("pop restores remembered focus when surviving shell chrome held focus during the path write", function()
		local w = fixture()
		w.pres.dismiss(w.handle)
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					height = UI.fill(),
					children = {
						UI.Button({ id = "Chrome", label = "Shell action" }),
						w.nav.blueprint,
					},
				}),
			},
		}))
		local remembered = find(w, "/Other")
		w.pres.focus.focusOn(remembered)
		w.nav.api.push({ id = "step" })
		w.settle()
		w.pres.focus.focusOn(find(w, "/Chrome"))
		w.path:set({})
		w.settle(2)
		expect(w.pres.focus.focused:get()).toBe(remembered)
		w.pres.dismiss(w.handle)
		w.nav.dispose()
	end)
end)

describe("NavigationStack transactional path writes", function()
	it("multiple pushes and pops in one core transaction compose on the caller path", function()
		local w = fixture()
		w.core:transaction(function()
			w.nav.api.push({ id = "step", value = 1 })
			w.nav.api.push({ id = "step", value = 2 })
		end)
		w.settle()
		expect(w.nav.dump().depth).toBe(2)
		expect(w.path:get()[1].value).toBe(1)
		expect(w.path:get()[2].value).toBe(2)
		w.core:transaction(function()
			w.nav.api.pop()
			w.nav.api.pop()
		end)
		w.settle()
		expect(w.nav.dump().depth).toBe(0)
		w.core:transaction(function()
			w.nav.api.push({ id = "step", value = 1 })
			w.nav.api.popToRoot()
			w.nav.api.push({ id = "step", value = 3 })
		end)
		w.settle()
		expect(w.nav.dump().depth).toBe(1)
		expect(w.path:get()[1].value).toBe(3)
		w.pres.dismiss(w.handle)
		w.nav.dispose()
	end)
end)

describe("NavigationStack existing-shell root", function()
	it("an untitled root preserves the full shell box while destinations still receive Back chrome", function()
		local w = world.new()
		local function full()
			return UI.Box({ id = "FullShell", width = UI.fill(), height = UI.fill() })
		end
		local nav = Facet.Controls.NavigationStack(w.core, {
			path = w.core:signal({}),
			backLabel = "Back",
			root = { content = full },
			destinations = { step = { content = full } },
		})
		w.present(UI.Screen({ id = "S", children = { nav.blueprint } }))
		local root = w.adapter.node(find(w, "/FullShell"))
		expect(root.rect.w).toBe(390)
		expect(root.rect.h).toBe(844)
		for _, path in w.adapter.paths() do
			expect(path:find("/NavBar", 1, true) == nil).toBe(true)
		end
		nav.api.push({ id = "step" })
		w.settle()
		expect(w.adapter.node(find(w, "/NavBar/Back")) ~= nil).toBe(true)
		expect(w.adapter.node(find(w, "/FullShell")).rect.w < 390).toBe(true)
		w.pres.dismiss(w.handle)
		nav.dispose()
	end)
end)

describe("NavigationStack gamepad focus boundaries", function()
	it("DPad crosses sibling chrome Back and page controls without a trap or a delayed focus steal", function()
		local w = world.new({
			viewport = { x = 0, y = 0, w = 1280, h = 720 },
			capabilities = { gamepad = true, mouse = false, keyboard = false, touch = false },
			preferredInput = "Gamepad",
			displaySize = "Large",
			reducedMotion = true,
		})
		local nav
		local activations = 0
		local function body()
			return UI.VStack({
				id = "Body",
				gap = "m",
				children = {
					UI.Button({
						id = "Continue",
						label = "Continue",
						onActivate = function()
							activations += 1
							nav.api.push({ id = "step" })
						end,
					}),
					UI.Button({ id = "Last", label = "Last action" }),
				},
			})
		end
		nav = Facet.Controls.NavigationStack(w.core, {
			id = "Flow",
			path = w.core:signal({}),
			backLabel = "Back",
			env = w.env,
			root = { content = body },
			destinations = { step = { title = "Details", content = body } },
		})
		w.present(
			UI.Screen({
				id = "S",
				children = {
					UI.VStack({
						height = UI.fill(),
						gap = "m",
						children = {
							UI.Button({ id = "Before", label = "Before the flow" }),
							nav.blueprint,
							UI.Button({ id = "After", label = "After the flow" }),
						},
					}),
				},
			}),
			{ initialFocus = "Before" }
		)
		local function focused(suffix)
			local path = w.pres.focus.focused:get()
			expect(path:sub(-#suffix)).toBe(suffix)
		end
		local function press(key, suffix)
			w.press(key)
			w.settle(3)
			focused(suffix)
		end
		focused("/Before")
		press("DPadDown", "/Continue")
		press("DPadDown", "/Last")
		press("DPadDown", "/After")
		press("DPadUp", "/Last")
		press("DPadUp", "/Continue")
		press("ButtonA", "/NavBar/Back")
		expect(activations).toBe(1)
		expect(nav.dump().depth).toBe(1)
		press("DPadUp", "/Before")
		press("DPadDown", "/NavBar/Back")
		press("DPadDown", "/Continue")
		press("DPadDown", "/Last")
		press("DPadDown", "/After")
		press("DPadUp", "/Last")
		press("ButtonB", "/Continue")
		expect(nav.dump().depth).toBe(0)
		press("DPadUp", "/Before")
		w.pres.dismiss(w.handle)
		nav.dispose()
		expect(nav.dump().livePages).toBe(0)
		expect(w.core:lastError()).toBeNil()
	end)
end)

describe("NavigationStack interrupted transitions", function()
	it("rapid forward and back leaves one opaque current page and no retired input or scope", function()
		local w = fixture({ reducedMotion = false }, { enter = "fade", exit = "fade", class = "container" })
		w.settle(60)
		local launcher = find(w, "/Next")
		w.pres.focus.focusOn(launcher)
		for _ = 1, 4 do
			w.nav.api.push({ id = "step" })
			w.pres.refresh()
			w.tick(1 / 120)
			local body = w.adapter.node(find(w, "/Page"))
			-- Every destination paints a theme-owned backdrop, including its chrome.
			local currentKey = w.nav.dump().current.key
			for _, path in w.adapter.paths() do
				if path:find("[" .. currentKey .. "]", 1, true) and path:sub(-5) == "/Page" then
					body = w.adapter.node(path)
				end
			end
			expect(body.props.surface).toBe("base")
			w.nav.api.pop()
			w.pres.refresh()
			w.tick(1 / 120)
		end
		w.settle(120)
		expect(w.nav.dump().depth).toBe(0)
		expect(w.nav.dump().livePages).toBe(1)
		local visits, releases = w.counts()
		expect(visits - releases).toBe(1)
		expect(w.pres.focus.focused:get()).toBe(launcher)
		for _, entry in w.handle.focusOrder().traversal do
			expect(entry.path:find("[Page0]", 1, true) ~= nil).toBe(true)
		end
		expect(w.pres.motionClock:activeCount()).toBe(0)
		w.pres.dismiss(w.handle)
		w.nav.dispose()
		visits, releases = w.counts()
		expect(visits).toBe(releases)
	end)
end)

describe("NavigationStack page slide geometry", function()
	it("push and Back slide full pages through one clipped viewport without vertical reflow", function()
		local w = fixture({ reducedMotion = false }, { enter = "slide-left", exit = "slide-right" })
		w.settle(60)
		local root = "/S/Nav/Pages/[Page0]/PageMotion"
		local first = "/S/Nav/Pages/[Page1]/PageMotion"
		local box = w.adapter.node("/S/Nav").rect
		local function near(a, b)
			expect(math.abs(a - b) < 0.01).toBe(true)
		end
		local function sameBox(path)
			local rect = w.adapter.node(path).rect
			near(rect.x, box.x)
			near(rect.y, box.y)
			near(rect.w, box.w)
			near(rect.h, box.h)
		end
		w.nav.api.push({ id = "step" })
		w.pres.refresh()
		sameBox(root)
		sameBox(first)
		expect(w.adapter.node("/S/Nav").props.clipChildren).toBe(true)
		near(w.adapter.node(first).presentationOffset.x, box.w)
		for _ = 1, 6 do
			w.tick(1 / 120)
			sameBox(root)
			sameBox(first)
			local old = w.adapter.node(root).presentationOffset
			local incoming = w.adapter.node(first).presentationOffset
			expect(old.x < 0).toBe(true)
			expect(incoming.x > 0).toBe(true)
			near(incoming.x - old.x, box.w)
			near(old.y, 0)
			near(incoming.y, 0)
		end
		w.settle(60)
		w.nav.api.pop()
		w.pres.refresh()
		sameBox(root)
		sameBox(first)
		near(w.adapter.node(root).presentationOffset.x, -box.w)
		for _ = 1, 6 do
			w.tick(1 / 120)
			local outgoing = w.adapter.node(first).presentationOffset
			local revealed = w.adapter.node(root).presentationOffset
			expect(outgoing.x > 0).toBe(true)
			expect(revealed.x < 0).toBe(true)
			near(outgoing.x - revealed.x, box.w)
			sameBox(root)
			sameBox(first)
		end
		w.settle(60)
		expect(w.nav.dump().livePages).toBe(1)
		w.pres.dismiss(w.handle)
		w.nav.dispose()
	end)
end)

describe("NavigationStack slide interruption and containment", function()
	it("interrupting an entering page preserves its painted position and retires all extra pages", function()
		local w = fixture({ reducedMotion = false }, { enter = "slide-left", exit = "slide-right" })
		expect(w.pres.motionClock:activeCount()).toBe(0)
		w.nav.api.push({ id = "step", value = 1 })
		w.pres.refresh()
		w.tick(1 / 120)
		local first = "/S/Nav/Pages/[Page1]/PageMotion"
		local before = w.adapter.node(first).presentationOffset.x
		w.nav.api.push({ id = "step", value = 2 })
		w.pres.refresh()
		expect(math.abs(w.adapter.node(first).presentationOffset.x - before) < 0.01).toBe(true)
		w.tick(1 / 120)
		local second = "/S/Nav/Pages/[Page2]/PageMotion"
		before = w.adapter.node(second).presentationOffset.x
		w.nav.api.pop()
		w.pres.refresh()
		expect(math.abs(w.adapter.node(second).presentationOffset.x - before) < 0.01).toBe(true)
		w.nav.api.popToRoot()
		w.settle(120)
		expect(w.nav.dump().livePages).toBe(1)
		expect(w.pres.motionClock:activeCount()).toBe(0)
		w.pres.dismiss(w.handle)
		w.nav.dispose()
		local visits, releases = w.counts()
		expect(visits).toBe(releases)
	end)
	it("a nested stack uses its own resized viewport and reduced motion completes in place", function()
		for _, reduced in { false, true } do
			local w = fixture({ reducedMotion = reduced }, { enter = "slide-left", exit = "slide-right" })
			w.pres.dismiss(w.handle)
			w.present(UI.Screen({
				id = "S",
				children = {
					UI.VStack({
						id = "Shell",
						width = UI.fill(),
						height = UI.fill(),
						padding = 24,
						children = {
							UI.Button({ id = "Before", label = "Outside" }),
							w.nav.blueprint,
							UI.Button({ id = "After", label = "Outside" }),
						},
					}),
				},
			}))
			for _, width in { 640, 980 } do
				w.env:set("viewportRect", { x = 0, y = 0, w = width, h = 700 })
				w.settle(60)
				local box = w.adapter.node("/S/Shell/Nav").rect
				expect(box.w < width).toBe(true)
				w.nav.api.push({ id = "step", value = width })
				w.pres.refresh()
				local key = w.nav.dump().current.key
				local current = w.adapter.node("/S/Shell/Nav/Pages/[" .. key .. "]/PageMotion")
				expect(math.abs(current.rect.y - box.y) < 0.01).toBe(true)
				expect(math.abs(current.presentationOffset.x - (if reduced then 0 else box.w)) < 0.01).toBe(true)
				w.settle(60)
				w.nav.api.popToRoot()
				w.settle(60)
			end
			w.pres.dismiss(w.handle)
			w.nav.dispose()
		end
	end)
end)

describe("NavigationStack retained and not-yet-presented pages", function()
	it("rapid Back restores a retained page's remembered control even when shell chrome holds focus", function()
		local w = fixture({ reducedMotion = false }, { enter = "slide-left", exit = "slide-right" })
		w.pres.dismiss(w.handle)
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "Shell",
					width = UI.fill(),
					height = UI.fill(),
					children = {
						UI.Button({ id = "Chrome", label = "Outside" }),
						w.nav.blueprint,
					},
				}),
			},
		}))
		w.settle(60)
		local remembered = find(w, "/Other")
		w.pres.focus.focusOn(remembered)
		w.nav.api.push({ id = "step" })
		w.pres.refresh()
		w.tick(1 / 120)
		for _, path in w.adapter.paths() do
			if path:find("[Page1]", 1, true) and path:sub(-5) == "/Next" then
				w.pres.focus.focusOn(path)
			end
		end
		w.pres.focus.focusOn("/S/Shell/Chrome")
		w.nav.api.pop()
		w.settle(120)
		expect(w.pres.focus.focused:get()).toBe(remembered)
		w.pres.dismiss(w.handle)
		w.nav.dispose()
	end)
	it("navigation before the first presentation appears in place without a guessed slide width", function()
		local w = world.new({ reducedMotion = false })
		local function content()
			return UI.Button({ label = "Ready" })
		end
		local nav = Facet.Controls.NavigationStack(w.core, {
			id = "Nav",
			path = w.core:signal({}),
			backLabel = "Back",
			root = { content = content },
			destinations = { step = { content = content } },
			transition = { enter = "slide-left" },
		})
		nav.api.push({ id = "step" })
		w.present(UI.Screen({ id = "S", children = { nav.blueprint } }))
		expect(w.pres.motionClock:activeCount()).toBe(0)
		expect(nav.dump().depth).toBe(1)
		w.pres.dismiss(w.handle)
		nav.dispose()
	end)
end)
