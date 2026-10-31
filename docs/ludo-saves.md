# Ludo Saves & Replays (Milestone 5)

Design of the save games and of the replay data. Pure Dart core in `lib/storage/` (chat A); sqflite persistence, autosave and resume in the app (chat B); replay viewer and polish (chat C).

Related: [[ludo-roadmap]] (milestone 5), [[ludo-blueprint]] (sections 4 and 7, partly superseded here: sqflite instead of drift), [[ludo-seats]] (`MatchSetup`), [[ludo-rules]] (banked rolls, section 8).

---

## 1. Decisions (approved)

- Database: `sqflite` (chat B) and `shared_preferences` for settings. This chat adds no dependency.
- A save appears only after the first decision. Nothing is written for a game that was only rolled or abandoned at the start.
- One save per game, autosaved. A finished game keeps its save until the user deletes it. A rematch (or any new game, including a rules change that restarts the game) is a **new save** with a new id and seed.
- Auto-name from date and time (`2026-10-26 14:05`, caller passes local time); the user can rename. Names are trimmed, newlines become spaces, at most 40 characters; a blank name is not accepted by a rename.
- Quitting must never allow a re-roll (section 5).
- Broken or incompatible saves are not opened. They are listed greyed and can be deleted. The replay viewer may still play a damaged log up to its last valid entry.

## 2. Principle

The whole game is a pure function of `setup + seed + decisions`. The save stores exactly those three. Every board, bank, snapshot, wait counter and ranking is rebuilt by `Engine.applyEntry`. Rolls, forfeits and no-move passes are never stored, they are re-derived from `GameState.rngState` (`Dice.roll`). One mechanism serves autosave, resume and replay.

## 3. Save model (`GameSave`, `lib/storage/game_save.dart`)

| Field | Meaning |
|---|---|
| `id` | Opaque unique string (`GameSave.newId`). Never reused. |
| `name` | User-visible name, auto-named at creation. |
| `createdAt`, `updatedAt` | UTC, millisecond precision. `updatedAt` is the time of the last decision; a rename keeps it. |
| `schemaVersion` | JSON schema version, `1` now. |
| `setup` | `MatchSetup`: seats (human / ai + `aiLevel` / remote, names), teams, `baseRules`. Rules never change during a save's life (changing them starts a new game). |
| `seed` | The game seed. Created once when the game starts, never regenerated. |
| `log` | `List<MoveLogEntry>`: the decisions `(seat, dice, tokenIndex, unit)`. |
| `finished` | Cache of `state.isOver`, for list rows. The replayed state is authoritative. |
| `summary` | `turnNumber` (after the last decision) and `finishOrder` (only when finished). List rows never replay. |
| `check` | Optional 16-hex fingerprint of the state after the last decision (section 4). |

`GameSave` is immutable. `GameSave.begin(...)` makes an empty save; `withEntry(entry, stateAfter, now)` appends one decision and refreshes `updatedAt`, `finished`, `summary` and `check`; `withName(...)` renames.

`MoveLogEntry.seat` is the roller (the seat whose turn it is), as `Engine.logEntry` records it; with teammate control the moved tokens belong to the partner.

## 4. JSON schema, version 1 (`SaveCodec`)

```json
{
  "schemaVersion": 1,
  "id": "mh3k9x2a-1f8c0d2e",
  "name": "2026-10-26 14:05",
  "createdAt": 1793023500000,
  "updatedAt": 1793024100000,
  "setup": { "seats": [ {"type":"human","aiLevel":"medium"}, ... 4 entries, null = empty ], "teams": false, "rules": { ... rulesToJson ... } },
  "seed": "1234567890",
  "log": "0a2c41...",
  "finished": false,
  "summary": { "turn": 57, "finishOrder": [] },
  "check": "9f2c4be07a1d3355"
}
```

