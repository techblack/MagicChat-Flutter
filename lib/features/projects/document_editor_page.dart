import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/repository.dart';
import '../../data/document_collaboration.dart';
import '../../domain/models.dart';

class DocumentEditorPage extends StatefulWidget {
  const DocumentEditorPage(
      {required this.repository,
      required this.document,
      this.collaboration,
      super.key});
  final MagicChatRepository repository;
  final ProjectDocument document;
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

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
        title: TextField(
            controller: _title,
            decoration: const InputDecoration(
                border: InputBorder.none, hintText: '文档标题')),
        actions: [
          IconButton(
              tooltip: _preview ? '编辑' : '预览',
              onPressed: () => setState(() => _preview = !_preview),
              icon: Icon(
                  _preview ? Icons.edit_outlined : Icons.preview_outlined)),
          IconButton(
              tooltip: '保存标题',
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined))
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _preview
            ? Markdown(
                data: _body.text.isEmpty ? '暂无内容' : _body.text,
                padding: EdgeInsets.zero)
            : TextField(
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
                onChanged: (value) {
                  widget.collaboration?.replaceText(value);
                  setState(() {});
                }),
      ),
      bottomNavigationBar: SafeArea(
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(
                    widget.collaboration == null
                        ? '${_body.text.length} 字'
                        : '${_body.text.length} 字 · $_collaborationLabel',
                    style: Theme.of(context).textTheme.bodySmall)
              ]))));

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
