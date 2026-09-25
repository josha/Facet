--!strict
local t = require("./lib/testkit")
local Compose = require("../src/vendor/compose/core")
local overlay = require("./lib/overlay_world")
local placement = require("../src/ui/overlay_placement")
local Vector2 = require("@lune/roblox").Vector2

local TIP = "Post Avatars to Marketplace"

local function tip(Host: any): () -> any
	return function()
		return Host.TextLabel "Body" { Text = TIP }
	end
end

local function mount(specOf: (any, any) -> { [string]: any }, options: any?): any
	return overlay.new(function(UI, Host)
		local anchor = UI.Button "Plus" { label = "+" }
		local spec = specOf(UI, Host)
		spec.anchor = anchor
		if spec.onRetire == nil then
			spec.onRetire = function() end
		end
		return Host.Frame({ Name = "Editor", Host.Frame({ Name = "Bar", anchor }), UI.Callout "Callout"(spec) })
	end, options)
end

local function buttons(root: any): { string }
	local out = {}
	for _, node in root:GetDescendants() do
		if node:IsA("TextButton") and node.Name ~= "DismissOutside" then
			table.insert(out, `{node.Parent.Name}/{node.Name}`)
		end
	end
	table.sort(out)
	return out
end

t.describe("native Callout: bound facts are read as tracked values", function()
	t.it("a function isPresented is evaluated and followed, not treated as a request", function()
		local wanted = Compose.cell(false)
		local w = mount(function(_, Host)
			return {
				content = tip(Host),
				isPresented = function(use: any)
					return use(wanted)
				end,
			}
		end)
		t.expect(w.find("CalloutPanel")).toBeNil()
		wanted:set(true)
		t.expect(w.find("CalloutPanel") ~= nil).toBe(true)
		wanted:set(false)
		t.expect(w.find("CalloutPanel")).toBeNil()
		w.stop()
	end)

	t.it("a function seen or featureUsed rules the callout out, and a later true retires it once", function()
		local seen = Compose.cell(true)
		local early: { string } = {}
		local w = mount(function(_, Host)
			return {
				content = tip(Host),
				seen = function(use: any)
					return use(seen)
				end,
				onRetire = function(reason: string)
					table.insert(early, reason)
				end,
			}
		end)
		t.expect(w.find("CalloutPanel")).toBeNil()
		t.expect(table.concat(early, ",")).toBe("seen")
		w.stop()
		local used = Compose.cell(false)
		local reports: { string } = {}
		local live = mount(function(_, Host)
			return {
				content = tip(Host),
				featureUsed = function(use: any)
					return use(used)
				end,
				onRetire = function(reason: string)
					table.insert(reports, reason)
				end,
			}
		end)
		t.expect(live.find("CalloutPanel") ~= nil).toBe(true)
		used:set(true)
		used:set(false)
		used:set(true)
		t.expect(live.find("CalloutPanel")).toBeNil()
		t.expect(table.concat(reports, ",")).toBe("featureUsed")
		live.stop()
	end)
end)

