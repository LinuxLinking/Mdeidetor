import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 最近打开的文件元数据。
///
/// 仅持久化 URI / 名称 / 最后打开时间,文件内容本身仍走 SAF
/// (`content://` URI 已 `takePersistableUriPermission`,重启后仍可访问)。
class RecentFile {
  final Uri uri;
  final String name;
  final DateTime lastOpened;

  RecentFile({
    required this.uri,
    required this.name,
    required this.lastOpened,
  });

  Map<String, dynamic> toJson() => {
        'uri': uri.toString(),
        'name': name,
        'lastOpened': lastOpened.toIso8601String(),
      };

  factory RecentFile.fromJson(Map<String, dynamic> j) => RecentFile(
        uri: Uri.parse(j['uri'] as String),
        name: j['name'] as String,
        lastOpened: DateTime.parse(j['lastOpened'] as String),
      );
}

/// 最近文件索引,持久化到 `SharedPreferences`。
///
/// 最多保留 [_max] 条,按 `lastOpened` 倒序。重复 URI 自动去重(以最新为准)。
class RecentFiles {
  RecentFiles(this._prefs);
  final SharedPreferences _prefs;

  static const String _key = 'recent_files';
  static const int _max = 20;

  /// 加入一条记录(去重 + 截断到 [_max])。
  Future<void> add(RecentFile file) async {
    final list = await all();
    list.removeWhere((f) => f.uri == file.uri); // 去重
    list.insert(0, file); // 最新置顶
    if (list.length > _max) {
      list.removeRange(_max, list.length); // 截断尾部
    }
    await _prefs.setString(
      _key,
      jsonEncode(list.map((f) => f.toJson()).toList()),
    );
  }

  /// 读取全部(按 lastOpened 倒序)。
  Future<List<RecentFile>> all() async {
    final s = _prefs.getString(_key);
    if (s == null) return [];
    final list = jsonDecode(s) as List<dynamic>;
    return list
        .map((j) => RecentFile.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// 按 URI 移除一条。
  Future<void> remove(Uri uri) async {
    final list = await all();
    list.removeWhere((f) => f.uri == uri);
    await _prefs.setString(
      _key,
      jsonEncode(list.map((f) => f.toJson()).toList()),
    );
  }

  /// 清空。
  Future<void> clear() async => _prefs.remove(_key);
}
