import 'package:flutter/material.dart';

import 'template_skin.dart';

/// 表格的一列
///
/// 宽度二选一：给 [width] 是固定列；不给就按 [flex] 分配剩余宽度
class TemplateTableColumn {
  const TemplateTableColumn(
    this.label, {
    this.width,
    this.flex,
    this.icon,
    this.align = Alignment.centerLeft,
    this.headerAlign,
  });

  final String label;
  final double? width;
  final int? flex;
  final IconData? icon;
  final Alignment align;
  final Alignment? headerAlign;
}

/// 表格：表头 + 行 + 行间分隔线；窄到放不下固定列时自动横向滚动
///
/// 覆盖度审计 P2-24：模组页的版本列表原先手写列宽，这里抽成可复用组件
class TemplateTable extends StatelessWidget {
  const TemplateTable({
    super.key,
    required this.skin,
    required this.columns,
    required this.rows,
    this.showHeader = true,
    this.onRowTap,
    this.rowPadding = const EdgeInsets.symmetric(
      horizontal: TemplateSpace.md,
      vertical: TemplateSpace.sm,
    ),
    this.headerPadding = const EdgeInsets.symmetric(
      horizontal: TemplateSpace.md,
      vertical: TemplateSpace.xs,
    ),
  });

  final TemplateSkin skin;
  final List<TemplateTableColumn> columns;

  /// 每行按列顺序给 cell；`null` 留空
  final List<List<Widget?>> rows;
  final bool showHeader;
  final void Function(int index)? onRowTap;
  final EdgeInsets rowPadding;
  final EdgeInsets headerPadding;

  static const _gap = TemplateSpace.md;

  /// 弹性列在可滚动模式下的最小宽
  static const _minFlexWidth = 120.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final fixed = columns.fold<double>(
          0,
          (sum, column) => sum + (column.width ?? 0),
        );
        final flexCount = columns.where((c) => c.width == null).length;
        final gaps = _gap * (columns.length - 1).clamp(0, columns.length);
        final flexShare = flexCount == 0
            ? 0.0
            : (available - fixed - gaps) / flexCount;
        final scrollable = flexCount > 0 && flexShare < _minFlexWidth;
        final totalWidth = scrollable
            ? fixed + gaps + _minFlexWidth * flexCount
            : available;

        final table = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHeader) ...[
              _buildHeader(scrollable),
              Container(height: 1, color: skin.border),
            ],
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Container(height: 1, color: skin.border),
              _buildRow(i, scrollable),
            ],
          ],
        );

        if (!scrollable) return table;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: totalWidth, child: table),
        );
      },
    );
  }

  Widget _buildHeader(bool scrollable) {
    return Padding(
      padding: headerPadding,
      child: Row(
        spacing: _gap,
        children: [
          for (final column in columns)
            _slot(column, header: true, scrollable: scrollable),
        ],
      ),
    );
  }

  Widget _buildRow(int index, bool scrollable) {
    final cells = rows[index];
    final content = Padding(
      padding: rowPadding,
      child: Row(
        spacing: _gap,
        children: [
          for (var c = 0; c < columns.length; c++)
            _slot(
              columns[c],
              child: c < cells.length ? cells[c] : null,
              scrollable: scrollable,
            ),
        ],
      ),
    );
    final onTap = onRowTap;
    if (onTap == null) return content;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(index),
        child: content,
      ),
    );
  }

  /// 一个单元格：固定列给宽、弹性列给 Expanded；对齐方式按列取
  Widget _slot(
    TemplateTableColumn column, {
    Widget? child,
    bool header = false,
    required bool scrollable,
  }) {
    final align = header ? (column.headerAlign ?? column.align) : column.align;
    final content = Align(
      alignment: align,
      child:
          child ??
          (header
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: TemplateSpace.xs,
                  children: [
                    if (column.icon != null)
                      Icon(column.icon, size: 14, color: skin.textTertiary),
                    Text(
                      column.label,
                      style: TemplateType.caption.copyWith(
                        color: skin.textTertiary,
                      ),
                    ),
                  ],
                )
              : SizedBox.shrink()),
    );

    if (column.width != null || scrollable) {
      final width = column.width ?? _minFlexWidth;
      return SizedBox(width: width, child: content);
    }
    return Expanded(flex: column.flex ?? 1, child: content);
  }
}
