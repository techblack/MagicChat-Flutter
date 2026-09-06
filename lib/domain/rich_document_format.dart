/// Web/Desktop 富文档允许写入 `blockBackgroundColor` 的固定色板。
///
/// 保留原始 OKLCH 字符串作为 Yjs schema 值，Flutter 仅在展示层转换颜色，
/// 避免跨端保存时产生另一套不被官方编辑器识别的色值。
const richDocumentBlockBackgroundTypes = {
  'paragraph',
  'heading',
  'bulletList',
  'orderedList',
  'taskList',
  'blockquote',
  'codeBlock',
  'table',
};

const richDocumentBlockBackgroundColors = <({String label, String value})>[
  (label: '红色 100', value: 'oklch(93.6% 0.032 17.717)'),
  (label: '琥珀色 100', value: 'oklch(96.2% 0.059 95.617)'),
  (label: '青柠色 100', value: 'oklch(96.7% 0.067 122.328)'),
  (label: '翠绿色 100', value: 'oklch(95% 0.052 163.051)'),
  (label: '青色 100', value: 'oklch(95.6% 0.045 203.388)'),
  (label: '蓝色 100', value: 'oklch(93.2% 0.032 255.585)'),
  (label: '紫罗兰色 100', value: 'oklch(94.3% 0.029 294.588)'),
  (label: '品红色 100', value: 'oklch(95.2% 0.037 318.852)'),
  (label: '橄榄色 100', value: 'oklch(96.6% 0.005 106.5)'),
  (label: '灰色 100', value: 'oklch(96.7% 0.003 264.542)'),
  (label: '红色 300', value: 'oklch(80.8% 0.114 19.571)'),
  (label: '琥珀色 300', value: 'oklch(87.9% 0.169 91.605)'),
  (label: '青柠色 300', value: 'oklch(89.7% 0.196 126.665)'),
  (label: '翠绿色 300', value: 'oklch(84.5% 0.143 164.978)'),
  (label: '青色 300', value: 'oklch(86.5% 0.127 207.078)'),
  (label: '蓝色 300', value: 'oklch(80.9% 0.105 251.813)'),
  (label: '紫罗兰色 300', value: 'oklch(81.1% 0.111 293.571)'),
  (label: '品红色 300', value: 'oklch(83.3% 0.145 321.434)'),
  (label: '橄榄色 300', value: 'oklch(88% 0.011 106.6)'),
  (label: '灰色 300', value: 'oklch(87.2% 0.01 258.338)'),
  (label: '红色 500', value: 'oklch(63.7% 0.237 25.331)'),
  (label: '琥珀色 500', value: 'oklch(76.9% 0.188 70.08)'),
  (label: '青柠色 500', value: 'oklch(76.8% 0.233 130.85)'),
  (label: '翠绿色 500', value: 'oklch(69.6% 0.17 162.48)'),
  (label: '青色 500', value: 'oklch(71.5% 0.143 215.221)'),
  (label: '蓝色 500', value: 'oklch(62.3% 0.214 259.815)'),
  (label: '紫罗兰色 500', value: 'oklch(60.6% 0.25 292.717)'),
  (label: '品红色 500', value: 'oklch(66.7% 0.295 322.15)'),
  (label: '橄榄色 500', value: 'oklch(58% 0.031 107.3)'),
  (label: '灰色 500', value: 'oklch(55.1% 0.027 264.364)'),
  (label: '红色 700', value: 'oklch(50.5% 0.213 27.518)'),
  (label: '琥珀色 700', value: 'oklch(55.5% 0.163 48.998)'),
  (label: '青柠色 700', value: 'oklch(53.2% 0.157 131.589)'),
  (label: '翠绿色 700', value: 'oklch(50.8% 0.118 165.612)'),
  (label: '青色 700', value: 'oklch(52% 0.105 223.128)'),
  (label: '蓝色 700', value: 'oklch(48.8% 0.243 264.376)'),
  (label: '紫罗兰色 700', value: 'oklch(49.1% 0.27 292.581)'),
  (label: '品红色 700', value: 'oklch(51.8% 0.253 323.949)'),
  (label: '橄榄色 700', value: 'oklch(39.4% 0.023 107.4)'),
  (label: '灰色 700', value: 'oklch(37.3% 0.034 259.733)'),
  (label: '红色 900', value: 'oklch(39.6% 0.141 25.723)'),
  (label: '琥珀色 900', value: 'oklch(41.4% 0.112 45.904)'),
  (label: '青柠色 900', value: 'oklch(40.5% 0.101 131.063)'),
  (label: '翠绿色 900', value: 'oklch(37.8% 0.077 168.94)'),
  (label: '青色 900', value: 'oklch(39.8% 0.07 227.392)'),
  (label: '蓝色 900', value: 'oklch(37.9% 0.146 265.522)'),
  (label: '紫罗兰色 900', value: 'oklch(38% 0.189 293.745)'),
  (label: '品红色 900', value: 'oklch(40.1% 0.17 325.612)'),
  (label: '橄榄色 900', value: 'oklch(22.8% 0.013 107.4)'),
  (label: '灰色 900', value: 'oklch(21% 0.034 264.665)'),
];

String? normalizeRichDocumentBlockBackground(Object? value) {
  if (value is! String) return null;
  final normalized = value.trim();
  return richDocumentBlockBackgroundColors.any(
    (color) => color.value == normalized,
  )
      ? normalized
      : null;
}
