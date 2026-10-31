import 'package:ludo/seats/seats.dart';

/// `2026-10-30 14:05`, in the phone's local time.
String formatSaveDate(DateTime time) {
  final t = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

const Map<AiLevel, String> _levelName = {
  AiLevel.easy: 'Easy',
  AiLevel.medium: 'Medium',
  AiLevel.hard: 'Hard',
  AiLevel.expert: 'Expert',
};

/// One line about who plays: `4 players: 2 human, 2 AI (Hard) · Teams`.
/// Empty when the setup is unknown (an unreadable row).
String seatSummary(MatchSetup? setup) {
  if (setup == null) {
    return '';
  }
  final seats = setup.activeSeats;
  final humans = seats.where((s) => setup.typeOf(s) == SeatType.human).length;
  final remotes = seats.where((s) => setup.typeOf(s) == SeatType.remote).length;
  final levels = {
    for (final s in seats)
      if (setup.typeOf(s) == SeatType.ai) setup.configOf(s).aiLevel,
  };
  final aiCount = seats.where((s) => setup.typeOf(s) == SeatType.ai).length;

  final parts = <String>[
    if (humans > 0) '$humans human',
    if (aiCount > 0)
      levels.length == 1
          ? '$aiCount AI (${_levelName[levels.first]})'
          : '$aiCount AI',
    if (remotes > 0) '$remotes online',
  ];
  final teams = setup.isTeamPlay ? ' · Teams' : '';
  return '${seats.length} players: ${parts.join(', ')}$teams';
}
