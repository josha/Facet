--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local Radial = require("./radial_types")
local Inputs = require("./input_types")
local Overlay = require("./overlay_types")

export type Value<T> = Types.Value<T>
export type Content = Instance | (() -> Instance)
export type Indicator = "automatic" | "pill" | "underline" | "none"
export type Placement = "automatic" | "topBar" | "sidebar" | "bottomBar" | "bottomBarCompact" | "none"
export type Transition = ComposeTypes.TweenOptions
export type SourceTransition = { seconds: Types.ValueNumber?, ease: ComposeTypes.Easing?, source: Value<GuiObject?>? }
export type MenuTrigger = "activate" | "secondary" | "longPress" | "keyboard" | "gamepad"
export type OptionAvatar = MenuAvatar
export type OptionIndicator = {
	status: Value<"neutral" | "info" | "success" | "warning" | "error" | "accent">?,
	form: ("dot" | "ring" | "square" | "dash")?,
	count: Types.ValueNumber?,
}
export type MenuItemBase = {
	role: Value<"default" | "cancel" | "destructive" | "onIndicator">?,
	id: string?,
	label: Types.ValueString,
	description: Types.ValueString?,
	icon: Types.ValueString?,
	meta: Types.ValueString?,
	enabled: Types.ValueBoolean?,
	marked: Types.ValueBoolean?,
	dismiss: boolean?,
	divider: false?,
	badge: Value<string | number>?,
	avatar: MenuAvatar?,
	sectionTitle: Types.ValueString?,
	shortcutLabel: Types.ValueString?,
}
export type MenuAvatar = { name: string, image: string?, userId: number? }
export type MenuEdge = "top" | "bottom" | "leading" | "trailing"
export type MenuAlign = "start" | "center" | "end"
export type MenuDimLength = number | string
export type MenuDim = {
	type: "fixed" | "fill" | "hug" | "percent" | "content" | "minMax",
	px: MenuDimLength?,
	weight: number?,
	fraction: number?,
	offset: number?,
	min: MenuDimLength?,
	preferred: MenuDimLength?,
	max: MenuDimLength?,
}
export type MenuWidth = number | UDim | UDim2 | MenuDim
export type MenuAction<V = string> =
	(MenuItemBase & {
		children: Value<{ MenuItem<V> }>,
		onSelect: nil,
		checked: nil,
		selected: nil,
	})
	| (MenuItemBase & { children: nil, onSelect: () -> (), checked: nil, selected: nil })
	| (MenuItemBase & {
		children: nil,
		checked: ComposeTypes.Cell<boolean>,
		selected: nil,
		onChange: ((boolean) -> ())?,
		onSelect: (() -> ())?,
	})
	| (MenuItemBase & {
		children: nil,
		checked: nil,
		selected: ComposeTypes.Cell<V>,
		value: V,
		onChange: ((V) -> ())?,
		onSelect: (() -> ())?,
	})
