--!strict
local Shared = require("./types")
local Commands = require("./command_types")
local Effects = require("./effect_types")
local Inputs = require("./input_types")
local Content = require("./content_types")
local Env = require("./environment_types")
local LayoutProps = require("./layout_props")
local MediaProps = require("./media_props")
local HudProps = require("./hud_props")
local InputProps = require("./input_props")
local NavigationProps = require("./navigation_props")
local RadialProps = require("./radial_props")
local OverlayProps = require("./overlay_props")
local CollectionProps = require("./collection_props")
local SpatialProps = require("./spatial_grid_props")
local ContentProps = require("./content_props")
local EffectProps = require("./effect_props")
local ZoomTravelProps = require("./zoom_travel_props")
local DiegeticTypes = require("./diegetic_types")

local commandControls: Commands.Controls
local effectControls: Effects.Controls
local environmentControls: Env.EnvironmentControls

type Constructor<P, N> = Shared.Constructor<P, N>

type PickerShapes =
	(<V>(NavigationProps.SinglePickerSpec<V>) -> GuiObject)
	& (<V>(NavigationProps.MultiplePickerSpec<V>) -> GuiObject)
	& (<V>(NavigationProps.PickerSpec<V>) -> GuiObject)
export type PickerConstructor = PickerShapes & ((string) -> PickerShapes)
type ToggleShapes =
	((InputProps.ToggleCellProps) -> TextButton)
	& ((InputProps.ToggleRequestProps) -> TextButton)
	& ((InputProps.ToggleProps) -> TextButton)
export type ToggleConstructor = ToggleShapes & ((string) -> ToggleShapes)
type TextInputShapes =
	((InputProps.TextInputCellProps) -> TextBox | Frame)
	& ((InputProps.TextInputRequestProps) -> TextBox | Frame)
	& ((InputProps.TextInputNumberCellProps) -> TextBox | Frame)
	& ((InputProps.TextInputNumberRequestProps) -> TextBox | Frame)
	& ((InputProps.TextInputProps) -> TextBox | Frame)
export type TextInputConstructor = TextInputShapes & ((string) -> TextInputShapes)
type NumberInputShapes =
	((InputProps.NumberInputCellProps) -> TextBox | Frame)
	& ((InputProps.NumberInputRequestProps) -> TextBox | Frame)
	& ((InputProps.NumberInputProps) -> TextBox | Frame)
export type NumberInputConstructor = NumberInputShapes & ((string) -> NumberInputShapes)
type StepperShapes =
	((InputProps.StepperCellProps) -> Frame)
	& ((InputProps.StepperRequestProps) -> Frame)
	& ((InputProps.StepperProps) -> Frame)
export type StepperConstructor = StepperShapes & ((string) -> StepperShapes)
type SliderShapes =
	((InputProps.SliderCellProps) -> Frame)
	& ((InputProps.SliderRequestProps) -> Frame)
	& ((InputProps.SliderRangeProps) -> Frame)
	& ((InputProps.SliderProps) -> Frame)
export type SliderConstructor = SliderShapes & ((string) -> SliderShapes)
type RatingShapes =
	((InputProps.RatingCellProps) -> TextButton)
	& ((InputProps.RatingRequestProps) -> TextButton)
	& ((InputProps.RatingReadOnlyProps) -> TextButton)
	& ((InputProps.RatingProps) -> TextButton)
export type RatingConstructor = RatingShapes & ((string) -> RatingShapes)
type LevelPickerShapes =
	((InputProps.LevelPickerCellProps) -> TextButton)
	& ((InputProps.LevelPickerRequestProps) -> TextButton)
	& ((InputProps.LevelPickerReadOnlyProps) -> TextButton)
	& ((InputProps.LevelPickerProps) -> TextButton)
export type LevelPickerConstructor = LevelPickerShapes & ((string) -> LevelPickerShapes)
type ChipShapes =
	((InputProps.ChipCellProps) -> TextButton | Frame)
	& ((InputProps.ChipRequestProps) -> TextButton | Frame)
	& ((InputProps.ChipRemovableProps) -> TextButton | Frame)
	& ((InputProps.ChipProps) -> TextButton | Frame)