- `setup` is `MatchSetup.toJson()` unchanged (it already carries rules and per-seat `aiLevel`).
- `seed` is a **decimal string**, so a 64-bit value survives any JSON reader. The decoder also accepts a JSON integer.
- `log` is a hex string, **one byte (2 hex digits) per decision**: `v = seat | (dice - 1) << 2 | tokenIndex << 5 | unit << 7`. Seat 0..3 (bits 0-1), dice-1 0..5 (bits 2-4), token 0..3 (bits 5-6), unit-move flag (bit 7). About 2 characters per decision, a long game stays near 2 KB. Decoding is case-insensitive; the encoder writes lowercase.
- `check` is an FNV-1a 64-bit hash over the integers of the state after the last decision (rng state, turn, seat, sixes, tokens, waits, finish order, bank, phase). It catches **engine drift**: if a later rules change alters what an old log replays to, the hash differs and the save is reported incompatible instead of silently showing another game. It is computed only from the state the engine returned right after `Engine.apply` (never after a later roll).
- Tolerance (like `SeatConfig.fromJson`): unknown fields are ignored; missing or wrongly typed optional fields fall back (`name` to the auto-name, a missing timestamp to the other one, `finished` to false, `summary` to empty, `check` to unchecked, unknown seat types to human). Fields the game cannot be rebuilt without are failures: `schemaVersion`, `id`, `setup` (four-entry seat list, two or more occupied seats), `seed`, `log` (section 7).
- Versioning: a reader migrates any older version forward (none yet) and refuses a newer one (`newerSchema`, shown as incompatible). Bump the version when the JSON shape changes or when a deliberate engine change must keep old logs replaying (the engine then needs a switch keyed on the version).

## 5. Resume semantics

Resume = decode, `SaveReplayer.replay` (strict), put the resulting `GameState` into the controller **without calling `newGame`**, and continue exactly as after a move.

The saved state is "just after the last decision". Everything after it is re-derived, and the PRNG state is the very one in force, so the next roll is the same face the player had already seen:

| Situation when the app closed | State after the replay | What happens next |
|---|---|---|
| Waiting for a roll | Awaiting roll | The roll happens; nothing to compare. |
| Rolled, move not yet chosen | The state before that roll | Rolling gives the **same face and the same legal moves**. Quitting never re-rolls. |
| A roll that auto-passed or forfeited (3 sixes) was on screen | The state before it | It plays out again, identically. |
| A chosen move still animating | Includes the move (it is saved when chosen, not when the animation ends) | The board shows the result, no animation. |
| Bonus roll pending (6, capture, home) | Awaiting roll with `consecutiveSixes` as it was | Same rolls. |
| Banked: still rolling sixes into the bank | Rolling, bank as of the last decision | The sequence re-rolls identically (the 6s were never stored). |
| Banked: all dice rolled, none spent | Same as above, the bank is re-rolled | Identical bank, identical `turnSnapshot`. |
| Banked: some dice spent (`bankPhase.moving`, bank not empty) | `awaitingMove` with the remaining bank and the rebuilt `turnSnapshot` | The controller goes straight to the move choice (tray), **not** to a roll. |
| Banked: capture/home bonus with dice left (`bankPhase.rolling`, bank not empty) | Rolling with the leftover bank | The bonus sequence rolls identically, the bank grows as before. |
| Game over | `isOver` | Not resumable; the replay viewer opens it. |

The controller must decide by `state.awaitingRoll` / `state.awaitingMove`, never by `dice == null`. A seed must never be re-drawn on resume, and nothing may advance `rngState` except `Engine.roll`. The AI and the look-ahead never read it (CI grep on `lib/ai/`), so thinking or quitting cannot influence dice.

## 6. Autosave points

- **After every decision, at the moment it is chosen** (`GameController._startMove`: `before`, `move`, `after`), not after the animation. `entry = Engine.logEntry(before, move)` (take it from the state **before** `apply`), `save = save.withEntry(entry, after, now)`, then `store.put(save)`.
- The first decision creates the save (`GameSave.begin(...).withEntry(...)`); there is no earlier write.
- A decision that ends the game writes `finished: true` in the same write.
- Rolls, passes and forfeits are not autosave points (they are re-derived). Pausing or backgrounding needs no extra write.
- Rename writes the save again (same `updatedAt`).
- Writes are one at a time per save (a small queue in chat B) so an older log can never overwrite a newer one. Every write holds the full log, so a failed write is healed by the next one.

## 7. Failure handling

