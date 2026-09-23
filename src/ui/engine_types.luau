--!strict
local Compose = require("../vendor/compose/core")

export type Value<T> = T | Compose.Source<T> | Compose.Cell<T> | Compose.Formula<T>
export type StaticValue = typeof(Compose.static(nil))
export type Constructor<P, N> = ((P) -> N) & ((string) -> (P) -> N)
export type AttributeValue =
	string
	| boolean
	| number
	| UDim
	| UDim2
	| BrickColor
	| Color3
	| Vector2
	| Vector3
	| CFrame
	| NumberSequence
	| ColorSequence
	| NumberRange
	| Rect
	| Font
export type Attributes = { [string]: Value<AttributeValue?> }

export type ObjectProperties = {
	Changed: ((string) -> ())?,
}
export type ObjectNativeProps = ObjectProperties & { [number]: Compose.Child }
export type ObjectProps = ObjectNativeProps & { ref: ((Object) -> ())? }

export type InstanceProperties = ObjectProperties & {
	Attributes: Attributes?,
	AncestryChanged: ((Instance, Instance?) -> ())?,
	Archivable: Value<boolean>?,
	AttributeChanged: ((string) -> ())?,
	Capabilities: Value<SecurityCapabilities>?,
	ChildAdded: ((Instance) -> ())?,
	ChildRemoved: ((Instance) -> ())?,
	DescendantAdded: ((Instance) -> ())?,
	DescendantRemoving: ((Instance) -> ())?,
	Destroying: (() -> ())?,
	Name: Value<string>?,
	Parent: (Value<Instance?> | StaticValue)?,
	Sandboxed: Value<boolean>?,
	StyledPropertiesChanged: (() -> ())?,
}
export type InstanceNativeProps = InstanceProperties & { [number]: Compose.Child }
export type InstanceProps = InstanceNativeProps & { ref: ((Instance) -> ())? }

export type GuiBaseProperties = InstanceProperties & {}
export type GuiBaseNativeProps = GuiBaseProperties & { [number]: Compose.Child }
export type GuiBaseProps = GuiBaseNativeProps & { ref: ((GuiBase) -> ())? }

export type GuiBase2dProperties = GuiBaseProperties & {
	AutoLocalize: Value<boolean>?,
	RootLocalizationTable: (Value<LocalizationTable> | StaticValue)?,
	SelectionBehaviorDown: Value<Enum.SelectionBehavior>?,
	SelectionBehaviorLeft: Value<Enum.SelectionBehavior>?,
	SelectionBehaviorRight: Value<Enum.SelectionBehavior>?,
	SelectionBehaviorUp: Value<Enum.SelectionBehavior>?,
	SelectionChanged: ((boolean, GuiObject, GuiObject) -> ())?,
	SelectionGroup: Value<boolean>?,
}
export type GuiBase2dNativeProps = GuiBase2dProperties & { [number]: Compose.Child }
export type GuiBase2dProps = GuiBase2dNativeProps & { ref: ((GuiBase2d) -> ())? }

export type LayerCollectorProperties = GuiBase2dProperties & {
	Enabled: Value<boolean>?,
	ResetOnSpawn: Value<boolean>?,
	ZIndexBehavior: Value<Enum.ZIndexBehavior>?,
}
export type LayerCollectorNativeProps = LayerCollectorProperties & { [number]: Compose.Child }
export type LayerCollectorProps = LayerCollectorNativeProps & { ref: ((LayerCollector) -> ())? }

export type BillboardGuiProperties = LayerCollectorProperties & {
	Active: Value<boolean>?,
	Adornee: (Value<Instance> | StaticValue)?,
	AlwaysOnTop: Value<boolean>?,
	Brightness: Value<number>?,
	ClipsDescendants: Value<boolean>?,
	DistanceStep: Value<number>?,
	ExtentsOffset: Value<Vector3>?,
	ExtentsOffsetWorldSpace: Value<Vector3>?,
	LightInfluence: Value<number>?,
	MaxDistance: Value<number>?,
	PlayerToHideFrom: (Value<Instance> | StaticValue)?,
	Size: Value<UDim2>?,
	SizeOffset: Value<Vector2>?,
	StudsOffset: Value<Vector3>?,
	StudsOffsetWorldSpace: Value<Vector3>?,
}
export type BillboardGuiNativeProps = BillboardGuiProperties & { [number]: Compose.Child }
export type BillboardGuiProps = BillboardGuiNativeProps & { ref: ((BillboardGui) -> ())? }

export type PVInstanceProperties = InstanceProperties & {}
export type PVInstanceNativeProps = PVInstanceProperties & { [number]: Compose.Child }
export type PVInstanceProps = PVInstanceNativeProps & { ref: ((PVInstance) -> ())? }

export type CameraProperties = PVInstanceProperties & {
	CFrame: Value<CFrame>?,
	CameraSubject: (Value<Humanoid | BasePart | nil> | StaticValue)?,
	CameraType: Value<Enum.CameraType>?,
	DiagonalFieldOfView: Value<number>?,
	FieldOfView: Value<number>?,
	FieldOfViewMode: Value<Enum.FieldOfViewMode>?,
	Focus: Value<CFrame>?,
	HeadLocked: Value<boolean>?,
	HeadScale: Value<number>?,
	InterpolationFinished: (() -> ())?,
	MaxAxisFieldOfView: Value<number>?,
	VRTiltAndRollEnabled: Value<boolean>?,
}
export type CameraNativeProps = CameraProperties & { [number]: Compose.Child }
export type CameraProps = CameraNativeProps & { ref: ((Camera) -> ())? }

