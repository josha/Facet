--!strict
local Compose = require("../vendor/compose/core")
local ownedBuild = require("../core/owned_build")
local ownedFormula = require("../core/owned_formula")
--[[ MENU — a freestanding action menu attachable to ANY blueprint
	(navigation-and-menus brief §2 D2). This is what closes the context-menu construct.

	ITEMS ARE VERBS, NOT VALUES, and that is the whole reason this is a control
	rather than a property on `UI.PopupButton`. That control's `value` is a
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
	ruling 2026-08-16). No structural cap exists — a menu nests inside a menu
	arbitrarily — while the interface guidance says it is generally best to restrict
	them to a single level. An earlier draft capped at 2 and was wrong in both
	directions: it forbade what the API allows and permitted twice what the
	guidance advises. So nothing here refuses depth; `diagnostics()` names it.

	TOUCH DOES NOT NEST. When the presentation resolves to `sheet`, entering a
	submenu REPLACES the sheet's contents and grows a Back row, rather than
	floating a second panel over the first. Same item tree, two presentations —
	the `resolvePresentation` pattern, never a device branch. There is exactly one
	live surface under `sheet` at any depth, and `dump().surfaces` is where a test
	reads that rather than trusting the shape.

	COMPACT DOES NOT NEST EITHER, AS A FRAMEWORK DEFAULT (director item 14,
	framework-gaps-phase2-followups). `resolvePresentation`'s own sheet
	branch answers "is touch primary", which is a different question from "does
	this fit" — a compact width with a pointer primary (a phone with a mouse, or
	Roblox Studio's own compact preset, which cannot inject touch at all) used to
	fall through to the floating `menu` idiom and stack a submenu over its own
	parent and the page beneath it. The automatic resolution now forces `sheet`
	whenever `sizeClass == "compact"`, independent of which pointer is live;
	medium/large keep the side-by-side expansion. Backing out of a level restores
	focus to the row that led into it, not the level's first row — `sheet`
	replaces its one surface on every level change, so nothing else remembers.
	The Back row's own WORD is `spec.backLabel` (review finding I1, fix round 1)
	— an English literal is now shown to every compact session by default, so a
	caller shipping to a localized audience sets it, the same "this construct
	invents no i18n of its own" stance `present/nav_bar.luau`'s `backLabel`
	already takes.

	A MENU WHOSE EVERY ITEM IS DISABLED STILL OPENS. The guidance: if all of a menu's
	items are unavailable, the menu itself needs to remain available so people can
	open it and learn about the commands it contains."* Nothing here counts
	enabled items before presenting; swallowing the trigger is the "silently does
	nothing" class, and it is invisible until the one state nobody fixtured.
]]

local contribution = require("../input/contribution")
local menuRecipe = require("./menu_recipe")
local anchorPlacement = require("../layout/anchor_placement")
local controlContract = require("../class_contract")
local specGuard = require("../spec_guard")
local surfaceEnv = require("../env/surface_env")
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

local specTypes = require("../spec_types/menu")
export type Item = specTypes.Item

export type Spec = specTypes.Spec

local MENU_KEYS = specGuard.keySet({
	"align",
	"backLabel",
	"edge",
	"env",
	"id",
	"interactionClasses",
	"items",
	"maxHeight",
	"onClose",
	"onOpen",
	"presentation",
	"sizeClass",
	"trigger",
	"label",
	"triggers",
	"width",
})
local ITEM_KEYS = specGuard.keySet({
	"avatar",
	"badge",
	"children",
	"divider",
	"enabled",
	"icon",
	"id",
	"label",
	"onSelect",
	"role",
	"checked",
	"selected",
	"value",
	"description",
	"dismiss",
	"onChange",
	"sectionTitle",
	"shortcutLabel",
})
local TRIGGERS: { [string]: boolean } =
	table.freeze({ activate = true, secondary = true, longPress = true, keyboard = true, gamepad = true })
local ALL_TRIGGERS = { "activate", "secondary", "longPress", "keyboard", "gamepad" }
-- `inline` is a POPUP idiom: it puts rows in place under the trigger, which a
-- freestanding menu attached to an arbitrary node has nowhere to do. So the
-- resolved `inline` collapses to `menu` here; the rule itself stays shared.
local PRESENTATIONS: { [string]: boolean } = table.freeze({ automatic = true, menu = true, sheet = true })

local PANEL_ID = "Panel"
local BACK_ID = "Back"
local DUMP_SCHEMA = "facet-menu-dump/1"

--[[ VALIDATE ONE LEVEL OF ITEMS, and every level below it. Returns the
	diagnostics; an outright authoring error throws instead, because a closed spec
	is a refusal and not a warning (constitution §4).

	`children` AND `onSelect` on one item is a SPEC ERROR, not a precedence rule
	(brief §2 D2). A precedence rule would mean one of the two silently never
	runs, and the author would find out from a player. ]]
