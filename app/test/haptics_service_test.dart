import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo/ui/core/haptics.dart';

import 'package:ludo_app/haptics/haptics_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(HapticsService.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('sends the first pulse of an event to the native channel', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    final service = HapticsService(channel: channel);
    service.play(HapticEvent.tokenLand);
    await Future<void>.delayed(Duration.zero);
    expect(calls.length, 1);
    expect(calls.single.method, 'pulse');
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['kind'], 'tick');
    expect(args['strength'], 0.8);
    service.dispose();
  });

  test('toggle off sends nothing', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    final service = HapticsService(channel: channel)..enabled = false;
    service.play(HapticEvent.capture);
    await Future<void>.delayed(Duration.zero);
    expect(calls, isEmpty);
    service.dispose();
  });

  test('a missing channel or a false result never throws', () async {
    final service = HapticsService(channel: channel);
    service.play(HapticEvent.diceSettle);
    await Future<void>.delayed(Duration.zero);
    expect(await service.isNativeAvailable(), isFalse);

    messenger.setMockMethodCallHandler(channel, (call) async => false);
    service.play(HapticEvent.capture);
    await Future<void>.delayed(Duration.zero);
    service.dispose();
  });
}
