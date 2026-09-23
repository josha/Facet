# Facet's architecture rules

1. Compose alone owns scene construction, reactive bindings and lifetime.
2. Roblox owns layout, text editing/measurement, scrolling, selection, native
   input transport, drag detection and styling.
3. Facet owns reusable control behavior, semantic styling and adaptive decisions.
4. A control returns a native Instance and uses the caller's Compose runtime.
5. Native properties and Compose keys pass through without a parallel vocabulary.
6. Behavioral options are explicit. Unknown native properties fail at the engine
   boundary; silently dropping options is not validation.
7. Durable state belongs to the model. Controls emit commands through callbacks.
8. Modal eligibility, focus restoration, cancellation, accessibility and resource
   cleanup are behavioral requirements, not optional decoration.
9. Current examples and tools use one supported API. No compatibility facades.
10. Code is self-documenting. Preserve executable directives and required legal
    notices; keep explanation in focused public documentation and named tests.

A native engine double establishes binding/ownership policy. Only a live engine
establishes layout and input behavior. A passing subset is not full evidence.
