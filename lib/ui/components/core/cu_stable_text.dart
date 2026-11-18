import 'package:flutter/material.dart';

/// 字重稳定的文本
///
/// 默认字体（Windows 上是「Microsoft YaHei UI」）在 w400 / w600 之间的**行宽不一样**，
/// 选中态一加粗整行宽度就变，标签、分段、下划线全跟着抖。
///
/// 做法：用最宽的那个字重放一份**透明副本**撑开尺寸，可见文字照常按当前字重绘制。
/// 只给「会切换字重」的文本用，普通文本不需要多一层。
class CuStableText extends StatelessWidget {
  const CuStableText(
    this.text, {
    super.key,
    required this.style,
    this.reserveWeight = FontWeight.w600,
    this.textAlign,
    this.maxLines,
    this.overflow = TextOverflow.ellipsis,
  });

  final String text;

  /// 当前要显示的字重 / 颜色
  final TextStyle style;

  /// 用来定宽的（最宽）字重
  final FontWeight reserveWeight;

  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    final widest = style.copyWith(fontWeight: reserveWeight);
    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        // 透明副本只参与布局，不参与绘制
        Opacity(
          opacity: 0,
          child: Text(
            text,
            textAlign: textAlign,
            maxLines: maxLines,
            overflow: overflow,
            style: widest,
          ),
        ),
        Text(
          text,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: overflow,
          style: style,
        ),
      ],
    );
  }
}
