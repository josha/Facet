--!strict
local t = require("./lib/testkit")
local fs = require("@lune/fs")
local Facet = require("../src")
local themes = Facet.themes

local ROOT = "src/ui/"
local KEYS = { "seconds", "duration", "period", "damping", "TweenTime" }
local ALLOWED: { [string]: string } = {
	["toast_schedule.luau|duration = 4"] = "how long a toast stays readable, not motion",
	["nav_modal.luau|duration = 0.001"] = "an age clock for the first styled frame",
	["nav_modal.luau|duration = HELP_DWELL"] = "the hover dwell before help shows, an interaction delay",
	["nav_radial.luau|duration = HOLD"] = "the long-press hold that names an item, an interaction delay",
	["nav_sheet.luau|seconds = SETTLE_LIMIT"] = "the layout-settle wait before a sheet may move, not motion",
}

local function literals(): { string }
	local found = {}
	for _, name in fs.readDir(ROOT) do
		if string.sub(name, -5) == ".luau" and name ~= "themes.luau" then
			local source = fs.readFile(ROOT .. name)
			local line = 0
			for text in string.gmatch(source .. "\n", "(.-)\n") do
				line += 1
				local hits = {}
				for _, key in KEYS do
					for value in string.gmatch(text, key .. "%s*=%s*([%w_%.]+)") do
						if string.match(value, "^[%d%.]+$") or string.match(value, "^[%u_]+$") then
							table.insert(hits, `{key} = {value}`)
						end
					end
				end
				for hit in string.gmatch(text, "TweenInfo%.new%(%s*[%d%.]+") do
					table.insert(hits, hit)
				end
				for hit in string.gmatch(text, "Compose%.easing%.%a+") do
					table.insert(hits, hit)
				end
				for hit in string.gmatch(text, "EasingStyle%.%a+") do
					table.insert(hits, hit)
				end
				for hit in string.gmatch(text, "enter%s*=%s*[%d%.]+") do
					table.insert(hits, hit)
				end
				for hit in string.gmatch(text, "exit%s*=%s*[%d%.]+") do
					table.insert(hits, hit)
				end
				for _, hit in hits do
					if ALLOWED[`{name}|{hit}`] == nil then
						table.insert(found, `{name}:{line}: {hit}`)
					end
				end
			end
		end
	end
	return found
end

t.describe("motion values live in the theme", function()
	t.it("no Facet control hard-codes a duration, easing or spring", function()
		local found = literals()
		if #found > 0 then
			error("hard-coded motion outside the theme:\n" .. table.concat(found, "\n"))
		end
	end)

	t.it("the neutral package carries today's values", function()
		local m: any = themes.neutralPackage().metrics.motion
		t.expect(m.fast).toBe(0.12)
		t.expect(m.normal).toBe(0.2)
		t.expect(m.press).toBe(0.08)
		t.expect(m.hover).toBe(0.15)
		t.expect(m.popover.enter).toBe(0.15)
		t.expect(m.popover.exit).toBe(0.1)
		t.expect(m.dialog.enter).toBe(0.2)
		t.expect(m.dialog.exit).toBe(0.15)
		t.expect(m.reveal.enter).toBe(0.25)
		t.expect(m.reveal.exit).toBe(0.2)
		t.expect(m.sheet.enter).toBe(0.3)
		t.expect(m.sheet.exit).toBe(0.2)
		t.expect(m.toast.enter).toBe(0.2)
		t.expect(m.toast.exit).toBe(0.2)
		t.expect(m.radial.enter).toBe(0.2)
		t.expect(m.radial.exit).toBe(0.12)
		t.expect(m.radial.slot).toBe(0.16)
		t.expect(m.springs.snappy.period).toBe(0.2)
		t.expect(m.springs.quick.period).toBe(0.18)
		t.expect(m.springs.control.period).toBe(0.25)
		t.expect(m.springs.move.period).toBe(0.3)
		t.expect(m.springs.sheet.period).toBe(0.4)
		t.expect(m.materialize.anchored).toBe(0.9)
		t.expect(m.materialize.menu).toBe(0.96)
		t.expect(m.materialize.modal).toBe(0.94)
		t.expect(m.materialize.branch).toBe(0.3)
		t.expect(m.materialize.lift).toBe(1.04)
		t.expect(m.distances.menuSlide).toBe(32)
		t.expect(m.distances.parallax).toBe(0.3)
		t.expect(m.distances.dim).toBe(0.1)
		t.expect(m.easing.present).toBe("outCubic")
		t.expect(m.easing.fade).toBe("outQuad")
		t.expect(m.styles.paint).toBe("Quad")
		t.expect(m.styles.page).toBe("Cubic")
		t.expect(m.styles.fling).toBe("Back")
		t.expect(m.styles.scroll).toBe("Quad")
		t.expect(m.styles.pulse).toBe("Sine")
	end)

	t.it("a derived package retimes a popover without touching Facet", function()
		local package = themes.define({
			identity = {
				id = "motion-probe",
				displayName = "Motion probe",
				version = "1.0.0",
				schemaVersion = themes.SCHEMA,
			},
			metrics = { motion = { popover = { enter = 0.3 } } },
		})
		t.expect((package :: any).metrics.motion.popover.enter).toBe(0.3)
		t.expect((package :: any).metrics.motion.popover.exit).toBe(0.1)
	end)
end)
