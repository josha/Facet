--!strict
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T

local widgets = require("./widgets")
local gallery = require("./gallery")
local layerOutline = require("./layer_outline")

local shell = {}

function shell.mount(Facet: any, parent: Instance, model: any, actions: any, options: any): any
	local runtime: typeof(require("@repo/src/vendor/compose/roblox").createRuntime(nil :: any)) =
		Facet.Roblox.createRuntime()
	local Host, Compose: typeof(require("@repo/src/vendor/compose/core")) =
		(runtime.constructors :: unknown) :: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host),
		Facet.Compose
	local kit: any
	local canvas: Frame?, codeBox: TextBox?
	local stop, mounted = runtime.mount(function(): Frame
		kit = widgets.new(Facet, runtime, model, options)
		local sheet = kit.sheet()
		local function contentTop(use)
			return if use(model).compact then 192 else 122
		end
		local function contentPosition(use)
			return UDim2.fromOffset(if use(model).compact then 0 else 224, contentTop(use))
		end
		local function contentSize(use)
			return UDim2.new(1, if use(model).compact then 0 else -496, 1, -contentTop(use) - 32)
		end
		local function paneVisible(name)
			return function(use: Use)
				local state = use(model)
				return not state.compact or state.pane == name
			end
		end
		local inspector = Host.ScrollingFrame "Inspector" {
			AnchorPoint = Vector2.new(1, 0),
			Position = function(use: Use)
				return UDim2.new(1, 0, 0, contentTop(use))
			end,
			Size = function(use: Use)
				return UDim2.new(
					if use(model).compact then 1 else 0,
					if use(model).compact then 0 else 272,
					1,
					-contentTop(use) - 32
				)
			end,
			Visible = paneVisible("Inspector"),
			BackgroundColor3 = Color3.fromRGB(248, 250, 254),
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 3,
			kit.padding(16) :: unknown,
			Host.UIListLayout { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder },
			kit.text("InspectorHeading", function(use: Use)
				return tostring(use(model).selectedKind) .. "  /  PROPERTIES"
			end, 11, 28),
			Compose.keyed({
				from = function(use: Use)
					return use(model).fields
				end,
				key = function(field)
					return field.id
				end,
				render = function(current, index)
					local field = current:peek()
					local control
					if field.kind == "color" then
						control = kit.UI.ColorPicker("Property_" .. field.key) {
							value = function(use: Use)
								local value = use(current).value
								return if value then Color3.fromHex(value) else nil
							end,
							onChange = function(value)
								actions.property(field.key, if value then "#" .. value:ToHex():upper() else nil)
							end,
							label = "Color",
							allowEmpty = true,
							placeholder = "Theme default",
							draft = true,
							Size = UDim2.new(1, -10, 0, 44),
						}
					elseif field.kind == "padding" then
						local sides = {}
						for index, side in { "top", "right", "bottom", "left" } do
							local label = kit.text("SideLabel", string.upper(string.sub(side, 1, 1)), 11, 18)
							local input = kit.input("Padding_" .. side, function(use: Use)
								local value = use(current).value
								return tostring(if type(value) == "table" then value[side] or 0 else value or 0)
							end, function(text)
								local value = current:peek().value
								local proposed = if type(value) == "table"
									then table.clone(value)
									else {
										top = value or 0,
										right = value or 0,
										bottom = value or 0,
										left = value or 0,
									}
								proposed[side] = tonumber(text) or text
								actions.property(field.key, proposed)
							end, UDim2.new(1, 0, 0, 32))
							table.insert(
								sides,
								Host.Frame("PaddingSide_" .. side) {
									Size = UDim2.new(0.25, -5, 0, 66),
									BackgroundTransparency = 1,
									LayoutOrder = index,
									Host.UIListLayout { SortOrder = Enum.SortOrder.LayoutOrder } :: unknown,
									label,
									input,
								}
							)
						end
						control = kit.row("PaddingSides", sides, 66)
					elseif field.kind == "json" then
						control = kit.button("EditData_" .. field.key, "Edit " .. field.label, 238, function()
							actions.editStructured(field.key)
						end)
					elseif field.kind == "boolean" then
						control = kit.button(
							"Property_" .. field.key,
							function(use: Use)
								local value = use(current).value
								return if value == nil then "Default" elseif value == true then "On" else "Off"
							end,
							-1,
							function()
								actions.property(field.key, not current:peek().value)
							end
						)
					elseif field.kind == "choice" then
						control = kit.button(
							"ChoiceProperty_" .. field.key,
							function(use: Use)
								return tostring(use(current).value or "Default") .. "  ▾"
							end,
							-1,
							function()
								actions.chooseProperty(field.key, field.options)
							end
						)
					else
						control = kit.input("Property_" .. field.key, function(use: Use)
							return tostring(use(current).value or "")
						end, function(value)
							actions.property(field.key, value)
						end)
					end
					local reset = kit.button("Reset_" .. field.key, "Reset", 54, function()
						actions.property(field.key, nil)
					end)
					runtime.decorate(reset, {
						Visible = function(use: Use)
							return field.key ~= "name" and use(current).explicit == true
						end,
					})
					local label = kit.text("FieldLabel", field.label, 11, 21)
					runtime.decorate(label, { Size = UDim2.new(1, -60, 0, 24) })
					local heading = kit.row("PropertyHeading", { label, reset }, 24)
					runtime.decorate(heading, { LayoutOrder = 1 })
					runtime.decorate(control, { LayoutOrder = 2 })
					return Host.Frame "PropertyField" {
						LayoutOrder = function(use: Use)
							return (use(index) :: number) + 1
						end,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,
						Host.UIListLayout { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder } :: unknown,
						heading,
						control,
					}
				end,
			}),
		}
		local sidebar = kit.UI.VStack "DesignOutline" {
			width = "fill" :: "fill",
			height = "fill" :: "fill",
			padding = 12,
			gap = 8,
			Position = function(use: Use)
				return UDim2.fromOffset(0, contentTop(use))
			end,
			Size = function(use: Use)
				return UDim2.new(
					if use(model).compact then 1 else 0,
					if use(model).compact then 0 else 224,
					1,
					-contentTop(use) - 32
				)
			end,
			Visible = paneVisible("Layers"),
			BackgroundColor3 = Color3.fromRGB(248, 250, 254),
			BorderSizePixel = 0,
			kit.row("InsertControls", { kit.button("Insert", "+ Insert control", 198, actions.insertMenu, true) }),
			kit.text("OutlineHeading", "LAYERS", 11, 22),
			layerOutline.mount(Facet, kit.UI, Host, model, actions),
			kit.row("LayerActions", {
				kit.button("Duplicate", "Duplicate", 92, actions.duplicate, false, function(use: Use)
					return use(model).selected ~= nil and use(model).canEditLayer
				end),
				kit.button("Delete", "Delete", 92, actions.delete, false, function(use: Use)
					return use(model).selected ~= nil and use(model).canEditLayer
				end),
			}),
			kit.row("MoveActions", { kit.button("MoveInto", "Move into…", 140, actions.moveMenu) }),
		}
		canvas = Host.Frame "CanvasHost" {
			Position = contentPosition,
			Size = contentSize,
			Visible = paneVisible("Canvas"),
			BackgroundTransparency = 1,
		}
		local title = kit.input("DesignName", function(use: Use)
			return use(model).name
		end, actions.rename, UDim2.fromOffset(200, 32))
		local header = Host.ScrollingFrame "DesignHeader" {
			Visible = function(use: Use)
				return not use(model).compact
			end,
			Size = UDim2.new(1, 0, 0, 62),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			ScrollBarThickness = 0,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			kit.padding(14) :: unknown,
			kit.row("Commands", {
				kit.button("Brand", "FD", 38, actions.home, true),
				title,
				kit.button("Undo", "Undo", 54, actions.undo, false, function(use: Use)
					return use(model).canUndo
				end),
				kit.button("Redo", "Redo", 54, actions.redo, false, function(use: Use)
					return use(model).canRedo
				end),
				kit.button("Templates", "Templates ▾", 112, actions.templates),
				kit.button("Saved", "My designs ▾", 122, actions.saved),
				kit.button("SaveDesign", "Save", 56, actions.save),
				kit.button("Files", "Files", 62, actions.commands),
				kit.button("Import", "Import", 62, actions.import),
				kit.button("Code", "Code", 58, actions.code),
				kit.button("Export", "Export Luau", 100, actions.export, true),
			}),
		}
		local compactTitle = kit.input("CompactDesignName", function(use: Use)
			return use(model).name
		end, actions.rename, UDim2.new(1, -182, 0, 44))
		local compactHeader = Host.Frame "CompactHeader" {
			Visible = function(use: Use)
				return use(model).compact
			end,
			Size = UDim2.new(1, 0, 0, 76),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			kit.padding(12) :: unknown,
			kit.row("CompactCommands", {
				compactTitle,
				kit.button("CompactUndo", "Undo", 54, actions.undo, false, function(use: Use)
					return use(model).canUndo
				end),
				kit.button("CompactRedo", "Redo", 54, actions.redo, false, function(use: Use)
					return use(model).canRedo
				end),
				kit.button("DesignCommands", "•••", 44, actions.commands, true),
			}),
		}

		local settings = Host.ScrollingFrame "DesignSettings" {
			Position = function(use: Use)
				return UDim2.fromOffset(0, if use(model).compact then 76 else 62)
			end,
			Size = function(use: Use)
				return UDim2.new(1, 0, 0, 60)
			end,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			ScrollBarThickness = 0,
			BackgroundColor3 = Color3.fromRGB(248, 250, 254),
			BorderSizePixel = 0,
			kit.padding(8) :: unknown,
			kit.row("PreviewSettings", {
				kit.button(
					"Device",
					function(use: Use)
						return tostring(use(model).device) .. " ▾"
					end,
					112,
					function()
						actions.settingMenu("device")
					end
				),
				kit.button("Rotate", "Rotate", 60, actions.rotate),
				kit.button(
					"Palette",
					function(use: Use)
						return tostring(use(model).palette) .. " ▾"
					end,
					82,
					function()
						actions.settingMenu("palette")
					end
				),
				kit.button(
					"TextSize",
					function(use: Use)
						return "Text: " .. tostring(use(model).textSize) .. " ▾"
					end,
					146,
					function()
						actions.settingMenu("textSize")
					end
				),
				kit.button(
					"Compare",
					function(use: Use)
						return tostring(use(model).comparison) .. " ▾"
					end,
					100,
					function()
						actions.settingMenu("comparison")
					end
				),
				kit.button(
					"Zoom",
					function(use: Use)
						return "Zoom: " .. tostring(use(model).zoom) .. " ▾"
					end,
					132,
					function()
						actions.settingMenu("zoom")
					end
				),
				kit.button("Interaction", function(use: Use)
					return if use(model).interactive then "Interact" else "Select"
				end, 92, actions.interactive),
			}),
		}
		codeBox = Host.TextBox "GeneratedCode" {
			Text = function(use: Use)
				return use(model).code
			end,
			Font = Enum.Font.Code,
			TextSize = 12,
			TextColor3 = kit.colors.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ClearTextOnFocus = false,
			TextEditable = true,
			MultiLine = true,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Size = UDim2.new(1, -32, 0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			Position = UDim2.fromOffset(16, 52),
		}
		local applyCode = kit.button("ApplyCode", "Apply code to design", 182, function()
			actions.applyCode(assert(codeBox).Text)
		end, true)
		runtime.decorate(applyCode, { Position = UDim2.new(1, -202, 0, 8), ZIndex = 3001 })
		local codePanel = Host.Frame "CodePanel" {
			Visible = function(use: Use)
				return use(model).showCode
			end,
			Position = contentPosition,
			Size = contentSize,
			ZIndex = 3000,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			applyCode :: unknown,
			Host.ScrollingFrame "CodeScroll" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AutomaticCanvasSize = Enum.AutomaticSize.XY,
				CanvasSize = UDim2.new(),
				ScrollBarThickness = 6,
				codeBox :: unknown,
			},
		}
		local menu = Host.Frame "DesignMenu" {
			Visible = function(use: Use)
				return use(model).menuTitle ~= ""
			end,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = function(use: Use)
				return if use(model).compact then UDim2.new(0.94, 0, 0.8, 0) else UDim2.fromOffset(420, 470)
			end,
			ZIndex = 4000,
			BackgroundColor3 = Color3.fromRGB(248, 250, 254),
			BorderSizePixel = 0,
			kit.corner(12) :: unknown,
			kit.padding(16),
			Host.UIStroke { Color = kit.colors.line, Thickness = 1 },
			Host.UIListLayout { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder },
			kit.row(
				"MenuTitle",
				{ kit.text("MenuHeading", function(use: Use)
					return use(model).menuTitle
				end, 15, 30) }
			),
			kit.search(function(use: Use)
				return use(model).menuQuery
			end, actions.menuSearch),
			Host.ScrollingFrame "MenuChoices" {
				LayoutOrder = 3,
				Size = UDim2.new(1, 0, 1, -170),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollBarThickness = 3,
				Host.UIListLayout { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder } :: unknown,
				Host.TextLabel "EmptyMenu" {
					Size = UDim2.new(1, -10, 0, 72),
					BackgroundTransparency = 1,
					TextColor3 = kit.colors.muted,
					TextSize = 14,
					TextWrapped = true,
					Text = function(use: Use)
						return if use(model).menuQuery ~= ""
							then "No matches. Clear search to see all items."
							else "No items yet. Save a design to add it to your library."
					end,
					Visible = function(use: Use)
						local state = use(model)
						for _, entry in state.menu do
							if string.find(string.lower(entry.label), string.lower(state.menuQuery), 1, true) then
								return false
							end
						end
						return true
					end,
				},
				Compose.keyed({
					from = function(use: Use)
						local state = use(model)
						local entries = {}
						for _, entry in state.menu do
							if string.find(string.lower(entry.label), string.lower(state.menuQuery), 1, true) then
								table.insert(entries, entry)
							end
						end
						return entries
					end,
					key = function(entry)
						return entry.label
					end,
					render = function(current, index)
						local button = kit.button("MenuChoice", current:peek().label, 378, function()
							actions.menuPick(current:peek().value)
						end)
						runtime.decorate(button, {
							LayoutOrder = index,
							Size = function(use: Use)
								return UDim2.new(1, -10, 0, if use(model).compact then 44 else 32)
							end,
						})
						return button
					end,
				}),
			},
			kit.row("MenuFooter", {
				kit.button("ClearMenuSearch", "Clear", 80, function()
					actions.menuSearch("")
				end),
				kit.button("CloseMenu", "Close", 100, actions.menuClose),
			}),
		}
		local transferBox = Host.TextBox "DesignFileText" {
			Text = function(use: Use)
				return use(model).transferText
			end,
			TextEditable = function(use: Use)
				return use(model).transferEditable
			end,
			ClearTextOnFocus = false,
			MultiLine = true,
			TextWrapped = true,
			Font = Enum.Font.Code,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, -12, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
		}
		local transferTitle = kit.text("FileHeading", function(use: Use)
			return use(model).transferTitle
		end, 18, 42)
		runtime.decorate(transferTitle, { Size = UDim2.new(1, -36, 0, 42), Position = UDim2.fromOffset(18, 12) })
		local transferActions = kit.row("FileActions", {
			kit.button(
				"ApplyDesignFile",
				"Apply",
				92,
				function()
					actions.transferApply(transferBox.Text)
				end,
				true,
				function(use: Use)
					return use(model).transferEditable
				end
			),
			kit.button("CloseDesignFile", "Close", 92, actions.transferClose),
		})
		runtime.decorate(transferActions, { Position = UDim2.new(0, 18, 1, -64), Size = UDim2.new(1, -36, 0, 44) })
		local transferPanel = Host.Frame "DesignFilePanel" {
			Visible = function(use: Use)
				return use(model).transferTitle ~= ""
			end,
			Size = UDim2.fromScale(0.94, 0.8),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(248, 250, 254),
			BorderSizePixel = 0,
			ZIndex = 5100,
			kit.corner(12) :: unknown,
			transferTitle,
			transferActions,
			Host.ScrollingFrame "DesignFileScroll" {
				Position = UDim2.fromOffset(18, 64),
				Size = UDim2.new(1, -36, 1, -142),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollBarThickness = 4,
				transferBox :: unknown,
			},
		}
		local dataPanel = Host.Frame "DataEditor" {
			Visible = function(use: Use)
				return use(model).dataTitle ~= ""
			end,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = function(use: Use)
				return UDim2.new(if use(model).compact then 0.94 else 0.6, 0, 0.8, 0)
			end,
			ZIndex = 4000,
			BackgroundColor3 = Color3.fromRGB(248, 250, 254),
			BorderSizePixel = 0,
			kit.corner(12) :: unknown,
			kit.padding(18),
			Host.UIStroke { Color = kit.colors.line, Thickness = 1 },
			kit.text("DataHeading", function(use: Use)
				return "Edit " .. tostring(use(model).dataTitle)
			end, 18, 30),
			Host.ScrollingFrame "DataFields" {
				Position = UDim2.fromOffset(0, 44),
				Size = UDim2.new(1, 0, 1, -100),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollBarThickness = 4,
				Host.UIListLayout { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder } :: unknown,
				Compose.keyed({
					from = function(use: Use)
						return use(model).dataFields
					end,
					key = function(item)
						return item.id
					end,
					render = function(current, index)
						local item = current:peek()
						local input
						if item.kind == "boolean" then
							input = kit.button(
								"DataValue",
								function(use: Use)
									return if use(current).value then "On" else "Off"
								end,
								180,
								function()
									actions.dataProperty(item.path, not current:peek().value, item.kind)
								end
							)
						else
							input = kit.input("DataValue", function(use: Use)
								return tostring(use(current).value)
							end, function(value)
								actions.dataProperty(item.path, value, item.kind)
							end)
						end
						return Host.Frame "DataField" {
							LayoutOrder = index,
							Size = function(use: Use)
								return UDim2.new(1, -10, 0, if use(model).compact then 76 else 60)
							end,
							BackgroundTransparency = 1,
							Host.UIListLayout { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder } :: unknown,
							kit.text("DataLabel", item.label, 11, 22),
							input,
						}
					end,
				}),
			},
			Host.ScrollingFrame "DataCommands" {
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.X,
				ScrollBarThickness = 0,
				Position = UDim2.new(0, 0, 1, -56),
				Size = UDim2.new(1, 0, 0, 52),
				BackgroundTransparency = 1,
				kit.row("DataActions", {
					kit.button("AddEntry", "Add entry", 96, actions.dataAdd),
					kit.button("AddDataField", "Add field", 94, actions.dataField),
					kit.button("RemoveEntry", "Remove last", 112, actions.dataRemove),
					kit.button("CancelData", "Cancel", 80, actions.dataClose),
					kit.button("ApplyData", "Apply", 80, actions.dataApply, true),
				}),
			},
		}
		local paneBar = Host.Frame "PaneNavigation" {
			Visible = function(use: Use)
				return use(model).compact == true
			end,
			Position = UDim2.fromOffset(0, 136),
			Size = UDim2.new(1, 0, 0, 56),
			BackgroundColor3 = Color3.fromRGB(248, 250, 254),
			BorderSizePixel = 0,
			kit.padding(6) :: unknown,
			kit.row("Panes", {
				kit.button("CanvasPane", "Canvas", 86, function()
					actions.pane("Canvas")
				end, function(use: Use)
					return use(model).pane == "Canvas"
				end),
				kit.button("LayersPane", "Layers", 86, function()
					actions.pane("Layers")
				end, function(use: Use)
					return use(model).pane == "Layers"
				end),
				kit.button("InspectorPane", "Inspector", 98, function()
					actions.pane("Inspector")
				end, function(use: Use)
					return use(model).pane == "Inspector"
				end),
				kit.button("QuickInsert", "+", 44, actions.insertMenu, true),
			}),
		}
		for _, name in { "CanvasPane", "LayersPane", "InspectorPane" } do
			local button = paneBar:FindFirstChild(name, true)
			runtime.decorate(button, { Size = UDim2.new(1 / 3, -22, 0, 44) })
		end

		for _, name in { "Commands", "PreviewSettings", "DataActions" } do
			local row = if name == "Commands"
				then header:FindFirstChild(name)
				elseif name == "PreviewSettings" then settings:FindFirstChild(name)
				else dataPanel:FindFirstChild(name, true)
			row.AutomaticSize = Enum.AutomaticSize.X
			row.Size = UDim2.fromOffset(0, 44)
		end
		return Host.Frame "FacetDesign" {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(233, 237, 245),
			BorderSizePixel = 0,
			sheet :: unknown,
			Host.StyleLink { StyleSheet = Compose.static(sheet) },
			header,
			compactHeader,
			settings,
			paneBar,
			sidebar,
			canvas,
			inspector,
			codePanel,
			Host.Frame "ModalScrim" {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.fromRGB(24, 34, 54),
				BackgroundTransparency = 0.65,
				BorderSizePixel = 0,
				Active = true,
				ZIndex = 3900,
				Visible = function(use: Use)
					return use(model).menuTitle ~= "" or use(model).dataTitle ~= "" or use(model).transferTitle ~= ""
				end,
			},
			menu,
			dataPanel,
			gallery.build(Facet, runtime, kit, model, actions, options),
			transferPanel,
			Host.Frame "StatusBar" {
				Position = UDim2.new(0, 0, 1, -32),
				Size = UDim2.new(1, 0, 0, 32),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				kit.padding(7) :: unknown,
				kit.text("DesignStatus", function(use: Use)
					return use(model).status
				end, 11, 18),
			},
		}
	end, parent)
	local root = mounted :: Frame
	for _, name in { "DesignOutline", "DesignMenu" } do
		local container = root:FindFirstChild(name)
		local names: { string } = if name == "DesignOutline"
			then { "InsertControls", "OutlineHeading", "LayerTree", "LayerActions", "MoveActions" }
			else { "MenuTitle", "MenuSearch", "MenuChoices", "MenuFooter" }
		for index, childName in names do
			local child = assert(container):FindFirstChild(childName)
			if child then
				(child :: GuiObject).LayoutOrder = index
			end
		end
	end
	local function measure()
		if root.AbsoluteSize.X <= 0 then
			return
		end
		local compact = root.AbsoluteSize.X < 980
		if model:peek().compact ~= compact then
			model:update(function(previous)
				local nextValue = table.clone(previous)
				nextValue.compact = compact
				return nextValue
			end)
		end
		actions.layout(compact)
	end
	local connection = root:GetPropertyChangedSignal("AbsoluteSize"):Connect(measure)
	measure()
	root:AddTag("facet-pane")
	return {
		root = root,
		canvas = canvas,
		codeBox = codeBox,
		runtime = runtime,
		dispose = function()
			connection:Disconnect()
			stop()
			runtime:dispose()
		end,
	}
end

return shell
