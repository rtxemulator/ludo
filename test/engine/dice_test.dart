import 'package:ludo/engine/dice.dart';
import 'package:ludo/engine/sha256.dart';
import 'package:test/test.dart';

void main() {
  group('PRNG', () {
    test('SplitMix64 matches reference vectors', () {
      var state = 0;
      final seed0 = <int>[];
      for (var i = 0; i < 3; i++) {
        final step = Dice.nextRaw(state);
        seed0.add(step.output);
        state = step.next;
      }
      expect(seed0, [
        -2152535657050944081, // 0xE220A8397B1DCDAF
        7960286522194355700,
        487617019471545679,
      ]);

      state = 42;
      final seed42 = <int>[];
      for (var i = 0; i < 3; i++) {
        final step = Dice.nextRaw(state);
        seed42.add(step.output);
        state = step.next;
      }
      expect(seed42, [
        -4767286540954276203,
        2949826092126892291,
        5139283748462763858,
      ]);
    });

    test('dice sequence for a seed is stable', () {
      var state = 123;
      final values = <int>[];
      for (var i = 0; i < 20; i++) {
        final roll = Dice.roll(state);
        values.add(roll.value);
        state = roll.nextState;
      }
      expect(values, [
        3, 6, 2, 3, 3, 1, 3, 1, 6, 2, 4, 2, 5, 2, 1, 4, 6, 6, 3, 4, //
      ]);
    });

    test('roll is a pure function of the state', () {
      final a = Dice.roll(777);
      final b = Dice.roll(777);
      expect(a.value, b.value);
      expect(a.nextState, b.nextState);
      expect(a.nextState, isNot(777));
    });

    test('every value 1..6 is produced, roughly uniformly', () {
      final counts = List<int>.filled(7, 0);
      var state = 2026;
      const n = 60000;
      for (var i = 0; i < n; i++) {
        final roll = Dice.roll(state);
        counts[roll.value]++;
        state = roll.nextState;
      }
      expect(counts[0], 0);
      for (var face = 1; face <= 6; face++) {
        expect(counts[face], inInclusiveRange(9500, 10500),
            reason: 'face $face');
      }
    });

    test('negative and extreme seeds work', () {
      for (final seed in [-1, 0, 1, 1 << 62, -(1 << 62), 0x7FFFFFFFFFFFFFFF]) {
        final value = Dice.roll(seed).value;
        expect(value, inInclusiveRange(1, 6));
      }
    });
  });

  group('SHA-256', () {
    test('known answers', () {
      expect(
        toHex(sha256(const [])),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
      expect(
        toHex(sha256('abc'.codeUnits)),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('multi-block message', () {
      expect(
        toHex(sha256(List<int>.filled(1000, 0x61))),
        '41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3',
      );
    });
  });

  group('commit-reveal', () {
    test('commitments match reference hashes of the big-endian seed', () {
      expect(
        Dice.commit(0x0123456789ABCDEF),
        '55c53f5d490297900cefa825d0c8e8e9532ee8a118abe7d8570762cd38be9818',
      );
      expect(
        Dice.commit(0),
        'af5570f5a1810b7af78caf4bc70a660f0df51e42baf91d4de5b2328de0e83dfc',
      );
      expect(
        Dice.commit(-1),
        '12a3ae445661ce5dee78d0650d33362dec29c4f82af05e7e57fb595bbbacf0ca',
      );
    });

    test('verify accepts the real seed and rejects any other', () {
      const seedA = 0x1122334455667788;
      final commitment = Dice.commit(seedA);
      expect(Dice.verify(seedA, commitment), isTrue);
      expect(Dice.verify(seedA, commitment.toUpperCase()), isTrue);
      expect(Dice.verify(seedA + 1, commitment), isFalse);
    });

    test('both peers derive the same roll seed', () {
      const seedA = 0x1234567890ABCDEF;
      const seedB = 0x0FEDCBA987654321;
      final atPeerA = Dice.combineSeeds(seedA, seedB);
      final atPeerB = Dice.combineSeeds(seedB, seedA);
      expect(atPeerA, atPeerB);
      expect(Dice.roll(atPeerA).value, Dice.roll(atPeerB).value);
    });

    test('neither seed alone determines the shared seed', () {
      const seedA = 42;
      expect(Dice.combineSeeds(seedA, 1), isNot(Dice.combineSeeds(seedA, 2)));
    });
  });
}
