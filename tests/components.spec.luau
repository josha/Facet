--!strict
-- Components are plain functions that return nodes. Setup runs once per mount;
-- state is Compose cells, and the mount's owner releases everything it created.
local t = require("./lib/testkit")
local world = require("./lib/world")

t.describe("component authoring", function()
	t.it("mounts once, updates only bindings, and owns cleanup", function()
		local w = world.new()
		local UI, Compose = w.UI, w.Compose
		local before = w.core.owner.size()
		local setups, cleaned = 0, 0
		local count = Compose.cell(0)
		local function Counter()
			setups += 1
			Compose.cleanup(function()
				cleaned += 1
			end)
			return UI.Text("Count")({
				text = function(use)
					return `Count {use(count)}`
				end,
			})
		end
		w.present(function()
			return UI.Screen("S")({ Counter() })
		end)
		local node = w.adapter.node("/S/Count")
		t.expect(node.props.text).toBe("Count 0")
		count:set(2)
		w.settle()
		t.expect(w.adapter.node("/S/Count")).toBe(node)
		t.expect(node.props.text).toBe("Count 2")
		t.expect(setups).toBe(1)
		w.close()
		w.settle(60)
		t.expect(cleaned).toBe(1)
		t.expect(w.adapter.rootCount()).toBe(0)
		t.expect(w.core.owner.size()).toBe(before)
		t.expect(w.core.owner.size()).toBe(before)
	end)

	t.it("a watch runs initially, reruns on change, and stops at unmount", function()
		local w = world.new()
		local UI, Compose = w.UI, w.Compose
		local source = Compose.cell("a")
		local seen: { string } = {}
		w.present(function()
			Compose.watch(function(use)
				table.insert(seen, use(source))
			end)
			return UI.Screen("S")({ UI.Text("Label")({ text = "Label" }) })
		end)
		source:set("b")
		w.settle()
		t.expect(table.concat(seen, ",")).toBe("a,b")
		w.close()
		w.settle(60)
		source:set("c")
		w.settle()
		t.expect(table.concat(seen, ",")).toBe("a,b")
	end)

	t.it("a formula is shared by every property that reads it", function()
		local w = world.new()
		local UI, Compose = w.UI, w.Compose
		local balance, runs = Compose.cell(5), 0
		w.present(function()
			local canBuy = Compose.formula(function(use)
				runs += 1
				return use(balance) >= 10
			end)
			return UI.Screen("S")({
				UI.Button("Buy")({ label = "Buy", enabled = canBuy, onActivate = function() end }),
				UI.Button("Gift")({ label = "Gift", enabled = canBuy, onActivate = function() end }),
			})
		end)
		t.expect(w.adapter.node("/S/Buy").props.enabled).toBe(false)
		local initial = runs
		balance:set(20)
		w.settle()
		t.expect(runs).toBe(initial + 1)
		t.expect(w.adapter.node("/S/Buy").props.enabled).toBe(true)
		t.expect(w.adapter.node("/S/Gift").props.enabled).toBe(true)
	end)

	t.it("releases a partially constructed component after a setup error", function()
		local w = world.new()
		local UI, Compose = w.UI, w.Compose
		local released = 0
		local ok = pcall(w.present, function()
			Compose.cleanup(function()
				released += 1
			end)
			UI.Text("Kept")({ text = "Kept" })
			error("setup failed")
		end)
		t.expect(ok).toBe(false)
		t.expect(released).toBe(1)
		t.expect(w.adapter.rootCount()).toBe(0)
		t.expect(w.pres.depth()).toBe(0)
	end)

	t.it("applies layout modifiers to the component's root node", function()
		local w = world.new()
		local UI = w.UI
		local function Card()
			return UI.VStack("Card")({ UI.Text("Title")({ text = "Card" }) })
		end
		w.present(function()
			return UI.Screen("S")({ UI.frame(UI.padding(Card(), 8), { width = 200 }) })
		end)
		local card = w.adapter.node("/S/Card")
		t.expect(card.rect.w).toBe(200)
		t.expect(w.adapter.node("/S/Card/Title").rect.x - card.rect.x).toBe(8)
		-- the mounted node carries every authored property
		t.expect(w.node.children[1].props.padding).toBe(8)
	end)
end)

