String timeSince(DateTime past) {
  final now = DateTime.now();
  if (past.isAfter(now)) {
    return '错误时间';
  }

  int years = now.year - past.year;
  int months = now.month - past.month;
  int days = now.day - past.day;

  //这里是时间借位扣除
  if (days < 0) months--;
  if (months < 0) {
    years--;
    months += 12;
  }

  if (years > 3) return '更早';

  if (years >= 1)return '$years 年前';

  if (months >= 1) return '$months 月前';

  final diff = now.difference(past);
  final daysTotal = diff.inDays;

  if (daysTotal >= 1) return '$daysTotal 天前';

  final hours = diff.inHours;
  if (hours >= 1) return '$hours 小时前';

  return '刚刚';
}