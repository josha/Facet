--!strict
--[[ UI.Notice — inline status copy, and the page-local affixed recipe whose
	measured rect reserves space a real content consumer then avoids. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local world = require("./lib/world")
local Facet = require("../src") :: any
local Compose = Facet.Compose

local function mount(content: (UI: any) -> { any }, opts: any?): any
	local o = opts or {}
	local w = world.new({ viewport = { x = 0, y = 0, w = o.w or 800, h = o.h or 600 }, reducedMotion = true })
	if o.classes ~= nil then
		w.env:set("capabilities", o.classes.capabilities)
		w.env:set("preferredInput", o.classes.preferredInput)
	end
	local UI = w.UI
	w.present(function()
		return UI.Screen("S")({ UI.VStack("Page")({ width = UI.fill(), gap = "s", table.unpack(content(UI)) }) })
	end)
	w.settle(3)
	return w
end

local ROOT = "/S/Page/Conn"

describe("Notice: inline copy, accessories and close", function()
	it("paints the severity icon, title and message, and the close reports the press only", function()
		local closed = 0
		local w = mount(function(UI)
			return {
				UI.Notice("Conn")({
					severity = "warning",
					title = "Connection interrupted",
					message = "Reconnecting to the race server.",
					onDismiss = function()
						closed += 1
					end,
				}),
			}
		end)
		expect(w.adapter.node(`{ROOT}/Content/Row/Icon`).decorationHint.icon).toBe("status.warning")
		expect(w.adapter.node(`{ROOT}/Content/Row/Body/Copy/Title`).props.text).toBe("Connection interrupted")
		expect(w.adapter.node(`{ROOT}/Content/Row/Body/Copy/Message`).props.text).toBe(
			"Reconnecting to the race server."
		)
		local close = w.adapter.node(`{ROOT}/Content/Row/Close`).rect
		expect(close.w >= 44 and close.h >= 44).toBe(true)
		w.adapter.tap(`{ROOT}/Content/Row/Close`)
		w.settle(1)
		expect(closed).toBe(1)
		-- the caller unmounts: the notice is still there until it does
		expect(w.adapter.node(ROOT) ~= nil).toBe(true)
	end)

	it("icon = false hides only the artwork, and an explicit source paints that source", function()
		local w = mount(function(UI)
			return {
				UI.Notice("Conn")({ message = "Saved.", severity = "success", icon = false }),
				UI.Notice("Other")({ message = "Custom.", icon = "flag" }),
			}
		end)
		expect(w.adapter.node(`{ROOT}/Content/Row/Icon`)).toBeNil()
		expect(w.adapter.node(`{ROOT}/Content/Row/Body/Copy/Message`).props.text).toBe("Saved.")
		expect(w.adapter.node("/S/Page/Other/Content/Row/Icon").decorationHint.icon).toBe("flag")
	end)

	it("the link and actions sit beside the copy when there is room and move below it when there is not", function()
		local pressed: { string } = {}
		local function spec(UI: any): { any }
			return {
				UI.Notice("Conn")({
					message = "Update available.",
					link = {
						label = "Notes",
						onActivate = function()
							table.insert(pressed, "Notes")
						end,
					},
					actions = {
						{
							id = "Install",
							label = "Install",
							role = "default",
							onActivate = function()
								table.insert(pressed, "Install")
							end,
						},
					},
				}),
			}
		end
		local wide = mount(spec, { w = 900 })
		expect(wide.record("Conn").dump().accessories).toBe("beside")
		local copy = wide.adapter.node(`{ROOT}/Content/Row/Body/Copy`).rect
		local acc = wide.adapter.node(`{ROOT}/Content/Row/Body/Accessories`).rect
		expect(acc.x >= copy.x + copy.w - 1).toBe(true)
		local narrow = mount(spec, { w = 320 })
		expect(narrow.record("Conn").dump().accessories).toBe("below")
		local copy2 = narrow.adapter.node(`{ROOT}/Content/Row/Body/Copy`).rect
		local acc2 = narrow.adapter.node(`{ROOT}/Content/Row/Body/Accessories`).rect
		expect(acc2.y >= copy2.y + copy2.h - 1).toBe(true)
		narrow.adapter.tap(`{ROOT}/Content/Row/Body/Accessories/Install`)
		narrow.adapter.tap(`{ROOT}/Content/Row/Body/Accessories/Link`)
		expect(table.concat(pressed, ",")).toBe("Install,Notes")
		-- actions never close the notice
		expect(narrow.adapter.node(ROOT) ~= nil).toBe(true)
	end)

	it("a link wears no plate, and on an emphasis fill the link and default action are ordinary controls", function()
		local function spec(appearance: string?): (any) -> { any }
			return function(UI: any): { any }
				return {
					UI.Notice("Conn")({
						message = "Update available.",
						appearance = appearance,
						link = { label = "Notes", onActivate = function() end },
						actions = {
							{ id = "Install", label = "Install", role = "default", onActivate = function() end },
						},
					}),
				}
			end
		end
		local ACC = `{ROOT}/Content/Row/Body/Accessories`
		local plain = mount(spec(nil), { w = 900 })
		local link = plain.adapter.node(`{ACC}/Link`).props
		expect(`{link.appearance} {link.surface}`).toBe("link plain")
		expect(plain.adapter.node(`{ACC}/Install`).props.surface).toBe("accent")
		local loud = mount(spec("emphasis"), { w = 900 })
		local link2, install = loud.adapter.node(`{ACC}/Link`).props, loud.adapter.node(`{ACC}/Install`).props
		expect(`{link2.appearance} {install.surface}`).toBe("nil nil")
	end)

	it("arrival never moves focus, and every control is a pad stop in the page's own order", function()
		local show = Compose.cell(false)
		local w = mount(function(UI)
			return {
				UI.Button("Before")({ label = "Before" }),
				UI.When("Gate")({
					condition = show,
					thenView = function()
						return UI.Notice("Conn")({
							message = "Heads up.",
							actions = { { id = "Go", label = "Go", onActivate = function() end } },
							onDismiss = function() end,
						})
					end,
				}),
			}
		end, {
			classes = {
				capabilities = { keyboard = false, mouse = false, touch = false, gamepad = true },
				preferredInput = "Gamepad",
			},
		})
		expect(w.pres.focus.focusOn("/S/Page/Before")).toBe(true)
		show:set(true)
		w.settle(2)
		expect(w.pres.focus.focused:peek()).toBe("/S/Page/Before")
		w.press("Down")
		w.settle(1)
		expect(string.find(w.pres.focus.focused:peek() or "", "/Conn/", 1, true) ~= nil).toBe(true)
	end)

	it("keyboard and gamepad reach the action and press it; a pointer or finger taps it", function()
		for _, route in { "pointer", "touch", "keyboard", "gamepad" } do
			local pressed = 0
			local w = mount(function(UI)
				return {
					UI.Notice("Conn")({
						message = "Update ready.",
						actions = {
							{
								id = "Install",
								label = "Install",
								onActivate = function()
									pressed += 1
								end,
							},
						},
					}),
				}
			end)
			local path = `{ROOT}/Content/Row/Body/Accessories/Install`
			if route == "pointer" or route == "touch" then
				w.adapter.tap(path, { source = "pointer", pointer = route })
			else
				w.pres.focus.setFocusOrigin("navigation")
				expect(w.pres.focus.focusOn(path)).toBe(true)
				w.press(if route == "keyboard" then "Return" else "ButtonA")
			end
			w.settle(1)
			expect(`{route}: {pressed}`).toBe(`{route}: 1`)
		end
	end)

	it("malformed specs are refused by name", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 } })
		local UI = w.UI
		local noop = function() end
		for index, bad in
			{
				{},
				{ message = "m", severity = "fatal" },
				{ message = "m", appearance = "loud" },
				{ message = "m", placement = "bottom" },
				{ message = "m", icon = "" },
				{ message = "m", link = { label = "L" } },
				{
					message = "m",
					actions = {
						{ id = "A", label = "A", onActivate = noop },
						{ id = "B", label = "B", onActivate = noop },
						{ id = "C", label = "C", onActivate = noop },
					},
				},
				{ message = "m", controlSize = "huge" },
				{ message = "m", extra = true },
				-- the built-in sibling buttons' ids, and action value types
				{ message = "m", actions = { { id = "Link", label = "L", onActivate = noop } } },
				{ message = "m", actions = { { id = "Close", label = "C", onActivate = noop } } },
				{ message = "m", actions = { { id = "A", label = 5, onActivate = noop } } },
				{ message = "m", actions = { { id = "A", label = "A", enabled = "yes", onActivate = noop } } },
				{ message = "m", actions = { { id = "A", label = "A", busy = 1, onActivate = noop } } },
			}
		do
			local ok = pcall(function()
				w.scoped(function()
					return UI.Notice(bad :: any)
				end)
			end)
			expect(`case {index} refused: {not ok}`).toBe(`case {index} refused: true`)
		end
	end)
