--!strict
--[[ THE NATIVE CAPABILITIES THE LEAF SPECS DID NOT REACH — rich text, text
	direction, middle truncation, image tiling/slicing/resampling, and two-axis
	scrolling with an explicit canvas, a freeze and shared indicators.

	Everything here except middle truncation is EXPOSURE: the engine already does
	it, and the library's job is to let a screen ask for it through the one
	property pipeline every other leaf prop rides. So the claims are mostly about
	the pipeline — the value reaches BOTH targets, the closed key set still
	refuses, the default is byte-identical to the day before.

	Middle truncation is the one piece of real policy, because the engine has no
	such mode, and it carries two claims a screenshot cannot make: the painted
	string FITS the width the solver gave it at every width, and it is recomputed
	only when a text, typography, width or metrics-epoch input moves. A policy that re-derived per frame
	would look identical and cost a measurement pass per label.

	Rich text carries the other one: the box is reserved for the text the player
	SEES, so a tag never widens a label. That is the whole reason the measure seam
	takes the displayed form rather than the authored string.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")

local Facet = require("../src") :: any
local world = require("./lib/world")
local richText = require("../src/layout/rich_text")
local textFit = require("../src/layout/text_fit")
local textMetrics = require("../src/layout/text_metrics")
local fake_target = require("./lib/fake_target")

local Compose = Facet.Compose

local function propsOf(w: any, path: string): any
	local node = w.adapter.node(path)
	return if node ~= nil then node.props else nil
end

local function rectOf(w: any, path: string): any
	local node = w.adapter.node(path)
	return if node ~= nil then node.rect else nil
end

-- the one-line width of a string at the face and size a Text node measures with
local function widthOf(text: string, font: string, size: number): number
	return textMetrics.measure(text, font, size, math.huge, nil, 1).width
end

describe("rich text: markup in, displayed text out", function()
	it("strips markup and decodes the five escapes", function()
		expect(richText.displayText("<b>Lap</b> <i>record</i>")).toBe("Lap record")
		expect(richText.displayText('<font color="#ff0000" size="20">Hot</font> lap')).toBe("Hot lap")
		expect(richText.displayText("<stroke thickness='2'>Edge</stroke>")).toBe("Edge")
		-- the two CASE transforms leave a trace, which is the whole difference
		-- between them and every other tag
		expect(richText.displayText("<uc>quiet</uc><sc>Loud</sc><mark>seen</mark>")).toBe("QUIETLOUDseen")
		expect(richText.displayText("one<br/>two")).toBe("one\ntwo")
		expect(richText.displayText("a<br>b")).toBe("a\nb")
		expect(richText.displayText("5 &lt; 6 &amp;&amp; 7 &gt; 6 &quot;yes&quot; &apos;no&apos;")).toBe(
			"5 < 6 && 7 > 6 \"yes\" 'no'"
		)
	end)

	it("consumes a tag it does not implement, and leaves an unknown ENTITY literal", function()
		-- measured live: the engine strips `<blink>` rather than drawing it, so the
		-- estimator has to strip it too or it reserves a box for tags nobody sees
		expect(richText.displayText("<blink>on</blink>")).toBe("on")
		-- ...but a bare `<` is not a tag at all, so the parse fails and the engine
		-- shows the raw string — which is then what gets measured
		expect(richText.displayText("a < b")).toBe("a < b")
		expect(richText.displayText("100&nbsp;km")).toBe("100&nbsp;km")
		expect(richText.displayText("plain")).toBe("plain")
	end)

	it("escape() is the inverse door and round-trips through displayText", function()
		expect(richText.escape("<b>&\"'")).toBe("&lt;b&gt;&amp;&quot;&apos;")
		local raw = "Racer <TheBest> & \"Co.\" 'x'"
		expect(richText.displayText(richText.escape(raw))).toBe(raw)
		-- escaping first is what makes composed markup safe
		local composed = "<b>" .. richText.escape(raw) .. "</b>"
		expect(richText.displayText(composed)).toBe(raw)
	end)

	it("is reachable from the public surface as Facet.richText.escape", function()
		expect(type(Facet.richText)).toBe("table")
		expect(Facet.richText.escape("<a>")).toBe("&lt;a&gt;")
	end)

	it("MEASUREMENT: tags do not widen the box", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 400, h = 400 } })
		local UI = w.UI
		w.present(function()
			return UI.Screen("Rich")({
				padding = 0,

				UI.VStack("Col")({
					UI.Text("Plain")({ text = "Lap record" }),
					UI.Text("Marked")({ rich = true, text = '<mark><font color="#ff0000">Lap record</font></mark>' }),
					-- a tag the engine does not implement is CONSUMED, not drawn
					-- (measured live), so it reserves the same box as the plain form
					UI.Text("Unknown")({ rich = true, text = "<blink>Lap record</blink>" }),
				}),
			})
		end)
		local plain = rectOf(w, "/Rich/Col/Plain")
		expect(rectOf(w, "/Rich/Col/Marked").w).toBe(plain.w)
		expect(rectOf(w, "/Rich/Col/Unknown").w).toBe(plain.w)
	end)

	it("the adapter is told to parse it, and only when asked", function()
		local w = world.new()
		local UI = w.UI
		w.present(function()
			return UI.Screen("RichProp")({
				padding = 0,

				UI.Text("Marked")({ rich = true, text = "<b>x</b>" }),
				UI.Text("Plain")({ text = "x" }),
			})
		end)
		expect(w.adapter.node("/RichProp/Marked").appliedRichText).toBe(true)
		expect(w.adapter.node("/RichProp/Plain").appliedRichText).toBeNil()
		-- the ENGINE still draws the authored string; only the measure sees the
		-- displayed one
		expect(propsOf(w, "/RichProp/Marked").text).toBe("<b>x</b>")
	end)

	it("REFUSES a reactive rich flag and an unknown value", function()
		local w = world.new()
		local UI = w.UI
		w.scoped(function()
			local signal = Compose.cell(true)
			expect(function()
				UI.Text("R")({ rich = signal, text = "x" })
			end).toThrow()
			expect(function()
				UI.Text("R")({ rich = "yes", text = "x" })
			end).toThrow()
		end)
	end)
end)

describe("text direction", function()
	it("reaches both targets as a closed word and is absent by default", function()
		local w = world.new()
		local UI = w.UI
		w.present(function()
			return UI.Screen("Dir")({
				padding = 0,

				UI.Text("Rtl")({ direction = "rtl", text = "x" }),
				UI.Text("Auto")({ direction = "auto", text = "x" }),
				UI.Text("Plain")({ text = "x" }),
			})
		end)
		expect(w.adapter.node("/Dir/Rtl").appliedTextDirection).toBe("RightToLeft")
		expect(w.adapter.node("/Dir/Auto").appliedTextDirection).toBe("Auto")
		expect(w.adapter.node("/Dir/Plain").appliedTextDirection).toBeNil()
	end)

	it("REFUSES a value outside the closed set", function()
		local w = world.new()
		local UI = w.UI
		w.scoped(function()
			expect(function()
				UI.Text("D")({ direction = "leftToRight", text = "x" })
			end).toThrow()
		end)
	end)
end)

describe("middle truncation", function()
	it("keeps the head and the tail, and fits the width at three of them", function()
		local value = "Coastal circuit reverse night lap 14"
		local font, size = "BuilderSans", 16
		for _, width in { 60, 120, 200 } do
			local out = textFit.middle({ text = value, font = font, size = size, width = width })
			expect(widthOf(out, font, size) <= width).toBe(true)
			expect(string.find(out, "\u{2026}", 1, true) ~= nil).toBe(true)
			-- head AND tail survive: the first character and the last are the
			-- value's own, which is the whole difference from an end ellipsis
			expect(string.sub(out, 1, 1)).toBe("C")
			expect(string.sub(out, -2)).toBe("14")
		end
	end)

	it("returns the value untouched when it already fits, and the bare mark when nothing does", function()
		local spec = { text = "Lap 3", font = "BuilderSans", size = 16, width = 400 }
		expect(textFit.middle(spec)).toBe("Lap 3")
		expect(textFit.middle({ text = "Lap 3", font = "BuilderSans", size = 16, width = 1 })).toBe("\u{2026}")
	end)

	it("never cuts inside a multi-byte character", function()
		local value = "Piloté circuit côtier — réservé"
		local out = textFit.middle({ text = value, font = "BuilderSans", size = 16, width = 90 })
		expect(utf8.len(out) ~= nil).toBe(true)
	end)

	it("REFUSES an unknown key on the spec", function()
		expect(function()
			(textFit :: any).middle({ text = "x", font = "BuilderSans", size = 16, width = 10, cap = 20 })
		end).toThrow()
	end)

	it("PAINTS the elided string, and the full value stays the disclosure value", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 400, h = 400 } })
		local UI = w.UI
		local value = "Coastal circuit reverse night lap 14"
		w.present(function()
			return UI.Screen("Mid")({
				padding = 0,

				UI.Text("Path")({
					truncate = "middle",
					disclose = true,
					lineLimit = 1,
					text = value,
					width = { type = "fixed", px = 120 },
				}),
			})
		end)
		local painted = propsOf(w, "/Mid/Path").text
		expect(painted ~= value).toBe(true)
		expect(string.find(painted, "\u{2026}", 1, true) ~= nil).toBe(true)
		expect(string.sub(painted, -2)).toBe("14")
		-- the solve still reports the WHOLE value, which is what the disclosure
		-- plate and the large-text audit read
		local facts = w.controller.textAt("/Mid/Path")
		expect(facts.text).toBe(value)
		expect(facts.truncated).toBe(true)
	end)

	it("RECOMPUTES on a width change and on nothing else", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 400, h = 400 } })
		local UI = w.UI
		local width = Compose.cell(120)
		w.present(function()
			return UI.Screen("MidR")({
				padding = 0,

				UI.Text("Path")({
					truncate = "middle",
					lineLimit = 1,
					text = "Coastal circuit reverse night lap 14",
					width = function(use)
						return { type = "fixed", px = use(width) }
					end,
				}),
			})
		end)
		local before = w.controller.stats().middleTruncations
		expect(before).toBeGreaterThan(0)
		-- three solves that move nothing this policy reads
		w.settle(3)
		expect(w.controller.stats().middleTruncations).toBe(before)
		local narrow = propsOf(w, "/MidR/Path").text
		width:set(240)
		w.settle(2)
		expect(w.controller.stats().middleTruncations).toBeGreaterThan(before)
		expect(propsOf(w, "/MidR/Path").text ~= narrow).toBe(true)
	end)

	it("RESTORES the whole value when the box grows back", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 400 } })
		local UI = w.UI
		local value = "Coastal circuit"
		local width = Compose.cell(60)
		w.present(function()
			return UI.Screen("MidBack")({
				padding = 0,

				UI.Text("Path")({
					truncate = "middle",
					lineLimit = 1,
					text = value,
					width = function(use)
						return { type = "fixed", px = use(width) }
					end,
				}),
			})
		end)
		expect(propsOf(w, "/MidBack/Path").text ~= value).toBe(true)
		width:set(560)
		w.settle(2)
		expect(propsOf(w, "/MidBack/Path").text).toBe(value)
	end)

	it("REFUSES middle truncation on rich text (no displayed-form cut is expressible)", function()
		local w = world.new()
		local UI = w.UI
		w.scoped(function()
			expect(function()
				UI.Text("X")({ rich = true, truncate = "middle", text = "<b>x</b>" })
			end).toThrow()
			expect(function()
				UI.Text("X")({ truncate = "centre", text = "x" })
			end).toThrow()
		end)
	end)
