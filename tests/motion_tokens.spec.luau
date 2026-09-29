--!strict
local t = require("./lib/testkit")
local fs = require("@lune/fs")
local Facet = require("../src")
local themes = Facet.themes
local Compose = require("../src/vendor/compose/core")
local Roblox = require("../src/vendor/compose/roblox")
local context = require("../src/ui/context")
local engineLib = require("./lib/native_engine")

local function newContext(): (any, () -> ())
	local engine = engineLib.new()
	local runtime = Roblox.createRuntime(engine)
	local ctx: any
	local stop = runtime.mount(function()
		ctx = context(Compose, runtime, { types = engine.types, services = {} })
		return runtime.constructors.Folder({})
	end, engine.new("Folder"))
	return ctx, function()
		stop()
		runtime:dispose()
	end
end

local ROOT = "src/ui/"
local KEYS = { "seconds", "duration", "period", "damping", "TweenTime" }
local ALLOWED: { [string]: string } = {
	["toast_schedule.luau|duration = 4"] = "how long a toast stays readable, not motion",
	["nav_modal.luau|duration = 0.001"] = "an age clock for the first styled frame",
	["nav_modal.luau|duration = HELP_DWELL"] = "the hover dwell before help shows, an interaction delay",
	["nav_radial.luau|duration = HOLD"] = "the long-press hold that names an item, an interaction delay",
	["nav_sheet.luau|seconds = SETTLE_LIMIT"] = "the layout-settle wait before a sheet may move, not motion",
}

local CONSTANTS: { [string]: string } = {
	ARC = "radial geometry",
	CELL = "layout size",
	CELL_PADDING = "layout size",
	CELLS = "layout count",
	CHECKER_CELLS = "layout count",
	COMPACT_HEIGHT = "layout size",
	CORNER_OVERLAP = "layout share",
	DISC = "layout size",
	FLING_MINIMUM = "interaction threshold",
	FLING_SPEED = "interaction threshold",
	FLING_STOP = "interaction threshold",
	FLING_WINDOW = "interaction threshold",
	FULL_SWIPE = "interaction threshold",
	GAP = "layout size",
	HANDLE = "layout size",
	HELD_PULL = "drag resistance, interaction",
	HELP_DWELL = "hover dwell, interaction delay",
	HOLD = "long-press hold, interaction delay",
	KNOB = "layout size",
	MARGIN = "layout size",
	MAX_COLUMNS = "layout count",
	MAX_CONTROL_POINTS = "path limit",
	MAX_DEPTH = "structure limit",
	MAX_LENGTH = "text limit",
	MAX_SAFE = "numeric limit",
	MAX_WINDOW = "layout limit",
	MEASURE = "layout size",
	PADDING = "layout size",
	REFIT_FRAMES = "layout retry count",
	RESISTANCE = "drag resistance, interaction",
	ROW = "layout size",
	SCRUB_PIXELS = "interaction threshold",
	SETTLE_LIMIT = "layout-settle wait, not motion",
	SETTLE_SECONDS = "scrub idle wait, interaction delay",
	SLOP = "interaction threshold",
	SPAN = "layout size",
	STACK = "layout count",
	STICK_DOMINANCE = "interaction threshold",
	STICK_PRESS = "interaction threshold",
	STICK_RELEASE = "interaction threshold",
	TAP = "interaction threshold",
	TRAVEL = "layout size",
	VISIBLE_FRACTION = "layout share",
	YEAR_SPAN = "calendar range",
	PAUSE = "marquee reading pause before it scrolls, a reading delay",
	STICK_SPEED = "stick input rate, interaction",
	RADIO_MARK = "layout size",
	REPEAT_DELAY = "key repeat, an interaction delay",
	PROJECTION_S = "sheet release decision rule",
	DISMISS_FRACTION = "sheet release decision rule",
	POINTER_SLOP = "interaction threshold",
	RING = "layout size",
}
local DECIMALS: { [string]: string } = {
	["nav_path_shapes.luau"] = "unit-square path geometry",
	["text_field.luau|repeatDelay"] = "key repeat, an interaction delay",
	["text_field.luau|repeatInterval"] = "key repeat, an interaction delay",
	["nav_surfaces.luau|math.max(0.01"] = "a size floor, not motion",
}

local function lineAt(source: string, at: number): number
	local _, count = string.gsub(string.sub(source, 1, at), "\n", "")
	return count + 1
end

local function scan(source: string, pattern: string, each: (number, ...string) -> ())
	local init = 1
	while true do
		local found = { string.find(source, pattern, init) }
		if found[1] == nil then
			return
		end
		each(found[1], table.unpack(found, 3))
		init = found[2] + 1
	end
end

