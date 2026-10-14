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
