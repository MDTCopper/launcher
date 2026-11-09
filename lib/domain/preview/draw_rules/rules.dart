import '../plan_draw_rule.dart';
import 'canvas_pixels.dart';
import 'config_marks.dart';
import 'connection_links.dart';
import 'drawer_composition.dart';
import 'transport_connectivity.dart';

/// 汇总所有预览绘制规则
List<PlanDrawRule> buildPlanDrawRules() => [
  CanvasPlanRule(),
  ...configMarkRules,
  ...connectionLinkRules,
  ...transportConnectivityRules,
  ...drawerCompositionRules,
];
