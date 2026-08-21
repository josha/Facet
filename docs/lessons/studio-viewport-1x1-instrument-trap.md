# A hidden Studio game viewport makes Camera.ViewportSize 1x1 and silently kills input injection and screen capture

Observed 2026-07-19 (Phase 1 gallery verification): a Play Solo session in a Studio whose game view was not visible (window unfocused/minimized/tab hidden) reports `Camera.ViewportSize == 1,1`; `user_keyboard_input` and `user_mouse_input` deliver nothing to `UserInputService` (raw probe empty), and `screen_capture` hangs >120s. Everything else runs normally — scripts, IAS actions, attributes — so failures look like framework bugs when they are instrument blindness (ENGINEERING.md "know what your instrument can and cannot see"). The same place had a real 1440x1080 viewport with working key injection and screenshots earlier the same day.

**Rule:** before trusting Studio-side interaction or visual checks, read `workspace.CurrentCamera.ViewportSize` first; if it is 1x1, the session cannot receive injected input or produce captures — record FAIL_ENVIRONMENT and either re-run when the viewport is visible or fall back to engine-Scriptable InputBinding:Fire() traces (which DO work viewport-less, and drive the real action pipeline).

**Recovery that works (2026-07-24).** Reproduced again with a new symptom worth recording: the EDIT datamodel still reported the last good size (1233x1067) while the CLIENT datamodel reported `1, 1`, and `System Events` listed **no windows** for the `RobloxStudio` process — the window was minimized or on another desktop workspace. These did NOT restore it:

- `osascript ... tell application "Roblox Studio" to activate`
- `osascript ... tell process "RobloxStudio" to set frontmost to true`
- stop Play -> start Play

This DID, immediately:

```
open -a "RobloxStudio"
```

`open -a` asks the window server to unminimize and bring the window forward, which `activate`/`set frontmost` do not do for a window the server is not currently listing. Try it FIRST before recording FAIL_ENVIRONMENT — a whole matrix run was blocked on this for want of one command.
