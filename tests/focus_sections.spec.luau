--!strict
local t = require("./lib/testkit")
local world = require("./lib/world")
local Facet = require("../src") :: any
local UI = Facet.UI
local function button(id)
	return UI.Button({ id = id, label = id, width = { type = "fixed", px = 100 }, height = { type = "fixed", px = 50 } })
end
t.describe("declared focus sections", function()
	t.it("uses broad section bounds and restores an eligible descendant", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 1000, h = 700 }, preferredInput = "Gamepad" })
		local enabled = w.core:signal(true)
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "Body",
					gap = 80,
					children = {
						UI.focusSection(
							UI.HStack({
								id = "Hero",
								width = UI.fill(),
								children = {
									button("Play"),
									UI.Button({ id = "Info", label = "Info", enabled = enabled }),
								},
							}),
							{ entry = "restore", preferred = "Info" }
						),
						UI.focusSection(
							UI.HStack({
								id = "Shelf",
								width = UI.fill(),
								align = "end",
								children = {
									button("A"),
									button("B"),
								},
							}),
							{ entry = "nearest" }
						),
					},
				}),
			},
		}))
		w.pres.focus.focusOn("/S/Body/Shelf/B")
		w.press("DPadUp")
		t.expect(w.pres.focus.focused:get()).toBe("/S/Body/Hero/Info")
		w.pres.focus.focusOn("/S/Body/Hero/Play")
		w.press("DPadDown")
		w.press("DPadUp")
		t.expect(w.pres.focus.focused:get()).toBe("/S/Body/Hero/Play")
		enabled:set(false)
		w.settle(1)
		w.pres.focus.focusOn("/S/Body/Shelf/B")
		w.press("DPadUp")
		t.expect(w.pres.focus.focused:get()).toBe("/S/Body/Hero/Play")
		w.pres.dismiss(w.handle)
	end)
	t.it("preserves grid exits inside a declared section", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 }, preferredInput = "Gamepad" })
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.focusSection(UI.Grid({
					id = "Grid",
					columns = 2,
					children = { button("A"), button("B"), button("C"), button("D") },
				})),
			},
		}))
		w.pres.focus.focusOn("/S/Grid/B")
		w.press("DPadDown")
		t.expect(w.pres.focus.focused:get()).toBe("/S/Grid/D")
		w.press("DPadUp")
		t.expect(w.pres.focus.focused:get()).toBe("/S/Grid/B")
		w.pres.dismiss(w.handle)
	end)
	t.it("leaves a grid section at its outer boundary", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 }, preferredInput = "Gamepad" })
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "Body",
					children = {
						UI.focusSection(UI.Grid({
							id = "Grid",
							columns = 2,
							children = {
								button("A"),
								button("B"),
								button("C"),
								button("D"),
							},
						})),
						button("Outside"),
					},
				}),
			},
		}))
		w.pres.focus.focusOn("/S/Body/Grid/D")
		w.press("DPadDown")
		t.expect(w.pres.focus.focused:get()).toBe("/S/Body/Outside")
		w.pres.dismiss(w.handle)
	end)
	t.it("honors outer preferred entry while preserving nested section navigation", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 }, preferredInput = "Gamepad" })
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "Body",
					gap = 40,
					children = {
						UI.focusSection(
							UI.VStack({
								id = "Outer",
								children = {
									UI.focusSection(
										UI.HStack({ id = "Inner", children = { button("A"), button("B") } })
									),
								},
							}),
							{ preferred = "Inner/B", entry = "first" }
						),
						button("Outside"),
					},
				}),
			},
		}))
		t.expect(w.pres.focus.focused:get()).toBe("/S/Body/Outer/Inner/B")
		w.pres.focus.focusOn("/S/Body/Outside")
		w.press("DPadUp")
		t.expect(w.pres.focus.focused:get()).toBe("/S/Body/Outer/Inner/B")
		w.press("DPadLeft")
		t.expect(w.pres.focus.focused:get()).toBe("/S/Body/Outer/Inner/A")
		w.pres.dismiss(w.handle)
	end)
	t.it("rejects inert sections and malformed entry declarations", function()
		t.expect(function()
			UI.focusSection(UI.Text({ text = "x" }), {})
		end).toThrow()
		t.expect(function()
			UI.focusSection(UI.VStack({ children = {} }), { entry = "random" })
		end).toThrow()
	end)
	t.it("keeps adjacent section topology and contributed exit identities", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 500 }, preferredInput = "Gamepad" })
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.focusSection(UI.Grid({
					id = "Grid",
					columns = 2,
					children = { button("A"), button("B"), button("C"), button("D") },
				})),
				UI.focusSection(UI.HStack({ id = "Below", children = { button("OutsideA"), button("OutsideB") } })),
			},
		}))
		w.pres.focus.focusOn("/S/Grid/D")
		w.press("DPadDown")
		t.expect(w.pres.focus.focused:get()).toBe("/S/Below/OutsideB")
		w.pres.dismiss(w.handle)
		local function control(id, exits)
			return Facet.contribution.attach(UI.VStack({ id = id, children = { button("Action") } }), {
				focusGroups = function(node)
					return {
						{ name = id .. "Group", axis = "vertical", order = { node.path .. "/Action" }, exit = exits },
					}
				end,
			})
		end
		w.present(
			UI.Screen({ id = "S", children = { control("A", { down = "BGroup" }), UI.focusSection(control("B")) } })
		)
		w.pres.focus.focusOn("/S/A/Action")
		w.press("DPadDown")
		t.expect(w.pres.focus.focused:get()).toBe("/S/B/Action")
		w.pres.dismiss(w.handle)
	end)
	t.it("moves between rows without reentering its own section", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 500 }, preferredInput = "Gamepad" })
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.focusSection(UI.VStack({
					id = "Section",
					children = {
						UI.HStack({ id = "First", children = { button("A"), button("B") } }),
						UI.HStack({ id = "Second", children = { button("C"), button("D") } }),
					},
				})),
			},
		}))
		w.pres.focus.focusOn("/S/Section/First/B")
		w.press("DPadDown")
		t.expect(w.pres.focus.focused:get()).toBe("/S/Section/Second/D")
		w.pres.dismiss(w.handle)
	end)
end)
