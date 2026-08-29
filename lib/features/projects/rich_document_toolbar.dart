import 'package:flutter/material.dart';

import '../../data/document_collaboration.dart';

/// 富文档的 block 工具栏。
///
/// Flutter 当前以安全的 block 追加方式编辑来自 Tiptap 的 XML 文档；工具栏
/// 将 block 类型直接暴露在编辑区，避免用户必须先打开“追加内容块”对话框。
class RichDocumentToolbar extends StatelessWidget {
  const RichDocumentToolbar({
    required this.enabled,
    required this.onInsert,
    super.key,
  });

  final bool enabled;
  final ValueChanged<RichDocumentBlockType> onInsert;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: '富文档格式工具栏',
        child: SizedBox(
          height: 48,
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  _tool(context, Icons.notes_outlined, '段落',
                      RichDocumentBlockType.paragraph),
                  _tool(context, Icons.title, '一级标题',
                      RichDocumentBlockType.heading1),
                  _tool(context, Icons.format_list_bulleted, '无序列表',
                      RichDocumentBlockType.bulletList),
                  _tool(context, Icons.format_list_numbered, '有序列表',
                      RichDocumentBlockType.orderedList),
                  _tool(context, Icons.checklist, '任务列表',
                      RichDocumentBlockType.taskList),
                  const VerticalDivider(width: 12, indent: 10, endIndent: 10),
                  _tool(context, Icons.format_quote, '引用',
                      RichDocumentBlockType.blockquote),
                  _tool(context, Icons.code, '代码块',
                      RichDocumentBlockType.codeBlock),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _tool(BuildContext context, IconData icon, String label,
          RichDocumentBlockType type) =>
      IconButton(
        tooltip: label,
        onPressed: enabled ? () => onInsert(type) : null,
        icon: Icon(icon, size: 20),
        visualDensity: VisualDensity.compact,
      );
}
