---
title: Ludo Animation & Shader Plan (Milestone 2)
tags: [project]
updated: 2026-10-16
---

# Ludo Animation & Shader Plan

Resolves the "UI Animation Curves & Shaders" deferred item in [[ludo-roadmap]].
All numbers are the *starting* values; they live in one `MotionSpec` class so they can be tuned on a device without touching logic.

Related: [[ludo-blueprint]] (section 9), [[ludo-rules]], [[ludo-engine-tests]].

---

## 1. Principles

1. **Engine first, animation second.** The engine has already produced the new `GameState`. Animations are a *presentation* of the diff `before -> after`; they never decide anything and never mutate state.
2. **Animations are pure functions of time.** `pose = timeline.sample(tMs)`. No hidden state, so they are unit-testable with `dart test` and replay-safe.
3. **Units are grid cells** (board = 15 x 15). The painter multiplies by cell size, so geometry and motion are resolution independent.
4. **Transform + opacity only** for tokens (blueprint rule). No `saveLayer`, no `MaskFilter.blur`, no `ColorFilter` in the animated layer.
5. **One clock.** A single `AnimationController` drives the dynamic layer; the static board is never repainted during play.
6. **Reduced motion is a first-class mode** (`MediaQuery.disableAnimations`): hops become a 120 ms cross-fade, no shake, no ring, dice shows the result immediately.

---

## 2. Board geometry (15 x 15 grid)

Seat 0 = top-left yard, seats run clockwise (0 TL, 1 TR, 2 BR, 3 BL). Row 0 is the top.

- Absolute squares `0..12` are hand-listed; `13..51` are the same cells rotated 90 degrees clockwise (`(x, y) -> (15 - y, x)` in continuous coordinates), which mirrors the engine's `+13 per seat` offset exactly.
- The track cuts **diagonally** around the 4 inner corners of the cross (abs 4->5, 17->18, 30->31, 43->44), so those hops are 1.41 cells long; every other step is 1 cell.
- Seat 0 start `(1,6)`; star squares (abs 8, 21, 34, 47) land on `(6,2) (12,6) (8,12) (2,8)`.
- Home column of seat 0 = cells `(1..5, 7)`; other seats rotate it. Finish slot is in the centre 3 x 3, nudged toward the owner's arm.
- Yard spots (seat 0): `(2,2) (4,2) (2,4) (4,4)`, rotated per seat.
- **Stacking:** several tokens on one cell (safe squares, home column) get a grid offset and a smaller scale (1 token = 1.0, 2 to 4 = 0.8, 5+ = 0.62). Resting positions are computed from the whole `GameState`.

---

## 3. Curve library

| Name | Formula | Used for |
|---|---|---|
| `easeOutCubic` | `1 - (1-t)^3` | dice spin-down, ring burst, UI fades |
| `easeInOutCubic` | standard | captured token flight |
| `easeInOutSine` | `0.5 - 0.5 cos(pi t)` | legal-move pulse |
| `easeOutBack(1.7)` | overshoot to ~1.1 | finish shrink-to-pocket |
| `cubicBezier(x1,y1,x2,y2)` | Newton + bisection solver | tunable custom easing (e.g. `0.2, 0.8, 0.2, 1`) |
| `arc(u, h)` | `4 h u (1-u)` | hop height (parabola, apex `h` at u = 0.5) |
| `dampedSine(u, cycles, decay)` | `e^(-decay u) sin(2 pi cycles u)` | shake, dice settle wobble |

Integer `cycles` guarantee the value returns to exactly 0 at `u = 1`, so segments join without a pop.

---

## 4. Motion spec

### 4.1 Token hop (per move)

| Parameter | Value |
|---|---|
| Step duration | 130 ms per square, linear horizontal travel |
| Hop height | 0.35 cell, parabola |
| Yard exit | one 220 ms hop, height 0.6 cell |
| Landing squash (final square only) | 100 ms: `scaleY = 1 - 0.18 sin(pi u)`, `scaleX = 1 + 0.12 sin(pi u)` |
| Intermediate landings | no squash (keeps the run fluid) |
| Anticipation | none: the token leaves the instant the player taps (input latency matters more than flourish) |
| Max duration | 6 squares: `6 x 130 + 100 = 880 ms` |

The shadow stays on the ground and shrinks/fades with `lift`.

### 4.2 Capture (starts at the capturer's impact, i.e. when its last hop lands)

1. **Impact shake** of the victim, 220 ms: `x += 0.12 * dampedSine(u, cycles 5, decay 5)`.
2. **Return flight**, 420 ms: straight line to its yard spot (not along the track), `easeInOutCubic`, arc height 1.2 cells.
3. Capturer's landing squash plays during the shake. Haptic: medium impact at impact time.
4. Capture adds 640 ms to the turn's animation time; input stays locked until `totalMs`.

### 4.3 Finishing

