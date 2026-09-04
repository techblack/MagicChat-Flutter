# yjs_dart（MagicChat fork）

此目录保留 `yjs_dart` 1.1.15 的 Dart 实现，并补齐 MagicChat 富文档协作所需的
`YXmlElement`、`YXmlText` 与 Yjs XML 类型解码。上游来源：
<https://pub.dev/packages/yjs_dart>（1.1.15，原始许可证见 [LICENSE](LICENSE)）。

改动集中在 `lib/src/types/`，用于让 Flutter 端读写与 Web/Desktop Tiptap
`Y.XmlFragment("body")` 相同的 paragraph/text 节点；其余 CRDT 协议代码保持上游实现。
