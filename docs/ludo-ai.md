# Ludo AI Design (Milestone 4)

Design for the computer players that replace the `GreedyBot` stand-in for the Medium, Hard and Expert levels. Written in chat A (design + engine API check, no code). Chats B and C implement it; neither re-plans. Starting weights and budgets here are starting points: chat B tunes them with self-play.

Related: `ludo-blueprint.md` section 6 (original AI outline), `ludo-seats.md` (the seat seam), `ludo-rules.md` (rules the AI must cover), `ludo-roadmap.md` (milestone 4).

---

## 1. Goals and constraints

- Four levels behind the existing `AiLevel` enum: Easy (the current `GreedyBot`, untouched), Medium, Hard, Expert. Saves and setups already carry `aiLevel`; nothing changes there.
- Hard cap 300 ms per decision on a mid-range phone (blueprint). The search is time-budgeted, never fixed-depth-at-all-costs.
- Fair by construction: the AI reads only public state. It never calls `Dice.roll` and never reads `GameState.rngState`.
- Pure Dart in `lib/ai/` (imports only `package:ludo/engine/ludo_engine.dart` and `package:ludo/seats/seats.dart`, plus `dart:async`, `dart:isolate`, `dart:math`). No new packages, no Flutter. Guarded like `lib/seats/` by a purity test and a CI grep.
- Every rule flag works: banked rolls, team play with teammate control, blockades and all their options (unit moves, forming moves, waiting tokens). The AI always returns a member of the legal list.

## 2. Decisions

| # | Decision |
|---|---|
| D1 | The AI plays for a **unit** (the seat, or the team in 2v2). Teammate control needs no special case: the controller of `currentSeat` chooses, `controlledSeat` owns the moved token, and both count for the same unit. |
| D2 | **Expectimax with modelled opponents.** My decision nodes maximise; chance nodes average the six faces with probability 1/6 each. In 2-player games opponent nodes minimise (true expectiminimax). With 3 or 4 units, a true min node is ill-defined, so each opponent plays its **one-ply best reply under its own evaluation** (cost: one apply per opponent move, but only one child continues). Allies (a teammate who is not my own controller) are modelled the same way. |
| D3 | **Depth counts turn handovers**, not plies of moves: depth N = N turns by other seats after mine. Bonus rolls (6, capture, home) stay inside the turn as extra chance nodes, capped at `bonusDepth` levels (1 for Medium/Hard, 2 for Expert), then the position is evaluated. Medium = depth 1, Hard = depth 2, Expert = iterative deepening from depth 1 until the deadline (usually 3). |
| D4 | **No MCTS in Milestone 4.** On this phone the engine runs about 10k applies/s under JIT (see section 6); even at 5x for release AOT, 250 ms buys a few dozen playouts, which is noise next to a tuned evaluation. Revisit only if tournaments show Expert stuck below its target. |
| D5 | **Budgets:** Medium 40 ms, Hard 100 ms, Expert 250 ms wall clock (the rest of the 300 ms is isolate messaging and slack). `AiBudget` has `maxMillis` and `maxNodes`; the app uses time, tests and tournaments use nodes only so results are reproducible. Iterative deepening returns the best move of the last completed depth. |
| D6 | **Branching control:** collapse symmetric moves (tokens on the same square give the same result; keep the lowest `tokenIndex`), order moves by one-ply evaluation, and at inner nodes keep the top K (K = 3 Hard, 3 Expert) as a beam. The root always considers every distinct move. |
| D7 | **Banked rolls:** the AI still answers one `choose` at a time, but plans the whole bank: at each decision it enumerates spending orders (memoised on board key + remaining dice multiset, so equal outcomes via different orders are searched once), scores the end board, and returns the first step of the best plan. A capture or home move inside a plan adds a flat `bonusRollValue` instead of expanding the bonus dice. Opponent turns after the plan are searched only at Hard and above, with chance nodes over single dice (a 6 continues the sequence; branches below 0.5% probability are dropped and the rest renormalised). If the banked engine path is too slow, banked games get one depth less than the table below; correctness never changes. |
| D8 | **No randomness in the AI.** Ties go to the lowest `tokenIndex` after collapsing. Expert variety, if ever wanted, would use an AI-private seeded generator, never the game's dice. |
| D9 | **Fallback:** if the worker is late (hard watchdog 600 ms), crashes, or returns something not in the legal list, the controller plays `GreedyBot`. The game never freezes and the engine still validates every move through `Engine.apply`. |

