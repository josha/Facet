--!strict

type FacetModule = typeof(require("@repo/tools/typecheck/aliases").FacetModule)
type Runtime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type RobloxTypes = typeof(require("@repo/tools/typecheck/aliases").RobloxTypes)
type Child = typeof(require("@repo/tools/typecheck/aliases").Child)
type MenuItem = typeof(require("@repo/tools/typecheck/aliases").StringMenuItem)
type MenuSpec = typeof(require("@repo/tools/typecheck/aliases").MenuSpec)
type StringPickerOption = typeof(require("@repo/tools/typecheck/aliases").StringPickerOption)
type PickerOption = typeof(require("@repo/tools/typecheck/aliases").PickerOption)
type OverlayAction = typeof(require("@repo/tools/typecheck/aliases").OverlayAction)
type TableColumn = typeof(require("@repo/tools/typecheck/aliases").TableColumn)
type AlertAction = typeof(require("@repo/tools/typecheck/aliases").AlertAction)
type RowAction = typeof(require("@repo/tools/typecheck/aliases").RowAction)
type Step = typeof(require("@repo/tools/typecheck/aliases").Step)
type Tab = typeof(require("@repo/tools/typecheck/aliases").Tab)
type PathPoint = typeof(require("@repo/tools/typecheck/aliases").PathPoint)
type CardAction = typeof(require("@repo/tools/typecheck/aliases").CardAction)
type CardMenu = typeof(require("@repo/tools/typecheck/aliases").CardMenu)
type CollectionPlacement = typeof(require("@repo/tools/typecheck/aliases").CollectionPlacement)
type DialogAction = typeof(require("@repo/tools/typecheck/aliases").DialogAction)
type TextProps = typeof(require("@repo/tools/typecheck/aliases").TextProps)
type ButtonProps = typeof(require("@repo/tools/typecheck/aliases").ButtonProps)
type StageProps = typeof(require("@repo/tools/typecheck/aliases").StageProps)
type StackProps = typeof(require("@repo/tools/typecheck/aliases").StackProps)
type ScrollViewProps = typeof(require("@repo/tools/typecheck/aliases").ScrollViewProps)
type EnvironmentPreview = typeof(require("@repo/tools/typecheck/aliases").ControlOptions.environment)
type ReadOnlyValue<T> = typeof(require("@repo/src/vendor/compose/core").accumulator<<T, number>>(nil :: never))
type Value<T> = typeof(require("@repo/src/vendor/compose/core").cell<<T>>(nil :: never))
type Use = typeof(require("@repo/tools/typecheck/aliases").Use)
type ChipRequestProps = typeof(require("@repo/tools/typecheck/aliases").ChipRequestProps)
type MenuCommand = typeof(require("@repo/tools/typecheck/aliases").MenuCommand)
type MonitorPresencePickerSpec = typeof(require("@repo/tools/typecheck/aliases").MonitorPresencePickerSpec)
type RatingProps = typeof(require("@repo/tools/typecheck/aliases").RatingRequestProps)
type ShortcutHintActionProps = typeof(require("@repo/tools/typecheck/aliases").ShortcutHintActionProps)
type StringPickerSpec = typeof(require("@repo/tools/typecheck/aliases").StringPickerSpec)
type TextInputCellProps = typeof(require("@repo/tools/typecheck/aliases").TextInputCellProps)
local modelModule = require("./model")
type Game = modelModule.Game
type Toast = modelModule.Toast
type Actions = modelModule.Actions
type Context = modelModule.Context
type StageContent = modelModule.StageContent
type TextValue = modelModule.TextValue
type TextRole = modelModule.TextRole
type TextExtras = modelModule.TextExtras
local screens = { CANVAS = { w = 920, h = 640 }, SHORT_HEIGHT = 500 }
screens.APPS = table.freeze({ "Discover", "Avatar", "Chat", "Flap" })

