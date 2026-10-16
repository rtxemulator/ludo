---
title: Ludo UI/UX Redesign (Milestone 2 polish)
tags: [project]
updated: 2026-10-16
---

# Ludo UI/UX Redesign

Design for the polish round after the first on-device test. Builds on [[ludo-animation]]; does not change [[ludo-rules]] (rule changes are owned by the Milestone 1 chat, see section 10).

Feedback addressed: no haptics felt, dice animation too plain, centre dice bad for couch play, token/shadow only look right from one side, gap between yards and path, no board frame, top-left text, missing nudges and capture / yard-exit / home polish.

---

## 1. Design principles

1. **Table, not screen.** Players sit around a flat device, one per side/corner. Nothing may have a built-in "up": no directional light, no screen-up shadow offset. Text that is shown to a player faces that player (section 3).
2. **Overhead light.** One light straight above: shadows are centred, bevels and highlights are symmetric (frame, tokens, dice).
3. **Height = scale, not Y-offset.** A hopping token or tossed die gets bigger and its shadow softer/wider. It never moves toward screen-up (that reads as "sinking" from the top side).
4. **The board is the HUD.** Turn, prompt and result are shown by the yard, the dock and the dice, not by a text line.
5. **Big targets.** Whole dock zone rolls; whole token cell selects.
6. **Everything procedural.** No raster assets, no new packages (haptics via a tiny native channel). Motion stays pure functions of time in `lib/ui/core`.

---

## 2. Screen anatomy (portrait phone)

```
 +--------------------------------+
 |  [dock 0]      [=]    [dock 1] |   table margin (felt)
 |   +----------------------+     |
 |   |  wooden frame        |     |
 |   |   board 15 x 15      |     |
 |   +----------------------+     |
 |  [dock 3]             [dock 2] |
 +--------------------------------+
```

- **Table:** dark neutral felt with a faint vignette (procedural gradient). Light theme = warm linen.
- **Docks:** one per seat, in the table margin next to that seat's yard corner (seat 0 TL, 1 TR, 2 BR, 3 BL). Each dock is a ~4.5 x 3.5 cell zone; the die is ~1.9 cells.
- **Menu button:** small round icon in the top-centre margin. The glyph is rotation-neutral; the sheet it opens follows section 3.
- **Layout engine** (`TableLayout`, pure Dart): board side = `min(width - 2 pad, ...)`; docks go in whichever margin pair is larger (top/bottom on phones, left/right on landscape/tablets). If a margin is under ~3 cells the dock falls back to the yard interior. The layout also reports, per seat, which edge it faces (section 3).
- Nothing else on screen: the top-left status text is removed.

---

## 3. Orientation (decided with the user)

Casual play is face-to-face with the device flat: one player per side/corner.

### 3.1 Default: Table mode (multi-seat / local play)

Everything addressed to one player **faces outward toward that seat's nearest table edge**, so the player sitting there reads it right-side up.

| Seat edge | Text rotation | Phone portrait seats |
|---|---|---|
| bottom | 0 deg | seats 2 (BR), 3 (BL) |
| top | **180 deg** | seats 0 (TL), 1 (TR) |
| left (landscape/tablet layout) | 90 deg clockwise | seats 0, 3 |
| right (landscape/tablet layout) | 270 deg clockwise | seats 1, 2 |

Per-seat elements that rotate: toasts ("No move", "Three sixes"), the rank badge at game over, the roll tray chips and any bank hints. Dice pips and tokens have no "up", so they are never rotated (the dice gets a random yaw anyway).

**Shared UI** (menu sheet, game-over card with Rematch/Menu) rotates to the **active seat** when the sub-option "Auto-rotate shared UI to active seat" is on (default on in Table mode), with a 250 ms turn animation. At game over, each seat gets its own rank badge at its dock facing it, and the shared buttons face the winner.

### 3.2 Pass-and-play / single-person: Fixed orientation

A lightweight setting for testing alone or passing the device at a table edge:

- **UI orientation:** `Table (default)` or `Fixed`. In Fixed everything is upright (0 deg), the layout is unchanged.
- **Auto-rotate shared UI to active seat:** on/off, only meaningful in Table mode. Turning it off keeps per-seat text facing outward but leaves shared sheets upright.

Implementation: one pure function `seatTextTurns(layout, seat, mode) -> quarter turns` in `lib/ui/core`, unit tested for every seat in portrait and landscape layouts, plus Fixed mode. The Flutter side wraps text in `RotatedBox`/`Transform.rotate` driven by it.

---

## 4. Dice and docks

### 4.1 Behaviour

- The active seat's dock shows a fresh die with an **idle bob** (+-0.04 cell, 1.6 s) and soft halo. Tapping the die or anywhere in the dock zone rolls.
- Other seats' docks keep a **ghost die**: their last result, 45% opacity, 0.8 scale, desaturated, no bob. Cleared on new game.
- When a seat becomes active, its ghost lifts and becomes the live die (handoff 200 ms) and the previous seat's die settles into its ghost state.
- Tapping a non-active dock does a short dock pulse, nothing else.
- Tapping the die mid-roll skips to the settle (quick-roll).

### 4.2 3D tumble (pure Dart cube, drawn with `CustomPainter`)

- Cube with standard pips (opposite faces sum to 7), flat-shaded by an overhead light, rounded face corners, thin bevel line, pips drawn per visible face through an affine transform (max 3 visible faces, <= 18 pips per frame).
- Orientation `R(t) = R_final(value) * Rot(axisA, a(t)) * Rot(axisB, b(t))` where `a, b -> 0` with `easeOutCubic`; `R_final` puts the rolled face up with a deterministic yaw. So the result is correct by construction and never leaks early.

| Phase | Time (ms) | Detail |
|---|---|---|
| Pop-in | 0 - 120 | scale 0.6 -> 1.1 -> 1 (`easeOutBack`), leaves the "hand" edge of the dock |
| Flight | 120 - 420 | arc, apex 1.6 cells of height (scale +45%, shadow widens and fades) |
| Bounce 2 | 420 - 650 | apex 0.55 |
| Bounce 3 | 650 - 800 | apex 0.18 |
| Settle | 800 - 920 | slide + damped yaw wobble (+-4 deg), face locks |
| Reveal | 920 - 1120 | result ring pulse; a **six** gets a gold halo flash (bonus turn) |

- Impacts (420, 650, 800 ms): uniform press 1 -> 0.96 -> 1 (60 ms), tiny dust ring, haptic tick (strength 0.9 / 0.5 / 0.25).
- Landing spot: dock centre + small deterministic jitter (seeded from the roll), so repeats do not look identical.
- Reduced motion: 120 ms fade-in showing the result, no tumble.
- Total ~0.9 s to settle (was 0.6 s but far richer); tune on device, quick-roll covers impatience.

---

## 5. Board, frame and the yard gap

- **Gap fix:** yards become flush quadrants (no deflate, no rounded inner corners), exactly meeting the path arms, one continuous surface. Only the outer board corners are rounded (matching the frame radius). The inner white panel keeps its rounding.
- **Wooden frame (procedural, ~0.45 cell thick):**
  - base `LinearGradient` in two browns, symmetric (no top-left bias);
  - grain: ~40 thin seeded-random strokes along the frame direction, low alpha;
  - bevel: 1 dark outer hairline + 1 light inner hairline;
  - baked into the cached static layer, zero per-frame cost.
- **Turn light:** the active yard gets a slow breathing inner glow (period 2 s); inactive yards are 15% desaturated. No text needed.

---

## 6. Tokens: natural from every side

Replace the "ball with shadow below" look with a **top-down pawn disc**:

| Part | Spec |
|---|---|
| Base ring | `seatDark`, radius 1.0 |
| Body | seat colour, radius 0.78, radial gradient lighter at the centre |
| Dome | `seatLight` highlight, radius 0.52, tiny specular dot at the centre |
| Rim light | thin 12% white ring (symmetric) |
| Emblem (optional, accessibility) | circle / square / triangle / diamond per seat |

