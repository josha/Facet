--!strict
local ComposeTypes = require("../vendor/compose/core")
local Engine = require("./engine_types")
local Theme = require("./theme_types")

export type ComposeModule = typeof(ComposeTypes)
export type Runtime = ComposeTypes.Runtime
export type Source<T> = ComposeTypes.Source<T>
export type Readable<T> = ComposeTypes.Readable<T>
export type Cell<T> = ComposeTypes.Cell<T>
export type Use = ComposeTypes.Use
export type Child = ComposeTypes.Child
export type Dispose = ComposeTypes.Dispose
export type Value<T> = Engine.Value<T>
export type ValueString = Engine.ValueString
export type ValueBoolean = Engine.ValueBoolean
export type ValueNumber = Engine.ValueNumber

export type Constructor<P, N> = Engine.Constructor<P, N>
export type Host = Engine.Host
export type Attributes = Engine.Attributes
export type AttributeValue = Engine.AttributeValue
export type RobloxTypes = Engine.RobloxTypes
export type Observe = Engine.Observe
export type Playback = typeof(((nil :: unknown) :: Runtime).timeline())
export type ControlSize = "xsmall" | "compact" | "regular" | "large"
export type SpaceStep = "xs" | "s" | "m" | "l" | "xl"
export type Space = number | SpaceStep | string
export type Sides = { top: Space?, right: Space?, bottom: Space?, left: Space? }
export type Padding = Space | Sides
export type Extent = number | "fill" | "hug"
export type Align = "start" | "center" | "end" | "stretch"
export type Distribute = "start" | "center" | "end" | "spaceBetween" | "spaceAround" | "spaceEvenly"
export type Edge = "start" | "center" | "end"
export type Box = {
	padding: Value<Padding>?,
	width: Value<Extent>?,
	height: Value<Extent>?,
}
export type Flow = {
	padding: Value<Padding>?,
	width: Value<Extent>?,
	height: Value<Extent>?,
	gap: Value<Space>?,
	align: Value<Align>?,
	distribute: Value<Distribute>?,
	wrap: Engine.ValueBoolean?,
}

export type BillboardGuiProps = Engine.BillboardGuiProps
export type BillboardGuiNativeProps = Engine.BillboardGuiNativeProps
export type CameraProps = Engine.CameraProps
export type CameraNativeProps = Engine.CameraNativeProps
export type CanvasGroupProps = Engine.CanvasGroupProps
export type CanvasGroupNativeProps = Engine.CanvasGroupNativeProps
export type FolderProps = Engine.FolderProps
export type FolderNativeProps = Engine.FolderNativeProps
export type FrameProps = Engine.FrameProps
export type FrameNativeProps = Engine.FrameNativeProps
export type GuiButtonProps = Engine.GuiButtonProps
export type GuiButtonNativeProps = Engine.GuiButtonNativeProps
export type GuiObjectProps = Engine.GuiObjectProps
export type GuiObjectNativeProps = Engine.GuiObjectNativeProps
export type ImageButtonProps = Engine.ImageButtonProps
export type ImageButtonNativeProps = Engine.ImageButtonNativeProps
export type ImageLabelProps = Engine.ImageLabelProps
export type ImageLabelNativeProps = Engine.ImageLabelNativeProps
export type InputActionProps = Engine.InputActionProps
export type InputActionNativeProps = Engine.InputActionNativeProps
export type InputBindingProps = Engine.InputBindingProps
export type InputBindingNativeProps = Engine.InputBindingNativeProps
export type InputContextProps = Engine.InputContextProps
export type InputContextNativeProps = Engine.InputContextNativeProps
export type Path2DProps = Engine.Path2DProps
export type Path2DNativeProps = Engine.Path2DNativeProps
export type ScreenGuiProps = Engine.ScreenGuiProps
export type ScreenGuiNativeProps = Engine.ScreenGuiNativeProps
export type ScrollingFrameProps = Engine.ScrollingFrameProps
export type ScrollingFrameNativeProps = Engine.ScrollingFrameNativeProps
export type StyleRuleProps = Engine.StyleRuleProps
export type StyleRuleNativeProps = Engine.StyleRuleNativeProps
export type StyleSheetProps = Engine.StyleSheetProps
export type StyleSheetNativeProps = Engine.StyleSheetNativeProps
export type SurfaceGuiProps = Engine.SurfaceGuiProps
export type SurfaceGuiNativeProps = Engine.SurfaceGuiNativeProps
export type TextBoxProps = Engine.TextBoxProps
export type TextBoxNativeProps = Engine.TextBoxNativeProps
export type TextButtonProps = Engine.TextButtonProps
export type TextButtonNativeProps = Engine.TextButtonNativeProps
export type TextLabelProps = Engine.TextLabelProps
export type TextLabelNativeProps = Engine.TextLabelNativeProps
export type UIAspectRatioConstraintProps = Engine.UIAspectRatioConstraintProps
export type UIAspectRatioConstraintNativeProps = Engine.UIAspectRatioConstraintNativeProps
export type UICornerProps = Engine.UICornerProps
export type UICornerNativeProps = Engine.UICornerNativeProps
export type UIDragDetectorProps = Engine.UIDragDetectorProps
export type UIDragDetectorNativeProps = Engine.UIDragDetectorNativeProps
export type UIFlexItemProps = Engine.UIFlexItemProps
export type UIFlexItemNativeProps = Engine.UIFlexItemNativeProps
export type UIGradientProps = Engine.UIGradientProps
export type UIGradientNativeProps = Engine.UIGradientNativeProps
export type UIGridLayoutProps = Engine.UIGridLayoutProps
export type UIGridLayoutNativeProps = Engine.UIGridLayoutNativeProps
export type UIListLayoutProps = Engine.UIListLayoutProps
export type UIListLayoutNativeProps = Engine.UIListLayoutNativeProps
export type UIPaddingProps = Engine.UIPaddingProps
export type UIPaddingNativeProps = Engine.UIPaddingNativeProps
export type UIPageLayoutProps = Engine.UIPageLayoutProps
export type UIPageLayoutNativeProps = Engine.UIPageLayoutNativeProps
export type UIScaleProps = Engine.UIScaleProps
export type UIScaleNativeProps = Engine.UIScaleNativeProps
export type UIShadowProps = Engine.UIShadowProps
export type UIShadowNativeProps = Engine.UIShadowNativeProps
export type UISizeConstraintProps = Engine.UISizeConstraintProps
export type UISizeConstraintNativeProps = Engine.UISizeConstraintNativeProps
export type UIStrokeProps = Engine.UIStrokeProps
export type UIStrokeNativeProps = Engine.UIStrokeNativeProps
export type ViewportFrameProps = Engine.ViewportFrameProps
export type ViewportFrameNativeProps = Engine.ViewportFrameNativeProps
export type WorldModelProps = Engine.WorldModelProps
export type WorldModelNativeProps = Engine.WorldModelNativeProps

