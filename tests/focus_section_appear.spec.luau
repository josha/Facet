--!strict
--[[ WHERE THE RING GOES WHEN A BRANCH OPENS, AND WHERE IT COMES BACK TO.

	Found live on 2026-09-20: opening a catalog card from the keyboard put the
	focus ring on the application's TAB STRIP. Nothing was wrong with the focus
	graph. The branch that opened declared `enabled = false` on the column
	underneath it, so every stop the ring could have been standing on went
	ineligible in the same frame the detail page arrived; the graph did what it is
	supposed to do with a focused node that stopped being focusable — it took the
	nearest surviving neighbour — and the nearest surviving neighbour was three
	levels up and outside the app. A player who pressed Return to open a game then
	had to walk all the way back down to read it.

	A presented SURFACE has had an answer since `presenter.initialFocus`. An
	in-page branch — a `UI.When`, a `Compose.show`, a route inside a page — had no
	spelling for it at all, which is the shape most of a real screen opens and
	closes in. `UI.focusSection` already described a REGION of the ring and said
	where navigation lands when it walks in (`entry`/`preferred`); the two keys
	pinned here say where focus goes when that region ARRIVES, and where it goes
	back to when the region LEAVES.

	These cases drive the real path: a mounted surface, the real focus graph, the
	real per-solve focus sync. The two-frame fact ("this region is new") is the
	whole difficulty, so every case settles, changes one cell, and settles again.
]]
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local nativeWorld = require("./lib/native_world")
local Compose = Facet.Compose

local VIEWPORT = { x = 0, y = 0, w = 1280, h = 720 }

--[[ A LIST AND A DETAIL PANEL THAT REPLACES IT, which is the showcase's own
	shape reduced to what the focus ring can see: three rows, and a branch that
	opens over them and disables them while it is open. `enabled = false` is not
	incidental — it is what makes the old behaviour reproduce, because a branch
	that left its siblings focusable would have had somewhere sensible to fall. ]]
local function build(app: any, open: any, section: any?)
	return function()
		local UI = app.controls
		local rows = {}
		for index = 1, 3 do
			table.insert(
				rows,
				UI.Button("Row" .. index)({
					label = "Row " .. index,
					onActivate = function()
						open:set(true)
					end,
				})
			)
		end
		local panel = UI.VStack("Detail")({
			width = UI.fill(),
			UI.Button("Back")({
				label = "Back",
				onActivate = function()
					open:set(false)
				end,
			}),
			UI.Button("Save")({ label = "Save", onActivate = function() end }),
		})
		return UI.Screen("S")({
			UI.VStack("List")({
				width = UI.fill(),
				enabled = function(use)
					return not use(open)
				end,
				table.unpack(rows),
			}),
			UI.When("Expand")({
				condition = function(use)
					return use(open)
				end,
				thenView = function()
					return if section ~= nil then UI.focusSection(panel, section) else panel
				end,
			}),
		})
	end
end

local function mount(open: any, section: any?)
	local app, _, settle = nativeWorld(VIEWPORT)
	app.mount(build(app, open, section))
	settle(8)
	return app, settle, app.presenter.focus
end

