import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo/storage/storage.dart';
import 'package:ludo/ui/core/palette_spec.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ludo_app/game/game_controller.dart';
import 'package:ludo_app/game/replay_controller.dart';
import 'package:ludo_app/main.dart';
import 'package:ludo_app/settings/game_settings.dart';
import 'package:ludo_app/settings/settings_store.dart';
import 'package:ludo_app/ui/board/board_painter.dart';
import 'package:ludo_app/ui/board/token_layer_painter.dart';
import 'package:ludo_app/ui/board/yard_glow_painter.dart';
import 'package:ludo_app/ui/dice/dock_painter.dart';
import 'package:ludo_app/ui/replay/replay_screen.dart';
import 'package:ludo_app/ui/screens/game_screen.dart';
import 'package:ludo_app/ui/settings/settings_panel.dart';
import 'package:ludo_app/ui/settings/settings_screen.dart';
import 'package:ludo_app/ui/setup/seat_map.dart';
import 'package:ludo_app/ui/setup/setup_screen.dart';
import 'package:ludo_app/ui/table/felt_painter.dart';
import 'package:ludo_app/ui/table/overlay_painter.dart';
import 'package:ludo_app/ui/theme/app_theme.dart';
import 'package:ludo_app/ui/theme/palette.dart';
import 'package:ludo_app/ui/theme/token_shaders.dart';

import 'save_fixtures.dart';

final _themeMode = find.byKey(const ValueKey('theme-mode'));
final _gear = find.byKey(const ValueKey('home-settings'));
Finder _tile(PaletteId id) => find.byKey(ValueKey('palette-${id.name}'));

/// The Look rows sit below the Sound rows: a tall phone builds them all.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 1500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The semantics properties of a palette tile (its label names the palette).
SemanticsProperties _tileSemantics(WidgetTester tester, PaletteId id) {
  final label = '${paletteName(id)} palette';
  return tester
      .widget<Semantics>(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == label,
        ),
      )
      .properties;
}

List<T> _painters<T extends CustomPainter>(WidgetTester tester) => [
      for (final c in tester.widgetList<CustomPaint>(find.byType(CustomPaint)))
        if (c.painter is T) c.painter! as T,
    ];

/// The table painters that carry a palette, from the widget tree.
List<LudoPalette> _tablePalettes(WidgetTester tester) => [
      for (final p in _painters<BoardPainter>(tester)) p.palette,
      for (final p in _painters<FeltPainter>(tester)) p.palette,
      for (final p in _painters<YardGlowPainter>(tester)) p.palette,
      for (final p in _painters<TokenLayerPainter>(tester)) p.palette,
      for (final p in _painters<DockPainter>(tester)) p.palette,
      for (final p in _painters<OverlayPainter>(tester)) p.palette,
    ];

Widget _app(Widget home, {ThemeMode mode = ThemeMode.light}) => MaterialApp(
      themeMode: mode,
      theme: ludoTheme(PaletteId.classic, Brightness.light),
      darkTheme: ludoTheme(PaletteId.classic, Brightness.dark),
      home: home,
    );

