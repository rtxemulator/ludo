import 'dart:io';

import 'package:test/test.dart';

/// The engine must stay pure Dart (CLAUDE.md, cardinal rule): no Flutter, no
/// dart:ui / dart:io / dart:html, and no dependency on the other layers.
void main() {
  final files = Directory('lib/engine')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('lib/engine contains the engine sources', () {
    expect(files, isNotEmpty);
  });

  final importPattern = RegExp(
    r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );
  const forbiddenDart = {
    'dart:ui',
    'dart:io',
    'dart:html',
    'dart:js',
    'dart:js_interop',
    'dart:ffi',
    'dart:isolate',
  };

  for (final file in files) {
    test('${file.path} only imports pure Dart and engine files', () {
      final source = file.readAsStringSync();
      for (final match in importPattern.allMatches(source)) {
        final uri = match.group(1)!;
        expect(uri.startsWith('package:flutter'), isFalse, reason: uri);
        expect(forbiddenDart.contains(uri), isFalse, reason: uri);
        if (uri.startsWith('package:')) {
          expect(
            uri.startsWith('package:ludo/engine/'),
            isTrue,
            reason: '$uri reaches outside lib/engine',
          );
        } else if (!uri.startsWith('dart:')) {
          expect(uri.contains('..'), isFalse, reason: '$uri leaves lib/engine');
        }
      }
    });
  }
}
