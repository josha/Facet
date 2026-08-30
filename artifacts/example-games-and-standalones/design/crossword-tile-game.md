# The crossword tile game — design

Replaces `examples/gallery/examples/06_tile_game.luau`, whose current loop is "put
every rack tile into any empty box": no words, no dictionary, no adjacency, and a win
condition that is simply an empty rack. The binding scope is
`docs/plans/example-games-and-standalones.md`, "Crossword tile game".

Almost none of the existing file survives. The declarative scaffolding — `UI.Grid` for
board and rack, signals and memos for state, the presenter for the screen — is the
reusable part. The domain logic is new.

---

## 1. What the player does

You have seven letter tiles and six turns. Build words on a small board, crossing the
starred centre square first, and reach sixty points before the turns run out.

That is the whole game, and the screen says it in one line above the board.

## 2. The rules, exactly

**Board.** Seven by seven. The centre square (4, 4) carries a star and a label the
first turn has to cover.

**Rack.** Seven tiles, refilled from a deterministic bag after each committed turn.

**A turn.** Place any number of rack tiles, then **Submit word**.

1. **The first turn must cover the centre square.**
2. **Every tile placed in one turn lies in a single row or a single column.** The very
   first tile of a turn does not fix an axis; the second one does.
3. **The tiles you place, together with the committed tiles between them, form one
   unbroken run.** A gap that is not filled by a committed tile is refused.
4. **After the first turn, at least one placed tile must touch a committed tile** —
   orthogonally, not diagonally.