Tier table:

| Level | Method | Depth | Budget | Inner beam |
|---|---|---|---|---|
| Easy | `GreedyBot` (unchanged) | 0 | none | - |
| Medium | expectimax + new evaluation | 1 | 40 ms | all |
| Hard | expectimax + new evaluation | 2 | 100 ms | 3 |
| Expert | iterative deepening expectimax | 1..N | 250 ms | 3 |

## 3. Evaluation

`V(state, unit) = S(unit) - mean(S(opponent units))`, so in 2-player play it is zero-sum. A finished match returns a placement value instead: win 1000, then 400, 150, 0 by rank (`state.ranking`, team-aware). Units are `state.unitOf(seat)`; a unit's score sums all its seats' tokens.

`S(unit)` per token, in "squares of progress" so it stays continuous with `GreedyBot`:

| Feature | Starting weight | Notes |
|---|---|---|
| Progress | `relative position + 1` (yard 0, finish 57) | |
| Safe | +4 | on a safe square or in the home column |
| Finished | +20 | tempo bonus on top of progress |
| Exposure | `- p_hit * (progress + 10)` | `p_hit` = share of the six faces that let some opponent token land on this square next turn |
| Threat | `+ 0.5 * p_hit_by_me * (their progress + 25)` | symmetric `p_hit` for my tokens against theirs |
| Blockades (only if `rules.blockades`) | +3 per own wall with opponents 1-6 behind it; -3 per opponent wall just ahead of my token | tuned, may be zero |
| Waiting (`rest > 0`) | -6 | squatting on a blockade |
| Bank (banked rolls) | `bonusRollValue` 8 per capture/home inside a plan | |

`p_hit` counts an opponent token only if its relative position plus the distance is at most 50 (a token cannot hit from the home column) and ignores yard tokens (start squares are safe). Weights live in one const `AiWeights` class so tuning edits one file.

Tuning (chat B): coordinate hill-climb or SPSA on `AiWeights` by self-play tournaments with node budgets, fixed seeds, seats rotated. Freeze the tuned values in the class with a comment on how they were found.

## 4. Fairness rules (enforced by tests)

1. `lib/ai/` never references `Dice.roll` or `.rngState` (grep test, like the purity tests).
2. Property test: for random states, `choose(state)` equals `choose(state.copyWith(rngState: other))`. A search that peeked at the PRNG would fail it.
3. Chance nodes use `Engine.applyRoll` (section 5, E1) with explicit faces, never `Engine.roll`.

## 5. Engine API check

Verified by reading `lib/engine/` as built on `main` (ecab830).

