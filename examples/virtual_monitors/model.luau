--!strict
type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type CivilDate = typeof(require("@repo/tools/typecheck/aliases").CivilDate)
type Readable<T> = { peek: (Readable<T>) -> T }
type Cell<T> = Readable<T> & { set: (Cell<T>, T) -> (), update: (Cell<T>, (T) -> T) -> () }
type Use = <T>(Readable<T>) -> T
local catalogModule = require("./catalog")
local chatModule = require("./chat_model")
local flapModule = require("./flap_model")
local model = {}

export type Game = catalogModule.Game
export type Presence = "online" | "away" | "busy" | "offline" | "inExperience"
export type Launch = { id: string, mode: string, stage: number, elapsed: number }
export type Toast = { serial: number, message: string, undo: (() -> ())? }
export type Presentation = { about: Cell<boolean>, status: Cell<boolean> }
export type PathEntry = { id: string, value: boolean? }
export type SavedSort = { column: string, direction: "ascending" | "descending" }
export type Model = {
	catalog: catalogModule.Catalog,
	chat: chatModule.Chat,
	flap: flapModule.Flap,
	mode: Cell<string>,
	selectedTab: Cell<string>,
	focused: Cell<string>,
	dark: Cell<boolean>,
	query: Cell<string>,
	searchSelection: Cell<string>,
	featuredIndex: Cell<number>,
	discoveryScroll: Cell<number?>,
	savedScroll: Cell<number?>,
	chatScroll: Cell<number?>,
	genre: Cell<string>,
	launch: Cell<any>,
	avatarPath: Cell<{ PathEntry }>,
	sort: Cell<string>,
	shelf: Cell<string>,
	selectedGame: Cell<any>,
	detailTab: Cell<string>,
	saved: Cell<{ [string]: boolean }>,
	savedOrder: Cell<{ string }>,
	savedSelection: Cell<{ [string]: boolean }>,
	savedSort: Cell<SavedSort?>,
	savedWidths: Cell<{ [string]: number }>,
	notes: Cell<{ [string]: string }>,
	ratings: Cell<{ [string]: number }>,
	palette: Cell<string>,
	hat: Cell<boolean>,
	hatTint: Cell<{ number }>,
	angle: Cell<number>,
	turnStep: Cell<number>,
	autoSpin: Cell<number>,
	followChat: Cell<boolean>,
	avatarSummary: Cell<boolean>,
	avatarSummaryDetent: Cell<string>,
	avatarSettingsExpanded: Cell<boolean>,
	avatarTipsExpanded: Cell<boolean>,
	chatPromptUsed: Cell<boolean>,
	detailPath: Cell<{ PathEntry }>,
	featuredSelection: Cell<string>,
	resetAvatarPresented: Cell<boolean>,
	lookResets: Cell<number>,
	hidden: Cell<{ [string]: boolean }>,
	sessions: Cell<{ [string]: CivilDate }>,
	similarPage: Cell<number>,
	presence: Cell<Presence?>,
	chatUnread: Cell<number>,
	toasts: { [string]: Cell<Toast?> },
	presentations: { [string]: Presentation },
	modeChosen: boolean,
	visibleGames: Readable<{ Game }>,
	savedGames: Readable<{ Game }>,
	flapActive: (Use) -> boolean,
	flapPress: () -> (),
	notify: (app: string, message: string, undo: (() -> ())?) -> (),
	dismissToast: (app: string, id: number) -> (),
	toggleSaved: (id: string) -> (),
	save: (item: Game) -> (),
	hide: (item: Game) -> (),
	schedule: (id: string, date: CivilDate?) -> (),
	launchGame: (id: string, mode: string) -> (),
	deleteMessage: (id: number) -> (),
	reorderSaved: (keys: { string }, slot: number) -> (),
	setNote: (id: string, value: string) -> (),
	rate: (id: string, value: number) -> (),
	selectGame: (item: Game?) -> (),
	toggleMode: () -> (),
	focus: (name: string) -> (),
	turn: (direction: number) -> (),
	resetAvatar: () -> (),
	prompt: (value: string) -> (),
	step: (dt: number, reducedMotion: boolean) -> (),
	dispose: () -> (),
}

