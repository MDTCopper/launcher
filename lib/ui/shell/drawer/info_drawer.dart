import 'package:copper_launcher/ui/components/button/action_button.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

import 'log_list.dart';
import 'task_list.dart';

class InfoList extends StatefulWidget {
  const InfoList({super.key});

  @override
  State<StatefulWidget> createState() => _InfoListState();
}

class _InfoListState extends State<InfoList>
    with SingleTickerProviderStateMixin {
  static int index = 0;

  final List<Widget> pages = [TaskList(), LogList()];

  late final AnimationController controller;

  late final Animation<double> opacity1;
  late final Animation<Offset> position1;

  late final Animation<double> opacity2;
  late final Animation<double> position2;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 500),
    );

    opacity1 = Tween(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: controller, curve: Interval(0.3, 0.8)));

    position1 = Tween(begin: const Offset(0.0, -1.0), end: Offset.zero).animate(
      CurvedAnimation(
        parent: controller,
        curve: Interval(0.3, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    opacity2 = Tween(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: controller, curve: Interval(0.5, 1.0)));

    position2 = CurvedAnimation(
      parent: controller,
      curve: Interval(0.5, 1.0, curve: Curves.easeOutCubic),
    );

    controller.forward();
  }

  Widget _buildMenu() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          Row(
            spacing: 16,
            children: [
              Text('状态列表', style: theme.textTheme.headlineMedium),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    ActionButton(
                      selected: index == 0,
                      icon: Icon(Icons.list_alt),
                      content: Text('任务'),
                      onTap: () => setState(() {
                        index = 0;
                      }),
                    ),
                    ActionButton(
                      selected: index == 1,
                      icon: Icon(Icons.watch_later_outlined),
                      content: Text('日志'),
                      onTap: () => setState(() {
                        index = 1;
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Divider(height: 10, thickness: 1, color: colors.border),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FadeTransition(
          opacity: opacity1,
          child: SlideTransition(position: position1, child: _buildMenu()),
        ),
        Expanded(
          child: FadeTransition(
            opacity: opacity2,
            child: MatrixTransition(
              animation: position2,
              onTransform: (value) {
                return Matrix4.translationValues(0.0, -30.0 * (1 - value), 0.0);
              },
              child: AnimatedSwitcher(
                duration: Duration(milliseconds: 350),
                transitionBuilder: (child, animation) {
                  final animation1 = CurvedAnimation(
                    parent: animation,
                    curve: Interval(0.4, 1.0, curve: Curves.easeOutBack),
                    reverseCurve: Interval(0.4, 1.0, curve: Curves.easeOut),
                  );
                  return MatrixTransition(
                    animation: animation1,
                    onTransform: (value) {
                      return Matrix4.translationValues(
                        0.0,
                        40.0 * (1 - value),
                        0.0,
                      );
                    },
                    child: FadeTransition(
                      opacity: CurvedAnimation(
                        parent: animation,
                        curve: Interval(0.4, 1.0),
                      ),
                      child: child,
                    ),
                  );
                },
                child: pages[index],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
