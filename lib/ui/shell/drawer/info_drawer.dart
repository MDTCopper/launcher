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

  final List<Widget> pages = [TaskList(), TaskLogList()];

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
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          Row(
            children: [
              Text('状态列表', style: theme.textTheme.headlineMedium),
              const SizedBox(width: 32),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: theme.brightness == .dark
                        ? Border.all(color: colors.border)
                        : null,
                    borderRadius: BorderRadius.circular(8),
                    color: colors.cardBackground,
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    spacing: 4,
                    children: [
                      Expanded(
                        child: ActionButton(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(4),
                          selected: index == 0,
                          icon: Icon(Icons.list_alt),
                          content: Text('任务'),
                          onTap: () => setState(() {
                            index = 0;
                          }),
                        ),
                      ),
                      Expanded(
                        child: ActionButton(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(4),
                          selected: index == 1,
                          icon: Icon(Icons.watch_later_outlined),
                          content: Text('日志'),
                          onTap: () => setState(() {
                            index = 1;
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
