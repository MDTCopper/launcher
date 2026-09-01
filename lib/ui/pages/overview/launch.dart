import 'package:flutter/material.dart';

import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/launch_mindustry_task.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/tile/rebound_list_tile.dart';
import '../../../core/app_config.dart';
import '../../feature/images.dart';

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
      padding: EdgeInsets.all(8),
      borderRadius: BorderRadius.circular(8),

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
        _selectedVersion!.release,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w900,
          fontSize: 14,
        ),
      ),
      trailing: ReboundButton(
        borderRadius: BorderRadius.circular(8),
        backgroundColor: Colors.transparent,
        padding: EdgeInsets.all(8),
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
        borderRadius: BorderRadius.circular(8),
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
                color: Theme.of(context).colorScheme.secondary,
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
    Widget child = Column(
      //主页面
      children: [
        Expanded(child: SizedBox()),
        Padding(
          padding: EdgeInsets.all(8),
          child: Row(
            //下方操作条
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Expanded(child: _buildVersionTile()),
              SizedBox(width: 8),
              _buildLaunchButton(),
            ],
          ),
        ),
      ],
    );

    return child;
  }
}