void main() {
  group('LudoPalette', () {
    test('of() is the spec of that palette and shares its instances', () {
      for (final id in PaletteId.values) {
        for (final b in Brightness.values) {
          final p = LudoPalette.of(id, b);
          final spec = PaletteSpec.of(id, dark: b == Brightness.dark);
          expect(identical(p, LudoPalette.of(id, b)), isTrue);
          expect(p.background, Color(spec.background));
          expect(p.board, Color(spec.board));
          expect(p.cell, Color(spec.cell));
          expect(p.cellLine, Color(spec.cellLine));
          expect(p.text, Color(spec.text));
          expect(p.feltEdge, Color(spec.feltEdge));
          expect(p.woodLight, Color(spec.woodLight));
          expect([for (final c in p.seat) c.toARGB32()], spec.seat);
        }
      }
    });

    test('Classic is the old light and dark', () {
      expect(
        identical(LudoPalette.light,
            LudoPalette.of(PaletteId.classic, Brightness.light)),
        isTrue,
      );
      expect(
        identical(LudoPalette.dark,
            LudoPalette.of(PaletteId.classic, Brightness.dark)),
        isTrue,
      );
      expect(LudoPalette.light.background, const Color(0xFFF3F1EC));
      expect(LudoPalette.dark.board, const Color(0xFF1E1E22));
      expect(LudoPalette.light.seat[2], const Color(0xFFFDD835));
    });

    test('the six palettes are six different instances', () {
      final all = {
        for (final id in PaletteId.values)
          for (final b in Brightness.values) LudoPalette.of(id, b),
      };
      expect(all.length, 6);
    });
  });

  group('ludoTheme', () {
    test('one theme per palette and brightness, built once', () {
      for (final id in PaletteId.values) {
        final light = ludoTheme(id, Brightness.light);
        final dark = ludoTheme(id, Brightness.dark);
        expect(light.colorScheme.brightness, Brightness.light);
        expect(dark.colorScheme.brightness, Brightness.dark);
        expect(identical(light, ludoTheme(id, Brightness.light)), isTrue);
        expect(light.useMaterial3, isTrue);
      }
    });

    test('the palettes give different colour schemes', () {
      final primaries = {
        for (final id in PaletteId.values)
          ludoTheme(id, Brightness.light).colorScheme.primary,
      };
      expect(primaries.length, PaletteId.values.length);
    });
  });

  group('caches follow the palette', () {
    test('TokenShadersCache rebuilds on a palette or brightness change only',
        () {
      final cache = TokenShadersCache();
      final classic = LudoPalette.of(PaletteId.classic, Brightness.light);
      final a = cache.forPalette(classic);
      expect(identical(cache.forPalette(classic), a), isTrue);
      expect(cache.builds, 1);

      final slate = cache.forPalette(
        LudoPalette.of(PaletteId.slate, Brightness.light),
      );
      expect(identical(slate, a), isFalse);
      expect(cache.builds, 2);

      final slateDark = cache.forPalette(
        LudoPalette.of(PaletteId.slate, Brightness.dark),
      );
      expect(identical(slateDark, slate), isFalse);
      expect(cache.builds, 3);
    });

    test('the baked layers repaint when the palette changes, not otherwise',
        () {
      final classic = LudoPalette.of(PaletteId.classic, Brightness.light);
      final slate = LudoPalette.of(PaletteId.slate, Brightness.light);
      final classicDark = LudoPalette.of(PaletteId.classic, Brightness.dark);
      const frame = Rect.fromLTWH(0, 0, 100, 100);

      expect(
        BoardPainter(classic).shouldRepaint(BoardPainter(classic)),
        isFalse,
      );
      expect(BoardPainter(classic).shouldRepaint(BoardPainter(slate)), isTrue);
      expect(
        BoardPainter(classic).shouldRepaint(BoardPainter(classicDark)),
        isTrue,
      );

      expect(
        FeltPainter(palette: classic, frame: frame)
            .shouldRepaint(FeltPainter(palette: classic, frame: frame)),
        isFalse,
      );
      expect(
        FeltPainter(palette: classic, frame: frame)
            .shouldRepaint(FeltPainter(palette: slate, frame: frame)),
        isTrue,
      );
    });

    test('the painters that sample every frame always repaint', () {
      final game = GameController(seed: 3, haptics: false);
      addTearDown(game.dispose);
      final p = LudoPalette.of(PaletteId.classic, Brightness.light);
      final s = TokenShaders(p);
      final a = TokenLayerPainter(game: game, palette: p, shaders: s);
      final b = TokenLayerPainter(game: game, palette: p, shaders: s);
      expect(a.shouldRepaint(b), isTrue);
    });
  });

  group('Look rows', () {
    testWidgets('the panel has a Look section with Theme and Palette',
        (tester) async {
      _tall(tester);
      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(settings: GameSettings())),
      );
      expect(find.text('Look'), findsOneWidget);
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Palette'), findsOneWidget);
      expect(_themeMode, findsOneWidget);
      for (final id in PaletteId.values) {
        expect(_tile(id), findsOneWidget);
        expect(find.text(paletteName(id)), findsOneWidget);
      }
      // Each tile draws a swatch in code (no image).
      expect(_painters<PaletteSwatchPainter>(tester).length, 3);
      // The rows above and below are where they were.
      expect(find.text('Haptics'), findsOneWidget);
      expect(find.text('Frame timing overlay'), findsOneWidget);
    });

    testWidgets('the swatches use each palette in the current brightness',
        (tester) async {
      _tall(tester);
      await tester.pumpWidget(
        MaterialApp(
          themeMode: ThemeMode.dark,
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          home: SettingsScreen(settings: GameSettings()),
        ),
      );
      final palettes = [
        for (final p in _painters<PaletteSwatchPainter>(tester)) p.palette,
      ];
      expect(palettes, [
        for (final id in PaletteId.values) LudoPalette.of(id, Brightness.dark),
      ]);
    });

    testWidgets('Theme and Palette change the model', (tester) async {
      _tall(tester);
      final settings = GameSettings();
      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(settings: settings)),
      );
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.paletteId, PaletteId.classic);

      await tester.tap(
        find.descendant(of: _themeMode, matching: find.text('Dark')),
      );
      await tester.pump();
      expect(settings.themeMode, ThemeMode.dark);
      await tester.tap(
        find.descendant(of: _themeMode, matching: find.text('Light')),
      );
      await tester.pump();
      expect(settings.themeMode, ThemeMode.light);
      await tester.tap(
        find.descendant(of: _themeMode, matching: find.text('System')),
      );
      await tester.pump();
      expect(settings.themeMode, ThemeMode.system);

      await tester.tap(_tile(PaletteId.slate));
      await tester.pump();
      expect(settings.paletteId, PaletteId.slate);
      await tester.tap(_tile(PaletteId.highContrast));
      await tester.pump();
      expect(settings.paletteId, PaletteId.highContrast);
    });

    testWidgets('the rows follow the model and mark the selected palette',
        (tester) async {
      _tall(tester);
      final settings = GameSettings(
        themeMode: ThemeMode.dark,
        paletteId: PaletteId.slate,
      );
      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(settings: settings)),
      );
      SegmentedButton<ThemeMode> seg() =>
          tester.widget<SegmentedButton<ThemeMode>>(_themeMode);
      expect(seg().selected, {ThemeMode.dark});
      expect(_tileSemantics(tester, PaletteId.slate).selected, isTrue);
      expect(_tileSemantics(tester, PaletteId.classic).selected, isFalse);
      expect(_tileSemantics(tester, PaletteId.slate).button, isTrue);

      settings.themeMode = ThemeMode.light;
      settings.paletteId = PaletteId.classic;
      await tester.pump();
      expect(seg().selected, {ThemeMode.light});
      expect(_tileSemantics(tester, PaletteId.classic).selected, isTrue);
      expect(_tileSemantics(tester, PaletteId.slate).selected, isFalse);
    });
  });

  group('live in the app', () {
    testWidgets('Theme mode and palette restyle the app and survive a restart',
        (tester) async {
      _tall(tester);
      SharedPreferences.setMockInitialValues({});
      var store = (await tester.runAsync(SettingsStore.open))!;
      await tester.pumpWidget(
        LudoApp(
          library: SaveLibrary(InMemorySaveStore()),
          settingsStore: store,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(_gear);
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SettingsScreen));
      expect(Theme.of(context).brightness, Brightness.light);
      expect(
        Theme.of(context).colorScheme.primary,
        ludoTheme(PaletteId.classic, Brightness.light).colorScheme.primary,
      );

      await tester.tap(
        find.descendant(of: _themeMode, matching: find.text('Dark')),
      );
      await tester.pumpAndSettle();
      expect(Theme.of(context).brightness, Brightness.dark);

      await tester.tap(_tile(PaletteId.highContrast));
      await tester.pumpAndSettle();
      expect(
        Theme.of(context).colorScheme.primary,
        ludoTheme(PaletteId.highContrast, Brightness.dark).colorScheme.primary,
      );
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );

      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );

      // "Restart" on the same preferences.
      await tester.pumpWidget(const SizedBox());
      store = (await tester.runAsync(SettingsStore.open))!;
      await tester.pumpWidget(
        LudoApp(
          library: SaveLibrary(InMemorySaveStore()),
          settingsStore: store,
        ),
      );
      await tester.pumpAndSettle();
      final home = tester.element(find.text('Play'));
      expect(Theme.of(home).brightness, Brightness.dark);
      expect(
        Theme.of(home).colorScheme.primary,
        ludoTheme(PaletteId.highContrast, Brightness.dark).colorScheme.primary,
      );
      await tester.tap(_gear);
      await tester.pumpAndSettle();
      expect(
        tester.widget<SegmentedButton<ThemeMode>>(_themeMode).selected,
        {ThemeMode.dark},
      );
    });

    testWidgets('the setup screen follows the palette', (tester) async {
      _phone(tester);
      final settings = GameSettings(paletteId: PaletteId.slate);
      await tester.pumpWidget(
        _app(
          SetupScreen(settings: settings, onPlay: (_, __) {}),
        ),
      );
      expect(
        tester.widget<SeatMap>(find.byType(SeatMap)).palette,
        LudoPalette.of(PaletteId.slate, Brightness.light),
      );
      settings.paletteId = PaletteId.highContrast;
      await tester.pump();
      expect(
        tester.widget<SeatMap>(find.byType(SeatMap)).palette,
        LudoPalette.of(PaletteId.highContrast, Brightness.light),
      );
    });
  });

  group('the table repaints live', () {
    testWidgets('a palette change reaches every painter and the shaders',
        (tester) async {
      _phone(tester);
      var t = 0.0;
      final game = GameController(seed: 5, now: () => t, haptics: false);
      final settings = GameSettings(haptics: false);
      await tester.pumpWidget(
        _app(GameScreen(controller: game, settings: settings)),
      );
      final classic = LudoPalette.of(PaletteId.classic, Brightness.light);
      expect(_tablePalettes(tester), isNotEmpty);
      expect(
          _tablePalettes(tester).every((p) => identical(p, classic)), isTrue);
      final shadersBefore = _painters<TokenLayerPainter>(tester).first.shaders;
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        classic.feltEdge,
      );

      settings.paletteId = PaletteId.slate;
      await tester.pump();
      final slate = LudoPalette.of(PaletteId.slate, Brightness.light);
      expect(_tablePalettes(tester).every((p) => identical(p, slate)), isTrue);
      expect(
        identical(
            _painters<TokenLayerPainter>(tester).first.shaders, shadersBefore),
        isFalse,
      );
      // The turn light uses the same new shaders as the tokens.
      expect(
        identical(
          _painters<YardGlowPainter>(tester).first.shaders,
          _painters<TokenLayerPainter>(tester).first.shaders,
        ),
        isTrue,
      );
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        slate.feltEdge,
      );

      // The brightness switch picks the dark variant of the same palette.
      await tester.pumpWidget(
        _app(
          GameScreen(controller: game, settings: settings),
          mode: ThemeMode.dark,
        ),
      );
      // MaterialApp animates the theme change; wait it out.
      await tester.pump(const Duration(milliseconds: 400));
      final slateDark = LudoPalette.of(PaletteId.slate, Brightness.dark);
      expect(
        _tablePalettes(tester).every((p) => identical(p, slateDark)),
        isTrue,
      );

      await tester.pumpWidget(const SizedBox());
      game.dispose();
      settings.dispose();
    });

    testWidgets('the replay table follows the palette too', (tester) async {
      _phone(tester);
      final replay = ReplayController(
        script: ReplayScript.of(playSave(id: 'a', at: day, decisions: 6)),
        clock: () => 0,
        haptics: false,
      );
      final settings = GameSettings(haptics: false);
      await tester.pumpWidget(
        _app(
          ReplayScreen(
            script: replay.script,
            controller: replay,
            settings: settings,
          ),
        ),
      );
      await tester.pump();
      final classic = LudoPalette.of(PaletteId.classic, Brightness.light);
      expect(
          _tablePalettes(tester).every((p) => identical(p, classic)), isTrue);

      settings.paletteId = PaletteId.highContrast;
      await tester.pump();
      final hc = LudoPalette.of(PaletteId.highContrast, Brightness.light);
      expect(_tablePalettes(tester), isNotEmpty);
      expect(_tablePalettes(tester).every((p) => identical(p, hc)), isTrue);

      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    });

    testWidgets('changing the palette in the in-game menu repaints the table',
        (tester) async {
      _phone(tester);
      final game = GameController(seed: 9, haptics: false);
      // Upright, so the card scrolls the way the finger moves.
      final settings = GameSettings(
        haptics: false,
        orientation: UiOrientation.fixed,
      );
      await tester.pumpWidget(
        _app(GameScreen(controller: game, settings: settings)),
      );
      await tester.tap(find.byTooltip('Menu'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Settings'));
      await tester.pump(const Duration(milliseconds: 400));
      // Scroll the Look rows into view inside the small card.
      await tester.scrollUntilVisible(
        _tile(PaletteId.slate),
        200,
        scrollable: find.descendant(
          of: find.byType(SettingsPanel),
          matching: find.byType(Scrollable),
        ),
      );
      // Built is not visible: bring the tile inside the card before tapping.
      await tester.ensureVisible(_tile(PaletteId.slate));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(_tile(PaletteId.slate));
      await tester.pump();
      expect(settings.paletteId, PaletteId.slate);
      final slate = LudoPalette.of(PaletteId.slate, Brightness.light);
      expect(_tablePalettes(tester).every((p) => identical(p, slate)), isTrue);

      await tester.pumpWidget(const SizedBox());
      game.dispose();
      settings.dispose();
    });
  });
}