end)

describe("Notice: affixed placement reserves space a real consumer avoids", function()
	-- the documented recipe: the safe root is a fill ZStack; the page content reads
	-- the reservations through Facet.layout.hudInsets; the notice sits on top
	local function affixed(notices: (UI: any) -> { any }, opts: any?): (any, any)
		local o = opts or {}
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 }, reducedMotion = true })
		local UI = w.UI
		local bounds = Compose.cell({ x = 0, y = 0, w = 800, h = 600 })
		local function reserved(use: any): any
			local inset = Facet.layout.hudInsets({
				bounds = use(bounds),
				reservations = use(w.pres.hudReservations),
			})
			return { top = inset.top, bottom = inset.bottom, left = inset.left, right = inset.right }
		end
		w.present(function()
			local children: { any } = {
				UI.ZStack("Content")({
					width = UI.fill(),
					height = UI.fill(),
					padding = reserved,
					UI.ScrollView("Body")({
						width = UI.fill(),
						height = UI.fill(),
						UI.Text("Top")({ text = "Page content" }),
					}),
				}),
			}
			for _, n in notices(UI) do
				table.insert(children, n)
			end
			return UI.Screen("Page")({
				padding = 0,
				UI.ZStack("Safe")({ width = UI.fill(), height = UI.fill(), table.unpack(children) }),
			})
		end, o.present)
		w.settle(4)
		return w, UI
	end

	it("content moves down by the notice's real height and returns when it goes", function()
		local show = Compose.cell(true)
		local w = affixed(function(UI)
			return {
				UI.When("Gate")({
					condition = show,
					thenView = function()
						return UI.Notice("Conn")({ placement = "affixed", severity = "warning", message = "Offline." })
					end,
				}),
			}
		end)
		local noticeRect = w.adapter.node("/Page/Safe/Gate/then/Conn").rect
		local top = w.adapter.node("/Page/Safe/Content/Body/Top").rect
		expect(noticeRect.y).toBe(0)
		expect(top.y >= noticeRect.y + noticeRect.h - 1).toBe(true)
		-- the body scrolls under a notice that stays pinned
		w.adapter.setScrollPosition(w.adapter.node("/Page/Safe/Content/Body"), { x = 0, y = 40 })
		w.settle(2)
		expect(w.adapter.node("/Page/Safe/Gate/then/Conn").rect.y).toBe(0)
		show:set(false)
		w.settle(4)
		expect(#w.pres.hudReservations:peek()).toBe(0)
		expect(w.adapter.node("/Page/Safe/Content/Body/Top").rect.y).toBe(0)
	end)

	it("two stacked notices reserve the deepest edge, same names in two apps never collide", function()
		local w = affixed(function(UI)
			return {
				UI.VStack("Stack")({
					width = UI.fill(),
					height = UI.hug(),
					alignV = "start",
					UI.Notice("A")({ placement = "affixed", message = "First." }),
					UI.Notice("B")({ placement = "affixed", message = "Second." }),
				}),
			}
		end)
		local b = w.adapter.node("/Page/Safe/Stack/B").rect
		local top = w.adapter.node("/Page/Safe/Content/Body/Top").rect
		expect(top.y >= b.y + b.h - 1).toBe(true)
		expect(#w.pres.hudReservations:peek()).toBe(2)
		local w2 = affixed(function(UI)
			return { UI.Notice("A")({ placement = "affixed", message = "Other app." }) }
		end)
		expect(#w2.pres.hudReservations:peek()).toBe(1)
		expect(#w.pres.hudReservations:peek()).toBe(2)
	end)

	it("a taller message grows the reservation live", function()
		local message = Compose.cell("Short.")
		local w = affixed(function(UI)
			return { UI.Notice("Conn")({ placement = "affixed", message = message }) }
		end)
		local before = w.pres.hudReservations:peek()[1].rect.h
		message:set(string.rep("A much longer message that wraps onto more lines. ", 8))
		w.settle(4)
		local after = w.pres.hudReservations:peek()[1].rect.h
		expect(after > before).toBe(true)
		local top = w.adapter.node("/Page/Safe/Content/Body/Top").rect
		expect(top.y >= after - 1).toBe(true)
	end)
end)

describe("Notice: the Status tab's affixed banner", function()
	it("the banner pins to the tab's top and its content moves out of the way, then back", function()
		local scenario = require("../examples/gallery/scenarios/status_family") :: any
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 900 }, reducedMotion = true })
		local built = scenario.build({
			Facet = Facet,
			UI = w.UI,
			Compose = Compose,
			core = w.core,
			env = w.env,
			adapter = w.adapter,
			presenter = w.pres,
		})
		w.present(function()
			return built.screen()
		end, built.present)
		w.settle(3)
		local reset = "/StatusFamily/Safe/Content/Recipes/Reset"
		local before = w.adapter.node(reset).rect.y
		w.adapter.tap("/StatusFamily/Safe/Content/Recipes/NoticeRecipe/Commands/ShowBanner")
		w.settle(4)
		local banner = w.adapter.node("/StatusFamily/Safe/Banner/then/Offline").rect
		expect(banner.h > 0).toBe(true)
		expect(w.adapter.node(reset).rect.y >= before + banner.h - 1).toBe(true)
		w.adapter.tap("/StatusFamily/Safe/Banner/then/Offline/Content/Row/Close")
		w.settle(4)
		expect(w.adapter.node("/StatusFamily/Safe/Banner/then/Offline")).toBeNil()
		expect(w.adapter.node(reset).rect.y).toBe(before)
	end)
end)