Nothing in `lib/storage/` throws on bad data. Three layers, each returning a typed result:

1. **Decode** (`SaveCodec.decode / fromJson` -> `SaveDecoded | SaveDecodeFailed(SaveFailure)`). Problems: `notJson`, `notAnObject`, `badSchemaVersion`, `newerSchema`, `missingId`, `badSetup`, `badSeed`, `missingLog`, `corruptLog`, `unreadable`. A failure keeps the `id` and `name` when they could be read. `corruptLog` (bad character, bad value, odd length = cut off) also carries `logIndex` and a **salvage** `GameSave` holding the valid prefix (its `check` removed).
2. **Replay** (`SaveReplayer.replay(save)` -> `SaveReplay`). Stops at the last valid entry; reports `entryRejected` (index and reason, including entries after the game ended), `invalidSetup` or `checksumMismatch`. `SaveReplay.state` is the state after the entries that did apply, so a partial replay is possible. `SaveReplayer.timeline(save)` returns every intermediate state (index 0 is the start) for the viewer.
3. **Store** (`SaveStore.list` gives `SaveListItem`s with `SaveStatus.ok | damaged | incompatible`). Listing only decodes, it does not replay, so it stays cheap. `newerSchema` and `checksumMismatch` count as incompatible; every other failure as damaged.

Rules for the app:

- Only `ok` saves are resumable (`SaveReplay.resumable`). Open a save by decoding and replaying strictly; if the replay fails, show it as damaged/incompatible instead of opening it.
- Greyed rows cannot be opened or renamed; they can always be deleted. Nothing is ever deleted automatically.
- Chat B verifies saves lazily after the list shows (one `SaveReplayer.replay` per row when idle, memoised by `id + updatedAt`) and greys the ones that fail, because list rows alone cannot see an engine drift.
- A damaged save with a salvage (or a replay that stopped at entry k) can be offered to the replay viewer as "play up to move k".
- A failed autosave never blocks play: keep playing, retry with the next decision, show one quiet notice.

## 8. API (`lib/storage/storage.dart`)

- `GameSave`, `SaveSummary`, `GameSave.autoName / cleanName / newId`.
- `SaveCodec.toJson / encode / fromJson / decode`, `SaveDecode` (sealed), `SaveFailure`, `SaveProblem`; `MoveLogCodec.pack / unpack / encode / decode`; `StateFingerprint.of`.
- `SaveReplayer.replay / timeline`, `SaveReplay`, `SaveTimeline`, `ReplayFailure`, `ReplayProblem`.
- `SaveStore` (`list`, `get`, `put`, `rename`, `delete`, all async), `SaveListItem`, `SaveStatus`, `InMemorySaveStore` (also `putRaw` to plant a broken row in tests).

The package barrel is `package:ludo/storage/storage.dart`. `lib/storage/` imports only the engine barrel, `package:ludo/seats/seats.dart` and `dart:convert` / `dart:math`; a purity test and a CI grep keep Flutter and `dart:io` out.

## 9. Test plan (`test/storage/`)

- Move-log codec: all 192 valid entries round-trip, invalid values are refused, hex edge cases (`-1`, `+f`, upper case, odd length).
- `GameSave` / codec: round trip, fallbacks, every malformed-input case of section 7 (not JSON, wrong types, missing or too new schema, bad setup, bad seed, missing log), and a fuzz test (random edits of valid saves and of the decoded JSON tree must never throw, decode or replay).
- Property test: many random playouts over Classic, Quick and Strategic, 2/3/4 players, teams with and without teammate control, banked rolls, and the blockade options. Autosave as the controller will (`begin` + `withEntry`), then encode, decode, replay: equal to the original final state, equal to `Engine.replay`, sampled prefixes equal to the live state after each decision.
- Truncated and corrupted logs: cut-off string, bad character, out-of-range die, an entry from the wrong seat, entries after game over, a flipped `check`, a wrong seed.
- Resume equivalence: for several prefixes of many games, replay the prefix, continue with the same remaining decisions, and the dice sequence (every roll, including passes and forfeits) equals the uninterrupted game; the unplayed roll after a resume equals the one the live game had shown.
- `InMemorySaveStore`: put/get/list order, upsert, rename (keeps `updatedAt`, refuses blank), delete, damaged and incompatible rows (listed, not opened, deletable).
- Purity of `lib/storage/` (no Flutter, no `dart:io`/`dart:ui`).
- If the property test finds an engine replay bug it is fixed in the engine with its own test.

