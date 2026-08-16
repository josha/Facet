--!strict
--[[ MENU — a freestanding action menu attachable to ANY blueprint
	(navigation-and-menus brief §2 D2). This is what closes `.contextMenu`.

	ITEMS ARE VERBS, NOT VALUES, and that is the whole reason this is a control
	rather than a property on `newPopupButton`. That control's `value` is a
	`Signal<string>` and its `Option` is `{ id, label }`: picking an option WRITES
	a value. Picking a menu item RUNS something. A control that sometimes owns a
	value signal and sometimes does not is two controls in one, so this is the
	second one.

	WHAT IT DOES NOT OWN, ON PURPOSE. The rows are `menu_recipe`'s — the same
	recipe `row_actions`' floating menu wrote and `popup_button` now renders from.
	The placement is D1's (`presenter.presentAnchored`), so the edge flip, the
	along-edge shift, the safe box and the moving-source follow are the shipped
	ones. The focus scope, the trap, the restore and the tap-away catcher are the
	presenter's, reached by presenting through it. The touch long-press comes off
	the NORMALIZED GESTURE LAYER that has shipped since the native-substrate round
	with nothing consuming it as a trigger (`src/input/touch_gestures.luau`,
	`adapter.setTouchGestureHandlers`) — consumed, not re-recognized.

	THE FIVE TRIGGERS, one per input class plus the two pointer idioms:

	  activate   the primary verb — a tap, Return, ButtonA. Every class has it,
	             which is why it is the one trigger that is never optional: a menu
	             that only opens on right-click is a defect on two of three
	             classes.
	  secondary  the pointer's right button (`adapter.setSecondaryActivate`).
	  longPress  touch, through the normalized gesture stream.
	  keyboard   the context key, or Shift+F10 for a keyboard without one.
	  gamepad    a bindable face button.

	SUBMENUS ARE STRUCTURALLY UNBOUNDED AND DIAGNOSED AT DEPTH >= 2 (director
	ruling 2026-08-16, brief §6.4). SwiftUI documents no cap — `Menu` nests inside
	`Menu` arbitrarily — while the HIG says it is *"generally best to restrict
	them to a single level"*. An earlier draft capped at 2 and was wrong in both
	directions: it forbade what the API allows and permitted twice what the
	guidance advises. So nothing here refuses depth; `diagnostics()` names it.

	TOUCH DOES NOT NEST. When the presentation resolves to `sheet`, entering a
	submenu REPLACES the sheet's contents and grows a Back row, rather than
	floating a second panel over the first. Same item tree, two presentations —
	the `resolvePresentation` pattern, never a device branch. There is exactly one
	live surface under `sheet` at any depth, and `dump().surfaces` is where a test
	reads that rather than trusting the shape.

	A MENU WHOSE EVERY ITEM IS DISABLED STILL OPENS. Apple: *"If all of a menu's
	items are unavailable, the menu itself needs to remain available so people can
	open it and learn about the commands it contains."* Nothing here counts
	enabled items before presenting; swallowing the trigger is the "silently does
	nothing" class, and it is invisible until the one state nobody fixtured.
]]

local contribution = require("../input/contribution")
local menuRecipe = require("./menu_recipe")
local specGuard = require("../spec_guard")
local themePackage = require("../themes/package")

local menu = {}

