--!strict
local FacetTypes = require("../../src")

type FacetModule = FacetTypes.Facet
type FacetControls = FacetTypes.Controls
type TypewriterControls = FacetTypes.TypewriterControls
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type Reply = { id: string, label: string }
type Line = { speaker: string, text: string, replies: { Reply } }
type Model = {
	line: Readable<Line?>,
	choose: (replyId: string) -> (),
}

return function(Facet: FacetModule, UI: FacetControls, model: Model): Instance
	local Compose = Facet.Compose
	local reveal: TypewriterControls = {}
	local talking = Compose.formula(function(use: Use): boolean
		return use(model.line) ~= nil
	end)
	return UI.Screen "Dialogue" {
		padding = "m",
		Compose.show(talking, function()
			return UI.VStack "DialogueBox" {
				UI.fill(),
				gap = "s",
				width = "fill",
				distribute = "end",
				UI.Text "Speaker" {
					text = function(use: Use)
						local line = use(model.line)
						return if line then line.speaker else ""
					end,
					textRole = "heading",
				},
				UI.Typewriter "LineText" {
					text = function(use: Use)
						local line = use(model.line)
						return if line then line.text else ""
					end,
					textRole = "body",
					wrap = true,
					controls = reveal,
				},
				UI.HStack "Replies" {
					gap = "s",
					wrap = true,
					Compose.show(function(use: Use)
						return not use(assert(reveal.revealed))
					end, function()
						return UI.Button "Skip" {
							label = "Skip",
							onActivate = function()
								if reveal.finish then
									reveal.finish()
								end
							end,
						}
					end),
					Compose.keyed({
						from = function(use: Use): { Reply }
							local line = use(model.line)
							return if line and use(assert(reveal.revealed)) then line.replies else {}
						end,
						key = function(reply: Reply): string
							return reply.id
						end,
						render = function(reply: Readable<Reply>)
							return UI.Button "Reply" {
								label = reply:peek().label,
								onActivate = function()
									model.choose(reply:peek().id)
								end,
							}
						end,
					}),
				},
			}
		end),
	}
end
