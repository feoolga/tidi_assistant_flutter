// test/core/utils/date_format_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/core/utils/date_format.dart';

void main() {
  // ============================================================
  // formatShortDate — dd.MM.yyyy
  // ============================================================

  group('formatShortDate', () {
    test('добавляет ведущий ноль к дню и месяцу', () {
      expect(formatShortDate(DateTime(2026, 1, 5)), '05.01.2026');
    });

    test('не добавляет ноль, если он не нужен', () {
      expect(formatShortDate(DateTime(2026, 11, 25)), '25.11.2026');
    });

    test('работает для конца года', () {
      expect(formatShortDate(DateTime(2026, 12, 31)), '31.12.2026');
    });

    test('работает для начала года', () {
      expect(formatShortDate(DateTime(2026, 1, 1)), '01.01.2026');
    });
  });

  // ============================================================
  // formatRelative — «только что», Nм, Nч, Nд
  // ============================================================

  group('formatRelative', () {
    final now = DateTime(2026, 11, 5, 14, 35);

    test('меньше минуты → «только что»', () {
      final date = now.subtract(const Duration(seconds: 30));
      expect(formatRelative(date, now: now), 'только что');
    });

    test('ровно 0 секунд → «только что»', () {
      expect(formatRelative(now, now: now), 'только что');
    });

    test('несколько минут → Nм', () {
      final date = now.subtract(const Duration(minutes: 5));
      expect(formatRelative(date, now: now), '5м');
    });

    test('несколько часов → Nч', () {
      final date = now.subtract(const Duration(hours: 3));
      expect(formatRelative(date, now: now), '3ч');
    });

    test('несколько дней → Nд', () {
      final date = now.subtract(const Duration(days: 2));
      expect(formatRelative(date, now: now), '2д');
    });

    test('ровно 1 час — уже «1ч», не «60м»', () {
      // Важно: inHours округляет вниз, 60 минут = 1 час.
      final date = now.subtract(const Duration(minutes: 60));
      expect(formatRelative(date, now: now), '1ч');
    });

    test('ровно 1 день — «1д»', () {
      final date = now.subtract(const Duration(hours: 24));
      expect(formatRelative(date, now: now), '1д');
    });
  });

  // ============================================================
  // formatTime — HH:mm
  // ============================================================

  group('formatTime', () {
    test('добавляет ведущий ноль к часу и минуте', () {
      expect(formatTime(DateTime(2026, 11, 5, 9, 5)), '09:05');
    });

    test('работает для полудня', () {
      expect(formatTime(DateTime(2026, 11, 5, 12, 0)), '12:00');
    });

    test('работает для полуночи', () {
      expect(formatTime(DateTime(2026, 11, 5, 0, 0)), '00:00');
    });

    test('работает для конца дня', () {
      expect(formatTime(DateTime(2026, 11, 5, 23, 59)), '23:59');
    });
  });
}