export type MenuItem<V = string> = { id: string?, divider: true } | MenuAction<V>
export type MenuSpec<V = string> = Types.FrameProps & {
	items: Value<{ MenuItem<V> }>,
	query: ComposeTypes.Cell<string>?,
	label: Types.ValueString?,
	trigger: GuiObject | (() -> GuiObject)?,
	disclosure: boolean?,
	triggers: { MenuTrigger }?,
	presentation: Value<"automatic" | "menu" | "sheet">?,
	backLabel: Types.ValueString?,
	onOpen: (() -> ())?,
	onClose: (() -> ())?,
	enabled: Types.ValueBoolean?,
	isPresented: ComposeTypes.Cell<boolean>?,
	edge: MenuEdge?,
	align: MenuAlign?,
	width: Value<MenuWidth>?,
	maxHeight: number?,
	controls: { diagnostics: (() -> { string })? }?,
}
export type PickerOption<V = string> = {
	id: string?,
	value: V,
	label: Types.ValueString,
	description: Types.ValueString?,
	icon: Types.ValueString?,
	badge: Value<string | number>?,
	meta: Types.ValueString?,
	avatar: OptionAvatar?,
	sectionTitle: Types.ValueString?,
	indicator: OptionIndicator?,
	enabled: Types.ValueBoolean?,
}
export type PickerStyle = "automatic" | "menu" | "navigationLink" | "segmented" | "inline" | "radioGroup" | "cards"
export type PickerCommon<V> = Types.GuiObjectProps & {
	Style: Value<Enum.FrameStyle>?,
	options: Value<{ PickerOption<V> }>,
	style: PickerStyle?,
	query: ComposeTypes.Cell<string>?,
	placeholder: Types.ValueString?,
	label: Types.ValueString?,
	required: boolean?,
	enabled: Types.ValueBoolean?,
	indicator: Value<Indicator>?,
	axis: Value<"x" | "y">?,
	sizing: Value<"fill" | "hug">?,
	iconOnly: Types.ValueBoolean?,
	textSize: Types.ValueNumber?,
	isPresented: ComposeTypes.Cell<boolean>?,
	requiredMark: ("required" | "optional")?,
	hint: Types.ValueString?,
	errorText: Types.ValueString?,
	controlSize: Value<Types.ControlSize>?,
	appearance: Types.ValueString?,
	corners: ("pill" | "square")?,
	maxHeight: number?,
	indicatorPosition: ("leading" | "trailing")?,
	valueAlignment: ("start" | "end")?,
}
export type SinglePickerSpec<V = string> = PickerCommon<V> & {
	multiple: false?,
	selected: ComposeTypes.Cell<V>,
	onChanging: ((V, V) -> boolean?)?,
	onChange: ((V) -> ())?,
}
export type MultiplePickerSpec<V = string> = PickerCommon<V> & {
	multiple: true,
	selected: ComposeTypes.Cell<{ [V]: boolean }>,
	onChanging: (({ [V]: boolean }, { [V]: boolean }) -> boolean?)?,
	onChange: (({ [V]: boolean }) -> ())?,
}
export type PickerSpec<V = string> = SinglePickerSpec<V> | MultiplePickerSpec<V>
export type SplitButtonSpec<V = string> = Types.FrameProps & {
	label: Types.ValueString?,
	onActivate: (() -> ())?,
	items: Value<{ MenuItem<V> }>,
	enabled: Types.ValueBoolean?,
	busy: Types.ValueBoolean?,
	shortcut: Inputs.Shortcut?,
	menuLabel: Types.ValueString?,
}
export type ComboBoxSpec = Types.FrameProps & {
	value: ComposeTypes.Cell<string>,
	text: ComposeTypes.Cell<string>,
	options: Value<{ PickerOption<string> }>,
	enabled: Types.ValueBoolean?,
	acceptCustom: (string) -> (boolean, string?),
	onChange: ((string) -> ())?,
	commitOnFocusLost: boolean?,
	placeholder: Types.ValueString?,
}
export type DisclosureGroupSpec = Types.FrameProps & {
	expanded: ComposeTypes.Cell<boolean>,
	label: Types.ValueString?,
	content: Content,
	description: Types.ValueString?,
	icon: Types.ValueString?,
	enabled: Types.ValueBoolean?,
	onToggle: ((boolean) -> ())?,
	chevronPosition: "leading" | "trailing"?,
	appearance: "plain" | "contained" | "divided" | "outline"?,
	textSize: Value<string | number>?,
	indent: (number | Types.SpaceStep)?,
}
export type CollapsibleViewSpec = Types.TextButtonProps & Inputs.ButtonVisualOptions & Inputs.ButtonInputOptions & {
	expanded: ComposeTypes.Cell<boolean>,
	content: Content,
	initialFocus: string?,
	dismissButton: Types.ValueBoolean?,
	selected: Types.ValueBoolean?,
	onActivate: ((InputObject?, number?) -> ())?,
}

export type AlertAction<P = unknown> = {
	id: string,
	label: Types.ValueString,
	role: "default" | "cancel" | "destructive"?,
	enabled: Types.ValueBoolean?,
	shortcut: "defaultAction" | "cancelAction" | Inputs.Shortcut?,
	onActivate: ((P) -> ())?,
}
export type AlertSpec<P = unknown> = Types.FrameProps & {
	isPresented: ComposeTypes.Cell<boolean>?,
	item: ComposeTypes.Cell<P?>?,
	presenting: Value<P>?,
	title: string | ((P) -> string)?,
	message: string | ((P) -> string)?,
	actions: { AlertAction<P> } | ((P) -> { AlertAction<P> })?,
	content: ((P) -> Instance)?,
	error: ComposeTypes.Cell<string?>?,
	icon: Types.ValueString?,
	severity: "information" | "warning" | "critical"?,
	suppression: { isSuppressed: ComposeTypes.Cell<boolean>, label: Types.ValueString? }?,
	maxWidth: number?,
	padding: number?,
	surface: "dialog" | "fullScreen"?,
	transition: SourceTransition | false?,
}
export type SheetDetent =
	"medium"
	| "large"
	| "hug"
	| { id: string, fraction: number, height: nil }
	| { id: string, fraction: nil, height: number }
