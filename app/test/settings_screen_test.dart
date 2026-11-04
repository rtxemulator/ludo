import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo/storage/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ludo_app/main.dart';
import 'package:ludo_app/settings/game_settings.dart';
import 'package:ludo_app/settings/settings_store.dart';
import 'package:ludo_app/ui/settings/settings_panel.dart';
import 'package:ludo_app/ui/settings/settings_screen.dart';

final _gear = find.byKey(const ValueKey('home-settings'));

Future<SettingsStore> _openStore(WidgetTester tester) async {
  return (await tester.runAsync(SettingsStore.open))!;
}

/// Lets the fire-and-forget settings save finish (real time, not fake).
Future<void> _flushSaves(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
}

void main() {
  group('SettingsScreen', () {
    testWidgets('shows the settings rows under an app bar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(settings: GameSettings())),
      );
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.byType(SettingsPanel), findsOneWidget);
      for (final row in [
        'Haptics',
        'Reduce motion',
        'UI orientation',
        'Auto-rotate menu to active seat',
        'Sound effects',
        'Music',
        'Frame timing overlay',
      ]) {
        expect(find.text(row), findsOneWidget, reason: row);
      }
    });

    testWidgets('rows change the model', (tester) async {
      final settings = GameSettings();
      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(settings: settings)),
      );

      await tester.tap(find.byType(Switch).first); // Haptics
      await tester.pump();
      expect(settings.haptics, isFalse);

      await tester.tap(find.text('Fixed'));
      await tester.pump();
      expect(settings.orientation, UiOrientation.fixed);

      await tester.tap(find.text('On'));
      await tester.pump();
      expect(settings.reduceMotion, ReduceMotion.on);

      // Fixed orientation disables the auto-rotate row and says why.
      expect(find.text('Table orientation only'), findsOneWidget);
    });

    testWidgets('rows follow the model when it changes elsewhere',
        (tester) async {
      final settings = GameSettings();
      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(settings: settings)),
      );
      expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);

      settings.haptics = false;
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
    });
  });

  group('from Home', () {
    testWidgets('the gear opens Settings and Back returns to Home',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        LudoApp(library: SaveLibrary(InMemorySaveStore())),
      );
      await tester.pumpAndSettle();
      expect(find.text('Play'), findsOneWidget);

      await tester.tap(_gear);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('Haptics'), findsOneWidget);
      expect(find.text('Play'), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.text('Play'), findsOneWidget);
    });

    testWidgets('a change made on Home survives a restart', (tester) async {
      SharedPreferences.setMockInitialValues({});
      var store = await _openStore(tester);
      await tester.pumpWidget(
        LudoApp(
            library: SaveLibrary(InMemorySaveStore()), settingsStore: store),
      );
      await tester.pumpAndSettle();
      await tester.tap(_gear);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);

      await tester.tap(find.byType(Switch).first); // Haptics off
      await tester.pump();
      await tester.tap(find.text('Fixed'));
      await tester.pump();
      await _flushSaves(tester);

      // "Restart": drop the whole app and open a new one on the same prefs.
      await tester.pumpWidget(const SizedBox());
      store = await _openStore(tester);
      await tester.pumpWidget(
        LudoApp(
            library: SaveLibrary(InMemorySaveStore()), settingsStore: store),
      );
      await tester.pumpAndSettle();
      await tester.tap(_gear);
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
      final fixed = tester.widget<SegmentedButton<UiOrientation>>(
        find.byType(SegmentedButton<UiOrientation>),
      );
      expect(fixed.selected, {UiOrientation.fixed});
    });
  });
}
