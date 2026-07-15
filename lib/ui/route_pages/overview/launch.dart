import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/domain/mindustry_launcher.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/launch_mindustry_task.dart';
import 'package:copper_launcher/ui/util/widget/feature_button.dart';
import 'package:copper_launcher/ui/util/widget/feature_list_tile.dart';
import 'package:flutter/material.dart';

import '../../../core/app_config.dart';
import '../../feature/images.dart';
import '../../util/info/log_list.dart';
import '../../util/info/notification.dart';

class LaunchPage extends StatefulWidget {
  const LaunchPage({super.key});

  @override
  State<StatefulWidget> createState() => _LaunchPageState();
}

class _LaunchPageState extends State<LaunchPage> {
  Mindustry? _selectedVersion = config.versionOptions.selectedVersion;

  Widget _buildVersionTile() {
    if (_selectedVersion == null) {
      return ReboundListTile(
        borderRadius: BorderRadius.circular(8),

        onTap: () async {
          await Navigator.pushNamed(
            context,
            '/version_select',
            arguments: {'lead': '版本选择', 'routes': []},
          );
          setState(() {});
        },
        title: SizedBox(
          height: 80,
          child: Center(
            child: Text(
              '未选择版本，点击以选择游戏版本',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontSize: 32),
            ),
          ),
        ),
      );
    }
    return ReboundListTile(
      margin: EdgeInsets.all(8),
      elevation: 2,
      hoverElevation: 4,
      borderRadius: BorderRadius.circular(8),
      onLongTap: () {},
      onTap: () async {
        await Navigator.pushNamed(
          context,
          '/version_select',
          arguments: {'lead': '版本选择'},
        );
        setState(() {});
      },
      leading: Image.asset(
        _selectedVersion!.launcher == .copper
            ? Images.copper
            : Images.mindustry,
        scale: 0.66,
        height: 64,
      ),
      title: Text(
        _selectedVersion!.tag,
        style: TextStyle(
          color: Theme.of(context).colorScheme.secondary,
          fontWeight: FontWeight.w900,
          fontSize: 28,
        ),
      ),
      subtitle: Text(
        _selectedVersion!.name,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w900,
          fontSize: 14,
        ),
      ),
      trailing: ReboundButton(
        borderRadius: BorderRadius.circular(8),
        child: Icon(
          Icons.settings,
          color: Theme.of(context).iconTheme.color,
          size: 50,
        ),
        onTap: () {
          Navigator.pushNamed(
            context,
            '/version_setting',
            arguments: {
              'lead': '版本设置',
              'version': _selectedVersion,
              'title': _selectedVersion?.tag ?? 'null',
            },
          );
        },
      ),
    );
  }

  Widget _buildLaunchButton() {
    if (_selectedVersion == null) return SizedBox();

    return SizedBox(
      height: 80,
      width: 225,
      child: ReboundButton(
        pressedScale: 0.9,
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
        elevation: 2,
        hoverElevation: 4,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 16,
          children: [
            Icon(
              Icons.play_arrow,
              size: 50,
              color: Theme.of(context).iconTheme.color,
            ),
            Text(
              "启动游戏",
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            SizedBox(),
          ],
        ),
        onTap: () async {
          addTask(LaunchMindustryTask(_selectedVersion!));
        },
      ),
    );
  }

  @override
  void setState(VoidCallback fn) {
    _selectedVersion = config.versionOptions.selectedVersion;
    super.setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      //主页面
      children: [
        Expanded(
          child: Align(
            //屏幕中心
            // child: Test(),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(8),
          child: Row(
            //下方操作条
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Expanded(child: _buildVersionTile()), //
              SizedBox(width: 8),
              _buildLaunchButton(),
            ],
          ),
        ),
      ],
    );
  }
}

//开始游戏
class _Begin extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _BeginState();
}

class _BeginState extends State<_Begin> {
  final _mindustryLauncher = MindustryLauncher();

  Mindustry? _selectedVersion = config.versionOptions.selectedVersion;

  @override
  void setState(VoidCallback fn) {
    _selectedVersion = config.versionOptions.selectedVersion;
    super.setState(fn);
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _launch() async {}

  @override
  Widget build(BuildContext context) {
    //开始游戏

    if (_selectedVersion == null) return SizedBox();

    return SizedBox(
      height: 80,
      width: 225,
      child: ReboundButton(
        pressedScale: 0.9,
        backgroundColor: Colors.grey,
        borderRadius: BorderRadius.circular(8),
        hoverElevation: 8,
        onTap: () async {
          NotificationManager.addNotice(
            icon: Icons.rocket_launch_outlined,
            title: '启动',
            content: '正在启动游戏',
          );
          LogManager.addLog(LogEntry(.info, '正在启动游戏'));
          final s = await _mindustryLauncher.start(_selectedVersion!);
          if (s) {
            NotificationManager.addNotice(
              icon: Icons.info_outline,
              title: '启动',
              content: '游戏启动成功',
            );
            LogManager.addLog(LogEntry(.success, '游戏启动成功'));
          } else {
            NotificationManager.addNotice(
              icon: Icons.info_outline,
              title: '失败',
              content: '游戏启动失败',
            );
            LogManager.addLog(LogEntry(.success, '游戏启动失败'));
          }
        },
        child: Row(
          mainAxisAlignment: .center,
          spacing: 16,
          children: [
            Icon(Icons.play_arrow, size: 50, color: Colors.white),
            Text(
              "启动游戏",
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(),
          ],
        ),
      ),
    );
  }
}

//游戏版本 选择或设置
class _VersionSelect extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _VersionSelectState();
}

class _VersionSelectState extends State<_VersionSelect>
    with TickerProviderStateMixin {
  Mindustry? selectedVersion = config.versionOptions.selectedVersion;

  @override
  Widget build(BuildContext context) {
    late Widget child;

    if (selectedVersion == null) {
      child = ReboundListTile(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          await Navigator.pushNamed(
            context,
            '/version_select',
            arguments: {'lead': '版本选择'},
          );
          setState(() {});
        },
        title: Text('未选择版本，点击以选择游戏版本', style: TextStyle(color: Colors.white60)),
      );
    } else {
      final mindustry = config.versionOptions.findVersion(selectedVersion!);
      child = ReboundListTile(
        margin: EdgeInsets.all(8),
        borderRadius: BorderRadius.circular(8),
        onLongTap: () {},
        onTap: () async {
          await Navigator.pushNamed(
            context,
            '/version_select',
            arguments: {'lead': '版本选择'},
          );
          setState(() {});
        },
        leading: Image.asset(Images.mindustry, fit: BoxFit.fill),
        title: Text(
          selectedVersion!.tag ?? '该版本未命名',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
        subtitle: Text(
          selectedVersion!.name ?? '未知版本',
          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
        ),
        trailing: ReboundButton(
          borderRadius: BorderRadius.circular(8),
          child: Icon(Icons.settings, color: Colors.white, size: 50),
          onTap: () {
            Navigator.pushNamed(
              context,
              '/version_setting',
              arguments: {'lead': '版本设置', 'mindustry': mindustry},
            );
          },
        ),
      );
    }
    return child;
  }
}