type FacetModule = typeof(require("@repo/tools/typecheck/aliases").FacetModule)
type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Host = typeof(require("@repo/tools/typecheck/aliases").Host)
type Runtime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type RobloxTypes = typeof(require("@repo/tools/typecheck/aliases").RobloxTypes)
type Child = typeof(require("@repo/tools/typecheck/aliases").Child)
type ControlOptions = typeof(require("@repo/tools/typecheck/aliases").ControlOptions)
type ButtonProps = typeof(require("@repo/tools/typecheck/aliases").ButtonProps)
type StageProps = typeof(require("@repo/tools/typecheck/aliases").StageProps)
export type TextValue = typeof(require("@repo/tools/typecheck/aliases").TextPropsText)
export type TextRole = "caption" | "label" | "body" | "heading" | "title" | "control" | "strong" | "numeral"
export type TextExtras = {
	Size: UDim2?,
	AutomaticSize: Enum.AutomaticSize?,
	TextWrapped: boolean?,
	TextTruncate: Enum.TextTruncate?,
	TextXAlignment: Enum.TextXAlignment?,
	Visible: ((Use) -> boolean)?,
	role: "secondary"?,
	[number]: Child,
}
export type StageContent = (runtime: Runtime, world: WorldModel, live: Readable<boolean>) -> (() -> ())?
export type Actions = {
	model: Model,
	types: RobloxTypes?,
	services: typeof(require("@repo/tools/typecheck/aliases").ControlOptions.services),
	theme: typeof(require("@repo/tools/typecheck/aliases").ControlOptions.theme),
	motionLevel: typeof(require("@repo/tools/typecheck/aliases").ControlOptions.motionLevel),
	pressHaptic: typeof(require("@repo/tools/typecheck/aliases").ControlOptions.pressHaptic),
	spatial: boolean?,
	player: Player?,
	clock: typeof(require("@repo/tools/typecheck/aliases").DateTimePickerProps.clock),
	creatorImageLoader: typeof(require("@repo/tools/typecheck/aliases").AsyncImageProps.loader),
	discoveryContent: StageContent?,
	gameContent: ((Readable<Game>) -> StageContent)?,
	avatarContent: StageContent?,
}
export type Context = {
	Facet: FacetModule,
	Compose: ComposeModule,
	Host: Host,
	UI: FacetControls,
	runtime: Runtime,
	model: Model,
	types: RobloxTypes,
	D: typeof(UDim),
	D2: typeof(UDim2),
	V2: typeof(Vector2),
	C3: typeof(Color3),
	CF: typeof(CFrame),
	E: typeof(Enum),
	words: (name: string, value: TextValue, role: TextRole?, extras: TextExtras?) -> GuiObject,
	quiet: (name: string, value: TextValue, role: TextRole?, extras: TextExtras?) -> GuiObject,
	button: (name: string, label: TextValue, activate: () -> (), extras: ButtonProps?) -> TextButton,
	stage: (name: string, content: StageContent?, extras: StageProps?) -> Child,
	observeSize: (node: GuiObject) -> Cell<Vector2>,
	measure: (node: GuiObject, value: Cell<Vector2>) -> GuiObject,
	collection: (source: Cell<number?>, build: (canvas: ((Use) -> Vector2)?) -> ScrollingFrame) -> ScrollingFrame,
	actions: Actions,
	rounded: (radius: number?) -> UICorner,
	panelShadow: () -> Frame,
	toastFor: (app: string) -> Child,
}

local function peekNow<T>(value: Readable<T>): T
	return value:peek()
end

