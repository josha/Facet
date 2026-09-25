--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local worlds = require("./lib/content_world")
local Compose = Facet.Compose

local SEGMENT = { up = "Opt1", down = "Opt2" }

local function mount(spec: any, extra: ((any) -> { any })?): any
	return worlds.new(function(UI, Host)
		local children: { any } = { UI.Vote("V")(spec) }
		for _, node in (if extra then extra(UI) else {}) do
			table.insert(children, node)
		end
		return Host.Frame({ Name = "Row", table.unpack(children) })
	end)
end

local function option(world: any, side: string, root: string?): any
	return world.find(SEGMENT[side], world.find(root or "V"))
end

local function painted(world: any, root: string?): string?
	local chosen: string? = nil
	for side in SEGMENT do
		local node = option(world, side, root)
		if node:HasTag("facet-segment-current") and node:GetAttribute("selected") == true then
			assert(chosen == nil, "two segments are painted")
			chosen = side
		end
	end
	return chosen
end

t.describe("native Vote", function()
	t.it("accepts, swaps in one change, and proposes none when the chosen side is pressed again", function()
		local value = Compose.cell("none")
		local seen: { string } = {}
		local world: any
		world = mount({
			value = value,
			onChange = function(nextValue: string)
				table.insert(seen, `{nextValue}<{value:peek()},{painted(world) or "nil"}>`)
				value:set(nextValue)
			end,
		})
		t.expect(painted(world)).toBeNil()
		option(world, "up").Activated.fire()
		t.expect(painted(world)).toBe("up")
		option(world, "down").Activated.fire()
		t.expect(painted(world)).toBe("down")
		option(world, "down").Activated.fire()
		t.expect(painted(world)).toBeNil()
		t.expect(table.concat(seen, " ")).toBe("up<none,nil> down<up,up> none<down,down>")
		world.stop()
	end)

	t.it("never paints a refused proposal and never touches the caller's cell", function()
		local value = Compose.cell("up")
		local asked: { string } = {}
		local world = mount({
			value = value,
			onChange = function(nextValue: string)
				table.insert(asked, nextValue)
			end,
		})
		option(world, "down").Activated.fire()
		option(world, "up").Activated.fire()
		t.expect(table.concat(asked, ",")).toBe("down,none")
		t.expect(value:peek()).toBe("up")
		t.expect(painted(world)).toBe("up")
		world.stop()
	end)

	t.it("proposes from a selected side through the keyboard Activate action", function()
		local value = Compose.cell("none")
		local world = mount({
			value = value,
			onChange = function(nextValue: string)
				value:set(nextValue)
			end,
		})
		local down = option(world, "down")
		t.expect(down.Selectable).toBe(true)
		world.gui.SelectedObject = down
		local activate = world.action("Activate")
		t.expect(activate ~= nil).toBe(true)
		activate.Pressed.fire()
		t.expect(value:peek()).toBe("down")
		world.stop()
	end)

	t.it("reads a function value and keeps the last legal paint for an invalid late value", function()
		local source = Compose.cell("up")
		local controls: { [string]: any } = {}
		local world = mount({
			value = function(use: any)
				return use(source)
			end,
			controls = controls,
			onChange = function(nextValue: string)
				source:set(nextValue)
			end,
		})
		t.expect(painted(world)).toBe("up")
		source:set("sideways")
		t.expect(painted(world)).toBe("up")
		t.expect(#controls.diagnostics()).toBe(1)
		source:set("down")
		t.expect(painted(world)).toBe("down")
		world.stop()
	end)

	t.it("leaves no stale state when a callback removes the vote", function()
		local show = Compose.cell(true)
		local value = Compose.cell("none")
		local world = worlds.new(function(UI)
			return Compose.show(show, function()
				return UI.Vote("V")({
					value = value,
					onChange = function(nextValue: string)
						value:set(nextValue)
						show:set(false)
					end,
				})
			end)
		end)
		world.find("Opt1").Activated.fire()
		t.expect(value:peek()).toBe("up")
		t.expect(world.find("V")).toBeNil()
		world.stop()
	end)

	t.it("shows a read-only choice with nothing to press or select and uses ordinary disabled paint", function()
		local readOnly = Compose.cell(true)
		local enabled = Compose.cell(true)
		local world = mount({ value = "up", readOnly = readOnly, enabled = enabled, onChange = function() end })
		local up = option(world, "up")
		t.expect(up:IsA("GuiButton")).toBe(false)
		t.expect(up.Parent.Name).toBe("Plate")
		t.expect(up:HasTag("facet-segment-current")).toBe(true)
		t.expect(up:HasTag("facet-disabled")).toBe(false)
		readOnly:set(false)
		t.expect(option(world, "up"):IsA("GuiButton")).toBe(true)
		t.expect(option(world, "up").Selectable).toBe(true)
		enabled:set(false)
		t.expect(option(world, "down").Selectable).toBe(false)
		t.expect(option(world, "down"):HasTag("facet-disabled")).toBe(true)
		world.stop()
	end)

	t.it("refuses to become interactive without onChange", function()
		local readOnly = Compose.cell(true)
		local controls: { [string]: any } = {}
		local world = mount({ value = "down", readOnly = readOnly, controls = controls })
		readOnly:set(false)
		t.expect(world.find("V"):GetAttribute("FacetReadOnly")).toBe(true)
		t.expect(option(world, "down"):IsA("GuiButton")).toBe(false)
		t.expect(#controls.diagnostics()).toBe(1)
		world.stop()
		t.expect(worlds.mountError(function(UI)
			return UI.Vote({ value = "none" })
		end) ~= nil).toBe(true)
		t.expect(worlds.mountError(function(UI)
			return UI.Vote({ value = "sideways", onChange = print })
		end) ~= nil).toBe(true)
		t.expect(worlds.mountError(function(UI)
			return UI.Vote({ value = "none", onChange = print, extra = true })
		end) ~= nil).toBe(true)
	end)

	t.it("keeps two votes and a chip as separate targets at the floor, with a disclosed summary", function()
		local a, b = Compose.cell("up"), Compose.cell("none")
		local world = mount({
			value = a,
			summary = "99% liked",
			onChange = function(nextValue: string)
				a:set(nextValue)
			end,
		}, function(UI)
			return {
				UI.Vote("W")({
					value = b,
					controlSize = "compact",
					onChange = function(nextValue: string)
						b:set(nextValue)
					end,
				}),
				UI.Chip({ Name = "Tag", label = "Racing", selected = Compose.cell(false) }),
			}
		end)
		local targets = {}
		for _, root in { "V", "W" } do
			for side in SEGMENT do
				local node = option(world, side, root)
				local constraint = node:FindFirstChildWhichIsA("UISizeConstraint")
				t.expect(constraint.MinSize.X >= 44 and constraint.MinSize.Y >= 44).toBe(true)
				t.expect(targets[node]).toBeNil()
				targets[node] = true
			end
		end
		t.expect(option(world, "up", "W"):GetAttribute("controlSize")).toBe("compact")
		t.expect(option(world, "up"):GetAttribute("label")).toBe("Upvote")
		t.expect(option(world, "down"):GetAttribute("label")).toBe("Downvote")
		local summary = world.find("Summary", world.find("V"))
		t.expect(summary.Text).toBe("99% liked")
		t.expect(summary:GetAttribute("FacetLabel")).toBe("99% liked")
		t.expect(summary.TextWrapped).toBe(false)
		t.expect(world.find("Summary", world.find("W")).Visible).toBe(false)
		t.expect(b:peek()).toBe("none")
		world.stop()
	end)

	t.it("repaints the Choices vote only from its caller's value and follows the summary", function()
		local scenario = require("../examples/gallery/scenarios/selection_controls") :: any
		local world = worlds.new(function(UI, Host, engine)
			local viewport = Compose.cell({ width = 1000, height = 800 })
			return scenario
				.build({ UI = UI, Compose = Compose, Host = Host, types = engine.types, viewport = viewport, Facet = Facet })
				.screen()
		end)
		local track = world.find("TrackVote")
		local summary = world.find("Summary", track)
		t.expect(summary.Text).toBe("98% liked this")
		world.find("Opt1", track).Activated.fire()
		t.expect(summary.Text).toBe("You and 98% liked this")
		t.expect(world.find("Opt1", track):HasTag("facet-segment-current")).toBe(true)
		local past = world.find("PastVote")
		t.expect(world.find("Opt2", past):IsA("GuiButton")).toBe(false)
		t.expect(world.find("Opt2", past):HasTag("facet-segment-current")).toBe(true)
		world.stop()
	end)
end)

return nil