end)

describe("image leaf options", function()
	it("tile, slice and resample reach the fake target", function()
		local w = world.new()
		local UI = w.UI
		w.present(function()
			return UI.Screen("Img")({
				padding = 0,

				UI.Image("Tiled")({
					image = "rbxassetid://1",
					scaleMode = "tile",
					tileSize = { width = 32, height = 32 },
					width = { type = "fixed", px = 100 },
					height = { type = "fixed", px = 100 },
				}),
				UI.Image("Sliced")({
					image = "rbxassetid://2",
					scaleMode = "slice",
					sliceCenter = { x0 = 8, y0 = 8, x1 = 56, y1 = 56 },
					sliceScale = 2,
					width = { type = "fixed", px = 100 },
					height = { type = "fixed", px = 100 },
				}),
				UI.Image("Pixel")({
					image = "rbxassetid://3",
					resample = "pixelated",
					width = { type = "fixed", px = 16 },
					height = { type = "fixed", px = 16 },
				}),
			})
		end)
		expect(w.adapter.node("/Img/Tiled").appliedScaleType).toBe("Tile")
		expect(w.adapter.node("/Img/Tiled").appliedTileSize).toEqual({ width = 32, height = 32 })
		expect(w.adapter.node("/Img/Sliced").appliedScaleType).toBe("Slice")
		expect(w.adapter.node("/Img/Sliced").appliedSliceCenter).toEqual({ x0 = 8, y0 = 8, x1 = 56, y1 = 56 })
		expect(w.adapter.node("/Img/Sliced").appliedSliceScale).toBe(2)
		expect(w.adapter.node("/Img/Pixel").appliedResampleMode).toBe("Pixelated")
		-- the sheet-owned engine properties are CLAIMED before they are written,
		-- exactly as `ScaleType` is, or a native session would refuse the write
		expect(w.adapter.node("/Img/Tiled").paintClaims.TileSize).toBe(true)
		expect(w.adapter.node("/Img/Sliced").paintClaims.SliceCenter).toBe(true)
		expect(w.adapter.node("/Img/Pixel").paintClaims.ResampleMode).toBe(true)
		-- the engine vocabulary is shared, not copied: the live adapter's map and
		-- the fake's name map name the same six modes
		expect(fake_target.SCALE_MODE_ENGINE_NAME.tile).toBe("Tile")
		expect(fake_target.SCALE_MODE_ENGINE_NAME.slice).toBe("Slice")
	end)

	it("REFUSES the geometry key without its mode and the mode without its geometry", function()
		local w = world.new()
		local UI = w.UI
		w.scoped(function()
			expect(function()
				UI.Image("A")({ image = "x", tileSize = { width = 8, height = 8 } })
			end).toThrow()
			expect(function()
				UI.Image("B")({ image = "x", scaleMode = "tile" })
			end).toThrow()
			expect(function()
				UI.Image("C")({ image = "x", sliceCenter = { x0 = 1, y0 = 1, x1 = 9, y1 = 9 } })
			end).toThrow()
			expect(function()
				UI.Image("D")({ image = "x", scaleMode = "slice" })
			end).toThrow()
			expect(function()
				UI.Image("E")({ image = "x", scaleMode = "fit", tileSize = { width = 8, height = 8 } })
			end).toThrow()
			expect(function()
				UI.Image("F")({ image = "x", scaleMode = "tile", tileSize = { width = 8 } })
			end).toThrow()
			expect(function()
				UI.Image("G")({ image = "x", resample = "smooth" })
			end).toThrow()
		end)
	end)

	it("AsyncImage forwards the picture keys", function()
		local w = world.new()
		local UI = w.UI
		local provider = w.app.newResourceProvider({ bind = false })
		w.present(function()
			return UI.Screen("AsyncImg")({
				padding = 0,
				UI.AsyncImage("Async")({
					key = "poster",
					provider = provider,
					scaleMode = "slice",
					sliceCenter = { x0 = 4, y0 = 4, x1 = 28, y1 = 28 },
					resample = "pixelated",
					width = { type = "fixed", px = 64 },
					height = { type = "fixed", px = 64 },
				}),
			})
		end)
		local found: any = nil
		for _, path in w.adapter.paths() do
			local node = w.adapter.node(path)
			if node.class == "Image" and node.appliedSliceCenter ~= nil then
				found = node
			end
		end
		expect(found ~= nil).toBe(true)
		expect(found.appliedScaleType).toBe("Slice")
		expect(found.appliedResampleMode).toBe("Pixelated")
		local request = provider.pendingRequests()[1]
		provider.complete(request.key, request.generation, "rbxassetid://133513168894379")
		w.settle()
		expect(found.props.image).toBe("rbxassetid://133513168894379")
		w.close()
		expect(w.adapter.node("/AsyncImg/Async/Content")).toBeNil()
	end)
end)

describe("two-axis scrolling", function()
	local function twoAxisScreen(UI: any, extra: any): any
		local cells = {}
		for i = 1, 6 do
			table.insert(
				cells,
				UI.Box("Row" .. i)({
					surface = "control",
					width = { type = "fixed", px = 400 },
					height = { type = "fixed", px = 60 },
				})
			)
		end
		local spec: any = {
			axis = "xy",
			width = { type = "fixed", px = 200 },
			height = { type = "fixed", px = 150 },
			table.unpack(cells),
		}
		for key, value in extra or {} do
			spec[key] = value
		end
		return UI.Screen("XY")({ padding = 0, UI.ScrollView("Map")(spec) })
	end

	it("publishes a canvas bigger than the host on BOTH axes", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 400, h = 400 } })
		local UI = w.UI
		w.present(function()
			return twoAxisScreen(UI, nil)
		end)
		local region = w.adapter.node("/XY/Map").scrollRegion
		expect(region.axis).toBe("xy")
		expect(region.contentW).toBeGreaterThan(region.hostW)
		expect(region.contentH).toBeGreaterThan(region.hostH)
	end)

	it("scrollEnabled = false freezes the host and keeps the offset", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 400, h = 400 } })
		local UI = w.UI
		local enabled = Compose.cell(true)
		w.present(function()
			return twoAxisScreen(UI, { scrollEnabled = enabled })
		end)
		w.controller.scrollTo("/XY/Map", { x = 0, y = 40 })
		expect(w.adapter.node("/XY/Map").appliedScrollingEnabled).toBe(true)
		local creates = w.controller.stats().creates
		enabled:set(false)
		w.pres.refresh()
		expect(w.adapter.node("/XY/Map").appliedScrollingEnabled).toBe(false)
		-- ...and it is a prop change, not a rebuild: nothing was created or
		-- destroyed to turn a boolean off
		expect(w.controller.stats().creates).toBe(creates)
		-- the position is PRESERVED: a freeze is not a rewind
		expect(w.controller.scrollPosition("/XY/Map").y).toBe(40)
		-- ...and keep-visible may still move it programmatically
		w.controller.scrollTo("/XY/Map", { x = 0, y = 80 })
		expect(w.controller.scrollPosition("/XY/Map").y).toBe(80)
	end)

	it("an explicit extent overrides the canvas the solve could describe", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 400, h = 400 } })
		local UI = w.UI
		w.present(function()
			return twoAxisScreen(UI, { extent = { width = 1200, height = 900 } })
		end)
		local region = w.adapter.node("/XY/Map").scrollRegion
		expect(region.contentW).toBe(1200)
		expect(region.contentH).toBe(900)
	end)

	it("the indicator opt-out reaches the region as ONE word for both axes", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 400, h = 400 } })
		local UI = w.UI
		w.present(function()
			return twoAxisScreen(UI, { indicators = "none" })
		end)
		expect(w.adapter.node("/XY/Map").scrollRegion.indicators).toBe("none")
		expect(w.adapter.node("/XY/Map").indicatorsOff).toBe(true)

		local w2 = world.new({ viewport = { x = 0, y = 0, w = 400, h = 400 } })
		w2.present(function()
			return twoAxisScreen(w2.UI, nil)
		end)
		expect(w2.adapter.node("/XY/Map").scrollRegion.indicators).toBe("auto")
	end)

	it("REFUSES an unknown axis, an unknown indicator word and a malformed extent", function()
		local w = world.new()
		local UI = w.UI
		w.scoped(function()
			expect(function()
				UI.ScrollView("S")({ axis = "yx" })
			end).toThrow()
			expect(function()
				UI.ScrollView("S")({ indicators = "off" })
			end).toThrow()
			expect(function()
				UI.ScrollView("S")({ axis = "xy", extent = { width = 100, depth = 3 } })
			end).toThrow()
			expect(function()
				UI.ScrollView("S")({ axis = "xy", extent = {} })
			end).toThrow()
		end)
	end)

	it("ARBITRATION: a nested xy scroller pinned at its tail hands the drag to its parent", function()
		--[[ The chain rule, asked of the axis it did not have a case for. An `xy`
			host is a `y` host to the autoscroll model (see `scroll_arrange`), so the
			claim is that `"xy"` reaches the SAME "can this host still travel the way
			the band is asking" test rather than falling off the `axis == "x"` /
			else fork into a band it cannot serve — which is how a two-axis list
			nested in a page would swallow the page's gesture forever.

			The two hosts share a bottom edge, so one drag point sits in BOTH bands;
			that coincidence is what makes the rule observable. ]]
		local w = world.new({ viewport = { x = 0, y = 0, w = 400, h = 600 } })
		local UI = w.UI
		w.present(function()
			local function cells(prefix: string, n: number, w: number, h: number)
				local out = {}
				for i = 1, n do
					table.insert(
						out,
						UI.Box(prefix .. i)({
							surface = "control",
							width = { type = "fixed", px = w },
							height = { type = "fixed", px = h },
						})
					)
				end
				return out
			end
			local outerChildren: { any } = {
				UI.ScrollView("Inner")({
					axis = "xy",
					width = UI.fill(),
					height = { type = "fixed", px = 300 },
					gap = 0,
					padding = 0,
					table.unpack(cells("i", 40, 600, 40)),
				}),
			}
			for _, row in cells("o", 20, 200, 40) do
				table.insert(outerChildren, row)
			end
			return UI.Screen("Nest")({
				padding = 0,
				gap = 0,

				UI.ScrollView("Page")({
					width = UI.fill(),
					height = { type = "fixed", px = 300 },
					gap = 0,
					padding = 0,
					table.unpack(outerChildren),
				}),
			})
		end)
		local c = w.controller
		-- 5px above the shared bottom edge: inside both bands
		local inBand = { x = 200, y = 295 }
		-- ...with the inner host armed and free, it wins
		c.setPointerDrag({ pos = inBand })
		c.stepAutoscroll(0)
		expect(c.stepAutoscroll(0.5).path).toBe("/Nest/Page/Inner")
		c.setPointerDrag(nil)
		c.stepAutoscroll(0)
		-- ...and pinned at its own tail it is transparent, so the page behind it wins
		w.adapter.driveScroll("/Nest/Page/Inner", { x = 0, y = 99999 })
		c.setPointerDrag({ pos = inBand })
		c.stepAutoscroll(0)
		expect(c.stepAutoscroll(0.5).path).toBe("/Nest/Page")
		c.setPointerDrag(nil)
	end)
