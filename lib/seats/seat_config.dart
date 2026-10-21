/// Who controls a seat.
enum SeatType {
  /// A person at this device.
  human,

  /// A computer player (see `GreedyBot`; the real tiers arrive in
  /// Milestone 4).
  ai,

  /// A person on another device (Milestone 8; not selectable yet).
  remote,
}

/// Strength of an AI seat. Stored now so saves and setups already carry it;
/// every level plays the same greedy baseline until Milestone 4.
enum AiLevel { easy, medium, hard, expert }

/// Default display names of the four seats (clockwise from the top-left
/// yard).
const List<String> defaultSeatNames = ['Red', 'Green', 'Yellow', 'Blue'];

/// Configuration of one occupied seat: `{ type, aiLevel, name }`.
class SeatConfig {
  const SeatConfig({
    this.type = SeatType.human,
    this.aiLevel = AiLevel.medium,
    this.name,
  });

  const SeatConfig.human({String? name}) : this(name: name);

  const SeatConfig.ai({AiLevel level = AiLevel.medium, String? name})
      : this(type: SeatType.ai, aiLevel: level, name: name);

  /// Longest name the setup accepts.
  static const int maxNameLength = 12;

  final SeatType type;
  final AiLevel aiLevel;

  /// Custom player name; `null` means the seat's colour name.
  final String? name;

  bool get isHuman => type == SeatType.human;
  bool get isAi => type == SeatType.ai;
  bool get isRemote => type == SeatType.remote;

  SeatConfig copyWith({
    SeatType? type,
    AiLevel? aiLevel,
    String? name,
    bool clearName = false,
  }) {
    return SeatConfig(
      type: type ?? this.type,
      aiLevel: aiLevel ?? this.aiLevel,
      name: clearName ? null : _cleanName(name ?? this.name),
    );
  }

  /// Trims [raw] and cuts it to [maxNameLength]; empty means no name.
  static String? _cleanName(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed.length <= maxNameLength
        ? trimmed
        : trimmed.substring(0, maxNameLength);
  }

  Map<String, Object?> toJson() => {
        'type': type.name,
        'aiLevel': aiLevel.name,
        if (name != null) 'name': name,
      };

  /// Reads a config written by [toJson]; unknown or missing fields fall back
  /// to the defaults so old saves keep loading.
  factory SeatConfig.fromJson(Map<String, Object?> json) {
    return SeatConfig(
      type: _byName(SeatType.values, json['type'], SeatType.human),
      aiLevel: _byName(AiLevel.values, json['aiLevel'], AiLevel.medium),
      name: _cleanName(json['name'] as String?),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SeatConfig &&
      other.type == type &&
      other.aiLevel == aiLevel &&
      other.name == name;

  @override
  int get hashCode => Object.hash(type, aiLevel, name);

  @override
  String toString() => 'SeatConfig(${type.name}'
      '${isAi ? ', ${aiLevel.name}' : ''}'
      '${name == null ? '' : ', "$name"'})';
}

T _byName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }
  return fallback;
}
