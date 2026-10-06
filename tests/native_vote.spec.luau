--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local FixtureContentTypes = require("../src/ui/content_types")
	local FixtureComposeTypes = require("../src/vendor/compose/core")

	local Facet = require("../src")
	local worlds = require("./lib/content_world")
	local Compose: ComposeModule = Facet.Compose

	local SEGMENT: { [string]: string } = { up = "Opt1", down = "Opt2" }

	local function mount(spec: any, extra: ((any) -> { any })?): any
		return worlds.new(function(UI: FacetControls, Host: RobloxHost)
			local children: { any } = { UI.Vote("V")(spec) }
			local additions: { any } = if extra then extra(UI) else {}
			for _, node in additions do
				table.insert(children, node)
			end
			return Host.Frame({ Name = "Row", table.unpack((children :: unknown) :: { unknown }) })
		end)
	end

	local function option(world: any, side: string, root: string?): any
		return world.find(SEGMENT[side], world.find(root or "V"))
	end

	local function painted(world: any, root: string?): string?
		local chosen: string? = nil
		for side in SEGMENT do
			local node = option(world, side, root)
			if node:HasTag("facet-segment-current") and node:GetAttribute("selected") == true then
				assert(chosen == nil, "two segments are painted")
				chosen = side
			end
		end
		return chosen
	end

	verifyHarness:suite("native Vote", function()
		verifyHarness:case("accepts, swaps in one change, and proposes none when the chosen side is pressed again", {
			id = "native_vote::native Vote::accepts, swaps in one change, and proposes none when the chosen side is pressed again",
			run = function()
				local value: FixtureComposeTypes.Cell<"down" | "none" | "up"> =
					Compose.cell("none" :: "down" | "none" | "up")
				local seen: { string } = {}
				local world: any
				world = mount({
					value = value,
					onChange = function(nextValue: "down" | "none" | "up")
						table.insert(seen, `{nextValue}<{value:peek()},{painted(world) or "nil"}>`)
						value:set(nextValue)
					end,
				})
				Verify.expect((painted(world))):toBeNil()
				option(world, "up").Activated.fire()
				Verify.expect((painted(world))):toBe("up")
				option(world, "down").Activated.fire()
				Verify.expect((painted(world))):toBe("down")
				option(world, "down").Activated.fire()
				Verify.expect((painted(world))):toBeNil()
				Verify.expect((table.concat(seen, " "))):toBe("up<none,nil> down<up,up> none<down,down>")
				world.stop()
			end,
		})

		verifyHarness:case("never paints a refused proposal and never touches the caller's cell", {
			id = "native_vote::native Vote::never paints a refused proposal and never touches the caller's cell",
			run = function()
				local value: FixtureComposeTypes.Cell<"down" | "none" | "up"> =
					Compose.cell("up" :: "down" | "none" | "up")
				local asked: { string } = {}
				local world = mount({
					value = value,
					onChange = function(nextValue: "down" | "none" | "up")
						table.insert(asked, nextValue)
					end,
				})
				option(world, "down").Activated.fire()
				option(world, "up").Activated.fire()
				Verify.expect((table.concat(asked, ","))):toBe("down,none")
				Verify.expect((value:peek())):toBe("up")
				Verify.expect((painted(world))):toBe("up")
				world.stop()
			end,
		})

		verifyHarness:case("proposes from a selected side through the keyboard Activate action", {
			id = "native_vote::native Vote::proposes from a selected side through the keyboard Activate action",
			run = function()
				local value: FixtureComposeTypes.Cell<"down" | "none" | "up"> =
					Compose.cell("none" :: "down" | "none" | "up")
				local world = mount({
					value = value,
					onChange = function(nextValue: "down" | "none" | "up")
						value:set(nextValue)
					end,
				})
				local down = option(world, "down")
				Verify.expect(down.Selectable):toBe(true)
				world.gui.SelectedObject = down
				local activate = world.action("Activate")
				Verify.expect(activate ~= nil):toBe(true)
				activate.Pressed.fire()
				Verify.expect((value:peek())):toBe("down")
				world.stop()
			end,
		})

		verifyHarness:case("reads a function value and keeps the last legal paint for an invalid late value", {
			id = "native_vote::native Vote::reads a function value and keeps the last legal paint for an invalid late value",
			run = function()
				local source = Compose.cell("up")
				local controls: FixtureContentTypes.Diagnostics = {}
				local world = mount({
					value = function(use: any)
						return use(source)
					end,
					controls = controls,
					onChange = function(nextValue: "down" | "none" | "up")
						source:set(nextValue)
					end,
				})
				Verify.expect((painted(world))):toBe("up")
				source:set("sideways")
				Verify.expect((painted(world))):toBe("up")
				Verify.expect(#assert(controls.diagnostics)()):toBe(1)
				source:set("down")
				Verify.expect((painted(world))):toBe("down")
				world.stop()
			end,
		})

		verifyHarness:case("leaves no stale state when a callback removes the vote", {
			id = "native_vote::native Vote::leaves no stale state when a callback removes the vote",
			run = function()
				local show = Compose.cell(true)
				local value: FixtureComposeTypes.Cell<"down" | "none" | "up"> =
					Compose.cell("none" :: "down" | "none" | "up")
				local world = worlds.new(function(UI: FacetControls)
					return Compose.show(show, function()
						return UI.Vote("V")({
							value = value,
							onChange = function(nextValue: "down" | "none" | "up")
								value:set(nextValue)
								show:set(false)
							end,
						})
					end)
				end)
				world.find("Opt1").Activated.fire()
				Verify.expect((value:peek())):toBe("up")
				Verify.expect((world.find("V"))):toBeNil()
				world.stop()
			end,
		})

		verifyHarness:case(
			"shows a read-only choice with nothing to press or select and uses ordinary disabled paint",
			{
				id = "native_vote::native Vote::shows a read-only choice with nothing to press or select and uses ordinary disabled paint",
				run = function()
					local readOnly = Compose.cell(true)
					local enabled = Compose.cell(true)
					local world =
						mount({ value = "up", readOnly = readOnly, enabled = enabled, onChange = function() end })
					local up = option(world, "up")
					Verify.expect((up:IsA("GuiButton"))):toBe(false)
					Verify.expect(up.Parent.Name):toBe("Plate")
					Verify.expect((up:HasTag("facet-segment-current"))):toBe(true)
					Verify.expect((up:HasTag("facet-disabled"))):toBe(false)
					readOnly:set(false)
					Verify.expect((option(world, "up"):IsA("GuiButton"))):toBe(true)
					Verify.expect(option(world, "up").Selectable):toBe(true)
					enabled:set(false)
					Verify.expect(option(world, "down").Selectable):toBe(false)
					Verify.expect((option(world, "down"):HasTag("facet-disabled"))):toBe(true)
					world.stop()
				end,
			}
		)

		verifyHarness:case("refuses to become interactive without onChange", {
			id = "native_vote::native Vote::refuses to become interactive without onChange",
			run = function()
				local readOnly = Compose.cell(true)
				local controls: FixtureContentTypes.Diagnostics = {}
				local world = mount({ value = "down", readOnly = readOnly, controls = controls })
				readOnly:set(false)
				Verify.expect((world.find("V"):GetAttribute("FacetReadOnly"))):toBe(true)
				Verify.expect((option(world, "down"):IsA("GuiButton"))):toBe(false)
				Verify.expect(#assert(controls.diagnostics)()):toBe(1)
				world.stop()
				Verify.expect(worlds.mountError(function(UI: FacetControls)
					return UI.Vote({ value = "none" } :: any)
				end) ~= nil):toBe(true)
				Verify.expect(worlds.mountError(function(UI: FacetControls)
					return UI.Vote({ value = "sideways", onChange = print } :: any)
				end) ~= nil):toBe(true)
				Verify.expect(worlds.mountError(function(UI: FacetControls)
					return UI.Vote({ value = "none", onChange = print, extra = true } :: any)
				end) ~= nil):toBe(true)
			end,
		})

		verifyHarness:case(
			"sizes each vote square to its rung, floors it at the touch target on touch, and discloses the summary",
			{
				id = "native_vote::native Vote::sizes each vote square to its rung, floors it at the touch target on touch, and discloses the summary",
				run = function()
					local a, b: FixtureComposeTypes.Cell<"down" | "none" | "up"> =
						Compose.cell("up"), Compose.cell("none" :: "down" | "none" | "up")
					local world = mount({
						value = a,
						summary = "99% liked",
						onChange = function(nextValue: "down" | "none" | "up")
							a:set(nextValue)
						end,
					}, function(UI: FacetControls)
						return {
							UI.Vote("W")({
								value = b,
								controlSize = "compact" :: "compact",
								onChange = function(nextValue: "down" | "none" | "up")
									b:set(nextValue)
								end,
							}),
							UI.Chip({ Name = "Tag", label = "Racing", selected = Compose.cell(false) }),
						}
					end)
					local targets = {}
					for _, root in { "V", "W" } do
						for side in SEGMENT do
							local node = option(world, side, root)
							Verify.expect(node.Size.X.Offset):toBe(if root == "W" then 36 else 44)
							Verify.expect(node.Size.Y.Offset):toBe(node.Size.X.Offset)
							Verify.expect((node:HasTag("facet-button-glyph"))):toBe(true)
							Verify.expect(targets[node]):toBeNil()
							targets[node] = true
						end
					end
					world.input.TouchEnabled = true
					for side in SEGMENT do
						local constraint = option(world, side, "W"):FindFirstChildWhichIsA("UISizeConstraint")
						Verify.expect(constraint.MinSize.X >= 44 and constraint.MinSize.Y >= 44):toBe(true)
					end
					Verify.expect((option(world, "up", "W"):GetAttribute("controlSize"))):toBe("compact")
					Verify.expect((option(world, "up"):GetAttribute("label"))):toBe("Upvote")
					Verify.expect((option(world, "down"):GetAttribute("label"))):toBe("Downvote")
					local summary = world.find("Summary", world.find("V"))
					Verify.expect(summary.Text):toBe("99% liked")
					Verify.expect((summary:GetAttribute("FacetLabel"))):toBe("99% liked")
					Verify.expect(summary.TextWrapped):toBe(false)
					Verify.expect(world.find("Summary", world.find("W")).Visible):toBe(false)
					Verify.expect((b:peek())):toBe("none")
					world.stop()
				end,
			}
		)

		verifyHarness:case("repaints the Choices vote only from its caller's value and follows the summary", {
			id = "native_vote::native Vote::repaints the Choices vote only from its caller's value and follows the summary",
			run = function()
				local scenario = require("../examples/gallery/scenarios/selection_controls") :: any
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost, engine)
					local viewport = Compose.cell({ width = 1000, height = 800 })
					return scenario
						.build({
							UI = UI,
							Compose = Compose,
							Host = Host,
							types = engine.types,
							viewport = viewport,
							Facet = Facet,
						})
						.screen()
				end)
				local track = world.find("TrackVote")
				local summary = world.find("Summary", track)
				Verify.expect(summary.Text):toBe("98% liked this")
				world.find("Opt1", track).Activated.fire()
				Verify.expect(summary.Text):toBe("You and 98% liked this")
				Verify.expect((world.find("Opt1", track):HasTag("facet-segment-current"))):toBe(true)
				local past = world.find("PastVote")
				Verify.expect((world.find("Opt2", past):IsA("GuiButton"))):toBe(false)
				Verify.expect((world.find("Opt2", past):HasTag("facet-segment-current"))):toBe(true)
				world.stop()
			end,
		})
	end)

	return nil
end
