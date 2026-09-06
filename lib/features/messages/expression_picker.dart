import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/message_cache_store_types.dart';

const expressionUsageMaxAge = Duration(days: 30);
const frequentExpressionLimit = 8;

class ExpressionItem {
  const ExpressionItem(this.value, this.label);

  final String value;
  final String label;
}

class ExpressionUsage {
  const ExpressionUsage({
    required this.value,
    required this.count,
    required this.lastUsedAt,
  });

  final String value;
  final int count;
  final int lastUsedAt;

  Map<String, Object> toJson() => {
        'value': value,
        'count': count,
        'last_used_at': lastUsedAt,
      };
}

const allExpressionItems = <ExpressionItem>[
  ExpressionItem('😂', '笑哭'),
  ExpressionItem('🤣', '笑到打滚'),
  ExpressionItem('😄', '大笑'),
  ExpressionItem('😅', '流汗笑'),
  ExpressionItem('😆', '眯眼笑'),
  ExpressionItem('😀', '笑脸'),
  ExpressionItem('😃', '开心'),
  ExpressionItem('😁', '露齿笑'),
  ExpressionItem('😊', '微笑'),
  ExpressionItem('🙂', '浅笑'),
  ExpressionItem('😉', '眨眼'),
  ExpressionItem('🥰', '喜爱'),
  ExpressionItem('😍', '花痴'),
  ExpressionItem('😘', '飞吻'),
  ExpressionItem('🤗', '拥抱'),
  ExpressionItem('🤩', '星星眼'),
  ExpressionItem('😏', '坏笑'),
  ExpressionItem('🤭', '偷笑'),
  ExpressionItem('😜', '眨眼吐舌'),
  ExpressionItem('🙃', '倒脸'),
  ExpressionItem('😋', '好吃'),
  ExpressionItem('🤪', '滑稽'),
  ExpressionItem('😎', '酷'),
  ExpressionItem('🤫', '嘘'),
  ExpressionItem('🤔', '思考'),
  ExpressionItem('🙄', '翻白眼'),
  ExpressionItem('🤦', '捂脸'),
  ExpressionItem('🤷', '摊手'),
  ExpressionItem('😑', '面无表情'),
  ExpressionItem('😬', '尴尬'),
  ExpressionItem('🫠', '融化'),
  ExpressionItem('🤡', '小丑'),
  ExpressionItem('😭', '大哭'),
  ExpressionItem('🥺', '可怜'),
  ExpressionItem('🥹', '忍住眼泪'),
  ExpressionItem('😢', '哭'),
  ExpressionItem('😔', '沮丧'),
  ExpressionItem('🥲', '含泪微笑'),
  ExpressionItem('😮‍💨', '叹气'),
  ExpressionItem('😳', '脸红'),
  ExpressionItem('😡', '愤怒'),
  ExpressionItem('😤', '生气'),
  ExpressionItem('😱', '惊恐'),
  ExpressionItem('🤯', '爆炸头'),
  ExpressionItem('🥳', '庆祝'),
  ExpressionItem('😴', '睡觉'),
  ExpressionItem('🥱', '打哈欠'),
  ExpressionItem('🫡', '敬礼'),
  ExpressionItem('👍', '赞'),
  ExpressionItem('👏', '鼓掌'),
  ExpressionItem('🙏', '拜托'),
  ExpressionItem('👌', '好的'),
  ExpressionItem('💪', '加油'),
  ExpressionItem('✌️', '胜利'),
  ExpressionItem('🤝', '握手'),
  ExpressionItem('👎', '踩'),
  ExpressionItem('👋', '挥手'),
  ExpressionItem('👀', '关注'),
  ExpressionItem('❤️', '爱心'),
  ExpressionItem('🫶', '爱心手势'),
  ExpressionItem('🔥', '火'),
  ExpressionItem('🎉', '庆祝礼花'),
  ExpressionItem('✅', '完成'),
  ExpressionItem('❌', '错误'),
];

const defaultFrequentExpressionValues = <String>[
  '😂',
  '😊',
  '😭',
  '👍',
  '❤️',
  '👏',
  '🙏',
  '🎉',
];

final _expressionsByValue = <String, ExpressionItem>{
  for (final item in allExpressionItems) item.value: item,
};

List<ExpressionUsage> normalizeExpressionUsage(Object? value, DateTime now) {
  if (value is! List) return const [];
  final cutoff = now.subtract(expressionUsageMaxAge).millisecondsSinceEpoch;
  return value
      .whereType<Map>()
      .map((item) {
        final expression = item['value'];
        final count = item['count'];
        final lastUsedAt = item['last_used_at'];
        if (expression is! String ||
            !_expressionsByValue.containsKey(expression) ||
            count is! num ||
            !count.isFinite ||
            count <= 0 ||
            count % 1 != 0 ||
            lastUsedAt is! num ||
            !lastUsedAt.isFinite ||
            lastUsedAt % 1 != 0 ||
            lastUsedAt < cutoff) {
          return null;
        }
        return ExpressionUsage(
          value: expression,
          count: count.toInt(),
          lastUsedAt: lastUsedAt.toInt(),
        );
      })
      .whereType<ExpressionUsage>()
      .toList(growable: false);
}

List<ExpressionUsage> updateExpressionUsage(
  List<ExpressionUsage> usage,
  String value,
  DateTime now,
) {
  final normalized = normalizeExpressionUsage(
    usage.map((item) => item.toJson()).toList(growable: false),
    now,
  );
  final byValue = <String, ExpressionUsage>{
    for (final item in normalized) item.value: item,
  };
  final previous = byValue[value];
  byValue[value] = ExpressionUsage(
    value: value,
    count: (previous?.count ?? 0) + 1,
    lastUsedAt: now.millisecondsSinceEpoch,
  );
  return byValue.values.toList(growable: false);
}

