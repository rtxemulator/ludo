import 'dart:convert';

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
  void Function(ReplayOpening opening)? onReplay,
  VoidCallback? onNewGame,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: SavedGamesScreen(
        library: library,
        onOpen: (save) async => onOpen?.call(save),
        onReplay: (opening) async => onReplay?.call(opening),
        onNewGame: onNewGame ?? () {},
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

  testWidgets('an empty list says so and offers a new game', (tester) async {
    var newGames = 0;
    await _pump(tester, library, onNewGame: () => newGames++);
    expect(find.byKey(const ValueKey('saved-empty')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('saved-new-game')));
    await tester.pumpAndSettle();
    expect(newGames, 1);
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

  testWidgets('tapping a finished game replays it, it is not resumed',
      (tester) async {
    await store.put(playSave(id: 'done', at: day, toEnd: true, name: 'Won'));
    GameSave? opened;
    ReplayOpening? replayed;
    await _pump(
      tester,
      library,
      onOpen: (s) => opened = s,
      onReplay: (o) => replayed = o,
    );
    expect(find.textContaining('Finished'), findsOneWidget);
    expect(_enabled(tester, 'done'), isTrue);
    expect(find.textContaining('coming soon'), findsNothing);
    await tester.tap(_row('done'));
    await tester.pumpAndSettle();
    expect(opened, isNull);
    expect(replayed?.ok, isTrue);
    expect(replayed?.script?.endsInGameOver, isTrue);
    expect(replayed?.partial, isFalse);
  });

  testWidgets('every openable row has Replay in its menu', (tester) async {
    await store.put(playSave(id: 'live', at: day, name: 'Live'));
    await store.put(playSave(
      id: 'done',
      at: day.add(const Duration(hours: 1)),
      toEnd: true,
      name: 'Done',
    ));
    GameSave? opened;
    final replayed = <String>[];
    await _pump(
      tester,
      library,
      onOpen: (s) => opened = s,
      onReplay: (o) => replayed.add(o.script!.save.id),
    );
    await _menu(tester, 'live', 'Replay');
    await _menu(tester, 'done', 'Replay');
    expect(replayed, ['live', 'done']);
    expect(opened, isNull);
    // Replaying leaves the games as they were.
    final rows = await store.list();
    expect(
      rows.map((r) => r.updatedAt).toSet(),
      {day, day.add(const Duration(hours: 1))},
    );
  });

  testWidgets('a damaged log is greyed but replays up to its last valid move',
      (tester) async {
    final save = playSave(id: 'x', at: day, decisions: 20, name: 'Cut');
    final json = jsonDecode(SaveCodec.encode(save)) as Map<String, Object?>;
    final text = json['log']! as String;
    json['log'] = '${text.substring(0, 14)}zz${text.substring(16)}';
    store.putRaw('x', jsonEncode(json), name: 'Cut', updatedAt: day);
    ReplayOpening? replayed;
    await _pump(tester, library, onReplay: (o) => replayed = o);

    expect(_enabled(tester, 'x'), isFalse);
    expect(find.textContaining('can replay 7 moves'), findsOneWidget);
    await _menu(tester, 'x', 'Replay (partial)');
    expect(replayed?.ok, isTrue);
    expect(replayed?.salvaged, isTrue);
    expect(replayed?.partial, isTrue);
    expect(replayed?.playable, 7);
  });

  testWidgets('a greyed row with nothing to replay has no Replay action',
      (tester) async {
    store.putRaw('junk', '{{{', name: 'Junk', updatedAt: day);
    await store.put(withBrokenCheck(playSave(
      id: 'bad',
      at: day.add(const Duration(hours: 1)),
      name: 'Drifted',
    )));
    await _pump(tester, library);

    for (final id in ['junk', 'bad']) {
      await tester.tap(find.byKey(ValueKey('save-menu-$id')));
      await tester.pumpAndSettle();
      expect(find.text('Replay'), findsNothing);
      expect(find.text('Replay (partial)'), findsNothing);
      expect(find.text('Delete'), findsOneWidget);
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
    }
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
