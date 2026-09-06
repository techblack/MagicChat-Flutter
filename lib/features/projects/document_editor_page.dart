import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:yjs_dart/yjs_dart.dart' as yjs;

import '../../data/repository.dart';
import '../../data/document_collaboration.dart';
import '../../data/rich_document_paste.dart';
import '../../domain/models.dart';
import '../messages/send_card_dialog.dart';
import '../shared/user_facing_error.dart';
import 'markdown_editor_toolbar.dart';
import 'rich_document_view.dart';
import 'rich_document_toolbar.dart';
import 'rich_document_horizontal_rule.dart';
import 'rich_document_image_dialog.dart';
import 'rich_table_size_picker.dart';
import 'document_export.dart';

class DocumentEditorPage extends StatefulWidget {
  const DocumentEditorPage(
      {required this.repository,
      required this.document,
      this.projectName = '',
      this.collaboration,
      this.readRichClipboard,
      super.key});
  final MagicChatRepository repository;
  final ProjectDocument document;
  final String projectName;
  final DocumentCollaborationSession? collaboration;
  final Future<RichDocumentClipboardContent?> Function()? readRichClipboard;

  @override
  State<DocumentEditorPage> createState() => _DocumentEditorPageState();
}

class _DocumentEditorPageState extends State<DocumentEditorPage> {
  late final TextEditingController _title =
      TextEditingController(text: widget.document.title);
  late final TextEditingController _body = TextEditingController();
  late String _lastSavedTitle = widget.document.title;
  String _lastSavedBody = '';
  bool _preview = false;
  bool _saving = false;
  bool _reconnecting = false;
  yjs.YXmlText? _selectedRichText;
  TextSelection _selectedRichTextSelection =
      const TextSelection.collapsed(offset: 0);
  Map<String, Object?> _storedRichMarks = {};
  Map<String, Object?>? _formatPainterMarks;
  String? _formatPainterAlignment;
  yjs.YXmlText? _formatPainterSource;
  RichDocumentTextRange? _formatPainterSourceRange;
  Timer? _formatPainterApplyTimer;
  final Map<String, Future<Uri?>> _documentImageUrls = {};
  ClipboardEvents? _clipboardEvents;

  @override
  void initState() {
    super.initState();
    if (widget.collaboration == null) {
      _loadDraft();
    } else {
      widget.collaboration!.addListener(_onCollaborationChanged);
      _clipboardEvents = ClipboardEvents.instance;
      _clipboardEvents?.registerPasteEventListener(_onWebPaste);
      unawaited(widget.collaboration!.connect().catchError((_) {}));
    }
  }

  void _onWebPaste(ClipboardReadEvent event) {
    if (_selectedRichText == null ||
        widget.collaboration?.status != DocumentCollaborationStatus.synced) {
      return;
    }
    unawaited(_pasteRichDocument(read: () async {
      final reader = await event.getClipboardReader();
      return readRichDocumentClipboardReader(reader);
    }));
  }

