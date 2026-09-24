--!strict
local harness = require("./lib/harness")
-- DisclosureGroup: the caret turns, the content reveals, and — with a presenter
-- — the siblings it displaces glide (task 12, transitions round, spec 2I).
--
-- The two-region CaretOpen/CaretShut mount/unmount (display_controls.spec.luau,
-- theme_icons_applied.spec.luau) is replaced here by a single `chevron.trailing`
-- glyph whose paint-only `rotation` springs 0 -> 90: this file is the new
-- contract's home, not a rewrite of those two — they keep proving the header's
-- focus story and the icon-request story, which this task did not touch.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local worldLib = require("./lib/harness_world")
local Facet = require("../src") :: any
local Compose = require("../src/vendor/compose/core")

local FRAME = 1 / 60

local function makeWorld(opts: any?)
	local merged: any = { viewport = { x = 0, y = 0, w = 390, h = 844 } }
	for k, v in (opts or {}) :: any do
		merged[k] = v
	end
	return worldLib.new(merged)
end

describe("disclosure: caret turns, content reveals", function()
	it("the caret rotates toward 90 on expand and back on collapse", function()
		local w = makeWorld()
		local expanded = Compose.cell(false)
		local group = harness.Controls.DisclosureGroup(w.core, {
			id = "Adv",
			label = "Advanced",
			expanded = expanded,
			content = function()
				return harness.UI.Text({ id = "Body", text = "hello" })
			end,
		})
		w.pres.present(harness.UI.Screen({ id = "S", children = { group.blueprint } }))
		w.pres.refresh()
		local caret = w.adapter.node("/S/Adv/Header/Caret")
		expect(caret.rotation or 0).toBe(0)
		expanded:set(true)
		-- the caret's rotation is an AUTHORED presentation prop, not a
		-- withAnimation flight record: it reaches the adapter through the
		-- ordinary reactive-commit walk, so advancing the spring needs a
		-- `refresh()` alongside every `tick()` (button.luau's own "button: pop"
		-- test drives its lift/scale spring the identical way).
		for _ = 1, 60 do
			w.pres.tick(FRAME)
			w.pres.refresh()
		end
		expect(math.abs((caret.rotation or 0) - 90) < 0.5).toBe(true)
		expect(w.adapter.node("/S/Adv/Reveal/Body") ~= nil).toBe(true)
		expanded:set(false)
		for _ = 1, 60 do
			w.pres.tick(FRAME)
			w.pres.refresh()
		end
		expect(math.abs(caret.rotation or 0) < 0.5).toBe(true)
	end)
end)

