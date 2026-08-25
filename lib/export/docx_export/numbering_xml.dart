/// 生成 `word/numbering.xml`:bullet + decimal 编号定义。
///
/// 设计对齐 dev-doc.md 第 9.5 节。
///
/// 编号实例:
///   - numId=1 → abstractNumId=0(bullet,• / ◦ / ▪ / ...)
///   - numId=2 → abstractNumId=1(decimal,1. / a. / i. / ...)
///
/// 嵌套用 ilvl 表示层级(0=顶层,1=第二层,...),与 [DocumentXmlBuilder]
/// 生成 `numPr` 时的 `w:ilvl` 对应。
class NumberingXmlBuilder {
  String build() {
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <!-- abstractNumId=0:bullet -->
  <w:abstractNum w:abstractNumId="0">
    <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/>
      <w:lvlText w:val="•"/><w:lvlJc w:val="left"/>
      <w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl>
    <w:lvl w:ilvl="1"><w:start w:val="1"/><w:numFmt w:val="bullet"/>
      <w:lvlText w:val="◦"/><w:lvlJc w:val="left"/>
      <w:pPr><w:ind w:left="1440" w:hanging="360"/></w:pPr></w:lvl>
    <w:lvl w:ilvl="2"><w:start w:val="1"/><w:numFmt w:val="bullet"/>
      <w:lvlText w:val="▪"/><w:lvlJc w:val="left"/>
      <w:pPr><w:ind w:left="2160" w:hanging="360"/></w:pPr></w:lvl>
    <w:lvl w:ilvl="3"><w:start w:val="1"/><w:numFmt w:val="bullet"/>
      <w:lvlText w:val="•"/><w:lvlJc w:val="left"/>
      <w:pPr><w:ind w:left="2880" w:hanging="360"/></w:pPr></w:lvl>
    <w:lvl w:ilvl="4"><w:start w:val="1"/><w:numFmt w:val="bullet"/>
      <w:lvlText w:val="◦"/><w:lvlJc w:val="left"/>
      <w:pPr><w:ind w:left="3600" w:hanging="360"/></w:pPr></w:lvl>
  </w:abstractNum>

  <!-- abstractNumId=1:decimal -->
  <w:abstractNum w:abstractNumId="1">
    <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/>
      <w:lvlText w:val="%1."/><w:lvlJc w:val="left"/>
      <w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl>
    <w:lvl w:ilvl="1"><w:start w:val="1"/><w:numFmt w:val="lowerLetter"/>
      <w:lvlText w:val="%2."/><w:lvlJc w:val="left"/>
      <w:pPr><w:ind w:left="1440" w:hanging="360"/></w:pPr></w:lvl>
    <w:lvl w:ilvl="2"><w:start w:val="1"/><w:numFmt w:val="lowerRoman"/>
      <w:lvlText w:val="%3."/><w:lvlJc w:val="left"/>
      <w:pPr><w:ind w:left="2160" w:hanging="360"/></w:pPr></w:lvl>
    <w:lvl w:ilvl="3"><w:start w:val="1"/><w:numFmt w:val="decimal"/>
      <w:lvlText w:val="%4."/><w:lvlJc w:val="left"/>
      <w:pPr><w:ind w:left="2880" w:hanging="360"/></w:pPr></w:lvl>
    <w:lvl w:ilvl="4"><w:start w:val="1"/><w:numFmt w:val="lowerLetter"/>
      <w:lvlText w:val="%5."/><w:lvlJc w:val="left"/>
      <w:pPr><w:ind w:left="3600" w:hanging="360"/></w:pPr></w:lvl>
  </w:abstractNum>

  <!-- 编号实例:numId → abstractNumId -->
  <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
  <w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>
</w:numbering>''';
  }
}
