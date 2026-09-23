# Adapting to another platform context

Use engine facts rather than device-name branches. Available native bounds, preferred input, text size, safe areas and reduced motion are the relevant inputs. Keep the same model and composition owner while adapting layout or presentation.

A control-specific presentation choice belongs in that control: TabView can select a sidebar or bottom bar, and a large option set can use a searchable picker. A screen can choose a different arrangement when its content requires one, using native layouts and Compose structural operations.

Do not add another reactor, focus graph, gesture transport or rendering backend for a platform. Use native selection and input actions. Do not infer ray, hand, gaze or VR support from a world-fixed SurfaceGui.

Verify the task through every claimed input class. Record what was actually exercised and where engine behavior remains unverified. A native engine fixture can check callbacks and ownership, but a headless bounds value does not prove visual fit or hardware-input reachability.
