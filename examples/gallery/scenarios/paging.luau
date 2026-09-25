--!strict
local COPY = {
	title = "Paging",
	results = "Results",
	feed = "Unknown count",
	labelForm = "Label form",
	rtl = "Right to left",
	refuse = "Refuse changes",
	showing = "Showing results",
	of = "of",
	loaded = "Feed page loaded:",
}

return {
	title = "Paging",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx)
		local UI, Compose, Host = ctx.UI, ctx.Compose, ctx.Host
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Enum = Enum }
		local UDim, UDim2, Enum = nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Enum
		local copy = ctx.copy or COPY
		local refuse = Compose.cell(false)
		local results = Compose.cell(5)
		local feed = Compose.cell(1)
		local label = Compose.cell(3)
		local rtl = Compose.cell(5)
		local PER_PAGE, TOTAL = 20, 4000
		local function accept(cell)
			return function(nextPage: number)
				if not refuse:peek() then
					cell:set(nextPage)
				end
			end
		end
		local function caption(name: string, text, order: number, role: string?)
			return UI.Label({
				Name = name,
				LayoutOrder = order,
				Text = text,
				textRole = role or "body",
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end
		local function section()
			return Host.Frame "Paging" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 16),
				}),
				caption("Title", copy.title, 1, "heading"),
				UI.Toggle({ Name = "Refuse", LayoutOrder = 2, label = copy.refuse, value = refuse }),
				caption("ResultsTitle", copy.results, 3, "label"),
				caption("ResultsContext", function(use)
					local page = use(results)
					local first = (page - 1) * PER_PAGE + 1
					return `{copy.showing} {first}–{math.min(TOTAL, page * PER_PAGE)} {copy.of} {TOTAL}`
				end, 4),
				UI.Pagination({
					Name = "Results",
					LayoutOrder = 5,
					page = results,
					pageCount = TOTAL // PER_PAGE,
					showFirstLast = true,
					onChange = accept(results),
				}),
				caption("FeedTitle", copy.feed, 6, "label"),
				caption("FeedContext", function(use)
					return `{copy.loaded} {use(feed)}`
				end, 7),
				UI.Pagination({
					Name = "Feed",
					LayoutOrder = 8,
					page = feed,
					hasPrevious = function(use)
						return use(feed) > 1
					end,
					hasNext = function(use)
						return use(feed) < 7
					end,
					onChange = accept(feed),
				}),
				caption("LabelTitle", copy.labelForm, 9, "label"),
				UI.Pagination({
					Name = "Label",
					LayoutOrder = 10,
					page = label,
					pageCount = 12,
					form = "label",
					onChange = accept(label),
				}),
				caption("RtlTitle", copy.rtl, 11, "label"),
				UI.Pagination({
					Name = "Rtl",
					LayoutOrder = 12,
					page = rtl,
					pageCount = 30,
					direction = "rtl",
					onChange = accept(rtl),
				}),
			}
		end
		return {
			section = section,
			screen = function()
				return Host.ScrollingFrame "PagingScreen" {
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					CanvasSize = UDim2.new(),
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					ScrollBarThickness = 6,
					Host.UIPadding({
						PaddingTop = UDim.new(0, 16),
						PaddingBottom = UDim.new(0, 16),
						PaddingLeft = UDim.new(0, 16),
						PaddingRight = UDim.new(0, 16),
					}),
					section(),
				}
			end,
			steps = {
				next = function()
					accept(results)(results:peek() + 1)
				end,
				refuse = function()
					refuse:set(not refuse:peek())
				end,
			},
			report = function()
				return { results = results:peek(), feed = feed:peek(), refuse = refuse:peek() }
			end,
		}
	end,
}
