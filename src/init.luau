--!strict
local Compose = require("@self/vendor/compose/core")
local Roblox = require("@self/vendor/compose/roblox")
local ControlTypes = require("@self/ui/control_types")
local SharedTypes = require("@self/ui/types")
local CollectionProps = require("@self/ui/collection_props")
local ContentProps = require("@self/ui/content_props")
local EffectProps = require("@self/ui/effect_props")
local InputProps = require("@self/ui/input_props")
local LayoutProps = require("@self/ui/layout_props")
local MediaProps = require("@self/ui/media_props")
local NavigationProps = require("@self/ui/navigation_props")
local OverlayProps = require("@self/ui/overlay_props")
local RadialProps = require("@self/ui/radial_props")
local ZoomTravelProps = require("@self/ui/zoom_travel_props")
local createControls: ControlTypes.Factory = require("@self/ui")
local bindThemes = require("@self/ui/themes")
local InputTypes = require("@self/ui/input_types")
local CommandTypes = require("@self/ui/command_types")
export type CommandTarget<K> = CommandTypes.CommandTarget<K>
export type Command<K> = CommandTypes.Command<K>
export type CommandSpec<K> = CommandTypes.CommandSpec<K>
export type CommandScope<K> = CommandTypes.CommandScope<K>
local NavigationTypes = require("@self/ui/navigation_types")
local RadialTypes = require("@self/ui/radial_types")
local CollectionTypes = require("@self/ui/collection_types")
local MediaTypes = require("@self/ui/media_types")
local ContentTypes = require("@self/ui/content_types")
local ThemeTypes = require("@self/ui/theme_types")
local LayoutTypes = require("@self/ui/layout_types")
local createApp = require("@self/ui/app")
local OverlayTypes = require("@self/ui/overlay_types")
local civilDate = require("@self/ui/civil_date")
local CivilTypes = require("@self/ui/civil_date_types")
local arithmetic = require("@self/ui/arithmetic")
local adaptive = require("@self/ui/adaptive")
local gamepadContention = require("@self/ui/gamepad_contention")
local pathShapes = require("@self/ui/nav_path_shapes")
local richText = require("@self/ui/rich_text")
local GestureTypes = require("@self/ui/gesture_arbitration")
local EnvironmentTypes = require("@self/ui/environment_types")
local freeze = require("@self/ui/freeze")
local EffectTypes = require("@self/ui/effect_types")
export type SequenceStep = EffectTypes.SequenceStep
export type SequenceSpec = EffectTypes.SequenceSpec
export type Sequence = EffectTypes.Sequence
export type FlashProps = EffectProps.FlashProps
local ZoomTravelTypes = require("@self/ui/zoom_travel_types")
export type ZoomViewProps = ZoomTravelProps.ZoomViewProps
export type ZoomControls = ZoomTravelTypes.ZoomControls
export type ZoomRect = ZoomTravelTypes.Rect
export type TravelProps = ZoomTravelProps.TravelProps
export type NavigationSplitViewProps = NavigationProps.NavigationSplitViewProps
export type ButtonProps = InputProps.ButtonProps
export type ToggleProps = InputProps.ToggleProps
export type TextInputProps = InputProps.TextInputProps
export type NumberInputProps = InputProps.NumberInputProps
export type StepperProps = InputProps.StepperProps
export type SliderProps = InputProps.SliderProps
export type RatingProps = InputProps.RatingProps
export type LevelPickerProps = InputProps.LevelPickerProps
export type ChipProps = InputProps.ChipProps
export type ShortcutHintProps = InputProps.ShortcutHintProps
export type MenuItem<V = string> = NavigationTypes.MenuItem<V>
export type MenuSpec<V = string> = NavigationProps.MenuSpec<V>
export type PickerOption<V = string> = NavigationTypes.PickerOption<V>
export type PickerSpec<V = string> = NavigationProps.PickerSpec<V>
export type SplitButtonSpec<V = string> = NavigationProps.SplitButtonSpec<V>
export type ComboBoxSpec = NavigationProps.ComboBoxSpec
export type DisclosureGroupSpec = NavigationProps.DisclosureGroupSpec
export type CollapsibleViewSpec = NavigationProps.CollapsibleViewSpec
export type AlertAction<P = unknown> = NavigationTypes.AlertAction<P>
export type AlertSpec<P = unknown> = NavigationProps.AlertSpec<P>
export type SheetDetent = NavigationTypes.SheetDetent
export type SheetSpec = NavigationProps.SheetSpec
export type CalloutSpec = NavigationProps.CalloutSpec
export type Tab = NavigationTypes.Tab
export type TabViewSpec = NavigationProps.TabViewSpec
export type NavigationEntry<P = unknown> = NavigationTypes.NavigationEntry<P>
export type NavigationDestination<P = unknown> = NavigationTypes.NavigationDestination<P>
export type NavigationStackSpec<P = unknown> = NavigationProps.NavigationStackSpec<P>
export type PageViewSpec = NavigationProps.PageViewSpec
export type RadialItem<V = string> = RadialTypes.RadialItem<V>
export type RadialMenuSpec<V = string> = RadialProps.RadialMenuSpec<V>
export type SlotControls<K> = CollectionTypes.SlotControls<K>
export type KeyedCollectionSpec<V, K> = CollectionProps.KeyedCollectionSpec<V, K>
export type IdentityCollectionSpec<V> = CollectionProps.IdentityCollectionSpec<V>
export type CollectionSpec<V, K> = CollectionProps.CollectionSpec<V, K>
export type RowAction = CollectionTypes.RowAction
export type RowActionsOptions = CollectionProps.RowActionsOptions
export type RowActionsSpec = CollectionProps.RowActionsSpec
export type CellDraft = CollectionTypes.CellDraft
export type CellEditorSpec = CollectionProps.CellEditorSpec
export type TableColumn<V, K> = CollectionTypes.TableColumn<V, K>
export type KeyedTableSpec<V, K> = CollectionProps.KeyedTableSpec<V, K>
export type IdentityTableSpec<V> = CollectionProps.IdentityTableSpec<V>
export type TableSpec<V, K> = CollectionProps.TableSpec<V, K>
export type OutlineSpec<V, K> = CollectionProps.OutlineSpec<V, K>
export type HierarchyOptions<V, K> = CollectionTypes.HierarchyOptions<V, K>
export type TextProps = MediaProps.TextProps
export type LabelProps = MediaProps.LabelProps
export type ImageProps = MediaProps.ImageProps
export type BadgeProps = MediaProps.BadgeProps
export type StatusIndicatorProps = MediaProps.StatusIndicatorProps
export type PathProps = MediaProps.PathProps
export type PathPoint = MediaTypes.PathPoint
export type ProgressViewProps = MediaProps.ProgressViewProps
export type SkeletonProps = MediaProps.SkeletonProps
export type ImageResource = MediaTypes.ImageResource
export type AsyncImageProps = MediaProps.AsyncImageProps
export type AvatarProps = MediaProps.AvatarProps
export type AvatarMember = MediaTypes.AvatarMember
export type AvatarGroupProps = MediaProps.AvatarGroupProps
export type StageProps = MediaProps.StageProps
export type PaginationSpec = ContentProps.PaginationSpec
export type StepIndicatorSpec = ContentProps.StepIndicatorSpec
export type Step = ContentTypes.Step
export type VoteSpec = ContentProps.VoteSpec
export type CardSpec = ContentProps.CardSpec
export type CardControls = ContentTypes.CardControls
export type BadgeValue = ContentTypes.BadgeValue
export type Space = LayoutTypes.Space
export type Padding = LayoutTypes.Padding
export type Extent = LayoutTypes.Extent
export type StackProps = LayoutProps.StackProps
export type ScreenProps = LayoutProps.ScreenProps
export type ZStackProps = LayoutProps.ZStackProps
export type ScrollViewProps = LayoutProps.ScrollViewProps
export type GridProps = LayoutProps.GridProps
export type AdaptiveStackProps = LayoutProps.AdaptiveStackProps
export type ViewThatFitsProps = LayoutProps.ViewThatFitsProps
export type ErrorBoundaryProps = LayoutProps.ErrorBoundaryProps
export type DividerProps = LayoutProps.DividerProps
export type SpacerProps = LayoutProps.SpacerProps
export type CompositionProps = LayoutProps.CompositionProps
export type RegionProps = LayoutProps.RegionProps
export type Zone = LayoutTypes.Zone
export type OverlayAction = OverlayTypes.Action
export type DialogAction = OverlayTypes.DialogAction
export type OverlayMedia = OverlayTypes.Media
export type OverlayHero = OverlayTypes.Hero
export type DialogSpec = OverlayProps.DialogSpec
export type PopoverSpec = OverlayProps.PopoverSpec
export type NoticeSpec = OverlayProps.NoticeSpec
export type NavBarSpec = OverlayProps.NavBarSpec
export type ToastSpec = OverlayProps.ToastSpec
export type DateTimePickerProps = InputProps.DateTimePickerProps
export type ColorPickerProps = InputProps.ColorPickerProps
export type Controls = ControlTypes.Controls
export type Host = SharedTypes.Host
export type Child = SharedTypes.Child
export type Environment = EnvironmentTypes.Environment
export type InteractionClasses = EnvironmentTypes.InteractionClasses
export type SafeInsets = EnvironmentTypes.SafeInsets
export type WorldAnchorOptions = EnvironmentTypes.WorldAnchorOptions
export type WorldAnchor = EnvironmentTypes.WorldAnchor
export type ScrollOptions = EnvironmentTypes.ScrollOptions
export type GestureKind = GestureTypes.Kind
export type GestureOptions = GestureTypes.Options
export type GestureDecision = GestureTypes.Decision
export type GestureBinding = GestureTypes.Binding
export type DraggableSpec = EnvironmentTypes.DraggableSpec
export type DropTargetSpec = EnvironmentTypes.DropTargetSpec
export type DropInfo = EnvironmentTypes.DropInfo
export type DropOperation = EnvironmentTypes.DropOperation
export type DropDestination = EnvironmentTypes.DropDestination
export type DropInsertion = EnvironmentTypes.DropInsertion
export type AdjustableOptions = InputTypes.AdjustableOptions
export type HapticKind = InputTypes.HapticKind
export type Adaptive = adaptive.Adaptive
export type App = createApp.App
export type AppOptions = createApp.AppOptions
export type Component = createApp.Component
export type AnchoredOptions = createApp.AnchoredOptions
export type ToastOptions = createApp.ToastOptions
export type ControlOptions = ControlTypes.Config
export type ThemePackage = ThemeTypes.ThemePackage
export type CivilDate = CivilTypes.CivilDate
export type CivilRange = CivilTypes.Range
export type CivilLocale = CivilTypes.Locale
export type CivilDateModule = CivilTypes.Module
export type Cell<T> = Compose.Cell<T>
export type Readable<T> = Compose.Readable<T>
export type Runtime = Compose.Runtime
export type Owner = Compose.Owner
export type Use = Compose.Use
export type ComposeModule = typeof(Compose)
export type ComposeRobloxModule = typeof(Roblox)
export type Facet = {
	VERSION: string,
	COMPOSE_COMMIT: string,
	Compose: ComposeModule,
	Roblox: ComposeRobloxModule,
	controls: (Runtime, ControlOptions?) -> Controls,
	host: (Runtime) -> Host,
	app: (AppOptions?) -> App,
	themes: ThemeTypes.Themes,
	civilDate: CivilTypes.Module,
	adaptive: adaptive.Adaptive,
	gamepadContention: gamepadContention.GamepadContention,
	pathShapes: typeof(pathShapes),
	richText: typeof(richText),
	recipes: { arithmetic: { parse: (unknown) -> number? } },
	inputPriority: { belowControls: number, aboveFacet: number },
	bind: (ComposeModule, ComposeRobloxModule) -> Facet,
}

