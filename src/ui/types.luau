--!strict
local Compose = require("../vendor/compose/core")
local Engine = require("./engine_types")
local Theme = require("./theme_types")

export type Runtime = Compose.Runtime
export type Source<T> = Compose.Source<T>
export type Readable<T> = Compose.Readable<T>
export type Cell<T> = Compose.Cell<T>
export type Use = Compose.Use
export type Child = Compose.Child
export type Dispose = Compose.Dispose
export type Value<T> = Engine.Value<T>
export type Constructor<P, N> = Engine.Constructor<P, N>
export type Host = Engine.Host
export type Attributes = Engine.Attributes
export type AttributeValue = Engine.AttributeValue
export type RobloxTypes = Engine.RobloxTypes
export type Observe = Engine.Observe
export type ControlSize = "compact" | "regular" | "large"

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
	onError: ((unknown) -> ())?,
}
export type ResolvedConfig = Config & { services: Services }
export type Read =
	(<T>(Compose.Cell<T>, Use?) -> T)
	& (<T>(Compose.Formula<T>, Use?) -> T)
	& (<T>(Compose.Readable<T>, Use?) -> T)
	& (<T>(Compose.Body<T>, Use?) -> T)
	& (<T>(Value<T>, Use?) -> T)
export type ModalPortal = { node: Instance, anchor: Instance }
export type ActionBinding = string | Enum.KeyCode | InputBindingNativeProps
export type ActionSettings = { priority: number?, sink: boolean?, onReleased: (() -> ())? }
export type SkinStateOptions = { disabled: Value<boolean>?, selected: Value<boolean>? }
export type Context = {
	runtime: Runtime,
	Host: Host,
	Compose: typeof(Compose),
	types: RobloxTypes,
	config: ResolvedConfig,
	metrics: { textSize: number, controlHeight: number, gap: number, cornerRadius: number },
	read: Read,
	metric: (string, Use?) -> number,
	controlSize: (Value<ControlSize>?, "height" | "paddingX" | "iconSize", Use?) -> number,
	observe: Observe,
	observeStyled: Observe,
	props: <P>(P, { string } | { [string]: boolean }?, unknown?) -> P,
	construct: <F>(F) -> F & ((string) -> F),
	styled: <N>(N & Instance, string) -> N & Instance,
	padding: (number, number) -> UIPadding,
	corner: (number?) -> UICorner,
	text: (TextLabelNativeProps?) -> TextLabel,
	row: ({ Child }, FrameNativeProps?) -> Frame,
	column: ({ Child }, FrameNativeProps?) -> Frame,
	icon: (Value<string>, ImageLabelNativeProps?, Value<Theme.SkinState>?) -> ImageLabel,
	modalScopes: Cell<{ Instance }>,
	modalPortals: Cell<{ ModalPortal }>,
	modalPortal: (Instance, Instance) -> (),
	available: (Instance, Use?) -> boolean,
	action: (
		Instance,
		string,
		{ ActionBinding },
		Value<boolean>?,
		() -> (),
		ActionSettings?
	) -> (InputAction, InputContext),
	skin: (GuiObject, string, SkinStateOptions?) -> (Dispose?, GuiObject?),
}

return {}
