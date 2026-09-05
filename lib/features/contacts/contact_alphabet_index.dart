import 'dart:async';

import 'package:flutter/material.dart';

import 'contact_directory_model.dart';

class ContactAlphabetIndex extends StatefulWidget {
  const ContactAlphabetIndex({required this.onSelected, super.key});

  final ValueChanged<String> onSelected;

  @override
  State<ContactAlphabetIndex> createState() => _ContactAlphabetIndexState();
}

class _ContactAlphabetIndexState extends State<ContactAlphabetIndex> {
  String? _active;
  Timer? _hideTimer;

  void _select(String label) {
    if (_active != label) setState(() => _active = label);
    widget.onSelected(label);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _active = null);
    });
  }

  void _selectAt(double y, double height) {
    if (height <= 0) return;
    final index = (y / height * contactIndexLabels.length)
        .floor()
        .clamp(0, contactIndexLabels.length - 1);
    _select(contactIndexLabels[index]);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragDown: (details) =>
              _selectAt(details.localPosition.dy, constraints.maxHeight),
          onVerticalDragUpdate: (details) =>
              _selectAt(details.localPosition.dy, constraints.maxHeight),
          child: Column(
            children: contactIndexLabels
                .map((label) => Expanded(
                      child: Semantics(
                        button: true,
                        label: '跳转到 $label',
                        child: InkWell(
                          key: ValueKey('contact-index-$label'),
                          onTap: () => _select(label),
                          child: SizedBox(
                            width: 24,
                            child: Center(
                              child: Text(label,
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: _active == label
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                      color: _active == label
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant)),
                            ),
                          ),
                        ),
                      ),
                    ))
                .toList(growable: false),
          ),
        ),
      );
}
