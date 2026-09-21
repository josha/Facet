--!strict
local Compose = require("../vendor/compose/core")
local ownedBuild = require("../core/owned_build")
local selectionModel = require("../selection_model")

-- Finite content pages share selection with native scrolling and page indicators.
local guard = require("../spec_guard")
local pageView = {}
local specTypes = require("../spec_types/page_view")
export type Page = specTypes.Page
type StringCell = specTypes.StringCell
export type Spec<V = StringCell> = specTypes.Spec<V>
local KEYS = guard.keySet({ "id", "pages", "selection", "height", "indicators", "summary", "controls" })
local function build(Facet, core, spec: Spec, owner)
	guard.assertKnownKeys("UI.PageView", spec, KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "PageView"
	assert(type(id) == "string" and id ~= "", "UI.PageView.id must be a nonempty string")
	assert(selectionModel.isWritable(spec.selection), "UI.PageView.selection must be a writable Compose cell")
	assert(type(spec.pages) == "table" and #spec.pages > 0, "UI.PageView.pages must be a nonempty array")
	assert(spec.indicators == nil or type(spec.indicators) == "boolean", "UI.PageView.indicators must be boolean")
	assert(spec.summary == nil or type(spec.summary) == "boolean", "UI.PageView.summary must be boolean")
	assert(spec.controls == nil or type(spec.controls) == "boolean", "UI.PageView.controls must be boolean")
	local pages, ids, indices = {}, {}, {}
	for index, page in spec.pages do
		assert(
			type(index) == "number" and index % 1 == 0 and index >= 1 and index <= #spec.pages,
			"UI.PageView.pages must be a dense array"
		)
		guard.assertKnownKeys("UI.PageView.pages", page, guard.keySet({ "id", "title", "content" }), "page")
		assert(
			type(page.id) == "string" and page.id ~= "" and not page.id:find("/", 1, true) and not indices[page.id],
			"UI.PageView page IDs must be unique nonempty names without /"
		)
		assert(type(page.title) == "string" and page.title ~= "", "UI.PageView page title must be nonempty text")
		assert(
			type(page.content) == "table" and type(page.content.class) == "string",
			"UI.PageView page content must be a blueprint"
		)
		indices[page.id] = index
		ids[index] = page.id
		pages[index] = table.clone(page)
	end
	assert(indices[spec.selection:peek()] ~= nil, "UI.PageView.selection must name a declared page")
	local target = Compose.cell(spec.selection:peek())
	local writing = false
	local scrollSelection
	local pendingSelection
	local function select(key)
		if key == spec.selection:peek() then
			target:set(nil)
			target:set(key)
		else
			spec.selection:set(key)
		end
	end
	local function adjust(direction)
		local index = indices[spec.selection:peek()]
		local nextIndex = math.clamp(index + direction, 1, #ids)
		if nextIndex == index then
			return false
		end
		select(ids[nextIndex])
		return true
	end
	local observingSelection = false
	owner.watchStatic(spec.selection, function(key)
		if not observingSelection then
			return
		end
		assert(indices[key] ~= nil, "UI.PageView.selection must name a declared page")
		if key == scrollSelection then
			scrollSelection = nil
		elseif not writing then
			scrollSelection = nil
			pendingSelection = key
			target:set(key)
		end
	end)
	observingSelection = true
	local cards, dots = {}, {}
	for i, page in pages do
		table.insert(
			cards,
			UI.containerRelativeFrame(
				UI.ScrollView({
					id = page.id,
					axis = "y",
					height = UI.fill(),
					padding = "m",
					children = { page.content },
				}),
				{ axis = "horizontal", fraction = 1 }
			)
		)
		local selected = Compose.formula(function(use)
			return use(spec.selection) == page.id
		end)
		table.insert(
			dots,
			UI.Button({
				id = "Dot" .. i,
				label = "Page " .. i .. ": " .. page.title,
				selected = selected,
				surface = "plain",
				--[[ THE RING FOLLOWS THE SHAPE OF THE THING IT IS ON. A dot is round
					and the focus ring around it was a SQUARE (measured live, 1080p,
					2026-09-20): the fallback ring radius is derived from the node's own
					surface role, and `plain` names none, so it stayed sharp-cornered.
					`shape = "circle"` is the framework's one disc idiom and carries that
					radius on both paint paths — it also makes the 1:1 target explicit,
					which is what the dot always was. The label stays the accessible name
					(a disc with custom content draws no text). ]]
				shape = "circle",
				width = { type = "fixed", px = "targetSizes.minimum" },
				onActivate = function()
					select(page.id)
				end,
				children = {
					UI.ZStack({
						id = "Center",
						width = UI.fill(),
						height = UI.fill(),
						children = {
							UI.corners(
								UI.Box({
									id = "Mark",
									width = { type = "fixed", px = "space.s" },
									height = { type = "fixed", px = "space.s" },
									tint = Compose.formula(function(use)
										return {
											role = if use(selected) then "accent" else "contentSecondary",
											blend = 1,
										}
									end),
									alignH = "center",
									alignV = "center",
								}),
								"pill"
							),
						},
					}),
				},
			})
		)
	end
	--[[ THE CAROUSEL IS ONE STOP (measured live, 1080p, 2026-09-20: walking from
		the showcase header to its game grid took ~10 Down presses, because the hero
		page's own card and then each of the three dots were separate stops).

		A carousel is ONE thing to a reader: you arrive on it, you page Left/Right,
		you activate what is on the page, and one press of Down leaves it. That is
		exactly a HORIZONTAL navigation group whose entries are the pages — so the
		group is what this control contributes, and `focus_map.autoGroups` does not
		descend into a contribution, which is what takes the dots out of the
		keyboard and pad order without taking them out of the tree. They stay
		mounted, tappable and clickable, and they stay the fallback: a PageView
		whose pages hold no focusable at all (three pictures, say) keeps its dots as
		the stops, because otherwise the control would have none.

		ONE ENTRY PER PAGE, not one per focusable: the entry is the page's FIRST
		focusable, which is the page's primary action, so Return activates the thing
		the page is about. A page that puts several controls on itself still shows
		them and still takes taps on them; what it does not get is a keyboard walk
		THROUGH the carousel, which is the trade this stop is.

		Vertical arrows are left alone, so Up and Down fall straight out of the
		group to the neighbouring region — one press, whichever page is showing. ]]
	local FOCUS_STOP: { [string]: boolean } = { Button = true, Toggle = true, TextField = true }
	-- the focusables this control's own subtree offers, split by the region they
	-- sit in. One walk, shared by `focusGroups` and `adjustTargets`.
	local function survey(root: any)
		local pageStops: { string } = {}
		local dotStops: { string } = {}
		local controlStops: { string } = {}
		local seenPage: { [string]: boolean } = {}
		local pagePrefix = root.path .. "/Pages/"
		local dotPrefix = root.path .. "/Indicators/"
		local controlPrefix = root.path .. "/Controls/"
		local function walk(node: any)
			if node.retiring == true then
				return
			end
			local path = node.path
			if path ~= nil and FOCUS_STOP[node.class] and not (node.props ~= nil and node.props.focusable == false) then
				if string.sub(path, 1, #pagePrefix) == pagePrefix then
					local key = string.match(string.sub(path, #pagePrefix + 1), "^([^/]+)")
					if key ~= nil and indices[key] ~= nil and not seenPage[key] then
						seenPage[key] = true
						table.insert(pageStops, path)
					end
				elseif string.sub(path, 1, #dotPrefix) == dotPrefix then
					table.insert(dotStops, path)
				elseif string.sub(path, 1, #controlPrefix) == controlPrefix then
					table.insert(controlStops, path)
				end
				return -- a focusable is a leaf for this control's purposes
			end
			for _, child in node.children or {} do
				walk(child)
			end
		end
		walk(root)
		return pageStops, dotStops, controlStops
	end
	local summary = Compose.formula(function(use)
		local n = indices[use(spec.selection)]
		return "Page " .. n .. " of " .. #pages .. ": " .. pages[n].title
	end)
	local controller, rootPath, lastWidth, graph, offScroll, offIntent, subscribedPath
	local frameworkPosition
	owner.own(function()
		if offIntent then
			offIntent()
		end
		if offScroll then
			offScroll()
		end
	end)
	-- Optional chrome leaves gaps in the authored list; layout reads a dense one.
	local function dense(list: { any }, slots: number): { any }
		local out = {}
		for index = 1, slots do
			if list[index] ~= nil then
				table.insert(out, list[index])
			end
		end
		return out
	end
	local blueprint = require("../input/contribution").attach(
		UI.VStack({
			id = id,
			width = UI.fill(),
			height = spec.height or UI.fill(),
			gap = "s",
			children = dense({
				UI.ScrollView({
					id = "Pages",
					axis = "x",
					indicators = if spec.indicators == false then "auto" else "none",
					width = UI.fill(),
					height = UI.fill(),
					navigation = {
						targets = ids,
						target = target,
						snap = "page",
					},
					children = cards,
				}),
				if spec.summary == false then nil else UI.Text({ id = "Summary", text = summary, disclose = true }),
				UI.HStack({
					id = "Indicators",
					distribute = "center",
					wrap = true,
					hidden = spec.indicators == false,
					width = UI.fill(),
					align = "center",
					children = dots,
				}),
				if spec.controls == false
					then nil
					else UI.HStack({
						id = "Controls",
						width = UI.fill(),
						gap = "s",
						children = {
							UI.Button({
								id = "Previous",
								disclose = true,
								label = "Previous",
								width = UI.fill(),
								height = { type = "minMax", min = "targetSizes.minimum" },
								enabled = Compose.formula(function(use)
									return indices[use(spec.selection)] > 1
								end),
								onActivate = function()
									adjust(-1)
								end,
							}),
							UI.Button({
								id = "Next",
								disclose = true,
								label = "Next",
								width = UI.fill(),
								height = { type = "minMax", min = "targetSizes.minimum" },
								enabled = Compose.formula(function(use)
									return indices[use(spec.selection)] < #pages
								end),
								onActivate = function()
									adjust(1)
								end,
							}),
						},
					}),
			}, 4),
		}),
		{
			adjustAxis = "horizontal",
			adjustRepeat = true,
			focusGroups = function(root)
				local pageStops, dotStops, controlStops = survey(root)
				local groups: { any } = {}
				local ring = if #pageStops > 0 then pageStops else dotStops
				if #ring > 0 then
					table.insert(groups, {
						name = `page-view-{root.path}`,
						axis = "horizontal",
						--[[ ARRIVING PUTS YOU BACK WHERE YOU WERE. The ring inside this
							group follows the selected page (see `bindInputScope` below), so
							Down-then-Up lands on the page you were reading rather than on
							page one. ]]
						entry = "restore",
						wrap = false,
						order = ring,
					})
				end
				-- Previous/Next are ordinary buttons on their own line and keep their
				-- own run: this control declares the groups for its whole subtree, so
				-- a region left out of them would have no stops at all.
				if #controlStops > 0 then
					table.insert(groups, {
						name = `page-view-controls-{root.path}`,
						axis = "horizontal",
						entry = "nearest",
						wrap = false,
						order = controlStops,
					})
				end
				return groups
			end,
			adjustTargets = function(root)
				local targets = {}
				local pageStops, dotStops = survey(root)
				-- Left/Right PAGE from wherever the ring is standing inside the
				-- carousel — the page stops when the pages own the ring, and the dots
				-- both when they are the fallback and when a pointer put the ring on
				-- one, which is still a place it may legally stand.
				for _, path in pageStops do
					targets[path] = true
				end
				for _, path in dotStops do
					targets[path] = true
				end
				return targets
			end,
			handleAdjust = function(_, direction)
				return adjust(direction)
			end,
			bindFocusGraph = function(g)
				graph = g
			end,
			focusMoved = function(path)
				if writing or not rootPath or not path then
					return
				end
				local prefix = rootPath .. "/Pages/"
				if path:sub(1, #prefix) == prefix then
					local key = path:sub(#prefix + 1):match("^([^/]+)")
					if indices[key] and key ~= spec.selection:peek() then
						select(key)
					end
				end
			end,
			bindInputScope = function(input)
				owner.own(input.onTick(function()
					if not graph or not controller or not rootPath then
						return
					end
					local focused = graph.focused:peek()
					local prefix = rootPath .. "/Pages/"
					if not focused or focused:sub(1, #prefix) ~= prefix then
						return
					end
					local key = spec.selection:peek()
					local current = prefix .. key .. "/"
					if focused:sub(1, #current) == current then
						return
					end
					local host = controller.scrollHostFor(rootPath .. "/Pages", true)
					if not host or math.abs(host.offset - (indices[key] - 1) * host.rect.w) > 0.5 then
						return
					end
					local map = graph.focusMap()
					for _, entry in (map and map.traversal) or {} do
						if entry.path:sub(1, #current) == current then
							writing = true
							local ok = graph.focusOn(entry.path)
							writing = false
							if ok then
								return
							end
						end
					end
					if spec.indicators ~= false then
						graph.focusOn(rootPath .. "/Indicators/Dot" .. indices[key])
					elseif not graph.focusOn(rootPath .. "/Controls/Next") then
						graph.focusOn(rootPath .. "/Controls/Previous")
					end
				end))
			end,
			bindController = function(c)
				if c ~= controller then
					if offIntent then
						offIntent()
						offIntent = nil
					end
					if offScroll then
						offScroll()
						offScroll = nil
					end
					subscribedPath = nil
				end
				controller = c
			end,
			syncGeometry = function(_, root)
				if not root or not controller then
					return
				end
				rootPath = root.path
				if subscribedPath ~= rootPath then
					if offScroll then
						offScroll()
					end
					subscribedPath = rootPath
					if offIntent then
						offIntent()
					end
					offIntent = controller.observeScrollIntent(rootPath .. "/Pages", function(pos)
						frameworkPosition = pos.x
					end)
					offScroll = controller.observeScroll(rootPath .. "/Pages", function(pos)
						local frameworkWrite = frameworkPosition ~= nil and math.abs(pos.x - frameworkPosition) <= 0.5
						if frameworkWrite and pendingSelection then
							local host = controller.scrollHostFor(rootPath .. "/Pages", true)
							if host and math.abs(pos.x - (indices[pendingSelection] - 1) * host.rect.w) <= 0.5 then
								pendingSelection = nil
							end
							return
						end
						if not frameworkWrite then
							pendingSelection = nil
						end
						frameworkPosition = nil
						if writing then
							return
						end
						local host = controller.scrollHostFor(rootPath .. "/Pages", true)
						if not host or host.rect.w <= 0 then
							return
						end
						local index = math.clamp(math.floor(pos.x / host.rect.w + 0.5) + 1, 1, #pages)
						if ids[index] ~= spec.selection:peek() then
							writing = true
							scrollSelection = ids[index]
							spec.selection:set(ids[index])
							writing = false
						end
					end)
				end
				local host = controller.scrollHostFor(rootPath .. "/Pages", true)
				if not host then
					return
				end
				local width = host.rect.w
				if lastWidth and lastWidth ~= width then
					writing = true
					controller.scrollTo(
						rootPath .. "/Pages",
						{ x = (indices[spec.selection:peek()] - 1) * width, y = 0 }
					)
					writing = false
				end
				lastWidth = width
			end,
		}
	)
	local function dump()
		return {
			schema = "facet-page-view-dump/1",
			id = id,
			selection = spec.selection:peek(),
			index = indices[spec.selection:peek()],
			count = #pages,
		}
	end
	return table.freeze({
		blueprint = blueprint,
		dump = dump,
		dispose = function()
			owner.dispose()
		end,
	})
end
function pageView.build(Facet, core, spec)
	return ownedBuild(core, function(owner)
		return build(Facet, core, spec, owner)
	end)
end
return pageView
