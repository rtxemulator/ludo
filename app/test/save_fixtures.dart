import 'dart:convert';

import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/seats/seats.dart';
import 'package:ludo/storage/storage.dart';

final DateTime day = DateTime.utc(2026, 10, 30, 12);

/// A real save: [decisions] "first legal move" decisions of a 2-player game
/// (or the whole game with [toEnd]), last updated at [at].
GameSave playSave({
  required String id,
  required DateTime at,
  int decisions = 6,
  int seed = 11,
  MatchSetup? setup,
  String? name,
  bool toEnd = false,
}) {
  final match = setup ?? MatchSetup.hotSeat(players: 2);
  var state = match.newGame(seed);
  var save = GameSave.begin(id: id, now: at, setup: match, seed: seed);
  var n = 0;
  while (!state.isOver && (toEnd || n < decisions)) {
    while (!state.isOver && !state.awaitingMove) {
      state = Engine.roll(state).state;
    }
    if (state.isOver) {
      break;
    }
    final move = Engine.legalMoves(state).first;
    final entry = Engine.logEntry(state, move);
    final after = Engine.apply(state, move);
    save = save.withEntry(entry, after, at);
    state = after;
    n++;
  }
  return name == null ? save : save.withName(name);
}

/// [save] with a wrong check fingerprint: it decodes but fails its replay.
GameSave withBrokenCheck(GameSave save) {
  final json = jsonDecode(SaveCodec.encode(save)) as Map<String, Object?>;
  json['check'] = '0000000000000000';
  return SaveCodec.decode(jsonEncode(json)).save!;
}
