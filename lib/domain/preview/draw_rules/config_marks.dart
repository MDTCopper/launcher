import '../plan_draw_rule.dart';

/// 官方 `drawPlanConfig` 覆写类的 config 标记
///
/// 官方预览的默认区域绘制结尾会调用 `drawPlanConfig`，排序器/卸载器靠它显示
/// 当前选中的物品；这里按声明类复刻
final List<PlanDrawRule> configMarkRules = <PlanDrawRule>[
  _SorterConfigRule(),
  _UnloaderConfigRule(),
];

class _SorterConfigRule extends PlanDrawRule {
  @override
  Set<String> get configClasses => const {'Sorter'};

  @override
  void drawConfig(PlanDrawContext context, PlanTile plan) {
    drawPlanConfigCenter(context, plan, iconName: 'center', showNull: true);
  }
}

class _UnloaderConfigRule extends PlanDrawRule {
  @override
  Set<String> get configClasses => const {'Unloader'};

  @override
  void drawConfig(PlanDrawContext context, PlanTile plan) {
    drawPlanConfigCenter(context, plan, iconName: 'unloader-center');
  }
}
