import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo/seats/seats.dart';
import 'package:ludo/storage/storage.dart';

import 'package:ludo_app/ui/home/saved_games_screen.dart';

import 'save_fixtures.dart';

Future<void> _pump(
  WidgetTester tester,
  SaveLibrary library, {
  void Function(GameSave save)? onOpen,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: SavedGamesScreen(
        library: library,
        onOpen: (save) async => onOpen?.call(save),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _row(String id) => find.byKey(ValueKey('save-$id'));

bool _enabled(WidgetTester tester, String id) =>
    tester.widget<ListTile>(_row(id)).enabled;

Future<void> _menu(WidgetTester tester, String id, String item) async {
  await tester.tap(find.byKey(ValueKey('save-menu-$id')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

void main() {
  late InMemorySaveStore store;
  late SaveLibrary library;
  setUp(() {
    store = InMemorySaveStore();
    library = SaveLibrary(store);
  });

  testWidgets('an empty list says so', (tester) async {
    await _pump(tester, library);
    expect(find.byKey(const ValueKey('saved-empty')), findsOneWidget);
  });

  testWidgets('a row shows name, date, seats, turn and state', (tester) async {
    final setup = MatchSetup.hotSeat(players: 2)
        .withSeat(2, const SeatConfig.ai(level: AiLevel.hard));
    final save = playSave(
      id: 'a',
      at: DateTime.utc(2026, 10, 30, 12, 30),
      setup: setup,
      name: 'Friday game',
    );
    await store.put(save);
    await _pump(tester, library);

    expect(find.text('Friday game'), findsOneWidget);
    final subtitle = find.textContaining('2 players: 1 human, 1 AI (Hard)');
    expect(subtitle, findsOneWidget);
    final text = tester.widget<Text>(subtitle).data!;
    expect(text, contains('2026-10-30'));
    expect(text, contains('Turn ${save.summary.turnNumber}'));
    expect(text, contains('In progress'));
    expect(_enabled(tester, 'a'), isTrue);
  });

  testWidgets('newest first', (tester) async {
    await store.put(playSave(id: 'old', at: day, name: 'Older'));
    await store.put(playSave(
      id: 'new',
      at: day.add(const Duration(days: 1)),
      name: 'Newer',
    ));
    await _pump(tester, library);
    expect(
      tester.getTopLeft(find.text('Newer')).dy,
      lessThan(tester.getTopLeft(find.text('Older')).dy),
    );
  });

  testWidgets('tapping an unfinished game resumes it', (tester) async {
    await store.put(playSave(id: 'a', at: day, name: 'Mine'));
    GameSave? opened;
    await _pump(tester, library, onOpen: (s) => opened = s);
    await tester.tap(_row('a'));
    await tester.pumpAndSettle();
    expect(opened?.id, 'a');
    expect(opened?.name, 'Mine');
  });

  testWidgets('a finished game is disabled and does nothing when tapped',
      (tester) async {
    await store.put(playSave(id: 'done', at: day, toEnd: true, name: 'Won'));
    GameSave? opened;
    await _pump(tester, library, onOpen: (s) => opened = s);
    expect(find.textContaining('Finished'), findsOneWidget);
    expect(_enabled(tester, 'done'), isFalse);
    await tester.tap(_row('done'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(opened, isNull);
  });

  testWidgets('a save that fails its replay is greyed out after the check',
      (tester) async {
    await store.put(playSave(id: 'good', at: day, name: 'Good'));
    await store.put(withBrokenCheck(playSave(
      id: 'bad',
      at: day.add(const Duration(hours: 1)),
      name: 'Broken',
    )));
    GameSave? opened;
    await _pump(tester, library, onOpen: (s) => opened = s);

    expect(_enabled(tester, 'good'), isTrue);
    expect(_enabled(tester, 'bad'), isFalse);
    expect(find.textContaining("Can't open"), findsOneWidget);
    await tester.tap(_row('bad'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(opened, isNull);
  });

  testWidgets('an unreadable row is greyed and can still be deleted',
      (tester) async {
    store.putRaw('junk', '{{{', name: 'Junk', updatedAt: day);
    await _pump(tester, library);
    expect(_enabled(tester, 'junk'), isFalse);
    expect(find.textContaining("Can't open"), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('save-menu-junk')));
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsNothing);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-confirm')));
    await tester.pumpAndSettle();
    expect(_row('junk'), findsNothing);
    expect(await store.list(), isEmpty);
  });

  testWidgets('rename changes the name', (tester) async {
    await store.put(playSave(id: 'a', at: day, name: 'Before'));
    await _pump(tester, library);

    await _menu(tester, 'a', 'Rename');
    await tester.enterText(
        find.byKey(const ValueKey('rename-field')), 'After that');
    await tester.tap(find.byKey(const ValueKey('rename-save')));
    await tester.pumpAndSettle();

    expect(find.text('After that'), findsOneWidget);
    expect(find.text('Before'), findsNothing);
    expect((await store.list()).single.name, 'After that');
  });

  testWidgets('a blank rename is refused and keeps the name', (tester) async {
    await store.put(playSave(id: 'a', at: day, name: 'Keep me'));
    await _pump(tester, library);
    await _menu(tester, 'a', 'Rename');
    await tester.enterText(find.byKey(const ValueKey('rename-field')), '   ');
    await tester.tap(find.byKey(const ValueKey('rename-save')));
    await tester.pumpAndSettle();
    expect(find.text('Keep me'), findsOneWidget);
    expect((await store.list()).single.name, 'Keep me');
  });

  testWidgets('delete asks first; cancel keeps the game', (tester) async {
    await store.put(playSave(id: 'a', at: day, name: 'Doomed'));
    await _pump(tester, library);

    await _menu(tester, 'a', 'Delete');
    expect(find.text('Delete this game?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('delete-cancel')));
    await tester.pumpAndSettle();
    expect(_row('a'), findsOneWidget);
    expect(await store.list(), hasLength(1));

    await _menu(tester, 'a', 'Delete');
    await tester.tap(find.byKey(const ValueKey('delete-confirm')));
    await tester.pumpAndSettle();
    expect(_row('a'), findsNothing);
    expect(find.byKey(const ValueKey('saved-empty')), findsOneWidget);
    expect(await store.list(), isEmpty);
  });
}
