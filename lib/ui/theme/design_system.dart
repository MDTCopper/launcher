/// UI 几何令牌：间距 / 圆角 / 描边 / 图标 / 控件高度
///
/// 规范正文与组件选型表见 `.project_status/components.md` 的「UI 设计规范」，
/// 可视对照见设计规范页 `ui/pages/design/design_system_page.dart`（导航栏「设计规范」）
///
/// 职责边界：本文件只管几何；颜色一律取 `AppColors`，文字一律取 `textTheme` 的语义名
library;

import 'package:flutter/material.dart';

/// 间距刻度：`inline` 只用于行内微调，其余都是 4 的倍数
abstract final class AppSpacing {
  /// 2 图标与文字的间隙、徽标内衬
  static const double inline = 2;

  /// 4 紧邻的同类元素、控件的紧凑内衬
  static const double tight = 4;

  /// 8 同一组内的元素之间
  static const double related = 8;

  /// 12 组与组之间、标题到内容
  static const double group = 12;

  /// 16 区块之间、卡片内衬
  static const double section = 16;

  /// 24 页面内的大块之间、页面横向内衬
  static const double block = 24;

  /// 32 空态与大块留白
  static const double page = 32;
}

/// 圆角刻度：按层级取，嵌套时内层比外层小一档
abstract final class AppRadius {
  /// 4 控件级：按钮 / 输入框 / 选项 / 徽标
  static const double control = 4;

  /// 8 条目级：瓦片 / 菜单项 / 面板模块
  static const double item = 8;

  /// 12 面板级：卡片 / 对话框 / 浮层
  static const double panel = 12;

  /// 16 容器级：页面大块 / 图片 / 首屏
  static const double container = 16;

  /// 胶囊 / 圆形
  static const double pill = 999;

  static const BorderRadius controlShape = BorderRadius.all(
    Radius.circular(control),
  );
  static const BorderRadius itemShape = BorderRadius.all(Radius.circular(item));
  static const BorderRadius panelShape = BorderRadius.all(
    Radius.circular(panel),
  );
  static const BorderRadius containerShape = BorderRadius.all(
    Radius.circular(container),
  );
}

/// 描边宽度：只有这两档，对话框那套「顶粗两侧细」不手写，取对话框组件给的壳
abstract final class AppBorderWidth {
  /// 1 常规描边、分隔、描边进度轨道
  static const double hairline = 1;

  /// 2 聚焦 / 选中 / 输入框这类需要点出来的状态
  static const double emphasis = 2;
}

/// 图标尺寸：与同一行的文字角色搭配着取
abstract final class AppIconSize {
  /// 16 行内：标签旁、紧凑说明行
  static const double inline = 16;

  /// 20 条目：按钮图标、列表项图标
  static const double item = 20;

  /// 24 常规：导航栏、顶栏工具、独立图标按钮
  static const double normal = 24;

  /// 32 大：卡片头部、次级空态
  static const double large = 32;

  /// 48 特大：空态主图、头像位
  static const double hero = 48;
}

/// 控件高度：同一行的控件取同一档，别各写各的
abstract final class AppControlHeight {
  /// 24 纯图标按钮、顶栏工具
  static const double iconButton = 24;

  /// 32 小按钮 / 牌子 / 徽标
  static const double compact = 32;

  /// 40 标准按钮、输入框、顶栏
  static const double standard = 40;

  /// 48 列表项与触控目标的下限
  static const double item = 48;
}