t.describe("branches and keyed collections", function()
	t.it("show builds its branch on demand and releases it when the condition clears", function()
		local w = world.new()
		local UI, Compose = w.UI, w.Compose
		local expanded, live = Compose.cell(false), 0
		w.present(function()
			return UI.Screen("S")({
				UI.VStack("Body")({
					UI.Text("Title")({ text = "Title" }),
					Compose.show(expanded, function()
						live += 1
						Compose.cleanup(function()
							live -= 1
						end)
						return UI.Text("Details")({ text = "Details" })
					end),
				}),
			})
		end)
		t.expect(w.adapter.node("/S/Body/Details")).toBeNil()
		expanded:set(true)
		w.settle()
		t.expect(w.adapter.node("/S/Body/Details") ~= nil).toBe(true)
		t.expect(live).toBe(1)
		expanded:set(false)
		w.settle()
		t.expect(w.adapter.node("/S/Body/Details")).toBeNil()
		t.expect(live).toBe(0)
	end)

	t.it("keyed rows keep their identity and hand handlers the latest item", function()
		local w = world.new()
		local UI, Compose = w.UI, w.Compose
		local items = Compose.cell({ { id = "a", name = "Axe" }, { id = "b", name = "Bow" } })
		local built, equipped = 0, nil
		w.present(function()
			return UI.Screen("S")({
				UI.VStack("List")({
					Compose.keyed({
						from = items,
						key = function(item)
							return item.id
						end,
						render = function(item)
							built += 1
							return UI.Button("Row-" .. item:peek().id)({
								label = function(use)
									return use(item).name
								end,
								onActivate = function()
									equipped = item:peek().name
								end,
							})
						end,
					}),
				}),
			})
		end)
		local row = w.adapter.node("/S/List/Row-a")
		items:set({ { id = "b", name = "Bow" }, { id = "a", name = "Great Axe" }, { id = "c", name = "Club" } })
		w.settle()
		t.expect(built).toBe(3)
		t.expect(w.adapter.node("/S/List/Row-a")).toBe(row)
		t.expect(row.props.label).toBe("Great Axe")
		w.adapter.tap("/S/List/Row-a")
		w.settle()
		t.expect(equipped).toBe("Great Axe")
		items:set({ { id = "c", name = "Club" } })
		w.settle()
		t.expect(w.adapter.node("/S/List/Row-a")).toBeNil()
	end)
end)

