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

---

## 7. Banked Rolls Unit Tests (`test/engine/banked_rolls_test.dart`)

Covers `bankedRolls: true` (see `ludo-rules.md` section 8). Dice are seeded: tests pick a PRNG state that yields an exact sequence (`findRngState`, `rollSequence`) or build a moving-phase state with an explicit bank.

- **Rolling phase:** a 6 is banked with an immediate extra roll and nothing moves; a 1-5 ends the sequence and snapshots the turn; a lone 1-5 ends at once; `6,6,x` is not a forfeit; `tripleSixForfeit: false` keeps banking; `extraTurnOnSix: false` makes a 6 end the sequence.
- **Triple-six wipe:** three 6s wipe the whole bank including earlier dice, pass the turn and leave the board untouched.
- **Order flexibility:** `6,6,4` spent in different orders and across tokens reaches the same board; any equal-value `dieIndex` works; only moves that leave the rest of the bank spendable are legal (a `3` cannot be spent before the `6` that exits the yard); no moves outside the moving phase.
- **All-or-nothing:** a bank that cannot be spent in full from the start is forfeited (tokens unchanged, bank cleared, turn passes); a dead end after a bonus roll reverts the capture that earned it; a move that ends the match is legal only as the last die.
- **Bonus sequences:** bonus dice are added to a non-empty bank (`6,6,x` -> `6,6,6,6,y`); older 6s do not count toward the bonus sequence; the counter is `0` at each bonus sequence start; a triple six in a bonus sequence wipes the bank, passes the turn and keeps the moves (capture included); several captures/home moves each grant their own sequence in one turn; `extraTurnOnCapture: false` grants none.
- **Bank lifecycle:** the bank, phase and snapshot are cleared when the turn passes; state equality covers bank, phase and snapshot; `nextDecision` rolls through a whole sequence.
- **Regression:** `bankedRolls` is `false` in the defaults and every preset; with it off a roll sets the single pending die, never touches the bank, and the triple-six forfeit is unchanged.
- **Playout:** 600 random banked playouts across Classic and Strategic setups (all layouts and end modes) check the bank invariants (no pending die, non-6 dice only after the sequence ends, no bank on game over), termination and exact replay from the move log.

---

## 8. Safe Squares and Optional Blockade Rules (`test/engine/blockade_test.dart`, `blockade_options_test.dart`)

Covers `ludo-rules.md` sections 4 and 9.

- **Safe squares (part of the blockade rule):** a pair on a star square or another seat's start square blocks nobody and captures nobody; a pair on its owner's own start square blocks (also when two tokens come out of the yard); an ordinary-square pair blocks.
- **Prerequisites:** all options default off; with `blockades` off none is in force; capture and unbreakable need movement; `normalized()` switches inert options off; equality and hashing include the options.
- **Friendly restriction:** passing your own or a teammate's blockade is refused, landing allowed, the pair's own tokens unaffected, opponent blockades still impassable.
- **Movement:** unit moves on even rolls only, half the roll each; single moves stay; exactly two tokens; jumps over opponent and restricted friendly blockades; cannot land on own / opponent blockades; **never captures and cannot land on a single piece** (shares a safe square with one); a pair on its start square can move, on a star square it cannot; can enter the home column but not inside it; inert without `blockades`; the move log round-trips unit moves; forged unit moves are rejected.
- **Capture:** pair beats pair; illegal without the option, against a start-square blockade, against teammates, and without movement; single tokens still cannot.
- **Unbreakable:** no single moves for a pair on a non-safe square; odd rolls leave it; other tokens free; splittable on a safe square (also right after reaching it) and as a stack of three; inert without movement.
- **Piece on blockade:** landing allowed only with the option and only on the destination; no capture; **the piece cannot move during the rest of its arrival turn (extra roll) and moves on its owner's very next turn**; a landing without a bonus roll leaves it free next turn; the blockade's owner captures it with a single token; a moving blockade leaves it behind; a start-square blockade can be squatted on; teammates excluded.
- **Playouts:** 25 random games for each of ten option combinations (all on, quick, movement only, capture, unbreakable, squatting, friendly, banked, teams, banked teams; 2/3/4 seats) always finish, keep wait counters in range and replay exactly from seed + log.
