--!strict
-- THE HEADLESS TWIN OF THE FIVE-VIEW DEVICE MATRIX (RS-A16 structural guard).
--
-- WHY THIS EXISTS. The rich-skinning-v2 matrix was stopped twice by defects that
-- a green suite could not see and only a Studio drive found:
--
--   RS-A16-D2  the ornate panel plaque's declared `overhang` was validated,
--              painted and published in the census — and reserved by nobody, so
--              the nameplate painted through the "Save changes" label of the row
--              above it (792 px2 at desktop, 1176 at console);
--   RS-A16-D3  pixel-quest's `barTrack.contentInsets` exceeded the track height
--              the same package resolved, so the download bar's fill solved to
--              ZERO height and the control showed no value at all;
--   RS-A16-D4  with NO package installed the four value-control surfaces were
--              selected by no rule in the live sheet at all, so the default
--              Download bar was pixel-identical at 0% and 100%.
--
-- Both are PURE consequences of pure inputs: the solver is deterministic and a
-- package is data, so every row of that matrix is computable headlessly. What was
-- missing was not an engine — it was an assertion. This is that assertion, at
-- suite speed, over all nineteen canonical row configurations:
--
--   (a) no chrome-painted extent — every layer box, every bar ornament, and the
--       node's own decoration, INCLUDING what `chromeOutsets` reserves — overlaps
--       a sibling text or control rect that belongs to a different child of the
--       same FLOW container (a stack, a grid, a scroll region). An ornament may
--       paint over its own host and its own ancestors; a neighbour's label is
--       never its to paint on.
--   (b) no value display solves to a zero-area content box.
--   (c) no text node is unfit: every string still fits the rect it was given.
--   (d) the solver reports no diagnostics on any row.
--   (e) every classification TAG a row's tree carries is selected by at least one
--       rule in the sheet that row would really run — the base seed for the five
--       studio-neutral rows, the package model for the other fourteen — plus a
--       sweep of the whole `classifyTags` vocabulary against every one of those
--       sheets. Emission is not application, and `Frame default` makes an
--       unselected surface INVISIBLE rather than merely unstyled.
--
-- WHAT IT IS NOT. It is not the matrix. It cannot see paint, the engine's own
-- text bounds, clipping, focus visuals or asset decoding, and it does not
-- replace the Studio drive or the captures — the row viewports here are the ones
-- that drive RECORDED live rows so the two instruments talk about the same
-- geometry. It is the part of that matrix a machine can check every time.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local fake_target = require("./lib/fake_target")
local chrome_slots = require("../src/tokens/chrome_slots")
local sheet_model = require("../src/tokens/sheet_model")
local default_style = require("../src/tokens/default_style")
local default_light_style = require("../src/tokens/default_light_style")
local text_metrics = require("../src/layout/text_metrics")

local scenario = require("../examples/gallery/scenarios/theme_authoring") :: any

local PACKAGES = {
	fantasy_ornate = require("../examples/themes/fantasy_ornate"),
	pixel_quest = require("../examples/themes/pixel_quest"),
	glossy_touch = require("../examples/themes/glossy_touch"),
	compact_pointer = require("../examples/themes/compact_pointer"),
}

-- The five canonical view rows of docs/plans/studio-device-verification.md, at
-- the viewports the driver actually RECORDED in
-- artifacts/rich-skinning-v2/rs-a16-matrix.json — the emulator reports a FITTED
-- size that for several presets is not the catalog resolution, and the row that
-- matters is the one the framework laid out for. `coreSafeInsets.top = 58` is the
-- CoreGui inset every row measured; the console row's overscan is derived by the
-- environment from `displaySize = "Large"` (90 x 60 at 1080p), exactly as it is
-- live.
local VIEWS = {
	{
		id = "compact-phone-portrait",
		viewport = { x = 0, y = 0, w = 359, h = 718 },
		displaySize = "Small",
		preferredInput = "Touch",
		capabilities = { touch = true, mouse = false, keyboard = false, gamepad = false },
	},
	{
		id = "compact-phone-landscape",
		viewport = { x = 0, y = 0, w = 705, h = 338 },
		displaySize = "Small",
		preferredInput = "Touch",
		capabilities = { touch = true, mouse = false, keyboard = false, gamepad = false },
	},
	{
		id = "tablet-landscape",
		viewport = { x = 0, y = 0, w = 1079, h = 809 },
		displaySize = "Small",
		preferredInput = "Touch",
		capabilities = { touch = true, mouse = false, keyboard = false, gamepad = false },
	},
	{
		id = "desktop-standard",
		viewport = { x = 0, y = 0, w = 1232, h = 1067 },
		displaySize = "Medium",
		preferredInput = "KeyboardAndMouse",
		capabilities = { touch = false, mouse = true, keyboard = true, gamepad = false },
	},
	{
		id = "console-ten-foot",
		viewport = { x = 0, y = 0, w = 1920, h = 1078 },
		displaySize = "Large",
		preferredInput = "Gamepad",
		capabilities = { touch = false, mouse = true, keyboard = true, gamepad = true },
	},
}

