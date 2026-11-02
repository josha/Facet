--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(harness: Verify.Harness)
	type FacetModule = typeof(require("@repo/tools/typecheck/aliases").FacetModule)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local hud = require("../examples/blocks/hud_panel")
	local store = require("../examples/blocks/item_store")
	local categories = require("../examples/blocks/category_tabs")
	local settings = require("../examples/blocks/settings_panel")
	local redeem = require("../examples/blocks/code_redeem")
	local inventory = require("../examples/blocks/inventory_grid")
	local scoreboard = require("../examples/blocks/scoreboard_table")
	local roundHud = require("../examples/blocks/round_hud")
	local dialogue = require("../examples/blocks/dialogue_box")
	local Compose = Facet.Compose

	type StoreItem = {
		id: string,
		name: string,
		description: string,
		image: string,
		price: number,
		currency: "Coins" | "Gems",
		owned: boolean,
	}

	local function bootsFor(price: number): { StoreItem }
		return {
			{
				id = "boots",
				name = "Boots",
				description = "Move faster",
				image = "rbxassetid://1",
				price = price,
				currency = "Coins",
				owned = false,
			},
		}
	end

	local function mount(t: Verify.Context, component: (FacetModule, FacetControls) -> Instance)
		local engine = engineLib.new()
		local parent = engine.new("Folder")
		local runtime = Facet.Roblox.createRuntime(engine)
		local app = Facet.app({ runtime = runtime, types = engine.types, parent = parent, motionLevel = "none" })
		t:defer(function()
			app.dispose()
			runtime:dispose()
		end)
		app.mount(function()
			return component(Facet, app.UI)
		end)
		for _, node in parent:GetDescendants() do
			if node:IsA("ScrollingFrame") then
				engine.environment.poke(node, "AbsoluteWindowSize", engine.types.Vector2.new(1280, 500))
			end
		end
		engine.heartbeat:Fire(1 / 60)
		return parent, engine
	end

	local function find(root: Instance, name: string): Instance
		return assert(root:FindFirstChild(name, true), `Missing {name}`)
	end

	local function activate(node: Instance)
		local button = (node :: unknown) :: { Activated: { Fire: (unknown) -> () } }
		button.Activated:Fire()
	end

	local function text(root: Instance, name: string): string
		return (find(root, name) :: TextLabel).Text
	end

	harness:suite("starter blocks", function()
		harness:case("opens and closes the HUD task sheet", function(t)
			local tracked = 0
			local parent, engine = mount(t, function(F, UI)
				return hud(F, UI, {
					objective = Compose.cell("Find the camp"),
					trackObjective = function()
						tracked += 1
					end,
				})
			end)
			activate(find(parent, "OpenTasks"))
			for _ = 1, 30 do
				engine.heartbeat:Fire(1 / 60)
			end
			t:expect(text(parent, "Objective")):toBe("Find the camp")
			activate(find(parent, "Track"))
			t:expect(tracked):toBe(1)
			activate(find(parent, "Close"))
			for _ = 1, 30 do
				engine.heartbeat:Fire(1 / 60)
			end
			t:expect(parent:FindFirstChild("SheetPanel", true)):toBe(nil)
		end)

		harness:case("purchases by id and shows the returned failure or success toast", function(t)
			local requested = ""
			local ok = false
			local reason = "Not enough Coins"
			local parent = mount(t, function(F, UI)
				return store(F, UI, {
					coins = Compose.cell(0),
					gems = Compose.cell(0),
					confirmationThreshold = 100,
					items = Compose.cell(bootsFor(10)),
					purchase = function(id)
						requested = id
						return { ok = ok, reason = if ok then nil else reason }
					end,
				})
			end)
			activate(find(parent, "Primary"))
			t:expect(requested):toBe("boots")
			t:expect(text(parent, "Result")):toBe("Not enough Coins")
			reason = "Not enough Gems"
			activate(find(parent, "Primary"))
			t:expect(text(parent, "Result")):toBe("Not enough Gems")
			ok = true
			activate(find(parent, "Primary"))
			t:expect(text(parent, "Result")):toBe("Purchased Boots")
			t:expect(find(parent, "PurchaseToast"):GetAttribute("ToastVisible")):toBe(true)
		end)

		harness:case("confirms a purchase above the threshold", function(t)
			local calls = 0
			local parent = mount(t, function(F, UI)
				return store(F, UI, {
					coins = Compose.cell(500),
					gems = Compose.cell(0),
					confirmationThreshold = 100,
					items = Compose.cell(bootsFor(200)),
					purchase = function()
						calls += 1
						return { ok = true }
					end,
				})
			end)
			activate(find(parent, "Primary"))
			t:expect(calls):toBe(0)
			activate(find(parent, "buy"))
			t:expect(calls):toBe(1)
		end)

		harness:case("filters one collection with category tabs", function(t)
			local parent = mount(t, function(F, UI)
				return categories(F, UI, {
					items = Compose.cell({
						{ id = "hat", name = "Hat", category = "outfits" },
						{ id = "axe", name = "Axe", category = "tools" },
					}),
				})
			end)
			activate(find(parent, "tools"))
			local names = {}
			for _, node in parent:GetDescendants() do
				if node.Name == "ItemName" then
					table.insert(names, (node :: TextLabel).Text)
				end
			end
			t:expect(names):toEqual({ "Axe" })
		end)

		harness:case("resets settings through the model", function(t)
			local music, volume, quality = Compose.cell(false), Compose.cell(12), Compose.cell("low")
			local parent = mount(t, function(F, UI)
				return settings(F, UI, {
					music = music,
					volume = volume,
					quality = quality,
					reset = function()
						music:set(true)
						volume:set(75)
						quality:set("high")
					end,
				})
			end)
			activate(find(parent, "Reset"))
			t:expect(music:peek()):toBe(true)
			t:expect(volume:peek()):toBe(75)
			t:expect(quality:peek()):toBe("high")
		end)

		harness:case("disables empty and busy redemption and shows rewards", function(t)
			local requested = ""
			local request: thread? = nil
			local parent = mount(t, function(F, UI)
				return redeem(F, UI, {
					redeem = function(code)
						requested = code
						request = coroutine.running()
						coroutine.yield()
						return { ok = true, rewards = { "10 Coins", "Hat" } }
					end,
				})
			end)
			local button = find(parent, "Redeem") :: TextButton
			activate(button)
			t:expect(requested):toBe("")
			t:expect(button.Interactable):toBe(false)
			local field = find(parent, "Field") :: TextBox
			field:CaptureFocus()
			field.Text = "GIFT"
			activate(button)
			t:expect(requested):toBe("GIFT")
			t:expect(button.Interactable):toBe(false)
			t:expect(coroutine.resume(assert(request))):toBe(true)
			t:expect(text(parent, "Result")):toBe("Received: 10 Coins, Hat")
			t:expect(button.Interactable):toBe(true)
		end)

		harness:case("selects an inventory item and equips its slot through the model", function(t)
			local equipped = Compose.cell({} :: { [string]: string })
			local requested = ""
			local parent = mount(t, function(F, UI)
				return inventory(F, UI, {
					items = Compose.cell({ { id = "hat", name = "Hat", description = "A warm hat", slot = "head" } }),
					equipped = equipped,
					equip = function(id, slot)
						requested = id .. ":" .. slot
						equipped:set({ [slot] = id })
					end,
				})
			end)
			activate(find(parent, "RowHit"))
			t:expect(text(parent, "Description")):toBe("A warm hat")
			activate(find(parent, "Equip"))
			t:expect(requested):toBe("hat:head")
			t:expect(text(parent, "Equip")):toBe("Equipped")
		end)

		harness:case("sorts scoreboard rows by score and marks the local player", function(t)
			local parent = mount(t, function(F, UI)
				return scoreboard(F, UI, {
					localPlayerId = "me",
					players = Compose.cell({
						{ id = "me", name = "Local", kills = 1, deaths = 3, score = 10 },
						{ id = "other", name = "Leader", kills = 4, deaths = 0, score = 40 },
					}),
				})
			end)
			local rows: { Frame } = {}
			for _, node in parent:GetDescendants() do
				if node:IsA("Frame") and node.Name == "Row" and node:FindFirstChild("score") then
					table.insert(rows, node)
				end
			end
			table.sort(rows, function(a: Frame, b: Frame)
				return a.AbsolutePosition.Y < b.AbsolutePosition.Y
			end)
			t:expect(#rows):toBe(2)
			t:expect(text(find(rows[1], "score"), "Value")):toBe("40")
			t:expect(text(find(rows[2], "name"), "Value")):toBe("Local (You)")
		end)

		harness:case("shows the round clock and compact counters", function(t)
			local coins = Compose.cell(93210)
			local parent = mount(t, function(F, UI)
				return roundHud(F, UI, {
					phase = Compose.cell("Round"),
					deadline = Compose.cell(77),
					now = function()
						return 0
					end,
					coins = coins,
					gems = Compose.cell(387153),
				})
			end)
			t:expect(text(parent, "PhaseName")):toBe("Round")
			t:expect(text(parent, "Clock")):toBe("1:17")
			t:expect(text(parent, "Coins")):toBe("93.2K Coins")
			t:expect(text(parent, "Gems")):toBe("387,153 Gems")
			coins:set(2350)
			t:expect(text(parent, "Coins")):toBe("2.35K Coins")
		end)

		harness:case("shows a dialogue line and sends the chosen reply", function(t)
			local chosen = ""
			local line = Compose.cell({
				speaker = "Guide",
				text = "Follow the lights.",
				replies = { { id = "ask", label = "Where?" }, { id = "bye", label = "Goodbye" } },
			})
			local parent = mount(t, function(F, UI)
				return dialogue(F, UI, {
					line = line,
					choose = function(id: string)
						chosen = id
					end,
				})
			end)
			t:expect(text(parent, "Speaker")):toBe("Guide")
			t:expect(parent:FindFirstChild("Skip", true)):toBe(nil)
			local replies = {}
			for _, node in parent:GetDescendants() do
				if node.Name == "Reply" then
					table.insert(replies, node)
				end
			end
			t:expect(#replies):toBe(2)
			activate(replies[1])
			t:expect(chosen == "ask" or chosen == "bye"):toBe(true)
		end)
	end)
end