export type GuiObjectProperties = GuiBase2dProperties & {
	Active: Value<boolean>?,
	AnchorPoint: Value<Vector2>?,
	AutomaticSize: Value<Enum.AutomaticSize>?,
	BackgroundColor3: Value<Color3>?,
	BackgroundTransparency: Value<number>?,
	BorderColor3: Value<Color3>?,
	BorderMode: Value<Enum.BorderMode>?,
	BorderSizePixel: Value<number>?,
	ClipsDescendants: Value<boolean>?,
	InputBegan: ((InputObject) -> ())?,
	InputChanged: ((InputObject) -> ())?,
	InputEnded: ((InputObject) -> ())?,
	InputSink: Value<Enum.InputSink>?,
	Interactable: Value<boolean>?,
	LayoutOrder: Value<number>?,
	MouseEnter: ((number, number) -> ())?,
	MouseLeave: ((number, number) -> ())?,
	MouseMoved: ((number, number) -> ())?,
	MouseWheelBackward: ((number, number) -> ())?,
	MouseWheelForward: ((number, number) -> ())?,
	NextSelectionDown: (Value<GuiObject> | StaticValue)?,
	NextSelectionLeft: (Value<GuiObject> | StaticValue)?,
	NextSelectionRight: (Value<GuiObject> | StaticValue)?,
	NextSelectionUp: (Value<GuiObject> | StaticValue)?,
	Position: Value<UDim2>?,
	Rotation: Value<number>?,
	Selectable: Value<boolean>?,
	SelectionGained: (() -> ())?,
	SelectionImageObject: (Value<GuiObject> | StaticValue)?,
	SelectionLost: (() -> ())?,
	SelectionOrder: Value<number>?,
	Size: Value<UDim2>?,
	SizeConstraint: Value<Enum.SizeConstraint>?,
	TouchLongPress: (({ Vector2 }, Enum.UserInputState) -> ())?,
	TouchPan: (({ Vector2 }, Vector2, Vector2, Enum.UserInputState) -> ())?,
	TouchPinch: (({ Vector2 }, number, number, Enum.UserInputState) -> ())?,
	TouchRotate: (({ Vector2 }, number, number, Enum.UserInputState) -> ())?,
	TouchSwipe: ((Enum.SwipeDirection, number) -> ())?,
	TouchTap: (({ Vector2 }) -> ())?,
	Visible: Value<boolean>?,
	ZIndex: Value<number>?,
}
export type GuiObjectNativeProps = GuiObjectProperties & { [number]: Compose.Child }
export type GuiObjectProps = GuiObjectNativeProps & { ref: ((GuiObject) -> ())? }

export type CanvasGroupProperties = GuiObjectProperties & {
	GroupColor3: Value<Color3>?,
	GroupTransparency: Value<number>?,
}
export type CanvasGroupNativeProps = CanvasGroupProperties & { [number]: Compose.Child }
export type CanvasGroupProps = CanvasGroupNativeProps & { ref: ((CanvasGroup) -> ())? }

export type FolderProperties = InstanceProperties & {}
export type FolderNativeProps = FolderProperties & { [number]: Compose.Child }
export type FolderProps = FolderNativeProps & { ref: ((Folder) -> ())? }

export type FrameProperties = GuiObjectProperties & {
	Style: Value<Enum.FrameStyle>?,
}
export type FrameNativeProps = FrameProperties & { [number]: Compose.Child }
export type FrameProps = FrameNativeProps & { ref: ((Frame) -> ())? }

export type GuiButtonProperties = GuiObjectProperties & {
	Activated: ((InputObject, number) -> ())?,
	AutoButtonColor: Value<boolean>?,
	HoverHapticEffect: (Value<HapticEffect> | StaticValue)?,
	Modal: Value<boolean>?,
	MouseButton1Click: (() -> ())?,
	MouseButton1Down: ((number, number) -> ())?,
	MouseButton1Up: ((number, number) -> ())?,
	MouseButton2Click: (() -> ())?,
	MouseButton2Down: ((number, number) -> ())?,
	MouseButton2Up: ((number, number) -> ())?,
	PressHapticEffect: (Value<HapticEffect> | StaticValue)?,
	SecondaryActivated: ((InputObject) -> ())?,
	Selected: Value<boolean>?,
	Style: Value<Enum.ButtonStyle>?,
}
export type GuiButtonNativeProps = GuiButtonProperties & { [number]: Compose.Child }
export type GuiButtonProps = GuiButtonNativeProps & { ref: ((GuiButton) -> ())? }

export type ImageButtonProperties = GuiButtonProperties & {
	HoverImage: Value<string>?,
	HoverImageContent: Value<Content>?,
	Image: Value<string>?,
	ImageColor3: Value<Color3>?,
	ImageContent: Value<Content>?,
	ImageRectOffset: Value<Vector2>?,
	ImageRectSize: Value<Vector2>?,
	ImageTransparency: Value<number>?,
	PressedImage: Value<string>?,
	PressedImageContent: Value<Content>?,
	ResampleMode: Value<Enum.ResamplerMode>?,
	ScaleType: Value<Enum.ScaleType>?,
	SliceCenter: Value<Rect>?,
	SliceScale: Value<number>?,
	TileSize: Value<UDim2>?,
}
export type ImageButtonNativeProps = ImageButtonProperties & { [number]: Compose.Child }
export type ImageButtonProps = ImageButtonNativeProps & { ref: ((ImageButton) -> ())? }

