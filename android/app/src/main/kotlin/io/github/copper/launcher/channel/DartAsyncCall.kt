package io.github.copper.launcher.channel

/**
 * Dart 调用的静态方法，但宿主侧会阻塞（等进程消失、遍历 task、跑 dex 构建之类）。
 *
 * 生成器把它放进 `Thread`，干完 `post` 回主线程再 `result.success`：Flutter 的平台线程
 * 不能等，阻塞在这里会卡住整条通道。异常同样回到主线程（`call_failed`）。
 *
 * 静态方法约束、参数注入、允许的类型与 [DartCall] **完全一致**（含 `@DartData` 结构体），
 * 区别只有线程语义；同一个方法不要两个注解都标。
 *
 * 注意：异步不等于可取消。Dart 侧把 `Future` 丢了，宿主线程里的活仍会跑完。
 */
@Target(AnnotationTarget.FUNCTION)
@Retention(AnnotationRetention.SOURCE)
annotation class DartAsyncCall
