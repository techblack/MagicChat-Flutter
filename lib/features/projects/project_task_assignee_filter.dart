import 'package:flutter/material.dart';
import 'package:pinyin/pinyin.dart';

import '../../data/repository.dart';
import '../../domain/models.dart';
import '../shared/user_facing_error.dart';

class ProjectTaskAssigneeFilter extends StatefulWidget {
  const ProjectTaskAssigneeFilter({
    required this.repository,
    required this.projectId,
    required this.selectedUserIds,
    required this.onChanged,
    super.key,
  });

  final MagicChatRepository repository;
  final String projectId;
  final List<String> selectedUserIds;
  final ValueChanged<List<String>> onChanged;

  @override
  State<ProjectTaskAssigneeFilter> createState() =>
      _ProjectTaskAssigneeFilterState();
}

class _ProjectTaskAssigneeFilterState extends State<ProjectTaskAssigneeFilter> {
  Future<List<ProjectMember>>? _membersFuture;
  List<ProjectMember> _members = const [];

  Future<List<ProjectMember>> _loadMembers({bool reload = false}) {
    if (reload || _membersFuture == null) {
      _membersFuture = widget.repository.projectMembers(widget.projectId).then((
        members,
      ) {
        final seen = <String>{};
        final available = members
            .where(
              (member) =>
                  member.id.isNotEmpty &&
                  (member.status.isEmpty || member.status == 'active') &&
                  seen.add(member.id),
            )
            .toList(growable: false);
        if (mounted) setState(() => _members = available);
        return available;
      });
    }
    return _membersFuture!;
  }

  String get _label {
    final selected = widget.selectedUserIds.toSet();
    if (selected.isEmpty) return '筛选负责人';
    if (selected.length == 1) {
      for (final member in _members) {
        if (selected.contains(member.id)) return member.displayName;
      }
    }
    return '负责人 ${selected.length}';
  }

  Future<void> _showPicker() async {
    final selected = await showDialog<List<String>>(
      context: context,
      builder: (context) => _ProjectTaskAssigneeDialog(
        initialUserIds: widget.selectedUserIds,
        loadMembers: _loadMembers,
      ),
    );
    if (selected != null && mounted) widget.onChanged(selected);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: OutlinedButton.icon(
          onPressed: _showPicker,
          icon: const Icon(Icons.person_search_outlined, size: 19),
          label: Text(_label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      );
}

class _ProjectTaskAssigneeDialog extends StatefulWidget {
  const _ProjectTaskAssigneeDialog({
    required this.initialUserIds,
    required this.loadMembers,
  });

  final List<String> initialUserIds;
  final Future<List<ProjectMember>> Function({bool reload}) loadMembers;

  @override
  State<_ProjectTaskAssigneeDialog> createState() =>
      _ProjectTaskAssigneeDialogState();
}

class _ProjectTaskAssigneeDialogState
    extends State<_ProjectTaskAssigneeDialog> {
  late final Set<String> _selected = widget.initialUserIds.toSet();
  late Future<List<ProjectMember>> _future = widget.loadMembers();
  String _query = '';

  void _retry() => setState(() {
        _future = widget.loadMembers(reload: true);
      });

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('筛选负责人'),
        content: SizedBox(
          width: 440,
          height: 460,
          child: Column(
            children: [
              TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '搜索项目成员',
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<List<ProjectMember>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('成员加载失败：${userFacingError(snapshot.error!)}'),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _retry,
                              icon: const Icon(Icons.refresh),
                              label: const Text('重试'),
                            ),
                          ],
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final query = _query.trim().toLowerCase();
                    final members = query.isEmpty
                        ? snapshot.data!
                        : snapshot.data!
                            .where(
                              (member) =>
                                  _memberSearchText(member).contains(query),
                            )
                            .toList(growable: false);
                    if (members.isEmpty) {
                      return Center(
                        child: Text(query.isEmpty ? '暂无可选成员' : '没有匹配的项目成员'),
                      );
                    }
                    return ListView.builder(
                      itemCount: members.length,
                      itemBuilder: (context, index) {
                        final member = members[index];
                        return CheckboxListTile(
                          value: _selected.contains(member.id),
                          title: Text(member.displayName),
                          subtitle:
                              member.email.isEmpty ? null : Text(member.email),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (checked) => setState(() {
                            if (checked == true) {
                              _selected.add(member.id);
                            } else {
                              _selected.remove(member.id);
                            }
                          }),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: () => setState(_selected.clear),
              child: const Text('清除'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _selected.toList()),
            child: const Text('应用'),
          ),
        ],
      );
}

String _memberSearchText(ProjectMember member) {
  final source = '${member.displayName} ${member.name} ${member.nickname} '
      '${member.email}';
  final pinyin = PinyinHelper.getPinyinE(
    source,
    separator: '',
    format: PinyinFormat.WITHOUT_TONE,
    defPinyin: '#',
  );
  final initials = PinyinHelper.getShortPinyin(source);
  return '$source $pinyin $initials'.toLowerCase();
}