t.describe("UI.focusSection focusOnAppear / returnFocus", function()
	t.it("WITHOUT the keys, the ring does not come back to the row that opened", function()
		--[[ The defect, pinned so the fix below is measured against something. The
			graph is not doing anything wrong when the branch OPENS — it takes the
			nearest surviving neighbour, which in a tree this small is the panel
			itself. What no amount of neighbour-finding can do is remember, across
			the branch's whole lifetime, WHICH row the player was on; so when the
			branch closes the ring lands wherever the ring happens to land, and the
			player's place in a list they were walking is simply gone. ]]
		local open = Compose.cell(false)
		local app, settle, graph = mount(open)
		graph.focusOn("/S/List/Row3")
		t.expect(graph.focused:peek()).toBe("/S/List/Row3")
		open:set(true)
		settle(8)
		open:set(false)
		settle(8)
		t.expect(graph.focused:peek() ~= "/S/List/Row3").toBe(true)
		app.dispose()
	end)

	t.it("focusOnAppear = true lands the ring on the branch's first stop", function()
		local open = Compose.cell(false)
		local app, settle, graph = mount(open, { focusOnAppear = true })
		graph.focusOn("/S/List/Row2")
		open:set(true)
		settle(8)
		t.expect(graph.focused:peek()).toBe("/S/Expand/then/Detail/Back")
		app.dispose()
	end)

	t.it("focusOnAppear names a descendant by its own id", function()
		local open = Compose.cell(false)
		local app, settle, graph = mount(open, { focusOnAppear = "Save" })
		graph.focusOn("/S/List/Row1")
		open:set(true)
		settle(8)
		t.expect(graph.focused:peek()).toBe("/S/Expand/then/Detail/Save")
		app.dispose()
	end)

	t.it("returnFocus puts the ring back on the row that opened the branch", function()
		local open = Compose.cell(false)
		local app, settle, graph = mount(open, { focusOnAppear = true, returnFocus = true })
		graph.focusOn("/S/List/Row3")
		open:set(true)
		settle(8)
		t.expect(graph.focused:peek()).toBe("/S/Expand/then/Detail/Back")
		open:set(false)
		settle(8)
		t.expect(graph.focused:peek()).toBe("/S/List/Row3")
		app.dispose()
	end)

	t.it("remembers what held focus BEFORE the claim moved it, not after", function()
		-- a section that does both must not restore itself
		local open = Compose.cell(false)
		local app, settle, graph = mount(open, { focusOnAppear = "Save", returnFocus = true })
		graph.focusOn("/S/List/Row1")
		open:set(true)
		settle(8)
		t.expect(graph.focused:peek()).toBe("/S/Expand/then/Detail/Save")
		open:set(false)
		settle(8)
		t.expect(graph.focused:peek()).toBe("/S/List/Row1")
		app.dispose()
	end)

	t.it("a remembered target that is gone falls through rather than blanking the ring", function()
		-- Row2 is removed while the panel is open, so the restore refuses; the
		-- surviving scope's own entry rule is what decides, and the ring stays on
		-- something real
		local open = Compose.cell(false)
		local rowCount = Compose.cell(3)
		local app, _, settle = nativeWorld(VIEWPORT)
		app.mount(function()
			local UI = app.controls
			return UI.Screen("S")({
				UI.VStack("List")({
					width = UI.fill(),
					enabled = function(use)
						return not use(open)
					end,
					UI.ForEach("Rows")({
						Compose.keyed({
							from = Compose.formula(function(use)
								local list = {}
								for index = 1, use(rowCount) do
									table.insert(list, { id = index })
								end
								return list
							end),
							key = function(item)
								return item.id
							end,
							render = function(item)
								local id = item:peek().id
								return UI.Button("Row" .. id)({ label = "Row " .. id, onActivate = function() end })
							end,
						}),
					}),
				}),
				UI.When("Expand")({
					condition = function(use)
						return use(open)
					end,
					thenView = function()
						return UI.focusSection(
							UI.VStack("Detail")({
								width = UI.fill(),
								UI.Button("Back")({ label = "Back", onActivate = function() end }),
							}),
							{ focusOnAppear = true, returnFocus = true }
						)
					end,
				}),
			})
		end)
		settle(8)
		local graph = app.presenter.focus
		graph.focusOn("/S/List/Rows/Row3")
		open:set(true)
		settle(8)
		t.expect(graph.focused:peek()).toBe("/S/Expand/then/Detail/Back")
		rowCount:set(1) -- Row3 is gone before the branch closes
		settle(8)
		open:set(false)
		settle(8)
		local landed = graph.focused:peek()
		t.expect(landed ~= nil).toBe(true)
		t.expect(string.find(tostring(landed), "Row3", 1, true) == nil).toBe(true)
		app.dispose()
	end)

	t.it("refuses a misspelled field rather than accepting it silently", function()
		local app, _, settle = nativeWorld(VIEWPORT)
		local ok, err = true, nil
		app.mount(function()
			local UI = app.controls
			ok, err = pcall(function()
				return UI.focusSection(UI.VStack("A")({ width = UI.fill() }), { focusOnApear = true })
			end)
			return UI.Screen("S")({ UI.Button("B")({ label = "B", onActivate = function() end }) })
		end)
		settle(2)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(err), "focusOnApear", 1, true) ~= nil).toBe(true)
		app.dispose()
	end)
end)
