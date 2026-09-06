import 'package:flutter/material.dart';

import '../../data/document_collaboration.dart';
import '../../domain/rich_document_format.dart';
import 'rich_document_block_background.dart';

/// 富文档的 block 工具栏。
///
/// Flutter 当前以安全的 block 追加方式编辑来自 Tiptap 的 XML 文档；工具栏
/// 将 block 类型直接暴露在编辑区，避免用户必须先打开“追加内容块”对话框。
class RichDocumentToolbar extends StatelessWidget {
  const RichDocumentToolbar({
    required this.enabled,
    required this.onInsert,
    this.canUndo = false,
    this.canRedo = false,
    this.onUndo,
    this.onRedo,
    this.formatPainterActive = false,
    this.onFormatPainter,
    this.onClearFormatting,
    this.onInsertHorizontalRule,
    this.onInsertTable,
    this.onInsertImage,
    super.key,
  });

  final bool enabled;
  final ValueChanged<RichDocumentBlockType> onInsert;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final bool formatPainterActive;
  final VoidCallback? onFormatPainter;
  final VoidCallback? onClearFormatting;
  final VoidCallback? onInsertHorizontalRule;
  final VoidCallback? onInsertTable;
  final VoidCallback? onInsertImage;

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
                  IconButton(
                      tooltip: '撤销',
                      onPressed: enabled && canUndo ? onUndo : null,
                      icon: const Icon(Icons.undo, size: 20)),
                  IconButton(
                      tooltip: '重做',
                      onPressed: enabled && canRedo ? onRedo : null,
                      icon: const Icon(Icons.redo, size: 20)),
                  const VerticalDivider(width: 12, indent: 10, endIndent: 10),
                  IconButton(
                      tooltip: formatPainterActive ? '取消格式刷' : '格式刷',
                      isSelected: formatPainterActive,
                      onPressed: enabled ? onFormatPainter : null,
                      icon: const Icon(Icons.format_paint, size: 20),
                      selectedIcon: const Icon(Icons.format_paint, size: 20)),
                  IconButton(
                      tooltip: '清除格式',
                      onPressed: enabled ? onClearFormatting : null,
                      icon: const Icon(Icons.format_clear, size: 20)),
                  const VerticalDivider(width: 12, indent: 10, endIndent: 10),
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
                  const VerticalDivider(width: 12, indent: 10, endIndent: 10),
                  IconButton(
                      tooltip: '插入分割线',
                      onPressed: enabled ? onInsertHorizontalRule : null,
                      icon: const Icon(Icons.horizontal_rule, size: 20)),
                  IconButton(
                      tooltip: '插入表格',
                      onPressed: enabled ? onInsertTable : null,
                      icon: const Icon(Icons.table_chart_outlined, size: 20)),
                  IconButton(
                      tooltip: '插入图片',
                      onPressed: enabled ? onInsertImage : null,
                      icon: const Icon(Icons.add_photo_alternate_outlined,
                          size: 20)),
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
    required this.alignment,
    this.blockBackground,
    required this.onToggleMark,
    required this.onTextColor,
    required this.onHighlight,
    required this.onAlignment,
    this.onBlockBackground,
    required this.onEditLink,
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
  final String alignment;
  final String? blockBackground;
  final ValueChanged<String> onToggleMark;
  final ValueChanged<String?> onTextColor;
  final ValueChanged<String?> onHighlight;
  final ValueChanged<String> onAlignment;
  final ValueChanged<String?>? onBlockBackground;
  final VoidCallback onEditLink;
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
                        value: RichDocumentBlockType.bulletList,
                        child: Text('无序列表')),
                    PopupMenuItem(
                        value: RichDocumentBlockType.orderedList,
                        child: Text('有序列表')),
                    PopupMenuItem(
                        value: RichDocumentBlockType.taskList,
                        child: Text('任务列表')),
                    PopupMenuItem(
                        value: RichDocumentBlockType.blockquote,
                        child: Text('引用')),
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
                _colorTool(context, Icons.format_color_text, '字体颜色',
                    _nestedMarkValue('textStyle', 'color'), onTextColor),
                _colorTool(context, Icons.format_color_fill, '文字背景色',
                    _nestedMarkValue('highlight', 'color'), onHighlight),
                _blockBackgroundTool(context),
                _alignmentTool(),
                IconButton(
                    tooltip: '链接',
                    isSelected: _linkHref != null,
                    onPressed: blockType == RichDocumentBlockType.codeBlock
                        ? null
                        : onEditLink,
                    icon: const Icon(Icons.link, size: 20),
                    selectedIcon: const Icon(Icons.link, size: 20)),
                IconButton(
                    tooltip: '清除格式',
                    onPressed: marks.isEmpty ||
                            blockType == RichDocumentBlockType.codeBlock
                        ? null
                        : onClearFormatting,
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

  Widget _colorTool(BuildContext context, IconData icon, String label,
      String? selected, ValueChanged<String?> onSelected) {
    final enabled = blockType != RichDocumentBlockType.codeBlock;
    return PopupMenuButton<String>(
      tooltip: label,
      enabled: enabled,
      onSelected: (value) => onSelected(value.isEmpty ? null : value),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: '',
          child: Row(children: [
            Icon(Icons.restart_alt,
                size: 18, color: Theme.of(context).colorScheme.onSurface),
            const SizedBox(width: 10),
            Text(label == '字体颜色' ? '默认颜色' : '无背景色'),
          ]),
        ),
        for (final color in _documentColors)
          PopupMenuItem(
            value: color.value,
            child: Row(children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                    color: Color(
                        int.parse('FF${color.value.substring(1)}', radix: 16)),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black12)),
              ),
              const SizedBox(width: 10),
              Text(color.label),
              if (selected == color.value) ...[
                const Spacer(),
                const Icon(Icons.check, size: 18),
              ],
            ]),
          ),
      ],
      icon: Icon(icon,
          size: 20,
          color: selected == null
              ? null
              : Color(int.parse('FF${selected.substring(1)}', radix: 16))),
    );
  }

  Widget _blockBackgroundTool(BuildContext context) => IconButton(
        tooltip: '段落背景',
        onPressed: onBlockBackground == null
            ? null
            : () async {
                final value = await _showBlockBackgroundPicker(context);
                if (value != null) {
                  onBlockBackground!(value.isEmpty ? null : value);
                }
              },
        icon: Icon(Icons.format_color_fill,
            size: 20,
            color: richDocumentBlockBackgroundDisplayColor(blockBackground)),
      );

  Future<String?> _showBlockBackgroundPicker(BuildContext context) =>
      showDialog<String>(
        context: context,
        builder: (dialogContext) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 336),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, ''),
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('无段落背景'),
                  ),
                ),
                const Divider(height: 8),
                Semantics(
                  label: '段落背景色板',
                  child: SizedBox(
                    width: 320,
                    child: AspectRatio(
                      aspectRatio: 2,
                      child: GridView.builder(
                        key: const ValueKey(
                            'rich-document-block-background-grid'),
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 10,
                          crossAxisSpacing: 2,
                          mainAxisSpacing: 2,
                        ),
                        itemCount: richDocumentBlockBackgroundColors.length,
                        itemBuilder: (context, index) {
                          final color =
                              richDocumentBlockBackgroundColors[index];
                          final display =
                              richDocumentBlockBackgroundDisplayColor(
                                  color.value)!;
                          final selected = blockBackground == color.value;
                          return Tooltip(
                            message: color.label,
                            child: Semantics(
                              key: ValueKey(
                                  'rich-document-block-background-swatch-$index'),
                              button: true,
                              selected: selected,
                              label: '段落背景：${color.label}',
                              child: InkResponse(
                                onTap: () =>
                                    Navigator.pop(dialogContext, color.value),
                                containedInkWell: true,
                                customBorder: const CircleBorder(),
                                child: Center(
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: display,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: selected
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                            : Colors.black12,
                                        width: selected ? 3 : 1,
                                      ),
                                    ),
                                    child: selected
                                        ? Icon(Icons.check,
                                            size: 14,
                                            color:
                                                richDocumentBlockForegroundColor(
                                                    display))
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _alignmentTool() => PopupMenuButton<String>(
        tooltip: '文本对齐',
        enabled: blockType != RichDocumentBlockType.codeBlock,
        onSelected: onAlignment,
        itemBuilder: (_) => const [
          PopupMenuItem(
              value: 'left',
              child: ListTile(
                  leading: Icon(Icons.format_align_left), title: Text('左对齐'))),
          PopupMenuItem(
              value: 'center',
              child: ListTile(
                  leading: Icon(Icons.format_align_center),
                  title: Text('居中对齐'))),
          PopupMenuItem(
              value: 'right',
              child: ListTile(
                  leading: Icon(Icons.format_align_right), title: Text('右对齐'))),
        ],
        icon: Icon(
            switch (alignment) {
              'center' => Icons.format_align_center,
              'right' => Icons.format_align_right,
              _ => Icons.format_align_left,
            },
            size: 20),
      );

  String? _nestedMarkValue(String mark, String key) {
    final value = marks[mark];
    final nested = value is Map ? value[key] : null;
    return nested is String && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(nested)
        ? nested.toLowerCase()
        : null;
  }

  String? get _linkHref {
    final link = marks['link'];
    final href = link is Map ? link['href'] : null;
    return href is String && href.trim().isNotEmpty ? href.trim() : null;
  }

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
        RichDocumentBlockType.bulletList => Icons.format_list_bulleted,
        RichDocumentBlockType.orderedList => Icons.format_list_numbered,
        RichDocumentBlockType.taskList => Icons.checklist,
        RichDocumentBlockType.blockquote => Icons.format_quote,
        RichDocumentBlockType.codeBlock => Icons.code,
        _ => Icons.notes_outlined,
      };
}

const _documentColors = [
  (label: '黑色', value: '#111827'),
  (label: '灰色', value: '#6b7280'),
  (label: '红色', value: '#dc2626'),
  (label: '橙色', value: '#ea580c'),
  (label: '黄色', value: '#ca8a04'),
  (label: '绿色', value: '#16a34a'),
  (label: '蓝色', value: '#2563eb'),
  (label: '靛蓝', value: '#4f46e5'),
  (label: '紫色', value: '#9333ea'),
  (label: '粉色', value: '#db2777'),
];