function model.new(Compose: ComposeModule): Model
	local catalog = catalogModule.new(Compose)
	local chat = chatModule.new(Compose)
	local flap = flapModule.new(Compose)
	local mode = Compose.cell("Spatial")
	local selectedTab = Compose.cell("Discover")
	local focused = Compose.cell("Overview")
	local initialScroll: number? = 0
	local noScroll: number? = nil
	local noLaunch: Launch? = nil
	local noGame: Game? = nil
	local noSort: SavedSort? = nil
	local noToast: Toast? = nil
	local initialPresence: Presence? = "online"
	local emptyPath: { PathEntry } = {}
	local emptyDetailPath: { PathEntry } = {}
	local emptySaved: { [string]: boolean } = {}
	local emptyOrder: { string } = {}
	local emptySelection: { [string]: boolean } = {}
	local emptyWidths: { [string]: number } = {}
	local emptyNotes: { [string]: string } = {}
	local emptyRatings: { [string]: number } = {}
	local emptyHidden: { [string]: boolean } = {}
	local emptySessions: { [string]: CivilDate } = {}
	local presentations: { [string]: Presentation } = {}
	local discoveryScroll: Cell<number?> = Compose.cell(initialScroll)
	local savedScroll: Cell<number?> = Compose.cell(initialScroll)
	local chatScroll: Cell<number?> = Compose.cell(noScroll)
	local query, genre, sort = Compose.cell(""), Compose.cell("all"), Compose.cell("recommended")
	local launch: Cell<Launch?> = Compose.cell(noLaunch)
	local avatarPath: Cell<{ PathEntry }> = Compose.cell(emptyPath)
	local selectedGame: Cell<Game?> = Compose.cell(noGame)
	local detailTab = Compose.cell("about")
	local saved: Cell<{ [string]: boolean }> = Compose.cell(emptySaved)
	local savedOrder: Cell<{ string }> = Compose.cell(emptyOrder)
	local savedSelection: Cell<{ [string]: boolean }> = Compose.cell(emptySelection)
	local savedSort: Cell<SavedSort?> = Compose.cell(noSort)
	local savedWidths: Cell<{ [string]: number }> = Compose.cell(emptyWidths)
	local notes: Cell<{ [string]: string }> = Compose.cell(emptyNotes)
	local ratings: Cell<{ [string]: number }> = Compose.cell(emptyRatings)
	local palette, hat = Compose.cell("sage"), Compose.cell(true)
	local hatTint: Cell<{ number }> = Compose.cell({ 218, 195, 145 })
	local angle, turnStep, autoSpin = Compose.cell(-15), Compose.cell(30), Compose.cell(0)
	local chatPromptUsed = Compose.cell(false)
	local detailPath: Cell<{ PathEntry }> = Compose.cell(emptyDetailPath)
	local lookResets = Compose.cell(0)
	local hidden: Cell<{ [string]: boolean }> = Compose.cell(emptyHidden)
	local sessions: Cell<{ [string]: CivilDate }> = Compose.cell(emptySessions)
	local similarPage = Compose.cell(1)
	local presence: Cell<Presence?> = Compose.cell(initialPresence)
	local chatUnread = Compose.cell(0)
	local discoverToast: Cell<Toast?> = Compose.cell(noToast)
	local chatToast: Cell<Toast?> = Compose.cell(noToast)
	local toasts: { [string]: Cell<Toast?> } = { Discover = discoverToast, Chat = chatToast }
	local self: Model
	local serial = 0
	local function flapActive(use: Use): boolean
		local current = use(mode)
		local selected = if current == "Screen" then use(selectedTab) else use(focused)
		local presentation = presentations["Flap:" .. current]
		return selected == "Flap" and not (presentation and (use(presentation.about) or use(presentation.status)))
	end
	local function flapPress()
		if flapActive(peekNow) then
			flap.flap()
		end
	end
	Compose.watch(function(use: Use)
		if not flapActive(use) then
			flap.pause()
		end
	end)
	local function notify(app: string, message: string, undo: (() -> ())?)
		serial += 1
		toasts[app]:set({ serial = serial, message = message, undo = undo })
	end
	local function dismissToast(app: string, id: number)
		local current = toasts[app]:peek()
		if current and current.serial == id then
			toasts[app]:set(nil)
		end
	end
	Compose.watch(function(use: Use)
		use(query)
		use(genre)
		use(sort)
		discoveryScroll:set(0)
	end)
	local visibleGames = Compose.formula(function(use: Use): { Game }
		local text, chosenGenre, order = use(query):lower(), use(genre), use(sort)
		local hiddenNow, result: { Game } = use(hidden), {}
		for _, item in use(catalog.items) do
			if
				not hiddenNow[item.id]
				and (chosenGenre == "all" or item.genre == chosenGenre)
				and (text == "" or item.title:lower():find(text, 1, true))
			then
				table.insert(result, item)
			end
		end
		if order ~= "recommended" then
			local function score(item: Game): number
				return if order == "rating" then item.percent else item.playing
			end
			table.sort(result, function(a: Game, b: Game): boolean
				return if score(a) == score(b) then a.index < b.index else score(a) > score(b)
			end)
		end
		return result
	end)
	local savedGames = Compose.formula(function(use: Use): { Game }
		local savedNow, byId, result: { Game } = use(saved), {}, {}
		for _, item in use(catalog.items) do
			byId[item.id] = item
		end
		for _, id in use(savedOrder) do
			if savedNow[id] and byId[id] then
				table.insert(result, byId[id])
			end
		end
		return result
	end)
	local function toggleSaved(id: string)
		local nextSaved = table.clone(saved:peek())
		if nextSaved[id] then
			nextSaved[id] = nil
		else
			nextSaved[id] = true
		end
		local order = table.clone(savedOrder:peek())
		local index = table.find(order, id)
		if nextSaved[id] and not index then
			table.insert(order, id)
		elseif index then
			table.remove(order, index)
		end
		savedOrder:set(order)
		saved:set(nextSaved)
	end
	local function save(item: Game)
		local wasSaved = saved:peek()[item.id] == true
		toggleSaved(item.id)
		if not wasSaved then
			notify("Discover", `Saved {item.title}`, function()
				if saved:peek()[item.id] then
					toggleSaved(item.id)
				end
			end)
		end
	end
	local function hide(item: Game)
		hidden:update(function(current)
			local nextHidden = table.clone(current)
			nextHidden[item.id] = true
			return nextHidden
		end)
		notify("Discover", `{item.title} is hidden`, function()
			hidden:update(function(current)
				local nextHidden = table.clone(current)
				nextHidden[item.id] = nil
				return nextHidden
			end)
		end)
	end
	local function schedule(id: string, date: CivilDate?)
		sessions:update(function(current)
			local nextSessions = table.clone(current)
			if date then
				nextSessions[id] = date
			else
				nextSessions[id] = nil
			end
			return nextSessions
		end)
	end
	local function launchGame(id: string, launchMode: string)
		launch:set({ id = id, mode = launchMode, stage = 1, elapsed = 0 })
	end
	local function deleteMessage(id: number)
		local removed, index = chat.remove(id)
		if removed and index then
			notify("Chat", "Message deleted", function()
				chat.restore(removed, index)
			end)
		end
	end
	local function reorderSaved(keys: { string }, slot: number)
		local moving: { [string]: boolean }, rest: { string }, ordered: { string } = {}, {}, {}
		for _, id in keys do
			moving[id] = true
		end
		for _, id in savedOrder:peek() do
			if moving[id] then
				table.insert(ordered, id)
			else
				table.insert(rest, id)
			end
		end
		local index = math.clamp(slot, 0, #rest)
		for offset, id in ordered do
			table.insert(rest, index + offset, id)
		end
		savedOrder:set(rest)
	end
	local function setNote(id: string, value: string)
		notes:update(function(current)
			local nextValue = table.clone(current)
			nextValue[id] = value
			return nextValue
		end)
	end
	local function rate(id: string, value: number)
		ratings:update(function(current)
			local nextValue = table.clone(current)
			nextValue[id] = math.clamp(value, 1, 5)
			return nextValue
		end)
	end
	local function selectGame(item: Game?)
		detailTab:set("about")
		similarPage:set(1)
		detailPath:set({})
		selectedGame:set(item)
	end
	local function toggleMode()
		self.modeChosen = true
		local current = focused:peek()
		if mode:peek() == "Spatial" and current ~= "Overview" then
			selectedTab:set(current)
		end
		focused:set(selectedTab:peek())
		mode:set(if mode:peek() == "Spatial" then "Screen" else "Spatial")
	end
	local function focus(name: string)
		focused:set(if focused:peek() == name then "Overview" else name)
	end
	local function turn(direction: number)
		angle:set((angle:peek() + direction * turnStep:peek() + 180) % 360 - 180)
	end
	local function resetAvatar()
		palette:set("sage")
		hat:set(true)
		hatTint:set({ 218, 195, 145 })
		angle:set(-15)
		lookResets:set(lookResets:peek() + 1)
	end
	local function prompt(value: string)
		chatPromptUsed:set(true)
		chat.draft:set(value)
	end
	local function chatVisible()
		local currentMode, current = mode:peek(), focused:peek()
		return if currentMode == "Screen"
			then selectedTab:peek() == "Chat"
			else current == "Chat" or current == "Overview"
	end
	Compose.watch(function(use: Use)
		use(mode)
		use(focused)
		use(selectedTab)
		if chatVisible() and chatUnread:peek() > 0 then
			chatUnread:set(0)
		end
	end)
	local answered = chat.completed:peek()
	Compose.watch(function(use: Use)
		local completed = use(chat.completed)
		if completed > answered and not chatVisible() then
			chatUnread:set(chatUnread:peek() + completed - answered)
		end
		answered = completed
	end)
	local function step(dt: number, reducedMotion: boolean)
		if flapActive(peekNow) then
			flap.step(dt)
		else
			flap.pause()
		end
		catalog.step()
		chat.step(dt)
		local current = launch:peek()
		if current and current.stage <= 3 then
			local elapsed = current.elapsed + math.min(dt, 0.1)
			local stage = current.stage
			if elapsed >= 0.9 then
				elapsed, stage = 0, stage + 1
			end
			launch:set({ id = current.id, mode = current.mode, stage = stage, elapsed = elapsed })
		end
		if not reducedMotion and autoSpin:peek() > 0 then
			local rate = ({ 0, 30, 75, 150 })[autoSpin:peek() + 1]
			angle:set((angle:peek() + rate * math.min(dt, 0.1) + 180) % 360 - 180)
		end
	end
	local function dispose()
		catalog.dispose()
		chat.dispose()
		flap.dispose()
	end
	self = {
		catalog = catalog,
		chat = chat,
		flap = flap,
		mode = mode,
		selectedTab = selectedTab,
		focused = focused,
		dark = Compose.cell(true),
		query = query,
		searchSelection = Compose.cell(""),
		featuredIndex = Compose.cell(1),
		discoveryScroll = discoveryScroll,
		savedScroll = savedScroll,
		chatScroll = chatScroll,
		genre = genre,
		launch = launch,
		avatarPath = avatarPath,
		sort = sort,
		shelf = Compose.cell("browse"),
		selectedGame = selectedGame,
		detailTab = detailTab,
		saved = saved,
		savedOrder = savedOrder,
		savedSelection = savedSelection,
		savedSort = savedSort,
		savedWidths = savedWidths,
		notes = notes,
		ratings = ratings,
		palette = palette,
		hat = hat,
		hatTint = hatTint,
		angle = angle,
		turnStep = turnStep,
		autoSpin = autoSpin,
		followChat = Compose.cell(true),
		avatarSummary = Compose.cell(false),
		avatarSummaryDetent = Compose.cell("medium"),
		avatarSettingsExpanded = Compose.cell(true),
		avatarTipsExpanded = Compose.cell(false),
		chatPromptUsed = chatPromptUsed,
		detailPath = detailPath,
		featuredSelection = Compose.cell("1"),
		resetAvatarPresented = Compose.cell(false),
		lookResets = lookResets,
		hidden = hidden,
		sessions = sessions,
		similarPage = similarPage,
		presence = presence,
		chatUnread = chatUnread,
		toasts = toasts,
		presentations = presentations,
		modeChosen = false,
		visibleGames = visibleGames,
		savedGames = savedGames,
		flapActive = flapActive,
		flapPress = flapPress,
		notify = notify,
		dismissToast = dismissToast,
		toggleSaved = toggleSaved,
		save = save,
		hide = hide,
		schedule = schedule,
		launchGame = launchGame,
		deleteMessage = deleteMessage,
		reorderSaved = reorderSaved,
		setNote = setNote,
		rate = rate,
		selectGame = selectGame,
		toggleMode = toggleMode,
		focus = focus,
		turn = turn,
		resetAvatar = resetAvatar,
		prompt = prompt,
		step = step,
		dispose = dispose,
	}
	return self
end

return model
