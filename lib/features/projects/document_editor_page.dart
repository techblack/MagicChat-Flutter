import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/repository.dart';
import '../../domain/models.dart';

class DocumentEditorPage extends StatefulWidget {
  const DocumentEditorPage(
      {required this.repository, required this.document, super.key});
  final MagicChatRepository repository;
  final ProjectDocument document;

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
    _loadDraft();
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'magicchat.document.${widget.document.id}.draft', _body.text);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('标题已同步，正文已保存为本机草稿')));
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
                onChanged: (_) => setState(() {})),
      ),
      bottomNavigationBar: SafeArea(
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text('${_body.text.length} 字',
                    style: Theme.of(context).textTheme.bodySmall)
              ]))));
}
