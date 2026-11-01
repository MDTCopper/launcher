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
