--!strict
local motion = require("./motion")
local reorder = require("./collection_reorder")
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local CollectionTypes = require("./collection_types")
local InputTypes = require("./input_types")
local InputProps = require("./input_props")
local Metrics = require("./collection_table_metrics")
return function<V, K>(
	ctx: Types.Context,
	UI: { Button: Types.Constructor<InputProps.ButtonProps, TextButton> },
	spec: CollectionTypes.TableShape<V, K>,
	editing: Types.ValueBoolean?,
	editor: reorder.Editor<V, K>?,
	metrics: Metrics.Metrics
): ComposeTypes.Directive
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local read = ctx.read
	local D2, V2, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local toolbarShown, toolbarHeight, preferredInput =
		metrics.toolbarShown, metrics.toolbarHeight, metrics.preferredInput
	return Compose.show(toolbarShown, function()
		local progress = runtime.tween(function(use: ComposeTypes.Use): number
			return if read(editing, use) then 1 else 0
		end, {
			seconds = function(use: ComposeTypes.Use): number
				local timing = ctx.motionTiming("reveal", use)
				return if read(editing, use) then timing.enter else timing.exit
			end,
			ease = ctx.motionEase("fade"),
			reducedMotion = motion.reduced(ctx),
		})
		local function fraction(use: ComposeTypes.Use): number
			return math.clamp(use(progress), 0, 1)
		end
		local button = UI.Button({
			Name = "Edit",
			label = function(use: ComposeTypes.Use): string
				return if read(editing, use) then "Done" else "Edit"
			end,
			AnchorPoint = V2.new(1, 0),
			Position = D2.fromScale(1, 0),
			Size = D2.new(0, 0, 1, 0),
			AutomaticSize = E.AutomaticSize.X,
			onActivate = function()
				local cell = (editing :: unknown) :: ComposeTypes.Cell<boolean>
				cell:set(not cell:peek())
			end,
		})
		local font, size = ctx.observeStyled.FontFace(button), ctx.observeStyled.TextSize(button)

		runtime.decorate(button, { TextTransparency = 1 })
		local function hideLabel(node: Instance)
			if node:IsA("TextLabel") and (node.Name == "Label" or node.Name == "Title") then
				node.TextTransparency = 1
			end
		end
		for _, node in button:GetDescendants() do
			hideLabel(node)
		end
		runtime.connect(button, "DescendantAdded", hideLabel)
		local function caption(word: string): TextLabel
			return ctx.styled(
				ctx.text({
					Name = word .. "Caption",
					Text = word,
					FontFace = font,
					TextSize = size,
					TextColor3 = ctx.observeStyled.TextColor3(button),
					TextXAlignment = E.TextXAlignment.Center,
					TextTransparency = function(use: ComposeTypes.Use)
						return if word == "Edit" then fraction(use) else 1 - fraction(use)
					end,
					Size = D2.fromScale(1, 1),
					AutomaticSize = E.AutomaticSize.None,
					Interactable = false,
				}),
				"button-caption"
			)
		end
		runtime.mountFragment(function()
			return { caption("Edit"), caption("Done") }
		end, button)
		local function reserve(word: string): TextLabel
			return ctx.text({
				Name = word,
				Text = word,
				TextTransparency = 1,
				FontFace = font,
				TextSize = size,
			})
		end
		runtime.mount(function()
			return Host.Frame({
				Name = "WidthReserve",
				BackgroundTransparency = 1,
				AutomaticSize = E.AutomaticSize.XY,
				reserve("Edit") :: ComposeTypes.Child,
				reserve("Done"),
			})
		end, button)
		local words: { string } = {}
		if spec.deletable then
			table.insert(words, "X Delete")
		end
		if spec.reorderable then
			table.insert(words, "L1 / R1 Move")
		end
		local function pad(use: ComposeTypes.Use): boolean
			return preferredInput ~= nil and use(preferredInput) == E.PreferredInput.Gamepad
		end
		local remove = if spec.deletable and editor
			then UI.Button {
				Name = "DeleteSelected",
				label = "Delete",
				role = "destructive" :: InputTypes.ButtonRole,
				Size = D2.new(0, 0, 1, 0),
				AutomaticSize = E.AutomaticSize.X,
				Visible = function(use: ComposeTypes.Use)
					return (read(editing, use) == true or fraction(use) > 0) and not pad(use)
				end,
				enabled = function(use: ComposeTypes.Use)
					return read(editing, use) == true and editor.canDeleteSelected(use)
				end,
				onActivate = editor.deleteSelected,
			}
			else nil
		return Host.Frame({
			Name = "Toolbar",
			BackgroundTransparency = 1,
			Size = function(use: ComposeTypes.Use)
				return D2.new(1, 0, 0, use(toolbarHeight) - ctx.metric("space.s", use))
			end,
			button :: ComposeTypes.Child,
			ctx.styled(
				ctx.text({
					Name = "PadHints",
					Text = table.concat(words, " · "),
					AnchorPoint = V2.new(0, 0.5),
					Position = D2.fromScale(0, 0.5),
					AutomaticSize = E.AutomaticSize.XY,
					Visible = function(use: ComposeTypes.Use)
						return read(editing, use) == true and pad(use)
					end,
				}),
				"secondary"
			),
			if remove
				then ctx.fade {
					Name = "DeleteFade",
					BackgroundTransparency = 1,
					Size = D2.new(0, 0, 1, 0),
					AutomaticSize = E.AutomaticSize.X,
					GroupTransparency = function(use: ComposeTypes.Use)
						return 1 - fraction(use)
					end,
					remove,
				}
				else nil,
		})
	end)
end
