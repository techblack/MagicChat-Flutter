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

/// 选中文本块后的原位格式与块操作工具栏。
class RichDocumentInlineToolbar extends StatelessWidget {
  const RichDocumentInlineToolbar({
    required this.blockType,
    required this.marks,
    required this.onToggleMark,
    required this.onClearFormatting,
    required this.onTransform,
    required this.onInsertBefore,
    required this.onInsertAfter,
    required this.onDelete,
    required this.onDone,
    super.key,
  });

  final RichDocumentBlockType? blockType;
  final Map<String, Object?> marks;
  final ValueChanged<String> onToggleMark;
  final VoidCallback onClearFormatting;
  final ValueChanged<RichDocumentBlockType> onTransform;
  final VoidCallback onInsertBefore;
  final VoidCallback onInsertAfter;
  final VoidCallback onDelete;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: '当前文本块格式工具栏',
        child: Material(
          key: const ValueKey('rich-document-inline-toolbar'),
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 48,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(children: [
                PopupMenuButton<RichDocumentBlockType>(
                  tooltip: '块类型',
                  enabled: blockType != null,
                  onSelected: onTransform,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: RichDocumentBlockType.paragraph,
                        child: Text('正文')),
                    PopupMenuItem(
                        value: RichDocumentBlockType.heading1,
                        child: Text('一级标题')),
                    PopupMenuItem(
                        value: RichDocumentBlockType.heading2,
                        child: Text('二级标题')),
                    PopupMenuItem(
                        value: RichDocumentBlockType.heading3,
                        child: Text('三级标题')),
                    PopupMenuItem(
                        value: RichDocumentBlockType.codeBlock,
                        child: Text('代码块')),
                  ],
                  icon: Icon(_blockIcon(blockType), size: 20),
                ),
                const VerticalDivider(width: 8, indent: 10, endIndent: 10),
                _markTool(Icons.format_bold, '粗体', 'bold'),
                _markTool(Icons.format_italic, '斜体', 'italic'),
                _markTool(Icons.format_underline, '下划线', 'underline'),
                _markTool(Icons.format_strikethrough, '删除线', 'strike'),
                _markTool(Icons.code, '行内代码', 'code'),
                IconButton(
                    tooltip: '清除格式',
                    onPressed: marks.isEmpty ? null : onClearFormatting,
                    icon: const Icon(Icons.format_clear, size: 20)),
                const VerticalDivider(width: 8, indent: 10, endIndent: 10),
                IconButton(
                    tooltip: '在上方插入一行',
                    onPressed: onInsertBefore,
                    icon: const Icon(Icons.vertical_align_top, size: 20)),
                IconButton(
                    tooltip: '在下方插入一行',
                    onPressed: onInsertAfter,
                    icon: const Icon(Icons.vertical_align_bottom, size: 20)),
                IconButton(
                    tooltip: '删除当前块',
                    onPressed: onDelete,
                    icon: Icon(Icons.delete_outline,
                        size: 20, color: Theme.of(context).colorScheme.error)),
                IconButton(
                    tooltip: '完成编辑',
                    onPressed: onDone,
                    icon: const Icon(Icons.check, size: 20)),
              ]),
            ),
          ),
        ),
      );

  Widget _markTool(IconData icon, String label, String mark) => IconButton(
        tooltip: label,
        isSelected: marks[mark] == true,
        onPressed: blockType == RichDocumentBlockType.codeBlock
            ? null
            : () => onToggleMark(mark),
        icon: Icon(icon, size: 20),
        selectedIcon: Icon(icon, size: 20),
      );

  IconData _blockIcon(RichDocumentBlockType? type) => switch (type) {
        RichDocumentBlockType.heading1 ||
        RichDocumentBlockType.heading2 ||
        RichDocumentBlockType.heading3 =>
          Icons.title,
        RichDocumentBlockType.codeBlock => Icons.code,
        _ => Icons.notes_outlined,
      };
}
