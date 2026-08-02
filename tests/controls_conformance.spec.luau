--!strict
-- P1.6 control conformance kit (design §10.2): every v1 control class has a
-- declared contract; each mounts/disposes memory-neutrally with a
-- deterministic dump; focusable contracts declare an effective hit target
-- >= the token floor; blueprint dirty maps and authority manifests exist for
-- every bindable prop the contract implies.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local serde = require("@lune/serde")

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local controlContract = require("../src/controls/contract")
local blueprintLib = require("../src/blueprint")
local authority = require("../src/render/authority")
local pathShapes = require("../src/controls/path_shapes")

-- one minimal instance per control class
local function minimalInstance(core: any, class: string): any
	if class == "Text" then
		return UI.Text({ id = "T", text = "x" })
	elseif class == "Button" then
		return UI.Button({ id = "B", label = "b" })
	elseif class == "Toggle" then
		return UI.Toggle({ id = "G", label = "g", value = core:signal(false) })
	elseif class == "TextField" then
		return UI.TextField({ id = "F", text = "x", placeholder = "p" })
	elseif class == "Image" then
		return UI.Image({ id = "I", image = "rbxassetid://1" })
	elseif class == "Spacer" then
		return UI.Spacer({ id = "S" })
	elseif class == "Box" then
		return UI.Box({ id = "X" })
	elseif class == "Screen" then
		return UI.Screen({ id = "Sc", children = { UI.Box({ id = "c" }) } })
	elseif class == "VStack" then
		return UI.VStack({ id = "V", children = { UI.Box({ id = "c" }) } })
	elseif class == "HStack" then
		return UI.HStack({ id = "H", children = { UI.Box({ id = "c" }) } })
	elseif class == "ZStack" then
		return UI.ZStack({ id = "Z", children = { UI.Box({ id = "c" }) } })
	elseif class == "ScrollView" then
		return UI.ScrollView({ id = "L", children = { UI.Box({ id = "c" }) } })
	elseif class == "Anchor" then
		return UI.Anchor({ id = "A", children = { UI.Box({ id = "c", anchor = "topLeft" }) } })
	elseif class == "AdaptiveStack" then
		return UI.AdaptiveStack({ id = "As", axis = "y", children = { UI.Box({ id = "c" }) } })
	elseif class == "ViewThatFits" then
		return UI.ViewThatFits({ id = "Vtf", children = { UI.Box({ id = "c" }) } })
	elseif class == "Composition" then
		return UI.Composition({
			id = "Cmp",
			arrangements = { "column" },
			groups = { { id = "body", lane = "main", sizing = "fill" } },
			children = {
				UI.Region({
					id = "Only",
					group = "body",
					rank = 1,
					sizing = "fill",
					children = { UI.Box({ id = "c" }) },
				}),
			},
		})
	elseif class == "Region" then
		-- a Region is only meaningful inside a Composition; the conformance
		-- instance is the Composition that gives it its box
		return UI.Composition({
			id = "CmpR",
			arrangements = { "column" },
			groups = { { id = "body", lane = "main" } },
			children = { UI.Region({ id = "R", group = "body", rank = 1, children = { UI.Box({ id = "c" }) } }) },
		})
	elseif class == "Divider" then
		return UI.Divider({ id = "Dv" })
	elseif class == "Grid" then
		return UI.Grid({ id = "Gr", columns = 2, children = { UI.Box({ id = "c" }), UI.Box({ id = "d" }) } })
	elseif class == "Grip" then
		return UI.Grip({ id = "Gp", cursorHint = "rbxasset://SizeEW", focusable = true })
	elseif class == "Path" then
		return UI.Path({ id = "P", points = pathShapes.ring({ radius = 0.5 }) })
	elseif class == "When" then
		return UI.When({
			id = "W",
			condition = core:signal(true),
			thenView = function()
				return UI.Box({ id = "c" })
			end,
		})
	elseif class == "ForEach" then
		return UI.ForEach({
			id = "Fe",
			items = core:signal({ 1, 2 }),
			key = function(item)
				return tostring(item)
			end,
			row = function(item)
				return UI.Box({ id = "row" .. tostring(item) })
			end,
		})
	elseif class == "ErrorBoundary" then
		return UI.ErrorBoundary({
			id = "Eb",
			view = function()
				return UI.Box({ id = "c" })
			end,
			fallback = function()
				return UI.Box({ id = "f" })
			end,
		})
	end
	return nil
end

describe("control conformance kit", function()
	local classNames = {}
	for class in controlContract.all() do
		table.insert(classNames, class)
	end
	table.sort(classNames)
	for _, class in classNames do
		local spec = controlContract.all()[class]
		it(`{class}: contract + mount/dispose neutrality + deterministic dump`, function()
			-- contract completeness
			expect(spec.focusRole == "focusable" or spec.focusRole == "none").toBe(true)
			expect(#spec.accessibility > 0).toBe(true)
			if spec.focusRole == "focusable" then
				expect((spec.minHitSize or 0) >= 44).toBe(true)
				expect(#spec.actions > 0).toBe(true)
			end
			-- dirty map declared for the class
			expect(blueprintLib.PROP_DIRTY[class] ~= nil).toBe(true)
			-- mount, dump determinism, dispose neutrality
			local core = customFactory.new()
			local bp = minimalInstance(core, class)
			expect(bp ~= nil).toBe(true)
			local baseline = core:counters()
			local root = mountLib.mount(core, bp)
			local d1 = serde.encode("json", root.dump(), true)
			local d2 = serde.encode("json", root.dump(), true)
			expect(d1).toBe(d2)
			root.dispose()
			local after = core:counters()
			expect(after.scopes).toBe(baseline.scopes)
			expect(after.observers).toBe(baseline.observers)
		end)
	end

	it("bindable props of interactive controls have binding authority declared", function()
		expect(authority.authorityFor("Button", "text")).toBe("binding")
		expect(authority.authorityFor("Button", "enabled")).toBe("binding")
		expect(authority.authorityFor("Toggle", "value")).toBe("binding")
		expect(authority.authorityFor("Text", "text")).toBe("binding")
		expect(authority.authorityFor("Image", "image")).toBe("binding")
	end)
end)
