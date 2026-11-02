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
local CameraRigTypes = require("./camera_rig_types")

local commandControls: Commands.Controls
local effectControls: Effects.Controls
local environmentControls: Env.EnvironmentControls

type Constructor<P, N> = Shared.Constructor<P, N>

export type PickerConstructor = <V>(
	NavigationProps.PickerSpecInput<V> | string,
	string?
) -> GuiObject
	& typeof(setmetatable({} :: {}, {} :: { __call: (unknown, NavigationProps.PickerSpecInput<V>) -> GuiObject }))

export type ToggleConstructor = Constructor<InputProps.TogglePropsInput, TextButton>

export type TextInputConstructor = Constructor<InputProps.TextInputPropsInput, GuiObject>

export type NumberInputConstructor = Constructor<InputProps.NumberInputPropsInput, GuiObject>

export type StepperConstructor = Constructor<InputProps.StepperPropsInput, Frame>

export type SliderConstructor = Constructor<InputProps.SliderPropsInput, Frame>

export type RatingConstructor = Constructor<InputProps.RatingPropsInput, TextButton>

export type LevelPickerConstructor = Constructor<InputProps.LevelPickerPropsInput, TextButton>

export type ChipConstructor = Constructor<InputProps.ChipPropsInput, GuiObject>

export type ShortcutHintConstructor = Constructor<InputProps.ShortcutHintPropsInput, GuiObject>

export type MenuConstructor = <V>(
	NavigationProps.MenuSpecInput<V> | string,
	string?
) -> GuiObject
	& typeof(setmetatable({} :: {}, {} :: { __call: (unknown, NavigationProps.MenuSpecInput<V>) -> GuiObject }))

export type SplitButtonConstructor = <V>(
	NavigationProps.SplitButtonSpecInput<V> | string,
	string?
) -> Frame
	& typeof(setmetatable({} :: {}, {} :: { __call: (unknown, NavigationProps.SplitButtonSpecInput<V>) -> Frame }))

export type AlertConstructor = <P>(
	NavigationProps.AlertSpecInput<P> | string,
	string?
) -> Frame & typeof(setmetatable({} :: {}, {} :: { __call: (unknown, NavigationProps.AlertSpecInput<P>) -> Frame }))

export type NavigationStackConstructor = <P>(
	NavigationProps.NavigationStackSpecInput<P> | string,
	string?
) -> Frame
	& typeof(setmetatable({} :: {}, {} :: { __call: (unknown, NavigationProps.NavigationStackSpecInput<P>) -> Frame }))

export type RadialMenuConstructor = <V>(
	RadialProps.RadialMenuSpecInput<V> | string,
	string?
) -> Frame & typeof(setmetatable({} :: {}, {} :: { __call: (unknown, RadialProps.RadialMenuSpecInput<V>) -> Frame }))

export type CollectionConstructor = <V, K>(
	CollectionProps.KeyedCollectionSpecInput<V, K> | CollectionProps.IdentityCollectionSpecInput<V> | string,
	string?
) -> ScrollingFrame
	& typeof(setmetatable(
		{} :: {},
		{} :: {
			__call: (
				unknown,
				CollectionProps.KeyedCollectionSpecInput<V, K> | CollectionProps.IdentityCollectionSpecInput<V>
			) -> ScrollingFrame,
		}
	))

export type SpatialGridConstructor = <V, K>(
	SpatialProps.SpatialGridSpecInput<V, K> | string,
	string?
) -> Frame
	& typeof(setmetatable({} :: {}, {} :: { __call: (unknown, SpatialProps.SpatialGridSpecInput<V, K>) -> Frame }))

export type OutlineConstructor = <V, K>(
	CollectionProps.KeyedOutlineSpecInput<V, K> | CollectionProps.IdentityOutlineSpecInput<V> | string,
	string?
) -> ScrollingFrame
	& typeof(setmetatable(
		{} :: {},
		{} :: {
			__call: (
				unknown,
				CollectionProps.KeyedOutlineSpecInput<V, K> | CollectionProps.IdentityOutlineSpecInput<V>
			) -> ScrollingFrame,
		}
	))

export type TableConstructor = <V, K>(
	CollectionProps.KeyedTableSpecInput<V, K> | string,
	string?
) -> Frame & typeof(setmetatable(
	{} :: {},
	{} :: {
		__call: (unknown, CollectionProps.KeyedTableSpecInput<V, K>) -> Frame,
	}
))

