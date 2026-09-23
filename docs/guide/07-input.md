# Input and focus

GuiButton activation, TextBox editing, native InputContext/InputAction bindings,
GuiService selection and UIDragDetector provide the mechanisms. Compose owns their
Instances and subscriptions. Facet supplies control eligibility and interaction
policy. Input contexts are siblings under a native host, never nested contexts.

Modal controls trap all native selection directions, choose an enabled initial
selection, own Back input and restore the previous surviving selection. The
GuiButton.Modal property affects mouse locking and is not a focus trap.

TextInput distinguishes user edits from model synchronization. The engine owns
IME, caret and selection; the control retains validation, numeric bounds and
change/commit/cancel behavior. External model writes do not emit edit callbacks.

Virtual controls retain logical focus with Compose keys, scroll via collection
controls and restore GuiService.SelectedObject when the requested row exists.
Keyboard/gamepad traversal must not depend on every item being mounted.

World-fixed UI is a flat two-dimensional SurfaceGui. Facet does not add VR, gaze,
hand input or declarative three-dimensional layout.
