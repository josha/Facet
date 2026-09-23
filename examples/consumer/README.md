# Standalone consumer

Build with `rojo build examples/consumer/default.project.json -o build/Facet-Consumer.rbxl`, then open the place in Studio and play.

The client creates a Compose Roblox runtime, installs a native StyleSheet with StyleLink, and mounts a ScreenGui. The screen uses Facet controls with Compose cells and native layout objects. **Bump** updates its counter; **Sound** edits a caller-owned value; **Close** removes the panel through Compose.show. Destroying the client releases the root and runtime.

The same screen module runs in the native gallery tests. No Facet application, environment, renderer, or scene wrapper exists.

Run `lune run tests/run_one native_gallery` for the gallery and consumer checks.
