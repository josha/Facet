--!strict

local Verify = require("../tools/vendor/verify/src/core")
local Facet = require("../src")

local function theme(): Facet.ThemePackage
	local definition: Facet.ThemeDefinition = {
		identity = { id = "resolution-test", displayName = "Resolution Test" },
		metrics = { typography = { caption = { size = 10 } } },
		chrome = {
			panel = {
				kind = "layered",
				contentInsets = { top = 12 },
				layers = { { kind = "plaque", size = { w = 160, h = 40 }, overhang = 8 } },
			},
		},
	}
	local package, report = Facet.themes.define(definition)
	assert(package ~= nil and report.ok)
	return package
end

return function(harness: Verify.Harness)
	harness:case("resolution scale follows the short display edge without shrinking compact UI", {
		id = "resolution-scale-display-room",
		run = function()
			for _, size in { { 390, 844 }, { 844, 390 }, { 1024, 1366 }, { 1920, 1080 }, { 3440, 1080 } } do
				Verify.expect(Facet.adaptive.resolutionScale(size[1], size[2])):toBe(1)
			end
			Verify.expect(Facet.adaptive.resolutionScale(2560, 1440)):toBe(4 / 3)
			Verify.expect(Facet.adaptive.resolutionScale(3840, 2160)):toBe(2)
			Verify.expect(Facet.adaptive.resolutionScale(2160, 3840)):toBe(2)
			Verify.expect(Facet.adaptive.resolutionScale(0, 0)):toBe(1)
			Verify.expect(Facet.adaptive.resolutionScale(math.huge, 2160)):toBe(1)
			Verify.expect(Facet.adaptive.resolutionScale(0 / 0, 2160)):toBe(1)
		end,
	})
	harness:case("resolution scaling keeps the reading floor before enlarging text and targets", {
		id = "resolution-scale-reading-floor",
		run = function()
			local base = theme()
			local scaled = Facet.themes.forResolution(base, 3840, 2160)
			Verify.expect(scaled.metrics.typography.caption.size):toBe(28)
			Verify.expect(scaled.metrics.typography.body.size):toBe(base.metrics.typography.body.size * 2)
			Verify.expect(scaled.metrics.controlSizes.regular.height):toBe(base.metrics.controlSizes.regular.height * 2)
			Verify.expect(scaled.metrics.targetSizes.minimum):toBe(base.metrics.targetSizes.minimum * 2)
		end,
	})
	harness:case("resolution scaling is cached idempotent and reversible across display changes", {
		id = "resolution-scale-display-change",
		run = function()
			local base = theme()
			local scaled = Facet.themes.forResolution(base, 3840, 2160)
			Verify.expect(Facet.themes.forResolution(scaled, 3840, 2160) == scaled):toBe(true)
			Verify.expect(Facet.themes.forResolution(scaled, 1920, 1080) == base):toBe(true)
			Verify.expect(Facet.themes.forResolution(base, 390, 844) == base):toBe(true)
		end,
	})
	harness:case("resolution and viewing distance compose in either order without compounding", {
		id = "resolution-scale-ten-foot",
		run = function()
			local base = theme()
			local far = Facet.themes.forDistance(base, "ten-foot")
			local distant4k = Facet.themes.forResolution(far, 3840, 2160)
			local wide = Facet.themes.forResolution(base, 3840, 2160)
			Verify.expect(Facet.themes.forDistance(wide, "ten-foot") == distant4k):toBe(true)
			Verify.expect(distant4k.metrics.typography.caption.size):toBe(far.metrics.typography.caption.size * 2)
			Verify.expect(Facet.themes.forDistance(distant4k, "near") == wide):toBe(true)
			Verify.expect(Facet.themes.forResolution(distant4k, 1920, 1080) == far):toBe(true)
		end,
	})
	harness:case("resolution scaling keeps fantasy chrome content clearances proportional", {
		id = "resolution-scale-chrome",
		run = function()
			local base = theme()
			local scaled = Facet.themes.forResolution(base, 3840, 2160)
			local panel = assert(assert(scaled.chrome).panel)
			Verify.expect(assert(panel.contentInsets).top):toBe(24)
			local plaque = assert(panel.layers)[1]
			local size = plaque.size
			assert(type(size) == "table")
			Verify.expect(size.w):toBe(320)
			Verify.expect(size.h):toBe(80)
			Verify.expect(plaque.overhang):toBe(16)
			Verify.expect(scaled.metrics.motion.normal):toBe(base.metrics.motion.normal)
		end,
	})
	harness:case("custom geometry follows the same reactive resolution scale as controls", {
		id = "resolution-scale-environment",
		run = function()
			local engine = require("./lib/native_engine").new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local base = theme()
			local package = Facet.Compose.cell(Facet.themes.forResolution(base, 3840, 2160))
			local geometry: Facet.ReadOnlyValue<number>? = nil
			local stop = runtime.mount(function()
				local UI = Facet.controls(runtime, { types = engine.types, theme = package })
				geometry = UI.environment().scaled(52)
				return Facet.host(runtime).Folder({})
			end, engine.new("ScreenGui"))
			Verify.expect(assert(geometry):peek()):toBe(104)
			package:set(Facet.themes.forResolution(base, 1920, 1080))
			Verify.expect(assert(geometry):peek()):toBe(52)
			stop()
			runtime:dispose()
		end,
	})
end
