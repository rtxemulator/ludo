import 'dart:io';

import 'package:test/test.dart';

/// `lib/storage` is the pure-Dart save layer: it may use the engine, the
/// seat layer and plain Dart (`dart:convert`, `dart:math`), never Flutter,
/// dart:ui or dart:io (files and databases belong to the app's store).
void main() {
  final files = Directory('lib/storage')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('lib/storage contains sources', () {
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
  const allowedPackages = {
    'package:ludo/engine/ludo_engine.dart',
    'package:ludo/seats/seats.dart',
  };

  for (final file in files) {
    test('${file.path} imports no Flutter, dart:ui or dart:io', () {
      final source = file.readAsStringSync();
      for (final match in importPattern.allMatches(source)) {
        final uri = match.group(1)!;
        expect(uri.startsWith('package:flutter'), isFalse, reason: uri);
        expect(forbidden.contains(uri), isFalse, reason: uri);
        if (uri.startsWith('package:')) {
          expect(
            allowedPackages.contains(uri),
            isTrue,
            reason: 'only the engine and seats barrels are allowed: $uri',
          );
        }
      }
    });
  }
}
