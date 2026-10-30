import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo/storage/storage.dart';

import 'package:ludo_app/ui/home/home_screen.dart';

import 'save_fixtures.dart';

Future<void> _pump(
  WidgetTester tester,
  SaveLibrary library, {
  Future<void> Function()? onPlay,
  Future<void> Function(GameSave save)? onContinue,
  Future<void> Function()? onSavedGames,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: HomeScreen(
        library: library,
        onPlay: onPlay ?? () async {},
        onContinue: onContinue ?? (_) async {},
        onSavedGames: onSavedGames ?? () async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _continue = find.byKey(const ValueKey('home-continue'));

void main() {
  late InMemorySaveStore store;
  late SaveLibrary library;
  setUp(() {
    store = InMemorySaveStore();
    library = SaveLibrary(store);
  });

  testWidgets('Continue is hidden when there is nothing to continue',
      (tester) async {
    await _pump(tester, library);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Saved Games'), findsOneWidget);
    expect(_continue, findsNothing);
  });

  testWidgets('Continue is hidden when every save is finished', (tester) async {
    await store.put(playSave(id: 'done', at: day, toEnd: true));
    await _pump(tester, library);
    expect(_continue, findsNothing);
  });

  testWidgets('Continue shows the most recent unfinished game', (tester) async {
    await store.put(playSave(id: 'old', at: day, name: 'Old one'));
    await store.put(playSave(
      id: 'new',
      at: day.add(const Duration(hours: 1)),
      name: 'Newest',
    ));
    await store.put(playSave(
      id: 'done',
      at: day.add(const Duration(hours: 2)),
      toEnd: true,
      name: 'Finished',
    ));
    GameSave? opened;
    await _pump(tester, library, onContinue: (s) async => opened = s);
    expect(_continue, findsOneWidget);
    expect(find.text('Newest'), findsOneWidget);

    await tester.tap(_continue);
    await tester.pumpAndSettle();
    expect(opened?.id, 'new');
  });

  testWidgets('Continue skips a newer save that cannot be replayed',
      (tester) async {
    await store.put(playSave(id: 'good', at: day, name: 'Good'));
    await store.put(withBrokenCheck(playSave(
      id: 'bad',
      at: day.add(const Duration(hours: 1)),
      name: 'Broken',
    )));
    await _pump(tester, library);
    expect(find.text('Good'), findsOneWidget);
    expect(find.text('Broken'), findsNothing);
  });

  testWidgets('the buttons open Play and Saved Games', (tester) async {
    var plays = 0;
    var lists = 0;
    await _pump(
      tester,
      library,
      onPlay: () async => plays++,
      onSavedGames: () async => lists++,
    );
    await tester.tap(find.byKey(const ValueKey('home-play')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-saved')));
    await tester.pumpAndSettle();
    expect((plays, lists), (1, 1));
  });

  testWidgets('coming back refreshes Continue', (tester) async {
    await _pump(
      tester,
      library,
      onPlay: () async {
        await store.put(playSave(id: 'made', at: day, name: 'Just played'));
      },
    );
    expect(_continue, findsNothing);
    await tester.tap(find.byKey(const ValueKey('home-play')));
    await tester.pumpAndSettle();
    expect(_continue, findsOneWidget);
    expect(find.text('Just played'), findsOneWidget);
  });
}
