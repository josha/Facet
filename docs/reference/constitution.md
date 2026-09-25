# Facet's architecture rules

1. Only Compose owns scene construction, reactive bindings and lifetime.
2. Roblox owns layout, text editing and measurement, scrolling, selection,
   native input transport, drag detection and styling.
3. Facet owns reusable control behavior, semantic styling and adaptive
   decisions.
4. A control returns a native Instance and uses the Compose runtime of the
   caller.
5. Native properties and Compose keys pass through. There is no parallel
   vocabulary.
6. Behavioral options are explicit. An unknown native property fails at the
   engine boundary. Silently dropping options is not validation.
7. The model owns durable state. Controls send commands through callbacks.
8. Modal eligibility, focus restoration, cancellation, accessibility and
   resource cleanup are behavioral requirements. They are not optional
   decoration.
9. Current examples and tools use one supported API. There are no
   compatibility facades.
10. Code is self-documenting. Keep executable directives and required legal
    notices. Put explanations in focused public documentation and named tests.

A native engine double proves the binding and ownership policy. Only a live
engine proves layout and input behavior. A passing subset is not full evidence.
