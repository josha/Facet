--!strict
-- Passive hints, a bound Label and a caller-owned link share ordinary controls.
return {
	title = "Keys and labels",
	build = function(ctx)
		local Facet, UI, Compose = ctx.Facet, ctx.UI, ctx.Compose
		local rung, separator, title = Compose.cell("regular"), Compose.cell("or"), Compose.cell("Saved")
		local guide = Compose.cell(false)
		local rootPath, controller, customContext, customAction, customBinding
		local liveRecord, customRecord
		local function refresh()
			if controller then
				ctx.presenter.refresh()
			end
		end
		local function text(path)
			local facts = if controller and rootPath then controller.textAt(rootPath .. path) else nil
			return if facts then facts.text else nil
		end
		local function rect(path)
			return if controller and rootPath then controller.rectOf(rootPath .. path) else nil
		end
		local function live(id, record)
			local letter = text("/" .. id .. "/Live/then/Chord1/Key1/Label")
			local glyph = rect("/" .. id .. "/LiveGlyph/then/Chord1/Key1/Glyph")
			return { text = letter, glyph = if glyph and record then record.dump().glyph else nil }
		end
		local function report()
			refresh()
			local cap = rect("/Explicit/Chord1/Key1")
			return {
				live = live("Live", liveRecord),
				custom = live("Custom", customRecord),
				separator = text("/Explicit/Or2"),
				title = text("/BoundLabel/Title"),
				capHeight = if cap then cap.h else nil,
				guideVisible = rect("/Guide/then/GuideText") ~= nil,
			}
		end
		local function class(value)
			ctx.env:set("capabilities", { keyboard = true, mouse = true, gamepad = true, touch = true })
			ctx.env:set("preferredInput", value)
			return report()
		end
		local function binding(key)
			if not rootPath then
				return report()
			end
			if not customContext then
				customContext = ctx.actionSystem.createContext({ name = "ShortcutRecipe" })
				customAction = customContext.createAction("RecipeCommand", "Bool")
			end
			if customBinding then
				customBinding.remove()
				customBinding = nil
			end
			if key then
				customBinding = customAction.bind({ keyCode = key })
			end
			return report()
		end
		local function section()
			Compose.cleanup(function()
				if customContext then
					customContext.destroy()
				end
				customContext, customAction, customBinding = nil, nil, nil
				rootPath, controller, liveRecord, customRecord = nil, nil, nil, nil
			end)
			local root = UI.VStack("HintRecipe")({
				width = UI.fill(),
				gap = "m",
				UI.Text("Title")({ text = "Keys and labels", textSize = "heading", width = UI.fill() }),
				UI.Text("Note")({
					text = "Hints describe a shortcut. They do not take focus or claim its key.",
					width = UI.fill(),
				}),
				UI.HStack("Size")({
					gap = "s",
					wrap = true,
					UI.Button("Compact")({
						label = "Compact",
						onActivate = function()
							rung:set("compact")
						end,
					}),
					UI.Button("Large")({
						label = "Large",
						onActivate = function()
							rung:set("large")
						end,
					}),
					UI.Button("Rename")({
						label = "Update label",
						onActivate = function()
							title:set("Lap saved")
						end,
					}),
				}),
				UI.Text("LiveHeading")({ text = "This surface's action", textSize = "label" }),
				UI.ShortcutHint("Live")({
					action = "Activate",
					controlSize = rung,
					env = ctx.env,
					ref = function(record)
						liveRecord = record
					end,
				}),
				UI.Text("ExplicitHeading")({
					text = "Alternatives, with a localized joining word",
					textSize = "label",
					width = UI.fill(),
				}),
				UI.ShortcutHint("Explicit")({
					keys = { { "K" }, { "F1" } },
					separator = separator,
					controlSize = rung,
					over = "media",
				}),
				UI.Label("BoundLabel")({ title = title, icon = "checkmark" }),
				UI.Text("CustomHeading")({
					text = "A binding can arrive after its hint",
					textSize = "label",
					width = UI.fill(),
				}),
				UI.ShortcutHint("Custom")({
					action = "RecipeCommand",
					controlSize = rung,
					env = ctx.env,
					ref = function(record)
						customRecord = record
					end,
				}),
				UI.HStack("Bindings")({
					gap = "s",
					wrap = true,
					UI.Button("Bind")({
						label = "Bind Enter",
						onActivate = function()
							binding("Return")
						end,
					}),
					UI.Button("Rebind")({
						label = "Rebind R",
						onActivate = function()
							binding("R")
						end,
					}),
					UI.Button("Unbind")({
						label = "Remove binding",
						onActivate = function()
							binding(nil)
						end,
					}),
				}),
				-- Link is a Button appearance; this screen owns the navigation state.
				UI.Button("OpenGuide")({
					label = "Open shortcut guide",
					appearance = "link",
					onActivate = function()
						guide:set(true)
					end,
				}),
				UI.When("Guide")({
					condition = guide,
					thenView = function()
						return UI.Text("GuideText")({
							text = "The guide is open. Your screen decides what a link opens.",
							width = UI.fill(),
						})
					end,
				}),
			})
			return Facet.contribution.attach(root, {
				bindController = function(value)
					controller = value
				end,
				syncGeometry = function(_, node)
					if node then
						rootPath = node.path
					end
				end,
			})
		end
		return {
			section = section,
			screen = function()
				return UI.Screen("ShortcutHint")({
					surface = "base",
					padding = "m",
					UI.ScrollView("Content")({ width = UI.fill(), height = UI.fill(), section() }),
				})
			end,
			report = report,
			steps = {
				keyboard = function()
					return class("KeyboardAndMouse")
				end,
				pad = function()
					return class("Gamepad")
				end,
				touch = function()
					return class("Touch")
				end,
				compact = function()
					rung:set("compact")
					return report()
				end,
				large = function()
					rung:set("large")
					return report()
				end,
				localize = function()
					separator:set("ou")
					return report()
				end,
				rename = function()
					title:set("Lap saved")
					return report()
				end,
				bind = function()
					return binding("Return")
				end,
				rebind = function()
					return binding("R")
				end,
				unbind = function()
					return binding(nil)
				end,
			},
			reset = function()
				rung:set("regular")
				separator:set("or")
				title:set("Saved")
				guide:set(false)
				binding(nil)
			end,
		}
	end,
}
