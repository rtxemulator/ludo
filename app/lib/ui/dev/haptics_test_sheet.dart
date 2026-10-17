import 'package:flutter/material.dart';
import 'package:ludo/ui/core/haptics.dart';

import '../../haptics/haptics_service.dart';

/// Temporary developer sheet to feel every haptic pattern and flip the
/// global toggle (replaced by the real settings screen in step P6).
Future<void> showHapticsTestSheet(
  BuildContext context,
  HapticsService service,
) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) => _HapticsTestSheet(service: service),
  );
}

const Map<HapticEvent, String> _labels = {
  HapticEvent.diceImpact: 'Dice impacts (tick x3, 0.9 / 0.5 / 0.25)',
  HapticEvent.diceSettle: 'Dice settle (click)',
  HapticEvent.tokenLand: 'Token land (tick)',
  HapticEvent.capture: 'Capture (heavy, click)',
  HapticEvent.home: 'Reach home (click, click, heavy)',
  HapticEvent.illegal: 'Illegal move (tick, tick)',
  HapticEvent.six: 'Six (medium click)',
  HapticEvent.win: 'Win (5 pulses)',
};

class _HapticsTestSheet extends StatefulWidget {
  const _HapticsTestSheet({required this.service});

  final HapticsService service;

  @override
  State<_HapticsTestSheet> createState() => _HapticsTestSheetState();
}

class _HapticsTestSheetState extends State<_HapticsTestSheet> {
  late final Future<bool> _native = widget.service.isNativeAvailable();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          SwitchListTile(
            title: const Text('Haptics'),
            subtitle: FutureBuilder<bool>(
              future: _native,
              builder: (context, snapshot) => Text(
                snapshot.connectionState != ConnectionState.done
                    ? 'checking vibrator...'
                    : snapshot.data == true
                        ? 'native vibrator found'
                        : 'no native vibrator: framework fallback',
              ),
            ),
            value: widget.service.enabled,
            onChanged: (v) => setState(() => widget.service.enabled = v),
          ),
          for (final event in HapticEvent.values)
            ListTile(
              leading: const Icon(Icons.vibration),
              title: Text(_labels[event]!),
              onTap: () => widget.service.play(event),
            ),
        ],
      ),
    );
  }
}