export type Controls = {
	provide: <R...>(body: () -> R...) -> R...,
	WorldMarker: Constructor<HudProps.WorldMarkerPropsInput, Frame>,
	DiegeticScreen: Constructor<DiegeticTypes.DiegeticScreenProps, Folder>,
	cameraRig: (CameraRigTypes.CameraRigOptions) -> CameraRigTypes.CameraRig,
	Timer: Constructor<HudProps.TimerPropsInput, TextLabel>,
	Typewriter: Constructor<HudProps.TypewriterPropsInput, TextLabel>,
	commandScope: typeof(commandControls.commandScope),
	sequence: typeof(effectControls.sequence),
	shake: typeof(effectControls.shake),
	countUp: typeof(effectControls.countUp),
	follow: typeof(effectControls.follow),
	toward: typeof(effectControls.toward),
	Flash: Constructor<EffectProps.FlashPropsInput, Frame>,
	ZoomView: Constructor<ZoomTravelProps.ZoomViewPropsInput, ScrollingFrame>,
	Travel: Constructor<ZoomTravelProps.TravelPropsInput, Frame>,
	NavigationSplitView: Constructor<NavigationProps.NavigationSplitViewPropsInput, Frame>,
	Screen: Constructor<LayoutProps.ScreenPropsInput, Frame>,
	VStack: Constructor<LayoutProps.StackPropsInput, Frame>,
	HStack: Constructor<LayoutProps.StackPropsInput, Frame>,
	ZStack: Constructor<LayoutProps.ZStackPropsInput, Frame>,
	ScrollView: Constructor<LayoutProps.ScrollViewPropsInput, ScrollingFrame>,
	Grid: Constructor<LayoutProps.GridPropsInput, Frame>,
	AdaptiveStack: Constructor<LayoutProps.AdaptiveStackPropsInput, Frame>,
	ViewThatFits: Constructor<LayoutProps.ViewThatFitsPropsInput, Frame>,
	ErrorBoundary: Constructor<LayoutProps.ErrorBoundaryPropsInput, Frame>,
	Divider: Constructor<LayoutProps.DividerPropsInput, Frame>,
	Spacer: Constructor<LayoutProps.SpacerPropsInput, Frame>,
	Composition: Constructor<LayoutProps.CompositionPropsInput, Frame>,
	Region: Constructor<LayoutProps.RegionPropsInput, Frame>,
	fill: (weight: number?) -> UIFlexItem,
	Button: Constructor<InputProps.ButtonPropsInput, TextButton>,
	Toggle: ToggleConstructor,
	TextInput: TextInputConstructor,
	NumberInput: NumberInputConstructor,
	Stepper: StepperConstructor,
	Slider: SliderConstructor,
	Rating: RatingConstructor,
	LevelPicker: LevelPickerConstructor,
	Chip: ChipConstructor,
	ShortcutHint: ShortcutHintConstructor,
	ButtonGuide: Constructor<InputProps.ButtonGuidePropsInput, Frame>,
	Picker: PickerConstructor,
	Menu: MenuConstructor,
	RadialMenu: RadialMenuConstructor,
	SplitButton: SplitButtonConstructor,
	ComboBox: Constructor<NavigationProps.ComboBoxSpecInput, Frame>,
	DisclosureGroup: Constructor<NavigationProps.DisclosureGroupSpecInput, Frame>,
	CollapsibleView: Constructor<NavigationProps.CollapsibleViewSpecInput, TextButton>,
	Alert: AlertConstructor,
	Callout: Constructor<NavigationProps.CalloutSpecInput, Frame>,
	Sheet: Constructor<NavigationProps.SheetSpecInput, Frame>,
	NavigationStack: NavigationStackConstructor,
	PageView: Constructor<NavigationProps.PageViewSpecInput, Frame>,
	TabView: Constructor<NavigationProps.TabViewSpecInput, Frame>,
	VirtualList: CollectionConstructor,
	Outline: OutlineConstructor,
	VirtualGrid: CollectionConstructor,
	SpatialGrid: SpatialGridConstructor,
	CellEditor: Constructor<CollectionProps.CellEditorSpecInput, Frame>,
	Table: TableConstructor,
	RowActions: Constructor<CollectionProps.RowActionsSpecInput, Frame>,
	Text: Constructor<MediaProps.TextPropsInput, GuiObject>,
	Label: Constructor<MediaProps.LabelPropsInput, GuiObject>,
	Image: Constructor<MediaProps.ImagePropsInput, GuiObject>,
	Badge: Constructor<MediaProps.BadgePropsInput, GuiObject>,
	StatusIndicator: Constructor<MediaProps.StatusIndicatorPropsInput, TextLabel>,
	Path: Constructor<MediaProps.PathPropsInput, Frame>,
	ProgressView: Constructor<MediaProps.ProgressViewPropsInput, Frame>,
	Skeleton: Constructor<MediaProps.SkeletonPropsInput, Frame>,
	AsyncImage: Constructor<MediaProps.AsyncImagePropsInput, Frame>,
	Avatar: Constructor<MediaProps.AvatarPropsInput, TextButton>,
	AvatarGroup: Constructor<MediaProps.AvatarGroupPropsInput, Frame>,
	Stage: Constructor<MediaProps.StagePropsInput, ViewportFrame>,
	Pagination: Constructor<ContentProps.PaginationSpecInput, Frame>,
	StepIndicator: Constructor<ContentProps.StepIndicatorSpecInput, Frame>,
	Vote: Constructor<ContentProps.VoteSpecInput, Frame>,
	Card: Constructor<ContentProps.CardSpecInput, Frame>,
	badged: Content.Badged,
	Dialog: Constructor<OverlayProps.DialogSpecInput, Frame>,
	Popover: Constructor<OverlayProps.PopoverSpecInput, GuiObject>,
	Notice: Constructor<OverlayProps.NoticeSpecInput, Frame>,
	NavBar: Constructor<OverlayProps.NavBarSpecInput, Frame>,
	Toast: Constructor<OverlayProps.ToastSpecInput, Frame>,
	DateTimePicker: Constructor<InputProps.DateTimePickerPropsInput, Frame>,
	ColorPicker: Constructor<InputProps.ColorPickerPropsInput, Frame>,
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
export type ComposeModule = Shared.ComposeModule
export type Runtime = Shared.Runtime
export type Config = Shared.Config
export type Context = Shared.Context
export type Factory = (Shared.ComposeModule, Shared.Runtime, Config?) -> Controls

return {}
