import 'package:flutter/material.dart';
import '../framework/main_framework.dart';

class PageKeyProvider {

  static final _globalKey = GlobalKey<MainFrameWorkState>();
  static GlobalKey<MainFrameWorkState> get globalKey => _globalKey;

  static final _innerKey = GlobalKey<NavigatorState>();
  static GlobalKey<NavigatorState> get innerKey => _innerKey;

}