import 'dart:convert';

import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/seats/seats.dart';
import 'package:test/test.dart';

void main() {
  group('SeatConfig', () {
    test('defaults to a human with the medium AI level and no name', () {
      const c = SeatConfig();
      expect(c.type, SeatType.human);
      expect(c.aiLevel, AiLevel.medium);
      expect(c.name, isNull);
      expect(c.isHuman, isTrue);
      expect(const SeatConfig.ai().isAi, isTrue);
    });

    test('names are trimmed, cut to the limit and cleared when empty', () {
      expect(const SeatConfig().copyWith(name: '  Ana  ').name, 'Ana');
      expect(
        const SeatConfig().copyWith(name: 'x' * 40).name!.length,
        SeatConfig.maxNameLength,
      );
      expect(const SeatConfig(name: 'Ana').copyWith(name: '   ').name, isNull);
      expect(
          const SeatConfig(name: 'Ana').copyWith(clearName: true).name, isNull);
    });

    test('JSON round-trips and tolerates junk', () {
      const c = SeatConfig.ai(level: AiLevel.expert, name: 'Bot');
      expect(SeatConfig.fromJson(c.toJson()), c);
      final junk = SeatConfig.fromJson({'type': 'robot', 'aiLevel': 7});
      expect(junk, const SeatConfig());
    });
  });

  group('MatchSetup layout', () {
    test('2 players sit in opposite corners, 3 in 0..2, 4 everywhere', () {
      expect(MatchSetup.hotSeat(players: 2).activeSeats, [0, 2]);
      expect(MatchSetup.hotSeat(players: 3).activeSeats, [0, 1, 2]);
      expect(MatchSetup.hotSeat(players: 4).activeSeats, [0, 1, 2, 3]);
    });

    test('rejects a player count outside 2..4 and a wrong seat list', () {
      expect(() => MatchSetup.hotSeat(players: 1), throwsArgumentError);
      expect(() => MatchSetup.hotSeat(players: 5), throwsArgumentError);
      expect(() => MatchSetup(seats: const [null, null]), throwsArgumentError);
    });

    test('changing the player count keeps the configs of seats that stay', () {
      var setup = MatchSetup.hotSeat()
          .withSeat(0, const SeatConfig.ai(name: 'Zed'))
          .withSeat(2, const SeatConfig.ai());
      setup = setup.withPlayerCount(2);
      expect(setup.activeSeats, [0, 2]);
      expect(setup.configOf(0).name, 'Zed');
      expect(setup.typeOf(2), SeatType.ai);
      expect(setup.typeOf(1), isNull);

      setup = setup.withPlayerCount(4);
      expect(setup.configOf(0).name, 'Zed');
      expect(setup.typeOf(1), SeatType.human);
    });

    test('an empty seat cannot be edited', () {
      final setup = MatchSetup.hotSeat(players: 2);
      expect(() => setup.configOf(1), throwsStateError);
      expect(
        () => setup.withSeat(1, const SeatConfig.ai()),
        throwsStateError,
      );
    });

    test('display names fall back to the colour', () {
      final setup =
          MatchSetup.hotSeat().withSeat(1, const SeatConfig(name: 'Ana'));
      expect(setup.displayName(0), 'Red');
      expect(setup.displayName(1), 'Ana');
      expect(setup.displayName(3), 'Blue');
    });
  });

  group('MatchSetup teams', () {
    test('team play needs four players', () {
      expect(MatchSetup.hotSeat(players: 3).problems(), isEmpty);
      expect(
        () => MatchSetup.hotSeat(players: 3).withTeams(true),
        throwsStateError,
      );
      final teams = MatchSetup.hotSeat().withTeams(true);
      expect(teams.isTeamPlay, isTrue);
      expect(teams.rules.teamsEnabled, isTrue);
      expect(teams.teamOf(0), teams.teamOf(2));
      expect(teams.teamOf(1), teams.teamOf(3));
      expect(teams.teamOf(0), isNot(teams.teamOf(1)));
    });

    test('dropping to fewer players drops the teams', () {
      final setup = MatchSetup.hotSeat().withTeams(true).withPlayerCount(3);
      expect(setup.teams, isFalse);
      expect(setup.isTeamPlay, isFalse);
      expect(setup.rules.teamsEnabled, isFalse);
      expect(setup.teamOf(1), 1);
    });

    test('teamsEnabled is derived: whatever the caller passes is ignored', () {
      final solo = MatchSetup.hotSeat(
        rules: const RulesConfig(teamsEnabled: true),
      );
      expect(solo.rules.teamsEnabled, isFalse);
      expect(solo.withTeams(true).rules.teamsEnabled, isTrue);
      expect(
        solo.withTeams(true).withRules(const RulesConfig.quick()).isTeamPlay,
        isTrue,
      );
    });

    test('a team setup builds an engine game that scores partners together',
        () {
      final state = MatchSetup.hotSeat().withTeams(true).newGame(5);
      expect(state.rules.teamsEnabled, isTrue);
      expect(state.unitOf(0), state.unitOf(2));
    });
  });

  group('MatchSetup problems', () {
    test('a valid table has none', () {
      expect(MatchSetup.hotSeat().problems(), isEmpty);
    });

    test('fewer than two occupied seats is flagged', () {
      final one = MatchSetup(
        seats: const [SeatConfig(), null, null, null],
      );
      expect(one.problems(), [SetupProblem.tooFewPlayers]);
    });

    test('a stored team flag on a small table is flagged', () {
      final bad = MatchSetup(
        seats: const [SeatConfig(), null, SeatConfig(), null],
        teams: true,
      );
      expect(bad.problems(), [SetupProblem.teamsNeedFourPlayers]);
      expect(bad.isTeamPlay, isFalse);
    });

    test('remote seats are unavailable until online play exists', () {
      final setup = MatchSetup.hotSeat(players: 2)
          .withSeat(2, const SeatConfig(type: SeatType.remote));
      expect(setup.problems(), [SetupProblem.remoteUnavailable]);
      expect(setup.problems(remoteAvailable: true), isEmpty);
    });
  });

  group('MatchSetup to engine', () {
    test('newGame uses the active seats and the rules', () {
      final setup = MatchSetup.hotSeat(
        players: 2,
        rules: const RulesConfig.quick(),
      );
      final state = setup.newGame(11);
      expect(state.activeSeats, [0, 2]);
      expect(state.rules.needSixToLeave, isFalse);
      expect(state.currentSeat, 0);
    });

    test('three players: the turn skips the empty seat', () {
      final state = MatchSetup.hotSeat(players: 3).newGame(3);
      expect(state.activeSeats, [0, 1, 2]);
      var s = state;
      final seen = <int>{};
      for (var i = 0; i < 200 && !s.isOver; i++) {
        s = Engine.nextDecision(s);
        if (s.isOver) {
          break;
        }
        seen.add(s.currentSeat);
        s = Engine.apply(s, Engine.legalMoves(s).first);
      }
      expect(seen.contains(3), isFalse);
      expect(seen, {0, 1, 2});
    });

    test('seed plus move log replays to the same state', () {
      final setup = MatchSetup.hotSeat(players: 2);
      var state = setup.newGame(99);
      final log = <MoveLogEntry>[];
      for (var i = 0; i < 40 && !state.isOver; i++) {
        state = Engine.nextDecision(state);
        if (state.isOver) {
          break;
        }
        final move = Engine.legalMoves(state).last;
        log.add(Engine.logEntry(state, move));
        state = Engine.apply(state, move);
      }
      final replayed = Engine.replay(
        seed: 99,
        log: log,
        rules: setup.rules,
        activeSeats: setup.activeSeats,
      );
      expect(replayed.tokens, state.tokens);
      expect(replayed.rngState, state.rngState);
    });
  });

  group('MatchSetup JSON', () {
    test('round-trips through real JSON text', () {
      final setup = MatchSetup.hotSeat()
          .withTeams(true)
          .withSeat(1, const SeatConfig.ai(level: AiLevel.hard, name: 'Bo'))
          .withRules(const RulesConfig.strategic().copyWith(bankedRolls: true));
      final text = jsonEncode(setup.toJson());
      final back = MatchSetup.fromJson(
        jsonDecode(text) as Map<String, Object?>,
      );
      expect(back, setup);
      expect(back.rules, setup.rules);
    });

    test('empty seats survive the round trip', () {
      final setup = MatchSetup.hotSeat(players: 3);
      final back = MatchSetup.fromJson(
        jsonDecode(jsonEncode(setup.toJson())) as Map<String, Object?>,
      );
      expect(back.activeSeats, [0, 1, 2]);
    });

    test('a damaged save falls back to a four-human table', () {
      final back = MatchSetup.fromJson({'seats': 'nope', 'rules': 3});
      expect(back.activeSeats, [0, 1, 2, 3]);
      expect(back.rules, const RulesConfig());
    });
  });

  group('RulesPreset', () {
    test('recognises the three presets', () {
      expect(RulesPreset.of(const RulesConfig.classic()), RulesPreset.classic);
      expect(RulesPreset.of(const RulesConfig.quick()), RulesPreset.quick);
      expect(
        RulesPreset.of(const RulesConfig.strategic()),
        RulesPreset.strategic,
      );
    });

    test('table options do not make a preset custom', () {
      final rules = const RulesConfig.quick().copyWith(
        bankedRolls: true,
        teammateControl: false,
        teamsEnabled: true,
      );
      expect(RulesPreset.of(rules), RulesPreset.quick);
    });

    test('any other combination is custom', () {
      expect(
        RulesPreset.of(const RulesConfig(blockades: true)),
        RulesPreset.custom,
      );
    });

    test('applying a preset keeps the table options', () {
      const current = RulesConfig(
        bankedRolls: true,
        teammateControl: false,
        teamsEnabled: true,
      );
      final applied = RulesPreset.quick.applyTo(current);
      expect(applied.needSixToLeave, isFalse);
      expect(applied.endMode, EndMode.firstToWin);
      expect(applied.bankedRolls, isTrue);
      expect(applied.teammateControl, isFalse);
      expect(applied.teamsEnabled, isTrue);
    });

    test('a blockade option makes the strategic preset custom', () {
      expect(
        RulesPreset.of(
          const RulesConfig.strategic().copyWith(blockadeSafeSquares: true),
        ),
        RulesPreset.custom,
      );
    });

    test('a setup drops blockade options whose prerequisite is off', () {
      final setup = MatchSetup.hotSeat().withRules(
        const RulesConfig(
          blockades: true,
          blockadeCapture: true,
          pieceOnBlockade: true,
        ),
      );
      expect(setup.rules.blockadeCapture, isFalse);
      expect(setup.rules.pieceOnBlockade, isTrue);
      final noBlockades = setup.withRules(
        setup.baseRules.copyWith(blockades: false),
      );
      expect(noBlockades.rules.pieceOnBlockade, isFalse);
    });

    test('the preset of a setup follows its rules', () {
      final setup = MatchSetup.hotSeat().withRules(const RulesConfig.quick());
      expect(setup.preset, RulesPreset.quick);
    });

    test('rules JSON round-trips every switch', () {
      const rules = RulesConfig(
        endMode: EndMode.firstToWin,
        teammateControl: false,
        needSixToLeave: false,
        extraTurnOnSix: false,
        tripleSixForfeit: false,
        extraTurnOnCapture: false,
        extraTurnOnHome: false,
        exactRollToFinish: false,
        blockades: true,
        teamsEnabled: true,
        bankedRolls: true,
        blockadeSafeSquares: true,
        blockadeFriendlyRestriction: true,
        blockadeMovement: true,
        blockadeCapture: true,
        blockadeUnbreakable: true,
        pieceOnBlockade: true,
      );
      expect(rulesFromJson(rulesToJson(rules)), rules);
      expect(rulesFromJson(const {}), const RulesConfig());
    });
  });
}
