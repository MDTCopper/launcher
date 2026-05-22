
import 'package:copperlauncher_main/ui/feature/feature_color.dart';
import 'package:copperlauncher_main/ui/util/framework/main_framework.dart';
import 'package:copperlauncher_main/ui/util/route/page_key_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void runCopperLauncher() {
  runApp(CopperLauncher());
}

class CopperLauncher extends StatelessWidget {
  const CopperLauncher({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Copper',

      theme: ThemeData(
        fontFamily: 'sc',

        colorScheme: ColorScheme.light(
          primary: Color(0xFFC89958), // 主铜色
          primaryContainer: Color(0xFFF0E9E0), // 浅铜过渡色
          secondary: Color(0xFFC8A06E), // 深铜强调色
          secondaryContainer: Color(0xFFF9F5F0), // 米白辅助色
          background: Color(0xFFFFFFFF), // 白色页面背景
          surface: Color(0xFFFFFFFF), // 白色卡片背景
          surfaceVariant: Color(0xFFF9F9F9), // 浅灰白次要容器
          error: Color(0xFFD96666), // 错误色
          onPrimary: Color(0xFFFFFFFF), // 主色上的文本（白色）
          onSecondary: Color(0xFFFFFFFF), // 次要色上的文本（白色）
          onBackground: Color(0xFF333333), // 白色背景上的文本（深灰）
          onSurface: Color(0xFF333333), // 卡片上的文本（深灰）
          onError: Color(0xFFFFFFFF), // 错误色上的文本（白色）
          outline: Color(0xFFEAEAEA), // 边框颜色
        ),

        // 2. 文本样式（柔和对比，护眼优先）
        textTheme: TextTheme(
          displayLarge: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
            height: 1.2,
          ),
          displayMedium: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
            height: 1.2,
          ),
          titleLarge: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            color: Color(0xFF333333),
            height: 1.5,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            color: Color(0xFF666666),
            height: 1.5,
          ),
          bodySmall: TextStyle(fontSize: 12, color: Color(0xFF999999)),
          labelLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFFFFFFFF),
          ), // 按钮白色文本
        ),

        // 3. 页面背景色
        scaffoldBackgroundColor: Color(0xFFC89958),

        // 4. 卡片样式（柔和立体，无突兀阴影）
        cardTheme: CardThemeData(
          color: Color(0xFFF9F9F9), // 卡片背景（比页面稍深）
          elevation: 1, // 极弱阴影，避免强光反射
          shadowColor: Color(0xFF000000).withAlpha(60), // 浅透明阴影
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        // segmentedButtonTheme: SegmentedButtonThemeData(
        //   style: ButtonStyle(
        //
        //   )
        // ),

        // 5. 按钮样式（浅灰柔和，反馈清晰）
        // elevatedButtonTheme: ElevatedButtonThemeData(
        //   style: ButtonStyle(
        //     backgroundColor: MaterialStateProperty.all(Color(0xFFF0F0F0)), // 按钮浅灰
        //     foregroundColor: MaterialStateProperty.all(Color(0xFF555555)), // 中灰文本
        //     padding: MaterialStateProperty.all(
        //       EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        //     ),
        //     shape: MaterialStateProperty.all(
        //       RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        //     ),
        //     elevation: MaterialStateProperty.resolveWith((states) {
        //       if (states.contains(MaterialState.pressed)) return 0; // 按压时无阴影
        //       if (states.contains(MaterialState.hovered)) return 2; // 悬浮时弱阴影
        //       return 1;
        //     }),
        //     overlayColor: MaterialStateProperty.all(Color(0xFFE5E5E5)), // 按压反馈（中灰）
        //   ),
        // ),

        // 6. 文本按钮样式（中灰文本，无背景）
        // textButtonTheme: TextButtonThemeData(
        //   style: ButtonStyle(
        //     foregroundColor: MaterialStateProperty.all(Color(0xFF666666)), // 中灰文本
        //     hoverColor: MaterialStateProperty.all(Color(0xFFF0F0F0).withOpacity(0.5)), // 悬浮背景（浅灰）
        //     padding: MaterialStateProperty.all(
        //       EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        //     ),
        //   ),
        // ),

        // 7. 输入框样式（柔和边框，浅灰背景）
        inputDecorationTheme: InputDecorationTheme(
          isDense: true,
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF666666)),
            borderRadius: BorderRadius.circular(4),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFFC89958), width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFFC89958), width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          errorBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFFD96666)),
            borderRadius: BorderRadius.circular(4),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFFD96666), width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          fillColor: Color(0x55F5DAB6),
          filled: true,
          hintStyle: TextStyle(color: Color(0xFFBBBBBB), fontSize: 14),
          labelStyle: TextStyle(color: Color(0xFF666666), fontSize: 14),
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        ),

        // 8. 开关样式（柔和无彩色）
        // switchTheme: SwitchThemeData(
        //   activeColor: Color(0xFFE5E5E5), // 开启滑块（中灰）
        //   activeTrackColor: Color(0xFFF0F0F0), // 开启轨道（浅灰）
        //   inactiveThumbColor: Color(0xFFFFFFFF), // 关闭滑块（纯白，点缀）
        //   inactiveTrackColor: Color(0xFFEAEAEA), // 关闭轨道（浅灰）
        //   trackBorderColor: MaterialStateProperty.all(Color(0xFFF5F5F5)),
        // ),
        hoverColor: Color(0xFFC89958).withAlpha(30),
        highlightColor: Color(0xFFC89958).withAlpha(30),
        splashColor: Color(0xFFC89958).withAlpha(30),
        focusColor: Color(0xFFC89958).withAlpha(30),

        // 10. 导航栏样式（柔和近白）
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFFC89958), // 导航栏背景
          elevation: 1,
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF222222),
          ),
          toolbarTextStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFFC8A06E),
          ),

          iconTheme: IconThemeData(color: Color(0xFFFFFFFF)),
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarBrightness: Brightness.light,
            statusBarIconBrightness: Brightness.dark, // 状态栏图标黑色（柔和对比）
          ),
        ),

        // 11. 图标样式
        iconTheme: IconThemeData(color: Color(0xFFC8A06E), size: 24),
        // 12. 分割线样式
        dividerTheme: DividerThemeData(
          color: Color(0xFFC8A06E),
          space: 1,
          thickness: 1,
        ),
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: Color(0xFFC89958),
          linearTrackColor: Color(0xFFC89958).withAlpha(85),
        ),

        scrollbarTheme: ScrollbarThemeData(
          radius: Radius.circular(8),
          thumbColor: WidgetStateProperty.resolveWith<Color?>((status) {
            if (status.contains(WidgetState.dragged)) {
              return Colors.grey.shade500;
            }
            if (status.contains(WidgetState.hovered)) {
              return Colors.grey.shade600;
            }
            return Colors.grey.shade600.withAlpha(85);
          }),
          trackColor: WidgetStateProperty.resolveWith<Color?>((status) {
            if (status.contains(WidgetState.hovered) ||
                status.contains(WidgetState.dragged)) {
              return Colors.grey.shade600.withAlpha(85);
            }
            return Colors.grey.withAlpha(55);
          }),
        ),
        sliderTheme: SliderThemeData(
          trackHeight: 8,
          activeTrackColor: Color(0xFFC89958),
          inactiveTrackColor: Color(0xFFC89958).withAlpha(85),
          disabledActiveTrackColor: Color(0xFFC89958).withAlpha(100),
          disabledInactiveTrackColor: Color(0xFFC89958).withAlpha(30),
          disabledThumbColor: Color(0xFFC89958).withAlpha(185),
          overlayShape: RoundSliderOverlayShape(overlayRadius: 18),
          overlayColor: Color(0xFFC89958).withAlpha(55),
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 10),
        ),
        switchTheme: SwitchThemeData(
          padding: EdgeInsets.all(0),
          overlayColor: WidgetStatePropertyAll(Color(0xFFC89958).withAlpha(55)),
          thumbColor: WidgetStateProperty.resolveWith((status) {
            if (status.contains(WidgetState.disabled)) {
              if (status.contains(WidgetState.selected)) {
                return Color(0xFFC89958).withAlpha(185);
              }
              return Color(0xFFC89958).withAlpha(85);
            }
            if (status.contains(WidgetState.focused) ||
                status.contains(WidgetState.hovered)) {
              if (status.contains(WidgetState.selected)) {
                return Color(0xFFF0E9E0);
              } else {
                return Color(0xFFC89958);
              }
            }
            if (status.contains(WidgetState.selected)) {
              return Color(0xFFF0E9E0);
            }
            return Color(0xFFC89958);
          }),
          trackOutlineWidth: WidgetStateProperty.resolveWith((status) {
            if (status.contains(WidgetState.disabled)) {
              return 1.0;
            }
            return 2.0;
          }),
          trackColor: WidgetStateProperty.resolveWith((status) {
            if (status.contains(WidgetState.disabled)) {
              if (status.contains(WidgetState.selected)) {
                return Color(0xFFC89958).withAlpha(55);
              }
              return Color(0xFFC89958).withAlpha(25);
            }
            return null;
          }),
          trackOutlineColor: WidgetStateProperty.resolveWith((status) {
            if (status.contains(WidgetState.disabled)) {
              return Color(0xFFC89958).withAlpha(185);
            }
            return Color(0xFFC89958);
          }),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),

      darkTheme: ThemeData(
        fontFamily: 'sc',
        // 1. 核心颜色方案（仅黑/灰渐变，无额外主色）
        colorScheme: ColorScheme.dark(
          primary: FeatureColors.deepCharcoal, // 主色（深灰，替代鲜明色彩）
          primaryContainer: FeatureColors.matteBlack, // 主色容器（深灰偏黑）//容器背景
          secondary: FeatureColors.midToneGrayishBlack, // 次要色（中灰，用于强调元素）
          secondaryContainer: Color(0xFF1A1A1A), // 页面背景（纯黑，极致护眼）
          surface: Color(0xFF111111), // 卡片/容器背景（近黑，与页面区分）
          surfaceContainerHighest: Color(0xFF1A1A1A), // 次要容器背景（深灰）
          error: Color(0xFF552222), // 错误色（暗红灰，不突兀）
          onPrimary: Color(0xFFEEEEEE), // 主色上的文本（浅灰，保证可读）
          onSecondary: Color(0xFFEEEEEE), // 页面背景文本（浅灰，护眼）
          onSurface: Color(0xFFDDDDDD), // 卡片文本颜色
          onError: Color(0xFFFFCCCC), // 错误文本颜色（浅红，不刺眼）
          outline: Color(0xFF333333), // 边框颜色（深灰，不突兀）
        ),

        // 2. 文本样式（纯黑调统一风格，层次分明）
        textTheme: TextTheme(
          displayLarge: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Color(0xFFEEEEEE),
            height: 1.2,
          ),
          displayMedium: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFFEEEEEE),
            height: 1.2,
          ),
          titleLarge: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFFEEEEEE),
          ),
          // 主要正文（核心内容）
          bodyLarge: TextStyle(
            fontSize: 16,
            color: Color(0xFFDDDDDD),
            height: 1.5,
          ),
          // 次要正文
          bodyMedium: TextStyle(
            fontSize: 14,
            color: Color(0xFFBBBBBB),
            height: 1.5,
          ),
          // 辅助文本（提示、说明）
          bodySmall: TextStyle(fontSize: 12, color: Color(0xFF888888)),
          // 按钮文本
          labelLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0x00ffffff),
          ),
        ),

        // 3. 页面背景色（纯黑）
        scaffoldBackgroundColor: Color(0xFF000000),

        // 7. 输入框样式（纯黑调，无多余色彩）
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF333333)),
            borderRadius: BorderRadius.circular(6),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(
              color: Color(0xFF555555),
              width: 2,
            ), // 聚焦时深灰边框
            borderRadius: BorderRadius.circular(6),
          ),
          errorBorder: OutlineInputBorder(
            borderSide: BorderSide(
              color: Color(0xFF552222),
              width: 1.5,
            ), // 错误暗红灰边框
            borderRadius: BorderRadius.circular(6),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF663333), width: 2),
            borderRadius: BorderRadius.circular(6),
          ),
          fillColor: Color(0xFF111111), // 输入框背景（近黑）
          filled: true,
          hintStyle: TextStyle(
            color: Color(0xFF777777),
            fontSize: 14,
          ), // 提示文本（中灰）
          labelStyle: TextStyle(
            color: Color(0xFFBBBBBB),
            fontSize: 14,
          ), // 标签文本（浅灰）
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),

        // 9. 精简交互反馈（无多余水波纹）
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,

        // 10. 导航栏样式（纯黑+浅灰图标）
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFF111111), // 导航栏背景（近黑）
          elevation: 2,
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFFEEEEEE),
          ),
          iconTheme: IconThemeData(color: Color(0xFFBBBBBB)), // 图标浅灰
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarBrightness: Brightness.dark,
            statusBarIconBrightness: Brightness.light,
          ),
        ),

        // 11. 图标样式（浅灰，统一风格）
        iconTheme: IconThemeData(color: Color(0xFFBBBBBB), size: 24),

        // 12. 分割线样式（深灰，不突兀）
        dividerTheme: DividerThemeData(thickness: 1, space: 1),
      ),

      themeMode: ThemeMode.light,
      debugShowCheckedModeBanner: false,
      home: MainFrameWork(key: PageKeyProvider.globalKey),
    );
  }
}