  void _onCollaborationChanged() {
    if (!mounted) return;
    final session = widget.collaboration!;
    if (session.status != DocumentCollaborationStatus.synced) {
      _selectedRichText = null;
      _selectedRichTextSelection = const TextSelection.collapsed(offset: 0);
      _storedRichMarks = {};
      _formatPainterMarks = null;
      _formatPainterAlignment = null;
      _formatPainterSource = null;
      _formatPainterSourceRange = null;
      _formatPainterApplyTimer?.cancel();
      _formatPainterApplyTimer = null;
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
      _lastSavedBody = draft;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _formatPainterApplyTimer?.cancel();
    _clipboardEvents?.unregisterPasteEventListener(_onWebPaste);
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
        _lastSavedTitle = title;
        _lastSavedBody = _body.text;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(collaborationSynced ? '标题和正文已同步' : '标题已同步，正文已保存为本机草稿')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('保存失败：${userFacingError(error)}')));
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
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('重新连接失败：${userFacingError(error)}')));
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

  Future<void> _exportDocument() async {
    final body = widget.collaboration?.text ?? _body.text;
    final bytes = documentExportBytes(title: _title.text, body: body);
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: '导出文档',
        fileName: documentExportFileName(widget.document),
        type: FileType.custom,
        allowedExtensions:
            widget.document.documentType == 'markdown' ? ['md'] : ['txt'],
        bytes: bytes,
      );
      if (path != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('文档已导出')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导出失败：${userFacingError(error)}')));
      }
    }
  }

  Future<void> _showDocumentInfo() async {
    final collaboration = widget.collaboration;
    final type =
        widget.document.documentType == 'markdown' ? 'Markdown' : '富文本文档';
    final status = collaboration == null ? '本机草稿' : _collaborationLabel;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('文档信息'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(
                    _title.text.trim().isEmpty ? '未命名文档' : _title.text.trim()),
                subtitle: Text(type)),
            ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('所属项目'),
                subtitle: Text(widget.projectName.trim().isEmpty
                    ? '未提供项目名称'
                    : widget.projectName.trim())),
            ListTile(
                leading: const Icon(Icons.sync_outlined),
                title: const Text('同步状态'),
                subtitle: Text(status)),
            if (collaboration != null)
              ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: const Text('在线协作者'),
                  subtitle: Text('${collaboration.collaboratorCount} 人')),
            ListTile(
                leading: const Icon(Icons.schema_outlined),
                title: const Text('文档结构版本'),
                subtitle: Text('v${widget.document.schemaVersion}')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭')),
        ],
      ),
    );
  }

  bool get _hasUnsavedChanges => hasUnsavedDocumentChanges(
      title: _title.text,
      savedTitle: _lastSavedTitle,
      body: _body.text,
      savedBody: _lastSavedBody);

  Future<void> _confirmLeave() async {
    if (!_hasUnsavedChanges || !mounted) return;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('文档尚未保存'),
        content: const Text('当前修改还没有同步完成，确定要离开吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('继续编辑')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('离开')),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
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
      _selectRichText(node);
    }
  }

  void _selectRichText(yjs.YXmlText? node) {
    final session = widget.collaboration;
    if (session == null) return;
    final offset = node?.length ?? 0;
    final selection = TextSelection.collapsed(offset: offset);
    setState(() {
      _selectedRichText = node;
      _selectedRichTextSelection = selection;
      _storedRichMarks = node == null
          ? {}
          : session.xmlTextMarksForRange(node, offset, offset);
    });
  }

  void _updateRichTextSelection(yjs.YXmlText node, TextSelection selection) {
    final session = widget.collaboration;
    if (session == null || !identical(node, _selectedRichText)) return;
    final start = selection.start;
    final end = selection.end;
    final painterMarks = _formatPainterMarks;
    final painterAlignment = _formatPainterAlignment;
    final sourceRange = _formatPainterSourceRange;
    final isSource = identical(node, _formatPainterSource) &&
        sourceRange?.start == start &&
        sourceRange?.end == end;
    _formatPainterApplyTimer?.cancel();
    _formatPainterApplyTimer = null;
    if (!selection.isCollapsed &&
        painterMarks != null &&
        painterAlignment != null &&
        !isSource) {
      setState(() {
        _selectedRichTextSelection = selection;
        _storedRichMarks = session.xmlTextMarksForRange(node, start, end);
      });
      _formatPainterApplyTimer =
          Timer(const Duration(milliseconds: 80), _applyRichFormatPainter);
      return;
    }
    setState(() {
      _selectedRichTextSelection = selection;
      _storedRichMarks = session.xmlTextMarksForRange(node, start, end);
    });
  }

  void _applyRichFormatPainter() {
    if (!mounted) return;
    final session = widget.collaboration;
    final node = _selectedRichText;
    final selection = _selectedRichTextSelection;
    final marks = _formatPainterMarks;
    final alignment = _formatPainterAlignment;
    final sourceRange = _formatPainterSourceRange;
    final isSource = identical(node, _formatPainterSource) &&
        sourceRange?.start == selection.start &&
        sourceRange?.end == selection.end;
    if (session == null ||
        node == null ||
        marks == null ||
        alignment == null ||
        selection.isCollapsed ||
        isSource) {
      _formatPainterApplyTimer = null;
      return;
    }
    session.replaceXmlTextMarks(node, selection.start, selection.end, marks);
    session.setXmlTextAlignment(node, alignment);
    setState(() {
      _storedRichMarks = Map<String, Object?>.from(marks);
      _formatPainterMarks = null;
      _formatPainterAlignment = null;
      _formatPainterSource = null;
      _formatPainterSourceRange = null;
      _formatPainterApplyTimer = null;
    });
  }

  void _toggleRichFormatPainter() {
    final session = widget.collaboration;
    final source = _selectedRichText;
    if (session == null ||
        session.status != DocumentCollaborationStatus.synced) {
      return;
    }
    if (_formatPainterMarks != null) {
      _formatPainterApplyTimer?.cancel();
      setState(() {
        _formatPainterMarks = null;
        _formatPainterAlignment = null;
        _formatPainterSource = null;
        _formatPainterSourceRange = null;
        _formatPainterApplyTimer = null;
      });
      return;
    }
    _formatPainterApplyTimer?.cancel();
    _formatPainterApplyTimer = null;
    if (source == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先选择格式来源文本块')));
      return;
    }
    final selection = _selectedRichTextSelection;
    final marks = selection.isCollapsed
        ? Map<String, Object?>.from(_storedRichMarks)
        : session.xmlTextMarksAt(source, selection.start, preferRight: true);
    marks.remove('link');
    setState(() {
      _formatPainterMarks = marks;
      _formatPainterAlignment = session.xmlTextAlignment(source);
      _formatPainterSource = source;
      _formatPainterSourceRange = (start: selection.start, end: selection.end);
    });
  }

  void _clearRichFormatPainter() {
    if (_formatPainterMarks == null && _formatPainterSource == null) return;
    _formatPainterApplyTimer?.cancel();
    setState(() {
      _formatPainterMarks = null;
      _formatPainterAlignment = null;
      _formatPainterSource = null;
      _formatPainterSourceRange = null;
      _formatPainterApplyTimer = null;
    });
  }

  void _updateRichText(yjs.YXmlText node, String value,
      TextSelection previousSelection, TextSelection selection) {
    final session = widget.collaboration;
    if (session == null) return;
    session.replaceXmlTextPreservingMarks(
      node,
      value,
      _storedRichMarks,
      replacedRange: (
        start: previousSelection.start,
        end: previousSelection.end,
      ),
      selectionAfter: selection.start,
    );
    _selectedRichTextSelection = selection;
  }

  void _toggleRichTextMark(String mark) {
    _setSelectedRichMark(mark, _storedRichMarks[mark] == true ? null : true);
  }

  void _setRichTextColor(String? color) {
    _setSelectedRichMark('textStyle', color == null ? null : {'color': color});
  }

  void _setRichTextHighlight(String? color) {
    _setSelectedRichMark('highlight', color == null ? null : {'color': color});
  }

  void _setSelectedRichMark(String mark, Object? value,
      {RichDocumentTextRange? range}) {
    final session = widget.collaboration;
    final node = _selectedRichText;
    if (session == null || node == null) return;
    final selection = range == null
        ? _selectedRichTextSelection
        : TextSelection(baseOffset: range.start, extentOffset: range.end);
    if (selection.isCollapsed) {
      setState(() {
        if (value == null) {
          _storedRichMarks.remove(mark);
        } else {
          _storedRichMarks[mark] = value;
        }
      });
      return;
    }
    if (session.updateXmlTextMarks(
        node, selection.start, selection.end, {mark: value})) {
      setState(() {
        _storedRichMarks =
            session.xmlTextMarksForRange(node, selection.start, selection.end);
      });
    }
  }

  void _setRichTextAlignment(String alignment) {
    final session = widget.collaboration;
    final node = _selectedRichText;
    if (session == null || node == null) return;
    if (session.setXmlTextAlignment(node, alignment)) setState(() {});
  }

  void _setRichBlockBackground(String? color) {
    final session = widget.collaboration;
    final node = _selectedRichText;
    if (session == null || node == null) return;
    if (session.setXmlTextBlockBackground(node, color)) setState(() {});
  }

  void _editRichTable(RichDocumentTableAction action) {
    final session = widget.collaboration;
    final node = _selectedRichText;
    if (session == null || node == null) return;
    final result = session.editTable(node, action);
    if (result.changed) _selectRichText(result.selection);
  }

  Future<void> _pasteRichDocument(
      {Future<RichDocumentClipboardContent?> Function()? read}) async {
    final session = widget.collaboration;
    if (session == null ||
        session.status != DocumentCollaborationStatus.synced) {
      return;
    }
    try {
      final content = await (read ??
          widget.readRichClipboard ??
          readRichDocumentClipboard)();
      if (!mounted) return;
      final result = content == null
          ? (changed: false, selection: null)
          : session.pasteRichDocument(content, near: _selectedRichText);
      if (!result.changed) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('剪贴板中没有可粘贴的内容')));
        return;
      }
      _selectRichText(result.selection);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('粘贴失败：${userFacingError(error)}')));
      }
    }
  }

  Future<void> _editRichTextLink() async {
    final session = widget.collaboration;
    final node = _selectedRichText;
    if (session == null || node == null) return;
    final currentLink = _storedRichMarks['link'];
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
    final selection = _selectedRichTextSelection;
    final linkRange = selection.isCollapsed
        ? session.xmlTextLinkRange(node, selection.start)
        : null;
    _setSelectedRichMark('link', href == null ? null : {'href': href},
        range: linkRange);
  }

  void _clearRichTextFormatting() {
    final session = widget.collaboration;
    final node = _selectedRichText;
    if (session == null || node == null) return;
    final selection = _selectedRichTextSelection;
    if (!selection.isCollapsed) {
      session
          .replaceXmlTextMarks(node, selection.start, selection.end, const {});
    }
    _formatPainterApplyTimer?.cancel();
    setState(() {
      _storedRichMarks = {};
      _formatPainterMarks = null;
      _formatPainterAlignment = null;
      _formatPainterSource = null;
      _formatPainterSourceRange = null;
      _formatPainterApplyTimer = null;
    });
  }

  void _transformRichTextBlock(RichDocumentBlockType type) {
    final session = widget.collaboration;
    final node = _selectedRichText;
    if (session == null || node == null) return;
    final replacement = session.transformXmlTextBlock(node, type);
    if (replacement != null) _selectRichText(replacement);
  }

  void _insertRichParagraph({required bool after}) {
    final session = widget.collaboration;
    final node = _selectedRichText;
    if (session == null || node == null) return;
    final inserted = session.insertParagraphNear(node, after: after);
    if (inserted != null) _selectRichText(inserted);
  }

  void _deleteRichTextBlock() {
    final session = widget.collaboration;
    final node = _selectedRichText;
    if (session == null || node == null) return;
    final replacement = session.deleteXmlTextBlock(node);
    _selectRichText(replacement);
  }

  void _undoRichDocument() {
    final session = widget.collaboration;
    if (session == null || !session.undo()) return;
    _formatPainterApplyTimer?.cancel();
    setState(() {
      _selectedRichText = null;
      _selectedRichTextSelection = const TextSelection.collapsed(offset: 0);
      _storedRichMarks = {};
      _formatPainterMarks = null;
      _formatPainterAlignment = null;
      _formatPainterSource = null;
      _formatPainterSourceRange = null;
      _formatPainterApplyTimer = null;
    });
  }

  void _redoRichDocument() {
    final session = widget.collaboration;
    if (session == null || !session.redo()) return;
    _formatPainterApplyTimer?.cancel();
    setState(() {
      _selectedRichText = null;
      _selectedRichTextSelection = const TextSelection.collapsed(offset: 0);
      _storedRichMarks = {};
      _formatPainterMarks = null;
      _formatPainterAlignment = null;
      _formatPainterSource = null;
      _formatPainterSourceRange = null;
      _formatPainterApplyTimer = null;
    });
  }

  void _insertRichHorizontalRule() {
    final session = widget.collaboration;
    if (session == null ||
        session.status != DocumentCollaborationStatus.synced) {
      return;
    }
    final rule = session.insertHorizontalRule(near: _selectedRichText);
    if (rule != null) _selectRichText(null);
  }

  Future<void> _editRichHorizontalRule(yjs.YXmlElement rule) async {
    final session = widget.collaboration;
    if (session == null ||
        session.status != DocumentCollaborationStatus.synced) {
      return;
    }
    final result = await showDialog<RichDocumentHorizontalRuleDialogResult>(
      context: context,
      builder: (_) => RichDocumentHorizontalRuleDialog(
        initialValue: session.horizontalRuleAttributes(rule),
      ),
    );
    if (!mounted || result == null) return;
    if (result.deleted) {
      session.deleteHorizontalRule(rule);
    } else {
      session.updateHorizontalRule(rule, result.attributes);
    }
    setState(() {});
  }

  void _setRichTaskChecked(yjs.YXmlElement item, bool checked) {
    final session = widget.collaboration;
    if (session != null && session.setTaskItemChecked(item, checked)) {
      setState(() {});
    }
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
    if (firstCell != null) _selectRichText(firstCell);
  }

  Future<void> _insertRichImage() async {
    final session = widget.collaboration;
    if (session == null ||
        session.status != DocumentCollaborationStatus.synced) {
      return;
    }
    final image = session.insertDocumentImage(near: _selectedRichText);
    if (image == null) return;
    _selectRichText(null);
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
      _selectRichText(null);
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
  Widget build(BuildContext context) => PopScope<void>(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_confirmLeave());
      },
      child: Scaffold(
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
                    icon: Icon(_preview
                        ? Icons.edit_outlined
                        : Icons.preview_outlined)),
              IconButton(
                  key: const ValueKey('document-info'),
                  tooltip: '文档信息',
                  onPressed: _showDocumentInfo,
                  icon: const Icon(Icons.info_outline)),
              IconButton(
                  key: const ValueKey('document-export'),
                  tooltip: '导出文档',
                  onPressed: _exportDocument,
                  icon: const Icon(Icons.download_outlined)),
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
              if (widget.collaboration?.status ==
                  DocumentCollaborationStatus.error)
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
          body: Focus(
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.keyV &&
                  _selectedRichText != null &&
                  _clipboardEvents == null &&
                  (HardwareKeyboard.instance.isControlPressed ||
                      HardwareKeyboard.instance.isMetaPressed)) {
                unawaited(_pasteRichDocument());
                return KeyEventResult.handled;
              }
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape &&
                  _formatPainterMarks != null) {
                _clearRichFormatPainter();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: widget.document.documentType == 'document' &&
                      widget.collaboration != null
                  ? Column(children: [
                      Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .secondaryContainer,
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
                                    : _formatPainterMarks != null
                                        ? '格式刷已启用 · 选择目标文本应用格式'
                                        : '富文档安全编辑 · 长按文本块可编辑，可追加标准内容块')),
                          ])),
                      const SizedBox(height: 8),
                      RichDocumentToolbar(
                          enabled: widget.collaboration!.status ==
                              DocumentCollaborationStatus.synced,
                          canUndo: widget.collaboration!.canUndo,
                          canRedo: widget.collaboration!.canRedo,
                          formatPainterActive: _formatPainterMarks != null,
                          onUndo: _undoRichDocument,
                          onRedo: _redoRichDocument,
                          onFormatPainter: _toggleRichFormatPainter,
                          onClearFormatting: _clearRichTextFormatting,
                          onPaste: () => unawaited(_pasteRichDocument()),
                          onInsertHorizontalRule: _insertRichHorizontalRule,
                          onInsertTable: _insertRichTable,
                          onInsertImage: _insertRichImage,
                          onInsert: (type) =>
                              unawaited(_appendBlock(initialType: type))),
                      if (_selectedRichText case final selected?
                          when widget.collaboration!.status ==
                              DocumentCollaborationStatus.synced) ...[
                        const SizedBox(height: 6),
                        RichDocumentInlineToolbar(
                          blockType:
                              widget.collaboration!.xmlTextBlockType(selected),
                          marks: _storedRichMarks,
                          alignment:
                              widget.collaboration!.xmlTextAlignment(selected),
                          blockBackground: widget.collaboration!
                              .xmlTextBlockBackground(selected),
                          onToggleMark: _toggleRichTextMark,
                          onTextColor: _setRichTextColor,
                          onHighlight: _setRichTextHighlight,
                          onAlignment: _setRichTextAlignment,
                          onBlockBackground: _setRichBlockBackground,
                          onTableAction: widget.collaboration!
                                  .isXmlTextInEditableTable(selected)
                              ? _editRichTable
                              : null,
                          onEditLink: _editRichTextLink,
                          onClearFormatting: _clearRichTextFormatting,
                          onTransform: _transformRichTextBlock,
                          onInsertBefore: () =>
                              _insertRichParagraph(after: false),
                          onInsertAfter: () =>
                              _insertRichParagraph(after: true),
                          onDelete: _deleteRichTextBlock,
                          onDone: () => _selectRichText(null),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Expanded(
                          child: RichDocumentView(
                              body: widget.collaboration!.body,
                              selectedText: _selectedRichText,
                              selectedTextSelection: _selectedRichTextSelection,
                              onSelectText: widget.collaboration!.status ==
                                      DocumentCollaborationStatus.synced
                                  ? _selectRichText
                                  : null,
                              onTextChanged: widget.collaboration!.status ==
                                      DocumentCollaborationStatus.synced
                                  ? _updateRichText
                                  : null,
                              onTextSelectionChanged:
                                  widget.collaboration!.status == DocumentCollaborationStatus.synced
                                      ? _updateRichTextSelection
                                      : null,
                              imageUrlResolver: _resolveDocumentImage,
                              onEditHorizontalRule: widget.collaboration!.status ==
                                      DocumentCollaborationStatus.synced
                                  ? (rule) =>
                                      unawaited(_editRichHorizontalRule(rule))
                                  : null,
                              onTaskChecked: widget.collaboration!.status ==
                                      DocumentCollaborationStatus.synced
                                  ? _setRichTaskChecked
                                  : null,
                              onEditImage: widget.collaboration!.status == DocumentCollaborationStatus.synced
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
                                  data:
                                      _body.text.isEmpty ? '暂无内容' : _body.text,
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
          ),
          bottomNavigationBar: SafeArea(
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child:
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text(
                        widget.collaboration == null
                            ? '${_body.text.length} 字'
                            : '${widget.collaboration!.text.length} 字 · $_collaborationLabel',
                        style: Theme.of(context).textTheme.bodySmall)
                  ])))));

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

bool hasUnsavedDocumentChanges({
  required String title,
  required String savedTitle,
  required String body,
  required String savedBody,
}) =>
    title.trim() != savedTitle.trim() || body != savedBody;

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
