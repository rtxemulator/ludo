# Ludo Rules Specification

Definitive rules specification and configuration model for the Ludo engine.

Related: [ludo-blueprint.md](ludo-blueprint.md), [ludo-engine-tests.md](ludo-engine-tests.md), [ludo-roadmap.md](ludo-roadmap.md)

---

## 1. Rules Configuration Model

The pure Dart engine exposes all house rules through an immutable `RulesConfig` class:

```dart
enum EndMode {
  firstToWin,   // Game terminates when the first player/team gets all tokens home
  fullRanking,  // Continues until only one player/team remains, establishing 1st..4th
}

class RulesConfig {
  final EndMode endMode;          // default: EndMode.fullRanking
  final bool teammateControl;     // default: true (finished player rolls for partner)
  final bool needSixToLeave;      // default: true (require a 6 to exit yard)
  final bool extraTurnOnSix;      // default: true (rolling 6 grants bonus turn)
  final bool tripleSixForfeit;    // default: true (3 consecutive 6s forfeits turn)
  final bool extraTurnOnCapture;  // default: true (capturing an enemy grants bonus turn)
  final bool extraTurnOnHome;     // default: true (reaching finish grants bonus turn)
  final bool exactRollToFinish;   // default: true (token must hit square 56 exactly)
  final bool blockades;           // default: false (2+ tokens stack into impassable block)
  final bool teamsEnabled;        // derived from SeatConfig
  final bool bankedRolls;         // default: false (stacking dice, see section 8)
  // Optional blockade rules (section 9); all default to false, all need `blockades`.
  final bool blockadeFormFromSafe;    // default: TRUE (only matters with blockades)
  final bool blockadeFriendlyRestriction;
  final bool blockadeMovement;
  final bool blockadeCapture;         // also needs blockadeMovement
  final bool blockadeUnbreakable;     // also needs blockadeMovement
  final bool pieceOnBlockade;

  const RulesConfig({
    this.endMode = EndMode.fullRanking,
    this.teammateControl = true,
    this.needSixToLeave = true,
    this.extraTurnOnSix = true,
    this.tripleSixForfeit = true,
    this.extraTurnOnCapture = true,
    this.extraTurnOnHome = true,
    this.exactRollToFinish = true,
    this.blockades = false,
    this.teamsEnabled = false,
    this.bankedRolls = false,
    this.blockadeSafeSquares = false,
    this.blockadeFormFromSafe = true,
    this.blockadeFriendlyRestriction = false,
    this.blockadeMovement = false,
    this.blockadeCapture = false,
    this.blockadeUnbreakable = false,
    this.pieceOnBlockade = false,
  });
}
```

---

## 2. Board & Coordinate Topology

- **Track Layout:** 52-square outer perimeter track, 4 tokens per player, 5-square protected home column per player, 1 finish square.
- **Safe Squares (8 total):**
  - The 4 starting exit squares (one per color).
  - The 4 star/globe squares on the perimeter.
  - Safe squares forbid captures; tokens belonging to different players share the square safely.
- **Relative Coordinate System:**
  - `-1`: Yard (unentered)
  - `0` to `50`: Main perimeter track (seat 0 perspective; mapped to absolute board coordinates via seat offset: `absolutePos = (relativePos + seatIndex * 13) % 52`)
  - `51` to `55`: Home column (protected, accessible only by owning player)
  - `56`: Finished (off-board / home pocket)

---

## 3. Turn Flow

1. **Roll:** Die is rolled using the seeded PRNG.
   - If `consecutiveSixes == 3` (and `tripleSixForfeit: true`): the turn is forfeited immediately, the 3rd roll is discarded/unplayed, and the turn advances to the next player.
   - *Edge case:* This forfeit rule also applies when a finished player rolls on behalf of a teammate.
2. **Legal Moves Check:** Calculate all valid moves for the rolled value. If no legal move exists, the turn automatically passes to the next seat.
3. **Move Selection:** If one or more legal moves exist, the seat controller (Human, AI, or Remote) must choose one. Players cannot choose to skip or pass if a legal move exists.
4. **Execution & Bonus Turns:**
   - The selected move is applied to update `GameState`.
   - A bonus roll/turn is awarded if:
     - The die rolled was a 6 (when `extraTurnOnSix: true`), OR
     - An opponent token was captured (when `extraTurnOnCapture: true`), OR
     - A token reached the finish square (when `extraTurnOnHome: true`).
   - If none of these conditions are met, the turn passes.

---

## 4. Capturing & Blockades

