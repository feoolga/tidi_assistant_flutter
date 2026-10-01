// test/data/mappers/rag_document_mapper_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/data/mappers/rag_document_mapper.dart';
import 'package:tidi_assistant_flutter/data/models/rag_document_dto.dart';
import 'package:tidi_assistant_flutter/domain/models/rag_document_status.dart';

void main() {
  group('RagDocumentMapper.toDomain', () {
    // Хелпер — создаёт DTO с разумными дефолтами.
    RagDocumentDto buildDto({
      String id = 'doc-1',
      String filename = 'a.pdf',
      String status = 'pending',
      int? sizeBytes,
      DateTime? createdAt,
      int? chunksCount,
      String? error,
      String? duplicateOf,
    }) {
      return RagDocumentDto(
        id: id,
        filename: filename,
        status: status,
        sizeBytes: sizeBytes,
        createdAt: createdAt,
        chunksCount: chunksCount,
        error: error,
        duplicateOf: duplicateOf,
      );
    }

    // ============================================================
    // HAPPY PATH
    // ============================================================

    group('happy path', () {
      test('маппит все поля корректно', () {
        final created = DateTime(2026, 1, 15, 10, 30);
        final dto = buildDto(
          id: 'doc-42',
          filename: 'file.pdf',
          status: 'success',
          sizeBytes: 1024,
          createdAt: created,
          chunksCount: 10,
        );

        final doc = RagDocumentMapper.toDomain(dto);

        expect(doc.id, 'doc-42');
        expect(doc.filename, 'file.pdf');
        expect(doc.status, RagDocumentStatus.success);
        expect(doc.sizeBytes, 1024);
        expect(doc.createdAt, created);
        expect(doc.chunksCount, 10);
        expect(doc.error, isNull);
        expect(doc.duplicateOf, isNull);
      });

      test('пробрасывает error и duplicateOf', () {
        final dto = buildDto(
          status: 'failed',
          error: 'Ошибка парсинга',
          duplicateOf: 'original-id',
        );

        final doc = RagDocumentMapper.toDomain(dto);

        expect(doc.error, 'Ошибка парсинга');
        expect(doc.duplicateOf, 'original-id');
        expect(doc.isDuplicate, isTrue);
      });
    });

    // ============================================================
    // ПАРСИНГ STATUS
    // ============================================================

    group('парсинг status', () {
      test('"pending" → pending', () {
        final doc = RagDocumentMapper.toDomain(buildDto(status: 'pending'));
        expect(doc.status, RagDocumentStatus.pending);
      });

      test('"processing" → processing', () {
        final doc = RagDocumentMapper.toDomain(buildDto(status: 'processing'));
        expect(doc.status, RagDocumentStatus.processing);
      });

      test('"success" → success', () {
        final doc = RagDocumentMapper.toDomain(buildDto(status: 'success'));
        expect(doc.status, RagDocumentStatus.success);
      });

      test('"failed" → failed', () {
        final doc = RagDocumentMapper.toDomain(buildDto(status: 'failed'));
        expect(doc.status, RagDocumentStatus.failed);
      });

      test('незнакомый статус → ArgumentError', () {
        // Если бэкенд добавит новый статус — мы ХОТИМ упасть.
        // Молчаливое искажение хуже явного падения.
        expect(
          () => RagDocumentMapper.toDomain(buildDto(status: 'paused')),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('пустой статус → ArgumentError', () {
        expect(
          () => RagDocumentMapper.toDomain(buildDto(status: '')),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('статус с неправильным регистром → ArgumentError', () {
        // Бэкенд всегда шлёт lower-case. Если пришёл UPPER —
        // это баг контракта, и мы хотим об этом знать.
        expect(
          () => RagDocumentMapper.toDomain(buildDto(status: 'SUCCESS')),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    // ============================================================
    // FALLBACK — sizeBytes
    // ============================================================

    group('fallback sizeBytes', () {
      test('null → 0', () {
        final dto = buildDto(sizeBytes: null);
        final doc = RagDocumentMapper.toDomain(dto);

        expect(doc.sizeBytes, 0);
      });

      test('явный 0 сохраняется как 0', () {
        final dto = buildDto(sizeBytes: 0);
        final doc = RagDocumentMapper.toDomain(dto);

        expect(doc.sizeBytes, 0);
      });

      test('обычное значение сохраняется', () {
        final dto = buildDto(sizeBytes: 2048);
        final doc = RagDocumentMapper.toDomain(dto);

        expect(doc.sizeBytes, 2048);
      });
    });

    // ============================================================
    // FALLBACK — createdAt
    // ============================================================

    group('fallback createdAt', () {
      test('null → Unix epoch (1970-01-01 UTC)', () {
        final dto = buildDto(createdAt: null);
        final doc = RagDocumentMapper.toDomain(dto);

        expect(doc.createdAt, DateTime.utc(1970, 1, 1));
        // Проверяем, что это именно эпоха.
        expect(doc.createdAt.year, 1970);
        expect(doc.createdAt.month, 1);
        expect(doc.createdAt.day, 1);
      });

      test('обычная дата сохраняется', () {
        final created = DateTime(2026, 5, 15);
        final dto = buildDto(createdAt: created);
        final doc = RagDocumentMapper.toDomain(dto);

        expect(doc.createdAt, created);
      });
    });

    // ============================================================
    // FALLBACK — chunksCount
    // ============================================================

    group('fallback chunksCount', () {
      test('null → 0', () {
        final dto = buildDto(chunksCount: null);
        final doc = RagDocumentMapper.toDomain(dto);

        expect(doc.chunksCount, 0);
      });

      test('явный 0 сохраняется как 0', () {
        final dto = buildDto(chunksCount: 0);
        final doc = RagDocumentMapper.toDomain(dto);

        expect(doc.chunksCount, 0);
      });

      test('обычное значение сохраняется', () {
        final dto = buildDto(chunksCount: 42);
        final doc = RagDocumentMapper.toDomain(dto);

        expect(doc.chunksCount, 42);
      });
    });
  });
}
