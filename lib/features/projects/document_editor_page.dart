import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yjs_dart/yjs_dart.dart' as yjs;

import '../../data/repository.dart';
import '../../data/document_collaboration.dart';
import '../../domain/models.dart';
import '../messages/send_card_dialog.dart';
import 'markdown_editor_toolbar.dart';
import 'rich_document_view.dart';
import 'rich_document_toolbar.dart';
import 'rich_document_image_dialog.dart';
import 'rich_table_size_picker.dart';

class DocumentEditorPage extends StatefulWidget {
  const DocumentEditorPage(
      {required this.repository,
      required this.document,
      this.projectName = '',
      this.collaboration,
      super.key});
  final MagicChatRepository repository;
  final ProjectDocument document;
  final String projectName;
  final DocumentCollaborationSession? collaboration;

  @override
  State<DocumentEditorPage> createState() => _DocumentEditorPageState();
}

class _DocumentEditorPageState extends State<DocumentEditorPage> {
  late final TextEditingController _title =
      TextEditingController(text: widget.document.title);
  late final TextEditingController _body = TextEditingController();
  bool _preview = false;
  bool _saving = false;
  bool _reconnecting = false;
  yjs.YXmlText? _selectedRichText;
  final Map<String, Future<Uri?>> _documentImageUrls = {};

  @override
  void initState() {
    super.initState();
    if (widget.collaboration == null) {
      _loadDraft();
    } else {
      widget.collaboration!.addListener(_onCollaborationChanged);
      unawaited(widget.collaboration!.connect().catchError((_) {}));
    }
  }

  void _onCollaborationChanged() {
    if (!mounted) return;
    final session = widget.collaboration!;
    if (session.status != DocumentCollaborationStatus.synced) {
      _selectedRichText = null;
    }
    if (session.status == DocumentCollaborationStatus.synced &&
        _body.text != session.text) {
      final offset = _body.selection.baseOffset.clamp(0, session.text.length);
      _body.value = TextEditingValue(
          text: session.text,
          selection: TextSelection.collapsed(offset: offset));
    }
    setState(() {});
  }

