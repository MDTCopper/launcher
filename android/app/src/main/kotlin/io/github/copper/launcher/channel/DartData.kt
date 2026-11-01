package io.github.copper.launcher.channel

/**
 * 跨通道的结构体：调用方向的参数 / 返回值（事件方向用 Dart 侧的 `@KotlinData`）。
 *
 * 生成器把它翻成 Dart 数据类（含 `fromMap` / `toMap`）；过通道就是 `Map<String, Object?>`，
 * 字段名当 key —— 通道只认基础值。
 *
 * ## 定义归被调方
 *
 * Dart 调 Kotlin 时被调方是 Kotlin，所以结构体在这里声明，Dart 侧拿生成镜像；
 * Kotlin 推事件给 Dart 时被调方是 Dart，那类结构体写在 Dart 侧并标 `@KotlinData`，
 * Kotlin 镜像由生成器产出。两边各只有一处定义，不会漂移。
 *
 * ## 约束（生成阶段强制）
 *
 * - 顶层 `class`，不嵌套；一个结构体只服务一个方向（不做双栖）。
 * - 字段只能在主构造里用 `val` 声明，类型限 `String` / `Boolean` / `Int` / `Long` /
 *   `Double` / `List<String>`（各自可空）。
 * - 不支持嵌套结构体、`Map`、`Set`、enum、`DateTime`、任意对象，也没有循环引用。
 * - 字段名两侧一致；按值拷贝，没有引用/身份语义。
 */
@Target(AnnotationTarget.CLASS)
@Retention(AnnotationRetention.SOURCE)
annotation class DartData