export type GuiLabelProperties = GuiObjectProperties & {}
export type GuiLabelNativeProps = GuiLabelProperties & { [number]: Compose.Child }
export type GuiLabelProps = GuiLabelNativeProps & { ref: ((GuiLabel) -> ())? }

export type ImageLabelProperties = GuiLabelProperties & {
	Image: Value<string>?,
	ImageColor3: Value<Color3>?,
	ImageContent: Value<Content>?,
	ImageRectOffset: Value<Vector2>?,
	ImageRectSize: Value<Vector2>?,
	ImageTransparency: Value<number>?,
	ResampleMode: Value<Enum.ResamplerMode>?,
	ScaleType: Value<Enum.ScaleType>?,
	SliceCenter: Value<Rect>?,
	SliceScale: Value<number>?,
	TileSize: Value<UDim2>?,
}
export type ImageLabelNativeProps = ImageLabelProperties & { [number]: Compose.Child }
export type ImageLabelProps = ImageLabelNativeProps & { ref: ((ImageLabel) -> ())? }

export type InputActionProperties = InstanceProperties & {
	Enabled: Value<boolean>?,
	Pressed: (() -> ())?,
	Released: (() -> ())?,
	StateChanged: ((unknown) -> ())?,
	Type: Value<Enum.InputActionType>?,
}
export type InputActionNativeProps = InputActionProperties & { [number]: Compose.Child }
export type InputActionProps = InputActionNativeProps & { ref: ((InputAction) -> ())? }

export type InputBindingProperties = InstanceProperties & {
	Backward: Value<Enum.KeyCode>?,
	ClampMagnitudeToOne: Value<boolean>?,
	DisplayImage: Value<Content>?,
	DisplayName: Value<string>?,
	Down: Value<Enum.KeyCode>?,
	Forward: Value<Enum.KeyCode>?,
	KeyCode: Value<Enum.KeyCode>?,
	Left: Value<Enum.KeyCode>?,
	PointerIndex: Value<number>?,
	PressedThreshold: Value<number>?,
	PrimaryModifier: Value<Enum.KeyCode>?,
	ReleasedThreshold: Value<number>?,
	ResponseCurve: Value<number>?,
	Right: Value<Enum.KeyCode>?,
	Scale: Value<number>?,
	SecondaryModifier: Value<Enum.KeyCode>?,
	Type: Value<Enum.InputBindingType>?,
	UIButton: (Value<GuiButton> | StaticValue)?,
	UIModifier: (Value<GuiButton> | StaticValue)?,
	Up: Value<Enum.KeyCode>?,
	Vector2Scale: Value<Vector2>?,
	Vector3Scale: Value<Vector3>?,
}
export type InputBindingNativeProps = InputBindingProperties & { [number]: Compose.Child }
export type InputBindingProps = InputBindingNativeProps & { ref: ((InputBinding) -> ())? }

export type InputContextProperties = InstanceProperties & {
	Enabled: Value<boolean>?,
	Priority: Value<number>?,
	Sink: Value<boolean>?,
}
export type InputContextNativeProps = InputContextProperties & { [number]: Compose.Child }
export type InputContextProps = InputContextNativeProps & { ref: ((InputContext) -> ())? }

export type Path2DProperties = GuiBaseProperties & {
	Closed: Value<boolean>?,
	Color3: Value<Color3>?,
	ControlPointChanged: (() -> ())?,
	Thickness: Value<number>?,
	Visible: Value<boolean>?,
	ZIndex: Value<number>?,
}
export type Path2DNativeProps = Path2DProperties & { [number]: Compose.Child }
export type Path2DProps = Path2DNativeProps & { ref: ((Path2D) -> ())? }

export type ScreenGuiProperties = LayerCollectorProperties & {
	ClipToDeviceSafeArea: Value<boolean>?,
	DisplayOrder: Value<number>?,
	IgnoreGuiInset: Value<boolean>?,
	SafeAreaCompatibility: Value<Enum.SafeAreaCompatibility>?,
	ScreenInsets: Value<Enum.ScreenInsets>?,
}
export type ScreenGuiNativeProps = ScreenGuiProperties & { [number]: Compose.Child }
export type ScreenGuiProps = ScreenGuiNativeProps & { ref: ((ScreenGui) -> ())? }

export type ScrollingFrameProperties = GuiObjectProperties & {
	AutomaticCanvasSize: Value<Enum.AutomaticSize>?,
	BottomImage: Value<string>?,
	BottomImageContent: Value<Content>?,
	CanvasPosition: Value<Vector2>?,
	CanvasSize: Value<UDim2>?,
	ElasticBehavior: Value<Enum.ElasticBehavior>?,
	HorizontalScrollBarInset: Value<Enum.ScrollBarInset>?,
	MidImage: Value<string>?,
	MidImageContent: Value<Content>?,
	ScrollBarImageColor3: Value<Color3>?,
	ScrollBarImageTransparency: Value<number>?,
	ScrollBarThickness: Value<number>?,
	ScrollingDirection: Value<Enum.ScrollingDirection>?,
	ScrollingEnabled: Value<boolean>?,
	TopImage: Value<string>?,
	TopImageContent: Value<Content>?,
	VerticalScrollBarInset: Value<Enum.ScrollBarInset>?,
	VerticalScrollBarPosition: Value<Enum.VerticalScrollBarPosition>?,
}
export type ScrollingFrameNativeProps = ScrollingFrameProperties & { [number]: Compose.Child }
export type ScrollingFrameProps = ScrollingFrameNativeProps & { ref: ((ScrollingFrame) -> ())? }