end)

--[[ ── FIX ROUND 1 ───────────────────────────────────────────────────────────
	Every case below covers one review finding or one lead ruling. They are
	grouped by the seam they exercise rather than by finding number, because a
	reader arriving at a failure wants the mechanism, not the ledger. ]]

describe("fix round 1: middle truncation fits what is DRAWN, and re-derives when it must", function()
	local VALUE = "Coastal circuit reverse night lap 14"

	it("fits the DRAWABLE area, not the outer box, when the label is padded", function()
		--[[ The fit width used to be `entry.rect.w`, but a Text spends its own
			`padding` inside that rect — so the fitted string was up to left+right too
			wide for the area it is drawn into and `TextTruncate.AtEnd` ate the tail,
			which is the one thing middle truncation exists to keep. ]]
		local w = world.new({ viewport = { x = 0, y = 0, w = 400, h = 400 } })
		local UI = w.UI
		w.present(function()
			return UI.Screen("Pad")({
				padding = 0,

				UI.Text("Bare")({
					truncate = "middle",
					lineLimit = 1,
					text = VALUE,
					width = { type = "fixed", px = 160 },
				}),
				UI.Text("Padded")({
					truncate = "middle",
					lineLimit = 1,
					padding = 20,
					text = VALUE,
					width = { type = "fixed", px = 160 },
				}),
			})
		end)
		local facts = w.controller.textAt("/Pad/Padded")
		local painted = propsOf(w, "/Pad/Padded").text
		-- 160 outer − 20 − 20 of padding = 120 drawable, and the facts carry the
		-- pair of sides the solve actually spent
		expect(facts.padX).toBe(40)
		expect(widthOf(painted, facts.font, facts.size) <= 120).toBe(true)
		-- ...and it is a DIFFERENT, shorter string than the unpadded label's, which
		-- is what the old single-width fit could not produce
		expect(painted ~= propsOf(w, "/Pad/Bare").text).toBe(true)
	end)

	it("RE-DERIVES for an instance recycled into a new row", function()
		--[[ The memo is keyed on the adapter handle, and `adopt` re-keys the SAME
			handle table to a new path — so a recycled row used to hit its
			predecessor's entry and keep the predecessor's string (or, with an equal
			key, keep the FULL string the fresh binding write had just put there). ]]
		local w = world.new({ viewport = { x = 0, y = 0, w = 400, h = 400 } })
		local UI = w.UI
		local keys = Compose.cell({ "a", "b", "c" })
		w.present(function()
			return UI.Screen("Recycle")({
				padding = 0,

				UI.ForEach("Rows")({
					items = keys,
					key = function(k)
						return k
					end,
					row = function(_item)
						return UI.Text("Row")({
							truncate = "middle",
							lineLimit = 1,
							text = VALUE,
							width = { type = "fixed", px = 160 },
						})
					end,
				}),
			})
		end, { recycleInstances = true })
		local originalHandles = {}
		for _, path in w.adapter.paths() do
			local node = w.adapter.node(path)
			if node.class == "Text" then
				originalHandles[node] = true
			end
		end
		local reused, labels = 0, 0
		keys:set({})
		w.settle(2) -- Retire first: the Compose pass creates new nodes before parking removals.
		keys:set({ "d", "e", "f" })
		w.settle(2)
		for _, path in w.adapter.paths() do
			local node = w.adapter.node(path)
			if node.class == "Text" then
				labels += 1
				if originalHandles[node] then
					reused += 1
				end
				expect(string.find(node.props.text, "\u{2026}", 1, true) ~= nil).toBe(true)
				expect(node.props.text ~= VALUE).toBe(true)
			end
		end
		expect(labels).toBe(3)
		expect(reused).toBeGreaterThan(0)
	end)

	it("RE-DERIVES when the measurer learns a word (the boot-window settle)", function()
		--[[ Studio, 2026-09-18: the first fit after mount ran on boot-window text
			metrics — "Coastal … lap 14" filled 92 px of a 160 px box — and never
			recomputed when the engine's metrics flipped. The memo now carries the
			measurer's own epoch, which is the signal the text pipeline already
			publishes when a word is learned or a calibration moves. No timer. ]]
		local w = world.new({ viewport = { x = 0, y = 0, w = 400, h = 400 } })
		local UI = w.UI
		w.present(function()
			return UI.Screen("Settle")({
				padding = 0,

				UI.Text("Path")({
					truncate = "middle",
					lineLimit = 1,
					text = VALUE,
					width = { type = "fixed", px = 160 },
				}),
			})
		end)
		local before = w.controller.stats().middleTruncations
		local narrowCut = propsOf(w, "/Settle/Path").text
		-- the measurer answers differently for the same string at the same size:
		-- exactly what a settled boot window does
		textMetrics.calibrate("BuilderSans", 0.3)
		-- the fact the premeasure round publishes when it learns something: a
		-- geometry key, so setting it re-solves exactly as a settle does
		w.env:set("textMeasureEpoch", 1)
		w.settle(2)
		expect(w.controller.stats().middleTruncations).toBeGreaterThan(before)
		expect(propsOf(w, "/Settle/Path").text ~= narrowCut).toBe(true)
		textMetrics.resetCalibration()
	end)

	it("REFUSES a middle cut on a multi-line label", function()
		local w = world.new()
		local UI = w.UI
		w.scoped(function()
			-- a middle-truncated string is one line by definition; with `lineLimit = 3`
			-- the box solved for three lines and one was painted
			expect(function()
				UI.Text("M")({ truncate = "middle", lineLimit = 3, text = VALUE })
			end).toThrow()
			UI.Text("M")({ truncate = "middle", lineLimit = 1, text = VALUE })
			UI.Text("M")({ truncate = "middle", text = VALUE })
		end)
	end)
end)

