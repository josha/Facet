# Ticket: send a quick message while preparing to race

Start from `hub-track-vote` in the same arm and seed. Keep all earlier behavior and the same visual identity. Add a wheel of eight preset messages from the supplied catalog. Open it with Q on keyboard, Y on gamepad, or a visible Quick Chat touch button. Keep the visible button available for console selection too. Opening must not send a message.

Show all eight choices around the wheel. Every label must fit and every choice must have a usable touch target. Send one message when I activate a choice, close the wheel, and show the message as a bubble or toast. Cancel with Close or B without sending. Restore selection to Quick Chat. Another send is blocked for five seconds; show Cooldown with the remaining time and then Ready. Reopening must not clear the cooldown.

Use `Extended.messages` and `Extended.client()`. State has `chat`, `chatCount`, and `readyAt`. Call `request("chat", message)` once. The server validates the preset and cooldown. Use `now()` for the countdown. Do not change server or shared files.
