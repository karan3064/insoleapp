/// Ported from `utils/tool.js`.
class FormatUtils {
  FormatUtils._();

  static String getTestTime([DateTime? now]) {
    final n = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)} ${two(n.hour)}:${two(n.minute)}';
  }

  static String secondsToMinutesString(int seconds) {
    final minutes = seconds ~/ 60;
    final remaining = seconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(minutes)} : ${two(remaining)}';
  }
}