describe("fix round 1: rich text measures what the engine draws", function()
	it("strips EVERY well-formed tag and the comment form, not a closed subset", function()
		-- measured live 2026-09-18: `<blink>Lap record</blink>` renders as
		-- `Lap record` with bounds 63.5, so the engine consumes markup it does not
		-- implement rather than drawing it
		expect(richText.displayText("<blink>Lap record</blink>")).toBe("Lap record")
		expect(richText.displayText("a<!-- hidden -->b")).toBe("ab")
		expect(richText.displayText("<Foo bar='1'>x</Foo>")).toBe("x")
	end)

	it("applies the CASE transforms, in both spellings", function()
		expect(richText.displayText("<uc>lap record</uc>")).toBe("LAP RECORD")
		expect(richText.displayText("<uppercase>lap record</uppercase>")).toBe("LAP RECORD")
		-- small caps are narrower than full caps, so upper-casing over-measures:
		-- the safe direction, documented as approximate
		expect(richText.displayText("<sc>lap</sc> record")).toBe("LAP record")
		expect(richText.displayText("<smallcaps>lap</smallcaps>")).toBe("LAP")
	end)

	it("measures MALFORMED markup as the raw string", function()
		-- the engine falls back to the raw text when the markup does not parse, so
		-- the box has to be reserved for the raw text
		expect(richText.displayText("a < b")).toBe("a < b")
		expect(richText.displayText("5 < 6 and <b>bold</b>")).toBe("5 < 6 and <b>bold</b>")
		expect(richText.displayText("100% < 200%")).toBe("100% < 200%")
		-- an UNCLOSED but well-formed tag is not malformed: the engine opens the
		-- span and never closes it, which is exactly what this does
		expect(richText.displayText("<b>Lap record")).toBe("Lap record")
	end)

	it("carries a face-changing span onto the measure, so the box does not UNDER-reserve", function()
		--[[ Measured live: rendered `<b>` is +3.5% wider than plain and
			`<font weight="heavy">` +6.6%, while `GetTextBoundsAsync` returns the PLAIN
			width for bold even with RichText on — so the weight has to reach the
			per-word measure key, not the bounds call. ]]
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 400 } })
		local UI = w.UI
		w.present(function()
			return UI.Screen("Span")({
				padding = 0,

				UI.VStack("Col")({
					UI.Text("Plain")({ text = "Championship standings" }),
					UI.Text("Bold")({ rich = true, text = "<b>Championship standings</b>" }),
					UI.Text("Big")({ rich = true, text = '<font size="30">Championship standings</font>' }),
					UI.Text("Caps")({ rich = true, text = "<uc>championship standings</uc>" }),
				}),
			})
		end)
		local plain = rectOf(w, "/Span/Col/Plain").w
		expect(rectOf(w, "/Span/Col/Bold").w).toBeGreaterThan(plain)
		expect(rectOf(w, "/Span/Col/Big").w).toBeGreaterThan(plain)
		--[[ THE CASE TRANSFORM IS EXACT WHERE IT COUNTS AND FLAT WHERE IT CANNOT BE.
			The estimator is a fraction PER GLYPH, so upper-casing cannot move it — but
			the words handed to the engine's per-word measure ARE the upper-cased ones,
			which is where the real +16% comes from on a live session. What a headless
			suite can prove is that the measured string is the drawn string. ]]
		expect(w.controller.textAt("/Span/Col/Caps").text).toBe("CHAMPIONSHIP STANDINGS")
		--[[ ...and the bold run reaches the measure KEY as a weight of the same
			family, which is what makes the engine answer for the face it draws. ]]
		expect(string.find(w.controller.textAt("/Span/Col/Bold").font, "#Bold#", 1, true) ~= nil).toBe(true)
	end)

	it("a paint-only span still measures EXACTLY the plain string", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 400 } })
		local UI = w.UI
		w.present(function()
			return UI.Screen("Paint")({
				padding = 0,

				UI.VStack("Col")({
					UI.Text("Plain")({ text = "Championship standings" }),
					UI.Text("Coloured")({ rich = true, text = '<font color="#ff0000">Championship standings</font>' }),
				}),
			})
		end)
		expect(rectOf(w, "/Paint/Col/Coloured").w).toBe(rectOf(w, "/Paint/Col/Plain").w)
	end)

	it("the disclosure plate and the reveal strip render a rich label AS RICH", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 400, h = 400 } })
		local UI = w.UI
		w.present(function()
			return UI.Screen("Disc")({
				padding = 0,

				UI.Text("Marked")({
					rich = true,
					disclose = true,
					lineLimit = 1,
					text = "<b>Championship</b> standings updated for the season",
					width = { type = "fixed", px = 80 },
				}),
			})
		end)
		expect(w.controller.textAt("/Disc/Marked").truncated).toBe(true); -- the touch route, the one a spec can drive directly
		(w.pres :: any)._discloseLongPress("/Disc/Marked")
		local plate = w.adapter.node("/__disclose__/Layer/Plate/Full")
		expect(plate ~= nil).toBe(true)
		-- the plate shows the AUTHORED value and parses it, so a reader sees
		-- `Championship standings…` rather than `<b>Championship</b> standings…`
		expect(plate.props.text).toBe("<b>Championship</b> standings updated for the season")
		expect(plate.appliedRichText).toBe(true)
	end)
end)

describe("fix round 1: one writer, one axis rule, one closed set", function()
	it("keep-visible on an xy host moves BOTH axes", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 600 } })
		local UI = w.UI
		w.present(function()
			local cells = {}
			for i = 1, 6 do
				table.insert(
					cells,
					UI.Button("B" .. i)({
						label = "cell " .. i,
						width = { type = "fixed", px = 400 },
						height = { type = "fixed", px = 40 },
					})
				)
			end
			return UI.Screen("Keep")({
				padding = 0,

				UI.ScrollView("Board")({
					axis = "xy",
					width = { type = "fixed", px = 200 },
					height = { type = "fixed", px = 100 },
					extent = { width = 1080, height = 400 },
					table.unpack(cells),
				}),
			})
		end)
		expect(w.controller.scrollToVisible("/Keep/Board/B6")).toBe(true)
		local at = w.controller.scrollPosition("/Keep/Board")
		-- the cells are 400 wide in a 200 box and the sixth is below the fold, so
		-- B6 is off BOTH edges of the window
		expect(at.y > 0).toBe(true)
		expect(at.x > 0).toBe(true)
	end)

	it("the paging drag release restores the AUTHORED freeze, not an unconditional true", function()
		-- `screen_pointer`'s paging path turns scrolling off for the gesture and back
		-- on at release; with an authored freeze in play that release used to thaw a
		-- host its author had frozen, permanently (the min-write cache holds `false`)
		local source = fs.readFile("src/client/screen_pointer.luau")
		expect(string.find(source, "instance.ScrollingEnabled = true", 1, true)).toBeNil()
		expect(string.find(source, "authoredScrollingEnabled", 1, true) ~= nil).toBe(true)
		-- ...and the one place the authored value is recorded is the binding write
		local props = fs.readFile("src/client/screen_props.luau")
		expect(string.find(props, "handle.authoredScrollingEnabled", 1, true) ~= nil).toBe(true)
	end)

	it("drag-to-edge autoscroll respects a freeze", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 400, h = 600 } })
		local UI = w.UI
		local enabled = Compose.cell(true)
		w.present(function()
			local rows = {}
			for i = 1, 20 do
				table.insert(
					rows,
					UI.Box("R" .. i)({
						surface = "control",
						width = { type = "fixed", px = 300 },
						height = { type = "fixed", px = 40 },
					})
				)
			end
			return UI.Screen("Froz")({
				padding = 0,
				gap = 0,

				UI.ScrollView("List")({
					scrollEnabled = enabled,
					width = UI.fill(),
					height = { type = "fixed", px = 300 },
					gap = 0,
					padding = 0,
					table.unpack(rows),
				}),
			})
		end)
		local c = w.controller
		local inBand = { x = 200, y = 295 }
		c.setPointerDrag({ pos = inBand })
		c.stepAutoscroll(0)
		expect(c.stepAutoscroll(0.5).path).toBe("/Froz/List")
		c.setPointerDrag(nil)
		c.stepAutoscroll(0)
		enabled:set(false)
		w.pres.refresh()
		c.setPointerDrag({ pos = inBand })
		c.stepAutoscroll(0)
		local frozenStep = c.stepAutoscroll(0.5)
		expect(frozenStep == nil or frozenStep.path == nil).toBe(true)
		c.setPointerDrag(nil)
	end)

	it("REFUSES an indicators TABLE: the engine has one bar thickness", function()
		local w = world.new()
		local UI = w.UI
		w.scoped(function()
			expect(function()
				UI.ScrollView("S")({ indicators = { x = "none", y = "auto" } })
			end).toThrow()
			expect(function()
				UI.ScrollView("S")({ indicators = { x = "none", y = "none" } })
			end).toThrow()
			UI.ScrollView("S")({ indicators = "none" })
			UI.ScrollView("S")({ indicators = "auto" })
		end)
	end)

	it("REFUSES an extent on an axis the host cannot scroll, and a value that is not one", function()
		local w = world.new()
		local UI = w.UI
		w.scoped(function()
			UI.ScrollView("S")({ axis = "y", extent = { height = 900 } })
			UI.ScrollView("S")({ axis = "x", extent = { width = 900 } })
			UI.ScrollView("S")({ axis = "xy", extent = { width = 900, height = 400 } })
			expect(function()
				UI.ScrollView("S")({ axis = "y", extent = { width = 1200 } })
			end).toThrow()
			expect(function()
				UI.ScrollView("S")({ extent = { height = 900, width = 1200 } })
			end).toThrow()
			expect(function()
				UI.ScrollView("S")({ axis = "x", extent = { height = 900 } })
			end).toThrow()
			expect(function()
				UI.ScrollView("S")({ axis = "y", extent = { height = true } })
			end).toThrow()
		end)
	end)

	it("REFUSES a bound scaleMode reaching a mode whose geometry is construction-only", function()
		local w = world.new()
		local UI = w.UI
		local mode = Compose.cell("fit")
		w.present(function()
			return UI.Screen("Bound")({
				padding = 0,

				UI.Image("Pic")({
					image = "rbxassetid://1",
					scaleMode = mode,
					width = { type = "fixed", px = 40 },
					height = { type = "fixed", px = 40 },
				}),
			})
		end)
		-- the four continuous modes still bind freely
		mode:set("crop")
		w.pres.refresh()
		expect(w.adapter.node("/Bound/Pic").appliedScaleType).toBe("Crop")
		--[[ ...and the two that need a construction-only companion key do not. The
			refusal lands inside the binding OBSERVER, which the core quarantines
			rather than re-raising to the setter — so the proof is the pair it leaves:
			the write is DROPPED (the node keeps the mode it had) and the reason is on
			the core's last error, which is the tripwire this suite reads. ]]
		mode:set("tile")
		w.pres.refresh()
		expect(w.adapter.node("/Bound/Pic").appliedScaleType).toBe("Crop")
		expect(string.find(tostring(w.core:lastError()), "construction-only companion key", 1, true) ~= nil).toBe(true)
	end)

	it("REFUSES a tile size or a slice rectangle the engine cannot use", function()
		local w = world.new()
		local UI = w.UI
		w.scoped(function()
			expect(function()
				UI.Image("I")({ image = "x", scaleMode = "tile", tileSize = { width = 0, height = 8 } })
			end).toThrow()
			expect(function()
				UI.Image("I")({ image = "x", scaleMode = "tile", tileSize = { width = 24.5, height = 8 } })
			end).toThrow()
			expect(function()
				UI.Image("I")({ image = "x", scaleMode = "slice", sliceCenter = { x0 = -1, y0 = 8, x1 = 56, y1 = 56 } })
			end).toThrow()
			expect(function()
				UI.Image("I")({
					image = "x",
					scaleMode = "slice",
					sliceCenter = { x0 = 8, y0 = 8, x1 = 56, y1 = 56 },
					sliceScale = 0,
				})
			end).toThrow()
		end)
	end)

	it("the nine-slice keys are the repo's own sliceCenter/sliceScale words", function()
		local w = world.new()
		local UI = w.UI
		w.present(function()
			return UI.Screen("Slice")({
				padding = 0,

				UI.Image("Framed")({
					image = "rbxassetid://1",
					scaleMode = "slice",
					sliceCenter = { x0 = 8, y0 = 8, x1 = 56, y1 = 56 },
					sliceScale = 2,
					width = { type = "fixed", px = 100 },
					height = { type = "fixed", px = 100 },
				}),
			})
		end)
		local node = w.adapter.node("/Slice/Framed")
		expect(node.appliedScaleType).toBe("Slice")
		expect(node.appliedSliceCenter).toEqual({ x0 = 8, y0 = 8, x1 = 56, y1 = 56 })
		expect(node.appliedSliceScale).toBe(2)
	end)
end)

--[[ ── FIX ROUND 2 ───────────────────────────────────────────────────────────
	The live regression first: the lead's Studio pass on the round-1 build found
	the gallery board mounted `ScrollingEnabled = false` and never thawed, while
	every headless case stayed green. A fake that cannot see that is part of the
	defect, so the first case below is the reproduction — and it fails on the
	round-1 tree. ]]

describe("fix round 2: a freeze is only ever what the author asked for", function()
	it("the gallery scenario's own board is SCROLLABLE at mount, and thaws", function()
		--[[ THE LIVE REGRESSION, HEADLESS. `ui.state(x)` CREATES state initialised to
			`x`; it does not wrap an owner-held signal — so `ui.state(frozen)` made a
			getter whose value was the Signal OBJECT (truthy), `not canScroll()` was
			`false` forever, and the board mounted frozen and never thawed. The
			scenario reads the owner's signal with `ui.read` now.

			Driven through the scenario module itself rather than a hand-built tree:
			the defect was IN the fixture, and a spec that rebuilt the tree by hand
			would have kept passing. ]]
		local scenario = require("../examples/gallery/scenarios/leaf_capabilities") :: any
		local w = world.new({ viewport = { x = 0, y = 0, w = 1280, h = 720 }, overflowGuardOff = "scenario fixture" })
		local UI = w.UI
		local built =
			scenario.build({ Facet = Facet, UI = w.UI, Compose = Compose, app = w.app, core = w.core, env = w.env })
		w.present(built.screen)
		built.handle = w.handle
		local board = w.adapter.node("/LeafCapabilities/Content/Body/Board")
		expect(board ~= nil).toBe(true)
		expect(board.props.scrollEnabled).toBe(true)
		expect(board.appliedScrollingEnabled).toBe(true)
		-- ...and the two steps the Studio pass drove
		built.steps.freeze({ handle = w.handle })
		w.pres.refresh()
		expect(w.adapter.node("/LeafCapabilities/Content/Body/Board").appliedScrollingEnabled).toBe(false)
		built.steps.thaw()
		w.pres.refresh()
		expect(w.adapter.node("/LeafCapabilities/Content/Body/Board").appliedScrollingEnabled).toBe(true)
		w.close()
	end)

	it("a host that never authored the freeze is SCROLLABLE, and is never written false", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 400, h = 400 }, ops = true })
		local UI = w.UI
		w.present(function()
			return UI.Screen("Plainish")({
				padding = 0,

				UI.ScrollView("List")({
					width = UI.fill(),
					height = { type = "fixed", px = 100 },
					UI.Box("Tall")({ width = UI.fill(), height = { type = "fixed", px = 400 } }),
				}),
			})
		end)
		-- the engine's own default, mirrored by the fake at creation: a scroll host
		-- is born scrollable and Facet writes nothing unless a screen says otherwise
		expect(w.adapter.node("/Plainish/List").appliedScrollingEnabled).toBe(true)
		local wrote = false
		for _, op in w.adapter.ops() do
			if string.find(op, "scrollEnabled", 1, true) ~= nil then
				wrote = true
			end
		end
		expect(wrote).toBe(false)
	end)

	it("every flip of a bound freeze reaches the instance", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 400, h = 400 } })
		local UI = w.UI
		local frozen = Compose.cell(false)
		w.present(function()
			return UI.Screen("Flip")({
				padding = 0,

				UI.ScrollView("List")({
					scrollEnabled = function(use)
						return not use(frozen)
					end,
					width = UI.fill(),
					height = { type = "fixed", px = 100 },
					UI.Box("Tall")({ width = UI.fill(), height = { type = "fixed", px = 400 } }),
				}),
			})
		end)
		local function applied(): any
			return w.adapter.node("/Flip/List").appliedScrollingEnabled
		end
		expect(applied()).toBe(true)
		for _, want in { true, false, true, false } do
			frozen:set(want)
			w.pres.refresh()
			expect(applied()).toBe(not want)
		end
	end)

	it("the paging drag restores the AUTHORED value in BOTH states, and invents nothing", function()
		--[[ The live half of the one-writer rule, pinned over the adapter's own
			source because a paging mouse-drag needs a real pointer and a real
			`ScrollingFrame`. Three claims, one per line of the restore:
			it reads the recorded authored value, absent means TRUE (the engine's
			default and the behaviour before the freeze existed), and the literal
			`= true` it replaced is gone. ]]
		local pointer = fs.readFile("src/client/screen_pointer.luau")
		local props = fs.readFile("src/client/screen_props.luau")
		expect(
			string.find(pointer, "instance.ScrollingEnabled = handle.authoredScrollingEnabled ~= false", 1, true) ~= nil
		).toBe(true)
		expect(string.find(pointer, "instance.ScrollingEnabled = true", 1, true)).toBeNil()
		-- ...and exactly one seam records it, at the binding write
		expect(string.find(props, "handle.authoredScrollingEnabled = value ~= false", 1, true) ~= nil).toBe(true)
		local recorders = 0
		for _ in string.gmatch(props .. pointer, "handle%.authoredScrollingEnabled = ") do
			recorders += 1
		end
		expect(recorders).toBe(1)
	end)