export type StyleBaseProperties = InstanceProperties & {
	StyleRulesChanged: (() -> ())?,
}
export type StyleBaseNativeProps = StyleBaseProperties & { [number]: Compose.Child }
export type StyleBaseProps = StyleBaseNativeProps & { ref: ((StyleBase) -> ())? }

export type StyleRuleProperties = StyleBaseProperties & {
	Priority: Value<number>?,
	Selector: Value<string>?,
}
export type StyleRuleNativeProps = StyleRuleProperties & { [number]: Compose.Child }
export type StyleRuleProps = StyleRuleNativeProps & { ref: ((StyleRule) -> ())? }

export type StyleSheetProperties = StyleBaseProperties & {}
export type StyleSheetNativeProps = StyleSheetProperties & { [number]: Compose.Child }
export type StyleSheetProps = StyleSheetNativeProps & { ref: ((StyleSheet) -> ())? }

export type SurfaceGuiBaseProperties = LayerCollectorProperties & {
	Active: Value<boolean>?,
	Adornee: (Value<Instance> | StaticValue)?,
	Face: Value<Enum.NormalId>?,
}
export type SurfaceGuiBaseNativeProps = SurfaceGuiBaseProperties & { [number]: Compose.Child }
export type SurfaceGuiBaseProps = SurfaceGuiBaseNativeProps & { ref: ((SurfaceGuiBase) -> ())? }

export type SurfaceGuiProperties = SurfaceGuiBaseProperties & {
	AlwaysOnTop: Value<boolean>?,
	Brightness: Value<number>?,
	CanvasSize: Value<Vector2>?,
	ClipsDescendants: Value<boolean>?,
	LightInfluence: Value<number>?,
	MaxDistance: Value<number>?,
	PixelsPerStud: Value<number>?,
	SizingMode: Value<Enum.SurfaceGuiSizingMode>?,
	ToolPunchThroughDistance: Value<number>?,
	ZOffset: Value<number>?,
}
export type SurfaceGuiNativeProps = SurfaceGuiProperties & { [number]: Compose.Child }
export type SurfaceGuiProps = SurfaceGuiNativeProps & { ref: ((SurfaceGui) -> ())? }

export type TextBoxProperties = GuiObjectProperties & {
	ClearTextOnFocus: Value<boolean>?,
	CursorPosition: Value<number>?,
	FocusLost: ((boolean, InputObject) -> ())?,
	Focused: (() -> ())?,
	Font: Value<Enum.Font>?,
	FontFace: Value<Font>?,
	LineHeight: Value<number>?,
	MaxVisibleGraphemes: Value<number>?,
	MultiLine: Value<boolean>?,
	OpenTypeFeatures: Value<string>?,
	PlaceholderColor3: Value<Color3>?,
	PlaceholderText: Value<string>?,
	ReturnPressedFromOnScreenKeyboard: (() -> ())?,
	RichText: Value<boolean>?,
	SelectionStart: Value<number>?,
	ShowNativeInput: Value<boolean>?,
	Text: Value<string>?,
	TextColor3: Value<Color3>?,
	TextDirection: Value<Enum.TextDirection>?,
	TextEditable: Value<boolean>?,
	TextScaled: Value<boolean>?,
	TextSize: Value<number>?,
	TextStrokeColor3: Value<Color3>?,
	TextStrokeTransparency: Value<number>?,
	TextTransparency: Value<number>?,
	TextTruncate: Value<Enum.TextTruncate>?,
	TextWrapped: Value<boolean>?,
	TextXAlignment: Value<Enum.TextXAlignment>?,
	TextYAlignment: Value<Enum.TextYAlignment>?,
}
export type TextBoxNativeProps = TextBoxProperties & { [number]: Compose.Child }
export type TextBoxProps = TextBoxNativeProps & { ref: ((TextBox) -> ())? }

export type TextButtonProperties = GuiButtonProperties & {
	Font: Value<Enum.Font>?,
	FontFace: Value<Font>?,
	LineHeight: Value<number>?,
	MaxVisibleGraphemes: Value<number>?,
	OpenTypeFeatures: Value<string>?,
	RichText: Value<boolean>?,
	Text: Value<string>?,
	TextColor3: Value<Color3>?,
	TextDirection: Value<Enum.TextDirection>?,
	TextScaled: Value<boolean>?,
	TextSize: Value<number>?,
	TextStrokeColor3: Value<Color3>?,
	TextStrokeTransparency: Value<number>?,
	TextTransparency: Value<number>?,
	TextTruncate: Value<Enum.TextTruncate>?,
	TextWrapped: Value<boolean>?,
	TextXAlignment: Value<Enum.TextXAlignment>?,
	TextYAlignment: Value<Enum.TextYAlignment>?,
}
export type TextButtonNativeProps = TextButtonProperties & { [number]: Compose.Child }
export type TextButtonProps = TextButtonNativeProps & { ref: ((TextButton) -> ())? }

