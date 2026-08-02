--!strict
-- Theme-package COMPATIBILITY BASELINE dumper (stage theme-packages-and-skinning).
--
-- Why this exists: migrating the framework's hardcoded metric literals onto
-- semantic theme roles is only safe if the DEFAULT (Studio Neutral) result is
-- byte-identical to what shipped. This walks a control-vocabulary fixture plus
-- every gallery example through the real mount -> renderer -> FakeTarget stack at
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

local LuauUI = require("../../src") :: any
local customFactory = require("../../src/core/custom")
local mountLib = require("../../src/mount")
local environment = require("../../src/env/environment")
local rendererLib = require("../../src/render/renderer")
local text_metrics = require("../../src/layout/text_metrics")
local fake_target = require("../../tests/lib/fake_target")

local UI = LuauUI.UI

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

-- one fixture render: build -> mount -> present -> refresh -> dump
local function render(name: string, viewport: any, build: (core: any, deps: any) -> any): any
	text_metrics.resetMeasured()
	text_metrics.resetCalibration()
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = viewport.w, h = viewport.h })
	local adapter = fake_target.new()
	local system = LuauUI.newActionSystem(core)
	local presenter = LuauUI.newPresenter(core, env, adapter, system)
	local deps = { env = env, actionSystem = system, presenter = presenter, adapter = adapter }
	local built = build(core, deps)
	presenter.present(built.screen, built.present)
	presenter.refresh()
	local out = { fixture = name, viewport = viewport.name, nodes = snapshotOf(adapter), opened = nil :: any }
	-- transient surfaces (the PopupButton panel) only exist while open, and their
	-- row metrics are exactly what the migration touches — so drive them open.
	if built.drive ~= nil then
		built.drive(adapter, presenter)
		presenter.refresh()
		out.opened = snapshotOf(adapter)
	end
	return out
end

-- the control vocabulary: every control whose metrics the theme stage migrates
local function controlVocabulary(core: any, _deps: any): any
	local slider = LuauUI.newSlider(LuauUI, core, {
		id = "Volume",
		label = "Volume",
		value = core:signal(6),
		min = 0,
		max = 10,
	})
	local stepper = LuauUI.newStepper(LuauUI, core, {
		id = "Count",
		label = "Count",
		value = core:signal(3),
		min = 0,
		max = 9,
		step = 1,
	})
	local progress =
		LuauUI.newProgressView(LuauUI, core, { id = "Load", label = "Load", value = 0.4, showValue = true })
	local label = LuauUI.newLabel(LuauUI, core, { id = "Save", title = "Save changes", icon = "rbxassetid://1" })
	local picker = LuauUI.newPicker(LuauUI, core, {
		id = "Quality",
		label = "Quality",
		options = { { label = "Low", value = "low" }, { label = "High", value = "high" } },
		selected = core:signal("low"),
	})
	local disclosure = LuauUI.newDisclosureGroup(LuauUI, core, {
		id = "More",
		label = "More",
		expanded = core:signal(true),
		content = function()
			return UI.Text({ id = "Body", text = "Hidden detail", textSize = 14 })
		end,
	})
	local chip = LuauUI.newChip(LuauUI, core, { id = "Tag", label = "Tag", selected = core:signal(false) })
	local popup = LuauUI.newPopupButton(LuauUI, core, {
		id = "Mode",
		options = { { id = "a", label = "Alpha" }, { id = "b", label = "Beta" } },
		value = core:signal("a"),
	})
	local input = LuauUI.newTextInput(LuauUI, core, {
		id = "Name",
		value = core:signal("Ada"),
		placeholder = "Your name",
		clearButton = true,
	})
	return {
		screen = UI.Screen({
			id = "Vocabulary",
			padding = 16,
			gap = 8,
			children = {
				UI.Text({ id = "Title", text = "Controls", textSize = 24 }),
				UI.Text({ id = "Body", text = "Every control the theme stage migrates." }),
				UI.Button({ id = "Go", label = "Go" }),
				UI.Toggle({ id = "Flag", label = "Flag", value = core:signal(true) }),
				UI.TextField({ id = "Field", placeholder = "Type here" }),
				UI.Divider({ id = "Rule" }),
				slider.blueprint,
				stepper.blueprint,
				progress.blueprint,
				label.blueprint,
				picker.blueprint,
				disclosure.blueprint,
				chip.blueprint,
				popup.blueprint,
				input.blueprint,
			},
		}),
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
			render(name, viewport, function(core, deps)
				return module.build(LuauUI, core, deps)
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
fs.writeFile(target, serde.encode("json", { schema = "luauui-theme-baseline/1", fixtures = results }, true))
print(`theme baseline: {#results} renders -> {target}`)
