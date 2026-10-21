import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo/seats/seats.dart';

import 'package:ludo_app/settings/game_settings.dart';
import 'package:ludo_app/ui/screens/game_screen.dart';
import 'package:ludo_app/ui/setup/seat_map.dart';
import 'package:ludo_app/ui/setup/setup_screen.dart';
import 'package:ludo_app/ui/theme/palette.dart';

Finder inKey(String key, Finder matching) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: matching);

Future<void> tall(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(480, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  Future<MatchSetup?> playFrom(
    WidgetTester tester, {
    MatchSetup? initial,
    Future<void> Function()? edit,
  }) async {
    await tall(tester);
    MatchSetup? played;
    await tester.pumpWidget(
      MaterialApp(
        home: SetupScreen(
          initial: initial,
          onPlay: (_, setup) => played = setup,
        ),
      ),
    );
    await edit?.call();
    await tester.tap(find.byKey(const ValueKey('play')));
    await tester.pump();
    return played;
  }

  testWidgets('starts with four human seats and the classic rules',
      (tester) async {
    final played = await playFrom(tester);
    expect(played, isNotNull);
    expect(played!.activeSeats, [0, 1, 2, 3]);
    expect(played.activeSeats.every((s) => played.configOf(s).isHuman), isTrue);
    expect(played.preset, RulesPreset.classic);
    expect(played.isTeamPlay, isFalse);
  });

  testWidgets('the player count shows and hides the seat tiles',
      (tester) async {
    await tall(tester);
    await tester.pumpWidget(
      MaterialApp(home: SetupScreen(onPlay: (_, __) {})),
    );
    for (var seat = 0; seat < 4; seat++) {
      expect(find.byKey(ValueKey('seat-$seat')), findsOneWidget);
    }

    await tester.tap(inKey('player-count', find.text('2')));
    await tester.pump();
    expect(find.byKey(const ValueKey('seat-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('seat-1')), findsNothing);
    expect(find.byKey(const ValueKey('seat-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('seat-3')), findsNothing);
    // No team choice below four players.
    expect(find.byKey(const ValueKey('team-mode')), findsNothing);

    await tester.tap(inKey('player-count', find.text('3')));
    await tester.pump();
    expect(find.byKey(const ValueKey('seat-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('seat-3')), findsNothing);
  });

  testWidgets('two players hand a two-seat setup to Play', (tester) async {
    final played = await playFrom(
      tester,
      edit: () async {
        await tester.tap(inKey('player-count', find.text('2')));
        await tester.pump();
      },
    );
    expect(played!.activeSeats, [0, 2]);
  });

  testWidgets('a seat can be switched to AI', (tester) async {
    final played = await playFrom(
      tester,
      edit: () async {
        await tester.tap(inKey('seat-2', find.text('AI')));
        await tester.pump();
      },
    );
    expect(played!.typeOf(2), SeatType.ai);
    expect(played.typeOf(0), SeatType.human);
  });

  testWidgets('the online seat type is not selectable yet', (tester) async {
    final played = await playFrom(
      tester,
      edit: () async {
        await tester.tap(inKey('seat-1', find.text('Online')));
        await tester.pump();
      },
    );
    expect(played!.typeOf(1), SeatType.human);
  });

  testWidgets('teams are offered with four players and show the team names',
      (tester) async {
    final played = await playFrom(
      tester,
      edit: () async {
        await tester.tap(find.text('Teams 2v2'));
        await tester.pump();
        expect(find.text('Team A'), findsWidgets);
        expect(find.text('Team B'), findsWidgets);
      },
    );
    expect(played!.isTeamPlay, isTrue);
    expect(played.rules.teamsEnabled, isTrue);
  });

  testWidgets('going down to three players leaves team play', (tester) async {
    final played = await playFrom(
      tester,
      edit: () async {
        await tester.tap(find.text('Teams 2v2'));
        await tester.pump();
        await tester.tap(inKey('player-count', find.text('3')));
        await tester.pump();
        expect(find.byKey(const ValueKey('team-mode')), findsNothing);
      },
    );
    expect(played!.isTeamPlay, isFalse);
    expect(played.activeSeats, [0, 1, 2]);
  });

  testWidgets('presets, banked rolls and house rules edit the rules',
      (tester) async {
    final played = await playFrom(
      tester,
      edit: () async {
        await tester.tap(find.byKey(const ValueKey('preset-quick')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('rule-banked')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('house-rules')));
        // One frame to start the expansion, one long frame to finish it.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Blockades'));
        await tester.pump();
      },
    );
    final rules = played!.rules;
    expect(rules.needSixToLeave, isFalse);
    expect(rules.bankedRolls, isTrue);
    expect(rules.blockades, isTrue);
    // A quick game plus blockades is no preset any more.
    expect(played.preset, RulesPreset.custom);
  });

  testWidgets('every edit is reported through onChanged', (tester) async {
    await tall(tester);
    final seen = <MatchSetup>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SetupScreen(onChanged: seen.add, onPlay: (_, __) {}),
      ),
    );
    await tester.tap(inKey('player-count', find.text('2')));
    await tester.pump();
    expect(seen.single.playerCount, 2);
  });

  testWidgets('a setup that cannot be played disables Play and says why',
      (tester) async {
    await tall(tester);
    final setup = MatchSetup.hotSeat(players: 2)
        .withSeat(2, const SeatConfig(type: SeatType.remote));
    await tester.pumpWidget(
      MaterialApp(home: SetupScreen(initial: setup, onPlay: (_, __) {})),
    );
    expect(find.text('Online seats are not available yet.'), findsOneWidget);
    final play =
        tester.widget<FilledButton>(find.byKey(const ValueKey('play')));
    expect(play.onPressed, isNull);
  });

  testWidgets('the seat map fills the seats that play', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SeatMap(
            setup: MatchSetup.hotSeat(players: 2)
                .withSeat(2, const SeatConfig.ai()),
            palette: LudoPalette.light,
          ),
        ),
      ),
    );
    expect(find.text('Human'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
    expect(find.byKey(const ValueKey('map-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('map-3')), findsOneWidget);
  });

  testWidgets('Play opens the table for those seats; the menu returns',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = GameSettings(haptics: false);
    await tester.pumpWidget(
      MaterialApp(
        home: SetupScreen(
          onPlay: (context, setup) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => GameScreen(setup: setup, settings: settings),
            ),
          ),
        ),
      ),
    );
    await tester.tap(inKey('player-count', find.text('2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('play')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const ValueKey('dock-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('dock-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('dock-1')), findsNothing);
    expect(find.byKey(const ValueKey('dock-3')), findsNothing);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Players & rules'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const ValueKey('play')), findsOneWidget);
    expect(find.byKey(const ValueKey('dock-0')), findsNothing);
    expect(tester.takeException(), isNull);
    settings.dispose();
  });
}