export type TextLabelProperties = GuiLabelProperties & {
	Font: Value<Enum.Font>?,
	FontFace: Value<Font>?,
	LineHeight: Value<number>?,
	MaxVisibleGraphemes: Value<number>?,
	OpenTypeFeatures: Value<string>?,
	RichText: Value<boolean>?,
	Text: Value<string>?,
	TextColor3: Value<Color3>?,
	TextDirection: Value<Enum.TextDirection>?,
	TextScaled: Value<boolean>?,
	TextSize: Value<number>?,
	TextStrokeColor3: Value<Color3>?,
	TextStrokeTransparency: Value<number>?,
	TextTransparency: Value<number>?,
	TextTruncate: Value<Enum.TextTruncate>?,
	TextWrapped: Value<boolean>?,
	TextXAlignment: Value<Enum.TextXAlignment>?,
	TextYAlignment: Value<Enum.TextYAlignment>?,
}
export type TextLabelNativeProps = TextLabelProperties & { [number]: Compose.Child }
export type TextLabelProps = TextLabelNativeProps & { ref: ((TextLabel) -> ())? }

export type UIBaseProperties = InstanceProperties & {}
export type UIBaseNativeProps = UIBaseProperties & { [number]: Compose.Child }
export type UIBaseProps = UIBaseNativeProps & { ref: ((UIBase) -> ())? }

export type UIComponentProperties = UIBaseProperties & {}
export type UIComponentNativeProps = UIComponentProperties & { [number]: Compose.Child }
export type UIComponentProps = UIComponentNativeProps & { ref: ((UIComponent) -> ())? }

export type UIConstraintProperties = UIComponentProperties & {}
export type UIConstraintNativeProps = UIConstraintProperties & { [number]: Compose.Child }
export type UIConstraintProps = UIConstraintNativeProps & { ref: ((UIConstraint) -> ())? }

export type UIAspectRatioConstraintProperties = UIConstraintProperties & {
	AspectRatio: Value<number>?,
	AspectType: Value<Enum.AspectType>?,
	DominantAxis: Value<Enum.DominantAxis>?,
}
export type UIAspectRatioConstraintNativeProps = UIAspectRatioConstraintProperties & { [number]: Compose.Child }
export type UIAspectRatioConstraintProps =
	UIAspectRatioConstraintNativeProps
	& { ref: ((UIAspectRatioConstraint) -> ())? }

export type UICornerProperties = UIComponentProperties & {
	BottomLeftRadius: Value<UDim>?,
	BottomRightRadius: Value<UDim>?,
	CornerRadius: Value<UDim>?,
	TopLeftRadius: Value<UDim>?,
	TopRightRadius: Value<UDim>?,
}
export type UICornerNativeProps = UICornerProperties & { [number]: Compose.Child }
export type UICornerProps = UICornerNativeProps & { ref: ((UICorner) -> ())? }

export type UIDragDetectorProperties = UIComponentProperties & {
	ActivatedCursorIcon: Value<string>?,
	ActivatedCursorIconContent: Value<Content>?,
	BoundingBehavior: Value<Enum.UIDragDetectorBoundingBehavior>?,
	BoundingUI: (Value<GuiBase2d> | StaticValue)?,
	CursorIcon: Value<string>?,
	CursorIconContent: Value<Content>?,
	DragAxis: Value<Vector2>?,
	DragContinue: ((Vector2) -> ())?,
	DragEnd: ((Vector2) -> ())?,
	DragRelativity: Value<Enum.UIDragDetectorDragRelativity>?,
	DragRotation: Value<number>?,
	DragSpace: Value<Enum.UIDragDetectorDragSpace>?,
	DragStart: ((Vector2) -> ())?,
	DragStyle: Value<Enum.UIDragDetectorDragStyle>?,
	DragUDim2: Value<UDim2>?,
	Enabled: Value<boolean>?,
	MaxDragAngle: Value<number>?,
	MaxDragTranslation: Value<UDim2>?,
	MinDragAngle: Value<number>?,
	MinDragTranslation: Value<UDim2>?,
	ReferenceUIInstance: (Value<GuiObject> | StaticValue)?,
	ResponseStyle: Value<Enum.UIDragDetectorResponseStyle>?,
	SelectionModeDragSpeed: Value<UDim2>?,
	SelectionModeRotateSpeed: Value<number>?,
	UIDragSpeedAxisMapping: Value<Enum.UIDragSpeedAxisMapping>?,
}
export type UIDragDetectorNativeProps = UIDragDetectorProperties & { [number]: Compose.Child }
export type UIDragDetectorProps = UIDragDetectorNativeProps & { ref: ((UIDragDetector) -> ())? }

export type UIFlexItemProperties = UIComponentProperties & {
	FlexMode: Value<Enum.UIFlexMode>?,
	GrowRatio: Value<number>?,
	ItemLineAlignment: Value<Enum.ItemLineAlignment>?,
	ShrinkRatio: Value<number>?,
}
export type UIFlexItemNativeProps = UIFlexItemProperties & { [number]: Compose.Child }
export type UIFlexItemProps = UIFlexItemNativeProps & { ref: ((UIFlexItem) -> ())? }

