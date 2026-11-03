# Ludo Sound, Themes & Settings (Milestone 6)

Design of the sound effects, the music, the palettes, the theme mode and the settings screen. Chat A lays the foundations (this doc, the settings model, the shared settings panel, the pure sound core) and adds no audio plugin; chat B builds the audio (assets and `flutter_soloud`); chat C builds the look (palettes) and finishes the milestone.

Related: [[ludo-roadmap]] (milestone 6), [[ludo-ui-ux]] (section 7 effects, section 8 menu and settings, section 9 haptics), [[ludo-saves]] (settings persistence, replay viewer), [[ludo-blueprint]] (section 10, audio architecture).

---

## 1. Decisions (approved)

- **Assets.** Sounds are synthesized by a committed script into Ogg Opus, at most 600 KB in total (chat B). The script is the source of truth; the `.ogg` files are build output that is committed with it.
- **Sound set.** Dice roll, dice settle, hop, land, capture, home, six, win, illegal/no-move and select. They are placed on the existing haptic call sites (section 2).
- **Defaults.** Effects on at 80 %, music off at 40 %.
- **Music.** Plays only on the table and replay screens, with 400 ms fades in and out, and pauses when the app goes to the background.
- **Replay.** Effects play at 1x and are silent at 2x and 4x. Music follows the normal music rules.
- **Runtime.** Audio initialises lazily after the first frame. Failures are silent (no audio is a valid state, never an error dialog). No audio focus is taken, so the user's own music or podcast keeps playing. Pitch and volume variation uses its own `Random`, never the engine's `rngState`.
- **Looks.** Three palettes, Classic, Slate and High Contrast, each in a light and a dark variant. Theme mode is System / Light / Dark and defaults to System; the palette defaults to Classic. Theme and palette are presentation only: no save-format change, nothing in `GameSave`, `lib/engine/`, `lib/storage/` or `lib/ai/`.
- **Settings screen.** One shared settings panel is used by both the Home screen (`SettingsScreen`, reached from a gear button) and the in-game menu.
- **Dependencies.** The only new dependency is `flutter_soloud`, added in chat B. Chat A and chat C add none. No raster assets.
- **Size.** Out of scope until Milestone 7 (the audio assets are capped by the 600 KB limit above and nothing else is optimised now).
- **Rules item removed.** The in-game menu loses its "Rules" item and page. Banked rolls stays in Players & rules (the setup screen); `GameController.setBankedRolls` stays.

---

## 2. Sound catalogue

Every sound sits on a haptic call site in `GameController` (`feedback.play(HapticEvent.x)`), except `hop`, which has no haptic. `sfxFor(HapticEvent)` in `lib/ui/core/sfx.dart` is the mapping. The player that bundles haptic and sound (chat B) calls both from the same place, so the two can never drift apart.

| Sound (`SfxEvent`) | Haptic event | Call site | Character | Duration |
|---|---|---|---|---|
| `diceRoll` | `diceImpact` | `tick`, first dice impact (420 ms into the roll) | three wooden knocks on the bounce times (420, 650, 800 ms), the last one softest | about 380 ms |
| `diceSettle` | `diceSettle` | `_finishRoll`, `_finishBankedRoll` (face locks, 920 ms) | one dry click, the die has stopped | about 90 ms |
| `hop` | none | one per hop step of a move (`hopStepMs` 130 ms), hooked in chat B | soft short pluck, light and wooden | about 70 ms |
| `land` | `tokenLand` | `tick`, move impact, a plain landing | pawn set down on the board, a muted tock | about 120 ms |
| `capture` | `capture` | `tick`, move impact with victims | heavier knock plus a short downward whoosh for the victim sent home | about 350 ms |
| `home` | `home` | `tick`, move impact on the finish pocket | three rising bell notes (a major triad), warm, not shrill | about 500 ms |
| `six` | `six` | after `diceSettle` of a 6 (80 ms later, like the haptic) | a bright two-note chime, a "lucky" accent over the settle click | about 260 ms |
| `win` | `win` | `tick`, entering `gameOver` | short rising fanfare, resolves on a held chord | about 1800 ms |
| `illegal` | `illegal`, `noMove` | illegal tap, bank shake, "No move", "Three sixes", "Turn undone" | a low double tick, flat and unhappy but quiet | about 160 ms |
| `select` | `select` | token or tray chip selected, variants prompt, formed blockade | a tiny high tick | about 40 ms |

Notes:

- `capture`, `home`, a formed blockade (`select`) and a plain landing share the one call site of the move impact; exactly one of them plays, as with the haptic.
- `noMove` maps to `illegal` on purpose: one "that did not work" sound for a refused tap and for a roll with no move. The toast already tells the two apart.
- Total length of the set is about 3.9 s; at 48 kbps mono Opus this is far below the 600 KB cap (section 3).

### Rate limits and variation (`lib/ui/core/sfx.dart`)

A per-event minimum gap stops a burst from smearing (a sound that fires again before the first has ended just muddies). Gaps in ms: `diceRoll` 300, `diceSettle` 100, `hop` 60, `land` 80, `capture` 150, `home` 200, `six` 200, `win` 1500, `illegal` 120, `select` 40.

