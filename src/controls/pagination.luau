--!strict
--[[ Pagination — page selection, independent of fetching (phase6 P6b, D7).

	CONTROLLED. `page` is the caller's; every activation proposes one page through
	`onChange(nextPage)` and paint follows only the caller's next value. A page
	outside the known range is DISPLAYED clamped (with a diagnostic) and never
	written back.

	COUNTS. A known `pageCount` decides availability and ignores
	`hasNext`/`hasPrevious`; an absent one is an unknown count, where those two
	flags decide and there is no last page. Zero pages is an inert "No pages"; one
	page shows its context with no enabled navigation.

	THE WINDOW is the boundary pages, the current page and its neighbours, with an
	ellipsis only for a real gap (a gap of one page shows that page), filled to a
	fixed slot count near the edges so the row does not jump. Its work is bounded
	by `boundaryCount` and `siblingCount`, never by `pageCount`. When the measured
	width cannot hold it, the farthest optional boundary page goes first, then the
	farthest neighbour (the higher page on a tie); when not even the current page
	and its arrows fit, the numbers become the "Page n of m" label; the row scrolls
	sideways rather than shrink a target.

	`direction = "rtl"` reverses the row and its arrows once; Left and Right stay
	physical movement. Page nodes are keyed by page number, so a window change
	keeps every page that stays. ]]
local Compose = require("../vendor/compose/core")
local ownedBuild = require("../core/owned_build")
local ownedFormula = require("../core/owned_formula")
local contribution = require("../input/contribution")
local guard = require("../spec_guard")
local selection = require("../selection_model")
local surfaceEnv = require("../env/surface_env")
local themeSnapshot = require("../themes/snapshot")
local textFit = require("../layout/text_fit")
local vocabulary = require("./control_vocabulary")
local alert = require("./alert")

local pagination = {}

local specTypes = require("../spec_types/pagination")
export type Spec = specTypes.Spec

local KEYS = guard.keySet({
	"boundaryCount",
	"controlSize",
	"direction",
	"enabled",
	"env",
	"form",
	"hasNext",
	"hasPrevious",
	"id",
	"onChange",
	"page",
	"pageCount",
	"showFirstLast",
	"siblingCount",
	"width",
})
local FORMS = { numbers = true, arrows = true, label = true }
local DIRECTIONS = { ltr = true, rtl = true }
local MAX_WINDOW = 20
local MAX_SAFE = 9007199254740991
local ELLIPSIS = "…"
local DUMP_SCHEMA = "facet-pagination-dump/1"

local function isPage(v: any): boolean
	return type(v) == "number" and v == v and v % 1 == 0 and math.abs(v) <= MAX_SAFE
end

--[[ THE NUMERIC WINDOW for a known count >= 1: the page numbers to show and
	their roles. `boundary` pages are the edge pages (and a single missing page
	shown in place of an ellipsis); `neighbor` pages sit around the current page.
	Bounded by the two counts, never by `count`. ]]
function pagination.window(current: number, count: number, sibling: number, boundary: number): { any }
	local roles: { [number]: string } = {}
	local function add(p: number, role: string)
		if p >= 1 and p <= count and roles[p] == nil then
			roles[p] = role
		end
	end
	for p = 1, math.min(boundary, count) do
		add(p, "boundary")
	end
	for p = math.max(count - boundary + 1, boundary + 1), count do
		add(p, "boundary")
	end
	-- the neighbour run keeps its full width near an edge (the fixed slot count)
	local startRun = math.max(math.min(current - sibling, count - boundary - sibling * 2 - 1), boundary + 2)
	local endRun = math.min(math.max(current + sibling, boundary + sibling * 2 + 2), count - boundary - 1)
	for p = startRun, endRun do
		add(p, if p == current then "current" else "neighbor")
	end
	-- a gap of exactly one page shows that page instead of an ellipsis
	if startRun == boundary + 2 then
		add(boundary + 1, "boundary")
	end
	if endRun == count - boundary - 1 then
		add(count - boundary, "boundary")
	end
	roles[current] = "current"
	local out: { any } = {}
	for p, role in roles do
		table.insert(out, { page = p, role = role })
	end
	table.sort(out, function(a, b)
		return a.page < b.page
	end)
	return out
end