export type UIGradientProperties = UIComponentProperties & {
	Color: Value<ColorSequence>?,
	Enabled: Value<boolean>?,
	Offset: Value<Vector2>?,
	Rotation: Value<number>?,
	Scale: Value<number>?,
	TileMode: Value<Enum.GradientTileMode>?,
	Transparency: Value<NumberSequence>?,
	Type: Value<Enum.GradientType>?,
}
export type UIGradientNativeProps = UIGradientProperties & { [number]: Compose.Child }
export type UIGradientProps = UIGradientNativeProps & { ref: ((UIGradient) -> ())? }

export type UILayoutProperties = UIComponentProperties & {}
export type UILayoutNativeProps = UILayoutProperties & { [number]: Compose.Child }
export type UILayoutProps = UILayoutNativeProps & { ref: ((UILayout) -> ())? }

export type UIGridStyleLayoutProperties = UILayoutProperties & {
	FillDirection: Value<Enum.FillDirection>?,
	HorizontalAlignment: Value<Enum.HorizontalAlignment>?,
	SortOrder: Value<Enum.SortOrder>?,
	VerticalAlignment: Value<Enum.VerticalAlignment>?,
}
export type UIGridStyleLayoutNativeProps = UIGridStyleLayoutProperties & { [number]: Compose.Child }
export type UIGridStyleLayoutProps = UIGridStyleLayoutNativeProps & { ref: ((UIGridStyleLayout) -> ())? }

export type UIListLayoutProperties = UIGridStyleLayoutProperties & {
	HorizontalFlex: Value<Enum.UIFlexAlignment>?,
	ItemLineAlignment: Value<Enum.ItemLineAlignment>?,
	Padding: Value<UDim>?,
	VerticalFlex: Value<Enum.UIFlexAlignment>?,
	Wraps: Value<boolean>?,
}
export type UIListLayoutNativeProps = UIListLayoutProperties & { [number]: Compose.Child }
export type UIListLayoutProps = UIListLayoutNativeProps & { ref: ((UIListLayout) -> ())? }

export type UIPaddingProperties = UIComponentProperties & {
	PaddingBottom: Value<UDim>?,
	PaddingLeft: Value<UDim>?,
	PaddingRight: Value<UDim>?,
	PaddingTop: Value<UDim>?,
}
export type UIPaddingNativeProps = UIPaddingProperties & { [number]: Compose.Child }
export type UIPaddingProps = UIPaddingNativeProps & { ref: ((UIPadding) -> ())? }

export type UIPageLayoutProperties = UIGridStyleLayoutProperties & {
	Animated: Value<boolean>?,
	Circular: Value<boolean>?,
	EasingDirection: Value<Enum.EasingDirection>?,
	EasingStyle: Value<Enum.EasingStyle>?,
	GamepadInputEnabled: Value<boolean>?,
	Padding: Value<UDim>?,
	PageEnter: ((Instance) -> ())?,
	PageLeave: ((Instance) -> ())?,
	ScrollWheelInputEnabled: Value<boolean>?,
	Stopped: ((Instance) -> ())?,
	TouchInputEnabled: Value<boolean>?,
	TweenTime: Value<number>?,
}
export type UIPageLayoutNativeProps = UIPageLayoutProperties & { [number]: Compose.Child }
export type UIPageLayoutProps = UIPageLayoutNativeProps & { ref: ((UIPageLayout) -> ())? }

export type UIScaleProperties = UIComponentProperties & {
	Scale: Value<number>?,
}
export type UIScaleNativeProps = UIScaleProperties & { [number]: Compose.Child }
export type UIScaleProps = UIScaleNativeProps & { ref: ((UIScale) -> ())? }

export type UIShadowProperties = UIComponentProperties & {
	BlurRadius: Value<UDim>?,
	Color: Value<Color3>?,
	Enabled: Value<boolean>?,
	Offset: Value<UDim2>?,
	Spread: Value<UDim2>?,
	Transparency: Value<number>?,
	ZIndex: Value<number>?,
}
export type UIShadowNativeProps = UIShadowProperties & { [number]: Compose.Child }
export type UIShadowProps = UIShadowNativeProps & { ref: ((UIShadow) -> ())? }

export type UISizeConstraintProperties = UIConstraintProperties & {
	MaxSize: Value<Vector2>?,
	MinSize: Value<Vector2>?,
}
export type UISizeConstraintNativeProps = UISizeConstraintProperties & { [number]: Compose.Child }
export type UISizeConstraintProps = UISizeConstraintNativeProps & { ref: ((UISizeConstraint) -> ())? }

export type UIStrokeProperties = UIComponentProperties & {
	ApplyStrokeMode: Value<Enum.ApplyStrokeMode>?,
	BorderOffset: Value<UDim>?,
	BorderStrokePosition: Value<Enum.BorderStrokePosition>?,
	Color: Value<Color3>?,
	Enabled: Value<boolean>?,
	LineJoinMode: Value<Enum.LineJoinMode>?,
	StrokeSizingMode: Value<Enum.StrokeSizingMode>?,
	Thickness: Value<number>?,
	Transparency: Value<number>?,
	ZIndex: Value<number>?,
}
export type UIStrokeNativeProps = UIStrokeProperties & { [number]: Compose.Child }
export type UIStrokeProps = UIStrokeNativeProps & { ref: ((UIStroke) -> ())? }