end)

describe("fix round 2: the remaining review findings", function()
	it("NEW-1: a weight attribute widens in EVERY spelling the engine accepts", function()
		local base = "GothamSSm#Regular#Normal"
		local plain = textMetrics.measure("Championship standings", base, 24, math.huge, nil, 1).width
		for _, markup in
			{
				"<b>Championship standings</b>",
				'<font weight="Heavy">Championship standings</font>',
				'<font weight="heavy">Championship standings</font>',
				'<font weight="bold">Championship standings</font>',
				'<font weight="700">Championship standings</font>',
			}
		do
			local display = richText.displayText(markup)
			local spans = richText.spansOf(markup)
			expect(spans ~= nil).toBe(true)
			local runs = {}
			for _, span in spans :: any do
				table.insert(runs, {
					at = span.at,
					font = if span.weight ~= nil then `GothamSSm#{span.weight}#Normal` else "",
					size = span.size,
				})
			end
			local key = textMetrics.runKey(base, runs)
			expect(textMetrics.measure(display, key, 24, math.huge, nil, 1).width > plain).toBe(true)
		end
	end)

	it("NEW-1: the lower-case spellings resolve to the engine's own FontWeight names", function()
		local spans = richText.spansOf('<font weight="heavy">x</font>') :: any
		expect(spans[1].weight).toBe("Heavy")
		expect((richText.spansOf('<font weight="bold">x</font>') :: any)[1].weight).toBe("Bold")
		expect((richText.spansOf('<font weight="SEMIBOLD">x</font>') :: any)[1].weight).toBe("SemiBold")
		expect((richText.spansOf('<font weight="extrabold">x</font>') :: any)[1].weight).toBe("ExtraBold")
		-- a spelling the engine has no weight for names nothing, so nothing widens
		expect(richText.spansOf('<font weight="chunky">x</font>') :: any).toBeNil()
	end)

	it("NEW-2: a BOUND axis with an extent is refused, by testing the prop", function()
		local w = world.new()
		local UI = w.UI
		w.scoped(function()
			local axis = Compose.cell("y")
			expect(function()
				UI.ScrollView("S")({ axis = axis, extent = { height = 900 } })
			end).toThrow()
			expect(function()
				UI.ScrollView("S")({ axis = axis, extent = { width = 900 } })
			end).toThrow()
			-- ...and a bound axis with NO extent is untouched
			UI.ScrollView("S")({ axis = axis })
		end)
	end)

	it("NEW-3: the SPACE is measured at the base face, never with the compound key", function()
		local base = "GothamSSm#Regular#Normal"
		local key = textMetrics.runKey(base, { { at = 1, font = "GothamSSm#Bold#Normal" }, { at = 5, font = "" } })
		textMetrics.resetMeasured()
		textMetrics.beginCollect()
		textMetrics.measure("Lap record here", key, 16, 400, nil, 2)
		local requests = textMetrics.endCollect()
		local spaceFonts: { string } = {}
		for _, request in requests do
			if request.word == " " then
				table.insert(spaceFonts, request.font)
			end
		end
		expect(#spaceFonts > 0).toBe(true)
		for _, font in spaceFonts do
			expect(font).toBe(base)
		end
	end)
end)

--[[ ── FIX ROUND 3 ───────────────────────────────────────────────────────────
	The fixture's SECOND device-visible defect: its two width stops never moved.
	A read in component setup captures a value; a function(use) property
	reads again when the cell changes. Both halves of that lesson are now driven here rather than
	asserted in a report. ]]

describe("fix round 3: the fixture's width stops actually move", function()
	local BOARD = "/LeafCapabilities/Content/Body/Board"
	local CUT_MIDDLE = "/LeafCapabilities/Content/Body/CutMiddle"
	local CUT_END = "/LeafCapabilities/Content/Body/CutEnd"

	local function mountScenario(): (any, any)
		local scenario = require("../examples/gallery/scenarios/leaf_capabilities") :: any
		local w = world.new({ viewport = { x = 0, y = 0, w = 1280, h = 720 }, overflowGuardOff = "scenario fixture" })
		local UI = w.UI
		local built =
			scenario.build({ Facet = Facet, UI = w.UI, Compose = Compose, app = w.app, core = w.core, env = w.env })
		w.present(built.screen)
		built.handle = w.handle
		return w, built
	end

	it("widen and narrow move BOTH truncation rows, and the middle cut re-derives", function()
		local w, built = mountScenario()
		local function widthOfRow(path: string): number
			return w.controller.rectOf(path).w
		end
		expect(widthOfRow(CUT_MIDDLE)).toBe(160)
		expect(widthOfRow(CUT_END)).toBe(160)
		local narrowCut = propsOf(w, CUT_MIDDLE).text

		built.steps.widen()
		w.pres.refresh()
		expect(widthOfRow(CUT_MIDDLE)).toBe(320)
		expect(widthOfRow(CUT_END)).toBe(320)
		-- the point of the two stops: the cut is a different string at each
		expect(propsOf(w, CUT_MIDDLE).text ~= narrowCut).toBe(true)

		built.steps.narrow()
		w.pres.refresh()
		expect(widthOfRow(CUT_MIDDLE)).toBe(160)
		expect(propsOf(w, CUT_MIDDLE).text).toBe(narrowCut)
		w.close()
	end)

	it("a step reports the width the SCREEN has, not the one it asked for", function()
		--[[ The step returned its own request, so it reported a widened row for
			three rounds while the screen never moved. Read from the solved rect and
			the instrument can no longer agree with itself. ]]
		local w, built = mountScenario()
		local widened = built.steps.widen({ handle = w.handle })
		expect(widened.width).toBe(w.controller.rectOf(CUT_MIDDLE).w)
		expect(widened.width).toBe(320)
		local narrowed = built.steps.narrow({ handle = w.handle })
		expect(narrowed.width).toBe(w.controller.rectOf(CUT_MIDDLE).w)
		expect(narrowed.width).toBe(160)
		w.close()
	end)

	it("freeze and thaw still hold, and the board is scrollable at mount", function()
		local w, built = mountScenario()
		expect(w.adapter.node(BOARD).appliedScrollingEnabled).toBe(true)
		built.steps.freeze({ handle = w.handle })
		w.pres.refresh()
		expect(w.adapter.node(BOARD).appliedScrollingEnabled).toBe(false)
		built.steps.thaw()
		w.pres.refresh()
		expect(w.adapter.node(BOARD).appliedScrollingEnabled).toBe(true)
		w.close()
	end)
end)

describe("fix round 3: the numeric weight ladder is the engine's own", function()
	it("every engine weight number names its own face", function()
		local pairs_: { { n: string, name: string } } = {
			{ n = "100", name = "Thin" },
			{ n = "200", name = "ExtraLight" },
			{ n = "300", name = "Light" },
			{ n = "500", name = "Medium" },
			{ n = "600", name = "SemiBold" },
			{ n = "700", name = "Bold" },
			{ n = "800", name = "ExtraBold" },
			{ n = "900", name = "Heavy" },
		}
		for _, row in pairs_ do
			local spans = richText.spansOf(`<font weight="{row.n}">x</font>`) :: any
			expect(`{row.n}=${if spans ~= nil then spans[1].weight else "nil"}`).toBe(`{row.n}=${row.name}`)
		end
		-- 400 IS the base face, so it names nothing rather than a redundant span
		expect(richText.spansOf('<font weight="400">x</font>')).toBeNil()
		-- ...and a number the engine has no weight for names nothing either, which
		-- is what the engine itself draws for it
		expect(richText.spansOf('<font weight="750">x</font>')).toBeNil()
	end)

	it("every weight that can widen has an estimate, and the ladder is monotonic", function()
		local base = "GothamSSm#Regular#Normal"
		local plain = textMetrics.measure("Championship standings", base, 24, math.huge, nil, 1).width
		local last = plain
		for _, weight in { "Medium", "SemiBold", "Bold", "ExtraBold", "Heavy" } do
			local key = textMetrics.runKey(base, { { at = 1, font = `GothamSSm#{weight}#Normal` } })
			local width = textMetrics.measure("Championship standings", key, 24, math.huge, nil, 1).width
			expect(`{weight} wider than plain`).toBe(
				`{weight} {if width > plain then "wider" else "NOT wider"} than plain`
			)
			expect(`{weight} monotonic`).toBe(`{weight} {if width >= last then "monotonic" else "BACKWARDS"}`)
			last = width
		end
	end)

	it("the spellings the review probed each reach their own face", function()
		expect((richText.spansOf('<font weight="500">x</font>') :: any)[1].weight).toBe("Medium")
		expect((richText.spansOf('<font weight="800">x</font>') :: any)[1].weight).toBe("ExtraBold")
		expect((richText.spansOf('<font weight="extrabold">x</font>') :: any)[1].weight).toBe("ExtraBold")
	end)
end)

describe("Compose leaf recipe validation", function()
	local function bound(value, kind)
		local cell = Compose.cell(value)
		if kind == "cell" then
			return cell
		end
		if kind == "formula" then
			return Compose.formula(function(use)
				return use(cell)
			end)
		end
		return function(use)
			return use(cell)
		end
	end
	local function refuses(fn, word)
		local ok, why = pcall(fn)
		expect(ok).toBe(false)
		expect(string.find(tostring(why), word, 1, true) ~= nil).toBe(true)
	end
	for _, named in { false, true } do
		for _, kind in { "cell", "formula", "recipe" } do
			it(`rejects static recipes before mount ({named}, {kind})`, function()
				local w = world.new()
				w.scoped(function()
					for _, row in { { "rich", true }, { "direction", "rtl" }, { "truncate", "middle" } } do
						local props = { text = "hello", [row[1]] = bound(row[2], kind) }
						refuses(function()
							if named then
								w.UI.Text("Label")(props)
							else
								w.UI.Text(props)
							end
						end, "read once at mount")
					end
					refuses(function()
						local props = { scaleMode = "tile", tileSize = bound({ width = 24, height = 24 }, kind) }
						if named then
							w.UI.Image("Pic")(props)
						else
							w.UI.Image(props)
						end
					end, "read once at mount")
					refuses(function()
						local props = { axis = bound("xy", kind), extent = { width = 640, height = 480 } }
						if named then
							w.UI.ScrollView("Board")(props)
						else
							w.UI.ScrollView(props)
						end
					end, "static `axis`")
				end)
			end)
			it(`rejects initially bound tile/slice with matching geometry ({named}, {kind})`, function()
				local w = world.new()
				w.scoped(function()
					for _, mode in { "tile", "slice" } do
						local props = { scaleMode = bound(mode, kind) }
						if mode == "tile" then
							props.tileSize = { width = 24, height = 24 }
						else
							props.sliceCenter = { x0 = 8, y0 = 8, x1 = 56, y1 = 56 }
						end
						refuses(function()
							if named then
								w.UI.Image("Pic")(props)
							else
								w.UI.Image(props)
							end
						end, "static mode")
					end
				end)
			end)
		end
	end
	it("live recipes retain valid image paint when a static-only mode is refused", function()
		local w = world.new()
		local mode, sample = Compose.cell("fit"), Compose.cell("default")
		w.present(function()
			return w.UI.Screen("Recipes")({
				w.UI.Image("Pic")({
					image = "rbxassetid://1",
					scaleMode = function(use)
						return use(mode)
					end,
					resample = function(use)
						return use(sample)
					end,
				}),
			})
		end)
		mode:set("crop")
		sample:set("pixelated")
		w.settle()
		expect(w.adapter.node("/Recipes/Pic").appliedScaleType).toBe("Crop")
		expect(w.adapter.node("/Recipes/Pic").appliedResampleMode).toBe("Pixelated")
		mode:set("slice")
		w.settle()
		expect(w.adapter.node("/Recipes/Pic").appliedScaleType).toBe("Crop")
		expect(string.find(tostring(w.core:lastError()), "static mode", 1, true) ~= nil).toBe(true)
	end)
end)

describe("leaf gallery controls", function()
	it("drives visible controls, reports mounted facts and clears them on teardown", function()
		local scenario = require("../examples/gallery/scenarios/leaf_capabilities")
		local w = world.new({ viewport = { x = 0, y = 0, w = 1280, h = 720 } })
		local built = scenario.build({ Facet = Facet, UI = w.UI, Compose = Compose })
		expect(built.report().width).toBeNil()
		expect(built.report().offset).toBeNil()
		w.present(built.screen)
		built.handle = w.handle
		local prefix = "/LeafCapabilities/Content/Body/"
		expect(built.report().width).toBe(160)
		expect(w.adapter.driveActivate(prefix .. "Actions/Width")).toBe(true)
		w.settle()
		expect(built.report().width).toBe(320)
		expect(built.report().endWidth).toBe(320)
		expect(w.adapter.driveActivate(prefix .. "Actions/Freeze")).toBe(true)
		w.settle()
		expect(w.adapter.node(prefix .. "Board").appliedScrollingEnabled).toBe(false)
		built.reset()
		w.settle()
		expect(built.report().width).toBe(160)
		expect(w.adapter.node(prefix .. "Board").appliedScrollingEnabled).toBe(true)
		w.close()
		expect(built.report().width).toBeNil()
		expect(built.report().endWidth).toBeNil()
		expect(built.report().offset).toBeNil()
	end)
end)

describe("P1b review: rich word boundaries and reveal identity", function()
	it("measures opening, closing and whole rich runs inside one unbroken word", function()
		textMetrics.resetMeasured()
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 400 } })
		w.present(function()
			return w.UI.Screen("Runs")({
				w.UI.VStack("Col")({
					w.UI.Text("Open")({ rich = true, textSize = 16, text = 'Lap<font size="48">Record</font>' }),
					w.UI.Text("Close")({ rich = true, textSize = 16, text = '<font size="48">Lap</font>Record' }),
					w.UI.Text("Whole")({ rich = true, textSize = 16, text = '<font size="48">LapRecord</font>' }),
				}),
			})
		end)
		local open = w.controller.textAt("/Runs/Col/Open")
		local close = w.controller.textAt("/Runs/Col/Close")
		local whole = w.controller.textAt("/Runs/Col/Whole")
		local base = string.split(open.font, "\1")[1]
		textMetrics.beginCollect()
		textMetrics.measure("LapRecord", open.font, 16, math.huge)
		textMetrics.measure("LapRecord", whole.font, 16, math.huge)
		local requested = {}
		for _, request in textMetrics.endCollect() do
			requested[request.word .. ":" .. request.size] = true
		end
		expect(requested["Lap:16"]).toBe(true)
		expect(requested["Record:48"]).toBe(true)
		expect(requested["LapRecord:48"]).toBe(true)
		for _, row in
			{
				{ "Lap", 16, 30 },
				{ "Record", 48, 120 },
				{ "Lap", 48, 70 },
				{ "Record", 16, 60 },
				{ "LapRecord", 48, 186 },
			}
		do
			textMetrics.setMeasured(base, row[2], row[1], row[3])
		end
		w.env:set("textMeasureEpoch", 1)
		w.settle()
		expect(rectOf(w, "/Runs/Col/Open").w).toBe(150)
		expect(rectOf(w, "/Runs/Col/Close").w).toBe(130)
		expect(rectOf(w, "/Runs/Col/Whole").w).toBe(186)
		expect(textMetrics.minWidth("LapRecord", open.font, 16)).toBe(150)
		expect(textMetrics.minWidth("LapRecord", close.font, 16)).toBe(130)
		expect(textMetrics.minWidth("LapRecord", whole.font, 16)).toBe(186)
		-- A font boundary is not a wrapping opportunity, even when the word cannot fit.
		expect(textMetrics.measure("LapRecord", open.font, 16, 100).naturalLines).toBe(1)
		textMetrics.beginCollect()
		expect(textMetrics.measure("LapRecord", open.font, 16, math.huge).width).toBe(150)
		expect(#textMetrics.endCollect()).toBe(0)
		textMetrics.resetMeasured()
	end)

	it("retires a moving rich strip when equal displayed words change markup", function()
		local w = world.new({
			viewport = { x = 0, y = 0, w = 400, h = 400 },
			overflowGuardOff = "the reveal strip deliberately travels behind its native clipping window",
		})
		local words = "Championship standings updated for the season"
		local markup = Compose.cell('<font color="#ff0000">' .. words .. "</font>")
		local visible = Compose.cell(true)
		local source
		w.present(function()
			return w.UI.Screen("Moving")({
				Compose.show(visible, function()
					source = w.UI.Text("Label")({
						rich = true,
						text = markup,
						textSize = 16,
						reveal = "auto",
						lineLimit = 1,
						width = { type = "fixed", px = 80 },
					})
					return source
				end),
			})
		end)
		local full = "/__reveal__/Layer/Window/Inner/Full"
		local function start()
			for _ = 1, 65 do
				w.tick(1 / 30)
			end
			expect(w.pres.reveal().present).toBe(true)
			expect(w.adapter.node(full).props.text).toBe(markup:peek())
			expect(w.adapter.visibleOf("/Moving/Label")).toBe(false)
		end
		start()
		for _, nextMarkup in { '<font color="#0000ff">' .. words .. "</font>", "<b>" .. words .. "</b>" } do
			markup:set(nextMarkup)
			w.settle()
			w.tick(1 / 30)
			expect(w.pres.reveal().present).toBe(false)
			expect(w.adapter.node(full)).toBeNil()
			expect(w.adapter.visibleOf("/Moving/Label")).toBe(true)
			start()
		end
		local prior = source
		visible:set(false)
		w.settle()
		visible:set(true)
		w.settle()
		w.tick(1 / 30)
		expect(source == prior).toBe(false)
		expect(prior.destroyed).toBe(true)
		expect(w.adapter.node(full)).toBeNil()
		expect(w.adapter.visibleOf("/Moving/Label")).toBe(true)
		start()
		w.close()
		expect(w.adapter.node(full)).toBeNil()
	end)