- Final hop, then the token eases to 0.55 scale in its pocket slot (`easeOutBack`, 260 ms); no squash.
- **Ring burst** at the pocket: stroked circle, radius 0.5 -> 1.6 cells, opacity 0.8 -> 0, `easeOutCubic`, 420 ms.

### 4.4 Dice (600 ms total, matches blueprint)

- Outcome is rolled by the engine *before* the animation starts.
- **Tumble 0 to 480 ms:** rotation `(1 - easeOutCubic(u)) * 3 turns` (ends upright); scale `1 + 0.15 sin(pi u)`.
- **Face flicker:** 9 changes, timed by `easeOutCubic` (fast first, slowing down), every flicker face is offset 1..5 from the rolled value (so the result is never shown early) and two consecutive flickers never match.
- **Settle 480 to 600 ms:** scale `1 + 0.06 dampedSine(s, 1.5, 4)`. Light haptic on settle.

### 4.5 Legal-move highlight

- One shared pulse, period 900 ms, `w = easeInOutSine` wave 0..1..0.
- Ring radius `0.62 + 0.14 w` cells, opacity `0.35 + 0.55 w`.
- Only tokens with a legal move pulse; tapping one cancels all pulses instantly.

### 4.6 Misc

- Turn indicator cross-fade: 180 ms `easeOutCubic`.
- Illegal tap: 160 ms horizontal nudge `0.06 * dampedSine(u, 2, 6)`.

---

## 5. Shaders

**Decision: Milestone 2 ships zero custom fragment programs (`.frag`).**

Reasons: the size budget (15 MB), cold-start budget (runtime shader assets load asynchronously), and the fact that everything in section 4 is achievable with built-in shaders. Flutter's `Gradient` objects *are* shaders (`Paint.shader`), so we still get GPU-side effects:

| Effect | Implementation |
|---|---|
| Legal-move glow | `RadialGradient` (seat colour, alpha 0.9 -> 0) as `Paint.shader`, scaled by the pulse. No blur. |
| Token body | `RadialGradient` highlight offset up-left for a subtle 3D look |
| Board surface | `LinearGradient` very subtle vignette, baked into the cached static layer |
| Dice face highlight | `SweepGradient`/`LinearGradient` sheen, cached |
| Ring burst | plain stroked circle with animated alpha |

Gradient shaders are created once per size/theme change and reused (four seat colours x glow), never per frame.

**Custom `.frag` is allowed later (candidate: victory shimmer, Milestone 6) only if all hold:**
1. It cannot be built from gradients + transforms.
2. Source <= 2 KB, Impeller-compatible.
3. Measured <= 1 ms/frame on the mid-range target in profile mode.
4. There is a static gradient fallback.

---

## 6. Render architecture

| Layer | Content | Repaint rule |
|---|---|---|
| L0 static | board, yards, safe-square markers, vignette | `RepaintBoundary` + cached `Picture`; rebuilt only on size or theme change |
| L1 tokens | resting + animating tokens, shadows | repaints on the shared ticker only while a move animation runs |
| L2 overlay | glow rings, ring burst | same ticker; during idle only the pulse runs |
| Dice | separate widget | own controller |

- Z-order: tokens sorted by row (lower on screen drawn later), the moving token always on top.
- `Paint` objects preallocated; no allocation inside `paint()`.
- Budget: paint <= 4 ms of the 16.6 ms frame on the target device; 0 dropped frames.

---

> **M2 implementation notes.** The Flutter app lives in `app/` (own pubspec, path dependency on the root pure-Dart `ludo` package) so `dart test` keeps working in Termux and the engine stays Flutter-free. L1 and L2 share one `TokenLayerPainter` in M2. Glow = fixed-alpha radial gradient whose *size* pulses plus a ring whose alpha pulses (paint alpha on shader paints is not relied upon). Illegal-tap nudge is deferred.

## 7. Code structure (pure Dart first)

Everything that is math lives in `lib/ui/core/` with **no Flutter import**, so it is testable with plain `dart test` and the Flutter layer is only a thin painter:

```
lib/ui/core/
  pt.dart              # 2D point
  curves.dart          # easing library
  motion_spec.dart     # every tunable number
  board_geometry.dart  # cells, yards, finish, stacking, resting points
  dice_timeline.dart   # dice pose(t)
  token_timeline.dart  # hop / captured / ring pose(t)
  move_plan.dart       # state diff -> animation plan
```

A purity test guards `lib/ui/core/` the same way as the engine.

## 8. Milestone 2 build order

| Step | Work | Needs Flutter SDK |
|---|---|---|
| 2a | Pure Dart core above + tests | no |
| 2b | Flutter scaffold (`flutter_test`, Android folder), analyzer config | yes |
| 2c | `BoardPainter` static layer + golden test | yes |
| 2d | Token layer, legal-move overlay, hit testing | yes |
| 2e | Dice widget | yes |
| 2f | Hot-seat game screen wired to `Engine` (plain `ChangeNotifier`, no new package) | yes |
| 2g | Profile-mode perf pass on device | yes |
