import 'dart:typed_data';

import 'package:ludo/engine/ludo_engine.dart';

import 'weights.dart';

// Scratch buffers: the evaluation runs on one isolate at a time and never
// re-enters itself, so static buffers save an allocation per call.
final Int32List _unit = Int32List(16);
final Int32List _abs = Int32List(16);
final Int32List _rel = Int32List(16);
final Int32List _safe = Int32List(16);
final Int32List _mask = Int32List(seatCount);

int _bits(int mask) {
  var n = 0;
  for (var d = 1; d <= 6; d++) {
    n += (mask >> d) & 1;
  }
  return n;
}

/// `S(unit)` for every unit (indexed by unit id `0..3`; units that do not
/// play stay 0). Reads only public board facts: token positions, waiting
/// counters and rules, never the PRNG.
List<double> unitScores(GameState s, AiWeights w) {
  final scores = List<double>.filled(seatCount, 0);
  var n = 0;
  for (final seat in s.activeSeats) {
    final u = s.unitOf(seat);
    final row = s.tokens[seat];
    for (var i = 0; i < tokensPerSeat; i++) {
      final p = row[i];
      if (p == yardPosition) {
        continue;
      }
      if (p == finishPosition) {
        scores[u] += finishPosition + 1 + w.out + w.finished;
        continue;
      }
      scores[u] += p + 1 + w.out;
      if (p >= firstHomeColumnPosition) {
        scores[u] += w.safe;
        continue;
      }
      final a = (p + seat * seatTrackOffset) % trackSquares;
      final safe = isSafeSquare(a);
      if (safe) {
        scores[u] += w.safe;
      }
      if (s.rest[seat][i] > 0) {
        scores[u] -= w.waiting;
      }
      _unit[n] = u;
      _abs[n] = a;
      _rel[n] = p;
      _safe[n] = safe ? 1 : 0;
      n++;
    }
  }

  // Exposure and threat: which faces let an enemy token land on this one.
  for (var v = 0; v < n; v++) {
    if (_safe[v] == 1) {
      continue;
    }
    for (var u = 0; u < seatCount; u++) {
      _mask[u] = 0;
    }
    for (var a = 0; a < n; a++) {
      if (_unit[a] == _unit[v]) {
        continue;
      }
      final d = (_abs[v] - _abs[a] + trackSquares) % trackSquares;
      // A token cannot hit from the home column; the walk must also reach.
      if (d >= 1 && d <= 6 && _rel[a] + d <= lastTrackPosition) {
        _mask[_unit[a]] |= 1 << d;
      }
    }
    var union = 0;
    for (var u = 0; u < seatCount; u++) {
      union |= _mask[u];
    }
    final progress = _rel[v] + 1;
    if (union != 0) {
      scores[_unit[v]] -=
          _bits(union) / 6 * w.exposureScale * (progress + w.exposureBase);
    }
    for (var u = 0; u < seatCount; u++) {
      if (_mask[u] != 0) {
        scores[u] +=
            _bits(_mask[u]) / 6 * w.threatScale * (progress + w.threatBase);
      }
    }
  }

  if (s.rules.blockades) {
    for (final wall in Engine.blockades(s)) {
      final owner = s.unitOf(wall.seat);
      var holds = false;
      for (var t = 0; t < n; t++) {
        if (_unit[t] == owner) {
          continue;
        }
        final d = (wall.square - _abs[t] + trackSquares) % trackSquares;
        if (d >= 1 && d <= 6) {
          holds = true;
          scores[_unit[t]] -= w.blockStuck;
        }
      }
      if (holds) {
        scores[owner] += w.blockHold;
      }
    }
  }
  return scores;
}
