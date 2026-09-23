--!strict
local Compose = require("../vendor/compose/core")
local Types = require("./types")
local Radial = require("./radial_types")
local Inputs = require("./input_types")

export type Value<T> = Types.Value<T>
export type Content = Instance | (() -> Instance)
export type Indicator = "automatic" | "pill" | "underline" | "none"
export type Placement = "automatic" | "topBar" | "sidebar" | "bottomBar" | "bottomBarCompact"
export type Transition = Compose.TweenOptions
export type SourceTransition = { seconds: Value<number>?, ease: Compose.Easing?, source: Value<GuiObject?>? }
export type MenuTrigger = "activate" | "secondary" | "longPress" | "keyboard" | "gamepad"
export type MenuItemBase = {
	role: Value<"default" | "cancel" | "destructive" | "onIndicator">?,
	id: string?,
	label: Value<string>,
	description: Value<string>?,
	icon: Value<string>?,
	enabled: Value<boolean>?,
	marked: Value<boolean>?,
	dismiss: boolean?,
	divider: false?,
}
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
		checked: Compose.Cell<boolean>,
		selected: nil,
		onChange: ((boolean) -> ())?,
		onSelect: (() -> ())?,
	})
	| (MenuItemBase & {
		children: nil,
		checked: nil,
		selected: Compose.Cell<V>,
		value: V,
		onChange: ((V) -> ())?,
		onSelect: (() -> ())?,
	})
export type MenuItem<V = string> = { id: string?, divider: true } | MenuAction<V>
export type MenuSpec<V = string> = Types.FrameProps & {
	items: Value<{ MenuItem<V> }>,
	query: Compose.Cell<string>?,
	label: Value<string>?,
	trigger: GuiObject | (() -> GuiObject)?,
	triggers: { MenuTrigger }?,
	presentation: Value<"automatic" | "menu" | "sheet">?,
	backLabel: Value<string>?,
	onOpen: (() -> ())?,
	onClose: (() -> ())?,
	enabled: Value<boolean>?,
	isPresented: Compose.Cell<boolean>?,
}
export type PickerOption<V = string> = {
	id: string?,
	value: V,
	label: Value<string>,
	description: Value<string>?,
	icon: Value<string>?,
	badge: Value<string | number>?,
	enabled: Value<boolean>?,
}
export type PickerStyle = "automatic" | "menu" | "navigationLink" | "segmented" | "inline" | "radioGroup"
export type PickerCommon<V> = Types.GuiObjectProps & {
	Style: Value<Enum.FrameStyle>?,
	options: Value<{ PickerOption<V> }>,
	style: PickerStyle?,
	query: Compose.Cell<string>?,
	placeholder: Value<string>?,
	label: Value<string>?,
	required: boolean?,
	enabled: Value<boolean>?,
	indicator: Value<Indicator>?,
	axis: Value<"x" | "y">?,
	sizing: Value<"fill" | "hug">?,
	iconOnly: Value<boolean>?,
	textSize: Value<number>?,
	valueAlignment: "leading" | "center" | "trailing"?,
	isPresented: Compose.Cell<boolean>?,
}
export type SinglePickerSpec<V = string> = PickerCommon<V> & {
	multiple: false?,
	selected: Compose.Cell<V>,
	onChanging: ((V, V) -> boolean?)?,
	onChange: ((V) -> ())?,
}
export type MultiplePickerSpec<V = string> = PickerCommon<V> & {
	multiple: true,
	selected: Compose.Cell<{ [V]: boolean }>,
	onChanging: (({ [V]: boolean }, { [V]: boolean }) -> boolean?)?,
	onChange: (({ [V]: boolean }) -> ())?,
}
export type PickerSpec<V = string> = SinglePickerSpec<V> | MultiplePickerSpec<V>
export type SplitButtonSpec<V = string> = Types.FrameProps & {
	label: Value<string>?,
	onActivate: (() -> ())?,
	items: Value<{ MenuItem<V> }>,
	enabled: Value<boolean>?,
	busy: Value<boolean>?,
	shortcut: Inputs.Shortcut?,
	menuLabel: Value<string>?,
}
export type ComboBoxSpec = Types.FrameProps & {
	value: Compose.Cell<string>,
	text: Compose.Cell<string>,
	options: Value<{ PickerOption<string> }>,
	enabled: Value<boolean>?,
	acceptCustom: (string) -> (boolean, string?),
	onChange: ((string) -> ())?,
	commitOnFocusLost: boolean?,
	placeholder: Value<string>?,
}
export type DisclosureGroupSpec = Types.FrameProps & {
	expanded: Compose.Cell<boolean>,
	label: Value<string>?,
	content: Content,
	description: Value<string>?,
	icon: Value<string>?,
	enabled: Value<boolean>?,
	onToggle: ((boolean) -> ())?,
	chevronPosition: "leading" | "trailing"?,
	appearance: "plain" | "contained" | "divided"?,
}
export type CollapsibleViewSpec = Types.TextButtonProps & Inputs.ButtonVisualOptions & Inputs.ButtonInputOptions & {
	expanded: Compose.Cell<boolean>,
	content: Content,
	initialFocus: string?,
	dismissButton: Value<boolean>?,
	selected: Value<boolean>?,
	onActivate: ((InputObject?, number?) -> ())?,
}