end)

describe("P1b review: an acquired native scroll capture can be frozen", function()
	for _, paging in { false, true } do
		it(`stops the real move/up/cancel handlers mid-drag, paging {paging}`, function()
			-- Execute the native handler closure, as native_caret_scroll does, rather than a copied state machine.
			local source = fs.readFile("src/client/screen_pointer.luau")
			local first = string.find(source, "local instance = hit", 1, true)
			local last = string.find(source, "beginPointerCapture(handle, handlers, input)", first, true)
			assert(first and last)
			local factory = require("@lune/luau").load(
				"return function(handle, hit, pos, mouseScroll, input, suppressedInputs, Vector2, endCapture)\n"
					.. string.sub(source, first, last - 1)
					.. "\nreturn handlers\nend",
				{ debugName = "native-scroll-capture" }
			)()
			local Vector2 = require("@lune/roblox").Vector2
			local handle = { paging = paging, authoredScrollingEnabled = true }
			local instance = {
				CanvasPosition = Vector2.new(40, 20),
				AbsoluteWindowSize = Vector2.new(200, 100),
				AbsoluteCanvasSize = Vector2.new(1000, 100),
				ScrollingEnabled = true,
				ResetScrollVelocity = function() end,
			}
			local handlers, cancelled = nil, 0
			handlers = factory(
				handle,
				instance,
				{ x = 100, y = 0 },
				require("../src/input/mouse_scroll"),
				{},
				{},
				Vector2,
				function()
					cancelled += 1
					handlers.cancel()
				end
			)
			handlers.move({ x = 80, y = 0 })
			expect(instance.CanvasPosition.X).toBe(60)
			handlers.move({ x = 60, y = 0 }) -- paging's own native false is not an authored freeze
			expect(instance.CanvasPosition.X).toBe(80)
			handle.authoredScrollingEnabled = false
			instance.ScrollingEnabled = false
			handlers.move({ x = 0, y = 0 })
			expect(instance.CanvasPosition.X).toBe(80)
			expect(cancelled).toBe(1)
			expect(handle.mouseScrolling).toBeNil()
			handlers.up()
			handlers.cancel()
			expect(instance.ScrollingEnabled).toBe(false)
			instance.CanvasPosition = Vector2.new(300, 20) -- freezing never disables programmatic placement
			expect(instance.CanvasPosition.X).toBe(300)
		end)
	end
end)

