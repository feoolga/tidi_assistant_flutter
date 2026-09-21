// lib/core/utils/date_format.dart

/// Утилиты форматирования дат для UI.
///
/// Каждая функция отвечает за **один** формат, чтобы не было путаницы:
/// - [formatShortDate] — абсолютная дата (`05.11.2026`);
/// - [formatRelative] — относительное время (`5м`, `2ч`, `3д`);
/// - [formatTime] — время суток (`14:35`).
///
/// Все функции чистые (не зависят от `BuildContext`, `DateTime.now()`
/// внутри [formatRelative] — параметр `now` по умолчанию), поэтому
/// легко тестируются без виджетов.
library;

/// Абсолютная дата в формате `dd.MM.yyyy`.
///
/// Пример: `DateTime(2026, 11, 5)` → `"05.11.2026"`.
///
/// Используется в `ChatSession.displayTitle`, когда у чата нет названия.
String formatShortDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year;
  return '$day.$month.$year';
}

/// Относительное время: «только что», `5м`, `2ч`, `3д`.
///
/// Логика:
/// - меньше минуты → «только что»;
/// - меньше часа → `Nм`;
/// - меньше суток → `Nч`;
/// - больше суток → `Nд`.
///
/// Параметр [now] добавлен для **тестируемости**: в тестах мы не можем
/// подменить `DateTime.now()`, поэтому передаём его явно. В UI —
/// не передаём, используется текущее время.
///
/// Используется в `ChatHistoryDrawer` для времени последнего
/// обновления чата.
String formatRelative(DateTime date, {DateTime? now}) {
  final effectiveNow = now ?? DateTime.now();
  final diff = effectiveNow.difference(date);

  if (diff.inDays > 0) {
    return '${diff.inDays}д';
  } else if (diff.inHours > 0) {
    return '${diff.inHours}ч';
  } else if (diff.inMinutes > 0) {
    return '${diff.inMinutes}м';
  } else {
    return 'только что';
  }
}

/// Время суток в формате `HH:mm`.
///
/// Пример: `DateTime(2026, 11, 5, 14, 35)` → `"14:35"`.
///
/// Используется в `MessageBubble` для отображения времени сообщения.
String formatTime(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