| Need | Status | Detail |
|---|---|---|
| Legal moves for a hypothetical die | OK | `legalMoves(state, dice)`; banked mode uses the bank when `dice` is omitted. |
| Successor state | OK | `apply` is pure, immutable, and never touches `rngState`. |
| Chance node (hypothetical roll) | **GAP E1** | `roll` always draws from `state.rngState`, and `_passTurn` (forfeit, no-legal-move pass, wait counters, teammate skipping, snapshot clear) is private, so the AI cannot enumerate faces without peeking or duplicating the turn logic. |
| Search speed | **GAP E2** | `apply` re-runs `legalMoves` to validate, which the search already has. Measured about 10k applies/s (classic, strategic, blockade options) and about 3k/s with banked rolls, JIT on this phone. |
| Evaluation inputs | OK | `Engine.blockades`, `absoluteSquare`, `isSafeSquare`, `partnerOf`, `unitOf`, `seatsOfUnit`, `ranking`, `finishOrder`, `rest`/`isWaiting`, the `...Active` rule getters, `turnSnapshot`. |
| Search key / transposition | AI-side | `GameState ==`/`hashCode` include `rngState`, `turnNumber`, `rest`, snapshot, so equal positions differ. `lib/ai` builds its own `PositionKey` (token positions + seat + dice/bank + waiting). No engine change. |
| Symmetric moves | AI-side | the engine returns one move per token (four identical yard moves); `lib/ai` collapses them. |
| Terminal value | OK | `isOver`, `ranking`, `winners`. |
| Isolate transfer | Check in chat C | `GameState`, `RulesConfig`, `TurnSnapshot`, `Move` are plain classes of ints, lists and enums, so they should be sendable; chat C adds a round-trip test before relying on it. |
| Seam | OK | `GameController` calls `_bot.choose(state, legal)` in `_driveAi` for every level; `AiLevel` is already in `SeatConfig` JSON. |

Engine additions for chat B (additive, each with unit tests, `docs/ludo-rules.md` untouched):

- **E1 `Engine.applyRoll(GameState, DiceRoll)`**: the body of `roll` (forfeit, pass, banked outcomes) with the face supplied; `roll(state)` becomes `applyRoll(state, Dice.roll(state.rngState))`. The AI passes `DiceRoll(face, state.rngState)` so the PRNG is never advanced. Tests: `roll` and `applyRoll` agree for random states across presets (including banked, forfeits, dead ends); `applyRoll` never changes `rngState` when handed the same one.
- **E2 `Engine.applyLegal(GameState, Move)`**: `apply` without re-validation, documented "move must come from `legalMoves(state)`". Tests: identical to `apply` for every legal move in the playout corpus. `apply` stays the validated path and the only one the controller uses.
- **E3 (only if measured necessary)**: a cheaper `_canSpendAll` for banked search. Decide after chat B's benchmark.

## 6. Performance notes

Scratch benchmark in chat A (not committed): random playouts, every legal move applied at each decision, `dart run` (JIT) in Termux: classic 11.0k applies/s, strategic 10.5k, all blockade options 9.4k, banked 3.2k. JIT is pessimistic; release AOT should be several times faster, and the final check is the Milestone 7 audit on device. Rough tree sizes with 3 moves per decision: depth 1 is about 100 nodes, depth 2 about 2k, depth 3 about 40k before beam and symmetry collapse. Hence the time budget, the beam, and iterative deepening. Chat B starts with a proper benchmark in `tool/` and records the real numbers here.

## 7. Packaging

```
lib/ai/
  weights.dart      # AiWeights (all tunables)
  features.dart     # p_hit, exposure, threat, blockade terms
  eval.dart         # V(state, unit), terminal values
  search.dart       # expectimax, iterative deepening, beam, banked planner
  position_key.dart # search/memo key
  ai_player.dart    # AiPlayer(level).choose(state, legal) -> Move  (sync, deterministic with node budgets)
  worker.dart       # dart:isolate worker + request/response (chat C)
tool/ai_tournament.dart   # self-play harness, run by hand, not in dart test
test/ai/                  # unit, fairness, purity, small tournament smoke
```

`AiPlayer.choose(state, legal)` keeps the `GreedyBot` signature so tests and tournaments run it synchronously; the worker wraps the same function.

## 8. Isolate and seat controller (chat C)

- One long-lived worker isolate per app session: spawned on the first game with an AI seat, shut down when the game screen closes.
- Request `{id, state, legal moves, level, budgetMillis}`, response `{id, chosen index}`; the id lets the controller drop answers from an abandoned turn (new game, rewind, menu).
- `_driveAi` becomes a small state machine: on an AI turn it sends the request immediately and plays the answer after `max(think delay, compute time)`, so computing hides inside the existing 650 ms pause. Rolling stays automatic (the AI has no roll decision).
- Reduced motion keeps its short delay; compute time is additive only when it exceeds it.
- Watchdog and fallback as in D9. CI is the only way to build the app (no Flutter in Termux), so chat C pushes the branch and watches CI.