local function validate(id: string, items: { Item }, path: string, depth: number, notes: { string })
	if type(items) ~= "table" or #items == 0 then
		error(`Facet UI.Menu('{id}'): {path} must be a non-empty array of items.`, 0)
	end
	local seen: { [string]: boolean } = {}
	local actionable = 0
	local destructiveAt: number? = nil
	for index, item in items do
		local where = `{path}[{index}]`
		if type(item) ~= "table" then
			error(`Facet UI.Menu('{id}'): {where} must be a table.`, 0)
		end
		specGuard.assertKnownKeys("UI.Menu", item, ITEM_KEYS, where)
		if item.divider == true then
			if item.label ~= nil or item.onSelect ~= nil or item.children ~= nil or item.icon ~= nil then
				error(
					`Facet UI.Menu('{id}'): {where} is a divider, so it carries nothing else — `
						.. "no label, icon, onSelect or children. A divider groups; it never responds.",
					0
				)
			end
			continue
		end

		local hasState = item.checked ~= nil or item.selected ~= nil
		assert(
			not (item.checked ~= nil and item.selected ~= nil),
			"Menu: checked and selected are distinct contracts; specify only one"
		)
		if hasState then
			local state = item.checked or item.selected
			assert(
				require("../selection_model").isWritable(state),
				"UI.Menu: checked/selected must be writable Compose cells the caller owns"
			)
			assert(item.checked == nil or type(state:peek()) == "boolean", "Menu: checked must hold a boolean")
			assert(item.selected == nil or item.value ~= nil, "Menu: a selected group item requires value")
			assert(
				item.children == nil and item.onSelect == nil,
				"Menu: a state item cannot also have children or onSelect; use onChange"
			)
		end
		assert(item.dismiss == nil or type(item.dismiss) == "boolean", "Menu: dismiss must be boolean")
		assert(
			item.avatar == nil or (type(item.avatar) == "table" and type(item.avatar.name) == "string"),
			"Menu: an item avatar must be an Avatar spec table with a name"
		)
		assert(
			item.shortcutLabel == nil or (type(item.shortcutLabel) == "string" and item.shortcutLabel ~= ""),
			'Menu: shortcutLabel is display text such as "Ctrl+B"; it binds nothing'
		)
		assert(
			item.onChange == nil or (hasState and type(item.onChange) == "function"),
			"Menu: onChange requires a state item and function"
		)
		local hasSelect = item.onSelect ~= nil or hasState
		local hasChildren = item.children ~= nil
		if hasSelect and hasChildren then
			error(
				`Facet UI.Menu('{id}'): {where} declares BOTH onSelect and children. That is a spec error, `
					.. "not a precedence rule: an item is an ACTION or a SUBMENU, and silently running one of "
					.. "the two is how an author finds out from a player.",
				0
			)
		end
		if not hasSelect and not hasChildren then
			error(
				`Facet UI.Menu('{id}'): {where} has neither onSelect nor children, so activating it would `
					.. "silently do nothing. Give it an action, give it children, or make it divider = true.",
				0
			)
		end
		if type(item.id) ~= "string" or type(item.label) ~= "string" then
			error(`Facet UI.Menu('{id}'): {where} needs a string id and a string label.`, 0)
		end
		local itemId = item.id :: string
		if string.find(itemId, "/", 1, true) then
			error(`Facet UI.Menu('{id}'): item id '{itemId}' must be path-safe (no "/").`, 0)
		end
		if seen[itemId] then
			error(`Facet UI.Menu('{id}'): two items in {path} share the id '{itemId}'.`, 0)
		end
		seen[itemId] = true
		actionable += 1
		if item.role == "destructive" then
			destructiveAt = index
		end
		if hasChildren then
			--[[ DEPTH IS UNBOUNDED, AND SAID OUT LOUD AT >= 2. `depth` counts
				submenu levels: a top-level submenu is 1, a submenu inside it is 2 —
				which is the level the interface guidance asks authors to reconsider and the API
				permits. Nothing refuses it. ]]
			if depth + 1 >= menuRecipe.DEPTH_ADVICE then
				table.insert(
					notes,
					`submenu '{itemId}' nests {depth + 1} levels deep. Facet sets no cap, but the `
						.. "interface guidance advises a single level: it can be difficult for people to "
						.. 'reveal multiple levels of hierarchical submenus."'
				)
			end
			validate(id, item.children :: { Item }, `{where}.children`, depth + 1, notes)
		end
	end
	if actionable == 0 then
		error(`Facet UI.Menu('{id}'): {path} is all dividers — a rule between nothing and nothing.`, 0)
	end
	--[[ THE ICON LINT: provide icons for all menu items in a group, or none
		of them"). A GROUP is the run between two dividers, which is what makes this
		checkable at authoring time at all: the author has already said where the
		groups are. This is what keeps the new `icon` field from being a
		free-for-all — a half-iconned group looks fine in the one fixture it was
		authored in and reads as a rendering bug everywhere else. ]]
	local mixed = menuRecipe.mixedIconGroup(items)
	if mixed ~= nil then
		error(
			`Facet UI.Menu('{id}'): the {path} group starting at index {mixed} mixes items that declare an `
				.. "icon with items that do not. Give every item in a group an icon, or none of them "
				.. "A divider starts a new group.",
			0
		)
	end
	-- ADVICE, not a refusal, exactly as the interface guidance frames it
	if actionable > menuRecipe.GROUP_SIZE_ADVICE then
		table.insert(
			notes,
			`{path} holds {actionable} items; the interface guidance advises that if a submenu contains more than about `
				.. `{menuRecipe.GROUP_SIZE_ADVICE} items, consider creating a new menu".`
		)
	end
	-- Context-menu guidance: a destructive item belongs at the END, so a slip on
	-- the way down the list lands on something recoverable
	if destructiveAt ~= nil and destructiveAt ~= #items then
		table.insert(
			notes,
			`{path}[{destructiveAt}] is destructive but is not the last item; the interface guidance lists destructive `
				.. "items at the end of the menu."
		)
	end
