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
  });

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
  RangeRuler(super.min, super.max, this.result);

  static RangeRuler<int, int> fromJson(Map<String, dynamic> json) {
    final min = json['min'] ?? 0;
    final max = json['max'] ?? 0;
    final result = json['value'] ?? 0;
    return RangeRuler<int, int>(min, max, result);
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

  Map<String, dynamic> toJson() {
    return {'min': min, 'max': max, 'result': result};
  }
}

//todo 开区间和闭区间
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

  static RangeModifier<int, int> fromJson(Map<String, dynamic> json) {
    final rulers = json['rulers'].map((it) => RangeRuler.fromJson(it)).toList();
    return RangeModifier<int, int>(
      json['default'] ?? 0,
      rulers as List<RangeRuler<int, int>>? ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'default': defaultResult,
      'rulers': rulers.map((it) => it.toJson()).toList(),
    };
  }
}
