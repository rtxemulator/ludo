# Ludo Blueprint

Master architectural blueprint for the Android-first Flutter Ludo project.

Related: [ludo-seats.md](ludo-seats.md), [ludo-rules.md](ludo-rules.md), [ludo-engine-tests.md](ludo-engine-tests.md), [ludo-roadmap.md](ludo-roadmap.md)

---

## 1. Goals and Budgets

| Area | Target |
|---|---|
| APK / AAB download size | Under 15 MB (stretch target: under 10 MB) |
| Cold start to interactive home screen | Under 600 ms on a mid-range Android phone |
| Animation frame rate | Steady 60 fps (90/120 fps where supported), zero dropped frames |
| AI move calculation time | Under 300 ms at the highest difficulty level |
| Ads, analytics, trackers | None (zero telemetry) |

---

## 2. Tech Stack

- **Flutter + Dart:** Android first (minSdk 24) with the Impeller rendering backend.
- **Visuals:** Board and tokens drawn procedurally with `CustomPainter`, no raster image assets. Tokens are animated widgets using only transform and opacity.
- **State Management:** Riverpod, or plain `ChangeNotifier` to maintain low overhead.
- **Storage:** `drift` (SQLite) for games and replay logs; `shared_preferences` for settings.
- **Audio:** `flutter_soloud` (low-latency C++ backend), Opus audio files.
- **P2P Multiplayer:** `flutter_webrtc` with manual QR/short-code signaling. Offline local play via Google Nearby Connections plugin.
- **Build & Optimization:** R8 code shrinking, `--split-per-abi` or AAB bundle, baseline profiles for fast cold start.
- *Tradeoff:* Kotlin + Jetpack Compose offers marginally smaller size and faster startup, but Flutter was chosen so the pure Dart engine and UI can be ported to iOS later.

---

## 3. Directory Architecture

```
lib/
  engine/     # PURE Dart, zero Flutter dependencies
    rules_config.dart   # Configurable house-rule switchboard
    game_state.dart     # Immutable state representation
    move.dart           # Move definitions and validations
    engine.dart         # legalMoves(state, dice), apply(state, move)
    dice.dart           # Seeded PRNG and commit-reveal helper
  ai/         # Runs entirely in a background isolate
  seats/      # PURE Dart: SeatConfig, MatchSetup, presets, GreedyBot (see ludo-seats.md)
  storage/    # drift database, save/load, move log serialization
  net/        # WebRTC + Nearby Connections message protocols
  ui/         # Screens, CustomPainter board, token animations
  audio/      # Sound effects and ambient music players
test/         # Unit and property tests for engine and AI
```

> **Cardinal Rule:** `lib/engine/` must NEVER import Flutter (`package:flutter/*`). UI, AI, storage, and networking layers depend on the engine, never the reverse.

---

## 4. Data Model

- **Token Coordinates (relative per player):** `-1` yard; `0..50` main track; `51..55` home column; `56` finished.
- **GameState:**
  - `tokens[4][4]`: positions of all 4 tokens across all 4 seats.
  - `currentSeat`: active seat index (`0..3`).
  - `dice`: current die value.
  - `consecutiveSixes`: consecutive 6s rolled in the current turn.
  - `rngState`: internal state for the deterministic PRNG.
  - `turnNumber`: monotonically increasing turn counter.
  - `finishOrder`: seats in the order they finished (for `fullRanking`).
- **SeatConfig:** `{ type: human | ai | remote, aiLevel, teamId?, name }` x 4 seats. Accommodates 2, 3, or 4 players, team play, and human/AI mixes.
- **MoveLog:** sequence of `(seat, dice, tokenIndex)`. The whole game is deterministic and reproducible from `initialSeed + moveLog`; this powers autosaves, replays, undo, and network sync.

---

## 5. Rules

Fully configurable. See ludo-rules.md.

---

## 6. AI Design (Strong & Fair)

Detailed design (supersedes the outline below where they differ): `ludo-ai.md`.

- **Algorithm:** Expectiminimax with dice rolls as chance nodes (depth 2-3). Optional MCTS for the expert tier.
- **Evaluation heuristics:** token progress; captures vs danger of being captured; safe-square occupation; blockade formation; bonus for entering the home column.
- **Fairness:** AI uses only public game state and the identical seeded PRNG; it never peeks at future rolls.
- **Tiers:** Easy = greedy; Medium = depth 1; Hard = depth 2; Expert = depth 3+ or MCTS.
- **Validation:** self-play regression tournaments in `test/`. Target: Expert beats random playout >= 90% and beats Easy consistently.

---

## 7. Persistence & Save Games

```sql
CREATE TABLE games (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  createdAt INTEGER NOT NULL,
  updatedAt INTEGER NOT NULL,
  config_json TEXT NOT NULL,
  seed INTEGER NOT NULL,
  move_log_json TEXT NOT NULL,
  finished INTEGER NOT NULL
);
```

Autosave after every valid move; saved games can be renamed; "Continue Last Game" shortcut on the home screen.

---

## 8. Serverless P2P Multiplayer

1. **Signaling:** host creates a WebRTC offer encoded as a QR code or short string; guest returns an answer code, establishing a direct data channel.
2. **Move replication:** only moves go over the wire; both clients run identical deterministic engines.
3. **Provably fair dice (commit-reveal):** each peer generates a seed and sends its hash; both then reveal, verify hashes, and combine seeds (S = S_A xor S_B) to seed the roll PRNG.
4. **Validation:** each peer validates every incoming move with its local engine; illegal moves are rejected.
5. **Fallback:** if NAT traversal fails, offer Google Nearby Connections / local Wi-Fi.

---

## 9. UI & Animation Guidelines

- **Rendering:** pre-compute board geometry once; repaint only dynamic token and dice layers.
- **Tokens:** parabolic hop, squash on landing, shake on capture, pulsing glow on legal moves.
- **Dice:** ~600 ms with physics-inspired easing; the outcome is computed before the animation starts.
- **Design system:** 2-3 cohesive palettes, full dark mode, subtle haptics.
- **Screens:** Home, New Game, Game, Saved Games / Replay, Settings, Online Lobby.

---

## 10. Audio Architecture

- **Music:** one ambient loop (60-120 s, low-bitrate Opus) with its own volume slider.
- **SFX:** dice roll, token hop, capture, home column arrival, victory fanfare.
- **Loading:** lazy-load non-essential audio; keep dice and hop sounds pre-cached. All audio must be CC0 or self-recorded.

---

## 11. Project Rules for AI Assistants

See `CLAUDE.md` in the repo root.
