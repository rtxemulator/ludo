# Ludo Sound, Themes & Settings (Milestone 6)

Design of the sound effects, the music, the palettes, the theme mode and the settings screen. Chat A lays the foundations (this doc, the settings model, the shared settings panel, the pure sound core) and adds no audio plugin; chat B builds the audio (assets and `flutter_soloud`); chat C builds the look (palettes) and finishes the milestone.

Related: [[ludo-roadmap]] (milestone 6), [[ludo-ui-ux]] (section 7 effects, section 8 menu and settings, section 9 haptics), [[ludo-saves]] (settings persistence, replay viewer), [[ludo-blueprint]] (section 10, audio architecture).

---

## 1. Decisions (approved)

- **Assets.** Sounds are synthesized by a committed script into Ogg Opus, at most 600 KB in total (chat B). The script is the source of truth; the `.opus` files are build output that is committed with it.
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
- **Generator (built in chat B):** `tool/audio/generate.py`, plain Python 3 with the standard library (`wave`, `math`, `random`, `array`) plus the `opusenc` command line encoder (`pkg install -y opus-tools` in Termux). Every sound is synthesized from oscillators, noise and envelopes; every random draw uses a fixed seed (`zlib.crc32` of the sound's name, a constant for the music) and `opusenc` gets a fixed serial, so the same script gives the same audio. No samples from anywhere, so nothing to license (blueprint section 10).
- **Location:** `app/assets/audio/<SfxEvent name>.opus` for the ten effects and `music.opus`, registered as the `assets/audio/` folder in `app/pubspec.yaml`. Only audio is added there; there are still no raster assets. The file name is `sfxAssetFile(event)` in `sfx.dart`.
- **Levels:** every effect is normalised to the same perceived loudness (about -16 LUFS integrated for the short ones, peak below -1 dBFS), so the 80 % default is comfortable and one volume slider is enough. Music is about 6 dB below the effects at the same slider value.
- **Music:** one seamless ambient loop of 60 to 120 s, soft, no percussion that fights the dice sounds. Built: 60 s, stereo, 64 kbps constrained VBR (plain VBR overshot to 645 KB); four chords (Cmaj7, Am, Fmaj7, G6/9) crossfading in a circle, every oscillator with a whole number of cycles per loop, a few soft pentatonic bell notes wrapping around the end, so the loop is seamless before encoding. `AudioService` plays it at `musicGainBelowEffects` (0.5, -6 dB) times the slider, because the file itself is normalised like an effect.

### Generator usage and what it made

```
python3 tool/audio/generate.py                       # everything (music takes about 2 min on a phone)
python3 tool/audio/generate.py --only capture        # one effect, or "music"
python3 tool/audio/generate.py --keep-wav DIR        # keep the WAV files
python3 tool/audio/generate.py --out DIR             # another output folder
```

It prints one line per file (duration, size, LUFS, peak) and the total. Loudness is measured with ITU-R BS.1770 K-weighting; an effect is measured over its sound only (10 ms blocks within 30 dB of the loudest), the music over the whole loop; a soft limiter keeps peaks under -1 dBFS.

| File | Duration | Size |
|---|---|---|
| `diceRoll.opus` | 470 ms (three knocks at 0, 230, 380 ms) | 3,587 B |
| `diceSettle.opus` | 100 ms | 2,033 B |
| `hop.opus` | 70 ms | 1,683 B |
| `land.opus` | 120 ms | 1,934 B |
| `capture.opus` | 350 ms | 3,028 B |
| `home.opus` | 520 ms | 5,357 B |
| `six.opus` | 260 ms | 3,655 B |
| `win.opus` | 1,800 ms | 15,650 B |
| `illegal.opus` | 160 ms | 2,574 B |
| `select.opus` | 40 ms | 1,109 B |
| `music.opus` | 60 s stereo | 488,811 B |
| **Total** | | **529,421 B (517 KB of 600 KB)** |

`test/audio/audio_assets_test.dart` (pure Dart, runs in the engine CI job) keeps it honest: every `SfxEvent` has a file, the folder holds nothing else, the total stays under 600 KB, each file is Ogg Opus with the right channel count and a length inside the window of section 2, the music is 60 to 120 s, and `pubspec.yaml` registers the folder.

### Package

`flutter_soloud` **5.2.2**, pinned exactly (Dart >= 3.11, Flutter >= 3.41). CI uses the stable Flutter channel unpinned; its last run resolved to Flutter 3.47.9. 5.2.2 is the latest release and the SDK constraint is met. It plays Ogg Opus through prebuilt Xiph libraries fetched by its native build hook; a CI failure in that native build would be a stop-and-report case (no other package is a fallback).

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

**As built (`app/lib/audio/`):**

- `AudioBackend` is the small abstract engine (`init`, `loadEffect`, `loadMusic`, `playEffect(volume, rate)`, `startMusic`, `setMusicVolume`, `pauseMusic`, `dispose`). `SoloudBackend` is the only file that imports `flutter_soloud`, and only `main.dart` imports it, so no test loads the plugin; tests use `FakeAudioBackend` and `FakeAudioClock` (`app/test/fakes/fake_audio.dart`).
- `AudioService` owns the `SfxPlayer` (its `emit` goes to `playEffect`) and the music voice. Effects are decoded into memory once at `start()`; the music streams from disk (`LoadMode.disk`) and is protected from voice stealing. `start()` is called from a post-frame callback in `LudoApp`. Any exception turns the service off for the session (`debugPrint`, backend disposed once). `bind(GameSettings)` applies the four sound settings now and on every change; `LudoApp`, `GameScreen` and `ReplayScreen` all bind (idempotent).
- Music is state, not an event: `enterMusicScreen()` / `leaveMusicScreen()` count the screens that want it (the replay opened over the table makes it 2, so the track keeps playing); it plays when ready, enabled, a screen is up and the app is `resumed`. A request made before the engine is ready is remembered and starts when it is (effects are dropped, not remembered). The fade is `MusicFade` (`lib/ui/core/music_fade.dart`, pure): linear, 400 ms for a full swing, a partial swing takes proportionally less. Leaving `resumed` pauses at once without a fade and drops delayed cues; returning fades in from silence. The music pauses (keeps its place) after a fade-out, so the next screen continues the track.
- `GameFeedback` (`game_feedback.dart`) is the one place that plays haptic and sound together: `feedback.play(HapticEvent.x)` is unchanged at all call sites, so timing is unchanged; `feedback.sound(SfxEvent.hop)` is the hop. `feedback.enabled` stays the haptics switch. `soundMuted` is the replay gate (setting it drops delayed cues); `ReplayController.speed` sets it (`!= 1` mutes); `replayShow` (scrub, jump, step back) cancels delayed cues and plays nothing.
- Hops: `MoveAnimationPlan.hopTimesMs` (pure, from `hopSoundTimesMs`) lists one take-off time per hop step (`hopStepMs` 130 ms; a yard exit is one hop of `yardExitMs`; none with reduced motion); `GameController.tick` fires them.
- A test scans `app/lib/audio/` for `rngState` and `Dice`.

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

- **Shared panel** (`SettingsPanel`, `app/lib/ui/settings/settings_panel.dart`): the rows that used to live inside the menu page (Haptics, Reduce motion, UI orientation, Auto-rotate menu to active seat, Frame timing overlay), as a scrollable list bound to a `GameSettings`. Chat B added a **Sound** section (header, Sound effects switch and slider, Music switch and slider; keys `sfx-switch`, `sfx-volume`, `music-switch`, `music-volume`) between Auto-rotate and Frame timing overlay; a slider is greyed out while its switch is off, and changes apply live through `AudioService.bind` and persist through `SettingsStore`. Chat C adds the Look rows to this one panel, so both entry points get them.
- **`SettingsScreen`** (`app/lib/ui/settings/settings_screen.dart`): a normal route with an app bar and the panel. Home has a gear button (key `home-settings`) that opens it.
- **In-game menu:** the Settings entry shows the same panel inside the turned menu card, with its own back arrow.
- **Menu entries now:** New game, Players & rules (when available), Settings, Close. No Rules item.
- Orientation rows that make no sense outside a game (auto-rotate of the shared menu) stay as they are; they are harmless on Home.

---

## 9. Chat plan

- **Chat A (done with this doc):** this doc; settings model and store; shared panel, `SettingsScreen` and the Home gear; the Rules item removed; `lib/ui/core/sfx.dart` and tests; status pointers. No plugin, no assets.
- **Chat B (sound), done:**
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

Chat B (sound). Use the release or profile APK from CI; effects volume 80 %, music volume 40 % (defaults) unless a step says otherwise.

1. Cold start feels the same as before (the audio engine starts after the first frame). Home is silent.
2. Start a game with sound effects on. Each event is audible and fits the moment: dice roll (three knocks on the three bounces), dice settle click, a hop per square (a run of soft plucks, one per step; a yard exit is one hop), landing, capture (heavier knock and a sweep), reaching home (three rising bells), a six (two-note chime just after the settle), win (short fanfare), illegal tap and "no move" (low double tick), roll-tray chip select (tiny tick). Haptics still fire exactly where they did.
3. Dice and hop sounds line up with what you see (no obvious lag); note how late the first sound feels after a tap.
4. Settings, Sound effects volume slider while playing: the next sound follows it. Sound effects off: silence (haptics unaffected). Back on: sounds return.
5. Music is off by default. Switch it on in Settings (from Home): nothing plays on Home or Settings. Start a game: music fades in over about 0.4 s. It is clearly quieter than the effects at equal sliders.
6. Music slider moves the volume live. Music off in the in-game menu: it fades out and stops; on again: it fades in.
7. Game menu, New game, Players & rules, Saved Games, Setup, Home: the music fades out when the table is left and is silent on those screens.
8. Game over, Watch replay: the music keeps playing without a restart; leave the replay back to the table: still playing; leave the table to Home: it fades out.
9. Home button or app switcher: the music pauses at once. Come back: it fades in again. No effect "ghost" plays after coming back.
10. Replay at 1x plays the effects; 2x and 4x are silent for effects; dragging the scrubber, Jump to start or end and Step back are silent. The music is unaffected by the speed.
11. Listen to the music loop for a minute or two (it is 60 s): the seam where it starts again should not click or jump.
12. Other apps: start music or a podcast in another app, then open Ludo and play with the music off: the other audio is not interrupted or ducked by effects. Notification volume or silent mode behaves like any media app (media volume controls it).
13. Replay in the background or screen off does not keep playing sound.
14. Airplane mode and a Bluetooth headset connecting or disconnecting mid-game do not crash; if audio breaks, the game goes on silent.
15. Settings persist across a full restart (switches and both volumes).

Chat C (to fill in): each palette in light and dark on the table, the menu and the screens; theme mode System follows the phone; High Contrast legibility check outdoors; nothing in a saved game or replay changes with the look.