export type ChipConstructor = ChipShapes & ((string) -> ChipShapes)
type ShortcutHintShapes =
	((InputProps.ShortcutHintKeysProps) -> TextLabel | Frame)
	& ((InputProps.ShortcutHintActionProps) -> TextLabel | Frame)
	& ((InputProps.ShortcutHintProps) -> TextLabel | Frame)
export type ShortcutHintConstructor = ShortcutHintShapes & ((string) -> ShortcutHintShapes)
type MenuShapes = ((NavigationProps.MenuSpec<string>) -> GuiObject) & (<V>(NavigationProps.MenuSpec<V>) -> GuiObject)
export type MenuConstructor = MenuShapes & ((string) -> MenuShapes)
type SplitButtonShapes =
	((NavigationProps.SplitButtonSpec<string>) -> Frame)
	& (<V>(NavigationProps.SplitButtonSpec<V>) -> Frame)
export type SplitButtonConstructor = SplitButtonShapes & ((string) -> SplitButtonShapes)
type AlertShapes = <P>(NavigationProps.AlertSpec<P>) -> Frame
export type AlertConstructor = AlertShapes & ((string) -> AlertShapes)
type NavigationStackShapes = <P>(NavigationProps.NavigationStackSpec<P>) -> Frame
export type NavigationStackConstructor = NavigationStackShapes & ((string) -> NavigationStackShapes)
type RadialMenuShapes = ((RadialProps.RadialMenuSpec<string>) -> Frame) & (<V>(RadialProps.RadialMenuSpec<V>) -> Frame)
export type RadialMenuConstructor = RadialMenuShapes & ((string) -> RadialMenuShapes)
type CollectionShapes =
	(<V, K>(spec: CollectionProps.KeyedCollectionSpec<V, K>) -> ScrollingFrame)
	& (<V, _K>(spec: CollectionProps.IdentityCollectionSpec<V>) -> ScrollingFrame)
export type CollectionConstructor = CollectionShapes & ((string) -> CollectionShapes)
export type SpatialGridShape = <V, K>(SpatialProps.SpatialGridSpec<V, K>) -> Frame
export type SpatialGridConstructor = SpatialGridShape & ((string) -> SpatialGridShape)
type OutlineShapes =
	(<V, K>(spec: CollectionProps.KeyedOutlineSpec<V, K>) -> ScrollingFrame)
	& (<V, _K>(spec: CollectionProps.IdentityOutlineSpec<V>) -> ScrollingFrame)
export type OutlineConstructor = OutlineShapes & ((string) -> OutlineShapes)
type TableShapes =
	(<V, K>(spec: CollectionProps.KeyedTableSpec<V, K>) -> Frame)
	& (<V, _K>(spec: CollectionProps.IdentityTableSpec<V>) -> Frame)
export type TableConstructor = TableShapes & ((string) -> TableShapes)