function screens.create(Facet: FacetModule, runtime: Runtime, actions: Actions)
	local Compose, Host, civil = Facet.Compose, Facet.host(runtime), Facet.civilDate
	local model = actions.model
	local types: RobloxTypes = actions.types or getfenv(0)
	local D, D2, V2, C3, CF, E = types.UDim, types.UDim2, types.Vector2, types.Color3, types.CFrame, types.Enum
	local environment: EnvironmentPreview = if actions.spatial then { viewingDistance = "near" } else nil
	local UI = Facet.controls(runtime, {
		types = types,
		services = actions.services,
		theme = actions.theme,
		motionLevel = actions.motionLevel,
		pressHaptic = actions.pressHaptic,
		environment = environment,
	})
	local observation = assert(runtime.host.observation, "Virtual Monitors needs property observation")
	local services = actions.services
	local environmentGame = getfenv(0).game
	local inputService = (services and services.UserInputService)
		or (environmentGame and environmentGame:GetService("UserInputService"))
	local touchEnabled = Compose.cell(inputService ~= nil and inputService.TouchEnabled == true)
	if inputService then
		Compose.cleanup(observation.observeProperty(inputService, "TouchEnabled", function()
			touchEnabled:set(inputService.TouchEnabled == true)
		end))
	end
	local clock = actions.clock or civil.systemClock()
	local noCard: GuiObject? = nil
	local selectedCard: Value<GuiObject?> = Compose.cell(noCard)
	local function rounded(radius: number?): UICorner
		return Host.UICorner { CornerRadius = D.new(0, radius or 12) }
	end
	local function words(name: string, value: TextValue, role: TextRole?, extras: TextExtras?): GuiObject
		local spec: TextProps = {
			Name = name,
			text = value,
			textRole = role or "body",
			TextWrapped = true,
			TextYAlignment = E.TextYAlignment.Top,
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
		}
		if extras then
			for key, item in extras do
				spec[if type(key) == "number" then #spec + 1 else key] = item
			end
		end
		return UI.Text(spec)
	end
	local function quiet(name: string, value: TextValue, role: TextRole?, extras: TextExtras?): GuiObject
		local spec: TextExtras = extras or {}
		if spec.role == nil then
			spec.role = "secondary"
		end
		return words(name, value, role or "caption", spec)
	end
	local function button(name: string, label: TextValue, activate: () -> (), extras: ButtonProps?): TextButton
		local spec: ButtonProps = {
			Name = name,
			label = label,
			onActivate = function()
				activate()
			end,
			Size = D2.fromOffset(0, 36),
		}
		if extras then
			for key, item in extras do
				spec[if type(key) == "number" then #spec + 1 else key] = item
			end
		end
		return UI.Button(spec)
	end
	local function measure(node: GuiObject, value: Value<Vector2>): GuiObject
		Compose.cleanup(observation.observeProperty(node, "AbsoluteSize", function()
			local size = observation.readProperty(node, "AbsoluteSize")
			if typeof(size) == "Vector2" and size.X > 0 and size.Y > 0 then
				value:set(size)
			end
		end))
		return node
	end
	local function observeSize(node: GuiObject): Value<Vector2>
		local value = Compose.cell(V2.new(screens.CANVAS.w, screens.CANVAS.h))
		measure(node, value)
		return value
	end
	local function collection(
		source: Value<number?>,
		build: (canvas: ((Use) -> Vector2)?) -> ScrollingFrame
	): ScrollingFrame
		local canvas = if source:peek() ~= nil
			then function(use: Use): Vector2
				use(model.mode)
				return V2.new(0, source:peek() or 0)
			end
			else nil
		local node = build(canvas)
		Compose.cleanup(observation.observeProperty(node, "CanvasPosition", function()
			if
				actions.spatial == nil
				or (actions.spatial and model.mode:peek() == "Spatial")
				or (not actions.spatial and model.mode:peek() == "Screen")
			then
				local position = observation.readProperty(node, "CanvasPosition")
				if typeof(position) == "Vector2" then
					source:set(position.Y)
				end
			end
		end))
		return node
	end
	local function stage(name: string, contentBuilder: StageContent?, extras: StageProps?): Child
		local spec: StageProps = {
			Name = name,
			Size = D2.fromScale(1, 1),
			BorderSizePixel = 0,
			camera = CF.lookAt(types.Vector3.new(-10, 8, -13), types.Vector3.new(0, 1, 0)),
			fieldOfView = 43,
			Ambient = C3.fromRGB(166, 173, 191),
			LightColor = C3.fromRGB(255, 235, 204),
			LightDirection = types.Vector3.new(-1, -1, -0.5),
			content = contentBuilder,
			rounded(),
		}
		if extras then
			for key, item in extras do
				spec[if type(key) == "number" then #spec + 1 else key] = item
			end
		end
		return Compose.boundary(function()
			return UI.Stage(spec)
		end, function()
			return UI.Text {
				Name = name .. "Unavailable",
				text = "Preview unavailable",
				textRole = "label",
				role = "secondary",
				Size = spec.Size,
				Position = spec.Position,
				AutomaticSize = E.AutomaticSize.None,
			}
		end)
	end
	local function panelShadow(): Frame
		return Facet.themes.skin(runtime, actions.theme, "monitorPanel", { types = types })
	end
	local function toastFor(app: string): Child
		local source: ReadOnlyValue<Toast?> = model.toasts[app]
		return Compose.keyed({
			from = function(use: Use): { Toast }
				local toast = use(source)
				return if toast then { toast } else {}
			end,
			key = function(toast: Toast): number
				return toast.serial
			end,
			render = function(current: ReadOnlyValue<Toast>): GuiObject
				local toast = current:peek()
				local undo = toast.undo
				local presented = Compose.formula(function(use: Use)
					local live = use(source)
					return live ~= nil and live.serial == toast.serial
				end)
				return UI.Toast(app .. "Toast")({
					isPresented = presented,
					onPresentedChange = function(value)
						if not value then
							model.dismissToast(app, toast.serial)
						end
					end,
					message = toast.message,
					duration = 5,
					action = if undo
						then {
							label = "Undo",
							onActivate = function()
								if undo then
									undo()
								end
								model.dismissToast(app, toast.serial)
							end,
						}
						else nil,
				})
			end,
		})
	end
	local function shell(
		name: string,
		build: (Value<Vector2>) -> (Child, Child?),
		collapsed: ReadOnlyValue<boolean>?
	): Frame
		local about = Compose.cell(false)
		local statusOpen = Compose.cell(false)
		local presentationKey = name .. (if actions.spatial then ":Spatial" else ":Screen")
		local presentation = { about = about, status = statusOpen }
		model.presentations[presentationKey] = presentation
		Compose.cleanup(function()
			if model.presentations[presentationKey] == presentation then
				model.presentations[presentationKey] = nil
			end
		end)
		local region = Compose.cell(V2.new(screens.CANVAS.w, screens.CANVAS.h))
		local function wide(use: Use): boolean
			return use(region).X >= 860
		end
		local function switchAppearance()
			model.dark:update(function(value)
				return not value
			end)
		end
		local chrome: StackProps = { Name = "Chrome", gap = "s", align = "center", Visible = wide }
		if actions.spatial then
			chrome[#chrome + 1] = button("Focus", function(use: Use)
				return if use(model.focused) == name then "All monitors" else "Focus"
			end, function()
				model.focus(name)
			end)
		end
		chrome[#chrome + 1] = button("Presentation", function(use: Use)
			return if use(model.mode) == "Spatial" then "Screen mode" else "Spatial mode"
		end, model.toggleMode)
		chrome[#chrome + 1] = button("Appearance", function(use: Use)
			return if use(model.dark) then "Light mode" else "Dark mode"
		end, switchAppearance)
		chrome[#chrome + 1] = button("About", "About", function()
			about:set(true)
		end)
		local player = actions.player
		local displayName = if player then player.DisplayName else "You"
		local profile: GuiObject = UI.Avatar "Profile" {
			name = displayName,
			userId = if player and player.UserId > 0 then player.UserId else nil,
			presence = model.presence,
			diameter = 44,
			onActivate = function()
				statusOpen:set(true)
			end,
		}
		local presenceWords: { [string]: string } = { online = "Online", away = "Away", busy = "Busy" }
		local menuShown = Compose.cell(false)
		local presentation: MenuCommand = {
			id = "Presentation",
			label = "Switch presentation",
			onSelect = model.toggleMode,
		}
		local appearance: MenuCommand = { id = "Appearance", label = "Switch appearance", onSelect = switchAppearance }
		local aboutItem: MenuCommand = {
			id = "About",
			label = "About",
			onSelect = function()
				about:set(true)
			end,
		}
		local menuItems: { MenuItem } = { presentation, appearance, aboutItem }
		if actions.spatial then
			local focusItem: MenuCommand = {
				id = "Focus",
				label = function(use: Use)
					return if use(model.focused) == name then "All monitors" else "Focus"
				end,
				onSelect = function()
					model.focus(name)
				end,
			}
			table.insert(menuItems, focusItem)
		end
		local presenceOptions: { PickerOption } = {
			{ value = "online", label = "Online" },
			{ value = "away", label = "Away" },
			{ value = "busy", label = "Busy" },
		}
		local aboutActions: { DialogAction } = {
			{
				id = "done",
				label = "Done",
				role = "cancel",
				onActivate = function()
					about:set(false)
				end,
			},
		}
		local function actionsMenu(): GuiObject
			local spec: MenuSpec = {
				trigger = UI.Button "ActionsMenu" {
					icon = "more",
					name = "Menu",
					shape = "circle",
					appearance = "utility",
				},
				Visible = function(use: Use): boolean
					return not wide(use)
				end,
				onOpen = function()
					menuShown:set(true)
				end,
				onClose = function()
					menuShown:set(false)
				end,
				items = menuItems,
			}
			return UI.Menu(spec)
		end
		local root = UI.ZStack(name)({
			width = "fill",
			height = "fill",
			SelectionGroup = true,
			ClipsDescendants = true,
			UI.Screen "Page" {
				gap = "s",
				padding = { top = "s", right = "m", bottom = "m", left = "m" },
				UI.NavBar "Header" {
					title = if name == "Chat" then "Assistant" elseif name == "Flap" then "Facet Flap" else name,
					titleSize = "heading",
					Visible = function(use: Use)
						return actions.spatial == true or use(menuShown) or not (collapsed and use(collapsed))
					end,
					trailing = UI.AdaptiveStack "HeaderActions" {
						axis = "x",
						gap = "s",
						align = "center",
						UI.ViewThatFits "ChromeFit" { width = "hug", UI.HStack(chrome) },
						actionsMenu(),
						profile,
					},
				},
				Host.Frame "Content" {
					BackgroundTransparency = 1,
					Size = D2.fromScale(1, 0),
					Interactable = function(use: Use)
						return not actions.spatial or use(model.focused) == name
					end,
					UI.fill(),
					UI.ErrorBoundary "AppBoundary" {
						width = "fill",
						height = "fill",
						view = function()
							local body, extra = build(region)
							return UI.ZStack "AppContent" {
								width = "fill",
								height = "fill",
								body,
								extra,
							}
						end,
						fallback = function(failure, retry)
							warn(`{name} stopped: {failure}`)
							return UI.VStack "AppFailure" {
								width = "fill",
								gap = "s",
								padding = "l",
								words(
									"FailureTitle",
									`{if name == "Chat" then "Assistant" else name} stopped`,
									"heading"
								),
								quiet(
									"FailureMessage",
									"Something in this app failed. Your saved games, notes and messages are safe.",
									"label"
								),
								button("Retry", "Try again", retry),
							}
						end,
					},
				},
			},
			button("WakeMonitor", "", function()
				model.focus(name)
			end, {
				Size = D2.fromScale(1, 1),
				BackgroundTransparency = 1,
				TextTransparency = 1,
				ZIndex = 100,
				AutomaticSize = E.AutomaticSize.None,
				Visible = function(use: Use)
					return actions.spatial == true and use(model.focused) ~= name
				end,
			}),
			UI.Popover "StatusPopover" {
				title = "Status",
				source = { node = profile },
				isPresented = statusOpen,
				onPresentedChange = function(value)
					statusOpen:set(value)
				end,
				edge = "bottom",
				align = "end",
				maxWidth = 280,
				content = function(): Instance
					local presenceProps: MonitorPresencePickerSpec = {
						selected = model.presence,
						onChange = function()
							statusOpen:set(false)
						end,
						style = "radioGroup",
						options = presenceOptions,
					}
					return UI.VStack "PresenceCard" {
						width = "fill",
						gap = "s",
						UI.HStack "Identity" {
							gap = "s",
							align = "center",
							UI.StatusIndicator "PresenceDot" {
								status = function(use: Use): "success" | "warning" | "error"
									local presence = use(model.presence)
									return if presence == "online"
										then "success"
										elseif presence == "away" then "warning"
										else "error"
								end,
								name = function(use: Use)
									return presenceWords[use(model.presence) or ""] or ""
								end,
							},
							UI.Text "DisplayName" {
								text = "Signed in as <b>" .. Facet.richText.escape(displayName) .. "</b>",
								rich = true,
							},
						},
						UI.Picker "Presence"(presenceProps),
					}
				end,
			},
			UI.Dialog "AboutDialog" {
				isPresented = about,
				onPresentedChange = function(value)
					about:set(value)
				end,
				title = "About Virtual Monitors",
				content = function(): Instance
					return UI.VStack "AboutCopy" {
						width = "fill",
						gap = "s",
						stage("AboutScene", actions.discoveryContent, { Size = D2.new(1, 0, 0, 150) }),
						words(
							"AboutMessage",
							"Four apps, shared between a spatial desktop and a flat screen. Compose owns every scene and lifetime; Facet supplies controls; Roblox supplies layout and rendering."
						),
						quiet(
							"AboutVersion",
							`Facet {Facet.VERSION} · Compose {string.sub(Facet.COMPOSE_COMMIT, 1, 7)}`,
							"caption"
						),
					}
				end,
				actions = aboutActions,
			},
		})
		root:AddTag("facet-surface")
		measure(root, region)
		return root
	end
	local function saveAction(current: ReadOnlyValue<Game?>): CardAction
		return {
			label = function(use: Use)
				return if use(model.saved)[assert(use(current)).id] then "Saved" else "Save"
			end,
			icon = function(use: Use)
				return if use(model.saved)[assert(use(current)).id] then "checkmark" else "increment"
			end,
			onActivate = function()
				model.save(assert(current:peek()))
			end,
		}
	end
	local function gameMenu(current: ReadOnlyValue<Game>): CardMenu
		local share: MenuCommand = {
			id = "Share",
			label = "Share",
			onSelect = function()
				model.notify("Discover", `Link to {current:peek().title} copied`)
			end,
		}
		local hide: MenuCommand = {
			id = "Hide",
			label = "Not interested",
			onSelect = function()
				model.hide(current:peek())
			end,
		}
		local report: MenuCommand = {
			id = "Report",
			label = "Report",
			role = "destructive",
			onSelect = function()
				model.notify("Discover", `Thanks. We will review {current:peek().title}.`)
			end,
		}
		local divider: { divider: true, id: string? } = { divider = true }
		local items: { MenuItem } = { share, hide, divider, report }
		return { items = items }
	end
	local function gameCard(current: ReadOnlyValue<Game>, placement: ReadOnlyValue<CollectionPlacement>): GuiObject
		local item = current:peek()
		local card: Frame
		local preview: Frame
		local function openCard()
			selectedCard:set(card)
			model.selectGame(current:peek())
		end
		card = UI.Card("Game_" .. item.id)({
			title = function(use: Use)
				return use(current).title
			end,
			caption = function(use: Use)
				local game = use(current)
				return game.rating .. "  ·  " .. game.players
			end,
			artwork = function()
				local decorated = runtime.timeline({ duration = (1 + item.index % 3) / 60 }).completed
				preview = UI.ZStack "Preview" {
					width = "fill",
					height = "fill",
					ClipsDescendants = true,
					rounded(),
					stage("Scene", if actions.gameContent then actions.gameContent(current) else nil, {
						Active = false,
						lazy = true,
					}),
					Compose.show(decorated, function()
						return UI.StatusIndicator "LiveDot" {
							status = "success",
							name = "Live now",
							AnchorPoint = V2.new(0, 0),
							Position = D2.fromOffset(10, 10),
						}
					end),
					Compose.show(function(use: Use)
						return use(decorated) and #use(current).friends > 0
					end, function()
						return UI.AvatarGroup "Friends" {
							items = function(use: Use)
								return use(current).friends
							end,
							max = 3,
							layout = "stacked",
							diameter = 28,
							Position = D2.new(1, -10, 1, -10),
							AnchorPoint = V2.new(1, 1),
						}
					end),
				}

				UI.draggable(preview, {
					payload = function()
						return current:peek()
					end,
				})
				return preview
			end,
			onActivate = openCard,
			primaryAction = saveAction(current),
			menu = gameMenu(current),
		})
		model.catalog.seen(placement:peek().index, #model.visibleGames:peek())
		return card
	end
	local launchSteps = {
		{ id = "find", label = "Find server" },
		{ id = "load", label = "Load world" },
		{ id = "join", label = "Join" },
	}
	local function detailContent(current: ReadOnlyValue<Game?>): GuiObject
		local selected = current:peek()
		if not selected then
			return Host.Frame { BackgroundTransparency = 1 }
		end
		local joinFriends: MenuCommand = {
			id = "Friends",
			label = if #selected.friends > 0 then `Join friends ({#selected.friends})` else "Join friends",
			enabled = #selected.friends > 0,
			onSelect = function()
				model.launchGame(selected.id, "Joining your friends")
			end,
		}
		local privateServer: MenuCommand = {
			id = "Private",
			label = "Start a private server",
			onSelect = function()
				model.launchGame(selected.id, "Starting a private server")
			end,
		}
		local playItems: { MenuItem } = { joinFriends, privateServer }
		local sectionOptions: { PickerOption } = {
			{ value = "about", label = "About" },
			{ value = "similar", label = "Similar games" },
		}
		local ratingPresented = Compose.cell(false)
		local ratingAnchor = button("AboutRating", selected.rating .. " recommend this game", function()
			ratingPresented:set(true)
		end, { Size = D2.new(1, 0, 0, 36), AutomaticSize = E.AutomaticSize.None })
		local function sparkline()
			local points: { PathPoint } = {}
			for day = 0, 6 do
				local wobble = ((selected.index * (day + 1) * 37) % 23) / 23
				table.insert(
					points,
					{ x = day / 6, y = 1 - (0.25 + 0.5 * wobble), inX = 0, inY = 0, outX = 0, outY = 0 }
				)
			end
			return UI.HStack "Sparkline" {
				width = "fill",
				gap = "s",
				align = "center",
				UI.Path "TrendLine" {
					points = points,
					role = "accent",
					thickness = 3,
					Size = D2.new(1, -52, 0, 40),
				},
				UI.Path "RatingArc" {
					points = Facet.pathShapes.arc(0, selected.percent * 3.6, { radius = 0.8 }),
					role = "secondary",
					thickness = 4,
					width = 40,
				},
			}
		end
		local tab = function(use: Use)
			return use(model.detailTab)
		end
		local function launching(use: Use)
			local launch = use(model.launch)
			return if launch and launch.id == selected.id then launch else nil
		end
		local similar: { Game } = {}
		for _, candidate in model.catalog.items:peek() do
			if candidate.genre == selected.genre and candidate.id ~= selected.id then
				table.insert(similar, candidate)
			end
		end
		local perPage = 6
		local sectionProps: StringPickerSpec = {
			selected = model.detailTab,
			onChange = function(value)
				model.detailTab:set(value)
			end,
			style = "segmented",
			sizing = "hug",
			Size = D2.fromOffset(0, 44),
			AutomaticSize = E.AutomaticSize.X,
			options = sectionOptions,
		}
		local pageCount = math.max(1, math.ceil(#similar / perPage))
		return UI.VStack "GameDetails" {
			width = "fill",
			gap = "s",
			stage(
				"DetailScene",
				if actions.gameContent then actions.gameContent(Compose.cell(selected)) else nil,
				{ Size = D2.new(1, 0, 0, 180) }
			),
			UI.HStack "PlayRow" {
				width = "fill",
				gap = "s",
				align = "center",
				UI.SplitButton "Play" {
					label = "Play",
					menuLabel = "More ways to play",
					onActivate = function()
						model.launchGame(selected.id, "Joining a public server")
					end,
					items = playItems,
				},
				quiet("LaunchStatus", function(use: Use)
					local launch = launching(use)
					return if launch == nil
						then ""
						elseif launch.stage > 3 then "Joined (simulated)"
						else `{launch.mode}… (simulated)`
				end, "label", { Size = D2.fromOffset(0, 0), TextWrapped = false, UI.fill() }),
			},
			Compose.show(function(use: Use)
				return launching(use) ~= nil
			end, function()
				return UI.StepIndicator "LaunchSteps" {
					steps = function(use: Use): { Step }
						local stage = assert(launching(use)).stage
						local steps: { Step } = {}
						for index, step in launchSteps do
							local entry: Step = {
								id = step.id,
								label = step.label,
								state = if index < stage
									then "complete"
									elseif index == stage then "current"
									else "upcoming",
							}
							table.insert(steps, entry)
						end
						return steps
					end,
					current = function(use: Use)
						local launch = launching(use)
						return if launch and launch.stage <= 3 then launchSteps[launch.stage].id else nil
					end,
					listLabel = "Launch steps",
				}
			end),
			UI.DateTimePicker "Session" {
				label = "Play session",
				time = true,
				minuteStep = 15,
				clock = clock,
				min = civil.dateOf(clock()),
				placeholder = "Not scheduled",
				value = function(use: Use)
					return use(model.sessions)[selected.id]
				end,
				onChange = function(date)
					model.schedule(selected.id, date)
				end,
				hint = function(use: Use)
					local session = use(model.sessions)[selected.id]
					return if session
						then `Friends see {civil.format(session)} at {civil.formatTime(session, 12)}.`
						else "Pick a time to play with friends."
				end,
			},
			words("Description", selected.description),
			UI.Divider "CreatorRule" {},
			UI.HStack "Creator" {
				width = "fill",
				gap = "s",
				align = "center",
				UI.AsyncImage "CreatorAvatar" {
					source = selected.creatorImage,
					loader = actions.creatorImageLoader,
					Size = D2.fromOffset(40, 40),
					placeholder = function()
						return UI.Skeleton "CreatorShimmer" {
							form = "circle",
							Size = D2.fromOffset(40, 40),
							AutomaticSize = E.AutomaticSize.None,
						}
					end,
				},
				UI.Text "CreatorName" { text = selected.creator, textRole = "label" },
				UI.Spacer {},
			},
			UI.HStack "DetailsTabs" {
				width = "fill",
				gap = "s",
				UI.Picker "DetailSection"(sectionProps),
				UI.Spacer "TabsGap" { minLength = "s" },
				button("SaveDetail", saveAction(current).label, function()
					model.save(assert(current:peek()))
				end),
			},
			Compose.show(function(use: Use)
				return tab(use) == "about"
			end, function()
				local ratingProps: RatingProps = {
					value = function(use: Use)
						return use(model.ratings)[selected.id] or selected.stars
					end,
					count = 5,
					allowZero = false,
					onChange = function(value)
						model.rate(selected.id, value)
					end,
					Size = D2.new(1, 0, 0, 44),
					AutomaticSize = E.AutomaticSize.None,
				}
				return UI.VStack "AboutGame" {
					width = "fill",
					gap = "s",
					ratingAnchor,
					Compose.show(ratingPresented, function()
						return UI.Callout "RatingPopover" {
							priority = 10,
							anchor = ratingAnchor,
							isPresented = ratingPresented,
							content = function(): Instance
								return words(
									"RatingMeaning",
									"The rating is the share of players who would recommend this game to a friend.",
									"label"
								)
							end,
							onRetire = function()
								ratingPresented:set(false)
							end,
						}
					end),
					UI.Label "TrendHeading" { title = "Players this week", icon = "person", textSize = "label" },
					sparkline(),
					quiet("Rating", selected.rating .. " recommend this game · " .. selected.players, "label"),
					words("YourRating", "Your rating", "label"),
					UI.Rating "Stars"(ratingProps),
					quiet(
						"RatingExplanation",
						"The rating is the share of players who would recommend this game to a friend."
					),
				}
			end),
			Compose.show(function(use: Use)
				return tab(use) == "similar"
			end, function()
				local function similarRow(candidate: Game): Frame
					local trailing: { RowAction } = {
						{
							id = "SaveSimilar",
							label = "Save",
							onActivate = function()
								model.save(candidate)
							end,
						},
					}
					return UI.RowActions {
						Name = "SimilarRow_" .. candidate.id,
						Size = D2.new(1, 0, 0, 42),
						content = function(): GuiObject
							return button(
								"Similar_" .. candidate.id,
								candidate.title .. "  ·  " .. candidate.rating,
								function()
									model.selectGame(candidate)
								end,
								{ Size = D2.fromScale(1, 1), AutomaticSize = E.AutomaticSize.None }
							)
						end,
						trailing = trailing,
					}
				end
				return UI.VStack "SimilarGames" {
					width = "fill",
					gap = "s",
					Compose.switch(function(use: Use)
						return math.clamp(use(model.similarPage), 1, pageCount)
					end, {}, function()
						local page = math.clamp(model.similarPage:peek(), 1, pageCount)
						local rows: StackProps = { Name = "SimilarPage", width = "fill", gap = "s" }
						for index = (page - 1) * perPage + 1, math.min(#similar, page * perPage) do
							rows[#rows + 1] = similarRow(similar[index])
						end
						return UI.VStack(rows)
					end),
					Compose.show(function()
						return pageCount > 1
					end, function()
						return UI.Pagination "SimilarPages" {
							page = model.similarPage,
							pageCount = pageCount,
							onChange = function(page)
								model.similarPage:set(page)
							end,
						}
					end),
				}
			end),
		}
	end
	local function draggedGame(payload: unknown): Game?
		for _, item in model.catalog.items:peek() do
			if item == payload then
				return item
			end
		end
		return nil
	end
	local function discoverContent(region: Value<Vector2>, collapsed: Value<boolean>): (Frame, Frame)
		local dimensions = Compose.cell(V2.new(screens.CANVAS.w, screens.CANVAS.h))
		local function short(use: Use)
			return use(region).Y < screens.SHORT_HEIGHT
		end
		local function compact(use: Use)
			return use(dimensions).X < (if short(use) then 480 else 620)
		end
		Compose.watch(function(use: Use)
			local offset = use(model.discoveryScroll) or 0
			local browsing = short(use) and use(model.shelf) == "browse"
			if not browsing or offset < 8 then
				collapsed:set(false)
			elseif offset > 48 then
				collapsed:set(true)
			end
		end)
		local function featured(use: Use)
			return not compact(use) and use(dimensions).Y >= 682 and use(model.shelf) == "browse"
		end
		local genreOptions: { { value: string, label: string } } = { { value = "all", label = "All" } }
		for _, name in require("./catalog").genres do
			table.insert(genreOptions, { value = name, label = name })
		end
		local body: Frame
		local focusSearch = Host.InputAction "FocusSearch" {
			Type = E.InputActionType.Bool,
			Enabled = function(use: Use)
				return if actions.spatial then use(model.mode) == "Spatial" else use(model.mode) == "Screen"
			end,
			Released = function()
				local editor = body:FindFirstChild("Editor", true)
				if editor and editor:IsA("TextBox") then
					(editor :: TextBox):CaptureFocus()
				end
			end,
			Host.InputBinding { KeyCode = E.KeyCode.Slash },
		}
		local chips: ScrollViewProps = {
			Name = "Genres",
			axis = "x",
			gap = "s",
			ScrollBarThickness = 2,
			Visible = function(use: Use)
				return not use(collapsed)
			end,
		}
		for _, option in genreOptions do
			local value = option.value
			local chipProps: ChipRequestProps = {
				Name = "Genre_" .. value,
				label = option.label,
				selected = function(use: Use)
					return use(model.genre) == value
				end,
				onToggle = function()
					model.genre:set(value)
				end,
			}
			chips[#chips + 1] = UI.Chip(chipProps)
		end
		local savedShelf = button("Saved", "Saved", function()
			model.shelf:set("saved")
		end, {
			selected = function(use: Use)
				return use(model.shelf) == "saved"
			end,
		})
		local shelves = UI.HStack "Shelves" {
			width = function(use: Use): "hug" | "fill"
				return if short(use) and not compact(use) then "hug" else "fill"
			end,
			gap = "s",
			align = "center",
			button("Browse", "Browse", function()
				model.shelf:set("browse")
			end, {
				selected = function(use: Use)
					return use(model.shelf) == "browse"
				end,
			}),
			UI.badged(savedShelf, function(use: Use)
				return #use(model.savedGames)
			end),
			UI.Text "Count" {
				text = function(use: Use)
					return `{#use(model.savedGames)} saved`
				end,
				textRole = "caption",
				role = "secondary",
				TextXAlignment = E.TextXAlignment.Right,
				Visible = function(use: Use)
					return not short(use) and use(model.shelf) == "saved"
				end,
				UI.fill(),
			},
		}
		UI.dropTarget(shelves, {
			accepts = function(payload: unknown): (boolean, string?)
				local game = draggedGame(payload)
				return game ~= nil and not model.saved:peek()[game.id], nil
			end,
			onDrop = function(payload: unknown)
				local game = draggedGame(payload)
				if game then
					model.save(game)
				end
			end,
		})
		local sortOptions: { PickerOption } = {
			{ value = "recommended", label = "Recommended" },
			{ value = "rating", label = "Top rated" },
			{ value = "playing", label = "Most playing" },
		}
		local detailActions: { AlertAction } = {
			{ id = "close", label = "Done", role = "cancel" },
		}
		local lastTitle = ""
		local detailTitle = Compose.formula(function(use: Use): string
			local selected = use(model.selectedGame)
			if selected then
				lastTitle = selected.title
			end
			return lastTitle
		end)
		local function feedFrame(child: Instance): Frame
			return Host.Frame "Feed" {
				BackgroundTransparency = 1,
				Size = D2.fromScale(1, 0),
				UI.fill(),
				child,
			}
		end
		local sortProps: StringPickerSpec = {
			selected = model.sort,
			onChange = function(value)
				model.sort:set(value)
			end,
			options = sortOptions,
			style = "menu",
			Size = function(use: Use)
				return if compact(use) then D2.new(1, 0, 0, 44) else D2.fromOffset(if short(use) then 150 else 180, 44)
			end,
			AutomaticSize = E.AutomaticSize.None,
		}
		local shortcutProps: ShortcutHintActionProps = {
			action = focusSearch,
			Visible = function(use: Use)
				return not compact(use) and not use(touchEnabled)
			end,
		}
		body = UI.VStack "DiscoverBody" {
			width = "fill",
			height = "fill",
			gap = "s",
			Host.InputContext "DiscoverShortcuts" { focusSearch },
			UI.HStack "SearchControls" {
				width = "fill",
				gap = "s",
				align = "center",
				wrap = true,
				UI.ComboBox "Search" {
					value = model.searchSelection,
					text = model.query,
					acceptCustom = function()
						return true, nil
					end,
					options = function(use: Use): { StringPickerOption }
						local query, choices: { StringPickerOption } = use(model.query):lower(), {}
						if query ~= "" then
							for _, item in use(model.catalog.items) do
								if item.title:lower():find(query, 1, true) then
									table.insert(choices, { value = item.id, label = item.title })
									if #choices == 8 then
										break
									end
								end
							end
						end
						return choices
					end,
					onChange = function(id)
						for _, item in model.catalog.items:peek() do
							if item.id == id then
								model.selectGame(item)
								break
							end
						end
					end,
					placeholder = "Search games",
					Size = function(use: Use)
						return if compact(use) then D2.new(1, 0, 0, 44) else D2.fromOffset(0, 44)
					end,
					AutomaticSize = E.AutomaticSize.None,
					Host.UIFlexItem {
						FlexMode = function(use: Use)
							return if compact(use) then E.UIFlexMode.None else E.UIFlexMode.Fill
						end,
					},
				},
				UI.ShortcutHint "SearchShortcut"(shortcutProps),
				UI.Picker "Sort"(sortProps),
				shelves,
			},
			UI.ScrollView(chips),
			Compose.show(featured, function()
				local pages: { Tab } = {}
				for index = 1, 3 do
					local item = model.catalog.items:peek()[index]
					table.insert(pages, {
						id = item.id,
						label = item.title,
						content = function(): Instance
							local card: TextButton
							card = button("ExploreFeatured_" .. item.id, "", function()
								selectedCard:set(card)
								model.selectGame(item)
							end, {
								Size = D2.fromScale(1, 1),
								AutomaticSize = E.AutomaticSize.None,
								stage(
									"FeaturedScene",
									if item.index == 1
										then actions.discoveryContent
										elseif actions.gameContent then actions.gameContent(Compose.cell(item))
										else nil,
									{ Position = D2.fromOffset(12, 12), Size = D2.new(0.42, -18, 1, -24) }
								),
								UI.VStack "FeaturedCopy" {
									gap = "xs",
									Position = D2.new(0.42, 8, 0, 18),
									Size = D2.new(0.58, -28, 0, 0),
									AutomaticSize = E.AutomaticSize.Y,
									Host.UISizeConstraint { MaxSize = V2.new(520, 1000000) },
									quiet("FeaturedGenre", item.genre),
									words("FeaturedTitle", item.title, "heading"),
									quiet("FeaturedDescription", item.description, "body"),
									quiet("FeaturedFacts", item.rating .. " recommend  ·  " .. item.players),
									UI.HStack "FeaturedCreator" {
										gap = "xs",
										align = "center",
										UI.Image "FeaturedCreatorImage" {
											image = item.creatorImage,
											shape = "circle",
											scaleMode = "crop",
											Size = D2.fromOffset(24, 24),
										},
										quiet("FeaturedCreatorName", item.creator, "label", {
											Size = D2.fromOffset(0, 0),
											AutomaticSize = E.AutomaticSize.XY,
											TextWrapped = false,
										}),
									},
								},
								UI.Badge "FeaturedBadge" {
									label = "Featured",
									AnchorPoint = V2.new(1, 0),
									Position = D2.new(1, -12, 0, 8),
								},
							})
							card:AddTag("facet-panel")
							return card
						end,
					})
				end
				return UI.PageView "Featured" {
					pages = pages,
					selection = model.featuredSelection,
					summary = false,
					controls = false,
					Size = D2.new(1, 0, 0, 284),
				}
			end),
			Compose.show(function(use: Use)
				return use(model.shelf) == "browse" and #use(model.visibleGames) == 0
			end, function()
				local noResultActions: { OverlayAction } = {
					{
						id = "ClearFilters",
						label = "Clear filters",
						onActivate = function()
							model.genre:set("all")
							model.query:set("")
							model.searchSelection:set("")
						end,
					},
				}
				return UI.Notice "NoResults" {
					title = "No games match",
					message = "Try another genre or a shorter search.",
					actions = noResultActions,
				}
			end),
			Compose.show(function(use: Use)
				return use(model.shelf) == "saved" and #use(model.savedGames) == 0
			end, function()
				return UI.VStack "Empty" {
					width = "fill",
					gap = "xs",
					padding = "m",
					words("EmptyTitle", "Nothing saved yet", "heading"),
					quiet("EmptyMessage", "Save a game from its page, or drag a card onto Saved.", "label"),
				}
			end),
			Compose.show(function(use: Use)
				return use(model.shelf) == "browse"
			end, function()
				return feedFrame(collection(model.discoveryScroll, function(canvas)
					local gridProps = {
						scrollReset = function(use: Use)
							return use(model.sort) .. "\0" .. use(model.genre) .. "\0" .. use(model.query)
						end,
						from = model.visibleGames,
						key = "id",
						columns = function(use: Use)
							return math.max(1, math.floor((use(dimensions).X + 16) / 280))
						end,
						itemSize = 250,
						measure = true,
						gap = 16,
						overscan = 2,
						render = gameCard,
						Size = D2.fromScale(1, 1),
						BackgroundTransparency = 1,
						ScrollBarThickness = 5,
						CanvasPosition = canvas,
					}
					return UI.VirtualGrid "Games"(gridProps)
				end))
			end),
			Compose.show(function(use: Use)
				return use(model.shelf) == "saved" and #use(model.savedGames) > 0
			end, function()
				local savedColumns: { TableColumn } = {
					{
						id = "title",
						label = "Game",
						minWidth = 140,
						value = function(item)
							return item.title
						end,
					},
					{
						id = "genre",
						label = "Genre",
						width = 120,
						value = function(item)
							return item.genre
						end,
					},
					{
						id = "session",
						label = "Session",
						width = 120,
						value = function(item: Game)
							local session = model.sessions:peek()[item.id]
							return if session then civil.format(session) else "—"
						end,
					},
					{
						id = "rating",
						label = "Rating",
						width = 80,
						value = function(item)
							return item.rating
						end,
					},
					{
						id = "note",
						label = "Note",
						width = 160,
						sortable = false,
						priority = "always",
						render = function(current): GuiObject
							local id = current:peek().id
							local draft = Compose.cell(model.notes:peek()[id] or "")
							local noteProps: TextInputCellProps = {
								Name = "Note_" .. id,
								value = draft,
								placeholder = "Add a note",
								Size = D2.new(1, 0, 1, -12),
								AutomaticSize = E.AutomaticSize.None,
								onCommit = function(value)
									model.setNote(id, value)
								end,
								onCancel = function()
									draft:set(model.notes:peek()[id] or "")
								end,
							}
							return UI.TextInput(noteProps)
						end,
					},
				}
				local savedTable = UI.Table "SavedGames" {
					from = model.savedGames,
					key = "id",
					selection = model.savedSelection,
					selectionMode = "single",
					sort = model.savedSort,
					widths = model.savedWidths,
					itemSize = 60,
					reorderable = true,
					onReorder = model.reorderSaved,
					dragLabel = function(item: Game)
						return item.title
					end,
					onActivate = function(item: Game)
						model.shelf:set("browse")
						model.selectGame(item)
					end,
					Size = D2.fromScale(1, 1),
					columns = savedColumns,
				}
				return feedFrame(savedTable)
			end),
		}
		measure(body, dimensions)
		local gameDetail = UI.Alert "GameDetail" {
			surface = "fullScreen",
			transition = { source = selectedCard, seconds = 0.32, ease = Compose.easing.outCubic },
			item = model.selectedGame,
			title = detailTitle,
			content = function(payload): Instance
				local presentedGame = Compose.cell(payload)
				Compose.watch(function(use: Use)
					local selected = use(model.selectedGame)
					if selected then
						presentedGame:set(selected)
					end
				end)
				return Host.Frame "DetailSelection" {
					BackgroundTransparency = 1,
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
					Compose.keyed({
						from = function(use: Use): { Game }
							return { use(presentedGame) }
						end,
						key = function(item: Game): string
							return item.id
						end,
						render = detailContent,
					}),
				}
			end,
			actions = detailActions,
		}
		return body,
			UI.ZStack "Overlays" {
				width = "fill",
				height = "fill",
				gameDetail,
				toastFor("Discover"),
			}
	end
	local ctx: Context = {
		Facet = Facet,
		Compose = Compose,
		Host = Host,
		UI = UI,
		runtime = runtime,
		model = model,
		types = types,
		D = D,
		D2 = D2,
		V2 = V2,
		C3 = C3,
		CF = CF,
		E = E,
		words = words,
		quiet = quiet,
		button = button,
		stage = stage,
		observeSize = observeSize,
		measure = measure,
		collection = collection,
		actions = actions,
		rounded = rounded,
		panelShadow = panelShadow,
		toastFor = toastFor,
	}
	local function Discover(): Frame
		local collapsed = Compose.cell(false)
		return shell("Discover", function(region)
			return discoverContent(region, collapsed)
		end, collapsed)
	end
	local function Avatar(): Frame
		return shell("Avatar", function()
			return require("./avatar")(ctx)
		end)
	end
	local function Chat(): Frame
		return shell("Chat", function()
			return require("./chat")(ctx)
		end)
	end
	local function Flap(): Frame
		return shell("Flap", function()
			return require("./flap")(ctx), nil
		end)
	end
	local views: { [string]: () -> Instance } = { Discover = Discover, Avatar = Avatar, Chat = Chat, Flap = Flap }
	return views
end

return screens
