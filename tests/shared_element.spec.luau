--!strict
-- SHARED-ELEMENT EXPANSION. `transition = { enter = "transform", source = … }`
-- grows a branch out of a rectangle that MOVES — a mounted node's painted rect,
-- or a rect Readable the owner keeps — and collapses back onto wherever that
-- source has reached. The motion is paint-only: the branch is laid out at its
-- own full size for the whole flight, so nothing reflows and no second sizing
-- authority exists.
local t = require("./lib/testkit")
local Facet = require("../src")
local Compose = Facet.Compose

local function fixed(px: number)
	return { type = "fixed", px = px }
end

-- the one mounted Detail node, whatever path segment the region gave it
local function detail(adapter: any): any
	for _, path in adapter.paths() do
		if path:sub(-7) == "/Detail" then
			return adapter.node(path)
		end
	end
	return nil
end

t.describe("shared-element expansion", function()
	local function world(source: any, lead: any)
		local app, adapter, advance = require("./lib/native_motion_world")()
		local open = Compose.cell(false)
		local UI = app.controls
		app.mount(function()
			return UI.Screen("S")({
				UI.VStack("Feed")({
					width = fixed(640),
					height = fixed(480),
					UI.Box("Lead")({
						width = fixed(80),
						height = function(use)
							return fixed(if lead then use(lead) else 0)
						end,
					}),
					UI.Box("Card")({ width = fixed(80), height = fixed(60), surface = "raised" }),
				}),
				UI.When("Expand")({
					condition = open,
					transition = { enter = "transform", source = source, content = "Body" },
					thenView = function()
						return UI.ZStack("Detail")({
							canvasGroup = true,
							clipChildren = true,
							width = fixed(400),
							height = fixed(300),
							surface = "raised",
							UI.ZStack("Body")({
								canvasGroup = true,
								width = fixed(400),
								height = fixed(300),
								UI.Text("Title")({ text = "Detail" }),
							}),
						})
					end,
				}),
			})
		end)
		advance(0.1)
		return app, adapter, advance, open
	end

	t.it("grows a branch out of its source node's painted rect and lands on its own", function()
		local app, adapter, advance, open = world({ path = "/S/Feed/Card" })
		local card = assert(adapter.node("/S/Feed/Card")).rect
		t.expect(detail(adapter)).toBeNil()
		open:set(true)
		advance(1 / 60)
		local first = assert(detail(adapter))
		-- the first PAINTED frame is the card's box, not the branch's own
		t.expect(math.abs(first.presentedSize.w - card.w) < 24).toBe(true)
		t.expect(math.abs(first.presentedPosition.x - card.x) < 24).toBe(true)
		local last = first.presentedSize.w
		for _ = 1, 6 do
			advance(1 / 60)
			local node = assert(detail(adapter))
			t.expect(node.presentedSize.w > last).toBe(true)
			t.expect(node.presentedSize.w <= node.rect.w).toBe(true)
			last = node.presentedSize.w
		end
		advance(1.5)
		local settled = assert(detail(adapter))
		t.expect(settled.presentedSize.w).toBe(settled.rect.w)
		t.expect(settled.presentedPosition.x).toBe(settled.rect.x)
		app.dispose()
	end)

	t.it("reverses mid-flight from the painted rect and leaves no jump", function()
		local app, adapter, advance, open = world({ path = "/S/Feed/Card" })
		open:set(true)
		advance(6 / 60)
		local mid = assert(detail(adapter)).presentedSize.w
		open:set(false)
		advance(1 / 60)
		local after = assert(detail(adapter)).presentedSize.w
		-- one frame of a reversal moves a fraction of the travel, never a snap
		t.expect(math.abs(after - mid) < 40).toBe(true)
		t.expect(after < mid).toBe(true)
		-- and re-opening mid-collapse resumes rather than restarting
		open:set(true)
		advance(1 / 60)
		local resumed = assert(detail(adapter)).presentedSize.w
		t.expect(math.abs(resumed - after) < 40).toBe(true)
		advance(1.5)
		t.expect(assert(detail(adapter)).presentedSize.w).toBe(assert(detail(adapter)).rect.w)
		open:set(false)
		advance(1.5)
		t.expect(detail(adapter)).toBeNil()
		app.dispose()
	end)

	t.it("follows a source that moves while the expansion is in flight", function()
		local lead = Compose.cell(1)
		local app, adapter, advance, open = world({ path = "/S/Feed/Card" }, lead)
		open:set(true)
		advance(2 / 60)
		local before = assert(detail(adapter)).presentedPosition.y
		lead:set(200)
		advance(1 / 60)
		local moved = assert(detail(adapter)).presentedPosition.y
		t.expect(adapter.node("/S/Feed/Card").rect.y).toBe(200)
		-- the origin moved with the card, so the painted box went with it. A
		-- frozen origin would have carried on in the OTHER direction.
		local control = Compose.cell(1)
		local other, otherAdapter, otherAdvance, otherOpen = world({ path = "/S/Feed/Card" }, control)
		otherOpen:set(true)
		otherAdvance(3 / 60)
		local unmoved = assert(detail(otherAdapter)).presentedPosition.y
		t.expect(moved > before).toBe(true)
		t.expect(moved > unmoved + 60).toBe(true)
		app.dispose()
		other.dispose()
	end)

	t.it("reads a rect Readable as the origin and keeps the last one when it goes nil", function()
		local rect = Compose.cell({ x = 40, y = 300, w = 80, h = 60 })
		local app, adapter, advance, open = world({ rect = rect })
		open:set(true)
		advance(1 / 60)
		local first = assert(detail(adapter))
		local firstWidth = first.presentedSize.w
		t.expect(math.abs(first.presentedPosition.y - 300) < 24).toBe(true)
		rect:set(nil)
		advance(1 / 60)
		-- nothing snaps: the last origin the source yielded is retained
		t.expect(assert(detail(adapter)).presentedSize.w > firstWidth).toBe(true)
		advance(1.5)
		t.expect(assert(detail(adapter)).presentedSize.w).toBe(assert(detail(adapter)).rect.w)
		app.dispose()
	end)

	t.it("settles on the frame it starts under reduced motion", function()
		local app, adapter, advance, open = world({ path = "/S/Feed/Card" })
		app.environment:set("reducedMotion", true)
		open:set(true)
		advance(1 / 60)
		local node = assert(detail(adapter))
		t.expect(node.presentedSize.w).toBe(node.rect.w)
		open:set(false)
		advance(1 / 60)
		t.expect(detail(adapter)).toBeNil()
		app.dispose()
	end)

	t.it("refuses an origin that is named twice or not at all", function()
		local resolve = require("../src/render/transitions").resolve
		local function declare(transition: any)
			return (pcall(resolve, transition))
		end
		t.expect(declare({ enter = "transform" })).toBe(false)
		t.expect(declare({
			enter = "transform",
			fromRect = { x = 0, y = 0, w = 1, h = 1 },
			source = { path = "/S" },
		})).toBe(false)
		t.expect(declare({ enter = "transform", source = { path = "/S", rect = { x = 0, y = 0, w = 1, h = 1 } } }))
			.toBe(false)
		t.expect(declare({ enter = "transform", source = { edge = "top" } })).toBe(false)
		t.expect(declare({ enter = "transform", source = { path = "/S" } })).toBe(true)
		t.expect(declare({ enter = "transform", source = { rect = Compose.cell(nil) } })).toBe(true)
		t.expect(declare({ enter = "transform", fromRect = { x = 0, y = 0, w = 1, h = 1 } })).toBe(true)
	end)
end)
