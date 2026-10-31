import 'package:ludo/seats/seats.dart';
import 'package:ludo/storage/storage.dart';

/// What happened in [step], in words: `Red rolled 4 · moved token 2`. With
/// teammate control the roller moves a partner's token:
/// `Red rolled 4 · moved Yellow's token 2`.
String describeStep(ReplayStep step, MatchSetup setup) {
  final roller = setup.displayName(step.roller);
  final owner = step.move.owner;
  final token = step.move.isUnit
      ? 'blockade of tokens ${step.move.tokenIndex + 1} and '
          '${step.move.partnerIndex + 1}'
      : 'token ${step.move.tokenIndex + 1}';
  final whose = owner == step.roller ? '' : "${setup.displayName(owner)}'s ";
  return '$roller rolled ${step.dice} · moved $whose$token';
}
