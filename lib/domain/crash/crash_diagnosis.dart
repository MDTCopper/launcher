/// 崩溃诊断对外暴露的结构
///
/// UI 只认这里的字段；码与文案分开，换文案不影响调用方
library;

/// 诊断的展示级别
enum CrashSeverity {
  /// 认定了原因，要弹窗
  fatal,

  /// 崩了但只能给「可能原因」
  degraded,

  /// 不致命，只进日志不弹窗
  info,
}

/// 可以给用户一键做的事
///
/// 这里只描述，执行由 UI 决定
enum CrashAction {
  /// 打开本次游戏日志
  openGameLog,

  /// 打开崩溃报告所在目录
  openCrashFolder,

  /// 导出诊断包
  exportBundle,

  /// 把本版本内存调高一档
  raiseMemory,

  /// 换 Java
  pickJava,

  /// 置灰被点名的模组
  disableMod,

  /// 打开版本设置
  openVersionSettings,

  /// 重装桥运行环境
  reinstallBridge,

  /// 没有可执行的动作
  none,
}

/// 一条诊断结论
class CrashDiagnosis {
  const CrashDiagnosis({
    required this.code,
    required this.severity,
    required this.fatal,
    required this.title,
    required this.detail,
    required this.matchedRuleId,
    this.suggestions = const [],
    this.evidenceExcerpt,
    this.action = CrashAction.none,
  });

  /// 稳定的错误码，UI 与用例按它断言
  final String code;

  /// 展示级别
  final CrashSeverity severity;

  /// 这一局是不是真的崩了；非致命结论必须是 false
  final bool fatal;

  /// 短语，给通知标题用
  final String title;

  /// 为什么这么判，两到三行
  final String detail;

  /// 命中的规则 id；兜底结论为空串
  final String matchedRuleId;

  /// 用户能做的事，按顺序展示
  final List<String> suggestions;

  /// 命中行前后几行的原文；命中非文本信号时为空
  final String? evidenceExcerpt;

  /// 建议的一键动作，可以没有
  final CrashAction action;
}
