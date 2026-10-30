--!strict

export type Viewport = { width: number, height: number }

export type ViewportOptions = {
	minimumSide: number?,
	fallback: Viewport?,
}

export type PreferredInputClass = "Touch" | "KeyboardAndMouse" | "Gamepad"

export type PreferredInputSpec = {
	class: PreferredInputClass,
	token: string,
}

return {}
