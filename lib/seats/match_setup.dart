import 'package:ludo/engine/ludo_engine.dart';

import 'rules_preset.dart';
import 'seat_config.dart';

/// Why a [MatchSetup] cannot be played yet.
enum SetupProblem {
  /// Fewer than two seats are occupied.
  tooFewPlayers,

  /// Team play (2v2) needs all four seats.
  teamsNeedFourPlayers,

  /// A seat is `remote` but online play is not available.
  remoteUnavailable,
}

/// Everything chosen on the new-game screen: who sits where, who controls
/// each seat, and the rules. Immutable; every `with...` returns a copy.
///
/// Seats are the four board corners (`0` top-left ... `3` bottom-left); an
/// empty seat is `null`. Two players take the opposite corners `0` and `2`,
/// three players `0`, `1` and `2`. In team play partners are `0 + 2` versus
/// `1 + 3`, as in the engine.
///
/// `RulesConfig.teamsEnabled` is derived here: [rules] always carries the
/// value matching the seats, whatever was passed in.
class MatchSetup {
  /// [seats] must have exactly four entries (`null` = empty seat).
  MatchSetup({
    required List<SeatConfig?> seats,
    RulesConfig rules = const RulesConfig(),
    this.teams = false,
  })  : seats = List.unmodifiable(seats),
        baseRules = rules.copyWith(teamsEnabled: false) {
    if (seats.length != seatCount) {
      throw ArgumentError.value(seats, 'seats', 'need exactly $seatCount');
    }
  }

  /// A hot-seat table of [players] humans (2 to 4).
  factory MatchSetup.hotSeat({
    int players = 4,
    RulesConfig rules = const RulesConfig(),
    bool teams = false,
  }) {
    return MatchSetup(
      seats: _layout(players, const [null, null, null, null]),
      rules: rules,
      teams: teams && players == seatCount,
    );
  }

  /// Seats used for 2, 3 and 4 players.
  static const Map<int, List<int>> seatLayouts = {
    2: [0, 2],
    3: [0, 1, 2],
    4: [0, 1, 2, 3],
  };

  static const int minPlayers = 2;
  static const int maxPlayers = seatCount;

  /// The four seats; `null` is an empty one.
  final List<SeatConfig?> seats;

  /// The rules without the derived `teamsEnabled` flag.
  final RulesConfig baseRules;

  /// Whether 2v2 team play was chosen (only effective with four players).
  final bool teams;

  static List<SeatConfig?> _layout(int players, List<SeatConfig?> previous) {
    final used = seatLayouts[players];
    if (used == null) {
      throw ArgumentError.value(
        players,
        'players',
        'must be $minPlayers to $maxPlayers',
      );
    }
    return [
      for (var seat = 0; seat < seatCount; seat++)
        used.contains(seat) ? (previous[seat] ?? const SeatConfig()) : null,
    ];
  }

  // ---- Reading ------------------------------------------------------------

  /// Occupied seats, ascending (what `Engine.newGame` takes).
  List<int> get activeSeats => [
        for (var seat = 0; seat < seatCount; seat++)
          if (seats[seat] != null) seat,
      ];

  int get playerCount => activeSeats.length;

  bool isActive(int seat) => seats[seat] != null;

  /// The config of occupied [seat]; throws for an empty one.
  SeatConfig configOf(int seat) {
    final config = seats[seat];
    if (config == null) {
      throw StateError('Seat $seat is empty.');
    }
    return config;
  }

  /// Controller type of [seat]; `null` for an empty seat.
  SeatType? typeOf(int seat) => seats[seat]?.type;

  /// Whether the match is played as 2v2 teams.
  bool get isTeamPlay => teams && playerCount == seatCount;

  /// The competing unit of [seat]: its team (`seat % 2`) in team play,
  /// otherwise the seat itself.
  int teamOf(int seat) => isTeamPlay ? seat % 2 : seat;

  /// Name shown for [seat]: the custom one, else the colour name.
  String displayName(int seat) => seats[seat]?.name ?? defaultSeatNames[seat];

  /// The rules the engine plays with (`teamsEnabled` matches the seats).
  RulesConfig get rules => baseRules.copyWith(teamsEnabled: isTeamPlay);

  /// Which rule preset [rules] is.
  RulesPreset get preset => RulesPreset.of(baseRules);

  /// What keeps this setup from being played; empty means ready.
  ///
  /// [remoteAvailable] is `false` until online play exists (Milestone 8).
  List<SetupProblem> problems({bool remoteAvailable = false}) {
    return [
      if (playerCount < minPlayers) SetupProblem.tooFewPlayers,
      if (teams && playerCount != seatCount) SetupProblem.teamsNeedFourPlayers,
      if (!remoteAvailable && seats.any((s) => s != null && s.isRemote))
        SetupProblem.remoteUnavailable,
    ];
  }

  /// The match this setup describes, ready for the first roll.
  GameState newGame(int seed) => Engine.newGame(
        seed: seed,
        rules: rules,
        activeSeats: activeSeats,
      );

  // ---- Changing -----------------------------------------------------------

  MatchSetup _copy({
    List<SeatConfig?>? seats,
    RulesConfig? rules,
    bool? teams,
  }) {
    return MatchSetup(
      seats: seats ?? this.seats,
      rules: rules ?? baseRules,
      teams: teams ?? this.teams,
    );
  }

  /// Moves to [players] players (2 to 4). Seats that stay keep their config;
  /// team play is dropped unless there are four players.
  MatchSetup withPlayerCount(int players) {
    return _copy(
      seats: _layout(players, seats),
      teams: teams && players == seatCount,
    );
  }

  /// Replaces the config of occupied [seat].
  MatchSetup withSeat(int seat, SeatConfig config) {
    configOf(seat);
    return _copy(seats: [...seats]..[seat] = config);
  }

  /// Turns 2v2 team play on or off; it needs four players.
  MatchSetup withTeams(bool on) {
    if (on && playerCount != seatCount) {
      throw StateError('Team play needs $seatCount players.');
    }
    return _copy(teams: on);
  }

  /// Replaces the rules (the derived `teamsEnabled` of [rules] is ignored).
  MatchSetup withRules(RulesConfig rules) => _copy(rules: rules);

  // ---- Serialisation ------------------------------------------------------

  Map<String, Object?> toJson() => {
        'seats': [for (final s in seats) s?.toJson()],
        'teams': teams,
        'rules': rulesToJson(baseRules),
      };

  /// Reads a setup written by [toJson]. Anything malformed falls back to a
  /// four-human hot-seat table so a damaged save never blocks the app.
  factory MatchSetup.fromJson(Map<String, Object?> json) {
    final raw = json['seats'];
    final rulesJson = json['rules'];
    final rules = rulesJson is Map<String, Object?>
        ? rulesFromJson(rulesJson)
        : const RulesConfig();
    if (raw is! List || raw.length != seatCount) {
      return MatchSetup.hotSeat(rules: rules);
    }
    return MatchSetup(
      seats: [
        for (final entry in raw)
          entry is Map<String, Object?> ? SeatConfig.fromJson(entry) : null,
      ],
      rules: rules,
      teams: json['teams'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MatchSetup &&
      other.teams == teams &&
      other.baseRules == baseRules &&
      _sameSeats(other.seats, seats);

  static bool _sameSeats(List<SeatConfig?> a, List<SeatConfig?> b) {
    for (var i = 0; i < seatCount; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(seats), baseRules, teams);

  @override
  String toString() => 'MatchSetup(seats: $seats, teams: $teams, '
      'preset: ${preset.label})';
}
