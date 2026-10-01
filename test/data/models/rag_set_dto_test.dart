// test/data/models/rag_set_dto_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/data/models/rag_set_dto.dart';

void main() {
  group('RagSetDto.fromJson', () {
    // ============================================================
    // HAPPY PATH
    // ============================================================

    test('парсит полный JSON', () {
      final json = <String, dynamic>{
        'id': 'rag-1',
        'name': 'Регламенты',
        'description': 'Описание набора',
        'status': 'ready',
        'documents': {'total': 5, 'ready': 3, 'failed': 1, 'pending': 1},
        'chunks_total': 152,
        'has_pending': true,
        'has_icon': true,
        'config': {
          'prompt': 'Отвечай кратко',
          'temperature': 0.5,
          'top_k': 7,
          'score_threshold': 0.6,
        },
        'created_at': '2026-01-15T10:30:00',
        'updated_at': '2026-01-20T15:45:00',
      };

      final dto = RagSetDto.fromJson(json);

      expect(dto.id, 'rag-1');
      expect(dto.name, 'Регламенты');
      expect(dto.description, 'Описание набора');
      expect(dto.status, 'ready');
      expect(dto.documents, isNotNull);
      expect(dto.documents!.total, 5);
      expect(dto.documents!.ready, 3);
      expect(dto.chunksTotal, 152);
      expect(dto.hasPending, isTrue);
      expect(dto.hasIcon, isTrue);
      expect(dto.config, isNotNull);
      expect(dto.config!.temperature, 0.5);
      expect(dto.config!.topK, 7);
      expect(dto.createdAt, DateTime(2026, 1, 15, 10, 30));
      expect(dto.updatedAt, DateTime(2026, 1, 20, 15, 45));
    });

    // ============================================================
    // МИНИМАЛЬНЫЙ JSON
    // ============================================================

    test('парсит минимальный JSON (только id и name)', () {
      final json = <String, dynamic>{'id': 'rag-min', 'name': 'Минимальный'};

      final dto = RagSetDto.fromJson(json);

      expect(dto.id, 'rag-min');
      expect(dto.name, 'Минимальный');
      expect(dto.description, isNull);
      expect(dto.status, isNull);
      expect(dto.documents, isNull);
      expect(dto.chunksTotal, isNull);
      expect(dto.hasPending, isFalse); // дефолт
      expect(dto.hasIcon, isFalse); // дефолт
      expect(dto.config, isNull);
      expect(dto.createdAt, isNull);
      expect(dto.updatedAt, isNull);
    });

    // ============================================================
    // ОБЯЗАТЕЛЬНЫЕ ПОЛЯ — ПАДАЕМ
    // ============================================================

    test('нет id → TypeError', () {
      final json = <String, dynamic>{'name': 'Без ID'};

      expect(() => RagSetDto.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('нет name → TypeError', () {
      final json = <String, dynamic>{'id': 'rag-1'};

      expect(() => RagSetDto.fromJson(json), throwsA(isA<TypeError>()));
    });

    // ============================================================
    // ВЛОЖЕННЫЕ ОБЪЕКТЫ
    // ============================================================

    test('documents отсутствует → null', () {
      final json = <String, dynamic>{'id': 'rag-1', 'name': 'Набор'};

      final dto = RagSetDto.fromJson(json);

      expect(dto.documents, isNull);
    });

    test('documents не объект → null (не падаем)', () {
      final json = <String, dynamic>{
        'id': 'rag-1',
        'name': 'Набор',
        'documents': 'не объект',
      };

      final dto = RagSetDto.fromJson(json);

      expect(dto.documents, isNull);
    });

    test('config отсутствует → null', () {
      final json = <String, dynamic>{'id': 'rag-1', 'name': 'Набор'};

      final dto = RagSetDto.fromJson(json);

      expect(dto.config, isNull);
    });

    test('config не объект → null (не падаем)', () {
      final json = <String, dynamic>{
        'id': 'rag-1',
        'name': 'Набор',
        'config': 42,
      };

      final dto = RagSetDto.fromJson(json);

      expect(dto.config, isNull);
    });

    // ============================================================
    // ДЕФОЛТЫ ДЛЯ BOOL
    // ============================================================

    test('has_pending отсутствует → false', () {
      final json = <String, dynamic>{'id': 'rag-1', 'name': 'Набор'};

      final dto = RagSetDto.fromJson(json);

      expect(dto.hasPending, isFalse);
    });

    test('has_icon отсутствует → false', () {
      final json = <String, dynamic>{'id': 'rag-1', 'name': 'Набор'};

      final dto = RagSetDto.fromJson(json);

      expect(dto.hasIcon, isFalse);
    });

    test('has_pending = true парсится', () {
      final json = <String, dynamic>{
        'id': 'rag-1',
        'name': 'Набор',
        'has_pending': true,
      };

      final dto = RagSetDto.fromJson(json);

      expect(dto.hasPending, isTrue);
    });

    // ============================================================
    // ДАТЫ
    // ============================================================

    test('created_at невалидный → null (не падаем)', () {
      final json = <String, dynamic>{
        'id': 'rag-1',
        'name': 'Набор',
        'created_at': 'вчера',
      };

      final dto = RagSetDto.fromJson(json);

      expect(dto.createdAt, isNull);
    });

    test('updated_at отсутствует → null', () {
      final json = <String, dynamic>{'id': 'rag-1', 'name': 'Набор'};

      final dto = RagSetDto.fromJson(json);

      expect(dto.updatedAt, isNull);
    });

    // ============================================================
    // STATUS
    // ============================================================

    test('status = "ready" парсится строкой', () {
      final json = <String, dynamic>{
        'id': 'rag-1',
        'name': 'Набор',
        'status': 'ready',
      };

      final dto = RagSetDto.fromJson(json);

      expect(dto.status, 'ready');
    });

    test('status отсутствует → null (не падаем)', () {
      final json = <String, dynamic>{'id': 'rag-1', 'name': 'Набор'};

      final dto = RagSetDto.fromJson(json);

      expect(dto.status, isNull);
    });

    // ============================================================
    // CHUNKS_TOTAL
    // ============================================================

    test('chunks_total = 0 парсится как 0, не как null', () {
      final json = <String, dynamic>{
        'id': 'rag-1',
        'name': 'Набор',
        'chunks_total': 0,
      };

      final dto = RagSetDto.fromJson(json);

      expect(dto.chunksTotal, 0);
    });

    test('chunks_total отсутствует → null', () {
      final json = <String, dynamic>{'id': 'rag-1', 'name': 'Набор'};

      final dto = RagSetDto.fromJson(json);

      expect(dto.chunksTotal, isNull);
    });
  });
}
