--!strict
local ControlTypes = require("./control_types")
local Types = require("./types")
local Nav = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local Overlay = require("./overlay_types")
local InputProps = require("./input_props")
local NavigationProps = require("./navigation_props")
local surfaceParts = require("./nav_surface_parts")

return function(
	ctx: Types.Context,
	UI: ControlTypes.BuilderControls,
	surfaces: Nav.Surfaces,
	kit: surfaceParts.SurfaceParts
): ()
	local Host, Compose, runtime, read = ctx.Host, ctx.Compose, ctx.runtime, ctx.read
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local body, revealMotion = kit.body, kit.revealMotion
	UI.CollapsibleView = ctx.construct(
		"CollapsibleView",
		function(spec: NavigationProps.CollapsibleViewSpec): TextButton
			assert(
				type(spec.expanded) == "table" and spec.expanded.set,
				"CollapsibleView.expanded requires a writable Compose cell"
			)
			local buttonSpec: InputProps.ButtonProps & {
				content: Nav.Content?,
				expanded: ComposeTypes.Cell<boolean>?,
				initialFocus: string?,
				dismissButton: Nav.Value<boolean>?,
				outsideDismiss: Nav.Value<boolean>?,
			} =
				table.clone(spec)
			buttonSpec.content = nil
			buttonSpec.expanded = nil
			buttonSpec.initialFocus = nil
			buttonSpec.dismissButton = nil
			buttonSpec.outsideDismiss = nil
			buttonSpec.ref = nil
			buttonSpec.trailingIcon = spec.trailingIcon or "chevron.down"
			buttonSpec.corners = spec.corners or "pill"
			buttonSpec.onActivate = function()
				spec.expanded:set(not spec.expanded:peek())
			end
			local root = UI.Button(buttonSpec)
			local input = surfaces.service("UserInputService")
			local preferred = if input
				then ctx.observe.PreferredInput(input) :: ComposeTypes.Readable<Enum.PreferredInput?>
				else Compose.cell(nil :: Enum.PreferredInput?)
			local prepared, entered = Compose.cell(false), Compose.cell(false)
			Compose.watch(function(use: ComposeTypes.Use)
				entered:set(use(spec.expanded) and use(prepared))
			end)
			local progress, closed, opacity = revealMotion(entered)
			local function hidden(use: ComposeTypes.Use): number
				return if use(prepared) then opacity(use) else 1
			end
			local function collapse()
				spec.expanded:set(false)
			end
			local title = root:FindFirstChild("Title", true)
			if title and title:IsA("TextLabel") then
				runtime.decorate(title, { TextTruncate = E.TextTruncate.AtEnd, TextWrapped = false })
				runtime.mount(function()
					return Host.UIFlexItem({ FlexMode = E.UIFlexMode.Shrink })
				end, title)
			end
			local caret = root:FindFirstChild("TrailingIcon", true)
			if spec.trailingIcon == nil and caret and caret:IsA("GuiObject") then
				runtime.decorate(caret, {
					Rotation = function(use: ComposeTypes.Use)
						return 180 * progress(use)
					end,
				})
			end
			local rootBox, rootAt = ctx.observe.AbsoluteSize(root), ctx.observe.AbsolutePosition(root)
			surfaces.attach(root, {
				surfaces.overlay(root, spec.expanded, function(phase: Nav.PresencePhase?)
					prepared:set(false)
					Compose.cleanup(function()
						prepared:set(false)
					end)
					local layer = assert(surfaces.parent(root))
					local extent, origin = ctx.observe.AbsoluteSize(layer), ctx.observe.AbsolutePosition(layer)
					local column = ctx.column({
						body(spec.content),
						Compose.show(function(use: ComposeTypes.Use)
							return read(spec.dismissButton, use) ~= false or use(preferred) == E.PreferredInput.Gamepad
						end, function()
							return UI.Button "Close" { label = "Close", onActivate = collapse }
						end),
						ctx.padding(16, 16),
					}, { Name = "ExpandedBody", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y })
					local natural = ctx.observe.AbsoluteSize(column)
					local chrome = Compose.cell(V2.zero)
					local target = Compose.formula(function(use: ComposeTypes.Use): Overlay.Rect
						local room, offset, at, box = use(extent), use(origin), use(rootAt), use(rootBox)
						local margin = ctx.metric("space.s", use)
						local w = math.min(
							math.max(box.X, (ctx.metric("controls.popup.panelWidth", use))),
							math.max(0, room.X - 2 * margin)
						)
						local h =
							math.min(math.max(use(natural).Y + use(chrome).Y, box.Y), math.max(0, room.Y - 2 * margin))
						local x, y = at.X - offset.X, at.Y - offset.Y
						return {
							x = math.clamp(x, margin, math.max(margin, room.X - margin - w)),
							y = math.clamp(y, margin, math.max(margin, room.Y - margin - h)),
							w = w,
							h = h,
						}
					end)
					local function lerp(use: ComposeTypes.Use): Overlay.Rect
						local goal, at, offset = use(target), use(rootAt), use(origin)
						local t = if use(prepared) then progress(use) else 1
						local x, y = at.X - offset.X, at.Y - offset.Y
						return {
							x = x + (goal.x - x) * t,
							y = y + (goal.y - y) * t,
							w = goal.w,
							h = goal.h,
						}
					end
					local fade = ctx.fade {
						Name = "ExpandedFade",
						BackgroundTransparency = 1,
						Size = function(use: ComposeTypes.Use)
							local goal, inset = use(target), use(chrome)
							return D2.fromOffset(goal.w - inset.X, goal.h - inset.Y)
						end,
						GroupTransparency = 0,
						Host.ScrollingFrame "ExpandedScroll" {
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = D2.fromScale(1, 1),
							CanvasSize = function(use: ComposeTypes.Use)
								return D2.fromOffset(0, use(natural).Y)
							end,
							ScrollingDirection = E.ScrollingDirection.Y,
							ScrollBarThickness = 4,
							VerticalScrollBarInset = E.ScrollBarInset.ScrollBar,
							Selectable = false,
							column,
						},
					}
					local plate = surfaces.skin(ctx.styled(
						ctx.fade {
							Name = "Expanded",
							GroupTransparency = hidden,
							Active = true,
							BackgroundTransparency = 0,
							ClipsDescendants = true,
							Position = function(use: ComposeTypes.Use)
								local rect = lerp(use)
								return D2.fromOffset(rect.x, rect.y)
							end,
							Size = function(use: ComposeTypes.Use)
								local rect = lerp(use)
								return D2.fromOffset(rect.w, rect.h)
							end,
							fade,
							Host.Frame "ContentBox" {
								BackgroundTransparency = 1,
								Interactable = false,
								Size = D2.fromScale(1, 1),
							},
							ctx.corner(),
						},
						"panel"
					))
					ctx.styled(plate, "floating")
					local content = assert(plate:FindFirstChild("ContentBox", true)) :: GuiObject
					local plateBox, contentBox = ctx.observe.AbsoluteSize(plate), ctx.observe.AbsoluteSize(content)
					Compose.watch(function(use: ComposeTypes.Use)
						use(plateBox)
						use(contentBox)
						local outer, inner = plate.AbsoluteSize, content.AbsoluteSize
						if inner.X > 0 and inner.Y > 0 then
							chrome:set(outer - inner)
						end
					end)
					surfaces.atRest(function()
						return 0
					end, prepared, { plate, fade, column, content })
					local modal = surfaces.modal(
						function()
							return plate
						end,
						collapse,
						{
							Name = "CollapsibleModal",
							outsideMargin = 0,
							outsideDismiss = spec.outsideDismiss,
							backgroundTransparency = 1,
							initialFocus = spec.initialFocus,
							exiting = if phase then phase.exiting else nil,
							appearance = progress,
						}
					)
					surfaces.keep(spec.content)
					return modal
				end, {
					presence = {
						exit = function(): ComposeTypes.Exiting
							return { completed = closed }
						end,
					},
				}),
			})
			return root
		end
	)
end
