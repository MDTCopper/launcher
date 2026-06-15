///[inclusive] 闭区间
///
///[exclusive] 开区间
enum BoundaryType { inclusive, exclusive }

/// [Range]范围，泛型[T]为[num]子类，[contains]默认为左闭右开
class Range<T extends num> {
  const Range(
    this.min,
    this.max, {
    this.minType = BoundaryType.inclusive,
    this.maxType = BoundaryType.exclusive,
  }) : assert(min < max, 'min < max');

  final T min;
  final T max;

  final BoundaryType minType;
  final BoundaryType maxType;

  bool contains(T value) {
    bool minCheck =
        minType == BoundaryType.inclusive ? value >= min : value > min;
    bool maxCheck =
        maxType == BoundaryType.inclusive ? value <= max : value < max;
    return minCheck && maxCheck;
  }

  bool allContains(Iterable<T> list) => list.any((it) => contains(it));

  @override
  String toString() {
    return 'Range[$min , $max]';
  }

  @override
  bool operator ==(Object other) {
    if (other is Range) {
      return min == other.min && max == other.max;
    }
    return false;
  }

  @override
  int get hashCode => min.hashCode + max.hashCode;
}

/// [T] 为范围的泛型(num子类)，[R]为对应值的泛型
class RangeRuler<T extends num, R> extends Range<T> {
  RangeRuler(super.min, super.max, this.result, {super.minType, super.maxType});

  static RangeRuler<num, num> fromJson(String json) {
    json = json.replaceAll(' ', '');
    if (!json.startsWith('Range')) {
      throw Exception('头格式应为 Range , 如 Range[ 20 , 30 ) => 50');
    }

    json = json.split('Range').last;
    final parts = json.split('=>');

    final maxBoundary =
        parts.first.endsWith(')')
            ? BoundaryType.exclusive
            : BoundaryType.inclusive;
    final minBoundary =
        parts.first.startsWith('(')
            ? BoundaryType.exclusive
            : BoundaryType.inclusive;

    final range = parts.first.split(',');

    final min = num.tryParse(range.first.substring(1)) ?? 0;
    final max =
        num.tryParse(range.last.substring(0, range.last.length - 1)) ?? 0;

    final result = num.tryParse(parts.last) ?? 0;

    return RangeRuler<num, num>(
      min,
      max,
      result,
      minType: minBoundary,
      maxType: maxBoundary,
    );
  }

  final R result;

  @override
  bool operator ==(Object other) {
    if (other is RangeRuler) {
      return min == other.min && max == other.max && result == other.result;
    }
    return false;
  }

  @override
  int get hashCode => super.hashCode + result.hashCode;

  /// [20,30)=>50
  String toJson() {
    final minBoundary = minType == BoundaryType.inclusive ? '[' : '(';
    final maxBoundary = maxType == BoundaryType.inclusive ? ']' : ')';
    return 'Range $minBoundary ${min as num} , ${max as num} $maxBoundary => ${result as num}';

    // return {'min': min, 'max': max, 'result': result};
  }
}

class RangeModifier<T extends num, R> {
  RangeModifier(this.defaultResult, this.rulers);

  final List<RangeRuler<T, R>> rulers;
  final R defaultResult;

  R resultOf(T value) {
    for (var ruler in rulers) {
      if (ruler.contains(value)) return ruler.result;
    }
    return defaultResult;
  }

  bool contains(T value) {
    return rulers.any((it) => it.contains(value));
  }

  RangeRuler<T, R> firstRulerOf(T value) {
    return rulers.firstWhere((it) => it.contains(value));
  }

  List<RangeRuler<T, R>> rulersOf(T value) {
    final List<RangeRuler<T, R>> list = [];
    for (var ruler in rulers) {
      if (ruler.contains(value)) list.add(ruler);
    }
    return list;
  }

  static RangeModifier<num, num> fromJson(Map<String, dynamic> json) {
    final rulers = json['rulers'] as List<String>;

    return RangeModifier<num, num>(
      json['default'] ?? 0,
      rulers.map((it) => RangeRuler.fromJson(it)).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'default': defaultResult,
      'rulers': rulers.map((it) => it.toJson()).toList(),
    };
  }
}