export type Services = {
	GuiService: GuiService?,
	UserInputService: UserInputService?,
	Players: Players?,
	RunService: RunService?,
	TextService: TextService?,
	ContentProvider: ContentProvider?,
	Workspace: Workspace?,
	TweenService: TweenService?,
}
export type MotionLevel = "normal" | "limited" | "none"
export type HapticKind = "selection" | "impact" | "success" | "warning" | "error"
export type Config = {
	types: RobloxTypes?,
	services: Services?,
	guiService: GuiService?,
	userInputService: UserInputService?,
	inputParent: Instance?,
	overlayParent: Instance?,
	controlSize: Value<ControlSize>?,
	theme: Value<Theme.ThemePackage>?,
	icons: Value<{ [string]: Theme.IconEntry }>?,
	motionLevel: Value<MotionLevel>?,
	pressHaptic: (HapticEffect | HapticKind)?,
	onError: ((unknown) -> ())?,
	environment: EnvironmentPreview?,
	keyboardNavigation: boolean?,
}
export type EnvironmentPreview = {
	preferredInput: Value<(Enum.PreferredInput | string)?>?,
	touchEnabled: Value<boolean?>?,
	mouseEnabled: Value<boolean?>?,
	gamepadEnabled: Value<boolean?>?,
	keyboardEnabled: Value<boolean?>?,
	preferredTextSize: Value<(Enum.PreferredTextSize | string)?>?,
	displaySize: Value<(Enum.DisplaySize | string)?>?,
	viewportSize: Value<Vector2?>?,
	viewingDistance: Value<("automatic" | "near" | "ten-foot")?>?,
	overscanInsets: Value<({ top: number, left: number, bottom: number, right: number } | "none")?>?,
}
export type ResolvedConfig = Config & { services: Services }
export type Read = <T>(Value<T>, Use?) -> T
export type ModalPortal = { node: Instance, anchor: Instance }
export type ActionBinding = string | Enum.KeyCode | InputBindingNativeProps
export type ActionBindings = { ActionBinding } | { Enum.KeyCode } | { InputBindingNativeProps } | { string }
export type ActionSettings = {
	priority: number?,
	sink: boolean?,
	onReleased: (() -> ())?,
	capture: boolean?,
	group: string?,
	conditional: { binding: ActionBinding, when: (ComposeTypes.Use) -> boolean }?,
	direction2D: ((Vector2) -> ())?,
}
export type ListRow = {
	leading: { Child }?,
	captions: { GuiObject },
	trailing: { Child }?,
	described: boolean,
	controlSize: Value<ControlSize>?,
}
export type SkinStateOptions = {
	disabled: Engine.ValueBoolean?,
	selected: Engine.ValueBoolean?,
	label: Engine.ValueString?,
	onCaption: ((boolean) -> ())?,
}
export type ResponderOptions = { passive: boolean?, gameplayGuard: boolean?, traversalWrap: boolean? }
export type ResponderState = "passive" | "engaged"
export type Responder = { state: Readable<ResponderState>, engage: () -> (), resign: () -> () }
export type FocusDirection = "Up" | "Down" | "Left" | "Right"
export type FocusMove = { target: GuiObject?, rule: string }
export type FocusQuery = { Up: FocusMove, Down: FocusMove, Left: FocusMove, Right: FocusMove }
export type Context = {
	runtime: Runtime,
	Host: Host,
	Compose: ComposeModule,
	types: RobloxTypes,
	config: ResolvedConfig,
	metrics: { textSize: number, controlHeight: number, gap: number, cornerRadius: number },
	read: Read,
	readSource: <T>(Readable<T>, Use?) -> T,
	haptic: (kind: unknown) -> HapticEffect?,
	metric: (string, Use?) -> number,
	motionTiming: (string, Use?) -> { enter: number, exit: number },
	motionSpring: (string, Use?) -> { period: number, damping: number },
	motionEase: (string, Use?) -> (number) -> number,
	motionStyle: (string, Use?) -> Enum.EasingStyle,
	neutralMetrics: (Use?) -> Theme.Metrics,
	controlSize: (Value<ControlSize>?, "height" | "paddingX" | "iconSize", Use?) -> number,
	pointerOnly: () -> (Use?) -> boolean,
	hitFloor: () -> (Use?) -> number,
	tenFoot: () -> (Use?) -> boolean,
	viewingDistance: (Use?) -> "automatic" | "near" | "ten-foot",
	effectiveInput: () -> (Use?) -> "Touch" | "Gamepad" | "KeyboardAndMouse",
	touchFloor: () -> (Use?) -> number,
	observe: Observe,
	observeStyled: Observe,
	shiftRoute: (Instance, () -> ()) -> (),
	whenSelected: (Instance, Instance, () -> ()) -> (),
	selectionHooks: { (unknown) -> () },
	shiftActivation: (Instance, InputObject?) -> (() -> ())?,
	playWhileShown: (Playback, Instance) -> (),
	props: <P>(P, { string } | { [string]: boolean }?, unknown?) -> P,
	construct: <F>(string, F) -> F & ((string) -> F),
	styled: <N>(N & Instance, string) -> N & Instance,
	padding: (number, number) -> UIPadding,
	round: (ComposeTypes.Use?, UDim?) -> UDim,
	corner: (number?) -> UICorner,
	fade: (CanvasGroupNativeProps) -> Frame,
	fadeTo: (Instance, Engine.ValueNumber) -> (),
	text: (TextLabelNativeProps?) -> TextLabel,
	row: ({ Child }, FrameNativeProps?) -> Frame,
	layoutUnit: (GuiBase2d) -> ComposeTypes.Readable<number>,
	layoutSize: (GuiBase2d, ComposeTypes.Readable<number>?) -> ComposeTypes.Readable<Vector2>,
	layoutBounds: (TextLabel | TextButton | TextBox, ComposeTypes.Readable<number>?) -> ComposeTypes.Readable<Vector2>,
	column: ({ Child }, FrameNativeProps?) -> Frame,
	listRow: (ListRow) -> (Frame, Value<UDim2>, (GuiObject) -> ()),
	icon: (Engine.ValueString, ImageLabelNativeProps?, Value<Theme.SkinState>?) -> ImageLabel,
	iconVaries: (Engine.ValueString?) -> boolean,
	modalScopes: Cell<{ Instance }>,
	modalPortals: Cell<{ ModalPortal }>,
	modalPortal: (Instance, Instance) -> (),
	available: (Instance, Use?) -> boolean,
	navigationGamepads: () -> { Enum.UserInputType },
	action: (
		Instance,
		string,
		ActionBindings,
		Engine.ValueBoolean?,
		() -> (),
		ActionSettings?
	) -> (InputAction, InputContext),
	skin: (GuiObject, string, SkinStateOptions?) -> (Dispose?, GuiObject?),
	responder: (Instance, ResponderOptions?) -> Responder,
	spaceActivates: (Instance) -> (Use) -> boolean,
	focusQuery: (GuiObject?) -> FocusQuery,
	focusPast: (GuiObject, FocusDirection) -> GuiObject?,
	layoutKit: unknown?,
	showHelp: unknown?,
	reducedMotion: unknown?,
}

return {}