  Future<void> _loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final draft =
        prefs.getString('magicchat.document.${widget.document.id}.draft');
    if (draft != null && mounted) {
      _body.text = draft;
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.collaboration?.removeListener(_onCollaborationChanged);
    unawaited(widget.collaboration?.close());
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.repository
          .updateCollaborativeDocumentTitle(widget.document.id, title);
      final collaborationSynced =
          widget.collaboration?.status == DocumentCollaborationStatus.synced;
      if (!collaborationSynced) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            'magicchat.document.${widget.document.id}.draft', _body.text);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(collaborationSynced ? '标题和正文已同步' : '标题已同步，正文已保存为本机草稿')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reconnect() async {
    final session = widget.collaboration;
    if (session == null || _reconnecting) return;
    setState(() => _reconnecting = true);
    try {
      await session.reconnect();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('重新连接失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _reconnecting = false);
    }
  }

  Future<void> _sendCard() {
    final title = createDocumentCardTitle(_title.text);
    final projectName = widget.projectName.trim();
    return showDialog<void>(
      context: context,
      builder: (_) => SendCardDialog(
        repository: widget.repository,
        cardTitle: title,
        cardDescription: projectName.isEmpty ? '项目文档' : '项目：$projectName',
        icon: Icons.description_outlined,
        onSend: (conversationId) => widget.repository.sendCard(
          conversationId,
          title: title,
          description: projectName.isEmpty ? '项目文档' : '项目: $projectName',
          url: documentCardPath(widget.document),
        ),
      ),
    );
  }

  Future<void> _editTextNode(yjs.YXmlText node) async {
    final session = widget.collaboration;
    if (session == null ||
        session.status != DocumentCollaborationStatus.synced) {
      return;
    }
    final result =
        await showDialog<({String text, Map<String, Object?> marks})>(
            context: context,
            builder: (_) => _TextBlockDialog(
                initialText: node.toString(),
                initialMarks: session.xmlTextMarks(node)));
    if (result != null && mounted) {
      session.replaceXmlText(node, result.text, marks: result.marks);
      setState(() => _selectedRichText = node);
    }
  }

  void _selectRichText(yjs.YXmlText? node) {
    if (!identical(_selectedRichText, node)) {
      setState(() => _selectedRichText = node);
    }
  }

  void _updateRichText(yjs.YXmlText node, String value) {
    widget.collaboration?.replaceXmlText(node, value);
  }

  void _toggleRichTextMark(String mark) {
    _updateSelectedRichMarks((marks) {
      if (marks[mark] == true) {
        marks.remove(mark);
      } else {
        marks[mark] = true;
      }
    });
  }

  void _setRichTextColor(String? color) {
    _updateSelectedRichMarks((marks) {
      final textStyle = marks['textStyle'] is Map
          ? Map<String, Object?>.from(marks['textStyle'] as Map)
          : <String, Object?>{};
      if (color == null) {
        textStyle.remove('color');
      } else {
        textStyle['color'] = color;
      }
      if (textStyle.isEmpty) {
        marks.remove('textStyle');
      } else {
        marks['textStyle'] = textStyle;
      }
    });
  }

  void _setRichTextHighlight(String? color) {
    _updateSelectedRichMarks((marks) {
      if (color == null) {
        marks.remove('highlight');
      } else {
        marks['highlight'] = {'color': color};
      }
    });
  }

  void _setRichTextAlignment(String alignment) {
    final session = widget.collaboration;
    final node = _selectedRichText;
    if (session == null || node == null) return;
    if (session.setXmlTextAlignment(node, alignment)) setState(() {});
  }

  Future<void> _editRichTextLink() async {
    final session = widget.collaboration;
    final node = _selectedRichText;
    if (session == null || node == null) return;
    final currentLink = session.xmlTextMarks(node)['link'];
    final currentHref = currentLink is Map && currentLink['href'] is String
        ? currentLink['href'] as String
        : '';
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _RichLinkDialog(initialValue: currentHref),
    );
    if (!mounted || value == null) return;
    final input = value.trim();
    final href = input.isEmpty ? null : normalizeRichDocumentLink(input);
    if (input.isNotEmpty && href == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('链接地址无效')));
      return;
    }
    _updateSelectedRichMarks((marks) {
      if (href == null) {
        marks.remove('link');
      } else {
        marks['link'] = {'href': href};
      }
    });
  }

  void _updateSelectedRichMarks(
      void Function(Map<String, Object?> marks) update) {
    final session = widget.collaboration;
    final node = _selectedRichText;
    if (session == null || node == null) return;
    final marks = Map<String, Object?>.from(session.xmlTextMarks(node));
    update(marks);
    session.stopUndoCapture();
    session.replaceXmlText(node, node.toString(), marks: marks);
    setState(() {});
  }

  void _clearRichTextFormatting() {
    final session = widget.collaboration;
    final node = _selectedRichText;
    if (session == null || node == null) return;
    session.stopUndoCapture();
    session.replaceXmlText(node, node.toString(), marks: const {});
    setState(() {});
  }

  void _transformRichTextBlock(RichDocumentBlockType type) {
    final session = widget.collaboration;
    final node = _selectedRichText;
    if (session == null || node == null) return;
    final replacement = session.transformXmlTextBlock(node, type);
    if (replacement != null) setState(() => _selectedRichText = replacement);
  }

  void _insertRichParagraph({required bool after}) {
    final session = widget.collaboration;
    final node = _selectedRichText;
    if (session == null || node == null) return;
    final inserted = session.insertParagraphNear(node, after: after);
    if (inserted != null) setState(() => _selectedRichText = inserted);
  }

  void _deleteRichTextBlock() {
    final session = widget.collaboration;
    final node = _selectedRichText;
    if (session == null || node == null) return;
    final replacement = session.deleteXmlTextBlock(node);
    setState(() => _selectedRichText = replacement);
  }

  void _undoRichDocument() {
    final session = widget.collaboration;
    if (session == null || !session.undo()) return;
    setState(() => _selectedRichText = null);
  }

  void _redoRichDocument() {
    final session = widget.collaboration;
    if (session == null || !session.redo()) return;
    setState(() => _selectedRichText = null);
  }

  Future<void> _insertRichTable() async {
    final session = widget.collaboration;
    if (session == null ||
        session.status != DocumentCollaborationStatus.synced) {
      return;
    }
    final size = await showDialog<RichTableSize>(
        context: context, builder: (_) => const RichTableSizePicker());
    if (!mounted || size == null) return;
    final firstCell = session.insertTable(
        near: _selectedRichText, rows: size.rows, columns: size.columns);
    if (firstCell != null) setState(() => _selectedRichText = firstCell);
  }

  Future<void> _insertRichImage() async {
    final session = widget.collaboration;
    if (session == null ||
        session.status != DocumentCollaborationStatus.synced) {
      return;
    }
    final image = session.insertDocumentImage(near: _selectedRichText);
    if (image == null) return;
    setState(() => _selectedRichText = null);
    await _editRichImage(image);
  }

  Future<void> _editRichImage(yjs.YXmlElement image) async {
    final session = widget.collaboration;
    if (session == null ||
        session.status != DocumentCollaborationStatus.synced) {
      return;
    }
    final result = await showDialog<RichDocumentImageDialogResult>(
      context: context,
      builder: (_) => RichDocumentImageDialog(
          repository: widget.repository,
          initialValue: session.documentImageAttributes(image)),
    );
    if (!mounted || result == null) return;
    if (result.deleted) {
      session.deleteDocumentImage(image);
      setState(() => _selectedRichText = null);
      return;
    }
    final attributes = result.attributes;
    if (attributes != null && session.updateDocumentImage(image, attributes)) {
      final fileId = attributes.fileId;
      if (fileId != null) _documentImageUrls.remove(fileId);
      setState(() {});
    }
  }

  Future<Uri?> _resolveDocumentImage(String fileId) => _documentImageUrls
      .putIfAbsent(fileId, () => widget.repository.attachmentUrl(fileId));

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
        title: TextField(
            controller: _title,
            decoration: const InputDecoration(
                border: InputBorder.none, hintText: '文档标题')),
        actions: [
          if (widget.document.documentType != 'document')
            IconButton(
                tooltip: _preview ? '编辑' : '预览',
                onPressed: () => setState(() => _preview = !_preview),
                icon: Icon(
                    _preview ? Icons.edit_outlined : Icons.preview_outlined)),
          if (widget.document.documentType == 'document' &&
              widget.collaboration != null)
            IconButton(
                tooltip: '追加内容块',
                onPressed: widget.collaboration!.status ==
                        DocumentCollaborationStatus.synced
                    ? _appendBlock
                    : null,
                icon: const Icon(Icons.add_box_outlined)),
          IconButton(
              key: const ValueKey('document-send-card'),
              tooltip: '发送到会话',
              onPressed: _sendCard,
              icon: const Icon(Icons.send_outlined)),
          if (widget.collaboration?.status == DocumentCollaborationStatus.error)
            IconButton(
                tooltip: '重新连接',
                onPressed: _reconnecting ? null : _reconnect,
                icon: _reconnecting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync)),
          IconButton(
              tooltip: '保存标题',
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined))
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: widget.document.documentType == 'document' &&
                widget.collaboration != null
            ? Column(children: [
                Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      Icon(
                          widget.collaboration!.status ==
                                  DocumentCollaborationStatus.error
                              ? Icons.error_outline
                              : Icons.visibility_outlined,
                          size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(widget.collaboration!.status ==
                                  DocumentCollaborationStatus.error
                              ? '协作连接已断开 · 点击右上角重新连接'
                              : '富文档安全编辑 · 长按文本块可编辑，可追加标准内容块')),
                    ])),
                const SizedBox(height: 8),
                RichDocumentToolbar(
                    enabled: widget.collaboration!.status ==
                        DocumentCollaborationStatus.synced,
                    canUndo: widget.collaboration!.canUndo,
                    canRedo: widget.collaboration!.canRedo,
                    onUndo: _undoRichDocument,
                    onRedo: _redoRichDocument,
                    onInsertTable: _insertRichTable,
                    onInsertImage: _insertRichImage,
                    onInsert: (type) =>
                        unawaited(_appendBlock(initialType: type))),
                if (_selectedRichText case final selected?
                    when widget.collaboration!.status ==
                        DocumentCollaborationStatus.synced) ...[
                  const SizedBox(height: 6),
                  RichDocumentInlineToolbar(
                    blockType: widget.collaboration!.xmlTextBlockType(selected),
                    marks: widget.collaboration!.xmlTextMarks(selected),
                    alignment: widget.collaboration!.xmlTextAlignment(selected),
                    onToggleMark: _toggleRichTextMark,
                    onTextColor: _setRichTextColor,
                    onHighlight: _setRichTextHighlight,
                    onAlignment: _setRichTextAlignment,
                    onEditLink: _editRichTextLink,
                    onClearFormatting: _clearRichTextFormatting,
                    onTransform: _transformRichTextBlock,
                    onInsertBefore: () => _insertRichParagraph(after: false),
                    onInsertAfter: () => _insertRichParagraph(after: true),
                    onDelete: _deleteRichTextBlock,
                    onDone: () => _selectRichText(null),
                  ),
                ],
                const SizedBox(height: 8),
                Expanded(
                    child: RichDocumentView(
                        body: widget.collaboration!.body,
                        selectedText: _selectedRichText,
                        onSelectText: widget.collaboration!.status ==
                                DocumentCollaborationStatus.synced
                            ? _selectRichText
                            : null,
                        onTextChanged: widget.collaboration!.status ==
                                DocumentCollaborationStatus.synced
                            ? _updateRichText
                            : null,
                        imageUrlResolver: _resolveDocumentImage,
                        onEditImage: widget.collaboration!.status ==
                                DocumentCollaborationStatus.synced
                            ? (image) => unawaited(_editRichImage(image))
                            : null,
                        onEditText: _editTextNode)),
              ])
            : Column(children: [
                MarkdownEditorToolbar(
                    controller: _body,
                    enabled: !_preview &&
                        widget.collaboration?.status !=
                            DocumentCollaborationStatus.connecting,
                    onChanged: _onBodyChanged),
                const SizedBox(height: 8),
                Expanded(
                    child: _preview
                        ? Markdown(
                            data: _body.text.isEmpty ? '暂无内容' : _body.text,
                            padding: EdgeInsets.zero)
                        : TextField(
                            key: const ValueKey('markdown-body-editor'),
                            controller: _body,
                            expands: true,
                            maxLines: null,
                            minLines: null,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: const InputDecoration(
                                hintText: '输入 Markdown 或文档内容…',
                                border: OutlineInputBorder()),
                            readOnly: widget.collaboration?.status ==
                                DocumentCollaborationStatus.connecting,
                            onChanged: _onBodyChanged)),
              ]),
      ),
      bottomNavigationBar: SafeArea(
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(
                    widget.collaboration == null
                        ? '${_body.text.length} 字'
                        : '${widget.collaboration!.text.length} 字 · $_collaborationLabel',
                    style: Theme.of(context).textTheme.bodySmall)
              ]))));

  void _onBodyChanged(String value) {
    widget.collaboration?.replaceText(value);
    setState(() {});
  }

  Future<void> _appendBlock({RichDocumentBlockType? initialType}) async {
    final session = widget.collaboration;
    if (session == null ||
        session.status != DocumentCollaborationStatus.synced) {
      return;
    }
    final controller = TextEditingController();
    var type = initialType ?? RichDocumentBlockType.paragraph;
    final result = await showDialog<
            ({String text, RichDocumentBlockType type})>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
                    title: const Text('追加内容块'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      DropdownButtonFormField<RichDocumentBlockType>(
                          initialValue: type,
                          decoration: const InputDecoration(labelText: '块类型'),
                          items: RichDocumentBlockType.values
                              .map((value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(_richBlockLabel(value))))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => type = value);
                            }
                          }),
                      const SizedBox(height: 8),
                      TextField(
                          controller: controller,
                          autofocus: true,
                          minLines: 2,
                          maxLines: 5,
                          decoration: const InputDecoration(
                              labelText: '正文', border: OutlineInputBorder()))
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('取消')),
                      FilledButton(
                          onPressed: () => Navigator.pop(
                              context, (text: controller.text, type: type)),
                          child: const Text('追加'))
                    ])));
    controller.dispose();
    if (!mounted || result == null) return;
    if (!session.appendTextBlock(result.text, type: result.type)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('正文尚未同步，无法追加内容块')));
    }
  }

  String get _collaborationLabel {
    final session = widget.collaboration!;
    final status = switch (session.status) {
      DocumentCollaborationStatus.disconnected => '未连接',
      DocumentCollaborationStatus.connecting => '连接中',
      DocumentCollaborationStatus.synced => '已同步',
      DocumentCollaborationStatus.error => '连接失败',
    };
    return session.collaboratorCount > 0
        ? '$status · ${session.collaboratorCount} 人在线'
        : status;
  }
}