- **Shadow:** centred circle, contact core (tight, darker) + penumbra (wide, light). In the air: radius `x (1 + 0.35 h)`, alpha `/ (1 + 2 h)`, shifted **away from the board centre** by `0.12 h` cells (parallax, radially symmetric, no screen-up).
- **Hop:** token scale `1 + 0.5 h` (0.35 cell hop = +17%, yard exit 0.6 = +30%). **No** vertical translation.
- **Landing:** uniform press (1 -> 0.9 -> 1, 100 ms) instead of the vertical squash, plus a dust ring (radius 0.5 -> 0.9 cells, alpha 0.25 -> 0, 160 ms).
- Remove row-based z-sorting (wrong from the top side); draw moving tokens last, others by stable seat/index order.

---

## 7. Motion polish catalogue

| Moment | Effect | Haptic |
|---|---|---|
| Illegal tap (token with no move, or opponent token during a choice) | 160 ms nudge `0.07 x dampedSine(2 cycles)` + faint red ring | double tick |
| Tap board while waiting to roll | dock halo flash (300 ms) | none |
| No legal move | die shakes, tokens dim 200 ms, toast "No move" at the dock (facing that seat), turn glow travels to next yard | single soft |
| Leave yard | yard spot ring contracts, token rises (higher arc), ripple at start square | tick |
| Capture | impact shockwave ring (r 0.4 -> 1.2, 260 ms); victim flips like a coin (`scaleX = cos(2 pi 1.5 u)`) while flying home, lands with press + ripple | heavy double |
| Reach home | token settles into pocket, pocket glow (500 ms), 8 radial sparks (0.9 cell, fade), ring | rising triple |
| Roll a six | gold halo on the die | medium |
| Win | confetti (<= 60 deterministic particles), per-seat rank badges | pattern |

Toasts: small pill at the active dock, rotated per section 3, 1.2 s, fades; text only for transient notices.

---

## 8. Menu, game over, settings

- **Menu sheet** (top-centre icon): New game, Settings, Rules (placeholder until the rules chat lands), Close. Oriented per section 3.
- **Settings (in-memory for now, `shared_preferences` in Milestone 6):** Haptics on/off, Reduce motion override, UI orientation (Table / Fixed), Auto-rotate shared UI to active seat.
- **Game over:** per-seat rank badges (1st to 4th, seat colours) at each dock facing its player, confetti, shared "Rematch" / "Menu" buttons facing the winner.

---

## 9. Haptics (why none were felt, and the fix)

Likely cause: Flutter's `HapticFeedback.*` goes through Android's `performHapticFeedback`, which many phones silence when "Touch feedback / haptic feedback" is off in system settings, and which cannot express strength or patterns. The current code is otherwise correct (calls fire, errors are swallowed).

Fix: a small native channel (no package): `VibrationEffect` predefined effects (API 29+: tick / click / heavy click), `createOneShot` with amplitude (API 26+), plain `vibrate(ms)` below that (minSdk 24), plus `VIBRATE` permission. Dart side maps named events to patterns; `HapticFeedback` stays as fallback.

| Event | Pattern |
|---|---|
| dice impact | tick x3, strength 0.9 / 0.5 / 0.25 |
| dice settle | click |
| token land | tick |
| capture | heavy click, 40 ms gap, click |
| home | click, click, heavy (rising) |
| illegal | tick, 60 ms gap, tick |
| six | medium click |
| win | 5-pulse pattern |

Rate-limited (>= 30 ms apart), global toggle, skipped when the system disables vibration. Needs `app/android/` committed (it is generated in CI today): add a one-off CI artifact step, download it, commit, drop the gitignore lines. First thing to verify on the phone; also check Android Settings > Sound & vibration > touch/vibration feedback.

---

## 10. Banked rolls ("stacking dice") - UI contract with the rules chat

The rules chat decides the rules; this UI must be data-driven so it works whatever they are. Needed from the engine (names are placeholders):

