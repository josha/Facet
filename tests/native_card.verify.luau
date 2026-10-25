--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local FixtureComposeTypes = require("../src/vendor/compose/core")
	local FixtureNavigationTypes = require("../src/ui/navigation_types")
	local FixtureMediaTypes = require("../src/ui/media_types")
	local FixtureContentTypes = require("../src/ui/content_types")

	local fadeKit = require("./lib/fade")
	local Facet = require("../src")
	local worlds = require("./lib/content_world")
	local Compose: ComposeModule = Facet.Compose
	local UDim2 = require("./lib/native_engine").types.UDim2
	local styleRules = require("./lib/style_rules")

	local function cardSpec(log: { string }, extra: { [any]: any }?): { [any]: any }
		local spec: { [any]: any } = {
			image = "rbxassetid://1",
			title = "Nebula Racers",
			caption = "Friends playing",
			onActivate = function()
				table.insert(log, "body")
			end,
			primaryAction = {
				label = "Play",
				onActivate = function()
					table.insert(log, "primary")
				end,
			},
			menu = {
				items = {
					{
						id = "hide",
						label = "Not interested",
						onSelect = function()
							table.insert(log, "hide")
						end,
					},
				},
			},
		}
		local additions: { [any]: any } = extra or {}
		for key, value in additions do
			spec[key] = value
		end
		return spec
	end

	local function mount(spec: { [any]: any }, options: { [string]: any }?, touch: boolean?): (any, any, { [any]: any })
		local controls: FixtureComposeTypes.OrderedCollectionControls<any> = {}
		spec.controls = controls
		local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
			return Host.Frame({
				Name = "Row",
				UI.Card "C"(spec) :: unknown,
				UI.Button({ Name = "Next", label = "Next" }),
			})
		end, options or { motionLevel = "none" })
		if touch then
			world.engine.environment.poke(world.input, "TouchEnabled", true)
		end
		return world, world.find("C"), controls
	end

	local function attr(root: any, name: string): any
		return root:GetAttribute("Facet" .. name)
	end

	local function plate(world: any): any
		return world.find("Reveal")
	end

	local function primary(world: any): any
		return world.find("Primary")
	end

	local function more(world: any): any
		return world.find("More")
	end

	local function hover(root: any, inside: boolean)
		root[if inside then "MouseEnter" else "MouseLeave"]:Fire()
	end

	local function settle(world: any, seconds: number)
		for _ = 1, math.ceil(seconds * 60) do
			world.engine.heartbeat:Fire(1 / 60)
		end
	end

	local function lift(root: any): string
		local scale = root:FindFirstChild("Lift").Scale
		local shadow = root:FindFirstChild("LiftShadow", true)
		return `scale {math.floor(scale * 1000 + 0.5) / 1000} shadow {shadow ~= nil and shadow.Enabled == true}`
	end

	local function gridWorld(count: number, twoGrids: boolean?, reduced: boolean?): any
		local log: { string } = {}
		local controlsByGrid: { [string]: { [string]: any } } = { A = {}, B = {} }
		local cardsByGrid: { [string]: { [string]: any } } = { A = {}, B = {} }
		local sources = {
			A = Compose.cell((function()
				local out = {}
				for index = 1, count do
					out[index] = { id = `i{index}`, title = `Game {index}` }
				end
				return out
			end)()),
			B = Compose.cell({ { id = "i1", title = "Other 1" }, { id = "i2", title = "Other 2" } }),
		}
		local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
			local function grid(name: string)
				local controls, cards = controlsByGrid[name], cardsByGrid[name]
				return UI.VirtualGrid({
					Name = name,
					from = sources[name],
					key = "id",
					columns = 3,
					itemSize = 280,
					gap = 16,
					onActivate = function(_item: any, key: string)
						local entry = controls[key]
						if entry then
							entry.enterActions()
						end
					end,
					render = function(current: any, _placement: any, key: string): GuiObject
						local entry = {}
						controls[key] = entry
						local card = UI.Card({
							Name = "Card",
							image = "rbxassetid://1",
							title = function(use: any)
								return use(current).title
							end,
							controls = entry,
							browseTarget = function()
								local node = cards[key]
								local content = if node then node.Parent else nil
								return if content then content:FindFirstChild("RowHit") else nil
							end,
							primaryAction = {
								label = "Play",
								onActivate = function()
									table.insert(log, `play:{key}`)
								end,
							},
							menu = {
								items = {
									{
										id = "hide",
										label = "Not interested",
										onSelect = function()
											table.insert(log, `hide:{key}`)
										end,
									},
								},
							},
						})
						cards[key] = card
						Compose.cleanup(function()
							if cards[key] == card then
								cards[key] = nil
								controls[key] = nil
							end
						end)
						return card
					end,
				})
			end
			local children: { any } = { grid("A") }
			if twoGrids then
				table.insert(children, grid("B"))
			end
			return Host.Frame({ Name = "Page", table.unpack((children :: unknown) :: { unknown }) })
		end, { motionLevel = if reduced ~= false then "none" else "normal" })
		for _, name in (if twoGrids then { "A", "B" } else { "A" }) :: { string } do
			local node = world.find(name)
			world.engine.environment.poke(node, "AbsoluteWindowSize", world.V2(900, 600))
		end
		return {
			world = world,
			log = log,
			sources = sources,
			controls = controlsByGrid,
			cards = cardsByGrid,
			hit = function(key: string, name: string?): any
				local card = cardsByGrid[name or "A"][key]
				return card and card.Parent and card.Parent:FindFirstChild("RowHit")
			end,
			card = function(key: string, name: string?): any
				return cardsByGrid[name or "A"][key]
			end,
		}
	end

	verifyHarness:suite("native Card", function()
		verifyHarness:case("shows a text card with no art when image and artwork are absent", {
			id = "native_card::native Card::shows a text card with no art when image and artwork are absent",
			run = function()
				local world, card = mount({ title = "Sport Motor", caption = "250 Coins" })
				Verify.expect(world.find("Artwork").Visible):toBe(false)
				Verify.expect(world.find("Artwork").Size):toBe(UDim2.new(1, 0, 0, 0))
				Verify.expect(world.find("Title"):FindFirstChildWhichIsA("UIPadding").PaddingTop.Offset > 0):toBe(true)
				Verify.expect(world.find("Caption").Text):toBe("250 Coins")
				Verify.expect(table.find(card:GetTags(), "facet-card-text") ~= nil):toBe(true)
				Verify.expect(table.find(card:GetTags(), "facet-panel") ~= nil):toBe(true)
				Verify.expect(card:FindFirstChildWhichIsA("UIPadding") ~= nil):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("omits absent caption and action-cancel resources", {
			id = "native_card::native Card::omits absent caption and action-cancel resources",
			run = function()
				local world, _, controls = mount({ image = "rbxassetid://1", title = "Course" })
				Verify.expect(world.find("Caption")):toBe(nil)
				Verify.expect(world.find("FacetCardCancel")):toBe(nil)
				Verify.expect(assert(controls.enterActions)()):toBe(false)
				world.stop()
				Verify.expect(world.engine.census().connections):toBe(0)
			end,
		})

		verifyHarness:case("leaves the reveal row out of a card with nothing to reveal so its plate ends at its body", {
			id = "native_card::native Card::leaves the reveal row out of a card with nothing to reveal so its plate ends at its body",
			run = function()
				for _, reveal in { "automatic", "always" } do
					local caption = Compose.cell("Friends playing")
					local world, root = mount({
						image = "rbxassetid://1",
						title = "Course",
						caption = caption,
						reveal = reveal,
					})
					local laidOut: { string } = {}
					for _, child in root:GetChildren() do
						if child:IsA("GuiObject") then
							table.insert(laidOut, child.Name)
						end
					end
					Verify.expect((table.concat(laidOut, ","))):toBe("Body")
					Verify.expect((world.find("Reveal"))):toBeNil()
					Verify.expect((world.find("Plate"))):toBeNil()
					Verify.expect((world.action("CardCancel"))):toBeNil()
					local titleInset = world.find("Title"):FindFirstChildWhichIsA("UIPadding")
					local captionInset = world.find("Caption"):FindFirstChildWhichIsA("UIPadding")
					Verify.expect(titleInset.PaddingBottom.Offset):toBe(0)
					Verify.expect(captionInset.PaddingBottom.Offset > 0):toBe(true)
					caption:set("")
					Verify.expect(titleInset.PaddingBottom.Offset):toBe(captionInset.PaddingBottom.Offset)
					caption:set("Friends playing")
					Verify.expect(titleInset.PaddingBottom.Offset):toBe(0)
					world.stop()
				end
				local acting = cardSpec({})
				acting.caption = nil
				local world, root = mount(acting)
				Verify.expect(plate(world).Parent):toBe(root)
				Verify.expect(fadeKit.layer(world.find("Plate"))):toBe(plate(world))
				local actingTitle = root:FindFirstChild("Title", true):FindFirstChildWhichIsA("UIPadding")
				Verify.expect(actingTitle.PaddingBottom.Offset):toBe(0)
				world.stop()
			end,
		})

		verifyHarness:case("shows a price, then nothing once owned, then a named check icon once equipped", {
			id = "native_card::native Card::shows a price, then nothing once owned, then a named check icon once equipped",
			run = function()
				local owned, equipped = Compose.cell(false), Compose.cell(false)
				local world = mount({
					image = "rbxassetid://1",
					title = "Comet",
					badges = {
						trailing = {
							label = function(use: Compose.Use): string?
								return if use(owned) then nil else "3,400"
							end,
							icon = function(use: Compose.Use): string?
								return if use(equipped) then "checkmark" elseif use(owned) then nil else "coin"
							end,
							name = "Equipped",
							status = "neutral",
						},
					},
				})
				local trailing = world.find("Trailing", world.find("Badges"))
				local function pill(): GuiObject?
					return trailing:FindFirstChildWhichIsA("GuiObject")
				end
				local function words(): string
					local found = pill()
					local label = if found then found:FindFirstChildWhichIsA("TextLabel", true) else nil
					return if label and label.Visible then label.Text else ""
				end
				Verify.expect(pill() ~= nil):toBe(true)
				Verify.expect(words()):toBe("3,400")
				owned:set(true)
				Verify.expect(pill()):toBeNil()
				equipped:set(true)
				Verify.expect(pill() ~= nil):toBe(true)
				Verify.expect(words()):toBe("")
				local named = (pill() :: GuiObject):FindFirstChild("Label", true)
				Verify.expect(named and named:GetAttribute("AccessibleLabel")):toBe("Equipped")
				world.stop()
			end,
		})

		verifyHarness:case("moves the leading badge to the front of the caption when both badges do not fit, once", {
			id = "native_card::native Card::moves the leading badge to the front of the caption when both badges do not fit, once",
			run = function()
				local caption = Compose.cell("Spd 82")
				local world = mount({
					image = "rbxassetid://1",
					title = "Comet",
					caption = caption,
					badges = { leading = { label = "Rare", status = "accent" }, trailing = { label = "Owned" } },
				})
				local layer = world.find("Badges")
				local poke = world.engine.environment.poke
				poke(world.find("Leading", layer):FindFirstChildWhichIsA("GuiObject"), "AbsoluteSize", world.V2(80, 24))
				poke(
					world.find("Trailing", layer):FindFirstChildWhichIsA("GuiObject"),
					"AbsoluteSize",
					world.V2(90, 24)
				)
				poke(layer, "AbsoluteSize", world.V2(300, 160))
				local label = world.find("Caption")
				Verify.expect(label.Text):toBe("Spd 82")
				poke(layer, "AbsoluteSize", world.V2(180, 100))
				Verify.expect(label.Text):toBe("Rare · Spd 82")
				caption:set("Rare Spd 82")
				Verify.expect(label.Text):toBe("Rare Spd 82")
				local leadPill = world.find("Leading", layer):FindFirstChildWhichIsA("GuiObject")
				local trailPill = world.find("Trailing", layer):FindFirstChildWhichIsA("GuiObject")
				poke(trailPill, "AbsoluteSize", world.V2(200, 24))
				Verify.expect(trailPill.Visible):toBe(false)
				Verify.expect(leadPill.Visible):toBe(true)
				Verify.expect(label.Text):toBe("Owned · Rare Spd 82")
				world.stop()
			end,
		})

		verifyHarness:case("puts badges over the top corners of the art at theme spacing and follows their labels", {
			id = "native_card::native Card::puts badges over the top corners of the art at theme spacing and follows their labels",
			run = function()
				local function shown(holder: Instance): string
					local words: { string } = {}
					for _, node in holder:GetDescendants() do
						if node:IsA("TextLabel") and (node :: TextLabel).Text ~= "" then
							table.insert(words, (node :: TextLabel).Text)
						end
					end
					return table.concat(words, ",")
				end
				local label = Compose.cell("Owned" :: string?)
				local status = Compose.cell("success")
				local world = mount({
					image = "rbxassetid://1",
					title = "Course",
					badges = {
						leading = { label = "Rare", status = "accent" },
						trailing = { label = label, status = status, icon = "checkmark" },
					},
				})
				local layer = world.find("Badges")
				Verify.expect(layer.Parent):toBe(world.find("Artwork"))
				Verify.expect(layer.Size):toBe(UDim2.fromScale(1, 1))
				Verify.expect(layer.ZIndex):toBe(2)
				local inset = layer:FindFirstChildWhichIsA("UIPadding")
				local gap = inset.PaddingTop.Offset
				Verify.expect(gap > 0):toBe(true)
				for _, side in { "Left", "Right", "Bottom" } do
					Verify.expect(inset["Padding" .. side].Offset):toBe(gap)
				end
				local leading, trailing = world.find("Leading", layer), world.find("Trailing", layer)
				Verify.expect(leading.AnchorPoint):toBe(world.V2(0, 0))
				Verify.expect(leading.Position):toBe(UDim2.fromScale(0, 0))
				Verify.expect(trailing.AnchorPoint):toBe(world.V2(1, 0))
				Verify.expect(trailing.Position):toBe(UDim2.fromScale(1, 0))
				local poke = world.engine.environment.poke
				local leadPill = leading:FindFirstChildWhichIsA("GuiObject")
				local trailPill = trailing:FindFirstChildWhichIsA("GuiObject")
				poke(layer, "AbsoluteSize", world.V2(300, 160))
				poke(leadPill, "AbsoluteSize", world.V2(80, 24))
				poke(trailPill, "AbsoluteSize", world.V2(90, 24))
				local caption = world.find("Caption")
				Verify.expect(leadPill.Visible):toBe(true)
				Verify.expect(caption.Visible):toBe(false)
				poke(layer, "AbsoluteSize", world.V2(180, 100))
				Verify.expect(leadPill.Visible):toBe(false)
				Verify.expect(caption.Visible):toBe(true)
				Verify.expect(caption.Text):toBe("Rare")
				poke(layer, "AbsoluteSize", world.V2(300, 160))
				Verify.expect(leadPill.Visible):toBe(true)
				Verify.expect(caption.Visible):toBe(false)
				Verify.expect((shown(leading))):toBe("Rare")
				Verify.expect((shown(trailing))):toBe("Owned")
				Verify.expect((leading:FindFirstChildWhichIsA("GuiObject"):HasTag("facet-status-accent"))):toBe(true)
				Verify.expect((leading:FindFirstChildWhichIsA("GuiObject"):HasTag("facet-badge-on-media"))):toBe(true)
				local pill = trailing:FindFirstChildWhichIsA("GuiObject")
				Verify.expect((pill:HasTag("facet-status-success"))):toBe(true)
				status:set("warning")
				Verify.expect((pill:HasTag("facet-status-warning"))):toBe(true)
				label:set(nil)
				Verify.expect((shown(trailing))):toBe("")
				Verify.expect((shown(leading))):toBe("Rare")
				label:set("Sold")
				Verify.expect((shown(trailing))):toBe("Sold")
				world.stop()
				local plain = mount({ image = "rbxassetid://1", title = "Course" })
				Verify.expect((plain.find("Badges"))):toBeNil()
				plain.stop()
				Verify.expect(function()
					mount({ title = "Coins", badges = { leading = { label = "New" } } })
				end):toThrow("badges need image or artwork")
				Verify.expect(function()
					mount({ image = "rbxassetid://1", title = "Coins", badges = { top = { label = "New" } } })
				end):toThrow("badges has the unknown field 'top'")
				Verify.expect(function()
					mount({ image = "rbxassetid://1", title = "Coins", badges = { leading = { text = "New" } } })
				end):toThrow("badges.leading has the unknown field 'text'")
				Verify.expect(function()
					mount({ image = "rbxassetid://1", title = "Coins", badges = { leading = { status = "accent" } } })
				end):toThrow("badges.leading needs a label, or an icon and a name")
				Verify.expect(function()
					mount({ image = "rbxassetid://1", title = "Coins", badges = { trailing = { icon = "checkmark" } } })
				end):toThrow("badges.trailing needs a label, or an icon and a name")
				local marked = mount({
					image = "rbxassetid://1",
					title = "Coins",
					badges = { trailing = { icon = "checkmark", name = "Verified" } },
				})
				local mark = marked.find("Trailing"):FindFirstChildWhichIsA("GuiObject")
				Verify.expect(mark ~= nil and mark.Visible):toBe(true)
				marked.stop()
			end,
		})

		verifyHarness:case("paints a collection selection on the card's own plate, not on a plate under it", {
			id = "native_card::native Card::paints a collection selection on the card's own plate, not on a plate under it",
			run = function()
				local selection = Compose.cell({ art = true } :: { [string]: boolean })
				local world = worlds.new(function(UI)
					return UI.VirtualGrid({
						Name = "Grid",
						from = { { id = "art" }, { id = "plain" } },
						key = "id",
						columns = 2,
						itemSize = 200,
						selection = selection,
						render = function(_current, _placement, key)
							return UI.Card({
								Name = "Card",
								image = if key == "art" then "rbxassetid://1" else nil,
								title = key,
							})
						end,
					})
				end, { motionLevel = "none" })
				world.engine.environment.poke(world.find("Grid"), "AbsoluteWindowSize", world.V2(600, 400))
				local _, sheet = world.runtime.mount(function()
					return Facet.themes.createStyleSheet(world.runtime, Facet.themes.neutralPackage(), {
						types = world.engine.types,
					})
				end, world.engine.new("Folder"))
				local function paint(node: Instance): unknown
					return styleRules.resolve(sheet, node, "BackgroundColor3")
				end
				local items = world.find("Grid"):FindFirstChild("Items")
				local art = world.find("Card", items:FindFirstChild("art"))
				local plain = world.find("Card", items:FindFirstChild("plain"))
				for _, card in { art, plain } do
					local surface = card.Parent
					Verify.expect(surface.Name):toBe("Surface")
					Verify.expect((surface:HasTag("facet-tablerow"))):toBe(false)
					Verify.expect((surface:HasTag("facet-skinned"))):toBe(false)
					Verify.expect(surface.BackgroundTransparency):toBe(1)
					Verify.expect((card:FindFirstChild("Reveal"))):toBeNil()
				end
				Verify.expect((art.Parent:HasTag("facet-selected"))):toBe(true)
				local chosen = paint(art.Parent)
				Verify.expect(chosen ~= nil):toBe(true)
				Verify.expect(paint(art:FindFirstChild("Body"))):toBe(chosen)
				Verify.expect(paint(plain) == chosen):toBe(false)
				selection:set({ plain = true })
				Verify.expect((art.Parent:HasTag("facet-selected"))):toBe(false)
				Verify.expect(paint(plain)):toBe(chosen)
				Verify.expect(paint(art:FindFirstChild("Body")) == chosen):toBe(false)
				world.stop()
			end,
		})

		verifyHarness:case("keeps body, primary and More as sibling targets so one press runs one intent", {
			id = "native_card::native Card::keeps body, primary and More as sibling targets so one press runs one intent",
			run = function()
				local log: { string } = {}
				local world, root = mount(cardSpec(log))
				Verify.expect(world.find("Body").Parent):toBe(root)
				Verify.expect(fadeKit.layer(primary(world).Parent).Parent):toBe(root)
				Verify.expect((root:IsA("GuiButton"))):toBe(false)
				world.find("Body").Activated:Fire()
				Verify.expect((table.concat(log, ","))):toBe("body")
				hover(root, true)
				primary(world).Activated:Fire()
				Verify.expect((table.concat(log, ","))):toBe("body,primary")
				more(world).Activated:Fire()
				Verify.expect((attr(root, "MenuOpen"))):toBe(true)
				Verify.expect((table.concat(log, ","))):toBe("body,primary")
				world.stop()
			end,
		})

		verifyHarness:case("draws live artwork in the artwork frame and forwards the activating input to the body", {
			id = "native_card::native Card::draws live artwork in the artwork frame and forwards the activating input to the body",
			run = function()
				local inputs: { InputObject | string } = {}
				local released = 0
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Card("C")({
						title = "Afterlight",
						artwork = function(): GuiObject
							Compose.cleanup(function()
								released += 1
							end)
							return Host.ViewportFrame({ Name = "Preview" })
						end,
						onActivate = function(input: InputObject?)
							table.insert(inputs, (input or "none") :: any)
						end,
					})
				end, { motionLevel = "none" })
				local artwork = world.find("Artwork")
				local live = artwork:FindFirstChild("Preview")
				Verify.expect(artwork.Image):toBe("")
				Verify.expect(live ~= nil):toBe(true)
				Verify.expect(live.Size):toBe(UDim2.fromScale(1, 1))
				world.engine.environment.poke(world.find("C"), "AbsoluteSize", world.V2(320, 260))
				Verify.expect(artwork.Size):toBe(UDim2.new(1, 0, 0, 100000))
				local press = { UserInputType = "MouseButton1" }
				world.find("Body").Activated:Fire(press)
				world.find("Body").Activated:Fire()
				Verify.expect(inputs[1]):toBe(press)
				Verify.expect(inputs[2]):toBe("none")
				Verify.expect((world.find("C"):GetAttribute("FacetBody"))):toBe("button")
				world.stop()
				Verify.expect(released):toBe(1)
			end,
		})

		verifyHarness:case("resolves artwork aspect in native layout before its first measured width", {
			id = "native_card::native Card::resolves artwork aspect in native layout before its first measured width",
			run = function()
				for _, ratio in { 16 / 9, 1, 2 } do
					local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
						return UI.Card "C" {
							title = "Afterlight",
							imageAspectRatio = ratio,
							artwork = function(): GuiObject
								return Host.ViewportFrame { Name = "Preview" }
							end,
						}
					end, { motionLevel = "none" })
					local artwork = world.find("Artwork")
					local inset = world.find("Body"):FindFirstChildWhichIsA("UIPadding")
					local _, sheet = world.runtime.mount(function()
						return Facet.themes.createStyleSheet(world.runtime, Facet.themes.neutralPackage(), {
							types = world.engine.types,
						})
					end, world.engine.new("Folder"))
					Verify.expect(world.find("Body"):HasTag("facet-card-body")):toBe(true)
					Verify.expect(inset ~= nil):toBe(true)
					for _, side in { "Left", "Right", "Top", "Bottom" } do
						Verify.expect(inset["Padding" .. side].Offset):toBe(0)
						Verify.expect(inset["Padding" .. side].Scale):toBe(0)
						Verify.expect(styleRules.resolve(sheet, inset, "Padding" .. side).Offset):toBe(0)
					end
					local constraint = artwork:FindFirstChildWhichIsA("UIAspectRatioConstraint")
					Verify.expect(constraint ~= nil):toBe(true)
					Verify.expect(constraint.AspectRatio):toBe(ratio)
					Verify.expect(constraint.DominantAxis):toBe(world.engine.types.Enum.DominantAxis.Width)
					Verify.expect(constraint.AspectType):toBe(world.engine.types.Enum.AspectType.FitWithinMaxSize)
					Verify.expect(artwork.Size.X.Scale):toBe(1)
					Verify.expect(artwork.Size.Y.Offset > 0):toBe(true)
					Verify.expect(world.find("Preview").Size):toBe(UDim2.fromScale(1, 1))
					local authored = artwork.Size
					world.engine.environment.poke(world.find("C"), "AbsoluteSize", world.V2(340, 320))
					Verify.expect(artwork.Size):toBe(authored)
					world.engine.environment.poke(world.find("C"), "AbsoluteSize", world.V2(321.25, 320))
					Verify.expect(artwork.Size):toBe(authored)
					Verify.expect(artwork:FindFirstChildWhichIsA("UIAspectRatioConstraint")):toBe(constraint)
					world.stop()
				end
			end,
		})

		verifyHarness:case("gives an informational body no activation target and keeps its actions at rest", {
			id = "native_card::native Card::gives an informational body no activation target and keeps its actions at rest",
			run = function()
				local log: { string } = {}
				local spec = cardSpec(log)
				spec.onActivate = nil
				local world, root = mount(spec)
				Verify.expect((attr(root, "Body"))):toBe("informational")
				Verify.expect((world.find("Body"):IsA("GuiButton"))):toBe(false)
				Verify.expect(world.find("Title").Text):toBe("Nebula Racers")
				Verify.expect((attr(root, "Revealed"))):toBe(true)
				Verify.expect(plate(world).Interactable):toBe(true)
				world.gui.SelectedObject = primary(world)
				world.action("Activate").Pressed:Fire()
				Verify.expect((table.concat(log, ","))):toBe("primary")
				world.stop()
			end,
		})

		verifyHarness:case("keeps the semantics of disabled cards and busy actions", {
			id = "native_card::native Card::keeps the semantics of disabled cards and busy actions",
			run = function()
				local log: { string } = {}
				local enabled = Compose.cell(false)
				local busy = Compose.cell(true)
				local spec = cardSpec(log, { enabled = enabled })
				spec.primaryAction.busy = busy
				spec.menu = nil
				local world, _, controls = mount(spec)
				world.find("Body").Activated:Fire()
				Verify.expect(#log):toBe(0)
				Verify.expect((assert(controls.enterActions)())):toBe(false)
				enabled:set(true)
				Verify.expect((assert(controls.enterActions)())):toBe(false)
				busy:set(false)
				Verify.expect((assert(controls.enterActions)())):toBe(true)
				Verify.expect(world.gui.SelectedObject):toBe(primary(world))
				world.stop()
			end,
		})

		verifyHarness:case("leaves nothing behind when a callback removes its own card", {
			id = "native_card::native Card::leaves nothing behind when a callback removes its own card",
			run = function()
				local show = Compose.cell(true)
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						Name = "Row",
						Compose.show(show, function()
							return UI.Card "C"(cardSpec({}, {
								onActivate = function()
									show:set(false)
								end,
							}))
						end) :: unknown,
						UI.Button({ Name = "Next", label = "Next" }),
					})
				end)
				local body = world.find("Body")
				world.gui.SelectedObject = body
				body.Activated:Fire()
				Verify.expect((world.find("C"))):toBeNil()
				Verify.expect((world.find("CardCancel"))):toBeNil()
				world.stop()
			end,
		})

		verifyHarness:case("keeps hidden actions out of reach at rest and lets a selected body reveal them", {
			id = "native_card::native Card::keeps hidden actions out of reach at rest and lets a selected body reveal them",
			run = function()
				local log: { string } = {}
				local world, root = mount(cardSpec(log))
				primary(world).Activated:Fire()
				Verify.expect(#log):toBe(0)
				Verify.expect(plate(world).Interactable):toBe(false)
				world.gui.SelectedObject = world.find("Body")
				Verify.expect((attr(root, "FocusWithin"))):toBe(true)
				Verify.expect(plate(world).Interactable):toBe(true)
				primary(world).Activated:Fire()
				Verify.expect((table.concat(log, ","))):toBe("primary")
				world.stop()
			end,
		})

		verifyHarness:case("reveals on focus within, keeps it when the pointer leaves and ends it when focus leaves", {
			id = "native_card::native Card::reveals on focus within, keeps it when the pointer leaves and ends it when focus leaves",
			run = function()
				local world, root = mount(cardSpec({}))
				hover(root, true)
				world.gui.SelectedObject = world.find("Body")
				hover(root, false)
				Verify.expect((attr(root, "Revealed"))):toBe(true)
				world.gui.SelectedObject = primary(world)
				Verify.expect((attr(root, "Revealed"))):toBe(true)
				world.gui.SelectedObject = world.find("Next")
				Verify.expect((attr(root, "Revealed"))):toBe(false)
				world.stop()
			end,
		})

		verifyHarness:case("holds the reveal while its menu is open and releases it when the menu closes", {
			id = "native_card::native Card::holds the reveal while its menu is open and releases it when the menu closes",
			run = function()
				local world, root = mount(cardSpec({}))
				hover(root, true)
				more(world).Activated:Fire()
				hover(root, false)
				Verify.expect((attr(root, "MenuOpen"))):toBe(true)
				Verify.expect((attr(root, "Revealed"))):toBe(true)
				world.action("ModalBack").Pressed:Fire()
				Verify.expect((attr(root, "MenuOpen"))):toBe(false)
				Verify.expect((attr(root, "Revealed"))):toBe(false)
				world.stop()
			end,
		})

		verifyHarness:case("keeps the reveal while a press is held on an action after the pointer leaves", {
			id = "native_card::native Card::keeps the reveal while a press is held on an action after the pointer leaves",
			run = function()
				local world, root = mount(cardSpec({}))
				hover(root, true)
				world.engine.environment.poke(primary(world), "GuiState", world.engine.types.Enum.GuiState.Press)
				hover(root, false)
				Verify.expect((attr(root, "Pressing"))):toBe(true)
				Verify.expect((attr(root, "Revealed"))):toBe(true)
				world.engine.environment.poke(primary(world), "GuiState", world.engine.types.Enum.GuiState.Idle)
				Verify.expect((attr(root, "Revealed"))):toBe(false)
				world.stop()
				local held, heldRoot = mount(cardSpec({}))
				local Enum = held.engine.types.Enum
				local button = primary(held)
				hover(heldRoot, true)
				button.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1 })
				world.engine.environment.poke(button, "GuiState", Enum.GuiState.Press)
				hover(heldRoot, false)
				world.engine.environment.poke(button, "GuiState", Enum.GuiState.Idle)
				Verify.expect((attr(heldRoot, "Revealed"))):toBe(true)
				button.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1 })
				Verify.expect((attr(heldRoot, "Revealed"))):toBe(false)
				held.stop()
			end,
		})

		verifyHarness:case("keeps the actions at rest while touch is present and runs the body on the first tap", {
			id = "native_card::native Card::keeps the actions at rest while touch is present and runs the body on the first tap",
			run = function()
				local log: { string } = {}
				local world, root = mount(cardSpec(log), nil, true)
				Verify.expect((attr(root, "Revealed"))):toBe(true)
				world.find("Body").Activated:Fire()
				Verify.expect((table.concat(log, ","))):toBe("body")
				world.engine.environment.poke(
					world.input,
					"PreferredInput",
					world.engine.types.Enum.PreferredInput.KeyboardAndMouse
				)
				Verify.expect((attr(root, "Revealed"))):toBe(true)
				world.engine.environment.poke(world.input, "TouchEnabled", false)
				Verify.expect((attr(root, "Revealed"))):toBe(false)
				world.stop()
			end,
		})

		verifyHarness:case("takes no tap on hidden actions and never fires a press cut off by disabling", {
			id = "native_card::native Card::takes no tap on hidden actions and never fires a press cut off by disabling",
			run = function()
				local log: { string } = {}
				local enabled = Compose.cell(true)
				local world, root = mount(cardSpec(log, { enabled = enabled }))
				primary(world).Activated:Fire()
				Verify.expect(#log):toBe(0)
				hover(root, true)
				world.engine.environment.poke(primary(world), "GuiState", world.engine.types.Enum.GuiState.Press)
				enabled:set(false)
				world.engine.environment.poke(primary(world), "GuiState", world.engine.types.Enum.GuiState.Idle)
				primary(world).Activated:Fire()
				Verify.expect(#log):toBe(0)
				world.stop()
			end,
		})

		verifyHarness:case("grows a lifted card evenly around its centre", {
			id = "native_card::native Card::grows a lifted card evenly around its centre",
			run = function()
				local world, root = mount(cardSpec({}), { motionLevel = "normal" })
				world.engine.environment.poke(root, "AbsoluteSize", world.engine.types.Vector2.new(300, 200))
				Verify.expect(root.Position):toBe(world.engine.types.UDim2.fromOffset(0, 0))
				hover(root, true)
				settle(world, 1)
				world.engine.environment.poke(root, "AbsoluteSize", world.engine.types.Vector2.new(312, 208))
				Verify.expect(root.Position):toBe(world.engine.types.UDim2.fromOffset(0, 0))
				Verify.expect(root.AnchorPoint.X * root.AbsoluteSize.X):toBeCloseTo(6, 0.00001)
				Verify.expect(root.AnchorPoint.Y * root.AbsoluteSize.Y):toBeCloseTo(4, 0.00001)
				world.stop()
				local position = UDim2.fromOffset(30, 40)
				local explicit, positioned = mount(
					cardSpec({}, {
						Position = position,
						AnchorPoint = world.V2(0.5, 0.5),
					}),
					{ motionLevel = "normal" }
				)
				hover(positioned, true)
				settle(explicit, 1)
				Verify.expect(positioned.Position):toBe(position)
				Verify.expect(positioned.AnchorPoint):toBe(explicit.V2(0.5, 0.5))
				explicit.stop()
				local plain = cardSpec({})
				plain.primaryAction = nil
				plain.menu = nil
				local empty, emptyRoot = mount(plain, { motionLevel = "normal" })
				Verify.expect((empty.find("Plate"))):toBeNil()
				hover(emptyRoot, true)
				settle(empty, 1)
				Verify.expect((empty.find("Reveal"))):toBeNil()
				empty.stop()
			end,
		})

		verifyHarness:case(
			"lifts the card with a raised shadow for hover, selection and a held press and lands it after",
			{
				id = "native_card::native Card::lifts the card with a raised shadow for hover, selection and a held press and lands it after",
				run = function()
					local world, root = mount(cardSpec({}), { motionLevel = "normal" })
					Verify.expect((lift(root))):toBe("scale 1 shadow false")
					hover(root, true)
					settle(world, 1)
					Verify.expect((lift(root))):toBe("scale 1.04 shadow true")
					hover(root, false)
					settle(world, 1)
					Verify.expect((lift(root))):toBe("scale 1 shadow false")
					world.gui.SelectedObject = world.find("Body")
					settle(world, 1)
					Verify.expect((lift(root))):toBe("scale 1.04 shadow true")
					world.gui.SelectedObject = nil
					settle(world, 1)
					local body = world.find("Body")
					body.InputBegan:Fire({ UserInputType = world.engine.types.Enum.UserInputType.Touch })
					settle(world, 1)
					Verify.expect((lift(root))):toBe("scale 1.04 shadow true")
					body.InputEnded:Fire({ UserInputType = world.engine.types.Enum.UserInputType.Touch })
					settle(world, 1)
					Verify.expect((lift(root))):toBe("scale 1 shadow false")
					world.stop()
				end,
			}
		)

		local function stacked(reduced: FixtureComposeTypes.Cell<boolean>, container: string?): worlds.World
			local spec = cardSpec({})
			spec.image = nil
			spec.onActivate = nil
			local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
				return Host.Frame({
					Name = "Stack",
					Host.UIListLayout({}) :: unknown,
					UI.Card "C"(spec) :: unknown,
				})
			end, {
				motionLevel = Compose.formula(function(use: FixtureComposeTypes.Use): string
					return if use(reduced) then "none" else "normal"
				end),
			})
			if container then
				world.find("Stack"):AddTag(container)
			end
			world.engine.environment.poke(world.find("C"), "AbsoluteSize", world.V2(230, 137))
			return world
		end

		verifyHarness:case("gives a laid-out card its hug height back when its lift is cut off in motion", {
			id = "native_card::native Card::gives a laid-out card its hug height back when its lift is cut off in motion",
			run = function()
				local reduced = Compose.cell(false)
				local world = stacked(reduced)
				local root = world.find("C")
				local Enum = world.engine.types.Enum
				Verify.expect(root.AutomaticSize):toBe(Enum.AutomaticSize.Y)
				hover(root, true)
				settle(world, 0.1)
				Verify.expect(root.AutomaticSize):toBe(Enum.AutomaticSize.None)
				reduced:set(true)
				Verify.expect(root.AutomaticSize):toBe(Enum.AutomaticSize.Y)
				Verify.expect(root.Size.Y.Offset):toBe(0)
				reduced:set(false)
				hover(root, false)
				settle(world, 1)
				hover(root, true)
				settle(world, 0.1)
				hover(root, false)
				settle(world, 1)
				Verify.expect(root.AutomaticSize):toBe(Enum.AutomaticSize.Y)
				Verify.expect(root.Size.Y.Offset):toBe(0)
				world.stop()
			end,
		})

		verifyHarness:case(
			"keeps a laid-out card at its rest height while its lift paint is empty or not yet measured",
			{
				id = "native_card::native Card::keeps a laid-out card at its rest height while its lift paint is empty or not yet measured",
				run = function()
					local world = stacked(Compose.cell(false))
					local root = world.find("C")
					hover(root, true)
					world.engine.heartbeat:Fire(1 / 60)
					local paint = world.find("FeedbackPaint")
					Verify.expect(paint ~= nil):toBe(true)
					world.engine.environment.poke(paint, "AbsoluteSize", world.V2(230, 12))
					Verify.expect(root.Size.Y.Offset):toBe(137)
					settle(world, 0.05)
					Verify.expect(paint.Visible):toBe(true)
					world.engine.environment.poke(paint, "AbsoluteSize", world.V2(230, 12))
					Verify.expect(root.Size.Y.Offset):toBe(137)
					world.engine.environment.poke(paint, "AbsoluteSize", world.V2(230, 160))
					Verify.expect(root.Size.Y.Offset):toBe(160)
					world.stop()
				end,
			}
		)

		verifyHarness:case("keeps fractional rest bounds and their measurement probe outside the lifted paint", {
			id = "native_card::native Card::keeps fractional rest bounds and their measurement probe outside the lifted paint",
			run = function()
				local world = stacked(Compose.cell(false))
				local root = world.find("C")
				world.engine.environment.poke(root, "AbsoluteSize", world.V2(230, 137.4))
				hover(root, true)
				settle(world, 0.1)
				Verify.expect(root.Size.Y.Offset >= 137.4):toBe(true)
				Verify.expect(root:FindFirstChild("FeedbackUnit") ~= nil):toBe(true)
				Verify.expect(world.find("FeedbackPaint"):FindFirstChild("FeedbackUnit", true)):toBe(nil)
				world.stop()
			end,
		})

		verifyHarness:case(
			"keeps a lifted text card's panel and its color on its paint and clears only the parts inside it",
			{
				id = "native_card::native Card::keeps a lifted text card's panel and its color on its paint and clears only the parts inside it",
				run = function()
					for _, container in { "", "facet-sheet", "facet-panel" } do
						local world = stacked(Compose.cell(false), if container == "" then nil else container)
						local _, sheet = world.runtime.mount(function()
							return Facet.themes.createStyleSheet(world.runtime, Facet.themes.neutralPackage(), {
								types = world.engine.types,
							})
						end, world.engine.new("Folder"))
						local root = world.find("C")
						local rest = styleRules.resolve(sheet, root, "BackgroundColor3")
						hover(root, true)
						settle(world, 0.1)
						local paint = world.find("FeedbackPaint")
						Verify.expect(paint ~= nil and paint.Visible):toBe(true)
						Verify.expect(paint:HasTag("facet-card-text")):toBe(true)
						Verify.expect(styleRules.resolve(sheet, paint, "BackgroundTransparency")):toBe(0)
						Verify.expect(styleRules.resolve(sheet, paint, "BackgroundColor3")):toBe(rest)
						Verify.expect(styleRules.resolve(sheet, world.find("Body"), "BackgroundTransparency")):toBe(1)
						Verify.expect(styleRules.resolve(sheet, world.find("Plate"), "BackgroundTransparency")):toBe(1)
						world.stop()
					end
				end,
			}
		)

		verifyHarness:case("does not lift for touch presses or its menu, and lifts again for gamepad selection", {
			id = "native_card::native Card::does not lift for touch presses or its menu, and lifts again for gamepad selection",
			run = function()
				local world, root, controls = mount(cardSpec({}), { motionLevel = "normal" }, true)
				local Enum = world.engine.types.Enum
				world.engine.environment.poke(world.input, "PreferredInput", Enum.PreferredInput.Touch)
				local body = world.find("Body")
				body.InputBegan:Fire({ UserInputType = Enum.UserInputType.Touch })
				settle(world, 1)
				Verify.expect((lift(root))):toBe("scale 1 shadow false")
				body.InputEnded:Fire({ UserInputType = Enum.UserInputType.Touch })
				hover(root, true)
				settle(world, 1)
				Verify.expect((lift(root))):toBe("scale 1 shadow false")
				world.engine.environment.poke(primary(world), "GuiState", Enum.GuiState.Press)
				settle(world, 1)
				Verify.expect((lift(root))):toBe("scale 1 shadow false")
				world.engine.environment.poke(primary(world), "GuiState", Enum.GuiState.Idle)
				world.engine.environment.poke(more(world), "GuiState", Enum.GuiState.Press)
				settle(world, 1)
				Verify.expect((lift(root))):toBe("scale 1 shadow false")
				Verify.expect((controls.engaged:peek())):toBe(true)
				Verify.expect((controls.revealed:peek())):toBe(true)
				world.engine.environment.poke(more(world), "GuiState", Enum.GuiState.Idle)
				hover(root, false)
				world.engine.environment.poke(world.input, "PreferredInput", Enum.PreferredInput.Gamepad)
				world.gui.SelectedObject = body
				settle(world, 1)
				Verify.expect((lift(root))):toBe("scale 1.04 shadow true")
				world.stop()
			end,
		})

		verifyHarness:case("puts the card lift on its grid browse stop so the selection ring marks the lifted card", {
			id = "native_card::native Card::puts the card lift on its grid browse stop so the selection ring marks the lifted card",
			run = function()
				local g = gridWorld(12, false, false)
				local hit = g.hit("i1")
				g.world.gui.SelectedObject = hit
				settle(g.world, 1)
				Verify.expect(hit:FindFirstChild("CardLift").Scale):toBe(1.04)
				g.world.stop()
			end,
		})

		verifyHarness:case("reveals only the card whose grid browse stop is selected and moves with the selection", {
			id = "native_card::native Card::reveals only the card whose grid browse stop is selected and moves with the selection",
			run = function()
				local g = gridWorld(12)
				g.world.gui.SelectedObject = g.hit("i1")
				Verify.expect((attr(g.card("i1"), "Browsing"))):toBe(true)
				Verify.expect((attr(g.card("i1"), "Revealed"))):toBe(true)
				Verify.expect((attr(g.card("i2"), "Revealed"))):toBe(false)
				Verify.expect(g.card("i1"):FindFirstChild("Reveal").Parent):toBe(g.card("i1"))
				g.world.gui.SelectedObject = g.hit("i2")
				Verify.expect((attr(g.card("i1"), "Revealed"))):toBe(false)
				Verify.expect((attr(g.card("i2"), "Revealed"))):toBe(true)
				g.world.stop()
			end,
		})

		verifyHarness:case(
			"enters the actions at the first action, traps the selection and restores the stop on Cancel",
			{
				id = "native_card::native Card::enters the actions at the first action, traps the selection and restores the stop on Cancel",
				run = function()
					local g = gridWorld(12)
					local card = g.card("i2")
					g.world.gui.SelectedObject = g.hit("i2")
					g.hit("i2").Activated:Fire()
					Verify.expect(g.world.gui.SelectedObject):toBe(card:FindFirstChild("Primary", true))
					Verify.expect((attr(card, "Entered"))):toBe(true)
					Verify.expect(#g.log):toBe(0)
					local row = card:FindFirstChild("Row", true)
					Verify.expect(row.SelectionGroup):toBe(true)
					for _, side in { "Up", "Down", "Left", "Right" } do
						Verify.expect(row["SelectionBehavior" .. side].Name):toBe("Stop")
					end
					local trigger = card:FindFirstChild("More", true)
					g.world.gui.SelectedObject = trigger
					trigger.Activated:Fire()
					Verify.expect((attr(card, "MenuOpen"))):toBe(true)
					Verify.expect((g.world.action("CardCancel"))):toBeNil()
					g.world.action("ModalBack").Pressed:Fire()
					Verify.expect((attr(card, "MenuOpen"))):toBe(false)
					g.world.gui.SelectedObject = trigger
					g.world.action("CardCancel").Pressed:Fire()
					Verify.expect(g.world.gui.SelectedObject):toBe(g.hit("i2"))
					Verify.expect((attr(card, "Entered"))):toBe(false)
					Verify.expect(row.SelectionBehaviorRight.Name):toBe("Escape")
					Verify.expect((attr(card, "Revealed"))):toBe(true)
					Verify.expect(#g.log):toBe(0)
					g.world.stop()
				end,
			}
		)

		verifyHarness:case("leaves no trap, menu or controls behind when an entered card is removed or replaced", {
			id = "native_card::native Card::leaves no trap, menu or controls behind when an entered card is removed or replaced",
			run = function()
				local g = gridWorld(12)
				g.world.gui.SelectedObject = g.hit("i1")
				g.hit("i1").Activated:Fire()
				local trigger = g.card("i1"):FindFirstChild("More", true)
				g.world.gui.SelectedObject = trigger
				trigger.Activated:Fire()
				Verify.expect((attr(g.card("i1"), "MenuOpen"))):toBe(true)
				local rest = table.clone(g.sources.A:peek())
				table.remove(rest, 1)
				g.sources.A:set(rest)
				Verify.expect(g.controls.A.i1):toBeNil()
				Verify.expect((g.world.action("CardCancel"))):toBeNil()
				local selected = g.world.gui.SelectedObject
				Verify.expect(selected == nil or g.world.engine.environment.isAlive(selected)):toBe(true)
				local again = table.clone(rest)
				table.insert(again, 1, { id = "i1", title = "Back" })
				g.sources.A:set(again)
				Verify.expect((attr(g.card("i1"), "Entered"))):toBe(false)
				Verify.expect((attr(g.card("i1"), "MenuOpen"))):toBe(false)
				g.world.stop()
			end,
		})

		verifyHarness:case("recycles an entered card scrolled out of the window without stranding its trap", {
			id = "native_card::native Card::recycles an entered card scrolled out of the window without stranding its trap",
			run = function()
				local g = gridWorld(60)
				g.world.gui.SelectedObject = g.hit("i1")
				g.hit("i1").Activated:Fire()
				Verify.expect((attr(g.card("i1"), "Entered"))):toBe(true)
				g.world.find("A").CanvasPosition = g.world.V2(0, 4000)
				Verify.expect(g.controls.A.i1):toBeNil()
				local selected = g.world.gui.SelectedObject
				Verify.expect(selected == nil or g.world.engine.environment.isAlive(selected)):toBe(true)
				g.world.stop()
			end,
		})

		verifyHarness:case("keeps separate cards and entries in two grids with identical keys", {
			id = "native_card::native Card::keeps separate cards and entries in two grids with identical keys",
			run = function()
				local g = gridWorld(6, true)
				g.world.gui.SelectedObject = g.hit("i1", "B")
				g.hit("i1", "B").Activated:Fire()
				Verify.expect(g.world.gui.SelectedObject):toBe(g.card("i1", "B"):FindFirstChild("Primary", true))
				Verify.expect((attr(g.card("i1", "B"), "Entered"))):toBe(true)
				Verify.expect((attr(g.card("i1", "A"), "Entered"))):toBe(false)
				Verify.expect((attr(g.card("i1", "A"), "Revealed"))):toBe(false)
				g.world.stop()
			end,
		})

		verifyHarness:case("reserves authored gutters and the themed lift at the outer edges of a Card grid", {
			id = "native_card::native Card::reserves authored gutters and the themed lift at the outer edges of a Card grid",
			run = function()
				local scenario = require("../examples/gallery/scenarios/cards") :: any
				local built: any
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost, engine)
					built = scenario.build({
						UI = UI,
						Compose = Compose,
						Host = Host,
						types = engine.types,
						viewport = Compose.cell({ width = 1280, height = 720 }),
					})
					return built.screen()
				end, { motionLevel = "none" })
				local grid = world.find("Games")
				world.engine.environment.poke(grid, "AbsoluteWindowSize", world.V2(1248, 640))
				local columns, crossGap, gap =
					4, math.max(16, math.ceil(312 * 1.04) - 312), math.max(16, math.ceil(320 * 1.04) - 320)
				local padding = grid:FindFirstChild("Items"):FindFirstChildWhichIsA("UIPadding")
				local crossEdge = math.max(math.ceil(crossGap / 2), math.ceil(1248 / columns * (1.04 - 1)))
				local mainEdge = math.max(math.ceil(gap / 2), math.ceil(320 * (1.04 - 1)))
				Verify.expect(padding.PaddingLeft.Offset):toBe(crossEdge)
				Verify.expect(padding.PaddingRight.Offset):toBe(crossEdge)
				Verify.expect(padding.PaddingTop.Offset):toBe(mainEdge)
				local first = grid:FindFirstChild("Items"):FindFirstChild("g1")
				local width = first.Size.X.Offset
				Verify.expect(width):toBe(math.floor((1248 - 2 * crossEdge - crossGap * (columns - 1)) / columns))
				local grown = width * 1.04 - width
				Verify.expect(padding.PaddingLeft.Offset >= grown / 2):toBe(true)
				Verify.expect(crossGap >= grown):toBe(true)
				Verify.expect(padding.PaddingTop.Offset >= (320 * 1.04 - 320) / 2):toBe(true)
				local hit = first:FindFirstChild("RowHit", true)
				Verify.expect(hit.AnchorPoint):toBe(world.V2(0.5, 0.5))
				Verify.expect(hit.Position.X.Scale):toBe(0.5)
				Verify.expect(hit.Position.Y.Scale):toBe(0.5)
				Verify.expect((built.steps.enter("g1"))):toBe(true)
				Verify.expect(world.gui.SelectedObject.Name):toBe("Primary")
				world.action("Activate").Pressed:Fire()
				Verify.expect(built.report().last):toBe("Last action: play g1")
				local extent = grid.CanvasSize.Y.Offset
				Verify.expect(extent):toBe(15 * 320 + 14 * gap + 2 * mainEdge)
				grid.CanvasPosition = world.V2(0, 100000)
				Verify.expect(grid.CanvasPosition.Y):toBe(extent - 640)
				grid.CanvasPosition = world.V2(0, 0)
				Verify.expect(grid.CanvasPosition.Y):toBe(0)
				world.stop()
			end,
		})

		verifyHarness:case("mirrors the seal to the top-left in rtl and shows true as a status dot", {
			id = "native_card::native Card::mirrors the seal to the top-left in rtl and shows true as a status dot",
			run = function()
				local world = worlds.new(function(UI: FacetControls)
					return UI.badged(UI.Button({ Name = "Inbox", label = "Inbox" }), true, { direction = "rtl" })
				end)
				local wrapper = world.find("Inbox+badge")
				Verify.expect(world.find("Corner", wrapper).Position):toBe(UDim2.fromScale(0, 0))
				Verify.expect(world.find("CornerDot", wrapper).AnchorPoint):toBe(world.V2(0.5, 0.5))
				Verify.expect(world.find("CornerDot", wrapper).Text):toBe("")
				Verify.expect(world.find("CornerBadge", wrapper)):toBeNil()
				Verify.expect(world.find("Corner", wrapper).Parent:IsA("Folder")):toBe(true)
				Verify.expect(wrapper:FindFirstChildWhichIsA("UIListLayout") ~= nil):toBe(true)
				world.stop()
				Verify.expect(worlds.mountError(function(UI: FacetControls)
					return UI.badged(UI.Button({ label = "Inbox" }), 1, { direction = "up" :: any })
				end) ~= nil):toBe(true)
				Verify.expect(worlds.mountError(function(UI: FacetControls)
					return UI.badged(UI.Button({ label = "Inbox" }), 1.5)
				end) ~= nil):toBe(true)
			end,
		})

		verifyHarness:case("paints the seal in the error status unless the author names a status", {
			id = "native_card::native Card::paints the seal in the error status unless the author names a status",
			run = function()
				local status = Compose.cell("accent" :: FixtureMediaTypes.Status)
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.badged(UI.Button({ Name = "Daily", label = "Daily" }), true) :: unknown,
						UI.badged(UI.Button({ Name = "Shop", label = "Shop" }), true, { status = status }),
						UI.badged(UI.Button({ Name = "Inbox", label = "Inbox" }), 3),
						UI.badged(UI.Button({ Name = "Mail", label = "Mail" }), 3, { status = "warning" }),
					})
				end)
				local daily = world.find("CornerDot", world.find("Daily+badge"))
				local shop = world.find("CornerDot", world.find("Shop+badge"))
				Verify.expect((daily:HasTag("facet-status-error"))):toBe(true)
				Verify.expect((daily:HasTag("facet-status-neutral"))):toBe(false)
				Verify.expect((shop:HasTag("facet-status-accent"))):toBe(true)
				status:set("success")
				Verify.expect((shop:HasTag("facet-status-accent"))):toBe(false)
				Verify.expect((shop:HasTag("facet-status-success"))):toBe(true)
				local plain = world.find("CornerBadge", world.find("Inbox+badge"))
				Verify.expect(plain.Text):toBe("3")
				Verify.expect((plain:HasTag("facet-status-error"))):toBe(true)
				Verify.expect((plain:HasTag("facet-status-neutral"))):toBe(false)
				local mail = world.find("CornerBadge", world.find("Mail+badge"))
				Verify.expect((mail:HasTag("facet-status-warning"))):toBe(true)
				world.stop()
				Verify.expect(worlds.mountError(function(UI: FacetControls)
					local stray = ({ tone = "accent" } :: unknown) :: FixtureContentTypes.BadgedOptions
					return UI.badged(UI.Button({ label = "Inbox" }), true, stray)
				end) ~= nil):toBe(true)
			end,
		})

		verifyHarness:case("puts an icon tab count on the icon corner and a text tab count in a trailing pill", {
			id = "native_card::native Card::puts an icon tab count on the icon corner and a text tab count in a trailing pill",
			run = function()
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView({
						selection = Compose.cell("inbox"),
						placement = "topBar" :: "topBar",
						tabs = {
							{
								id = "inbox",
								label = "Inbox",
								icon = "menu",
								badge = 3,
								content = function(): Instance
									return Host.Frame({})
								end,
							} :: FixtureNavigationTypes.Tab,
							{
								id = "sent",
								label = "Sent",
								badge = 2,
								content = function(): Instance
									return Host.Frame({})
								end,
							} :: FixtureNavigationTypes.Tab,
						},
					})
				end)
				local tabs = world.find("Tabs")
				local inbox = world.find("inbox", tabs)
				local seal = inbox:FindFirstChild("CornerBadge", true)
				Verify.expect(seal ~= nil and seal.Text == "3"):toBe(true)
				Verify.expect((seal:HasTag("facet-status-error"))):toBe(true)
				Verify.expect(seal:FindFirstAncestorWhichIsA("ImageLabel") ~= nil):toBe(true)
				local sent = world.find("sent", tabs)
				Verify.expect((sent:FindFirstChild("CornerBadge", true))):toBeNil()
				Verify.expect(sent:FindFirstChild("Count", true).Text):toBe("2")
				Verify.expect((sent:GetAttribute("label"))):toBe("Sent (2)")
				world.stop()
				local pickers = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Picker("Icons")({
							style = "segmented" :: "segmented",
							selected = Compose.cell("a"),
							options = {
								{ value = "a", label = "Inbox", icon = "menu", badge = 3 } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "Sent", icon = "flag" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						}) :: unknown,
						UI.Picker("Words")({
							style = "segmented" :: "segmented",
							selected = Compose.cell("a"),
							options = {
								{ value = "a", label = "Inbox", badge = 3 } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "Sent" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						}),
					})
				end)
				local icons = pickers.find("Icons")
				local iconSeal = pickers.find("a", icons):FindFirstChild("CornerBadge", true)
				Verify.expect(iconSeal ~= nil and iconSeal.Text == "3"):toBe(true)
				Verify.expect(iconSeal:FindFirstAncestorWhichIsA("ImageLabel") ~= nil):toBe(true)
				local segment = pickers.find("a", icons)
				Verify.expect(segment.AutomaticSize.Name):toBe("X")
				Verify.expect(segment:FindFirstChildWhichIsA("UISizeConstraint").MinSize.X <= 44):toBe(true)
				local shown = {}
				for _, node in pickers.find("a", icons):GetDescendants() do
					if
						(node:IsA("TextLabel") or node:IsA("TextButton"))
						and node.Visible
						and node.TextTransparency < 1
						and node.Name ~= "CornerBadge"
						and node.Text ~= ""
					then
						table.insert(shown, node.Text)
					end
				end
				Verify.expect((table.concat(shown, ","))):toBe("Inbox")
				Verify.expect((pickers.find("b", icons):FindFirstChild("CornerBadge", true))):toBeNil()
				local words = pickers.find("a", pickers.find("Words"))
				Verify.expect((words:FindFirstChild("CornerBadge", true))):toBeNil()
				Verify.expect(words:FindFirstChild("Count", true).Text):toBe("3")
				Verify.expect((words:GetAttribute("label"))):toBe("Inbox (3)")
				pickers.stop()
			end,
		})
	end)

	return nil
end