String createDocumentCardTitle(String value) {
  const prefix = '文档 - ';
  const maxLength = 256;
  final title = value.trim().isEmpty ? '无标题文档' : value.trim();
  final remaining = maxLength - prefix.characters.length;
  if (title.characters.length <= remaining) return '$prefix$title';
  return '$prefix${title.characters.take(remaining - 1).join()}…';
}

String documentCardPath(ProjectDocument document) {
  final type = document.documentType == 'markdown' ? 'markdown' : 'document';
  return '/documents/$type/${Uri.encodeComponent(document.id)}';
}

String? normalizeRichDocumentLink(String value) {
  final input = value.trim();
  if (input.isEmpty || RegExp(r'\s').hasMatch(input)) return null;
  final explicit = Uri.tryParse(input);
  if (explicit?.hasScheme == true) {
    final scheme = explicit!.scheme.toLowerCase();
    if ((scheme == 'http' || scheme == 'https') && explicit.host.isNotEmpty) {
      return explicit.toString();
    }
    if ((scheme == 'mailto' || scheme == 'tel') &&
        explicit.path.trim().isNotEmpty) {
      return explicit.toString();
    }
    return null;
  }
  final https = Uri.tryParse('https://$input');
  return https?.host.isNotEmpty == true ? https.toString() : null;
}