--[[ LIFETIME UNDER A COMPOSE OWNER (restored coverage, 2026-09-20).

	`Facet.component` is gone; a component is a plain function and the owner that
	was active while it ran is what holds everything it created. THE THREE CLAIMS
	THAT WRAPPER USED TO CARRY ARE STILL CLAIMS, so they are still asserted here —
	only the spelling moved:

	  · a cleanup that THROWS is contained, and every other cleanup of the same
	    owner still runs (the wrapper's "a failing effect cleanup does not
	    disconnect later updates");
	  · a watch created inside a component stops when THAT component unmounts, not
	    when the surface closes (the wrapper's "stopping a watcher releases its
	    private bindings before unmount"), and stopping it by hand is idempotent;
	  · a REMOUNT builds fresh state — nothing survives the owner that held it.

	Every case releases its branch and reads `core.owner.size()` back to the
	baseline it took, because "the cleanup ran" and "the owner let go" are two
	different facts and only the second one rules out a leak. ]]
t.describe("component lifetime under Compose owners", function()
	t.it("a cleanup that THROWS is contained, and every other cleanup still releases", function()
		local w = world.new()
		local UI, Compose = w.UI, w.Compose
		local shown = Compose.cell(true)
		local released: { string } = {}
		local before = w.core.owner.size()
		w.present(function()
			return UI.Screen("S")({
				UI.VStack("Body")({
					Compose.show(shown, function()
						-- three cleanups on ONE owner; the middle one is the hazard
						Compose.cleanup(function()
							table.insert(released, "first")
						end)
						Compose.cleanup(function()
							error("bad cleanup")
						end)
						Compose.cleanup(function()
							table.insert(released, "third")
						end)
						return UI.Text("Details")({ text = "Details" })
					end),
				}),
			})
		end)
		t.expect(w.adapter.node("/S/Body/Details") ~= nil).toBe(true)
		shown:set(false)
		w.settle()
		-- the throw did not take the siblings with it, in EITHER direction: the
		-- cleanup registered before it and the one registered after it both ran
		table.sort(released)
		t.expect(table.concat(released, ",")).toBe("first,third")
		-- ...and the branch is gone, which is the half "the cleanup ran" cannot say
		t.expect(w.adapter.node("/S/Body/Details")).toBeNil()
		w.close()
		w.settle(60)
		t.expect(w.core.owner.size()).toBe(before)
	end)

	t.it("a watch created in a component stops when THAT component unmounts", function()
		local w = world.new()
		local UI, Compose = w.UI, w.Compose
		local shown, source = Compose.cell(true), Compose.cell("a")
		local seen: { string } = {}
		w.present(function()
			return UI.Screen("S")({
				UI.VStack("Body")({
					Compose.show(shown, function()
						Compose.watch(function(use)
							table.insert(seen, use(source))
						end)
						return UI.Text("Details")({ text = "Details" })
					end),
				}),
			})
		end)
		source:set("b")
		w.settle()
		t.expect(table.concat(seen, ",")).toBe("a,b")
		-- the SURFACE is still open; only the component went away
		shown:set(false)
		w.settle()
		source:set("c")
		w.settle()
		t.expect(table.concat(seen, ",")).toBe("a,b")
		t.expect(w.adapter.node("/S/Body") ~= nil).toBe(true)
	end)

	t.it("a watch stopped by hand releases before unmount, and stopping twice is safe", function()
		local w = world.new()
		local UI, Compose = w.UI, w.Compose
		local source = Compose.cell(0)
		local calls, stop = 0, nil :: any
		w.present(function()
			stop = Compose.watch(function(use)
				use(source)
				calls += 1
			end)
			return UI.Screen("S")({ UI.Text("Label")({ text = "Label" }) })
		end)
		source:set(1)
		w.settle()
		t.expect(calls).toBe(2)
		stop()
		stop() -- DOUBLE DISPOSE IS SAFE: the second call is a no-op, not a throw
		source:set(2)
		w.settle()
		t.expect(calls).toBe(2)
		-- ...and the surface still closes cleanly over a watch that is already gone
		w.close()
		w.settle(60)
		t.expect(w.adapter.rootCount()).toBe(0)
	end)

	t.it("a REMOUNT builds fresh state: nothing survives the owner that held it", function()
		local w = world.new()
		local UI, Compose = w.UI, w.Compose
		local shown = Compose.cell(true)
		local setups = 0
		local function Counter()
			setups += 1
			local count = Compose.cell(0)
			-- the handler writes THIS mount's cell; a remount must not see it
			return UI.Button("Bump")({
				label = function(use)
					return `n {use(count)}`
				end,
				onActivate = function()
					count:set(count:peek() + 1)
				end,
			})
		end
		w.present(function()
			return UI.Screen("S")({ UI.VStack("Body")({ Compose.show(shown, Counter) }) })
		end)
		t.expect(w.adapter.node("/S/Body/Bump").props.label).toBe("n 0")
		w.adapter.tap("/S/Body/Bump")
		w.settle()
		t.expect(w.adapter.node("/S/Body/Bump").props.label).toBe("n 1")
		shown:set(false)
		w.settle()
		t.expect(w.adapter.node("/S/Body/Bump")).toBeNil()
		shown:set(true)
		w.settle()
		t.expect(setups).toBe(2)
		t.expect(w.adapter.node("/S/Body/Bump").props.label).toBe("n 0")
	end)
end)