- **Capturing:**
  - Landing on an opponent's lone token on any non-safe square captures it, sending it back to the opponent's yard (`-1`).
  - You can never capture your own token or a teammate's token.
  - On safe squares, multiple tokens (even from opposing players) coexist without captures.
- **Blockades (`blockades: true`):**
  - When 2 or more friendly tokens occupy the same square, they form an impassable blockade.
  - An opponent token cannot pass over or land on a blockade.
  - Teammates are permitted to pass through friendly blockades, but cannot land on the same square unless it is a designated safe square.
  - Your own blockade can be passed and landed on (a third token may join it).
  - **Safe squares stay open (part of the blockade rule itself, not an option):** a pair on a safe square (a yard exit or a star) is **not** a blockade: it blocks nobody, nobody waits because of it, and tokens of different players share safe squares as always. Blockades are formed on ordinary squares, for instance by stepping out of a safe square together (`blockadeFormFromSafe`, section 9.1, on by default).
  - The optional blockade rules of section 9 refine all of this; with none of them on, exactly the rules above apply.

---

## 5. End Modes & Ranking

- **First to Win (`EndMode.firstToWin`):**
  - The match concludes the instant the first player (or team) gets all 4 tokens to square 56.
- **Full Ranking (`EndMode.fullRanking`):**
  - As players get all 4 tokens home, their seat index is appended to `finishOrder`.
  - Finished seats are skipped in subsequent turn cycles.
  - Play continues until only one unfinished player (or team) remains; that player is assigned last place automatically.
- **Team Mode (2v2):**
  - Partners sit opposite each other (Seats 0+2 vs Seats 1+3).
  - A team finishes only when **both** partners have moved all 8 tokens home.
  - Final rankings are assigned by team rather than individually.

---

## 6. Teammate Control (2v2 with `teammateControl: true`)

- When Player A finishes all 4 tokens but their partner Player B is still playing:
  - Player A continues taking their regular turns in rotation.
  - Player A rolls the die, and the engine calculates legal moves for **Player B's tokens**.
  - Player A's controller (Human or AI) chooses the move for Player B.
  - Bonus turns (from rolling 6, captures, or reaching home) and the triple-six forfeit rule still apply normally.
  - If Player B has no legal moves on Player A's roll, the turn passes.
- When `teammateControl: false`:
  - Finished players are skipped, and the remaining teammate plays alone.

---

## 7. Rule Presets

| Preset | Differences from Classic | Intended Playstyle |
|---|---|---|
| **Classic (Default)** | All defaults specified above. | Balanced, standard tournament Ludo rules. |
| **Quick** | `needSixToLeave: false`<br>`tripleSixForfeit: false`<br>`endMode: EndMode.firstToWin` | Fast-paced, casual mobile session (tokens leave on 1-6). |
| **Strategic** | `blockades: true`<br>`extraTurnOnCapture: false` | Deep tactical play with path blocking and controlled pacing. |

All presets keep `bankedRolls: false`; banked rolls are an opt-in variant (section 8), not part of any preset.

---

## 8. Banked ("Stacking") Rolls (`bankedRolls: true`)

Off by default; with `bankedRolls: false` everything above applies unchanged. When on, sections 3 (Turn Flow) and 6 (Teammate Control) are replaced by the rules below. Boards, captures, safe squares, blockades, end modes and teammate control otherwise work as before.

### 8.1 Rolling without moving ("Roll All First")

A turn starts by rolling dice into a **bank** without moving anything. A *rolling sequence* is a run of rolls:

- A **6** is added to the bank and grants an immediate extra roll (the sequence continues).
- A **1-5** is added to the bank and ends the sequence; the turn moves on to the moving phase.
- **Three consecutive 6s in one sequence** wipe the **entire bank** (earlier dice included) and forfeit the turn. The third 6 is discarded. Moves already made this turn are kept (this only matters in a bonus sequence, see 8.3).
- The consecutive-6s counter is per sequence: it is `0` at the start of the turn and of every bonus sequence, and a 1-5 resets it to `0`. Sixes already in the bank never count toward a new sequence.
- Rolling never checks for legal moves; a roll with no possible move is still banked.

### 8.2 Moving phase: spend the bank, all-or-nothing