local VERSION = "0.12.0"
local INPUT_PRIORITY = table.freeze({ belowControls = 25, aboveFacet = 12000 })
local COMPOSE_COMMIT = "1836eaaa4da1e39046d9a3176be768890cf50731"
local USED = {
	"boundary",
	"cell",
	"cleanup",
	"createFocusScope",
	"createPool",
	"createSharedResource",
	"currentOwner",
	"focusNeighbor",
	"formula",
	"fragment",
	"isReadable",
	"keyed",
	"portal",
	"presence",
	"sharedCell",
	"show",
	"static",
	"switch",
	"watch",
	"withOwner",
	"withRootOwner",
}

local recipes: { arithmetic: { parse: (unknown) -> number? } } =
	freeze({ arithmetic = freeze({ parse = arithmetic.parse }) })

local function bind(core: ComposeModule, roblox: ComposeRobloxModule): Facet
	local fields = (core :: unknown) :: { [string]: unknown }
	for _, name in USED do
		if type(fields[name]) ~= "function" then
			error(
				`Facet.bind: this Compose has no function '{name}'. Facet {VERSION} supports Compose `
					.. `{string.sub(COMPOSE_COMMIT, 1, 7)} and later commits that keep the functions Facet uses.`,
				2
			)
		end
	end
	if type(roblox) ~= "table" or type(roblox.createRuntime) ~= "function" then
		error("Facet.bind: pass the Compose Roblox module from the same Compose copy as the second argument", 2)
	end
	local themes = bindThemes(core)
	local surface: Facet
	surface = freeze({
		VERSION = VERSION,
		COMPOSE_COMMIT = COMPOSE_COMMIT,
		Compose = core,
		Roblox = roblox,
		controls = function(runtime: Runtime, options: ControlOptions?): Controls
			return createControls(core, runtime, options)
		end,
		host = function(runtime: Runtime): Host
			if type(runtime) ~= "table" or type(runtime.constructors) ~= "table" then
				error("Facet.host: pass a Compose runtime", 2)
			end
			return (runtime.constructors :: unknown) :: Host
		end,
		app = function(options: AppOptions?): App
			return createApp(core, roblox, createControls, themes, options)
		end,
		themes = themes,
		civilDate = civilDate,
		adaptive = adaptive,
		gamepadContention = gamepadContention,
		pathShapes = pathShapes,
		richText = richText,
		recipes = recipes,
		inputPriority = INPUT_PRIORITY,
		bind = bind,
	})
	return surface
end

return bind(Compose, Roblox)
