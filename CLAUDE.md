# Project rules for AI assistants

- Never import Flutter (package:flutter/*) into lib/engine/.
- Every rule change or engine addition requires a corresponding unit test.
- The engine is the single source of truth; the UI never mutates state directly.
- Add no external dependencies without asking first.
- Prefer procedural CustomPainter drawing over raster image assets.
- Create a Git commit before and after every AI-assisted code change.

Specs live in docs/. Start with docs/ludo-roadmap.md.

## Status

- Milestone 1 (pure Dart engine + tests) is DONE. Next: Milestone 2 (board UI & animations). Animation curves/shaders are planned in docs/ludo-animation.md. Pure-Dart motion/geometry core lives in lib/ui/core/ (no Flutter imports); the Flutter layer needs an SDK toolchain decision first.

## Engine notes (lib/engine/)

- Public surface: `import 'package:ludo/engine/ludo_engine.dart'`. Files: `board.dart` (coordinates, safe squares), `rules_config.dart`, `game_state.dart`, `move.dart`, `dice.dart` (SplitMix64 + commit-reveal), `sha256.dart` (pure Dart, no dependency), `engine.dart`.
- Flow: `Engine.newGame` -> `Engine.roll` (auto-passes on no legal move / triple-six forfeit; returns `RollResult` with the rolled value so the UI can animate it) -> `Engine.legalMoves` -> `Engine.apply`. `Engine.nextDecision` rolls until a choice is needed (bots/replay). `Engine.replay(seed, log)` rebuilds a game from `seed + MoveLogEntry` list.
- `GameState` is immutable; never mutate token lists. `controlledSeat` is the seat whose tokens move (differs from `currentSeat` under teammate control). `ranking`/`winners` give team-aware results.
- Move log records only decisions `(seat, dice, tokenIndex)`; forfeits and no-move passes are reproduced from the seed.
- Rule decisions the spec left open: yard exit always lands on square 0; with blockades off, landing on stacked opponents captures all of them; a blockade is 2+ tokens of one seat, teammates may pass but not land on it (unless the square is safe); `exactRollToFinish: false` clamps an overshoot to finish; a roll with no legal move passes the turn even on a 6.
- Tests: `test/engine/` (helpers in `helpers.dart`). The 10,000-game playout takes ~2.5 min on-device and has a 15 min timeout. A purity test fails if the engine imports Flutter/dart:ui/dart:io or reaches outside `lib/engine/`.
- Before committing: `dart format --set-exit-if-changed .`, `dart analyze --fatal-infos`, `dart test`. Dart is installed in Termux via `pkg install -y dart`.

## UI core notes (lib/ui/core/)

- Flutter-free math for Milestone 2 (guarded by `test/ui/core_purity_test.dart`): `board_geometry.dart` (15x15 grid, track/home/yard/finish cells, stacking), `curves.dart`, `motion_spec.dart` (every tunable number), `dice_timeline.dart`, `token_timeline.dart`, `move_plan.dart` (engine `before -> after` diff to animation plan).
- Painters must only sample these (`pose = timeline.sample(tMs)`); never put animation numbers in widgets. Spec: `docs/ludo-animation.md`.
- Flutter app lives in `app/` (package `ludo_app`, path dep on root `ludo`). Flutter is NOT installed in Termux: it is built/tested only by the CI job `app` (APK artifact `ludo-arm64-release`). Locally you can only `dart format` app/ code; run the CI via push (branch `milestone-*`) and read it with `gh run watch` / `gh run view --log-failed`. Android platform files are generated in CI (gitignored).
- Run root checks as before; root `dart analyze` excludes `app/`.

- Milestone 2 polish plan: docs/ludo-ui-ux.md. Rules: overhead light (no directional shadows/bevels), height = scale not Y offset, docks in the table margin, face-to-face text (upper seats rotated 180 deg by default, Fixed option). Work in 4 chats (A: P0+P1, B: P2-P4, C: P5-P7, D: P8 after the rules chat); each chat starts by reading this file and that doc, no re-planning. Status: plan written, nothing implemented yet.

## Local notes

Machine-specific Git/signing/SSH instructions live in `CLAUDE.local.md` (gitignored; read it before any git commit or push).
