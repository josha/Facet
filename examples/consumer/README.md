# Standalone consumer

Build with `rojo build examples/consumer/default.project.json -o build/Facet-Consumer.rbxl`, then open the place in Studio and play.

The client makes an app with `Facet.app` and mounts the screen with `app.mount`. The app adds the ScreenGui, the native StyleSheet and the StyleLink. The screen uses Facet controls and layout constructors with Compose cells. **Bump** updates its counter; **Sound** edits a caller-owned value; **Close** removes the panel through Compose.show. Destroying the client calls `app.dispose`, which releases the mount and the runtime.

The same screen module runs in the native gallery tests. `Facet.app` adds no environment, renderer or scene wrapper.

Run `lune run tests/run_one native_gallery` for the gallery and consumer checks.
