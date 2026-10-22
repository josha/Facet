# Acceptance requirements

These requirements apply to both arms. Test player outcomes, not a prescribed
implementation. Keep this list fixed during a comparison. The author receives
the complete product requirements in the brief, but not evaluator code or
another submission.

For every row, record the starting state, normal player action, observed result,
device, and supporting capture or state observation. A control's presence does
not prove its behavior. Test cancellation, rejection, and reopening as stated.

| Area | Required outcome and evidence |
| --- | --- |
| Save and launch | The complete place frozen at the deadline reopens, starts, and mounts the game without a blocking error. Persistent scripts, world objects, terrain, and service settings survive. No operator patches are needed. |
| Hub | The player can reach every task, understand the current wallet and loadout, and return from each task. The root has no misleading Back action. |
| Driving | Input changes the kart's movement and steering in a real circuit. Braking, drift or boost, camera behavior, and stuck recovery work. The road and required controls remain visible. |
| Queue | Solo and Duo choices show joined and required counts. Join, leave before start, and rejoin work. Leaving cancels a pending countdown when the required count is no longer met. Countdown leads to an actual race with opponents. |
| Race | Ordered movement through the course advances laps. Position and finish state reflect progress. Standing still or crossing the finish backward does not complete a race. |
| Scoreboard | Live racers, rank, lap, and finish state are shown in order. The local racer is identifiable. Open and close work on keyboard, touch, and controller; closed UI does not capture steering. |
| Results | Actual finish order and rewards appear. Rewards are granted once, remain in the hub, and a second race can start. |
| Shop | All items and each category can be browsed. Prices, ownership, and affordability agree. Successful buying updates wallet and inventory. Expensive purchase confirmation supports Cancel. Rejection and cancellation do not spend currency. |
| Garage | Details, selection, favorites, and trying a kart work. Case-insensitive name search combines with category and rarity filters. Name sorts ascending, speed descending, and rarity highest first, with name order breaking ties. Clear removes search while preserving the filters. Selection and favorites survive filtering and reopening. Exiting a preview drive returns to the hub without changing the chosen next-race kart. |
| Loadout | Equip, replace, and unequip owned parts, with one item per slot and visible empty slots. Incoming grants update an open inventory. The next race uses the selected kart, parts, and driver. Focus, selection, equipped, and unavailable states remain distinguishable. |
| Drivers | Groups and statistics can be compared. Buy and rent confirmations identify the driver and full price. Cancel spends nothing. A ten-minute rental permits equipment, shows remaining time, and expires without removing permanent ownership. Invalid or repeated requests cannot bypass ownership or charge twice. |
| Crates | Prices, card counts, and rarity odds are visible before commitment. Confirmation Cancel spends nothing. Opening consumes an available free crate before currency, grants each accepted card once, and reveals cards in accepted order individually or all at once. Collection counts, unknown cards, and progress agree with the grants. |
| Daily rewards | Seven days show claimed, ready, and locked states, a next-claim countdown, and a special final reward. The hub ready indicator agrees. Claim grants once; reopening and repeated requests cannot duplicate it. A new day enables the next reward. A missed day restarts the track with an explanation. |
| Codes | The discoverable valid sample grants once, with whitespace trimmed and case ignored. Empty, invalid, expired, reused, busy, and rate-limited requests give truthful feedback without extra grants. Rate limiting shows a retry countdown. Opening Codes from Shop and returning preserves the shop state. |
| Boosts | Acquiring or activating a boost changes the relevant game behavior for its stated duration. Eligibility and expiry remain consistent after reopening. |
| Quests | Actual player actions advance quest progress. Eligible rewards can be claimed once; incomplete quests cannot grant rewards. |
| Timed offer | Contents, cost, time remaining, eligibility, accepted purchase, and expiry agree. The offer cannot be bought after expiry or duplicated contrary to its stated rules. |
| Mechanic | Asking, accepting, declining, and leaving work. Walking away ends dialogue. Acceptance leads to a real job. Completing its stated action unlocks the promised reward once; declining or leaving does not grant it. |
| Settings | Music and effects volume, damage numbers, camera shake, and graphics settings affect the game. The controls reference is readable. Sliders work with touch and gamepad steps. Pending, saved, and failure states reflect server results. Reset confirms all defaults; Cancel and gamepad Back preserve values and restore focus. Accepted values survive returning. Incoming server changes appear while settings or a purchase confirmation is open. |
| Livery | Six labeled body and accent colors, three shade levels, and six decals visibly change the kart preview. The draft is marked unsaved. Save reports success only after acceptance and survives reopening. Revert and leaving a dirty draft ask before discarding. Cancel keeps the draft; Discard restores the saved design. Clean Close returns immediately. Gamepad Back follows the same rules and restores focus. |
| Voting | Choices and descriptions are readable. Votes and remaining time update. Changing a vote moves the player's choice without adding a duplicate vote. Other votes are represented. Deadline locks voting and the winner determines the next track. |
| Quick chat | Q, gamepad Y, and a visible selectable button open eight presets. Choosing sends once and closes; Open and Cancel send nothing. Feedback names the sent message. The five-second cooldown survives closing and reopening. Driving controls stay clear and focus returns to the opener. |
| Upgrades | Levels, next improvement, two-currency costs, and affordability agree. Confirm changes the chosen kart and charges once. Cancel changes nothing. Insufficient funds and maximum level reject correctly. Different karts retain independent upgrades, which affect play. |
| Party | Online/racing/offline states govern invitation eligibility. Search and Clear work. Invites move through pending to accepted or declined, prevent duplicates, and never invite offline friends. Accepted members persist through filtering and reopening. Demo participants are identified as such. |
| Tutorial | Tips show step and total and point to the actual garage, shop, and queue actions without blocking them. Next, Back, Skip, completion, and replay work. First-step Back is disabled; last-step Next completes. Close or gamepad B goes back one step or dismisses at the first step. Dismissal restores focus. Completion and skipping are remembered. Using the target returns to the same step. The pointer remains attached through rotation and scrolling. |
| Shared progression | Both currencies, level, XP, race count, income, and zone progress remain consistent across panels and live grants. Store prices remain fully readable when HUD balances are abbreviated. Accepted race rewards update progression once. Any knockout mode shows truthful OUT state and recent eliminations, clearing the feed for a new race. |
| Authority | Purchases, rewards, equipment, and progression are server-owned and validated. Repeated or invalid client requests cannot create currency, bypass ownership, or collect the same reward twice. Visible state reflects accepted server state. |
| Persistence | Server-accepted progression survives closing panels and the race-to-hub loop. A failed save reports failure instead of false success. Source review and live behavior support the claim. Cross-session persistence is checked if claimed; external storage setup is not part of the supplied environment. |
| Adaptation | All required tasks remain readable and operable on desktop, both phone orientations, tablet, and console. Test focus entry and return, scroll access, safe areas, large text, reduced motion, and a live viewport change. |
| Stability | An open sheet or other task surface settles at a fixed viewport. Idle geometry does not jitter. Repeated navigation preserves state without accumulating UI or retained resources. |
| Visual quality | Matched hub, shop, garage, livery, race, results, and tutorial states show a coherent finished game. Blind review assesses attention order, composition, readability, state clarity, and compact forms. |

Do not accelerate gameplay by editing the authored state and then count the
result as a successful player action. For time-dependent rejection paths,
controlled clock or storage fault injection may support a separate robustness
check if it changes only the test environment. Preserve the normal player-path
evidence and identify every injection.

Measure performance in the settled hub, an open collection, active racing, and
after returning through the same tasks. Keep the viewport, frame cap, graphics
settings, observation interval, and warm-up policy the same for both arms.
Record actual sample counts and environment failures. A failed return is not
a low-memory observation.
