// test/data/models/rag_document_dto_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/data/models/rag_document_dto.dart';

void main() {
  group('RagDocumentDto.fromJson', () {
    // ============================================================
    // HAPPY PATH — ПОЛНЫЙ JSON
    // ============================================================

    group('полный JSON', () {
      test('парсит все поля', () {
        final json = <String, dynamic>{
          'id': 'doc-1',
          'filename': 'a.pdf',
          'status': 'success',
          'size_bytes': 1024,
          'created_at': '2026-01-15T10:30:00',
          'chunks_count': 42,
          'error': null,
          'duplicate_of': null,
        };

        final dto = RagDocumentDto.fromJson(json);

        expect(dto.id, 'doc-1');
        expect(dto.filename, 'a.pdf');
        expect(dto.status, 'success');
        expect(dto.sizeBytes, 1024);
        expect(dto.createdAt, DateTime(2026, 1, 15, 10, 30));
        expect(dto.chunksCount, 42);
        expect(dto.error, isNull);
        expect(dto.duplicateOf, isNull);
      });

      test('парсит с error (failed)', () {
        final json = <String, dynamic>{
          'id': 'doc-2',
          'filename': 'broken.pdf',
          'status': 'failed',
          'size_bytes': 2048,
          'created_at': '2026-01-15T10:30:00',
          'chunks_count': 0,
          'error': 'Ошибка парсинга PDF',
          'duplicate_of': null,
        };

        final dto = RagDocumentDto.fromJson(json);

        expect(dto.status, 'failed');
        expect(dto.error, 'Ошибка парсинга PDF');
      });

      test('парсит с duplicate_of', () {
        final json = <String, dynamic>{
          'id': 'doc-3',
          'filename': 'copy.pdf',
          'status': 'success',
          'size_bytes': 512,
          'created_at': '2026-01-15T10:30:00',
          'chunks_count': 10,
          'error': null,
          'duplicate_of': 'original-doc-id',
        };

        final dto = RagDocumentDto.fromJson(json);

        expect(dto.duplicateOf, 'original-doc-id');
      });
    });

    // ============================================================
    // МИНИМАЛЬНЫЙ JSON — ТОЛЬКО ОБЯЗАТЕЛЬНЫЕ
    // ============================================================

    group('минимальный JSON', () {
      test('парсит только обязательные поля', () {
        final json = <String, dynamic>{
          'id': 'doc-min',
          'filename': 'minimal.txt',
          'status': 'pending',
        };

        final dto = RagDocumentDto.fromJson(json);

        expect(dto.id, 'doc-min');
        expect(dto.filename, 'minimal.txt');
        expect(dto.status, 'pending');
        expect(dto.sizeBytes, isNull);
        expect(dto.createdAt, isNull);
        expect(dto.chunksCount, isNull);
        expect(dto.error, isNull);
        expect(dto.duplicateOf, isNull);
      });

      test('chunks_count == 0 распознаётся как 0, не null', () {
        final json = <String, dynamic>{
          'id': 'doc-0',
          'filename': 'zero.txt',
          'status': 'pending',
          'chunks_count': 0,
        };

        final dto = RagDocumentDto.fromJson(json);

        expect(dto.chunksCount, 0);
      });
    });

    // ============================================================
    // ОБЯЗАТЕЛЬНЫЕ ПОЛЯ — ПАДАЕМ
    // ============================================================

    group('обязательные поля отсутствуют', () {
      test('нет id → TypeError', () {
        final json = <String, dynamic>{
          'filename': 'a.pdf',
          'status': 'pending',
        };

        expect(() => RagDocumentDto.fromJson(json), throwsA(isA<TypeError>()));
      });

      test('нет filename → TypeError', () {
        final json = <String, dynamic>{'id': 'doc-1', 'status': 'pending'};

        expect(() => RagDocumentDto.fromJson(json), throwsA(isA<TypeError>()));
      });

      test('нет status → TypeError', () {
        final json = <String, dynamic>{'id': 'doc-1', 'filename': 'a.pdf'};

        expect(() => RagDocumentDto.fromJson(json), throwsA(isA<TypeError>()));
      });

      test('id не строка → TypeError', () {
        final json = <String, dynamic>{
          'id': 42,
          'filename': 'a.pdf',
          'status': 'pending',
        };

        expect(() => RagDocumentDto.fromJson(json), throwsA(isA<TypeError>()));
      });
    });

    // ============================================================
    // ДАТЫ — УСТОЙЧИВЫЙ ПАРСИНГ
    // ============================================================

    group('created_at — устойчивый парсинг', () {
      test('валидная ISO-8601', () {
        final json = <String, dynamic>{
          'id': 'doc-1',
          'filename': 'a.pdf',
          'status': 'pending',
          'created_at': '2026-03-20T15:45:30',
        };

        final dto = RagDocumentDto.fromJson(json);

        expect(dto.createdAt, DateTime(2026, 3, 20, 15, 45, 30));
      });

      test('пустая строка → null', () {
        final json = <String, dynamic>{
          'id': 'doc-1',
          'filename': 'a.pdf',
          'status': 'pending',
          'created_at': '',
        };

        final dto = RagDocumentDto.fromJson(json);

        expect(dto.createdAt, isNull);
      });

      test('невалидная строка → null (не падаем)', () {
        final json = <String, dynamic>{
          'id': 'doc-1',
          'filename': 'a.pdf',
          'status': 'pending',
          'created_at': 'вчера вечером',
        };

        final dto = RagDocumentDto.fromJson(json);

        expect(dto.createdAt, isNull);
      });

      test('число вместо строки → null', () {
        final json = <String, dynamic>{
          'id': 'doc-1',
          'filename': 'a.pdf',
          'status': 'pending',
          'created_at': 1735900000,
        };

        final dto = RagDocumentDto.fromJson(json);

        expect(dto.createdAt, isNull);
      });

      test('null → null', () {
        final json = <String, dynamic>{
          'id': 'doc-1',
          'filename': 'a.pdf',
          'status': 'pending',
          'created_at': null,
        };

        final dto = RagDocumentDto.fromJson(json);

        expect(dto.createdAt, isNull);
      });
    });
  });
}