-- five views x {flat, ornate, pixel} = 15, plus the four platform-pair rows
local PAIR_ROWS = {
	{ view = "compact-phone-portrait", package = "glossy_touch" },
	{ view = "desktop-standard", package = "glossy_touch" },
	{ view = "compact-phone-portrait", package = "compact_pointer" },
	{ view = "desktop-standard", package = "compact_pointer" },
}

local function rows(): { { id: string, view: any, package: string? } }
	local out: { { id: string, view: any, package: string? } } = {}
	local byId: { [string]: any } = {}
	for _, view in VIEWS do
		byId[view.id] = view
		for _, name in { "studio-neutral", "fantasy_ornate", "pixel_quest" } do
			table.insert(out, {
				id = `{view.id}/{if name == "studio-neutral" then name else string.gsub(name, "_", "-")}`,
				view = view,
				package = if name == "studio-neutral" then nil else name,
			})
		end
	end
	for _, pair in PAIR_ROWS do
		table.insert(out, {
			id = `{pair.view}/{(string.gsub(pair.package, "_", "-"))}`,
			view = byId[pair.view],
			package = pair.package,
		})
	end
	return out
end

-- ===== one row, solved =====================================================
--
-- The real presenter over the real theme scenario, with the runner's engine
-- seams stubbed exactly as tests/theme_authoring_scenario.spec.luau stubs them:
-- the module under solve is the same file Studio loads.
local function solveRow(row: any): any
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", row.view.viewport)
	env:set("coreSafeInsets", { top = 58, bottom = 0, left = 0, right = 0 })
	env:set("displaySize", row.view.displaySize)
	env:set("preferredInput", row.view.preferredInput)
	env:set("capabilities", row.view.capabilities)
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	-- the engine draws the scrollbar INSIDE the region; the live adapter reserves
	-- 8px off the cross axis when content overflows, and a row solved without it
	-- would lay out 8px wider than the live one
	adapter.scrollBarThickness = 8
	local presenter = Facet.newPresenter(core, env, adapter, system)
	local chromeState = chrome_slots.newState(nil)
	local ctx: any
	ctx = {
		Facet = Facet,
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
	if row.package ~= nil then
		local applied = built.steps.installPackage(nil, row.package)
		assert(applied.ok == true, `{row.id}: the package must install (got {tostring(applied.error)})`)
		presenter.refresh()
	end
	local metrics = env:get("themeMetrics"):get()
	local nodes: { [string]: any } = {}
	for _, path in adapter.paths() do
		local node = adapter.node(path)
		if node.rect ~= nil then
			nodes[path] = node
		end
	end
	return {
		id = row.id,
		package = if row.package ~= nil then chromeState.package() else nil,
		metrics = metrics,
		-- the factor the renderer painted authored text sizes with (the ten-foot
		-- floor); the measure seam used the same one, preferredTextSize being 1
		paintScale = env:get("typographyPaintScale"):get(),
		nodes = nodes,
		paths = adapter.paths(),
		adapter = adapter,
		diagnostics = handle.controller.diagnostics(),
		dispose = function()
			presenter.dismiss(handle)
			if built.dispose ~= nil then
				built.dispose()
			end
		end,
	}
end

-- ===== tree relationships ==================================================

-- structural regions splice their children into the PARENT's flow (the renderer
-- treats them as transparent containers), so they are never the container that
-- decides whether two nodes are neighbours
local TRANSPARENT: { [string]: boolean } = { When = true, ForEach = true, ErrorBoundary = true }
-- containers whose children are LAID OUT SIDE BY SIDE: two different children of
-- one of these may never paint on each other
local FLOW: { [string]: boolean } = {
	Screen = true,
	VStack = true,
	HStack = true,
	Grid = true,
	ScrollView = true,
	AdaptiveStack = true,
}
-- containers whose children OVERLAP by design (a badge over its tile, a bar's
-- fill over its track, a losing ViewThatFits candidate over the winner)
local OVERLAY: { [string]: boolean } = { ZStack = true, Anchor = true, ViewThatFits = true }
-- everything that PAINTS: a chrome extent over one of these is what a player
-- sees. Containers are excluded because their rect is their children's space.
local function paints(class: string): boolean
	return not (FLOW[class] or OVERLAY[class] or TRANSPARENT[class] or class == "Spacer")
