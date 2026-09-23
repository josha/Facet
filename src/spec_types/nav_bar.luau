--!strict
-- `UI.NavBar`'s types, apart from its implementation: reading a type must not
-- load the control.
local blueprint = require("../blueprint")

export type Spec = {
	id: string?,
	onBack: (() -> ())?, -- nil: no Back button
	backLabel: string?,
	title: blueprint.Bound<string>?, -- the default center: one line, disclosed
	titleSize: string?,
	leading: blueprint.Blueprint?, -- follows Back
	center: blueprint.Blueprint?, -- replaces the default title and fills the rest
	trailing: blueprint.Blueprint?, -- ONE blueprint; moves to a second row when needed
	gap: (string | number)?,
	padding: any?,
}

return nil