-- ===== presenter-bound glide: the reason `presenter` exists on the spec =====
--
-- `spec.presenter` is ONLY for this: the caret and the content animate their
-- own paint off the ambient motion clock every mounted control gets for free
-- (see the describe block above, which never passes one). What a presenter
-- buys is `withAnimation("container", flip)` around the mutation itself, so
-- every OTHER node whose solved position the flip moves — a sibling below the
-- group, pushed down as the content claims its height — travels there instead
-- of jumping, exactly like `tests/with_animation.spec.luau`'s own header/body
-- pair proves for a plain layout change.
describe("disclosure: a presenter glides the sibling it displaces", function()
	it("with presenter given, a sibling below the group travels to its new place", function()
		local w = makeWorld()
		local expanded = Compose.cell(false)
		local group = harness.Controls.DisclosureGroup(w.core, {
			id = "Adv",
			label = "Advanced",
			expanded = expanded,
			presenter = w.pres,
			content = function()
				return harness.UI.Box({ id = "Body", height = { type = "fixed", px = 80 } })
			end,
		})
		w.pres.present(harness.UI.Screen({
			id = "S",
			padding = 0,
			gap = 0,
			children = {
				group.blueprint,
				harness.UI.Box({ id = "Sibling", height = { type = "fixed", px = 40 } }),
			},
		}))
		w.pres.refresh()
		local before = w.adapter.node("/S/Sibling").rect.y

		-- the real path: a tap on the header, not a direct `expanded:set` — the
		-- withAnimation call lives inside `toggle()`, dispatched through the same
		-- contribution `handleActivate` every input class reaches
		w.adapter.tap("/S/Adv/Header")

		local moved = w.adapter.node("/S/Sibling")
		-- the solve is already exact and instant on the frame the tap resolves...
		expect(moved.rect.y > before).toBe(true)
		-- ...but the PAINT is still seeded at the old place — it has not jumped
		expect(moved.presentedPosition.y).toBe(before)

		for _ = 1, 6 do
			w.pres.tick(FRAME)
		end
		local mid = w.adapter.node("/S/Sibling").presentedPosition.y
		expect(mid > before).toBe(true)
		expect(mid < w.adapter.node("/S/Sibling").rect.y).toBe(true)

		for _ = 1, 90 do
			w.pres.tick(FRAME)
		end
		local settled = w.adapter.node("/S/Sibling")
		expect(settled.presentedPosition.y).toBe(settled.rect.y)
	end)

	it("with no presenter, the same sibling jumps instantly — no flight to compare against", function()
		local w = makeWorld()
		local expanded = Compose.cell(false)
		local group = harness.Controls.DisclosureGroup(w.core, {
			id = "Adv",
			label = "Advanced",
			expanded = expanded,
			content = function()
				return harness.UI.Box({ id = "Body", height = { type = "fixed", px = 80 } })
			end,
		})
		w.pres.present(harness.UI.Screen({
			id = "S",
			padding = 0,
			gap = 0,
			children = {
				group.blueprint,
				harness.UI.Box({ id = "Sibling", height = { type = "fixed", px = 40 } }),
			},
		}))
		w.pres.refresh()
		local before = w.adapter.node("/S/Sibling").rect.y
		w.adapter.tap("/S/Adv/Header")
		w.pres.refresh()
		local moved = w.adapter.node("/S/Sibling")
		expect(moved.rect.y > before).toBe(true)
		-- no presenter bound, so nothing armed a flight: the paint lands exactly
		-- where the solve did, on the same frame
		expect(moved.presentedPosition.y).toBe(moved.rect.y)
	end)
end)

-- ===== reduced motion: the caret is decorative, so it SNAPS ================
describe("disclosure: reduced motion snaps the caret instead of turning it", function()
	it("the caret reaches 90 on the very first frame, not gradually", function()
		local w = makeWorld({ reducedMotion = true })
		local expanded = Compose.cell(false)
		local group = harness.Controls.DisclosureGroup(w.core, {
			id = "Adv",
			label = "Advanced",
			expanded = expanded,
			content = function()
				return harness.UI.Text({ id = "Body", text = "hello" })
			end,
		})
		w.pres.present(harness.UI.Screen({ id = "S", children = { group.blueprint } }))
		w.pres.refresh()
		local caret = w.adapter.node("/S/Adv/Header/Caret")
		expect(caret.rotation or 0).toBe(0)
		expanded:set(true)
		w.pres.tick(FRAME)
		w.pres.refresh()
		expect(math.abs((caret.rotation or 0) - 90) < 0.5).toBe(true)
	end)
end)

