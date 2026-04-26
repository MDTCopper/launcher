
import 'package:copperlauncher_main/ui/util/framework/page_skeleton.dart';
import 'package:flutter/material.dart';

import '../util/framework/menu_bar.dart';


class MorePage extends StatefulWidget {
  const MorePage({super.key});

  @override
  State<MorePage> createState() => _AboutState();
}

class _AboutState extends State<MorePage> with SingleTickerProviderStateMixin {
  static int index = 0;

  late AnimationController controller;

  late ScrollController scrollController;

  @override
  void initState() {
    controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 500),
    );
    controller.forward();

    scrollController = ScrollController();

    super.initState();
  }

  final List<Widget> pageList = [

    Center(child: Text('todo')),
    Center(child: Text('todo')),
    Center(child: Text('todo')),
  ];

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageSkeleton(
      body: pageList[index],
      menuBar: SideMenuBar(
        items: [
          MenuItem(
            leading: Icon(Icons.widgets_outlined),
            title: Text('神秘小工具'),
            selected: index == 0,
            onTap: () {
              setState(() {
                index = 0;
              });
            },
          ),
          MenuItem(
            leading: Icon(Icons.help_outline),
            title: Text('帮助'),
            selected: index == 1,
            onTap: () {
              setState(() {
                index = 1;
              });
            },
          ),
          MenuItem(
            leading: Icon(Icons.info_outline),
            title: Text('关于'),
            selected: index == 2,
            onTap: () {
              setState(() {
                index = 2;
              });
            },
          ),
        ],
      ),
    );
  }
}
