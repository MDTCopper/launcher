import 'package:copper_launcher/ui/components/core/cu_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_state.dart';
import 'package:flutter/material.dart';

/// 空态（搬运自 `TemplateEmptyState`）
class CuEmptyState extends StatelessWidget {
  const CuEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => TemplateEmptyState(
    skin: cuSkinOf(context),
    title: title,
    message: message,
    icon: icon,
    action: action,
  );
}

/// 错误态（搬运自 `TemplateErrorState`）
class CuErrorState extends StatelessWidget {
  const CuErrorState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.error_outline,
    this.action,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => TemplateErrorState(
    skin: cuSkinOf(context),
    title: title,
    message: message,
    icon: icon,
    action: action,
  );
}

/// 加载态（搬运自 `TemplateLoadingState`）
class CuLoadingState extends StatelessWidget {
  const CuLoadingState({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) =>
      TemplateLoadingState(skin: cuSkinOf(context), message: message);
}
