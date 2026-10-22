# Ludo Seats & Setup (Milestone 3)

How a match is configured: who sits where, who controls each seat, and which rules apply. Code: `lib/seats/` (pure Dart, only the engine's public surface; guarded by `test/seats/seats_purity_test.dart`) and `app/lib/ui/setup/` (the screen).

Related: [ludo-rules.md](ludo-rules.md), [ludo-blueprint.md](ludo-blueprint.md), [ludo-roadmap.md](ludo-roadmap.md)

---

## 1. Model

- `SeatConfig { type: human | ai | remote, aiLevel, name? }`. `name` null means the colour name (Red, Green, Yellow, Blue). There is no rename UI yet (names are shown nowhere on the table); the field exists for saves and online play.
- `MatchSetup { seats[4] (null = empty), baseRules, teams }`, immutable (`withPlayerCount`, `withSeat`, `withTeams`, `withRules`). `RulesConfig.teamsEnabled` is **derived**: `MatchSetup.rules` always matches the seats.
- `MatchSetup.newGame(seed)` is `Engine.newGame(seed, rules, activeSeats)`. Seed + move log + `activeSeats` + `rules` replays any match.
- `toJson` / `fromJson` (for `games.config_json` in Milestone 5). A damaged value falls back to four humans.
- `RulesPreset` (classic / quick / strategic / custom): `of(rules)` ignores `teamsEnabled`, `teammateControl` and `bankedRolls` (table options); `applyTo(current)` keeps them.

## 2. Layouts

| Players | Seats | Notes |
|---|---|---|
| 2 | 0 and 2 | Opposite corners (top-left / bottom-right: one player at each long edge of the phone). |
| 3 | 0, 1, 2 | Seat 3 empty. |
| 4 | 0, 1, 2, 3 | Free for all, or **Teams 2v2** (0+2 vs 1+3). |

Team play needs all four seats (engine rule). Going below four players drops team play. Empty seats have no dock, no dice, no tray and a veiled yard; the engine skips them in the turn order.

## 3. Problems (`MatchSetup.problems`)

`tooFewPlayers`, `teamsNeedFourPlayers`, `remoteUnavailable` (online seats exist in the model but cannot be chosen until Milestone 8). "Play" is disabled while any problem is listed.

## 4. Controllers in the game

`GameController` is built for a `MatchSetup`. The controller of the seat that **rolls** (`state.currentSeat`) also chooses, so under teammate control a finished AI player picks the move for its human partner.

- Human seats: taps, as before. Taps on the docks, board or tray during an AI turn are ignored (the dock only flashes).
- AI seats: `GameController.tick` rolls after `aiRollDelayMs` (700 ms) and picks after `aiMoveDelayMs` (650 ms) (250 ms with reduced motion), then uses the same roll / move paths as a person, so animation, haptics and the move log are identical.
- Until Milestone 4 every AI level uses `GreedyBot` (blueprint "Easy"): one move ahead, scores progress, captures, finishing, leaving the yard, safe squares and being in reach of an opponent 1-6 squares behind. It reads only public state and never the dice. Milestone 4 replaces it behind the same `choose(state, legal)` call.

## 5. Screens

`SetupScreen` (the app's first screen): player count (2/3/4), team mode (4 players), a `SeatMap` picture of the table, one tile per seat (Human / AI / Online-disabled), rule presets, Banked rolls, and an expandable list of every house rule (teammate control only in team play; the six optional blockade rules under "Blockades", disabled while their prerequisites are off). "Play" opens `GameScreen(setup, settings)`; the game menu has "Players & rules" to come back. The last setup and the `GameSettings` live in memory for the app's lifetime (disk persistence comes with Milestones 5 and 6).

## 6. Not in this milestone

AI levels and strength (Milestone 4), saved setups and "Continue" (Milestone 5), the home screen (with the saves), online seats (Milestone 8), seat renaming and showing names on the table.
