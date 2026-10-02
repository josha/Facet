--!strict
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T

local session = require("./session")
local render = require("./design_render")

local gallery = {}

function gallery.page(entries: { any }, query: string, page: number): ({ any }, number)
	local filtered = {}
	local search = string.lower(query)
	for _, entry in entries do
		if string.find(string.lower(entry.label .. " " .. (entry.detail or "")), search, 1, true) then
			table.insert(filtered, entry)
		end
	end
	local pages = math.max(1, math.ceil(#filtered / 6))
	local at = math.clamp(page, 1, pages)
	local result = {}
	for index = (at - 1) * 6 + 1, math.min(at * 6, #filtered) do
		table.insert(result, filtered[index])
	end
	return result, pages
end

function gallery.build(Facet: any, runtime: any, kit: any, model: any, actions: any, options: any): Frame
	local Host, Compose: typeof(require("@repo/src/vendor/compose/core")) =
		(runtime.constructors :: unknown) :: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host),
		Facet.Compose
	local grid = Host.UIGridLayout {
		CellSize = function(use: Use)
			return if use(model).compact then UDim2.new(1, -8, 0, 264) else UDim2.new(1 / 3, -12, 0, 264)
		end,
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}
	local list = Host.ScrollingFrame "DesignGalleryCards" {
		Position = UDim2.fromOffset(18, 116),
		Size = UDim2.new(1, -36, 1, -180),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		grid :: unknown,
		Compose.keyed({
			from = function(use: Use)
				local state = use(model)
				return gallery.page(state.galleryEntries, state.galleryQuery, state.galleryPage)
			end,
			key = function(entry)
				return entry.id
			end,
			render = function(current, index)
				local entry = current:peek()
				local previewHost = Host.Frame "Thumbnail" {
					LayoutOrder = 1,
					Size = UDim2.new(1, 0, 0, 164),
					BackgroundColor3 = Color3.fromRGB(240, 244, 251),
					BorderSizePixel = 0,
					ClipsDescendants = true,
					kit.corner(8),
				}
				local preview = session.mount(Facet, previewHost, render.definition(entry.design).previews[1], {
					config = {
						width = 390,
						height = 844,
						input = "Touch",
						display = "Small",
						distance = "near",
						palette = "Light",
						textSize = "Medium",
						motionLevel = "none",
					},
					inputParent = options.inputParent,
					keyboardNavigation = false,
					register = Compose.cleanup,
				})
				local scale = Host.UIScale { Scale = 0.4 }
				scale.Parent = preview.root
				runtime.decorate(preview.root, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
				})
				local function measure()
					scale.Scale =
						math.max(0.01, math.min(previewHost.AbsoluteSize.X / 390, previewHost.AbsoluteSize.Y / 844))
				end
				local connection = previewHost:GetPropertyChangedSignal("AbsoluteSize"):Connect(measure)
				Compose.cleanup(function()
					connection:Disconnect()
				end)
				measure()
				local pick = kit.button("OpenGalleryCard", entry.label, -1, function()
					actions.galleryPick(entry.id)
				end, function()
					return true
				end)
				runtime.decorate(pick, { Size = UDim2.new(0, 0, 0, 44) })
				kit.UI.fill().Parent = pick
				local manage = kit.button("ManageGalleryCard", "•••", 40, function()
					actions.galleryManage(entry.id)
				end)
				runtime.decorate(manage, {
					Visible = function(use: Use)
						return use(model).galleryTitle == "My designs"
					end,
				})
				local detail = kit.text("GalleryDetail", entry.detail or "", 11, 20)
				runtime.decorate(detail, { LayoutOrder = 3 })
				local controls = kit.row("GalleryCardActions", { pick, manage })
				runtime.decorate(controls, { LayoutOrder = 2 })
				local card = Host.Frame("GalleryCard_" .. entry.id) {
					LayoutOrder = index,
					BackgroundColor3 = Color3.new(1, 1, 1),
					BorderSizePixel = 0,
					kit.corner(10) :: unknown,
					Host.UIStroke { Color = kit.colors.line, Thickness = 1 },
					kit.padding(10),
					Host.UIListLayout { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder },
					previewHost,
					controls,
					detail,
				}
				local select = Host.TextButton "ThumbnailSelect" {
					Size = UDim2.fromScale(1, 1),
					Text = "",
					BackgroundTransparency = 1,
					ZIndex = 2001,
					[Compose.event("Activated")] = function()
						actions.galleryPick(entry.id)
					end,
				}
				select.Parent = previewHost
				return card
			end,
		}),
	}
	local title = kit.text("GalleryTitle", function(use: Use)
		return use(model).galleryTitle
	end, 22, 38)
	runtime.decorate(title, { Position = UDim2.fromOffset(18, 14), Size = UDim2.new(1, -110, 0, 38) })
	local close = kit.button("CloseGallery", "Close", 76, actions.galleryClose)
	runtime.decorate(close, { Position = UDim2.new(1, -94, 0, 14) })
	local search = kit.search(function(use: Use)
		return use(model).galleryQuery
	end, actions.gallerySearch)
	runtime.decorate(search, { Position = UDim2.fromOffset(18, 62), Size = UDim2.new(1, -36, 0, 44) })
	local footer = kit.row("GalleryPaging", {
		kit.button(
			"GalleryPrevious",
			"Previous",
			84,
			function()
				actions.galleryPage(-1)
			end,
			false,
			function(use: Use)
				return use(model).galleryPage > 1
			end
		),
		kit.button(
			"GalleryNext",
			"Next",
			64,
			function()
				actions.galleryPage(1)
			end,
			false,
			function(use: Use)
				local state = use(model)
				local _, pages = gallery.page(state.galleryEntries, state.galleryQuery, state.galleryPage)
				return state.galleryPage < pages
			end
		),
		kit.text("GalleryPage", function(use: Use)
			local state = use(model)
			local _, pages = gallery.page(state.galleryEntries, state.galleryQuery, state.galleryPage)
			return tostring(state.galleryPage) .. " / " .. tostring(pages)
		end, 12, 32),
	})
	runtime.decorate(footer, { Position = UDim2.new(0, 18, 1, -56), Size = UDim2.new(1, -36, 0, 44) })
	local empty = kit.text("GalleryEmpty", "No designs found. Clear search or save your first design.", 14, 80)
	runtime.decorate(empty, {
		Position = UDim2.fromOffset(18, 120),
		Size = UDim2.new(1, -36, 0, 80),
		TextWrapped = true,
		Visible = function(use: Use)
			local state = use(model)
			return #gallery.page(state.galleryEntries, state.galleryQuery, state.galleryPage) == 0
		end,
	})
	return Host.Frame "DesignGallery" {
		Visible = function(use: Use)
			return use(model).galleryTitle ~= ""
		end,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5000,
		BackgroundColor3 = Color3.fromRGB(248, 250, 254),
		BorderSizePixel = 0,
		title :: unknown,
		close,
		search,
		list,
		empty,
		footer,
	}
end

return gallery