5. **Every word the turn creates must be in the dictionary.** That is the main word
   (the full run along the turn's axis, including committed letters at either end) and
   every perpendicular word any placed tile now sits inside.
6. **The score is the sum of every letter in every word the turn created**, counting a
   letter once per word it appears in. Using five or more rack tiles in one turn adds
   ten.
7. **Undo turn** returns every uncommitted tile to the rack and unlocks the axis.
8. **The game ends** when the turn budget is spent or the goal is reached, whichever
   comes first, and says which.

**The bag.** A fixed multiset, drawn with a seeded pseudo-random generator, so a given
seed always deals the same game and a replay test can assert an exact final board.
Letter values follow the familiar English distribution (A E I O U N R S T L = 1, D G =
2, B C M P = 3, F H V W Y = 4, K = 5, J X = 8, Q Z = 10) because a player already knows
that Z is worth more than E and does not need to be taught it.

**The guaranteed opening.** After the initial deal, the game checks that some subset of
the rack forms a dictionary word of at least two letters that can be laid across the
centre. If not, it reshuffles from the same seeded stream and deals again, bounded at
sixty-four attempts, exactly as the match-3 example already guarantees a legal opening
move. The check is part of the deal, so the guarantee holds for every seed the tests
use and for the reset button.

## 3. Every refusal, and what it says

The plan requires that "invalid placement or word explains the exact problem and
preserves recoverable state". Nothing is silently ignored, and nothing is dropped: a
refused submit leaves every placed tile exactly where it is, so the player can move one
tile rather than start the turn over.

| Situation | What the game says |
|---|---|
| First turn misses the centre | "Your first word has to cover the starred centre square." |
| Tiles are not in one line | "The tiles you place in a turn go in a single row or a single column." |
| A gap in the run | "Leave no gaps — your tiles and the letters already on the board have to make one unbroken run." |
| Later turn touches nothing | "After the first turn, a word has to touch a letter already on the board." |
| The main word is unknown | "PLZTK isn't a word this game knows." |
| A crossing word is unknown | "That would make QXZ downward, and that isn't a word this game knows." |
| Submit with nothing placed | "Place at least one tile before you submit." |
| Placing on an occupied square | "That square already has a letter." |
| Picking up a committed tile | "Letters from an earlier turn stay put." |

Each of these is a distinct case in the spec, and each is played once in Studio.

## 4. What is on screen, and why

The plan requires that the player can see "legal next cells, selected tile,
uncommitted versus committed letters, current word, score, goal, and turns". Mapping
each to a visible thing:

| Fact | How it is shown |
|---|---|
| Goal and progress | A single line: "**38 of 60 points · 4 turns left**" |
| The task, before the first move | "Cover the starred square with a word to begin." |
| Legal next cells | Once the axis is locked, the cells that could still take a tile carry a distinct plate. Before the axis is locked, every empty cell adjacent to a committed tile (or the centre, on turn one) carries it. |
| The selected rack tile | The rack tile reads as selected, and the board's hint line says "Placing **R** — choose a square." |
| Committed versus uncommitted | Two different plates plus a mark: a committed letter is solid, an uncommitted one carries a visible outline. Not colour alone. |
| The current word | "Making **BRAIN** — 7 points" updates as tiles land, and shows the refusal instead when the run is not yet a word. |
| Turn budget | In the same line as the score. |

Empty cells always carry chrome, for the same reason the word game's do: a default
valued write claims nothing, so a cell that paints its surface's own colour is
invisible on the device while being perfectly present in the tree.

## 5. Input

Every action is reachable by pointer, touch, keyboard, and gamepad, with no per-device
branch in the example.

- **Select then place.** Activating a rack tile selects it; activating a board square
  places the selected tile. Activating the selected rack tile again puts it down.
- **Focus.** The board is one navigation group with seven columns, so directional
  navigation moves a square at a time; the rack is a second group; Submit and Undo sit
  in the actions row. Moving between the three is ordinary traversal.
- **Keyboard shortcut, not requirement.** With a board square focused, typing a letter
  that is in the rack places it. This is a convenience on top of the select-then-place
  path, never the only way in — the plan's "all inputs" requirement is met by the
  select-then-place path alone.

## 6. Where the code lives

| Module | Owns |
|---|---|
| `examples/gallery/examples/words/` | The shared, generated dictionary and its lookup. Used by the word game too. |
| `examples/gallery/examples/06_tile_game.luau` | The declarative screen, and — as its own `rules` table, the way `05_word_game.luau` already does — the pure crossword rules: the bag, the deal, placement validation, word extraction, scoring, and the end states. |

The rules table is pure: it takes a board and a placement and returns a verdict, with
no signal, no presenter, and no engine. That is what makes every rule in §2 and every
refusal in §3 a headless test, and it is what keeps the crossword out of Facet.

Nothing about crossword play belongs in `src/`. If the board or rack needs something
the framework cannot do — a focus behaviour, a grid affordance, a way to show a cell as
legal — that is a framework gap, it gets a row in the responsibility ledger, and it is
fixed in Facet behind a public API rather than worked around here.

## 7. The tests

Headless, red first, in `tests/examples_games.spec.luau` beside the existing example
cases (and a new dedicated spec if the block outgrows the file).

**Rules.** Axis locking including the single-tile case; gaps refused; gaps closed by a
committed tile accepted; the centre requirement on turn one and its absence afterwards;
connectivity accepted orthogonally and refused diagonally; the main word read through
committed letters at both ends; every crossing word extracted and validated; the score
counting a letter once per word; the five-tile bonus.

**Dictionary.** Accept and reject through the shared module, including a real word the
old hand-written list would have rejected.

**Loop.** Commit; the rack refills to seven from the bag; undo returns exactly the
uncommitted tiles and unlocks the axis; a refused submit changes no state; the turn
budget decrements only on a commit.

**Endings.** Reaching the goal wins and says so; spending the budget without reaching
it loses and says so; both offer restart; restart returns every observable to its
seeded start.

**Determinism.** The same seed deals the same rack and bag; replaying a fixed script of
moves reproduces the same final board, score, and dump.

**Robustness.** Rapid alternating input leaves no stale selection or held tile;
teardown returns the registry to baseline.

**Four inputs.** The existing `✓ ex06 touch/keyboard/gamepad` parity cases are kept and
extended to the new actions.

## 8. What this deliberately does not do

- No blank tiles, no premium squares, no two-player turn order. The plan asks for "one
  clear, finite word-building loop", and each of those adds a rule the player has to
  learn before the first move.
- No timer.
- Words longer than seven letters cannot be validated, because the shared dictionary
  carries lengths two to seven. On a seven-wide board with a seven-tile rack the only
  way to exceed that is a run that spans the whole board through committed letters; the
  game refuses it by name ("This game only knows words up to seven letters long")
  rather than by silently calling it unknown.
