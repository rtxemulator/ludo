import 'package:flutter/material.dart';
import 'package:ludo/engine/ludo_engine.dart' show EndMode, RulesConfig;
import 'package:ludo/seats/seats.dart';

import '../theme/palette.dart';
import 'seat_map.dart';

/// The new-game screen: how many players, who sits where and who controls
/// each seat (human / AI / online), the rule preset and the house rules.
///
/// Pure view over a [MatchSetup]: every edit makes a new setup, reported
/// through [onChanged]; "Play" hands the finished one to [onPlay].
class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    this.initial,
    this.onChanged,
    required this.onPlay,
  });

  /// The setup to start from (four humans, classic rules when omitted).
  final MatchSetup? initial;

  /// Called after every edit, so the app can remember the last setup.
  final ValueChanged<MatchSetup>? onChanged;

  /// Called with the context of this screen and the chosen setup.
  final void Function(BuildContext context, MatchSetup setup) onPlay;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late MatchSetup _setup = widget.initial ?? MatchSetup.hotSeat();

  void _update(MatchSetup next) {
    setState(() => _setup = next);
    widget.onChanged?.call(next);
  }

  void _rules(RulesConfig Function(RulesConfig) edit) =>
      _update(_setup.withRules(edit(_setup.baseRules)));

  static const Map<SetupProblem, String> _problemText = {
    SetupProblem.tooFewPlayers: 'At least two players are needed.',
    SetupProblem.teamsNeedFourPlayers: 'Teams need four players.',
    SetupProblem.remoteUnavailable: 'Online seats are not available yet.',
  };

  static const Map<RulesPreset, String> _presetText = {
    RulesPreset.classic: 'Standard tournament rules.',
    RulesPreset.quick:
        'Tokens leave the yard on any roll, no three-sixes penalty, the first '
            'player home wins.',
    RulesPreset.strategic: 'Blockades are on; captures give no extra turn.',
    RulesPreset.custom: 'Your own mix of house rules.',
  };

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final palette =
        brightness == Brightness.dark ? LudoPalette.dark : LudoPalette.light;
    final problems = _setup.problems();
    return Scaffold(
      appBar: AppBar(title: const Text('New game')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  ..._playersSection(palette),
                  const SizedBox(height: 20),
                  ..._rulesSection(),
                  if (problems.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    for (final p in problems)
                      Text(
                        _problemText[p]!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('play'),
                  onPressed: problems.isEmpty
                      ? () => widget.onPlay(context, _setup)
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Players ------------------------------------------------------------

  List<Widget> _playersSection(LudoPalette palette) {
    return [
      _heading('Players'),
      SegmentedButton<int>(
        key: const ValueKey('player-count'),
        showSelectedIcon: false,
        segments: [
          for (final n in [2, 3, 4]) ButtonSegment(value: n, label: Text('$n')),
        ],
        selected: {_setup.playerCount},
        onSelectionChanged: (v) => _update(_setup.withPlayerCount(v.first)),
      ),
      if (_setup.playerCount == MatchSetup.maxPlayers) ...[
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          key: const ValueKey('team-mode'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('Free for all')),
            ButtonSegment(value: true, label: Text('Teams 2v2')),
          ],
          selected: {_setup.teams},
          onSelectionChanged: (v) => _update(_setup.withTeams(v.first)),
        ),
        if (_setup.teams)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Partners sit opposite: Red + Yellow against '
                'Green + Blue.'),
          ),
      ],
      const SizedBox(height: 16),
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 190),
          child: SeatMap(setup: _setup, palette: palette),
        ),
      ),
      const SizedBox(height: 8),
      for (final seat in _setup.activeSeats) _seatTile(seat, palette),
      if (_setup.activeSeats.any((s) => _setup.configOf(s).isAi))
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            'AI seats play a basic greedy game for now; stronger levels '
            'come later.',
            style: TextStyle(fontSize: 12),
          ),
        ),
    ];
  }

  Widget _seatTile(int seat, LudoPalette palette) {
    final config = _setup.configOf(seat);
    return Card(
      key: ValueKey('seat-$seat'),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 9, backgroundColor: palette.seat[seat]),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _setup.displayName(seat),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_setup.isTeamPlay)
                  Text(_setup.teamOf(seat) == 0 ? 'Team A' : 'Team B'),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<SeatType>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: SeatType.human,
                    icon: Icon(Icons.person),
                    label: Text('Human'),
                  ),
                  ButtonSegment(
                    value: SeatType.ai,
                    icon: Icon(Icons.smart_toy),
                    label: Text('AI'),
                  ),
                  ButtonSegment(
                    value: SeatType.remote,
                    icon: Icon(Icons.wifi),
                    label: Text('Online'),
                    enabled: false,
                    tooltip: 'Online play arrives in a later release',
                  ),
                ],
                selected: {config.type},
                onSelectionChanged: (v) => _update(
                    _setup.withSeat(seat, config.copyWith(type: v.first))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Rules --------------------------------------------------------------

  List<Widget> _rulesSection() {
    final rules = _setup.baseRules;
    final preset = _setup.preset;
    return [
      _heading('Rules'),
      Wrap(
        spacing: 8,
        children: [
          for (final p in RulesPreset.named)
            ChoiceChip(
              key: ValueKey('preset-${p.name}'),
              label: Text(p.label),
              selected: preset == p,
              onSelected: (_) => _rules(p.applyTo),
            ),
          if (preset == RulesPreset.custom)
            const ChoiceChip(
              key: ValueKey('preset-custom'),
              label: Text('Custom'),
              selected: true,
            ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(_presetText[preset]!),
      ),
      SwitchListTile(
        key: const ValueKey('rule-banked'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Banked rolls'),
        subtitle: const Text(
          'Sixes stack: roll them all, then spend the whole bank.',
        ),
        value: rules.bankedRolls,
        onChanged: (v) => _rules((r) => r.copyWith(bankedRolls: v)),
      ),
      ExpansionTile(
        key: const ValueKey('house-rules'),
        tilePadding: EdgeInsets.zero,
        title: const Text('House rules'),
        children: [
          _rule('Need a 6 to leave the yard', rules.needSixToLeave,
              (r, v) => r.copyWith(needSixToLeave: v)),
          _rule('Extra turn on a 6', rules.extraTurnOnSix,
              (r, v) => r.copyWith(extraTurnOnSix: v)),
          _rule('Three 6s forfeit the turn', rules.tripleSixForfeit,
              (r, v) => r.copyWith(tripleSixForfeit: v)),
          _rule('Extra turn on a capture', rules.extraTurnOnCapture,
              (r, v) => r.copyWith(extraTurnOnCapture: v)),
          _rule('Extra turn on reaching home', rules.extraTurnOnHome,
              (r, v) => r.copyWith(extraTurnOnHome: v)),
          _rule('Exact roll to finish', rules.exactRollToFinish,
              (r, v) => r.copyWith(exactRollToFinish: v)),
          _rule(
              'Blockades', rules.blockades, (r, v) => r.copyWith(blockades: v)),
          _rule(
            'Play on for a full ranking',
            rules.endMode == EndMode.fullRanking,
            (r, v) => r.copyWith(
              endMode: v ? EndMode.fullRanking : EndMode.firstToWin,
            ),
          ),
          if (_setup.isTeamPlay)
            _rule(
              'Finished player rolls for their partner',
              rules.teammateControl,
              (r, v) => r.copyWith(teammateControl: v),
            ),
        ],
      ),
    ];
  }

  Widget _rule(
    String title,
    bool value,
    RulesConfig Function(RulesConfig rules, bool value) apply,
  ) {
    return SwitchListTile(
      key: ValueKey('rule-$title'),
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      value: value,
      onChanged: (v) => _rules((r) => apply(r, v)),
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(
          text,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      );
}
