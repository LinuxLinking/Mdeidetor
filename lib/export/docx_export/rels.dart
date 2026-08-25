/// 文档内关系收集器 + .rels 生成器。
///
/// 设计参见 dev-doc.md 第 9.7 节。
///
/// 生成两类 .rels:
///   - `_rels/.rels`(顶层关系):指向 `word/document.xml`(必需)
///   - `word/_rels/document.xml.rels`(文档内关系):图片、超链接等
class RelsCollector {
  final List<_Rel> _rels = [];
  int _nextId = 1;

  /// 注册一条关系,返回 rId(如 "rId1")。
  /// 同 target + type 复用同一 rId(超链接去重)。
  String register({
    required String target,
    required String type,
    String? targetMode,
  }) {
    final existing = _rels.firstWhere(
      (r) => r.target == target && r.type == type,
      orElse: () => _Rel('', '', ''),
    );
    if (existing.rId.isNotEmpty) return existing.rId;

    final rId = 'rId${_nextId++}';
    _rels.add(_Rel(rId, target, type, targetMode));
    return rId;
  }

  /// 生成 `word/_rels/document.xml.rels` XML 内容。
  String buildDocumentRelsXml() {
    final buf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..writeln('<Relationships xmlns='
          '"http://schemas.openxmlformats.org/package/2006/relationships">');
    for (final r in _rels) {
      final mode = r.targetMode == null ? '' : ' TargetMode="${r.targetMode}"';
      buf.writeln('  <Relationship Id="${r.rId}" Type="${r.type}" '
          'Target="${r.target}"$mode/>');
    }
    buf.writeln('</Relationships>');
    return buf.toString();
  }
}

class _Rel {
  final String rId;
  final String target;
  final String type;
  final String? targetMode;
  const _Rel(this.rId, this.target, this.type, [this.targetMode]);
}

/// 生成顶层 `_rels/.rels`:只指向 `word/document.xml`。
class TopLevelRelsBuilder {
  String build() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Relationships xmlns='
        '"http://schemas.openxmlformats.org/package/2006/relationships">\n'
        '  <Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
        'Target="word/document.xml"/>\n'
        '</Relationships>';
  }
}

/// 生成 `word/_rels/document.xml.rels`(基于 [RelsCollector])。
class DocumentRelsBuilder {
  final RelsCollector collector;
  DocumentRelsBuilder(this.collector);

  String build() => collector.buildDocumentRelsXml();
}
