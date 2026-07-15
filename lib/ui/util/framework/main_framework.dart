import 'dart:io';

import 'package:copper_launcher/ui/feature/images.dart';
import 'package:copper_launcher/ui/util/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/util/framework/info_drawer.dart';
import 'package:copper_launcher/ui/util/widget/appear_list_view.dart';
import 'package:copper_launcher/ui/util/widget/feature_list_tile.dart';
import 'package:copper_launcher/ui/util/widget/resource_importer.dart';
import 'package:copper_launcher/util/io/file_reader.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../util/format/string_cleaner.dart';
import '../../vars.dart';
import '../dialog/drag_file_field.dart';
import '../info/task_drawer_opener.dart';
import '../route/page_key_provider.dart';
import '../route/page_route_observer.dart';
import '../widget/feature_button.dart';
import 'appbar_navigator.dart';

class MainFrameWork extends StatefulWidget {
  const MainFrameWork({super.key});

  @override
  State<StatefulWidget> createState() => MainFrameWorkState();
}

class MainFrameWorkState extends State<MainFrameWork> with RouteAware {
  static final _appbarKey = GlobalKey<AppbarNavigationBarState>();
  static final _navigatorKey = PageKeyProvider.navigatorKey;

  String get route {
    if (_appbarKey.currentState == null) return '/';
    return _appbarKey.currentState!.currentRootRoute;
  }

  late final PageRouteObserver _routeObserver;

  late List<DropItem> files;

  //zip,jar,msav,msch
  //安卓不能实现拖拽，不需要适配apk
  //模组返回Map格式，其实只需要名称与版本，游戏也是
  //地图蓝图尝试用源代码读取内容，名字即可
  void _handleDragFile(DropDoneDetails d) async {
    await showResourceImporter(d.files.map((it) => it.path).toList());
  }

