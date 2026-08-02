# Desktop keyboard navigation and activation

**Status:** Planned after the API consistency stage.

## Purpose

LuauUI already has a strong logical focus graph and directional navigation for
keyboard and gamepad. It does not yet provide the desktop convention an author will
expect: Tab and Shift+Tab move through a focus chain, Space activates the focused
control, and arrow keys adjust a focused value control.

This is a framework behavior. Screens must not bind these keys themselves.

## Interaction contract

### Focus traversal

- Tab moves forward and Shift+Tab moves backward through the active focus scope.
- The order comes from the existing mounted focus graph and declared navigation
  groups. Do not create a second focus system or derive order from Roblox Instances.
- Hidden, disabled, non-focusable, losing adaptive candidates, and disposed nodes are
  skipped. Structural changes preserve focus or choose the same nearest survivor the
  graph already uses.
- Modal and transient scopes remain trapped and restore focus when dismissed.
- The active scope declares whether traversal wraps. A default must be documented and
  consistent; controls cannot invent their own wrap behavior.
- Every move uses the existing scroll-to-visible service.

### Activation and adjustment

- Return/Enter remains Activate. Space also emits Activate for the focused control.
- One physical press produces one semantic action even when a native `GuiButton`
  also reports `Activated`.
- A focused value control receives the arrow directions it declares as Adjust. A
  horizontal Slider uses Left/Right for decrement/increment; directions it declines
  remain available to Navigate.
- Pointer, touch, gamepad, and existing directional keyboard behavior do not change.

### Input ownership

- Bind and sink desktop navigation keys only while an interactive LuauUI responder
  owns UI input and keyboard capability is live. Passive HUDs never steal Tab, Space,
  arrows, or gameplay actions.
- While a TextInput is editing, Space inserts text and arrow keys remain native text
  editing. Tab follows the documented commit/validation path and advances only after
  editing ends; it must never type a tab character or bypass validation.
- Input hot-plug, pointer-plus-keyboard use, nested modals, and responder teardown
  must add and remove bindings without a one-frame leak or stuck sink.
- Use Roblox's Input Action System at the adapter boundary. Do not add direct
  `UserInputService` listeners to controls or screen code.

## Public API rule

Prefer behavior that falls out automatically from existing focusability, control
roles, and contribution metadata. Add public options only for real author intent,
such as a traversal exclusion or explicit order that the current graph cannot
express. Follow the API constitution and reject invalid combinations early.

Keyboard-specific behavior must not become a device-name branch. It is selected from
live capability and responder state, so a tablet with a hardware keyboard works like
a desktop while touch remains available.

## Verification

Add pure tests for forward/reverse traversal, wrap, group crossing, dynamic removal,
disabled/hidden nodes, modal trap/restore, keep-visible, and value-control routing.
Add action-system tests for responder ownership, text editing, hot switching,
teardown, and exactly-once activation.

Use the real adapter and Studio `VirtualInput` to prove raw Tab, Shift+Tab, Space,
Return, and arrow events reach the intended semantic action and visible state. Test a
form, a scrollable list, a modal, Slider/Stepper, and TextInput on desktop and on a
phone/tablet profile with keyboard capability. Keep physical keyboard rows separate
when Studio cannot reproduce the device path.

Update the input guide, API reference, control conformance registry, hints where
useful, tutorial examples, and the SwiftUI parity audit.

## Gate

Register `desktop-keyboard-navigation`. It passes only when the behavior above is
automatic for public controls, no screen-local key bindings are needed, passive
gameplay is untouched, text entry is correct, activation is exactly once, focused
content remains visible, the full suite and affected gates are green, and Studio
evidence is paired with raw-input/action/focus/state traces.

