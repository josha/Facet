# Ticket: bring friends into my party

Start from `hub-upgrades` in the same arm and seed. Keep all earlier behavior and the same visual identity. Add Party in the hub. Show friends with Online, In race, or Offline presence. Search friends by name without case sensitivity. Use Search friends, Clear, and `No friends match`. Clear restores the full list. Do not lose invite or party state while filtering.

Each friend has Invite. Offline friends cannot be invited. Show Pending while a reply is due, then Accepted or Declined. Do not allow duplicate invites while pending or after a reply. Add accepted friends to a party strip with the local player. Declined friends do not join. Keep all presence and outcome text readable on phones. Close or B returns to the hub and restores selection.

Use `Extended.client()`. State has `friends` with `name`, `presence`, and `invite`, and `party`, the member names. Call `request("invite", friendName)` once. The supplied simulation replies after two seconds: Mira accepts, Sol declines, and Tess is offline. Subscribe to changes; do not invent outcomes in the interface. Do not change server or shared files. Search, Clear, and invites must work through touch and console selection.