class _RichLinkDialog extends StatefulWidget {
  const _RichLinkDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_RichLinkDialog> createState() => _RichLinkDialogState();
}

class _RichLinkDialogState extends State<_RichLinkDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('编辑链接'),
        content: TextField(
          key: const ValueKey('rich-document-link-field'),
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
              labelText: '链接地址',
              hintText: 'https://example.com',
              border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          if (widget.initialValue.isNotEmpty)
            TextButton(
                onPressed: () => Navigator.pop(context, ''),
                child: const Text('移除链接')),
          FilledButton(
              onPressed: () => Navigator.pop(context, _controller.text),
              child: const Text('应用')),
        ],
      );
}

class _TextBlockDialog extends StatefulWidget {
  const _TextBlockDialog(
      {required this.initialText, required this.initialMarks});

  final String initialText;
  final Map<String, Object?> initialMarks;

  @override
  State<_TextBlockDialog> createState() => _TextBlockDialogState();
}

class _TextBlockDialogState extends State<_TextBlockDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);
  late final Map<String, Object?> _marks =
      Map<String, Object?>.from(widget.initialMarks);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('编辑文本块'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: _controller,
              autofocus: true,
              minLines: 2,
              maxLines: 8,
              decoration: const InputDecoration(
                  hintText: '输入文本', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          Align(
              alignment: Alignment.centerLeft,
              child: Wrap(spacing: 8, runSpacing: 4, children: [
                _markChip('粗体', 'bold'),
                _markChip('斜体', 'italic'),
                _markChip('删除线', 'strike'),
                _markChip('代码', 'code'),
              ])),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(
                  context, (text: _controller.text, marks: Map.of(_marks))),
              child: const Text('保存')),
        ],
      );

  Widget _markChip(String label, String key) => FilterChip(
        label: Text(label),
        selected: _marks[key] == true,
        onSelected: (selected) => setState(() {
          if (selected) {
            _marks[key] = true;
          } else {
            _marks.remove(key);
          }
        }),
      );
}

String _richBlockLabel(RichDocumentBlockType type) => switch (type) {
      RichDocumentBlockType.paragraph => '段落',
      RichDocumentBlockType.heading1 => '一级标题',
      RichDocumentBlockType.heading2 => '二级标题',
      RichDocumentBlockType.heading3 => '三级标题',
      RichDocumentBlockType.bulletList => '无序列表',
      RichDocumentBlockType.orderedList => '有序列表',
      RichDocumentBlockType.taskList => '任务列表',
      RichDocumentBlockType.blockquote => '引用',
      RichDocumentBlockType.codeBlock => '代码块',
    };
