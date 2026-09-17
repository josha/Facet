--!strict
-- Shared by semantic actions, pointer input, shortcuts and control repeat.
export type Metadata = {
	source: ("pointer" | "action" | "shortcut" | "repeat" | "programmatic")?,
	pointer: ("mouse" | "touch" | "gamepad" | "keyboard" | boolean)?,
	x: number?,
	y: number?,
	shift: boolean?,
	toggle: boolean?,
}
return nil
