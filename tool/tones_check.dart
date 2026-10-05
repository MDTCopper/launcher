// 配色校验：直接把 app 里的 `template_tones.dart`（纯 Dart）跑一遍，
// 四个主题 × 亮暗 × 全部「前景/背景」配对，打出实际色值与 WCAG 比值，低于阈值的标 ✗。
// 跑法：dart run tool/tones_check.dart  —— 改了 tone 档位或目标对比度之后跑一遍
//
// ignore_for_file: avoid_print, avoid_relative_lib_imports
import 'package:copper_launcher/ui/pages/design/template_tones.dart';

const _themes = <({String name, double hue, double chroma})>[
  (name: '铜', hue: 68.7, chroma: 37),
  (name: '钛', hue: 253.4, chroma: 46),
  (name: '钍', hue: 336.2, chroma: 74),
  (name: '塑钢', hue: 136.9, chroma: 67),
];

String hex(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

void pair(
  String label,
  int fg,
  int bg,
  double need, {
  required List<String> failures,
}) {
  final ratio = toneContrast(fg, bg);
  final ok = ratio >= need;
  if (!ok) failures.add('$label ${ratio.toStringAsFixed(2)} < $need');
  print(
    '    ${label.padRight(26)} ${hex(fg)} on ${hex(bg)}  '
    '${ratio.toStringAsFixed(2)}:1  (需 $need)${ok ? '' : '  ✗'}',
  );
}

void main() {
  for (final theme in _themes) {
    for (final dark in [false, true]) {
      final t = TemplateTones.of(
        hue: theme.hue,
        chroma: theme.chroma,
        dark: dark,
      );
      final failures = <String>[];
      print('');
      print('══ ${theme.name} · ${dark ? '暗色' : '亮色'} ══');
      print(
        '  表面：页底 ${hex(t.page)} / 卡面 ${hex(t.surface)} / 抬升 ${hex(t.raised)} / '
        '凹槽 ${hex(t.sunken)} / 描边 ${hex(t.border)} / 强描边 ${hex(t.borderStrong)}',
      );
      pair('正文 / 卡面', t.textPrimary, t.surface, 4.5, failures: failures);
      pair('次要文字 / 卡面', t.textSecondary, t.surface, 4.5, failures: failures);
      pair('三级小字 / 卡面', t.textTertiary, t.surface, 5.5, failures: failures);
      pair('控件边界 / 卡面', t.controlBorder, t.surface, 3, failures: failures);
      pair('实心上的字', t.onAccent, t.accent, 4.5, failures: failures);
      if (dark) {
        pair('实心 / 卡面（暗色要跳出来）', t.accent, t.surface, 3, failures: failures);
      }
      pair('强调文字 / 卡面', t.accentText, t.surface, 5, failures: failures);
      pair('软底上的字', t.onAccentTint, t.accentTint, 6.5, failures: failures);
      pair('危险实心上的字', t.onDanger, t.danger, 4.5, failures: failures);
      pair('危险文字 / 卡面', t.dangerText, t.surface, 5, failures: failures);
      if (dark) {
        pair('成功 / 卡面', t.success, t.surface, 5, failures: failures);
        pair('警告 / 卡面', t.warning, t.surface, 5, failures: failures);
      } else {
        pair('成功实心上的字', t.onAccent, t.success, 4.5, failures: failures);
        pair('警告实心上的字', t.onAccent, t.warning, 4.5, failures: failures);
      }
      pair('软底 / 卡面（块感）', t.accentTint, t.surface, 1, failures: failures);
      print('  ${failures.isEmpty ? '全部达标' : '✗ ${failures.join(' | ')}'}');
    }
  }
}
