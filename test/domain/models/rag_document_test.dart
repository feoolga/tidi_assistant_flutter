// test/domain/models/rag_document_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/domain/models/rag_document.dart';
import 'package:tidi_assistant_flutter/domain/models/rag_document_status.dart';

void main() {
  group('RagDocument', () {
    // Общий объект для тестов — пересоздаём в каждом тесте через хелпер.
    // Так тесты независимы, и mutation в одном не влияет на другой.
    RagDocument buildDocument({
      String id = 'doc-1',
      String filename = 'a.pdf',
      int sizeBytes = 1024,
      DateTime? createdAt,
      RagDocumentStatus status = RagDocumentStatus.pending,
      int chunksCount = 0,
      String? error,
      String? duplicateOf,
    }) {
      return RagDocument(
        id: id,
        filename: filename,
        sizeBytes: sizeBytes,
        createdAt: createdAt ?? DateTime(2026, 1, 1),
        status: status,
        chunksCount: chunksCount,
        error: error,
        duplicateOf: duplicateOf,
      );
    }

    // ============================================================
    // КОНСТРУКТОР И ДЕФОЛТЫ
    // ============================================================

    group('конструктор и дефолты', () {
      test('дефолтные значения chunksCount/error/duplicateOf', () {
        final doc = buildDocument();

        expect(doc.chunksCount, 0);
        expect(doc.error, isNull);
        expect(doc.duplicateOf, isNull);
      });

      test('все поля сохраняются как есть', () {
        final created = DateTime(2026, 5, 15, 10, 30);
        final doc = buildDocument(
          id: 'my-id',
          filename: 'file.docx',
          sizeBytes: 2048,
          createdAt: created,
          status: RagDocumentStatus.success,
          chunksCount: 42,
        );

        expect(doc.id, 'my-id');
        expect(doc.filename, 'file.docx');
        expect(doc.sizeBytes, 2048);
        expect(doc.createdAt, created);
        expect(doc.status, RagDocumentStatus.success);
        expect(doc.chunksCount, 42);
      });
    });

    // ============================================================
    // ГЕТТЕРЫ С ЛОГИКОЙ
    // ============================================================

    group('isReady', () {
      test('true только для success', () {
        expect(
          buildDocument(status: RagDocumentStatus.success).isReady,
          isTrue,
        );
        expect(
          buildDocument(status: RagDocumentStatus.pending).isReady,
          isFalse,
        );
        expect(
          buildDocument(status: RagDocumentStatus.processing).isReady,
          isFalse,
        );
        expect(
          buildDocument(status: RagDocumentStatus.failed).isReady,
          isFalse,
        );
      });
    });

    group('isFailed', () {
      test('true только для failed', () {
        expect(
          buildDocument(status: RagDocumentStatus.failed).isFailed,
          isTrue,
        );
        expect(
          buildDocument(status: RagDocumentStatus.success).isFailed,
          isFalse,
        );
      });
    });

    group('isInProgress', () {
      test('true для pending', () {
        expect(
          buildDocument(status: RagDocumentStatus.pending).isInProgress,
          isTrue,
        );
      });

      test('true для processing', () {
        expect(
          buildDocument(status: RagDocumentStatus.processing).isInProgress,
          isTrue,
        );
      });

      test('false для success', () {
        expect(
          buildDocument(status: RagDocumentStatus.success).isInProgress,
          isFalse,
        );
      });

      test('false для failed', () {
        expect(
          buildDocument(status: RagDocumentStatus.failed).isInProgress,
          isFalse,
        );
      });
    });

    group('isDuplicate', () {
      test('true, если duplicateOf задан', () {
        final doc = buildDocument(duplicateOf: 'original-id');
        expect(doc.isDuplicate, isTrue);
      });

      test('false, если duplicateOf == null', () {
        final doc = buildDocument();
        expect(doc.isDuplicate, isFalse);
      });

      test('true, даже если duplicateOf == id', () {
        // Особый случай от бэкенда — на него НЕ полагаемся
        // как на «не дубликат». Только «!= null» — признак.
        final doc = buildDocument(id: 'same-id', duplicateOf: 'same-id');
        expect(doc.isDuplicate, isTrue);
      });
    });

    // ============================================================
    // copyWith
    // ============================================================

    group('copyWith', () {
      test('без параметров возвращает эквивалент', () {
        final original = buildDocument(
          id: 'doc-1',
          filename: 'file.pdf',
          status: RagDocumentStatus.success,
          chunksCount: 10,
        );

        final copy = original.copyWith();

        expect(copy.id, original.id);
        expect(copy.filename, original.filename);
        expect(copy.sizeBytes, original.sizeBytes);
        expect(copy.createdAt, original.createdAt);
        expect(copy.status, original.status);
        expect(copy.chunksCount, original.chunksCount);
        expect(copy.error, original.error);
        expect(copy.duplicateOf, original.duplicateOf);
      });

      test('меняет только status', () {
        final original = buildDocument(status: RagDocumentStatus.pending);
        final copy = original.copyWith(status: RagDocumentStatus.success);

        expect(copy.status, RagDocumentStatus.success);
        expect(copy.id, original.id); // не тронуто
        expect(copy.filename, original.filename); // не тронуто
      });

      test('меняет только chunksCount', () {
        final original = buildDocument(chunksCount: 0);
        final copy = original.copyWith(chunksCount: 42);

        expect(copy.chunksCount, 42);
        expect(copy.status, original.status);
      });

      // ---- Маркер для nullable-полей ----

      test('copyWith(error: null) СБРАСЫВАЕТ error', () {
        final original = buildDocument(
          status: RagDocumentStatus.failed,
          error: 'Что-то упало',
        );

        final copy = original.copyWith(error: null);

        expect(copy.error, isNull);
      });

      test('copyWith() БЕЗ error сохраняет старый error', () {
        final original = buildDocument(error: 'Что-то упало');

        final copy = original.copyWith();

        expect(copy.error, 'Что-то упало');
      });

      test('copyWith(error: "новое") устанавливает error', () {
        final original = buildDocument();
        final copy = original.copyWith(error: 'новое');

        expect(copy.error, 'новое');
      });

      test('copyWith(duplicateOf: null) СБРАСЫВАЕТ duplicateOf', () {
        final original = buildDocument(duplicateOf: 'original-id');

        final copy = original.copyWith(duplicateOf: null);

        expect(copy.duplicateOf, isNull);
        expect(copy.isDuplicate, isFalse);
      });

      test('copyWith() БЕЗ duplicateOf сохраняет старый', () {
        final original = buildDocument(duplicateOf: 'original-id');

        final copy = original.copyWith();

        expect(copy.duplicateOf, 'original-id');
      });
    });
  });
}
