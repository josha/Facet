# Kart input migration observations

The preserved Kart example remains package-free. Its drift, modal Back, and
settings-slider actions now use native InputContext, InputAction, and
InputBinding objects declared in `input.project.json`. No Compose runtime or
second UI tree was added. The existing UI, race behavior, and example remain.

APIs checked: Roblox InputContext.Enabled, Priority, and Sink; InputAction
Pressed and Released; InputBinding.KeyCode. Compose Host constructors already
own these instances in Facet applications. This existing native-only example
uses serialized engine instances instead of adding a package solely for input.

Live checks used `artifacts/facet-kart-input.rbxlx`, built from the changed
example, in Studio `f91fba0a-c2a9-46a6-9446-dd9bd683191d` on 2026-10-21.
This is a separate test place, not either sealed eval submission.

- The example started in Play without console errors.
- A Kit modal opened with its Back InputContext enabled. Studio MCP native
  Backspace closed the modal and disabled the context.
- Selecting the music slider enabled its InputContext. Scripted engine
  InputAction events changed its displayed value in five-point steps. The
  server response is asynchronous, so an immediate read can precede the
  final displayed value.
- Studio MCP accepted a DPadRight keyboard request but the value did not
  change. That request does not prove physical gamepad behavior. Physical
  controller verification remains pending.

These checks establish limited engine integration. They do not establish
complete keyboard, touch, gamepad, or race acceptance. The Card regression
has separate live Studio receipts in `library-card-lift`.
