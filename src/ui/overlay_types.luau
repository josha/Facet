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
	label: Value<string>,
	role: ActionRole?,
	enabled: Value<boolean>?,
	busy: Value<boolean>?,
	onActivate: () -> (),
}
export type ActionLayout = "automatic" | "row" | "stacked"
export type WidthPreset = "automatic" | "narrow" | "wide"
export type Edge = "top" | "bottom" | "leading" | "trailing"
export type Align = "start" | "center" | "end"

export type DialogDismissReason = "close" | "outside" | "cancel" | "action"
export type DialogSpec = Types.FrameProps & {
	isPresented: Value<boolean>,
	onPresentedChange: ((boolean) -> ())?,
	onDismiss: ((DialogDismissReason) -> ())?,
	title: Value<string>?,
	content: (() -> Instance)?,
	hero: Media?,
	actionLabel: Value<string>?,
	actions: { Action }?,
	actionLayout: ActionLayout?,
	closeButton: boolean?,
	width: WidthPreset?,
	contentSelectable: boolean?,
}

export type DialogConstructor = ((DialogSpec) -> Frame) & ((string) -> (DialogSpec) -> Frame)

export type PopoverDismissReason = "cancel" | "outside" | "trigger" | "anchorLost"
export type PopoverSource = { node: GuiObject } | { rect: Rect }
export type PopoverSpec = Types.FrameProps & {
	isPresented: Value<boolean>,
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
	title: Value<string>?,
}

export type SnackbarDismissReason = "action" | "close" | "timeout" | "superseded" | "cancel"
export type SnackbarAction = { label: Value<string>, onActivate: () -> () }
export type SnackbarSpec = Types.FrameProps & {
	isPresented: Value<boolean>,
	message: Value<string>,
	icon: string?,
	action: SnackbarAction?,
	closeButton: boolean?,
	onPresentedChange: ((boolean) -> ())?,
	onDismiss: ((SnackbarDismissReason) -> ())?,
	duration: number?,
	priority: number?,
}

export type NoticeSeverity = "info" | "success" | "warning" | "error"
export type NoticeSpec = Types.FrameProps & {
	message: Value<string>,
	title: Value<string>?,
	severity: NoticeSeverity?,
	appearance: ("standard" | "emphasis")?,
	placement: ("inline" | "affixed")?,
	icon: (boolean | string)?,
	link: { label: Value<string>, onActivate: () -> () }?,
	actions: { Action }?,
	onDismiss: (() -> ())?,
	controlSize: Value<Types.ControlSize>?,
}

export type NavBarSpec = Types.FrameProps & {
	onBack: (() -> ())?,
	backLabel: string?,
	title: Value<string>?,
	titleSize: string?,
	leading: GuiObject?,
	center: GuiObject?,
	trailing: GuiObject?,
	gap: number?,
	padding: number?,
}

export type OverlayControls = {
	Dialog: Types.Constructor<DialogSpec, Frame>,
	Popover: Types.Constructor<PopoverSpec, GuiObject>,
	Snackbar: Types.Constructor<SnackbarSpec, Frame>,
	Notice: Types.Constructor<NoticeSpec, Frame>,
	NavBar: Types.Constructor<NavBarSpec, Frame>,
}

return {}