describe("native horizontal acquisition respects decorative and real overlays", function()
	local function acquisition(hits, handles, pointer)
		-- Run the actual ordered native hit/ancestor walk and capture closures, without global engine mocks.
		local source = fs.readFile("src/client/screen_pointer.luau")
		local first = string.find(source, "local hits = playerGui:GetGuiObjectsAtPosition", 1, true)
		local last = string.find(source, "\n\t\t\tend)\n\t\tend)\n\tend", first, true)
		assert(first and last)
		local factory = require("@lune/luau").load(
			"return function(playerGui, input, handlesByPath, Enum, pos, mouseScroll, suppressedInputs, Vector2, beginPointerCapture, endCapture)\n"
				.. string.sub(source, first, last - 1)
				.. "\nend",
			{ debugName = "native-scroll-acquisition" }
		)()
		local gui = {
			GetGuiObjectsAtPosition = function()
				return hits
			end,
		}
		for _, hit in hits do
			if hit.Parent == nil then
				hit.Parent = gui
			end
		end
		local captured, handlers
		factory(
			gui,
			{ UserInputType = pointer or "MouseButton1", Position = { X = 100, Y = 0 } },
			handles,
			{ UserInputType = { Touch = "Touch" }, ScrollingDirection = { X = "X", Y = "Y" } },
			{ x = 100, y = 0 },
			require("../src/input/mouse_scroll"),
			{},
			require("@lune/roblox").Vector2,
			function(handle, callbacks)
				captured, handlers = handle, callbacks
			end,
			function()
				if handlers then
					handlers.cancel()
				end
			end
		)
		return captured, handlers
	end
	local function node(name, class, parent)
		return {
			Name = name,
			Parent = parent,
			IsA = function(_, wanted)
				return wanted == class
			end,
			FindFirstChildWhichIsA = function()
				return nil
			end,
		}
	end
	local function scroller()
		local hit = node("/S/X", "ScrollingFrame")
		hit.ScrollingEnabled, hit.ScrollingDirection, hit.ScrollBarThickness = true, "X", 0
		hit.AbsoluteCanvasSize, hit.AbsoluteWindowSize = { X = 900 }, { X = 200 }
		hit.CanvasPosition = require("@lune/roblox").Vector2.new(0, 0)
		return hit, { instance = hit, path = "/S/X", authoredScrollingEnabled = true }
	end

	it("skips multiple owned reveal and focus-ring hits, then acquires and freezes the real scroller", function()
		local scroll, handle = scroller()
		local reveal = node("/__reveal__", "Frame")
		local child = node("Decorative child", "TextLabel", reveal)
		local ring = node("FocusRingFloat", "Frame")
		handle.focusRingFloat = ring
		local handles = {
			X = handle,
			Reveal = { instance = reveal, path = "/__reveal__", rootHandle = { screenId = "__reveal__" } },
		}
		local captured, handlers = acquisition({ child, ring, reveal, scroll }, handles)
		expect(captured).toBe(handle)
		handlers.move({ x = 70, y = 0 })
		expect(scroll.CanvasPosition.X).toBe(30)
		handle.authoredScrollingEnabled, scroll.ScrollingEnabled = false, false
		handlers.move({ x = 10, y = 0 })
		handlers.up()
		expect(scroll.CanvasPosition.X).toBe(30)
		expect(scroll.ScrollingEnabled).toBe(false)
		expect(handle.mouseScrolling).toBeNil()
	end)

	it("retains real overlays, foreign lookalikes, text selection and drag-detector refusal", function()
		for _, kind in { "modal", "foreign", "foreignRing", "foreignRingChild", "textbox", "drag" } do
			local scroll, handle = scroller()
			local blocker = node(
				if kind == "foreign" then "/__reveal__" else "/Modal",
				if kind == "textbox" then "TextBox" else "Frame",
				if kind == "textbox" or kind == "drag" then scroll else nil
			)
			if kind == "foreignRing" then
				blocker.Name = "FocusRingFloat"
			elseif kind == "foreignRingChild" then
				blocker.Parent = node("FocusRingFloat", "Frame")
			end
			if kind == "drag" then
				blocker.FindFirstChildWhichIsA = function()
					return {}
				end
			end
			local handles = { X = handle }
			if kind == "modal" then
				handles.Modal = { instance = blocker, path = "/Modal", rootHandle = { screenId = "Modal" } }
			end
			expect(acquisition({ blocker, scroll }, handles)).toBeNil()
			expect(scroll.CanvasPosition.X).toBe(0)
		end
		local scroll, handle = scroller()
		expect(acquisition({ scroll }, { X = handle }, "Touch")).toBeNil()
	end)
end)

