# 应用组件：清单里的类通常已由 AGP 保留，这里显式写死，避免 R8 full mode 下的意外。
-keep class io.github.copper.launcher.CopperApplication { *; }
-keep class io.github.copper.launcher.CopperComponentFactory { *; }
-keep class io.github.copper.launcher.game.MindustryActivity { *; }
-keep class io.github.copper.launcher.MainActivity { *; }
-keep class io.github.copper.launcher.SilentLaunchActivity { *; }

# 生成的桥（AndroidCall / AndroidEvent）：通道名是字符串，handler 走 MethodChannel 反射式接线。
-keep class io.github.copper.launcher.generated.** { *; }

# 外置 jar 的入口由 ContainerClassLoader 加载；应用侧这两个入口保持可调用。
-keep class io.github.copper.launcher.launch.Bridge { *; }
-keep class io.github.copper.launcher.launch.Loader { *; }

# 桥活动的子类：只由组件工厂按名字反射加载，父类在 bridge.jar 里，R8 看不到引用，必须保住。
-keep class io.github.copper.launcher.game.CopperGameActivity { *; }

# 桥的类只在编译期出现（compileOnly，见 build.gradle.kts），运行期由载荷里的 bridge.jar 提供；
# R8 看不到它们，别把「缺父类 / 缺成员」报成错误。
-dontwarn copper.bridge.**
