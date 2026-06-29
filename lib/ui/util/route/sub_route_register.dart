import 'package:copperlauncher_main/ui/shell/navigation_rail.dart';
import 'package:copperlauncher_main/ui/util/route/page_key_provider.dart';

mixin SubRoute {
  void register(String key, List<SubRailSection> sections) {
    final state = PageKeyProvider.shellKey.currentState;
    if (state == null) throw Exception('未找到shell');
    state.registerSubRoute(key, sections);
  }

  void registerKey(String key) {
    final state = PageKeyProvider.shellKey.currentState;
    if (state == null) throw Exception('未找到shell');
    state.registerSubRouteKey(key);
  }
}
