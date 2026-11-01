package io.github.copper.launcher.channel

/**
 * Dart 直接调用的静态方法（同步）。生成器据此接进 `AndroidCall`。
 *
 * ## 只能标在静态方法上
 *
 * 允许 `object` 成员、`companion object` 成员、顶层函数。标在实例方法上会在生成阶段
 * 报错：生成器要写 `Receiver.method(...)`，实例方法没有可写的接收者。
 *
 * ## 参数注入（按参数名，Dart 侧不传）
 *
 * - `activityContext: Activity` → 当前 Activity；
 * - `applicationContext: Context` → `activity.applicationContext`。
 *
 * ## 参数 / 返回值允许的类型（其余类型生成阶段报错）
 *
 * ```
 * Kotlin                   Dart                  通道上的值
 * Unit（仅返回值）          void                  null
 * String / String?         String / String?      String
 * Boolean / Boolean?       bool / bool?          bool
 * Int / Long（含 ?）        int / int?            int
 * Double（含 ?）            double / double?      double
 * List<String>（含 ?）      List<String>（含 ?）   List
 * Array<String>（仅参数）   List<String>          List
 * @DartData X（含 ?）       X 的生成镜像（含 ?）   Map<String, Object?>
 * ```
 *
 * Kotlin 返回非空类型却给了 `null` 时，Dart 侧兜底：`false` / `0` / `''` / `const []`。
 *
 * ## 结构体
 *
 * 参数 / 返回值里的结构体只能是 Kotlin 顶层 `@DartData`（见 [DartData]）：Dart 侧的类型
 * 是生成镜像，不要手写；过通道就是 `Map<String, Object?>`，字段名当 key。
 *
 * ## 阻塞就别用这个
 *
 * 宿主侧会阻塞的实现标 [DartAsyncCall]（`Thread` + 主线程回包），否则会卡住平台线程。
 *
 * ## 非安卓平台
 *
 * 生成层统一短路：`void` 直接返回，可空类型返回 `null`，非空的标量 / 列表返回默认值；
 * 调用点不需要各自判断平台，也不会因为通道不存在抛异常。
 */
@Target(AnnotationTarget.FUNCTION)
@Retention(AnnotationRetention.SOURCE)
annotation class DartCall
