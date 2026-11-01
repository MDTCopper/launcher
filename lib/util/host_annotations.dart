/// Android → Dart 事件的标记注解
///
/// 只标在**现有** `static void` 事件方法上：方法名就是事件名（`on` 开头），参数就是载荷。
/// 生成器生成 `AndroidEvent` 时直接 static 调用它 —— 没有"注册回调"这一步，通道 handler
/// 只在 `AndroidEvent.start()` 里装一次（装之前发出的事件会丢，冷启动那次的数据由各功能
/// 自己的 `take*` 补取）。
///
/// ## 载荷允许的类型（其余类型生成阶段报错）
///
/// ```
/// Dart                   Kotlin（生成的 send* 签名）
/// String / String?       String / String?
/// bool / bool?           Boolean / Boolean?
/// int / int?             Int / Int?
/// double / double?       Double / Double?
/// List<String>（含 ?）    List<String>（含 ?）
/// @KotlinData X（含 ?）   X 的 Kotlin 镜像（含 ?）
/// ```
///
/// 载荷固定是「位置参数列表」：0 个参数发 `null`，N 个发 `listOf(...)`；结构体在列表里
/// 是 `Map<String, Object?>`，Dart 侧用生成的 `_xFromMap` 还原成 [KotlinData] 声明的类。
///
/// 事件所在的类、方法、结构体类与字段都要是 public（不能以 `_` 开头）：生成代码在
/// 另一个库里调用/构造它们，Dart 的 `_` 是库私有的。
class KotlinEvent {
  const KotlinEvent();
}

/// 事件载荷的结构体：**声明在被调方（Dart）**，Kotlin 镜像由生成器产出
///
/// 只写在顶层 class 上，类要长这样（字段名两个方向一致，走通道就是 Map）：
///
/// ```dart
/// @KotlinData()
/// class SharedFilesPayload {
///   const SharedFilesPayload({required this.files});
///
///   final List<String> files;
/// }
/// ```
///
/// ## 约束（生成阶段强制）
///
/// - 顶层 `class`，不嵌套；一个结构体只服务事件方向（调用方向的结构体在 Kotlin 用
///   `@DartData`，由 Dart 侧生成镜像 —— 谁被调用，谁拥有定义）。
/// - 字段只能是 `String` / `bool` / `int` / `double` / `List<String>`（各自可空）。
/// - 不支持嵌套结构体、`Map`、`Set`、enum、`DateTime`、任意对象，也没有循环引用。
/// - 字段名两侧一致；按值拷贝，没有引用/身份语义。
/// - 必须提供 `const X({required this.字段, ...})` 构造，字段用 `final` 声明。
/// - 结构体名、字段名不能以 `_` 开头（生成代码在另一个库里构造它）。
class KotlinData {
  const KotlinData();
}

/// 与 Kotlin 侧 `@DartCall` 写法一致的常量形式（`@KotlinEvent` 直接用类名也行）
const kotlinEvent = KotlinEvent();
