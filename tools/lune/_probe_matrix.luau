-- TEMPORARY probe (RS-A16-D2/D3): headless ornament-vs-neighbour sweep.
local LuauUI = require("../../src") :: any
local fake_target = require("../../tests/lib/fake_target")
local chrome_slots = require("../../src/tokens/chrome_slots")
local scenario = require("../../examples/gallery/scenarios/theme_authoring") :: any

local PACKAGES = {
	fantasy_ornate = require("../../examples/themes/fantasy_ornate"),
	pixel_quest = require("../../examples/themes/pixel_quest"),
	glossy_touch = require("../../examples/themes/glossy_touch"),
	compact_pointer = require("../../examples/themes/compact_pointer"),
	fantasy_parchment = require("../../examples/themes/fantasy_parchment"),
	classic_desktop = require("../../examples/themes/classic_desktop"),
}

local function makeWorld(facts: any)
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	for k, v in facts do
		env:set(k, v)
	end
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	adapter.scrollBarThickness = 8
	local presenter = LuauUI.newPresenter(core, env, adapter, system)
	local chromeState = chrome_slots.newState(nil)
	local ctx: any
	ctx = {
		LuauUI = LuauUI,
		core = core,
		env = env,
		adapter = adapter,
		presenter = presenter,
		actionSystem = system,
		record = function() end,
		flags = {},
		themePackages = PACKAGES,
		themeChrome = {
			setPackage = function(package: any?): boolean
				return chromeState.setPackage(package)
			end,
			census = function()
				return chromeState.census()
			end,
			setAssetLoaded = function(name: string, ok: boolean): boolean
				return chromeState.setAssetLoaded(name, ok)
			end,
			assetsToPreload = function(policy: string)
				return chrome_slots.assetsToPreload(chromeState.package(), policy)
			end,
		},
		themeController = function()
			return nil
		end,
		geometry = function(paths: { string })
			local out: any = {}
			for _, path in paths do
				local node = adapter.node(path)
				if node ~= nil and node.rect ~= nil then
					out[path] = node.rect
				end
			end
			return out
		end,
		nativeStyle = {
			styledOf = function()
				return nil
			end,
			dumpNode = function(path: string): any
				return { path = path }
			end,
			mountIdentity = function()
				return {}
			end,
			info = function()
				return { active = false }
			end,
		},
	}
	local built = scenario.build(ctx)
	local handle = presenter.present(built.screen, built.present)
	presenter.refresh()
	return { ctx = ctx, built = built, adapter = adapter, presenter = presenter, handle = handle, env = env }
end

local world = makeWorld({
	viewportRect = { x = 0, y = 0, w = 1232, h = 1067 },
	coreSafeInsets = { top = 58, bottom = 0, left = 0, right = 0 },
})
print("== flat: node classes present")
local seen: { [string]: number } = {}
for _, path in world.adapter.paths() do
	local n = world.adapter.node(path)
	seen[n.class] = (seen[n.class] or 0) + 1
end
for class, count in seen do
	print("  ", class, count)
end
print("== sample flat node dumps")
for _, path in
	{
		"/AdaptiveScreen",
		"/AdaptiveScreen/BodyScroll/Body/Hud/SaveLabel",
		"/AdaptiveScreen/BodyScroll/Body/Hud/Media",
		"/AdaptiveScreen/BodyScroll/Body/Hud/Download/Bar",
		"/AdaptiveScreen/BodyScroll/Body/Hud/Download/Bar/Fill",
		"/AdaptiveScreen/BodyScroll/Body/Hud/Stats/StatPlate1",
		"/AdaptiveScreen/BodyScroll/Body/Hud/SaveLabel/Title",
	}
do
	local n = world.adapter.node(path)
	if n == nil then
		print("  MISSING", path)
	else
		local props = n.props or {}
		print(
			"  ",
			path,
			n.class,
			`rect {n.rect and `{n.rect.x},{n.rect.y} {n.rect.w}x{n.rect.h}` or "nil"}`,
			`surface={tostring(props.surface)} text={tostring(props.text)} textSize={tostring(props.textSize)} font={tostring(
				props.font
			)} meta={tostring(props.meta)}`
		)
	end
end

print("== install fantasy_ornate")
local res = world.built.steps.installPackage(nil, "fantasy_ornate")
print("  install:", res.ok, res.applied and res.applied.packageId)
world.presenter.refresh()
local pkg = world.env:get("themeMetrics"):get()
print(
	"  chromeOutsets:",
	(function()
		local s = ""
		for slot, sides in pkg.chromeOutsets do
			s ..= `{slot}={sides.top},{sides.right},{sides.bottom},{sides.left} `
		end
		return s
	end)()
)
print("  panel insets:", pkg.chromeInsets.panel and pkg.chromeInsets.panel.top)

for _, path in
	{
		"/AdaptiveScreen/BodyScroll/Body/Hud/SaveLabel",
		"/AdaptiveScreen/BodyScroll/Body/Hud/SaveLabel/Title",
		"/AdaptiveScreen/BodyScroll/Body/Hud/Media",
		"/AdaptiveScreen/BodyScroll/Body/Hud/Stats/StatPlate1",
		"/AdaptiveScreen/BodyScroll/Body/Hud/Stats/Stat1",
	}
do
	local n = world.adapter.node(path)
	print("  ", path, n and n.class, n and n.rect and `{n.rect.x},{n.rect.y} {n.rect.w}x{n.rect.h}`)
end
print("  diagnostics:", #world.handle.controller.diagnostics())
for _, d in world.handle.controller.diagnostics() do
	print("    ", d.node, d.issue)
end

print("== handle keys")
for k, v in world.handle do
	print("  ", k, typeof(v))
end
print("== stat paths")
for _, path in world.adapter.paths() do
	if string.find(path, "Stat") ~= nil or string.find(path, "Tile") ~= nil then
		local n = world.adapter.node(path)
		print(
			"  ",
			path,
			n.class,
			n.rect and `{n.rect.x},{n.rect.y} {n.rect.w}x{n.rect.h}`,
			tostring((n.props or {}).surface)
		)
	end
end

print("== text node props under ornate")
local shown = 0
for _, path in world.adapter.paths() do
	local n = world.adapter.node(path)
	if n.class == "Text" and shown < 6 then
		shown += 1
		local keys = {}
		for k, v in (n.props or {}) do
			table.insert(keys, `{k}={tostring(v)}`)
		end
		table.sort(keys)
		print("  ", path, `{n.rect.w}x{n.rect.h}`, table.concat(keys, " "))
	end
end
print("== bar nodes under ornate")
for _, path in world.adapter.paths() do
	if string.find(path, "Bar") ~= nil or string.find(path, "Volume") ~= nil then
		local n = world.adapter.node(path)
		print("  ", path, n.class, `{n.rect.x},{n.rect.y} {n.rect.w}x{n.rect.h}`)
	end
end
