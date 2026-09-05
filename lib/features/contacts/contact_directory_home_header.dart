import 'package:flutter/material.dart';

import 'contact_directory_model.dart';

class ContactDirectoryHomeEntry {
  const ContactDirectoryHomeEntry(
      {required this.category, required this.count});

  final ContactDirectoryCategory category;
  final int count;
}

class ContactDirectoryHomeHeader extends StatelessWidget {
  const ContactDirectoryHomeHeader(
      {required this.entries, required this.onPressed, super.key});

  final List<ContactDirectoryHomeEntry> entries;
  final ValueChanged<ContactDirectoryCategory> onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var index = 0; index < entries.length; index++) ...[
              if (index > 0) const Divider(height: 1, indent: 68),
              _ContactDirectoryEntryTile(
                entry: entries[index],
                color: _entryColor(entries[index].category, colors),
                icon: _entryIcon(entries[index].category),
                onTap: () => onPressed(entries[index].category),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _entryIcon(ContactDirectoryCategory category) => switch (category) {
        ContactDirectoryCategory.newFriends => Icons.person_add_alt_1_outlined,
        ContactDirectoryCategory.myApps => Icons.smart_toy_outlined,
        ContactDirectoryCategory.allApps => Icons.apps_outlined,
        ContactDirectoryCategory.joinedGroups => Icons.groups_outlined,
        ContactDirectoryCategory.publicGroups => Icons.public_outlined,
      };

  Color _entryColor(ContactDirectoryCategory category, ColorScheme colors) =>
      switch (category) {
        ContactDirectoryCategory.newFriends => Colors.orange.shade600,
        ContactDirectoryCategory.myApps => colors.primary,
        ContactDirectoryCategory.allApps => Colors.indigo.shade500,
        ContactDirectoryCategory.joinedGroups => Colors.amber.shade700,
        ContactDirectoryCategory.publicGroups => Colors.blue.shade600,
      };
}

class _ContactDirectoryEntryTile extends StatelessWidget {
  const _ContactDirectoryEntryTile(
      {required this.entry,
      required this.color,
      required this.icon,
      required this.onTap});

  final ContactDirectoryHomeEntry entry;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        key: ValueKey(entry.category == ContactDirectoryCategory.newFriends
            ? 'friend-management-button'
            : 'contact-category-${entry.category.name}'),
        onTap: onTap,
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: Colors.white, size: 25),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.category.label,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${entry.count} 个',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                    ]),
              ),
              const Icon(Icons.chevron_right),
            ]),
          ),
        ),
      );
}