## 9. Validation

- Unit tests: features on hand-built states, symmetric-move collapse, beam, banked planner memo, chance-node weights, `applyRoll`/`applyLegal` equivalence, fairness tests of section 4, rule coverage (random configs: AI-vs-AI playouts finish, never throw `IllegalMoveException`, always pick a legal move).
- Tournaments (`tool/`, node budgets, seats rotated, at least 1000 games per pairing, results recorded in this doc): 2-player head-to-head and 4-player one-versus-three. Targets: Expert beats random playout at least 90% (blueprint); the tier order Medium > Easy > random and Expert > Hard > Medium must hold with the lower 95% bound above 50% in 2-player play. Exact margins are fixed after the first tournament, once the ceiling is known; Ludo's dice variance caps how large they can be.
- Timing: p95 decision time under the budget on the phone in Termux (JIT, pessimistic); final device check in Milestone 7.

## 10. Chat plan

- **A (this chat):** this doc, engine API check. Branch `milestone-4-ai`, no code.
- **B:** E1/E2 with tests, then `lib/ai/` (features, eval, search, tiers, banked planner), `tool/ai_tournament.dart`, weight tuning, results in this doc. Replaces `GreedyBot` only inside `AiPlayer`; the app still uses `GreedyBot` until C. Stops with green `dart format/analyze/test` and a tournament table.
- **C:** worker isolate, `GameController` hookup (`AiLevel` to `AiPlayer`), watchdog/fallback, settings/setup copy if levels are described anywhere, CI green, device checklist (play each level, check frame timing during AI turns). PR to main after the device review.

## 11. Results (chat B)

All numbers: `tool/ai_tournament.dart`, node budgets only (Medium 400, Hard 2500, Expert 8000 nodes), seats rotated and swapped on every seed, `firstToWin`, win = first place. 95% intervals are Wilson. Seeds are the harness defaults (tuning used a disjoint range).

| Layout | Rules | A | B | Games | A wins | 95% CI |
|---|---|---|---|---|---|---|
| duel | classic | Easy | random | 1000 | 91.3% | 89.4-92.9 |
| duel | classic | Medium | random | 1000 | 94.8% | 93.2-96.0 |
| duel | classic | Expert | random | 1000 | 96.0% | 94.6-97.0 |
| duel | classic | Medium | Easy | 1000 | 56.1% | 53.0-59.1 |
| duel | classic | Hard | Medium | 1000 | 55.9% | 52.8-58.9 |
| duel | classic | Expert | Hard | 1000 (4 x 250) | 49.1% | 46.0-52.2 |
| duel | banked | Medium | Easy | 400 | 54.8% | 49.9-59.6 |
| duel | banked | Hard | Medium | 300 | 54.7% | 49.0-60.2 |
| one vs three | classic | Hard | 3 x Easy | 400 | 31.0% | 26.7-35.7 |
| one vs three | classic | Medium | 3 x Easy | 400 | 27.8% | 23.6-32.3 |

(One vs three: 25% is parity.)

Against the section 9 targets:

- Expert beats random 96% (target 90%): met.
- Medium > Easy > random and Hard > Medium (classic duel, lower bound above 50%): met.
- **Expert > Hard: not met.** 491 wins in 1000 games; Expert at 8000 nodes (depth up to 4, bonus depth 2) is statistically the same player as Hard at 2500 nodes (depth 2). Banked and 4-player rows have too few games to separate tiers; Medium vs 3 x Easy has a CI that includes parity.

The ceiling is low: each tier step is worth about 6 points of win rate, which is what dice variance leaves for evaluation quality.

### Tuning

