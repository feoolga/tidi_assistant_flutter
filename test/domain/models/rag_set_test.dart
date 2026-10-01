// test/domain/models/rag_set_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/domain/models/rag_config.dart';
import 'package:tidi_assistant_flutter/domain/models/rag_set.dart';
import 'package:tidi_assistant_flutter/domain/models/rag_status.dart';

void main() {
  // ============================================================
  // DocumentsCounts — ОТДЕЛЬНАЯ ГРУППА
  // ============================================================

  group('DocumentsCounts', () {
    // ---- Конструктор и дефолты ----

    group('конструктор и дефолты', () {
      test('пустой конструктор даёт все нули', () {
        const counts = DocumentsCounts();

        expect(counts.total, 0);
        expect(counts.ready, 0);
        expect(counts.failed, 0);
        expect(counts.pending, 0);
      });

      test('factory .empty() эквивалентен дефолтному', () {
        final counts = DocumentsCounts.empty();

        expect(counts.total, 0);
        expect(counts.ready, 0);
        expect(counts.failed, 0);
        expect(counts.pending, 0);
      });
    });

    // ---- isEmpty ----

    group('isEmpty', () {
      test('true при total == 0', () {
        expect(const DocumentsCounts().isEmpty, isTrue);
      });

      test('false при total > 0', () {
        const counts = DocumentsCounts(total: 5, ready: 5);
        expect(counts.isEmpty, isFalse);
      });
    });

    // ---- isComplete ----

    group('isComplete', () {
      test('false для пустого набора (0 документов)', () {
        // Пустой набор не «завершён» — там нечего завершать.
        expect(const DocumentsCounts().isComplete, isFalse);
      });

      test('true, если все документы ready', () {
        const counts = DocumentsCounts(total: 5, ready: 5);
        expect(counts.isComplete, isTrue);
      });

      test('false, если есть failed', () {
        const counts = DocumentsCounts(total: 5, ready: 4, failed: 1);
        expect(counts.isComplete, isFalse);
      });

      test('false, если есть pending', () {
        const counts = DocumentsCounts(total: 5, ready: 3, pending: 2);
        expect(counts.isComplete, isFalse);
      });
    });

    // ---- hasFailures ----

    group('hasFailures', () {
      test('false при failed == 0', () {
        expect(const DocumentsCounts().hasFailures, isFalse);
      });

      test('true при failed > 0', () {
        const counts = DocumentsCounts(total: 5, ready: 4, failed: 1);
        expect(counts.hasFailures, isTrue);
      });
    });

    // ---- readyPercent ----

    group('readyPercent', () {
      test('0 при total == 0 (не падаем на делении на ноль)', () {
        expect(const DocumentsCounts().readyPercent, 0);
      });

      test('0 при ready == 0', () {
        const counts = DocumentsCounts(total: 5, pending: 5);
        expect(counts.readyPercent, 0);
      });

      test('100 при ready == total', () {
        const counts = DocumentsCounts(total: 5, ready: 5);
        expect(counts.readyPercent, 100);
      });

      test('60 при 3 из 5', () {
        const counts = DocumentsCounts(total: 5, ready: 3, pending: 2);
        expect(counts.readyPercent, 60);
      });

      test('67 при 2 из 3 (round)', () {
        // 2/3 = 66.666... → round даёт 67.
        const counts = DocumentsCounts(total: 3, ready: 2, pending: 1);
        expect(counts.readyPercent, 67);
      });

      test('failed НЕ считается как готовое', () {
        // 3 ready, 2 failed → 60%, а не 100%.
        const counts = DocumentsCounts(total: 5, ready: 3, failed: 2);
        expect(counts.readyPercent, 60);
      });
    });
  });

  // ============================================================
  // RagSet — ОСНОВНАЯ ГРУППА
  // ============================================================

  group('RagSet', () {
    // Хелпер — создаёт набор с разумными дефолтами.
    RagSet buildSet({
      String id = 'rag-1',
      String name = 'Тестовый набор',
      String? description,
      RagStatus status = RagStatus.empty,
      DocumentsCounts? documentsCounts,
      int chunksTotal = 0,
      bool hasPending = false,
      bool hasIcon = false,
      RagConfig? config,
      DateTime? createdAt,
      DateTime? updatedAt,
    }) {
      final now = DateTime(2026, 1, 1);
      return RagSet(
        id: id,
        name: name,
        description: description,
        status: status,
        documentsCounts: documentsCounts ?? const DocumentsCounts(),
        chunksTotal: chunksTotal,
        hasPending: hasPending,
        hasIcon: hasIcon,
        config: config ?? const RagConfig(),
        createdAt: createdAt ?? now,
        updatedAt: updatedAt ?? now,
      );
    }

    // ---- Конструктор ----

    group('конструктор', () {
      test('все поля сохраняются как есть', () {
        final created = DateTime(2026, 1, 15);
        final updated = DateTime(2026, 2, 20);
        const counts = DocumentsCounts(total: 5, ready: 3, pending: 2);

        final set = buildSet(
          id: 'rag-42',
          name: 'Регламенты',
          description: 'Описание',
          status: RagStatus.ingesting,
          documentsCounts: counts,
          chunksTotal: 152,
          hasPending: true,
          hasIcon: true,
          createdAt: created,
          updatedAt: updated,
        );

        expect(set.id, 'rag-42');
        expect(set.name, 'Регламенты');
        expect(set.description, 'Описание');
        expect(set.status, RagStatus.ingesting);
        expect(set.documentsCounts, counts);
        expect(set.chunksTotal, 152);
        expect(set.hasPending, isTrue);
        expect(set.hasIcon, isTrue);
        expect(set.createdAt, created);
        expect(set.updatedAt, updated);
      });

      test('дефолтные значения', () {
        final set = buildSet();

        expect(set.description, isNull);
        expect(set.chunksTotal, 0);
        expect(set.hasPending, isFalse);
        expect(set.hasIcon, isFalse);
      });
    });

    // ---- Геттеры статуса ----

    group('isReady', () {
      test('true только для ready', () {
        expect(buildSet(status: RagStatus.ready).isReady, isTrue);
        expect(buildSet(status: RagStatus.empty).isReady, isFalse);
        expect(buildSet(status: RagStatus.ingesting).isReady, isFalse);
        expect(buildSet(status: RagStatus.failed).isReady, isFalse);
      });
    });

    group('isIngesting', () {
      test('true только для ingesting', () {
        expect(buildSet(status: RagStatus.ingesting).isIngesting, isTrue);
        expect(buildSet(status: RagStatus.ready).isIngesting, isFalse);
      });
    });

    group('isEmpty', () {
      test('true только для empty', () {
        expect(buildSet(status: RagStatus.empty).isEmpty, isTrue);
        expect(buildSet(status: RagStatus.ready).isEmpty, isFalse);
      });
    });

    group('isFailed', () {
      test('true только для failed', () {
        expect(buildSet(status: RagStatus.failed).isFailed, isTrue);
        expect(buildSet(status: RagStatus.ready).isFailed, isFalse);
      });
    });

    // ---- copyWith ----

    group('copyWith', () {
      test('без параметров возвращает эквивалент', () {
        final original = buildSet(
          id: 'rag-1',
          name: 'Набор',
          description: 'Описание',
          status: RagStatus.ready,
          chunksTotal: 42,
          hasIcon: true,
        );

        final copy = original.copyWith();

        expect(copy.id, original.id);
        expect(copy.name, original.name);
        expect(copy.description, original.description);
        expect(copy.status, original.status);
        expect(copy.documentsCounts, original.documentsCounts);
        expect(copy.chunksTotal, original.chunksTotal);
        expect(copy.hasPending, original.hasPending);
        expect(copy.hasIcon, original.hasIcon);
        expect(copy.config, original.config);
        expect(copy.createdAt, original.createdAt);
        expect(copy.updatedAt, original.updatedAt);
      });

      test('меняет только name', () {
        final original = buildSet(name: 'Старое');
        final copy = original.copyWith(name: 'Новое');

        expect(copy.name, 'Новое');
        expect(copy.id, original.id); // не тронуто
      });

      test('меняет только status', () {
        final original = buildSet(status: RagStatus.ingesting);
        final copy = original.copyWith(status: RagStatus.ready);

        expect(copy.status, RagStatus.ready);
        expect(copy.name, original.name); // не тронуто
      });

      // ---- Маркер для description ----

      test('copyWith(description: null) СБРАСЫВАЕТ description', () {
        final original = buildSet(description: 'Было');
        final copy = original.copyWith(description: null);

        expect(copy.description, isNull);
      });

      test('copyWith() БЕЗ description сохраняет старый', () {
        final original = buildSet(description: 'Было');
        final copy = original.copyWith();

        expect(copy.description, 'Было');
      });

      test('copyWith(description: "новое") устанавливает description', () {
        final original = buildSet();
        final copy = original.copyWith(description: 'Новое');

        expect(copy.description, 'Новое');
      });
    });
  });
}