local function literals(): { string }
	local found = {}
	for _, name in fs.readDir(ROOT) do
		if string.sub(name, -5) == ".luau" and name ~= "themes.luau" then
			local source = fs.readFile(ROOT .. name)
			local function hit(at: number, text: string)
				if ALLOWED[`{name}|{text}`] == nil then
					table.insert(found, `{name}:{lineAt(source, at)}: {text}`)
				end
			end
			for _, key in KEYS do
				scan(source, "[^%w_]" .. key .. "%s*=%s*([%w_%.]+)", function(at: number, value: string)
					if string.match(value, "^[%d%.]+$") or string.match(value, "^[%u_]+$") then
						hit(at, `{key} = {value}`)
					end
				end)
			end
			for _, pattern in
				{
					"(TweenInfo%.new%(%s*[%d%.]+)",
					"(Compose%.easing%.%a+)",
					"(EasingStyle%.%a+)",
					"([^%w_]enter%s*=%s*[%d%.]+)",
					"([^%w_]exit%s*=%s*[%d%.]+)",
					"(%(%s*1%s*%-[^()]*%)%s*%^%s*[%d%.]+)",
					"(task%.wait%(%s*[%d%.]+)",
					"(task%.delay%(%s*[%d%.]+)",
				}
			do
				scan(source, pattern, function(at: number, text: string)
					hit(at, (string.gsub(string.gsub(text, "^[^%w]+", ""), "%s+", " ")))
				end)
			end
			for _, pattern in
				{
					"\n[ \t]*local[ \t]+([%u][%u_%d]*)[%w_:, \t]*=[ \t]*[%d%.]+",
					"\n[ \t]*[%l_]+%.([%u][%u_%d]*)[ \t]*=[ \t]*[%d%.]+",
				}
			do
				scan(source, pattern, function(at: number, constant: string)
					if CONSTANTS[constant] == nil then
						hit(at + 1, `{constant} = <number>`)
					end
				end)
			end
			if DECIMALS[name] == nil then
				scan(source, "local[ \t]+([%l_][%w_]*)[%w_:, \t]*=[ \t]*%d*%.%d+", function(at: number, left: string)
					if DECIMALS[`{name}|{left}`] == nil then
						hit(at, `local {left} = <decimal>`)
					end
				end)
				scan(source, "(math%.%a+%(%s*%d*%.%d+)", function(at: number, call: string)
					if DECIMALS[`{name}|{call}`] == nil then
						hit(at, call)
					end
				end)
			end
		end
	end
	return found
end

local function readers(): string
	local all = {}
	for _, name in fs.readDir(ROOT) do
		if string.sub(name, -5) == ".luau" then
			table.insert(all, fs.readFile(ROOT .. name))
		end
	end
	return table.concat(all, "\n")
end

t.describe("motion values live in the theme", function()
	t.it("no Facet control hard-codes a duration, easing or spring", function()
		local found = literals()
		if #found > 0 then
			error("hard-coded motion outside the theme:\n" .. table.concat(found, "\n"))
		end
	end)

	t.it("every neutral motion token is read by some control", function()
		local source = readers()
		local m: any = themes.neutralPackage().metrics.motion
		local unread = {}
		local function need(path: string, ...: string)
			for _, form in { ... } do
				if string.find(source, form, 1, true) then
					return
				end
			end
			table.insert(unread, path)
		end
		for key, value in m do
			if type(value) ~= "table" then
				need(key, `"motion.{key}"`, `motion.{key}`, `{key} = "FacetMotion`)
			elseif key == "springs" then
				for role in value do
					need(`springs.{role}`, `motionSpring("{role}")`)
				end
			elseif key == "easing" then
				for role in value do
					need(`easing.{role}`, `motionEase("{role}"`)
				end
			elseif key == "styles" then
				for role in value do
					need(`styles.{role}`, `motionStyle("{role}")`, `styles.{role}`)
				end
			elseif value.enter ~= nil then
				need(key, `motionTiming("{key}")`, `motion.{key}.enter`)
				for field in value do
					if field ~= "enter" and field ~= "exit" then
						need(`{key}.{field}`, `motion.{key}.{field}`)
					end
				end
			else
				for field in value do
					need(`{key}.{field}`, `motion.{key}.{field}`)
				end
			end
		end
		table.sort(unread)
		t.expect(table.concat(unread, ", ")).toBe("")
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
		t.expect(m.easing.trail).toBe("linear")
		t.expect(m.styles.paint).toBe("Quad")
		t.expect(m.styles.page).toBe("Cubic")
		t.expect(m.styles.fling).toBe("Quint")
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

	t.it("each motion reader returns exactly one value, so a call in last position adds no argument", function()
		local ctx, stop = newContext()
		t.expect(select("#", ctx.metric("motion.normal"))).toBe(1)
		t.expect(select("#", ctx.motionEase("present"))).toBe(1)
		t.expect(select("#", ctx.motionStyle("paint"))).toBe(1)
		stop()
	end)

	t.it("define refuses motion values that would break a control", function()
		local bad: { any } = {
			{ springs = { sheet = { period = 0 } } },
			{ springs = { sheet = { period = -0.4 } } },
			{ springs = { control = { damping = 0 } } },
			{ popover = { enter = -1 } },
			{ durations = { tabFade = -0.1 } },
			{ restLimit = 1e9 },
			{ easing = { present = "bogus" } },
			{ styles = { paint = "Bogus" } },
			{ normal = "fast" },
			{ fling = { maxSpeed = 0 } },
		}
		for index, motion in bad do
			local package, report = themes.define({
				identity = { id = `bad-{index}`, displayName = "Bad", version = "1.0.0", schemaVersion = themes.SCHEMA },
				metrics = { motion = motion },
			})
			t.expect(`{index} {package == nil} {#report.errors > 0}`).toBe(`{index} true true`)
		end
	end)

	t.it("a package may turn the row swipe projection off", function()
		local package, report = themes.define({
			identity = {
				id = "no-projection",
				displayName = "No projection",
				version = "1.0.0",
				schemaVersion = themes.SCHEMA,
			},
			metrics = { motion = { fling = { projection = 0 } } },
		})
		t.expect(`{package ~= nil} {#report.errors}`).toBe("true 0")
	end)
end)