Variation makes repeated sounds feel less mechanical: each cue gets a playback-rate factor `1 +/- pitch` and a gain factor `1 +/- gain` drawn from the player's own `Random`. `hop` and `land` vary the most (pitch 6 %, gain 8 %), `diceRoll` and `select` a little (3 %, 5 %), `win`, `six`, `home`, `capture` and `illegal` almost not at all (0-2 %), because those carry meaning.

---

## 3. Asset spec

- **Format:** Ogg Opus, mono, 48 kHz, about 48 kbps (voice-like VBR is fine). Music: stereo is allowed, 64 kbps.
- **Budget:** at most 600 KB for all sound and music assets together (the effects are under 100 KB at the lengths above; the rest is the music loop).
- **Generator:** one committed script (`tool/` , plain Python with the standard library plus an Opus encoder call, or Dart, decided in chat B) synthesizes every sound from oscillators, noise and envelopes, with fixed seeds so the output is reproducible. No samples taken from anywhere else, so there is nothing to license (blueprint section 10: CC0 or self made).
- **Location:** generated files in `app/assets/audio/`, registered in the app's `pubspec.yaml` assets list (chat B). Only audio is added there; there are still no raster assets.
- **Levels:** every effect is normalised to the same perceived loudness (about -16 LUFS integrated for the short ones, peak below -1 dBFS), so the 80 % default is comfortable and one volume slider is enough. Music is about 6 dB below the effects at the same slider value.
- **Music:** one seamless ambient loop of 60 to 120 s, soft, no percussion that fights the dice sounds.

---

## 4. Audio runtime rules (chat B)

- Lazy init: the audio engine starts after the first frame (`addPostFrameCallback`), never in `main` before `runApp`. Cold start is unchanged. Sounds queued before it is ready are dropped, not delayed.
- Failure is silent: any error from the plugin (init, load, play) turns audio off for the session and logs with `debugPrint`; the game goes on without sound.
- No audio focus: the app does not request it and does not duck other apps.
- Background: music pauses when the lifecycle leaves `resumed` and resumes (with a fade) when it returns; effects are never queued across a pause.
- Fades: 400 ms linear in and out for music (screen enter and exit, toggle, background, pause).
- Screens: music plays on the table (`GameScreen`) and on the replay viewer only. Home, Setup, Saved Games and Settings are silent.
- Replay: `ReplayController.speed == 1x` plays effects; 2x and 4x mute them (music is unaffected). A scrub or a jump plays nothing.
- Variation uses the `SfxPlayer`'s own `Random`. Nothing in the audio path may read `GameState.rngState` or call `Dice`.
- Settings are applied live: `sfxEnabled` and `sfxVolume` go to `SfxPlayer.enabled/volume`, `musicEnabled` and `musicVolume` to the music voice.

---

## 5. Sound core (`lib/ui/core/sfx.dart`, chat A)

Pure Dart like `haptics.dart` (guarded by `test/ui/core_purity_test.dart`; it only uses `dart:math` and `haptics.dart`).

- `SfxEvent`: the ten events above.
- `sfxFor(HapticEvent)`: the mapping (total: every haptic event has a sound). `hop` has no haptic source.
- `sfxMinGapMs`, `sfxVariation`: the tables of section 2.
- `clampVolume(double)`: into `0..1`, NaN becomes 0.
- `SfxCue(event, volume, rate)`: what the backend plays; `volume` is the slider value times the gain factor, already clamped; `rate` is the playback-rate factor.
- `SfxPlayer({emit, schedule, nowMs, seed})`: `enabled`, `volume`, `play(SfxEvent)`, `playHaptic(HapticEvent)`. It applies the enabled flag and the per-event rate limit, spreads delayed cues (`six` 80 ms) through the injected `schedule`, re-checks `enabled` and the limit when a delayed cue fires, and draws variation from its own `Random(seed)`. A volume of 0 emits nothing.

Chat A does not hook it into `GameController`.

---

## 6. Palettes and theme mode

- **Palettes:** `PaletteId.classic`, `PaletteId.slate`, `PaletteId.highContrast`. Each has a light and a dark `LudoPalette` (the table: background, board, cells, felt, wood frame, seat colours) and a Material `ColorScheme` seed for the screens that use Material widgets (Home, Setup, Saved Games, Settings, menu).
  - **Classic** is today's look (warm linen felt, wooden frame, red / green / yellow / blue).
  - **Slate** is a cool, quieter look: blue-grey felt and a darker frame, seat colours slightly desaturated.
  - **High Contrast** has strong value contrast between board, cells, lines and tokens, black or white text, saturated seat colours, and shape cues that do not rely on colour alone where the painters allow it. Target: WCAG AA contrast (4.5:1) for text and 3:1 for the board lines and token outlines.
  - Hex values are settled in chat C, not here.
