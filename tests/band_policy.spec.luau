--!strict
--[[ THE FOURTH CASE ON `rootPolicy` — `bandSafeContent` (framework-gaps §9).

	THE HOLE THIS CLOSES, in the audit's own words: *"`platformChrome.bandInsets`
	exists and api.md says it is 'what a surface that means to ride the band applies
	instead' — but no policy applies it. So a band-riding surface must present
	`edgeToEdge`, which drops all four insets, and re-spend them by hand."* Two
	shipped consumers did exactly that and said so in their own headers — the HUD
	demo (`examples/gallery/scenarios/hud.luau`) and Rascal Rally's chip band
	(`FacetSponsor/HudScreen.luau`: *"that row is the PLATFORM'S TOPBAR STRIP, and
	it is outside every content-safe root policy by definition"*).

	AND THE SECOND HALF: the HUD's hand-roll was *strictly better* than the shipped
	policy, because it floored each edge against the theme's own gutter and
	`deviceSafeContent` did not. When the consumer's hand-rolled version beats the
	shipped policy, the policy is the bug — so the floor is now the policy's, for
	every content policy, and the hand-roll is deleted rather than copied.

	`edgeToEdge` is NOT floored and that is the one exemption: it is the DECORATION
	policy ("a scrim or a backdrop... has to paint to the edges or it draws a
	rectangle inside the screen with the world showing around it" — renderer.luau),
	so a gutter there would break the thing the policy exists for. The control case
	below is what says so out loud.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local UI = require("../src/blueprint")
local customFactory = require("../src/core/custom")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local composition = require("../src/layout/composition")
local themeSnapshot = require("../src/themes/snapshot")
local fake_target = require("./lib/fake_target")

-- the theme's own step, read rather than written: a package that breathes more
-- moves every number in this file with it
local GUTTER = (themeSnapshot.neutral().space :: any).gutter

--[[ THE LIVE-ENGINE PROFILE, verbatim from the 2026-08-14 Studio measurement the
	`platformChrome` fact was built on (735x413: `TopbarInset` = (164,0)+571x58 and
	the topbar-safe area = x 164..735 / y 0..58 — the same band). ]]
local LIVE = {
	vp = { x = 0, y = 0, w = 735, h = 413 },
	core = { top = 58, bottom = 0, left = 0, right = 0 },
	device = { top = 0, bottom = 0, left = 0, right = 0 },
	topbarSafe = { top = 0, bottom = 355, left = 164, right = 0 },
	bar = { x = 164, y = 0, w = 571, h = 58 },
}

local function envWith(core: any, profile: any): any
	local env = environment.new(core)
	env:set("viewportRect", profile.vp)
	env:set("coreSafeInsets", profile.core)
	env:set("deviceSafeInsets", profile.device)
	env:set("topbarSafeInsets", profile.topbarSafe)
	env:set("topbarInset", profile.bar)
	return env
end

-- mount a blueprint under a policy and hand back the adapter + the env
local function mountUnder(blueprint: any, policy: string, profile: any?): any
	local core = customFactory.new()
	local env = envWith(core, profile or LIVE)
	local mountLib = require("../src/mount")
	local root = mountLib.mount(core, blueprint)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, { rootPolicy = policy })
	controller.initialRender()
	return { core = core, env = env, adapter = adapter, controller = controller }
end

local function plainScreen(): any
	return UI.Screen({
		id = "S",
		children = {
			UI.Box({ id = "Body", width = { type = "fill", weight = 1 }, height = { type = "fill", weight = 1 } }),
		},
	})
end

-- ===== 1. the policy exists, and it spends the fact nothing spent ==========

describe("§9: `bandSafeContent` is the policy that spends `platformChrome.bandInsets`", function()
	it("the renderer accepts it, and names it among the valid values when a typo arrives", function()
		local w = mountUnder(plainScreen(), "bandSafeContent")
		expect(w.adapter.node("/S").rect ~= nil).toBe(true)
		local core = customFactory.new()
		local env = envWith(core, LIVE)
		local mountLib = require("../src/mount")
		local root = mountLib.mount(core, plainScreen())
		local ok, err = pcall(function()
			renderer.attach(core, root, env, fake_target.new(), { rootPolicy = "bandSafeContnt" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "bandSafeContent", 1, true) ~= nil).toBe(true)
	end)

	it("its content rect starts where the BAND starts, not below the platform's whole row", function()
		local w = mountUnder(plainScreen(), "bandSafeContent")
		local chrome = w.env:get("platformChrome"):get()
		-- the fact the audit says nothing spent
		expect(chrome.bandInsets.top).toBe(0)
		expect(chrome.insets.top).toBe(58)
		local rect = w.adapter.node("/S").rect
		expect(rect.y).toBe(chrome.bandInsets.top)
		-- ...and the three edges with no hole in them are the per-edge max of the
		-- platform's own reservation and the theme's gutter
		expect(rect.x).toBe(math.max(chrome.insets.left, GUTTER))
		expect(rect.w).toBe(LIVE.vp.w - math.max(chrome.insets.left, GUTTER) - math.max(chrome.insets.right, GUTTER))
		expect(rect.h).toBe(LIVE.vp.h - chrome.bandInsets.top - math.max(chrome.insets.bottom, GUTTER))
	end)

	it("with NO band reported its TOP is `deviceSafeContent`'s — no branch for a consumer", function()
		local NO_STRIP = {
			vp = { x = 0, y = 0, w = 1280, h = 720 },
			core = { top = 58, bottom = 0, left = 0, right = 0 },
			device = { top = 0, bottom = 0, left = 0, right = 0 },
			topbarSafe = { top = 0, bottom = 0, left = 0, right = 0 },
			bar = { x = 0, y = 0, w = 0, h = 0 },
		}
		local band = mountUnder(plainScreen(), "bandSafeContent", NO_STRIP)
		local device = mountUnder(plainScreen(), "deviceSafeContent", NO_STRIP)
		expect(band.env:get("platformChrome"):get().band).toBe(nil)
		local a, b = band.adapter.node("/S").rect, device.adapter.node("/S").rect
		--[[ THE TOP IS THE WHOLE CLAIM: with no band, `bandInsets` IS `insets`, so a
			consumer needs no branch for a platform that reports no strip. The other
			three edges differ by the theme's own gutter, which THIS policy floors and
			`deviceSafeContent` does not yet (the deferral below). ]]
		expect(a.y).toBe(b.y)
		expect(a.y + a.h).toBe(b.y + b.h - GUTTER)
		expect(a.x).toBe(b.x + GUTTER)
	end)
end)

-- ===== 2. the gutter floor, on every content policy ========================

describe("§9: `bandSafeContent` floors its other three edges at the theme's own gutter", function()
	local ZERO = {
		vp = { x = 0, y = 0, w = 400, h = 300 },
		core = { top = 0, bottom = 0, left = 0, right = 0 },
		device = { top = 0, bottom = 0, left = 0, right = 0 },
		topbarSafe = { top = 0, bottom = 0, left = 0, right = 0 },
		bar = { x = 0, y = 0, w = 0, h = 0 },
	}

	it("a platform reporting NO lateral inset still leaves the theme's gutter", function()
		local w = mountUnder(plainScreen(), "bandSafeContent", ZERO)
		local rect = w.adapter.node("/S").rect
		-- three edges floored; the TOP is the platform's and is not (ADR-0027)
		expect(`{rect.x},{rect.y},{rect.w},{rect.h}`).toBe(`{GUTTER},0,{400 - GUTTER * 2},{300 - GUTTER}`)
	end)

	it("a REAL inset bigger than the gutter still wins — the floor is a floor, not a replacement", function()
		local DEEP = {
			vp = { x = 0, y = 0, w = 400, h = 300 },
			core = { top = 44, bottom = 0, left = 0, right = 0 },
			device = { top = 0, bottom = 34, left = 0, right = 0 },
			topbarSafe = { top = 0, bottom = 0, left = 0, right = 0 },
			bar = { x = 0, y = 0, w = 0, h = 0 },
		}
		local w = mountUnder(plainScreen(), "bandSafeContent", DEEP)
		local rect = w.adapter.node("/S").rect
		expect(rect.y).toBe(44) -- no band: `bandInsets` IS `insets`
		expect(rect.h).toBe(300 - 44 - 34)
		expect(rect.x).toBe(GUTTER)
	end)

	it("THE OTHER TWO CONTENT POLICIES ARE UNTOUCHED, and that is a DEFERRAL rather than a decision", function()
		--[[ The audit's §9 asks for the gutter to floor EVERY content policy, and
			this round ships it on the band policy alone. The reason is a measurement
			and it is recorded in `docs/handoff/G8G9-OWED-LIVE-WORK.md` §5: built the
			audit's way, `tests/overflow_sweep.spec.luau` files 255 findings across 51
			of its 95 scenarios, 249 of them at the two narrowest swept viewports —
			content that no longer fits its own box on the device class the gutter
			exists to protect.

			This case PINS the deferral so the next reader meets it as a decision with
			a number rather than as an absence. It fails the day the floor is widened,
			which is exactly when its own comment should be re-read. ]]
		for _, policy in { "coreSafeContent", "deviceSafeContent" } do
			local w = mountUnder(plainScreen(), policy, ZERO)
			local rect = w.adapter.node("/S").rect
			expect(`{policy} {rect.x},{rect.y},{rect.w},{rect.h}`).toBe(`{policy} 0,0,400,300`)
		end
	end)

	it("CONTROL: `edgeToEdge` is EXEMPT — a scrim still reaches the glass on all four sides", function()
		local w = mountUnder(plainScreen(), "edgeToEdge", ZERO)
		local rect = w.adapter.node("/S").rect
		expect(`{rect.x},{rect.y},{rect.w},{rect.h}`).toBe("0,0,400,300")
	end)
end)

-- ===== 3. the topbar zone is inset to the free band ========================

local function hudScreen(withTopbar: boolean): any
	local regions: { any } = {}
	if withTopbar then
		table.insert(
			regions,
			UI.Region({
				id = "Strip",
				group = "topbar",
				rank = 1,
				-- `fill`, so the region takes the strip and its content can centre in
				-- it — the same word it means in a lane (rule 6)
				sizing = "fill",
				children = {
					UI.Box({ id = "Chip", width = { type = "fixed", px = 90 }, height = { type = "fixed", px = 24 } }),
				},
			})
		)
	end
	table.insert(
		regions,
		UI.Region({
			id = "Left",
			group = "topLeft",
			rank = 2,
			children = {
				UI.Box({ id = "Btn", width = { type = "fixed", px = 60 }, height = { type = "fixed", px = 40 } }),
			},
		})
	)
	return UI.Screen({
		id = "S",
		children = {
			UI.Composition({
				id = "H",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				groups = composition.HUD_GROUPS,
				arrangements = { composition.HUD },
				children = regions,
			}),
		},
	})
end

describe("§9: the `topbar` zone is inset to `platformChrome.band`, by the framework", function()
	it("the row sits INSIDE the free strip — level with the platform's buttons, never on them", function()
		local w = mountUnder(hudScreen(true), "bandSafeContent")
		local chrome = w.env:get("platformChrome"):get()
		local strip = w.adapter.node("/S/H/Strip").rect
		expect(strip.x).toBe(chrome.band.x)
		expect(strip.w).toBe(chrome.band.w)
		expect(strip.y).toBe(chrome.band.y)
		expect(strip.h).toBe(chrome.band.h)
	end)

	it("...and the lanes start BELOW the band, so the top-left cluster is clear by construction", function()
		local w = mountUnder(hudScreen(true), "bandSafeContent")
		local chrome = w.env:get("platformChrome"):get()
		local btn = w.adapter.node("/S/H/Left").rect
		expect(btn.y).toBe(chrome.band.y + chrome.band.h)
	end)

	it("a composition that declares NO topbar region reserves the platform's whole row anyway", function()
		--[[ THE SAFE DEFAULT, and it is what makes the new policy additive in risk
			rather than a trap: a surface presenting `bandSafeContent` whose composition
			never mentions `topbar` gets exactly the lane band `deviceSafeContent` would
			have given it. Only a DECLARED topbar region reaches into the strip. ]]
		local band = mountUnder(hudScreen(false), "bandSafeContent")
		local device = mountUnder(hudScreen(false), "deviceSafeContent")
		local a, b = band.adapter.node("/S/H/Left").rect, device.adapter.node("/S/H/Left").rect
		-- the LANE BAND is what this case is about, and it starts at the platform's
		-- whole reservation either way; the lateral gutter is the policy's own
		expect(`{a.y},{a.w},{a.h}`).toBe(`{b.y},{b.w},{b.h}`)
		expect(a.y).toBe(58)
	end)

	--[[ ADOPT-round fix (framework-gaps-phase2, 2026-08-23): a composition that
		DOES declare a `topbar` region, on a platform that reports NO strip at
		all (`platformChrome.band` nil — a real, if TRANSIENT, live rung: it goes
		nil at boot before the platform's first push and on a measured
		rotation-recovery frame, NM-H4a in `environment.luau`, not only under
		Lune), used to measure and place that row against a zero-area placeholder
		(`composition_resolve.localBand`'s own fallback for "nothing to ride"),
		collapsing a real row of content to WIDTH ZERO — discovered live by Rascal
		Rally's chip-band cutover (`facet_large_text_sweep.spec.luau`: a
		measured, real truncation on value-bearing text). The row should get
		exactly what the "no topbar region declared" case above gets: the
		composition's own offered width, not a strip that does not exist. ]]
	it("a DECLARED topbar region on a platform reporting NO strip is NOT zero-width", function()
		local NO_STRIP = {
			vp = { x = 0, y = 0, w = 1280, h = 720 },
			core = { top = 58, bottom = 0, left = 0, right = 0 },
			device = { top = 0, bottom = 0, left = 0, right = 0 },
			topbarSafe = { top = 0, bottom = 0, left = 0, right = 0 },
			bar = { x = 0, y = 0, w = 0, h = 0 },
		}
		local w = mountUnder(hudScreen(true), "bandSafeContent", NO_STRIP)
		expect(w.env:get("platformChrome"):get().band).toBe(nil)
		local strip = w.adapter.node("/S/H/Strip").rect
		-- the composition's own offer, not a free-strip rect nobody published —
		-- the byte-identical answer a composition with NO `topbar` region gets
		local plain = mountUnder(hudScreen(false), "bandSafeContent", NO_STRIP)
		local plainH = plain.adapter.node("/S/H").rect
		expect(strip.w).toBe(plainH.w)
		expect(strip.w > 0).toBe(true)
		-- the row still floors at ITS OWN content (the `Chip` box declared inside
		-- it, 24px tall), not at a platform band's height that does not exist
		expect(strip.h).toBe(24)
	end)

	--[[ REVIEW ROUND 2 FINDING (ADOPT round, same day as the width fix above):
		`bandReserve` had a SECOND read of the sentinel, in the `hasExclusions`
		branch — `elseif hasExclusions and spanActive[BAND_ZONE] then
		math.max(0, bandBox.h)`, gated on `bandBox == nil` alone, not
		`hasRealBand`. On a real-but-degenerate band (`composition_resolve
		.localBand` returns the SAME `{x=0,w=0,h=0,reserve=N}` shape whenever the
		band's own width/height clamp to zero, whether or not the platform
		published a band fact at all — `reserve` stays a REAL, independently
		computed number in that case, `fullTop - originY`) the lane band would
		have read the sentinel's `.h` (0) as its floor instead of the platform's
		real top reservation — silently discarding it exactly where a live host
		that declares BOTH `exclusions` AND a `topbar` region needs it most
		(`examples/gallery/scenarios/hud.luau:2240` declares `exclusions`, on this
		same `rootPolicy`).

		Tested at `composition.resolve()`'s own level, not through `mountUnder`:
		the upstream chain that makes `reserve` nonzero while the band's own
		width/height are zero (a real band whose CLAMPED width/height fall to
		zero while its ORIGIN still shrank `bandInsets` below the surface's full
		reservation) is a narrow enough environment fact to construct that this
		module's own documented `ResolveCtx.band` contract — accept exactly this
		shape, `{x,w,h,reserve}` with any of the four independently zero or not —
		is the more direct thing to hold to account. ]]
	it(
		"the RESERVE still floors the lanes on a sentinel band with exclusions declared and an active topbar row",
		function()
			local SIZES: { [string]: { { w: number, h: number } } } = {
				-- smaller than `reserve` on purpose: the row's OWN height is not what
				-- this case is proving
				Chip = { { w = 90, h = 10 } },
				Btn = { { w = 60, h = 40 } },
			}
			local ctx: any = {
				measure = function(id: string, form: number, _w: number, _h: number): (number, number)
					local list = SIZES[id]
					local s = list[math.min(form, #list)]
					return s.w, s.h
				end,
				exclusions = { { x = 0, y = 0, w = 10, h = 10 } },
				band = { x = 0, w = 0, h = 0, reserve = 25 },
			}
			local decl = {
				groups = composition.HUD_GROUPS,
				arrangements = { composition.HUD },
				regions = {
					{ id = "Chip", group = "topbar", rank = 1, forms = 1, sizing = "fill" },
					{ id = "Btn", group = "topLeft", rank = 2, forms = 1 },
				},
			}
			local r = composition.resolve(decl :: any, { w = 400, h = 300 }, ctx)
			-- the floor is the RESERVE (25) — the platform's whole top reservation —
			-- not the sentinel's own zero height, and not the topbar row's measured
			-- 10px either: the lane clears whichever of the two is taller, exactly
			-- as "a composition that declares NO topbar region" does two tests up
			expect(r.lanes[1].rect.y).toBe(25)
		end
	)
end)