export type SheetSpec = Types.FrameProps & {
	isPresented: ComposeTypes.Cell<boolean>,
	detent: ComposeTypes.Cell<string>,
	detents: { SheetDetent }?,
	title: Types.ValueString?,
	content: Content,
	interactiveDismissDisabled: Types.ValueBoolean?,
	dragIndicator: ("automatic" | "visible" | "hidden")?,
	placement: ("automatic" | "adaptive" | "bottom" | "side" | "center")?,
	edge: ("left" | "right")?,
	width: Overlay.WidthPreset?,
	closeButton: (boolean | Types.ValueString)?,
	header: (Content | false)?,
	hero: Overlay.Hero?,
	actions: { Overlay.Action }?,
	actionLayout: Overlay.ActionLayout?,
	contentInset: ("standard" | "none")?,
	scrollPolicy: ("always" | "atLargestDetent")?,
}
export type SheetRequest = (string) -> boolean
export type CalloutRetirement = "featureUsed" | "seen" | "dismissed" | "tapAway" | "action"
export type CalloutSpec = Types.FrameProps & {
	anchor: GuiObject,
	content: Content?,
	title: Types.ValueString?,
	media: Overlay.Media?,
	steps: { index: number, count: number }?,
	actions: { Overlay.Action }?,
	closeButton: boolean?,
	dismissLabel: Types.ValueString?,
	edge: Value<"top" | "bottom">?,
	align: Value<"leading" | "center" | "trailing">?,
	tail: boolean | "none"?,
	priority: number?,
	seen: Types.ValueBoolean?,
	sessions: Types.ValueNumber?,
	afterSessions: number?,
	featureUsed: Types.ValueBoolean?,
	onRetire: (CalloutRetirement) -> (),
	onShow: (() -> ())?,
	onHide: (("retired" | "hidden") -> ())?,
	isPresented: Types.ValueBoolean?,
}
export type Tab = {
	id: string,
	badge: Value<string | number>?,
	label: Types.ValueString?,
	icon: Types.ValueString?,
	content: Content,
	section: string?,
	required: boolean?,
	indicator: TabIndicator?,
	enabled: Types.ValueBoolean?,
}
export type TabIndicator = {
	form: ("dot" | "ring" | "square" | "dash")?,
	status: ("neutral" | "info" | "success" | "warning" | "error" | "accent")?,
	count: Value<number?>?,
	max: number?,
}
export type TabViewSpec = Types.FrameProps & {
	selection: ComposeTypes.Cell<string>,
	tabs: Value<{ Tab }>,
	sections: { { id: string, label: string } }?,
	customization: Value<{ order: { string }?, hidden: { string }? }>?,
	accessories: {
		head: ((Placement) -> Instance?)?,
		foot: ((Placement) -> Instance?)?,
		trailing: ((Placement) -> Instance?)?,
		aboveBar: ((Placement) -> Instance?)?,
	}?,
	railWidth: Types.ValueNumber?,
	transition: Transition | false?,
	retention: "all" | "top"?,
	placement: Value<Placement>?,
	style: "automatic" | "sidebarAdaptable" | "collapsible"?,
	sidebarPreference: Value<"automatic" | "topBar" | "sidebar">?,
	restoreScroll: boolean?,
	restoreFocus: boolean?,
	shoulderNavigation: "strip" | "content"?,
	indicator: Value<Indicator>?,
	iconOnly: Types.ValueBoolean?,
	textSize: Value<number | "fit">?,
	controlSize: Value<Types.ControlSize>?,
	enabled: Types.ValueBoolean?,
	onChange: ((string) -> ())?,
}
export type NavigationEntry<P = unknown> = { id: string, value: P? }
export type NavigationDestination<P = unknown> = {
	title: Types.ValueString?,
	content: Instance | ((NavigationEntry<P>?) -> Instance),
}
export type NavigationStackSpec<P = unknown> = Types.FrameProps & {
	path: ComposeTypes.Cell<{ NavigationEntry<P> }>,
	root: NavigationDestination<P>,
	destinations: { [string]: NavigationDestination<P> },
	backLabel: Types.ValueString?,
	transition: Transition | false?,
}
export type PageViewSpec = Types.FrameProps & {
	selection: ComposeTypes.Cell<string>,
	pages: { Tab },
	indicators: boolean?,
	summary: boolean?,
	controls: boolean?,
}
export type PresencePhase = { exiting: ComposeTypes.Readable<boolean> }
export type MotionTiming = { enter: number, exit: number }
export type Appearance = (ComposeTypes.Use?) -> number
export type ModalOptions = {
	exiting: ComposeTypes.Readable<boolean>?,
	appearance: Appearance?,
	Name: string?,
	ZIndex: number?,
	priority: number?,
	initialFocus: string?,
	backgroundTransparency: Types.ValueNumber?,
	outsideDismiss: Types.ValueBoolean?,
	canDismiss: Types.ValueBoolean?,
	onOutside: (() -> ())?,
}
export type OverlayOptions = {
	presence: ComposeTypes.PresenceOptions?,
	motion: MotionTiming?,
	identity: ((ComposeTypes.Use) -> number)?,
	failure: ((unknown) -> Instance)?,
}
export type PanelSkin = {
	padding: UIPadding?,
	reserve: ((string, ComposeTypes.Use) -> number)?,
	title: Types.ValueString?,
	onCaption: ((boolean) -> ())?,
}
export type Surfaces = {
	service: (("GuiService") -> GuiService?) & (("UserInputService") -> UserInputService?),
	within: (Instance?, Instance) -> boolean,
	firstSelectable: (Instance, string?) -> GuiObject?,
	preference: () -> (ComposeTypes.Use) -> number,
	selecting: () -> (ComposeTypes.Use) -> boolean,
	attach: <N>(N & Instance, { Types.Child }) -> N & Instance,
	available: (GuiObject) -> ComposeTypes.Readable<boolean>,
	centered: (GuiObject, number) -> GuiObject,
	skin: (GuiObject, string?, PanelSkin?) -> GuiObject,
	inset: (number, string, string?, ComposeTypes.Use?) -> number,
	modal: (() -> GuiObject, (string?) -> (), ModalOptions?) -> Frame,
	overlay: (GuiObject, Types.ValueBoolean, (PresencePhase?) -> Instance, OverlayOptions?) -> Types.Child,
	appearance: (PresencePhase?, MotionTiming, ComposeTypes.Readable<boolean>?) -> Appearance,
	popover: (GuiObject, Appearance, (ComposeTypes.Use) -> (Vector2, Vector2), number?, boolean?) -> (),
	sheetModal: ((SheetSpec, SheetRequest, PresencePhase?) -> Frame)?,
}
export type PickerConstructor = (<V>(PickerSpec<V>) -> GuiObject) & ((string) -> <V>(PickerSpec<V>) -> GuiObject)
export type MenuConstructor = (<V>(MenuSpec<V>) -> GuiObject) & ((string) -> <V>(MenuSpec<V>) -> GuiObject)
export type SplitButtonConstructor = (<V>(SplitButtonSpec<V>) -> Frame) & ((string) -> <V>(SplitButtonSpec<V>) -> Frame)
export type AlertConstructor = (<P>(AlertSpec<P>) -> Frame) & ((string) -> <P>(AlertSpec<P>) -> Frame)
export type NavigationStackConstructor =
	(<P>(NavigationStackSpec<P>) -> Frame)
	& ((string) -> <P>(NavigationStackSpec<P>) -> Frame)
export type NavigationControls = {
	Picker: PickerConstructor,
	Menu: MenuConstructor,
	RadialMenu: Radial.RadialMenuConstructor,
	SplitButton: SplitButtonConstructor,
	ComboBox: Types.Constructor<ComboBoxSpec, Frame>,
	DisclosureGroup: Types.Constructor<DisclosureGroupSpec, Frame>,
	CollapsibleView: Types.Constructor<CollapsibleViewSpec, TextButton>,
	Alert: AlertConstructor,
	Callout: Types.Constructor<CalloutSpec, Frame>,
	Sheet: Types.Constructor<SheetSpec, Frame>,
	NavigationStack: NavigationStackConstructor,
	PageView: Types.Constructor<PageViewSpec, Frame>,
	TabView: Types.Constructor<TabViewSpec, Frame>,
}
return {}
