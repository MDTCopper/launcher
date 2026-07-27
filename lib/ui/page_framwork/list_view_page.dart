import 'package:flutter/material.dart';

class ListViewPage extends StatefulWidget {
  final Widget child;
  final Widget navigation;

  const ListViewPage({
    super.key,
    required this.child,
    required this.navigation,
  });

  @override
  State<StatefulWidget> createState() => ListViewPageState();
}

class ListViewPageState extends State<ListViewPage> {
  @override
  Widget build(BuildContext context) {
    // TODO: implement build
    throw UnimplementedError();
  }
}
