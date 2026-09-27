--!strict
local Types = require("./types")

type Value<T> = Types.Value<T>

export type Rect = { x: number, y: number, w: number, h: number }
export type ScaleMode = "fit" | "crop" | "stretch"
export type Media = {
	image: string,
	aspectRatio: number?,
	height: (number | string)?,
	scaleMode: ScaleMode?,
	background: Value<Color3>?,
}
export type Hero = {
	image: string?,
	content: (Instance | (() -> Instance))?,
	aspectRatio: number?,
	height: (number | string)?,
	scaleMode: ScaleMode?,
	background: Value<Color3>?,
	sticky: boolean?,
}
export type ActionRole = "default" | "cancel" | "destructive"
export type Action = {
	id: string,
	label: Types.ValueString,
	role: ActionRole?,
	enabled: Types.ValueBoolean?,
	busy: Types.ValueBoolean?,
	onActivate: () -> (),
}
export type DialogAction = {
	id: string,
	label: Types.ValueString,
	role: ActionRole?,
	enabled: Types.ValueBoolean?,
	busy: Types.ValueBoolean?,
	keepOpen: boolean?,
	onActivate: () -> (),
}
export type ActionLayout = "automatic" | "row" | "stacked"
export type WidthPreset = "automatic" | "narrow" | "wide"
export type Edge = "top" | "bottom" | "leading" | "trailing"
export type Align = "start" | "center" | "end"

export type DialogDismissReason = "close" | "outside" | "cancel" | "action"
export type DialogSpec = Types.FrameProps & {
	isPresented: Types.ValueBoolean,
	onPresentedChange: ((boolean) -> ())?,
	onDismiss: ((DialogDismissReason) -> ())?,
	title: Types.ValueString?,
	content: (() -> Instance)?,
	hero: Media?,
	actionLabel: Types.ValueString?,
	actions: { DialogAction }?,
	actionLayout: ActionLayout?,
	closeButton: boolean?,
	width: WidthPreset?,
	contentSelectable: boolean?,
}

export type DialogConstructor = ((DialogSpec) -> Frame) & ((string) -> (DialogSpec) -> Frame)

export type PopoverDismissReason = "cancel" | "outside" | "trigger" | "anchorLost"
export type PopoverSource = { node: GuiObject } | { rect: Rect }
export type PopoverSpec = Types.FrameProps & {
	isPresented: Types.ValueBoolean,
	onPresentedChange: ((boolean) -> ())?,
	onDismiss: ((PopoverDismissReason) -> ())?,
	trigger: GuiButton?,
	source: PopoverSource?,
	content: () -> Instance,
	edge: Edge?,
	align: Align?,
	gap: number?,
	crossOffset: number?,
	tail: boolean?,
	maxWidth: number?,
	maxHeight: number?,
	compact: ("sheet" | "popover")?,
	title: Types.ValueString?,
	modal: boolean?,
	cancelPolicy: ("dismiss" | "none")?,
}

export type NoticeSeverity = "info" | "success" | "warning" | "error"
export type NoticeSpec = Types.FrameProps & {
	message: Types.ValueString,
	title: Types.ValueString?,
	severity: NoticeSeverity?,
	appearance: ("standard" | "emphasis")?,
	placement: ("inline" | "affixed")?,
	icon: (boolean | string)?,
	link: { label: Types.ValueString, onActivate: () -> () }?,
	actions: { Action }?,
	onDismiss: (() -> ())?,
	controlSize: Value<Types.ControlSize>?,
}

export type NavBarSpec = Types.FrameProps & {
	onBack: (() -> ())?,
	backLabel: string?,
	title: Types.ValueString?,
	titleSize: string?,
	leading: GuiObject?,
	center: GuiObject?,
	trailing: GuiObject?,
	gap: number?,
	padding: number?,
	surface: ("surface" | "panel" | "pane")?,
}

export type ToastDismissReason =
	"timeout"
	| "supersede"
	| "preempt"
	| "capacity"
	| "manual"
	| "action"
	| "close"
	| "cancel"
export type ToastAction = { label: Types.ValueString, onActivate: () -> () }
export type ToastSpec = Types.FrameProps & {
	message: Types.ValueString?,
	content: (() -> Instance)?,
	icon: string?,
	action: ToastAction?,
	closeButton: boolean?,
	isPresented: Types.ValueBoolean?,
	onPresentedChange: ((boolean) -> ())?,
	key: string?,
	priority: number?,
	duration: number?,
	readFloor: number?,
	position: ("top" | "bottom")?,
	width: ("fill" | "hug")?,
	fade: boolean?,
	onDismiss: ((ToastDismissReason) -> ())?,
}

export type OverlayControls = {
	Dialog: Types.Constructor<DialogSpec, Frame>,
	Popover: Types.Constructor<PopoverSpec, GuiObject>,
	Toast: Types.Constructor<ToastSpec, Frame>,
	Notice: Types.Constructor<NoticeSpec, Frame>,
	NavBar: Types.Constructor<NavBarSpec, Frame>,
}

return {}
