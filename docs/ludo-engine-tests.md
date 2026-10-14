# Ludo Engine Acceptance Tests (Milestone 1)

Test specification and acceptance criteria for the pure Dart engine in `test/engine/`. All tests must pass before proceeding to Milestone 2 (UI).

Related: [ludo-blueprint.md](ludo-blueprint.md), [ludo-rules.md](ludo-rules.md), [ludo-roadmap.md](ludo-roadmap.md)

---

## 1. Movement Unit Tests

- **Yard Exit:**
  - Token in yard (`-1`) cannot move on rolls 1-5 when `needSixToLeave: true`.
  - Token in yard moves to starting square (`0`) on roll of 6.
  - When `needSixToLeave: false`, token exits yard on any roll (1-6).
- **Home Column & Exact Finish:**
  - When `exactRollToFinish: true`, a token cannot move if the roll overshoots finish square `56`.
  - A token inside the home column (`51..55`) can legally advance using rolls smaller than or equal to the exact distance to `56`.
- **Coordinate Conversion:**
  - Conversion between relative coordinates (`0..50`) and absolute board squares (`0..51`) accurately accounts for seat offset (`(relativePos + seat * 13) % 52`) across all 4 seats, correctly wrapping around square 51.

---

## 2. Capture and Safety Unit Tests

- **Open Square Capture:**
  - Landing on an opponent token on any non-safe track square captures it, resetting the victim's position to `-1` (yard).
- **Safe Squares (8 Squares):**
  - Verify all 4 starting exit squares and 4 star squares are immune to captures.
  - Opposing tokens sharing a safe square must coexist without either being sent home.
- **Friendly Immunity:**
  - Landing on a square occupied by your own token or a teammate's token never triggers a capture.
- **Extra Turn Award:**
  - When `extraTurnOnCapture: true`, a capture awards an immediate extra turn.
  - When `extraTurnOnCapture: false`, capturing does not award an extra turn.

---

## 3. Dice and Turn Flow Unit Tests

- **Six Extra Turn:**
  - Rolling a 6 grants a bonus turn when `extraTurnOnSix: true`.
- **Triple Six Forfeit:**
  - Rolling 6 three times consecutively forfeits the turn immediately when `tripleSixForfeit: true`.
  - The third roll of 6 cannot be applied to move any token; turn advances immediately to the next seat.
  - Verify that the triple-six forfeit also applies when a finished player rolls on behalf of their teammate.
- **Turn Passing:**
  - When no legal moves exist for the rolled value, the turn passes automatically without hanging.
  - If a bonus turn was active and has no legal moves, the turn ends cleanly.
- **State Determinism & Reproducibility:**
  - Replaying the identical random seed and move log sequence produces the exact identical `GameState`.

---

## 4. Blockade Unit Tests

- **Impassability (`blockades: true`):**
  - Two or more friendly tokens stacked on a track square form a blockade.
  - Opponents cannot move past the blockade square even if their rolled distance exceeds it.
  - Opponents cannot land on the blockade square.
- **Teammate Passage:**
  - Teammates of the blockade owner may traverse past the blockade square.
- **Safe Square Interaction:**
  - Blockades formed on safe squares are fully respected.

---

## 5. Ending & Ranking Unit Tests

- **First to Win (`EndMode.firstToWin`):**
  - Match terminates immediately when the 4th token of the first player (or team) hits square 56.
- **Full Ranking (`EndMode.fullRanking`):**
  - `finishOrder` accurately records the sequence of completed seats for 2, 3, and 4 player matches.
  - Finished seats are skipped in subsequent turn cycles.
  - When only one unfinished player remains, they are automatically placed in last position.
- **Team Mode Ranking:**
  - A team only finishes when both partners have all 4 tokens home (8 total tokens).
  - Teams are ranked by team outcome, not individual player order.
- **Teammate Control:**
  - When `teammateControl: true`: a finished player continues rolling and moves only their partner's tokens.
  - When `teammateControl: false`: finished players are skipped entirely.
  - If a finished player rolls and the active teammate has no legal moves, the turn cleanly passes.

---

## 6. Property-Based Playout Test

```dart
test('10,000 random playouts property invariant test', () {
  // Test across Classic, Quick, and Strategic presets and all EndModes
  // 1. Never produces an illegal engine state or uncaught exception.
  // 2. Every simulated game terminates cleanly within reasonable turn limit.
  // 3. Invariant: Total token count per seat strictly equals 4 at every tick.
});
```
