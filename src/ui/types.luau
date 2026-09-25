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
	wrap: Value<boolean>?,
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
	reducedMotion: Value<boolean>?,
	pressHaptic: HapticEffect?,
	onError: ((unknown) -> ())?,
}
export type ResolvedConfig = Config & { services: Services }
export type Read = <T>(Value<T>, Use?) -> T
export type ModalPortal = { node: Instance, anchor: Instance }
export type ActionBinding = string | Enum.KeyCode | InputBindingNativeProps
export type ActionBindings = { ActionBinding } | { Enum.KeyCode } | { InputBindingNativeProps } | { string }
export type ActionSettings = { priority: number?, sink: boolean?, onReleased: (() -> ())?, capture: boolean? }
export type SkinStateOptions = { disabled: Value<boolean>?, selected: Value<boolean>? }
export type Context = {
	runtime: Runtime,
	Host: Host,
	Compose: ComposeModule,
	types: RobloxTypes,
	config: ResolvedConfig,
	metrics: { textSize: number, controlHeight: number, gap: number, cornerRadius: number },
	read: Read,
	readSource: <T>(Readable<T>, Use?) -> T,
	metric: (string, Use?) -> number,
	controlSize: (Value<ControlSize>?, "height" | "paddingX" | "iconSize", Use?) -> number,
	pointerOnly: () -> (Use?) -> boolean,
	hitFloor: () -> (Use?) -> number,
	observe: Observe,
	observeStyled: Observe,
	shiftRoute: (Instance, () -> ()) -> (),
	whenSelected: (Instance, Instance, () -> ()) -> (),
	shiftActivation: (Instance, InputObject?) -> (() -> ())?,
	playWhileShown: (Playback, Instance) -> (),
	props: <P>(P, { string } | { [string]: boolean }?, unknown?) -> P,
	construct: <F>(string, F) -> F & ((string) -> F),
	styled: <N>(N & Instance, string) -> N & Instance,
	padding: (number, number) -> UIPadding,
	corner: (number?) -> UICorner,
	text: (TextLabelNativeProps?) -> TextLabel,
	row: ({ Child }, FrameNativeProps?) -> Frame,
	column: ({ Child }, FrameNativeProps?) -> Frame,
	icon: (Value<string>, ImageLabelNativeProps?, Value<Theme.SkinState>?) -> ImageLabel,
	iconVaries: (Value<string>?) -> boolean,
	modalScopes: Cell<{ Instance }>,
	modalPortals: Cell<{ ModalPortal }>,
	modalPortal: (Instance, Instance) -> (),
	available: (Instance, Use?) -> boolean,
	action: (
		Instance,
		string,
		ActionBindings,
		Value<boolean>?,
		() -> (),
		ActionSettings?
	) -> (InputAction, InputContext),
	skin: (GuiObject, string, SkinStateOptions?) -> (Dispose?, GuiObject?),
}

return {}
