--!strict
local Shared = require("./types")
local Commands = require("./command_types")
local Effects = require("./effect_types")
local Inputs = require("./input_types")
local Content = require("./content_types")
local Env = require("./environment_types")
local LayoutProps = require("./layout_props")
local MediaProps = require("./media_props")
local InputProps = require("./input_props")
local NavigationProps = require("./navigation_props")
local RadialProps = require("./radial_props")
local OverlayProps = require("./overlay_props")
local CollectionProps = require("./collection_props")
local ContentProps = require("./content_props")
local EffectProps = require("./effect_props")
local ZoomTravelProps = require("./zoom_travel_props")

type Constructor<P, N> = Shared.Constructor<P, N>

export type PickerConstructor =
	(<V>(NavigationProps.SinglePickerSpec<V>) -> GuiObject)
	& (<V>(NavigationProps.MultiplePickerSpec<V>) -> GuiObject)
	& (<V>(NavigationProps.PickerSpec<V>) -> GuiObject)
export type ToggleConstructor =
	((InputProps.ToggleCellProps) -> TextButton)
	& ((InputProps.ToggleRequestProps) -> TextButton)
	& ((InputProps.ToggleProps) -> TextButton)
export type TextInputConstructor =
	((InputProps.TextInputCellProps) -> TextBox | Frame)
	& ((InputProps.TextInputRequestProps) -> TextBox | Frame)
	& ((InputProps.TextInputNumberCellProps) -> TextBox | Frame)
	& ((InputProps.TextInputNumberRequestProps) -> TextBox | Frame)
	& ((InputProps.TextInputProps) -> TextBox | Frame)
export type NumberInputConstructor =
	((InputProps.NumberInputCellProps) -> TextBox | Frame)
	& ((InputProps.NumberInputRequestProps) -> TextBox | Frame)
	& ((InputProps.NumberInputProps) -> TextBox | Frame)
export type StepperConstructor =
	((InputProps.StepperCellProps) -> Frame)
	& ((InputProps.StepperRequestProps) -> Frame)
	& ((InputProps.StepperProps) -> Frame)
export type SliderConstructor =
	((InputProps.SliderCellProps) -> Frame)
	& ((InputProps.SliderRequestProps) -> Frame)
	& ((InputProps.SliderRangeProps) -> Frame)
	& ((InputProps.SliderProps) -> Frame)
export type RatingConstructor =
	((InputProps.RatingCellProps) -> TextButton)
	& ((InputProps.RatingRequestProps) -> TextButton)
	& ((InputProps.RatingReadOnlyProps) -> TextButton)
	& ((InputProps.RatingProps) -> TextButton)
export type LevelPickerConstructor =
	((InputProps.LevelPickerCellProps) -> TextButton)
	& ((InputProps.LevelPickerRequestProps) -> TextButton)
	& ((InputProps.LevelPickerReadOnlyProps) -> TextButton)
	& ((InputProps.LevelPickerProps) -> TextButton)
export type ChipConstructor =
	((InputProps.ChipCellProps) -> TextButton | Frame)
	& ((InputProps.ChipRequestProps) -> TextButton | Frame)
	& ((InputProps.ChipRemovableProps) -> TextButton | Frame)
	& ((InputProps.ChipProps) -> TextButton | Frame)
export type ShortcutHintConstructor =
	((InputProps.ShortcutHintKeysProps) -> TextLabel | Frame)
	& ((InputProps.ShortcutHintActionProps) -> TextLabel | Frame)
	& ((InputProps.ShortcutHintProps) -> TextLabel | Frame)
export type MenuConstructor = <V>(NavigationProps.MenuSpec<V>) -> GuiObject
export type SplitButtonConstructor = <V>(NavigationProps.SplitButtonSpec<V>) -> Frame
export type AlertConstructor = <P>(NavigationProps.AlertSpec<P>) -> Frame
export type NavigationStackConstructor = <P>(NavigationProps.NavigationStackSpec<P>) -> Frame
export type RadialMenuConstructor = <V>(RadialProps.RadialMenuSpec<V>) -> Frame
export type CollectionConstructor =
	(<V, K>(spec: CollectionProps.KeyedCollectionSpec<V, K>) -> ScrollingFrame)
	& (<V, _K>(spec: CollectionProps.IdentityCollectionSpec<V>) -> ScrollingFrame)
export type OutlineConstructor =
	(<V, K>(spec: CollectionProps.KeyedOutlineSpec<V, K>) -> ScrollingFrame)
	& (<V, _K>(spec: CollectionProps.IdentityOutlineSpec<V>) -> ScrollingFrame)
export type TableConstructor =
	(<V, K>(spec: CollectionProps.KeyedTableSpec<V, K>) -> Frame)
	& (<V, _K>(spec: CollectionProps.IdentityTableSpec<V>) -> Frame)

export type Controls = {
	commandScope: typeof(((nil :: unknown) :: Commands.Controls).commandScope),
	sequence: typeof(((nil :: unknown) :: Effects.Controls).sequence),
	countUp: typeof(((nil :: unknown) :: Effects.Controls).countUp),
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
	environment: typeof(((nil :: unknown) :: Env.EnvironmentControls).environment),
	focusRing: typeof(((nil :: unknown) :: Env.EnvironmentControls).focusRing),
	focusSection: typeof(((nil :: unknown) :: Env.EnvironmentControls).focusSection),
	responder: typeof(((nil :: unknown) :: Env.EnvironmentControls).responder),
	adjustable: (node: GuiObject, options: Inputs.AdjustableOptions) -> (),
	feedback: (kind: Inputs.HapticKind) -> (),
	gestureArbiter: typeof(((nil :: unknown) :: Env.EnvironmentControls).gestureArbiter),
	draggable: typeof(((nil :: unknown) :: Env.EnvironmentControls).draggable),
	dropTarget: typeof(((nil :: unknown) :: Env.EnvironmentControls).dropTarget),
	worldAnchor: typeof(((nil :: unknown) :: Env.EnvironmentControls).worldAnchor),
	scrollTo: typeof(((nil :: unknown) :: Env.EnvironmentControls).scrollTo),
	scrollToVisible: typeof(((nil :: unknown) :: Env.EnvironmentControls).scrollToVisible),
}
export type ComposeModule = Shared.ComposeModule
export type Runtime = Shared.Runtime
export type Config = Shared.Config
export type Context = Shared.Context
export type Factory = (Shared.ComposeModule, Shared.Runtime, Config?) -> Controls

return {}
