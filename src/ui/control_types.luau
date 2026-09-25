--!strict
local Shared = require("./types")
local Inputs = require("./input_types")
local Navigation = require("./navigation_types")
local Collections = require("./collection_types")
local Media = require("./media_types")
local Content = require("./content_types")
local Layout = require("./layout_types")
local Overlay = require("./overlay_types")
local Dates = require("./date_time_picker_types")
local Colors = require("./color_picker_types")
local Env = require("./environment_types")

export type Controls = {
	Screen: typeof(((nil :: unknown) :: Layout.LayoutControls).Screen),
	VStack: typeof(((nil :: unknown) :: Layout.LayoutControls).VStack),
	HStack: typeof(((nil :: unknown) :: Layout.LayoutControls).HStack),
	ZStack: typeof(((nil :: unknown) :: Layout.LayoutControls).ZStack),
	ScrollView: typeof(((nil :: unknown) :: Layout.LayoutControls).ScrollView),
	Grid: typeof(((nil :: unknown) :: Layout.LayoutControls).Grid),
	ErrorBoundary: typeof(((nil :: unknown) :: Layout.LayoutControls).ErrorBoundary),
	Divider: typeof(((nil :: unknown) :: Layout.LayoutControls).Divider),
	Spacer: typeof(((nil :: unknown) :: Layout.LayoutControls).Spacer),
	fill: typeof(((nil :: unknown) :: Layout.LayoutControls).fill),
	Button: typeof(((nil :: unknown) :: Inputs.InputControls).Button),
	Toggle: typeof(((nil :: unknown) :: Inputs.InputControls).Toggle),
	TextInput: typeof(((nil :: unknown) :: Inputs.InputControls).TextInput),
	NumberInput: typeof(((nil :: unknown) :: Inputs.InputControls).NumberInput),
	Stepper: typeof(((nil :: unknown) :: Inputs.InputControls).Stepper),
	Slider: typeof(((nil :: unknown) :: Inputs.InputControls).Slider),
	Rating: typeof(((nil :: unknown) :: Inputs.InputControls).Rating),
	LevelPicker: typeof(((nil :: unknown) :: Inputs.InputControls).LevelPicker),
	Chip: typeof(((nil :: unknown) :: Inputs.InputControls).Chip),
	ShortcutHint: typeof(((nil :: unknown) :: Inputs.InputControls).ShortcutHint),
	Picker: typeof(((nil :: unknown) :: Navigation.NavigationControls).Picker),
	Menu: typeof(((nil :: unknown) :: Navigation.NavigationControls).Menu),
	RadialMenu: typeof(((nil :: unknown) :: Navigation.NavigationControls).RadialMenu),
	SplitButton: typeof(((nil :: unknown) :: Navigation.NavigationControls).SplitButton),
	ComboBox: typeof(((nil :: unknown) :: Navigation.NavigationControls).ComboBox),
	DisclosureGroup: typeof(((nil :: unknown) :: Navigation.NavigationControls).DisclosureGroup),
	CollapsibleView: typeof(((nil :: unknown) :: Navigation.NavigationControls).CollapsibleView),
	Alert: typeof(((nil :: unknown) :: Navigation.NavigationControls).Alert),
	Callout: typeof(((nil :: unknown) :: Navigation.NavigationControls).Callout),
	Sheet: typeof(((nil :: unknown) :: Navigation.NavigationControls).Sheet),
	NavigationStack: typeof(((nil :: unknown) :: Navigation.NavigationControls).NavigationStack),
	PageView: typeof(((nil :: unknown) :: Navigation.NavigationControls).PageView),
	TabView: typeof(((nil :: unknown) :: Navigation.NavigationControls).TabView),
	VirtualList: typeof(((nil :: unknown) :: Collections.CollectionControls).VirtualList),
	VirtualGrid: typeof(((nil :: unknown) :: Collections.CollectionControls).VirtualGrid),
	Table: typeof(((nil :: unknown) :: Collections.CollectionControls).Table),
	RowActions: typeof(((nil :: unknown) :: Collections.CollectionControls).RowActions),
	Text: typeof(((nil :: unknown) :: Media.MediaControls).Text),
	Label: typeof(((nil :: unknown) :: Media.MediaControls).Label),
	Image: typeof(((nil :: unknown) :: Media.MediaControls).Image),
	Badge: typeof(((nil :: unknown) :: Media.MediaControls).Badge),
	StatusIndicator: typeof(((nil :: unknown) :: Media.MediaControls).StatusIndicator),
	Path: typeof(((nil :: unknown) :: Media.MediaControls).Path),
	ProgressView: typeof(((nil :: unknown) :: Media.MediaControls).ProgressView),
	Skeleton: typeof(((nil :: unknown) :: Media.MediaControls).Skeleton),
	AsyncImage: typeof(((nil :: unknown) :: Media.MediaControls).AsyncImage),
	Avatar: typeof(((nil :: unknown) :: Media.MediaControls).Avatar),
	AvatarGroup: typeof(((nil :: unknown) :: Media.MediaControls).AvatarGroup),
	Stage: typeof(((nil :: unknown) :: Media.MediaControls).Stage),
	Pagination: typeof(((nil :: unknown) :: Content.ContentControls).Pagination),
	StepIndicator: typeof(((nil :: unknown) :: Content.ContentControls).StepIndicator),
	Vote: typeof(((nil :: unknown) :: Content.ContentControls).Vote),
	Card: typeof(((nil :: unknown) :: Content.ContentControls).Card),
	badged: typeof(((nil :: unknown) :: Content.ContentControls).badged),
	Dialog: typeof(((nil :: unknown) :: Overlay.OverlayControls).Dialog),
	Popover: typeof(((nil :: unknown) :: Overlay.OverlayControls).Popover),
	Notice: typeof(((nil :: unknown) :: Overlay.OverlayControls).Notice),
	NavBar: typeof(((nil :: unknown) :: Overlay.OverlayControls).NavBar),
	Snackbar: typeof(((nil :: unknown) :: Overlay.OverlayControls).Snackbar),
	DateTimePicker: typeof(((nil :: unknown) :: Dates.DateTimePickerControls).DateTimePicker),
	ColorPicker: typeof(((nil :: unknown) :: Colors.ColorPickerControls).ColorPicker),
	environment: typeof(((nil :: unknown) :: Env.EnvironmentControls).environment),
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