end

local function build(Facet, core, spec, owner)
	specGuard.assertKnownKeys("UI.Menu", spec, MENU_KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "Menu"
	-- the ROOT panel's placement and every panel's size; absent is unchanged
	anchorPlacement.assertEdge(spec.edge, `UI.Menu('{id}') edge`)
	anchorPlacement.assertAlign(spec.align, `UI.Menu('{id}') align`)
	if spec.width ~= nil and (type(spec.width) ~= "table" or type(spec.width.type) ~= "string") then
		error(
			`Facet UI.Menu('{id}'): \`width\` is a dimension table such as \{ type = "hug", max = "controls.popup.panelWidth" }.`,
			0
		)
	end
	local maxHeight = spec.maxHeight
	if
		maxHeight ~= nil
		and (type(maxHeight) ~= "number" or maxHeight ~= maxHeight or maxHeight <= 0 or maxHeight == math.huge)
	then
		error(`Facet UI.Menu('{id}'): \`maxHeight\` is a positive finite number of px, chrome included.`, 0)
	end
	-- a bounded list scrolls its rows one level deeper; every path below reads this
	local ROWS = if maxHeight ~= nil then "/List/Rows" else ""
	if spec.label ~= nil then
		assert(type(spec.label) == "string", "UI.Menu.label must be a string")
		assert(spec.trigger == nil, "Menu: use label or trigger, not both")
		spec = table.clone(spec)
		spec.trigger = UI.Button({ id = id, label = spec.label })
	end

	if type(spec.trigger) ~= "table" then
		error(
			`Facet UI.Menu('{id}'): \`trigger\` is the blueprint the menu attaches to — ANY node, not a `
				.. "built-in trigger. The contribution rides it; its layout is untouched.",
			0
		)
	end
	local diagnostics: { string } = {}
	validate(id, spec.items, "items", 0, diagnostics)

	--[[ `presentation` accepts a plain string OR a `Readable<string>` (gap 20,
		framework-gaps-phase2). A STATIC misspelling still fails fast, at
		construction, exactly as before; a REACTIVE value is domain-checked at
		each read instead (`presentationMemo` below), the same split every other
		reactive prop in this framework uses (`scale`/`rotation`'s
		`schema.checkX` pattern) because a Readable's future values cannot be
		known here. ]]
	local presentationIsReadable = Compose.isReadable(spec.presentation)
	local staticPresentation = if presentationIsReadable then nil else (spec.presentation or "automatic")
	if staticPresentation ~= nil and not PRESENTATIONS[staticPresentation] then
		error(
			`Facet UI.Menu('{id}'): unknown presentation '{tostring(staticPresentation)}' (automatic | menu | sheet). `
				.. "`inline` is a popup idiom — a freestanding menu has no trigger row to open into.",
			0
		)
	end

	local enabledTriggers: { [string]: boolean } = {}
	local requestedTriggers = spec.triggers or ALL_TRIGGERS
	if type(requestedTriggers) ~= "table" or #requestedTriggers == 0 then
		error(`Facet UI.Menu('{id}'): \`triggers\` is a non-empty array, or absent for all five.`, 0)
	end
	for _, name in requestedTriggers do
		if not TRIGGERS[name] then
			error(
				`Facet UI.Menu('{id}'): unknown trigger '{tostring(name)}' `
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
			`Facet UI.Menu('{id}'): dropping the 'activate' trigger leaves the menu unreachable on a `
				.. "keyboard or a gamepad. Keep 'activate', or declare both 'keyboard' and 'gamepad'.",
			0
		)
	end

	-- ===== state ==========================================================
	-- the open CHAIN: {} is the root level, { "adjust" } is one submenu deep.
	-- Held as a plain array behind a signal so a level change is one write.
	local openPath = Compose.cell({} :: { string })
	local isOpen = Compose.cell(false)
	local disposed = false
	local mountedNode
	local function available()
		return not disposed and not controlContract.isDisabled(mountedNode)
	end
	-- State bindings live once per item, independently of transient panels.
	local selectedByItem, hiddenByItem = {}, {}
	local function bindStates(items)
		for _, item in items do
			if item.checked ~= nil or item.selected ~= nil then
				local selected = ownedFormula(owner, function(use)
					return if item.checked ~= nil then use(item.checked) else use(item.selected) == item.value
				end)
				selectedByItem[item] = selected
				hiddenByItem[item] = ownedFormula(owner, function(use)
					return not use(selected)
				end)
			end
			if item.children then
				bindStates(item.children)
			end
		end
	end
	bindStates(spec.items)

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
		if Compose.isReadable(fact) then
			return (fact :: any):peek()
		end
		return fact
	end

	--[[ RESOLVED PER OPEN, never cached: reopening after a space or input-class
		change picks the right idiom without the control holding stale state. The
		rule is `menu_recipe`'s, shared with `popup_button` — two copies drift, and
		the drift only shows on the input class nobody tested. `inline` folds into
		`menu`: see PRESENTATIONS above. ]]
	local function useFact(use: any, fact: any): any
		if Compose.isReadable(fact) then
			return use(fact)
		end
		return fact
	end

	--[[ A MEMO, not a plain read, because the answer has to be able to CHANGE
		while the menu is open. `sizeClass` and `interactionClasses` are the caller's
		Readables; a memo tracks them, so the observer below hears a live rotation or
		a keyboard being put down and re-presents. Read non-reactively (`:peek()`) it
		would have been correct at every open and stale for the whole time one was
		up — the shape that makes a hot-switch defect device-only. ]]
	--[[ THE FACTS, AND WHERE THEY COME FROM. Both were spec keys and
		nothing else, and `interactionClasses` was wired at exactly ONE place in all
		of `examples/` — so the touch->sheet rung, the reference platform's own
		default, fired nowhere. Authored keys still win; otherwise the surface's own
		environment answers, and a menu that can adapt but has no environment
		refuses to construct rather than presenting a desktop plate to a thumb. ]]
	local envForFacts: any = nil
	local factsFrom = "spec"
	-- resolve env facts whenever the presentation MIGHT resolve to "automatic"
	-- at some point in its life: the static "automatic" case (as before), or a
	-- Readable whose future values this constructor cannot see (gap 20) — a
	-- forced-then-later-automatic flip must not find the facts it needs
	-- unresolved because construction guessed it would never need them.
	if
		(presentationIsReadable or staticPresentation == "automatic")
		and (spec.sizeClass == nil or spec.interactionClasses == nil)
	then
		local env, source = surfaceEnv.resolve(
			"UI.Menu",
			id,
			core,
			spec.env,
			"an automatic presentation adapts to the size class and the live interaction class"
		)
		envForFacts = env
		factsFrom = source
	end
	local sizeClassSource: any = spec.sizeClass or (if envForFacts ~= nil then envForFacts:get("sizeClass") else nil)
	local classesSource: any = spec.interactionClasses
		or (if envForFacts ~= nil then envForFacts:get("interactionClasses") else nil)

	local presentationMemo = ownedFormula(owner, function(use)
		local requested = useFact(use, spec.presentation)
		if requested ~= nil and requested ~= "automatic" then
			if not PRESENTATIONS[requested] then
				error(
					`Facet UI.Menu('{id}'): unknown presentation '{tostring(requested)}' (automatic | menu | sheet). `
						.. "`inline` is a popup idiom — a freestanding menu has no trigger row to open into.",
					0
				)
			end
			return requested
		end
		-- PRIMARY, not merely present: one predicate, in the recipe
		local classes = useFact(use, classesSource)
		local touchLive = menuRecipe.touchPrimary(classes)
		local liveSizeClass = useFact(use, sizeClassSource)
		local resolved = menuRecipe.resolvePresentation(
			menuRecipe.actionableCount(spec.items),
			liveSizeClass,
			touchLive,
			classes ~= nil and classes.primary == "gamepad"
		)
		-- Cascades require both room and pointer precision. A short gamepad root
		-- still needs one panel when entering a submenu; Back pops its history.
		if
			resolved ~= "sheet" and (liveSizeClass == "compact" or (classes ~= nil and classes.primary == "gamepad"))
		then
			resolved = "sheet"
		end
		return if resolved == "sheet" then "sheet" else "menu"
	end)

	local function presentationNow(): string
		return presentationMemo:peek()
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
					-- `spec.backLabel` (review finding I1): the caller's localized
					-- word, or the framework's own English fallback when absent —
					-- see the Spec field's own comment for why this row, unlike
					-- `nav_bar`'s, HAS a fallback at all.
					label = `{glyph} {spec.backLabel or "Back"}`,
					-- THE SAME DEGRADE PATH EVERY OTHER ROW IN THIS PANEL ALREADY
					-- HAS (`menu_recipe.row`'s own doctrine: label first, icon on
					-- `compactLabel`, deliberately NO `prefer` — "a menu row keeps
					-- its label... the icon rides `compactLabel`, which draws it
					-- only when the words genuinely do not fit"). A localized
					-- `backLabel` — measured up to ~1.4x an English source under
					-- pseudo-localization, binding R9-family — degrades to the
					-- chevron alone rather than clipping; unlike `nav_bar`'s Back
					-- button this one is NOT `prefer`red, because it is a row
					-- inside this SAME panel's list, not a chrome-bar affordance.
					compactLabel = { icon = "chevron.leading" },
					width = { type = "fill", weight = 1 },
					height = { type = "fixed", px = rowHeight },
				})
			)
			table.insert(rows, menuRecipe.divider(UI, "BackRule"))
		end
		--[[ ONE CARD, FLAT ROWS (user review of the desktop split button's menu,
			2026-09-12: *"the open menu still reads as stacked rounded rects"*). The
			anchored panel is the plate — `surface = "raised"` already carries the
			corner and the stroke — so its rows carry neither: they go `plain`, a
			hairline separates every adjacent pair, the selected row's fill IS its own
			surface (so it fits the row exactly, by construction rather than by two
			rectangles agreeing), and the first and last rows take the card's radius on
			their outer corners so nothing paints over the plate's arc. The rules and
			the four constants are `menu_recipe`'s, shared with the picker's popover.

			The SHEET keeps the shape it had: it is a full-width surface anchored to
			the bottom edge with its own padding, not a plate hugging a trigger, and
			its rows have no card ends to round. So this is a presentation branch, like
			every other difference between the two idioms in this file. ]]
		local isCard = presentation ~= "sheet"
		local total = 0
		for _, item in list do
			if item.divider ~= true then
				total += 1
			end
		end
		local emitted = 0
		for index, item in list do
			if item.divider == true then
				--[[ INSIDE THE CARD A DIVIDER IS THE HAIRLINE THE CARD ALREADY DRAWS
					between these two rows, so it adds nothing rather than a second rule:
					two touching hairlines read as a 2px seam, and the author's grouping
					is already in the order the rows appear. The floating/inline idiom
					keeps the explicit rule it has always drawn. ]]
				if not isCard then
					table.insert(rows, menuRecipe.divider(UI, `Div-{index}`))
				end
				continue
			end
			emitted += 1
			if isCard and emitted > 1 then
				table.insert(rows, menuRecipe.divider(UI, `Rule-{emitted}`))
			end
			-- a section heading is a caption before its row: never a stop, never a press
			if item.sectionTitle ~= nil then
				table.insert(
					rows,
					UI.VStack({
						id = `Section:{item.id}`,
						width = UI.fill(),
						padding = { left = "s", right = "s", top = "xs" },
						children = { menuRecipe.sectionHeading(UI, item.sectionTitle) },
					})
				)
			end
			local spec = {
				id = `Item:{item.id}`,
				badge = item.badge,
				avatar = menuRecipe.avatarNode(Facet, item.avatar),
				-- display only: the words of a shortcut some other binding owns
				trailing = if item.shortcutLabel ~= nil
					then UI.Text({
						id = "Shortcut",
						text = item.shortcutLabel,
						textSize = "caption",
						role = "secondary",
					})
					else nil,

				label = item.label,
				description = item.description,
				indicator = if item.checked ~= nil then "check" elseif item.selected ~= nil then "radio" else nil,
				markHidden = hiddenByItem[item],
				selected = selectedByItem[item],
				icon = item.icon,
				role = item.role,
				enabled = item.enabled,
				submenu = item.children ~= nil,
				-- a plain row's label leads, as a badge or shortcut row's does
				leading = true,
				height = rowHeight,
			}
			if not isCard then
				table.insert(rows, menuRecipe.row(UI, spec))
				continue
			end
			(spec :: any).platedSelection = true
			local position = if total == 1
				then "only"
				elseif emitted == 1 then "first"
				elseif emitted == total then "last"
				else "middle"
			table.insert(rows, menuRecipe.cardRow(UI, spec :: any, position))
		end
		local isSheet = presentation == "sheet"
		-- a row with a mark, a second line, or a fill-width part (badge, shortcut,
		-- section heading) has no natural width to hug: it takes the themed width
		local rich = false
		for _, item in list do
			if
				item.checked ~= nil
				or item.selected ~= nil
				or item.description ~= nil
				or item.badge ~= nil
				or item.shortcutLabel ~= nil
				or item.sectionTitle ~= nil
			then
				rich = true
				break
			end
		end
		if maxHeight ~= nil then
			-- THE BOUNDED LIST: the rows scroll inside the author's height, less the
			-- panel's own chrome (the `raised` slot's insets a package carves)
			rows = {
				UI.ScrollView({
					id = "List",
					axis = "y",
					chromeReserve = "none",
					width = UI.fill(),
					-- the PANEL carries the author's bound (chrome included); the list is
					-- the part that gives height back when the rows outgrow it
					shrinkWeight = 1,
					children = {
						UI.VStack({
							id = "Rows",
							width = UI.fill(),
							gap = if isCard then 0 else menuRecipe.ROW_GAP,
							children = rows,
						}),
					},
				}),
			}
		end
		local panel = UI.VStack({
			id = PANEL_ID,
			-- a SHEET spans the width a thumb reaches; a floating panel hugs its
			-- longest row, which is what lets D1 place it against the trigger
			anchor = if isSheet then "bottomLeft" else nil,
			height = if maxHeight ~= nil then { type = "hug", max = maxHeight } else nil,
			width = if isSheet
				then { type = "fill", weight = 1 }
				elseif spec.width ~= nil then spec.width
				elseif rich then { type = "fixed", px = "controls.popup.panelWidth" }
				else { type = "hug" },
			surface = "raised",
			padding = if isSheet then "s" else nil,
			-- the card's rhythm is the hairline BETWEEN two rows, drawn as a real
			-- `UI.Divider`, so there is no gap of surface showing through as well:
			-- a gap plus a rule is a 2px seam, and it is what made a highlight look
			-- under-filled at the row's top and bottom edge
			gap = if isCard then 0 else menuRecipe.ROW_GAP,
			children = rows,
		})
		if isSheet then
			return panel
		end
		-- the FADE GROUP the materialize transition needs (picker_menu's exact
		-- `Popup` shape, 2026-09-11): one CanvasGroup around the floating panel so
		-- it grows in as one plate rather than row by row
		return UI.ZStack({
			id = "Popup",
			canvasGroup = true,
			width = { type = "hug" },
			height = { type = "content" },
			children = { panel },
		})
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
		if #handles == 0 and not isOpen:peek() then
			return
		end
		while #handles > 0 do
			dismissDeepest()
		end
		openPath:set({})
		if isOpen:peek() then
			isOpen:set(false)
			if spec.onClose ~= nil then
				pcall(spec.onClose)
			end
		end
	end

	local presentLevel: (level: number, presentation: string, chain: { string }, direction: string?) -> ()

	--[[ ONE SURFACE PER LEVEL UNDER `menu`, ONE SURFACE TOTAL UNDER `sheet`.
		The difference is entirely here, and it is a presentation branch rather than
		a device branch: `sheet` tears the current panel down before building the
		next one, so a submenu REPLACES the contents; `menu` leaves the parent
		standing and anchors the child to the row it came from. ]]
	function presentLevel(level: number, presentation: string, chain: { string }, direction: string?)
		-- `buildPanel`'s own `isSheet` is scoped to that function; recomputed here
		-- once per open/level rather than threaded through as another return
		local isSheet = presentation == "sheet"
		local rowIds: { string } = {}
		for _, item in itemsAt(chain) do
			if item.divider ~= true then
				table.insert(rowIds, `Item:{item.id}`)
			end
		end
		local function buildAttached()
			return contribution.attach(buildPanel(presentation, chain), {
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
					-- a non-sheet root is the `Popup` fade group the materialize
					-- transition wraps around `Panel`, one level above the rows it used
					-- to sit on directly; a sheet's root IS `Panel`, unwrapped
					local rowRoot = (if isSheet then rootNode.path else `{rootNode.path}/{PANEL_ID}`) .. ROWS
					for _, rowId in rowIds do
						table.insert(order, `{rowRoot}/{rowId}`)
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
					local itemId = string.match(path, `/{PANEL_ID}{ROWS}/Item:(.+)$`)
					if itemId == nil then
						return false
					end
					return ops.select(itemId)
				end,
				handleCancel = function(_focusedPath: string?): boolean
					if not isOpen:peek() then
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
					if not isOpen:peek() then
						return false
					end
					if direction == "left" then
						if #openPath:peek() == 0 then
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
		end
		local surfaceId = surfaceIdFor(level)
		local handle
		if presentation == "sheet" then
			local function buildSheet()
				return UI.Screen({
					id = surfaceId,
					children = {
						UI.Anchor({
							id = "Layer",
							width = UI.fill(),
							height = UI.fill(),
							children = { buildAttached() },
						}),
					},
				})
			end
			handle = (presentModalFn :: any)(if Facet.surfaces then buildSheet else buildSheet(), {
				-- the touch idiom: a dimming scrim under a bottom-anchored surface,
				-- which is what makes a sheet read as "the screen is waiting"
				scrim = "scrim",
				outsideTapCancel = true,
				cancelPolicy = "none",
				transition = { enter = direction or "slide-up", exit = "slide-down" },
			})
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
				edge = spec.edge or "bottom"
			else
				local parentChain = table.clone(chain)
				local last = table.remove(parentChain) :: string
				sourcePath = `/{surfaceIdFor(level - 1)}/Layer/Surface/Popup/{PANEL_ID}{ROWS}/Item:{last}`
				edge = "trailing"
			end
			handle = (presentAnchoredFn :: any)(if Facet.surfaces then buildAttached else buildAttached(), {
				id = surfaceId,
				modal = true,
				-- the same attachment every control-presented popover keeps (picker
				-- round, 2026-09-11): a tight gap under the source and the screen's
				-- content inset as the margin it will not cross
				anchor = {
					source = { path = sourcePath },
					edge = edge,
					align = if level == 0 then spec.align or "start" else "start",
					gap = "xs",
					margin = "m",
				},
				-- "none" is fully transparent but STILL CATCHING: an outside tap
				-- closes the menu and is consumed, never clicking through to whatever
				-- was behind it, and the surface underneath is never dimmed. A menu is
				-- a lightweight popover, not a modal sheet.
				scrim = "none",
				outsideTapCancel = true,
				cancelPolicy = "none",
				-- the short fade-and-grow every pop-up menu materializes with; an
				-- anchored surface with no pivot of its own grows from the corner it
				-- hangs at (render/transitions `pivot` inference)
				-- `plate = "fades"`: the Popup IS its Panel — the popover shape whose
				-- backdrop is the scrim behind the whole surface, not the panel's
				-- own face (blueprint_schema's TRANSITION_PLATES header)
				transition = { enter = "materialize", plate = "fades", scale = 1.015 },
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
		if not available() then
			return
		end
		local chain = table.clone(openPath:peek())
		table.insert(chain, itemId)
		openPath:set(chain)
		local presentation = presentationNow()
		if presentation == "sheet" then
			-- REPLACE, never stack (brief §2 D2): the sheet's contents become the
			-- submenu's, and the Back row `buildPanel` grows is the way out.
			dismissDeepest()
			presentLevel(0, presentation, chain, "slide-left")
		else
			presentLevel(#chain, presentation, chain)
		end
	end

	function ops.back()
		local chain = table.clone(openPath:peek())
		if #chain == 0 then
			closeAll()
			return
		end
		local leavingId = table.remove(chain)
		openPath:set(chain)
		local presentation = presentationNow()
		dismissDeepest()
		if presentation == "sheet" then
			presentLevel(0, presentation, chain, "slide-right")
			--[[ FOCUS RETURNS TO THE ROW THAT LED HERE, not the level's own
				`entry = "first"` default (director item 14: "state preserved —
				scroll/focus position on back"). `sheet` REPLACES its one surface on
				every level change, so the fresh scope `presentLevel` just built has
				no memory of where the player was — without this, backing out of ANY
				level always lands on that level's first row (or its Back row, one
				deeper), which is sane on the way IN and wrong on the way OUT: the
				player just left `leavingId`, and that is what they were looking at.
				`graph.focusOn` is the same technique
				`present/surface_lifecycle.luau`'s `raise` uses to restore a
				remembered focus across an identical remove-then-push scope rebuild;
				it is a harmless no-op if the id is no longer present (an author
				removed it while the level was open). ]]
			local graph = graphs[#graphs]
			if graph ~= nil then
				graph.focusOn(`/{surfaceIdFor(0)}/Layer/{PANEL_ID}{ROWS}/Item:{leavingId}`)
			end
		end
	end

	--[[ THE HOT SWITCH (§C, UI-PARADIGM-002). An open menu holds in-flight state —
		the open chain — so a live interaction-class or size-class change is not free
		the way it is for a control whose every gesture is atomic. The chain CARRIES:
		the surfaces are rebuilt in the newly resolved idiom at exactly the depth the
		player had reached. Cancelling it instead would close a menu under a player
		who did nothing but rotate the device. ]]
	owner.watchStatic(presentationMemo, function(presentation: string)
		if not isOpen:peek() then
			return
		end
		rebuild(openPath:peek(), presentation)
	end)

	-- A submenu cannot retain input ownership after its parent becomes unavailable.
	local validOpenChain = ownedFormula(owner, function(use)
		local chain, valid, items = use(openPath), {}, spec.items
		for _, identity in chain do
			local item = itemIn(items, identity)
			if not item or item.children == nil then
				break
			end
			local state = item.enabled
			if Compose.isReadable(state) then
				state = use(state)
			end
			if state == false then
				break
			end
			table.insert(valid, identity)
			items = item.children
		end
		return valid
	end)
	owner.watchStatic(validOpenChain, function(valid)
		if not isOpen:peek() or #valid == #openPath:peek() then
			return
		end
		openPath:set(valid)
		rebuild(valid, presentationNow())
	end)

	function ops.select(itemId: string): boolean
		if not available() then
			return false
		end
		local chain = openPath:peek()
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

		local hasState = item.checked ~= nil or item.selected ~= nil
		if item.dismiss == true or (item.dismiss ~= false and not hasState) then
			closeAll()
		end
		if hasState then
			local state = item.checked or item.selected
			local nextValue = if item.checked ~= nil then not state:peek() else item.value
			if state:peek() ~= nextValue then
				state:set(nextValue)
				if item.onChange then
					pcall(item.onChange, nextValue)
				end
			end
		end
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
		local focused = if graph ~= nil then graph.focused:peek() else nil
		if type(focused) ~= "string" then
			return false
		end
		local itemId = string.match(focused :: string, `/{PANEL_ID}{ROWS}/Item:(.+)$`)
		if itemId == nil then
			return false
		end
		local item = itemIn(itemsAt(openPath:peek()), itemId)
		if item == nil or item.children == nil then
			return false
		end
		ops.enter(itemId)
		return true
	end

	local api = {} :: any

	function api.open(): boolean
		if not available() then
			return false
		end
		if isOpen:peek() then
			return false
		end
		--[[ THE FUNCTION THIS IDIOM ACTUALLY NEEDS, not "either of them". `bindPresent`
			gained `presentAnchored` as a THIRD argument, and the seam's own contract is
			that a control must work when what it wanted never arrives (a bare mount in
			a unit test hands over nothing at all). A presenter that predates the third
			argument would leave `presentAnchoredFn` nil while `presentModalFn` is fine
			— and a check for "either" would then call nil on the `menu` idiom and
			crash, which is a worse answer than not opening. ]]
		local presentation = presentationNow()
		local needed = if presentation == "sheet" then presentModalFn else presentAnchoredFn
		if rootPath == nil or needed == nil then
			return false -- no presenter, or not mounted yet: nothing to present onto
		end
		--[[ NO ENABLED-ITEM COUNT HERE, AND THAT IS THE POINT. The guidance: "if all of a
			menu's items are unavailable, the menu itself needs to remain available so
			people can open it and learn about the commands it contains." A trigger
			that silently does nothing is the worst failure this control could have,
			because the player cannot tell it from a dead button. ]]
		openPath:set({})
		isOpen:set(true)
		presentLevel(0, presentation, {})
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
		if isOpen:peek() then
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
			owner.own(detachGestures :: any)
		end
	end

	local triggerGraph: any = nil
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
			-- Context commands belong to the focused trigger. Multiple menus may
			-- share the chord without opening all their panels at once.
			if triggerGraph and rootPath and triggerGraph.focused:peek() == rootPath then
				api.toggle()
			end
		end)
		keysContext = ctx
		owner.own(function()
			if keysContext ~= nil then
				keysContext.destroy()
				keysContext = nil
			end
		end)
	end

	local blueprint = contribution.attach(spec.trigger, {
		bindFocusGraph = function(graph)
			triggerGraph = graph
		end,
		handleActivate = api.handleActivate,
		syncGeometry = function(_rectOf: (string) -> any, rootNode: any?)
			mountedNode = rootNode
			if not available() and isOpen:peek() then
				closeAll()
			end
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
			presentModalFn = if Facet.surfaces then Facet.surfaces.modal else presentModal
			dismissFn = dismiss
			presentAnchoredFn = if Facet.surfaces then Facet.surfaces.anchored else presentAnchored
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

	-- A trigger that declares its own effect still opens its menu: the presenter
	-- asks a node's `onActivate` before any contribution, so the menu's activate
	-- route goes first there and the trigger's effect runs when the menu declines.
	local ownActivate = spec.trigger.props and spec.trigger.props.onActivate
	if type(ownActivate) == "function" then
		Facet.runtime.decorate(blueprint, {
			onActivate = function(path: string, meta: any?)
				if not api.handleActivate(path, meta) then
					ownActivate(path, meta)
				end
			end,
		})
	end

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
						kind = if item.children ~= nil
							then "submenu"
							elseif item.checked ~= nil then "check"
							elseif item.selected ~= nil then "selection"
							else "action",
						checked = if item.checked ~= nil
							then item.checked:peek()
							elseif item.selected ~= nil then item.selected:peek() == item.value
							else nil,
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
		local chain = openPath:peek()
		local presentation = presentationNow()
		local depth = #chain
		local text = if not isOpen:peek()
			then `menu '{id}': closed, {menuRecipe.actionableCount(spec.items)} items, presents as {presentation}`
			else `menu '{id}': open at depth {depth} ({table.concat(chain, " > ")}), {presentation}, `
				.. `{#handles} surface(s)`
		return {
			schema = DUMP_SCHEMA,
			-- "spec" (authored) or "core" (the surface's environment, no wiring)
			factsFrom = factsFrom,
			id = id,
			open = isOpen:peek(),
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

	owner.own(function()
		disposed = true
		closeAll()
	end)
	return {
		blueprint = blueprint,
		api = api,
		presentation = presentationNow,
		dump = dump,
		dispose = function()
			if disposed then
				return
			end
			disposed = true
			closeAll()
			owner.dispose()
		end,
	}
end

function menu.build(Facet, core, spec)
	return ownedBuild(core, function(owner)
		return build(Facet, core, spec, owner)
	end)
end
return menu
