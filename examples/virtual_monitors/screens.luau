--!strict
-- Three small, fully mounted applications. Their shared desktop appearance is
-- model state; each application keeps its own durable interaction state.
local screens = { CANVAS = { w = 920, h = 640 } }
-- The featured hero's one shape decision: the art's aspect ratio and, on a
-- regular-width layout, its width. Every other number in that card (its height,
-- the carousel's height) is derived from these two so the art can never stand
-- past the card that holds it.
local FEATURED_RATIO = 16 / 10
local FEATURED_ART_W = 280
function screens.create(Facet: any, app: any, actions: any?)
	local UI, Compose = app.controls, Facet.Compose
	local icons = require("./icons")
	local hostEnvironment = app.environment
	local callbacks = actions or {}
	local fill = UI.fill()
	local function fixed(px)
		return { type = "fixed", px = px }
	end
	local function text(value, size, role)
		return UI.Text({ text = value, textSize = size or "body", role = role or "content", width = fill })
	end
	-- A 3D Stage's content builder runs engine-side code this module does not
	-- control (`scenes.luau`'s `gameContent`/`avatarContent`, wired by the host).
	-- `Compose.boundary` quarantines a factory failure to this one spot: the
	-- scene keeps its reserved box and a quiet placeholder instead of taking
	-- the whole page down. `buildContent`, when given, is called INSIDE the
	-- guarded builder (never eagerly by the caller) so a throw from resolving
	-- the content closure itself — not only from the closure once invoked — is
	-- caught too.
	local function stage(id, spec, buildContent, decorate)
		decorate = decorate or function(node)
			return node
		end
		return Compose.boundary(function()
			local resolved = spec
			if buildContent then
				resolved = table.clone(spec)
				resolved.content = buildContent()
			end
			return decorate(UI.Stage(id)(resolved))
		end, function()
			return decorate(UI.VStack(id)({
				width = spec.width,
				height = spec.height,
				surface = spec.surface,
				-- A stack centres ACROSS its line with `align` and ALONG it with
				-- `distribute`. `alignH`/`alignV` are what a ZStack parent reads off a
				-- child; under a stack they are accepted and then ignored, which is
				-- exactly what `controller.diagnostics()` said about this box.
				align = "center",
				distribute = "center",
				text("Preview unavailable", "caption", "secondary"),
			}))
		end)
	end
	-- A native loading skeleton: a Roblox `Frame` with a `UIGradient` whose
	-- Offset sweeps to shimmer, hosted through `UI.Foreign` — the bounded
	-- escape hatch for content Facet does not wrap (docs/reference/api.md
	-- §Foreign). Headless specs have no Instance API, so the adopted content
	-- never exists there: `Instance` itself is nil under Lune, which is the
	-- engine guard, and every check below folds to a no-op. Only the RESERVED
	-- BOX (the `UI.Foreign` node mounting and unmounting) is what a spec can
	-- assert; the sweep is the live host's half.
	local function shimmerHost(id, size)
		return UI.Foreign(id)({
			width = fixed(size),
			height = fixed(size),
			surface = "control",
			--[[ THE SEAM ARRIVES; WE DO NOT GO LOOKING FOR IT. `onHost` is called
				once, with the same `{ adopt }` handle `controller.foreignHost(path)`
				answers, at the moment the node has one — and `nil` where the target
				has no foreign seam at all. What it returns runs when the box goes
				away. The whole sweep is one frame connection owned by the content it
				drives, instead of a per-frame poll for a controller smuggled out of
				`app.mount`. ]]
			onHost = function(host)
				if Instance == nil or host == nil then
					return nil
				end
				local frame = Instance.new("Frame")
				frame.BackgroundColor3 = Color3.new(1, 1, 1)
				frame.BackgroundTransparency = 0.85
				frame.BorderSizePixel = 0
				frame.Size = UDim2.fromScale(1, 1)
				local gradient = Instance.new("UIGradient")
				gradient.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0.35),
					NumberSequenceKeypoint.new(1, 1),
				})
				gradient.Parent = frame
				host.adopt(frame)
				local stop = app.onFrame(function(dt)
					-- Reduced motion: the gradient stands still instead of sweeping.
					if app.environment:get("motionPolicy"):peek() == "reduced" then
						return
					end
					local offset = gradient.Offset
					gradient.Offset = Vector2.new((offset.X + dt * 0.7 + 1) % 2 - 1, 0)
				end)
				return function()
					stop()
					frame:Destroy()
				end
			end,
		})
	end
	-- The three shell actions, built once so the full row and the cramped-header
	-- Menu fallback (ViewThatFits below) stay in exact sync: same labels, same
	-- callbacks, never two copies to drift.
	local function aboutModal()
		local close
		close = app.presentModal(function()
			return UI.Screen("About")({
				surface = "scrim",
				padding = "m",
				UI.ZStack("Center")({
					width = fill,
					height = fill,
					alignH = "center",
					alignV = "center",
					UI.VStack("Card")({
						surface = "raised",
						padding = "m",
						gap = "m",
						width = fixed(360),
						text("About Virtual Monitors", "heading"),
						text(
							"A showcase of Facet's native authoring path: three small apps shared between a spatial desktop and a flat screen presentation.",
							"body",
							"secondary"
						),
						UI.Button("Done")({
							label = "Done",
							width = fill,
							onActivate = function()
								close()
							end,
						}),
					}),
				}),
			})
		end)
		return close
	end
	local function shellActions(app)
		local actions = {}
		if callbacks.spatial ~= false then
			table.insert(actions, {
				id = "focus",
				buttonId = "Focus",
				menuLabel = "Focus this monitor",
				compactLabel = "Focus",
				label = if callbacks.focusLabel then callbacks.focusLabel(app) else "Focus",
				onActivate = function()
					if callbacks.focus then
						callbacks.focus(app)
					end
				end,
			})
		end
		table.insert(actions, {
			id = "mode",
			buttonId = "Presentation",
			menuLabel = "Switch presentation",
			compactLabel = "Mode",
			label = callbacks.modeLabel or "Screen mode",
			onActivate = callbacks.toggleMode or function() end,
		})
		table.insert(actions, {
			id = "theme",
			buttonId = "Appearance",
			menuLabel = "Switch appearance",
			compactLabel = "Theme",
			label = callbacks.appearanceLabel or "Dark mode",
			onActivate = callbacks.toggleAppearance or function() end,
		})
		table.insert(actions, {
			id = "about",
			buttonId = "About",
			menuLabel = "About Virtual Monitors",
			compactLabel = "About",
			label = "About",
			onActivate = aboutModal,
		})
		return actions
	end
	local function chrome(name, app)
		local actions = shellActions(app)
		local buttons = {}
		for _, action in actions do
			table.insert(
				buttons,
				UI.Button(action.buttonId)({
					label = action.label,
					compactLabel = action.compactLabel,
					onActivate = action.onActivate,
				})
			)
		end
		local menuItems = {}
		for _, action in actions do
			-- A menu item names its action; the button beside it shows the live state.
			table.insert(menuItems, { id = action.id, label = action.menuLabel, onSelect = action.onActivate })
		end
		-- The full button row is the preferred layout; a Menu behind one button
		-- is the fallback ViewThatFits reaches for once the row no longer fits.
		-- The title keeps clear of the engine's top-left controls; surfaces that
		-- have none report a zero inset.
		local topbar = hostEnvironment:get("topbarInset")
		return UI.HStack("Chrome")({
			width = fill,
			UI.Spacer({
				-- Only a screen presentation sits under the engine's top bar.
				width = function(use)
					local free = use(topbar)
					-- Wide screens carry the tab strip on the top row, so this row
					-- already sits below the engine's controls.
					local topRow = use(hostEnvironment:get("sizeClass")) == "compact"
					if callbacks.spatial ~= false or free == nil or not topRow then
						return fixed(0)
					end
					return fixed(math.max(0, free.x - 24))
				end,
			}),
			UI.navBar({
				id = "NavBar",
				title = name,
				titleSize = "title",
				titleWidth = UI.hug(),
				trailing = {
					UI.ViewThatFits("Actions")({
						-- The actions take the width the title leaves, so the row is measured
						-- against the space it really has. The trailing edge is claimed by the
						-- fill Spacer inside each alternative, not by `alignH`: the nav bar
						-- lays its trailing slot out as an hstack, and an hstack places on the
						-- main axis by flow.
						width = { type = "fill", weight = 1000 },
						UI.HStack("Row")({
							width = fill,
							gap = "s",
							UI.Spacer({ width = fill }),
							table.unpack(buttons),
						}),
						UI.HStack("Compact")({
							width = fill,
							UI.Spacer({ width = fill }),
							UI.Menu("Menu")({ label = "More", items = menuItems }),
						}),
					}),
				},
			}),
		})
	end
	local function header(title, subtitle)
		return UI.VStack({ width = fill, gap = "xs", text(title, "title"), text(subtitle, "body", "secondary") })
	end
	-- `overlays`, when given, are extra ZStack SIBLINGS of `Content` — painted
	-- above it, at the root's own top level. That is what lets a screen layer a
	-- HUD over its content without renaming a single node underneath `Content`:
	-- every existing `/S/<id>/Content/...` path stays exactly what it was.
	local function root(id, children, overlays)
		local content: any = { width = fill, height = fill, padding = "l", gap = "m" }
		for _, child in children do
			table.insert(content, child)
		end
		local layers: any = {
			width = fill,
			height = fill,
			surface = "base",
			hidden = callbacks.hidden,
			UI.VStack("Content")(content),
		}
		for _, overlay in overlays or {} do
			table.insert(layers, overlay)
		end
		-- INERT GROUND. The gate below spends an ACTIVATION, and a press on the 3D
		-- preview or a margin activates nothing. While the monitor sleeps, this
		-- plain button is the ground such a press lands on; the gate spends it like
		-- any other. It unmounts once the monitor is awake and is never a focus stop.
		if callbacks.needsFocus then
			table.insert(
				layers,
				UI.When("Wake")({
					condition = callbacks.needsFocus(id),
					thenView = function()
						return UI.Button("Ground")({
							label = "Focus " .. id,
							surface = "plain",
							focusable = false,
							width = fill,
							height = fill,
							onActivate = function() end,
							UI.Spacer({ width = fill, height = fill }),
						})
					end,
				})
			)
		end
		-- ONE ACTIVATION TO WAKE THE MONITOR. An input-policy declaration, not
		-- a cover: while this screen is not the focused one, the first press —
		-- pointer, touch, keyboard or gamepad — focuses it and reaches nothing
		-- underneath.
		return UI.activationGate(UI.ZStack(id)(layers), {
			closed = if callbacks.needsFocus then callbacks.needsFocus(id) else false,
			onOpen = function()
				if callbacks.focus then
					callbacks.focus(id)
				end
			end,
		})
	end

	--[[ A NEAR-DISTANCE PIXEL NUMBER, IN THE SIZE THIS DISPLAY ACTUALLY DRAWS AT.

		Every token in a theme — type, padding, target floors, icon sizes — is scaled
		by the display the package resolves against, and a ten-foot television comes
		back about half again as large. A raw number written beside them does not
		move, and the gap is a defect class of its own: a 340px settings column held
		rows whose own controls had grown, a segmented switch truncated both its
		words, a carousel reserved 47px less chrome than its card needed. `scaled`
		is the one place that gap is closed — a number authored at near distance,
		read back in the metric the screen is painting with. ]]
	local function scaled(px: number)
		return function(use)
			local metrics = use(hostEnvironment:get("themeMetrics"))
			local factor = if type(metrics) == "table" and type(metrics.metricScale) == "number"
				then metrics.metricScale
				else 1
			return fixed(px * factor)
		end
	end
	-- A television. Its type and its targets are half again as large as a
	-- monitor's, so a row that fits one may not fit the other.
	local function tenFoot(use)
		return use(hostEnvironment:get("distanceProfile")) == "ten-foot"
	end
	-- A viewport with room for one band and not two: a landscape phone, a short
	-- window. Empty states spend their mark only above it.
	local function shortViewport(use)
		return Facet.adaptive.heightClass(use(hostEnvironment:get("viewportRect")).h) == "short"
	end
	--[[ A VIEWPORT WITH NO ROOM FOR AN ORNAMENT — which a television is, in spite
		of having 1080 rows of them. Its type, its padding and its targets are all
		about half again as large, so the same empty state that fits a 1080p monitor
		with room to spare stands 70px past the feed on a TV. The two cases want the
		same answer (keep the sentence and the way back, spend the mark only where
		there is room), so they share one predicate. ]]
	local function spareLayout(use)
		return shortViewport(use) or tenFoot(use)
	end
	-- Short AND wide: a landscape phone, a short desktop window. A short PORTRAIT
	-- window is short without room for a second column, so it is not this.
	local function sideBySide(use)
		return shortViewport(use) and use(hostEnvironment:get("viewportRect")).w >= 640
	end
	local function Discover()
		local function compactWidth(use)
			return use(hostEnvironment:get("viewportRect")).w < 640
		end
		-- six genre chips (about 560) beside the 452 tools, with the page padding
		--[[ ...but a SHORT viewport spends width rather than height: two filter rows
			cost 115px of the 221 a landscape phone leaves the feed, and the empty state
			under them then painted over the grid. There it is one row, and the genre
			scroller takes whatever the tools leave. ]]
		local function filtersStacked(use)
			return use(hostEnvironment:get("viewportRect")).w < 1100 and not sideBySide(use)
		end
		local viewport = app.environment:get("viewportRect")
		local feed = callbacks.catalog or require("./catalog").new(Facet.Compose)
		if not callbacks.catalog then
			Compose.cleanup(feed.dispose)
		end
		local selected = callbacks.selectedGame or Facet.Compose.cell(nil)
		local saved = callbacks.savedGames or Facet.Compose.cell({})
		-- One shared lease-holder for every creator avatar on this page. Default
		-- to a headless-safe, unbound provider (a spec world has no `game`
		-- service); the live host (`main.client.luau`) passes an explicit empty
		-- override table so `bind` stays nil and the real Roblox transport loads.
		local creatorImages, releaseCreatorImages =
			app.newResourceProvider(callbacks.resourceProviderOptions or { bind = false })
		Compose.cleanup(releaseCreatorImages)
		if callbacks.creatorImagesRef then
			callbacks.creatorImagesRef(creatorImages)
		end
		local lastSelected = Compose.cell(selected:peek())
		-- AsyncImage.key is fixed at construction, so the avatar remounts fresh
		-- (a legal keyed remount, not a live-binding gap) whenever the selected
		-- game's id changes, exactly like the reply ProgressView's own remount.
		local creatorList = Compose.formula(function(use)
			local item = use(lastSelected)
			return if item then { item } else {}
		end)
		local shelf = callbacks.discoveryShelf or Compose.cell("browse")
		local function savedShown(use)
			return use(shelf) == "saved"
		end
		local savedSelection = Compose.cell({})
		local savedSort = Compose.cell({})
		-- The Saved table's own row order, independent of the catalog's order.
		-- A newly saved game appends; dropping a game drops its slot too.
		local savedOrder = callbacks.savedOrder or Compose.cell({})
		-- `{ [gameId]: string }`, edited inline by the Saved table's own Note
		-- column. A shared cell, like `savedOrder`, so a note outlives the row
		-- that edited it — a shelf switch or a Screen/Spatial mode change
		-- unmounts and remounts the table, never this.
		local savedNotes = callbacks.savedNotes or Compose.cell({})
		Compose.watch(function(use)
			local kept = use(saved)
			local order = savedOrder:peek()
			local seen, nextOrder = {}, {}
			for _, id in order do
				if kept[id] then
					seen[id] = true
					table.insert(nextOrder, id)
				end
			end
			for id in kept do
				if not seen[id] then
					table.insert(nextOrder, id)
				end
			end
			local changed = #nextOrder ~= #order
			if not changed then
				for i, id in nextOrder do
					if order[i] ~= id then
						changed = true
						break
					end
				end
			end
			if changed then
				savedOrder:set(nextOrder)
			end
		end)
		local savedGames = Compose.formula(function(use)
			local order, kept, byId, list = use(savedOrder), use(saved), {}, {}
			for _, item in use(feed.items) do
				byId[item.id] = item
			end
			for _, id in order do
				if kept[id] and byId[id] then
					table.insert(list, byId[id])
				end
			end
			return list
		end)
		-- Moves `keys` (in document order) so the first of them lands at the
		-- resulting `toIndex` — the standard reorder-insert used across this
		-- codebase's other `onReorder` handlers (`Table.reorderable` contract).
		local function reorder(order, keys, toIndex)
			local moving = {}
			for _, k in keys do
				moving[k] = true
			end
			local rest = {}
			for _, id in order do
				if not moving[id] then
					table.insert(rest, id)
				end
			end
			local nextOrder = {}
			for i = 1, math.min(toIndex, #rest + 1) - 1 do
				table.insert(nextOrder, rest[i])
			end
			for _, id in keys do
				table.insert(nextOrder, id)
			end
			for i = math.min(toIndex, #rest + 1), #rest do
				table.insert(nextOrder, rest[i])
			end
			return nextOrder
		end
		local genre = callbacks.discoveryGenre or Compose.cell(nil)
		-- The player's own rating of each game; the catalog's rating is the default.
		local ratings = callbacks.gameRatings or Compose.cell({})
		local stars = Compose.cell(0)
		Compose.watch(function(use)
			local item = use(lastSelected)
			if item then
				stars:set(use(ratings)[item.id] or item.stars)
			end
		end)
		local sort = callbacks.discoverySort or Compose.cell("recommended")
		local query = callbacks.discoveryQuery or Compose.cell("")
		local searchValue = Compose.cell("")
		-- Each chip owns a settable cell; the shared genre keeps them exclusive.
		local genreChips = {}
		for _, name in require("./catalog").genres do
			genreChips[name] = Compose.cell(genre:peek() == name)
		end
		Compose.watch(function(use)
			local current = use(genre)
			for name, chip in genreChips do
				chip:set(current == name)
			end
		end)
		-- The feed stays endless under a filter: the grid reports rows as they
		-- appear, and the catalog appends the next page.
		local visibleGames = Compose.formula(function(use)
			local wanted, order, q = use(genre), use(sort), use(query):lower()
			local list = {}
			for _, item in use(feed.items) do
				local matchesGenre = wanted == nil or item.genre == wanted
				local matchesQuery = q == "" or item.title:lower():find(q, 1, true) ~= nil
				if matchesGenre and matchesQuery then
					table.insert(list, item)
				end
			end
			if order ~= "recommended" then
				local field = if order == "rating" then "percent" else "playing"
				table.sort(list, function(a, b)
					if a[field] ~= b[field] then
						return a[field] > b[field]
					end
					return a.index < b.index
				end)
			end
			return list
		end)
		-- THE EXPANSION IS A TRANSITION, NOT A LAYOUT. The detail surface is
		-- declared at its full size; `transition = { enter = "transform", source }`
		-- paints it growing out of the selected card's own rect and back again.
		-- Facet re-reads that rect every frame, so the card may scroll under it.
		local cards = {}
		local desktop
		local sourcePath = Compose.cell(nil)
		Compose.watch(function(use)
			local item = use(selected)
			if item then
				local node = cards[item.id]
				if node ~= nil and node.path ~= nil then
					sourcePath:set(node.path)
				end
				lastSelected:set(item)
			end
		end)
		local function setSelected(value)
			selected:set(value)
		end
		-- The carousel's three games are fixed once the feed has loaded its first
		-- page; new pages only extend the feed past them, so the featured set
		-- never has to re-derive mid-scroll.
		local featuredItems = {}
		do
			local pool = feed.items:peek()
			for i = 1, math.min(3, #pool) do
				table.insert(featuredItems, pool[i])
			end
		end
		local featuredSelection = Compose.cell(if featuredItems[1] then featuredItems[1].id else "none")
		local function featuredCard(item)
			-- A pill plate BEHIND the label, not a hand-built HStack+surface, nudged
			-- inward from the corner with an arrange-only offset instead of ZStack
			-- padding.
			local badge = UI.ZStack("Badge")({
				width = fill,
				height = fill,
				alignH = "end",
				alignV = "start",
				--[[ THE INSET IS THE OVERLAY'S OWN PADDING. `UI.offset` writes the
					LAYOUT pair `offsetX`/`offsetY`, which only a `UI.Anchor` reads — under
					a ZStack the nudge was accepted and then ignored (`diagnostics()` said
					so), and the pill sat jammed into the card's rounded corner. Padding the
					overlay insets whichever corner it aligns to, once and for every one. ]]
				padding = "s",
				UI.corners(
					UI.padding(
						UI.background(
							UI.Text("Label")({ text = "Featured", textSize = "caption", role = "content" }),
							UI.Box("Plate")({ surface = "chip" })
						),
						"xs"
					),
					"pill"
				),
			})
			--[[ THE HERO PAIRS THE GAME'S LIVE WORLD WITH ITS PITCH, and the art's
				16:10 is the one number its shape is stated in. `UI.aspectRatio` derives
				HEIGHT FROM WIDTH, and a derived height does not shrink into a box too
				short for it — which is why this only works with the card HUGGING: the
				art states 280x175, the card is that plus its own padding token whatever
				that token is at this display size, and the page's button is the card. A
				hug cannot overflow the box it reports into, so the ratio can never stand
				past the rounded corners it is clipped by. (It did, for a while: with the
				card filling a fixed page height, the art stood 2 to 16px past the card's
				content box, top and bottom, at every size but the one the numbers were
				tuned at.) A failing scene shows a quiet placeholder instead of taking
				the carousel down with it, at the same ratio. ]]
			local function styledArt(node)
				return UI.aspectRatio(UI.corners(node, "panel"), FEATURED_RATIO)
			end
			local artWidth = fixed(FEATURED_ART_W)
			local art = Compose.boundary(function()
				return styledArt(UI.Stage("Art")({
					content = if callbacks.gameContent then callbacks.gameContent(Compose.cell(item)) else nil,
					width = artWidth,
					surface = "control",
				}))
			end, function()
				return styledArt(UI.VStack("Art")({
					width = artWidth,
					surface = "control",
					align = "center",
					distribute = "center",
					text("Preview unavailable", "caption", "secondary"),
				}))
			end)
			-- The hero pairs the game's live world with its pitch.
			local card = UI.HStack("Card")({
				width = fill,
				-- hug: the card is its art plus its own padding, whatever the padding
				-- token is at this display size
				surface = "raised",
				padding = "m",
				gap = "l",
				-- A 2px accent outline on whichever page the carousel is currently
				-- on. `stroke` is normalized once at construction by the `UI.stroke`
				-- modifier, so a value that tracks live selection is set as a
				-- reactive PROP here instead (the documented pulse idiom).
				stroke = function(use)
					return UI.strokeData({
						thickness = 2,
						color = "accent",
						transparency = if use(featuredSelection) == item.id then 0 else 1,
					})
				end,
				art,
				UI.VStack({
					--[[ A LINE HAS A LENGTH IT READS AT. `fill` gave the pitch the whole
						1920 screen, so the title and the one-line description ran 1484px
						across — a measure no one reads. The column takes the room it wants
						and leaves the rest as air. ]]
					width = { type = "minMax", min = 160, max = 520 },
					-- ...AND IT YIELDS FIRST when the card is narrower than the art plus
					-- this cap: the shrink pass needs a nominated child, and the art beside
					-- it is a fixed box with nothing to give.
					shrinkWeight = 1,
					height = fill,
					gap = "xs",
					-- a vstack centres ALONG its own axis with `distribute`; `alignV` is
					-- a ZStack parent's word and was inert here
					distribute = "center",
					text(item.genre, "caption", "secondary"),
					text(item.title, "heading"),
					text(item.description, "body", "secondary"),
					text(item.rating .. " recommend  ·  " .. item.players, "caption", "secondary"),
				}),
			})
			return UI.corners(
				UI.shadow(
					--[[ NO TOKEN-COLOURED GRADIENT HERE, and the reason is a real limit
					rather than taste. `UI.gradient`'s colour names are resolved ONCE,
					against the style the blueprint is BUILT with, and on the native target
					that resolution can never be redone: colour reaches a live screen as
					StyleSheet RULES keyed on this node's tags, while the target's own style
					VALUE table is fixed at construction (`theme_controller`'s own note:
					"today's ScreenTarget cannot [take a new style at runtime]"). So a
					`{ "surfaceStrong", "surface" }` wash built under the dark theme stayed
					near-black through a swap into the light one — a hero card with dark grey
					text on near-black, while every tagged surface around it had re-styled
					correctly (found live, 2026-09-20).

					`surface = "raised"` on the card below is a TAG, so it swaps. The wash it
					replaces was decoration; being readable in both themes is not. ]]
					UI.overlay(card, badge),
					"raised"
				),
				"panel"
			)
		end
		-- `frame` takes either a plain width or a min/max pair, so a caller that
		-- wants the sort to YIELD (a phone row sharing its line with the shelf
		-- switch) and one that wants it fixed both say so in the same argument.
		local function sortPopup(width)
			return UI.frame(
				UI.PopupButton("Sort")({
					value = sort,
					onChange = function(value)
						sort:set(value)
					end,
					options = {
						{ value = "recommended", label = "Recommended" },
						{ value = "rating", label = "Top rated" },
						{ value = "players", label = "Most played" },
					},
				}),
				if type(width) == "table" then width else { width = width }
			)
		end
		local function featuredCarousel()
			local pages = {}
			for _, item in featuredItems do
				table.insert(pages, {
					id = item.id,
					title = item.title,
					content = UI.Button("Open-" .. item.id)({
						label = item.title,
						surface = "plain",
						width = fill,
						height = fill,
						onActivate = function()
							setSelected(item)
						end,
						featuredCard(item),
					}),
				})
			end
			return UI.PageView("Featured")({
				pages = pages,
				selection = featuredSelection,
				--[[ THE ONE NUMBER THE HERO'S SHAPE IS DECIDED BY: the art's 16:10 at
					280px wide, plus the CHROME around it — the card's padding, the page's
					button inset, and the dots under it.

					...and the chrome half SCALES, because every part of it is a theme
					token and tokens grow with the display. Reserved flat, the carousel
					under-reserved by 47px at ten-foot and the page's own scroller clipped
					the bottom of the card, taking the art's lower edge and the whole
					"93% recommend" line with it (found live on the xbox profile,
					2026-09-20). The art is a stated 175px at every distance; only the room
					around it moves. ]]
				height = function(use)
					-- the art is a stated 175px at every distance; only the room around it
					-- moves, so only that half is scaled
					return fixed(FEATURED_ART_W / FEATURED_RATIO + (scaled(121)(use) :: any).px)
				end,
				summary = false,
				controls = false,
			})
		end
		local function field(key, fallback)
			return function(use)
				local item = use(lastSelected)
				return if item then item[key] else fallback
			end
		end
		-- An explanatory popover anchored to the rating line, opened and closed
		-- by the same "About" button; it dismisses on an outside tap because it
		-- presents modally (a focus trap, but that is also what wires the
		-- presenter's own outside-tap dismissal for a non-Screen surface).
		local ratingRowPath = Compose.cell(nil :: string?)
		local ratingInfoClose = nil :: (() -> ())?
		local function toggleRatingInfo()
			if ratingInfoClose then
				ratingInfoClose()
				ratingInfoClose = nil
				return
			end
			local path = ratingRowPath:peek()
			if not path then
				return
			end
			-- The builder runs against `domainUI`, whose id spelling is
			-- `{ id = ... }` in the table rather than the double-call form the
			-- rest of this module uses, so it stays on the outer `UI`/`text`
			-- already captured by this closure (the same choice `aboutModal`
			-- above makes).
			local close = app.presentAnchored(function()
				return UI.VStack("Panel")({
					surface = "raised",
					padding = "m",
					gap = "xs",
					width = fixed(220),
					text("About this rating", "label"),
					text("The share of players who'd recommend this game to a friend.", "caption", "secondary"),
				})
			end, {
				id = "RatingInfo",
				modal = true,
				anchor = { source = { path = path }, edge = "bottom", align = "start", gap = "s", tail = true },
			})
			ratingInfoClose = close
		end
		--[[ THE RATING ROW, IN TWO DESIGNED FORMS.

			One row of genre + five stars + an explanation asked for 423px of a 297px
			phone column and painted 132px past it (205 at 320). Worse than the
			overflow: `{ width = 132 }` squeezed five stars into 10px apiece, a fifth
			of the 44px target the control reserves for each of them when it is
			allowed to — so the compact case was the one where the rating was both
			off-screen AND unhittable.

			So the phone gets its own shape. The facts and the explanation keep one
			line, and the stars take the line under it at full width, where each one
			is a real target. On a regular width all three stay on one line and the
			stars get the 220px five 44px targets need.

			`RatingInfo` is bounded rather than hugging on the compact form, because
			`compactLabel` is a FIT degrade: the solver draws the short spelling only
			when the width the button is GIVEN is too small for the long one, and a
			hugging button is never given too little. The cap is what lets "About
			ratings" become "About" instead of overflowing as its full self. ]]
		local function ratingRow()
			local function genre()
				return UI.Text("Genre")({ text = field("genre", ""), textSize = "label" })
			end
			local function stars5(width)
				local rating = UI.Rating("Stars")({
					value = stars,
					count = 5,
					onChange = function(value)
						local item = lastSelected:peek()
						if item then
							local nextRatings = table.clone(ratings:peek())
							nextRatings[item.id] = value
							ratings:set(nextRatings)
						end
					end,
				})
				-- no frame at all on the compact form: a rating fills the line it is
				-- given, which is exactly what its own targets want
				return if width then UI.frame(rating, width) else rating
			end
			local function about(width)
				local button = UI.Button("RatingInfo")({
					--[[ NAMED FOR WHAT IT OPENS. "About" is the shell's own button
						(this file's `aboutModal`), and a second one on the same screen
						left both unreadable out of context — which is exactly how a
						screen reader reads them. ]]
					label = "About ratings",
					-- the compact form must be ONE word, so it stays "About" — the
					-- full label is what carries the noun
					compactLabel = "About",
					onActivate = toggleRatingInfo,
				})
				return if width then UI.frame(button, width) else button
			end
			-- whichever form is mounted is the one the popover anchors to
			local function mark(path)
				ratingRowPath:set(path)
			end
			-- The row's own column, not the screen's: on a short viewport the detail
			-- page turns side by side (see `Body` below), so a 794px landscape phone
			-- hands this row about 360px — narrower than the 393px portrait one.
			local function narrowRow(use)
				return compactWidth(use) or shortViewport(use)
			end
			return Compose.show(narrowRow, function()
				return UI.VStack("RatingRow")({
					width = fill,
					gap = "s",
					onAppear = mark,
					UI.HStack("Facts")({
						width = fill,
						gap = "m",
						align = "center",
						genre(),
						UI.Spacer({ width = fill }),
						about({ maxWidth = 96 }),
					}),
					stars5(nil),
				})
			end, function()
				return UI.HStack("RatingRow")({
					width = fill,
					gap = "m",
					align = "center",
					onAppear = mark,
					-- genre and stars read as one fact on the leading edge; the
					-- explanation sits on the trailing one
					genre(),
					-- five 44px targets, which is what the control reserves when a
					-- caller lets it
					stars5({ width = 220 }),
					UI.Spacer({ width = fill }),
					about(nil),
				})
			end)
		end
		-- Up to six same-genre games, excluding the one already open.
		local discoveryPath = callbacks.discoveryPath or Compose.cell({})
		local similarGames = Compose.formula(function(use)
			local base = use(lastSelected)
			local list = {}
			if base then
				for _, item in use(feed.items) do
					if item.id ~= base.id and item.genre == base.genre then
						table.insert(list, item)
						if #list >= 6 then
							break
						end
					end
				end
			end
			return list
		end)
		-- A new selection always lands on the game's own info, never mid-browse.
		Compose.watch(function(use)
			use(selected)
			discoveryPath:set({})
		end)
		-- Each route scrolls its own content: a stack page fills its stack, and a
		-- page inside an outer scroll would have no height to fill.
		local function infoRoute()
			return UI.ScrollView("InfoScroll")({
				axis = "y",
				width = fill,
				height = fill,
				UI.VStack("Body")({
					width = fill,
					gap = "m",
					UI.Divider({ width = fill }),
					text(field("description", "Explore this world with friends."), "body", "secondary"),
					UI.ForEach("Creator")({
						Compose.keyed({
							from = creatorList,
							key = function(item)
								return item.id
							end,
							render = function(item)
								local game = item:peek()
								-- `ref` hands back the composite's own record
								-- (round-2 addendum): `record.api.state` is
								-- `Controls.AsyncImage`'s provider Readable, which
								-- is what drives the shimmer's own visibility.
								local imageState
								local avatar = UI.AsyncImage("Avatar")({
									provider = creatorImages,
									key = game.creatorImage,
									width = fixed(40),
									height = fixed(40),
									ref = function(record)
										imageState = record.api.state
									end,
								})
								return UI.HStack("Row-" .. game.id)({
									width = fill,
									gap = "s",
									align = "center",
									UI.ZStack("AvatarSlot")({
										width = fixed(40),
										height = fixed(40),
										UI.corners(avatar, "pill"),
										-- The shimmer sits ONLY while the request
										-- is pending, over the same slot the image
										-- fills once it resolves — never both.
										Compose.show(function(use)
											return imageState ~= nil and use(imageState) == "pending"
										end, function()
											return UI.corners(shimmerHost("Shimmer-" .. game.id, 40), "pill")
										end),
									}),
									text("By " .. game.creator, "caption", "secondary"),
								})
							end,
						}),
					}),
					UI.Divider({ width = fill }),
					UI.VStack("Trend")({
						width = fill,
						gap = "xs",
						text("Players this week", "caption", "secondary"),
						UI.Path("Sparkline")({
							-- Deterministic per game: no randomness, so the same card
							-- always draws the same trend line headlessly and live.
							points = function(use)
								local item = use(lastSelected)
								local index = if item then item.index else 1
								local points = {}
								for day = 0, 6 do
									local wobble = ((index * (day + 1) * 37) % 23) / 23
									table.insert(points, { x = day / 6, y = 1 - (0.25 + 0.5 * wobble) })
								end
								return points
							end,
							thickness = 3,
							role = "accent",
							width = fill,
							height = fixed(40),
						}),
					}),
					text(function(use)
						local item = use(lastSelected)
						return if item then item.rating .. " recommend  ·  " .. item.players else ""
					end, "body", "secondary"),
					UI.Button("MoreLikeThis")({
						label = "More like this",
						width = fill,
						enabled = function(use)
							return #use(similarGames) > 0
						end,
						onActivate = function()
							discoveryPath:set({ { id = "similar" } })
						end,
					}),
				}),
			})
		end
		local function similarRoute()
			-- Sized against the NavigationStack's own container (not viewport
			-- arithmetic): each row is the full canvas width on a compact layout,
			-- half of it once there is room to breathe.
			local function rows(fraction)
				return UI.ForEach("Matches")({
					Compose.keyed({
						from = similarGames,
						key = function(item)
							return item.id
						end,
						render = function(item)
							local id = item:peek().id
							return UI.containerRelativeFrame(
								UI.RowActions("Row-" .. id)({
									content = UI.Button("Pick-" .. id)({
										label = function(use)
											local v = use(item)
											return v.title .. "  ·  " .. v.rating
										end,
										width = fill,
										onActivate = function()
											setSelected(item:peek())
										end,
									}),
									trailing = {
										{
											id = "save",
											label = "Save",
											onAction = function()
												local v = item:peek()
												local nextSaved = table.clone(saved:peek())
												nextSaved[v.id] = not nextSaved[v.id]
												saved:set(nextSaved)
											end,
										},
									},
								}),
								{ axis = "horizontal", fraction = fraction }
							)
						end,
					}),
				})
			end
			return UI.ScrollView("SimilarScroll")({
				axis = "y",
				width = fill,
				height = fill,
				UI.VStack("Similar")({
					width = fill,
					gap = "s",
					--[[ NO `icon` HERE. `UI.Label.icon` is an ASSET STRING, not one of the
						semantic names `UI.Button`/`UI.CollapsibleView` take — those resolve
						through the theme's icon system and fall back to a glyph, and this one
						goes straight into a `UI.Image`. A semantic name there paints NOTHING:
						a 20px hole and a 26px gap in front of the title, at every size, in
						both themes. Absent, the label degrades to title-only, which is what
						this heading wanted. ]]
					UI.Label("Heading")({ title = "More like this" }),
					Compose.show(compactWidth, function()
						return rows(1)
					end, function()
						return rows(0.5)
					end),
				}),
			})
		end
		desktop = UI.ZStack("Desktop")({
			width = fill,
			height = fill,
			UI.VStack("Browse")({
				width = fill,
				height = fill,
				gap = "m",
				enabled = function(use)
					return use(selected) == nil
				end,
				UI.HStack({
					width = fill,
					gap = "m",
					align = "center",
					--[[ THE SORT TAKES THE SLACK. A fixed 148 beside a fixed 184 and two
						gaps is 360px of demand on a 345px phone row — the shelf switch ran
						off the right edge by 19px at 393 and 92px at 320. The switch is the
						fixed thing (two words that must both stay readable); the sort takes
						whatever is left and shortens its own value before anything leaves
						the screen. On a regular width this row is a caption and the switch,
						and the sort lives beside the search instead. ]]
					Compose.show(compactWidth, function()
						return sortPopup({ minWidth = 112, maxWidth = "infinity" })
					end, function()
						return text("Recommended for you", "body", "secondary")
					end),
					Compose.show(function(use)
						return not compactWidth(use)
					end, function()
						return UI.Spacer({ width = fill })
					end),
					UI.dropTarget(
						--[[ THE SWITCH IS AS WIDE AS ITS TWO WORDS, WHATEVER SIZE THEY ARE.
							A raw `{ width = 164 }` is a near-distance number, and type is not:
							at ten-foot the theme scales every glyph by about 1.5 while that
							frame did not move, so "Browse" and "Saved" both came out as
							"Br…"/"Sav…" on a television (found live on the xbox profile,
							2026-09-20). `sizing = "hug"` is the Picker's own word for
							"natural width, uncapped", so the band measures the labels it is
							actually going to draw — correct at 320px and at ten-foot, with
							no number here to keep in step with the type scale. ]]
						UI.Picker("Shelf")({
							style = "segmented",
							sizing = "hug",
							selected = shelf,
							onChange = function(value)
								shelf:set(value)
							end,
							options = {
								{ value = "browse", label = "Browse" },
								{ value = "saved", label = "Saved" },
							},
						}),
						{
							accepts = function(payload)
								if type(payload) ~= "table" or payload.kind ~= "game" then
									return false, "NOT_A_GAME"
								end
								return true
							end,
							-- The Save button stays the accessible route; this drop zone is
							-- an additional, pointer-only shortcut onto the same toggle.
							onDrop = function(payload)
								local nextSaved = table.clone(saved:peek())
								if nextSaved[payload.id] then
									return
								end
								nextSaved[payload.id] = true
								saved:set(nextSaved)
								for _, item in feed.items:peek() do
									if item.id == payload.id then
										app.presentToast(function()
											return text(`Saved {item.title}`)
										end, { duration = 2.5 })
										break
									end
								end
							end,
						}
					),
				}),
				--[[ THE HERO IS A REGULAR-WIDTH BAND. Its stacked form — art above the
					pitch on a phone — never sized: the card hugged the text, the art's
					`fill` share of a hugging box was 0, and the carousel showed a 56px
					strip with no art in it at all. It was also only ever reachable on a
					compact layout TALLER than 900px, so a phone that met the old gate saw
					the broken form and every other phone saw nothing. A phone goes straight
					to the filters and the grid, which is what it has room to do well. ]]
				--[[ ...AND NOT ON A TELEVISION, WHICH IS A WORKAROUND AND NOT A DESIGN.

					On the ten-foot profile this carousel's whole subtree is present in the
					PlayerGui and the engine draws NONE of it. Verified by painting the
					`Pages` scroller opaque red and seeing the band stay empty, so it is
					not a colour, a theme or a transparency.

					RULED OUT, by dumping the label's whole ancestor chain on xbox and at
					1080p and diffing (2026-09-20):
					  * CanvasGroup texture starvation — there is exactly ONE CanvasGroup
					    on the surface (`Tab-Discover`), it is not nested, its
					    GroupTransparency is 0, and its pixel area is the SAME at both
					    (an xbox profile changes the metric scale, not the resolution).
					  * geometry — every rect in the chain is non-zero and sensible.
					  * clipping — both scrollers clip, and the content sits inside the
					    clipped box at both sizes.
					  * canvas — CanvasPosition is 0,0 and AbsoluteCanvasSize covers the
					    content at both.
					  * visibility and z — `Visible = true` the whole way up, ZIndex
					    ascends, DisplayOrder is the same 10100.
					  * siblings — the chips, the grid and this carousel's own page dots
					    draw normally through the same CanvasGroup on the same frame.

					So it is none of the usual suspects, it is below the showcase, and it
					is unresolved. Until it is, a television shows the filters and the feed
					rather than 280px of nothing. ]]
				Compose.show(function(use)
					return #featuredItems > 0
						and use(shelf) ~= "saved"
						and not compactWidth(use)
						and not tenFoot(use)
						and Facet.adaptive.heightClass(use(viewport).h) ~= "short"
						and use(viewport).h >= 760
				end, featuredCarousel),
				Compose.show(function(use)
					return use(shelf) == "saved" and #use(savedGames) == 0
				end, function()
					return UI.VStack("SavedEmpty")({
						width = fill,
						height = fill,
						gap = "s",
						-- `align` centres ACROSS a stack's line and `distribute` ALONG it;
						-- `alignH`/`alignV` are a ZStack parent's words and left this empty
						-- state pinned to the shelf's top-left corner
						align = "center",
						distribute = "center",
						Compose.show(function(use)
							return not spareLayout(use)
						end, function()
							return icons.draw(UI, "heart", 56, "accent")
						end),
						UI.Text({ text = "Nothing saved yet", textSize = "heading", role = "content" }),
						UI.Text({
							text = "Save a game from its page, or drag a card onto Saved.",
							textSize = "body",
							role = "secondary",
						}),
					})
				end),
				Compose.show(function(use)
					return use(shelf) == "saved" and #use(savedGames) > 0
				end, function()
					return UI.Table("Saved")({
						rows = savedGames,
						key = function(item)
							return item.id
						end,
						--[[ THE ROW CLEARS THE CONTROL IT HOLDS. "The height is a DESCRIPTION,
							not a number" (src/controls/table.luau), and the theme's description is
							derived from TEXT — lines x line box, floored at a target. This table's
							Note column is not text: it is a `UI.TextField`, whose own floor is the
							44px touch target, and the derived row is 10px short of that once a
							television scales the target up. Pinned flat at 48 it was 20px short.

							So the height is still a description — of the tallest thing in the row
							rather than of its type — and it is read from the live metric rather
							than written as a near-distance number. ]]
						rowHeight = function()
							local metrics = app.environment:get("themeMetrics"):peek()
							local targets = if type(metrics) == "table" then metrics.targetSizes else nil
							local floor = if type(targets) == "table" and type(targets.minimum) == "number"
								then targets.minimum
								else 44
							return floor + 16
						end,
						--[[ NO PINNED `rowHeight`. "The height is a DESCRIPTION, not a number"
							(src/controls/table.luau): the theme says how many lines a row holds
							per input paradigm and what floor it may not go under, and the control
							adds the two things only the live environment knows — the ten-foot
							typography scale and the accessibility text offset the engine applies
							on top. Pinned at 48, this table's inline Note field stood 20px past
							its own row on a television and painted across the row below it. Left
							to the theme, a raised text preference gets taller rows instead of
							clipped ones and a touch session gets a row that clears the target
							floor, without this screen asking for either. ]]
						height = fill,
						selection = "single",
						selectedKeys = savedSelection,
						sortOrder = savedSort,
						reorderable = true,
						ref = callbacks.savedTableRef,
						onReorder = function(keys, toIndex)
							savedOrder:set(reorder(savedOrder:peek(), keys, toIndex))
						end,
						onPrimaryAction = function(item)
							shelf:set("browse")
							setSelected(item)
						end,
						columns = {
							{
								id = "title",
								title = "Game",
								sortable = true,
								width = fill,
								value = function(item)
									return item.title
								end,
							},
							{
								id = "genre",
								title = "Genre",
								sortable = true,
								width = fixed(140),
								value = function(item)
									return item.genre
								end,
							},
							{
								id = "rating",
								title = "Rating",
								sortable = true,
								width = fixed(96),
								value = function(item)
									return item.rating
								end,
							},
							{
								id = "note",
								title = "Note",
								width = fixed(160),
								-- A native `cell` (not `value`): the row's own
								-- editable field, not a formatted Text. `itemRead`
								-- is the row's Compose readable — read once to
								-- seed a per-row draft, keyed by the game's own
								-- stable id.
								cell = function(itemRead)
									local gameId = itemRead:peek().id
									local draft = Compose.cell(savedNotes:peek()[gameId] or "")
									local function commit()
										local next = table.clone(savedNotes:peek())
										local value = draft:peek()
										if value == "" then
											next[gameId] = nil
										else
											next[gameId] = value
										end
										savedNotes:set(next)
									end
									return UI.TextField("Note")({
										text = draft,
										placeholder = "Add a note",
										width = fill,
										surface = "control",
										onTextChanged = function(value)
											draft:set(value)
										end,
										-- Return and focus loss both commit; Escape
										-- reverts the draft to the last saved note.
										onFocusLost = function(reason)
											if reason == "cancel" then
												draft:set(savedNotes:peek()[gameId] or "")
											else
												commit()
											end
										end,
									})
								end,
							},
						},
					})
				end),
				--[[ STRUCTURAL, NOT HIDDEN. `hidden` keeps a node's layout box and
					stops painting it — which is right for a control that must not move
					its siblings, and wrong here: this stack declares `height = fill`,
					so on the Saved shelf it went on claiming half the Browse column and
					the Saved table got the other half of the height it asked for. The
					grid's scroll position survives the unmount anyway, because
					`scrollNavigation.position` is a cell the showcase owns, not state
					inside the node. ]]
				Compose.show(function(use)
					return not savedShown(use)
				end, function()
					return UI.VStack("Catalog")({
						width = fill,
						height = fill,
						gap = "m",
						UI.AdaptiveStack("Filters")({
							width = fill,
							gap = "s",
							-- The six genres and the tools share a row only where both fit.
							-- On a monitor canvas the tools take their own row, so no chip
							-- is sliced by the search field.
							axis = function(use)
								return if filtersStacked(use) then "y" else "x"
							end,
							UI.ScrollView("Genres")({
								axis = "x",
								indicators = "none",
								width = fill,
								UI.HStack({
									gap = "s",
									-- room for the chips' outline: a scroller clips at its own
									-- edge, and a pill that fills it loses its top and bottom
									padding = 2,
									table.unpack((function()
										local chips = {}
										for _, name in require("./catalog").genres do
											table.insert(
												chips,
												UI.Chip("Genre-" .. name)({
													label = name,
													selected = genreChips[name],
													onToggle = function(on)
														if on then
															genre:set(name)
														elseif genre:peek() == name then
															genre:set(nil)
														end
													end,
												})
											)
										end
										-- One consistent outline across the whole genre-chip group, so
										-- a theme can style the group as a unit.
										return UI.styleGroup({
											stroke = { thickness = 1, color = "contentSecondary", transparency = 0.5 },
										}, chips)
									end)()),
								}),
							}),
							UI.HStack("Tools")({
								gap = "s",
								width = function(use)
									return if filtersStacked(use) then fill else fixed(452)
								end,
								UI.frame(
									UI.ComboBox("Search")({
										value = searchValue,
										text = query,
										placeholder = "Search games",
										acceptCustom = function()
											return true
										end,
										options = function(use)
											local q = use(query):lower()
											local list = {}
											if q ~= "" then
												for _, item in use(feed.items) do
													if #list >= 8 then
														break
													end
													if item.title:lower():find(q, 1, true) then
														table.insert(list, { id = item.id, label = item.title })
													end
												end
											end
											return list
										end,
										onChange = function(id)
											for _, item in feed.items:peek() do
												if item.id == id then
													setSelected(item)
													break
												end
											end
										end,
									}),
									{ minWidth = 200, maxWidth = "infinity" }
								),
								Compose.show(function(use)
									return not compactWidth(use)
								end, function()
									return sortPopup(176)
								end),
							}),
						}),
						-- Filters that match nothing say so, and offer the way back.
						Compose.show(function(use)
							return #use(visibleGames) == 0
						end, function()
							return UI.VStack("NoMatches")({
								width = fill,
								gap = "s",
								--[[ AN EMPTY STATE IS A BAND, AND A LANDSCAPE PHONE HAS 150px OF
									THEM. At `xl` padding with a mark above it this one measured
									194px against the 152 the feed had, and it painted straight over
									the grid below. It keeps the sentence and the way back at every
									size and spends the mark only where there is room for it.

									`align` centres ACROSS a stack's line; `alignH` is a ZStack
									parent's word and did nothing here. ]]
								padding = function(use)
									return if spareLayout(use) then "s" else "l"
								end,
								align = "center",
								Compose.show(function(use)
									return not spareLayout(use)
								end, function()
									return icons.draw(UI, "search", 32, "secondary")
								end),
								UI.Text({
									text = "No games match",
									textSize = "heading",
									textAlign = "center",
									width = fill,
								}),
								UI.Text({
									text = "Try another genre or a shorter search.",
									role = "secondary",
									textAlign = "center",
									width = fill,
								}),
								UI.Button("ClearFilters")({
									label = "Clear filters",
									onActivate = function()
										genre:set(nil)
										query:set("")
										searchValue:set("")
									end,
								}),
							})
						end),
						UI.VirtualGrid("Games")({
							scrollNavigation = if callbacks.discoveryScroll
								then {
									position = callbacks.discoveryScroll,
									active = callbacks.scrollActive,
								}
								else nil,
							items = visibleGames,
							key = "id",
							columns = function(use)
								-- The same arithmetic UI.Grid derives its own column count from,
								-- against this container's own viewport (a 920x640 monitor
								-- canvas in Spatial mode, the real screen once presented flat).
								local available = use(app.environment:get("viewportRect")).w - 48
								return math.min(6, Facet.adaptive.columnsFor(available, 260, 0))
							end,
							itemExtent = 240,
							viewportExtent = "auto",
							gap = "m",
							rowGap = "m",
							overscan = 1,
							width = fill,
							onActivate = function(item)
								setSelected(item)
							end,
							cell = function(plain, ctx)
								-- The cell receives the item; `ctx.current` follows its edits.
								local item = Compose.formula(ctx.current)
								local key = plain.id
								--[[ THE CARD SHOWS WHERE THE RING IS. The grid's own cell-sized
									hit sits BEHIND this card and paints nothing, so until
									`ctx.focused` existed an opaque card could not show focus at
									all — a catalog a player could walk with the keyboard with no
									idea which card they were on. The control already withholds
									this after a tap (a finger asked no such question), so the
									outline appears for the keyboard and the pad only. ]]
								local card = UI.VStack("Card")({
									width = fill,
									height = fixed(240),
									surface = "raised",
									padding = "s",
									gap = "s",
									stroke = function(use)
										local ring = use(ctx.focused)
										return UI.strokeData({
											thickness = 2,
											color = "accent",
											transparency = if ring then 0 else 1,
										})
									end,
									-- The card stays painted under the expansion: it is the
									-- rectangle the transition reads on every frame.
									onAppear = function(use)
										feed.seen(plain.index)
									end,
									--[[ THE ART TAKES THE SLACK. A 240px cell holding 140 of art, a
										title and a meta line left 31px of dead plate under the last
										row of text — a card that reads bottom-heavy at every size
										because the extent is fixed and the content is not. Filling
										gives those pixels to the one thing that wants them. ]]
									stage("WorldSlice", {
										width = fill,
										height = fill,
										surface = "raised",
									}, function()
										return if callbacks.gameContent then callbacks.gameContent(item) else nil
									end, function(node)
										return UI.corners(node, "panel")
									end),
									UI.Text("Title")({
										text = function(use)
											return use(item).title
										end,
										textSize = "label",
										role = "content",
										width = fill,
									}),
									UI.HStack("Meta")({
										width = fill,
										gap = "xs",
										icons.draw(UI, "star", 14, "accent", 2),
										text(function(use)
											return use(item).rating .. "  ·  " .. use(item).players
										end, "caption", "secondary"),
									}),
								})
								--[[ Dragging a card onto the Browse|Saved switch saves it; the
									Favorite button in the detail panel stays the accessible route.

									NO `declineTouch` HERE ANY MORE. It was declared because the
									engine's `UIDragDetector` claimed the finger from the press and
									the feed could not be scrolled at all — but declining only
									disabled Facet's own drag and left the engine's claim standing,
									so the cost was paid and the drag was unreachable anyway. Now
									that a finger arms the detector by HOLDING STILL
									(`interactionTokens.touchDragArm`), a flick reaches the scroller
									and a hold reaches the drag, and this card wants both. ]]
								card = UI.draggable(card, {
									payload = { kind = "game", id = key },
								})
								cards[key] = card
								Compose.cleanup(function()
									cards[key] = nil
								end)
								return card
							end,
						}),
					})
				end),
			}),
			-- THE SHARED-ELEMENT EXPANSION. The panel is declared at its own
			-- full size; the transition paints it growing out of the card that
			-- opened it and back onto it. Facet re-reads that card's rect every
			-- frame, so a reversal continues from where the paint had reached.
			UI.When("Expand")({
				condition = function(use)
					return use(selected) ~= nil
				end,
				transition = {
					enter = "transform",
					source = { path = sourcePath },
					content = "Body/Information",
					plate = "fades",
				},
				thenView = function()
					--[[ THE PAGE THAT OPENS IS THE PAGE THAT GETS THE RING, and the card
					that opened it is what gets it back.

					Opening a card from the keyboard used to put the ring on the app's TAB
					STRIP (found live, 2026-09-20): the Browse column below declares
					`enabled = false` while a game is selected, so every stop the ring could
					have been standing on went ineligible in the same frame the detail page
					arrived, and the nearest surviving neighbour was three levels up and
					outside the app. On Back the ring did not come home either, so a player
					walking the grid lost their place every time they looked at something.

					`focusOnAppear` names the way OUT of the page rather than the first thing
					in it: a player who has just opened something wants Back under the thumb,
					not the first control the page happens to declare. ]]
					return UI.focusSection(
						UI.ZStack("Details")({
							width = fill,
							height = fill,
							canvasGroup = true,
							clipChildren = true,
							corners = UI.cornersData("panel"),
							surface = "raised",
							UI.AdaptiveStack("Body")({
								--[[ A SHORT VIEWPORT TURNS THE PAGE ON ITS SIDE. Stacked, the
								hero's own 140px FLOOR plus the two pinned rows needed more
								height than a landscape phone has at all: the information area
								was left 111px for 120px of pinned rows, the route inside it
								solved to height 0, and its whole body — description, creator,
								sparkline, "More like this" — painted 350px below the panel that
								was supposed to clip it. Side by side, the hero takes width
								instead of height and the information keeps a column it can
								actually scroll. ]]
								axis = function(use)
									return if sideBySide(use) then "x" else "y"
								end,
								width = fill,
								height = fill,
								padding = "s",
								gap = "m",
								enabled = function(use)
									return use(selected) ~= nil
								end,
								--[[ THE HERO NEVER EATS THE WHOLE PANEL. `h * 0.56` alone put
								the description, "More like this" and the sparkline BELOW THE
								FOLD on the 920x640 monitor canvas, inside a `clipChildren`
								panel with nothing to scroll — unreachable, with no affordance
								saying so. The third term reserves room for the Information
								area at any height: two pinned rows, the route's own bar, and a
								scrolling body that is still worth reading. ]]
								stage("World", {
									width = function(use)
										-- beside the information rather than above it: two fifths of
										-- the panel, never more than a readable column's worth
										return if sideBySide(use)
											then fixed(math.min(360, use(app.environment:get("viewportRect")).w * 0.4))
											else fill
									end,
									height = function(use)
										if sideBySide(use) then
											return fill
										end
										local h = use(app.environment:get("viewportRect")).h
										-- A short PORTRAIT window cannot turn the page on its side (the
										-- column beside the hero would be 80px wide), so the hero gives
										-- up its floor instead of the information giving up its rows.
										local floor = if shortViewport(use) then 96 else 140
										-- ...and what is reserved for the information BELOW it is two
										-- pinned rows and a route, all of which are type — so the
										-- reservation is in the metric this screen draws with. At a flat
										-- 460 a television's route overflowed its page by 41px.
										local reserve = (scaled(460)(use) :: any).px
										return fixed(math.max(floor, math.min(520, h * 0.42, h - reserve)))
									end,
									surface = "raised",
								}, function()
									return if callbacks.gameContent
										then callbacks.gameContent(lastSelected)
										else callbacks.discoveryContent
								end),
								-- the transition's `content` group: the plate grows, the
								-- information inside it crossfades on its own beat
								UI.ZStack("Information")({
									width = fill,
									height = fill,
									canvasGroup = true,
									UI.padding(
										UI.VStack({
											width = fill,
											height = fill,
											gap = "m",
											UI.HStack({
												width = fill,
												gap = "m",
												UI.Button("Back")({
													label = "Back",
													onActivate = function()
														setSelected(nil)
													end,
												}),
												text(field("title", ""), "title"),
												-- wide enough for either label, so "Saved" never truncates
												UI.frame(
													UI.Button("Favorite")({
														label = function(use)
															local item = use(selected)
															return if item and use(saved)[item.id]
																then "Saved"
																else "Save"
														end,
														onActivate = function()
															local item = selected:peek()
															if item then
																local nextSaved = table.clone(saved:peek())
																nextSaved[item.id] = not nextSaved[item.id]
																saved:set(nextSaved)
																app.presentToast(function()
																	return text(
																		if nextSaved[item.id]
																			then `Saved {item.title}`
																			else `Removed {item.title}`
																	)
																end, { duration = 2.5 })
															end
														end,
													}),
													{ width = 96 }
												),
											}),
											ratingRow(),
											--[[ ...and the route itself SCROLLS. The title row and
											the rating row stay pinned; everything the route adds —
											description, creator, sparkline, "More like this" — is
											reachable at every canvas this showcase runs on, which a
											clipped natural-height box was not. ]]
											UI.NavigationStack("Info")({
												path = discoveryPath,
												backLabel = "Back",
												transition = { enter = "slide-left" },
												root = { title = "About", content = infoRoute },
												destinations = {
													similar = { title = "More like this", content = similarRoute },
												},
											}),
										}),
										"m"
									),
								}),
							}),
						}),
						{ focusOnAppear = "Back", returnFocus = true }
					)
				end,
			}),
		})
		return root("Discover", { chrome("Discover", "Discover"), desktop })
	end
	local function Avatar()
		local viewport = app.environment:get("viewportRect")
		-- The stack-above threshold this app wants; `adaptive.axisFor` is the same
		-- decision AdaptiveStack itself binds, so "wide" here and the Workspace
		-- stack's own axis can never disagree.
		local function wide(use)
			return Facet.adaptive.axisFor(use(viewport).w, { stackAbove = 760 }) == "x"
		end
		local function compactWidth(use)
			return use(viewport).w < 640
		end
		-- A row whose label will not share its line with its control: a phone at a
		-- large text preference, and a television, which are the same problem seen
		-- from two ends — the label, the readout and the two targets all grow, and
		-- the row they sit in does not.
		local function labelOnOwnLine(use)
			return compactWidth(use) or tenFoot(use)
		end
		local palette = callbacks.avatarPalette or Facet.Compose.cell("sage")
		local hat = callbacks.avatarHat or Facet.Compose.cell(true)
		local angle = callbacks.avatarAngle or Compose.cell(-15)
		local confirmReset = Compose.cell(false)
		local summaryShown = callbacks.avatarSummaryShown or Compose.cell(false)
		local advancedExpanded = callbacks.avatarTipsExpanded or Compose.cell(false)
		local summaryDetent = callbacks.avatarSummaryDetent or Compose.cell("medium")
		-- Turn step: the Stepper and the Slider share one signal, the standard
		-- pairing rule (`docs` level_picker precedent) — the Stepper walks a fixed
		-- ladder of degree presets; the Slider and the Turn buttons read its
		-- current value so all three agree on one increment.
		local turnSteps = { 15, 30, 45, 90 }
		local turnStepIndex = callbacks.avatarTurnStepIndex or Compose.cell(2)
		local turnStep = Compose.formula(function(use)
			return turnSteps[use(turnStepIndex)]
		end)
		-- The Turn buttons and the slider move one angle, kept within a full turn.
		local function turn(direction)
			angle:set((angle:peek() + direction * turnStep:peek() + 180) % 360 - 180)
		end
		local function color(use)
			return use(palette)
		end
		local function accessory(use)
			return use(hat)
		end
		local function setColor(value)
			palette:set(value)
		end
		local function setAccessory(value)
			hat:set(value)
		end
		-- Rotation sits beside the settings it previews, so one scroller reaches
		-- every control. The row stacks when the settings column is too narrow.
		local rotation = UI.AdaptiveStack("Rotate")({
			axis = function(use)
				local w = use(viewport).w
				return if wide(use) or w < 380 then "y" else "x"
			end,
			width = fill,
			gap = "s",
			UI.Button("TurnLeft")({
				label = "Turn left",
				width = fill,
				onActivate = function()
					turn(-1)
				end,
			}),
			UI.Button("TurnRight")({
				label = "Turn right",
				width = fill,
				onActivate = function()
					turn(1)
				end,
			}),
		})
		--[[ Auto-spin: 0 Off, 1 Slow, 2 Fast, in degrees per second. Reduced motion
			holds the current angle instead of animating it.

			ONE DRIVER, HOWEVER MANY VIEWS ARE MOUNTED. `angle` is SHARED model
			state — the monitor's Avatar app and the desktop shell's Avatar tab read
			and write the same cell — so a per-view frame connection integrated it
			once PER MOUNT, and during a mode transition, while both presentations
			are alive, the preview spun at double rate and then snapped back. The
			claim below is the smallest thing that cannot drift: whoever mounts
			first drives, the rest watch, and the claim is released with its view so
			the survivor picks it up. ]]
		local autoSpin = callbacks.avatarAutoSpin or Compose.cell(0)
		local SPIN_RATES = { 0, 30, 75, 150 }
		local spinDriver = callbacks.avatarSpinDriver or {}
		if callbacks.avatarSpinDriver == nil then
			callbacks.avatarSpinDriver = spinDriver
		end
		local claim = {}
		if spinDriver.owner == nil then
			spinDriver.owner = claim
		end
		Compose.cleanup(function()
			if spinDriver.owner == claim then
				spinDriver.owner = nil
			end
		end)
		Compose.cleanup(app.onFrame(function(dt)
			if spinDriver.owner ~= claim then
				return
			end
			if app.environment:get("motionPolicy"):peek() == "reduced" then
				return
			end
			local rate = SPIN_RATES[autoSpin:peek() + 1]
			if rate and rate > 0 then
				angle:set((angle:peek() + rate * dt + 180) % 360 - 180)
			end
		end))
		-- A HUD over the 3D preview: three ranked facts about the look on
		-- screen (palette + hat, live rotation, auto-spin), each declaring
		-- rich -> compact -> minimal forms so `UI.Composition` degrades them
		-- under space pressure instead of a hand-rolled device branch. It is a
		-- sibling of `Content` in the root ZStack (see `root`'s `overlays`),
		-- so `Preview`'s own path never moves.
		local paletteNames = { sage = "Sage", clay = "Clay", iris = "Iris" }
		local spinNames = { "Off", "Slow", "Medium", "Fast" }
		--[[ THE WIDTH GOES ON THE CHIP, NOT ON THE LABEL INSIDE IT. `UI.background`
			copies its base's own dims onto the wrapper it builds (so a fill-width base
			is never collapsed to the size of its plate) — which meant a `fixed` width
			on the TEXT became the PLATE's width too, and the `xs` padding then took 8
			of those px back from the text that had asked for all of them. The label ran
			8px past its own plate, onto the preview beside it, at every compact size.
			One width, declared on the box that is meant to carry it. ]]
		local function hudChip(id, width, content)
			return UI.frame(
				UI.corners(
					UI.padding(UI.background(content, UI.Box(id .. "Plate")({ surface = "chip" })), "xs"),
					"pill"
				),
				{ width = width }
			)
		end
		-- Each form declares its own fixed width, so the composition's ladder
		-- steps on a deterministic measure instead of font metrics: a rich
		-- plate needs real room for a label AND a value line, a compact chip
		-- needs enough for the value alone, and a minimal chip is a glyph.
		local function hudRich(id, label, valueFn)
			return UI.corners(
				UI.VStack(id)({
					gap = 0,
					width = fixed(140),
					surface = "chip",
					padding = "xs",
					UI.Text(id .. "Label")({ text = label, textSize = "caption", role = "secondary", lineLimit = 1 }),
					UI.Text(id .. "Value")({ text = valueFn, textSize = "caption", lineLimit = 1 }),
				}),
				"control"
			)
		end
		local function hudCompact(id, valueFn)
			return hudChip(
				id,
				54,
				UI.Text(id .. "T")({ text = valueFn, textSize = "caption", lineLimit = 1, width = fill })
			)
		end
		local function hudMinimal(id, glyph)
			return hudChip(
				id,
				22,
				UI.Text(id .. "T")({
					text = glyph,
					textSize = "caption",
					lineLimit = 1,
					width = fill,
					textAlign = "center",
				})
			)
		end
		-- THE QUICK PALETTE RING. A radial menu wants the space left after the
		-- chrome, so it is an overlay of the whole screen with no launcher of its
		-- own; the settings row opens it.
		local quickRing
		--[[ ...AND THE RING KEEPS OFF THE EDGES. Its own status caption anchors to
			the BOTTOM of whatever box it is given, and the box was the whole screen — so
			"Quick palette" sat flush on the monitor's bottom edge, a hair under the
			preview HUD and reading as a fourth chip in that stack. A padded layer is the
			inset; the ring stays centred in what is left of it. ]]
		local quickRingOverlay = UI.ZStack("QuickRingArea")({
			width = fill,
			height = fill,
			padding = "l",
			UI.RadialMenu("QuickRing")({
				label = "Quick palette",
				launcher = false,
				--[[ ROUND SWATCHES, NOT WEDGES. Three colours on a `wedges` ring paint
				three small skewed label plates around an empty middle — the default
				reads as a slice of a menu with many entries, and this one has three.
				`buttons` gives each palette its own round target on the same ring,
				which is the shape a colour picker wants and the one a thumb can hit. ]]
				appearance = "buttons",
				items = {
					{
						id = "sage",
						label = "Sage",
						onSelect = function()
							setColor("sage")
						end,
					},
					{
						id = "clay",
						label = "Clay",
						onSelect = function()
							setColor("clay")
						end,
					},
					{
						id = "iris",
						label = "Iris",
						onSelect = function()
							setColor("iris")
						end,
					},
				},
				ref = function(record)
					quickRing = record.api
				end,
			}),
		})
		local previewHud = UI.Composition("PreviewHud")({
			-- The compact column is its widest chip (a 46px value) plus that chip's
			-- own pill padding and this composition's: 46 + 8 + 16 + the lane's own
			-- 8. Short by those last eight, the value text stood 8px outside its
			-- plate and painted over the preview beside it.
			width = function(use)
				return fixed(if compactWidth(use) then 78 else 260)
			end,
			padding = "s",
			laneGap = "xs",
			groupGap = "xs",
			surface = "plain",
			--[[ A CORNER AND AN INSET, WHICH IS WHAT `UI.Anchor` IS FOR. This
				composition carried `offsetX`/`offsetY` under the screen's ROOT ZSTACK,
				which places by layering and reads neither — so the nudge moved nothing
				and the HUD sat flush against the screen's own edge, 14px outside the
				preview it belongs to, at every size. `diagnostics()` had been saying so
				on every frame, in as many words: "wrap this child in a `UI.Anchor` (it
				reads offsetX/offsetY)". It is wrapped in one now (see the overlays list
				below) and the pair means what it says. No `alignH`/`alignV` either: an
				Anchor places by CORNER, and those two are a ZStack parent's words.

				22 is the page's own gutter; the extra 12 carries the HUD inside the
				preview's edge rather than sitting on it. ]]
			anchor = function(use)
				return if compactWidth(use) then "topLeft" else "bottomLeft"
			end,
			offsetX = 34,
			offsetY = function(use)
				-- compact: under the title, over the preview stacked above the settings.
				-- Regular: lifted off the bottom edge by the same inset the leading edge
				-- uses, so the HUD sits in the preview's own lower-left corner.
				return if compactWidth(use) then 132 else -34
			end,
			groups = { { id = "info", lane = "main", sizing = "hug", place = "start" } },
			arrangements = { { name = "single", lanes = { { "main" } } } },

			UI.Region("Look")({
				group = "info",
				rank = 1,
				recover = "self",
				floor = { lines = 1 },
				hudRich("LookRich", "Look", function(use)
					local name = paletteNames[use(palette)] or use(palette)
					return if use(hat) then `{name} · Hat on` else `{name} · Hat off`
				end),
				hudCompact("LookCompact", function(use)
					return paletteNames[use(palette)] or use(palette)
				end),
				hudMinimal("LookMinimal", function(use)
					return string.upper(string.sub(paletteNames[use(palette)] or use(palette), 1, 1))
				end),
			}),
			UI.Region("Rotation")({
				group = "info",
				rank = 2,
				recover = "self",
				floor = { lines = 1 },
				hudRich("RotationRich", "Rotation", function(use)
					return `{math.round(use(angle))}°`
				end),
				hudCompact("RotationCompact", function(use)
					return `{math.round(use(angle))}°`
				end),
				hudMinimal("RotationMinimal", function(use)
					return `{math.round(use(angle))}°`
				end),
			}),
			UI.Region("Spin")({
				group = "info",
				rank = 3,
				recover = "self",
				floor = { lines = 1 },
				hudRich("SpinRich", "Spin", function(use)
					return spinNames[use(autoSpin) + 1]
				end),
				hudCompact("SpinCompact", function(use)
					return spinNames[use(autoSpin) + 1]
				end),
				hudMinimal("SpinMinimal", function(use)
					return string.sub(spinNames[use(autoSpin) + 1], 1, 1)
				end),
			}),
		})
		return root("Avatar", {
			chrome("Avatar", "Avatar"),
			-- A short viewport gives the title's band to the preview.
			Compose.show(function(use)
				return Facet.adaptive.heightClass(use(viewport).h) ~= "short"
			end, function()
				return text("Customize your character.", "body", "secondary")
			end),
			UI.AdaptiveStack("Workspace")({
				height = fill,
				axis = function(use)
					return Facet.adaptive.axisFor(use(viewport).w, { stackAbove = 760 })
				end,
				width = fill,
				gap = "l",
				-- The stacked preview stays pinned above the scrolling settings and
				-- yields height on shorter viewports.
				stage("Preview", {
					content = callbacks.avatarContent,
					width = fill,
					height = function(use)
						return if wide(use) then fill else fixed(math.clamp(use(viewport).h * 0.3, 120, 280))
					end,
					surface = "raised",
				}),
				UI.ScrollView("Settings")({
					-- 340 at near distance, and the same column in the metric a television
					-- draws with — at a flat 340 the slider row stood 95px past it and the
					-- turn stepper 234px, because every control inside had grown and the
					-- column had not.
					width = function(use)
						return if wide(use) then scaled(340)(use) else fill
					end,
					height = fill,
					-- Directional focus (gamepad/keyboard) stays inside the settings
					-- column instead of leaking out to the preview or the tab bar.
					UI.focusSection(
						UI.VStack("Panel")({
							width = fill,
							gap = "m",
							padding = "m",
							surface = "raised",
							--[[ A SETTINGS PANEL HAS ONE LEFT EDGE. `UI.Label`, `UI.Stepper`
								and `UI.Toggle` all HUG, and a hugging child of a centring column
								sits centred — so the heading floated in the middle of the panel,
								the turn stepper floated under it, and the hat switch stopped
								167px into a 312px row while every other control ran the full
								width. `maxWidth = "infinity"` is the documented fill idiom, and
								it is what puts all four labels on the same gutter and all four
								values on the same trailing edge. ]]
							UI.frame(
								-- no `icon`: see the note on the "More like this" Label above —
								-- `UI.Label.icon` is an asset string, and a semantic name paints an
								-- empty box
								UI.Label("Heading")({ title = "Explorer", textSize = "heading" }),
								{ maxWidth = "infinity" }
							),
							text("Choose a palette and accessories.", "body", "secondary"),
							UI.DisclosureGroup("Appearance")({
								label = "Appearance",
								expanded = callbacks.avatarSettingsExpanded or Compose.cell(true),
								content = function()
									return UI.VStack({
										width = fill,
										gap = "m",
										UI.sensoryFeedback(
											UI.Picker("Palette")({
												label = "Palette",
												style = "segmented",
												selected = palette,
												onChange = setColor,
												options = {
													{ value = "sage", label = "Sage" },
													{ value = "clay", label = "Clay" },
													{ value = "iris", label = "Iris" },
												},
											}),
											{ trigger = palette, event = "select" }
										),
										UI.frame(
											UI.Toggle("Accessory")({
												label = "Explorer hat",
												value = hat,
												onChange = setAccessory,
											}),
											{ maxWidth = "infinity" }
										),
										-- A compact one-tap palette switch, beside the segmented
										-- Picker above. It used to be hidden below 640px: the
										-- radial's LIST form subtracted its launcher gap from a
										-- box that did not have it and hung its scroller below
										-- its own area (fixed in `controls/radial_menu`, pinned
										-- at 393px below), so the affordance is now offered at
										-- every width the showcase runs at.
										UI.HStack("QuickPalette")({
											width = fill,
											gap = "s",
											align = "center",
											text("Quick palette", "caption", "secondary"),
											-- The ring needs room: it opens over the whole monitor
											-- (the overlay below) and this row only asks for it.
											UI.Button("Quick")({
												label = "Palette ring",
												compactLabel = "Ring",
												onActivate = function()
													if quickRing then
														quickRing.open()
													end
												end,
											}),
										}),
									})
								end,
							}),
							-- ...AND THE SAME ROW ON A TELEVISION. The label, the readout and the two
							-- targets all grow with the display, so the row that was 22px too wide at
							-- 393px is 64px too wide at ten-foot for exactly the same reason.
							-- COMPACT: THE LABEL TAKES ITS OWN LINE. A Stepper's row is a
							-- label, a readout and two 44px targets, and it hugs — so below
							-- ~480px at a large text preference that row is wider than the
							-- panel and the "+" paints outside it. The label moves above the
							-- control there and the row keeps the whole line, the same shape
							-- the Auto-spin row below already uses.
							Compose.show(labelOnOwnLine, function()
								return text("Turn step", "label")
							end),
							UI.frame(
								UI.Stepper("TurnStep")({
									label = function(use)
										return if labelOnOwnLine(use) then "" else "Turn step"
									end,
									value = turnStepIndex,
									min = 1,
									max = #turnSteps,
									step = 1,
									format = function(index)
										return `{turnSteps[index]}°`
									end,
								}),
								{ maxWidth = "infinity" }
							),
							-- One increment, three controls: the Stepper picks it, the Turn
							-- buttons spend it, and the slider snaps to it — `Slider.step`
							-- takes the same readable they all read.
							UI.Slider("Angle")({
								label = "Rotation",
								value = angle,
								min = -180,
								max = 180,
								step = turnStep,
								format = function(value)
									return `{math.round(value)}°`
								end,
							}),
							rotation,
							UI.VStack("AutoSpinRow")({
								width = fill,
								gap = "xs",
								UI.HStack({
									width = fill,
									gap = "s",
									UI.VStack({
										width = fill,
										gap = "xs",
										text("Auto-spin", "label"),
										text(function(use)
											local names = { "Off", "Slow", "Medium", "Fast" }
											return names[use(autoSpin) + 1]
										end, "caption", "secondary"),
									}),
									UI.LevelPicker("AutoSpin")({
										value = autoSpin,
										count = 3,
										allowZero = true,
										-- empty steps stay visible against the control plate
										tint = { empty = { role = "contentSecondary", blend = 0.4 } },
										onChange = function(value)
											autoSpin:set(value)
										end,
									}),
								}),
							}),
							UI.HStack({
								width = fill,
								gap = "s",
								UI.Button("Summary")({
									label = "Summary",
									width = fill,
									onActivate = function()
										summaryShown:set(true)
									end,
								}),
								UI.CollapsibleView("Advanced")({
									label = "Tips",
									icon = "edit",
									width = fill,
									expanded = advancedExpanded,
									content = function()
										return UI.VStack({
											width = fill,
											gap = "s",
											padding = "m",
											text(
												"Turn step sets both the Turn buttons and the Stepper's ladder — drag Rotation for finer control.",
												"body",
												"secondary"
											),
											text(
												"Auto-spin keeps turning the preview until you pick Off, or your device asks for reduced motion.",
												"body",
												"secondary"
											),
										})
									end,
								}),
							}),
							UI.Sheet("LookSummary")({
								title = "Look summary",
								isPresented = summaryShown,
								detent = summaryDetent,
								content = function()
									local function row(label, value)
										return UI.GridRow({
											text(label, "body", "secondary"),
											text(value, "body"),
										})
									end
									return UI.VStack("Content")({
										-- a sheet hugs what it holds: the summary states the
										-- width it reads well at, and yields on a phone
										width = { type = "minMax", min = 240, preferred = 420, max = 420 },
										gap = "m",
										UI.Grid("Summary")({
											gap = "s",
											width = fill,
											row("Palette", function(use)
												local names = { sage = "Sage", clay = "Clay", iris = "Iris" }
												return names[use(palette)] or use(palette)
											end),
											row("Hat", function(use)
												return if use(hat) then "On" else "Off"
											end),
											row("Rotation", function(use)
												return `{math.round(use(angle))}°`
											end),
											row("Turn step", function(use)
												return `{use(turnStep)}°`
											end),
											row("Auto-spin", function(use)
												local names = { "Off", "Slow", "Medium", "Fast" }
												return names[use(autoSpin) + 1]
											end),
										}),
										UI.Divider({ width = fill }),
										UI.Button("Done")({
											label = "Done",
											width = fill,
											onActivate = function()
												summaryShown:set(false)
											end,
										}),
									})
								end,
							}),
							UI.Button("Reset")({
								label = "Reset look",
								width = fill,
								onActivate = function()
									confirmReset:set(true)
								end,
							}),
							UI.Alert("ConfirmReset")({
								title = "Reset your look?",
								message = "The palette, hat and rotation return to their defaults.",
								isPresented = confirmReset,
								actions = {
									{ id = "Cancel", label = "Cancel", role = "cancel" },
									{
										id = "Reset",
										label = "Reset",
										role = "destructive",
										onActivate = function()
											palette:set("sage")
											hat:set(true)
											angle:set(-15)
										end,
									},
								},
							}),
						}),
						{ entry = "restore" }
					),
				}),
			}),
		}, {
			-- The HUD sits over the preview: its lower left beside the settings
			-- panel, and under the title when the preview is stacked above them.
			-- It is only as large as its plates, so the page under it stays live.
			-- The Anchor is the layer that READS a corner and an offset; the HUD names
			-- both on itself (see `PreviewHud` above).
			UI.Anchor("PreviewHudArea")({ width = fill, height = fill, previewHud }),
			quickRingOverlay,
		})
	end
	local function Chat()
		local conversation = callbacks.chat or require("./chat_model").new(Facet.Compose)
		if not callbacks.chat then
			Compose.cleanup(conversation.dispose)
		end
		-- The hint shows until a prompt is used, and only on an empty conversation.
		local promptUsed = callbacks.chatPromptUsed or Compose.cell(false)
		local hintShown = Compose.cell(#conversation.messages:peek() == 0 and not promptUsed:peek())
		local chatFollow = callbacks.chatFollow or Compose.cell(true)
		local function read(source)
			return function(use)
				return use(source)
			end
		end
		return root("Chat", {
			chrome("Assistant", "Chat"),
			-- The thread's toolbar shares the conversation's centred column.
			UI.ZStack("Header")({
				width = fill,
				alignH = "center",
				UI.HStack("Bar")({
					width = { type = "percent", fraction = 1, max = 960 },
					gap = "m",
					-- the caption sits on the menu button's centre line: an hstack's
					-- cross-axis word is `align`, and `alignV` (a ZStack parent's word)
					-- left the caption pinned to the top of a 46px row
					align = "center",
					-- the thread's own status, on the title's edge; its menu, on the actions'
					--[[ THE CAPTION TAKES THE SLACK, so the menu beside it never has to
						give up its own label. `compactLabel` is a FIT degrade — the solver
						reaches for it only when the width a button is GIVEN is too small for
						the full string — and a hugging button is never given too little, so
						at 320px this row simply ran 38px past its box. One fill child is the
						whole rule: the status is what yields, and it yields exactly as much
						as the row is short. ]]
					UI.Text("Status")({
						text = function(use)
							local count = #use(conversation.messages)
							return if count == 0 then "New conversation" else `{count} messages`
						end,
						textSize = "caption",
						role = "secondary",
						width = fill,
						lineLimit = 1,
					}),
					UI.Menu("ConversationMenu")({
						-- A trigger rather than a bare `label`, for the one thing a label
						-- cannot carry: a compact spelling. At 320px "Conversation" plus the
						-- thread's own status ran 38px past this bar.
						trigger = UI.Button("ConversationMenu")({
							label = "Conversation",
							compactLabel = "Thread",
						}),
						items = {
							{
								id = "suggest",
								label = "Suggest",
								children = {
									{
										id = "findGame",
										label = "Find a game",
										onSelect = function()
											promptUsed:set(true)
											conversation.draft:set("What game should I play with friends?")
										end,
									},
									{
										id = "buildSomething",
										label = "Build something",
										onSelect = function()
											conversation.draft:set("Help me build a game browser")
										end,
									},
								},
							},
							{
								id = "followReplies",
								label = "Follow replies",
								checked = chatFollow,
								onChange = function(value)
									chatFollow:set(value)
								end,
							},
							{ divider = true },
							{
								id = "clear",
								label = "Clear conversation",
								role = "destructive",
								onSelect = conversation.clear,
							},
						},
					}),
				}),
			}),
			UI.ZStack("Conversation")({
				width = fill,
				height = fill,
				alignH = "center",
				UI.VStack({
					width = { type = "percent", fraction = 1, max = 960 },
					height = fill,
					gap = "m",
					--[[ THE WELCOME SITS OVER THE THREAD, NOT ABOVE IT. As a SIBLING of
						the list, both declared `height = fill` and split the thread area in
						half — so on a 1080p screen the greeting floated in the upper half
						with a dead band under it, and on a small phone its half was 43px
						too short for the greeting to fit at all (it painted over the empty
						list below). Layered, it owns the whole thread box while the thread
						is empty, and the list underneath is never unmounted: its scroll
						position, its follow state and its row lifetimes survive the first
						message instead of being rebuilt by it. ]]
					UI.ZStack("Thread")({
						width = fill,
						height = fill,
						Compose.show(function(use)
							return #use(conversation.messages) == 0
						end, function()
							-- A short entrance each time the welcome reappears (a fresh
							-- conversation, or Clear). Reduced motion holds it fully visible.
							local welcomeShown = Compose.cell(0)
							local welcomeMotion = app.runtime.tween(function(use)
								return use(welcomeShown)
							end, { seconds = 0.24 })
							welcomeShown:set(1)
							local function reveal(use)
								if use(app.environment:get("motionPolicy")) == "reduced" then
									return 1
								end
								return math.clamp(use(welcomeMotion), 0, 1)
							end
							return UI.ZStack("Welcome")({
								width = fill,
								height = fill,
								alignV = "center",
								canvasGroup = true,
								opacity = reveal,
								--[[ THE RISE IS PAINT, NOT LAYOUT. `offsetY` is the LAYOUT
								offset a `UI.Anchor` parent reads; under this vstack it was
								accepted and then ignored, so the entrance only ever faded.
								The `offset` PROP is the paint-only translation that belongs
								beside `opacity` — same channel, same frame, no re-measure. ]]
								offset = function(use)
									return { x = 0, y = (1 - reveal(use)) * 12 }
								end,
								UI.VStack({
									width = fill,
									gap = "s",
									-- A LANDSCAPE PHONE HAS NO ROOM FOR A MARK. The greeting's
									-- glyph and its second line stood 35px past the thread box
									-- there and painted over the composer. A short viewport keeps
									-- the question and drops the ornament around it.
									Compose.show(function(use)
										return Facet.adaptive.heightClass(use(app.environment:get("viewportRect")).h)
											~= "short"
									end, function()
										return icons.draw(UI, "sparkle", 40, "accent")
									end),
									Compose.show(function(use)
										return Facet.adaptive.heightClass(use(app.environment:get("viewportRect")).h)
											~= "short"
									end, function()
										return header(
											"What are you working on?",
											"Ask a question or try a prompt below."
										)
									end, function()
										return text("What are you working on?", "title")
									end),
								}),
							})
						end),
						UI.VirtualList("History")({
							scrollNavigation = if callbacks.chatScroll
								then {
									position = callbacks.chatScroll,
									active = callbacks.scrollActive,
								}
								else nil,
							width = fill,
							-- "auto" measures the list's viewport from the box it is given, and
							-- the box is now the whole thread area: the welcome is LAYERED over
							-- this list rather than stacked above it
							viewportExtent = "auto",
							rows = conversation.messages,
							key = "id",
							itemExtent = "measured",
							estimatedItemExtent = 100,
							rowGap = "m",
							overscan = 2,
							-- Live-bound to the Conversation menu's "Follow replies" item
							-- (VirtualList.follow now takes a readable / function(use)).
							follow = function(use)
								return if use(chatFollow) then "end" else "none"
							end,
							followThreshold = 48,
							-- Swipe a message, or press Delete on it, to remove it.
							rowActions = function(message)
								return {
									trailing = {
										{
											id = "delete",
											role = "destructive",
											label = "Delete",
											onAction = function()
												conversation.remove(message.id)
											end,
										},
									},
								}
							end,
							cell = function(_, ctx)
								local item = Compose.formula(ctx.current)
								-- The reply arrives a character at a time. The reveal owns the
								-- placeholder and the codepoint boundary; the model owns the text.
								local reply = Facet.motion.newTextReveal({
									value = function(use)
										return use(item).content
									end,
									placeholder = "Thinking…",
								})
								return UI.HStack({
									width = fill,
									gap = "s",
									Compose.show(function(use)
										return use(item).role == "assistant"
									end, function()
										-- Pinned to the message's top line, not centered on the
										-- whole (possibly multi-line) bubble: `lineAlign` is the
										-- shared box property `UI.alignment` sets on a ZStack
										-- child; a stack child names it directly.
										return UI.ZStack("Glyph")({
											width = fixed(20),
											height = fixed(20),
											lineAlign = "start",
											icons.draw(UI, "sparkle", 20, "accent"),
										})
									end),
									UI.VStack({
										width = fill,
										gap = "s",
										padding = "m",
										surface = function(use)
											return if use(item).role == "user" then "control" else "plain"
										end,
										text(function(use)
											return if use(item).role == "user" then "You" else "Assistant"
										end, "label"),
										text(reply.text),
									}),
								})
							end,
						}),
					}),
					UI.HStack({
						width = fill,
						gap = "s",
						-- Two starter prompts read best side by side and must not be cut
						-- down to fit: at 393px they are 2px too wide for the column, and
						-- narrower still on a small phone. A wrapping row takes the second
						-- line only when it needs one, so neither label is ever truncated.
						wrap = true,
						UI.Callout("PromptHint")({
							anchor = UI.Button("GamePrompt")({
								label = "Find a game",
								onActivate = function()
									promptUsed:set(true)
									conversation.draft:set("What game should I play with friends?")
								end,
							}),
							-- The tip sits above its prompt, clear of the message field, and
							-- starts on the prompt's leading edge so it stays inside the column.
							edge = "top",
							align = "start",
							isPresented = hintShown,
							featureUsed = promptUsed,
							-- The shared model remembers a retired hint for the session.
							onRetire = function()
								promptUsed:set(true)
							end,
							content = function()
								return text("Start from a prompt, then edit it before you send.")
							end,
						}),
						UI.Button("BuildPrompt")({
							label = "Build something",
							onActivate = function()
								conversation.draft:set("Help me build a game browser")
							end,
						}),
					}),
					-- The reply's progress runs above the composer, so the field never moves.
					Compose.show(read(conversation.streaming), function()
						-- Determinate: streamed vs. total characters of the in-flight
						-- reply. The mode is construction-fixed, but this block remounts
						-- fresh every time streaming turns on, so a real value is always
						-- known before it is built.
						return UI.ProgressView("ResponseProgress")({
							value = function(use)
								return use(conversation.streamedChars)
							end,
							min = 0,
							max = math.max(1, conversation.totalChars:peek()),
							showValue = false,
						})
					end),
					UI.HStack({
						width = fill,
						gap = "m",
						UI.frame(
							UI.TextInput("Prompt")({
								placeholder = "Message assistant",
								value = conversation.draft,
								onChange = function(value)
									conversation.draft:set(value)
								end,
								onCommit = conversation.send,
							}),
							{ maxWidth = "infinity" }
						),
						UI.frame(
							UI.SplitButton("Send")({
								label = function(use)
									return if use(conversation.streaming) then "Stop" else "Send"
								end,
								menuLabel = "More send options",
								onActivate = function()
									if conversation.streaming:peek() then
										conversation.stop()
									else
										conversation.send()
									end
								end,
								items = {
									{
										id = "fresh",
										label = "Send in a new conversation",
										onSelect = function()
											local kept = conversation.draft:peek()
											conversation.clear()
											conversation.draft:set(kept)
											conversation.send()
										end,
									},
									{
										id = "clear",
										label = "Clear conversation",
										role = "destructive",
										onSelect = conversation.clear,
									},
								},
							}),
							{ width = 148 }
						),
					}),
					text("Simulated responses · No messages leave this device", "caption", "secondary"),
				}),
			}),
		})
	end
	return { Discover = Discover, Avatar = Avatar, Chat = Chat }
end
return screens