local function build(Facet: any, core: any, spec: Spec, owner: any)
	guard.assertKnownKeys("UI.Pagination", spec, KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "Pagination"
	local where = `UI.Pagination('{id}')`

	-- ===== validation, before anything is allocated =======================
	if not isPage(selection.read(spec.page)) then
		error(`Facet {where}: \`page\` is required — a finite whole number or a bound one.`, 0)
	end
	if type(spec.onChange) ~= "function" then
		error(`Facet {where}: \`onChange(nextPage)\` is required.`, 0)
	end
	local count0 = selection.read(spec.pageCount)
	if count0 ~= nil and not (isPage(count0) and count0 >= 0) then
		error(`Facet {where}: \`pageCount\` is a whole number >= 0, or absent for an unknown count.`, 0)
	end
	for _, key in { "hasNext", "hasPrevious", "enabled" } do
		local v = selection.read((spec :: any)[key])
		if v ~= nil and type(v) ~= "boolean" then
			error(`Facet {where}: \`{key}\` is a boolean or a bound boolean.`, 0)
		end
	end
	for _, key in { "siblingCount", "boundaryCount" } do
		local v = (spec :: any)[key]
		if v ~= nil and not (isPage(v) and v >= 0 and v <= MAX_WINDOW) then
			error(`Facet {where}: \`{key}\` is a whole number from 0 to {MAX_WINDOW}.`, 0)
		end
	end
	if spec.showFirstLast ~= nil and type(spec.showFirstLast) ~= "boolean" then
		error(`Facet {where}: \`showFirstLast\` is a boolean.`, 0)
	end
	local form = spec.form or "numbers"
	if FORMS[form] ~= true then
		error(`Facet {where}: \`form\` is numbers | arrows | label.`, 0)
	end
	local direction = spec.direction or "ltr"
	if DIRECTIONS[direction] ~= true then
		error(`Facet {where}: \`direction\` is ltr | rtl.`, 0)
	end
	vocabulary.assertSize("UI.Pagination", spec.controlSize)
	-- the window narrows to the room it is OFFERED; a hugging box has none of its own
	local function offerable(d: any): boolean
		return d == nil or (type(d) == "table" and d.type ~= "hug" and d.type ~= "content")
	end
	if not offerable(selection.read(spec.width)) then
		error(`Facet {where}: \`width\` is fill, fixed or another offered width — never hug or content.`, 0)
	end
	local sibling = spec.siblingCount or 1
	local boundary = spec.boundaryCount or 1
	local showFirstLast = spec.showFirstLast == true
	local onChange: any = spec.onChange

	-- ===== the caller's facts, legal values only ============================
	local diagnostics: { string } = {}
	local function legal(key: string, source: any, ok: (any) -> boolean, what: string): any
		local last = selection.read(source)
		local refused = false
		return ownedFormula(owner, function(use)
			local v = selection.read(source, use)
			if ok(v) then
				last, refused = v, false
			elseif not refused then
				refused = true
				selection.note(diagnostics, `Facet {where}: \`{key}\` {what} — keeping the last legal value`)
			end
			return last
		end)
	end
	local pageIn = legal("page", spec.page, isPage, "is a finite whole number")
	local countIn = legal("pageCount", spec.pageCount, function(v)
		return v == nil or (isPage(v) and v >= 0)
	end, "is a whole number >= 0 or nil")
	local function flag(key: string): any
		return legal(key, (spec :: any)[key], function(v)
			return v == nil or type(v) == "boolean"
		end, "is a boolean")
	end
	local hasNextIn, hasPreviousIn = flag("hasNext"), flag("hasPrevious")
	local width = legal("width", spec.width, offerable, "is never hug or content")
	local enabled = ownedFormula(owner, function(use)
		return selection.read(spec.enabled, use) ~= false
	end)

	-- the normalized state every paint and every proposal reads
	local lastClamp: string? = nil
	local state = ownedFormula(owner, function(use)
		local page, count = use(pageIn), use(countIn)
		local current: number?
		if count == 0 then
			current = nil
		elseif count ~= nil then
			current = math.clamp(page, 1, count)
		else
			current = math.max(page, 1)
		end
		local clamp = if current ~= nil and current ~= page then `{page}->{current}` else nil
		if clamp ~= nil and clamp ~= lastClamp then
			selection.note(diagnostics, `Facet {where}: page {page} is outside 1..{count or "?"}; showing {current}`)
		end
		lastClamp = clamp
		local hasPrevious, hasNext
		if current == nil then
			hasPrevious, hasNext = false, false
		elseif count ~= nil then
			hasPrevious, hasNext = current > 1, current < count
		else
			hasPrevious = use(hasPreviousIn) == true and current > 1
			hasNext = use(hasNextIn) == true and current < MAX_SAFE
		end
		return { current = current, count = count, hasPrevious = hasPrevious, hasNext = hasNext }
	end)

	-- ===== the measured fit =================================================
	local env = if spec.env ~= nil then spec.env else surfaceEnv.find(core)
	local offered = Compose.cell(math.huge)
	local function measure(use: any): (any, any, number, number, number)
		local metrics = if env ~= nil then use(env:get("themeMetrics")) else themeSnapshot.neutral()
		local facts = if env ~= nil then textFit.facts({ env = env, use = use }) else { scale = 1, offset = 0 }
		local floor = themeSnapshot.resolveNumber(metrics, "targetSizes.minimum") or 44
		local gap = themeSnapshot.resolveNumber(metrics, "xs") or 4
		return metrics, facts, floor, gap, alert.buttonChromeX(metrics)
	end
	local function labelOf(st: any): string
		if st.current == nil then
			return "No pages"
		end
		return if st.count ~= nil then `Page {st.current} of {st.count}` else `Page {st.current}`
	end

	-- the row's entries, in visual order
	local entries = ownedFormula(owner, function(use)
		local st = use(state)
		local out: { any } = {}
		if st.current == nil then
			table.insert(out, { kind = "label", key = "label" })
			return out
		end
		local metrics, facts, floor, gap, chrome = measure(use)
		local function buttonWidth(text: string): number
			return math.max(floor, alert.labelWidth(metrics, facts, text) + chrome)
		end
		local arrows = 2 + (if showFirstLast then 2 else 0)
		local fixedWidth = arrows * floor
		local chosen = form
		local pages: { any } = {}
		if chosen == "numbers" and st.count == nil then
			chosen = "label"
		end
		if chosen == "numbers" then
			pages = pagination.window(st.current, st.count, sibling, boundary)
			local function need(): number
				local total, prev = fixedWidth, nil
				for _, entry in pages do
					if prev ~= nil and entry.page > prev + 1 then
						total += alert.labelWidth(metrics, facts, ELLIPSIS) + gap
					end
					total += buttonWidth(tostring(entry.page)) + gap
					prev = entry.page
				end
				return total + gap * arrows
			end
			local room = use(offered)
			while need() > room do
				local drop: number? = nil
				for _, role in { "boundary", "neighbor" } do
					for i, entry in pages do
						if entry.role == role then
							local d = math.abs(entry.page - st.current)
							local best = if drop ~= nil then math.abs(pages[drop].page - st.current) else -1
							if d > best or (d == best and entry.page > pages[drop :: number].page) then
								drop = i
							end
						end
					end
					if drop ~= nil then
						break
					end
				end
				if drop == nil then
					break -- only the current page is left
				end
				table.remove(pages, drop)
			end
			if need() > room then
				chosen = "label"
			end
		end
		local function arrow(kind: string)
			table.insert(out, { kind = kind, key = kind })
		end
		if showFirstLast then
			arrow("first")
		end
		arrow("previous")
		if chosen == "numbers" then
			local prev: number? = nil
			for _, entry in pages do
				if prev ~= nil and entry.page > prev + 1 then
					table.insert(out, { kind = "gap", key = `gap-{prev}` })
				end
				table.insert(out, { kind = "page", key = tostring(entry.page), page = entry.page })
				prev = entry.page
			end
		elseif chosen == "label" then
			table.insert(out, { kind = "label", key = "label" })
		end
		arrow("next")
		if showFirstLast and st.count ~= nil then
			arrow("last")
		end
		if direction == "rtl" then
			local reversed = {}
			for i = #out, 1, -1 do
				table.insert(reversed, out[i])
			end
			out = reversed
		end
		return out
	end)

	-- ===== proposals: re-read, then one onChange ============================
	local disposed = false
	local function targetOf(kind: string, page: number?): number?
		local st = state:peek()
		if st.current == nil then
			return nil
		end
		if kind == "previous" then
			return if st.hasPrevious then st.current - 1 else nil
		elseif kind == "next" then
			return if st.hasNext then st.current + 1 else nil
		elseif kind == "first" then
			return if st.current > 1 and st.hasPrevious then 1 else nil
		elseif kind == "last" then
			return if st.count ~= nil and st.current < st.count then st.count else nil
		elseif page ~= nil and page ~= st.current and page >= 1 and (st.count == nil or page <= st.count) then
			return page
		end
		return nil
	end
	local function propose(kind: string, page: number?)
		if disposed or not enabled:peek() then
			return
		end
		local target = targetOf(kind, page)
		if target ~= nil then
			onChange(target)
		end
	end

	local ICONS = {
		first = if direction == "rtl" then "chevron.last" else "chevron.first",
		previous = if direction == "rtl" then "chevron.trailing" else "chevron.leading",
		next = if direction == "rtl" then "chevron.leading" else "chevron.trailing",
		last = if direction == "rtl" then "chevron.first" else "chevron.last",
	}
	-- the target floor is layout width, so neighbouring hit bands never overlap
	local TARGET = { type = "minMax", min = "targetSizes.minimum" }
	local NAMES = { first = "First page", previous = "Previous page", next = "Next page", last = "Last page" }
	local buttonLib = require("./button")

	--[[ FOCUS RECOVERY. A focused page that leaves the window (an external page or
		count change), or a focused arrow that disables at an edge, hands focus to
		the graph's nearest survivor, which may be outside this row. The row notes
		it; the next geometry sync puts focus on the current page, else the next or
		previous arrow — once they are in the order, which is the refresh after the
		one that removed the page. ]]
	local graph: any = nil
	local rootPath: string? = nil
	local paths: { [string]: string } = {}
	local recover = 0
	local function track(key: string): any
		return {
			onAppear = function(path: string)
				paths[key] = path
			end,
			cleanup = function()
				local path = paths[key]
				if path ~= nil and graph ~= nil and graph.focused:peek() == path then
					recover = 3
				end
				if paths[key] == path then
					paths[key] = nil
				end
			end,
		}
	end
	-- the focused arrow whose target is gone (Next on the last page)
	local function deadArrow(focused: any): boolean
		for kind in ICONS do
			if paths[kind] ~= nil and paths[kind] == focused and targetOf(kind) == nil then
				return true
			end
		end
		return false
	end
	owner.watchStatic(state, function()
		if graph ~= nil and deadArrow(graph.focused:peek()) then
			recover = 3
		end
	end)
	--[[ THE LABEL HOLDS ITS WIDTH (owner 2026-09-23): the arrows beside it must not
		move as "Page 9" becomes "Page 10". A hidden twin (laid out, unpainted)
		carries the widest label the count can produce — every digit the widest one
		— so the engine measures the reservation with the words it draws; an unknown
		count reserves UNKNOWN_DIGITS digits (past 9999 the row widens once more). ]]
	local UNKNOWN_DIGITS = 4
	local widestLabel = ownedFormula(owner, function(use)
		local st = use(state)
		local metrics, facts = measure(use)
		local digit, widest = "0", -1
		for d = 0, 9 do
			local w = alert.labelWidth(metrics, facts, tostring(d))
			if w > widest then
				digit, widest = tostring(d), w
			end
		end
		local count = st.count
		local most = string.rep(digit, if count ~= nil then #tostring(math.max(count, 1)) else UNKNOWN_DIGITS)
		return if count ~= nil then `Page {most} of {count}` else `Page {most}`
	end)
	local function row(entry: any): any
		if entry.kind == "label" then
			return UI.ZStack({
				id = "ContextBox",
				children = {
					UI.Text({ id = "Reserve", text = widestLabel, textSize = "control", hidden = true }),
					UI.Text({
						id = "Context",
						text = Compose.formula(function(use)
							return labelOf(use(state))
						end),
						textSize = "control",
						textAlign = "center",
						width = UI.fill(),
					}),
				},
			})
		elseif entry.kind == "gap" then
			return UI.Text({ id = `Gap-{entry.key}`, text = ELLIPSIS, textSize = "control", role = "secondary" })
		elseif entry.kind == "page" then
			local page = entry.page
			local tracked = track(entry.key)
			Compose.cleanup(tracked.cleanup)
			-- the page is the small plate around its number (owner 2026-09-23: the
			-- target-wide plate read as a big button); the SLOT holds the target
			-- floor, so its hit band fills the slot and never overlaps a neighbour's
			return UI.ZStack({
				id = `Slot-{page}`,
				width = TARGET,
				alignH = "center",
				alignV = "center",
				children = {
					buttonLib.build(Facet, core, {
						id = `Page-{page}`,
						onAppear = tracked.onAppear,
						label = tostring(page),
						controlSize = spec.controlSize,
						selected = Compose.formula(function(use)
							return use(state).current == page
						end),
						onActivate = function()
							propose("page", page)
						end,
					}).blueprint,
				},
			})
		end
		local kind = entry.kind
		local tracked = track(kind)
		Compose.cleanup(tracked.cleanup)
		return buttonLib.build(Facet, core, {
			id = kind:sub(1, 1):upper() .. kind:sub(2),
			onAppear = tracked.onAppear,
			icon = ICONS[kind],
			name = NAMES[kind],
			width = TARGET,
			controlSize = spec.controlSize,
			enabled = Compose.formula(function(use)
				use(state)
				return targetOf(kind) ~= nil
			end),
			onActivate = function()
				propose(kind)
			end,
		}).blueprint
	end

	local root = UI.ScrollView({
		id = id,
		axis = "x",
		width = if spec.width ~= nil then width else UI.fill(),
		height = UI.hug(),
		enabled = enabled,
		children = {
			UI.HStack({
				id = "Row",
				gap = "xs",
				align = "center",
				children = {
					UI.ForEach({
						id = "Items",
						items = entries,
						key = function(entry: any): string
							return entry.key
						end,
						row = row,
					}),
				},
			}),
		},
	})

	local blueprint = contribution.attach(root, {
		bindFocusGraph = function(g: any)
			graph = g
		end,
		syncGeometry = function(rectOf: any, node: any?)
			if node == nil then
				return
			end
			rootPath = node.path
			if recover > 0 and graph ~= nil then
				recover -= 1
				local focused = graph.focused:peek()
				-- still on a LIVE node of this row (a surviving page): nothing to do
				local inside = type(focused) == "string"
					and string.sub(focused, 1, #node.path + 1) == node.path .. "/"
					and rectOf(focused) ~= nil
					and not deadArrow(focused)
				local current = state:peek().current
				if inside then
					recover = 0
				else
					-- the current page first; the arrows only once it has had its chance
					local keys = { if current ~= nil then tostring(current) else "" }
					if recover == 0 then
						table.insert(keys, "next")
						table.insert(keys, "previous")
					end
					for _, key in keys do
						local path = paths[key]
						if path ~= nil and graph.focusOn(path) then
							recover = 0
							break
						end
					end
				end
			end
			-- the room is the viewport, except when the viewport IS the row: a hugging
			-- parent sized it from the window it drew, so that width is not an offer
			-- and feeding it back would narrow the window every round
			local r, content = rectOf(node.path), rectOf(`{node.path}/Row`)
			if type(r) == "table" and type(content) == "table" and r.w ~= content.w and r.w ~= offered:peek() then
				offered:set(r.w)
			end
		end,
	})
	owner.own(function()
		disposed = true
	end)

	local function dump()
		local st = state:peek()
		local items: { string } = {}
		for _, entry in entries:peek() do
			table.insert(
				items,
				if entry.kind == "page"
					then (if entry.page == st.current then `[{entry.page}]` else tostring(entry.page))
					elseif entry.kind == "gap" then ELLIPSIS
					elseif entry.kind == "label" then labelOf(st)
					else entry.kind
			)
		end
		return {
			schema = DUMP_SCHEMA,
			id = id,
			current = st.current,
			count = st.count,
			hasPrevious = st.hasPrevious,
			hasNext = st.hasNext,
			form = form,
			direction = direction,
			items = items,
			text = table.concat(items, " "),
			diagnostics = table.clone(diagnostics),
		}
	end

	return {
		blueprint = blueprint,
		api = {
			diagnostics = function(): { string }
				return table.clone(diagnostics)
			end,
		},
		dump = dump,
		dispose = function()
			owner.dispose()
		end,
	}
end

function pagination.build(Facet: any, core: any, spec: Spec)
	return ownedBuild(core, function(owner)
		return build(Facet, core, spec, owner)
	end)
end

return pagination
