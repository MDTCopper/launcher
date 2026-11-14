import 'package:copper_launcher/ui/components/core/cu_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_shell.dart';
import 'package:flutter/material.dart';

/// 徽标语气
enum CuBadgeTone { neutral, accent, success, warning, danger, note }

/// 状态点语气
enum CuStatusTone { online, busy, away, offline }

TemplateBadgeTone _badgeTone(CuBadgeTone tone) => switch (tone) {
  CuBadgeTone.neutral => TemplateBadgeTone.neutral,
  CuBadgeTone.accent => TemplateBadgeTone.accent,
  CuBadgeTone.success => TemplateBadgeTone.success,
  CuBadgeTone.warning => TemplateBadgeTone.warning,
  CuBadgeTone.danger => TemplateBadgeTone.danger,
  CuBadgeTone.note => TemplateBadgeTone.note,
};

TemplateStatusTone _statusTone(CuStatusTone tone) => switch (tone) {
  CuStatusTone.online => TemplateStatusTone.online,
  CuStatusTone.busy => TemplateStatusTone.busy,
  CuStatusTone.away => TemplateStatusTone.away,
  CuStatusTone.offline => TemplateStatusTone.offline,
};

/// 徽标（搬运自 `TemplateBadge`）
class CuBadge extends StatelessWidget {
  const CuBadge({
    super.key,
    required this.label,
    this.tone = CuBadgeTone.neutral,
    this.icon,
  });

  final String label;
  final CuBadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => TemplateBadge(
    skin: cuSkinOf(context),
    label: label,
    tone: _badgeTone(tone),
    icon: icon,
  );
}

/// Chip（可选中 / 可关闭，搬运自 `TemplateChip`）
class CuChip extends StatelessWidget {
  const CuChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
    this.onClose,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => TemplateChip(
    skin: cuSkinOf(context),
    label: label,
    icon: icon,
    selected: selected,
    onTap: onTap,
    onClose: onClose,
  );
}

/// 状态点（搬运自 `TemplateStatusDot`）
class CuStatusDot extends StatelessWidget {
  const CuStatusDot({
    super.key,
    this.tone = CuStatusTone.online,
    this.size = 8,
    this.label,
  });

  final CuStatusTone tone;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) => TemplateStatusDot(
    skin: cuSkinOf(context),
    tone: _statusTone(tone),
    size: size,
    label: label,
  );
}

/// 计数徽标（搬运自 `TemplateCountBadge`）
class CuCountBadge extends StatelessWidget {
  const CuCountBadge({
    super.key,
    this.count = 0,
    this.max = 99,
    this.dotOnly = false,
    this.tone = CuBadgeTone.accent,
  });

  final int count;
  final int max;
  final bool dotOnly;
  final CuBadgeTone tone;

  @override
  Widget build(BuildContext context) => TemplateCountBadge(
    skin: cuSkinOf(context),
    count: count,
    max: max,
    dotOnly: dotOnly,
    tone: _badgeTone(tone),
  );
}