  void _importPagePop(List<FileReader> importList) {
    importList.sort((a, b) {
      if (a.type == ResourceType.mindustry) return -1;
      if (b.type == ResourceType.mindustry) return 1;
      if (a.type == ResourceType.mod) return -1;
      if (b.type == ResourceType.mod) return 1;
      if (a.type == ResourceType.mapSave) return -1;
      if (b.type == ResourceType.mapSave) return 1;
      if (a.type == ResourceType.schematic) return -1;
      if (b.type == ResourceType.schematic) return 1;
      return 0;
    });
    showDefaultDialogPopup(
      pageBuilder: (context, _, _) {
        return Column(
          children: [
            ReboundIconButton(
              icon: Icons.arrow_back,
              content: '导入外部资源',
              onTap: () {
                Navigator.pop(context);
              },
            ),
            Expanded(
              child: AppearListView(
                delay: 300,
                offset: Offset(-0.1, 0.0),
                items: importList.map((it) {
                  final type = it.type;
                  switch (type) {
                    case null:
                      return SizedBox();
                    case ResourceType.mindustry:
                      final m = it.mindustry!;
                      return ReboundListTile(
                        leading: Image.asset(Images.mindustry),
                        title: Text('Mindustry v${m.version}'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('build ${m.build}  (${m.type})'),
                            Text('${m.path}'),
                          ],
                        ),
                        onTap: () {},
                      );
                    case ResourceType.mod:
                      final mod = it.mod!;
                      return ReboundListTile(
                        leading: Icon(Icons.add_box_outlined, size: 64),
                        title: Text(
                          '模组  ${generalizeText(mod.name)}  |  作者  ${generalizeText(mod.author)}}',
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '版本  ${mod.version}   |   minGameVersion ${mod.minGameVersion}',
                            ),
                            Text('${mod.path}'),
                          ],
                        ),
                        onTap: () {},
                      );
                    case ResourceType.mapSave:
                      final m = it.mapSave!;
                      return ReboundListTile(
                        leading: Icon(Icons.map_outlined, size: 64),
                        title: Text(
                          '地图  ${generalizeText(m.name)}  |  作者  ${generalizeText(m.author)}',
                        ),
                        subtitle: Text('${m.path}'),
                        onTap: () {},
                      );
                    case ResourceType.schematic:
                      final m = it.schematic!;
                      return ReboundListTile(
                        leading: Icon(Icons.paste, size: 64),
                        title: Text(
                          '蓝图  ${generalizeText(m.name)}  |  作者  ${generalizeText(m.author)}',
                        ),
                        subtitle: Text('${m.path}'),
                        onTap: () {},
                      );
                    case ResourceType.settings:
                      // TODO: Handle this case.
                      throw UnimplementedError();
                  }
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }

  void _updateRoute(Route newRoute) {
    if (_appbarKey.currentState == null) return;
    _appbarKey.currentState!.updateRoute(newRoute);
  }

  @override
  void initState() {
    _routeObserver = PageRouteObserver(onRouteChange: _updateRoute);
    super.initState();
  }

  @override
  void didChangeDependencies() {
    _routeObserver.subscribe(this, ModalRoute.of(context) as PageRoute);
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    _routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appBarTheme = theme.appBarTheme;

    List<Widget>? buildWindowsButton() {
      if (!Platform.isWindows) return null;
      return [
        SizedBox(width: 4),
        ReboundButton(
          backgroundColor: appBarTheme.backgroundColor,
          shadowColor: colorScheme.primary,
          hoverElevation: 4.0,
          child: Icon(Icons.remove, color: appBarTheme.iconTheme?.color),
          onTap: () => windowManager.minimize(),
        ),
        SizedBox(width: 4),
        ReboundButton(
          backgroundColor: appBarTheme.backgroundColor,
          hoverElevation: 4.0,
          child: Icon(Icons.close, color: appBarTheme.iconTheme?.color),
          onTap: () => windowManager.close(),
        ),
      ];
    }

    Widget widget = Scaffold(
      appBar: AppbarNavigationBar(
        key: _appbarKey,
        initialRoute: '/',
        routeObserver: _routeObserver,
        leading: Transform.translate(
          offset: Offset(4.0, -3.0),
          child: Text(
            'Copper',
            style: TextStyle(
              color: colorScheme.onPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),

        options: [
          AppbarNavigatorOption(
            route: '/',
            icon: Icons.play_arrow_outlined,
            name: '启动',
          ),
          AppbarNavigatorOption(
            route: '/download',
            icon: Icons.file_download_outlined,
            name: '下载',
          ),
          AppbarNavigatorOption(
            route: '/setting',
            icon: Icons.settings,
            name: '设置',
          ),
          AppbarNavigatorOption(route: '/about', icon: Icons.menu, name: '更多'),
        ],
        action: [TaskDrawerOpener(), ...?buildWindowsButton()],
      ),
      drawerScrimColor: Colors.black26,
      endDrawer: Drawer(
        backgroundColor: colorScheme.primary,
        width: MediaQuery.of(context).size.width * 0.40,
        elevation: 2,
        shadowColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: InfoList(),
      ),
      body: Container(
        margin: const EdgeInsets.fromLTRB(4, 0, 4, 4),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Navigator(
          key: _navigatorKey,
          initialRoute: '/',
          observers: [_routeObserver],
          onGenerateRoute: (setting) {
            Widget page =
                routeMap[setting.name] ??
                SizedBox(
                  child: BackButton(
                    onPressed: () {
                      _routeObserver.navigator!.pop();
                    },
                  ),
                );

            return PageRouteBuilder(
              settings: setting,
              pageBuilder: (_, _, _) => page,
              transitionDuration: const Duration(milliseconds: 400),
              reverseTransitionDuration: const Duration(milliseconds: 400),
              transitionsBuilder: (_, animation1, animation2, child) {
                Animation<Offset> position1 =
                    Tween(begin: Offset(0.0, 0.1), end: Offset.zero).animate(
                      CurvedAnimation(
                        parent: animation1,
                        curve: Interval(0.4, 1.0, curve: Curves.easeOutBack),
                        reverseCurve: Interval(0.4, 1.0, curve: Curves.easeIn),
                      ),
                    );

                Animation<double> fade1 = CurvedAnimation(
                  parent: animation1,
                  curve: Interval(0.4, 1.0, curve: Curves.easeOutBack),
                  reverseCurve: Interval(0.4, 1.0, curve: Curves.easeIn),
                );

                child = SlideTransition(
                  position: position1,
                  child: FadeTransition(opacity: fade1, child: child),
                );

                Animation<Offset> position2 =
                    Tween(begin: Offset.zero, end: Offset(0.0, 0.1)).animate(
                      CurvedAnimation(
                        parent: animation2,
                        curve: Interval(0.0, 0.6, curve: Curves.easeOut),
                        reverseCurve: Interval(
                          0.0,
                          0.6,
                          curve: Curves.easeInBack,
                        ),
                      ),
                    );

                Animation<double> fade2 = Tween(begin: 1.0, end: 0.0).animate(
                  CurvedAnimation(
                    parent: animation2,
                    curve: Interval(0.0, 0.6, curve: Curves.easeOut),
                    reverseCurve: Interval(0.0, 0.6, curve: Curves.easeInBack),
                  ),
                );

                child = SlideTransition(
                  position: position2,
                  child: FadeTransition(opacity: fade2, child: child),
                );

                return child;
              },
            );
          },
        ),
      ),
    );

    if (Platform.isWindows) {
      widget = DragFileField(onDragDone: _handleDragFile, child: widget);
    }

    return widget;
  }
}
