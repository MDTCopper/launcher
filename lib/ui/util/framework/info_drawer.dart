import 'package:flutter/material.dart';

import '../info/log_list.dart';
import '../info/task_list.dart';
import 'menu_bar.dart';

//自定义抽屉
class InfoDrawer extends Drawer {
  //todo 信息栏抽屉
  const InfoDrawer({
    super.key
  });
}

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
        curve: Interval(0.3, 0.8, curve: Curves.easeOutBack),
      ),
    );

    opacity2 = Tween(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: controller, curve: Interval(0.5, 1.0)));

    position2 = CurvedAnimation(
      parent: controller,
      curve: Interval(0.5, 1.0, curve: Curves.easeOutBack),
    );

    controller.forward();
    super.initState(); //todo 完善动画，可以在做完后优化AppearListView
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: FadeTransition(
            opacity: opacity1,
            child: SlideTransition(
              position: position1,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  Row(
                    spacing: 16,
                    children: [
                      Text(
                        '状态列表',
                        style: TextStyle(
                          color: theme.colorScheme.onSecondary,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            MenuItem(
                              isSide: false,
                              itemSpacing: 4,
                              margin: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 0,
                              ),
                              itemColor: theme.colorScheme.primaryContainer,
                              activeItemColor: theme.colorScheme.primary,
                              backgroundColor: theme.colorScheme.primary,
                              activeBackgroundColor: theme.colorScheme.primaryContainer,
                              leading: Icon(Icons.list_alt),
                              title: Text('任务'),
                              selected: index == 0,
                              onTap: () {
                                if (index != 0) {
                                  setState(() {
                                    index = 0;
                                  });
                                }
                              },
                            ),

                            MenuItem(
                              isSide: false,
                              itemSpacing: 4,
                              margin: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 0,
                              ),
                              itemColor: theme.colorScheme.primaryContainer,
                              activeItemColor: theme.colorScheme.primary,
                              backgroundColor: theme.colorScheme.primary,
                              activeBackgroundColor: theme.colorScheme.primaryContainer,
                              leading: Icon(Icons.watch_later_outlined),
                              title: Text('日志'),
                              selected: index == 1,
                              onTap: () {
                                if (index != 1) {
                                  setState(() {
                                    index = 1;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Divider(height: 10,thickness: 1,color: Colors.white24,),
                ],
              )
            ),
          ),
        ),

        Expanded(
          child:  FadeTransition(
              opacity: opacity2,
              child: MatrixTransition(
                animation: position2,
                onTransform: (value) {
                  return Matrix4.translationValues(
                    0.0,
                    -30.0 * (1 - value),
                    0.0,
                  );
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