- **Theme mode:** `ThemeMode.system` (default), `light`, `dark`. The app's `MaterialApp` uses `themeMode`; the table picks the light or dark `LudoPalette` of the chosen palette from the effective brightness.
- **Presentation only:** theme mode and palette live in `GameSettings` and `shared_preferences`. No change in the save format, the engine, the storage or the AI. A replay or a resumed game looks the way the settings say now, not the way it looked when it was played.

---

## 7. Settings keys and defaults

`GameSettings` (app) and `SettingsStore` keys (`shared_preferences`):

| Field | Key | Type | Default |
|---|---|---|---|
| `haptics` | `settings.haptics` | bool | `true` (existing) |
| `reduceMotion` | `settings.reduceMotion` | enum name | `system` (existing) |
| `orientation` | `settings.orientation` | enum name | `table` (existing) |
| `autoRotateShared` | `settings.autoRotateShared` | bool | `true` (existing) |
| `frameOverlay` | `settings.frameOverlay` | bool | `false` (existing) |
| `sfxEnabled` | `settings.sfxEnabled` | bool | `true` |
| `sfxVolume` | `settings.sfxVolume` | double `0..1` | `0.8` |
| `musicEnabled` | `settings.musicEnabled` | bool | `false` |
| `musicVolume` | `settings.musicVolume` | double `0..1` | `0.4` |
| `themeMode` | `settings.themeMode` | `ThemeMode` name | `system` |
| `paletteId` | `settings.paletteId` | `PaletteId` name | `classic` |

Loading is tolerant: a missing, mistyped or unknown value (a bool where a string is expected, a volume outside `0..1`, NaN, an unknown palette name) falls back to the default of that one field and keeps the good ones. A volume that is a number but out of range is clamped rather than dropped; one that is not a finite number falls back to the default. The setters clamp a number into range and ignore a value that is not finite (NaN, infinity), keeping the current one.

---

## 8. Settings screen and menu

- **Shared panel** (`SettingsPanel`, `app/lib/ui/settings/settings_panel.dart`): the rows that used to live inside the menu page (Haptics, Reduce motion, UI orientation, Auto-rotate menu to active seat, Frame timing overlay), unchanged, as a scrollable list bound to a `GameSettings`. Chat B adds the Sound rows and chat C the Look rows to this one panel, so both entry points get them.
- **`SettingsScreen`** (`app/lib/ui/settings/settings_screen.dart`): a normal route with an app bar and the panel. Home has a gear button (key `home-settings`) that opens it.
- **In-game menu:** the Settings entry shows the same panel inside the turned menu card, with its own back arrow.
- **Menu entries now:** New game, Players & rules (when available), Settings, Close. No Rules item.
- Orientation rows that make no sense outside a game (auto-rotate of the shared menu) stay as they are; they are harmless on Home.

---

## 9. Chat plan

- **Chat A (done with this doc):** this doc; settings model and store; shared panel, `SettingsScreen` and the Home gear; the Rules item removed; `lib/ui/core/sfx.dart` and tests; status pointers. No plugin, no assets.
- **Chat B (sound):**
  1. The synthesis script and the generated assets (<= 600 KB), a test or CI check of the size cap, `pubspec.yaml` asset entries.
  2. `flutter_soloud` as the only new dependency; an `AudioService` in `app/lib/audio/` that binds `SfxPlayer` to the engine (lazy init, silent failures, no audio focus), plus a music voice with 400 ms fades.
  3. Hook the player into the haptic call sites (one place that plays haptic and sound together), the `hop` call site, replay speed gating, music on the table and the replay screen only, lifecycle pause.
  4. Sound rows in the shared panel (Sound effects on/off and volume, Music on/off and volume); widget and unit tests with a fake backend.
- **Chat C (look, polish, PR):**
  1. Settle the palette hex values and write them into section 6.
  2. `PaletteId` palettes (light and dark), theme mode wired into `MaterialApp`, the table painters reading the chosen palette, `ColorScheme` per palette.
  3. Look rows in the shared panel (Theme mode, Palette with a small preview).
  4. Polish, update this doc, run the device review, then open the PR to main after it.

Each chat starts by reading `CLAUDE.md` and this file; no re-planning.

---

## 10. Device checklist (stubs)

Chat A (settings and menu, no sound yet):

1. Home shows a gear button; it opens Settings; every existing row works; Back returns to Home.
2. Changing a setting on Home, then starting a game, applies it in the game.
3. In a game the menu has New game, Players & rules, Settings, Close, and no Rules item; Settings shows the same rows.
4. Banked rolls can still be switched in Players & rules.
5. Settings persist across a full restart (force stop and reopen).

Chat B (to fill in): effects audible on every event of section 2; volume slider live; effects off is silent; music off by default, fades in and out at 400 ms, plays on the table and in a replay only, pauses in the background; replay at 2x and 4x is silent for effects; other apps' audio is not interrupted; airplane or silent mode behaves; airplane of a missing audio device does not crash.

Chat C (to fill in): each palette in light and dark on the table, the menu and the screens; theme mode System follows the phone; High Contrast legibility check outdoors; nothing in a saved game or replay changes with the look.
