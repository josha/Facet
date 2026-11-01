--!strict
local Facet = require(game.ReplicatedStorage.Packages.Facet)

export type Gain = { value: string, label: string }
export type Standing = { id: string, name: string, result: string }
export type AcceptedOutcome = {
	title: string,
	context: string?,
	gains: { Gain },
	standings: { Standing }?,
	standingsLabel: string?,
	explanation: string?,
}
export type State = { accepted: AcceptedOutcome }
export type Callbacks = { onContinue: () -> () }

local Outcome = {}

function Outcome.build(app: Facet.App, state: State, callbacks: Callbacks): Frame
	local C, UI, Host = Facet.Compose, app.UI, Facet.host(app.runtime)
	local result = state.accepted
	local root = Host.Frame "OutcomeTask" { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }
	local room = UI.environment(root)
	local open, details, explanation = C.cell(true), C.cell(false), C.cell(false)
	local finished = false
	local function continue()
		if finished then
			return
		end
		finished = true
		open:set(false)
		callbacks.onContinue()
	end
	local function short(use: Facet.Use): boolean
		return use(room.viewportHeight) < 520 and use(room.viewportWidth) > 600
	end
	local function support(use: Facet.Use): boolean
		return short(use) and (use(details) or use(explanation))
	end
	local function summary()
		details:set(false)
		explanation:set(false)
	end
	local detents: { Facet.SheetDetent } = { "hug", { id = "bounded", fraction = 0.88 } }
	local detent = C.cell("hug")
	C.watch(function(use: Facet.Use)
		detent:set(if short(use) then "bounded" else "hug")
	end)
	local actions: { Facet.OverlayAction } = {
		{ id = "Continue", label = "Continue", role = "default", onActivate = continue },
	}
	UI.Sheet "AcceptedOutcome" {
		Parent = C.static(root),
		title = result.title,
		header = false,
		closeButton = false,
		isPresented = open,
		placement = "center",
		width = function(use: Facet.Use): "narrow" | "wide"
			return if use(room.viewportWidth) < 600 then "narrow" else "wide"
		end,
		detents = detents,
		detent = detent,
		actions = actions,
		initialFocus = "Continue",
		onPresentedChange = function(presented: boolean)
			if not presented then
				if
					room.viewportHeight:peek() < 520
					and room.viewportWidth:peek() > 600
					and (details:peek() or explanation:peek())
				then
					summary()
				else
					continue()
				end
			end
		end,
		content = function()
			local gainsArea = Host.Frame "GainsArea" {
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = function(use: Facet.Use): UDim2
					return if short(use) then UDim2.new(0.55, -8, 0, 0) else UDim2.new(1, 0, 0, 0)
				end,
			}
			local gainsRoom = UI.environment(gainsArea)
			local function verticalGains(use: Facet.Use): boolean
				return use(gainsRoom.viewportWidth) < math.max(1, #result.gains) * 150
			end
			local gains: { Instance } = {}
			for index, gain in result.gains do
				gains[index] = UI.VStack("Gain" .. index)({
					Size = function(use: Facet.Use): UDim2
						return if verticalGains(use)
							then UDim2.new(1, 0, 0, 0)
							else UDim2.new(1 / math.max(1, #result.gains), -12, 0, 0)
					end,
					AutomaticSize = Enum.AutomaticSize.Y,
					gap = "xs",
					UI.Text "Value" { text = gain.value, textRole = "numeral", textAlign = "center", wrap = true },
					UI.Text "Meaning" { text = gain.label, textAlign = "center", wrap = true },
				})
			end
			local standings = result.standings or {}
			local columns: { Facet.TableColumn<Standing, string> } = {
				{
					id = "name",
					label = "Participant",
					value = function(row: Standing)
						return row.name
					end,
				},
				{
					id = "result",
					label = "Contribution",
					value = function(row: Standing)
						return row.result
					end,
				},
			}
			local records: Facet.KeyedTableSpec<Standing, string> = {
				from = standings,
				key = "id",
				columns = columns,
				selectionMode = "none",
				header = false,
				Size = function(use: Facet.Use): UDim2
					return UDim2.new(1, 0, 0, math.clamp(use(room.viewportHeight) * 0.3, 140, 240))
				end,
			}
			local contributions: Facet.KeyedTableSpec<Standing, string> = {
				from = standings,
				key = "id",
				columns = columns,
				selectionMode = "none",
				header = false,
				Visible = details,
				Size = UDim2.new(1, 0, 0, 160),
			}
			UI.AdaptiveStack "AcceptedGains" {
				Parent = C.static(gainsArea),
				width = "fill",
				AutomaticSize = Enum.AutomaticSize.Y,
				gap = "m",
				distribute = "center",
				axis = function(use: Facet.Use): "x" | "y"
					return if verticalGains(use) then "y" else "x"
				end,
				table.unpack(gains),
			}

			return UI.VStack "OutcomeBody" {
				width = "fill",
				gap = "m",
				padding = "m",
				UI.VStack "SupportStep" {
					Visible = support,
					width = "fill",
					gap = "s",
					UI.HStack "SupportHeader" {
						width = "fill",
						gap = "m",
						align = "center",
						UI.Button "BackToOutcome" { label = "Back to outcome", onActivate = summary },
						UI.Text(
							{ text = result.title, textRole = "heading", wrap = true, UI.fill() },
							"AcceptedIdentity"
						),
					},
					UI.Table "ContributionDetails" (contributions),
					UI.Text "ChangeDetails" { text = result.explanation or "", wrap = true, Visible = explanation },
				},
				UI.AdaptiveStack "OutcomeAndGains" {
					Visible = function(use: Facet.Use): boolean
						return not support(use)
					end,
					width = "fill",
					gap = "m",
					align = "center",
					axis = function(use: Facet.Use): "x" | "y"
						return if short(use) then "x" else "y"
					end,
					UI.VStack "Outcome" {
						Size = function(use: Facet.Use): UDim2
							return if short(use) then UDim2.new(0.45, -8, 0, 0) else UDim2.new(1, 0, 0, 0)
						end,
						AutomaticSize = Enum.AutomaticSize.Y,
						gap = "s",
						if result.context
							then UI.Text "Context" {
								text = result.context,
								role = "secondary",
								textAlign = "center",
								wrap = true,
							}
							else nil,
						UI.Text "OutcomeTitle" {
							text = result.title,
							textRole = "title",
							textAlign = "center",
							wrap = true,
						},
					},
					gainsArea,
				},
				if #standings > 0
					then UI.DisclosureGroup "Standings" {
						Visible = function(use: Facet.Use): boolean
							return not support(use)
						end,
						label = result.standingsLabel or "Contributions",
						expanded = details,
						content = function()
							return UI.Table "Participants" (records)
						end,
					}
					else nil,
				if result.explanation
					then UI.DisclosureGroup "Explanation" {
						Visible = function(use: Facet.Use): boolean
							return not support(use)
						end,
						label = "What changed?",
						expanded = explanation,
						content = function()
							return UI.Text { text = result.explanation or "", wrap = true }
						end,
					}
					else nil,
			}
		end,
	}
	return root
end

return Outcome
