--!strict
--[[ Paging: `UI.Pagination` over caller-owned pages (docs/reference/api.md#uipagination).
	A known count with its result context printed beside it, an unknown count that
	only knows whether there is more, the label form, and the same row right to
	left. A toggle refuses proposals, to show the row repaint only on the
	caller's own value. ]]
local COPY = {
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
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local refuse = Compose.cell(false)
		local results = Compose.cell(5)
		local feed = Compose.cell(1)
		local label = Compose.cell(3)
		local rtl = Compose.cell(5)
		local PER_PAGE, TOTAL = 20, 4000
		local function accept(cell: any): (number) -> ()
			return function(next: number)
				if not refuse:peek() then
					cell:set(next)
				end
			end
		end

		local function section(): any
			return UI.VStack("Paging")({
				width = UI.fill(),
				gap = "m",
				UI.Toggle("Refuse")({ label = COPY.refuse, value = refuse }),
				UI.Text("ResultsTitle")({ text = COPY.results, textSize = "label", width = UI.fill() }),
				UI.Text("ResultsContext")({
					width = UI.fill(),
					text = function(use: any): string
						local page = use(results)
						local first = (page - 1) * PER_PAGE + 1
						return `{COPY.showing} {first}–{math.min(TOTAL, page * PER_PAGE)} {COPY.of} {TOTAL}`
					end,
				}),
				UI.Pagination("Results")({
					page = results,
					pageCount = TOTAL // PER_PAGE,
					showFirstLast = true,
					onChange = accept(results),
				}),
				UI.Text("FeedTitle")({ text = COPY.feed, textSize = "label", width = UI.fill() }),
				UI.Text("FeedContext")({
					width = UI.fill(),
					text = function(use: any): string
						return `{COPY.loaded} {use(feed)}`
					end,
				}),
				UI.Pagination("Feed")({
					page = feed,
					hasPrevious = function(use: any): boolean
						return use(feed) > 1
					end,
					hasNext = function(use: any): boolean
						return use(feed) < 7
					end,
					onChange = accept(feed),
				}),
				UI.Text("LabelTitle")({ text = COPY.labelForm, textSize = "label", width = UI.fill() }),
				UI.Pagination("Label")({ page = label, pageCount = 12, form = "label", onChange = accept(label) }),
				UI.Text("RtlTitle")({ text = COPY.rtl, textSize = "label", width = UI.fill() }),
				UI.Pagination("Rtl")({ page = rtl, pageCount = 30, direction = "rtl", onChange = accept(rtl) }),
			})
		end

		return {
			section = section,
			screen = function()
				return UI.Screen("PagingScreen")({
					surface = "base",
					padding = { top = "m", bottom = "m" },
					UI.ScrollView("Content")({
						width = UI.fill(),
						height = UI.fill(),
						padding = { left = "m", right = "m" },
						section(),
					}),
				})
			end,
			steps = {},
		}
	end,
}