describe("Notice: an art theme's frame carve holds the content", function()
	-- the standard plate is the Content stack itself, so the shared surface inset
	-- path (the panel carve) insets the icon, copy and accessories off the art
	it("pixel, fantasy and glossy: every part sits inside the carve at every rung", function()
		for _, name in { "pixel_quest", "fantasy_ornate", "glossy_mobile" } do
			local metrics = Facet.themes.resolve(require(`../examples/themes/{name}`).build(Facet.themes), nil, {})
			local carve = metrics.chromeInsets.panel or { left = 0, right = 0, top = 0, bottom = 0 }
			for _, rung in { "xsmall", "compact", "regular", "large" } do
				local w = world.new({
					viewport = { x = 0, y = 0, w = 800, h = 600 },
					reducedMotion = true,
					themeMetrics = metrics,
				})
				local UI = w.UI
				w.present(function()
					return UI.Screen("S")({
						UI.VStack("Page")({
							width = UI.fill(),
							UI.Notice("Conn")({
								title = "Update available",
								message = "A new track pack is ready.",
								controlSize = rung,
								actions = { { id = "Install", label = "Install", onActivate = function() end } },
								onDismiss = function() end,
							}),
						}),
					})
				end)
				w.settle(3)
				-- the painted plate (the Content stack, or the root before this fix)
				local box = (w.adapter.node(ROOT .. "/Content") or w.adapter.node(ROOT)).rect
				for _, part in
					{
						"/Content/Row/Icon",
						"/Content/Row/Body/Copy/Title",
						"/Content/Row/Body/Copy/Message",
						"/Content/Row/Close",
					}
				do
					local node = w.adapter.node(ROOT .. part)
					if node == nil then -- a sized control sits in its hit-floor wrapper
						for _, path in w.adapter.paths() do
							if string.sub(path, 1, #ROOT) == ROOT and string.sub(path, -6) == "/Close" then
								node = w.adapter.node(path)
							end
						end
					end
					local r = assert(node, part).rect
					local inside = r.x >= box.x + carve.left - 0.5
						and r.y >= box.y + carve.top - 0.5
						and r.x + r.w <= box.x + box.w - carve.right + 0.5
						and r.y + r.h <= box.y + box.h - carve.bottom + 0.5
					expect(`{name} {rung} {part}: {inside}`).toBe(`{name} {rung} {part}: true`)
				end
				w.close()
			end
		end
	end)
end)