export type Controls = {
	WorldMarker: Constructor<HudProps.WorldMarkerProps, Frame>,
	DiegeticScreen: Constructor<DiegeticTypes.DiegeticScreenProps, Folder>,
	Timer: Constructor<HudProps.TimerProps, TextLabel>,
	Typewriter: Constructor<HudProps.TypewriterProps, TextLabel>,
	commandScope: typeof(commandControls.commandScope),
	sequence: typeof(effectControls.sequence),
	countUp: typeof(effectControls.countUp),
	Flash: Constructor<EffectProps.FlashProps, Frame>,
	ZoomView: Constructor<ZoomTravelProps.ZoomViewProps, ScrollingFrame>,
	Travel: Constructor<ZoomTravelProps.TravelProps, Frame>,
	NavigationSplitView: Constructor<NavigationProps.NavigationSplitViewProps, Frame>,
	Screen: Constructor<LayoutProps.ScreenProps, Frame>,
	VStack: Constructor<LayoutProps.StackProps, Frame>,
	HStack: Constructor<LayoutProps.StackProps, Frame>,
	ZStack: Constructor<LayoutProps.ZStackProps, Frame>,
	ScrollView: Constructor<LayoutProps.ScrollViewProps, ScrollingFrame>,
	Grid: Constructor<LayoutProps.GridProps, Frame>,
	AdaptiveStack: Constructor<LayoutProps.AdaptiveStackProps, Frame>,
	ViewThatFits: Constructor<LayoutProps.ViewThatFitsProps, Frame>,
	ErrorBoundary: Constructor<LayoutProps.ErrorBoundaryProps, Frame>,
	Divider: Constructor<LayoutProps.DividerProps, Frame>,
	Spacer: Constructor<LayoutProps.SpacerProps, Frame>,
	Composition: Constructor<LayoutProps.CompositionProps, Frame>,
	Region: Constructor<LayoutProps.RegionProps, Frame>,
	fill: (weight: number?) -> UIFlexItem,
	Button: Constructor<InputProps.ButtonProps, TextButton>,
	Toggle: ToggleConstructor,
	TextInput: TextInputConstructor,
	NumberInput: NumberInputConstructor,
	Stepper: StepperConstructor,
	Slider: SliderConstructor,
	Rating: RatingConstructor,
	LevelPicker: LevelPickerConstructor,
	Chip: ChipConstructor,
	ShortcutHint: ShortcutHintConstructor,
	ButtonGuide: Constructor<InputProps.ButtonGuideProps, Frame>,
	Picker: PickerConstructor,
	Menu: MenuConstructor,
	RadialMenu: RadialMenuConstructor,
	SplitButton: SplitButtonConstructor,
	ComboBox: Constructor<NavigationProps.ComboBoxSpec, Frame>,
	DisclosureGroup: Constructor<NavigationProps.DisclosureGroupSpec, Frame>,
	CollapsibleView: Constructor<NavigationProps.CollapsibleViewSpec, TextButton>,
	Alert: AlertConstructor,
	Callout: Constructor<NavigationProps.CalloutSpec, Frame>,
	Sheet: Constructor<NavigationProps.SheetSpec, Frame>,
	NavigationStack: NavigationStackConstructor,
	PageView: Constructor<NavigationProps.PageViewSpec, Frame>,
	TabView: Constructor<NavigationProps.TabViewSpec, Frame>,
	VirtualList: CollectionConstructor,
	Outline: OutlineConstructor,
	VirtualGrid: CollectionConstructor,
	SpatialGrid: SpatialGridConstructor,
	CellEditor: Constructor<CollectionProps.CellEditorSpec, Frame>,
	Table: TableConstructor,
	RowActions: Constructor<CollectionProps.RowActionsSpec, Frame>,
	Text: Constructor<MediaProps.TextProps, GuiObject>,
	Label: Constructor<MediaProps.LabelProps, GuiObject>,
	Image: Constructor<MediaProps.ImageProps, GuiObject>,
	Badge: Constructor<MediaProps.BadgeProps, GuiObject>,
	StatusIndicator: Constructor<MediaProps.StatusIndicatorProps, TextLabel>,
	Path: Constructor<MediaProps.PathProps, Frame>,
	ProgressView: Constructor<MediaProps.ProgressViewProps, Frame>,
	Skeleton: Constructor<MediaProps.SkeletonProps, Frame>,
	AsyncImage: Constructor<MediaProps.AsyncImageProps, Frame>,
	Avatar: Constructor<MediaProps.AvatarProps, TextButton>,
	AvatarGroup: Constructor<MediaProps.AvatarGroupProps, Frame>,
	Stage: Constructor<MediaProps.StageProps, ViewportFrame>,
	Pagination: Constructor<ContentProps.PaginationSpec, Frame>,
	StepIndicator: Constructor<ContentProps.StepIndicatorSpec, Frame>,
	Vote: Constructor<ContentProps.VoteSpec, Frame>,
	Card: Constructor<ContentProps.CardSpec, Frame>,
	badged: Content.Badged,
	Dialog: Constructor<OverlayProps.DialogSpec, Frame>,
	Popover: Constructor<OverlayProps.PopoverSpec, GuiObject>,
	Notice: Constructor<OverlayProps.NoticeSpec, Frame>,
	NavBar: Constructor<OverlayProps.NavBarSpec, Frame>,
	Toast: Constructor<OverlayProps.ToastSpec, Frame>,
	DateTimePicker: Constructor<InputProps.DateTimePickerProps, Frame>,
	ColorPicker: Constructor<InputProps.ColorPickerProps, Frame>,
	environment: typeof(environmentControls.environment),
	focusRing: typeof(environmentControls.focusRing),
	focusSection: typeof(environmentControls.focusSection),
	responder: typeof(environmentControls.responder),
	adjustable: (node: GuiObject, options: Inputs.AdjustableOptions) -> (),
	feedback: (kind: Inputs.HapticKind) -> (),
	gestureArbiter: typeof(environmentControls.gestureArbiter),
	draggable: typeof(environmentControls.draggable),
	dropTarget: typeof(environmentControls.dropTarget),
	worldAnchor: typeof(environmentControls.worldAnchor),
	scrollTo: typeof(environmentControls.scrollTo),
	scrollToVisible: typeof(environmentControls.scrollToVisible),
}
export type BuilderControls = {
	scrollTo: typeof(environmentControls.scrollTo),
	DiegeticScreen: Constructor<DiegeticTypes.DiegeticScreenProps, Folder>,
	Button: Constructor<InputProps.ButtonProps, TextButton>,
	Toggle: Constructor<InputProps.ToggleProps, TextButton>,
	TextInput: Constructor<InputProps.TextInputProps, TextBox | Frame>,
	NumberInput: Constructor<InputProps.NumberInputProps, TextBox | Frame>,
	Chip: Constructor<InputProps.ChipProps, TextButton | Frame>,
	ShortcutHint: Constructor<InputProps.ShortcutHintProps, TextLabel | Frame>,
	ButtonGuide: Constructor<InputProps.ButtonGuideProps, Frame>,
	Slider: Constructor<InputProps.SliderProps, Frame>,
	ColorPicker: Constructor<InputProps.ColorPickerProps, Frame>,
	DateTimePicker: Constructor<InputProps.DateTimePickerProps, Frame>,
	Picker: PickerConstructor,
	Menu: MenuConstructor,
	SplitButton: SplitButtonConstructor,
	ComboBox: Constructor<NavigationProps.ComboBoxSpec, Frame>,
	RadialMenu: RadialMenuConstructor,
	DisclosureGroup: Constructor<NavigationProps.DisclosureGroupSpec, Frame>,
	CollapsibleView: Constructor<NavigationProps.CollapsibleViewSpec, TextButton>,
	Alert: AlertConstructor,
	Callout: Constructor<NavigationProps.CalloutSpec, Frame>,
	Sheet: Constructor<NavigationProps.SheetSpec, Frame>,
	NavigationStack: NavigationStackConstructor,
	PageView: Constructor<NavigationProps.PageViewSpec, Frame>,
	TabView: Constructor<NavigationProps.TabViewSpec, Frame>,
	Dialog: Constructor<OverlayProps.DialogSpec, Frame>,
	Popover: Constructor<OverlayProps.PopoverSpec, GuiObject>,
	Notice: Constructor<OverlayProps.NoticeSpec, Frame>,
	NavBar: Constructor<OverlayProps.NavBarSpec, Frame>,
	Toast: Constructor<OverlayProps.ToastSpec, Frame>,
	Table: TableConstructor,
	CellEditor: Constructor<CollectionProps.CellEditorSpec, Frame>,
	VirtualList: CollectionConstructor,
	VirtualGrid: CollectionConstructor,
	SpatialGrid: SpatialGridConstructor,
	Outline: OutlineConstructor,
	RowActions: Constructor<CollectionProps.RowActionsSpec, Frame>,
	Avatar: Constructor<MediaProps.AvatarProps, TextButton>,
	Badge: Constructor<MediaProps.BadgeProps, GuiObject>,
	StatusIndicator: Constructor<MediaProps.StatusIndicatorProps, TextLabel>,
	Card: Constructor<ContentProps.CardSpec, Frame>,
	Pagination: Constructor<ContentProps.PaginationSpec, Frame>,
	StepIndicator: Constructor<ContentProps.StepIndicatorSpec, Frame>,
	Vote: Constructor<ContentProps.VoteSpec, Frame>,
	badged: Content.Badged,
	adjustable: (GuiObject, Inputs.AdjustableOptions) -> (),
}
export type ComposeModule = Shared.ComposeModule
export type Runtime = Shared.Runtime
export type Config = Shared.Config
export type Context = Shared.Context
export type Factory = (Shared.ComposeModule, Shared.Runtime, Config?) -> Controls

return {}
