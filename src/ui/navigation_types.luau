--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local Radial = require("./radial_types")
local Inputs = require("./input_types")
local Overlay = require("./overlay_types")

export type Input<T> = Types.Input<T>
export type Content = Instance | Types.GuiInstance | (() -> Instance)
export type Indicator = "automatic" | "pill" | "underline" | "none"
export type TabSelectionIndicator = Indicator | "mark"
export type Placement = "automatic" | "topBar" | "sidebar" | "bottomBar" | "bottomBarCompact" | "none"
export type TransitionContext = {
	progress: ComposeTypes.ReadOnlyValue<number>,
	isPresented: ComposeTypes.ReadOnlyValue<boolean>,
}
export type Transition = {
	seconds: Types.ValueNumber?,
	ease: ComposeTypes.Easing?,
	motion: string?,
	fade: boolean?,
	progress: ComposeTypes.ReadOnlyValue<number?>?,
	apply: ((GuiObject, TransitionContext) -> ())?,
}
export type SourceTransition = { seconds: Types.ValueNumber?, ease: ComposeTypes.Easing?, source: Input<GuiObject?>? }
export type MenuTrigger = "activate" | "secondary" | "longPress" | "keyboard" | "gamepad"
export type OptionAvatar = MenuAvatar
export type OptionIndicator = {
	status: Input<"neutral" | "info" | "success" | "warning" | "error" | "accent">?,
	form: ("dot" | "ring" | "square" | "dash")?,
	count: Types.ValueNumber?,
}
export type MenuItemBase = {
	role: Input<"default" | "cancel" | "destructive" | "onIndicator">?,
	id: string?,
	label: Types.ValueString,
	description: Types.ValueString?,
	icon: Types.ValueString?,
	meta: Types.ValueString?,
	enabled: Types.ValueBoolean?,
	marked: Types.ValueBoolean?,
	dismiss: boolean?,
	divider: false?,
	badge: Input<(string | number)?>?,
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
export type MenuSubmenu<V = string> = {
	role: Input<"default" | "cancel" | "destructive" | "onIndicator">?,
	id: string?,
	label: Types.ValueString,
	description: Types.ValueString?,
	icon: Types.ValueString?,
	meta: Types.ValueString?,
	enabled: Types.ValueBoolean?,
	marked: Types.ValueBoolean?,
	dismiss: boolean?,
	divider: false?,
	badge: Input<(string | number)?>?,
	avatar: MenuAvatar?,
	sectionTitle: Types.ValueString?,
	shortcutLabel: Types.ValueString?,
	children: Input<{ MenuItem<V> }>,
	onSelect: nil,
	checked: nil,
	selected: nil,
}
export type MenuCommand = {
	role: Input<"default" | "cancel" | "destructive" | "onIndicator">?,
	id: string?,
	label: Types.ValueString,
	description: Types.ValueString?,
	icon: Types.ValueString?,
	meta: Types.ValueString?,
	enabled: Types.ValueBoolean?,
	marked: Types.ValueBoolean?,
	dismiss: boolean?,
	divider: false?,
	badge: Input<(string | number)?>?,
	avatar: MenuAvatar?,
	sectionTitle: Types.ValueString?,
	shortcutLabel: Types.ValueString?,
	children: nil,
	onSelect: () -> (),
	checked: nil,
	selected: nil,
}
export type MenuCheck = {
	role: Input<"default" | "cancel" | "destructive" | "onIndicator">?,
	id: string?,
	label: Types.ValueString,
	description: Types.ValueString?,
	icon: Types.ValueString?,
	meta: Types.ValueString?,
	enabled: Types.ValueBoolean?,
	marked: Types.ValueBoolean?,
	dismiss: boolean?,
	divider: false?,
	badge: Input<(string | number)?>?,
	avatar: MenuAvatar?,
	sectionTitle: Types.ValueString?,
	shortcutLabel: Types.ValueString?,
	children: nil,
	checked: ComposeTypes.Value<boolean>,
	selected: nil,
	onChange: ((boolean) -> ())?,
	onSelect: (() -> ())?,
}
export type MenuChoice<V = string> = {
	role: Input<"default" | "cancel" | "destructive" | "onIndicator">?,
	id: string?,
	label: Types.ValueString,
	description: Types.ValueString?,
	icon: Types.ValueString?,
	meta: Types.ValueString?,
	enabled: Types.ValueBoolean?,
	marked: Types.ValueBoolean?,
	dismiss: boolean?,
	divider: false?,
	badge: Input<(string | number)?>?,
	avatar: MenuAvatar?,
	sectionTitle: Types.ValueString?,
	shortcutLabel: Types.ValueString?,
	children: nil,
	checked: nil,
	selected: ComposeTypes.Value<V>,
	value: V,
	onChange: ((V) -> ())?,
	onSelect: (() -> ())?,
}
export type MenuAction<V = string> = MenuSubmenu<V> | MenuCommand | MenuCheck | MenuChoice<V>
export type MenuItem<V = string> = { id: string?, divider: true } | MenuAction<V>
export type MenuOptions<V = string> = {
	items: Input<{ MenuItem<V> }>,
	query: ComposeTypes.Value<string>?,
	label: Types.ValueString?,
	trigger: Types.GuiInstance | (() -> GuiObject)?,
	disclosure: boolean?,
	triggers: { MenuTrigger }?,
	presentation: Input<"automatic" | "menu" | "sheet">?,
	backLabel: Types.ValueString?,
	onOpen: (() -> ())?,
	onClose: (() -> ())?,
	closeButton: boolean?,
	enabled: Types.ValueBoolean?,
	isPresented: ComposeTypes.Value<boolean>?,
	edge: MenuEdge?,
	align: MenuAlign?,
	width: Input<MenuWidth>?,
	maxHeight: number?,
	controls: { diagnostics: (() -> { string })? }?,
}
export type PickerOption<V = string> = {
	id: string?,
	value: V,
	label: Types.ValueString,
	description: Types.ValueString?,
	icon: Types.ValueString?,
	badge: Input<(string | number)?>?,
	meta: Types.ValueString?,
	avatar: OptionAvatar?,
	sectionTitle: Types.ValueString?,
	indicator: OptionIndicator?,
	enabled: Types.ValueBoolean?,
}
export type PickerStyle = "automatic" | "menu" | "navigationLink" | "segmented" | "inline" | "radioGroup" | "cards"
export type PickerCommon<V> = {
	Style: Input<Enum.FrameStyle>?,
	options: Input<{ PickerOption<V> }>,
	style: PickerStyle?,
	query: ComposeTypes.Value<string>?,
	placeholder: Types.ValueString?,
	label: Types.ValueString?,
	required: boolean?,
	enabled: Types.ValueBoolean?,
	indicator: Input<Indicator?>?,
	axis: Input<"x" | "y">?,
	sizing: Input<"fill" | "hug">?,
	iconOnly: Types.ValueBoolean?,
	textSize: Types.ValueNumber?,
	isPresented: ComposeTypes.Value<boolean>?,
	requiredMark: ("required" | "optional")?,
	hint: Types.ValueString?,
	errorText: Types.ValueString?,
	controlSize: Input<Types.ControlSize?>?,
	appearance: Types.ValueString?,
	corners: ("pill" | "square")?,
	maxHeight: number?,
	indicatorPosition: ("leading" | "trailing")?,
	valueAlignment: ("start" | "end")?,
}
export type SingleSelection<V = string> = {
	multiple: false?,
	selected: ComposeTypes.Value<V>,
	onChanging: ((V, V) -> boolean?)?,
	onChange: ((V) -> ())?,
}
export type MultipleSelection<V = string> = {
	multiple: true,
	selected: ComposeTypes.Value<{ [V]: boolean }>,
	onChanging: (({ [V]: boolean }, { [V]: boolean }) -> boolean?)?,
	onChange: (({ [V]: boolean }) -> ())?,
}
export type SplitButtonOptions<V = string> = {
	label: Types.ValueString?,
	onActivate: (() -> ())?,
	items: Input<{ MenuItem<V> }>,
	enabled: Types.ValueBoolean?,
	busy: Types.ValueBoolean?,
	shortcut: Inputs.Shortcut?,
	menuLabel: Types.ValueString?,
}
export type ComboBoxOptions = {
	value: ComposeTypes.Value<string>,
	text: ComposeTypes.Value<string>,
	options: Input<{ PickerOption<string> }>,
	enabled: Types.ValueBoolean?,
	acceptCustom: (string) -> (boolean, string?),
	onChange: ((string) -> ())?,
	commitOnFocusLost: boolean?,
	placeholder: Types.ValueString?,
}
export type DisclosureGroupOptions = {
	expanded: ComposeTypes.Value<boolean>,
	label: Types.ValueString?,
	content: Content,
	description: Types.ValueString?,
	icon: Types.ValueString?,
	enabled: Types.ValueBoolean?,
	onToggle: ((boolean) -> ())?,
	chevronPosition: "leading" | "trailing"?,
	appearance: "plain" | "contained" | "divided" | "outline"?,
	textSize: Input<number | Types.TextRole>?,
	indent: (number | Types.SpaceStep)?,
}
export type CollapsibleViewOptions = {
	glyph: (() -> GuiObject)?,
	expanded: ComposeTypes.Value<boolean>,
	content: Content,
	initialFocus: string?,
	dismissButton: Types.ValueBoolean?,
	outsideDismiss: Types.ValueBoolean?,
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
export type AlertText<P> = string | ComposeTypes.ReadOnlyValue<string> | ComposeTypes.Value<string> | ((P) -> string)
export type AlertOptions<P = unknown> = {
	isPresented: ComposeTypes.Value<boolean>?,
	item: ComposeTypes.Value<P?>?,
	presenting: Input<P>?,
	title: AlertText<P>?,
	message: AlertText<P>?,
	actions: { AlertAction<P> } | ((P) -> { AlertAction<P> })?,
	content: ((P) -> Instance)?,
	error: ComposeTypes.Value<string?>?,
	icon: Types.ValueString?,
	severity: "information" | "warning" | "critical"?,
	suppression: { isSuppressed: ComposeTypes.Value<boolean>, label: Types.ValueString? }?,
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
export type SheetOptions = {
	transition: Transition | false?,
	isPresented: ComposeTypes.Value<boolean>,
	onPresentedChange: ((boolean) -> ())?,
	detent: (ComposeTypes.Value<string> | string)?,
	detents: { SheetDetent }?,
	title: Types.ValueString?,
	content: Content,
	interactiveDismissDisabled: Types.ValueBoolean?,
	dragIndicator: ("automatic" | "visible" | "hidden")?,
	placement: ("automatic" | "adaptive" | "bottom" | "side" | "center")?,
	edge: ("left" | "right")?,
	width: Input<Overlay.WidthPreset?>?,
	closeButton: (boolean | Types.ValueString)?,
	header: (Content | false)?,
	hero: Overlay.Hero?,
	actions: { Overlay.Action }?,
	actionLayout: Input<Overlay.ActionLayout?>?,
	contentInset: ("standard" | "none")?,
	scrollPolicy: ("always" | "atLargestDetent")?,
	initialFocus: (string | () -> string?)?,
	guide: Inputs.ButtonGuideOptions?,
	guideAlignment: ("start" | "end")?,
}
export type SheetRequest = (string) -> boolean
export type CalloutRetirement = "featureUsed" | "seen" | "dismissed" | "tapAway" | "action"
export type CalloutOptions = {
	anchor: Types.GuiInstance,
	content: Content?,
	title: Types.ValueString?,
	media: Overlay.Media?,
	steps: { index: number, count: number }?,
	actions: { Overlay.Action }?,
	closeButton: boolean?,
	dismissLabel: Types.ValueString?,
	edge: Input<"top" | "bottom" | "leading" | "trailing">?,
	align: Input<"leading" | "center" | "trailing">?,
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
	badge: Input<(string | number)?>?,
	badgeAnchor: Input<"topLeading" | "topTrailing" | "bottomLeading" | "bottomTrailing">?,
	label: Types.ValueString?,
	icon: Types.ValueString?,
	glyph: (() -> GuiObject)?,
	content: Content,
	section: string?,
	required: boolean?,
	indicator: TabIndicator?,
	enabled: Types.ValueBoolean?,
}
export type TabIndicator = {
	form: ("dot" | "ring" | "square" | "dash")?,
	status: ("neutral" | "info" | "success" | "warning" | "error" | "accent")?,
	count: Input<number?>?,
	max: number?,
}
export type TabViewOptions = {
	selection: ComposeTypes.Value<string>,
	tabs: Input<{ Tab }>,
	sections: { { id: string, label: string } }?,
	customization: Input<{ order: { string }?, hidden: { string }? }>?,
	accessories: {
		head: ((Placement) -> Instance?)?,
		foot: ((Placement) -> Instance?)?,
		trailing: ((Placement) -> Instance?)?,
		aboveBar: ((Placement) -> Instance?)?,
	}?,
	railWidth: Input<number?>?,
	transition: Transition | false?,
	retention: "all" | "top"?,
	placement: Input<Placement>?,
	style: "automatic" | "sidebarAdaptable" | "collapsible"?,
	sidebarPreference: Input<"automatic" | "topBar" | "sidebar">?,
	sidebarExpanded: ComposeTypes.Value<boolean>?,
	restoreScroll: boolean?,
	restoreFocus: boolean?,
	shoulderNavigation: "strip" | "content"?,
	indicator: Input<TabSelectionIndicator?>?,
	track: Input<"automatic" | "floating">?,
	indicatorPlacement: Input<"aboveIcon" | "belowIcon" | "inset">?,
	iconOnly: Types.ValueBoolean?,
	labelPlacement: Input<"besideIcon" | "belowIcon">?,
	textSize: Input<number | "fit">?,
	controlSize: Input<Types.ControlSize?>?,
	enabled: Types.ValueBoolean?,
	onChange: ((string) -> ())?,
}
export type NavigationEntry<P = unknown> = { id: string, value: P? }
export type NavigationDestination<P = unknown> = {
	title: Types.ValueString?,
	chrome: Input<"automatic" | "hidden">?,
	initialFocus: (string | () -> string?)?,
	content: Instance | ((NavigationEntry<P>?) -> Instance),
}
export type NavigationStackOptions<P = unknown> = {
	path: ComposeTypes.Value<{ NavigationEntry<P> }>,
	root: NavigationDestination<P>,
	destinations: { [string]: NavigationDestination<P> },
	backLabel: Types.ValueString?,
	chrome: Input<"automatic" | "hidden">?,
	transition: Transition | false?,
}
export type PageViewOptions = {
	selection: ComposeTypes.Value<string>,
	pages: { Tab },
	autoAdvanceSeconds: Input<number?>?,
	scrollWheel: Input<boolean>?,
	indicators: boolean?,
	indicatorPlacement: ("footer" | "overlay")?,
	summary: boolean?,
	controls: boolean?,
}
export type PresencePhase = { exiting: ComposeTypes.ReadOnlyValue<boolean> }
export type MotionTiming = { enter: number, exit: number }
export type Appearance = (ComposeTypes.Use?) -> number
export type Presence = { opacity: Appearance, travel: Appearance }
export type PopoverOptions = {
	geometry: { Size: Types.Input<UDim2>?, AutomaticSize: Types.Input<Enum.AutomaticSize>? }?,
	from: number?,
	pinned: boolean?,
	rested: ComposeTypes.ReadOnlyValue<boolean>?,
	size: ComposeTypes.ReadOnlyValue<Vector2>?,
	rise: ((ComposeTypes.Use) -> number?)?,
}
export type ModalOptions = {
	exiting: ComposeTypes.ReadOnlyValue<boolean>?,
	appearance: Appearance?,
	Name: string?,
	ZIndex: number?,
	priority: number?,
	initialFocus: string?,
	entry: (() -> GuiObject?)?,
	backgroundTransparency: Types.ValueNumber?,
	outsideDismiss: Types.ValueBoolean?,
	outsideMargin: number?,
	canDismiss: Types.ValueBoolean?,
	onOutside: (() -> ())?,
	keepsGameplay: boolean?,
}
export type OverlayOptions = {
	parent: (() -> GuiBase2d?)?,
	presence: ComposeTypes.PresenceOptions?,
	motion: MotionTiming?,
	identity: ((ComposeTypes.Use) -> number)?,
	failure: ((unknown) -> Instance)?,
}
export type PanelSkin = {
	padding: (UIPadding | false)?,
	reserve: ((string, ComposeTypes.Use) -> number)?,
	title: Types.ValueString?,
	onCaption: ((boolean) -> ())?,
}
export type Surfaces = {
	parent: (Instance) -> GuiBase2d?,
	service: (("GuiService") -> GuiService?) & (("UserInputService") -> UserInputService?),
	within: (Instance?, Instance) -> boolean,
	keep: (...unknown) -> (),
	firstSelectable: (Instance, string?, ((Instance) -> boolean)?) -> GuiObject?,
	displayed: (Instance) -> boolean,
	preference: () -> (ComposeTypes.Use) -> number,
	selecting: () -> (ComposeTypes.Use) -> boolean,
	attach: <N>(N & Instance, { Types.Child }) -> N & Instance,
	available: (GuiObject) -> ComposeTypes.ReadOnlyValue<boolean>,
	centered: (GuiObject, number) -> GuiObject,
	skin: (GuiObject, string?, PanelSkin?) -> GuiObject,
	inset: (number, string, string?, ComposeTypes.Use?) -> number,
	modal: (() -> GuiObject, (string?) -> (), ModalOptions?) -> Frame,
	overlay: (GuiObject, Types.ValueBoolean, (PresencePhase?) -> Instance, OverlayOptions?) -> Types.Child,
	appearance: (PresencePhase?, MotionTiming, ComposeTypes.ReadOnlyValue<boolean>?) -> Presence,
	popover: (
		GuiObject,
		Appearance,
		(ComposeTypes.Use) -> (Vector2, Vector2),
		PopoverOptions?
	) -> (ComposeTypes.Use) -> number,
	atRest: (
		Appearance,
		ComposeTypes.Value<boolean>,
		{ GuiObject },
		((ComposeTypes.Use) -> string)?
	) -> ({ ComposeTypes.ReadOnlyValue<Vector2> }, ComposeTypes.ReadOnlyValue<boolean>),
	sheetModal: ((Types.FrameProps & SheetOptions, SheetRequest, PresencePhase?) -> Frame)?,
}
export type SplitColumn = "sidebar" | "detail"
export type NavigationSplitViewOptions = {
	axis: ("x" | "y")?,
	resizable: Types.ValueBoolean?,
	alwaysShowResizeHandle: Types.ValueBoolean?,
	sidebarHeight: ComposeTypes.Value<number>?,
	minSidebarHeight: number?,
	maxSidebarHeight: number?,
	minDetailHeight: number?,
	compactHeight: number?,
	sidebar: Content,
	detail: Content,
	detailVisible: Types.ValueBoolean?,
	preferredCompactColumn: ComposeTypes.Value<SplitColumn>?,
	sidebarWidth: ComposeTypes.Value<number>?,
	minSidebarWidth: number?,
	maxSidebarWidth: number?,
	minDetailWidth: number?,
	compactWidth: number?,
	backLabel: Types.ValueString?,
	detailLabel: (Types.ValueString | false)?,
	compactBack: ComposeTypes.Value<boolean>?,
}
return {}