end

local function parentOf(path: string): string?
	local cut = string.match(path, "^(.*)/[^/]*$")
	return if cut == nil or cut == "" then nil else cut
end

local function isAncestor(maybeAncestor: string, path: string): boolean
	return maybeAncestor == path or string.sub(path, 1, #maybeAncestor + 1) == maybeAncestor .. "/"
end

local function commonAncestor(a: string, b: string): string
	local best = ""
	local cursor = a
	while cursor ~= nil do
		if isAncestor(cursor, b) then
			best = cursor
			break
		end
		cursor = parentOf(cursor)
	end
	return best
end

-- are these two nodes NEIGHBOURS — different children of the same flow container?
local function areFlowNeighbours(nodes: { [string]: any }, a: string, b: string): boolean
	if isAncestor(a, b) or isAncestor(b, a) then
		return false
	end
	local ancestor = commonAncestor(a, b)
	while ancestor ~= "" do
		local node = nodes[ancestor]
		local class = if node ~= nil then node.class else nil
		if class == nil or TRANSPARENT[class] then
			ancestor = parentOf(ancestor) or ""
			continue
		end
		return FLOW[class] == true
	end
	return false
end

-- ===== chrome extents ======================================================

local function boxRect(host: any, box: any): any
	local w = box.size.xScale * host.w + box.size.xOffset
	local h = box.size.yScale * host.h + box.size.yOffset
	return {
		x = host.x + box.position.xScale * host.w + box.position.xOffset - box.anchor.x * w,
		y = host.y + box.position.yScale * host.h + box.position.yOffset - box.anchor.y * h,
		w = w,
		h = h,
	}
end

-- CLIPPING IS THE ENGINE'S, AND THE AUDIT HAS TO SEE IT. A `clipChildren` host —
-- every ScrollView by declaration — crops its descendants, so content the solver
-- placed past the window is not painted at all and cannot be painted ON. Without
-- this the audit reports the pinned action bar as covering everything the scroll
-- region laid out below its own window, which is exactly what the region exists
-- to hide.
local function clips(node: any): boolean
	return (node.props or {}).clipChildren == true
end

local function intersect(a: any, b: any): any?
	local x0, y0 = math.max(a.x, b.x), math.max(a.y, b.y)
	local x1, y1 = math.min(a.x + a.w, b.x + b.w), math.min(a.y + a.h, b.y + b.h)
	if x1 <= x0 or y1 <= y0 then
		return nil
	end
	return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

-- `from` is the first node whose clip applies: a node's own rect for the chrome
-- INSIDE it, its parent for the node itself
local function clippedTo(nodes: { [string]: any }, from: string?, rect: any): any?
	local out: any? = rect
	local cursor = from
	while cursor ~= nil and out ~= nil do
		local node = nodes[cursor]
		if node ~= nil and node.rect ~= nil and clips(node) then
			out = intersect(out, node.rect)
		end
		cursor = parentOf(cursor)
	end
	return out
end

local function overlapArea(a: any, b: any): number
	local w = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
	local h = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
	if w <= 0 or h <= 0 then
		return 0
	end
	return w * h
end

-- the same classification the adapter makes, from the same three facts: the
-- class, the public `surface`, and the internal decoration HINT the renderer
-- passes to `adapter.create` (a Slider's rail and a bar's track are hinted; no
-- generic rule could infer them)
local function slotOf(node: any): string?
	local props = node.props or {}
	local hint = node.decorationHint
	return chrome_slots.classify({
		class = node.class,
		surface = props.surface,
		hasSelection = props.selected ~= nil,
		hint = if type(hint) == "table" then hint.slot else nil,
	})
end

-- every rectangle a package PAINTS for this node, named for the report: the
-- node's own decoration, each layer box of a stack, and the bar ornaments that
-- are anchored to a track rather than inside it
local function paintedExtents(package: any, node: any, slot: string): { { name: string, rect: any } }
	local out: { { name: string, rect: any } } = {}
	if package == nil then
		return out
	end
	local rect = node.rect
	local stack = chrome_slots.layerPlanFor(package, slot)
	if stack ~= nil then
		for _, layer in stack.layers do
			for _, box in chrome_slots.layerBoxes(layer) do
				table.insert(out, { name = box.name, rect = boxRect(rect, box) })
			end
		end
		local lift = chrome_slots.plaqueTextBox(stack)
		if lift ~= nil then
			table.insert(out, { name = lift.name, rect = boxRect(rect, lift) })
		end
	elseif chrome_slots.planFor(package, slot) ~= nil then
		-- a nine-slice decoration is full bleed: it IS the node's rect, and it is
		-- checked so a solver overlap between two decorated rows cannot hide here
		table.insert(out, { name = chrome_slots.DECORATION_NAME, rect = rect })
	end
	if slot == "barTrack" then
		local chrome = package.chrome or {}
		local direction = chrome_slots.barDirectionOf(package, "barFill")
		if chrome.barCap ~= nil then
			local size = chrome_slots.barOrnamentSize(chrome.barCap)
			for _, which in { "start", "finish" } do
				local box = chrome_slots.barCapBox(which, direction, size)
				table.insert(out, { name = box.name, rect = boxRect(rect, box) })
			end
		end
		if chrome.barCenter ~= nil then
			local box = chrome_slots.barCenterBox(chrome_slots.barOrnamentSize(chrome.barCenter))
			table.insert(out, { name = box.name, rect = boxRect(rect, box) })
		end
	end
	return out
end

-- ===== the sheet that will actually be LIVE for a row ======================
--
-- RS-A16-D4: `screen_target` builds the BASE seed (`sheet_model.build`, Dark +
-- Light) when no package is installed and `buildPackage` when one is. The
-- value-control own-paint family existed in the second and not in the first, so
-- the five studio-neutral rows ran a sheet in which four surfaces were selected
-- by nothing at all and `Frame default` made them invisible. Every assertion
-- below therefore reads the model for THAT row rather than a package model.
local modelCache: { [string]: any } = {}
local function liveModel(package: any?): any
	local key = if package == nil then "<studio-neutral>" else package.identity.id
	if modelCache[key] == nil then
		modelCache[key] = if package == nil
			then sheet_model.build({
				themes = {
					{ name = "Dark", style = default_style },
					{ name = "Light", style = default_light_style },
				},
			})
			else sheet_model.buildPackage(package)
	end
	return modelCache[key]
end

-- the class tokens a model's selectors really key on. Tokenized, never substring
-- matched: `.luau-chrome-barCap-finish` must not read as covering
-- `luau-chrome-barCap`.
local selectedCache: { [string]: { [string]: boolean } } = {}
local function selectedTags(package: any?): { [string]: boolean }
	local key = if package == nil then "<studio-neutral>" else package.identity.id
	if selectedCache[key] == nil then
		local out: { [string]: boolean } = {}
		for _, rule in liveModel(package).rules do
			for token in string.gmatch(rule.selector, "%.([%w%-_]+)") do
				out[token] = true
			end
		end
		selectedCache[key] = out
	end
	return selectedCache[key]
end

-- the rung-2 per-view override carried on the hint, read exactly as
-- `screen_chrome.chromeOverrideOf` reads it
local function overrideOf(hint: any): any
	if type(hint) ~= "table" then
		return nil
	end
	local hasImage = type(hint.image) == "string" and hint.image ~= ""
	local hasVariants = type(hint.imageVariants) == "table"
	if not hasImage and not hasVariants then
		return nil
	end
	return { image = if hasImage then hint.image else nil, imageVariants = hint.imageVariants }
end

-- the slot this node is actually DECORATED with under this package (what the
-- adapter records as `handle.chromeSlot`, which is what earns the skinned tag)
local function skinnedSlotOf(package: any?, node: any): string?
	local slot = chrome_slots.resolveSlot(package, slotOf(node))
	if slot == nil then
		return nil
	end
	if chrome_slots.layerPlanFor(package, slot) ~= nil then
		return slot
	end
	if chrome_slots.planFor(package, slot, overrideOf(node.decorationHint)) ~= nil then
		return slot
	end
	return nil
end

-- ===== the five audits =====================================================

local VALUE_SLOTS: { [string]: boolean } = {
	barTrack = true,
	barFill = true,
	sliderTrack = true,
	sliderThumb = true,
	toggleTrack = true,
	toggleKnob = true,
	stepperPlate = true,
}

local function visible(node: any): boolean
	return node.visible ~= false and node.rect ~= nil
end

local function auditRow(solved: any): { string }
	local findings: { string } = {}
	local nodes = solved.nodes
	local package = solved.package

	-- (a) chrome extents versus the neighbours
	for path, node in nodes do
		if not visible(node) then
			continue
		end
		local slot = slotOf(node)
		if slot == nil then
			continue
		end
		for _, extent in paintedExtents(package, node, slot) do
			if extent.rect.w <= 0 or extent.rect.h <= 0 then
				continue
			end
			-- what the engine actually PAINTS of this ornament: the chrome is a
			-- child of its host, so the host's own clip applies too
			local painted = clippedTo(nodes, path, extent.rect)
			if painted == nil then
				continue
			end
			for victimPath, victim in nodes do
				if not visible(victim) or not paints(victim.class) then
					continue
				end
				if victim.rect.w <= 0 or victim.rect.h <= 0 then
					continue
				end
				if not areFlowNeighbours(nodes, path, victimPath) then
					continue
				end
				local shown = clippedTo(nodes, parentOf(victimPath), victim.rect)
				if shown == nil then
					continue
				end
				local area = overlapArea(painted, shown)
				if area > 0 then
					table.insert(
						findings,
						string.format(
							"%s: %s's %s [%d,%d %dx%d] paints %d px2 over the neighbouring %s %s [%d,%d %dx%d]",
							solved.id,
							path,
							extent.name,
							painted.x,
							painted.y,
							painted.w,
							painted.h,
							area,
							victim.class,
							victimPath,
							shown.x,
							shown.y,
							shown.w,
							shown.h
						)
					)
				end
			end
		end
	end

	-- (b) a value display with no content box shows no value
	for path, node in nodes do
		local slot = if visible(node) then slotOf(node) else nil
		if slot == nil or not VALUE_SLOTS[slot] then
			continue
		end
		if node.rect.w <= 0 or node.rect.h <= 0 then
			table.insert(
				findings,
				string.format(
					"%s: the %s node %s solved to %dx%d — a value display with no content box shows no value",
					solved.id,
					slot,
					path,
					node.rect.w,
					node.rect.h
				)
			)
		end
	end

	-- (c) text that does not fit the rect it was given, re-measured through the
	-- SAME estimator the solve used. Headless there are no engine widths, so the
	-- estimate is reproducible — but it is per FONT DESCRIPTOR and per line-height
	-- factor, and those belong to the typography ROLE the renderer resolved. The
	-- painted `textSize` identifies the role (authored sizes carry the display
	-- scale, intrinsic ones do not, so both are tried); where several roles share
	-- a size the audit takes the roomiest reading, so "unfit" means NO role this
	-- package declares could have fitted the string in the rect it got.
	local roles = solved.metrics.type
	local scale = if solved.paintScale ~= nil then solved.paintScale else 1
	for path, node in nodes do
		local props = node.props or {}
		if node.class ~= "Text" or not visible(node) or type(props.text) ~= "string" or props.text == "" then
			continue
		end
		local size = props.textSize
		if type(size) ~= "number" or node.rect.w <= 0 then
			continue
		end
		local best: any = nil
		for _, role in roles do
			local owns = math.abs(role.size - size) < 0.001 or math.abs(role.size * scale - size) < 0.001
			if not owns then
				continue
			end
			local m = text_metrics.measure(props.text, role.fontKey, size, node.rect.w, role.lineHeight)
			if best == nil or m.height < best.height then
				best = m
			end
		end
		if best ~= nil and best.height > node.rect.h + 0.5 then
			table.insert(
				findings,
				string.format(
					'%s: %s does not fit: "%s" at %gpx needs %gx%g in a %dx%d rect',
					solved.id,
					path,
					props.text,
					size,
					best.width,
					best.height,
					node.rect.w,
					node.rect.h
				)
			)
		end
	end

	-- (d) the solver's own complaints
	--
	-- EXCEPT the chrome-inset yield (director report 2026-07-28). Every other
	-- solver diagnostic describes something BROKEN — a box that collapsed, a text
	-- that does not fit, an unbounded percent. The yield describes the opposite:
	-- a control smaller than its theme's own carved border, whose inset was
	-- therefore given back SO THAT IT STILL DRAWS. It is a note about the design,
	-- reported per solve, and the compact-label row exists precisely to keep one
	-- on screen under the heavy packages (a Pixel Quest Button costs 56px of
	-- chrome; that row's fixed buttons are 52px, deliberately). Failing the matrix
	-- on a repaired condition would mean deleting the fixture that proves the
	-- repair. The collapse diagnostic — the unrepaired case — still fails (b)/(d).
	for _, entry in solved.diagnostics do
		if string.find(entry.issue, "could not be spent", 1, true) == nil then
			table.insert(
				findings,
				string.format("%s: solver diagnostic on %s — %s", solved.id, entry.node, entry.issue)
			)
		end
	end

	-- (e) EMISSION IS NOT APPLICATION — RS-A16-D4.
	--
	-- Every tag this row's own tree would carry, checked against the sheet this
	-- row would really run. A tag with no rule is not "unstyled": `Frame default`
	-- sets BackgroundTransparency = 1, so it is INVISIBLE — which is how the
	-- default Download bar came to be pixel-identical at 0% and 100% and the
	-- default Brightness slider came to have no rail and no thumb.
	--
	-- Computed from the same three facts the live adapter classifies from (the
	-- public surface, the internal decoration hint, and whether that slot is
	-- decorated under this package) through the same pure `classifyTags`.
	local selected = selectedTags(package)
	local reported: { [string]: boolean } = {}
	for path, node in nodes do
		if not visible(node) then
			continue
		end
		local hint = node.decorationHint
		local tags = sheet_model.classifyTags({
			surface = (node.props or {}).surface,
			slotHint = if type(hint) == "table" then hint.slot else nil,
			skinnedSlot = skinnedSlotOf(package, node),
		})
		for tag in tags do
			if selected[tag] or reported[tag] then
				continue
			end
			reported[tag] = true
			table.insert(
				findings,
				string.format(
					-- deliberately shares no word with the other four reports' filters
					"%s: %s carries the tag `%s` that NO rule in the live sheet selects — Frame default wins and the surface is invisible",
					solved.id,
					path,
					tag
				)
			)
		end
	end
	return findings
end

-- one solve per row, shared by every proposition below (nineteen solves, not
-- nineteen times four)
local audited: { { id: string, findings: { string } } } = {}
local rowSet = rows()
for _, row in rowSet do
	local solved = solveRow(row)
	table.insert(audited, { id = solved.id, findings = auditRow(solved) })
	solved.dispose()
end

local function report(kinds: { string }): string
	local out: { string } = {}
	for _, entry in audited do
		for _, finding in entry.findings do
			for _, kind in kinds do
				if string.find(finding, kind, 1, true) ~= nil then
					table.insert(out, finding)
					break
				end
			end
		end
	end
	table.sort(out)
	return table.concat(out, "\n")
end

describe("the headless matrix audit: nineteen canonical rows, solved and checked", function()
	it("covers the five canonical views x three packages, plus the four pair rows", function()
		expect(#rowSet).toBe(19)
		expect(#audited).toBe(19)
		local ids: { [string]: boolean } = {}
		for _, entry in audited do
			expect(ids[entry.id]).toBeNil()
			ids[entry.id] = true
		end
		-- the rows the two stopped drives named, by the names they used
		for _, id in
			{
				"desktop-standard/studio-neutral",
				"desktop-standard/fantasy-ornate",
				"console-ten-foot/fantasy-ornate",
				"desktop-standard/pixel-quest",
				"compact-phone-portrait/glossy-touch",
				"desktop-standard/compact-pointer",
			}
		do
			expect(ids[id]).toBe(true)
		end
	end)

	it("(a) no chrome extent paints on a neighbour's text or control — RS-A16-D2", function()
		expect(report({ "paints" })).toBe("")
	end)

	it("(b) no value display has a zero content box — RS-A16-D3", function()
		expect(report({ "no content box" })).toBe("")
	end)

	it("(c) every text node fits the rect it was given", function()
		expect(report({ "does not fit" })).toBe("")
	end)

	it("(d) the solver reports nothing on any row", function()
		expect(report({ "solver diagnostic" })).toBe("")
	end)

	it("(e) every tag a row emits is selected by a rule in that row's live sheet — RS-A16-D4", function()
		expect(report({ "NO rule in the live sheet" })).toBe("")
	end)

	it("(e) the five studio-neutral rows really do run the BASE seed", function()
		-- the guard above is only worth anything if the flat rows are checked
		-- against `sheet_model.build` and not against a package model: the defect
		-- was a family of rules the package builder had and the base seed did not
		local flat = 0
		for _, row in rowSet do
			if row.package == nil then
				flat += 1
			end
		end
		expect(flat).toBe(5)
		local base = liveModel(nil)
		expect(base.rules[1].group).toBeNil() -- the legacy shape, i.e. `build`
		local selected = selectedTags(nil)
		for _, slot in chrome_slots.OWN_PAINT_SLOTS do
			expect(selected[chrome_slots.slotTagFor(slot)]).toBe(true)
		end
	end)
end)

-- ===== THE TAG VOCABULARY, SWEPT (RS-A16-D4 class guard) ====================
--
-- The row audit above catches a missing rule for a tag the FIXTURE happens to
-- emit. This one closes the class: it drives `classifyTags` — the single function
-- by which every Facet state reaches a native selector — over its whole declared
-- input domain, and requires each resulting tag to be selected by a rule in every
-- sheet the framework can run. A tag added to the classifier with no rule behind
-- it fails here whether or not any fixture happens to render it.
--
-- The only exemptions are tags that can ONLY land on a node a package decorated,
-- and each one's reachability is computed from the same `chrome_slots` functions
-- the adapter uses — never from a hand-maintained list of package names.

local SURFACES = { "base", "raised", "control", "chip", "badge", "accent", "scrim", "plain" }
local BUTTON_ROLES = { "default", "cancel", "destructive" }

local function emittableTags(): { { tag: string, from: string } }
	local out: { { tag: string, from: string } } = {}
	local seen: { [string]: boolean } = {}
	local function add(input: any, label: string)
		for tag in sheet_model.classifyTags(input) do
			if not seen[tag] then
				seen[tag] = true
				table.insert(out, { tag = tag, from = label })
			end
		end
	end
	for _, surface in SURFACES do
		add({ surface = surface, interactive = true, pointerLive = true, selected = true }, `surface "{surface}"`)
	end
	for _, role in BUTTON_ROLES do
		add({ buttonRole = role }, `buttonRole "{role}"`)
	end
	add(
		{ roleSecondary = true, strong = true, gripFocus = true, divider = true, iconArt = true },
		"roles + divider + icon art"
	)
	add({ errorState = true, chromeYield = true, toggleOn = true }, "state tags")
	for _, slot in chrome_slots.SLOTS do
		add({ slotHint = slot }, `slotHint "{slot}"`)
		add({ skinnedSlot = slot }, `skinnedSlot "{slot}"`)
	end
	table.sort(out, function(a, b)
		return a.tag < b.tag
	end)
	return out
end

-- does this package put ART on the slot at all (nine-slice or layered)?
local function skins(package: any?, slot: string): boolean
	return chrome_slots.layerPlanFor(package, slot) ~= nil or chrome_slots.planFor(package, slot) ~= nil
end

-- does any of this package's art declare the sixth variant state?
local function declaresErrorArt(package: any?): boolean
	if package == nil then
		return false
	end
	for _, slot in chrome_slots.SLOTS do
		local plan = chrome_slots.planFor(package, slot)
		if plan ~= nil and plan.variants ~= nil and plan.variants.error ~= nil then
			return true
		end
		local stack = chrome_slots.layerPlanFor(package, slot)
		if stack ~= nil then
			for _, layer in stack.layers do
				if layer.variants ~= nil and layer.variants.error ~= nil then
					return true
				end
			end
		end
	end
	return false
end

-- Why a tag may be absent from a sheet, and the exact condition that makes it
-- reachable again. `nil` = required unconditionally.
local function reachableWithoutArt(tag: string, package: any?): boolean?
	-- plain prefix comparison, never a pattern: `luau-skinned-` carries dashes,
	-- and a dash is a Lua pattern quantifier (this silently matched nothing on the
	-- first attempt and reported every slot as required)
	local skinnedPrefix = chrome_slots.TAGS.skinnedPrefix
	local skinnedSlot = if string.sub(tag, 1, #skinnedPrefix) == skinnedPrefix
		then string.sub(tag, #skinnedPrefix + 1)
		else nil
	if skinnedSlot ~= nil then
		-- the four own-paint slots are ALWAYS skinnable — a Slider's `thumbImage`
		-- is a rung-2 per-view override and needs no package at all — so their
		-- suppression is pre-armed in every sheet. Every other slot earns the tag
		-- only from a recipe, which emits the rule that matches it.
		return chrome_slots.hasOwnPaint(skinnedSlot) or skins(package, skinnedSlot)
	end
	if tag == chrome_slots.TAGS.stackYield then
		-- only a LAYERED TextBox yields its whole ladder (a single decoration uses
		-- the `luau-chrome-editing` tag on the decoration instead)
		return chrome_slots.layerPlanFor(package, "field") ~= nil
	end
	if tag == chrome_slots.TOGGLE_ON_TAG then
		-- a flat switch's ON colours are `togglePalette`'s bespoke writes; the tag
		-- exists for a package's ON ART
		return skins(package, "toggleTrack") or skins(package, "toggleKnob")
	end
	if tag == chrome_slots.TAGS.stateError then
		return declaresErrorArt(package)
	end
	return true
end

describe("every tag the framework can emit has a rule that applies it (RS-A16-D4)", function()
	local VOCABULARY = emittableTags()

	local SHEETS: { { name: string, package: any? } } = { { name = "studio-neutral (the BASE seed)", package = nil } }
	for _, name in { "fantasy_ornate", "pixel_quest", "glossy_touch", "compact_pointer" } do
		local pkg, report = (PACKAGES[name] :: any).build(Facet.themes)
		assert(pkg ~= nil, `{name} failed its own package gate: {report.errors[1] and report.errors[1].message}`)
		table.insert(SHEETS, { name = name, package = pkg })
	end

	it("the vocabulary really is the whole classifier (a new tag lands in it automatically)", function()
		-- the sweep is only a class guard if it enumerates from the classifier
		-- rather than from a list somebody has to remember to extend
		expect(#VOCABULARY).toBeGreaterThan(30)
		local set: { [string]: boolean } = {}
		for _, entry in VOCABULARY do
			set[entry.tag] = true
		end
		for _, slot in chrome_slots.OWN_PAINT_SLOTS do
			expect(set[chrome_slots.slotTagFor(slot)]).toBe(true)
			expect(set[chrome_slots.skinnedTagFor(slot)]).toBe(true)
		end
		expect(set["luau-surface-control"]).toBe(true)
		expect(set["luau-role-destructive"]).toBe(true)
		expect(set[chrome_slots.TAGS.iconArt]).toBe(true)
		-- `plain` is chrome-less by design and adds no tag of its own
		expect(set["luau-surface-plain"]).toBeNil()
	end)

	for _, sheet in SHEETS do
		it(`{sheet.name}: no tag it can carry is left unselected`, function()
			local selected: { [string]: boolean } = {}
			for _, rule in liveModel(sheet.package).rules do
				for token in string.gmatch(rule.selector, "%.([%w%-_]+)") do
					selected[token] = true
				end
			end
			local unapplied: { string } = {}
			for _, entry in VOCABULARY do
				if selected[entry.tag] then
					continue
				end
				if reachableWithoutArt(entry.tag, sheet.package) then
					table.insert(unapplied, `{entry.tag} (emitted from {entry.from})`)
				end
			end
			expect(table.concat(unapplied, "\n")).toBe("")
		end)
	end

	it("the conditional tags are not dead vocabulary: the corpus applies every one", function()
		-- the other direction. A tag exempted "because only art reaches it" has to
		-- be reached by the art SOMEWHERE, or the exemption is hiding a rule that
		-- was never written (which is exactly what RS-A16-D4 was).
		local conditional = {
			chrome_slots.TAGS.stackYield,
			chrome_slots.TAGS.stateError,
			chrome_slots.TOGGLE_ON_TAG,
			chrome_slots.skinnedTagFor("panel"),
			chrome_slots.skinnedTagFor("control"),
		}
		for _, tag in conditional do
			local applied = false
			for _, sheet in SHEETS do
				for _, rule in liveModel(sheet.package).rules do
					for token in string.gmatch(rule.selector, "%.([%w%-_]+)") do
						if token == tag then
							applied = true
						end
					end
				end
			end
			expect(applied).toBe(true)
		end
	end)
end)