export type AlertAction<P = unknown> = {
	id: string,
	label: Value<string>,
	role: "default" | "cancel" | "destructive"?,
	enabled: Value<boolean>?,
	shortcut: "defaultAction" | "cancelAction" | Inputs.Shortcut?,
	onActivate: ((P) -> ())?,
}
export type AlertSpec<P = unknown> = Types.FrameProps & {
	isPresented: Compose.Cell<boolean>?,
	item: Compose.Cell<P?>?,
	presenting: Value<P>?,
	title: string | ((P) -> string)?,
	message: string | ((P) -> string)?,
	actions: { AlertAction<P> } | ((P) -> { AlertAction<P> })?,
	content: ((P) -> Instance)?,
	error: Compose.Cell<string?>?,
	icon: Value<string>?,
	severity: "information" | "warning" | "critical"?,
	suppression: { isSuppressed: Compose.Cell<boolean>, label: Value<string>? }?,
	maxWidth: number?,
	padding: number?,
	surface: "dialog" | "fullScreen"?,
	transition: SourceTransition | false?,
}
export type SheetDetent =
	"medium"
	| "large"
	| { id: string, fraction: number, height: nil }
	| { id: string, fraction: nil, height: number }
export type SheetSpec = Types.FrameProps & {
	isPresented: Compose.Cell<boolean>,
	detent: Compose.Cell<string>,
	detents: { SheetDetent }?,
	title: Value<string>?,
	content: Content,
	interactiveDismissDisabled: Value<boolean>?,
	dragIndicator: "visible" | "hidden"?,
}
export type CalloutRetirement = "featureUsed" | "seen" | "dismissed" | "tapAway"
export type CalloutSpec = Types.FrameProps & {
	anchor: GuiObject,
	content: Content,
	dismissLabel: Value<string>?,
	edge: Value<"top" | "bottom">?,
	align: Value<"leading" | "center" | "trailing">?,
	tail: boolean | "none"?,
	priority: number?,
	seen: Value<boolean>?,
	sessions: Value<number>?,
	afterSessions: number?,
	featureUsed: Value<boolean>?,
	onRetire: (CalloutRetirement) -> (),
	onShow: (() -> ())?,
	onHide: (("retired" | "hidden") -> ())?,
	isPresented: Value<boolean>?,
}
export type Tab = {
	id: string,
	badge: Value<string | number>?,
	label: Value<string>?,
	icon: Value<string>?,
	content: Content,
	section: string?,
	required: boolean?,
}
export type TabViewSpec = Types.FrameProps & {
	selection: Compose.Cell<string>,
	tabs: Value<{ Tab }>,
	sections: { { id: string, label: string } }?,
	customization: Value<{ order: { string }?, hidden: { string }? }>?,
	accessories: {
		head: ((Placement) -> Instance?)?,
		foot: ((Placement) -> Instance?)?,
		trailing: ((Placement) -> Instance?)?,
		aboveBar: ((Placement) -> Instance?)?,
	}?,
	railWidth: Value<number>?,
	transition: Transition | false?,
	retention: "all" | "top"?,
	placement: Value<Placement>?,
	style: "automatic" | "sidebarAdaptable" | "collapsible"?,
	sidebarPreference: Value<"automatic" | "topBar" | "sidebar">?,
	restoreScroll: boolean?,
	restoreFocus: boolean?,
	shoulderNavigation: "strip" | "content"?,
	indicator: Value<Indicator>?,
	sizing: Value<"automatic" | "fill" | "hug">?,
	iconOnly: Value<boolean>?,
	textSize: Value<number>?,
	enabled: Value<boolean>?,
	onChange: ((string) -> ())?,
}
export type NavigationEntry<P = unknown> = { id: string, value: P? }
export type NavigationDestination<P = unknown> = {
	title: Value<string>?,
	content: Instance | ((NavigationEntry<P>?) -> Instance),
}
export type NavigationStackSpec<P = unknown> = Types.FrameProps & {
	path: Compose.Cell<{ NavigationEntry<P> }>,
	root: NavigationDestination<P>,
	destinations: { [string]: NavigationDestination<P> },
	backLabel: Value<string>?,
	transition: Transition | false?,
}
export type PageViewSpec = Types.FrameProps & {
	selection: Compose.Cell<string>,
	pages: { Tab },
	indicators: boolean?,
	summary: boolean?,
	controls: boolean?,
}
export type PresencePhase = { exiting: Compose.Readable<boolean> }
export type ModalOptions = {
	Name: string?,
	ZIndex: number?,
	priority: number?,
	initialFocus: string?,
	backgroundTransparency: Value<number>?,
	outsideDismiss: Value<boolean>?,
	canDismiss: Value<boolean>?,
	onOutside: (() -> ())?,
}
export type OverlayOptions = {
	presence: Compose.PresenceOptions?,
	failure: ((unknown) -> Instance)?,
}
export type Surfaces = {
	service: (("GuiService") -> GuiService?) & (("UserInputService") -> UserInputService?),
	within: (Instance?, Instance) -> boolean,
	firstSelectable: (Instance, string?) -> GuiObject?,
	attach: <N>(N & Instance, { Types.Child }) -> N & Instance,
	available: (GuiObject) -> Compose.Readable<boolean>,
	centered: (GuiObject, number) -> GuiObject,
	skin: (GuiObject, string?) -> GuiObject,
	modal: (() -> GuiObject, (string?) -> (), ModalOptions?) -> Frame,
	overlay: (GuiObject, Value<boolean>, (PresencePhase?) -> Instance, OverlayOptions?) -> Types.Child,
}
export type PickerConstructor = (<V>(PickerSpec<V>) -> GuiObject) & ((string) -> <V>(PickerSpec<V>) -> GuiObject)
export type MenuConstructor = (<V>(MenuSpec<V>) -> Frame) & ((string) -> <V>(MenuSpec<V>) -> Frame)
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