List<ExpressionItem> frequentExpressionItems(List<ExpressionUsage> usage) {
  final used = usage.toList()
    ..sort((left, right) {
      final count = right.count.compareTo(left.count);
      return count != 0 ? count : right.lastUsedAt.compareTo(left.lastUsedAt);
    });
  final usedItems = used
      .map((item) => _expressionsByValue[item.value])
      .whereType<ExpressionItem>()
      .toList(growable: false);
  final usedValues = usedItems.map((item) => item.value).toSet();
  final fallbacks = <ExpressionItem>[
    ...defaultFrequentExpressionValues
        .map((value) => _expressionsByValue[value])
        .whereType<ExpressionItem>(),
    ...allExpressionItems,
  ];
  final fallbackValues = <String>{};
  return <ExpressionItem>[
    ...usedItems,
    ...fallbacks.where(
      (item) =>
          !usedValues.contains(item.value) && fallbackValues.add(item.value),
    ),
  ].take(frequentExpressionLimit).toList(growable: false);
}

String expressionUsageStorageKey(MessageCacheScope? scope) {
  if (scope == null) return 'magicchat.expression-picker.usage.v1.local';
  String encode(String value) =>
      base64Url.encode(utf8.encode(value.trim())).replaceAll('=', '');
  return 'magicchat.expression-picker.usage.v1.'
      '${encode(scope.serverUrl)}.${encode(scope.userId)}';
}

class ExpressionUsageStore {
  const ExpressionUsageStore(this.scope);

  final MessageCacheScope? scope;

  Future<List<ExpressionUsage>> read({DateTime? now}) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final encoded = preferences.getString(expressionUsageStorageKey(scope));
      if (encoded == null) return const [];
      final decoded = jsonDecode(encoded);
      final normalized =
          normalizeExpressionUsage(decoded, now ?? DateTime.now());
      if (decoded is! List || normalized.length != decoded.length) {
        await write(normalized);
      }
      return normalized;
    } catch (_) {
      return const [];
    }
  }

  Future<void> write(List<ExpressionUsage> usage) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        expressionUsageStorageKey(scope),
        jsonEncode(usage.map((item) => item.toJson()).toList(growable: false)),
      );
    } catch (_) {
      // 本地记录失败不应阻止表情输入。
    }
  }
}

TextEditingValue insertExpression(TextEditingValue current, String expression) {
  final selection = current.selection;
  final start = selection.isValid ? selection.start : current.text.length;
  final end = selection.isValid ? selection.end : start;
  final text = current.text.replaceRange(start, end, expression);
  return TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: start + expression.length),
  );
}

class ExpressionPicker extends StatefulWidget {
  const ExpressionPicker({
    required this.onSelect,
    this.cacheScope,
    this.now = DateTime.now,
    super.key,
  });

  final ValueChanged<ExpressionItem> onSelect;
  final MessageCacheScope? cacheScope;
  final DateTime Function() now;

  @override
  State<ExpressionPicker> createState() => _ExpressionPickerState();
}

class _ExpressionPickerState extends State<ExpressionPicker> {
  late ExpressionUsageStore _store;
  List<ExpressionUsage> _usage = const [];
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _store = ExpressionUsageStore(widget.cacheScope);
    _load();
  }

  @override
  void didUpdateWidget(covariant ExpressionPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheScope != widget.cacheScope) {
      _store = ExpressionUsageStore(widget.cacheScope);
      _usage = const [];
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final usage = await _store.read(now: widget.now());
    if (mounted && generation == _loadGeneration) {
      setState(() => _usage = usage);
    }
  }

  void _select(ExpressionItem item) {
    _loadGeneration++;
    final usage = updateExpressionUsage(_usage, item.value, widget.now());
    setState(() => _usage = usage);
    unawaited(_store.write(usage));
    widget.onSelect(item);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < 320 ? 6 : 8;
          return SingleChildScrollView(
            key: const ValueKey('expression-picker-scroll'),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ExpressionSection(
                  label: '常用',
                  items: frequentExpressionItems(_usage),
                  columns: columns,
                  onSelect: _select,
                ),
                const SizedBox(height: 16),
                _ExpressionSection(
                  label: '所有表情',
                  items: allExpressionItems,
                  columns: columns,
                  onSelect: _select,
                ),
              ],
            ),
          );
        },
      );
}

class _ExpressionSection extends StatelessWidget {
  const _ExpressionSection({
    required this.label,
    required this.items,
    required this.columns,
    required this.onSelect,
  });

  final String label;
  final List<ExpressionItem> items;
  final int columns;
  final ValueChanged<ExpressionItem> onSelect;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: label,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 6),
            GridView.builder(
              key: ValueKey('expression-section-$label'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemBuilder: (context, index) {
                final item = items[index];
                return IconButton(
                  key: ValueKey('expression-$label-${item.label}'),
                  tooltip: item.label,
                  onPressed: () => onSelect(item),
                  icon: Text(item.value, style: const TextStyle(fontSize: 22)),
                );
              },
            ),
          ],
        ),
      );
}

Future<ExpressionItem?> showExpressionPicker(
  BuildContext context, {
  MessageCacheScope? cacheScope,
}) =>
    showModalBottomSheet<ExpressionItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) => Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: math.min(400, constraints.maxWidth),
              height: math.min(560, constraints.maxHeight * .76),
              child: ExpressionPicker(
                cacheScope: cacheScope,
                onSelect: (item) => Navigator.pop(sheetContext, item),
              ),
            ),
          ),
        ),
      ),
    );
