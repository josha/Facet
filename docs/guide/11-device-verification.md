# Device verification

A headless native engine double verifies bindings, event cleanup and control
policy. It does not run engine layout, hit testing, text shaping, IME or input
routing. Those claims require live Roblox Studio or physical-device evidence.

Build and run the actual gallery and virtual monitors. Exercise compact and wide
sizes, keyboard/gamepad selection, pointer/touch controls, preferred text size,
reduced motion, theme switching, modal Back and focus restoration. For monitors,
exercise spatial/flat switching, Discover sorting/scanning, Avatar scene controls
and streaming Chat while scrolling.

Record the build revision, scenario, observed interactions and engine errors.
Keep benchmark and live evidence separate. A pre-cutover screenshot or green
subset does not prove this architecture's behavior.