`tool/ai_tune.dart`: coordinate hill-climb, candidate against the champion (Medium, 300 nodes, 60% classic and 40% strategic duels, 400 games per trial on fresh seeds, accept at 55%). Two sweeps, 44 trials, every result between 45.3% and 52.8%, nothing accepted. The starting weights are therefore frozen as `AiWeights.tuned`: safe 4, finished 20, exposureScale 1, exposureBase 10, threatScale 0.5, threatBase 25, blockHold 3, blockStuck 3, waiting 6, bonusRollValue 8, out 10. Raising exposure or threat weights hurt (45-47%); the rest is flat. The weights are not the bottleneck.

### Benchmark (Termux, JIT, pessimistic)

Sampled positions from random classic games, measured with `--bench`: `Engine.apply` about 5k/s and `applyLegal` about 7k/s when the legal-move generation is included in the loop (chat A's 11k/s figure counted applies only); search 21-39k nodes/s. Node-capped at 50k: decision average and p95 were Medium 16 / 56 ms, Hard 25 / 77 ms, Expert 61 / 191 ms, mean completed depth 0.95 / 1.9 / 3.8 (forced moves count as depth 0). Easy vs random ran at about 55 games/s per core, so a full playout costs roughly 18 ms under JIT. Still to verify on device in Milestone 7.

### Deviations from sections 2-3

- The search passes `DiceRoll(face, 0)` to `Engine.applyRoll` instead of `DiceRoll(face, state.rngState)`: the fairness grep forbids any mention of `rngState` in `lib/ai`. Nothing downstream reads that field.
- New weight `out` (tempo for each token that left the yard). Without it Medium lost to Easy (38%, 120 games); with it 56.1%.
- Expert: max depth 4, beam 3, bonus depth 2, 250 ms. Medium: depth 1, 40 ms. Hard: depth 2, beam 3, 100 ms.
- The transposition key is a 64-bit hash (tokens sorted per seat, seat to move, die or bank, six counter, waiting counters, search counters).
- `tool/tournament.dart` is the shared harness; layouts are duel, one-vs-three and 2v2 teams.

### MCTS (D4 revisited)

D4's trigger fired: Expert is not above Hard. I still recommend against MCTS here. A random or greedy playout costs about 18 ms under JIT (maybe 5 ms in release), so 250 ms buys 15-50 playouts, while one game outcome has a standard deviation near 0.5; that cannot rank three candidate moves whose true values differ by a few points. Deeper search also did not help (above), which points at evaluation noise and Ludo's luck rather than at the search method. If Expert needs to be a real step, the cheaper experiments are, in order: (1) a learned evaluation, logistic regression of final placement on the same features over self-play positions, instead of hand-tuned weights; (2) removing or weakening the beam at Expert to see whether pruning is what flattens it; (3) only then rollouts as a tiebreak between near-equal moves.


## 12. Worker and controller hookup (chat C)

What chat C built, against sections 2 and 8. No weight tuning, no MCTS; Expert equalling Hard (section 11) is a known result.

### Code

- `lib/ai/worker.dart`: `AiRequest {id, state, legal, level, budgetMillis}`, `AiResponse {id, index}` (`index == null` means failed), `AiBackend` (`send`, `close`, `alive`), `AiWorker` (the real isolate; requests sent while it spawns are queued; an uncaught error or exit turns every request in flight into a failure and `alive` false), `InlineAiBackend` (same computation on the calling isolate with node budgets, for tests) and `aiWorkerMain` (the isolate entry). `answerRequest` never throws.
- `lib/ai/turn_driver.dart`: `AiTurnDriver`, the pure Dart state machine, driven by frame-clock milliseconds (no timers, so tests do not wait). `begin` sends at once, `poll(now, state)` returns the move once `max(think time, compute time)` has passed, `cancel` and `dispose` drop it.
- `app/lib/game/game_controller.dart`: `_driveAi` rolls by itself as before (700 ms, 250 ms with reduced motion). For a move it calls `begin` the first frame the choice is due and `poll` every frame. The think pause is 650 ms (250 ms reduced), unchanged. `GameController(aiDriver:)` is injectable; the controller tests use `AiTurnDriver.inline()` (node budgets, deterministic).

### Behaviour

- **Easy** stays `GreedyBot` and never touches the worker. A single legal move is played without a request for every level.
- **Medium, Hard, Expert** go through the worker with the time budgets of D5 (40, 100, 250 ms; node budgets stay for tests and tournaments).
- **Lifetime:** the worker is spawned when a game starts with a Medium, Hard or Expert seat (an Easy-only table needs none) and shut down by `GameController.dispose`, which the game screen calls when it closes. A second game on the same screen reuses it.
- **Stale answers:** every request has an id and remembers the exact `GameState` it was made for. `newGame`, a banked dead-end revert, a turn that is no longer an AI turn, and `dispose` cancel it; a different `state` at `poll` drops it too. An answer with another id is ignored.
- **Watchdog (D9):** no answer 600 ms after the request, a crashed worker, a failed response, or an index outside the legal list: `GreedyBot` plays (after the usual think time) and `fallbackCount` / `lastFallback` (`timeout`, `crashed`, `invalid`) record why. After a timeout the worker is closed and a fresh one starts on the next request, because a worker still busy with a stuck search would delay every later answer. The engine still validates every move through `Engine.apply`.

### Isolate transfer

`GameState` (with its unmodifiable lists), `RulesConfig`, `TurnSnapshot` and `Move` cross a `SendPort` unchanged. `test/ai/worker_test.dart` sends them through a real isolate (classic, banked rolls with a snapshot, teams, every blockade option) and compares with `==`, then runs the real `AiWorker` for the answer, the crash, the silent and the bad-index cases.

### Tests

- `test/ai/turn_driver_test.dart`: think delay vs compute time, stale ids, other state, timeout, crash, invalid index (both sides), worker replacement, Easy and forced moves, dispose.
- `test/ai/worker_test.dart`: port round trips and the real worker (see above).
- `app/test/ai_worker_flow_test.dart` (CI only): the same cases through `GameController` with a scripted backend and the fake frame clock, including whole games with a worker that never answers (classic and banked).

### Copy

The setup screen has a level picker (UI addendum): each AI seat tile shows a compact Easy / Medium / Hard / Expert selector (default Medium, key `ai-level-<seat>`, one labelled semantics node "<colour> AI level") and one line of copy per level (`SetupScreen.levelText`: Easy "Plays fast and forgives mistakes", Expert "Thinks longest, plays strongest"). A single note under the seats says Hard and Expert are close in strength (section 11: Expert is not stronger than Hard). The level lives in `SeatConfig.aiLevel`, so it reaches `GameController`, rematch (`newGame` reuses the setup) and the JSON a saved game stores. The picker has no animation, so reduced motion needs no special case. No "thinking" indicator: the table shows no seat names, so there is nowhere cheap to put one.

### Device checklist (before the PR to main)

0. Setup: give each of the four seats a different level (Easy, Medium, Hard, Expert), start, confirm each plays at its pace; Menu > Players & rules shows the same levels; Rematch keeps them.
1. Play a 2-player game against each of Easy, Medium, Hard, Expert; the AI should feel like the old pause, never longer than about a second.
2. Frame timing during AI turns (frame-timing overlay, profile APK): no spikes while Hard or Expert think; the search runs off the UI isolate.
3. 4-player games with AI seats: banked rolls on, and each blockade option on; the AI answers every choice (no stalls, no illegal move errors).
4. Rewind: a banked dead end ("Turn undone") while an AI seat is next; New game from the menu during an AI turn; quit to setup during an AI turn and start another game.
5. Optional: put the phone under load (a build running in Termux) and check that a slow AI turn falls back to the greedy move instead of freezing.
