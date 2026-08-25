// ignore_for_file: avoid_relative_lib_imports

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/file_io/recent_files.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('RecentFiles deduplicates by URI and keeps the newest 20 records', () async {
    final prefs = await SharedPreferences.getInstance();
    final recent = RecentFiles(prefs);
    final now = DateTime(2026, 8, 20, 12);

    for (var i = 0; i < 21; i++) {
      await recent.add(
        RecentFile(
          uri: Uri.parse('content://docs/$i'),
          name: '$i.md',
          lastOpened: now.add(Duration(minutes: i)),
        ),
      );
    }
    await recent.add(
      RecentFile(
        uri: Uri.parse('content://docs/5'),
        name: 'renamed.md',
        lastOpened: now.add(const Duration(hours: 2)),
      ),
    );

    final files = await recent.all();
    expect(files, hasLength(20));
    expect(files.first.name, 'renamed.md');
    expect(files.where((file) => file.uri.toString() == 'content://docs/5'), hasLength(1));
    expect(files.any((file) => file.uri.toString() == 'content://docs/0'), isFalse);
  });
}