export type ViewportFrameProperties = GuiObjectProperties & {
	Ambient: Value<Color3>?,
	CurrentCamera: (Value<Camera> | StaticValue)?,
	ImageColor3: Value<Color3>?,
	ImageTransparency: Value<number>?,
	LightColor: Value<Color3>?,
	LightDirection: Value<Vector3>?,
}
export type ViewportFrameNativeProps = ViewportFrameProperties & { [number]: Compose.Child }
export type ViewportFrameProps = ViewportFrameNativeProps & { ref: ((ViewportFrame) -> ())? }

export type ModelProperties = PVInstanceProperties & {
	ModelStreamingMode: Value<Enum.ModelStreamingMode>?,
	PrimaryPart: (Value<BasePart?> | StaticValue)?,
	WorldPivot: Value<CFrame>?,
}
export type ModelNativeProps = ModelProperties & { [number]: Compose.Child }
export type ModelProps = ModelNativeProps & { ref: ((Model) -> ())? }

export type WorldRootProperties = ModelProperties & {}
export type WorldRootNativeProps = WorldRootProperties & { [number]: Compose.Child }
export type WorldRootProps = WorldRootNativeProps & { ref: ((WorldRoot) -> ())? }

export type WorldModelProperties = WorldRootProperties & {
	UseWorkspaceCollisionGroups: Value<boolean>?,
}
export type WorldModelNativeProps = WorldModelProperties & { [number]: Compose.Child }
export type WorldModelProps = WorldModelNativeProps & { ref: ((WorldModel) -> ())? }

export type RobloxTypes = {
	UDim: typeof(UDim),
	UDim2: typeof(UDim2),
	Vector2: typeof(Vector2),
	Vector3: typeof(Vector3),
	Color3: typeof(Color3),
	CFrame: typeof(CFrame),
	Enum: typeof(Enum),
	Font: typeof(Font),
	Rect: typeof(Rect),
	ColorSequence: typeof(ColorSequence),
	ColorSequenceKeypoint: typeof(ColorSequenceKeypoint),
	NumberSequence: typeof(NumberSequence),
	NumberSequenceKeypoint: typeof(NumberSequenceKeypoint),
	NumberRange: typeof(NumberRange),
	Path2DControlPoint: typeof(Path2DControlPoint),
	FloatCurveKey: typeof(FloatCurveKey),
	TweenInfo: typeof(TweenInfo),
}

export type Observe =
	((GuiBase2d, "AbsolutePosition") -> Compose.Cell<Vector2>)
	& ((GuiBase2d, "AbsoluteSize") -> Compose.Cell<Vector2>)
	& ((GuiObject, "GuiState") -> Compose.Cell<Enum.GuiState>)
	& ((GuiObject, "Interactable") -> Compose.Cell<boolean>)
	& ((GuiObject, "Position") -> Compose.Cell<UDim2>)
	& ((GuiObject, "Visible") -> Compose.Cell<boolean>)
	& ((GuiService, "ReducedMotionEnabled") -> Compose.Cell<boolean>)
	& ((GuiService, "SelectedObject") -> Compose.Cell<GuiObject?>)
	& ((InputAction, "DisplayName") -> Compose.Cell<string>)
	& ((InputAction, "Enabled") -> Compose.Cell<boolean>)
	& ((InputAction, "PreferredBinding") -> Compose.Cell<InputBinding>)
	& ((InputBinding, "DisplayImage") -> Compose.Cell<Content>)
	& ((InputBinding, "DisplayName") -> Compose.Cell<string>)
	& ((InputBinding, "KeyCode") -> Compose.Cell<Enum.KeyCode>)
	& ((InputBinding, "PrimaryModifier") -> Compose.Cell<Enum.KeyCode>)
	& ((InputBinding, "SecondaryModifier") -> Compose.Cell<Enum.KeyCode>)
	& ((InputContext, "Enabled") -> Compose.Cell<boolean>)
	& ((Instance, "Parent") -> Compose.Cell<Instance?>)
	& ((LayerCollector, "Enabled") -> Compose.Cell<boolean>)
	& ((ScrollingFrame, "AbsoluteWindowSize") -> Compose.Cell<Vector2>)
	& ((ScrollingFrame, "CanvasPosition") -> Compose.Cell<Vector2>)
	& ((TextBox, "FontFace") -> Compose.Cell<Font>)
	& ((TextBox, "LineHeight") -> Compose.Cell<number>)
	& ((TextBox, "RichText") -> Compose.Cell<boolean>)
	& ((TextBox, "Text") -> Compose.Cell<string>)
	& ((TextBox, "TextBounds") -> Compose.Cell<Vector2>)
	& ((TextBox, "TextColor3") -> Compose.Cell<Color3>)
	& ((TextBox, "TextFits") -> Compose.Cell<boolean>)
	& ((TextBox, "TextScaled") -> Compose.Cell<boolean>)
	& ((TextBox, "TextSize") -> Compose.Cell<number>)
	& ((TextBox, "TextTruncate") -> Compose.Cell<Enum.TextTruncate>)
	& ((TextBox, "TextWrapped") -> Compose.Cell<boolean>)
	& ((TextBox, "TextXAlignment") -> Compose.Cell<Enum.TextXAlignment>)
	& ((TextBox, "TextYAlignment") -> Compose.Cell<Enum.TextYAlignment>)
	& ((TextButton, "FontFace") -> Compose.Cell<Font>)
	& ((TextButton, "LineHeight") -> Compose.Cell<number>)
	& ((TextButton, "RichText") -> Compose.Cell<boolean>)
	& ((TextButton, "Text") -> Compose.Cell<string>)
	& ((TextButton, "TextBounds") -> Compose.Cell<Vector2>)
	& ((TextButton, "TextColor3") -> Compose.Cell<Color3>)
	& ((TextButton, "TextFits") -> Compose.Cell<boolean>)
	& ((TextButton, "TextScaled") -> Compose.Cell<boolean>)
	& ((TextButton, "TextSize") -> Compose.Cell<number>)
	& ((TextButton, "TextTruncate") -> Compose.Cell<Enum.TextTruncate>)
	& ((TextButton, "TextWrapped") -> Compose.Cell<boolean>)
	& ((TextButton, "TextXAlignment") -> Compose.Cell<Enum.TextXAlignment>)
	& ((TextButton, "TextYAlignment") -> Compose.Cell<Enum.TextYAlignment>)
	& ((TextLabel, "FontFace") -> Compose.Cell<Font>)
	& ((TextLabel, "LineHeight") -> Compose.Cell<number>)
	& ((TextLabel, "RichText") -> Compose.Cell<boolean>)
	& ((TextLabel, "Text") -> Compose.Cell<string>)
	& ((TextLabel, "TextBounds") -> Compose.Cell<Vector2>)
	& ((TextLabel, "TextColor3") -> Compose.Cell<Color3>)
	& ((TextLabel, "TextFits") -> Compose.Cell<boolean>)
	& ((TextLabel, "TextScaled") -> Compose.Cell<boolean>)
	& ((TextLabel, "TextSize") -> Compose.Cell<number>)
	& ((TextLabel, "TextTruncate") -> Compose.Cell<Enum.TextTruncate>)
	& ((TextLabel, "TextWrapped") -> Compose.Cell<boolean>)
	& ((TextLabel, "TextXAlignment") -> Compose.Cell<Enum.TextXAlignment>)
	& ((TextLabel, "TextYAlignment") -> Compose.Cell<Enum.TextYAlignment>)
	& ((UIGridStyleLayout, "AbsoluteContentSize") -> Compose.Cell<Vector2>)
	& ((UIPageLayout, "CurrentPage") -> Compose.Cell<GuiObject>)
	& ((UserInputService, "GamepadEnabled") -> Compose.Cell<boolean>)
	& ((UserInputService, "KeyboardEnabled") -> Compose.Cell<boolean>)
	& ((UserInputService, "MouseEnabled") -> Compose.Cell<boolean>)
	& ((UserInputService, "PreferredInput") -> Compose.Cell<Enum.PreferredInput>)
	& ((UserInputService, "TouchEnabled") -> Compose.Cell<boolean>)

