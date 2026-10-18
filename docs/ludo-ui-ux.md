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
| A | P0 + P1 | Native haptics + pure-Dart core. Ends with `dart test` green and one device check (haptics). **Done**, see notes below. |
| B | P2 + P3 + P4 | All visual layers (table, frame, tokens, docks, 3D dice). Needs the P1 core; share one device review at the end. **Done**, see notes below. |
| C | P5 + P6 + P7 | FX, menu/settings/orientation, performance pass. **Done**, see notes below (awaiting the device review). |
| D | P8 | Banked-roll tray, only after the rules chat defines the engine API (section 10). |

### Done notes

**Chat A (P0 + P1), done.**

- P0: `app/android/` committed (generated once from CI, `VIBRATE` permission added, `**/key.properties` ignored); CI now runs `flutter create` only if `android/` is missing. `MainActivity` exposes the `dev.ludo/haptics` channel (`pulse(kind, strength)`, `isAvailable`): predefined tick/click/heavy effects on API 29+ at full strength, `createOneShot` with amplitude when the strength is lower and the hardware has amplitude control, plain `vibrate(ms)` below API 26. Event table, rate limiter (>= 30 ms) and toggle are pure Dart (`lib/ui/core/haptics.dart`); controller events wired today: dice settle, six, token land, capture, home, win. Not wired yet (their moments arrive later): dice impact (P4), illegal (P5). A temporary "Haptics test" sheet (vibration icon in the top bar) plays every pattern and flips the toggle; it goes away with the settings screen (P6).
- P1: `table_layout`, `dice3d`, `fx`, `TokenPose` change (lift = scale, uniform press) as specified; see `CLAUDE.md` for the file list. Decisions the doc left open:
  - Dock-local frame of the 3D die: origin = dock centre, `+y` toward the player's own edge (the "hand"), `-y` toward the board. The painter rotates it per seat.
  - The confetti burst flies radially with no gravity (a table has no "down").
  - Layout: if the best margin pair is under 3 cells the board shrinks (at most 10%) to buy it (tablets); beyond that the docks go inside the yards and the menu button gets its own strip above the board. In the left/right placement the menu sits in the left margin, vertically centred.
  - `coinFlipScaleX` is the signed `cos` from section 7 (ends at -1); the painter should use `.abs()` for a symmetric disc. It is not yet part of `TokenTimeline.captured` (P5 wires it).
  - Old 2D `DiceTimeline` stays until P4 replaces the dice view.

**Chat B (P2 + P3 + P4), done.** Decisions the doc left open:

- Layers (bottom to top): felt (+ soft centred frame shadow), cached frame + board, yard glow, tokens, docks, two temporary round buttons. The table runs edge to edge and applies the system insets itself.
- Yards are plain 6 x 6 rects clipped to the rounded board, so only the outer corners are round. Inactive yards get a 15% wash-out overlay (dynamic layer, so the board stays cached).
- Wood: radial base (light mid-sides, dark corners), 10 seeded strokes per side clipped to the mitred band, mitre seams, dark outer + light inner hairline. Concentric radii (outer = 0.4 + 0.45).
- Pawn: base ring 0.38 cell; body, dome and specular dot as in section 6; the optional emblem is not drawn yet. Shadow = core + penumbra shaders, alpha applied with a `dstIn` colour filter; drawn for all pawns before any pawn; draw order resting, victims, mover.
- The roll finishes at the die's **settle** (920 ms), not at the end of the reveal; the reveal ring keeps playing in the dock afterwards (`rollerSeat` + `dice` stay until the next roll). Quick-roll sets the clock to the settle and skips the impact haptics (only the settle click plays).
- Idle bob is a +-4% scale wobble (height = scale), not a Y offset. A seat with no roll yet shows a fresh die (face 1) only while it is on turn.
- The die's dock frame is applied by turning the canvas by `turnsForEdge`; the shadow drift is computed on screen with `rotateQuarterTurns`.
- Not done (belongs to later steps): dice dust rings (P5), toasts such as "No legal move" (P5; the old text line is gone), the illegal-tap nudge (P5), the emblem.

**Chat C (P5 + P6 + P7), done.** Decisions the doc left open:

- Effects live in an `FxScene` (`lib/ui/core/fx_scene.dart`, pure): rings, sparks, pocket glows and tap nudges carry **absolute** start times, so they outlive the `MoveAnimationPlan` that spawned them (`MoveAnimationPlan.plan(..., startMs:)` builds them, `GameController.fx` holds and prunes them each tick). The token timelines stay relative to the plan start.
- Catalogue wiring: dust ring at every landing; yard exit = ring contracting on the yard spot at t=0 + ripple at the start square on landing; capture = shockwave on the victim square at the impact, victim shakes, flips (`TokenPose.flipX = |cos|`, min 0.04) while flying, lands with the uniform press (+100 ms in `TokenTimeline.captured`) and a dust ring at its yard spot; home = 8 sparks + pocket glow (`shaders.glow`) + the old finish ring; six halo was already P4 (`Dice3dPose.goldOpacity`); dice dust rings at each of the three impacts (skipped by quick-roll).
- Illegal tap (`GameController.tapAt`): during a choice, a tap within 0.8 cell of a token that has no move nudges it sideways (`nudgeOffset`, 160 ms) with a faint red ring and the `illegal` haptic; while a roll is due, a board tap flashes the active dock. No-move: `noMove` haptic (new, soft tick), die shakes sideways in its dock frame, the controlled seat's tokens dim for 200 ms, and the turn glow now cross-fades from one yard to the next (`DockLook.live`) instead of jumping.
- Toasts ("No move", "Three sixes") and game-over rank badges are **painted** (`OverlayPainter`, `TextPainter` cache), not `Text` widgets: a canvas rotation by `seatTextTurns` turns each to face its seat, and the widget test "no text on screen" still holds. Toast pill sits on the strip between the die and the player's edge; the badge is centred on the dock.
- Confetti: `ConfettiBurst` from the board centre (<= 60 pieces, seat colours), started at game over; the ticker keeps running for `confettiMs` after game over, then `GameController.tick` notifies once so the screen stops it. Reduced motion: no confetti, badges appear at full size.
- Menu sheet and game-over card are `TurnedBox` squares (250 ms shortest-way turn) so a quarter turn never overflows; `sharedUiTurns(layout, activeSeat | winner, mode, autoRotate)` drives them. Menu: New game, Settings, Rules (placeholder), Close. Game over: Rematch + Menu facing the winner.
- Settings (`app/lib/settings/game_settings.dart`, in memory): haptics, reduce motion (System / On / Off), UI orientation (Table / Fixed), auto-rotate shared UI (table only), frame timing overlay. The haptics test sheet and the temporary round buttons are gone.
- P7: `FrameTimingOverlay` (`SchedulerBinding.addTimingsCallback`, mounted only while the setting is on) shows fps, dropped/slow frames, UI/raster times, p95/worst and the game's own paint time (`PaintProbe`, 4 ms budget). CI now also builds and uploads `ludo-arm64-profile` (profile-mode APK). Static fixes for per-frame allocations: dock halos and the yard turn light reuse one unit shader per colour (alpha through a `dstIn` filter) instead of building a gradient every frame. **No on-device numbers yet**: read them with the profile APK and the overlay (checklist in the chat C hand-off).

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
