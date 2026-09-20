--!strict
-- Theme-package COMPATIBILITY BASELINE dumper (stage theme-packages-and-skinning).
--
-- Why this exists: migrating the framework's hardcoded metric literals onto
-- semantic theme roles is only safe if the DEFAULT (Facet Neutral) result is
-- byte-identical to what shipped. This walks a control-vocabulary fixture plus
-- every gallery example through a real Facet application over the FakeTarget at
-- three viewports and writes every solved rect and every adapter prop write,
-- deterministically ordered, to the path you name.
--
--   lune run tools/lune/_theme_baseline -- <path>
--
-- THE TARGET IS REQUIRED, and that is a fix (Step 5.5 cleanup ledger C-09). It
-- used to default to `artifacts/theme-packages-and-skinning/baseline-neutral-dump.json`
-- — a STORED comparison input — so running it bare silently overwrote the thing
-- being compared against. That happened on 2026-07-28 and left the Step 3.5 gate
-- red until the cleanup pass found it; a handoff doc carried a prose "do not run
-- this without an argument" warning instead. A required argument needs no warning.
--
-- Today's real callers: `tools/lune/check_flat_baseline` (regenerates to a temp
-- path and diffs against the stored 3.5 baseline with a named allow-list), and a
-- human refreshing `artifacts/rich-skinning-v2/rows/neutral-render-dump.json`.

local process = require("@lune/process")
local serde = require("@lune/serde")
local fs = require("@lune/fs")

local Facet = require("../../src") :: any
local text_metrics = require("../../src/layout/text_metrics")
local fake_target = require("../../tests/lib/fake_target")

local Compose = Facet.Compose

local VIEWPORTS = {
	{ name = "phone-portrait", w = 390, h = 844 },
	{ name = "tablet", w = 820, h = 1180 },
	{ name = "desktop", w = 1280, h = 720 },
}

-- deterministic, shallow, sorted rendering of a prop value
local function fmt(value: any): string
	local kind = type(value)
	if kind == "table" then
		local keys: { string } = {}
		for k in value do
			table.insert(keys, tostring(k))
		end
		table.sort(keys)
		local parts: { string } = {}
		for _, k in keys do
			local v = (value :: any)[k]
			table.insert(parts, `{k}={if type(v) == "table" then "{...}" else tostring(v)}`)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	if kind == "function" then
		return "<fn>"
	end
	if kind == "number" then
		return string.format("%.6g", value)
	end
	return tostring(value)
end

local function snapshotOf(adapter: any): { any }
	local out: { any } = {}
	for _, path in adapter.paths() do
		local node = adapter.node(path)
		local propKeys: { string } = {}
		for k in node.props do
			table.insert(propKeys, k)
		end
		table.sort(propKeys)
		local props: { string } = {}
		for _, k in propKeys do
			table.insert(props, `{k}={fmt(node.props[k])}`)
		end
		local rect = node.rect
		table.insert(out, {
			path = path,
			class = node.class,
			rect = if rect ~= nil then `{rect.x},{rect.y} {rect.w}x{rect.h}` else "nil",
			hit = if adapter.hitRectOf(path) ~= nil
				then `{adapter.hitRectOf(path).x},{adapter.hitRectOf(path).y} `
					.. `{adapter.hitRectOf(path).w}x{adapter.hitRectOf(path).h}`
				else "nil",
			props = table.concat(props, ";"),
		})
	end
	return out
end

-- one fixture render: application -> build -> mount -> refresh -> dump.
-- `build(ctx)` answers `{ screen = component?, present = options?, drive = fn? }`.
local function render(name: string, viewport: any, build: (ctx: any) -> any): any
	text_metrics.resetMeasured()
	text_metrics.resetCalibration()
	local adapter = fake_target.new()
	local core, env, system
	local app = Facet.new({
		newAdapter = function()
			return adapter
		end,
		newInputSystem = function(value)
			core = value
			system = Facet.newActionSystem(value)
			return system
		end,
		bindEnv = function(value)
			env = value
			env:set("viewportRect", { x = 0, y = 0, w = viewport.w, h = viewport.h })
			return function() end
		end,
		-- nothing here animates: the dump is the first settled solve
		connectFrame = function()
			return function() end
		end,
	})
	local presenter = app.presenter
	local built = build({
		Facet = Facet,
		app = app,
		UI = app.controls,
		Compose = Compose,
		env = env,
		core = core,
		actionSystem = system,
	})
	-- an example that owns its own surface mounts it inside `build`
	if built.screen ~= nil then
		app.mount(built.screen, built.present)
	end
	presenter.refresh()
	local out = { fixture = name, viewport = viewport.name, nodes = snapshotOf(adapter), opened = nil :: any }
	-- transient surfaces (the PopupButton panel) only exist while open, and their
	-- row metrics are exactly what the migration touches — so drive them open.
	if built.drive ~= nil then
		built.drive(adapter, presenter)
		presenter.refresh()
		out.opened = snapshotOf(adapter)
	end
	app.dispose()
	return out
