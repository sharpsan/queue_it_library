import 'dart:async';

import 'package:queue_it_example/main.dart' as example;
import 'package:test/test.dart';

void main() {
  test('processes every download and retries the one that fails', () async {
    final lines = <String>[];
    await runZoned(
      example.main,
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => lines.add(line),
      ),
    );

    expect(
      lines,
      contains('file-3.zip is completed after 2 retries; '
          'the last error was: Exception: connection reset'),
    );
    expect(lines.last, contains('Completed: 5'));
    expect(lines.last, contains('Failed: 0'));
  });
}