t.describe("native Callout: callbacks during a show never strand or double-close a plate", function()
	local function pair(onShow: (any) -> ()): (any, { string }, any)
		local reports: { string } = {}
		local used = Compose.cell(false)
		local gate = Compose.cell(true)
		local w = overlay.new(function(UI, Host)
			local first = UI.Button "Plus" { label = "+" }
			local second = UI.Button "Share" { label = "Share" }
			return Host.Frame({
				Name = "Editor",
				Host.Frame({ Name = "Bar", first, second }),
				Compose.show(gate, function()
					return UI.Callout "First" {
						anchor = first,
						priority = 2,
						content = tip(Host),
						featureUsed = used,
						onShow = function()
							onShow({ used = used, gate = gate })
						end,
						onRetire = function(reason: string)
							table.insert(reports, reason)
						end,
					}
				end),
				UI.Callout "Second" {
					anchor = second,
					priority = 1,
					content = function()
						return Host.TextLabel "SecondBody" { Text = "Share it" }
					end,
					onRetire = function() end,
				},
			})
		end, { reducedMotion = true })
		return w, reports, gate
	end

	t.it("a retirement inside onShow retires once and takes the plate down", function()
		local w, reports = pair(function(state)
			state.used:set(true)
		end)
		t.expect(table.concat(reports, ",")).toBe("featureUsed")
		t.expect(w.find("Body")).toBeNil()
		t.expect(w.find("SecondBody") ~= nil).toBe(true)
		t.expect(#w.findAll("CalloutPanel")).toBe(1)
		w.stop()
	end)

	t.it("disposal inside onShow releases the queue slot", function()
		local w = pair(function(state)
			state.gate:set(false)
		end)
		t.expect(w.find("Body")).toBeNil()
		t.expect(w.find("SecondBody") ~= nil).toBe(true)
		t.expect(#w.findAll("CalloutPanel")).toBe(1)
		w.stop()
	end)

	t.it("an ordinary throw in onShow still shows the plate and keeps the slot accounting", function()
		local failures: { string } = {}
		local reports: { string } = {}
		local w = overlay.new(function(UI, Host)
			local first = UI.Button "Plus" { label = "+" }
			local second = UI.Button "Share" { label = "Share" }
			return Host.Frame({
				Name = "Editor",
				Host.Frame({ Name = "Bar", first, second }),
				UI.Callout "First" {
					anchor = first,
					priority = 2,
					content = tip(Host),
					onShow = function()
						error("caller bug")
					end,
					onRetire = function(reason: string)
						table.insert(reports, reason)
					end,
				},
				UI.Callout "Second" {
					anchor = second,
					priority = 1,
					content = function()
						return Host.TextLabel "SecondBody" { Text = "Share it" }
					end,
					onRetire = function() end,
				},
			})
		end, {
			onError = function(failure: unknown)
				table.insert(failures, tostring(failure))
			end,
		})
		t.expect(w.find("Body") ~= nil).toBe(true)
		t.expect(w.find("SecondBody")).toBeNil()
		t.expect(#failures).toBe(1)
		t.expect(string.find(failures[1], "caller bug", 1, true) ~= nil).toBe(true)
		w.find("Dismiss").Activated.fire()
		t.expect(table.concat(reports, ",")).toBe("dismissed")
		t.expect(w.find("Body")).toBeNil()
		t.expect(w.find("SecondBody") ~= nil).toBe(true)
		w.stop()
	end)
end)

t.describe("native Callout: two worlds and a recycled source keep their own resources", function()
	t.it("disposing one world's callout never touches another world's", function()
		local gate = Compose.cell(true)
		local a = overlay.new(function(UI, Host)
			local anchor = UI.Button "Plus" { label = "+" }
			return Host.Frame({
				Host.Frame({ anchor }),
				Compose.show(gate, function()
					return UI.Callout "Callout" { anchor = anchor, content = tip(Host), onRetire = function() end }
				end),
			})
		end)
		local b = mount(function(_, Host)
			return { content = tip(Host) }
		end)
		t.expect(a.find("CalloutPanel") ~= nil and b.find("CalloutPanel") ~= nil).toBe(true)
		gate:set(false)
		t.expect(a.find("CalloutPanel")).toBeNil()
		t.expect(b.find("CalloutPanel") ~= nil).toBe(true)
		a.stop()
		b.stop()
	end)

	t.it("a callout rebuilt by a branch cycle is a new control with one plate", function()
		local gate, built = Compose.cell(true), 0
		local w = overlay.new(function(UI, Host)
			local anchor = UI.Button "Plus" { label = "+" }
			return Host.Frame({
				Host.Frame({ anchor }),
				Compose.show(gate, function()
					built += 1
					return UI.Callout "Callout" { anchor = anchor, content = tip(Host), onRetire = function() end }
				end),
			})
		end)
		t.expect(#w.findAll("CalloutPanel")).toBe(1)
		gate:set(false)
		t.expect(#w.findAll("CalloutPanel")).toBe(0)
		gate:set(true)
		t.expect(built).toBe(2)
		t.expect(#w.findAll("CalloutPanel")).toBe(1)
		w.stop()
	end)
end)

t.describe("native Callout: rich parts", function()
	t.it("the full composition paints every part, and one or two actions replace the bottom dismiss", function()
		local pressed, reports = {}, {}
		local w = mount(function(_, Host)
			return {
				content = tip(Host),
				title = "Try the editor",
				media = { image = "rbxassetid://1", aspectRatio = 2 },
				steps = { index = 2, count = 3 },
				closeButton = true,
				actions = {
					{
						id = "Later",
						label = "Later",
						onActivate = function()
							table.insert(pressed, "Later")
						end,
					},
					{
						id = "Go",
						label = "Show me",
						role = "default",
						onActivate = function()
							table.insert(pressed, "Go")
						end,
					},
				},
				onRetire = function(reason: string)
					table.insert(reports, reason)
				end,
			}
		end)
		local panel = w.find("CalloutPanel")
		t.expect(overlay.find(panel, "Title").Text).toBe("Try the editor")
		local media = overlay.find(panel, "Media")
		t.expect(media.Size.X.Scale).toBe(1)
		media.AbsoluteSize = Vector2.new(260, 0)
		t.expect(media.Size.Y.Offset).toBe(130)
		t.expect(overlay.find(panel, "Steps").Text).toBe("2 of 3")
		t.expect(overlay.find(panel, "Body").Text).toBe(TIP)
		t.expect(table.concat(buttons(panel), ",")).toBe("Actions/Go,Actions/Later,Header/Close")
		t.expect(overlay.find(panel, "Dismiss")).toBeNil()
		overlay.find(panel, "Go").Activated.fire()
		t.expect(table.concat(pressed, ",")).toBe("Go")
		t.expect(table.concat(reports, ",")).toBe("action")
		t.expect(w.find("CalloutPanel")).toBeNil()
		w.stop()
	end)

	t.it("an action retires its own generation once, and never a newer one it presented", function()
		local generation, reports = Compose.cell(1), {}
		local w = overlay.new(function(UI, Host)
			local anchor = UI.Button "Plus" { label = "+" }
			return Host.Frame({
				Host.Frame({ anchor }),
				Compose.keyed({
					from = function(use: any)
						return { use(generation) }
					end,
					render = function()
						return UI.Callout "Callout" {
							anchor = anchor,
							content = tip(Host),
							actions = {
								{
									id = "Again",
									label = "Again",
									onActivate = function()
										generation:set(generation:peek() + 1)
										error("caller bug after rearm")
									end,
								},
							},
							onRetire = function(reason: string)
								table.insert(reports, reason)
							end,
						}
					end,
				}),
			})
		end)
		local first = w.find("CalloutPanel")
		local ok = pcall(overlay.find(first, "Again").Activated.fire)
		t.expect(ok).toBe(false)
		t.expect(generation:peek()).toBe(2)
		local panels = w.findAll("CalloutPanel")
		t.expect(#panels).toBe(1)
		t.expect(panels[1] ~= first).toBe(true)
		t.expect(overlay.find(panels[1], "Body") ~= nil).toBe(true)
		t.expect(#reports).toBe(0)
		w.stop()
	end)

	t.it("a throwing action still retires the presentation it belonged to, exactly once", function()
		local reports = {}
		local w = mount(function(_, Host)
			return {
				content = tip(Host),
				actions = {
					{
						id = "Boom",
						label = "Boom",
						onActivate = function()
							error("caller bug")
						end,
					},
				},
				onRetire = function(reason: string)
					table.insert(reports, reason)
				end,
			}
		end)
		local boom = overlay.find(w.find("CalloutPanel"), "Boom")
		w.gui.SelectedObject = boom
		t.expect((pcall(w.action("Activate").Pressed.fire))).toBe(false)
		t.expect(table.concat(reports, ",")).toBe("action")
		t.expect(w.find("CalloutPanel")).toBeNil()
		w.stop()
	end)

	t.it("a disabled action cannot fire", function()
		local fired = false
		local w = mount(function(_, Host)
			return {
				content = tip(Host),
				actions = {
					{
						id = "Nope",
						label = "Nope",
						enabled = false,
						onActivate = function()
							fired = true
						end,
					},
				},
			}
		end)
		local nope = overlay.find(w.find("CalloutPanel"), "Nope")
		t.expect(nope.Interactable).toBe(false)
		nope.Activated.fire()
		t.expect(fired).toBe(false)
		t.expect(w.find("CalloutPanel") ~= nil).toBe(true)
		w.stop()
	end)

	t.it("closeButton adds a top close and keeps the legacy bottom dismiss when there are no actions", function()
		local reports = {}
		local w = mount(function(_, Host)
			return {
				content = tip(Host),
				closeButton = true,
				onRetire = function(reason: string)
					table.insert(reports, reason)
				end,
			}
		end)
		local panel = w.find("CalloutPanel")
		t.expect(table.concat(buttons(panel), ",")).toBe("CalloutContent/Dismiss,Header/Close")
		local close = overlay.find(panel, "Close")
		t.expect(close.Size.X.Offset >= 44 and close.Size.Y.Offset >= 44).toBe(true)
		close.Activated.fire()
		t.expect(table.concat(reports, ",")).toBe("dismissed")
		t.expect(w.find("CalloutPanel")).toBeNil()
		w.stop()
	end)

	t.it("the legacy content-only plate is unchanged: content then the dismiss button, nothing else", function()
		local w = mount(function(_, Host)
			return { content = tip(Host) }
		end)
		local panel = w.find("CalloutPanel")
		t.expect(table.concat(buttons(panel), ",")).toBe("CalloutContent/Dismiss")
		t.expect(overlay.find(panel, "Header")).toBeNil()
		t.expect(overlay.find(panel, "Media")).toBeNil()
		t.expect(overlay.find(panel, "Steps")).toBeNil()
		t.expect(overlay.find(panel, "Body").LayoutOrder < overlay.find(panel, "Dismiss").LayoutOrder).toBe(true)
		w.stop()
	end)

	t.it("title-only, media-only, steps-only and actions-only compositions need no content", function()
		for index, spec in
			{
				{ title = "Title only" } :: { [string]: any },
				{ media = { image = "rbxassetid://1", height = 80 } },
				{ steps = { index = 1, count = 2 } },
				{ actions = { { id = "Ok", label = "Ok", onActivate = function() end } } },
			}
		do
			local w = mount(function()
				return table.clone(spec)
			end)
			t.expect(`case {index}: {w.find("CalloutPanel") ~= nil}`).toBe(`case {index}: true`)
			w.stop()
		end
	end)

	t.it("an empty composition and malformed parts are refused by name", function()
		local print = function() end
		for index, bad in
			{
				{} :: { [string]: any },
				{ closeButton = true },
				{ media = { image = "x", aspectRatio = 1, height = 20 } },
				{ media = { image = "x" } },
				{ media = { image = "x", aspectRatio = -1 } },
				{ media = { image = "x", height = 10, scaleMode = "tile" } },
				{ media = { image = "x", height = 10, extra = 1 } },
				{ steps = { index = 0, count = 2 } },
				{ steps = { index = 3, count = 2 } },
				{ steps = { index = 1.5, count = 2 } },
				{
					actions = {
						{ id = "A", label = "A", onActivate = print },
						{ id = "B", label = "B", onActivate = print },
						{ id = "C", label = "C", onActivate = print },
					},
				},
				{
					actions = {
						{ id = "A", label = "A", onActivate = print },
						{ id = "A", label = "B", onActivate = print },
					},
				},
				{ actions = { { id = "A", label = "A" } } },
				{ actions = { { id = "A", label = "A", onActivate = print, role = "primary" } } },
				{ closeButton = "yes", title = "T" },
				{ title = 4 },
			}
		do
			local ok = pcall(function()
				mount(function()
					return table.clone(bad)
				end).stop()
			end)
			t.expect(`case {index}: {ok}`).toBe(`case {index}: false`)
		end
	end)
end)

t.describe("native help: the structured form and the live plate", function()
	local function helped(value: any): any
		local w = overlay.new(function(UI, Host)
			return Host.Frame({ Name = "Screen", UI.Button "Post" { label = "Post", help = value } })
		end, { reducedMotion = true })
		local post = w.find("Post")
		post.AbsolutePosition = Vector2.new(300, 200)
		post.AbsoluteSize = Vector2.new(80, 44)
		w.input.PreferredInput = w.Enum.PreferredInput.Gamepad
		w.gui.SelectedObject = post
		w.advance(0.5)
		return w
	end

	t.it("a title, a body and a display-only shortcut paint in one plate", function()
		local before = overlay.new(function(UI, Host)
			return Host.Frame({ Name = "Screen", UI.Button "Post" { label = "Post", help = "Posts it" } })
		end)
		local post = before.find("Post")
		before.input.PreferredInput = before.Enum.PreferredInput.Gamepad
		before.gui.SelectedObject = post
		before.advance(0.5)
		local contexts = 0
		for _, node in before.screen:GetDescendants() do
			if node:IsA("InputContext") then
				contexts += 1
			end
		end
		before.stop()
		local w = helped({ title = "Post", body = "Posts this avatar", shortcut = { { "Ctrl", "P" }, { "F2" } } })
		t.expect(w.find("HelpTitle").Text).toBe("Post")
		t.expect(w.find("HelpText").Text).toBe("Posts this avatar")
		t.expect(w.find("HelpShortcut").Text).toBe("Ctrl+P or F2")
		local after = 0
		for _, node in w.screen:GetDescendants() do
			if node:IsA("InputContext") then
				after += 1
			end
		end
		t.expect(after).toBe(contexts)
		w.stop()
	end)

	t.it("edge and align place the plate", function()
		local w = helped({ body = "Posts it", edge = "trailing", align = "end" })
		local panel = w.find("Help")
		panel.AbsoluteSize = Vector2.new(120, 30)
		local expected = placement.solve({
			source = { x = 300, y = 200, w = 80, h = 44 },
			size = { w = 120, h = 30 },
			safe = { x = 8, y = 8, w = 800 - 16, h = 600 - 16 },
			edge = "trailing",
			align = "end",
			gap = 6,
		})
		t.expect(panel.Position.X.Offset).toBe(expected.x)
		t.expect(panel.Position.X.Offset).toBe(300 + 80 + 6)
		t.expect(panel.Position.Y.Offset).toBe(200 + 44 - 30)
		w.stop()
	end)

	t.it("the string form paints exactly as before: no title node", function()
		local w = helped("Posts this avatar")
		t.expect(w.find("HelpTitle")).toBeNil()
		t.expect(w.find("HelpShortcut")).toBeNil()
		t.expect(w.find("HelpText").Text).toBe("Posts this avatar")
		local panel = w.find("Help")
		panel.AbsoluteSize = Vector2.new(100, 30)
		t.expect(panel.Position.Y.Offset).toBe(200 - 30 - 6)
		t.expect(panel.Position.X.Offset).toBe(300 + 40 - 50)
		w.stop()
	end)

	t.it("malformed tables are refused by name at construction", function()
		for index, bad in
			{
				{ title = "T" } :: any,
				{ body = "" },
				{ body = "Posts", extra = true },
				{ body = "Posts", shortcut = { "Ctrl" } },
				{ body = "Posts", shortcut = { {} } },
				{ body = "Posts", edge = "overlap" },
				{ body = "Posts", align = "middle" },
				{ body = 4 },
			}
		do
			local ok, failure = pcall(function()
				helped(bad).stop()
			end)
			t.expect(`case {index}: {ok}`).toBe(`case {index}: false`)
			t.expect(string.find(tostring(failure), "help", 1, true) ~= nil).toBe(true)
		end
		helped({ title = "Post", body = "" }).stop()
	end)

	t.it("a bound help value repaints the live plate in place", function()
		local body = Compose.cell("Posts this avatar")
		local w = helped(body)
		local text = w.find("HelpText")
		body:set("Shares this build")
		t.expect(w.find("HelpText")).toBe(text)
		t.expect(text.Text).toBe("Shares this build")
		w.stop()
	end)

	t.it("safe insets that grow under a live plate keep it inside the new safe box", function()
		local w = helped({ body = "Posts it", edge = "trailing" })
		local panel = w.find("Help")
		panel.AbsoluteSize = Vector2.new(200, 30)
		t.expect(panel.Position.X.Offset).toBe(386)
		w.screen.AbsoluteSize = Vector2.new(500, 600)
		t.expect(panel.Position.X.Offset + 200 <= 500 - 8).toBe(true)
		w.stop()
	end)
end)

t.describe("native Callout: layering", function()
	t.it("paints above the modal layer that holds its anchor and stays under modals elsewhere", function()
		local w = overlay.new(function(UI, Host)
			local plain = UI.Button "Plain" { label = "+" }
			local held = UI.Button "Held" { label = "+" }
			return Host.Folder({
				Name = "Root",
				Host.Frame({ Name = "Page", ZIndex = 1, plain }),
				Host.Frame({ Name = "Modal", ZIndex = 100, held }),
				UI.Callout "Low" {
					anchor = plain,
					isPresented = true,
					content = tip(Host),
					onRetire = function() end,
				},
			})
		end)
		local panel = w.find("CalloutPanel")
		t.expect(panel ~= nil).toBe(true)
		t.expect(panel.ZIndex).toBe(95)
		w.stop()
		local lifted = overlay.new(function(UI, Host)
			local held = UI.Button "Held" { label = "+" }
			return Host.Folder({
				Name = "Root",
				Host.Frame({ Name = "Modal", ZIndex = 100, held }),
				UI.Callout "High" {
					anchor = held,
					isPresented = true,
					content = tip(Host),
					onRetire = function() end,
				},
			})
		end)
		local high = lifted.find("CalloutPanel")
		t.expect(high ~= nil).toBe(true)
		t.expect(high:HasTag("facet-floating")).toBe(true)
		t.expect(high.ZIndex > 100).toBe(true)
		local arrow = lifted.find("Arrow")
		if arrow then
			t.expect(arrow.ZIndex > 100).toBe(true)
			t.expect(arrow.ZIndex < high.ZIndex).toBe(true)
		end
		lifted.stop()
	end)
end)