## 9a. Not in this milestone

Cloud sync, export/import of saves, multiple saves per game (branching), and saving online matches (Milestone 8 will reuse the same log) are out of scope. Undo is possible later by dropping the last entries of a copy, but there is no UI for it.

## 10. Chat plan

- **Chat A (this one):** this doc, `lib/storage/`, `test/storage/`.
- **Chat B:** `sqflite` store implementing `SaveStore` (one table: `id` primary key, `name`, `created_at`, `updated_at`, `finished`, `schema_version`, `json`), `shared_preferences` for settings, autosave in `GameController` (hook in `_startMove`; the controller needs the seed, the log and the current `GameSave`; `newGame` resets them), `GameController.resume(save)`, a minimal Home with Continue and Saved Games (rename, delete, greyed rows), lazy verification, widget tests, CI green.
- **Chat C (done):** replay viewer, polish and tests, section 11. The PR is opened only after the on-device review (section 12).

## 11. Replay viewer (chat C)

Any save that opens can be watched, finished or in progress. A replay never writes: it has no `SaveWriteQueue`, `GameController.save` stays `null`, and the only store call it makes is the one read that opens it.

### Data

- `ReplayScript.of(save)` (`lib/storage/replay_script.dart`, pure Dart) is built on `SaveReplayer.timeline` and adds, for each decision `k` (1-based): `before` (the state after decision `k-1`), `ready` (`before` with the roll made, a die pending or, banked, the bank to spend), `move`, `after` (`== states[k]`) and the log `entry`. `ready` is `Engine.nextDecision(before)` unless `before` already awaits a move (banked, mid-spend). The move is found exactly like `Engine.applyEntry` does, and a step is accepted only if `Engine.apply(ready, move)` has the same fingerprint as `states[k]`; otherwise the script stops before it.
- `ReplayOpening` is the result of opening a save: `script`, `salvaged` (damaged file, readable start only), `partial` (the replay stops before the game did), or a refusal with a reason. `SaveLibrary.openReplay(item)` flushes the write queue, reads the stored row once and returns it; `ReplayOpening.of(save)` does the same for a save already in memory (game over).
- What can be replayed: a save that decodes and replays; a save whose log has an entry the engine refuses (plays up to the last valid entry, says so); a damaged log with a salvage (plays the readable start, says so). Refused, with no Replay action: unreadable rows, newer schemas, an engine drift (`checksumMismatch`, "incompatible": the replay would show another game), and anything with no decision to play. Rows that are greyed "Can't open" but have a partial replay (a salvage or a replay that stops at move k) stay greyed for resuming and offer "Replay (partial)" in their menu with "can replay k moves" in the subtitle.

### Presentation model

`GameController(setup: save.setup, seed: save.seed, replay: true, now: scaledClock)` is the table the screen paints, with no `saves`. It is not built with `resumeFrom` because `resume` refuses a finished game and a partial one; the replay loads states through two methods instead:

- `replayShow(state, rolls:)` shows a state at once (reset table, tray rebuilt from `state.bank`, ghost dice from `rolls`, game over without confetti or haptic).
- `replayPlay(ready, move, roller:, dice:, reverted:)` loads `ready` without animation and runs `_startMove(move)`: the normal hop, capture, home and tray-chip animations. A move that is still hopping is settled first.

In replay mode `roll`, `quickRoll`, `dockTap`, `tapAt`, `chipTap`, `trayTappable` and `_driveAi` do nothing, no AI worker is warmed up, and `_enterMoving` is never called (no choice, no forced spend).

### Controller and screen

