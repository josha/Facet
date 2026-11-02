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
	read seconds: Types.ValueNumber?,
	read ease: ComposeTypes.Easing?,
	read motion: string?,
	read fade: boolean?,
	read progress: ComposeTypes.ReadOnlyValue<number?>?,
	read apply: ((GuiObject, TransitionContext) -> ())?,
	read scale: (number | true)?,
	read zoom: number?,
}
export type SourceTransition = {
	read seconds: Types.ValueNumber?,
	read ease: ComposeTypes.Easing?,
	read source: Input<GuiObject?>?,
}
export type MenuTrigger = "activate" | "secondary" | "longPress" | "keyboard" | "gamepad"
export type OptionAvatar = MenuAvatar
export type OptionIndicator = {
	read status: Input<"neutral" | "info" | "success" | "warning" | "error" | "accent">?,
	read form: ("dot" | "ring" | "square" | "dash")?,
	read count: Types.ValueNumber?,
}
export type MenuItemBase = {
	read role: Input<"default" | "cancel" | "destructive" | "onIndicator">?,
	read id: string?,
	read label: Types.ValueString,
	read description: Types.ValueString?,
	read icon: Types.ValueString?,
	read meta: Types.ValueString?,
	read enabled: Types.ValueBoolean?,
	read marked: Types.ValueBoolean?,
	read dismiss: boolean?,
	read divider: false?,
	read badge: Input<(string | number)?>?,
	read avatar: MenuAvatar?,
	read sectionTitle: Types.ValueString?,
	read shortcutLabel: Types.ValueString?,
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
	read role: Input<"default" | "cancel" | "destructive" | "onIndicator">?,
	read id: string?,
	read label: Types.ValueString,
	read description: Types.ValueString?,
	read icon: Types.ValueString?,
	read meta: Types.ValueString?,
	read enabled: Types.ValueBoolean?,
	read marked: Types.ValueBoolean?,
	read dismiss: boolean?,
	read divider: false?,
	read badge: Input<(string | number)?>?,
	read avatar: MenuAvatar?,
	read sectionTitle: Types.ValueString?,
	read shortcutLabel: Types.ValueString?,
	read children: Input<{ MenuItem<V> }>,
	read onSelect: nil,
	read checked: nil,
	read selected: nil,
}
export type MenuCommand = {
	read role: Input<"default" | "cancel" | "destructive" | "onIndicator">?,
	read id: string?,
	read label: Types.ValueString,
	read description: Types.ValueString?,
	read icon: Types.ValueString?,
	read meta: Types.ValueString?,
	read enabled: Types.ValueBoolean?,
	read marked: Types.ValueBoolean?,
	read dismiss: boolean?,
	read divider: false?,
	read badge: Input<(string | number)?>?,
	read avatar: MenuAvatar?,
	read sectionTitle: Types.ValueString?,
	read shortcutLabel: Types.ValueString?,
	read children: nil,
	read onSelect: () -> (),
	read checked: nil,
	read selected: nil,
}
export type MenuCheck = {
	read role: Input<"default" | "cancel" | "destructive" | "onIndicator">?,
	read id: string?,
	read label: Types.ValueString,
	read description: Types.ValueString?,
	read icon: Types.ValueString?,
	read meta: Types.ValueString?,
	read enabled: Types.ValueBoolean?,
	read marked: Types.ValueBoolean?,
	read dismiss: boolean?,
	read divider: false?,
	read badge: Input<(string | number)?>?,
	read avatar: MenuAvatar?,
	read sectionTitle: Types.ValueString?,
	read shortcutLabel: Types.ValueString?,
	read children: nil,
	read checked: ComposeTypes.Value<boolean>,
	read selected: nil,
	read onChange: ((boolean) -> ())?,
	read onSelect: (() -> ())?,
}
export type MenuChoice<V = string> = {
	read role: Input<"default" | "cancel" | "destructive" | "onIndicator">?,
	read id: string?,
	read label: Types.ValueString,
	read description: Types.ValueString?,
	read icon: Types.ValueString?,
	read meta: Types.ValueString?,
	read enabled: Types.ValueBoolean?,
	read marked: Types.ValueBoolean?,
	read dismiss: boolean?,
	read divider: false?,
	read badge: Input<(string | number)?>?,
	read avatar: MenuAvatar?,
	read sectionTitle: Types.ValueString?,
	read shortcutLabel: Types.ValueString?,
	read children: nil,
	read checked: nil,
	read selected: ComposeTypes.Value<V>,
	read value: V,
	read onChange: ((V) -> ())?,
	read onSelect: (() -> ())?,
}
export type MenuAction<V = string> = MenuSubmenu<V> | MenuCommand | MenuChoice<V> | MenuCheck
export type MenuItem<V = string> = { read id: string?, read divider: true } | MenuAction<V>
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
	read id: string?,
	read value: V,
	read label: Types.ValueString,
	read description: Types.ValueString?,
	read icon: Types.ValueString?,
	read badge: Input<(string | number)?>?,
	read meta: Types.ValueString?,
	read avatar: OptionAvatar?,
	read sectionTitle: Types.ValueString?,
	read indicator: OptionIndicator?,
	read enabled: Types.ValueBoolean?,
}
export type PickerOptions<V = string> = { read [number]: PickerOption<V> }
export type PickerStyle = "automatic" | "menu" | "navigationLink" | "segmented" | "inline" | "radioGroup" | "cards"
export type PickerCommon<V> = {
	Style: Input<Enum.FrameStyle>?,
	read options: Input<PickerOptions<V>>,
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
	read id: string,
	read label: Types.ValueString,
	read role: "default" | "cancel" | "destructive"?,
	read enabled: Types.ValueBoolean?,
	read shortcut: "defaultAction" | "cancelAction" | Inputs.Shortcut?,
	read onActivate: ((P) -> ())?,
}
export type AlertActions<P> = { read [number]: AlertAction<P> }
export type AlertText<P> = string | ComposeTypes.ReadOnlyValue<string> | ComposeTypes.Value<string> | ((P) -> string)
export type AlertOptions<P = unknown> = {
	read isPresented: ComposeTypes.Value<boolean>?,
	read item: ComposeTypes.Value<P?>?,
	read presenting: Input<P>?,
	read title: AlertText<P>?,
	read message: AlertText<P>?,
	read actions: AlertActions<P> | ((P) -> AlertActions<P>)?,
	read content: ((P) -> Instance)?,
	read error: ComposeTypes.Value<string?>?,
	read icon: Types.ValueString?,
	read severity: "information" | "warning" | "critical"?,
	read suppression: { read isSuppressed: ComposeTypes.Value<boolean>, read label: Types.ValueString? }?,
	read maxWidth: number?,
	read padding: number?,
	read surface: "dialog" | "fullScreen"?,
	read transition: SourceTransition | false?,
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
	read id: string,
	read badge: Input<(string | number)?>?,
	read badgeAnchor: Input<"topLeading" | "topTrailing" | "bottomLeading" | "bottomTrailing">?,
	read label: Types.ValueString?,
	read icon: Types.ValueString?,
	read glyph: (() -> GuiObject)?,
	read content: Content,
	read section: string?,
	read required: boolean?,
	read indicator: TabIndicator?,
	read enabled: Types.ValueBoolean?,
}
export type TabIndicator = {
	read form: ("dot" | "ring" | "square" | "dash")?,
	read status: ("neutral" | "info" | "success" | "warning" | "error" | "accent")?,
	read count: Input<number?>?,
	read max: number?,
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
	read title: Types.ValueString?,
	read chrome: Input<"automatic" | "hidden">?,
	read initialFocus: (string | () -> string?)?,
	read content: Instance | ((NavigationEntry<P>?) -> Instance),
	read onBack: ((NavigationEntry<P>) -> boolean?)?,
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
export type Attach = (Instance, Types.ChildList) -> ()
export type Surfaces = {
	parent: (Instance) -> GuiBase2d?,
	service: (("GuiService") -> GuiService?) & (("UserInputService") -> UserInputService?),
	within: (Instance?, Instance) -> boolean,
	keep: (...unknown) -> (),
	firstSelectable: (Instance, string?, ((Instance) -> boolean)?) -> GuiObject?,
	displayed: (Instance) -> boolean,
	preference: () -> (ComposeTypes.Use) -> number,
	selecting: () -> (ComposeTypes.Use) -> boolean,
	attach: Attach,
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
	transition: Transition | false?,
}
return {}