1. `state.bank` per seat: ordered list of banked die values (empty when the rule is off).
2. A way to **roll without moving** when the rules allow it (e.g. `Engine.roll` allowed again while the bank is non-empty), and a limit (`maxBank`).
3. `Engine.legalMoves(state)` returning moves that carry **which banked value** they spend (e.g. `Move.die`), so one token can have several options.
4. Whether bonus turns (six, capture, home) add a roll to the bank or grant an immediate roll.
5. Interaction with triple-six forfeit (does it clear the bank?).
6. Whether the bank survives turn passes.

UI built on that contract:

- **Roll tray** beside the dock: banked values as small die chips (1.1 cells) in a fan, oriented per section 3; selected chip lifts and glows.
- Legal glows follow the selected chip; tapping a token spends the selected value; with a single option it auto-selects.
- Spent chip flies to the token and dissolves; a new roll appends a chip with a mini pop.
- If several values are playable on the tapped token the tray pulses to prompt a choice.
- Main die stays the roll button; it is disabled with a "bank full" shake when `maxBank` is reached.

All of this is hidden when the rule is off, so it does not block the other work.

---

## 11. Work plan

Order is chosen so device-visible wins come first and nothing waits for the rules chat until the last step.

| Step | Work | Pure core tests | Verify on device |
|---|---|---|---|
| P0 | Commit `android/`, native haptics channel + event table + toggle | event table, rate limiter | feel each pattern |
| P1 | Pure core: `table_layout` (+ seat edges, `seatTextTurns`), `dice3d` (cube math, bounce timeline), `fx` timelines (rings, sparks, confetti, coin flip), token pose change (lift = scale), uniform press | all faces end up on top, monotone decay, deterministic, layouts fit 9 aspect ratios, text turns for every seat/mode | - |
| P2 | `TableView`, felt, wood frame, yard flush fix, turn glow | - | gap gone, frame look |
| P3 | Token pawn painter, radial parallax shadows, remove y-sort | - | view from all four sides |
| P4 | Docks, 3D dice painter, ghost dice, roll interaction, quick-roll | - | dice feel |
| P5 | FX: dust, shockwave, coin flip, yard exit, home sparks, nudges, rotated toasts | - | each moment |
| P6 | Menu sheet, settings (orientation modes), game-over badges, confetti | - | flow, rotation per seat |
| P7 | Performance pass (old 2g): profile mode, 0 dropped frames | - | frame timing |
| P8 | Roll tray and bank UI | contract tests | after rules chat lands |

Budgets: no new packages, no raster assets, paint <= 4 ms/frame, particles <= 60, APK growth negligible (size reduction remains a Milestone 7 item).

---

## 12. New-chat plan (decided)

Long chats re-read their whole history every turn, which burns usage and drifts. The repo is the shared memory (`CLAUDE.md` + `docs/`), so work is split into **4 chats, grouped by theme, not one per step**:

| Chat | Steps | Why a boundary here |
|---|---|---|
| A | P0 + P1 | Native haptics + pure-Dart core. Ends with `dart test` green and one device check (haptics). |
| B | P2 + P3 + P4 | All visual layers (table, frame, tokens, docks, 3D dice). Needs the P1 core; share one device review at the end. |
| C | P5 + P6 + P7 | FX, menu/settings/orientation, performance pass. |
| D | P8 | Banked-roll tray, only after the rules chat defines the engine API (section 10). |

Rules for every chat:
- Start by reading `CLAUDE.md` and `docs/ludo-ui-ux.md` (plus `docs/ludo-animation.md` if touching motion). Do **not** re-plan.
- Work on branch `milestone-2-ui`; commit before and after each change (signed); push; CI job `app` must be green.
- At the end, update the status line in `CLAUDE.md` and tick the steps in section 11's chat table (add "done" notes below).
- Rule changes never happen in these chats; they go to the rules chat and arrive as engine commits.

Starter prompt (replace the steps):

> Read CLAUDE.md and docs/ludo-ui-ux.md. Implement steps P0 and P1 of section 11 on branch milestone-2-ui, following the principles in section 1 and the chat rules in section 12. Don't re-plan. Stop after CI is green and tell me what to check on the device.

---

## 13. Open questions

- Dock position: table margin beside the yard (this doc, default) vs inside the yard. Say if you prefer inside.
- Rules chat answers to the section 10 list.
