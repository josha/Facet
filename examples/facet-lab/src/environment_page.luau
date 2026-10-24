--!strict

type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T

local CatalogTypes = require("./catalog_types")
type Context = CatalogTypes.Context
type Properties = CatalogTypes.Properties

local page: CatalogTypes.PageDefinition = {
	host = "Screen",
	family = "facet",
	alias = "Environment (size class, input, safe area)",
	purpose = "Engine facts a screen adapts to: viewport, size and height class, orientation, input, display size, safe insets, text size, reduced motion.",
	alternatives = "Observe one container's AbsoluteSize for a local decision.",
	snippet = "local env = UI.environment(); env.sizeClass, env.interactionClasses, …",
	base = function()
		return {}
	end,
	axes = { { key = "source", values = { "viewport", "this box" } } },
	states = {},
	make = function(UI: FacetControls, p: Properties, c: Context): Instance
		local text = c.Compose.cell("")
		local label = UI.Text({
			text = text,
			wrap = true,
			Size = UDim2.fromOffset(320, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		})
		local env = if p.source == "this box" then UI.environment(label) else UI.environment()
		c.Compose.watch(function(use: Use)
			local size = use(env.viewportSize)
			local ic = use(env.interactionClasses)
			local inset = use(env.safeInsets)
			local topbar = use(env.topbarInset)
			text:set(table.concat({
				`viewport {math.floor(size.X)}×{math.floor(size.Y)} ({use(env.viewportWidth)} wide, {use(
					env.viewportHeight
				)} high)`,
				`sizeClass {use(env.sizeClass)} · heightClass {use(env.heightClass)} · {use(env.orientation)} · axis {use(
					env.axis
				)}`,
				`compact {tostring(use(env.isCompact))} · regular {tostring(use(env.isRegular))} · regular+ {tostring(
					use(env.isRegularOrWider)
				)} · wide {tostring(use(env.isWide))} · short {tostring(use(env.isShort))} · tall {tostring(
					use(env.isTall)
				)} · landscape {tostring(use(env.isLandscape))}`,
				`input {ic.primary} (pointer {tostring(ic.pointer)}, touch {tostring(ic.touch)}, gamepad {tostring(
					ic.gamepad
				)}, keyboard {tostring(ic.keyboard)}) · effective {use(env.effectiveInput)}`,
				`display {use(env.displaySize)} · text {use(env.preferredTextSize)} · motion {use(
					env.motionLevel
				)}`,
				`safe insets t{inset.top} l{inset.left} b{inset.bottom} r{inset.right}`,
				`topbar {topbar.Width}×{topbar.Height} at {topbar.Min.X},{topbar.Min.Y}`,
				`topbar control diameter {use(env.topbarControlDiameter)}`,
				`thumb target {use(env.thumbTarget)}`,
			}, "\n"))
		end)
		local atLeast = env.atLeast("regular")
		local function square(name: string, side: Readable<number>, caption: string): Instance
			return UI.VStack(name)({
				gap = "xs",
				align = "center",
				c.Host.Frame({
					Name = "Square",
					BackgroundColor3 = Color3.fromRGB(120, 140, 220),
					Size = function(use: Use): UDim2
						local edge = math.floor(use(side) + 0.5)
						return UDim2.fromOffset(edge, edge)
					end,
				}),
				UI.Text({
					text = function(use: Use)
						return `{caption} = {math.floor(use(side) + 0.5)}`
					end,
					textRole = "caption",
				}),
			})
		end
		return UI.VStack({
			gap = "xs",
			label,
			UI.Text({
				text = function(use: Use)
					return `atLeast("regular") = {tostring(use(atLeast))}`
				end,
				textRole = "caption",
			}),
			UI.HStack({
				gap = "m",
				align = "end",
				square("Scaled", env.scaled(48), "scaled(48)"),
				square("ScaledBody", env.scaled(48, "body"), 'scaled(48, "body")'),
			}),
		})
	end,
	surface = "UI.environment",
}

return page