end

-- the control vocabulary: every control whose metrics the theme stage migrates
local function controlVocabulary(ctx: any): any
	local UI = ctx.UI
	local function noop() end
	return {
		screen = function()
			return UI.Screen("Vocabulary")({
				padding = 16,
				gap = 8,
				UI.Text("Title")({ text = "Controls", textSize = 24 }),
				UI.Text("Body")({ text = "Every control the theme stage migrates." }),
				UI.Button("Go")({ label = "Go", onActivate = noop }),
				UI.Toggle("Flag")({ label = "Flag", value = Compose.cell(true) }),
				UI.TextField("Field")({ placeholder = "Type here" }),
				UI.Divider("Rule")({}),
				UI.Slider("Volume")({ label = "Volume", value = Compose.cell(6), min = 0, max = 10 }),
				UI.Stepper("Count")({ label = "Count", value = Compose.cell(3), min = 0, max = 9, step = 1 }),
				UI.ProgressView("Load")({ label = "Load", value = 0.4, showValue = true }),
				UI.Label("Save")({ title = "Save changes", icon = "rbxassetid://1" }),
				UI.Picker("Quality")({
					label = "Quality",
					options = { { label = "Low", value = "low" }, { label = "High", value = "high" } },
					selected = Compose.cell("low"),
					-- `style = "segmented"` DECLARED: the frozen render is the STRIP's
					-- nodes, and an undeclared style on this pointer fixture is the
					-- menu family
					style = "segmented",
					-- `indicator = "none"` DELIBERATELY. This fixture is not a screen: it
					-- is the frozen input `check_flat_baseline` regenerates and compares
					-- node-for-node against the stored `control-vocabulary` render, and
					-- that comparison IS the flat-theme byte-compatibility claim.
					-- Letting the sliding-pill default in here would re-pin the framework
					-- claim to make a paint change quiet. The default is swept where it
					-- belongs: the `Picker-indicator` large-text fixture and
					-- `tests/picker_segments.spec`.
					indicator = "none",
				}),
				UI.DisclosureGroup("More")({
					label = "More",
					expanded = Compose.cell(true),
					content = function()
						return UI.Text("Body")({ text = "Hidden detail", textSize = 14 })
					end,
				}),
				UI.Chip("Tag")({ label = "Tag", selected = Compose.cell(false) }),
				UI.PopupButton("Mode")({
					options = { { id = "a", label = "Alpha" }, { id = "b", label = "Beta" } },
					value = Compose.cell("a"),
				}),
				UI.TextInput("Name")({ value = Compose.cell("Ada"), placeholder = "Your name", clearButton = true }),
			})
		end,
		drive = function(adapter: any, _presenter: any)
			adapter.tap("/Vocabulary/Mode/Trigger")
		end,
	}
end

local GALLERY = {
	"01_temperature_converter",
	"02_playlist_table",
	"03_settings_sync",
	"04_confirm_dialog",
	"05_word_game",
	"06_tile_game",
	"07_match3",
}

local results: { any } = {}
for _, viewport in VIEWPORTS do
	table.insert(results, render("control-vocabulary", viewport, controlVocabulary))
	for _, name in GALLERY do
		local module = require("../../examples/gallery/examples/" .. name) :: any
		table.insert(
			results,
			render(name, viewport, function(ctx)
				return module.build(ctx)
			end)
		)
	end
end

local target = process.args[1]
if target == nil or target == "--" then
	target = process.args[2]
end
if target == nil or target == "" then
	print("theme baseline: a target path is REQUIRED — `lune run tools/lune/_theme_baseline -- <path>`")
	print("  (it used to default to the stored comparison baseline, which running it bare then destroyed)")
	process.exit(2)
end
fs.writeFile(target, serde.encode("json", { schema = "facet-theme-baseline/1", fixtures = results }, true))
print(`theme baseline: {#results} renders -> {target}`)
