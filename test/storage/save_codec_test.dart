import 'dart:convert';
import 'dart:math';

import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/seats/seats.dart';
import 'package:ludo/storage/storage.dart';
import 'package:test/test.dart';

import 'storage_helpers.dart';

Map<String, Object?> _json(GameSave save) =>
    jsonDecode(SaveCodec.encode(save)) as Map<String, Object?>;

SaveProblem? _problem(Object? json) =>
    SaveCodec.fromJson(json).failure?.problem;

void main() {
  final setup = MatchSetup.hotSeat(
    rules: const RulesConfig.strategic().copyWith(bankedRolls: true),
    teams: true,
  ).withSeat(
    2,
    const SeatConfig(type: SeatType.ai, aiLevel: AiLevel.hard, name: 'Robo'),
  );
  final game = play(setup, 424242, Random(9), maxDecisions: 120);
  final save = game.save.withName('Friday night');

  group('round trip', () {
    test('encode then decode gives an equal save', () {
      final decoded = SaveCodec.decode(SaveCodec.encode(save));
      expect(decoded, isA<SaveDecoded>());
      expect(decoded.save, save);
      expect(decoded.failure, isNull);
    });

    test('toJson of the model and the codec agree', () {
      expect(save.toJson(), SaveCodec.toJson(save));
      expect(SaveCodec.fromJson(save.toJson()).save, save);
    });

    test('setup survives: rules, teams, ai level and names', () {
      final back = SaveCodec.decode(SaveCodec.encode(save)).save!;
      expect(back.setup, setup);
      expect(back.setup.rules.bankedRolls, isTrue);
      expect(back.setup.seats[2]!.aiLevel, AiLevel.hard);
      expect(back.setup.seats[2]!.name, 'Robo');
      expect(back.setup.teams, isTrue);
    });

    test('the JSON has the documented shape', () {
      final json = _json(save);
      expect(json['schemaVersion'], 1);
      expect(json['seed'], '424242');
      expect(json['log'], isA<String>());
      expect((json['log'] as String).length, save.log.length * 2);
      expect(json['finished'], isFalse);
      expect(json['summary'], {
        'turn': save.summary.turnNumber,
        'finishOrder': <int>[],
      });
      expect(json['check'], save.check);
      expect(json['createdAt'], save.createdAt.millisecondsSinceEpoch);
    });

    test('negative and 64-bit seeds survive as strings', () {
      for (final seed in [-1, 0, 9223372036854775807, -9223372036854775808]) {
        final s = GameSave.begin(id: 'x', now: t0, setup: setup, seed: seed);
        final back = SaveCodec.decode(SaveCodec.encode(s)).save!;
        expect(back.seed, seed);
      }
    });

    test('a JSON integer seed is accepted too', () {
      final json = _json(save)..['seed'] = 4242;
      expect(SaveCodec.fromJson(json).save!.seed, 4242);
    });

    test('an empty log and a finished flag round-trip', () {
      final empty = GameSave.begin(id: 'e', now: t0, setup: setup, seed: 5);
      expect(SaveCodec.decode(SaveCodec.encode(empty)).save, empty);
      final done = play(MatchSetup.hotSeat(players: 2), 8, Random(2)).save;
      expect(done.finished, isTrue);
      expect(SaveCodec.decode(SaveCodec.encode(done)).save, done);
    });
  });

  group('tolerance', () {
    test('unknown fields are ignored', () {
      final json = _json(save)
        ..['futureThing'] = {'a': 1}
        ..['another'] = [1, 2];
      expect(SaveCodec.fromJson(json).save, save);
    });

    test('a missing or blank name falls back to the auto-name', () {
      final json = _json(save)..remove('name');
      expect(SaveCodec.fromJson(json).save!.name,
          GameSave.autoName(save.createdAt));
      json['name'] = '   ';
      expect(SaveCodec.fromJson(json).save!.name,
          GameSave.autoName(save.createdAt));
      json['name'] = 42;
      expect(SaveCodec.fromJson(json).save!.name,
          GameSave.autoName(save.createdAt));
    });

    test('a missing timestamp takes the other, both missing give the epoch',
        () {
      final json = _json(save)..remove('createdAt');
      final a = SaveCodec.fromJson(json).save!;
      expect(a.createdAt, save.updatedAt);
      expect(a.updatedAt, save.updatedAt);
      final json2 = _json(save)..remove('updatedAt');
      final b = SaveCodec.fromJson(json2).save!;
      expect(b.updatedAt, save.createdAt);
      final json3 = _json(save)
        ..remove('createdAt')
        ..remove('updatedAt');
      final c = SaveCodec.fromJson(json3).save!;
      expect(c.createdAt.millisecondsSinceEpoch, 0);
      expect(c.updatedAt.millisecondsSinceEpoch, 0);
      final json4 = _json(save)
        ..['createdAt'] = 'yesterday'
        ..['updatedAt'] = 1.5;
      expect(
          SaveCodec.fromJson(json4).save!.updatedAt.millisecondsSinceEpoch, 0);
    });

    test('finished, summary and check fall back', () {
      final json = _json(save)
        ..['finished'] = 'yes'
        ..['summary'] = 'nope'
        ..['check'] = 'not-a-hash';
      final back = SaveCodec.fromJson(json).save!;
      expect(back.finished, isFalse);
      expect(back.summary, const SaveSummary());
      expect(back.check, isNull);
      expect(back.log, save.log);
    });

    test('summary entries are filtered', () {
      final json = _json(save)
        ..['summary'] = {
          'turn': -4,
          'finishOrder': [2, 'x', 9, -1, 0, 1.5],
        };
      final back = SaveCodec.fromJson(json).save!;
      expect(back.summary.turnNumber, 0);
      expect(back.summary.finishOrder, [2, 0]);
    });

    test('a missing check means unchecked, the replay still works', () {
      final json = _json(save)..remove('check');
      final back = SaveCodec.fromJson(json).save!;
      expect(back.check, isNull);
      expect(SaveReplayer.replay(back).ok, isTrue);
    });

    test('unknown seat fields fall back like SeatConfig.fromJson', () {
      final json = _json(save);
      final seats = (json['setup'] as Map)['seats'] as List;
      seats[0] = {'type': 'martian', 'aiLevel': 'godlike', 'name': 7};
      final back = SaveCodec.fromJson(json).save!;
      final seat = back.setup.seats[0]!;
      expect(seat.type, SeatType.human);
      expect(seat.aiLevel, AiLevel.medium);
      expect(seat.name, isNull);
    });

    test('a map with non-string keys is read', () {
      final json = Map<Object?, Object?>.from(_json(save));
      expect(SaveCodec.fromJson(json).save, save);
    });
  });

  group('malformed input', () {
    test('text that is not JSON', () {
      for (final text in ['', 'nope', '{', '{"a":', '\u0000', '[1,2', 'ü']) {
        final result = SaveCodec.decode(text);
        expect(result.failure?.problem, SaveProblem.notJson, reason: text);
        expect(result.save, isNull);
      }
    });

    test('JSON that is not an object', () {
      for (final json in <Object?>[null, 1, 2.5, 'x', true, <Object?>[]]) {
        expect(_problem(json), SaveProblem.notAnObject, reason: '$json');
      }
      expect(SaveCodec.decode('[]').failure!.problem, SaveProblem.notAnObject);
      expect(
          SaveCodec.decode('null').failure!.problem, SaveProblem.notAnObject);
    });

    test('an empty object is a bad schema version', () {
      expect(_problem(<String, Object?>{}), SaveProblem.badSchemaVersion);
    });

    test('schemaVersion missing, zero, negative or not an integer', () {
      for (final value in <Object?>[null, 0, -1, '1', 1.0, 1.5, true, []]) {
        final json = _json(save)..['schemaVersion'] = value;
        expect(_problem(json), SaveProblem.badSchemaVersion, reason: '$value');
      }
      expect(_problem(_json(save)..remove('schemaVersion')),
          SaveProblem.badSchemaVersion);
    });

    test('a newer schema is incompatible and keeps its id and name', () {
      final json = _json(save)..['schemaVersion'] = saveSchemaVersion + 1;
      final failure = SaveCodec.fromJson(json).failure!;
      expect(failure.problem, SaveProblem.newerSchema);
      expect(failure.incompatible, isTrue);
      expect(failure.id, save.id);
      expect(failure.name, 'Friday night');
      expect(failure.salvage, isNull);
    });

    test('id missing, empty or not a string', () {
      for (final value in <Object?>[null, '', 5, [], {}]) {
        final json = _json(save)..['id'] = value;
        expect(_problem(json), SaveProblem.missingId, reason: '$value');
      }
      expect(_problem(_json(save)..remove('id')), SaveProblem.missingId);
    });

    test('setup missing or malformed', () {
      final bad = <Object?>[
        null,
        'x',
        5,
        <Object?>[],
        <String, Object?>{},
        {'seats': 'x'},
        {'seats': <Object?>[]},
        {'seats': List<Object?>.filled(3, null)},
        {'seats': List<Object?>.filled(5, null)},
        // A seat entry that is neither null nor an object.
        {
          'seats': [
            {'type': 'human'},
            'oops',
            {'type': 'human'},
            null,
          ]
        },
        // Fewer than two players.
        {
          'seats': [
            {'type': 'human'},
            null,
            null,
            null,
          ]
        },
        {'seats': List<Object?>.filled(4, null)},
      ];
      for (final value in bad) {
        final json = _json(save)..['setup'] = value;
        expect(_problem(json), SaveProblem.badSetup, reason: '$value');
      }
      expect(_problem(_json(save)..remove('setup')), SaveProblem.badSetup);
    });

    test('a garbled rules object falls back instead of failing', () {
      final json = _json(save);
      (json['setup'] as Map)['rules'] = 'garbage';
      final back = SaveCodec.fromJson(json).save;
      expect(back, isNotNull);
      expect(back!.setup.rules.bankedRolls, isFalse);
    });

    test('seed missing or not an integer', () {
      for (final value in <Object?>[null, 'abc', '', '1.5', 1.5, true, []]) {
        final json = _json(save)..['seed'] = value;
        expect(_problem(json), SaveProblem.badSeed, reason: '$value');
      }
      expect(_problem(_json(save)..remove('seed')), SaveProblem.badSeed);
    });

    test('log missing or not a string', () {
      for (final value in <Object?>[null, 5, [], {}, true]) {
        final json = _json(save)..['log'] = value;
        expect(_problem(json), SaveProblem.missingLog, reason: '$value');
      }
      expect(_problem(_json(save)..remove('log')), SaveProblem.missingLog);
    });

    test('a failure keeps the id and name that could be read', () {
      final json = _json(save)..['seed'] = 'x';
      final failure = SaveCodec.fromJson(json).failure!;
      expect(failure.id, save.id);
      expect(failure.name, 'Friday night');
    });
  });

  group('corrupt log', () {
    test('a bad character gives corruptLog with a salvage of the prefix', () {
      final text = MoveLogCodec.encode(save.log);
      final broken = '${text.substring(0, 20)}!!${text.substring(22)}';
      final json = _json(save)..['log'] = broken;
      final failure = SaveCodec.fromJson(json).failure!;
      expect(failure.problem, SaveProblem.corruptLog);
      expect(failure.logIndex, 10);
      expect(failure.id, save.id);
      final salvage = failure.salvage!;
      expect(salvage.log, save.log.take(10).toList());
      expect(salvage.check, isNull);
      expect(salvage.id, save.id);
      expect(salvage.setup, save.setup);
    });

    test('a cut-off log salvages the whole entries', () {
      final text = MoveLogCodec.encode(save.log);
      final json = _json(save)..['log'] = text.substring(0, text.length - 1);
      final failure = SaveCodec.fromJson(json).failure!;
      expect(failure.problem, SaveProblem.corruptLog);
      expect(failure.logIndex, save.log.length - 1);
      expect(failure.salvage!.log, save.log.take(save.log.length - 1));
    });

    test('a corrupt first entry salvages an empty save', () {
      final json = _json(save)..['log'] = 'zz${'00' * 3}';
      final failure = SaveCodec.fromJson(json).failure!;
      expect(failure.logIndex, 0);
      expect(failure.salvage!.log, isEmpty);
      expect(SaveReplayer.replay(failure.salvage!).ok, isTrue);
    });
  });

  group('never throws', () {
    final text = SaveCodec.encode(save);

    void check(Object? tree) {
      final result = SaveCodec.fromJson(tree);
      final decoded = result.save ?? result.failure?.salvage;
      expect(result.save != null || result.failure != null, isTrue);
      if (decoded != null) {
        // Whatever decodes must also replay and list without throwing.
        SaveReplayer.replay(decoded);
        SaveListItem.fromSave(decoded);
      }
    }

    test('random edits of the encoded text', () {
      final rng = Random(2026);
      for (var i = 0; i < 1500; i++) {
        var s = text;
        final edits = 1 + rng.nextInt(3);
        for (var e = 0; e < edits; e++) {
          final at = rng.nextInt(s.length);
          switch (rng.nextInt(4)) {
            case 0:
              s = s.replaceRange(
                  at, at + 1, String.fromCharCode(32 + rng.nextInt(95)));
            case 1:
              s = s.replaceRange(
                  at, min(s.length, at + 1 + rng.nextInt(5)), '');
            case 2:
              s = s.substring(0, at);
            default:
              s = s.replaceRange(at, at, '"{[,:'[rng.nextInt(5)]);
          }
          if (s.isEmpty) {
            break;
          }
        }
        final result = SaveCodec.decode(s);
        expect(result.save != null || result.failure != null, isTrue);
        final decoded = result.save ?? result.failure?.salvage;
        if (decoded != null) {
          SaveReplayer.replay(decoded);
        }
      }
    });

    test('random replacement of nodes in the decoded tree', () {
      final rng = Random(7);
      final replacements = <Object?>[
        null,
        0,
        -1,
        1.5,
        1e30,
        'x',
        '',
        '00',
        true,
        <Object?>[],
        <String, Object?>{},
        ['a', 1],
        {'k': 'v'},
        9223372036854775807,
      ];
      for (var i = 0; i < 500; i++) {
        final tree = jsonDecode(text) as Object?;
        Object? node = tree;
        for (var depth = 0; depth < 1 + rng.nextInt(4); depth++) {
          if (node is Map && node.isNotEmpty) {
            final key = node.keys.elementAt(rng.nextInt(node.length));
            if (rng.nextInt(3) == 0 || node[key] is! Object) {
              if (rng.nextBool()) {
                node.remove(key);
              } else {
                node[key] = replacements[rng.nextInt(replacements.length)];
              }
              break;
            }
            final next = node[key];
            if (next is Map || next is List) {
              node = next;
            } else {
              node[key] = replacements[rng.nextInt(replacements.length)];
              break;
            }
          } else if (node is List && node.isNotEmpty) {
            final index = rng.nextInt(node.length);
            final next = node[index];
            if ((next is Map || next is List) && rng.nextBool()) {
              node = next;
            } else {
              node[index] = replacements[rng.nextInt(replacements.length)];
              break;
            }
          } else {
            break;
          }
        }
        check(tree);
      }
    });
  });
}