describe("disclosure content exit", function()
	it("keeps a long expanded list out of rasterized fade groups", function()
		local w = makeWorld()
		local expanded = Compose.cell(false)
		local group = harness.Controls.DisclosureGroup(w.core, {
			id = "Adv",
			label = "UI laboratory",
			expanded = expanded,
			content = function()
				local rows = {}
				for i = 1, 80 do
					table.insert(rows, harness.UI.Button({ id = "Row" .. i, label = "Laboratory entry " .. i }))
				end
				return harness.UI.VStack({ id = "Rows", children = rows })
			end,
		})
		w.present(harness.UI.Screen({ id = "S", children = { group.blueprint } }))
		expanded:set(true)
		w.pres.refresh()
		local path = "/S/Adv/Reveal"
		local content = w.adapter.node(path)
		expect(content.canvasGroupInstance).toBeNil()
		expect(content.presentedSize.h < 1).toBe(true)
		local previous = 0
		for _ = 1, 90 do
			w.tick()
			content = w.adapter.node(path)
			expect(content.canvasGroupInstance).toBeNil()
			expect(content.presentedSize.h >= previous - 0.01).toBe(true)
			expect(content.presentedSize.h <= content.rect.h + 0.01).toBe(true)
			expect(content.props.transform == nil or content.props.transform.scale == nil).toBe(true)
			previous = content.presentedSize.h
		end
		expect(content.presentedSize.h).toBe(content.rect.h)
		expanded:set(false)
		w.settle(4)
		local closingHeight = content.presentedSize.h
		expanded:set(true)
		w.pres.refresh()
		expect(w.adapter.node(path)).toBe(content)
		expect(content.presentedSize.h).toBe(closingHeight)
		w.settle(90)
		expect(content.presentedSize.h).toBe(content.rect.h)
		w.pres.dismiss(w.handle)
		group.dispose()
	end)

	it("starts clipping while the caret closes instead of disappearing after it", function()
		local w = makeWorld()
		local expanded = Compose.cell(true)
		local group = harness.Controls.DisclosureGroup(w.core, {
			id = "Adv",
			label = "Advanced",
			expanded = expanded,
			content = function()
				return harness.UI.Text({ id = "Body", text = "Additional settings" })
			end,
		})
		w.present(harness.UI.Screen({ id = "S", children = { group.blueprint } }))
		w.settle(120)
		expanded:set(false)
		w.settle(5)
		local content = w.adapter.node("/S/Adv/Reveal") or w.adapter.node("/S/Adv/Reveal/Body")
		expect(content ~= nil).toBe(true)
		expect(content.canvasGroupInstance).toBeNil()
		expect(content.presentedSize.h < content.rect.h * 0.95).toBe(true)
		w.settle(60)
		expect(w.adapter.node("/S/Adv/Reveal")).toBeNil()
		w.pres.dismiss(w.handle)
	end)
end)

describe("disclosure opening stays within its endpoints", function()
	it("never overshoots the caret or slides content past its resting position", function()
		local w = makeWorld()
		local expanded = Compose.cell(false)
		local group = harness.Controls.DisclosureGroup(w.core, {
			id = "Adv",
			label = "Advanced",
			expanded = expanded,
			content = function()
				return harness.UI.Text({ id = "Body", text = "Additional settings" })
			end,
		})
		w.present(harness.UI.Screen({ id = "S", children = { group.blueprint } }))
		expanded:set(true)
		for _ = 1, 90 do
			w.pres.tick(FRAME)
			w.pres.refresh()
			local angle = w.adapter.node("/S/Adv/Header/Caret").rotation or 0
			expect(angle >= 0 and angle <= 90).toBe(true)
			local content = w.adapter.node("/S/Adv/Reveal")
			expect(content.presentedPosition.y).toBe(content.rect.y)
		end
		w.pres.dismiss(w.handle)
	end)
end)