- `ReplayController` (`app/lib/game/replay_controller.dart`): `position` (`0..N`, "after decision k"), `play/pause`, `speed` (1x, 2x, 4x), `stepForward` (animated), `stepBack`, `toStart`, `toEnd`, `seek` (all three show the state at once), `tick`. Every manual control pauses playback. Playing waits for the hop to end, then `gapMs` (450 ms) of the scaled clock, then the next decision; after the last one it pauses by itself. Play at the end starts over.
- Speed is a `ScaledClock` (`lib/ui/core/scaled_clock.dart`) handed to the table as its clock, so hops, rings and chips all follow it, and a speed change never makes time jump.
- `ReplayScreen`: the normal `TableView` (orientation, reduce motion and haptics settings apply; the menu button becomes a close button; no game-over card) above `ReplayControls`: what happened (`Red rolled 4 · moved token 2`, or `moved Yellow's token 2` under teammate control, `blockade of tokens 1 and 2` for a unit move), `Move k of N · Turn t`, the scrubber, jump/step/play buttons and the speed button. A notice line says "Damaged save: replaying the first k moves." or "This replay stops after move k". Leaving the screen disposes the ticker and the controller.
- Not shown, by design: rolls that passed (no legal move, three sixes) and banked dice rolled before a spend are not in the log. The viewer starts each decision at its `ready` state. When banked rolls reverted a turn between two decisions (a dead end) the tokens are simply back, with a "Turn undone" notice, not animated.

### Entry points

- Saved Games: tapping a finished row replays it, tapping an unfinished row resumes it, every openable row has "Replay" in its menu. The empty state has a "New game" button.
- Game over: "Watch replay" next to Rematch and Menu, shown when the game has a save. It opens the save held in memory by the controller (`GameController.save`, the same object the queue wrote), so it never reads the store.

### Replay and the autosave of the active game

A replay cannot start while its save is being written, today:

1. Saved Games is only reachable from Home, and a game is a route pushed over Home or Saved Games, so a running game and the list are never interactive together.
2. The game-over replay uses the in-memory save of a game that is over (no further decision, no further write).
3. `SaveLibrary.openReplay` (like `verify`) waits for the write queue before it reads, and a write replaces the whole row (`put` carries the full log), so a read sees either the old or the new log, never half of one. When online play or a second surface arrives (Milestone 8) this guarantee has to be kept or the replay has to read from memory.

### Tests

`test/storage/replay_script_test.dart` (every setup of the property matrix: step fields, fingerprints, shorter scripts for bad logs, `openReplay` for whole, salvaged, drifted, too-new and missing rows, waiting for queued writes), `test/ui/scaled_clock_test.dart`, and in the app `replay_controller_test.dart` (forward/back/scrub for plain, banked mid-spend, team with teammate control and finished games; speed and auto-pause; no store writes; disposal; property: forward then back equals `SaveReplayer.timeline` for five setups), `replay_screen_test.dart` (controls, notices, no input, disposal without timers, game-over "Watch replay", app wiring) and the extended `saved_games_screen_test.dart`.

## 12. What shipped, and the device checklist

Shipped in Milestone 5: `lib/storage/` (model, codec, replayer, script, library, write queue), the sqflite store, autosave in `GameController`, resume, Home, Saved Games (rename, delete, greyed rows, lazy verification, empty state), persisted settings, the replay viewer. Not shipped (section 9a): export/import, branching, online saves, undo.

Device review (all on the phone, release or profile APK from CI):

1. Replay of a finished game: tap it in Saved Games, play, auto-pause at the end, play again restarts.
2. Replay of an in-progress game: Replay from the row menu; the game can still be resumed afterwards and continues from the same place.
3. Scrub and speed: drag the slider (no hops, tokens jump), switch 1x/2x/4x while playing (no jump in the animation).
4. Banked mid-spend replay: a banked game replayed over a turn with several dice (chips in the tray shrink as they are spent, no move choice appears).
5. Teammate-control game: the finished player's roll moves the partner's token and the text says so.
6. Salvage replay: a save with a damaged log (planted by editing the stored row) offers "Replay (partial)", says how many moves it plays and stops there.
7. Leave mid-replay (close button, system back) and return to Home: no crash, no stuck ticker (the table is gone, battery calm).
8. Memory and frame timing during a long replay (frame overlay in Settings, profile APK): paint stays under 4 ms, particles at most 60.
9. After any number of replays: no new save in the list, no changed date or name, "Continue last game" still points at the same game.

