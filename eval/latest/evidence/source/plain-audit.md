# Plain source audit

This is a read-only audit of the sealed complete place, SHA256
`3783a2f70b147d87bbe81e1dd070e0d04a65cb086d2bb0b150d7db7f574c6549`.
The public `Lute.model` export is
`plain/sources.json`. Its three indexed files
are ApexClient (`001.luau`), Data (`002.luau`), and ApexServer (`003.luau`).
No source finding is a live acceptance pass. All 155 acceptance cells remain
separate from the player diagnostic cases.

## Ownership and normal routes

The server owns the session profile, prices, grants, equipment, rentals, race
progress and rewards (`003:10–24`, `003:110–224`). The client sends named requests
and replaces its displayed state with server snapshots (`001:85–88`,
`001:419–440`). The UI explicitly declares session-only storage (`001:77`);
profiles are created at join and removed at leave (`003:102–108`). Cross-session
persistence is not claimed. There is no direct client award path in these files.
Invalid/repeated-request behavior still needs native evidence; source presence
does not prove the complete Authority row.

The bottom scroll row exposes Garage, Shop, Inventory, Drivers, Livery,
Upgrades, Crates, Daily, Quests, Party, Mechanic, Settings and Help
(`001:98–104`). Codes is a Shop child. Quests contains the boost and timed offer.
`ENTER THE GRID →` opens Solo/Duo queue choices. Queue counts explicitly include
local CPU drivers; the accepted queue lasts12seconds and the race has a further
4-second countdown (`003:75`, `003:193–200`). No state editing is needed to race.

The authored race follows a guided ellipse. W/Up and the visible held ACCEL
control accelerate; A/D move the lane; S brakes; Shift boosts; R recovers.
Server movement advances angle from actual input-derived speed, limits the
lane and applies a wide-line penalty. Two laps finish Zenith; Midnight uses
three (`003:239–264`). The native input plan uses the existing Play probe's
`drag` at a constant position on visible ACCEL, with bounded rendered-frame
segments. This is native pointer input on mouse/touch-configured viewports.
It does not prove a physical touch hold or a controller trigger.
Standing still can be checked normally. Backward finish traversal cannot be
tested by this game's brake-only reverse input.

The initial profile has2400credits,120prisms, Pulse GT, Rook and one free crate.
Ion Motor costs650; Fusion Core1800; Echo rental180 and lasts600seconds
(`002`, `003:13`, `003:130–139`). Tests compare exact wallet values, accepted
ownership/equipment and reopened state. A generic `Session saved` message is
insufficient to identify which request succeeded.

## Concrete limits and risks

| Finding | Source evidence | Claim boundary |
| --- | --- | --- |
| Volume controls are discrete buttons; no slider is authored. | `001:319–321` | The Settings requirement for touch/gamepad slider operation is not implemented as specified. Step changes can be tested separately. |
| Damage numbers has stored UI state but no effect path; the controls reference says the game has no damage mode. | `001:323–327`, `001:411–417`, `003:189` | Do not claim the damage-number setting changes gameplay. |
| Zone progress is absent from the profile and shared HUD. | `003:13`, `001:505–506` | Shared progression is incomplete even if wallet/race grants work. |
| Race quick-chat Close clears selection and only restores a destination or a Hub opener. Chat has no destination button and racing is not Hub. | `001:355–361`, `001:379–380` | Inspect native focus after chat before any QA selection repair. Do not claim opener restoration from a repaired path. |
| Steering/acceleration polling continues while a task surface is open; only text-box focus suppresses keyboard polling. | `001:486–498` | Native input ownership requires observation; a modal's visibility alone does not suspend driving. |
| Livery clears `dirty` when sending, before the accepted snapshot. Any State message can replace its draft while clean. | `001:251`, `001:419–426` | Accepted Save/reopen is testable; rejection, concurrent snapshots and stale acknowledgments remain unverified. |
| A single `state.save` and uncancelled timeout callbacks represent all requests. | `001:85–88`, `001:422` | Do not treat this text as a request-specific acknowledgment. |
| Tutorial targets are a stroke on the real button; the first-step Back stays selectable but becomes inactive. | `001:386–394`, `001:518–524` | Native activation, focus and viewport behavior need their own observations. |
| Core touch controls are not disabled by this UI. | No `TouchControlsEnabled` or PlayerModule control ownership path in `001`; first-use portrait capture shows the overlap. | Use native reachability before operating the bottom navigation; preserve any occlusion. |

The source supports cancellation paths, purchase ownership checks, rental expiry,
daily UTC-day rules, code normalization and rate limits, once-only race/quest/job
rewards, vote changes, and demo invite outcomes. These are implementation
observations. Ten-minute rental expiry, midnight/missed-day transitions, offer
expiry, failure injection, hostile requests, incoming grants, all item/filter
permutations, live viewport changes and physical controller input remain
unverified unless later evidence explicitly covers them.

## Native first-use calibration

`discovery-plain-1` has a standard build plus two observation passes only.
The native captures show the tutorial at1/3 on desktop and portrait. Native
dimensions are1919×1080 and389×843. The portrait thumbstick and jump control
overlap the bottom Garage/Inventory region. A source-informed locator must
still pass normal reveal/reachability. No game object visibility, selection,
profile or clock is changed by the evaluator.

The Plain player adapter uses diagnostic IDs and no complete-row claims.
Each case establishes and recovers its start through normal Close, Cancel,
Discard, Exit and Skip actions. Unique capture names preserve original failures.
Any later calibration must preserve the old adapter, report and captures and
change only a proven operator issue.
