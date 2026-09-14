// ignore_for_file: constant_identifier_names

const B = 1;
const KB = B * 1024;
const MB = KB * 1024;
const GB = MB * 1024;

/// 字节数转短文本：按 B / KB / MB / GB 逐级取整，默认一位小数
///
/// 例：`formatBytes(0)` → `0B`、`formatBytes(1536)` → `1.5KB`、`formatBytes(3 * GB)` → `3.0GB`
///
/// 只管显示、保持短（不补空格、不做千位分隔），方便塞进状态行与列表
String formatBytes(int bytes, {int decimals = 1}) {
  if (bytes >= GB) return '${(bytes / GB).toStringAsFixed(decimals)}GB';
  if (bytes >= MB) return '${(bytes / MB).toStringAsFixed(decimals)}MB';
  if (bytes >= KB) return '${(bytes / KB).toStringAsFixed(decimals)}KB';
  return '${bytes}B';
}
