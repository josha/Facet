--!strict
local Shared = require("./types")
local Inputs = require("./input_types")
local Navigation = require("./navigation_types")
local Collections = require("./collection_types")
local Media = require("./media_types")

export type Controls = {
	Button: typeof(((nil :: unknown) :: Inputs.InputControls).Button),
	Toggle: typeof(((nil :: unknown) :: Inputs.InputControls).Toggle),
	TextInput: typeof(((nil :: unknown) :: Inputs.InputControls).TextInput),
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
	Label: typeof(((nil :: unknown) :: Media.MediaControls).Label),
	Badge: typeof(((nil :: unknown) :: Media.MediaControls).Badge),
	StatusIndicator: typeof(((nil :: unknown) :: Media.MediaControls).StatusIndicator),
	ProgressView: typeof(((nil :: unknown) :: Media.MediaControls).ProgressView),
	Skeleton: typeof(((nil :: unknown) :: Media.MediaControls).Skeleton),
	AsyncImage: typeof(((nil :: unknown) :: Media.MediaControls).AsyncImage),
	Avatar: typeof(((nil :: unknown) :: Media.MediaControls).Avatar),
	AvatarGroup: typeof(((nil :: unknown) :: Media.MediaControls).AvatarGroup),
	Stage: typeof(((nil :: unknown) :: Media.MediaControls).Stage),
}
export type Runtime = Shared.Runtime
export type Config = Shared.Config
export type Context = Shared.Context
export type Factory = (Shared.Runtime, Config?) -> Controls

return {}
