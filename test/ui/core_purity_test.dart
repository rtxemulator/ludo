import 'dart:io';

import 'package:test/test.dart';

/// `lib/ui/core` is the Flutter-free half of the UI layer: it may use the
/// engine and pure Dart, but never Flutter or dart:ui, so it stays testable
/// with plain `dart test` and the painter layer stays a thin wrapper.
void main() {
  final files = Directory('lib/ui/core')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('lib/ui/core contains sources', () {
    expect(files, isNotEmpty);
  });

  final importPattern = RegExp(
    r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );
  const forbidden = {
    'dart:ui',
    'dart:io',
    'dart:html',
    'dart:js',
    'dart:js_interop',
    'dart:ffi',
    'dart:isolate',
  };

  for (final file in files) {
    test('${file.path} imports no Flutter or dart:ui', () {
      final source = file.readAsStringSync();
      for (final match in importPattern.allMatches(source)) {
        final uri = match.group(1)!;
        expect(uri.startsWith('package:flutter'), isFalse, reason: uri);
        expect(forbidden.contains(uri), isFalse, reason: uri);
        if (uri.startsWith('package:')) {
          expect(
            uri == 'package:ludo/engine/ludo_engine.dart',
            isTrue,
            reason: 'only the public engine surface is allowed: $uri',
          );
        }
      }
    });
  }
}
