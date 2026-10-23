# Ludo Roadmap & Milestones

Phased implementation roadmap, acceptance milestones, deferred designs, and project workflow rules.

Related: [ludo-blueprint.md](ludo-blueprint.md), [ludo-rules.md](ludo-rules.md), [ludo-engine-tests.md](ludo-engine-tests.md)

---

## 1. Milestones

Each milestone ends with passing automated tests, manual verification, and a Git commit.

1. **Milestone 1 - Engine & Unit Tests:**
   - Implement `RulesConfig`, `GameState`, `Move`, `Dice`, and `Engine` in pure Dart (`lib/engine/`).
   - Implement all unit test cases and 10,000-game property playout in `test/engine/` (see ludo-engine-tests.md).
2. **Milestone 2 - Board UI & Animations:**
   - Single device, local hot-seat mode.
   - `CustomPainter` board rendering with layer caching.
   - Token hop, landing squash, capture shake, and glowing legal move animations.
3. **Milestone 3 - Seat Configuration:** (implemented, see ludo-seats.md)
   - Dynamic 2, 3, and 4 player setup screens.
   - 2v2 team configuration and slot assignment (Human / AI / Remote). Remote is modelled but not selectable until Milestone 8; AI seats play the `GreedyBot` baseline until Milestone 4.
4. **Milestone 4 - AI Engine:**
   - Background isolate execution to guarantee 60 fps main thread UI.
   - Difficulty levels (Easy, Medium, Hard, Expert expectiminimax / MCTS).
   - Automated self-play tournament regression tests.
   - Design and engine API check: `ludo-ai.md` (chats A/B/C; Expert is iterative-deepening expectimax, no MCTS).
5. **Milestone 5 - Saves & Replays:**
   - `drift` SQLite database integration.
   - Autosave after each move, continue-last-game shortcut, and deterministic game replays from seed + move log.
6. **Milestone 6 - Sound, Polish & Themes:**
   - `flutter_soloud` Opus audio engine integration.
   - Light haptic feedback, 2-3 cohesive palettes, dark mode, and settings screen.
7. **Milestone 7 - Performance Audit:**
   - Profile mode execution on target Android hardware.
   - Startup trace verification (<600 ms cold start).
   - APK / AAB size audit (<15 MB download size).
8. **Milestone 8 - Serverless P2P Multiplayer:**
   - Google Nearby Connections for local offline play.
   - `flutter_webrtc` data channels with QR / short-code manual signaling.
   - Provably fair commit-reveal dice synchronization.
9. **Milestone 9 - Release:**
   - Production Android app signing, AAB packaging, R8 shrinking, and Play Store listing assets.

---

## 2. Intentionally Deferred Design Decisions

- **AI Heuristic Weights & MCTS Tuning:** Starting weights and the MCTS decision (not in Milestone 4) are in `ludo-ai.md`; the weights are tuned by self-play in Milestone 4 chat B.
- **UI Animation Curves & Shaders:** Resolved 2026-10-16 in `docs/ludo-animation.md` (values are starting points, tune on device).
- **P2P Wire Protocol & ICE Negotiation:** Detail before starting Milestone 8.

---

## 3. Project Rules for AI Assistants

See `CLAUDE.md` in the repo root.

---

## 4. How to Start

Prompt the agent:
> "Implement Milestone 1 from docs/ludo-roadmap.md. Write the engine and tests only, no UI."

---

## 5. Milestone 2 polish round

Design and work plan for the post-device-test polish (haptics, 3D dice, docks, frame, token look, FX, menu, face-to-face orientation, banked-roll UI contract): `docs/ludo-ui-ux.md`. Work is split into 4 chats (section 12 of that doc).
