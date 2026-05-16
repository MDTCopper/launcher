import 'dart:math';

import 'package:copperlauncher_main/data/local_asset.dart';
import 'package:copperlauncher_main/domain/mindustry_launcher.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_button.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_list_tile.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_text_field.dart';
import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../feature/images.dart';
import '../util/animation/loop_animated_widget/drill_loading.dart';
import '../util/info/log_list.dart';
import '../util/info/notification.dart';

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
            arguments: {'lead': '版本选择'},
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
        _selectedVersion!.launcher == LauncherType.copper
            ? Images.copper
            : Images.mindustry,
        scale: 0.66,
        height: 64,
      ),
      title: Text(
        _selectedVersion!.tag ?? '该版本未命名',
        style: TextStyle(
          color: Theme.of(context).colorScheme.secondary,
          fontWeight: FontWeight.w900,
          fontSize: 28,
        ),
      ),
      subtitle: Text(
        _selectedVersion!.name ?? '未知版本',
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
    final mindustryLauncher = MindustryLauncher();
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
          NotificationManager.addNotice(
            icon: Icons.rocket_launch_outlined,
            title: '启动',
            content: '正在启动\r\n[${_selectedVersion!.name}]',
          );
          LogManager.addLog(LogEntry(LogType.info, '正在启动游戏'));

          List<String>? isolation;
          if (_selectedVersion?.isolation ?? false) {
            if (_selectedVersion!.dataPath != null) {
              isolation = [
                '-Dmindustry.data.dir=${_selectedVersion!.dataPath}',
              ];
            }
          }

          final s = await mindustryLauncher.startMindustryJar(
            extraArgs1: isolation,
            jarPath: _selectedVersion!.jarPath ?? '',
          );

          if (s) {
            NotificationManager.addNotice(
              icon: Icons.info_outline,
              title: '启动',
              content: '游戏启动成功',
            );
            LogManager.addLog(LogEntry(LogType.success, '游戏启动成功'));
          } else {
            NotificationManager.addNotice(
              icon: Icons.info_outline,
              title: '失败',
              content: '游戏启动失败',
            );
            LogManager.addLog(LogEntry(LogType.success, '游戏启动失败'));
          }
        },
      ),
    );
  }

  @override
  void setState(VoidCallback fn) {
    _selectedVersion = config.versionOptions.selectedVersion;
    super.setState(fn);
  }

  void _test() async {}

  @override
  Widget build(BuildContext context) {
    return Column(
      //主页面
      children: [
        Expanded(
          child: Align(
            // child: ElectricConverter(),
            //屏幕中心
            // child: _CenterField(),
            child: ReboundIconButton(
              icon: Icons.add,
              content: 'a+++',
              onTap: _test,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(8),
          child: Row(
            //下方操作条
            spacing: 8,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Expanded(child: _buildVersionTile()), //
              _buildLaunchButton(),
            ],
          ),
        ),
      ],
    );
  }
}

class ElectricConverter extends StatefulWidget {
  const ElectricConverter({super.key});

  @override
  State<StatefulWidget> createState() => _ElectricConverterState();
}

class _ElectricConverterState extends State<ElectricConverter> {
  bool imaginaryToAngle = true;

  double imaginary = 6;
  double real = 8;
  double modulus = 0.0;
  double angle = 0.0;

  late final TextEditingController controller1;
  late final TextEditingController controller2;

  @override
  void initState() {
    super.initState();
    controller1 = TextEditingController(text: real.toString())..addListener(() {
      setState(() {
        if (imaginaryToAngle) {
          real = double.parse(controller1.text);
        } else {
          modulus = double.parse(controller1.text);
        }
      });
    });
    controller2 = TextEditingController(text: imaginary.toString())
      ..addListener(() {
        setState(() {
          if (imaginaryToAngle) {
            imaginary = double.parse(controller2.text);
          } else {
            angle = double.parse(controller2.text);
          }
        });
      });
  }

  @override
  Widget build(BuildContext context) {
    if (imaginaryToAngle) {
      modulus = sqrt(imaginary * imaginary + real * real);
      angle = atan(imaginary / real) * 180 / pi;
      if (real.isNegative) {
        if (angle.isNegative) {
          angle += 180;
        } else {
          angle -= 180;
        }
      }
    } else {
      real = cos(angle * pi / 180) * modulus;
      imaginary = sin(angle * pi / 180) * modulus;
    }

    return Material(
      borderRadius: BorderRadius.circular(16),
      elevation: 8,
      child: Container(
        margin: EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: 8,
          children: [
            ReboundIconButton(
              icon: Icons.refresh,
              content: imaginaryToAngle ? '代数式转为极坐标' : '极坐标转为代数式',
              onTap: () {
                imaginaryToAngle = !imaginaryToAngle;
                if (imaginaryToAngle) {
                  controller1.text = real.toStringAsFixed(3);
                  controller2.text = imaginary.toStringAsFixed(3);
                } else {
                  controller1.text = modulus.toStringAsFixed(3);
                  controller2.text = angle.toStringAsFixed(3);
                }
              },
            ),
            SizedBox(
              width: 200,
              child: Row(
                spacing: 8,
                children: [
                  Expanded(child: OutlinedTextField(controller: controller1)),
                  Text(imaginaryToAngle ? '+' : '∠'),
                  Expanded(child: OutlinedTextField(controller: controller2)),
                  Text(imaginaryToAngle ? 'j' : '°'),
                ],
              ),
            ),
            Text(
              imaginaryToAngle
                  ? '${modulus.toStringAsFixed(3)}∠${angle.toStringAsFixed(3)}'
                  : '${real.toStringAsFixed(3)}${imaginary.isNegative ? '' : '+'}${imaginary.toStringAsFixed(3)}j',
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterField extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _CenterFieldState();
}

class _CenterFieldState extends State<_CenterField> {
  String? file;
  bool isDrop = false;

  @override
  void dispose() {
    super.dispose();
  }

  double value = 0.4;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(alignment: Alignment.center, children: [DrillLoading()]);
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
          LogManager.addLog(LogEntry(LogType.info, '正在启动游戏'));
          final s = await _mindustryLauncher.startMindustryJar(
            jarPath: _selectedVersion!.jarPath ?? '',
          );
          if (s) {
            NotificationManager.addNotice(
              icon: Icons.info_outline,
              title: '启动',
              content: '游戏启动成功',
            );
            LogManager.addLog(LogEntry(LogType.success, '游戏启动成功'));
          } else {
            NotificationManager.addNotice(
              icon: Icons.info_outline,
              title: '失败',
              content: '游戏启动失败',
            );
            LogManager.addLog(LogEntry(LogType.success, '游戏启动失败'));
          }
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
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
