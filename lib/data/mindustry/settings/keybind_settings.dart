import 'package:copper_launcher/data/mindustry/settings/key_code.dart';
import 'package:copper_launcher/data/mindustry/settings/settings.dart';

/// 键位在 settings.bin 里的键名前缀（arc `KeyBind.settingsKey()`）
///
/// 游戏按 `keybind-<分区>-<设备>-<名字>` 存：分区固定 default、设备固定
/// keyboard（键位表只处理键盘这一套），后面接 `-single` / `-key` / `-min` / `-max`
const String mindustryKeybindPrefix = 'keybind-default-keyboard-';

/// 某个键位在 settings.bin 里的自定义值
///
/// 单键用 [key]，轴键位用 [min] / [max]；值为键码序号。
/// [MindustryKeybindAccess.keybindValue] 返回 null 表示没自定义，按游戏默认
class MindustryKeybindValue {
  const MindustryKeybindValue.single(this.key) : min = null, max = null;

  const MindustryKeybindValue.axis(this.min, this.max) : key = null;

  final int? key;
  final int? min;
  final int? max;

  bool get isAxis => key == null;
}

extension MindustryKeybindAccess on MindustrySettings {
  /// 读某个键位的自定义值；没写过（或写得读不出有效键）返回 null
  ///
  /// 判定照搬游戏 `KeyBind.load()`：先看 `-single`（缺省 true），单键读 `-key`
  /// （缺省 -1，负数按没绑处理）；轴键位读 `-min` / `-max`（缺省 unset，
  /// 任一侧是 unset 就按没绑处理）
  MindustryKeybindValue? keybindValue(String name) {
    final prefix = '$mindustryKeybindPrefix$name';
    final single = getBool('$prefix-single', true);
    if (single) {
      if (!containsKey('$prefix-key')) return null;
      final ordinal = getInt('$prefix-key', -1);
      return ordinal < 0 ? null : MindustryKeybindValue.single(ordinal);
    }

    final min = getInt('$prefix-min', mindustryUnsetKeyOrdinal);
    final max = getInt('$prefix-max', mindustryUnsetKeyOrdinal);
    if (min == mindustryUnsetKeyOrdinal || max == mindustryUnsetKeyOrdinal) {
      return null;
    }
    return MindustryKeybindValue.axis(min, max);
  }

  /// 写成单键；顺手清掉轴键位的旧值，免得文件里留着两份互相矛盾的值
  void setKeybindSingle(String name, int ordinal) {
    final prefix = '$mindustryKeybindPrefix$name';
    this['$prefix-single'] = true;
    this['$prefix-key'] = ordinal;
    remove('$prefix-min');
    remove('$prefix-max');
  }

  /// 写成双键轴；顺手清掉单键的旧值
  void setKeybindAxis(String name, int min, int max) {
    final prefix = '$mindustryKeybindPrefix$name';
    this['$prefix-single'] = false;
    this['$prefix-min'] = min;
    this['$prefix-max'] = max;
    remove('$prefix-key');
  }

  /// 删掉该键位的自定义值，让游戏回到自己的默认键
  void resetKeybind(String name) {
    final prefix = '$mindustryKeybindPrefix$name';
    remove('$prefix-single');
    remove('$prefix-key');
    remove('$prefix-min');
    remove('$prefix-max');
  }
}
