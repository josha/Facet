--!strict

type ExampleContext = typeof(require("@repo/examples/types").Context)
type Child = typeof(require("@repo/tools/typecheck/aliases").Child)
type StackProps = typeof(require("@repo/tools/typecheck/aliases").StackProps)
type ReadOnlyValue<T> = typeof(require("@repo/src/vendor/compose/core").accumulator<<T, number>>(nil :: never))
type Use = <T>(ReadOnlyValue<T>) -> T
type Input<T> = T | ReadOnlyValue<T> | (Use) -> T
return function(ctx: ExampleContext)
	local Host, UI, Compose = ctx.Host, ctx.UI, ctx.Compose
	local D, D2, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Enum
	local view = {}
	function view.text(label: Input<string>, size: number?): GuiObject
		return UI.Text {
			text = label,
			TextSize = size or 16,
			TextWrapped = true,
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
		}
	end
	function view.column(name: string, children: { Child }, spacing: number?): Frame
		local props: StackProps = {
			Name = name,
			width = "fill",
			gap = spacing or 12,
		}
		for _, child in children do
			props[#props + 1] = child
		end
		return UI.VStack(props)
	end
	function view.page(name: string, children: { Child }): ScrollingFrame
		return Host.ScrollingFrame(name)({
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = D2.fromScale(1, 1),
			CanvasSize = D2.fromOffset(0, 0),
			AutomaticCanvasSize = E.AutomaticSize.Y,
			ScrollBarThickness = 6,
			Host.UIPadding {
				PaddingTop = D.new(0, 16),
				PaddingBottom = D.new(0, 16),
				PaddingLeft = D.new(0, 16),
				PaddingRight = D.new(0, 16),
			},
			Host.UIListLayout { SortOrder = E.SortOrder.LayoutOrder },
			view.column("Content", children, 16),
		})
	end
	function view.action(
		name: string,
		label: Input<string>,
		command: (InputObject?, number?) -> (),
		enabled: Input<boolean>?
	): TextButton
		return UI.Button {
			Name = name,
			label = label,
			onActivate = command,
			enabled = enabled,
			Size = D2.new(1, 0, 0, 44),
			AutomaticSize = E.AutomaticSize.None,
		}
	end
	function view.watch<T>(source: (Use) -> { T }, render: (ReadOnlyValue<T>, string) -> GuiObject, id: (T) -> string)
		return Compose.keyed({
			from = source,
			key = function(item: T): string
				return id(item)
			end,
			render = function(current: ReadOnlyValue<T>, index: ReadOnlyValue<number>, key: string): GuiObject
				local node = render(current, key)
				ctx.runtime.decorate(node, { LayoutOrder = index })
				return node
			end,
		})
	end
	function view.list<T>(items: { T }, render: (ReadOnlyValue<T>, string) -> GuiObject, id: (T) -> string)
		return view.watch(function(): { T }
			return items
		end, render, id)
	end
	return view
end
