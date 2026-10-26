import 'dart:io';

import 'package:test/test.dart';

/// `lib/ai` is pure Dart on top of the engine and seats surfaces: no
/// Flutter, no dart:ui / dart:io, and (fairness rule 1 of docs/ludo-ai.md)
/// it never draws a die or reads the generator state.
void main() {
  final files = Directory('lib/ai')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('lib/ai contains sources', () {
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
  };
  const allowedPackages = {
    'package:ludo/engine/ludo_engine.dart',
    'package:ludo/seats/seats.dart',
  };

  for (final file in files) {
    final source = file.readAsStringSync();
    test('${file.path} imports no Flutter or dart:ui', () {
      for (final match in importPattern.allMatches(source)) {
        final uri = match.group(1)!;
        expect(uri.startsWith('package:flutter'), isFalse, reason: uri);
        expect(forbidden.contains(uri), isFalse, reason: uri);
        if (uri.startsWith('package:')) {
          expect(allowedPackages.contains(uri), isTrue, reason: uri);
        }
      }
    });
    test('${file.path} never draws a die or reads the generator state', () {
      expect(source.contains('rngState'), isFalse);
      expect(RegExp(r'Dice\.(roll|nextRaw)').hasMatch(source), isFalse);
      expect(source.contains('Engine.roll('), isFalse);
    });
  }
}
