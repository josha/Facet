--!strict
local Compose = require("@self/vendor/compose/core")
local Roblox = require("@self/vendor/compose/roblox")
local ComposeDesign = require("@self/vendor/compose/design")
local FacetDesign = require("@self/design")
local ControlTypes = require("@self/ui/control_types")
local DiegeticTypes = require("@self/ui/diegetic_types")
export type DiegeticScreenProps = DiegeticTypes.DiegeticScreenProps
local SharedTypes = require("@self/ui/types")
local CollectionProps = require("@self/ui/collection_props")
local SpatialProps = require("@self/ui/spatial_grid_props")
local ContentProps = require("@self/ui/content_props")
local EffectProps = require("@self/ui/effect_props")
local InputProps = require("@self/ui/input_props")
local LayoutProps = require("@self/ui/layout_props")
local MediaProps = require("@self/ui/media_props")
local HudProps = require("@self/ui/hud_props")
local HudTypes = require("@self/ui/hud_types")
local format = require("@self/ui/format")
export type TimerProps = HudProps.TimerProps
export type WorldMarkerProps = HudProps.WorldMarkerProps
export type TimerControls = HudTypes.TimerControls
export type TypewriterProps = HudProps.TypewriterProps
export type TypewriterControls = HudTypes.TypewriterControls
export type CompactOptions = format.CompactOptions
export type GroupedOptions = format.GroupedOptions
export type DurationOptions = format.DurationOptions
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
local ColorPickerTypes = require("@self/ui/color_picker_types")
local DateTimePickerTypes = require("@self/ui/date_time_picker_types")
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
export type ShakeOptions = EffectTypes.ShakeOptions
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
export type ToggleCellProps = InputProps.ToggleCellProps
export type ToggleRequestProps = InputProps.ToggleRequestProps
export type TextInputCellProps = InputProps.TextInputCellProps
export type TextInputRequestProps = InputProps.TextInputRequestProps
export type TextInputNumberCellProps = InputProps.TextInputNumberCellProps
export type TextInputNumberRequestProps = InputProps.TextInputNumberRequestProps
export type NumberInputCellProps = InputProps.NumberInputCellProps
export type NumberInputRequestProps = InputProps.NumberInputRequestProps
export type StepperCellProps = InputProps.StepperCellProps
export type StepperRequestProps = InputProps.StepperRequestProps
export type SliderCellProps = InputProps.SliderCellProps
export type SliderRequestProps = InputProps.SliderRequestProps
export type SliderRangeProps = InputProps.SliderRangeProps
export type RatingCellProps = InputProps.RatingCellProps
export type RatingRequestProps = InputProps.RatingRequestProps
export type RatingReadOnlyProps = InputProps.RatingReadOnlyProps
export type LevelPickerCellProps = InputProps.LevelPickerCellProps
export type LevelPickerRequestProps = InputProps.LevelPickerRequestProps
export type LevelPickerReadOnlyProps = InputProps.LevelPickerReadOnlyProps
export type ChipCellProps = InputProps.ChipCellProps
export type ChipRequestProps = InputProps.ChipRequestProps
export type ChipRemovableProps = InputProps.ChipRemovableProps
export type ShortcutHintKeysProps = InputProps.ShortcutHintKeysProps
export type ShortcutHintActionProps = InputProps.ShortcutHintActionProps
export type ButtonGuideProps = InputProps.ButtonGuideProps
export type ButtonGuideEntry = InputTypes.ButtonGuideEntry
export type ButtonRole = InputTypes.ButtonRole
export type TextCommitReason = InputTypes.TextCommitReason
export type CommitReason = InputTypes.CommitReason
export type ClearButtonMode = InputTypes.ClearButtonMode
export type MenuItem<V = string> = NavigationTypes.MenuItem<V>
export type MenuCommand = NavigationTypes.MenuCommand
export type MenuSpec<V = string> = NavigationProps.MenuSpec<V>
export type PickerOption<V = string> = NavigationTypes.PickerOption<V>
export type PickerSpec<V = string> = NavigationProps.PickerSpec<V>
export type SinglePickerSpec<V = string> = NavigationProps.SinglePickerSpec<V>
export type MultiplePickerSpec<V = string> = NavigationProps.MultiplePickerSpec<V>
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
export type RadialAction<V = string> = RadialTypes.RadialAction<V>
export type RadialMenuSpec<V = string> = RadialProps.RadialMenuSpec<V>
export type SlotControls<K> = CollectionTypes.SlotControls<K>
export type FocusControls<K> = CollectionTypes.FocusControls<K>
export type CollectionPlacement = Compose.Placement
export type Transition = NavigationTypes.Transition
export type TransitionContext = NavigationTypes.TransitionContext
export type SpatialPlacement = EnvironmentTypes.DropPlacement
export type SpatialGridSpec<V, K> = SpatialProps.SpatialGridSpec<V, K>
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
export type KeyedOutlineSpec<V, K> = CollectionProps.KeyedOutlineSpec<V, K>
export type IdentityOutlineSpec<V> = CollectionProps.IdentityOutlineSpec<V>
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
export type CardAction = ContentTypes.CardAction
export type CardMenu = ContentTypes.CardMenu
export type CardBadge = ContentTypes.CardBadge
export type CardBadges = ContentTypes.CardBadges
export type BadgeValue = ContentTypes.BadgeValue
export type BadgedOptions = ContentTypes.BadgedOptions
export type Space = LayoutTypes.Space
export type Padding = LayoutTypes.Padding
export type Sides = LayoutTypes.Sides
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
export type ActionRole = OverlayTypes.ActionRole
export type ToastAction = OverlayTypes.ToastAction
export type PopoverSource = OverlayTypes.PopoverSource
export type OverlayRect = OverlayTypes.Rect
export type DialogDismissReason = OverlayTypes.DialogDismissReason
export type PopoverDismissReason = OverlayTypes.PopoverDismissReason
export type ToastDismissReason = OverlayTypes.ToastDismissReason
export type NoticeSeverity = OverlayTypes.NoticeSeverity
export type ColorSwatch = ColorPickerTypes.Swatch
export type ColorPickerMode = ColorPickerTypes.Mode
export type ColorPickerDismissReason = ColorPickerTypes.DismissReason
export type DateRangePreset = DateTimePickerTypes.Preset
export type DateTimePickerDismissReason = DateTimePickerTypes.DismissReason
export type ControlSize = MediaTypes.ControlSize
export type Status = MediaTypes.Status
export type TextRole = MediaTypes.TextRole
export type Presence = MediaTypes.Presence
export type ImageScaleMode = MediaTypes.ScaleMode
export type ImageLoader = MediaTypes.ImageLoader
export type VoteValue = ContentTypes.VoteValue
export type StepState = ContentTypes.StepState
export type PaginationForm = ContentTypes.PaginationForm
export type TabPlacement = NavigationTypes.Placement
export type TabSelectionIndicator = NavigationTypes.TabSelectionIndicator
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
export type ThemeDefinition = ThemeTypes.ThemeDefinition
export type PalettePatch = ThemeTypes.PalettePatch
export type PaletteExtra = ThemeTypes.PaletteExtra
export type TypographyPatch = ThemeTypes.TypographyPatch
export type CivilDate = CivilTypes.CivilDate
export type CivilRange = CivilTypes.Range
export type CivilLocale = CivilTypes.Locale
export type CivilDateModule = CivilTypes.Module
export type Value<T> = Compose.Value<T>
export type ReadOnlyValue<T> = Compose.ReadOnlyValue<T>
export type Input<T> = SharedTypes.Input<T>
export type ValueString = SharedTypes.ValueString
export type ValueBoolean = SharedTypes.ValueBoolean
export type ValueNumber = SharedTypes.ValueNumber
export type Activate = (InputObject?, number?) -> ()
export type Runtime = Compose.Runtime
export type Owner = Compose.Owner
export type Use = Compose.Use
export type ComposeModule = typeof(Compose)
export type ComposeRobloxModule = typeof(Roblox)
export type DesignModule = typeof(ComposeDesign)
export type DesignContext = FacetDesign.Context
export type DesignControlSpec = FacetDesign.ControlSpec
export type DesignSeed = FacetDesign.Seed
export type DesignLibrary = ComposeDesign.Library
export type DesignDocument = ComposeDesign.Document
export type DesignNode = ComposeDesign.Node
export type DesignValue = ComposeDesign.Value
export type DesignLiteral = ComposeDesign.Literal
export type DesignInput = ComposeDesign.Input
export type DesignItemField = ComposeDesign.ItemField
export type DesignOutput = ComposeDesign.Output
export type DesignInputType = ComposeDesign.InputType
export type DesignState = ComposeDesign.State
export type DesignEmitOptions = ComposeDesign.EmitOptions
export type Facet = {
	VERSION: string,
	COMPOSE_COMMIT: string,
	Compose: ComposeModule,
	Roblox: ComposeRobloxModule,
	Design: DesignModule,
	designLibrary: (DesignContext) -> ComposeDesign.Library,
	designControls: { [string]: DesignControlSpec },
	designSeeds: (kind: string) -> { DesignSeed },
	controls: (Runtime, ControlOptions?) -> Controls,
	host: (Runtime) -> Host,
	app: (AppOptions?) -> App,
	themes: ThemeTypes.Themes,
	civilDate: CivilTypes.Module,
	adaptive: adaptive.Adaptive,
	gamepadContention: gamepadContention.GamepadContention,
	pathShapes: typeof(pathShapes),
	richText: typeof(richText),
	format: typeof(format),
	recipes: { arithmetic: { parse: (unknown) -> number? } },
	inputPriority: { belowControls: number, aboveFacet: number },
	bind: (ComposeModule, ComposeRobloxModule) -> Facet,
}

local VERSION = "0.12.0"
local INPUT_PRIORITY = table.freeze({ belowControls = 25, aboveFacet = 12000 })
local COMPOSE_COMMIT = "ed850c6a8189e9ec2d457d992bf7262aa2a95f85"
local USED = {
	"boundary",
	"cell",
	"cleanup",
	"createContext",
	"createFocusScope",
	"createPool",
	"createSharedResource",
	"currentOwner",
	"focusNeighbor",
	"formula",
	"fragment",
	"isValue",
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
		Design = ComposeDesign,
		designLibrary = FacetDesign.library,
		designControls = FacetDesign.controls,
		designSeeds = FacetDesign.seeds,
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
		format = format,
		recipes = recipes,
		inputPriority = INPUT_PRIORITY,
		bind = bind,
	})
	return surface
end

return bind(Compose, Roblox)
