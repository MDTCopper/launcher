import 'package:flutter/cupertino.dart';

class InheritedColor extends InheritedWidget {

  final double elevation;
  final Color? hoverColor;
  final Color? focusColor;
  final Color? splashColor;
  final Color? highlightColor;
  final Color? shadowColor;
  final Color? itemColor;
  final Color? activeItemColor;
  final Color? backgroundColor;
  final Color? activeBackgroundColor;

  const InheritedColor({
    super.key,
    required super.child,
    this.itemColor,
    this.activeItemColor,
    this.backgroundColor,
    this.activeBackgroundColor,
    this.elevation = 0.0,
    this.hoverColor,
    this.focusColor,
    this.splashColor,
    this.highlightColor,
    this.shadowColor,
  });



  static InheritedColor? of (BuildContext context){
    return context.dependOnInheritedWidgetOfExactType<InheritedColor>();
  }

  @override
  bool updateShouldNotify(covariant InheritedColor oldWidget) {
    return itemColor != oldWidget.itemColor ||
        activeItemColor != oldWidget.activeItemColor ||
        backgroundColor != oldWidget.backgroundColor ||
        activeBackgroundColor != oldWidget.activeBackgroundColor ||
        elevation != oldWidget.elevation ||
        hoverColor!= oldWidget.hoverColor ||
        focusColor != oldWidget.focusColor ||
        shadowColor != oldWidget.shadowColor ||
        highlightColor != oldWidget.highlightColor ||
        splashColor !=oldWidget.splashColor;
  }


}
