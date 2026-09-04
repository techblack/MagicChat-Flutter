# Flutter 富文档 block 工具栏阶段验证

## 覆盖范围

- 富文档协作页在同步状态下展示“富文档格式工具栏”。
- 工具栏提供段落、一级标题、无序/有序/任务列表、引用和代码块入口。
- 点击入口复用 `DocumentCollaborationSession.appendTextBlock`，仍只向 XML 文档末尾追加标准 Tiptap block，不覆盖远端已有 marks、表格和图片。
- 已有段落和标题文本可长按进入编辑对话框，可切换粗体、斜体、删除线和代码 marks；回写时保留当前 Yjs 文本叶子的可见 marks。
- 连接中或连接失败时按钮禁用，避免在未建立 Yjs 状态时产生本地假更新。

## 自动化验证

| 命令 | 结果 | 覆盖 |
| --- | --- | --- |
| `dart format lib/features/projects/rich_document_toolbar.dart lib/features/projects/document_editor_page.dart test/rich_document_toolbar_test.dart test/realtime_store_test.dart` | 通过 | 代码格式 |
| `flutter test --no-pub test/rich_document_toolbar_test.dart test/realtime_store_test.dart` | 通过，19 项 | 工具栏回调/禁用状态及实时选择题状态回归 |

已有 `test/document_collaboration_test.dart` 继续覆盖 block XML 生成、文本编辑和 Yjs 同步；完整原位富文本编辑器仍作为后续阶段。
