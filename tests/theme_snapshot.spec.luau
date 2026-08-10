--!strict
-- Theme SNAPSHOT resolution (ADR-0019 §2): one frozen metric authority,
-- composed EXACTLY ONCE in the documented order. The composition order is the
-- whole contract — the ten-foot floor and the preferred-text reservation are
-- applied by the existing environment/measure seams, so applying them here too
-- would double them, and the accessibility floor must only ever clamp UP.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local themes = require("../src/themes/package")
local snapshot = require("../src/themes/snapshot")
local defaultStyle = require("../src/tokens/default_style")
local customFactory = require("../src/core/custom")
local environment = require("../src/env/environment")

local function derive(metrics: any, id: string?): any
	local pkg, report = themes.define({
		base = snapshot.neutralPackage(),
		identity = {
			id = id or "derived",
			displayName = "Derived",
			schemaVersion = themes.SCHEMA,
			version = "1.0.0",
		},
		metrics = metrics,
	})
	assert(pkg ~= nil, "derive: " .. (if report.errors[1] then report.errors[1].message else "?"))
	return pkg
end

describe("themes.neutral: Studio Neutral reproduces the pre-theme literals", function()
	it("reads its shared values from default_style rather than restating them", function()
		local snap = snapshot.neutral()
		expect(snap.type.caption.size).toBe(defaultStyle.type.caption)
		expect(snap.type.body.size).toBe(defaultStyle.type.body)
		expect(snap.type.title.size).toBe(defaultStyle.type.title)
		expect(snap.space.xs).toBe(defaultStyle.space.xs)
		expect(snap.space.xl).toBe(defaultStyle.space.xl)
		expect(snap.radii.panel).toBe(defaultStyle.radii.panel)
		expect(snap.strokes.hairline).toBe(defaultStyle.strokes.hairline)
		expect(snap.motion.fast).toBe(defaultStyle.motion.fast)
		expect(snap.targetSizes.minimum).toBe(defaultStyle.targetSizes.minimum)
	end)

	it("carries the semantic roles this stage added, at the values they replaced", function()
		local snap = snapshot.neutral()
		expect(snap.type.control.size).toBe(18) -- renderer Button/TextField text
		expect(snap.controlSizes.compact.height).toBe(36) -- PopupButton menu row
		expect(snap.controlSizes.regular.height).toBe(44) -- inline row / touch floor
		expect(snap.controlSizes.large.height).toBe(56) -- touch-sheet row
		expect(snap.controlSizes.regular.iconSize).toBe(20) -- Label icon default
		expect(snap.controls.button.padding).toBe(12)
		expect(snap.controls.slider.thumbSize).toBe(20)
		expect(snap.controls.slider.railHeight).toBe(6)
		expect(snap.controls.slider.readoutMinWidth).toBe(40)
		expect(snap.controls.progress.trackHeight).toBe(6)
		expect(snap.controls.progress.rowMinHeight).toBe(20)
		expect(snap.controls.popup.triggerHeight).toBe(40)
		expect(snap.controls.textInput.fieldHeight).toBe(44)
		expect(snap.controls.textInput.clearSize).toBe(28)
		expect(snap.controls.textInput.padding).toBe(12)
		expect(snap.controls.toggle.minHeight).toBe(28)
		expect(snap.controls.toggle.trackWidth).toBe(44)
		expect(snap.controls.toggle.trackInset).toBe(12)
		expect(snap.controls.stepper.valueMinWidth).toBe(32)
		expect(snap.controls.label.gap).toBe(6)
		expect(snap.controls.image.defaultSize).toBe(48)
		expect(snap.controls.table.cellTextSize).toBe(15)
		expect(snap.controls.table.headerHeight).toBe(28)
	end)

	it("every role carries the canonical font descriptor and the 1.2 line height", function()
		local snap = snapshot.neutral()
		for _, role in themes.REQUIRED_TYPE_ROLES do
			expect(snap.type[role].fontKey).toBe("BuilderSans#Regular#Normal")
			expect(snap.type[role].lineHeight).toBe(1.2)
		end
	end)

	it("is frozen, shared and identity-stable (the env default must be immutable)", function()
		local snap = snapshot.neutral()
		expect(table.isfrozen(snap)).toBe(true)
		expect(table.isfrozen(snap.controls.slider)).toBe(true)
		expect(snapshot.neutral()).toBe(snap)
	end)

	it("carries its package identity and stamp for inspection", function()
		local snap = snapshot.neutral()
		expect(snap.identity.packageId).toBe("studio-neutral")
		expect(snap.identity.themeName).toBe("Dark")
		expect(#snap.identity.stamp).toBe(8)
	end)
end)

describe("themes.resolve: composition happens exactly once, in ADR order", function()
	it("1. authored metrics are the base", function()
		local snap = snapshot.resolve(derive({ space = { m = 20 } }), nil, {})
		expect(snap.space.m).toBe(20)
	end)

	it("2. the ten-foot floor is RECORDED, never multiplied into the authored sizes", function()
		local near = snapshot.resolve(snapshot.neutralPackage(), nil, { displaySize = "Medium" })
		local far = snapshot.resolve(snapshot.neutralPackage(), nil, { displaySize = "Large" })
		expect(near.density).toBe("near")
		expect(far.density).toBe("ten-foot")
		-- the SAME authored size on both: env.typographyScale/typographyPaintScale
		-- already compose the 1.5 floor at the measure and paint seams, so scaling
		-- here would apply it twice
		expect(far.type.body.size).toBe(near.type.body.size)
		expect(far.space.m).toBe(near.space.m)
	end)

	it("3. preferred-text reservation inputs are carried through, not re-applied", function()
		local snap = snapshot.resolve(snapshot.neutralPackage(), nil, {
			preferredTextSize = 1.5,
			preferredTextOffset = 8,
		})
		expect(snap.preferredText.multiplier).toBe(1.5)
		expect(snap.preferredText.offset).toBe(8)
		expect(snap.type.body.size).toBe(defaultStyle.type.body) -- untouched
	end)

	it("4. the accessibility floor clamps UP and never down", function()
		local roomy = snapshot.resolve(derive({ targetSizes = { minimum = 56 } }, "roomy"), nil, {})
		expect(roomy.targetSizes.minimum).toBe(56) -- a theme may enlarge a target
		-- ...and it can never shrink one: the package gate already refuses a value
		-- below the floor, and resolve clamps whatever reaches it
		local _, report = themes.define({
			base = snapshot.neutralPackage(),
			identity = { id = "small", displayName = "Small", schemaVersion = themes.SCHEMA, version = "1.0.0" },
			metrics = { targetSizes = { minimum = 30 } },
		})
		expect(report.ok).toBe(false)
	end)

	it("5. explicit overrides apply last and are recorded as theme-independent", function()
		local snap = snapshot.resolve(snapshot.neutralPackage(), nil, {}, {
			["space.m"] = 32,
			["controls.slider.thumbSize"] = 26,
		})
		expect(snap.space.m).toBe(32)
		expect(snap.controls.slider.thumbSize).toBe(26)
		-- deterministic, sorted, inspectable
		expect(#snap.overrides).toBe(2)
		expect(snap.overrides[1].path).toBe("controls.slider.thumbSize")
		expect(snap.overrides[2].path).toBe("space.m")
		-- an override on one property leaves the rest theme-owned
		expect(snap.space.l).toBe(defaultStyle.space.l)
	end)

	it("an override cannot defeat the accessibility floor", function()
		local snap = snapshot.resolve(snapshot.neutralPackage(), nil, {}, { ["targetSizes.minimum"] = 10 })
		expect(snap.targetSizes.minimum).toBe(44)
	end)

	it("an override naming no metric is an error, not a silent no-op", function()
		expect(function()
			snapshot.resolve(snapshot.neutralPackage(), nil, {}, { ["space.enormous"] = 99 })
		end).toThrow()
	end)

	it("resolution is deterministic: the same inputs give equal values", function()
		local a = snapshot.resolve(snapshot.neutralPackage(), nil, { displaySize = "Large" }, { ["space.m"] = 18 })
		local b = snapshot.resolve(snapshot.neutralPackage(), nil, { displaySize = "Large" }, { ["space.m"] = 18 })
		expect(a.space.m).toBe(b.space.m)
		expect(a.identity.stamp).toBe(b.identity.stamp)
		expect(a.density).toBe(b.density)
	end)

	it("selects a named theme and rejects one the package does not declare", function()
		local pkg = themes.define({
			base = snapshot.neutralPackage(),
			identity = { id = "duo", displayName = "Duo", schemaVersion = themes.SCHEMA, version = "1.0.0" },
			style = {
				defaultTheme = "Dark",
				themes = {
					{ name = "Dark", colors = defaultStyle.colors, extra = defaultStyle.extra },
					{ name = "Light", colors = defaultStyle.colors, extra = defaultStyle.extra },
				},
			},
		})
		expect(snapshot.resolve(pkg, "Light", {}).identity.themeName).toBe("Light")
		expect(snapshot.resolve(pkg, nil, {}).identity.themeName).toBe("Dark")
		expect(function()
			snapshot.resolve(pkg, "Sepia", {})
		end).toThrow()
	end)

	it("a nineSlice recipe's contentInsets reach the snapshot's slot inset", function()
		local pkg = themes.define({
			base = snapshot.neutralPackage(),
			identity = { id = "sliced", displayName = "Sliced", schemaVersion = themes.SCHEMA, version = "1.0.0" },
			assets = { frame = { contentId = "rbxassetid://7" } },
			chrome = {
				panel = {
					kind = "nineSlice",
					asset = "frame",
					contentInsets = { top = 4, right = 4, bottom = 4, left = 4 },
					fallback = "native",
				},
			},
		})
		local snap = snapshot.resolve(pkg, nil, {})
		-- the slot's authored inset PLUS what the decoration reserves
		expect(snap.insets.panel.top).toBe(defaultStyle.space.m + 4)
		expect(snap.insets.control.top).toBe(12) -- an unslotted native slot is untouched
	end)
end)

describe("metric-name resolution", function()
	local snap = snapshot.neutral()

	it("resolves spacing steps, dotted paths, and their negation", function()
		expect(snapshot.resolveNumber(snap, "m")).toBe(defaultStyle.space.m)
		expect(snapshot.resolveNumber(snap, "targetSizes.minimum")).toBe(44)
		expect(snapshot.resolveNumber(snap, "controls.slider.thumbSize")).toBe(20)
		expect(snapshot.resolveNumber(snap, "controls.rowActions.buttonMinWidth")).toBe(64)
		expect(snapshot.resolveNumber(snap, "controls.rowActions.editAffordance")).toBe(28)
		expect(snapshot.resolveNumber(snap, "-s")).toBe(-defaultStyle.space.s)
		expect(snapshot.resolveNumber(snap, 17)).toBe(17)
		expect(snapshot.resolveNumber(snap, "nope.nope")).toBeNil()
	end)

	it("resolveSize takes a typography role, a metric path, or a literal", function()
		expect(snapshot.resolveSize(snap, "heading")).toBe(defaultStyle.type.heading)
		expect(snapshot.resolveSize(snap, "control")).toBe(18)
		expect(snapshot.resolveSize(snap, "controls.table.cellTextSize")).toBe(15)
		expect(snapshot.resolveSize(snap, 13)).toBe(13)
		expect(snapshot.resolveSize(snap, nil)).toBeNil()
	end)

	it("resolveSides and resolveDim keep their shape and pass numbers through", function()
		expect(snapshot.resolveSides(snap, "m")).toBe(defaultStyle.space.m)
		expect(snapshot.resolveSides(snap, 9)).toBe(9)
		local sides = snapshot.resolveSides(snap, { left = "s", right = 3 })
		expect(sides.left).toBe(defaultStyle.space.s)
		expect(sides.right).toBe(3)
		local dim = snapshot.resolveDim(snap, { type = "minMax", min = "targetSizes.minimum" })
		expect(dim.type).toBe("minMax")
		expect(dim.min).toBe(44)
		local plain = { type = "fixed", px = 12 }
		expect(snapshot.resolveDim(snap, plain)).toBe(plain) -- untouched, not cloned
	end)

	it("names the canonical vocabulary for the schema's closed-set validation", function()
		expect(snapshot.isSpaceStep("xl")).toBe(true)
		expect(snapshot.isSpaceStep("huge")).toBe(false)
		expect(snapshot.isTypeRole("control")).toBe(true)
		expect(snapshot.isTypeRole("caption")).toBe(true)
		expect(snapshot.isTypeRole("subtitle")).toBe(false)
		expect(snapshot.isMetricPath("controlSizes.large.height")).toBe(true)
		expect(snapshot.isMetricPath("controlSizes.enormous.height")).toBe(false)
		expect(snapshot.isMetricPath("m")).toBe(false) -- a bare step is not a path
	end)
end)

describe("the themeMetrics environment fact", function()
	it("defaults to Studio Neutral and is a plain per-key signal", function()
		local core = customFactory.new()
		local env = environment.new(core)
		expect(env:get("themeMetrics"):get()).toBe(snapshot.neutral())
		local swapped = snapshot.resolve(derive({ space = { m = 24 } }, "wide"), nil, {})
		env:set("themeMetrics", swapped)
		expect(env:get("themeMetrics"):get().space.m).toBe(24)
	end)

	it("a themeMetrics change notifies only its own subscribers", function()
		local core = customFactory.new()
		local env = environment.new(core)
		local themeSeen, viewportSeen = 0, 0
		core:observe(env:get("themeMetrics"), function()
			themeSeen += 1
		end)
		core:observe(env:get("viewportRect"), function()
			viewportSeen += 1
		end)
		env:set("themeMetrics", snapshot.resolve(derive({ space = { m = 24 } }, "wide2"), nil, {}))
		expect(themeSeen).toBe(1)
		expect(viewportSeen).toBe(0)
	end)
end)
