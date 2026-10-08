--!strict
local Shared = require("./types")

export type CommandTarget<K> = { key: K, node: GuiObject }
export type Command<K> = {
	id: string,
	keys: { string },
	enabled: Shared.ValueBoolean?,
	onInvoke: (K) -> (),
}
export type CommandSpec<K> = {
	targets: Shared.Value<{ CommandTarget<K> }>,
	commands: { Command<K> },
	enabled: Shared.ValueBoolean?,
}
export type CommandScope<K> = {
	current: Shared.Readable<K?>,
	focus: (K) -> boolean,
	clear: () -> (),
	actions: { [string]: InputAction },
}
export type Controls = {
	commandScope: <K>(GuiObject, CommandSpec<K>) -> CommandScope<K>,
}
return {}