describe("text and canvas hardening", function()
	it("refuses invalid canvas values before mount and permits same-app recovery", function()
		local w = world.new()
		local UI = w.UI
		for _, value in { 0, -2, math.huge, -math.huge, 0 / 0, "not.a.metric", "-xl" } do
			local ok, err = pcall(function()
				w.present(function()
					return UI.Screen("S")({ UI.ScrollView("Canvas")({ axis = "xy", extent = { width = value } }) })
				end)
			end)
			expect(ok).toBe(false)
			expect(string.find(tostring(err), "extent.width", 1, true) ~= nil).toBe(true)
			expect(w.adapter.liveCount()).toBe(0)
		end
		w.present(function()
			return UI.Screen("S")({
				UI.ScrollView("Canvas")({ axis = "xy", extent = { width = "targetSizes.minimum", height = 900 } }),
			})
		end)
		expect(w.adapter.node("/S/Canvas").scrollRegion.contentW).toBe(44)
		expect(w.adapter.node("/S/Canvas").scrollRegion.contentH).toBe(900)
	end)

	it("clamps rich font sizes to the measurement ceiling in width and line box", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 1000, h = 1000 } })
		local UI = w.UI
		w.present(function()
			return UI.Screen("S")({
				padding = 0,
				UI.VStack("Rows")({
					UI.Text("Huge")({ text = '<font size="200">Lap</font>', rich = true }),
					UI.Text("Ceiling")({ text = '<font size="100">Lap</font>', rich = true }),
					UI.Text("Small")({ text = '<font size="30">Lap</font>', rich = true }),
				}),
			})
		end)
		local huge, ceiling, small = rectOf(w, "/S/Rows/Huge"), rectOf(w, "/S/Rows/Ceiling"), rectOf(w, "/S/Rows/Small")
		expect(huge.w).toBe(ceiling.w)
		expect(huge.h).toBe(ceiling.h)
		expect(small.h < ceiling.h).toBe(true)
		expect(richText.spansOf('<font size="4000">x</font>')[1].size).toBe(100)
		expect(richText.spansOf('<font size="30">x</font>')[1].size).toBe(30)
	end)

	it("takes displayed text and run faces from one parse per changed rich node", function()
		local calls = { parse = 0, display = 0, spans = 0 }
		local realParse, realDisplay, realSpans = richText.parse, richText.displayText, richText.spansOf
		richText.parse = function(...)
			calls.parse += 1
			return realParse(...)
		end
		richText.displayText = function(...)
			calls.display += 1
			return realDisplay(...)
		end
		richText.spansOf = function(...)
			calls.spans += 1
			return realSpans(...)
		end
		local ok, err = pcall(function()
			local w = world.new()
			local UI, text = w.UI, w.Compose.cell("<b>Lap 1</b>")
			w.present(function()
				return UI.Screen("S")({ UI.Text("T")({ text = text, rich = true }) })
			end)
			expect(calls).toEqual({ parse = 1, display = 0, spans = 0 })
			for lap = 2, 6 do
				text:set(`<b>Lap {lap}</b>`)
				w.settle()
			end
			expect(calls).toEqual({ parse = 6, display = 0, spans = 0 })
			local displayed, spans = realParse("<b>Lap</b> &amp; 1")
			expect(displayed).toBe(realDisplay("<b>Lap</b> &amp; 1"))
			expect(spans).toEqual(realSpans("<b>Lap</b> &amp; 1"))
		end)
		richText.parse, richText.displayText, richText.spansOf = realParse, realDisplay, realSpans
		if not ok then
			error(err, 0)
		end
	end)

	it("answers an ellipsis for nonpositive drawable width and preserves empty text", function()
		for _, width in { 0, -5, -400 } do
			expect(textFit.middle({ text = "Coastal circuit", font = "BuilderSans", size = 16, width = width })).toBe(
				"…"
			)
			expect(textFit.middle({ text = "", font = "BuilderSans", size = 16, width = width })).toBe("")
		end
	end)

	it("bounds font-run admission and resets both font memos without changing answers", function()
		local ok, err = pcall(function()
			textMetrics.resetMeasured()
			local base = "BuilderSans#Regular#Normal"
			local function key(i)
				return textMetrics.runKey(base, { { at = i, font = "BuilderSans#Bold#Normal" } })
			end
			local first = textMetrics.runsOf(key(1))
			expect(textMetrics.runsOf(key(1))).toBe(first)
			textMetrics.resetMeasured()
			expect(textMetrics.runsOf(key(1)) ~= first).toBe(true)
			for i = 1, 8200 do
				textMetrics.runsOf(key(i))
				textMetrics.canonicalFont(`Fixture{i}`)
			end
			local a, b = textMetrics.runsOf(key(99999)), textMetrics.runsOf(key(99999))
			expect(a ~= b).toBe(true)
			expect(a).toEqual(b)
			expect(textMetrics.canonicalFont("AfterCap")).toBe("AfterCap#Regular#Normal")
			textMetrics.resetMeasured()
			expect(textMetrics.runsOf(key(99999))).toBe(textMetrics.runsOf(key(99999)))
		end)
		textMetrics.resetMeasured()
		if not ok then
			error(err, 0)
		end
	end)
end)

describe("resolved scroll extents", function()
	it("refuses invalid metric answers without publishing a canvas, then recovers", function()
		local snapshot = require("../src/themes/snapshot")
		local w = world.new()
		local UI = w.UI
		local function metrics(value)
			local m = table.clone(snapshot.neutral())
			m.space = table.clone(m.space)
			m.space.xl = value
			return m
		end
		local function mount()
			w.present(function()
				return UI.Screen("S")({ UI.ScrollView("Canvas")({ axis = "xy", extent = { width = "xl" } }) })
			end)
		end
		for _, value in { 0, -1, math.huge, 0 / 0 } do
			w.env:set("themeMetrics", metrics(value))
			local ok, err = pcall(mount)
			expect(ok).toBe(false)
			expect(string.find(tostring(err), "extent.width", 1, true) ~= nil).toBe(true)
			expect(w.adapter.liveCount()).toBe(0)
		end
		w.env:set("themeMetrics", metrics(600))
		mount()
		expect(w.adapter.node("/S/Canvas").scrollRegion.contentW).toBe(600)
		local ok, err = pcall(function()
			w.env:set("themeMetrics", metrics(-5))
			w.settle()
		end)
		local refusal = if ok then tostring(w.core:lastError()) else tostring(err)
		expect(string.find(refusal, "extent.width", 1, true) ~= nil).toBe(true)
		expect(w.adapter.node("/S/Canvas").scrollRegion.contentW).toBe(600)
		w.env:set("themeMetrics", metrics(800))
		w.settle()
		expect(w.adapter.node("/S/Canvas").scrollRegion.contentW).toBe(800)
	end)
end)

describe("rich font ceiling reaches publication", function()
	it("normalizes only real font-size attributes and preserves literal or ordinary input", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 2000, h = 1000 } })
		local UI = w.UI
		local rows = {
			{ '<font size="200">X</font>', '<font size="100">X</font>' },
			{ "<font size='200'>X</font>", "<font size='100'>X</font>" },
			{ "<font size=200>X</font>", "<font size=100>X</font>" },
			{ [=[<font face='size="200"' size="200">X</font>]=], [=[<font face='size="200"' size="100">X</font>]=] },
			{
				'<!-- <font size="200"> --><font size="30">X</font>',
				'<!-- <font size="200"> --><font size="30">X</font>',
			},
			{ '<font size="100">X</font>', '<font size="100">X</font>' },
			{ '<font size="200">X</font> < broken', '<font size="200">X</font> < broken' },
		}
		for _, row in rows do
			w.present(function()
				return UI.Screen("S")({
					UI.Text("Rich")({ rich = true, text = row[1], width = { type = "fixed", px = 1900 } }),
					UI.Text("Plain")({ text = row[1] }),
				})
			end)
			expect(propsOf(w, "/S/Rich").text).toBe(row[2])
			expect(propsOf(w, "/S/Plain").text).toBe(row[1])
			w.close()
		end
	end)

	it("keeps the caller's markup while initial, updated and revealed text share the ceiling", function()
		local w = world.new({
			viewport = { x = 0, y = 0, w = 600, h = 600 },
			overflowGuardOff = "the moving reveal strip is intentionally clipped",
		})
		local UI = w.UI
		local text = Compose.cell('<font size="200">Lap record on the coastal circuit</font>')
		w.present(function()
			return UI.Screen("S")({
				UI.Text("Source")({
					text = text,
					rich = true,
					reveal = "auto",
					lineLimit = 1,
					width = { type = "fixed", px = 200 },
				}),
			})
		end)
		local function check(expected, raw)
			expect(propsOf(w, "/S/Source").text).toBe(expected)
			expect(text:peek()).toBe(raw)
			for _ = 1, 65 do
				w.tick(1 / 30)
			end
			expect(w.pres.reveal().present).toBe(true)
			expect(propsOf(w, "/__reveal__/Layer/Window/Inner/Full").text).toBe(expected)
		end
		check('<font size="100">Lap record on the coastal circuit</font>', text:peek())
		local raw = '<font size="300" color="#0000ff">Lap record on the coastal circuit</font>'
		text:set(raw)
		w.settle()
		w.tick(1 / 30)
		expect(w.pres.reveal().present).toBe(false)
		check('<font size="100" color="#0000ff">Lap record on the coastal circuit</font>', raw)
		w.close()
		expect(w.adapter.liveCount()).toBe(0)
	end)
end)
