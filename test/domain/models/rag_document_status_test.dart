// test/domain/models/rag_document_status_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/domain/models/rag_document_status.dart';

void main() {
  group('RagDocumentStatus', () {
    group('состав', () {
      test('содержит ровно 4 значения', () {
        expect(RagDocumentStatus.values.length, 4);
      });

      test('содержит ровно ожидаемые значения', () {
        // `unorderedEquals` — проверяет РОВНО этот набор,
        // порядок не важен.
        expect(
          RagDocumentStatus.values,
          unorderedEquals([
            RagDocumentStatus.pending,
            RagDocumentStatus.processing,
            RagDocumentStatus.success,
            RagDocumentStatus.failed,
          ]),
        );
      });

      test('значения уникальны', () {
        final unique = RagDocumentStatus.values.toSet();
        expect(unique.length, RagDocumentStatus.values.length);
      });
    });

    group('name', () {
      test('имена совпадают с ожидаемыми строками', () {
        // Эти имена парсит маппер (D2) из JSON от бэкенда:
        // "pending" → RagDocumentStatus.pending.
        expect(RagDocumentStatus.pending.name, 'pending');
        expect(RagDocumentStatus.processing.name, 'processing');
        expect(RagDocumentStatus.success.name, 'success');
        expect(RagDocumentStatus.failed.name, 'failed');
      });
    });
  });
}
