# Ticket: teach a new player the hub

Start from `hub-party-invite` in the same arm and seed. Keep all earlier behavior and the same visual identity. Add Tutorial to the hub so a first-time player can start help and can replay it later. Guide the player through three coach marks in order: Dock (point to the real Garage action), Shop (the real Shop action), and Race queue (the real Play action). Show `Step N of 3: NAME`, Next, Back, and Skip. Disable Back on step 1. Last Next completes help. Skip ends help at any step.

The pointed action must still work while its coach mark is visible. Do not put an input-blocking layer over it. Keep its visible relationship to the coach mark clear, with an arrow or pointer. Keep the text and actions inside the safe area. Find the current position of the real element; do not assume a fixed screen coordinate. Reposition on window resize and phone rotation, including when the dock scrolls. Opening the pointed panel must not lose the tutorial step. Closing that panel returns to that step.

Close or gamepad B goes back one step, or dismisses help at step 1. After dismissal restore selection to Tutorial. Mouse, touch, and gamepad must reach the target and the help actions. Use `Extended.client().request("tutorial")` on completion or Skip. State `tutorialDone` records dismissal for the session. Do not change server or shared files.

## Design direction

Use a sci-fi neon identity with dark panels, cyan and violet accents, and readable pale text. Keep the world visible around the HUD.