- The player may spend the banked dice **in any order**, each on any eligible token of the controlled seat, with the usual movement rules (yard exit, exact finish, captures, blockades).
- **All-or-nothing:** the player must be able to spend 100% of the bank in some order. A move is legal only if, after it, the remaining known dice can still all be spent (search over die orders and tokens).
- When the moving phase begins the engine snapshots the board (tokens and `finishOrder`) and the bank. If the bank is non-empty and no legal move exists, the turn is **reverted** to the snapshot (captures and home moves undone), the bank is cleared and the turn passes. This also happens when a full spend is impossible from the very start. The PRNG is not rewound, so the dice already rolled are not rolled again.
- A move that ends the match (`firstToWin`, or the last place in `fullRanking`) is legal only as the very last die of the bank. Winning with dice left over would leave dice unspent and is treated like any other dead end.
- **No carry over:** the bank is cleared whenever the turn passes to the next seat, whether through spending the last die, a triple six or a dead end. Only the current seat ever holds banked dice.
- Teammate control: the seat that rolled keeps the bank; each die is spent on the tokens of whichever seat is currently controlled (the finished roller's partner), including after a finishing move hands control over mid-turn.

### 8.3 Captures and going home: bonus sequences

- A move that **captures** an opponent token, or **lands a token on the finish square**, grants a **bonus rolling sequence** (subject to `extraTurnOnCapture` / `extraTurnOnHome`; if the seat has no one left to move it, no bonus is granted).
- The bonus sequence is rolled **immediately, before the next spend**, with the consecutive-6s counter at `0`. Its dice are **added** to the remaining bank. Older 6s in the bank do not count toward the new sequence's counter.
- A triple six inside a bonus sequence wipes the **entire bank** and passes the turn, but **moves already made this turn are kept**, including the capture that earned the bonus.
- Every capture or home move grants its **own** bonus sequence, so several can happen in one turn.
- The bonus dice are random, so a dead end can still appear after a bonus roll (the known dice were spendable, the new ones make the bank unspendable). That reverts the turn's moves to the snapshot, **including** the capture that earned the bonus.

| Outcome | Bank | Moves made this turn | Turn |
|---|---|---|---|
| Triple six (first or bonus sequence) | wiped | **kept** | passes |
| Dead end (full spend impossible) | cleared | **reverted** to the snapshot | passes |
| Last die spent, no bonus | empty | kept | passes |

### 8.4 No fixed bank size

There is no cap on the bank. Example: bank `6,6,x` -> spend `x` to capture -> bonus roll `6,6,y` -> the bank is now `6,6,6,6,y`. (The two bonus 6s alone are not a triple six; a third bonus 6 would be.)

### 8.5 Interaction with the other switches

`extraTurnOnSix`, `tripleSixForfeit`, `extraTurnOnCapture` and `extraTurnOnHome` still gate their respective behaviour: without `extraTurnOnSix` a 6 is banked but ends the sequence like a 1-5; without `tripleSixForfeit` there is no wipe; without `extraTurnOnCapture` / `extraTurnOnHome` those moves grant no bonus sequence. `needSixToLeave` and `exactRollToFinish` shape which spends are possible, and hence dead ends.

### 8.6 Engine representation

- `GameState.bank` is the current seat's banked dice in the order rolled (`bankOf(seat)` returns it for the current seat and an empty list otherwise). `bankPhase` is `rolling` or `moving`. `turnSnapshot` holds the snapshot taken when the moving phase began. `dice` stays `null`.
- `Move.dieIndex` is the index into `bank` of the die the move spends. Equal dice are interchangeable, so `legalMoves` offers one move per token and distinct value (using the first matching index) and `apply` accepts any index with that value.
- The move log keeps `(seat, dice, tokenIndex)` where `dice` is the value spent. Rolling-only rolls, forfeits and reverts are reproduced from the seed.

---

## 9. Optional Blockade Rules (`blockades: true` only)

Six switches that only exist while `blockades` is on (the first one is **on by default**, the others off). **Prerequisites:** `blockadeCapture` and `blockadeUnbreakable` need `blockadeMovement`; the others need only `blockades`. A switch whose prerequisite is off is *inert* (the engine reads the `...Active` getters of `RulesConfig`) and the setup screen shows it disabled; `RulesConfig.normalized()` (applied by `MatchSetup`) switches such options off. The base blockade rules, including the open safe squares of section 4, always apply.

A **blockade** is two or more tokens of one seat on the same track square (subject to the safe-square rule of section 4). A **pair** is exactly two. Home-column squares never hold blockades.

### 9.1 Forming blockades from a safe square (`blockadeFormFromSafe`, default on)

Safe squares hold no blockades, so this is how pairs come to stand on ordinary squares without a lucky landing: when **two or more of your tokens stand on the same safe square** (a yard exit or a star) and you roll an **even** number, you may **step out together** instead of playing normally: both tokens advance half the roll (2 -> 1, 4 -> 2, 6 -> 3) and the pair stands on that ordinary square as a **blockade**. The normal single-token moves stay available, so it is always a choice.

- with three or more tokens on the square, the two lowest-numbered go;
- the destination must be an ordinary square (a pair that ends on a safe square would not be a blockade);
- without moving blockades (9.3) the pair has to **walk**: it cannot jump over blockades, and the friendly restriction (9.2) applies as for single tokens; with moving blockades it jumps like a moving blockade;
- like every unit move it **never captures a single piece**: it may land on a square holding one and simply shares the square; it may not land on an opponent blockade (unless 9.4 allows it);
- engine: a `Move` with `partnerIndex >= 0`, same as a unit move; in the UI a tap on a pair that has both options offers "this token" or "both tokens" markers.

### 9.2 Friendly blockade restriction (`blockadeFriendlyRestriction`)

You may not pass a blockade of your own or of a teammate (only moves that *end* before it are allowed). Landing rules are unchanged: you may land on your own blockade; a teammate may not land on yours unless the square is safe. A moving blockade (9.3) ignores this, as it ignores every blockade on its way. Opponent blockades stay impassable.

### 9.3 Blockade movement (`blockadeMovement`)

A **pair** may also move **as a unit**:

- only on an **even** roll `d`; each of the two tokens advances `d / 2` squares (2 -> 1, 4 -> 2, 6 -> 3), with the usual end-of-track rules (a pair may enter the home column; it stops being a blockade there; it cannot finish in one move);
- it **jumps over** every blockade on the way (opponent, friendly, restricted);
- it **may not land** on a blockade of its own, on a teammate's blockade (unless the square is safe), or on an opponent blockade (unless 9.4 allows it);
- it **never captures a single piece**: it may land on a square holding a lone opponent token and shares the square with it (no capture, no bonus turn; a single token of yours landing there later would capture it as usual). If the pair splits later, the two lone tokens keep sharing the square until someone lands there (a landing captures every opponent token on the square, as usual); only blockades can be captured, and only by 9.4;
- exactly two tokens: three or more on a square do not move as a unit; a waiting token (9.6) cannot be part of one; a pair on a safe square is no blockade and cannot move as one (but may step out, 9.1);
- the single-token moves stay legal (the pair may be split) unless 9.5 forbids it.

Engine representation: `Move.partnerIndex >= 0` (`Move.isUnit`) with `tokenIndex` the lower index; the log entry carries `MoveLogEntry.unit`. In banked-roll games a unit move spends one die like any other move.

### 9.4 Blockade capture (`blockadeCapture`, needs 9.3)

A moving blockade that lands on an opponent blockade on a **non-safe** square captures it: every token of that blockade goes back to its yard (a capture, so the bonus turn applies). Single tokens still cannot capture a blockade, and blockades never stand on safe squares. Teammate blockades are never captured.

### 9.5 Unbreakable blockade (`blockadeUnbreakable`, needs 9.3)

A pair on a **non-safe** square cannot be split: its tokens can only move together (so only on even rolls; an odd roll leaves the pair where it is). Safe squares hold no blockades, so a pair that stands on one is two ordinary tokens again. A stack of three or more may lose a token (a pair stays behind). A blockade can still be broken by capture.

### 9.6 Piece on blockade (`pieceOnBlockade`)

*Interpretation (the request was short; this is the reading implemented):* a **single piece** (an ordinary single-token move) may land on a square held by an **opponent's** blockade, which normally is impassable. It is the one way to "get onto" an enemy blockade:

- landing captures nothing, and the blockade stays intact (a pair that lands there is a blockade capture, 9.4, not this rule);
- the piece **cannot move for the rest of the turn it arrived in** (for example the extra roll a six or a capture earns); it is **free on its owner's very next turn** (`GameState.rest` is set to 1 on arrival and counts down at the end of the turn; a waiting piece cannot move alone or in a unit; a banked-roll dead end restores the counter with the rest of the board);
- it is **not protected**: a **single** token of the blockade's owner landing on the square captures it (the owner may land on their own blockade). Nobody else can land there;
- passing the blockade is still impossible; only landing on it is allowed;
- if the blockade **moves away** (9.3), the piece is **left behind** and is then just a lone piece on an ordinary square (capturable by any opponent single piece);
- teammate blockades cannot be squatted on.

### 9.7 Combinations worth knowing

Moving + unbreakable gives walls that only advance on even rolls. Moving + capture makes a wall a battering ram against other walls (never against single pieces). Friendly restriction + unbreakable can freeze your own tokens behind a wall that cannot move on odd rolls; the engine just passes the turn when nothing is legal. Form-from-safe + unbreakable: step out of the yard exit as a wall that then only advances as a wall.
