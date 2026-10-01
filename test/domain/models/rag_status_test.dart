// test/domain/models/rag_status_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/domain/models/rag_status.dart';

void main() {
  group('RagStatus', () {
    // ============================================================
    // СОСТАВ ENUM
    // ============================================================

    group('состав', () {
      test('содержит ровно 4 значения', () {
        // Если кто-то случайно удалит case — упадём.
        // Если добавит новое — тест упадёт, и это хорошо:
        // надо будет обновить все switch'и в коде.
        expect(RagStatus.values.length, 4);
      });

      test('содержит ровно ожидаемые значения', () {
        // `unorderedEquals` — проверяет РОВНО этот набор,
        // порядок не важен. Если кто-то заменит `ready` на что-то
        // другое, сохранив длину 4, — тест упадёт.
        //
        // `containsAll` для этой проверки НЕ подходит: он проверяет
        // только «все эти элементы есть», но не «и только эти».
        expect(
          RagStatus.values,
          unorderedEquals([
            RagStatus.empty,
            RagStatus.ingesting,
            RagStatus.ready,
            RagStatus.failed,
          ]),
        );
      });

      test('значения уникальны', () {
        // Set автоматически убирает дубликаты.
        // Если размер Set != размер List — есть дубликаты.
        final unique = RagStatus.values.toSet();
        expect(unique.length, RagStatus.values.length);
      });
    });

    // ============================================================
    // NAME
    // ============================================================

    group('name', () {
      test('имена совпадают с ожидаемыми строками', () {
        // Enum.name — это имя константы как строка.
        // Важно: мы полагаемся на эти имена в маппере (D2),
        // когда будем парсить JSON. Если кто-то переименует
        // константу — упадём.
        expect(RagStatus.empty.name, 'empty');
        expect(RagStatus.ingesting.name, 'ingesting');
        expect(RagStatus.ready.name, 'ready');
        expect(RagStatus.failed.name, 'failed');
      });
    });
  });
}