describe("DisclosureGroup header vocabulary", function()
	local world = require("./lib/world")
	local function find(w, suffix)
		for path, node in w.adapter.liveNodes() do
			if string.sub(path, -#suffix) == suffix then
				return node, path
			end
		end
		error("missing disclosure " .. suffix)
	end
	it("paints each appearance and opens a divider only with its content", function()
		for _, appearance in { "plain", "contained", "divided" } do
			local w = world.new()
			local expanded = Compose.cell(false)
			w.present(function()
				return w.UI.Screen("S")({
					w.UI.DisclosureGroup("Group")({
						label = "Details",
						description = "Configure the current race",
						icon = "menu",
						appearance = appearance,
						chevronPosition = "trailing",
						expanded = expanded,
						content = function()
							return w.UI.Text("Body")({ text = "Details" })
						end,
					}),
				})
			end)
			expect(find(w, "/Group").props.surface).toBe(if appearance == "contained" then "raised" else nil)
			local caret, label = find(w, "/Caret").rect, find(w, "/Label").rect
			expect(caret.x >= label.x + label.w).toBe(true)
			expect(find(w, "/Description").props.text).toBe("Configure the current race")
			local function dividerCount()
				local n = 0
				for _, node in w.adapter.liveNodes() do
					if node.class == "Divider" then
						n += 1
					end
				end
				return n
			end
			expect(dividerCount()).toBe(0)
			expanded:set(true)
			w.settle()
			expect(dividerCount()).toBe(if appearance == "divided" then 1 else 0)
			expanded:set(false)
			w.settle()
			expect(dividerCount()).toBe(0)
			w.close()
		end
	end)
	it("tracks description and rung geometry while preserving branch lifetime", function()
		local w = world.new({ reducedMotion = true })
		local expanded, size, description = Compose.cell(false), Compose.cell("compact"), Compose.cell("Details")
		local built, disposed = 0, 0
		w.present(function()
			return w.UI.Screen("S")({
				w.UI.DisclosureGroup("Group")({
					label = "Details",
					description = description,
					controlSize = size,
					expanded = expanded,
					content = function()
						built += 1
						Compose.cleanup(function()
							disposed += 1
						end)
						return w.UI.Button("Inside")({ label = "Inside", onActivate = function() end })
					end,
				}),
			})
		end)
		local header, path = find(w, "/Header")
		expect(header.rect.h >= 36).toBe(true)
		expect(string.find(path, "Header+target", 1, true) ~= nil).toBe(true)
		size:set("large")
		description:set("Updated details")
		w.settle()
		expect(header.rect.h >= 56).toBe(true)
		expect(find(w, "/Description").props.text).toBe("Updated details")
		for _ = 1, 3 do
			expanded:set(true)
			w.settle()
			expanded:set(false)
			w.settle()
		end
		expect(built).toBe(3)
		expect(disposed).toBe(3)
	end)
	it("binds the real focus hook and hands back before closing a wrapped header branch", function()
		local w = world.new({ reducedMotion = true })
		local expanded, order, bindings = Compose.cell(true), {}, 0
		local contributions = require("../src/input/contribution")
		local original = contributions.attach
		contributions.attach = function(root, bundle)
			if bundle.bindFocusGraph then
				local bind = bundle.bindFocusGraph
				bundle.bindFocusGraph = function(graph)
					bindings += 1
					bind({
						focused = graph.focused,
						focusOn = function(path)
							table.insert(order, "focus:" .. path)
							graph.focusOn(path)
						end,
					})
				end
			end
			return original(root, bundle)
		end
		local ok, err = pcall(function()
			w.present(function()
				return w.UI.Screen("S")({
					w.UI.DisclosureGroup("Group")({
						label = "Details",
						controlSize = "compact",
						expanded = expanded,
						onToggle = function()
							table.insert(order, "closed")
						end,
						content = function()
							return w.UI.Button("Inside")({ label = "Inside", onActivate = function() end })
						end,
					}),
				})
			end)
		end)
		contributions.attach = original
		assert(ok, err)
		expect(bindings).toBe(1)
		local _, header = find(w, "/Header")
		local _, inside = find(w, "/Inside")
		w.pres.focus.focusOn(inside)
		contributions.read(require("../src/paths").nodeAt(w.handle.root.node, "/S/Group")).handleActivate(header)
		w.settle()
		expect(order[1]).toBe("focus:" .. header)
		expect(order[2]).toBe("closed")
		expect(w.pres.focus.focused:peek()).toBe(header)
	end)
	it("returns keyboard focus before child or caller collapse without stealing unrelated focus", function()
		for _, reduced in { false, true } do
			local w = world.new({
				reducedMotion = reduced,
				preferredInput = "MouseKeyboard",
				hostOpts = { keyboardNavigation = true },
			})
			local expanded = Compose.cell(false)
			w.present(function()
				return w.UI.Screen("S")({
					w.UI.VStack("Cases")({
						width = { type = "fixed", px = 320 },
						w.UI.DisclosureGroup("Group")({
							label = "Details",
							expanded = expanded,
							content = function()
								return w.UI.Button("Inside")({
									label = "Close",
									onActivate = function()
										expanded:set(false)
									end,
								})
							end,
						}),
						w.UI.Button("Outside")({ label = "Next control" }),
					}),
				})
			end)
			local _, header = find(w, "/Header")
			expect(w.pres.focus.focusOn(header)).toBe(true)
			w.press("Return")
			w.settle(60)
			local _, inside = find(w, "/Inside")
			w.press("Tab")
			expect(w.pres.focus.focused:peek()).toBe(inside)
			w.press("Return")
			expect(expanded:peek()).toBe(false)
			expect(w.pres.focus.focused:peek()).toBe(header)
			w.settle(60)
			expect(w.adapter.node(inside)).toBeNil()
			expect(w.pres.focus.focused:peek()).toBe(header)
			expanded:set(true)
			w.settle(60)
			w.press("Tab")
			expect(w.pres.focus.focused:peek()).toBe(inside)
			expanded:set(false)
			expect(w.pres.focus.focused:peek()).toBe(header)
			w.settle(60)
			expanded:set(true)
			w.settle(60)
			local _, outside = find(w, "/Outside")
			expect(w.pres.focus.focusOn(outside)).toBe(true)
			expanded:set(false)
			w.settle(60)
			expect(w.pres.focus.focused:peek()).toBe(outside)
			w.close()
			expanded:set(true)
			expanded:set(false)
			expect(#w.adapter.paths()).toBe(0)
		end
	end)
end)

-- G7 (owner 2026-09-24): an outline of sections in a scroller closes up when one
-- collapses. The lab's gap came from a space-reserving `hidden`, not from this path;
-- this pins the path the lab now uses (groups in When branches, keyed rows).
describe("DisclosureGroup outline in a ScrollView", function()
	it("collapsing a section moves the next one up and shrinks the canvas; expanding grows it back", function()
		local w = require("./lib/world").new({ viewport = { x = 0, y = 0, w = 390, h = 400 } })
		local UI = w.UI
		local open = Compose.cell(true)
		w.present(function()
			local groups: any = { width = UI.fill() }
			for i = 1, 2 do
				table.insert(
					groups,
					UI.When("W" .. i)({
						Compose.show(Compose.cell(true), function()
							return UI.When("then")({
								UI.DisclosureGroup("G" .. i)({
									label = "Group " .. i,
									expanded = if i == 1 then open else Compose.cell(true),
									content = function()
										return UI.VStack("Rows")({
											width = UI.fill(),
											Compose.keyed({
												from = Compose.cell({ "a", "b", "c", "d" }),
												key = function(id: string): string
													return id
												end,
												render = function(id: any)
													return UI.Button("B" .. id:peek())({
														label = id:peek(),
														width = UI.fill(),
													})
												end,
											}),
										})
									end,
								}),
							})
						end),
					})
				)
			end
			return UI.Screen("S")({
				UI.ScrollView("Sc")({ width = UI.fill(), height = UI.fill(), UI.VStack("Tree")(groups) }),
			})
		end)
		w.settle(10)
		local function facts(): (number, number)
			local next, canvas = -1, -1
			for _, path in w.adapter.paths() do
				local node = w.adapter.node(path)
				if string.sub(path, -3) == "/G2" then
					next = node.rect.y
				elseif string.sub(path, -6) == "/S/Sc" then
					canvas = node.scrollRegion.contentH
				end
			end
			return next, canvas
		end
		local openY, openCanvas = facts()
		open:set(false)
		w.settle(60)
		local closedY, closedCanvas = facts()
		expect(closedY < openY).toBe(true)
		expect(closedCanvas).toBe(openCanvas - (openY - closedY))
		open:set(true)
		w.settle(60)
		local againY, againCanvas = facts()
		expect(`{againY},{againCanvas}`).toBe(`{openY},{openCanvas}`)
	end)
end)

describe("an outline DisclosureGroup is a tree row", function()
	it("no header plate or expanded wash, a chosen type role, and an indented body", function()
		local w = require("./lib/world").new({ viewport = { x = 0, y = 0, w = 390, h = 400 } })
		local UI = w.UI
		w.present(function()
			return UI.Screen("S")({
				UI.VStack("Tree")({
					width = UI.fill(),
					UI.DisclosureGroup("G")({
						label = "Inputs",
						appearance = "outline",
						textSize = "label",
						indent = "m",
						expanded = Compose.cell(true),
						content = function()
							return UI.Text("Row")({ text = "Button" })
						end,
					}),
				}),
			})
		end)
		w.settle(10)
		local header, label, group, row
		for _, path in w.adapter.paths() do
			local node = w.adapter.node(path)
			if string.match(path, "/Header$") then
				header = path
			elseif string.match(path, "/Header/Label$") then
				label = node
			elseif string.match(path, "/Tree/G$") then
				group = node
			elseif string.match(path, "/Row$") then
				row = node
			end
		end
		local headerNode = w.adapter.node(header)
		expect(headerNode.props.surface).toBe("plain")
		expect(headerNode.props.selected).toBeNil()
		expect(table.find(w.adapter.tagsOf(header), "facet-selected")).toBeNil()
		expect(label.props.textSize).toBe(14) -- the label role at Neutral
		expect(row.rect.x - group.rect.x).toBe(16) -- space.m at Neutral
	end)
end)