export type Host = {
	BillboardGui: (BillboardGuiNativeProps) -> BillboardGui,
	Camera: (CameraNativeProps) -> Camera,
	CanvasGroup: (CanvasGroupNativeProps) -> CanvasGroup,
	Folder: (FolderNativeProps) -> Folder,
	Frame: (FrameNativeProps) -> Frame,
	ImageButton: (ImageButtonNativeProps) -> ImageButton,
	ImageLabel: (ImageLabelNativeProps) -> ImageLabel,
	InputAction: (InputActionNativeProps) -> InputAction,
	InputBinding: (InputBindingNativeProps) -> InputBinding,
	InputContext: (InputContextNativeProps) -> InputContext,
	Path2D: (Path2DNativeProps) -> Path2D,
	ScreenGui: (ScreenGuiNativeProps) -> ScreenGui,
	ScrollingFrame: (ScrollingFrameNativeProps) -> ScrollingFrame,
	StyleRule: (StyleRuleNativeProps) -> StyleRule,
	StyleSheet: (StyleSheetNativeProps) -> StyleSheet,
	SurfaceGui: (SurfaceGuiNativeProps) -> SurfaceGui,
	TextBox: (TextBoxNativeProps) -> TextBox,
	TextButton: (TextButtonNativeProps) -> TextButton,
	TextLabel: (TextLabelNativeProps) -> TextLabel,
	UIAspectRatioConstraint: (UIAspectRatioConstraintNativeProps) -> UIAspectRatioConstraint,
	UICorner: (UICornerNativeProps) -> UICorner,
	UIDragDetector: (UIDragDetectorNativeProps) -> UIDragDetector,
	UIFlexItem: (UIFlexItemNativeProps) -> UIFlexItem,
	UIGradient: (UIGradientNativeProps) -> UIGradient,
	UIListLayout: (UIListLayoutNativeProps) -> UIListLayout,
	UIPadding: (UIPaddingNativeProps) -> UIPadding,
	UIPageLayout: (UIPageLayoutNativeProps) -> UIPageLayout,
	UIScale: (UIScaleNativeProps) -> UIScale,
	UIShadow: (UIShadowNativeProps) -> UIShadow,
	UISizeConstraint: (UISizeConstraintNativeProps) -> UISizeConstraint,
	UIStroke: (UIStrokeNativeProps) -> UIStroke,
	ViewportFrame: (ViewportFrameNativeProps) -> ViewportFrame,
	WorldModel: (WorldModelNativeProps) -> WorldModel,
}

return {}
