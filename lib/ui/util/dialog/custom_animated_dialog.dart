import 'dart:ui';

import 'package:copperlauncher_main/ui/util/widget/feature_button.dart';
import 'package:flutter/material.dart';

import '../route/page_key_provider.dart';

enum DialogAnimation { fade, slide, popup, leapOut }

Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)
matchAnimation(DialogAnimation animationType) {
  switch (animationType) {
    case DialogAnimation.fade:
      return (context, animation1, animation2, child) {
        return Text('todo 淡入淡出弹窗');
      };
    case DialogAnimation.slide:
      return (context, animation1, animation2, child) {
        return Text('todo 划入划出弹窗');
      };
    case DialogAnimation.popup:
      return (context, animation1, animation2, child) {
        return Text('todo 弹入');
      };
    case DialogAnimation.leapOut:
      return (context, animation1, animation2, child) {
        final position = Tween<Offset>(
          begin: Offset(0.0, 0.15),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: animation1,
            curve: Curves.easeOutBack,
            //reverseCurve: Curves.easeIn,
          ),
        );

        final opacity = CurvedAnimation(
          parent: animation1,
          curve: Interval(0.2, 0.8),
        );

        final turns = Tween(begin: -0.025, end: 0.0).animate(
          CurvedAnimation(
            parent: animation1,
            curve: Interval(0.2, 0.8, curve: Curves.easeOutBack),
          ),
        );

        return SlideTransition(
          position: position,
          child: FadeTransition(
            opacity: opacity,
            child: RotationTransition(
              turns: turns,
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: 2,
                  sigmaY: 2,
                  tileMode: TileMode.mirror,
                ),
                child: child,
              ),
            ),
          ),
        );
      };
  }
}

Future<T?> showAnimatedDialog<T extends Object?>({
  required BuildContext context,
  DialogAnimation animationType = DialogAnimation.leapOut,
  bool barrierDismissible = true,
  String barrierLabel = '',
  Color barrierColor = const Color(0x80000000),
  Duration transitionDuration = const Duration(milliseconds: 350),
  required Widget Function(BuildContext, Animation<double>, Animation<double>)
  pageBuilder,
  bool useRootNavigator = true,
  bool fullscreenDialog = false,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  bool? requestFocus,
}) {
  return showGeneralDialog<T>(
    transitionDuration: transitionDuration,
    context: context,
    barrierLabel: barrierLabel,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    useRootNavigator: useRootNavigator,
    fullscreenDialog: fullscreenDialog,
    requestFocus: requestFocus,
    anchorPoint: anchorPoint,
    routeSettings: routeSettings,
    transitionBuilder: matchAnimation(animationType),
    pageBuilder: pageBuilder,
  );
}

enum ConfirmationType { warning, notification }

Future<T?> showConfirmationPopup<T extends Object?>({
  required BuildContext context,
  required ConfirmationType type,
  String? title,
  required String content,
  Widget? widgetContent,
  required VoidCallback action,
}) {
  final theme = Theme.of(context);

  Color barrierColor = const Color(0x80000000);
  if (type == ConfirmationType.warning) {
    barrierColor = Colors.red.shade700.withAlpha(100);
  }
  bool warning = type == ConfirmationType.warning;

  return showAnimatedDialog<T>(
    context: context,
    barrierColor: barrierColor,
    pageBuilder: (context, _, _) {
      Widget child;

      if (widgetContent != null) {
        child = widgetContent;
      } else {
        child = Text(content);
      }

      return Center(
        child: Material(
          elevation: 8,
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 500,
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border(
                top: BorderSide(color: Colors.white38, width: 1.5),
                left: BorderSide(color: Colors.white38, width: 0.75),
                right: BorderSide(color: Colors.white38, width: 0.75),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              spacing: 16,
              children: [
                Row(
                  spacing: 4,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 32,
                      color:
                          warning
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurface,
                    ),
                    Text(
                      title ?? '确认',
                      style:
                          warning
                              ? theme.textTheme.titleLarge?.copyWith(
                                color: theme.colorScheme.error,
                              )
                              : theme.textTheme.titleLarge,
                    ),
                    Expanded(child: SizedBox()),
                    ReboundButton(
                      hoverElevation: 2,
                      child: Icon(Icons.close),
                      onTap: () => Navigator.pop(context),
                    ),
                  ],
                ),
                child,
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  spacing: 8,
                  children: [
                    ReboundButton(
                      backgroundColor:
                          warning
                              ? theme.colorScheme.error
                              : theme.colorScheme.secondaryContainer,
                      margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      hoverElevation: 4,
                      child: Text(
                        '确定',
                        style: TextStyle(
                          color: theme.colorScheme.onError,
                          fontSize: 18,
                        ),
                      ),
                      onTap: () {
                        action.call();
                        Navigator.pop(context);
                      },
                    ),
                    ReboundButton(
                      backgroundColor: theme.colorScheme.secondaryContainer,
                      margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      hoverElevation: 4,
                      child: Text(
                        '取消',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 18,
                        ),
                      ),
                      onTap: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Future<T?> showDefaultDialogPopup<T extends Object?>({
  required Widget Function(BuildContext, Animation<double>, Animation<double>)
  pageBuilder,
  BoxConstraints? constraints,
  EdgeInsetsGeometry? padding,
  (double? width, double? height)? boxRate,
}) {
  final key = PageKeyProvider.shellKey;
  final context = key.currentContext;
  if (context == null) throw Exception('未能找到全局context');
  final theme = Theme.of(context);

  final size = MediaQuery.of(context).size;

  final width = (boxRate?.$1 ?? 0.6) * size.width;
  final height = (boxRate?.$2 ?? 0.6) * size.height;

  final c = constraints ?? BoxConstraints(maxWidth: width, maxHeight: height);

  return showAnimatedDialog<T>(
    context: context,
    pageBuilder: (context, a1, a2) {
      return Center(
        child: Material(
          elevation: 8,
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: EdgeInsets.all(16),

            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border(
                top: BorderSide(color: Colors.white38, width: 1.5),
                left: BorderSide(color: Colors.white38, width: 0.75),
                right: BorderSide(color: Colors.white38, width: 0.75),
              ),
            ),
            child: ConstrainedBox(
              constraints: c,
              child: pageBuilder.call(context, a1, a2),
            ),
          ),
        ),
      );
    },
  );
}

// required BuildContext context,
// required Widget Function(BuildContext, Animation<double>, Animation<double>) pageBuilder,
// bool barrierDismissible = false,
// String? barrierLabel,
// Color barrierColor = const Color(0x80000000),
// Duration transitionDuration = const Duration(milliseconds: 200),
// Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)? transitionBuilder,
// bool useRootNavigator = true,
// bool fullscreenDialog = false,
// RouteSettings? routeSettings,
// Offset? anchorPoint,
// bool? requestFocus,
