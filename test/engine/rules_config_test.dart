import 'package:ludo/engine/ludo_engine.dart';
import 'package:test/test.dart';

void main() {
  group('RulesConfig defaults', () {
    const rules = RulesConfig();

    test('match the specification', () {
      expect(rules.endMode, EndMode.fullRanking);
      expect(rules.teammateControl, isTrue);
      expect(rules.needSixToLeave, isTrue);
      expect(rules.extraTurnOnSix, isTrue);
      expect(rules.tripleSixForfeit, isTrue);
      expect(rules.extraTurnOnCapture, isTrue);
      expect(rules.extraTurnOnHome, isTrue);
      expect(rules.exactRollToFinish, isTrue);
      expect(rules.blockades, isFalse);
      expect(rules.teamsEnabled, isFalse);
    });

    test('classic preset equals the defaults', () {
      expect(const RulesConfig.classic(), rules);
    });
  });

  group('presets', () {
    test('quick', () {
      const quick = RulesConfig.quick();
      expect(quick.needSixToLeave, isFalse);
      expect(quick.tripleSixForfeit, isFalse);
      expect(quick.endMode, EndMode.firstToWin);
      // Everything else stays classic.
      expect(
        quick.copyWith(
          needSixToLeave: true,
          tripleSixForfeit: true,
          endMode: EndMode.fullRanking,
        ),
        const RulesConfig.classic(),
      );
    });

    test('strategic', () {
      const strategic = RulesConfig.strategic();
      expect(strategic.blockades, isTrue);
      expect(strategic.extraTurnOnCapture, isFalse);
      expect(
        strategic.copyWith(blockades: false, extraTurnOnCapture: true),
        const RulesConfig.classic(),
      );
    });
  });

  group('value semantics', () {
    test('copyWith changes only the named field', () {
      const base = RulesConfig();
      final changed = base.copyWith(blockades: true);
      expect(changed.blockades, isTrue);
      expect(changed.copyWith(blockades: false), base);
    });

    test('equal configs have equal hash codes', () {
      expect(
        const RulesConfig.quick().hashCode,
        const RulesConfig.quick().hashCode,
      );
      expect(const RulesConfig.quick(), isNot(const RulesConfig.classic()));
    });
  });
}
