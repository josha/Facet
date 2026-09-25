# Adapting to another platform context

Use engine facts. Do not branch on device names. The applicable inputs are the
available native bounds, the preferred input, the text size, the safe areas and
reduced motion. Keep the same model and composition owner while you adapt the
layout or the presentation.

A control-specific presentation choice belongs in that control. For example,
TabView can select a sidebar or a bottom bar, and a large option set can use a
searchable picker. When its content needs a different arrangement, a screen can
choose one. Use native layouts and Compose structural operations for this.

Do not add another reactor, focus graph, gesture transport or rendering backend
for a platform. Use native selection and input actions. A world-fixed
SurfaceGui does not give ray, hand, gaze or VR support.

Verify the task through each input class that you claim. Record what you
actually exercised. Record where engine behavior is still not verified. A native
engine fixture can check callbacks and ownership. A headless bounds value does
not prove visual fit or reachability with hardware input.
