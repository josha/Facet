# Ticket: reset hub settings

The racing team needs a safe way to restore settings. Start from the completed racing hub. Keep the same visual identity and all earlier behavior.

Add Reset to Defaults in Settings. Ask `Reset all settings to their defaults?` with Reset and Cancel. Cancel keeps all values and sends no save. Reset saves every value in `context.settings.defaults` through `context.settings.save`. Do not change the server or shared files.

Show Saving while a save is pending and Saved only after the server accepts it. Use this indicator for ordinary edits and resets. Show a short failure message if a save fails. Reopening Settings must show the accepted values. Reset and Cancel must work with touch and gamepad. B cancels the confirmation and returns selection to Reset to Defaults.

| Element | Words |
| --- | --- |
| Action | Reset to Defaults |
| Question | Reset all settings to their defaults? |
| Choices | Reset, Cancel |
| Save state | Saving, Saved |

The entire racing hub must still work.