--[[ THE TRIGGER KEYS, module scope so a host binding them on an engine's behalf
	names the same set the control does (`row_actions.ROW_KEYS`' precedent).

	`Menu` is the dedicated context key every desktop keyboard between the right
	Alt and Ctrl carries; Shift+F10 is the chord every platform accepts for the
	keyboards that dropped it, and it is what a laptop player actually has.
	`ButtonY` is the free right face button — `ButtonA` is Activate and `ButtonB`
	is Cancel, so neither could carry a second meaning. ]]
menu.TRIGGER_KEYS = {
	keyboard = { { keyCode = "Menu" }, { keyCode = "F10", modifiers = { shift = true } } },
	gamepad = { { keyCode = "ButtonY" } },
}
-- above the base screen's own Activate context, so the chord is not shadowed by
-- a screen that happens to have claimed the same key
menu.TRIGGER_KEY_PRIORITY = 1200

export type Item = {
	id: string?,
	label: string?,
	icon: string?, -- semantic icon NAME, never an asset id
	role: string?, -- "default" (the fallback) | "destructive"
	enabled: any?, -- boolean | Readable<boolean>
	onSelect: (() -> ())?, -- an ACTION item
	children: { Item }?, -- a SUBMENU item
	divider: boolean?, -- a rule between two groups
}

export type Spec = {
	id: string?,
	trigger: any, -- Blueprint, required: ANY node, not a built-in trigger
	items: { Item }, -- required, non-empty
	triggers: { string }?, -- which gestures open it; default all five
	presentation: string?, -- automatic | menu | sheet
	sizeClass: any?, -- string | Readable<string>
	interactionClasses: any?, -- table | Readable<table>
	onOpen: (() -> ())?,
	onClose: (() -> ())?,
}

local MENU_KEYS = specGuard.keySet({
	"id",
	"interactionClasses",
	"items",
	"onClose",
	"onOpen",
	"presentation",
	"sizeClass",
	"trigger",
	"triggers",
})
local ITEM_KEYS = specGuard.keySet({ "children", "divider", "enabled", "icon", "id", "label", "onSelect", "role" })
local TRIGGERS: { [string]: boolean } =
	table.freeze({ activate = true, secondary = true, longPress = true, keyboard = true, gamepad = true })
local ALL_TRIGGERS = { "activate", "secondary", "longPress", "keyboard", "gamepad" }
-- `inline` is a POPUP idiom: it puts rows in place under the trigger, which a
-- freestanding menu attached to an arbitrary node has nowhere to do. So the
-- resolved `inline` collapses to `menu` here; the rule itself stays shared.
local PRESENTATIONS: { [string]: boolean } = table.freeze({ automatic = true, menu = true, sheet = true })

local PANEL_ID = "Panel"
local BACK_ID = "Back"
local DUMP_SCHEMA = "luauui-menu-dump/1"

--[[ VALIDATE ONE LEVEL OF ITEMS, and every level below it. Returns the
	diagnostics; an outright authoring error throws instead, because a closed spec
	is a refusal and not a warning (constitution §4).

	`children` AND `onSelect` on one item is a SPEC ERROR, not a precedence rule
	(brief §2 D2). A precedence rule would mean one of the two silently never
	runs, and the author would find out from a player. ]]
local function validate(id: string, items: { Item }, path: string, depth: number, notes: { string })
	if type(items) ~= "table" or #items == 0 then
		error(`LuauUI newMenu('{id}'): {path} must be a non-empty array of items.`, 0)
	end
	local seen: { [string]: boolean } = {}
	local actionable = 0
	local destructiveAt: number? = nil
	for index, item in items do
		local where = `{path}[{index}]`
		if type(item) ~= "table" then
			error(`LuauUI newMenu('{id}'): {where} must be a table.`, 0)
		end
		specGuard.assertKnownKeys("newMenu", item, ITEM_KEYS, where)
		if item.divider == true then
			if item.label ~= nil or item.onSelect ~= nil or item.children ~= nil or item.icon ~= nil then
				error(
					`LuauUI newMenu('{id}'): {where} is a divider, so it carries nothing else — `
						.. "no label, icon, onSelect or children. A divider groups; it never responds.",
					0
				)
			end
			continue
		end
		local hasSelect = item.onSelect ~= nil
		local hasChildren = item.children ~= nil
		if hasSelect and hasChildren then
			error(
				`LuauUI newMenu('{id}'): {where} declares BOTH onSelect and children. That is a spec error, `
					.. "not a precedence rule: an item is an ACTION or a SUBMENU, and silently running one of "
					.. "the two is how an author finds out from a player.",
				0
			)
		end
		if not hasSelect and not hasChildren then
			error(
				`LuauUI newMenu('{id}'): {where} has neither onSelect nor children, so activating it would `
					.. "silently do nothing. Give it an action, give it children, or make it divider = true.",
				0
			)
		end
		if type(item.id) ~= "string" or type(item.label) ~= "string" then
			error(`LuauUI newMenu('{id}'): {where} needs a string id and a string label.`, 0)
		end
		local itemId = item.id :: string
		if string.find(itemId, "/", 1, true) then
			error(`LuauUI newMenu('{id}'): item id '{itemId}' must be path-safe (no "/").`, 0)
		end
		if seen[itemId] then
			error(`LuauUI newMenu('{id}'): two items in {path} share the id '{itemId}'.`, 0)
		end
		seen[itemId] = true
		actionable += 1
		if item.role == "destructive" then
			destructiveAt = index
		end
		if hasChildren then
			--[[ DEPTH IS UNBOUNDED, AND SAID OUT LOUD AT >= 2. `depth` counts
				submenu levels: a top-level submenu is 1, a submenu inside it is 2 —
				which is the level the HIG asks authors to reconsider and the API
				permits. Nothing refuses it. ]]
			if depth + 1 >= menuRecipe.DEPTH_ADVICE then
				table.insert(
					notes,
					`submenu '{itemId}' nests {depth + 1} levels deep. SwiftUI sets no cap and neither does `
						.. 'LuauUI, but the HIG advises a single level: "It can be difficult for people to '
						.. 'reveal multiple levels of hierarchical submenus."'
				)
			end
			validate(id, item.children :: { Item }, `{where}.children`, depth + 1, notes)
		end
	end
	if actionable == 0 then
		error(`LuauUI newMenu('{id}'): {path} is all dividers — a rule between nothing and nothing.`, 0)
	end
	--[[ THE ICON LINT (HIG: "provide icons for all menu items in a group, or none
		of them"). A GROUP is the run between two dividers, which is what makes this
		checkable at authoring time at all: the author has already said where the
		groups are. This is what keeps the new `icon` field from being a
		free-for-all — a half-iconned group looks fine in the one fixture it was
		authored in and reads as a rendering bug everywhere else. ]]
	local mixed = menuRecipe.mixedIconGroup(items)
	if mixed ~= nil then
		error(
			`LuauUI newMenu('{id}'): the {path} group starting at index {mixed} mixes items that declare an `
				.. "icon with items that do not. Give every item in a group an icon, or none of them "
				.. "(HIG: Menus). A divider starts a new group.",
			0
		)
	end
	-- ADVICE, not a refusal, exactly as the HIG frames it
	if actionable > menuRecipe.GROUP_SIZE_ADVICE then
		table.insert(
			notes,
			`{path} holds {actionable} items; the HIG advises that "if a submenu contains more than about `
				.. `{menuRecipe.GROUP_SIZE_ADVICE} items, consider creating a new menu".`
		)
	end
	-- HIG (context menus): a destructive item belongs at the END, so a slip on
	-- the way down the list lands on something recoverable
	if destructiveAt ~= nil and destructiveAt ~= #items then
		table.insert(
			notes,
			`{path}[{destructiveAt}] is destructive but is not the last item; the HIG lists destructive `
				.. "items at the end of the menu."
		)
	end
end

function menu.build(LuauUI: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("newMenu", spec, MENU_KEYS, "spec")
	local UI = LuauUI.UI
	local id = spec.id or "Menu"
	local scope = core:scope(`menu-{id}`)

	if type(spec.trigger) ~= "table" then
		error(
			`LuauUI newMenu('{id}'): \`trigger\` is the blueprint the menu attaches to — ANY node, not a `
				.. "built-in trigger. The contribution rides it; its layout is untouched.",
			0
		)
	end
	local diagnostics: { string } = {}
	validate(id, spec.items, "items", 0, diagnostics)

	local requestedPresentation = spec.presentation or "automatic"
	if not PRESENTATIONS[requestedPresentation] then
		error(
			`LuauUI newMenu('{id}'): unknown presentation '{requestedPresentation}' (automatic | menu | sheet). `
				.. "`inline` is a popup idiom — a freestanding menu has no trigger row to open into.",
			0
		)
	end

	local enabledTriggers: { [string]: boolean } = {}
	local requestedTriggers = spec.triggers or ALL_TRIGGERS
	if type(requestedTriggers) ~= "table" or #requestedTriggers == 0 then
		error(`LuauUI newMenu('{id}'): \`triggers\` is a non-empty array, or absent for all five.`, 0)
	end
	for _, name in requestedTriggers do
		if not TRIGGERS[name] then
			error(
				`LuauUI newMenu('{id}'): unknown trigger '{tostring(name)}' `
					.. `(activate | secondary | longPress | keyboard | gamepad).`,
				0
			)
		end
		enabledTriggers[name] = true
	end
	--[[ THE THREE-AXES RULE, ENFORCED AT AUTHORING TIME (constitution; brief §3).
		`activate` is the only trigger every input class has. Dropping it leaves the
		menu reachable on a mouse and a finger and on NEITHER a keyboard nor a pad
		unless both of those were also declared — and "a menu that only opens on
		right-click is a defect" is the brief's own wording. ]]
	if not enabledTriggers.activate and not (enabledTriggers.keyboard and enabledTriggers.gamepad) then
		error(
			`LuauUI newMenu('{id}'): dropping the 'activate' trigger leaves the menu unreachable on a `
				.. "keyboard or a gamepad. Keep 'activate', or declare both 'keyboard' and 'gamepad'.",
			0
		)
	end

	-- ===== state ==========================================================
	-- the open CHAIN: {} is the root level, { "adjust" } is one submenu deep.
	-- Held as a plain array behind a signal so a level change is one write.
	local openPath = scope:own(core:signal({} :: { string }))
	local isOpen = scope:own(core:signal(false))
	-- one entry per live surface, deepest last
	local handles: { any } = {}
	local presentModalFn: ((any, any?) -> any)? = nil
	local presentAnchoredFn: ((any, any?) -> any)? = nil
	local dismissFn: ((any) -> ())? = nil
	local controller: any = nil
	local rootPath: string? = nil
	local detachGestures: (() -> ())? = nil
	local keysContext: any = nil
	-- guards the feedback subscription below: a dismiss WE drove is bookkeeping,
	-- any other dismiss is the presenter's own outside-tap and closes everything
	local dismissingSelf = false
	--[[ ONE FOCUS GRAPH PER LIVE SURFACE, deepest last, parallel to `handles`.
		Right-arrow has to know which row the ring is standing on, and a control must
		never be handed a focus graph by its consumer (constitution §13) — the
		contribution's own `bindFocusGraph` is the canonical route. Kept per level
		rather than as one latest-wins reference, because leaving a submenu presents
		nothing new: a single reference would still point at the dismissed panel's
		graph and the next Right would read a focused path that no longer exists. ]]
	local graphs: { any } = {}
	local pendingGraph: any = nil
	--[[ THE OPERATIONS TABLE, DECLARED BEFORE THE PANEL THAT CALLS IT. A panel's
		contribution is built inside `presentLevel`, which runs before `enter`,
		`back` and `select` are assigned — so the handlers close over THIS table and
		read the field at call time. It is one indirection and it buys the control
		back from a module-level registry keyed by id, which two menus sharing an id
		would have silently shared. ]]
	local ops = {} :: any

	local function readFact(fact: any): any
		if type(fact) == "table" and (fact :: any).get ~= nil then
			return (fact :: any):get()
		end
		return fact
	end

	--[[ RESOLVED PER OPEN, never cached: reopening after a space or input-class
		change picks the right idiom without the control holding stale state. The
		rule is `menu_recipe`'s, shared with `popup_button` — two copies drift, and
		the drift only shows on the input class nobody tested. `inline` folds into
		`menu`: see PRESENTATIONS above. ]]
	local function useFact(use: any, fact: any): any
		if type(fact) == "table" and (fact :: any).get ~= nil then
			return use(fact)
		end
		return fact
	end

	--[[ A MEMO, not a plain read, because the answer has to be able to CHANGE
		while the menu is open. `sizeClass` and `interactionClasses` are the caller's
		Readables; a memo tracks them, so the observer below hears a live rotation or
		a keyboard being put down and re-presents. Read non-reactively (`:get()`) it
		would have been correct at every open and stale for the whole time one was
		up — the shape that makes a hot-switch defect device-only. ]]
	local presentationMemo = scope:own(core:memo(function(use)
		if requestedPresentation ~= "automatic" then
			return requestedPresentation
		end
		local classes = useFact(use, spec.interactionClasses)
		local touchLive = type(classes) == "table" and (classes :: any).touch == true
		local resolved = menuRecipe.resolvePresentation(
			menuRecipe.actionableCount(spec.items),
			useFact(use, spec.sizeClass),
			touchLive
		)
		return if resolved == "sheet" then "sheet" else "menu"
	end))

	local function presentationNow(): string
		return presentationMemo:get()
	end

	-- the item list at a given open chain, and the item a chain's last hop names
	local function itemsAt(chain: { string }): { Item }
		local list = spec.items
		for _, hop in chain do
			for _, item in list do
				if item.id == hop and item.children ~= nil then
					list = item.children :: { Item }
					break
				end
			end
		end
		return list
	end

	local function itemIn(list: { Item }, itemId: string): Item?
		for _, item in list do
			if item.id == itemId then
				return item
			end
		end
		return nil
	end

	local function surfaceIdFor(level: number): string
		return if level == 0 then `Menu-{id}` else `Menu-{id}-L{level}`
	end

	-- ===== the panel ======================================================
	local function buildPanel(presentation: string, chain: { string }): any
		local list = itemsAt(chain)
		local rowHeight = menuRecipe.rowHeightFor(presentation)
		local rows: { any } = {}
		--[[ THE BACK ROW IS THE SHEET'S ANSWER TO NESTING (brief §2 D2). Under
			`menu` a submenu is its own floating panel beside its parent, so the parent
			is still on screen and Back would be a second way to say what a click
			outside already says. Under `sheet` the contents were REPLACED, so without
			this row there is no way back up at all. It leads, because that is where a
			back affordance lives in every sheet a player has ever used. ]]
		if presentation == "sheet" and #chain > 0 then
			local glyph = themePackage.iconGlyph("chevron.leading") or "<"
			table.insert(
				rows,
				UI.Button({
					id = BACK_ID,
					label = `{glyph} Back`,
					width = { type = "fill", weight = 1 },
					height = { type = "fixed", px = rowHeight },
				})
			)
			table.insert(rows, menuRecipe.divider(UI, "BackRule"))
		end
		for index, item in list do
			if item.divider == true then
				table.insert(rows, menuRecipe.divider(UI, `Div-{index}`))
				continue
			end
			table.insert(
				rows,
				menuRecipe.row(UI, {
					id = `Item:{item.id}`,
					label = item.label,
					icon = item.icon,
					role = item.role,
					enabled = item.enabled,
					submenu = item.children ~= nil,
					height = rowHeight,
				})
			)
		end
		local isSheet = presentation == "sheet"
		local panel = UI.VStack({
			id = PANEL_ID,
			-- a SHEET spans the width a thumb reaches; a floating panel hugs its
			-- longest row, which is what lets D1 place it against the trigger
			anchor = if isSheet then "bottomLeft" else nil,
			width = if isSheet then { type = "fill", weight = 1 } else { type = "hug" },
			surface = "raised",
			padding = if isSheet then "s" else nil,
			gap = menuRecipe.ROW_GAP,
			children = rows,
		})
		return panel
	end

	-- ===== opening, entering, leaving, closing ============================
	local function dismissDeepest()
		table.remove(graphs)
		local handle = table.remove(handles)
		if handle == nil or dismissFn == nil then
			return
		end
		dismissingSelf = true
		dismissFn(handle)
		dismissingSelf = false
	end

	local function closeAll()
		if #handles == 0 and not isOpen:get() then
			return
		end
		while #handles > 0 do
			dismissDeepest()
		end
		openPath:set({})
		if isOpen:get() then
			isOpen:set(false)
			if spec.onClose ~= nil then
				pcall(spec.onClose)
			end
		end
	end

	local presentLevel: (level: number, presentation: string, chain: { string }) -> ()

	--[[ ONE SURFACE PER LEVEL UNDER `menu`, ONE SURFACE TOTAL UNDER `sheet`.
		The difference is entirely here, and it is a presentation branch rather than
		a device branch: `sheet` tears the current panel down before building the
		next one, so a submenu REPLACES the contents; `menu` leaves the parent
		standing and anchors the child to the row it came from. ]]
	function presentLevel(level: number, presentation: string, chain: { string })
		local panel = buildPanel(presentation, chain)
		local rowIds: { string } = {}
		for _, item in itemsAt(chain) do
			if item.divider ~= true then
				table.insert(rowIds, `Item:{item.id}`)
			end
		end
		local attached = contribution.attach(panel, {
			--[[ ONE GROUP, AND IT IS WHAT MAKES THE ARROWS EXIST. The presenter
				creates its HORIZONTAL Navigate action only when the surface has
				navigation groups (`navigateH` is nil otherwise), so without this
				declaration Left/Right would never reach `navigateIntercept` and the
				submenu arrows would silently do nothing — the "check that proves
				nothing" shape, one level down. The order is DOCUMENT order, matching
				the Tab rule shipped in `97e9d93`. ]]
			focusGroups = function(rootNode: any)
				local order: { string } = {}
				if presentation == "sheet" and #chain > 0 then
					table.insert(order, `{rootNode.path}/{BACK_ID}`)
				end
				for _, rowId in rowIds do
					table.insert(order, `{rootNode.path}/{rowId}`)
				end
				return { { name = `menu-{id}-{level}`, axis = "vertical", entry = "first", order = order } }
			end,
			bindFocusGraph = function(graph: any)
				pendingGraph = graph
			end,
			handleActivate = function(path: string, _meta: any?): boolean
				if string.match(path, `/{PANEL_ID}/{BACK_ID}$`) ~= nil then
					ops.back()
					return true
				end
				local itemId = string.match(path, `/{PANEL_ID}/Item:(.+)$`)
				if itemId == nil then
					return false
				end
				return ops.select(itemId)
			end,
			handleCancel = function(_focusedPath: string?): boolean
				if not isOpen:get() then
					return false
				end
				-- CANCEL CLOSES ONE LEVEL, tap-away closes ALL (brief §2 D2). They are
				-- different verbs: Cancel is "I am done with this submenu", an outside
				-- tap is "I am done with the menu". Conflating them is invisible until
				-- a submenu is open, which no smoke test does.
				ops.back()
				return true
			end,
			navigateIntercept = function(direction: string): boolean
				if not isOpen:get() then
					return false
				end
				if direction == "left" then
					if #openPath:get() == 0 then
						return false -- nothing to leave; let the ring have the arrow
					end
					ops.back()
					return true
				end
				if direction == "right" then
					return ops.enterFocused()
				end
				return false
			end,
		})

		local surfaceId = surfaceIdFor(level)
		local handle
		if presentation == "sheet" then
			handle = (presentModalFn :: any)(
				UI.Screen({
					id = surfaceId,
					children = {
						UI.Anchor({
							id = "Layer",
							width = { type = "fill", weight = 1 },
							height = { type = "fill", weight = 1 },
							children = { attached },
						}),
					},
				}),
				{
					-- the touch idiom: a dimming scrim under a bottom-anchored surface,
					-- which is what makes a sheet read as "the screen is waiting"
					scrim = "scrim",
					outsideTapCancel = true,
					cancelPolicy = "none",
				}
			)
		else
			--[[ D1 DOES THE PLACEMENT. Level 0 hangs under the trigger; a submenu
				hangs off its PARENT ROW, preferred edge trailing, flipping to leading
				at the screen edge — which is exactly what `anchor_placement.solve`
				already decides, so this passes `edge` and nothing else. `overflow` is
				left at the default clamp: a menu panel pulled back inside the safe box
				is readable, and unlike `row_actions`' own ruling there is no trigger
				underneath it to cover. ]]
			local sourcePath: string
			local edge: string
			if level == 0 then
				sourcePath = rootPath :: string
				edge = "bottom"
			else
				local parentChain = table.clone(chain)
				local last = table.remove(parentChain) :: string
				sourcePath = `/{surfaceIdFor(level - 1)}/Layer/Surface/{PANEL_ID}/Item:{last}`
				edge = "trailing"
			end
			handle = (presentAnchoredFn :: any)(attached, {
				id = surfaceId,
				modal = true,
				anchor = { source = { path = sourcePath }, edge = edge, align = "start" },
				-- "none" is fully transparent but STILL CATCHING: an outside tap
				-- closes the menu and is consumed, never clicking through to whatever
				-- was behind it, and the surface underneath is never dimmed. A menu is
				-- a lightweight popover, not a modal sheet.
				scrim = "none",
				outsideTapCancel = true,
				cancelPolicy = "none",
			})
		end
		table.insert(handles, handle)
		graphs[#handles] = pendingGraph
		pendingGraph = nil
		--[[ EVERY DISMISS PATH, not only the ones this file drives. The presenter's
			own outside-tap teardown runs entirely inside `applyOutsideOutcome` and
			never through `closeAll`, so without this an outside tap would tear the
			surface down while `isOpen` stayed stuck true forever (the exact defect
			`row_actions` found live and fixed the same way). And it is where
			"tap-away closes ALL" is implemented: a dismiss we did not drive means the
			player left the menu, not a level of it. ]]
		if handle.onFeedback ~= nil then
			handle.onFeedback(function(event: any)
				if type(event) == "table" and event.type == "dismiss" and not dismissingSelf then
					local index = table.find(handles, handle)
					if index ~= nil then
						table.remove(handles, index)
					end
					closeAll()
				end
			end)
		end
	end

	--[[ EVERY SURFACE FOR ONE OPEN CHAIN, from nothing. Under `menu` that is one
		panel per level, each anchored to the row above it; under `sheet` it is one
		panel showing the deepest level's items with a Back row. This is the ONE
		place the two presentations differ, and it is a presentation branch resolved
		from space and live input class — never a device name. ]]
	local function rebuild(chain: { string }, presentation: string)
		while #handles > 0 do
			dismissDeepest()
		end
		if presentation == "sheet" then
			presentLevel(0, presentation, chain)
			return
		end
		local walk: { string } = {}
		presentLevel(0, presentation, walk)
		for _, hop in chain do
			table.insert(walk, hop)
			presentLevel(#walk, presentation, table.clone(walk))
		end
	end

	function ops.enter(itemId: string)
		local chain = table.clone(openPath:get())
		table.insert(chain, itemId)
		openPath:set(chain)
		local presentation = presentationNow()
		if presentation == "sheet" then
			-- REPLACE, never stack (brief §2 D2): the sheet's contents become the
			-- submenu's, and the Back row `buildPanel` grows is the way out.
			dismissDeepest()
			presentLevel(0, presentation, chain)
		else
			presentLevel(#chain, presentation, chain)
		end
	end

	function ops.back()
		local chain = table.clone(openPath:get())
		if #chain == 0 then
			closeAll()
			return
		end
		table.remove(chain)
		openPath:set(chain)
		local presentation = presentationNow()
		dismissDeepest()
		if presentation == "sheet" then
			presentLevel(0, presentation, chain)
		end
	end

	--[[ THE HOT SWITCH (§C, UI-PARADIGM-002). An open menu holds in-flight state —
		the open chain — so a live interaction-class or size-class change is not free
		the way it is for a control whose every gesture is atomic. The chain CARRIES:
		the surfaces are rebuilt in the newly resolved idiom at exactly the depth the
		player had reached. Cancelling it instead would close a menu under a player
		who did nothing but rotate the device. ]]
	scope:own(core:observe(presentationMemo, function(presentation: string)
		if not isOpen:get() then
			return
		end
		rebuild(openPath:get(), presentation)
	end))

	function ops.select(itemId: string): boolean
		local chain = openPath:get()
		local item = itemIn(itemsAt(chain), itemId)
		if item == nil then
			return false
		end
		if readFact(item.enabled) == false then
			return true -- consumed, and deliberately inert: a disabled verb is not a verb
		end
		if item.children ~= nil then
			ops.enter(itemId)
			return true
		end
		-- close FIRST, so an onSelect that presents something of its own is not
		-- fighting a surface on its way out (row_actions' own ordering)
		closeAll()
		if item.onSelect ~= nil then
			pcall(item.onSelect)
		end
		return true
	end

	--[[ RIGHT ENTERS THE SUBMENU THE RING IS STANDING ON — and only a submenu.
		On a plain action row the arrow is not ours, so it falls through and the ring
		keeps whatever the surface does with it. That asymmetry is the point: Left
		always means "up a level" while a level exists, Right means "into this one"
		only when there is one to go into. ]]
	function ops.enterFocused(): boolean
		local graph = graphs[#graphs]
		local focused = if graph ~= nil then graph.focused:get() else nil
		if type(focused) ~= "string" then
			return false
		end
		local itemId = string.match(focused :: string, `/{PANEL_ID}/Item:(.+)$`)
		if itemId == nil then
			return false
		end
		local item = itemIn(itemsAt(openPath:get()), itemId)
		if item == nil or item.children == nil then
			return false
		end
		ops.enter(itemId)
		return true
	end

	local api = {} :: any

	function api.open(): boolean
		if isOpen:get() then
			return false
		end
		if rootPath == nil or (presentModalFn == nil and presentAnchoredFn == nil) then
			return false -- no presenter, or not mounted yet: nothing to present onto
		end
		--[[ NO ENABLED-ITEM COUNT HERE, AND THAT IS THE POINT. Apple: "If all of a
			menu's items are unavailable, the menu itself needs to remain available so
			people can open it and learn about the commands it contains." A trigger
			that silently does nothing is the worst failure this control could have,
			because the player cannot tell it from a dead button. ]]
		openPath:set({})
		isOpen:set(true)
		presentLevel(0, presentationNow(), {})
		if spec.onOpen ~= nil then
			pcall(spec.onOpen)
		end
		return true
	end

	function api.close()
		closeAll()
	end
	function api.closeLevel()
		ops.back()
	end
	function api.toggle()
		if isOpen:get() then
			closeAll()
		else
			api.open()
		end
	end
	function api.select(itemId: string): boolean
		return ops.select(itemId)
	end
	api.isOpen = isOpen
	api.openPath = openPath
	api.presentation = presentationNow
	function api.diagnostics(): { string }
		return table.clone(diagnostics)
	end

	-- routes an Activate landing on the TRIGGER itself
	function api.handleActivate(path: string, _meta: any?): boolean
		if not enabledTriggers.activate or rootPath == nil then
			return false
		end
		if path ~= rootPath then
			return false
		end
		api.toggle()
		return true
	end

	-- ===== the trigger's own contribution ================================
	local function wireGestures()
		if controller == nil or rootPath == nil or detachGestures ~= nil then
			return
		end
		if controller.attachContextGestures == nil then
			return -- an adapter without either channel; the other triggers still open it
		end
		local handlers: any = {}
		if enabledTriggers.longPress then
			handlers.onGesture = function(gesture: any)
				--[[ THE NORMALIZED GESTURE LAYER, CONSUMED (brief §2 D2: "the
					normalized gesture layer exists and nothing consumes it as a trigger
					— consume it"). `began` and not `ended`: the menu opens under the
					finger that is still down, which is what makes the press feel like it
					did something, and the release then lands on the open menu rather than
					re-toggling the trigger. ]]
				if type(gesture) == "table" and gesture.kind == "longPress" and gesture.state == "began" then
					api.open()
				end
			end
		end
		if enabledTriggers.secondary then
			handlers.onSecondary = function()
				api.open()
			end
		end
		if handlers.onGesture == nil and handlers.onSecondary == nil then
			return
		end
		detachGestures = controller.attachContextGestures(rootPath :: string, handlers)
		if detachGestures ~= nil then
			scope:own(detachGestures :: any)
		end
	end

	local actionSystemRef: any = nil
	local function ensureKeys()
		if actionSystemRef == nil or keysContext ~= nil then
			return
		end
		if not enabledTriggers.keyboard and not enabledTriggers.gamepad then
			return
		end
		local ctx = actionSystemRef.createContext({
			name = `MenuTrigger-{id}`,
			priority = menu.TRIGGER_KEY_PRIORITY,
			sink = true,
		})
		local action = ctx.createAction("MenuOpen", "Bool")
		if enabledTriggers.keyboard then
			for _, binding in menu.TRIGGER_KEYS.keyboard do
				action.bind(binding)
			end
		end
		if enabledTriggers.gamepad then
			for _, binding in menu.TRIGGER_KEYS.gamepad do
				action.bind(binding)
			end
		end
		action.onPressed(function()
			api.toggle()
		end)
		keysContext = ctx
		scope:own(function()
			if keysContext ~= nil then
				keysContext.destroy()
				keysContext = nil
			end
		end)
	end

	local blueprint = contribution.attach(spec.trigger, {
		handleActivate = api.handleActivate,
		syncGeometry = function(_rectOf: (string) -> any, rootNode: any?)
			if rootNode ~= nil and rootPath == nil then
				rootPath = rootNode.path
				wireGestures()
			end
		end,
		bindController = function(ctrl: any)
			controller = ctrl
			wireGestures()
		end,
		bindPresent = function(presentModal: any, dismiss: any, presentAnchored: any)
			presentModalFn = presentModal
			dismissFn = dismiss
			presentAnchoredFn = presentAnchored
		end,
		bindActionSystem = function(sys: any)
			actionSystemRef = sys
			ensureKeys()
		end,
		--[[ THE LONG-PRESS CARVE-OUT (see contribution.contextTriggers). Only while
			a context gesture is actually claimed: a menu declared without `longPress`
			or `secondary` takes nothing away from the disclosure plate. ]]
		contextTriggers = function(): { string }
			if rootPath == nil or not (enabledTriggers.longPress or enabledTriggers.secondary) then
				return {}
			end
			return { rootPath :: string }
		end,
	})

	local function dump()
		local function describe(list: { Item }, out: { any })
			for _, item in list do
				if item.divider == true then
					table.insert(out, { divider = true })
				else
					local entry: any = {
						id = item.id,
						label = item.label,
						icon = item.icon,
						role = item.role or "default",
						enabled = readFact(item.enabled) ~= false,
						kind = if item.children ~= nil then "submenu" else "action",
					}
					if item.children ~= nil then
						entry.children = {}
						describe(item.children :: { Item }, entry.children)
					end
					table.insert(out, entry)
				end
			end
		end
		local items: { any } = {}
		describe(spec.items, items)
		local chain = openPath:get()
		local presentation = presentationNow()
		local depth = #chain
		local text = if not isOpen:get()
			then `menu '{id}': closed, {menuRecipe.actionableCount(spec.items)} items, presents as {presentation}`
			else `menu '{id}': open at depth {depth} ({table.concat(chain, " > ")}), {presentation}, `
				.. `{#handles} surface(s)`
		return {
			schema = DUMP_SCHEMA,
			id = id,
			open = isOpen:get(),
			presentation = presentation,
			openPath = table.clone(chain),
			depth = depth,
			surfaces = #handles,
			triggers = table.clone(requestedTriggers),
			items = items,
			diagnostics = table.clone(diagnostics),
			text = text,
		}
	end

	return {
		blueprint = blueprint,
		api = api,
		presentation = presentationNow,
		dump = dump,
		dispose = function()
			closeAll()
			scope:dispose()
		end,
	}
end

return menu
