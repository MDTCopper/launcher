import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:copperlauncher_main/ui/util/framework/info_drawer.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:hjson_dart/hjson_dart.dart';
import 'package:mime/mime.dart';
import 'package:properties/properties.dart';
import 'package:window_manager/window_manager.dart';

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
  static final _navigatorKey = PageKeyProvider.innerKey;

  String get route {
    if (_appbarKey.currentState == null) return '/';
    return _appbarKey.currentState!.currentRootRoute;
  }

  late final PageRouteObserver _routeObserver;

  late List<DropItem> files;

  Future<Map<String, dynamic>?> _gameMetaFrom(String path) async {
    //这里后续要对手机端做特殊化
    final f = File(path);
    if (!await f.exists()) return null;
    final b = await f.readAsBytes();
    final arc = ZipDecoder().decodeBytes(b);
    var file = arc.findFile('version.properties');
    if (file != null) {
      final p = Properties.fromString(utf8.decode(file.content));
      //print(jsonDecode(p.toJSON()));
      return jsonDecode(p.toJSON());
    }
    file = arc.findFile('assets/version.properties');
    if (file == null) return null;
    final p = Properties.fromString(utf8.decode(file.content));
    return jsonDecode(p.toJSON());
  }

  ///找到元数据返回json格式
  Future<Map<String, dynamic>?> _modMetaFrom(String path) async {
    final f = File(path);
    if (!await f.exists()) return null;
    final b = await f.readAsBytes();
    final arc = ZipDecoder().decodeBytes(b);

    final index = arc.files.indexWhere((it) {
      final modMeta = it.name.split('/');
      if (modMeta.length > 2) return false;
      if (modMeta.contains('mod.json') || modMeta.contains('mod.hjson')) {
        return true;
      }
      return false;
    });

    if (index == -1) return null;

    var file = arc.files[index];
    var content = utf8.decode(file.content, allowMalformed: true);
    return hjsonDecode(content, strict: false) as Map<String, dynamic>;

    // content = parseBrokenJson(content);
    // if (isJson) {
    //   return jsonDecode(content) as Map<String, dynamic>;
    // } else {
    //   return hjsonDecode(content) as Map<String, dynamic>;
    // }
  }

  //todo 存档导入,应该有存档元数据检查 查看有什么
  Future<bool> _checkSaveMetaFrom(String path) async {
    final f = File(path);
    if (!await f.exists()) return false;
    final b = await f.readAsBytes();
    final arc = ZipDecoder().decodeBytes(b);
    var file = arc.findFile('setting.bin');
    return file != null;
  }

  //zip,jar,msav,msch
  //安卓不能实现拖拽，不需要适配apk
  //模组返回Map格式，其实只需要名称与版本，游戏也是
  //地图蓝图尝试用源代码读取内容，名字即可
  void _handleDragFile(DropDoneDetails d) async {
    final List<Map<String, String>> importList = [];

    for (var file in d.files) {
      final path = file.path;
      var type = lookupMimeType(path);
      print(type);
      if (type != null) {
        if (type.contains('java-archive')) {
          var meta = await _modMetaFrom(path);
          if (meta != null) {
            print(meta..remove('description'));
          } else {
            meta = await _gameMetaFrom(path);
            if (meta == null) continue;
            print(meta..remove('description'));
          }
        }
        if (type.contains('zip')) {
          var meta = await _modMetaFrom(path);
          if (meta == null) continue;
          print(meta..remove('description'));
        }
      } else {
        if (path.contains('.msav')) {
          print('地图');
        } else if (path.contains('.msch')) {
          print('蓝图');
        }
      }
    }
  }

  void _importPagePop(List<Map<String, String>> importList) {}

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
              pageBuilder: (_, _, _) => page, //todo 后续优化动画可以从这里下手，直接传入动画变量
              transitionDuration: const Duration(milliseconds: 400),
              reverseTransitionDuration: const Duration(milliseconds: 400),
              transitionsBuilder: (_, animation1, animation2, child) {
                Animation<Offset> position1 = Tween(
                  begin: Offset(0.0, 0.1),
                  end: Offset.zero,
                ).animate(
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

                Animation<Offset> position2 = Tween(
                  begin: Offset.zero,
                  end: Offset(0.0, 0.1),
                ).animate(
                  CurvedAnimation(
                    parent: animation2,
                    curve: Interval(0.0, 0.6, curve: Curves.easeOut),
                    reverseCurve: Interval(0.0, 0.6, curve: Curves.easeInBack),
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
